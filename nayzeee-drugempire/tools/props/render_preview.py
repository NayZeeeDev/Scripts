"""Preview renders of the props (Workbench, textured). python render_preview.py <out dir from build_props>"""
import math
import os
import sys

import bpy
from mathutils import Vector

OUT = os.path.abspath(sys.argv[-1])
bpy.ops.preferences.addon_enable(module="sollumz")
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, "nz_drugempire_props.blend"))
png = bpy.data.images.load(os.path.join(OUT, "nz_drugempire_atlas.png"))

# simple textured material for the preview (the game material stays in the .blend untouched)
prev = bpy.data.materials.new("preview")
prev.use_nodes = True
nt = prev.node_tree
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = png
tex.interpolation = "Closest"
nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])

roots = {o.name: o for o in bpy.data.objects if o.parent is None}
for o in bpy.data.objects:
    if o.type == "MESH" and o.data.materials and o.sollum_type == "sollumz_drawable_model":
        o.data.materials[0] = prev
    elif o.type == "MESH":
        o.hide_render = True

scene = bpy.context.scene
scene.render.engine = "CYCLES"          # CPU, works headless without a GPU
scene.cycles.device = "CPU"
scene.cycles.samples = 24
scene.render.resolution_x, scene.render.resolution_y = 800, 800
scene.world = scene.world or bpy.data.worlds.new("w")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.37, 0.4, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
scene.collection.objects.link(sun)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam


def shoot(show, target, dist, height, yaw, name):
    for n, o in roots.items():
        o.hide_render = n not in show
        for ch in o.children_recursive:
            if ch.sollum_type == "sollumz_drawable_model":
                ch.hide_render = n not in show
    t = Vector(target)
    a = math.radians(yaw)
    cam.location = t + Vector((math.sin(a) * dist, -math.cos(a) * dist, height))
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)


# grow tent
roots["nz_growtent"].location = (0, 0, 0)
shoot(["nz_growtent"], (0, 0, 0.95), 3.2, 0.6, -30, "preview_growtent.png")

# bench with the lid open, a bag on the table and a jar
bench = roots["nz_packbench"]
lid = roots["nz_packbench_lid"]
lid.location = (0.565, 0.375, 0.9)
lid.rotation_euler = (math.radians(-78), 0, 0)
roots["nz_zipbag"].location = (-0.12, -0.08, 0.9)
roots["nz_jar"].location = (-0.45, 0.02, 0.9)
roots["nz_jar_lid"].location = (-0.45, 0.02, 0.993)
shoot(["nz_packbench", "nz_packbench_lid", "nz_zipbag", "nz_jar", "nz_jar_lid"], (0.1, 0, 1.0), 3.0, 0.9, 25, "preview_packbench.png")
# close-up over the drawer like the in-game camera
shoot(["nz_packbench", "nz_packbench_lid", "nz_zipbag", "nz_jar", "nz_jar_lid"], (0.2, 0.0, 0.9), 1.0, 0.7, 0, "preview_packbench_cam.png")
print("RENDERED")
