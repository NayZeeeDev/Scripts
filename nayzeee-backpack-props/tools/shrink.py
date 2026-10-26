#!/usr/bin/env python3
"""
Resize a .dds to <size> and re-encode as DXT5 (DXT1 when fully opaque)
with a full mip chain.

  python3 shrink.py <in.dds> <out.dds> [size=1024]
"""
import io
import struct
import sys

from PIL import Image


def level_bytes(im, fmt):
    b = io.BytesIO()
    im.save(b, 'DDS', pixel_format=fmt)
    data = b.getvalue()
    if data[84:88] == b'DX10':
        return data[148:]
    return data[128:]


def main():
    src, dst = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    im = Image.open(src).convert('RGBA')
    if im.width > size or im.height > size:
        im = im.resize((min(size, im.width), min(size, im.height)), Image.LANCZOS)
    opaque = im.getchannel('A').getextrema()[0] >= 250
    fmt = 'DXT1' if opaque else 'DXT5'

    levels = []
    w, h = im.size
    cur = im
    while True:
        levels.append(level_bytes(cur, fmt))
        if w <= 4 and h <= 4:
            break
        w, h = max(1, w // 2), max(1, h // 2)
        cur = im.resize((max(4, w), max(4, h)), Image.LANCZOS)

    # header from the top level, then mark it as a mip chain
    b = io.BytesIO()
    im.save(b, 'DDS', pixel_format=fmt)
    head = bytearray(b.getvalue()[:128])
    flags = struct.unpack_from('<I', head, 8)[0] | 0x20000          # DDSD_MIPMAPCOUNT
    struct.pack_into('<I', head, 8, flags)
    struct.pack_into('<I', head, 28, len(levels))                    # dwMipMapCount
    caps = struct.unpack_from('<I', head, 108)[0] | 0x400008         # COMPLEX | MIPMAP
    struct.pack_into('<I', head, 108, caps)

    with open(dst, 'wb') as f:
        f.write(head)
        for lv in levels:
            f.write(lv)
    print(f'{dst}: {im.width}x{im.height} {fmt} {len(levels)} mips')


if __name__ == '__main__':
    main()
