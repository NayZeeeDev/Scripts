"""
nayzeee-garages - original key fob prop generator for Blender (4.x / 5.x).

Builds one low-poly key fob per design used by the key ring art (generic, sport, luxury,
classic, leather, compact) plus a plain metal car key, each in its own collection, sized like
a real fob (about 6-8 cm), with separate materials for the body, trim, buttons and badge.

Run it on your own machine:
    blender --background --python tools/fobprops/make_fobs.py -- --out install/fobprops
or open Blender, Scripting tab, open this file and press Run.

It saves install/fobprops/nz_keyfobs.blend and one GLB per prop. To use them in game, export
each collection with the Sollumz add-on as a drawable (nz_keyfob_<design>.ydr / nz_carkey.ydr)
plus one archetype file (nz_keyfobs.ytyp) - see install/fobprops/README.md.
"""
import math
import os
import sys

import bpy
import bmesh

DESIGNS = {
    # name: (width, length, thickness, corner radius, body colour, trim colour, buttons, shape)
    'generic': (0.034, 0.068, 0.013, 0.010, (0.05, 0.05, 0.055), (0.55, 0.56, 0.58), 4, 'round'),
    'sport':   (0.032, 0.072, 0.012, 0.006, (0.02, 0.02, 0.02),  (0.03, 0.69, 0.64), 4, 'wedge'),
    'luxury':  (0.036, 0.074, 0.014, 0.014, (0.08, 0.07, 0.06),  (0.80, 0.78, 0.74), 4, 'round'),
    'classic': (0.030, 0.062, 0.015, 0.004, (0.06, 0.06, 0.06),  (0.40, 0.40, 0.42), 3, 'box'),
    'leather': (0.036, 0.070, 0.016, 0.012, (0.22, 0.11, 0.05),  (0.70, 0.70, 0.72), 4, 'round'),
    'compact': (0.028, 0.052, 0.012, 0.010, (0.10, 0.10, 0.11),  (0.55, 0.56, 0.58), 3, 'round'),
}


def args():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = 'install/fobprops'
    if '--out' in argv:
        out = argv[argv.index('--out') + 1]
    return os.path.abspath(out)


def material(name, colour, metallic=0.0, roughness=0.5, emission=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*colour, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if emission is not None and 'Emission Color' in bsdf.inputs:
        bsdf.inputs['Emission Color'].default_value = (*emission, 1.0)
        bsdf.inputs['Emission Strength'].default_value = 1.5
    return mat


def rounded_slab(name, w, l, t, r, shape, segments=6):
    """Fob body: a rounded rectangle (or wedge) outline extruded to thickness t, bevelled."""
    bm = bmesh.new()
    pts = []
    hw, hl = w / 2, l / 2
    corners = [(hw - r, hl - r, 0), (-hw + r, hl - r, 90), (-hw + r, -hl + r, 180), (hw - r, -hl + r, 270)]
    for cx, cy, start in corners:
        for i in range(segments + 1):
            a = math.radians(start + 90 * i / segments)
            x, y = cx + r * math.cos(a), cy + r * math.sin(a)
            if shape == 'wedge' and y > 0:
                x *= 1 - 0.18 * (y / hl)  # taper the top
            pts.append((x, y))
    verts = [bm.verts.new((x, y, -t / 2)) for x, y in pts]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    top = [v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, t))
    bmesh.ops.bevel(bm, geom=[e for e in bm.edges], offset=min(r, t) * 0.35, segments=2, affect='EDGES')
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return bpy.data.objects.new(name, mesh)


def button(name, x, y, z, size, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=size, depth=0.002, location=(x, y, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def key_ring(name, l, mats):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.011, minor_radius=0.0012, major_segments=16,
                                     minor_segments=6, location=(0, l / 2 + 0.010, 0))
    ring = bpy.context.active_object
    ring.name = name
    ring.data.materials.append(mats['chrome'])
    return ring


def build_fob(design, spec, mats, coll):
    w, l, t, r, body_col, trim_col, n_buttons, shape = spec
    body_mat = material(f'nz_fob_{design}_body', body_col, roughness=0.35 if design != 'leather' else 0.8)
    trim_mat = material(f'nz_fob_{design}_trim', trim_col, metallic=0.9, roughness=0.25)
    body = rounded_slab(f'nz_keyfob_{design}', w, l, t, r, shape)
    body.data.materials.append(body_mat)
    coll.objects.link(body)
    trim = rounded_slab(f'nz_keyfob_{design}_trim', w * 1.02, l * 1.02, t * 0.25, r, shape)
    trim.data.materials.append(trim_mat)
    coll.objects.link(trim)
    parts = [trim]
    spacing = l * 0.16
    for i in range(n_buttons):
        y = l * 0.12 - i * spacing
        btn_mat = mats['panic'] if i == n_buttons - 1 else mats['button']
        b = button(f'nz_keyfob_{design}_btn{i}', 0, y, t / 2 + 0.0008, w * 0.18, btn_mat)
        parts.append(b)
    badge = button(f'nz_keyfob_{design}_badge', 0, l * 0.34, t / 2 + 0.0006, w * 0.22, mats['badge'])
    parts.append(badge)
    parts.append(key_ring(f'nz_keyfob_{design}_ring', l, mats))
    for p in parts:
        for c in p.users_collection:
            if c is not coll:
                c.objects.unlink(p)
        if p.name not in coll.objects:
            coll.objects.link(p)
        p.parent = body
    return body


def build_key(mats, coll):
    head = rounded_slab('nz_carkey', 0.026, 0.030, 0.008, 0.009, 'round')
    head.data.materials.append(mats['body_black'])
    coll.objects.link(head)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.040, 0))
    blade = bpy.context.active_object
    blade.name = 'nz_carkey_blade'
    blade.scale = (0.008, 0.050, 0.002)
    blade.data.materials.append(mats['chrome'])
    for c in blade.users_collection:
        c.objects.unlink(blade)
    coll.objects.link(blade)
    blade.parent = head
    ring = key_ring('nz_carkey_ring', 0.030, mats)
    for c in ring.users_collection:
        c.objects.unlink(ring)
    coll.objects.link(ring)
    ring.parent = head
    return head


def main():
    out = args()
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {
        'button': material('nz_fob_button', (0.12, 0.12, 0.13), roughness=0.6),
        'panic': material('nz_fob_panic', (0.70, 0.08, 0.08), roughness=0.5, emission=(0.4, 0.02, 0.02)),
        'badge': material('nz_fob_badge', (0.75, 0.75, 0.78), metallic=1.0, roughness=0.2),
        'chrome': material('nz_fob_chrome', (0.8, 0.8, 0.82), metallic=1.0, roughness=0.15),
        'body_black': material('nz_fob_key_head', (0.04, 0.04, 0.045), roughness=0.4),
    }
    roots = []
    for design, spec in DESIGNS.items():
        coll = bpy.data.collections.new(f'nz_keyfob_{design}')
        bpy.context.scene.collection.children.link(coll)
        roots.append((coll, build_fob(design, spec, mats, coll)))
    coll = bpy.data.collections.new('nz_carkey')
    bpy.context.scene.collection.children.link(coll)
    roots.append((coll, build_key(mats, coll)))

    # lay them out side by side for inspection; the GLB export keeps each at the origin
    for i, (_, root) in enumerate(roots):
        root.location.x = i * 0.1

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'nz_keyfobs.blend'))
    for coll, root in roots:
        bpy.ops.object.select_all(action='DESELECT')
        x = root.location.x
        root.location.x = 0
        for obj in coll.objects:
            obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, f'{coll.name}.glb'), use_selection=True,
                                  export_format='GLB')
        root.location.x = x
    print(f'nayzeee-garages: {len(roots)} key props written to {out}')


main()
