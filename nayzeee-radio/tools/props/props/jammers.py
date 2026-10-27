"""
Jammers (PROPS_BRIEF section 5, SPEC sections 9.1 / 14): three placeable RF jammers.

    nzr_jammer_pocket   JX-10   black anodised aluminium brick, machined heatsink fins, 6 splayed stubby antennas
    nzr_jammer_case     JX-40   rugged field hard case, lid open ~100 deg, electronics deck, 8 folding antennas
    nzr_jammer_heavy    JX-90   olive steel cabinet on feet with a welded tube mast carrying 8 whips

All three: origin = bottom centre (they stand on the ground), +Y = front, +Z up, +X = the viewer's left when
facing the front. client/modules/jammers.lua spawns them frozen on the ground; the layout gets
`jammers.<type> = { model, size (= model bounds), interact }` from b.anchor(jammer=..., interact=...).

Labelling (Rule B): model codes JX-10 / JX-40 / JX-90, generic band / port / switch legends, rating plates
with fictitious identifiers, caution / danger stickers. No maker name, no NAYZEEE mark anywhere.

LOD (PROPS_BRIEF): high model up to 20 m, medium model 20 m -> lodDist 150 m. Fine detail (screws, LEDs,
legend plates, fan blades, cable boots ...) is added with b.hi_only(); antennas get cheap 'm' stand-ins.
"""
from __future__ import annotations

import math
from dataclasses import replace as dc_replace

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from nzprops import (DecalCanvas, Geo, axis_angle, box, catmull, cylinder, extrude, lathe, normalize, poly_cap,
                     polyline_fillet, prop, quad, rrect, sweep, torus, tube, vec)
from nzprops.mesh import _rrect_n, loft
from nzprops.paint import font

from .common import align, caution_label, led_lens, m_rubber, rating_plate, rubber_foot, screw
from .radio_common import (INK, ink, lanyard_eye, m_anodised_black, m_print_dark, m_sma, m_smoked_glass, model_print,
                           sma_nut)

# =============================================================================================
# shared helpers
# =============================================================================================
YZX = np.array([[0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])   # profile (y, z) extruded along +X


def _frame(normal, up):
    """(right, up, normal) of a surface the way align() / decals see it (viewer looks at the surface)."""
    n = normalize(vec(normal))
    u = vec(up) - n * float(np.dot(vec(up), n))
    u = normalize(u)
    return np.cross(u, n), u, n


def _round(poly, radii, n=4):
    """Fillet every corner of a CCW polygon with its own radius (radii: list or one number)."""
    p = np.asarray(poly, np.float64)
    m = len(p)
    rs = radii if hasattr(radii, "__len__") else [radii] * m
    out = []
    for i in range(m):
        a, b_, c = p[i - 1], p[i], p[(i + 1) % m]
        r = float(rs[i])
        d1, d2 = a - b_, c - b_
        l1, l2 = float(np.linalg.norm(d1)), float(np.linalg.norm(d2))
        if r <= 0 or l1 < 1e-12 or l2 < 1e-12:
            out.append(b_)
            continue
        d1, d2 = d1 / l1, d2 / l2
        ang = math.acos(float(np.clip(np.dot(d1, d2), -1, 1)))
        if ang > math.pi - 1e-4:
            out.append(b_)
            continue
        t = min(r / math.tan(ang / 2), l1 * 0.5, l2 * 0.5)
        rr = t * math.tan(ang / 2)
        p1, p2 = b_ + d1 * t, b_ + d2 * t
        bis = normalize(d1 + d2)
        ctr = b_ + bis * (rr / math.sin(ang / 2))
        a0 = math.atan2(p1[1] - ctr[1], p1[0] - ctr[0])
        a1 = math.atan2(p2[1] - ctr[1], p2[0] - ctr[0])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(n + 1):
            aa = a0 + da * k / n
            out.append(ctr + rr * np.array([math.cos(aa), math.sin(aa)]))
    res = [out[0]]
    for q in out[1:]:
        if np.linalg.norm(q - res[-1]) > 1e-9:
            res.append(q)
    if np.linalg.norm(res[0] - res[-1]) < 1e-9:
        res.pop()
    return np.asarray(res)


def _support(poly, eps=0.00008):
    """Support points eps from both ends of every long edge: flat faces keep flat normals right up to
    the fillets (the smooth-shading gradient lives in the eps strip only)."""
    p = np.asarray(poly, np.float64)
    out = []
    for i in range(len(p)):
        a, c = p[i], p[(i + 1) % len(p)]
        out.append(a)
        L = float(np.linalg.norm(c - a))
        if L > 5 * eps:
            d = (c - a) / L
            out += [a + d * eps, c - d * eps]
    return np.asarray(out)


def _profile_bar(poly, x0, x1, mat, caps=True, tag="bar", smooth=38.0, side_mat=None, cap_mat=None):
    """Extrude a rounded (y, z) profile along X from x0 to x1: flat faces stay flat (support points), the
    end caps are triangulated from the clean outline."""
    g = extrude(_support(poly), x1 - x0, side_mat or mat, z0=x0, caps=(False, False), smooth_angle=smooth, tag=tag)
    if caps:
        g += poly_cap(poly, x0, cap_mat or mat, up=False, tag=tag + ":cap0")
        g += poly_cap(poly, x1, cap_mat or mat, up=True, tag=tag + ":cap1")
    return g.transform(YZX)


def _hex(across):
    r = across / 2 / math.cos(math.radians(30))
    return np.array([(r * math.cos(math.radians(60 * k + 30)), r * math.sin(math.radians(60 * k + 30))) for k in range(6)])


def _ring_window(b, center, normal, up, outer, r_out, view, r_in, t, recess, frame_mat, floor_mat, chamfer=0.0003,
                 bevel=0.0004, n=4, bevel_seg=2):
    """A rounded frame plate (outer w x h, corner r_out, standing t proud of the surface) with a rounded
    opening (view w x h, corner r_in) that falls `recess` deep to a floor. Returns (Geo, floor centre)."""
    ow, oh = outer
    vw, vh = view
    g = Geo()
    rim = extrude(rrect(ow, oh, r_out, n), t, frame_mat, bevel=bevel, bevel_seg=bevel_seg, caps=(False, True), smooth_angle=50,
                  tag="win:rim")
    rim.charts = [c for c in rim.charts if not c.tag.endswith(":top")]
    g += rim
    ztop = t
    A = _rrect_n(ow - 2 * bevel, oh - 2 * bevel, max(r_out - bevel, 1e-4), n)
    B = _rrect_n(vw + 2 * chamfer, vh + 2 * chamfer, r_in + chamfer, n)
    C = _rrect_n(vw, vh, r_in, n)
    z3 = lambda P, z: np.concatenate([P, np.full((len(P), 1), z)], axis=1)   # noqa: E731
    g += loft(z3(A, ztop), z3(B, ztop), frame_mat, tag="win:top")
    g += loft(z3(B, ztop), z3(C, ztop - chamfer), frame_mat, tag="win:chamfer")
    dep = max(recess - chamfer, 1e-5)
    g += extrude(rrect(vw, vh, r_in, n), dep, floor_mat, caps=(False, False), z0=ztop - chamfer - dep, smooth_angle=50,
                 tag="win:well").flip()
    g += poly_cap(rrect(vw, vh, r_in, n), ztop - recess, floor_mat, up=True, tag="win:floor")
    _, _, nn = _frame(normal, up)
    align(g, normal, up, center)
    return g, vec(center) + nn * (ztop - recess)


def _stencil(dc: DecalCanvas, x, y, s, size, color, spacing=0.0, bridge=0.11, fnt="label-black", wear=0.25, seed=1):
    """Spray-stencilled text: bridges cut through the closed counters (0 4 6 8 9 A B D O P Q R) and a
    slightly uneven, worn spray edge."""
    m = dc.text(x, y, s, size, fnt=fnt, anchor="mm", spacing=spacing)     # no ink: just the glyph mask
    W, H = dc.W, dc.H
    total = dc.text_width(s, size, fnt, spacing)
    x0 = x - total / 2
    cut = np.ones((H, W), np.float32)
    px = size * 1.38
    for ch in s:
        cw = dc.text_width(ch, size, fnt)
        if ch.upper() in "0468ABDOPQR9":
            cx = x0 + cw / 2
            bw = size * bridge
            i0, i1 = int((cx - bw / 2) * dc.ppm), int((cx + bw / 2) * dc.ppm)
            j0, j1 = int((y - px) * dc.ppm), int((y + px) * dc.ppm)
            cut[max(0, j0):max(0, j1), max(0, i0):max(0, i1)] = 0.0
        x0 += cw + spacing
    rng = np.random.default_rng(seed)
    nz = np.asarray(Image.fromarray((rng.random((max(2, H // 6), max(2, W // 6))) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC),
                    np.float32) / 255.0
    spray = np.clip(1.0 - wear * np.clip(nz * 1.6 - 0.45, 0, 1), 0, 1)
    mask = np.clip(m * cut, 0, 1)
    soft = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
    dc.ink(np.maximum(mask, soft * 0.35) * spray, color=color, spec=0.22, gloss=0.3)


def _status_image(lines, size, color=(255, 70, 44), ghost=(34, 12, 10), bg=(7, 5, 5)):
    """Small emissive status display (PIL image) drawn with VT323 + blocks. `lines` is a callable
    painting on (ImageDraw, scale, colour, ghost colour)."""
    W, H = size
    S = 4
    img = Image.new("RGB", (W * S, H * S), bg)
    d = ImageDraw.Draw(img)
    # faint backlight bloom + pixel row structure
    lines(d, S, color, ghost)
    img = img.resize((W, H), Image.LANCZOS)
    glow = img.filter(ImageFilter.GaussianBlur(2.2))
    arr = np.asarray(img, np.float32) + np.asarray(glow, np.float32) * 0.55
    rows = np.ones((H, 1, 1), np.float32)
    rows[::2] = 0.9
    arr = np.clip(arr * rows, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


# =============================================================================================
# JX-10 pocket jammer  120 x 70 x 28 mm
# =============================================================================================
PL, PD = 0.120, 0.070          # length (X), depth (Y)
PZ0, PZT, PZF = 0.0018, 0.0215, 0.028   # body bottom (on the feet), deck, fin tops
P_END = 0.003                  # end plate thickness
P_FIN_Y0, P_FIN_N, P_FIN_T, P_FIN_P = 0.006, 8, 0.0016, 0.0034   # first fin front face, count, thickness, pitch
P_ANT_Y = -0.027
P_ANT_X = (0.050, 0.030, 0.010, -0.010, -0.030, -0.050)
P_ANT_LEN = (0.090, 0.074, 0.062, 0.062, 0.074, 0.090)
P_ANT_SPLAY = (24.0, 14.0, 5.0, -5.0, -14.0, -24.0)
P_BANDS = (("433", (226, 52, 48)), ("868", (238, 120, 32)), ("1.5G", (236, 196, 40)), ("2.4G", (70, 190, 90)),
           ("3.5G", (40, 120, 220)), ("5.8G", (230, 232, 234)))
P_WIN = (0.030, 0.0205)        # status window centre (x, y) on the deck
P_TOG = (-0.017, 0.0205)       # guarded toggle
P_TOG_D = 0.0215               # guard plate depth (Y): room for the ARM / SAFE legends past the nut
P_LED = ((-0.038, 0.0175, "red", "TX"), (-0.049, 0.0175, "green", "PWR"))


def _pocket_profile():
    """Body + fin comb cross-section in (y, z), CCW, every corner filleted."""
    pts, rad = [], []
    R_BODY, R_TIP, R_ROOT = 0.0026, 0.00045, 0.0006

    def add(y, z, r):
        pts.append((y, z))
        rad.append(r)
    add(-PD / 2, PZ0, R_BODY)
    add(PD / 2, PZ0, R_BODY)
    add(PD / 2, PZT, R_BODY)
    for k in range(P_FIN_N):
        yf = P_FIN_Y0 - k * P_FIN_P
        add(yf, PZT, R_ROOT)
        add(yf, PZF, R_TIP)
        add(yf - P_FIN_T, PZF, R_TIP)
        add(yf - P_FIN_T, PZT, R_ROOT)
    add(-PD / 2, PZT, R_BODY)
    return _round(pts, rad, n=4)


def _stubby(b, base, axis, length, d, band_col, segs=14, tag="antenna_stub", k=1.0, taper=0.84, ribs=3):
    """Rubber antenna from a hinge knuckle centre `base` along `axis`: rounded collar, ribbed boot,
    coloured band-ID ring, tapering body, rounded tip. k scales the collar / boot / band lengths."""
    rub = b.mat("stub_rubber", color=(23, 24, 26), spec=0.16, gloss=0.28, bump="rubber", bump_amp=0.00003,
                bump_scale=0.0006, grain=0.03, grain_scale=0.02, edge=0.35, dirt=0.15, wear_color=(70, 72, 76))
    R = d / 2
    tipR = R * taper
    prof = [(0.0, 0.0), (R * 0.95, 0.0), (R * 1.02, 0.0012 * k), (R * 1.02, 0.0034 * k), (R * 0.9, 0.0042 * k)]
    for i in range(ribs):
        z0 = (0.0046 + i * 0.0034) * k
        prof += [(R * 1.0, z0), (R * 1.1, z0 + 0.0006 * k), (R * 1.1, z0 + 0.0019 * k), (R * 1.0, z0 + 0.0025 * k)]
    zb = prof[-1][1] + 0.001 * k
    zt = length - tipR

    def rad(z):
        return R * 0.98 + (tipR - R * 0.98) * (z - zb) / max(zt - zb, 1e-6)
    prof += [(rad(zb), zb)]
    g = lathe(prof, rub, segs=segs, smooth_angle=50, tag=tag)
    band = b.mat(f"band_{band_col[0]}_{band_col[1]}_{band_col[2]}", color=band_col, spec=0.3, gloss=0.45, grain=0.02, edge=0.3,
                 dirt=0.15)
    b0, b1 = zb + 0.0012 * k, zb + 0.0042 * k
    g += lathe([(rad(zb), zb), (rad(b0), b0)], rub, segs=segs, smooth_angle=60, tag=tag)
    g += lathe([(rad(b0), b0), (rad(b0) + 0.00015, b0 + 0.0002), (rad(b1) + 0.00015, b1 - 0.0002), (rad(b1), b1)], band, segs=segs,
               smooth_angle=60, tag=tag + "_band")
    top = [(rad(b1), b1), (rad((b1 + zt) / 2), (b1 + zt) / 2), (rad(zt), zt)]
    top += [(tipR * math.cos(a), zt + tipR * math.sin(a)) for a in np.linspace(0.35, math.pi / 2, 4)]
    top[-1] = (0.0, top[-1][1])
    g += lathe(top, rub, segs=segs, smooth_angle=50, tag=tag)
    return align(g, axis, (0, 1, 0) if abs(vec(axis)[1]) < 0.9 else (1, 0, 0), base)


def _jx10_screen():
    def paint(d, S, col, ghost):
        f = font("lcd", 58 * S)
        d.text((12 * S, 33 * S), "JAM", font=f, fill=col, anchor="lm")
        for k in range(5):
            x0 = (112 + k * 21) * S
            d.rectangle([x0, 15 * S, x0 + 15 * S, 51 * S], fill=col if k < 3 else ghost)
        # battery glyph
        bx, by = 222 * S, 20 * S
        d.rectangle([bx, by, bx + 24 * S, by + 24 * S], outline=col, width=3 * S)
        d.rectangle([bx + 24 * S, by + 8 * S, bx + 28 * S, by + 16 * S], fill=col)
        for k in range(3):
            d.rectangle([bx + (4 + k * 7) * S, by + 5 * S, bx + (9 + k * 7) * S, by + 19 * S], fill=col if k < 2 else ghost)
        small = font("lcd", 14 * S)
        d.text((112 * S, 58 * S), "1 2 3 4 5 6", font=small, fill=ghost, anchor="lm")
    return _status_image(paint, (256, 64))


def _pocket_deck_prints(b):
    alu = "anodised_black"
    # window legend + band / port legends on the deck (white / grey pad print)
    dc = DecalCanvas(0.112, 0.027, ppm=9000)
    W, H = 0.112, 0.027

    def X(x):          # prop x -> canvas x (canvas x runs to -X, centred on x = 0)
        return W / 2 - x

    def Y(y):          # prop y -> canvas y (the canvas top edge faces -Y: canvas y runs to +Y)
        return (y - 0.0205) + H / 2
    # status window caption
    dc.text(X(P_WIN[0] + 0.020), Y(0.0310), "STATUS", 0.0016, fnt="label", anchor="lm", spacing=0.0003, **ink("grey"))
    dc.rect(X(P_WIN[0] + 0.020) + 0.0105, Y(0.0310) - 0.0001, 0.026, 0.00018, **ink("grey"))
    # toggle legends on the red guard plate are printed separately; deck legends beside it
    for x, y, col, word in P_LED:
        dc.text(X(x), Y(y + 0.0062), word, 0.0017, fnt="label", **ink("white"))
    b.decal(dc, center=(0.0, 0.0205, PZT), normal=(0, 0, 1), up=(0, -1, 0), mats=[alu], depth=0.0012, min_dot=0.8)
    # rear deck: band numbers + frequencies under each antenna
    dr = DecalCanvas(0.112, 0.012, ppm=9000)
    for k, x in enumerate(P_ANT_X):
        cx = 0.056 - x
        dr.text(cx + 0.0068, 0.0040, f"B{k + 1}", 0.0016, fnt="label", anchor="lm", **ink("white"))
        dr.text(cx + 0.0068, 0.0076, P_BANDS[k][0], 0.0013, fnt="label-semi", anchor="lm", **ink("grey"))
        dr.rect(cx + 0.0062, 0.0026, 0.00035, 0.0064, color=P_BANDS[k][1], spec=0.3, gloss=0.45, height=0.000006)
    b.decal(dr, center=(0.0, P_ANT_Y, PZT), normal=(0, 0, 1), up=(0, -1, 0), mats=[alu], depth=0.0012, min_dot=0.8)


@prop("nzr_jammer_pocket", atlas=2048, alpha_atlas=128, glow_atlas=32, lod=150.0, lod_high=20.0, hd=12.0, med_drop=0.004,
      budget=12000, falloff=90.0,
      doc={"title": "JX-10 pocket jammer (120 x 70 x 28 mm brick, 6 stubby antennas)",
           "origin": "bottom centre (lies flat on the ground on four rubber feet)",
           "axes": "+Y = front (status window, guarded toggle, LEDs on the deck), +Z up, length along X; antennas on the rear deck",
           "attach": "placed on the ground (client/modules/jammers.lua): frozen, non-networked; ghost while placing"},
      preview={"views": ["front", "iso", "front34", "top", "back", "left", "right", "face"]})
def jammer_pocket(b):
    alu = m_anodised_black(b)
    endm = b.mat("endplate_anod", color=(40, 42, 46), spec=0.52, gloss=0.48, metal=0.8, bump="brushed", bump_amp=0.000006,
                 bump_scale=0.0005, grain=0.02, grain_scale=0.03, edge=0.75, wear_color=(160, 164, 170), dirt=0.12)
    red = b.mat("guard_red", color=(168, 30, 30), spec=0.55, gloss=0.55, metal=0.7, bump="brushed", bump_amp=0.000005,
                bump_scale=0.0004, grain=0.02, edge=0.7, wear_color=(205, 190, 186), dirt=0.08)
    nickel = m_sma(b, "nickel")
    gloss = b.mat("lens_plate", color=(10, 11, 12), spec=0.75, gloss=0.88, grain=0.01, edge=0.35, ao=0.6)
    floor = m_print_dark(b)

    # ---- body: extruded profile with the fin comb, closed by end plates ----------------------------------
    xb = PL / 2 - P_END
    prof = _pocket_profile()
    body = _profile_bar(prof, -xb, xb, alu, tag="body")
    for c in body.charts:
        if c.tag.startswith("body") and not c.tag.endswith(("cap0", "cap1")):
            c.density = 1.15
    b.add(body)
    # end plates: slightly larger than the profile's body part, bevelled all round
    ep = _round([(-PD / 2 - 0.0005, PZ0 - 0.0004), (PD / 2 + 0.0005, PZ0 - 0.0004), (PD / 2 + 0.0005, PZT + 0.0004),
                 (-PD / 2 - 0.0005, PZT + 0.0004)], 0.0031, n=4)
    for sx in (1, -1):
        x0 = xb if sx > 0 else -PL / 2
        plate = extrude(ep, P_END, endm, bevel=0.0007, bevel_seg=2, z0=x0, smooth_angle=50, tag="endplate").transform(YZX)
        b.add(plate)
        zc = (PZ0 + PZT) / 2
        pts = [(sx * PL / 2, yy, zz) for yy in (-0.029, 0.029) for zz in (zc - 0.0062, zc + 0.0062)]
        for p in pts:
            b.hi_only(screw(b, p, (sx, 0, 0), (0, 0, 1), d=0.0034, kind="torx", color=(58, 60, 64), segs=8))
    zc = (PZ0 + PZT) / 2
    # -X end (the viewer's right): DC jack, USB-C, charge LED
    jx = -PL / 2
    jack = lathe([(0.0, 0.0), (0.0042, 0.0), (0.0042, 0.0012), (0.0036, 0.0016), (0.0026, 0.0016), (0.0024, 0.0008),
                  (0.0012, 0.0004), (0.0, 0.0004)], nickel, segs=20, smooth_angle=50, tag="jack")
    jack += cylinder(0.0006, 0.0011, b.mat("pin_gold", color=(208, 166, 78), spec=0.9, gloss=0.75, metal=1.0), segs=8, z0=0.0004)
    b.add(align(jack, (-1, 0, 0), (0, 0, 1), (jx, 0.016, zc)))
    usb = extrude(rrect(0.0094, 0.0034, 0.0016, 4), 0.0005, nickel, bevel=0.00012, bevel_seg=1, smooth_angle=50,
                  cap_mat=b.mat("port_dark", color=(10, 10, 11), spec=0.2, gloss=0.3, ao=1.0), tag="usb")
    b.add(align(usb, (-1, 0, 0), (0, 0, 1), (jx, -0.004, zc)))
    b.hi_only(led_lens(b, (jx, -0.018, zc), (-1, 0, 0), (0, 0, 1), r=0.0011, color=(255, 170, 30), name="led_amber"))
    # +X end: lanyard eye + vent slots (decal)
    b.add(lanyard_eye(b, (PL / 2, 0.0, zc - 0.0035), (1, 0, 0), (0, 0, 1), r=0.0042, wire=0.0013, mat=endm))
    # ---- feet ---------------------------------------------------------------------------------------------
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(rubber_foot(b, sx * 0.047, sy * 0.025, 0.0, r=0.0052, h=PZ0 + 0.0003, segs=10))

    # ---- deck: status window ------------------------------------------------------------------------------
    win, flo = _ring_window(b, (P_WIN[0], P_WIN[1], PZT), (0, 0, 1), (0, -1, 0), (0.044, 0.0150), 0.0024, (0.0352, 0.0092),
                            0.0009, 0.0011, 0.0008, gloss, floor)
    b.add(win)
    right, upv, nn = _frame((0, 0, 1), (0, -1, 0))
    b.screen(quad(flo + nn * 0.00005, right, upv, 0.0336, 0.0084, "x", fixed_uv=True), texname="nzr_jx10_scr",
             image=_jx10_screen(), mult=1.2, size=(256, 64))
    b.add(quad(flo + nn * 0.00055, right, upv, 0.0350, 0.0090, m_smoked_glass(b, 0.2), tag="glass"))

    # ---- deck: guarded toggle switch ----------------------------------------------------------------------
    tx, ty = P_TOG
    g = extrude(rrect(0.024, P_TOG_D, 0.0028, 4), 0.0012, red, bevel=0.0004, bevel_seg=2, z0=PZT, smooth_angle=50, tag="guard_plate")
    g.translate(tx, ty, 0)
    b.add(g)
    for sx in (-1, 1):
        ear = extrude(_round([(-0.0068, 0.0), (0.0068, 0.0), (0.0068, 0.0118), (0.0040, 0.0152), (-0.0040, 0.0152),
                              (-0.0068, 0.0118)], [0.0004, 0.0004, 0.004, 0.002, 0.002, 0.004], n=3),
                      0.0022, red, bevel=0.0005, bevel_seg=1, smooth_angle=45, tag="guard_ear")
        # profile in (y, z) -> extrude along X
        ear.transform(YZX).translate(tx + sx * 0.0068 - 0.0011, ty, PZT + 0.0012)
        b.add(ear)
    zt = PZT + 0.0012
    b.add(extrude(_hex(0.0084), 0.0018, nickel, bevel=0.0003, bevel_seg=1, z0=zt, smooth_angle=20, tag="tog_nut").translate(tx, ty, 0))
    thr = b.mat("tog_thread", color=(176, 178, 182), spec=0.8, gloss=0.6, metal=1.0, bump="ribs", bump_amp=0.00006,
                bump_scale=0.0004, edge=0.3)
    b.add(cylinder(0.0029, 0.0042, thr, segs=18, bevel=0.0002, z0=zt + 0.0018).translate(tx, ty, 0))
    chrome = b.mat("tog_chrome", color=(196, 200, 206), spec=0.95, gloss=0.88, metal=1.0, grain=0.01, edge=0.15)
    bat = lathe([(0.0, 0.0), (0.0013, 0.0), (0.0013, 0.001), (0.00155, 0.0085), (0.00185, 0.0098), (0.0017, 0.0106),
                 (0.0010, 0.0112), (0.0, 0.01135)], chrome, segs=14, smooth_angle=40, tag="tog_bat")
    piv = vec(tx, ty, zt + 0.0058)
    b.add(bat.rotate(22, 0, 0).translate(piv))          # thrown toward ARM (-Y): the status window reads JAM
    # ---- deck: LEDs ----------------------------------------------------------------------------------------
    for x, y, col, _ in P_LED:
        rgb = {"red": (255, 46, 40), "green": (60, 255, 120)}[col]
        b.add(led_lens(b, (x, y, PZT), (0, 0, 1), (0, -1, 0), r=0.0021, color=rgb, name=f"led_{col}"))

    # ---- antennas on the rear deck ---------------------------------------------------------------------------
    knk = b.mat("knuckle_black", color=(30, 31, 33), spec=0.4, gloss=0.5, edge=0.5, dirt=0.1, wear_color=(90, 92, 96))
    fer = b.mat("ferrule_knurl", color=(32, 33, 36), spec=0.55, gloss=0.5, metal=0.8, bump="ribs_u", bump_amp=0.00008,
                bump_scale=0.0005, edge=0.6, wear_color=(150, 152, 156), dirt=0.1)
    thr = b.mat("sma_thread_nickel", color=(176, 178, 182), spec=0.8, gloss=0.6, metal=1.0, bump="ribs", bump_amp=0.00008,
                bump_scale=0.0005, edge=0.3)
    for k, x in enumerate(P_ANT_X):
        ant = Geo()
        # SMA bulkhead: hex nut + threaded barrel, then the antenna's knurled ferrule, hinge knuckle and body
        ant += extrude(_hex(0.0076), 0.0022, nickel, bevel=0.0003, bevel_seg=1, z0=PZT, smooth_angle=20, tag="antenna_nut")
        ant += cylinder(0.0029, 0.0024, thr, segs=12, z0=PZT + 0.0021, caps=(False, False), tag="antenna_thread")
        z1 = PZT + 0.0044
        ant += cylinder(0.0034, 0.0062, fer, segs=12, bevel=0.0004, bevel_seg=1, z0=z1 - 0.001, tag="antenna_ferrule")
        kz = z1 + 0.0052 + 0.0028
        ant.translate(x, P_ANT_Y, 0)
        ant += cylinder(0.0030, 0.0058, knk, segs=12, bevel=0.0005, bevel_seg=1, z0=-0.0029, tag="antenna_knuckle").rotate(
            0, 90, 0).translate(x, P_ANT_Y, kz)
        ant += box((0.0040, 0.0050, 0.0030), knk, r=0.0008, seg=1, center=(x, P_ANT_Y, kz - 0.0018), tag="antenna_yoke")
        ax = axis_angle((0, 1, 0), P_ANT_SPLAY[k]) @ axis_angle((1, 0, 0), 7.0) @ vec(0, 0, 1)
        ant += _stubby(b, vec(x, P_ANT_Y, kz), ax, P_ANT_LEN[k] - 0.012, 0.0072, P_BANDS[k][1], segs=12)
        b.add(ant, lod="h")
        # medium stand-in: nut + one tapered stick (6 sides) from the deck to the tip
        med = extrude(_hex(0.0076), 0.0044, nickel, z0=PZT, caps=(False, True), smooth_angle=20, tag="antenna_med").translate(x, P_ANT_Y, 0)
        med += cylinder(0.0034, kz - PZT - 0.004, "ferrule_knurl", segs=6, z0=PZT + 0.004, caps=(False, False), tag="antenna_med").translate(x, P_ANT_Y, 0)
        st = cylinder(0.0036, P_ANT_LEN[k] - 0.012, "stub_rubber", segs=6, r_top=0.0028, caps=(False, True), tag="antenna_med")
        med += align(st, ax, (0, 1, 0), vec(x, P_ANT_Y, kz))
        b.add(med, lod="m")

    # ---- prints ------------------------------------------------------------------------------------------
    _pocket_deck_prints(b)
    # guard plate legends
    gp = DecalCanvas(0.024, P_TOG_D, ppm=12000)
    gp.text(0.012, 0.0027, "ARM", 0.0019, fnt="label-black", spacing=0.0003, **ink("white"))
    gp.glyph("up", 0.0052, 0.0027, 0.0015, **ink("white"))
    gp.glyph("up", 0.0188, 0.0027, 0.0015, **ink("white"))
    gp.text(0.012, P_TOG_D - 0.0026, "SAFE", 0.0016, fnt="label", spacing=0.0003, **ink("white"))
    b.decal(gp, center=(tx, ty, PZT + 0.0012), normal=(0, 0, 1), up=(0, -1, 0), mats=["guard_red"], depth=0.0006, min_dot=0.8)
    # front face: model print + caution sticker
    yf = PD / 2
    mp = model_print("JX-10", "MULTI-BAND  ·  6 CH", w=0.040, h=0.0118, color="white", rule_color="orange")
    b.decal(mp, center=(0.031, yf, zc + 0.0006), normal=(0, 1, 0), up=(0, 0, 1), mats=[alu], depth=0.002, min_dot=0.6)
    cl = caution_label(0.040, 0.0128, head="CAUTION", lines=("RF EMISSION WHEN ARMED", "Keep 20 cm from the body"), ppm=9000)
    b.decal(cl, center=(-0.027, yf, zc), normal=(0, 1, 0), up=(0, 0, 1), mats=[alu], depth=0.002, min_dot=0.6)
    # front face machined accent groove
    gr = DecalCanvas(0.114, 0.004, ppm=8000)
    gr.groove([(0.0, 0.0028), (0.114, 0.0028)], width=0.00045, depth=0.0002, alpha=0.5)
    b.decal(gr, center=(0.0, yf, PZ0 + 0.0042), normal=(0, 1, 0), up=(0, 0, 1), mats=[alu], depth=0.002, min_dot=0.6)
    # +X end plate: vent slots + port legends on the -X plate
    vs = DecalCanvas(0.017, 0.009, ppm=10000)
    vs.slots(0.0, 0.0, 0.017, 0.009, 5, vertical=True, fill=0.42, depth=0.0005)
    for yy in (0.0135, -0.0135):
        b.decal(vs, center=(PL / 2, yy, zc + 0.0008), normal=(1, 0, 0), up=(0, 0, 1), mats=["endplate_anod"], depth=0.002, min_dot=0.6)
    pl = DecalCanvas(0.060, 0.006, ppm=10000)
    for yy, word in ((0.016, "DC 12V"), (-0.004, "USB-C"), (-0.018, "CHG")):
        pl.text(0.030 - yy, 0.003, word, 0.0015, fnt="label", **ink("white"))      # canvas x runs to -Y here
    b.decal(pl, center=(-PL / 2, 0.0, zc - 0.0062), normal=(-1, 0, 0), up=(0, 0, 1), mats=["endplate_anod"], depth=0.0015, min_dot=0.6)
    # rear face: asset tag + antenna notice
    yb = -PD / 2
    at = DecalCanvas(0.030, 0.009, ppm=12000)
    at.rect(0, 0, 0.030, 0.009, r=0.0008, color=(196, 200, 204), spec=0.7, gloss=0.6, metal=1.0)
    at.text(0.0015, 0.0022, "ASSET", 0.0012, fnt="label", anchor="lm", color=(30, 32, 35))
    at.text(0.0285, 0.0022, "JX10-0417", 0.0012, fnt="mono-bold", anchor="rm", color=(30, 32, 35))
    at.barcode(0.0015, 0.0038, 0.027, 0.0045, seed=417, color=(30, 32, 35))
    b.decal(at, center=(0.032, yb, zc), normal=(0, -1, 0), up=(0, 0, 1), mats=[alu], depth=0.002, min_dot=0.6)
    nt = DecalCanvas(0.050, 0.008, ppm=10000)
    nt.text(0.025, 0.0026, "DO NOT ARM WITHOUT ANTENNAS", 0.0014, fnt="label", spacing=0.0002, **ink("white"))
    nt.text(0.025, 0.0058, "ANT 1-6  ·  SMA  ·  50 OHM", 0.0012, fnt="label-semi", spacing=0.0002, **ink("grey"))
    b.decal(nt, center=(-0.024, yb, zc), normal=(0, -1, 0), up=(0, 0, 1), mats=[alu], depth=0.002, min_dot=0.6)
    # bottom: rating plate
    rp = rating_plate(0.062, 0.026, "MULTI-BAND JAMMER", "JX-10", "SN 26-10384", ref="EQ-JX10-06",
                      rating="7.4 V  5200 mAh  Li-ion  ·  12 V DC", ppm=7000, icons=("factory", "date", "book", "bin"), foot="IP54")
    b.decal(rp, center=(0.0, 0.0, PZ0), normal=(0, 0, -1), up=(0, 1, 0), mats=[alu], depth=0.002, min_dot=0.6)

    # ---- anchors, collision, review cameras --------------------------------------------------------------------
    b.anchor(jammer="pocket", interact=(0.0, 0.0, 0.045))
    b.col_box((-PL / 2, -PD / 2, 0.0), (PL / 2, PD / 2, PZF), "METAL_SOLID_SMALL")
    b.col_box((-0.072, -0.036, PZT), (0.072, -0.016, 0.105), "PLASTIC_HIGH_DENSITY")
    b.closeup("deck", (0.006, 0.020, 0.024), direction=(0.05, 0.75, 1.0), extent=0.085)
    b.closeup("toggle", (-0.022, 0.020, 0.030), direction=(0.35, 1.0, 0.65), extent=0.045)
    b.closeup("antennas", (0.0, -0.025, 0.055), direction=(0.25, -1.0, 0.45), extent=0.15)
    b.closeup("endx", (-PL / 2, 0.0, 0.014), direction=(-1.0, 0.35, 0.3), extent=0.08)


# =============================================================================================
# JX-40 field case  460 x 360 x 180 mm closed, lid open 100 deg
# =============================================================================================
CW, CD = 0.460, 0.360          # footprint (X, Y)
CR = 0.032                     # plan corner radius
C_FOOT = 0.006
C_ZS = 0.122                   # base / lid seam
C_LID = 0.058                  # lid height (closed)
C_WALL = 0.010
C_DECK = 0.098                 # electronics deck top surface
C_ANG = 100.0                  # lid opening angle
C_HINGE = vec(0.0, -CD / 2 - 0.009, C_ZS)
C_LATCH_X = (0.135, -0.135)
C_RAIL_X = 0.193               # antenna rails (|x|)
C_PORT_Y = (-0.105, -0.035, 0.035, 0.105)
C_ANT_LEN = (0.300, 0.240, 0.215, 0.270)
C_ANT_COLS = ((226, 52, 48), (238, 120, 32), (236, 196, 40), (70, 190, 90), (40, 120, 220), (150, 70, 200),
              (230, 232, 234), (120, 124, 130))
C_FAN_X = 0.112
C_FAN_Y = -0.112
C_DISP = (0.085, 0.072)        # display centre (x, y) on the deck
C_ROCK_Y = 0.136
C_ROCK_X = (0.140, 0.110, 0.080, 0.050)
C_BATT = (-0.106, 0.048)       # battery centre (x, y)
C_BATT_SIZE = (0.088, 0.168, 0.056)
C_STRAP_Y = (-0.064, 0.064)    # battery strap offsets from the battery centre (clear of the label)
C_SLOT_Y = -0.036              # brush-grommet slot in front of the amplifier (harness goes under the deck)
C_GROM_X = 0.161               # |x| of the pigtail grommets beside the rails


def _lid_rot():
    return axis_angle((1, 0, 0), C_ANG)


def _lid_xf(p):
    """A closed-lid point -> its place with the lid open."""
    return tuple(_lid_rot() @ (vec(p) - C_HINGE) + C_HINGE)


def _lid_dir(v):
    return tuple(_lid_rot() @ vec(v))


def _outline_path(w, d, r, z, n=6):
    lp = rrect(w, d, r, n)
    return np.stack([lp[:, 0], lp[:, 1], np.full(len(lp), z)], axis=1)


def _case_latch(b, x, y_face, hard_dark, steel):
    """Over-centre draw latch hanging open on the base front (+Y face): base bracket with pivot pins,
    latch body swung down and out, finger lip, wire-hook tip."""
    g = Geo()
    piv = vec(x, y_face + 0.0085, C_ZS - 0.034)
    g += box((0.058, 0.010, 0.020), hard_dark, r=0.004, seg=1, center=(x, y_face + 0.004, C_ZS - 0.036))
    body = Geo()
    prof = _round([(-0.026, -0.006), (0.026, -0.006), (0.024, 0.060), (0.018, 0.068), (-0.018, 0.068), (-0.024, 0.060)],
                  [0.004, 0.004, 0.006, 0.004, 0.004, 0.006], n=3)
    lb = extrude(prof, 0.010, hard_dark, bevel=0.0028, bevel_seg=2, smooth_angle=50, tag="latch")
    lb.transform(np.array([[1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]]) @ np.diag([1.0, 1.0, 1.0]))   # profile y -> +Z, depth -> +Y
    body += lb.translate(x, piv[1] - 0.004, piv[2])
    # finger lip at the far end + wire hook
    body += box((0.050, 0.010, 0.008), hard_dark, r=0.0035, seg=1, center=(x, piv[1] + 0.008, piv[2] + 0.063))
    hook = polyline_fillet([(x - 0.017, piv[1] + 0.001, piv[2] + 0.046), (x - 0.017, piv[1] - 0.004, piv[2] + 0.080),
                            (x + 0.017, piv[1] - 0.004, piv[2] + 0.080), (x + 0.017, piv[1] + 0.001, piv[2] + 0.046)], 0.006, 5)
    body += tube(hook, 0.0016, steel, segs=6, tag="latch_hook").set_lod("h")
    body.rotate_axis((1, 0, 0), -152.0, origin=piv)
    g += body
    g += cylinder(0.0024, 0.064, steel, segs=10, bevel=0.0006, bevel_seg=1, z0=-0.032, tag="latch_pin").rotate(0, 90, 0).translate(piv).set_lod("h")
    return g


def _case_handle(b, y_face, hard_dark, grip):
    g = Geo()
    zp = C_ZS - 0.024
    for sx in (-1, 1):
        g += box((0.026, 0.020, 0.026), hard_dark, r=0.007, seg=1, center=(sx * 0.072, y_face + 0.007, zp))
    drop = 0.036
    path = polyline_fillet([(-0.072, y_face + 0.014, zp), (-0.072, y_face + 0.026, zp - drop), (0.072, y_face + 0.026, zp - drop),
                            (0.072, y_face + 0.014, zp)], 0.014, 6)
    g += sweep(rrect(0.020, 0.016, 0.006, 3), path, hard_dark, side=(0, 1, 0), tag="handle", smooth_angle=55)
    g += sweep(rrect(0.024, 0.020, 0.008, 3), np.array([(-0.050, y_face + 0.026, zp - drop), (0.050, y_face + 0.026, zp - drop)]), grip,
               side=(0, 1, 0), tag="handle_grip", smooth_angle=55)
    return g


def _purge_valve(b, at, normal=(0, 1, 0)):
    blk = b.mat("valve_black", color=(26, 27, 29), spec=0.3, gloss=0.42, edge=0.5, dirt=0.2)
    knurl = b.mat("valve_knurl", color=(30, 31, 34), spec=0.3, gloss=0.4, bump="ribs_u", bump_amp=0.0001, bump_scale=0.0014, edge=0.45)
    g = lathe([(0.0, 0.0), (0.0130, 0.0), (0.0130, 0.0055), (0.0108, 0.0084), (0.0, 0.0086)], knurl, segs=28, smooth_angle=50, tag="valve")
    g += cylinder(0.0058, 0.0016, blk, segs=16, bevel=0.0005, bevel_seg=1, z0=0.0084, tag="valve_cap")
    return align(g, normal, (0, 0, 1), at)


def _fan(b, at, frame_mat, blade_mat, steel_dark):
    """80 mm fan in a square frame sunk into the deck: hub + 7 pitched blades under a wire guard."""
    x, y, z = at
    g, flo = _ring_window(b, (x, y, z), (0, 0, 1), (0, -1, 0), (0.082, 0.082), 0.005, (0.074, 0.074), 0.037, 0.009, 0.0085,
                          frame_mat, b.mat("fan_well", color=(12, 13, 14), spec=0.1, gloss=0.2, ao=1.0), n=6, bevel_seg=1)
    b.add(g)
    fan = Geo()
    fan += cylinder(0.0135, 0.0048, blade_mat, segs=20, bevel=0.0008, bevel_seg=1, z0=0.0005, tag="fan_hub")
    for i in range(7):
        bl = box((0.021, 0.0125, 0.0012), blade_mat, center=(0.0245, 0.0, 0.0030), tag="fan_blade")
        bl.rotate_axis((1, 0, 0), 28.0, origin=(0.0245, 0.0, 0.0030))
        fan += bl.rotate(0, 0, 360.0 * i / 7 + 9.0)
    b.hi_only(fan.translate(x, y, flo[2]))
    guard = Geo()
    zt = z + 0.0095
    for R in (0.0355, 0.0265, 0.0175):
        guard += torus(R, 0.0007, steel_dark, segs=16, tube_segs=3).translate(0, 0, zt)
    for i in range(4):
        sp = cylinder(0.0006, 0.036, steel_dark, segs=4, caps=(False, False)).rotate(0, 90, 0)
        guard += sp.rotate(0, 0, 45 + 90 * i).translate(0, 0, zt)
    guard += cylinder(0.0085, 0.0014, steel_dark, segs=12, bevel=0.0004, bevel_seg=1, z0=zt - 0.0007)
    b.hi_only(guard.translate(x, y, 0))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.hi_only(screw(b, (x + sx * 0.0355, y + sy * 0.0355, z + 0.009), (0, 0, 1), (0, -1, 0), d=0.0042, kind="phillips",
                            color=(60, 62, 66), segs=6))


def _rocker(b, at, mat, bezel_mat):
    x, y, z = at
    g, flo = _ring_window(b, (x, y, z), (0, 0, 1), (0, -1, 0), (0.0160, 0.0230), 0.0018, (0.0118, 0.0190), 0.0012, 0.0036, 0.0032,
                          bezel_mat, b.mat("rocker_well", color=(10, 10, 11), spec=0.1, gloss=0.2, ao=1.0), n=3, bevel_seg=1)
    b.add(g)
    rk = box((0.0108, 0.0182, 0.0042), mat, r=0.0011, seg=1, center=(0, 0, 0.0021), tag="rocker")
    rk.rotate(-11.0, 0, 0)       # pressed toward the front: the 'I' half (the -Y half) proud
    b.hi_only(rk.translate(x, y, flo[2] + 0.0006))


def _jx40_screen():
    def paint(d, S, col, ghost):
        W = 512
        f_big = font("lcd", 44 * S)
        f_mid = font("lcd", 30 * S)
        f_sm = font("lcd", 22 * S)
        d.text((14 * S, 22 * S), "JX-40", font=f_big, fill=col, anchor="lm")
        d.rectangle([150 * S, 8 * S, 210 * S, 36 * S], fill=col)
        d.text((180 * S, 22 * S), "TX", font=f_mid, fill=(10, 6, 2), anchor="mm")
        d.text((228 * S, 22 * S), "8/8", font=f_mid, fill=col, anchor="lm")
        d.text((W * S - 66 * S, 22 * S), "78%", font=f_mid, fill=col, anchor="rm")
        bx, by = W * S - 58 * S, 10 * S
        d.rectangle([bx, by, bx + 40 * S, by + 24 * S], outline=col, width=3 * S)
        d.rectangle([bx + 40 * S, by + 7 * S, bx + 45 * S, by + 17 * S], fill=col)
        d.rectangle([bx + 5 * S, by + 5 * S, bx + 29 * S, by + 19 * S], fill=col)
        d.line([10 * S, 44 * S, (W - 10) * S, 44 * S], fill=ghost, width=2 * S)
        levels = (0.92, 0.78, 0.85, 0.66, 0.95, 0.72, 0.58, 0.81)
        for i, lv in enumerate(levels):
            x0 = (18 + i * 61) * S
            seg = 9
            for k in range(seg):
                yy = (150 - k * 11) * S
                on = k < round(lv * seg)
                d.rectangle([x0, yy - 8 * S, x0 + 40 * S, yy], fill=col if on else ghost)
            d.text((x0 + 20 * S, 172 * S), f"B{i + 1}", font=f_sm, fill=col, anchor="mm")
        d.text(((W - 10) * S, 186 * S), "", font=f_sm, fill=col, anchor="rm")
    return _status_image(paint, (512, 192), color=(255, 168, 52), ghost=(40, 24, 8), bg=(8, 6, 3))


def _rot_decal(b, canvas, center, normal, up, **kw):
    b.decal(canvas, center=_lid_xf(center), normal=_lid_dir(normal), up=_lid_dir(up), **kw)


@prop("nzr_jammer_case", atlas=2048, alpha_atlas=256, glow_atlas=64, lod=150.0, lod_high=20.0, hd=15.0, med_drop=0.006,
      budget=30000, falloff=80.0, layers={"deck": 2048}, maps={"main": {"n": 1024, "s": 512}, "deck": {"n": 512, "s": 512}},
      doc={"title": "JX-40 field jammer case (rugged hard case 46 x 36 x 18 cm, lid open ~100 deg)",
           "origin": "bottom centre (stands on four rubber feet)",
           "axes": "+Y = front (latches, handle, valve), lid hinged at -Y and open ~100 deg, +Z up; 8 folding antennas on "
                   "the side rails of the electronics deck",
           "attach": "placed on the ground (client/modules/jammers.lua): frozen, non-networked; ghost while placing"},
      preview={"views": ["front", "iso", "front34", "top", "back", "left", "face", "back34"]})
def jammer_case(b):
    hard = b.mat("hardcase_olive", color=(66, 72, 54), spec=0.22, gloss=0.32, bump="stipple", bump_amp=0.00009, bump_scale=0.0014,
                 grain=0.05, grain_scale=0.09, edge=0.6, dirt=0.32, wear_color=(118, 124, 104), scratch=0.3, cavity=0.6)
    hard_dark = b.mat("hardcase_black", color=(30, 31, 30), spec=0.25, gloss=0.36, bump="stipple", bump_amp=0.00006,
                      bump_scale=0.0010, grain=0.04, grain_scale=0.06, edge=0.6, dirt=0.25, wear_color=(84, 86, 84))
    grip = b.mat("handle_grip", color=(24, 25, 27), spec=0.1, gloss=0.16, bump="ribs", bump_amp=0.0003, bump_scale=0.003, edge=0.25,
                 dirt=0.2)
    steel = b.mat("case_steel", color=(150, 154, 158), spec=0.8, gloss=0.62, metal=1.0, bump="brushed", bump_amp=0.00001,
                  bump_scale=0.0004, grain=0.03, edge=0.3, dirt=0.25, scratch=0.4)
    rub = m_rubber(b)
    gasket = b.mat("gasket", color=(18, 19, 20), spec=0.18, gloss=0.3, edge=0.1)
    crate = b.mat("crate_foam", color=(32, 33, 35), spec=0.03, gloss=0.05, bump="eggcrate", bump_amp=0.007, bump_scale=0.040,
                  grain=0.05, grain_scale=0.05, ao=1.0, dirt=0.1)
    # the electronics deck, its rails, the battery top and the quick-start card carry the small prints: own 2048 atlas
    deck = b.mat("deck_anod", color=(28, 29, 32), spec=0.42, gloss=0.42, metal=0.7, bump="brushed", bump_amp=0.000006,
                 bump_scale=0.0006, grain=0.025, grain_scale=0.05, edge=0.7, wear_color=(150, 154, 160), dirt=0.2, scratch=0.3,
                 layer="deck")
    alu = m_anodised_black(b)
    rail = b.mat_from("rail_anod", dc_replace(b.mats[alu], layer="deck"))
    nickel = m_sma(b, "nickel")
    coax = b.mat("coax_jacket", color=(20, 21, 23), spec=0.32, gloss=0.5, grain=0.02, edge=0.15, dirt=0.15)
    plastic = b.mat("module_plastic", color=(34, 35, 38), spec=0.3, gloss=0.42, bump="stipple", bump_amp=0.00004, bump_scale=0.0008,
                    edge=0.5, dirt=0.15, wear_color=(80, 82, 86))
    W2, D2 = CW / 2, CD / 2
    outline = rrect(CW, CD, CR, 6)
    inner = rrect(CW - 2 * C_WALL, CD - 2 * C_WALL, CR - C_WALL, 6)

    # ---- base shell -----------------------------------------------------------------------------------------
    base = Geo()
    base += extrude(outline, C_ZS - C_FOOT, hard, bevel=0.018, bevel_seg=3, z0=C_FOOT, caps=(True, False), smooth_angle=50,
                    tag="base")
    cav = extrude(inner, C_ZS - C_DECK + 0.004, hard, z0=C_DECK - 0.004, caps=(False, False), smooth_angle=50, tag="cavity")
    base += cav.flip()
    base += sweep(rrect(C_WALL + 0.001, 0.008, 0.0035, 1) + vec(0, -0.004), _outline_path(CW - C_WALL, CD - C_WALL, CR - C_WALL / 2, C_ZS),
                  hard, closed_path=True, up=(0, 0, 1), tag="rim", smooth_angle=50)
    # bumper band under the seam + lower stacking band
    base += sweep(rrect(0.006, 0.016, 0.0028, 1), _outline_path(CW + 0.004, CD + 0.004, CR + 0.002, C_ZS - 0.010), hard,
                  closed_path=True, up=(0, 0, 1), tag="band", smooth_angle=50)
    # vertical ribs on the ends
    for sx in (-1, 1):
        for yy in (-0.105, 0.105):
            base += box((0.010, 0.020, 0.080), hard, r=0.0045, seg=1, center=(sx * (W2 + 0.002), yy, 0.062), faces="+x +y -y +z -z")
    for c in base.charts:
        if c.tag.startswith("cavity"):
            c.density = 0.45
    b.add(base)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(rubber_foot(b, sx * 0.180, sy * 0.130, 0.0, r=0.018, h=C_FOOT + 0.002, segs=12))
    # front: latches (open), handle, purge valve, padlock eyes
    yf = D2 + 0.002
    for x in C_LATCH_X:
        b.add(_case_latch(b, x, yf, hard_dark, steel))
        for sx in (-1, 1):
            pass
    b.add(_case_handle(b, yf, hard_dark, grip))
    b.hi_only(_purge_valve(b, (-0.192, D2, 0.070)))
    for x in (0.195, -0.195):
        b.add(box((0.016, 0.012, 0.024), hard, r=0.004, seg=1, center=(x, yf + 0.003, C_ZS - 0.016)))
        b.hi_only(torus(0.0040, 0.0012, steel, segs=14, tube_segs=5).rotate(90, 0, 0).translate(x, yf + 0.0095, C_ZS - 0.016))
    # back: hinges (base leaves + barrels)
    yb = -D2
    for x in (-0.150, 0.0, 0.150):
        b.add(box((0.080, 0.004, 0.024), hard_dark, r=0.0015, seg=1, center=(x, yb - 0.002, C_ZS - 0.014)))
        from .common import hinge
        b.add(hinge(b, (x - 0.040, C_HINGE[1], C_ZS), (x + 0.040, C_HINGE[1], C_ZS), r=0.0075, knuckles=3, mat=hard_dark, segs=8), lod="h")
        b.add(cylinder(0.0076, 0.080, hard_dark, segs=6, z0=-0.040, caps=(False, False)).rotate(0, 90, 0).translate(x, C_HINGE[1], C_ZS), lod="m")

    # ---- lid, built closed, then swung open about the hinge axis ---------------------------------------------------
    lid = Geo()
    lid += extrude(outline, C_LID, hard, bevel=0.018, bevel_seg=3, z0=C_ZS, caps=(False, True), smooth_angle=50, tag="lid")
    lin = extrude(inner, C_LID - C_WALL, hard, z0=C_ZS, caps=(False, True), smooth_angle=50, tag="lidin")
    for c in lin.charts:
        c.density = 0.45
    lid += lin.flip()
    lid += sweep(rrect(C_WALL + 0.001, 0.008, 0.0035, 1) + vec(0, 0.004), _outline_path(CW - C_WALL, CD - C_WALL, CR - C_WALL / 2, C_ZS),
                 hard, closed_path=True, up=(0, 0, 1), tag="lidrim", smooth_angle=50)
    lid += sweep(rrect(0.0045, 0.003, 0.0012, 1), _outline_path(CW - C_WALL, CD - C_WALL, CR - C_WALL / 2, C_ZS - 0.0012), gasket,
                 closed_path=True, up=(0, 0, 1), tag="gasket", smooth_angle=50).set_lod("h")
    lid += sweep(rrect(0.006, 0.014, 0.0028, 1), _outline_path(CW + 0.004, CD + 0.004, CR + 0.002, C_ZS + 0.009), hard,
                 closed_path=True, up=(0, 0, 1), tag="lidband", smooth_angle=50)
    top = C_ZS + C_LID
    for yy in (-0.120, 0.120):
        lid += box((0.380, 0.022, 0.012), hard, r=0.005, seg=1, center=(0, yy, top - 0.003), faces="+x -x +y -y +z")
    lid += box((CW - 2 * C_WALL - 0.004, CD - 2 * C_WALL - 0.004, 0.034), crate, r=0.006, seg=1,
               center=(0, 0, top - C_WALL - 0.017), faces="-z +x -x +y -y", face_density={"-z": 1.0})
    card = b.mat("quick_card", color=(232, 234, 230), spec=0.5, gloss=0.62, edge=0.2, dirt=0.15, layer="deck")
    lid += box((0.190, 0.120, 0.0016), card, r=0.002, seg=1, center=(0.07, 0.01, top - C_WALL - 0.0348), faces="-z +x -x +y -y")
    # clear vinyl sleeve over the card, riveted to the foam backer at the corners
    sleeve = b.mat("card_sleeve", color=(226, 232, 236), spec=0.9, gloss=0.86, alpha=0.14, layer="alpha", grain=0.0, edge=0.05,
                   smudge=0.35, scratch=0.15)
    lid += box((0.202, 0.132, 0.0005), sleeve, r=0.004, seg=1, center=(0.07, 0.01, top - C_WALL - 0.0362), faces="-z",
               tag="sleeve").set_lod("h")
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            lid += cylinder(0.0030, 0.0010, steel, segs=8, bevel=0.0004, bevel_seg=1, z0=-0.0010, caps=(True, False),
                            tag="rivet").translate(0.07 + sx_ * 0.0955, 0.01 + sy_ * 0.0615, top - C_WALL - 0.0364).set_lod("h")
    for x in C_LATCH_X:
        lid += box((0.048, 0.012, 0.016), hard_dark, r=0.004, seg=1, center=(x, D2 + 0.005, C_ZS + 0.026))
        lid += cylinder(0.0022, 0.040, steel, segs=8, z0=-0.020).rotate(0, 90, 0).translate(x, D2 + 0.012, C_ZS + 0.022)
    for x in (0.195, -0.195):
        lid += box((0.016, 0.012, 0.024), hard, r=0.004, seg=1, center=(x, D2 + 0.005, C_ZS + 0.016))
    for x in (-0.150, 0.0, 0.150):
        lid += box((0.080, 0.004, 0.024), hard_dark, r=0.0015, seg=1, center=(x, yb - 0.002, C_ZS + 0.014))
    lid.rotate_axis((1, 0, 0), C_ANG, origin=C_HINGE)
    b.add(lid)

    # ---- electronics deck -------------------------------------------------------------------------------------
    dw, dd = CW - 2 * C_WALL - 0.006, CD - 2 * C_WALL - 0.006
    b.add(extrude(rrect(dw, dd, CR - C_WALL - 0.003, 6), 0.004, deck, bevel=0.0012, bevel_seg=2, z0=C_DECK - 0.004, smooth_angle=50,
                  tag="deck", caps=(False, True)))
    for sx in (-1, 1):
        for yy in (-0.150, 0.0, 0.150):
            b.hi_only(screw(b, (sx * (dw / 2 - 0.008), yy, C_DECK), (0, 0, 1), (0, -1, 0), d=0.006, kind="hex",
                            color=(70, 72, 76), segs=8))
    # antenna rails
    for sx in (-1, 1):
        b.add(box((0.016, 0.290, 0.024), rail, r=0.0025, seg=2, center=(sx * C_RAIL_X, 0.0, C_DECK + 0.012), tag="rail"))
        for yy in (-0.140, 0.140):
            b.hi_only(screw(b, (sx * C_RAIL_X, yy, C_DECK + 0.024), (0, 0, 1), (0, -1, 0), d=0.005, kind="hex", color=(70, 72, 76), segs=8))
    # RF amplifier block with heatsink fins (centre rear)
    amp_y0, amp_y1 = -0.160, -0.066
    b.add(box((0.124, amp_y1 - amp_y0, 0.012), alu, r=0.002, seg=2, center=(0.0, (amp_y0 + amp_y1) / 2, C_DECK + 0.006), tag="amp"))
    fins = []
    rad = []
    for i in range(11):
        xf = -0.055 + i * 0.011
        fins += [(xf - 0.0011, C_DECK + 0.012), (xf - 0.0011, C_DECK + 0.036), (xf + 0.0011, C_DECK + 0.036), (xf + 0.0011, C_DECK + 0.012)]
        rad += [0.0005, 0.0006, 0.0006, 0.0005]
    comb = [(0.062, C_DECK + 0.0118)] + fins[::-1] + [(-0.062, C_DECK + 0.0118), (-0.062, C_DECK + 0.010), (0.062, C_DECK + 0.010)]
    # comb profile in (x, z) extruded along Y: built as (y', z) with y' = -x so the YZX helper can be reused
    comb = [(-p[0], p[1]) for p in comb]
    rad = [0.0] + rad[::-1] + [0.0, 0.0, 0.0]
    cp = _round(comb[::-1], rad[::-1], n=3) if False else _round(comb, rad, n=3)
    finb = extrude(_support(cp), amp_y1 - amp_y0 - 0.004, alu, z0=amp_y0 + 0.002, caps=(False, False), smooth_angle=38, tag="ampfins")
    finb += poly_cap(cp, amp_y0 + 0.002, alu, up=False, tag="ampfins:c0")
    finb += poly_cap(cp, amp_y1 - 0.002, alu, up=True, tag="ampfins:c1")
    finb.transform(np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]]))
    b.add(finb)
    # fans
    for sx in (-1, 1):
        _fan(b, (sx * C_FAN_X, C_FAN_Y, C_DECK), plastic, b.mat("fan_blade", color=(38, 39, 42), spec=0.3, gloss=0.4, edge=0.4),
             b.mat("guard_wire", color=(46, 47, 50), spec=0.7, gloss=0.55, metal=1.0, edge=0.4, wear_color=(150, 152, 156)))
    # display module
    dx, dy = C_DISP
    g, flo = _ring_window(b, (dx, dy, C_DECK), (0, 0, 1), (0, -1, 0), (0.150, 0.072), 0.005, (0.1225, 0.0465), 0.0025, 0.0060,
                          0.0035, plastic, m_print_dark(b))
    b.add(g)
    right, upv, nn = _frame((0, 0, 1), (0, -1, 0))
    b.screen(quad(flo + nn * 0.00005, right, upv, 0.1200, 0.0450, "x", fixed_uv=True), texname="nzr_jx40_scr", image=_jx40_screen(),
             mult=1.15, size=(512, 192))
    b.add(quad(flo + nn * 0.0012, right, upv, 0.1222, 0.0462, m_smoked_glass(b, 0.18), tag="glass"))
    # rocker switches
    for i, x in enumerate(C_ROCK_X):
        rm = b.mat("rocker_red", color=(176, 30, 28), spec=0.45, gloss=0.55, edge=0.4) if i == 0 else \
            b.mat("rocker_black", color=(24, 25, 27), spec=0.35, gloss=0.5, edge=0.45, wear_color=(80, 82, 86))
        _rocker(b, (x, C_ROCK_Y, C_DECK), rm, plastic)
    # main input connector + fuse holder (between the display and the battery)
    # square-flange panel receptacle under the DC plug
    b.add(box((0.032, 0.032, 0.0024), alu, r=0.0035, seg=1, center=(-0.030, 0.128, C_DECK + 0.0012), faces="+x -x +y -y +z",
              tag="dc_flange"))
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            b.hi_only(screw(b, (-0.030 + sx_ * 0.0115, 0.128 + sy_ * 0.0115, C_DECK + 0.0024), (0, 0, 1), (0, -1, 0), d=0.0036,
                            kind="phillips", color=(70, 72, 76), segs=6))
    fuse = cylinder(0.0075, 0.016, plastic, segs=16, bevel=0.0012, bevel_seg=2, z0=0.0).translate(-0.030, 0.088, C_DECK)
    fuse += cylinder(0.0055, 0.008, b.mat("fuse_cap", color=(176, 30, 28), spec=0.4, gloss=0.5, bump="ribs_u", bump_amp=0.00008,
                                                  bump_scale=0.0012, edge=0.4), segs=16, bevel=0.001, z0=0.016).translate(-0.030, 0.088, C_DECK)
    b.hi_only(fuse)
    b.hi_only(led_lens(b, (-0.030, 0.060, C_DECK), (0, 0, 1), (0, -1, 0), r=0.0030, color=(60, 255, 120), name="led_green"))
    b.hi_only(led_lens(b, (-0.030, 0.045, C_DECK), (0, 0, 1), (0, -1, 0), r=0.0030, color=(255, 46, 40), name="led_red"))

    # battery pack + straps + power lead
    bx, by = C_BATT
    bw, bd, bh = C_BATT_SIZE
    batt = b.mat("battery_case", color=(36, 38, 34), spec=0.28, gloss=0.38, bump="stipple", bump_amp=0.00005, bump_scale=0.0011,
                 grain=0.04, grain_scale=0.06, edge=0.55, dirt=0.25, wear_color=(90, 92, 86), layer="deck")
    b.add(box((bw, bd, bh), batt, r=0.006, seg=2, center=(bx, by, C_DECK + bh / 2), tag="battery"))
    # moulded lid seam + grip recesses on the ends
    b.add(box((bw + 0.003, bd + 0.003, 0.006), batt, r=0.003, seg=1, center=(bx, by, C_DECK + bh - 0.012), tag="batt_rim"))
    web = b.mat("strap_web", color=(26, 27, 28), spec=0.14, gloss=0.22, bump="webbing", bump_amp=0.00022, bump_scale=0.0016,
                grain=0.05, edge=0.15, dirt=0.15)
    buckle = b.mat("buckle", color=(20, 21, 22), spec=0.35, gloss=0.45, edge=0.5)
    xo, xi = bx - bw / 2 - 0.0015, bx + bw / 2 + 0.0015     # -X (outer) / +X (inner, buckle) faces
    zt = C_DECK + bh + 0.0015 + 0.0016
    for dy in C_STRAP_Y:
        yy = by + dy
        path = polyline_fillet([(xo - 0.0025, yy, C_DECK + 0.0008), (xo - 0.0015, yy, C_DECK + 0.004), (xo - 0.0015, yy, zt),
                                (xi + 0.0015, yy, zt), (xi + 0.0015, yy, C_DECK + 0.004), (xi + 0.0060, yy, C_DECK + 0.0008)], 0.005, 4)
        b.hi_only(sweep(rrect(0.024, 0.0016, 0.0006, 1), path, web, side=(0, 1, 0), tag="strap", smooth_angle=50))
        # cam buckle on the inner side face
        b.hi_only(box((0.006, 0.030, 0.026), buckle, r=0.0018, seg=1, center=(xi + 0.0045, yy, C_DECK + bh * 0.55), tag="buckle"))
        b.hi_only(box((0.004, 0.026, 0.008), buckle, r=0.0014, seg=1, center=(xi + 0.0080, yy, C_DECK + bh * 0.55 + 0.009), tag="buckle"))
    # power lead: battery front connector -> loop -> panel input (red + black pair)
    conn = b.mat("anderson_grey", color=(120, 124, 126), spec=0.3, gloss=0.42, edge=0.4, dirt=0.2)
    cy0 = by + bd / 2
    b.add(box((0.018, 0.022, 0.016), conn, r=0.002, seg=1, center=(bx + 0.010, cy0 + 0.010, C_DECK + bh - 0.014)))
    red_j = b.mat("lead_red", color=(150, 28, 26), spec=0.3, gloss=0.45, edge=0.2)
    blk_j = b.mat("lead_black", color=(22, 23, 24), spec=0.3, gloss=0.45, edge=0.2)
    for off, m in ((-0.0035, red_j), (0.0035, blk_j)):
        pts = catmull([(bx + 0.010 + off, cy0 + 0.021, C_DECK + bh - 0.014), (bx + 0.012 + off, cy0 + 0.030, C_DECK + 0.030),
                       (bx + 0.036 + off, cy0 + 0.027, C_DECK + 0.008), (-0.047 + off * 0.6, 0.149, C_DECK + 0.012),
                       (-0.033 + off * 0.6, 0.135, C_DECK + 0.040), (-0.030 + off * 0.5, 0.128, C_DECK + 0.031)], n=4)
        b.hi_only(tube(pts, 0.0034, m, segs=7, split=0.2, tag="lead"))
    # DC plug seated on the panel input: knurled coupling ring, body, boot the pair enters
    dcp = lathe([(0.0, 0.004), (0.0124, 0.004), (0.0126, 0.0055), (0.0126, 0.0135), (0.0112, 0.0150)],
                b.mat("dc_coupling", color=(34, 35, 37), spec=0.45, gloss=0.5, metal=0.6, bump="ribs_u", bump_amp=0.0001,
                      bump_scale=0.0012, edge=0.6, wear_color=(150, 152, 156)), segs=20, smooth_angle=50, tag="dc_plug")
    dcp += lathe([(0.0112, 0.0150), (0.0100, 0.0158), (0.0098, 0.0225), (0.0080, 0.0250), (0.0072, 0.0310), (0.0060, 0.0322),
                  (0.0, 0.0324)], blk_j, segs=16, smooth_angle=45, tag="dc_boot")
    b.hi_only(dcp.translate(-0.030, 0.128, C_DECK))
    # RF harness (runs under the deck plate): 8 SMA outputs on the amplifier's front face with short coax loops
    # into a brush-grommet slot, and at every antenna port a pigtail rising out of a deck grommet into a
    # right-angle plug on the rail's inner face. Nothing crosses the fans or the battery.
    plug = b.mat("sma_plug", color=(176, 178, 182), spec=0.85, gloss=0.7, metal=1.0, edge=0.3)
    thr_n = b.mat("sma_thread_nickel", color=(176, 178, 182), spec=0.8, gloss=0.6, metal=1.0, bump="ribs", bump_amp=0.00008,
                  bump_scale=0.0005, edge=0.3)
    plug_k = b.mat("sma_plug_knurl", color=(168, 170, 174), spec=0.8, gloss=0.62, metal=1.0, bump="ribs_u", bump_amp=0.00006,
                   bump_scale=0.0005, edge=0.3)
    grom = b.mat("grommet_rubber", color=(15, 16, 17), spec=0.12, gloss=0.22, bump="rubber", bump_amp=0.00003, bump_scale=0.0006,
                 edge=0.2, dirt=0.15)
    zc_amp = C_DECK + 0.006
    slot_y = C_SLOT_Y
    b.add(extrude(rrect(0.136, 0.012, 0.0045, 3), 0.0018, grom, bevel=0.0007, bevel_seg=1, z0=C_DECK, caps=(False, True), smooth_angle=50,
                  tag="slot").translate(0.0, slot_y, 0.0))
    for i in range(8):
        xj = -0.0525 + i * 0.015
        jk = lathe([(0.0, 0.0), (0.0040, 0.0), (0.0040, 0.0010)], plug, segs=8, smooth_angle=20, tag="pa_jack")
        jk += cylinder(0.0034, 0.0052, plug_k, segs=8, bevel=0.0003, bevel_seg=1, z0=0.0010, caps=(False, True), tag="pa_plug")
        jk += lathe([(0.0030, 0.0062), (0.0026, 0.0090), (0.0023, 0.0140), (0.0, 0.0141)], coax, segs=8, smooth_angle=50, tag="pa_boot")
        b.hi_only(align(jk, (0, 1, 0), (0, 0, 1), (xj, amp_y1, zc_amp)))
        lean = (i - 3.5) * 0.0012
        pts = catmull([(xj, amp_y1 + 0.0145, zc_amp), (xj + lean * 0.4, amp_y1 + 0.022, zc_amp + 0.0008),
                       (xj + lean, slot_y - 0.0035, C_DECK + 0.0045), (xj + lean, slot_y, C_DECK + 0.0005), (xj + lean, slot_y, C_DECK - 0.004)], n=3)
        b.hi_only(tube(pts, 0.0021, coax, segs=6, split=0.2, tag="coax"))
    for sx in (-1, 1):
        for i, py in enumerate(C_PORT_Y):
            xr = sx * (C_RAIL_X - 0.008)
            pl = cylinder(0.0036, 0.008, plug_k, segs=8, bevel=0.0005, bevel_seg=1).rotate(0, 90 * sx, 0)
            b.hi_only(pl.translate(xr - sx * 0.008, py, C_DECK + 0.014))
            b.hi_only(extrude(_hex(0.0080), 0.004, plug, bevel=0.0003, bevel_seg=1, smooth_angle=20).rotate(0, 90 * sx, 0).translate(
                xr - sx * 0.002, py, C_DECK + 0.014))
            # right-angle body + boot, pigtail down into a deck grommet
            xg = sx * C_GROM_X
            ra = lathe([(0.0034, 0.0), (0.0034, 0.0035), (0.0028, 0.0048), (0.0024, 0.0065), (0.0, 0.0066)], coax, segs=8,
                       smooth_angle=50, tag="ra_boot")
            b.hi_only(align(ra, (-sx, 0, 0), (0, 0, 1), (xr - sx * 0.008, py, C_DECK + 0.014)))
            x0 = xr - sx * 0.0145
            pts = catmull([(x0, py, C_DECK + 0.014), (x0 - sx * 0.004, py, C_DECK + 0.0132), (xg + sx * 0.0022, py, C_DECK + 0.0085),
                           (xg, py, C_DECK + 0.003), (xg, py, C_DECK - 0.003)], n=3)
            b.hi_only(tube(pts, 0.0021, coax, segs=6, split=0.2, tag="coax"))
            b.hi_only(lathe([(0.0046, 0.0), (0.0046, 0.0010), (0.0040, 0.0017), (0.0021, 0.0017)], grom, segs=8,
                            smooth_angle=50, tag="grommet").translate(xg, py, C_DECK))
    # ---- folding antennas on the rails ------------------------------------------------------------------------
    knk = b.mat("knuckle_black", color=(30, 31, 33), spec=0.4, gloss=0.5, edge=0.5, dirt=0.1, wear_color=(90, 92, 96))
    fer = b.mat("ferrule_knurl", color=(32, 33, 36), spec=0.55, gloss=0.5, metal=0.8, bump="ribs_u", bump_amp=0.0001,
                bump_scale=0.0007, edge=0.6, wear_color=(150, 152, 156), dirt=0.1)
    thr = b.mat("sma_thread_nickel", color=(176, 178, 182), spec=0.8, gloss=0.6, metal=1.0, bump="ribs", bump_amp=0.00008,
                bump_scale=0.0005, edge=0.3)
    zr = C_DECK + 0.024
    for si, sx in enumerate((1, -1)):
        for i, py in enumerate(C_PORT_Y):
            k = si * 4 + i
            x = sx * C_RAIL_X
            ant = Geo()
            ant += extrude(_hex(0.0095), 0.003, nickel, bevel=0.0004, bevel_seg=1, z0=zr, smooth_angle=20, tag="antenna_nut")
            ant += cylinder(0.0036, 0.003, thr, segs=12, z0=zr + 0.0028, caps=(False, False), tag="antenna_thread")
            ant += cylinder(0.0052, 0.012, fer, segs=10, bevel=0.0006, bevel_seg=1, z0=zr + 0.0055, tag="antenna_ferrule")
            kz = zr + 0.0175 + 0.0048
            ant.translate(x, py, 0)
            ant += cylinder(0.0048, 0.0095, knk, segs=8, bevel=0.0008, bevel_seg=1, z0=-0.00475, tag="antenna_knuckle").rotate(
                90, 0, 0).translate(x, py, kz)
            ant += box((0.0068, 0.0075, 0.005), knk, r=0.0012, seg=1, center=(x, py, kz - 0.0032), tag="antenna_yoke")
            tilt = 30.0 if i in (0, 3) else 20.0
            fan_y = (-8.0, -3.0, 3.0, 8.0)[i]
            ax = axis_angle((1, 0, 0), -fan_y) @ axis_angle((0, 1, 0), sx * tilt) @ vec(0, 0, 1)
            L = C_ANT_LEN[i] if si == 0 else C_ANT_LEN[3 - i]
            ant += _stubby(b, vec(x, py, kz), ax, L, 0.0118, C_ANT_COLS[k], segs=9, k=2.2, taper=0.78, ribs=2)
            b.add(ant, lod="h")
            med = extrude(_hex(0.0095), 0.017, nickel, z0=zr, caps=(False, True), smooth_angle=20, tag="antenna_med").translate(x, py, 0)
            st = cylinder(0.0060, L, "stub_rubber", segs=6, r_top=0.0045, caps=(False, True), tag="antenna_med")
            med += align(st, ax, (0, 1, 0), vec(x, py, kz))
            b.add(med, lod="m")

    # ---- prints -------------------------------------------------------------------------------------------------
    _case_prints(b, dw, dd)

    # ---- anchors, collision, cameras -----------------------------------------------------------------------------
    b.anchor(jammer="case", interact=(0.0, 0.10, 0.20))
    b.col_box((-W2 - 0.004, -D2 - 0.004, 0.0), (W2 + 0.004, D2 + 0.012, C_ZS), "PLASTIC_HIGH_DENSITY")
    lo = np.min([_lid_xf((sx * W2, sy * D2, C_ZS + sz * C_LID)) for sx in (-1, 1) for sy in (-1, 1) for sz in (0, 1)], axis=0)
    hi = np.max([_lid_xf((sx * W2, sy * D2, C_ZS + sz * C_LID)) for sx in (-1, 1) for sy in (-1, 1) for sz in (0, 1)], axis=0)
    b.col_box(lo, hi, "PLASTIC_HIGH_DENSITY")
    b.closeup("deck", (0.0, 0.0, C_DECK + 0.02), direction=(0.0, 0.55, 1.0), extent=0.50)
    b.closeup("panel", (0.040, 0.090, C_DECK + 0.01), direction=(0.1, 0.8, 1.0), extent=0.24)
    b.closeup("fan", (C_FAN_X, C_FAN_Y, C_DECK + 0.01), direction=(0.3, 0.6, 1.0), extent=0.12)
    b.closeup("frontface", (0.0, D2, 0.07), direction=(0.25, 1.0, 0.25), extent=0.50)
    b.closeup("lid", _lid_xf((0.0, 0.0, C_ZS + C_LID - C_WALL - 0.035)), direction=(0.0, 1.0, 0.25), extent=0.50)


def _case_prints(b, dw, dd):
    W2, D2 = CW / 2, CD / 2
    hard = "hardcase_olive"
    sand = (214, 204, 172)
    # base front stencil
    st = DecalCanvas(0.200, 0.026, ppm=3000)
    _stencil(st, 0.100, 0.013, "JX-40  FIELD CASE", 0.0105, sand, spacing=0.0022, seed=3)
    b.decal(st, center=(0.0, D2, 0.031), normal=(0, 1, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.5)
    # lid top stencil (faces backwards / up with the lid open)
    lt = DecalCanvas(0.300, 0.140, ppm=2200)
    _stencil(lt, 0.150, 0.058, "JX-40", 0.060, sand, spacing=0.008, seed=5)
    lt.text(0.150, 0.118, "FIELD CASE  ·  HANDLE WITH CARE", 0.0095, fnt="label-black", spacing=0.002, color=sand, alpha=0.85)
    _rot_decal(b, lt, (0.0, 0.0, C_ZS + C_LID), (0, 0, 1), (0, 1, 0), mats=[hard], depth=0.012, min_dot=0.6)
    # side plates: rating plate (+X) and asset tag (-X)
    rp = rating_plate(0.090, 0.034, "FIELD JAMMER", "JX-40", "SN 26-40112", ref="EQ-JX40-08",
                      rating="25.6 V  20 Ah  LiFePO4  ·  8 x 5 W", ppm=4500, icons=("factory", "date", "book", "warn"), foot="IP65")
    b.decal(rp, center=(W2, 0.040, 0.044), normal=(1, 0, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.6)
    se = DecalCanvas(0.180, 0.050, ppm=2600)
    _stencil(se, 0.090, 0.025, "JX-40", 0.030, sand, spacing=0.004, seed=13)
    b.decal(se, center=(W2, 0.0, 0.088), normal=(1, 0, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.6)
    from .common import asset_tag
    b.decal(asset_tag(0.060, 0.018, "JX40 07-C", seed=11, ppm=5000), center=(-W2, -0.040, 0.042), normal=(-1, 0, 0), up=(0, 0, 1),
            mats=[hard], depth=0.01, min_dot=0.6)
    sd = DecalCanvas(0.180, 0.050, ppm=2600)
    _stencil(sd, 0.090, 0.025, "JX-40", 0.030, sand, spacing=0.004, seed=9)
    b.decal(sd, center=(-W2, 0.0, 0.088), normal=(-1, 0, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.6)
    # caution sticker on the -X end beside the asset tag (the front is all latches + handle)
    cl = caution_label(0.070, 0.034, head="WARNING", lines=("RF TRANSMITTER INSIDE", "Lid open, antennas up", "before switching MAIN on"),
                       kind="warning", ppm=5000)
    b.decal(cl, center=(-W2, 0.048, 0.044), normal=(-1, 0, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.6)
    # valve legend
    vl = DecalCanvas(0.040, 0.010, ppm=5000)
    vl.text(0.020, 0.005, "PURGE", 0.0045, fnt="label-black", spacing=0.0008, color=sand, alpha=0.85)
    b.decal(vl, center=(-0.192, D2, 0.050), normal=(0, 1, 0), up=(0, 0, 1), mats=[hard], depth=0.01, min_dot=0.6)

    # deck prints (white pad print on the black anodised deck), readable from the front
    dk = DecalCanvas(dw, dd, ppm=2600)

    def P(x, y):              # deck point -> canvas (canvas x runs to -X, canvas y to +Y)
        return dw / 2 - x, y + dd / 2
    for i, (x, word) in enumerate(zip(C_ROCK_X, ("MAIN", "BANK A", "BANK B", "FAN"))):
        cx, cy = P(x, C_ROCK_Y + 0.019)
        dk.text(cx, cy, word, 0.0042, fnt="label", spacing=0.0004, **ink("orange" if i == 0 else "white"))
    cx, cy = P(C_DISP[0], C_DISP[1] - 0.047)
    dk.text(cx, cy, "JX-40  ·  8-BAND FIELD JAMMER", 0.0050, fnt="label", spacing=0.0006, **ink("white"))
    for x, y, word in ((-0.030, 0.150, "DC IN 24-30 V"), (-0.030, 0.104, "FUSE 30 A"), (-0.016, 0.060, "PWR"), (-0.016, 0.045, "TX")):
        cx, cy = P(x, y)
        dk.text(cx, cy, word, 0.0036, fnt="label", anchor="mm" if x == -0.030 else "lm", **ink("white"))
    # antenna numbers + band colour chips on the rail tops, in front of each antenna
    for sx in (1, -1):
        rl = DecalCanvas(0.016, 0.290, ppm=4000)
        for i, py in enumerate(C_PORT_Y):
            k = (0 if sx > 0 else 4) + i
            cy = py + 0.145
            rl.rect(0.003, cy + 0.0112, 0.010, 0.0020, r=0.0004, color=C_ANT_COLS[k], spec=0.3, gloss=0.45, height=0.000006)
            rl.text(0.008, cy + 0.0175, str(k + 1), 0.0048, fnt="label-black", **ink("white"))
        b.decal(rl, center=(sx * C_RAIL_X, 0.0, C_DECK + 0.024), normal=(0, 0, 1), up=(0, -1, 0), mats=["rail_anod"], depth=0.002,
                min_dot=0.8)
    for sx in (1, -1):
        cx, cy = P(sx * C_FAN_X, C_FAN_Y + 0.050)
        dk.text(cx, cy, "AIR OUT  ·  KEEP CLEAR", 0.0034, fnt="label-semi", spacing=0.0003, **ink("grey"))
    cx, cy = P(0.0, C_SLOT_Y + 0.0175)
    dk.text(cx, cy, "PA 8 x 5 W  ·  HOT SURFACE", 0.0036, fnt="label-semi", spacing=0.0003, **ink("orange"))
    for i in range(8):                     # output numbers above the slot, one per PA jack
        cx, cy = P(-0.0525 + i * 0.015 + (i - 3.5) * 0.0012, C_SLOT_Y + 0.0088)
        dk.text(cx, cy, str(8 - i), 0.0028, fnt="label", **ink("grey"))
    b.decal(dk, center=(0.0, 0.0, C_DECK), normal=(0, 0, 1), up=(0, -1, 0), mats=["deck_anod"], depth=0.0015, min_dot=0.8)
    # battery label (between the two straps)
    LW, LH = 0.078, 0.100
    bl = DecalCanvas(LW, LH, ppm=3200)
    bl.rect(0.0, 0.0, LW, LH, r=0.004, color=(26, 27, 28), spec=0.3, gloss=0.45)
    bl.rect(0.0, 0.0, LW, 0.019, r=0.004, color=(214, 160, 40), spec=0.35, gloss=0.5)
    bl.text(0.039, 0.0095, "BP-40", 0.0095, fnt="label-black", spacing=0.001, color=(20, 20, 20))
    bl.text(0.039, 0.030, "LiFePO4", 0.0070, fnt="label", **ink("white"))
    bl.text(0.039, 0.043, "25.6 V  20 Ah  512 Wh", 0.0048, fnt="label-semi", max_w=0.070, **ink("white"))
    for k, t in enumerate(("Charge with the BP-40 charger only.", "Do not short, crush or burn.", "Keep away from heat above 60 C.")):
        bl.text(0.039, 0.0555 + k * 0.0072, t, 0.0030, fnt="label-reg", max_w=0.070, **ink("grey"))
    for k, kind in enumerate(("recycle", "bin", "warn")):
        bl.icon(kind, 0.011 + k * 0.016, 0.0815, 0.011, color=INK["white"] if kind != "warn" else (16, 16, 18))
    bl.barcode(0.052, 0.0765, 0.022, 0.011, seed=40, color=INK["white"])
    bl.text(0.063, 0.0935, "SN 40-2611", 0.0026, fnt="mono-bold", color=INK["grey"])
    bx, by = C_BATT
    b.decal(bl, center=(bx, by, C_DECK + C_BATT_SIZE[2]), normal=(0, 0, 1), up=(0, -1, 0), mats=["battery_case"], depth=0.003, min_dot=0.7)
    # quick-start card inside the lid
    qc = DecalCanvas(0.190, 0.120, ppm=3200)
    qc.rect(0.0, 0.0, 0.190, 0.020, color=(24, 26, 28))
    qc.text(0.008, 0.010, "JX-40  ·  QUICK START", 0.0070, fnt="label-black", anchor="lm", spacing=0.0008, color=(240, 240, 236))
    steps = ("Unfold all eight antennas before power-up.", "Battery lead into DC IN, fuse seated.", "MAIN on, then BANK A and BANK B.",
             "FAN stays on while transmitting.", "MAIN off before folding or closing.")
    for k, t in enumerate(steps):
        y = 0.032 + k * 0.0145
        qc.circle(0.012, y, 0.0045, color=(214, 120, 30))
        qc.text(0.012, y, str(k + 1), 0.0045, fnt="label-black", color=(255, 255, 255))
        qc.text(0.022, y, t, 0.0048, fnt="label-semi", anchor="lm", color=(30, 32, 35), max_w=0.162)
    qc.rect(0.008, 0.106, 0.174, 0.0008, color=(150, 154, 158))
    qc.text(0.008, 0.113, "Keep 2 m clear of the antennas while TX is lit.", 0.0036, fnt="label-semi", anchor="lm", color=(170, 40, 36))
    _rot_decal(b, qc, (0.07, 0.01, C_ZS + C_LID - C_WALL - 0.0356), (0, 0, -1), (0, 1, 0), mats=["quick_card"], depth=0.004, min_dot=0.6)


# =============================================================================================
# JX-90 heavy jammer  cabinet 550 x 400 x 550 mm on four feet, welded tube mast ~1.0 m, 8 whips
# =============================================================================================
HW, HD, HH = 0.550, 0.400, 0.550
H_Z0 = 0.048                   # cabinet floor (top of the feet / base frame)
H_ZT = H_Z0 + HH               # cabinet top
H_ROOF = H_ZT + 0.012          # roof plate top
H_DOOR = (0.470, 0.462)        # door w x h
H_DOOR_Z = H_Z0 + 0.026 + H_DOOR[1] / 2
H_MAST_R = 0.0215
H_MAST_TOP = H_ROOF + 0.990
H_LOW = H_ROOF + 0.540         # lower antenna arms
H_UP = H_ROOF + 0.890          # upper antenna arms
H_LAMPS = ((0.090, (60, 255, 120), "PWR"), (0.034, (255, 46, 40), "JAM"), (-0.022, (255, 170, 30), "ALM"))   # bezel centres (x)
H_KEY_X = -0.088
H_FIELD = (0.0225, 0.0, 0.355, 0.400)    # door field centre x, z offset, w, h (clear of hinges and the latch escutcheon)


def _louvre_panel(b, x_face, sx, yc, zc, w, h, n, olive, dark):
    """Pressed louvres on a side face (x = x_face, outward sx): a dark opening + n hooded slats."""
    g = Geo()
    g += box((0.002, w + 0.012, h + 0.010), dark, center=(x_face + sx * 0.001, yc, zc), faces="+x" if sx > 0 else "-x", tag="vent")
    # hood profile in (out, z): a thick quarter-shell, open at the bottom
    R0, R1 = 0.0125, 0.0108
    outer = [(R0 * math.cos(a), R0 * math.sin(a)) for a in np.linspace(math.radians(95), math.radians(-25), 9)]
    inner = [(R1 * math.cos(a), R1 * math.sin(a)) for a in np.linspace(math.radians(-25), math.radians(95), 9)]
    prof = np.array(outer + inner) + np.array([-0.0035, 0.0])
    pitch = h / n
    for i in range(n):
        z = zc - h / 2 + pitch * (i + 0.62)
        path = np.array([(0.0, yc - w / 2, 0.0), (0.0, yc + w / 2, 0.0)])
        # sweep profile x -> frame side, y -> frame up: build along +Y with side = +X (outward) and up = +Z
        sl = sweep(prof, path, olive, side=(1, 0, 0), smooth_angle=50, tag="louvre")
        if sx < 0:
            sl.mirror("x")
        g += sl.translate(x_face, 0.0, z)
    # pressed frame bead around the panel
    for dz in (-1, 1):
        g += box((0.004, w + 0.022, 0.006), olive, r=0.0018, seg=1, center=(x_face + sx * 0.002, yc, zc + dz * (h / 2 + 0.008)),
                 faces="+x +z -z" if sx > 0 else "-x +z -z", tag="vent_bead")
    for dy in (-1, 1):
        g += box((0.004, 0.006, h + 0.022), olive, r=0.0018, seg=1, center=(x_face + sx * 0.002, yc + dy * (w / 2 + 0.008), zc),
                 faces="+x +y -y" if sx > 0 else "-x +y -y", tag="vent_bead")
    return g


def _whip(b, base, axis, length, coil_mat, whip_mat, tip_mat, nickel, segs=10):
    """Military whip on a loading-coil base: N connector, ribbed black coil housing, tapering olive
    fibreglass whip, black tip cap. Built along +Z from `base`, aligned to `axis`."""
    g = Geo()
    g += cylinder(0.0115, 0.022, nickel, segs=segs, bevel=0.0012, bevel_seg=1, tag="antenna_mount")
    prof = [(0.0, 0.022), (0.0150, 0.022), (0.0150, 0.030)]
    for i in range(4):
        z = 0.036 + i * 0.022
        prof += [(0.0150, z), (0.0138, z + 0.003), (0.0138, z + 0.006), (0.0150, z + 0.009)]
    prof += [(0.0150, 0.128), (0.0122, 0.140), (0.0080, 0.148), (0.0, 0.149)]
    g += lathe(prof, coil_mat, segs=segs + 2, smooth_angle=50, tag="antenna_coil")
    zt = length - 0.005
    g += lathe([(0.0068, 0.146), (0.0064, 0.20), (0.0052, 0.20 + (zt - 0.20) * 0.5), (0.0038, zt), (0.0, zt + 0.0004)], whip_mat, segs=segs,
               smooth_angle=50, tag="antenna_whip")
    g += lathe([(0.0, zt - 0.010), (0.0046, zt - 0.010), (0.0050, zt - 0.002)] + [(0.0050 * math.cos(a), zt + 0.0050 * math.sin(a))
                                                                               for a in np.linspace(0.3, math.pi / 2, 4)],
               tip_mat, segs=segs, smooth_angle=50, tag="antenna_tip")
    g.charts[-1].pos[-1:] *= 1.0
    return align(g, axis, (0, 1, 0) if abs(vec(axis)[1]) < 0.9 else (1, 0, 0), base)


def _n_bulkhead(b, at, nickel, boot):
    g = Geo()
    g += extrude(_hex(0.024), 0.005, nickel, bevel=0.0007, bevel_seg=1, smooth_angle=20, tag="nconn")
    g += cylinder(0.0095, 0.016, nickel, segs=12, bevel=0.0008, bevel_seg=1, z0=0.005, tag="nconn")
    g += lathe([(0.0, 0.021), (0.0105, 0.021), (0.0105, 0.034), (0.0085, 0.036), (0.0072, 0.040)], nickel, segs=12, smooth_angle=45, tag="nconn")
    g += lathe([(0.0072, 0.040), (0.0072, 0.046), (0.0062, 0.060), (0.0050, 0.066), (0.0, 0.066)], boot, segs=10, smooth_angle=45, tag="nboot")
    return g.translate(at)


def _mast_point(level_z, ang, r):
    a = math.radians(ang)
    return vec(r * math.cos(a), r * math.sin(a), level_z)


def _jx90_arms():
    """(level z, arm angle deg, arm length, antenna tilt deg, antenna length) for the 8 whips."""
    out = []
    for ang in (0, 90, 180, 270):
        out.append((H_LOW, ang, 0.205, 33.0, 0.560))
    for ang in (45, 135, 225, 315):
        out.append((H_UP, ang, 0.135, 17.0, 0.480))
    return out


@prop("nzr_jammer_heavy", atlas=2048, alpha_atlas=128, glow_atlas=64, lod=150.0, lod_high=20.0, hd=20.0, med_drop=0.012,
      budget=40000, falloff=70.0, layers={"face": 1024}, maps={"face": {"n": 512, "s": 512}},
      doc={"title": "JX-90 heavy jammer (olive steel cabinet 55 x 40 x 55 cm on four feet, welded tube mast ~1 m, 8 whips)",
           "origin": "bottom centre (stands on four feet)",
           "axes": "+Y = front (hinged door with swing-handle latch, status lamps above it), +Z up; louvres + lifting handles on "
                   "the +-X sides; mast on the roof, coax down to N bulkheads on the roof",
           "attach": "placed on the ground (client/modules/jammers.lua): frozen, non-networked; ghost while placing"},
      preview={"views": ["front", "iso", "front34", "face", "back", "left", "top", "back34"]})
def jammer_heavy(b):
    from .common import hinge
    from .radio_common import m_olive_steel
    olive = m_olive_steel(b)
    olive_d = b.mat("olive_steel_dark", color=(62, 67, 48), spec=0.26, gloss=0.34, metal=0.2, bump="orange_peel", bump_amp=0.00002,
                    bump_scale=0.002, grain=0.05, grain_scale=0.08, edge=0.8, wear=0.75, wear_color=(140, 140, 136), dirt=0.4,
                    scratch=0.35)
    dark = b.mat("vent_dark", color=(10, 11, 10), spec=0.08, gloss=0.15, ao=1.0, cavity=0.2)
    blk = b.mat("black_steel", color=(26, 27, 26), spec=0.35, gloss=0.42, metal=0.5, bump="orange_peel", bump_amp=0.00002,
                bump_scale=0.002, edge=0.7, wear_color=(130, 130, 128), dirt=0.3, scratch=0.3)
    zinc = b.mat("zinc", color=(160, 164, 166), spec=0.7, gloss=0.5, metal=1.0, grain=0.05, grain_scale=0.02, edge=0.3, dirt=0.35, scratch=0.3)
    chrome = b.mat("lamp_chrome", color=(196, 200, 204), spec=0.95, gloss=0.86, metal=1.0, grain=0.01, edge=0.2, dirt=0.2)
    nickel = m_sma(b, "nickel")
    rub = m_rubber(b)
    coax = b.mat("coax_jacket", color=(20, 21, 23), spec=0.32, gloss=0.5, grain=0.02, edge=0.15, dirt=0.25)
    coil = b.mat("coil_black", color=(24, 25, 24), spec=0.25, gloss=0.35, bump="stipple", bump_amp=0.00004, bump_scale=0.0012, edge=0.5,
                 dirt=0.3, wear_color=(80, 82, 78))
    glass_whip = b.mat("whip_olive", color=(86, 92, 62), spec=0.35, gloss=0.5, grain=0.06, grain_scale=0.05, edge=0.4, dirt=0.3,
                       wear_color=(140, 142, 120))
    W2, D2 = HW / 2, HD / 2
    zc = H_Z0 + HH / 2

    # ---- cabinet --------------------------------------------------------------------------------------------
    cab = box((HW, HD, HH), olive, r=0.007, seg=2, center=(0, 0, zc), tag="cab", face_density={"-z": 0.25, "-y": 0.8})
    b.add(cab)
    b.add(box((HW + 0.026, HD + 0.026, 0.012), olive, r=0.004, seg=1, center=(0, 0, H_ZT + 0.006), tag="roof",
              face_density={"-z": 0.3}))
    b.add(box((HW + 0.020, HD + 0.020, 0.010), olive_d, r=0.003, seg=1, center=(0, 0, H_ZT - 0.001), faces="+x -x +y -y -z",
              tag="drip"))
    # base frame + feet
    for sy in (-1, 1):
        b.add(box((HW - 0.010, 0.034, 0.030), blk, r=0.003, seg=1, center=(0, sy * (D2 - 0.022), H_Z0 - 0.015), tag="frame"))
    for sx in (-1, 1):
        b.add(box((0.034, HD - 0.078, 0.030), blk, r=0.003, seg=1, center=(sx * (W2 - 0.022), 0, H_Z0 - 0.015), faces="+x -x -z", tag="frame"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W2 - 0.026), sy * (D2 - 0.026)
            b.add(box((0.046, 0.046, 0.014), blk, r=0.003, seg=1, center=(x, y, H_Z0 - 0.034), tag="foot_post"))
            b.add(cylinder(0.026, 0.010, rub, segs=16, bevel=0.002, bevel_seg=1, z0=0.0, tag="foot_pad").translate(x, y, 0))
            b.hi_only(cylinder(0.012, 0.018, zinc, segs=12, bevel=0.001, bevel_seg=1, z0=0.009, tag="foot_stud").translate(x, y, 0))
            b.hi_only(extrude(_hex(0.024), 0.008, zinc, bevel=0.0008, bevel_seg=1, z0=0.016, smooth_angle=20).translate(x, y, 0))

    # ---- front: door, hinges, swing-handle latch, lamp panel ---------------------------------------------------------
    dw, dh = H_DOOR
    yf = D2
    olive_face = b.mat("olive_door", color=(78, 84, 60), spec=0.26, gloss=0.34, metal=0.2, bump="orange_peel", bump_amp=0.00002,
                       bump_scale=0.002, grain=0.05, grain_scale=0.08, edge=0.8, wear=0.75, wear_color=(140, 140, 136), dirt=0.35,
                       scratch=0.35, layer="face")
    door = box((dw, 0.012, dh), olive, r=0.005, seg=2, center=(0, yf + 0.004, H_DOOR_Z), faces="+x -x +y +z -z", tag="door",
               face_mat={"+y": olive_face})
    b.add(door)
    yd = yf + 0.010            # door face
    # pressed stiffening field on the door (catches the light along its bevel; the stickers sit on it)
    field = extrude(rrect(H_FIELD[2], H_FIELD[3], 0.012, 4), 0.0025, olive_face, bevel=0.0018, bevel_seg=2, caps=(False, True),
                    smooth_angle=45, tag="door_field")
    b.add(align(field, (0, 1, 0), (0, 0, 1), (H_FIELD[0], yd, H_DOOR_Z + H_FIELD[1])))
    for z in (H_DOOR_Z - 0.165, H_DOOR_Z + 0.165):
        b.add(hinge(b, (W2 - 0.026 + 0.0, yd + 0.002, z - 0.045), (W2 - 0.026, yd + 0.002, z + 0.045), r=0.0075, knuckles=3, mat=olive_d,
                    segs=10))
        b.add(box((0.030, 0.003, 0.090), olive_d, r=0.0012, seg=1, center=(W2 - 0.044, yd + 0.0005, z), tag="hinge_leaf"))
    lx = -0.188
    esc = extrude(_round([(-0.022, -0.072), (0.022, -0.072), (0.022, 0.072), (-0.022, 0.072)], 0.008, n=3), 0.006, blk, bevel=0.0015,
                  bevel_seg=1, smooth_angle=45, tag="latch_esc")
    b.add(align(esc, (0, 1, 0), (0, 0, 1), (lx, yd, H_DOOR_Z)))
    lever = extrude(_round([(-0.0105, -0.060), (0.0105, -0.060), (0.0105, 0.046), (-0.0105, 0.046)], 0.0045, n=3), 0.009, chrome,
                    bevel=0.0025, bevel_seg=2, smooth_angle=45, tag="latch_lever")
    b.add(align(lever, (0, 1, 0), (0, 0, 1), (lx, yd + 0.006, H_DOOR_Z - 0.006)))
    b.add(align(cylinder(0.0085, 0.006, chrome, segs=16, bevel=0.0012, bevel_seg=1), (0, 1, 0), (0, 0, 1), (lx, yd + 0.006, H_DOOR_Z + 0.056)))
    b.hi_only(align(box((0.0016, 0.0085, 0.002), dark), (0, 1, 0), (0, 0, 1), (lx, yd + 0.012, H_DOOR_Z + 0.056)))
    # padlock hasp under the latch
    b.add(align(box((0.016, 0.026, 0.004), blk, r=0.0015, seg=1), (0, 1, 0), (0, 0, 1), (lx, yd, H_DOOR_Z - 0.095)))
    b.hi_only(torus(0.0055, 0.0016, zinc, segs=12, tube_segs=5).translate(lx, yd + 0.0095, H_DOOR_Z - 0.098))
    # lamp panel above the door
    pz = H_ZT - 0.026
    lamp_plate = b.mat_from("lamp_plate", dc_replace(b.mats[blk], layer="face"))     # legends: the door's sharper atlas
    b.add(box((0.250, 0.006, 0.040), lamp_plate, r=0.002, seg=1, center=(0, yf + 0.003, pz), faces="+x -x +y +z -z", tag="lamp_plate"))
    for x, col, _ in H_LAMPS:
        bez = lathe([(0.0, 0.0), (0.0118, 0.0), (0.0118, 0.0035), (0.0100, 0.0062), (0.0082, 0.0066)], chrome, segs=20, smooth_angle=45,
                    tag="lamp_bezel")
        b.add(align(bez, (0, 1, 0), (0, 0, 1), (x, yf + 0.006, pz)))
        lens = b.mat(f"lamp_{col[0]}_{col[1]}_{col[2]}", color=col, layer="glow")
        dome = lathe([(0.0082, 0.0062)] + [(0.0082 * math.cos(a), 0.0062 + 0.0055 * math.sin(a)) for a in np.linspace(0.2, math.pi / 2, 5)],
                     lens, segs=20, smooth_angle=60, tag="lamp_lens")
        dome.charts[-1].pos[:] = dome.charts[-1].pos
        b.add(align(dome, (0, 1, 0), (0, 0, 1), (x, yf + 0.006, pz)))
    # key switch at the right end of the panel
    b.add(align(cylinder(0.0085, 0.006, chrome, segs=16, bevel=0.0012, bevel_seg=1), (0, 1, 0), (0, 0, 1), (H_KEY_X, yf + 0.006, pz)))
    b.hi_only(align(box((0.0018, 0.010, 0.0025), dark), (0, 1, 0), (0, 0, 1), (H_KEY_X, yf + 0.0125, pz)))

    # ---- sides: louvres, lifting handles -------------------------------------------------------------------------
    for sx in (1, -1):
        xf = sx * W2
        b.add(_louvre_panel(b, xf, sx, 0.0, H_Z0 + 0.205, 0.300, 0.240, 10, olive, dark))
        hz = H_ZT - 0.085
        path = polyline_fillet([(xf, -0.115, hz), (xf + sx * 0.052, -0.115, hz), (xf + sx * 0.052, 0.115, hz), (xf, 0.115, hz)], 0.024, 6)
        b.add(tube(path, 0.0085, blk, segs=10, tag="lift_handle"))
        for yy in (-0.115, 0.115):
            b.add(box((0.006, 0.040, 0.040), blk, r=0.002, seg=1, center=(xf + sx * 0.003, yy, hz), faces="+x +y -y +z -z" if sx > 0 else
                      "-x +y -y +z -z", tag="handle_plate"))
            for dz in (-1, 1):
                b.hi_only(screw(b, (xf + sx * 0.006, yy, hz + dz * 0.013), (sx, 0, 0), (0, 0, 1), d=0.0075, kind="hex", color=(70, 72, 68),
                                segs=8))
    # ---- back: gland plate, power inlet, earth stud ---------------------------------------------------------------
    yb = -D2
    b.add(box((0.200, 0.006, 0.100), olive_d, r=0.003, seg=1, center=(0.08, yb - 0.003, H_Z0 + 0.120), faces="+x -x -y +z -z", tag="gland_plate"))
    for i, x in enumerate((0.040, 0.120)):
        gl = lathe([(0.0, 0.0), (0.0145, 0.0), (0.0145, 0.006), (0.0118, 0.009), (0.0105, 0.016), (0.0072, 0.020), (0.0068, 0.040)], blk,
                   segs=14, smooth_angle=45, tag="gland")
        b.hi_only(align(gl, (0, -1, 0), (0, 0, 1), (x, yb - 0.006, H_Z0 + 0.120)))
        cab_path = catmull([(x, yb - 0.046, H_Z0 + 0.120), (x, yb - 0.080, H_Z0 + 0.090), (x + 0.01, yb - 0.10, H_Z0 + 0.01),
                            (x + 0.04 * (i + 1), yb - 0.20, 0.006)], n=6)
        b.hi_only(tube(cab_path, 0.0065, coax, segs=8, tag="power_cable"))
    from .radio_common import round_connector
    b.hi_only(round_connector(b, (-0.120, yb, H_Z0 + 0.120), (0, -1, 0), (0, 0, 1), d=0.036, pins=5, depth=0.010))
    b.hi_only(align(cylinder(0.006, 0.026, zinc, segs=10, bevel=0.001, bevel_seg=1), (0, -1, 0), (0, 0, 1), (-0.220, yb, H_Z0 + 0.060)))

    # ---- roof: lifting eye bolts at the corners ------------------------------------------------------------------
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.258, sy * 0.183
            eb = cylinder(0.0115, 0.006, zinc, segs=12, bevel=0.0012, bevel_seg=1, tag="eyebolt")
            eb += cylinder(0.0055, 0.008, zinc, segs=8, z0=0.006, caps=(False, False), tag="eyebolt")
            eb += torus(0.0155, 0.0042, zinc, segs=16, tube_segs=6, tag="eyebolt").rotate(90, 0, 0).translate(0, 0, 0.0285)
            b.add(eb.rotate(0, 0, math.degrees(math.atan2(y, x)) + 90).translate(x, y, H_ROOF))
    # ---- roof: mast flange, mast, braces, arms, whips, coax ---------------------------------------------------------
    b.add(box((0.170, 0.170, 0.012), olive_d, r=0.003, seg=1, center=(0, 0, H_ROOF + 0.006), tag="flange"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.hi_only(extrude(_hex(0.017), 0.008, zinc, bevel=0.0008, bevel_seg=1, z0=H_ROOF + 0.012, smooth_angle=20).translate(
                sx * 0.068, sy * 0.068, 0))
    mast = Geo()
    mast += cylinder(H_MAST_R, H_MAST_TOP - H_ROOF - 0.012, olive, segs=16, z0=H_ROOF + 0.012, caps=(False, False), tag="mast")
    mast += lathe([(H_MAST_R, H_MAST_TOP), (H_MAST_R + 0.002, H_MAST_TOP + 0.002), (H_MAST_R + 0.002, H_MAST_TOP + 0.010),
                   (H_MAST_R - 0.004, H_MAST_TOP + 0.016), (0.0, H_MAST_TOP + 0.018)], olive_d, segs=16, smooth_angle=50, tag="mast_cap")
    mast += lathe([(H_MAST_R + 0.012, H_ROOF + 0.012), (H_MAST_R + 0.012, H_ROOF + 0.020), (H_MAST_R + 0.003, H_ROOF + 0.034),
                   (H_MAST_R, H_ROOF + 0.040)], olive, segs=16, smooth_angle=40, tag="mast_gusset")
    # braces: four tubes from the roof corners to a collar on the mast
    zcol = H_ROOF + 0.330
    mast += cylinder(H_MAST_R + 0.006, 0.040, olive_d, segs=16, bevel=0.002, bevel_seg=1, z0=zcol - 0.020, tag="mast_collar")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p0 = vec(sx * 0.205, sy * 0.140, H_ROOF + 0.004)
            p1 = vec(sx * 0.024, sy * 0.016, zcol - 0.004)
            mast += tube(np.array([p0, p1]), 0.0105, olive, segs=10, tag="brace")
            mast += box((0.050, 0.040, 0.008), olive_d, r=0.002, seg=1, center=(p0[0], p0[1], H_ROOF + 0.004), tag="brace_foot")
    # arms + clamp blocks
    arms = _jx90_arms()
    for zl, ang, L, tilt, alen in arms:
        d = _mast_point(0, ang, 1.0)
        a0 = _mast_point(zl, ang, H_MAST_R - 0.002)
        a1 = _mast_point(zl, ang, L)
        mast += tube(np.array([a0, a1]), 0.0115, olive, segs=10, tag="arm")
        # diagonal strut under each lower arm
        if zl == H_LOW:
            mast += tube(np.array([_mast_point(zl - 0.150, ang, H_MAST_R - 0.002), _mast_point(zl - 0.006, ang, L * 0.72)]), 0.0075, olive,
                         segs=8, tag="arm_strut")
        blkc = box((0.040, 0.040, 0.050), olive_d, r=0.004, seg=1, center=(0, 0, 0), tag="clamp")
        blkc.rotate(0, 0, ang).translate(a1 + d * 0.012)
        mast += blkc
        # two U-bolts holding the clamp block on the arm tube (+ nuts on the block's top)
        sv = np.cross(vec(0, 0, 1), d)
        for off in (-0.026, -0.044):
            c0 = a1 + d * off
            ub = [c0 + sv * 0.0145 + vec(0, 0, 0.014)]
            ub += [c0 + sv * 0.0145 * math.cos(t) + vec(0, 0, -0.0145 * math.sin(t)) for t in np.linspace(0, math.pi, 9)]
            ub += [c0 - sv * 0.0145 + vec(0, 0, 0.014)]
            b.hi_only(tube(np.array(ub), 0.0026, zinc, segs=6, tag="ubolt"))
            for sgn in (-1, 1):
                b.hi_only(extrude(_hex(0.0095), 0.005, zinc, bevel=0.0005, bevel_seg=1, z0=0.0, smooth_angle=20).translate(
                    c0 + sv * 0.0145 * sgn + vec(0, 0, 0.0115)))
            b.hi_only(box((0.008, 0.040, 0.004), zinc, r=0.001, seg=1, center=(0, 0, 0)).rotate(0, 0, ang).translate(c0 + vec(0, 0, 0.0115)))
    for zl in (H_LOW, H_UP):
        mast += cylinder(H_MAST_R + 0.007, 0.050, olive_d, segs=16, bevel=0.002, bevel_seg=1, z0=zl - 0.025, tag="mast_collar")
    b.add(mast)
    # whips
    for k, (zl, ang, L, tilt, alen) in enumerate(arms):
        d = _mast_point(0, ang, 1.0)
        a1 = _mast_point(zl, ang, L) + d * 0.012
        side = np.cross(vec(0, 0, 1), d)
        axis = axis_angle(side, tilt) @ vec(0, 0, 1)
        base = a1 + vec(0, 0, 0.025)
        b.add(_whip(b, base, axis, alen, coil, glass_whip, blk, nickel, segs=10), lod="h")
        st = cylinder(0.014, 0.15, "coil_black", segs=6, caps=(False, True), tag="antenna_med")
        st += cylinder(0.0060, alen - 0.15, "whip_olive", segs=5, z0=0.15, r_top=0.004, caps=(False, True), tag="antenna_med")
        b.add(align(st, axis, (0, 1, 0) if abs(axis[1]) < 0.9 else (1, 0, 0), base), lod="m")
    # bulkheads on the roof + coax runs up the mast
    boot = b.mat("boot_black", color=(18, 19, 20), spec=0.2, gloss=0.32, bump="rubber", bump_amp=0.00004, bump_scale=0.0008, edge=0.3,
                 dirt=0.3)
    tie = b.mat("cable_tie", color=(16, 16, 17), spec=0.35, gloss=0.5, edge=0.3)
    rc = H_MAST_R + 0.0052
    for k, (zl, ang, L, tilt, alen) in enumerate(arms):
        d = _mast_point(0, ang, 1.0)
        bang = ang + 22.5
        bpt = _mast_point(H_ROOF, bang, 0.118 if k < 4 else 0.150)
        b.hi_only(_n_bulkhead(b, bpt, nickel, boot))
        a1 = _mast_point(zl, ang, L) + d * 0.012
        lane = ang + (8.0 if k < 4 else -8.0)
        pts = [a1 + vec(0, 0, -0.030), a1 - d * 0.035 + vec(0, 0, -0.085), _mast_point(zl - 0.120, ang, L * 0.45) + vec(0, 0, -0.03),
               _mast_point(zl - 0.170, lane, rc + 0.003)]
        zz = zl - 0.26
        while zz > zcol + 0.08:
            pts.append(_mast_point(zz, lane, rc))
            zz -= 0.16
        pts += [_mast_point(zcol + 0.04, lane, rc + 0.009), _mast_point(zcol - 0.06, lane + 6, rc + 0.040),
                _mast_point(H_ROOF + 0.17, bang, 0.110), bpt + vec(0, 0, 0.115), bpt + vec(0, 0, 0.066)]
        b.hi_only(tube(catmull(pts, n=4), 0.0047, coax, segs=6, split=0.25, tag="coax"))
    # cable ties round the mast
    for z in np.arange(zcol + 0.10, H_UP - 0.05, 0.16):
        b.hi_only(torus(rc + 0.0052, 0.0011, tie, segs=20, tube_segs=4).translate(0, 0, z))

    # ---- prints ---------------------------------------------------------------------------------------------------
    _heavy_prints(b)

    # ---- anchors, collision, cameras ---------------------------------------------------------------------------------
    b.anchor(jammer="heavy", interact=(0.0, 0.26, 0.42))
    b.col_box((-W2 - 0.013, -D2 - 0.013, 0.0), (W2 + 0.013, D2 + 0.016, H_ROOF), "METAL_SOLID_MEDIUM")
    b.col_box((-0.23, -0.23, H_ROOF), (0.23, 0.23, H_MAST_TOP + 0.02), "METAL_HOLLOW_SMALL")
    b.closeup("door", (0.0, D2, H_DOOR_Z + 0.03), direction=(0.15, 1.0, 0.25), extent=0.62)
    b.closeup("lamps", (0.0, D2, H_ZT - 0.026), direction=(0.25, 1.0, 0.3), extent=0.30)
    b.closeup("mast", (0.0, 0.0, H_ROOF + 0.45), direction=(0.6, 1.0, 0.35), extent=1.0)
    b.closeup("roof", (0.0, 0.0, H_ROOF + 0.10), direction=(0.4, 0.8, 0.9), extent=0.55)
    b.closeup("side", (W2, 0.0, H_Z0 + 0.30), direction=(1.0, 0.35, 0.2), extent=0.62)


def _heavy_prints(b):
    W2, D2 = HW / 2, HD / 2
    olive = "olive_steel"
    sand = (222, 214, 182)
    yd = D2 + 0.010
    # door: DANGER sticker, model placard, HV sticker, rating plate
    dg = caution_label(0.200, 0.110, head="DANGER", lines=("RF RADIATION HAZARD", "Keep 3 m clear of the mast", "while JAM is lit.",
                                                            "Authorised personnel only."), kind="danger", ppm=2600)
    door = ["olive_door"]
    b.decal(dg, center=(0.050, yd, H_DOOR_Z + 0.120), normal=(0, 1, 0), up=(0, 0, 1), mats=door, depth=0.004, min_dot=0.6)
    mp = DecalCanvas(0.220, 0.080, ppm=3000)
    mp.rect(0, 0, 0.220, 0.080, r=0.004, color=(24, 26, 24), spec=0.35, gloss=0.5)
    mp.rect(0.004, 0.004, 0.212, 0.072, r=0.003, fill=False, width=0.0012, color=sand)
    mp.text(0.014, 0.032, "JX-90", 0.024, fnt="label-black", anchor="lm", spacing=0.0015, color=(240, 236, 220), max_w=0.110)
    mp.text(0.014, 0.062, "AREA JAMMER  ·  8 BAND", 0.0066, fnt="label", anchor="lm", spacing=0.0008, color=sand, max_w=0.112)
    mp.rect(0.134, 0.014, 0.0010, 0.052, color=sand)
    for k, t in enumerate(("230 V AC / 24 V DC", "8 x 25 W  PA", "IP55  ·  OUTDOOR")):
        mp.text(0.142, 0.024 + k * 0.016, t, 0.0050, fnt="label-semi", anchor="lm", color=(220, 216, 200), max_w=0.072)
    b.decal(mp, center=(0.050, yd, H_DOOR_Z - 0.010), normal=(0, 1, 0), up=(0, 0, 1), mats=door, depth=0.004, min_dot=0.6)
    hv = caution_label(0.090, 0.060, head="WARNING", lines=("HIGH VOLTAGE INSIDE", "Isolate before opening"), kind="warning",
                       symbol="bolt", ppm=3200)
    b.decal(hv, center=(0.090, yd, H_DOOR_Z - 0.130), normal=(0, 1, 0), up=(0, 0, 1), mats=door, depth=0.004, min_dot=0.6)
    rp = rating_plate(0.090, 0.034, "AREA JAMMER", "JX-90", "SN 26-90031", ref="EQ-JX90-25", rating="230 V~ 50 Hz  900 W  ·  24 V DC",
                      ppm=4000, icons=("factory", "date", "book", "warn"), foot="IP55")
    b.decal(rp, center=(-0.040, yd, H_DOOR_Z - 0.140), normal=(0, 1, 0), up=(0, 0, 1), mats=door, depth=0.004, min_dot=0.6)
    # the door gap on the cabinet face
    gp = DecalCanvas(0.490, 0.482, ppm=1500)
    gp.groove_rect(0.004, 0.004, 0.482, 0.474, r=0.006, width=0.004, depth=0.001, alpha=0.75)
    b.decal(gp, center=(0.0, D2, H_DOOR_Z), normal=(0, 1, 0), up=(0, 0, 1), mats=[olive], depth=0.003, min_dot=0.6)
    # lamp legends on the black plate
    lp = DecalCanvas(0.250, 0.040, ppm=3200)
    for x, col, word in H_LAMPS:          # canvas x runs to -X: legend to the viewer's right of each lamp
        lp.text(0.125 - x + 0.0155, 0.020, word, 0.0062, fnt="label", anchor="lm", **ink("white"))
    lp.text(0.125 - H_KEY_X + 0.0135, 0.016, "KEY", 0.0046, fnt="label", anchor="lm", **ink("grey"))
    lp.text(0.125 - H_KEY_X + 0.0135, 0.026, "0 / I", 0.0040, fnt="label", anchor="lm", **ink("grey"))
    b.decal(lp, center=(0.0, D2 + 0.006, H_ZT - 0.026), normal=(0, 1, 0), up=(0, 0, 1), mats=["lamp_plate"], depth=0.002, min_dot=0.6)
    # sides: stencils above the louvres, lifting legend
    for sx in (1, -1):
        st = DecalCanvas(0.300, 0.060, ppm=2000)
        _stencil(st, 0.150, 0.028, "JX-90", 0.036, sand, spacing=0.005, seed=21 + sx)
        st.text(0.150, 0.054, "LIFT HERE  ·  2 PERSONS  ·  38 kg", 0.0060, fnt="label-black", spacing=0.0012, color=sand, alpha=0.8)
        b.decal(st, center=(sx * W2, 0.0, H_Z0 + 0.380), normal=(sx, 0, 0), up=(0, 0, 1), mats=[olive], depth=0.004, min_dot=0.6)
    # back: rating repeat + cable legend
    bk = DecalCanvas(0.200, 0.030, ppm=2600)
    bk.text(0.100, 0.010, "MAINS IN  ·  24 V DC  ·  DATA", 0.0062, fnt="label-black", spacing=0.001, color=sand)
    bk.text(0.100, 0.023, "EARTH BEFORE CONNECTING", 0.0052, fnt="label", spacing=0.001, color=(236, 196, 40))
    b.decal(bk, center=(-0.030, -D2, H_Z0 + 0.190), normal=(0, -1, 0), up=(0, 0, 1), mats=[olive], depth=0.004, min_dot=0.6)
    b.decal(rating_plate(0.090, 0.034, "AREA JAMMER", "JX-90", "SN 26-90031", ref="EQ-JX90-25", rating="230 V~ 50 Hz  900 W",
                         ppm=4000, icons=("factory", "date", "book", "bin"), foot="IP55"),
            center=(0.150, -D2, H_Z0 + 0.420), normal=(0, -1, 0), up=(0, 0, 1), mats=[olive], depth=0.004, min_dot=0.6)
    # roof: band labels by each bulkhead
    rf = DecalCanvas(0.380, 0.380, ppm=1800)
    for k, (zl, ang, L, tilt, alen) in enumerate(_jx90_arms()):
        bang = ang + 22.5
        p = _mast_point(0, bang, (0.118 if k < 4 else 0.150) + 0.030)
        rf.text(0.190 - p[0], 0.190 + p[1], f"B{k + 1}", 0.0080, fnt="label-black", color=sand, alpha=0.9)
    b.decal(rf, center=(0.0, 0.0, H_ROOF), normal=(0, 0, 1), up=(0, -1, 0), mats=[olive], depth=0.004, min_dot=0.6)
