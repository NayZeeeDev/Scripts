#!/usr/bin/env python3
"""
NAYZEEE props pipeline - builds every registered prop into streamable GTA V assets.

    python3 tools/props/build.py --out /tmp/nza-work/props/out \
                                 --stream /home/user/Scripts/nayzeee-ambulance/stream

Steps
  1. import every module in tools/props/props/ (each registers props with @prop / register)
  2. build each prop in parallel: geometry -> automatic atlas -> baked textures (DDS) ->
     CodeWalker XML (.ydr.xml with embedded textures + collision) + .glb preview
  3. make sure CodeWalker + cwtool are built (clones CodeWalker into <work>/CodeWalker once)
  4. cwtool: XML -> .ydr for every prop and ONE nz_amb_props.ytyp with every archetype,
     then load every binary back ('inspect') - any error aborts before stream/ is touched
  5. copy the binaries to --stream (stale nz_amb_*.ydr there are removed)
  6. headless three.js previews (3 angles per prop) -> <out>/sheets/contact_*.png
  7. <out>/props_manifest.json + props_table.md + props_catalog.md; --docs refreshes the generated
     <!-- props:table:* --> and <!-- props:catalog:* --> sections of a markdown file (docs/modules/props.md)

Requirements: python3 with numpy + Pillow, .NET 8 SDK, git, node 18+ (previews), chromium.
"""
from __future__ import annotations

import argparse
import fnmatch
import importlib
import json
import math
import multiprocessing as mp
import os
import pkgutil
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image, ImageDraw  # noqa: E402

from nzprops.paint import font  # noqa: E402
from nzprops.prop import REGISTRY, build_prop  # noqa: E402
from nzprops.cwxml import ytyp_xml  # noqa: E402

YTYP_NAME = "nz_amb_props"
DEFAULT_WORK = "/tmp/nza-work/props"
CODEWALKER_GIT = "https://github.com/dexyfex/CodeWalker"


def log(*a):
    print("[props]", *a, flush=True)


def load_props():
    import props as pkg  # tools/props/props
    for m in pkgutil.iter_modules(pkg.__path__):
        importlib.import_module(f"props.{m.name}")
    return REGISTRY


def _build_one(args):
    name, out, quick = args
    load_props()
    t0 = time.time()
    try:
        man = build_prop(REGISTRY[name], out, quick=quick)
        man["build_seconds"] = round(time.time() - t0, 2)
        return name, man, None
    except Exception:  # report and keep the pool alive
        import traceback
        return name, None, traceback.format_exc()


# ---------------------------------------------------------------------------------------------
# toolchain
# ---------------------------------------------------------------------------------------------
def ensure_cwtool(work, codewalker=None):
    cw_dir = codewalker or os.path.join(work, "CodeWalker")
    if not os.path.isdir(os.path.join(cw_dir, "CodeWalker.Core")):
        log(f"cloning CodeWalker into {cw_dir}")
        subprocess.run(["git", "clone", "--depth", "1", CODEWALKER_GIT, cw_dir], check=True)
    proj = os.path.join(HERE, "cwtool")
    outbase = os.path.join(work, "cwtool")
    dll = os.path.join(outbase, "bin", "Release", "net8.0", "cwtool.dll")
    src_time = max(os.path.getmtime(os.path.join(proj, f)) for f in ("Program.cs", "cwtool.csproj", "Directory.Build.props"))
    if not os.path.exists(dll) or os.path.getmtime(dll) < src_time:
        log("building cwtool")
        env = dict(os.environ, NZA_CWTOOL_OUT=outbase, DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_NOLOGO="1")
        r = subprocess.run(["dotnet", "build", "-c", "Release", f"-p:CodeWalkerDir={cw_dir}", "-nologo", "-v", "q"],
                           cwd=proj, env=env, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-4000:], r.stderr[-4000:])
            raise SystemExit("cwtool build failed")
    return ["dotnet", dll]


def ensure_preview_modules(work):
    mod_root = os.path.join(work, "preview_node")
    nm = os.path.join(mod_root, "node_modules")
    if os.path.isdir(os.path.join(nm, "three")) and os.path.isdir(os.path.join(nm, "playwright-core")):
        return nm
    os.makedirs(mod_root, exist_ok=True)
    shutil.copy(os.path.join(HERE, "preview", "package.json"), os.path.join(mod_root, "package.json"))
    log("installing preview dependencies (three, playwright-core)")
    subprocess.run(["npm", "install", "--no-audit", "--no-fund", "--loglevel", "error"], cwd=mod_root, check=True)
    return nm


# ---------------------------------------------------------------------------------------------
# conversion + verification
# ---------------------------------------------------------------------------------------------
def external_manifests():
    """Imported third-party models (tools/props/external/*.json, written by import_model.py)."""
    d = os.path.join(HERE, "external")
    res = {}
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith(".json"):
                with open(os.path.join(d, f)) as fh:
                    m = json.load(fh)
                res[m["name"]] = m
    return res


def all_archetypes(all_manifests):
    ext = external_manifests()
    merged = {**ext, **all_manifests}
    return [merged[n]["archetype_xml"] for n in sorted(merged)], len(merged)


def write_ytyp(cw, out):
    """Rebuild only nz_amb_props.ytyp from every built manifest in <out> + the imported models."""
    load_props()
    all_m = {}
    for n in sorted(REGISTRY):
        p = os.path.join(out, n, "manifest.json")
        if os.path.exists(p):
            with open(p) as f:
                all_m[n] = json.load(f)
    arch, count = all_archetypes(all_m)
    bin_dir = os.path.join(out, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    src = os.path.join(out, YTYP_NAME + ".ytyp.xml")
    with open(src, "w", encoding="utf-8") as f:
        f.write(ytyp_xml(YTYP_NAME, arch))
    dst = os.path.join(bin_dir, YTYP_NAME + ".ytyp")
    subprocess.run(cw + ["ytyp", src, dst], check=True, capture_output=True)
    r = subprocess.run(cw + ["inspect", dst], capture_output=True, text=True)
    m = re.search(r"Ytyp Name=.*archetypes=(\d+)", r.stdout)
    if not m or int(m.group(1)) != count:
        raise SystemExit(f"ytyp archetype count mismatch ({m.group(1) if m else '?'} != {count})")
    log(f"{YTYP_NAME}.ytyp rebuilt ({count} archetypes)")
    return dst


def convert(cw, out, names, all_manifests):
    bin_dir = os.path.join(out, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    arch, arch_count = all_archetypes(all_manifests)
    ytyp_src = os.path.join(out, YTYP_NAME + ".ytyp.xml")
    with open(ytyp_src, "w", encoding="utf-8") as f:
        f.write(ytyp_xml(YTYP_NAME, arch))
    lines = []
    for n in names:
        src = os.path.join(out, n, "source")
        lines.append("\t".join(["ydr", os.path.join(src, n + ".ydr.xml"), os.path.join(src, n), os.path.join(bin_dir, n + ".ydr")]))
    lines.append("\t".join(["ytyp", ytyp_src, os.path.join(bin_dir, YTYP_NAME + ".ytyp")]))
    for n in names:
        lines.append("\t".join(["inspect", os.path.join(bin_dir, n + ".ydr")]))
    lines.append("\t".join(["inspect", os.path.join(bin_dir, YTYP_NAME + ".ytyp")]))
    batch = os.path.join(out, "cwtool_batch.txt")
    with open(batch, "w") as f:
        f.write("\n".join(lines) + "\n")
    r = subprocess.run(cw + ["batch", batch], capture_output=True, text=True)
    with open(os.path.join(out, "cwtool_log.txt"), "w") as f:
        f.write(r.stdout)
        f.write(r.stderr)
    fails = []
    cur, last = None, ""
    for line in r.stdout.splitlines():
        m_end = re.match(r"^### \d+ end rc=(\d+)", line)
        if m_end:
            if m_end.group(1) != "0":
                fails.append(f"{cur} :: {last or 'no result'}")
            cur, last = None, ""
            continue
        m_start = re.match(r"^### \d+ (.*)$", line)
        if m_start:
            cur, last = m_start.group(1), ""
        elif line.startswith("RESULT"):
            last = line
    if r.returncode != 0 or fails:
        for fl in fails:
            print("  FAIL", fl)
        print(r.stderr[-3000:])
        raise SystemExit(f"cwtool reported errors (see {out}/cwtool_log.txt)")
    # archetype count check
    m = re.search(r"Ytyp Name=.*archetypes=(\d+)", r.stdout)
    if not m or int(m.group(1)) != arch_count:
        raise SystemExit(f"ytyp archetype count mismatch ({m.group(1) if m else '?'} != {arch_count})")
    log(f"cwtool: {len(names)} drawables + {YTYP_NAME}.ytyp converted and verified ({arch_count} archetypes)")
    return bin_dir


def install_stream(bin_dir, stream, names):
    os.makedirs(stream, exist_ok=True)
    for n in names:
        shutil.copy2(os.path.join(bin_dir, n + ".ydr"), os.path.join(stream, n + ".ydr"))
    shutil.copy2(os.path.join(bin_dir, YTYP_NAME + ".ytyp"), os.path.join(stream, YTYP_NAME + ".ytyp"))
    registered = set(REGISTRY) | set(external_manifests())   # imported models are never "stale"
    for f in os.listdir(stream):
        if f.startswith("nz_amb_") and f.endswith(".ydr") and f[:-4] not in registered:
            os.remove(os.path.join(stream, f))
            log(f"removed stale {f}")
    total = sum(os.path.getsize(os.path.join(stream, f)) for f in os.listdir(stream) if f.endswith((".ydr", ".ytyp")))
    log(f"stream: {len(names)} .ydr + {YTYP_NAME}.ytyp installed in {stream} ({total / 1048576:.2f} MB total)")


# ---------------------------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------------------------
def render_previews(out, work, names, size, views, manifests=None):
    nm = ensure_preview_modules(work)
    rdir = os.path.join(out, "renders")
    lst = []
    for n in names:
        pv = ((manifests or {}).get(n) or {}).get("preview") or {}
        lst.append({"name": n, "glb": os.path.join(out, n, n + ".glb"), "cams": pv.get("cams", []), "lights": pv.get("lights", [])})
    lpath = os.path.join(out, "render_list.json")
    with open(lpath, "w") as f:
        json.dump(lst, f)
    r = subprocess.run(["node", os.path.join(HERE, "preview", "render.mjs"), "--list", lpath, "--out", rdir,
                        "--modules", nm, "--size", str(size), "--views", ",".join(views)], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("preview rendering failed")
    return rdir


def contact_sheets(out, rdir, manifests, views, per_page=6, cell=360):
    sdir = os.path.join(out, "sheets")
    os.makedirs(sdir, exist_ok=True)
    names = sorted(manifests)
    pages = [names[i:i + per_page] for i in range(0, len(names), per_page)]
    cols = 2
    pw = cols * (len(views) * cell + 24) + 24
    files = []
    for pi, page in enumerate(pages):
        rows = math.ceil(len(page) / cols)
        ph = 64 + rows * (cell + 58)
        sheet = Image.new("RGB", (pw, ph), (17, 19, 22))
        d = ImageDraw.Draw(sheet)
        d.text((24, 22), f"NAYZEEE AMBULANCE  -  streamed props  ({pi + 1}/{len(pages)})", font=font("brand", 22), fill=(230, 233, 235))
        for k, n in enumerate(page):
            cx = 24 + (k % cols) * (len(views) * cell + 24)
            cy = 64 + (k // cols) * (cell + 58)
            m = manifests[n]
            pviews = ((m.get("preview") or {}).get("views") or views)[:len(views)]
            for vi, v in enumerate(pviews):
                p = os.path.join(rdir, f"{n}_{v}.png")
                if os.path.exists(p):
                    sheet.paste(Image.open(p).convert("RGB").resize((cell, cell), Image.LANCZOS), (cx + vi * cell, cy))
            dims = " x ".join(f"{x:.3f}" for x in m["dims"])
            d.text((cx, cy + cell + 6), n, font=font("brand-semi", 17), fill=(8, 190, 176))
            d.text((cx, cy + cell + 30), f"{dims} m   {m['tris']} tris   lod {m['lodDist']:g}   {'static' if m['static'] else 'dynamic'}",
                   font=font("mono", 13), fill=(160, 166, 170))
        fp = os.path.join(sdir, f"contact_{pi + 1:02d}.png")
        sheet.save(fp)
        files.append(fp)
    return files


# ---------------------------------------------------------------------------------------------
# manifest / docs
# ---------------------------------------------------------------------------------------------
MODULE_TITLES = {
    "props.cases": "Cases & bags", "props.devices": "Electronic devices", "props.fluids": "Fluids & IV",
    "props.handheld": "Hand-held tools", "props.ortho": "Orthopaedic & worn", "props.stretcher": "Transport",
    "props.airway": "Airway", "props.radiology": "Imaging & angiography suite", "props.hospital": "Hospital equipment",
    "props.bay": "Ambulance treatment bay",
}


def config_keys(config_path):
    """model name -> Config.Props key, parsed from config/props.lua (if present)."""
    keys = {}
    if config_path and os.path.exists(config_path):
        for m in re.finditer(r"^\s*([a-z0-9_]+)\s*=\s*'(nz_amb_[a-z0-9_]+)'", open(config_path, encoding="utf-8").read(), re.M):
            keys.setdefault(m.group(2), []).append(m.group(1))
    return keys


def catalog_md(manifests, config_path=None):
    """Per-prop reference (generated from the @prop doc dicts + build manifests)."""
    keys = config_keys(config_path)
    groups = {}
    for n, m in sorted(manifests.items()):
        groups.setdefault(m.get("module", ""), []).append(n)
    order = [k for k in MODULE_TITLES if k in groups] + sorted(k for k in groups if k not in MODULE_TITLES)
    out = []
    for mod in order:
        out.append(f"### {MODULE_TITLES.get(mod, mod)}\n")
        for n in groups[mod]:
            m = manifests[n]
            d = m.get("doc") or {}
            out.append(f"#### `{n}` - {d.get('title', '')}\n")
            out.append("| | |\n|---|---|")
            ck = ", ".join(f"`Config.Props.{k}`" for k in keys.get(n, [])) or "-"
            out.append(f"| Config | {ck} |")
            dims = " x ".join(f"{v:.3f}" for v in m["dims"])
            out.append(f"| Size X x Y x Z | {dims} m (bbMin {tuple(round(v, 3) for v in m['bbMin'])}, bbMax "
                       f"{tuple(round(v, 3) for v in m['bbMax'])}) |")
            for k, lab in (("origin", "Origin / pivot"), ("axes", "Axes"), ("attach", "Attach / use"), ("screen", "Screen"),
                           ("variant", "Variants")):
                if d.get(k):
                    out.append(f"| {lab} | {d[k]} |")
            typ = "static (archetype flag 32 - never moves, cheapest)" if m["static"] else "dynamic (physics, can be attached / carried)"
            out.append(f"| LOD / type | lodDist {m['lodDist']:g} m, hdTextureDist {m['hdTextureDist']:g} m, {typ} |")
            cols = {}
            for c in m["collision"]:
                cols[(c["type"], c["material"])] = cols.get((c["type"], c["material"]), 0) + 1
            out.append("| Collision | " + ", ".join(f"{v} {t} {mat}" for (t, mat), v in sorted(cols.items())) + " (embedded composite) |")
            tex = ", ".join(f"{t['name']} {t['size'] if not isinstance(t['size'], list) else 'x'.join(map(str, t['size']))}"
                            for t in m["textures"])
            out.append(f"| Textures (txd = `{n}`) | {tex} |")
            out.append(f"| Mesh | {m['tris']} tris, {m['verts']} verts, shaders: {', '.join(sorted(set(m['shaders'])))} |")
            if m.get("ydr_bytes"):
                out[-1] = out[-1][:-2] + f", .ydr {m['ydr_bytes'] / 1024:.0f} KB |"
            out.append("")
    return "\n".join(out) + "\n"


def write_tables(out, manifests, docs=None, stream=None):
    slim = {n: {k: v for k, v in m.items() if k != "archetype_xml"} for n, m in sorted(manifests.items())}
    if stream:
        for n in slim:
            p = os.path.join(stream, n + ".ydr")
            if os.path.exists(p):
                slim[n]["ydr_bytes"] = os.path.getsize(p)
    with open(os.path.join(out, "props_manifest.json"), "w") as f:
        json.dump(slim, f, indent=1)
    lines = ["| Model | Size X x Y x Z (m) | bbMin | bbMax | Tris | lodDist | Type | Screens | Collision |",
             "|---|---|---|---|---|---|---|---|---|"]
    for n, m in slim.items():
        col = ", ".join(sorted({c["material"] for c in m["collision"]}))
        lines.append(f"| `{n}` | {' x '.join(f'{v:.3f}' for v in m['dims'])} | {tuple(round(v, 3) for v in m['bbMin'])} | "
                     f"{tuple(round(v, 3) for v in m['bbMax'])} | {m['tris']} | {m['lodDist']:g} | "
                     f"{'static' if m['static'] else 'dynamic'} | {', '.join(m['screens']) or '-'} | {col} |")
    table = "\n".join(lines) + "\n"
    with open(os.path.join(out, "props_table.md"), "w") as f:
        f.write(table)
    cfg = os.path.join(HERE, "..", "..", "config", "props.lua")
    cat = catalog_md(slim, cfg)
    with open(os.path.join(out, "props_catalog.md"), "w") as f:
        f.write(cat)
    if docs and os.path.exists(docs):
        s = open(docs, encoding="utf-8").read()
        changed = False
        for (a, b), body in ((("<!-- props:table:begin -->", "<!-- props:table:end -->"), table),
                             (("<!-- props:catalog:begin -->", "<!-- props:catalog:end -->"), cat)):
            if a in s and b in s:
                s = s.split(a)[0] + a + "\n" + body + b + s.split(b)[1]
                changed = True
        if changed:
            with open(docs, "w", encoding="utf-8") as f:
                f.write(s)
            log(f"updated generated sections in {docs}")
    return table


# ---------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(DEFAULT_WORK, "out"), help="build folder (XML, DDS, glb, renders)")
    ap.add_argument("--stream", default=None, help="resource stream/ folder to install .ydr/.ytyp into")
    ap.add_argument("--work", default=DEFAULT_WORK, help="tool cache (CodeWalker clone, cwtool build, node modules)")
    ap.add_argument("--codewalker", default=None, help="existing CodeWalker checkout to use")
    ap.add_argument("--only", default=None, help="comma separated names/globs to rebuild (others reuse <out>)")
    ap.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)))
    ap.add_argument("--quick", action="store_true", help="skip ambient occlusion (fast iteration)")
    ap.add_argument("--no-convert", action="store_true", help="stop after the XML/DDS/glb stage")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--views", default="front,back,top")
    ap.add_argument("--size", type=int, default=640, help="preview render size")
    ap.add_argument("--docs", default=None, help="markdown file whose props:table / props:catalog sections get refreshed")
    ap.add_argument("--list", action="store_true", help="list registered props and exit")
    ap.add_argument("--docs-only", action="store_true", help="only rewrite the manifest tables / --docs sections from <out>")
    args = ap.parse_args()

    load_props()
    names_all = sorted(REGISTRY)
    if args.list:
        for n in names_all:
            print(n, REGISTRY[n].module)
        return
    if args.docs_only:
        all_m = {}
        for n in names_all:
            p = os.path.join(args.out, n, "manifest.json")
            if not os.path.exists(p):
                raise SystemExit(f"{n} has never been built in {args.out}")
            with open(p) as f:
                all_m[n] = json.load(f)
        write_tables(args.out, all_m, args.docs, args.stream)
        return
    sel = names_all
    if args.only:
        pats = [p.strip() for p in args.only.split(",") if p.strip()]
        sel = [n for n in names_all if any(fnmatch.fnmatch(n, p) or n == p for p in pats)]
        if not sel:
            raise SystemExit(f"--only matched nothing ({args.only})")
    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    log(f"building {len(sel)} prop(s) with {args.jobs} job(s)")
    manifests = {}
    errors = []
    ctx = mp.get_context("fork")
    with ctx.Pool(args.jobs) as pool:
        for name, man, err in pool.imap_unordered(_build_one, [(n, args.out, args.quick) for n in sel]):
            if err:
                errors.append((name, err))
                log(f"FAILED {name}")
                print(err)
            else:
                manifests[name] = man
                log(f"built {name:28s} {man['tris']:6d} tris  {man['build_seconds']:5.1f}s")
    if errors:
        raise SystemExit(f"{len(errors)} prop(s) failed: {', '.join(n for n, _ in errors)}")
    # every archetype must be present in the ytyp: reuse manifests of props not rebuilt now
    all_m = dict(manifests)
    for n in names_all:
        if n not in all_m:
            p = os.path.join(args.out, n, "manifest.json")
            if os.path.exists(p):
                with open(p) as f:
                    all_m[n] = json.load(f)
            elif not args.no_convert:
                raise SystemExit(f"{n} has never been built in {args.out}; run a full build first")
    log(f"geometry + textures done in {time.time() - t0:.1f}s")

    if not args.no_convert:
        cw = ensure_cwtool(args.work, args.codewalker)
        bin_dir = convert(cw, args.out, names_all if not args.only else sel, all_m)
        if args.only:
            # ytyp needs every drawable present; make sure the others were converted before
            missing = [n for n in names_all if not os.path.exists(os.path.join(bin_dir, n + ".ydr"))]
            if missing:
                bin_dir = convert(cw, args.out, names_all, all_m)
        if args.stream:
            install_stream(bin_dir, args.stream, names_all)
    if not args.no_preview:
        views = [v.strip() for v in args.views.split(",") if v.strip()]
        rdir = render_previews(args.out, args.work, sel, args.size, views, all_m)
        sheets = contact_sheets(args.out, rdir, all_m, views)
        log("contact sheets: " + ", ".join(sheets))
    write_tables(args.out, all_m, args.docs, args.stream)
    log(f"done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
