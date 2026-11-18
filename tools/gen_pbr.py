#!/usr/bin/env python3
"""Photoreal PBR surface set for OFFICE MAYHEM (run after gen_textures.py).

For every surface it writes <name>_albedo.png, <name>_normal.png and <name>_orm.png
(R = ambient occlusion, G = roughness, B = unused/metal) at 1024 px for floors/walls,
512 px for small props. Also writes micro_rough.png (triplanar roughness breakup for
flat-coloured materials) and lens_dirt.png (post-process bloom dirt).
Everything is procedural and tileable (numpy + Pillow), no third-party art.
Usage: python3 tools/gen_pbr.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUT = os.path.join(ROOT, "textures")
os.makedirs(OUT, exist_ok=True)


# ------------------------------------------------------------------ helpers
def noise(size, scale, octaves=4, seed=0, persistence=0.5):
    """Periodic fBm built in the frequency domain (exactly tileable)."""
    r = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        cells = min(cells, size)
        grid = r.random((cells, cells))
        g = np.fft.fft2(grid)
        pad = np.zeros((size, size), dtype=complex)
        h = cells // 2
        pad[:h, :h] = g[:h, :h]
        pad[:h, -h:] = g[:h, -h:]
        pad[-h:, :h] = g[-h:, :h]
        pad[-h:, -h:] = g[-h:, -h:]
        layer = np.real(np.fft.ifft2(pad))
        layer = (layer - layer.min()) / (np.ptp(layer) + 1e-9)
        out += layer * amp
        total += amp
        amp *= persistence
    return out / total


def blur(a, radius):
    """Wrap-around gaussian blur in the frequency domain (keeps tiling)."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    k = np.exp(-2 * (math.pi ** 2) * (radius ** 2) * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * k))


def norm01(a):
    return (a - a.min()) / (np.ptp(a) + 1e-9)


def to8(a):
    return np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8)


def srgb(rgb):
    return Image.fromarray(to8(rgb), "RGB")


def ramp(h, c0, c1):
    c0 = np.array(c0, float) / 255.0
    c1 = np.array(c1, float) / 255.0
    return c0 + (c1 - c0) * h[..., None]


def normal_map(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, -dy, np.ones_like(h)], -1)   # same convention as gen_textures.py
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(to8(n * 0.5 + 0.5), "RGB")


def ao_from_height(h, radius, strength=1.0):
    cav = blur(h, radius) - h
    return np.clip(1.0 - np.maximum(cav, 0) * strength, 0, 1)


def save_set(name, albedo, height, nstrength, rough, ao, metal=None):
    albedo_img = srgb(albedo)
    albedo_img.save(os.path.join(OUT, name + "_albedo.png"), optimize=True)
    normal_map(height, nstrength).save(os.path.join(OUT, name + "_normal.png"), optimize=True)
    b = metal if metal is not None else np.zeros_like(rough)
    orm = np.stack([ao, rough, b], -1)
    Image.fromarray(to8(orm), "RGB").save(os.path.join(OUT, name + "_orm.png"), optimize=True)
    print("  ", name, albedo.shape[0])


def grid(s):
    y, x = np.mgrid[0:s, 0:s] / s
    return x, y


def cells(s, n, seed):
    """Per-cell random values on an n x n grid (for tiles / boards)."""
    r = np.random.default_rng(seed).random((n, n))
    x, y = grid(s)
    return r[(y * n).astype(int) % n, (x * n).astype(int) % n]


# ------------------------------------------------------------------ surfaces
def carpet():
    """Commercial loop-pile carpet tiles (2 x 2 tiles of 50 cm per texture), quarter-turned."""
    s = 1024
    x, y = grid(s)
    n = 2
    tile_rot = cells(s, n, 21)
    lx, ly = (x * n) % 1.0, (y * n) % 1.0
    rot = tile_rot > 0.5
    u = np.where(rot, ly, lx)
    # loop rows + fibre noise
    rows = np.sin(u * 2 * math.pi * 90) * 0.5 + 0.5
    fib = noise(s, 256, 2, 3) * 0.6 + np.random.default_rng(4).random((s, s)) * 0.4
    tuft = noise(s, 64, 3, 5)
    h = norm01(rows * 0.35 + fib * 0.45 + tuft * 0.2)
    seam = np.minimum(np.minimum(lx, 1 - lx), np.minimum(ly, 1 - ly)) * s / n
    seam_m = np.clip(seam / 2.5, 0, 1)
    h = h * (0.55 + 0.45 * seam_m)
    heather = np.random.default_rng(6).random((s, s))
    col = ramp(h, (44, 50, 64), (92, 102, 124))
    col = np.where((heather > 0.93)[..., None], col * 1.35 + 0.03, col)
    col = np.where((heather < 0.04)[..., None], col * 0.6, col)
    col *= (0.94 + tile_rot[..., None] * 0.08)
    wear = noise(s, 3, 3, 7)
    col *= (0.92 + wear[..., None] * 0.12)
    stains = np.clip((noise(s, 6, 4, 8) - 0.72) * 6, 0, 1)
    col = col * (1 - stains[..., None] * 0.25)
    rough = np.clip(0.88 + fib * 0.12, 0, 1)
    ao = ao_from_height(h, 3, 1.6) * (0.75 + 0.25 * seam_m)
    save_set("carpet", col, h, 2.5, rough, ao)


def wood_set(name, light, dark, seed, boards=6, gloss=0.5):
    """Oak / walnut planks: annual rings, medullary rays, pores, per-board tint, bevelled seams."""
    s = 1024
    x, y = grid(s)
    bi = np.floor(y * boards).astype(int)
    r = np.random.default_rng(seed)
    tint = r.random(boards + 1)[bi]
    offs = r.random(boards + 1)[bi]
    ring_f = (8 + r.random(boards + 1) * 6)[bi]
    warp = noise(s, 3, 4, seed + 1)
    v = (y * boards) % 1.0
    rings = np.sin((v * ring_f + warp * 3.0 + np.sin((x + offs) * 2 * math.pi) * 0.6) * 2 * math.pi)
    rings = np.abs(rings) ** 0.6
    streak = noise(s, 64, 3, seed + 2)
    pores = (np.random.default_rng(seed + 3).random((s, s)) > 0.965).astype(float)
    pores = blur(pores, 0.7)
    h = norm01(rings * 0.45 + streak * 0.35 - pores * 0.8)
    col = ramp(h, dark, light)
    col *= (0.85 + tint[..., None] * 0.28)
    # end joints along each board
    joint = np.abs(((x + offs) % 1.0) - 0.5) > 0.4985
    edge = np.minimum(v, 1 - v) * s / boards
    bevel = np.clip(edge / 3.0, 0, 1)
    jm = np.where(joint, 0.0, 1.0)
    col *= (0.45 + 0.55 * bevel * jm)[..., None]
    height = h * 0.25 + bevel * jm * 1.0
    rough = np.clip(gloss + (1 - h) * 0.18 + pores * 0.3 + (1 - bevel) * 0.3, 0, 1)
    ao = np.clip(0.35 + 0.65 * bevel * jm, 0, 1) * ao_from_height(h, 2, 0.8)
    save_set(name, col, height, 6.0, rough, ao)


def concrete():
    """Polished concrete: aggregate, trowel swirls, hairline cracks, patchy sheen."""
    s = 1024
    base = noise(s, 4, 6, 31)
    agg = np.random.default_rng(32).random((s, s))
    speck = blur((agg > 0.985).astype(float), 0.9) - blur((agg < 0.012).astype(float), 0.9) * 0.6
    swirl = noise(s, 2, 3, 33)
    x, y = grid(s)
    trowel = np.sin((x + swirl * 0.8) * 2 * math.pi * 2) * 0.5 + 0.5
    cr = noise(s, 5, 5, 34)
    crack = np.clip(1 - np.abs(cr - 0.5) * 260, 0, 1) * (noise(s, 3, 2, 35) > 0.72) * 0.7
    h = norm01(base * 0.6 + speck * 0.3 + trowel * 0.05) - crack * 0.5
    col = ramp(norm01(base * 0.7 + speck * 0.3), (118, 118, 116), (178, 176, 170))
    col *= (1 - crack[..., None] * 0.45)
    col *= (0.93 + noise(s, 2, 2, 36)[..., None] * 0.1)
    rough = np.clip(0.3 + norm01(noise(s, 3, 6, 37) * 0.7 + swirl * 0.3) * 0.5 + crack * 0.3, 0, 1)
    ao = ao_from_height(h, 2, 1.2) * (1 - crack * 0.6)
    save_set("concrete", col, h, 1.8, rough, ao)


def tiles(name, c_tile, c_grout, n, gloss, seed):
    s = 1024
    x, y = grid(s)
    lx, ly = (x * n) % 1.0, (y * n) % 1.0
    e = np.minimum(np.minimum(lx, 1 - lx), np.minimum(ly, 1 - ly)) * s / n
    gw = 4.5
    tile_m = np.clip((e - gw) / 2.5, 0, 1)
    pertile = cells(s, n, seed)
    glaze = noise(s, 8, 4, seed + 1)
    col_t = ramp(glaze * 0.4 + pertile * 0.6, [c * 0.93 for c in c_tile], c_tile)
    grout_n = noise(s, 64, 2, seed + 2)
    col_g = ramp(grout_n, [c * 0.8 for c in c_grout], c_grout)
    dirt = np.clip(noise(s, 6, 3, seed + 3) - 0.4, 0, 1)
    col_g *= (1 - dirt[..., None] * 0.5)
    col = col_g + (col_t - col_g) * tile_m[..., None]
    pillow = np.clip(e / 14.0, 0, 1) ** 0.5
    height = tile_m * (0.8 + pillow * 0.2) + glaze * 0.02
    rough = gloss + (1 - tile_m) * (0.9 - gloss) + glaze * 0.08
    ao = np.clip(0.4 + 0.6 * np.clip(e / (gw + 4), 0, 1), 0, 1)
    save_set(name, col, height, 7.0, np.clip(rough, 0, 1), ao)


def wall_paint():
    """Eggshell paint over plaster: roller orange-peel + faint trowel waves + scuffs."""
    s = 1024
    peel = noise(s, 160, 2, 41)
    wave = noise(s, 3, 3, 42)
    h = norm01(peel * 0.7 + wave * 0.3)
    col = ramp(h, (220, 215, 204), (236, 232, 222))
    scuff = np.clip(noise(s, 12, 4, 43) - 0.74, 0, 1) * 3
    col *= (1 - scuff[..., None] * 0.15)
    rough = np.clip(0.72 + peel * 0.18 - scuff * 0.1, 0, 1)
    save_set("wall_paint", col, h, 0.9, rough, ao_from_height(h, 2, 0.5))


def ceiling():
    """Mineral-fibre acoustic tiles, 2 x 2 per texture (60 cm), fissures and pinholes, T-bar grid."""
    s = 1024
    x, y = grid(s)
    n = 2
    lx, ly = (x * n) % 1.0, (y * n) % 1.0
    e = np.minimum(np.minimum(lx, 1 - lx), np.minimum(ly, 1 - ly)) * s / n
    rail = e < 6
    fiss = noise(s, 24, 4, 51)
    fiss = np.clip(1 - np.abs(fiss - 0.5) * 22, 0, 1)
    pins = blur((np.random.default_rng(52).random((s, s)) > 0.992).astype(float), 0.8)
    h = 0.8 - fiss * 0.3 - pins * 1.5 + noise(s, 128, 2, 53) * 0.1
    bevel = np.clip((e - 6) / 6, 0, 1)
    h = np.where(rail, 1.0, h * (0.6 + 0.4 * bevel))
    col = ramp(np.clip(h, 0, 1), (196, 196, 190), (240, 240, 234))
    col = np.where(rail[..., None], np.array([0.92, 0.92, 0.9]), col)
    stain = np.clip(noise(s, 4, 4, 54) - 0.78, 0, 1) * 4
    col *= (1 - stain[..., None] * np.array([0.05, 0.1, 0.2]))
    rough = np.where(rail, 0.35, 0.97)
    ao = np.where(rail, 1.0, np.clip(0.55 + 0.45 * bevel, 0, 1) * ao_from_height(h, 2, 1.0))
    save_set("ceiling", col, h, 3.0, rough, ao)


def metal(s=512):
    """Brushed stainless steel (horizontal brushing)."""
    r = np.random.default_rng(61)
    lines = r.random((s, 1)) * np.ones((1, s))
    lines = blur(lines + noise(s, 64, 2, 62) * 0.2, 0.6)
    fine = blur(r.random((s, s)), 0.5)
    stretch = np.array(Image.fromarray(to8(fine)).resize((s * 8, s)).crop((0, 0, s, s))) / 255.0
    h = norm01(lines * 0.6 + stretch * 0.4)
    col = ramp(h, (150, 154, 160), (196, 200, 206))
    smudge = np.clip(noise(s, 5, 4, 63) - 0.6, 0, 1) * 2
    rough = np.clip(0.22 + h * 0.15 + smudge * 0.25, 0, 1)
    save_set("metal", col, h, 0.6, rough, np.ones_like(h))


def leather(s=512):
    """Pebbled leather: Voronoi-ish grain via thresholded noise cells."""
    cellsn = noise(s, 48, 2, 71)
    grain = np.abs(np.sin(cellsn * 40))
    h = norm01(blur(grain, 1.2))
    col = ramp(h, (34, 23, 20), (70, 47, 38))
    wear = np.clip(noise(s, 4, 3, 72) - 0.55, 0, 1) * 2
    col = col * (1 + wear[..., None] * 0.35)
    rough = np.clip(0.42 + (1 - h) * 0.25 - wear * 0.15, 0, 1)
    save_set("leather", col, h, 3.5, rough, ao_from_height(h, 1.5, 1.5))


def fabric(s=512):
    """Office-chair woven polyester: tight twill weave with heathered yarns."""
    x, y = np.mgrid[0:s, 0:s]
    k = 2 * math.pi / 8
    warp = np.sin(x * k) * 0.5 + 0.5
    weft = np.sin(y * k) * 0.5 + 0.5
    over = ((x // 4 + y // 4) % 2) == 0
    weave = np.where(over, warp * (0.6 + 0.4 * weft), weft * (0.6 + 0.4 * warp))
    heather = noise(s, 32, 2, 81) * 0.5 + np.random.default_rng(82).random((s, s)) * 0.2
    h = norm01(weave * 0.75 + heather * 0.25)
    col = ramp(h, (58, 66, 80), (108, 118, 136))
    rough = np.clip(0.85 + (1 - weave) * 0.15, 0, 1)
    save_set("fabric", col, h, 2.0, rough, ao_from_height(weave, 1.2, 1.4))


def plastic(s=512):
    """Light-grey ABS with fine moulded texture (VDI 3400 style spark erosion)."""
    h = norm01(noise(s, 128, 3, 91) * 0.6 + np.random.default_rng(92).random((s, s)) * 0.4)
    h = blur(h, 0.6)
    col = ramp(noise(s, 4, 3, 93), (222, 222, 224), (238, 238, 240))
    rough = np.clip(0.42 + h * 0.2, 0, 1)
    save_set("plastic", col, h, 0.8, rough, np.ones_like(h))


def grey_detail():
    """Micro roughness breakup used triplanar on flat-colour materials."""
    s = 512
    a = noise(s, 4, 6, 101) * 0.55 + noise(s, 64, 2, 102) * 0.25 + blur(np.random.default_rng(103).random((s, s)), 0.6) * 0.2
    smudges = np.clip(noise(s, 8, 4, 104) - 0.6, 0, 1) * 1.5
    a = norm01(a) * 0.35 + 0.65 - smudges * 0.25
    Image.fromarray(to8(np.clip(a, 0, 1)), "L").save(os.path.join(OUT, "micro_rough.png"), optimize=True)
    print("   micro_rough")


def lens_dirt():
    """Dust, smudges and finger marks on the camera lens (revealed by bright light)."""
    w, h = 1024, 576
    r = np.random.default_rng(111)
    img = np.zeros((h, w))
    yy, xx = np.mgrid[0:h, 0:w]
    for _ in range(260):
        cx, cy = r.random() * w, r.random() * h
        rad = r.random() ** 3 * 38 + 2
        a = r.random() * 0.5 + 0.1
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        ring = np.clip(1 - d / rad, 0, 1) ** 0.7 * (0.6 + 0.4 * (d > rad * 0.75))
        img += ring * a
    big = noise(1024, 3, 5, 112)[:h, :w]
    img = img * 0.55 + np.clip(big - 0.45, 0, 1) * 1.6
    img = np.array(Image.fromarray(to8(np.clip(img, 0, 1))).filter(ImageFilter.GaussianBlur(1.5)))
    Image.fromarray(img, "L").save(os.path.join(OUT, "lens_dirt.png"), optimize=True)
    print("   lens_dirt")


def skyline():
    """City seen from the office windows: three depth layers of towers fading into the haze,
    glass curtain walls reflecting the sky, mullion grids, a few lit floors, rooftop kit."""
    W, H = 2048, 768
    r = np.random.default_rng(121)
    yy = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
    sky_top = np.array([0.42, 0.6, 0.86])
    sky_hor = np.array([0.86, 0.9, 0.93])
    t = np.clip(yy / 0.85, 0, 1) ** 1.4
    img = sky_top + (sky_hor - sky_top) * t[..., None]
    cloud = noise(2048, 3, 6, 122)[:H, :W]
    cloud = np.clip((cloud - 0.55) * 3, 0, 1) * (1 - yy) * 0.5
    img = img + (np.array([1, 1, 1]) - img) * cloud[..., None]
    haze = np.array([0.8, 0.85, 0.9])
    layers = [  # (count, min_h, max_h, width range, haze amount, base tone)
        (34, 0.25, 0.62, (40, 110), 0.72, 0.55),
        (24, 0.35, 0.85, (70, 170), 0.45, 0.42),
        (14, 0.2, 0.55, (130, 300), 0.18, 0.3),
    ]
    for li, (count, hmin, hmax, wr, hz, tone) in enumerate(layers):
        x = -40
        while x < W:
            bw = int(r.integers(*wr))
            bh = int(H * (hmin + r.random() * (hmax - hmin)))
            top = H - bh
            x0, x1 = max(0, x), min(W, x + bw)
            if x1 <= x0:
                x += bw
                continue
            kind = r.random()
            hue = np.array([0.36, 0.42, 0.5]) * (tone + r.random() * 0.15) / 0.45
            if kind < 0.45:   # glass tower reflecting the sky gradient
                refl = sky_top + (sky_hor - sky_top) * (1 - np.clip((np.arange(top, H) - top) / max(1, bh), 0, 1))[:, None] ** 0.7
                block = refl[:, None, :] * 0.55 + hue * 0.45
                block = np.repeat(block, x1 - x0, 1)
            else:             # concrete / stone with punched windows
                block = np.ones((H - top, x1 - x0, 3)) * (hue * 1.25)
            fy = np.arange(top, H)[:, None]
            fx = np.arange(x0, x1)[None, :]
            floor_h = 9 - li * 2 if li < 2 else 12
            col_w = 7 if kind < 0.45 else 10
            win = ((fy - top) % floor_h > 2) & ((fx - x0) % col_w > 1)
            dark = 0.82 if kind < 0.45 else 0.55
            block = np.where(win[..., None], block * dark, block)
            lit = (r.random((((H - top) // floor_h) + 1, ((x1 - x0) // col_w) + 1)) > 0.975)
            litm = lit[((fy - top) // floor_h), ((fx - x0) // col_w)] & win
            block = np.where(litm[..., None], block * 0.4 + np.array([1.0, 0.92, 0.7]) * 0.6, block)
            # vertical sun / shade side
            shade = np.clip((fx - x0) / max(1, x1 - x0), 0, 1)
            block = block * (1.06 - shade[..., None] * 0.18)
            # haze by depth layer and with height (aerial perspective)
            hzm = hz * (0.7 + 0.3 * np.clip((fy - top) / max(1, bh), 0, 1))
            block = block + (haze - block) * hzm[..., None]
            img[top:H, x0:x1] = block
            # rooftop details
            if r.random() < 0.5 and bw > 50:
                rx = x0 + int(bw * r.random() * 0.6)
                rw, rh = int(bw * 0.2), int(6 + r.random() * 14)
                img[max(0, top - rh):top, rx:min(W, rx + rw)] = img[top + 2, rx:min(W, rx + rw)] * 0.95
            x += bw + int(r.integers(-10, 25))
    # ground haze band
    band = np.clip((yy - 0.82) / 0.18, 0, 1) ** 2 * 0.35
    img = img + (haze - img) * band[..., None]
    Image.fromarray(to8(np.clip(img, 0, 1)), "RGB").save(os.path.join(OUT, "skyline.png"), optimize=True)
    print("   skyline")


if __name__ == "__main__":
    print("PBR surfaces:")
    carpet()
    wood_set("wood", (214, 170, 120), (120, 80, 46), 11, 6, 0.32)
    wood_set("wood_dark", (128, 84, 54), (52, 30, 20), 13, 5, 0.28)
    concrete()
    tiles("tile_floor", (212, 210, 202), (128, 126, 120), 4, 0.18, 61)
    tiles("tile_wall", (238, 241, 243), (196, 200, 204), 6, 0.08, 63)
    wall_paint()
    ceiling()
    metal()
    leather()
    fabric()
    plastic()
    grey_detail()
    lens_dirt()
    skyline()
