"""
FX-280 FIELD - compact waterproof field handheld (PROPS_BRIEF section 2, SPEC section 9).

Models (radio kit): nzr_fieldpro (complete, idle STN screen, medium LOD), nzr_fieldpro_body (no pressable
parts, live screen placeholder) and one nzr_fieldpro_<part> per SPEC 9.2 part id:
    k0..k9 kstar khash kup kdown kmenu kset(-> ok) kband(-> back) kpower(-> power) knob_ch (outer ring)
    knob_vol (inner cap) ptt side1 emerg
Generic labelling only (Rule B): model code FX-280, the word FIELD, WATERPROOF / IP67, a battery label and a
rating label with fictitious identifiers. No NAYZEEE name or mark, no real maker.

Construction (metres, +X = viewer's left, +Y = front, +Z up, origin = grip point 40 % up the body):
    body            60 W x 30 D x 95 H mm
    armour shell    the front 17.8 mm: black rubber armour (sides, top, bottom, a narrow land round the
                    front), front corners chamfered 2.5 mm + filleted, thick moulded rubber corner bumpers
                    on the four top / bottom front corners
    faceplate       a 1.4 mm dark gunmetal (painted die-cast) plate on the front: top print strip
                    ("FX-280" / FIELD, DUAL BAND), the raised screen bezel (STN LCD 44 x 22 mm, 512 x 256,
                    smoked glass), "WATERPROOF · IP67", the arrow column (SCAN, up / down keys), the recessed
                    speaker grille (11 x 8 real holes, 0.9 mm on a 2 mm pitch), the LED light pipe + mic port
                    column and the 4 x 4 keypad wells with orange function legends printed above each key
    top deck        gunmetal deck plate: rubber-duck antenna (11 x 85 mm, yellow band 12 mm below the tip)
                    on a nickel SMA nut, concentric dual knob (outer knurled channel ring 14 mm, inner volume
                    cap 9 mm, white index marks) on a boss with the concentric shafts, red emergency key in a
                    guard ring, rubber MIC/SP jack cover with a moulded pull tab
    left side       rubber pad with the ridged PTT and the MONI key (side1)
    right side      moulded grip ribs, DC-in plug cover, lanyard eye
    back            battery pack behind a 0.6 mm seam: moulded IP67 badge, battery label, belt clip, ribbed
                    release latch; charging contacts underneath, rating label under the shell
Texture layers: main (1024: knobs, keys, antenna, clip, small bits), face (1024: faceplate + deck plate, every
fine print) and side (1024: the rubber armour walls and the battery pack). A hand-built medium LOD (stand-ins
flagged 'm', the detailed geometry flagged 'h') is used from 6 m.
"""
from __future__ import annotations

import math
from types import SimpleNamespace

import numpy as np

from nzprops import (DecalCanvas, Geo, box, cylinder, extrude, lathe, polyline_fillet, quad, rr_lathe, rrect, split_by_normal, sweep,
                     vec, well_plate)
from nzprops.mesh import Chart, ensure_ccw, offset_poly, subdivide_poly

from .common import align, rating_plate, screw
from .radio_common import (INK, charging_contacts, ink, key, key_cap, lanyard_eye, latch_tab, m_mesh, m_print_dark,
                           m_smoked_glass, m_soft_black, ptt, sma_nut)
from .radio_kit import radio

# ---------------------------------------------------------------------------------------------
# dimensions
# ---------------------------------------------------------------------------------------------
W, D, H = 0.060, 0.030, 0.095          # body without knobs / antenna
Z0 = -0.4 * H                          # bottom (-0.038): origin = grip point 40 % up
ZT = Z0 + H                            # top (+0.057)
FY, BY = D / 2, -D / 2                 # front (faceplate top) / back
FP_T = 0.0014                          # faceplate thickness
FS = FY - FP_T + 0.0002                # front face of the armour shell (faceplate stands on it)
DF = 0.0178                            # armour shell depth
YS = FS - DF                           # shell back (-0.004)
SEAM = 0.0006                          # shell / battery gap
YB = YS - SEAM                         # battery front
DB = YB - BY                           # battery depth (10.4 mm)
CHAMF, FIL = 0.0025, 0.0012            # vertical front corners
FLOOR = 0.00004                        # well floors float this far above the shell surface
SX = W / 2                             # side walls

# faceplate (world X / Z; plate-local x = world -X)
FPW, FPZ0, FPZ1 = 0.051, Z0 + 0.0030, ZT - 0.0030
FPZC = (FPZ0 + FPZ1) / 2
FPR = 0.0048                           # plate corner radius
STRIP_Z = 0.0509                       # model print strip
SCR_Z = 0.0356                         # screen centre
VIEW = (0.044, 0.022)                  # visible LCD (layout screen.size)
BEZEL = 0.0010                         # black bezel round the visible LCD
LIP_W, LIP_H = 0.0011, 0.0007          # raised lip round the window
WP_Z = 0.0207                          # "WATERPROOF · IP67"
GRILLE = (-0.0020, 0.0109, 0.0230, 0.0166)   # opening centre X, Z, width, height
G_COLS, G_ROWS, G_PITCH, G_R = 11, 8, 0.0020, 0.00045
G_T = 0.0009                           # grille insert thickness
ARR_X = 0.0175                         # arrow column (viewer's left)
ARR = (0.0075, 0.0050)                 # arrow key caps
ARR_Z = (0.01295, 0.00605)             # kup, kdown centres
SCAN_Z = 0.0176
RCOL_X = -0.0195                       # mic column (viewer's right)
MIC_Z = 0.0122
KEY = (0.009, 0.006)                   # keypad caps
KEY_T = 0.0025
KGAP = 0.00045
KP_PITCH = (0.0124, 0.0088)
KP_ROW0 = -0.00335                     # first row centre
KP_COLS = (0.0186, 0.0062, -0.0062, -0.0186)   # X of the four columns (viewer's left first)

# top deck (world X / Y)
DECK_T = 0.0012
DK_Y0, DK_Y1, DK_W = YS + 0.0008, FS - 0.0015, 0.0490
DK_YC = (DK_Y0 + DK_Y1) / 2
ANT_XY = (0.0175, DK_YC)
KNOB_XY = (-0.0160, DK_YC)
EM_XY = (-0.0022, 0.0075)              # emergency key (front centre)
LED_XY = (0.0068, 0.0092)              # light pipe (front, left of centre) - the LED inserts face +Z
JACK_XY = (0.0045, 0.0000)             # MIC/SP cover (crosswise at the back)
EM_D = 0.0050
ZDK = ZT + DECK_T                      # deck plate top
BOSS_D, BOSS_H = 0.0150, 0.0010
KO_D, KO_H = 0.0140, 0.0070            # outer channel ring
KI_D, KI_H = 0.0090, 0.0060            # inner volume cap (height above the ring)
NUT_H = 0.0030

# sides
SIDE_YC = (YS + FS - CHAMF) / 2        # centre of the flat side walls of the shell
PTT_L, PTT_W, PTT_T = 0.0250, 0.0100, 0.0026
PTT_Z = 0.0225
S1_D, S1_Z = 0.0064, 0.0010
LPAD = (0.0136, -0.0090, 0.0400)       # width (Y), bottom, top of the left rubber pad

# back
CLIP_TOP, CLIP_LEN = 0.0450, 0.0360

# bumpers
BUMP_E, BUMP_A, BUMP_B, BUMP_H = 0.0008, 0.0050, 0.0072, 0.0140

PART_TEX = 2.0                         # texel multiplier of every pressable part (see fieldpro())


# ---------------------------------------------------------------------------------------------
# module-local geometry helpers
# ---------------------------------------------------------------------------------------------
def _fillet_var(poly, radii, n=4):
    """fillet_poly with one radius per corner (0 keeps the corner)."""
    p = np.asarray(poly, np.float64)
    m = len(p)
    out = []
    for i in range(m):
        a, b, c = p[i - 1], p[i], p[(i + 1) % m]
        r = radii[i]
        d1, d2 = a - b, c - b
        l1, l2 = float(np.linalg.norm(d1)), float(np.linalg.norm(d2))
        if r <= 0 or l1 < 1e-12 or l2 < 1e-12:
            out.append(b)
            continue
        d1, d2 = d1 / l1, d2 / l2
        ang = math.acos(float(np.clip(np.dot(d1, d2), -1, 1)))
        if ang > math.pi - 1e-4:
            out.append(b)
            continue
        t = min(r / math.tan(ang / 2), l1 * 0.5, l2 * 0.5)
        rr = t * math.tan(ang / 2)
        p1, p2 = b + d1 * t, b + d2 * t
        bis = (d1 + d2) / max(float(np.linalg.norm(d1 + d2)), 1e-12)
        ctr = b + bis * (rr / math.sin(ang / 2))
        a0 = math.atan2(p1[1] - ctr[1], p1[0] - ctr[0])
        a1 = math.atan2(p2[1] - ctr[1], p2[0] - ctr[0])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(n + 1):
            out.append(ctr + rr * np.array([math.cos(a0 + da * k / n), math.sin(a0 + da * k / n)]))
    res = [out[0]]
    for q in out[1:]:
        if np.linalg.norm(q - res[-1]) > 1e-9:
            res.append(q)
    if np.linalg.norm(res[0] - res[-1]) < 1e-9:
        res.pop()
    return np.asarray(res)


def _outline(w, d, cf, cb, rf, rb, n=4):
    """CCW plan outline w (X) x d (Y): front (+Y) corners chamfered cf + filleted rf, back corners cb / rb."""
    pts, rad = [], []
    for sx, sy, horiz in ((1, -1, True), (1, 1, False), (-1, 1, True), (-1, -1, False)):
        c, r = (cf, rf) if sy > 0 else (cb, rb)
        if c > 1e-9:
            a = (sx * (w / 2 - c), sy * d / 2)
            b = (sx * w / 2, sy * (d / 2 - c))
            pts += [a, b] if horiz else [b, a]
            rad += [r, r]
        else:
            pts.append((sx * w / 2, sy * d / 2))
            rad.append(r)
    return _fillet_var(pts, rad, n)


def _clip_convex(poly, clip):
    """Sutherland-Hodgman: polygon clipped by a convex CCW polygon."""
    out = [np.asarray(p, np.float64) for p in poly]
    m = len(clip)
    for i in range(m):
        if not out:
            break
        a, b = clip[i], clip[(i + 1) % m]
        e = b - a
        inp, out = out, []
        sides = [e[0] * (p[1] - a[1]) - e[1] * (p[0] - a[0]) for p in inp]
        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            sp, sq = sides[j], sides[(j + 1) % len(inp)]
            if sp >= 0:
                out.append(p)
            if (sp >= 0) != (sq >= 0):
                out.append(p + (q - p) * (sp / (sp - sq)))
    return out


def _clip_half(poly, nx, ny, c):
    """Keep the part of a CCW polygon where nx * x + ny * y >= c."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        da, db = nx * a[0] + ny * a[1] - c, nx * b[0] + ny * b[1] - c
        if da >= 0:
            out.append(tuple(a))
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def holed_plate(outline, t, holes, mat, depth=None, wall_mat=None, floor_mats=None, bevel=0.0004, hole_bevel=0.0003, corner_n=5,
                tag="plate", floor=True):
    """well_plate() with any CONVEX outline instead of a square one: the openings fall into wells (top
    chamfer, inward walls, a floor per hole - floor_mats[i] picks each floor's material). Built on z = 0 .. t
    facing +Z, outline centred."""
    ol = ensure_ccw(np.asarray(outline, np.float64))
    bw = 2 * float(np.abs(ol[:, 0]).max()) + 0.004
    bh = 2 * float(np.abs(ol[:, 1]).max()) + 0.004
    g = well_plate(bw, bh, t, holes, mat, depth=depth, wall_mat=wall_mat or mat, floor_mat=wall_mat or mat, bevel=0.0,
                   hole_bevel=hole_bevel, corner_n=corner_n, tag=tag, floor=floor)
    bv = float(min(bevel, t * 0.45))
    inner = offset_poly(ol, bv)
    out = Geo()
    k_floor = 0
    for c in g.charts:
        if c.tag.startswith(tag + ":rim"):
            continue
        if c.tag == tag + ":floor":
            if floor_mats is not None and k_floor < len(floor_mats) and floor_mats[k_floor]:
                c.mat = floor_mats[k_floor]
            k_floor += 1
        if c.tag != tag + ":top":
            out.charts.append(c)
            continue
        P2, tri = [], []
        for tr in c.tri:
            pts = c.pos[tr][:, :2]
            poly = _clip_convex(list(pts), inner)
            if len(poly) < 3:
                continue
            base = len(P2)
            P2 += poly
            tri += [(base, base + k, base + k + 1) for k in range(1, len(poly) - 1)]
        P2 = np.asarray(P2)
        P = np.concatenate([P2, np.full((len(P2), 1), t)], axis=1)
        N = np.tile(vec(0, 0, 1), (len(P), 1))
        UV = np.stack([P[:, 0], -P[:, 1]], axis=1)
        out.charts.append(Chart(P, N, UV, np.asarray(tri), c.mat, c.density, tag + ":top").clean())
    rim = extrude(ol, t, mat, bevel=bv, bevel_seg=2, caps=(False, True), smooth_angle=50, tag=tag + ":rim")
    rim.charts = [c for c in rim.charts if not c.tag.endswith(":top")]
    out += rim
    return out


def rr_ring(w, h, cr, ring_w, t, mat, bevel=0.0005, tag="lip", n=5):
    """Raised rounded-rectangle ring standing on z = 0 facing +Z: outer w x h (corner cr), ring_w wide, t
    tall, rounded top edges (outer wall up, over the top, inner wall down)."""
    bv = min(bevel, t * 0.45, ring_w * 0.3)
    prof = [(0.0, 0.0), (0.0, t - bv)]
    prof += [(bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 3)]
    prof += [(ring_w - bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(math.pi / 2, 0.3, 3)]
    prof += [(ring_w, t - bv), (ring_w, 0.0)]
    return rr_lathe(w, h, cr, prof, mat, n=n, tag=tag)


def ring(mat, d_in, d_out, h, segs=24, bevel=0.0005, tag="ring"):
    """Raised round ring (guard ring, seat) standing on z = 0 facing +Z with a soft rounded top. The profile
    runs outer wall up -> over the top -> inner wall down (lathe(): the outside on the right-hand side)."""
    ri, ro = d_in / 2, d_out / 2
    bv = min(bevel, h * 0.45, (ro - ri) * 0.3)
    prof = [(ro, 0.0), (ro, h - bv), (ro - bv, h), (ri + bv, h), (ri, h - bv), (ri, -0.0002)]
    return lathe(prof, mat, segs=segs, smooth_angle=50, tag=tag)


def fx_light_pipe(r, at, d=0.0030, bezel_h=0.0004, segs=20):
    """Light-pipe socket on the deck (facing +Z), module-local instead of radio_common.light_pipe() (written
    while that one's bezel profile was still inside out; this one adds the lens dome): a raised dark bezel ring - outer wall up,
    over the top, inner wall down - and a clear dark lens dome rising flush with the bezel top, so the
    socket reads as a lens and not as a hole when no LED insert sits on it. Returns (Geo, insert point,
    lens material); the insert point (layout leds.tx / rx) is 0.2 mm under the deck surface as before, and
    the lit nzr_led_* dome (r 1.5 mm, 1.65 mm tall) encloses this lens."""
    bezel = r.mat("pipe_bezel", color=(16, 17, 19), spec=0.4, gloss=0.55, edge=0.4)
    lens = r.mat("fx_pipe_lens", color=(40, 44, 48), spec=0.72, gloss=0.8, grain=0.01, edge=0.0, ao=0.5, smudge=0.2, scratch=0.05)
    rl = d / 2
    ro = rl + 0.0007
    g = lathe([(ro, 0.0), (ro, bezel_h * 0.5), (ro - 0.0002, bezel_h), (rl + 0.0002, bezel_h), (rl, bezel_h * 0.5), (rl, -0.0004)],
              bezel, segs=segs, smooth_angle=50, tag="pipe")
    prof = [(rl * math.cos(a), bezel_h * math.sin(a)) for a in np.linspace(0.0, math.pi / 2, 4)]
    prof[-1] = (0.0, bezel_h)
    lg = lathe(prof, lens, segs=20, smooth_angle=60, tag="pipe_lens")
    for c in lg.charts:                    # one normal at the pole (per-segment pole normals shade as a starburst)
        c.nrm[np.hypot(c.pos[:, 0], c.pos[:, 1]) < 1e-7] = vec(0, 0, 1)
    lg.set_density(6.0)                    # the reflector ring print needs texels (a 3 mm lens: negligible atlas space)
    g += lg
    return align(g, (0, 0, 1), (0, 1, 0), at), vec(at) - vec(0, 0, 1) * 0.0002, lens


_PLANAR = {"+x": (1, 1, 2), "-x": (1, -1, 2), "+y": (0, -1, 2), "-y": (0, 1, 2), "+z": (0, 1, 1), "-z": (0, -1, 1)}


def _planar_uv(g: Geo):
    """Planar UVs on the dominant plane of each split_by_normal() chart (u = right, v = down from outside)."""
    for c in g.charts:
        k = c.tag[-2:]
        if k not in _PLANAR:
            continue
        a, sa, b = _PLANAR[k]
        c.uvm = np.stack([c.pos[:, a] * sa, -c.pos[:, b]], axis=1)
    return g


def _hide(g: Geo, suffixes, k=0.04):
    """Charts pressed against another moulding get almost no texels."""
    for c in g.charts:
        if any(c.tag.endswith(s) for s in suffixes):
            c.density *= k
    return g


def _set_mat(g: Geo, mat, suffixes):
    for c in g.charts:
        if any(c.tag.endswith(s) for s in suffixes):
            c.mat = mat
    return g


def _front(g: Geo, at_z, y=FS):
    """Plate-local (x = viewer's right = world -X, y = up, z = out) -> world on the shell front at height at_z."""
    return align(g, (0, 1, 0), (0, 0, 1), (0.0, y, at_z))


def _flute_outline(R, rd, ribs, phase, land=3):
    """Plan outline of a fluted knob: `ribs` V-bottomed grooves `rd` deep, flat lands between them (a land
    centred on `phase`, so the index faces the front)."""
    per = 2 * math.pi / ribs
    gb, gw = per * 0.07, per * 0.21
    pts = []
    for k in range(ribs):
        a0 = phase + per / 2 + k * per
        pts.append((R - rd, a0 - gb))
        pts.append((R - rd, a0 + gb))
        for j in range(land):
            pts.append((R, a0 + gw + (per - 2 * gw) * j / max(land - 1, 1)))
    return np.array([(rr * math.cos(a), rr * math.sin(a)) for rr, a in pts])


def grille_plate(w, h, t, cols, rows, pitch, r, mat, rim_bevel=0.0003, tag="grille"):
    """Perforated speaker plate standing on z = 0 .. t facing +Z (centred): a cols x rows matrix of real
    octagonal holes (radius r) on a square pitch. Each hole cell is 12 triangles (octagon in a square, no
    walls): the plate stands on the dark acoustic mesh, so the holes read as dark recessed discs with real
    parallax. The outer rim is a rounded wall."""
    gw, gh = cols * pitch, rows * pitch
    P, T = [], []

    def v(x, y):
        P.append((x, y, t))
        return len(P) - 1

    oct_a = [math.radians(22.5 + 45 * k) for k in range(8)]
    for j in range(rows):
        for i in range(cols):
            cx = (i - (cols - 1) / 2) * pitch
            cy = ((rows - 1) / 2 - j) * pitch
            hp = pitch / 2
            o = [v(cx + r * math.cos(a), cy + r * math.sin(a)) for a in oct_a]
            sq = [v(cx + hp, cy + hp), v(cx - hp, cy + hp), v(cx - hp, cy - hp), v(cx + hp, cy - hp)]   # 45, 135, 225, 315
            for k in range(4):
                a0, a1 = o[2 * k], o[2 * k + 1]            # 22.5 + 90k, 67.5 + 90k -> corner 45 + 90k
                T.append((a0, sq[k], a1))
                b0, b1 = o[2 * k + 1], o[(2 * k + 2) % 8]  # flat edge between corners k and k + 1
                T.append((b0, sq[k], sq[(k + 1) % 4]))
                T.append((b0, sq[(k + 1) % 4], b1))
    # border round the hole array up to the plate outline (inset by the rim bevel)
    X0, X1, Y0, Y1 = -w / 2 + rim_bevel, w / 2 - rim_bevel, -h / 2 + rim_bevel, h / 2 - rim_bevel
    ax0, ax1, ay0, ay1 = -gw / 2, gw / 2, -gh / 2, gh / 2
    for (x0, y0, x1, y1) in ((X0, ay1, X1, Y1), (X0, Y0, X1, ay0), (X0, ay0, ax0, ay1), (ax1, ay0, X1, ay1)):
        if x1 - x0 < 1e-7 or y1 - y0 < 1e-7:
            continue
        a, b_, c, d = v(x0, y0), v(x1, y0), v(x1, y1), v(x0, y1)
        T += [(a, b_, c), (a, c, d)]
    P = np.asarray(P, np.float64)
    N = np.tile(vec(0, 0, 1), (len(P), 1))
    UV = np.stack([P[:, 0], -P[:, 1]], axis=1)
    g = Geo([Chart(P, N, UV, np.asarray(T), mat, 1.0, tag + ":top").clean()])
    rim = extrude(rrect(w, h, 0.0, 1), t, mat, bevel=rim_bevel, bevel_seg=2, caps=(False, True), smooth_angle=50, tag=tag + ":rim")
    rim.charts = [c for c in rim.charts if not c.tag.endswith(":top")]
    return g + rim


def drop_icon(dc, cx, cy, s, **ik):
    """Water drop (s = height): a disc with a pointed top."""
    rr = s * 0.32
    yc = cy + s / 2 - rr
    dc.circle(cx, yc, rr, **ik)
    dc.polygon([(cx, cy - s / 2), (cx + rr * 0.94, yc - rr * 0.34), (cx - rr * 0.94, yc - rr * 0.34)], **ik)


def fx_key(r, pid, at, normal, up, size, t, mat, corner, dome, bevel, canvas, depth, shape=None, n=3):
    """radio_common.key() with fewer corner steps (the 16 keypad caps share the triangle budget)."""
    w, h = size
    nrm = vec(normal) / np.linalg.norm(vec(normal))
    upv = vec(up) - nrm * float(np.dot(vec(up), nrm))
    upv = upv / np.linalg.norm(upv)
    right = np.cross(upv, nrm)
    origin = vec(at) + nrm * (t + dome)
    shape = shape or ("round" if corner >= min(w, h) / 2 - 1e-6 else "rect")
    with r.part(pid, origin=origin, press=-nrm, depth=depth, u=right * w / 2, v=upv * h / 2, shape=shape):
        r.add(align(key_cap(mat, w, h, t, corner, dome, bevel, n=n), nrm, upv, at))
        if canvas is not None:
            r.decal(canvas, center=origin, normal=nrm, up=upv, depth=dome + 0.0012, min_dot=0.55)
    return origin


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def _mats(r):
    soft = m_soft_black(r)
    # rubber armour: matte black TPE with a fine moulded texture, lighter where edges are rubbed
    # (ao=0.3 on every large black rubber / polymer surface: the AO grid of this 200 mm tall prop is 1.8 mm, its steps
    # showed as a blocky checker on the flat armour, bumpers and battery; crevices still darken through cavity)
    armour = r.mat("fx_armour", color=(25, 26, 28), spec=0.11, gloss=0.21, bump="rubber", bump_amp=0.000045, bump_scale=0.00055,
                   grain=0.045, grain_scale=0.03, edge=0.4, dirt=0.24, wear_color=(70, 72, 76), cavity=0.75, ao=0.3, layer="side")
    armour_m = r.mat("fx_armour_m", color=(25, 26, 28), spec=0.11, gloss=0.21, bump="rubber", bump_amp=0.000045, bump_scale=0.00055,
                     grain=0.045, grain_scale=0.03, edge=0.4, dirt=0.24, wear_color=(70, 72, 76), cavity=0.75, ao=0.3)
    # dark gunmetal faceplate / deck plate: painted die-cast, satin, bright metal where the edges are worn
    gun = r.mat("fx_gunmetal", color=(70, 73, 79), spec=0.5, gloss=0.5, metal=0.6, bump="orange_peel", bump_amp=0.000010,
                bump_scale=0.0007, grain=0.045, grain_scale=0.02, edge=0.7, wear=0.4, wear_color=(146, 148, 152), dirt=0.18,
                scratch=0.25, smudge=0.3, cavity=0.85, layer="face")
    well = r.mat("fx_well", color=(30, 31, 34), spec=0.16, gloss=0.3, bump="rubber", bump_amp=0.00002, bump_scale=0.0004,
                 grain=0.02, edge=0.15, ao=1.0, cavity=0.8, layer="face")
    # perforated grille plate: a mid-dark painted grey so the black holes read against it
    grille = r.mat("fx_grille", color=(58, 61, 66), spec=0.35, gloss=0.40, bump="stipple", bump_amp=0.00002, bump_scale=0.00035,
                   grain=0.03, edge=0.6, dirt=0.18, wear_color=(120, 123, 128), cavity=0.9, layer="face")
    # battery pack: hard glass-filled polymer, a touch glossier than the armour
    batt = r.mat("fx_battery", color=(28, 29, 32), spec=0.2, gloss=0.32, bump="stipple", bump_amp=0.00003, bump_scale=0.00045,
                 grain=0.03, grain_scale=0.03, edge=0.5, dirt=0.12, wear_color=(74, 76, 80), cavity=0.6, ao=0.3, layer="side")
    # silicone keypad: smooth satin moulding, no chipped edges (rubber does not wear bright like paint)
    keys = r.mat("fx_key_rubber", color=(25, 26, 29), spec=0.16, gloss=0.28, bump="stipple", bump_amp=0.000006, bump_scale=0.00032,
                 grain=0.008, grain_scale=0.02, edge=0.0, dirt=0.05, cavity=0.5, smudge=0.1, scratch=0.02)
    # emergency cap: glossy red moulding, a fine stipple on the side wall, the dimpled grip only on the top (cap:top chart)
    red = r.mat("fx_emerg_red", color=(206, 34, 30), spec=0.34, gloss=0.48, bump="stipple", bump_amp=0.000012, bump_scale=0.00035,
                grain=0.03, edge=0.4, dirt=0.12, wear_color=(240, 120, 110))
    red_top = r.mat("fx_emerg_red_top", color=(206, 34, 30), spec=0.34, gloss=0.48, bump="dimple", bump_amp=0.000022, bump_scale=0.00042,
                    grain=0.03, edge=0.4, dirt=0.12, wear_color=(240, 120, 110))
    shaft = r.mat("fx_shaft", color=(150, 152, 156), spec=0.7, gloss=0.55, metal=1.0, bump="brushed", bump_amp=0.000005,
                  bump_scale=0.0003, edge=0.3, dirt=0.1)
    brass = r.mat("fx_sleeve", color=(176, 146, 86), spec=0.7, gloss=0.55, metal=1.0, bump="brushed", bump_amp=0.000005,
                  bump_scale=0.0003, edge=0.3, dirt=0.15)
    plug = r.mat("fx_plug_rubber", color=(30, 31, 34), spec=0.16, gloss=0.28, bump="rubber", bump_amp=0.00003, bump_scale=0.0004,
                 grain=0.03, edge=0.45, dirt=0.18, wear_color=(78, 80, 84), ao=0.3)
    return SimpleNamespace(soft=soft, armour=armour, armour_m=armour_m, gun=gun, well=well, grille=grille, batt=batt, keys=keys,
                           red=red, red_top=red_top, shaft=shaft, brass=brass, plug=plug)


# ---------------------------------------------------------------------------------------------
# the radio
# ---------------------------------------------------------------------------------------------
@radio("fieldpro", title="FX-280 field handheld", code="FX-280", layers={"face": 1024, "side": 1024}, part_boost=2.5 / PART_TEX,
       maps={"face": {"n": 1024, "s": 512}, "side": {"n": 1024, "s": 512}},
       doc={"screen": "nzr_scr 512 x 256 (grey-green STN) behind smoked glass, visible LCD 44 x 22 mm (layout screen.size)"})
def fieldpro(r):
    M = _mats(r)
    _shell_and_battery(r, M)
    r.add(_bumpers(r, M))
    _faceplate(r, M)
    _front_prints(r, M)
    _keypad(r, M)
    _keymat_marks(r, M)
    insert = _deck(r, M)
    _deck_screws(r, M)
    _knobs(r, M)
    _armour_details(r, M)
    _antenna(r, M)
    _left_side(r, M)
    _right_side(r, M)
    _back_and_bottom(r, M)
    # part charts carry PART_TEX x texels: the part models (the raised, clicked view) pack their 256 atlases
    # above the packer's base-density cap; the complete model compensates through part_boost (net 2.5 x)
    for c in r.geo.charts:
        if c.part is not None:
            c.density *= PART_TEX
    _medium(r, M)
    r.anchor(focus=(0.0, FY + 0.0015, 0.0105), camDist=0.28, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422): palm on the battery / belt clip, fingers round the right side, thumb on the left "
                  "PTT; screen faces the camera when raised. Tune with /radiogrip.")


# ---------------------------------------------------------------------------------------------
# housing: armour shell, battery pack, corner bumpers
# ---------------------------------------------------------------------------------------------
def _shell_and_battery(r, M):
    ol = subdivide_poly(_outline(W, DF, CHAMF, 0.0, FIL, 0.0006, n=4), 0.004)
    g = extrude(ol, ZT - Z0, M.armour, bevel=0.0014, bevel_seg=3, z0=Z0, smooth_angle=50, tag="shell")
    g.translate(0, FS - DF / 2, 0)
    # cap_dot: the rim bevels stay with their side wall; split by the dominant axis alone, the two triangles of a
    # twisted bevel quad alternated between the wall and the cap chart (a sawtooth / carbon-weave checker of
    # gutter-filled texels along every top and bottom edge)
    g = _planar_uv(split_by_normal(g, cap_dot=0.92))
    _hide(g, (":-y",))                     # back face against the battery
    _hide(g, (":+y",), 0.8)                # front face: the narrow land round the faceplate (seen in the raised view)
    for c in g.charts:
        if c.tag == "shell:bot:-z":
            c.density *= 1.4               # the rating label's fine print
    r.add(g)
    ins = 0.0004
    ob = _outline(W - 2 * ins, DB, 0.0, CHAMF - ins, 0.0006, FIL, n=4)
    bt = extrude(ob, ZT - Z0 - 2 * ins, M.batt, bevel=0.0012, bevel_seg=3, z0=Z0 + ins, smooth_angle=50, tag="battery")
    bt.translate(0, BY + DB / 2, 0)
    bt = _planar_uv(split_by_normal(bt, cap_dot=0.92))
    _hide(bt, (":+y",))
    for c in bt.charts:
        if c.tag.endswith(":-y"):
            c.density *= 1.35              # the labelled back
    r.add(bt)
    # moulded finger grooves round the battery sides (shallow, geometry catches the light)
    for sx in (1, -1):
        for k in range(4):
            z = Z0 + 0.0095 + k * 0.0036
            rib = box((0.0008, DB - 0.0058, 0.0013), M.batt, r=0.00038, seg=1, center=(sx * (W / 2 - ins + 0.0003), BY + DB / 2 + 0.0002, z),
                      faces="+x -x +y -y +z -z", tag="bat_rib")
            r.hi_only(rib)


def _bumpers(r, M, n=3, bevel_seg=2, mat=None, tag="bumper"):
    """Moulded rubber corner bumpers over the four front corners (top and bottom) of the armour shell: the shell
    outline grown by BUMP_E, clipped to one corner quadrant, BUMP_H tall, rounded all round. Returns the Geo."""
    e = BUMP_E
    mat = mat or M.armour
    out = Geo()
    outline = _outline(W + 2 * e, DF + 2 * e, CHAMF + e * 0.4, 0.0, FIL + e, 0.0, n=n)
    yc = FS - DF / 2
    for sx in (1, -1):
        for top in (True, False):
            poly = [tuple(p) for p in outline]
            poly = _clip_half(poly, sx, 0.0, W / 2 + e - BUMP_A)
            poly = _clip_half(poly, 0.0, 1.0, DF / 2 + e - BUMP_B)
            # round only the corners the clip made (new points); the outline arcs are already round
            orig = [tuple(np.round(p, 9)) for p in outline]
            rad = [0.0 if tuple(np.round(p, 9)) in orig else 0.0010 for p in poly]
            poly = _fillet_var(np.asarray(poly), rad, max(1, n - 1))
            z0 = ZT + e - BUMP_H if top else Z0 - e
            g = extrude(poly, BUMP_H, mat, bevel=0.0012, bevel_seg=bevel_seg, z0=z0, smooth_angle=50, tag=tag)
            g.translate(0, yc, 0)
            g = _planar_uv(split_by_normal(g, cap_dot=0.92))
            # the inner ends are small steps against the shell - few texels
            _hide(g, (":-y",), 0.3)
            out += g
    return out


# ---------------------------------------------------------------------------------------------
# faceplate: screen window, grille opening, key wells
# ---------------------------------------------------------------------------------------------
def _keypad_cells():
    """(pid, X, Z, legend, sub, fn) of the 4 x 4 keypad, X = viewer's left first."""
    rows = [[("k1", "1", "", "STEP"), ("k2", "2", "ABC", "CODE"), ("k3", "3", "DEF", "SQL"), ("kband", "BAND", None, "MODE")],
            [("k4", "4", "GHI", "MW"), ("k5", "5", "JKL", "ATT"), ("k6", "6", "MNO", "DW"), ("kmenu", "MENU", None, "INFO")],
            [("k7", "7", "PQRS", "LOCK"), ("k8", "8", "TUV", "PRI"), ("k9", "9", "WXYZ", "V/M"), ("kset", "SET", None, "REV")],
            [("kstar", "*", None, "SCN"), ("k0", "0", "", "ENT"), ("khash", "#", None, "HM"), ("kpower", None, None, "LAMP")]]
    out = []
    for ri, row in enumerate(rows):
        for ci, (pid, lg, sub, fn) in enumerate(row):
            out.append((pid, KP_COLS[ci], KP_ROW0 - ri * KP_PITCH[1], lg, sub, fn))
    return out


def _window():
    """Screen opening (half extents) and the lip ring outer size."""
    ow, oh = VIEW[0] + 2 * BEZEL, VIEW[1] + 2 * BEZEL
    hb = 0.00028
    lw, lh = ow + 2 * (hb + LIP_W), oh + 2 * (hb + LIP_W)
    return ow, oh, hb, lw, lh


def _plate_holes(M, mesh, bezel_black, keys=True):
    holes, fl = [], []

    def hole(X, Z, hw, hh, rad, floor, n=None, depth=None):
        holes.append((-X, Z - FPZC, hw, hh, rad, depth) + ((n,) if n else ()))
        fl.append(floor)

    ow, oh, _, _, _ = _window()
    hole(0.0, SCR_Z, ow / 2, oh / 2, 0.0012, bezel_black)
    gx, gz, gw, gh = GRILLE
    hole(gx, gz, gw / 2, gh / 2, 0.0018, mesh)
    hole(RCOL_X, MIC_Z, 0.0007, 0.0007, 0.0007, mesh, n=3)                            # mic port
    if keys:
        for z in ARR_Z:
            hole(ARR_X, z, ARR[0] / 2 + KGAP, ARR[1] / 2 + KGAP, ARR[1] * 0.42 + KGAP, M.well, n=3)
        for pid, X, Z, *_ in _keypad_cells():
            hole(X, Z, KEY[0] / 2 + KGAP, KEY[1] / 2 + KGAP, KEY[1] * 0.3 + KGAP, M.well, n=3)
    return holes, fl


def _faceplate(r, M):
    mesh = m_mesh(r)
    bezel_black = m_print_dark(r)
    holes, fl = _plate_holes(M, mesh, bezel_black)
    outline = rrect(FPW, FPZ1 - FPZ0, FPR, 6)
    g = holed_plate(outline, FP_T, holes, M.gun, depth=FP_T - FLOOR, wall_mat=M.gun, floor_mats=fl, bevel=0.0005, hole_bevel=0.00028,
                    corner_n=4, tag="face")
    # well floors sit under the keys (and in shadow on the body model) - give their texels to the printed plate
    for c in g.charts:
        if c.tag.endswith(":floor"):
            c.density *= 0.4
        elif c.tag.endswith(":well"):
            c.density *= 0.7
    r.add(_front(g, FPZC))
    # raised lip round the screen window (the "raised bezel")
    ow, oh, hb, lw, lh = _window()
    lip = rr_ring(lw, lh, 0.0012 + hb + LIP_W, LIP_W, LIP_H, M.gun, bevel=0.00045, tag="lip", n=5)
    r.add(_front(lip, SCR_Z, y=FS + FP_T - 0.00005))
    # screen (fixed UV, layout anchor) on the bezel floor + smoked glass 0.3 mm above it
    yf = FS + FLOOR
    r.screen(quad((0.0, yf + 0.00006, SCR_Z), (-1, 0, 0), (0, 0, 1), VIEW[0], VIEW[1], "x", fixed_uv=True))
    glass = m_smoked_glass(r)
    r.add(quad((0.0, yf + 0.00036, SCR_Z), (-1, 0, 0), (0, 0, 1), ow - 0.0002, oh - 0.0002, glass, tag="glass"))
    sh = DecalCanvas(ow, oh, ppm=6000)
    sh.polygon([(ow * 0.10, oh), (ow * 0.30, oh), (ow * 0.52, 0.0), (ow * 0.32, 0.0)], color=(190, 196, 204), alpha=0.07, blur=0.0016)
    sh.polygon([(ow * 0.34, oh), (ow * 0.37, oh), (ow * 0.59, 0.0), (ow * 0.56, 0.0)], color=(200, 206, 214), alpha=0.06, blur=0.0005)
    r.decal(sh, center=(0.0, yf + 0.00036, SCR_Z), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0003, mats=[glass])
    # speaker grille insert: a perforated plate (real holes falling into the dark acoustic mesh) sitting 0.45 mm
    # below the faceplate in its opening
    gx, gz, gw, gh = GRILLE
    gp = grille_plate(gw - 0.0004, gh - 0.0004, G_T, G_COLS, G_ROWS, G_PITCH, G_R, M.grille)
    r.add(align(gp, (0, 1, 0), (0, 0, 1), (gx, FS + FLOOR + 0.00002, gz)))
    # a soft rolled lip round every hole (normal map + a darker rim)
    pf = DecalCanvas(gw, gh, ppm=40000)
    pf.perforate((gw - (G_COLS - 1) * G_PITCH) / 2, (gh - (G_ROWS - 1) * G_PITCH) / 2, G_COLS, G_ROWS, G_PITCH, G_R + 0.00014,
                 depth=0.00012, color=(12, 13, 14))
    r.decal(pf, center=(gx, FS + FLOOR + G_T, gz), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0006, mats=[M.grille])


def _front_prints(r, M):
    """Prints on the faceplate (face atlas): model code strip, waterproof line, SCAN, column marks."""
    ytop = FY + 0.0002
    # top-left: "FX-280" bold white with FIELD in orange under a thin orange rule
    dc = DecalCanvas(0.030, 0.0046, ppm=40000)
    dc.text(0.0, 0.0019, "FX-280", 0.0030, fnt="label-black", anchor="lm", spacing=0.00012, **ink("white"))
    tw = dc.text_width("FX-280", 0.0030, "label-black", 0.00012)
    dc.rect(tw + 0.0012, 0.00045, 0.00028, 0.0029, **ink("orange"))
    dc.text(tw + 0.0021, 0.0019, "FIELD", 0.0016, fnt="label-semi", anchor="lm", spacing=0.00022, **ink("orange"))
    r.decal(dc, center=(0.0225 - 0.015, ytop, STRIP_Z + 0.0001), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])
    # top-right: band word
    db = DecalCanvas(0.016, 0.003, ppm=40000)
    db.text(0.016, 0.0015, "DUAL BAND", 0.0012, fnt="label-semi", anchor="rm", spacing=0.00018, **ink("grey"))
    r.decal(db, center=(-0.0225 + 0.008, ytop, STRIP_Z + 0.0002), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])
    # under the LCD: WATERPROOF · IP67 with a drop icon
    wp = DecalCanvas(0.036, 0.0030, ppm=40000)
    s = 0.00145
    t1, t2 = "WATERPROOF", "IP67"
    w1 = wp.text_width(t1, s, "label", 0.00022)
    w2 = wp.text_width(t2, s, "label", 0.00022)
    gap = 0.0026
    total = 0.0022 + 0.0008 + w1 + gap + w2
    x = (0.036 - total) / 2
    drop_icon(wp, x + 0.0009, 0.0015, 0.0021, **ink("orange"))
    x += 0.0030
    wp.text(x, 0.0015, t1, s, fnt="label", anchor="lm", spacing=0.00022, **ink("white"))
    x += w1
    wp.circle(x + gap / 2, 0.0015, 0.00032, **ink("orange"))
    wp.text(x + gap, 0.0015, t2, s, fnt="label", anchor="lm", spacing=0.00022, **ink("white"))
    r.decal(wp, center=(0.0, ytop, WP_Z), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])
    # SCAN above the arrow keys (orange, with two tiny chevrons)
    sc = DecalCanvas(0.0100, 0.0022, ppm=40000)
    sc.text(0.005, 0.0011, "SCAN", 0.00125, fnt="label", anchor="mm", spacing=0.00022, **ink("orange"))
    r.decal(sc, center=(ARR_X, ytop, SCAN_Z), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])
    # right column: MIC under the mic port (a moulded ring round it), a VOX hint below
    mc = DecalCanvas(0.0090, 0.0090, ppm=40000)
    mc.circle(0.0045, 0.0026, 0.0017, fill=False, width=0.00024, **ink("grey"))
    mc.text(0.0045, 0.0060, "MIC", 0.00110, fnt="label-semi", anchor="mm", spacing=0.0002, **ink("grey"))
    mc.text(0.0045, 0.0080, "VOX", 0.00085, fnt="label-semi", anchor="mm", spacing=0.00016, **ink("orange"))
    r.decal(mc, center=(RCOL_X, ytop, MIC_Z - 0.0019), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])
    # orange function legends ABOVE each keypad key (one print over the whole keypad)
    KW, KH = 0.050, 0.036
    kz = KP_ROW0 - 1.5 * KP_PITCH[1]
    kp = DecalCanvas(KW, KH, ppm=40000)
    for pid, X, Z, lg, sub, fn in _keypad_cells():
        cx = KW / 2 - X                     # canvas x runs along world -X
        cy = KH / 2 - (Z - kz) - (KEY[1] / 2 + KGAP + 0.00092)
        kp.text(cx, cy, fn, 0.00118, fnt="label", anchor="mm", spacing=0.00012, max_w=KEY[0] * 1.15, **ink("orange"))
    r.decal(kp, center=(0.0, ytop, kz), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.gun])


# ---------------------------------------------------------------------------------------------
# front parts: keypad, arrow keys
# ---------------------------------------------------------------------------------------------
def _digit_legend(w, h, digit, sub):
    """Keypad legend: big digit left of centre, small letters right (white pad print)."""
    dc = DecalCanvas(w, h, ppm=60000)
    if sub:
        dc.text(w * 0.40, h * 0.53, digit, h * 0.58, fnt="label", anchor="rm", **ink("white"))
        dc.text(w * 0.46, h * 0.57, sub, h * 0.24, fnt="label-semi", anchor="lm", max_w=w * 0.48, **ink("white"))
    else:
        dc.text(w * 0.5, h * 0.53 if digit not in "*#" else h * 0.5, digit, h * (0.62 if digit not in "*" else 0.74), fnt="label",
                **ink("white"))
    return dc


def _word_legend(w, h, word):
    dc = DecalCanvas(w, h, ppm=60000)
    dc.text(w / 2, h * 0.52, word, h * 0.40, fnt="label", spacing=h * 0.03, max_w=w * 0.84, **ink("white"))
    return dc


def _keymat_marks(r, M):
    """Contact-dome rings moulded into the keymat at the bottom of every well (body model, keys pulled)."""
    KW, KH = 0.050, 0.044
    kz = KP_ROW0 - 1.5 * KP_PITCH[1] + 0.004
    dc = DecalCanvas(KW, KH, ppm=24000)
    cells = [(X, Z) for _, X, Z, *_ in _keypad_cells()] + [(ARR_X, z) for z in ARR_Z]
    for X, Z in cells:
        cx, cy = KW / 2 - X, KH / 2 - (Z - kz)
        dc.circle(cx, cy, 0.0016, fill=False, width=0.0003, color=(20, 21, 23), height=-0.00008)
        dc.circle(cx, cy, 0.0009, color=(36, 37, 40), height=0.00006, spec=0.3, gloss=0.45)
    r.decal(dc, center=(0.0, FS + FLOOR, kz), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0008, mats=[M.well])


def _keypad(r, M):
    for pid, X, Z, lg, sub, fn in _keypad_cells():
        at = (X, FS + FLOOR, Z)
        cw, ch = KEY[0] * 0.92, KEY[1] * 0.88
        if pid == "kpower":
            cv = DecalCanvas(cw, ch, ppm=60000)
            cv.glyph("power", cw / 2, ch / 2, ch * 0.56, **ink("red"))
        elif lg in ("BAND", "MENU", "SET"):
            cv = _word_legend(cw, ch, lg)
        else:
            cv = _digit_legend(cw, ch, lg, sub)
        fx_key(r, pid, at, (0, 1, 0), (0, 0, 1), size=KEY, t=KEY_T, mat=M.keys, corner=KEY[1] * 0.3, dome=0.00026, bevel=0.0009,
               canvas=cv, depth=0.0014)
    for pid, z, gl in (("kup", ARR_Z[0], "up"), ("kdown", ARR_Z[1], "down")):
        cw, ch = ARR[0] * 0.9, ARR[1] * 0.88
        cv = DecalCanvas(cw, ch, ppm=60000)
        cv.glyph(gl, cw / 2, ch / 2, ch * 0.42, **ink("white"))
        fx_key(r, pid, (ARR_X, FS + FLOOR, z), (0, 1, 0), (0, 0, 1), size=ARR, t=0.0023, mat=M.keys, corner=ARR[1] * 0.42, dome=0.00024,
               bevel=0.0006, canvas=cv, depth=0.0012)


# ---------------------------------------------------------------------------------------------
# top deck: deck plate, emergency key, jack cover
# ---------------------------------------------------------------------------------------------
def _deck(r, M):
    """Deck plate (gunmetal) with the emergency well and the light-pipe socket, the knob boss + concentric
    shafts, the MIC/SP plug cover. Returns the LED insert point (layout leds.tx / rx)."""
    em_d = EM_D
    holes = [(EM_XY[0], EM_XY[1] - DK_YC, em_d / 2 + 0.0005, em_d / 2 + 0.0005, em_d / 2 + 0.0005, None, 6),
             (LED_XY[0], LED_XY[1] - DK_YC, 0.0017, 0.0017, 0.0017, 0.0004, 6)]
    dk = holed_plate(rrect(DK_W, DK_Y1 - DK_Y0, 0.0030, 6), DECK_T, holes, M.gun, depth=DECK_T - FLOOR, wall_mat=M.gun,
                     floor_mats=[M.well, m_print_dark(r)], bevel=0.0005, hole_bevel=0.00025, tag="deck")
    r.add(dk.translate(0, DK_YC, ZT))
    # emergency key: guard ring round the well, red button on the floor
    r.add(ring(M.gun, em_d + 2 * 0.0005 + 0.0007, em_d + 0.0036, 0.0014, segs=28, bevel=0.0005, tag="em_guard")
          .translate(EM_XY[0], EM_XY[1], ZDK - 0.0001))
    # the click face is tilted 20 deg towards the front: the raised camera sees the deck almost edge-on, so a disc
    # flat in the deck plane would project to 1 - 2 px. v stays inside the kit's 20.5 deg tolerance to the press
    # axis and is longer, so the projected target is ~5 x 3 mm on screen (layout u / v only - the cap is level)
    em_t, em_dome = 0.0026, 0.0003
    e_origin = vec(EM_XY[0], EM_XY[1], ZT + FLOOR + em_t + em_dome)
    with r.part("emerg", origin=e_origin, press=(0, 0, -1), depth=0.0012, u=vec(em_d / 2, 0, 0), v=vec(0, 0.0036, 0.0013), shape="round",
                action="emerg"):
        cap = key_cap(M.red, em_d, em_d, em_t, em_d / 2, em_dome, None)
        for c in cap.charts:
            if c.tag.endswith(":top"):
                c.mat = M.red_top              # dimpled grip only on the top, a fine stipple on the side wall
        r.add(cap.translate(EM_XY[0], EM_XY[1], ZT + FLOOR))
    # orange "EMG" pad print behind the guard (reads from the front, like every deck print)
    ep = DecalCanvas(0.0060, 0.0020, ppm=40000)
    ep.text(0.0030, 0.0010, "EMG", 0.00115, fnt="label-semi", anchor="mm", spacing=0.00018, **ink("orange"))
    r.decal(ep, center=(EM_XY[0] - 0.0006, EM_XY[1] - 0.0058, ZDK), normal=(0, 0, 1), up=(0, -1, 0), depth=0.0006, mats=[M.gun])
    # light pipe (faces +Z like every radio's: the shared nzr_led_* inserts attach with zero rotation): bezel ring +
    # a dark clear lens dome flush with the bezel top, a pale reflector ring printed inside the lens
    pipe, insert, lens = fx_light_pipe(r, (LED_XY[0], LED_XY[1], ZDK), d=0.0030)
    r.add(pipe)
    rf = DecalCanvas(0.0030, 0.0030, ppm=60000)
    rf.circle(0.0015, 0.0015, 0.0010, fill=False, width=0.0003, color=(120, 124, 130), spec=0.6, gloss=0.7, blur=0.00004)
    rf.circle(0.0011, 0.0011, 0.00022, color=(150, 154, 160), alpha=0.55, spec=0.9, gloss=0.9, blur=0.00008)    # glint
    r.decal(rf, center=(LED_XY[0], LED_XY[1], ZDK + 0.0004), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0008, mats=[lens])
    # knob boss with the concentric shafts (outer sleeve for the channel ring, inner D-shaft for the volume cap)
    kx, ky = KNOB_XY
    r.add(cylinder(BOSS_D / 2, BOSS_H, M.gun, segs=40, bevel=0.0004, bevel_seg=2, caps=(False, True), tag="boss")
          .translate(kx, ky, ZDK - 0.00005))
    zb = ZDK + BOSS_H
    r.add(lathe([(0.0, 0.0), (0.0042, 0.0), (0.0042, KO_H - 0.0022), (0.0038, KO_H - 0.0018), (0.0, KO_H - 0.0018)], M.brass, segs=24,
                smooth_angle=40, tag="sleeve").translate(kx, ky, zb))
    shaft = lathe([(0.0, KO_H - 0.0018), (0.0021, KO_H - 0.0018), (0.0021, KO_H + 0.0040), (0.0017, KO_H + 0.0044),
                   (0.0, KO_H + 0.0044)], M.shaft, segs=18, smooth_angle=40, tag="shaft")
    lim = 0.0021 - 0.0042 * 0.18
    for c in shaft.charts:
        m = c.pos[:, 1] > lim
        c.pos[m, 1] = lim
        c.nrm[m] = vec(0, 1, 0)
        c.clean()
    r.add(shaft.translate(kx, ky, zb))
    # MIC/SP jack cover: rubber plug cover lying crosswise at the back of the deck, pull tab at its outer (+X) end
    jx, jy = JACK_XY
    jw, jl = 0.0090, 0.0054
    gasket = r.mat("fx_gasket", color=(16, 17, 18), spec=0.06, gloss=0.12, bump="rubber", bump_amp=0.00002, bump_scale=0.0003)
    gk = extrude(rrect(jw + 0.0009, jl + 0.0009, 0.0020, 4), 0.0003, gasket, bevel=0.0001, bevel_seg=1, caps=(False, True), tag="jack_gasket")
    r.add(gk.translate(jx, jy, ZDK - 0.00005))
    t = 0.0016
    cap = extrude(rrect(jw, jl, 0.0018, 4), t, M.plug, bevel=min(t * 0.45, 0.0004), bevel_seg=2, caps=(False, True), smooth_angle=50,
                  tag="jack_cap")
    cap.set_density(2.6)                   # moulded lettering on a 9 mm cover: give it texels
    r.add(cap.translate(jx, jy, ZDK + 0.00025))
    tab = box((0.0034, 0.0030, 0.0011), M.plug, r=0.0005, seg=2, center=(jx + jw / 2 + 0.0008, jy, ZDK + 0.0008), faces="+x -x +y -y +z",
              tag="jack_tab")
    r.add(tab)
    # moulded "MIC/SP" lettering + grip lines at the tab end (raised, a shade lighter); reads from the front
    lab = DecalCanvas(jw, jl, ppm=50000)
    lab.text(jw * 0.585, jl * 0.52, "MIC/SP", jl * 0.235, fnt="label-semi", anchor="mm", spacing=jl * 0.012, max_w=jw * 0.6,
             color=(62, 64, 68), height=0.00006, spec=0.3, gloss=0.42)
    for k in range(3):
        lab.rect(jw * 0.11 + k * jw * 0.045, jl * 0.26, jw * 0.018, jl * 0.48, r=jw * 0.008, height=0.00008)
    r.decal(lab, center=(jx, jy, ZDK + 0.0018), normal=(0, 0, 1), up=(0, -1, 0), depth=0.0012, mats=[M.plug])
    return np.asarray(insert, np.float64)


def _deck_screws(r, M):
    for x, y in ((0.0222, DK_Y0 + 0.0016), (-0.0222, DK_Y0 + 0.0016), (0.0222, DK_Y1 - 0.0016), (-0.0222, DK_Y1 - 0.0016)):
        s = screw(r, (x, y, ZDK - 0.00005), (0, 0, 1), (0, 1, 0), d=0.0022, kind="torx", color=(66, 68, 73), segs=12, spec=0.55, gloss=0.5)
        s.set_density(6.0)                 # the torx recess needs ~36 texels across the head, not 6
        r.hi_only(s)


def _knobs(r, M):
    """Concentric dual knob: knob_ch = outer fluted + knurled ring (14 mm), knob_vol = inner knurled cap (9 mm)
    standing above it; two separate part models on the same axis."""
    kx, ky = KNOB_XY
    base = vec(kx, ky, ZDK + BOSS_H)
    ax, fr, right = vec(0, 0, 1), vec(0, 1, 0), vec(-1, 0, 0)
    # straight knurl between the flutes (a diamond knurl on a fluted flank reads as a woven pattern)
    ring_m = r.mat("fx_knob_ring", color=(31, 32, 35), spec=0.3, gloss=0.4, bump="ribs_u", bump_amp=0.00006, bump_scale=0.00042,
                   grain=0.03, edge=0.7, dirt=0.15, wear_color=(96, 98, 102), cavity=0.8)
    cap_m = r.mat("fx_knob_cap", color=(29, 30, 33), spec=0.28, gloss=0.38, bump="ribs_u", bump_amp=0.00004, bump_scale=0.00030,
                  grain=0.03, edge=0.65, dirt=0.12, wear_color=(92, 94, 98), cavity=0.8)
    # the flat tops, the chamfer bands and the skirt are smooth satin mouldings (knurl only on the flanks)
    top_m = r.mat("fx_knob_top", color=(32, 33, 36), spec=0.36, gloss=0.5, bump="orange_peel", bump_amp=0.000005, bump_scale=0.0005,
                  grain=0.02, grain_scale=0.02, edge=0.55, dirt=0.1, wear_color=(98, 100, 104), cavity=0.8, smudge=0.3)
    Ro = KO_D / 2
    ri = KI_D / 2 + 0.0004
    h = KO_H
    sk, band, bev = 0.0010, 0.0010, 0.0006
    o_origin = base + ax * (h / 2)
    with r.part("knob_ch", origin=o_origin, press=-ax, depth=0.0008, u=right * Ro, v=ax * (h / 2), shape="rect", action="knob",
                value="channel", axis=ax, detents=16):
        Rs = Ro + 0.0004
        g = lathe([(Rs * 0.96, 0.0), (Rs, sk * 0.4), (Rs, sk * 0.7), (Rs - 0.0003, sk), (Ro - 0.0005, sk)], top_m,
                  segs=40, smooth_angle=40, tag="ring_skirt")
        ol = _flute_outline(Ro, 0.00055, 20, math.pi / 2, land=2)
        g += extrude(ol, h - band - sk, ring_m, z0=sk, caps=(False, True), smooth_angle=28, tag="ring_flutes")
        for c in g.charts:
            if c.tag.endswith(":top"):         # only the bore floor shows (under the volume cap): smooth, few texels
                c.mat, c.density = top_m, 0.3
        prof = [(Ro, h - band), (Ro, h - bev)]
        prof += [(Ro - bev + bev * math.cos(a), h - bev + bev * math.sin(a)) for a in np.linspace(math.pi / 4, math.pi / 2, 2)]
        prof += [(ri + 0.0004, h), (ri, h - 0.0004), (ri, h - 0.0020)]
        g += lathe(prof, top_m, segs=40, smooth_angle=40, tag="ring_top")
        r.add(g.translate(*base))
        dc = DecalCanvas(KO_D, KO_D, ppm=40000)
        dc.rect(KO_D / 2 - 0.00028, 0.00015, 0.00056, Ro - ri - 0.0007, r=0.0002, **ink("white"))
        r.decal(dc, center=base + ax * h, normal=ax, up=fr, depth=0.0015, min_dot=0.4)
        side = DecalCanvas(0.0016, h, ppm=40000)
        side.rect(0.0008 - 0.00026, h * 0.22, 0.00052, h * 0.52, r=0.0002, **ink("white"))
        r.decal(side, center=base + ax * (h * 0.5) + fr * Ro, normal=fr, up=ax, depth=0.0008, min_dot=0.6)
    # inner cap: knurled, slightly domed top with a white dot; it rises out of the ring
    hi = KI_H + 0.0018
    i_base = base + ax * (h - 0.0018)
    i_origin = base + ax * (h + KI_H / 2)
    with r.part("knob_vol", origin=i_origin, press=-ax, depth=0.0008, u=right * (KI_D / 2), v=ax * (KI_H / 2), shape="rect",
                action="knob", value="volume", axis=ax, detents=24):
        Ri = KI_D / 2
        ol = _flute_outline(Ri, 0.00028, 28, math.pi / 2, land=2)
        g = extrude(ol, hi - 0.0008, cap_m, z0=0.0, caps=(False, False), smooth_angle=28, tag="cap_flutes")   # the domed top closes it
        bv = 0.0006
        prof = [(Ri, hi - 0.0008), (Ri, hi - bv)]
        prof += [(Ri - bv + bv * math.cos(a), hi - bv + bv * math.sin(a)) for a in np.linspace(math.pi / 6, math.pi / 2, 3)]
        prof += [(Ri * 0.55, hi + 0.00028), (0.0, hi + 0.00035)]
        g += lathe(prof, top_m, segs=40, smooth_angle=50, tag="cap_top")
        r.add(g.translate(*i_base))
        dc = DecalCanvas(KI_D, KI_D, ppm=50000)
        dc.circle(KI_D / 2, KI_D * 0.2, KI_D * 0.075, **ink("white"))
        r.decal(dc, center=i_base + ax * (hi + 0.0003), normal=ax, up=fr, depth=0.0015, min_dot=0.3)


# ---------------------------------------------------------------------------------------------
# antenna
# ---------------------------------------------------------------------------------------------
def _duck_profile():
    """(r, z) mm of the rubber duck above the SMA nut: knurled ferrule, ribbed strain-relief boot, a slightly
    tapering body (11 -> 10.2 mm), the yellow band sleeve 12 mm below the tip, rounded tip."""
    prof = [(0.0, 0.0), (4.3, 0.0), (4.3, 3.2), (4.0, 3.5)]
    prof += [(5.6, 3.6), (5.95, 4.1)]
    for k in range(3):
        z0 = 4.6 + k * 2.9
        prof += [(5.95, z0), (6.25, z0 + 0.35), (6.25, z0 + 1.55), (5.95, z0 + 1.9)]
    prof += [(5.9, 13.6), (5.65, 15.0), (5.5, 17.0)]
    prof += [(5.45, 30.0), (5.35, 50.0), (5.25, 68.2)]
    return prof


def _antenna(r, M):
    ax, ay = ANT_XY
    duck = r.mat("fx_duck_rubber", color=(22, 23, 25), spec=0.17, gloss=0.28, bump="rubber", bump_amp=0.00004, bump_scale=0.0007,
                 grain=0.035, edge=0.35, dirt=0.15, wear_color=(70, 72, 76), cavity=0.7, ao=0.3)
    # straight (axial) knurl on the ferrule: a diagonal knurl on a small cylinder reads as woven carbon
    ferrule = r.mat("fx_ferrule", color=(34, 35, 38), spec=0.5, gloss=0.5, metal=0.8, bump="ribs_u", bump_amp=0.00004, bump_scale=0.0005,
                    edge=0.6, wear_color=(140, 142, 146), dirt=0.1, ao=0.3)
    band = r.mat("fx_duck_band", color=(228, 184, 34), spec=0.3, gloss=0.45, grain=0.025, edge=0.3, dirt=0.25, wear_color=(250, 220, 120))
    # seat ring on the deck plate, then the nickel SMA nut
    r.add(ring(M.gun, 0.0068, 0.0112, 0.0008, segs=28, bevel=0.0003, tag="ant_seat").translate(ax, ay, ZDK - 0.0001))
    nz = ZDK + 0.0007
    nut = sma_nut(r, (ax, ay, nz), across=0.008, h=NUT_H, finish="nickel", barrel_h=0.0004)
    nut.charts = [c for c in nut.charts if not c.tag.startswith("antenna_thread")]     # hidden inside the ferrule
    r.add(nut)
    z0 = nz + NUT_H
    prof = [(a * 0.001, z * 0.001) for a, z in _duck_profile()]
    fer = [p for p in prof[:4]]
    g = lathe(fer, ferrule, segs=20, smooth_angle=50, tag="antenna_ferrule")
    g += lathe(prof[3:], duck, segs=20, smooth_angle=50, tag="antenna_duck")
    # band sleeve 12 mm below the tip (4.6 mm wide), then the top section and the rounded tip
    L = 0.085
    zb1 = L - 0.012
    zb0 = zb1 - 0.0046
    rb0, rb1 = 0.00525, 0.00519
    g += lathe([(0.00525, 0.0682), (0.00523, zb0 - 0.0001)], duck, segs=20, smooth_angle=50, tag="antenna_duck")
    g += lathe([(rb0 - 0.00005, zb0 - 0.0001), (rb0 + 0.00012, zb0 + 0.0001), (rb1 + 0.00012, zb1 - 0.0001), (rb1 - 0.00005, zb1 + 0.0001)],
               band, segs=20, smooth_angle=60, tag="antenna_band")
    tip = [(rb1 - 0.00005, zb1 + 0.0001), (0.00512, L - 0.0050)]
    rt = 0.00512
    for a in np.linspace(0.15, math.pi / 2, 6):
        tip.append((rt * math.cos(a), L - 0.0050 + 0.0046 * math.sin(a)))
    tip[-1] = (0.0, L - 0.0004)
    g += lathe(tip, duck, segs=20, smooth_angle=55, tag="antenna_duck")
    r.add(g.translate(ax, ay, z0))


def _armour_details(r, M):
    """Moulded parting line round the rubber armour (sides, top, bottom) and grip grooves on the bumpers."""
    yp = FS - 0.0064                        # parting line depth
    zc = (Z0 + ZT) / 2
    for sx in (1, -1):
        dc = DecalCanvas(DF + 0.006, H + 0.006, ppm=9000)
        xx = (DF + 0.006) / 2 + (yp - (FS - DF / 2)) * sx
        dc.groove([(xx, 0.0), (xx, H + 0.006)], width=0.00045, depth=0.0002, alpha=0.4)
        r.decal(dc, center=(sx * SX, FS - DF / 2, zc), normal=(sx, 0, 0), up=(0, 0, 1), depth=0.004, mats=[M.armour], min_dot=0.5)
    for sz in (1, -1):
        dc = DecalCanvas(W + 0.006, DF + 0.006, ppm=9000)
        yy = (DF + 0.006) / 2 - (yp - (FS - DF / 2)) * sz
        dc.groove([(0.0, yy), (W + 0.006, yy)], width=0.00045, depth=0.0002, alpha=0.4)
        r.decal(dc, center=(0.0, FS - DF / 2, zc + sz * H / 2), normal=(0, 0, sz), up=(0, sz, 0), depth=0.004, mats=[M.armour], min_dot=0.5)
    # three short grip grooves on the outer face of each bumper
    for sx in (1, -1):
        for top in (True, False):
            zb = ZT + BUMP_E - BUMP_H / 2 if top else Z0 - BUMP_E + BUMP_H / 2
            dc = DecalCanvas(0.0060, 0.0110, ppm=30000)
            for k in range(3):
                y = 0.0035 + k * 0.0020
                dc.groove([(0.0012, y), (0.0048, y)], width=0.0005, depth=0.00018, alpha=0.35)
            r.decal(dc, center=(sx * (SX + BUMP_E), FS - 0.0018, zb), normal=(sx, 0, 0), up=(0, 0, 1), depth=0.0012, mats=[M.armour],
                    min_dot=0.6)


# ---------------------------------------------------------------------------------------------
# sides
# ---------------------------------------------------------------------------------------------
def _side_plate(outline, t, holes, mat, floor_mats, normal, at, tag, wall_mat=None):
    g = holed_plate(outline, t, holes, mat, depth=t - FLOOR, wall_mat=wall_mat or mat, floor_mats=floor_mats, bevel=0.0004,
                    hole_bevel=0.00025, tag=tag)
    return align(g, normal, (0, 0, 1), at)


def _left_side(r, M):
    """+X side: raised rubber pad with the ridged PTT and the MONI key (side1)."""
    pw, pz0, pz1 = LPAD
    pzc = (pz0 + pz1) / 2
    pad = r.mat("fx_pad", color=(27, 28, 31), spec=0.1, gloss=0.18, bump="ribs", bump_amp=0.00006, bump_scale=0.0011,
                grain=0.04, edge=0.4, dirt=0.22, wear_color=(70, 72, 76), cavity=0.75, ao=0.3, layer="side")
    pwell = r.mat("fx_pad_well", color=(14, 15, 16), spec=0.08, gloss=0.18, edge=0.15, ao=1.0, cavity=0.8, layer="side")
    # plate local x = world +Y (towards the front) when facing +X with up = +Z
    holes = [(0.0, PTT_Z - pzc, PTT_W / 2 + 0.0005, PTT_L / 2 + 0.0005, PTT_W * 0.42 + 0.0005)]
    holes += [(0.0, S1_Z - pzc, S1_D / 2 + 0.0004, S1_D / 2 + 0.0004, S1_D / 2 + 0.0004, None, 6)]
    r.add(_side_plate(rrect(pw, pz1 - pz0, 0.0040, 6), 0.0012, holes, pad, [pwell] * 2, (1, 0, 0), (SX, SIDE_YC, pzc), "lpad",
                      wall_mat=pwell))
    # well floors (seen on the body model with the keys pulled): the moulded switch membrane - a long actuator
    # land with its tactile dome under the PTT, a dome ring under MONI
    span = (PTT_Z + PTT_L / 2 + 0.001) - (S1_Z - S1_D / 2 - 0.001)
    fl = DecalCanvas(PTT_W + 0.001, span, ppm=24000)
    zc_fl = (PTT_Z + PTT_L / 2 + 0.001 + S1_Z - S1_D / 2 - 0.001) / 2
    cx = (PTT_W + 0.001) / 2

    def fy(z):
        return span / 2 - (z - zc_fl)
    fl.rect(cx - PTT_W * 0.22, fy(PTT_Z + PTT_L * 0.36), PTT_W * 0.44, PTT_L * 0.72, r=PTT_W * 0.2, color=(24, 25, 27), height=0.00009,
            spec=0.2, gloss=0.35)
    fl.circle(cx, fy(PTT_Z), 0.0017, fill=False, width=0.0003, color=(12, 12, 13), height=-0.00008)
    fl.circle(cx, fy(PTT_Z), 0.0011, color=(34, 35, 38), height=0.00012, spec=0.3, gloss=0.45)
    fl.circle(cx, fy(S1_Z), 0.0017, fill=False, width=0.0003, color=(12, 12, 13), height=-0.00008)
    fl.circle(cx, fy(S1_Z), 0.0010, color=(34, 35, 38), height=0.00012, spec=0.3, gloss=0.45)
    r.decal(fl, center=(SX + 0.0004, SIDE_YC, zc_fl), normal=(1, 0, 0), up=(0, 0, 1), depth=0.0012, mats=[pwell], min_dot=0.7)
    o = ptt(r, "ptt", at=(SX + FLOOR, SIDE_YC, PTT_Z), normal=(1, 0, 0), up=(0, 0, 1), length=PTT_L, width=PTT_W, t=PTT_T,
            ridges=6, ridge_h=0.00045, mat=M.keys, emboss=None, depth=0.0016, dome=0.0005, ridge_span=0.6)
    with r.part("ptt"):          # moulded "PTT" a shade lighter / glossier than the rubber
        em = DecalCanvas(PTT_W * 0.9, PTT_L * 0.22, ppm=40000)
        em.text(PTT_W * 0.45, PTT_L * 0.11, "PTT", PTT_L * 0.085, fnt="label", spacing=PTT_L * 0.008, color=(56, 58, 62),
                height=0.00008, spec=0.32, gloss=0.5)
        r.decal(em, center=o - vec(1, 0, 0) * 0.00015 + vec(0, 0, 1) * (-PTT_L * 0.5 + PTT_L * 0.15), normal=(1, 0, 0), up=(0, 0, 1),
                depth=0.0015, min_dot=0.5)
    cv = DecalCanvas(S1_D * 0.9, S1_D * 0.9, ppm=60000)
    cv.circle(S1_D * 0.45, S1_D * 0.45, S1_D * 0.12, height=0.00016, spec=0.3, gloss=0.45)
    key(r, "side1", (SX + FLOOR, SIDE_YC, S1_Z), normal=(1, 0, 0), up=(0, 0, 1), size=(S1_D, S1_D), t=0.0020, mat=M.keys,
        corner=S1_D / 2, dome=0.00024, bevel=0.0005, canvas=cv, depth=0.0010, shape="round")
    # side keys face away from the raised camera (it looks at the face): their click areas lean 20 deg out of the
    # side plane (within the kit's tolerance to the press axis) and are wider, so the visible edge of each key is a
    # ~4 mm wide target on screen instead of a zero-width line. Layout u only - the caps stay where they are.
    r.part_meta("ptt", u=vec(0.0019, 0.0052, 0.0))
    r.part_meta("side1", u=vec(0.0013, 0.0036, 0.0))
    # MONI print below the side key (white pad print on the rubber)
    mo = DecalCanvas(0.0110, 0.0022, ppm=40000)
    mo.text(0.0055, 0.0011, "MONI", 0.00125, fnt="label", anchor="mm", spacing=0.0002, **ink("white"))
    r.decal(mo, center=(SX + 0.0012, SIDE_YC, S1_Z - S1_D / 2 - 0.0020), normal=(1, 0, 0), up=(0, 0, 1), depth=0.0012, mats=[pad])


def _right_side(r, M):
    """-X side: moulded grip ribs, DC-in plug cover with a pull tab, lanyard eye."""
    sx = -SX
    n = (-1, 0, 0)
    # grip ribs (geometry) down the middle of the side
    rib_m = M.armour
    for k in range(9):
        z = -0.0225 + k * 0.0034
        rb = box((0.0007, 0.0118, 0.0012), rib_m, r=0.00033, seg=1, center=(sx - 0.00025, SIDE_YC, z), faces="-x +y -y +z -z",
                 tag="grip_rib")
        r.hi_only(rb)
    # DC-in plug cover
    cz, cw, chh = 0.0215, 0.0090, 0.0150
    gasket = r.mat("fx_gasket")
    gk = extrude(rrect(cw + 0.0009, chh + 0.0009, 0.0030, 4), 0.0003, gasket, bevel=0.0001, bevel_seg=1, caps=(False, True), tag="dc_gasket")
    r.add(align(gk, n, (0, 0, 1), (sx + 0.00005, SIDE_YC, cz)))
    t = 0.0015
    cap = extrude(rrect(cw, chh, 0.0028, 4), t, M.plug, bevel=min(t * 0.45, 0.0004), bevel_seg=2, caps=(False, True), smooth_angle=50,
                  tag="dc_cap")
    cap.set_density(2.2)
    r.add(align(cap, n, (0, 0, 1), (sx - 0.00025, SIDE_YC, cz)))
    tab = box((0.0036, 0.0036, 0.0011), M.plug, r=0.0005, seg=2, center=(0, 0, 0.00075), faces="+x -x +y -y +z", tag="dc_tab")
    r.add(align(tab, n, (0, 0, 1), (sx, SIDE_YC, cz - chh / 2 - 0.0010)))
    lab = DecalCanvas(cw, chh, ppm=50000)
    lab.text(cw / 2, chh * 0.32, "DC", cw * 0.24, fnt="label", anchor="mm", color=(60, 62, 66), height=0.00006, spec=0.3, gloss=0.42)
    lab.text(cw / 2, chh * 0.55, "IN", cw * 0.20, fnt="label", anchor="mm", color=(60, 62, 66), height=0.00006, spec=0.3, gloss=0.42)
    lab.circle(cw / 2, chh * 0.78, cw * 0.09, fill=False, width=cw * 0.03, color=(60, 62, 66), height=0.00006)
    lab.circle(cw / 2, chh * 0.78, cw * 0.025, color=(60, 62, 66), height=0.00006)
    r.decal(lab, center=(sx - 0.0018, SIDE_YC, cz), normal=n, up=(0, 0, 1), depth=0.0012, mats=[M.plug])
    # lanyard eye moulded into the right flank near the back top
    r.hi_only(lanyard_eye(r, (sx, YS + 0.0030, ZT - 0.0215), n, up=(0, 0, 1), r=0.0026, wire=0.0010, mat=M.armour_m))


# ---------------------------------------------------------------------------------------------
# back and bottom
# ---------------------------------------------------------------------------------------------
def _battery_label(w, h, pack, chem, volts, cap, wh, serial):
    dc = DecalCanvas(w, h, ppm=34000)
    dc.rect(0, 0, w, h, r=h * 0.06, color=(23, 24, 26), spec=0.34, gloss=0.52)
    dc.rect(0, 0, w * 0.018, h, color=INK["orange"])
    x0, pad = w * 0.055, h * 0.09
    dc.text(x0, h * 0.18, pack, h * 0.15, fnt="label-black", anchor="lm", **ink("white"))
    dc.text(w - pad, h * 0.18, f"{chem}  {volts}", h * 0.10, fnt="label-semi", anchor="rm", **ink("white"))
    dc.text(x0, h * 0.385, f"{cap}   {wh}   RECHARGEABLE", h * 0.078, fnt="label-semi", anchor="lm", max_w=w - x0 - pad, **ink("white"))
    dc.rect(x0, h * 0.48, w - x0 - pad, h * 0.01, color=(84, 87, 91))
    fine = ["Charge only with the matching charger.", "Do not short-circuit, crush or burn.", "Keep away from heat above 60 °C."]
    for k, t in enumerate(fine):
        dc.text(x0, h * (0.58 + k * 0.1), t, h * 0.058, fnt="label-reg", anchor="lm", max_w=w * 0.55, **ink("grey"))
    isz = h * 0.2
    for k, kind in enumerate(("recycle", "bin", "warn")):
        dc.icon(kind, w * 0.64 + k * isz * 1.2, h * 0.53, isz, color=INK["white"] if kind != "warn" else (16, 16, 18))
    dc.barcode(w * 0.64, h * 0.78, w * 0.32, h * 0.15, seed=sum(map(ord, serial)) % 997, color=INK["white"])
    dc.text(x0, h * 0.9, serial, h * 0.062, fnt="mono", anchor="lm", **ink("grey"))
    return dc


def fx_belt_clip(r, top, w, length, t, standoff, lip, mat, block_mat, bow=0.0006, screw_kind="phillips"):
    """radio_common.belt_clip() with a smoothly bowed plate: the shared clip bends its plate at one mid point
    (a 0.15 mm fillet), which shows as a sharp crease line in the reflection - read as a glass edge. Here the
    plate runs straight between the mount bend and the lip bend and bows `bow` out along a sine over 6 rings
    (same ring count). Built on the back face (normal -Y, up +Z) with the mount block's top edge at `top`."""
    sec = [(0.0, 0.004, 0.0), (0.0, 0.0, standoff), (0.0, -length + lip * 0.6, standoff), (0.0, -length, standoff + lip * 0.55)]
    P = polyline_fillet(np.asarray(sec), 0.004, 6)
    # the straight run between the two bends: its end points are the last point of the first fillet and the first
    # point of the second one
    flat = [i for i in range(1, len(P) - 1) if abs(P[i, 2] - standoff) < 1e-7]
    ia, ib = flat[0], flat[-1]
    run = [P[ia] + (P[ib] - P[ia]) * s for s in np.linspace(0.0, 1.0, 7)]
    for k, p in enumerate(run):
        p[2] += bow * math.sin(math.pi * k / 6)
    P = np.concatenate([P[:ia], np.asarray(run), P[ib + 1:]])
    plate = sweep(rrect(w, t, t * 0.45, 2), P, mat, side=(1, 0, 0), tag="clip", smooth_angle=55)
    g = Geo()
    g += plate
    g += box((w + 0.004, 0.012, standoff + 0.0005), block_mat, r=0.0012, seg=2, center=(0, 0.002, (standoff + 0.0005) / 2))
    n, upv = vec(0, -1, 0), vec(0, 0, 1)
    out = align(g, n, upv, top)
    right = np.cross(upv, n)
    for k in range(2):
        x = (k - 0.5) * (w * 0.5)
        p = vec(top) + right * x + upv * (-0.003) + n * (standoff + t * 0.5 + 0.0001)
        out += screw(r, p, n, upv, d=0.0042, kind=screw_kind, segs=12, color=(66, 68, 73), spec=0.55, gloss=0.5)
    return out


def _ip_badge(r, M):
    """Moulded IP67 badge on the battery back: a raised rounded plate with a groove border and its print."""
    bw, bh, bt = 0.0220, 0.0084, 0.00045
    bz = 0.0002
    g = extrude(rrect(bw, bh, 0.0026, 4), bt, M.batt, bevel=0.0002, bevel_seg=2, caps=(False, True), smooth_angle=50, tag="badge")
    r.add(align(g, (0, -1, 0), (0, 0, 1), (0.0, BY, bz)))
    dc = DecalCanvas(bw, bh, ppm=40000)
    dc.groove_rect(0.0009, 0.0009, bw - 0.0018, bh - 0.0018, r=0.0018, width=0.0003, depth=0.0001, alpha=0.35)
    drop_icon(dc, 0.0040, bh * 0.5, 0.0040, **ink("orange"))
    dc.text(0.0068, bh * 0.40, "IP67", 0.0026, fnt="label-black", anchor="lm", spacing=0.0002, **ink("white"))
    dc.text(0.0068, bh * 0.70, "1 m · 30 min", 0.00095, fnt="label-semi", anchor="lm", spacing=0.0001, **ink("grey"))
    r.decal(dc, center=(0.0, BY - bt, bz), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.batt])


def _back_and_bottom(r, M):
    rub = r.mat("latch_rubber", color=(30, 31, 34), spec=0.16, gloss=0.26, bump="rubber", bump_amp=0.00003, bump_scale=0.0004,
                edge=0.4, dirt=0.15, wear_color=(76, 78, 82))
    # black powder-coated spring steel: satin coat, a little darker steel showing through on the rubbed edges
    # (the 0.8 mm plate edges are fully convex, so any wear runs the whole edge: kept low and dark, or the plate reads as
    # a glass sheet with bright polished edges)
    clip = r.mat("clip_steel", color=(29, 30, 33), spec=0.17, gloss=0.28, metal=0.0, bump="orange_peel", bump_amp=0.000025,
                 bump_scale=0.0006, grain=0.03, grain_scale=0.03, edge=0.45, wear=0.25, wear_color=(118, 121, 126), dirt=0.14,
                 scratch=0.12, smudge=0.12, cavity=0.7)
    # module-local clip: smooth bow instead of a creased plate, dark zinc Phillips screws
    bc = fx_belt_clip(r, (0.0, BY, CLIP_TOP), w=0.026, length=CLIP_LEN, t=0.0018, standoff=0.0032, lip=0.0070, mat=clip, block_mat=M.soft)
    for c in bc.charts:
        if c.mat.startswith("screw_"):
            c.density *= 6.0
    r.add(bc)
    # stamped stiffening channel down the plate + a small embossed arrow
    st = DecalCanvas(0.024, 0.026, ppm=16000)
    st.groove_rect(0.0072, 0.0016, 0.0096, 0.0228, r=0.0040, width=0.0009, depth=0.00028, alpha=0.3)
    for x in (0.0098, 0.0142):
        st.groove([(x, 0.004), (x, 0.0226)], width=0.0007, depth=0.00018, alpha=0.2)
    r.decal(st, center=(0.0, BY - 0.0042, CLIP_TOP - 0.019), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0022, mats=[clip])
    _ip_badge(r, M)
    # moulded label recess round the battery label + two stiffening lines across the pack above the latch
    rc = DecalCanvas(0.054, 0.030, ppm=20000)
    rc.groove_rect(0.0018, 0.0060, 0.0504, 0.0200, r=0.0016, width=0.0005, depth=0.00022, alpha=0.4)     # z -5.0 .. -25.0 mm
    for y in (0.0274, 0.0286):
        rc.groove([(0.010, y), (0.044, y)], width=0.00035, depth=0.00014, alpha=0.3)
    r.decal(rc, center=(0.0, BY, -0.0140), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.batt])
    bl = _battery_label(0.046, 0.0165, "FB-28", "Li-ion", "7.4 V", "1800 mAh", "13.3 Wh", "SN B26-28041")
    r.decal(bl, center=(0.0, BY, -0.0150), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.batt])   # 1.75 mm margins
    r.add(latch_tab(r, rub, (0.0, BY, Z0 + 0.0042), (0, -1, 0), (0, 0, 1), w=0.014, h=0.0055, t=0.0012, ribs=4))
    rel = DecalCanvas(0.03, 0.0026, ppm=30000)
    rel.text(0.015, 0.0013, "▼ RELEASE", 0.0011, fnt="label-semi", spacing=0.00012, **ink("grey"))
    r.decal(rel, center=(0.0, BY, Z0 + 0.0083), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.batt])
    # battery bottom: gold charging contacts with polarity marks
    cy = BY + DB / 2
    r.hi_only(charging_contacts(r, (0.0, cy, Z0 + 0.0004), (0, 0, -1), (0, 1, 0), n=2, pitch=0.012, size=(0.0042, 0.0026), proud=0.0002))
    pk = DecalCanvas(0.024, 0.0076, ppm=30000)
    pk.groove_rect(0.0016, 0.0012, 0.0208, 0.0052, r=0.0014, width=0.0003, depth=0.00018, alpha=0.4)
    pk.text(0.0011, 0.0038, "+", 0.0013, fnt="label-semi", **ink("grey"))
    pk.text(0.0229, 0.0038, "−", 0.0013, fnt="label-semi", **ink("grey"))
    r.decal(pk, center=(0.0, cy, Z0 + 0.0004), normal=(0, 0, -1), up=(0, 1, 0), depth=0.0008, mats=[M.batt])
    # rating label under the armour shell (sticker on the rubber), two screws holding the faceplate from below
    rl = _rating_label()
    r.decal(rl, center=(0.0, FS - DF / 2 - 0.0005, Z0), normal=(0, 0, -1), up=(0, 1, 0), depth=0.0008, mats=[M.armour])
    for x in (0.0215, -0.0215):
        s = screw(r, (x, FS - 0.0032, Z0), (0, 0, -1), (0, 1, 0), d=0.0026, kind="torx", color=(66, 68, 73), segs=12, spec=0.55, gloss=0.5)
        s.set_density(6.0)
        r.hi_only(s)


def _rating_label():
    # silver-grey foil (a white sticker blooms on the black rubber and its fine print smears at this texel size)
    return rating_plate(0.034, 0.0092, "FM TRANSCEIVER", "FX-280", "SN 26-02804", ref="TXQ-FX280B", rating="7.4 V  1800 mAh  Li-ion",
                        ppm=36000, ref_label="ID", foot="IP67", icons=("factory", "date", "book", "bin"), bg=(146, 150, 155), ink=(16, 17, 19))


# ---------------------------------------------------------------------------------------------
# medium LOD (6 m -> lodDist): cheap stand-ins flagged 'm', the detailed geometry flagged 'h'
# ---------------------------------------------------------------------------------------------
MED_DENSITY = 0.3


def _medium(r, M):
    keep = ("glass",)
    for c in r.geo.charts:
        if c.lod == "hm" and not c.mat.startswith("screen:") and not c.tag.startswith(keep):
            c.lod = "h"

    def add_m(g, part=None):
        g.set_density(MED_DENSITY)
        if part:
            with r.part(part):
                r.add(g, lod="m")
        else:
            r.add(g, lod="m")

    # armour shell + battery + bumpers (2 arc steps)
    sh = extrude(_outline(W, DF, CHAMF, 0.0, FIL, 0.0006, n=2), ZT - Z0, M.armour, bevel=0.0014, bevel_seg=1, z0=Z0, smooth_angle=50,
                 tag="m_shell").translate(0, FS - DF / 2, 0)
    add_m(_hide(_planar_uv(split_by_normal(sh, cap_dot=0.92)), (":-y",), 0.2))
    ins = 0.0004
    bt = extrude(_outline(W - 2 * ins, DB, 0.0, CHAMF - ins, 0.0006, FIL, n=2), ZT - Z0 - 2 * ins, M.batt, bevel=0.0012, bevel_seg=1,
                 z0=Z0 + ins, smooth_angle=50, tag="m_battery").translate(0, BY + DB / 2, 0)
    add_m(_hide(_planar_uv(split_by_normal(bt, cap_dot=0.92)), (":+y",), 0.2))
    # faceplate with only the screen / grille openings (keys become blocks on its face)
    mesh = m_mesh(r)
    holes, fl = _plate_holes(M, mesh, m_print_dark(r), keys=False)
    holes, fl = holes[:2], fl[:2]
    gun_m = r.mat("fx_gunmetal_m", color=(70, 73, 79), spec=0.5, gloss=0.5, metal=0.6, grain=0.045, grain_scale=0.02, edge=0.0, wear=0.0,
                  dirt=0.12, scratch=0.0, smudge=0.2, cavity=0.85, layer="face")
    g = holed_plate(rrect(FPW, FPZ1 - FPZ0, FPR, 3), FP_T, holes, gun_m, depth=FP_T - FLOOR, wall_mat=gun_m, floor_mats=fl,
                    bevel=0.0005, hole_bevel=0.0, corner_n=2, tag="m_face")
    add_m(_front(g, FPZC))
    yb = FS + FP_T

    def front_block(pid, X, Z, w, h, t):
        blk = box((w, h, t), M.keys, r=min(w, h) * 0.22, seg=1, faces="+x -x +y -y +z", tag="m_key")
        add_m(align(blk.translate(0, 0, t / 2), (0, 1, 0), (0, 0, 1), (X, yb - 0.0003, Z)), part=pid)

    for pid, X, Z, *_ in _keypad_cells():
        front_block(pid, X, Z, KEY[0], KEY[1], KEY_T - FP_T + 0.0006)
    for pid, z in zip(("kup", "kdown"), ARR_Z):
        front_block(pid, ARR_X, z, ARR[0], ARR[1], 0.0023 - FP_T + 0.0006)
    # deck plate, knobs, emergency, antenna, nut
    add_m(extrude(rrect(DK_W, DK_Y1 - DK_Y0, 0.003, 2), DECK_T, gun_m, bevel=0.0004, bevel_seg=1, caps=(False, True), tag="m_deck")
          .translate(0, DK_YC, ZT))
    kx, ky = KNOB_XY
    add_m(cylinder(KO_D / 2, KO_H + BOSS_H, "fx_knob_ring", segs=14, bevel=0.0005, bevel_seg=1, caps=(False, True), tag="m_knob")
          .translate(kx, ky, ZDK), part="knob_ch")
    add_m(cylinder(KI_D / 2, KI_H, "fx_knob_cap", segs=12, bevel=0.0005, bevel_seg=1, caps=(False, True), tag="m_knob")
          .translate(kx, ky, ZDK + BOSS_H + KO_H), part="knob_vol")
    add_m(cylinder(EM_D / 2, 0.0012, M.red, segs=8, caps=(False, True), tag="m_emerg").translate(EM_XY[0], EM_XY[1], ZDK), part="emerg")
    ax, ay = ANT_XY
    prof = [(0.0, 0.0), (0.0062, 0.0), (0.0062, 0.017), (0.0054, 0.03), (0.0052, 0.08), (0.0030, 0.0849), (0.0, 0.085)]
    add_m(lathe(prof, "fx_duck_rubber", segs=8, smooth_angle=50, tag="antenna_m").translate(ax, ay, ZDK + 0.0007 + NUT_H))
    add_m(lathe([(0.0056, 0.068), (0.0056, 0.073)], "fx_duck_band", segs=8, smooth_angle=50, tag="antenna_mband")
          .translate(ax, ay, ZDK + 0.0007 + NUT_H + 0.00005))
    hexo = np.array([(0.004 / math.cos(math.radians(30)) * math.cos(math.radians(30 + 60 * k)),
                      0.004 / math.cos(math.radians(30)) * math.sin(math.radians(30 + 60 * k))) for k in range(6)])
    add_m(extrude(hexo, NUT_H + 0.0007, "sma_nickel", caps=(False, True), smooth_angle=20, tag="m_nut").translate(ax, ay, ZDK))
    # corner bumpers + the left rubber pad (silhouette)
    add_m(_bumpers(r, M, n=1, bevel_seg=1, tag="m_bumper"))
    pw, pz0, pz1 = LPAD
    add_m(align(extrude(rrect(pw, pz1 - pz0, 0.004, 2), 0.0012, "fx_pad", bevel=0.0004, bevel_seg=1, caps=(False, True), tag="m_pad"),
                (1, 0, 0), (0, 0, 1), (SX, SIDE_YC, (pz0 + pz1) / 2)))
    # side parts
    sx = SX + 0.0010
    add_m(align(box((PTT_W, PTT_L, 0.0018), M.keys, r=0.003, seg=1, faces="+x -x +y -y +z", tag="m_ptt").translate(0, 0, 0.0009),
                (1, 0, 0), (0, 0, 1), (sx, SIDE_YC, PTT_Z)), part="ptt")
    add_m(align(cylinder(S1_D / 2, 0.0008, M.keys, segs=10, caps=(False, True), tag="m_side"), (1, 0, 0), (0, 0, 1),
                (sx, SIDE_YC, S1_Z)), part="side1")
    # belt clip plate
    clip = box((0.026, CLIP_LEN, 0.0018), "clip_steel", r=0.0007, seg=1, faces="+x -x +y -y +z -z", tag="m_clip")
    clip.translate(0, -CLIP_LEN / 2 + 0.002, 0.0041)
    clip += box((0.030, 0.012, 0.0037), M.soft, r=0.001, seg=1, center=(0, 0.002, 0.00185), faces="+x -x +y -y +z", tag="m_clip")
    add_m(align(clip, (0, -1, 0), (0, 0, 1), (0.0, BY, CLIP_TOP)))


__all__ = ["fieldpro"]
