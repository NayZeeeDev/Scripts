"""
nzprops - code-only GTA V prop pipeline (numpy + Pillow), NAYZEEE Radio edition.

    mesh    primitives (box, lathe, cylinder, sweep, tube, extrude, plane, quad, pillow, well_plate, loft ...)
            + Geo transforms; charts carry a part id and an LOD flag
    paint   Mat (materials), noise, DecalCanvas (labels, glyphs, icons, barcodes, screws, seams)
    atlas   automatic chart packing + rasteriser + gutter filling
    bake    per-texel material / decal / AO / edge baking -> diffuse, normal, spec
    dds     DXT1/DXT5 writer with mips
    cwxml   CodeWalker XML (drawable with embedded textures, high + medium LOD, composite collision, ytyp)
    gltf    .glb preview export
    budget  memory estimate of a drawable without converting it (RSC7 page model)
    fsutil  atomic file writes (several builds may run at the same time)
    prop    registry (@prop / register), Builder (parts, anchors, LOD flags), build_prop()
"""
from .mesh import (Chart, Geo, arc_points, axis_angle, bezier, box, capsule, catmull, chamfer_fillet_rect, chamfer_poly,
                   circle, cylinder, ellipse, euler, extrude, fillet_poly, helix, lathe, loft, look_basis, normalize,
                   offset_poly, path_frames, pillow, plane, pocket, poly_cap, polyline_fillet, quad, rect_profile, resample,
                   rot_x, rot_y, rot_z, rr_lathe, rrect, slab_with_holes, sphere, subdivide_poly, sweep, torus, triangulate, tube, vec,
                   well_plate)
from .paint import (AMBER, BLACK, INK2, ORANGE, RED, TEAL, TEAL_HI, TEAL_LO, WHITE, YELLOW, DecalCanvas, Mat, fbm3, font,
                    has_glyph, noise3, rgb)
from .prop import FLAG_STATIC, REGISTRY, Builder, PropSpec, build_prop, prop, register

__all__ = [
    # mesh
    "Chart", "Geo", "arc_points", "axis_angle", "bezier", "box", "capsule", "catmull", "chamfer_fillet_rect", "chamfer_poly",
    "circle", "cylinder", "ellipse", "euler", "extrude", "fillet_poly", "helix", "lathe", "loft", "look_basis", "normalize",
    "offset_poly", "path_frames", "pillow", "plane", "pocket", "poly_cap", "polyline_fillet", "quad", "rect_profile",
    "resample", "rot_x", "rot_y", "rot_z", "rr_lathe", "rrect", "slab_with_holes", "sphere", "subdivide_poly", "sweep", "torus",
    "triangulate", "tube", "vec", "well_plate",
    # paint
    "AMBER", "BLACK", "INK2", "ORANGE", "RED", "TEAL", "TEAL_HI", "TEAL_LO", "WHITE", "YELLOW",
    "DecalCanvas", "Mat", "fbm3", "font", "has_glyph", "noise3", "rgb",
    # prop
    "FLAG_STATIC", "REGISTRY", "Builder", "PropSpec", "build_prop", "prop", "register",
]
