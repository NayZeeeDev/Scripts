"""The salon props: what the stylist holds while doing hair, built like the other Wig Snatch props.

    nz_sty_comb    rat-tail comb              nz_sty_brush   paddle brush       nz_sty_edge    edge brush
    nz_sty_needle  curved C-needle + thread   nz_sty_hook    crochet hook       nz_sty_iron    flat iron
    nz_sty_wand    curling wand               nz_sty_dryer   blow dryer         nz_sty_gel     braiding gel tub
    nz_sty_tin     edge control tin           nz_sty_mousse  foam mousse can    nz_sty_spray   spray bottle
    nz_sty_pack    a pack of braiding hair

Hand tools run along +Y with the grip at the origin (like the clippers); tubs, cans and bottles stand
on z = 0 along +Z (like the dye bottle). build.py adds these to the props ytyp, icons.py renders the
item icons from the same models (with each product's own label).
"""
import math
import numpy as np
from PIL import Image, ImageDraw

from mesh import merge, lathe, loft_y, box, rot, torus

TEAL = (8, 175, 162)
TEAL_HI = (15, 212, 196)
PINK = (236, 92, 160)
BLACK = (18, 19, 21)


def _h():
    import build
    return build


def solid_tex(rgb, w=128, h=128, amp=5, seed=3):
    b = _h()
    t = np.ones((h, w, 3)) * np.array(rgb, dtype=np.float64) + b.noise(w, h, 0.4, 1.2, seed)[..., None] * amp
    return b.to_img(t)


def atlas(parts, w=512, h=512):
    """parts: [(rect(u0,v0,u1,v1), rgb, amp)] -> texture. Like the other props, v is the image row (v = 0 at the top)."""
    b = _h()
    t = np.zeros((h, w, 3))
    for (u0, v0, u1, v1), rgb, amp in parts:
        b.fill(t, (u0, v0, u1, v1), rgb, b.noise(w, h, 0.4, 1.2, int(u0 * 100 + v0 * 10)), amp)
    return b.to_img(t)


def label_on(img, rect, lines, flip=True, bg=None):
    """Writes centred lines into rect (u0,v0,u1,v1 as image fractions). A lathe's v runs up the object while
    image rows run down, so lathe labels are drawn flipped (like the dye bottle)."""
    b = _h()
    W, H = img.size
    u0, v0, u1, v1 = rect
    pw, ph = int((u1 - u0) * W), int((v1 - v0) * H)
    panel = Image.new('RGBA', (pw, ph), (0, 0, 0, 0) if not bg else bg + (255,))
    d = ImageDraw.Draw(panel)
    y = ph * 0.14
    for text, size, rgb, weight in lines:
        ft = b.font(max(6, int(size)), weight)
        d.text((pw / 2, y), text, font=ft, fill=rgb + (255,), anchor='mt')
        y += size * 1.3
    if flip:
        panel = panel.transpose(Image.FLIP_TOP_BOTTOM)
    img.paste(panel, (int(u0 * W), int(v0 * H)), panel)
    return img


# ═════════════════════════════════════════════════════════════════════════════════════
def comb():
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 1), (28, 30, 33), 3)])
    tex = label_on(tex, (0.0, 0.35, 0.5, 0.65), [('NZ', 40, TEAL_HI, 800)], flip=False)
    spine = box((-0.0035, 0.0, -0.0013), (0.0095, 0.105, 0.0013), (0, 0, 0.5, 1))
    teeth = []
    for i in range(26):
        y = 0.004 + i * 0.0038
        teeth.append(box((-0.0145, y, -0.0009), (-0.0035, y + 0.0015, 0.0009), (0.5, 0, 1, 1)))
    tail = loft_y([(-0.105, 0.0006, 0.0006, 2, 0.003, 0), (-0.06, 0.0013, 0.0011, 2, 0.003, 0), (0.0, 0.0022, 0.0012, 2, 0.003, 0)],
                  10, (0.5, 0, 1, 1))
    return ('nz_sty_comb', merge([spine, tail] + teeth), tex, 25.0, ((35, 20), (215, 15), (110, 60)))


def brush():
    b = _h()
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 0.5), (36, 38, 42), 4), ((0.5, 0.5, 1, 1), TEAL, 6)])
    handle = loft_y([(-0.11, 0.008, 0.007, 2.2, 0, 0), (-0.06, 0.0105, 0.0085, 2.2, 0, 0), (-0.01, 0.009, 0.0075, 2.2, 0, 0)],
                    20, (0, 0, 0.5, 1), caps=[(0, (0, 0, 0.05, 0.05))])
    secs = []
    for i in range(12):
        a = i / 11
        y = -0.012 + a * 0.115
        w = 0.012 + 0.024 * math.sin(min(1, a * 1.4) * math.pi / 2) - 0.01 * max(0, a - 0.8) / 0.2
        secs.append((y, w, 0.007, 3.0, 0, 0))
    head = loft_y(secs, 28, (0, 0, 0.5, 1), caps=[(1, (0, 0.95, 0.05, 1))])
    cushion = box((-0.026, 0.008, 0.0065), (0.026, 0.094, 0.0085), (0.5, 0, 1, 0.5))
    bristles = []
    for r in range(9):
        for c in range(6):
            x = -0.021 + c * 0.0084
            y = 0.013 + r * 0.0094
            bristles.append(box((x - 0.0007, y - 0.0007, 0.0085), (x + 0.0007, y + 0.0007, 0.017), (0.5, 0.5, 1, 1)))
    return ('nz_sty_brush', merge([handle, head, cushion] + bristles), tex, 30.0, ((35, 30), (215, 15), (110, 70)))


def edge_brush():
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 1), (235, 238, 240), 4)])
    handle = loft_y([(-0.075, 0.0028, 0.0025, 2.4, 0, 0), (0.0, 0.0042, 0.0032, 2.4, 0, 0), (0.035, 0.0035, 0.003, 2.4, 0, 0)],
                    14, (0, 0, 0.5, 1), caps=[(0, (0, 0, 0.05, 0.05)), (1, (0, 0.95, 0.05, 1))])
    block = box((-0.004, 0.025, 0.003), (0.004, 0.036, 0.006), (0, 0, 0.5, 1))
    bristles = []
    for r in range(3):
        for c in range(4):
            x, y = -0.003 + c * 0.002, 0.027 + r * 0.004
            bristles.append(box((x - 0.0005, y - 0.0005, 0.006), (x + 0.0005, y + 0.0005, 0.0125), (0.5, 0, 1, 1)))
    comb = [box((-0.0035, -0.075 + i * 0.0035, -0.0008), (-0.0095, -0.074 + i * 0.0035, 0.0008), (0, 0, 0.5, 1)) for i in range(9)]
    return ('nz_sty_edge', merge([handle, block] + bristles + comb), tex, 20.0, ((35, 30), (215, 15), (110, 70)))


def needle():
    tex = atlas([((0, 0, 0.5, 1), (205, 210, 214), 3), ((0.5, 0, 1, 1), (214, 166, 58), 5)])
    arc = torus(0.022, 0.0008, 30, 8, (0, 0, 0.5, 1), a0=-20, a1=190).transformed(R=rot('x', 90), t=(0.0, 0.022, 0.0))
    eye = torus(0.0016, 0.0005, 12, 6, (0, 0, 0.5, 1)).transformed(t=(0.021, 0.0, 0.0))
    thread = loft_y([(0.0, 0.0005, 0.0005, 2, 0.022, 0), (-0.04, 0.0005, 0.0005, 2, 0.026, 0.006), (-0.09, 0.0005, 0.0005, 2, 0.018, -0.004)],
                    6, (0.5, 0, 1, 1))
    return ('nz_sty_needle', merge([arc, eye, thread]), tex, 15.0, ((35, 30), (215, 15), (110, 70)))


def hook():
    tex = atlas([((0, 0, 0.5, 1), (200, 205, 210), 3), ((0.5, 0, 1, 1), PINK, 6)])
    rod = loft_y([(-0.07, 0.0018, 0.0018, 2, 0, 0), (0.07, 0.0016, 0.0016, 2, 0, 0)], 10, (0, 0, 0.5, 1))
    tip = torus(0.0024, 0.0009, 10, 6, (0, 0, 0.5, 1), a0=0, a1=220).transformed(R=rot('y', 90), t=(0.0, 0.072, 0.0024))
    grip = loft_y([(-0.05, 0.0042, 0.004, 2, 0, 0), (-0.015, 0.0046, 0.0044, 2, 0, 0), (0.005, 0.0036, 0.0034, 2, 0, 0)],
                  14, (0.5, 0, 1, 1), caps=[(0, (0.5, 0, 0.55, 0.05))])
    return ('nz_sty_hook', merge([rod, tip, grip]), tex, 15.0, ((35, 30), (215, 15), (110, 70)))


def flat_iron():
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 0.5), (220, 140, 90), 6), ((0.5, 0.5, 1, 1), TEAL, 6)])
    tex = label_on(tex, (0.0, 0.2, 0.5, 0.45), [('NZ PRO', 34, TEAL_HI, 800), ('230°', 26, (200, 205, 210), 500)], flip=False)
    arms = []
    for s, ang in ((1, 3.0), (-1, -3.0)):
        secs = [(-0.1, 0.009, 0.0045, 2.4, 0, 0), (0.0, 0.0115, 0.006, 2.4, 0, 0), (0.17, 0.0125, 0.0055, 2.4, 0, 0)]
        arm = loft_y(secs, 18, (0, 0, 0.5, 1), caps=[(0, (0, 0, 0.05, 0.05)), (1, (0, 0.95, 0.05, 1))])
        plate = box((-0.0105, 0.04, -0.0012), (0.0105, 0.165, 0.0012), (0.5, 0, 1, 0.5))
        a = merge([arm, plate.transformed(t=(0, 0, -s * 0.006))])
        arms.append(a.transformed(R=rot('x', ang), t=(0, 0, s * 0.0085)))
    hinge = loft_y([(-0.104, 0.008, 0.016, 2, 0, 0), (-0.094, 0.008, 0.016, 2, 0, 0)], 14, (0.5, 0.5, 1, 1))
    cord = loft_y([(-0.104, 0.0022, 0.0022, 2, 0, 0), (-0.16, 0.0022, 0.0022, 2, 0.004, -0.01)], 8, (0, 0, 0.5, 1))
    return ('nz_sty_iron', merge(arms + [hinge, cord]), tex, 30.0, ((35, 30), (215, 15), (110, 70)))


def wand():
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 1), (210, 150, 105), 7)])
    handle = loft_y([(-0.11, 0.009, 0.009, 2, 0, 0), (-0.03, 0.0125, 0.0125, 2, 0, 0), (0.005, 0.0115, 0.0115, 2, 0, 0)],
                    20, (0, 0, 0.5, 1), caps=[(0, (0, 0, 0.05, 0.05))])
    barrel = loft_y([(0.005, 0.0105, 0.0105, 2, 0, 0), (0.16, 0.0085, 0.0085, 2, 0, 0)], 20, (0.5, 0, 1, 1))
    tip = loft_y([(0.16, 0.0062, 0.0062, 2, 0, 0), (0.175, 0.0055, 0.0055, 2, 0, 0)], 14, (0, 0, 0.5, 1), caps=[(1, (0, 0.95, 0.05, 1))])
    return ('nz_sty_wand', merge([handle, barrel, tip]), tex, 30.0, ((35, 30), (215, 15), (110, 70)))


def dryer():
    tex = atlas([((0, 0, 0.5, 1), BLACK, 4), ((0.5, 0, 1, 0.5), (40, 42, 46), 4), ((0.5, 0.5, 1, 1), TEAL, 6)])
    handle = loft_y([(-0.1, 0.012, 0.016, 2.6, 0, 0), (-0.02, 0.014, 0.018, 2.6, 0, 0), (0.02, 0.016, 0.02, 2.6, 0, 0)],
                    18, (0, 0, 0.5, 1), caps=[(0, (0, 0, 0.05, 0.05))])
    # the body runs along -X ... +X, nozzle at +X, vent at -X
    body = lathe([(0.0, -0.075), (0.026, -0.075), (0.034, -0.06), (0.036, 0.0), (0.03, 0.06), (0.021, 0.095), (0.022, 0.11), (0.0, 0.11)],
                 30, (0, 0, 0.5, 1)).transformed(R=rot('y', 90), t=(0.0, 0.045, 0.0))
    vent = torus(0.026, 0.0035, 28, 8, (0.5, 0.5, 1, 1)).transformed(R=rot('y', 90), t=(-0.074, 0.045, 0.0))
    nozzle = torus(0.021, 0.002, 24, 6, (0.5, 0, 1, 0.5)).transformed(R=rot('y', 90), t=(0.108, 0.045, 0.0))
    return ('nz_sty_dryer', merge([handle, body, vent, nozzle]), tex, 35.0, ((35, 20), (215, 15), (110, 60)))


def tub(name='nz_sty_gel', body_rgb=(70, 160, 226), lines=None, r=0.034, h=0.042, lid=BLACK):
    img = atlas([((0, 0, 1, 0.7), body_rgb, 6), ((0, 0.7, 1, 1), lid, 4)])
    for uc in (0.25, 0.75):
        label_on(img, (uc - 0.2, 0.12, uc + 0.2, 0.62), lines or [('NZ', 44, (255, 255, 255), 800), ('BRAIDING GEL', 22, (255, 255, 255), 700), ('extra hold', 18, (230, 240, 246), 400)])
    body = lathe([(0.0, 0.0), (r * 0.94, 0.0), (r, 0.004), (r, h * 0.86), (r * 0.98, h * 0.9)], 40, (0, 0, 1, 0.7))
    cap = lathe([(r * 1.02, h * 0.84), (r * 1.04, h * 0.88), (r * 1.04, h), (r * 0.6, h * 1.02), (0.0, h * 1.02)], 40, (0, 0.7, 1, 1))
    return (name, merge([body, cap]), img, 25.0, ((30, 18), (210, 12), (100, 60)))


def gel():
    return tub()


def tin():
    return tub('nz_sty_tin', (224, 176, 76), [('NZ', 36, BLACK, 800), ('EDGE CONTROL', 18, BLACK, 700), ('24h hold', 14, (60, 40, 20), 400)],
               r=0.032, h=0.02, lid=(20, 20, 22))


def can(name='nz_sty_mousse', band=PINK, lines=None):
    img = atlas([((0, 0, 1, 0.75), (240, 241, 242), 4), ((0, 0.3, 1, 0.55), band, 5), ((0, 0.75, 1, 1), BLACK, 4)])
    for uc in (0.25, 0.75):
        label_on(img, (uc - 0.2, 0.32, uc + 0.2, 0.72), lines or [('NZ', 46, BLACK, 800), ('FOAM MOUSSE', 20, (255, 255, 255), 700), ('wrap & set', 16, (40, 40, 44), 400)])
    body = lathe([(0.0, 0.0), (0.021, 0.0), (0.0235, 0.004), (0.0235, 0.118), (0.019, 0.13), (0.011, 0.136)], 36, (0, 0, 1, 0.75))
    top = lathe([(0.0115, 0.135), (0.0125, 0.14), (0.0125, 0.152), (0.009, 0.156), (0.0, 0.157)], 24, (0, 0.75, 1, 1))
    spout = loft_y([(0.0, 0.003, 0.003, 2, 0, 0.152), (0.016, 0.0024, 0.0024, 2, 0, 0.151)], 10, (0, 0.75, 1, 1), caps=[(1, (0, 0.95, 0.05, 1))])
    return (name, merge([body, top, spout]), img, 25.0, ((30, 12), (210, 12), (100, 55)))


def mousse():
    return can()


def spray(name='nz_sty_spray', liquid=(220, 236, 240), band=TEAL, lines=None):
    img = atlas([((0, 0, 1, 0.7), liquid, 4), ((0, 0.25, 1, 0.55), band, 5), ((0, 0.7, 1, 1), BLACK, 4)])
    for uc in (0.25, 0.75):
        label_on(img, (uc - 0.2, 0.26, uc + 0.2, 0.62), lines or [('NZ', 44, (255, 255, 255), 800), ('SHINE SPRAY', 20, (255, 255, 255), 700), ('gloss finish', 16, (230, 244, 242), 400)])
    body = lathe([(0.0, 0.0), (0.019, 0.0), (0.0215, 0.004), (0.0215, 0.098), (0.017, 0.11), (0.009, 0.116), (0.009, 0.122)], 36, (0, 0, 1, 0.7))
    head = lathe([(0.0098, 0.12), (0.0105, 0.124), (0.0105, 0.138), (0.0085, 0.145), (0.0, 0.146)], 24, (0, 0.7, 1, 1))
    nozzle = box((-0.0035, 0.004, 0.132), (0.0035, 0.016, 0.14), (0, 0.7, 1, 1))
    return (name, merge([body, head, nozzle]), img, 25.0, ((30, 12), (210, 12), (100, 55)))


def pack(name='nz_sty_pack', hair=((150, 104, 56), (200, 150, 90), (240, 205, 150)), lines=None, seed=91):
    b = _h()
    W, H = 512, 512
    t = np.zeros((H, W, 3))
    t[:, :int(0.8 * W)] = b.hair_texture(int(0.8 * W), H, base=hair[0], mid=hair[1], hi=hair[2], seed=seed)
    b.fill(t, (0.8, 0, 1, 1), (245, 246, 247), b.noise(W, H, 0.3, 1, 92), 4)
    img = b.to_img(t)
    label_on(img, (0.8, 0.3, 1.0, 0.75), lines or [('NZ', 26, TEAL, 800), ('BRAID', 16, BLACK, 700), ('HAIR', 16, BLACK, 700)], flip=False)
    # a long flat folded hank: the hair along Y, a paper band around the middle
    secs = []
    for i in range(16):
        a = i / 15
        y = -0.15 + a * 0.3
        w = 0.016 - 0.004 * abs(a - 0.5) * 2
        secs.append((y, w, 0.0055, 2.2, 0.0015 * math.sin(a * 8), 0.0))
    hank = loft_y(secs, 20, (0, 0, 0.8, 1), caps=[(0, (0, 0, 0.05, 0.05)), (1, (0, 0.95, 0.05, 1))])
    band = loft_y([(-0.03, 0.0175, 0.0068, 2.6, 0, 0), (0.03, 0.0175, 0.0068, 2.6, 0, 0)], 20, (0.8, 0, 1, 1))
    return (name, merge([hank, band]), img, 25.0, ((35, 40), (210, 30), (100, 70)))


PROPS = [comb, brush, edge_brush, needle, hook, flat_iron, wand, dryer, gel, tin, mousse, spray, pack]
