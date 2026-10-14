#!/usr/bin/env python3
"""
import_model.py - bring a third-party .ydr into the resource under its own model name.

    python3 tools/props/import_model.py <source.ydr> <new_name> [--stream nayzeee-ambulance/stream]
                                        [--lod 100] [--hd 15] [--static] [--max-size 2048]
                                        [--title "Medic bag (red)"] [--module props.external]

What it does (nothing is ever modified in the source file):

  1. loads the drawable with cwtool and re-exports it to CodeWalker XML + its embedded textures,
  2. renames the drawable and every embedded texture to `<new_name>` / `<new_name>_<texture>` so the
     model never collides with the native prop it was made for (or with other resources that
     stream the same replacement),
  3. re-encodes textures for streaming: uncompressed ARGB becomes DXT1 (opaque) or DXT5 (alpha),
     every texture gets a full mip chain (no shimmer at distance, a fraction of the memory),
     optionally capped at --max-size,
  4. rebuilds the .ydr, re-loads and validates it,
  5. writes `tools/props/external/<new_name>.json` (bounds + archetype) so build.py puts the model
     into nz_amb_props.ytyp and never deletes it as "stale",
  6. regenerates nz_amb_props.ytyp and copies the .ydr into --stream.

The source file is only read. Keep the original files outside the repository.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

from nzprops.cwxml import archetype_xml  # noqa: E402
from nzprops.dds import write_dds  # noqa: E402
from nzprops.prop import FLAG_STATIC  # noqa: E402

EXTERNAL = os.path.join(HERE, "external")


def log(msg):
    print(f"[import] {msg}", flush=True)


def vec(s):
    m = re.findall(r"[XYZ]:(-?[\d.eE+-]+)", s)
    return [float(v) for v in m]


def read_dds(path: str) -> Image.Image:
    """Top mip of a DDS as RGBA (uncompressed A8R8G8B8 / X8R8G8B8 or DXT1/3/5 via Pillow)."""
    b = open(path, "rb").read()
    h, w = struct_u32(b, 12), struct_u32(b, 16)
    fourcc = b[84:88]
    if fourcc in (b"DXT1", b"DXT3", b"DXT5"):
        im = Image.open(io.BytesIO(b))
        im.load()
        return im.convert("RGBA")
    bits = struct_u32(b, 88)
    if bits != 32:
        raise SystemExit(f"{os.path.basename(path)}: unsupported DDS pixel format ({bits} bpp, fourcc {fourcc!r})")
    px = np.frombuffer(b[128:128 + w * h * 4], dtype=np.uint8).reshape(h, w, 4)
    return Image.fromarray(px[..., [2, 1, 0, 3]].copy(), "RGBA")


def struct_u32(b, off):
    return int.from_bytes(b[off:off + 4], "little")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("name")
    ap.add_argument("--stream", default=None)
    ap.add_argument("--work", default="/tmp/nza-work/props")
    ap.add_argument("--out", default=None, help="build folder (default <work>/out)")
    ap.add_argument("--lod", type=float, default=100.0)
    ap.add_argument("--hd", type=float, default=15.0)
    ap.add_argument("--static", action="store_true")
    ap.add_argument("--max-size", type=int, default=2048)
    ap.add_argument("--title", default="")
    ap.add_argument("--module", default="props.external")
    ap.add_argument("--credit", default="", help="who made the model (stored in the manifest)")
    ap.add_argument("--keep", action="store_true", help="keep the temp folder")
    args = ap.parse_args()

    import build  # noqa: E402  (reuses the cwtool build + ytyp writer)

    name = args.name.lower()
    if not re.fullmatch(r"[a-z0-9_]+", name):
        raise SystemExit("model name: lowercase letters, digits and _ only")
    cw = build.ensure_cwtool(args.work)
    tmp = tempfile.mkdtemp(prefix=f"import_{name}_")
    xml_in = os.path.join(tmp, "in.ydr.xml")
    r = subprocess.run(cw + ["inspect", os.path.abspath(args.source), xml_in], capture_output=True, text=True)
    if not os.path.exists(xml_in):
        print(r.stdout[-2000:], r.stderr[-2000:])
        raise SystemExit("could not load the source drawable")
    xml = open(xml_in, encoding="utf-8").read()

    # ---- rename drawable + textures --------------------------------------------------------
    xml = re.sub(r"(<Drawable>\s*<Name>)[^<]*(</Name>)", rf"\g<1>{name}\g<2>", xml, count=1)
    texdir = os.path.join(tmp, name)
    os.makedirs(texdir)
    items = re.findall(r"<Item>\s*<Name>([^<]+)</Name>\s*<Unk32[^>]*/>\s*<Usage>", xml)
    tex_summary = []
    for old in items:
        new = f"{name}_{old}".lower()
        if len(new) > 60:
            new = new[:60]
        src_dds = os.path.join(tmp, old + ".dds")
        if not os.path.exists(src_dds):
            raise SystemExit(f"texture {old} was not exported")
        block_re = re.compile(r"(<Item>\s*<Name>)" + re.escape(old) + r"(</Name>.*?</Item>)", re.S)
        m = block_re.search(xml)
        block = m.group(0)
        fmt_old = re.search(r"<Format>([^<]+)</Format>", block).group(1)
        mips_old = int(re.search(r'<MipLevels value="(\d+)"', block).group(1))
        img = read_dds(src_dds)
        if max(img.size) > args.max_size:
            s = args.max_size / max(img.size)
            img = img.resize((max(4, int(img.width * s)), max(4, int(img.height * s))), Image.LANCZOS)
        is_normal = bool(re.search(r'name="BumpSampler" type="Texture">\s*<Name>' + re.escape(old) + "<", xml))
        alpha = np.asarray(img)[..., 3]
        if fmt_old in ("D3DFMT_DXT1", "D3DFMT_DXT5", "D3DFMT_DXT3") and mips_old > 1 and max(img.size) <= args.max_size \
                and img.size == read_dds(src_dds).size:
            # already compressed with mips: keep the original bytes (no generation loss)
            shutil.copy(src_dds, os.path.join(texdir, new + ".dds"))
            fmt_new, mips_new, w, h = fmt_old, mips_old, img.width, img.height
        else:
            fmt = "DXT5" if (alpha.min() < 250 or fmt_old in ("D3DFMT_DXT5", "D3DFMT_DXT3")) else "DXT1"
            mips_new = write_dds(os.path.join(texdir, new + ".dds"), img, fmt, normal_map=is_normal)
            fmt_new, w, h = "D3DFMT_" + fmt, img.width, img.height
        nb = block.replace(f"<Name>{old}</Name>", f"<Name>{new}</Name>", 1)
        nb = re.sub(r"<Format>[^<]+</Format>", f"<Format>{fmt_new}</Format>", nb)
        nb = re.sub(r'<MipLevels value="\d+"', f'<MipLevels value="{mips_new}"', nb)
        nb = re.sub(r'<Width value="\d+"', f'<Width value="{w}"', nb)
        nb = re.sub(r'<Height value="\d+"', f'<Height value="{h}"', nb)
        nb = nb.replace(f"<FileName>{old}.dds</FileName>", f"<FileName>{new}.dds</FileName>")
        xml = xml.replace(block, nb)
        xml = re.sub(r'(type="Texture">\s*<Name>)' + re.escape(old) + "(</Name>)", rf"\g<1>{new}\g<2>", xml)
        tex_summary.append({"name": new, "size": [w, h], "format": fmt_new, "mips": mips_new})
        log(f"texture {old} {fmt_old}/{mips_old} mips -> {new} {fmt_new} {w}x{h}/{mips_new} mips")

    xml_out = os.path.join(tmp, name + ".ydr.xml")
    with open(xml_out, "w", encoding="utf-8") as f:
        f.write(xml)
    out_ydr = os.path.join(tmp, name + ".ydr")
    r = subprocess.run(cw + ["ydr", xml_out, texdir, out_ydr], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out_ydr):
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("cwtool could not build the drawable")
    r = subprocess.run(cw + ["inspect", out_ydr], capture_output=True, text=True)
    print("\n".join(l for l in r.stdout.splitlines() if not l.startswith("    ")))
    if "RESULT OK" not in r.stdout:
        raise SystemExit("re-built drawable failed validation")
    bmin = vec(re.search(r"BBMin=([^\n]*?) BBMax", r.stdout).group(1))
    bmax = vec(re.search(r"BBMax=([^\n]*)", r.stdout).group(1))
    acen = [(a + b) / 2 for a, b in zip(bmin, bmax)]
    arad = float(np.linalg.norm(np.array(bmax) - np.array(acen)))
    tris = sum(int(t) for t in re.findall(r"Tris=(\d+)", r.stdout)) or None
    flags = FLAG_STATIC if args.static else 0
    man = {
        "name": name, "module": args.module, "external": True,
        "source": os.path.basename(args.source), "credit": args.credit,
        "dims": [round(b - a, 4) for a, b in zip(bmin, bmax)],
        "bbMin": [round(v, 4) for v in bmin], "bbMax": [round(v, 4) for v in bmax],
        "bsCentre": [round(v, 4) for v in acen], "bsRadius": round(arad, 4),
        "lodDist": args.lod, "hdTextureDist": args.hd, "flags": flags, "static": args.static,
        "tris": tris, "textures": tex_summary, "doc": {"title": args.title} if args.title else {},
        "archetype_xml": archetype_xml(name, bmin, bmax, acen, arad, args.lod, flags, args.hd),
    }
    os.makedirs(EXTERNAL, exist_ok=True)
    with open(os.path.join(EXTERNAL, name + ".json"), "w") as f:
        json.dump(man, f, indent=1)
    size = os.path.getsize(out_ydr)
    log(f"{name}.ydr {size / 1048576:.2f} MB (source {os.path.getsize(args.source) / 1048576:.2f} MB)")

    out = args.out or os.path.join(args.work, "out")
    bin_dir = os.path.join(out, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    shutil.copy2(out_ydr, os.path.join(bin_dir, name + ".ydr"))
    build.write_ytyp(cw, out)
    if args.stream:
        shutil.copy2(out_ydr, os.path.join(args.stream, name + ".ydr"))
        shutil.copy2(os.path.join(bin_dir, build.YTYP_NAME + ".ytyp"), os.path.join(args.stream, build.YTYP_NAME + ".ytyp"))
        log(f"installed {name}.ydr + {build.YTYP_NAME}.ytyp in {args.stream}")
    if not args.keep:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
