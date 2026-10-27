#!/usr/bin/env python3
"""Inventory images of the record items, the CarPlay unit and the phone app icon.

    python3 tools/item_images.py                         # everything (about 35 min on a 4-core CPU)
    python3 tools/item_images.py --only record vinyl_21 carplay icon
    python3 tools/item_images.py --covers out/previews/covers.png      # only the cover/label art sheet (fast)
    python3 tools/item_images.py --quality draft --out /tmp/img        # quick look somewhere else

Writes (512 x 512 transparent PNG unless noted) into nayzeee-speaker/:
    install/images/vinyl_record.png      generic record half out of a plain nayzeee sleeve
    install/images/vinyl_<key>.png       one per record in vinyls.lua (Config.Vinyls): record half out of its
                                         sleeve; sleeve + label colourway derived from the key, album title and
                                         artist printed in Lexend (no real album art)
    install/images/nayzeee_carplay.png   models/nayzeee_carplay_unit.py (image-only model)
    html/phone/icon.png                  256 x 256 phone app icon (drawn in 2D, no render)

The 3D images are rendered with render.py's renderer at 1024 px (one Chromium session for all of them) and
downsampled with premultiplied alpha, so edges never get halos.  One camera and light rig for every item
(3/4 view from the front right, like the speaker images), the prop about 80 % of the frame, soft contact
shadow.  Cover / label art only exists in this process (textures img_cover_<key> / img_label_<key>); it is
never written into the game texture dictionary.  Records are read from vinyls.lua with a small parser:
add a record there, rerun this tool, and its image appears.
"""
from __future__ import annotations

import argparse
import colorsys
import dataclasses
import hashlib
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

import models  # noqa: E402
import render as R  # noqa: E402
from lib import glb, materials as mats, textures as tx  # noqa: E402

RESOURCE = os.path.normpath(os.path.join(ROOT, "..", "nayzeee-speaker"))
VINYLS = os.path.join(RESOURCE, "vinyls.lua")
CACHE = os.path.join(ROOT, "cache", "images")

# one product camera for every item (yaw 35 = front + the viewer's-right side, like the speaker images)
CAMERA = {"yaw": 32.0, "pitch": 16.0, "fov": 30.0, "margin": 0.085, "shadow": 0.75}
EXPOSURE = 1.25
RECORD_OUT = -0.205          # sleeve-local x of the record centre: the label just clears the open edge
SLEEVE_LEAN = 8.0            # degrees the sleeve leans back


# --------------------------------------------------------------------------- vinyls.lua
def read_vinyls(path: str = VINYLS) -> list:
    """[{key, artist, album, year, genre}] in file order, from Config.Vinyls (string fields only)."""
    src = open(path, encoding="utf-8").read()
    src = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)                  # block comments
    src = re.sub(r"--[^\n]*", "", src)                                   # line comments
    out = []
    heads = list(re.finditer(r"\[\s*(['\"])([a-z0-9_]+)\1\s*\]\s*=\s*\{", src))
    for i, m in enumerate(heads):
        body = src[m.end(): heads[i + 1].start() if i + 1 < len(heads) else len(src)]
        body = body.split("tracks", 1)[0]

        def field(name):
            f = re.search(r"\b" + name + r"\s*=\s*(\"((?:[^\"\\]|\\.)*)\"|'((?:[^'\\]|\\.)*)'|(\d+))", body)
            if not f:
                return None
            v = f.group(2) if f.group(2) is not None else f.group(3) if f.group(3) is not None else f.group(4)
            return v.replace("\\'", "'").replace('\\"', '"')
        rec = {"key": m.group(2), "artist": field("artist") or "", "album": field("album") or m.group(2),
               "year": field("year"), "genre": field("genre")}
        out.append(rec)
    return out


# --------------------------------------------------------------------------- colourways
def _hls(h, l, s):
    return np.array(colorsys.hls_to_rgb((h % 360) / 360.0, l, s))


def _lum(c):
    c = np.asarray(c, float)
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return float(lin @ [0.2126, 0.7152, 0.0722])


def _contrast(a, b):
    la, lb = sorted((_lum(a), _lum(b)))
    return (lb + 0.05) / (la + 0.05)


def palette(key: str) -> dict:
    """Deterministic colourway for a record key: background gradient, two accents, text inks, layout."""
    h = hashlib.sha1(key.encode("utf-8")).digest()
    hue = ((h[0] << 8) | h[1]) / 65535.0 * 360.0
    mode = ("dark", "vivid", "light", "dark", "vivid")[h[2] % 5]
    shift = (150.0, 40.0, 190.0, -50.0, 110.0)[h[4] % 5]
    hue2 = hue + shift
    if mode == "dark":
        bg = (_hls(hue, 0.17, 0.42), _hls(hue + 8, 0.085, 0.40))
        acc, acc2 = _hls(hue2, 0.60, 0.80), _hls(hue, 0.52, 0.62)
    elif mode == "vivid":
        bg = (_hls(hue, 0.50, 0.70), _hls(hue + 14, 0.36, 0.72))
        acc, acc2 = _hls(hue2, 0.86, 0.70), _hls(hue2, 0.20, 0.55)
    else:
        bg = (_hls(hue, 0.91, 0.42), _hls(hue + 6, 0.83, 0.38))
        acc, acc2 = _hls(hue2, 0.50, 0.78), _hls(hue, 0.30, 0.55)
    white, black = np.array([0.95, 0.957, 0.96]), np.array([0.07, 0.078, 0.086])
    mid = (bg[0] + bg[1]) / 2
    ink = white if _contrast(mid, white) >= _contrast(mid, black) else black
    sub = ink * 0.72 + mid * 0.28
    # the label: accent colour, its own ink
    lab = acc
    lab_ink = white if _contrast(lab, white) >= _contrast(lab, black) else black
    return {"hue": hue, "mode": mode, "layout": h[3] % 4, "bg": bg, "acc": acc, "acc2": acc2, "ink": ink,
            "sub": sub, "label": lab, "label_ink": lab_ink, "seed": int.from_bytes(h[5:9], "little")}


def _c8(c, a=255):
    c = np.clip(np.asarray(c, float), 0, 1)
    return (int(c[0] * 255 + 0.5), int(c[1] * 255 + 0.5), int(c[2] * 255 + 0.5), a)


# --------------------------------------------------------------------------- type helpers
def _fit_lines(text: str, max_w: float, max_size: float, max_lines: int, weight: int, max_h: float):
    """Largest font size (<= max_size) at which ``text`` wraps into <= max_lines lines of <= max_w px,
    the block staying <= max_h px tall -> (size, lines)."""
    words = text.split()
    size = max_size
    while size > 6:
        lines, cur = [], ""
        ok = True
        for w in words:
            t = (cur + " " + w).strip()
            if tx.text_length(t, size, weight) <= max_w:
                cur = t
            else:
                if cur:
                    lines.append(cur)
                cur = w
                if tx.text_length(w, size, weight) > max_w:
                    ok = False
                    break
        if cur:
            lines.append(cur)
        if ok and len(lines) <= max_lines and len(lines) * size * 1.08 <= max_h:
            return size, lines
        size *= 0.94
    return size, [text]


def _fit_size(text: str, max_w: float, size: float, weight: int, tracking: float = 0.0) -> float:
    while size > 6 and tx.text_length(text, size, weight, tracking) > max_w:
        size *= 0.95
    return size


# --------------------------------------------------------------------------- cover art
def _gradient(S, top, bottom, seed):
    yy = np.linspace(0, 1, S)[:, None]
    c = tx.lerp_colors(np.repeat(yy, S, axis=1), [(0.0, top), (1.0, bottom)])
    g = tx.blur(tx.white(S, S, seed % 997), 0.8) * 0.012 + tx.fbm(S, S, 3, 4, seed=seed % 991) * 0.012
    return np.clip(c + g[:, :, None], 0, 1)


def _to_img(rgb):
    S = rgb.shape[0]
    return Image.fromarray((np.dstack([rgb, np.ones(rgb.shape[:2])]) * 255 + 0.5).astype(np.uint8), "RGBA")


def _art_orbit(img, S, p, r):
    """Big accent disc with ring lines, partly off the top-right edge."""
    d = ImageDraw.Draw(img)
    cx, cy, rad = S * r.uniform(0.62, 0.74), S * r.uniform(0.26, 0.34), S * r.uniform(0.34, 0.40)
    d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=_c8(p["acc"]))
    for k in range(1, 9):
        rr = rad * (1 + 0.075 * k)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=_c8(p["acc"], int(150 - 14 * k)), width=max(2, S // 300))
    rr = rad * 0.32
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=_c8(p["acc2"]))
    sx, sy = cx - rad * 1.25, cy + rad * 0.95
    d.ellipse([sx - S * 0.03, sy - S * 0.03, sx + S * 0.03, sy + S * 0.03], fill=_c8(p["acc2"]))


def _art_bands(img, S, p, r):
    """Three diagonal bands crossing the upper part."""
    d = ImageDraw.Draw(img)
    cols = (p["acc"], p["acc2"], p["ink"])
    base = S * r.uniform(-0.05, 0.10)
    for k, col in enumerate(cols):
        off = base + S * 0.17 * k
        wd = S * (0.10 if k < 2 else 0.035)
        d.polygon([(off, S * 0.66), (off + wd, S * 0.66), (off + wd + S * 0.62, -S * 0.02), (off + S * 0.62, -S * 0.02)],
                  fill=_c8(col, 255 if k < 2 else 200))


def _art_halftone(img, S, p, r):
    """Halftone sun: a dot grid whose dots grow toward a centre."""
    d = ImageDraw.Draw(img)
    cx, cy = S * r.uniform(0.55, 0.70), S * r.uniform(0.30, 0.40)
    step = S / 26
    for j in range(-1, 20):
        for i in range(-1, 28):
            x, y = (i + 0.5 * (j % 2)) * step, j * step
            if y > S * 0.64:
                continue
            dist = math.hypot(x - cx, y - cy) / (S * 0.42)
            rad = step * 0.46 * max(0.0, 1.0 - dist)
            if rad > 0.6:
                col = p["acc"] if dist < 0.55 else p["acc2"]
                d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=_c8(col))


def _art_letter(img, S, p, r, title):
    """A huge first letter / digit of the album, cropped by the frame, with a stripe."""
    d = ImageDraw.Draw(img)
    ch = next((c for c in title if c.isalnum()), "N").upper()
    size = S * 0.92
    tx.draw_text(d, (S * 0.70, S * 0.30), ch, size, 800, _c8(p["acc"]), "mm")
    d.rectangle([0, S * 0.555, S, S * 0.575], fill=_c8(p["acc2"]))


def cover_art(rec: dict, p: dict, S: int = 1024) -> np.ndarray:
    """Square sleeve front (RGB 0..1): abstract art in the key's colourway + Lexend type, no real album art.
    The art fills the top of the sleeve and stops above the type block, so the title is always clean."""
    ss = 2
    W = S * ss
    r = np.random.default_rng(p["seed"])
    img = _to_img(_gradient(W, p["bg"][0], p["bg"][1], p["seed"]))
    # type block (bottom left): artist (caps, tracked), album title (big), year / genre line
    margin = W * 0.065
    max_w = W - 2 * margin
    size, lines = _fit_lines(rec["album"], max_w, W * 0.125, 3, 700, W * 0.30)
    art_txt = rec["artist"].upper()
    asz = _fit_size(art_txt, max_w, W * 0.036, 600, 0.16)
    y_meta = W * 0.905
    y_last = y_meta - W * 0.050
    y_artist = y_last - (len(lines) - 1) * size * 1.06 - size * 1.06 - W * 0.012
    text_top = y_artist - asz * 1.1
    # art layer, clipped above the type block
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    layout = p["layout"]
    if layout == 0:
        _art_orbit(layer, W, p, r)
    elif layout == 1:
        _art_bands(layer, W, p, r)
    elif layout == 2:
        _art_halftone(layer, W, p, r)
    else:
        _art_letter(layer, W, p, r, rec["album"])
    cut = int(text_top - W * 0.035)
    la = np.asarray(layer).copy()
    la[cut:, :, 3] = 0
    img.alpha_composite(Image.fromarray(la, "RGBA"))
    d = ImageDraw.Draw(img)
    d.rectangle([margin, cut - W * 0.004, W - margin, cut], fill=_c8(p["acc"], 255))
    ink, sub = _c8(p["ink"]), _c8(p["sub"])
    # brand + format row at the top
    tx.draw_mark(img, W * 0.065, W * 0.06, W * 0.062, "white" if p["ink"][0] > 0.5 else "ink")
    d = ImageDraw.Draw(img)
    meta = " · ".join(x for x in (rec.get("year"), (rec.get("genre") or "").upper()) if x)
    tx.draw_text(d, (margin, y_meta), meta, W * 0.024, 500, sub, "ls", 0.22)
    y = y_last
    for ln in reversed(lines):
        tx.draw_text(d, (margin - size * 0.04, y), ln, size, 700, ink, "ls")
        y -= size * 1.06
    acc_ok = _contrast(p["acc"], (p["bg"][0] + p["bg"][1]) / 2) >= 2.6
    tx.draw_text(d, (margin, y_artist), art_txt, asz, 600, _c8(p["acc"] if acc_ok else p["ink"]), "ls", 0.16)
    # thin rule at the very bottom + a tiny nayzeee records credit
    d.rectangle([margin, W * 0.945, W - margin, W * 0.947], fill=_c8(p["sub"], 255))
    tx.draw_text(d, (W - margin, W * 0.968), "NAYZEEE RECORDS", W * 0.017, 600, sub, "rm", 0.3)
    tx.draw_text(d, (margin, W * 0.968), "33 RPM  ·  STEREO", W * 0.017, 600, sub, "lm", 0.3)
    return tx.finish(img, ss)[:, :, :3]


def cover_generic(S: int = 1024) -> np.ndarray:
    """Plain nayzeee sleeve (the generic record item): dark, teal rings, the mark and the wordmark."""
    ss = 2
    W = S * ss
    img = _to_img(_gradient(W, tx.hex_rgb("#121517"), tx.hex_rgb("#07080a"), 4242))
    d = ImageDraw.Draw(img)
    cx, cy = W * 0.5, W * 0.43
    for k in range(14):
        rr = W * (0.10 + 0.024 * k)
        a = int(200 - 12 * k)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=_c8(tx.hex_rgb(tx.TEAL), max(a, 30)), width=max(2, W // 400))
    rr = W * 0.075
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=_c8(tx.hex_rgb(tx.TEAL)))
    tx.draw_mark(img, cx - W * 0.095, cy - W * 0.095, W * 0.19, "color")
    d = ImageDraw.Draw(img)
    tx.draw_text(d, (W * 0.5, W * 0.83), "nayzeee", W * 0.13, 600, (242, 244, 245, 255), "mm")
    tx.draw_text(d, (W * 0.5, W * 0.915), "RECORDS  ·  33 RPM  ·  STEREO", W * 0.026, 600,
                 _c8(tx.hex_rgb(tx.TEAL)), "mm", 0.3)
    return tx.finish(img, ss)[:, :, :3]


def label_art(rec: dict, p: dict, S: int = 512) -> np.ndarray:
    """Centre label (inscribed circle = the 0.050 m label disc), in the key's accent colour."""
    ss = 2
    W = S * ss
    c, Rr = W / 2, W / 2
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64) + 0.5
    rr = np.hypot(xx - c, yy - c) / Rr
    ang = np.arctan2(yy - c, xx - c)
    base = np.asarray(p["label"])[None, None, :] * (0.94 + 0.05 * np.cos(2 * (ang - 0.6)) * rr)[:, :, None]
    img = _to_img(np.clip(base, 0, 1))
    d = ImageDraw.Draw(img)
    ink = p["label_ink"]
    for rad, wd, a in ((0.955, 0.010, 200), (0.90, 0.004, 90)):
        r0 = rad * Rr
        d.ellipse([c - r0, c - r0, c + r0, c + r0], outline=_c8(ink, a), width=max(1, int(wd * W)))
    ms = 0.15 * W
    tx.draw_mark(img, c - ms / 2, c - 0.70 * Rr, ms, "white" if ink[0] > 0.5 else "ink")
    d = ImageDraw.Draw(img)
    size, lines = _fit_lines(rec["album"], 1.30 * Rr, 0.11 * W, 2, 700, 0.26 * W)
    y = c + 0.30 * Rr
    for ln in lines:
        tx.draw_text(d, (c, y), ln, size, 700, _c8(ink), "mm")
        y += size * 1.05
    art = rec["artist"].upper()
    tx.draw_text(d, (c, y + 0.02 * W), art, _fit_size(art, 1.2 * Rr, 0.034 * W, 600, 0.14), 600, _c8(ink, 200), "mm", 0.14)
    for sx, t1, t2 in ((-1, "SIDE", "A"), (1, "33", "RPM")):
        tx.draw_text(d, (c + sx * 0.52 * Rr, c - 0.06 * Rr), t1, 0.032 * W, 600, _c8(ink, 170), "mm", 0.16)
        tx.draw_text(d, (c + sx * 0.52 * Rr, c + 0.05 * Rr), t2, 0.032 * W, 600, _c8(ink, 170), "mm", 0.16)
    hole = 0.0037 / 0.050 * Rr
    for k, col in ((2.4, _c8(p["label"] * 0.75)), (1.2, (6, 6, 7, 255))):
        d.ellipse([c - hole * k, c - hole * k, c + hole * k, c + hole * k], fill=col)
    return tx.finish(img, ss)[:, :, :3]


# --------------------------------------------------------------------------- GLBs for one record item
def _register(name: str, size, fn):
    if not tx.exists(name):
        tx.register(name, size, "DXT1", "color", "item image art (never exported)")(fn)


def _material_copy(src: str, name: str, texture: str):
    if name not in mats.names():
        m = mats.get(src)
        mats.register(dataclasses.replace(m, name=name, textures={**m.textures, "DiffuseSampler": texture}))
    return name


def record_glbs(tag: str, cover_fn, label_fn=None) -> tuple:
    """(sleeve.glb, vinyl.glb) with this item's cover (+ label) art -> cache/images."""
    os.makedirs(CACHE, exist_ok=True)
    _register(f"img_cover_{tag}", 1024, cover_fn)
    cover_mat = _material_copy("sleeve_cover_a", f"img_sleeve_cover_{tag}", f"img_cover_{tag}")
    sleeve = models.build("nayzeee_sleeve_a", 1.0)
    sp = [q.with_material(cover_mat, rescale_uvs=False) if q.name == "cover" else q for q in sleeve.parts]
    vinyl = models.build("nayzeee_vinyl", 1.0)
    vp = list(vinyl.parts)
    if label_fn is not None:
        _register(f"img_label_{tag}", 512, label_fn)
        lab_mat = _material_copy("vinyl_label", f"img_vinyl_label_{tag}", f"img_label_{tag}")
        vp = [q.with_material(lab_mat, rescale_uvs=False) if q.name.startswith("label") else q for q in vp]
    a = os.path.join(CACHE, f"{tag}_sleeve.glb")
    b = os.path.join(CACHE, f"{tag}_vinyl.glb")
    glb.write_glb(a, f"{tag}_sleeve", sp)
    glb.write_glb(b, f"{tag}_vinyl", vp)
    return a, b


def _opts(quality: str, size: int) -> dict:
    o = dict(R.DEFAULTS)
    o.update(CAMERA)
    o.update({"size": str(size), "quality": quality, "exposure": EXPOSURE, "overrides": R.load_overrides(None)})
    return o


def record_job(tag: str, glbs: tuple, quality: str, size: int) -> dict:
    parts = [{"model": "sleeve", "pos": [0, 0, 0], "rot": [SLEEVE_LEAN, 0, 0]},
             {"model": "vinyl", "pos": [RECORD_OUT, 0.0011, 0.1575], "rot": [90, 0, 0], "parent": 0}]
    mats_ = R.resolve_matrices(parts)
    return R.make_job(_opts(quality, size), [{"model": p["model"], "matrix": m} for p, m in zip(parts, mats_)],
                      list(glbs), tag)


def carplay_job(quality: str, size: int) -> dict:
    g = R.resolve_glb("nayzeee_carplay_unit", "fresh", log=lambda *a: None)
    o = _opts(quality, size)
    o.update({"yaw": 28.0, "pitch": 15.0})
    return R.make_job(o, [{"model": "nayzeee_carplay_unit", "matrix": np.eye(4)}], [g], "carplay")


# --------------------------------------------------------------------------- phone icon (2D)
def phone_icon(S: int = 256) -> Image.Image:
    """Rounded-square app icon: near-black tile, teal glow, a record with the nayzeee mark as its label."""
    ss = 4
    W = S * ss
    teal, teal_hi, teal_lo = (tx.hex_rgb(c) for c in (tx.TEAL, tx.TEAL_HI, tx.TEAL_LO))
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float64) / W
    base = tx.lerp_colors(yy, [(0.0, "#15181a"), (1.0, "#08090a")])
    cx, cy, Rr = 0.5, 0.5, 0.37
    r = np.hypot(xx - cx, yy - cy) / Rr
    glow = np.exp(-(((xx - 0.5) / 0.42) ** 2 + ((yy - 0.55) / 0.42) ** 2)) * 0.22
    halo = np.exp(-((r - 1.0) / 0.16) ** 2) * (r > 1.0) * 0.45
    col = base + (glow + halo)[:, :, None] * teal[None, None, :]
    # record: black disc, groove rings, sheen, teal rim light
    a = np.arctan2(yy - cy, xx - cx)
    disc = r < 1.0
    grooves = 0.5 + 0.5 * np.sin(r * 2 * math.pi * 9)
    sheen = np.clip(np.cos(2 * (a + 0.75)), 0, 1) ** 4 * 0.20
    vin = tx.hex_rgb("#0b0c0d")[None, None, :] + ((0.02 + 0.022 * grooves) * (1 + 3.0 * sheen))[:, :, None]
    vin = vin + (np.clip((r - 0.93) / 0.07, 0, 1) ** 2 * 0.55)[:, :, None] * teal[None, None, :]
    col = np.where(disc[:, :, None], vin, col)
    img = _to_img(np.clip(col, 0, 1))
    d = ImageDraw.Draw(img)
    # label: teal gradient disc with the mark (the mark IS the label)
    lr = Rr * 0.56 * W
    lab = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    lab_rgb = tx.lerp_colors(np.clip((xx - 0.5) * 0.9 + (yy - 0.5) * 0.9 + 0.5, 0, 1),
                             [(0.0, teal_hi), (1.0, teal_lo)])
    lab_a = (np.hypot(xx - cx, yy - cy) * W < lr).astype(np.float64)
    lab = Image.fromarray((np.dstack([lab_rgb, lab_a]) * 255).astype(np.uint8), "RGBA")
    img.alpha_composite(lab)
    ms = lr * 1.18
    tx.draw_mark(img, W * cx - ms / 2, W * cy - ms / 2, ms, "ink")
    # rounded-square mask with a fine inner rim
    out = tx.finish(img, ss)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, W - 1], radius=W * 0.225, fill=255)
    rim = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([ss, ss, W - 1 - ss, W - 1 - ss], radius=W * 0.225 - ss,
                                          outline=(255, 255, 255, 26), width=2 * ss)
    rim_s = np.asarray(rim.reduce(ss), np.float64) / 255.0
    m = np.asarray(mask.reduce(ss), np.float64) / 255.0
    rgb = out[:, :, :3] * (1 - rim_s[:, :, 3:4]) + rim_s[:, :, :3] * rim_s[:, :, 3:4]
    res = np.dstack([rgb, m])
    return Image.fromarray((np.clip(res, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


# --------------------------------------------------------------------------- output
def downsample(arr: np.ndarray, size: int) -> Image.Image:
    """RGBA uint8 (straight alpha) -> size x size with premultiplied LANCZOS (no dark/bright fringes)."""
    im = Image.fromarray(arr, "RGBA")
    if im.size != (size, size):
        im = im.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    return im


def save(im: Image.Image, path: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = np.asarray(im).copy()
    a[a[:, :, 3] == 0, :3] = 0                       # no colour under fully transparent pixels
    Image.fromarray(a, "RGBA").save(path, optimize=True)
    print(f"wrote {path} ({os.path.getsize(path) // 1024} KB)")


def art_sheet(recs: list, path: str):
    cell = 256
    cols = 4
    items = [("record", cover_generic(512), tx.image("nayzeee_vinyl_label"))]
    for rec in recs:
        p = palette(rec["key"])
        items.append((rec["key"], cover_art(rec, p, 512), label_art(rec, p, 256)))
    rows = math.ceil(len(items) / cols)
    sheet = Image.new("RGB", (cols * (cell + 16) + 16, rows * (cell + 100) + 16), (21, 24, 26))
    d = ImageDraw.Draw(sheet)
    f = tx.fonts.pil_font(13, 500)
    for i, (k, cov, lab) in enumerate(items):
        x, y = 16 + (i % cols) * (cell + 16), 16 + (i // cols) * (cell + 100)
        sheet.paste(tx.to_pil(cov).resize((cell, cell), Image.LANCZOS), (x, y))
        lb = tx.to_pil(lab).resize((cell // 3, cell // 3), Image.LANCZOS)
        m = Image.new("L", lb.size, 0)
        ImageDraw.Draw(m).ellipse([0, 0, lb.size[0] - 1, lb.size[1] - 1], fill=255)
        sheet.paste(lb, (x + cell - lb.size[0], y + cell + 2), m)
        d.text((x, y + cell + 8), k, font=f, fill=(220, 224, 228))
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    sheet.save(path)
    print("wrote", path)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*", help="record | vinyl_<key> ... | carplay | icon (default: all)")
    ap.add_argument("--out", default=RESOURCE, help="resource folder to write into (default: nayzeee-speaker)")
    ap.add_argument("--quality", default="normal", choices=sorted(R.QUALITY))
    ap.add_argument("--render-size", type=int, default=1024)
    ap.add_argument("--covers", metavar="PNG", help="only write a sheet of every cover + label (no rendering)")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args(argv)
    recs = read_vinyls()
    if a.covers:
        art_sheet(recs, a.covers)
        return 0
    want = set(a.only) if a.only else None

    def wanted(name):
        return want is None or name in want

    img_dir = os.path.join(a.out, "install", "images")
    t0 = time.time()
    if wanted("icon"):
        save(phone_icon(256), os.path.join(a.out, "html", "phone", "icon.png"))
    jobs, outs = [], []
    if wanted("record"):
        jobs.append(record_job("record", record_glbs("record", lambda w, h: cover_generic(w)), a.quality, a.render_size))
        outs.append(os.path.join(img_dir, "vinyl_record.png"))
    for rec in recs:
        if not wanted(rec["key"]):
            continue
        p = palette(rec["key"])
        g = record_glbs(rec["key"], lambda w, h, r=rec, q=p: cover_art(r, q, w), lambda w, h, r=rec, q=p: label_art(r, q, w))
        jobs.append(record_job(rec["key"], g, a.quality, a.render_size))
        outs.append(os.path.join(img_dir, rec["key"] + ".png"))
    if wanted("carplay"):
        jobs.append(carplay_job(a.quality, a.render_size))
        outs.append(os.path.join(img_dir, "nayzeee_carplay.png"))
    if jobs:
        print(f"rendering {len(jobs)} image(s) at {a.render_size} px, quality {a.quality} ...")
        for (img, _), path in zip(R.run_jobs(jobs, a.verbose), outs):
            save(downsample(img, 512), path)
    print(f"done in {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
