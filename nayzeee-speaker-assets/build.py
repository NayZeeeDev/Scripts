#!/usr/bin/env python3
"""Build the Record Console upgrade props into CodeWalker XML + DDS, GLB previews and layout.json.

    python3 build.py                     # everything
    python3 build.py --only nayzeee_vinyl
    python3 build.py --no-dds            # skip DDS encoding (fast geometry iteration)
    python3 build.py --png               # also dump every texture as PNG (out/textures)

Outputs (deterministic):
    out/xml/<model>.ydr.xml                 one per exported model (High + Medium LOD, collision)
    out/xml/nayzeee_console_texture.ytd.xml one texture dictionary for every exported model
    out/xml/nayzeee_console_texture/*.dds   its textures (DXT1/DXT5, full mip chains to 4 px)
    out/xml/nayzeee_console.ytyp.xml        one CBaseArchetypeDef per exported model
    out/glb/<model>.glb                     PBR previews (also image-only models)
    out/layout.json                         anchors, bounds, tri counts per LOD, meta
The txd / ytyp names differ from the speaker pack's (nayzeee_audio_texture / nayzeee_audio.ytyp), so
the converted files are ADDED to nayzeee-speaker/stream and never replace the pack.
Outputs of models / dictionaries that no longer exist are deleted from out/.
The validator (lib/validate.py) runs at the end; the exit code is non-zero on errors.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import numpy as np  # noqa: E402

import models  # noqa: E402
from lib import cwxml, dds, glb, materials, textures, validate  # noqa: E402
from lib.mesh import parts_bounds  # noqa: E402

TXD = textures.TXD_NAME
YTYP = "nayzeee_console"
DDS_CACHE_VERSION = "bc-v2"


def _r(v, n=6):
    if isinstance(v, (list, tuple, np.ndarray)):
        return [_r(x, n) for x in v]
    if isinstance(v, (float, np.floating)):
        return round(float(v), n) + 0.0
    if isinstance(v, (np.integer,)):
        return int(v)
    return v


def _clean_json(o):
    if isinstance(o, dict):
        return {str(k): _clean_json(v) for k, v in o.items()}
    return _r(o) if not isinstance(o, (list, tuple, np.ndarray)) else [_clean_json(x) for x in o]


def dump_json(obj, ind: int = 0) -> str:
    """Deterministic, readable JSON: sorted keys, numeric vectors on one line."""
    pad = " " * ind
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        items = [f'{pad} {json.dumps(k)}: {dump_json(obj[k], ind + 1)}' for k in sorted(obj)]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(obj, list):
        if all(isinstance(x, (int, float, str, bool)) or x is None for x in obj):
            return "[" + ", ".join(json.dumps(x) for x in obj) + "]"
        return "[\n" + ",\n".join(pad + " " + dump_json(x, ind + 1) for x in obj) + "\n" + pad + "]"
    return json.dumps(obj)


def mip_count(w: int, h: int, min_size: int = 4) -> int:
    n = 1
    while min(w, h) // 2 >= min_size:
        w, h, n = w // 2, h // 2, n + 1
    return n


def encode_texture(name: str, cache_dir: str) -> tuple:
    """Encode (or fetch from cache) the DDS for texture ``name`` -> (path, mips, psnr)."""
    d = textures.get(name)
    img = textures.image(name)
    h = hashlib.sha1()
    h.update(DDS_CACHE_VERSION.encode())
    h.update(f"{d.fmt}|{d.kind}|{img.shape}".encode())
    h.update(np.ascontiguousarray(img).tobytes())
    key = h.hexdigest()[:16]
    os.makedirs(cache_dir, exist_ok=True)
    path = os.path.join(cache_dir, f"{name}.{key}.dds")
    meta = path + ".json"
    if os.path.isfile(path) and os.path.isfile(meta):
        with open(meta) as f:
            m = json.load(f)
        return path, m["mips"], m["psnr"]
    data, mips = dds.encode_dds(img, d.fmt, d.kind)
    info, levels = dds.read_dds(data, decode_levels=1)
    ref = dds.to_u8(img)
    p = dds.psnr(levels[0][:, :, :ref.shape[2]], ref)
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)
    with open(meta, "w") as f:
        json.dump({"mips": mips, "psnr": round(p, 3)}, f)
    return path, mips, round(p, 3)


def write_texture_dictionary(tex_names, xml_dir: str, cache_dir: str, no_dds: bool = False):
    """Write <txd>.ytd.xml and <txd>/*.dds for ``tex_names`` -> (entries, report rows)."""
    dds_dir = os.path.join(xml_dir, TXD)
    entries, report = [], []
    if not no_dds:
        os.makedirs(dds_dir, exist_ok=True)
        keep = set()
        for t in tex_names:
            src, mips, p = encode_texture(t, cache_dir)
            dst = os.path.join(dds_dir, t + ".dds")
            shutil.copyfile(src, dst)
            keep.add(t + ".dds")
            d = textures.get(t)
            entries.append({"name": t, "width": d.size[0], "height": d.size[1], "mips": mips, "format": d.fmt,
                            "usage": d.usage})
            report.append((t, d.size, d.fmt, mips, os.path.getsize(dst), p))
        for f in os.listdir(dds_dir):
            if f not in keep:
                os.remove(os.path.join(dds_dir, f))
    else:
        for t in tex_names:
            d = textures.get(t)
            entries.append({"name": t, "width": d.size[0], "height": d.size[1],
                            "mips": mip_count(*d.size), "format": d.fmt, "usage": d.usage})
    cwxml.write_text(os.path.join(xml_dir, TXD + ".ytd.xml"), cwxml.ytd_xml(entries))
    return entries, report


def textures_for(specs) -> list:
    """Sorted texture names used by the given ModelSpecs (+ runtime-replaceable defaults)."""
    names = set()
    for sp in specs:
        for part in sp.parts:
            names.update(materials.get(part.material).texture_names())
    names.update(t for t in textures.names() if textures.get(t).replaceable)
    return sorted(names)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="+", metavar="NAME", help="write ydr/glb only for these models")
    ap.add_argument("--no-dds", action="store_true", help="do not (re)encode DDS textures")
    ap.add_argument("--no-glb", action="store_true", help="skip GLB previews")
    ap.add_argument("--png", action="store_true", help="also write every texture as PNG into out/textures")
    ap.add_argument("--out", default=os.path.join(ROOT, "out"), help="output folder (default: out)")
    args = ap.parse_args(argv)

    t0 = time.time()
    out = os.path.abspath(args.out)
    xml_dir = os.path.join(out, "xml")
    glb_dir = os.path.join(out, "glb")
    cache_dir = os.path.join(ROOT, "cache", "dds")
    for d in (xml_dir, glb_dir):
        os.makedirs(d, exist_ok=True)

    all_names = models.names()
    selected = args.only or all_names
    unknown = [n for n in selected if n not in all_names]
    if unknown:
        print(f"unknown model(s): {unknown}; available: {all_names}")
        return 2

    # 1. build every model (High + Medium) -- cheap, and the ytd/ytyp/layout always cover all models
    specs = {}
    problems = []
    for name in all_names:
        hi = models.build(name, 1.0)
        med = models.build(name, hi.lod.med_detail)
        specs[name] = (hi, med)
        problems += hi.problems()
    if problems:
        for p in problems:
            print("ERROR", p)
        return 1

    # 2. textures: everything any exported model uses + runtime-replaceable defaults
    tex_names = textures_for([sp for name in all_names for sp in specs[name] if sp.export])
    entries, tex_report = write_texture_dictionary(tex_names, xml_dir, cache_dir, args.no_dds)
    if args.png:
        png_dir = os.path.join(out, "textures")
        os.makedirs(png_dir, exist_ok=True)
        for t in tex_names:
            textures.pil(t).save(os.path.join(png_dir, t + ".png"))

    # 3. drawables + GLB
    archetypes = []
    layout = {"txd": TXD, "ytyp": YTYP, "units": "metres", "axes": "+Z up, +Y front, +X viewer's left",
              "models": {}}
    rows = []
    for name in all_names:
        hi, med = specs[name]
        lo, hi_b, bsc, bsr = parts_bounds(hi.parts)
        if hi.export:
            ydr_path = os.path.join(xml_dir, name + ".ydr.xml")
            if name in selected or not os.path.isfile(ydr_path):
                cwxml.write_text(ydr_path, cwxml.ydr_xml(name, {"High": hi.parts, "Medium": med.parts},
                                                         hi.collision, hi.lod))
            archetypes.append({"name": name, "txd": TXD, "lod_dist": hi.lod.archetype_lod_dist, "flags": hi.flags,
                               "bb_min": lo, "bb_max": hi_b, "bs_centre": bsc, "bs_radius": bsr,
                               "hd_dist": hi.lod.hd_texture_dist})
        glb_kb = ""
        if not args.no_glb and name in selected:
            n = glb.write_glb(os.path.join(glb_dir, name + ".glb"), name, hi.parts)
            glb_kb = f"{n / 1024:.0f}"
        mats_used = []
        for p in list(hi.parts) + list(med.parts):
            if p.material not in mats_used:
                mats_used.append(p.material)
        coll = cwxml.collision_summary(hi.collision) if hi.collision else None
        layout["models"][name] = {
            "export": hi.export,
            "description": hi.description,
            "bbox": {"min": lo, "max": hi_b, "size": hi_b - lo},
            "sphere": {"centre": bsc, "radius": bsr},
            "lods": {"high": {"tris": sum(p.tri_count for p in hi.parts), "verts": sum(p.vertex_count for p in hi.parts)},
                     "medium": {"tris": sum(p.tri_count for p in med.parts),
                                "verts": sum(p.vertex_count for p in med.parts), "detail": hi.lod.med_detail}},
            "lod_distances": {"high": hi.lod.high_dist, "medium": hi.lod.med_dist,
                              "archetype": hi.lod.archetype_lod_dist},
            "materials": mats_used,
            "anchors": {k: a.to_json() for k, a in sorted(hi.anchors.items())},
            "collision": None if coll is None else {"min": coll["min"], "max": coll["max"], "volume": coll["volume"],
                                                   "shapes": len(hi.collision)},
            "flags": hi.flags,
            "meta": hi.meta,
        }
        rows.append((name, "yes" if hi.export else "image", layout["models"][name]["lods"]["high"]["tris"],
                     layout["models"][name]["lods"]["medium"]["tris"], len(mats_used),
                     "x".join(f"{v:.3f}" for v in (hi_b - lo)), len(hi.collision), glb_kb))
    # drop stale outputs of models / dictionaries that no longer exist (renamed or removed)
    exported = {a["name"] for a in archetypes}
    for f in os.listdir(xml_dir):
        p = os.path.join(xml_dir, f)
        if (f.endswith(".ydr.xml") and f[:-len(".ydr.xml")] not in exported) or \
                (f.endswith(".ytd.xml") and f != TXD + ".ytd.xml") or \
                (f.endswith(".ytyp.xml") and f != YTYP + ".ytyp.xml"):
            os.remove(p)
        elif os.path.isdir(p) and f != TXD:
            shutil.rmtree(p)
    if not args.no_glb:
        for f in os.listdir(glb_dir):
            if f.endswith(".glb") and f[:-len(".glb")] not in all_names:
                os.remove(os.path.join(glb_dir, f))
    cwxml.write_text(os.path.join(xml_dir, YTYP + ".ytyp.xml"), cwxml.ytyp_xml(YTYP, archetypes))
    with open(os.path.join(out, "layout.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(dump_json(_clean_json(layout)) + "\n")

    # 4. report + validation
    print(f"\n{'model':24s} {'export':6s} {'high tris':>9s} {'med tris':>8s} {'mats':>4s} {'size (m)':>20s} "
          f"{'coll':>4s} {'glb KB':>6s}")
    for r in rows:
        print(f"{r[0]:24s} {r[1]:6s} {r[2]:9d} {r[3]:8d} {r[4]:4d} {r[5]:>20s} {r[6]:4d} {r[7]:>6s}")
    if tex_report:
        total = sum(r[4] for r in tex_report)
        worst = min(tex_report, key=lambda r: r[5])
        print(f"\ntextures: {len(tex_report)} in {TXD} = {total / 1048576:.2f} MB of DDS "
              f"(lowest round-trip PSNR {worst[5]:.1f} dB: {worst[0]})")
        low = [r for r in tex_report if r[5] < 30]
        for r in low:
            print(f"  WARN {r[0]} PSNR {r[5]:.1f} dB")
    if args.no_dds:
        print("\n(--no-dds: DDS files were not re-encoded; validation of .dds files may report missing files)")
    rep = validate.validate_dir(xml_dir)
    for w in rep.warnings:
        print("WARN ", w)
    for e in rep.errors:
        print("ERROR", e)
    print(f"validate: {len(rep.info.get('drawables', {}))} drawable(s), {len(rep.info.get('textures', {}))} "
          f"texture(s), {len(rep.info.get('archetypes', []))} archetype(s), {len(rep.info.get('glb', {}))} glb: "
          f"{'OK' if rep.ok else str(len(rep.errors)) + ' error(s)'}, {len(rep.warnings)} warning(s)")
    print(f"done in {time.time() - t0:.1f}s -> {out}")
    return 0 if rep.ok else 1


if __name__ == "__main__":
    sys.exit(main())
