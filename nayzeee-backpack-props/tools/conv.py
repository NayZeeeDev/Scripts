#!/usr/bin/env python3
"""
Clothing bag (.ydd ped component, CodeWalker XML) -> prop (.ydr) XML.

  python3 conv.py drawable <src.ydd.xml> <item index> <model> <out dir>
  python3 conv.py prop     <src.ydr.xml> <model> <out dir>          (already a prop: rename only)
  python3 conv.py texture  <src.ytd.xml> <new texture name> <out xml>
  python3 conv.py ytyp     <model> <variant count> <bounds.json> <out xml> [--alpha] [--no-txd] [--loose=<bounds.json>]

What `drawable` does:
  * DrawableDictionary item -> Drawable root, named <model>
  * drops the ped skeleton, un-skins every model (HasSkin 0, no BoneIDs)
  * vertex layout -> Position Normal Colour0 TexCoord0 [Tangent]
    (blend weights/indices and the 2nd colour/uv set are removed per vertex)
  * ped shaders -> prop shaders: normal_spec when tangents exist, else default;
    ped_alpha / ped_fur go in the alpha bucket
  * DiffuseSampler (empty on clothing: the ped system fills it per colour)
    -> <model>_d, which every colour's .ytd provides
  * recomputes bounds from the real vertices
Writes <out>/<model>.ydr.xml, copies embedded textures to <out>/<model>/,
and <out>/bounds.json.
"""
import json
import math
import os
import shutil
import sys
import xml.etree.ElementTree as ET

KEEP = ['Position', 'Normal', 'Colour0', 'TexCoord0', 'Tangent']
ALPHA_SHADERS = {'ped_alpha', 'ped_fur', 'ped_hair_cutout_alpha', 'hash_4478B2A6', 'hash_66D45BB7'}


def vec(el, **kv):
    for k, v in kv.items():
        el.set(k, repr(float(v)) if isinstance(v, float) else str(v))


def param_tex(params, name, tex):
    it = ET.SubElement(params, 'Item', {'name': name, 'type': 'Texture'})
    if tex:
        ET.SubElement(it, 'Name').text = tex


def param_vec(params, name, x=0.0, y=0.0, z=0.0, w=0.0):
    ET.SubElement(params, 'Item', {'name': name, 'type': 'Vector', 'x': str(x), 'y': str(y), 'z': str(z), 'w': str(w)})


def tex_of(shader, pname):
    ps = shader.find('Parameters')
    for it in (ps if ps is not None else []):
        if it.get('name') == pname:
            n = it.find('Name')
            return n.text if n is not None else None
    return None


def convert_shader(sh, diffuse, has_tangent):
    old = (sh.findtext('Name') or '').strip()
    bump = tex_of(sh, 'BumpSampler')
    spec = tex_of(sh, 'SpecSampler')
    alpha = old in ALPHA_SHADERS

    for child in list(sh):
        sh.remove(child)

    params = ET.Element('Parameters')
    if has_tangent:
        name = 'normal_spec'
        param_tex(params, 'DiffuseSampler', diffuse)
        param_tex(params, 'BumpSampler', bump)
        param_tex(params, 'SpecSampler', spec)
        param_vec(params, 'specularFresnel', 0.97)
        param_vec(params, 'specularFalloffMult', 100)
        param_vec(params, 'specularIntensityMult', 0.3)
        param_vec(params, 'specMapIntMask', 1, 0, 0, 0)
        param_vec(params, 'bumpiness', 1)
        param_vec(params, 'wetnessMultiplier', 1)
        param_vec(params, 'useTessellation', 0)
        param_vec(params, 'HardAlphaBlend', 1 if alpha else 0)
    else:
        name = 'default'
        param_tex(params, 'DiffuseSampler', diffuse)
        param_vec(params, 'wetnessMultiplier', 1)
        param_vec(params, 'useTessellation', 0)
        param_vec(params, 'HardAlphaBlend', 1 if alpha else 0)
        param_vec(params, 'matMaterialColorScale', 1, 0, 0, 1)
        param_vec(params, 'globalAnimUV0', 1, 0, 0, 0)
        param_vec(params, 'globalAnimUV1', 0, 1, 0, 0)

    ET.SubElement(sh, 'Name').text = name
    ET.SubElement(sh, 'FileName').text = name + '.sps'
    ET.SubElement(sh, 'RenderBucket', {'value': '1' if alpha else '0'})
    sh.append(params)
    return alpha


def data_node(vb):
    for tag in ('Data', 'Data2'):
        d = vb.find(tag)
        if d is not None and d.text and d.text.strip():
            return d
    return None


def convert_geometry(g, mins, maxs, stats):
    b = g.find('BoneIDs')
    if b is not None:
        g.remove(b)

    vb = g.find('VertexBuffer')
    layout = vb.find('Layout')
    comps = [c.tag for c in layout]
    keep_idx = [i for i, c in enumerate(comps) if c in KEEP]
    for c in list(layout):
        if c.tag not in KEEP:
            layout.remove(c)

    d = data_node(vb)
    rows = d.text.strip().split('\n')
    out = []
    gmin = [math.inf] * 3
    gmax = [-math.inf] * 3
    pos_i = comps.index('Position')
    for r in rows:
        parts = [p for p in r.strip().split('   ')]
        if len(parts) != len(comps):
            raise SystemExit(f'vertex row has {len(parts)} parts, layout has {len(comps)}: {r[:80]}')
        p = [float(v) for v in parts[pos_i].split()]
        for k in range(3):
            gmin[k] = min(gmin[k], p[k]); gmax[k] = max(gmax[k], p[k])
            mins[k] = min(mins[k], p[k]); maxs[k] = max(maxs[k], p[k])
        stats['points'].append(p)
        out.append('   '.join(parts[i] for i in keep_idx))
    # weld: many clothing meshes give every triangle its own 3 vertices.
    # Merge rows that are byte-for-byte identical and re-point the triangles;
    # nothing visible changes, the vertex count and file size drop a lot.
    remap, uniq, index_of = [], [], {}
    for row in out:
        i = index_of.get(row)
        if i is None:
            i = index_of[row] = len(uniq)
            uniq.append(row)
        remap.append(i)
    ib = g.find('IndexBuffer').find('Data')
    idx = [remap[int(v)] for v in ib.text.split()]
    ib.text = '\n' + '\n'.join(' '.join(str(v) for v in idx[k:k + 24]) for k in range(0, len(idx), 24)) + '\n'
    d.text = '\n' + '\n'.join(uniq) + '\n'
    stats['verts'] += len(uniq)
    stats['raw'] = stats.get('raw', 0) + len(rows)

    bmin, bmax = g.find('BoundingBoxMin'), g.find('BoundingBoxMax')
    if bmin is not None:
        vec(bmin, x=gmin[0], y=gmin[1], z=gmin[2])
    if bmax is not None:
        vec(bmax, x=gmax[0], y=gmax[1], z=gmax[2])
    return 'Tangent' in comps


def drawable(src, index, model, outdir):
    tree = ET.parse(src)
    root = tree.getroot()
    items = root.findall('Item') if root.tag == 'DrawableDictionary' else [root]
    item = items[int(index)]

    d = ET.Element('Drawable')
    for child in list(item):
        if child.tag in ('Skeleton', 'Joints'):
            continue
        d.append(child)
    d.find('Name').text = model

    diffuse = model + '_d'
    mins, maxs = [math.inf] * 3, [-math.inf] * 3
    stats = {'verts': 0, 'points': []}

    tangent_ok = True
    shader_uses = {}
    for tag in ('DrawableModelsHigh', 'DrawableModelsMedium', 'DrawableModelsLow', 'DrawableModelsVeryLow'):
        lod = d.find(tag)
        if lod is None:
            continue
        for m in lod.findall('Item'):
            hs = m.find('HasSkin')
            if hs is not None:
                hs.set('value', '0')
            bi = m.find('BoneIndex')
            if bi is not None:
                bi.set('value', '0')
            for g in m.find('Geometries').findall('Item'):
                has_t = convert_geometry(g, mins, maxs, stats)
                sid = int(g.find('ShaderIndex').get('value'))
                shader_uses.setdefault(sid, []).append(has_t)

    shaders = d.find('ShaderGroup').find('Shaders').findall('Item')
    any_alpha = False
    for i, sh in enumerate(shaders):
        # a shader is normal_spec only if every geometry using it has tangents
        has_t = all(shader_uses.get(i, [False]))
        any_alpha = convert_shader(sh, diffuse, has_t) or any_alpha

    centre = [(mins[k] + maxs[k]) / 2 for k in range(3)]
    radius = max(math.dist(p, centre) for p in stats['points'])
    vec(d.find('BoundingSphereCenter'), x=centre[0], y=centre[1], z=centre[2])
    d.find('BoundingSphereRadius').set('value', str(radius))
    vec(d.find('BoundingBoxMin'), x=mins[0], y=mins[1], z=mins[2])
    vec(d.find('BoundingBoxMax'), x=maxs[0], y=maxs[1], z=maxs[2])
    for tag in ('LodDistHigh', 'LodDistMed', 'LodDistLow', 'LodDistVlow'):
        el = d.find(tag)
        if el is not None:
            el.set('value', '9998')

    os.makedirs(outdir, exist_ok=True)
    texdir = os.path.join(outdir, model)
    os.makedirs(texdir, exist_ok=True)
    srcdir = os.path.splitext(os.path.splitext(src)[0])[0]  # folder CodeWalker exported dds into
    for t in d.find('ShaderGroup').iter('FileName'):
        f = t.text and os.path.join(srcdir, t.text)
        if f and os.path.isfile(f):
            shutil.copy(f, texdir)

    ET.ElementTree(d).write(os.path.join(outdir, model + '.ydr.xml'), encoding='UTF-8', xml_declaration=True)
    bounds = {'min': mins, 'max': maxs, 'centre': centre, 'radius': radius,
              'alpha': any_alpha, 'verts': stats['verts'], 'raw_verts': stats.get('raw', 0), 'shaders': [s.findtext('Name') for s in shaders]}
    json.dump(bounds, open(os.path.join(outdir, 'bounds.json'), 'w'), indent=1)
    print(json.dumps({k: v for k, v in bounds.items()}, default=str))


def prop(src, model, outdir):
    """Already a prop: rename the drawable, keep everything else."""
    tree = ET.parse(src)
    d = tree.getroot()
    d.find('Name').text = model
    os.makedirs(outdir, exist_ok=True)
    texdir = os.path.join(outdir, model)
    os.makedirs(texdir, exist_ok=True)
    srcdir = os.path.splitext(os.path.splitext(src)[0])[0]
    for t in d.iter('FileName'):
        f = t.text and os.path.join(srcdir, t.text)
        if f and os.path.isfile(f):
            shutil.copy(f, texdir)
    mn = d.find('BoundingBoxMin'); mx = d.find('BoundingBoxMax')
    mins = [float(mn.get(k)) for k in 'xyz']; maxs = [float(mx.get(k)) for k in 'xyz']
    c = d.find('BoundingSphereCenter')
    centre = [float(c.get(k)) for k in 'xyz']
    radius = float(d.find('BoundingSphereRadius').get('value'))
    tree.write(os.path.join(outdir, model + '.ydr.xml'), encoding='UTF-8', xml_declaration=True)
    json.dump({'min': mins, 'max': maxs, 'centre': centre, 'radius': radius, 'alpha': False},
              open(os.path.join(outdir, 'bounds.json'), 'w'), indent=1)


def texture(src, newname, outxml):
    """One colour's .ytd: keep its diffuse, renamed to what the prop's shader asks for."""
    tree = ET.parse(src)
    root = tree.getroot()
    items = root.findall('Item')
    keep = None
    for it in items:
        if (it.findtext('Usage') or '').upper() == 'DIFFUSE':
            keep = it
            break
    keep = keep if keep is not None else items[0]
    for it in items:
        if it is not keep:
            root.remove(it)
    srcdir = os.path.splitext(os.path.splitext(src)[0])[0]
    old = keep.findtext('FileName')
    keep.find('Name').text = newname
    keep.find('FileName').text = newname + '.dds'
    outdir = os.path.splitext(os.path.splitext(outxml)[0])[0]
    os.makedirs(outdir, exist_ok=True)
    shutil.copy(os.path.join(srcdir, old), os.path.join(outdir, newname + '.dds'))
    tree.write(outxml, encoding='UTF-8', xml_declaration=True)


def ytyp(model, count, bounds_path, outxml, alpha=False, no_txd=False, lod=100, loose=None):
    """`loose`: bounds of <model>_loose (the same bag off the back, straps
    lying flat). Each colour then also gets <colour>_loose, drawing that
    model with the colour's own textures."""
    b = json.load(open(bounds_path))
    flags = 537001984 + (32 if alpha or b.get('alpha') else 0)
    root = ET.Element('CMapTypes', {'name': model})
    ET.SubElement(root, 'extensions')
    arch = ET.SubElement(root, 'archetypes')
    kinds = [('', b)] + ([('_loose', json.load(open(loose)))] if loose else [])
    for (suffix, b), i in ((k, i) for k in kinds for i in range(1, int(count) + 1)):
        txdname = model if i == 1 else f'{model}_{i}'
        name = txdname + suffix
        it = ET.SubElement(arch, 'Item', {'type': 'CBaseArchetypeDef'})
        ET.SubElement(it, 'lodDist', {'value': str(lod)})
        ET.SubElement(it, 'flags', {'value': str(flags)})
        ET.SubElement(it, 'specialAttribute', {'value': '0'})
        ET.SubElement(it, 'bbMin', {k: str(v) for k, v in zip('xyz', b['min'])})
        ET.SubElement(it, 'bbMax', {k: str(v) for k, v in zip('xyz', b['max'])})
        ET.SubElement(it, 'bsCentre', {k: str(v) for k, v in zip('xyz', b['centre'])})
        ET.SubElement(it, 'bsRadius', {'value': str(b['radius'])})
        ET.SubElement(it, 'hdTextureDist', {'value': '5'})
        ET.SubElement(it, 'name').text = name
        txd = ET.SubElement(it, 'textureDictionary')
        if not no_txd:
            txd.text = txdname
        ET.SubElement(it, 'clipDictionary')
        ET.SubElement(it, 'drawableDictionary')
        ET.SubElement(it, 'physicsDictionary')
        ET.SubElement(it, 'assetType').text = 'ASSET_TYPE_DRAWABLE'
        ET.SubElement(it, 'assetName').text = model + suffix  # every colour shares the one model
        ET.SubElement(it, 'extensions')
    ET.SubElement(root, 'name').text = model
    ET.SubElement(root, 'dependencies')
    ET.SubElement(root, 'compositeEntityTypes', {'itemType': 'CCompositeEntityType'})
    ET.ElementTree(root).write(outxml, encoding='UTF-8', xml_declaration=True)


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'drawable':
        drawable(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif cmd == 'prop':
        prop(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == 'texture':
        texture(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == 'ytyp':
        lod = next((int(a.split('=')[1]) for a in sys.argv if a.startswith('--lod=')), 100)
        loose = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--loose=')), None)
        ytyp(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], '--alpha' in sys.argv, '--no-txd' in sys.argv, lod, loose)
