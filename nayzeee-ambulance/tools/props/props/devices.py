"""
Electronic devices: portable patient monitor, monitor/defibrillator, EMS pager.
All three carry an emissive screen whose texture is named 'nz_amb_screen' (replace it at runtime
with a DUI: AddReplaceTexture('<model name>', 'nz_amb_screen', duiTxd, duiTex)).

Detail: front / rear shell split lines, screwed rubber bumpers, speaker grilles, battery doors with
latches, connector blocks, rating plates, calibration + caution stickers.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (DecalCanvas, Geo, box, catmull, cylinder, draw_defib_ui, draw_monitor_ui, draw_pager_lcd, lathe,
                     polyline_fillet, prop, quad, rrect, sphere, sweep, tube, vec)

from .common import (align, asset_tag, button, cal_sticker, caution_label, label_canvas, led_lens, lightning, m_alu,
                     m_black_plastic, m_gloss_black, m_steel, rating_plate, screw, screws, strain_relief,
                     text_canvas)

LEGEND = (214, 218, 220)


def _bezel_lip(b, mat, w, h, r, at_y, cx, cz, prof_w=0.0035, prof_h=0.0018):
    """Thin raised lip around a screen opening (rounded rectangle path in the XZ plane)."""
    loop = rrect(w, h, r, 4)
    path = np.stack([cx + loop[:, 0], np.full(len(loop), at_y), cz + loop[:, 1]], axis=1)
    prof = rrect(prof_w, prof_h, prof_h * 0.45, 2) + vec(0, prof_h / 2)
    return b.add(sweep(prof, path, mat, closed_path=True, up=(0, 1, 0), smooth_angle=50, tag="lip"))


def _knurled_knob(b, d, h, mat_name="knob_knurl", color=(34, 36, 40)):
    m = b.mat(mat_name, color=color, spec=0.3, gloss=0.42, bump="ribs_u", bump_amp=0.00012, bump_scale=0.0013, edge=0.5, dirt=0.2)
    top = b.mat(mat_name + "_top", color=color, spec=0.35, gloss=0.5, bump="orange_peel", bump_amp=0.00001, bump_scale=0.001, edge=0.5)
    g = lathe([(d / 2, 0.0), (d / 2, h * 0.82), (d / 2 - h * 0.12, h)], m, segs=40, smooth_angle=50)
    g += lathe([(d / 2 - h * 0.12, h), (d * 0.3, h * 0.97), (0.0, h * 0.94)], top, segs=40, smooth_angle=60)
    return g


def _parting_lines(b, mat, W, D, H, zc, y=0.0, width=0.0005, depth=0.00022):
    """Front / rear shell split line running around a box body at depth y (top, bottom, both sides)."""
    for sz in (1, -1):
        dc = DecalCanvas(W + 0.02, D + 0.02, ppm=5000)
        yy = (D + 0.02) / 2 - y * sz
        dc.groove([(0.0, yy), (W + 0.02, yy)], width=width, depth=depth)
        b.decal(dc, center=(0, 0, zc + sz * H / 2), normal=(0, 0, sz), up=(0, sz, 0), mats=[mat], depth=0.01, min_dot=0.5)
    for sx in (1, -1):
        dc = DecalCanvas(D + 0.02, H + 0.02, ppm=5000)
        xx = (D + 0.02) / 2 + y * sx
        dc.groove([(xx, 0.0), (xx, H + 0.02)], width=width, depth=depth)
        b.decal(dc, center=(sx * W / 2, 0, zc), normal=(sx, 0, 0), up=(0, 0, 1), mats=[mat], depth=0.01, min_dot=0.5)


# =============================================================================================
# portable patient monitor  0.30 (X) x 0.064 (Y) x 0.235 (Z incl. handle)
# =============================================================================================
@prop("nz_amb_monitor", atlas=2048, lod=70, hd=12, doc={
    "title": "Portable patient monitor",
    "origin": "bottom centre (sits on surfaces)",
    "axes": "+Y = screen side (front), +Z up; control column beside the screen on +X (the viewer's left when facing the "
            "screen), connector panel on the +X side face",
    "attach": "carry: PH_R_Hand (28422) pos (0.0, -0.03, -0.24) rot (0, 0, 90) holding the top handle; "
              "on stretcher/bed: place on the mattress or attach to the stretcher entity at its foot end",
    "screen": "nz_amb_screen - quad 0.180 x 0.112 m (aspect 1.61), UV 0..1 = full visible screen, top-left = (0,0)",
})
def monitor(b):
    body = b.mat("charcoal", color=(46, 49, 54), spec=0.3, gloss=0.42, bump="stipple", bump_amp=0.00006, bump_scale=0.0008,
                 grain=0.03, grain_scale=0.05, edge=0.6, dirt=0.25, wear_color=(96, 100, 106))
    rub = b.mat("bumper", color=(30, 31, 34), spec=0.12, gloss=0.2, bump="rubber", bump_amp=0.00008, bump_scale=0.0007,
                grain=0.05, grain_scale=0.03, edge=0.3, dirt=0.3, wear_color=(70, 72, 76))
    panel = m_gloss_black(b)
    blk = m_black_plastic(b)
    grip = b.mat("grip", color=(28, 29, 31), spec=0.12, gloss=0.18, bump="ribs", bump_amp=0.00022, bump_scale=0.0028, edge=0.25,
                 dirt=0.2)
    alu = m_alu(b)
    red_btn = b.mat("red_btn", color=(196, 44, 48), spec=0.45, gloss=0.6, edge=0.4)
    teal_btn = b.mat("teal_btn", color=(14, 150, 140), spec=0.45, gloss=0.6, edge=0.4)
    grey_btn = b.mat("grey_btn", color=(74, 78, 84), spec=0.35, gloss=0.5, edge=0.45)
    lamp = b.mat("alarm_lamp", color=(150, 26, 28), spec=0.85, gloss=0.9, bump="ribs_u", bump_amp=0.00006, bump_scale=0.0018, edge=0.2)

    W, D, H = 0.29, 0.05, 0.19
    zc = 0.10
    b.add(box((W, D, H), body, r=0.012, seg=3, center=(0, 0, zc), face_density={"-z": 0.4}))
    # rubber corner bumpers, each held by two screws on the front + back
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.add(box((0.042, 0.064, 0.042), rub, r=0.013, seg=3, center=(sx * 0.129, 0, zc + sz * 0.079)))
            for sy in (1, -1):
                b.add(screw(b, (sx * 0.136, sy * 0.032, zc + sz * 0.086), (0, sy, 0), d=0.0045, segs=10, color=(60, 62, 66)))
    # front panel
    fy = D / 2
    b.add(box((0.236, 0.004, 0.17), panel, r=0.006, seg=2, center=(-0.003, fy + 0.001, zc), faces="+y +x -x +z -z"))
    py = fy + 0.003
    sw, sh = 0.180, 0.112
    scx, scz = -0.024, zc + 0.008
    b.screen(quad((scx, py + 0.0004, scz), (-1, 0, 0), (0, 0, 1), sw, sh, "x", fixed_uv=True),
             image=draw_monitor_ui(512, 319), size=(512, 256), mult=1.0)
    _bezel_lip(b, blk, sw + 0.008, sh + 0.008, 0.004, py, scx, scz)
    # control column on the viewer's left of the screen (+X): ALARM / NIBP / MENU / HOME + rotary encoder
    bx = 0.087
    for k, m in enumerate((red_btn, grey_btn, grey_btn, grey_btn)):
        z = zc + 0.060 - k * 0.026
        b.add(align(button(m, 0.017, 0.0035, kind="sq", bevel=0.0012), (0, 1, 0), (0, 0, 1), (bx, py, z)))
    b.add(align(_knurled_knob(b, 0.026, 0.012), (0, 1, 0), (0, 0, 1), (bx, py, zc - 0.050)))
    b.add(align(cylinder(0.0155, 0.0012, teal_btn, segs=40, caps=(False, True)), (0, 1, 0), (0, 0, 1), (bx, py, zc - 0.050)))
    b.add(align(sphere(0.0011, m_steel(b), segs=8, rings=4), (0, 1, 0), (0, 0, 1), (bx + 0.008, py + 0.012, zc - 0.044)))
    # power button + charge / power LEDs under the screen (viewer's right)
    b.add(align(button(grey_btn, 0.012, 0.003, bevel=0.0009), (0, 1, 0), (0, 0, 1), (-0.095, py, zc - 0.069)))
    b.add(led_lens(b, (-0.078, py, zc - 0.069), (0, 1, 0), r=0.0018, color=(70, 255, 140), name="led_green"))
    b.add(led_lens(b, (-0.068, py, zc - 0.069), (0, 1, 0), r=0.0018, color=(255, 170, 40), name="led_amber"))
    # alarm light bar on top (ribbed red lens in a black bezel)
    b.add(box((0.078, 0.022, 0.006), blk, r=0.003, seg=2, center=(0, 0.006, zc + H / 2 + 0.0015)))
    b.add(box((0.07, 0.016, 0.008), lamp, r=0.004, seg=2, center=(0, 0.006, zc + H / 2 + 0.003)))
    # top carry handle on two screwed posts
    hz = zc + H / 2
    path = polyline_fillet([(-0.105, -0.004, hz - 0.004), (-0.105, -0.004, hz + 0.034), (0.105, -0.004, hz + 0.034), (0.105, -0.004, hz - 0.004)], 0.018, 8)
    b.add(tube(path, 0.0085, grip, segs=16, tag="handle"))
    for sx in (-1, 1):
        b.add(box((0.03, 0.03, 0.012), body, r=0.005, seg=2, center=(sx * 0.105, -0.004, hz + 0.004)))
        b.add(screw(b, (sx * 0.105, -0.004 - 0.015, hz + 0.004), (0, -1, 0), d=0.004, segs=10))
    # +X side connector panel: four colour-coded sensor ports, USB + LAN block, DC-in jack
    sxp = W / 2
    b.add(box((0.004, 0.036, 0.14), blk, r=0.003, seg=2, center=(sxp + 0.001, 0, zc), faces="+x +y -y +z -z"))
    cols = [(60, 200, 110), (40, 120, 220), (220, 222, 224), (230, 190, 40)]
    for k, c in enumerate(cols):
        z = zc + 0.05 - k * 0.026
        ring = b.mat(f"port_ring{k}", color=c, spec=0.4, gloss=0.55, edge=0.3)
        b.add(align(cylinder(0.0075, 0.004, ring, segs=24, bevel=0.0008, caps=(False, True)), (1, 0, 0), (0, 0, 1), (sxp + 0.003, 0, z)))
        b.add(align(cylinder(0.0042, 0.0045, panel, segs=18, caps=(False, True)), (1, 0, 0), (0, 0, 1), (sxp + 0.003, 0, z)))
    b.add(box((0.003, 0.022, 0.026), m_steel(b), r=0.001, seg=1, center=(sxp + 0.0035, 0, zc - 0.056)))
    b.add(align(cylinder(0.0045, 0.004, alu, segs=16, bevel=0.0006, caps=(False, True)), (1, 0, 0), (0, 0, 1), (sxp + 0.003, 0, zc - 0.034)))
    # back: hanging bracket (screwed), battery door with latch, rear feet
    by = -D / 2
    b.add(box((0.12, 0.006, 0.07), alu, r=0.003, seg=2, center=(0, by - 0.003, zc + 0.035)))
    hook = polyline_fillet([(-0.04, by - 0.006, zc + 0.07), (-0.04, by - 0.024, zc + 0.07), (-0.04, by - 0.024, zc + 0.05)], 0.008, 6)
    for hx in (-0.04, 0.04):
        p = hook.copy()
        p[:, 0] = hx
        b.add(sweep(rrect(0.014, 0.003, 0.001, 2), p, alu, side=(1, 0, 0), tag="hook"))
    b.add(screws(b, [(hx, by - 0.006, hz2) for hx in (-0.05, 0.05) for hz2 in (zc + 0.008, zc + 0.062)], (0, -1, 0), d=0.005, segs=10))
    b.add(box((0.026, 0.004, 0.012), grey_btn, r=0.002, seg=2, center=(-0.07, by - 0.0015, zc - 0.035)))
    for fx in (-0.1, 0.1):
        for fyy in (-0.012, 0.012):
            b.add(cylinder(0.006, 0.003, rub, segs=14, bevel=0.001).translate(fx, fyy, -0.0005))

    # decals ------------------------------------------------------------------------------
    _parting_lines(b, "charcoal", W, D, H, zc, y=-0.004)
    b.decal(label_canvas(0.085, 0.0125, "PATIENT MONITOR", ppm=7000, color=LEGEND, icon="star", icon_color=(40, 110, 210)),
            center=(-0.045, py + 0.0001, zc + 0.0765), normal=(0, 1, 0), mats=[panel], depth=0.004)
    b.decal(text_canvas([("PM-8", 0.044, 0.006, 0.0042, "label", LEGEND, "rm", 0.0006)], 0.046, 0.012, ppm=8000),
            center=(0.068, py + 0.0001, zc + 0.0765), normal=(0, 1, 0), mats=[panel], depth=0.004)
    # button legends to the right of the column (icons drawn on the keys)
    legends = DecalCanvas(0.028, 0.12, ppm=9000)
    for k, t in enumerate(("ALARM", "NIBP", "MENU", "HOME")):
        legends.text(0.014, 0.0045 + k * 0.026 + 0.0115, t, 0.0021, fnt="label-semi", color=LEGEND, max_w=0.026)
    legends.text(0.014, 0.118, "SELECT", 0.0021, fnt="label-semi", color=LEGEND)
    b.decal(legends, center=(bx, py + 0.0001, zc + 0.006), normal=(0, 1, 0), mats=[panel], depth=0.003)
    keys = DecalCanvas(0.016, 0.1, ppm=12000)
    for k in range(4):
        y = 0.008 + k * 0.026
        if k == 0:     # bell
            keys.polygon([(0.008, y - 0.0035), (0.0105, y + 0.002), (0.0055, y + 0.002)], color=(250, 236, 236), height=0.00005)
            keys.circle(0.008, y + 0.003, 0.0008, color=(250, 236, 236))
        elif k == 1:   # cuff
            keys.rect(0.0045, y - 0.002, 0.007, 0.004, r=0.0008, fill=False, width=0.0006, color=(230, 232, 234))
            keys.circle(0.008, y + 0.0035, 0.0009, color=(230, 232, 234))
        elif k == 2:   # menu lines
            for j in range(3):
                keys.rect(0.0045, y - 0.0025 + j * 0.002, 0.007, 0.0007, color=(230, 232, 234))
        else:          # home
            keys.polygon([(0.008, y - 0.003), (0.0115, y), (0.0045, y)], color=(230, 232, 234))
            keys.rect(0.0055, y, 0.005, 0.003, color=(230, 232, 234))
    b.decal(keys, center=(bx, py + 0.0036, zc + 0.060 - 0.039 - 0.0005 + 0.0005), normal=(0, 1, 0),
            mats=["red_btn", "grey_btn"], depth=0.003)
    spk = DecalCanvas(0.06, 0.012, ppm=9000)
    spk.perforate(0.003, 0.003, 14, 3, 0.0038, 0.00085, depth=0.0005)
    b.decal(spk, center=(0.015, py + 0.0001, zc - 0.069), normal=(0, 1, 0), mats=[panel], depth=0.003)
    pw = DecalCanvas(0.03, 0.01, ppm=9000)
    pw.circle(0.005, 0.005, 0.0022, fill=False, width=0.0005, color=LEGEND)
    pw.rect(0.0047, 0.0022, 0.0006, 0.0028, color=LEGEND)
    pw.text(0.017, 0.0052, "AC  BAT", 0.0016, fnt="label-semi", color=LEGEND)
    b.decal(pw, center=(-0.082, py + 0.0001, zc - 0.081), normal=(0, 1, 0), mats=[panel], depth=0.003)
    side = DecalCanvas(0.03, 0.14, ppm=6000)
    for k, t in enumerate(("ECG", "SpO2", "NIBP", "TEMP")):
        side.text(0.015, 0.016 + k * 0.026 - 0.0105, t, 0.0026, fnt="label-semi", color=(205, 208, 210))
    side.text(0.015, 0.093, "USB  LAN", 0.0022, fnt="label-semi", color=(205, 208, 210))
    side.text(0.015, 0.118, "DC 15V", 0.0022, fnt="label-semi", color=(205, 208, 210))
    b.decal(side, center=(sxp + 0.003, 0.0, zc - 0.002), normal=(1, 0, 0), up=(0, 0, 1), mats=[blk], depth=0.003)
    rear = DecalCanvas(0.29, 0.19, ppm=4000)
    rear.groove_rect(0.035, 0.115, 0.115, 0.06, r=0.004, width=0.0006, depth=0.0003)
    rear.text(0.0925, 0.135, "Li-ion  11.1 V  5200 mAh", 0.0034, fnt="label-semi", color=(150, 155, 160))
    rear.text(0.0925, 0.145, "PUSH TO RELEASE", 0.0026, fnt="label-semi", color=(150, 155, 160))
    rear.slots(0.20, 0.008, 0.07, 0.04, 6, vertical=True, fill=0.4, depth=0.0008)
    b.decal(rear, center=(0, by, zc), normal=(0, -1, 0), up=(0, 0, 1), mats=["charcoal"], depth=0.004)
    b.decal(rating_plate(0.064, 0.024, "PATIENT MONITOR", "PM-8", "SN 26-11804", rating="15 V DC  2.5 A  /  Li-ion 11.1 V"),
            center=(0.072, by - 0.0001, zc - 0.052), normal=(0, -1, 0), mats=["charcoal"], depth=0.004)
    b.decal(cal_sticker(0.026, 0.016), center=(0.032, by - 0.0001, zc - 0.055), normal=(0, -1, 0), mats=["charcoal"], depth=0.004)
    b.decal(asset_tag(0.04, 0.011, "FLEET 07-A", seed=5), center=(0.0, -0.0, zc + H / 2 + 0.0001), normal=(0, 0, 1), up=(0, 1, 0),
            mats=["charcoal"], depth=0.003)
    vent = DecalCanvas(0.05, 0.12, ppm=4000)
    vent.slots(0.008, 0.01, 0.034, 0.10, 9, fill=0.45, depth=0.0008)
    b.decal(vent, center=(-W / 2 - 0.0001, 0, zc), normal=(-1, 0, 0), up=(0, 0, 1), mats=["charcoal"], depth=0.004)

    b.col_box((-0.15, -0.032, 0.0), (0.15, 0.032, 0.20), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.115, -0.014, 0.19), (0.115, 0.006, 0.238), "RUBBER")


# =============================================================================================
# monitor / defibrillator  0.33 (X) x 0.12 (Y) x 0.26 (Z incl. handle)
# =============================================================================================
@prop("nz_amb_defib", atlas=2048, lod=70, hd=12, doc={
    "title": "Monitor / defibrillator (orange + black handle)",
    "origin": "bottom centre",
    "axes": "+Y = screen side (front), +Z up; handle on top, pads pouch on the +X side, printer on the -X side",
    "attach": "carry: PH_R_Hand (28422) pos (0.0, -0.06, -0.26) rot (0, 0, 90); placed next to the patient on the ground",
    "screen": "nz_amb_screen - quad 0.170 x 0.096 m (aspect 1.77), UV 0..1 = visible screen, top-left = (0,0)",
})
def defib(b):
    orange = b.mat("defib_orange", color=(222, 100, 28), spec=0.38, gloss=0.5, bump="stipple", bump_amp=0.00006,
                   bump_scale=0.0009, grain=0.03, grain_scale=0.05, edge=0.6, dirt=0.28, wear_color=(242, 170, 120))
    blk = m_black_plastic(b)
    rub = b.mat("bumper", color=(28, 29, 32), spec=0.12, gloss=0.2, bump="rubber", bump_amp=0.00008, bump_scale=0.0007,
                grain=0.05, grain_scale=0.03, edge=0.3, dirt=0.35, wear_color=(70, 72, 76))
    panel = m_gloss_black(b)
    grip = b.mat("grip", color=(28, 29, 31), spec=0.12, gloss=0.18, bump="ribs", bump_amp=0.00024, bump_scale=0.003, edge=0.3,
                 dirt=0.25)
    teal = b.mat("on_btn", color=(14, 150, 140), spec=0.45, gloss=0.6, edge=0.4)
    charge = b.mat("charge_btn", color=(236, 186, 30), spec=0.45, gloss=0.6, edge=0.4)
    shock = b.mat("shock_btn", color=(214, 52, 40), spec=0.5, gloss=0.65, edge=0.4)
    grey = b.mat("grey_btn", color=(70, 74, 79), spec=0.35, gloss=0.5, edge=0.45)
    pouch = b.mat("pouch", color=(30, 31, 34), spec=0.14, gloss=0.2, bump="cordura", bump_amp=0.00016, bump_scale=0.0011, edge=0.15,
                  color2=(22, 23, 25), dirt=0.3)
    zipm = b.mat("zipper", color=(24, 25, 27), spec=0.3, gloss=0.4, bump="ribs", bump_amp=0.00012, bump_scale=0.0014, edge=0.2)
    paper = b.mat("ecg_paper", color=(242, 236, 228), spec=0.1, gloss=0.2, edge=0.0)
    cable = b.mat("pads_cable", color=(34, 36, 40), spec=0.3, gloss=0.45, edge=0.1, dirt=0.2)
    steel = m_steel(b)

    W, D, H = 0.31, 0.11, 0.205
    zc = 0.004 + H / 2
    # lower black bumper shell (grip ribs) + orange upper housing
    b.add(box((W + 0.012, D + 0.012, 0.03), rub, r=0.012, seg=3, center=(0, 0, 0.015), face_density={"-z": 0.4}))
    b.add(box((W, D, H - 0.02), orange, r=0.016, seg=3, center=(0, 0, zc + 0.008)))
    # rubber corner guards on the upper corners
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(box((0.03, 0.03, 0.05), rub, r=0.011, seg=3, center=(sx * (W / 2 - 0.008), sy * (D / 2 - 0.008), zc + H / 2 - 0.024)))
    fy = D / 2
    # black front fascia
    b.add(box((0.29, 0.006, 0.175), panel, r=0.008, seg=2, center=(0, fy + 0.001, zc + 0.008), faces="+y +x -x +z -z"))
    py = fy + 0.004
    sw, sh = 0.170, 0.096
    scx, scz = 0.042, zc + 0.04
    b.screen(quad((scx, py + 0.0004, scz), (-1, 0, 0), (0, 0, 1), sw, sh, "x", fixed_uv=True),
             image=draw_defib_ui(512, 289), size=(512, 256), mult=1.0)
    _bezel_lip(b, blk, sw + 0.008, sh + 0.008, 0.004, py, scx, scz)
    # soft keys under the screen
    for k in range(4):
        b.add(align(button(grey, 0.022, 0.003, kind="sq").scale(1.0, 0.45, 1.0), (0, 1, 0), (0, 0, 1), (scx + 0.06 - k * 0.04, py, zc - 0.028)))
    # right column (viewer's right = -X): energy knob, CHARGE, SHOCK (guarded)
    cx = -0.098
    b.add(align(_knurled_knob(b, 0.036, 0.016), (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.058)))
    b.add(align(box((0.004, 0.0015, 0.012), b.mat("knob_mark", color=(240, 240, 240), spec=0.4, gloss=0.5), center=(0, 0.0085, 0.0168)),
                (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.058)))
    b.add(align(button(charge, 0.03, 0.006, kind="sq"), (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.008)))
    b.add(align(lathe([(0.0175, 0.0), (0.0195, 0.0), (0.0195, 0.006), (0.0178, 0.0068), (0.0168, 0.004)], blk, segs=40, smooth_angle=50),
                (0, 1, 0), (0, 0, 1), (cx, py, zc - 0.038)))
    b.add(align(button(shock, 0.03, 0.009, kind="round", bevel=0.002, segs=36), (0, 1, 0), (0, 0, 1), (cx, py + 0.001, zc - 0.038)))
    # ON button + LEDs
    b.add(align(button(teal, 0.016, 0.004), (0, 1, 0), (0, 0, 1), (0.12, py, zc - 0.058)))
    b.add(led_lens(b, (0.104, py, zc - 0.058), (0, 1, 0), r=0.0019, color=(70, 255, 140), name="led_green"))
    b.add(led_lens(b, (0.094, py, zc - 0.058), (0, 1, 0), r=0.0019, color=(255, 170, 40), name="led_amber"))
    # therapy cable: right-angle plug in the front socket, strain relief, cable running into the pads pouch
    plug = Geo()
    plug += cylinder(0.0115, 0.006, blk, segs=28, bevel=0.0015, caps=(False, True))
    plug += cylinder(0.0098, 0.012, grip, segs=24, bevel=0.003, caps=(False, True), z0=0.006)
    b.add(align(plug, (0, 1, 0), (0, 0, 1), (-0.02, py, zc - 0.062)))
    b.add(box((0.022, 0.014, 0.016), grip, r=0.005, seg=2, center=(-0.011, py + 0.011, zc - 0.062)))
    b.add(strain_relief(b, (0.0, py + 0.011, zc - 0.062), (1, 0, 0), length=0.02, r0=0.0062, r1=0.0042, rings=5, mat=rub))
    cp = catmull([(0.019, py + 0.011, zc - 0.062), (0.06, py + 0.012, zc - 0.066), (0.12, py + 0.012, zc - 0.07),
                  (0.158, 0.05, zc - 0.064), (0.170, 0.02, zc - 0.055), (0.172, 0.0, zc - 0.05)], n=8)
    b.add(tube(cp, 0.0042, cable, segs=12, tag="padscable"))
    # handle (black, ribbed) on top with screwed posts
    top = zc + H / 2 - 0.002
    path = polyline_fillet([(-0.12, 0.0, top - 0.004), (-0.12, 0.0, top + 0.046), (0.12, 0.0, top + 0.046), (0.12, 0.0, top - 0.004)], 0.024, 8)
    b.add(sweep(rrect(0.03, 0.016, 0.007, 3), path, grip, up=(0, 1, 0), tag="handle", smooth_angle=55))
    for sx in (-1, 1):
        b.add(box((0.05, 0.05, 0.016), blk, r=0.007, seg=2, center=(sx * 0.12, 0, top + 0.004)))
        b.add(screws(b, [(sx * 0.12 + dx, 0.0, top + 0.012) for dx in (-0.016, 0.016)], (0, 0, 1), up=(0, 1, 0), d=0.0045, segs=10))
    # pads pouch on the +X side: zip around the lid, puller, velcro tab, stitching
    px = W / 2 + 0.014
    b.add(box((0.03, 0.09, 0.15), pouch, r=0.012, seg=3, center=(px, 0, zc + 0.002)))
    zl = rrect(0.084, 0.144, 0.010, 5)
    zpath = np.stack([np.full(len(zl), px + 0.0152), zl[:, 0], zc + 0.002 + zl[:, 1]], axis=1)
    b.add(sweep(rrect(0.003, 0.0035, 0.001, 1), zpath, zipm, closed_path=True, side=(0, 1, 0), tag="zip", smooth_angle=60))
    pull = Geo()
    pull += box((0.0016, 0.008, 0.022), steel, r=0.0007, seg=1, center=(0, 0, -0.011))
    pull += box((0.003, 0.010, 0.012), grip, r=0.0012, seg=1, center=(0, 0, -0.026))
    b.add(pull.translate(px + 0.017, 0.042, zc + 0.06))
    b.add(box((0.004, 0.07, 0.03), b.mat("pouch_tab", color=(14, 150, 140), spec=0.16, gloss=0.25, bump="webbing",
                                          bump_amp=0.00014, bump_scale=0.0012, edge=0.15), r=0.0015, seg=1,
              center=(px + 0.016, 0, zc + 0.065)))
    # printer on the -X side with a strip of ECG paper coming out
    b.add(box((0.006, 0.08, 0.03), blk, r=0.003, seg=2, center=(-W / 2 - 0.001, 0, zc + 0.04)))
    b.add(box((0.004, 0.064, 0.002), panel, center=(-W / 2 - 0.0041, 0, zc + 0.04), faces="-x"))
    strip = polyline_fillet([(-W / 2 - 0.002, 0.0, zc + 0.04), (-W / 2 - 0.009, 0.0, zc + 0.04), (-W / 2 - 0.0135, 0.0, zc + 0.032),
                             (-W / 2 - 0.0145, 0.0, zc - 0.005)], 0.005, 6)
    b.add(sweep(rrect(0.0004, 0.05, 0.0, 1), strip, paper, side=(0, 1, 0), up=None, tag="paper", smooth_angle=60))
    # battery pack in the back with a release latch
    by = -D / 2
    b.add(box((0.20, 0.008, 0.07), blk, r=0.006, seg=2, center=(0.0, by - 0.002, zc - 0.03)))
    b.add(box((0.03, 0.006, 0.012), grey, r=0.002, seg=2, center=(0.075, by - 0.006, zc + 0.012)))

    # decals ------------------------------------------------------------------------------
    _parting_lines(b, "defib_orange", W, D, H - 0.02, zc + 0.008, y=-0.012)
    b.decal(label_canvas(0.11, 0.0135, "MONITOR / DEFIBRILLATOR", ppm=7000, color=(220, 224, 226), icon="star",
                         icon_color=(40, 110, 210)), center=(0.078 + 0.005, py + 0.0001, zc + 0.0805), normal=(0, 1, 0), mats=[panel], depth=0.004)
    b.decal(text_canvas([("MD-2", 0.05, 0.007, 0.0048, "label", (220, 224, 226), "rm", 0.0006)], 0.052, 0.014, ppm=7000),
            center=(-0.09, py + 0.0001, zc + 0.0805), normal=(0, 1, 0), mats=[panel], depth=0.004)
    lab = DecalCanvas(0.034, 0.15, ppm=7000)
    for k, (num, word, col) in enumerate((("1", "ENERGY", (230, 232, 234)), ("2", "CHARGE", (236, 186, 30)), ("3", "SHOCK", (230, 70, 60)))):
        y = 0.01 + k * 0.046
        lab.circle(0.017, y, 0.0042, color=col)
        lab.text(0.017, y + 0.0002, num, 0.0042, fnt="label", color=(14, 15, 17))
        lab.text(0.017, y + 0.0095, word, 0.0036, fnt="label", color=col, max_w=0.032)
    b.decal(lab, center=(-0.098 + 0.0405, py + 0.0001, zc + 0.0125), normal=(0, 1, 0), mats=[panel], depth=0.004)
    ring = DecalCanvas(0.06, 0.06, ppm=7000)
    for k, t in enumerate(("2", "5", "10", "50", "100", "150", "200", "360")):
        a = math.radians(225 - k * (270 / 7))
        ring.text(0.03 + math.cos(a) * 0.025, 0.03 - math.sin(a) * 0.025, t, 0.0024, fnt="label-semi", color=(220, 224, 226))
    ring.text(0.03, 0.057, "JOULES", 0.0022, fnt="label", color=(236, 186, 30))
    b.decal(ring, center=(cx, py + 0.0001, zc + 0.058), normal=(0, 1, 0), mats=[panel], depth=0.003)
    sym = DecalCanvas(0.02, 0.02, ppm=9000)
    lightning(sym, 0.01, 0.01, 0.013, color=(255, 240, 230))
    b.decal(sym, center=(cx, py + 0.0111, zc - 0.038), normal=(0, 1, 0), mats=["shock_btn"], depth=0.004)
    ch = DecalCanvas(0.03, 0.03, ppm=9000)
    ch.text(0.015, 0.015, "CHG", 0.0045, fnt="label", color=(30, 26, 14))
    b.decal(ch, center=(cx, py + 0.0061, zc + 0.008), normal=(0, 1, 0), mats=["charge_btn"], depth=0.003)
    on = DecalCanvas(0.03, 0.01, ppm=9000)
    on.text(0.015, 0.005, "ON / OFF", 0.0026, fnt="label", color=(230, 232, 234))
    b.decal(on, center=(0.12, py + 0.0001, zc - 0.045), normal=(0, 1, 0), mats=[panel], depth=0.003)
    sk = DecalCanvas(0.17, 0.008, ppm=8000)
    for k, t in enumerate(("PACER", "SYNC", "ANALYZE", "PRINT")):
        sk.text(0.025 + k * 0.04, 0.004, t, 0.0022, fnt="label-semi", color=(200, 204, 208))
    b.decal(sk, center=(scx, py + 0.0001, zc - 0.041), normal=(0, 1, 0), mats=[panel], depth=0.003)
    spk = DecalCanvas(0.05, 0.016, ppm=9000)
    spk.perforate(0.003, 0.003, 12, 3, 0.0038, 0.0009, depth=0.0005, stagger=True)
    b.decal(spk, center=(0.06, py + 0.0001, zc - 0.064), normal=(0, 1, 0), mats=[panel], depth=0.003)
    side = label_canvas(0.074, 0.02, "DEFIBRILLATOR", "MD-2  ·  BIPHASIC 360 J", ppm=7000, color=(20, 20, 22),
                        sub_color=(20, 20, 22), icon="star", icon_color=(30, 30, 34))
    b.decal(side, center=(-W / 2 - 0.0001, 0.0, zc - 0.035), normal=(-1, 0, 0), up=(0, 0, 1), mats=["defib_orange"], depth=0.004)
    pr = DecalCanvas(0.06, 0.012, ppm=7000)
    pr.text(0.03, 0.006, "PRINTER  ·  50 mm", 0.0028, fnt="label-semi", color=(20, 20, 22))
    b.decal(pr, center=(-W / 2 - 0.0001, 0.0, zc + 0.065), normal=(-1, 0, 0), up=(0, 0, 1), mats=["defib_orange"], depth=0.004)
    pp = DecalCanvas(0.05, 0.02, ppm=7000)
    for k in range(8):
        pp.rect(0.0, k * 0.0025, 0.05, 0.0002, color=(230, 160, 150))
    pts = [(0.002 + i * 0.0005, 0.012 - 0.008 * math.exp(-((i % 18) - 8) ** 2 / 0.6)) for i in range(92)]
    pp.line(pts, 0.0003, color=(40, 40, 44))
    b.chart_decal(pp, "paper:", u0=0.0, v0=0.0, rot=0, mats=["ecg_paper"])
    pz = DecalCanvas(0.13, 0.03, ppm=6000)
    pz.text(0.065, 0.011, "PADS", 0.008, fnt="label", color=(232, 234, 236), spacing=0.0015)
    pz.text(0.065, 0.022, "ADULT / CHILD  ·  CHECK EXPIRY", 0.0028, fnt="label-semi", color=(180, 184, 188))
    b.decal(pz, center=(px + 0.0151, 0.0, zc - 0.02), normal=(1, 0, 0), up=(0, 0, 1), mats=["pouch"], depth=0.004)
    stitch = DecalCanvas(0.10, 0.16, ppm=6000)
    stitch.stitch_rect(0.0, 0.0, 0.10, 0.16, r=0.012, inset=0.005, color=(60, 62, 66))
    b.decal(stitch, center=(px + 0.0151, 0.0, zc + 0.002), normal=(1, 0, 0), up=(0, 0, 1), mats=["pouch"], depth=0.004)
    rear = caution_label(0.08, 0.03, "DANGER", ["HIGH VOLTAGE - stand clear during shock", "No user serviceable parts inside"],
                         kind="danger", symbol="bolt", ppm=6000)
    b.decal(rear, center=(-0.06, -D / 2 - 0.0001, zc + 0.05), normal=(0, -1, 0), mats=["defib_orange"], depth=0.004)
    b.decal(rating_plate(0.064, 0.024, "DEFIBRILLATOR", "MD-2", "SN 26-07310", rating="Li-ion 14.4 V  5.7 Ah  /  DC 18 V"),
            center=(0.07, -D / 2 - 0.0001, zc + 0.05), normal=(0, -1, 0), mats=["defib_orange"], depth=0.004)
    bt = DecalCanvas(0.20, 0.07, ppm=5000)
    bt.text(0.10, 0.02, "Li-ion  14.4 V  ·  RECHARGEABLE", 0.0042, fnt="label", color=(190, 194, 198))
    bt.rect(0.06, 0.033, 0.08, 0.016, r=0.002, fill=False, width=0.0008, color=(190, 194, 198))
    for k in range(4):
        bt.rect(0.0625 + k * 0.0145, 0.0355, 0.012, 0.011, color=(70, 220, 120) if k < 3 else (60, 64, 68))
    bt.groove_rect(0.004, 0.004, 0.192, 0.062, r=0.005)
    b.decal(bt, center=(0.0, -D / 2 - 0.0061, zc - 0.03), normal=(0, -1, 0), mats=[blk], depth=0.004)
    b.decal(cal_sticker(0.026, 0.016, title="TESTED", color=(30, 140, 70)), center=(0.13, -D / 2 - 0.0001, zc + 0.012), normal=(0, -1, 0),
            mats=["defib_orange"], depth=0.004)

    b.col_box((-0.165, -0.061, 0.0), (0.172, 0.061, 0.212), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.14, -0.02, 0.21), (0.14, 0.02, 0.262), "RUBBER")


# =============================================================================================
# EMS pager  0.09 (X) x 0.022 (Y) x 0.06 (Z)
# =============================================================================================
@prop("nz_amb_pager", atlas=1024, lod=40, hd=6, doc={
    "title": "EMS pager",
    "origin": "centre of the body (the grip)",
    "axes": "+Y = LCD side (front), +Z up, belt clip on -Y",
    "attach": "hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (-90, 0, 0) -> adjust per animation; "
              "belt: SKEL_Pelvis (11816) pos (0.0, 0.14, 0.1) rot (0, 0, 180)",
    "screen": "nz_amb_screen - LCD quad 0.056 x 0.022 m (aspect 2.55), UV 0..1 = LCD, top-left = (0,0)",
})
def pager(b):
    body = b.mat("pager_body", color=(38, 40, 44), spec=0.32, gloss=0.46, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0005, grain=0.03, grain_scale=0.02, edge=0.7, dirt=0.25, wear_color=(96, 100, 106))
    rub = b.mat("pager_rubber", color=(24, 25, 27), spec=0.12, gloss=0.2, bump="ribs", bump_amp=0.00014, bump_scale=0.0012,
                edge=0.3, dirt=0.25)
    panel = m_gloss_black(b)
    teal = b.mat("read_btn", color=(14, 150, 140), spec=0.45, gloss=0.6, edge=0.45)
    grey = b.mat("grey_btn", color=(80, 84, 89), spec=0.35, gloss=0.5, edge=0.5)
    steel = b.mat("clip_steel", color=(150, 154, 160), spec=0.8, gloss=0.62, metal=1.0, bump="brushed", bump_amp=0.000008,
                  bump_scale=0.0004, edge=0.4, dirt=0.2)

    W, D, H = 0.09, 0.022, 0.06
    b.add(box((W, D, H), body, r=0.007, seg=3))
    # rubber side grips (ribbed) + side volume buttons
    for sx in (-1, 1):
        b.add(box((0.006, 0.018, 0.04), rub, r=0.0025, seg=2, center=(sx * (W / 2 + 0.0005), 0, -0.002)))
    b.add(box((0.004, 0.008, 0.012), grey, r=0.0015, seg=2, center=(W / 2 + 0.003, 0, 0.022)))
    fy = D / 2
    b.add(box((0.068, 0.002, 0.03), panel, r=0.003, seg=2, center=(0.0, fy + 0.0005, 0.011), faces="+y +x -x +z -z"))
    b.screen(quad((0.0, fy + 0.0017, 0.011), (-1, 0, 0), (0, 0, 1), 0.056, 0.022, "x", fixed_uv=True),
             image=draw_pager_lcd(326, 128), size=(256, 128), mult=0.8)
    # 3 buttons under the LCD
    for k, (m, x) in enumerate(((grey, 0.022), (teal, 0.0), (grey, -0.022))):
        b.add(align(button(m, 0.011, 0.0025, kind="round", bevel=0.0008, segs=24), (0, 1, 0), (0, 0, 1), (x, fy, -0.016)))
    # alert LED on top in a bezel
    b.add(led_lens(b, (0.03, 0.0, H / 2), (0, 0, 1), up=(0, 1, 0), r=0.0022, color=(255, 60, 50), name="led_red"))
    # belt clip: spring steel leaf on a pivot block with a ribbed thumb press
    clip = polyline_fillet([(0, -fy - 0.001, 0.016), (0, -fy - 0.0055, 0.0185), (0, -fy - 0.0055, -0.024), (0, -fy - 0.0045, -0.027)], 0.003, 5)
    b.add(sweep(rrect(0.03, 0.0015, 0.0006, 2), clip, steel, side=(1, 0, 0), tag="clip"))
    b.add(box((0.032, 0.004, 0.012), body, r=0.0015, seg=1, center=(0, -fy - 0.001, 0.019)))
    b.add(cylinder(0.0016, 0.034, steel, segs=10, z0=-0.017).rotate(0, 90, 0).translate(0, -fy - 0.003, 0.021))
    b.add(box((0.02, 0.003, 0.006), rub, r=0.001, seg=1, center=(0, -fy - 0.0068, 0.016)))
    # back screws
    b.add(screws(b, [(sx * 0.038, -fy, sz * 0.023) for sx in (-1, 1) for sz in (-1, 1)], (0, -1, 0), d=0.0032, segs=10))
    # decals
    lab = DecalCanvas(0.07, 0.008, ppm=12000)
    lab.text(0.0, 0.004, "PG-7", 0.0024, fnt="label", anchor="lm", color=(220, 224, 226), spacing=0.0004)
    lab.text(0.063, 0.004, "EMS ALERT", 0.0022, fnt="label", anchor="rm", color=(40, 200, 186), spacing=0.0003)
    b.decal(lab, center=(0.0, fy + 0.0001, 0.0228), normal=(0, 1, 0), mats=["pager_body", "gloss_black"], depth=0.003)
    leg = DecalCanvas(0.07, 0.006, ppm=12000)
    for x, t in ((0.013, "MENU"), (0.035, "READ"), (0.057, "BACK")):
        leg.text(x, 0.003, t, 0.0016, fnt="label-semi", color=(200, 204, 208))
    b.decal(leg, center=(0.0, fy + 0.0001, -0.0255), normal=(0, 1, 0), mats=["pager_body"], depth=0.003)
    spk = DecalCanvas(0.03, 0.01, ppm=12000)
    spk.slots(0.0, 0.0, 0.03, 0.01, 7, vertical=True, fill=0.4, depth=0.0004)
    b.decal(spk, center=(-0.026, fy + 0.0001, 0.0228), normal=(0, 1, 0), mats=["pager_body"], depth=0.003)
    back = DecalCanvas(0.09, 0.06, ppm=8000)
    back.groove_rect(0.01, 0.033, 0.07, 0.022, r=0.003, width=0.0004, depth=0.00018)
    back.text(0.045, 0.040, "1.5 V  AA", 0.0026, fnt="label-semi", color=(150, 155, 160))
    back.text(0.045, 0.047, "OPEN  >>", 0.0022, fnt="label-semi", color=(150, 155, 160))
    b.decal(back, center=(0.0, -fy - 0.0001, 0.0), normal=(0, -1, 0), mats=["pager_body"], depth=0.003)
    b.decal(rating_plate(0.032, 0.012, "PAGER", "PG-7", "SN 7741", rating="1.5 V  AA", ppm=16000, icons=("factory", "book", "bin")),
            center=(0.024, -fy - 0.0001, -0.019), normal=(0, -1, 0), mats=["pager_body"], depth=0.003)
    _parting_lines(b, "pager_body", W, D, H, 0.0, y=-0.002, width=0.0003, depth=0.00012)
    b.col_box((-0.046, -0.019, -0.03), (0.046, 0.0125, 0.031), "PLASTIC")
