"""
Builds the custom props for nayzeee-drugempire with Blender + Sollumz (headless).

    nz_growtent        grow tent with an open, rolled-up door, light panel inside
    nz_packbench       packaging bench (shelf + light bar), drawer under the right end
    nz_packbench_lid   the lid over that drawer (origin on the hinge, rotate on X to open)
    nz_zipbag          zip-lock baggie lying flat
    nz_jar             glass jar with product
    nz_jar_lid         jar lid

Run:  BLENDER_USER_SCRIPTS=<dir with addons/sollumz> python build_props.py <out_dir>
(python = a venv with `bpy` and `szio` installed). Output is CodeWalker XML; run
tools/props/xml2bin to turn it into .ydr files for stream/.

Units are metres, Z up, the working side of every prop faces -Y (towards the player).
"""
import math
import os
import struct
import sys

import bpy  # noqa: I001  (bpy first: it sets up bmesh / mathutils)
import bmesh
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFont

OUT = os.path.abspath(sys.argv[-1])
os.makedirs(OUT, exist_ok=True)

bpy.ops.preferences.addon_enable(module="sollumz")
from sollumz.sollumz_properties import SollumType  # noqa: E402
from sollumz.tools.blenderhelper import create_blender_object, create_empty_object  # noqa: E402
from sollumz.tools.boundhelper import apply_flag_preset  # noqa: E402
from sollumz.tools.drawablehelper import convert_obj_to_model  # noqa: E402
from sollumz.tools.meshhelper import create_box, mesh_add_missing_color_attrs, mesh_add_missing_uv_maps  # noqa: E402
from sollumz.ybn.collision_materials import create_collision_material_from_index  # noqa: E402
from sollumz.ydr.shader_materials import create_shader  # noqa: E402

# ─────────────────────────── texture atlas ───────────────────────────
# 256x256, 8x8 grid of 32px swatches; rows 6-7 are the logo strip
SW = {
    "black": (18, 19, 20), "fabric": (26, 28, 27), "green": (58, 160, 64), "mylar": (196, 200, 204),
    "mylar_dk": (150, 154, 158), "white": (250, 250, 245), "steel": (112, 116, 120), "steel_dk": (64, 67, 70),
    "steel_lt": (150, 154, 158), "red": (220, 40, 40), "drawer": (36, 38, 40), "glass": (190, 214, 222),
    "bag": (226, 232, 236), "zip": (40, 110, 220), "weed": (78, 120, 52), "lid": (22, 22, 24), "strap": (40, 40, 42),
    "pot": (30, 30, 32), "floor": (120, 124, 128),
}
SLOT = {name: i for i, name in enumerate(SW)}
LOGO = (0, 192, 256, 256)  # x0, y0, x1, y1 in pixels


def build_atlas():
    img = Image.new("RGB", (256, 256), (0, 0, 0))
    d = ImageDraw.Draw(img)
    for name, i in SLOT.items():
        x, y = (i % 8) * 32, (i // 8) * 32
        d.rectangle([x, y, x + 31, y + 31], fill=SW[name])
    # logo strip: black fabric with a green rule and the brand
    d.rectangle(LOGO, fill=SW["fabric"])
    d.rectangle([0, 252, 256, 256], fill=SW["green"])
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
    except OSError:
        font = ImageFont.load_default()
    text = "NZ GROW"
    w = d.textlength(text, font=font)
    d.text(((256 - w) / 2, 205), text, fill=(240, 240, 240), font=font)
    return img


def rgb565(c):
    r, g, b = c
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def bc1_block(px):
    """px: 16 (r,g,b). Simple min/max endpoint BC1 encoder (exact for flat swatches)."""
    lum = [p[0] * 3 + p[1] * 6 + p[2] for p in px]
    c0, c1 = px[lum.index(max(lum))], px[lum.index(min(lum))]
    a, b = rgb565(c0), rgb565(c1)
    if a < b:
        a, b, c0, c1 = b, a, c1, c0
    if a == b:
        return struct.pack("<HHI", a, b, 0)
    pal = [c0, c1, tuple((2 * c0[i] + c1[i]) // 3 for i in range(3)), tuple((c0[i] + 2 * c1[i]) // 3 for i in range(3))]
    idx = 0
    for k, p in enumerate(px):
        best = min(range(4), key=lambda j: sum((p[i] - pal[j][i]) ** 2 for i in range(3)))
        idx |= best << (2 * k)
    return struct.pack("<HHI", a, b, idx)


def encode_bc1(img):
    w, h = img.size
    pix = img.load()
    out = bytearray()
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            block = [pix[min(bx + x, w - 1), min(by + y, h - 1)] for y in range(4) for x in range(4)]
            out += bc1_block(block)
    return bytes(out)


def make_dds(img):
    mips, cur = [], img
    while True:
        mips.append(encode_bc1(cur))
        if cur.size[0] <= 4:
            break
        cur = cur.resize((cur.size[0] // 2, cur.size[1] // 2), Image.BOX)
    w, h = img.size
    header = struct.pack(
        "<4sIIIIIII44sII4sIIIIIIIIII",
        b"DDS ", 124, 0x1 | 0x2 | 0x4 | 0x1000 | 0x80000 | 0x20000, h, w, max(1, (w // 4)) * max(1, (h // 4)) * 8, 0, len(mips),
        b"\0" * 44,
        32, 0x4, b"DXT1", 0, 0, 0, 0, 0,          # pixel format: size, FOURCC flag, fourcc, bitcount, masks
        0x1000 | 0x8 | 0x400000, 0, 0, 0, 0,      # caps (texture | complex | mipmap), caps2-4, reserved
    )
    assert len(header) == 128
    return header + b"".join(mips)


def packed_image(name, dds):
    img = bpy.data.images.new(name=name, width=1, height=1)
    img.source = "FILE"
    img.filepath = f"//{name}.dds"
    img.pack(data=dds, data_len=len(dds))
    return img


_atlas_img = build_atlas()
_atlas_img.save(os.path.join(OUT, "nz_drugempire_atlas.png"))
ATLAS = packed_image("nz_drugempire_atlas", make_dds(_atlas_img))


def swatch_uv(name):
    i = SLOT[name]
    cx, cy = (i % 8) * 32 + 16, (i // 8) * 32 + 16
    return [((cx + dx) / 256.0, 1.0 - (cy + dy) / 256.0) for dx, dy in ((-6, 6), (6, 6), (6, -6), (-6, -6))]


def logo_uv():
    x0, y0, x1, y1 = LOGO
    return [(x0 / 256, 1 - y1 / 256), (x1 / 256, 1 - y1 / 256), (x1 / 256, 1 - y0 / 256), (x0 / 256, 1 - y0 / 256)]


# ─────────────────────────── geometry ───────────────────────────
class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def _paint(self, face, uvs):
        for loop, uv in zip(face.loops, uvs if len(uvs) == len(face.loops) else [uvs[k % len(uvs)] for k in range(len(face.loops))]):
            loop[self.uv].uv = uv

    def box(self, mn, mx, sw="steel", faces=None):
        """faces: optional {'+x'|'-x'|'+y'|'-y'|'+z'|'-z': swatch or 'logo'}"""
        (x0, y0, z0), (x1, y1, z1) = mn, mx
        v = [self.bm.verts.new(p) for p in (
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
        quads = {
            "-z": (v[0], v[3], v[2], v[1]), "+z": (v[4], v[5], v[6], v[7]),
            "-y": (v[0], v[1], v[5], v[4]), "+y": (v[2], v[3], v[7], v[6]),
            "-x": (v[3], v[0], v[4], v[7]), "+x": (v[1], v[2], v[6], v[5]),
        }
        for key, q in quads.items():
            f = self.bm.faces.new(q)
            s = (faces or {}).get(key, sw)
            self._paint(f, logo_uv() if s == "logo" else swatch_uv(s))

    def cyl(self, center, r, h, sw="steel", segs=16, axis="z", cap_sw=None):
        cx, cy, cz = center
        ring0, ring1 = [], []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            dx, dy = math.cos(a) * r, math.sin(a) * r
            if axis == "z":
                ring0.append(self.bm.verts.new((cx + dx, cy + dy, cz)))
                ring1.append(self.bm.verts.new((cx + dx, cy + dy, cz + h)))
            else:  # x axis
                ring0.append(self.bm.verts.new((cx, cy + dx, cz + dy)))
                ring1.append(self.bm.verts.new((cx + h, cy + dx, cz + dy)))
        for i in range(segs):
            j = (i + 1) % segs
            self._paint(self.bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i])), swatch_uv(sw))
        self._paint(self.bm.faces.new(list(reversed(ring0))), swatch_uv(cap_sw or sw))
        self._paint(self.bm.faces.new(ring1), swatch_uv(cap_sw or sw))

    def finish(self, name):
        mesh = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        return obj


def material():
    mat = create_shader("default.sps")
    node = mat.node_tree.nodes["DiffuseSampler"]
    node.image = ATLAS
    node.texture_properties.embedded = True
    return mat


def collision(drawable, boxes):
    comp = create_empty_object(SollumType.BOUND_COMPOSITE, drawable.name + "_col")
    comp.parent = drawable
    cmat = create_collision_material_from_index(0)
    for (mn, mx) in boxes:
        b = create_blender_object(SollumType.BOUND_BOX)
        size = Vector(mx) - Vector(mn)
        create_box(b.data, 1, Matrix.Diagonal(size))
        b.data.materials.append(cmat)
        b.location = (Vector(mn) + Vector(mx)) * 0.5
        b.parent = comp
        apply_flag_preset(b, "General (Default)")


def drawable(name, builder, boxes):
    obj = builder.finish(name + "_model")
    obj.data.materials.append(material())
    mesh_add_missing_uv_maps(obj.data)
    mesh_add_missing_color_attrs(obj.data)
    root = create_empty_object(SollumType.DRAWABLE, name)
    convert_obj_to_model(obj)
    obj.parent = root
    if boxes:
        collision(root, boxes)
    return root


# ─────────────────────────── props ───────────────────────────
def grow_tent():
    b = Builder()
    W, D, H, T = 0.45, 0.45, 1.9, 0.02
    inner = {"-x": "mylar", "+x": "mylar", "-y": "mylar", "+y": "mylar", "-z": "mylar", "+z": "mylar"}
    # walls: fabric outside, mylar inside
    b.box((-W, D - T, 0), (W, D, H), "fabric", {"-y": "mylar"})                 # back
    b.box((-W, -D, 0), (-W + T, D, H), "fabric", {"+x": "mylar"})               # left
    b.box((W - T, -D, 0), (W, D, H), "fabric", {"-x": "mylar"})                 # right
    b.box((-W, -D, H - T), (W, D, H), "fabric", {"-z": "mylar"})                # roof
    b.box((-W + T, -D + T, 0), (W - T, D - T, 0.02), "fabric", {"+z": "floor"})  # floor
    # front frame around the door opening (the logo sits on the top band)
    b.box((-W, -D, 1.62), (W, -D + T, H), "fabric", {"-y": "logo", "+y": "mylar"})
    b.box((-W, -D, 0), (-0.33, -D + T, 1.62), "fabric", {"+y": "mylar"})
    b.box((0.33, -D, 0), (W, -D + T, 1.62), "fabric", {"+y": "mylar"})
    b.box((-0.33, -D, 0), (0.33, -D + T, 0.12), "fabric", {"+y": "mylar"})
    # green trim around the door and on every outer edge
    t, e = 0.018, -D - 0.004
    b.box((-0.335, e, 0.12), (-0.317, -D, 1.62), "green")
    b.box((0.317, e, 0.12), (0.335, -D, 1.62), "green")
    b.box((-0.335, e, 1.602), (0.335, -D, 1.62), "green")
    b.box((-0.335, e, 0.12), (0.335, -D, 0.138), "green")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W - t / 2), sy * (D - t / 2)
            b.box((x - t / 2 - 0.002, y - t / 2 - 0.002, 0), (x + t / 2 + 0.002, y + t / 2 + 0.002, H), "green")
    for sy in (-1, 1):
        y = sy * (D - t / 2)
        b.box((-W - 0.002, y - t / 2 - 0.002, H - t), (W + 0.002, y + t / 2 + 0.002, H + 0.002), "green")
        b.box((-W - 0.002, y - t / 2 - 0.002, 0), (W + 0.002, y + t / 2 + 0.002, t), "green")
    for sx in (-1, 1):
        x = sx * (W - t / 2)
        b.box((x - t / 2 - 0.002, -D - 0.002, H - t), (x + t / 2 + 0.002, D + 0.002, H + 0.002), "green")
        b.box((x - t / 2 - 0.002, -D - 0.002, 0), (x + t / 2 + 0.002, D + 0.002, t), "green")
    # rolled up door flap (left side, like the reference)
    b.cyl((-0.39, -D - 0.03, 0.14), 0.035, 1.46, "mylar_dk", cap_sw="fabric")
    # vent window on the right side, round port on the left
    b.box((W, 0.12, 0.25), (W + 0.004, 0.32, 0.45), "black", {"+x": "fabric"})
    b.box((W, 0.12, 0.25), (W + 0.006, 0.135, 0.45), "green")
    b.box((W, 0.305, 0.25), (W + 0.006, 0.32, 0.45), "green")
    b.box((W, 0.12, 0.25), (W + 0.006, 0.32, 0.265), "green")
    b.box((W, 0.12, 0.435), (W + 0.006, 0.32, 0.45), "green")
    b.cyl((-W - 0.006, 0.18, 1.55), 0.07, 0.006, "green", axis="x", cap_sw="black")
    # light: two bars, straps, LED panel
    b.box((-W + T, -0.06, 1.84), (W - T, -0.04, 1.86), "steel_lt")
    b.box((-W + T, 0.04, 1.84), (W - T, 0.06, 1.86), "steel_lt")
    b.box((-0.2, -0.005, 1.68), (-0.19, 0.005, 1.84), "strap")
    b.box((0.19, -0.005, 1.68), (0.2, 0.005, 1.84), "strap")
    b.box((-0.25, -0.12, 1.64), (0.25, 0.12, 1.68), "steel_dk", {"-z": "white"})
    walls = [
        ((-W, D - T, 0), (W, D, H)), ((-W, -D, 0), (-W + T, D, H)), ((W - T, -D, 0), (W, D, H)),
        ((-W, -D, H - T), (W, D, H)), ((-W, -D, 1.62), (W, -D + T, H)),
        ((-W, -D, 0), (-0.33, -D + T, 1.62)), ((0.33, -D, 0), (W, -D + T, 1.62)),
    ]
    return drawable("nz_growtent", b, walls)


LID_X0, LID_X1 = 0.33, 0.8   # lid section along the bench (right end)
TOP = 0.9


def pack_bench():
    b = Builder()
    X, Y = 0.8, 0.375
    # table top (left part) + rims around the drawer opening
    b.box((-X, -Y, 0.86), (LID_X0, Y, TOP), "steel_lt", {"-z": "steel_dk"})
    b.box((LID_X0, -Y, 0.86), (X, -Y + 0.03, TOP), "steel_lt")
    b.box((LID_X0, Y - 0.03, 0.86), (X, Y, TOP), "steel_lt")
    b.box((X - 0.03, -Y, 0.86), (X, Y, TOP), "steel_lt")
    # drawer under the lid
    dx0, dx1, dy0, dy1, dz0 = LID_X0 + 0.015, X - 0.03, -Y + 0.03, Y - 0.03, 0.66
    b.box((dx0, dy0, dz0), (dx1, dy1, dz0 + 0.02), "drawer")
    b.box((dx0, dy0, dz0), (dx1, dy0 + 0.015, 0.86), "drawer")
    b.box((dx0, dy1 - 0.015, dz0), (dx1, dy1, 0.86), "drawer")
    b.box((dx0, dy0, dz0), (dx0 + 0.015, dy1, 0.86), "drawer")
    b.box((dx1 - 0.015, dy0, dz0), (dx1, dy1, 0.86), "drawer")
    # apron (deep front panel) and side panels
    b.box((-0.78, -0.37, 0.6), (0.78, -0.35, 0.86), "steel", {"+y": "steel_dk"})
    b.box((-0.78, -0.35, 0.6), (-0.76, 0.35, 0.86), "steel_dk")
    b.box((0.76, -0.35, 0.6), (0.78, 0.35, 0.86), "steel_dk")
    # legs + lower frame
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.74, sy * 0.32
            b.box((x - 0.03, y - 0.03, 0), (x + 0.03, y + 0.03, 0.86), "steel")
        b.box((sx * 0.74 - 0.02, -0.3, 0.12), (sx * 0.74 + 0.02, 0.3, 0.16), "steel")
    b.box((-0.72, 0.30, 0.12), (0.72, 0.34, 0.16), "steel")
    # uprights, shelf, light bar, red switch
    for sx in (-1, 1):
        b.box((sx * 0.72 - 0.025, 0.31, TOP), (sx * 0.72 + 0.025, 0.36, 1.78), "steel")
    b.box((-0.7, 0.1, 1.32), (0.7, 0.36, 1.345), "steel_dk")
    b.box((-0.76, 0.04, 1.74), (0.76, 0.37, 1.8), "steel_dk")
    b.box((-0.7, 0.1, 1.733), (0.7, 0.31, 1.74), "white")
    b.box((-0.76, 0.04, 1.73), (0.76, 0.06, 1.74), "steel")
    b.box((-0.705, 0.30, 1.0), (-0.675, 0.31, 1.03), "red")
    boxes = [
        ((-X, -Y, 0.86), (LID_X0, Y, TOP)), ((LID_X0, -Y, 0.6), (X, Y, 0.68)),
        ((-0.78, -0.37, 0.6), (0.78, -0.35, 0.86)),
        ((-0.77, -0.35, 0), (-0.71, 0.35, 0.86)), ((0.71, -0.35, 0), (0.77, 0.35, 0.86)),
        ((-0.75, 0.31, TOP), (0.75, 0.36, 1.8)), ((-0.7, 0.1, 1.32), (0.7, 0.36, 1.345)),
    ]
    return drawable("nz_packbench", b, boxes)


def pack_lid():
    # origin = hinge on the back edge, top surface. Lid spans -Y (towards the player)
    b = Builder()
    w = (LID_X1 - LID_X0) / 2
    b.box((-w, -0.75, -0.04), (w, 0.0, 0.0), "steel_lt", {"-z": "steel_dk"})
    b.box((-0.07, -0.765, -0.03), (0.07, -0.75, -0.012), "steel_dk")
    b.cyl((-w, -0.008, -0.02), 0.01, 2 * w, "steel", axis="x")
    return drawable("nz_packbench_lid", b, [((-w, -0.75, -0.04), (w, 0.0, 0.0))])


def zip_bag():
    b = Builder()
    b.box((-0.05, -0.07, 0.0), (0.05, 0.07, 0.01), "bag")
    b.box((-0.034, -0.052, 0.01), (0.034, 0.04, 0.016), "weed")
    b.box((-0.05, 0.05, 0.01), (0.05, 0.062, 0.014), "zip")
    return drawable("nz_zipbag", b, [((-0.05, -0.07, 0.0), (0.05, 0.07, 0.016))])


def jar():
    b = Builder()
    b.cyl((0, 0, 0), 0.04, 0.085, "glass", segs=20)
    b.cyl((0, 0, 0.004), 0.034, 0.055, "weed", segs=16)
    b.cyl((0, 0, 0.085), 0.036, 0.008, "glass", segs=20)
    return drawable("nz_jar", b, [((-0.04, -0.04, 0), (0.04, 0.04, 0.093))])


def jar_lid():
    b = Builder()
    b.cyl((0, 0, 0), 0.042, 0.016, "lid", segs=20)
    return drawable("nz_jar_lid", b, [((-0.042, -0.042, 0), (0.042, 0.042, 0.016))])


roots = [grow_tent(), pack_bench(), pack_lid(), zip_bag(), jar(), jar_lid()]
bpy.context.view_layer.update()

# print bounds for the ytyp
for r in roots:
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for ch in r.children:
        if ch.type == "MESH" and ch.sollum_type == SollumType.DRAWABLE_MODEL:
            for v in ch.data.vertices:
                p = ch.matrix_world @ v.co
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
    print("BOUNDS", r.name, tuple(round(c, 4) for c in lo), tuple(round(c, 4) for c in hi))

bpy.ops.object.select_all(action="DESELECT")
for r in roots:
    r.select_set(True)
res = bpy.ops.sollumz.export_assets(
    directory=OUT, direct_export=True, use_custom_settings=True,
    target_formats={"CWXML"}, target_versions={"GEN8"}, limit_to_selected=True,
    exclude_skeleton=False, ymap_exclude_entities=False, ymap_box_occluders=False, ymap_model_occluders=False,
)
print("EXPORT", res)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "nz_drugempire_props.blend"))
