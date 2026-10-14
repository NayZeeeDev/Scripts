"""
Fluids: tripod IV stand, 500 mL saline bag, blood bags (5 fill levels), pressure infuser.
Bags have their origin at the hanging slot so they attach straight to the stand's hooks.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL_HI, DecalCanvas, Geo, box, catmull, cylinder, lathe, pillow, polyline_fillet, prop,
                     register, rrect, sphere, sweep, torus, tube)

from .common import align, m_black_plastic, m_chrome, m_rubber, m_teal, m_white_plastic

HOOK_X = 0.073
HOOK_Z = 1.766


# =============================================================================================
# tripod IV stand
# =============================================================================================
@prop("nz_amb_ivstand", atlas=512, lod=140, hd=20, static=True, doc={
    "title": "Tripod IV stand, 1.8 m, two hooks",
    "origin": "ground centre (pole axis)",
    "axes": "pole along +Z, hooks on +X and -X, one leg points +Y",
    "attach": f"bags: attach the bag (origin = its hanging slot) to the stand entity at ({HOOK_X}, 0, {HOOK_Z}) or (-{HOOK_X}, 0, {HOOK_Z}) rot (0, 0, 0); "
              "the stand itself can be attached to the stretcher entity at its head end",
})
def ivstand(b):
    chrome = m_chrome(b)
    blk = m_black_plastic(b)
    rub = m_rubber(b)
    teal = m_teal(b)
    b.add(cylinder(0.0125, 0.92, chrome, segs=20, caps=(False, False), z0=0.10))
    b.add(cylinder(0.0095, 0.78, chrome, segs=18, caps=(False, False), z0=0.98))
    # height collar + clamp knob
    b.add(lathe([(0.0, 0.985), (0.0185, 0.985), (0.0205, 0.99), (0.0205, 1.03), (0.0175, 1.04), (0.0098, 1.045)], blk, segs=28, smooth_angle=40))
    b.add(cylinder(0.0212, 0.008, teal, segs=28, caps=(False, False), z0=1.005))
    b.add(cylinder(0.004, 0.03, chrome, segs=10, z0=0.0).rotate(0, 90, 0).translate(0.018, 0, 1.015))
    b.add(lathe([(0.0, 0.0), (0.014, 0.0), (0.016, 0.004), (0.016, 0.012), (0.012, 0.016), (0.0, 0.016)], blk, segs=20, smooth_angle=40)
          .rotate(0, 90, 0).translate(0.046, 0, 1.015))
    # top: cap + two hooks + finial
    b.add(lathe([(0.0098, 1.75), (0.016, 1.752), (0.017, 1.772), (0.012, 1.78), (0.0, 1.781)], blk, segs=24, smooth_angle=40))
    for sx in (-1, 1):
        path = polyline_fillet([(sx * 0.012, 0, 1.770), (sx * 0.058, 0, 1.775), (sx * HOOK_X, 0, HOOK_Z - 0.008), (sx * 0.090, 0, 1.778), (sx * 0.092, 0, 1.79)], 0.009, 6)
        b.add(tube(path, 0.0034, chrome, segs=10))
        b.add(sphere(0.0045, chrome, segs=10, rings=6).translate(sx * 0.092, 0, 1.79))
    b.add(sphere(0.011, chrome, segs=16, rings=8).translate(0, 0, 1.79))
    # base hub + 3 legs
    b.add(lathe([(0.0, 0.08), (0.03, 0.08), (0.034, 0.09), (0.034, 0.15), (0.026, 0.165), (0.0125, 0.17)], blk, segs=28, smooth_angle=40))
    for k in range(3):
        a = math.radians(90 + 120 * k)
        d = np.array([math.cos(a), math.sin(a), 0.0])
        p0 = d * 0.026 + np.array([0, 0, 0.125])
        p1 = d * 0.16 + np.array([0, 0, 0.075])
        p2 = d * 0.31 + np.array([0, 0, 0.032])
        b.add(tube(catmull([p0, p1, p2], n=6), 0.0095, chrome, segs=14))
        foot = lathe([(0.0, 0.0), (0.017, 0.0), (0.018, 0.006), (0.015, 0.03), (0.0, 0.032)], rub, segs=18, smooth_angle=40)
        b.add(foot.translate(*(d * 0.315)))
    lab = DecalCanvas(0.13, 0.03, ppm=2600)
    lab.lockup(0.004, 0.003, 0.022, color=(30, 32, 35), sub_color=(10, 130, 120))
    b.decal(lab, center=(0.0, 0.0206, 1.022), normal=(0, 1, 0), up=(0, 0, 1), mats=["black_plastic"], depth=0.01, min_dot=0.1)
    b.col_cyl((0, 0, 0.9), 0.013, 1.8, axis="z", material="METAL_HOLLOW_SMALL")
    b.col_cyl((0, 0, 0.03), 0.30, 0.06, axis="z", material="METAL_HOLLOW_SMALL")


# =============================================================================================
# bag helpers
# =============================================================================================
def _film(b):
    return b.mat("bag_film", color=(236, 242, 244), spec=0.9, gloss=0.9, alpha=0.20, layer="alpha", grain=0.0)


def _bag_tab(b, w=0.032, top=0.0):
    film = _film(b)
    g = box((w, 0.0016, 0.016), film, r=0.0007, seg=1, center=(0, 0, top - 0.008))
    return g


def _port(b, x, z, cap_mat):
    film = _film(b)
    g = Geo()
    g += cylinder(0.0042, 0.03, film, segs=14, caps=(False, True), z0=-0.03).translate(x, 0, z)
    g += lathe([(0.0, -0.012), (0.0058, -0.012), (0.0058, 0.0), (0.0, 0.0)], cap_mat, segs=16).translate(x, 0, z - 0.03)
    return g


def _giving_set(b, x, z_top, length=0.36, fluid_mat=None):
    film = _film(b)
    white = m_white_plastic(b)
    blue = b.mat("roller_blue", color=(40, 110, 200), spec=0.4, gloss=0.5, edge=0.3)
    g = Geo()
    # spike into the port + drip chamber
    g += cylinder(0.0085, 0.055, film, segs=18, bevel=0.002, z0=-0.055).translate(x, 0, z_top)
    if fluid_mat:
        g += cylinder(0.0078, 0.02, fluid_mat, segs=16, bevel=0.0015, z0=-0.053).translate(x, 0, z_top)
    g += cylinder(0.006, 0.01, white, segs=16, z0=0.0).translate(x, 0, z_top - 0.005)
    # tubing hanging with a slight S curve
    z0 = z_top - 0.055
    path = catmull([(x, 0, z0), (x, 0.004, z0 - 0.06), (x + 0.02, 0.012, z0 - length * 0.45), (x - 0.01, 0.01, z0 - length * 0.8), (x, 0.004, z0 - length)], n=8)
    g += tube(path, 0.0021, film, segs=10, split=0.2)
    # roller clamp
    zc = z0 - length * 0.3
    g += box((0.016, 0.012, 0.05), white, r=0.003, seg=2, center=(x + 0.012, 0.006, zc))
    g += cylinder(0.0065, 0.006, blue, segs=18, bevel=0.0012, z0=-0.003).rotate(0, 90, 0).translate(x + 0.012, 0.013, zc + 0.008)
    g += cylinder(0.0035, 0.018, white, segs=14, bevel=0.001, z0=-0.018).translate(*path[-1])
    return g


def _bag_label(lines, w, h, ppm=3600, band=(40, 110, 200)):
    dc = DecalCanvas(w, h, ppm)
    dc.rect(0, 0, w, h, r=0.003, color=(236, 240, 242), alpha=0.92, spec=0.35, gloss=0.5)
    dc.rect(0, 0, w, h * 0.16, r=0.003, color=band)
    dc.mark(0.004, h * 0.025, h * 0.11)
    dc.text(0.004 + h * 0.15, h * 0.08, "NAYZEEE MEDICAL", h * 0.055, fnt="label", anchor="lm", color=(250, 252, 252), spacing=h * 0.006, max_w=w * 0.75)
    for t, y, size, fnt, col in lines:
        dc.text(w / 2, y, t, size, fnt=fnt, color=col, max_w=w * 0.92)
    return dc


# =============================================================================================
# saline bag 500 mL
# =============================================================================================
@prop("nz_amb_ivbag_saline", atlas=256, alpha_atlas=512, lod=50, hd=8, doc={
    "title": "Saline 0.9% 500 mL bag with giving set",
    "origin": "hanging slot at the top of the bag",
    "axes": "bag hangs along -Z, printed front faces +Y",
    "attach": f"IV stand hook: stand entity pos ({HOOK_X}, 0, {HOOK_Z}) rot (0, 0, 0); hand: PH_R_Hand (28422) pos (0.0, 0.0, 0.1) rot (0, 0, 0)",
})
def ivbag_saline(b):
    film = _film(b)
    saline = b.mat("saline", color=(205, 228, 238), spec=0.6, gloss=0.85, alpha=0.14, layer="alpha", grain=0.0)
    cap = b.mat("port_cap", color=(40, 110, 200), spec=0.4, gloss=0.5, edge=0.3)
    W, H = 0.115, 0.170
    zc = -0.012 - 0.006 - H / 2
    g = Geo()
    g += pillow(W, H, 0.032, film, seam=0.006, tag="bag").translate(0, 0, zc)
    g += pillow(W - 0.01, H - 0.01, 0.026, saline, zmax=H / 2 - 0.02, tag="fluid", inset=0.0).translate(0, 0, zc)
    g += _bag_tab(b, top=0.0)
    zb = zc - H / 2 - 0.006
    g += _port(b, 0.016, zb, cap)
    g += _giving_set(b, -0.014, zb, fluid_mat=saline)
    b.add(g)
    lab = _bag_label([("0.9% SODIUM CHLORIDE", 0.032, 0.0062, "label", (30, 60, 140)),
                      ("Intravenous Infusion", 0.042, 0.0042, "label-semi", (40, 44, 48)),
                      ("500 mL", 0.058, 0.010, "label", (30, 60, 140)),
                      ("LOT 26A417   EXP 2029-04", 0.074, 0.0034, "mono", (40, 44, 48))], 0.075, 0.084)
    b.decal(lab, center=(0.0, 0.02, zc + 0.02), normal=(0, 1, 0), up=(0, 0, 1), mats=["bag_film"], depth=0.03, min_dot=0.2)
    sc = DecalCanvas(0.02, 0.13, ppm=4000)
    for k in range(1, 5):
        y = 0.01 + k * 0.025
        sc.rect(0.0, y - 0.0003, 0.008, 0.0006, color=(20, 22, 26))
        sc.text(0.0105, y, str(k * 100), 0.0028, fnt="label-semi", anchor="lm", color=(20, 22, 26))
    b.decal(sc, center=(-0.044, 0.02, zc - 0.005), normal=(0, 1, 0), up=(0, 0, 1), mats=["bag_film"], depth=0.03, min_dot=0.2)
    hole = DecalCanvas(0.03, 0.016, ppm=6000)
    hole.rect(0.006, 0.004, 0.018, 0.006, r=0.003, fill=False, width=0.0012, color=(160, 170, 175))
    b.decal(hole, center=(0, 0.001, -0.008), normal=(0, 1, 0), up=(0, 0, 1), mats=["bag_film"], depth=0.004)
    b.col_box((-0.064, -0.018, zb - 0.06), (0.064, 0.018, 0.0), "PLASTIC_HOLLOW_CLEAR")


# =============================================================================================
# blood bags
# =============================================================================================
def _make_bloodbag(level):
    fill = level / 100.0

    def build(b):
        film = _film(b)
        blood = b.mat("blood", color=(104, 8, 14), spec=0.75, gloss=0.85, grain=0.04, grain_scale=0.03, ao=0.5)
        cap = b.mat("port_cap", color=(206, 40, 44), spec=0.4, gloss=0.5, edge=0.3)
        W, H = 0.120, 0.165
        t = 0.007 + 0.03 * fill
        zc = -0.012 - 0.006 - H / 2
        g = Geo()
        g += pillow(W, H, t, film, seam=0.007, tag="bag").translate(0, 0, zc)
        if fill > 0:
            # liquid settles at the bottom of the hanging bag: from -H/2 up to the level
            g += pillow(W - 0.008, H - 0.008, max(t - 0.004, 0.003), blood, zmax=-H / 2 + fill * (H - 0.012), tag="blood").translate(0, 0, zc)
        g += _bag_tab(b, top=0.0)
        zb = zc - H / 2 - 0.007
        g += _port(b, 0.02, zb, cap)
        g += _port(b, -0.002, zb, cap)
        # donor tube with sealed segments, filled when the bag holds blood
        tmat = blood if fill > 0 else film
        path = catmull([(-0.022, 0, zb), (-0.024, 0.004, zb - 0.06), (-0.01, 0.012, zb - 0.13), (0.015, 0.01, zb - 0.15),
                        (0.03, 0.006, zb - 0.11), (0.026, 0.002, zb - 0.07)], n=8)
        g += tube(path, 0.0022, film, segs=10, split=0.2)
        if fill > 0:
            g += tube(path, 0.0017, tmat, segs=8, split=0.2, caps=True)
        for k in range(0, len(path) - 4, 6):
            g += cylinder(0.0028, 0.003, film, segs=10, caps=(True, True)).rotate(0, 0, 0).translate(*path[k])
        b.add(g)
        lab = DecalCanvas(0.084, 0.09, ppm=3400)
        lab.rect(0, 0, 0.084, 0.09, r=0.003, color=(240, 242, 242), alpha=0.95, spec=0.35, gloss=0.5)
        lab.rect(0, 0, 0.084, 0.014, r=0.003, color=(196, 30, 36))
        lab.mark(0.003, 0.002, 0.010)
        lab.text(0.016, 0.007, "NAYZEEE BLOOD SERVICE", 0.0042, fnt="label", anchor="lm", color=(250, 250, 250), max_w=0.064)
        lab.text(0.042, 0.022, "RED CELLS  CPD-SAGM", 0.0046, fnt="label", color=(30, 32, 35), max_w=0.078)
        lab.rect(0.006, 0.030, 0.034, 0.034, r=0.002, color=(196, 30, 36))
        lab.text(0.023, 0.044, "O", 0.014, fnt="label-black", color=(250, 250, 250))
        lab.text(0.023, 0.058, "NEG", 0.0055, fnt="label", color=(250, 250, 250))
        rng = np.random.default_rng(level + 3)
        x = 0.046
        while x < 0.078:
            bw = 0.0004 + rng.random() * 0.0012
            lab.rect(x, 0.031, bw, 0.020, color=(20, 22, 24))
            x += bw + 0.0004 + rng.random() * 0.0009
        lab.text(0.062, 0.056, "DN 26-04417", 0.0028, fnt="mono", color=(30, 32, 35))
        lab.text(0.042, 0.072, "450 mL  ·  store 2-6 C", 0.0034, fnt="label-semi", color=(30, 32, 35), max_w=0.078)
        lab.text(0.042, 0.083, "CHECK ID BEFORE TRANSFUSION", 0.0028, fnt="label", color=(196, 30, 36), max_w=0.078)
        b.decal(lab, center=(0.0, 0.03, zc + 0.012), normal=(0, 1, 0), up=(0, 0, 1), mats=["bag_film"], depth=0.04, min_dot=0.2)
        hole = DecalCanvas(0.03, 0.016, ppm=6000)
        hole.rect(0.006, 0.004, 0.018, 0.006, r=0.003, fill=False, width=0.0012, color=(160, 170, 175))
        b.decal(hole, center=(0, 0.001, -0.008), normal=(0, 1, 0), up=(0, 0, 1), mats=["bag_film"], depth=0.004)
        b.col_box((-0.068, -max(t / 2, 0.005) - 0.002, zb - 0.16), (0.068, max(t / 2, 0.005) + 0.002, 0.0), "PLASTIC_HOLLOW_CLEAR")
    build.__module__ = __name__
    return build


for _lvl in (0, 25, 50, 75, 100):
    register(f"nz_amb_bloodbag_{_lvl}", _make_bloodbag(_lvl), atlas=256, alpha_atlas=512, lod=50, hd=8, doc={
        "title": f"Blood bag, {_lvl}% full (red cells, O NEG label)",
        "origin": "hanging slot at the top of the bag",
        "axes": "bag hangs along -Z (blood settles at the bottom), label faces +Y",
        "attach": f"IV stand hook: stand entity pos ({HOOK_X}, 0, {HOOK_Z}) rot (0, 0, 0); lying flat label-up on nz_amb_blood_mixer: see the mixer's attach note (rot (90, 0, 0) lays it along +Y label-up, add a Z turn to run it along X); in the bay: IV hooks of nz_amb_bay_shell",
        "variant": "swap between _0/_25/_50/_75/_100 as the bag fills (donation) or empties (transfusion)",
    })


# =============================================================================================
# pressure infuser
# =============================================================================================
@prop("nz_amb_infuser", atlas=512, alpha_atlas=512, lod=50, hd=8, doc={
    "title": "Pressure infuser bag with gauge and hand bulb (holds a 500 mL bag)",
    "origin": "top hook",
    "axes": "hangs along -Z, clear window + gauge face +Y",
    "attach": f"IV stand hook: stand entity pos ({HOOK_X}, 0, {HOOK_Z}) rot (0, 0, 0)",
})
def infuser(b):
    fabric = b.mat("infuser_fabric", color=(26, 92, 112), spec=0.16, gloss=0.25, bump="fabric", bump_amp=0.0002, bump_scale=0.0016,
                   grain=0.05, grain_scale=0.04, edge=0.15, color2=(20, 74, 92))
    vinyl = b.mat("vinyl", color=(232, 238, 240), spec=0.85, gloss=0.88, alpha=0.18, layer="alpha", grain=0.0)
    film = _film(b)
    saline = b.mat("saline", color=(205, 228, 238), spec=0.6, gloss=0.85, alpha=0.14, layer="alpha", grain=0.0)
    teal = m_teal(b)
    chrome = m_chrome(b)
    bulbm = b.mat("bulb", color=(8, 140, 130), spec=0.3, gloss=0.45, bump="rubber", bump_amp=0.00005, bump_scale=0.001, edge=0.2)
    white = m_white_plastic(b)
    blk = m_black_plastic(b)
    glass = b.mat("gauge_glass", color=(240, 244, 246), spec=1.0, gloss=0.95, alpha=0.12, layer="alpha", grain=0.0)
    W, H = 0.15, 0.26
    zc = -0.03 - H / 2
    shell = pillow(W, H, 0.05, fabric, seam=0.008, tag="cuff", nx=20, nz=26)
    for c in shell.charts:
        if c.tag.endswith(":front"):
            c.mat = vinyl
    b.add(shell.translate(0, 0, zc))
    # fabric frame around the window
    lp = rrect(W - 0.02, H - 0.02, 0.02, 5)

    def front_y(x, z):
        hw, hh = W / 2, H / 2
        a = np.clip(1 - np.abs(x / hw) ** 3, 0, 1)
        c = np.clip(1 - np.abs(z / hh) ** 3, 0, 1)
        return 0.025 * np.sqrt(a * c)
    path = np.stack([lp[:, 0], front_y(lp[:, 0], lp[:, 1]) + 0.001, zc + lp[:, 1]], axis=1)
    b.add(sweep(rrect(0.016, 0.002, 0.0008, 2), path, fabric, closed_path=True, up=(0, 1, 0), tag="frame", smooth_angle=60))
    # inner saline bag visible through the window
    b.add(pillow(W - 0.04, H - 0.06, 0.03, film, tag="inner").translate(0, -0.002, zc + 0.01))
    b.add(pillow(W - 0.05, H - 0.07, 0.024, saline, zmax=(H - 0.07) / 2 - 0.015, tag="inner_fluid").translate(0, -0.002, zc + 0.01))
    # binding + hook
    b.add(box((0.05, 0.012, 0.03), fabric, r=0.005, seg=2, center=(0, 0, -0.03)))
    b.add(torus(0.012, 0.0022, chrome, segs=20, tube_segs=8).rotate(90, 0, 0).translate(0, 0, -0.012))
    b.add(box((0.05, 0.004, 0.008), teal, r=0.002, seg=1, center=(0, 0.007, -0.028)))
    # gauge on the right side (viewer's right = -X)
    gx, gz = -0.105, zc + 0.03
    gauge = Geo()
    gauge += lathe([(0.0, 0.0), (0.028, 0.0), (0.030, 0.003), (0.030, 0.014), (0.0285, 0.0172), (0.0258, 0.0176), (0.0256, 0.016), (0.0, 0.016)],
                   blk, segs=36, smooth_angle=40)
    gauge += cylinder(0.0256, 0.0008, white, segs=36, caps=(False, True), z0=0.016)
    gauge += lathe([(0.0258, 0.0176), (0.0255, 0.0186), (0.018, 0.0212), (0.0, 0.022)], glass, segs=36, smooth_angle=60)
    gauge += box((0.0012, 0.019, 0.0006), blk, center=(0, 0.006, 0.0172)).rotate(0, 0, -35, origin=(0, 0, 0))
    gauge += cylinder(0.002, 0.0012, blk, segs=10, z0=0.0168)
    b.add(align(gauge, (0, 1, 0), (0, 0, 1), (gx, -0.008, gz)))
    # tubes: bag -> gauge -> bulb
    clear = film
    t1 = catmull([(-0.06, 0.0, zc - H / 2 + 0.02), (-0.085, 0.0, zc - H / 2 - 0.01), (-0.105, -0.008, gz - 0.06), (gx, -0.008, gz - 0.03)], n=8)
    b.add(tube(t1, 0.0028, clear, segs=10))
    t2 = catmull([(gx, -0.008, gz - 0.03), (-0.115, -0.006, gz - 0.12), (-0.1, 0.0, zc - H / 2 - 0.12), (-0.09, 0.0, zc - H / 2 - 0.19)], n=8)
    b.add(tube(t2, 0.0028, clear, segs=10))
    zb = zc - H / 2 - 0.19
    b.add(lathe([(0.0, 0.0), (0.006, 0.002), (0.016, 0.014), (0.022, 0.035), (0.021, 0.06), (0.014, 0.078), (0.006, 0.086), (0.0, 0.087)],
                bulbm, segs=24, smooth_angle=50).rotate(180, 0, 0).translate(-0.09, 0.0, zb))
    b.add(cylinder(0.005, 0.012, chrome, segs=14, bevel=0.0015, z0=-0.012).translate(-0.09, 0.0, zb - 0.087))
    # decals
    dial = DecalCanvas(0.05, 0.05, ppm=9000)
    cx = cy = 0.025
    for k in range(0, 31):
        a = math.radians(225 - k * 9)
        r0, r1 = (0.0175, 0.022) if k % 5 == 0 else (0.0195, 0.022)
        dial.line([(cx + math.cos(a) * r0, cy - math.sin(a) * r0), (cx + math.cos(a) * r1, cy - math.sin(a) * r1)], 0.0006, color=(20, 22, 24))
        if k % 10 == 0:
            dial.text(cx + math.cos(a) * 0.0145, cy - math.sin(a) * 0.0145, str(k * 10), 0.0026, fnt="label", color=(20, 22, 24))
    for k0, k1, col in ((20, 30, (40, 170, 90)), (30, 31, (210, 40, 40))):
        for k in range(k0 * 3, k1 * 3):
            a = math.radians(225 - k * 3)
            dial.circle(cx + math.cos(a) * 0.0232, cy - math.sin(a) * 0.0232, 0.0011, color=col)
    dial.text(cx, cy + 0.009, "mmHg", 0.0026, fnt="label-semi", color=(60, 64, 68))
    dial.text(cx, cy - 0.006, "NAYZEEE", 0.0022, fnt="label", color=(10, 130, 120))
    b.decal(dial, center=(gx, -0.008 + 0.0168, gz), normal=(0, 1, 0), up=(0, 0, 1), mats=["white_plastic"], depth=0.003)
    lab = DecalCanvas(0.12, 0.03, ppm=3000)
    lab.lockup(0.004, 0.003, 0.022, color=(235, 238, 240), sub_color=TEAL_HI)
    b.decal(lab, center=(0.0, 0.006, -0.03 - 0.02), normal=(0, 1, 0), up=(0, 0, 1), mats=["infuser_fabric"], depth=0.03, min_dot=0.2)
    tag = DecalCanvas(0.11, 0.024, ppm=3000)
    tag.text(0.055, 0.012, "PRESSURE INFUSER  500 mL", 0.0058, fnt="label", color=(235, 238, 240), spacing=0.0006, max_w=0.105)
    b.decal(tag, center=(0.0, 0.004, zc - H / 2 + 0.003), normal=(0, 1, 0), up=(0, 0, 1), mats=["infuser_fabric"], depth=0.03, min_dot=0.2)
    b.col_box((-0.085, -0.03, zc - H / 2 - 0.01), (0.085, 0.03, -0.0), "CLOTH")
    b.col_box((-0.14, -0.03, zb - 0.1), (-0.06, 0.03, gz + 0.035), "RUBBER")


