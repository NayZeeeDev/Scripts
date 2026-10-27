#!/usr/bin/env python3
"""Product-shot renderer for the nayzeee props: transparent PNGs from the build's GLB files.

A hand-written WebGL2 renderer (render/renderer.js + render/shaders.js) runs in the preinstalled headless
Chromium through Playwright (render/run.js).  It does GGX PBR with normal maps and anisotropic
grooves, a procedural soft-box studio, soft shadows, ambient occlusion, a contact shadow on a transparent
floor, bloom, ACES/AgX tone mapping and heavy supersampling (32-64 jittered samples per pixel).

    python3 render.py --model nayzeee_vinyl                          # -> out/previews/nayzeee_vinyl.png (512 px)
    python3 render.py --model nayzeee_vinyl --size 1024 --out shot.png --yaw 35 --pitch 18 --fov 30
    python3 render.py --model nayzeee_vinyl --quick                  # fast draft while modelling
    python3 render.py --parts nayzeee_audio_g nayzeee_tt_platter:0.3,0,0.785 nayzeee_vinyl:0.3,0,0.811 \\
                      "nayzeee_tt_arm:0.075,-0.125,0.835:0,0,-33.6" --out console.png    # arm at groove radius 0.12
    python3 render.py --scene render/scenes/console_playing.json --out console.png
    python3 render.py --model nayzeee_vinyl --yaws 0,35,70 --out strip.png       # several angles in one row
    python3 render.py --model nayzeee_vinyl --turntable 12 --out tt.png          # tt_000..011.png + tt_grid.png + tt.webp
    python3 render.py --sheet out/previews/contact_sheet.png                      # every exported model, labelled grid

Part spec (--parts): NAME[:x,y,z[:rx,ry,rz[:scale]]] or with keys NAME:pos=x,y,z:rot=rx,ry,rz:scale=s:parent=I.
NAME is a model name (models/<NAME>.py) or a path to a .glb.  Positions are metres in GTA model space
(+Z up, +Y front, +X viewer's left), rotations are degrees applied X, then Y, then Z (R = Rz*Ry*Rx).
parent=I places the part relative to an earlier part (0-based index or its model name).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

RENDER_DIR = os.path.join(ROOT, "render")
OUT_GLB = os.path.join(ROOT, "out", "glb")
CACHE_GLB = os.path.join(ROOT, "cache", "render", "glb")
PREVIEW_DIR = os.path.join(ROOT, "out", "previews")
LAYOUT = os.path.join(ROOT, "out", "layout.json")

QUALITY = {               # soft-box frames (soft shadows), environment frames (anti-aliasing), AO directions
    "draft": (24, 16, 128),
    "normal": (96, 32, 384),
    "high": (192, 64, 768),
}
DEFAULTS = {
    "size": "512", "yaw": 35.0, "pitch": 18.0, "fov": 30.0, "margin": 0.06, "distance_scale": None,
    "bg": "transparent", "exposure": 1.0, "tonemap": "aces", "quality": "normal", "samples": None,
    "ao_samples": None, "shadow": 1.0, "bloom": 1.0, "spec_occlusion": 1.0, "ground": "auto",
}


# --------------------------------------------------------------------------- matrices (GTA space, column-major out)
def _rot(axis: str, deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    m = np.eye(4)
    if axis == "x":
        m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, -s, s, c
    elif axis == "y":
        m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c
    else:
        m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
    return m


def trs(pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0) -> np.ndarray:
    """4x4 = T * Rz * Ry * Rx * S (rotations in degrees)."""
    t = np.eye(4)
    t[:3, 3] = pos
    s = np.eye(4)
    sc = scale if isinstance(scale, (list, tuple)) else (scale, scale, scale)
    s[0, 0], s[1, 1], s[2, 2] = sc
    return t @ _rot("z", rot[2]) @ _rot("y", rot[1]) @ _rot("x", rot[0]) @ s


def _floats(txt: str, n: int, what: str):
    v = [float(x) for x in txt.split(",") if x.strip() != ""]
    if len(v) == 1 and n == 3 and what == "scale":
        return v[0]
    if len(v) != n:
        raise ValueError(f"{what} needs {n} comma-separated numbers, got {txt!r}")
    return v


def parse_part(spec: str) -> dict:
    """'NAME[:x,y,z[:rx,ry,rz[:s]]]' or 'NAME:pos=..:rot=..:scale=..:parent=..' -> part dict."""
    # model paths may contain ':' only on Windows drive letters; allow 'C:\\..' by re-joining
    bits = spec.split(":")
    if len(bits) > 1 and len(bits[0]) == 1 and bits[1].startswith(("\\", "/")):
        bits = [bits[0] + ":" + bits[1]] + bits[2:]
    part = {"model": bits[0], "pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0], "scale": 1.0}
    positional = ["pos", "rot", "scale"]
    pi = 0
    for b in bits[1:]:
        if not b:
            continue
        if "=" in b:
            k, v = b.split("=", 1)
            k = k.strip().lower()
            if k in ("pos", "p", "at"):
                part["pos"] = _floats(v, 3, "pos")
            elif k in ("rot", "r"):
                part["rot"] = _floats(v, 3, "rot")
            elif k in ("scale", "s"):
                part["scale"] = _floats(v, 3, "scale") if "," in v else float(v)
            elif k == "parent":
                part["parent"] = int(v) if v.strip().lstrip("-").isdigit() else v.strip()
            else:
                raise ValueError(f"unknown part key {k!r} in {spec!r}")
        else:
            if pi >= len(positional):
                raise ValueError(f"too many fields in part spec {spec!r}")
            k = positional[pi]
            pi += 1
            part[k] = _floats(b, 3, k) if k != "scale" or "," in b else float(b)
    return part


def resolve_matrices(parts: list) -> list:
    """World matrices for parts (parents first)."""
    mats = []
    for i, p in enumerate(parts):
        m = trs(p.get("pos", (0, 0, 0)), p.get("rot", (0, 0, 0)), p.get("scale", 1.0))
        par = p.get("parent")
        if par is not None:
            if isinstance(par, str):
                idx = [j for j, q in enumerate(parts[:i]) if q["model"] == par]
                if not idx:
                    raise ValueError(f"part {p['model']}: parent {par!r} is not an earlier part")
                par = idx[-1]
            if not 0 <= par < i:
                raise ValueError(f"part {p['model']}: parent index {par} must refer to an earlier part")
            m = mats[par] @ m
        mats.append(m)
    return mats


# --------------------------------------------------------------------------- GLB sources
def _newest_source_mtime(name: str) -> float:
    paths = [os.path.join(ROOT, "models", f"{name}.py")]
    for d in ("lib", "models"):
        for f in os.listdir(os.path.join(ROOT, d)):
            if f.endswith(".py") and (d == "lib" or f.startswith("_")):
                paths.append(os.path.join(ROOT, d, f))
    return max(os.path.getmtime(p) for p in paths if os.path.isfile(p))


def build_glb(name: str, dest_dir: str = CACHE_GLB) -> str:
    """Build models/<name>.py in-process and write its GLB to ``dest_dir`` (never touches out/)."""
    import models
    from lib import glb
    os.makedirs(dest_dir, exist_ok=True)
    spec = models.build(name, 1.0)
    path = os.path.join(dest_dir, f"{name}.glb")
    tmp = path + ".tmp"
    glb.write_glb(tmp, name, spec.parts)
    os.replace(tmp, path)
    with open(path + ".meta.json", "w") as f:
        json.dump({"export": bool(spec.export), "description": spec.description or "",
                   "render": (spec.meta or {}).get("render", {})}, f)
    return path


def resolve_glb(name: str, policy: str = "auto", log=print) -> str:
    """Path of the GLB for a model name or .glb path.

    policy: 'auto' = out/glb/<name>.glb if it is newer than the model + lib sources, else a fresh in-process
    build cached in cache/render/glb; 'out' = always out/glb; 'fresh' = always rebuild into the cache.
    """
    if name.lower().endswith(".glb") or os.sep in name or "/" in name:
        p = os.path.abspath(name)
        if not os.path.isfile(p):
            raise FileNotFoundError(f"GLB not found: {p}")
        return p
    src = os.path.join(ROOT, "models", f"{name}.py")
    out_p = os.path.join(OUT_GLB, f"{name}.glb")
    cache_p = os.path.join(CACHE_GLB, f"{name}.glb")
    if policy == "out" or not os.path.isfile(src):
        if not os.path.isfile(out_p):
            raise FileNotFoundError(f"no GLB for {name!r}: {out_p} is missing"
                                    + ("" if os.path.isfile(src) else f" and models/{name}.py does not exist"))
        return out_p
    if policy != "fresh":
        newest = _newest_source_mtime(name)
        for p in (out_p, cache_p):
            if os.path.isfile(p) and os.path.getmtime(p) >= newest:
                return p
    t0 = time.time()
    p = build_glb(name)
    log(f"render: built {name}.glb from models/{name}.py ({time.time() - t0:.1f} s)")
    return p


def model_render_hints(name: str) -> dict:
    """Preferred camera/look for a model: render/cameras.json, then the model's meta["render"] (layout.json)."""
    hints = {}
    try:
        with open(os.path.join(RENDER_DIR, "cameras.json")) as f:
            hints.update(json.load(f).get(name, {}))
    except (OSError, ValueError):
        pass
    try:
        with open(LAYOUT) as f:
            hints.update(json.load(f)["models"].get(name, {}).get("meta", {}).get("render", {}))
    except (OSError, ValueError, KeyError):
        pass
    meta = os.path.join(CACHE_GLB, f"{name}.glb.meta.json")
    if os.path.isfile(meta):
        try:
            with open(meta) as f:
                hints.update(json.load(f).get("render", {}))
        except (OSError, ValueError):
            pass
    return {k.replace("-", "_"): v for k, v in hints.items() if not k.startswith("_")}


def model_export_flag(name: str) -> bool:
    """True when the model is exported to the game (layout.json / cache meta), building it if unknown."""
    try:
        with open(LAYOUT) as f:
            lay = json.load(f)["models"]
        if name in lay and "export" in lay[name]:
            return bool(lay[name]["export"])
    except (OSError, ValueError, KeyError):
        pass
    meta = os.path.join(CACHE_GLB, f"{name}.glb.meta.json")
    if not os.path.isfile(meta):
        build_glb(name)
    with open(meta) as f:
        return bool(json.load(f)["export"])


# --------------------------------------------------------------------------- browser driver
def node_env() -> dict:
    env = dict(os.environ)
    if "NODE_PATH" not in env or not os.path.isdir(os.path.join(env["NODE_PATH"], "playwright")):
        root = None
        try:
            root = subprocess.run(["npm", "root", "-g"], capture_output=True, text=True, timeout=60).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        for cand in (root, "/opt/node22/lib/node_modules", "/usr/lib/node_modules", "/usr/local/lib/node_modules"):
            if cand and os.path.isdir(os.path.join(cand, "playwright")):
                env["NODE_PATH"] = cand
                break
    return env


def run_jobs(jobs: list, verbose: bool = False) -> list:
    """Render job dicts in one browser session -> list of (RGBA uint8 array top-down, stats)."""
    if shutil.which("node") is None:
        raise RuntimeError("node is not installed (needed to drive headless Chromium)")
    with tempfile.TemporaryDirectory(prefix="nz_render_") as tmp:
        for i, j in enumerate(jobs):
            j["out"] = os.path.join(tmp, f"job{i:04d}.raw")
        jf = os.path.join(tmp, "jobs.json")
        with open(jf, "w") as f:
            json.dump({"verbose": verbose, "jobs": jobs}, f)
        proc = subprocess.run(["node", os.path.join(RENDER_DIR, "run.js"), jf], env=node_env(),
                              stderr=None if verbose else subprocess.PIPE, text=True)
        results = []
        for j in jobs:
            if not os.path.isfile(j["out"]):
                err = (proc.stderr or "").strip() if not verbose else ""
                raise RuntimeError(f"render failed for {j.get('label', '?')}" + (f":\n{err}" if err else ""))
            w, h = j["width"], j["height"]
            a = np.frombuffer(open(j["out"], "rb").read(), np.uint8).reshape(h, w, 4)[::-1].copy()
            with open(j["out"] + ".json") as f:
                stats = json.load(f)
            results.append((a, stats))
        if proc.returncode != 0 and not verbose and proc.stderr:
            sys.stderr.write(proc.stderr)
        return results


# --------------------------------------------------------------------------- options -> job
def parse_size(txt) -> tuple:
    txt = str(txt).lower()
    if "x" in txt:
        w, h = txt.split("x", 1)
        return int(w), int(h)
    return int(txt), int(txt)


def parse_bg(txt):
    if txt is None or str(txt).lower() in ("", "none", "transparent", "alpha"):
        return None
    t = str(txt).lstrip("#")
    if len(t) == 3:
        t = "".join(c * 2 for c in t)
    if len(t) != 6:
        raise ValueError(f"--bg wants transparent or #rrggbb, got {txt!r}")
    return [int(t[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def load_overrides(extra: str | None) -> dict:
    with open(os.path.join(RENDER_DIR, "materials.json")) as f:
        ov = {k: v for k, v in json.load(f).items() if not k.startswith("_")}
    if extra:
        with open(extra) as f:
            for k, v in json.load(f).items():
                if not k.startswith("_"):
                    ov[k] = {**ov.get(k, {}), **v}
    return ov


def make_job(opts: dict, parts: list, glbs: list, label: str, **camera_extra) -> dict:
    w, h = parse_size(opts["size"])
    q = QUALITY[opts["quality"]]
    mats = [p["matrix"] for p in parts] if all("matrix" in p for p in parts) else resolve_matrices(parts)
    cam = {"yaw": float(opts["yaw"]), "pitch": float(opts["pitch"]), "fov": float(opts["fov"]),
           "margin": float(opts["margin"])}
    if opts.get("distance_scale"):
        cam["distanceScale"] = float(opts["distance_scale"])
    for k in ("target", "distance", "eye"):
        if opts.get(k) is not None:
            cam[k] = opts[k]
    cam.update(camera_extra)
    ground = opts.get("ground", "auto")
    if ground in (None, "none", "off") or float(opts["shadow"]) <= 0:
        ground_v = None
    elif ground == "auto":
        ground_v = "auto"
    else:
        ground_v = float(ground)
    job = {
        "label": label, "width": w, "height": h,
        "instances": [{"glb": g, "matrix": [float(x) for x in m.T.reshape(-1)], "name": p["model"]}
                      for p, g, m in zip(parts, glbs, mats)],
        "camera": cam,
        "samples": int(opts["samples"] or q[0]), "aoSamples": int(opts["ao_samples"] or q[2]),
        "exposure": float(opts["exposure"]), "tonemap": opts["tonemap"], "shadow": float(opts["shadow"]),
        "bloom": float(opts["bloom"]), "background": parse_bg(opts["bg"]),
        "specOcclusion": float(opts["spec_occlusion"]), "overrides": opts["overrides"],
    }
    if not opts["samples"]:
        job["envSamples"] = q[1]
    if ground_v != "auto":
        job["ground"] = ground_v
    if opts.get("debug"):
        job["debug"] = opts["debug"]
    if opts.get("rig"):
        job["rig"] = opts["rig"]
    return job


def save_png(arr: np.ndarray, path: str):
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    Image.fromarray(arr, mode).save(path, compress_level=7)


# --------------------------------------------------------------------------- sheets
def _font(size, weight=500):
    try:
        from lib import fonts
        return fonts.pil_font(size, weight)
    except Exception:  # noqa: BLE001 - fonttools missing: fall back to Pillow's default font
        from PIL import ImageFont
        return ImageFont.load_default()


def _spaced(draw, xy, text, font, fill, spacing):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + spacing
    return x


def _spaced_width(draw, text, font, spacing):
    return sum(draw.textlength(ch, font=font) for ch in text) + spacing * max(0, len(text) - 1)


def grid(images: list, labels: list, cols: int, title: str | None = None, sub: list | None = None,
         bg=(21, 24, 26), card=(30, 33, 36)) -> Image.Image:
    """Labelled contact sheet: transparent renders composited on soft dark cards."""
    cw, ch = images[0].shape[1], images[0].shape[0]
    pad, lab = max(10, cw // 24), max(30, cw // 8)
    rows = math.ceil(len(images) / cols)
    head = (lab + pad) if title else 0
    W = cols * cw + (cols + 1) * pad
    H = head + rows * (ch + lab) + (rows + 1) * pad
    sheet = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(sheet)
    f_lab = _font(max(11, cw // 30), 600)
    f_sub = _font(max(10, cw // 40), 400)
    if title:
        ft = _font(max(14, cw // 22), 600)
        d.rounded_rectangle((pad, pad + lab * 0.18, pad + lab * 0.55, pad + lab * 0.73), radius=lab * 0.08,
                            fill=(8, 175, 162))
        _spaced(d, (pad + lab * 0.75, pad + lab * 0.16), title.upper(), ft, (236, 238, 240), max(1, cw // 160))
    for i, (img, text) in enumerate(zip(images, labels)):
        r, c = divmod(i, cols)
        x = pad + c * (cw + pad)
        y = head + pad + r * (ch + lab + pad)
        d.rounded_rectangle((x, y, x + cw - 1, y + ch + lab - 1), radius=max(4, cw // 64), fill=card + (255,))
        tile = Image.fromarray(img, "RGBA")
        sheet.alpha_composite(tile, (x, y))
        tx = x + max(8, cw // 32)
        _spaced(d, (tx, y + ch + lab * 0.08), text.upper(), f_lab, (230, 232, 235), max(1, cw // 220))
        if sub and sub[i]:
            d.text((tx, y + ch + lab * 0.52), sub[i], font=f_sub, fill=(140, 146, 152))
    return sheet


# --------------------------------------------------------------------------- CLI
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    what = ap.add_argument_group("what to render")
    what.add_argument("--model", help="model name (models/<name>.py) or a .glb path")
    what.add_argument("--parts", nargs="+", metavar="SPEC", help="compose several models (see part spec above)")
    what.add_argument("--scene", help="JSON scene file: {parts: [{model, pos, rot, scale, parent}], camera: {...}, render: {...}}")
    what.add_argument("--sheet", metavar="PNG", help="render every exported model into a labelled grid")
    what.add_argument("--all", action="store_true", help="with --sheet: include image-only models (export=False)")
    out = ap.add_argument_group("output")
    out.add_argument("--out", help="output PNG (default out/previews/<model>.png)")
    out.add_argument("--size", help="pixels: 512 or WxH (default 512; sheet cells 384)")
    out.add_argument("--yaws", help="comma list of yaws -> one image per angle, side by side in --out")
    out.add_argument("--turntable", type=int, metavar="N", help="N frames around the model: <out>_000.png.., <out>_grid.png, <out>.webp")
    out.add_argument("--cols", type=int, help="columns of the sheet / turntable grid")
    cam = ap.add_argument_group("camera")
    cam.add_argument("--yaw", type=float, help="degrees; 0 = straight at the front (+Y), positive orbits to the viewer's right (default 35)")
    cam.add_argument("--pitch", type=float, help="degrees above the horizon (default 18)")
    cam.add_argument("--fov", type=float, help="vertical field of view in degrees (default 30)")
    cam.add_argument("--margin", type=float, help="empty border per side as a fraction of the frame (default 0.06)")
    cam.add_argument("--distance-scale", type=float, help="pull the camera back (>1) or in (<1) from the auto framing")
    look = ap.add_argument_group("look")
    look.add_argument("--bg", help="transparent (default) or #rrggbb")
    look.add_argument("--exposure", type=float, help="linear exposure multiplier (default 1.0)")
    look.add_argument("--tonemap", choices=["aces", "agx", "neutral", "linear"], help="tone curve (default aces)")
    look.add_argument("--quality", choices=sorted(QUALITY), help="draft / normal / high sample counts (default normal)")
    look.add_argument("--quick", action="store_true", help="= --quality draft (fast check while modelling)")
    look.add_argument("--samples", type=int, help="soft-box frames (soft-shadow samples); anti-aliasing frames follow as max(16, N/3)")
    look.add_argument("--ao-samples", type=int, help="ambient-occlusion directions (overrides --quality)")
    look.add_argument("--shadow", type=float, help="floor shadow opacity, 0 = no floor (default 1.0)")
    look.add_argument("--ground", help="floor height in metres (default: lowest point of the scene)")
    look.add_argument("--bloom", type=float, help="glow strength for emissive parts (default 1.0, 0 = off)")
    look.add_argument("--spec-occlusion", type=float, help="0..1 strength of reflection occlusion (default 1.0)")
    look.add_argument("--materials", help="extra JSON of material hints merged over render/materials.json")
    look.add_argument("--debug", choices=["ao", "normal", "base", "spec", "diffuse"], help="debug view")
    src = ap.add_argument_group("sources")
    src.add_argument("--glb", choices=["auto", "out", "fresh"], default="auto",
                     help="auto: out/glb when up to date, else build in-process (cache/render/glb); out: only out/glb; fresh: always rebuild")
    src.add_argument("--skip-missing", action="store_true",
                     help="leave out parts whose model does not exist yet (instead of failing)")
    ap.add_argument("--verbose", "-v", action="store_true")
    a = ap.parse_args(argv)

    if not (a.model or a.parts or a.scene or a.sheet):
        ap.error("give --model, --parts, --scene or --sheet")
    def log(*x):
        print(*x, file=sys.stderr)

    scene = {}
    if a.scene:
        with open(a.scene) as f:
            scene = json.load(f)
    # option precedence: CLI > scene "render"/"camera" > defaults
    opts = dict(DEFAULTS)
    for k, v in {**scene.get("render", {}), **scene.get("camera", {})}.items():
        opts[k.replace("-", "_")] = v
    cli = {"size": a.size, "yaw": a.yaw, "pitch": a.pitch, "fov": a.fov, "margin": a.margin,
           "distance_scale": a.distance_scale, "bg": a.bg, "exposure": a.exposure, "tonemap": a.tonemap,
           "quality": "draft" if a.quick else a.quality, "samples": a.samples, "ao_samples": a.ao_samples,
           "shadow": a.shadow, "ground": a.ground, "bloom": a.bloom, "spec_occlusion": a.spec_occlusion,
           "debug": a.debug}
    for k, v in cli.items():
        if v is not None:
            opts[k] = v
    opts["overrides"] = load_overrides(a.materials or scene.get("materials"))

    def with_hints(o: dict, name: str) -> dict:
        """o + the model's camera hints, except where the CLI or the scene set the value."""
        o = dict(o)
        fixed = {k for k, v in cli.items() if v is not None} | set(scene.get("render", {})) | set(scene.get("camera", {}))
        for k, v in model_render_hints(name).items():
            if k in DEFAULTS and k not in fixed:
                o[k] = v
        return o
    if a.sheet and a.size is None and "size" not in scene.get("render", {}):
        opts["size"] = "384"

    t_start = time.time()
    # ------------------------------------------------------------------ contact sheet
    if a.sheet:
        import models
        names = [n for n in models.names() if a.all or model_export_flag(n)]
        if not names:
            log("render: no models to put on the sheet")
            return 1
        jobs, labels, subs = [], [], []
        for n in names:
            g = resolve_glb(n, a.glb, log)
            jobs.append(make_job(with_hints(opts, n), [{"model": n}], [g], n))
            labels.append(n)
        results = run_jobs(jobs, a.verbose)
        for (img, st), n in zip(results, names):
            subs.append(f"{st['tris']:,} tris")
        cols = a.cols or min(4, len(names))
        sheet = grid([r[0] for r in results], labels, cols, "nayzeee speaker / props", subs)
        os.makedirs(os.path.dirname(os.path.abspath(a.sheet)) or ".", exist_ok=True)
        sheet.convert("RGB").save(a.sheet, compress_level=7)
        log(f"render: {a.sheet} ({len(names)} models, {time.time() - t_start:.1f} s)")
        return 0

    # ------------------------------------------------------------------ scene parts
    if a.parts:
        parts = [parse_part(s) for s in a.parts]
    elif a.model:
        parts = [{"model": a.model, "pos": [0, 0, 0], "rot": [0, 0, 0], "scale": 1.0}]
        opts = with_hints(opts, os.path.splitext(os.path.basename(a.model))[0])
    else:
        parts = [{"model": p["model"], "pos": p.get("pos", [0, 0, 0]), "rot": p.get("rot", [0, 0, 0]),
                  "scale": p.get("scale", 1.0), **({"parent": p["parent"]} if "parent" in p else {})}
                 for p in scene.get("parts", [])]
        if not parts:
            ap.error("scene has no parts")
    glbs = []
    keep = []
    for i, p in enumerate(parts):
        try:
            glbs.append(resolve_glb(p["model"], a.glb, log))
            keep.append(i)
        except FileNotFoundError as e:
            if not a.skip_missing:
                raise SystemExit(f"render: {e}  (use --skip-missing to render the parts that exist)")
            log(f"render: skipping {p['model']} (no model yet)")
    if len(keep) != len(parts):
        # world matrices are resolved with the full list so children keep their parent's transform
        mats = resolve_matrices(parts)
        parts = [{"model": parts[i]["model"], "matrix": mats[i]} for i in keep]
        if not parts:
            raise SystemExit("render: none of the parts exist yet")
    stem_name = os.path.splitext(os.path.basename(a.scene))[0] if a.scene else \
        os.path.splitext(os.path.basename(parts[0]["model"]))[0]
    out = a.out or os.path.join(PREVIEW_DIR, f"{stem_name}.png")
    label = " + ".join(os.path.basename(p["model"]) for p in parts)

    if a.turntable:
        n = max(1, a.turntable)
        yaws = [float(opts["yaw"]) + i * 360.0 / n for i in range(n)]
        jobs = []
        for y in yaws:
            o = dict(opts, yaw=y)
            jobs.append(make_job(o, parts, glbs, f"{label} @ {y:.0f}", orbitYaws=yaws))
        results = run_jobs(jobs, a.verbose)
        stem, _ = os.path.splitext(out)
        frames = []
        for i, (img, _) in enumerate(results):
            save_png(img, f"{stem}_{i:03d}.png")
            frames.append(Image.fromarray(img, "RGBA"))
        cols = a.cols or (n if n <= 6 else math.ceil(n / math.ceil(n / 6)))
        g = grid([r[0] for r in results], [f"{y % 360:.0f} deg" for y in yaws], cols)
        g.convert("RGB").save(f"{stem}_grid.png", compress_level=7)
        try:
            frames[0].save(f"{stem}.webp", save_all=True, append_images=frames[1:], duration=1000 // 12,
                           loop=0, lossless=False, quality=92)
            webp = f", {stem}.webp"
        except (OSError, ValueError, KeyError):
            webp = ""
        log(f"render: {stem}_000..{n - 1:03d}.png, {stem}_grid.png{webp} ({time.time() - t_start:.1f} s)")
        return 0

    if a.yaws:
        yaws = [float(y) for y in a.yaws.split(",") if y.strip()]
        jobs = [make_job(dict(opts, yaw=y), parts, glbs, f"{label} @ {y:.0f}", orbitYaws=yaws) for y in yaws]
        results = run_jobs(jobs, a.verbose)
        h, w = results[0][0].shape[:2]
        strip = np.concatenate([r[0] for r in results], axis=1)
        save_png(strip, out)
        log(f"render: {out} ({len(yaws)} angles, {w}x{h} each, {time.time() - t_start:.1f} s)")
        return 0

    (img, st), = run_jobs([make_job(opts, parts, glbs, label)], a.verbose)
    save_png(img, out)
    log(f"render: {out} {img.shape[1]}x{img.shape[0]}, {st['tris']:,} tris, {st['envFrames']}+{st['frames']} frames, "
        f"{st['aoDirections']} AO dirs ({sum(st['ms'].values()) / 1000:.1f} s render, {time.time() - t_start:.1f} s total)")
    return 0


def _cli() -> int:
    try:
        return main()
    except (ValueError, FileNotFoundError, RuntimeError, json.JSONDecodeError) as e:
        print(f"render: error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(_cli())
