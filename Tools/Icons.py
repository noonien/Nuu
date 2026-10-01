"""Makes each addon's icon for the client's addon list: <Addon>/Icon.tga, named by `## IconTexture` in its TOC.

Run from anywhere:
    uv run --no-project --with pillow python Tools/Icons.py [--png]

Procedural and our own. One family: a dark rounded tile with a thin rim and a bold glyph, both in the addon's
colour, so the four read as a set and apart from each other at the list's small size. NuuRoad's is the kit's
default accent. Drawn at 8x and scaled down for soft edges; 64x64, a power of two. TGA is written as the kit's
Tools/Textures.py writes it: 32-bit, uncompressed, bottom-left origin. --png also writes Icon.png beside it for
looking at; it is not shipped.
"""
import math
import os
import struct
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 64
SCALE = 8
BIG = SIZE * SCALE
PNG = "--png" in sys.argv

TILE_TOP, TILE_BOTTOM = (34, 40, 50), (16, 19, 25)


def u(v):
    """A length in icon pixels, at the drawing scale."""
    return round(v * SCALE)


def pts(points):
    return [(u(x), u(y)) for x, y in points]


def tile(color):
    """The background: a vertical gradient in a rounded square, with a rim of the addon's colour."""
    gradient = Image.new("RGBA", (BIG, BIG))
    g = ImageDraw.Draw(gradient)
    for y in range(BIG):
        t = y / (BIG - 1)
        g.line([(0, y), (BIG, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TILE_TOP, TILE_BOTTOM)) + (255,))
    mask = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(mask).rounded_rectangle([u(2), u(2), u(62) - 1, u(62) - 1], radius=u(11), fill=255)
    out = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    out.paste(gradient, (0, 0), mask)
    rim = tuple(round(c * 0.75) for c in color) + (255,)
    ImageDraw.Draw(out).rounded_rectangle([u(2), u(2), u(62) - 1, u(62) - 1], radius=u(11), outline=rim, width=u(2))
    return out


def glyph_layer(draw_glyph, color):
    """The glyph in the addon's colour over a dark shadow a pixel down, so it stands off the tile."""
    mask = Image.new("L", (BIG, BIG), 0)
    draw_glyph(ImageDraw.Draw(mask))
    out = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 170))
    out.paste(shadow, (0, u(1.5)), mask)
    lit = Image.new("RGBA", (BIG, BIG), color + (255,))
    out.paste(lit, (0, 0), mask)
    # The top half a touch lighter, lit from above, as NuuGear's upgrade arrow.
    top = Image.new("L", (BIG, BIG), 0)
    ImageDraw.Draw(top).rectangle([0, 0, BIG, u(30)], fill=255)
    top.paste(0, (0, 0), Image.eval(mask, lambda v: 255 - v))
    light = tuple(min(255, c + 35) for c in color) + (255,)
    out.paste(Image.new("RGBA", (BIG, BIG), light), (0, 0), top)
    return out


# --- Glyphs (in 64-pixel icon space) -------------------------------------------------------------------------------

def road(d):
    """A waypoint arrow, pointing up and to the right: where to go next."""
    cx, cy, angle = 31, 33, math.radians(45)

    def turn(x, y):
        x, y = x - 32, y - 33
        c, s = math.cos(angle), math.sin(angle)
        return (cx + x * c - y * s, cy + x * s + y * c)

    # An arrowhead with a notched tail, as the guide arrow.
    d.polygon(pts(turn(x, y) for x, y in [(32, 12), (48, 50), (32, 42), (16, 50)]), fill=255)


def professions(d):
    """An anvil."""
    d.polygon(pts([(9, 20), (50, 20), (55, 24), (47, 29), (43, 31), (43, 34), (23, 34), (23, 31), (16, 28)]),
              fill=255)
    d.rectangle(pts([(27, 33), (40, 44)]), fill=255)
    d.polygon(pts([(20, 44), (47, 44), (52, 52), (15, 52)]), fill=255)


def gear(d):
    """A shield with an upgrade arrow cut out of it."""
    d.polygon(pts([(14, 12), (50, 12), (50, 33), (46, 43), (32, 54), (18, 43), (14, 33)]), fill=255)
    d.polygon(pts([(32, 18), (42, 30), (36, 30), (36, 43), (28, 43), (28, 30), (22, 30)]), fill=0)


def kit(d):
    """A cog."""
    cx = cy = 32
    teeth, outer, inner = 8, 22, 17
    points = []
    for i in range(teeth * 4):
        a = 2 * math.pi * (i - 0.5) / (teeth * 4)
        r = outer if i % 4 in (0, 1) else inner
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts(points), fill=255)
    d.ellipse(pts([(cx - 7.5, cy - 7.5), (cx + 7.5, cy + 7.5)]), fill=0)


ICONS = {
    "NuuRoad": (road, (77, 201, 240)),
    "NuuProfessions": (professions, (240, 170, 70)),
    "NuuGear": (gear, (90, 215, 100)),
    "NuuKit": (kit, (165, 175, 195)),
}


def write_tga(path, image):
    """32-bit uncompressed TGA, rows bottom to top, 8 bits of alpha."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 8)
    r, g, b, a = image.transpose(Image.FLIP_TOP_BOTTOM).split()
    with open(path, "wb") as f:
        f.write(header)
        f.write(Image.merge("RGBA", (b, g, r, a)).tobytes())


def main():
    for addon, (draw_glyph, color) in ICONS.items():
        big = Image.alpha_composite(tile(color), glyph_layer(draw_glyph, color))
        icon = big.resize((SIZE, SIZE), Image.LANCZOS)
        path = os.path.join(ROOT, addon, "Icon.tga")
        write_tga(path, icon)
        print("wrote", path)
        if PNG:
            icon.save(os.path.join(ROOT, addon, "Icon.png"))


if __name__ == "__main__":
    main()
