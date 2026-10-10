"""
Renders the props with Cycles: inventory images (transparent PNG) and preview shots.

    python render_images.py <build dir> <out dir> [size] [samples] [only,names]

Uses weedlab_props.blend from build_props.py. Every Sollumz material is swapped for a
Principled BSDF fed by the same diffuse / normal / spec textures, so the renders show
what the game shows (plus nicer light).
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
BUILD = os.path.abspath(args[0])
OUT = os.path.abspath(args[1])
SIZE = int(args[2]) if len(args) > 2 else 512
SAMPLES = int(args[3]) if len(args) > 3 else 96
ONLY = set(args[4].split(",")) if len(args) > 4 and args[4] else None
os.makedirs(OUT, exist_ok=True)

bpy.ops.preferences.addon_enable(module="sollumz")
bpy.ops.wm.open_mainfile(filepath=os.path.join(BUILD, "weedlab_props.blend"))
PNG = os.path.join(BUILD, "png")

METAL = ("steel", "chrome", "galv", "reflector", "alu", "brass")


def tex_node(nt, name, non_color=False):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(PNG, name + ".png"), check_existing=True)
    if non_color:
        n.image.colorspace_settings.name = "Non-Color"
    return n


def principled_for(mat):
    nodes = mat.node_tree.nodes
    names = {}
    for s in ("DiffuseSampler", "BumpSampler", "SpecSampler"):
        nd = nodes.get(s)
        if nd is not None and nd.image is not None:
            names[s] = os.path.splitext(os.path.basename(nd.image.filepath))[0]
    shader = mat.shader_properties.filename
    key = mat.name.replace("nzw_", "").split(".")[0]
    new = bpy.data.materials.new(mat.name + "_render")
    new.use_nodes = True
    nt = new.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    out = nt.nodes["Material Output"]
    d = tex_node(nt, names["DiffuseSampler"])
    if "emissive" in shader:
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(d.outputs["Color"], em.inputs["Color"])
        em.inputs["Strength"].default_value = 6.0 if key != "halogen" else 10.0
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        return new
    nt.links.new(d.outputs["Color"], bsdf.inputs["Base Color"])
    if "BumpSampler" in names:
        n = tex_node(nt, names["BumpSampler"], True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 1.2
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if "SpecSampler" in names:
        s = tex_node(nt, names["SpecSampler"], True)
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "MULTIPLY_ADD"
        inv.inputs[1].default_value = -0.75
        inv.inputs[2].default_value = 0.92
        nt.links.new(s.outputs["Color"], inv.inputs[0])
        nt.links.new(inv.outputs[0], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = 0.35
    if key in METAL:
        bsdf.inputs["Metallic"].default_value = 1.0 if key != "galv" else 0.8
    if key in ("glass", "bag", "cling"):
        bsdf.inputs["Roughness"].default_value = 0.04
        bsdf.inputs["IOR"].default_value = 1.45
        bsdf.inputs["Transmission Weight"].default_value = 1.0
        bsdf.inputs["Base Color"].default_value = (0.92, 0.97, 0.97, 1) if key == "glass" else (0.97, 0.97, 0.97, 1)
        nt.links.remove(bsdf.inputs["Base Color"].links[0])
        if key != "glass":
            bsdf.inputs["Roughness"].default_value = 0.12
            bsdf.inputs["Thin Film Thickness"].default_value = 0.0
    if key.startswith("bud") or key in ("leaf", "compressed"):
        bsdf.inputs["Subsurface Weight"].default_value = 0.15
        bsdf.inputs["Subsurface Radius"].default_value = (0.004, 0.006, 0.002)
    if key in ("fabric", "fabric_teal"):
        bsdf.inputs["Sheen Weight"].default_value = 0.4
    return new


swap = {}
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    if o.sollum_type != "sollumz_drawable_model":
        o.hide_render = True
        continue
    for slot in o.material_slots:
        m = slot.material
        if m and m.name not in swap:
            swap[m.name] = principled_for(m)
        if m:
            slot.material = swap[m.name]

roots = {o.name: o for o in bpy.data.objects if o.parent is None and o.sollum_type == "sollumz_drawable"}

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 8
scene.cycles.transmission_bounces = 8
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = SIZE
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"

world = bpy.data.worlds.new("studio")
scene.world = world
world.use_nodes = True
wn = world.node_tree
bg = wn.nodes["Background"]
grad = wn.nodes.new("ShaderNodeTexGradient")
coord = wn.nodes.new("ShaderNodeTexCoord")
mp = wn.nodes.new("ShaderNodeMapping")
mp.inputs["Rotation"].default_value = (0, math.radians(-90), 0)
ramp = wn.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].color = (0.05, 0.055, 0.06, 1)
ramp.color_ramp.elements[1].color = (0.75, 0.78, 0.8, 1)
wn.links.new(coord.outputs["Generated"], mp.inputs["Vector"])
wn.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
wn.links.new(grad.outputs["Fac"], ramp.inputs["Fac"])
wn.links.new(ramp.outputs["Color"], bg.inputs["Color"])
bg.inputs["Strength"].default_value = 0.6


def area(name, loc, rot, energy, size, color=(1, 1, 1)):
    l = bpy.data.lights.new(name, "AREA")
    l.energy = energy
    l.size = size
    l.color = color
    o = bpy.data.objects.new(name, l)
    o.location = loc
    o.rotation_euler = Euler(rot)
    scene.collection.objects.link(o)
    return o


LIGHTS = [
    area("key", (-2.2, -2.6, 3.0), (math.radians(50), 0, math.radians(-40)), 700, 2.5, (1.0, 0.97, 0.92)),
    area("fill", (2.8, -1.6, 1.2), (math.radians(75), 0, math.radians(60)), 250, 3.0, (0.85, 0.92, 1.0)),
    area("rim", (0.5, 3.0, 2.6), (math.radians(-55), 0, math.radians(170)), 500, 2.0, (0.8, 1.0, 0.98)),
]

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 85
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def model_of(root):
    return [c for c in root.children_recursive if c.type == "MESH" and c.sollum_type == "sollumz_drawable_model"]


def bbox(objs):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def show(names):
    for n, r in roots.items():
        vis = n in names
        r.hide_render = not vis
        for c in r.children_recursive:
            if c.type == "MESH" and c.sollum_type == "sollumz_drawable_model":
                c.hide_render = not vis


def frame(objs, yaw=-32.0, pitch=22.0, pad=1.12, target=None):
    lo, hi = bbox(objs)
    center = (lo + hi) / 2 if target is None else Vector(target)
    radius = (hi - lo).length / 2 * pad
    fov = 2 * math.atan(cam_data.sensor_width / 2 / cam_data.lens)
    dist = radius / math.sin(fov / 2)
    a, p = math.radians(yaw), math.radians(pitch)
    cam.location = center + Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p))) * dist
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    # scale the lights with the object so small and big props get the same look
    k = max(radius, 0.08)
    for l, base in zip(LIGHTS, ((-2.2, -2.6, 3.0), (2.8, -1.6, 1.2), (0.5, 3.0, 2.6))):
        l.location = center + Vector(base) * k
        l.data.size = 2.5 * k
        l.rotation_euler = (center - l.location).to_track_quat("-Z", "Y").to_euler()
    LIGHTS[0].data.energy = 700 * k * k
    LIGHTS[1].data.energy = 240 * k * k
    LIGHTS[2].data.energy = 520 * k * k


def shoot(path, names, **kw):
    if ONLY and not (set(names) & ONLY):
        return
    show(names)
    objs = [m for n in names for m in model_of(roots[n])]
    frame(objs, **kw)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)


def place(name, loc=(0, 0, 0), rot=(0, 0, 0)):
    r = roots[name]
    r.location = loc
    r.rotation_euler = Euler([math.radians(a) for a in rot])
    return r


# ── inventory images: one item per prop ──
ICONS = {
    "nzw_pot": "nzw_pot", "nzw_growtent": "nzw_growtent", "nzw_suspension_rack": "nzw_rack",
    "nzw_light_halogen": "nzw_light_halogen", "nzw_light_led": "nzw_light_led", "nzw_light_fullspec": "nzw_light_fullspec",
    "nzw_dryrack": "nzw_dryrack", "nzw_speedgrow": "nzw_speedgrow", "nzw_pgr": "nzw_pgr", "nzw_fertilizer": "nzw_fertilizer",
    "nzw_soilbag": "nzw_soil", "nzw_wateringcan": "nzw_wateringcan", "nzw_trimmers": "nzw_trimmers", "nzw_seedvial": "nzw_seed",
    "nzw_brick": "nzw_brick", "nzw_baggie": "nzw_baggie_empty", "nzw_jar": "nzw_jar_empty",
}
inside = bpy.data.objects.new("tent_led", bpy.data.lights.new("tent_led", "POINT"))
inside.data.energy = 0.0
inside.data.color = (1.0, 0.94, 0.86)
inside.data.shadow_soft_size = 0.2
inside.location = (0, 0, 1.2)
scene.collection.objects.link(inside)
for prop, item in ICONS.items():
    inside.data.energy = 60.0 if prop == "nzw_growtent" else 0.0
    place(prop)
    pitch = 55 if prop in ("nzw_trimmers", "nzw_brick") else 20
    shoot(os.path.join(OUT, item + ".png"), [prop], pitch=pitch)

# stations with their moving parts in place
place("nzw_packstation")
place("nzw_packstation_hatch", (0.5, 0.17, 0.92 + 0.166), (-70, 0, 0))
shoot(os.path.join(OUT, "nzw_packstation.png"), ["nzw_packstation", "nzw_packstation_hatch"])
place("nzw_packstation_hatch", (0.5, 0.17, 0.92 + 0.166), (0, 0, 0))

place("nzw_mixstation")
place("nzw_mixstation_bowl", (0.28, 0.0, 0.9 + 0.22))
shoot(os.path.join(OUT, "nzw_mixstation.png"), ["nzw_mixstation", "nzw_mixstation_bowl"])

place("nzw_brickpress")
place("nzw_brickpress_plate", (0, 0, 1.5))
place("nzw_brickpress_lever", (0.36, -0.05, 0.98), (-18, 0, 0))
shoot(os.path.join(OUT, "nzw_brickpress.png"), ["nzw_brickpress", "nzw_brickpress_plate", "nzw_brickpress_lever"])

# product: bud per strain colour, a sealed baggie with a bud, a jar with buds + lid
for color in ("green", "purple", "lime", "golden", "red"):
    place("nzw_bud_" + color)
    shoot(os.path.join(OUT, "nzw_bud_" + color + ".png"), ["nzw_bud_" + color], pitch=12)

for color in ("green", "purple", "lime", "golden", "red"):
    place("nzw_baggie_sealed")
    place("nzw_bud_" + color, (-0.024, 0.0, 0.032), (0, 90, 0))
    shoot(os.path.join(OUT, "nzw_baggie_" + color + ".png"), ["nzw_baggie_sealed", "nzw_bud_" + color], pitch=10, yaw=-20)
    place("nzw_jar")
    place("nzw_jar_lid", (0, 0, 0.104))
    place("nzw_bud_" + color, (0.0, 0.0, 0.006), (0, 0, 30))
    copies = []
    src = model_of(roots["nzw_bud_" + color])[0]
    for (x, y, z, rx, rz) in ((0.02, 0.012, 0.004, 70, 10), (-0.018, 0.014, 0.006, 80, 140), (0.004, -0.02, 0.008, 75, 260), (-0.006, 0.0, 0.04, 85, 200)):
        c = src.copy()
        c.parent = None
        c.location = (x, y, z)
        c.rotation_euler = Euler((math.radians(rx), 0, math.radians(rz)))
        scene.collection.objects.link(c)
        copies.append(c)
    shoot(os.path.join(OUT, "nzw_jar_" + color + ".png"), ["nzw_jar", "nzw_jar_lid", "nzw_bud_" + color], pitch=14)
    for c in copies:
        bpy.data.objects.remove(c)
    place("nzw_bud_" + color)
    place("nzw_jar_lid")
print("DONE")
