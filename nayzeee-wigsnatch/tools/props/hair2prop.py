"""Turns a freemode hair drawable (CodeWalker .ydd.xml + its diffuse .dds) into a prop for the wig head.

    python hair2prop.py <hair.ydd.xml> <diffuse.dds> <prop_name> <out_dir> [--tex 512] [--tint r,g,b]

- reads every geometry of the high LOD, whatever the vertex layout (skinned or not)
- drops skinning, keeps position / normal / uv, moves everything so the SKEL_Head bone is the origin
  (the foam head's `point`), facing +Y like the ped
- bakes the diffuse into a DXT5 texture (power-of-two size), optionally tinted
- writes <prop>.ydr.xml + <prop>_d.dds, and nzw_hair.ytyp.xml listing every prop in the folder,
  ready for cwtool xml2ydr / xml2ytyp
"""
import argparse
import math
import os
import re
import sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mesh import Part, merge, ydr_xml, archetype_xml, write_dds, render  # noqa: E402

SIZES = {'Position': 3, 'BlendWeights': 4, 'BlendIndices': 4, 'Normal': 3, 'Colour0': 4, 'Colour1': 4, 'Tangent': 4}
for i in range(8):
    SIZES['TexCoord%d' % i] = 2


def qmat(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def head_bone(xml):
    """SKEL_Head in model space, from the drawable's skeleton (falls back to the freemode default)."""
    if '<Skeleton>' not in xml:
        return np.array([0.0, 0.003, 0.642])
    sk = xml[xml.index('<Skeleton>'):xml.index('</Skeleton>')]
    bones = {}
    for name, body in re.findall(r'<Item>\s*<Name>(.*?)</Name>(.*?)</Item>', sk, re.S):
        def attrs(tag):
            m = re.search(r'<%s ([^/]*)/>' % tag, body)
            return dict(re.findall(r'(\w+)="([^"]*)"', m.group(1))) if m else {}
        idx = int(attrs('Index').get('value', -1))
        t, r = attrs('Translation'), attrs('Rotation')
        bones[idx] = dict(name=name, par=int(attrs('ParentIndex').get('value', -1)),
                          t=np.array([float(t.get(k, 0)) for k in 'xyz']),
                          q=np.array([float(r.get(k, 0)) for k in 'xyzw']) if r else np.array([0, 0, 0, 1.0]))
    cache = {}

    def world(i):
        if i in cache:
            return cache[i]
        b = bones[i]
        R = qmat(b['q'])
        if b['par'] < 0:
            M = (R, b['t'])
        else:
            PR, PT = world(b['par'])
            M = (PR @ R, PR @ b['t'] + PT)
        cache[i] = M
        return M
    for i, b in bones.items():
        if b['name'] == 'SKEL_Head':
            return world(i)[1]
    return np.array([0.0, 0.003, 0.642])


def geometries(xml):
    """High LOD geometries as Parts (positions in model space)."""
    hi = xml[xml.index('<DrawableModelsHigh>'):xml.index('</DrawableModelsHigh>')]
    parts = []
    for g in re.findall(r'<VertexBuffer>(.*?)</VertexBuffer>\s*<IndexBuffer>\s*<Data>(.*?)</Data>', hi, re.S):
        vb, ib = g
        layout = re.findall(r'<(\w+) />', vb[vb.index('<Layout'):vb.index('</Layout>')])
        off, cols = {}, 0
        for sem in layout:
            off[sem] = cols
            cols += SIZES.get(sem, 0)
        data = np.array([[float(v) for v in l.split()] for l in re.search(r'<Data>(.*?)</Data>', vb, re.S).group(1).strip().split('\n')])
        assert data.shape[1] == cols, (data.shape, cols, layout)
        P = data[:, off['Position']:off['Position'] + 3]
        N = data[:, off['Normal']:off['Normal'] + 3] if 'Normal' in off else np.tile([0, 0, 1.0], (len(P), 1))
        UV = data[:, off['TexCoord0']:off['TexCoord0'] + 2]
        T = np.array(ib.split(), dtype=np.int64).reshape(-1, 3)
        parts.append(Part(P, N, UV, T))
    return parts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ydd_xml'); ap.add_argument('diffuse'); ap.add_argument('name'); ap.add_argument('out')
    ap.add_argument('--tex', type=int, default=512)
    ap.add_argument('--tint', default=None)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    xml = open(a.ydd_xml, encoding='utf-8').read()
    hb = head_bone(xml)
    parts = [p.transformed(t=-hb) for p in geometries(xml)]

    tex = Image.open(a.diffuse).convert('RGBA')
    side = lambda v: 1 << max(5, min(int(math.log2(a.tex)), round(math.log2(max(4, v)))))
    tex = tex.resize((side(tex.width), side(tex.height)), Image.LANCZOS)
    if a.tint:
        tint = np.array([float(v) for v in a.tint.split(',')]) / 255.0
        arr = np.asarray(tex, dtype=np.float64)
        lum = arr[..., :3].mean(axis=2, keepdims=True) / 255.0
        arr[..., :3] = np.clip(lum * tint * 255 * 1.6, 0, 255)
        tex = Image.fromarray(arr.astype(np.uint8), 'RGBA')

    tex_name = a.name + '_d'
    mips = write_dds(tex, os.path.join(a.out, tex_name + '.dds'))
    with open(os.path.join(a.out, a.name + '.ydr.xml'), 'w') as fh:
        fh.write(ydr_xml(a.name, parts, tex_name, tex.width, tex.height, mips))
    whole = merge(parts)
    with open(os.path.join(a.out, a.name + '.archetype.xml'), 'w') as fh:
        fh.write(archetype_xml(a.name, whole, 40.0))
    tex.save(os.path.join(a.out, tex_name + '.png'))
    # one .ytyp for every hair prop converted into this folder
    from mesh import ytyp_xml
    items = [open(os.path.join(a.out, f), encoding='utf-8').read() for f in sorted(os.listdir(a.out)) if f.endswith('.archetype.xml')]
    with open(os.path.join(a.out, 'nzw_hair.ytyp.xml'), 'w') as fh:
        fh.write(ytyp_xml('nzw_hair', items))
    print('%s: %d geometries, %d verts, %d tris, head bone %s, size %s' % (
        a.name, len(parts), len(whole.P), len(whole.T), np.round(hb, 3), np.round(whole.P.max(0) - whole.P.min(0), 3)))


if __name__ == '__main__':
    main()
