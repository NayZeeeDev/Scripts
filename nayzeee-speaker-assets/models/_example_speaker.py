"""Template / API tour (NOT exported: names starting with "_" are ignored by the registry).

Shows the common building blocks for the speaker models:
  rounded housing, front baffle with driver cut-outs (extrude + holes), perforated
  grille inserts, driver cones (lathe), knob with a printed scale (decal from the
  print atlas), LED, swept carry handle with rubber grips, raised 3D wordmark,
  rubber feet, collision shapes and gameplay anchors.

Render it with:  python3 tools/selftest.py   (builds + validates it in a temp folder)
"""
from lib import fonts
from lib import mesh as M
from lib import textures as tx
from lib.spec import Anchor, Box, Cylinder, LodSettings, ModelSpec

W, D, H = 0.30, 0.18, 0.42        # housing size (x, y, z); front = +Y


def driver(radius: float, depth: float):
    """Cone + surround + dust cap, facing +Z (rotate into place)."""
    cone = M.lathe([(radius * 0.92, 0.0), (radius * 0.30, -depth), (0.0, -depth)], 48,
                   material="matte_black_plastic")                  # concave cone, visible side faces +Z
    surround = M.torus(radius * 0.96, radius * 0.06, 48, 10, material="rubber").translate(0, 0, -radius * 0.02)
    cap = M.hemisphere(radius * 0.30, 32, 6, cap=False, material="satin_graphite").scale(1, 1, 0.5) \
        .translate(0, 0, -depth)
    return [cone, surround, cap]


def build(detail: float) -> ModelSpec:
    parts = []
    # housing ------------------------------------------------------------------
    parts.append(M.rounded_box((W, D, H), 0.025, 6, center=(0, 0, H / 2), material="satin_graphite"))
    # front baffle: plate with two driver holes, sits proud of the housing front
    holes = [M.circle_2d(0.085, 64, (0.0, 0.09)), M.circle_2d(0.045, 48, (0.0, -0.11))]
    baffle = M.extrude(M.rounded_rect_2d(W - 0.03, H - 0.03, 0.018), 0.008, holes=holes, bevel=0.002,
                       bevel_segments=2, material="matte_black_plastic")
    front = (0, D / 2, H / 2)                     # baffle origin on the housing front
    parts.append(baffle.orient("+y", front).uv_planar("+y"))
    # drivers + perforated grilles in the holes (design coords: x right, y up)
    for (cx, cy), r in (((0.0, 0.09), 0.085), ((0.0, -0.11), 0.045)):
        for p in driver(r * 0.95, r * 0.35):
            parts.append(p.translate(cx, cy, 0.002).orient("+y", front))
        grille = M.cylinder(r * 0.98, 0.002, 64, material="speaker_grille_metal").translate(cx, cy, 0.008)
        parts.append(grille.orient("+y", front).uv_planar("+y"))
    # top control: knob + printed scale decal + LED -----------------------------
    knob = M.cylinder(0.018, 0.016, 48, bevel=0.002, material="rubber_grip").translate(0.08, 0.0, H)
    cap = M.cylinder(0.0145, 0.002, 48, bevel=0.0008, material="brushed_aluminium_radial") \
        .translate(0.08, 0.0, H + 0.016).uv_radial(0.0145, center=(0.08, 0.0, 0))
    scale = M.plane(0.05, 0.05, center=(0.08, 0.0, H + 0.0004), facing="+z", rect=tx.atlas_rect("knob_scale"),
                    material="print_decal")
    led = M.cylinder(0.003, 0.0015, 16, material="led_teal").translate(-0.10, 0.04, H)
    parts += [knob, cap, scale, led]
    # carry handle: swept rounded-rect tube with rubber grip sleeve ----------------
    path = M.polyline_path([(-0.10, 0, H - 0.005), (-0.10, 0, H + 0.07), (0.10, 0, H + 0.07), (0.10, 0, H - 0.005)],
                           radius=0.025, segments=6)
    parts.append(M.sweep(M.rounded_rect_section(0.022, 0.016, 0.006), path, material="gunmetal"))
    grip = M.sweep(M.circle_section(0.0145, 20), [(-0.06, 0, H + 0.07), (0.06, 0, H + 0.07)], material="rubber_grip")
    parts.append(grip)
    # raised 3D wordmark under the woofer ---------------------------------------
    for outer, holes_ in fonts.text_polygons("nayzeee", 0.012, weight=600):
        t = M.extrude(outer, 0.0012, holes=holes_, bevel=0.0003, material="teal_plastic")
        parts.append(t.translate(0, -0.172, 0.008).orient("+y", front))
    # rubber feet
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(M.cylinder(0.012, 0.006, 24, bevel=0.002, material="rubber")
                         .translate(sx * (W / 2 - 0.03), sy * (D / 2 - 0.03), -0.004))

    return ModelSpec(
        name="_example_speaker",
        parts=parts,
        collision=[Box((0, 0, H / 2), (W, D, H)),
                   Cylinder((-0.10, 0, H + 0.07), (0.10, 0, H + 0.07), 0.012, "METAL_SOLID_SMALL")],
        anchors={"grip": Anchor((0, 0, H + 0.07), note="handle centre"),
                 "front": Anchor((0, D / 2, H / 2), note="front centre")},
        lod=LodSettings(high_dist=15, archetype_lod_dist=100),
        export=False,
        description="API tour / template model",
    )
