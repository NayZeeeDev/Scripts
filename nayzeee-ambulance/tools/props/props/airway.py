"""
Airway management: bag-valve mask, portable suction unit with canister + Yankauer, endotracheal
tube with tube holder.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL, DecalCanvas, box, catmull, cylinder, lathe, polyline_fillet, prop, rrect, sphere, sweep, torus,
                     tube)

from .common import (align, brand_canvas, knob, m_chrome, m_gloss_black, m_led, m_rubber, m_teal, m_white_plastic,
                     serial_label)
from .parts import boost, m_hosp_dark, m_hosp_grey, m_hosp_white, vents


def _clear(b, name="clear_pvc", alpha=0.26, color=(228, 238, 242)):
    return b.mat(name, color=color, spec=0.9, gloss=0.92, alpha=alpha, layer="alpha", grain=0.0)


# =============================================================================================
# bag-valve mask
# =============================================================================================
BVM_R = 0.05            # mask half width (unit circle radius before the teardrop mapping)


def _teardrop(p, R=BVM_R):
    """Map unit-disc XY to the mask outline: narrow at the nose (+Y), wide at the chin (-Y)."""
    q = p.copy()
    u = np.clip(p[:, 1], -1.2, 1.2)
    w = 0.86 - 0.24 * u
    q[:, 0] = p[:, 0] * R * w
    q[:, 1] = p[:, 1] * R * 1.12
    return q


@prop("nz_amb_bvm", atlas=512, alpha_atlas=256, lod=35, hd=6, doc={
    "title": "Bag-valve mask (adult): clear face mask, elbow, patient valve, squeeze bag, O2 inlet + tubing",
    "origin": "centre of the mask rim (the face contact plane)",
    "axes": "mask rim on the XY plane, face side -Z (the mask dome rises +Z), nose end of the mask +Y; the elbow turns the "
            "valve + bag towards +Y (over the patient's forehead / the medic at the head end)",
    "attach": "face: SKEL_Head (31086) - the head bone's +X runs up through the crown and +Y out of the face, so the rim's "
              "-Z must face the bone's -Y and the mask's +Y the bone's +X: start from pos (0.06, 0.11, 0.0) rot (0, -90, -90) "
              "and tune per ped; hand: the medic's PH_L_Hand (60309) holds the mask (C-E grip) at pos (0.0, 0.0, 0.0) and the "
              "PH_R_Hand (28422) squeezes the bag at (0, 0.21, 0.095) in prop space",
})
def bvm(b):
    shell = _clear(b, "mask_clear", 0.30, (232, 240, 244))
    cushion = b.mat("mask_cushion", color=(66, 172, 196), spec=0.5, gloss=0.7, grain=0.02, edge=0.15)
    white = m_white_plastic(b)
    teal = m_teal(b)
    bag = b.mat("bag_silicone", color=(236, 238, 236), spec=0.45, gloss=0.62, bump="orange_peel", bump_amp=0.00002,
                bump_scale=0.002, grain=0.02, grain_scale=0.04, edge=0.15)
    o2 = b.mat("o2_tube", color=(170, 226, 196), spec=0.6, gloss=0.75, edge=0.1)
    # cushion ring around the rim
    t = np.linspace(0, 2 * math.pi, 72, endpoint=False)
    rim = _teardrop(np.stack([np.cos(t), np.sin(t), np.zeros_like(t)], axis=1))
    rim[:, 2] = 0.0075
    b.add(tube(rim, 0.0075, cushion, segs=10, closed_path=True, tag="cushion"))
    # clear dome
    prof = [(1.0, 0.009), (0.985, 0.018), (0.90, 0.031), (0.70, 0.043), (0.46, 0.051), (0.24, 0.0545), (0.0, 0.0555)]
    dome = lathe([(r, z) for r, z in prof], shell, segs=48, smooth_angle=60, planar_caps=False)
    b.add(dome.deform(_teardrop))
    # 22 mm port + elbow + patient valve
    b.add(cylinder(0.0115, 0.022, white, segs=24, bevel=0.002, z0=0.05))
    el = polyline_fillet([(0, 0, 0.066), (0, 0, 0.096), (0, 0.055, 0.096)], 0.022, 8)
    b.add(tube(el, 0.0112, white, segs=18, tag="elbow"))
    b.add(cylinder(0.0175, 0.036, teal, segs=28, bevel=0.003, z0=0.0).rotate(-90, 0, 0).translate(0, 0.052, 0.096))
    b.add(cylinder(0.006, 0.012, white, segs=14, bevel=0.0015, z0=0.0).translate(0, 0.068, 0.096 + 0.016))
    # squeeze bag along +Y
    bp = [(0.0, 0.0), (0.013, 0.0), (0.013, 0.012), (0.03, 0.03), (0.052, 0.06), (0.061, 0.095), (0.063, 0.13), (0.058, 0.17),
          (0.045, 0.205), (0.026, 0.228), (0.015, 0.236), (0.015, 0.245), (0.0, 0.245)]
    bg = lathe(bp, bag, segs=40, smooth_angle=40)
    b.add(bg.rotate(-90, 0, 0).translate(0, 0.088, 0.096))
    # grip ribs (raised bands) around the bag's waist
    for k in range(5):
        yy = 0.088 + 0.095 + k * 0.012
        rr = float(np.interp(yy - 0.088, [p[1] for p in bp], [p[0] for p in bp]))
        b.add(torus(rr + 0.0004, 0.0012, bag, segs=40, tube_segs=6).rotate(90, 0, 0).translate(0, yy, 0.096))
    # inlet valve + O2 nipple + tubing
    y_in = 0.088 + 0.245
    b.add(cylinder(0.017, 0.03, teal, segs=28, bevel=0.003, z0=0.0).rotate(-90, 0, 0).translate(0, y_in - 0.004, 0.096))
    b.add(lathe([(0.0, 0.0), (0.006, 0.0), (0.006, 0.006), (0.004, 0.012), (0.0045, 0.016), (0.003, 0.024), (0.0, 0.024)], white,
                segs=16, smooth_angle=40).rotate(-90, 0, 0).translate(0, y_in + 0.026, 0.096))
    tp = catmull([(0, y_in + 0.048, 0.096), (0.0, y_in + 0.08, 0.09), (0.04, y_in + 0.12, 0.05), (0.09, y_in + 0.10, 0.012),
                  (0.14, y_in + 0.03, 0.004), (0.20, y_in - 0.02, 0.003)], n=8)
    b.add(tube(tp, 0.0028, o2, segs=8, tag="o2"))
    # decals: print on the bag top + valve label
    dc = DecalCanvas(0.10, 0.04, ppm=4500)
    dc.mark(0.002, 0.004, 0.013)
    dc.text(0.019, 0.0105, "NAYZEEE", 0.0062, fnt="label", anchor="lm", color=(40, 44, 48), spacing=0.0008)
    dc.text(0.002, 0.026, "BVM  ADULT  ·  1600 mL", 0.0042, fnt="label-semi", anchor="lm", color=TEAL, spacing=0.0003)
    dc.text(0.002, 0.034, "SINGLE PATIENT USE", 0.0032, fnt="label-semi", anchor="lm", color=(110, 116, 120))
    b.decal(dc, center=(0, 0.088 + 0.14, 0.096 + 0.063), normal=(0, 0, 1), up=(-1, 0, 0), mats=["bag_silicone"], depth=0.02, min_dot=0.4)
    boost(b, 1.6, mats=["bag_silicone"])
    b.col_box((-0.065, -0.065, -0.002), (0.065, 0.06, 0.12), "PLASTIC")
    b.col_box((-0.065, 0.06, 0.03), (0.065, y_in + 0.05, 0.16), "RUBBER_HOLLOW")


# =============================================================================================
# portable suction unit
# =============================================================================================
@prop("nz_amb_suction", atlas=512, alpha_atlas=256, lod=50, hd=8, preview={
    "cams": [{"name": "detail", "pos": [-0.04, 0.50, 0.14], "target": [-0.04, 0.0, 0.11], "fov": 34}]}, doc={
    "title": "Portable suction unit with 1 L canister, patient tubing and Yankauer tip",
    "origin": "bottom centre of the unit (stands on the ground)",
    "axes": "+Y = front (gauge + controls), +Z up; canister on the +X side, the patient tube runs out to the Yankauer "
            "lying on the ground in front (+Y)",
    "attach": "carry: PH_R_Hand (28422) by the top handle pos (0.03, 0.0, -0.26) rot (0, 0, 0); in-hand Yankauer: hide is not "
              "possible per part - spawn a second suction prop or a native tube when the medic picks the tip up; the tip "
              "lies at (-0.21, 0.27, 0.012) pointing -X",
})
def suction(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    teal = m_teal(b)
    rub = m_rubber(b)
    chrome = m_chrome(b)
    gloss = m_gloss_black(b)
    clear = _clear(b, "canister_clear", 0.22, (232, 240, 244))
    fluid = b.mat("aspirate", color=(206, 126, 112), spec=0.6, gloss=0.85, alpha=0.42, layer="alpha", grain=0.0)
    ptube = _clear(b, "suction_tube", 0.42, (214, 230, 236))
    yank = _clear(b, "yankauer", 0.55, (206, 226, 236))
    led = m_led(b, "led_green", (70, 255, 140))
    dial = b.mat("gauge_face", color=(236, 238, 238), spec=0.3, gloss=0.5, edge=0.1)
    # body + feet + handle
    bx, W, D, H = -0.04, 0.26, 0.16, 0.19
    b.add(box((W, D, H), white, r=0.024, seg=3, center=(bx, 0, 0.012 + H / 2)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(cylinder(0.012, 0.012, rub, segs=12, bevel=0.003).translate(bx + sx * 0.10, sy * 0.055, 0.0))
    hz = 0.012 + H
    hp = polyline_fillet([(bx - 0.09, 0, hz - 0.004), (bx - 0.09, 0, hz + 0.045), (bx + 0.09, 0, hz + 0.045), (bx + 0.09, 0, hz - 0.004)], 0.02, 6)
    b.add(tube(hp, 0.011, dark, segs=14, tag="handle"))
    for sx in (-1, 1):
        b.add(box((0.035, 0.04, 0.014), dark, r=0.006, seg=2, center=(bx + sx * 0.09, 0, hz + 0.003)))
    # front panel
    yf = D / 2
    b.add(box((0.21, 0.004, 0.135), gloss, r=0.006, seg=2, center=(bx, yf + 0.001, 0.112), faces="+y +x -x +z -z"))
    gx, gz = bx + 0.045, 0.118
    b.add(align(cylinder(0.034, 0.008, chrome, segs=36, bevel=0.002, caps=(False, True)), (0, 1, 0), (0, 0, 1), (gx, yf + 0.002, gz)))
    b.add(align(cylinder(0.029, 0.0012, dial, segs=36, caps=(False, True)), (0, 1, 0), (0, 0, 1), (gx, yf + 0.009, gz)))
    b.add(align(sphere(0.029, _clear(b, "gauge_glass", 0.12, (240, 244, 246)), segs=28, rings=8).scale(1, 1, 0.18), (0, 1, 0), (0, 0, 1),
                (gx, yf + 0.0095, gz)))
    b.add(align(knob(teal, 0.03, 0.016), (0, 1, 0), (0, 0, 1), (bx - 0.05, yf + 0.003, 0.135)))
    b.add(box((0.026, 0.008, 0.016), dark, r=0.003, seg=1, center=(bx - 0.05, yf + 0.005, 0.075)))
    b.add(box((0.012, 0.006, 0.012), teal, r=0.002, seg=1, center=(bx - 0.046, yf + 0.009, 0.075)))
    b.add(align(cylinder(0.0025, 0.002, led, segs=10, caps=(False, True)), (0, 1, 0), (0, 0, 1), (bx - 0.075, yf + 0.003, 0.075)))
    # canister on the +X side
    cx = bx + W / 2 + 0.058
    b.add(box((0.02, 0.07, 0.10), dark, r=0.006, seg=2, center=(bx + W / 2 + 0.004, 0, 0.09)))
    b.add(lathe([(0.0, 0.0), (0.052, 0.0), (0.054, 0.006), (0.054, 0.15), (0.05, 0.155), (0.05, 0.004), (0.0, 0.004)], clear,
                segs=40, smooth_angle=40).translate(cx, 0, 0.012))
    b.add(cylinder(0.049, 0.032, fluid, segs=36, z0=0.017).translate(cx, 0, 0))
    b.add(lathe([(0.0, 0.0), (0.057, 0.0), (0.058, 0.004), (0.058, 0.022), (0.054, 0.026), (0.0, 0.026)], white, segs=40,
                smooth_angle=40).translate(cx, 0, 0.012 + 0.152))
    zl = 0.012 + 0.152 + 0.026
    for (px, m) in ((-0.022, white), (0.022, teal)):
        b.add(cylinder(0.0065, 0.018, m, segs=16, bevel=0.0015, z0=zl).translate(cx + px, 0.0, 0))
    b.add(cylinder(0.025, 0.008, grey, segs=24, bevel=0.002, z0=zl).translate(cx, -0.03, 0))
    # vacuum line (body -> lid) + patient tube (lid -> floor -> Yankauer)
    vp = catmull([(bx + W / 2 - 0.01, -0.03, 0.17), (bx + W / 2 + 0.02, -0.035, 0.235), (cx - 0.022, -0.01, 0.245), (cx - 0.022, 0.0, zl + 0.016)], n=8)
    b.add(tube(vp, 0.0055, ptube, segs=10, tag="vac"))
    pp = catmull([(cx + 0.022, 0.0, zl + 0.016), (cx + 0.03, 0.02, zl + 0.07), (cx + 0.09, 0.08, 0.20), (cx + 0.11, 0.17, 0.05),
                  (0.12, 0.25, 0.008), (0.02, 0.28, 0.008), (-0.06, 0.27, 0.010)], n=10)
    b.add(tube(pp, 0.0058, ptube, segs=10, tag="ptube"))
    # Yankauer: handle with grip rings, curved tapered tip, bulb end
    yp = catmull([(-0.06, 0.27, 0.010), (-0.10, 0.268, 0.011), (-0.15, 0.266, 0.012), (-0.185, 0.266, 0.016), (-0.21, 0.27, 0.012)], n=8)
    sc = np.interp(np.linspace(0, 1, len(yp)), [0, 0.55, 0.8, 1.0], [1.0, 0.95, 0.62, 0.5])
    b.add(sweep(np.array([(0.0075 * math.cos(a), 0.0075 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 14, endpoint=False)]),
                yp, yank, scale=sc, up=(0, 0, 1), tag="yankauer", smooth_angle=60))
    b.add(sphere(0.0048, yank, segs=14, rings=8).translate(-0.212, 0.27, 0.012))
    for k in range(4):
        b.add(torus(0.0078, 0.0011, yank, segs=16, tube_segs=6).rotate(0, 90, 0).translate(-0.07 - k * 0.012, 0.2698, 0.0102))
    # decals
    gd = DecalCanvas(0.058, 0.058, ppm=7000)
    for k in range(0, 13):
        a = math.radians(225 - k * 22.5)
        r0, r1 = 0.021 if k % 2 == 0 else 0.0235, 0.026
        gd.line([(0.029 + math.cos(a) * r0, 0.029 - math.sin(a) * r0), (0.029 + math.cos(a) * r1, 0.029 - math.sin(a) * r1)],
                0.0007 if k % 2 else 0.0011, color=(30, 32, 34))
    gd.text(0.029, 0.040, "mmHg", 0.0032, fnt="label-semi", color=(80, 86, 90))
    gd.text(0.029, 0.048, "x 100", 0.0026, fnt="label-semi", color=(80, 86, 90))
    a = math.radians(225 - 7 * 22.5)
    gd.line([(0.029, 0.029), (0.029 + math.cos(a) * 0.021, 0.029 - math.sin(a) * 0.021)], 0.0011, color=(206, 40, 44))
    gd.circle(0.029, 0.029, 0.0022, color=(30, 32, 34))
    gd.rect(0.029 - 0.019, 0.016, 0.006, 0.003, r=0.001, color=TEAL)
    b.decal(gd, center=(gx, yf + 0.0095, gz), normal=(0, 1, 0), up=(0, 0, 1), mats=["gauge_face"], depth=0.002)
    lab = DecalCanvas(0.21, 0.135, ppm=3000)
    lab.mark(0.008, 0.006, 0.014)
    lab.text(0.027, 0.013, "NAYZEEE  SUCTION", 0.0062, fnt="label", anchor="lm", color=(190, 198, 204), spacing=0.0007)
    lab.text(0.155, 0.048, "VACUUM", 0.004, fnt="label-semi", color=(150, 158, 164))
    lab.text(0.155, 0.112, "ON / OFF", 0.004, fnt="label-semi", color=(150, 158, 164))
    lab.text(0.067, 0.112, "LOW  ·  MED  ·  HIGH", 0.0034, fnt="label-semi", color=(150, 158, 164))
    b.decal(lab, center=(bx, yf + 0.0031, 0.112), normal=(0, 1, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.003)
    can = DecalCanvas(0.05, 0.13, ppm=5000)
    for k in range(0, 11):
        y = 0.125 - k * 0.0115
        can.rect(0.0, y, 0.012 if k % 2 == 0 else 0.007, 0.0006, color=(30, 34, 38))
        if k % 2 == 0 and k > 0:
            can.text(0.015, y, str(k * 100), 0.0034, fnt="label-semi", anchor="lm", color=(30, 34, 38))
    can.text(0.03, 0.008, "mL", 0.0036, fnt="label", color=(30, 34, 38))
    b.decal(can, center=(cx, 0.0545, 0.09), normal=(0, 1, 0), up=(0, 0, 1), mats=["canister_clear"], depth=0.01, min_dot=0.5)
    b.decal(brand_canvas(0.16, 0.026, ppm=3200, color=(46, 50, 54), sub_color=TEAL), center=(bx - W / 2 - 0.0001, 0.0, 0.12),
            normal=(-1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    b.decal(vents(0.14, 0.06, 5), center=(bx, -D / 2 - 0.0001, 0.13), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.005)
    b.decal(serial_label(0.07, 0.025, "SUCTION 8  NZ-SU8", "SN 2026-0612"), center=(bx, -D / 2 - 0.0001, 0.06), normal=(0, -1, 0),
            up=(0, 0, 1), mats=["hosp_white"], depth=0.005)
    boost(b, 3.0, mats=["gloss_black", "gauge_face"])
    b.col_box((bx - W / 2, -D / 2, 0.0), (cx + 0.058, D / 2, zl + 0.02), "PLASTIC_HIGH_DENSITY")
    b.col_box((bx - 0.10, -0.012, hz), (bx + 0.10, 0.012, hz + 0.057), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# endotracheal tube + tube holder
# =============================================================================================
ETT_R = 0.14


def _ett_path(n=40, phi1=1.62):
    straight = np.array([(0.0, 0.048, 0.0), (0.0, 0.03, 0.0), (0.0, 0.012, 0.0)])
    phi = np.linspace(0.0, phi1, n)
    arc = np.stack([np.zeros_like(phi), -ETT_R * np.sin(phi), -ETT_R + ETT_R * np.cos(phi)], axis=1)
    return np.concatenate([straight, arc])


@prop("nz_amb_ett", atlas=256, alpha_atlas=256, lod=30, hd=5, doc={
    "title": "Endotracheal tube 7.5 (cuffed, Magill curve) secured in a tube holder",
    "origin": "centre of the tube holder = the lip line",
    "axes": "the tube leaves the mouth along +Y (15 mm connector at +Y), enters along -Y and curves towards -Z (down the "
            "airway); holder bar across the lips along X, straps run back along -Y around the cheeks",
    "attach": "SKEL_Head (31086): rim of the lips is about (0.0, 0.12, -0.04) in bone space for the freemode heads; the prop's "
              "+Y must point out of the mouth (bone +Y) and its -Z towards the neck (bone -X): start from pos "
              "(-0.04, 0.12, 0.0) rot (0, 90, 0) and tune; the BVM / ventilator connects at the connector end (0, 0.075, 0)",
})
def ett(b):
    clear = _clear(b, "ett_pvc", 0.30, (226, 236, 240))
    cuff = _clear(b, "ett_cuff", 0.20, (234, 242, 246))
    pilot = _clear(b, "pilot_balloon", 0.40, (150, 196, 230))
    white = m_white_plastic(b)
    teal = m_teal(b)
    dark = m_hosp_dark(b)
    line = b.mat("rad_line", color=(40, 90, 200), spec=0.4, gloss=0.6, edge=0.1)
    ink = b.mat("depth_ink", color=(24, 26, 28), spec=0.3, gloss=0.5, edge=0.1)
    strap = b.mat("holder_strap", color=(238, 240, 240), spec=0.08, gloss=0.15, bump="webbing", bump_amp=0.00012, bump_scale=0.0012,
                  grain=0.04, grain_scale=0.03, edge=0.1)
    path = _ett_path()
    b.add(tube(path, 0.0054, clear, segs=16, tag="ett"))
    side = path.copy()
    side[:, 0] += 0.0052
    b.add(tube(side, 0.0007, line, segs=5, caps=False, tag="radline"))
    # cuff around the distal arc
    idx = np.arange(len(path))
    cs = path[(idx >= len(path) - 12) & (idx <= len(path) - 3)]
    sc = 1.0 + 1.25 * np.sin(np.linspace(0, math.pi, len(cs))) ** 0.6
    b.add(sweep(np.array([(0.0056 * math.cos(a), 0.0056 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)]),
                cs, cuff, scale=sc, side=(1, 0, 0), tag="cuff", smooth_angle=60))
    # depth marks around the lip line
    for yy in (0.008, -0.004, -0.016):
        b.add(torus(0.00545, 0.00035, ink, segs=20, tube_segs=4).rotate(90, 0, 0).translate(0, yy, 0.0))
    # 15 mm connector
    con = lathe([(0.0, 0.0), (0.0062, 0.0), (0.0062, 0.012), (0.0105, 0.013), (0.0105, 0.018), (0.0076, 0.019), (0.0076, 0.036),
                 (0.0066, 0.037), (0.0, 0.037)], white, segs=24, smooth_angle=40)
    b.add(con.rotate(-90, 0, 0).translate(0, 0.040, 0.0))
    # pilot line + balloon + valve
    pl = catmull([(0.0052, 0.024, 0.0), (0.02, 0.032, -0.012), (0.045, 0.045, -0.04), (0.062, 0.07, -0.055), (0.066, 0.088, -0.058)], n=8)
    b.add(tube(pl, 0.0009, clear, segs=6, tag="pilot"))
    bal = sphere(1.0, pilot, segs=18, rings=10)
    bal.scale(0.0055, 0.011, 0.0032)
    b.add(bal.translate(0.066, 0.099, -0.058))
    b.add(cylinder(0.0038, 0.014, white, segs=14, bevel=0.001, z0=0.0).rotate(-90, 0, 0).translate(0.066, 0.109, -0.058))
    # tube holder: lip bar + clamp + bite block + straps
    b.add(box((0.10, 0.008, 0.022), teal, r=0.004, seg=2, center=(0, 0.0, 0.0)))
    b.add(box((0.024, 0.022, 0.032), dark, r=0.005, seg=2, center=(0, 0.004, 0.0)))
    b.add(align(knob(white, 0.012, 0.008), (0, 0, 1), (0, 1, 0), (0, 0.004, 0.016)))
    b.add(box((0.018, 0.03, 0.014), white, r=0.004, seg=2, center=(0, -0.018, -0.012)))
    for sx in (-1, 1):
        sp = polyline_fillet([(sx * 0.048, 0.0, 0.0), (sx * 0.062, -0.006, 0.0), (sx * 0.075, -0.035, 0.0), (sx * 0.078, -0.07, 0.0)], 0.012, 5)
        b.add(sweep(rrect(0.003, 0.018, 0.001, 1), sp, strap, up=(0, 0, 1), tag="strap"))
    lab = DecalCanvas(0.034, 0.018, ppm=8000)
    lab.mark(0.002, 0.0035, 0.011)
    lab.text(0.016, 0.009, "ID 7.5", 0.0046, fnt="label", anchor="lm", color=(255, 255, 255), spacing=0.0003)
    for sx in (-1, 1):
        b.decal(lab, center=(sx * 0.031, 0.0041, 0.0), normal=(0, 1, 0), up=(0, 0, 1), mats=["teal"], depth=0.003)
    boost(b, 3.0, mats=["teal"])
    b.col_box((-0.08, -0.14, -0.14), (0.08, 0.11, 0.02), "PLASTIC")
