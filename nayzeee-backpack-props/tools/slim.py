#!/usr/bin/env python3
"""
Slim a prop (.ydr exported to CodeWalker XML) before it's copied per colour:

  python3 slim.py <model.ydr.xml> <out.ydr.xml> [--max-tris=N] [--max-tex=512]

  * drops embedded textures no shader uses
  * shrinks embedded textures bigger than --max-tex (with mips)
  * if the model has more than --max-tris triangles, simplifies the dense
    parts by merging vertices that sit within a few millimetres of each other
    (never across a UV seam), growing the merge distance until it fits

Writes the XML next to a texture folder named like it, ready for
`bagconv import <out.ydr.xml> ydr <file.ydr> <texture folder>`.
"""
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def parse_rows(text, layout):
    rows = [r for r in text.strip().split('\n') if r.strip()]
    cols = [[] for _ in layout]
    for r in rows:
        parts = r.strip().split('   ')
        for i, p in enumerate(parts):
            cols[i].append([float(v) for v in p.split()])
    return [np.array(c, float) for c in cols]


def fmt(v, comp):
    if comp.startswith('Colour') or comp.startswith('Blend'):
        return ' '.join(str(int(round(x))) for x in v)
    return ' '.join(f'{x:.6f}'.rstrip('0').rstrip('.') if x != 0 else '0' for x in v)


def cluster(cols, layout, idx, cell, uvcell=0.002):
    """Merge vertices into cells of `cell` metres, keeping UV islands apart."""
    P = cols[layout.index('Position')]
    keys = [np.floor(P / cell).astype(np.int64)]
    if 'TexCoord0' in layout:
        keys.append(np.floor(cols[layout.index('TexCoord0')] / max(uvcell, cell * 2)).astype(np.int64))
    key = np.concatenate(keys, axis=1)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    n = inv.max() + 1
    out = []
    counts = np.bincount(inv, minlength=n)[:, None]
    for c, comp in zip(cols, layout):
        acc = np.zeros((n, c.shape[1]))
        np.add.at(acc, inv, c)
        avg = acc / counts
        if comp == 'Normal':
            avg /= np.linalg.norm(avg, axis=1, keepdims=True) + 1e-9
        if comp == 'Tangent':
            t = avg[:, :3] / (np.linalg.norm(avg[:, :3], axis=1, keepdims=True) + 1e-9)
            first = np.zeros(n, int); first[inv[::-1]] = np.arange(len(inv))[::-1]
            avg = np.concatenate([t, np.sign(c[first, 3:4]) + (c[first, 3:4] == 0)], axis=1)
        out.append(avg)
    tri = inv[idx.reshape(-1, 3)]
    keep = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
    tri = tri[keep]
    _, first = np.unique(np.sort(tri, axis=1), axis=0, return_index=True)   # drop doubled triangles
    tri = tri[np.sort(first)]
    used = np.unique(tri)
    remap = -np.ones(n, int); remap[used] = np.arange(len(used))
    return [o[used] for o in out], remap[tri]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    max_tris = next((int(a.split('=')[1]) for a in sys.argv if a.startswith('--max-tris=')), 0)
    max_tex = next((int(a.split('=')[1]) for a in sys.argv if a.startswith('--max-tex=')), 512)
    tree = ET.parse(src)
    root = tree.getroot()
    srcdir = os.path.splitext(os.path.splitext(src)[0])[0]
    dstdir = os.path.splitext(os.path.splitext(dst)[0])[0]
    os.makedirs(dstdir, exist_ok=True)

    # textures: keep what a shader uses, at most max_tex
    used = {p.findtext('Name') for p in root.iter('Item') if p.get('type') == 'Texture'}
    td = root.find('ShaderGroup/TextureDictionary')
    if td is not None:
        for it in list(td.findall('Item')):
            name, fn = it.findtext('Name'), it.findtext('FileName')
            if name not in used:
                td.remove(it)
                print('  drop texture', name)
                continue
            w = int(it.find('Width').get('value'))
            if w > max_tex:
                subprocess.run([sys.executable, os.path.join(HERE, 'shrink.py'), os.path.join(srcdir, fn),
                                os.path.join(dstdir, fn), str(max_tex)], check=True, stdout=subprocess.DEVNULL)
                print(f'  shrink {name} {w} -> {max_tex}')
            else:
                shutil.copy(os.path.join(srcdir, fn), os.path.join(dstdir, fn))

    # geometry
    geos = []
    for tag in ('DrawableModelsHigh', 'DrawableModelsMedium', 'DrawableModelsLow', 'DrawableModelsVeryLow'):
        for m in root.findall(f'{tag}/Item'):
            for g in m.findall('Geometries/Item'):
                geos.append((tag, g))
    total = sum(len((g.findtext('IndexBuffer/Data') or '').split()) // 3 for t, g in geos if t == 'DrawableModelsHigh')
    print(f'  {total} triangles')
    if max_tris and total > max_tris:
        parsed = []
        for tag, g in geos:
            vb = g.find('VertexBuffer')
            layout = [c.tag for c in vb.find('Layout')]
            dn = vb.find('Data') if (vb.findtext('Data') or '').strip() else vb.find('Data2')
            cols = parse_rows(dn.text, layout)
            idx = np.array(g.findtext('IndexBuffer/Data').split(), int)
            parsed.append((tag, g, vb, dn, layout, cols, idx))
        cell = 0.0015
        while True:
            results = [cluster(cols, layout, idx, cell) for (_, _, _, _, layout, cols, idx) in parsed]
            n = sum(len(r[1]) for r, p in zip(results, parsed) if p[0] == 'DrawableModelsHigh')
            print(f'  merge {cell * 1000:.1f} mm -> {n} triangles')
            if n <= max_tris or cell > 0.02:
                break
            cell *= 1.3
        for (tag, g, vb, dn, layout, cols, idx), (newcols, tris) in zip(parsed, results):
            rows = ['   '.join(fmt(c[i], comp) for c, comp in zip(newcols, layout)) for i in range(len(newcols[0]))]
            dn.text = '\n' + '\n'.join(rows) + '\n'
            flat = [str(v) for v in tris.reshape(-1)]
            g.find('IndexBuffer/Data').text = '\n' + '\n'.join(' '.join(flat[i:i + 24]) for i in range(0, len(flat), 24)) + '\n'
            P = newcols[layout.index('Position')]
            for k, v in (('BoundingBoxMin', P.min(0)), ('BoundingBoxMax', P.max(0))):
                e = g.find(k)
                if e is not None:
                    e.set('x', f'{v[0]:.6f}'); e.set('y', f'{v[1]:.6f}'); e.set('z', f'{v[2]:.6f}')
    tree.write(dst, encoding='UTF-8', xml_declaration=True)


if __name__ == '__main__':
    main()
