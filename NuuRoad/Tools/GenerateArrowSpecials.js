// Generates Art/ArrowSpecials.tga: the icons the arrow window shows instead of
// the arrow when pointing somewhere is not the useful answer.
//
// The established guide addons all swap the arrow out rather than leave it
// spinning, and they animate the swap, which is what makes "you are here" read
// instantly. We carry the three states NuuRoad can actually detect; the rest
// of Zygor's set (boat, pathfinding wait, stairs, instance preview) has no
// signal behind it here. See Domain/Navigation.lua.
//
// Icons are drawn white so the tracker can tint them, with the same dark
// outline the arrow carries so they stay readable over bright terrain.
// Run from the addon root: node Tools/GenerateArrowSpecials.js
const fs = require("fs");
const { Image } = require("./Tga.js");

const CELL = 64, COLUMNS = 4, SS = 4;
const SHEET_W = CELL * COLUMNS, SHEET_H = CELL;
const OUTLINE = 5;                       // Supersampled, so about 1.2 pixels.
const OUTLINE_COLOR = [0.05, 0.08, 0.10];

function polygon(points) {
    return (x, y) => {
        let inside = false;
        for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
            const a = points[i], b = points[j];
            if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
        }
        return inside;
    };
}

function disc(cx, cy, r) {
    return (x, y) => (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

// A rounded thick line, for the slash through the unreachable ring.
function bar(x1, y1, x2, y2, width) {
    const dx = x2 - x1, dy = y2 - y1, lengthSquared = dx * dx + dy * dy;
    return (x, y) => {
        const t = Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / lengthSquared));
        return Math.hypot(x - x1 - t * dx, y - y1 - t * dy) <= width / 2;
    };
}

// Each icon is a list of parts, and a part is a union of shapes with holes cut
// out of it. Keeping the parts separate is what lets the slash lie across the
// barred ring instead of being cut away with the ring's centre.
// A pin, the shape every map in the game uses for "this spot".
const here = [
    { add: [polygon([[32, 60], [19, 38], [45, 38]]), disc(32, 26, 17)], subtract: [disc(32, 26, 6.5)] },
];
// A swept wing: the tracker already marks flight steps, and this is the same
// idea at arrow size.
const taxi = [
    {
        add: [polygon([
            [32, 4], [40, 26], [58, 42], [58, 48], [36, 40],
            [36, 50], [42, 56], [42, 60], [32, 56], [22, 60], [22, 56],
            [28, 50], [28, 40], [6, 48], [6, 42], [24, 26],
        ])],
        subtract: [],
    },
];
// A barred ring: there is a destination, but no line to it from here.
const unreachable = [
    { add: [disc(32, 32, 22)], subtract: [disc(32, 32, 15.5)] },
    { add: [bar(17, 17, 47, 47, 8)], subtract: [] },
];
// Cell order, which Domain/Navigation.lua indexes by name.
const ICONS = [here, taxi, unreachable];

const sheet = new Image(SHEET_W, SHEET_H);
const samples = CELL * SS;

for (let cell = 0; cell < ICONS.length; cell++) {
    const icon = ICONS[cell];
    const covered = new Uint8Array(samples * samples);
    for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
            const x = (sx + 0.5) / SS, y = (sy + 0.5) / SS;
            const inside = icon.some((part) => part.add.some((shape) => shape(x, y))
                && !part.subtract.some((shape) => shape(x, y)));
            covered[sy * samples + sx] = inside ? 1 : 0;
        }
    }
    // Same separable dilation as the arrow sheet, for the outline.
    const scratch = new Uint8Array(samples * samples), dilated = new Uint8Array(samples * samples);
    for (let y = 0; y < samples; y++) for (let x = 0; x < samples; x++) {
        let hit = 0;
        for (let d = -OUTLINE; d <= OUTLINE && !hit; d++) {
            const sx = x + d;
            if (sx >= 0 && sx < samples && covered[y * samples + sx]) hit = 1;
        }
        scratch[y * samples + x] = hit;
    }
    for (let y = 0; y < samples; y++) for (let x = 0; x < samples; x++) {
        let hit = 0;
        for (let d = -OUTLINE; d <= OUTLINE && !hit; d++) {
            const sy = y + d;
            if (sy >= 0 && sy < samples && scratch[sy * samples + x]) hit = 1;
        }
        dilated[y * samples + x] = hit;
    }
    for (let y = 0; y < CELL; y++) {
        for (let x = 0; x < CELL; x++) {
            let red = 0, green = 0, blue = 0, alpha = 0;
            for (let sy = 0; sy < SS; sy++) {
                for (let sx = 0; sx < SS; sx++) {
                    const index = (y * SS + sy) * samples + (x * SS + sx);
                    if (covered[index]) { red += 1; green += 1; blue += 1; alpha += 1; }
                    else if (dilated[index]) {
                        red += OUTLINE_COLOR[0]; green += OUTLINE_COLOR[1]; blue += OUTLINE_COLOR[2]; alpha += 1;
                    }
                }
            }
            const byte = (value) => Math.max(0, Math.min(255, Math.round(value * 255)));
            const scale = alpha > 0 ? 1 / alpha : 0;
            sheet.set(cell * CELL + x, y, byte(red * scale), byte(green * scale), byte(blue * scale), byte(alpha / (SS * SS)));
        }
    }
}

fs.mkdirSync("Art", { recursive: true });
fs.writeFileSync("Art/ArrowSpecials.tga", sheet.toTGA());
console.log(`Wrote Art/ArrowSpecials.tga: ${ICONS.length} icons of ${CELL}x${CELL} on ${SHEET_W}x${SHEET_H}.`);
