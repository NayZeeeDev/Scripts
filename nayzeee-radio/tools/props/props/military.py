"""
MX-905 TACTICAL - rugged military handheld (PROPS_BRIEF section 3, SPEC section 9).

    nzr_military           complete radio (idle mx905 screen, medium LOD)
    nzr_military_body      the same without its pressable parts (key wells, knob bosses + D-shafts, PTT pocket)
    nzr_military_<pid>     k0..k9 kstar khash kok kback kup(-> menu) dpad knob_ch knob_vol emerg ptt side1 side2

Body 66 W x 42 D x 150 H mm, ranger-green polymer: front shell + rear top cover + battery box (real seams all
round), black rubber corner bumpers on all 8 corners, a raised front frame with 6 Torx screws, a raised lip round
the black screen bezel (colour LCD 42 x 32 mm, 512 x 384), control cluster (back, menu, square d-pad with raised
arrow ridges, tall OK key), 4 x 3 grey keypad, speaker hole array + mic port. Top: large knurled channel knob with
a guard flange and a pointer in a raised ring with 16 printed positions, volume knob with an OFF detent, orange
emergency key recessed in a rubber guard ring, LED light pipe, coil-spring gooseneck + tapered whip with a ball tip
(220 mm). Left: guarded PTT between two guard ribs, two side keys in round collars (tactile dots), anodised rating
plate. Right: 6-pin bayonet accessory connector with a dust cap on a moulded strap, rubber grip insert. Back: battery box with two
over-centre draw latches, MOLLE-style strap plate with a webbing strap woven through its slots, caution sticker.

Labelling: "MX-905" + "TACTICAL" stencil print, rating plate, battery label, fine print - no maker name, no NAYZEEE
mark (Rule B).

Texels: the main atlas (1024) carries the shells, plates and small hardware; a second 1024 "face" atlas carries the
printed surfaces (front face, top deck, right side, rating plate, rear cover back, front / battery bottoms) so every print is
crisp at 25-40 cm. Medium LOD (6 m -> 40 m): the fine hardware is high-only; cheap stand-ins (keys, knobs, antenna,
bumpers, plates) keep the silhouette and the colour blocks.

Axes: metres, +Z up (antenna), +Y = front face, +X = viewer's left. Origin = grip point (body cross-section centre
at 40 % of the body height from its bottom).
"""
from __future__ import annotations

import contextlib
import math
from dataclasses import replace as dc_replace

import numpy as np

from nzprops import DecalCanvas, Geo, box, cylinder, extrude, fillet_poly, lathe, quad, rr_lathe, rrect, sweep, tube, vec
from nzprops.mesh import chamfer_fillet_rect, polyline_fillet

from .common import align, caution_label, rating_plate, screws
from .radio_common import (INK, battery_label, battery_pack, boss, charging_contacts, gooseneck, grille_holes,
                           housing, ink, key, key_cap, knob, light_pipe, m_bumper_rubber, m_gunmetal, m_keypad_rubber,
                           m_print_dark, m_ranger_green, m_soft_black, print_decal, screen_window,
                           sma_nut, well_for, wells, whip_antenna)
from .radio_kit import radio

# ---------------------------------------------------------------------------------------------
# dimensions (metres)
# ---------------------------------------------------------------------------------------------
W, D, H = 0.066, 0.042, 0.150
Z0 = -0.4 * H                 # bottom (-0.060)
ZT = Z0 + H                   # top deck (+0.090)
FY = D / 2                    # front face
DF = 0.027                    # front shell depth
YS = FY - DF                  # front shell / rear pieces split plane (-0.006)
YB = -D / 2                   # back face of the battery box
GAP = 0.0006                  # seam between the front shell and the rear pieces
LIFT = 0.0002                 # pressable parts stand this far off their well floors (clean AO under them)
DB = D - DF - GAP             # depth of the rear pieces
CHAMF, FIL, RIM = 0.0035, 0.0012, 0.0012
SX = W / 2                    # side faces at +-SX
YSIDE = (FY + YS) / 2         # centre line of the front shell's side faces (0.0075)
Z_TC = 0.0598                 # rear top cover / battery box split height

# front face layout (z of centres)
Z_SCREEN = 0.0525
Z_PRINT = 0.0805
Z_CLUSTER = 0.0175
Z_KEYPAD = -0.0145
Z_SPEAKER = -0.0480
X_SCREW = 0.0276
Z_SCREWS = (0.0695, 0.0105, -0.0405)
FRAME = (0.0584, 0.1460, 0.0040, 0.0032, 0.0008)   # front frame: outer w, h, corner, band width, height
Z_FRAME = (Z0 + ZT) / 2 - 0.0000

# top deck layout (x, y)
P_ANT = (0.0215, -0.003)
P_CH = (0.0005, -0.0025)
P_VOL = (-0.0215, -0.006)
P_EMERG = (-0.0185, 0.0135)
P_LED = (0.0215, 0.0125)

BUMPER_A, BUMPER_B, BUMPER_H, BUMPER_E = 0.0075, 0.0075, 0.017, 0.0015

KEYPAD = [
    [("k1", "1", ".,?"), ("k2", "2", "ABC"), ("k3", "3", "DEF")],
    [("k4", "4", "GHI"), ("k5", "5", "JKL"), ("k6", "6", "MNO")],
    [("k7", "7", "PQRS"), ("k8", "8", "TUV"), ("k9", "9", "WXYZ")],
    [("kstar", "*", "‹"), ("k0", "0", "⇧"), ("khash", "#", "⇥")],
]
KP_PITCH = (0.0135, 0.0095)
KP_SIZE = (0.0100, 0.0070)


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def _face_mat(r, base, name):
    """The same material on the 'face' atlas (print-heavy surfaces get their own 1024 texels)."""
    return r.mat_from(name, dc_replace(r.mats[base], layer="face"))


def m_emerg_orange(r):
    return r.mat("mx_emerg_orange", color=(236, 104, 22), spec=0.42, gloss=0.55, bump="dimple", bump_amp=0.00005,
                 bump_scale=0.0007, grain=0.03, edge=0.45, dirt=0.12, wear_color=(250, 160, 90))


def m_knob_knurl(r, name="mx_knob_knurl"):
    return r.mat(name, color=(26, 27, 29), spec=0.26, gloss=0.36, bump="knurl", bump_amp=0.00011, bump_scale=0.0008,
                 grain=0.03, grain_scale=0.02, edge=0.55, dirt=0.18, wear_color=(92, 94, 98), scratch=0.2)


def m_well_floor(r):
    """Dark floor of the key / PTT / button wells (seen on the body model with the parts pulled)."""
    return r.mat("mx_well_floor", color=(17, 18, 19), spec=0.12, gloss=0.22, bump="stipple", bump_amp=0.00001, bump_scale=0.0004,
                 grain=0.02, edge=0.0, ao=0.6, dirt=0.05)


def m_knob_cap(r):
    return r.mat("mx_knob_cap", color=(28, 29, 31), spec=0.22, gloss=0.32, bump="stipple", bump_amp=0.00002, bump_scale=0.0004,
                 grain=0.03, edge=0.5, dirt=0.15, wear_color=(88, 90, 94))


def m_latch_steel(r):
    return r.mat("mx_latch_steel", color=(84, 87, 82), spec=0.6, gloss=0.5, metal=1.0, bump="brushed", bump_amp=0.000008,
                 bump_scale=0.0004, grain=0.03, edge=0.8, dirt=0.25, wear_color=(168, 170, 162), scratch=0.45)


def m_strap_plate(r):
    return r.mat("mx_strap_plate", color=(40, 42, 40), spec=0.2, gloss=0.3, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0005, grain=0.035, grain_scale=0.03, edge=0.6, dirt=0.25, wear_color=(84, 86, 82), cavity=0.6)


def m_cap_rubber(r):
    return r.mat("mx_cap_rubber", color=(24, 25, 26), spec=0.12, gloss=0.2, bump="rubber", bump_amp=0.00005,
                 bump_scale=0.0005, grain=0.04, edge=0.35, dirt=0.2, wear_color=(70, 72, 74))


def m_mx_webbing(r):
    return r.mat("mx_webbing", color=(62, 64, 46), spec=0.12, gloss=0.2, bump="webbing", bump_amp=0.0002, bump_scale=0.0014,
                 grain=0.06, grain_scale=0.02, edge=0.25, dirt=0.25, wear_color=(96, 98, 76))


def m_battery_green(r):
    """Battery-box sides: the chassis green with a coarser moulded dimple grip texture."""
    return r.mat("mx_battery_grip", color=(56, 61, 49), spec=0.16, gloss=0.26, bump="dimple", bump_amp=0.00008,
                 bump_scale=0.0016, grain=0.035, grain_scale=0.03, edge=0.6, dirt=0.2, wear_color=(96, 102, 86), cavity=0.6)


def m_rating_plate(r):
    return r.mat("mx_rating_plate", color=(40, 42, 38), spec=0.5, gloss=0.5, metal=0.7, bump="brushed", bump_amp=0.000006,
                 bump_scale=0.0003, grain=0.02, edge=0.8, dirt=0.15, wear_color=(150, 152, 146), layer="face")


# ---------------------------------------------------------------------------------------------
# LOD helpers
# ---------------------------------------------------------------------------------------------
@contextlib.contextmanager
def _hi(r):
    """Everything added inside is high-detail only (the medium model leaves it out)."""
    n0 = len(r.geo.charts)
    yield
    for c in r.geo.charts[n0:]:
        c.lod = "h"


def _med(r, *geos):
    """Cheap stand-ins drawn only by the medium model (6 m -> 40 m)."""
    if r.current_part is not None:
        raise RuntimeError("medium stand-ins belong to the body")
    for g in geos:
        r.add(g, lod="m")


def _set_mats(g: Geo, mapping):
    for c in g.charts:
        if c.tag in mapping:
            c.mat = mapping[c.tag]
    return g


# ---------------------------------------------------------------------------------------------
# small geometry helpers (module local)
# ---------------------------------------------------------------------------------------------
def _clip(poly, nx, ny, c):
    """Sutherland-Hodgman: keep the part of a CCW polygon where nx * x + ny * y >= c."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        da, db = nx * a[0] + ny * a[1] - c, nx * b[0] + ny * b[1] - c
        if da >= 0:
            out.append(tuple(a))
        if (da >= 0) != (db >= 0):
            t = da / (da - db)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def corner_bumper(mat, sx, sy, top):
    """Moulded rubber corner cap: the housing outline grown by BUMPER_E, clipped to one corner quadrant
    (BUMPER_A along X, BUMPER_B along Y), extruded BUMPER_H tall over the top (or bottom) corner."""
    e = BUMPER_E
    outline = chamfer_fillet_rect(W + 2 * e, D + 2 * e, CHAMF + e * 0.4, FIL + e, 2)
    poly = [tuple(p) for p in outline]
    poly = _clip(poly, sx, 0.0, SX - BUMPER_A)
    poly = _clip(poly, 0.0, sy, FY - BUMPER_B)
    poly = fillet_poly(np.asarray(poly), 0.0011, 1)
    if top:
        z0 = ZT + e - BUMPER_H
        caps = (False, True)
    else:
        z0 = Z0 - e
        caps = (True, False)
    return extrude(poly, BUMPER_H, mat, bevel=0.0013, bevel_seg=2, z0=z0, caps=caps, smooth_angle=50, tag="bumper")


def rr_ring(w, h, cr, ring_w, t, mat, bevel=0.0006, tag="lip", n=5):
    """Raised rounded-rectangle ring (lip / frame) standing on z = 0 facing +Z: outer w x h (corner cr), ring_w
    wide, t tall, rounded top edges. Built with rr_lathe (outer wall up, over the top, inner wall down)."""
    bv = min(bevel, t * 0.45, ring_w * 0.3)
    prof = [(0.0, 0.0), (0.0, t - bv)]
    prof += [(bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 3)]
    prof += [(ring_w - bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(math.pi / 2, 0.3, 3)]
    prof += [(ring_w, t - bv), (ring_w, 0.0)]
    return rr_lathe(w, h, cr, prof, mat, n=n, tag=tag)


def ring(mat, d_in, d_out, h, segs=24, bevel=0.0005, tag="ring"):
    """Raised ring (guard ring, button collar) standing on z = 0 facing +Z: soft rounded top (6-point profile)."""
    ri, ro = d_in / 2, d_out / 2
    bv = min(bevel, h * 0.45, (ro - ri) * 0.3)
    prof = [(ri, -0.0002), (ri, h - bv), (ri + bv, h), (ro - bv, h), (ro, h - bv), (ro, 0.0)]
    return lathe(prof, mat, segs=segs, smooth_angle=50, tag=tag)


def round_collar(mat, floor_mat, d_in, d_out, h, segs=20):
    """Raised round collar round a side button (standing on z = 0 facing +Z) + a dark floor disc inside."""
    g = ring(mat, d_in, d_out, h, segs=segs, bevel=0.0004, tag="collar")
    g += cylinder(d_in / 2, 0.0001, floor_mat, segs=segs, caps=(False, True), z0=0.00002, tag="collar_floor")
    return g


def over_centre_latch(r, x, z_pivot, z_keeper, y_face):
    """Over-centre draw latch on the back (outward = -Y): a bracket riveted to the battery box, the pivot barrel,
    a U-channel lever with a finger lip, the wire bail hooking the keeper on the rear top cover. Built in a local
    frame (x across, y up, z out of the back) from extrusions - cheap and crisp."""
    st = m_latch_steel(r)
    g = Geo()
    # bracket plate (z = out)
    g += extrude(rrect(0.0132, 0.0068, 0.0012, 2), 0.0015, st, bevel=0.0003, bevel_seg=1, caps=(False, True), smooth_angle=40,
                 tag="latch").translate(0, -0.0018, 0)
    # pivot barrel along x
    g += cylinder(0.0014, 0.0128, st, segs=10, bevel=0.0003, bevel_seg=1).rotate(0, 90, 0).translate(-0.0064, 0.0, 0.0024)
    # lever: U channel (open toward the box) from the pivot upward, lifted 6 deg at the top, finger lip
    u = np.array([(-0.0056, 0.0012), (-0.0046, 0.0012), (-0.0046, 0.0030), (0.0046, 0.0030), (0.0046, 0.0012), (0.0056, 0.0012),
                  (0.0056, 0.0041), (-0.0056, 0.0041)])
    lev = extrude(u, 0.0160, st, bevel=0.0002, bevel_seg=1, z0=-0.0160, smooth_angle=40, tag="latch_lever").rotate(90, 0, 0)
    lev += box((0.0112, 0.0012, 0.0032), st, r=0.0004, seg=1, center=(0.0, 0.0166, 0.0050), faces="+x -x +y -y +z")
    lev.rotate(6, 0, 0)
    g += lev
    # wire bail: from the lever's side pivots up over the keeper hook
    zb = 0.0062
    zk = z_keeper - z_pivot
    zo = 0.0046
    pts = np.array([(0.0060, zb, zo - 0.0004), (0.0060, zb + 0.0035, zo), (0.0060, zk + 0.0004, zo), (0.0042, zk + 0.0013, zo),
                    (-0.0042, zk + 0.0013, zo), (-0.0060, zk + 0.0004, zo), (-0.0060, zb + 0.0035, zo), (-0.0060, zb, zo - 0.0004)])
    g += tube(polyline_fillet(pts, 0.0011, 2), 0.00058, st, segs=5, caps=True, tag="bail")
    # keeper on the top cover: an L-shaped hook block (profile in (y, z), extruded across x)
    hook = np.array([(-0.0004, 0.0), (0.0048, 0.0), (0.0048, 0.0038), (0.0036, 0.0038), (0.0036, 0.0024), (-0.0004, 0.0024)])
    kp = extrude(hook, 0.0130, st, bevel=0.0003, bevel_seg=1, z0=-0.0065, smooth_angle=40, tag="keeper")
    kp.transform(np.array([[0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]))
    g += kp.translate(0.0, zk, 0.0)
    g = align(g, (0, -1, 0), (0, 0, 1), (x, y_face, z_pivot))
    # rivets on the bracket and the keeper (printed domes)
    for zc, out in ((z_pivot - 0.0040, 0.0015), (z_pivot + zk + 0.0008, 0.0024)):
        dc = DecalCanvas(0.014, 0.0036, ppm=30000)
        for sx in (-1, 1):
            dc.rivet(0.007 + sx * 0.0048, 0.0018, 0.00075, color=(126, 128, 120))
        r.decal(dc, center=(x, y_face - out, zc), normal=(0, -1, 0), up=(0, 0, 1), mats=[st], depth=0.0006, min_dot=0.7)
    return g


def strap_plate(r, plate_mat, web_mat, center_z, w=0.046, h=0.084, t=0.0022, y_face=YB):
    """MOLLE-style strap mount plate on the battery box back: a plate with three webbing slot rows, four hex screws
    and a webbing strap woven through it (over the bar between the upper two slots, out of the lowest slot down to a
    press-stud tab)."""
    slot_hw, slot_hh = 0.0155, 0.0019
    zs = [center_z + 0.0254, center_z, center_z - 0.0254]
    holes = [(0.0, z - center_z, slot_hw, slot_hh, slot_hh) for z in zs]
    wells(r, plate_mat, (0.0, y_face, center_z), (0, -1, 0), (0, 0, 1), (w, h), t, holes, depth=t, corner_n=2,
          floor_mat=r.mat("mx_slot_floor", color=(14, 15, 15), spec=0.1, gloss=0.2, ao=1.0))
    pts = [(sx * (w / 2 - 0.0038), y_face - t, center_z + sz * (h / 2 - 0.0038)) for sx in (-1, 1) for sz in (-1, 1)]
    with _hi(r):
        r.add(screws(r, pts, (0, -1, 0), d=0.0034, kind="hex", color=(70, 72, 70), segs=8))
    # webbing: 25 mm wide, 1.3 mm thick, rounded edges
    sw, st_ = 0.025, 0.0013
    prof = rrect(sw, st_, 0.0005, 2)
    ys = y_face - t                       # plate top surface
    yo = ys - st_ / 2 - 0.0001            # strap centre line lying on the plate
    yin = y_face - 0.0004                 # inside a slot
    z1, z2, z3 = zs
    seg_a = np.array([(0.0, yin, z1 - 0.0004), (0.0, yo, z1 - slot_hh - 0.0016), (0.0, yo, z2 + slot_hh + 0.0016), (0.0, yin, z2 + 0.0004)])
    seg_b = np.array([(0.0, yin, z3 - 0.0004), (0.0, yo, z3 - slot_hh - 0.0016), (0.0, yo, center_z - h / 2 + 0.0030)])
    g = Geo()
    for sp in (seg_a, seg_b):
        g += sweep(prof, polyline_fillet(sp, 0.0016, 3), web_mat, side=(1, 0, 0), smooth_angle=60, tag="webbing")
    # press stud on the tab
    tab_top, tab_bot = z3 - slot_hh - 0.0016, center_z - h / 2 + 0.0030
    stud = lathe([(0.0, 0.0), (0.0034, 0.0), (0.0034, 0.0006), (0.0026, 0.0012), (0.0014, 0.0014), (0.0, 0.0015)], m_gunmetal(r), segs=12,
                 smooth_angle=45, tag="stud")
    g += align(stud, (0, -1, 0), (0, 0, 1), (0.0, ys - st_ - 0.0001, tab_bot + 0.0036))
    r.add(g)
    # stitching on the webbing: edge rows + a box-X on the tab under the lowest slot
    top = center_z + h / 2
    dc = DecalCanvas(sw, h, ppm=24000)
    kw = dict(length=0.0016, gap=0.0009, width=0.0005, color=(92, 94, 70), height=0.0001)
    for xs in (0.0011, sw - 0.0011):
        dc.stitch([(xs, top - (z1 - slot_hh)), (xs, top - (z2 + slot_hh))], **kw)
        dc.stitch([(xs, top - (z3 - slot_hh)), (xs, top - tab_bot)], **kw)
    sh = 0.0050
    y0 = top - (tab_top - 0.0005)
    dc.stitch_rect(0.0024, y0, sw - 0.0048, sh, r=0.0004, **kw)
    dc.stitch([(0.0026, y0 + 0.0002), (sw - 0.0026, y0 + sh - 0.0002)], **kw)
    dc.stitch([(sw - 0.0026, y0 + 0.0002), (0.0026, y0 + sh - 0.0002)], **kw)
    r.decal(dc, center=(0.0, ys - st_, center_z), normal=(0, -1, 0), up=(0, 0, 1), mats=[web_mat], depth=0.0025, min_dot=0.5)
    return g


def dust_cap(r, at, normal, up, d=0.0150):
    """Rubber dust cap hanging on its strap, seen from its top: a domed cup with a gripping rim, a moulded
    centre ring and a pull tab."""
    m = m_cap_rubber(r)
    R = d / 2
    prof = [(R * 0.86, -0.0001), (R, 0.0006), (R, 0.0030), (R - 0.0005, 0.0040), (R * 0.72, 0.0043), (R * 0.68, 0.0040),
            (R * 0.42, 0.0040), (R * 0.38, 0.0044), (0.0, 0.0047)]
    g = lathe(prof, m, segs=20, smooth_angle=40, tag="dustcap")
    g += box((0.0040, 0.0030, 0.0016), m, r=0.0006, seg=1, center=(0.0, R + 0.0010, 0.0016), faces="+x -x +y +z -z")
    return align(g, normal, up, at)


def guard_ribs(mat, at, length_span, rib_w=0.0036, rib_h=0.0040, rib_len=0.0178):
    """Two raised guard ribs above and below the PTT on the +X side: stadium plan, tapered, bevelled."""
    g = Geo()
    prof = fillet_poly(np.array([(-rib_len / 2, -rib_w / 2), (rib_len / 2, -rib_w / 2), (rib_len / 2, rib_w / 2),
                                 (-rib_len / 2, rib_w / 2)]), rib_w * 0.48, 3)
    for s in (1, -1):
        rb = extrude(prof, rib_h, mat, bevel=0.0010, bevel_seg=2, caps=(False, True), smooth_angle=50, tag="ptt_guard")
        rb.taper(0.0, rib_h, 1.0, 0.72)
        g += rb.translate(0, s * length_span / 2, 0)
    return align(g, (1, 0, 0), (0, 0, 1), at)


def bayonet_connector(r, at, normal, up=(0, 0, 1), d=0.0125, pins=6, depth=0.0032):
    """Round 6-pin accessory connector: seat flange, knurled coupling ring, gunmetal shell lip with three bayonet
    pins, dark insert with gold pins and a keyway."""
    mat = m_gunmetal(r)
    knurl = r.mat("mx_conn_knurl", color=(58, 61, 64), spec=0.6, gloss=0.5, metal=1.0, bump="knurl", bump_amp=0.00006,
                  bump_scale=0.0006, edge=0.5, dirt=0.15)
    ins = r.mat("mx_conn_insert", color=(20, 21, 22), spec=0.3, gloss=0.4, edge=0.2)
    R = d / 2
    g = lathe([(R * 1.16, -0.0003), (R * 1.16, 0.00035), (R * 1.09, 0.0005)], mat, segs=24, smooth_angle=40, tag="conn")
    g += lathe([(R * 1.09, 0.0005), (R * 1.09, depth * 0.62), (R * 1.03, depth * 0.68)], knurl, segs=24, smooth_angle=40, tag="conn")
    g += lathe([(R * 1.03, depth * 0.68), (R * 0.96, depth * 0.7), (R * 0.96, depth * 0.94), (R * 0.9, depth), (R * 0.64, depth),
                (R * 0.62, depth * 0.94), (R * 0.62, depth * 0.3)], mat, segs=24, smooth_angle=40, tag="conn")
    for k in range(3):
        a = 360.0 * k / 3 + 30.0
        pin = cylinder(0.00042, 0.0009, mat, segs=6, caps=(False, True), tag="conn_pin").rotate(0, 90, 0).translate(R * 0.95, 0.0,
                                                                                                                     depth * 0.8)
        g += pin.rotate(0, 0, a)
    g += cylinder(R * 0.6, depth * 0.55, ins, segs=20, caps=(False, True), tag="conn_insert")
    pm = r.mat("mx_pin_gold", color=(214, 170, 72), spec=0.85, gloss=0.75, metal=1.0, edge=0.2)
    for k in range(pins - 1):
        a = 2 * math.pi * (k + 0.5) / (pins - 1)
        g += cylinder(R * 0.065, depth * 0.66, pm, segs=6, caps=(False, True), tag="conn_pin").translate(math.cos(a) * R * 0.36,
                                                                                                           math.sin(a) * R * 0.36, 0)
    g += cylinder(R * 0.075, depth * 0.66, pm, segs=6, caps=(False, True), tag="conn_pin")
    g += box((R * 0.16, R * 0.12, depth * 0.1), mat, center=(0.0, R * 0.62, depth * 0.56), faces="+x -x -y +z")
    return align(g, normal, up, at)


def mx_ptt(r, at, mat, length=0.032, width=0.013, t=0.0026, ridges=6, ridge_h=0.00048, dome=0.0005, depth=0.0016):
    """Big rubber PTT on the +X side: pillow-domed rounded cap, six rounded ridges following the dome across its
    upper part, 'PTT' moulded (raised, unprinted) below. `at` = base centre on the well floor."""
    n, upv = vec(1, 0, 0), vec(0, 0, 1)
    right = np.cross(upv, n)
    corner = min(length, width) * 0.42
    bv = min(0.0009, t * 0.4)
    origin = vec(at) + n * (t + dome)
    ax_, ay_ = width / 2 - bv, length / 2 - bv

    def dome_z(x, y):
        u, v = np.clip(x / ax_, -1, 1), np.clip(y / ay_, -1, 1)
        return dome * (1 - u * u) * (1 - v * v)
    with r.part("ptt", origin=origin, press=-n, depth=depth, u=right * width / 2, v=upv * length / 2, shape="rect", action="ptt"):
        g = key_cap(mat, width, length, t, corner, dome, bevel=bv)
        top = length * 0.5 - length * 0.13
        span = length * 0.56
        prof = rrect(width * 0.70, 0.0011, 0.00054, 1)
        for k in range(ridges):
            y = top - span * k / max(ridges - 1, 1)
            rg = extrude(prof, ridge_h + 0.00025, mat, bevel=0.00022, bevel_seg=1, z0=t - 0.00025, caps=(False, True),
                         smooth_angle=50, tag="ptt_ridge").translate(0.0, y, 0.0)

            def fn(p, y=y):
                q = p.copy()
                q[:, 2] = p[:, 2] + dome_z(p[:, 0], p[:, 1])
                return q
            g += rg.deform(fn)
        r.add(align(g, n, upv, at))
        dc = DecalCanvas(width * 0.9, length * 0.22, ppm=30000)
        dc.text(width * 0.45, length * 0.11, "PTT", length * 0.10, fnt="label", spacing=length * 0.01, height=0.00014, spec=0.3,
                gloss=0.45)
        y_txt = -length * 0.5 + length * 0.17
        r.decal(dc, center=origin - n * dome * 0.3 + upv * y_txt, normal=n, up=upv, depth=0.0015, min_dot=0.5)
    return origin


def floor_caps(r, holes, center, right, up, lift=0.00006):
    """Flat 2-triangle caps just above the well floors of a wells() plate (the plate's fan-triangulated floors bake
    with streaks): one quad per opening, a little oversized so its edges tuck under the well walls."""
    right, up = vec(right), vec(up)
    n = np.cross(right, up)
    g = Geo()
    for hole in holes:
        hx, hy, hw, hh = hole[:4]
        c = vec(center) + right * hx + up * hy + n * lift
        g += quad(c, right, up, 2 * hw + 0.0003, 2 * hh + 0.0003, m_well_floor(r), tag="well_cap")
    with _hi(r):
        r.add(g)


def chevron(s, w):
    """Arrow-head ridge outline pointing +Y (tip at y = s), arm width w."""
    k = w / s
    return np.array([(0.0, s), (s, 0.0), (s - k * s * 1.4, 0.0), (0.0, s - k * s * 1.4), (-(s - k * s * 1.4), 0.0), (-s, 0.0)])


# ---------------------------------------------------------------------------------------------
# prints
# ---------------------------------------------------------------------------------------------
def _stencil_cut(dc: DecalCanvas, x_m, y0_m, y1_m, w_m):
    """Cut a stencil bridge (clears colour, alpha and height) - vertical strip."""
    x0 = max(0, int(round((x_m - w_m / 2) * dc.ppm)))
    x1 = min(dc.W, int(round((x_m + w_m / 2) * dc.ppm)))
    y0 = max(0, int(round(y0_m * dc.ppm)))
    y1 = min(dc.H, int(round(y1_m * dc.ppm)))
    dc.a[y0:y1, x0:x1] = 0.0
    dc.height[y0:y1, x0:x1] = 0.0
    dc.sg_a[y0:y1, x0:x1] = 0.0


def stencil_text(dc: DecalCanvas, x, y, s, size, fnt="label-black", spacing=0.0, cut=None, **ik):
    """Text with stencil bridges: a narrow vertical gap through the round / closed glyphs (left anchored at x,
    vertically centred on y). Returns the right edge (m)."""
    dc.text(x, y, s, size, fnt=fnt, anchor="lm", spacing=spacing, **ik)
    cut = cut if cut is not None else set("0689ABDOPQRCGSMX")
    for i, ch in enumerate(s):
        if ch not in cut:
            continue
        left = x + (dc.text_width(s[:i], size, fnt, spacing) + spacing if i else 0.0)
        cw = dc.text_width(ch, size, fnt, 0.0)
        _stencil_cut(dc, left + cw / 2, y - size * 0.9, y + size * 0.9, size * 0.11)
    return x + dc.text_width(s, size, fnt, spacing)


def model_stencil(h=0.0064):
    """Front print: 'MX-905' bold stencil, an orange rule and 'TACTICAL' spaced stencil caps, centred."""
    hs = h * 0.64
    ts = hs * 0.50
    probe = DecalCanvas(0.002, 0.002, ppm=30000)
    w1 = probe.text_width("MX-905", hs, "label-black", hs * 0.06)
    w2 = probe.text_width("TACTICAL", ts, "label", ts * 0.22)
    gap = h * 0.30
    total = w1 + gap * 2 + h * 0.09 + w2
    pad = h * 0.15
    w = total + 2 * pad
    dc = DecalCanvas(w, h, ppm=30000)
    xe = stencil_text(dc, pad, h * 0.5, "MX-905", hs, fnt="label-black", spacing=hs * 0.06, **ink("white"))
    xr = xe + gap
    dc.rect(xr, h * 0.18, h * 0.09, h * 0.64, **ink("orange"))
    stencil_text(dc, xr + h * 0.09 + gap, h * 0.53, "TACTICAL", ts, fnt="label", spacing=ts * 0.22, cut=set("ACRL"), **ink("white"))
    return dc


def deck_canvas():
    """One print over the whole top deck (read from the front: canvas up = -Y): 16 channel positions on the raised
    ring, the volume scale with its OFF detent, labels, the emergency legend, the LED / antenna legends."""
    ppm = 30000
    dc = DecalCanvas(W, D, ppm)

    def C(x, y):                         # world (x, y) on the deck -> canvas (metres)
        return W / 2 - x, D / 2 + y

    # channel ring: 16 position ticks (1 at the front), bold every 4th, orange dot at position 1
    cx, cy = C(*P_CH)
    for k in range(16):
        a = math.radians(180 + k * 22.5)          # 0 = canvas up (= back), clockwise
        sx, sy = math.sin(a), -math.cos(a)
        r0, r1 = (0.0103, 0.0119) if k % 4 else (0.0102, 0.0123)
        dc.line([(cx + sx * r0, cy + sy * r0), (cx + sx * r1, cy + sy * r1)], 0.0006 if k % 4 else 0.0009, **ink("white"))
    dc.circle(cx, cy + 0.0129 + 0.0007, 0.0006, **ink("orange"))
    for k, lab in ((4, "5"), (8, "9"), (12, "13")):
        a = math.radians(180 + k * 22.5)
        sx, sy = math.sin(a), -math.cos(a)
        rr = 0.0136
        dc.text(cx + sx * rr, cy + sy * rr, lab, 0.0016, fnt="label-semi", **ink("white"))
    # volume: OFF detent + growing dots on the front arc
    vx, vy = C(*P_VOL)
    a_off = math.radians(108)
    dc.line([(vx + math.sin(a_off) * 0.0090, vy - math.cos(a_off) * 0.0090), (vx + math.sin(a_off) * 0.0107,
             vy - math.cos(a_off) * 0.0107)], 0.0007, **ink("white"))
    ox, oy = vx + math.sin(math.radians(93)) * 0.0118, vy - math.cos(math.radians(93)) * 0.0118
    dc.text(ox - 0.0002, oy - 0.0021, "OFF", 0.0016, fnt="label-semi", **ink("white"))
    for k in range(8):
        a = math.radians(126 + k * 15.0)
        rr = 0.0098
        dc.circle(vx + math.sin(a) * rr, vy - math.cos(a) * rr, 0.00026 + k * 0.00007, **ink("white"))
    tx, ty = C(P_VOL[0] - 0.0006, P_VOL[1] - 0.0118)
    dc.text(tx, ty, "VOL", 0.0018, fnt="label-semi", spacing=0.0002, **ink("white"))
    # emergency legend, LED legend, antenna legend
    ex, ey = C(P_EMERG[0] + 0.0118, P_EMERG[1] + 0.0004)
    dc.text(ex, ey, "EMER", 0.0021, fnt="label", spacing=0.0003, **ink("orange"))
    gx, gy = C(P_LED[0] - 0.0062, P_LED[1])
    dc.text(gx, gy, "TX/RX", 0.0016, fnt="label-semi", spacing=0.0002, **ink("white"))
    ax_, ay_ = C(P_ANT[0] - 0.0004, P_ANT[1] + 0.0098)
    dc.text(ax_, ay_, "ANT 50Ω", 0.0014, fnt="label-semi", **ink("grey"))
    return dc


def front_prints():
    """Small prints on the front face: 'MIC' beside the port, an ingress badge."""
    mic = DecalCanvas(0.008, 0.003, ppm=30000)
    mic.text(0.004, 0.0015, "MIC", 0.0016, fnt="label-semi", spacing=0.0002, **ink("white"))
    badge = DecalCanvas(0.0082, 0.0036, ppm=30000)
    badge.rect(0.0002, 0.0002, 0.0078, 0.0032, r=0.0006, fill=False, width=0.00024, **ink("grey"))
    badge.text(0.0041, 0.0018, "IP68", 0.0017, fnt="label-semi", spacing=0.0001, **ink("grey"))
    return mic, badge


def key_legend(w, h, digit, sub):
    """Keypad legend: big digit left of centre, small letters / symbol right (white pad print)."""
    dc = DecalCanvas(w, h, ppm=60000)
    sym = len(sub) == 1 and not sub.isalpha() and sub not in ".,?"
    dc.text(w * (0.36 if not sym else 0.38), h * 0.52, digit, h * (0.62 if digit not in "*#" else 0.58), fnt="label", **ink("white"))
    if sym:
        dc.text(w * 0.66, h * 0.50, sub, h * 0.52, fnt="sans-bold", **ink("white"))
    else:
        dc.text(w * 0.71, h * 0.55, sub, h * 0.33, fnt="label", max_w=w * 0.42, **ink("white"))
    return dc


# ---------------------------------------------------------------------------------------------
# the radio
# ---------------------------------------------------------------------------------------------
@radio("military", title="MX-905 tactical handheld", code="MX-905", layers={"face": 1024}, part_boost=4.0, maps={"face": {"n": 512, "s": 512}},
       doc={"screen": "nzr_scr 512 x 384, colour LCD 42 x 32 mm behind smoked glass (mx905 skin)"})
def military(r):
    green = m_ranger_green(r)
    face = _face_mat(r, green, "mx_face")
    rub = m_bumper_rubber(r)
    blk = m_soft_black(r)
    _housing(r, green, face, rub)
    _front(r, green, face, blk)
    _front_parts(r)
    insert = _top(r, green, face, rub)
    _left(r, green, face)
    _rating_plate(r)
    _right(r, green, face)
    _back(r, green, face)
    _medium(r, green, rub)
    for c in r.geo.charts:               # the pressable parts are high-detail only (the medium model has stand-ins)
        if c.part is not None:
            c.lod = "h"
    r.anchor(focus=(0.0, FY, 0.020), camDist=0.36, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422): palm on the battery box / strap plate, thumb on the PTT (+X side), antenna up; "
                  "tune with /radiogrip")


# ---------------------------------------------------------------------------------------------
# housing: front shell, rear top cover, battery box, bumpers
# ---------------------------------------------------------------------------------------------
def _housing(r, green, face, rub):
    shell = housing(r, green, W, DF, H, z0=Z0, center=(0.0, FY - DF / 2), chamfer=CHAMF, fillet=FIL, rim=RIM)
    _set_mats(shell, {"housing:side:+y": face, "housing:side:-x": face, "housing:top:+z": face, "housing:side:+z": face,
                      "housing:bot:-z": face})
    r.add(shell)
    cover = battery_pack(r, green, W, DB, ZT - Z_TC, YS, Z_TC, gap=GAP, chamfer=CHAMF, fillet=FIL, rim=RIM)
    _set_mats(cover, {"battery:side:-y": face, "battery:top:+z": face, "battery:side:+z": face})
    r.add(cover)
    grip = m_battery_green(r)
    bat = battery_pack(r, green, W, DB, Z_TC - GAP - Z0, YS, Z0, gap=GAP, chamfer=CHAMF, fillet=FIL, rim=RIM)
    _set_mats(bat, {"battery:bot:-z": face, "battery:side:+x": grip, "battery:side:-x": grip})
    r.add(bat)
    for sx in (1, -1):                   # silhouette: kept in the medium model too
        for sy in (1, -1):
            for top in (True, False):
                r.add(corner_bumper(rub, sx, sy, top))


# ---------------------------------------------------------------------------------------------
# front: frame, screen + lip, cluster wells, keypad wells, speaker, prints
# ---------------------------------------------------------------------------------------------
def _front(r, green, face, blk):
    fw, fh, fcr, fbw, ft = FRAME
    with _hi(r):
        r.add(align(rr_ring(fw, fh, fcr, fbw, ft, green, bevel=0.0005, tag="frame", n=2), (0, 1, 0), (0, 0, 1), (0.0, FY, Z_FRAME)))
        pts = [(sx * X_SCREW, FY + ft, z) for sx in (1, -1) for z in Z_SCREWS]
        r.add(screws(r, pts, (0, 1, 0), d=0.0030, kind="torx", color=(64, 66, 62), segs=9))
    # screen window + raised lip round the black bezel
    screen_window(r, center=(0.0, FY, Z_SCREEN), view=(0.042, 0.032), bezel=0.001, recess=0.0012, margin=(0.0015, 0.0025),
                  frame_mat=blk, corner=0.0008)
    r.add(align(rr_ring(0.0506, 0.0426, 0.0032, 0.0018, 0.0026, green, n=4), (0, 1, 0), (0, 0, 1), (0.0, FY, Z_SCREEN)))
    print_decal(r, model_stencil(), center=(0.0, FY, Z_PRINT), normal=(0, 1, 0), mats=[face], depth=0.0012)
    # control cluster plate: back / menu (left column), d-pad well, tall OK (right)
    cx_l = 0.0185
    kw, kh, gap = 0.0085, 0.0060, 0.0005
    holes = [(0.0, 0.0, 0.0080 + gap, 0.0080 + gap, 0.0028 + gap),                       # dpad (16 mm square-ish)
             (-cx_l, 0.0050, kw / 2 + gap, kh / 2 + gap, 0.0016 + gap),                 # kback (plate x = viewer's right)
             (-cx_l, -0.0050, kw / 2 + gap, kh / 2 + gap, 0.0016 + gap),                # kup
             (cx_l, 0.0, kw / 2 + gap, 0.0070 + gap, 0.0020 + gap)]                     # kok (tall)
    with _hi(r):
        wells(r, green, (0.0, FY, Z_CLUSTER), (0, 1, 0), (0, 0, 1), (0.0500, 0.0206), 0.0012, holes, depth=0.0012, floor_mat=m_well_floor(r),
              corner_n=3)
    floor_caps(r, holes, (0.0, FY, Z_CLUSTER), (-1, 0, 0), (0, 0, 1))
    # keypad surround: one plate with 12 wells (3-step corners)
    px, py = KP_PITCH
    w, h = KP_SIZE
    cr = 0.0019
    holes = [((ci - 1) * px, (1.5 - ri) * py, w / 2 + gap, h / 2 + gap, cr + gap) for ri in range(4) for ci in range(3)]
    pw = 2 * (px + w / 2 + gap + 0.0019)
    ph = 2 * (1.5 * py + h / 2 + gap + 0.0019)
    with _hi(r):
        wells(r, green, (0.0, FY, Z_KEYPAD), (0, 1, 0), (0, 0, 1), (pw, ph), 0.0012, holes, depth=0.0012, floor_mat=m_well_floor(r), corner_n=2)
    floor_caps(r, holes, (0.0, FY, Z_KEYPAD), (-1, 0, 0), (0, 0, 1))
    # speaker hole array + mic port
    with _hi(r):
        r.add(grille_holes(r, (0.0, FY, Z_SPEAKER), cols=10, rows=4, pitch=0.0026, hole_r=0.00064, t=0.0008, margin=0.0013,
                           mat=green, corner_n=1))
        r.add(grille_holes(r, (0.0190, FY, Z_SPEAKER + 0.0010), cols=1, rows=1, pitch=0.002, hole_r=0.0006, t=0.0006, margin=0.0009,
                           mat=green))
    mic, badge = front_prints()
    print_decal(r, mic, center=(0.0190, FY, Z_SPEAKER - 0.0028), normal=(0, 1, 0), mats=[face], depth=0.0012)
    print_decal(r, badge, center=(-0.0190, FY, Z_SPEAKER + 0.0010), normal=(0, 1, 0), mats=[face], depth=0.0012)


def _front_parts(r):
    key_black = m_keypad_rubber(r, "black")
    key_grey = m_keypad_rubber(r, "grey")
    cx_l = 0.0185
    kw, kh = 0.0085, 0.0060
    key(r, "kback", at=(cx_l, FY + LIFT, Z_CLUSTER + 0.0050), size=(kw, kh), t=0.0022, mat=key_black, corner=0.0016, glyph="ring",
        color="white", depth=0.0013)
    key(r, "kup", at=(cx_l, FY + LIFT, Z_CLUSTER - 0.0050), size=(kw, kh), t=0.0022, mat=key_black, corner=0.0016, glyph="up",
        glyph_color=INK["green"], color="green", depth=0.0013, action="menu")
    key(r, "kok", at=(-cx_l, FY + LIFT, Z_CLUSTER), size=(kw, 0.0140), t=0.0022, mat=key_black, corner=0.0020, glyph="check",
        glyph_color=INK["red"], color="red", depth=0.0013, legend_size=0.0045)
    _dpad(r, key_grey)
    px, py = KP_PITCH
    w, h = KP_SIZE
    for ri, row in enumerate(KEYPAD):
        for ci, (pid, legend, sub) in enumerate(row):
            x = -(ci - 1) * px
            z = Z_KEYPAD + (1.5 - ri) * py
            key(r, pid, at=(x, FY + LIFT, z), size=(w, h), t=0.0021, mat=key_grey, corner=0.0019, dome=0.0003, bevel=0.0006,
                canvas=key_legend(w * 0.92, h * 0.88, legend, sub), depth=0.0014)


def _dpad(r, mat):
    """Grey square-ish 4-way rocker (16 mm) with four raised chevron ridges and a dished centre dot."""
    size, t, dome = 0.016, 0.0024, 0.00025
    at = vec(0.0, FY + LIFT, Z_CLUSTER)
    origin = at + vec(0, 1, 0) * (t + dome)
    with r.part("dpad", origin=origin, press=(0, -1, 0), depth=0.0010, u=(-size / 2, 0, 0), v=(0, 0, size / 2), shape="round",
                action="dpad", tilt=5.0):
        g = key_cap(mat, size, size, t, corner=0.0028, dome=dome, bevel=0.0007)
        for ang in (0, 90, 180, 270):
            rg = extrude(chevron(0.0019, 0.0007), 0.0007, mat, bevel=0.00018, bevel_seg=1, z0=t - 0.0001, caps=(False, True),
                         smooth_angle=40, tag="ridge")
            rg.translate(0, size * 0.27, 0).rotate(0, 0, ang)
            g += rg
        r.add(align(g, (0, 1, 0), (0, 0, 1), at))
        dc = DecalCanvas(size, size, ppm=40000)
        dc.circle(size / 2, size / 2, 0.0011, fill=False, width=0.00028, **ink("white", alpha=0.85))
        r.decal(dc, center=origin, normal=(0, 1, 0), up=(0, 0, 1), depth=dome + 0.0012, min_dot=0.6)


# ---------------------------------------------------------------------------------------------
# top deck: antenna, channel knob in its marked ring, volume, guarded emergency key, light pipe
# ---------------------------------------------------------------------------------------------
def _top(r, green, face, rub):
    ax, ay = P_ANT
    fer = r.mat("mx_ferrule", color=(36, 37, 39), spec=0.55, gloss=0.5, metal=0.8, bump="ribs", bump_amp=0.00004,
                bump_scale=0.0006, edge=0.4, dirt=0.15)
    with _hi(r):
        r.add(cylinder(0.0058, 0.0022, green, segs=28, bevel=0.0006, bevel_seg=2, caps=(False, True), z0=ZT - 0.0003)
              .translate(ax, ay, 0))
        r.add(sma_nut(r, (ax, ay, ZT + 0.0019), across=0.0095, h=0.0040, finish="black", barrel_h=0.0028))
    zf = ZT + 0.0019 + 0.0040 + 0.0028
    with _hi(r):
        r.add(lathe([(0.0, 0.0), (0.0042, 0.0), (0.0045, 0.0005), (0.0045, 0.0034), (0.0040, 0.0040), (0.0, 0.0040)], fer, segs=20,
                    smooth_angle=45, tag="antenna_ferrule").translate(ax, ay, zf))
        zg = zf + 0.0040
        coil = r.mat("mx_coil", color=(30, 31, 33), spec=0.42, gloss=0.42, metal=0.9, edge=0.55, dirt=0.2, wear_color=(110, 112, 116),
                     scratch=0.3)
        r.add(gooseneck(r, (ax, ay, zg), length=0.040, coil_r=0.0041, wire_r=0.0013, n_per_turn=9, segs=5, mat=coil))
        zw = zg + 0.040
        r.add(lathe([(0.0, -0.0004), (0.0043, -0.0004), (0.0045, 0.0002), (0.0045, 0.0036), (0.0040, 0.0044), (0.0, 0.0044)], fer,
                    segs=20, smooth_angle=45, tag="antenna_ferrule").translate(ax, ay, zw))
        r.add(whip_antenna(r, (ax, ay, zw + 0.0044), length=ZT + 0.220 - (zw + 0.0044), d0=0.0076, d1=0.0040, collar_h=0.010,
                           collar_ribs=3, cap="ball", segs=12))

    # channel knob: boss + raised ring with 16 printed positions + large ribbed / knurled knob, guard flange, pointer
    cxk, cyk = P_CH
    with _hi(r):
        r.add(boss(r, green, (cxk, cyk, ZT), d=0.0185, h=0.0019, shaft_d=0.006, shaft_h=0.0055, shaft_mat=m_gunmetal(r)))
        r.add(ring(face, 0.0200, 0.0256, 0.0016, segs=36, bevel=0.0005, tag="guard").translate(cxk, cyk, ZT))
    knob(r, "knob_ch", base=(cxk, cyk, ZT + 0.0019 + LIFT), d=0.018, h=0.0150, style="ribbed", ribs=16, rib_depth=0.00045, skirt=True,
         skirt_d=0.0198, skirt_h=0.0026, mat=m_knob_knurl(r), cap_mat=m_knob_cap(r), index="line", value="channel", detents=16, segs=56)
    with r.part("knob_ch"):
        # raised pointer bar on the top from the centre to the front edge (white filled)
        ptr = box((0.0026, 0.0078, 0.0010), m_knob_cap(r), r=0.0004, seg=1, center=(0.0, 0.0040, 0.0005), faces="+x -x +y -y +z")
        r.add(ptr.translate(cxk, cyk, ZT + 0.0019 + LIFT + 0.0150 - 0.0001))
    # volume knob: fluted, knurled, dot + line index
    vx, vy = P_VOL
    with _hi(r):
        r.add(boss(r, green, (vx, vy, ZT), d=0.0172, h=0.0016, shaft_d=0.0055, shaft_h=0.005, shaft_mat=m_gunmetal(r)))
    knob(r, "knob_vol", base=(vx, vy, ZT + 0.0016 + LIFT), d=0.016, h=0.0125, style="ribbed", ribs=10, rib_depth=0.00035, skirt=True,
         skirt_d=0.0170, skirt_h=0.0018, mat=m_knob_knurl(r, "mx_knob_knurl_v"), cap_mat=m_knob_cap(r), index="line", value="volume", detents=24,
         segs=44)
    # emergency key recessed in a rubber guard ring
    exk, eyk = P_EMERG
    with _hi(r):
        r.add(cylinder(0.0050, 0.0002, m_well_floor(r), segs=24, caps=(False, True), z0=ZT - 0.0001).translate(exk, eyk, 0))
        r.add(ring(rub, 0.0106, 0.0154, 0.0031, segs=28, bevel=0.0008, tag="guard").translate(exk, eyk, ZT))
    key(r, "emerg", at=(exk, eyk, ZT + 0.0001 + LIFT), normal=(0, 0, 1), up=(0, -1, 0), size=(0.0085, 0.0085), corner=0.00425, t=0.0020,
        mat=m_emerg_orange(r), dome=0.0004, depth=0.0012, shape="round")
    # LED light pipe
    pipe, insert = light_pipe(r, (P_LED[0], P_LED[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), d=0.0032, color="green")
    with _hi(r):
        r.add(pipe)
    print_decal(r, deck_canvas(), center=(0.0, 0.0, ZT + 0.004), normal=(0, 0, 1), up=(0, -1, 0), depth=0.0065, mats=[face],
                min_dot=0.6)
    return insert


# ---------------------------------------------------------------------------------------------
# left side (+X): guarded PTT, two side keys in round collars
# ---------------------------------------------------------------------------------------------
def _left(r, green, face):
    key_black = m_keypad_rubber(r, "black")
    z_ptt = 0.0400
    with _hi(r):
        floor = well_for(r, green, (SX, YSIDE, z_ptt), (1, 0, 0), (0, 0, 1), (0.0130, 0.0320), gap=0.0005, margin=0.0016, t=0.0014,
                         corner=0.0050, floor_mat=m_well_floor(r))
    floor_caps(r, [(0.0, 0.0, 0.0130 / 2 + 0.0005, 0.0320 / 2 + 0.0005)], (SX, YSIDE, z_ptt), (0, 1, 0), (0, 0, 1))
    mx_ptt(r, (SX + floor + LIFT, YSIDE, z_ptt), key_black)
    with _hi(r):
        r.add(guard_ribs(green, (SX - 0.0002, YSIDE, z_ptt), 0.0410))
    dark = m_well_floor(r)
    for pid, z, dots in (("side1", 0.0110, 1), ("side2", -0.0010, 2)):
        with _hi(r):
            r.add(align(round_collar(green, dark, 0.0076, 0.0104, 0.0010), (1, 0, 0), (0, 0, 1), (SX, YSIDE, z)))
        d = 0.0066
        key(r, pid, at=(SX + LIFT, YSIDE, z), normal=(1, 0, 0), up=(0, 0, 1), size=(d, d), t=0.0018, mat=key_black, corner=d / 2,
            dome=0.0003, depth=0.0010, shape="round")
        # tactile dots (moulded, unprinted)
        with r.part(pid):
            dc = DecalCanvas(d, d, ppm=40000)
            for k in range(dots):
                off = (k - (dots - 1) / 2) * 0.0017
                dc.circle(d / 2 + off, d / 2, 0.00045, color=(44, 45, 48), height=0.00022, spec=0.3, gloss=0.45)
            r.decal(dc, center=(SX + LIFT + 0.0018 + 0.0003, YSIDE, z), normal=(1, 0, 0), up=(0, 0, 1), depth=0.0012, min_dot=0.6)


def _rating_plate(r):
    """Anodised rating plate on the lower left side (thin plate + engraved light print)."""
    plate = m_rating_plate(r)
    pw, ph, zc = 0.0200, 0.0130, -0.0270
    with _hi(r):
        r.add(box((0.0004, pw, ph), plate, r=0.00018, seg=1, center=(SX + 0.0002, YSIDE, zc), faces="+x +y -y +z -z"))
    rp = rating_plate(pw - 0.0006, ph - 0.0006, title="TACTICAL RADIO", model="MX-905", serial="SN 26-90517", ref="TXQ-MX905T",
                      rating="7.4 V  3400 mAh  Li-ion", ppm=40000, bg=(44, 46, 42), ink=(206, 208, 200), ref_label="ID",
                      foot="IP68  1 m")
    print_decal(r, rp, center=(SX + 0.0004, YSIDE, zc), normal=(1, 0, 0), up=(0, 0, 1), mats=[plate], depth=0.0008)


# ---------------------------------------------------------------------------------------------
# right side (-X): bayonet accessory connector, tethered dust cap, rating plate
# ---------------------------------------------------------------------------------------------
def _right(r, green, face):
    z_acc = 0.0440
    with _hi(r):
        r.add(cylinder(0.0090, 0.0010, green, segs=32, bevel=0.0005, bevel_seg=2, caps=(False, True)).rotate(0, -90, 0)
              .translate(-SX, YSIDE, z_acc))
        r.add(bayonet_connector(r, (-SX - 0.0010, YSIDE, z_acc), (-1, 0, 0), d=0.0125, pins=6, depth=0.0032))
        # moulded strap from the connector boss down to the hanging cap
        strap = r.mat("mx_strap_rubber", color=(24, 25, 26), spec=0.12, gloss=0.2, bump="rubber", bump_amp=0.00004,
                      bump_scale=0.0005, edge=0.3, dirt=0.2)
        sp = np.array([(-SX - 0.0005, YSIDE, z_acc - 0.0082), (-SX - 0.0016, YSIDE, z_acc - 0.0110),
                       (-SX - 0.0018, YSIDE, z_acc - 0.0150), (-SX - 0.0014, YSIDE, z_acc - 0.0172)])
        r.add(sweep(rrect(0.0040, 0.0011, 0.0005, 2), sp, strap, side=(0, 1, 0), tag="capstrap", smooth_angle=60))
        r.add(dust_cap(r, (-SX - 0.0002, YSIDE, z_acc - 0.0246), (-1, 0, 0), (0, 0, 1)))
    acc = DecalCanvas(0.012, 0.0036, ppm=30000)
    acc.text(0.006, 0.0018, "ACC", 0.0018, fnt="label-semi", spacing=0.0003, **ink("white"))
    print_decal(r, acc, center=(-SX, YSIDE, z_acc + 0.0118), normal=(-1, 0, 0), up=(0, 0, 1), mats=[face], depth=0.0012)
    # rubber grip insert on the lower right side (where the fingers wrap round), diamond tread
    grip = r.mat("mx_grip_insert", color=(25, 26, 27), spec=0.11, gloss=0.2, bump="diamond", bump_amp=0.00012, bump_scale=0.0016,
                 grain=0.04, grain_scale=0.03, edge=0.35, dirt=0.2, wear_color=(66, 68, 70))
    gp = extrude(rrect(0.0170, 0.0460, 0.0030, 3), 0.0009, grip, bevel=0.00042, bevel_seg=2, caps=(False, True), smooth_angle=50,
                 tag="grip_insert")
    r.add(align(gp, (-1, 0, 0), (0, 0, 1), (-SX, 0.00425, -0.0190)))


# ---------------------------------------------------------------------------------------------
# back: over-centre latches, strap mount plate + webbing, prints; bottom: contacts, battery label
# ---------------------------------------------------------------------------------------------
def _back(r, green, face):
    with _hi(r):
        for x in (0.0165, -0.0165):
            r.add(over_centre_latch(r, x, z_pivot=0.0420, z_keeper=0.0618, y_face=YB))
        strap_plate(r, m_strap_plate(r), m_mx_webbing(r), center_z=-0.0080)
    print_decal(r, battery_label(0.034, 0.012, pack="MB-90", volts="7.4 V", cap="3400 mAh", serial="SN B26-90233"),
                center=(0.0, YB + DB / 2 - 0.0002, Z0), normal=(0, 0, -1), up=(0, 1, 0), mats=[face], depth=0.002)
    print_decal(r, caution_label(0.026, 0.012, "CAUTION", ["Close both latches before use", "Li-ion: do not open or burn"], ppm=30000),
                center=(0.0, YB, 0.0752), normal=(0, -1, 0), up=(0, 0, 1), mats=[face], depth=0.0012)
    with _hi(r):
        r.add(charging_contacts(r, (0.0, YSIDE + 0.001, Z0), (0, 0, -1), (0, 1, 0), pitch=0.009, size=(0.0045, 0.0028)))


# ---------------------------------------------------------------------------------------------
# medium LOD stand-ins (6 m -> 40 m): silhouette + colour blocks only
# ---------------------------------------------------------------------------------------------
def _medium(r, green, rub):
    blk = m_soft_black(r)
    key_black = m_keypad_rubber(r, "black")
    key_grey = m_keypad_rubber(r, "grey")
    knob_m = m_knob_knurl(r)
    g = Geo()
    # front plates: cluster + keypad surround as flat dark slabs, keys as flat blocks
    g += box((0.050, 0.0012, 0.0206), green, center=(0.0, FY + 0.0006, Z_CLUSTER), faces="+x -x +y +z -z")
    px, py = KP_PITCH
    w, h = KP_SIZE
    g += box((2 * px + w + 0.004, 0.0012, 3 * py + h + 0.004), blk, center=(0.0, FY + 0.0006, Z_KEYPAD), faces="+x -x +y +z -z")
    for ri in range(4):
        for ci in range(3):
            g += box((w, 0.0022, h), key_grey, center=(-(ci - 1) * px, FY + 0.0012 + 0.0011, Z_KEYPAD + (1.5 - ri) * py),
                     faces="+x -x +y +z -z")
    g += box((0.016, 0.0024, 0.016), key_grey, center=(0.0, FY + 0.0024, Z_CLUSTER), faces="+x -x +y +z -z")
    for x, z, hh in ((0.0185, Z_CLUSTER + 0.005, 0.006), (0.0185, Z_CLUSTER - 0.005, 0.006), (-0.0185, Z_CLUSTER, 0.014)):
        g += box((0.0085, 0.0024, hh), key_black, center=(x, FY + 0.0024, z), faces="+x -x +y +z -z")
    # grille: one dark patch
    g += box((0.028, 0.0004, 0.010), blk, center=(0.0, FY + 0.0002, Z_SPEAKER), faces="+y")
    # knobs + emergency key
    g += cylinder(0.0090, 0.0170, knob_m, segs=12, z0=ZT).translate(P_CH[0], P_CH[1], 0)
    g += cylinder(0.0080, 0.0141, knob_m, segs=12, z0=ZT).translate(P_VOL[0], P_VOL[1], 0)
    g += cylinder(0.0062, 0.0030, m_emerg_orange(r), segs=10, z0=ZT).translate(P_EMERG[0], P_EMERG[1], 0)
    # antenna: one tapered lathe from the nut to the ball tip
    ax, ay = P_ANT
    zt = ZT + 0.220
    ant = lathe([(0.0, ZT), (0.0050, ZT), (0.0050, ZT + 0.009), (0.0045, ZT + 0.060), (0.0036, ZT + 0.075), (0.0020, zt - 0.006),
                 (0.0030, zt - 0.003), (0.0, zt)], knob_m, segs=8, smooth_angle=60, tag="antenna_med")
    g += ant.translate(ax, ay, 0)
    # PTT + guard, connector, latches + strap plate as blocks
    g += box((0.0040, 0.0150, 0.0440), key_black, center=(SX + 0.0018, YSIDE, 0.0400), faces="+x +y -y +z -z")
    g += cylinder(0.0070, 0.0040, m_gunmetal(r), segs=10).rotate(0, -90, 0).translate(-SX, YSIDE, 0.0440)
    g += box((0.046, 0.0022, 0.084), m_strap_plate(r), center=(0.0, YB - 0.0011, -0.0080), faces="+x -x -y +z -z")
    for x in (0.0165, -0.0165):
        g += box((0.012, 0.0030, 0.022), m_latch_steel(r), center=(x, YB - 0.0015, 0.051), faces="+x -x -y +z -z")
    _med(r, g)
