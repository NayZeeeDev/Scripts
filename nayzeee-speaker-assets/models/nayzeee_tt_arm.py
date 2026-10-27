"""nayzeee_tt_arm -- tonearm: gimbal pivot base, straight chrome arm tube, counterweight at the back,
black headshell (offset angle) with a finger lift, cartridge with a teal stylus holder.

Model space (shared contract): origin = the PIVOT point (console attach offset 0.075, -0.125, 0.835).
At rotation 0 the arm points along +Y and lies on the console's arm rest; the stylus tip is at
exactly (0, 0.250, -0.022).  Gameplay rotates the model about Z (negative = swing over the record)
and tips it up with a positive rotation about local X (about 3 deg) to lift the needle.

The arm tube (radius 4 mm, centre z -0.006) rests with its bottom on the rest post top (z -0.010,
arm-local y 0.225).  The round pillar reaches down into the collar on the console's arm board, so the
small lift tilt stays hidden inside it.
"""
import math

from lib import mesh as M
from lib.spec import Anchor, Capsule, Cylinder, LodSettings, ModelSpec
from models import _tt_common as C

TZ = C.ARM_TUBE_Z                     # -0.006 tube centre height
TR = C.ARM_TUBE_R                     # 0.004
TIP = C.STYLUS_LOCAL                  # (0, 0.250, -0.022)
TY = TIP[1]
OFFSET = -18.0                        # headshell offset angle (cartridge turned toward the spindle side)
COLLAR_Y = (0.2290, 0.2370)           # tube -> headshell connector (the rest cradle ends at y 0.228)
PLATE_Z = (-0.0118, -0.0090)          # headshell plate
CART_Z = (-0.0190, -0.0118)           # cartridge body


def _y_lathe(profile, segments, material, y0=0.0, toward=+1, z=TZ):
    """Lathe around local Z, then lay it along +Y (toward=+1) or -Y (toward=-1) from y0 at height z."""
    m = M.lathe(profile, segments, material=material)
    m = m.rotate_x(-90.0 if toward > 0 else 90.0)
    return m.translate(0, y0, z)


def _headshell_frame(mesh):
    """Turn a part authored straight along +Y about the stylus tip by the offset angle."""
    return mesh.rotate_z(OFFSET, origin=(TIP[0], TIP[1], 0.0))


def _base(parts):
    # pillar: reaches into the console collar (deck top is at local z -0.050, collar top -0.038)
    pil = [(0.0115, -0.047, 1.0, 0.0), (0.0115, -0.0272, 1.0, 0.0)]
    pil += M.arc_profile((0.0107, -0.0272), 0.0008, 0, 90, 2)
    pil += [(0.0, -0.0264, 0.0, 1.0)]
    parts.append(M.lathe(pil, 40, material="gunmetal").named("pillar"))
    # knurled height-lock ring just above the collar
    for p in C.knurled_ring(0.0135, 0.0115, 0.006, 40, 0.0006):
        parts.append(p.translate(0, 0, -0.0365).named("height_ring"))
    # yaw bearing housing
    hz0, hz1 = -0.0262, -0.0160
    parts.append(M.cylinder(0.0175, hz1 - hz0, 48, bevel=0.0016, bevel_segments=3, material="satin_graphite")
                 .translate(0, 0, hz0).named("bearing_housing"))
    parts.append(M.tube(0.0177, 0.0150, 0.0008, 48, material="brushed_aluminium_radial")
                 .translate(0, 0, hz1 - 0.0003).uv_radial(0.0177).named("housing_trim"))
    # gimbal yoke: U bracket across X, bearing axis along X through the pivot (z 0)
    out = [(-0.0185, -0.0160), (0.0185, -0.0160), (0.0185, 0.0)]
    out += [(0.0140 + 0.0045 * math.cos(t), 0.0045 * math.sin(t)) for t in
            [math.radians(a) for a in range(0, 181, 15)]][1:]
    out += [(0.0095, -0.0120), (-0.0095, -0.0120)]
    out += [(-0.0140 + 0.0045 * math.cos(t), 0.0045 * math.sin(t)) for t in
            [math.radians(a) for a in range(0, 181, 15)]]
    yoke = M.extrude(C.fillet_2d(out, 0.0012, 2, only={0, 1, 15, 16}), 0.011, bevel=0.0007, bevel_segments=2,
                     z0=-0.0055, material="gunmetal").orient("+y", (0, 0, 0))
    parts.append(yoke.named("yoke"))
    # bearing caps (chrome) on the outside of the yoke, axis = local X through the pivot
    for sx in (-1, 1):
        cap = M.cylinder(0.0034, 0.0022, 32, bevel=0.0007, bevel_segments=2, material="chrome")
        parts.append(cap.rotate_y(90 * sx).translate(sx * 0.0185, 0, 0).named("bearing_cap"))
    # arm hub between the yoke cheeks: carries the tube (front) and the counterweight stub (back)
    hub = M.rounded_box((0.0170, 0.026, 0.0150), 0.0022, 3, center=(0, 0, -0.0040), material="satin_graphite")
    parts.append(hub.named("arm_hub"))
    # teal hairline on the hub sides (the lane's one accent besides the stylus holder)
    for sx in (-1, 1):
        parts.append(M.box((0.0004, 0.0200, 0.0012), center=(sx * 0.0087, 0, -0.0005), material="teal_plastic")
                     .named("hub_accent"))


def _tube_and_weight(parts):
    tube_len = COLLAR_Y[0] + 0.001 - 0.012
    tube = M.cylinder(TR, tube_len, 40, top=False, bottom=False, material="chrome")
    parts.append(tube.rotate_x(-90).translate(0, 0.012, TZ).named("arm_tube"))
    # counterweight shaft (back) with a chrome end cap
    stub = M.cylinder(0.0035, 0.058, 32, top=False, bottom=False, material="chrome")
    parts.append(stub.rotate_x(90).translate(0, -0.012, TZ).named("weight_shaft"))
    endcap = [(0.0035, 0.0, 1.0, 0.0), (0.0035, 0.0012, 1.0, 0.0)]
    endcap += M.arc_profile((0.0027, 0.0012), 0.0008, 0, 90, 2) + [(0.0, 0.0020, 0.0, 1.0)]
    parts.append(_y_lathe(endcap, 32, "chrome", y0=-0.070, toward=-1).named("shaft_cap"))
    # counterweight: knurled scale ring, teal hairline, black anodised body with grip grooves
    for p in C.knurled_ring(0.0168, 0.0035, 0.0064, 56, 0.0006):
        parts.append(p.rotate_x(90).translate(0, -0.0330, TZ).named("weight_ring"))
    teal = M.tube(0.0166, 0.0036, 0.0008, 56, material="teal_plastic")
    parts.append(teal.rotate_x(90).translate(0, -0.0396, TZ).named("weight_accent"))
    body = [(0.0036, 0.0, 0.0, -1.0), (0.0172, 0.0, 0.0, -1.0)]
    for g in (0.0060, 0.0095, 0.0130):                  # three grip grooves
        body += [(0.0175, g - 0.0018, 1.0, 0.0)]
        body += M.arc_profile((0.0175, g), 0.0009, -90, -270, 3, concave=True)
        body += [(0.0175, g + 0.0018, 1.0, 0.0)]
    body += [(0.0175, 0.0200, 1.0, 0.0)]
    body += M.arc_profile((0.0145, 0.0200), 0.0030, 0, 90, 4)
    body += [(0.0036, 0.0230, 0.0, 1.0)]
    weight = _y_lathe(body, 56, "satin_graphite", y0=-0.0406, toward=-1)
    parts.append(weight.named("counterweight"))


def _headshell(parts):
    # connector collar (brushed) with a locking groove, plus the headshell plug
    col = [(TR - 0.0002, 0.0, 0.0, -1.0), (0.0050, 0.0, 0.0, -1.0)]
    col += M.arc_profile((0.0044, 0.0006), 0.0006, -90, 0, 2)
    col += [(0.0050, 0.0030, 1.0, 0.0), (0.0046, 0.0034), (0.0046, 0.0042), (0.0050, 0.0046, 1.0, 0.0)]
    col += [(0.0050, 0.0074, 1.0, 0.0)] + M.arc_profile((0.0044, 0.0074), 0.0006, 0, 90, 2)
    col += [(0.0040, 0.0080, 0.0, 1.0)]
    parts.append(_y_lathe(col, 40, "brushed_aluminium", y0=COLLAR_Y[0]).uv_cylindrical("y").named("collar"))
    # headshell neck: a solid tapered plug out of the collar, nosing down into the plate
    neck_p = [(0.0040, 0.0, 1.0, 0.0), (0.0036, 0.0050), (0.0030, 0.0072)]
    neck_p += M.arc_profile((0.0018, 0.0072), 0.0012, 0, 90, 3) + [(0.0, 0.0084, 0.0, 1.0)]
    parts.append(_y_lathe(neck_p, 32, "gloss_black_plastic", y0=COLLAR_Y[1] - 0.0002).named("headshell_plug"))
    # headshell plate: neck in line with the tube + cartridge mount turned by the offset angle
    neck = [(-0.0046, COLLAR_Y[1] - 0.0004), (0.0046, COLLAR_Y[1] - 0.0004), (0.0046, COLLAR_Y[1] + 0.006),
            (-0.0046, COLLAR_Y[1] + 0.006)]
    mount = M.rounded_rect_2d(0.0190, 0.0280, 0.0035, 4, center=(0.0, TY + 0.0040))
    mount = C.rotate_2d(mount, OFFSET, (0.0, TY))
    outline = C.hull_2d(list(neck) + [tuple(p) for p in mount])
    outline = C.fillet_2d(outline, 0.0018, 2)
    plate = M.extrude(outline, PLATE_Z[1] - PLATE_Z[0], bevel=0.0007, bevel_segments=2, z0=PLATE_Z[0],
                      material="gloss_black_plastic")
    parts.append(plate.named("headshell"))
    hs = []
    # finger lift: a flat strip off the outside (-X) edge, curling up and out
    path = M.catmull_rom_path([(-0.0080, TY + 0.0105, PLATE_Z[1] - 0.0010), (-0.0150, TY + 0.0125, PLATE_Z[1] - 0.0008),
                               (-0.0215, TY + 0.0135, PLATE_Z[1] + 0.0015), (-0.0250, TY + 0.0138, PLATE_Z[1] + 0.0060)], 5)
    lift = M.sweep(M.rounded_rect_section(0.0012, 0.0046, 0.0005, 2), path, up=(0, 0, 1),
                   material="gloss_black_plastic")
    hs.append(lift.named("finger_lift"))
    # cartridge body (matte black), teal stylus holder, aluminium cantilever, diamond tip
    cart = M.rounded_box((0.0165, 0.0180, CART_Z[1] - CART_Z[0]), 0.0011, 2,
                         center=(0, TY - 0.0015, (CART_Z[0] + CART_Z[1]) / 2), material="matte_black_plastic")
    hs.append(cart.named("cartridge"))
    holder = M.rounded_box((0.0100, 0.0095, 0.0020), 0.0006, 2, center=(0, TY - 0.0012, CART_Z[0] - 0.0008),
                           material="teal_plastic")
    hs.append(holder.named("stylus_holder"))
    L = ((0.0032) ** 2 + (CART_Z[0] - 0.0016 - TIP[2] - 0.00045) ** 2) ** 0.5
    cant = C.along(M.cylinder(0.00042, L, 10, top=False, bottom=False, material="brushed_aluminium"),
                   (0, TY - 0.0032, CART_Z[0] - 0.0016), (0, TY, TIP[2] + 0.00045))
    hs.append(cant.named("cantilever"))
    tip = M.cone(0.00045, 0.0, 0.00045, 8, material="chrome").rotate_x(180).translate(0, TY, TIP[2] + 0.00045)
    hs.append(tip.named("stylus_tip"))
    # mounting screws on the plate top + the brand on the cartridge's outer side
    for dy in (-0.0025, 0.0095):                        # centred on the cartridge mount, clear of the neck
        sc = M.hemisphere(0.0016, 16, 3, cap=False, material="chrome").scale(1, 1, 0.45)
        hs.append(sc.translate(0, TY + dy, PLATE_Z[1]).named("screw"))
    word = C.decal("wordmark", 0.0125, (-0.00825 - C.DECAL_OFF, TY - 0.0015, (CART_Z[0] + CART_Z[1]) / 2), "-x")
    hs.append(word.named("cartridge_print"))
    parts += [_headshell_frame(p) for p in hs]


def build(detail: float) -> ModelSpec:
    parts = []
    _base(parts)
    _tube_and_weight(parts)
    _headshell(parts)
    return ModelSpec(
        name="nayzeee_tt_arm",
        parts=parts,
        collision=[Cylinder((0, 0, -0.047), (0, 0, 0.0045), 0.0185, "METAL_SOLID_SMALL"),
                   Capsule((0, 0.012, TZ), (0, 0.236, TZ), 0.006, "METAL_SOLID_SMALL"),
                   Cylinder((0, -0.033, TZ), (0, -0.064, TZ), 0.0175, "METAL_SOLID_SMALL"),
                   Capsule((0, 0.236, PLATE_Z[1] - 0.004), (0, 0.262, PLATE_Z[1] - 0.004), 0.010, "PLASTIC")],
        anchors={
            "pivot": Anchor((0, 0, 0), note="model origin = pivot; rotate about Z to swing (negative = over the "
                                            "record), about local X to lift the tip (positive, ~3 deg)"),
            "stylus_tip": Anchor(TIP, note="needle tip; touches the record top (console z 0.8132) when level"),
            "rest_contact": Anchor((0, C.ARM_REST_LOCAL_Y, TZ - TR), note="tube underside resting on the arm "
                                                                          "rest post (console 0.075, 0.100, 0.825)"),
            "finger_lift": Anchor((-0.022, TY + 0.012, PLATE_Z[1] + 0.003), note="finger lift (before the offset turn)"),
        },
        lod=LodSettings(high_dist=6.0, archetype_lod_dist=60.0, hd_texture_dist=3.0, med_detail=0.4),
        description="Tonearm: gimbal pivot, chrome tube, counterweight, offset headshell with finger lift and a "
                    "teal-accented cartridge. Origin = pivot (console attach offset 0.075, -0.125, 0.835).",
        meta={
            "arm_length": C.ARM_LEN, "stylus_local": list(TIP), "console_attach_offset": list(C.ARM_OFFSET),
            "tube_centre_z": TZ, "tube_radius": TR, "headshell_offset_deg": OFFSET,
            "rest_local_y": C.ARM_REST_LOCAL_Y, "lift_deg": C.ARM_LIFT_DEG,
            "angle_lead_in_deg": round(C.arm_angle(C.LEAD_IN), 3),
            "angle_run_out_deg": round(C.arm_angle(C.RUN_OUT), 3),
            "render": {"yaw": 55, "pitch": 24},
        },
    )
