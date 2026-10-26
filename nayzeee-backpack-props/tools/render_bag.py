#!/usr/bin/env python3
"""
Software render of a converted prop (CodeWalker .ydr.xml) with its diffuse
texture, from three angles, to check geometry + UV mapping by eye.

  python3 render_bag.py <model.ydr.xml> <diffuse.dds> <out.png> [title]
"""
import math
import sys
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw

W = H = 360


def load(xml_path):
    d = ET.parse(xml_path).getroot()
    tris = []  # (p0,p1,p2,uv0,uv1,uv2,n0,n1,n2)
    lod = d.find('DrawableModelsHigh')
    for m in lod.findall('Item'):
        for g in m.find('Geometries').findall('Item'):
            vb = g.find('VertexBuffer')
            comps = [c.tag for c in vb.find('Layout')]
            dn = vb.find('Data') if vb.find('Data') is not None and (vb.find('Data').text or '').strip() else vb.find('Data2')
            rows = [r.strip().split('   ') for r in dn.text.strip().split('\n')]
            pi, ti, ni = comps.index('Position'), comps.index('TexCoord0'), comps.index('Normal')
            P = np.array([[float(v) for v in r[pi].split()] for r in rows])
            T = np.array([[float(v) for v in r[ti].split()] for r in rows])
            N = np.array([[float(v) for v in r[ni].split()] for r in rows])
            idx = np.array([int(v) for v in g.find('IndexBuffer').find('Data').text.split()]).reshape(-1, 3)
            tris.append((P, T, N, idx))
    return tris


def rot(yaw, pitch):
    y, p = math.radians(yaw), math.radians(pitch)
    Rz = np.array([[math.cos(y), -math.sin(y), 0], [math.sin(y), math.cos(y), 0], [0, 0, 1]])
    Rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    return Rx @ Rz


def render(tris, tex, yaw, pitch):
    img = np.zeros((H, W, 3), np.float32) + np.array([24, 27, 30], np.float32)
    zb = np.full((H, W), -np.inf, np.float32)
    allP = np.concatenate([t[0] for t in tris])
    c = (allP.min(0) + allP.max(0)) / 2
    ext = (allP.max(0) - allP.min(0)).max()
    R = rot(yaw, pitch)
    scale = W * 0.8 / ext
    th, tw = tex.shape[:2]
    light = np.array([0.4, -0.6, 0.7]); light /= np.linalg.norm(light)

    for P, T, N, idx in tris:
        V = (P - c) @ R.T          # view space: x right, y depth, z up
        Nv = N @ R.T
        sx = W / 2 + V[:, 0] * scale
        sy = H / 2 - V[:, 2] * scale
        depth = -V[:, 1]
        for a, b, cc in idx:
            xs = np.array([sx[a], sx[b], sx[cc]]); ys = np.array([sy[a], sy[b], sy[cc]])
            x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, W)
            y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, H)
            if x0 >= x1 or y0 >= y1:
                continue
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            w2 = 1 - w0 - w1
            m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not m.any():
                continue
            z = w0 * depth[a] + w1 * depth[b] + w2 * depth[cc]
            sub = zb[y0:y1, x0:x1]
            m &= z > sub
            if not m.any():
                continue
            u = w0 * T[a, 0] + w1 * T[b, 0] + w2 * T[cc, 0]
            v = w0 * T[a, 1] + w1 * T[b, 1] + w2 * T[cc, 1]
            tx = (np.mod(u, 1.0) * (tw - 1)).astype(int)
            ty = (np.mod(v, 1.0) * (th - 1)).astype(int)
            col = tex[ty, tx, :3].astype(np.float32)
            n = Nv[a] + Nv[b] + Nv[cc]
            n /= (np.linalg.norm(n) + 1e-9)
            shade = 0.35 + 0.65 * abs(float(n @ light))
            sub[m] = z[m]
            img[y0:y1, x0:x1][m] = col[m] * shade
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def main():
    xml_path, dds, out = sys.argv[1:4]
    title = sys.argv[4] if len(sys.argv) > 4 else ''
    tris = load(xml_path)
    tex = np.array(Image.open(dds).convert('RGBA'))
    if tex.shape[0] > 1024:
        tex = np.array(Image.fromarray(tex).resize((1024, 1024)))
    views = [render(tris, tex, yaw, pitch) for yaw, pitch in ((180, 8), (135, 12), (90, 6))]
    sheet = Image.new('RGB', (W * 3, H + 26), (14, 16, 17))
    for i, v in enumerate(views):
        sheet.paste(v, (i * W, 26))
    ImageDraw.Draw(sheet).text((10, 7), title, fill=(230, 235, 240))
    sheet.save(out)


if __name__ == '__main__':
    main()
