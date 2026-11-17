"""
nayzeee-garages - original key fob prop generator for Blender 4.2+ (also runs with the `bpy` module).

Builds one low-poly key fob per design used by the key ring art (generic, sport, luxury, classic,
leather, compact, slim, card, retro) plus a plain metal car key. Every prop is one mesh object in
its own collection, sized like the real thing (body 5-9 cm), with one material per part
(body, trim, buttons, panic button, badge, metal).

Axes and origin (all props): origin = grip point = centre of the fob body (for the car key, the
centre of the key head). +Y = the key ring end, -Y = the bottom / key blade tip, +Z = the button face.

Run:
    blender --background --python tools/fobprops/make_fobs.py -- --out install/fobprops [--preview out.png]
    python make_fobs.py -- --out install/fobprops          (pip `bpy` module, Python 3.11)

Writes nz_keyfobs.blend and one GLB per prop. tools/fobprops/export_gta.py turns the .blend into
GTA V assets with the Sollumz add-on - see install/fobprops/README.md.
"""
import math
import os
import sys

import bpy
import bmesh

# ----------------------------------------------------------------------------------------------
# colours (linear) / materials
# ----------------------------------------------------------------------------------------------
MATS = {
    # name: (base colour, metallic, roughness, emissive)
    'black_gloss': ((0.018, 0.018, 0.020), 0.0, 0.25, False),
    'black_matte': ((0.022, 0.022, 0.024), 0.0, 0.70, False),
    'graphite':    ((0.045, 0.047, 0.052), 0.2, 0.40, False),
    'bronze_dark': ((0.050, 0.036, 0.026), 0.4, 0.30, False),
    'leather':     ((0.150, 0.060, 0.022), 0.0, 0.85, False),
    'stitch':      ((0.620, 0.470, 0.280), 0.0, 0.80, False),
    'cream':       ((0.700, 0.640, 0.520), 0.0, 0.45, False),
    'card_white':  ((0.780, 0.790, 0.800), 0.1, 0.30, False),
    'rubber':      ((0.050, 0.050, 0.055), 0.0, 0.80, False),
    'button_grey': ((0.150, 0.155, 0.165), 0.0, 0.55, False),
    'silver':      ((0.600, 0.610, 0.630), 1.0, 0.25, False),
    'chrome':      ((0.800, 0.800, 0.820), 1.0, 0.12, False),
    'gold':        ((0.800, 0.560, 0.200), 1.0, 0.25, False),
    'teal':        ((0.010, 0.450, 0.400), 0.3, 0.35, False),
    'red_trim':    ((0.450, 0.020, 0.020), 0.2, 0.40, False),
    'panic':       ((0.800, 0.030, 0.020), 0.0, 0.45, True),
    'led':         ((0.020, 0.400, 1.000), 0.0, 0.30, True),
}


def material(name):
    col, metallic, rough, emissive = MATS[name]
    mat = bpy.data.materials.get(f'nz_fob_{name}')
    if mat:
        return mat
    mat = bpy.data.materials.new(f'nz_fob_{name}')
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*col, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough
    if emissive:
        bsdf.inputs['Emission Color'].default_value = (*col, 1.0)
        bsdf.inputs['Emission Strength'].default_value = 2.0
    mat.diffuse_color = (*col, 1.0)
    mat['nz_emissive'] = emissive
    return mat


# ----------------------------------------------------------------------------------------------
# 2D outlines (counter-clockwise, centred on the origin)
# ----------------------------------------------------------------------------------------------
def rrect(w, l, r, seg=5, cx=0.0, cy=0.0):
    hw, hl = w / 2, l / 2
    r = min(r, hw, hl)
    pts = []
    for ccx, ccy, start in ((hw - r, hl - r, 0), (-hw + r, hl - r, 90), (-hw + r, -hl + r, 180), (hw - r, -hl + r, 270)):
        for i in range(seg + 1):
            a = math.radians(start + 90 * i / seg)
            pts.append((cx + ccx + r * math.cos(a), cy + ccy + r * math.sin(a)))
    return dedupe(pts)


def squircle(w, l, p=4.0, n=36):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        pts.append((w / 2 * math.copysign(abs(c) ** (2 / p), c), l / 2 * math.copysign(abs(s) ** (2 / p), s)))
    return pts


def circle(r, n=12, cx=0.0, cy=0.0):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def taper(pts, l, top=0.22, bottom=0.0):
    """Narrow the outline towards +Y (top) and/or -Y (bottom): a wedge / teardrop look."""
    hl = l / 2
    out = []
    for x, y in pts:
        t = y / hl
        k = 1 - top * max(t, 0) ** 1.5 - bottom * max(-t, 0) ** 1.5
        out.append((x * k, y))
    return out


def dedupe(pts, eps=1e-7):
    out = []
    for p in pts:
        if not out or math.dist(p, out[-1]) > eps:
            out.append(p)
    if math.dist(out[0], out[-1]) <= eps:
        out.pop()
    return out


def offset(pts, d):
    """Offset a convex CCW outline outward by d (negative = inset), mitred."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e1 = (p1[0] - p0[0], p1[1] - p0[1])
        e2 = (p2[0] - p1[0], p2[1] - p1[1])
        n1 = norm2((e1[1], -e1[0]))
        n2 = norm2((e2[1], -e2[0]))
        m = norm2((n1[0] + n2[0], n1[1] + n2[1]))
        cos_h = max(m[0] * n1[0] + m[1] * n1[1], 0.3)
        out.append((p1[0] + m[0] * d / cos_h, p1[1] + m[1] * d / cos_h))
    return out


def norm2(v):
    ln = math.hypot(*v) or 1.0
    return (v[0] / ln, v[1] / ln)


# ----------------------------------------------------------------------------------------------
# mesh builders (all add into one bmesh, with a material index per part)
# ----------------------------------------------------------------------------------------------
class Builder:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.sharp = set()

    def mi(self, mat_name):
        mat = material(mat_name)
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def ring(self, pts, z):
        return [self.bm.verts.new((x, y, z)) for x, y in pts]

    def bridge(self, a, b, mi):
        """Quads between two vertex rings of the same size (a below / outside b)."""
        n = len(a)
        faces = []
        for i in range(n):
            j = (i + 1) % n
            f = self.bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
            faces.append(f)
        return faces

    def cap(self, ring, mi, up=True):
        f = self.bm.faces.new(ring if up else list(reversed(ring)))
        f.material_index = mi
        for e in f.edges:
            self.sharp.add(e)
        return f

    def slab(self, pts, z0, z1, mat, rtop=0.0, rbot=0.0, seg=3, bottom_cap=True):
        """Extrude a convex outline from z0 to z1 with quarter-round edges of radius rtop / rbot."""
        mi = self.mi(mat)
        rings = []
        if rbot > 0:
            for k in range(seg + 1):
                a = math.radians(90 * k / seg)
                rings.append(self.ring(offset(pts, -rbot * (1 - math.sin(a))), z0 + rbot * (1 - math.cos(a))))
        else:
            rings.append(self.ring(pts, z0))
        if rtop > 0:
            for k in range(seg, -1, -1):
                a = math.radians(90 * k / seg)
                rings.append(self.ring(offset(pts, -rtop * (1 - math.sin(a))), z1 - rtop * (1 - math.cos(a))))
        else:
            rings.append(self.ring(pts, z1))
        for a, b in zip(rings, rings[1:]):
            faces = self.bridge(a, b, mi)
            if rbot == 0 and a is rings[0] or rtop == 0 and b is rings[-1]:
                for f in faces:
                    for e in f.edges:
                        if e.verts[0].co.z == e.verts[1].co.z:
                            self.sharp.add(e)
        if bottom_cap:
            self.cap(rings[0], mi, up=False)
        self.cap(rings[-1], mi, up=True)

    def band(self, pts, zc, h, out, mat):
        """A trim band around an outline: outer wall + top / bottom lips, buried into the body."""
        mi = self.mi(mat)
        inner, outer = offset(pts, -0.0015), offset(pts, out)
        r = [self.ring(inner, zc - h / 2), self.ring(outer, zc - h / 2), self.ring(outer, zc + h / 2), self.ring(inner, zc + h / 2)]
        for a, b in zip(r, r[1:]):
            for f in self.bridge(a, b, mi):
                for e in f.edges:
                    if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-9 and e.verts[0] in r[1] + r[2]:
                        self.sharp.add(e)

    def inlay_ring(self, pts, inset, width, z, height, mat):
        """A thin raised outline ring on a flat face (stitching / frame line)."""
        mi = self.mi(mat)
        o, i = offset(pts, -inset), offset(pts, -inset - width)
        r = [self.ring(o, z - 0.0003), self.ring(o, z + height), self.ring(i, z + height), self.ring(i, z - 0.0003)]
        for a, b in zip(r, r[1:]):
            self.bridge(a, b, mi)

    def torus(self, center, R, r, nmaj, nmin, mat, plane='XY'):
        mi = self.mi(mat)
        cx, cy, cz = center
        rings = []
        for i in range(nmaj):
            a = 2 * math.pi * i / nmaj
            ring = []
            for j in range(nmin):
                b = 2 * math.pi * j / nmin
                u, v, w = (R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)
                if plane == 'XY':
                    co = (cx + u, cy + v, cz + w)
                else:  # YZ plane: hole axis along X
                    co = (cx + w, cy + u, cz + v)
                ring.append(self.bm.verts.new(co))
            rings.append(ring)
        for i in range(nmaj):
            a, b = rings[i], rings[(i + 1) % nmaj]
            for j in range(nmin):
                k = (j + 1) % nmin
                f = self.bm.faces.new((a[j], b[j], b[k], a[k]) if plane == 'XY' else (a[j], a[k], b[k], b[j]))
                f.material_index = mi

    def key_ring(self, top_y, R=0.0085, mat='chrome', eyelet=True):
        """Metal eyelet at the top of the body (hole along X) and a split ring through it."""
        if eyelet:
            self.torus((0, top_y + 0.0004, 0), 0.0028, 0.0010, 10, 5, mat, plane='YZ')
        self.torus((0, top_y + 0.0016 + R, 0), R, 0.0009, 18, 6, mat)

    def finish(self, coll):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            sharp = (not e.is_valid) or e.calc_face_angle(0.0) > math.radians(48)
            e.smooth = not sharp
        for e in self.sharp:
            if e.is_valid:
                e.smooth = False
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        mesh.uv_layers.new(name='UVMap')
        obj = bpy.data.objects.new(self.name, mesh)
        coll.objects.link(obj)
        return obj


# ----------------------------------------------------------------------------------------------
# designs
# ----------------------------------------------------------------------------------------------
def buttons_column(b, top_z, ys, r, mats, kind='round', bw=0.0, bh=0.0):
    for y, mat in zip(ys, mats):
        pts = circle(r, 14, 0, y) if kind == 'round' else rrect(bw, bh, min(bw, bh) * 0.35, 3, 0, y)
        b.slab(pts, top_z - 0.0004, top_z + 0.0013, mat, rtop=0.0007, seg=2, bottom_cap=False)


def fob_generic(b):
    w, l, t = 0.034, 0.066, 0.013
    pts = rrect(w, l, 0.011, 5)
    b.slab(pts, -t / 2, t / 2, 'black_gloss', rtop=0.0035, rbot=0.0035)
    b.band(pts, 0, 0.0022, 0.0004, 'silver')
    buttons_column(b, t / 2, (0.010, -0.002, -0.014, -0.025), 0.0047,
                   ('button_grey', 'button_grey', 'button_grey', 'panic'))
    b.slab(circle(0.0045, 16, 0, 0.023), t / 2 - 0.0003, t / 2 + 0.0005, 'silver', bottom_cap=False)
    b.key_ring(l / 2)


def fob_sport(b):
    w, l, t = 0.033, 0.070, 0.012
    pts = taper(rrect(w, l, 0.009, 5), l, top=0.30, bottom=0.05)
    b.slab(pts, -t / 2, t / 2, 'black_matte', rtop=0.003, rbot=0.003)
    b.band(pts, 0.0015, 0.0018, 0.0005, 'teal')
    buttons_column(b, t / 2, (0.006, -0.005, -0.016), 0.0045, ('button_grey',) * 3)
    b.slab(rrect(0.012, 0.007, 0.0025, 3, 0, -0.027), t / 2 - 0.0004, t / 2 + 0.0013, 'panic', rtop=0.0007, seg=2,
           bottom_cap=False)
    b.slab([(x, y + 0.021) for x, y in squircle(0.011, 0.006, 3, 16)], t / 2 - 0.0003, t / 2 + 0.0005, 'teal',
           bottom_cap=False)
    b.key_ring(l / 2)


def fob_luxury(b):
    w, l, t = 0.037, 0.072, 0.014
    pts = squircle(w, l, 3.2, 30)
    b.slab(pts, -t / 2, t / 2, 'bronze_dark', rtop=0.004, rbot=0.004)
    b.band(pts, 0, 0.0030, 0.0005, 'chrome')
    panel = squircle(w - 0.012, l - 0.016, 3.2, 26)
    b.slab(panel, t / 2 - 0.0003, t / 2 + 0.0006, 'black_gloss', rtop=0.0003, seg=1, bottom_cap=False)
    top = t / 2 + 0.0006
    for y, mat in ((0.009, 'chrome'), (-0.002, 'chrome'), (-0.013, 'chrome'), (-0.024, 'panic')):
        b.slab(circle(0.0036, 14, 0, y), top - 0.0003, top + 0.0007, mat, rtop=0.0004, seg=1, bottom_cap=False)
    b.slab(circle(0.0042, 16, 0, 0.022), top - 0.0003, top + 0.0004, 'gold', bottom_cap=False)
    b.key_ring(l / 2, mat='chrome')


def fob_classic(b):
    w, l, t = 0.031, 0.060, 0.015
    pts = rrect(w, l, 0.005, 3)
    b.slab(pts, -t / 2, t / 2, 'graphite', rtop=0.0022, rbot=0.0022, seg=2)
    b.band(pts, -0.002, 0.0035, 0.0004, 'button_grey')
    buttons_column(b, t / 2, (0.008, -0.006, -0.020), 0, ('rubber', 'rubber', 'panic'), kind='rect',
                   bw=0.019, bh=0.0105)
    b.slab(rrect(0.012, 0.004, 0.0015, 2, 0, 0.022), t / 2 - 0.0003, t / 2 + 0.0004, 'silver', bottom_cap=False)
    b.key_ring(l / 2, mat='silver')


def fob_leather(b):
    w, l, t = 0.036, 0.068, 0.016
    pts = rrect(w, l, 0.012, 5)
    b.slab(pts, -t / 2, t / 2, 'leather', rtop=0.005, rbot=0.005)
    b.inlay_ring(pts, 0.0062, 0.0007, t / 2, 0.0002, 'stitch')
    buttons_column(b, t / 2, (0.007, -0.0055, -0.018), 0.0052, ('leather', 'leather', 'panic'))
    # leather strap tab with the ring through it
    tab = rrect(0.014, 0.020, 0.006, 4, 0, l / 2 + 0.004)
    b.slab(tab, -0.0018, 0.0018, 'leather', rtop=0.0008, rbot=0.0008, seg=1)
    b.key_ring(l / 2 + 0.011, mat='silver', eyelet=False)


def fob_compact(b):
    w, l, t = 0.028, 0.050, 0.011
    pts = squircle(w, l, 4.0, 32)
    b.slab(pts, -t / 2, t / 2, 'black_gloss', rtop=0.003, rbot=0.003)
    b.band(pts, 0, 0.0016, 0.0004, 'silver')
    buttons_column(b, t / 2, (0.006, -0.0045, -0.015), 0.0042, ('button_grey', 'button_grey', 'panic'))
    b.slab(circle(0.0010, 8, 0.0085, 0.016), t / 2 - 0.0002, t / 2 + 0.0004, 'led', bottom_cap=False)
    b.key_ring(l / 2, R=0.0075)


def fob_slim(b):
    w, l, t = 0.029, 0.074, 0.009
    pts = rrect(w, l, 0.007, 4)
    b.slab(pts, -t / 2, t / 2, 'graphite', rtop=0.0025, rbot=0.0025)
    b.band(pts, 0, 0.0014, 0.0004, 'chrome')
    buttons_column(b, t / 2, (0.012, 0.001, -0.010), 0, ('black_gloss',) * 3, kind='rect', bw=0.016, bh=0.008)
    buttons_column(b, t / 2, (-0.022,), 0, ('panic',), kind='rect', bw=0.016, bh=0.008)
    b.slab(rrect(0.010, 0.0025, 0.001, 2, 0, 0.027), t / 2 - 0.0003, t / 2 + 0.0004, 'chrome', bottom_cap=False)
    b.key_ring(l / 2, R=0.008)


def fob_card(b):
    w, l, t = 0.054, 0.086, 0.0035  # credit-card sized key card
    pts = rrect(w, l, 0.004, 3)
    b.slab(pts, -t / 2, t / 2, 'card_white', rtop=0.0008, rbot=0.0008, seg=1)
    b.slab(rrect(w - 0.004, 0.016, 0.002, 2, 0, 0.030), t / 2 - 0.0002, t / 2 + 0.0002, 'black_gloss',
           bottom_cap=False)
    b.slab(rrect(0.011, 0.009, 0.0015, 2, -0.014, -0.010), t / 2 - 0.0002, t / 2 + 0.0003, 'gold', bottom_cap=False)
    b.slab(circle(0.0045, 16, 0.012, -0.028), t / 2 - 0.0002, t / 2 + 0.0004, 'silver', bottom_cap=False)
    b.slab(circle(0.0010, 8, 0.020, 0.030), t / 2 + 0.0001, t / 2 + 0.0004, 'led', bottom_cap=False)


def fob_retro(b):
    w, l, t = 0.038, 0.056, 0.018
    pts = rrect(w, l, 0.004, 3)
    b.slab(pts, -t / 2, t / 2, 'cream', rtop=0.002, rbot=0.002, seg=2)
    b.band(pts, -0.003, 0.0040, 0.0005, 'chrome')
    for x, mat in ((-0.0085, 'rubber'), (0.0085, 'rubber')):
        b.slab(rrect(0.014, 0.018, 0.003, 3, x, 0.002), t / 2 - 0.0004, t / 2 + 0.0018, mat, rtop=0.0008, seg=2,
               bottom_cap=False)
    b.slab(circle(0.0035, 14, 0, -0.018), t / 2 - 0.0004, t / 2 + 0.0012, 'panic', rtop=0.0005, seg=1,
           bottom_cap=False)
    b.slab(circle(0.0012, 8, 0.013, 0.021), t / 2 - 0.0002, t / 2 + 0.0004, 'red_trim', bottom_cap=False)
    b.key_ring(l / 2, R=0.0095, mat='chrome')


def car_key(b):
    hw, hl, t = 0.024, 0.026, 0.009
    head = rrect(hw, hl, 0.008, 4)
    b.slab(head, -t / 2, t / 2, 'rubber', rtop=0.0025, rbot=0.0025, seg=2)
    b.slab(rrect(0.010, 0.004, 0.0015, 2, 0, 0.003), t / 2 - 0.0003, t / 2 + 0.0004, 'silver', bottom_cap=False)
    # collar between the head and the blade
    b.slab(rrect(0.012, 0.005, 0.0015, 2, 0, -hl / 2 - 0.0015), -0.0025, 0.0025, 'silver', rtop=0.0005,
           rbot=0.0005, seg=1)
    # blade: a notched profile, 2 mm thick
    y0, y1 = -hl / 2 - 0.003, -hl / 2 - 0.042
    prof = [(-0.004, y0), (0.004, y0)]
    teeth = [(0.004, -0.024), (0.0022, -0.027), (0.004, -0.030), (0.0018, -0.034), (0.004, -0.037),
             (0.0025, -0.041), (0.004, -0.044), (0.004, -0.050)]
    prof += teeth + [(0.0005, y1), (-0.004, y1 + 0.004)]
    b.slab(list(reversed(prof)), -0.001, 0.001, 'silver')  # CCW
    b.key_ring(hl / 2, R=0.0085, mat='chrome')


DESIGNS = {
    'nz_keyfob_generic': fob_generic,
    'nz_keyfob_sport': fob_sport,
    'nz_keyfob_luxury': fob_luxury,
    'nz_keyfob_classic': fob_classic,
    'nz_keyfob_leather': fob_leather,
    'nz_keyfob_compact': fob_compact,
    'nz_keyfob_slim': fob_slim,
    'nz_keyfob_card': fob_card,
    'nz_keyfob_retro': fob_retro,
    'nz_carkey': car_key,
}


# ----------------------------------------------------------------------------------------------
def args():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out, preview = 'install/fobprops', None
    if '--out' in argv:
        out = argv[argv.index('--out') + 1]
    if '--preview' in argv:
        preview = os.path.abspath(argv[argv.index('--preview') + 1])
    return os.path.abspath(out), preview


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def render_preview(objs, path):
    """Cycles (CPU) preview: the props in a 5 x 2 grid, seen from above at an angle."""
    scene = bpy.context.scene
    spacing = 0.075
    for i, obj in enumerate(objs):
        obj.location = ((i % 5 - 2) * spacing, -(i // 5) * 0.115 + 0.055, 0)
        obj.rotation_euler = (0, 0, 0)
    cam_data = bpy.data.cameras.new('preview_cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 0.40
    cam = bpy.data.objects.new('preview_cam', cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.0, -0.20, 0.42)
    cam.rotation_euler = (math.radians(26), 0, 0)
    scene.camera = cam
    for name, rot, energy in (('key', (math.radians(40), math.radians(-25), 0), 4.0),
                              ('fill', (math.radians(55), math.radians(40), 0), 1.5)):
        ld = bpy.data.lights.new(name, 'SUN')
        ld.energy = energy
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = rot
        scene.collection.objects.link(lo)
    world = bpy.data.worlds.new('preview_world')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.35, 0.37, 0.40, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
    scene.world = world
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for obj in objs:
        obj.location = (0, 0, 0)
    for o in (cam, *[o for o in scene.collection.objects if o.type == 'LIGHT']):
        bpy.data.objects.remove(o)


def main():
    out, preview = args()
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = []
    for name, build in DESIGNS.items():
        coll = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(coll)
        b = Builder(name)
        build(b)
        obj = b.finish(coll)
        objs.append(obj)
        d = obj.dimensions
        print(f'{name:20s} {d.x * 100:5.1f} x {d.y * 100:5.1f} x {d.z * 100:4.1f} cm  {tri_count(obj):5d} tris')

    if preview:
        render_preview(objs, preview)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'nz_keyfobs.blend'), compress=True)
    for obj in objs:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, f'{obj.name}.glb'), use_selection=True,
                                  export_format='GLB', export_apply=True)
    print(f'nayzeee-garages: {len(objs)} key props written to {out}')


main()
