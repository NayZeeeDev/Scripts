"""nayzeee_console -- "Record Console": a mid-century record cabinet on four splayed legs.

Optional upgrade model for the turntable item nayzeee_audio_g: it is streamed NEXT TO the speaker
pack's own nayzeee_audio_g.ydr (different model name, txd nayzeee_console_texture, ytyp
nayzeee_console.ytyp) and used once Config.Boomboxes['nayzeee_audio_g'].model = 'nayzeee_console'.

Walnut cabinet with soft waterfall edges, a full-width woven speaker grille recessed into a walnut
face frame, four tapered black lacquer legs with brushed-brass ferrules and floor glides.  On top:
the deck plinth on the viewer's LEFT half (+X) and the control panel on the viewer's RIGHT half (-X),
both satin black with a diamond-cut aluminium edge, separated by a strip of walnut.

Deck (+X): arm board with the tonearm collar, cue lever, arm rest post, a 45 adapter.  The platter,
tonearm and record are NOT part of this model: they are the separate props nayzeee_tt_platter,
nayzeee_tt_arm and nayzeee_vinyl, placed at the anchors below (shared contract, "Turntable geometry").
Controls (-X): two knurled aluminium knobs over printed tick scales, an amber back-lit VU meter with a
needle and pivot hood, a square start/stop key in an aluminium bezel, 33/45 keys with indicator LEDs,
chrome POWER and PHONO/LINE toggles, a teal power LED, an engraved NAYZEEE name plate and an
aluminium pinstripe.  Back: hardboard panel with a perforated vent, RCA jacks and a power inlet.

Model space: origin = floor centre under the cabinet, +Y = front, +X = viewer's left.
"""
import math

import numpy as np

from lib import mesh as M
from lib.spec import Anchor, Box, Cylinder, LodSettings, ModelSpec
from models import _tt_common as C

W = C.CAB_X[1] - C.CAB_X[0]               # 1.00
H = C.CAB_TOP - C.LEG_TOP                 # 0.36
ZC = (C.CAB_TOP + C.LEG_TOP) / 2          # 0.56
FRONT = C.CAB_Y[1]                        # 0.21
RECESS = FRONT - 0.010                    # grille cloth plane / face frame back
BACK = C.CAB_Y[0] + 0.010                 # walnut back; back panel, ports and screws end inside y -0.21
EDGE_R = 0.016                            # waterfall radius of the long edges
OPEN = (0.936, 0.294, 0.565)              # grille opening: width, height, centre z
SLAB_Z = (C.CAB_TOP, 0.7755, 0.7835, C.DECK_TOP)   # walnut top, black body / alu edge / inlay, deck top
INSET = 0.009                             # aluminium margin around the black inlay
LEG_SPLAY = 7.0                           # degrees outward in x and in y
LEG_XY = (0.415, 0.135)                   # leg tops
GLIDE_H = 0.006
TOP = C.DECK_TOP


# --------------------------------------------------------------------------- cabinet
def _cabinet(parts):
    outline = M.rounded_rect_2d(W, H, EDGE_R, 6)
    # body: open at the front, rounded back edges (built facing +y, then mirrored to face the back)
    body = M.extrude(outline, RECESS - BACK, bevel=0.010, bevel_segments=4, bevel_bottom=False,
                     cap_bottom=False, material="walnut").orient("+y", (0, 0, ZC)).mirror("y")
    parts.append(body.translate(0, RECESS, 0).named("cabinet"))
    # face frame around the grille opening, rounded front edges inside and out
    hole = M.rounded_rect_2d(OPEN[0], OPEN[1], 0.010, 4, center=(0, OPEN[2] - ZC))
    inlay_h = 0.0004                      # brass inlay stands this proud; frame face sits back so y max = 0.21
    frame = M.extrude(outline, FRONT - RECESS - inlay_h, holes=[hole], bevel=0.007, bevel_segments=4,
                      bevel_bottom=False, cap_bottom=False, material="walnut").orient("+y", (0, RECESS, ZC))
    parts.append(frame.named("face_frame"))
    # thin brass inlay line around the opening, on the flat of the face frame
    oc = (0, OPEN[2] - ZC)
    ring_o = M.rounded_rect_2d(OPEN[0] + 0.029, OPEN[1] + 0.029, 0.0245, 4, center=oc)
    ring_i = M.rounded_rect_2d(OPEN[0] + 0.024, OPEN[1] + 0.024, 0.0220, 4, center=oc)
    inlay = M.extrude(ring_o, inlay_h + 0.0002, holes=[ring_i], cap_bottom=False, material="tt_brass")
    parts.append(inlay.orient("+y", (0, FRONT - inlay_h - 0.0002, ZC)).named("grille_inlay"))
    cloth = M.plane(OPEN[0] + 0.002, OPEN[1] + 0.002, center=(0, RECESS + 0.0004, OPEN[2]), facing="+y",
                    material="fabric_grille_dark").uv_planar("+y")
    parts.append(cloth.named("grille_cloth"))
    # small brushed mark badge on the cloth, viewer's bottom right
    mark, bar = M.mark_2d(0.028, 6)
    badge = M.extrude(mark, 0.0016, holes=[bar], bevel=0.0004, bevel_segments=2, cap_bottom=False,
                      material="brushed_aluminium")
    bx, by = OPEN[0] / 2 - 0.034, OPEN[2] - OPEN[1] / 2 + 0.030 - ZC
    parts.append(badge.translate(bx, by, 0).orient("+y", (0, RECESS + 0.0004, ZC)).named("grille_badge"))
    # back panel: black hardboard with a perforated vent, screws and prints
    bp = M.extrude(M.rounded_rect_2d(0.90, 0.28, 0.006, 3), 0.0025, bevel=0.0008, bevel_segments=2,
                   cap_bottom=False, material="matte_black_plastic").orient("-y", (0, BACK, ZC))
    parts.append(bp.named("back_panel"))
    by_ = BACK - 0.0025
    parts.append(M.plane(0.56, 0.11, center=(0, by_ - C.DECAL_OFF, ZC + 0.045), facing="-y",
                         material="speaker_grille_round").uv_planar("-y").named("back_vent"))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts += _screw((sx * 0.43, by_, ZC + sz * 0.12), "-y")
    parts.append(C.decal("nayzeee_audio", 0.11, (0.0, by_ - C.DECAL_OFF, ZC - 0.065), "-y").named("back_print"))
    parts.append(C.decal("record_console", 0.10, (0.0, by_ - C.DECAL_OFF, ZC - 0.090), "-y").named("back_print"))
    _back_ports(parts, by_)


def _back_ports(parts, y):
    """Connector plate on the back panel (viewer's right seen from behind = +X): two RCA line jacks
    (teal / white rings) and a recessed power inlet."""
    cx, cz = 0.335, ZC - 0.072
    plate = M.extrude(M.rounded_rect_2d(0.110, 0.042, 0.003, 3), 0.0015, bevel=0.0004, bevel_segments=1,
                      cap_bottom=False, material="brushed_aluminium")
    parts.append(plate.orient("-y", (cx, y, cz)).named("port_plate"))
    yp = y - 0.0015
    for k, (dx, ring) in enumerate(((-0.036, "teal_plastic"), (-0.014, "white_plastic"))):
        p = (cx + dx, yp, cz + 0.004)
        parts.append(M.tube(0.0052, 0.0040, 0.0012, 24, bevel=0.0003, material=ring).orient("-y", p).named("rca_ring"))
        barrel = M.lathe([(0.0041, 0.0, 1.0, 0.0), (0.0041, 0.0046, 1.0, 0.0), (0.0034, 0.0052),
                          (0.0023, 0.0052, 0.0, 1.0), (0.0023, 0.0030, -1.0, 0.0), (0.0, 0.0030, 0.0, 1.0)],
                         24, crease=45, material="chrome")
        parts.append(barrel.orient("-y", p).named("rca_jack"))
    inlet = M.extrude(M.chamfer_rect_2d(0.026, 0.017, 0.004, corners=(0, 0, 1, 1)), 0.0030, bevel=0.0005,
                      bevel_segments=1, cap_bottom=False, material="matte_black_plastic")
    parts.append(inlet.orient("-y", (cx + 0.028, yp, cz + 0.002)).named("power_inlet"))
    for dx in (-0.006, 0.0, 0.006):
        parts.append(M.box((0.0016, 0.0006, 0.0062), (cx + 0.028 + dx, yp - 0.0030 - 0.0003, cz + 0.002),
                           material="gloss_black_plastic").named("inlet_pin_slot"))
    parts.append(C.decal("line", 0.0, (cx - 0.025, y - C.DECAL_OFF, cz - 0.0285), "-y", height=0.0060).named("label"))


def _screw(pos, facing_dir="+z", r=0.0019):
    """Chrome dome screw head with a dark slot, on a surface facing ``facing_dir`` -> [head, slot]."""
    head = M.hemisphere(r, 16, 3, cap=False, material="chrome").scale(1, 1, 0.42)
    slot = M.box((1.5 * r, 0.22 * r, 0.10 * r), center=(0, 0, 0.42 * r - 0.03 * r), material="gloss_black_plastic")
    return [head.orient(facing_dir, pos).named("screw"), slot.orient(facing_dir, pos).named("screw_slot")]


def _legs(parts, collision):
    t = math.tan(math.radians(LEG_SPLAY))
    for sx in (-1, 1):
        for sy in (-1, 1):
            top = np.array([sx * LEG_XY[0], sy * LEG_XY[1], C.LEG_TOP - 0.001])
            foot_z = 0.0035
            drop = top[2] - foot_z
            bot = np.array([top[0] + sx * t * drop, top[1] + sy * t * drop, foot_z])
            L = float(np.linalg.norm(top - bot))

            def r_at(z):
                return 0.0105 + (0.0185 - 0.0105) * z / L
            leg = M.lathe([(r_at(0.034), 0.034), (r_at(L), L)], 32, material="tt_lacquer_black")
            fr = r_at(0.050) + 0.0011
            ferrule = M.lathe([(fr, 0.0), (fr, 0.0465, 1.0, 0.0)] + M.arc_profile((fr - 0.0009, 0.0465), 0.0009, 0, 90, 2)
                              + [(r_at(0.0474) - 0.0003, 0.0474, 0.0, 1.0)], 32, material="tt_brass")
            parts.append(C.along(leg, bot, top).named("leg"))
            parts.append(C.along(ferrule.uv_cylindrical("z"), bot, top).named("leg_ferrule"))
            glide = M.cylinder(0.0128, GLIDE_H, 24, bevel=0.0018, bevel_segments=2, material="rubber")
            parts.append(glide.translate(bot[0], bot[1], 0.0).named("glide"))
            plate = M.rounded_box((0.056, 0.056, 0.0055), 0.0015, 2,
                                  center=(top[0], top[1], C.LEG_TOP - 0.00275), material="gunmetal")
            parts.append(plate.named("leg_plate"))
            for dx in (-1, 1):
                for dy in (-1, 1):
                    parts += _screw((top[0] + dx * 0.020, top[1] + dy * 0.020, C.LEG_TOP - 0.0055), "-z", 0.0024)
            collision.append(Cylinder(tuple(bot), tuple(top), 0.016, "WOOD_SOLID_POLISHED"))


# --------------------------------------------------------------------------- deck + panel slabs
def _slab(parts, x0, x1, name):
    w, d = x1 - x0, C.PLINTH_Y[1] - C.PLINTH_Y[0]
    cx = (x0 + x1) / 2
    out = M.rounded_rect_2d(w, d, 0.008, 4, center=(cx, 0))
    body = M.extrude(out, SLAB_Z[1] - SLAB_Z[0], z0=SLAB_Z[0], cap_top=False, cap_bottom=False,
                     material="matte_black_plastic")
    edge = M.extrude(out, SLAB_Z[2] - SLAB_Z[1], z0=SLAB_Z[1], bevel=0.0018, bevel_segments=1, bevel_bottom=False,
                     cap_bottom=False, material="brushed_aluminium")
    inlay = M.extrude(M.rounded_rect_2d(w - 2 * INSET, d - 2 * INSET, 0.004, 4, center=(cx, 0)),
                      SLAB_Z[3] - SLAB_Z[2], z0=SLAB_Z[2], bevel=0.0005, bevel_segments=1, bevel_bottom=False,
                      cap_bottom=False, material="matte_black_plastic")
    parts += [body.named(name + "_body"), edge.named(name + "_edge"), inlay.named(name + "_top")]
    m = INSET / 2 + 0.0009
    for x in (x0 + 0.035, x1 - 0.035):
        for y in (C.PLINTH_Y[0] + m, C.PLINTH_Y[1] - m):
            parts += _screw((x, y, SLAB_Z[2]), r=0.0017)


def _deck(parts):
    _slab(parts, *C.PLINTH_X, "plinth")
    ax, ay = C.ARM_OFFSET[0], C.ARM_OFFSET[1]
    # arm board + collar the tonearm pillar drops into
    board = M.cylinder(0.036, 0.0015, 64, bevel=0.0005, bevel_segments=1, material="brushed_aluminium_radial")
    parts.append(board.translate(ax, ay, TOP).uv_radial(0.036, center=(ax, ay, 0)).named("arm_board"))
    collar = M.tube(0.0195, 0.0135, 0.0105, 48, bevel=0.0012, bevel_segments=2, material="gunmetal")
    parts.append(collar.translate(ax, ay, TOP + 0.0015).named("arm_collar"))
    parts.append(M.tube(0.0197, 0.0186, 0.0006, 48, material="teal_plastic")
                 .translate(ax, ay, TOP + 0.0015 + 0.0045).named("arm_collar_accent"))
    # cue lever beside the arm base
    cx, cy = 0.036, -0.088
    parts.append(M.cylinder(0.0075, 0.012, 32, bevel=0.0012, bevel_segments=2, material="satin_graphite")
                 .translate(cx, cy, TOP).named("cue_base"))
    rod = C.along(M.cylinder(0.0016, 0.030, 12, top=False, bottom=False, material="chrome"),
                  (cx, cy, TOP + 0.0095), (cx, cy + 0.030, TOP + 0.0135))
    parts.append(rod.named("cue_lever"))
    parts.append(M.uv_sphere(0.0034, 20, 10, center=(cx, cy + 0.031, TOP + 0.0137), material="gloss_black_plastic")
                 .named("cue_knob"))
    # arm rest: post + rubber cradle; the cradle's inner bottom is the contract rest top (z 0.825)
    rx, ry = C.ARM_REST_XY
    parts.append(M.tube(0.0085, 0.0040, 0.0025, 32, bevel=0.0006, material="brushed_aluminium_radial")
                 .translate(rx, ry, TOP).uv_radial(0.0085, center=(rx, ry, 0)).named("rest_flange"))
    parts.append(M.cylinder(0.0042, 0.0345, 24, top=False, bottom=False, material="gunmetal")
                 .translate(rx, ry, TOP).named("rest_post"))
    rc = C.ARM_REST_TOP + C.ARM_TUBE_R + 0.0002          # tube centre height (+0.2 mm play)
    ri = C.ARM_TUBE_R + 0.0002
    u = [(-0.0068, rc - 0.0105), (0.0068, rc - 0.0105), (0.0068, rc + 0.0022), (ri, rc + 0.0022)]
    u += [(ri * math.cos(a), rc + ri * math.sin(a)) for a in np.radians(np.linspace(0, -180, 13))]
    u += [(-ri, rc + 0.0022), (-0.0068, rc + 0.0022)]
    u = C.fillet_2d(u, 0.0013, 2, only={0, 1, 2, len(u) - 1})
    cradle = M.extrude(u, 0.006, bevel=0.0007, bevel_segments=2, z0=-0.003, material="rubber")
    parts.append(cradle.orient("+y", (rx, ry, 0)).named("rest_cradle"))
    # 45 adapter puck parked in the front-left corner
    px, py = 0.448, 0.158
    prof = M.arc_profile((0.0181, 0.0009), 0.0009, -90, 0, 2) + M.arc_profile((0.0181, 0.0033), 0.0009, 0, 90, 2)
    prof += [(0.0084, 0.0042, 0.0, 1.0)] + M.arc_profile((0.0084, 0.0050), 0.0008, -90, -180, 2, concave=True)
    prof += [(0.0076, 0.0068, 1.0, 0.0)] + M.arc_profile((0.0069, 0.0068), 0.0007, 0, 90, 2)
    prof += [(0.0044, 0.0075, 0.0, 1.0)] + M.arc_profile((0.0044, 0.0068), 0.0007, 90, 180, 2)
    prof += [(0.0037, 0.0, -1.0, 0.0)]
    puck = M.lathe(prof, 48, crease=50, material="brushed_aluminium_radial")
    parts.append(puck.translate(px, py, TOP).uv_radial(0.019, center=(px, py, 0)).named("adapter_45"))


LABEL_H = 0.0062                          # printed panel labels share one height (atlas entry height)


def _label(parts, entry, x, y, h=LABEL_H):
    parts.append(C.decal(entry, 0.0, (x, y, TOP + C.DECAL_OFF), height=h).named("label"))


def _knob(parts, x, y, label, value):
    """Knurled aluminium knob with a chamfered radial-brushed cap and a teal pointer, over a printed
    21-tick scale; ``value`` 0..10 sets the pointer on the 270 deg scale."""
    z = TOP + 0.0009                                   # small shadow gap above the panel
    r = C.KNOB_R
    grip = M.lathe([(r - 0.0007, 0.0, 0.0, -1.0), (r, 0.0007, 1.0, 0.0), (r, 0.0128, 1.0, 0.0)], 56,
                   material="tt_alu_knurl").uv_cylindrical("z")
    cap = M.lathe([(r, 0.0128), (r - 0.0013, 0.0146)] + [(r - 0.0021, 0.0150, 0.0, 1.0), (0.0, 0.0150, 0.0, 1.0)],
                  56, crease=35, material="brushed_aluminium_radial").uv_radial(r)
    under = M.disc(r - 0.0007, 0.0, 32, facing="-z", material="gunmetal")
    for p, n in ((grip, "knob_grip"), (cap, "knob_cap"), (under, "knob_base")):
        parts.append(p.translate(x, y, z).named(n))
    a = math.radians(135 + 270 * value / 10.0)          # print-space angle (y down, read from the front)
    d = np.array([-math.cos(a), math.sin(a)])           # image right = -X, image down = +Y
    mid = np.array([x, y]) + d * (r * 0.58)
    ptr = M.rounded_box((0.0013, r * 0.62, 0.0004), (0.0005, 0.0005, 0.0), 2, material="teal_plastic")
    ang = math.degrees(math.atan2(d[1], d[0])) - 90
    parts.append(ptr.rotate_z(ang).translate(mid[0], mid[1], z + 0.0150 + 0.0002).named("knob_pointer"))
    parts.append(C.decal("knob_ticks", 0.068, (x, y, TOP + C.DECAL_OFF)).named("knob_scale"))
    _label(parts, label, x, y + 0.045)


def _toggle(parts, x, y, front: bool):
    """Chrome bat-handle toggle on a hex nut and a brushed escutcheon; ``front`` = lever toward +Y."""
    parts.append(M.cylinder(0.0095, 0.0008, 40, bevel=0.0003, bevel_segments=1, material="brushed_aluminium_radial")
                 .translate(x, y, TOP).uv_radial(0.0095, center=(x, y, 0)).named("toggle_plate"))
    nut = M.extrude(M.regular_polygon_2d(0.0064, 6, start=0.0), 0.0020, bevel=0.0003, bevel_segments=1, material="chrome")
    parts.append(nut.translate(x, y, TOP + 0.0008).named("toggle_nut"))
    parts.append(M.cylinder(0.0040, 0.0040, 24, bevel=0.0005, bevel_segments=2, material="chrome")
                 .translate(x, y, TOP + 0.0028).named("toggle_bushing"))
    tilt = math.radians(24.0) * (1 if front else -1)
    p0 = np.array([x, y, TOP + 0.0050])
    p1 = p0 + 0.0165 * np.array([0.0, math.sin(tilt), math.cos(tilt)])
    lever = M.lathe([(0.0020, 0.0), (0.0013, 0.0165)], 16, material="chrome")
    parts.append(C.along(lever, p0, p1).named("toggle_lever"))
    parts.append(M.uv_sphere(0.0021, 16, 8, center=tuple(p1), material="chrome").named("toggle_tip"))


def _vu_meter(parts, collision, xc, y_front):
    e = math.radians(55)                               # face normal elevation
    n = np.array([0.0, math.cos(e), math.sin(e)])
    tdir = np.array([0.0, -math.sin(e), math.cos(e)])   # up the face
    face_w, face_h, bez = 0.128, 0.064, 0.0075
    width = face_w + 2 * bez + 0.014
    Lf = face_h + 2 * bez
    A = np.array([y_front, 0.0])
    B = A + [0.0, 0.006]
    Cc = B + Lf * tdir[1:]
    D = Cc + [-0.013, 0.0]
    E = np.array([D[0], 0.0])
    prof = C.fillet_2d([E, A, B, Cc, D], 0.0024, 3, only={1, 2, 3, 4})
    housing = M.extrude(prof, width, bevel=0.0016, bevel_segments=2, z0=-width / 2, material="satin_graphite")
    parts.append(housing.orient("+x", (xc, 0.0, TOP)).named("vu_housing"))
    # face centre on the slope, slightly proud of it
    mid2 = B + (Lf / 2) * tdir[1:]
    fc = np.array([xc, mid2[0], TOP + mid2[1]]) + n * 0.0006
    # the face runs 1 mm under the bezel on every side so its edge never meets the bezel's hole wall
    m = 0.001
    face = M.plane(face_w + 2 * m, face_h + 2 * m, center=tuple(fc), facing=tuple(n), material="vu_meter_amber",
                   rect=(-m / face_w, -m / face_h, 1 + m / face_w, 1 + m / face_h))
    parts.append(face.named("vu_face"))
    # chrome bezel standing proud around the face
    bez_out = M.rounded_rect_2d(face_w + 2 * bez, face_h + 2 * bez, 0.0055, 3)
    bez_in = M.rounded_rect_2d(face_w, face_h, 0.0025, 3)
    bezel = M.extrude(bez_out, 0.0028, holes=[bez_in], bevel=0.0010, bevel_segments=2, cap_bottom=False,
                      material="chrome")
    parts.append(bezel.orient(tuple(n), tuple(fc - n * 0.0008)).named("vu_bezel"))
    # needle (resting near -10 VU) from its pivot under the hood, and the black pivot hood
    pivot = np.array([0.0, -0.68 * face_h])
    ang = math.radians(-96.5)
    ndir = np.array([math.cos(ang), -math.sin(ang)])    # print space (y down) -> design (y up)
    p0, p1 = pivot + ndir * 0.024, pivot + ndir * (0.97 * face_h)
    mid = (p0 + p1) / 2
    needle = M.box((0.0008, float(np.linalg.norm(p1 - p0)), 0.0004), material="gloss_black_plastic")
    needle = needle.rotate_z(math.degrees(math.atan2(ndir[1], ndir[0])) - 90).translate(mid[0], mid[1], 0.0016)
    parts.append(needle.orient(tuple(n), tuple(fc)).named("vu_needle"))
    hood = np.array([(0.0165 * math.cos(a), -face_h / 2 + 0.0138 * math.sin(a))
                     for a in np.radians(np.linspace(0, 180, 17))])
    hood = M.extrude(hood, 0.0029, bevel=0.0006, bevel_segments=2, material="satin_graphite")
    parts.append(hood.orient(tuple(n), tuple(fc)).named("vu_hood"))
    collision.append(Box.from_minmax((xc - width / 2, E[0], TOP), (xc + width / 2, A[0], TOP + Cc[1]), "PLASTIC"))


def _panel(parts, collision):
    _slab(parts, *C.PANEL_X, "panel")
    yb, yf = -0.078, 0.056                              # back row (meter, plate, toggles), front row (knobs, keys)
    _vu_meter(parts, collision, -0.250, -0.036)
    # engraved name plate (back left)
    plate = M.extrude(M.rounded_rect_2d(0.096, 0.024, 0.0022, 3), 0.0016, bevel=0.0004, bevel_segments=1,
                      cap_bottom=False, z0=TOP, material="tt_plate")
    plate_top, plate_rest = C.facing(plate, (0, 0, 1), 0.99)
    px = -0.100
    parts.append(plate_top.uv_fit((0, 0, 1, 1), axis="+z").translate(px, yb, 0).named("name_plate"))
    parts.append(plate_rest.with_material("brushed_aluminium").translate(px, yb, 0).named("name_plate_edge"))
    for sx in (-1, 1):
        parts += _screw((px + sx * 0.0435, yb, TOP + 0.0016), r=0.0014)
    # power toggle (on, with its LED) and PHONO / LINE toggle (back right)
    tx_p, tx_m = -0.392, -0.442
    _toggle(parts, tx_p, yb, True)
    _toggle(parts, tx_m, yb, False)
    lx = tx_p + 0.031
    parts.append(M.hemisphere(0.0024, 16, 4, cap=False, material="led_teal").scale(1, 1, 0.75)
                 .translate(lx, yb, TOP).named("power_led"))
    parts.append(M.tube(0.0040, 0.0024, 0.0010, 24, bevel=0.0003, material="chrome").translate(lx, yb, TOP)
                 .named("led_bezel"))
    _label(parts, "power", tx_p, yb + 0.024)
    _label(parts, "phono", tx_m, yb + 0.024)
    _label(parts, "line", tx_m, yb - 0.035)
    # aluminium pinstripe between the rows
    parts.append(M.rounded_box((0.410, 0.0013, 0.0004), (0.0, 0.0005, 0.0), 2, center=(-0.250, -0.022, TOP + 0.0002),
                               material="brushed_aluminium").named("pinstripe"))
    # knobs
    _knob(parts, -0.090, yf, "volume", 7.0)
    _knob(parts, -0.190, yf, "tone", 5.0)
    # start/stop: black square key in a brushed aluminium bezel, play icon printed on it
    sx, sy = -0.300, yf
    bez = M.extrude(M.rounded_rect_2d(0.044, 0.044, 0.0045, 3), 0.0030,
                    holes=[M.rounded_rect_2d(0.0345, 0.0345, 0.0028, 3)],
                    bevel=0.0008, bevel_segments=2, cap_bottom=False, z0=TOP, material="brushed_aluminium")
    parts.append(bez.translate(sx, sy, 0).named("start_bezel"))
    key = M.extrude(M.rounded_rect_2d(0.0325, 0.0325, 0.0024, 3), 0.0062, bevel=0.0013, bevel_segments=3,
                    cap_bottom=False, z0=TOP, material="gloss_black_plastic")
    parts.append(key.translate(sx, sy, 0).named("start_key"))
    parts.append(C.decal("icon_play", 0.014, (sx, sy, TOP + 0.0062 + C.DECAL_OFF)).named("start_icon"))
    _label(parts, "start_stop", sx, sy + 0.036)
    # 33 / 45 keys with indicator LEDs (33 lit)
    for k, (x, txt) in enumerate(((-0.378, "33"), (-0.432, "45"))):
        key = M.extrude(M.rounded_rect_2d(0.032, 0.019, 0.0026, 3), 0.0050, bevel=0.0010, bevel_segments=2,
                        cap_bottom=False, z0=TOP, material="gloss_black_plastic")
        parts.append(key.translate(x, yf + 0.004, 0).named("speed_key"))
        parts.append(C.decal(txt, 0.0, (x, yf + 0.004, TOP + 0.0050 + C.DECAL_OFF), height=0.0085).named("speed_print"))
        led = M.hemisphere(0.0021, 16, 4, cap=False, material="led_teal" if k == 0 else "gloss_black_plastic")
        parts.append(led.scale(1, 1, 0.7).translate(x, yf - 0.0155, TOP).named("speed_led"))
        parts.append(M.tube(0.0034, 0.0021, 0.0009, 24, material="chrome").translate(x, yf - 0.0155, TOP)
                     .named("led_bezel"))
    _label(parts, "rpm", -0.405, yf + 0.036)


# --------------------------------------------------------------------------- model
def build(detail: float) -> ModelSpec:
    parts, collision = [], []
    _cabinet(parts)
    _legs(parts, collision)
    _deck(parts)
    _panel(parts, collision)
    collision += [
        Box.from_minmax((C.CAB_X[0], C.CAB_Y[0], C.LEG_TOP), (C.CAB_X[1], C.CAB_Y[1], C.CAB_TOP), "WOOD_SOLID_POLISHED"),
        Box.from_minmax((C.PLINTH_X[0], C.PLINTH_Y[0], C.CAB_TOP), (C.PLINTH_X[1], C.PLINTH_Y[1], TOP), "PLASTIC"),
        Box.from_minmax((C.PANEL_X[0], C.PLINTH_Y[0], C.CAB_TOP), (C.PANEL_X[1], C.PLINTH_Y[1], TOP), "PLASTIC"),
    ]
    lead_a, run_a = C.arm_angle(C.LEAD_IN), C.arm_angle(C.RUN_OUT)
    anchors = {
        "platter_offset": Anchor(C.PLATTER_OFFSET, note="nayzeee_tt_platter origin (centre of its bottom face)"),
        "record_offset": Anchor(C.RECORD_OFFSET, note="nayzeee_vinyl origin when seated on the slipmat"),
        "arm_offset": Anchor(C.ARM_OFFSET, note="nayzeee_tt_arm origin = pivot; rot z 0 = parked on the rest"),
        "stylus_local": Anchor(C.STYLUS_LOCAL, note="ARM-LOCAL stylus tip (not console space)"),
        "arm_rest_local": Anchor((C.ARM_REST_XY[0], C.ARM_REST_XY[1], C.ARM_REST_TOP),
                                 note="console-space top of the arm rest (arm-local y 0.225 rests here)"),
        "lead_in_radius": Anchor((C.LEAD_IN, 0, 0), (0, 0, round(lead_a, 3)),
                                 note="x = groove radius from the platter centre; rot z = arm angle there"),
        "run_out_radius": Anchor((C.RUN_OUT, 0, 0), (0, 0, round(run_a, 3)),
                                 note="x = groove radius from the platter centre; rot z = arm angle there"),
        "platter_radius": Anchor((C.PLATTER_R, 0, 0), note="x = platter radius"),
        "record_radius": Anchor((C.RECORD_R, 0, 0), note="x = record radius"),
        "spindle_top": Anchor((C.PLATTER_OFFSET[0], C.PLATTER_OFFSET[1], C.PLATTER_OFFSET[2] + C.SPINDLE_TOP),
                              note="console-space spindle tip"),
        "record_top": Anchor((C.RECORD_OFFSET[0], C.RECORD_OFFSET[1], C.RECORD_OFFSET[2] + C.RECORD_T),
                             note="console-space playing surface (stylus contact height)"),
    }
    return ModelSpec(
        name="nayzeee_console",
        parts=parts,
        collision=collision,
        anchors=anchors,
        lod=LodSettings(high_dist=16.0, archetype_lod_dist=120.0, hd_texture_dist=8.0, med_detail=0.35),
        description="Record Console: walnut mid-century cabinet on splayed legs, woven grille, deck plinth (left) "
                    "and control panel (right). Platter, tonearm and record are separate props at the anchors.",
        meta={
            "turntable": {
                "platter_offset": list(C.PLATTER_OFFSET), "record_offset": list(C.RECORD_OFFSET),
                "arm_offset": list(C.ARM_OFFSET), "stylus_local": list(C.STYLUS_LOCAL),
                "arm_rest": [C.ARM_REST_XY[0], C.ARM_REST_XY[1], C.ARM_REST_TOP],
                "platter_radius": C.PLATTER_R, "record_radius": C.RECORD_R, "record_thickness": C.RECORD_T,
                "lead_in_radius": C.LEAD_IN, "run_out_radius": C.RUN_OUT, "arm_length": C.ARM_LEN,
                "pivot_to_platter_centre": round(C.PIVOT_TO_CENTRE, 6),
                "arm_angle_lead_in_deg": round(lead_a, 3), "arm_angle_run_out_deg": round(run_a, 3),
                "arm_lift_deg": C.ARM_LIFT_DEG, "spin_deg_per_s_33rpm": C.SPIN_DEG_S,
                "deck_top": TOP, "spindle_top": C.PLATTER_OFFSET[2] + C.SPINDLE_TOP,
                "record_top": C.RECORD_OFFSET[2] + C.RECORD_T,
            },
            "render": {"pitch": 24},
        },
    )
