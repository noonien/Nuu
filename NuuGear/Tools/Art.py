"""Makes NuuGear's art: Art/UpgradeArrow.tga, the upgrade arrow on item icons.

Run from anywhere:
    python3 NuuGear/Tools/Art.py

Procedural and our own. A green arrow pointing up with a dark edge, so it
reads over any icon; drawn 4x4 supersampled for soft edges. TGA is written
as the kit's Tools/Textures.py writes it: 32-bit, uncompressed, bottom-left
origin.
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "Art")
SIZE = 32
SAMPLES = 4

FILL = (64, 220, 64)
EDGE = (0, 40, 0)


def inside_arrow(x, y, grow):
    """Whether (x, y), in 0-1 with y down, is in the arrow grown by `grow`."""
    # The head: a triangle from the tip (0.5, 0.07) to the base at y = 0.52.
    tip, base, half = 0.07 - grow, 0.52 + grow, 0.40 + grow
    if tip <= y <= base:
        width = half * (y - tip) / (base - tip)
        if abs(x - 0.5) <= width:
            return True
    # The shaft below it.
    return 0.5 - 0.16 - grow <= x <= 0.5 + 0.16 + grow and 0.5 <= y <= 0.92 + grow


def pixel(px, py):
    fill = edge = 0
    for sy in range(SAMPLES):
        for sx in range(SAMPLES):
            x = (px + (sx + 0.5) / SAMPLES) / SIZE
            y = (py + (sy + 0.5) / SAMPLES) / SIZE
            if inside_arrow(x, y, 0):
                fill += 1
            elif inside_arrow(x, y, 0.06):
                edge += 1
    total = SAMPLES * SAMPLES
    alpha = (fill + edge) / total
    if fill + edge == 0:
        return (0, 0, 0, 0)
    mix = fill / (fill + edge)
    rgb = tuple(round(EDGE[i] + (FILL[i] - EDGE[i]) * mix) for i in range(3))
    # A lighter top half, so it reads as lit from above.
    if py < SIZE // 2 and mix > 0.5:
        rgb = tuple(min(255, c + 30) for c in rgb)
    return rgb + (round(alpha * 255),)


def write_tga(path, rows):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        for row in reversed(rows):
            for r, g, b, a in row:
                f.write(bytes((b, g, r, a)))


def main():
    os.makedirs(ART, exist_ok=True)
    rows = [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]
    path = os.path.join(ART, "UpgradeArrow.tga")
    write_tga(path, rows)
    print("wrote", path)


if __name__ == "__main__":
    main()
