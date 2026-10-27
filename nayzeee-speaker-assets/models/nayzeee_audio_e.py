"""nayzeee_audio_e -- "Carry Cube": a compact rugged cube speaker.

A 300 mm satin graphite cube (20 mm radii) rides on eight thick black rubber corner caps -- the
bottom four are its feet.  A recessed teal band wraps over the top, down both sides and under the
base just behind the front face.  Front: one woofer behind a domed, round-hole perforated graphite
steel grille with a rolled gunmetal rim, sitting 10 mm deep in a circular recess (brushed aluminium lip,
dark shadow gap), a raised teal mark badge at its centre.  Top: a fold-down bail handle -- two brushed aluminium straps pivoting on gunmetal
hinge blocks (chrome pivot caps), a knurled rubber grip with teal ferrules.  Viewer's right side: a
rubber control strip with five rubber keys (power with a teal status LED, bluetooth, play, - / +).
Back: a flared bass port, a brushed connector plate (AUX, USB-C, DC in) and prints.

Model space: origin = floor centre under the model, +Y = front, +X = viewer's left.
"""
import numpy as np

from lib import mesh as M
from lib.spec import Anchor, Box, Cylinder, LodSettings, ModelSpec
from models import _aeb_kit as K

NAME = __name__.rsplit(".", 1)[-1]

T = 0.008                                   # rubber cap thickness
HB = 0.150                                  # body half size (0.30 cube)
RC = 0.020                                  # body edge radius
ZC = T + HB                                 # body centre height
TOP = ZC + HB                               # body top surface
CAP_S = 0.074                               # corner cap box size
R_CAP = RC + T                              # corner cap radius (concentric with the body corner)
Y_STRIPE, W_STRIPE, D_STRIPE = 0.034, 0.010, 0.0016
R_G = 0.1165                                # grille recess radius
LIP = 0.0018                                # rounded lip into the recess
G_DY = 0.006                                # grille centre above the body centre
Y_HG = -0.022                               # handle hinge line (y)
Z_PIV = TOP + 0.012                         # pivot axis height
Z_BAR = TOP + 0.087                         # grip centre height
X_ARM = 0.1065                              # inner face of the bail arms
ARM_T = 0.0060                              # arm thickness
R_GRIP = 0.0132

OUTLINE = M.rounded_rect_2d(2 * HB, 2 * HB, RC, 8)
BODY_SDF = K.sdf_rounded_box((0.0, 0.0, ZC), (2 * HB, 2 * HB, 2 * HB), RC)


def _design(m, facing="+y"):
    return m.orient(facing, (0.0, 0.0, ZC))


# --------------------------------------------------------------------------- body
def _body(parts, d):
    arc = M.arc_profile
    y0, y1 = Y_STRIPE - W_STRIPE / 2, Y_STRIPE + W_STRIPE / 2
    back = arc((-RC, -HB + RC), RC, -90, 0, 5) + [(0.0, y0, 1.0, 0.0)]
    groove_back = [(0.0, y0), (-D_STRIPE, y0)]
    groove_floor = [(-D_STRIPE, y0, 1.0, 0.0), (-D_STRIPE, y1, 1.0, 0.0)]
    groove_front = [(-D_STRIPE, y1), (0.0, y1)]
    front = [(0.0, y1, 1.0, 0.0)] + arc((-RC, HB - RC), RC, 0, 90, 5)
    for prof, mat, nm in ((back, "satin_graphite", "body"), (groove_back, "satin_graphite", "stripe_groove"),
                          (groove_floor, "teal_plastic", "stripe"), (groove_front, "satin_graphite", "stripe_groove"),
                          (front, "satin_graphite", "body")):
        parts.append(_design(K.loft(OUTLINE, prof, material=mat)).named(nm))
    # front face with the grille recess, back face with the port
    n_g = K.nseg(64)
    hole = K.ring2d(R_G + LIP, n_g, (0.0, G_DY))
    front_cap = K.cap(OUTLINE, HB, offset=-RC, holes=[hole], material="satin_graphite")
    parts.append(_design(front_cap).uv_planar("+y").named("front_face"))
    _grille(parts, n_g, d)
    n_p = K.nseg(40)
    port_c = (0.060, -0.056)                         # shell design space: x = viewer's right seen from the FRONT
    back_cap = K.cap(OUTLINE, -HB, offset=-RC, holes=[K.ring2d(0.031, n_p, port_c)], up=False,
                     material="satin_graphite")
    parts.append(_design(back_cap).uv_planar("-y").named("back_face"))
    _back(parts, port_c, n_p, d)


def _grille(parts, n, d):
    """Recess wall + dark floor ring + domed perforated grille with a rolled rim (local z = 0 = front face)."""
    out = []
    lip = K.lathe_n(M.arc_profile((R_G + LIP, -LIP), LIP, 90, 180, 3), n, material="brushed_aluminium_radial")
    out.append(lip.uv_radial(R_G + LIP).named("grille_lip"))
    out.append(K.lathe_n([(R_G, -LIP, -1.0, 0.0), (R_G, -0.0100, -1.0, 0.0)], n, material="satin_graphite")
               .named("grille_recess"))
    out.append(K.lathe_n([(R_G, -0.0100, 0.0, 1.0), (0.1100, -0.0100, 0.0, 1.0)], n, material="matte_black_plastic")
               .named("grille_floor"))
    rim = [(0.1138, -0.0100, 1.0, 0.0), (0.1138, -0.0068, 1.0, 0.0)] + M.arc_profile((0.1113, -0.0068), 0.0025, 0, 90, 3)
    rim += [(0.1080, -0.0043, 0.0, 1.0)]
    out.append(K.lathe_n(rim, n, crease=50, material="gunmetal").named("grille_rim"))
    dome = [(0.1080, -0.0043)] + K.dome(0.1060, -0.0050, -0.0008, 6)
    g = K.lathe_n(dome, n, crease=60, material="spk_grille_graphite").uv_planar("+z")
    out.append(g.named("grille"))
    # raised teal mark badge on the grille centre
    mk, bar = M.mark_2d(0.034, 4)
    badge = M.extrude(mk, 0.0020, holes=[bar], bevel=0.0006, bevel_segments=2, cap_bottom=False, z0=-0.0013,
                      material="teal_plastic")
    out.append(badge.named("grille_badge"))
    for p in out:
        parts.append(_design(p.translate(0.0, G_DY, HB)).named(p.name))


def _back(parts, port_c, n, d):
    yb = -HB
    rh, rt, L = 0.031, 0.023, 0.090
    fr = rh - rt
    prof = [(0.0, yb + L, 0.0, -1.0), (rt, yb + L), (rt, yb + fr, -1.0, 0.0)] + M.arc_profile((rh, yb + fr), fr, 180, 270, 3)
    port = K.lathe_n(prof, n, crease=50, material="matte_black_plastic").translate(port_c[0], port_c[1], 0)
    parts.append(_design(port).named("bass_port"))
    ring = K.lathe_n([(rh + 0.0040, 0.0), (rh + 0.0040, 0.0009), (rh + 0.0014, 0.0009), (rh + 0.0014, 0.0)],
                     n, crease=50, material="teal_plastic").translate(port_c[0], port_c[1], 0)
    parts.append(_design(ring.mirror("z", 0.0).translate(0, 0, yb)).named("port_ring"))
    # brushed connector plate (seen from behind: image right = +X)
    cz = ZC + 0.060
    plate = M.extrude(M.rounded_rect_2d(0.120, 0.044, 0.006, 4), 0.0016, bevel=0.0005, bevel_segments=1,
                      cap_bottom=False, material="brushed_aluminium")
    parts.append(plate.orient("-y", (0.0, yb, cz)).named("io_plate"))
    yp = yb - 0.0016
    for sx in (-1, 1):
        parts += K.screw((sx * 0.052, yp, cz), "-y", 0.0018, "chrome", d)
    parts += K.jack((0.026, yp, cz + 0.005), "-y", 0.0056, "teal_plastic")
    parts += K.usb_c((0.000, yp, cz + 0.005), "-y")
    parts += K.dc_inlet((-0.026, yp, cz + 0.005), "-y")
    for x, e in ((0.026, "aux"), (-0.026, "power")):
        parts.append(K.decal(e, (x, yp - K.DECAL_OFF, cz - 0.011), "-y", height=0.0048).named("io_label"))
    # prints: seen from behind the port is on the left (world -X), the prints on the right (world +X)
    parts.append(K.decal("mark_white", (0.060, yb - K.DECAL_OFF, ZC - 0.028), "-y", width=0.022).named("back_mark"))
    parts.append(K.decal("carry_cube", (0.060, yb - K.DECAL_OFF, ZC - 0.054), "-y", height=0.0085).named("back_print"))
    parts.append(K.decal("nayzeee_audio", (0.060, yb - K.DECAL_OFF, ZC - 0.071), "-y", height=0.0052)
                 .named("back_print"))


# --------------------------------------------------------------------------- rubber corner caps
def _caps(parts, d):
    seg = 6 if d >= 0.6 else 4
    caps = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                c = np.array([sx, sy, sz]) * (HB + T - CAP_S / 2) + np.array([0.0, 0.0, ZC])
                caps.append(c)
                b = M.rounded_box((CAP_S,) * 3, R_CAP, seg, center=tuple(c), material="rubber")
                parts.append(K.cull_inside(b, BODY_SDF, 0.0004).named("corner_cap"))
    # the body under the caps is hidden: drop it
    sdfs = [K.sdf_rounded_box(c, (CAP_S,) * 3, R_CAP) for c in caps]
    for i, p in enumerate(parts):
        if p.material in ("satin_graphite", "teal_plastic") and p.name in ("body", "stripe", "stripe_groove",
                                                                          "front_face", "back_face"):
            for f in sdfs:
                p = K.cull_inside(p, f, 0.0004)
            parts[i] = p


# --------------------------------------------------------------------------- fold handle
def _handle(parts, d):
    # hinge blocks on the top
    for sx in (-1, 1):
        bx = sx * (X_ARM - 0.0125)
        blk = M.rounded_box((0.024, 0.030, 0.026), (0.0045, 0.0045, 0.0045), 4, center=(bx, Y_HG, TOP + 0.012),
                            material="gunmetal")
        parts.append(K.cull_inside(blk, BODY_SDF, 0.0003).named("hinge_block"))
        parts += K.screw((bx, Y_HG + 0.006, TOP + 0.025), "+z", 0.0024, "chrome", d)
        parts += K.screw((bx, Y_HG - 0.006, TOP + 0.025), "+z", 0.0024, "chrome", d)
    # bail arms: stadium straps from the pivot eye up past the grip
    L = Z_BAR - Z_PIV
    strap = M.rounded_rect_2d(0.020, L + 0.020, 0.0099, 6, center=(0.0, L / 2))
    for sx, fac in ((1, "+x"), (-1, "-x")):
        arm = M.extrude(strap, ARM_T, bevel=0.0012, bevel_segments=2, material="brushed_aluminium")
        arm = arm.orient(fac, (sx * X_ARM, Y_HG, Z_PIV))
        flat, edges = K.facing(arm, (sx, 0.0, 0.0), 0.999)
        parts.append(flat.uv_planar(fac, 0.15, rotate=90.0).named("bail_arm"))
        parts.append(edges.named("bail_arm"))
        xo = sx * (X_ARM + ARM_T)
        for z, r in ((Z_PIV, 0.0052), (Z_BAR, 0.0040)):
            cap = M.hemisphere(r, 16, 3, cap=False, material="chrome").scale(1, 1, 0.42)
            parts.append(cap.orient(fac, (xo, Y_HG, z)).named("pivot_cap"))
    # grip: knurled rubber, teal ferrules into the arms (lathe along Z, turned onto X)
    fer = [(0.0108, -X_ARM, 1.0, 0.0), (0.0108, -X_ARM + 0.008, 1.0, 0.0), (0.0124, -0.0920),
           (0.0124, -0.0830, 1.0, 0.0)]
    grip = [(0.0124, -0.0830, 0.0, -1.0), (R_GRIP - 0.0006, -0.0830, 0.0, -1.0)]
    grip += M.arc_profile((R_GRIP - 0.0006, -0.0824), 0.0006, -90, 0, 2)
    grip += [(R_GRIP + 0.0010, -0.045, 1.0, 0.0), (R_GRIP + 0.0015, 0.0, 1.0, 0.0), (R_GRIP + 0.0010, 0.045, 1.0, 0.0)]
    grip += M.arc_profile((R_GRIP - 0.0006, 0.0824), 0.0006, 0, 90, 2) + [(0.0124, 0.0830, 0.0, 1.0)]
    fer2 = [(0.0124, 0.0830, 1.0, 0.0), (0.0124, 0.0920), (0.0108, X_ARM - 0.008, 1.0, 0.0), (0.0108, X_ARM, 1.0, 0.0)]
    for prof, mat, nm in ((fer, "teal_plastic", "grip_ferrule"), (grip, "rubber_grip", "grip"),
                          (fer2, "teal_plastic", "grip_ferrule")):
        m = M.lathe(prof, 32, crease=40, material=mat)
        if mat == "rubber_grip":
            m = m.uv_cylindrical("z")
        parts.append(m.rotate_y(90.0).translate(0.0, Y_HG, Z_BAR).named(nm))


# --------------------------------------------------------------------------- side controls (viewer's right = -X)
def _controls(parts, d):
    x = -HB
    yc, zc = -0.052, ZC
    strip = M.extrude(M.rounded_rect_2d(0.034, 0.172, 0.017, 6), 0.0020, bevel=0.0010, bevel_segments=2,
                      cap_bottom=False, material="rubber")
    parts.append(strip.orient("-x", (x, yc, zc)).uv_planar("-x").named("control_strip"))
    xs = x - 0.0020
    keys = [("icon_power", 0.056), ("icon_bluetooth", 0.028), ("icon_play", 0.0), ("icon_minus", -0.028),
            ("icon_plus", -0.056)]
    for icon, dz in keys:
        key = M.lathe([(0.0098, 0.0, 1.0, 0.0), (0.0098, 0.0016, 1.0, 0.0)] + M.arc_profile((0.0086, 0.0016), 0.0012, 0, 90, 2)
                      + [(0.0, 0.0030, 0.0, 1.0)], 28, crease=50, material="satin_graphite")
        parts.append(key.orient("-x", (xs, yc, zc + dz)).named("key"))
        parts.append(K.decal(icon, (xs - 0.0030 - K.DECAL_OFF, yc, zc + dz), "-x", width=0.0085).named("key_icon"))
    led = M.hemisphere(0.0016, 12, 3, cap=False, material="led_teal").scale(1, 1, 0.7)
    parts.append(led.orient("-x", (xs, yc, zc + 0.076)).named("status_led"))


def build(detail: float) -> ModelSpec:
    parts = []
    _body(parts, detail)
    _caps(parts, detail)
    _handle(parts, detail)
    _controls(parts, detail)
    z_top = Z_BAR + R_GRIP + 0.0016
    return ModelSpec(
        name=NAME,
        parts=parts,
        collision=[
            Box((0.0, 0.0, ZC), (2 * (HB + T), 2 * (HB + T), 2 * (HB + T)), "PLASTIC"),
            Cylinder((-X_ARM, Y_HG, Z_BAR), (X_ARM, Y_HG, Z_BAR), R_GRIP + 0.001, "RUBBER"),
        ],
        anchors={
            "grip": Anchor((0.0, Y_HG, Z_BAR), note="centre of the rubber grip, where the hand closes"),
            "top": Anchor((0.0, Y_HG, z_top), note="highest point (top of the grip)"),
            "front": Anchor((0.0, HB, ZC + G_DY), note="centre of the grille"),
        },
        lod=LodSettings(high_dist=14.0, archetype_lod_dist=100.0, hd_texture_dist=6.0, med_detail=0.4),
        description="Carry Cube: rounded cube speaker with rubber corner caps, perforated round grille, "
                    "fold-down bail handle, side keys and a teal band.",
        meta={"render": {"pitch": 18, "yaw": 34}},
    )
