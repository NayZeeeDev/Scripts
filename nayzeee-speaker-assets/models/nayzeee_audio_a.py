"""nayzeee_audio_a -- "Pulse Tower": a tall portable party speaker.

A satin graphite shell (soft 45 mm radii, 14 mm back bevel) wraps a deep front bezel whose inner edge
rolls into the recess over a brushed aluminium lip; 14 mm behind the bezel face sits a separate matte
black baffle with a 1.5 mm shadow gap all round.  On the baffle: two 10" woofers (woven twill cones,
rubber roll surrounds, gloss dust caps with a brushed badge printed with the nayzeee mark) in chrome trim
rings held by six screws, each ringed by a domed teal LED halo in a channel with a rounded lip; a dome
tweeter in its own chrome ring and waveguide between them, flanked by two teal light bars.  A small
printed teal "nayzeee" wordmark on the bezel's bottom rail.

Top: an integrated carry handle (soft rounded-rect bar on two swept legs that land on gunmetal boots,
knurled rubber grip where the hand closes) and, in front of it, a raised control strip: aluminium
diamond-cut edge, gloss black inlay, six rubber keys with printed icons (power + bluetooth with teal
status LEDs, light mode, play, volume - / +) and a knurled volume knob over a printed tick ring.
Sides: soft rubber panels and slim teal LED strips near the front edge.  Back: a screwed panel with a
lifting pocket, two flared bass ports with teal rings, a brushed connector plate (AUX, USB-C, DC in) and
prints.  Four rubber feet.

Model space: origin = floor centre under the model, +Y = front, +X = viewer's left.
"""
import math

import numpy as np

from lib import mesh as M
from lib.spec import Anchor, Box, LodSettings, ModelSpec
from models import _aeb_kit as K

NAME = __name__.rsplit(".", 1)[-1]

W, D = 0.420, 0.360
Z0, Z1 = 0.016, 0.856                      # shell bottom (on the feet) / shell top
H = Z1 - Z0
ZC = (Z0 + Z1) / 2
YB, YF = -D / 2, D / 2                     # shell back / bezel face
R_OUT = 0.045                              # outline corner radius (seen from the front)
BB, BF = 0.014, 0.008                      # back / front bevel radius
BEZ = 0.032                                # bezel width (outer edge to recess wall)
RR = 0.004                                 # round into the recess
REC = 0.014                                # baffle face below the bezel face
GAP = 0.0015                               # shadow gap baffle <-> recess wall
PLATE_T = 0.006

Z_LO, Z_TW, Z_HI = 0.232, 0.437, 0.642     # woofer / tweeter / woofer centres
R_LED = 0.146                              # woofer hole = LED channel outer radius
R_TW = 0.038
LIP = 0.0012                               # rounded lip into the driver holes

Y_H = -0.085                               # handle centre line (y)
Z_POCKET = 0.770                           # rear lifting pocket centre
X_LEG = 0.135                              # handle legs
Z_BAR = 0.934                              # handle bar centre (bar top = 0.950)
BAR_T, BAR_D = 0.032, 0.050                # bar thickness (z) and depth (y)
GRIP_X = 0.072                             # rubber grip from -GRIP_X .. GRIP_X

POD = (0.310, 0.082, 0.088)                # control strip: width, depth, centre y
POD_H = 0.006

OUTLINE = M.rounded_rect_2d(W, H, R_OUT, 8)


def _design(m, facing="+y"):
    """Shell design space (x right seen from the front, y up from the shell centre, z = world y)."""
    return m.orient(facing, (0.0, 0.0, ZC))


# --------------------------------------------------------------------------- shell
def _shell(parts, d):
    arc = lambda c, r, a0, a1, n: M.arc_profile(c, r, a0, a1, n)
    back = arc((-BB, YB + BB), BB, -90, 0, 4)
    front = arc((-BF, YF - BF), BF, 0, 90, 3)
    walls = K.loft(OUTLINE, back + front, material="satin_graphite", name="shell")
    face = K.loft(OUTLINE, [(-BF, YF, 0.0, 1.0), (-(BEZ - RR), YF, 0.0, 1.0)], material="satin_graphite")
    lip = K.loft(OUTLINE, arc((-(BEZ - RR), YF - RR), RR, 90, 180, 3), material="brushed_aluminium")
    recess = K.loft(OUTLINE, [(-BEZ, YF - RR, -1.0, 0.0), (-BEZ, YF - REC - 0.008),
                              (-BEZ - 0.010, YF - REC - 0.008, 0.0, 1.0)], material="satin_graphite")
    parts.append(_design(walls).named("shell"))
    parts.append(_design(face).uv_planar("+y").named("bezel_face"))
    parts.append(_design(lip).named("bezel_lip"))
    parts.append(_design(recess).named("bezel_recess"))
    # back: the shell's back face is a ring around a screwed back panel
    panel = M.rounded_rect_2d(W - 2 * BB - 0.040, H - 2 * BB - 0.050, 0.024, 6)
    back_cap = K.cap(OUTLINE, YB, offset=-BB, holes=[panel], up=False, material="satin_graphite")
    parts.append(_design(back_cap).uv_planar("-y").named("shell_back"))
    _back_panel(parts, panel, d)


def _back_panel(parts, panel, d):
    pt, pb = 0.0025, 0.0012                       # panel stands 2.5 mm proud, 1.2 mm round
    yb = YB - pt
    edge = K.loft(panel, M.arc_profile((-pb, yb + pb), pb, -90, 0, 2) + [(0.0, YB, 1.0, 0.0)],
                  material="matte_black_plastic", name="back_panel_edge")
    parts.append(_design(edge).named("back_panel"))
    n_p = K.nseg(40)
    ports = [(sx * 0.095, 0.200 - ZC) for sx in (-1, 1)]
    holes = [K.ring2d(0.036, n_p, c) for c in ports]
    pocket = K.offset2d(M.rounded_rect_2d(0.170, 0.036, 0.018, 6, center=(0.0, Z_POCKET - ZC)), 0.0012)
    face = K.cap(panel, yb, offset=-pb, holes=holes + [pocket], up=False, material="matte_black_plastic")
    parts.append(_design(face).uv_planar("-y").named("back_panel"))
    for c in ports:
        _port(parts, c, yb, n_p)
    # rear lifting pocket (second hand when carrying the tower level)
    pk = M.rounded_rect_2d(0.170, 0.036, 0.018, 6)
    pd = 0.030
    wall = K.loft(pk, [(0.0, -pd), (0.0, -0.0012, 1.0, 0.0)] + M.arc_profile((-0.0012, -0.0012), 0.0012, 0, 90, 2),
                  material="matte_black_plastic", hole=True)
    floor = K.cap(pk, -pd, material="rubber")
    for p, nm in ((wall, "rear_pocket"), (floor, "rear_pocket_floor")):
        parts.append(p.orient("-y", (0.0, yb, Z_POCKET)).named(nm))
    # screws round the panel
    hw, hh = (W - 2 * BB - 0.040) / 2 - 0.014, (H - 2 * BB - 0.050) / 2 - 0.014
    for sx in (-1, 1):
        for sz in (-1, 0, 1):
            p = (sx * hw, yb, ZC + sz * hh)
            parts += K.screw(p, "-y", 0.0026, "gunmetal", d)
    # connector plate: AUX (teal collar), USB-C, DC in; prints
    cz = 0.640
    plate = M.extrude(M.rounded_rect_2d(0.150, 0.056, 0.006, 4), 0.0018, bevel=0.0006, bevel_segments=2,
                      cap_bottom=False, material="brushed_aluminium")
    parts.append(plate.orient("-y", (0.0, yb, cz)).named("io_plate"))
    yp = yb - 0.0018
    for sx in (-1, 1):
        parts += K.screw((sx * 0.066, yp, cz), "-y", 0.0019, "chrome", d)
    # seen from behind, image right = +X
    parts += K.jack((0.034, yp, cz + 0.006), "-y", 0.0058, "teal_plastic")
    parts += K.usb_c((0.000, yp, cz + 0.006), "-y")
    parts += K.dc_inlet((-0.034, yp, cz + 0.006), "-y")
    for x, e in ((0.034, "aux"), (-0.034, "power")):
        parts.append(K.decal(e, (x, yp - K.DECAL_OFF, cz - 0.012), "-y", height=0.0052).named("io_label"))
    # prints on the panel
    parts.append(K.decal("pulse_tower", (0.0, yb - K.DECAL_OFF, 0.520), "-y", height=0.0105).named("back_print"))
    parts.append(K.decal("nayzeee_audio", (0.0, yb - K.DECAL_OFF, 0.498), "-y", height=0.0062).named("back_print"))
    parts.append(K.decal("mark_white", (0.0, yb - K.DECAL_OFF, 0.556), "-y", width=0.026).named("back_mark"))


def _port(parts, c, yb, n):
    """Flared bass port in the back panel (design space of the shell, axis along design z)."""
    rh, rt, L = 0.036, 0.027, 0.11
    fr = rh - rt
    prof = [(0.0, yb + L, 0.0, -1.0), (rt, yb + L), (rt, yb + fr, -1.0, 0.0)]
    prof += M.arc_profile((rh, yb + fr), fr, 180, 270, 2)
    port = K.lathe_n(prof, n, crease=50, material="matte_black_plastic").translate(c[0], c[1], 0)
    parts.append(_design(port).named("bass_port"))
    ring = K.lathe_n([(rh + 0.0045, 0.0), (rh + 0.0045, 0.0009), (rh + 0.0015, 0.0009), (rh + 0.0015, 0.0)],
                     n, crease=50, material="teal_plastic").translate(c[0], c[1], 0)
    parts.append(_design(ring.mirror("z", 0.0).translate(0, 0, yb)).named("port_ring"))


# --------------------------------------------------------------------------- front baffle + drivers
def _baffle(parts, d):
    outline = K.offset2d(OUTLINE, -(BEZ + GAP))
    zf = YF - REC
    pb = 0.0022
    edge = K.loft(outline, [(0.0, zf - PLATE_T, 1.0, 0.0), (0.0, zf - pb, 1.0, 0.0)]
                  + M.arc_profile((-pb, zf - pb), pb, 0, 90, 2), material="matte_black_plastic", name="baffle_edge")
    parts.append(_design(edge).named("baffle_edge"))
    n_w, n_t = K.nseg(48), K.nseg(36)
    holes = [K.ring2d(R_LED + LIP, n_w, (0.0, Z_LO - ZC)), K.ring2d(R_LED + LIP, n_w, (0.0, Z_HI - ZC)),
             K.ring2d(R_TW + LIP, n_t, (0.0, Z_TW - ZC))]
    bars = [M.rounded_rect_2d(0.094, 0.0085, 0.00425, 4, center=(sx * 0.106, Z_TW - ZC)) for sx in (-1, 1)]
    face = K.cap(outline, zf, offset=-pb, holes=holes + bars, material="matte_black_plastic")
    parts.append(_design(face).uv_planar("+y").named("baffle"))
    for zc in (Z_LO, Z_HI):
        for p in _woofer(n_w, d):
            parts.append(_design(p.translate(0.0, zc - ZC, zf)).named(p.name))
    for p in _tweeter(n_t):
        parts.append(_design(p.translate(0.0, Z_TW - ZC, zf)).named(p.name))
    for b in bars:
        wall = K.loft(b, [(0.0, zf - 0.0028), (0.0, zf)], material="matte_black_plastic", hole=True)
        led = K.cap(b, zf - 0.0028, material="led_teal")
        parts.append(_design(wall).named("light_bar_slot"))
        parts.append(_design(led).uv_planar("+y").named("light_bar"))
    # four corner screws hold the baffle in the bezel
    hx = W / 2 - BEZ - GAP - 0.0135
    hz = H / 2 - BEZ - GAP - 0.0135
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts += K.screw((sx * hx, zf, ZC + sz * hz), "+y", 0.0024, "gunmetal", d)
    # printed teal wordmark on the bezel's bottom rail
    parts.append(K.decal("wordmark_teal", (0.0, YF + K.DECAL_OFF, Z0 + (BEZ + BF) / 2 - 0.0005), "+y",
                         height=0.0125).named("wordmark"))


def _woofer(n, d):
    """10" woofer facing +z, baffle face at z = 0, filling a hole of radius R_LED -> parts."""
    out = []

    def piece(prof, mat, nm, crease=40.0):
        out.append(K.lathe_n(prof, n, crease=crease, material=mat).named(nm))

    z_ch = -0.0045
    piece(M.arc_profile((R_LED + LIP, -LIP), LIP, 90, 180, 1) + [(R_LED, z_ch, -1.0, 0.0)], "matte_black_plastic",
          "led_channel")
    piece(M.arc_profile((0.1408, -0.0116), 0.0088, 53.8, 126.2, 2), "led_teal", "led_ring")
    tr = [(0.1356, z_ch, 1.0, 0.0), (0.1356, 0.0010, 1.0, 0.0)] + M.arc_profile((0.1326, 0.0010), 0.003, 0, 90, 2)
    tr += [(0.1236, 0.0040, 0.0, 1.0), (0.1224, 0.0028), (0.1224, -0.0035, -1.0, 0.0)]
    piece(tr, "chrome", "trim_ring")
    piece([(0.1224, -0.0035, 0.0, 1.0), (0.1176, -0.0080)], "matte_black_plastic", "woofer_gasket", 30.0)
    piece(M.arc_profile((0.1100, -0.0080), 0.0076, 0, 180, 4), "rubber", "woofer_surround")
    cone = [tuple(p) for p in M.bezier_path((0.1024, -0.0080, 0), (0.075, -0.016, 0), (0.050, -0.030, 0),
                                            (0.0360, -0.0470, 0), 4)[:, :2]]
    co = K.lathe_n(cone, n, material="spk_cone_twill").uv_planar("+z", 0.032)
    out.append(co.named("woofer_cone"))
    piece(K.dome(0.0360, -0.0470, -0.0320, 2, r_end=0.0200), "gloss_black_plastic", "dust_cap")
    zb = K.dome_z(0.0360, -0.0470, -0.0320, 0.0200)
    badge = [(0.0200, zb, 1.0, 0.0), (0.0200, -0.0338, 1.0, 0.0), (0.0193, -0.0331, 0.0, 1.0), (0.0, -0.0331, 0.0, 1.0)]
    out.append(K.lathe_n(badge, n, crease=50, material="brushed_aluminium_radial").uv_radial(0.020).named("cap_badge"))
    out.append(K.decal("mark", (0.0, 0.0, -0.0331 + K.DECAL_OFF), "+z", width=0.0165).named("cap_mark"))
    # six screws hold the trim ring
    if d >= 0.5:
        for k in range(6):
            a = math.radians(30.0 + 60 * k)
            out += K.screw((0.1290 * math.cos(a), 0.1290 * math.sin(a), 0.0035), "+z", 0.0021, "gunmetal", d)
    return out


def _tweeter(n):
    out = []

    def piece(prof, mat, nm, crease=40.0):
        out.append(K.lathe_n(prof, n, crease=crease, material=mat).named(nm))
    piece(M.arc_profile((R_TW + LIP, -LIP), LIP, 90, 180, 1) + [(R_TW, -0.0030, -1.0, 0.0)], "matte_black_plastic",
          "tweeter_well")
    tr = [(R_TW, -0.0030, 0.0, 1.0), (0.0372, -0.0030), (0.0372, 0.0005, 1.0, 0.0)]
    tr += M.arc_profile((0.0352, 0.0005), 0.0020, 0, 90, 2) + [(0.0332, 0.0025, 0.0, 1.0), (0.0318, 0.0011)]
    tr += [(0.0318, -0.0020, -1.0, 0.0)]
    piece(tr, "chrome", "tweeter_ring", 50.0)
    wg = [(0.0318, -0.0020), (0.0260, -0.0032), (0.0200, -0.0060), (0.0160, -0.0098), (0.0148, -0.0120)]
    piece(wg, "gloss_black_plastic", "tweeter_waveguide")
    piece(M.arc_profile((0.0137, -0.0120), 0.0011, 0, 180, 3), "rubber", "tweeter_surround")
    piece(K.dome(0.0126, -0.0120, -0.0040, 4), "gunmetal", "tweeter_dome")
    return out


# --------------------------------------------------------------------------- top: handle + control strip
def _handle(parts):
    up = (0.0, 1.0, 0.0)
    sec = M.rounded_rect_section(BAR_D, BAR_T, 0.0125, 3)
    zf = Z1 - 0.006
    left = M.polyline_path([(X_LEG, Y_H, zf), (X_LEG, Y_H, Z_BAR), (GRIP_X, Y_H, Z_BAR)], 0.042, 8)
    right = M.polyline_path([(-GRIP_X, Y_H, Z_BAR), (-X_LEG, Y_H, Z_BAR), (-X_LEG, Y_H, zf)], 0.042, 8)
    grip = np.array([(GRIP_X - 2 * GRIP_X * t, Y_H, Z_BAR) for t in np.linspace(0, 1, 5)])
    for path, mat, nm in ((left, "satin_graphite", "handle"), (grip, "rubber_grip", "handle_grip"),
                          (right, "satin_graphite", "handle")):
        parts.append(M.sweep(sec, path, caps=False, up=up, material=mat).named(nm))
    # teal rings where the grip meets the bar (0.6 mm proud, rounded)
    ring_c = M.rounded_rect_2d(BAR_D, BAR_T, 0.0125, 3)
    rr = 0.0006
    prof = [(0.0, 0.0)] + M.arc_profile((0.0, rr), rr, -90, 0, 1) + M.arc_profile((0.0, 0.0024 - rr), rr, 0, 90, 1)
    prof += [(0.0, 0.0024)]
    for sx in (-1, 1):
        ring = K.loft(ring_c, prof, material="teal_plastic")
        parts.append(ring.orient("+x", (sx * GRIP_X - 0.0012, Y_H, Z_BAR)).named("grip_ring"))
    # boots where the legs land on the shell
    for sx in (-1, 1):
        boot = M.extrude(M.rounded_rect_2d(0.050, 0.068, 0.014, 4), 0.0075, bevel=0.0028, bevel_segments=2,
                         bevel_bottom=False, cap_bottom=False, z0=Z1 - 0.001, material="gunmetal")
        parts.append(boot.translate(sx * X_LEG, Y_H, 0.0).named("handle_boot"))


def _pod(parts, d):
    w, dp, yc = POD
    out = M.rounded_rect_2d(w, dp, 0.012, 6, center=(0.0, yc))
    z_top = Z1 + POD_H
    eb = 0.0018
    body = K.loft(out, [(0.0, Z1 - 0.001, 1.0, 0.0), (0.0, z_top - 0.0028, 1.0, 0.0)], material="satin_graphite")
    edge = K.loft(out, [(0.0, z_top - 0.0028, 1.0, 0.0), (0.0, z_top - eb, 1.0, 0.0)]
                  + M.arc_profile((-eb, z_top - eb), eb, 0, 90, 2) + [(-0.0058, z_top, 0.0, 1.0)]
                  + [(-0.0066, z_top - 0.0008)], material="brushed_aluminium")
    inlay = K.cap(out, z_top - 0.0008, offset=-0.0066, material="gloss_black_plastic")
    parts += [body.named("pod_body"), edge.named("pod_edge"), inlay.uv_planar("+z").named("pod_inlay")]
    zi = z_top - 0.0008
    keys = [(0.125, "icon_power", True), (0.090, "icon_bluetooth", True), (0.055, "icon_note", False),
            (-0.055, "icon_play", False), (-0.090, "icon_minus", False), (-0.125, "icon_plus", False)]
    for x, icon, led in keys:
        key = M.extrude(M.rounded_rect_2d(0.026, 0.017, 0.0055, 3), 0.0032, bevel=0.0011, bevel_segments=1,
                        cap_bottom=False, z0=zi, material="rubber")
        parts.append(key.translate(x, yc + 0.004, 0.0).named("key"))
        parts.append(K.decal(icon, (x, yc + 0.004, zi + 0.0032 + K.DECAL_OFF), "+z", width=0.0085).named("key_icon"))
        if led:
            parts.append(M.hemisphere(0.0016, 12, 3, cap=False, material="led_teal").scale(1, 1, 0.7)
                         .translate(x, yc - 0.0185, zi).named("status_led"))
    # volume knob over a printed tick ring
    kr = 0.0185
    zk = zi + 0.0006
    grip = M.lathe([(kr - 0.0008, 0.0, 0.0, -1.0), (kr, 0.0008, 1.0, 0.0), (kr, 0.0150, 1.0, 0.0)], 56,
                   material="rubber_grip").uv_cylindrical("z")
    capk = M.lathe([(kr, 0.0150), (kr - 0.0014, 0.0168), (kr - 0.0022, 0.0172, 0.0, 1.0), (0.0, 0.0172, 0.0, 1.0)],
                   56, crease=35, material="brushed_aluminium_radial").uv_radial(kr)
    for p, nm in ((grip, "knob_grip"), (capk, "knob_cap")):
        parts.append(p.translate(0.0, yc, zk).named(nm))
    c = math.radians(-135.0 + 270.0 * 0.7)                 # clock angle seen by a reader in front
    dv = np.array([-math.sin(c), -math.cos(c)])             # image right = -X, image up = -Y
    mid = dv * (kr * 0.56)
    ptr = M.rounded_box((0.0016, kr * 0.62, 0.0005), (0.0006, 0.0006, 0.0), 2, material="teal_plastic")
    ang = math.degrees(math.atan2(dv[1], dv[0])) - 90.0
    parts.append(ptr.rotate_z(ang).translate(mid[0], yc + mid[1], zk + 0.0172 + 0.00015).named("knob_pointer"))
    parts.append(K.decal("ring_ticks", (0.0, yc, zi + K.DECAL_OFF), "+z", width=0.060).named("knob_ticks"))


# --------------------------------------------------------------------------- sides, feet
def _sides(parts):
    for sx, fac in ((1, "+x"), (-1, "-x")):
        x = sx * W / 2
        pan = M.extrude(M.rounded_rect_2d(0.250, 0.600, 0.032, 4), 0.0022, bevel=0.0012, bevel_segments=1,
                        cap_bottom=False, material="rubber")
        # soft rubber side panel (centred a little behind the middle) and a slim LED strip near the front edge
        parts.append(pan.orient(fac, (x, -0.012, 0.455)).uv_planar(fac).named("side_panel"))
        strip = M.extrude(M.rounded_rect_2d(0.0052, 0.600, 0.0026, 3), 0.0016, bevel=0.0006, bevel_segments=1,
                          cap_bottom=False, material="led_teal")
        parts.append(strip.orient(fac, (x, 0.150, 0.455)).named("side_led"))


def _feet(parts):
    prof = [(0.0, 0.0, 0.0, -1.0), (0.0255, 0.0, 0.0, -1.0)] + M.arc_profile((0.0255, 0.0025), 0.0025, -90, 0, 1)
    prof += [(0.0280, 0.0105, 1.0, 0.0), (0.0262, Z0 + 0.003)]
    foot = M.lathe(prof, 12, crease=45, material="rubber")
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(foot.translate(sx * 0.140, sy * 0.120, 0.0).named("foot"))


def build(detail: float) -> ModelSpec:
    parts = []
    _shell(parts, detail)
    _baffle(parts, detail)
    _handle(parts)
    _pod(parts, detail)
    _sides(parts)
    _feet(parts)
    z_top = Z_BAR + BAR_T / 2
    return ModelSpec(
        name=NAME,
        parts=parts,
        collision=[
            Box.from_minmax((-W / 2, YB - 0.003, 0.0), (W / 2, YF, Z1 + POD_H), "PLASTIC"),
            Box.from_minmax((-X_LEG - BAR_T / 2, Y_H - BAR_D / 2, Z1), (X_LEG + BAR_T / 2, Y_H + BAR_D / 2, z_top),
                            "PLASTIC"),
        ],
        anchors={
            "grip": Anchor((0.0, Y_H, Z_BAR), note="centre of the handle bar, where the hand closes"),
            "top": Anchor((0.0, Y_H, z_top), note="highest point (top of the handle bar)"),
            "front": Anchor((0.0, YF, ZC), note="centre of the bezel face"),
            "woofer_hi": Anchor((0.0, YF - REC, Z_HI), note="upper woofer centre on the baffle (LED halo)"),
            "woofer_lo": Anchor((0.0, YF - REC, Z_LO), note="lower woofer centre on the baffle (LED halo)"),
            "controls": Anchor((0.0, POD[2], Z1 + POD_H), note="top control strip centre"),
        },
        lod=LodSettings(high_dist=18.0, archetype_lod_dist=120.0, hd_texture_dist=8.0, med_detail=0.35),
        description="Pulse Tower: tall party speaker, two LED-ringed woofers + tweeter, top control strip, "
                    "integrated top handle, rear bass ports.",
        meta={"render": {"pitch": 14, "yaw": 32}},
    )
