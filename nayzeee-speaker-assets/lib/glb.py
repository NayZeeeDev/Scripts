"""glTF 2.0 binary (.glb) writer with PBR metallic-roughness materials.

* Geometry: one mesh, one primitive per material (POSITION, NORMAL, TANGENT,
  TEXCOORD_0, COLOR_0 when not all white, uint16/uint32 indices).
* Axes: GTA/Blender Z-up model space is converted to glTF Y-up with the
  standard Blender mapping (x, y, z) -> (x, z, -y).  Importing the .glb into
  Blender therefore gives exactly the GTA coordinates; in Y-up viewers the
  model FRONT (+Y in GTA) faces -Z.
* Textures are embedded as PNG: base colour = the GTA diffuse map, normal map
  converted from GTA/DirectX (green down) to glTF/OpenGL (green up), a
  metallicRoughness map derived from the GTA spec map, emissive maps for
  emissive shaders (+ KHR_materials_emissive_strength).
"""
from __future__ import annotations

import io
import json
import struct
from typing import Dict, List

import numpy as np

from . import materials as mats
from . import textures as tx
from .mesh import group_by_material

GLTF_TO = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])   # (x,y,z)_gta -> (x,z,-y)_gltf


def _png(arr: np.ndarray) -> bytes:
    im = tx.to_pil(arr)
    buf = io.BytesIO()
    im.save(buf, format="PNG", compress_level=6)
    return buf.getvalue()


def _gl_normal(name: str) -> np.ndarray:
    a = np.array(tx.image(name)[:, :, :3], dtype=np.float32)
    a[:, :, 1] = 1.0 - a[:, :, 1]
    return a


def _rough_map(spec_name: str, m: "mats.Material") -> np.ndarray:
    s = np.asarray(tx.image(spec_name)[:, :, 0], dtype=np.float64)
    mean = max(float(s.mean()), 1e-3)
    rel = s / mean
    rough = np.clip(m.pbr.roughness * (2.0 - rel), 0.03, 1.0)
    out = np.zeros(s.shape + (3,), np.float32)
    out[:, :, 1] = rough
    out[:, :, 2] = 1.0            # metallic channel (scaled by metallicFactor)
    return out


def _is_flat(name: str) -> bool:
    d = tx.get(name)
    return d.size[0] <= 16 and d.size[1] <= 16


class _Bin:
    def __init__(self):
        self.data = bytearray()
        self.views: List[dict] = []
        self.accessors: List[dict] = []

    def view(self, raw: bytes, target=None) -> int:
        while len(self.data) % 4:
            self.data += b"\x00"
        v = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.data += raw
        self.views.append(v)
        return len(self.views) - 1

    def accessor(self, arr: np.ndarray, ctype: int, atype: str, target=None, normalized=False, minmax=False) -> int:
        vi = self.view(arr.tobytes(), target)
        a = {"bufferView": vi, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.accessors.append(a)
        return len(self.accessors) - 1


def build_glb(name: str, parts) -> bytes:
    """Return the .glb bytes for ``parts`` (list of Mesh with materials)."""
    groups = group_by_material(parts)
    b = _Bin()
    images: List[dict] = []
    textures_: List[dict] = []
    tex_index: Dict[str, int] = {}
    materials_json: List[dict] = []
    used_ext = set()

    def texture(key: str, arr_fn) -> int:
        if key in tex_index:
            return tex_index[key]
        vi = b.view(_png(arr_fn()))
        images.append({"bufferView": vi, "mimeType": "image/png", "name": key})
        textures_.append({"source": len(images) - 1, "sampler": 0})
        tex_index[key] = len(textures_) - 1
        return tex_index[key]

    prims = []
    for mi, (mname, mesh) in enumerate(groups.items()):
        m = mats.get(mname)
        p = m.pbr
        mj = {"name": mname, "pbrMetallicRoughness": {
            "baseColorFactor": [float(c) for c in p.base_color] + [1.0],
            "metallicFactor": float(p.metallic), "roughnessFactor": float(p.roughness)}}
        emissive_shader = m.shader_def.name.startswith("emissive")
        if m.diffuse:
            ti = texture(m.diffuse, lambda n=m.diffuse: tx.image(n))
            mj["pbrMetallicRoughness"]["baseColorTexture"] = {"index": ti}
            if emissive_shader:
                mj["emissiveTexture"] = {"index": ti}
        if m.normal and not _is_flat(m.normal):
            ti = texture(m.normal + "@gl", lambda n=m.normal: _gl_normal(n))
            bump = {k.lower(): v for k, v in m.params.items()}.get("bumpiness", 1.0)
            mj["normalTexture"] = {"index": ti, "scale": float(p.normal_scale) * float(bump)}
        if m.spec and not _is_flat(m.spec) and not emissive_shader:
            ti = texture(m.spec + "@rough@" + mname, lambda n=m.spec, mm=m: _rough_map(n, mm))
            mj["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": ti}
            mj["pbrMetallicRoughness"]["roughnessFactor"] = 1.0
        if any(p.emissive):
            mj["emissiveFactor"] = [float(min(c, 1.0)) for c in p.emissive]
            if p.emissive_strength > 1.0:
                mj["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": float(p.emissive_strength)}}
                used_ext.add("KHR_materials_emissive_strength")
        if p.alpha_mode != "OPAQUE":
            mj["alphaMode"] = p.alpha_mode
            if p.alpha_mode == "MASK":
                mj["alphaCutoff"] = 0.5
        if p.double_sided:
            mj["doubleSided"] = True
        materials_json.append(mj)

        pos = (mesh.positions @ GLTF_TO.T).astype(np.float32)
        nrm = (mesh.normals @ GLTF_TO.T).astype(np.float32)
        tan = mesh.ensure_tangents().copy()
        tan[:, :3] = tan[:, :3] @ GLTF_TO.T
        tan = tan.astype(np.float32)
        uv = mesh.uvs.astype(np.float32)
        attrs = {
            "POSITION": b.accessor(pos, 5126, "VEC3", 34962, minmax=True),
            "NORMAL": b.accessor(nrm, 5126, "VEC3", 34962),
            "TANGENT": b.accessor(tan, 5126, "VEC4", 34962),
            "TEXCOORD_0": b.accessor(uv, 5126, "VEC2", 34962),
        }
        if not np.allclose(mesh.colors, 1.0):
            col = np.clip(np.rint(mesh.colors * 255), 0, 255).astype(np.uint8)
            attrs["COLOR_0"] = b.accessor(col, 5121, "VEC4", 34962, normalized=True)
        idx = mesh.indices.reshape(-1)
        if mesh.vertex_count < 65536:
            ia = b.accessor(idx.astype(np.uint16).reshape(-1, 1), 5123, "SCALAR", 34963)
        else:
            ia = b.accessor(idx.astype(np.uint32).reshape(-1, 1), 5125, "SCALAR", 34963)
        prims.append({"attributes": attrs, "indices": ia, "material": mi, "mode": 4})

    gltf = {
        "asset": {"version": "2.0", "generator": "nayzeee-speaker-assets"},
        "scene": 0,
        "scenes": [{"nodes": [0], "name": name}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": prims}],
        "materials": materials_json,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "buffers": [{"byteLength": 0}],
        "bufferViews": b.views,
        "accessors": b.accessors,
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures_
    if used_ext:
        gltf["extensionsUsed"] = sorted(used_ext)
    while len(b.data) % 4:
        b.data += b"\x00"
    gltf["buffers"][0]["byteLength"] = len(b.data)
    js = json.dumps(gltf, separators=(",", ":"), sort_keys=True).encode("utf-8")
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(b.data)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(b.data), b"BIN\x00") + bytes(b.data)
    return out


def write_glb(path: str, name: str, parts) -> int:
    data = build_glb(name, parts)
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def read_glb(path: str):
    """Minimal reader for checks: returns (gltf json dict, bin bytes)."""
    data = open(path, "rb").read()
    magic, ver, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or ver != 2 or total != len(data):
        raise ValueError("not a glTF 2.0 binary")
    jl, jt = struct.unpack_from("<I4s", data, 12)
    js = json.loads(data[20:20 + jl])
    bl, bt = struct.unpack_from("<I4s", data, 20 + jl)
    return js, data[28 + jl:28 + jl + bl]
