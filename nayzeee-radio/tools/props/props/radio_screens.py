"""
Idle screen images of the radios (texture 'nzr_scr').

The complete model (nzr_<m>) shows this static image: what other players see on your radio. The
body model (nzr_<m>_body) carries a near-black placeholder that client/modules/screen.lua replaces with
the live DUI page (AddReplaceTexture('nzr_<m>_body', 'nzr_scr', 'nzr_rt', ...)).

One look per DUI skin (SPEC section 3), drawn to match html/dui/radio.html's palettes:
    px740  colour TFT behind dark blue-black glass, white + teal text          (handheld, 512 x 384)
    fx280  grey-green STN monochrome LCD, dark segments with ghost segments    (fieldpro, 512 x 256)
    mx905  black panel with green text                                         (military, 512 x 384)
Each shows the model code and a dim "-- --.--" readout. No NAYZEEE mark anywhere (Rule B).
"""
from __future__ import annotations

from PIL import Image, ImageDraw

from nzprops import font

from .screens import glass_glare, lcd_base, pixel_grid, seg_text, seg_width, soften, vignette

SKINS = {
    "px740": {"code": "PX-740", "px": (512, 384), "bg": (7, 10, 16), "glow": (22, 40, 58), "ink": (232, 238, 242),
              "accent": (22, 200, 190), "dim": (64, 84, 96)},
    "fx280": {"code": "FX-280", "px": (512, 256), "bg": (138, 152, 128), "glow": (170, 182, 150), "ink": (26, 34, 26),
              "accent": (26, 34, 26), "dim": (118, 132, 108)},
    "mx905": {"code": "MX-905", "px": (512, 384), "bg": (4, 7, 5), "glow": (10, 30, 16), "ink": (96, 236, 128),
              "accent": (60, 200, 96), "dim": (22, 64, 34)},
}


def _bars(d, x, y, h, n_on, color, dim, k=4, w=None):
    w = w or h * 0.22
    for i in range(k):
        bh = h * (i + 1) / k
        d.rectangle([x + i * w * 1.5, y + h - bh, x + i * w * 1.5 + w, y + h], fill=color if i < n_on else dim)


def _battery(d, x, y, w, h, frac, color, dim):
    lw = max(1, int(h * 0.12))
    d.rectangle([x, y, x + w, y + h], outline=color, width=lw)
    d.rectangle([x + w, y + h * 0.3, x + w + h * 0.18, y + h * 0.7], fill=color)
    inner = (w - lw * 4) * frac
    d.rectangle([x + lw * 2, y + lw * 2, x + lw * 2 + inner, y + h - lw * 2], fill=color if frac > 0 else dim)


def idle_screen(skin="px740", px=None, code=None):
    """Static standby image of a radio's screen in the given skin (PIL RGB image)."""
    sk = SKINS.get(skin, SKINS["px740"])
    w, h = px or sk["px"]
    s = w / 512.0
    code = code or sk["code"]
    img = lcd_base(w, h, sk["bg"], sk["glow"], 0.55 if skin != "fx280" else 0.35)
    d = ImageDraw.Draw(img)
    ink, acc, dim = sk["ink"], sk["accent"], sk["dim"]
    if skin == "fx280":
        # STN: status icons row, model code, big segment readout with ghost segments, unit tag
        ghost = tuple(int(c * 0.93) for c in sk["bg"])
        d.text((int(16 * s), int(14 * s)), code, font=font("label", 26 * s), fill=ink, anchor="lt")
        _bars(d, w - int(150 * s), int(16 * s), 22 * s, 0, ink, ghost)
        _battery(d, w - int(70 * s), int(17 * s), 44 * s, 20 * s, 0.7, ink, ghost)
        dh = int(h * 0.42)
        txt = "-- --.--"
        tw = seg_width(txt, dh)
        seg_text(d, (w - tw) / 2, h * 0.36, txt, dh, on=ink, ghost=ghost)
        d.text((int(16 * s), h - int(16 * s)), "MEM --", font=font("lcd", 30 * s), fill=ink, anchor="lb")
        d.text((w - int(16 * s), h - int(16 * s)), "MHz", font=font("lcd", 30 * s), fill=ink, anchor="rb")
        img = pixel_grid(img, pitch=max(2, int(round(3 * s))), strength=0.07, color=(90, 102, 84))
        img = vignette(soften(img, 0.5 * s), 0.18)
        return img
    # colour TFT (px740) / green phosphor-look panel (mx905)
    title_f = font("label", 22 * s)
    d.text((int(18 * s), int(16 * s)), code, font=title_f, fill=acc, anchor="lt")
    _bars(d, w - int(150 * s), int(16 * s), 22 * s, 0, acc, dim)
    _battery(d, w - int(74 * s), int(17 * s), 46 * s, 20 * s, 0.75, ink if skin == "px740" else acc, dim)
    d.line([(int(18 * s), int(52 * s)), (w - int(18 * s), int(52 * s))], fill=dim, width=max(1, int(2 * s)))
    big = font("mono-bold", 92 * s)
    d.text((w / 2, h * 0.47), "-- --.--", font=big, fill=dim if skin == "px740" else sk["dim"], anchor="mm")
    small = font("mono", 22 * s)
    d.text((w / 2, h * 0.47 + 66 * s), "STANDBY", font=small, fill=dim, anchor="mm")
    # slot rows (empty)
    for k in range(3):
        y = h - int((96 - k * 28) * s)
        d.text((int(22 * s), y), f"S{k + 1}", font=small, fill=dim, anchor="lm")
        d.line([(int(70 * s), y), (int(200 * s), y)], fill=dim, width=max(1, int(2 * s)))
    d.text((w - int(22 * s), h - int(24 * s)), "--:--", font=small, fill=dim, anchor="rm")
    if skin == "mx905":
        for gy in range(int(60 * s), h, max(4, int(16 * s))):
            d.line([(0, gy), (w, gy)], fill=(8, 20, 11), width=1)
        img = pixel_grid(img, pitch=max(2, int(round(3 * s))), strength=0.12)
    else:
        img = pixel_grid(img, pitch=max(2, int(round(2 * s))), strength=0.06)
    img = vignette(soften(img, 0.45 * s), 0.3)
    return glass_glare(img, 0.035)


def placeholder_screen(px=(512, 384)):
    """Near-black panel for the body model; the client swaps it for the live DUI texture."""
    return Image.new("RGB", tuple(px), (5, 6, 8))


__all__ = ["SKINS", "idle_screen", "placeholder_screen"]
