"""Makes the art themes' textures: NuuKit/Media/<theme>/*.tga.

Run from anywhere:
    uv run --no-project --with numpy --with pillow python NuuKit/Tools/Textures.py

Procedural and our own, so they ship with the kit. Every size is a power of
two. Backgrounds tile both ways (the noise is made in frequency space, so it
wraps); frames and plates are 9-slice sources whose corner sizes match
UI/Theme/Themes.lua: a frame's corner is 30 of 128 pixels, a plate's 12 of 64.

TGA is written by hand: 32-bit, uncompressed, bottom-left origin, the form
every client reads. Pass --png to also write PNG copies for looking at.
"""
import os
import struct
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(os.path.dirname(HERE), "Media")
PNG = "--png" in sys.argv


def fnoise(h, w, beta, seed, stretch_x=1.0, stretch_y=1.0):
    """Unit-variance 1/f^beta noise that wraps at the edges. A stretch above 1
    damps that axis' high frequencies, which draws streaks along it."""
    r = np.random.default_rng(seed)
    n = r.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None] * stretch_y
    fx = np.fft.fftfreq(w)[None, :] * stretch_x
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    spec = np.fft.fft2(n) / (f ** beta)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    return (out - out.mean()) / out.std()


def ramp(t, dark, light):
    t = np.clip(t, 0, 1)[..., None]
    return np.array(dark, float) * (1 - t) + np.array(light, float) * t


def write_tga(path, rgba):
    """32-bit uncompressed TGA, rows bottom to top, 8 bits of alpha."""
    height, width = rgba.shape[:2]
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    bgra = rgba[::-1, :, [2, 1, 0, 3]]
    with open(path, "wb") as f:
        f.write(header)
        f.write(np.ascontiguousarray(bgra).astype(np.uint8).tobytes())


def save(rgb, name, alpha=None):
    """`name` is "<theme>_<texture>": written to Media/<theme>/<texture>.tga."""
    theme, texture = name.split("_", 1)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)
    a = np.full(rgb.shape[:2], 255, np.uint8) if alpha is None else np.clip(alpha * 255, 0, 255).astype(np.uint8)
    rgba = np.dstack([rgb, a])
    folder = os.path.join(MEDIA, theme)
    os.makedirs(folder, exist_ok=True)
    write_tga(os.path.join(folder, texture + ".tga"), rgba)
    if PNG:
        Image.fromarray(rgba, "RGBA").save(os.path.join(folder, texture + ".png"))


# --- Backgrounds (256x256, tile both ways) ---------------------------------

def leather(seed):
    base = fnoise(256, 256, 1.7, seed)
    grain = fnoise(256, 256, 1.0, seed + 1)
    creases = 1 - np.abs(fnoise(256, 256, 1.3, seed + 2))  # ridges near 1
    pores = fnoise(256, 256, 0.2, seed + 3)
    t = 0.5 + 0.10 * base + 0.05 * grain - 0.10 * np.clip(creases - 0.85, 0, 1) / 0.15
    t -= 0.10 * (pores < -2.3)
    return ramp(t, (18, 13, 11), (58, 43, 34))


def slate(seed):
    base = fnoise(256, 256, 1.8, seed)
    fine = fnoise(256, 256, 0.8, seed + 1)
    warp = fnoise(256, 256, 2.0, seed + 2)
    yy, xx = np.mgrid[0:256, 0:256] / 256.0
    # Veins: a ridge of a sine that the warp bends; the period divides 256, so it wraps.
    veins = np.abs(np.sin(2 * np.pi * (xx + yy) * 2 + 2.2 * warp))
    veins = np.clip(1 - veins / 0.06, 0, 1)
    t = 0.5 + 0.10 * base + 0.04 * fine + 0.10 * veins
    return ramp(t, (13, 18, 28), (44, 55, 76))


save(leather(11), "horde_bg")
save(slate(21), "alliance_bg")


# --- Header bands (256x64, tile across) ---------------------------------------

def band(seed, dark, light, line):
    streak = fnoise(64, 256, 1.2, seed, stretch_x=10)
    yy = np.mgrid[0:64, 0:256][0] / 63.0
    t = 0.55 - 0.18 * yy + 0.07 * streak
    rgb = ramp(t, dark, light)
    rgb[0:1] = rgb[0:1] * 1.35          # top rim catches the light
    rgb[-3:-1] = np.array(line, float)  # the faction line under the band
    rgb[-1:] = rgb[-1:] * 0.4
    return rgb


save(band(31, (16, 12, 10), (70, 56, 46), (122, 34, 26)), "horde_band")
save(band(41, (12, 16, 26), (58, 70, 94), (160, 128, 66)), "alliance_band")


# --- 9-slice frames (128x128, corner 32, band 22, centre transparent) ---------

def frame(seed, metal_dark, metal_light, inner_line, cap_dark, cap_light):
    S, B, C = 128, 22, 30
    yy, xx = np.mgrid[0:S, 0:S]
    d_top, d_left, d_bot, d_right = yy, xx, S - 1 - yy, S - 1 - xx
    d = np.minimum.reduce([d_top, d_left, d_bot, d_right])
    horiz = np.minimum(d_top, d_bot) <= np.minimum(d_left, d_right)
    brush_h = fnoise(S, S, 1.1, seed, stretch_x=12)
    brush_v = fnoise(S, S, 1.1, seed + 1, stretch_y=12)
    brush = np.where(horiz, brush_h, brush_v)
    lit = (d == d_top) | (d == d_left)  # light from the top left

    # Profile across the band: bright rim, slight dip, rounded body, shadow, line.
    prof = np.zeros_like(d, float)
    prof += np.where(d < 2, np.where(lit, 0.40, 0.12), 0)
    prof += np.where((d >= 2) & (d < 4), -0.12, 0)
    body = (d >= 4) & (d < B - 5)
    prof += np.where(body, 0.12 * np.cos(np.pi * (d - 4) / (B - 9) - np.pi / 2) * (np.where(lit, 1.0, 0.6)), 0)
    prof += np.where((d >= B - 5) & (d < B - 3), -0.30, 0)
    t = 0.45 + prof + 0.06 * brush
    rgb = ramp(t, metal_dark, metal_light)
    line = (d >= B - 3) & (d < B - 1)
    rgb[line] = np.array(inner_line, float)
    rgb[d == B - 1] = rgb[d == B - 1] * 0.35
    alpha = (d < B).astype(float)

    # Corner caps: a small bevelled plate with a flush bolt, nothing more.
    for cy, cx in ((0, 0), (0, S - C), (S - C, 0), (S - C, S - C)):
        py, px = yy - cy, xx - cx
        inside = (py >= 0) & (py < C) & (px >= 0) & (px < C)
        e = np.minimum.reduce([py, px, C - 1 - py, C - 1 - px])
        tl = np.minimum(py, px) <= np.minimum(C - 1 - py, C - 1 - px)
        ct = 0.5 + 0.06 * fnoise(S, S, 1.0, seed + 5)
        ct = ct + np.where(e < 2, np.where(tl, 0.35, -0.25), 0) + np.where((e >= 2) & (e < 3), np.where(tl, -0.1, 0.1), 0)
        cap = ramp(ct, cap_dark, cap_light)
        r = np.sqrt((py - C / 2 + 0.5) ** 2 + (px - C / 2 + 0.5) ** 2)
        bolt = r < 3.2
        cap[bolt] = ramp(0.75 - 0.12 * (py[bolt] - C / 2) / 3.2, cap_dark, cap_light)
        cap[(r >= 3.2) & (r < 4.2)] *= 0.45
        rgb[inside] = cap[inside]
        alpha[inside] = 1
    return rgb, alpha


rgb, a = frame(51, (22, 20, 19), (104, 96, 90), (110, 30, 22), (40, 30, 24), (120, 92, 72))
save(rgb, "horde_frame", a)
rgb, a = frame(61, (26, 30, 38), (118, 126, 140), (160, 128, 66), (70, 54, 24), (206, 170, 96))
save(rgb, "alliance_frame", a)


# --- Button plates (128x64, corner 16, filled centre) -------------------------

def plate(seed, face_dark, face_light, rim_dark, rim_light):
    H, W, R = 64, 128, 6
    yy, xx = np.mgrid[0:H, 0:W]
    e = np.minimum.reduce([yy, xx, H - 1 - yy, W - 1 - xx])
    tl = np.minimum(yy, xx) <= np.minimum(H - 1 - yy, W - 1 - xx)
    brush = fnoise(H, W, 1.1, seed, stretch_x=8)
    face_t = 0.62 - 0.30 * (yy / (H - 1)) + 0.05 * brush
    rgb = ramp(face_t, face_dark, face_light)
    rim_t = 0.5 + np.where(tl, 0.25, -0.2) + 0.05 * brush
    rim = ramp(rim_t, rim_dark, rim_light)
    on_rim = (e >= 1) & (e < R - 1)
    rgb[on_rim] = rim[on_rim]
    rgb[e == 0] = np.array(rim_dark, float) * 0.5
    rgb[e == R - 1] = rgb[e == R - 1] * 0.55   # the face sits a step below the rim
    rgb[(e == R) & (yy < H / 2)] = rgb[(e == R) & (yy < H / 2)] * 1.25
    return rgb


save(plate(71, (52, 13, 10), (126, 38, 28), (26, 24, 23), (110, 102, 96)), "horde_plate_primary")
save(plate(72, (30, 27, 25), (76, 70, 66), (22, 20, 19), (104, 96, 90)), "horde_plate")
save(plate(81, (14, 28, 58), (40, 78, 138), (70, 54, 24), (206, 170, 96)), "alliance_plate_primary")
save(plate(82, (24, 30, 42), (70, 82, 104), (26, 30, 38), (118, 126, 140)), "alliance_plate")

print("textures written to", MEDIA)
