"""
Inventory icons for the crafting materials, modelled from primitives and
rendered with the same lighting as the shoe icons.

    python material_icons.py <out_dir>        (needs the bpy module)
"""

import math
import os
import sys

import bpy  # noqa: I001  (bpy has to load before bmesh and mathutils)
import bmesh
from mathutils import Vector


def mat(name, rgb, rough=0.55, metal=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1)   # sRGB -> linear
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if coat and "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
    return m


def link(ob, m=None, smooth=True, bevel=0.0):
    bpy.context.scene.collection.objects.link(ob)
    if m:
        ob.data.materials.append(m)
    if smooth and hasattr(ob.data, "polygons"):
        for p in ob.data.polygons:
            p.use_smooth = True
    if bevel:
        mod = ob.modifiers.new("bev", "BEVEL")
        mod.width, mod.segments = bevel, 3
    return ob


def prim(op, m, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), bevel=0.0, smooth=True, **kw):
    getattr(bpy.ops.mesh, op)(location=loc, rotation=[math.radians(a) for a in rot], **kw)
    ob = bpy.context.active_object
    ob.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(m)
    if smooth:
        bpy.ops.object.shade_smooth()
    if bevel:
        mod = ob.modifiers.new("bev", "BEVEL")
        mod.width, mod.segments = bevel, 3
    return ob


def outline_prism(points, depth, m, z=0.0, bevel=0.004):
    """Extrude a closed 2D outline up by depth."""
    me = bpy.data.meshes.new("p")
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z)) for x, y in points]
    f = bm.faces.new(vs)
    ex = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in ex["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    ob = bpy.data.objects.new("p", me)
    return link(ob, m, smooth=False, bevel=bevel)


def sole_outline(length=0.28, n=48):
    """A left-foot sole: wide forefoot, narrow waist, round heel."""
    pts = []
    for i in range(n):
        t = i / n * 2 * math.pi
        x = math.cos(t) * length / 2
        y = math.sin(t)
        u = (x / (length / 2) + 1) / 2                    # 0 heel .. 1 toe
        w = 0.034 + 0.018 * math.sin(math.pi * min(1, u * 1.15)) - 0.012 * math.exp(-((u - 0.45) / 0.12) ** 2)
        pts.append((x, y * w + (0.006 if y > 0 else 0) * u))
    return pts


# --- the materials ---------------------------------------------------------------

def leather():
    brown = mat("leather", (0.32, 0.15, 0.06), 0.45, coat=0.2)
    prim("primitive_cylinder_add", brown, loc=(0, 0.02, 0.05), rot=(0, 90, 0), scale=(0.05, 0.05, 0.13), vertices=48, bevel=0.006)
    prim("primitive_cylinder_add", mat("core", (0.22, 0.1, 0.04), 0.6), loc=(0, 0.02, 0.05), rot=(0, 90, 0), scale=(0.018, 0.018, 0.1305), vertices=32)
    # the unrolled tail of the hide
    tail = [(-0.13, -0.09), (0.13, -0.09), (0.12, 0.0), (-0.12, 0.0)]
    outline_prism(tail, 0.006, brown)


def fabric():
    cols = [(0.85, 0.86, 0.88), (0.05, 0.55, 0.52), (0.12, 0.13, 0.15)]
    for i, c in enumerate(cols):
        prim("primitive_cube_add", mat(f"fab{i}", c, 0.85), loc=(0.004 * i, -0.003 * i, 0.012 + i * 0.022),
             rot=(0, 0, 6 * i - 6), scale=(0.11, 0.075, 0.01), bevel=0.008)


def sole():
    rubber = mat("rubber", (0.92, 0.92, 0.9), 0.5)
    gum = mat("gum", (0.55, 0.33, 0.16), 0.7)
    pts = sole_outline()
    outline_prism(pts, 0.01, gum, z=0.0, bevel=0.003)
    outline_prism(pts, 0.022, rubber, z=0.01, bevel=0.005)


def heel():
    black = mat("heelblack", (0.06, 0.06, 0.07), 0.25, coat=0.6)
    # side profile of a stiletto (Y forward, Z up): wide seat curving down to a thin tip
    prof = []
    for i in range(13):                                   # back edge, seat down to tip
        t = i / 12
        prof.append((-0.05 + 0.034 * t ** 0.6, 0.11 * (1 - t)))
    for i in range(13):                                   # front edge, tip back up to the seat
        t = i / 12
        prof.append((-0.008 + 0.022 * t ** 1.8, 0.11 * t))
    prof = [(y, z) for y, z in prof]
    ob = outline_prism(prof, 0.028, black, bevel=0.003)
    ob.rotation_euler = (math.radians(90), 0, math.radians(90))
    ob.location = (0.014, 0, 0.012)


def thread():
    wood = mat("wood", (0.62, 0.45, 0.27), 0.6)
    red = mat("thread", (0.75, 0.08, 0.1), 0.8)
    prim("primitive_cylinder_add", wood, loc=(0, 0, 0.006), scale=(0.045, 0.045, 0.006), vertices=48, bevel=0.002)
    prim("primitive_cylinder_add", red, loc=(0, 0, 0.05), scale=(0.037, 0.037, 0.038), vertices=48)
    prim("primitive_cylinder_add", wood, loc=(0, 0, 0.094), scale=(0.045, 0.045, 0.006), vertices=48, bevel=0.002)


def glue():
    white = mat("bottle", (0.92, 0.92, 0.9), 0.35)
    label = mat("label", (0.91, 0.55, 0.13), 0.5)
    cap = mat("cap", (0.05, 0.55, 0.52), 0.4)
    prim("primitive_cylinder_add", white, loc=(0, 0, 0.055), scale=(0.035, 0.035, 0.055), vertices=48, bevel=0.008)
    prim("primitive_cylinder_add", label, loc=(0, 0, 0.055), scale=(0.0355, 0.0355, 0.028), vertices=48)
    prim("primitive_cone_add", cap, loc=(0, 0, 0.135), scale=(0.02, 0.02, 0.025), vertices=32, radius1=1.0, radius2=0.15, depth=2.0)


def laces():
    white = mat("lace", (0.93, 0.93, 0.92), 0.85)
    aglet = mat("aglet", (0.08, 0.08, 0.09), 0.3)
    cu = bpy.data.curves.new("lace", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth, cu.bevel_resolution = 0.0035, 3
    sp = cu.splines.new("POLY")
    pts = []
    for i in range(160):
        t = i / 159 * 3 * 2 * math.pi
        r = 0.055 - 0.004 * math.sin(t * 0.5)
        pts.append((math.cos(t) * r, math.sin(t) * r * 0.8, 0.006 + 0.004 * math.sin(t * 2.3) + i * 0.00007))
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (*c, 1)
    ob = bpy.data.objects.new("lace", cu)
    link(ob, white, smooth=False)
    end = Vector(pts[-1])
    prim("primitive_cylinder_add", aglet, loc=end + Vector((0.012, 0.0, 0)), rot=(0, 90, 0), scale=(0.0045, 0.0045, 0.012), vertices=16)


def authtag():
    card = mat("card", (0.06, 0.06, 0.07), 0.4)
    teal = mat("teal", (0.03, 0.69, 0.64), 0.35)
    holo = mat("holo", (0.75, 0.78, 0.82), 0.12, metal=1.0)
    w, h, c = 0.06, 0.1, 0.012
    pts = [(-w, -h), (w, -h), (w, h - c), (w - c, h), (-w + c, h), (-w, h - c)]
    outline_prism(pts, 0.004, card, bevel=0.0015)
    prim("primitive_cube_add", teal, loc=(0, -0.055, 0.0045), scale=(0.045, 0.012, 0.0008))
    prim("primitive_cube_add", holo, loc=(0, 0.01, 0.0045), scale=(0.03, 0.03, 0.0008))
    prim("primitive_torus_add", holo, loc=(0, 0.082, 0.004), major_radius=0.008, minor_radius=0.0025)
    for o in list(bpy.context.scene.objects):
        if o.type in ("MESH", "CURVE"):
            o.rotation_euler = (math.radians(12), math.radians(-8), math.radians(-25))


def cleaning_kit():
    case = mat("case", (0.06, 0.06, 0.07), 0.45)
    teal = mat("kteal", (0.03, 0.69, 0.64), 0.35)
    white = mat("kwhite", (0.92, 0.92, 0.9), 0.35)
    bristle = mat("bristle", (0.95, 0.95, 0.92), 0.9)
    wood = mat("kwood", (0.62, 0.45, 0.27), 0.6)
    prim("primitive_cube_add", case, loc=(0, 0, 0.012), scale=(0.11, 0.07, 0.012), bevel=0.006)
    prim("primitive_cube_add", teal, loc=(0, -0.0705, 0.012), scale=(0.08, 0.0008, 0.006))
    # bottle
    prim("primitive_cylinder_add", white, loc=(-0.05, 0.01, 0.07), scale=(0.022, 0.022, 0.045), vertices=40, bevel=0.005)
    prim("primitive_cylinder_add", teal, loc=(-0.05, 0.01, 0.072), scale=(0.0225, 0.0225, 0.02), vertices=40)
    prim("primitive_cylinder_add", case, loc=(-0.05, 0.01, 0.122), scale=(0.01, 0.01, 0.01), vertices=24)
    # brush
    prim("primitive_cube_add", wood, loc=(0.04, 0.0, 0.034), rot=(0, 0, 20), scale=(0.055, 0.02, 0.008), bevel=0.004)
    prim("primitive_cube_add", bristle, loc=(0.04, 0.0, 0.05), rot=(0, 0, 20), scale=(0.05, 0.016, 0.009), bevel=0.002)


def burner():
    body = mat("pbody", (0.08, 0.08, 0.09), 0.35, coat=0.3)
    screen = mat("pscreen", (0.03, 0.55, 0.5), 0.15)
    keys = mat("pkeys", (0.25, 0.27, 0.29), 0.5)
    prim("primitive_cube_add", body, loc=(0, 0, 0.008), scale=(0.028, 0.055, 0.008), bevel=0.006)
    prim("primitive_cube_add", screen, loc=(0, 0.022, 0.0165), scale=(0.02, 0.017, 0.0008))
    for r in range(4):
        for c in range(3):
            prim("primitive_cube_add", keys, loc=(-0.012 + c * 0.012, -0.004 - r * 0.0105, 0.0165), scale=(0.0045, 0.0035, 0.0012), bevel=0.001)
    prim("primitive_cylinder_add", body, loc=(0.02, 0.05, 0.03), scale=(0.003, 0.003, 0.02), vertices=16)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH":
            o.rotation_euler = (math.radians(18), math.radians(-6), math.radians(-28))


ICONS = {
    "nz_leather": leather, "nz_fabric": fabric, "nz_sole": sole, "nz_heel": heel,
    "nz_thread": thread, "nz_glue": glue, "nz_laces": laces, "nz_authtag": authtag,
    "nz_cleaning_kit": cleaning_kit, "nz_burner": burner,
}


def frame_and_render(out, size=256):
    scene = bpy.context.scene
    bpy.context.view_layer.update()
    pts = []
    for o in scene.objects:
        if o.type in ("MESH", "CURVE"):
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre, radius = (lo + hi) / 2, (hi - lo).length / 2

    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    direction = Vector((0.55, -0.85, 0.62)).normalized()
    cam.location = centre + direction * radius * 3.0
    scene.collection.objects.link(cam)
    tgt = bpy.data.objects.new("tgt", None)
    tgt.location = centre
    scene.collection.objects.link(tgt)
    cam.constraints.new("TRACK_TO").target = tgt
    scene.camera = cam

    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy, key.data.size = 40 * (radius / 0.15) ** 2, 1.0 * radius / 0.15
    key.location = centre + Vector((0.6, -0.6, 1.0)) * radius / 0.15
    key.rotation_euler = (math.radians(35), 0, math.radians(40))
    scene.collection.objects.link(key)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.82, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)


def main():
    out_dir = sys.argv[-1]
    only = os.environ.get("ONLY", "").split(",") if os.environ.get("ONLY") else None
    os.makedirs(out_dir, exist_ok=True)
    for name, build in ICONS.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        build()
        frame_and_render(os.path.join(out_dir, name + ".png"))
        print("rendered", name)


main()
