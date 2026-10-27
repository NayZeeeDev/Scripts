"""
nzprops.dds - DXT1 / DXT5 DDS writer with a full mip chain (Pillow's BC1/BC3 encoder).
"""
from __future__ import annotations

import io
import struct

import numpy as np
from PIL import Image

DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT = 0x1, 0x2, 0x4, 0x1000
DDSD_MIPMAPCOUNT, DDSD_LINEARSIZE = 0x20000, 0x80000
DDPF_FOURCC = 0x4
DDSCAPS_COMPLEX, DDSCAPS_TEXTURE, DDSCAPS_MIPMAP = 0x8, 0x1000, 0x400000

FORMATS = {"DXT1": "D3DFMT_DXT1", "DXT5": "D3DFMT_DXT5"}


def _encode_level(img: Image.Image, fmt: str) -> bytes:
    w, h = img.size
    block = 8 if fmt == "DXT1" else 16
    nblocks = ((w + 3) // 4) * ((h + 3) // 4)
    src = img
    if w % 4 or h % 4:
        arr = np.asarray(img.convert("RGBA"))
        arr = np.pad(arr, ((0, (-h) % 4), (0, (-w) % 4), (0, 0)), mode="edge")
        src = Image.fromarray(arr, "RGBA")
    b = io.BytesIO()
    src.save(b, "DDS", pixel_format=fmt)
    data = b.getvalue()[128:]
    return data[: nblocks * block]


def mip_chain(img: Image.Image, min_size=1, renormalize=False):
    """Full mip chain down to 1x1 (tiny levels are padded to whole 4x4 blocks when encoded)."""
    img = img.convert("RGBA")
    levels = [img]
    w, h = img.size
    while max(w, h) > min_size:
        w, h = max(1, w // 2), max(1, h // 2)
        lv = img.resize((w, h), Image.LANCZOS if w >= 16 else Image.BOX)
        if renormalize:
            a = np.asarray(lv, np.float32)
            n = a[..., :3] / 127.5 - 1.0
            n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
            a[..., :3] = (n + 1.0) * 127.5
            lv = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        levels.append(lv)
    return levels


def write_dds(path: str, img: Image.Image, fmt: str = "DXT1", normal_map=False) -> int:
    """Write `img` as DDS with mips. Returns the number of mip levels."""
    assert fmt in FORMATS
    levels = mip_chain(img, renormalize=normal_map)
    blobs = [_encode_level(lv, fmt) for lv in levels]
    w, h = levels[0].size
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT | DDSD_LINEARSIZE
    header = struct.pack("<4sIIIIIII", b"DDS ", 124, flags, h, w, len(blobs[0]), 0, len(blobs))
    header += b"\x00" * 44
    header += struct.pack("<II4sIIIII", 32, DDPF_FOURCC, fmt.encode("ascii"), 0, 0, 0, 0, 0)
    header += struct.pack("<IIIII", DDSCAPS_COMPLEX | DDSCAPS_TEXTURE | DDSCAPS_MIPMAP, 0, 0, 0, 0)
    from .fsutil import write_bytes
    write_bytes(path, header + b"".join(blobs))
    return len(blobs)
