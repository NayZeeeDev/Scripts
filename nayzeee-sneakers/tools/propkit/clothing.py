"""
Read the high-LOD mesh out of a CodeWalker clothing export (.ydd.xml).

    meshes = read_ydd_xml("feet_000_u.ydd.xml")   # one Mesh per geometry

Skinning, second UV set, tangents and colours are dropped: a prop only needs
position, normal and the UV set the diffuse texture is mapped on.
"""

import re

from propkit import Mesh

FIELD_WIDTH = {
    "Position": 3, "BlendWeights": 4, "BlendIndices": 4, "Normal": 3,
    "Colour0": 4, "Colour1": 4, "Tangent": 4, "Binormal": 4,
    **{f"TexCoord{i}": 2 for i in range(8)},
}


def _geometries(lod_block):
    for m in re.finditer(r"<VertexBuffer>([\s\S]*?)</VertexBuffer>\s*<IndexBuffer>\s*<Data>([\s\S]*?)</Data>",
                         lod_block):
        yield m.group(1), m.group(2)


def read_ydd_xml(path, uv_set=0, drawable=0):
    text = open(path, encoding="utf-8").read()
    drawables = re.findall(r"<DrawableModelsHigh>([\s\S]*?)</DrawableModelsHigh>", text)
    if not drawables:
        raise ValueError("no high LOD models in " + path)
    meshes = []
    for vb, ib in _geometries(drawables[drawable]):
        layout = re.search(r"<Layout[^>]*>([\s\S]*?)</Layout>", vb).group(1)
        fields, off = {}, 0
        for name in re.findall(r"<(\w+)\s*/>", layout):
            fields[name] = off
            off += FIELD_WIDTH[name]
        data = re.search(r"<Data2?>([\s\S]*?)</Data2?>", vb).group(1)
        uv_key = f"TexCoord{uv_set}"
        mesh = Mesh()
        for line in data.strip().splitlines():
            v = line.split()
            if len(v) != off:
                continue
            p, n, t = fields["Position"], fields["Normal"], fields[uv_key]
            mesh.vertex((float(v[p]), float(v[p + 1]), float(v[p + 2])),
                        (float(v[n]), float(v[n + 1]), float(v[n + 2])),
                        (float(v[t]), float(v[t + 1])))
        mesh.idx = [int(i) for i in ib.split()]
        meshes.append(mesh)
    return meshes


def merge(meshes):
    out = Mesh()
    for m in meshes:
        out.extend(m)
    return out
