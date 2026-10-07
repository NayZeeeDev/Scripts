"""
Sets the sneaker box up in Blender, ready for Sollumz export.

  * imports models/nz_shoebox.obj + models/nz_shoebox_lid.obj
  * parents the lid to the base on the hinge line
  * keyframes an open -> hold -> close loop on the lid (frames 1-96)
  * optional: renders closed/open stills to check the result

Run it from Blender's Scripting tab (open the file, press Run), or headless:

    blender --background --python blender_setup.py
    blender --background --python blender_setup.py -- --render renders/ --save shoebox.blend
    blender --background --python blender_setup.py -- --frames frames/   (whole loop as PNGs)

Run generate_model.py first so the OBJs and texture exist.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(bpy.context.space_data.text.filepath)) \
    if getattr(bpy.context, "space_data", None) and getattr(bpy.context.space_data, "text", None) \
    else os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(HERE, "models")

# Must match generate_model.py
HINGE = (0.0, -0.105, 0.115)

OPEN_ANGLE = 105.0   # degrees, how far the lid swings back
FPS = 30

# (frame, lid angle in degrees) - small overshoot on open, little bounce on close
KEYS = [
    (1, 0.0),
    (16, OPEN_ANGLE + 6),
    (22, OPEN_ANGLE),
    (54, OPEN_ANGLE),
    (70, 0.0),
    (74, 3.0),
    (78, 0.0),
    (96, 0.0),
]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"render": None, "frames": None, "save": None}
    for key in opts:
        flag = f"--{key}"
        if flag in argv and argv.index(flag) + 1 < len(argv):
            opts[key] = argv[argv.index(flag) + 1]
    return opts


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.actions):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def import_part(name):
    path = os.path.join(MODEL_DIR, f"{name}.obj")
    if not os.path.exists(path):
        raise FileNotFoundError(f"{path} missing - run generate_model.py first")
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z")
    obj = bpy.context.selected_objects[0]
    obj.name = name
    obj.data.name = name
    return obj


def tidy_material(obj):
    # Cardboard: rough, no shine
    for slot in obj.material_slots:
        mat = slot.material
        if mat and mat.use_nodes:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Roughness"].default_value = 0.85
                bsdf.inputs["Specular IOR Level"].default_value = 0.2


def animate_lid(lid):
    lid.rotation_mode = "XYZ"
    for frame, angle in KEYS:
        lid.rotation_euler = (math.radians(angle), 0.0, 0.0)
        lid.keyframe_insert(data_path="rotation_euler", index=0, frame=frame)

    action = lid.animation_data.action
    action.name = "nz_shoebox_lid_openclose"

    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = KEYS[0][0]
    scene.frame_end = KEYS[-1][0]
    scene.frame_set(1)


def build():
    clear_scene()
    base = import_part("nz_shoebox")
    lid = import_part("nz_shoebox_lid")
    for obj in (base, lid):
        tidy_material(obj)

    lid.parent = base
    lid.location = HINGE
    animate_lid(lid)
    return base, lid


def setup_render_scene():
    scene = bpy.context.scene
    if scene.camera:
        return scene

    bpy.ops.object.camera_add(location=(0.72, 0.92, 0.62))
    cam = bpy.context.object
    cam.data.lens = 50
    target = bpy.data.objects.new("cam_target", None)
    target.location = (0, -0.02, 0.13)
    scene.collection.objects.link(target)
    track = cam.constraints.new("TRACK_TO")
    track.target = target
    scene.camera = cam

    bpy.ops.object.light_add(type="AREA", location=(0.6, 0.4, 1.0))
    key = bpy.context.object
    key.data.energy = 25
    key.data.size = 0.8
    key.rotation_euler = (math.radians(30), math.radians(25), 0)
    bpy.ops.mesh.primitive_plane_add(size=4)

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.82, 0.84, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    return scene


def render_checks(out_dir):
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    scene = setup_render_scene()
    for frame, label in ((1, "closed"), (22, "open"), (62, "closing")):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, f"shoebox_{label}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def render_frames(out_dir, step=2):
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    scene = setup_render_scene()
    scene.cycles.samples = 12
    scene.render.resolution_x = 480
    scene.render.resolution_y = 320
    for frame in range(scene.frame_start, scene.frame_end + 1, step):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(out_dir, f"frame_{frame:03d}.png")
        bpy.ops.render.render(write_still=True)
    print("rendered animation frames to", out_dir)


def main():
    opts = parse_args()
    base, lid = build()
    print(f"built {base.name} + {lid.name}, animation frames "
          f"{bpy.context.scene.frame_start}-{bpy.context.scene.frame_end} @ {FPS}fps")
    if opts["render"]:
        render_checks(opts["render"])
    if opts["frames"]:
        render_frames(opts["frames"])
    if opts["save"]:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opts["save"]))
        print("saved", opts["save"])


main()
