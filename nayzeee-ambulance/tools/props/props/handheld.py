"""
Hand-held instruments: IO driver, syringe, laryngoscope, ultrasound probe, stethoscope.
Part builders (iodrill_geo, syringe_geo) are reused by the open trauma case.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (DecalCanvas, Geo, box, catmull, cylinder, extrude, lathe, prop, rrect, sphere, sweep, tube)

from .common import (m_black_plastic, m_chrome, m_led, m_rubber, m_steel, m_teal, m_white_plastic)

YZ_FROM_XY = np.array([[0, 0, 1], [1, 0, 0], [0, 1, 0]], dtype=float)  # 2D (x, y) -> (Y, Z), extrusion -> X


def _along_y(g: Geo):
    """Lathe/cylinder built around +Z -> axis along +Y."""
    return g.rotate(-90, 0, 0)


# =============================================================================================
# IO driver
# =============================================================================================
def iodrill_geo(b):
    grey = b.mat("drill_grey", color=(128, 133, 139), spec=0.34, gloss=0.46, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0006, grain=0.03, grain_scale=0.04, edge=0.6, dirt=0.12)
    rub = b.mat("drill_rubber", color=(40, 42, 46), spec=0.12, gloss=0.18, bump="rubber", bump_amp=0.00008,
                bump_scale=0.0007, edge=0.25)
    teal = m_teal(b)
    steel = m_steel(b)
    chrome = m_chrome(b)
    g = Geo()
    zb = 0.048
    prof = [(0.0, -0.079), (0.012, -0.0785), (0.018, -0.0755), (0.0215, -0.070), (0.0225, -0.060), (0.0225, 0.012),
            (0.020, 0.026), (0.0155, 0.040), (0.0118, 0.046), (0.0110, 0.055)]
    g += _along_y(lathe(prof, grey, segs=40, smooth_angle=28)).translate(0, 0, zb)
    # teal ring + rubber rear cap
    g += _along_y(cylinder(0.0230, 0.006, teal, segs=40, caps=(False, False))).translate(0, -0.006, zb)
    g += _along_y(lathe([(0.0, -0.0815), (0.014, -0.081), (0.0195, -0.077), (0.0205, -0.072)], rub, segs=40, smooth_angle=40)).translate(0, 0, zb)
    # chuck, hub, needle
    g += _along_y(cylinder(0.0078, 0.012, chrome, segs=28, bevel=0.0012, caps=(False, True), z0=0.055)).translate(0, 0, zb)
    g += _along_y(lathe([(0.0, 0.067), (0.0062, 0.067), (0.0062, 0.073), (0.0042, 0.075), (0.0040, 0.081), (0.0, 0.081)], teal, segs=24)).translate(0, 0, zb)
    g += _along_y(lathe([(0.0, 0.081), (0.00095, 0.081), (0.00095, 0.104), (0.0, 0.1075)], steel, segs=10, smooth_angle=60)).translate(0, 0, zb)
    # pistol grip: side profile extruded along X
    poly = np.array([(-0.047, 0.040), (-0.052, 0.0), (-0.046, -0.048), (-0.038, -0.058), (-0.004, -0.058),
                     (0.004, -0.050), (0.010, -0.004), (0.020, 0.040)])
    grip = extrude(poly, 0.034, rub, bevel=0.009, bevel_seg=3, smooth_angle=50, side_mat=grey, tag="grip")
    grip.transform(YZ_FROM_XY).translate(-0.017, 0, 0)
    g += grip
    # battery cap + trigger
    g += box((0.03, 0.036, 0.008), teal, r=0.0035, seg=2, center=(0, -0.021, -0.061))
    trig = extrude(rrect(0.011, 0.030, 0.005, 3), 0.016, teal, bevel=0.003, bevel_seg=2)
    trig.transform(YZ_FROM_XY).translate(-0.008, 0.014, 0.012)
    g += trig
    return g


@prop("nz_amb_iodrill", atlas=512, lod=45, hd=8, doc={
    "title": "Intraosseous (IO) driver",
    "origin": "centre of the pistol grip (where the palm wraps)",
    "axes": "+Y = needle direction, +Z = up over the grip, body on top",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) needle forward; SKEL_R_Hand (57005) pos (0.10, 0.02, -0.02) rot (-90, 0, 0)",
})
def iodrill(b):
    b.add(iodrill_geo(b))
    lab = DecalCanvas(0.10, 0.03, ppm=4500)
    lab.mark(0.002, 0.004, 0.013)
    lab.text(0.019, 0.0105, "NAYZEEE", 0.0058, fnt="brand", anchor="lm", color=(24, 26, 28), spacing=0.0008)
    lab.text(0.002, 0.024, "IO DRIVER  ·  15-25 mm", 0.0036, fnt="brand-semi", anchor="lm", color=(24, 26, 28), spacing=0.0003)
    for sx in (1, -1):
        b.decal(lab, center=(sx * 0.0226, -0.028, 0.050), normal=(sx, 0, 0), up=(0, 0, 1), mats=["drill_grey"], depth=0.006)
    b.col_box((-0.024, -0.082, -0.066), (0.024, 0.108, 0.072), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# syringe 10 ml
# =============================================================================================
def syringe_geo(b, fill=0.55, cap=False):
    clear = b.mat("syringe_clear", color=(232, 238, 240), spec=0.9, gloss=0.92, alpha=0.18, layer="alpha", grain=0.0)
    fluid = b.mat("syringe_fluid", color=(214, 232, 236), spec=0.7, gloss=0.9, alpha=0.22, layer="alpha", grain=0.0)
    plunger = b.mat("plunger", color=(238, 240, 241), spec=0.35, gloss=0.5, bump="orange_peel", bump_amp=0.00001, bump_scale=0.001, edge=0.2)
    stopper = b.mat("stopper", color=(26, 27, 29), spec=0.3, gloss=0.4, edge=0.2)
    hub = m_teal(b)
    steel = m_steel(b)
    g = Geo()
    Ro, L = 0.0080, 0.074
    barrel = [(0.0063, 0.0), (Ro, 0.0), (Ro, L - 0.004), (Ro - 0.0015, L), (0.0024, L + 0.0015), (0.0021, L + 0.010), (0.0, L + 0.0105)]
    g += _along_y(lathe(barrel, clear, segs=36, smooth_angle=35))
    # finger flange
    fl = extrude(rrect(0.034, 0.015, 0.0065, 5), 0.0022, clear, bevel=0.0006, bevel_seg=1)
    g += fl.rotate(-90, 0, 0).translate(0, -0.0011, 0)
    # stopper + fluid
    ys = 0.006 + (1.0 - fill) * (L - 0.012)
    g += _along_y(lathe([(0.0, ys), (0.0072, ys), (0.0074, ys + 0.0015), (0.0068, ys + 0.003), (0.0074, ys + 0.0045),
                         (0.0072, ys + 0.006), (0.0, ys + 0.0075)], stopper, segs=28, smooth_angle=40))
    if fill > 0.02:
        g += _along_y(cylinder(0.0073, L - 0.0015 - (ys + 0.0075), fluid, segs=28, z0=ys + 0.0075))
    # plunger rod (cross) + thumb press
    rod_y0, rod_y1 = -0.035 + (1.0 - fill) * (L - 0.012), ys
    for rot in (0, 90):
        g += box((0.0105, rod_y1 - rod_y0, 0.0012), plunger, center=(0, (rod_y0 + rod_y1) / 2, 0)).rotate(0, rot, 0)
    g += _along_y(cylinder(0.0088, 0.0022, plunger, segs=32, bevel=0.0006, z0=rod_y0 - 0.0022))
    # needle hub + needle (or cap)
    g += _along_y(lathe([(0.0, L + 0.009), (0.0036, L + 0.009), (0.0036, L + 0.0125), (0.0028, L + 0.019), (0.0012, L + 0.0205), (0.0, L + 0.0205)], hub, segs=20))
    if cap:
        g += _along_y(cylinder(0.0034, 0.03, hub, segs=20, bevel=0.001, z0=L + 0.0195))
    else:
        g += _along_y(lathe([(0.0, L + 0.020), (0.00045, L + 0.020), (0.00045, L + 0.046), (0.0, L + 0.0485)], steel, segs=8, smooth_angle=60))
    return g


def syringe_scale(b, length=0.074):
    dc = DecalCanvas(0.014, length, ppm=9000)
    ink = (20, 22, 24)
    for k in range(0, 21):
        y = length - 0.006 - k * (length - 0.012) / 20
        major = k % 4 == 0
        dc.rect(0.0, y - 0.00012, 0.0042 if major else 0.0026, 0.00024, color=ink)
        if major and k > 0:
            dc.text(0.0058, y, str(k // 2), 0.0013, fnt="brand-semi", anchor="lm", color=ink)
    dc.text(0.0105, length * 0.5, "NAYZEEE 10 mL", 0.0011, fnt="brand-semi", color=(10, 120, 112), rotate=90)
    return dc


@prop("nz_amb_syringe", atlas=256, alpha_atlas=256, lod=30, hd=5, doc={
    "title": "10 mL syringe with needle",
    "origin": "finger flange (barrel back end)",
    "axes": "+Y = needle direction; flange wings along X",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) or SKEL_R_Hand (57005) pos (0.09, 0.03, -0.01) rot (-80, 0, 0)",
})
def syringe(b):
    b.add(syringe_geo(b, fill=0.55))
    b.decal(syringe_scale(b), center=(0.0, 0.037, 0.008), normal=(0, 0, 1), up=(0, 1, 0), mats=["syringe_clear"], depth=0.006, min_dot=0.3)
    b.col_box((-0.017, -0.04, -0.009), (0.017, 0.123, 0.009), "PLASTIC")


# =============================================================================================
# laryngoscope (Macintosh blade, open)
# =============================================================================================
@prop("nz_amb_laryngoscope", atlas=512, lod=35, hd=6, doc={
    "title": "Laryngoscope (Macintosh blade, open / light on)",
    "origin": "centre of the handle",
    "axes": "handle along Z (top = +Z), blade points +Y and curves down",
    "attach": "PH_L_Hand (60309) pos (0.0, 0.0, 0.0) rot (0, 0, 0); SKEL_L_Hand (18905) pos (0.08, 0.02, 0.0) rot (0, 90, 0)",
})
def laryngoscope(b):
    knurl = b.mat("knurl_steel", color=(150, 154, 160), spec=0.8, gloss=0.6, metal=1.0, bump="knurl", bump_amp=0.00018,
                  bump_scale=0.0018, grain=0.02, edge=0.3)
    chrome = m_chrome(b)
    teal = m_teal(b)
    lamp = m_led(b, "lamp", (255, 248, 225))
    # handle
    prof = [(0.0, -0.072), (0.0105, -0.0715), (0.0138, -0.068), (0.0140, -0.062)]
    b.add(lathe(prof, chrome, segs=36, smooth_angle=35))
    b.add(cylinder(0.0140, 0.112, knurl, segs=36, caps=(False, False), z0=-0.062))
    b.add(cylinder(0.0143, 0.006, teal, segs=36, caps=(False, False), z0=0.050))
    b.add(lathe([(0.0140, 0.056), (0.0140, 0.062), (0.0120, 0.066), (0.0, 0.066)], chrome, segs=36, smooth_angle=35))
    # hinge block
    b.add(box((0.020, 0.026, 0.016), chrome, r=0.004, seg=2, center=(0, 0.004, 0.073)))
    b.add(cylinder(0.0035, 0.024, chrome, segs=16, bevel=0.001, z0=-0.012).rotate(0, 90, 0).translate(0, 0.004, 0.075))
    # blade: curved spatula + flange
    path = catmull([(0, 0.012, 0.079), (0, 0.045, 0.080), (0, 0.08, 0.073), (0, 0.112, 0.058), (0, 0.128, 0.046)], n=8)
    b.add(sweep(rrect(0.019, 0.0022, 0.0009, 2), path, chrome, side=(1, 0, 0), tag="blade", smooth_angle=50))
    flange = path.copy()
    flange[:, 0] = -0.0085
    flange[:, 2] += 0.006
    b.add(sweep(rrect(0.0022, 0.012, 0.0009, 2), flange[:-6], chrome, side=(1, 0, 0), tag="flange", smooth_angle=50))
    b.add(sphere(0.0025, chrome, segs=12, rings=6).scale(3.6, 1.0, 1.0).translate(0, 0.1295, 0.0455))
    # light: small lens on the underside of the blade
    b.add(cylinder(0.0032, 0.004, chrome, segs=16, z0=0.0).rotate(-60, 0, 0).translate(0.0055, 0.09, 0.0675))
    b.add(sphere(0.0026, lamp, segs=12, rings=6).translate(0.0055, 0.0925, 0.0655))
    lab = DecalCanvas(0.028, 0.06, ppm=7000)
    lab.text(0.014, 0.03, "NAYZEEE", 0.0045, fnt="brand", color=(40, 42, 46), spacing=0.0006, rotate=90, height=-0.00008)
    b.decal(lab, center=(0.0141, 0.0, 0.0), normal=(1, 0, 0), up=(0, 0, 1), mats=["knurl_steel"], depth=0.006)
    b.col_cyl((0, 0, -0.003), 0.0145, 0.138, axis="z", material="METAL_SOLID_SMALL")
    b.col_box((-0.011, 0.0, 0.04), (0.011, 0.132, 0.084), "METAL_SOLID_SMALL")


# =============================================================================================
# ultrasound probe (convex)
# =============================================================================================
@prop("nz_amb_us_probe", atlas=512, lod=35, hd=6, doc={
    "title": "Ultrasound probe (convex) with cable stub",
    "origin": "centre of the grip",
    "axes": "lens points -Z, cable exits +Z; orientation marker on +X",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (180, 0, 0) lens down; SKEL_R_Hand (57005) pos (0.08, 0.03, -0.02) rot (90, 0, 0)",
})
def us_probe(b):
    shell = m_white_plastic(b)
    teal = m_teal(b)
    lens = b.mat("lens", color=(34, 36, 40), spec=0.5, gloss=0.75, edge=0.2)
    cable = b.mat("cable", color=(52, 55, 60), spec=0.25, gloss=0.4, edge=0.1)
    rub = m_rubber(b)
    zs = np.linspace(-0.055, 0.062, 24)
    sx = np.interp(zs, [-0.055, -0.035, -0.012, 0.02, 0.05, 0.062], [1.25, 1.18, 0.82, 0.74, 0.62, 0.42])
    sy = np.interp(zs, [-0.055, -0.035, -0.012, 0.02, 0.05, 0.062], [0.95, 0.95, 0.86, 0.84, 0.76, 0.52])
    path = np.stack([np.zeros_like(zs), np.zeros_like(zs), zs], axis=1)
    prof = rrect(0.043, 0.025, 0.0095, 5)
    b.add(sweep(prof, path, shell, scale=np.stack([sx, sy], axis=1), side=(1, 0, 0), tag="body", smooth_angle=60))
    # teal grip band + orientation marker
    b.add(sweep(rrect(0.0436, 0.0256, 0.0097, 5), np.array([[0, 0, -0.004], [0, 0, 0.004]]), teal,
                scale=np.array([[0.80, 0.858], [0.785, 0.856]]), side=(1, 0, 0), caps=False, tag="band"))
    b.add(sphere(0.0022, teal, segs=12, rings=6).translate(0.0272, 0, -0.04))
    # convex lens: circular segment swept across the head
    R, c = 0.0518, 0.0255
    half = math.degrees(math.asin(c / R))
    th = np.radians(np.linspace(-90 - half, -90 + half, 24))
    zc = -0.0092
    lensp = [(R * math.cos(t), zc + R * math.sin(t)) for t in th] + [(c, -0.049), (-c, -0.049)]
    b.add(sweep(np.array(lensp), np.array([[0, -0.0105, 0], [0, 0.0105, 0]]), lens, side=(1, 0, 0), tag="lens", smooth_angle=30))
    # strain relief + cable stub
    b.add(lathe([(0.0088, 0.058), (0.0068, 0.075), (0.0048, 0.095), (0.0043, 0.098)], rub, segs=20, smooth_angle=50))
    cab = catmull([(0, 0, 0.097), (0, 0, 0.118), (0.012, 0.006, 0.138), (0.04, 0.012, 0.148), (0.07, 0.008, 0.14)], n=6)
    b.add(tube(cab, 0.0036, cable, segs=12))
    lab = DecalCanvas(0.03, 0.05, ppm=7000)
    lab.mark(0.009, 0.004, 0.012)
    lab.text(0.015, 0.024, "NAYZEEE", 0.0038, fnt="brand", color=(30, 32, 35), spacing=0.0005)
    lab.text(0.015, 0.034, "C5-2  CONVEX", 0.0026, fnt="brand-semi", color=(10, 130, 120))
    b.decal(lab, center=(0, 0.0122, 0.022), normal=(0, 1, 0), up=(0, 0, 1), mats=["white_plastic"], depth=0.01)
    b.col_box((-0.034, -0.016, -0.06), (0.034, 0.016, 0.1), "PLASTIC")


# =============================================================================================
# stethoscope (coiled, lying flat)
# =============================================================================================
@prop("nz_amb_stethoscope", atlas=512, lod=35, hd=6, doc={
    "title": "Stethoscope, coiled",
    "origin": "bottom centre (lying flat)",
    "axes": "flat on the XY plane, chest piece at +X, ear pieces at -X",
    "attach": "neck: SKEL_Neck_1 (39317) needs a draped variant - use this model on surfaces / in hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0)",
})
def stethoscope(b):
    tubing = b.mat("steth_tube", color=(8, 128, 120), spec=0.32, gloss=0.55, bump="rubber", bump_amp=0.00002, bump_scale=0.0008, edge=0.2)
    chrome = m_chrome(b)
    diaph = b.mat("diaphragm", color=(226, 228, 230), spec=0.45, gloss=0.6, edge=0.1)
    tip = m_black_plastic(b)
    r = 0.0045
    # chest piece lying flat with the diaphragm up
    cx, cy = 0.085, -0.03
    b.add(lathe([(0.0, 0.0), (0.020, 0.0), (0.0235, 0.002), (0.0235, 0.0075), (0.0215, 0.0095), (0.0, 0.0095)], chrome, segs=48, smooth_angle=30).translate(cx, cy, 0))
    b.add(cylinder(0.0192, 0.0012, diaph, segs=48, caps=(False, True), z0=0.0094).translate(cx, cy, 0))
    b.add(cylinder(0.0034, 0.022, chrome, segs=14, bevel=0.0008).rotate(0, -90, 0).translate(cx - 0.0225, cy, 0.0048))
    # coiled tubing from the stem to the Y split
    pts = [(cx - 0.044, cy, r), (cx - 0.075, cy + 0.01, r), (0.0, 0.035, r), (-0.05, 0.055, r), (-0.085, 0.02, r),
           (-0.07, -0.035, r), (-0.01, -0.06, r * 2.4), (0.04, -0.035, r * 2.6), (0.045, 0.02, r), (0.02, 0.07, r),
           (-0.04, 0.085, r), (-0.09, 0.07, r), (-0.11, 0.035, r)]
    path = catmull(pts, n=7)
    b.add(tube(path, r, tubing, segs=14, split=0.25, tag="tube"))
    # Y split and binaurals
    y0 = np.array([-0.11, 0.035, r])
    b.add(sphere(0.006, tubing, segs=14, rings=8).scale(1.0, 1.0, 0.8).translate(*y0))
    for sgn in (1, -1):
        br = catmull([tuple(y0), (-0.125, 0.035 + sgn * 0.012, r), (-0.135, 0.035 + sgn * 0.03, r), (-0.13, 0.035 + sgn * 0.05, 0.0028)], n=6)
        b.add(tube(br, 0.0037, tubing, segs=12))
        bin_ = catmull([(-0.13, 0.035 + sgn * 0.05, 0.0028), (-0.12, 0.035 + sgn * 0.065, 0.0025), (-0.085, 0.035 + sgn * 0.08, 0.0022),
                        (-0.055, 0.035 + sgn * 0.075, 0.0022)], n=6)
        b.add(tube(bin_, 0.0019, chrome, segs=10))
        b.add(lathe([(0.0, 0.0), (0.0042, 0.0), (0.0052, 0.004), (0.0045, 0.009), (0.0, 0.0105)], tip, segs=16, smooth_angle=40)
              .rotate(0, 90, 0).translate(-0.055, 0.035 + sgn * 0.075, 0.0022))
    b.add(tube(np.array([[-0.118, 0.035 - 0.064, 0.0025], [-0.118, 0.035 + 0.064, 0.0025]]), 0.0016, chrome, segs=8))
    b.col_box((-0.14, -0.07, 0.0), (0.11, 0.12, 0.012), "RUBBER")


