"""
Electronic devices: portable patient monitor, monitor/defibrillator, EMS pager.
All three carry an emissive screen whose texture is named 'nz_amb_screen' (replace it at runtime
with a DUI: AddReplaceTexture('<model name>', 'nz_amb_screen', duiTxd, duiTex)).
"""
from __future__ import annotations

import numpy as np

from nzprops import (TEAL_HI, DecalCanvas, box, cylinder, draw_defib_ui, draw_monitor_ui, draw_pager_lcd,
                     polyline_fillet, prop, quad, rrect, sweep, tube, vec)

from .common import (align, brand_canvas, button, knob, lightning, m_alu, m_black_plastic, m_charcoal, m_gloss_black,
                     m_grip, m_led, m_rubber, m_steel, m_teal, screw_head, serial_label, text_canvas)


def _bezel_lip(b, mat, w, h, r, at_y, cx, cz, prof_w=0.0035, prof_h=0.0018):
    """Thin raised lip around a screen opening (rounded rectangle path in the XZ plane)."""
    loop = rrect(w, h, r, 4)
    path = np.stack([cx + loop[:, 0], np.full(len(loop), at_y), cz + loop[:, 1]], axis=1)
    prof = rrect(prof_w, prof_h, prof_h * 0.45, 2) + vec(0, prof_h / 2)
    return b.add(sweep(prof, path, mat, closed_path=True, up=(0, 1, 0), smooth_angle=50, tag="lip"))


# =============================================================================================
# portable patient monitor  0.30 (X) x 0.064 (Y) x 0.235 (Z incl. handle)
# =============================================================================================
@prop("nz_amb_monitor", atlas=1024, lod=70, hd=12, doc={
    "title": "Portable patient monitor",
    "origin": "bottom centre (sits on surfaces)",
    "axes": "+Y = screen side (front), +Z up, +X = right (button column side)",
    "attach": "carry: PH_R_Hand (28422) pos (0.0, -0.03, -0.24) rot (0, 0, 90) holding the top handle; "
              "on stretcher/bed: place on the mattress or attach to the stretcher entity at its foot end",
    "screen": "nz_amb_screen - quad 0.180 x 0.112 m (aspect 1.61), UV 0..1 = full visible screen, top-left = (0,0)",
})
def monitor(b):
    body = m_charcoal(b)
    rub = m_rubber(b)
    panel = m_gloss_black(b)
    teal = m_teal(b)
    blk = m_black_plastic(b)
    grip = m_grip(b)
    alu = m_alu(b)
    red_btn = b.mat("red_btn", color=(196, 44, 48), spec=0.45, gloss=0.6, edge=0.4)
    grey_btn = b.mat("grey_btn", color=(70, 74, 79), spec=0.35, gloss=0.5, edge=0.4)
    lamp = b.mat("alarm_lamp", color=(120, 22, 24), spec=0.8, gloss=0.85)
    led = m_led(b, "led_green", (70, 255, 140))

    W, D, H = 0.29, 0.05, 0.19
    zc = 0.10
    b.add(box((W, D, H), body, r=0.012, seg=3, center=(0, 0, zc), face_density={"-z": 0.4}))
    # rubber corner bumpers
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.add(box((0.042, 0.064, 0.042), rub, r=0.013, seg=3, center=(sx * 0.129, 0, zc + sz * 0.079)))
    # front panel
    fy = D / 2
    b.add(box((0.236, 0.004, 0.17), panel, r=0.006, seg=2, center=(-0.003, fy + 0.001, zc), faces="+y +x -x +z -z"))
    py = fy + 0.003
    sw, sh = 0.180, 0.112
    scx, scz = -0.024, zc + 0.008
    b.screen(quad((scx, py + 0.0004, scz), (-1, 0, 0), (0, 0, 1), sw, sh, "x", fixed_uv=True),
             image=draw_monitor_ui(512, 319), size=(512, 256), mult=1.0)
    _bezel_lip(b, blk, sw + 0.008, sh + 0.008, 0.004, py, scx, scz)
    # button column (right side of the panel = -X side seen from the front? no: +X is right when
    # looking at the front from +Y the viewer's right is -X) -> put the column at -X
    bx = -0.098
    for k, (m, kind) in enumerate(((red_btn, "sq"), (teal, "sq"), (grey_btn, "sq"), (grey_btn, "sq"))):
        z = zc + 0.058 - k * 0.027
        b.add(align(button(m, 0.016, 0.0035, kind="sq"), (0, 1, 0), (0, 0, 1), (bx, py, z)))
    b.add(align(knob(blk, 0.026, 0.012), (0, 1, 0), (0, 0, 1), (bx, py, zc - 0.058)))
    b.add(align(cylinder(0.0145, 0.0015, teal, segs=36, caps=(False, True)), (0, 1, 0), (0, 0, 1), (bx, py, zc - 0.058)))
    # power button + LED (bottom left of the panel, viewer's left = +X)
    b.add(align(button(grey_btn, 0.011, 0.003), (0, 1, 0), (0, 0, 1), (0.096, py, zc - 0.071)))
    b.add(align(cylinder(0.0022, 0.0012, led, segs=12, caps=(False, True)), (0, 1, 0), (0, 0, 1), (0.081, py, zc - 0.071)))
    # alarm lamp on top
    b.add(box((0.07, 0.016, 0.008), lamp, r=0.004, seg=2, center=(0, 0.006, zc + H / 2 + 0.002)))
    # top carry handle
    hz = zc + H / 2
    path = polyline_fillet([(-0.105, -0.004, hz - 0.004), (-0.105, -0.004, hz + 0.034), (0.105, -0.004, hz + 0.034), (0.105, -0.004, hz - 0.004)], 0.018, 6)
    b.add(tube(path, 0.0085, grip, segs=14, tag="handle"))
    for sx in (-1, 1):
        b.add(box((0.03, 0.03, 0.012), body, r=0.005, seg=2, center=(sx * 0.105, -0.004, hz + 0.004)))
    # left side (+X) connector panel
    sx = W / 2
    b.add(box((0.004, 0.036, 0.14), blk, r=0.003, seg=2, center=(sx + 0.001, 0, zc), faces="+x +y -y +z -z"))
    cols = [(60, 200, 110), (40, 120, 220), (220, 222, 224), (230, 190, 40)]
    for k, c in enumerate(cols):
        z = zc + 0.05 - k * 0.033
        ring = b.mat(f"port_ring{k}", color=c, spec=0.4, gloss=0.55, edge=0.3)
        b.add(align(cylinder(0.0075, 0.004, ring, segs=20, bevel=0.0008, caps=(False, True)), (1, 0, 0), (0, 0, 1), (sx + 0.003, 0, z)))
        b.add(align(cylinder(0.0042, 0.0045, panel, segs=16, caps=(False, True)), (1, 0, 0), (0, 0, 1), (sx + 0.003, 0, z)))
    # back hanging bracket
    by = -D / 2
    b.add(box((0.12, 0.006, 0.07), alu, r=0.003, seg=2, center=(0, by - 0.003, zc + 0.035)))
    hook = polyline_fillet([(-0.04, by - 0.006, zc + 0.07), (-0.04, by - 0.024, zc + 0.07), (-0.04, by - 0.024, zc + 0.05)], 0.008, 5)
    for hx in (-0.04, 0.04):
        p = hook.copy()
        p[:, 0] = hx
        b.add(sweep(rrect(0.014, 0.003, 0.001, 2), p, alu, side=(1, 0, 0), tag="hook"))
    for hx in (-0.05, 0.05):
        for hz2 in (zc + 0.008, zc + 0.062):
            b.add(align(screw_head(m_steel(b)), (0, -1, 0), (0, 0, 1), (hx, by - 0.006, hz2)))
    # feet
    for fx in (-0.1, 0.1):
        for fyy in (-0.012, 0.012):
            b.add(cylinder(0.006, 0.003, rub, segs=12, bevel=0.001).translate(fx, fyy, -0.0005))

    # decals ------------------------------------------------------------------------------
    b.decal(brand_canvas(0.085, 0.0135, ppm=5000), center=(0.044, py + 0.0001, zc + 0.0755), normal=(0, 1, 0), mats=[panel], depth=0.004)
    b.decal(text_canvas([("VITALS 8", 0.044, 0.006, 0.0042, "brand-semi", (200, 204, 208), "rm", 0.0006)], 0.046, 0.012, ppm=6000),
            center=(-0.07, py + 0.0001, zc + 0.0755), normal=(0, 1, 0), mats=[panel], depth=0.004)
    # button legends (icons as text glyphs)
    legends = DecalCanvas(0.03, 0.12, ppm=6000)
    for k, t in enumerate(("ALARM", "NIBP", "MENU", "HOME")):
        legends.text(0.015, 0.0055 + k * 0.027, t, 0.0026, fnt="brand-semi", color=(210, 214, 216), max_w=0.026)
    b.decal(legends, center=(-0.098, py + 0.0001, zc + 0.0115), normal=(0, 1, 0), mats=[panel], depth=0.003)
    side = DecalCanvas(0.03, 0.14, ppm=5000)
    for k, t in enumerate(("ECG", "SpO2", "NIBP", "TEMP")):
        side.text(0.015, 0.012 + k * 0.033 - 0.002, t, 0.0028, fnt="brand-semi", color=(205, 208, 210))
    b.decal(side, center=(sx + 0.003, 0.0, zc + 0.002), normal=(1, 0, 0), up=(0, 0, 1), mats=[blk], depth=0.003)
    b.decal(serial_label(0.06, 0.022, "VITALS 8  NZ-MON", "SN 2026-1180"), center=(0, -D / 2 - 0.0001, zc - 0.055), normal=(0, -1, 0), mats=[body], depth=0.004)
    vent = DecalCanvas(0.05, 0.12, ppm=3000)
    for k in range(9):
        vent.rect(0.008, 0.01 + k * 0.012, 0.034, 0.005, r=0.0025, color=(18, 19, 21), height=-0.0008)
    b.decal(vent, center=(-W / 2 - 0.0001, 0, zc), normal=(-1, 0, 0), up=(0, 0, 1), mats=[body], depth=0.004)

    b.col_box((-0.15, -0.032, 0.0), (0.15, 0.032, 0.20), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.115, -0.014, 0.19), (0.115, 0.006, 0.238), "RUBBER")


# =============================================================================================
# monitor / defibrillator  0.33 (X) x 0.12 (Y) x 0.26 (Z incl. handle)
# =============================================================================================
@prop("nz_amb_defib", atlas=1024, lod=70, hd=12, doc={
    "title": "Monitor / defibrillator (orange + black handle)",
    "origin": "bottom centre",
    "axes": "+Y = screen side (front), +Z up; handle on top, pads pouch on the -X side",
    "attach": "carry: PH_R_Hand (28422) pos (0.0, -0.06, -0.26) rot (0, 0, 90); placed next to the patient on the ground",
    "screen": "nz_amb_screen - quad 0.170 x 0.096 m (aspect 1.77), UV 0..1 = visible screen, top-left = (0,0)",
})
def defib(b):
    orange = b.mat("defib_orange", color=(222, 100, 28), spec=0.38, gloss=0.5, bump="stipple", bump_amp=0.00006,
                   bump_scale=0.0009, grain=0.03, grain_scale=0.05, edge=0.55, dirt=0.18)
    blk = m_black_plastic(b)
    rub = m_rubber(b)
    panel = m_gloss_black(b)
    grip = m_grip(b)
    teal = m_teal(b)
    charge = b.mat("charge_btn", color=(236, 186, 30), spec=0.45, gloss=0.6, edge=0.4)
    shock = b.mat("shock_btn", color=(214, 52, 40), spec=0.5, gloss=0.65, edge=0.4)
    grey = b.mat("grey_btn", color=(70, 74, 79), spec=0.35, gloss=0.5, edge=0.4)
    pouch = b.mat("pouch", color=(30, 31, 34), spec=0.14, gloss=0.2, bump="fabric", bump_amp=0.00018, bump_scale=0.0016, edge=0.1, color2=(22, 23, 25))
    led = m_led(b, "led_green", (70, 255, 140))

    W, D, H = 0.31, 0.11, 0.205
    zc = 0.004 + H / 2
    # lower black bumper shell + orange upper housing
    b.add(box((W + 0.012, D + 0.012, 0.03), rub, r=0.012, seg=3, center=(0, 0, 0.015), face_density={"-z": 0.4}))
    b.add(box((W, D, H - 0.02), orange, r=0.016, seg=3, center=(0, 0, zc + 0.008)))
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
    # right column (viewer's right = -X): energy knob, CHARGE, SHOCK
    cx = -0.098
    b.add(align(knob(blk, 0.036, 0.016), (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.058)))
    b.add(align(cylinder(0.0195, 0.0015, teal, segs=40, caps=(False, True)), (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.058)))
    b.add(align(button(charge, 0.03, 0.006, kind="sq"), (0, 1, 0), (0, 0, 1), (cx, py, zc + 0.008)))
    b.add(align(cylinder(0.0175, 0.003, blk, segs=32, caps=(False, True)), (0, 1, 0), (0, 0, 1), (cx, py, zc - 0.038)))
    b.add(align(button(shock, 0.03, 0.009, kind="round", bevel=0.002, segs=32), (0, 1, 0), (0, 0, 1), (cx, py + 0.003, zc - 0.038)))
    # ON button + LED
    b.add(align(button(teal, 0.016, 0.004), (0, 1, 0), (0, 0, 1), (0.12, py, zc - 0.058)))
    b.add(align(cylinder(0.0022, 0.0012, led, segs=12, caps=(False, True)), (0, 1, 0), (0, 0, 1), (0.105, py, zc - 0.058)))
    # pads connector at the bottom front
    b.add(align(cylinder(0.011, 0.01, blk, segs=24, bevel=0.002, caps=(False, True)), (0, 1, 0), (0, 0, 1), (-0.02, py, zc - 0.062)))
    b.add(align(cylinder(0.0065, 0.0105, panel, segs=16, caps=(False, True)), (0, 1, 0), (0, 0, 1), (-0.02, py, zc - 0.062)))
    # handle (black) on top
    top = zc + H / 2 - 0.002
    path = polyline_fillet([(-0.12, 0.0, top - 0.004), (-0.12, 0.0, top + 0.046), (0.12, 0.0, top + 0.046), (0.12, 0.0, top - 0.004)], 0.024, 6)
    b.add(sweep(rrect(0.03, 0.016, 0.007, 3), path, grip, up=(0, 1, 0), tag="handle", smooth_angle=55))
    for sx in (-1, 1):
        b.add(box((0.05, 0.05, 0.016), blk, r=0.007, seg=2, center=(sx * 0.12, 0, top + 0.004)))
    # pads pouch on the +X side
    b.add(box((0.03, 0.09, 0.15), pouch, r=0.012, seg=3, center=(W / 2 + 0.014, 0, zc + 0.002)))
    b.add(box((0.004, 0.07, 0.03), teal, r=0.0015, seg=1, center=(W / 2 + 0.03, 0, zc + 0.065)))
    # printer slot on -X side
    b.add(box((0.006, 0.08, 0.03), blk, r=0.003, seg=2, center=(-W / 2 - 0.001, 0, zc + 0.04)))

    # decals ------------------------------------------------------------------------------
    b.decal(brand_canvas(0.09, 0.014, ppm=5000), center=(0.078, py + 0.0001, zc + 0.0805), normal=(0, 1, 0), mats=[panel], depth=0.004)
    b.decal(text_canvas([("DEFIB X1", 0.05, 0.007, 0.0048, "brand", (220, 224, 226), "rm", 0.0006)], 0.052, 0.014, ppm=6000),
            center=(-0.09, py + 0.0001, zc + 0.0805), normal=(0, 1, 0), mats=[panel], depth=0.004)
    lab = DecalCanvas(0.034, 0.15, ppm=6000)
    for k, (num, word, col) in enumerate((("1", "ENERGY", (230, 232, 234)), ("2", "CHARGE", (236, 186, 30)), ("3", "SHOCK", (230, 70, 60)))):
        y = 0.01 + k * 0.046
        lab.circle(0.017, y, 0.0042, color=col)
        lab.text(0.017, y + 0.0002, num, 0.0042, fnt="brand", color=(14, 15, 17))
        lab.text(0.017, y + 0.0095, word, 0.0036, fnt="brand", color=col, max_w=0.032)
    b.decal(lab, center=(-0.098 + 0.0405, py + 0.0001, zc + 0.0125), normal=(0, 1, 0), mats=[panel], depth=0.004)
    sym = DecalCanvas(0.02, 0.02, ppm=8000)
    lightning(sym, 0.01, 0.01, 0.013, color=(255, 240, 230))
    b.decal(sym, center=(cx, py + 0.0121, zc - 0.038), normal=(0, 1, 0), mats=[shock], depth=0.004)
    on = DecalCanvas(0.03, 0.01, ppm=8000)
    on.text(0.015, 0.005, "ON", 0.0032, fnt="brand", color=(230, 232, 234))
    b.decal(on, center=(0.12, py + 0.0001, zc - 0.044), normal=(0, 1, 0), mats=[panel], depth=0.003)
    side = DecalCanvas(0.07, 0.05, ppm=3000)
    side.lockup(0.0, 0.002, 0.016, color=(20, 20, 22), sub_color=(20, 20, 22))
    side.text(0.0, 0.032, "MONITOR / DEFIBRILLATOR", 0.0048, fnt="brand-semi", anchor="lm", color=(20, 20, 22), spacing=0.0005, max_w=0.068)
    b.decal(side, center=(-W / 2 - 0.0001, 0.0, zc - 0.035), normal=(-1, 0, 0), up=(0, 0, 1), mats=[orange], depth=0.004)
    warn = DecalCanvas(0.07, 0.02, ppm=5000)
    warn.rect(0, 0, 0.07, 0.02, r=0.002, color=(236, 186, 30))
    warn.text(0.035, 0.0065, "DANGER  HIGH VOLTAGE", 0.0034, fnt="brand", color=(14, 15, 17))
    warn.text(0.035, 0.0145, "keep clear during shock", 0.0026, fnt="brand-semi", color=(14, 15, 17))
    b.decal(warn, center=(0.0, -D / 2 - 0.0001, zc + 0.04), normal=(0, -1, 0), mats=[orange], depth=0.004)
    b.decal(serial_label(0.06, 0.022, "DEFIB X1  NZ-DFB", "SN 2026-0731"), center=(0.0, -D / 2 - 0.0001, zc - 0.035), normal=(0, -1, 0), mats=[orange], depth=0.004)

    b.col_box((-0.165, -0.061, 0.0), (0.172, 0.061, 0.212), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.14, -0.02, 0.21), (0.14, 0.02, 0.262), "RUBBER")


# =============================================================================================
# EMS pager  0.09 (X) x 0.022 (Y) x 0.06 (Z)
# =============================================================================================
@prop("nz_amb_pager", atlas=512, lod=40, hd=6, doc={
    "title": "EMS pager",
    "origin": "centre of the body (the grip)",
    "axes": "+Y = LCD side (front), +Z up, belt clip on -Y",
    "attach": "hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (-90, 0, 0) -> adjust per animation; "
              "belt: SKEL_Pelvis (11816) pos (0.0, 0.14, 0.1) rot (0, 0, 180)",
    "screen": "nz_amb_screen - LCD quad 0.056 x 0.022 m (aspect 2.55), UV 0..1 = LCD, top-left = (0,0)",
})
def pager(b):
    body = b.mat("pager_body", color=(36, 38, 42), spec=0.32, gloss=0.46, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0005, grain=0.03, grain_scale=0.02, edge=0.65)
    rub = m_rubber(b)
    panel = m_gloss_black(b)
    teal = m_teal(b)
    grey = b.mat("grey_btn", color=(80, 84, 89), spec=0.35, gloss=0.5, edge=0.5)
    steel = m_steel(b)
    led = m_led(b, "led_red", (255, 60, 50))

    W, D, H = 0.09, 0.022, 0.06
    b.add(box((W, D, H), body, r=0.007, seg=3))
    # rubber side grips
    for sx in (-1, 1):
        b.add(box((0.006, 0.018, 0.04), rub, r=0.0025, seg=2, center=(sx * (W / 2 + 0.0005), 0, -0.002)))
    fy = D / 2
    b.add(box((0.068, 0.002, 0.03), panel, r=0.003, seg=2, center=(0.0, fy + 0.0005, 0.011), faces="+y +x -x +z -z"))
    b.screen(quad((0.0, fy + 0.0017, 0.011), (-1, 0, 0), (0, 0, 1), 0.056, 0.022, "x", fixed_uv=True),
             image=draw_pager_lcd(326, 128), size=(256, 128), mult=0.8)
    # 3 buttons under the LCD
    for k, (m, x) in enumerate(((grey, 0.022), (teal, 0.0), (grey, -0.022))):
        b.add(align(button(m, 0.011, 0.0025, kind="round", bevel=0.0008), (0, 1, 0), (0, 0, 1), (x, fy, -0.016)))
    # LED on top
    b.add(cylinder(0.0022, 0.0015, led, segs=12).translate(0.03, 0.0, H / 2 - 0.0005))
    # belt clip
    clip = polyline_fillet([(0, -fy - 0.001, 0.016), (0, -fy - 0.0055, 0.0185), (0, -fy - 0.0055, -0.024)], 0.003, 4)
    b.add(sweep(rrect(0.03, 0.0015, 0.0006, 2), clip, steel, side=(1, 0, 0), tag="clip"))
    b.add(box((0.032, 0.004, 0.012), body, r=0.0015, seg=1, center=(0, -fy - 0.001, 0.019)))
    # decals
    lab = DecalCanvas(0.07, 0.008, ppm=9000)
    lab.mark(0.0, 0.001, 0.006)
    lab.text(0.009, 0.004, "NAYZEEE", 0.0024, fnt="brand", anchor="lm", color=(220, 224, 226), spacing=0.0004)
    lab.text(0.063, 0.004, "EMS", 0.0024, fnt="brand", anchor="rm", color=TEAL_HI)
    b.decal(lab, center=(0.0, fy + 0.0001, 0.0228), normal=(0, 1, 0), mats=[body, panel], depth=0.003)
    b.decal(serial_label(0.04, 0.016, "NZ-PGR", "SN 7741"), center=(0.0, -fy - 0.0001, -0.012), normal=(0, -1, 0), mats=[body], depth=0.003)

    b.col_box((-0.046, -0.019, -0.03), (0.046, 0.0125, 0.031), "PLASTIC")


