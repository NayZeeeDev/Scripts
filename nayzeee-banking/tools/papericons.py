"""Inventory pictures for the printed papers: a receipt, a statement and a credit report,
in the same palette as the cards (off-white stock, dark ink, the brand teal).

    pip install pillow
    python3 papericons.py           # writes ../install/images/bank_receipt.png and the other two
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

from logo import BRAND, NAME, badge, font, spaced

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'install', 'images')

SIZE, SS = 256, 4
PAPER = (246, 244, 239, 255)
INK = (22, 25, 27, 255)
SOFT = (150, 154, 158, 255)
HAIR = (214, 212, 206, 255)
RED = (184, 38, 43, 255)


def s(v):
    return int(v * SS)


def sheet(w, h, torn=False):
    """A blank sheet, w x h at final scale, with a faint top-lit gradient."""
    img = Image.new('RGBA', (s(w), s(h)), 0)
    dr = ImageDraw.Draw(img)
    if torn:
        tooth = s(9)
        pts = [(0, 0), (s(w), 0), (s(w), s(h) - tooth)]
        n = int(s(w) / tooth)
        for i in range(n, -1, -1):
            x = i * s(w) / n
            pts.append((x, s(h) - (tooth if i % 2 == 0 else 0)))
        pts.append((0, s(h) - tooth))
        dr.polygon(pts, fill=PAPER)
    else:
        dr.rounded_rectangle((0, 0, s(w) - 1, s(h) - 1), s(3), fill=PAPER)
    # light from the top: a touch brighter there, a touch duller at the foot
    shade = Image.new('L', img.size, 0)
    for y in range(img.size[1]):
        shade.paste(int(28 * y / img.size[1]), (0, y, img.size[0], y + 1))
    dark = Image.new('RGBA', img.size, (60, 50, 30, 255))
    dark.putalpha(Image.composite(shade, Image.new('L', img.size, 0), img.getchannel('A')))
    img.alpha_composite(dark)
    return img


def lines(dr, x, y, w, rows, gap, widths, fill=HAIR, thick=4):
    for i in range(rows):
        lw = w * widths[i % len(widths)]
        dr.rounded_rectangle((s(x), s(y + i * gap), s(x + lw), s(y + i * gap) + s(thick)), s(thick) // 2, fill=fill)


def mark(img, x, y, d):
    b = badge(s(d), ss=1)
    img.alpha_composite(b, (s(x), s(y)))


def receipt():
    w, h = 112, 196
    p = sheet(w, h, torn=True)
    dr = ImageDraw.Draw(p)
    mark(p, w / 2 - 11, 12, 22)
    spaced(dr, (s(w / 2), s(44)), 'RECEIPT', font(s(8), 700), INK, s(1.4), 'mm')
    dr.line((s(12), s(54), s(w - 12), s(54)), fill=SOFT, width=s(1))
    spaced(dr, (s(w / 2), s(74)), '+$2 450', font(s(17), 700), BRAND + (255,), 0, 'mm')
    lines(dr, 24, 88, w - 48, 1, 0, [1], fill=SOFT, thick=3)
    for i in range(5):
        yy = 104 + i * 11
        dr.rounded_rectangle((s(14), s(yy), s(14 + 28), s(yy + 3)), s(1.5), fill=HAIR)
        dr.rounded_rectangle((s(w - 14 - 22 - (i % 3) * 6), s(yy), s(w - 14), s(yy + 3)), s(1.5), fill=SOFT)
    # barcode
    x = 18
    i = 0
    while x < w - 18:
        bw = (1, 2, 1, 3, 1, 2)[i % 6]
        dr.rectangle((s(x), s(164), s(x + bw), s(180)), fill=INK)
        x += bw + (1, 2, 1)[i % 3] + 0.5
        i += 1
    return p, -7


def statement():
    w, h = 150, 196
    p = sheet(w, h)
    dr = ImageDraw.Draw(p)
    mark(p, 12, 12, 20)
    spaced(dr, (s(38), s(22)), NAME, font(s(8), 800), INK, s(1), 'lm')
    spaced(dr, (s(w - 12), s(22)), 'STATEMENT', font(s(5.5), 600), BRAND + (255,), s(1), 'rm')
    dr.rectangle((s(12), s(38), s(w - 12), s(39.5)), fill=INK)
    # the four summary boxes, the last one tinted
    bw = (w - 24 - 9) / 4
    for i in range(4):
        x0 = 12 + i * (bw + 3)
        dr.rounded_rectangle((s(x0), s(46), s(x0 + bw), s(70)), s(2),
                             fill=(225, 241, 239, 255) if i == 3 else (236, 234, 228, 255))
        dr.rounded_rectangle((s(x0 + 4), s(51), s(x0 + 14), s(53)), s(1), fill=SOFT)
        dr.rounded_rectangle((s(x0 + 4), s(58), s(x0 + bw - 6), s(63)), s(1.5),
                             fill=BRAND + (255,) if i == 1 else RED if i == 2 else INK)
    # the table
    dr.rectangle((s(12), s(82), s(w - 12), s(83)), fill=INK)
    for i in range(9):
        yy = 90 + i * 11
        if i % 2:
            dr.rectangle((s(12), s(yy - 3), s(w - 12), s(yy + 6)), fill=(240, 238, 232, 255))
        dr.rounded_rectangle((s(14), s(yy), s(30), s(yy + 3)), s(1.5), fill=SOFT)
        dr.rounded_rectangle((s(36), s(yy), s(36 + 34 + (i * 13) % 26), s(yy + 3)), s(1.5), fill=HAIR if i % 2 == 0 else (205, 203, 197, 255))
        col = BRAND + (255,) if i % 3 == 0 else RED
        dr.rounded_rectangle((s(w - 52), s(yy), s(w - 38), s(yy + 3)), s(1.5), fill=col)
        dr.rounded_rectangle((s(w - 32), s(yy), s(w - 14), s(yy + 3)), s(1.5), fill=INK)
    lines(dr, 40, 186, w - 80, 1, 0, [1], fill=HAIR, thick=3)
    return p, 4


def credit():
    w, h = 150, 196
    p = sheet(w, h)
    dr = ImageDraw.Draw(p)
    mark(p, 12, 12, 20)
    spaced(dr, (s(38), s(22)), NAME, font(s(8), 800), INK, s(1), 'lm')
    spaced(dr, (s(w - 12), s(22)), 'CREDIT REPORT', font(s(5.5), 600), BRAND + (255,), s(0.8), 'rm')
    dr.rectangle((s(12), s(38), s(w - 12), s(39.5)), fill=INK)
    # the score ring
    cx, cy, r = 44, 74, 24
    dr.ellipse((s(cx - r), s(cy - r), s(cx + r), s(cy + r)), outline=(220, 232, 230, 255), width=s(5))
    dr.arc((s(cx - r), s(cy - r), s(cx + r), s(cy + r)), 135, 135 + 270 * 0.78, fill=BRAND + (255,), width=s(5))
    spaced(dr, (s(cx), s(cy - 2)), '712', font(s(14), 700), INK, 0, 'mm')
    spaced(dr, (s(cx), s(cy + 10)), 'GOOD', font(s(5), 600), BRAND + (255,), s(0.8), 'mm')
    for i in range(3):
        dr.rounded_rectangle((s(80), s(58 + i * 12), s(80 + 50 - i * 10), s(61 + i * 12)), s(1.5), fill=SOFT if i == 0 else HAIR)
    # the gauge
    gy = 110
    stops = [(229, 72, 77), (229, 121, 58), (229, 165, 10), (124, 195, 106), BRAND]
    gw = w - 24
    for x in range(s(gw)):
        t = x / s(gw) * (len(stops) - 1)
        a, b = stops[int(t)], stops[min(len(stops) - 1, int(t) + 1)]
        f = t - int(t)
        col = tuple(int(a[k] + (b[k] - a[k]) * f) for k in range(3)) + (255,)
        dr.line((s(12) + x, s(gy), s(12) + x, s(gy + 4)), fill=col)
    gx = 12 + gw * 0.82
    dr.rounded_rectangle((s(gx - 1), s(gy - 3), s(gx + 1), s(gy + 7)), s(1), fill=INK)
    # the factors, with their dots
    for i, dot in enumerate([BRAND, BRAND, (229, 165, 10), (229, 72, 77), BRAND]):
        yy = 128 + i * 11
        dr.ellipse((s(14), s(yy - 1), s(19), s(yy + 4)), fill=dot + (255,))
        dr.rounded_rectangle((s(25), s(yy), s(25 + 40 + (i * 9) % 20), s(yy + 3)), s(1.5), fill=SOFT)
        dr.rounded_rectangle((s(w - 34), s(yy), s(w - 14), s(yy + 3)), s(1.5), fill=HAIR)
    # the little history line
    pts = [(14 + i * (gw - 4) / 7, 186 - v) for i, v in enumerate([3, 6, 5, 9, 8, 12, 14, 16])]
    dr.line([(s(x), s(y)) for x, y in pts], fill=BRAND + (255,), width=s(1.6), joint='curve')
    return p, -4


def place(p, angle, out):
    """Rotate the sheet a little, drop a soft shadow, fit it to the icon."""
    big = Image.new('RGBA', (s(SIZE), s(SIZE)), 0)
    rot = p.rotate(angle, resample=Image.BICUBIC, expand=True)
    scale = min(s(SIZE - 24) / rot.width, s(SIZE - 24) / rot.height, 1)
    if scale < 1:
        rot = rot.resize((int(rot.width * scale), int(rot.height * scale)), Image.LANCZOS)
    x, y = (big.width - rot.width) // 2, (big.height - rot.height) // 2
    sh = Image.new('RGBA', big.size, 0)
    a = Image.new('L', big.size, 0)
    a.paste(rot.getchannel('A').point(lambda v: v * 110 // 255), (x, y + s(5)))
    sh.putalpha(a.filter(ImageFilter.GaussianBlur(s(6))))
    big.alpha_composite(sh)
    big.alpha_composite(rot, (x, y))
    big.resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (('bank_receipt', receipt), ('bank_statement', statement), ('credit_report', credit)):
        p, angle = fn()
        place(p, angle, os.path.join(OUT, name + '.png'))
        print(name + '.png')
