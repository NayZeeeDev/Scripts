"""Builds the Wig Snatch props as CodeWalker XML + DDS, ready for cwtool xml2ydr / xml2ytyp.

    nz_wig_clippers   cordless hair clippers (in hand)
    nz_wig_razor      open straight razor (in hand)
    nz_wig_dye        hair dye applicator bottle (in hand / on the table)
    nz_wig_head       bald foam head on a stand (on the table; hairstyle props sit on it)
    nz_wig_shell      a generic long wig for the foam head, for hairstyles without their own prop
    nz_hair_bundle    a tied bundle of hair (on the table, used up as the wig is made)

Units are metres, Z up. Hand tools run along +Y with the grip at the origin; table props stand on z = 0.
The foam head faces +Y like a ped, so hair converted from a ped keeps its orientation.
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mesh import Part, merge, lathe, loft_y, box, surface, rot, ydr_xml, archetype_xml, ytyp_xml, write_dds, render  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, 'lexend.ttf')
RNG = np.random.default_rng(7177)

TEAL = (8, 175, 162)
TEAL_HI = (15, 212, 196)
RED = (229, 72, 77)
PINK = (236, 92, 160)


def font(size, weight=700):
    # Lexend: convert web/fonts/lexend-latin-wght-normal.woff2 to tools/props/lexend.ttf (fontTools) for the labels
    try:
        ft = ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default(size)
    try:
        ft.set_variation_by_axes([weight])
    except Exception:
        pass
    return ft


def noise(w, h, scale=1.0, blur=1.5, seed=None):
    rng = np.random.default_rng(seed) if seed is not None else RNG
    n = rng.normal(0, 1, (h, w))
    im = Image.fromarray(np.uint8(np.clip(128 + n * 40 * scale, 0, 255))).filter(ImageFilter.GaussianBlur(blur))
    return (np.asarray(im, dtype=np.float64) - 128) / 128.0


def fill(arr, rect, rgb, n=None, amp=0.0):
    W, H = arr.shape[1], arr.shape[0]
    x0, y0, x1, y1 = [int(round(v)) for v in (rect[0] * W, rect[1] * H, rect[2] * W, rect[3] * H)]
    blk = np.ones((y1 - y0, x1 - x0, 3)) * np.array(rgb, dtype=np.float64)
    if n is not None:
        blk += n[:y1 - y0, :x1 - x0, None] * amp
    arr[y0:y1, x0:x1] = blk
    return (x0, y0, x1, y1)


def to_img(arr):
    return Image.fromarray(np.uint8(np.clip(arr, 0, 255)))


def hair_texture(w, h, base=(28, 19, 15), mid=(58, 40, 31), hi=(112, 82, 62), seed=3, tips=True):
    """Strands running down the texture (along v)."""
    rng = np.random.default_rng(seed)
    cols = rng.random(w)
    cols = np.convolve(cols, np.ones(3) / 3, mode='same')
    fine = rng.random(w)
    strand = 0.65 * cols + 0.35 * fine
    rows = np.linspace(0, 1, h)[:, None]
    wave = 0.08 * np.sin(rows * 40 + rng.random(w)[None, :] * 6.28)
    k = np.clip(strand[None, :] + wave, 0, 1)
    out = np.zeros((h, w, 3))
    for i in range(3):
        out[..., i] = base[i] + (mid[i] - base[i]) * k + (hi[i] - mid[i]) * np.clip((k - 0.72) * 3.5, 0, 1)
    if tips:
        out *= (1.0 + 0.18 * np.clip((rows - 0.75) * 4, 0, 1))[..., None]
    return out


def save(name, part, tex, lod=60.0, views=((35, 20), (215, 15), (110, 60))):
    tex_name = name + '_d'
    mips = write_dds(tex, os.path.join(OUT, tex_name + '.dds'))
    with open(os.path.join(OUT, name + '.ydr.xml'), 'w') as fh:
        fh.write(ydr_xml(name, part, tex_name, tex.size[0], tex.size[1], mips))
    tex.save(os.path.join(OUT, tex_name + '.png'))
    shots = [render(part, tex, 360, yaw=a, pitch=p) for a, p in views]
    sheet = Image.new('RGB', (360 * len(shots), 360))
    for i, s in enumerate(shots):
        sheet.paste(s, (360 * i, 0))
    sheet.save(os.path.join(OUT, name + '_preview.png'))
    P = part.P
    print('%-16s verts=%5d tris=%5d size=%s' % (name, len(P), len(part.T), np.round(P.max(axis=0) - P.min(axis=0), 3)))
    return archetype_xml(name, part, lod)


# ═════════════════════════════════════════════════════════════════════════════════════
# CLIPPERS
def clippers():
    W = H = 512
    t = np.zeros((H, W, 3))
    nz = noise(W, H, 0.6, 1.2, 11)
    # body: matte black with a soft top sheen; u around (0.25 = top), v along (0 = rear)
    x0, y0, x1, y1 = fill(t, (0, 0, 0.75, 1), (24, 26, 28), nz, 10)
    u = np.linspace(0, 1, x1 - x0)
    sheen = np.clip(1 - np.abs(u - 0.25) / 0.18, 0, 1) ** 2 * 26 + np.clip(1 - np.abs(u - 0.0) / 0.06, 0, 1) * 8
    t[y0:y1, x0:x1] += sheen[None, :, None]
    # teal band near the rear and a thin teal line down each side
    band = (int(0.16 * H), int(0.205 * H))
    t[band[0]:band[1], x0:x1] = np.array(TEAL)
    t[band[0]:band[0] + 2, x0:x1] = np.array(TEAL_HI)
    for us in (0.0, 0.5, 1.0):
        cx = int(x0 + us * (x1 - x0))
        t[int(0.26 * H):int(0.9 * H), max(x0, cx - 3):min(x1, cx + 3)] = np.array(TEAL) * 0.9
    # grip texture: little rubber dots on the underside half
    for yy in range(int(0.3 * H), int(0.75 * H), 9):
        for uu in np.arange(0.62, 0.88, 0.035):
            cx, cy = int(x0 + uu * (x1 - x0)), yy + (4 if int(uu * 100) % 2 else 0)
            t[cy - 2:cy + 2, cx - 2:cx + 2] = (40, 43, 46)
    img = to_img(t)
    d = ImageDraw.Draw(img)
    # NAYZEEE logo running along the top of the body
    logo = Image.new('RGBA', (int(0.5 * H), 60), (0, 0, 0, 0))
    ld = ImageDraw.Draw(logo)
    ld.text((logo.width // 2, 30), 'NAYZEEE', font=font(34, 800), fill=(240, 244, 245, 255), anchor='mm')
    logo = logo.rotate(90, expand=True)
    img.paste(logo, (int(x0 + 0.25 * (x1 - x0)) - logo.width // 2, int(0.34 * H)), logo)
    small = Image.new('RGBA', (int(0.25 * H), 30), (0, 0, 0, 0))
    ImageDraw.Draw(small).text((small.width // 2, 15), 'PRO CUT', font=font(16, 600), fill=TEAL_HI + (255,), anchor='mm')
    small = small.rotate(90, expand=True)
    img.paste(small, (int(x0 + 0.25 * (x1 - x0)) - small.width // 2 - 22, int(0.62 * H)), small)
    t = np.asarray(img, dtype=np.float64).copy()
    # blade: chrome with teeth
    bx0, by0, bx1, by1 = fill(t, (0.75, 0, 1, 0.5), (186, 192, 198), noise(W, H, 0.4, 0.8, 12), 18)
    grad = np.linspace(1.15, 0.75, by1 - by0)[:, None, None]
    t[by0:by1, bx0:bx1] *= grad
    for xx in range(bx0, bx1, 6):
        t[by0 + int(0.6 * (by1 - by0)):by1, xx:xx + 2] *= 0.55
    # lever: brushed silver
    lx0, ly0, lx1, ly1 = fill(t, (0.75, 0.5, 1, 0.75), (150, 156, 162), noise(W, H, 0.8, 0.5, 13), 20)
    # switch: teal
    fill(t, (0.75, 0.75, 1, 1), TEAL, noise(W, H, 0.3, 1, 14), 8)
    tex = to_img(t)

    secs = []
    prof = [(-0.079, 0.006, 0.004), (-0.077, 0.015, 0.011), (-0.073, 0.020, 0.0155), (-0.066, 0.0225, 0.0172),
            (-0.045, 0.0232, 0.0178), (-0.015, 0.0222, 0.0172), (0.015, 0.0232, 0.0178), (0.045, 0.0248, 0.0176),
            (0.062, 0.0252, 0.016), (0.071, 0.0246, 0.0128), (0.076, 0.0225, 0.0088), (0.078, 0.019, 0.005)]
    for y, hw, hh in prof:
        secs.append((y, hw, hh, 3.2, 0.0, 0.0))
    body = loft_y(secs, 40, (0, 0, 0.75, 1), caps=[(0, (0.0, 0.0, 0.1, 0.1)), (1, (0.0, 0.9, 0.1, 1.0))])

    # blade housing + plate, tilted down slightly at the front
    plate = box((-0.0235, 0.0, -0.0032), (0.0235, 0.024, 0.0032), (0.75, 0.0, 1.0, 0.3))
    teeth = []
    n = 17
    for i in range(n):
        x = -0.022 + i * (0.044 / (n - 1))
        teeth.append(box((x - 0.0009, 0.024, -0.0022), (x + 0.0009, 0.0315, 0.0016), (0.75, 0.3, 1.0, 0.5)))
    head = merge([plate] + teeth).transformed(R=rot('x', -14), t=(0, 0.066, 0.004))
    lever = box((-0.0278, 0.032, -0.003), (-0.0236, 0.05, 0.0045), (0.75, 0.5, 1.0, 0.75))
    switch = loft_y([(-0.012, 0.0001, 0.0001, 2.5, 0, 0.0172), (-0.011, 0.0055, 0.0025, 2.5, 0, 0.0172),
                     (0.009, 0.0055, 0.0025, 2.5, 0, 0.0172), (0.010, 0.0001, 0.0001, 2.5, 0, 0.0172)],
                    16, (0.75, 0.75, 1.0, 1.0))
    part = merge([body, head, lever, switch])
    return save('nz_wig_clippers', part, tex, lod=40.0)


# ═════════════════════════════════════════════════════════════════════════════════════
# STRAIGHT RAZOR
def wedge_ring(y, spine_x, edge_x, spine_t, edge_t, cz=0.0, n=14):
    """Cross-section of a blade: thick rounded spine at +x, thin edge at -x."""
    pts = []
    for i in range(n):
        a = i / (n - 1)
        x = spine_x + (edge_x - spine_x) * a
        th = spine_t + (edge_t - spine_t) * (a ** 0.8)
        pts.append((x, y, cz + th))
    for i in range(n):
        a = 1 - i / (n - 1)
        x = spine_x + (edge_x - spine_x) * a
        th = spine_t + (edge_t - spine_t) * (a ** 0.8)
        pts.append((x, y, cz - th))
    return pts


def razor():
    W = H = 512
    t = np.zeros((H, W, 3))
    # handle (scales): deep black acrylic with a teal inlay, teal pins
    x0, y0, x1, y1 = fill(t, (0, 0, 0.5, 1), (16, 17, 19), noise(W, H, 0.5, 2, 21), 8)
    u = np.linspace(0, 1, x1 - x0)
    for uc in (0.25, 0.75):   # faces
        t[y0:y1, x0:x1] += (np.clip(1 - np.abs(u - uc) / 0.2, 0, 1) ** 2 * 22)[None, :, None]
        cx = int(x0 + uc * (x1 - x0))
        t[int(0.1 * H):int(0.9 * H), cx - 3:cx + 3] = np.array(TEAL)
    for yy in (0.04, 0.95):
        cy = int(yy * H)
        for uc in (0.25, 0.75):
            cx = int(x0 + uc * (x1 - x0))
            yy_, xx_ = np.ogrid[-12:12, -12:12]
            m = xx_ ** 2 + yy_ ** 2 <= 100
            t[cy - 12:cy + 12, cx - 12:cx + 12][m] = (200, 205, 210)
    # blade: polished steel, darker spine, bright honed edge, etched name
    bx0, by0, bx1, by1 = fill(t, (0.5, 0, 1, 1), (176, 182, 188), noise(W, H, 0.3, 0.6, 22), 10)
    u = np.linspace(0, 1, bx1 - bx0)
    # ring goes spine(top) -> edge -> spine(bottom): edge in the middle of u
    edge = np.clip(1 - np.abs(u - 0.5) / 0.08, 0, 1)
    spine = np.clip(1 - np.minimum(u, 1 - u) / 0.08, 0, 1)
    t[by0:by1, bx0:bx1] += (edge * 55 - spine * 50)[None, :, None]
    t[by0:by1, bx0:bx1] *= np.linspace(0.9, 1.08, by1 - by0)[:, None, None]
    img = to_img(t)
    etch = Image.new('RGBA', (int(0.55 * H), 40), (0, 0, 0, 0))
    ImageDraw.Draw(etch).text((etch.width // 2, 20), 'NAYZEEE', font=font(24, 700), fill=(70, 74, 80, 255), anchor='mm')
    etch = etch.rotate(90, expand=True)
    for uc in (0.27, 0.73):
        img.paste(etch, (int(bx0 + uc * (bx1 - bx0)) - etch.width // 2, int(0.25 * H)), etch)
    tex = img

    # handle along Y, flat in Z, slight belly
    hs = []
    for i in range(13):
        a = i / 12
        y = -0.066 + a * 0.128
        w = 0.0085 + 0.0022 * math.sin(a * math.pi)
        th = 0.0042 + 0.0006 * math.sin(a * math.pi)
        if i == 0:
            w, th = 0.006, 0.003
        hs.append((y, w, th, 2.6, 0.0011 * math.sin(a * math.pi), 0.0))
    handle = loft_y(hs, 28, (0, 0, 0.5, 1), caps=[(0, (0.0, 0.0, 0.05, 0.05)), (1, (0.0, 0.95, 0.05, 1.0))])
    # pins (little discs on both faces)
    pins = []
    for y in (-0.06, 0.056):
        for s in (1, -1):
            disc = lathe([(0.0, 0.0), (0.0018, 0.0), (0.0018, 0.0006), (0.0, 0.0008)], 12, (0.0, 0.0, 0.05, 0.05))
            pins.append(disc.transformed(R=np.eye(3) if s > 0 else rot('x', 180), t=(0, y, s * 0.0046)))
    # tang + blade, in line with the handle (open razor), edge facing -x
    rings = []
    ys = np.linspace(0.058, 0.142, 16)
    for i, y in enumerate(ys):
        a = i / (len(ys) - 1)
        if a < 0.15:     # tang: narrow and thick
            k = a / 0.15
            spine_x, edge_x = 0.0065, -0.004 - 0.006 * k
            st, et = 0.0016, 0.0012 - 0.0009 * k
        else:
            spine_x, edge_x = 0.0072, -0.0118
            st, et = 0.0013, 0.0002
            if a > 0.93:  # rounded tip
                k = (a - 0.93) / 0.07
                spine_x, edge_x = 0.0072 - 0.004 * k, -0.0118 + 0.008 * k
        rings.append(wedge_ring(y, spine_x, edge_x, st, et))
    G = np.array(rings)
    blade = surface(G, (0.5, 0, 1, 1), closed=True, vparams=np.linspace(0, 1, len(ys)))
    capsP = []
    for idx, nrm in ((0, (0, -1, 0)), (-1, (0, 1, 0))):
        ring = G[idx]
        c = ring.mean(axis=0)
        P = [c] + list(ring)
        T = np.array([(0, 1 + i, 1 + (i + 1) % len(ring)) for i in range(len(ring))])
        a_, b_, c_ = np.array(P)[T[:, 0]], np.array(P)[T[:, 1]], np.array(P)[T[:, 2]]
        if np.dot(np.cross(b_ - a_, c_ - a_).sum(axis=0), nrm) < 0:
            T = T[:, ::-1]
        capsP.append(Part(P, [nrm] * len(P), [(0.75, 0.02)] * len(P), T))
    part = merge([handle, blade] + capsP + pins)
    return save('nz_wig_razor', part, tex, lod=40.0)


# ═════════════════════════════════════════════════════════════════════════════════════
# DYE BOTTLE
def dye():
    W = H = 512
    t = np.zeros((H, W, 3))
    # body (v 0..0.62 of the atlas): white bottle, black wrap label
    x0, y0, x1, y1 = fill(t, (0, 0, 1, 0.62), (236, 238, 240), noise(W, H, 0.3, 1.5, 31), 6)
    lab = (int(0.12 * (y1 - y0)) + y0, int(0.86 * (y1 - y0)) + y0)   # label band (v along the body bottom→top)
    t[lab[0]:lab[1], x0:x1] = (14, 15, 17)
    # colour swatch band: a gradient of dye shades
    sw = (lab[0] + int(0.08 * (lab[1] - lab[0])), lab[0] + int(0.24 * (lab[1] - lab[0])))
    grad = np.linspace(0, 1, x1 - x0)
    cols = np.array([PINK, (150, 60, 190), TEAL, (240, 180, 60), PINK], dtype=np.float64)
    pos = np.linspace(0, 1, len(cols))
    band = np.stack([np.interp(grad, pos, cols[:, i]) for i in range(3)], axis=1)
    t[sw[0]:sw[1], x0:x1] = band[None, :, :]
    img = to_img(t)
    d = ImageDraw.Draw(img)
    # text faces u = 0.75 (the -y side) and u = 0.25 (+y side); v grows up the bottle, image rows grow down,
    # so the label is drawn upside down in the texture and reads correctly on the model
    for uc in (0.25, 0.75):
        cx = int(x0 + uc * (x1 - x0))
        lbl = Image.new('RGBA', (220, 200), (0, 0, 0, 0))
        ld = ImageDraw.Draw(lbl)
        ld.text((110, 40), 'NZ', font=font(64, 800), fill=(255, 255, 255, 255), anchor='mm')
        ld.text((110, 92), 'HAIR DYE', font=font(26, 700), fill=TEAL_HI + (255,), anchor='mm')
        ld.text((110, 124), 'COLOUR CREAM', font=font(15, 500), fill=(200, 205, 208, 255), anchor='mm')
        ld.text((110, 150), 'NAYZEEE · 60 ml', font=font(13, 400), fill=(140, 146, 150, 255), anchor='mm')
        lbl = lbl.transpose(Image.FLIP_TOP_BOTTOM)
        img.paste(lbl, (cx - 110, lab[0] + int(0.3 * (lab[1] - lab[0])) - 20), lbl)
    t = np.asarray(img, dtype=np.float64).copy()
    # cap + nozzle (v 0.62..1): glossy black, teal ring
    cx0, cy0, cx1, cy1 = fill(t, (0, 0.62, 1, 1), (20, 21, 23), noise(W, H, 0.3, 1, 32), 6)
    t[cy0:cy0 + 10, cx0:cx1] = np.array(TEAL)
    tex = to_img(t)

    body = lathe([(0.0, 0.0), (0.019, 0.0), (0.0228, 0.0015), (0.024, 0.006), (0.024, 0.088), (0.0236, 0.095),
                  (0.0212, 0.101), (0.0165, 0.106), (0.0118, 0.109), (0.0112, 0.1115)], 40, (0, 0, 1, 0.62))
    cap = lathe([(0.0119, 0.111), (0.0121, 0.113), (0.0121, 0.127), (0.0095, 0.131), (0.0058, 0.1335),
                 (0.0046, 0.145), (0.0032, 0.158), (0.0018, 0.1655), (0.0009, 0.1675), (0.0, 0.168)], 32, (0, 0.62, 1, 1))
    part = merge([body, cap])
    return save('nz_wig_dye', part, tex, lod=50.0, views=((30, 12), (210, 12), (100, 55)))


# ═════════════════════════════════════════════════════════════════════════════════════
# FOAM HEAD WEARING A WIG
HEAD = [(0.0, 0.095), (0.026, 0.095), (0.034, 0.105), (0.036, 0.13), (0.038, 0.15), (0.048, 0.168), (0.062, 0.185),
        (0.071, 0.205), (0.076, 0.228), (0.0775, 0.252), (0.0755, 0.276), (0.069, 0.296), (0.057, 0.314),
        (0.04, 0.327), (0.02, 0.334), (0.0, 0.336)]


def head_r(z):
    zs = [p[1] for p in HEAD]
    rs = [p[0] for p in HEAD]
    return float(np.interp(z, zs, rs))


HEAD_POINT = 0.162  # the head bone (SKEL_Head) on the foam head: hair props are built around this point


def wig_head():
    """Bald foam head on a stand. Hairstyle props sit on it at HEAD_POINT."""
    W = H = 512
    t = np.zeros((H, W, 3))
    fill(t, (0, 0, 0.25, 1), (22, 23, 25), noise(W, H, 0.4, 1, 41), 8)
    x0, y0, x1, y1 = fill(t, (0.25, 0, 1, 1), (214, 190, 165), noise(W, H, 0.6, 2.5, 42), 10)
    u = np.linspace(0, 1, x1 - x0)
    v = np.linspace(0, 1, y1 - y0)
    # soft face shading on the front (+y like a ped, u = 0.25 of the head ring), closed eyes
    face = np.clip(1 - np.abs(u - 0.25) / 0.12, 0, 1)
    eyes = np.exp(-((v - 0.66) / 0.02) ** 2)[:, None] * (np.exp(-((u - 0.21) / 0.022) ** 2) + np.exp(-((u - 0.29) / 0.022) ** 2))[None, :]
    t[y0:y1, x0:x1] -= (eyes * 30)[..., None]
    t[y0:y1, x0:x1] += (face * 8)[None, :, None]
    tex = to_img(t)

    base = lathe([(0.0, 0.0), (0.056, 0.0), (0.06, 0.004), (0.058, 0.011), (0.05, 0.014), (0.012, 0.016), (0.0, 0.016)], 36, (0, 0, 0.25, 0.25))
    pole = lathe([(0.0085, 0.015), (0.0085, 0.098)], 16, (0, 0.25, 0.25, 1))
    foam = lathe(HEAD, 48, (0.25, 0, 1, 1), scale=(0.9, 1.06))
    part = merge([base, pole, foam])
    return save('nz_wig_head', part, tex, lod=50.0, views=((200, 10), (20, 10), (110, 25)))


def wig_shell():
    """A generic long wig, built around the head centre (origin), shown on the foam head when a
    hairstyle has no prop of its own."""
    W = H = 512
    tex = to_img(hair_texture(W, H, seed=43))
    segs, rows = 48, 22
    G = []
    ztop = 0.344
    for i in range(segs):
        a = 2 * math.pi * i / segs
        front = max(0.0, math.sin(a))   # +y is the face, like a ped
        zend = 0.112 + front ** 2.5 * 0.175
        ring = []
        for k in range(rows):
            s = k / (rows - 1)
            z = ztop - s * (ztop - zend)
            if z > 0.205:
                r = head_r(z) * 1.075 + 0.0035
            else:
                r = head_r(0.205) * 1.075 + 0.0035 + (0.205 - z) * 0.32
            if k == 0:
                r = 0.0
            r *= 1 + 0.025 * math.sin(a * 11 + s * 4) * min(1.0, s * 3)
            ring.append((r * math.cos(a) * 0.9, r * math.sin(a) * 1.06, z - HEAD_POINT))
        G.append(ring)
    G = np.array(G).transpose(1, 0, 2)
    outer = surface(G, (0, 0, 1, 1), closed=True, center=(0, 0, 0), pole_axis=(0, 0, 1))
    inner = outer.flipped(0.0012)
    part = merge([outer, inner])
    return save('nz_wig_shell', part, tex, lod=50.0, views=((200, 10), (20, 10), (110, 25)))


# ═════════════════════════════════════════════════════════════════════════════════════
# HAIR BUNDLE
def bundle():
    W, H = 512, 256
    t = np.zeros((H, W, 3))
    t[:, :int(0.85 * W)] = hair_texture(int(0.85 * W), H, seed=51).transpose(0, 1, 2)
    fill(t, (0.85, 0, 1, 1), TEAL, noise(W, H, 0.3, 1, 52), 6)
    tex = to_img(t)
    # strands run along v; lay the bundle along Y then turn it to lie on the table
    secs = []
    n = 20
    for i in range(n):
        a = i / (n - 1)
        y = a * 0.25
        if a < 0.06:
            w = 0.004 + a / 0.06 * 0.004
        elif a < 0.12:
            w = 0.008
        else:
            k = (a - 0.12) / 0.88
            w = 0.008 + 0.014 * math.sin(min(1.0, k * 1.6) * math.pi / 2) - 0.017 * max(0.0, k - 0.45) ** 1.3
        w = max(0.0025, w)
        secs.append((y, w, w * 0.45, 2.2, 0.006 * math.sin(a * 9.0), 0.0))
    hair = loft_y(secs, 24, (0, 0, 0.85, 1), caps=[(0, (0.0, 0.0, 0.05, 0.05)), (1, (0.0, 0.95, 0.05, 1.0))])
    band = loft_y([(0.012, 0.0098, 0.0060, 2.0, 0.0, 0.0), (0.0125, 0.0105, 0.0066, 2.0, 0.0, 0.0),
                   (0.0215, 0.0105, 0.0066, 2.0, 0.0, 0.0), (0.022, 0.0098, 0.0060, 2.0, 0.0, 0.0)], 20, (0.85, 0, 1, 1))
    part = merge([hair, band])
    zmin = part.P[:, 2].min()
    part = part.transformed(t=(0, -0.125, -zmin))
    return save('nz_hair_bundle', part, tex, lod=30.0, views=((35, 35), (200, 30), (90, 70)))


if __name__ == '__main__':
    items = [clippers(), razor(), dye(), wig_head(), wig_shell(), bundle()]
    with open(os.path.join(OUT, 'nz_wigsnatch_props.ytyp.xml'), 'w') as fh:
        fh.write(ytyp_xml('nz_wigsnatch_props', items))
    print('done ->', OUT)
