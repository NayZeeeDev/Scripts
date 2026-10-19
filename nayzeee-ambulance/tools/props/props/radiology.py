"""
Imaging / interventional suite equipment: radiography table with floor-rail tube stand, film
lightbox, contrast power injector on a mobile tray, contrast-run pedestal button and the boom
fluoroscopy monitor. Hospital furniture: origin on the floor, +Y = the side the operator faces.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (AMBER, TEAL, TEAL_HI, DecalCanvas, box, catmull, cylinder, lathe, polyline_fillet, prop, quad, torus,
                     tube)

from .common import (align, button, cal_sticker, caution_label, knob, label_canvas, m_alu, m_black_plastic,
                     m_chrome, m_gloss_black, m_led, m_rubber, m_teal, rating_plate, screws, text_canvas)
from .parts import (boost, caster, caster_top, collar, m_hosp_dark, m_hosp_grey, m_hosp_white, m_stainless, m_teal_led, m_vinyl,
                    pole, radiation_label, ruler, star_base, vents)
from .screens import draw_angio_ui, draw_lightbox_panel

# =============================================================================================
# X-ray table (with the floor rail) + the tube stand that slides along it
# =============================================================================================
XR_TOP = 0.825          # patient surface (top of the pad)
XR_COL = (-0.68, 0.35)  # tube stand column (x, y)
XR_TUBE = (0.0, 0.35)   # focal spot (x, y) over the table
XR_COLLIMATOR_Z = 1.42  # bottom of the collimator


XR_ARM = XR_TUBE[0] - XR_COL[0]   # focal spot ahead of the column, across the table (+X)


@prop("nz_amb_xray_table", atlas=2048, lod=120, hd=18, static=True, falloff=70, doc={
    "title": "Radiography table with the floor rail for the X-ray tube stand",
    "origin": "floor, under the centre of the table top",
    "axes": "table length along Y (patient head end +Y), operator side +X; the floor rail for the tube stand "
            f"(nz_amb_xray_tube) runs along Y at x = {XR_COL[0]}",
    "attach": f"patient lies on the pad (surface z = {XR_TOP}); the tube stand stands on the rail: place nz_amb_xray_tube "
              f"at table offset ({XR_COL[0]}, y, 0) with the table's heading, y = -1.0 .. 1.0 (its focal spot is then over "
              f"(0, y) of the table); rest position y = {XR_COL[1]}; medic stands at (+0.75, 0.0) facing -X",
})
def xray_table(b):
    white = m_hosp_white(b)
    grey = m_hosp_grey(b)
    dark = m_hosp_dark(b)
    alu = m_alu(b)
    chrome = m_chrome(b)
    blk = m_black_plastic(b)
    led = m_teal_led(b)
    teal = m_teal(b)
    pad = m_vinyl(b, "pad_vinyl", (34, 96, 120))
    carbon = b.mat("carbon", color=(58, 61, 66), spec=0.45, gloss=0.6, bump="fabric", bump_amp=0.00006, bump_scale=0.0022,
                   grain=0.02, grain_scale=0.05, edge=0.35, color2=(44, 47, 52))

    # ---- table pedestal ----------------------------------------------------------------------
    b.add(box((0.64, 1.02, 0.05), dark, r=0.02, seg=2, center=(0, -0.05, 0.025), face_density={"-z": 0.2}))
    b.add(box((0.61, 0.99, 0.01), led, center=(0, -0.05, 0.055), faces="+x -x +y -y"))
    b.add(box((0.52, 0.84, 0.56), white, r=0.06, seg=3, center=(0, -0.05, 0.06 + 0.28), face_density={"-z": 0.2}))
    b.add(box((0.40, 0.62, 0.10), dark, r=0.02, seg=2, center=(0, -0.05, 0.665)))
    for z in (0.632, 0.66, 0.688):      # bellows ribs on the lift neck
        b.add(box((0.412, 0.632, 0.008), grey, r=0.003, seg=1, center=(0, -0.05, z)))
    b.add(box((0.58, 1.46, 0.04), alu, r=0.012, seg=2, center=(0, 0.0, 0.73)))
    # ---- table top + pad ---------------------------------------------------------------------
    b.add(box((0.75, 2.2, 0.045), carbon, r=0.018, seg=3, center=(0, 0, 0.7725)))
    b.add(box((0.62, 2.02, 0.032), pad, r=0.014, seg=3, center=(0, 0, XR_TOP - 0.016)))
    # side rails with stand-offs
    for sx in (-1, 1):
        x = sx * 0.39
        b.add(box((0.012, 2.0, 0.03), alu, r=0.004, seg=2, center=(x, 0, 0.77)))
        for y in (-0.95, -0.3, 0.3, 0.95):
            b.add(box((0.02, 0.03, 0.02), dark, r=0.004, seg=1, center=(x - sx * 0.008, y, 0.77)))
    # bucky tray drawer front (+X side, under the chest area) with handle
    b.add(box((0.03, 0.50, 0.035), dark, r=0.006, seg=2, center=(0.36, XR_TUBE[1], 0.712)))
    hp = polyline_fillet([(0.375, XR_TUBE[1] - 0.12, 0.712), (0.40, XR_TUBE[1] - 0.12, 0.712), (0.40, XR_TUBE[1] + 0.12, 0.712),
                          (0.375, XR_TUBE[1] + 0.12, 0.712)], 0.01, 4)
    b.add(tube(hp, 0.006, chrome, segs=10))
    # hand control pendant hanging at the foot end
    b.add(box((0.07, 0.032, 0.13), white, r=0.012, seg=2, center=(0.42, -0.86, 0.60)))
    b.add(box((0.05, 0.006, 0.09), dark, r=0.004, seg=1, center=(0.42, -0.843, 0.605), faces="-y +x -x +z -z"))
    for k, m in enumerate((teal, grey, grey)):
        b.add(align(button(m, 0.012, 0.003), (0, -1, 0), (0, 0, 1), (0.42, -0.877, 0.635 - k * 0.025)))
    cab = catmull([(0.42, -0.86, 0.665), (0.42, -0.86, 0.70), (0.40, -0.84, 0.735), (0.375, -0.80, 0.745)], n=6)
    b.add(tube(cab, 0.004, blk, segs=8))

    # ---- floor rail (the tube stand nz_amb_xray_tube rides on it) ------------------------------
    cx = XR_COL[0]
    b.add(box((0.16, 2.30, 0.03), alu, r=0.008, seg=2, center=(cx, 0, 0.015), face_density={"-z": 0.1}))
    b.add(box((0.05, 2.28, 0.006), dark, center=(cx, 0, 0.031), faces="+z +x -x"))
    for sy in (-1, 1):
        b.add(box((0.17, 0.04, 0.045), blk, r=0.01, seg=2, center=(cx, sy * 1.15, 0.0225)))

    # ---- decals -------------------------------------------------------------------------------
    lab = label_canvas(0.30, 0.05, "RADIOGRAPHY TABLE", "RT-4  ·  FLOATING TOP", ppm=2200, color=(40, 44, 48), sub_color=TEAL)
    b.decal(lab, center=(0.0, -0.05 + 0.4201, 0.50), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.02)
    b.decal(lab, center=(0.2601, -0.05, 0.50), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.02)
    for sx in (-1, 1):
        r = ruler(1.9, 0.026, step=0.01, ppm=1400, numbers=10, start=0, unit_step=10, bg=(186, 190, 194))
        b.decal(r, center=(sx * 0.3961, 0.0, 0.77), normal=(sx, 0, 0), up=(0, 0, 1), mats=["alu"], depth=0.006)
    rr = ruler(2.2, 0.04, step=0.05, ppm=900, numbers=2, start=0, unit_step=10)
    b.decal(rr, center=(cx + 0.055, 0.0, 0.0301), normal=(0, 0, 1), up=(1, 0, 0), mats=["alu"], depth=0.004)
    pend = DecalCanvas(0.05, 0.03, ppm=6000)
    pend.text(0.003, 0.0065, "TABLE", 0.0045, fnt="label", anchor="lm", color=(230, 234, 236))
    pend.text(0.025, 0.022, "UP  ·  DOWN  ·  FLOAT", 0.0028, fnt="label-semi", color=(160, 168, 172))
    b.decal(pend, center=(0.42, -0.8771, 0.665), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.004)
    b.decal(rating_plate(0.10, 0.035, "RADIOGRAPHY TABLE", "RT-4", "SN 26-04230", rating="400 V 3~  50/60 Hz  ·  SWL 230 kg",
                         ppm=3500), center=(-0.2601, -0.05, 0.25), normal=(-1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.02)
    b.decal(cal_sticker(0.03, 0.018, title="QA TESTED"), center=(-0.2601, -0.05, 0.33), normal=(-1, 0, 0), up=(0, 0, 1),
            mats=["hosp_white"], depth=0.02)

    for c in b.geo.charts:
        zmax = float(c.pos[:, 2].max())
        if zmax < 0.6 and c.mat not in ("hosp_white",):
            c.density *= 0.5
    boost(b, 2.5, mats=["hosp_white"], zmin=0.52, zmax=0.68)     # hand pendant
    b.col_box((-0.395, -1.1, 0.70), (0.395, 1.1, XR_TOP), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.32, -0.56, 0.0), (0.32, 0.46, 0.70), "PLASTIC_HIGH_DENSITY")
    b.col_box((cx - 0.08, -1.17, 0.0), (cx + 0.08, 1.17, 0.045), "METAL_SOLID_MEDIUM")


@prop("nz_amb_xray_tube", atlas=2048, lod=120, hd=18, static=False, falloff=70, preview={
    "cams": [{"name": "detail", "pos": [XR_ARM + 0.75, 0.0, 1.62], "target": [XR_ARM, 0.0, 1.52], "fov": 36}]}, doc={
    "title": "X-ray tube stand: column on a rail carriage, swivel arm, tube head and collimator",
    "origin": "floor, under the column on the table's floor rail",
    "axes": "same as nz_amb_xray_table (spawn it with the table's heading): the arm reaches +X over the table",
    "attach": f"place it at table offset ({XR_COL[0]}, y, 0): the focal spot is at ({XR_ARM:.2f}, 0, 1.66) of this prop, "
              f"so over (0, y) of the table; collimator light field bottom at z {XR_COLLIMATOR_Z}. Slide it along the "
              "table's Y (rail) to the body part being imaged",
})
def xray_tube(b):
    white = m_hosp_white(b)
    grey = m_hosp_grey(b)
    dark = m_hosp_dark(b)
    led = m_teal_led(b)
    glass = b.mat("coll_glass", color=(30, 40, 44), spec=0.9, gloss=0.92, edge=0.1)
    cx, cy = 0.0, 0.0
    tx, ty = XR_ARM, 0.0

    # ---- rail carriage + column ----------------------------------------------------------------
    b.add(box((0.34, 0.42, 0.12), dark, r=0.03, seg=2, center=(cx, cy, 0.09)))
    b.add(box((0.35, 0.43, 0.008), led, center=(cx, cy, 0.034), faces="+x -x +y -y"))
    b.add(box((0.22, 0.30, 2.27), white, r=0.035, seg=3, center=(cx, cy, 0.15 + 1.135), face_density={"+z": 0.3}))
    # graphite inset + teal light line on the face towards the table
    b.add(box((0.006, 0.12, 1.40), dark, r=0.002, seg=1, center=(cx + 0.112, cy - 0.02, 0.95), faces="+x +y -y +z -z"))
    b.add(box((0.006, 0.014, 1.95), led, center=(cx + 0.112, cy + 0.105, 1.22), faces="+x +y -y +z -z"))
    b.add(box((0.26, 0.34, 0.06), dark, r=0.02, seg=2, center=(cx, cy, 2.45)))
    # carriage on the column + horizontal swivel arm
    zc = 1.93
    b.add(box((0.30, 0.36, 0.26), white, r=0.04, seg=3, center=(cx + 0.01, cy, zc)))
    for dz in (-0.135, 0.135):
        b.add(box((0.306, 0.366, 0.012), dark, r=0.005, seg=1, center=(cx + 0.01, cy, zc + dz)))
    b.add(box((0.56, 0.16, 0.14), white, r=0.035, seg=3, center=(cx + (tx - cx) * 0.625, cy, zc)))
    b.add(cylinder(0.085, 0.16, dark, segs=32, bevel=0.012, z0=zc - 0.08).translate(tx, ty, 0))
    b.add(cylinder(0.087, 0.008, led, segs=32, z0=zc - 0.004, caps=(False, False)).translate(tx, ty, 0))
    # ---- tube head (housing along Y) + collimator -------------------------------------------------
    zt = 1.70
    b.add(box((0.12, 0.10, 0.10), dark, r=0.02, seg=2, center=(tx, ty, (zt + zc) / 2 + 0.02)))
    housing = lathe([(0.0, -0.21), (0.10, -0.21), (0.118, -0.195), (0.122, -0.17), (0.122, 0.17), (0.118, 0.195), (0.10, 0.21),
                     (0.0, 0.21)], white, segs=40, smooth_angle=30)
    b.add(housing.rotate(90, 0, 0).translate(tx, ty, zt))
    for sy in (-1, 1):
        cap = lathe([(0.0, 0.0), (0.104, 0.0), (0.10, 0.02), (0.07, 0.045), (0.0, 0.055)], dark, segs=36, smooth_angle=30)
        b.add(cap.rotate(-90 if sy > 0 else 90, 0, 0).translate(tx, ty + sy * 0.209, zt))
        ring = torus(0.112, 0.004, led, segs=40, tube_segs=6)
        b.add(ring.rotate(90, 0, 0).translate(tx, ty + sy * 0.185, zt))
    zc0, zc1 = XR_COLLIMATOR_Z, 1.595
    b.add(box((0.26, 0.26, zc1 - zc0), grey, r=0.022, seg=3, center=(tx, ty, (zc0 + zc1) / 2)))
    b.add(box((0.16, 0.16, 0.03), dark, r=0.01, seg=2, center=(tx, ty, zc1 + 0.012)))
    # control face (+X, towards the operator): LCD + two knobs
    b.add(box((0.004, 0.18, 0.09), m_gloss_black(b), r=0.003, seg=1, center=(tx + 0.131, ty, 1.535), faces="+x +y -y +z -z"))
    for k, yy in enumerate((-0.05, 0.05)):
        b.add(align(knob(dark, 0.024, 0.012), (1, 0, 0), (0, 0, 1), (tx + 0.131, ty + yy, 1.452)))
    # side handles (+Y / -Y)
    for sy in (-1, 1):
        hp = polyline_fillet([(tx - 0.08, ty + sy * 0.13, 1.50), (tx - 0.08, ty + sy * 0.165, 1.50), (tx + 0.08, ty + sy * 0.165, 1.50),
                              (tx + 0.08, ty + sy * 0.13, 1.50)], 0.012, 4)
        b.add(tube(hp, 0.009, dark, segs=12, tag="handle"))
    # bottom: glass window with crosshair + glowing light-field ring
    b.add(quad((tx, ty, zc0 - 0.0005), (1, 0, 0), (0, 1, 0), 0.17, 0.17, glass).rotate(180, 0, 0, origin=(tx, ty, zc0 - 0.0005)))
    b.add(box((0.24, 0.24, 0.006), led, center=(tx, ty, zc0 + 0.004), faces="+x -x +y -y"))

    # ---- decals -------------------------------------------------------------------------------
    vb = label_canvas(0.62, 0.10, "RADIOGRAPHY", "RT-4  ·  FLOOR RAIL TUBE STAND", ppm=1800, color=(236, 240, 242), sub_color=TEAL_HI)
    b.decal(vb, center=(cx + 0.1151, cy - 0.02, 1.12), normal=(1, 0, 0), up=(0, -1, 0), mats=["hosp_dark"], depth=0.008)
    scr = DecalCanvas(0.18, 0.09, ppm=2600)
    scr.rect(0, 0, 0.18, 0.09, r=0.004, color=(6, 8, 10))
    scr.text(0.01, 0.016, "SID", 0.008, fnt="label-semi", anchor="lm", color=(130, 140, 146))
    scr.text(0.17, 0.016, "100 cm", 0.009, fnt="mono-bold", anchor="rm", color=TEAL_HI)
    scr.text(0.01, 0.042, "kV  78", 0.012, fnt="mono-bold", anchor="lm", color=(236, 240, 242))
    scr.text(0.17, 0.042, "mAs 16", 0.012, fnt="mono-bold", anchor="rm", color=(236, 240, 242))
    scr.text(0.09, 0.072, "READY", 0.010, fnt="label", color=(60, 230, 140), spacing=0.001)
    b.decal(scr, center=(tx + 0.1331, ty, 1.535), normal=(1, 0, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.004)
    b.decal(radiation_label(0.05), center=(tx, ty - 0.1301, 1.556), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_grey"], depth=0.01)
    b.decal(radiation_label(0.06), center=(cx + 0.1101, cy - 0.02, 1.72), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    b.decal(caution_label(0.10, 0.045, "CAUTION", ["X-RAY  -  authorised operators only", "Keep clear of moving parts"], ppm=3000),
            center=(cx + 0.1101, cy - 0.02, 0.40), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_dark"], depth=0.01)
    cross = DecalCanvas(0.17, 0.17, ppm=2000)
    cross.rect(0.084, 0.01, 0.002, 0.15, color=(40, 230, 210))
    cross.rect(0.01, 0.084, 0.15, 0.002, color=(40, 230, 210))
    b.decal(cross, center=(tx, ty, zc0 - 0.001), normal=(0, 0, -1), up=(0, 1, 0), mats=["coll_glass"], depth=0.004)

    boost(b, 3.0, mats=["gloss_black"])
    b.col_box((cx - 0.17, cy - 0.21, 0.03), (cx + 0.17, cy + 0.21, 0.15), "METAL_SOLID_MEDIUM")
    b.col_box((cx - 0.13, cy - 0.17, 0.15), (cx + 0.13, cy + 0.17, 2.48), "PLASTIC_HIGH_DENSITY")
    b.col_box((cx + 0.13, cy - 0.09, zc - 0.08), (tx + 0.09, ty + 0.09, zc + 0.08), "PLASTIC_HIGH_DENSITY")
    b.col_box((tx - 0.13, ty - 0.22, XR_COLLIMATOR_Z), (tx + 0.14, ty + 0.22, 1.83), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# film lightbox on a rolling stand
# =============================================================================================
LB_Z = 1.47             # centre of the light panel
LB_PANEL = (0.60, 0.75)
LB_Y = 0.1465           # light panel plane


@prop("nz_amb_lightbox", atlas=1024, lod=80, hd=12, static=True, doc={
    "title": "X-ray film viewer (lightbox) on a rolling stand",
    "origin": "floor, on the stand's pole axis",
    "axes": "+Y = light panel side (front), +Z up",
    "screen": f"nz_amb_screen - emissive light panel {LB_PANEL[0]} x {LB_PANEL[1]} m centred at (0, {LB_Y}, {LB_Z}), "
              "UV 0..1 = whole panel, top-left = (0,0); default = white diffuser. Replace it with a DUI to show the film "
              "being read",
    "attach": f"film clipped on the panel: a flat film plane at y = {LB_Y + 0.004:.4f} in front of the panel; the reading "
              f"camera looks at (0, {LB_Y}, {LB_Z}) from (0, 1.05, {LB_Z})",
})
def lightbox(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    chrome = m_chrome(b)
    alu = m_alu(b)
    teal = m_teal(b)
    led = m_led(b, "led_green", (70, 255, 140))

    base, hub_top = star_base(b, dark, radius=0.30, n=5, hub_r=0.05, caster_r=0.032)
    b.add(base)
    b.add(pole(alu, 0, 0, hub_top - 0.01, 1.24, r=0.019))
    b.add(collar(teal, 0, 0, 0.70, r=0.026, h=0.04))
    b.add(collar(dark, 0, 0, hub_top + 0.01, r=0.03, h=0.04))
    # mounting bracket from the pole into the back of the housing
    b.add(box((0.10, 0.07, 0.22), dark, r=0.015, seg=2, center=(0, 0.035, 1.20)))
    # housing
    W, D, H = 0.68, 0.075, 0.92
    yc = 0.07 + D / 2
    hz = LB_Z - 0.035
    b.add(box((W, D, H), white, r=0.02, seg=3, center=(0, yc, hz)))
    yf = yc + D / 2
    # front bezel frame (graphite) around the panel
    pw, ph = LB_PANEL
    fr = 0.022
    for (sx, sz, w, h) in ((0, 1, pw + 2 * fr, fr), (0, -1, pw + 2 * fr, fr), (1, 0, fr, ph), (-1, 0, fr, ph)):
        cxx = sx * (pw / 2 + fr / 2)
        czz = LB_Z + sz * (ph / 2 + fr / 2)
        b.add(box((w, 0.006, h), dark, r=0.002, seg=1, center=(cxx, yf + 0.003, czz), faces="+y +x -x +z -z"))
    b.screen(quad((0, yf + 0.0015, LB_Z), (-1, 0, 0), (0, 0, 1), pw, ph, "x", fixed_uv=True),
             image=draw_lightbox_panel(512, 640), size=(512, 512), mult=1.6)
    # film clip rail with three spring clips along the top edge
    zr = LB_Z + ph / 2 - 0.012
    b.add(cylinder(0.006, pw - 0.02, chrome, segs=12, z0=-(pw - 0.02) / 2).rotate(0, 90, 0).translate(0, yf + 0.012, zr))
    for x in (-0.2, 0.0, 0.2):
        b.add(box((0.05, 0.014, 0.03), grey, r=0.004, seg=2, center=(x, yf + 0.014, zr - 0.006)))
        b.add(box((0.03, 0.004, 0.012), dark, r=0.0015, seg=1, center=(x, yf + 0.022, zr - 0.016)))
    # bottom bezel controls: power rocker + LED + brightness knob
    zb = LB_Z - ph / 2 - fr - 0.045
    b.add(box((0.026, 0.008, 0.016), dark, r=0.003, seg=1, center=(0.27, yf + 0.004, zb)))
    b.add(box((0.012, 0.006, 0.012), b.mat("rocker", color=(26, 160, 150), spec=0.4, gloss=0.6, edge=0.3), r=0.002, seg=1,
              center=(0.274, yf + 0.009, zb)))
    b.add(align(cylinder(0.0025, 0.002, led, segs=10, caps=(False, True)), (0, 1, 0), (0, 0, 1), (0.24, yf, zb)))
    b.add(align(knob(dark, 0.024, 0.012), (0, 1, 0), (0, 0, 1), (0.20, yf, zb)))
    # back: vent slots + cable
    b.decal(vents(0.30, 0.05, 10, vertical=True), center=(0, 0.0699, LB_Z + 0.33), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    cab = catmull([(0.12, 0.07, 1.10), (0.12, 0.02, 1.0), (0.05, -0.01, 0.8), (0.03, -0.022, 0.5), (0.05, -0.04, 0.2), (0.15, -0.05, 0.12)], n=6)
    b.add(tube(cab, 0.004, m_black_plastic(b), segs=8))
    dc = label_canvas(0.40, 0.03, "FILM VIEWER", "LB-1  ·  DAYLIGHT 6500 K", ppm=3000, color=(60, 64, 70), sub_color=(20, 120, 112))
    b.decal(dc, center=(-0.12, yf + 0.0001, zb), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.008)
    leg = DecalCanvas(0.06, 0.012, ppm=6000)
    leg.text(0.03, 0.006, "BRIGHTNESS", 0.003, fnt="label-semi", color=(80, 88, 94))
    b.decal(leg, center=(0.20, yf + 0.0001, zb - 0.02), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.008)
    boost(b, 1.6, mats=["hosp_white"], zmin=0.9)
    b.col_box((-W / 2, 0.07, hz - H / 2), (W / 2, yf + 0.025, hz + H / 2), "PLASTIC_HIGH_DENSITY")
    b.col_cyl((0, 0, 0.62), 0.02, 1.0, "z", "METAL_HOLLOW_SMALL")
    b.col_box((-0.30, -0.30, 0.0), (0.30, 0.30, hub_top), "METAL_HOLLOW_SMALL")


# =============================================================================================
# contrast power injector on a mobile tray
# =============================================================================================
INJ_TRAY_Z = 0.96       # top of the tray mat
INJ_PLUNGER = (0.03, 0.05, INJ_TRAY_Z + 0.08)   # plunger face (separate model) in injector space
INJ_TRAVEL = 0.20       # plunger travel along -X (full -> empty)
INJ_SLEEVE_X = 0.078    # front of the ram sleeve


@prop("nz_amb_injector", atlas=2048, alpha_atlas=512, lod=70, hd=12, static=True, falloff=80, preview={
    "cams": [{"name": "detail", "pos": [-0.15, 0.55, 1.35], "target": [0.05, 0.05, 1.03], "fov": 40}]}, doc={
    "title": "Contrast power injector on a mobile pole tray",
    "origin": "floor, under the centre of the tray",
    "axes": "tray 0.90 (X) x 0.50 (Y); syringe along X with its tip at -X, motor head at +X; delivery line drapes over "
            "the front edge (+Y); +Z up",
    "attach": f"syringe tip at (-0.235, 0.05, {INJ_TRAY_Z + 0.08:.3f}); the syringe plunger + ram is the separate model "
              f"nz_amb_injector_plunger - ALWAYS spawn it with the injector, attached at {INJ_PLUNGER} rot (0, 0, 0) and "
              f"slide it 0 .. {INJ_TRAVEL} m along -X while dye goes in (the contrast column stays drawn); delivery line "
              "ends at (-0.47, 0.30, 0.66) - attach a line prop / rope from there to the patient's IV port; camera over the "
              "tray: (0.0, 0.55, 1.45) looking at (0, 0, 1.0)",
})
def injector(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    chrome = m_chrome(b)
    alu = m_alu(b)
    teal = m_teal(b)
    steel = m_stainless(b)
    mat_teal = b.mat("tray_mat", color=(16, 122, 124), spec=0.18, gloss=0.3, bump="ribs", bump_amp=0.00012, bump_scale=0.004,
                     grain=0.04, grain_scale=0.05, edge=0.1)
    tubing = b.mat("line_white", color=(236, 238, 238), spec=0.45, gloss=0.6, edge=0.1)
    clear = b.mat("barrel_clear", color=(232, 238, 240), spec=0.9, gloss=0.93, alpha=0.16, layer="alpha", grain=0.0)
    dye = b.mat("contrast", color=(244, 236, 200), spec=0.6, gloss=0.9, alpha=0.30, layer="alpha", grain=0.0)
    led = m_led(b, "led_green", (70, 255, 140))

    # ---- mobile stand: H base with casters, pole ---------------------------------------------
    py = -0.10
    zc = caster_top(0.034)
    for sx in (-1, 1):
        b.add(box((0.06, 0.62, 0.04), dark, r=0.012, seg=2, center=(sx * 0.26, py, zc + 0.02)))
        for sy in (-1, 1):
            b.add(caster(b, sx * 0.26, py + sy * 0.28, r=0.034, yaw=0, lock=(sy > 0)))
    b.add(box((0.52, 0.07, 0.05), dark, r=0.012, seg=2, center=(0, py, zc + 0.025)))
    b.add(pole(alu, 0, py, zc + 0.05, INJ_TRAY_Z - 0.06, r=0.024))
    b.add(collar(teal, 0, py, 0.55, r=0.03, h=0.04))
    b.add(collar(dark, 0, py, zc + 0.07, r=0.034, h=0.04))
    # power unit hanging on the pole
    b.add(box((0.22, 0.14, 0.18), white, r=0.02, seg=3, center=(0, py - 0.10, 0.72)))
    b.add(box((0.08, 0.06, 0.05), dark, r=0.01, seg=2, center=(0, py - 0.03, 0.75)))
    b.add(box((0.15, 0.004, 0.06), m_gloss_black(b), r=0.002, seg=1, center=(0, py - 0.172, 0.75), faces="-y +x -x +z -z"))
    b.add(box((0.004, 0.10, 0.12), b.mat("warn_orange", color=(236, 104, 34), spec=0.35, gloss=0.5, edge=0.3), r=0.002, seg=1,
              center=(0.112, py - 0.10, 0.72), faces="+x +y -y +z -z"))
    # ---- tray -------------------------------------------------------------------------------------
    TW, TD = 0.90, 0.50
    b.add(box((0.24, 0.24, 0.05), dark, r=0.012, seg=2, center=(0, py + 0.02, INJ_TRAY_Z - 0.06)))
    b.add(box((TW, TD, 0.03), white, r=0.012, seg=2, center=(0, 0, INJ_TRAY_Z - 0.019)))
    for (sx, sy, w, d) in ((0, 1, TW, 0.022), (0, -1, TW, 0.022), (1, 0, 0.022, TD - 0.044), (-1, 0, 0.022, TD - 0.044)):
        b.add(box((w, d, 0.03), white, r=0.008, seg=2, center=(sx * (TW / 2 - 0.011), sy * (TD / 2 - 0.011), INJ_TRAY_Z + 0.008)))
    b.add(box((TW - 0.05, TD - 0.05, 0.004), mat_teal, center=(0, 0, INJ_TRAY_Z - 0.002), faces="+z"))
    # ---- injector head ------------------------------------------------------------------------------
    zp = INJ_TRAY_Z
    b.add(box((0.62, 0.16, 0.03), white, r=0.01, seg=2, center=(0.01, 0.05, zp + 0.015)))
    b.add(box((0.17, 0.16, 0.17), white, r=0.022, seg=3, center=(0.255, 0.05, zp + 0.03 + 0.085)))
    b.add(box((0.004, 0.10, 0.06), m_gloss_black(b), r=0.002, seg=1, center=(0.1705, 0.05, zp + 0.17), faces="-x +y -y +z -z"))
    # ram sleeve (the ram + syringe plunger are the separate model nz_amb_injector_plunger)
    zs = zp + 0.08
    b.add(cylinder(0.012, 0.095, chrome, segs=16, bevel=0.002, z0=0.0).rotate(0, 90, 0).translate(INJ_SLEEVE_X, 0.05, zs))
    b.add(cylinder(0.02, 0.012, dark, segs=20, bevel=0.003, z0=-0.012).rotate(0, 90, 0).translate(0.17, 0.05, zs))
    # big syringe (clear barrel along X, tip at -X)
    R, x0, x1 = 0.034, 0.055, -0.185
    prof = [(R - 0.003, 0.0), (R, 0.0), (R, x0 - x1 - 0.006), (R - 0.004, x0 - x1), (0.008, x0 - x1 + 0.03), (0.006, x0 - x1 + 0.034),
            (0.006, x0 - x1 + 0.05), (0.0, x0 - x1 + 0.05)]
    barrel = lathe(prof, clear, segs=40, smooth_angle=35)
    b.add(barrel.rotate(0, -90, 0).translate(x0, 0.05, zs))
    flange = box((0.008, 0.11, 0.09), clear, r=0.006, seg=2, center=(x0 + 0.004, 0.05, zs))
    b.add(flange)
    # contrast column from the plunger face to the tip
    xs = INJ_PLUNGER[0]
    b.add(cylinder(R - 0.0025, xs - x1 - 0.002, dye, segs=36, z0=0).rotate(0, -90, 0).translate(xs - 0.001, 0.05, zs))
    # cradle: two teal saddles + upright clamp plates
    for xx in (-0.12, -0.01):
        b.add(box((0.035, 0.11, 0.035), teal, r=0.008, seg=2, center=(xx, 0.05, zp + 0.045)))
        for sy in (-1, 1):
            b.add(box((0.028, 0.012, 0.075), teal, r=0.004, seg=2, center=(xx, 0.05 + sy * (R + 0.008), zs + 0.005)))
    # luer tip + delivery line draping over the front edge
    tip = (x1 - 0.05, 0.05, zs)
    b.add(cylinder(0.009, 0.018, teal, segs=16, bevel=0.002, z0=0).rotate(0, -90, 0).translate(tip[0] + 0.012, 0.05, zs))
    line = catmull([(tip[0] - 0.004, 0.05, zs), (tip[0] - 0.04, 0.06, zs - 0.03), (-0.31, 0.12, zp + 0.012), (-0.36, 0.20, zp + 0.012),
                    (-0.40, 0.255, zp + 0.035), (-0.42, 0.285, zp - 0.02), (-0.44, 0.30, 0.80), (-0.47, 0.30, 0.68)], n=8)
    b.add(tube(line, 0.0035, tubing, segs=10, tag="line"))
    b.add(cylinder(0.0065, 0.03, teal, segs=14, bevel=0.0015, z0=-0.03).translate(-0.47, 0.30, 0.68))
    # tray accessories: stainless bowl + sterile pack + spare syringe pack
    bowl = lathe([(0.0, 0.0), (0.045, 0.0), (0.06, 0.012), (0.075, 0.035), (0.078, 0.037), (0.072, 0.037), (0.056, 0.016),
                  (0.042, 0.004), (0.0, 0.004)], steel, segs=40, smooth_angle=30)
    b.add(bowl.translate(-0.32, -0.12, zp))
    b.add(box((0.16, 0.12, 0.018), white, r=0.006, seg=2, center=(0.30, -0.15, zp + 0.009)))
    b.add(box((0.15, 0.06, 0.012), b.mat("pack_blue", color=(70, 140, 200), spec=0.3, gloss=0.5, edge=0.2), r=0.004, seg=1,
              center=(0.02, -0.15, zp + 0.006)))

    # ---- decals -----------------------------------------------------------------------------------------
    hd = DecalCanvas(0.15, 0.15, ppm=3000)
    hd.star_of_life(0.031, 0.031, 0.03, color=(40, 110, 210))
    hd.text(0.056, 0.026, "CT INJECTOR", 0.0095, fnt="label", anchor="lm", color=(36, 40, 44), spacing=0.001, max_w=0.09)
    hd.text(0.056, 0.042, "CI-2  ·  SINGLE HEAD", 0.0062, fnt="label-semi", anchor="lm", color=TEAL, spacing=0.0006, max_w=0.09)
    b.decal(hd, center=(0.255, 0.1301, zp + 0.12), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.02)
    b.decal(vents(0.12, 0.10, 6), center=(0.3401, 0.05, zp + 0.11), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    lcd = DecalCanvas(0.10, 0.06, ppm=3600)
    lcd.rect(0, 0, 0.10, 0.06, r=0.002, color=(6, 10, 12))
    lcd.text(0.006, 0.012, "150 mL", 0.009, fnt="mono-bold", anchor="lm", color=(236, 240, 242))
    lcd.text(0.094, 0.012, "5.0 mL/s", 0.0068, fnt="mono", anchor="rm", color=AMBER)
    lcd.text(0.006, 0.032, "PSI 300  ·  ARMED", 0.0058, fnt="mono", anchor="lm", color=TEAL_HI)
    lcd.rect(0.006, 0.044, 0.088, 0.008, r=0.002, color=(20, 40, 40))
    lcd.rect(0.006, 0.044, 0.060, 0.008, r=0.002, color=TEAL)
    b.decal(lcd, center=(0.1701, 0.05, zp + 0.17), normal=(-1, 0, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.004)
    sc = DecalCanvas(0.20, 0.03, ppm=5000)
    for k in range(0, 16):
        x = 0.006 + k * 0.0125
        major = k % 5 == 0
        sc.rect(x, 0.0, 0.0006, 0.012 if major else 0.007, color=(20, 22, 24))
        if major:
            sc.text(x, 0.019, str(200 - k * 10), 0.0034, fnt="label-semi", color=(20, 22, 24))
    b.decal(sc, center=(-0.065, 0.05, zs + R), normal=(0, 0, 1), up=(0, -1, 0), mats=["barrel_clear"], depth=0.01, min_dot=0.3)
    pu = DecalCanvas(0.15, 0.06, ppm=3000)
    pu.rect(0, 0, 0.15, 0.06, r=0.002, color=(6, 10, 12))
    pu.text(0.075, 0.018, "INJECTOR POWER", 0.0068, fnt="label", color=(200, 206, 210), spacing=0.0008)
    pu.text(0.075, 0.040, "ON  ·  LINE OK", 0.0062, fnt="mono", color=(60, 230, 140))
    b.decal(pu, center=(0, py - 0.1741, 0.75), normal=(0, -1, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.004)
    b.add(align(cylinder(0.003, 0.002, led, segs=10, caps=(False, True)), (0, -1, 0), (0, 0, 1), (0.08, py - 0.172, 0.69)))
    warn = text_canvas([("CONTRAST", 0.05, 0.03, 0.009, "label", (255, 255, 255), "mm", 0.001),
                        ("HIGH PRESSURE", 0.05, 0.06, 0.0065, "label-semi", (255, 255, 255), "mm", 0.0005)], 0.10, 0.09, ppm=3000)
    b.decal(warn, center=(0.1141, py - 0.10, 0.725), normal=(1, 0, 0), up=(0, 0, 1), mats=["warn_orange"], depth=0.004)
    b.decal(rating_plate(0.07, 0.025, "CONTRAST INJECTOR", "CI-2", "SN 26-08802", rating="100-240 V~  50/60 Hz  2.0 A"),
            center=(0.255, -0.0301, zp + 0.10), normal=(0, -1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)

    boost(b, 3.0, mats=["gloss_black", "warn_orange"])
    boost(b, 1.5, mats=["hosp_white"], zmin=INJ_TRAY_Z)
    b.col_box((-TW / 2, -TD / 2, INJ_TRAY_Z - 0.035), (TW / 2, TD / 2, INJ_TRAY_Z + 0.025), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.20, -0.04, INJ_TRAY_Z), (0.34, 0.14, INJ_TRAY_Z + 0.20), "PLASTIC_HIGH_DENSITY")
    b.col_cyl((0, py, 0.5), 0.025, 0.85, "z", "METAL_HOLLOW_SMALL")
    b.col_box((-0.11, py - 0.17, 0.63), (0.11, py - 0.03, 0.81), "PLASTIC_HIGH_DENSITY")
    b.col_box((-0.30, py - 0.33, 0.0), (0.30, py + 0.33, zc + 0.05), "METAL_HOLLOW_SMALL")


@prop("nz_amb_injector_plunger", atlas=256, lod=30, hd=5, doc={
    "title": "Power-injector syringe plunger + ram (moving part of nz_amb_injector)",
    "origin": "the plunger face (front of the rubber stopper) on the syringe axis",
    "axes": "ram runs along +X back into the injector head; the plunger pushes towards -X",
    "attach": f"attach to the nz_amb_injector entity at {INJ_PLUNGER} rot (0, 0, 0) (collision off); full syringe = offset "
              f"0, empty = {INJ_TRAVEL} m along -X (x = {INJ_PLUNGER[0] - INJ_TRAVEL:.2f})",
})
def injector_plunger(b):
    stopper = b.mat("stopper", color=(30, 31, 34), spec=0.3, gloss=0.45, edge=0.2)
    chrome = m_chrome(b)
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    R = 0.034
    # rubber stopper (two ribs), plunger stem, push plate, ram
    b.add(lathe([(0.0, 0.0), (R - 0.0024, 0.0), (R - 0.0018, 0.003), (R - 0.0026, 0.007), (R - 0.0018, 0.011), (R - 0.0024, 0.016),
                 (0.0, 0.016)], stopper, segs=36, smooth_angle=40).rotate(0, 90, 0))
    b.add(cylinder(0.012, 0.02, white, segs=20, z0=0.016).rotate(0, 90, 0))
    b.add(cylinder(0.027, 0.008, dark, segs=28, bevel=0.002, z0=0.036).rotate(0, 90, 0))
    b.add(cylinder(0.008, 0.26, chrome, segs=16, z0=0.044).rotate(0, 90, 0))
    knurl = b.mat("ram_knurl", color=(140, 144, 150), spec=0.75, gloss=0.55, metal=1.0, bump="knurl", bump_amp=0.0001,
                  bump_scale=0.0014, edge=0.4)
    b.add(cylinder(0.0105, 0.03, knurl, segs=20, bevel=0.0015, z0=0.27).rotate(0, 90, 0))
    for x in (0.10, 0.18):
        b.add(cylinder(0.0086, 0.002, dark, segs=16, caps=(False, False), z0=x).rotate(0, 90, 0))
    b.col_cyl((0.15, 0.0, 0.0), 0.02, 0.3, "x", "PLASTIC")


# =============================================================================================
# contrast-run pedestal button
# =============================================================================================
BTN_TOP = 1.012


@prop("nz_amb_contrast_button", atlas=1024, lod=60, hd=10, static=True, preview={
    "cams": [{"name": "detail", "pos": [0.0, 0.32, 1.20], "target": [0.0, 0.0, 0.96], "fov": 34}]}, doc={
    "title": "Contrast-run pedestal: big red mushroom button on a teal housing",
    "origin": "floor, on the pedestal axis",
    "axes": "+Y = front (labels), +Z up; key switch and ARMED LED on the top plate behind the button",
    "attach": f"button top centre at (0, 0.0, {BTN_TOP}) - press anim target; hand IK point (0, 0.02, {BTN_TOP + 0.02:.3f}); "
              "ped stands at (0, 0.45, 0) facing -Y",
})
def contrast_button(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    teal = m_teal(b)
    chrome = m_chrome(b)
    rub = m_rubber(b)
    red = b.mat("mushroom_red", color=(206, 30, 36), spec=0.6, gloss=0.78, edge=0.3)
    yellow = b.mat("guard_yellow", color=(240, 196, 30), spec=0.4, gloss=0.55, edge=0.3)
    led = m_led(b, "led_green", (70, 255, 140))
    # weighted base
    b.add(lathe([(0.0, 0.0), (0.155, 0.0), (0.165, 0.006), (0.165, 0.02), (0.15, 0.034), (0.05, 0.042), (0.0, 0.042)], dark,
                segs=48, smooth_angle=30))
    b.add(torus(0.152, 0.005, teal, segs=48, tube_segs=8).translate(0, 0, 0.03))
    b.add(cylinder(0.168, 0.004, rub, segs=48, z0=-0.0015))
    # pole + collars
    b.add(pole(white, 0, 0, 0.04, 0.905, r=0.021))
    b.add(collar(teal, 0, 0, 0.10, r=0.028, h=0.035))
    b.add(collar(teal, 0, 0, 0.55, r=0.028, h=0.03))
    b.add(collar(dark, 0, 0, 0.88, r=0.034, h=0.05))
    # housing
    z0, z1 = 0.905, 0.975
    b.add(box((0.17, 0.14, z1 - z0), teal, r=0.016, seg=3, center=(0, 0, (z0 + z1) / 2)))
    plate = b.mat("btn_plate", color=(54, 58, 63), spec=0.3, gloss=0.46, bump="stipple", bump_amp=0.00003, bump_scale=0.0008, edge=0.5)
    b.add(box((0.12, 0.10, 0.006), plate, r=0.012, seg=2, center=(0, -0.004, z1 + 0.002)))
    # mushroom button + yellow guard ring
    b.add(cylinder(0.044, 0.006, yellow, segs=40, bevel=0.0015, z0=z1 + 0.004).translate(0, -0.004, 0))
    b.add(cylinder(0.02, 0.016, dark, segs=24, z0=z1 + 0.008).translate(0, -0.004, 0))
    cap = lathe([(0.0, 0.0), (0.03, 0.0), (0.0355, 0.004), (0.036, 0.012), (0.03, 0.022), (0.016, 0.028), (0.0, 0.0295)], red,
                segs=40, smooth_angle=40)
    b.add(cap.translate(0, -0.004, BTN_TOP - 0.0295))
    # key switch + ARMED LED on the top plate rear
    b.add(cylinder(0.009, 0.006, chrome, segs=20, bevel=0.0015, z0=z1 + 0.004).translate(0.045, 0.048, 0))
    b.add(box((0.002, 0.008, 0.004), dark, center=(0.045, 0.048, z1 + 0.011)))
    b.add(cylinder(0.004, 0.004, led, segs=12, caps=(False, True), z0=z1 + 0.003).translate(-0.045, 0.048, 0))
    # coiled cord from the housing down the back of the pole, then a straight lead into the base
    t = np.linspace(0, 1, 420)
    zc0, zc1 = z0 - 0.01, 0.30
    axis_y = -0.034
    hel = np.stack([0.008 * np.cos(t * 2 * math.pi * 46), axis_y + 0.008 * np.sin(t * 2 * math.pi * 46), zc0 - t * (zc0 - zc1)], axis=1)
    b.add(tube(hel, 0.0026, m_black_plastic(b), segs=6, tag="coil", split=0.2))
    lead = catmull([(0.0, axis_y, zc1), (0.0, axis_y - 0.004, 0.2), (0.0, axis_y - 0.01, 0.08), (0.0, -0.06, 0.045)], n=6)
    b.add(tube(lead, 0.0028, m_black_plastic(b), segs=8))
    b.add(box((0.016, 0.02, 0.03), dark, r=0.004, seg=1, center=(0, -0.05, z0 - 0.012)))
    # decals
    lab = DecalCanvas(0.16, 0.06, ppm=3600)
    lab.text(0.08, 0.02, "CONTRAST RUN", 0.0105, fnt="label", color=(255, 255, 255), spacing=0.0012)
    lab.text(0.08, 0.042, "PRESS + HOLD TO INJECT", 0.0062, fnt="label-semi", color=(220, 250, 246), spacing=0.0006)
    b.decal(lab, center=(0, 0.0701, (z0 + z1) / 2), normal=(0, 1, 0), up=(0, 0, 1), mats=["teal"], depth=0.01)
    top = DecalCanvas(0.12, 0.10, ppm=4000)
    # canvas top towards -Y so the legends read from the front; x runs towards -X (the viewer's right)
    top.text(0.105, 0.084, "ARMED", 0.0055, fnt="label", color=(200, 206, 210))
    top.text(0.015, 0.084, "KEY", 0.0055, fnt="label", color=(200, 206, 210))
    b.decal(top, center=(0, -0.004, z1 + 0.0051), normal=(0, 0, 1), up=(0, -1, 0), mats=["btn_plate"], depth=0.003)
    bd = label_canvas(0.12, 0.022, "CONTRAST", "INJECT SWITCH  CB-1", ppm=4500, color=(255, 255, 255), sub_color=(220, 250, 246),
                      icon=None)
    b.decal(bd, center=(0, -0.0701, (z0 + z1) / 2), normal=(0, -1, 0), up=(0, 0, 1), mats=["teal"], depth=0.01)
    boost(b, 3.0, mats=["btn_plate"])
    boost(b, 2.5, mats=["teal"], zmin=0.89)
    b.col_cyl((0, 0, 0.021), 0.165, 0.042, "z", "METAL_SOLID_MEDIUM")
    b.col_cyl((0, 0, 0.47), 0.024, 0.86, "z", "METAL_HOLLOW_SMALL")
    b.col_box((-0.085, -0.07, z0), (0.085, 0.07, BTN_TOP), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# boom-mounted fluoroscopy monitor (floor boom stand)
# =============================================================================================
AM_SCREEN = (0.94, 0.53)
AM_Z = 1.55
AM_Y = 0.62


@prop("nz_amb_angio_monitor", atlas=2048, lod=100, hd=15, static=True, doc={
    "title": "Fluoroscopy monitor on a boom stand",
    "origin": "floor, on the boom column axis",
    "axes": "boom reaches +Y over the table side; screen faces +Y; +Z up",
    "screen": f"nz_amb_screen - quad {AM_SCREEN[0]} x {AM_SCREEN[1]} m (aspect 1.77) centred at (0, {AM_Y + 0.0385:.4f}, {AM_Z}), "
              "UV 0..1 = visible screen, top-left = (0,0); default = live fluoroscopy frame",
    "attach": f"viewing camera: from (0, {AM_Y + 1.1:.2f}, {AM_Z}) looking -Y fills the screen with a 40 deg FOV; place it "
              "beside the head end of the angio table so the boom hangs over the patient's legs",
})
def angio_monitor(b):
    white = m_hosp_white(b)
    dark = m_hosp_dark(b)
    grey = m_hosp_grey(b)
    teal = m_teal(b)
    blk = m_black_plastic(b)
    bezel = b.mat("monitor_bezel", color=(32, 34, 38), spec=0.35, gloss=0.55, bump="stipple", bump_amp=0.00003, bump_scale=0.0008, edge=0.45)
    led = m_teal_led(b)
    # base with locking casters
    zc = caster_top(0.04)
    b.add(box((0.70, 0.70, 0.08), dark, r=0.03, seg=3, center=(0, 0, zc + 0.04)))
    b.add(box((0.66, 0.66, 0.006), led, center=(0, 0, zc + 0.083), faces="+x -x +y -y"))
    b.add(box((0.62, 0.62, 0.04), white, r=0.02, seg=2, center=(0, 0, zc + 0.105)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.add(caster(b, sx * 0.29, sy * 0.29, r=0.04, w=0.026, yaw=45 * sx * sy, lock=True))
    zb = zc + 0.125
    # column
    b.add(cylinder(0.075, 2.02 - zb, white, segs=40, bevel=0.006, z0=zb))
    b.add(collar(dark, 0, 0, zb + 0.03, r=0.09, h=0.06))
    b.add(collar(teal, 0, 0, 1.05, r=0.081, h=0.05))
    b.add(cylinder(0.092, 0.13, dark, segs=40, bevel=0.012, z0=2.0))
    # boom arm + elbow + drop link + yoke
    za = 2.065
    b.add(box((0.11, 0.62, 0.10), white, r=0.035, seg=3, center=(0, 0.31, za)))
    b.add(box((0.112, 0.50, 0.006), led, center=(0, 0.31, za - 0.03), faces="+x -x"))
    b.add(cylinder(0.065, 0.14, dark, segs=32, bevel=0.01, z0=za - 0.07).translate(0, AM_Y, 0))
    zt = AM_Z + AM_SCREEN[1] / 2 + 0.06
    b.add(box((0.06, 0.06, za - 0.07 - zt + 0.04), grey, r=0.012, seg=2, center=(0, AM_Y - 0.055, (za - 0.07 + zt - 0.04) / 2)))
    b.add(box((0.36, 0.05, 0.05), dark, r=0.015, seg=2, center=(0, AM_Y - 0.055, zt - 0.06)))
    b.add(box((0.30, 0.06, 0.18), dark, r=0.02, seg=2, center=(0, AM_Y - 0.06, AM_Z)))
    # monitor
    W, H, D = 1.00, 0.60, 0.07
    b.add(box((W, D, H), bezel, r=0.014, seg=3, center=(0, AM_Y, AM_Z)))
    yf = AM_Y + D / 2
    b.add(box((AM_SCREEN[0] + 0.012, 0.003, AM_SCREEN[1] + 0.012), m_gloss_black(b), r=0.003, seg=1,
              center=(0, yf + 0.0015, AM_Z), faces="+y +x -x +z -z"))
    b.screen(quad((0, yf + 0.0035, AM_Z), (-1, 0, 0), (0, 0, 1), AM_SCREEN[0], AM_SCREEN[1], "x", fixed_uv=True),
             image=draw_angio_ui(1024, 576), size=(1024, 512), mult=1.0)
    # sterile handle bar under the monitor
    hp = polyline_fillet([(-0.32, yf - 0.01, AM_Z - H / 2 + 0.01), (-0.32, yf + 0.05, AM_Z - H / 2 - 0.04),
                          (0.32, yf + 0.05, AM_Z - H / 2 - 0.04), (0.32, yf - 0.01, AM_Z - H / 2 + 0.01)], 0.03, 5)
    b.add(tube(hp, 0.013, teal, segs=14, tag="handle"))
    # cables along the boom
    cab = catmull([(0.04, AM_Y - 0.09, AM_Z + 0.1), (0.05, AM_Y - 0.09, za - 0.12), (0.06, AM_Y - 0.2, za - 0.055),
                   (0.06, 0.1, za - 0.055), (0.06, 0.08, 1.9), (0.08, 0.06, 1.2), (0.09, 0.04, 0.4), (0.15, 0.02, zb)], n=6)
    b.add(tube(cab, 0.006, blk, segs=8))
    # decals
    bd = label_canvas(0.20, 0.024, "FLUORO DISPLAY", "FD-55  ·  MEDICAL GRADE", ppm=3500, color=(222, 228, 230), sub_color=TEAL_HI,
                      icon=None)
    b.decal(bd, center=(0, yf + 0.0001, AM_Z - H / 2 + 0.017), normal=(0, 1, 0), up=(0, 0, 1), mats=["monitor_bezel"], depth=0.006)
    vb = label_canvas(0.40, 0.07, "FD-55 BOOM", "MAX ARM LOAD 25 kg", ppm=2000, color=(46, 50, 54), sub_color=TEAL)
    b.decal(vb, center=(0.0, 0.0751, 1.45), normal=(0, 1, 0), up=(1, 0, 0), mats=["hosp_white"], depth=0.03)
    b.decal(vents(0.60, 0.30, 8), center=(0, AM_Y - D / 2 - 0.0001, AM_Z + 0.08), normal=(0, -1, 0), up=(0, 0, 1),
            mats=["monitor_bezel"], depth=0.005)
    b.decal(rating_plate(0.08, 0.03, "FLUORO DISPLAY", "FD-55", "SN 26-22015", rating="24 V DC  6.0 A"),
            center=(0, AM_Y - D / 2 - 0.0001, AM_Z - 0.18), normal=(0, -1, 0), up=(0, 0, 1), mats=["monitor_bezel"], depth=0.005)
    b.decal(cal_sticker(0.028, 0.017), center=(0.1, AM_Y - D / 2 - 0.0001, AM_Z - 0.18), normal=(0, -1, 0), up=(0, 0, 1),
            mats=["monitor_bezel"], depth=0.005)
    b.add(screws(b, [(sx * 0.42, AM_Y - D / 2, AM_Z + sz * 0.24) for sx in (-1, 1) for sz in (-1, 1)], (0, -1, 0), d=0.007, segs=12))
    for c in b.geo.charts:
        if float(c.pos[:, 2].max()) < 0.3:
            c.density *= 0.5
    b.col_box((-0.35, -0.35, 0.0), (0.35, 0.35, zb), "METAL_SOLID_MEDIUM")
    b.col_cyl((0, 0, (zb + 2.13) / 2), 0.08, 2.13 - zb, "z", "METAL_HOLLOW_MEDIUM")
    b.col_box((-0.06, 0.0, za - 0.05), (0.06, AM_Y + 0.07, za + 0.05), "METAL_HOLLOW_MEDIUM")
    b.col_box((-W / 2, AM_Y - D / 2 - 0.1, AM_Z - H / 2), (W / 2, AM_Y + D / 2, AM_Z + H / 2), "PLASTIC_HIGH_DENSITY")
