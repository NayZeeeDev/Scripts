"""
Render prop meshes with Cycles (CPU) for previews and inventory icons.

    python render_blender.py scene.json

scene.json (or a list of these, rendered one after another):
{
  "out": "icon.png", "size": [256, 256], "transparent": true, "samples": 48,
  "camera": {"location": [x,y,z], "target": [x,y,z], "lens": 50},
  "objects": [{"npz": "mesh.npz", "texture": "tex.png",
               "location": [0,0,0], "rotation_deg": [0,0,0]}]
}

Meshes are .npz files with pos/nrm/uv/idx in GTA space (Z up, UVs top-down).
"""

import json
import math
import sys

import bpy
import numpy as np


def add_mesh(spec, i):
    d = np.load(spec["npz"])
    pos, nrm, uv, idx = d["pos"], d["nrm"], d["uv"], d["idx"].reshape(-1, 3)
    me = bpy.data.meshes.new(f"m{i}")
    me.from_pydata(pos.tolist(), [], idx.tolist())
    corner_vert = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", corner_vert)
    uvs = uv[corner_vert].astype(np.float32)
    uvs[:, 1] = 1.0 - uvs[:, 1]                  # GTA top-down -> Blender bottom-up
    me.uv_layers.new(name="uv").data.foreach_set("uv", uvs.ravel())
    me.normals_split_custom_set([tuple(n) for n in nrm[corner_vert]])
    me.validate()
    ob = bpy.data.objects.new(f"o{i}", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = spec.get("location", (0, 0, 0))
    ob.rotation_euler = [math.radians(a) for a in spec.get("rotation_deg", (0, 0, 0))]

    mat = bpy.data.materials.new(f"mat{i}")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.6)
    if spec.get("texture"):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(spec["texture"])
        tex.extension = "REPEAT"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    return ob


def main():
    spec = json.load(open(sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else sys.argv[1]))
    for scene_spec in (spec if isinstance(spec, list) else [spec]):   # a list renders in one Blender session
        render_one(scene_spec)


def render_one(scene_spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for i, spec in enumerate(scene_spec["objects"]):
        add_mesh(spec, i)

    cam_spec = scene_spec["camera"]
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = cam_spec.get("lens", 50)
    cam.location = cam_spec["location"]
    scene.collection.objects.link(cam)
    tgt = bpy.data.objects.new("tgt", None)
    tgt.location = cam_spec["target"]
    scene.collection.objects.link(tgt)
    con = cam.constraints.new("TRACK_TO")
    con.target = tgt
    scene.camera = cam

    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy, key.data.size = 40, 1.0
    key.location = (0.6, -0.6, 1.0)
    key.rotation_euler = (math.radians(35), 0, math.radians(40))
    scene.collection.objects.link(key)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.8, 0.8, 0.82, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = scene_spec.get("ambient", 0.9)
    scene.world = world

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = scene_spec.get("samples", 48)
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = scene_spec.get("transparent", False)
    scene.render.resolution_x, scene.render.resolution_y = scene_spec.get("size", (800, 600))
    scene.render.filepath = scene_spec["out"]
    bpy.ops.render.render(write_still=True)


main()
