#!/usr/bin/env python3
"""Product renders of the legacy props wearing looks from nayzeee-speaker/html/looks.

    python3 tools/legacy_preview.py defaults --out DIR            # every prop in its default look (+ sheet.png)
    python3 tools/legacy_preview.py options --out SHEET.png        # every variant of every texture on its prop
    python3 tools/legacy_preview.py inventory                      # install/images/nayzeee_audio_[a-h].png
    python3 tools/legacy_preview.py one nayzeee_audio_c sp3=honeycomb --out x.png

The props are read with legacy_reader.py; replaced textures come from html/looks/<tex>/<variant>.png.
The shared light strip 'emissive4' (props e and f) is shown as the RGB strip the game draws at runtime
(rainbow, two cycles across the strip, like html/looks/rgb.html).  Lights that are embedded in a prop's
own .ydr keep their original texture, because the shared texture dictionary cannot replace them.
All renders go through render.py (one headless Chromium session per command).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import legacy_reader as LR  # noqa: E402
import render as R  # noqa: E402
from lib import fonts  # noqa: E402

LOOKS = os.path.normpath(os.path.join(ROOT, "..", "nayzeee-speaker", "html", "looks"))
IMAGES = os.path.normpath(os.path.join(ROOT, "..", "nayzeee-speaker", "install", "images"))
CACHE = os.path.join(ROOT, "cache", "legacy")

# product camera per prop: the props face -Y, so yaw ~180 looks at their front
CAMERA = {
    "nayzeee_audio_a": {"yaw": 215, "pitch": 18},
    "nayzeee_audio_b": {"yaw": 215, "pitch": 20},
    "nayzeee_audio_c": {"yaw": 215, "pitch": 30},
    "nayzeee_audio_d": {"yaw": 215, "pitch": 20},
    "nayzeee_audio_e": {"yaw": 215, "pitch": 20},
    "nayzeee_audio_f": {"yaw": 215, "pitch": 20},
    "nayzeee_audio_g": {"yaw": 215, "pitch": 30},
    "nayzeee_audio_h": {"yaw": 205, "pitch": 16},
}


def rgb_strip(w: int = 256, h: int = 32, cycles: int = 2, phase: float = 0.0) -> np.ndarray:
    """The animated strip at one moment: smoothed HSV rainbow across the width (as rgb.html draws it)."""
    x = (np.arange(w) + 0.5) / w
    hh = ((x * cycles + phase) % 1.0) * 6

    def sm(k):
        return k * k * (3 - 2 * k)
    r = sm(np.clip(np.abs(hh - 3) - 1, 0, 1))
    g = sm(np.clip(2 - np.abs(hh - 2), 0, 1))
    b = sm(np.clip(2 - np.abs(hh - 4), 0, 1))
    row = np.stack([r, g, b], axis=1) * 255
    img = np.repeat(row[None], h, axis=0)
    return np.dstack([img, np.full((h, w), 255.0)]).astype(np.uint8)


class Props:
    def __init__(self, looks_dir: str = LOOKS):
        self.looks_dir = looks_dir
        ytd = LR.read_ytd(os.path.join(LR.STREAM, LR.YTD))
        self.textures = {k: t["rgba"] for k, t in ytd.items() if t["rgba"] is not None}
        self.ydr = {}
        lib_path = os.path.join(looks_dir, "library.json")
        self.library = json.load(open(lib_path, encoding="utf-8"))["textures"] if os.path.exists(lib_path) else {}
        os.makedirs(CACHE, exist_ok=True)

    def drawable(self, model: str) -> dict:
        if model not in self.ydr:
            self.ydr[model] = LR.read_ydr(os.path.join(LR.STREAM, model + ".ydr"))
        return self.ydr[model]

    def default_look(self, model: str) -> dict:
        return {t: e["default"] for t, e in self.library.items() if model in e.get("usedBy", [])}

    def glb(self, model: str, look: dict, rgb_phase: float = 0.0, emissive_boost: float = 1.6) -> str:
        replace = {}
        for tex, variant in look.items():
            if variant and variant != "original":
                p = os.path.join(self.looks_dir, tex, variant + ".png")
                replace[tex] = np.asarray(Image.open(p).convert("RGBA"))
        replace["emissive4"] = rgb_strip(phase=rgb_phase)
        key = hashlib.sha1(json.dumps([model, sorted(look.items()), rgb_phase, emissive_boost]).encode()
                           + b"".join(np.ascontiguousarray(v).tobytes()[:4096] + str(v.shape).encode()
                                      for _, v in sorted(replace.items()))).hexdigest()[:16]
        path = os.path.join(CACHE, f"{model}.{key}.glb")
        data = LR.build_glb(self.drawable(model), model, self.textures, replace, emissive_boost=emissive_boost)
        with open(path, "wb") as f:
            f.write(data)
        return path


def job(glb: str, model: str, label: str, size="384", quality="draft", exposure=1.0, **cam) -> dict:
    opts = dict(R.DEFAULTS)
    opts.update({"size": size, "quality": quality, "exposure": exposure, "overrides": R.load_overrides(None)})
    c = dict(CAMERA.get(model, {}))
    c.update(cam)
    for k in ("yaw", "pitch", "fov", "margin", "shadow", "bloom"):
        if k in c:
            opts[k] = c[k]
    parts = [{"model": model, "matrix": np.eye(4)}]
    return R.make_job(opts, parts, [glb], label)


def render(jobs: list) -> list:
    return [a for a, _ in R.run_jobs(jobs)]


def sheet(cells, cols: int, path: str, cell: int = 300, title: str | None = None, row_labels=None):
    rows = (len(cells) + cols - 1) // cols
    top = 40 if title else 0
    left = 120 if row_labels else 0
    im = Image.new("RGB", (left + cols * cell, top + rows * (cell + 22)), (34, 36, 38))
    d = ImageDraw.Draw(im)
    f = fonts.pil_font(14, 500)
    if title:
        d.text((12, 11), title, font=fonts.pil_font(18, 600), fill=(240, 240, 240))
    for i, (label, arr) in enumerate(cells):
        if arr is None:
            continue
        a = Image.fromarray(arr).convert("RGBA")
        a.thumbnail((cell, cell), Image.LANCZOS)
        x, y = left + (i % cols) * cell, top + (i // cols) * (cell + 22)
        bg = Image.new("RGBA", (cell, cell), (58, 60, 63, 255))
        bg.alpha_composite(a, ((cell - a.size[0]) // 2, (cell - a.size[1]) // 2))
        im.paste(bg.convert("RGB"), (x, y))
        d.text((x + 6, y + cell + 3), label, font=f, fill=(225, 225, 225))
    if row_labels:
        for r, lab in enumerate(row_labels):
            d.text((10, top + r * (cell + 22) + cell // 2 - 8), lab, font=fonts.pil_font(15, 600), fill=(15, 212, 196))
    im.save(path)


# --------------------------------------------------------------------------- commands
def cmd_defaults(a, P: Props):
    os.makedirs(a.out, exist_ok=True)
    jobs, names = [], []
    for m in LR.MODELS:
        jobs.append(job(P.glb(m, P.default_look(m)), m, m, size=a.size, quality=a.quality, exposure=a.exposure))
        names.append(m)
    imgs = render(jobs)
    cells = []
    for m, img in zip(names, imgs):
        R.save_png(img, os.path.join(a.out, m + ".png"))
        look = P.default_look(m)
        shown = {k: v for k, v in look.items() if k != "brands"} or look
        cells.append((f"{m[-1]}: " + ", ".join(f"{k}={v}" for k, v in sorted(shown.items())), img))
    sheet(cells, 4, os.path.join(a.out, "sheet.png"), cell=360, title="Default looks (RGB strip lit)")
    print("wrote", a.out)


def cmd_options(a, P: Props):
    # show each texture on the prop that wears the most of it
    show = {"sp1": "nayzeee_audio_a", "sp2": "nayzeee_audio_b", "sp3": "nayzeee_audio_c", "sp4": "nayzeee_audio_d",
            "sp5": "nayzeee_audio_f", "repro": "nayzeee_audio_f", "brands": "nayzeee_audio_c",
            "record": "nayzeee_audio_g"}
    cam_override = {"repro": {"yaw": 268, "pitch": 12}, "brands": {"yaw": 180, "pitch": 55},
                    "record": {"yaw": 195, "pitch": 55}}
    texs = [t for t in show if t in P.library and (not a.only or t in a.only)]
    jobs, cells, row_labels = [], [], []
    cols = max(len(P.library[t]["variants"]) for t in texs)
    for t in texs:
        m = show[t]
        row_labels.append(f"{t}\n{m[-1]}")
        base = P.default_look(m)
        for v in P.library[t]["variants"]:
            look = dict(base)
            look[t] = v
            jobs.append(job(P.glb(m, look), m, f"{t}/{v}", size=a.size, quality=a.quality, exposure=a.exposure,
                            **cam_override.get(t, {})))
            cells.append(v + (" *" if v == P.library[t]["default"] else ""))
        cells.extend([None] * (cols - len(P.library[t]["variants"])))
    imgs = iter(render(jobs))
    out_cells = [(c, next(imgs)) if c is not None else ("", None) for c in cells]
    sheet(out_cells, cols, a.out, cell=a.cell, title="Looks library: every variant on its prop (* = default)",
          row_labels=[r.replace("\n", " ") for r in row_labels])
    print("wrote", a.out)


def cmd_inventory(a, P: Props):
    """512 px item images: transparent, one 3/4 camera, the prop ~80% of the frame, soft contact shadow,
    default look with the RGB strip lit.  Rendered at 2x and downsampled for clean edges."""
    os.makedirs(a.out, exist_ok=True)
    models = a.models or LR.MODELS
    jobs = []
    for m in models:
        cam = dict(CAMERA[m])
        cam.update({"margin": a.margin, "shadow": 0.75})
        jobs.append(job(P.glb(m, P.default_look(m), emissive_boost=a.emissive), m, m, size=str(a.render_size),
                        quality=a.quality, exposure=a.exposure, **cam))
    imgs = render(jobs)
    for m, img in zip(models, imgs):
        im = Image.fromarray(img, "RGBA").resize((512, 512), Image.LANCZOS)
        path = os.path.join(a.out, m + ".png")
        im.save(path, optimize=True)
        print("wrote", path, os.path.getsize(path) // 1024, "KB")


def cmd_one(a, P: Props):
    look = P.default_look(a.model)
    for kv in a.look:
        k, v = kv.split("=", 1)
        look[k] = v
    img = render([job(P.glb(a.model, look), a.model, a.model, size=a.size, quality=a.quality, exposure=a.exposure,
                      **({"yaw": a.yaw} if a.yaw is not None else {}),
                      **({"pitch": a.pitch} if a.pitch is not None else {}))])[0]
    R.save_png(img, a.out)
    print("wrote", a.out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--looks", default=LOOKS, help="looks folder (default: the resource's html/looks)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("defaults", "options", "inventory", "one"):
        sp = sub.add_parser(name)
        sp.add_argument("--size", default="384")
        sp.add_argument("--quality", default="draft", choices=["draft", "normal", "high"])
        sp.add_argument("--exposure", type=float, default=1.0)
        if name == "one":
            sp.add_argument("model")
            sp.add_argument("look", nargs="*", metavar="TEX=VARIANT")
            sp.add_argument("--yaw", type=float)
            sp.add_argument("--pitch", type=float)
            sp.add_argument("--out", required=True)
        elif name == "options":
            sp.add_argument("--out", required=True)
            sp.add_argument("--cell", type=int, default=220)
            sp.add_argument("--only", nargs="*")
        elif name == "inventory":
            sp.add_argument("--out", default=IMAGES)
            sp.add_argument("--models", nargs="*")
            sp.add_argument("--render-size", type=int, default=1024)
            sp.add_argument("--emissive", type=float, default=1.0)
            sp.add_argument("--margin", type=float, default=0.10)
        else:
            sp.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    P = Props(a.looks)
    {"defaults": cmd_defaults, "options": cmd_options, "inventory": cmd_inventory, "one": cmd_one}[a.cmd](a, P)
    return 0


if __name__ == "__main__":
    sys.exit(main())
