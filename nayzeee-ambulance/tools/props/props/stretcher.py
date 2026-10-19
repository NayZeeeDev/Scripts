"""
Ambulance stretcher / powered cot: base frame on 4 casters, scissor lift, litter frame with folded
side rails, 3-section mattress with pillow, restraint straps, foot-end handle with controls and
battery, head-end loading wheels.

Two models share one builder (same origin + axes, so the transport module can swap them on the
same spot): nz_amb_stretcher (lift raised, mattress top 0.885) and nz_amb_stretcher_low (lift folded
flat, litter 0.42 lower, mattress top 0.465, foot-end push handle swung up to the raised grip height).
"""
from __future__ import annotations

import numpy as np

from nzprops import (TEAL_HI, WHITE, DecalCanvas, Geo, box, cylinder, lathe, polyline_fillet, prop, rrect, sweep, tube)

from .common import (align, asset_tag, cal_sticker, caution_label, label_canvas, led_lens, m_alu, m_black_plastic, m_chrome, m_grip,
                     m_rubber, m_teal, m_webbing, rating_plate, screws)

Z_MAT_TOP = 0.885
Z_LOW_DROP = 0.42              # the folded lift lowers the litter by this much (= Config.Transport.Stretcher.patient.lowZ)
Z_MAT_LOW = Z_MAT_TOP - Z_LOW_DROP
GRIP_Z = 0.795                 # foot-end grip height of the raised cot (zl + 0.13); the lowered cot keeps it


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
    _cot(b, low=False)


@prop("nz_amb_stretcher_low", atlas=2048, lod=150, hd=20, falloff=80, preview={
    "cams": [{"name": "side", "pos": [2.5, -0.45, 0.42], "target": [0.0, -0.15, 0.30], "fov": 50}]}, doc={
    "title": "Ambulance stretcher / powered cot, lowered (scissor lift folded flat)",
    "origin": "on the ground under the centre of the cot - the same origin as nz_amb_stretcher",
    "axes": "same as nz_amb_stretcher: length along Y (head end +Y, foot end -Y), width along X; litter 0.42 m lower, "
            f"mattress top at z = {Z_MAT_LOW:.3f}; the foot-end push handle is swung up so its grip stays at z = {GRIP_Z} "
            "(y = -1.06), where the raised cot's grip is",
    "attach": "swap the networked cot to this model while it is lowered (Config.Transport.Stretcher.lowModel = "
              "'stretcher_low'); patient: the raised recipe + Config.Transport.Stretcher.patient.lowZ (-0.42), i.e. pos "
              "(0.0, 0.05, 0.91) rot (0, 0, 180); push: the same pusher offset as the raised cot (grip at y -1.06, z 0.795)",
})
def stretcher_low(b):
    _cot(b, low=True)


def _cot(b, low=False):
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
    redb = b.mat("release_red", color=(200, 36, 40), spec=0.45, gloss=0.6, edge=0.4)
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
    zl = 0.665 if not low else 0.665 - Z_LOW_DROP
    zt = Z_MAT_TOP if not low else Z_MAT_LOW
    if not low:
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
    else:
        # folded flat: the two legs of each side lie side by side on top of the base rail (z 0.21 .. 0.244),
        # under the litter frame; centre pivot pin + end rollers like the raised lift
        zg = 0.2265
        for sx in (-1, 1):
            for x, (y0, y1) in ((sx * 0.226, (-0.52, 0.46)), (sx * 0.204, (0.52, -0.46))):
                p0, p1 = np.array([x, y0, zg]), np.array([x, y1, zg])
                b.add(sweep(rrect(0.022, 0.034, 0.005, 2), np.array([p0, p1]), alu, side=(1, 0, 0), tag="leg", smooth_angle=50))
                for y in (y0, y1):
                    b.add(cylinder(0.012, 0.03, blk, segs=14, bevel=0.003, z0=-0.015).rotate(0, 90, 0).translate(x, y, zg))
            b.add(cylinder(0.014, 0.05, chrome, segs=16, bevel=0.003, z0=-0.025).rotate(0, 90, 0).translate(sx * 0.215, 0.0, zg))
        b.add(cylinder(0.008, 0.40, chrome, segs=12).rotate(0, 90, 0).translate(-0.2, 0.0, zg))
        # hydraulic actuator, retracted, lying inside the base housing
        a0, a1 = np.array([0.0, -0.42, 0.205]), np.array([0.0, 0.22, 0.212])
        b.add(tube(np.array([a0, a0 + (a1 - a0) * 0.62]), 0.03, blk, segs=18))
        b.add(tube(np.array([a0 + (a1 - a0) * 0.58, a1]), 0.017, chrome, segs=14))
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
        h = zt - zm0
        b.add(box((0.56, y1 - y0, h), vinyl, r=0.04, seg=3, center=(0.0, (y0 + y1) / 2, zm0 + h / 2), face_density={"-z": 0.3}))
        lp = rrect(0.56 - 0.0234, (y1 - y0) - 0.0234, 0.0283, 6)
        path = np.stack([lp[:, 0], (y0 + y1) / 2 + lp[:, 1], np.full(len(lp), zt - 0.0117)], axis=1)
        b.add(tube(path, 0.0045, piping, segs=8, closed_path=True, tag="piping"))
    pillow = box((0.42, 0.24, 0.07), vinyl, r=0.032, seg=3, center=(0.0, 0.73, zt + 0.03))

    def squash(p):
        q = p.copy()
        fx = np.clip(1 - (p[:, 0] / 0.21) ** 2, 0, 1)
        fy = np.clip(1 - ((p[:, 1] - 0.73) / 0.12) ** 2, 0, 1)
        q[:, 2] += 0.012 * fx * fy * np.sign(p[:, 2] - (zt + 0.03))
        return q
    b.add(pillow.deform(squash))
    # restraint straps lying across the mattress
    for yy in (0.32, -0.12, -0.62):
        lp = [(-0.33, yy, zl + 0.04), (-0.295, yy, zt - 0.02), (-0.255, yy, zt + 0.0018), (0.255, yy, zt + 0.0018),
              (0.295, yy, zt - 0.02), (0.33, yy, zl + 0.04)]
        path = polyline_fillet(lp, 0.02, 5)
        b.add(sweep(rrect(0.05, 0.003, 0.0, 1), path, web, side=(0, 1, 0), tag="strap", smooth_angle=35))
        # seat-belt style buckle: black housing, red release button, steel tongue
        b.add(box((0.06, 0.062, 0.013), blk, r=0.005, seg=2, center=(0.07, yy, zt + 0.0075)))
        b.add(box((0.026, 0.044, 0.006), redb, r=0.0025, seg=2, center=(0.058, yy, zt + 0.0145)))
        b.add(box((0.05, 0.034, 0.0025), chrome, r=0.001, seg=1, center=(0.115, yy, zt + 0.004)))
        b.add(box((0.012, 0.056, 0.008), blk, r=0.003, seg=2, center=(0.142, yy, zt + 0.005)))
    # ---- foot end: telescoping handle, controls, battery --------------------------------------
    if not low:
        hp = polyline_fillet([(-0.25, -0.90, zl + 0.03), (-0.25, -1.0, zl + 0.13), (0.25, -1.0, zl + 0.13), (0.25, -0.90, zl + 0.03)], 0.04, 6)
        b.add(tube(hp, 0.016, alu, segs=14, tag="foothandle"))
        gp = np.array([(-0.17, -1.0, zl + 0.13), (0.17, -1.0, zl + 0.13)])
        b.add(tube(gp, 0.0215, grip, segs=16, tag="footgrip"))
    else:
        # push handle swung up on its hinges: the grip stays where the raised cot's grip is
        hp = polyline_fillet([(-0.25, -0.90, zl + 0.03), (-0.25, -1.0, zl + 0.11), (-0.25, -1.06, GRIP_Z), (0.25, -1.06, GRIP_Z),
                              (0.25, -1.0, zl + 0.11), (0.25, -0.90, zl + 0.03)], 0.04, 6)
        b.add(tube(hp, 0.016, alu, segs=14, tag="foothandle"))
        gp = np.array([(-0.17, -1.06, GRIP_Z), (0.17, -1.06, GRIP_Z)])
        b.add(tube(gp, 0.0215, grip, segs=16, tag="footgrip"))
        for sx in (-1, 1):
            b.add(box((0.045, 0.05, 0.055), blk, r=0.01, seg=2, center=(sx * 0.25, -1.0, zl + 0.10)))   # hinge lock
            b.add(cylinder(0.009, 0.06, chrome, segs=12, bevel=0.002, z0=-0.03).rotate(0, 90, 0).translate(sx * 0.25, -1.0, zl + 0.10))
        b.add(box((0.05, 0.016, 0.022), redb, r=0.004, seg=2, center=(0.21, -1.075, GRIP_Z - 0.035)))   # handle release
    b.add(box((0.16, 0.06, 0.10), blk, r=0.012, seg=2, center=(0.0, -0.955, zl + 0.055)))
    for k, x in enumerate((-0.04, 0.0, 0.04)):
        m = teal if k != 1 else redb
        b.add(align(cylinder(0.011, 0.005, m, segs=24, bevel=0.0015, caps=(False, True)), (0, -1, 0), (0, 0, 1), (x, -0.985, zl + 0.07)))
    b.add(led_lens(b, (0.06, -0.985, zl + 0.035), (0, -1, 0), r=0.0022, color=(70, 255, 140), name="led_green"))
    b.add(screws(b, [(sx * 0.07, -0.985, zl + zz) for sx in (-1, 1) for zz in (0.012, 0.098)], (0, -1, 0), d=0.005, segs=10))
    # battery latch + rail, brake pedals on the foot-end casters
    by = 0.0 if not low else -0.06
    b.add(box((0.04, 0.012, 0.016), redb, r=0.003, seg=2, center=(0.0, -0.853 + by, zl - 0.03)))
    for sx in (-1, 1):
        ped = box((0.06, 0.05, 0.012), b.mat("pedal_red" if sx < 0 else "pedal_green", color=(200, 40, 40) if sx < 0 else (40, 160, 70),
                                              spec=0.35, gloss=0.5, bump="diamond", bump_amp=0.0005, bump_scale=0.008, edge=0.6, dirt=0.3),
                  r=0.004, seg=2, center=(0, 0, 0))
        b.add(ped.rotate(-12, 0, 0).translate(sx * 0.215, -0.80, 0.235))
    b.add(box((0.17, 0.10, 0.075), battery, r=0.014, seg=3, center=(0.0, -0.80 + by, zl - 0.06)))
    b.add(box((0.15, 0.03, 0.02), blk, r=0.005, seg=2, center=(0.0, -0.85 + by, zl - 0.02)))
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
        dc = DecalCanvas(0.40, 0.07, ppm=2200)
        dc.text(0.01, 0.024, "FLUID RESISTANT  ·  LATEX FREE", 0.0105, fnt="label", anchor="lm", color=TEAL_HI, spacing=0.0015)
        dc.text(0.01, 0.048, "MATTRESS MS-3  ·  WIPE CLEAN WITH APPROVED DISINFECTANT", 0.0062, fnt="label-semi", anchor="lm",
                color=(170, 176, 180), max_w=0.38)
        b.decal(dc, center=(sx * 0.281, 0.55, zm0 + 0.055), normal=(sx, 0, 0), up=(0, 0, 1), mats=["mattress"], depth=0.02, min_dot=0.5)
        sd = label_canvas(0.30, 0.036, "POWER COT", "PC-2  ·  SAFE WORKING LOAD 318 kg", ppm=2400, color=(232, 236, 238),
                          sub_color=(200, 206, 210), icon="star", icon_color=(40, 110, 210))
        b.decal(sd, center=(sx * 0.2985, 0.0, zl + 0.02), normal=(sx, 0, 0), up=(0, 0, 1), mats=["alu"], depth=0.01, min_dot=0.6)
        if not low:
            b.decal(caution_label(0.08, 0.036, "CAUTION", ["PINCH POINT", "Keep hands clear of the lift"], ppm=3000),
                    center=(sx * 0.2005, 0.35, (zb + zl) / 2), normal=(sx, 0, 0), up=(0, 0, 1), mats=["alu"], depth=0.008, min_dot=0.5)
        else:
            b.decal(caution_label(0.07, 0.028, "CAUTION", ["PINCH POINT", "Keep hands clear of the lift"], ppm=3400),
                    center=(sx * 0.2375, 0.30, 0.2265), normal=(sx, 0, 0), up=(0, 0, 1), mats=["alu"], depth=0.006, min_dot=0.5)
    # stitched seams around each mattress section top
    for (y0, y1) in secs:
        st = DecalCanvas(0.56, y1 - y0, ppm=1600)
        st.stitch_rect(0.0, 0.0, 0.56, y1 - y0, r=0.03, inset=0.032, color=(26, 28, 31), length=0.005, gap=0.0025, width=0.0012)
        b.decal(st, center=(0.0, (y0 + y1) / 2, zt), normal=(0, 0, 1), up=(0, 1, 0), mats=["mattress"], depth=0.01, min_dot=0.6)
    ctl = DecalCanvas(0.16, 0.10, ppm=4000)
    ctl.text(0.008, 0.014, "PC-2  LIFT", 0.0068, fnt="label", anchor="lm", color=WHITE, spacing=0.001)
    for k in range(4):
        ctl.rect(0.118 + k * 0.007, 0.010, 0.005, 0.008, r=0.0008, color=(70, 220, 120) if k < 3 else (60, 64, 68))
    for x, t in ((0.04, "DOWN"), (0.08, "STOP"), (0.12, "UP")):
        ctl.text(x, 0.075, t, 0.0062, fnt="label", color=(225, 230, 232))
    ctl.polygon([(0.04, 0.059), (0.036, 0.053), (0.044, 0.053)], color=(225, 230, 232))
    ctl.polygon([(0.12, 0.051), (0.116, 0.057), (0.124, 0.057)], color=(225, 230, 232))
    ctl.text(0.008, 0.092, "BATTERY", 0.0035, fnt="label-semi", anchor="lm", color=(170, 176, 180))
    b.decal(ctl, center=(0.0, -0.9851, zl + 0.055), normal=(0, -1, 0), up=(0, 0, 1), mats=["black_plastic"], depth=0.006)
    bat = DecalCanvas(0.16, 0.06, ppm=2600)
    bat.text(0.08, 0.02, "24V  LI-ION", 0.011, fnt="label", color=(12, 14, 16))
    bat.rect(0.03, 0.036, 0.10, 0.012, r=0.003, fill=False, width=0.0015, color=(12, 14, 16))
    bat.rect(0.033, 0.039, 0.07, 0.006, r=0.002, color=(12, 14, 16))
    b.decal(bat, center=(0.0, -0.851 + by, zl - 0.06), normal=(0, -1, 0), up=(0, 0, 1), mats=["battery"], depth=0.01)
    b.decal(rating_plate(0.08, 0.03, "POWER COT", "PC-2", "SN 26-03181", rating="24 V DC  ·  SWL 318 kg  ·  IPX6"),
            center=(0.2405, 0.25, zb), normal=(1, 0, 0), up=(0, 0, 1), mats=["frame_dark"], depth=0.01)
    b.decal(cal_sticker(0.03, 0.018, title="SERVICED"), center=(0.2405, -0.25, zb), normal=(1, 0, 0), up=(0, 0, 1), mats=["frame_dark"], depth=0.01)
    b.decal(asset_tag(0.05, 0.014, "COT 07-A", seed=11), center=(-0.2405, 0.25, zb), normal=(-1, 0, 0), up=(0, 0, 1), mats=["frame_dark"], depth=0.01)

    # texel budget: the mattress and the litter are what the camera sees up close
    cut = 0.45 if not low else 0.244
    for c in b.geo.charts:
        top = float(c.pos[:, 2].max())
        if top < cut:
            c.density *= 0.45
        elif c.mat in ("mattress", "mat_piping") and c.density >= 1.0:
            c.density = 1.35
    if not low:
        b.col_box((-0.30, -0.94, 0.72), (0.30, 0.94, zt), "LEATHER")
        b.col_box((-0.33, -1.03, 0.62), (0.33, 1.03, 0.80), "METAL_HOLLOW_MEDIUM")
        b.col_box((-0.27, -0.80, 0.0), (0.27, 0.80, 0.22), "METAL_HOLLOW_MEDIUM")
        b.col_box((-0.21, -0.52, 0.22), (-0.17, 0.52, 0.62), "METAL_HOLLOW_SMALL")
        b.col_box((0.17, -0.52, 0.22), (0.21, 0.52, 0.62), "METAL_HOLLOW_SMALL")
    else:
        b.col_box((-0.30, -0.94, zl + 0.055), (0.30, 0.94, zt), "LEATHER")
        b.col_box((-0.33, -1.03, zl - 0.04), (0.33, 1.03, zl + 0.135), "METAL_HOLLOW_MEDIUM")
        b.col_box((-0.27, -0.80, 0.0), (0.27, 0.80, zl - 0.04), "METAL_HOLLOW_MEDIUM")
        b.col_box((-0.28, -1.09, zl + 0.135), (0.28, -1.03, GRIP_Z + 0.03), "METAL_HOLLOW_SMALL")


