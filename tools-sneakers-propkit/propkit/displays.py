"""
displays.py - the clear acrylic shoe display cases (nzs_display, _heel, _boot).

Each size is two props:
    nzs_display[_size]        the case: clear back, sides, top and floor with frosted edges, box collision.
                              Origin at the bottom centre, +Y is the front (the open side).
    nzs_display[_size]_door   the front door, hinged on its left edge: origin at the bottom of the hinge.
                              The script attaches it at (-W/2, D/2, 0) and swings it open around Z.

The acrylic uses glass_pv (alpha-blended glass, opacity from the vertex colour), so the panels are
see-through and the edges read as frosted. The door's pull tab is plain opaque plastic.

    python displays.py <out_dir>
writes <name>.ydr.xml (+ texture folders) and nzs_display.ytyp.xml; codewalker/import turns them into
game files.
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from propkit import collision_xml, dds_dxt5, f, v3  # noqa: E402

# outer size (width x depth x height, metres); each fits the packed pair of that box size
SIZES = {
    "nzs_display": (0.37, 0.32, 0.235),
    "nzs_display_heel": (0.44, 0.33, 0.17),
    "nzs_display_boot": (0.55, 0.54, 0.21),
}
T = 0.005          # acrylic thickness
EDGE = 0.007       # frosted edge strip width
CLEAR = (226, 240, 255, 46)     # panel tint and opacity (vertex colour)
FROST = (238, 246, 255, 150)    # edges


class Part:
    """Triangles for one material, with per-vertex colour."""

    def __init__(self):
        self.pos, self.nrm, self.col, self.uv, self.idx = [], [], [], [], []

    def quad(self, a, b, c, d, n, col):
        base = len(self.pos)
        for p, t in zip((a, b, c, d), ((0, 1), (1, 1), (1, 0), (0, 0))):
            self.pos.append(p)
            self.nrm.append(n)
            self.col.append(col)
            self.uv.append(t)
        self.idx += [base, base + 1, base + 2, base + 2, base + 3, base]

    def box(self, lo, hi, col):
        """A solid axis-aligned slab, all six faces outward."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0), col)   # -Y
        self.quad((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (0, 1, 0), col)    # +Y
        self.quad((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (-1, 0, 0), col)   # -X
        self.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), (1, 0, 0), col)    # +X
        self.quad((x0, y1, z1), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (0, 0, 1), col)    # top
        self.quad((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (0, 0, -1), col)   # bottom

    def bounds(self):
        xs, ys, zs = zip(*self.pos)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def panel_with_edges(part, lo, hi, thin_axis):
    """A clear panel with a frosted strip round its border (strips are slightly proud, so no z-fighting)."""
    part.box(lo, hi, CLEAR)
    lo, hi = list(lo), list(hi)
    axes = [a for a in range(3) if a != thin_axis]
    for a in axes:
        other = [b for b in axes if b != a][0]
        for side in (0, 1):
            s_lo, s_hi = lo[:], hi[:]
            if side == 0:
                s_hi[other] = lo[other] + EDGE
            else:
                s_lo[other] = hi[other] - EDGE
            s_lo[thin_axis] -= 0.0004
            s_hi[thin_axis] += 0.0004
            part.box(tuple(s_lo), tuple(s_hi), FROST)


def case(w, d, h):
    glass = Part()
    hx, hy = w / 2, d / 2
    front = hy - T                                    # the door sits in front of this
    panel_with_edges(glass, (-hx, -hy, 0), (hx, front, T), 2)                 # floor
    panel_with_edges(glass, (-hx, -hy, h - T), (hx, front, h), 2)             # top
    panel_with_edges(glass, (-hx, -hy, T), (hx, -hy + T, h - T), 1)           # back
    panel_with_edges(glass, (-hx, -hy + T, T), (-hx + T, front, h - T), 0)    # left
    panel_with_edges(glass, (hx - T, -hy + T, T), (hx, front, h - T), 0)      # right
    return {"glass": glass}


def door(w, d, h):
    glass, tab = Part(), Part()
    # hinge at x=0: the panel runs along +X, its back face at y=-T, front face at y=0
    panel_with_edges(glass, (0.0005, -T, 0), (w - 0.0005, 0, h), 1)
    # pull tab: a small dark lip on the free edge, half way up
    tz = h * 0.5
    tab.box((w - 0.03, 0.0, tz - 0.018), (w - 0.012, 0.006, tz + 0.018), (40, 42, 46, 255))
    return {"glass": glass, "tab": tab}


SHADERS = {
    "glass": ("glass_pv", "glass_pv.sps", 1, [
        ("specularFresnel", (0.97, 0, 0, 0)),
        ("specularFalloffMult", (150, 0, 0, 0)),
        ("specularIntensityMult", (0.9, 0, 0, 0)),
        ("specMapIntMask", (1, 0, 0, 0)),
        ("useTessellation", (0, 0, 0, 0)),
        ("HardAlphaBlend", (0, 0, 0, 0)),
    ]),
    "tab": ("default", "default.sps", 0, [
        ("matMaterialColorScale", (1, 0, 0, 1)),
        ("HardAlphaBlend", (1, 0, 0, 0)),
        ("useTessellation", (0, 0, 0, 0)),
        ("wetnessMultiplier", (1, 0, 0, 0)),
        ("globalAnimUV0", (1, 0, 0, 0)),
        ("globalAnimUV1", (0, 1, 0, 0)),
    ]),
}
TEX_COLOUR = {"glass": (255, 255, 255, 255), "tab": (52, 54, 58, 255)}


def write(out_dir, name, parts, collision):
    os.makedirs(os.path.join(out_dir, name), exist_ok=True)
    keys = [k for k in ("glass", "tab") if k in parts]
    texs, shaders, geoms = [], [], []
    lo = [min(p.bounds()[0][i] for p in parts.values()) for i in range(3)]
    hi = [max(p.bounds()[1][i] for p in parts.values()) for i in range(3)]
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    r = sum((hi[i] - c[i]) ** 2 for i in range(3)) ** 0.5
    for si, k in enumerate(keys):
        tex = f"{name}_{k}"
        dds, mips = dds_dxt5(Image.new("RGBA", (16, 16), TEX_COLOUR[k]))
        with open(os.path.join(out_dir, name, tex + ".dds"), "wb") as fh:
            fh.write(dds)
        texs.append(f"""   <Item>
    <Name>{tex}</Name>
    <Unk32 value="128" />
    <Usage>DIFFUSE</Usage>
    <UsageFlags>UNK24</UsageFlags>
    <ExtraFlags value="0" />
    <Width value="16" />
    <Height value="16" />
    <MipLevels value="{mips}" />
    <Format>D3DFMT_DXT5</Format>
    <FileName>{tex}.dds</FileName>
   </Item>""")
        sname, sfile, bucket, params = SHADERS[k]
        prm = "\n".join(f'     <Item name="{n}" type="Vector" x="{f(v[0])}" y="{f(v[1])}" z="{f(v[2])}" w="{f(v[3])}" />' for n, v in params)
        shaders.append(f"""   <Item>
    <Name>{sname}</Name>
    <FileName>{sfile}</FileName>
    <RenderBucket value="{bucket}" />
    <Parameters>
     <Item name="DiffuseSampler" type="Texture">
      <Name>{tex}</Name>
     </Item>
{prm}
    </Parameters>
   </Item>""")
        p = parts[k]
        plo, phi = p.bounds()
        rows = "\n".join("          {}   {}   {} {} {} {}   {}".format(
            " ".join(f(x) for x in pos), " ".join(f(x) for x in n), *col, " ".join(f(x) for x in t))
            for pos, n, col, t in zip(p.pos, p.nrm, p.col, p.uv))
        idx = "\n".join("          " + " ".join(str(i) for i in p.idx[j:j + 24]) for j in range(0, len(p.idx), 24))
        geoms.append(f"""    <Item>
     <ShaderIndex value="{si}" />
     <BoundingBoxMin x="{f(plo[0])}" y="{f(plo[1])}" z="{f(plo[2])}" w="0" />
     <BoundingBoxMax x="{f(phi[0])}" y="{f(phi[1])}" z="{f(phi[2])}" w="0" />
     <VertexBuffer>
      <Flags value="0" />
      <Layout type="GTAV1">
       <Position />
       <Normal />
       <Colour0 />
       <TexCoord0 />
      </Layout>
      <Data>
{rows}
      </Data>
     </VertexBuffer>
     <IndexBuffer>
      <Data>
{idx}
      </Data>
     </IndexBuffer>
    </Item>""")
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Drawable>
 <Name>{name}</Name>
 {v3('BoundingSphereCenter', c)}
 <BoundingSphereRadius value="{f(r)}" />
 {v3('BoundingBoxMin', lo)}
 {v3('BoundingBoxMax', hi)}
 <LodDistHigh value="9998" />
 <LodDistMed value="9998" />
 <LodDistLow value="9998" />
 <LodDistVlow value="9998" />
 <FlagsHigh value="{len(keys)}" />
 <FlagsMed value="0" />
 <FlagsLow value="0" />
 <FlagsVlow value="0" />
 <ShaderGroup>
  <TextureDictionary>
{chr(10).join(texs)}
  </TextureDictionary>
  <Shaders>
{chr(10).join(shaders)}
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
{chr(10).join(geoms)}
   </Geometries>
  </Item>
 </DrawableModelsHigh>
{collision_xml(lo, hi, c, r) if collision else ''}</Drawable>
"""
    with open(os.path.join(out_dir, name + ".ydr.xml"), "w", newline="\n") as fh:
        fh.write(xml)
    return lo, hi, c, r


def ytyp(out_dir, name, arche):
    items = []
    for an, (lo, hi, c, r) in arche.items():
        items.append(f"""    <Item type="CBaseArchetypeDef">
      <lodDist value="100"/>
      <flags value="32"/>
      <specialAttribute value="0"/>
      <bbMin x="{f(lo[0])}" y="{f(lo[1])}" z="{f(lo[2])}"/>
      <bbMax x="{f(hi[0])}" y="{f(hi[1])}" z="{f(hi[2])}"/>
      <bsCentre x="{f(c[0])}" y="{f(c[1])}" z="{f(c[2])}"/>
      <bsRadius value="{f(r)}"/>
      <hdTextureDist value="50"/>
      <name>{an}</name>
      <textureDictionary/>
      <clipDictionary/>
      <drawableDictionary/>
      <physicsDictionary/>
      <assetType>ASSET_TYPE_DRAWABLE</assetType>
      <assetName>{an}</assetName>
      <extensions/>
    </Item>""")
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<CMapTypes>\n  <extensions/>\n  <archetypes>\n'
           + "\n".join(items) + f"\n  </archetypes>\n  <name>{name}</name>\n  <dependencies/>\n"
           "  <compositeEntityTypes/>\n</CMapTypes>\n")
    with open(os.path.join(out_dir, name + ".ytyp.xml"), "w", newline="\n") as fh:
        fh.write(xml)


def main(out_dir):
    arche = {}
    for name, (w, d, h) in SIZES.items():
        arche[name] = write(out_dir, name, case(w, d, h), collision=True)
        arche[name + "_door"] = write(out_dir, name + "_door", door(w, d, h), collision=False)
        print(f"{name}: {w} x {d} x {h} m, door hinge at ({-w / 2:.3f}, {d / 2:.3f}, 0)")
    ytyp(out_dir, "nzs_display", arche)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out_displays")
