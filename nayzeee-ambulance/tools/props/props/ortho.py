"""
Orthopaedic / haemorrhage control: pelvic binder (flat + worn), tourniquet (applied), forearm
crutch, posterior leg + arm splints, cervical collar.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL_HI, WHITE, DecalCanvas, box, catmull, cylinder, extrude, lathe, polyline_fillet, prop, torus,
                     rrect, sphere, sweep, tube, vec)

from .common import (align, m_alu, m_black_plastic, m_chrome, m_foam, m_rubber, m_teal, m_webbing, m_white_plastic)


def _stitch_strip(length, width, ppm=3000, inset=0.004, color=(20, 21, 23)):
    """Two lock-stitch rows along the long edges of a strap / band (canvas x = along the strap)."""
    dc = DecalCanvas(length, width, ppm)
    for y in (inset, width - inset):
        dc.stitch([(0.0, y), (length, y)], length=0.0035, gap=0.0016, width=0.0007, color=color)
    return dc


def _band_charts(geo, run, mat):
    for c in geo.charts:
        if c.tag.endswith(f":{run}"):
            c.mat = mat
    return geo


# =============================================================================================
# pelvic binder
# =============================================================================================
BELT = (52, 55, 60)


def _binder_mats(b):
    belt = b.mat("binder_belt", color=BELT, spec=0.14, gloss=0.22, bump="fabric", bump_amp=0.00025, bump_scale=0.0019,
                 grain=0.05, grain_scale=0.06, edge=0.2, dirt=0.15, color2=(42, 44, 48))
    edge = m_webbing(b, "binder_edge", (30, 31, 34))
    teal = b.mat("binder_teal", color=(10, 150, 140), spec=0.16, gloss=0.25, bump="webbing", bump_amp=0.0002, bump_scale=0.0014,
                 grain=0.05, grain_scale=0.03, edge=0.15)
    buckle = m_black_plastic(b)
    return belt, edge, teal, buckle


def _binder_print(b, tag, length, width, start, repeat):
    dc = DecalCanvas(0.26, width * 0.5, ppm=2400)
    hh = width * 0.5
    dc.star_of_life(hh * 0.5, hh * 0.5, hh * 0.62, color=TEAL_HI, rod=(52, 55, 60))
    dc.text(hh * 1.0, hh * 0.40, "PELVIC BINDER", hh * 0.24, fnt="label", anchor="lm", color=TEAL_HI, spacing=hh * 0.02, max_w=0.26 - hh * 1.05)
    dc.text(hh * 1.0, hh * 0.72, "PB-1  ·  SIZE STD  ·  LATEX FREE", hh * 0.12, fnt="label-semi", anchor="lm", color=(170, 176, 180),
            max_w=0.26 - hh * 1.05)
    b.chart_decal(dc, tag, u0=width * 0.25, v0=start, rot=270, repeat_v=repeat, mats=["binder_belt"])


@prop("nz_amb_binder_flat", atlas=512, lod=60, hd=10, doc={
    "title": "Pelvic binder laid flat (ready to slide under the patient)",
    "origin": "ground, centre of the belt",
    "axes": "belt length along X (buckle at +X), width along Y, printed face up (+Z)",
    "attach": "placed on the ground beside / under the patient; swap to nz_amb_binder_worn once applied",
})
def binder_flat(b):
    belt, edge, teal, buckle = _binder_mats(b)
    W, T = 0.215, 0.007
    xs = np.linspace(-0.47, 0.40, 44)
    zs = T / 2 + 0.0025 * (1 + np.sin(xs * 7.0 + 0.6)) * (np.abs(xs) < 0.38)
    ys = 0.008 * np.sin(xs * 3.1)
    path = np.stack([xs, ys, zs], axis=1)
    taper = np.interp(xs, [-0.47, -0.36, 0.40], [0.42, 1.0, 1.0])
    band = sweep(rrect(W, T, 0.0, 1), path, belt, up=(0, 0, 1), scale=np.stack([taper, np.ones_like(taper)], axis=1),
                 tag="belt", split=0.3, smooth_angle=30)
    _band_charts(band, 1, "binder_edge")
    _band_charts(band, 3, "binder_edge")
    b.add(band)
    # pull tab on the free end
    tp = polyline_fillet([(-0.46, 0.0, T), (-0.53, 0.0, T + 0.002), (-0.56, 0.0, T * 0.6)], 0.01, 3)
    b.add(sweep(rrect(0.05, 0.004, 0.0015, 2), tp, teal, side=(0, 1, 0), tag="tab"))
    # buckle + tension straps on the other end
    b.add(extrude(rrect(0.06, 0.20, 0.012, 4), 0.012, buckle, bevel=0.003, bevel_seg=2).translate(0.43, 0.0, 0.0))
    b.add(box((0.02, 0.17, 0.004), buckle, r=0.0015, seg=1, center=(0.43, 0.0, 0.013)))
    for yy in (-0.055, 0.055):
        sp = np.array([(0.41, yy, 0.0135), (0.30, yy, T + 0.0045), (0.14, yy, T + 0.0045), (0.10, yy, T + 0.006)])
        b.add(sweep(rrect(0.038, 0.0025, 0.0, 1), sp, teal, up=(0, 0, 1), tag="tension"))
        b.add(box((0.05, 0.045, 0.006), teal, r=0.0025, seg=1, center=(0.085, yy, T + 0.008)))
    # print: logo every 0.3 m + centring guide
    _binder_print(b, "belt:2", 0.87, W, 0.03, 0.57)
    guide = DecalCanvas(0.20, W * 0.86, ppm=2000)
    guide.rect(0.098, 0.0, 0.004, W * 0.86, color=WHITE)
    guide.text(0.05, W * 0.43, "CENTRE", 0.012, fnt="label", color=WHITE, spacing=0.002)
    guide.text(0.15, W * 0.43, "TROCHANTERS", 0.010, fnt="label", color=WHITE, spacing=0.0015, max_w=0.09)
    b.chart_decal(guide, "belt:2", u0=W * 0.07, v0=0.335, rot=270, mats=["binder_belt"])
    hook = DecalCanvas(0.12, W * 0.8, ppm=1500)
    hook.rect(0, 0, 0.12, W * 0.8, r=0.004, color=(30, 31, 34), height=0.0003, spec=0.08, gloss=0.1)
    b.chart_decal(hook, "belt:0", u0=W * 0.1, v0=0.02, rot=90)
    b.chart_decal(_stitch_strip(0.87, W, ppm=2200, inset=0.007), "belt:2", u0=0.0, v0=0.0, rot=270, repeat_v=0.87, mats=["binder_belt"])
    sl = DecalCanvas(0.06, 0.20, ppm=4000)
    for yy in (0.045, 0.155):
        sl.rect(0.012, yy - 0.022, 0.036, 0.044, r=0.004, color=(12, 13, 15), height=-0.002)
    sl.text(0.03, 0.10, "PULL", 0.006, fnt="label", color=(150, 156, 160), rotate=90, height=0.0002)
    b.decal(sl, center=(0.43, 0.0, 0.012), normal=(0, 0, 1), up=(0, 1, 0), mats=["black_plastic"], depth=0.004)
    b.col_box((-0.56, -0.12, 0.0), (0.46, 0.12, 0.02), "CLOTH")


@prop("nz_amb_binder_worn", atlas=512, lod=60, hd=10, doc={
    "title": "Pelvic binder applied (closed loop)",
    "origin": "centre of the loop (pelvis centre)",
    "axes": "loop around Z (band height along Z), buckle at the front (+Y), 0.36 wide (X) x 0.26 deep (Y) x 0.22 tall",
    "attach": "SKEL_Pelvis (11816) pos (0.0, 0.0, 0.0) rot (0, 0, 0) as a starting point - the pelvis bone's axes are not "
              "world aligned, typical fix rot (0, 90, 0) or (90, 0, 90); disable collision on the attached object",
})
def binder_worn(b):
    belt, edge, teal, buckle = _binder_mats(b)
    n = 72
    th = np.linspace(0, 2 * math.pi, n, endpoint=False)
    ax, ay = 0.176, 0.126
    x = ax * np.sign(np.cos(th)) * np.abs(np.cos(th)) ** 0.75
    y = ay * np.sign(np.sin(th)) * np.abs(np.sin(th)) ** 0.75
    path = np.stack([x, y, np.zeros(n)], axis=1)
    band = sweep(rrect(0.007, 0.20, 0.0, 1), path, belt, closed_path=True, up=(0, 0, 1), tag="loop", split=0.35, smooth_angle=30)
    _band_charts(band, 0, "binder_edge")
    _band_charts(band, 2, "binder_edge")
    b.add(band)
    # overlapping free end + buckle at the front
    k0, k1 = int(n * 0.12), int(n * 0.38)
    ov = path[k0:k1].copy()
    nrm = np.stack([np.cos(th[k0:k1]) / ax, np.sin(th[k0:k1]) / ay, np.zeros(k1 - k0)], axis=1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    ov += nrm * 0.0075
    b.add(sweep(rrect(0.007, 0.19, 0.0, 1), ov, belt, up=(0, 0, 1), tag="over", smooth_angle=30))
    front = np.array([0.0, ay + 0.012, 0.0])
    b.add(box((0.06, 0.012, 0.20), buckle, r=0.005, seg=2, center=front))
    for zz in (-0.05, 0.05):
        for sx in (-1, 1):
            m0, m1 = (int(n * 0.25), int(n * 0.40)) if sx < 0 else (int(n * 0.10), int(n * 0.25))
            sp = path[m0:m1].copy()
            nn = np.stack([np.cos(th[m0:m1]) / ax, np.sin(th[m0:m1]) / ay, np.zeros(m1 - m0)], axis=1)
            nn /= np.linalg.norm(nn, axis=1, keepdims=True)
            sp += nn * 0.0135
            sp[:, 2] = zz
            b.add(sweep(rrect(0.003, 0.036, 0.0, 1), sp, teal, up=(0, 0, 1), tag="tension"))
    for sx in (-1, 1):
        b.add(box((0.04, 0.008, 0.06), teal, r=0.003, seg=1, center=(sx * 0.07, ay + 0.012, 0.0)))
    per = float(np.sum(np.linalg.norm(np.diff(np.concatenate([path, path[:1]]), axis=0), axis=1)))
    dc = DecalCanvas(0.30, 0.10, ppm=2000)
    dc.star_of_life(0.045, 0.05, 0.06, color=TEAL_HI, rod=(52, 55, 60))
    dc.text(0.085, 0.040, "PELVIC BINDER", 0.016, fnt="label", anchor="lm", color=TEAL_HI, spacing=0.002, max_w=0.2)
    dc.text(0.085, 0.064, "PB-1  ·  SIZE STD", 0.008, fnt="label-semi", anchor="lm", color=(170, 176, 180), max_w=0.2)
    b.chart_decal(dc, "loop:1", u0=0.05, v0=per * 0.75 - 0.15, rot=90, mats=["binder_belt"])
    b.chart_decal(_stitch_strip(0.8, 0.2, ppm=2000, inset=0.006), "loop:1", u0=0.0, v0=0.0, rot=90, repeat_v=0.8, mats=["binder_belt"])
    side = DecalCanvas(0.16, 0.03, ppm=1500)
    side.text(0.08, 0.015, "PELVIC BINDER", 0.012, fnt="label", color=TEAL_HI, spacing=0.0025, max_w=0.155)
    b.chart_decal(side, "loop:1", u0=0.085, v0=per * 0.5 - 0.08, rot=90, mats=["binder_belt"])
    bk = DecalCanvas(0.06, 0.20, ppm=4000)
    for zz in (0.05, 0.15):
        bk.rect(0.014, zz - 0.02, 0.032, 0.04, r=0.004, color=(12, 13, 15), height=-0.002)
    bk.text(0.03, 0.10, "PB-1", 0.006, fnt="label", color=(150, 156, 160), height=0.0002)
    bk.groove_rect(0.004, 0.004, 0.052, 0.192, r=0.004)
    b.decal(bk, center=tuple(front + np.array([0, 0.006, 0])), normal=(0, 1, 0), up=(0, 0, 1), mats=["black_plastic"], depth=0.004)
    b.col_box((-0.18, -0.13, -0.11), (0.18, 0.14, 0.11), "CLOTH")


# =============================================================================================
# tourniquet (applied, windlass locked)
# =============================================================================================
@prop("nz_amb_tourniquet", atlas=1024, lod=40, hd=6, doc={
    "title": "Windlass tourniquet, applied loop (inner diameter ~0.11 m)",
    "origin": "centre of the loop (limb axis)",
    "axes": "limb / bone axis = X, windlass rod on top (+Z) lying along X, time strap on the rod",
    "attach": "limb bones (X runs along the bone): SKEL_L_UpperArm 45509, SKEL_R_UpperArm 40269, SKEL_L_Forearm 61163, "
              "SKEL_R_Forearm 28252, SKEL_L_Thigh 58271, SKEL_R_Thigh 51826, SKEL_L_Calf 63931, SKEL_R_Calf 36864 - "
              "pos (0.12, 0, 0) along the bone, rot (0, 0, 0); scale by choosing the bone (thigh loops look tight on big peds)",
})
def tourniquet(b):
    strap = m_webbing(b, "tq_strap", (26, 27, 30))
    blk = m_black_plastic(b)
    red = b.mat("tq_red", color=(200, 36, 40), spec=0.3, gloss=0.45, edge=0.3)
    white = b.mat("tq_time", color=(232, 234, 235), spec=0.2, gloss=0.3, bump="fabric", bump_amp=0.0001, bump_scale=0.0012)
    R = 0.057
    a = np.linspace(0, 2 * math.pi, 56, endpoint=False)
    loop = np.stack([np.zeros_like(a), R * np.cos(a), R * np.sin(a)], axis=1)
    b.add(sweep(rrect(0.0035, 0.038, 0.0, 1), loop, strap, closed_path=True, up=(1, 0, 0), tag="loop", smooth_angle=30))
    # second wrap (free running end) over most of the loop
    a2 = np.linspace(math.radians(-60), math.radians(200), 40)
    over = np.stack([np.full_like(a2, 0.0), (R + 0.0036) * np.cos(a2), (R + 0.0036) * np.sin(a2)], axis=1)
    b.add(sweep(rrect(0.0035, 0.036, 0.0, 1), over, strap, up=(1, 0, 0), tag="over", smooth_angle=30))
    ex = over[0] + np.array([0.0, 0.002, -0.004])
    b.add(box((0.036, 0.004, 0.02), red, r=0.0015, seg=1, center=ex).rotate_axis((1, 0, 0), -60, origin=ex))
    # windlass clip + rod on top
    zt = R + 0.008
    b.add(box((0.050, 0.040, 0.006), blk, r=0.003, seg=2, center=(0, 0, zt)))
    for sx in (-1, 1):
        hook = np.array([(sx * 0.022, -0.016, zt + 0.002), (sx * 0.022, -0.016, zt + 0.014), (sx * 0.022, -0.004, zt + 0.02), (sx * 0.022, 0.006, zt + 0.014)])
        b.add(sweep(rrect(0.006, 0.003, 0.001, 2), catmull(hook, n=5), blk, side=(1, 0, 0), tag="clip"))
    rodm = b.mat("tq_rod", color=(10, 150, 140), spec=0.42, gloss=0.55, bump="ribs", bump_amp=0.00012, bump_scale=0.0018, edge=0.5,
                 dirt=0.15)
    rod = cylinder(0.0055, 0.104, rodm, segs=20, bevel=0.0015, z0=-0.052).rotate(0, 90, 0).translate(0, -0.004, zt + 0.010)
    b.add(rod)
    b.add(box((0.03, 0.022, 0.008), strap, r=0.003, seg=1, center=(0, -0.004, zt + 0.0035)))
    b.add(box((0.034, 0.03, 0.0025), white, r=0.0012, seg=1, center=(0, 0.008, zt + 0.0168)))
    lab = DecalCanvas(0.034, 0.03, ppm=6000)
    lab.text(0.017, 0.009, "TIME", 0.0045, fnt="label", color=(200, 36, 40))
    lab.text(0.017, 0.021, "14:32", 0.0048, fnt="mono-bold", color=(20, 22, 24))
    b.decal(lab, center=(0, 0.008, zt + 0.0181), normal=(0, 0, 1), up=(0, -1, 0), mats=["tq_time"], depth=0.003)
    pr = DecalCanvas(0.10, 0.03, ppm=5000)
    pr.text(0.004, 0.011, "TQ-1  TOURNIQUET", 0.0058, fnt="label", anchor="lm", color=(232, 236, 238), spacing=0.0006)
    pr.text(0.004, 0.022, "NOTE TIME APPLIED  ·  DO NOT LOOSEN", 0.0032, fnt="label-semi", anchor="lm", color=(200, 60, 60))
    b.chart_decal(pr, "loop:1", u0=0.004, v0=0.21, rot=90, mats=["tq_strap"])
    b.chart_decal(_stitch_strip(0.4, 0.038, ppm=6000, inset=0.003, color=(60, 62, 66)), "loop:1", u0=0.0, v0=0.0, rot=90,
                  repeat_v=0.4, mats=["tq_strap"])
    b.col_box((-0.055, -0.065, -0.065), (0.055, 0.065, 0.09), "CLOTH")


# =============================================================================================
# forearm crutch
# =============================================================================================
@prop("nz_amb_crutch", atlas=1024, lod=70, hd=10, doc={
    "title": "Forearm crutch, 1.2 m",
    "origin": "centre of the hand grip",
    "axes": "lower tube along -Z (ferrule at z = -0.86), grip points +Y (forward), cuff on top at the back",
    "attach": "PH_R_Hand (28422) pos (0.0, 0.0, 0.0) rot (0, 0, 0) or SKEL_R_Hand (57005) pos (0.08, 0.02, 0.0) rot (90, 0, 90); "
              "second crutch in the left hand: PH_L_Hand (60309)",
})
def crutch(b):
    alu = m_alu(b)
    teal = b.mat("crutch_teal", color=(10, 150, 140), spec=0.6, gloss=0.65, metal=0.7, bump="brushed", bump_amp=0.00001,
                 bump_scale=0.0004, grain=0.02, edge=0.3)
    blk = m_black_plastic(b)
    rub = m_rubber(b)
    grip = b.mat("crutch_grip", color=(30, 31, 34), spec=0.14, gloss=0.2, bump="ribs", bump_amp=0.0003, bump_scale=0.006, edge=0.2)
    chrome = m_chrome(b)
    foam = m_foam(b)
    jy = -0.068
    b.add(cylinder(0.0095, 0.42, alu, segs=18, caps=(False, False), z0=-0.835).translate(0, jy, 0))
    b.add(cylinder(0.0112, 0.44, alu, segs=20, caps=(False, False), z0=-0.45).translate(0, jy, 0))
    b.add(cylinder(0.0128, 0.022, blk, segs=20, bevel=0.003, z0=-0.462).translate(0, jy, 0))
    b.add(sphere(0.0032, chrome, segs=10, rings=5).translate(0, jy + 0.0095, -0.60))
    b.add(lathe([(0.0, -0.86), (0.020, -0.86), (0.021, -0.855), (0.018, -0.84), (0.0135, -0.80), (0.0128, -0.79), (0.0, -0.79)],
                rub, segs=24, smooth_angle=40).translate(0, jy, 0))
    # junction moulding
    b.add(box((0.032, 0.044, 0.07), blk, r=0.013, seg=3, center=(0, jy - 0.002, 0.004)))
    # grip
    gy = np.linspace(jy + 0.01, 0.075, 12)
    gpath = np.stack([np.zeros_like(gy), gy, 0.004 + 0.004 * np.sin((gy - gy[0]) / (gy[-1] - gy[0]) * math.pi)], axis=1)
    sc = np.interp(gy, [gy[0], 0.0, 0.05, gy[-1]], [0.9, 1.05, 1.0, 0.92])
    b.add(sweep(rrect(0.032, 0.036, 0.013, 4), gpath, grip, up=(0, 0, 1), scale=sc, tag="grip", smooth_angle=50))
    # upper tube (teal) angled back + cuff
    top = np.array([0.0, jy - 0.035, 0.30])
    b.add(tube(np.array([[0.0, jy, 0.03], top]), 0.0108, teal, segs=18, caps=True))
    d = (top - np.array([0.0, jy, 0.03]))
    d /= np.linalg.norm(d)
    e1 = np.array([1.0, 0.0, 0.0])
    e2 = np.cross(d, e1)
    if e2[1] < 0:
        e2 = -e2
    Rc = 0.048
    cen = top + e2 * (Rc + 0.006) + d * 0.01
    ang = np.radians(np.linspace(130, 410, 44))
    arc = np.array([cen + Rc * (math.cos(t) * e1 + math.sin(t) * e2) for t in ang])
    b.add(sweep(rrect(0.004, 0.05, 0.0018, 2), arc, teal, up=tuple(d), tag="cuff", smooth_angle=40))
    arc_in = np.array([cen + (Rc - 0.004) * (math.cos(t) * e1 + math.sin(t) * e2) for t in ang[2:-2]])
    b.add(sweep(rrect(0.004, 0.044, 0.0015, 2), arc_in, foam, up=tuple(d), tag="cuffpad", smooth_angle=40))
    b.add(box((0.026, 0.02, 0.05), blk, r=0.008, seg=2, center=top + d * 0.01 + e2 * 0.002))
    # decals
    lab = DecalCanvas(0.03, 0.14, ppm=5000)
    lab.text(0.011, 0.07, "CR-2  ·  FOREARM CRUTCH", 0.0042, fnt="label", color=(240, 242, 243), spacing=0.0006, rotate=90)
    lab.text(0.021, 0.07, "MAX 120 kg", 0.0034, fnt="label-semi", color=(220, 226, 228), rotate=90)
    mid = (np.array([0.0, jy, 0.03]) + top) / 2
    b.decal(lab, center=tuple(mid + np.array([0.0108, 0, 0])), normal=(1, 0, 0), up=tuple(d), mats=["crutch_teal"], depth=0.008)
    holes = DecalCanvas(0.02, 0.30, ppm=4000)
    for k in range(9):
        holes.circle(0.006, 0.02 + k * 0.03, 0.0026, color=(18, 18, 20), height=-0.0004)
        holes.text(0.0145, 0.02 + k * 0.03, str(9 - k), 0.0034, fnt="label", color=(60, 62, 66), height=-0.00005)
    b.decal(holes, center=(0, jy + 0.0095, -0.62), normal=(0, 1, 0), up=(0, 0, 1), mats=["alu"], depth=0.006)
    b.col_cyl((0, jy, -0.415), 0.013, 0.89, axis="z", material="METAL_HOLLOW_SMALL")
    b.col_box((-0.02, jy - 0.02, -0.03), (0.02, 0.08, 0.04), "RUBBER")
    b.col_box((-0.055, jy - 0.06, 0.04), (0.055, 0.06, 0.345), "PLASTIC")


# =============================================================================================
# posterior splints
# =============================================================================================
def _splint(b, L, R, straps, foot_plate=False, palm=False, name="LEG"):
    shell = b.mat("splint_shell", color=(12, 146, 136), spec=0.4, gloss=0.5, bump="orange_peel", bump_amp=0.00002,
                  bump_scale=0.002, grain=0.03, grain_scale=0.06, edge=0.45, dirt=0.15)
    pad = b.mat("splint_pad", color=(46, 49, 53), spec=0.06, gloss=0.1, bump="fabric", bump_amp=0.00025, bump_scale=0.002,
                grain=0.05, grain_scale=0.04, ao=1.0, color2=(36, 38, 41))
    web = m_webbing(b)
    teal = m_teal(b)
    t_sh, t_pad = 0.004, 0.008

    def arc_poly(r0, r1, a0, a1, n=28):
        a = np.radians(np.linspace(a0, a1, n))
        outer = np.stack([r1 * np.cos(a), r1 * np.sin(a)], axis=1)
        inner = np.stack([r0 * np.cos(a[::-1]), r0 * np.sin(a[::-1])], axis=1)
        return np.concatenate([outer, inner])
    path = np.array([[-L / 2, 0, 0], [L / 2, 0, 0]])
    b.add(sweep(arc_poly(R + t_pad, R + t_pad + t_sh, 158, 382), path, shell, up=(0, 0, 1), tag="shell", smooth_angle=35))
    b.add(sweep(arc_poly(R, R + t_pad, 163, 377), np.array([[-L / 2 + 0.004, 0, 0], [L / 2 - 0.004, 0, 0]]), pad, up=(0, 0, 1),
                tag="pad", smooth_angle=35))
    Ro = R + t_pad + t_sh + 0.0025
    for xs in straps:
        a = np.radians(np.linspace(0, 360, 48, endpoint=False))
        loop = np.stack([np.full_like(a, xs), Ro * np.cos(a), Ro * np.sin(a)], axis=1)
        b.add(sweep(rrect(0.003, 0.038, 0.0, 1), loop, web, closed_path=True, up=(1, 0, 0), tag="strap", smooth_angle=30))
        bc = np.array([xs, -(Ro + 0.004) * math.cos(math.radians(35)), (Ro + 0.004) * math.sin(math.radians(35))])
        b.add(box((0.044, 0.012, 0.03), teal, r=0.004, seg=2, center=tuple(bc)))
        nrm = np.array([0.0, -math.cos(math.radians(35)), math.sin(math.radians(35))])
        b.add(align(torus(0.009, 0.0016, m_chrome(b), segs=20, tube_segs=6).scale(1.0, 0.7, 1.0), nrm, (1, 0, 0), tuple(bc + nrm * 0.008)))
    if straps:
        b.chart_decal(_stitch_strip(0.6, 0.038, ppm=4000, inset=0.004, color=(60, 62, 66)), "strap:", u0=0.0, v0=0.0, rot=90,
                      repeat_v=0.6, mats=["webbing"])
    if foot_plate:
        fx = L / 2 + 0.004
        b.add(box((0.008, 2 * (R + 0.012), 0.24), shell, r=0.003, seg=2, center=(fx, 0, 0.03)))
        b.add(box((0.008, 2 * R, 0.20), pad, r=0.003, seg=2, center=(fx - 0.008, 0, 0.035)))
        a = np.radians(np.linspace(0, 180, 24))
        loopf = np.stack([np.full_like(a, fx - 0.03), (R + 0.015) * np.cos(a), 0.06 + (R + 0.015) * np.sin(a) * 0.7], axis=1)
        b.add(sweep(rrect(0.003, 0.034, 0.0, 1), loopf, web, up=(1, 0, 0), tag="footstrap", smooth_angle=30))
    if palm:
        b.add(cylinder(0.018, 0.07, pad, segs=20, bevel=0.006, z0=-0.035).rotate(90, 0, 0).translate(L / 2 - 0.03, 0, -R + 0.022))
    lab = DecalCanvas(0.20, 0.04, ppm=3200)
    lab.star_of_life(0.02, 0.02, 0.032, color=WHITE, rod=(12, 146, 136))
    lab.text(0.042, 0.015, f"{name} SPLINT", 0.0095, fnt="label", anchor="lm", color=WHITE, spacing=0.0012, max_w=0.15)
    lab.text(0.042, 0.03, "VACUUM-FORMED  ·  X-RAY TRANSLUCENT  ·  SP-" + name[0], 0.0042, fnt="label-semi", anchor="lm",
             color=(210, 245, 240), max_w=0.15)
    for sy in (-1, 1):
        b.decal(lab, center=(0.0 if not straps else (straps[0] + straps[1]) / 2 if len(straps) > 1 else 0.0,
                             sy * (R + t_pad + t_sh) * math.cos(math.radians(30)), -(R + t_pad + t_sh) * math.sin(math.radians(30))),
                normal=(0, sy * math.cos(math.radians(30)), -math.sin(math.radians(30))), up=(0, sy * math.sin(math.radians(30)), math.cos(math.radians(30))),
                mats=["splint_shell"], depth=0.02, min_dot=0.4)


@prop("nz_amb_splint_leg", atlas=1024, lod=60, hd=10, doc={
    "title": "Posterior leg splint (U channel, 0.75 m, foot plate)",
    "origin": "on the limb axis at mid length (the channel wraps around it)",
    "axes": "length along X, foot plate at +X pointing +Z, open side of the channel +Z (anterior)",
    "attach": "SKEL_L_Calf (63931) / SKEL_R_Calf (36864) pos (0.10, 0.0, 0.0) rot (0, 0, 0) - the calf bone's X runs knee -> foot; "
              "rotate around X until the open side faces the shin (try rot (90, 0, 0) / (-90, 0, 0))",
})
def splint_leg(b):
    _splint(b, 0.75, 0.066, [-0.25, 0.0, 0.25], foot_plate=True, name="LEG")
    b.col_box((-0.38, -0.08, -0.08), (0.39, 0.08, 0.15), "PLASTIC")


@prop("nz_amb_splint_arm", atlas=1024, lod=50, hd=8, doc={
    "title": "Posterior arm splint (U channel, 0.40 m, palm roll)",
    "origin": "on the limb axis at mid length",
    "axes": "length along X (palm roll at +X), open side +Z",
    "attach": "SKEL_L_Forearm (61163) / SKEL_R_Forearm (28252) pos (0.12, 0.0, 0.0) rot (0, 0, 0); rotate around X so the open side faces the forearm",
})
def splint_arm(b):
    _splint(b, 0.40, 0.044, [-0.11, 0.09], palm=True, name="ARM")
    b.col_box((-0.205, -0.058, -0.058), (0.205, 0.058, 0.058), "PLASTIC")


# =============================================================================================
# cervical collar
# =============================================================================================
@prop("nz_amb_collar", atlas=1024, lod=40, hd=8, doc={
    "title": "Rigid cervical collar (applied loop)",
    "origin": "neck axis at the collar's mid height",
    "axes": "loop around Z, chin support and trachea opening at the front (+Y)",
    "attach": "SKEL_Neck_1 (39317) pos (0.0, 0.0, 0.0) rot (0, 0, 0) as a start - the neck bone's X runs up the neck, "
              "so the usual fix is rot (0, 90, 0) or (0, -90, 180); disable collision on the attached object",
})
def collar(b):
    shell = m_white_plastic(b)
    foam = m_foam(b)
    teal = m_teal(b)
    velcro = b.mat("velcro", color=(10, 146, 136), spec=0.1, gloss=0.15, bump="velcro", bump_amp=0.00012, bump_scale=0.0007, edge=0.1)
    n = 72
    th = np.linspace(0, 2 * math.pi, n, endpoint=False)
    rx, ry = 0.066, 0.071
    deg = np.degrees(th)
    key = [0, 45, 90, 135, 180, 270, 360]
    hgt = np.interp(deg, key, [0.064, 0.086, 0.104, 0.086, 0.064, 0.078, 0.064])
    zoff = np.interp(deg, key, [0.0, 0.007, 0.014, 0.007, 0.0, 0.004, 0.0])
    path = np.stack([rx * np.cos(th), ry * np.sin(th), zoff], axis=1)
    shell_geo = sweep(rrect(0.0045, 1.0, 0.0, 1), path, shell, closed_path=True, up=(0, 0, 1),
                      scale=np.stack([np.ones(n), hgt], axis=1), tag="shell", smooth_angle=30, split=0.12)
    for c in shell_geo.charts:
        if c.tag.endswith(":1"):
            c.density = 1.8
        elif c.tag.endswith(":3"):
            c.density = 0.15
        elif c.tag.endswith(":0") or c.tag.endswith(":2"):
            c.mat = "teal"
    b.add(shell_geo)
    nrm = np.stack([np.cos(th) / rx, np.sin(th) / ry, np.zeros(n)], axis=1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    inner = path - nrm * 0.0065
    b.add(sweep(rrect(0.0085, 1.0, 0.0, 1), inner, foam, closed_path=True, up=(0, 0, 1),
                scale=np.stack([np.ones(n), hgt - 0.008], axis=1), tag="pad", smooth_angle=30, split=0.25).set_density(0.6))
    # contoured chin support
    k0, k1 = int(n * 0.14), int(n * 0.37)
    lip = path[k0:k1] + nrm[k0:k1] * 0.0015
    lip[:, 2] = zoff[k0:k1] + hgt[k0:k1] / 2 - 0.006
    w = np.sin(np.linspace(0, math.pi, k1 - k0)) * 0.6 + 0.4
    lp = np.array([(-0.0025, 0.0), (0.0025, 0.0), (0.022, 0.018), (0.024, 0.024), (0.019, 0.025), (0.0, 0.0045)])
    b.add(sweep(lp, lip, shell, up=(0, 0, 1), scale=np.stack([w, w], axis=1), tag="chin", smooth_angle=40))
    b.add(sweep(rrect(0.006, 0.006, 0.0025, 2) + vec(0.0215, 0.0215), lip, foam, up=(0, 0, 1), scale=np.stack([w, w], axis=1), tag="chinpad"))
    # back closure tab
    k2, k3 = int(n * 0.62), int(n * 0.80)
    tab = path[k2:k3] + nrm[k2:k3] * 0.0042
    b.add(sweep(rrect(0.0025, 0.05, 0.0, 1), tab, velcro, up=(0, 0, 1), tag="tab", smooth_angle=30))
    b.add(box((0.012, 0.006, 0.05), teal, r=0.002, seg=1, center=tuple(tab[-1] + np.array([0.004, 0.0, 0.0]))))
    # decals: trachea opening + vents + logo
    front = DecalCanvas(0.09, 0.09, ppm=4000)
    front.rect(0.025, 0.036, 0.04, 0.03, r=0.012, color=(18, 18, 20), height=-0.0012, spec=0.05, gloss=0.1)
    front.rect(0.025, 0.036, 0.04, 0.03, r=0.012, fill=False, width=0.002, color=(10, 150, 140))
    for k in range(5):
        front.circle(0.01 + k * 0.0175, 0.079, 0.0026, color=(18, 18, 20), height=-0.0008)
    front.text(0.045, 0.015, "ADJUSTABLE", 0.0052, fnt="label", color=(10, 130, 120), spacing=0.0008)
    front.text(0.045, 0.024, "ADULT  ·  CC-4", 0.0036, fnt="label-semi", color=(90, 94, 98))
    for k, (t, c) in enumerate((("S", (230, 200, 40)), ("M", (40, 120, 210)), ("L", (200, 60, 60)))):
        front.circle(0.03 + k * 0.015, 0.031, 0.0028, color=c)
        front.text(0.03 + k * 0.015, 0.0312, t, 0.0028, fnt="label", color=(255, 255, 255))
    b.decal(front, center=(0.0, ry + 0.003, 0.012 + 0.002), normal=(0, 1, 0), up=(0, 0, 1), mats=["white_plastic"], depth=0.03, min_dot=0.3)
    side = DecalCanvas(0.06, 0.04, ppm=3000)
    for k in range(3):
        for j in range(2):
            side.circle(0.012 + k * 0.018, 0.012 + j * 0.016, 0.0028, color=(18, 18, 20), height=-0.0008)
    for sx in (-1, 1):
        b.decal(side, center=(sx * (rx + 0.003), 0.0, 0.002), normal=(sx, 0, 0), up=(0, 0, 1), mats=["white_plastic"], depth=0.03, min_dot=0.4)
    b.col_box((-0.075, -0.08, -0.04), (0.075, 0.09, 0.07), "PLASTIC")


