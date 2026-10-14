"""
nzprops - code-only GTA V prop pipeline (numpy + Pillow).

    mesh   primitives (box, lathe, cylinder, sweep, tube, extrude, plane, quad, pillow, ...) + Geo transforms
    paint  Mat (materials), noise, DecalCanvas (labels, brand mark), default screen images
    atlas  automatic chart packing + rasteriser + gutter filling
    bake   per-texel material / decal / AO / edge baking -> diffuse, normal, spec
    dds    DXT1/DXT5 writer with mips
    cwxml  CodeWalker XML (drawable with embedded textures + composite collision, ytyp)
    gltf   .glb preview export
    prop   registry (@prop / register), Builder, build_prop()
"""
from .mesh import (Chart, Geo, arc_points, axis_angle, bezier, box, capsule, catmull, chamfer_poly, circle,
                   cylinder, ellipse, euler, extrude, lathe, look_basis, normalize, offset_poly, path_frames, pillow,
                   plane, pocket, poly_cap, polyline_fillet, quad, rect_profile, resample, rot_x, rot_y, rot_z, rrect,
                   slab_with_holes, sphere, sweep, torus, triangulate, tube, vec)
from .paint import (AMBER, BLACK, INK2, MED_RED, ORANGE, RED, TEAL, TEAL_HI, TEAL_LO, WHITE, YELLOW, DecalCanvas,
                    Mat, draw_defib_ui, draw_monitor_ui, draw_pager_lcd, fbm3, font, noise3, rgb)
from .prop import FLAG_STATIC, REGISTRY, Builder, PropSpec, build_prop, prop, register

__all__ = [
    # mesh
    "Chart", "Geo", "arc_points", "axis_angle", "bezier", "box", "capsule", "catmull", "chamfer_poly", "circle",
    "cylinder", "ellipse", "euler", "extrude", "lathe", "look_basis", "normalize", "offset_poly", "path_frames",
    "pillow", "plane", "pocket", "poly_cap", "polyline_fillet", "quad", "rect_profile", "resample", "rot_x", "rot_y",
    "rot_z", "rrect", "slab_with_holes", "sphere", "sweep", "torus", "triangulate", "tube", "vec",
    # paint
    "AMBER", "BLACK", "INK2", "MED_RED", "ORANGE", "RED", "TEAL", "TEAL_HI", "TEAL_LO", "WHITE", "YELLOW",
    "DecalCanvas", "Mat", "draw_defib_ui", "draw_monitor_ui", "draw_pager_lcd", "fbm3", "font", "noise3", "rgb",
    # prop
    "FLAG_STATIC", "REGISTRY", "Builder", "PropSpec", "build_prop", "prop", "register",
]
