"""Tiny mesh kit for GTA props: lathes, lofts, boxes; CodeWalker XML out; DDS out; preview renders."""
import math
import struct
import io
import numpy as np
from PIL import Image


class Part:
    def __init__(self, P, N, UV, T):
        self.P = np.asarray(P, dtype=np.float64)
        self.N = np.asarray(N, dtype=np.float64)
        self.UV = np.asarray(UV, dtype=np.float64)
        self.T = np.asarray(T, dtype=np.int64).reshape(-1, 3)

    def transformed(self, R=None, t=(0, 0, 0), s=(1, 1, 1)):
        S = np.diag(s)
        R = np.eye(3) if R is None else np.asarray(R)
        P = (self.P @ S.T) @ R.T + np.asarray(t)
        # normals: inverse transpose of scale
        Ninv = np.diag([1.0 / v for v in s])
        N = (self.N @ Ninv.T) @ R.T
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        T = self.T.copy()
        if np.prod(s) < 0:
            T = T[:, ::-1]
        return Part(P, N, self.UV.copy(), T)

    def flipped(self, offset=0.0):
        return Part(self.P - self.N * offset, -self.N, self.UV.copy(), self.T[:, ::-1].copy())


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == 'x':
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == 'y':
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def merge(parts):
    P, N, UV, T, off = [], [], [], [], 0
    for p in parts:
        P.append(p.P); N.append(p.N); UV.append(p.UV); T.append(p.T + off)
        off += len(p.P)
    return Part(np.vstack(P), np.vstack(N), np.vstack(UV), np.vstack(T))


def _orient(P, T, N, center=None):
    """Make the winding agree with the outward direction (CCW seen from outside)."""
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    fn = np.cross(b - a, c - a)
    ctr = P.mean(axis=0) if center is None else np.asarray(center)
    out = ((a + b + c) / 3.0) - ctr
    if np.sum(np.einsum('ij,ij->i', fn, out)) < 0:
        T = T[:, ::-1].copy()
    return T


def surface(G, uv_rect, closed=True, vparams=None, uparams=None, outward=True, center=None, pole_axis=None):
    """G: (R, C, 3) grid of points (no duplicated seam column). Returns a smooth Part."""
    G = np.asarray(G, dtype=np.float64)
    R, C, _ = G.shape
    cols = C if closed else C - 1
    flatP = G.reshape(-1, 3)
    faces = []
    for r in range(R - 1):
        for c in range(cols):
            a = r * C + c
            b = r * C + (c + 1) % C
            d = (r + 1) * C + c
            e = (r + 1) * C + (c + 1) % C
            faces.append((a, b, e))
            faces.append((a, e, d))
    faces = np.array(faces, dtype=np.int64)
    if outward:
        faces = _orient(flatP, faces, None, center)
    # smooth normals (area weighted)
    a, b, c = flatP[faces[:, 0]], flatP[faces[:, 1]], flatP[faces[:, 2]]
    fn = np.cross(b - a, c - a)
    acc = np.zeros_like(flatP)
    for k in range(3):
        np.add.at(acc, faces[:, k], fn)
    # rings that collapse to a point: give them the average of the ring
    for r in range(R):
        ring = G[r]
        if np.max(np.linalg.norm(ring - ring.mean(axis=0), axis=1)) < 1e-7:
            avg = acc[r * C:(r + 1) * C].sum(axis=0)
            if pole_axis is not None and np.linalg.norm(avg) < 1e-12:
                avg = np.asarray(pole_axis, dtype=np.float64)
            acc[r * C:(r + 1) * C] = avg
    nrm = acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)

    # output with a duplicated seam column so UVs wrap cleanly
    OC = C + 1 if closed else C
    u0, v0, u1, v1 = uv_rect
    if vparams is None:
        vparams = np.linspace(0, 1, R)
    if uparams is None:
        uparams = np.linspace(0, 1, OC)
    P, N, UV = [], [], []
    for r in range(R):
        for c in range(OC):
            src = r * C + (c % C)
            P.append(flatP[src]); N.append(nrm[src])
            UV.append((u0 + uparams[c] * (u1 - u0), v0 + vparams[r] * (v1 - v0)))
    T = []
    # remap faces to output grid (seam faces use the duplicated column)
    for r in range(R - 1):
        for c in range(cols):
            a = r * OC + c
            b = r * OC + c + 1 if closed else r * OC + c + 1
            d = (r + 1) * OC + c
            e = (r + 1) * OC + c + 1
            T.append((a, b, e)); T.append((a, e, d))
    T = np.array(T, dtype=np.int64)
    # keep the same winding decision as the normals
    if outward:
        Pp = np.array(P)
        T = _orient(Pp, T, None, center)
    return Part(P, N, UV, T)


def lathe(profile, segs, uv_rect, scale=(1.0, 1.0), a0=0.0, a1=360.0, center_xy=(0.0, 0.0)):
    """profile: [(radius, z)], revolved around Z. Partial arcs are open sheets."""
    closed = abs((a1 - a0) - 360.0) < 1e-6
    n = segs if closed else segs + 1
    angs = [math.radians(a0 + (a1 - a0) * i / segs) for i in range(n)]
    G = []
    for r, z in profile:
        G.append([(center_xy[0] + r * math.cos(a) * scale[0], center_xy[1] + r * math.sin(a) * scale[1], z) for a in angs])
    # v along the profile by arc length
    L = [0.0]
    for i in range(1, len(profile)):
        L.append(L[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
    vp = np.array(L) / max(L[-1], 1e-9)
    zs = [z for _, z in profile]
    ctr = (center_xy[0], center_xy[1], (min(zs) + max(zs)) / 2)
    return surface(G, uv_rect, closed=closed, vparams=vp, center=ctr, pole_axis=(0, 0, 1))


def superellipse(t, a, b, n):
    c, s = math.cos(t), math.sin(t)
    x = a * math.copysign(abs(c) ** (2.0 / n), c)
    y = b * math.copysign(abs(s) ** (2.0 / n), s)
    return x, y


def loft_y(sections, segs, uv_rect, caps=None):
    """sections: [(y, half_width_x, half_height_z, n, cx, cz)] -> tube along Y with optional flat caps."""
    G = []
    for (y, hw, hh, n, cx, cz) in sections:
        ring = []
        for i in range(segs):
            t = 2 * math.pi * i / segs
            x, z = superellipse(t, max(hw, 1e-6), max(hh, 1e-6), n)
            ring.append((cx + x, y, cz + z))
        G.append(ring)
    L = [0.0]
    for i in range(1, len(sections)):
        L.append(L[-1] + abs(sections[i][0] - sections[i - 1][0]))
    vp = np.array(L) / max(L[-1], 1e-9)
    G = np.array(G)
    ctr = G.reshape(-1, 3).mean(axis=0)
    # a loft can bend: orient faces against each ring's own centre
    part = surface(G, uv_rect, closed=True, vparams=vp, center=ctr)
    parts = [part]
    if caps:
        for end, rect in caps:
            ring = G[0] if end == 0 else G[-1]
            c = ring.mean(axis=0)
            nrm = np.array([0, -1.0, 0]) if end == 0 else np.array([0, 1.0, 0])
            P = [c] + list(ring)
            N = [nrm] * len(P)
            u0, v0, u1, v1 = rect
            UV = [((u0 + u1) / 2, (v0 + v1) / 2)]
            xs = ring[:, 0]; zs = ring[:, 2]
            for p in ring:
                UV.append((u0 + (p[0] - xs.min()) / max(np.ptp(xs), 1e-9) * (u1 - u0), v0 + (p[2] - zs.min()) / max(np.ptp(zs), 1e-9) * (v1 - v0)))
            T = [(0, 1 + i, 1 + (i + 1) % segs) for i in range(segs)]
            T = np.array(T)
            a, b, cc = np.array(P)[T[:, 0]], np.array(P)[T[:, 1]], np.array(P)[T[:, 2]]
            if np.dot(np.cross(b - a, cc - a).sum(axis=0), nrm) < 0:
                T = T[:, ::-1]
            parts.append(Part(P, N, UV, T))
    return merge(parts)


def box(mn, mx, uv_rect, faces='all'):
    (x0, y0, z0), (x1, y1, z1) = mn, mx
    u0, v0, u1, v1 = uv_rect
    F = {
        '+x': ((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), (1, 0, 0)),
        '-x': ((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (-1, 0, 0)),
        '+y': ((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (0, 1, 0)),
        '-y': ((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0)),
        '+z': ((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1)),
        '-z': ((x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0), (0, 0, -1)),
    }
    P, N, UV, T = [], [], [], []
    for key, (a, b, c, d, n) in F.items():
        if faces != 'all' and key not in faces:
            continue
        base = len(P)
        P += [a, b, c, d]; N += [n] * 4
        UV += [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
        T += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return Part(P, N, UV, T)


# ----------------------------------------------------------------------------------------------
# CodeWalker XML

def f(v):
    s = ('%.6f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def ydr_xml(name, part, tex_name, tex_w, tex_h, mips, shader='default', bounds=True):
    parts = part if isinstance(part, (list, tuple)) else [part]
    P = np.vstack([p.P for p in parts])
    mn, mx = P.min(axis=0), P.max(axis=0)
    c = (mn + mx) / 2
    r = float(np.max(np.linalg.norm(P - c, axis=1)))
    size = mx - mn
    vol = float(np.prod(np.maximum(size, 0.001)))
    def geom_xml(gp):
        lines = []
        for i in range(len(gp.P)):
            p, n, uv = gp.P[i], gp.N[i], gp.UV[i]
            lines.append('       %s %s %s   %s %s %s   255 255 255 255   %s %s' % (
                f(p[0]), f(p[1]), f(p[2]), f(n[0]), f(n[1]), f(n[2]), f(uv[0]), f(uv[1])))
        idx = gp.T.reshape(-1)
        ilines = ['       ' + ' '.join(str(int(v)) for v in idx[i:i + 24]) for i in range(0, len(idx), 24)]
        gmn, gmx = gp.P.min(axis=0), gp.P.max(axis=0)
        return """    <Item>
     <ShaderIndex value="0" />
     %s
     %s
     <VertexBuffer>
      <Flags value="0" />
      <Layout type="GTAV1">
       <Position />
       <Normal />
       <Colour0 />
       <TexCoord0 />
      </Layout>
      <Data>
%s
      </Data>
     </VertexBuffer>
     <IndexBuffer>
      <Data>
%s
      </Data>
     </IndexBuffer>
    </Item>""" % (v3('BoundingBoxMin', gmn, True), v3('BoundingBoxMax', gmx, True), '\n'.join(lines), '\n'.join(ilines))

    def v3(tag, v, w=False):
        return '<%s x="%s" y="%s" z="%s"%s />' % (tag, f(v[0]), f(v[1]), f(v[2]), ' w="0"' if w else '')

    bnd = ''
    if bounds:
        common = '''  %s
  %s
  %s
  %s
  <SphereRadius value="%s" />
  <Margin value="0.005" />
  <Volume value="%s" />
  <Inertia x="%s" y="%s" z="%s" />
  <MaterialIndex value="0" />
  <MaterialColourIndex value="0" />
  <ProceduralID value="0" />
  <RoomID value="0" />
  <PedDensity value="0" />
  <UnkFlags value="0" />
  <PolyFlags value="0" />
  <UnkType value="1" />''' % (v3('BoxMin', mn), v3('BoxMax', mx), v3('BoxCenter', c), v3('SphereCenter', c), f(r), f(vol),
                               f((size[1] ** 2 + size[2] ** 2) / 12), f((size[0] ** 2 + size[2] ** 2) / 12), f((size[0] ** 2 + size[1] ** 2) / 12))
        child = common.replace('\n  ', '\n    ')
        bnd = ''' <Bounds type="Composite">
%s
  <Children>
   <Item type="Box">
  %s
    <CompositeTransform>
     1 0 0 0
     0 1 0 0
     0 0 1 0
     0 0 0 1
    </CompositeTransform>
    <CompositeFlags1>MAP_WEAPON, MAP_DYNAMIC, MAP_ANIMAL, MAP_COVER, MAP_VEHICLE</CompositeFlags1>
    <CompositeFlags2>VEHICLE_NOT_BVH, VEHICLE_BVH, PED, RAGDOLL, ANIMAL, ANIMAL_RAGDOLL, OBJECT, PLANT, PROJECTILE, EXPLOSION, FORKLIFT_FORKS, TEST_WEAPON, TEST_CAMERA, TEST_AI, TEST_SCRIPT, TEST_VEHICLE_WHEEL, GLASS</CompositeFlags2>
   </Item>
  </Children>
 </Bounds>
''' % (common, child)

    return '''<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
 <Name>%(name)s</Name>
 %(bsc)s
 <BoundingSphereRadius value="%(r)s" />
 %(bbmin)s
 %(bbmax)s
 <LodDistHigh value="9998" />
 <LodDistMed value="9998" />
 <LodDistLow value="9998" />
 <LodDistVlow value="9998" />
 <FlagsHigh value="1" />
 <FlagsMed value="0" />
 <FlagsLow value="0" />
 <FlagsVlow value="0" />
 <ShaderGroup>
  <TextureDictionary>
   <Item>
    <Name>%(tex)s</Name>
    <Unk32 value="128" />
    <Usage>DIFFUSE</Usage>
    <UsageFlags>UNK24</UsageFlags>
    <ExtraFlags value="0" />
    <Width value="%(tw)d" />
    <Height value="%(th)d" />
    <MipLevels value="%(mips)d" />
    <Format>D3DFMT_DXT5</Format>
    <FileName>%(tex)s.dds</FileName>
   </Item>
  </TextureDictionary>
  <Shaders>
   <Item>
    <Name>%(shader)s</Name>
    <FileName>%(shader)s.sps</FileName>
    <RenderBucket value="0" />
    <Parameters>
     <Item name="DiffuseSampler" type="Texture">
      <Name>%(tex)s</Name>
     </Item>
     <Item name="matMaterialColorScale" type="Vector" x="1" y="0" z="0" w="1" />
     <Item name="HardAlphaBlend" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="useTessellation" type="Vector" x="0" y="0" z="0" w="0" />
     <Item name="wetnessMultiplier" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="globalAnimUV0" type="Vector" x="1" y="0" z="0" w="0" />
     <Item name="globalAnimUV1" type="Vector" x="0" y="1" z="0" w="0" />
    </Parameters>
   </Item>
  </Shaders>
 </ShaderGroup>
 <DrawableModelsHigh>
  <Item>
   <RenderMask value="255" />
   <Flags value="0" />
   <HasSkin value="0" />
   <BoneIndex value="0" />
   <Unknown1 value="0" />
   <Geometries>
%(geoms)s
   </Geometries>
  </Item>
 </DrawableModelsHigh>
%(bounds)s <Lights />
</Drawable>
''' % dict(name=name, bsc=v3('BoundingSphereCenter', c), r=f(r), bbmin=v3('BoundingBoxMin', mn), bbmax=v3('BoundingBoxMax', mx),
           tex=tex_name, tw=tex_w, th=tex_h, mips=mips, shader=shader,
           geoms='\n'.join(geom_xml(gp) for gp in parts), bounds=bnd)


def archetype_xml(name, part, lod=60.0):
    P = part.P
    mn, mx = P.min(axis=0), P.max(axis=0)
    c = (mn + mx) / 2
    r = float(np.max(np.linalg.norm(P - c, axis=1)))
    return '''  <Item type="CBaseArchetypeDef">
   <lodDist value="%s" />
   <flags value="32" />
   <specialAttribute value="0" />
   <bbMin x="%s" y="%s" z="%s" />
   <bbMax x="%s" y="%s" z="%s" />
   <bsCentre x="%s" y="%s" z="%s" />
   <bsRadius value="%s" />
   <hdTextureDist value="%s" />
   <name>%s</name>
   <textureDictionary />
   <clipDictionary />
   <drawableDictionary />
   <physicsDictionary />
   <assetType>ASSET_TYPE_DRAWABLE</assetType>
   <assetName>%s</assetName>
   <extensions />
  </Item>''' % (f(lod), f(mn[0]), f(mn[1]), f(mn[2]), f(mx[0]), f(mx[1]), f(mx[2]), f(c[0]), f(c[1]), f(c[2]), f(r), f(lod / 2), name, name)


def ytyp_xml(name, items):
    return '''<?xml version="1.0" encoding="UTF-8"?>
<CMapTypes>
 <extensions />
 <archetypes>
%s
 </archetypes>
 <name>%s</name>
 <dependencies />
 <compositeEntityTypes itemType="CCompositeEntityType" />
</CMapTypes>
''' % ('\n'.join(items), name)


# ----------------------------------------------------------------------------------------------
# DDS (DXT5 with a full mip chain, each level compressed by Pillow)

def write_dds(img, path):
    img = img.convert('RGBA')
    w, h = img.size
    levels, payload = [], b''
    lw, lh, cur = w, h, img
    while True:
        buf = io.BytesIO()
        cur.save(buf, format='DDS', pixel_format='DXT5')
        data = buf.getvalue()[128:]
        payload += data
        levels.append((lw, lh))
        if lw <= 4 or lh <= 4:
            break
        lw, lh = max(4, lw // 2), max(4, lh // 2)
        cur = img.resize((lw, lh), Image.LANCZOS)
    mips = len(levels)
    DDSD = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000
    header = struct.pack('<4sIIIIIII', b'DDS ', 124, DDSD, h, w, max(1, ((w + 3) // 4)) * 16 * max(1, (h + 3) // 4), 0, mips)
    header += b'\0' * 44
    header += struct.pack('<II4sIIIII', 32, 0x4, b'DXT5', 0, 0, 0, 0, 0)
    header += struct.pack('<IIIII', 0x1000 | 0x8 | 0x400000, 0, 0, 0, 0)
    assert len(header) == 128, len(header)
    with open(path, 'wb') as fh:
        fh.write(header + payload)
    return mips


# ----------------------------------------------------------------------------------------------
# preview renderer (software, for eyeballing the models)

def render(part, tex, size=512, yaw=35, pitch=20, fov=30, bg=(18, 20, 22), light=(-0.4, -0.6, 0.7)):
    P, N, UV, T = part.P, part.N, part.UV, part.T
    texa = np.asarray(tex.convert('RGB'), dtype=np.float64) / 255.0
    th, tw, _ = texa.shape
    c = (P.min(axis=0) + P.max(axis=0)) / 2
    r = float(np.max(np.linalg.norm(P - c, axis=1)))
    R = rot('x', -pitch) @ rot('z', -yaw)
    V = (P - c) @ R.T  # camera looks down +y in view space
    Nv = N @ R.T
    dist = r / math.tan(math.radians(fov) / 2) * 1.15
    depth = V[:, 1] + dist
    fpx = (size / 2) / math.tan(math.radians(fov) / 2)
    sx = size / 2 + V[:, 0] / depth * fpx
    sy = size / 2 - V[:, 2] / depth * fpx
    img = np.zeros((size, size, 3)); img[:] = np.array(bg) / 255.0
    zb = np.full((size, size), np.inf)
    L = np.asarray(light, dtype=np.float64); L /= np.linalg.norm(L)
    Lv = L @ R.T
    for t in T:
        x = sx[t]; y = sy[t]; z = depth[t]
        # back-face cull (CCW seen from the camera)
        area = (x[1] - x[0]) * (y[2] - y[0]) - (x[2] - x[0]) * (y[1] - y[0])
        if area >= 0:
            continue
        x0, x1 = int(max(0, math.floor(x.min()))), int(min(size - 1, math.ceil(x.max())))
        y0, y1 = int(max(0, math.floor(y.min()))), int(min(size - 1, math.ceil(y.max())))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((x[1] - xs) * (y[2] - ys) - (x[2] - xs) * (y[1] - ys)) / area
        w1 = ((x[2] - xs) * (y[0] - ys) - (x[0] - xs) * (y[2] - ys)) / area
        w2 = 1 - w0 - w1
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not m.any():
            continue
        zz = w0 * z[0] + w1 * z[1] + w2 * z[2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= zz < sub
        if not m.any():
            continue
        sub[m] = zz[m]
        u = (w0 * UV[t[0], 0] + w1 * UV[t[1], 0] + w2 * UV[t[2], 0])[m]
        v = (w0 * UV[t[0], 1] + w1 * UV[t[1], 1] + w2 * UV[t[2], 1])[m]
        n = (w0[..., None] * Nv[t[0]] + w1[..., None] * Nv[t[1]] + w2[..., None] * Nv[t[2]])[m]
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        col = texa[np.clip((v * th).astype(int), 0, th - 1), np.clip((u * tw).astype(int), 0, tw - 1)]
        lam = np.clip(n @ Lv, 0, 1)[:, None]
        rim = np.clip(-n[:, 1], 0, 1)[:, None]
        shade = 0.38 + 0.62 * lam + 0.08 * rim
        reg = img[y0:y1 + 1, x0:x1 + 1]
        reg[m] = np.clip(col * shade, 0, 1)
    return Image.fromarray((img * 255).astype(np.uint8))
