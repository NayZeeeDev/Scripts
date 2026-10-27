"""nayzeee_vinyl -- 12 inch record (see the shared contract, "Turntable geometry").

Model space: origin = centre of the bottom face, +Z up, disc in the XY plane.
  radius 0.1515, thickness 0.0022 (playing surface top at z = 0.0022, which is
  where the stylus touches: console z 0.811 + 0.0022 = 0.8132), spindle hole
  radius 0.0037, centre label radius 0.050 on both faces using the
  runtime-replaceable texture ``nayzeee_vinyl_label``.
Details: rounded outer edge, raised outer bead (+0.3 mm), slightly raised
label area (+0.15 mm), glossy black vinyl with the radial groove normal map
(track gaps, lead-in at r 0.146, run-out from r 0.062).
Resting attach offset on nayzeee_console: (0.300, 0.000, 0.811), spins about +Z.
"""
from lib import mesh as M
from lib.spec import Anchor, Cylinder, LodSettings, ModelSpec
from lib.textures import VINYL_LEAD_IN, VINYL_RUN_OUT

RADIUS = 0.1515
THICK = 0.0022
LABEL_R = 0.050
HOLE_R = 0.0037
BEAD_TOP = THICK + 0.0003        # raised outer rim
LABEL_TOP = THICK + 0.00015      # label area slightly raised
EDGE_R = BEAD_TOP / 2            # full round outer edge


def build(detail: float) -> ModelSpec:
    seg = 128
    ec = RADIUS - EDGE_R
    # vinyl body: bottom -> rounded edge -> bead -> playing surface -> label step
    prof = [(LABEL_R, 0.0, 0.0, -1.0), (ec, 0.0, 0.0, -1.0)]
    prof += M.arc_profile((ec, EDGE_R), EDGE_R, -90, 90, 8)
    prof += [(RADIUS - 0.0025, BEAD_TOP, 0.0, 1.0),
             (RADIUS - 0.0039, THICK),
             (LABEL_R + 0.0005, THICK),
             (LABEL_R, LABEL_TOP)]
    body = M.lathe(prof, seg, crease=5.0, material="vinyl_black").uv_radial(RADIUS).named("vinyl")
    # spindle hole wall
    hole = M.lathe([(HOLE_R, LABEL_TOP), (HOLE_R, 0.0)], 32, material="vinyl_black").uv_radial(RADIUS) \
        .named("spindle_hole")
    # printed labels, side A on top and side B underneath
    label_a = M.lathe([(LABEL_R, LABEL_TOP), (HOLE_R, LABEL_TOP)], seg, material="vinyl_label") \
        .uv_radial(LABEL_R, axis="+z").named("label_a")
    label_b = M.lathe([(HOLE_R, 0.0), (LABEL_R, 0.0)], seg, material="vinyl_label") \
        .uv_radial(LABEL_R, axis="-z").named("label_b")
    parts = [body, hole, label_a, label_b]

    return ModelSpec(
        name="nayzeee_vinyl",
        parts=parts,
        collision=[Cylinder((0, 0, 0), (0, 0, BEAD_TOP), RADIUS, "PLASTIC")],
        anchors={
            "bottom_centre": Anchor((0, 0, 0), note="model origin, sits on the slipmat"),
            "play_surface": Anchor((0, 0, THICK), note="groove surface height (stylus contact)"),
            "label_top": Anchor((0, 0, LABEL_TOP), note="top of the centre label"),
            "edge_grip": Anchor((RADIUS, 0, THICK / 2), (0, 0, 0), "edge of the disc for a hand-held carry"),
        },
        lod=LodSettings(high_dist=6.0, archetype_lod_dist=60.0, hd_texture_dist=3.0, med_detail=0.35),
        description="12in record, glossy black vinyl with grooves; centre label texture nayzeee_vinyl_label "
                    "is runtime-replaceable.",
        meta={
            "radius": RADIUS, "thickness": THICK, "label_radius": LABEL_R, "spindle_hole_radius": HOLE_R,
            "groove_lead_in_radius": VINYL_LEAD_IN, "groove_run_out_radius": VINYL_RUN_OUT,
            "label_texture": "nayzeee_vinyl_label",
            "console_attach_offset": [0.300, 0.000, 0.811],
            "spin_axis": "+Z", "spin_deg_per_s_33rpm": 200.0,
        },
    )
