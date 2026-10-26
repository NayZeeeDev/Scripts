"""DDS (DirectX 9 FourCC) writer/reader with numpy BC1 (DXT1) and BC3 (DXT5) codecs.

The header matches what CodeWalker's DDSIO.GetTexture parses (and what its
own _EncodeDDSHeader writes): magic "DDS ", 124-byte header,
flags = CAPS|HEIGHT|WIDTH|PIXELFORMAT|MIPMAPCOUNT|LINEARSIZE, linear size of
the top mip, pixel format size 32 with DDPF_FOURCC and 'DXT1'/'DXT5',
caps = TEXTURE (|COMPLEX|MIPMAP when there are mips).  Everything after the
128-byte header is the mip chain, nothing else (CodeWalker reads the rest of
the file as texture data).

Mip chains stop at 4 px on the shortest side (one BC block), the GTA convention
and the size math CodeWalker uses for resource texture data.

    write_dds(path, rgb_or_rgba_float_image, fmt="DXT1", kind="color")
    info, levels = read_dds(path)      # levels: list of uint8 (h, w, 4)
    psnr(a, b)
"""
from __future__ import annotations

import struct

import numpy as np

DDS_MAGIC = 0x20534444
DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT = 0x1, 0x2, 0x4, 0x1000
DDSD_MIPMAPCOUNT, DDSD_LINEARSIZE = 0x20000, 0x80000
DDPF_FOURCC = 0x4
DDSCAPS_COMPLEX, DDSCAPS_TEXTURE, DDSCAPS_MIPMAP = 0x8, 0x1000, 0x400000
FOURCC = {"DXT1": b"DXT1", "DXT5": b"DXT5"}
BLOCK_BYTES = {"DXT1": 8, "DXT5": 16}


# --------------------------------------------------------------------------- colour helpers
def _srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def _down2(a: np.ndarray) -> np.ndarray:
    h, w = a.shape[:2]
    return a.reshape(h // 2, 2, w // 2, 2, *a.shape[2:]).mean(axis=(1, 3))


def mip_chain(img: np.ndarray, kind: str = "color", min_size: int = 4):
    """List of float images (0..1), level 0 first, down to ``min_size`` on the short side.

    kind 'color'/'emissive': sRGB-correct, alpha-weighted averaging.
    kind 'normal': averaged vectors re-normalised.  kind 'spec': plain average.
    """
    a = np.asarray(img, dtype=np.float64)
    levels = [a]
    while min(a.shape[0], a.shape[1]) // 2 >= min_size:
        if kind == "normal":
            v = a[:, :, :3] * 2 - 1
            v = _down2(v)
            v /= np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-8)
            n = v * 0.5 + 0.5
            a = np.concatenate([n, _down2(a[:, :, 3:])], axis=2) if a.shape[2] == 4 else n
        elif kind in ("color", "emissive"):
            lin = _srgb_to_linear(a[:, :, :3])
            if a.shape[2] == 4:
                al = a[:, :, 3:4]
                s = _down2(lin * al)
                wsum = _down2(al)
                plain = _down2(lin)
                col = np.where(wsum > 1e-6, s / np.maximum(wsum, 1e-6), plain)
                a = np.concatenate([_linear_to_srgb(col), wsum], axis=2)
            else:
                a = _linear_to_srgb(_down2(lin))
        else:
            a = _down2(a)
        levels.append(a)
    return levels


# --------------------------------------------------------------------------- BC1 colour blocks
def _to_blocks(img: np.ndarray) -> np.ndarray:
    h, w, c = img.shape
    return img.reshape(h // 4, 4, w // 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(-1, 16, c)


def _from_blocks(blk: np.ndarray, h: int, w: int) -> np.ndarray:
    c = blk.shape[2]
    return blk.reshape(h // 4, w // 4, 4, 4, c).transpose(0, 2, 1, 3, 4).reshape(h, w, c)


def _quant565(c: np.ndarray):
    """float RGB 0..255 -> (packed uint16, dequantised float RGB as the GPU expands it)."""
    r = np.clip(np.rint(c[..., 0] * 31 / 255), 0, 31).astype(np.int64)
    g = np.clip(np.rint(c[..., 1] * 63 / 255), 0, 63).astype(np.int64)
    b = np.clip(np.rint(c[..., 2] * 31 / 255), 0, 31).astype(np.int64)
    packed = (r << 11) | (g << 5) | b
    return packed, _unpack565(packed)


def _unpack565(p: np.ndarray) -> np.ndarray:
    p = np.asarray(p, dtype=np.int64)
    r = (p >> 11) & 31
    g = (p >> 5) & 63
    b = p & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=-1).astype(np.float64)


def _palette4(c0: np.ndarray, c1: np.ndarray) -> np.ndarray:
    """4-colour BC1 palette (B,4,3) with the integer rounding hardware/decoders use."""
    p2 = np.floor((2 * c0 + c1) / 3)
    p3 = np.floor((c0 + 2 * c1) / 3)
    return np.stack([c0, c1, p2, p3], axis=1)


def _assign(blk: np.ndarray, pal: np.ndarray):
    d = ((blk[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(axis=3)    # (B,16,4)
    idx = d.argmin(axis=2)
    err = np.take_along_axis(d, idx[:, :, None], axis=2)[:, :, 0].sum(axis=1)
    return idx, err


_W = np.array([[1.0, 0.0], [0.0, 1.0], [2 / 3, 1 / 3], [1 / 3, 2 / 3]])


def encode_bc1_colors(blk: np.ndarray):
    """blk (B,16,3) float 0..255 -> (c0 uint16, c1 uint16, idx (B,16)) in 4-colour mode."""
    B = blk.shape[0]
    mean = blk.mean(axis=1)
    cen = blk - mean[:, None, :]
    cov = np.einsum("bki,bkj->bij", cen, cen)
    v = blk.max(axis=1) - blk.min(axis=1) + 1e-3
    for _ in range(8):
        v = np.einsum("bij,bj->bi", cov, v)
        v /= np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-12)
    flat = np.linalg.norm(v, axis=1) < 1e-9
    v[flat] = [0.57735, 0.57735, 0.57735]
    proj = np.einsum("bki,bi->bk", cen, v)
    # endpoint candidates: principal axis extremes (inset), bounding-box diagonal,
    # and the two most distant pixels along the axis
    lo_pca = mean + proj.min(axis=1)[:, None] * v
    hi_pca = mean + proj.max(axis=1)[:, None] * v
    inset = (hi_pca - lo_pca) / 16.0
    bi = np.arange(B)
    cands = [(hi_pca - inset, lo_pca + inset), (hi_pca, lo_pca),
             (blk.max(axis=1), blk.min(axis=1)),
             (blk[bi, proj.argmax(axis=1)], blk[bi, proj.argmin(axis=1)])]
    best = None

    def consider(hi, lo, best):
        p0, q0 = _quant565(np.clip(hi, 0, 255))
        p1, q1 = _quant565(np.clip(lo, 0, 255))
        idx, err = _assign(blk, _palette4(q0, q1))
        cand = (p0, p1, idx, err)
        if best is None:
            return cand
        better = cand[3] < best[3]
        return tuple(np.where(better[:, None] if x.ndim == 2 else better, x, y) for x, y in zip(cand, best))

    for hi, lo in cands:
        best = consider(hi, lo, best)
    for it in range(4):
        # least-squares refit of the endpoints given the current best indices
        idx = best[2]
        wts = _W[idx]                                       # (B,16,2)
        A = np.einsum("bki,bkj->bij", wts, wts)              # (B,2,2)
        rhs = np.einsum("bki,bkc->bic", wts, blk)            # (B,2,3)
        det = A[:, 0, 0] * A[:, 1, 1] - A[:, 0, 1] * A[:, 1, 0]
        ok = np.abs(det) > 1e-9
        inv = np.zeros_like(A)
        inv[:, 0, 0] = A[:, 1, 1]
        inv[:, 1, 1] = A[:, 0, 0]
        inv[:, 0, 1] = -A[:, 0, 1]
        inv[:, 1, 0] = -A[:, 1, 0]
        inv /= np.where(ok, det, 1.0)[:, None, None]
        sol = np.einsum("bij,bjc->bic", inv, rhs)
        if not ok.any():
            break
        hi = np.where(ok[:, None], sol[:, 0], _unpack565(best[0]))
        lo = np.where(ok[:, None], sol[:, 1], _unpack565(best[1]))
        best = consider(hi, lo, best)
    p0, p1, idx, _ = best
    # enforce c0 > c1 (4-colour mode); swap endpoints and remap indices when needed
    swap = p0 < p1
    remap = np.array([1, 0, 3, 2])
    p0, p1 = np.where(swap, p1, p0), np.where(swap, p0, p1)
    idx = np.where(swap[:, None], remap[idx], idx)
    eq = p0 == p1
    idx[eq] = 0
    return p0.astype(np.uint16), p1.astype(np.uint16), idx.astype(np.int64)


def _pack_indices(idx: np.ndarray, bits: int) -> np.ndarray:
    sh = (np.arange(16, dtype=np.uint64) * bits)[None, :]
    return (idx.astype(np.uint64) << sh).sum(axis=1, dtype=np.uint64)


def encode_bc1(img_u8: np.ndarray) -> bytes:
    """(h, w, 3|4) uint8 -> BC1 bytes (opaque, 4-colour blocks)."""
    h, w = img_u8.shape[:2]
    blk = _to_blocks(img_u8[:, :, :3].astype(np.float64))
    c0, c1, idx = encode_bc1_colors(blk)
    bits = _pack_indices(idx, 2).astype(np.uint32)
    out = np.zeros(len(blk), dtype=[("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    out["c0"], out["c1"], out["i"] = c0, c1, bits
    return out.tobytes()


def _encode_alpha(a: np.ndarray):
    """a (B,16) float 0..255 -> (a0, a1, idx (B,16)) using the 8-value mode (a0 > a1)."""
    a0 = np.clip(np.rint(a.max(axis=1)), 0, 255)
    a1 = np.clip(np.rint(a.min(axis=1)), 0, 255)
    same = a0 == a1
    pal = np.stack([a0, a1] + [((7 - k) * a0 + k * a1) // 7 for k in range(1, 7)], axis=1)   # k=1..6 -> idx 2..7
    d = np.abs(a[:, :, None] - pal[:, None, :])
    idx = d.argmin(axis=2)
    idx[same] = 0
    return a0.astype(np.uint8), a1.astype(np.uint8), idx


def encode_bc3(img_u8: np.ndarray) -> bytes:
    """(h, w, 4) uint8 -> BC3 bytes."""
    blk = _to_blocks(img_u8.astype(np.float64))
    a0, a1, aidx = _encode_alpha(blk[:, :, 3])
    abits = _pack_indices(aidx, 3)
    c0, c1, idx = encode_bc1_colors(blk[:, :, :3])
    cbits = _pack_indices(idx, 2).astype(np.uint32)
    n = len(blk)
    out = np.zeros(n, dtype=[("a0", "u1"), ("a1", "u1"), ("ai", "u1", 6), ("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    out["a0"], out["a1"] = a0, a1
    ab = np.zeros((n, 6), dtype=np.uint8)
    for k in range(6):
        ab[:, k] = ((abits >> np.uint64(8 * k)) & np.uint64(0xFF)).astype(np.uint8)
    out["ai"] = ab
    out["c0"], out["c1"], out["i"] = c0, c1, cbits
    return out.tobytes()


# --------------------------------------------------------------------------- decoders
def decode_bc1(data: bytes, w: int, h: int) -> np.ndarray:
    """BC1 bytes -> (h, w, 4) uint8 (handles 3-colour/transparent blocks)."""
    n = (w // 4) * (h // 4)
    arr = np.frombuffer(data, dtype=[("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")], count=n)
    c0 = _unpack565(arr["c0"])
    c1 = _unpack565(arr["c1"])
    four = arr["c0"] > arr["c1"]
    p2 = np.where(four[:, None], np.floor((2 * c0 + c1) / 3), np.floor((c0 + c1) / 2))
    p3 = np.where(four[:, None], np.floor((c0 + 2 * c1) / 3), 0)
    pal = np.stack([c0, c1, p2, p3], axis=1)
    alpha = np.ones((n, 4)) * 255
    alpha[~four, 3] = 0
    idx = ((arr["i"][:, None].astype(np.uint64) >> (np.arange(16, dtype=np.uint64) * 2)) & np.uint64(3)).astype(int)
    rgb = np.take_along_axis(pal, idx[:, :, None].repeat(3, axis=2), axis=1)
    al = np.take_along_axis(alpha, idx, axis=1)
    blk = np.concatenate([rgb, al[:, :, None]], axis=2)
    return _from_blocks(blk, h, w).astype(np.uint8)


def decode_bc3(data: bytes, w: int, h: int) -> np.ndarray:
    n = (w // 4) * (h // 4)
    arr = np.frombuffer(data, dtype=[("a0", "u1"), ("a1", "u1"), ("ai", "u1", 6), ("c0", "<u2"), ("c1", "<u2"),
                                     ("i", "<u4")], count=n)
    a0 = arr["a0"].astype(np.int64)
    a1 = arr["a1"].astype(np.int64)
    eight = a0 > a1
    pal = np.zeros((n, 8))
    pal[:, 0], pal[:, 1] = a0, a1
    for k in range(1, 7):
        pal[:, 1 + k] = np.where(eight, ((7 - k) * a0 + k * a1) // 7, 0)
    for k in range(1, 5):
        pal[:, 1 + k] = np.where(eight, pal[:, 1 + k], ((5 - k) * a0 + k * a1) // 5)
    pal[:, 6] = np.where(eight, pal[:, 6], 0)
    pal[:, 7] = np.where(eight, pal[:, 7], 255)
    bits = np.zeros(n, dtype=np.uint64)
    for k in range(6):
        bits |= arr["ai"][:, k].astype(np.uint64) << np.uint64(8 * k)
    aidx = ((bits[:, None] >> (np.arange(16, dtype=np.uint64) * 3)) & np.uint64(7)).astype(int)
    al = np.take_along_axis(pal, aidx, axis=1)
    c0 = _unpack565(arr["c0"])
    c1 = _unpack565(arr["c1"])
    cpal = _palette4(c0, c1)       # BC3 colour blocks are always 4-colour
    idx = ((arr["i"][:, None].astype(np.uint64) >> (np.arange(16, dtype=np.uint64) * 2)) & np.uint64(3)).astype(int)
    rgb = np.take_along_axis(cpal, idx[:, :, None].repeat(3, axis=2), axis=1)
    blk = np.concatenate([rgb, al[:, :, None]], axis=2)
    return _from_blocks(blk, h, w).astype(np.uint8)


# --------------------------------------------------------------------------- DDS container
def dds_header(w: int, h: int, mips: int, fmt: str) -> bytes:
    linear = (max(1, w // 4) * max(1, h // 4)) * BLOCK_BYTES[fmt]
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT | DDSD_LINEARSIZE
    caps = DDSCAPS_TEXTURE | ((DDSCAPS_COMPLEX | DDSCAPS_MIPMAP) if mips > 1 else 0)
    hdr = struct.pack("<I", DDS_MAGIC)
    hdr += struct.pack("<7I", 124, flags, h, w, linear, 1, mips)
    hdr += b"\x00" * 44                                            # dwReserved1[11]
    hdr += struct.pack("<2I4s5I", 32, DDPF_FOURCC, FOURCC[fmt], 0, 0, 0, 0, 0)
    hdr += struct.pack("<5I", caps, 0, 0, 0, 0)
    assert len(hdr) == 128
    return hdr


def to_u8(img: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(np.asarray(img, dtype=np.float64) * 255.0), 0, 255).astype(np.uint8)


def encode_dds(img: np.ndarray, fmt: str = "DXT1", kind: str = "color", min_size: int = 4):
    """Float image (h, w, 3|4) in 0..1 -> (dds bytes, mip count)."""
    a = np.asarray(img, dtype=np.float64)
    h, w = a.shape[:2]
    if h % 4 or w % 4:
        raise ValueError("DDS block textures need sizes that are multiples of 4")
    if fmt == "DXT5" and a.shape[2] == 3:
        a = np.concatenate([a, np.ones((h, w, 1))], axis=2)
    levels = mip_chain(a, kind, min_size)
    body = b""
    for lv in levels:
        u8 = to_u8(lv)
        body += encode_bc3(u8) if fmt == "DXT5" else encode_bc1(u8)
    return dds_header(w, h, len(levels), fmt) + body, len(levels)


def write_dds(path: str, img: np.ndarray, fmt: str = "DXT1", kind: str = "color", min_size: int = 4) -> int:
    data, mips = encode_dds(img, fmt, kind, min_size)
    with open(path, "wb") as f:
        f.write(data)
    return mips


def parse_header(data: bytes) -> dict:
    """Parse a DDS header exactly like CodeWalker's DXTex._ReadDDSHeader + GetTexture."""
    if len(data) < 128:
        raise ValueError("file too small for a DDS header")
    magic, = struct.unpack_from("<I", data, 0)
    if magic != DDS_MAGIC:
        raise ValueError("Invalid DDS magic!")
    size, flags, h, w, pitch, depth, mips = struct.unpack_from("<7I", data, 4)
    pf_size, pf_flags, fourcc = struct.unpack_from("<2I4s", data, 76)
    caps, caps2 = struct.unpack_from("<2I", data, 108)
    if size != 124 or pf_size != 32:
        raise ValueError("Invalid DDS header size")
    if not (pf_flags & DDPF_FOURCC) or fourcc not in (b"DXT1", b"DXT5"):
        raise ValueError(f"unsupported pixel format {fourcc!r} (pipeline writes DXT1/DXT5 only)")
    fmt = fourcc.decode()
    return {"width": w, "height": h, "mips": max(1, mips), "format": fmt, "flags": flags, "caps": caps,
            "linear_size": pitch, "data_offset": 128}


def level_sizes(w: int, h: int, mips: int, fmt: str):
    out = []
    for i in range(mips):
        lw, lh = max(1, w >> i), max(1, h >> i)
        out.append((lw, lh, max(1, (lw + 3) // 4) * max(1, (lh + 3) // 4) * BLOCK_BYTES[fmt]))
    return out


def read_dds(path_or_bytes, decode_levels: int | None = None):
    """Return (header dict, [uint8 (h, w, 4) per decoded level]).  Raises on size mismatch."""
    data = path_or_bytes if isinstance(path_or_bytes, (bytes, bytearray)) else open(path_or_bytes, "rb").read()
    info = parse_header(data)
    sizes = level_sizes(info["width"], info["height"], info["mips"], info["format"])
    expected = 128 + sum(s for _, _, s in sizes)
    if len(data) != expected:
        raise ValueError(f"DDS data size {len(data)} != expected {expected} for {info['mips']} mips")
    out = []
    off = 128
    n = info["mips"] if decode_levels is None else min(decode_levels, info["mips"])
    for i, (lw, lh, sz) in enumerate(sizes):
        if i >= n:
            break
        chunk = data[off:off + sz]
        out.append(decode_bc3(chunk, lw, lh) if info["format"] == "DXT5" else decode_bc1(chunk, lw, lh))
        off += sz
    return info, out


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    mse = float(((a - b) ** 2).mean())
    return float("inf") if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)
