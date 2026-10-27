#!/usr/bin/env python3
"""
NAYZEEE Radio - procedural props pipeline: builds every registered prop (nzr_*) into CodeWalker XML +
DDS textures + .glb previews, review renders, the layout Lua, and (on a machine with .NET 8) the
streamable .ydr / nzr_props.ytyp.

    python3 tools/props/build.py --no-convert                     # everything except the binaries (no .NET)
    python3 tools/props/build.py --only 'nzr_handheld*' --no-convert --quick
    python3 tools/props/build.py --stream ../nayzeee-radio-props/stream   # + convert + install (.NET 8)
    python3 tools/props/build.py --convert-only --stream ../nayzeee-radio-props/stream   # convert tools/props/xml

Steps
  1. import every module in tools/props/props/ (each registers props with @prop / register / @radio);
     a module that fails to import is skipped with a warning (unless --only asks for its props) and
     modules named _*.py (examples) load only with --examples
  2. build each selected prop in parallel: geometry -> automatic atlas -> baked textures (DDS) ->
     CodeWalker XML (.ydr.xml with embedded textures, high + medium LOD, collision) + .glb preview;
     every file is written atomically, so several builds can run at the same time
  3. aggregate (under a lock) from every manifest that built cleanly so far: props_manifest.json,
     props_table.md, props_catalog.md, nzr_props.ytyp.xml, tools/props/xml/ (committed XML + DDS),
     shared/props_layout.lua (checked with luac5.4 -p), memory budget estimate
  4. conversion - only with --stream / --convert: cwtool XML -> .ydr + one nzr_props.ytyp, every binary
     loaded back, exact memory budget, install into stream/
  5. headless three.js review renders (+ the radios' assembled body+parts renders and alignment diffs),
     contact sheets
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
import tempfile
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image, ImageChops, ImageDraw, ImageStat  # noqa: E402

import gen_layout  # noqa: E402
from nzprops.budget import PAGE_LIMIT, mib  # noqa: E402
from nzprops.cwxml import ytyp_xml  # noqa: E402
from nzprops.fsutil import FileLock, copy_file, read_json, save_image, write_json, write_text  # noqa: E402
from nzprops.paint import font  # noqa: E402
from nzprops.prop import REGISTRY, build_prop  # noqa: E402

YTYP_NAME = "nzr_props"
PREFIX = "nzr_"
DEFAULT_WORK = "/tmp/nzr-work/props"
DEFAULT_STREAM = os.path.normpath(os.path.join(HERE, "..", "..", "..", "nayzeee-radio-props", "stream"))
DEFAULT_XML = os.path.join(HERE, "xml")
DEFAULT_LAYOUT = gen_layout.DEFAULT_LUA
CODEWALKER_GIT = "https://github.com/dexyfex/CodeWalker"
EXAMPLES_ENV = "NZR_PROPS_EXAMPLE"

IMPORT_FAILURES: dict[str, str] = {}


def log(*a):
    print("[props]", *a, flush=True)


# ---------------------------------------------------------------------------------------------
# prop modules
# ---------------------------------------------------------------------------------------------
def load_props(examples=None):
    """Import every props module. A module that raises is skipped (its partial registrations removed)
    and its traceback kept in IMPORT_FAILURES so --only can report it."""
    if examples is None:
        examples = os.environ.get(EXAMPLES_ENV, "") not in ("", "0")
    import props as pkg  # tools/props/props
    for m in sorted(pkgutil.iter_modules(pkg.__path__), key=lambda x: x.name):
        if m.name.startswith("_") and not examples:
            continue
        full = f"props.{m.name}"
        if full in sys.modules or m.name in IMPORT_FAILURES:
            continue
        before = set(REGISTRY)
        kit = sys.modules.get("props.radio_kit")
        radios_before = set(kit.RADIOS) if kit else set()
        try:
            importlib.import_module(full)
        except Exception:
            IMPORT_FAILURES[m.name] = traceback.format_exc()
            for n in set(REGISTRY) - before:
                REGISTRY.pop(n, None)
            kit = sys.modules.get("props.radio_kit")
            if kit:
                for k in set(kit.RADIOS) - radios_before:
                    kit.RADIOS.pop(k, None)
            sys.modules.pop(full, None)
            log(f"WARNING: skipped props/{m.name}.py - it does not import (someone's work in progress?): "
                f"{IMPORT_FAILURES[m.name].strip().splitlines()[-1]}")
    return REGISTRY


def _build_one(args):
    name, out, quick, examples = args
    if name not in REGISTRY:
        load_props(examples)
    t0 = time.time()
    try:
        man = build_prop(REGISTRY[name], out, quick=quick)
        man["build_seconds"] = round(time.time() - t0, 2)
        return name, man, None
    except Exception:  # report and keep the pool alive
        return name, None, traceback.format_exc()


def _cost(name):
    s = REGISTRY[name]
    return -(s.atlas * s.atlas + s.alpha_atlas * s.alpha_atlas)


def prewarm_designs(sel):
    """Evaluate radio designs once in the parent so the forked workers share them. Returns
    {prop name: traceback} for props whose design fails."""
    kit = sys.modules.get("props.radio_kit")
    if not kit:
        return {}
    bad = {}
    keys = sorted({k for k, rs in kit.RADIOS.items() for n in sel if n in [rs.full, rs.body] + [rs.part_model(p) for p in rs.parts]})
    for k in keys:
        rs = kit.RADIOS[k]
        try:
            t0 = time.time()
            kit.get_design(k)
            log(f"radio design '{k}' evaluated in {time.time() - t0:.1f}s ({len(rs.parts)} parts)")
        except Exception:
            tb = traceback.format_exc()
            for n in [rs.full, rs.body] + [rs.part_model(p) for p in rs.parts]:
                if n in sel:
                    bad[n] = tb
    return bad


# ---------------------------------------------------------------------------------------------
# toolchain (.NET 8 + CodeWalker; node + chromium for previews)
# ---------------------------------------------------------------------------------------------
def ensure_cwtool(work, codewalker=None):
    if not shutil.which("dotnet"):
        raise SystemExit("conversion needs the .NET 8 SDK (dotnet) - run without --stream / --convert to skip it "
                         "(see tools/props/convert.sh for the Windows CodeWalker GUI route)")
    with FileLock(os.path.join(work, ".cwtool.lock")):
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
            env = dict(os.environ, NZR_CWTOOL_OUT=outbase, DOTNET_CLI_TELEMETRY_OPTOUT="1", DOTNET_NOLOGO="1")
            r = subprocess.run(["dotnet", "build", "-c", "Release", f"-p:CodeWalkerDir={cw_dir}", "-nologo", "-v", "q"],
                               cwd=proj, env=env, capture_output=True, text=True)
            if r.returncode != 0:
                print(r.stdout[-4000:], r.stderr[-4000:])
                raise SystemExit("cwtool build failed")
    return ["dotnet", dll]


def ensure_preview_modules(work):
    mod_root = os.path.join(work, "preview_node")
    nm = os.path.join(mod_root, "node_modules")
    with FileLock(os.path.join(work, ".preview_node.lock")):
        if os.path.isdir(os.path.join(nm, "three")) and os.path.isdir(os.path.join(nm, "playwright-core")):
            return nm
        os.makedirs(mod_root, exist_ok=True)
        shutil.copy(os.path.join(HERE, "preview", "package.json"), os.path.join(mod_root, "package.json"))
        log("installing preview dependencies (three, playwright-core)")
        subprocess.run(["npm", "install", "--no-audit", "--no-fund", "--loglevel", "error"], cwd=mod_root, check=True)
    return nm


# ---------------------------------------------------------------------------------------------
# manifests / aggregation
# ---------------------------------------------------------------------------------------------
def with_physics(name, xml):
    """Every prop has embedded collision: its archetype must name it as physicsDictionary."""
    return xml.replace("<physicsDictionary />", f"<physicsDictionary>{name}</physicsDictionary>")


def collect_manifests(out, xml_dir):
    """Every prop that built cleanly so far: this machine's <out>/<name>/manifest.json plus the committed
    tools/props/xml/<name>.json (newest build wins)."""
    return gen_layout.collect([out], xml_dir if xml_dir and os.path.isdir(xml_dir) else None)


def exported(manifests):
    return {n: m for n, m in manifests.items() if m.get("export", True) and n.startswith(PREFIX)}


def ytyp_text(manifests):
    ex = exported(manifests)
    return ytyp_xml(YTYP_NAME, [with_physics(n, ex[n]["archetype_xml"]) for n in sorted(ex)]), len(ex)


def export_xml(out, xml_dir, names, manifests):
    """Copy the CodeWalker XML + DDS of freshly built (full quality) exported props into tools/props/xml/
    - what the user converts on a machine with .NET 8 or in the CodeWalker GUI."""
    n_done = 0
    for n in names:
        m = manifests.get(n)
        if not m or not m.get("export", True) or m.get("quick"):
            continue
        src = os.path.join(out, n, "source")
        sx = os.path.join(src, n + ".ydr.xml")
        if not os.path.exists(sx):
            continue
        ddir = os.path.join(xml_dir, n)
        os.makedirs(ddir, exist_ok=True)
        keep = set()
        for f in os.listdir(os.path.join(src, n)):
            if f.endswith(".dds"):
                copy_file(os.path.join(src, n, f), os.path.join(ddir, f))
                keep.add(f)
        for f in os.listdir(ddir):
            if f.endswith(".dds") and f not in keep:
                os.remove(os.path.join(ddir, f))
        copy_file(sx, os.path.join(xml_dir, n + ".ydr.xml"))
        write_json(os.path.join(xml_dir, n + ".json"), m)
        n_done += 1
    return n_done


def prune_stale(out, xml_dir, registered):
    """Full builds only: drop outputs of props that are no longer registered."""
    for d in (xml_dir,):
        if not d or not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            base = f[:-8] if f.endswith(".ydr.xml") else (f[:-5] if f.endswith(".json") else f)
            if base.startswith(PREFIX) and base not in registered and base != YTYP_NAME:
                p = os.path.join(d, f)
                if os.path.isdir(p):
                    shutil.rmtree(p, ignore_errors=True)
                else:
                    os.remove(p)
                log(f"removed stale xml/{f}")
    for f in os.listdir(out):
        if f.startswith(PREFIX) and f not in registered and os.path.isdir(os.path.join(out, f)) and \
                os.path.exists(os.path.join(out, f, "manifest.json")) and not f.endswith("_assembled"):
            shutil.rmtree(os.path.join(out, f), ignore_errors=True)
            log(f"removed stale out/{f}")


def budget_report(manifests, names):
    over = []
    for n in names:
        m = manifests.get(n)
        if not m or not m.get("mem_est"):
            continue
        v, p = m["mem_est"]["virtual"], m["mem_est"]["physical"]
        if v > PAGE_LIMIT or p > PAGE_LIMIT:
            over.append(f"{n}: ~{mib(v)} MiB virtual, ~{mib(p)} MiB physical (estimate)")
    if over:
        for o in over:
            print("  OVER BUDGET", o)
    else:
        worst = max((max(manifests[n]["mem_est"]["virtual"], manifests[n]["mem_est"]["physical"]) for n in names
                     if n in manifests and manifests[n].get("mem_est")), default=0)
        log(f"memory budget ok (estimate): every drawable <= {PAGE_LIMIT // 1048576} MiB virtual and physical "
            f"(largest {mib(worst)} MiB)")
    return over


# ---------------------------------------------------------------------------------------------
# conversion + verification (needs .NET 8)
# ---------------------------------------------------------------------------------------------
def convert(cw, work_dir, items, ytyp_src, arch_count):
    """items: [(name, ydr.xml path, dds folder)]; writes <work_dir>/bin/*.ydr + nzr_props.ytyp."""
    bin_dir = os.path.join(work_dir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    lines = []
    for n, sx, dds in items:
        lines.append("\t".join(["ydr", sx, dds, os.path.join(bin_dir, n + ".ydr")]))
    lines.append("\t".join(["ytyp", ytyp_src, os.path.join(bin_dir, YTYP_NAME + ".ytyp")]))
    for n, _, _ in items:
        lines.append("\t".join(["inspect", os.path.join(bin_dir, n + ".ydr")]))
    lines.append("\t".join(["inspect", os.path.join(bin_dir, YTYP_NAME + ".ytyp")]))
    batch = os.path.join(work_dir, "cwtool_batch.txt")
    write_text(batch, "\n".join(lines) + "\n")
    r = subprocess.run(cw + ["batch", batch], capture_output=True, text=True)
    write_text(os.path.join(work_dir, "cwtool_log.txt"), r.stdout + r.stderr)
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
        raise SystemExit(f"cwtool reported errors (see {work_dir}/cwtool_log.txt)")
    m = re.search(r"Ytyp Name=.*archetypes=(\d+)", r.stdout)
    if not m or int(m.group(1)) != arch_count:
        raise SystemExit(f"ytyp archetype count mismatch ({m.group(1) if m else '?'} != {arch_count})")
    log(f"cwtool: {len(items)} drawables + {YTYP_NAME}.ytyp converted and verified ({arch_count} archetypes)")
    return bin_dir


def rsc_pages(path):
    """(virtual / system bytes, physical / graphics bytes) of an RSC7 resource, decoded from its page flags
    (CodeWalker RpfResourcePageFlags) - what the game allocates for it, not the compressed file size."""
    import struct
    with open(path, "rb") as f:
        head = f.read(16)
    if len(head) < 16 or head[:4] != b"RSC7":
        return None

    def size(fl):
        counts = (((fl >> 27) & 1), ((fl >> 26) & 1) << 1, ((fl >> 25) & 1) << 2, ((fl >> 24) & 1) << 3,
                  ((fl >> 17) & 0x7F) << 4, ((fl >> 11) & 0x3F) << 5, ((fl >> 7) & 0xF) << 6, ((fl >> 5) & 3) << 7,
                  ((fl >> 4) & 1) << 8)
        return (0x200 << (fl & 0xF)) * sum(counts)
    _, _, sysf, gfxf = struct.unpack("<4sIII", head)
    return size(sysf), size(gfxf)


def check_budget(bin_dir, names):
    """Refuse drawables above PAGE_LIMIT before anything is copied to stream/ (exact, from the binaries)."""
    over = []
    for n in names:
        p = os.path.join(bin_dir, n + ".ydr")
        pg = rsc_pages(p) if os.path.exists(p) else None
        if pg and (pg[0] > PAGE_LIMIT or pg[1] > PAGE_LIMIT):
            over.append(f"{n}: virtual {pg[0] / 1048576:.1f} MiB, physical {pg[1] / 1048576:.1f} MiB")
    if over:
        for o in over:
            print("  OVER BUDGET", o)
        raise SystemExit(f"{len(over)} drawable(s) above {PAGE_LIMIT // 1048576} MiB of pages - shrink their textures "
                         "(@prop maps= / atlas sizes) or split them")
    log(f"memory budget ok: every drawable <= {PAGE_LIMIT // 1048576} MiB virtual and physical (exact)")


def install_stream(bin_dir, stream, names, prune):
    os.makedirs(stream, exist_ok=True)
    for n in names:
        copy_file(os.path.join(bin_dir, n + ".ydr"), os.path.join(stream, n + ".ydr"))
    copy_file(os.path.join(bin_dir, YTYP_NAME + ".ytyp"), os.path.join(stream, YTYP_NAME + ".ytyp"))
    if prune:
        for f in os.listdir(stream):
            if f.startswith(PREFIX) and f.endswith(".ydr") and f[:-4] not in names:
                os.remove(os.path.join(stream, f))
                log(f"removed stale {f}")
    total = sum(os.path.getsize(os.path.join(stream, f)) for f in os.listdir(stream) if f.endswith((".ydr", ".ytyp")))
    log(f"stream: {len(names)} .ydr + {YTYP_NAME}.ytyp installed in {stream} ({total / 1048576:.2f} MB total)")


def convert_committed(args):
    """--convert-only: tools/props/xml/*.ydr.xml (+ DDS folders) -> binaries -> stream, no rebuild."""
    xml_dir = args.xml
    mans = {}
    for p in sorted(os.listdir(xml_dir)) if os.path.isdir(xml_dir) else []:
        if p.endswith(".json") and p.startswith(PREFIX):
            m = read_json(os.path.join(xml_dir, p))
            if m and m.get("export", True) and os.path.exists(os.path.join(xml_dir, m["name"] + ".ydr.xml")):
                mans[m["name"]] = m
    if not mans:
        raise SystemExit(f"nothing to convert in {xml_dir} (build with full quality first)")
    cw = ensure_cwtool(args.work, args.codewalker)
    work_dir = os.path.join(args.work, "convert")
    os.makedirs(work_dir, exist_ok=True)
    txt, count = ytyp_text(mans)
    ysrc = os.path.join(xml_dir, YTYP_NAME + ".ytyp.xml")
    write_text(ysrc, txt)
    items = [(n, os.path.join(xml_dir, n + ".ydr.xml"), os.path.join(xml_dir, n)) for n in sorted(mans)]
    bin_dir = convert(cw, work_dir, items, ysrc, count)
    check_budget(bin_dir, sorted(mans))
    install_stream(bin_dir, args.stream or DEFAULT_STREAM, sorted(mans), prune=True)


# ---------------------------------------------------------------------------------------------
# previews
# ---------------------------------------------------------------------------------------------
def render_list_entries(out, names, manifests, views, assemblies=True):
    lst = []
    asm = []
    for n in names:
        m = manifests.get(n) or {}
        pv = m.get("preview") or {}
        glb = os.path.join(out, n, n + ".glb")
        if not os.path.exists(glb):
            continue
        lst.append({"name": n, "glb": glb, "views": pv.get("views") or views, "cams": pv.get("cams", []),
                    "lights": pv.get("lights", [])})
        a = pv.get("assembly")
        if assemblies and a:
            base = os.path.join(out, a["base"], a["base"] + ".glb")
            parts = [{"glb": os.path.join(out, p["name"], p["name"] + ".glb"), "pos": p["pos"]} for p in a["parts"]]
            if os.path.exists(base) and all(os.path.exists(p["glb"]) for p in parts):
                lst.append({"name": a["name"], "glb": base, "parts": parts, "views": pv.get("views") or views,
                            "cams": pv.get("cams", []), "lights": pv.get("lights", [])})
                asm.append((a["name"], a["compare"], (pv.get("views") or views) + [c["name"] for c in pv.get("cams", [])]))
            else:
                log(f"assembled render of {a['compare']} skipped: build its body and every part first")
    return lst, asm


def run_renderer(out, work, entries, size, chromium=None):
    """Render entries into a private temp folder, then move the PNGs into <out>/renders atomically."""
    nm = ensure_preview_modules(work)
    rdir = os.path.join(out, "renders")
    os.makedirs(rdir, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".render-", dir=out)
    try:
        lpath = os.path.join(tmp, "render_list.json")
        with open(lpath, "w") as f:
            json.dump(entries, f)
        cmd = ["node", os.path.join(HERE, "preview", "render.mjs"), "--list", lpath, "--out", tmp, "--modules", nm,
               "--size", str(size)]
        if chromium:
            cmd += ["--chromium", chromium]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-3000:], r.stderr[-3000:])
            raise SystemExit("preview rendering failed")
        for f in os.listdir(tmp):
            if f.endswith(".png"):
                os.replace(os.path.join(tmp, f), os.path.join(rdir, f))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return rdir


def alignment_diffs(rdir, assemblies):
    """Compare each assembled render (body + parts at their anchors) with the complete model: writes
    <asm>_<view>_diff.png (differences x4) and returns {asm: {view: mismatch fraction}}. Misplaced
    parts light up as hard edges; texel-density / AO differences stay faint."""
    res = {}
    for asm, full, views in assemblies:
        sc = {}
        for v in views:
            pa, pb = os.path.join(rdir, f"{asm}_{v}.png"), os.path.join(rdir, f"{full}_{v}.png")
            if not (os.path.exists(pa) and os.path.exists(pb)):
                continue
            a = Image.open(pa).convert("RGB")
            b = Image.open(pb).convert("RGB")
            if a.size != b.size:
                continue
            d = ImageChops.difference(a, b).convert("L")
            hist = d.histogram()
            total = float(sum(hist))
            frac = sum(hist[48:]) / total
            sc[v] = round(frac, 5)
            amp = d.point(lambda x: min(255, x * 4))
            save_image(Image.merge("RGB", (amp, amp, amp)), os.path.join(rdir, f"{asm}_{v}_diff.png"))
            _ = ImageStat
        res[asm] = sc
        write_json(os.path.join(rdir, f"{asm}_alignment.json"), sc)
        worst = max((v for k, v in sc.items() if k != "screen"), default=0.0)   # the screen differs by design
        log(f"alignment {asm} vs {full}: worst view {worst * 100:.2f} % of pixels differ "
            f"({'ok' if worst < 0.01 else 'CHECK ' + rdir + '/' + asm + '_*_diff.png'})")
    return res


def contact_sheets(out, rdir, manifests, views, per_page=6, cell=360):
    sdir = os.path.join(out, "sheets")
    os.makedirs(sdir, exist_ok=True)
    names = sorted(n for n in manifests if os.path.exists(os.path.join(rdir, f"{n}_{((manifests[n].get('preview') or {}).get('views') or views)[0]}.png")))
    pages = [names[i:i + per_page] for i in range(0, len(names), per_page)]
    cols = 2
    pw = cols * (len(views) * cell + 24) + 24
    files = []
    for pi, page in enumerate(pages):
        rows = math.ceil(len(page) / cols)
        ph = 64 + rows * (cell + 58)
        sheet = Image.new("RGB", (pw, ph), (17, 19, 22))
        d = ImageDraw.Draw(sheet)
        d.text((24, 22), f"NAYZEEE Radio  -  props  ({pi + 1}/{len(pages)})", font=font("label", 22), fill=(230, 233, 235))
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
            d.text((cx, cy + cell + 6), n, font=font("label-semi", 17), fill=(8, 190, 176))
            med = f" / {m['tris_med']} med" if m.get("tris_med") else ""
            d.text((cx, cy + cell + 30), f"{dims} m   {m['tris']}{med} tris   lod {m['lodDist']:g}   "
                   f"{'static' if m['static'] else 'dynamic'}", font=font("mono", 13), fill=(160, 166, 170))
        fp = os.path.join(sdir, f"contact_{pi + 1:02d}.png")
        save_image(sheet, fp)
        files.append(fp)
    return files


def _row_sheet(rows, title, cell=300):
    """rows: [(label, [(caption, png path)])] -> one image."""
    ncol = max((len(r[1]) for r in rows), default=1)
    W = 24 + ncol * (cell + 8) + 16
    H = 64 + len(rows) * (cell + 52)
    sheet = Image.new("RGB", (W, H), (17, 19, 22))
    d = ImageDraw.Draw(sheet)
    d.text((24, 20), title, font=font("label", 22), fill=(230, 233, 235))
    for ri, (label, imgs) in enumerate(rows):
        y = 64 + ri * (cell + 52)
        d.text((24, y), label, font=font("label-semi", 16), fill=(8, 190, 176))
        for ci, (cap, p) in enumerate(imgs):
            x = 24 + ci * (cell + 8)
            if p and os.path.exists(p):
                sheet.paste(Image.open(p).convert("RGB").resize((cell, cell), Image.LANCZOS), (x, y + 24))
            d.text((x + 4, y + 28), cap, font=font("mono", 12), fill=(200, 204, 208))
    return sheet


def radio_sheets(out, rdir, manifests, keys, align):
    """Per radio: <key>_overview.png (complete / body / assembled, every view + close-up), <key>_parts.png
    (every part model with its action) and <key>_align.png (complete vs assembled vs difference)."""
    sdir = os.path.join(out, "sheets")
    os.makedirs(sdir, exist_ok=True)
    files = []
    for key in keys:
        full = manifests.get(f"nzr_{key}")
        if not full:
            continue
        pv = full.get("preview") or {}
        views = (pv.get("views") or []) + [c["name"] for c in pv.get("cams", [])]
        asm = (pv.get("assembly") or {}).get("name", f"nzr_{key}_assembled")
        rows = []
        for label, n in (("complete", f"nzr_{key}"), ("body (parts removed)", f"nzr_{key}_body"), ("assembled (body + parts at anchors)", asm)):
            rows.append((f"{label}  -  {n}", [(v, os.path.join(rdir, f"{n}_{v}.png")) for v in views]))
        img = _row_sheet(rows, f"NAYZEEE Radio  -  {key}  -  review")
        fp = os.path.join(sdir, f"{key}_overview.png")
        save_image(img, fp)
        files.append(fp)
        keys_ = (full.get("anchors") or {}).get("keys", [])
        prow = []
        for i in range(0, len(keys_), 8):
            chunk = keys_[i:i + 8]
            prow.append(("  ".join(k["id"] for k in chunk),
                         [(f"{k['id']} {k['action']}{(' ' + k['value']) if k.get('value') else ''}  {k.get('tris', 0)}t",
                           os.path.join(rdir, f"{k['model']}_front.png")) for k in chunk]))
        if prow:
            fp = os.path.join(sdir, f"{key}_parts.png")
            save_image(_row_sheet(prow, f"NAYZEEE Radio  -  {key}  -  part models", cell=220), fp)
            files.append(fp)
        sc = align.get(asm, {})
        arow = []
        for v in [v for v in views if v in sc][:6]:
            arow.append((f"{v}: {sc[v] * 100:.2f} % differ", [("complete", os.path.join(rdir, f"nzr_{key}_{v}.png")),
                                                            ("assembled", os.path.join(rdir, f"{asm}_{v}.png")),
                                                            ("difference x4", os.path.join(rdir, f"{asm}_{v}_diff.png"))]))
        if arow:
            fp = os.path.join(sdir, f"{key}_align.png")
            save_image(_row_sheet(arow, f"NAYZEEE Radio  -  {key}  -  alignment", cell=260), fp)
            files.append(fp)
    return files


# ---------------------------------------------------------------------------------------------
# docs
# ---------------------------------------------------------------------------------------------
MODULE_TITLES = {
    "props.handheld": "PX-740 patrol handheld", "props.fieldpro": "FX-280 field radio", "props.military": "MX-905 tactical radio",
    "props.leds": "LED inserts", "props.jammers": "Jammers", "props.earpiece": "Earpiece (icon only)",
    "props._example_radio": "Example radio (not shipped)",
}


def lua_refs(name):
    """Lua files of nayzeee-radio that mention a model name (config / client code)."""
    root = os.path.normpath(os.path.join(HERE, "..", ".."))
    hits = []
    for sub in ("config", "client", "shared", "server"):
        d = os.path.join(root, sub)
        for dp, _, fs in os.walk(d):
            for f in fs:
                if f.endswith(".lua") and f != "props_layout.lua":
                    p = os.path.join(dp, f)
                    try:
                        if f"'{name}'" in open(p, encoding="utf-8").read():
                            hits.append(os.path.relpath(p, root))
                    except OSError:
                        pass
    return hits


def _maps_note(t):
    mp, S = t.get("maps"), t.get("size")
    if not mp or isinstance(S, list):
        return ""
    d = S if S <= 1024 else S // 2
    return "" if mp == [d, d] else f" (normal {mp[0]} / spec {mp[1]})"


def catalog_md(manifests):
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
            refs = ", ".join(f"`{r}`" for r in lua_refs(n)) or "-"
            out.append(f"| Referenced by | {refs} |")
            dims = " x ".join(f"{v:.3f}" for v in m["dims"])
            out.append(f"| Size X x Y x Z | {dims} m (bbMin {tuple(round(v, 3) for v in m['bbMin'])}, bbMax "
                       f"{tuple(round(v, 3) for v in m['bbMax'])}) |")
            for k, lab in (("origin", "Origin / pivot"), ("axes", "Axes"), ("attach", "Attach / use"), ("screen", "Screen")):
                if d.get(k):
                    out.append(f"| {lab} | {d[k]} |")
            typ = "static" if m["static"] else "dynamic"
            lod = f"lodDist {m['lodDist']:g} m"
            if m.get("lodHigh"):
                lod += f", high model to {m['lodHigh']:g} m then medium"
            out.append(f"| LOD / type | {lod}, hdTextureDist {m['hdTextureDist']:g} m, {typ}{'' if m.get('export', True) else ', NOT exported'} |")
            cols = {}
            for c in m["collision"]:
                cols[(c["type"], c["material"])] = cols.get((c["type"], c["material"]), 0) + 1
            out.append("| Collision | " + ", ".join(f"{v} {t} {mat}" for (t, mat), v in sorted(cols.items())) + " (embedded composite) |")
            tex = ", ".join(f"{t['name']} {t['size'] if not isinstance(t['size'], list) else 'x'.join(map(str, t['size']))}"
                            + _maps_note(t) for t in m["textures"])
            out.append(f"| Textures (txd = `{n}`) | {tex} |")
            med = f" (medium {m['tris_med']})" if m.get("tris_med") else ""
            mem = m.get("mem_est") or {}
            out.append(f"| Mesh | {m['tris']} tris{med}, {m['verts']} verts, shaders: {', '.join(sorted(set(m['shaders'])))}, "
                       f"memory ~{mib(mem.get('virtual', 0))} MiB virtual / ~{mib(mem.get('physical', 0))} MiB physical |")
            out.append("")
    return "\n".join(out) + "\n"


def write_tables(out, manifests, docs=None):
    slim = {n: {k: v for k, v in m.items() if k != "archetype_xml"} for n, m in sorted(manifests.items())}
    write_json(os.path.join(out, "props_manifest.json"), slim)
    lines = ["| Model | Size X x Y x Z (m) | Tris (high / med) | lodDist | Memory est. (MiB virt / phys) | Screens | Collision |",
             "|---|---|---|---|---|---|---|"]
    for n, m in slim.items():
        col = ", ".join(sorted({c["material"] for c in m["collision"]}))
        mem = m.get("mem_est") or {}
        lines.append(f"| `{n}`{'' if m.get('export', True) else ' (not exported)'} | {' x '.join(f'{v:.3f}' for v in m['dims'])} | "
                     f"{m['tris']}{' / ' + str(m['tris_med']) if m.get('tris_med') else ''} | {m['lodDist']:g} | "
                     f"{mib(mem.get('virtual', 0))} / {mib(mem.get('physical', 0))} | {', '.join(m['screens']) or '-'} | {col} |")
    table = "\n".join(lines) + "\n"
    write_text(os.path.join(out, "props_table.md"), table)
    cat = catalog_md(slim)
    write_text(os.path.join(out, "props_catalog.md"), cat)
    if docs and os.path.exists(docs):
        s = open(docs, encoding="utf-8").read()
        changed = False
        for (a, b), body in ((("<!-- props:table:begin -->", "<!-- props:table:end -->"), table),
                             (("<!-- props:catalog:begin -->", "<!-- props:catalog:end -->"), cat)):
            if a in s and b in s:
                s = s.split(a)[0] + a + "\n" + body + b + s.split(b)[1]
                changed = True
        if changed:
            write_text(docs, s)
            log(f"updated generated sections in {docs}")
    return table


# ---------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(DEFAULT_WORK, "out"), help="build folder (XML, DDS, glb, renders)")
    ap.add_argument("--work", default=DEFAULT_WORK, help="tool cache (CodeWalker clone, cwtool build, node modules)")
    ap.add_argument("--stream", default=None, help="stream/ folder: convert with cwtool (.NET 8) and install there "
                    f"(e.g. ../nayzeee-radio-props/stream; --convert uses {DEFAULT_STREAM})")
    ap.add_argument("--convert", action="store_true", help="convert + verify with cwtool and install into the default stream")
    ap.add_argument("--no-convert", action="store_true", help="never convert (the default unless --stream / --convert is given)")
    ap.add_argument("--convert-only", action="store_true", help="convert the committed tools/props/xml without rebuilding")
    ap.add_argument("--codewalker", default=None, help="existing CodeWalker checkout to use")
    ap.add_argument("--only", default=None, help="comma separated names/globs to rebuild (others keep their outputs)")
    ap.add_argument("--examples", action="store_true", help=f"also load props/_*.py example modules (or {EXAMPLES_ENV}=1)")
    ap.add_argument("--jobs", type=int, default=max(1, min(4, os.cpu_count() or 1)))
    ap.add_argument("--quick", action="store_true", help="skip ambient occlusion (fast iteration, never exported to xml/)")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--views", default="front,back,top", help="default review views of props that declare none")
    ap.add_argument("--size", type=int, default=640, help="preview render size")
    ap.add_argument("--chromium", default=None, help="chromium executable for the renders")
    ap.add_argument("--xml", default=DEFAULT_XML, help="committed CodeWalker XML + DDS folder")
    ap.add_argument("--no-xml", action="store_true", help="do not refresh the committed xml folder")
    ap.add_argument("--layout", default=DEFAULT_LAYOUT, help="props_layout.lua to regenerate ('none' to skip)")
    ap.add_argument("--layout-radios", default=",".join(gen_layout.RADIO_ORDER), help="radio keys written to the layout")
    ap.add_argument("--docs", default=None, help="markdown file whose props:table / props:catalog sections get refreshed")
    ap.add_argument("--list", action="store_true", help="list registered props and exit")
    ap.add_argument("--docs-only", action="store_true", help="only rewrite tables / docs / layout from existing manifests")
    args = ap.parse_args()
    examples = args.examples or os.environ.get(EXAMPLES_ENV, "") not in ("", "0")
    if examples:
        os.environ[EXAMPLES_ENV] = "1"
    t_start = time.time()

    if args.convert_only:
        convert_committed(args)
        return

    load_props(examples)
    names_all = sorted(REGISTRY)
    if args.list:
        for n in names_all:
            s = REGISTRY[n]
            print(f"{n:34s} {s.module:26s} atlas {s.atlas:4d}{'' if s.export else '  (not exported)'}")
        for mod, tb in IMPORT_FAILURES.items():
            print(f"(skipped props/{mod}.py: {tb.strip().splitlines()[-1]})")
        return
    os.makedirs(args.out, exist_ok=True)
    xml_dir = None if args.no_xml else args.xml
    if args.docs_only:
        all_m = collect_manifests(args.out, xml_dir)
        write_tables(args.out, all_m, args.docs)
        if args.layout != "none":
            p, ok, msg = gen_layout.write_layout(all_m, args.layout, args.layout_radios.split(","))
            log(f"layout {p} (luac: {'ok' if ok else msg})")
        return

    # selection ------------------------------------------------------------------------
    sel = names_all
    if args.only:
        pats = [p.strip() for p in args.only.split(",") if p.strip()]
        sel = [n for n in names_all if any(fnmatch.fnmatch(n, p) or n == p for p in pats)]
        hit_failed = {mod: tb for mod, tb in IMPORT_FAILURES.items()
                      if any(mod.lstrip("_") in p for p in pats) or any(not any(fnmatch.fnmatch(n, p) for n in names_all) for p in pats)}
        if hit_failed:
            for mod, tb in hit_failed.items():
                print(f"\nprops/{mod}.py failed to import:\n{tb}")
            raise SystemExit(f"--only {args.only}: the module(s) {', '.join(hit_failed)} do not import (see above)")
        if not sel:
            raise SystemExit(f"--only matched nothing ({args.only}); --list shows the registered props")
    sel = sorted(sel, key=_cost)
    convert_on = (args.convert or args.stream is not None) and not args.no_convert

    # build --------------------------------------------------------------------------------
    log(f"building {len(sel)} prop(s) with {args.jobs} job(s){' (quick: no AO)' if args.quick else ''}")
    t0 = time.time()
    errors = dict(prewarm_designs(sel))
    for n, tb in errors.items():
        log(f"FAILED {n} (radio design)")
    todo = [n for n in sel if n not in errors]
    if errors:
        print(next(iter(errors.values())))
    built = {}
    ctx = mp.get_context("fork") if hasattr(os, "fork") else mp.get_context("spawn")
    with ctx.Pool(max(1, min(args.jobs, len(todo) or 1))) as pool:
        for name, man, err in pool.imap_unordered(_build_one, [(n, args.out, args.quick, examples) for n in todo]):
            if err:
                errors[name] = err
                log(f"FAILED {name}")
                print(err)
            else:
                built[name] = man
                w = f"  ! {'; '.join(man['warnings'])}" if man.get("warnings") else ""
                med = f"/{man['tris_med']:<6d}" if man.get("tris_med") else " " * 7
                log(f"built {name:32s} {man['tris']:6d}{med} tris  {man['build_seconds']:5.1f}s{w}")
    log(f"geometry + textures done in {time.time() - t0:.1f}s ({len(built)} ok, {len(errors)} failed)")

    # aggregate (everything that built cleanly so far) ------------------------------------------
    problems = []
    with FileLock(os.path.join(args.out, ".aggregate.lock")):
        all_m = collect_manifests(args.out, xml_dir)
        all_m.update(built)
        write_tables(args.out, all_m, args.docs)
        txt, count = ytyp_text(all_m)
        write_text(os.path.join(args.out, YTYP_NAME + ".ytyp.xml"), txt)
        if xml_dir:
            n_x = export_xml(args.out, xml_dir, sorted(built), all_m)
            write_text(os.path.join(xml_dir, YTYP_NAME + ".ytyp.xml"), ytyp_text(collect_manifests(args.out, xml_dir))[0])
            if n_x:
                log(f"xml: {n_x} prop(s) exported to {xml_dir} (CodeWalker XML + DDS, committed for conversion)")
            elif built and args.quick:
                log("xml: quick build - tools/props/xml left untouched (run without --quick to refresh it)")
        if not args.only and not IMPORT_FAILURES and not errors:
            prune_stale(args.out, xml_dir, set(names_all))
        if args.layout != "none":
            radios = [r.strip() for r in args.layout_radios.split(",") if r.strip()]
            p, ok, msg = gen_layout.write_layout(all_m, args.layout, radios)
            log(f"layout: {p} written (luac -p: {'ok' if ok else ('not installed' if ok is None else 'FAILED')})")
            if ok is False:
                print(msg)
                problems.append("props_layout.lua does not parse")
    over = budget_report(all_m, sorted(built))
    if over:
        problems.append(f"{len(over)} drawable(s) over the memory budget")

    # conversion -------------------------------------------------------------------------------
    if convert_on and not errors and not over:
        cw = ensure_cwtool(args.work, args.codewalker)
        ex = exported(all_m)
        missing = [n for n in ex if not os.path.exists(os.path.join(args.out, n, "source", n + ".ydr.xml"))]
        if missing:
            raise SystemExit(f"cannot convert: never built here: {', '.join(missing[:8])} - run a full build first")
        items = [(n, os.path.join(args.out, n, "source", n + ".ydr.xml"), os.path.join(args.out, n, "source", n)) for n in sorted(ex)]
        bin_dir = convert(cw, args.out, items, os.path.join(args.out, YTYP_NAME + ".ytyp.xml"), count)
        check_budget(bin_dir, sorted(ex))
        install_stream(bin_dir, args.stream or DEFAULT_STREAM, sorted(ex), prune=not args.only and not IMPORT_FAILURES)
    elif convert_on:
        log("conversion skipped: fix the errors above first")
    else:
        log("conversion skipped (no --stream / --convert): XML + DDS are ready for tools/props/convert.sh")

    # previews ---------------------------------------------------------------------------------
    if not args.no_preview and built:
        views = [v.strip() for v in args.views.split(",") if v.strip()]
        tr = time.time()
        entries, asm = render_list_entries(args.out, sorted(built), all_m, views)
        rdir = run_renderer(args.out, args.work, entries, args.size, args.chromium)
        align = alignment_diffs(rdir, asm)
        sheets = contact_sheets(args.out, rdir, all_m, views)
        keys = sorted({(m.get("anchors") or {}).get("radio") for m in built.values() if (m.get("anchors") or {}).get("radio")})
        sheets += radio_sheets(args.out, rdir, all_m, keys, align)
        log(f"renders: {len(entries)} model(s) in {time.time() - tr:.1f}s -> {rdir}")
        log("sheets: " + ", ".join(sheets))
    log(f"done in {time.time() - t_start:.1f}s")
    if errors or problems:
        for p in problems:
            log("PROBLEM: " + p)
        raise SystemExit(f"{len(errors)} prop(s) failed{': ' + ', '.join(sorted(errors)) if errors else ''}"
                         f"{'; ' + '; '.join(problems) if problems else ''}")


if __name__ == "__main__":
    main()
