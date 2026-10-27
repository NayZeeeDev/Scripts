#!/usr/bin/env python3
"""
Item icons: renders 512 x 512 transparent PNGs of the props from their .glb previews into
nayzeee-radio/html/img/items/<item>.png (the item names come from config/items.lua: Config.Items).

    python3 tools/props/icons.py                       # every item whose model has been built
    python3 tools/props/icons.py --only handheld,heavy  # Config.Items keys
    python3 tools/props/icons.py --out /tmp/nzr-work/props/out --dest html/img/items --size 512

Each icon is rendered at twice the size (3/4 front, slightly from above, framed tightly, no floor) and
downsampled for clean edges. Writes nzr_unknown.png (the fallback image for unknown items) only when the
folder has none - the NUI ships its own styled one.
Models without a .glb are skipped with a note - build them first (build.py --no-convert).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

from nzprops.fsutil import save_image  # noqa: E402
from nzprops.paint import font  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
DEFAULT_WORK = "/tmp/nzr-work/props"
DEFAULT_DEST = os.path.join(REPO, "html", "img", "items")
ITEMS_LUA = os.path.join(REPO, "config", "items.lua")
# Config.Items key -> model
MODELS = {
    "handheld": "nzr_handheld", "fieldpro": "nzr_fieldpro", "military": "nzr_military", "earpiece": "nzr_earpiece",
    "pocket": "nzr_jammer_pocket", "case": "nzr_jammer_case", "heavy": "nzr_jammer_heavy",
}
# per-model camera direction (view name of preview/index.html) - radios stand, jammers sit on the ground
VIEWS = {"nzr_jammer_pocket": "iso", "nzr_jammer_case": "front", "nzr_jammer_heavy": "front"}


def item_names(path=ITEMS_LUA):
    """Config.Items { key = 'item' } from config/items.lua."""
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"Config\.Items\s*=\s*\{(.*?)\n\}", txt, re.S)
    if not m:
        raise SystemExit(f"Config.Items not found in {path}")
    out = {}
    for k, v in re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*'([^']+)'", m.group(1), re.M):
        out[k] = v
    return out


def unknown_icon(size=512):
    """Neutral fallback icon: a dark rounded tile with a question mark (NUI image, not a prop)."""
    S = size * 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S * 0.14, S * 0.14, S * 0.86, S * 0.86], radius=S * 0.12, fill=(24, 27, 31, 235),
                        outline=(70, 78, 86, 255), width=max(2, S // 128))
    d.text((S / 2, S * 0.5), "?", font=font("label", S * 0.42), fill=(150, 160, 168, 255), anchor="mm")
    return img.resize((size, size), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(DEFAULT_WORK, "out"), help="build folder with <model>/<model>.glb")
    ap.add_argument("--work", default=DEFAULT_WORK, help="tool cache (node modules)")
    ap.add_argument("--dest", default=DEFAULT_DEST)
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--only", default=None, help="comma separated Config.Items keys")
    ap.add_argument("--chromium", default=None)
    ap.add_argument("--map", action="append", default=[], help="extra item=model pairs (e.g. test_radio=nzr_example)")
    ap.add_argument("--no-unknown", action="store_true", help="never write nzr_unknown.png (default: only when missing)")
    args = ap.parse_args()

    import build  # tools/props/build.py (renderer helpers)
    items = item_names()
    models = dict(MODELS)
    for pair in args.map:
        item, model = pair.split("=", 1)
        items[f"map:{item}"] = item
        models[f"map:{item}"] = model
    keys = [k for k in items if k in models]
    if args.only:
        want = {k.strip() for k in args.only.split(",") if k.strip()}
        keys = [k for k in keys if k in want or k.startswith("map:")]
    entries, plan = [], []
    for k in keys:
        model = models[k]
        glb = os.path.join(args.out, model, model + ".glb")
        if not os.path.exists(glb):
            print(f"[icons] skip {items[k]}.png: {model} has not been built in {args.out}")
            continue
        entries.append({"name": f"icon_{model}", "glb": glb, "views": [VIEWS.get(model, "icon")], "cams": [], "transparent": True,
                        "fit": 0.86, "exposure": 1.35, "fill": 1.4})
        plan.append((k, model))
    os.makedirs(args.dest, exist_ok=True)
    if not args.no_unknown and not os.path.exists(os.path.join(args.dest, "nzr_unknown.png")):
        save_image(unknown_icon(args.size), os.path.join(args.dest, "nzr_unknown.png"))
    if not entries:
        print("[icons] nothing to render")
        return
    nm = build.ensure_preview_modules(args.work)
    tmp = tempfile.mkdtemp(prefix="nzr-icons-")
    try:
        lpath = os.path.join(tmp, "list.json")
        with open(lpath, "w") as f:
            json.dump(entries, f)
        cmd = ["node", os.path.join(HERE, "preview", "render.mjs"), "--list", lpath, "--out", tmp, "--modules", nm,
               "--size", str(args.size * 2)]
        if args.chromium:
            cmd += ["--chromium", args.chromium]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:])
            raise SystemExit("icon rendering failed")
        for (k, model), e in zip(plan, entries):
            src = os.path.join(tmp, f"{e['name']}_{e['views'][0]}.png")
            img = Image.open(src).convert("RGBA").resize((args.size, args.size), Image.LANCZOS)
            # soft contact shadow under the object so it reads on light inventory backgrounds
            a = img.split()[3]
            sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
            sh.putalpha(a.point(lambda v: int(v * 0.35)).filter(ImageFilter.GaussianBlur(args.size / 64)))
            out = Image.alpha_composite(sh.transform(img.size, Image.AFFINE, (1, 0, -args.size * 0.01, 0, 1, -args.size * 0.015)), img)
            dst = os.path.join(args.dest, f"{items[k]}.png")
            save_image(out, dst)
            print(f"[icons] {dst}  ({model})")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
