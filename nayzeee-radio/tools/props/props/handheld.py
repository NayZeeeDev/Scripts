"""
PX-740 PATROL - police portable handheld (PROPS_BRIEF section 1, SPEC section 9).

Models (radio kit): nzr_handheld (complete, idle screen), nzr_handheld_body (no pressable parts, live
screen placeholder) and one nzr_handheld_<part> per SPEC 9.2 part id. Generic labelling only - model code
PX-740, the word PATROL, a battery label and a rating label with fictitious identifiers (Rule B: no
NAYZEEE name or mark, no real maker).

Construction (metres, +X = viewer's left, +Y = front, +Z up, origin = grip point 40 % up the body):
    front shell     58 x 24 mm plan, front corners chamfered 3 mm + filleted, front face crowned 0.5 mm
    battery pack    the rear 13.4 mm, its own moulding behind a 0.6 mm seam (inset 0.4 mm at the sides),
                    ribbed release latch at the bottom centre, belt clip, battery + rating labels
    top deck        3 mm cap over both with a moulded parting line, two raised knob bosses (D-shafts),
                    a recessed emergency pocket, a light-pipe socket and a raised SMA antenna seat
    front bezel     one 1.2 mm moulding over the front: speaker slots (4 raised bars over acoustic mesh),
                    mic port, screen window (36 x 27 mm LCD, 1 mm bezel, smoked glass), the soft-key
                    cluster wells (P1 / P2 / OK / back, round d-pad well) and the 4 x 3 keypad wells
    sides           left: rubber grip panel with the PTT and two side-button wells; right: accessory
                    connector cover on a gasket with two knurled thumbscrews over a rubber grip panel
    bottom          gold charging contacts, moulded lanyard eye
Every pressable part (SPEC 9.2) is its own part block with full metadata.
"""
from __future__ import annotations

import math
from dataclasses import replace as dc_replace

import numpy as np

from nzprops import DecalCanvas, Geo, box, cylinder, extrude, lathe, poly_cap, quad, rrect, split_by_normal, vec, well_plate
from nzprops.mesh import Chart, ensure_ccw, offset_poly, subdivide_poly

from .common import align, screw
from .radio_common import (INK, battery_label, belt_clip, boss, charging_contacts, densify, dpad, ink, key, knob, lanyard_eye,
                           latch_tab, light_pipe, m_grip_rubber, m_keypad_rubber, m_mesh, m_print_dark, m_smoked_glass,
                           m_soft_black, model_print, ptt, rating_label, sma_nut, thumbscrew)
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
PW, PZ0, PZ1 = 0.048, -0.0505, 0.0735  # bezel width, bottom, top
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
KEY_PITCH = (0.0142, 0.0090)
KEY_ROW0 = -0.0180                     # first keypad row centre
KGAP = 0.00045                         # cap to well wall

# top deck layout (world X / Y)
CH_XY = (0.0170, 0.0030)
VOL_XY = (-0.0015, 0.0035)
ANT_XY = (-0.0175, -0.0055)
EM_XY = (-0.0185, 0.0115)
LED_XY = (-0.0085, -0.0115)

# sides
SIDE_YC = 0.0055                       # centre of the flat side faces of the front shell
PTT_Z = 0.0270


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


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def _mats(r):
    soft = m_soft_black(r)
    face = r.mat_from("px_face", dc_replace(r.mats[soft], layer="face"))
    well = r.mat("px_well", color=(16, 17, 19), spec=0.12, gloss=0.22, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                 grain=0.02, edge=0.2, ao=1.0, cavity=0.8)
    grip = m_grip_rubber(r, "knurl", tone=(25, 26, 28), scale=0.00105, amp=0.0001)
    keys = m_keypad_rubber(r, "black")
    return soft, face, well, grip, keys


# ---------------------------------------------------------------------------------------------
# the radio
# ---------------------------------------------------------------------------------------------
@radio("handheld", title="PX-740 patrol handheld", code="PX-740", layers={"face": 1024}, maps={"face": {"n": 512, "s": 512}},
       doc={"screen": "nzr_scr 512 x 384 behind smoked glass, visible LCD 36 x 27 mm (layout screen.size)"})
def handheld(r):
    soft, face, well, grip, keys = _mats(r)
    _shell_and_battery(r, soft, face)
    _deck(r, soft, face)
    _front_bezel(r, soft, face, well)
    _front_parts(r, keys)
    _top_parts(r)
    _left_side(r, soft, grip, well, keys)
    _right_side(r, soft, grip)
    _back_and_bottom(r, soft, face)
    insert = _top_details(r, soft, face)
    densify(r, 1.6, tags=["shell"], mats=[soft])
    r.anchor(focus=(0.0, FY + 0.0015, 0.004), camDist=0.34, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422): palm on the battery / belt clip, fingers round the right side, thumb on the left "
                  "PTT; screen faces the camera when raised. Tune with /radiogrip.")


# ---------------------------------------------------------------------------------------------
# housing: front shell, battery pack, top deck
# ---------------------------------------------------------------------------------------------
def _shell_and_battery(r, soft, face):
    # front shell: subdivided outline so the crown deform stays smooth on caps and walls alike
    ol = subdivide_poly(_outline(W, DF, CHAMF, 0.0, FIL, 0.0006, n=4), 0.0025)
    g = extrude(ol, ZD - Z0, soft, bevel=0.0009, bevel_seg=3, z0=Z0, smooth_angle=50, tag="shell")
    g.translate(0, FY - DF / 2, 0)
    yc = FY - DF / 2

    def fn(p):
        q = p.copy()
        w = np.clip((p[:, 1] - yc) / (DF / 2), 0, 1) ** 4
        q[:, 1] = p[:, 1] + crown(p[:, 0]) * w
        return q
    g.deform(fn)
    r.add(split_by_normal(g))
    # battery pack: 0.4 mm narrower, square-ish front corners against the shell, chamfered back corners
    ins = 0.0004
    ob = _outline(W - 2 * ins, DB, 0.0, CHAMF - ins, 0.0006, FIL, n=4)
    bt = extrude(ob, ZD - 0.0005 - (Z0 + 0.0003), soft, bevel=0.0010, bevel_seg=3, z0=Z0 + 0.0003, smooth_angle=50, tag="battery")
    bt.translate(0, BY + DB / 2, 0)
    bt = split_by_normal(bt)
    for c in bt.charts:
        if c.tag.endswith(":-y"):
            c.mat = face          # the labelled back gets the print atlas
    r.add(bt)


def _deck(r, soft, face):
    """3 mm top deck over shell + battery: emergency pocket and light-pipe socket are real wells."""
    ol = _outline(W, D, CHAMF, CHAMF, FIL, FIL, n=4)
    holes = [(EM_XY[0], EM_XY[1], 0.0045 + 0.0005, 0.003 + 0.0005, 0.0017, 0.0025),
             (LED_XY[0], LED_XY[1], 0.0015, 0.0015, 0.0015, 0.0004)]
    dk = holed_plate(ol, DECK, holes, face, wall_mat=soft, floor_mats=[soft, soft], bevel=0.0009, hole_bevel=0.0003, tag="deck")
    dk += poly_cap(ol, 0.0, soft, up=False, tag="deck:bottom")
    r.add(dk.translate(0, 0, ZD))
    # raised knob bosses with D-shaft stubs (seen on the body model once the knobs are pulled off)
    shaft = r.mat("shaft_steel", color=(150, 152, 156), spec=0.7, gloss=0.55, metal=1.0, bump="brushed", bump_amp=0.000005,
                  bump_scale=0.0003, edge=0.3)
    r.add(boss(r, soft, (CH_XY[0], CH_XY[1], ZT), d=0.0150, h=0.0020, shaft_d=0.0060, shaft_h=0.0060, shaft_mat=shaft))
    r.add(boss(r, soft, (VOL_XY[0], VOL_XY[1], ZT), d=0.0160, h=0.0020, shaft_d=0.0060, shaft_h=0.0055, shaft_mat=shaft))
    # antenna seat: low moulded ring + rubber gasket under the nut
    r.add(cylinder(0.0058, 0.0010, soft, segs=36, bevel=0.0004, bevel_seg=2, caps=(False, True)).translate(ANT_XY[0], ANT_XY[1], ZT))
    gasket = r.mat("ant_gasket", color=(20, 21, 23), spec=0.1, gloss=0.18, bump="rubber", bump_amp=0.00002, bump_scale=0.0003)
    r.add(cylinder(0.0049, 0.0005, gasket, segs=32, bevel=0.0002, bevel_seg=1, caps=(False, True)).translate(ANT_XY[0], ANT_XY[1],
                                                                                                             ZT + 0.0010))


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


def _front_bezel(r, soft, face, well):
    mesh = m_mesh(r)
    bezel_black = m_print_dark(r)
    holes, fl = [], []

    def hole(X, Z, hw, hh, rad, floor, depth=None):
        h = (-X, Z - PZC, hw, hh, rad)
        holes.append(h + ((depth,) if depth is not None else ()))
        fl.append(floor)

    gx, gz, gw, gh = GRILLE
    hole(gx, gz, gw / 2, gh / 2, 0.0026, mesh)
    hole(0.0, MIC_Z, 0.0006, 0.0006, 0.0006, mesh)
    hole(0.0, SCR_Z, VIEW[0] / 2 + BEZEL, VIEW[1] / 2 + BEZEL, 0.0014, bezel_black)
    hole(0.0, CL_Z, DPAD_R, DPAD_R, DPAD_R, well)
    for pid, (X, Z, w, h, cr) in CLUSTER.items():
        hole(X, Z, w / 2 + KGAP, h / 2 + KGAP, cr + KGAP, well)
    for pid, X, Z, lg, sub in _keypad_cells():
        hole(X, Z, KEY[0] / 2 + KGAP, KEY[1] / 2 + KGAP, KEY[1] * 0.28 + KGAP, well)
    outline = rrect(PW, PZ1 - PZ0, 0.0042, 6)
    g = holed_plate(outline, PT, holes, face, depth=PT - FLOOR, wall_mat=soft, floor_mats=fl, bevel=0.00045, hole_bevel=0.00028,
                    tag="bezel")
    # speaker bars: 4 rounded bars standing a hair proud of the bezel over the acoustic mesh
    n = 4
    bar_h = 0.0030
    gap = (gh - n * bar_h) / (n + 1)
    bt = PT + 0.00022 - FLOOR
    for k in range(n):
        zc = gz + gh / 2 - gap - bar_h / 2 - k * (bar_h + gap)
        g += box((gw - 0.0004, bar_h, bt), soft, r=0.00055, seg=2, center=(-gx, zc - PZC, FLOOR + bt / 2), faces="+x -x +y -y +z",
                 tag="grille_bar")
    r.add(_front(g, PZC))
    # screen (fixed UV, layout anchor) on the bezel floor + smoked glass 0.3 mm above it
    yf = FY + float(crown(0.0)) + FLOOR
    r.screen(quad((0.0, yf + 0.00006, SCR_Z), (-1, 0, 0), (0, 0, 1), VIEW[0], VIEW[1], "x", fixed_uv=True))
    r.add(quad((0.0, yf + 0.00036, SCR_Z), (-1, 0, 0), (0, 0, 1), VIEW[0] + 2 * BEZEL - 0.0002, VIEW[1] + 2 * BEZEL - 0.0002,
               m_smoked_glass(r), tag="glass"))
    # prints on the bezel (print atlas): model code strip, a tiny ingress badge, the mic port ring
    ytop = FY + CROWN + PT
    mp = model_print("PX-740", "PATROL", w=0.030, h=0.0080, rule_color="teal", align_="center")
    r.decal(mp, center=(0.0, ytop, PRINT_Z), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])
    badge = DecalCanvas(0.0075, 0.0034, ppm=40000)
    badge.rect(0.0002, 0.0002, 0.0071, 0.0030, r=0.0006, fill=False, width=0.00022, **ink("grey"))
    badge.text(0.00375, 0.0017, "IP54", 0.0015, fnt="label-semi", **ink("grey"))
    r.decal(badge, center=(-0.0185, ytop, PRINT_Z + 0.0006), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])
    band = DecalCanvas(0.0075, 0.0034, ppm=40000)
    band.text(0.00375, 0.0017, "UHF", 0.0015, fnt="label-semi", **ink("grey"))
    r.decal(band, center=(0.0185, ytop, PRINT_Z + 0.0006), normal=(0, 1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])


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


def _front_parts(r, keys):
    for pid, X, Z, lg, sub in _keypad_cells():
        at = (X, y_face(X) + FLOOR, Z)
        cv = _key_legend(KEY[0] * 0.92, KEY[1] * 0.88, lg, sub)
        key(r, pid, at, (0, 1, 0), (0, 0, 1), size=KEY, t=0.0020, mat=keys, corner=KEY[1] * 0.28, dome=0.00028, bevel=0.0006,
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
        key(r, pid, at, (0, 1, 0), (0, 0, 1), size=(w, h), t=0.0019, mat=keys, corner=cr, dome=0.00025, bevel=0.0006, canvas=cv,
            depth=0.0012)
    dpad(r, "dpad", at=(0.0, y_face(0.0) + FLOOR, CL_Z), normal=(0, 1, 0), up=(0, 0, 1), size=0.0160, kind="diamond",
         t=0.0024, mat=keys, arrows="print", tilt=5.0, depth=0.0010, dome=0.0004)


# ---------------------------------------------------------------------------------------------
# top: knobs, emergency key
# ---------------------------------------------------------------------------------------------
def _top_parts(r):
    knob(r, "knob_ch", base=(CH_XY[0], CH_XY[1], ZT + 0.0020), axis=(0, 0, 1), front=(0, 1, 0), d=0.012, h=0.014, style="ribbed",
         ribs=16, skirt=True, skirt_d=0.0142, skirt_h=0.0018, index="line", value="channel", detents=16, segs=64)
    knob(r, "knob_vol", base=(VOL_XY[0], VOL_XY[1], ZT + 0.0020), axis=(0, 0, 1), front=(0, 1, 0), d=0.013, h=0.012,
         style="knurled", skirt=True, skirt_d=0.0150, skirt_h=0.0016, index="dot", value="volume", detents=24, segs=48)
    orange = r.mat("emerg_orange", color=(238, 106, 24), spec=0.34, gloss=0.48, bump="dimple", bump_amp=0.00004, bump_scale=0.00062,
                   grain=0.03, edge=0.45, dirt=0.12, wear_color=(250, 170, 110))
    key(r, "emerg", (EM_XY[0], EM_XY[1], ZD + DECK - 0.0025), normal=(0, 0, 1), up=(0, 1, 0), size=(0.009, 0.006), t=0.0022,
        mat=orange, corner=0.0012, dome=0.00018, bevel=0.0005, depth=0.0012)


# ---------------------------------------------------------------------------------------------
# sides
# ---------------------------------------------------------------------------------------------
def _side_plate(outline, t, holes, mat, floor_mats, normal, at, tag):
    g = holed_plate(outline, t, holes, mat, depth=t - FLOOR, wall_mat=mat, floor_mats=floor_mats, bevel=0.0004,
                    hole_bevel=0.00025, tag=tag)
    return align(g, normal, (0, 0, 1), at)


def _left_side(r, soft, grip, well, keys):
    """+X side: rubber grip panel with the PTT and two side-button wells."""
    sx = W / 2
    pw, pz0, pz1 = 0.0175, -0.0410, 0.0490
    pzc = (pz0 + pz1) / 2
    # panel local x = world +Y (towards the front), y = world Z
    ptt_w, ptt_l = 0.012, 0.030
    s_d = 0.006
    side_z = (0.0030, -0.0075)
    holes = [(0.0, PTT_Z - pzc, ptt_w / 2 + 0.0005, ptt_l / 2 + 0.0005, ptt_w * 0.42 + 0.0005)]
    holes += [(0.0, z - pzc, s_d / 2 + 0.0004, s_d / 2 + 0.0004, s_d / 2 + 0.0004) for z in side_z]
    r.add(_side_plate(rrect(pw, pz1 - pz0, 0.0040, 6), 0.0012, holes, grip, [well, well, well], (1, 0, 0), (sx, SIDE_YC, pzc),
                      "lpanel"))
    ptt(r, "ptt", at=(sx + FLOOR, SIDE_YC, PTT_Z), normal=(1, 0, 0), up=(0, 0, 1), length=ptt_l, width=ptt_w, t=0.0026,
        ridges=5, ridge_h=0.00045, mat=keys, emboss="PTT", depth=0.0016, dome=0.0005)
    for pid, z, mark in (("side1", side_z[0], "dot"), ("side2", side_z[1], "bar")):
        cv = DecalCanvas(s_d * 0.9, s_d * 0.9, ppm=60000)
        if mark == "dot":
            cv.circle(s_d * 0.45, s_d * 0.45, s_d * 0.11, height=0.00016, spec=0.3, gloss=0.45)
        else:
            cv.rect(s_d * 0.2, s_d * 0.38, s_d * 0.5, s_d * 0.14, r=s_d * 0.06, height=0.00016, spec=0.3, gloss=0.45)
        key(r, pid, (sx + FLOOR, SIDE_YC, z), normal=(1, 0, 0), up=(0, 0, 1), size=(s_d, s_d), t=0.0017, mat=keys, corner=s_d / 2,
            dome=0.00022, bevel=0.0005, canvas=cv, depth=0.0010, shape="round")


def _right_side(r, soft, grip):
    """-X side: accessory connector cover (gasket + two knurled thumbscrews) over a rubber grip panel."""
    sx = -W / 2
    n = (-1, 0, 0)
    # grip panel
    pz0, pz1 = -0.0410, 0.0085
    r.add(_side_plate(rrect(0.0175, pz1 - pz0, 0.0040, 6), 0.0012, [], grip, [], n, (sx, SIDE_YC, (pz0 + pz1) / 2), "rpanel"))
    # accessory connector cover on a rubber gasket
    cz, cw, chh = 0.0305, 0.0135, 0.0330
    gasket = r.mat("acc_gasket", color=(18, 19, 21), spec=0.08, gloss=0.16, bump="rubber", bump_amp=0.00002, bump_scale=0.0003)
    cover = r.mat("acc_cover", color=(33, 34, 37), spec=0.30, gloss=0.42, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                  grain=0.03, edge=0.6, dirt=0.15, wear_color=(84, 86, 90))
    gk = holed_plate(rrect(cw + 0.0013, chh + 0.0013, 0.0032, 6), 0.0005, [], gasket, bevel=0.0002, tag="gasket")
    r.add(align(gk, n, (0, 0, 1), (sx, SIDE_YC, cz)))
    cv = holed_plate(rrect(cw, chh, 0.0026, 6), 0.0016, [], cover, bevel=0.0006, tag="acc_cover")
    r.add(align(cv, n, (0, 0, 1), (sx - 0.0005, SIDE_YC, cz)))
    for dz in (0.0115, -0.0115):
        r.add(thumbscrew(r, (sx - 0.0021, SIDE_YC, cz + dz), n, (0, 0, 1), d=0.0058, h=0.0026))
    lab = DecalCanvas(0.012, 0.012, ppm=30000)
    lab.text(0.006, 0.0032, "ACC", 0.0016, fnt="label-semi", spacing=0.0002, **ink("grey"))
    for k in range(3):
        lab.circle(0.0035 + k * 0.0025, 0.0072, 0.00045, **ink("grey"))
    lab.rect(0.0022, 0.0094, 0.0076, 0.0003, **ink("grey"))
    r.decal(lab, center=(sx - 0.0021, SIDE_YC, cz), normal=n, up=(0, 0, 1), depth=0.001, mats=[cover])


# ---------------------------------------------------------------------------------------------
# back and bottom
# ---------------------------------------------------------------------------------------------
def _back_and_bottom(r, soft, face):
    rub = r.mat("latch_rubber", color=(30, 31, 34), spec=0.16, gloss=0.26, bump="rubber", bump_amp=0.00003, bump_scale=0.0004,
                edge=0.4, dirt=0.15, wear_color=(76, 78, 82))
    r.add(belt_clip(r, (0.0, BY, 0.0640), normal=(0, -1, 0), up=(0, 0, 1), w=0.032, length=0.058, t=0.002, standoff=0.0035,
                    lip=0.008, block_mat=soft, screw_kind="phillips"))
    r.add(latch_tab(r, rub, (0.0, BY, Z0 + 0.0060), (0, -1, 0), (0, 0, 1), w=0.016, h=0.0065, t=0.0013, ribs=5))
    # battery label below the clip, rating label behind the clip (visible past its edges)
    bl = battery_label(0.044, 0.025, pack="PB-74", chem="Li-ion", volts="7.4 V", cap="2250 mAh", serial="SN B26-40711",
                       ppm=30000)
    r.decal(bl, center=(0.0, BY, -0.0175), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])
    rl = rating_label(0.034, 0.013, model="PX-740", serial="SN 26-07412", ident="ID: TXQ-PX740A", rating="7.4 V  2250 mAh  Li-ion",
                      title="TWO-WAY RADIO", foot="IP54", ppm=30000)
    r.decal(rl, center=(0.0, BY, 0.0300), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])
    rel = DecalCanvas(0.03, 0.006, ppm=30000)
    rel.text(0.015, 0.0018, "PUSH TO RELEASE", 0.0013, fnt="label-semi", spacing=0.00015, **ink("grey"))
    rel.glyph("down", 0.015, 0.0043, 0.0016, **ink("grey"))
    r.decal(rel, center=(0.0, BY, Z0 + 0.0125), normal=(0, -1, 0), up=(0, 0, 1), depth=0.0012, mats=[face])
    # bottom: charging contacts on the shell, lanyard eye moulded into the right-hand corner
    r.hi_only(charging_contacts(r, (0.0035, FY - DF / 2 + 0.001, Z0), (0, 0, -1), (0, 1, 0), n=2, pitch=0.010,
                                size=(0.0045, 0.0028), proud=0.00022))
    r.add(lanyard_eye(r, (-W / 2 + 0.0058, FY - DF / 2 + 0.0005, Z0), (0, 0, -1), up=(1, 0, 0), r=0.0030, wire=0.0011, mat=soft))


# ---------------------------------------------------------------------------------------------
# top details: antenna, light pipe, prints, screws
# ---------------------------------------------------------------------------------------------
def _whip(r, base):
    mat = r.mat("antenna_rubber", color=(23, 24, 26), spec=0.22, gloss=0.34, bump="rubber", bump_amp=0.00003, bump_scale=0.0006,
                grain=0.03, grain_scale=0.02, edge=0.3, dirt=0.12, wear_color=(66, 68, 72))
    prof = [(0.0, 0.0), (5.15, 0.0), (5.15, 0.6)]
    for k in range(4):
        z0 = 1.0 + k * 2.65
        prof += [(5.0, z0), (5.38, z0 + 0.38), (5.38, z0 + 1.55), (5.0, z0 + 1.93)]
    prof += [(4.95, 11.9), (4.72, 12.8), (4.52, 14.6)]
    prof += [(4.45, 26.0), (4.32, 40.0), (4.18, 54.0), (4.08, 66.0)]
    prof += [(4.08, 67.4), (4.18, 68.0), (4.18, 69.6), (3.82, 70.6), (3.62, 72.2)]
    prof += [(3.48, 90.0), (3.33, 110.0), (3.18, 130.0), (3.04, 147.0), (3.0, 152.0)]
    for a in np.linspace(0.25, math.pi / 2, 6):
        prof.append((3.0 * math.cos(a), 152.0 + 3.0 * math.sin(a)))
    prof[-1] = (0.0, 155.0)
    prof = [(a * 0.001, z * 0.001) for a, z in prof]
    g = lathe(prof, mat, segs=22, smooth_angle=50, tag="antenna_whip")
    return g.translate(base[0], base[1], base[2])


def _top_details(r, soft, face):
    nut_z = ZT + 0.0015
    r.add(sma_nut(r, (ANT_XY[0], ANT_XY[1], nut_z), across=0.008, h=0.0035, finish="nickel", barrel_h=0.003))
    r.add(_whip(r, (ANT_XY[0], ANT_XY[1], nut_z + 0.0035)))
    pipe, insert = light_pipe(r, (LED_XY[0], LED_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), d=0.003, color="white")
    r.add(pipe)
    # band print on the antenna collar side facing the front
    ab = DecalCanvas(0.0062, 0.0035, ppm=40000)
    ab.text(0.0031, 0.0011, "403-470", 0.00105, fnt="label-semi", **ink("grey"))
    ab.text(0.0031, 0.0025, "MHz", 0.00095, fnt="label-semi", **ink("grey"))
    r.decal(ab, center=(ANT_XY[0], ANT_XY[1] + 0.0042, nut_z + 0.0035 + 0.019), normal=(0, 1, 0), up=(0, 0, 1), depth=0.002,
            mats=["antenna_rubber"], min_dot=0.5)
    # deck prints: growing volume dots in front of the volume knob, channel ticks round the channel knob
    S = 0.028
    dc = DecalCanvas(S, S, ppm=24000)
    n = 8
    for k in range(n):
        th = math.radians(-62 + 124 * k / (n - 1))
        dX, dY = -math.sin(th) * 0.0099, math.cos(th) * 0.0099
        dc.circle(S / 2 + dX, S / 2 - dY, 0.00028 + 0.00034 * k / (n - 1), **ink("white"))
    r.decal(dc, center=(VOL_XY[0], VOL_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0006, mats=[face])
    tk = DecalCanvas(S, S, ppm=24000)
    for k in range(16):
        th = 2 * math.pi * k / 16
        r0, r1 = 0.0087, 0.0094 if k % 4 else 0.0099
        tk.line([(S / 2 - math.sin(th) * r0, S / 2 - math.cos(th) * r0), (S / 2 - math.sin(th) * r1, S / 2 - math.cos(th) * r1)],
                0.00026, **ink("grey"))
    r.decal(tk, center=(CH_XY[0], CH_XY[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0006, mats=[face])
    # two Torx screws holding the deck
    for p in ((0.0215, -0.0125, ZT), (0.0075, -0.0135, ZT)):
        r.hi_only(screw(r, p, (0, 0, 1), (0, 1, 0), d=0.0030, kind="torx", color=(58, 60, 64), segs=14))
    return np.asarray(insert, np.float64)


__all__ = ["handheld"]
