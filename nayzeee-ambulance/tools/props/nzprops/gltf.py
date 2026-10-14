"""
nzprops.gltf - binary glTF 2.0 (.glb) export of a built prop for previews and editing.

GTA is Z-up, glTF is Y-up: positions are written as (x, z, -y). One primitive per shader group,
PBR materials approximating the GTA look (spec map alpha -> roughness, preview metalness).
"""
from __future__ import annotations

import io
import json
import struct

import numpy as np


def _png(img):
    b = io.BytesIO()
    img.save(b, "PNG", optimize=False, compress_level=6)
    return b.getvalue()


def _yup(a):
    a = np.asarray(a, np.float32)
    return np.stack([a[:, 0], a[:, 2], -a[:, 1]], axis=1)


def write_glb(path, name, groups):
    """groups: list of dicts {pos, nrm, uv, tan|None, idx, material: {kind, base, normal, mr, emissive, alpha}}
    kind: 'pbr' | 'alpha' | 'emissive'. Images are PIL images (or None)."""
    blobs = []
    views = []
    accessors = []
    images = []
    textures = []
    materials = []
    prims = []
    offset = 0

    def add_blob(data, target=None):
        nonlocal offset
        pad = (-len(data)) % 4
        v = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        blobs.append(data + b"\x00" * pad)
        offset += len(data) + pad
        return len(views) - 1

    def add_acc(arr, typ, comp=5126, target=34962, minmax=False):
        vi = add_blob(arr.tobytes(), target)
        a = {"bufferView": vi, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = arr.min(axis=0).tolist()
            a["max"] = arr.max(axis=0).tolist()
        accessors.append(a)
        return len(accessors) - 1

    tex_cache = {}

    def add_tex(img):
        if img is None:
            return None
        key = id(img)
        if key in tex_cache:
            return tex_cache[key]
        vi = add_blob(_png(img))
        images.append({"bufferView": vi, "mimeType": "image/png"})
        textures.append({"source": len(images) - 1, "sampler": 0})
        tex_cache[key] = len(textures) - 1
        return tex_cache[key]

    for g in groups:
        pos = _yup(g["pos"])
        nrm = _yup(g["nrm"])
        uv = np.asarray(g["uv"], np.float32)
        idx = np.asarray(g["idx"], np.uint32).reshape(-1)
        attrs = {"POSITION": add_acc(pos, "VEC3", minmax=True), "NORMAL": add_acc(nrm, "VEC3"), "TEXCOORD_0": add_acc(uv, "VEC2")}
        if g.get("tan") is not None:
            t = np.asarray(g["tan"], np.float32)
            t3 = _yup(t[:, :3])
            attrs["TANGENT"] = add_acc(np.concatenate([t3, t[:, 3:4]], axis=1).astype(np.float32), "VEC4")
        ia = add_acc(idx, "SCALAR", comp=5125, target=34963)
        m = g["material"]
        mat = {"name": m.get("name", "mat"), "pbrMetallicRoughness": {"metallicFactor": 1.0, "roughnessFactor": 1.0}}
        if m["kind"] == "emissive":
            ti = add_tex(m.get("emissive"))
            mat["pbrMetallicRoughness"] = {"baseColorFactor": [0.02, 0.02, 0.02, 1], "metallicFactor": 0.0, "roughnessFactor": 0.35}
            mat["emissiveTexture"] = {"index": ti}
            mat["emissiveFactor"] = [1.0, 1.0, 1.0]
        else:
            bi = add_tex(m.get("base"))
            ni = add_tex(m.get("normal"))
            mi = add_tex(m.get("mr"))
            if bi is not None:
                mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": bi}
            if mi is not None:
                mat["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": mi}
            if ni is not None:
                mat["normalTexture"] = {"index": ni}
            if m["kind"] == "alpha":
                mat["alphaMode"] = "BLEND"
                mat["doubleSided"] = True
        materials.append(mat)
        prims.append({"attributes": attrs, "indices": ia, "material": len(materials) - 1})

    bin_data = b"".join(blobs)
    gltf = {
        "asset": {"version": "2.0", "generator": "nzprops (NAYZEEE props pipeline)"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{"name": name, "primitives": prims}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_data)}],
        "materials": materials,
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942) + bin_data)
