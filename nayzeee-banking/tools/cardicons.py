"""Inventory icons for the bank cards: a 3D card, three-quarter view, soft studio shadow,
transparent background, 256 px. The face is drawn the same way the bank UI draws .bcard
(web/css/style.css), so the item in the inventory is the card you see in the app.

    pip install numpy pillow
    python3 cardicons.py [out_dir]       # default: ../install/images

Writes
    card_<item>.png              one per card type (the image set on the item itself)
    card_<item>_<skin>.png       one per type + skin, picked per card through metadata.image
    ../web/images/cards/…        the same cards, larger and cropped, for the bank UI and the ATM
    _sheet.png                   contact sheet of everything

Adding a skin: add it to Config.Cards.skins, give .bcard.<skin> a gradient in style.css and
phone/style.css, add the same colours to SKINS below, and run this again.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

# .bcard.<skin> in web/css/style.css: linear-gradient(150deg, c0 0%, c1 mid, c2 100%)
#   dark = text is dark on this skin (.bcard.chrome)
SKINS = {
    'teal':    dict(stops=[(0.00, '#0fd4c4'), (0.42, '#08afa2'), (1.00, '#046b63')], dark=False),
    'noir':    dict(stops=[(0.00, '#2a2f33'), (0.50, '#141719'), (1.00, '#050607')], dark=False),
    'chrome':  dict(stops=[(0.00, '#e9edf0'), (0.48, '#9aa3aa'), (1.00, '#4c5359')], dark=True),
    'crimson': dict(stops=[(0.00, '#f0666a'), (0.45, '#e5484d'), (1.00, '#7d1b1e')], dark=False),
}

# Config.CardTypes: item name -> (badge on the card, the skin its plain item image uses)
#   The badge matches cardFace() in web/js/app.js (credit kinds say CREDIT, secured says SECURED).
TYPES = {
    'card_debit':    ('DEBIT',    'teal'),
    'card_secured':  ('SECURED',  'noir'),
    'card_credit':   ('CREDIT',   'crimson'),
    'card_platinum': ('PLATINUM', 'chrome'),
}

FONT = os.path.join(HERE, 'Lexend.woff2')
W, H = 1712, 1080            # face texture, ISO card ratio (85.6 x 54 mm)
RADIUS = 66                  # 12px on the 150px-tall UI card, scaled
SS = 4                       # supersampling for the final 256 px icon
OUT = 256
UI_SIZE = 384                # the bank UI's copy, before cropping


def hex_rgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64)


def font(size, weight):
    try:
        f = ImageFont.truetype(FONT, size)
        f.set_variation_by_axes([weight])
        return f
    except Exception:
        for p in ('/usr/share/fonts/opentype/inter/Inter-Bold.otf',
                  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
        return ImageFont.load_default()


def css_gradient(w, h, deg, stops):
    """CSS linear-gradient(<deg>, ...) over a w x h box."""
    a = math.radians(deg)
    dx, dy = math.sin(a), -math.cos(a)
    length = abs(w * dx) + abs(h * dy)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    t = ((xs - w / 2) * dx + (ys - h / 2) * dy) / length + 0.5
    t = np.clip(t, 0, 1)
    out = np.zeros((h, w, 3))
    pos = [s[0] for s in stops]
    cols = [hex_rgb(s[1]) for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, pos, [col[c] for col in cols])
    return out


def rounded_mask(w, h, r, scale=1):
    m = Image.new('L', (w * scale, h * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * scale - 1, h * scale - 1), r * scale, fill=255)
    return m.resize((w, h), Image.LANCZOS) if scale > 1 else m


def face(skin, badge):
    """The card face, laid out like .bcard (padding 16/18, chip top-left, badge top-right,
    number in the middle, ACCOUNT NAME / EXPIRES along the bottom)."""
    sk = SKINS[skin]
    rgb = css_gradient(W, H, 150, sk['stops'])
    # .glare: linear-gradient(115deg, rgba(255,255,255,.22), transparent 46%)
    g = css_gradient(W, H, 115, [(0, '#ffffff'), (0.46, '#000000'), (1, '#000000')])[..., 0] / 255 * 0.22
    rgb = rgb * (1 - g[..., None]) + 255 * g[..., None]
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert('RGBA')

    layer = Image.new('RGBA', (W, H), 0)   # drawn on its own layer so the alphas blend
    d = ImageDraw.Draw(layer)
    ink = (11, 12, 13, 255) if sk['dark'] else (255, 255, 255, 255)
    sub = (0, 0, 0, 140) if sk['dark'] else (255, 255, 255, 184)
    px, py = 120, 108          # padding

    # EMV chip: a real-looking gold chip reads far better at 64 px than the UI's frosted square
    cw, ch = 236, 176
    chip = Image.new('RGBA', (cw, ch), 0)
    cg = css_gradient(cw, ch, 135, [(0, '#f3dc9a'), (0.5, '#c9a24f'), (1, '#8e6a26')])
    chip.paste(Image.fromarray(cg.astype(np.uint8)), (0, 0), rounded_mask(cw, ch, 30, 4))
    cd = ImageDraw.Draw(chip)
    line = (110, 80, 30, 200)
    for x in (cw * 0.33, cw * 0.67):
        cd.line((x, 18, x, ch - 18), fill=line, width=6)
    cd.line((18, ch / 2, cw * 0.33, ch / 2), fill=line, width=6)
    cd.line((cw * 0.67, ch / 2, cw - 18, ch / 2), fill=line, width=6)
    cd.rounded_rectangle((cw * 0.33, ch * 0.3, cw * 0.67, ch * 0.7), 14, outline=line, width=6)
    layer.alpha_composite(chip, (px, py + 20))

    # contactless waves next to the chip
    cx, cy = px + cw + 70, py + 20 + ch / 2
    for i, r in enumerate((34, 62, 90)):
        d.arc((cx - r, cy - r, cx + r, cy + r), -48, 48, fill=ink[:3] + (200,), width=13)

    # badge chip, top right (rgba(0,0,0,.25) fill, rgba(255,255,255,.35) edge in the UI)
    if badge:
        f = font(74, 700)
        tw = d.textlength(badge, font=f)
        bw, bh = tw + 90, 132
        x1, y1 = W - px, py
        fill = (0, 0, 0, 38) if sk['dark'] else (0, 0, 0, 64)
        edge = (0, 0, 0, 90) if sk['dark'] else (255, 255, 255, 96)
        d.rounded_rectangle((x1 - bw, y1, x1, y1 + bh), 34, fill=fill, outline=edge, width=5)
        d.text((x1 - bw / 2, y1 + bh / 2 + 2), badge, font=f, fill=ink, anchor='mm')

    # number: three masked groups as dots, the last four shown, all on one line
    f = font(136, 600)
    y = H * 0.585                     # baseline
    last = '4821'
    lw = d.textlength(last, font=f)
    shadow = (0, 0, 0, 0 if sk['dark'] else 80)
    d.text((W - px + 3, y + 5), last, font=f, fill=shadow, anchor='rs')
    d.text((W - px, y), last, font=f, fill=ink, anchor='rs')
    span = (W - 2 * px - lw) / 3
    r = 19
    for gi in range(3):
        for k in range(4):
            cx, cy = px + gi * span + r + k * (r * 2 + 16), y - 50
            d.ellipse((cx - r + 3, cy - r + 5, cx + r + 3, cy + r + 5), fill=shadow)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ink)

    # foot: labels + bars standing in for the name and date (unreadable at icon size anyway)
    fl = font(54, 400)
    by = H - py - 150
    d.text((px, by), 'ACCOUNT NAME', font=fl, fill=sub, anchor='lt')
    d.rounded_rectangle((px, by + 84, px + 560, by + 84 + 50), 25, fill=ink[:3] + (230,))
    d.text((W - px, by), 'EXPIRES', font=fl, fill=sub, anchor='rt')
    d.rounded_rectangle((W - px - 200, by + 84, W - px, by + 84 + 50), 25, fill=ink[:3] + (230,))

    img.alpha_composite(layer)
    img.putalpha(rounded_mask(W, H, RADIUS, 2))
    return img


# ── 3D ─────────────────────────────────────────────────────────────────────────────────────────
def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == 'x':
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == 'y':
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def perspective_coeffs(dst, src):
    """PIL PERSPECTIVE wants the map from output pixels back to texture pixels."""
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def project(pts, R, size, dist=5.2, zoom=1.0):
    p = pts @ R.T
    z = p[:, 2] + dist
    f = size * zoom * dist / 2.0
    return np.stack([size / 2 + p[:, 0] * f / z, size / 2 - p[:, 1] * f / z], 1)


def render(skin, badge, out=OUT):
    tex = face(skin, badge)
    size = out * SS
    aspect = W / H
    hw, hh = 1.0, 1.0 / aspect
    thick = 0.03
    # three-quarter view: leaned back, turned left, a touch of roll
    R = rot('z', 7) @ rot('x', -24) @ rot('y', -20)

    corners = np.array([[-hw, hh, 0], [hw, hh, 0], [hw, -hh, 0], [-hw, -hh, 0]])
    top = project(corners, R, size, zoom=0.86)
    back = project(corners + np.array([0, 0, thick * 2]), R, size, zoom=0.86)
    centre = top.mean(0)
    top += size / 2 - centre
    back += size / 2 - centre
    src = [(0, 0), (W, 0), (W, H), (0, H)]

    canvas = Image.new('RGBA', (size, size), 0)

    # soft contact shadow under the card
    sh = Image.new('L', (size, size), 0)
    off = np.array([size * 0.02, size * 0.055])
    ImageDraw.Draw(sh).polygon([tuple(p + off) for p in back], fill=150)
    sh = sh.filter(ImageFilter.GaussianBlur(size * 0.03))
    canvas.alpha_composite(Image.merge('RGBA', [Image.new('L', (size, size), 0)] * 3 + [sh]))

    # card edge: the face's own colours, darker, stacked between the back and the front
    edge_tex = tex.copy()
    ea = np.array(edge_tex).astype(np.float64)
    ea[..., :3] *= 0.55
    edge_tex = Image.fromarray(ea.astype(np.uint8))
    steps = 10
    for i in range(steps, 0, -1):
        q = back + (top - back) * (1 - i / steps)
        layer = edge_tex.transform((size, size), Image.PERSPECTIVE,
                                   perspective_coeffs([tuple(p) for p in q], src), Image.BICUBIC)
        canvas.alpha_composite(layer)

    front = tex.transform((size, size), Image.PERSPECTIVE,
                          perspective_coeffs([tuple(p) for p in top], src), Image.BICUBIC)
    canvas.alpha_composite(front)

    # thin specular rim along the top edge
    rim = Image.new('RGBA', (size, size), 0)
    ImageDraw.Draw(rim).line([tuple(top[0]), tuple(top[1])], fill=(255, 255, 255, 70), width=SS * 2)
    canvas.alpha_composite(rim)

    return canvas.resize((out, out), Image.LANCZOS)


def ui_image(skin, badge):
    """The same card for the bank UI: rendered larger and cropped tight, so it
    can sit in a list row or fill a preview without empty space around it."""
    img = render(skin, badge, UI_SIZE)
    box = img.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    if box:
        pad = 6
        box = (max(0, box[0] - pad), max(0, box[1] - pad),
               min(img.width, box[2] + pad), min(img.height, box[3] + pad))
        img = img.crop(box)
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'install', 'images')
    ui = os.path.join(HERE, '..', 'web', 'images', 'cards')
    os.makedirs(out, exist_ok=True)
    os.makedirs(ui, exist_ok=True)
    done = []
    for item, (badge, base) in TYPES.items():
        for skin in SKINS:
            icon = render(skin, badge)
            icon.save(os.path.join(out, f'{item}_{skin}.png'), optimize=True)
            done.append(icon)
            if skin == base:
                icon.save(os.path.join(out, f'{item}.png'), optimize=True)
            ui_image(skin, badge).save(os.path.join(ui, f'{item}_{skin}.png'), optimize=True)
            print('icon', f'{item}_{skin}')
    cols = len(SKINS)
    sheet = Image.new('RGBA', (cols * 260, (len(done) // cols) * 260), (24, 26, 28, 255))
    for i, icon in enumerate(done):
        sheet.alpha_composite(icon, ((i % cols) * 260 + 2, (i // cols) * 260 + 2))
    sheet.save(os.path.join(HERE, '_sheet.png'))


if __name__ == '__main__':
    main()
