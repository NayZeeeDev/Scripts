"""
MX-905 TACTICAL - rugged military handheld (PROPS_BRIEF section 3, SPEC section 9).

    nzr_military           complete radio (idle mx905 screen, medium LOD)
    nzr_military_body      the same without its pressable parts (key wells, knob bosses + D-shafts, PTT pocket)
    nzr_military_<pid>     k0..k9 kstar khash kok kback kup(-> menu) dpad knob_ch knob_vol emerg ptt side1 side2

Body 66 W x 42 D x 150 H mm, ranger-green polymer chassis: front shell + rear top cover + battery box
(seams all round), black rubber corner bumpers on all 8 corners, a front frame with 6 Torx screws, a
raised lip around the black screen bezel (colour LCD 42 x 32 mm, 512 x 384), control cluster (back,
menu, square d-pad with arrow ridges, tall OK key), 4 x 3 grey keypad, speaker hole array + mic port.
Top: large knurled channel knob in a raised ring with 16 printed positions, volume knob with an OFF
detent, orange emergency key recessed in a guard ring, LED light pipe, coil-spring gooseneck + tapered
whip with a ball tip (220 mm). Left: guarded PTT with two guard ribs, two side keys. Right: 6-pin
bayonet accessory connector with a tethered dust cap, rating plate. Back: battery box with two
over-centre draw latches, MOLLE-style strap mount plate with webbing slots.

Labelling: "MX-905" + "TACTICAL" stencil print, rating plate, battery label, fine print - no maker
name, no NAYZEEE mark (Rule B).

Axes: metres, +Z up (antenna), +Y = front face, +X = viewer's left. Origin = grip point (body
cross-section centre at 40 % of the body height from its bottom).
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import DecalCanvas, Geo, box, cylinder, extrude, fillet_poly, lathe, rr_lathe, tube, vec
from nzprops.mesh import chamfer_fillet_rect

from .common import align, caution_label, screw, screws
from .radio_common import (INK, battery_label, battery_pack, boss, gooseneck, grille_holes, guard_ring, housing, ink, key,
                           knob, light_pipe, m_bumper_rubber, m_gunmetal, m_keypad_rubber, m_print_dark, m_ranger_green,
                           m_sma, m_soft_black, m_spring_steel, print_decal, ptt, rating_label, round_button,
                           round_connector, screen_window, sma_nut, well_for, wells, whip_antenna)
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
CHAMF, FIL, RIM = 0.0035, 0.0012, 0.0012
SX = W / 2                    # side faces at +-SX
YSIDE = (FY + YS) / 2         # centre line of the front shell's side faces (0.0075)
Z_TOPCOVER = 0.0598           # rear top cover / battery box split height

# front face layout (z of centres)
Z_SCREEN = 0.0525
Z_PRINT = 0.0815
Z_CLUSTER = 0.0175
Z_KEYPAD = -0.0145
Z_SPEAKER = -0.0485
X_SCREW = 0.0276
Z_SCREWS = (0.0695, 0.0105, -0.0405)

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


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def m_emerg_orange(r):
    return r.mat("mx_emerg_orange", color=(236, 104, 22), spec=0.42, gloss=0.55, bump="dimple", bump_amp=0.00007,
                 bump_scale=0.0008, grain=0.03, edge=0.45, dirt=0.12, wear_color=(250, 160, 90))


def m_knob_knurl(r, name="mx_knob_knurl"):
    return r.mat(name, color=(26, 27, 29), spec=0.26, gloss=0.36, bump="knurl", bump_amp=0.00011, bump_scale=0.0008,
                 grain=0.03, grain_scale=0.02, edge=0.55, dirt=0.18, wear_color=(92, 94, 98), scratch=0.2)


def m_latch_steel(r):
    return r.mat("mx_latch_steel", color=(58, 61, 58), spec=0.6, gloss=0.5, metal=1.0, bump="brushed", bump_amp=0.000008,
                 bump_scale=0.0004, grain=0.03, edge=0.75, dirt=0.25, wear_color=(168, 170, 166), scratch=0.45)


def m_strap_plate(r):
    return r.mat("mx_strap_plate", color=(30, 31, 30), spec=0.2, gloss=0.3, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0005, grain=0.035, grain_scale=0.03, edge=0.6, dirt=0.25, wear_color=(84, 86, 82), cavity=0.6)


def m_cap_rubber(r):
    return r.mat("mx_cap_rubber", color=(24, 25, 26), spec=0.12, gloss=0.2, bump="knurl", bump_amp=0.00008,
                 bump_scale=0.0009, grain=0.04, edge=0.3, dirt=0.2, wear_color=(66, 68, 70))


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


def corner_bumper(r, mat, sx, sy, top):
    """Moulded rubber corner cap: the housing outline grown by BUMPER_E, clipped to one corner quadrant
    (BUMPER_A along X, BUMPER_B along Y), extruded BUMPER_H tall over the top (or bottom) corner."""
    e = BUMPER_E
    outline = chamfer_fillet_rect(W + 2 * e, D + 2 * e, CHAMF + e * 0.4, FIL + e, 2)
    poly = [tuple(p) for p in outline]
    poly = _clip(poly, sx, 0.0, SX - BUMPER_A)
    poly = _clip(poly, 0.0, sy, FY - BUMPER_B)
    poly = fillet_poly(np.asarray(poly), 0.0011, 2)
    if top:
        z0 = ZT + e - BUMPER_H
        caps = (False, True)
    else:
        z0 = Z0 - e
        caps = (True, False)
    g = extrude(poly, BUMPER_H, mat, bevel=0.0013, bevel_seg=2, z0=z0, caps=caps, smooth_angle=50, tag="bumper")
    return g


def rr_ring(w, h, cr, ring_w, t, mat, bevel=0.0006, tag="lip"):
    """Raised rounded-rectangle ring (lip) standing on z = 0 facing +Z: outer w x h (corner cr), ring_w wide,
    t tall, rounded top edges. Built with rr_lathe (outer wall up, over the top, inner wall down)."""
    bv = min(bevel, t * 0.45, ring_w * 0.3)
    prof = [(0.0, 0.0), (0.0, t - bv)]
    prof += [(bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 3)]
    prof += [(ring_w - bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(math.pi / 2, 0.3, 3)]
    prof += [(ring_w, t - bv), (ring_w, 0.0)]
    return rr_lathe(w, h, cr, prof, mat, n=5, tag=tag)


def over_centre_latch(r, x, z_pivot, z_keeper, y_face, y_cover):
    """Over-centre draw latch on the back: base bracket + pivot barrel + lever plate on the battery box
    (y_face), wire bail hooking the keeper on the rear top cover (y_cover). Back faces look along -Y."""
    st = m_latch_steel(r)
    g = Geo()
    # base bracket riveted to the battery box
    g += box((0.0125, 0.0018, 0.0075), st, r=0.0006, seg=1, center=(x, y_face - 0.0009, z_pivot - 0.0012))
    # pivot barrel (along X)
    g += cylinder(0.0015, 0.0135, st, segs=14, bevel=0.0004, bevel_seg=1).rotate(0, 90, 0).translate(x - 0.00675, y_face - 0.0024,
                                                                                                         z_pivot)
    # lever plate lying on the box, slightly lifted at its free (top) end
    lev = box((0.0110, 0.0014, 0.0150), st, r=0.0006, seg=2, center=(0.0, 0.0, 0.0075))
    lev.rotate(-6, 0, 0)
    lev.translate(x, y_face - 0.0030, z_pivot)
    g += lev
    # finger lip at the top of the lever
    lip = box((0.0110, 0.0030, 0.0016), st, r=0.0006, seg=1, center=(0.0, -0.0010, 0.0148))
    lip.rotate(-6, 0, 0)
    lip.translate(x, y_face - 0.0030, z_pivot)
    g += lip
    # wire bail: a U from the lever's mid pivot up and over the keeper hook
    zb = z_pivot + 0.0065
    yk = y_cover - 0.0034
    for sx in (-1, 1):
        pts = np.array([(x + sx * 0.0047, y_face - 0.0043, zb), (x + sx * 0.0047, y_face - 0.0046, zb + 0.004),
                        (x + sx * 0.0047, yk - 0.0002, z_keeper - 0.0015), (x + sx * 0.0047, yk - 0.0003, z_keeper + 0.0003)])
        g += tube(pts, 0.0006, st, segs=6, tag="bail")
    g += tube(np.array([(x + 0.0047, yk - 0.0003, z_keeper + 0.0003), (x, yk - 0.0003, z_keeper + 0.0009),
                        (x - 0.0047, yk - 0.0003, z_keeper + 0.0003)]), 0.0006, st, segs=6, caps=True, tag="bail")
    # keeper (catch) on the top cover: a hooked block
    g += box((0.0120, 0.0024, 0.0050), st, r=0.0006, seg=1, center=(x, y_cover - 0.0012, z_keeper + 0.0018))
    g += box((0.0120, 0.0030, 0.0014), st, r=0.0005, seg=1, center=(x, y_cover - 0.0030, z_keeper + 0.0038))
    return g


def strap_plate(r, mat, center_z, w=0.046, h=0.084, t=0.0022, y_face=YB):
    """MOLLE-style strap mount plate on the battery box back: a plate with three webbing slot rows
    (rounded slots falling to the dark box face) and four screws."""
    holes = []
    for k in range(3):
        zc = (1 - k) * 0.0254
        holes.append((0.0, zc, 0.0155, 0.0019, 0.0019))
    g = wells(r, mat, (0.0, y_face, center_z), (0, -1, 0), (0, 0, 1), (w, h), t, holes, depth=t,
              floor_mat=r.mat("mx_slot_floor", color=(14, 15, 15), spec=0.1, gloss=0.2, ao=1.0))
    pts = [(sx * (w / 2 - 0.004), y_face - t, center_z + sz * (h / 2 - 0.004)) for sx in (-1, 1) for sz in (-1, 1)]
    r.hi_only(screws(r, pts, (0, -1, 0), d=0.0034, kind="hex", color=(70, 72, 70), segs=10))
    return g


def dust_cap(r, at, normal, up, d=0.0145):
    """Rubber dust cap (off, hanging on its strap): a knurled cup seen from its top."""
    m = m_cap_rubber(r)
    R = d / 2
    prof = [(0.0, 0.0), (R * 0.95, 0.0), (R, 0.0006), (R, 0.0032), (R - 0.0006, 0.0040), (R * 0.55, 0.0043), (0.0, 0.0043)]
    g = lathe(prof, m, segs=28, smooth_angle=45, tag="dustcap")
    return align(g, normal, up, at)


KP_PITCH = (0.0135, 0.0095)
KP_SIZE = (0.0100, 0.0070)


def military_keypad(r, plate_mat, key_mat, floor_mat, gap=0.0005, plate_t=0.0012, margin=0.0016):
    """4 x 3 keypad: one surround plate (wells with 3-step corners - cheaper than keypad()'s 4) + the keys."""
    px, py = KP_PITCH
    w, h = KP_SIZE
    cr = 0.0019
    cells, holes = [], []
    for ri, row in enumerate(KEYPAD):
        for ci, (pid, legend, sub) in enumerate(row):
            x = (ci - 1) * px                       # plate frame: x = viewer's right
            y = (1.5 - ri) * py
            cells.append((x, y, pid, legend, sub))
            holes.append((x, y, w / 2 + gap, h / 2 + gap, cr + gap))
    pw = 2 * (px + w / 2 + gap + margin + 0.0003)
    ph = 2 * (1.5 * py + h / 2 + gap + margin + 0.0003)
    wells(r, plate_mat, (0.0, FY, Z_KEYPAD), (0, 1, 0), (0, 0, 1), (pw, ph), plate_t, holes, depth=plate_t, floor_mat=floor_mat,
          corner_n=3)
    for x, y, pid, legend, sub in cells:
        key(r, pid, at=(-x, FY, Z_KEYPAD + y), size=(w, h), t=0.0021, mat=key_mat, corner=cr, dome=0.0003, legend=legend, sub=sub,
            color="white", depth=0.0014)


def guard_ribs(r, mat, at, length_span, rib_w=0.0032, rib_h=0.0034, rib_len=0.0170):
    """Two raised guard ribs above and below the PTT on the +X side: stadium-shaped, tapered, bevelled."""
    g = Geo()
    prof = fillet_poly(np.array([(-rib_len / 2, -rib_w / 2), (rib_len / 2, -rib_w / 2), (rib_len / 2, rib_w / 2),
                                 (-rib_len / 2, rib_w / 2)]), rib_w * 0.48, 3)
    for s in (1, -1):
        rb = extrude(prof, rib_h, mat, bevel=0.0009, bevel_seg=2, caps=(False, True), smooth_angle=50, tag="ptt_guard")
        rb.taper(0.0, rib_h, 1.0, 0.86)
        g += rb.translate(0, s * length_span / 2, 0)
    # +Z of the local frame -> +X (out of the side), local Y -> world Z, local X -> world -Y ... align does it
    return align(g, (1, 0, 0), (0, 0, 1), at)


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
    """Text with stencil bridges: a narrow vertical gap through the middle of the round / closed glyphs
    (left anchored at x, vertically centred on y). Returns the right edge (m)."""
    dc.text(x, y, s, size, fnt=fnt, anchor="lm", spacing=spacing, **ik)
    cut = cut if cut is not None else set("0689ABDOPQRCGSMX")
    for i, ch in enumerate(s):
        if ch not in cut:
            continue
        left = x + (dc.text_width(s[:i], size, fnt, spacing) + spacing if i else 0.0)
        cw = dc.text_width(ch, size, fnt, 0.0)
        _stencil_cut(dc, left + cw / 2, y - size * 0.9, y + size * 0.9, size * 0.11)
    return x + dc.text_width(s, size, fnt, spacing)


def model_stencil(w=0.044, h=0.0072):
    """Front print: 'MX-905' bold stencil, an orange rule and 'TACTICAL' spaced stencil caps."""
    dc = DecalCanvas(w, h, ppm=26000)
    hs = h * 0.62
    xe = stencil_text(dc, 0.0, h * 0.5, "MX-905", hs, fnt="label-black", spacing=hs * 0.06, **ink("white"))
    xr = xe + h * 0.28
    dc.rect(xr, h * 0.18, h * 0.09, h * 0.64, **ink("orange"))
    ts = hs * 0.52
    stencil_text(dc, xr + h * 0.3, h * 0.52, "TACTICAL", ts, fnt="label", spacing=ts * 0.32, cut=set("ACRL"), **ink("white"))
    return dc


def deck_canvas():
    """One print over the whole top deck (read from the front: canvas up = -Y): 16 channel positions on
    the raised ring, the volume scale with its OFF detent, labels, the emergency legend."""
    ppm = 22000
    dc = DecalCanvas(W, D, ppm)

    def C(x, y):                         # world (x, y) on the deck -> canvas (metres)
        return W / 2 - x, D / 2 + y

    # channel ring: 16 position ticks (1 at the front), bold every 4th, small dot at position 1
    cx, cy = C(*P_CH)
    for k in range(16):
        a = math.radians(180 + k * 22.5)          # 0 = canvas up (= back), clockwise
        sx, sy = math.sin(a), -math.cos(a)
        r0, r1 = 0.0104, 0.0118 if k % 4 else 0.0121
        dc.line([(cx + sx * r0, cy + sy * r0), (cx + sx * r1, cy + sy * r1)], 0.00042 if k % 4 else 0.0006, **ink("white"))
    dc.circle(cx, cy + 0.0129, 0.00045, **ink("orange"))
    lx, ly = C(P_CH[0], P_CH[1] + 0.0155)
    dc.text(lx, ly, "CH", 0.0016, fnt="label-semi", spacing=0.0002, **ink("white"))
    # volume: OFF detent + growing dots on the front arc
    vx, vy = C(*P_VOL)
    a_off = math.radians(112)
    dc.line([(vx + math.sin(a_off) * 0.0091, vy - math.cos(a_off) * 0.0091), (vx + math.sin(a_off) * 0.0106,
             vy - math.cos(a_off) * 0.0106)], 0.0006, **ink("white"))
    ox, oy = vx + math.sin(math.radians(96)) * 0.0118, vy - math.cos(math.radians(96)) * 0.0118
    dc.text(ox, oy - 0.0016, "OFF", 0.0013, fnt="label-semi", **ink("white"))
    for k in range(8):
        a = math.radians(128 + k * 15.5)
        rr = 0.0099
        dc.circle(vx + math.sin(a) * rr, vy - math.cos(a) * rr, 0.00022 + k * 0.00006, **ink("white"))
    tx, ty = C(P_VOL[0] - 0.0005, P_VOL[1] - 0.0115)
    dc.text(tx, ty, "VOL", 0.0015, fnt="label-semi", spacing=0.0002, **ink("white"))
    # emergency legend + LED legend
    ex, ey = C(P_EMERG[0] + 0.0115, P_EMERG[1])
    dc.text(ex, ey, "EMER", 0.0017, fnt="label", spacing=0.00025, **ink("orange"))
    gx, gy = C(P_LED[0] - 0.0055, P_LED[1])
    dc.text(gx, gy, "TX/RX", 0.0012, fnt="label-semi", spacing=0.00015, **ink("white"))
    ax_, ay_ = C(P_ANT[0], P_ANT[1] - 0.0105)
    dc.text(ax_, ay_, "ANT 50Ω", 0.0011, fnt="label-semi", **ink("grey"))
    return dc


def side_prints():
    """Small legends beside the left-side controls (canvas right = -Y ... see placement)."""
    dc = DecalCanvas(0.008, 0.026, ppm=22000)
    dc.text(0.004, 0.0028, "F1", 0.0015, fnt="label-semi", **ink("white"))
    dc.text(0.004, 0.0148, "F2", 0.0015, fnt="label-semi", **ink("white"))
    return dc


def front_fine_print():
    dc = DecalCanvas(0.012, 0.004, ppm=24000)
    dc.text(0.006, 0.002, "MIC", 0.0013, fnt="label-semi", spacing=0.0002, **ink("white"))
    return dc


# ---------------------------------------------------------------------------------------------
# the radio
# ---------------------------------------------------------------------------------------------
@radio("military", title="MX-905 tactical handheld", code="MX-905",
       doc={"screen": "nzr_scr 512 x 384, colour LCD 42 x 32 mm behind smoked glass (mx905 skin)"})
def military(r):
    green = m_ranger_green(r)
    rub = m_bumper_rubber(r)
    blk = m_soft_black(r)
    key_black = m_keypad_rubber(r, "black")
    key_grey = m_keypad_rubber(r, "grey")

    # --- housing: front shell, rear top cover, battery box (seams all round) ----------------------
    r.add(housing(r, green, W, DF, H, z0=Z0, center=(0.0, FY - DF / 2), chamfer=CHAMF, fillet=FIL, rim=RIM))
    r.add(battery_pack(r, green, W, D - DF - 0.0006, ZT - Z_TOPCOVER, YS, Z_TOPCOVER, chamfer=CHAMF, fillet=FIL, rim=RIM))
    r.add(battery_pack(r, green, W, D - DF - 0.0006, Z_TOPCOVER - 0.0006 - Z0, YS, Z0, chamfer=CHAMF, fillet=FIL, rim=RIM))
    for sx in (1, -1):
        for sy in (1, -1):
            for top in (True, False):
                r.add(corner_bumper(r, rub, sx, sy, top))

    # --- front: screen with a raised lip round the black bezel ------------------------------------
    sw = screen_window(r, center=(0.0, FY, Z_SCREEN), view=(0.042, 0.032), bezel=0.001, recess=0.0012, margin=(0.0015, 0.0025),
                       frame_mat=blk, corner=0.0008)
    _ = sw
    lip = rr_ring(0.0506, 0.0426, 0.0032, 0.0018, 0.0026, green)
    r.add(align(lip, (0, 1, 0), (0, 0, 1), (0.0, FY, Z_SCREEN)))
    # model print above the screen
    print_decal(r, model_stencil(), center=(0.0, FY, Z_PRINT), normal=(0, 1, 0), mats=[green])

    # --- control cluster: back / menu (left column), d-pad, tall OK (right) -----------------------
    cx_l, cx_r = 0.0185, -0.0185
    kw, kh, gap = 0.0085, 0.0060, 0.0005
    holes = [(0.0, 0.0, 0.0080 + gap, 0.0080 + gap, 0.0026 + gap),                       # dpad (16 mm square-ish)
             (-cx_l, 0.0050, kw / 2 + gap, kh / 2 + gap, 0.0016 + gap),                 # kback (viewer's left = -canvas x)
             (-cx_l, -0.0050, kw / 2 + gap, kh / 2 + gap, 0.0016 + gap),                # kup
             (-cx_r, 0.0, kw / 2 + gap, 0.0070 + gap, 0.0020 + gap)]                    # kok (tall)
    plate_t = 0.0012
    wells(r, green, (0.0, FY, Z_CLUSTER), (0, 1, 0), (0, 0, 1), (0.0500, 0.0206), plate_t, holes, depth=plate_t,
          floor_mat=blk, corner_n=3)
    yk = FY  # the well floor is the housing face (depth = plate thickness)
    key(r, "kback", at=(cx_l, yk, Z_CLUSTER + 0.0050), size=(kw, kh), t=0.0022, mat=key_black, corner=0.0016, glyph="ring",
        color="white", depth=0.0013)
    key(r, "kup", at=(cx_l, yk, Z_CLUSTER - 0.0050), size=(kw, kh), t=0.0022, mat=key_black, corner=0.0016, glyph="up",
        glyph_color=INK["green"], color="green", depth=0.0013, action="menu")
    key(r, "kok", at=(cx_r, yk, Z_CLUSTER), size=(kw, 0.0140), t=0.0022, mat=key_black, corner=0.0020, glyph="check",
        glyph_color=INK["red"], color="red", depth=0.0013, legend_size=0.0045)
    from .radio_common import dpad
    dpad(r, "dpad", at=(0.0, yk, Z_CLUSTER), size=0.016, kind="square", arrows="ridge", mat=key_grey, t=0.0024, tilt=5.0,
         depth=0.0010)

    # --- keypad 4 x 3 grey caps -----------------------------------------------------------------------
    military_keypad(r, green, key_grey, blk)

    # --- speaker hole array + mic port ------------------------------------------------------------------
    r.add(grille_holes(r, (0.0, FY, Z_SPEAKER), cols=11, rows=4, pitch=0.0025, hole_r=0.00064, t=0.0008, margin=0.0013,
                       mat=green, corner_n=1))
    r.add(grille_holes(r, (0.0195, FY, Z_SPEAKER), cols=1, rows=1, pitch=0.002, hole_r=0.0006, t=0.0006, margin=0.0009,
                       mat=green))
    print_decal(r, front_fine_print(), center=(0.0195, FY, Z_SPEAKER - 0.0042), normal=(0, 1, 0), mats=[green])

    # --- front frame: six Torx screws + the panel line ---------------------------------------------------
    pts = [(sx * X_SCREW, FY, z) for sx in (1, -1) for z in Z_SCREWS]
    r.hi_only(screws(r, pts, (0, 1, 0), d=0.0030, kind="torx", color=(64, 66, 62), segs=10))
    panel = DecalCanvas(0.0526, 0.142, ppm=9000)
    panel.groove_rect(0.0004, 0.0004, 0.0518, 0.1412, r=0.004, width=0.00045, depth=0.0002)
    r.decal(panel, center=(0.0, FY, (Z0 + ZT) / 2 + 0.0005), normal=(0, 1, 0), up=(0, 0, 1), mats=[green], depth=0.0008)

    # --- top deck: antenna, channel knob in its marked ring, volume, guarded emergency, light pipe ------
    ax, ay = P_ANT
    r.add(cylinder(0.0058, 0.0022, green, segs=32, bevel=0.0006, bevel_seg=2, caps=(False, True), z0=ZT - 0.0003)
          .translate(ax, ay, 0))
    r.add(sma_nut(r, (ax, ay, ZT + 0.0019), across=0.0095, h=0.0040, finish="black", barrel_h=0.0028))
    zf = ZT + 0.0019 + 0.0040 + 0.0028
    fer = r.mat("mx_ferrule", color=(36, 37, 39), spec=0.55, gloss=0.5, metal=0.8, bump="ribs", bump_amp=0.00004,
                bump_scale=0.0006, edge=0.4, dirt=0.15)
    r.add(lathe([(0.0, 0.0), (0.0042, 0.0), (0.0045, 0.0005), (0.0045, 0.0034), (0.0040, 0.0040), (0.0, 0.0040)], fer, segs=24,
                smooth_angle=45, tag="antenna_ferrule").translate(ax, ay, zf))
    zg = zf + 0.0040
    r.add(gooseneck(r, (ax, ay, zg), length=0.040, coil_r=0.0040, wire_r=0.0011, n_per_turn=9, segs=5))
    zw = zg + 0.040
    r.add(lathe([(0.0, -0.0004), (0.0043, -0.0004), (0.0045, 0.0002), (0.0045, 0.0036), (0.0040, 0.0044), (0.0, 0.0044)], fer, segs=24,
                smooth_angle=45, tag="antenna_ferrule").translate(ax, ay, zw))
    r.add(whip_antenna(r, (ax, ay, zw + 0.0044), length=ZT + 0.220 - (zw + 0.0044), d0=0.0076, d1=0.0040, collar_h=0.010,
                       collar_ribs=3, cap="ball", segs=16))

    # channel knob: boss + raised ring with 16 printed positions + large knurled knob with a guard flange
    cxk, cyk = P_CH
    r.add(boss(r, green, (cxk, cyk, ZT), d=0.0185, h=0.0019, shaft_d=0.006, shaft_h=0.0055, shaft_mat=m_gunmetal(r)))
    r.add(guard_ring(r, green, (cxk, cyk, ZT), d_in=0.0200, d_out=0.0250, h=0.0016, segs=40))
    knob(r, "knob_ch", base=(cxk, cyk, ZT + 0.0019), d=0.018, h=0.0150, style="ribbed", ribs=16, rib_depth=0.00045, skirt=True,
         skirt_d=0.0196, skirt_h=0.0024, mat=m_knob_knurl(r), index="line", value="channel", detents=16, segs=64)
    # volume knob
    vx, vy = P_VOL
    r.add(boss(r, green, (vx, vy, ZT), d=0.0172, h=0.0016, shaft_d=0.0055, shaft_h=0.005, shaft_mat=m_gunmetal(r)))
    knob(r, "knob_vol", base=(vx, vy, ZT + 0.0016), d=0.016, h=0.0125, style="ribbed", ribs=15, rib_depth=0.0004, skirt=True,
         skirt_d=0.0168, skirt_h=0.0018, mat=m_knob_knurl(r, "mx_knob_knurl_v"), index="line", value="volume", detents=24,
         segs=60)
    # emergency key recessed in a guard ring
    exk, eyk = P_EMERG
    r.add(cylinder(0.0050, 0.0002, m_print_dark(r), segs=28, caps=(False, True), z0=ZT - 0.0001).translate(exk, eyk, 0))
    r.add(guard_ring(r, rub, (exk, eyk, ZT), d_in=0.0106, d_out=0.0152, h=0.0031, segs=32))
    key(r, "emerg", at=(exk, eyk, ZT + 0.0001), normal=(0, 0, 1), up=(0, -1, 0), size=(0.0085, 0.0085), corner=0.00425, t=0.0020,
        mat=m_emerg_orange(r), dome=0.0003, depth=0.0012, shape="round")
    # LED light pipe
    pipe, insert = light_pipe(r, (P_LED[0], P_LED[1], ZT), normal=(0, 0, 1), up=(0, 1, 0), d=0.0032, color="green")
    r.add(pipe)
    print_decal(r, deck_canvas(), center=(0.0, 0.0, ZT + 0.004), normal=(0, 0, 1), up=(0, -1, 0), depth=0.0065,
                mats=[green, rub], min_dot=0.6)

    # --- left side (+X): guarded PTT, two side keys --------------------------------------------------------
    z_ptt = 0.0400
    floor = well_for(r, rub, (SX, YSIDE, z_ptt), (1, 0, 0), (0, 0, 1), (0.0130, 0.0320), gap=0.0005, margin=0.0014, t=0.0012,
                     corner=0.0050)
    ptt(r, "ptt", at=(SX + floor, YSIDE, z_ptt), length=0.032, width=0.013, ridges=6, t=0.0026, mat=key_black)
    r.add(guard_ribs(r, green, (SX - 0.0002, YSIDE, z_ptt), 0.0405))
    for pid, z in (("side1", 0.0110), ("side2", -0.0010)):
        f2 = well_for(r, rub, (SX, YSIDE, z), (1, 0, 0), (0, 0, 1), (0.0066, 0.0066), gap=0.0005, margin=0.0011, t=0.0009,
                      corner=0.0033)
        round_button(r, pid, (SX + f2, YSIDE, z), (1, 0, 0), d=0.0066, t=0.0017, mat=key_black)
    print_decal(r, side_prints(), center=(SX, YSIDE - 0.0090, 0.0050), normal=(1, 0, 0), up=(0, 0, 1), mats=[green])

    # --- right side (-X): bayonet accessory connector, tethered dust cap, rating plate ---------------------
    z_acc = 0.0440
    r.add(cylinder(0.0090, 0.0010, green, segs=36, bevel=0.0005, bevel_seg=2, caps=(False, True)).rotate(0, -90, 0)
          .translate(-SX, YSIDE, z_acc))
    r.add(round_connector(r, (-SX - 0.0010, YSIDE, z_acc), (-1, 0, 0), d=0.0125, pins=6, depth=0.0032))
    # moulded strap from the connector boss down to the hanging cap
    strap = r.mat("mx_strap_rubber", color=(24, 25, 26), spec=0.12, gloss=0.2, bump="rubber", bump_amp=0.00004, bump_scale=0.0005,
                  edge=0.3, dirt=0.2)
    sp = np.array([(-SX - 0.0006, YSIDE - 0.0005, z_acc - 0.0085), (-SX - 0.0016, YSIDE - 0.0007, z_acc - 0.0115),
                   (-SX - 0.0017, YSIDE - 0.0007, z_acc - 0.0150), (-SX - 0.0012, YSIDE - 0.0005, z_acc - 0.0170)])
    from nzprops import rrect, sweep
    r.add(sweep(rrect(0.0035, 0.0009, 0.0004, 2), sp, strap, side=(0, 1, 0), tag="capstrap", smooth_angle=60))
    r.add(dust_cap(r, (-SX, YSIDE, z_acc - 0.0245), (-1, 0, 0), (0, 0, 1)))
    print_decal(r, rating_label(0.0190, 0.0125, model="MX-905", serial="SN 26-90517", ident="ID: TXQ-MX905T",
                                rating="7.4 V  3400 mAh  Li-ion", foot="IP68  1 m"),
                center=(-SX, YSIDE, -0.0170), normal=(-1, 0, 0), up=(0, 0, 1), mats=[green])
    acc = DecalCanvas(0.012, 0.004, ppm=22000)
    acc.text(0.006, 0.002, "ACC", 0.0015, fnt="label-semi", spacing=0.0002, **ink("white"))
    print_decal(r, acc, center=(-SX, YSIDE, z_acc + 0.0115), normal=(-1, 0, 0), up=(0, 0, 1), mats=[green])

    # --- back: over-centre latches, strap mount plate, battery prints -----------------------------------------
    y_box = YB
    y_cover = YB  # the top cover is inset like the box
    for x in (0.0165, -0.0165):
        r.add(over_centre_latch(r, x, z_pivot=0.0420, z_keeper=0.0618, y_face=y_box, y_cover=y_cover))
    r.add(strap_plate(r, m_strap_plate(r), center_z=-0.0080))
    print_decal(r, battery_label(0.034, 0.022, pack="MB-90", volts="7.4 V", cap="3400 mAh", serial="SN B26-90233"),
                center=(0.0, 0.0010, Z0), normal=(0, 0, -1), up=(0, 1, 0), mats=[green], depth=0.002)
    print_decal(r, caution_label(0.026, 0.012, "CAUTION", ["Close both latches before use", "Li-ion: do not open"], ppm=16000),
                center=(0.0, y_cover, 0.0745), normal=(0, -1, 0), up=(0, 0, 1), mats=[green])

    # --- bottom: charging contacts on the front shell ----------------------------------------------------------
    from .radio_common import charging_contacts
    r.add(charging_contacts(r, (0.0, YSIDE + 0.001, Z0), (0, 0, -1), (0, 1, 0), pitch=0.009, size=(0.0045, 0.0028)))

    r.anchor(focus=(0.0, FY, 0.020), camDist=0.36, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422): palm on the battery box / strap plate, thumb on the PTT (+X side), antenna up; "
                  "tune with /radiogrip")
