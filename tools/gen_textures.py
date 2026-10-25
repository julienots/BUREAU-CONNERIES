#!/usr/bin/env python3
"""Generates the textures of OFFICE MAYHEM (albedo + normal maps, posters, screens).

Everything is procedural (numpy + Pillow) so the project has no third-party art dependency.
Usage: python3 tools/gen_textures.py   ->  assets/textures/*.png
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")
OUT = os.path.join(ROOT, "textures")
FONT_TITLE = os.path.join(ROOT, "fonts", "LilitaOne-Regular.ttf")
FONT_BODY = os.path.join(ROOT, "fonts", "Fredoka.ttf")
rng = np.random.default_rng(7)
os.makedirs(OUT, exist_ok=True)


def font(path, size):
    return ImageFont.truetype(path, size)


def tileable_noise(size, scale, octaves=4, seed=0):
    """Periodic value noise built from random low-res grids upsampled with wrap."""
    r = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        grid = r.random((cells, cells))
        # bicubic-ish wrap upsample via FFT zero-padding keeps it tileable
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
        amp *= 0.5
    return out / total


def to_img(arr):
    return Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))


def normal_from_height(h, strength=2.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, -dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return to_img(n * 0.5 + 0.5)


def colorize(h, c0, c1):
    c0 = np.array(c0) / 255.0
    c1 = np.array(c1) / 255.0
    return to_img(c0 + (c1 - c0) * h[..., None])


def save(img, name):
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


# ------------------------------------------------------------------ surfaces
def carpet():
    s = 512
    n = tileable_noise(s, 64, 3, 1) * 0.6 + rng.random((s, s)) * 0.4
    fleck = (rng.random((s, s)) > 0.985).astype(float)
    h = np.clip(n * 0.85 + fleck * 0.3, 0, 1)
    img = colorize(h, (58, 66, 84), (96, 106, 128))
    save(img, "carpet_albedo")
    save(normal_from_height(tileable_noise(s, 128, 2, 2) * 0.5 + rng.random((s, s)) * 0.5, 1.5), "carpet_normal")


def wood():
    """Straight-grain planks: long boards with per-board tint, fine grain lines and seams."""
    s = 512
    y, x = np.mgrid[0:s, 0:s] / s
    boards = 6
    bi = np.floor(y * boards)
    tint = np.random.default_rng(3).random(boards)[bi.astype(int)] * 0.25
    stretch = tileable_noise(s, 4, 3, 3)
    grain = np.sin((y * boards * 9.0 + stretch * 2.5 + np.sin(x * 2 * math.pi) * 0.3) * 2 * math.pi) * 0.5 + 0.5
    fine = tileable_noise(s, 64, 2, 4)
    h = np.clip(0.45 + grain * 0.18 + fine * 0.2 - tint, 0, 1)
    seam = (np.abs(((y * boards) % 1.0) - 0.0) < 0.012) | (np.abs(((y * boards) % 1.0) - 1.0) < 0.012)
    offs = np.random.default_rng(5).random(boards)[bi.astype(int)]
    seam |= (np.abs(((x + offs) % 1.0)) < 0.004)
    h = np.where(seam, h * 0.45, h)
    save(colorize(h, (140, 94, 56), (214, 168, 118)), "wood_albedo")
    save(normal_from_height(np.where(seam, 0.0, 0.6 + grain * 0.1), 2.0), "wood_normal")
    save(colorize(h, (70, 42, 26), (130, 86, 54)), "wood_dark_albedo")


def tiles(name, c_tile, c_grout, n_tiles=4):
    s = 512
    base = tileable_noise(s, 16, 3, 5) * 0.15 + 0.85
    img = colorize(base, [c * 0.92 for c in c_tile], c_tile)
    d = ImageDraw.Draw(img)
    step = s // n_tiles
    for i in range(n_tiles + 1):
        d.rectangle([i * step - 3, 0, i * step + 3, s], fill=tuple(c_grout))
        d.rectangle([0, i * step - 3, s, i * step + 3], fill=tuple(c_grout))
    save(img, name + "_albedo")
    h = np.ones((s, s))
    for i in range(n_tiles + 1):
        h[:, max(0, i * step - 3): i * step + 3] = 0
        h[max(0, i * step - 3): i * step + 3, :] = 0
    h = np.array(Image.fromarray((h * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))) / 255.0
    save(normal_from_height(h, 3.0), name + "_normal")


def plain(name, c0, c1, scale=8, normal=True):
    s = 256
    h = tileable_noise(s, scale, 4, hash(name) % 1000)
    save(colorize(h, c0, c1), name + "_albedo")
    if normal:
        save(normal_from_height(h * 0.5 + rng.random((s, s)) * 0.1, 1.0), name + "_normal")


def fabric():
    s = 256
    y, x = np.mgrid[0:s, 0:s]
    weave = (np.sin(x * math.pi / 2) * np.sin(y * math.pi / 2)) * 0.5 + 0.5
    h = weave * 0.4 + tileable_noise(s, 16, 2, 9) * 0.6
    save(colorize(h, (70, 78, 92), (105, 115, 132)), "fabric_albedo")
    save(normal_from_height(weave, 1.0), "fabric_normal")


def ceiling():
    s = 256
    h = tileable_noise(s, 32, 2, 11) * 0.2 + rng.random((s, s)) * 0.1 + 0.7
    img = colorize(h, (210, 210, 205), (238, 238, 232))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, s - 1, s - 1], outline=(170, 170, 168), width=3)
    save(img, "ceiling_albedo")


def cardboard():
    s = 256
    h = tileable_noise(s, 6, 4, 13) * 0.4 + 0.6
    img = colorize(h, (160, 118, 70), (196, 152, 98))
    d = ImageDraw.Draw(img)
    d.rectangle([110, 0, 146, s], fill=(205, 180, 130))  # tape
    d.text((20, 170), "ARCHIVES", font=font(FONT_TITLE, 30), fill=(60, 40, 30))
    d.text((24, 205), "2019 — NE PAS JETER", font=font(FONT_BODY, 16), fill=(60, 40, 30))
    d.text((150, 30), "FRAGILE", font=font(FONT_TITLE, 22), fill=(170, 30, 30))
    save(img, "cardboard_albedo")


def paper():
    s = 256
    img = Image.new("RGB", (s, s), (246, 246, 240))
    d = ImageDraw.Draw(img)
    d.rectangle([20, 20, 120, 34], fill=(40, 60, 130))
    for i in range(14):
        w = rng.integers(120, 215)
        d.rectangle([20, 50 + i * 13, 20 + w, 55 + i * 13], fill=(150, 150, 150))
    save(img, "paper_albedo")


def keyboard():
    w, h = 512, 192
    img = Image.new("RGB", (w, h), (40, 42, 48))
    d = ImageDraw.Draw(img)
    for row in range(5):
        for col in range(14):
            x0 = 10 + col * 35
            y0 = 10 + row * 35
            kw = 30 if not (row == 4 and 3 <= col <= 9) else 30
            d.rounded_rectangle([x0, y0, x0 + kw, y0 + 30], 5, fill=(70, 72, 80))
    d.rounded_rectangle([10 + 4 * 35, 10 + 4 * 35, 10 + 10 * 35, 10 + 4 * 35 + 30], 5, fill=(80, 82, 90))
    save(img, "keyboard_albedo")


def whiteboard():
    s = 512
    img = Image.new("RGB", (s * 2, s), (244, 246, 248))
    d = ImageDraw.Draw(img)
    f = font(FONT_BODY, 34)
    d.text((40, 30), "Objectifs Q3 :", font=font(FONT_TITLE, 46), fill=(30, 60, 160))
    for i, t in enumerate(["- Synergiser les synergies", "- Réunion sur les réunions", "- Moins de café (??)", "- KPI: +200% de bonheur"]):
        d.text((60, 110 + i * 52), t, font=f, fill=(40, 40, 40))
    d.line([(620, 380), (700, 300), (780, 340), (900, 150)], fill=(200, 40, 40), width=8)
    d.polygon([(900, 150), (870, 170), (905, 185)], fill=(200, 40, 40))
    save(img, "whiteboard_albedo")
    # Caricature drawn by the player on the same board
    d.ellipse([560, 60, 820, 330], outline=(30, 30, 30), width=8)
    d.ellipse([620, 140, 660, 180], fill=(30, 30, 30))
    d.ellipse([720, 140, 760, 180], fill=(30, 30, 30))
    d.arc([610, 200, 770, 300], 200, 340, fill=(30, 30, 30), width=8)
    d.line([(600, 110), (690, 130)], fill=(30, 30, 30), width=10)
    d.line([(690, 130), (780, 105)], fill=(30, 30, 30), width=10)
    d.rectangle([640, 330, 740, 400], fill=(200, 40, 40))
    d.text((840, 60), "LE CHEF", font=font(FONT_TITLE, 56), fill=(200, 40, 40))
    d.text((840, 130), "(en vrai)", font=f, fill=(30, 30, 30))
    save(img, "whiteboard_caricature_albedo")


def poster(name, bg, title, sub, fg=(255, 255, 255), accent=(255, 204, 34)):
    w, h = 384, 512
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    d.rectangle([16, 16, w - 16, h - 16], outline=accent, width=6)
    ft = font(FONT_TITLE, 64 if len(title) < 9 else 48)
    tw = d.textlength(title, font=ft)
    d.text(((w - tw) / 2, 70), title, font=ft, fill=accent)
    fb = font(FONT_BODY, 26)
    y = 330
    for line in sub.split("\n"):
        lw = d.textlength(line, font=fb)
        d.text(((w - lw) / 2, y), line, font=fb, fill=fg)
        y += 36
    cx, cy = w // 2, 230
    d.ellipse([cx - 60, cy - 60, cx + 60, cy + 60], fill=accent)
    d.ellipse([cx - 25, cy - 20, cx - 10, cy - 5], fill=bg)
    d.ellipse([cx + 10, cy - 20, cx + 25, cy - 5], fill=bg)
    d.arc([cx - 35, cy - 10, cx + 35, cy + 35], 20, 160, fill=bg, width=6)
    save(img, "poster_" + name)


def notice_board():
    w, h = 512, 320
    base = tileable_noise(256, 24, 3, 21)
    img = colorize(base, (150, 108, 66), (186, 142, 96)).resize((w, h))
    d = ImageDraw.Draw(img)
    notes = [((20, 20), (255, 240, 120), "Réunion\n10h30\nsalle Synergie"), ((170, 40), (255, 255, 255), "Qui a pris\nmon yaourt ??\n- Gérard"),
             ((330, 25), (160, 220, 255), "Pot de départ\nde Michel\n(il revient lundi)"), ((60, 170), (255, 190, 210), "Le café n'est\nPAS gratuit"),
             ((230, 175), (190, 255, 190), "Afterwork\nvendredi !!"), ((380, 175), (255, 255, 255), "Imprimante\nen panne\n(encore)")]
    fb = font(FONT_BODY, 17)
    for (x, y), c, t in notes:
        d.rectangle([x, y, x + 130, y + 120], fill=c)
        d.ellipse([x + 58, y + 2, x + 72, y + 16], fill=(200, 30, 30))
        d.multiline_text((x + 10, y + 24), t, font=fb, fill=(40, 40, 40), spacing=4)
    save(img, "notice_board")


def meeting_sign(name, text):
    w, h = 384, 256
    img = Image.new("RGB", (w, h), (250, 250, 245))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 60], fill=(30, 40, 70))
    d.text((20, 10), "PLANNING", font=font(FONT_TITLE, 36), fill=(255, 204, 34))
    d.multiline_text((24, 80), text, font=font(FONT_BODY, 30), fill=(30, 30, 30), spacing=8)
    save(img, name)


def screens():
    w, h = 320, 200
    defs = {
        "screen_work": ((30, 70, 140), "SuperEssence Corp", "Tableur — Q3_final_v12_VRAI.xlsx"),
        "screen_mail": ((235, 238, 245), "Boîte de réception (847)", "RE: RE: RE: TR: Réunion"),
        "screen_off": ((10, 10, 14), "", ""),
        "screen_it": ((0, 90, 200), "Mise à jour 3 %", "Ne pas éteindre l'ordinateur"),
        "screen_boss": ((60, 20, 20), "DIRECTION", "Planning des inspections"),
    }
    for name, (bg, title, sub) in defs.items():
        img = Image.new("RGB", (w, h), bg)
        d = ImageDraw.Draw(img)
        if name == "screen_work":
            d.rectangle([0, 0, w, 24], fill=(20, 110, 60))
            for r in range(8):
                for c in range(5):
                    d.rectangle([10 + c * 60, 34 + r * 19, 66 + c * 60, 50 + r * 19], fill=(250, 250, 250), outline=(180, 180, 180))
            d.text((8, 4), title, font=font(FONT_BODY, 14), fill=(255, 255, 255))
        elif name == "screen_mail":
            d.rectangle([0, 0, 80, h], fill=(210, 215, 228))
            for r in range(8):
                d.rectangle([90, 10 + r * 22, w - 10, 26 + r * 22], fill=(255, 255, 255) if r % 2 else (244, 247, 252))
                d.rectangle([96, 15 + r * 22, 96 + rng.integers(60, 200), 20 + r * 22], fill=(120, 120, 140))
            d.text((90, h - 22), title, font=font(FONT_BODY, 13), fill=(40, 40, 60))
        elif name != "screen_off":
            d.text((20, 70), title, font=font(FONT_TITLE, 26), fill=(255, 255, 255))
            d.text((20, 110), sub, font=font(FONT_BODY, 15), fill=(220, 220, 220))
        save(img, name)
    # Prank wallpapers
    pranks = [("wall_duck", (255, 214, 64), "COIN COIN", "le canard vous observe"), ("wall_potato", (140, 90, 40), "JE SUIS", "UNE PATATE"),
              ("wall_boss", (220, 50, 80), "LE CHEF", "employé du mois : moi"), ("wall_cat", (80, 50, 140), "MIAOU", "lundi encore ?!")]
    for name, bg, a, b in pranks:
        img = Image.new("RGB", (w, h), bg)
        d = ImageDraw.Draw(img)
        for i in range(12):
            x, y = rng.integers(0, w), rng.integers(0, h)
            d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=tuple(int(c * 0.8) for c in bg))
        cx, cy = w // 2, 85
        d.ellipse([cx - 45, cy - 45, cx + 45, cy + 45], fill=(255, 255, 255))
        d.ellipse([cx - 22, cy - 14, cx - 8, cy], fill=(20, 20, 20))
        d.ellipse([cx + 8, cy - 14, cx + 22, cy], fill=(20, 20, 20))
        d.arc([cx - 26, cy - 4, cx + 26, cy + 28], 10, 170, fill=(20, 20, 20), width=5)
        ft = font(FONT_TITLE, 30)
        d.text(((w - d.textlength(a, font=ft)) / 2, 132), a, font=ft, fill=(255, 255, 255))
        fb = font(FONT_BODY, 16)
        d.text(((w - d.textlength(b, font=fb)) / 2, 168), b, font=fb, fill=(255, 255, 255))
        save(img, name)
    # Post-it covered screen
    img = Image.new("RGB", (w, h), (30, 70, 140))
    d = ImageDraw.Draw(img)
    cols = [(255, 240, 100), (255, 170, 200), (160, 230, 255), (180, 255, 160)]
    for r in range(4):
        for c in range(6):
            x = c * 54 + rng.integers(-5, 5)
            y = r * 52 + rng.integers(-5, 5)
            d.rectangle([x, y, x + 56, y + 54], fill=cols[(r + c) % 4], outline=(0, 0, 0))
    d.text((70, 80), "SURPRISE", font=font(FONT_TITLE, 40), fill=(220, 30, 30))
    save(img, "screen_postits")


def skyline():
    w, h = 1024, 384
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(120 + 100 * t), int(170 + 60 * t), int(235 - 10 * t)))
    for layer, (shade, base_h) in enumerate([((150, 170, 200), 180), ((95, 110, 140), 120)]):
        x = 0
        while x < w:
            bw = int(rng.integers(40, 110))
            bh = int(rng.integers(60, 220)) + (base_h if layer == 0 else 0)
            top = h - bh
            d.rectangle([x, top, x + bw, h], fill=shade)
            for wy in range(top + 8, h - 8, 16):
                for wx in range(x + 6, x + bw - 6, 12):
                    if rng.random() > 0.4:
                        lit = (240, 230, 170) if rng.random() > 0.8 else tuple(min(255, c + 30) for c in shade)
                        d.rectangle([wx, wy, wx + 5, wy + 8], fill=lit)
            x += bw + int(rng.integers(0, 12))
    save(img, "skyline")


def logo_corp():
    w, h = 512, 160
    img = Image.new("RGB", (w, h), (18, 18, 22))
    d = ImageDraw.Draw(img)
    ft = font(FONT_TITLE, 72)
    d.text((24, 30), "Super", font=ft, fill=(255, 255, 255))
    x = 24 + d.textlength("Super", font=ft)
    d.text((x, 30), "Essence.", font=ft, fill=(255, 204, 34))
    d.text((28, 118), "CORP — Ensemble, synergisons.", font=font(FONT_BODY, 22), fill=(200, 200, 200))
    save(img, "corp_logo")


def icons():
    """Simple flat icons for inventory/shop items (128px)."""
    s = 128
    out = os.path.join(OUT, "icons")
    os.makedirs(out, exist_ok=True)

    def base(color):
        img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([4, 4, s - 4, s - 4], 24, fill=color)
        return img, d

    specs = {
        "canard": ((60, 140, 220, 255), lambda d: (d.ellipse([34, 50, 98, 104], fill=(255, 214, 40)), d.ellipse([60, 26, 96, 62], fill=(255, 214, 40)),
                                                   d.polygon([(94, 42), (114, 48), (94, 54)], fill=(255, 130, 20)), d.ellipse([78, 36, 86, 44], fill=(0, 0, 0)))),
        "coussin_peteur": ((200, 60, 120, 255), lambda d: (d.ellipse([20, 40, 108, 96], fill=(240, 110, 160)), d.polygon([(54, 92), (74, 92), (64, 116)], fill=(240, 110, 160)),
                                                           d.text((44, 50), "pfff", font=font(FONT_TITLE, 22), fill=(255, 255, 255)))),
        "post_its": ((80, 80, 90, 255), lambda d: [d.rectangle([24 + k * 12, 24 + k * 12, 84 + k * 12, 84 + k * 12], fill=c, outline=(0, 0, 0)) for k, c in
                                                   enumerate([(255, 240, 100), (255, 170, 200), (160, 230, 255)])]),
        "sel": ((70, 90, 110, 255), lambda d: (d.rounded_rectangle([42, 34, 86, 108], 10, fill=(240, 240, 240)), d.rectangle([42, 22, 86, 38], fill=(160, 160, 170)),
                                                d.text((52, 60), "SEL", font=font(FONT_TITLE, 18), fill=(40, 60, 160)))),
        "banane": ((40, 120, 80, 255), lambda d: (d.arc([20, 10, 110, 100], 30, 150, fill=(255, 220, 40), width=22),)),
        "buzzer": ((50, 50, 60, 255), lambda d: (d.rounded_rectangle([30, 40, 98, 104], 12, fill=(30, 30, 30)), d.ellipse([46, 30, 82, 66], fill=(230, 40, 40)))),
        "confettis": ((120, 60, 200, 255), lambda d: [d.rectangle([x, y, x + 8, y + 8], fill=c) for x, y, c in
                                                      [(int(rng.integers(16, 104)), int(rng.integers(16, 104)), tuple(int(v) for v in rng.integers(80, 255, 3))) for _ in range(40)]]),
        "moustache": ((230, 200, 150, 255), lambda d: (d.chord([16, 40, 66, 90], 180, 360, fill=(50, 30, 20)), d.chord([62, 40, 112, 90], 180, 360, fill=(50, 30, 20)))),
        "sac_sport": ((40, 70, 130, 255), lambda d: (d.rounded_rectangle([18, 50, 110, 104], 18, fill=(30, 30, 40)), d.arc([40, 24, 88, 76], 180, 360, fill=(30, 30, 40), width=8),
                                                      d.rectangle([20, 70, 108, 76], fill=(255, 204, 34)))),
        "marqueur": ((60, 60, 70, 255), lambda d: (d.rounded_rectangle([54, 14, 74, 100], 6, fill=(240, 240, 240)), d.rectangle([54, 14, 74, 40], fill=(30, 60, 200)),
                                                    d.polygon([(56, 100), (72, 100), (64, 116)], fill=(30, 60, 200)))),
        "poisson": ((60, 150, 200, 255), lambda d: (d.ellipse([20, 44, 90, 84], fill=(190, 190, 200)), d.polygon([(86, 64), (112, 44), (112, 84)], fill=(190, 190, 200)),
                                                     d.ellipse([34, 56, 42, 64], fill=(0, 0, 0)))),
        "agrafeuse": ((160, 60, 60, 255), lambda d: (d.rounded_rectangle([20, 70, 108, 88], 6, fill=(40, 40, 40)), d.rounded_rectangle([24, 50, 104, 68], 8, fill=(200, 40, 40)))),
        "mug": ((90, 110, 130, 255), lambda d: (d.rounded_rectangle([34, 34, 86, 104], 8, fill=(250, 250, 250)), d.arc([74, 50, 104, 86], 270, 90, fill=(250, 250, 250), width=8),
                                                 d.text((40, 56), "N°1", font=font(FONT_TITLE, 22), fill=(220, 40, 40)))),
        "cafe": ((110, 70, 40, 255), lambda d: (d.rounded_rectangle([34, 40, 86, 104], 8, fill=(250, 250, 250)), d.ellipse([38, 36, 82, 50], fill=(90, 50, 20)))),
        "dossier": ((90, 90, 100, 255), lambda d: (d.rectangle([22, 30, 106, 100], fill=(240, 200, 90)), d.rectangle([22, 24, 60, 34], fill=(240, 200, 90)))),
        "chapeau": ((90, 50, 50, 255), lambda d: (d.ellipse([14, 76, 114, 100], fill=(30, 30, 30)), d.rounded_rectangle([36, 26, 92, 88], 8, fill=(30, 30, 30)),
                                                   d.rectangle([36, 70, 92, 80], fill=(200, 40, 40)))),
        "lunettes": ((40, 100, 160, 255), lambda d: (d.ellipse([16, 46, 60, 82], fill=(20, 20, 20)), d.ellipse([68, 46, 112, 82], fill=(20, 20, 20)), d.line([(60, 58), (68, 58)], fill=(20, 20, 20), width=6))),
        "cravate_or": ((60, 60, 80, 255), lambda d: (d.polygon([(54, 20), (74, 20), (68, 34), (82, 96), (64, 114), (46, 96), (60, 34)], fill=(255, 200, 40)),)),
        "talkie": ((50, 90, 60, 255), lambda d: (d.rounded_rectangle([42, 34, 86, 110], 8, fill=(30, 30, 30)), d.rectangle([70, 12, 76, 36], fill=(30, 30, 30)), d.rectangle([50, 46, 78, 70], fill=(120, 200, 120)))),
        "klaxon": ((200, 60, 40, 255), lambda d: (d.polygon([(30, 52), (70, 40), (100, 22), (100, 106), (70, 88), (30, 76)], fill=(250, 210, 40)), d.ellipse([16, 46, 44, 82], fill=(240, 60, 60)),
                                                   d.arc([96, 30, 124, 98], 300, 60, fill=(255, 255, 255), width=5))),
        "poil_gratter": ((150, 90, 160, 255), lambda d: [d.line([(x, y), (x + 8, y - 14)], fill=(255, 230, 120), width=4) for x, y in
                                                         [(int(rng.integers(16, 100)), int(rng.integers(30, 112))) for _ in range(26)]]),
        "cafard": ((220, 200, 160, 255), lambda d: (d.ellipse([38, 30, 90, 104], fill=(80, 45, 25)), d.ellipse([50, 18, 78, 40], fill=(60, 35, 20)),
                                                    [d.line([(40 + (k % 2) * 48, 46 + (k // 2) * 22), (20 + (k % 2) * 88, 40 + (k // 2) * 26)], fill=(50, 30, 15), width=4) for k in range(6)],
                                                    d.line([(58, 20), (40, 4)], fill=(50, 30, 15), width=3), d.line([(70, 20), (88, 4)], fill=(50, 30, 15), width=3))),
        "boule_puante": ((90, 140, 60, 255), lambda d: (d.ellipse([34, 44, 94, 104], fill=(170, 210, 90)), d.arc([30, 10, 60, 50], 180, 360, fill=(120, 200, 60), width=6),
                                                         d.arc([66, 4, 100, 44], 180, 360, fill=(120, 200, 60), width=6))),
        "serpent": ((60, 110, 200, 255), lambda d: (d.rounded_rectangle([30, 70, 98, 112], 8, fill=(220, 60, 60)), d.line([(64, 72), (50, 56), (78, 44), (52, 30)], fill=(80, 200, 80), width=12),
                                                     d.ellipse([42, 14, 66, 36], fill=(80, 200, 80)))),
        "pistolet_eau": ((50, 150, 220, 255), lambda d: (d.rounded_rectangle([20, 44, 96, 70], 12, fill=(255, 140, 30)), d.rounded_rectangle([36, 64, 58, 104], 8, fill=(255, 140, 30)),
                                                          d.ellipse([60, 26, 90, 50], fill=(80, 200, 255)), [d.ellipse([100 + k * 6, 52 - k, 106 + k * 6, 58 - k], fill=(160, 220, 255)) for k in range(3)])),
        "plante": ((70, 120, 70, 255), lambda d: (d.polygon([(40, 76), (88, 76), (80, 112), (48, 112)], fill=(180, 90, 50)), d.ellipse([34, 24, 74, 80], fill=(60, 170, 70)), d.ellipse([58, 18, 98, 76], fill=(40, 140, 60)))),
    }
    for name, (col, draw) in specs.items():
        img, d = base(col)
        draw(d)
        img.save(os.path.join(out, name + ".png"))


if __name__ == "__main__":
    carpet()
    wood()
    tiles("tile_floor", (214, 214, 206), (150, 150, 145), 4)
    tiles("tile_wall", (236, 240, 242), (190, 196, 200), 6)
    plain("wall_paint", (226, 222, 212), (238, 234, 226), 4)
    plain("concrete", (150, 150, 150), (185, 185, 182), 8)
    plain("metal", (150, 155, 162), (190, 195, 200), 32)
    plain("leather", (40, 28, 24), (68, 46, 38), 24)
    plain("plastic", (225, 225, 228), (240, 240, 242), 4, False)
    fabric()
    ceiling()
    cardboard()
    paper()
    keyboard()
    whiteboard()
    poster("synergy", (30, 40, 70), "SYNERGIE", "Ensemble, on va plus\nloin. Ou plus tard.")
    poster("coffee", (110, 60, 30), "CAFÉ", "Le café ne résout rien.\nMais il essaie.")
    poster("team", (20, 110, 90), "TEAM", "Il n'y a pas de « je »\ndans « équipe ».")
    poster("boss", (140, 30, 40), "EMPLOYÉ", "du mois : personne.\nEncore.")
    poster("safety", (220, 140, 20), "SÉCURITÉ", "Sol glissant =\nchute probable.", (30, 30, 30), (255, 255, 255))
    notice_board()
    meeting_sign("sign_meeting_ok", "Réunion d'équipe\n10h30 - Salle Synergie\nPrésence obligatoire")
    meeting_sign("sign_meeting_fake", "Réunion d'équipe\nREPORTÉE à 16h\n(pas de panique)")
    screens()
    skyline()
    logo_corp()
    icons()
    print("textures:", len(os.listdir(OUT)))
