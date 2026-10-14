"""
Hand-held instruments: IO driver, syringe, laryngoscope, ultrasound probe, stethoscope.
Part builders (iodrill_geo, syringe_geo) are reused by the open trauma case.

These are seen at arm's length in close-up camera shots: 1024 atlases (full-size normal + spec),
moulded split lines, screws, overmoulds, printed fine print and colour-coded parts.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (DecalCanvas, Geo, box, catmull, cylinder, extrude, lathe, prop, rrect, sphere, sweep, torus, tube)

from .common import (align, caution_label, label_canvas, m_black_plastic, m_chrome, m_led, m_rubber, m_steel, rating_plate,
                     screw, strain_relief)

YZ_FROM_XY = np.array([[0, 0, 1], [1, 0, 0], [0, 1, 0]], dtype=float)  # 2D (x, y) -> (Y, Z), extrusion -> X
INK = (28, 30, 33)


def _along_y(g: Geo):
    """Lathe/cylinder built around +Z -> axis along +Y."""
    return g.rotate(-90, 0, 0)


def _hex_prism(r, length, mat, z0=0.0):
    pts = [(r * math.cos(math.radians(30 + 60 * k)), r * math.sin(math.radians(30 + 60 * k))) for k in range(6)]
    return extrude(np.array(pts), length, mat, bevel=r * 0.08, bevel_seg=1, z0=z0, smooth_angle=20)


# =============================================================================================
# IO driver
# =============================================================================================
IO_ZB = 0.048          # body axis height


def _io_mats(b):
    body = b.mat("drill_body", color=(184, 188, 192), spec=0.34, gloss=0.5, bump="stipple", bump_amp=0.000025,
                 bump_scale=0.0005, grain=0.025, grain_scale=0.04, edge=0.55, dirt=0.22, wear_color=(214, 218, 220))
    rub = b.mat("drill_rubber", color=(46, 48, 52), spec=0.14, gloss=0.24, bump="dimple", bump_amp=0.00016,
                bump_scale=0.0019, grain=0.04, grain_scale=0.02, edge=0.3, dirt=0.3, wear_color=(70, 72, 76))
    red = b.mat("drill_red", color=(190, 36, 40), spec=0.4, gloss=0.55, bump="stipple", bump_amp=0.00002, bump_scale=0.0005,
                grain=0.03, grain_scale=0.03, edge=0.5, dirt=0.15)
    ribs = b.mat("drill_ribs", color=(34, 36, 39), spec=0.14, gloss=0.22, bump="ribs", bump_amp=0.00018, bump_scale=0.0016,
                 edge=0.3, dirt=0.25)
    hub = b.mat("io_hub_blue", color=(36, 104, 196), spec=0.45, gloss=0.62, bump="ribs_u", bump_amp=0.00006,
                bump_scale=0.0011, edge=0.35)
    window = b.mat("gauge_window", color=(10, 12, 14), spec=0.85, gloss=0.9, edge=0.2, scratch=0.25)
    return body, rub, red, ribs, hub, window


def iodrill_geo(b, detail=True):
    body, rub, red, ribs, hub, window = _io_mats(b)
    steel = m_steel(b)
    chrome = m_chrome(b)
    g = Geo()
    zb = IO_ZB
    # motor housing: lathe along Y with a stepped nose and a groove ring before the nose cone
    prof = [(0.0, -0.0745), (0.0195, -0.0745), (0.0218, -0.0715), (0.0226, -0.066), (0.0226, -0.004), (0.0218, -0.0015),
            (0.0213, 0.0), (0.0219, 0.0015), (0.0226, 0.004), (0.0226, 0.012), (0.0205, 0.026), (0.016, 0.039), (0.0125, 0.0465),
            (0.0118, 0.052), (0.0112, 0.055)]
    g += _along_y(lathe(prof, body, segs=48, smooth_angle=28)).translate(0, 0, zb)
    # rubber rear cap with grip ribs + red accent ring
    g += _along_y(lathe([(0.0, -0.0835), (0.012, -0.083), (0.0185, -0.080), (0.0212, -0.076), (0.0216, -0.0705)], ribs, segs=48,
                        smooth_angle=40)).translate(0, 0, zb)
    g += _along_y(cylinder(0.0229, 0.0045, red, segs=48, bevel=0.0008, bevel_seg=1, z0=-0.0725)).translate(0, 0, zb)
    # nose: rubber bumper ring + chuck + magnetic hex driver
    g += _along_y(lathe([(0.0118, 0.0465), (0.0131, 0.047), (0.0134, 0.050), (0.0128, 0.0535), (0.0113, 0.0545)], rub, segs=40,
                        smooth_angle=50)).translate(0, 0, zb)
    g += _along_y(cylinder(0.0080, 0.007, chrome, segs=32, bevel=0.0012, caps=(False, True), z0=0.055)).translate(0, 0, zb)
    g += _hex_prism(0.0046, 0.0065, steel, z0=0.0615).rotate(-90, 0, 0).translate(0, 0, zb)
    # pistol grip core (side profile extruded along X) + rubber overmould panels on both sides
    poly = np.array([(-0.047, 0.040), (-0.052, 0.0), (-0.046, -0.048), (-0.038, -0.058), (-0.004, -0.058),
                     (0.004, -0.050), (0.010, -0.004), (0.020, 0.040)])
    grip = extrude(poly, 0.034, body, bevel=0.008, bevel_seg=3, smooth_angle=50, tag="grip")
    grip.transform(YZ_FROM_XY).translate(-0.017, 0, 0)
    g += grip
    pad = np.array([(-0.039, -0.045), (-0.008, -0.047), (-0.002, -0.041), (0.004, -0.006), (0.008, 0.016), (-0.035, 0.018),
                    (-0.041, 0.0)])
    for sx in (-1, 1):
        p = extrude(pad, 0.0032, rub, bevel=0.0012, bevel_seg=2, smooth_angle=50, tag="overmould")
        p.transform(YZ_FROM_XY)
        if sx < 0:
            p.mirror("x")
            p.translate(-0.0155, 0, 0)
        else:
            p.translate(0.0155, 0, 0)
        g += p
    # finger rest ridge under the trigger
    g += box((0.030, 0.006, 0.004), rub, r=0.0018, seg=2, center=(0, 0.0055, -0.009))
    # battery base: sealed pack with a split line, red lanyard loop
    g += box((0.032, 0.040, 0.010), body, r=0.004, seg=2, center=(0, -0.021, -0.0605))
    g += box((0.034, 0.042, 0.003), rub, r=0.0012, seg=1, center=(0, -0.021, -0.0665))
    loop = catmull([(0, -0.044, -0.060), (0, -0.050, -0.061), (0, -0.0515, -0.066), (0, -0.047, -0.068), (0, -0.041, -0.066)], n=4)
    g += tube(loop, 0.0016, red, segs=8, tag="lanyard")
    # trigger: red rocker with grip ribs
    trig = extrude(rrect(0.011, 0.030, 0.005, 3), 0.016, red, bevel=0.003, bevel_seg=2)
    trig.transform(YZ_FROM_XY).translate(-0.008, 0.0145, 0.012)
    g += trig
    if detail:
        # battery gauge window with 3 LEDs on the top rear of the housing + test button
        g += box((0.011, 0.024, 0.0024), window, r=0.0011, seg=2, center=(0, -0.050, zb + 0.0213))
        led = m_led(b, "gauge_led", (80, 255, 120))
        for k in range(3):
            g += box((0.0032, 0.0042, 0.0008), led, r=0.0003, seg=1, center=(0, -0.0585 + k * 0.0062, zb + 0.0227))
        g += cylinder(0.0034, 0.0018, rub, segs=16, bevel=0.0006, bevel_seg=1, z0=zb + 0.0205).translate(0, -0.030, 0)
        # clamshell screws on the -X side
        a = math.radians(-32)
        for y in (-0.064, -0.022, 0.012):
            g += screw(b, (-0.0222 * math.cos(a), y, zb + 0.0222 * math.sin(a)), (-math.cos(a), 0, math.sin(a)), d=0.0042, segs=10)
        for y, z in ((-0.046, -0.050), (0.0, -0.050)):
            g += screw(b, (-0.0168, y, z), (-1, 0, 0), d=0.0036, segs=10)
    return g


def io_needle_geo(b):
    """25 mm IO needle set (blue hub) on the driver chuck, tip at y = 0.1075."""
    _, _, _, _, hub, _ = _io_mats(b)
    steel = m_steel(b)
    ink = b.mat("depth_mark", color=(20, 21, 23), spec=0.3, gloss=0.5)
    g = Geo()
    g += lathe([(0.0, 0.068), (0.0064, 0.068), (0.0066, 0.0695), (0.0066, 0.0725), (0.0050, 0.0745), (0.0046, 0.080),
                (0.0032, 0.0815), (0.0, 0.0815)], hub, segs=28, smooth_angle=40)
    g += lathe([(0.0, 0.0815), (0.00092, 0.0815), (0.00092, 0.1035), (0.00055, 0.1065), (0.0, 0.1075)], steel, segs=12,
               smooth_angle=60)
    for k in range(3):
        g += cylinder(0.00098, 0.0007, ink, segs=10, caps=(False, False), z0=0.086 + k * 0.005)
    return _along_y(g).translate(0, 0, IO_ZB)


@prop("nz_amb_iodrill", atlas=1024, lod=45, hd=8, doc={
    "title": "Intraosseous (IO) driver",
    "origin": "centre of the pistol grip (where the palm wraps)",
    "axes": "+Y = needle direction, +Z = up over the grip, body on top",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) needle forward; SKEL_R_Hand (57005) pos (0.10, 0.02, -0.02) rot (-90, 0, 0)",
})
def iodrill(b):
    b.add(iodrill_geo(b), io_needle_geo(b))
    zb = IO_ZB
    # clamshell split line along the top and bottom of the housing + seam around the nose step
    seam = DecalCanvas(0.03, 0.16, ppm=9000)
    seam.groove([(0.015, 0.0), (0.015, 0.16)], width=0.00035, depth=0.00012)
    for sz in (1, -1):
        b.decal(seam, center=(0, -0.012, zb + sz * 0.0226), normal=(0, 0, sz), up=(0, sz, 0), mats=["drill_body"], depth=0.004, min_dot=0.6)
    gs = DecalCanvas(0.03, 0.12, ppm=9000)
    gs.groove([(0.015, 0.0), (0.015, 0.12)], width=0.00035, depth=0.00012)
    b.decal(gs, center=(0, 0.017, -0.02), normal=(0, 1, 0.25), up=(0, 0, 1), mats=["drill_body"], depth=0.006, min_dot=0.3)
    b.decal(gs, center=(0, -0.05, -0.01), normal=(0, -1, 0), up=(0, 0, 1), mats=["drill_body"], depth=0.006, min_dot=0.3)
    # motor vent slots on both sides of the rear housing
    vent = DecalCanvas(0.022, 0.016, ppm=9000)
    vent.slots(0.002, 0.002, 0.018, 0.012, 5, vertical=True, fill=0.38, depth=0.0006)
    for sx in (1, -1):
        b.decal(vent, center=(sx * 0.0226, -0.046, zb), normal=(sx, 0, 0), up=(0, 0, 1), mats=["drill_body"], depth=0.005)
    # side print (+X): symbol + device name; (-X): model, needle sizes
    lab = label_canvas(0.060, 0.012, "IO DRIVER", "IO-3  ·  POWERED", ppm=12000, color=INK, sub_color=(160, 30, 34))
    b.decal(lab, center=(0.0226, -0.010, zb + 0.004), normal=(1, 0, 0), up=(0, 0, 1), mats=["drill_body"], depth=0.006)
    side = DecalCanvas(0.050, 0.014, ppm=12000)
    side.text(0.0, 0.0035, "NEEDLE SETS", 0.0018, fnt="label", anchor="lm", color=INK, spacing=0.0002)
    for k, (t, c) in enumerate((("15 mm", (214, 70, 140)), ("25 mm", (36, 104, 196)), ("45 mm", (232, 190, 30)))):
        side.rect(k * 0.0165, 0.0065, 0.004, 0.004, r=0.0008, color=c)
        side.text(k * 0.0165 + 0.005, 0.0085, t, 0.0022, fnt="label-semi", anchor="lm", color=INK)
    side.text(0.0, 0.0128, "SINGLE PATIENT NEEDLES ONLY", 0.0013, fnt="label-semi", anchor="lm", color=(90, 94, 98))
    b.decal(side, center=(-0.0226, -0.008, zb + 0.0055), normal=(-1, 0, 0), up=(0, 0, 1), mats=["drill_body"], depth=0.006)
    # gauge legend on top
    top = DecalCanvas(0.018, 0.034, ppm=12000)
    top.text(0.009, 0.003, "BATTERY", 0.0016, fnt="label", color=INK, spacing=0.0002)
    top.text(0.009, 0.0315, "TEST", 0.0016, fnt="label", color=INK)
    top.icon("warn", 0.0005, 0.0005, 0.0045, color=INK)
    b.decal(top, center=(0, -0.042, zb + 0.0226), normal=(0, 0, 1), up=(0, -1, 0), mats=["drill_body"], depth=0.003, min_dot=0.6)
    # rating plate under the battery base, caution on the back of the grip
    b.decal(rating_plate(0.036, 0.028, "IO DRIVER", "IO-3", "SN 26-30417", rating="3.0 V  Li-MnO2  sealed", ppm=14000,
                         icons=("factory", "book", "bf", "bin")),
            center=(0, -0.021, -0.0682), normal=(0, 0, -1), up=(0, 1, 0), mats=["drill_rubber"], depth=0.003)
    b.decal(caution_label(0.026, 0.016, "CAUTION", ["Do not reuse needle sets", "Sterile only when sealed"], ppm=14000),
            center=(0, -0.0525, -0.014), normal=(0, -1, 0), up=(0, 0, 1), mats=["drill_body"], depth=0.008, min_dot=0.4)
    # needle hub print
    hub = DecalCanvas(0.010, 0.012, ppm=16000)
    hub.text(0.005, 0.006, "25", 0.0032, fnt="label", color=(240, 244, 248), rotate=0)
    b.decal(hub, center=(0, 0.071, IO_ZB + 0.0066), normal=(0, 0, 1), up=(0, 1, 0), mats=["io_hub_blue"], depth=0.002, min_dot=0.5)
    b.col_box((-0.024, -0.082, -0.066), (0.024, 0.108, 0.072), "PLASTIC_HIGH_DENSITY")


# =============================================================================================
# syringe 10 ml
# =============================================================================================
def syringe_geo(b, fill=0.55, cap=False):
    clear = b.mat("syringe_clear", color=(232, 238, 240), spec=0.9, gloss=0.92, alpha=0.18, layer="alpha", grain=0.0, scratch=0.12)
    fluid = b.mat("syringe_fluid", color=(214, 232, 236), spec=0.7, gloss=0.9, alpha=0.22, layer="alpha", grain=0.0, scratch=0.0)
    plunger = b.mat("plunger", color=(238, 240, 241), spec=0.35, gloss=0.5, bump="orange_peel", bump_amp=0.00001, bump_scale=0.001,
                    edge=0.25, wear=0.1)
    stopper = b.mat("stopper", color=(26, 27, 29), spec=0.3, gloss=0.4, bump="rubber", bump_amp=0.00002, bump_scale=0.0004, edge=0.2)
    hub = b.mat("hub_green", color=(28, 150, 84), spec=0.45, gloss=0.65, bump="ribs_u", bump_amp=0.00004, bump_scale=0.0008, edge=0.3)
    luer = b.mat("luer_white", color=(242, 244, 244), spec=0.4, gloss=0.6, bump="ribs", bump_amp=0.00003, bump_scale=0.0007, edge=0.25)
    steel = m_steel(b)
    g = Geo()
    Ro, L = 0.0080, 0.074
    barrel = [(0.0063, 0.0), (Ro, 0.0), (Ro, L - 0.004), (Ro - 0.0015, L), (0.0024, L + 0.0015), (0.0021, L + 0.010), (0.0, L + 0.0105)]
    g += _along_y(lathe(barrel, clear, segs=40, smooth_angle=35))
    # finger flange with a thin rim
    fl = extrude(rrect(0.034, 0.015, 0.0065, 6), 0.0022, clear, bevel=0.0006, bevel_seg=1)
    g += fl.rotate(-90, 0, 0).translate(0, -0.0011, 0)
    # stopper (three sealing ribs) + fluid column
    ys = 0.006 + (1.0 - fill) * (L - 0.012)
    g += _along_y(lathe([(0.0, ys), (0.0070, ys), (0.0075, ys + 0.0012), (0.0068, ys + 0.0026), (0.0075, ys + 0.0040),
                         (0.0068, ys + 0.0054), (0.0075, ys + 0.0066), (0.0071, ys + 0.0078), (0.0035, ys + 0.0090), (0.0, ys + 0.0092)],
                        stopper, segs=32, smooth_angle=40))
    if fill > 0.02:
        g += _along_y(cylinder(0.0073, L - 0.0015 - (ys + 0.0075), fluid, segs=32, z0=ys + 0.0075))
    # plunger rod (cross with a stiffening disc) + thumb press with rings
    rod_y0, rod_y1 = -0.035 + (1.0 - fill) * (L - 0.012), ys
    for rot in (0, 90):
        g += box((0.0105, rod_y1 - rod_y0, 0.0012), plunger, r=0.0003, seg=1, center=(0, (rod_y0 + rod_y1) / 2, 0)).rotate(0, rot, 0)
    g += _along_y(cylinder(0.0062, 0.0011, plunger, segs=24, bevel=0.0003, bevel_seg=1, z0=rod_y1 - 0.0012))
    g += _along_y(lathe([(0.0, rod_y0 - 0.0024), (0.0084, rod_y0 - 0.0024), (0.0090, rod_y0 - 0.0016), (0.0090, rod_y0 - 0.0006),
                         (0.0082, rod_y0), (0.0, rod_y0)], plunger, segs=36, smooth_angle=40))
    # luer-lock collar (threaded inside) + coloured needle hub + needle (or cap)
    g += _along_y(lathe([(0.0042, L + 0.001), (0.0052, L + 0.0015), (0.0052, L + 0.0085), (0.0046, L + 0.009), (0.0042, L + 0.009)],
                        luer, segs=28, smooth_angle=40))
    g += _along_y(lathe([(0.0, L + 0.009), (0.0038, L + 0.009), (0.0038, L + 0.0105), (0.0031, L + 0.011), (0.0031, L + 0.015),
                         (0.0026, L + 0.019), (0.0012, L + 0.0205), (0.0, L + 0.0205)], hub, segs=24, smooth_angle=40))
    if cap:
        g += _along_y(lathe([(0.0, L + 0.0195), (0.0035, L + 0.0195), (0.0035, L + 0.024), (0.0031, L + 0.046), (0.0026, L + 0.049),
                             (0.0, L + 0.0495)], hub, segs=20, smooth_angle=40))
    else:
        g += _along_y(lathe([(0.0, L + 0.020), (0.00045, L + 0.020), (0.00045, L + 0.0455), (0.00018, L + 0.0475), (0.0, L + 0.0485)],
                            steel, segs=8, smooth_angle=60))
    return g


def syringe_scale(length=0.074):
    dc = DecalCanvas(0.016, length, ppm=12000)
    ink = (20, 22, 24)
    for k in range(0, 21):
        y = length - 0.006 - k * (length - 0.012) / 20
        major = k % 4 == 0
        mid = k % 2 == 0
        dc.rect(0.0, y - 0.0001, 0.0045 if major else (0.0032 if mid else 0.0022), 0.0002, color=ink)
        if major and k > 0:
            dc.text(0.0058, y, str(k // 2), 0.0013, fnt="label-semi", anchor="lm", color=ink)
    dc.text(0.0058, length - 0.0035, "mL", 0.0011, fnt="label-semi", anchor="lm", color=ink)
    dc.text(0.0125, length * 0.5, "10 mL  LUER LOCK  STERILE  LOT 26C14", 0.00085, fnt="label-semi", color=(60, 64, 68), rotate=90)
    return dc


@prop("nz_amb_syringe", atlas=512, alpha_atlas=512, lod=30, hd=5, doc={
    "title": "10 mL syringe with needle",
    "origin": "finger flange (barrel back end)",
    "axes": "+Y = needle direction; flange wings along X",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, -90) or SKEL_R_Hand (57005) pos (0.09, 0.03, -0.01) rot (-80, 0, 0)",
})
def syringe(b):
    b.add(syringe_geo(b, fill=0.55))
    b.decal(syringe_scale(), center=(0.0, 0.037, 0.008), normal=(0, 0, 1), up=(0, 1, 0), mats=["syringe_clear"], depth=0.006, min_dot=0.3)
    gauge = DecalCanvas(0.006, 0.008, ppm=20000)
    gauge.text(0.003, 0.004, "21G", 0.0016, fnt="label", color=(240, 248, 244))
    b.decal(gauge, center=(0.0, 0.0875, 0.0031), normal=(0, 0, 1), up=(0, 1, 0), mats=["hub_green"], depth=0.002, min_dot=0.5)
    b.col_box((-0.017, -0.04, -0.009), (0.017, 0.123, 0.009), "PLASTIC")


# =============================================================================================
# laryngoscope (Macintosh blade, open)
# =============================================================================================
@prop("nz_amb_laryngoscope", atlas=1024, lod=35, hd=6, doc={
    "title": "Laryngoscope (Macintosh blade, open / light on)",
    "origin": "centre of the handle",
    "axes": "handle along Z (top = +Z), blade points +Y and curves down",
    "attach": "PH_L_Hand (60309) pos (0.0, 0.0, 0.0) rot (0, 0, 0); SKEL_L_Hand (18905) pos (0.08, 0.02, 0.0) rot (0, 90, 0)",
})
def laryngoscope(b):
    knurl = b.mat("knurl_steel", color=(150, 154, 160), spec=0.8, gloss=0.6, metal=1.0, bump="knurl", bump_amp=0.00018,
                  bump_scale=0.0016, grain=0.02, edge=0.3, dirt=0.2)
    chrome = m_chrome(b)
    satin = b.mat("satin_steel", color=(170, 174, 180), spec=0.8, gloss=0.66, metal=1.0, bump="brushed", bump_amp=0.000008,
                  bump_scale=0.0004, grain=0.02, edge=0.3, dirt=0.12)
    capk = b.mat("cap_knurl", color=(140, 144, 150), spec=0.75, gloss=0.55, metal=1.0, bump="ribs_u", bump_amp=0.00012,
                 bump_scale=0.0011, edge=0.4, dirt=0.25)
    oring = b.mat("o_ring", color=(20, 21, 23), spec=0.3, gloss=0.5, edge=0.1)
    band = b.mat("band_green", color=(30, 150, 80), spec=0.45, gloss=0.6, edge=0.4)   # green band = LED / fibre-optic standard
    fibre = b.mat("fibre", color=(210, 214, 218), spec=0.7, gloss=0.75, metal=0.6, edge=0.2)
    lamp = m_led(b, "lamp", (255, 248, 225))
    # handle: knurled grip between plain satin collars; screw-off battery end cap with knurled ring + O-ring
    b.add(lathe([(0.0, -0.0725), (0.0098, -0.0722), (0.0122, -0.0712), (0.0132, -0.0695), (0.0134, -0.066)], capk, segs=40, smooth_angle=35))
    b.add(cylinder(0.0134, 0.0055, capk, segs=40, caps=(False, False), z0=-0.066))
    b.add(lathe([(0.0134, -0.0605), (0.0129, -0.060), (0.0129, -0.0585), (0.0140, -0.058)], satin, segs=40, smooth_angle=40))
    b.add(torus(0.01315, 0.0006, oring, segs=40, tube_segs=6).translate(0, 0, -0.0603))
    b.add(cylinder(0.0140, 0.010, satin, segs=40, caps=(False, False), z0=-0.058))
    b.add(cylinder(0.0140, 0.088, knurl, segs=40, caps=(False, False), z0=-0.048))
    b.add(cylinder(0.0141, 0.008, satin, segs=40, caps=(False, False), z0=0.040))
    b.add(cylinder(0.0143, 0.005, band, segs=40, caps=(False, False), z0=0.048))
    b.add(lathe([(0.0141, 0.053), (0.0141, 0.060), (0.0128, 0.0645), (0.0105, 0.066), (0.0, 0.066)], chrome, segs=40, smooth_angle=35))
    # hook-on hinge block with the hinge pin, spring detent ball and the contact
    b.add(box((0.020, 0.026, 0.016), chrome, r=0.004, seg=2, center=(0, 0.004, 0.073)))
    b.add(cylinder(0.0035, 0.024, satin, segs=16, bevel=0.001, z0=-0.012).rotate(0, 90, 0).translate(0, 0.004, 0.075))
    for sx in (-1, 1):
        b.add(cylinder(0.0042, 0.0012, chrome, segs=16, bevel=0.0004, bevel_seg=1, z0=0.0).rotate(0, 90 * sx, 0)
              .translate(sx * 0.0121, 0.004, 0.075))
    b.add(sphere(0.0018, chrome, segs=10, rings=6).translate(0, -0.0092, 0.072))
    b.add(box((0.008, 0.004, 0.004), fibre, r=0.001, seg=1, center=(0, 0.017, 0.0705)))
    # blade: curved spatula + flange + bulbous tip
    path = catmull([(0, 0.012, 0.079), (0, 0.045, 0.080), (0, 0.08, 0.073), (0, 0.112, 0.058), (0, 0.128, 0.046)], n=10)
    b.add(sweep(rrect(0.019, 0.0022, 0.0009, 2), path, satin, side=(1, 0, 0), tag="blade", smooth_angle=50))
    flange = path.copy()
    flange[:, 0] = -0.0085
    flange[:, 2] += 0.006
    b.add(sweep(rrect(0.0022, 0.012, 0.0009, 2), flange[:-8], satin, side=(1, 0, 0), tag="flange", smooth_angle=50))
    b.add(sphere(0.0025, satin, segs=14, rings=7).scale(3.6, 1.0, 1.0).translate(0, 0.1295, 0.0455))
    # fibre-optic light guide under the blade, ending in the lamp window
    lg = catmull([(0.0058, 0.016, 0.0742), (0.0058, 0.045, 0.0752), (0.0058, 0.075, 0.0700), (0.0058, 0.0895, 0.0640)], n=8)
    b.add(tube(lg, 0.0016, fibre, segs=10, tag="lightguide"))
    b.add(cylinder(0.0030, 0.0035, chrome, segs=16, z0=0.0).rotate(-60, 0, 0).translate(0.0058, 0.0885, 0.0650))
    b.add(sphere(0.0024, lamp, segs=12, rings=6).translate(0.0058, 0.0915, 0.0632))
    # engraved print: handle (debossed through the knurl), blade size stamp
    lab = DecalCanvas(0.032, 0.07, ppm=9000)
    lab.rect(0.010, 0.006, 0.012, 0.058, r=0.002, color=(170, 174, 180), height=0.00012, spec=0.8, gloss=0.66, metal=1.0)
    lab.text(0.016, 0.035, "LED  2.5 V  ·  LS-30", 0.0028, fnt="label", color=(40, 42, 46), spacing=0.0004, rotate=90, height=-0.00006)
    b.decal(lab, center=(0.0141, 0.0, -0.004), normal=(1, 0, 0), up=(0, 0, 1), mats=["knurl_steel"], depth=0.006)
    lab2 = DecalCanvas(0.032, 0.07, ppm=9000)
    lab2.rect(0.010, 0.006, 0.012, 0.058, r=0.002, color=(170, 174, 180), height=0.00012, spec=0.8, gloss=0.66, metal=1.0)
    lab2.text(0.016, 0.035, "REF 30-2   SN 1180", 0.0024, fnt="mono-bold", color=(40, 42, 46), rotate=90, height=-0.00006)
    b.decal(lab2, center=(-0.0141, 0.0, -0.004), normal=(-1, 0, 0), up=(0, 0, 1), mats=["knurl_steel"], depth=0.006)
    st = DecalCanvas(0.016, 0.03, ppm=14000)
    st.text(0.008, 0.008, "MAC 3", 0.0026, fnt="label", color=(70, 74, 80), height=-0.00005, rotate=90)
    st.text(0.008, 0.022, "STAINLESS", 0.0014, fnt="label-semi", color=(90, 94, 100), height=-0.00004, rotate=90)
    b.decal(st, center=(0.0, 0.045, 0.0815), normal=(0, 0, 1), up=(0, 1, 0), mats=["satin_steel"], depth=0.003, min_dot=0.6)
    b.col_cyl((0, 0, -0.003), 0.0145, 0.138, axis="z", material="METAL_SOLID_SMALL")
    b.col_box((-0.011, 0.0, 0.04), (0.011, 0.132, 0.084), "METAL_SOLID_SMALL")


# =============================================================================================
# ultrasound probe (convex)
# =============================================================================================
@prop("nz_amb_us_probe", atlas=1024, lod=35, hd=6, doc={
    "title": "Ultrasound probe (convex) with cable stub",
    "origin": "centre of the grip",
    "axes": "lens points -Z, cable exits +Z; orientation marker on +X",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (180, 0, 0) lens down; SKEL_R_Hand (57005) pos (0.08, 0.03, -0.02) rot (90, 0, 0)",
})
def us_probe(b):
    shell = b.mat("probe_shell", color=(226, 229, 231), spec=0.38, gloss=0.58, bump="orange_peel", bump_amp=0.000015,
                  bump_scale=0.0018, grain=0.02, grain_scale=0.05, edge=0.35, dirt=0.25, wear_color=(240, 242, 242))
    grip = b.mat("probe_grip", color=(70, 76, 84), spec=0.2, gloss=0.3, bump="ribs", bump_amp=0.00012, bump_scale=0.0018,
                 edge=0.3, dirt=0.2)
    lens = b.mat("lens", color=(38, 40, 44), spec=0.42, gloss=0.6, bump="stipple", bump_amp=0.00001, bump_scale=0.0003, edge=0.2)
    nose = b.mat("nose_ring", color=(54, 58, 64), spec=0.3, gloss=0.45, edge=0.4)
    cable = b.mat("cable", color=(52, 55, 60), spec=0.28, gloss=0.45, edge=0.1, dirt=0.15)
    mark = b.mat("marker", color=(40, 160, 220), spec=0.5, gloss=0.65, edge=0.2)
    rub = m_rubber(b)
    zs = np.linspace(-0.055, 0.062, 28)
    sx = np.interp(zs, [-0.055, -0.035, -0.012, 0.02, 0.05, 0.062], [1.25, 1.18, 0.82, 0.74, 0.62, 0.42])
    sy = np.interp(zs, [-0.055, -0.035, -0.012, 0.02, 0.05, 0.062], [0.95, 0.95, 0.86, 0.84, 0.76, 0.52])
    path = np.stack([np.zeros_like(zs), np.zeros_like(zs), zs], axis=1)
    prof = rrect(0.043, 0.025, 0.0095, 6)
    b.add(sweep(prof, path, shell, scale=np.stack([sx, sy], axis=1), side=(1, 0, 0), tag="body", smooth_angle=60))
    # ribbed soft grip band around the waist + raised orientation marker
    b.add(sweep(rrect(0.0436, 0.0256, 0.0097, 6), np.array([[0, 0, -0.008], [0, 0, 0.010]]), grip,
                scale=np.array([[0.835, 0.866], [0.762, 0.852]]), side=(1, 0, 0), caps=False, tag="band"))
    b.add(sphere(0.0024, mark, segs=12, rings=6).scale(1.0, 1.0, 1.6).translate(0.0270, 0, -0.040))
    # nose ring framing the convex lens
    R, c = 0.0518, 0.0255
    half = math.degrees(math.asin(c / R))
    th = np.radians(np.linspace(-90 - half, -90 + half, 28))
    zc = -0.0092
    lensp = [(R * math.cos(t), zc + R * math.sin(t)) for t in th] + [(c, -0.049), (-c, -0.049)]
    b.add(sweep(np.array(lensp), np.array([[0, -0.0105, 0], [0, 0.0105, 0]]), lens, side=(1, 0, 0), tag="lens", smooth_angle=30))
    ring = [((R + 0.0012) * math.cos(t), zc + (R + 0.0012) * math.sin(t)) for t in th]
    for sy_ in (-1, 1):
        rp = np.array([(x, sy_ * 0.0112, z) for x, z in ring])
        b.add(tube(rp, 0.0011, nose, segs=8, tag="nose"))
    # ribbed strain relief + cable stub
    b.add(strain_relief(b, (0, 0, 0.056), (0, 0, 1), length=0.042, r0=0.0092, r1=0.0046, rings=8, mat=rub, segs=20))
    cab = catmull([(0, 0, 0.097), (0, 0, 0.118), (0.012, 0.006, 0.138), (0.04, 0.012, 0.148), (0.07, 0.008, 0.14)], n=8)
    b.add(tube(cab, 0.0036, cable, segs=14))
    # shell split line around the sides, print, serial
    seam = DecalCanvas(0.02, 0.13, ppm=7000)
    seam.groove([(0.01, 0.0), (0.01, 0.13)], width=0.0004, depth=0.00012)
    for sxn in (1, -1):
        b.decal(seam, center=(sxn * 0.027, 0, 0.0), normal=(sxn, 0, 0), up=(0, 0, 1), mats=["probe_shell"], depth=0.008, min_dot=0.5)
    lab = DecalCanvas(0.03, 0.05, ppm=9000)
    lab.text(0.015, 0.012, "C5-2", 0.0052, fnt="label", color=(34, 36, 40), spacing=0.0006)
    lab.text(0.015, 0.020, "CONVEX ARRAY", 0.0021, fnt="label-semi", color=(70, 74, 80), spacing=0.0003)
    lab.text(0.015, 0.0255, "2 - 5 MHz", 0.0021, fnt="label-semi", color=(40, 140, 200))
    lab.icon("bf", 0.006, 0.033, 0.006, color=(60, 64, 70))
    lab.icon("drop", 0.018, 0.033, 0.006, color=(60, 64, 70))
    b.decal(lab, center=(0, 0.0122, 0.020), normal=(0, 1, 0), up=(0, 0, 1), mats=["probe_shell"], depth=0.01)
    back = DecalCanvas(0.03, 0.03, ppm=9000)
    back.text(0.015, 0.006, "SN 26-55102", 0.0021, fnt="mono-bold", color=(50, 54, 58))
    back.text(0.015, 0.011, "REF C52-3", 0.0019, fnt="mono", color=(80, 84, 88))
    back.datamatrix(0.0105, 0.015, 0.009, n=12, seed=17)
    b.decal(back, center=(0, -0.0122, 0.022), normal=(0, -1, 0), up=(0, 0, 1), mats=["probe_shell"], depth=0.01)
    b.col_box((-0.034, -0.016, -0.06), (0.034, 0.016, 0.1), "PLASTIC")


# =============================================================================================
# stethoscope (coiled, lying flat)
# =============================================================================================
@prop("nz_amb_stethoscope", atlas=1024, lod=35, hd=6, doc={
    "title": "Stethoscope, coiled",
    "origin": "bottom centre (lying flat)",
    "axes": "flat on the XY plane, chest piece at +X, ear pieces at -X",
    "attach": "neck: SKEL_Neck_1 (39317) needs a draped variant - use this model on surfaces / in hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.0)",
})
def stethoscope(b):
    tubing = b.mat("steth_tube", color=(22, 74, 120), spec=0.34, gloss=0.55, bump="rubber", bump_amp=0.000015, bump_scale=0.0008,
                   edge=0.2, dirt=0.15, smudge=0.6)
    chrome = m_chrome(b)
    satin = b.mat("satin_steel", color=(176, 180, 186), spec=0.8, gloss=0.66, metal=1.0, bump="brushed", bump_amp=0.000006,
                  bump_scale=0.0004, edge=0.25)
    rimk = b.mat("rim_knurl", color=(168, 172, 178), spec=0.78, gloss=0.6, metal=1.0, bump="ribs_u", bump_amp=0.00008,
                 bump_scale=0.0009, edge=0.3)
    diaph = b.mat("diaphragm", color=(232, 234, 236), spec=0.45, gloss=0.62, edge=0.1, scratch=0.15)
    chill = b.mat("chill_ring", color=(30, 31, 34), spec=0.2, gloss=0.3, bump="rubber", bump_amp=0.00002, bump_scale=0.0005)
    tip = b.mat("ear_tip", color=(30, 31, 34), spec=0.18, gloss=0.3, bump="rubber", bump_amp=0.00002, bump_scale=0.0005, edge=0.1)
    idring = b.mat("id_ring", color=(220, 60, 50), spec=0.4, gloss=0.55, edge=0.3)
    r = 0.0045
    # dual-head chest piece lying flat, diaphragm up: knurled retaining rim, non-chill ring, stem with index mark
    cx, cy = 0.085, -0.03
    b.add(lathe([(0.0, 0.0), (0.016, 0.0), (0.0205, 0.0012), (0.0225, 0.003)], satin, segs=56, smooth_angle=30).translate(cx, cy, 0))
    b.add(cylinder(0.0236, 0.0016, chill, segs=56, caps=(False, False), z0=0.003).translate(cx, cy, 0))
    b.add(lathe([(0.0225, 0.0046), (0.0236, 0.0050), (0.0236, 0.0082), (0.0222, 0.0098), (0.0198, 0.0101)], rimk, segs=56,
                smooth_angle=30).translate(cx, cy, 0))
    b.add(lathe([(0.0198, 0.0101), (0.0193, 0.0096), (0.0, 0.0096)], diaph, segs=56, smooth_angle=60).translate(cx, cy, 0))
    b.add(cylinder(0.0034, 0.022, satin, segs=16, bevel=0.0008).rotate(0, -90, 0).translate(cx - 0.0225, cy, 0.0048))
    b.add(cylinder(0.0044, 0.006, chrome, segs=16, bevel=0.001).rotate(0, -90, 0).translate(cx - 0.034, cy, 0.0048))
    # coiled tubing from the stem to the Y split, ID ring
    pts = [(cx - 0.044, cy, r), (cx - 0.075, cy + 0.01, r), (0.0, 0.035, r), (-0.05, 0.055, r), (-0.085, 0.02, r),
           (-0.07, -0.035, r), (-0.01, -0.06, r * 2.4), (0.04, -0.035, r * 2.6), (0.045, 0.02, r), (0.02, 0.07, r),
           (-0.04, 0.085, r), (-0.09, 0.07, r), (-0.11, 0.035, r)]
    path = catmull(pts, n=8)
    b.add(tube(path, r, tubing, segs=16, split=0.25, tag="tube"))
    k_id = 14
    d_id = path[k_id + 1] - path[k_id - 1]
    b.add(align(cylinder(r * 1.18, 0.006, idring, segs=16, bevel=0.0008, bevel_seg=1, z0=-0.003), d_id, (0, 0, 1), path[k_id]))
    # Y yoke (metal), binaurals with a leaf spring, soft ear tips
    y0 = np.array([-0.11, 0.035, r])
    b.add(sphere(0.0062, satin, segs=16, rings=8).scale(1.3, 1.0, 0.75).translate(*y0))
    for sgn in (1, -1):
        br = catmull([tuple(y0), (-0.125, 0.035 + sgn * 0.012, r), (-0.135, 0.035 + sgn * 0.03, r), (-0.13, 0.035 + sgn * 0.05, 0.0028)], n=6)
        b.add(tube(br, 0.0037, tubing, segs=12))
        b.add(align(cylinder(0.0041, 0.006, satin, segs=14, bevel=0.0008, bevel_seg=1, z0=-0.003), (0.005, sgn * 0.02, 0),
                    (0, 0, 1), (-0.1315, 0.035 + sgn * 0.043, 0.0034)))
        bin_ = catmull([(-0.13, 0.035 + sgn * 0.05, 0.0028), (-0.12, 0.035 + sgn * 0.065, 0.0025), (-0.085, 0.035 + sgn * 0.08, 0.0022),
                        (-0.055, 0.035 + sgn * 0.075, 0.0022)], n=8)
        b.add(tube(bin_, 0.0019, chrome, segs=12))
        b.add(lathe([(0.0, 0.0), (0.0042, 0.0), (0.0052, 0.004), (0.0053, 0.006), (0.0045, 0.009), (0.0025, 0.0105), (0.0, 0.0105)], tip,
                    segs=18, smooth_angle=40).rotate(0, 90, 0).translate(-0.055, 0.035 + sgn * 0.075, 0.0022))
    spring = np.array([[-0.118, 0.035 - 0.064, 0.0025], [-0.118, 0.035 + 0.064, 0.0025]])
    b.add(sweep(rrect(0.0042, 0.0012, 0.0004, 1), spring, satin, up=(0, 0, 1), tag="spring"))
    # diaphragm print + rim engraving
    dd = DecalCanvas(0.04, 0.04, ppm=12000)
    for rr in (0.0055, 0.0115, 0.0172):
        dd.circle(0.02, 0.02, rr, fill=False, width=0.0003, color=(200, 202, 206), height=0.00004)
    dd.text(0.02, 0.0135, "ADULT", 0.0022, fnt="label", color=(120, 124, 130), spacing=0.0004)
    dd.text(0.02, 0.0275, "DUAL HEAD", 0.0016, fnt="label-semi", color=(140, 144, 150), spacing=0.0002)
    b.decal(dd, center=(cx, cy, 0.0097), normal=(0, 0, 1), up=(0, 1, 0), mats=["diaphragm"], depth=0.002)
    b.col_box((-0.14, -0.07, 0.0), (0.11, 0.12, 0.012), "RUBBER")
