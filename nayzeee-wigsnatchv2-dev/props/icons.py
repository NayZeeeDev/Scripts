"""Inventory icons for every Wig Snatch item: small 3D models rendered like the nayzeee-sneakers icons
(256 px, three-quarter view, soft studio light, transparent background).

    python3 icons.py <out_dir>          # writes <item>.png for every item + wig_<tier>.png + a contact sheet

The props the script streams (clippers, razor, dye, foam head + wig, bundle) come from build.py, so the
icons match what players see in game.
"""
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402
from build import noise, fill, to_img, hair_texture, font, TEAL, TEAL_HI, PINK, HEAD_POINT  # noqa: E402
from mesh import Part, merge, lathe, loft_y, box, surface, rot, render_icon, torus  # noqa: E402


# ── textures ────────────────────────────────────────────────────────────────────────────────────
def solid(rgb, n=None, amp=0.0, size=64, seed=1):
    t = np.ones((size, size, 3)) * np.array(rgb, dtype=np.float64)
    if amp:
        t += noise(size, size, 0.6, 1.2, seed)[..., None] * amp
    return to_img(t)


def label_lathe(w, h, bg, body, yaw, lines, band=None, label_v=(0.25, 0.8), label_bg=None, width=0.42):
    """Texture for a lathe: v up the object, u around it. The label faces the camera at `yaw`."""
    t = np.ones((h, w, 3)) * np.array(bg, dtype=np.float64)
    t += noise(w, h, 0.3, 1.5, 9)[..., None] * 5
    img = to_img(t)
    d = ImageDraw.Draw(img)
    u = (((270 + yaw) % 360) / 360.0)
    lv0, lv1 = label_v
    if label_bg:
        ImageDraw.Draw(img).rectangle((0, int(h * (1 - lv1)), w, int(h * (1 - lv0))), fill=label_bg)  # flipped below
    if band:
        for (v0, v1, rgb) in band:
            d.rectangle((0, int(h * (1 - v1)), w, int(h * (1 - v0))), fill=rgb)
    # text panel, drawn upright then flipped (image rows run down, v runs up)
    pw, ph = int(w * width), int(h * (lv1 - lv0))
    panel = Image.new('RGBA', (pw, ph), (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    y = ph * 0.12
    for text, size, rgb, weight in lines:
        ft = font(max(6, int(size * h / 512)), weight)
        pd.text((pw / 2, y), text, font=ft, fill=rgb + (255,) if len(rgb) == 3 else rgb, anchor='mt')
        y += size * h / 512 * 1.25
    panel = panel.transpose(Image.FLIP_TOP_BOTTOM)
    for du in (0, -1, 1):  # wrap around the seam
        img.paste(panel, (int((u + du) * w - pw / 2), int(h * (1 - lv1))), panel)
    return img


def net_texture(w, h, base=(222, 196, 168), line=(150, 118, 92), step=10, seed=4):
    t = np.ones((h, w, 3)) * np.array(base, dtype=np.float64) + noise(w, h, 0.5, 1, seed)[..., None] * 8
    img = to_img(t)
    d = ImageDraw.Draw(img)
    for x in range(0, w, step):
        d.line((x, 0, x, h), fill=line, width=1)
    for y in range(0, h, step):
        d.line((0, y, w, y), fill=line, width=1)
    return img


def two_sided(p, off=0.0004):
    return merge([p, p.flipped(off)])


PLASTIC = {'spec': 0.35, 'gloss': 40}
MATTE = {'spec': 0.08, 'gloss': 12}
GLOSS = {'spec': 0.6, 'gloss': 70}
METAL = {'spec': 0.9, 'gloss': 60}
HAIR = {'spec': 0.22, 'gloss': 22}
GLASS = {'spec': 1.0, 'gloss': 90}


# ── models ──────────────────────────────────────────────────────────────────────────────────────
def from_prop(builder):
    _, part, tex, _, _ = builder()
    return part, tex


def wig(hair_cols=None, seed=43):
    """The foam head on its stand wearing the long wig: the same models as the table props."""
    head, htex = from_prop(build.wig_head)
    shell, stex = from_prop(build.wig_shell)
    if hair_cols:
        stex = to_img(hair_texture(512, 512, *hair_cols, seed=seed))
    shell = shell.transformed(t=(0, 0, HEAD_POINT))
    return [(head, htex, MATTE), (shell, stex, HAIR)], dict(yaw=205, pitch=10)


def hair_bundle():
    part, tex = from_prop(build.bundle)
    part = part.transformed(s=(1.7, 1.0, 1.6))
    a = part.transformed(R=rot('z', 18), t=(0.026, 0, 0))
    b = part.transformed(R=rot('z', -14), t=(-0.03, 0.01, 0.016))
    return [(a, tex, HAIR), (b, tex, HAIR)], dict(yaw=30, pitch=40)


def hair_clippers():
    part, tex = from_prop(build.clippers)
    return [(part.transformed(R=rot('x', 62) @ rot('z', 0)), tex, PLASTIC)], dict(yaw=-35, pitch=18)


def straight_razor():
    part, tex = from_prop(build.razor)
    return [(part.transformed(R=rot('y', 75)), tex, METAL)], dict(yaw=40, pitch=35)


def hair_dye():
    part, tex = from_prop(build.dye)
    return [(part, tex, PLASTIC)], dict(yaw=0, pitch=12)


def wig_cap():
    prof = [(0.0, 0.118)] + [(0.085 * math.sin(math.radians(a)), 0.118 * math.cos(math.radians(a))) for a in range(6, 91, 6)]
    prof += [(0.087, -0.004), (0.087, -0.012)]
    cap = two_sided(lathe(prof, 48, (0, 0, 1, 1), scale=(0.92, 1.08)))
    tex = net_texture(512, 512)
    band = lathe([(0.088, -0.014), (0.089, -0.002)], 48, (0, 0, 1, 1), scale=(0.92, 1.08))
    return [(cap, tex, MATTE), (two_sided(band), solid((40, 34, 30)), MATTE)], dict(yaw=25, pitch=24)


def bottle(profile, cap_profile, tex, cap_tex, cap_mat=PLASTIC, body_mat=PLASTIC, scale=(1, 1)):
    return [(lathe(profile, 48, (0, 0, 1, 1), scale=scale), tex, body_mat),
            (lathe(cap_profile, 32, (0, 0, 1, 1), scale=scale), cap_tex, cap_mat)]


def wig_glue():
    yaw = 0
    tex = label_lathe(512, 512, (245, 246, 247), None, yaw, [
        ('LACE', 64, (20, 22, 24), 800), ('GLUE', 64, (8, 160, 150), 800), ('extra hold · 38 ml', 22, (110, 116, 120), 500)],
        band=[(0.1, 0.16, TEAL)], label_v=(0.18, 0.86))
    body = [(0, 0), (0.019, 0), (0.021, 0.004), (0.021, 0.07), (0.019, 0.078), (0.012, 0.085), (0.009, 0.088)]
    cap = [(0.0095, 0.087), (0.0095, 0.098), (0.007, 0.101), (0.0035, 0.128), (0.0012, 0.136), (0, 0.137)]
    return bottle(body, cap, tex, solid(TEAL, amp=4), GLOSS), dict(yaw=yaw, pitch=12)


def shampoo():
    yaw = 0
    tex = label_lathe(512, 512, (24, 160, 150), None, yaw, [
        ('SHAMPOO', 30, (255, 255, 255), 800), ('clarifying', 20, (210, 245, 240), 500), ('NZ', 70, (255, 255, 255), 800)],
        label_v=(0.2, 0.8), width=0.34)
    body = [(0, 0), (0.026, 0), (0.03, 0.006), (0.031, 0.11), (0.028, 0.13), (0.02, 0.142), (0.012, 0.146)]
    cap = [(0.0125, 0.145), (0.016, 0.147), (0.016, 0.168), (0.012, 0.172), (0, 0.173)]
    return bottle(body, cap, tex, solid((245, 245, 245), amp=3), PLASTIC, scale=(1, 0.62)), dict(yaw=yaw, pitch=12)


def regrowth_oil():
    yaw = 0
    tex = label_lathe(512, 512, (150, 82, 20), None, yaw, [
        ('REGROWTH', 30, (60, 34, 10), 800), ('OIL', 56, (150, 82, 20), 800), ('rosemary · 30 ml', 18, (110, 90, 70), 500)],
        label_v=(0.16, 0.64), label_bg=(240, 236, 226), width=0.34)
    body = [(0, 0), (0.019, 0), (0.021, 0.004), (0.021, 0.062), (0.017, 0.072), (0.008, 0.078), (0.008, 0.084)]
    cap = [(0.0095, 0.083), (0.0095, 0.098), (0.008, 0.1), (0.0075, 0.102), (0.009, 0.112), (0.008, 0.124), (0.004, 0.129), (0, 0.13)]
    return bottle(body, cap, tex, solid((22, 22, 24), amp=3), GLOSS, body_mat=GLASS), dict(yaw=yaw, pitch=12)


def relaxer():
    yaw = 0
    tex = label_lathe(512, 256, (248, 248, 246), None, yaw, [
        ('LYE', 60, (229, 72, 77), 800), ('RELAXER', 40, (30, 30, 32), 800), ('super strength', 22, (120, 120, 124), 500)],
        label_v=(0.08, 0.95), width=0.34)
    body = [(0, 0), (0.042, 0), (0.046, 0.004), (0.047, 0.056), (0.045, 0.06)]
    cap = [(0.048, 0.058), (0.05, 0.061), (0.05, 0.076), (0.047, 0.08), (0, 0.081)]
    return bottle(body, cap, tex, solid((229, 72, 77), amp=4), GLOSS), dict(yaw=yaw, pitch=24)


def lice_jar():
    yaw = 0
    w, h = 512, 512
    t = np.ones((h, w, 3)) * np.array([196, 214, 214], dtype=np.float64) + noise(w, h, 0.4, 2, 5)[..., None] * 10
    img = to_img(t)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(11)
    for _ in range(140):  # little bugs seen through the glass
        x, y = rng.integers(0, w), rng.integers(int(h * 0.1), int(h * 0.92))
        d.ellipse((x - 5, y - 3, x + 5, y + 3), fill=(28, 24, 20))
        for k in (-1, 1):
            d.line((x - 6, y + 3 * k, x + 6, y - 3 * k), fill=(40, 34, 30), width=1)
    label = label_lathe(w, h, (0, 0, 0), None, yaw, [('LICE', 70, (229, 72, 77), 800), ('do not open', 24, (40, 40, 40), 600)],
                        label_v=(0.4, 0.66), width=0.34)
    lab = np.asarray(label).astype(np.float64)
    arr = np.asarray(img).astype(np.float64)
    u = (((270 + yaw) % 360) / 360.0)
    x0, x1, y0, y1 = int((u - 0.17) * w), int((u + 0.17) * w), int(h * 0.34), int(h * 0.6)
    arr[y0:y1, x0:x1] = np.array([245, 240, 226])
    m = lab[y0:y1, x0:x1].sum(axis=2) > 30
    arr[y0:y1, x0:x1][m] = lab[y0:y1, x0:x1][m]
    tex = to_img(arr)
    body = [(0, 0), (0.034, 0), (0.037, 0.005), (0.037, 0.09), (0.033, 0.097), (0.031, 0.1)]
    cap = [(0.033, 0.098), (0.034, 0.1), (0.034, 0.116), (0.031, 0.119), (0, 0.12)]
    return bottle(body, cap, tex, solid((26, 26, 28), amp=5), PLASTIC, body_mat=GLASS), dict(yaw=yaw, pitch=16)


def hair_remover():
    yaw = 0
    w, h = 512, 512
    t = np.ones((h, w, 3)) * np.array(PINK, dtype=np.float64) + noise(w, h, 0.3, 1.5, 7)[..., None] * 5
    img = to_img(t)
    d = ImageDraw.Draw(img)
    # the tube runs along y; u around it, v along it. Label on the top face (u = 0.25)
    panel = Image.new('RGBA', (int(h * 0.62), int(w * 0.36)), (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    pd.rounded_rectangle((0, 0, panel.width - 1, panel.height - 1), 18, fill=(255, 255, 255, 255))
    pd.text((panel.width / 2, panel.height * 0.36), 'HAIR', font=font(46, 800), fill=(229, 72, 77, 255), anchor='mm')
    pd.text((panel.width / 2, panel.height * 0.72), 'REMOVER', font=font(34, 800), fill=(30, 30, 32, 255), anchor='mm')
    panel = panel.rotate(-90, expand=True)
    img.paste(panel, (int(0.25 * w - panel.width / 2), int(h * 0.22)), panel)
    secs = []
    for i in range(16):
        a = i / 15
        y = a * 0.16
        k = max(0.0, (a - 0.15) / 0.85) ** 1.4
        hw = 0.019 + 0.009 * k
        hh = 0.019 * (1 - k) + 0.0022 * k
        secs.append((y, hw, hh, 2.0 + 2.5 * k, 0.0, 0.0))
    tube = loft_y(secs, 36, (0, 0, 1, 1), caps=[(1, (0.0, 0.95, 0.05, 1.0))])
    crimp = box((-0.029, 0.16, -0.0025), (0.029, 0.172, 0.0025), (0, 0, 1, 1))
    cap = loft_y([(-0.026, 0.0001, 0.0001, 2, 0, 0), (-0.025, 0.012, 0.012, 2, 0, 0), (0.0, 0.012, 0.012, 2, 0, 0)], 32, (0, 0, 1, 1))
    parts = [(tube, img, PLASTIC), (crimp, solid(PINK, amp=3), PLASTIC), (cap, solid((255, 255, 255), amp=2), GLOSS)]
    return [(p.transformed(R=rot('z', 90)), t_, m) for p, t_, m in parts], dict(yaw=-30, pitch=34)


def mud_bag():
    w, h = 512, 512
    t = np.ones((h, w, 3)) * np.array([150, 112, 72], dtype=np.float64)
    weave = (np.indices((h, w)).sum(axis=0) % 6 < 3) * 10 - 5
    t += weave[..., None] + noise(w, h, 0.8, 0.8, 21)[..., None] * 12
    img = to_img(t)
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(3)
    for _ in range(26):  # mud stains
        x, y, r = rng.integers(0, w), rng.integers(int(h * 0.3), h), rng.integers(10, 38)
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=(78, 54, 32))
    u = (270 / 360.0)
    d.text((u * w, h * 0.45), 'MUD', font=font(70, 800), fill=(60, 40, 22), anchor='mm')
    img = img.transpose(Image.FLIP_TOP_BOTTOM)
    prof = [(0.0, 0.0), (0.045, 0.002), (0.062, 0.02), (0.066, 0.05), (0.06, 0.08), (0.044, 0.1), (0.022, 0.112), (0.016, 0.118),
            (0.024, 0.128), (0.03, 0.138), (0.022, 0.142)]
    sack = lathe(prof, 48, (0, 0, 1, 1), scale=(1.0, 0.86))
    # lumpy: push the vertices around a little
    P = sack.P.copy()
    rnd = np.random.default_rng(8)
    P[:, :2] *= (1 + 0.04 * np.sin(np.arctan2(P[:, 1], P[:, 0])[:, None] * 5 + P[:, 2:3] * 40))
    sack = Part(P, sack.N, sack.UV, sack.T)
    tie = torus(0.0175, 0.0035, 32, 10, (0, 0, 1, 1)).transformed(t=(0, 0, 0.118), s=(1, 0.86, 1))
    return [(two_sided(sack), img, MATTE), (tie, solid((200, 170, 110), amp=6), MATTE)], dict(yaw=0, pitch=14)


def wig_kit():
    case = loft_y([(-0.07, 0.0001, 0.0001, 4, 0, 0.025), (-0.069, 0.1, 0.028, 4, 0, 0.025), (0.069, 0.1, 0.028, 4, 0, 0.025),
                   (0.07, 0.0001, 0.0001, 4, 0, 0.025)], 40, (0, 0, 1, 1)).transformed(R=rot('z', 90))
    zip_ = loft_y([(-0.0702, 0.1002, 0.003, 4, 0, 0.026), (0.0702, 0.1002, 0.003, 4, 0, 0.026)], 40, (0, 0, 1, 1)).transformed(R=rot('z', 90))
    handle = torus(0.022, 0.004, 24, 8, (0, 0, 1, 1), a0=0, a1=180).transformed(R=rot('x', 90), t=(0, 0, 0.053))
    # comb + brush on top
    comb = [box((-0.06, -0.012, 0.053), (0.04, 0.0, 0.056), (0, 0, 1, 1))]
    for i in range(16):
        x = -0.056 + i * 0.006
        comb.append(box((x, 0.0, 0.053), (x + 0.0025, 0.014, 0.0555), (0, 0, 1, 1)))
    comb = merge(comb).transformed(R=rot('z', -12), t=(0.0, -0.02, 0.0))
    top = loft_y([(-0.03, 0.0001, 0.0001, 3, 0, 0.0585), (-0.029, 0.035, 0.004, 3, 0, 0.0585), (0.029, 0.035, 0.004, 3, 0, 0.0585),
                  (0.03, 0.0001, 0.0001, 3, 0, 0.0585)], 24, (0, 0, 1, 1))
    logo = Image.new('RGB', (256, 128), (22, 23, 25))
    ImageDraw.Draw(logo).text((128, 64), 'NZ WIG KIT', font=font(30, 800), fill=TEAL_HI, anchor='mm')
    plate = box((-0.03, 0.03, 0.025), (0.03, 0.06, 0.0532), (0, 0, 1, 1), faces=['+z']).transformed(R=rot('z', 90), t=(0.06, 0, 0))
    return [(case, solid((26, 27, 29), amp=4), PLASTIC), (zip_, solid(TEAL, amp=3), GLOSS), (handle, solid((40, 42, 44)), MATTE),
            (comb, solid((235, 235, 232), amp=2), PLASTIC)], dict(yaw=28, pitch=34)


def scissors():
    def blade(sign):
        secs = []
        for i in range(12):
            a = i / 11
            y = 0.01 + a * 0.095
            hw = 0.0075 * (1 - a) ** 0.6 + 0.0008
            secs.append((y, hw, 0.0012, 2.6, sign * hw * 0.5, 0.0))
        return loft_y(secs, 16, (0, 0, 1, 1), caps=[(0, (0, 0, 0.1, 0.1))])

    def handle(sign):
        arm = loft_y([(0.012, 0.0035, 0.0028, 2.4, 0, 0), (-0.03, 0.0035, 0.0028, 2.4, sign * 0.006, 0)], 14, (0, 0, 1, 1))
        ring = torus(0.0135, 0.0032, 32, 10, (0, 0, 1, 1)).transformed(t=(sign * 0.012, -0.043, 0))
        return [arm, ring]

    out = []
    for sign, ang in ((1, 9), (-1, -9)):
        b = blade(sign).transformed(R=rot('z', ang))
        out.append((b, solid((205, 210, 215), amp=6), METAL))
        for h in handle(sign):
            out.append((h.transformed(R=rot('z', ang)), solid((20, 20, 22), amp=3), GLOSS))
    screw = lathe([(0, 0.0016), (0.0028, 0.0016), (0.0028, -0.0016), (0, -0.0016)], 16, (0, 0, 1, 1)).transformed(t=(0, 0.012, 0))
    out.append((screw, solid((150, 155, 160)), METAL))
    return out, dict(yaw=20, pitch=55)


def zip_ties():
    out = []
    for k, (ang, off) in enumerate(((0, (0, 0, 0)), (140, (0.034, 0.018, 0.0)))):
        band = lathe([(0.026, -0.0028), (0.0292, -0.0028), (0.0292, 0.0028), (0.026, 0.0028), (0.026, -0.0028)], 48, (0, 0, 1, 1))
        head = box((0.024, -0.005, -0.004), (0.035, 0.005, 0.004), (0, 0, 1, 1))
        tail = box((0.029, 0.004, -0.0028), (0.0322, 0.05, 0.0028), (0, 0, 1, 1))
        tie = merge([band, head, tail]).transformed(R=rot('z', ang) @ rot('x', 8 if k else 0), t=off)
        out.append((tie, solid((24, 24, 26), amp=4), GLOSS))
    return out, dict(yaw=25, pitch=50)


def hair_weft():
    cols, rows = 40, 18
    G = []
    for r in range(rows):
        v = r / (rows - 1)
        ring = []
        for c in range(cols):
            u = c / (cols - 1)
            x = (u - 0.5) * 0.16
            y = 0.03 * math.sin(u * math.pi) - 0.015 + 0.004 * math.sin(v * 9 + u * 20) * v
            z = -v * 0.15
            ring.append((x, y + v * 0.02 * math.sin(u * 12), z))
        G.append(ring)
    sheet = surface(np.array(G), (0, 0, 1, 1), closed=False, center=(0, 0.2, -0.07))
    tex = to_img(hair_texture(512, 512, seed=61))
    track = loft_y([(-0.082, 0.004, 0.004, 3, 0, 0.002), (0.082, 0.004, 0.004, 3, 0, 0.002)], 12, (0, 0, 1, 1)).transformed(R=rot('z', 90))
    P = track.P.copy()
    P[:, 1] += 0.03 * np.sin((P[:, 0] / 0.164 + 0.5) * math.pi) - 0.015
    track = Part(P, track.N, track.UV, track.T)
    return [(two_sided(sheet), tex, HAIR), (track, solid((22, 22, 24)), PLASTIC)], dict(yaw=10, pitch=12)


def wig_thread():
    spool = lathe([(0.0, 0.0), (0.03, 0.0), (0.031, 0.002), (0.031, 0.008), (0.02, 0.009), (0.02, 0.071), (0.031, 0.072), (0.031, 0.078),
                   (0.03, 0.08), (0.0, 0.08)], 40, (0, 0, 1, 1))
    w, h = 256, 256
    t = np.ones((h, w, 3)) * np.array([30, 32, 36], dtype=np.float64)
    for y in range(0, h, 3):
        t[y, :] += 18
    thread = lathe([(0.0255, 0.0085), (0.0262, 0.04), (0.0255, 0.0715)], 40, (0, 0, 1, 1))
    needle = lathe([(0.0, 0.0), (0.0011, 0.004), (0.0011, 0.07), (0.0006, 0.074), (0.0, 0.075)], 10, (0, 0, 1, 1)).transformed(
        R=rot('y', 72) @ rot('z', 0), t=(-0.03, -0.034, 0.004))
    return [(spool, solid((200, 160, 110), amp=8), MATTE), (thread, to_img(t), MATTE), (needle, solid((200, 205, 210)), METAL)], dict(yaw=25, pitch=22)


def lace(kind):
    """Lace closure (square), frontal (long band), full lace (a cap) with a little tier tag."""
    tag_col = {'closure': (70, 192, 138), 'frontal': (61, 155, 255), 'full': (168, 115, 255)}[kind]
    tag_txt = {'closure': '5x5', 'frontal': '13x4', 'full': 'FULL'}[kind]
    tex = net_texture(512, 512, base=(232, 208, 182), line=(176, 146, 118), step=8)
    if kind == 'full':
        prof = [(0.0, 0.11)] + [(0.08 * math.sin(math.radians(a)), 0.11 * math.cos(math.radians(a))) for a in range(6, 91, 6)]
        sheet = two_sided(lathe(prof, 48, (0, 0, 1, 1), scale=(0.92, 1.08)))
        tag_at = (0.0, -0.088, 0.03)
        view = dict(yaw=20, pitch=26)
    else:
        wx, wy = (0.1, 0.1) if kind == 'closure' else (0.2, 0.06)
        G = []
        for r in range(14):
            v = r / 13
            ring = []
            for c in range(28):
                u = c / 27
                x = (u - 0.5) * wx
                y = (v - 0.5) * wy
                z = -((x / wx) ** 2 + (y / wy) ** 2) * (0.03 if kind == 'closure' else 0.025) + 0.002 * math.sin(u * 13 + v * 7)
                if kind == 'frontal':
                    y += 0.05 * (x / wx) ** 2 * 4 * 0.25
                ring.append((x, y, z))
            G.append(ring)
        sheet = two_sided(surface(np.array(G), (0, 0, 1, 1), closed=False, center=(0, 0, -1)))
        tag_at = (0.0, -wy / 2 - 0.002, -0.004)
        view = dict(yaw=15, pitch=48)
    tag_img = Image.new('RGB', (256, 128), tag_col)
    ImageDraw.Draw(tag_img).text((128, 64), tag_txt, font=font(64, 800), fill=(255, 255, 255), anchor='mm')
    tag = box((-0.022, -0.0015, -0.011), (0.022, 0.0015, 0.011), (0, 0, 1, 1)).transformed(t=tag_at)
    return [(sheet, tex, MATTE), (tag, tag_img, PLASTIC)], view


ITEMS = {
    'wig': lambda: wig(),
    'hair_bundle': hair_bundle,
    'wig_cap': wig_cap,
    'hair_dye': hair_dye,
    'wig_glue': wig_glue,
    'wig_kit': wig_kit,
    'scissors': scissors,
    'hair_clippers': hair_clippers,
    'straight_razor': straight_razor,
    'zip_ties': zip_ties,
    'hair_remover': hair_remover,
    'relaxer': relaxer,
    'lice_jar': lice_jar,
    'mud_bag': mud_bag,
    'shampoo': shampoo,
    'regrowth_oil': regrowth_oil,
    'hair_weft': hair_weft,
    'wig_thread': wig_thread,
    'lace_closure': lambda: lace('closure'),
    'lace_frontal': lambda: lace('frontal'),
    'lace_full': lambda: lace('full'),
}

# Config.Wig.Images = 'tier': one wig per tier, in that tier's look
TIERS = {
    'common':    ((26, 18, 14), (52, 36, 26), (92, 66, 48)),
    'uncommon':  ((52, 30, 16), (96, 58, 32), (150, 102, 60)),
    'rare':      ((10, 10, 12), (30, 30, 34), (70, 70, 78)),
    'epic':      ((56, 10, 22), (110, 24, 42), (170, 60, 80)),
    'legendary': ((150, 108, 50), (212, 170, 96), (250, 226, 160)),
    'mythic':    ((6, 80, 76), (8, 160, 150), (120, 230, 220)),
}

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'icons'
    only = set(sys.argv[2:])
    os.makedirs(out, exist_ok=True)
    jobs = [(k, f) for k, f in ITEMS.items()]
    jobs += [('wig_' + t, (lambda cols, s: (lambda: wig(cols, s)))(cols, 70 + i)) for i, (t, cols) in enumerate(TIERS.items())]
    done = []
    for name, fn in jobs:
        if only and name not in only:
            continue
        items, view = fn()
        icon = render_icon(items, **view)
        icon.save(os.path.join(out, name + '.png'))
        done.append((name, icon))
        print('icon', name)
    cols = 9
    sheet = Image.new('RGBA', (cols * 140, ((len(done) + cols - 1) // cols) * 140), (40, 42, 44, 255))
    for i, (name, icon) in enumerate(done):
        sheet.alpha_composite(icon.resize((130, 130), Image.LANCZOS), ((i % cols) * 140 + 5, (i // cols) * 140 + 5))
    sheet.save(os.path.join(out, '_sheet.png'))
