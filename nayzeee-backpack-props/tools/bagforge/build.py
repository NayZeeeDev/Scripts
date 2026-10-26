#!/usr/bin/env python3
"""
bagforge: build original bag props from code.

  python3 build.py <catalog key> <work dir>

Writes, for CodeWalker to import:
  <work>/<model>.ydr.xml + <work>/<model>/<model>_n.dds    (shared shape + relief)
  <work>/t<i>/<name>.ytd.xml + dds                          (one per colour: _d + _s)
  <work>/bounds.json
"""
import io
import json
import os
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh as M          # noqa: E402
import textures as T      # noqa: E402
import packtex as PT      # noqa: E402
from catalog import CATALOG  # noqa: E402
from designs import DESIGNS  # noqa: E402


# ---- dds with mips ----------------------------------------------------------

def save_dds(img, path, fmt='DXT1', size=None):
    img = img.convert('RGBA')
    if size and img.width != size:
        img = img.resize((size, size), Image.LANCZOS)

    def level(im):
        b = io.BytesIO(); im.save(b, 'DDS', pixel_format=fmt); d = b.getvalue()
        return d[148:] if d[84:88] == b'DX10' else d[128:]

    levels, w = [], img.width
    cur = img
    while True:
        levels.append(level(cur))
        if w <= 4:
            break
        w //= 2
        cur = img.resize((max(4, w), max(4, w)), Image.LANCZOS)
    b = io.BytesIO(); img.save(b, 'DDS', pixel_format=fmt)
    head = bytearray(b.getvalue()[:128])
    struct.pack_into('<I', head, 8, struct.unpack_from('<I', head, 8)[0] | 0x20000)
    struct.pack_into('<I', head, 28, len(levels))
    struct.pack_into('<I', head, 108, struct.unpack_from('<I', head, 108)[0] | 0x400008)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(head)
        for lv in levels:
            f.write(lv)


# ---- xml helpers ---------------------------------------------------------------

def el(parent, tag, text=None, **attrs):
    e = ET.SubElement(parent, tag, {k: str(v) for k, v in attrs.items()})
    if text is not None:
        e.text = text
    return e


def vec(parent, tag, v, w=None):
    a = {'x': f'{v[0]:.6f}', 'y': f'{v[1]:.6f}', 'z': f'{v[2]:.6f}'}
    if w is not None:
        a['w'] = str(w)
    return ET.SubElement(parent, tag, a)


def tex_item(parent, name, usage):
    it = el(parent, 'Item')
    el(it, 'Name', name)
    el(it, 'Unk32', value=0)
    el(it, 'Usage', usage)
    el(it, 'UsageFlags', '0')
    el(it, 'ExtraFlags', value=0)
    el(it, 'Width', value=1024); el(it, 'Height', value=1024); el(it, 'MipLevels', value=1)
    el(it, 'Format', 'D3DFMT_DXT1')
    el(it, 'FileName', name + '.dds')


def param_tex(params, name, tex):
    it = el(params, 'Item', name=name, type='Texture'); el(it, 'Name', tex)


def param_vec(params, name, x=0, y=0, z=0, w=0):
    el(params, 'Item', name=name, type='Vector', x=x, y=y, z=z, w=w)


def write_ydr(model, mesh, outdir):
    P, N, UV, I = mesh.arrays()
    Tn = M.tangents(P, N, UV, I)
    mn, mx = P.min(0), P.max(0)
    centre = (mn + mx) / 2
    radius = float(np.linalg.norm(P - centre, axis=1).max())

    d = ET.Element('Drawable')
    el(d, 'Name', model)
    vec(d, 'BoundingSphereCenter', centre); el(d, 'BoundingSphereRadius', value=f'{radius:.6f}')
    vec(d, 'BoundingBoxMin', mn); vec(d, 'BoundingBoxMax', mx)
    for t in ('LodDistHigh', 'LodDistMed', 'LodDistLow', 'LodDistVlow'):
        el(d, t, value=9998)
    el(d, 'FlagsHigh', value=1)
    for t in ('FlagsMed', 'FlagsLow', 'FlagsVlow'):
        el(d, t, value=0)
    sg = el(d, 'ShaderGroup')
    td = el(sg, 'TextureDictionary')
    tex_item(td, model + '_n', 'NORMAL')
    sh = el(el(sg, 'Shaders'), 'Item')
    el(sh, 'Name', 'normal_spec'); el(sh, 'FileName', 'normal_spec.sps'); el(sh, 'RenderBucket', value=0)
    ps = el(sh, 'Parameters')
    param_tex(ps, 'DiffuseSampler', model + '_d')
    param_tex(ps, 'BumpSampler', model + '_n')
    param_tex(ps, 'SpecSampler', model + '_s')
    param_vec(ps, 'specularFresnel', 0.97)
    param_vec(ps, 'specularFalloffMult', 120)
    param_vec(ps, 'specularIntensityMult', 1.0)
    param_vec(ps, 'specMapIntMask', 1, 0, 0, 0)
    param_vec(ps, 'bumpiness', 1.2)
    param_vec(ps, 'wetnessMultiplier', 1)
    param_vec(ps, 'useTessellation', 0)
    param_vec(ps, 'HardAlphaBlend', 0)

    models = el(d, 'DrawableModelsHigh')
    mi = el(models, 'Item')
    el(mi, 'RenderMask', value=255); el(mi, 'Flags', value=0); el(mi, 'HasSkin', value=0)
    el(mi, 'BoneIndex', value=0); el(mi, 'Unknown1', value=0)
    geos = el(mi, 'Geometries')

    # split into geometries of < 65000 vertices (index buffers are 16-bit)
    tris = I
    start = 0
    while start < len(tris):
        used, local, chunk = {}, [], []
        k = start
        while k < len(tris):
            tri = tris[k]
            new = [v for v in tri if v not in used]
            if len(used) + len(new) > 65000:
                break
            for v in tri:
                if v not in used:
                    used[v] = len(local); local.append(v)
            chunk.append([used[v] for v in tri])
            k += 1
        start = k
        g = el(geos, 'Item')
        el(g, 'ShaderIndex', value=0)
        lp = P[local]
        vec(g, 'BoundingBoxMin', lp.min(0), 0); vec(g, 'BoundingBoxMax', lp.max(0), 0)
        vb = el(g, 'VertexBuffer'); el(vb, 'Flags', value=0)
        lay = el(vb, 'Layout', type='GTAV1')
        for c in ('Position', 'Normal', 'Colour0', 'TexCoord0', 'Tangent'):
            el(lay, c)
        rows = []
        for v in local:
            p, n, uv, t = P[v], N[v], UV[v], Tn[v]
            rows.append(f'{p[0]:.5f} {p[1]:.5f} {p[2]:.5f}   {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}   255 255 255 255   '
                        f'{uv[0]:.5f} {uv[1]:.5f}   {t[0]:.4f} {t[1]:.4f} {t[2]:.4f} {t[3]:.0f}')
        el(vb, 'Data', '\n' + '\n'.join(rows) + '\n')
        flat = [str(i) for tri in chunk for i in tri]
        el(el(g, 'IndexBuffer'), 'Data', '\n' + '\n'.join(' '.join(flat[i:i + 24]) for i in range(0, len(flat), 24)) + '\n')
    el(d, 'Lights')

    ET.ElementTree(d).write(os.path.join(outdir, model + '.ydr.xml'), encoding='UTF-8', xml_declaration=True)
    return {'min': mn.tolist(), 'max': mx.tolist(), 'centre': centre.tolist(), 'radius': radius,
            'verts': int(len(P)), 'tris': int(len(I))}


def write_ytd(model, name, diffuse, specular, outdir):
    root = ET.Element('TextureDictionary')
    tex_item(root, model + '_d', 'DIFFUSE')
    tex_item(root, model + '_s', 'SPECULAR')
    folder = os.path.join(outdir, name)
    save_dds(diffuse, os.path.join(folder, model + '_d.dds'), 'DXT1')
    save_dds(specular, os.path.join(folder, model + '_s.dds'), 'DXT5', size=256)
    ET.ElementTree(root).write(os.path.join(outdir, name + '.ytd.xml'), encoding='UTF-8', xml_declaration=True)


def build(key, work):
    item = CATALOG[key]
    for model, group in item['models'].items():
        out = os.path.join(work, model)
        os.makedirs(out, exist_ok=True)
        mesh = DESIGNS[item['design']]()
        mesh.transform(M.rot_z(180))      # designs face -Y, GTA props face +Y
        bounds = write_ydr(model, mesh, out)
        json.dump(bounds, open(os.path.join(out, 'bounds.json'), 'w'))
        normal_done = False
        for i, (label, spec) in enumerate(group, 1):
            name = model if i == 1 else f'{model}_{i}'
            if 'style' in spec:   # backpack layout; one seed per model so every colour shares the relief
                dif, nrm, spc = PT.pack_atlas(spec, seed=zlib.crc32(model.encode()) & 0xffff)
            else:
                dif, nrm, spc = T.atlas(spec, seed=zlib.crc32(label.encode()) & 0xffff)
            if not normal_done:   # every colour of one model shares its relief
                save_dds(nrm, os.path.join(out, model, model + '_n.dds'), 'DXT1')
                normal_done = True
            write_ytd(model, name, dif, spc, os.path.join(out, f't{i}'))
        print(f'{model}: {bounds["verts"]} verts, {bounds["tris"]} tris, {len(group)} colours')


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
