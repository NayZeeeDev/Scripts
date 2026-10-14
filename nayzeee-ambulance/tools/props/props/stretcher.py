"""
Ambulance stretcher / powered cot: base frame on 4 casters, scissor lift, litter frame with folded
side rails, 3-section mattress with pillow, restraint straps, foot-end handle with controls and
battery, head-end loading wheels.
"""
from __future__ import annotations

import numpy as np

from nzprops import (TEAL_HI, WHITE, DecalCanvas, Geo, box, cylinder, lathe, polyline_fillet, prop, rrect, sweep, tube)

from .common import (align, m_alu, m_black_plastic, m_chrome, m_grip, m_rubber, m_teal, m_webbing, serial_label)

Z_MAT_TOP = 0.885


def _caster(b, x, y, wheel_r=0.072):
    blk = m_black_plastic(b)
    rub = m_rubber(b)
    alu = m_alu(b)
    g = Geo()
    w = 0.042
    tyre = lathe([(0.0, -w / 2), (0.045, -w / 2), (wheel_r - 0.012, -w / 2 + 0.001), (wheel_r - 0.002, -w / 2 + 0.006), (wheel_r, 0.0),
                  (wheel_r - 0.002, w / 2 - 0.006), (wheel_r - 0.012, w / 2 - 0.001), (0.045, w / 2), (0.0, w / 2)], rub, segs=36, smooth_angle=35)
    hub = cylinder(0.042, w + 0.003, alu, segs=28, bevel=0.004, z0=-(w + 0.003) / 2)
    wheel = (tyre + hub).rotate(0, 90, 0).translate(x, y - 0.035, wheel_r)
    g += wheel
    # swivel fork + stem
    for sx in (-1, 1):
        g += box((0.008, 0.06, 0.09), blk, r=0.003, seg=1, center=(x + sx * (w / 2 + 0.008), y - 0.02, wheel_r + 0.035))
    g += box((0.064, 0.08, 0.02), blk, r=0.006, seg=2, center=(x, y - 0.015, wheel_r + 0.085))
    g += cylinder(0.009, 0.016, alu, segs=12, bevel=0.002).rotate(0, 90, 0).translate(x - 0.008, y - 0.035, wheel_r)
    g += cylinder(0.014, 0.04, blk, segs=16, bevel=0.003, z0=wheel_r + 0.095).translate(x, y, 0)
    return g


@prop("nz_amb_stretcher", atlas=2048, lod=150, hd=20, falloff=80, doc={
    "title": "Ambulance stretcher / powered cot",
    "origin": "on the ground under the centre of the cot",
    "axes": "length along Y (head end +Y, foot-end handle and controls -Y), width along X, mattress top at z = 0.885",
    "attach": "patient: attach the ped to the stretcher entity pos (0.0, 0.05, 1.33) rot (0, 0, 180) with a lying anim (or use the "
              "mattress top z = 0.885 + ped root offset); push: attach the stretcher to the medic SKEL_Pelvis (11816) / "
              "PH_R_Hand with the foot-end handle (y = -1.02, z = 0.80) in the hands, e.g. stretcher pos (0.0, 1.45, -0.85) "
              "relative to the medic ped; into the ambulance: attach to the vehicle with an offset per model",
})
def stretcher(b):
    frame = b.mat("frame_dark", color=(52, 56, 61), spec=0.45, gloss=0.5, metal=0.4, bump="orange_peel", bump_amp=0.00002,
                  bump_scale=0.003, grain=0.03, grain_scale=0.08, edge=0.55, dirt=0.2)
    alu = m_alu(b)
    chrome = m_chrome(b)
    blk = m_black_plastic(b)
    teal = m_teal(b)
    grip = m_grip(b)
    web = m_webbing(b)
    rub = m_rubber(b)
    vinyl = b.mat("mattress", color=(40, 43, 47), spec=0.32, gloss=0.42, bump="leather", bump_amp=0.00025, bump_scale=0.004,
                  grain=0.04, grain_scale=0.1, edge=0.35, dirt=0.15)
    piping = b.mat("mat_piping", color=(10, 150, 140), spec=0.35, gloss=0.45, edge=0.2)
    battery = b.mat("battery", color=(10, 158, 147), spec=0.4, gloss=0.55, bump="stipple", bump_amp=0.00004, bump_scale=0.0008, edge=0.5)

    # ---- base -----------------------------------------------------------------------------
    zb = 0.19
    for sx in (-1, 1):
        b.add(box((0.05, 1.50, 0.035), frame, r=0.008, seg=2, center=(sx * 0.215, 0.0, zb)))
    for sy in (-1, 1):
        b.add(box((0.48, 0.05, 0.035), frame, r=0.008, seg=2, center=(0.0, sy * 0.75, zb)))
    b.add(box((0.36, 0.42, 0.11), blk, r=0.02, seg=2, center=(0.0, -0.05, zb + 0.02)))
    for x in (-0.215, 0.215):
        for y in (-0.73, 0.73):
            b.add(_caster(b, x, y))
    # ---- scissor lift -----------------------------------------------------------------------
    zl = 0.665
    for sx in (-1, 1):
        x = sx * 0.19
        for (y0, y1) in ((-0.52, 0.46), (0.52, -0.46)):
            p0, p1 = np.array([x, y0, zb + 0.02]), np.array([x, y1, zl - 0.02])
            b.add(sweep(rrect(0.022, 0.05, 0.006, 2), np.array([p0, p1]), alu, side=(1, 0, 0), tag="leg", smooth_angle=50))
        b.add(cylinder(0.016, 0.03, chrome, segs=16, bevel=0.003, z0=-0.015).rotate(0, 90, 0).translate(x, 0.0, (zb + zl) / 2))
        for y in (-0.52, 0.52):
            b.add(cylinder(0.014, 0.05, blk, segs=14, bevel=0.003, z0=-0.025).rotate(0, 90, 0).translate(x, y, zb + 0.02))
    b.add(cylinder(0.008, 0.40, chrome, segs=12).rotate(0, 90, 0).translate(-0.2, 0.0, (zb + zl) / 2))
    # hydraulic actuator
    a0, a1 = np.array([0.0, -0.40, zb + 0.06]), np.array([0.0, 0.20, zl - 0.06])
    b.add(tube(np.array([a0, a0 + (a1 - a0) * 0.55]), 0.03, blk, segs=18))
    b.add(tube(np.array([a0 + (a1 - a0) * 0.5, a1]), 0.017, chrome, segs=14))
    # ---- litter frame -------------------------------------------------------------------------
    for sx in (-1, 1):
        b.add(box((0.045, 1.86, 0.05), alu, r=0.008, seg=2, center=(sx * 0.275, 0.0, zl + 0.02)))
    for y in (-0.92, -0.3, 0.3, 0.92):
        b.add(box((0.55, 0.04, 0.04), alu, r=0.008, seg=2, center=(0.0, y, zl + 0.02)))
    b.add(box((0.54, 1.84, 0.012), blk, r=0.004, seg=1, center=(0.0, 0.0, zl + 0.05), faces="+z +x -x +y -y"))
    # folded side rails
    for sx in (-1, 1):
        lp = rrect(0.78, 0.12, 0.05, 6)
        path = np.stack([np.full(len(lp), sx * 0.315), lp[:, 0], zl + 0.075 + lp[:, 1]], axis=1)
        b.add(tube(path, 0.011, chrome, segs=12, closed_path=True, tag="rail"))
        for y in (-0.33, 0.0, 0.33):
            b.add(cylinder(0.0085, 0.13, chrome, segs=10, z0=-0.065).translate(sx * 0.315, y, zl + 0.075))
        for y in (-0.35, 0.35):
            b.add(box((0.05, 0.04, 0.05), blk, r=0.01, seg=2, center=(sx * 0.296, y, zl + 0.03)))
    # ---- mattress -----------------------------------------------------------------------------
    zm0 = zl + 0.056
    secs = [(-0.92, -0.33), (-0.31, 0.16), (0.18, 0.92)]
    for (y0, y1) in secs:
        h = Z_MAT_TOP - zm0
        b.add(box((0.56, y1 - y0, h), vinyl, r=0.04, seg=3, center=(0.0, (y0 + y1) / 2, zm0 + h / 2), face_density={"-z": 0.3}))
        lp = rrect(0.56 - 0.0234, (y1 - y0) - 0.0234, 0.0283, 6)
        path = np.stack([lp[:, 0], (y0 + y1) / 2 + lp[:, 1], np.full(len(lp), Z_MAT_TOP - 0.0117)], axis=1)
        b.add(tube(path, 0.0045, piping, segs=8, closed_path=True, tag="piping"))
    pillow = box((0.42, 0.24, 0.07), vinyl, r=0.032, seg=3, center=(0.0, 0.73, Z_MAT_TOP + 0.03))

    def squash(p):
        q = p.copy()
        fx = np.clip(1 - (p[:, 0] / 0.21) ** 2, 0, 1)
        fy = np.clip(1 - ((p[:, 1] - 0.73) / 0.12) ** 2, 0, 1)
        q[:, 2] += 0.012 * fx * fy * np.sign(p[:, 2] - (Z_MAT_TOP + 0.03))
        return q
    b.add(pillow.deform(squash))
    # restraint straps lying across the mattress
    for yy in (0.32, -0.12, -0.62):
        lp = [(-0.33, yy, zl + 0.04), (-0.295, yy, Z_MAT_TOP - 0.02), (-0.255, yy, Z_MAT_TOP + 0.0018), (0.255, yy, Z_MAT_TOP + 0.0018),
              (0.295, yy, Z_MAT_TOP - 0.02), (0.33, yy, zl + 0.04)]
        path = polyline_fillet(lp, 0.02, 5)
        b.add(sweep(rrect(0.05, 0.003, 0.0, 1), path, web, side=(0, 1, 0), tag="strap", smooth_angle=35))
        b.add(box((0.06, 0.062, 0.012), blk, r=0.004, seg=2, center=(0.07, yy, Z_MAT_TOP + 0.007)))
        b.add(box((0.022, 0.05, 0.014), teal, r=0.003, seg=1, center=(0.045, yy, Z_MAT_TOP + 0.008)))
    # ---- foot end: telescoping handle, controls, battery --------------------------------------
    hp = polyline_fillet([(-0.25, -0.90, zl + 0.03), (-0.25, -1.0, zl + 0.13), (0.25, -1.0, zl + 0.13), (0.25, -0.90, zl + 0.03)], 0.04, 6)
    b.add(tube(hp, 0.016, alu, segs=14, tag="foothandle"))
    gp = np.array([(-0.17, -1.0, zl + 0.13), (0.17, -1.0, zl + 0.13)])
    b.add(tube(gp, 0.0215, grip, segs=16, tag="footgrip"))
    b.add(box((0.16, 0.06, 0.10), blk, r=0.012, seg=2, center=(0.0, -0.955, zl + 0.055)))
    for k, x in enumerate((-0.04, 0.0, 0.04)):
        m = teal if k != 1 else blk
        b.add(align(cylinder(0.011, 0.005, m, segs=18, bevel=0.0015, caps=(False, True)), (0, -1, 0), (0, 0, 1), (x, -0.985, zl + 0.07)))
    b.add(box((0.17, 0.10, 0.075), battery, r=0.014, seg=3, center=(0.0, -0.80, zl - 0.06)))
    b.add(box((0.15, 0.03, 0.02), blk, r=0.005, seg=2, center=(0.0, -0.85, zl - 0.02)))
    # ---- head end: loading wheels + handle -------------------------------------------------------
    for sx in (-1, 1):
        lw = (lathe([(0.0, -0.016), (0.03, -0.016), (0.038, -0.01), (0.04, 0.0), (0.038, 0.01), (0.03, 0.016), (0.0, 0.016)], rub, segs=28, smooth_angle=35)
              + cylinder(0.02, 0.034, alu, segs=16, z0=-0.017))
        b.add(lw.rotate(0, 90, 0).translate(sx * 0.17, 0.985, zl - 0.035))
        b.add(box((0.05, 0.08, 0.07), blk, r=0.01, seg=2, center=(sx * 0.17, 0.95, zl - 0.005)))
    hh = polyline_fillet([(-0.24, 0.93, zl + 0.03), (-0.24, 0.99, zl + 0.08), (0.24, 0.99, zl + 0.08), (0.24, 0.93, zl + 0.03)], 0.03, 5)
    b.add(tube(hh, 0.014, alu, segs=12, tag="headhandle"))
    # folded IV pole along the head-left corner
    b.add(cylinder(0.0105, 0.62, chrome, segs=12, bevel=0.003).rotate(-90, 0, 0).translate(-0.30, 0.25, zl - 0.005))
    b.add(box((0.03, 0.05, 0.04), blk, r=0.008, seg=2, center=(-0.29, 0.86, zl + 0.0)))

    # ---- decals --------------------------------------------------------------------------------
    for sx in (-1, 1):
        dc = DecalCanvas(0.40, 0.07, ppm=1600)
        dc.lockup(0.01, 0.008, 0.052, color=TEAL_HI, sub_color=TEAL_HI)
        b.decal(dc, center=(sx * 0.281, 0.55, zm0 + 0.055), normal=(sx, 0, 0), up=(0, 0, 1), mats=["mattress"], depth=0.02, min_dot=0.5)
        sd = DecalCanvas(0.42, 0.04, ppm=1600)
        sd.text(0.21, 0.02, "NAYZEEE MEDICAL  ·  POWER COT", 0.014, fnt="brand", color=(232, 236, 238), spacing=0.003, max_w=0.41)
        b.decal(sd, center=(sx * 0.2985, 0.0, zl + 0.02), normal=(sx, 0, 0), up=(0, 0, 1), mats=["alu"], depth=0.01, min_dot=0.6)
    ctl = DecalCanvas(0.16, 0.10, ppm=3000)
    ctl.mark(0.006, 0.006, 0.016)
    ctl.text(0.028, 0.014, "NAYZEEE", 0.007, fnt="brand", anchor="lm", color=WHITE, spacing=0.0012)
    for x, t in ((0.04, "DOWN"), (0.08, "STOP"), (0.12, "UP")):
        ctl.text(x, 0.075, t, 0.0062, fnt="brand", color=(225, 230, 232))
    b.decal(ctl, center=(0.0, -0.9851, zl + 0.055), normal=(0, -1, 0), up=(0, 0, 1), mats=["black_plastic"], depth=0.006)
    bat = DecalCanvas(0.16, 0.06, ppm=2600)
    bat.text(0.08, 0.02, "24V  LI-ION", 0.011, fnt="brand", color=(12, 14, 16))
    bat.rect(0.03, 0.036, 0.10, 0.012, r=0.003, fill=False, width=0.0015, color=(12, 14, 16))
    bat.rect(0.033, 0.039, 0.07, 0.006, r=0.002, color=(12, 14, 16))
    b.decal(bat, center=(0.0, -0.851, zl - 0.06), normal=(0, -1, 0), up=(0, 0, 1), mats=["battery"], depth=0.01)
    b.decal(serial_label(0.08, 0.03, "POWER COT  NZ-PC2", "MAX 318 kg"), center=(0.2405, 0.25, zb), normal=(1, 0, 0), up=(0, 0, 1), mats=["frame_dark"], depth=0.01)

    # texel budget: the mattress and the litter are what the camera sees up close
    for c in b.geo.charts:
        top = float(c.pos[:, 2].max())
        if top < 0.45:
            c.density *= 0.45
        elif c.mat in ("mattress", "mat_piping") and c.density >= 1.0:
            c.density = 1.35
    b.col_box((-0.30, -0.94, 0.72), (0.30, 0.94, Z_MAT_TOP), "LEATHER")
    b.col_box((-0.33, -1.03, 0.62), (0.33, 1.03, 0.80), "METAL_HOLLOW_MEDIUM")
    b.col_box((-0.27, -0.80, 0.0), (0.27, 0.80, 0.22), "METAL_HOLLOW_MEDIUM")
    b.col_box((-0.21, -0.52, 0.22), (-0.17, 0.52, 0.62), "METAL_HOLLOW_SMALL")
    b.col_box((0.17, -0.52, 0.22), (0.21, 0.52, 0.62), "METAL_HOLLOW_SMALL")


