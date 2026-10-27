"""nayzeee_tt_platter -- turntable platter: machined aluminium with a strobe rim, printed felt slipmat
and a chrome spindle.  Spawned by client/turntable.lua at the console's platter offset and spun
about +Z (200 deg/s at 33 1/3).

Model space (shared contract): origin = centre of the bottom face (sits on the deck top, console
z 0.785), radius 0.160, top of the slipmat at z 0.026 (record bottom = console z 0.811), spindle
radius 0.0035 with its top at z 0.040.

The platter body floats 4 mm above the deck on a dark bearing hub, so it reads as a separate,
spinning part with a shadow gap.  Everything is a surface of revolution except the printed slipmat
and the strobe dots, which show the rotation.
"""
from lib import mesh as M
from lib.spec import Anchor, Cylinder, LodSettings, ModelSpec
from models import _tt_common as C

R = C.PLATTER_R                  # 0.160
TOP = C.SLIPMAT_TOP              # 0.026
MAT_T = 0.003                    # slipmat thickness
RIM_TOP = TOP - MAT_T            # 0.023: aluminium top ring around the mat
GAP = 0.004                      # underside height (bearing hub below)
MAT_R = 0.1500
CH = 0.0012                      # rim chamfers
SEG = 128


def build(detail: float) -> ModelSpec:
    parts = []
    # bearing hub: a dark collar between the deck and the platter (open bottom, hidden by the deck)
    hub = M.lathe([(0.032, 0.0), (0.032, GAP), (0.031, GAP + 0.0004)], 48, material="gunmetal")
    parts.append(hub.named("bearing_hub"))
    # underside + chamfers + top ring: spun aluminium (uv_radial -> concentric brushing)
    under = M.lathe([(0.031, GAP + 0.0004), (R - CH, GAP)], SEG, material="brushed_aluminium_radial")
    low_ch = M.lathe([(R - CH, GAP), (R, GAP + CH)], SEG, material="brushed_aluminium_radial")
    up_ch = M.lathe([(R, RIM_TOP - CH), (R - CH, RIM_TOP)], SEG, material="brushed_aluminium_radial")
    ring = M.lathe([(R - CH, RIM_TOP), (MAT_R - 0.0006, RIM_TOP)], SEG, material="brushed_aluminium_radial")
    for p, n in ((under, "underside"), (low_ch, "rim_chamfer_low"), (up_ch, "rim_chamfer_top"), (ring, "top_ring")):
        parts.append(p.uv_radial(R).named(n))
    # rim wall with the strobe dots (4 rows; 9 texture repeats around)
    wall = M.lathe([(R, GAP + CH), (R, RIM_TOP - CH)], SEG, material="tt_platter_strobe")
    parts.append(C.uv_around(wall, C.STROBE_REPEATS, GAP + CH, RIM_TOP - CH).named("strobe_rim"))
    # felt slipmat: rounded top edge, sits in the aluminium ring, hole fits the spindle
    er = 0.0009
    mat_prof = [(MAT_R, RIM_TOP - 0.0003, 1.0, 0.0), (MAT_R, TOP - er, 1.0, 0.0)]
    mat_prof += M.arc_profile((MAT_R - er, TOP - er), er, 0, 90, 3)
    mat_prof += [(C.SPINDLE_R + 0.0002, TOP, 0.0, 1.0)]
    slip = M.lathe(mat_prof, SEG, crease=50, material="tt_slipmat").uv_radial(MAT_R)
    parts.append(slip.named("slipmat"))
    # chrome spindle with a domed tip (nothing above the mat but the spindle: the record lies flat on it)
    sp = [(C.SPINDLE_R, TOP - 0.0006, 1.0, 0.0), (C.SPINDLE_R, C.SPINDLE_TOP - 0.0016, 1.0, 0.0)]
    sp += M.arc_profile((C.SPINDLE_R - 0.0016, C.SPINDLE_TOP - 0.0016), 0.0016, 0, 90, 4)
    sp += [(0.0, C.SPINDLE_TOP, 0.0, 1.0)]
    parts.append(M.lathe(sp, 32, crease=60, material="chrome").named("spindle"))

    return ModelSpec(
        name="nayzeee_tt_platter",
        parts=parts,
        collision=[Cylinder((0, 0, 0), (0, 0, TOP), R, "METAL_SOLID_SMALL"),
                   Cylinder((0, 0, TOP), (0, 0, C.SPINDLE_TOP), C.SPINDLE_R, "METAL_SOLID_SMALL")],
        anchors={
            "bottom_centre": Anchor((0, 0, 0), note="model origin = centre of the bottom face; sits on the deck top"),
            "record_seat": Anchor((0, 0, TOP), note="top of the slipmat: nayzeee_vinyl origin goes here"),
            "spindle_top": Anchor((0, 0, C.SPINDLE_TOP), note="tip of the spindle"),
            "rim": Anchor((R, 0, (GAP + RIM_TOP) / 2), note="strobe rim, radius 0.160"),
        },
        lod=LodSettings(high_dist=8.0, archetype_lod_dist=60.0, hd_texture_dist=4.0, med_detail=0.35),
        description="Turntable platter: spun aluminium with a strobe rim, printed felt slipmat, chrome spindle. "
                    "Spins about +Z on the record console (attach offset 0.300, 0, 0.785).",
        meta={
            "radius": R, "slipmat_top": TOP, "spindle_radius": C.SPINDLE_R, "spindle_top": C.SPINDLE_TOP,
            "console_attach_offset": list(C.PLATTER_OFFSET), "spin_axis": "+Z", "spin_deg_per_s_33rpm": C.SPIN_DEG_S,
            "render": {"pitch": 30},
        },
    )
