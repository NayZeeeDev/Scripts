"""
nayzeee-garages - export the key fob props (nz_keyfobs.blend from make_fobs.py) to GTA V with Sollumz.

    blender --background install/fobprops/nz_keyfobs.blend --python tools/fobprops/export_gta.py -- --out <dir>
    python export_gta.py -- --blend install/fobprops/nz_keyfobs.blend --out <dir> --sollumz <addons dir>   (pip bpy)

What it does, per prop (one mesh object per collection):
  * builds one 32x32 colour-swatch texture (nz_keyfob_atlas.dds, uncompressed A8R8G8B8, embedded in every
    drawable) from the Principled base colours, and points every face's UVs at its material's swatch;
  * swaps the materials for two GTA shaders: default.sps (everything) and emissive.sps (panic button / LEDs);
  * converts the object to a Sollumz drawable with a bound composite holding one box (collision);
  * exports <name>.ydr and one nz_keyfobs.ytyp with every archetype (lodDist 60, bbox / bsphere from the model).

Formats: CodeWalker XML (.ydr.xml / .ytyp.xml) always; binary .ydr / .ytyp as well when Sollumz's native
backend (PyMateria, Windows only) is installed. Convert XML to binary with CodeWalker otherwise.
"""
import os
import shutil
import struct
from pathlib import Path
import sys

import bpy

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


OUT = os.path.abspath(opt('--out', 'install/fobprops/gta5'))
LOD_DIST = 60.0
GRID, SWATCH = 8, 4  # 8 x 8 swatches of 4 x 4 px -> 32 x 32 texture
ATLAS = 'nz_keyfob_atlas'

if opt('--sollumz'):
    sys.path.insert(0, os.path.abspath(opt('--sollumz')))
    import addon_utils

    def _raise(e):
        raise e
    addon_utils.enable('Sollumz', default_set=True, handle_error=_raise)
if opt('--blend'):
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(opt('--blend')))

sz = sys.modules.get('Sollumz') or next(m for n, m in sys.modules.items() if n.endswith('sollumz_dev') or n == 'Sollumz')
pkg = sz.__name__
import importlib  # noqa: E402

drawablehelper = importlib.import_module(f'{pkg}.tools.drawablehelper')
blenderhelper = importlib.import_module(f'{pkg}.tools.blenderhelper')
boundhelper = importlib.import_module(f'{pkg}.tools.boundhelper')
meshhelper = importlib.import_module(f'{pkg}.tools.meshhelper')
shader_materials = importlib.import_module(f'{pkg}.ydr.shader_materials')
ydrexport = importlib.import_module(f'{pkg}.ydr.ydrexport')
ytypexport = importlib.import_module(f'{pkg}.ytyp.ytypexport')
iecontext = importlib.import_module(f'{pkg}.iecontext')
props = importlib.import_module(f'{pkg}.sollumz_properties')
from szio.gta5 import AssetFormat, AssetTarget, AssetVersion, is_provider_available  # noqa: E402

SollumType = props.SollumType
TARGETS = tuple(AssetTarget(f, AssetVersion.GEN8) for f in (AssetFormat.CWXML, AssetFormat.NATIVE)
                if is_provider_available(f))


def to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def write_dds(path, w, h, pixels):
    """Uncompressed A8R8G8B8 DDS, one mip. pixels: rows of (r, g, b, a) bytes, top row first."""
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x8  # CAPS | HEIGHT | WIDTH | PIXELFORMAT | PITCH
    pf = struct.pack('<II4sIIIII', 32, 0x41, b'\0\0\0\0', 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    header = struct.pack('<IIIIIII44s', 124, flags, h, w, w * 4, 0, 1, b'\0' * 44) + pf + \
        struct.pack('<IIIII', 0x1000, 0, 0, 0, 0)
    data = bytearray()
    for row in pixels:
        for r, g, b, a in row:
            data += bytes((b, g, r, a))
    with open(path, 'wb') as f:
        f.write(b'DDS ' + header + data)


def build_atlas(objs, tex_dir):
    mats = []
    for obj in objs:
        for m in obj.data.materials:
            if m not in mats:
                mats.append(m)
    assert len(mats) <= GRID * GRID, 'too many colours for the atlas'
    size = GRID * SWATCH
    px = [[(255, 255, 255, 255)] * size for _ in range(size)]
    uv = {}
    for i, m in enumerate(mats):
        gx, gy = i % GRID, i // GRID
        bsdf = m.node_tree.nodes.get('Principled BSDF')
        col = bsdf.inputs['Base Color'].default_value if bsdf else m.diffuse_color
        rgb = tuple(max(0, min(255, round(to_srgb(c) * 255))) for c in col[:3])
        for y in range(gy * SWATCH, gy * SWATCH + SWATCH):
            for x in range(gx * SWATCH, gx * SWATCH + SWATCH):
                px[y][x] = (*rgb, 255)
        # UV origin is bottom-left in Blender; DDS row 0 is the top
        uv[m.name] = ((gx + 0.5) / GRID, 1 - (gy + 0.5) / GRID)
    os.makedirs(tex_dir, exist_ok=True)
    path = os.path.join(tex_dir, f'{ATLAS}.dds')
    write_dds(path, size, size, px)
    return uv, path


def gta_material(shader, name, img, params):
    mat = shader_materials.create_shader(shader)
    mat.name = name
    for node in mat.node_tree.nodes:
        if node.bl_idname == 'ShaderNodeTexImage' and node.name == 'DiffuseSampler':
            node.image = img
            node.texture_properties.embedded = True
    for pname, value in params.items():
        node = mat.node_tree.nodes.get(pname)
        if node is None or not hasattr(node, 'set'):
            raise RuntimeError(f'{shader} has no parameter {pname}')
        node.set('X', value)
    return mat


def add_box_bound(drawable, obj):
    lo = [min(v.co[i] for v in obj.data.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in obj.data.vertices) for i in range(3)]
    comp = blenderhelper.create_empty_object(SollumType.BOUND_COMPOSITE, f'{drawable.name}.col')
    comp.parent = drawable
    box = boundhelper.create_bound_box()
    box.name = f'{drawable.name}.box'
    from mathutils import Matrix, Vector
    size = [hi[i] - lo[i] for i in range(3)]
    center = Vector([(hi[i] + lo[i]) / 2 for i in range(3)])
    box.data.transform(Matrix.Diagonal((*size, 1.0)))
    box.data.transform(Matrix.Translation(center))
    box.parent = comp
    cm = importlib.import_module(f'{pkg}.ybn.collision_materials')
    plastic = next(i for i, m in enumerate(cm.collisionmats) if m.name == 'PLASTIC')
    box.data.materials.append(cm.create_collision_material_from_index(plastic))
    return comp


def main():
    os.makedirs(OUT, exist_ok=True)
    print('targets:', [f'{t.format.name}/{t.version.name}' for t in TARGETS])
    objs = [o for c in bpy.data.collections if c.name.startswith('nz_') for o in c.objects if o.type == 'MESH']
    uv_of, atlas_path = build_atlas(objs, os.path.join(OUT, '_textures'))
    img = bpy.data.images.load(atlas_path, check_existing=True)
    img.name = f'{ATLAS}.dds'
    img.pack()  # keep the DDS inside the saved .blend; Sollumz embeds packed DDS data as is
    base = gta_material('default.sps', 'nz_fob_gta', img, {})
    glow = gta_material('emissive.sps', 'nz_fob_gta_glow', img, {'emissiveMultiplier': 2.0})

    drawables = []
    for obj in objs:
        mesh = obj.data
        src = [m.name for m in mesh.materials]
        emissive = [bool(m.get('nz_emissive')) for m in mesh.materials]
        uvl = mesh.uv_layers.get('UVMap') or mesh.uv_layers.new(name='UVMap')
        uvl.name = 'UVMap 0'  # Sollumz reads TexCoord0 from 'UVMap 0'
        slots = []
        for poly in mesh.polygons:
            u, v = uv_of[src[poly.material_index]]
            for li in poly.loop_indices:
                uvl.data[li].uv = (u, v)
            slots.append(1 if emissive[poly.material_index] else 0)
        mesh.materials.clear()  # resets the face material indices, so they are set again below
        mesh.materials.append(base)
        mesh.materials.append(glow)
        mesh.polygons.foreach_set('material_index', slots)
        mesh.update()
        if not mesh.color_attributes:
            ca = mesh.color_attributes.new('Color 1', 'BYTE_COLOR', 'CORNER')
            for d in ca.data:
                d.color = (1, 1, 1, 1)
        meshhelper.mesh_add_missing_uv_maps(mesh)
        name = obj.name
        bpy.context.view_layer.objects.active = obj
        drawable = drawablehelper.convert_obj_to_drawable(obj)
        for c in obj.users_collection:
            if drawable.name not in c.objects:
                c.objects.link(drawable)
        add_box_bound(drawable, obj)
        drawables.append(drawable)
        assert drawable.name == name, (drawable.name, name)

    settings = iecontext.ExportSettings(targets=TARGETS)
    for d in drawables:
        with iecontext.export_context_scope(iecontext.ExportContext(d.name, settings)):
            bundle = ydrexport.export_ydr(d)
        assert bundle.is_valid(), f'{d.name}: export failed'
        bundle.save(Path(OUT), TARGETS)

    # archetypes
    scene = bpy.context.scene
    bpy.ops.sollumz.createytyp()
    ytyp = scene.ytyps[-1]
    ytyp.name = 'nz_keyfobs'
    bpy.ops.object.select_all(action='DESELECT')
    for d in drawables:
        d.select_set(True)
    bpy.context.view_layer.objects.active = drawables[0]
    bpy.ops.sollumz.createarchetypefromselected()
    for a in ytyp.archetypes:
        a.lod_dist = LOD_DIST
        a.hd_texture_dist = 5.0
    with iecontext.export_context_scope(iecontext.ExportContext('nz_keyfobs', settings)):
        bundle = ytypexport.export_ytyp(scene, len(scene.ytyps) - 1)
    bundle.save(Path(OUT), TARGETS)
    print(f'nayzeee-garages: {len(drawables)} drawables + nz_keyfobs ytyp ({len(ytyp.archetypes)} archetypes) -> {OUT}')
    shutil.rmtree(os.path.join(OUT, '_textures'), ignore_errors=True)
    if opt('--save-blend'):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(opt('--save-blend')), compress=True)


main()
if opt('--sollumz'):
    sys.stdout.flush()
    os._exit(0)  # the bpy module can hang on interpreter shutdown with Sollumz loaded
