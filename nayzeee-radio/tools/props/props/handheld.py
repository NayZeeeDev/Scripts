"""
PX-740 PATROL - police portable handheld (PROPS_BRIEF section 1, SPEC section 9).

Models (radio kit): nzr_handheld (complete, idle screen, medium LOD), nzr_handheld_body (no pressable parts,
live screen placeholder) and one nzr_handheld_<part> per SPEC 9.2 part id. Generic labelling only - model code
PX-740, the word PATROL, a battery label and a rating label with fictitious identifiers (Rule B: no NAYZEEE
name or mark, no real maker).

Construction (metres, +X = viewer's left, +Y = front, +Z up, origin = grip point 40 % up the body):
    front shell     58 x 24 mm plan, front corners chamfered 3 mm + filleted, front face crowned 0.5 mm
    battery pack    the rear 13.4 mm, its own moulding behind a 0.6 mm seam (inset 0.4 mm at the sides),
                    ribbed release latch at the bottom centre, belt clip, battery label, rating label underneath
    top deck        3 mm cap over both with a moulded parting line, two raised knob bosses (D-shafts),
                    a recessed emergency pocket, a light-pipe socket and a raised SMA antenna seat
    front bezel     one 1.2 mm satin moulding over the front: speaker opening (4 raised bars over acoustic
                    mesh), mic port, screen window (36 x 27 mm LCD, 1 mm bezel, smoked glass), the soft-key
                    cluster wells (P1 / P2 / OK / back, round d-pad well) and the 4 x 3 keypad wells
    sides           left: diamond-texture rubber grip panel with the PTT and two side-button wells; right:
                    accessory connector cover on a gasket with two knurled thumbscrews over a rubber grip panel
    bottom          gold charging contacts in a moulded recess, lanyard eye, rating label on the battery
Every pressable part (SPEC 9.2) is its own part block with full metadata. Texture layers: main (1024: knobs,
antenna, clip, small bits), face (1024: bezel, deck, battery back / bottom - every print) and side (1024: the
side walls and the grip panels, so the diamond grip texture resolves at hand distance). A hand-built medium LOD
(stand-ins flagged 'm', everything detailed flagged 'h') is used from 6 m.
"""
from __future__ import annotations

import math
from dataclasses import replace as dc_replace
from types import SimpleNamespace

import numpy as np

from nzprops import DecalCanvas, Geo, box, cylinder, extrude, lathe, poly_cap, quad, rrect, split_by_normal, vec, well_plate
from nzprops.mesh import Chart, ensure_ccw, offset_poly, subdivide_poly

from .common import align, screw
from .radio_common import (INK, belt_clip, boss, charging_contacts, dpad, ink, key, knob, lanyard_eye, latch_tab, light_pipe,
                           m_keypad_rubber, m_mesh, m_print_dark, m_smoked_glass, m_soft_black, model_print, ptt, rating_label,
                           sma_nut, thumbscrew)
from .radio_kit import radio

# ---------------------------------------------------------------------------------------------
# dimensions
# ---------------------------------------------------------------------------------------------
W, D, H = 0.058, 0.038, 0.132          # body without knobs / antenna
Z0 = -0.4 * H                          # bottom (origin = grip point, 40 % of the body height up)
ZT = Z0 + H                            # top of the deck
FY, BY = D / 2, -D / 2                 # front / back faces
DECK = 0.003                           # top deck thickness
ZD = ZT - DECK                         # deck bottom = shell top
DF = 0.024                             # front shell depth
SEAM = 0.0006                          # front shell / battery gap
YS = FY - DF                           # shell back face
YB = YS - SEAM                         # battery front face
DB = YB - BY                           # battery depth
CHAMF, FIL = 0.003, 0.0012             # vertical edge chamfer + fillet
CROWN = 0.0005                         # front face crown at the centre line

# front bezel moulding (plate) - layout in world X (viewer's left = +X) and Z
PT = 0.0012                            # bezel thickness = well depth
PW, PZ0, PZ1 = 0.048, -0.0502, 0.0735  # bezel width, bottom, top
PZC = (PZ0 + PZ1) / 2
FLOOR = 0.00004                        # well floors float this far above the shell surface
GRILLE = (0.0, 0.0612, 0.0420, 0.0206)   # centre X, centre Z, width, height of the speaker opening
MIC_Z = 0.0486
PRINT_Z = 0.0430
SCR_Z = 0.0230                         # screen centre
VIEW = (0.036, 0.027)                  # visible LCD (layout screen.size)
BEZEL = 0.001
CL_Z = -0.0030                         # soft-key cluster centre
KP_X = 0.0165                          # P1 / OK column (+X), P2 / back (-X)
KEY = (0.011, 0.0065)                  # keypad caps
KEY_T = 0.0020
KEY_PITCH = (0.0142, 0.0087)
KEY_ROW0 = -0.0176                     # first keypad row centre
KGAP = 0.00045                         # cap to well wall

# top deck layout (world X / Y)
CH_XY = (0.0170, 0.0030)
VOL_XY = (-0.0015, 0.0035)
ANT_XY = (-0.0175, -0.0055)
EM_XY = (-0.0185, 0.0115)
LED_XY = (-0.0085, -0.0115)
CH_D, CH_H = 0.012, 0.014
VOL_D, VOL_H = 0.013, 0.012
BOSS_H = 0.0020
NUT_H = 0.0035

# sides
SIDE_YC = 0.0055                       # centre of the flat side faces of the front shell
PTT_Z = 0.0270
PTT_W, PTT_L, PTT_T = 0.012, 0.030, 0.0026
SIDE_D = 0.006
SIDE_Z = (0.0030, -0.0075)
LPANEL = (0.0175, -0.0410, 0.0490)     # width, bottom, top of the left grip panel
RPANEL = (0.0175, -0.0410, 0.0085)
ACC = (0.0305, 0.0135, 0.0330)         # accessory cover centre Z, width, height
CLIP_TOP, CLIP_LEN = 0.0640, 0.058


def crown(x):
    """Front face crown (m) at world X: CROWN on the centre line falling to 0 at the side walls."""
    x = np.asarray(x, np.float64)
    return CROWN * np.clip(1.0 - (x / (W / 2)) ** 2, 0.0, 1.0)


def y_face(x):
    """World Y of the (crowned) front shell surface at X."""
    return FY + float(crown(x))


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
    """CCW plan outline w (X) x d (Y): the front (+Y) corners chamfered cf and filleted rf, the back
    corners chamfered cb and filleted rb - shell and battery meet on square-ish corners so the seam
    between them stays a thin line instead of a V notch."""
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
    """Sutherland-Hodgman: polygon (list of 2D points) clipped by a convex CCW polygon."""
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


def holed_plate(outline, t, holes, mat, depth=None, wall_mat=None, floor_mats=None, bevel=0.0004, hole_bevel=0.0003, corner_n=5,
                tag="plate"):
    """well_plate() with any CONVEX outline (rounded rectangle, chamfered housing plan) instead of a
    square one: the openings fall into wells (top chamfer, inward walls, a floor per hole -
    floor_mats[i] picks each floor's material). Built on z = 0 .. t facing +Z, outline centred."""
    ol = ensure_ccw(np.asarray(outline, np.float64))
    bw = 2 * float(np.abs(ol[:, 0]).max()) + 0.004
    bh = 2 * float(np.abs(ol[:, 1]).max()) + 0.004
    g = well_plate(bw, bh, t, holes, mat, depth=depth, wall_mat=wall_mat or mat, floor_mat=wall_mat or mat, bevel=0.0,
                   hole_bevel=hole_bevel, corner_n=corner_n, tag=tag)
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


def _front(g: Geo, at_z=0.0):
    """Plate-local (x = viewer's right, y = up, z = out) -> world on the front face at height at_z, crowned."""
    g = align(g, (0, 1, 0), (0, 0, 1), (0.0, FY, at_z))

    def fn(p):
        q = p.copy()
        q[:, 1] = p[:, 1] + crown(p[:, 0])
        return q
    return g.deform(fn)


def _set_mat(g: Geo, mat, suffixes):
    """Give the charts of a split_by_normal() Geo whose tag ends with one of `suffixes` another material."""
    for c in g.charts:
        if any(c.tag.endswith(s) for s in suffixes):
            c.mat = mat
    return g


_PLANAR = {"+x": (1, 1, 2), "-x": (1, -1, 2), "+y": (0, -1, 2), "-y": (0, 1, 2), "+z": (0, 1, 1), "-z": (0, -1, 1)}


def _planar_uv(g: Geo):
    """Re-map the charts of a split_by_normal() Geo to planar UVs on their dominant plane (u = right, v = down
    as seen from outside). An extrude's side chart keeps the perimeter parameter as u, so the face across the
    outline's start point would otherwise span the whole perimeter in the atlas."""
    for c in g.charts:
        key = c.tag[-2:]
        if key not in _PLANAR:
            continue
        a, sa, b = _PLANAR[key]
        c.uvm = np.stack([c.pos[:, a] * sa, -c.pos[:, b]], axis=1)
    return g


def _hide(g: Geo, suffixes, k=0.04):
    """Charts of a split Geo that are never seen (faces pressed against another moulding) get almost no texels."""
    for c in g.charts:
        if any(c.tag.endswith(s) for s in suffixes):
            c.density *= k
    return g


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def _mats(r):
    soft = m_soft_black(r)                                                   # main: housing bits, bosses, seat
    face = r.mat_from("px_face", dc_replace(r.mats[soft], layer="face"))    # deck, battery back / bottom (prints)
    side = r.mat_from("px_side", dc_replace(r.mats[soft], layer="side"))    # side walls of shell + battery
    # front escutcheon: a touch smoother and satin against the soft-touch housing (reads as a separate moulding)
    bezel = r.mat("px_bezel", color=(21, 22, 25), spec=0.27, gloss=0.42, bump="stipple", bump_amp=0.000018, bump_scale=0.00032,
                  grain=0.025, grain_scale=0.025, edge=0.5, dirt=0.1, wear_color=(78, 80, 85), cavity=0.7, layer="face")
    well = r.mat("px_well", color=(15, 16, 18), spec=0.12, gloss=0.22, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                 grain=0.02, edge=0.2, ao=1.0, cavity=0.8, layer="face")
    grip = r.mat("px_grip", color=(32, 33, 36), spec=0.09, gloss=0.17, bump="diamond", bump_amp=0.00017, bump_scale=0.0016,
                 grain=0.045, grain_scale=0.03, edge=0.35, dirt=0.22, wear_color=(70, 72, 76), cavity=0.7, layer="side")
    gwell = r.mat("px_side_well", color=(15, 16, 18), spec=0.1, gloss=0.2, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                  edge=0.2, ao=1.0, cavity=0.8, layer="side")
    keys = m_keypad_rubber(r, "black")
    return SimpleNamespace(soft=soft, face=face, side=side, bezel=bezel, well=well, grip=grip, gwell=gwell, keys=keys)


# ---------------------------------------------------------------------------------------------
# the radio
# ---------------------------------------------------------------------------------------------
@radio("handheld", title="PX-740 patrol handheld", code="PX-740", layers={"face": 1024, "side": 1024},
       maps={"face": {"n": 1024, "s": 512}, "side": {"n": 1024, "s": 512}},
       doc={"screen": "nzr_scr 512 x 384 behind smoked glass, visible LCD 36 x 27 mm (layout screen.size)"})
def handheld(r):
    M = _mats(r)
    _shell_and_battery(r, M)
    _deck(r, M)
    _front_bezel(r, M)
    _front_parts(r, M)
    _top_parts(r, M)
    _left_side(r, M)
    _right_side(r, M)
    _back_and_bottom(r, M)
    insert = _top_details(r, M)
    _medium(r, M)
    r.anchor(focus=(0.0, FY + 0.0015, 0.004), camDist=0.34, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422): palm on the battery / belt clip, fingers round the right side, thumb on the left "
                  "PTT; screen faces the camera when raised. Tune with /radiogrip.")


# ---------------------------------------------------------------------------------------------
# housing: front shell, battery pack, top deck
# ---------------------------------------------------------------------------------------------
def _shell_and_battery(r, M):
    # front shell: subdivided outline so the crown deform stays smooth on caps and walls alike
    ol = subdivide_poly(_outline(W, DF, CHAMF, 0.0, FIL, 0.0006, n=4), 0.0025)
    g = extrude(ol, ZD - Z0, M.soft, bevel=0.0009, bevel_seg=3, z0=Z0, smooth_angle=50, tag="shell")
    g.translate(0, FY - DF / 2, 0)
    yc = FY - DF / 2

    def fn(p):
        q = p.copy()
        w = np.clip((p[:, 1] - yc) / (DF / 2), 0, 1) ** 4
        q[:, 1] = p[:, 1] + crown(p[:, 0]) * w
        return q
    g.deform(fn)
    g = _planar_uv(split_by_normal(g))
    _hide(g, (":-y", ":+z"))                 # back face against the battery, top face under the deck
    r.add(_set_mat(g, M.side, (":+x", ":-x")))
    # battery pack: 0.4 mm narrower, square-ish front corners against the shell, chamfered back corners
    ins = 0.0004
    ob = _outline(W - 2 * ins, DB, 0.0, CHAMF - ins, 0.0006, FIL, n=4)
    bt = extrude(ob, ZD - 0.0005 - (Z0 + 0.0003), M.soft, bevel=0.0010, bevel_seg=3, z0=Z0 + 0.0003, smooth_angle=50, tag="battery")
    bt.translate(0, BY + DB / 2, 0)
    bt = _planar_uv(split_by_normal(bt))
    _hide(bt, (":+y", ":+z"))                # front face against the shell, top face under the deck
    _set_mat(bt, M.side, (":+x", ":-x"))
    _set_mat(bt, M.face, (":-y", ":-z"))     # the labelled back and the bottom (rating label) get the print atlas
    r.add(bt)
    # battery side grip: three shallow moulded finger ribs low on each side of the pack
    for sx in (1, -1):
        for k in range(3):
            z = Z0 + 0.0105 + k * 0.0042
            rib = box((0.0009, DB - 0.0062, 0.0016), M.side, r=0.0004, seg=1, center=(sx * (W / 2 - ins + 0.00035), BY + DB / 2 + 0.0004, z),
                      faces="+x -x +y -y +z -z", tag="bat_rib")
            r.hi_only(rib)


def _deck(r, M):
    """3 mm top deck over shell + battery: emergency pocket and light-pipe socket are real wells."""
    ol = _outline(W, D, CHAMF, CHAMF, FIL, FIL, n=4)
    holes = [(EM_XY[0], EM_XY[1], 0.0045 + 0.0005, 0.003 + 0.0005, 0.0017, 0.0025),
             (LED_XY[0], LED_XY[1], 0.0015, 0.0015, 0.0015, 0.0004)]
    dk = holed_plate(ol, DECK, holes, M.face, wall_mat=M.soft, floor_mats=[M.soft, M.soft], bevel=0.0009, hole_bevel=0.0003,
                     tag="deck")
    dk += poly_cap(ol, 0.0, M.soft, up=False, tag="deck:bottom").set_density(0.04)
    r.add(dk.translate(0, 0, ZD))
    # raised knob bosses with D-shaft stubs (seen on the body model once the knobs are pulled off)
    shaft = r.mat("shaft_steel", color=(150, 152, 156), spec=0.7, gloss=0.55, metal=1.0, bump="brushed", bump_amp=0.000005,
                  bump_scale=0.0003, edge=0.3)
    r.add(boss(r, M.soft, (CH_XY[0], CH_XY[1], ZT), d=0.0150, h=BOSS_H, shaft_d=0.0060, shaft_h=0.0060, shaft_mat=shaft))
    r.add(boss(r, M.soft, (VOL_XY[0], VOL_XY[1], ZT), d=0.0160, h=BOSS_H, shaft_d=0.0060, shaft_h=0.0055, shaft_mat=shaft))
    # antenna seat: low moulded ring + rubber gasket under the nut
    r.add(cylinder(0.0058, 0.0010, M.soft, segs=28, bevel=0.0004, bevel_seg=1, caps=(False, True), tag="seat")
          .translate(ANT_XY[0], ANT_XY[1], ZT))
    gasket = r.mat("ant_gasket", color=(20, 21, 23), spec=0.1, gloss=0.18, bump="rubber", bump_amp=0.00002, bump_scale=0.0003)
    r.add(cylinder(0.0049, 0.0005, gasket, segs=28, bevel=0.0002, bevel_seg=1, caps=(False, True), tag="seat")
          .translate(ANT_XY[0], ANT_XY[1], ZT + 0.0010))


# ---------------------------------------------------------------------------------------------
# front bezel moulding: grille, mic, screen window, cluster + keypad wells, prints
# ---------------------------------------------------------------------------------------------
def _keypad_cells():
    """(pid, X, Z, legend, sub) of the 4 x 3 keypad, X = viewer's left."""
    rows = [[("k1", "1", ".,?"), ("k2", "2", "ABC"), ("k3", "3", "DEF")],
            [("k4", "4", "GHI"), ("k5", "5", "JKL"), ("k6", "6", "MNO")],
            [("k7", "7", "PQRS"), ("k8", "8", "TUV"), ("k9", "9", "WXYZ")],
            [("kstar", "*", "‹"), ("k0", "0", "⇧"), ("khash", "#", "⇥")]]
    out = []
    for ri, row in enumerate(rows):
        for ci, (pid, lg, sub) in enumerate(row):
            out.append((pid, (1 - ci) * KEY_PITCH[0], KEY_ROW0 - ri * KEY_PITCH[1], lg, sub))
    return out


CLUSTER = {   # pid: (X, Z, w, h, corner)
    "kp1": (KP_X, CL_Z + 0.0055, 0.0075, 0.0050, 0.0025),
    "kp2": (-KP_X, CL_Z + 0.0055, 0.0075, 0.0050, 0.0025),
    "kok": (KP_X, CL_Z - 0.0045, 0.0080, 0.0070, 0.0016),
    "kback": (-KP_X, CL_Z - 0.0045, 0.0080, 0.0070, 0.0016),
}
DPAD_R = 0.0090
DPAD_SIZE = 0.0160


def _bezel_holes(M, mesh, bezel_black, keys=True):
    holes, fl = [], []

    def hole(X, Z, hw, hh, rad, floor, n=None):
        holes.append((-X, Z - PZC, hw, hh, rad) + ((None, n) if n else ()))
        fl.append(floor)

    gx, gz, gw, gh = GRILLE
    hole(gx, gz, gw / 2, gh / 2, 0.0026, mesh)
    hole(0.0, MIC_Z, 0.0006, 0.0006, 0.0006, mesh)
    hole(0.0, SCR_Z, VIEW[0] / 2 + BEZEL, VIEW[1] / 2 + BEZEL, 0.0014, bezel_black)
    if keys:
        hole(0.0, CL_Z, DPAD_R, DPAD_R, DPAD_R, M.well, n=10)      # 44-sided round d-pad well
        for pid, (X, Z, w, h, cr) in CLUSTER.items():
            hole(X, Z, w / 2 + KGAP, h / 2 + KGAP, cr + KGAP, M.well)
        for pid, X, Z, lg, sub in _keypad_cells():
            hole(X, Z, KEY[0] / 2 + KGAP, KEY[1] / 2 + KGAP, KEY[1] * 0.28 + KGAP, M.well)
    return holes, fl


def _grille_bars(mat, t, rounded=True):
    gx, gz, gw, gh = GRILLE
    n = 4
    bar_h = 0.0030
    gap = (gh - n * bar_h) / (n + 1)
    g = Geo()
    for k in range(n):
        zc = gz + gh / 2 - gap - bar_h / 2 - k * (bar_h + gap)
        if rounded:
            g += box((gw - 0.0004, bar_h, t), mat, r=0.00055, seg=2, center=(-gx, zc - PZC, FLOOR + t / 2), faces="+x -x +y -y +z",
                     tag="grille_bar")
        else:
            g += box((gw - 0.0004, bar_h, t), mat, center=(-gx, zc - PZC, FLOOR + t / 2), faces="+x -x +y -y +z", tag="grille_bar_m")
    return g


def _front_bezel(r, M):
    mesh = m_mesh(r)
    bezel_black = m_print_dark(r)
    holes, fl = _bezel_holes(M, mesh, bezel_black)
    outline = rrect(PW, PZ1 - PZ0, 0.0042, 6)
    g = holed_plate(outline, PT, holes, M.bezel, depth=PT - FLOOR, wall_mat=M.soft, floor_mats=fl, bevel=0.00045, hole_bevel=0.00028,
                    corner_n=4, tag="bezel")
    # speaker bars: 4 rounded bars standing a hair proud of the bezel over the acoustic mesh
    g += _grille_bars(M.bezel, PT + 0.00022 - FLOOR)
    r.add(_front(g, PZC))
    # screen (fixed UV, layout anchor) on the bezel floor + smoked glass 0.3 mm above it
    yf = FY + float(crown(0.0)) + FLOOR
    r.screen(quad((0.0, yf + 0.00006, SCR_Z), (-1, 0, 0), (0, 0, 1), VIEW[0], VIEW[1], "x", fixed_uv=True))
    r.add(quad((0.0, yf + 0.00036, SCR_Z), (-1, 0, 0), (0, 0, 1), VIEW[0] + 2 * BEZEL - 0.0002, VIEW[1] + 2 * BEZEL - 0.0002,
               m_smoked_glass(r), tag="glass"))
    # prints on the bezel (print atlas): model code strip, ingress badge, band word
    ytop = FY + CROWN + PT
    mp = model_print("PX-740", "PATROL", w=0.030, h=0.0080, rule_color="teal", align_="center")
    r.decal(mp, center=(0.0, ytop, PRINT_Z), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.bezel])
    badge = DecalCanvas(0.0075, 0.0034, ppm=40000)
    badge.rect(0.0002, 0.0002, 0.0071, 0.0030, r=0.0006, fill=False, width=0.00022, **ink("grey"))
    badge.text(0.00375, 0.0017, "IP54", 0.0015, fnt="label-semi", **ink("grey"))
    r.decal(badge, center=(-0.0185, ytop, PRINT_Z + 0.0006), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.bezel])
    band = DecalCanvas(0.0075, 0.0034, ppm=40000)
    band.text(0.00375, 0.0017, "UHF", 0.0015, fnt="label-semi", **ink("grey"))
    r.decal(band, center=(0.0185, ytop, PRINT_Z + 0.0006), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.bezel])


# ---------------------------------------------------------------------------------------------
# front parts: keypad, soft keys, d-pad
# ---------------------------------------------------------------------------------------------
def _ok_canvas(w, h):
    dc = DecalCanvas(w, h, ppm=60000)
    dc.glyph("grid", w / 2, h * 0.33, h * 0.30, **ink("white"))
    dc.text(w / 2, h * 0.74, "OK", h * 0.27, fnt="label", **ink("white"))
    return dc


def _key_legend(w, h, digit, sub):
    """Keypad legend: big digit left of centre, small letters / symbol right (white pad print)."""
    dc = DecalCanvas(w, h, ppm=60000)
    sym = len(sub) == 1 and not sub.isalpha() and sub not in ".,?"
    dx = w * 0.36 if not sym else w * 0.40
    dc.text(dx, h * 0.52, digit, h * (0.62 if digit not in "*#" else 0.56), fnt="label", **ink("white"))
    if sym:
        dc.text(w * 0.64, h * 0.52, sub, h * 0.50, fnt="sans-bold", **ink("white"))
    else:
        dc.text(w * 0.70, h * 0.56, sub, h * 0.30, fnt="label-semi", max_w=w * 0.40, **ink("white"))
    return dc


def _front_parts(r, M):
    for pid, X, Z, lg, sub in _keypad_cells():
        at = (X, y_face(X) + FLOOR, Z)
        cv = _key_legend(KEY[0] * 0.92, KEY[1] * 0.88, lg, sub)
        key(r, pid, at, (0, 1, 0), (0, 0, 1), size=KEY, t=KEY_T, mat=M.keys, corner=KEY[1] * 0.28, dome=0.00028, bevel=0.0006,
            canvas=cv, depth=0.0014)
    for pid, (X, Z, w, h, cr) in CLUSTER.items():
        at = (X, y_face(X) + FLOOR, Z)
        if pid in ("kp1", "kp2"):
            cv = DecalCanvas(w * 0.9, h * 0.86, ppm=60000)
            cv.text(w * 0.45, h * 0.43, "P1" if pid == "kp1" else "P2", h * 0.46, fnt="label", spacing=h * 0.03, **ink("white"))
        elif pid == "kok":
            cv = _ok_canvas(w * 0.9, h * 0.9)
        else:
            cv = DecalCanvas(w * 0.9, h * 0.9, ppm=60000)
            cv.glyph("back", w * 0.45, h * 0.45, h * 0.44, **ink("white"))
        key(r, pid, at, (0, 1, 0), (0, 0, 1), size=(w, h), t=0.0019, mat=M.keys, corner=cr, dome=0.00025, bevel=0.0006, canvas=cv,
            depth=0.0012)
    dpad(r, "dpad", at=(0.0, y_face(0.0) + FLOOR, CL_Z), normal=(0, 1, 0), up=(0, 0, 1), size=DPAD_SIZE, kind="diamond",
         t=0.0024, mat=M.keys, arrows="print", tilt=5.0, depth=0.0010, dome=0.0004, center_mark=True)


# ---------------------------------------------------------------------------------------------
# top: knobs, emergency key
# ---------------------------------------------------------------------------------------------
def _flute_outline(R, rd, ribs, phase):
    """Plan outline of a fluted knob: `ribs` V-bottomed grooves `rd` deep, flat-topped lands between them.
    The land centres sit at `phase` + k * period (so one land faces the front for the index line)."""
    per = 2 * math.pi / ribs
    gb, gw = per * 0.07, per * 0.21          # groove half-width at the floor / at the rim
    pts = []
    for k in range(ribs):
        a0 = phase + per / 2 + k * per        # groove centre between two lands
        pts.append((R - rd, a0 - gb))
        pts.append((R - rd, a0 + gb))
        for j in range(3):
            pts.append((R, a0 + gw + (per - 2 * gw) * j / 2))
    return np.array([(rr * math.cos(a), rr * math.sin(a)) for rr, a in pts])


def _channel_knob(r, M, base):
    """knob_ch: 12 x 14 mm channel selector with 16 real flutes (hard-edged geometry, not a shading trick),
    a smooth chamfered crown band, a flange skirt and a white index line on the top and down the front land."""
    d, h = CH_D, CH_H
    R, rd = d / 2, 0.00068
    Rs, sh = 0.0142 / 2, 0.0018
    band, bev, dome = 0.0010, 0.0006, 0.0004
    mat = r.mat("knob_ch_black", color=(27, 28, 31), spec=0.26, gloss=0.38, bump="stipple", bump_amp=0.000018, bump_scale=0.00035,
                grain=0.03, edge=0.75, dirt=0.15, wear_color=(96, 98, 102), cavity=0.8)
    ax, fr = vec(0, 0, 1), vec(0, 1, 0)
    origin = vec(base) + ax * (h / 2)
    with r.part("knob_ch", origin=origin, press=-ax, depth=0.0008, u=vec(-1, 0, 0) * (d / 2), v=ax * (h / 2), shape="rect",
                action="knob", value="channel", axis=ax, detents=16):
        g = lathe([(Rs * 0.9, 0.0), (Rs, sh * 0.3), (Rs, sh * 0.72), (Rs - 0.00025, sh), (R - rd - 0.0001, sh)], mat, segs=40,
                  smooth_angle=40, tag="knob_skirt")
        ol = _flute_outline(R, rd, 16, math.pi / 2)
        g += extrude(ol, h - band - sh, mat, z0=sh, caps=(False, True), smooth_angle=28, tag="knob_flutes")
        prof = [(R, h - band), (R, h - bev)]
        prof += [(R - bev + bev * math.cos(a), h - bev + bev * math.sin(a)) for a in np.linspace(math.pi / 6, math.pi / 2, 3)]
        prof += [(R * 0.55, h + dome * 0.7), (0.0, h + dome)]
        g += lathe(prof, mat, segs=40, smooth_angle=40, tag="knob_top")
        r.add(g.translate(*base))
        top_c = vec(base) + ax * (h + dome)
        dc = DecalCanvas(d, d, ppm=max(9000, int(300 / d)))
        dc.rect(d / 2 - d * 0.035, d * 0.05, d * 0.07, d * 0.38, r=d * 0.02, **ink("white"))
        r.decal(dc, center=top_c, normal=ax, up=fr, depth=dome + 0.002, min_dot=0.3)
        side = DecalCanvas(d * 0.16, h, ppm=max(9000, int(300 / d)))
        side.rect(d * 0.08 - d * 0.025, h * 0.1, d * 0.05, h * 0.68, r=d * 0.015, **ink("white"))
        r.decal(side, center=vec(base) + ax * (h * 0.5) + fr * R, normal=fr, up=ax, depth=d * 0.08, min_dot=0.6)
    return origin


def _top_parts(r, M):
    _channel_knob(r, M, (CH_XY[0], CH_XY[1], ZT + BOSS_H))
    knob(r, "knob_vol", base=(VOL_XY[0], VOL_XY[1], ZT + BOSS_H), axis=(0, 0, 1), front=(0, 1, 0), d=VOL_D, h=VOL_H,
         style="knurled", skirt=True, skirt_d=0.0150, skirt_h=0.0016, index="dot", value="volume", detents=24, segs=40)
    orange = r.mat("emerg_orange", color=(238, 106, 24), spec=0.34, gloss=0.48, bump="dimple", bump_amp=0.00004, bump_scale=0.00062,
                   grain=0.03, edge=0.45, dirt=0.12, wear_color=(250, 170, 110))
    key(r, "emerg", (EM_XY[0], EM_XY[1], ZD + DECK - 0.0025), normal=(0, 0, 1), up=(0, 1, 0), size=(0.009, 0.006), t=0.0022,
        mat=orange, corner=0.0012, dome=0.00018, bevel=0.0005, depth=0.0012)


# ---------------------------------------------------------------------------------------------
# sides
# ---------------------------------------------------------------------------------------------
def _side_plate(outline, t, holes, mat, floor_mats, normal, at, tag, wall_mat=None):
    g = holed_plate(outline, t, holes, mat, depth=t - FLOOR, wall_mat=wall_mat or mat, floor_mats=floor_mats, bevel=0.0004,
                    hole_bevel=0.00025, tag=tag)
    return align(g, normal, (0, 0, 1), at)


def _left_side(r, M):
    """+X side: diamond-texture rubber grip panel with the PTT and two side-button wells."""
    sx = W / 2
    pw, pz0, pz1 = LPANEL
    pzc = (pz0 + pz1) / 2
    # panel local x = world +Y (towards the front), y = world Z
    holes = [(0.0, PTT_Z - pzc, PTT_W / 2 + 0.0005, PTT_L / 2 + 0.0005, PTT_W * 0.42 + 0.0005)]
    holes += [(0.0, z - pzc, SIDE_D / 2 + 0.0004, SIDE_D / 2 + 0.0004, SIDE_D / 2 + 0.0004) for z in SIDE_Z]
    r.add(_side_plate(rrect(pw, pz1 - pz0, 0.0040, 6), 0.0012, holes, M.grip, [M.gwell] * 3, (1, 0, 0), (sx, SIDE_YC, pzc), "lpanel",
                      wall_mat=M.gwell))
    o = ptt(r, "ptt", at=(sx + FLOOR, SIDE_YC, PTT_Z), normal=(1, 0, 0), up=(0, 0, 1), length=PTT_L, width=PTT_W, t=PTT_T,
            ridges=5, ridge_h=0.00045, mat=M.keys, emboss="PTT", depth=0.0016, dome=0.0005)
    with r.part("ptt"):          # the moulded "PTT" a shade lighter / glossier than the rubber so it reads at hand distance
        em = DecalCanvas(PTT_W * 0.9, PTT_L * 0.22, ppm=40000)
        em.text(PTT_W * 0.45, PTT_L * 0.11, "PTT", PTT_L * 0.09, fnt="label", spacing=PTT_L * 0.008, color=(52, 54, 58),
                height=0.00008, spec=0.32, gloss=0.5)
        r.decal(em, center=o - vec(1, 0, 0) * 0.00015 + vec(0, 0, 1) * (-PTT_L * 0.5 + PTT_L * 0.17), normal=(1, 0, 0), up=(0, 0, 1),
                depth=0.0015, min_dot=0.5)
    for pid, z, mark in (("side1", SIDE_Z[0], "dot"), ("side2", SIDE_Z[1], "bar")):
        cv = DecalCanvas(SIDE_D * 0.9, SIDE_D * 0.9, ppm=60000)
        if mark == "dot":
            cv.circle(SIDE_D * 0.45, SIDE_D * 0.45, SIDE_D * 0.11, height=0.00016, spec=0.3, gloss=0.45)
        else:
            cv.rect(SIDE_D * 0.2, SIDE_D * 0.38, SIDE_D * 0.5, SIDE_D * 0.14, r=SIDE_D * 0.06, height=0.00016, spec=0.3, gloss=0.45)
        key(r, pid, (sx + FLOOR, SIDE_YC, z), normal=(1, 0, 0), up=(0, 0, 1), size=(SIDE_D, SIDE_D), t=0.0017, mat=M.keys,
            corner=SIDE_D / 2, dome=0.00022, bevel=0.0005, canvas=cv, depth=0.0010, shape="round")


def _right_side(r, M):
    """-X side: accessory connector cover (gasket + two knurled thumbscrews) over a rubber grip panel."""
    sx = -W / 2
    n = (-1, 0, 0)
    pw, pz0, pz1 = RPANEL
    r.add(_side_plate(rrect(pw, pz1 - pz0, 0.0040, 6), 0.0012, [], M.grip, [], n, (sx, SIDE_YC, (pz0 + pz1) / 2), "rpanel"))
    cz, cw, chh = ACC
    gasket = r.mat("acc_gasket", color=(18, 19, 21), spec=0.08, gloss=0.16, bump="rubber", bump_amp=0.00002, bump_scale=0.0003,
                   layer="side")
    cover = r.mat("acc_cover", color=(33, 34, 37), spec=0.30, gloss=0.42, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                  grain=0.03, edge=0.6, dirt=0.15, wear_color=(84, 86, 90), layer="side")
    gk = holed_plate(rrect(cw + 0.0013, chh + 0.0013, 0.0032, 6), 0.0005, [], gasket, bevel=0.0002, tag="gasket")
    r.add(align(gk, n, (0, 0, 1), (sx, SIDE_YC, cz)))
    cv = holed_plate(rrect(cw, chh, 0.0026, 6), 0.0016, [], cover, bevel=0.0006, tag="acc_cover")
    r.add(align(cv, n, (0, 0, 1), (sx - 0.0005, SIDE_YC, cz)))
    for dz in (0.0115, -0.0115):
        r.hi_only(thumbscrew(r, (sx - 0.0021, SIDE_YC, cz + dz), n, (0, 0, 1), d=0.0058, h=0.0026))
    lab = DecalCanvas(0.012, 0.014, ppm=40000)
    lab.text(0.006, 0.0036, "ACC", 0.0021, fnt="label-semi", spacing=0.0003, **ink("grey"))
    for k in range(3):
        lab.circle(0.0035 + k * 0.0025, 0.0075, 0.00048, **ink("grey"))
    lab.rect(0.0024, 0.0098, 0.0072, 0.00035, **ink("grey"))
    r.decal(lab, center=(sx - 0.0021, SIDE_YC, cz), normal=n, up=(0, 0, 1), depth=0.001, mats=[cover])


# ---------------------------------------------------------------------------------------------
# back and bottom
# ---------------------------------------------------------------------------------------------
def _battery_label(w, h, pack, chem, volts, cap, wh, serial):
    """Battery label laid out for this pack (no overlaps at 44 x 25 mm): code + chemistry row, capacity row,
    fine print column on the left, handling symbols + barcode on the right, serial at the foot."""
    dc = DecalCanvas(w, h, ppm=36000)
    dc.rect(0, 0, w, h, r=h * 0.05, color=(23, 24, 26), spec=0.34, gloss=0.52)
    dc.rect(0, 0, w * 0.016, h, color=INK["teal"])
    x0, pad = w * 0.05, h * 0.08
    dc.text(x0, h * 0.16, pack, h * 0.13, fnt="label-black", anchor="lm", **ink("white"))
    dc.text(w - pad, h * 0.16, f"{chem}  {volts}", h * 0.09, fnt="label-semi", anchor="rm", **ink("white"))
    dc.text(x0, h * 0.34, f"{cap}   {wh}   RECHARGEABLE", h * 0.068, fnt="label-semi", anchor="lm", max_w=w - x0 - pad, **ink("white"))
    dc.rect(x0, h * 0.425, w - x0 - pad, h * 0.008, color=(84, 87, 91))
    fine = ["Charge only with the matching charger.", "Do not short-circuit, crush,", "open or burn the pack.",
            "Keep away from heat above 60 °C."]
    for k, t in enumerate(fine):
        dc.text(x0, h * (0.51 + k * 0.083), t, h * 0.05, fnt="label-reg", anchor="lm", max_w=w * 0.52, **ink("grey"))
    isz = h * 0.17
    for k, kind in enumerate(("recycle", "bin", "warn")):
        dc.icon(kind, w * 0.63 + k * isz * 1.22, h * 0.47, isz, color=INK["white"] if kind != "warn" else (16, 16, 18))
    dc.barcode(w * 0.6, h * 0.70, w * 0.36, h * 0.24, seed=sum(map(ord, serial)) % 997, color=INK["white"])
    dc.text(x0, h * 0.89, serial, h * 0.055, fnt="mono", anchor="lm", **ink("grey"))
    return dc


def _back_and_bottom(r, M):
    rub = r.mat("latch_rubber", color=(30, 31, 34), spec=0.16, gloss=0.26, bump="rubber", bump_amp=0.00003, bump_scale=0.0004,
                edge=0.4, dirt=0.15, wear_color=(76, 78, 82))
    # black powder-coated spring steel: satin paint (dielectric), bright steel where the edges are worn through
    clip = r.mat("clip_steel", color=(30, 31, 34), spec=0.2, gloss=0.3, metal=0.0, bump="orange_peel", bump_amp=0.000012,
                 bump_scale=0.0009, grain=0.035, grain_scale=0.03, edge=0.5, wear=0.25, wear_color=(128, 130, 134), dirt=0.16,
                 scratch=0.12, smudge=0.3)
    r.add(belt_clip(r, (0.0, BY, CLIP_TOP), normal=(0, -1, 0), up=(0, 0, 1), w=0.032, length=CLIP_LEN, t=0.002, standoff=0.0035,
                    lip=0.008, mat=clip, block_mat=M.soft, screw_kind="phillips"))
    # two stamped stiffening ribs down the clip plate (normal map), seen from behind
    st = DecalCanvas(0.030, 0.046, ppm=16000)
    for x in (0.0105, 0.0195):
        st.groove([(x, 0.002), (x, 0.044)], width=0.0011, depth=0.00028, alpha=0.25)
    r.decal(st, center=(0.0, BY - 0.0045, CLIP_TOP - 0.030), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0025, mats=[clip])
    r.add(latch_tab(r, rub, (0.0, BY, Z0 + 0.0060), (0, -1, 0), (0, 0, 1), w=0.016, h=0.0065, t=0.0013, ribs=5))
    # battery label below the clip
    bl = _battery_label(0.044, 0.025, "PB-74", "Li-ion", "7.4 V", "2250 mAh", "16.7 Wh", "SN B26-40711")
    r.decal(bl, center=(0.0, BY, -0.0175), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.face])
    rel = DecalCanvas(0.03, 0.006, ppm=30000)
    rel.text(0.015, 0.0018, "PUSH TO RELEASE", 0.0013, fnt="label-semi", spacing=0.00015, **ink("grey"))
    rel.glyph("down", 0.015, 0.0043, 0.0016, **ink("grey"))
    r.decal(rel, center=(0.0, BY, Z0 + 0.0125), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[M.face])
    # rating label on the underside of the battery pack (read when the pack is lifted / the radio turned over)
    rl = rating_label(0.040, 0.0100, model="PX-740", serial="SN 26-07412", ident="ID: TXQ-PX740A", rating="7.4 V  2250 mAh  Li-ion",
                      title="TWO-WAY RADIO", foot="IP54", ppm=36000)
    r.decal(rl, center=(0.0, BY + DB / 2, Z0 + 0.0003), normal=(0, 0, -1), up=(0, 1, 0), depth=0.0008, mats=[M.face])
    # bottom of the shell: charging contacts in a moulded recess, polarity marks, lanyard eye in the corner
    cy = FY - DF / 2 + 0.001
    r.hi_only(charging_contacts(r, (0.0035, cy, Z0), (0, 0, -1), (0, 1, 0), n=2, pitch=0.010, size=(0.0045, 0.0028), proud=0.00022))
    pk = DecalCanvas(0.024, 0.010, ppm=30000)
    pk.groove_rect(0.0012, 0.0019, 0.0216, 0.0062, r=0.0016, width=0.00035, depth=0.0002, alpha=0.4)
    pk.text(0.0045, 0.0090, "+", 0.0016, fnt="label-semi", **ink("grey"))
    pk.text(0.0195, 0.0090, "−", 0.0016, fnt="label-semi", **ink("grey"))
    # canvas x runs along world -X when looking up at the bottom with up = +Y: the "+" lands at the left contact
    r.decal(pk, center=(0.0035, cy - 0.0005, Z0), normal=(0, 0, -1), up=(0, 1, 0), depth=0.0008, mats=[M.soft])
    # lanyard eye moulded onto the right flank at the bottom corner (cord threads through vertically)
    r.hi_only(lanyard_eye(r, (-W / 2, YS + 0.0052, Z0 + 0.0052), (-1, 0, 0), up=(0, 0, 1), r=0.0028, wire=0.0011, mat=M.side))


# ---------------------------------------------------------------------------------------------
# top details: antenna, light pipe, prints, screws
# ---------------------------------------------------------------------------------------------
def _whip_profile():
    """(r, z) mm of the whip: ribbed boot collar (4 rings), tapering flexible body, a moulded step, the thin
    upper section and the rounded cap - Ø ~10.3 at the collar, 9 -> 6 mm along the body."""
    prof = [(0.0, 0.0), (5.15, 0.0), (5.15, 0.6)]
    for k in range(4):
        z0 = 1.0 + k * 2.65
        prof += [(5.0, z0), (5.38, z0 + 0.38), (5.38, z0 + 1.55), (5.0, z0 + 1.93)]
    prof += [(4.95, 11.9), (4.72, 12.8), (4.52, 14.6)]
    prof += [(4.45, 26.0), (4.26, 46.0), (4.08, 66.0)]
    prof += [(4.08, 67.4), (4.18, 68.0), (4.18, 69.6), (3.82, 70.6), (3.62, 72.2)]
    prof += [(3.40, 100.0), (3.18, 130.0), (3.02, 150.0)]
    for a in np.linspace(0.0, math.pi / 2, 5):
        prof.append((3.0 * math.cos(a), 152.0 + 3.0 * math.sin(a)))
    prof[-1] = (0.0, 155.0)
    return prof


def _whip(r, base):
    mat = r.mat("antenna_rubber", color=(23, 24, 26), spec=0.22, gloss=0.34, bump="rubber", bump_amp=0.00003, bump_scale=0.0006,
                grain=0.03, grain_scale=0.02, edge=0.3, dirt=0.12, wear_color=(66, 68, 72))
    prof = [(a * 0.001, z * 0.001) for a, z in _whip_profile()]
    g = lathe(prof, mat, segs=22, smooth_angle=50, tag="antenna_whip")
    # band identification sleeve: a thin teal ring moulded into the body just above the collar
    teal = r.mat("antenna_band", color=(26, 104, 98), spec=0.3, gloss=0.42, grain=0.03, edge=0.3, dirt=0.2, wear_color=(70, 140, 134))
    zb0, zb1 = 0.0200, 0.0222
    rb = 0.00466
    g += lathe([(0.00447, zb0 - 0.0001), (rb, zb0), (rb, zb1), (0.00446, zb1 + 0.0001)], teal, segs=22, smooth_angle=50,
               tag="antenna_band")
    return g.translate(base[0], base[1], base[2])


def _top_details(r, M):
    nut_z = ZT + 0.0015
    r.add(sma_nut(r, (ANT_XY[0], ANT_XY[1], nut_z), across=0.008, h=NUT_H, finish="nickel", barrel_h=0.003))
    r.add(_whip(r, (ANT_XY[0], ANT_XY[1], nut_z + NUT_H)))
    pipe, insert = light_pipe(r, (LED_XY[0], LED_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), d=0.003, color="white")
    # frosted light-pipe lens (reads as a lens, not a hole, while no LED insert sits on it)
    frost = r.mat("pipe_frost", color=(120, 126, 132), spec=0.55, gloss=0.62, grain=0.02, edge=0.1, ao=0.6, smudge=0.2)
    for c in pipe.charts:
        if c.tag.startswith("pipe_lens"):
            c.mat = frost
    r.add(pipe)
    # deck prints: growing volume dots in front of the volume knob, channel ticks round the channel knob
    S = 0.028
    dc = DecalCanvas(S, S, ppm=30000)
    n = 8
    for k in range(n):
        th = math.radians(-62 + 124 * k / (n - 1))
        dX, dY = -math.sin(th) * 0.0099, math.cos(th) * 0.0099
        dc.circle(S / 2 + dX, S / 2 - dY, 0.00028 + 0.00034 * k / (n - 1), **ink("white"))
    r.decal(dc, center=(VOL_XY[0], VOL_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0006, mats=[M.face])
    tk = DecalCanvas(S, S, ppm=30000)
    for k in range(16):
        th = 2 * math.pi * k / 16
        r0, r1 = 0.0087, 0.0094 if k % 4 else 0.0099
        tk.line([(S / 2 - math.sin(th) * r0, S / 2 - math.cos(th) * r0), (S / 2 - math.sin(th) * r1, S / 2 - math.cos(th) * r1)],
                0.00026, **ink("grey"))
    r.decal(tk, center=(CH_XY[0], CH_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0006, mats=[M.face])
    # moulded locating ring round the light pipe (normal map only)
    lp = DecalCanvas(0.008, 0.008, ppm=30000)
    lp.groove([(0.004 + 0.0029 * math.cos(a), 0.004 + 0.0029 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 41)[:-1]],
              width=0.0003, depth=0.00015, alpha=0.3, closed=True)
    r.decal(lp, center=(LED_XY[0], LED_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0006, mats=[M.face])
    # two Torx screws holding the deck
    for p in ((0.0215, -0.0125, ZT), (0.0075, -0.0135, ZT)):
        r.hi_only(screw(r, p, (0, 0, 1), (0, 1, 0), d=0.0028, kind="torx", color=(122, 125, 131), segs=14))
    return np.asarray(insert, np.float64)


# ---------------------------------------------------------------------------------------------
# medium LOD (6 m -> lodDist): cheap stand-ins flagged 'm', the detailed geometry flagged 'h'
# ---------------------------------------------------------------------------------------------
MED_DENSITY = 0.3      # stand-ins barely need texels - keep the atlases for the high model


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

    # housing
    sh = extrude(_outline(W, DF, CHAMF, 0.0, FIL, 0.0006, n=2), ZD - Z0, M.soft, bevel=0.0009, bevel_seg=1, z0=Z0, smooth_angle=50,
                 tag="m_shell").translate(0, FY - DF / 2, 0)
    add_m(_set_mat(_hide(_planar_uv(split_by_normal(sh)), (":-y", ":+z"), 0.2), M.side, (":+x", ":-x")))
    ins = 0.0004
    bt = extrude(_outline(W - 2 * ins, DB, 0.0, CHAMF - ins, 0.0006, FIL, n=2), ZD - 0.0005 - (Z0 + 0.0003), M.soft, bevel=0.0010,
                 bevel_seg=1, z0=Z0 + 0.0003, smooth_angle=50, tag="m_battery").translate(0, BY + DB / 2, 0)
    bt = _hide(_planar_uv(split_by_normal(bt)), (":+y", ":+z"), 0.2)
    _set_mat(bt, M.side, (":+x", ":-x"))
    _set_mat(bt, M.face, (":-y", ":-z"))
    add_m(bt)
    add_m(extrude(_outline(W, D, CHAMF, CHAMF, FIL, FIL, n=2), DECK, M.face, bevel=0.0009, bevel_seg=1, z0=ZD, smooth_angle=50,
                  tag="m_deck"))
    # bezel with the grille / mic / screen openings only - the key stand-ins stand on its face
    mesh = m_mesh(r)
    holes, fl = _bezel_holes(M, mesh, m_print_dark(r), keys=False)
    g = holed_plate(rrect(PW, PZ1 - PZ0, 0.0042, 3), PT, holes, M.bezel, depth=PT - FLOOR, wall_mat=M.soft, floor_mats=fl, bevel=0.00045,
                    hole_bevel=0.0, corner_n=2, tag="m_bezel")
    g += _grille_bars(M.bezel, PT + 0.00022 - FLOOR, rounded=False)
    add_m(_front(g, PZC))
    # keys, soft keys, d-pad: plain blocks standing out of the bezel face
    yb = FY + PT

    def front_block(pid, X, Z, w, h, t, rot=0.0):
        blk = box((w, h, t), M.keys, r=min(w, h) * 0.22, seg=1, faces="+x -x +y -y +z", tag="m_key")
        if rot:
            blk.rotate(0, 0, rot)
        add_m(align(blk.translate(0, 0, t / 2), (0, 1, 0), (0, 0, 1), (X, yb + float(crown(X)) - 0.0003, Z)), part=pid)

    for pid, X, Z, lg, sub in _keypad_cells():
        front_block(pid, X, Z, KEY[0], KEY[1], KEY_T - PT + 0.0006)
    for pid, (X, Z, w, h, cr) in CLUSTER.items():
        front_block(pid, X, Z, w, h, 0.0019 - PT + 0.0006)
    s = DPAD_SIZE / math.sqrt(2)
    front_block("dpad", 0.0, CL_Z, s, s, 0.0024 - PT + 0.0008, rot=45)
    # knobs, emergency key
    knob_m = r.mat("knob_ch_black")
    add_m(cylinder(CH_D / 2, CH_H + BOSS_H, knob_m, segs=16, bevel=0.0006, bevel_seg=1, caps=(False, True), tag="m_knob")
          .translate(CH_XY[0], CH_XY[1], ZT), part="knob_ch")
    add_m(cylinder(VOL_D / 2, VOL_H + BOSS_H, "knob_knurl", segs=16, bevel=0.0006, bevel_seg=1, caps=(False, True), tag="m_knob")
          .translate(VOL_XY[0], VOL_XY[1], ZT), part="knob_vol")
    add_m(box((0.009, 0.006, 0.0006), "emerg_orange", r=0.0008, seg=1, center=(EM_XY[0], EM_XY[1], ZT + 0.0001),
              faces="+x -x +y -y +z", tag="m_emerg"), part="emerg")
    # side parts and panels
    for sx, pw, pz0, pz1 in ((W / 2, *LPANEL), (-W / 2, *RPANEL)):
        add_m(align(extrude(rrect(pw, pz1 - pz0, 0.004, 2), 0.0012, M.grip, bevel=0.0004, bevel_seg=1, caps=(False, True), tag="m_panel"),
                    (np.sign(sx), 0, 0), (0, 0, 1), (sx, SIDE_YC, (pz0 + pz1) / 2)))
    sx = W / 2 + 0.0012
    add_m(align(box((PTT_W, PTT_L, 0.0016), M.keys, r=0.003, seg=1, faces="+x -x +y -y +z", tag="m_ptt").translate(0, 0, 0.0008),
                (1, 0, 0), (0, 0, 1), (sx, SIDE_YC, PTT_Z)), part="ptt")
    for pid, z in zip(("side1", "side2"), SIDE_Z):
        add_m(align(cylinder(SIDE_D / 2, 0.0006, M.keys, segs=10, caps=(False, True), tag="m_side"), (1, 0, 0), (0, 0, 1),
                    (sx, SIDE_YC, z)), part=pid)
    cz, cw, chh = ACC
    add_m(align(extrude(rrect(cw, chh, 0.0026, 2), 0.0021, "acc_cover", bevel=0.0005, bevel_seg=1, caps=(False, True), tag="m_acc"),
                (-1, 0, 0), (0, 0, 1), (-W / 2, SIDE_YC, cz)))
    # antenna (8 sides, collar + taper + cap), nut, belt clip plate
    prof = [(0.0, 0.0), (0.0052, 0.0), (0.0053, 0.0115), (0.0045, 0.0146), (0.0041, 0.066), (0.0036, 0.072), (0.0030, 0.152),
            (0.0018, 0.1545), (0.0, 0.155)]
    add_m(lathe(prof, "antenna_rubber", segs=8, smooth_angle=50, tag="antenna_m").translate(ANT_XY[0], ANT_XY[1], ZT + 0.0015 + NUT_H))
    hexo = np.array([(0.004 / math.cos(math.radians(30)) * math.cos(math.radians(30 + 60 * k)),
                      0.004 / math.cos(math.radians(30)) * math.sin(math.radians(30 + 60 * k))) for k in range(6)])
    add_m(extrude(hexo, NUT_H + 0.0015, "sma_nickel", caps=(False, True), smooth_angle=20, tag="m_nut")
          .translate(ANT_XY[0], ANT_XY[1], ZT))
    clip = box((0.032, CLIP_LEN, 0.002), "clip_steel", r=0.0008, seg=1, faces="+x -x +y -y +z -z", tag="m_clip")
    clip.translate(0, -CLIP_LEN / 2 + 0.002, 0.0045)
    clip += box((0.036, 0.012, 0.004), M.soft, r=0.001, seg=1, center=(0, 0.002, 0.002), faces="+x -x +y -y +z", tag="m_clip")
    add_m(align(clip, (0, -1, 0), (0, 0, 1), (0.0, BY, CLIP_TOP)))


__all__ = ["handheld"]
