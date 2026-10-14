"""
Cases and containers: trauma kit case (closed / open), sharps bin.
(The medic bag is an imported model: see tools/props/external/ and import_model.py.)
"""
from __future__ import annotations

import numpy as np

from nzprops import (TEAL_HI, WHITE, DecalCanvas, Geo, box, catmull, cylinder, extrude, lathe, pocket, polyline_fillet, prop,
                     rrect, slab_with_holes, sweep, torus, tube, vec)

from .common import (align, asset_tag, biohazard, caution_label, cross_mark, hinge, label_canvas, m_black_plastic,
                     m_case_grey, m_foam, m_grip, m_rubber, m_steel, m_teal, rating_plate, screws)
from .handheld import iodrill_geo, syringe_geo

# ---------------------------------------------------------------------------------------------
# trauma kit case
# ---------------------------------------------------------------------------------------------
CL, CD = 0.600, 0.430          # shell footprint (X, Y)
CR = 0.032                      # corner radius of the outline
Z_SEAM = 0.125                 # base / lid split height (from the ground)
LID_H = 0.072
FOOT = 0.006


def _outline_path(w, d, r, z, n=5):
    lp = rrect(w, d, r, n)
    return np.stack([lp[:, 0], lp[:, 1], np.full(len(lp), z)], axis=1)


def _case_latch(b, x, y_face):
    """Teal over-centre latch spanning the seam on the front face (+Y)."""
    teal = m_teal(b)
    grey = m_case_grey(b)
    steel = m_steel(b)
    g = Geo()
    prof = np.array([(-0.034, -0.040), (0.034, -0.040), (0.030, 0.034), (0.022, 0.040), (-0.022, 0.040), (-0.030, 0.034)])
    body = extrude(prof, 0.013, teal, bevel=0.004, bevel_seg=2, smooth_angle=50)
    body.rotate(-90, 0, 0)          # extrude axis Z -> +Y (out of the face) ; profile y -> -Z
    g += body.translate(x, y_face + 0.003, Z_SEAM - 0.004)
    # grip lip at the bottom of the latch
    g += box((0.064, 0.010, 0.008), teal, r=0.003, seg=2, center=(x, y_face + 0.014, Z_SEAM - 0.043))
    # hinge barrel on the base and catch on the lid
    g += cylinder(0.006, 0.074, grey, segs=16, bevel=0.0015, z0=-0.037).rotate(0, 90, 0).translate(x, y_face + 0.007, Z_SEAM - 0.034)
    g += box((0.05, 0.016, 0.012), grey, r=0.004, seg=2, center=(x, y_face + 0.006, Z_SEAM + 0.043))
    g += cylinder(0.0028, 0.078, steel, segs=10, z0=-0.039).rotate(0, 90, 0).translate(x, y_face + 0.007, Z_SEAM - 0.034)
    for sx in (-1, 1):
        g += cylinder(0.0042, 0.0016, steel, segs=12, bevel=0.0005, bevel_seg=1).rotate(0, 90 * sx, 0).translate(
            x + sx * 0.0372, y_face + 0.007, Z_SEAM - 0.034)
    # padlock eye beside the latch (base + lid tabs with holes)
    for dz, zz in ((-1, Z_SEAM - 0.012), (1, Z_SEAM + 0.012)):
        g += box((0.012, 0.012, 0.022), grey, r=0.003, seg=2, center=(x + 0.05, y_face + 0.004, zz))
    g += torus(0.0042, 0.0012, steel, segs=14, tube_segs=6).rotate(0, 90, 0).translate(x + 0.05, y_face + 0.0115, Z_SEAM)
    return g


def _case_hardware(b, open_lid=False):
    """Base shell details shared by both variants: feet, side ribs, handle, latches (closed only)."""
    grey = m_case_grey(b)
    rub = m_rubber(b)
    grip = m_grip(b)
    g = Geo()
    for sx in (-1, 1):
        for sy in (-1, 1):
            g += cylinder(0.022, FOOT + 0.002, rub, segs=20, bevel=0.002).translate(sx * 0.24, sy * 0.16, 0.0)
    # vertical ribs on both ends (base)
    for sx in (-1, 1):
        for yy in (-0.12, 0.12):
            g += box((0.012, 0.022, 0.09), grey, r=0.005, seg=2, center=(sx * (CL / 2 + 0.003), yy, 0.062))
    # fold-down carry handle on the front of the base
    yf = CD / 2
    for sx in (-1, 1):
        g += box((0.03, 0.026, 0.03), grey, r=0.008, seg=2, center=(sx * 0.085, yf + 0.008, 0.098))
    hp = polyline_fillet([(-0.085, yf + 0.016, 0.098), (-0.085, yf + 0.030, 0.050), (0.085, yf + 0.030, 0.050), (0.085, yf + 0.016, 0.098)], 0.016, 8)
    g += sweep(rrect(0.020, 0.030, 0.008, 3), hp, grey, side=(0, 1, 0), tag="handle", smooth_angle=55)
    g += sweep(rrect(0.024, 0.034, 0.010, 3), np.array([(-0.062, yf + 0.030, 0.050), (0.062, yf + 0.030, 0.050)]), grip,
               side=(0, 1, 0), tag="handlegrip", smooth_angle=55)
    for sx in (-1, 1):
        g += screws(b, [(sx * 0.085, yf + 0.021, 0.098)], (0, 1, 0), d=0.006, segs=12)
    return g


def _closed_shell(b):
    grey = m_case_grey(b)
    g = Geo()
    base_h = Z_SEAM - FOOT
    g += box((CL, CD, base_h), grey, r=CR, seg=3, center=(0, 0, FOOT + base_h / 2), face_density={"-z": 0.35})
    g += box((CL, CD, LID_H), grey, r=CR, seg=3, center=(0, 0, Z_SEAM + LID_H / 2))
    # seam lip (slightly proud band)
    g += sweep(rrect(0.010, 0.016, 0.004, 2), _outline_path(CL - 0.004, CD - 0.004, CR, Z_SEAM), grey, closed_path=True,
               up=(0, 0, 1), tag="seam", smooth_angle=50).translate(0, 0, 0)
    # lid top ribs
    top = Z_SEAM + LID_H
    for yy in (-0.165, 0.165):
        g += box((0.50, 0.018, 0.010), grey, r=0.004, seg=2, center=(0, yy, top - 0.002))
    # hinges on the back
    yb = -CD / 2
    for x in (-0.19, 0.0, 0.19):
        g += cylinder(0.0095, 0.08, grey, segs=18, bevel=0.002, z0=-0.04).rotate(0, 90, 0).translate(x, yb - 0.006, Z_SEAM)
    return g


@prop("nz_amb_kitcase_closed", atlas=1024, lod=90, hd=15, falloff=80, doc={
    "title": "Trauma kit hard case (closed)",
    "origin": "bottom centre (on the ground)",
    "axes": "+Y = front (latches + handle), +Z up, length along X",
    "attach": "carry: PH_R_Hand (28422) pos (0.0, -0.245, -0.06) rot (0, 0, 0) -> handle in the hand, case hanging; "
              "SKEL_R_Hand (57005) pos (0.06, 0.0, -0.06) rot (90, 0, 90) as a starting point",
})
def kitcase_closed(b):
    g = _closed_shell(b) + _case_hardware(b)
    for x in (-0.19, 0.19):
        g += _case_latch(b, x, CD / 2)
    # purge valve on the lid front
    blk = m_black_plastic(b)
    g += align(lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.006), (0.010, 0.009), (0.0, 0.009)], blk, segs=24), (0, 1, 0), (0, 0, 1), (0.0, CD / 2, Z_SEAM + 0.036))
    b.add(g)
    _case_decals(b, open_lid=False)
    b.col_box((-0.31, -0.232, 0.0), (0.31, 0.233, 0.205), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.1, 0.215, 0.04), (0.1, 0.255, 0.11), "PLASTIC_HIGH_DENSITY")


def _case_decals(b, open_lid=False, lid_rot=None, hinge_o=None):
    grey = "case_grey"
    top = Z_SEAM + LID_H
    dc = DecalCanvas(0.40, 0.16, ppm=1500)
    dc.lockup(0.012, 0.012, 0.075, color=WHITE, sub_color=TEAL_HI)
    dc.rect(0.012, 0.105, 0.376, 0.040, r=0.006, color=(8, 168, 156), spec=0.35, gloss=0.5)
    dc.text(0.2, 0.125, "TRAUMA  /  RESUS  KIT", 0.017, fnt="label", color=(12, 14, 16), spacing=0.003, max_w=0.36)
    lab = serial_label(0.07, 0.026, "TRAUMA KIT  NZ-TK62", "UNIT 07-A")
    if not open_lid:
        b.decal(dc, center=(0.0, 0.0, top), normal=(0, 0, 1), up=(0, -1, 0), mats=[grey], depth=0.012, min_dot=0.6)
        b.decal(lab, center=(0.21, -CD / 2, Z_SEAM + 0.036), normal=(0, -1, 0), mats=[grey], depth=0.01)
    else:
        n = lid_rot @ vec(0, 0, 1)
        up = lid_rot @ vec(0, 1, 0)
        c = lid_rot @ (vec(0, 0, top) - hinge_o) + hinge_o
        b.decal(dc, center=tuple(c), normal=tuple(n), up=tuple(up), mats=[grey], depth=0.012, min_dot=0.6)
    side = DecalCanvas(0.12, 0.05, ppm=2400)
    side.rect(0, 0, 0.12, 0.05, r=0.006, color=(214, 54, 50))
    cross_mark(side, 0.025, 0.025, 0.032, color=WHITE)
    side.text(0.078, 0.019, "EMS", 0.012, fnt="label", color=WHITE)
    side.text(0.078, 0.036, "07-A", 0.008, fnt="label-semi", color=WHITE)
    for sx in (-1, 1):
        b.decal(side, center=(sx * CL / 2, 0.0, 0.07), normal=(sx, 0, 0), up=(0, 0, 1), mats=[grey], depth=0.012)


# ---------------------------------------------------------------------------------------------
@prop("nz_amb_kitcase_open", atlas=2048, lod=90, hd=15, static=True, falloff=80, doc={
    "title": "Trauma kit hard case (open, foam inserts with IO driver, syringes, blood tubes)",
    "origin": "bottom centre (on the ground)",
    "axes": "+Y = front (latches), lid hinged at -Y and open ~100 deg (leans back), +Z up",
    "attach": "placed on the ground next to the patient (static archetype); use nz_amb_kitcase_closed while carrying",
})
def kitcase_open(b):
    grey = m_case_grey(b)
    foam = m_foam(b)
    pluck = b.mat("pluck_foam", color=(36, 38, 41), spec=0.04, gloss=0.06, bump="pluck", bump_amp=0.0012,
                  bump_scale=0.0125, grain=0.05, grain_scale=0.05, ao=1.0)
    crate = b.mat("crate_foam", color=(42, 44, 47), spec=0.04, gloss=0.06, bump="eggcrate", bump_amp=0.006,
                  bump_scale=0.045, grain=0.05, grain_scale=0.05, ao=1.0)
    gasket = b.mat("gasket", color=(22, 23, 25), spec=0.15, gloss=0.25, edge=0.1)
    g = Geo()
    wall = 0.012
    base_h = Z_SEAM - FOOT
    outline = rrect(CL, CD, CR, 5)
    inner = rrect(CL - 2 * wall, CD - 2 * wall, CR - wall, 5)
    g += extrude(outline, base_h, grey, bevel=0.022, bevel_seg=3, z0=FOOT, caps=(True, False), smooth_angle=50, tag="base")
    cav = extrude(inner, base_h - 0.012, grey, z0=FOOT + 0.012, caps=(True, False), smooth_angle=50, tag="cavity")
    g += cav.flip()
    rim = sweep(rrect(wall, 0.01, 0.004, 2) + vec(0, -0.005), _outline_path(CL - wall, CD - wall, CR - wall / 2, Z_SEAM), grey,
                closed_path=True, up=(0, 0, 1), tag="rim", smooth_angle=50)
    g += rim
    g += _case_hardware(b, open_lid=True)
    # latches hanging open on the front
    for x in (-0.19, 0.19):
        lat = _case_latch(b, x, CD / 2)
        lat.rotate_axis((1, 0, 0), -25, origin=(x, CD / 2 + 0.007, Z_SEAM - 0.034))
        g += lat

    # ---- lid, built closed then hinged open -----------------------------------------------
    lid = Geo()
    lid += extrude(outline, LID_H, grey, bevel=0.022, bevel_seg=3, z0=Z_SEAM, caps=(False, True), smooth_angle=50, tag="lid")
    lin = extrude(inner, LID_H - 0.012, grey, z0=Z_SEAM, caps=(False, True), smooth_angle=50, tag="lidin")
    lid += lin.flip()
    lid += sweep(rrect(wall, 0.008, 0.003, 2) + vec(0, 0.004), _outline_path(CL - wall, CD - wall, CR - wall / 2, Z_SEAM), grey,
                 closed_path=True, up=(0, 0, 1), tag="lidrim", smooth_angle=50)
    lid += sweep(rrect(0.006, 0.004, 0.0015, 2), _outline_path(CL - wall, CD - wall, CR - wall / 2, Z_SEAM - 0.0005), gasket,
                 closed_path=True, up=(0, 0, 1), tag="gasket", smooth_angle=50)
    top = Z_SEAM + LID_H
    for yy in (-0.165, 0.165):
        lid += box((0.50, 0.018, 0.010), grey, r=0.004, seg=2, center=(0, yy, top - 0.002))
    # egg crate liner in the lid (its visible face points down when closed)
    lid += box((CL - 2 * wall - 0.004, CD - 2 * wall - 0.004, 0.035), crate, r=0.006, seg=1,
               center=(0, 0, Z_SEAM + 0.0225), faces="-z", face_density={"-z": 1.2})
    # contents card on the liner
    card = b.mat("card", color=(236, 238, 238), spec=0.45, gloss=0.6, edge=0.2)
    lid += box((0.20, 0.13, 0.002), card, r=0.002, seg=1, center=(0.12, 0.02, Z_SEAM + 0.0035), faces="-z +x -x +y -y")
    for x in (-0.19, 0.19):
        lid += box((0.05, 0.016, 0.012), grey, r=0.004, seg=2, center=(x, CD / 2 + 0.006, Z_SEAM + 0.043))
    hinge_o = vec(0, -CD / 2 - 0.006, Z_SEAM)
    ang = 100.0
    lid.rotate_axis((1, 0, 0), ang, origin=hinge_o)
    g += lid
    from nzprops.mesh import axis_angle
    rot = axis_angle((1, 0, 0), ang)
    for x in (-0.19, 0.0, 0.19):
        g += cylinder(0.0095, 0.08, grey, segs=18, bevel=0.002, z0=-0.04).rotate(0, 90, 0).translate(x, -CD / 2 - 0.006, Z_SEAM)

    # ---- pick-and-pluck foam insert with pockets -------------------------------------------
    zt = Z_SEAM - 0.012
    x0, x1 = -CL / 2 + wall + 0.002, CL / 2 - wall - 0.002
    y0, y1 = -CD / 2 + wall + 0.002, CD / 2 - wall - 0.002
    holes = [(-0.262, -0.112, -0.135, 0.075),     # IO driver
             (-0.085, 0.045, -0.165, 0.025),      # syringes
             (0.07, 0.262, 0.05, 0.175),          # blood tubes
             (0.07, 0.262, -0.165, 0.015),        # dressings
             (-0.085, 0.045, 0.06, 0.175)]        # IO needle sets
    g += slab_with_holes(x0, x1, y0, y1, zt, holes, pluck, tag="foamtop")
    for (hx0, hx1, hy0, hy1) in holes:
        g += pocket(hx0, hx1, hy0, hy1, zt, 0.045, foam, tag="pocket")
    # contents
    drill = iodrill_geo(b).rotate(0, -90, 0).rotate(0, 0, 0)
    dmn, dmx = drill.bbox()
    drill.translate(-0.187 - (dmn[0] + dmx[0]) / 2, -0.03 - (dmn[1] + dmx[1]) / 2, zt - 0.032 - dmn[2])
    g += drill
    for k in range(3):
        s = syringe_geo(b, fill=(0.9, 0.0, 0.5)[k], cap=True).rotate(0, 0, 0)
        smn, smx = s.bbox()
        s.translate(-0.06 + k * 0.042 - (smn[0] + smx[0]) / 2, -0.07 - (smn[1] + smx[1]) / 2, zt - 0.031 - smn[2] + 0.01)
        g += s
    tube_cols = [(200, 40, 40), (150, 60, 170), (60, 110, 210), (40, 160, 90), (200, 40, 40), (240, 200, 40)]
    glass = b.mat("tube_glass", color=(225, 232, 235), spec=0.9, gloss=0.92, alpha=0.25, layer="alpha", grain=0.0)
    blood = b.mat("tube_blood", color=(108, 10, 16), spec=0.6, gloss=0.8, edge=0.0)
    for k, c in enumerate(tube_cols):
        capm = b.mat(f"tube_cap{k}", color=c, spec=0.35, gloss=0.5, bump="ribs", bump_amp=0.00015, bump_scale=0.0015, edge=0.3)
        yy = 0.068 + k * 0.0195
        t = Geo()
        t += cylinder(0.0062, 0.075, glass, segs=18, bevel=0.003, bevel_seg=2, caps=(True, False))
        t += cylinder(0.0055, 0.045, blood, segs=14, bevel=0.002, caps=(True, True), z0=0.003)
        t += cylinder(0.0075, 0.02, capm, segs=18, bevel=0.0015, z0=0.072)
        t.rotate(0, 90, 0).translate(0.075, yy, zt - 0.03)
        g += t
    pack = b.mat("dressing_pack", color=(110, 116, 84), spec=0.55, gloss=0.65, bump="orange_peel", bump_amp=0.0003, bump_scale=0.01, edge=0.3)
    for k in range(2):
        g += box((0.17, 0.065, 0.03), pack, r=0.012, seg=2, center=(0.166, -0.12 + k * 0.075, zt - 0.03))
    needles = [(10, 158, 147), (60, 110, 210), (230, 200, 40)]
    for k, c in enumerate(needles):
        m = b.mat(f"needle_set{k}", color=c, spec=0.4, gloss=0.55, edge=0.3)
        g += box((0.035, 0.09, 0.02), m, r=0.008, seg=2, center=(-0.06 + k * 0.042, 0.118, zt - 0.03))
    items = {"drill_grey", "drill_rubber", "teal", "steel", "chrome", "plunger", "stopper", "tube_blood", "dressing_pack"}
    for ch in g.charts:
        if ch.tag.startswith("cavity"):
            ch.density = 0.12
        elif ch.mat in items or ch.mat.startswith(("tube_cap", "needle_set")):
            ch.density = 1.4
    b.add(g)

    # decals ------------------------------------------------------------------------------
    _case_decals(b, open_lid=True, lid_rot=rot, hinge_o=hinge_o)
    cdc = DecalCanvas(0.20, 0.13, ppm=2600)
    cdc.rect(0, 0, 0.2, 0.024, color=(8, 168, 156))
    cdc.mark(0.006, 0.004, 0.016)
    cdc.text(0.028, 0.012, "TRAUMA KIT  -  CONTENTS", 0.0075, fnt="label", anchor="lm", color=(10, 12, 14), max_w=0.165)
    items = ["IO driver + needle sets (15/25/45)", "Syringes 10 mL  x3", "Blood tubes (red/purple/blue/green)",
             "Haemostatic dressings  x2", "Tourniquet  /  pelvic binder", "Check seal after every call"]
    for k, t in enumerate(items):
        cdc.circle(0.012, 0.036 + k * 0.0155, 0.0022, color=(8, 168, 156))
        cdc.text(0.02, 0.036 + k * 0.0155, t, 0.0058, fnt="label-semi", anchor="lm", color=(30, 32, 35), max_w=0.17)
    cc = rot @ (vec(0.12, 0.02, Z_SEAM + 0.0024) - hinge_o) + hinge_o
    b.decal(cdc, center=tuple(cc), normal=tuple(rot @ vec(0, 0, -1)), up=tuple(rot @ vec(0, 1, 0)), mats=["card"], depth=0.004)
    # pocket labels on the foam
    for (hx0, hx1, hy0, hy1), t in zip(holes, ("IO", "SYRINGES", "TUBES", "DRESSINGS", "IO NEEDLES")):
        lab = DecalCanvas(0.08, 0.014, ppm=3000)
        lab.text(0.04, 0.007, t, 0.0065, fnt="label", color=(150, 156, 160), spacing=0.0012, max_w=0.075)
        b.decal(lab, center=((hx0 + hx1) / 2, hy1 + 0.012, zt), normal=(0, 0, 1), up=(0, 1, 0), mats=["pluck_foam"], depth=0.004)
    b.decal(brand_canvas(0.07, 0.022, ppm=3000), center=(0.0, -CD / 2 + wall + 0.016, zt), normal=(0, 0, 1), up=(0, 1, 0), mats=["pluck_foam"], depth=0.004)

    b.col_box((-0.31, -0.232, 0.0), (0.31, 0.233, 0.127), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.31, -0.33, 0.12), (0.31, -0.215, 0.56), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# sharps bin
# =============================================================================================
@prop("nz_amb_sharps", atlas=512, lod=60, hd=10, doc={
    "title": "Sharps bin (5 L), yellow with orange lid",
    "origin": "bottom centre",
    "axes": "+Y = front (biohazard label), aperture on top, +Z up",
    "attach": "placed on the ground / ambulance shelf; carry: PH_R_Hand (28422) pos (0.0, 0.0, -0.27) by the lid handle",
})
def sharps(b):
    yel = b.mat("sharps_yellow", color=(236, 196, 30), spec=0.35, gloss=0.5, bump="orange_peel", bump_amp=0.00002,
                bump_scale=0.002, grain=0.03, grain_scale=0.05, edge=0.4, dirt=0.15)
    lidm = b.mat("sharps_lid", color=(226, 92, 28), spec=0.4, gloss=0.55, bump="orange_peel", bump_amp=0.00002,
                 bump_scale=0.002, grain=0.03, grain_scale=0.05, edge=0.45, dirt=0.12)
    dark = b.mat("aperture", color=(18, 18, 20), spec=0.1, gloss=0.2, ao=1.0)
    W, D, Hb = 0.20, 0.14, 0.195
    body = box((W, D, Hb), yel, r=0.014, seg=3, center=(0, 0, Hb / 2), face_density={"-z": 0.4})
    body.taper(0.0, Hb, 0.92, 1.0)
    b.add(body)
    # lid
    zl = Hb - 0.006
    b.add(box((W + 0.012, D + 0.012, 0.032), lidm, r=0.010, seg=2, center=(0, 0, zl + 0.016)))
    b.add(box((0.15, 0.085, 0.012), lidm, r=0.012, seg=2, center=(0, 0.005, zl + 0.034)))
    b.add(box((0.115, 0.032, 0.006), dark, r=0.008, seg=2, center=(0, 0.012, zl + 0.0385)))
    # sliding closure flap (parked at the back)
    b.add(box((0.125, 0.03, 0.006), lidm, r=0.004, seg=2, center=(0, -0.03, zl + 0.0425)))
    # fold-flat handle on top
    hp = polyline_fillet([(-0.088, -0.045, zl + 0.03), (-0.088, -0.062, zl + 0.036), (0.088, -0.062, zl + 0.036), (0.088, -0.045, zl + 0.03)], 0.01, 4)
    b.add(sweep(rrect(0.012, 0.006, 0.0025, 2), hp, lidm, up=(0, 0, 1), tag="handle"))
    # decals
    lab = DecalCanvas(0.16, 0.13, ppm=2600)
    lab.rect(0, 0, 0.16, 0.13, r=0.006, color=(244, 210, 40))
    lab.rect(0.004, 0.004, 0.152, 0.122, r=0.004, fill=False, width=0.002, color=(18, 18, 20))
    biohazard(lab, 0.04, 0.048, 0.028)
    lab.text(0.108, 0.034, "SHARPS", 0.017, fnt="label", color=(18, 18, 20), max_w=0.08)
    lab.text(0.108, 0.058, "BIOHAZARD", 0.008, fnt="label", color=(18, 18, 20), max_w=0.08)
    lab.text(0.08, 0.092, "DANGER - CONTAMINATED NEEDLES", 0.0058, fnt="label", color=(18, 18, 20), max_w=0.145)
    lab.text(0.08, 0.108, "DO NOT OVERFILL  ·  5 L", 0.0052, fnt="label-semi", color=(18, 18, 20), max_w=0.145)
    b.decal(lab, center=(0, D / 2 + 0.001, 0.095), normal=(0, 1, 0), up=(0, 0, 1), mats=["sharps_yellow"], depth=0.012)
    fill = DecalCanvas(0.13, 0.02, ppm=2600)
    for k in range(9):
        fill.rect(0.002 + k * 0.0145, 0.002, 0.009, 0.002, color=(18, 18, 20))
    fill.text(0.065, 0.012, "FILL LINE", 0.0045, fnt="label", color=(18, 18, 20))
    for sx in (-1, 1):
        b.decal(fill, center=(sx * (W / 2 + 0.001), 0, 0.155), normal=(sx, 0, 0), up=(0, 0, 1), mats=["sharps_yellow"], depth=0.012)
    b.decal(brand_canvas(0.07, 0.02, ppm=3000, color=(18, 18, 20), sub_color=(18, 18, 20)), center=(0, -D / 2 - 0.001, 0.15),
            normal=(0, -1, 0), up=(0, 0, 1), mats=["sharps_yellow"], depth=0.012)
    arrow = DecalCanvas(0.13, 0.03, ppm=3000)
    arrow.text(0.065, 0.015, "PUSH TO CLOSE", 0.0055, fnt="label", color=(250, 236, 224), spacing=0.0008)
    b.decal(arrow, center=(0, 0.04, zl + 0.0405), normal=(0, 0, 1), up=(0, -1, 0), mats=["sharps_lid"], depth=0.006)
    b.col_box((-0.106, -0.076, 0.0), (0.106, 0.076, 0.245), "PLASTIC_HOLLOW")


