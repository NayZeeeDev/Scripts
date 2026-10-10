"""
Preview scenes for the README (Cycles): the packaging station mid-batch, a grow room,
the processing gear and the product line-up.

    python render_scenes.py <build dir> <out dir> [width] [samples]
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

args = sys.argv[1:]
SCN_BUILD, SCN_OUT = os.path.abspath(args[0]), os.path.abspath(args[1])
SCN_WIDTH = int(args[2]) if len(args) > 2 else 1280
SCN_SAMPLES = int(args[3]) if len(args) > 3 else 128
os.makedirs(SCN_OUT, exist_ok=True)

# reuse the material swap + helpers from the icon renderer
sys.argv = [sys.argv[0], SCN_BUILD, os.path.join(SCN_BUILD, "_unused"), "64", "1", "__none__"]
HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "render_images.py")).read()
src = src.split("# ── inventory images")[0]
exec(compile(src, "render_images.py", "exec"))

scene = bpy.context.scene
scene.render.film_transparent = False
scene.render.resolution_x = SCN_WIDTH
scene.render.resolution_y = int(SCN_WIDTH * 9 / 16)
scene.cycles.samples = SCN_SAMPLES
scene.render.image_settings.file_format = "JPEG"
scene.render.image_settings.quality = 90
cam_data.lens = 35
for l in LIGHTS:
    l.hide_render = True

# room: concrete floor + back walls
floor_mat = bpy.data.materials.new("concrete")
floor_mat.use_nodes = True
nt = floor_mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
noise = nt.nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 18.0
noise.inputs["Detail"].default_value = 12.0
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].color = (0.16, 0.16, 0.15, 1)
ramp.color_ramp.elements[1].color = (0.32, 0.31, 0.29, 1)
nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.8
wall_mat = bpy.data.materials.new("wall")
wall_mat.use_nodes = True
wall_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.09, 0.1, 0.1, 1)
wall_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9


def plane(name, size, loc, rot, mat):
    bpy.ops.mesh.primitive_plane_add(size=size, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


ROOM = [
    plane("floor", 14, (0, 0, 0), (0, 0, 0), floor_mat),
    plane("wall_back", 14, (0, 2.2, 3), (math.radians(90), 0, 0), wall_mat),
    plane("wall_left", 14, (-3.2, 0, 3), (math.radians(90), 0, math.radians(90)), wall_mat),
]
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25


def light(name, loc, energy, size=1.0, color=(1, 1, 1), kind="AREA", rot=(0, 0, 0)):
    l = bpy.data.lights.new(name, kind)
    l.energy = energy
    l.color = color
    if kind == "AREA":
        l.size = size
    else:
        l.shadow_soft_size = size
    o = bpy.data.objects.new(name, l)
    o.location = loc
    o.rotation_euler = rot
    scene.collection.objects.link(o)
    return o


TEMP = []


def copy(name, loc=(0, 0, 0), rot=(0, 0, 0)):
    """an extra instance of a prop (for rows of baggies, buds ...)"""
    out = []
    for m in model_of(roots[name]):
        c = m.copy()
        c.parent = None
        c.location = loc
        c.rotation_euler = Euler([math.radians(a) for a in rot])
        c.hide_render = False
        scene.collection.objects.link(c)
        out.append(c)
        TEMP.append(c)
    return out


def clear():
    for o in TEMP:
        bpy.data.objects.remove(o)
    TEMP.clear()
    for o in list(scene.collection.objects):
        if o.type == "LIGHT" and o.name.startswith("s_"):
            bpy.data.objects.remove(o)


def shot(path, names, cam_loc, target, lens=35):
    show(names)
    cam_data.lens = lens
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


# ── 1. packaging station mid-batch ──
place("nzw_packstation")
place("nzw_packstation_hatch", (0.5, 0.17, 0.92 + 0.166), (-75, 0, 0))
for i in range(12):
    col, row = i % 6, i // 6
    copy("nzw_bud_green", (-0.52 + (col - 2.5) * 0.066, -0.02 + (row - 1.5) * 0.08, 0.94), (90, 0, i * 47))
for i in range(5):
    copy("nzw_baggie", (-0.25 + (i + 1) * 0.08, 0.11, 0.925))
place("nzw_baggie_sealed", (-0.04, -0.12, 0.925))
copy("nzw_bud_green", (-0.04, -0.12, 0.957), (0, 90, 0))
light("s_bar", (0, 0.27, 1.65), 60, 1.2, (1, 0.96, 0.9), rot=(0, 0, 0))
light("s_key", (-1.6, -1.8, 2.6), 380, 2.0, (1, 0.97, 0.92), rot=(math.radians(45), 0, math.radians(-40)))
light("s_fill", (1.8, -1.2, 1.6), 120, 2.0, (0.85, 0.92, 1), rot=(math.radians(70), 0, math.radians(55)))
shot(os.path.join(SCN_OUT, "preview_packstation.jpg"), ["nzw_packstation", "nzw_packstation_hatch", "nzw_baggie_sealed"], (-0.15, -1.25, 1.75), (0.0, 0.0, 0.98), 32)
clear()
place("nzw_baggie_sealed")
place("nzw_packstation_hatch", (0.5, 0.17, 0.92 + 0.166))

# ── 2. grow room: rack + LED over pots, a tent, the drying rack ──
place("nzw_suspension_rack", (-0.7, 0.6, 0))
place("nzw_light_led", (-0.7, 0.6, 1.86))
for x in (-1.15, -0.25):
    copy("nzw_pot", (x, 0.6, 0))
    copy("nzw_soil", (x, 0.6, 0.26))
place("nzw_growtent", (1.0, 0.95, 0), (0, 0, -18))
copy("nzw_soil", (1.0, 0.95, 0.23))
place("nzw_dryrack", (2.35, 0.8, 0), (0, 0, -35))
light("s_led", (-0.7, 0.6, 1.4), 220, 0.6, (0.78, 0.3, 1.0), kind="AREA", rot=(0, 0, 0))
light("s_tent", (1.0, 0.95, 1.35), 40, 0.25, (1, 0.93, 0.85), kind="POINT")
light("s_key", (0.5, -3.2, 3.0), 650, 4.0, (1, 0.97, 0.92), rot=(math.radians(55), 0, 0))
shot(os.path.join(SCN_OUT, "preview_growroom.jpg"), ["nzw_suspension_rack", "nzw_light_led", "nzw_growtent", "nzw_dryrack"], (0.55, -4.1, 1.75), (0.6, 0.6, 1.0), 30)
clear()

# ── 3. processing: mixing station + brick press ──
place("nzw_mixstation", (-0.75, 0.3, 0), (0, 0, 8))
place("nzw_mixstation_bowl", (-0.75 + 0.28, 0.3 + 0.04, 1.12), (0, 0, 8))
copy("nzw_bud_lime", (-1.15, 0.25, 0.905), (90, 0, 20))
place("nzw_brickpress", (0.75, 0.4, 0), (0, 0, -12))
place("nzw_brickpress_plate", (0.75, 0.4, 1.5), (0, 0, -12))
place("nzw_brickpress_lever", (0.75 + 0.35, 0.4 + 0.02, 0.98), (-15, 0, -12))
place("nzw_brick", (0.75, 0.4, 0.842), (0, 0, -12))
light("s_key", (-1.5, -2.4, 2.8), 520, 2.5, (1, 0.97, 0.92), rot=(math.radians(50), 0, math.radians(-30)))
light("s_fill", (2.2, -1.6, 1.6), 160, 2.5, (0.85, 0.92, 1), rot=(math.radians(70), 0, math.radians(55)))
shot(os.path.join(SCN_OUT, "preview_processing.jpg"), ["nzw_mixstation", "nzw_mixstation_bowl", "nzw_brickpress", "nzw_brickpress_plate", "nzw_brickpress_lever", "nzw_brick"], (0.0, -3.0, 1.7), (0.0, 0.3, 0.95), 35)
clear()

# ── 4. the product line-up ──
for o in ROOM[1:]:
    o.hide_render = True
x = -0.33
for color in ("green", "lime", "purple", "golden"):
    copy("nzw_bud_" + color, (x, 0, 0.004))
    x += 0.07
place("nzw_jar", (0.0, 0.03, 0))
place("nzw_jar_lid", (0.0, 0.03, 0.104))
for i, (dx, dy, dz, rx) in enumerate(((0.012, 0.0, 0.004, 70), (-0.014, 0.01, 0.006, 80), (0.0, -0.012, 0.03, 75))):
    copy("nzw_bud_purple", (dx, 0.03 + dy, dz), (rx, 0, i * 110))
place("nzw_baggie_sealed", (0.12, 0.0, 0), (0, 0, -10))
copy("nzw_bud_green", (0.12 - 0.024, 0.0, 0.032), (0, 90, -10))
place("nzw_brick", (0.32, 0.03, 0), (0, 0, 20))
light("s_key", (-0.4, -0.7, 0.8), 90, 0.6, (1, 0.97, 0.92), rot=(math.radians(50), 0, math.radians(-30)))
light("s_fill", (0.6, -0.5, 0.4), 30, 0.6, (0.85, 0.92, 1), rot=(math.radians(70), 0, math.radians(55)))
light("s_rim", (0.0, 0.6, 0.5), 50, 0.6, (0.8, 1, 0.98), rot=(math.radians(-55), 0, math.radians(180)))
shot(os.path.join(SCN_OUT, "preview_products.jpg"), ["nzw_jar", "nzw_jar_lid", "nzw_baggie_sealed", "nzw_brick"], (0.05, -1.05, 0.42), (0.05, 0.02, 0.05), 42)
print("DONE")
