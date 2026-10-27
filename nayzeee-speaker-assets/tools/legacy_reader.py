#!/usr/bin/env python3
"""Reader for the legacy (gen8 / RSC7) props that nayzeee-speaker ships in stream/.

    python3 tools/legacy_reader.py                      # all stream/nayzeee_audio_[a-h].ydr -> legacy/<model>.json + .glb
    python3 tools/legacy_reader.py --models nayzeee_audio_c --print
    python3 tools/legacy_reader.py --dump-textures DIR  # also write every texture of the .ytd as PNG

What it reads (layout cross-checked against CodeWalker's Drawable.cs / Texture.cs / VertexType.cs,
used as a read-only reference; no third-party code is executed):

* RSC7 container: 16-byte header (magic, version, system flags, graphics flags), raw-deflate body,
  system pages followed by graphics pages.  Pointers are 0x5XXXXXXX (system) or 0x6XXXXXXX (graphics).
* Drawable (system offset 0): shader group, skeleton, bounds, High/Med/Low/VLow model lists, name.
* ShaderGroup: optional embedded TextureDictionary + ShaderFX pointer array.  ShaderFX parameters are
  16-byte records (type 0 = texture reference, n>0 = n Vector4), then the vector data, then one name
  hash per parameter.  Hashes are resolved with Jenkins one-at-a-time against data/shaders_gen9.json.
* DrawableModel -> DrawableGeometry -> VertexBuffer (+ VertexDeclaration) / IndexBuffer.
  Vertex declaration: 16 semantic flags, a 4-bit component type per semantic.

What it writes:
* legacy/<model>.json : shaders (name, .sps, textures per sampler, vector params), geometry per LOD with
  the shader index, the textures each geometry samples, vertex layout and counts, UV ranges.
* legacy/<model>.glb  : the High LOD as glTF 2.0 (GTA Z-up -> glTF Y-up like lib/glb.py), one primitive
  per geometry, PBR materials using the original textures of nayzeee_audio_texture.ytd (or the
  drawable's embedded dictionary), emissive shaders as emissive.  ``--replace tex=path.png`` swaps a
  texture (used to preview looks), ``--glb-out`` writes one model's GLB somewhere else.

These files are derived from the third-party prop pack in stream/.  They are for previews only and
are never shipped; regenerate them with this script instead of committing edited copies.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
from lib import dds as D  # noqa: E402

STREAM = os.path.normpath(os.path.join(ROOT, "..", "nayzeee-speaker", "stream"))
OUT_DIR = os.path.join(ROOT, "legacy")
YTD = "nayzeee_audio_texture.ytd"
MODELS = [f"nayzeee_audio_{c}" for c in "abcdefgh"]


# --------------------------------------------------------------------------- hashes
def joaat(s: str) -> int:
    h = 0
    for c in s.lower().encode("utf-8"):
        h = (h + c) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h ^= h >> 6
    h = (h + (h << 3)) & 0xFFFFFFFF
    h ^= h >> 11
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h


def _hash_names() -> dict:
    names = set()
    path = os.path.join(ROOT, "data", "shaders_gen9.json")
    if os.path.exists(path):
        sh = json.load(open(path, encoding="utf-8"))["shaders"]
        for k, v in sh.items():
            names.add(k)
            names.add(v.get("file", ""))
            names.update(v.get("textures", []))
            names.update(v.get("params", []))
    names.update(["DiffuseSampler", "BumpSampler", "SpecSampler", "DetailSampler", "TextureSamp",
                  "emissiveMultiplier", "specularIntensityMult", "specularFalloffMult", "bumpiness",
                  "specularFresnel", "HardAlphaBlend", "globalAnimUV0", "globalAnimUV1"])
    return {joaat(n): n for n in names if n}


HASHES = _hash_names()


def hname(h: int) -> str:
    return HASHES.get(h, f"hash_{h:08X}")


# --------------------------------------------------------------------------- RSC7
def _page_size(flags: int) -> int:
    s = (((flags >> 27) & 1) << 0) + (((flags >> 26) & 1) << 1) + (((flags >> 25) & 1) << 2) + \
        (((flags >> 24) & 1) << 3) + (((flags >> 17) & 0x7F) << 4) + (((flags >> 11) & 0x3F) << 5) + \
        (((flags >> 7) & 0xF) << 6) + (((flags >> 5) & 3) << 7) + (((flags >> 4) & 1) << 8)
    return (0x200 << (flags & 0xF)) * s


class Res:
    """A decompressed RSC7 resource with typed reads through 0x5/0x6 pointers."""

    def __init__(self, path: str):
        raw = open(path, "rb").read()
        magic, self.version, sflags, gflags = struct.unpack("<4sIII", raw[:16])
        if magic != b"RSC7":
            raise ValueError(f"{path}: not an RSC7 resource ({magic!r})")
        data = zlib.decompress(raw[16:], -15)
        ssz, gsz = _page_size(sflags), _page_size(gflags)
        self.sys = data[:ssz]
        self.gfx = data[ssz:ssz + gsz]
        self.path = path

    def _seg(self, ptr: int):
        kind, off = ptr >> 28, ptr & 0x0FFFFFFF
        if kind == 5:
            return self.sys, off
        if kind == 6:
            return self.gfx, off
        raise ValueError(f"bad pointer {ptr:#x}")

    def bytes(self, ptr: int, n: int) -> bytes:
        buf, off = self._seg(ptr)
        if off + n > len(buf):
            raise ValueError(f"read past end at {ptr:#x}+{n}")
        return buf[off:off + n]

    def unpack(self, fmt: str, ptr: int):
        return struct.unpack_from("<" + fmt, *self._seg(ptr))

    def u8(self, p): return self.unpack("B", p)[0]
    def u16(self, p): return self.unpack("H", p)[0]
    def u32(self, p): return self.unpack("I", p)[0]
    def u64(self, p): return self.unpack("Q", p)[0]

    def cstr(self, ptr: int) -> str:
        buf, off = self._seg(ptr)
        end = buf.index(b"\0", off)
        return buf[off:end].decode("utf-8", "replace")


# --------------------------------------------------------------------------- textures
FMT = {0x31545844: "DXT1", 0x33545844: "DXT3", 0x35545844: "DXT5", 0x20374342: "BC7", 0x31495441: "ATI1",
       0x32495441: "ATI2", 21: "A8R8G8B8", 32: "A8B8G8R8", 50: "L8", 28: "A8"}


def decode_bc2(data: bytes, w: int, h: int) -> np.ndarray:
    """DXT3: 64-bit explicit 4-bit alpha + a 4-colour BC1 block."""
    n = (w // 4) * (h // 4)
    arr = np.frombuffer(data, dtype=[("a", "<u8"), ("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")], count=n)
    al = ((arr["a"][:, None] >> (np.arange(16, dtype=np.uint64) * 4)) & np.uint64(15)).astype(np.float64) * 17.0
    cpal = D._palette4(D._unpack565(arr["c0"]), D._unpack565(arr["c1"]))
    idx = ((arr["i"][:, None].astype(np.uint64) >> (np.arange(16, dtype=np.uint64) * 2)) & np.uint64(3)).astype(int)
    rgb = np.take_along_axis(cpal, idx[:, :, None].repeat(3, axis=2), axis=1)
    blk = np.concatenate([rgb, al[:, :, None]], axis=2)
    return D._from_blocks(blk, h, w).astype(np.uint8)


def read_texture_dictionary(res: Res, base: int) -> list:
    """TextureDictionary at ``base`` (0x50000000 for a .ytd): [{name, w, h, fmt, levels, rgba}]."""
    tptr = res.u64(base + 0x30)
    count = res.u16(base + 0x38)
    out = []
    for i in range(count):
        t = res.u64(tptr + 8 * i)
        name = res.cstr(res.u64(t + 0x28))
        w, h, _d, stride = res.unpack("HHHH", t + 0x50)
        fmt_code = res.u32(t + 0x58)
        levels = res.u8(t + 0x5D)
        dptr = res.u64(t + 0x70)
        fmt = FMT.get(fmt_code, hex(fmt_code))
        rgba = None
        if fmt in ("DXT1", "DXT3", "DXT5"):
            n = max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * (8 if fmt == "DXT1" else 16)
            blob = res.bytes(dptr, n)
            rgba = {"DXT1": D.decode_bc1, "DXT3": decode_bc2, "DXT5": D.decode_bc3}[fmt](blob, w, h)
        elif fmt == "A8R8G8B8":
            blob = res.bytes(dptr, stride * h)
            rgba = np.frombuffer(blob, np.uint8).reshape(h, stride)[:, :w * 4].reshape(h, w, 4)[..., [2, 1, 0, 3]].copy()
        out.append({"name": name, "w": w, "h": h, "fmt": fmt, "levels": levels, "rgba": rgba, "ptr": t})
    return out


def read_ytd(path: str) -> dict:
    res = Res(path)
    return {t["name"].lower(): t for t in read_texture_dictionary(res, 0x50000000)}


# --------------------------------------------------------------------------- drawable
COMP_SIZE = {0: 0, 1: 4, 2: 4, 3: 8, 4: 0, 5: 8, 6: 12, 7: 16, 8: 4, 9: 4, 10: 4}
COMP_NAME = {1: "Half2", 2: "Float", 3: "Half4", 5: "Float2", 6: "Float3", 7: "Float4", 8: "UByte4", 9: "Colour",
             10: "RGBA8SNorm"}
SEMANTICS = ["Position", "BlendWeights", "BlendIndices", "Normal", "Colour0", "Colour1", "TexCoord0", "TexCoord1",
             "TexCoord2", "TexCoord3", "TexCoord4", "TexCoord5", "TexCoord6", "TexCoord7", "Tangent", "Binormal"]


def _decode_component(raw: np.ndarray, off: int, ctype: int) -> np.ndarray:
    """raw: (n, stride) uint8 -> (n, k) float array."""
    sz = COMP_SIZE[ctype]
    chunk = np.ascontiguousarray(raw[:, off:off + sz])
    if ctype in (2, 5, 6, 7):
        return chunk.view("<f4").astype(np.float64)
    if ctype in (1, 3):
        return chunk.view("<f2").astype(np.float64)
    if ctype in (8, 9):
        return chunk.astype(np.float64) / (255.0 if ctype == 9 else 1.0)
    if ctype == 10:
        return chunk.view(np.int8).astype(np.float64) / 127.0
    raise ValueError(f"component type {ctype}")


def read_shader(res: Res, p: int) -> dict:
    params_ptr = res.u64(p)
    name_h = res.u32(p + 0x08)
    count = res.u8(p + 0x10)
    bucket = res.u8(p + 0x11)
    file_h = res.u32(p + 0x18)
    recs = []
    for i in range(count):
        dtype, _u1 = res.unpack("BB", params_ptr + 16 * i)
        dptr = res.u64(params_ptr + 16 * i + 8)
        recs.append((dtype, dptr))
    data_len = sum(16 * dt for dt, _ in recs)
    hptr = params_ptr + 16 * count + data_len
    textures, tex_ptrs, vectors = {}, {}, {}
    for i, (dtype, dptr) in enumerate(recs):
        pname = hname(res.u32(hptr + 4 * i))
        if dtype == 0:
            textures[pname] = res.cstr(res.u64(dptr + 0x28)) if dptr else None
            tex_ptrs[pname] = dptr
        else:
            vals = res.unpack("%df" % (4 * dtype), dptr)
            vectors[pname] = [round(float(v), 6) for v in (vals if dtype > 1 else vals[:4])]
    return {"name": hname(name_h), "file": hname(file_h), "render_bucket": bucket, "textures": textures,
            "params": vectors, "_tex_ptrs": tex_ptrs}


def read_geometry(res: Res, g: int) -> dict:
    vb = res.u64(g + 0x18)
    ib = res.u64(g + 0x38)
    stride = res.u16(vb + 0x08)
    vcount = res.u32(vb + 0x18)
    vdata = res.u64(vb + 0x10) or res.u64(vb + 0x20)
    decl = res.u64(vb + 0x30)
    flags = res.u32(decl)
    dstride = res.u16(decl + 4)
    types = res.u64(decl + 8)
    if dstride != stride:
        raise ValueError(f"vertex stride mismatch {dstride} != {stride}")
    raw = np.frombuffer(res.bytes(vdata, stride * vcount), np.uint8).reshape(vcount, stride)
    comps, off = {}, 0
    layout = []
    for k in range(16):
        if (flags >> k) & 1:
            ct = (types >> (4 * k)) & 0xF
            comps[SEMANTICS[k]] = _decode_component(raw, off, ct)
            layout.append(f"{SEMANTICS[k]}:{COMP_NAME.get(ct, ct)}")
            off += COMP_SIZE[ct]
    icount = res.u32(ib + 0x08)
    iptr = res.u64(ib + 0x10)
    idx = np.frombuffer(res.bytes(iptr, 2 * icount), "<u2").astype(np.uint32)
    return {"vertex_count": vcount, "index_count": icount, "stride": stride, "layout": layout, "comps": comps,
            "indices": idx.reshape(-1, 3)}


def read_bones(res: Res, skel: int) -> list:
    """Bone names + the skeleton's Transformations array (one 4x4 per bone), or [] without a skeleton.

    Rows 0..2 hold the rotation basis, row 3 the translation (row-vector convention).  For these props only
    the translation is exercised (every bone is unrotated and parented to an identity root: the spinning
    record of nayzeee_audio_g sits on bone 1); rotated or nested bones were not verified."""
    if not skel:
        return []
    bones_ptr = res.u64(skel + 0x20)
    tf_ptr = res.u64(skel + 0x30)          # TransformationsInverted = 0x28, Transformations = 0x30
    count = res.u16(skel + 0x5E)
    mats = []
    if tf_ptr and count:
        for i in range(count):
            v = res.unpack("16f", tf_ptr + 64 * i)
            m = np.array(v, dtype=np.float64).reshape(4, 4)
            mats.append(m)
    names = []
    if bones_ptr and count:
        for i in range(count):
            b = bones_ptr + 0x50 * i
            try:
                names.append(res.cstr(res.u64(b + 0x38)))
            except Exception:
                names.append(f"bone{i}")
    return [{"name": n, "m": m} for n, m in zip(names, mats)] if mats else [{"name": n} for n in names]


def read_ydr(path: str) -> dict:
    res = Res(path)
    base = 0x50000000
    sg = res.u64(base + 0x10)
    skel = res.u64(base + 0x18)
    bc = res.unpack("4f", base + 0x20)
    bmin = res.unpack("3f", base + 0x30)
    bmax = res.unpack("3f", base + 0x40)
    lod_ptrs = [res.u64(base + 0x50 + 8 * i) for i in range(4)]
    lod_dist = res.unpack("4f", base + 0x70)
    name = None
    try:
        name = res.cstr(res.u64(base + 0xA8))
    except Exception:
        pass
    # shader group
    txd_ptr = res.u64(sg + 0x08)
    sh_ptr = res.u64(sg + 0x10)
    sh_count = res.u16(sg + 0x18)
    shaders = [read_shader(res, res.u64(sh_ptr + 8 * i)) for i in range(sh_count)]
    embedded = read_texture_dictionary(res, txd_ptr) if txd_ptr else []
    emb_ptrs = {t["ptr"] for t in embedded}
    emb_names = {t["name"].lower() for t in embedded}
    for sh in shaders:
        ptrs = sh.pop("_tex_ptrs")
        # a parameter that points straight at a texture of the drawable's own dictionary is embedded;
        # anything else is a by-name reference resolved through the archetype's txd (nayzeee_audio_texture)
        sh["texture_source"] = {k: ("embedded" if ptrs.get(k) in emb_ptrs else
                                    "embedded-name" if (v or "").lower() in emb_names else "txd")
                                for k, v in sh["textures"].items() if v}
    lods = {}
    for lname, lp in zip(("high", "med", "low", "vlow"), lod_ptrs):
        if not lp:
            continue
        lptr = res.u64(lp)
        lcount = res.u16(lp + 8)
        models = []
        for mi in range(lcount):
            m = res.u64(lptr + 8 * mi)
            gptr = res.u64(m + 0x08)
            gcount = res.u16(m + 0x10)
            smap_ptr = res.u64(m + 0x20)
            skel_bind = res.u32(m + 0x28)
            smap = res.unpack("%dH" % gcount, smap_ptr) if gcount else ()
            geoms = []
            for gi in range(gcount):
                geo = read_geometry(res, res.u64(gptr + 8 * gi))
                geo["shader_index"] = smap[gi]
                geoms.append(geo)
            models.append({"bone_index": (skel_bind >> 24) & 0xFF, "has_skin": (skel_bind >> 8) & 0xFF,
                           "geometries": geoms})
        lods[lname] = models
    return {"path": path, "name": name, "version": res.version, "bounding_sphere": [round(x, 5) for x in bc],
            "bbox": [[round(x, 5) for x in bmin], [round(x, 5) for x in bmax]],
            "lod_distances": [round(x, 3) for x in lod_dist], "shaders": shaders, "embedded_textures": embedded,
            "lods": lods, "bones": read_bones(res, skel)}


# --------------------------------------------------------------------------- summary json
def summary(d: dict, model: str) -> dict:
    geoms = []
    for lod, models in d["lods"].items():
        for mi, m in enumerate(models):
            for gi, g in enumerate(m["geometries"]):
                sh = d["shaders"][g["shader_index"]]
                c = g["comps"]
                uv = c.get("TexCoord0")
                pos = c["Position"]
                entry = {"lod": lod, "model": mi, "geometry": gi, "bone_index": m["bone_index"],
                         "shader_index": g["shader_index"], "shader": sh["name"],
                         "textures": {k: v for k, v in sh["textures"].items() if v},
                         "texture_source": sh["texture_source"],
                         "vertices": g["vertex_count"], "triangles": int(g["indices"].shape[0]),
                         "layout": g["layout"],
                         "bbox": [[round(float(x), 4) for x in pos.min(0)], [round(float(x), 4) for x in pos.max(0)]]}
                if uv is not None:
                    entry["uv_range"] = [[round(float(x), 4) for x in uv.min(0)], [round(float(x), 4) for x in uv.max(0)]]
                col = c.get("Colour0")
                if col is not None:
                    entry["colour0_mean"] = [round(float(x), 3) for x in col.mean(0)]
                geoms.append(entry)
    usage, ext_usage = {}, {}
    for g in geoms:
        if g["lod"] != "high":
            continue
        for samp, tex in g["textures"].items():
            usage.setdefault(tex.lower(), set()).add(samp)
            if g["texture_source"].get(samp) == "txd":
                ext_usage.setdefault(tex.lower(), set()).add(samp)
    return {"model": model, "source": os.path.basename(d["path"]), "rsc_version": d["version"], "name": d["name"],
            "bbox": d["bbox"], "bounding_sphere": d["bounding_sphere"], "lod_distances": d["lod_distances"],
            "bones": [b["name"] for b in d["bones"]],
            "shaders": [{"index": i, **sh} for i, sh in enumerate(d["shaders"])],
            "embedded_textures": [{k: t[k] for k in ("name", "w", "h", "fmt", "levels")} for t in d["embedded_textures"]],
            "embedded_note": "textures in the drawable's own dictionary; they shadow same-named textures of "
                             "nayzeee_audio_texture and are not part of the shared .ytd",
            "textures_used": {k: sorted(v) for k, v in sorted(usage.items())},
            "txd_textures_used": {k: sorted(v) for k, v in sorted(ext_usage.items())},
            "geometries": geoms}


# --------------------------------------------------------------------------- GLB
GLTF_TO = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])


class _Bin:
    def __init__(self):
        self.data = bytearray()
        self.views, self.accessors = [], []

    def view(self, raw: bytes, target=None) -> int:
        while len(self.data) % 4:
            self.data += b"\0"
        v = {"buffer": 0, "byteOffset": len(self.data), "byteLength": len(raw)}
        if target:
            v["target"] = target
        self.data += raw
        self.views.append(v)
        return len(self.views) - 1

    def acc(self, arr, ctype, atype, target=None, normalized=False, minmax=False) -> int:
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]),
             "type": atype}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = [float(x) for x in arr.min(0)]
            a["max"] = [float(x) for x in arr.max(0)]
        self.accessors.append(a)
        return len(self.accessors) - 1


def _png_bytes(rgba: np.ndarray) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(rgba)).save(buf, format="PNG", compress_level=6)
    return buf.getvalue()


def _shader_pbr(sh: dict) -> dict:
    """Rough PBR guess for a GTA shader (the renderer only needs plausible values)."""
    name = sh["name"].lower()
    p = {k.lower(): v for k, v in sh["params"].items()}
    spec = (p.get("specularintensitymult") or [0.3])[0]
    falloff = (p.get("specularfalloffmult") or [30.0])[0]
    rough = float(np.clip(1.0 - np.log2(max(falloff, 1.0)) / 9.0, 0.18, 0.9))
    out = {"metallic": 0.0, "roughness": rough, "spec": spec, "emissive": 0.0}
    if name.startswith("emissive") or name == "decal_emissive_only":
        out["emissive"] = float((p.get("emissivemultiplier") or [1.0])[0])
    return out


def build_glb(d: dict, model: str, textures: dict, replace: dict | None = None, lod: str = "high",
              emissive_boost: float = 1.0, emissive_override: np.ndarray | None = None) -> bytes:
    """textures: lower-name -> rgba (uint8).  replace: lower-name -> rgba used instead."""
    replace = {k.lower(): v for k, v in (replace or {}).items()}
    texs = dict(textures)
    for t in d["embedded_textures"]:
        if t["rgba"] is not None:
            texs.setdefault(t["name"].lower(), t["rgba"])
    b = _Bin()
    images, gtex, tindex, mats, prims = [], [], {}, [], []

    def tex(key: str, arr_fn):
        if key not in tindex:
            vi = b.view(_png_bytes(arr_fn()))
            images.append({"bufferView": vi, "mimeType": "image/png", "name": key})
            gtex.append({"source": len(images) - 1, "sampler": 0})
            tindex[key] = len(gtex) - 1
        return tindex[key]

    def lookup(name):
        if not name:
            return None
        n = name.lower()
        if n in replace:
            return replace[n]
        return texs.get(n)

    mat_index = {}
    for si, sh in enumerate(d["shaders"]):
        pb = _shader_pbr(sh)
        mj = {"name": f"{si}_{sh['name']}", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
              "metallicFactor": pb["metallic"], "roughnessFactor": pb["roughness"]}}
        t = {k.lower(): v for k, v in sh["textures"].items() if v}
        diff = t.get("diffusesampler") or t.get("texturesamp")
        bump = t.get("bumpsampler")
        img = lookup(diff)
        if img is not None:
            key = diff.lower() + ("@r" if diff.lower() in replace else "")
            ti = tex(key, lambda a=img: a)
            mj["pbrMetallicRoughness"]["baseColorTexture"] = {"index": ti}
            if pb["emissive"] > 0:
                if emissive_override is not None and diff.lower() == "emissive4":
                    ti = tex("emissive@override", lambda: emissive_override)
                    mj["pbrMetallicRoughness"]["baseColorTexture"] = {"index": ti}
                mj["emissiveTexture"] = {"index": ti}
            sname = sh["name"].lower()
            if sname.startswith("decal"):
                mj["alphaMode"] = "BLEND"                  # decals: texture alpha over the surface below
                if sname == "decal_emissive_only":        # adds light only: no diffuse of its own
                    mj["pbrMetallicRoughness"]["baseColorFactor"] = [0.0, 0.0, 0.0, 1.0]
            elif img.shape[2] == 4 and img[..., 3].min() < 250 and "alpha" in sname:
                mj["alphaMode"] = "MASK"
        nimg = lookup(bump)
        if nimg is not None:
            def gl_normal(a=nimg):
                o = a.copy()
                o[..., 1] = 255 - o[..., 1]
                o[..., 3] = 255
                return o
            ti = tex(bump.lower() + "@gl", gl_normal)
            bmp = ({k.lower(): v for k, v in sh["params"].items()}.get("bumpiness") or [1.0])[0]
            mj["normalTexture"] = {"index": ti, "scale": float(bmp)}
        if pb["emissive"] > 0:
            # GTA's EmissiveMultiplier (0.05..1) is not a physical unit; map it to a visible glow for previews.
            # The strip's own diffuse is dimmed so a lit LED keeps its hue instead of washing out to white.
            if not sh["name"].lower().startswith("decal"):
                mj["pbrMetallicRoughness"]["baseColorFactor"] = [0.3, 0.3, 0.3, 1.0]
            strength = (0.6 + pb["emissive"]) * emissive_boost
            mj["emissiveFactor"] = [1.0, 1.0, 1.0]
            if strength > 1.0:
                mj["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": float(strength)}}
        mat_index[si] = len(mats)
        mats.append(mj)

    for mi, m in enumerate(d["lods"].get(lod, [])):
        bone_m = None
        bi = m["bone_index"]
        if bi and bi < len(d["bones"]) and "m" in d["bones"][bi]:
            bone_m = d["bones"][bi]["m"]
        for gi, g in enumerate(m["geometries"]):
            c = g["comps"]
            pos = c["Position"][:, :3].copy()
            nrm = c["Normal"][:, :3].copy() if "Normal" in c else None
            if bone_m is not None:
                R, T = bone_m[:3, :3], bone_m[3, :3]
                pos = pos @ R + T
                if nrm is not None:
                    nrm = nrm @ R
            attrs = {"POSITION": b.acc((pos @ GLTF_TO.T).astype(np.float32), 5126, "VEC3", 34962, minmax=True)}
            if nrm is not None:
                nl = np.linalg.norm(nrm, axis=1, keepdims=True)
                nrm = nrm / np.maximum(nl, 1e-8)
                attrs["NORMAL"] = b.acc((nrm @ GLTF_TO.T).astype(np.float32), 5126, "VEC3", 34962)
            if "TexCoord0" in c:
                attrs["TEXCOORD_0"] = b.acc(c["TexCoord0"][:, :2].astype(np.float32), 5126, "VEC2", 34962)
            if "Tangent" in c and c["Tangent"].shape[1] == 4:
                tg = c["Tangent"].copy()
                tg[:, :3] = tg[:, :3] @ GLTF_TO.T
                tl = np.linalg.norm(tg[:, :3], axis=1, keepdims=True)
                tg[:, :3] /= np.maximum(tl, 1e-8)
                tg[:, 3] = np.where(tg[:, 3] < 0, -1.0, 1.0)
                attrs["TANGENT"] = b.acc(tg.astype(np.float32), 5126, "VEC4", 34962)
            idx = g["indices"].reshape(-1)
            ia = b.acc(idx.astype(np.uint16 if g["vertex_count"] < 65536 else np.uint32).reshape(-1, 1),
                       5123 if g["vertex_count"] < 65536 else 5125, "SCALAR", 34963)
            prims.append({"attributes": attrs, "indices": ia, "material": mat_index[g["shader_index"]], "mode": 4})

    gltf = {"asset": {"version": "2.0", "generator": "nayzeee-speaker-assets legacy_reader"}, "scene": 0,
            "scenes": [{"nodes": [0], "name": model}], "nodes": [{"mesh": 0, "name": model}],
            "meshes": [{"name": model, "primitives": prims}], "materials": mats,
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "buffers": [{"byteLength": 0}], "bufferViews": b.views, "accessors": b.accessors}
    if images:
        gltf["images"], gltf["textures"] = images, gtex
    if any("extensions" in m for m in mats):
        gltf["extensionsUsed"] = ["KHR_materials_emissive_strength"]
    while len(b.data) % 4:
        b.data += b"\0"
    gltf["buffers"][0]["byteLength"] = len(b.data)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    out = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(b.data))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(b.data), b"BIN\0") + bytes(b.data)
    return out


# --------------------------------------------------------------------------- CLI
def load_rgba(path: str) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stream", default=STREAM, help="folder with the .ydr files and the .ytd")
    ap.add_argument("--out", default=OUT_DIR, help="output folder for <model>.json / <model>.glb")
    ap.add_argument("--models", nargs="*", default=MODELS)
    ap.add_argument("--replace", nargs="*", default=[], metavar="TEX=PNG", help="preview a texture replacement")
    ap.add_argument("--glb-out", help="with one model: write the GLB here (json is not written)")
    ap.add_argument("--emissive-boost", type=float, default=1.0)
    ap.add_argument("--dump-textures", metavar="DIR", help="write every .ytd texture as PNG into DIR")
    ap.add_argument("--print", action="store_true", help="print the per-geometry texture usage")
    a = ap.parse_args(argv)

    ytd = read_ytd(os.path.join(a.stream, YTD))
    textures = {k: t["rgba"] for k, t in ytd.items() if t["rgba"] is not None}
    if a.dump_textures:
        os.makedirs(a.dump_textures, exist_ok=True)
        for k, t in ytd.items():
            if t["rgba"] is not None:
                Image.fromarray(t["rgba"]).save(os.path.join(a.dump_textures, f"{t['name']}.png"))
    replace = {}
    for r in a.replace:
        k, v = r.split("=", 1)
        replace[k.lower()] = load_rgba(v)
    os.makedirs(a.out, exist_ok=True)
    for model in a.models:
        d = read_ydr(os.path.join(a.stream, model + ".ydr"))
        glb = build_glb(d, model, textures, replace, emissive_boost=a.emissive_boost)
        if a.glb_out:
            with open(a.glb_out, "wb") as f:
                f.write(glb)
        else:
            s = summary(d, model)
            with open(os.path.join(a.out, model + ".json"), "w", encoding="utf-8") as f:
                json.dump(s, f, indent=1)
            with open(os.path.join(a.out, model + ".glb"), "wb") as f:
                f.write(glb)
        if a.print or not a.glb_out:
            s = summary(d, model)
            print(f"{model}: v{d['version']} shaders={len(d['shaders'])} high geoms="
                  f"{sum(len(m['geometries']) for m in d['lods'].get('high', []))} lods={list(d['lods'])} "
                  f"bones={len(d['bones'])} embedded={[t['name'] for t in d['embedded_textures']]}")
            if a.print:
                for g in s["geometries"]:
                    if g["lod"] == "high":
                        src = {k: g["texture_source"].get(k, "?")[0] for k in g["textures"]}
                        print(f"   m{g['model']}g{g['geometry']} bone{g['bone_index']} {g['shader']:20s} "
                              f"v{g['vertices']:5d} t{g['triangles']:5d} {g['textures']} src={src} uv={g.get('uv_range')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
