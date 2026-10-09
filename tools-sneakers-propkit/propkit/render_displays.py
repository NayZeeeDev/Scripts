"""
Renders the display cases (displays.py) with Cycles: a preview of stacked cases with shoes inside, and the
three inventory icons.

    python render_displays.py <out_dir> <shoe.npz> <shoe.png> [<shoe2.npz> <shoe2.png>]
"""

import math
import os
import sys
import types

import bpy
import numpy as np

# displays.py imports PIL for its textures; rendering doesn't need it
sys.modules.setdefault("PIL", types.SimpleNamespace(Image=None))
sys.path.insert(0, os.path.dirname(__file__))
import displays  # noqa: E402


def glass_material(name, rough, tint, transmission=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = tint
    b.inputs["Roughness"].default_value = rough
    b.inputs["IOR"].default_value = 1.49
    b.inputs["Transmission Weight"].default_value = transmission
    return mat


def solid_material(name, colour, rough=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = colour
    b.inputs["Roughness"].default_value = rough
    return mat


MATS = {}


def mats():
    if not MATS:
        MATS["clear"] = glass_material("clear", 0.03, (0.94, 0.97, 1.0, 1))
        MATS["frost"] = glass_material("frost", 0.3, (0.97, 0.99, 1.0, 1), 0.35)
        MATS["tab"] = solid_material("tab", (0.04, 0.04, 0.05, 1), 0.4)
    return MATS


def add_parts(parts, location, rot_z=0.0, pivot=(0, 0, 0)):
    """parts: {"glass": Part, "tab": Part}; the glass faces are split clear / frosted by their alpha."""
    m = mats()
    obs = []
    for key, p in parts.items():
        me = bpy.data.meshes.new(key)
        faces = [tuple(p.idx[i:i + 3]) for i in range(0, len(p.idx), 3)]
        me.from_pydata([tuple(v) for v in p.pos], [], faces)
        if key == "glass":
            me.materials.append(m["clear"])
            me.materials.append(m["frost"])
            for fi, poly in enumerate(me.polygons):
                poly.material_index = 1 if p.col[faces[fi][0]][3] > 100 else 0
        else:
            me.materials.append(m["tab"])
        me.validate()
        ob = bpy.data.objects.new(key, me)
        bpy.context.scene.collection.objects.link(ob)
        obs.append(ob)
    # group under an empty so the door can turn round its hinge
    root = bpy.data.objects.new("root", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = location
    root.rotation_euler = (0, 0, rot_z)
    for ob in obs:
        ob.parent = root
        ob.location = pivot
    return root


def add_shoe(npz, png, location, rot_z=0.0):
    d = np.load(npz)
    pos, uv, idx = d["pos"], d["uv"], d["idx"].reshape(-1, 3)
    me = bpy.data.meshes.new("shoe")
    me.from_pydata(pos.tolist(), [], idx.tolist())
    cv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", cv)
    uvs = uv[cv].astype(np.float32)
    uvs[:, 1] = 1.0 - uvs[:, 1]
    me.uv_layers.new(name="uv").data.foreach_set("uv", uvs.ravel())
    mat = bpy.data.materials.new("shoe")
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(png)
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    me.materials.append(mat)
    me.validate()
    ob = bpy.data.objects.new("shoe", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = location
    ob.rotation_euler = (0, 0, rot_z)
    return ob


def case_at(name, location, rot_z=0.0, door_deg=0.0):
    w, d, h = displays.SIZES[name]
    add_parts(displays.case(w, d, h), location, rot_z)
    # the door's hinge sits at (-w/2, d/2) in the case
    c, s = math.cos(rot_z), math.sin(rot_z)
    hx, hy = -w / 2, d / 2
    hinge = (location[0] + hx * c - hy * s, location[1] + hx * s + hy * c, location[2])
    add_parts(displays.door(w, d, h), hinge, rot_z + math.radians(door_deg))
    return h


def scene(size, transparent, out, cam_loc, cam_tgt, lens=50, samples=96, floor=False):
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = lens
    cam.location = cam_loc
    sc.collection.objects.link(cam)
    tgt = bpy.data.objects.new("tgt", None)
    tgt.location = cam_tgt
    sc.collection.objects.link(tgt)
    con = cam.constraints.new("TRACK_TO")
    con.target = tgt
    sc.camera = cam
    for loc, energy in (((0.9, 1.0, 1.6), 90), ((-1.2, 0.4, 1.0), 35), ((0.0, -1.4, 1.2), 30)):
        l = bpy.data.objects.new("l", bpy.data.lights.new("l", "AREA"))
        l.data.energy, l.data.size = energy, 1.2
        l.location = loc
        c = l.constraints.new("TRACK_TO")
        c.target = tgt
        sc.collection.objects.link(l)
    if floor:
        bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
        bpy.context.active_object.data.materials.append(solid_material("floor", (0.55, 0.66, 0.85, 1), 0.35))
        bpy.ops.mesh.primitive_plane_add(size=6, location=(0, -1.0, 0), rotation=(math.radians(90), 0, 0))
        bpy.context.active_object.data.materials.append(solid_material("wall", (0.45, 0.58, 0.82, 1), 0.6))
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.85, 0.88, 0.95, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sc.world = w
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = transparent
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def main():
    out, shoes = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    pairs = [(shoes[i], shoes[i + 1]) for i in range(0, len(shoes) - 1, 2)]

    # preview: two shoe cases stacked (top one open, a pair in each) and a boot case beside them
    reset()
    flo = displays.T + 0.001
    h = case_at("nzs_display", (0, 0, 0))
    if pairs:
        add_shoe(*pairs[0], (0, 0, flo))
    case_at("nzs_display", (0, 0, h), door_deg=100)
    if len(pairs) > 1:
        add_shoe(*pairs[1], (0, 0, h + flo))
    case_at("nzs_display_heel", (0.43, -0.02, 0), rot_z=math.radians(8), door_deg=35)
    scene((1100, 800), False, os.path.join(out, "display_preview.png"), (0.75, 1.3, 0.7), (0.15, 0, 0.22), lens=42, floor=True)

    # icons: each case with a pair inside (the 3rd, 4th and 5th shoe given), door shut
    icon_shoes = pairs[2:5]
    for i, name in enumerate(displays.SIZES):
        reset()
        w, d, hh = displays.SIZES[name]
        case_at(name, (0, 0, 0))
        if i < len(icon_shoes):
            add_shoe(*icon_shoes[i], (0, 0, flo))
        dist = max(w, d, hh) * 2.25
        scene((256, 256), True, os.path.join(out, name.replace("nzs_", "nz_") + ".png"),
              (dist * 0.62, dist * 0.78, dist * 0.55), (0, 0, hh * 0.45), lens=50, samples=64)


main()
