"""
Hospital furniture + equipment: ultrasound cart, blood donation chair, collection mixer / scale,
waiting-room wall screen and the instrument tray table. Origin on the floor (wall screen: back
centre), +Y = the side a person uses / looks at.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL, TEAL_HI, DecalCanvas, Geo, box, catmull, cylinder, extrude, lathe, polyline_fillet, prop, quad, rrect,
                     sphere, sweep, torus, tube)

from .common import (align, brand_canvas, button, knob, m_black_plastic, m_chrome, m_gloss_black, m_led, m_rubber,
                     m_teal, m_white_plastic, serial_label)
from .handheld import syringe_geo
from .parts import (boost, caster, caster_top, m_hosp_dark, m_hosp_grey, m_hosp_white, m_stainless, m_teal_led, m_vinyl,
                    vents)
from .screens import draw_brand_standby, draw_mixer_lcd, draw_ultrasound_ui


def cushion(w, d, h, mat, r=None, bulge=0.010, center=(0, 0, 0), tag="cushion"):
    """Upholstered pad: rounded box whose top face bulges up by `bulge` in the middle."""
    r = min(h * 0.45, 0.05) if r is None else r
    g = box((w, d, h), mat, r=r, seg=3, tag=tag)

    def fn(p):
        q = p.copy()
        fx = np.clip(1 - (p[:, 0] / (w / 2)) ** 2, 0, 1)
        fy = np.clip(1 - (p[:, 1] / (d / 2)) ** 2, 0, 1)
        top = np.clip((p[:, 2] + h / 2) / h, 0, 1)
        q[:, 2] += bulge * fx * fy * top
        return q
    g.deform(fn)
    return g.translate(center)


# =============================================================================================
# ultrasound cart
# =============================================================================================
US_SCREEN = (0.40, 0.25)
US_MON = (-0.14, 0.045, 1.27)    # monitor body centre y, depth, centre z
US_SCREEN_C = (0.0, round(US_MON[0] + US_MON[1] / 2 + 0.0035, 4), US_MON[2] + 0.008)


@prop("nz_amb_us_cart", atlas=1024, lod=90, hd=14, static=True, preview={
    "cams": [{"name": "detail", "pos": [0.0, 0.55, 1.30], "target": [0.0, 0.0, 0.95], "fov": 45}]}, doc={
    "title": "Point-of-care ultrasound cart (eFAST) with monitor, console and probe holders",
    "origin": "floor, centre of the base",
    "axes": "+Y = operator side (console front, screen faces +Y), +Z up; probe holders on +X / -X",
    "screen": f"nz_amb_screen - quad {US_SCREEN[0]} x {US_SCREEN[1]} m (aspect 1.6) centred at {US_SCREEN_C}, "
              "UV 0..1 = visible screen, top-left = (0,0); default = eFAST B-mode frame",
    "attach": "operator stands at (0, 0.75, 0) facing -Y; the in-hand probe is nz_amb_us_probe (hide/show the parked one "
              "is not needed - the holders keep 3 probes); screen camera: from (0, 0.55, 1.30) looking at "
              f"{US_SCREEN_C}",
})
def us_cart(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    teal = m_teal(b)
    blk = m_black_plastic(b)
    gloss = m_gloss_black(b)
    led = m_teal_led(b)
    shell = m_white_plastic(b)
    cable = b.mat("probe_cable", color=(52, 55, 60), spec=0.25, gloss=0.4, edge=0.1)
    lens = b.mat("lens", color=(34, 36, 40), spec=0.5, gloss=0.75, edge=0.2)
    ball = b.mat("trackball", color=(18, 20, 22), spec=0.85, gloss=0.9, edge=0.1)
    gel = b.mat("gel_bottle", color=(40, 150, 200), spec=0.5, gloss=0.7, edge=0.2)

    # ---- base + casters ---------------------------------------------------------------------
    zc = caster_top(0.04)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(caster(b, sx * 0.21, sy * 0.23, r=0.04, w=0.024, yaw=0, lock=(sy > 0)))
    b.add(box((0.52, 0.58, 0.09), dark, r=0.03, seg=3, center=(0, 0, zc + 0.045), face_density={"-z": 0.2}))
    b.add(box((0.50, 0.56, 0.006), led, center=(0, 0, zc + 0.093), faces="+x -x +y -y"))
    b.add(box((0.48, 0.54, 0.04), white, r=0.02, seg=2, center=(0, 0, zc + 0.115)))
    z0 = zc + 0.135
    # ---- column + storage drawer -------------------------------------------------------------
    b.add(box((0.30, 0.24, 0.855 - z0), white, r=0.04, seg=3, center=(0, -0.06, (z0 + 0.855) / 2)))
    b.add(box((0.05, 0.004, 0.42), teal, r=0.002, seg=1, center=(0, 0.061, 0.60), faces="+y +x -x +z -z"))
    b.add(box((0.36, 0.17, 0.14), white, r=0.025, seg=3, center=(0, 0.13, 0.36)))
    hp = polyline_fillet([(-0.08, 0.215, 0.39), (-0.08, 0.232, 0.39), (0.08, 0.232, 0.39), (0.08, 0.215, 0.39)], 0.008, 4)
    b.add(tube(hp, 0.006, dark, segs=10))
    # ---- console ---------------------------------------------------------------------------------
    zt = 0.925
    b.add(box((0.56, 0.50, 0.07), white, r=0.03, seg=3, center=(0, 0.02, zt - 0.035)))
    panel = b.mat("us_panel", color=(54, 58, 63), spec=0.3, gloss=0.46, bump="stipple", bump_amp=0.00003, bump_scale=0.0008, edge=0.5)
    b.add(box((0.46, 0.30, 0.006), panel, r=0.01, seg=2, center=(0, 0.04, zt + 0.001), faces="+z +x -x +y -y"))
    b.add(box((0.50, 0.06, 0.03), grey, r=0.014, seg=2, center=(0, 0.245, zt - 0.006)))
    zp = zt + 0.004
    # trackball + ring
    b.add(sphere(0.021, ball, segs=24, rings=12).translate(0.12, 0.12, zp - 0.006))
    b.add(torus(0.026, 0.004, teal, segs=32, tube_segs=8).translate(0.12, 0.12, zp + 0.001))
    for k, x in enumerate((0.07, 0.17)):
        b.add(box((0.04, 0.022, 0.008), grey, r=0.004, seg=2, center=(x, 0.168, zp + 0.003)))
    # rotary knobs (gain / depth / mode)
    for k, (x, y) in enumerate(((-0.17, 0.15), (-0.11, 0.15), (-0.05, 0.15))):
        b.add(knob(blk, 0.026, 0.014).translate(x, y, zp))
        b.add(cylinder(0.0135, 0.0012, teal if k == 0 else grey, segs=28, caps=(False, True), z0=zp + 0.014).translate(x, y, 0))
    # TGC slide pots
    for k in range(8):
        x = -0.19 + k * 0.018
        b.add(box((0.004, 0.06, 0.002), m_gloss_black(b), center=(x, 0.06, zp + 0.001)))
        b.add(box((0.011, 0.008, 0.009), grey, r=0.002, seg=1, center=(x, 0.06 + math.sin(k * 0.9) * 0.018, zp + 0.005)))
    # keyboard keys (low caps)
    for row in range(3):
        for col in range(10):
            x = -0.006 + col * 0.0215
            y = 0.075 - row * 0.022
            if x > 0.20:
                continue
            b.add(box((0.018, 0.018, 0.005), grey, r=0.0025, seg=1, center=(x, y, zp + 0.0025)))
    # touch panel (tilted at the back of the console)
    tp = box((0.30, 0.012, 0.11), white, r=0.01, seg=2)
    tp += quad((0, 0.0065, 0), (-1, 0, 0), (0, 0, 1), 0.27, 0.085, "touch_glass")
    b.mat("touch_glass", color=(8, 12, 14), spec=0.85, gloss=0.9, edge=0.1)
    b.add(tp.rotate(62, 0, 0).translate(0, -0.15, zt + 0.045))
    # ---- probe holders (+X: two, -X: one + gel) ------------------------------------------------
    cup_prof = [(0.0, 0.0), (0.03, 0.0), (0.034, 0.004), (0.034, 0.075), (0.031, 0.078), (0.027, 0.074), (0.027, 0.006), (0.0, 0.006)]
    holders = [(0.305, 0.12), (0.305, -0.04), (-0.305, 0.12)]
    for (x, y) in holders:
        b.add(box((0.05, 0.08, 0.03), grey, r=0.008, seg=2, center=(x - math.copysign(0.03, x), y, zt - 0.05)))
        b.add(lathe(cup_prof, grey, segs=28, smooth_angle=40).translate(x, y, zt - 0.075))
    probes = [(0.305, 0.12, 0.0), (0.305, -0.04, 15.0), (-0.305, 0.12, -10.0)]
    for k, (x, y, tilt) in enumerate(probes):
        zs_ = np.linspace(0.0, 0.17, 18)
        rad = np.interp(zs_, [0.0, 0.02, 0.05, 0.10, 0.15, 0.17], [0.020, 0.025, 0.019, 0.017, 0.012, 0.006])
        prof = [(0.0, 0.0)] + [(float(r_), float(z_)) for r_, z_ in zip(rad, zs_)] + [(0.0, 0.17)]
        pr = lathe(prof, shell, segs=20, smooth_angle=50)
        pr += cylinder(0.0205, 0.004, lens, segs=20, z0=-0.003)
        pr += cylinder(0.0172, 0.008, teal, segs=20, z0=0.085, caps=(False, False))
        pr.scale(1.0, 0.72 if k != 2 else 0.9, 1.0)
        pr.rotate(tilt, 0, 0)
        b.add(pr.translate(x, y, zt - 0.068))
        top = np.array([x, y - math.sin(math.radians(tilt)) * 0.17, zt - 0.068 + 0.17])
        side = math.copysign(1, x)
        port = (0.12, 0.0, -0.12)[k]
        path = catmull([top, top + (0, 0, 0.05), top + (side * 0.06, -0.04, 0.03), (x + side * 0.07, -0.12, zt - 0.20),
                        (x * 0.7, -0.22, zt - 0.32), (port, -0.26, zt - 0.12), (port, -0.245, zt - 0.045)], n=8)
        b.add(tube(path, 0.0045, cable, segs=8, tag="cable"))
    # gel bottle in its cup on -X
    b.add(lathe(cup_prof, grey, segs=28, smooth_angle=40).translate(-0.305, -0.04, zt - 0.075))
    b.add(box((0.05, 0.08, 0.03), grey, r=0.008, seg=2, center=(-0.275, -0.04, zt - 0.05)))
    gb = lathe([(0.0, 0.0), (0.024, 0.0), (0.026, 0.006), (0.026, 0.12), (0.02, 0.135), (0.0, 0.135)], gel, segs=24, smooth_angle=40)
    gb += lathe([(0.0, 0.135), (0.016, 0.135), (0.016, 0.15), (0.006, 0.158), (0.002, 0.18), (0.0, 0.18)], shell, segs=16, smooth_angle=40)
    b.add(gb.translate(-0.305, -0.04, zt - 0.07))
    # probe connector ports on the rear of the console
    for x in (-0.12, 0.0, 0.12):
        b.add(box((0.08, 0.02, 0.04), dark, r=0.006, seg=2, center=(x, -0.235, zt - 0.04)))
    # rear push handle
    hp = polyline_fillet([(-0.24, -0.225, zt - 0.03), (-0.24, -0.29, zt - 0.03), (0.24, -0.29, zt - 0.03), (0.24, -0.225, zt - 0.03)], 0.03, 5)
    b.add(tube(hp, 0.012, grey, segs=14, tag="handle"))
    # ---- monitor on an arm --------------------------------------------------------------------------
    b.add(box((0.07, 0.07, 0.17), dark, r=0.015, seg=2, center=(0, -0.20, zt + 0.085)))
    b.add(cylinder(0.04, 0.05, grey, segs=24, bevel=0.008, z0=zt + 0.16).translate(0, -0.20, 0))
    b.add(box((0.06, 0.08, 0.06), dark, r=0.012, seg=2, center=(0, -0.20, zt + 0.23)))
    mw, mh = 0.48, 0.33
    my, md, mz = US_MON
    b.add(box((mw, md, mh), white, r=0.016, seg=3, center=(0, my, mz)))
    yf = my + md / 2
    b.add(box((US_SCREEN[0] + 0.03, 0.003, US_SCREEN[1] + 0.03), gloss, r=0.004, seg=1, center=(0, yf + 0.0015, mz + 0.008),
              faces="+y +x -x +z -z"))
    b.screen(quad((0, yf + 0.0035, mz + 0.008), (-1, 0, 0), (0, 0, 1), US_SCREEN[0], US_SCREEN[1], "x", fixed_uv=True),
             image=draw_ultrasound_ui(512, 320), size=(512, 320), mult=1.0)

    # ---- decals ----------------------------------------------------------------------------------------
    bd = brand_canvas(0.22, 0.036, ppm=3000, color=(46, 50, 54), sub_color=TEAL, sub="ECHO")
    b.decal(bd, center=(0, yf + 0.0001, mz - mh / 2 + 0.022), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.006)
    col = brand_canvas(0.24, 0.04, ppm=2400, color=(46, 50, 54), sub_color=TEAL, sub="ULTRASOUND")
    b.decal(col, center=(0.0, 0.0601, 0.80), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    # panel legends: canvas top towards the monitor (-Y) so they read from the operator side; canvas x runs to -X
    kb = DecalCanvas(0.46, 0.30, ppm=1800)
    kb.text(0.06, 0.256, "FREEZE", 0.0068, fnt="label", color=(170, 178, 184))
    kb.text(0.16, 0.256, "MEASURE", 0.0068, fnt="label", color=(170, 178, 184))
    kb.text(0.28, 0.286, "GAIN", 0.0062, fnt="label", color=TEAL_HI)
    kb.text(0.34, 0.286, "DEPTH", 0.0062, fnt="label", color=(170, 178, 184))
    kb.text(0.40, 0.286, "MODE", 0.0062, fnt="label", color=(170, 178, 184))
    kb.text(0.357, 0.128, "TGC", 0.0062, fnt="label", color=(140, 148, 154))
    kb.text(0.14, 0.122, "eFAST  ·  LUNG  ·  CARDIAC", 0.0058, fnt="label-semi", color=(140, 148, 154))
    b.decal(kb, center=(0, 0.04, zp - 0.0005), normal=(0, 0, 1), up=(0, -1, 0), mats=["us_panel"], depth=0.004)
    tpd = DecalCanvas(0.27, 0.085, ppm=2400)
    tpd.rect(0, 0, 0.27, 0.085, color=(8, 12, 14))
    for k, t in enumerate(("B", "M", "CFM", "PW", "3D")):
        x = 0.012 + k * 0.05
        tpd.rect(x, 0.012, 0.042, 0.03, r=0.004, color=(18, 60, 58) if k == 0 else (22, 26, 30))
        tpd.text(x + 0.021, 0.027, t, 0.009, fnt="label", color=TEAL_HI if k == 0 else (170, 178, 184))
    tpd.text(0.012, 0.062, "PRESET  TRAUMA  ·  C5-2", 0.0068, fnt="label-semi", anchor="lm", color=(150, 158, 164))
    tpd.rect(0.012, 0.072, 0.246, 0.004, r=0.002, color=(30, 36, 40))
    tpd.rect(0.012, 0.072, 0.15, 0.004, r=0.002, color=TEAL)
    nrm = np.array([0.0, math.cos(math.radians(62)), math.sin(math.radians(62))])
    up = np.array([0.0, -math.sin(math.radians(62)), math.cos(math.radians(62))])
    ctr = np.array([0.0, -0.15, zt + 0.045]) + nrm * 0.0066
    b.decal(tpd, center=tuple(ctr), normal=tuple(nrm), up=tuple(up), mats=["touch_glass"], depth=0.004)
    b.decal(serial_label(0.08, 0.03, "ECHO 9  NZ-US9", "SN 2026-3120"), center=(0, -0.1801, 0.60), normal=(0, -1, 0), up=(0, 0, 1),
            mats=["hosp_white"], depth=0.01)
    b.decal(vents(0.36, 0.12, 6), center=(0, my - md / 2 - 0.0001, mz + 0.06), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.005)
    for c in b.geo.charts:
        if float(c.pos[:, 2].max()) < 0.3:
            c.density *= 0.5
    boost(b, 2.2, mats=["us_panel", "touch_glass"])
    b.col_box((-0.26, -0.29, 0.0), (0.26, 0.29, z0), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.15, -0.18, z0), (0.15, 0.06, 0.855), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.18, 0.045, 0.29), (0.18, 0.215, 0.43), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.34, -0.23, 0.855), (0.34, 0.275, zt + 0.02), "PLASTIC_HIGH_DENSITY")
    b.col_box((-mw / 2, my - md / 2, mz - mh / 2 - 0.25), (mw / 2, yf, mz + mh / 2), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# blood donation chair
# =============================================================================================
DC_SEAT = 0.53
DC_BACK = 32.0          # backrest recline from vertical (deg)
DC_LEG = 28.0           # leg rest drop below horizontal (deg)


@prop("nz_amb_donation_chair", atlas=1024, lod=90, hd=14, static=True, falloff=60, doc={
    "title": "Reclining blood donation chair with padded armrests",
    "origin": "floor, under the centre of the seat",
    "axes": f"the occupant faces +Y (leg rest towards +Y, backrest towards -Y reclined {DC_BACK:g} deg), +Z up; the "
            "donor arm rests on the +X armrest (the seated ped's right arm)",
    "attach": f"seat top z = {DC_SEAT}; attach / place the donor at (0.0, -0.08, {DC_SEAT}) + the sit clip's root height, "
              "rot (0, 0, 0) (ped faces +Y) - a reclined sit clip (e.g. the dentist / beach chair clips) matches the back; "
              "venepuncture site (right antecubital) rests at about (0.36, 0.06, 0.70); place nz_amb_blood_mixer on the "
              "floor at (0.62, 0.15, 0) and the IV stand at (-0.55, 0.0, 0)",
})
def donation_chair(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    teal = m_teal(b)
    rub = m_rubber(b)
    vinyl = m_vinyl(b, "chair_vinyl", (22, 108, 108))
    piping = b.mat("chair_piping", color=(12, 70, 70), spec=0.35, gloss=0.45, edge=0.2)
    # base + pedestal
    b.add(box((0.60, 0.88, 0.05), dark, r=0.02, seg=2, center=(0, 0.04, 0.025), face_density={"-z": 0.15}))
    b.add(box((0.62, 0.90, 0.006), rub, r=0.003, seg=1, center=(0, 0.04, 0.003), faces="+x -x +y -y"))
    b.add(box((0.34, 0.46, 0.31), white, r=0.05, seg=3, center=(0, -0.02, 0.05 + 0.155)))
    b.add(box((0.24, 0.30, 0.04), dark, r=0.012, seg=2, center=(0, -0.02, 0.375)))
    # seat frame + side shrouds
    b.add(box((0.52, 0.52, 0.05), grey, r=0.02, seg=2, center=(0, 0.0, 0.415)))
    for sx in (-1, 1):
        b.add(box((0.022, 0.46, 0.10), white, r=0.008, seg=2, center=(sx * 0.27, 0.0, 0.40)))
    # seat cushion
    b.add(cushion(0.58, 0.54, 0.10, vinyl, r=0.04, bulge=0.012, center=(0, 0.0, DC_SEAT - 0.06)))
    # backrest (built upright about the hinge, then reclined)
    hinge_b = np.array([0.0, -0.25, 0.47])
    back = Geo()
    back += cushion(0.56, 0.12, 0.76, vinyl, r=0.045, bulge=0.0, center=(0, -0.06, 0.40))
    back += box((0.50, 0.05, 0.68), grey, r=0.02, seg=2, center=(0, -0.135, 0.38))
    back += cushion(0.34, 0.11, 0.20, vinyl, r=0.04, bulge=0.0, center=(0, -0.03, 0.88))
    back += box((0.06, 0.04, 0.10), dark, r=0.01, seg=2, center=(0, -0.10, 0.77))
    lp = rrect(0.56 - 0.03, 0.76 - 0.03, 0.03, 5)
    path = np.stack([lp[:, 0], np.full(len(lp), 0.0005), 0.40 + lp[:, 1]], axis=1)
    back += tube(path, 0.005, piping, segs=8, closed_path=True, tag="piping")
    back.rotate(DC_BACK, 0, 0)
    b.add(back.translate(hinge_b))
    # hinge brackets
    for sx in (-1, 1):
        b.add(box((0.03, 0.10, 0.10), dark, r=0.01, seg=2, center=(sx * 0.25, -0.25, 0.44)))
    # leg rest (built level about its hinge, then dropped)
    hinge_l = np.array([0.0, 0.25, 0.47])
    leg = Geo()
    leg += cushion(0.52, 0.52, 0.09, vinyl, r=0.04, bulge=0.008, center=(0, 0.27, 0.01))
    leg += box((0.46, 0.46, 0.03), grey, r=0.012, seg=2, center=(0, 0.26, -0.05))
    leg += box((0.44, 0.035, 0.16), dark, r=0.012, seg=2, center=(0, 0.555, -0.03))
    leg += box((0.42, 0.012, 0.13), rub, r=0.004, seg=1, center=(0, 0.535, -0.03), faces="-y +x -x +z -z")
    leg.rotate(-DC_LEG, 0, 0)
    b.add(leg.translate(hinge_l))
    # leg rest strut
    b.add(tube(np.array([(0, 0.10, 0.25), (0, 0.42, 0.37)]), 0.022, grey, segs=16))
    # armrests: post + long pad (slightly splayed); +X pad longer for the donor arm
    for sx in (-1, 1):
        L = 0.70 if sx > 0 else 0.60
        b.add(box((0.05, 0.07, 0.22), grey, r=0.015, seg=2, center=(sx * 0.33, -0.06, 0.56)))
        arm = Geo()
        arm += cushion(0.12, L, 0.065, vinyl, r=0.028, bulge=0.006, center=(0, L / 2 - 0.12, 0.0))
        arm += box((0.09, L - 0.08, 0.02), grey, r=0.008, seg=2, center=(0, L / 2 - 0.12, -0.04))
        arm.rotate(0, 0, -sx * 5.0)
        b.add(arm.translate(sx * 0.35, -0.12, 0.69))
    # hand pendant on a coiled cable at the -X side
    b.add(box((0.045, 0.025, 0.11), white, r=0.01, seg=2, center=(-0.40, 0.18, 0.52)))
    for k, m in enumerate((teal, grey, grey)):
        b.add(align(button(m, 0.011, 0.003), (0, 1, 0), (0, 0, 1), (-0.40, 0.193, 0.55 - k * 0.022)))
    t = np.linspace(0, 1, 200)
    hel = np.stack([-0.39 + 0.007 * np.cos(t * 2 * math.pi * 16), 0.17 + 0.007 * np.sin(t * 2 * math.pi * 16), 0.575 + t * 0.10], axis=1)
    b.add(tube(hel, 0.0022, m_black_plastic(b), segs=6, tag="coil"))
    # decals
    bd = brand_canvas(0.20, 0.034, ppm=2400, color=(46, 50, 54), sub_color=TEAL, sub="DONOR")
    b.decal(bd, center=(0, 0.2101, 0.22), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.02)
    bk = brand_canvas(0.22, 0.04, ppm=2200, color=(236, 240, 242), sub_color=TEAL_HI, sub="DONOR")
    bc = hinge_b + np.array([0, -0.161 * math.cos(math.radians(DC_BACK)) - 0.45 * math.sin(math.radians(DC_BACK)),
                             0.45 * math.cos(math.radians(DC_BACK)) - 0.161 * math.sin(math.radians(DC_BACK))])
    rear_n = (0.0, -math.cos(math.radians(DC_BACK)), -math.sin(math.radians(DC_BACK)))
    rear_up = (0.0, -math.sin(math.radians(DC_BACK)), math.cos(math.radians(DC_BACK)))
    b.decal(bk, center=tuple(bc), normal=rear_n, up=rear_up, mats=["hosp_grey"], depth=0.03)
    pend = DecalCanvas(0.04, 0.10, ppm=5000)
    pend.mark(0.012, 0.004, 0.012)
    for k, t_ in enumerate(("TRENDEL", "UP", "DOWN")):
        pend.text(0.02, 0.036 + k * 0.022, t_, 0.0034, fnt="label-semi", color=(60, 66, 70), max_w=0.036)
    b.decal(pend, center=(-0.40, 0.1931, 0.53), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.004)
    b.decal(serial_label(0.08, 0.03, "DONOR CHAIR  NZ-DC3", "MAX 200 kg"), center=(-0.1701, -0.02, 0.20), normal=(-1, 0, 0),
            up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    for c in b.geo.charts:
        if float(c.pos[:, 2].max()) < 0.35:
            c.density *= 0.5
    b.col_box((-0.30, -0.40, 0.0), (0.30, 0.48, 0.05), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.17, -0.25, 0.05), (0.17, 0.21, 0.39), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.29, -0.27, 0.39), (0.29, 0.27, DC_SEAT), "LEATHER")
    b.col_box((-0.28, -0.44, 0.47), (0.28, -0.22, 0.72), "LEATHER")
    b.col_box((-0.28, -0.58, 0.72), (0.28, -0.34, 0.95), "LEATHER")
    b.col_box((-0.28, -0.72, 0.95), (0.28, -0.47, 1.18), "LEATHER")
    b.col_box((-0.26, 0.25, 0.36), (0.26, 0.50, 0.50), "LEATHER")
    b.col_box((-0.26, 0.50, 0.20), (0.26, 0.76, 0.40), "LEATHER")
    for sx in (-1, 1):
        L = 0.70 if sx > 0 else 0.60
        b.col_box((sx * 0.35 - 0.065, -0.24, 0.45), (sx * 0.35 + 0.065, -0.24 + L, 0.725), "LEATHER")


# =============================================================================================
# blood collection mixer / scale
# =============================================================================================
BM_TRAY_Z = 0.318


@prop("nz_amb_blood_mixer", atlas=512, lod=50, hd=8, preview={
    "cams": [{"name": "detail", "pos": [0.0, 0.55, 0.25], "target": [0.0, 0.0, 0.17], "fov": 32}]}, doc={
    "title": "Blood collection mixer / scale with a rocking tray",
    "origin": "bottom centre (stands on the floor or a table)",
    "axes": "+Y = front (display + buttons), +Z up; the rocking tray on top tilts 6 deg towards the front, tube clamp on +X",
    "screen": "nz_amb_screen - LCD quad 0.110 x 0.055 m (aspect 2.0) on the front panel, UV 0..1 = LCD, top-left = (0,0); "
              "default = '312 mL / 450' collection screen",
    "attach": f"blood bag (nz_amb_bloodbag_*; origin = its hanging slot) lying on the tray: pos (-0.15, 0.0, {BM_TRAY_Z + 0.008:.3f}) "
              "with the bag extending +X and its label up (rot (90, 0, -90) for rotation order 2 - verify in game); the "
              "line runs through the clamp at (0.155, 0.04, 0.24)",
})
def blood_mixer(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    teal = m_teal(b)
    rub = m_rubber(b)
    gloss = m_gloss_black(b)
    chrome = m_chrome(b)
    red_btn = b.mat("red_btn", color=(196, 44, 48), spec=0.45, gloss=0.6, edge=0.4)
    mat = b.mat("tray_mat", color=(16, 122, 124), spec=0.18, gloss=0.3, bump="ribs", bump_amp=0.0001, bump_scale=0.003, edge=0.1)
    led = m_led(b, "led_green", (70, 255, 140))
    # body
    W, D, H = 0.28, 0.23, 0.25
    b.add(box((W, D, H), white, r=0.025, seg=3, center=(0, 0, 0.012 + H / 2)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(cylinder(0.013, 0.012, rub, segs=14, bevel=0.003).translate(sx * 0.11, sy * 0.085, 0.0))
    yf = D / 2
    b.add(box((0.22, 0.004, 0.16), gloss, r=0.006, seg=2, center=(0, yf + 0.001, 0.165), faces="+y +x -x +z -z"))
    # front panel layout in panel coordinates (u from the viewer's left = world +X, v down from the top)
    def P(u, v):
        return (0.11 - u, yf + 0.003, 0.245 - v)
    b.screen(quad(P(0.075, 0.0575), (-1, 0, 0), (0, 0, 1), 0.11, 0.055, "x", fixed_uv=True), image=draw_mixer_lcd(256, 128),
             size=(256, 128), mult=1.0)
    for (u, v, m, sz) in ((0.185, 0.045, teal, 0.016), (0.185, 0.085, red_btn, 0.016), (0.04, 0.125, grey, 0.013),
                          (0.075, 0.125, grey, 0.013), (0.11, 0.125, grey, 0.013)):
        b.add(align(button(m, sz, 0.0035, kind="sq"), (0, 1, 0), (0, 0, 1), P(u, v)))
    b.add(align(cylinder(0.0025, 0.002, led, segs=10, caps=(False, True)), (0, 1, 0), (0, 0, 1), P(0.185, 0.125)))
    # rocking tray on its yoke
    b.add(box((0.10, 0.10, 0.04), dark, r=0.012, seg=2, center=(0, 0, 0.262 + 0.02)))
    tray = Geo()
    tray += box((0.29, 0.21, 0.016), grey, r=0.008, seg=2, center=(0, 0, 0))
    loop = rrect(0.29 - 0.012, 0.21 - 0.012, 0.012, 5)
    path = np.stack([loop[:, 0], loop[:, 1], np.full(len(loop), 0.008)], axis=1)
    tray += sweep(rrect(0.008, 0.012, 0.003, 2) + np.array([0.0, 0.006]), path, grey, closed_path=True, up=(0, 0, 1), tag="rim")
    tray += box((0.26, 0.18, 0.003), mat, center=(0, 0, 0.0095), faces="+z")
    tray.rotate(-6.0, 0, 0)
    b.add(tray.translate(0, 0, BM_TRAY_Z - 0.0095))
    # tube clamp on +X + line hook on -X
    b.add(box((0.03, 0.06, 0.05), dark, r=0.008, seg=2, center=(0.153, 0.04, 0.24)))
    b.add(box((0.012, 0.064, 0.006), m_black_plastic(b), center=(0.169, 0.04, 0.24)))
    b.add(box((0.008, 0.02, 0.05), teal, r=0.003, seg=1, center=(0.17, 0.065, 0.255)))
    hk = polyline_fillet([(-0.14, -0.06, 0.22), (-0.17, -0.06, 0.22), (-0.17, -0.06, 0.26), (-0.16, -0.06, 0.27)], 0.008, 4)
    b.add(tube(hk, 0.003, chrome, segs=8))
    # decals
    lab = DecalCanvas(0.22, 0.16, ppm=3200)
    lab.mark(0.008, 0.006, 0.014)
    lab.text(0.027, 0.013, "COLLECT 450", 0.0078, fnt="label", anchor="lm", color=(190, 198, 204), spacing=0.0008)
    lab.text(0.170, 0.045, "START", 0.005, fnt="label", anchor="rm", color=(190, 198, 204))
    lab.text(0.170, 0.085, "STOP", 0.005, fnt="label", anchor="rm", color=(190, 198, 204))
    lab.text(0.185, 0.146, "POWER", 0.0042, fnt="label-semi", color=(160, 168, 174))
    for u, t in ((0.04, "TARE"), (0.075, "MIX"), (0.11, "MENU")):
        lab.text(u, 0.146, t, 0.0042, fnt="label-semi", color=(160, 168, 174))
    b.decal(lab, center=(0, yf + 0.0031, 0.165), normal=(0, 1, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.003)
    sd = brand_canvas(0.16, 0.026, ppm=3000, color=(46, 50, 54), sub_color=TEAL, sub="DONOR")
    b.decal(sd, center=(W / 2 + 0.0001, -0.04, 0.10), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    b.decal(vents(0.16, 0.06, 5), center=(0, -D / 2 - 0.0001, 0.17), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.006)
    b.decal(serial_label(0.07, 0.025, "COLLECT 450  NZ-BM1", "SN 2026-0451"), center=(0, -D / 2 - 0.0001, 0.07), normal=(0, -1, 0),
            up=(0, 0, 1), mats=["hosp_white"], depth=0.006)
    boost(b, 3.5, mats=["gloss_black"])
    b.col_box((-W / 2, -D / 2, 0.0), (W / 2, D / 2, 0.262), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.145, -0.105, 0.262), (0.145, 0.105, BM_TRAY_Z + 0.02), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# waiting room wall screen
# =============================================================================================
TV_SCREEN = (1.568, 0.882)


@prop("nz_amb_tv_board", atlas=512, lod=80, hd=15, static=True, doc={
    "title": "Waiting-room wall screen 1.6 x 0.9 m (thin bezel)",
    "origin": "centre of the BACK face - the prop sits flat on a wall when placed at the wall surface",
    "axes": "screen faces +Y (into the room), +Z up, everything at y >= 0 (depth 0.033)",
    "screen": f"nz_amb_screen - 1024 x 576 texture embedded in the drawable's own dictionary (txd 'nz_amb_tv_board'), quad "
              f"{TV_SCREEN[0]} x {TV_SCREEN[1]} m (16:9) centred at (0, 0.0343, 0.008), UV 0..1 = visible screen, top-left = "
              "(0,0); default = black with the teal NAYZEEE mark. Replace it with a DUI (AddReplaceTexture('nz_amb_tv_board', "
              "'nz_amb_screen', duiTxd, duiTex))",
    "attach": "place against a wall: position = wall surface point at the desired screen-centre height (about 2.0 - 2.3 m), "
              "heading = the wall normal's heading (screen +Y points into the room)",
})
def tv_board(b):
    gloss = m_gloss_black(b)
    body = b.mat("tv_body", color=(22, 23, 26), spec=0.4, gloss=0.6, bump="brushed", bump_amp=0.000006, bump_scale=0.0005, metal=0.5, edge=0.4)
    back = b.mat("tv_back", color=(40, 42, 46), spec=0.25, gloss=0.4, bump="stipple", bump_amp=0.00003, bump_scale=0.0008, edge=0.3)
    led = m_led(b, "led_white", (230, 240, 255))
    W, H = 1.60, 0.92
    # stepped rear (slim edge look) + main slab
    b.add(box((1.44, 0.012, 0.76), back, r=0.004, seg=1, center=(0, 0.006, 0.0), faces="+x -x +z -z -y"))
    b.add(box((W, 0.021, H), body, r=0.004, seg=2, center=(0, 0.012 + 0.0105, 0.0)))
    yf = 0.033
    b.add(box((TV_SCREEN[0] + 0.004, 0.0006, TV_SCREEN[1] + 0.004), gloss, center=(0, yf + 0.0003, 0.008), faces="+y"))
    b.screen(quad((0, yf + 0.0013, 0.008), (-1, 0, 0), (0, 0, 1), TV_SCREEN[0], TV_SCREEN[1], "x", fixed_uv=True),
             image=draw_brand_standby(1024, 576), size=(1024, 576), mult=1.0)
    b.add(align(cylinder(0.0022, 0.0008, led, segs=10, caps=(False, True)), (0, 1, 0), (0, 0, 1), (0.74, yf, -0.4465)))
    lab = DecalCanvas(0.12, 0.016, ppm=6000)
    lab.mark(0.0, 0.002, 0.012)
    lab.text(0.016, 0.008, "NAYZEEE", 0.0062, fnt="label", anchor="lm", color=(170, 176, 180), spacing=0.0012)
    b.decal(lab, center=(0.0, yf + 0.0001, -0.4465), normal=(0, 1, 0), up=(0, 0, 1), mats=["tv_body"], depth=0.003)
    b.decal(vents(0.60, 0.05, 8, vertical=True), center=(0, -0.0001, 0.30), normal=(0, -1, 0), up=(0, 0, 1), mats=["tv_back"], depth=0.004)
    b.col_box((-W / 2, 0.0, -H / 2), (W / 2, yf, H / 2), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# instrument tray table
# =============================================================================================
ST_TOP = 0.905
ST_DRAPE = ST_TOP + 0.004


def _ring_handle(mat, r=0.011, t=0.0024):
    return torus(r, t, mat, segs=20, tube_segs=6)


def _pliers(steel, length, jaw, open_deg=6.0, rings=True, ratchet=False, fine=False):
    """Scissors / hemostat / needle driver lying flat: ring handles at -Y, tips at +Y."""
    g = Geo()
    for s in (-1, 1):
        a = math.radians(s * open_deg / 2)
        piv = np.array([0.0, 0.0, 0.0])
        tipx = math.sin(a) * jaw
        tip = piv + np.array([-tipx, jaw * math.cos(a), 0.0])
        wj = 0.0035 if fine else 0.005
        blade = sweep(rrect(0.0022, 0.0028, 0.0008, 1), np.array([piv + (s * 0.001, 0, 0), tip]), steel, up=(0, 0, 1),
                      scale=np.array([[wj / 0.0022, 1.0], [0.45, 0.8]]), tag="blade", smooth_angle=60)
        g += blade
        hl = length - jaw - 0.022
        hp = np.array([[0.0, 0.0, 0.0], [s * 0.012, -hl * 0.6, 0.0], [s * 0.018, -hl, 0.0]])
        g += tube(catmull(hp, n=6), 0.0018, steel, segs=6, tag="shank")
        if rings:
            g += _ring_handle(steel).translate(s * 0.022, -hl - 0.010, 0.0)
        if ratchet:
            g += box((0.004, 0.012, 0.002), steel, center=(s * 0.006, -hl + 0.006, 0.0))
    g += cylinder(0.0035, 0.004, steel, segs=12, z0=-0.002)
    return g


@prop("nz_amb_surgery_tray", atlas=1024, alpha_atlas=256, lod=60, hd=10, static=True, falloff=90, doc={
    "title": "Instrument tray table (stainless, two shelves) with a draped instrument set",
    "origin": "floor, under the centre of the top",
    "axes": "top 0.80 (X) x 0.50 (Y); push handle at -X, drape overhangs the front (+Y); +Z up",
    "attach": f"drape surface z = {ST_DRAPE:.3f}; instruments lie in a row along X from (-0.30, -0.12) to (0.05, -0.12) "
              "with the tips towards +Y (scalpel first at x = -0.30); kidney dish (0.24, 0.10), saline bowl (0.24, -0.12), "
              "gauze (0.03, 0.12), syringe (-0.18, 0.12); place it beside the bed / X-ray table head end",
})
def surgery_tray(b):
    steel = m_stainless(b)
    blk = m_black_plastic(b)
    drape = b.mat("drape", color=(22, 128, 128), spec=0.08, gloss=0.16, bump="fabric", bump_amp=0.00012, bump_scale=0.0016,
                  grain=0.05, grain_scale=0.06, edge=0.1, color2=(18, 110, 110))
    gauze = b.mat("gauze", color=(240, 241, 238), spec=0.06, gloss=0.12, bump="fabric", bump_amp=0.00012, bump_scale=0.0012,
                  grain=0.03, grain_scale=0.03, edge=0.1, color2=(222, 224, 220))
    pack = b.mat("suture_pack", color=(232, 234, 236), spec=0.4, gloss=0.6, edge=0.2)
    blue = b.mat("wrap_blue", color=(62, 120, 176), spec=0.12, gloss=0.2, bump="fabric", bump_amp=0.0001, bump_scale=0.002, edge=0.15,
                 color2=(52, 104, 156))
    handle_tex = b.mat("scalpel_grip", color=(150, 156, 162), spec=0.7, gloss=0.6, metal=1.0, bump="knurl", bump_amp=0.00008, bump_scale=0.0015, edge=0.2)
    saline = b.mat("saline", color=(205, 228, 238), spec=0.6, gloss=0.85, alpha=0.18, layer="alpha", grain=0.0)
    # ---- frame --------------------------------------------------------------------------------
    TW, TD = 0.80, 0.50
    zc = caster_top(0.035)
    legs = [(-0.36, -0.21), (0.36, -0.21), (-0.36, 0.21), (0.36, 0.21)]
    for (x, y) in legs:
        b.add(caster(b, x, y, r=0.035, w=0.022, lock=(x > 0)))
        b.add(cylinder(0.014, ST_TOP - 0.03 - zc, steel, segs=16, bevel=0.003, z0=zc).translate(x, y, 0))
    for z in (0.30, ST_TOP - 0.03):
        for sy in (-1, 1):
            b.add(box((TW - 0.06, 0.02, 0.025), steel, r=0.005, seg=1, center=(0, sy * 0.21, z - 0.0125)))
        for sx in (-1, 1):
            b.add(box((0.02, TD - 0.06, 0.025), steel, r=0.005, seg=1, center=(sx * 0.36, 0, z - 0.0125)))
    # top tray with rim, lower shelf with rim
    for (z, w, d, rim) in ((ST_TOP, TW, TD, 0.018), (0.30, TW - 0.04, TD - 0.04, 0.03)):
        b.add(box((w, d, 0.012), steel, r=0.004, seg=1, center=(0, 0, z - 0.006)))
        loop = rrect(w - 0.006, d - 0.006, 0.01, 4)
        path = np.stack([loop[:, 0], loop[:, 1], np.full(len(loop), z)], axis=1)
        b.add(sweep(rrect(0.004, rim, 0.0015, 2) + np.array([0.0, rim / 2]), path, steel, closed_path=True, up=(0, 0, 1), tag="rim"))
    # push handle at -X
    hp = polyline_fillet([(-0.37, -0.18, ST_TOP - 0.03), (-0.45, -0.18, ST_TOP + 0.02), (-0.45, 0.18, ST_TOP + 0.02), (-0.37, 0.18, ST_TOP - 0.03)], 0.04, 6)
    b.add(tube(hp, 0.0115, steel, segs=14, tag="handle"))
    b.add(tube(np.array([(-0.45, -0.11, ST_TOP + 0.02), (-0.45, 0.11, ST_TOP + 0.02)]), 0.0155, blk, segs=16, tag="grip"))
    # ---- drape (flat on the top, folding over the front edge) ----------------------------------------
    b.add(box((TW - 0.03, TD - 0.03, 0.003), drape, center=(0, -0.01, ST_TOP + 0.0025), faces="+z"))
    fold = polyline_fillet([(0.0, TD / 2 - 0.03, ST_DRAPE), (0.0, TD / 2 - 0.012, ST_TOP + 0.021), (0.0, TD / 2 + 0.006, ST_TOP + 0.021),
                            (0.0, TD / 2 + 0.012, ST_TOP - 0.01), (0.0, TD / 2 + 0.016, ST_TOP - 0.17)], 0.008, 5)
    b.add(sweep(rrect(TW - 0.03, 0.003, 0.0, 1), fold, drape, side=(1, 0, 0), tag="drape_fold", smooth_angle=60))
    z = ST_DRAPE
    # ---- instruments -------------------------------------------------------------------------------
    y0 = -0.12
    # scalpel: knurled flat handle + blade
    b.add(box((0.011, 0.11, 0.0035), handle_tex, r=0.0015, seg=1, center=(-0.30, y0 - 0.015, z + 0.00175)))
    bl = extrude([(0.0, 0.0), (0.004, 0.0), (0.0045, 0.022), (0.0, 0.040), (-0.0035, 0.024)], 0.0006, steel)
    b.add(bl.translate(-0.30, y0 + 0.04, z + 0.0015))
    # tissue forceps
    for s in (-1, 1):
        fp = catmull(np.array([(-0.255, y0 - 0.07, z + 0.0035), (-0.255 + s * 0.006, y0 - 0.0, z + 0.004),
                               (-0.255 + s * 0.001, y0 + 0.07, z + 0.0015)]), n=6)
        b.add(sweep(rrect(0.006, 0.0012, 0.0004, 1), fp, steel, up=(0, 0, 1), scale=np.linspace(1.0, 0.45, len(fp)), tag="forceps"))
    # scissors, needle driver, two hemostats
    b.add(_pliers(steel, 0.16, 0.075, open_deg=4, fine=True).translate(-0.205, y0 + 0.02, z + 0.0026))
    b.add(_pliers(steel, 0.15, 0.040, open_deg=0, ratchet=True).translate(-0.145, y0 + 0.01, z + 0.0026))
    b.add(_pliers(steel, 0.14, 0.05, open_deg=0, ratchet=True).translate(-0.085, y0 + 0.015, z + 0.0026))
    b.add(_pliers(steel, 0.14, 0.05, open_deg=0, ratchet=True).translate(-0.035, y0 + 0.015, z + 0.0026))
    # retractor (bent flat strip)
    rp = polyline_fillet([(0.02, y0 - 0.06, z + 0.0012), (0.02, y0 + 0.07, z + 0.0012), (0.02, y0 + 0.085, z + 0.012)], 0.008, 5)
    b.add(sweep(rrect(0.014, 0.0016, 0.0005, 1), rp, steel, up=(0, 0, 1), tag="retractor"))
    # stainless saline bowl
    bowl = lathe([(0.0, 0.0), (0.045, 0.0), (0.065, 0.012), (0.08, 0.040), (0.083, 0.042), (0.077, 0.042), (0.061, 0.016),
                  (0.044, 0.004), (0.0, 0.004)], steel, segs=40, smooth_angle=30)
    b.add(bowl.translate(0.24, -0.12, z))
    b.add(cylinder(0.071, 0.002, saline, segs=40, z0=0.028, caps=(False, True)).translate(0.24, -0.12, z))
    # kidney dish (oval bowl)
    kd = lathe([(0.0, 0.0), (0.03, 0.0), (0.05, 0.012), (0.058, 0.03), (0.061, 0.032), (0.055, 0.032), (0.046, 0.014),
                (0.028, 0.004), (0.0, 0.004)], steel, segs=40, smooth_angle=30)
    kd.scale(1.7, 1.0, 1.0)

    def kidney(p):
        q = p.copy()
        q[:, 1] -= 0.018 * np.exp(-(p[:, 0] / 0.05) ** 2)
        return q
    kd.deform(kidney)
    b.add(kd.translate(0.24, 0.10, z))
    # gauze stack + suture packs + syringe
    for k in range(3):
        g = box((0.09, 0.09, 0.006), gauze, r=0.0025, seg=1, center=(0, 0, 0.003))
        g.rotate(0, 0, k * 7 - 7)
        b.add(g.translate(0.03, 0.12, z + k * 0.006))
    for k in range(3):
        b.add(box((0.038, 0.095, 0.003), pack, r=0.002, seg=1, center=(0.09 + k * 0.045, 0.13, z + 0.0015)))
    sy = syringe_geo(b, fill=0.5, cap=True)
    sy.rotate(0, 0, 90)
    b.add(sy.translate(-0.13, 0.12, z + 0.0082))
    # ---- lower shelf: wrapped sets + glove box ---------------------------------------------------------
    b.add(box((0.26, 0.20, 0.07), blue, r=0.012, seg=2, center=(-0.18, 0.0, 0.30 + 0.035)))
    b.add(box((0.20, 0.16, 0.05), blue, r=0.01, seg=2, center=(-0.17, 0.02, 0.30 + 0.07 + 0.025)))
    b.add(box((0.24, 0.12, 0.09), b.mat("glove_box", color=(236, 238, 240), spec=0.25, gloss=0.4, edge=0.25), r=0.004, seg=1,
              center=(0.18, 0.02, 0.30 + 0.045)))
    # ---- decals ------------------------------------------------------------------------------------------
    gb = DecalCanvas(0.24, 0.09, ppm=2400)
    gb.mark(0.008, 0.008, 0.02)
    gb.text(0.034, 0.018, "NAYZEEE", 0.0095, fnt="label", anchor="lm", color=(36, 40, 44), spacing=0.001)
    gb.text(0.12, 0.052, "NITRILE GLOVES", 0.011, fnt="label", color=(36, 40, 44), spacing=0.0008)
    gb.rect(0.06, 0.066, 0.12, 0.016, r=0.003, color=TEAL)
    gb.text(0.12, 0.074, "SIZE  M  ·  100", 0.0072, fnt="label-semi", color=(255, 255, 255))
    b.decal(gb, center=(0.18, 0.0801, 0.345), normal=(0, 1, 0), up=(0, 0, 1), mats=["glove_box"], depth=0.01)
    for k, t in enumerate(("3-0 NYLON", "4-0 VICRYL", "2-0 SILK")):
        sp = DecalCanvas(0.038, 0.095, ppm=6000)
        sp.rect(0, 0, 0.038, 0.022, color=(30, 90, 170) if k == 1 else ((40, 40, 44) if k == 2 else (20, 130, 120)))
        sp.text(0.019, 0.011, t, 0.0042, fnt="label", color=(255, 255, 255), max_w=0.034)
        sp.mark(0.003, 0.028, 0.008)
        sp.text(0.013, 0.032, "NAYZEEE", 0.0028, fnt="label", anchor="lm", color=(40, 44, 48))
        sp.text(0.019, 0.05, "SUTURE", 0.004, fnt="label-semi", color=(40, 44, 48))
        sp.text(0.019, 0.06, "75 cm  ·  3/8 C", 0.0026, fnt="label-semi", color=(100, 106, 110))
        sp.circle(0.019, 0.078, 0.009, fill=False, width=0.0008, color=(120, 126, 130))
        b.decal(sp, center=(0.09 + k * 0.045, 0.13, z + 0.0031), normal=(0, 0, 1), up=(0, -1, 0), mats=["suture_pack"], depth=0.003)
    wrap = DecalCanvas(0.20, 0.05, ppm=3000)
    wrap.rect(0.0, 0.017, 0.20, 0.016, color=(240, 240, 236))
    wrap.text(0.10, 0.025, "STERILE  ·  MINOR SET", 0.0062, fnt="label", color=(40, 44, 48), spacing=0.0006)
    b.decal(wrap, center=(-0.17, 0.1001, 0.395), normal=(0, 1, 0), up=(0, 0, 1), mats=["wrap_blue"], depth=0.01)
    bd = brand_canvas(0.18, 0.026, ppm=3000, color=(236, 240, 242), sub_color=TEAL_HI, sub="SURGICAL")
    b.decal(bd, center=(0.0, TD / 2 + 0.018, ST_TOP - 0.10), normal=(0, 1, 0), up=(0, 0, 1), mats=["drape"], depth=0.01)
    boost(b, 3.0, mats=["suture_pack"])
    boost(b, 1.8, mats=["glove_box", "wrap_blue"])
    b.col_box((-TW / 2, -TD / 2, ST_TOP - 0.04), (TW / 2, TD / 2, ST_TOP + 0.02), "METAL_SOLID_SMALL")
    b.col_box((-TW / 2 + 0.02, -TD / 2 + 0.02, 0.27), (TW / 2 - 0.02, TD / 2 - 0.02, 0.31), "METAL_SOLID_SMALL")
    for (x, y) in legs:
        b.col_cyl((x, y, ST_TOP / 2), 0.016, ST_TOP - 0.02, "z", "METAL_HOLLOW_SMALL")
    b.col_box((-0.46, -0.19, ST_TOP - 0.05), (-0.36, 0.19, ST_TOP + 0.035), "METAL_HOLLOW_SMALL")
