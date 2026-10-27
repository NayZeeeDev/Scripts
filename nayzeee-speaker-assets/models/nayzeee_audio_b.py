"""nayzeee_audio_b -- "Echo Column": a slim cylindrical column speaker.

110 mm across, 430 mm body, 480 mm to the top of its strap.  From the floor up: a soft rubber
base with a printed model name, a machined aluminium trim ring, a wrap-around charcoal woven fabric
grille (its edges tucked under the rings, a small brushed mark badge on the front), a second trim ring
and a machined aluminium top cap with two fine V-grooves round its side.  The cap's radially brushed
top carries a domed teal light ring near the rim and five graphite keys with printed icons
(play front and centre, - / + beside it, power and bluetooth at the back).  A charcoal nylon webbing
strap with teal tracers arches over the top: its ends are screwed to two gunmetal lugs on the cap's
sides, with teal bar-tack stitching.  Back: a rubber port flap (AUX / USB behind it) with a pull tab.

Model space: origin = floor centre under the model, +Y = front, +X = viewer's left.
"""
import math

import numpy as np

from lib import mesh as M
from lib.spec import Anchor, Box, Cylinder, LodSettings, ModelSpec
from models import _aeb_kit as K

NAME = __name__.rsplit(".", 1)[-1]

R = 0.0552                                   # outer radius of rings / cap
R_F = 0.0545                                 # fabric radius
R_BASE = 0.0544                              # rubber base print band radius
Z_BASE = 0.0222                              # top of the rubber base
LED_H = 0.0024                               # teal floor-glow ring between the base and the lower trim ring
R_GLOW = 0.0529                              # glow ring edge radius (= base top edge, trim ring bottom edge)
Z_F0, Z_F1 = 0.0295 + LED_H, 0.3875          # fabric (tucked) between the trim rings
Z_CAP0, TOP = 0.3940, 0.4300                 # machined cap
R_LED = (0.0446, 0.0484)                     # light ring channel
Y_STRAP = 0.0
X_STRAP = 0.0612 + K.WEB_T / 2               # strap centre line on the lugs
Z_ARCH0 = 0.4400                             # arch starts here
ARCH_H = 0.0360
Z_STRAP0 = 0.3985                            # strap ends (on the lugs)
SEG = 56


def _lathe(prof, mat, nm, n, crease=40.0, uv=None):
    m = K.lathe_n(prof, n, crease=crease, material=mat)
    if uv == "radial":
        m = m.uv_radial(R)
    elif mat == "brushed_aluminium":
        m = m.uv_transform(scale=(1.0, 6.0))          # fine turning lines round the rings (brushing along U)
    return m.named(nm)


def _body(parts, n):
    arc = M.arc_profile
    # rubber base: flat bottom, rounded foot edge, short flare, vertical print band, rounded top edge
    base = [(0.0, 0.0, 0.0, -1.0), (0.0505, 0.0, 0.0, -1.0)] + arc((0.0505, 0.0030), 0.0030, -90, 0, 3)
    base += [(R_BASE, 0.0075, 1.0, 0.0), (R_BASE, 0.0195, 1.0, 0.0)] + arc((R_BASE - 0.0015, 0.0195), 0.0015, 0, 90, 2)
    parts.append(_lathe(base, "rubber", "base", n))
    # floor-glow ring: a slightly domed teal light band between the base and the trim ring, 2 mm inside them
    zg0, zg1, sag = Z_BASE - 0.0012, Z_BASE + LED_H, 0.0005
    hh = (zg1 - zg0) / 2
    rho = (hh * hh + sag * sag) / (2 * sag)
    a = math.degrees(math.asin(hh / rho))
    glow = M.arc_profile((R_GLOW + sag - rho, (zg0 + zg1) / 2), rho, -a, a, 3)
    parts.append(_lathe(glow, "led_teal", "floor_glow", n, crease=60))
    # lower trim ring: machined aluminium, rounded edges; its top lip tucks the fabric
    t0 = Z_BASE + LED_H
    lower = [(R_GLOW, t0), (0.0537, t0 + 0.0009)] + arc((0.0537, t0 + 0.0024), 0.0015, -90, 0, 2)[1:]
    lower += [(R, Z_F0 - 0.0015, 1.0, 0.0)] + arc((R - 0.0015, Z_F0 - 0.0015), 0.0015, 0, 90, 2)
    lower += [(0.0527, Z_F0, 0.0, 1.0)]
    parts.append(_lathe(lower, "brushed_aluminium", "trim_ring", n))
    # fabric: rolls out from under both rings; seam-free weave (integer repeats round the column)
    fab = arc((0.0527, Z_F0 + 0.0018), 0.0018, -90, 0, 2) + [(R_F, Z_F1 - 0.0018, 1.0, 0.0)]
    fab += arc((0.0527, Z_F1 - 0.0018), 0.0018, 0, 90, 2)
    fabric = K.lathe_n(fab, n, crease=70, material="spk_fabric_melange")
    reps = round(2 * math.pi * R_F / 0.050)
    parts.append(K.uv_around(fabric, reps, Z_F0, Z_F1).named("fabric"))
    # upper trim ring
    upper = [(0.0527, Z_F1, 0.0, -1.0), (R - 0.0015, Z_F1, 0.0, -1.0)] + arc((R - 0.0015, Z_F1 + 0.0015), 0.0015, -90, 0, 2)
    upper += [(R, Z_CAP0 - 0.0021, 1.0, 0.0)] + arc((R - 0.0015, Z_CAP0 - 0.0021), 0.0015, 0, 90, 2)
    upper += [(0.0525, Z_CAP0 - 0.0006), (0.0525, Z_CAP0)]
    parts.append(_lathe(upper, "brushed_aluminium", "trim_ring", n))
    # machined cap side: shadow step, two V-grooves, polished round into the top
    side = [(0.0525, Z_CAP0), (R, Z_CAP0 + 0.0012, 1.0, 0.0)]
    for zg in (0.4060, 0.4180):
        side += [(R, zg - 0.0007, 1.0, 0.0), (R - 0.0006, zg), (R, zg + 0.0007, 1.0, 0.0)]
    side += [(R, TOP - 0.0016, 1.0, 0.0)] + arc((R - 0.0016, TOP - 0.0016), 0.0016, 0, 90, 2)
    parts.append(_lathe(side, "brushed_aluminium", "cap_side", n, crease=35))
    # cap top: radially brushed, domed teal light ring in a channel near the rim
    zc = TOP - 0.0016                                  # channel walls end here (LED dome edges)
    top_out = [(R - 0.0016, TOP, 0.0, 1.0), (R_LED[1] + 0.0004, TOP, 0.0, 1.0), (R_LED[1], TOP - 0.0004),
               (R_LED[1], zc, -1.0, 0.0)]
    parts.append(_lathe(top_out, "brushed_aluminium_radial", "cap_top", n, 50, "radial"))
    a, sg = (R_LED[1] - R_LED[0]) / 2, 0.0008
    rho = (a * a + sg * sg) / (2 * sg)
    cz = zc + sg - rho
    a0 = math.degrees(math.atan2(zc - cz, a))
    led = arc(((R_LED[0] + R_LED[1]) / 2, cz), rho, a0, 180.0 - a0, 3)
    parts.append(_lathe(led, "led_teal", "light_ring", n))
    top_in = [(R_LED[0], zc, 1.0, 0.0), (R_LED[0], TOP - 0.0004), (R_LED[0] - 0.0004, TOP, 0.0, 1.0),
              (0.0, TOP, 0.0, 1.0)]
    parts.append(_lathe(top_in, "brushed_aluminium_radial", "cap_top", n, 50, "radial"))


def _keys(parts, d):
    keys = [(0.0, 0.0340, 0.0098, "icon_play"), (42.0, 0.0335, 0.0074, "icon_minus"),
            (-42.0, 0.0335, 0.0074, "icon_plus"), (140.0, 0.0330, 0.0066, "icon_power"),
            (-140.0, 0.0330, 0.0066, "icon_bluetooth")]
    for ang, rad, kr, icon in keys:
        a = math.radians(90.0 - ang)                  # 0 deg = front (+Y); +ang toward +X (viewer's left)
        x, y = rad * math.cos(a), rad * math.sin(a)
        h = 0.0022
        prof = [(kr, 0.0, 1.0, 0.0), (kr, h - 0.0010, 1.0, 0.0)] + M.arc_profile((kr - 0.0010, h - 0.0010), 0.0010, 0, 90, 2)
        prof += [(0.0, h, 0.0, 1.0)]
        key = M.lathe(prof, 24, crease=50, material="satin_graphite")
        parts.append(key.translate(x, y, TOP).named("key"))
        parts.append(K.decal(icon, (x, y, TOP + h + K.DECAL_OFF), "+z", width=kr * 1.05).named("key_icon"))
    led = M.hemisphere(0.0013, 10, 2, cap=False, material="led_teal").scale(1, 1, 0.7)
    a = math.radians(90.0 - 140.0 + 17.0)
    parts.append(led.translate(0.0330 * math.cos(a), 0.0330 * math.sin(a), TOP).named("status_led"))


def _strap(parts, d):
    xs = X_STRAP
    path = [(xs, Y_STRAP, Z_STRAP0), (xs, Y_STRAP, Z_ARCH0 - 0.012), (xs, Y_STRAP, Z_ARCH0)]
    for t in np.linspace(0.0, math.pi, M.seg(28, 10) + 1)[1:-1]:
        path.append((xs * math.cos(t), Y_STRAP, Z_ARCH0 + ARCH_H * math.sin(t)))
    path += [(-xs, Y_STRAP, Z_ARCH0), (-xs, Y_STRAP, Z_ARCH0 - 0.012), (-xs, Y_STRAP, Z_STRAP0)]
    strap = M.sweep(K.web_section(), np.array(path), caps=True, up=(0.0, 1.0, 0.0), tile=K.web_tile(),
                    material="spk_webbing")
    parts.append(strap.named("strap"))
    cyl = K.sdf_cylinder_z((0.0, 0.0), R - 0.0004, Z_CAP0, TOP)
    for sx, fac in ((1, "+x"), (-1, "-x")):
        lug_x = sx * (xs - K.WEB_T / 2 - 0.0065)
        lug = M.rounded_box((0.0124, 0.032, 0.033), 0.0030, 4, center=(lug_x, Y_STRAP, 0.4120), material="gunmetal")
        parts.append(K.cull_inside(lug, cyl, 0.0004).named("strap_lug"))
        xo = sx * (xs + K.WEB_T / 2)
        parts.append(M.hemisphere(0.0034, 16, 3, cap=False, material="chrome").scale(1, 1, 0.45)
                     .orient(fac, (xo, Y_STRAP, 0.4055)).named("strap_screw"))
        st = K.decal("", (xo + sx * K.DECAL_OFF, Y_STRAP, 0.4265), fac, width=0.0175, material="spk_stitch",
                     rect=(0.0, 0.0, 1.0, 1.0), aspect=1.0)
        parts.append(st.named("strap_stitch"))


def _prints(parts):
    # brushed mark badge on the fabric front, model name printed on the rubber base
    mk, bar = M.mark_2d(0.0175, 4)
    badge = M.extrude(mk, 0.0011, holes=[bar], bevel=0.0003, bevel_segments=1, z0=-0.0003, cap_bottom=False,
                      material="brushed_aluminium")
    parts.append(K.wrap_cyl(badge.translate(0.0, 0.066, 0.0), R_F + 0.0002).named("badge"))
    parts.append(K.cyl_decal("echo_column", 0.0135, R_BASE, 0.0050).named("base_print"))
    # woven teal label tab sewn in under the upper trim ring (front, viewer's right), printed white mark
    a_tab = 90.0 + 48.0
    tag = M.extrude(M.rounded_rect_2d(0.0095, 0.0175, 0.0012, 2), 0.0013, bevel=0.0005, bevel_segments=1,
                    z0=-0.0004, cap_bottom=False, bevel_bottom=False, material="teal_plastic")
    parts.append(K.wrap_cyl(tag.translate(0.0, Z_F1 - 0.0085, 0.0), R_F, a_tab).named("label_tab"))
    parts.append(K.cyl_decal("mark_white", Z_F1 - 0.0105, R_F + 0.0009, 0.0060, a_tab).named("label_mark"))
    # rubber port flap on the back of the fabric (AUX / USB-C behind it), with a pull tab
    flap = M.extrude(M.rounded_rect_2d(0.024, 0.054, 0.007, 4), 0.0014, bevel=0.0006, bevel_segments=2,
                     z0=-0.0004, cap_bottom=False, bevel_bottom=False, material="rubber")
    tab = M.extrude(M.rounded_rect_2d(0.010, 0.006, 0.0025, 3), 0.0012, bevel=0.0004, bevel_segments=1,
                    z0=0.0006, cap_bottom=False, material="rubber")
    parts.append(K.wrap_cyl(flap.translate(0.0, 0.070, 0.0), R_F, 270.0).named("port_flap"))
    parts.append(K.wrap_cyl(tab.translate(0.0, 0.0995, 0.0), R_F, 270.0).named("port_flap_tab"))
    parts.append(K.cyl_decal("aux", 0.060, R_F + 0.0010, 0.0042, 270.0).named("flap_print"))
    parts.append(K.cyl_decal("icon_bluetooth", 0.077, R_F + 0.0010, 0.0060, 270.0).named("flap_print"))


def build(detail: float) -> ModelSpec:
    n = K.nseg(SEG)
    parts = []
    _body(parts, n)
    _keys(parts, detail)
    _strap(parts, detail)
    _prints(parts)
    z_top = Z_ARCH0 + ARCH_H + K.WEB_T / 2
    return ModelSpec(
        name=NAME,
        parts=parts,
        collision=[
            Cylinder.vertical((0.0, 0.0), 0.0, TOP, R),
            Box.from_minmax((-X_STRAP - 0.002, -K.WEB_W / 2, Z_STRAP0), (X_STRAP + 0.002, K.WEB_W / 2, z_top), "RUBBER"),
        ],
        anchors={
            "grip": Anchor((0.0, Y_STRAP, Z_ARCH0 + ARCH_H), note="top of the strap arch, where the hand closes"),
            "top": Anchor((0.0, Y_STRAP, z_top), note="highest point (top of the strap)"),
            "front": Anchor((0.0, R_F, (Z_F0 + Z_F1) / 2), note="front of the fabric grille"),
            "light_ring": Anchor((0.0, 0.0, TOP), note="centre of the top cap (teal light ring around it)"),
        },
        lod=LodSettings(high_dist=12.0, archetype_lod_dist=90.0, hd_texture_dist=5.0, med_detail=0.4),
        description="Echo Column: slim fabric-wrapped column speaker, machined top cap with keys and a teal "
                    "light ring, rubber base, webbing strap.",
        meta={"render": {"pitch": 16, "yaw": 30}},
    )
