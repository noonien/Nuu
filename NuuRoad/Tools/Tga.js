// Minimal 32-bit TGA writer shared by the art generators.
//
// Run-length encoding (image type 10) is the default: the sprite sheets are
// mostly transparent padding, which collapses to almost nothing, and the
// reference guide addons ship their sheets the same way, so the client is
// known to read the format. Pass `false` for an uncompressed file (type 2).
class Image {
    constructor(width, height) {
        this.width = width;
        this.height = height;
        this.pixels = Buffer.alloc(width * height * 4); // RGBA, row-major.
    }

    set(x, y, r, g, b, a) {
        const offset = (y * this.width + x) * 4;
        this.pixels[offset] = r;
        this.pixels[offset + 1] = g;
        this.pixels[offset + 2] = b;
        this.pixels[offset + 3] = a;
    }

    // TGA stores blue first; the descriptor byte marks 8 alpha bits and a
    // top-left origin, which is the order we fill rows in.
    bgra(index) {
        const offset = index * 4;
        return [this.pixels[offset + 2], this.pixels[offset + 1], this.pixels[offset], this.pixels[offset + 3]];
    }

    toTGA(compress = true) {
        const header = Buffer.alloc(18);
        header[2] = compress ? 10 : 2;
        header.writeUInt16LE(this.width, 12);
        header.writeUInt16LE(this.height, 14);
        header[16] = 32;
        header[17] = 0x28;
        if (!compress) {
            const body = Buffer.alloc(this.width * this.height * 4);
            for (let index = 0; index < this.width * this.height; index++) {
                const [b, g, r, a] = this.bgra(index);
                body[index * 4] = b; body[index * 4 + 1] = g; body[index * 4 + 2] = r; body[index * 4 + 3] = a;
            }
            return Buffer.concat([header, body]);
        }
        const chunks = [header];
        const same = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2] && a[3] === b[3];
        // Packets never cross a scanline, which is what the format requires and
        // what every loader assumes.
        for (let y = 0; y < this.height; y++) {
            let x = 0;
            while (x < this.width) {
                const start = y * this.width + x;
                const first = this.bgra(start);
                let run = 1;
                while (run < 128 && x + run < this.width && same(this.bgra(start + run), first)) run++;
                if (run >= 2) {
                    chunks.push(Buffer.from([0x80 | (run - 1), first[0], first[1], first[2], first[3]]));
                    x += run;
                    continue;
                }
                // A raw packet runs until two neighbours match, since a run
                // packet is cheaper from there on.
                let raw = 1;
                while (raw < 128 && x + raw + 1 < this.width
                    && !same(this.bgra(start + raw), this.bgra(start + raw + 1))) raw++;
                if (x + raw + 1 >= this.width) raw = Math.min(128, this.width - x);
                const packet = Buffer.alloc(1 + raw * 4);
                packet[0] = raw - 1;
                for (let index = 0; index < raw; index++) {
                    const [b, g, r, a] = this.bgra(start + index);
                    packet[1 + index * 4] = b; packet[2 + index * 4] = g;
                    packet[3 + index * 4] = r; packet[4 + index * 4] = a;
                }
                chunks.push(packet);
                x += raw;
            }
        }
        return Buffer.concat(chunks);
    }
}

module.exports = { Image };
