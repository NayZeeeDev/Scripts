"""
Earpiece (PROPS_BRIEF section 6, SPEC section 9.1): nzr_earpiece - image only (export=False: built and rendered
for the item icon html/img/items/radio_earpiece.png, never streamed, not in the ytyp).

A surveillance-style coiled earpiece: clear mushroom ear tip on a clear acoustic tube that coils down to a
two-part quick-disconnect, a small black transducer with a steel clothing clip, and a short black lead to a
right-angle 3.5 mm plug. Generic hardware only - no maker name or mark (Rule B).

Origin: bottom centre of the assembly lying on a surface; +Z up, +Y = the side the icon camera looks from.
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import Geo, bezier, box, catmull, cylinder, lathe, prop, tube, vec
from nzprops.mesh import path_frames

from .common import align
from .radio_common import m_sma


def _coil_along(axis_pts, coil_r, pitch, wire_r, mat, n_per_turn=16, segs=8):
    """A coil spring of wire radius wire_r wound around a curved axis polyline (constant pitch)."""
    P = np.asarray(axis_pts, np.float64)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    L = s[-1]
    turns = L / pitch
    n = max(8, int(turns * n_per_turn))
    t = np.linspace(0.0, L, n)
    C = np.stack([np.interp(t, s, P[:, k]) for k in range(3)], axis=1)
    T, S, U = path_frames(C, up=(0, 1, 0))
    a = 2 * math.pi * t / pitch
    pts = C + coil_r * (np.cos(a)[:, None] * S + np.sin(a)[:, None] * U)
    return tube(pts, wire_r, mat, segs=segs, split=0.05, tag="coil")


@prop("nzr_earpiece", atlas=512, alpha_atlas=256, glow_atlas=32, lod=10.0, hd=3.0, export=False, budget=15000,
      doc={"title": "Coiled radio earpiece (item icon model, not streamed)",
           "origin": "bottom centre of the assembly lying on a surface",
           "axes": "+Z up, ear tip at the top, plug at the bottom",
           "attach": "none - rendered for html/img/items/radio_earpiece.png only (export=False)"},
      preview={"views": ["icon", "front", "face", "left", "top"]})
def earpiece(b):
    clear = b.mat("tube_clear", color=(214, 224, 230), spec=0.92, gloss=0.9, alpha=0.42, layer="alpha", grain=0.0, edge=0.05,
                  smudge=0.2, scratch=0.05)
    tip = b.mat("tip_silicone", color=(226, 230, 232), spec=0.6, gloss=0.7, alpha=0.62, layer="alpha", grain=0.01, edge=0.05)
    blk = b.mat("ear_black", color=(26, 27, 29), spec=0.3, gloss=0.45, bump="stipple", bump_amp=0.00002, bump_scale=0.0005,
                grain=0.03, edge=0.55, wear_color=(70, 72, 76))
    rub = b.mat("ear_rubber", color=(20, 21, 23), spec=0.14, gloss=0.24, bump="rubber", bump_amp=0.00002, bump_scale=0.0004,
                edge=0.3)
    steel = b.mat("clip_steel", color=(170, 174, 178), spec=0.85, gloss=0.7, metal=1.0, bump="brushed", bump_amp=0.000006,
                  bump_scale=0.0003, edge=0.3, scratch=0.3)
    cord = b.mat("ear_cord", color=(22, 23, 25), spec=0.3, gloss=0.45, edge=0.2)
    nickel = m_sma(b, "nickel")

    # ---- ear tip + elbow (top left of the icon) ---------------------------------------------------------------------
    tip_c = vec(0.054, 0.010, 0.106)
    tip_dir = vec(0.62, 0.52, -0.58) / np.linalg.norm([0.62, 0.52, -0.58])
    mush = lathe([(0.0, 0.0), (0.0019, 0.0), (0.0022, 0.0025), (0.0058, 0.0040), (0.0061, 0.0060), (0.0050, 0.0088),
                  (0.0030, 0.0106), (0.0, 0.0111)], tip, segs=22, smooth_angle=40, tag="ear_tip")
    core = lathe([(0.0, 0.0), (0.0016, 0.0), (0.0016, 0.0085), (0.0, 0.0090)], b.mat("tip_core", color=(150, 160, 168), spec=0.5,
                                                                                     gloss=0.6, edge=0.1), segs=12, smooth_angle=50)
    stem = cylinder(0.0021, 0.008, clear, segs=12, z0=-0.0075, caps=(False, False), tag="ear_stem")
    b.add(align(mush + core + stem, tip_dir, (0, 0, 1), tip_c))
    # ---- coil: an arch from the ear tip over to the transducer ----------------------------------------------------
    a0 = vec(0.040, 0.004, 0.118)
    p_stem = tip_c - tip_dir * 0.0075
    elbow = bezier(p_stem, p_stem - tip_dir * 0.010, a0 + vec(0.006, 0.0, -0.008), a0, 14)
    b.add(tube(elbow, 0.0017, clear, segs=10, split=0.05, tag="tube"))
    axis = catmull([a0, vec(0.022, 0.0, 0.134), vec(-0.004, 0.0, 0.134), vec(-0.024, 0.0, 0.116), vec(-0.032, 0.0, 0.092),
                    vec(-0.031, 0.0, 0.074)], n=10)
    b.add(_coil_along(axis, 0.0052, 0.0040, 0.0016, clear, n_per_turn=18, segs=8))
    # ---- quick disconnect (clear half + black half) -----------------------------------------------------------
    qd_top = vec(-0.031, 0.0, 0.074)
    qd_dir = vec(0.0, 0.0, -1.0)
    qd = Geo()
    qd += lathe([(0.0, 0.0), (0.0024, 0.0), (0.0036, 0.003), (0.0036, 0.0095), (0.0030, 0.0105)], clear, segs=16, smooth_angle=40,
                tag="qd_clear")
    qd += lathe([(0.0030, 0.0105), (0.0038, 0.0110), (0.0040, 0.0190), (0.0032, 0.0205), (0.0, 0.0207)], blk, segs=16, smooth_angle=40,
                tag="qd_black")
    b.add(align(qd, qd_dir, (0, 1, 0), qd_top))
    # ---- transducer body with clothing clip -----------------------------------------------------------------------
    tb = qd_top + qd_dir * 0.0205
    body = Geo()
    body += box((0.020, 0.012, 0.030), blk, r=0.0045, seg=3, center=(0, 0, -0.015), tag="transducer")
    body += box((0.012, 0.0016, 0.020), b.mat("ear_grille", color=(14, 15, 16), spec=0.1, gloss=0.2, bump="perf", bump_amp=0.0002,
                                               bump_scale=0.0009, ao=1.0), r=0.0006, seg=1, center=(0, 0.0058, -0.016), tag="grille")
    body += box((0.010, 0.0012, 0.028), steel, r=0.0005, seg=1, center=(0, -0.0085, -0.017), tag="clip")
    body += box((0.010, 0.0035, 0.0018), steel, r=0.0006, seg=1, center=(0, -0.0072, -0.0025), tag="clip")
    body += box((0.008, 0.0028, 0.0050), blk, r=0.0010, seg=1, center=(0, -0.0068, -0.0010), tag="clip_hinge")
    body += lathe([(0.0, -0.030), (0.0036, -0.030), (0.0030, -0.038), (0.0020, -0.044), (0.0, -0.045)], rub, segs=12, smooth_angle=40,
                  tag="boot")
    body.rotate(0, 4.0, 0)
    b.add(body.translate(tb))
    # ---- lead looping back under the arch to a right-angle 3.5 mm plug lying on the surface ---------------------------
    p0 = tb + vec(-0.003, 0.0, -0.044)
    plug_at = vec(0.020, 0.012, 0.0046)
    lead = catmull([p0, p0 + vec(0.0, 0.002, -0.006), vec(-0.026, 0.010, 0.0035), vec(-0.012, 0.022, 0.0016), vec(0.004, 0.016, 0.0016),
                    plug_at + vec(-0.004, 0.0, 0.0), plug_at], n=8)
    b.add(tube(lead, 0.0014, cord, segs=8, split=0.1, tag="lead"))
    plug = lathe([(0.0, 0.0), (0.0040, 0.0), (0.0042, 0.012), (0.0036, 0.016), (0.0024, 0.0175), (0.0, 0.0177)], rub, segs=16,
                 smooth_angle=40, tag="plug_body")
    b.add(plug.rotate(0, 90, 0).translate(plug_at))
    pin = lathe([(0.0, 0.0), (0.0018, 0.0), (0.0018, 0.004), (0.0016, 0.0045), (0.0017, 0.0085), (0.0015, 0.009), (0.0017, 0.0125),
                 (0.0012, 0.0140), (0.0, 0.0142)], nickel, segs=12, smooth_angle=40, tag="plug_pin")
    b.add(align(pin, (0, 1, 0), (0, 0, 1), plug_at + vec(0.0135, 0.0036, 0.0)))
    b.col_box((-0.045, -0.015, 0.0), (0.065, 0.035, 0.145), "PLASTIC")
