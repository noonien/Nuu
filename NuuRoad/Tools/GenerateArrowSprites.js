// Generates the waypoint arrow sprite sheets: a pre-rendered turn of a lit 3D
// arrow, plus a matching specular pass. The tracker never rotates a texture;
// it picks the frame for the current heading, which is what makes the arrow
// read as a solid object catching the light instead of a flat shape spun in
// the screen plane.
//
// The sheet covers a half turn only. The arrow and the light are both
// symmetric about the arrow's long axis, so the frame for -angle is the frame
// for +angle with the texture mirrored, and the runtime flips the U
// coordinates instead. That buys ~1.2 degrees per frame out of 150 cells.
//
// Run from the addon root: node Tools/GenerateArrowSprites.js
const fs = require("fs");
const { Image } = require("./Tga.js");

// ---------------------------------------------------------------- settings

const SHEET = 1024;              // Texture dimensions must be powers of two.
const SPRITE_W = 102, SPRITE_H = 68;
const COLUMNS = Math.floor(SHEET / SPRITE_W);   // 10
const ROWS = Math.floor(SHEET / SPRITE_H);      // 15
const FRAMES = COLUMNS * ROWS;                  // 150, covering 0..180 degrees
const SS = 3;                    // Supersampling factor, box-filtered down.

const ELEVATION = 40 * Math.PI / 180; // Camera height above the arrow's plane.
const AMBIENT = 0.30;
const SPEC_POWER = 20, SPEC_STRENGTH = 0.85;
const OUTLINE = 4;               // Supersampled pixels, so ~1.3 final pixels.
const OUTLINE_COLOR = [0.05, 0.08, 0.10];

// Arrow solid, in sprite pixels, pointing +Y with +Z up. The silhouette keeps
// the proportions of Art/WaypointArrow.tga so the two read as the same arrow.
const TIP_Y = 44, BARB_Y = -6.6, TAIL_Y = -44;
const BARB_X = 44.2, SHAFT_X = 18.7;
const THICKNESS = 7, WALL_TOP = 3.5, BEVEL = 6;
const CROWN = 2.5, CROWN_SPAN = 30; // Shallow ridge along the arrow's axis.

// Counter-clockwise, which makes each edge's left normal the inward one.
const OUTLINE_POLY = [
    [0, TIP_Y], [-BARB_X, BARB_Y], [-SHAFT_X, BARB_Y], [-SHAFT_X, TAIL_Y],
    [SHAFT_X, TAIL_Y], [SHAFT_X, BARB_Y], [BARB_X, BARB_Y],
];
// Same topology, so both rings triangulate with the same index lists.
const TOP_TRIS = [[0, 1, 2], [0, 2, 5], [0, 5, 6], [2, 3, 4], [2, 4, 5]];

// ------------------------------------------------------------------- mesh

function normalize(v) {
    const len = Math.hypot(v[0], v[1], v[2]) || 1;
    return [v[0] / len, v[1] / len, v[2] / len];
}

function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

// Miter offset of a counter-clockwise ring, inward by `d`.
function insetRing(points, d) {
    const count = points.length;
    return points.map((point, index) => {
        const previous = points[(index + count - 1) % count], next = points[(index + 1) % count];
        const inward = (a, b) => {
            const n = normalize([-(b[1] - a[1]), b[0] - a[0], 0]);
            return [n[0], n[1]];
        };
        const n1 = inward(previous, point), n2 = inward(point, next);
        const cosine = n1[0] * n2[0] + n1[1] * n2[1];
        const scale = d / Math.max(0.35, 1 + cosine); // Clamped miter.
        return [point[0] + (n1[0] + n2[0]) * scale, point[1] + (n1[1] + n2[1]) * scale];
    });
}

// The crowned top surface: height and its exact normal, so the sheen sweeps
// across the arrow as it turns rather than sitting on it as a fixed blob.
function crownHeight(x) {
    const t = Math.min(1, Math.abs(x) / CROWN_SPAN);
    return THICKNESS + CROWN * (1 - t * t);
}

function crownNormal(x) {
    if (Math.abs(x) >= CROWN_SPAN) return [0, 0, 1];
    return normalize([2 * CROWN * x / (CROWN_SPAN * CROWN_SPAN), 0, 1]);
}

const triangles = [];

function addTriangle(a, b, c, normalA, normalB, normalC) {
    triangles.push([
        { p: a, n: normalA }, { p: b, n: normalB }, { p: c, n: normalC },
    ]);
}

function flatTriangle(a, b, c) {
    const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    const v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const n = normalize([u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]);
    addTriangle(a, b, c, n, n, n);
}

const inner = insetRing(OUTLINE_POLY, BEVEL);

// Top: each face subdivided so the crown curves instead of creasing, with
// analytic normals interpolated across the triangle.
function subdivide(a, b, c, depth) {
    if (depth === 0) {
        const lift = (p) => [p[0], p[1], crownHeight(p[0])];
        addTriangle(lift(a), lift(b), lift(c), crownNormal(a[0]), crownNormal(b[0]), crownNormal(c[0]));
        return;
    }
    const mid = (p, q) => [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
    const ab = mid(a, b), bc = mid(b, c), ca = mid(c, a);
    subdivide(a, ab, ca, depth - 1);
    subdivide(ab, b, bc, depth - 1);
    subdivide(ca, bc, c, depth - 1);
    subdivide(ab, bc, ca, depth - 1);
}
for (const [i, j, k] of TOP_TRIS) subdivide(inner[i], inner[j], inner[k], 2);

// Bevel band and vertical walls.
for (let i = 0; i < OUTLINE_POLY.length; i++) {
    const j = (i + 1) % OUTLINE_POLY.length;
    const outerA = OUTLINE_POLY[i], outerB = OUTLINE_POLY[j];
    const innerA = inner[i], innerB = inner[j];
    const oaTop = [outerA[0], outerA[1], WALL_TOP], obTop = [outerB[0], outerB[1], WALL_TOP];
    const iaTop = [innerA[0], innerA[1], crownHeight(innerA[0])];
    const ibTop = [innerB[0], innerB[1], crownHeight(innerB[0])];
    flatTriangle(oaTop, obTop, ibTop);
    flatTriangle(oaTop, ibTop, iaTop);
    flatTriangle([outerA[0], outerA[1], 0], [outerB[0], outerB[1], 0], obTop);
    flatTriangle([outerA[0], outerA[1], 0], obTop, oaTop);
}

// ---------------------------------------------------------------- shading

// The light sits in the arrow's plane of symmetry; a light biased to one side
// would break the mirrored half of the turn.
const LIGHT = normalize([0, -0.42, 0.91]);
const VIEW = [0, -Math.cos(ELEVATION), Math.sin(ELEVATION)];
const HALF = normalize([LIGHT[0] + VIEW[0], LIGHT[1] + VIEW[1], LIGHT[2] + VIEW[2]]);

const WIDTH = SPRITE_W * SS, HEIGHT = SPRITE_H * SS;
const zbuffer = new Float32Array(WIDTH * HEIGHT);
const luminance = new Float32Array(WIDTH * HEIGHT);
const specular = new Float32Array(WIDTH * HEIGHT);
const covered = new Uint8Array(WIDTH * HEIGHT);
const dilated = new Uint8Array(WIDTH * HEIGHT);
const scratch = new Uint8Array(WIDTH * HEIGHT);

function project(p, sin, cos) {
    // Rotate about Z, then an orthographic camera looking down at ELEVATION.
    const x = p[0] * cos - p[1] * sin;
    const y = p[0] * sin + p[1] * cos;
    return {
        x: WIDTH / 2 + x * SS,
        y: HEIGHT / 2 - (y * Math.sin(ELEVATION) + p[2] * Math.cos(ELEVATION)) * SS,
        depth: y * Math.cos(ELEVATION) - p[2] * Math.sin(ELEVATION),
    };
}

function rotateNormal(n, sin, cos) {
    return [n[0] * cos - n[1] * sin, n[0] * sin + n[1] * cos, n[2]];
}

function renderFrame(degrees) {
    zbuffer.fill(Infinity);
    luminance.fill(0);
    specular.fill(0);
    covered.fill(0);
    const radians = degrees * Math.PI / 180;
    const sin = Math.sin(radians), cos = Math.cos(radians);

    for (const triangle of triangles) {
        const normals = triangle.map((v) => rotateNormal(v.n, sin, cos));
        const facing = normals.reduce((sum, n) => sum + dot(n, VIEW), 0);
        if (facing <= 0) continue; // Back faces never show; the solid is closed.
        const screen = triangle.map((v) => project(v.p, sin, cos));
        const [a, b, c] = screen;
        const area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
        if (Math.abs(area) < 1e-9) continue;
        const minX = Math.max(0, Math.floor(Math.min(a.x, b.x, c.x)));
        const maxX = Math.min(WIDTH - 1, Math.ceil(Math.max(a.x, b.x, c.x)));
        const minY = Math.max(0, Math.floor(Math.min(a.y, b.y, c.y)));
        const maxY = Math.min(HEIGHT - 1, Math.ceil(Math.max(a.y, b.y, c.y)));
        for (let py = minY; py <= maxY; py++) {
            for (let px = minX; px <= maxX; px++) {
                const sx = px + 0.5, sy = py + 0.5;
                let w0 = ((b.x - a.x) * (sy - a.y) - (sx - a.x) * (b.y - a.y)) / area;
                let w1 = ((sx - a.x) * (c.y - a.y) - (c.x - a.x) * (sy - a.y)) / area;
                const w2 = 1 - w0 - w1;
                // w0 weights c, w1 weights b, w2 weights a.
                if (w0 < 0 || w1 < 0 || w2 < 0) continue;
                const depth = a.depth * w2 + b.depth * w1 + c.depth * w0;
                const index = py * WIDTH + px;
                if (depth >= zbuffer[index]) continue;
                zbuffer[index] = depth;
                const n = normalize([
                    normals[0][0] * w2 + normals[1][0] * w1 + normals[2][0] * w0,
                    normals[0][1] * w2 + normals[1][1] * w1 + normals[2][1] * w0,
                    normals[0][2] * w2 + normals[1][2] * w1 + normals[2][2] * w0,
                ]);
                const diffuse = Math.max(0, dot(n, LIGHT));
                luminance[index] = AMBIENT + (1 - AMBIENT) * diffuse;
                specular[index] = Math.pow(Math.max(0, dot(n, HALF)), SPEC_POWER) * SPEC_STRENGTH;
                covered[index] = 1;
            }
        }
    }
}

// Separable box dilation of the silhouette, for the dark outline that keeps
// the arrow readable against bright terrain.
function dilateCoverage() {
    for (let y = 0; y < HEIGHT; y++) {
        for (let x = 0; x < WIDTH; x++) {
            let hit = 0;
            for (let d = -OUTLINE; d <= OUTLINE && !hit; d++) {
                const sx = x + d;
                if (sx >= 0 && sx < WIDTH && covered[y * WIDTH + sx]) hit = 1;
            }
            scratch[y * WIDTH + x] = hit;
        }
    }
    for (let y = 0; y < HEIGHT; y++) {
        for (let x = 0; x < WIDTH; x++) {
            let hit = 0;
            for (let d = -OUTLINE; d <= OUTLINE && !hit; d++) {
                const sy = y + d;
                if (sy >= 0 && sy < HEIGHT && scratch[sy * WIDTH + x]) hit = 1;
            }
            dilated[y * WIDTH + x] = hit;
        }
    }
}

// ------------------------------------------------------------------ output

const base = new Image(SHEET, SHEET), sheen = new Image(SHEET, SHEET);

const step = 180 / (FRAMES - 1);
for (let frame = 0; frame < FRAMES; frame++) {
    renderFrame(frame * step);
    dilateCoverage();
    const cellX = (frame % COLUMNS) * SPRITE_W, cellY = Math.floor(frame / COLUMNS) * SPRITE_H;
    for (let y = 0; y < SPRITE_H; y++) {
        for (let x = 0; x < SPRITE_W; x++) {
            let red = 0, green = 0, blue = 0, alpha = 0, sheenAlpha = 0;
            for (let sy = 0; sy < SS; sy++) {
                for (let sx = 0; sx < SS; sx++) {
                    const index = (y * SS + sy) * WIDTH + (x * SS + sx);
                    if (covered[index]) {
                        const value = Math.min(1, luminance[index]);
                        red += value; green += value; blue += value; alpha += 1;
                        sheenAlpha += specular[index];
                    } else if (dilated[index]) {
                        red += OUTLINE_COLOR[0]; green += OUTLINE_COLOR[1]; blue += OUTLINE_COLOR[2];
                        alpha += 1;
                    }
                }
            }
            const samples = SS * SS;
            const byte = (value) => Math.max(0, Math.min(255, Math.round(value * 255)));
            // Un-premultiply so filtering at display size does not darken edges.
            const scale = alpha > 0 ? 1 / alpha : 0;
            base.set(cellX + x, cellY + y, byte(red * scale), byte(green * scale), byte(blue * scale), byte(alpha / samples));
            sheen.set(cellX + x, cellY + y, 255, 255, 255, byte(sheenAlpha / samples));
        }
    }
}

fs.mkdirSync("Art", { recursive: true });
fs.writeFileSync("Art/ArrowSprites.tga", base.toTGA());
fs.writeFileSync("Art/ArrowSpritesSpecular.tga", sheen.toTGA());
console.log(`Wrote Art/ArrowSprites.tga and Art/ArrowSpritesSpecular.tga: ${FRAMES} frames of ${SPRITE_W}x${SPRITE_H} on ${SHEET}x${SHEET}, covering 0..180 degrees at ${step.toFixed(3)} degrees per frame.`);
