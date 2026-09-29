// Generates the single source texture for the runtime-rotated waypoint arrow.
// Run from the addon root: node Tools/GenerateWaypointArrow.js
const fs = require("fs");

const size = 256;
const image = Buffer.alloc(18 + size * size * 4);
image[2] = 2;
image.writeUInt16LE(size, 12);
image.writeUInt16LE(size, 14);
image[16] = 32;
image[17] = 0x28;

function contains(points, x, y) {
    let inside = false;
    for (let current = 0, previous = points.length - 1; current < points.length; previous = current++) {
        const a = points[current], b = points[previous];
        if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
    }
    return inside;
}

function distanceToEdge(points, x, y) {
    let best = Infinity;
    for (let current = 0, previous = points.length - 1; current < points.length; previous = current++) {
        const a = points[current], b = points[previous];
        const dx = b[0] - a[0], dy = b[1] - a[1];
        const t = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)));
        best = Math.min(best, Math.hypot(x - a[0] - t * dx, y - a[1] - t * dy));
    }
    return best;
}

// Paints the polygon; `expand` grows it outward by that many texture pixels.
function paint(points, color, expand = 0) {
    for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
            let covered = 0;
            for (const sample of [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]) {
                const sx = x + sample[0], sy = y + sample[1];
                if (contains(points, sx, sy) || (expand > 0 && distanceToEdge(points, sx, sy) <= expand)) covered++;
            }
            if (covered === 0) continue;
            const offset = 18 + (y * size + x) * 4;
            const alpha = Math.floor(color[3] * covered / 4);
            image[offset] = color[2];
            image[offset + 1] = color[1];
            image[offset + 2] = color[0];
            image[offset + 3] = alpha;
        }
    }
}

// Thin outline (about two screen pixels at the 52px display size), teal body,
// and a small gold chevron: intentionally simple at UI scale.
const body = [[128, 25], [225, 136], [169, 136], [169, 218], [87, 218], [87, 136], [31, 136]];
const outlineWidth = 10; // 2 * (256 texture px / 52 screen px), rounded
paint(body, [14, 22, 28, 255], outlineWidth);
paint(body, [25, 143, 158, 255]);
paint([[128, 42], [199, 122], [151, 122], [151, 196], [105, 196], [105, 122], [57, 122]], [52, 190, 201, 255]);
paint([[128, 54], [176, 108], [145, 108], [128, 89], [111, 108], [80, 108]], [244, 194, 62, 255]);

fs.mkdirSync("Art", { recursive: true });
fs.writeFileSync("Art/WaypointArrow.tga", image);
console.log("Wrote Art/WaypointArrow.tga as a 256x256 32-bit RGBA TGA.");
