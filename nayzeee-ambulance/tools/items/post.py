#!/usr/bin/env python3
"""Turn the raw 1024x1024 premultiplied RGBA frames from render.mjs into the shipped PNGs.

    python3 tools/items/post.py --raw /tmp/nza-work/items/raw [--repo .] [--sets items,tools]
                                [--only a,b] [--sheets <dir>]

* downsample in premultiplied space (Lanczos), then un-premultiply -> clean edges, no dark fringes
* items -> html/img/items/<name>.png (512), tools -> html/img/tools/<name>.png (256)
* tools/index.json lists every tool picture, contact sheets go to --sheets
"""
import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SRC = 1024
OUT = {"items": ("html/img/items", 512), "tools": ("html/img/tools", 256)}
HERE = os.path.dirname(os.path.abspath(__file__))


def load_raw(path):
    a = np.frombuffer(open(path, "rb").read(), dtype=np.uint8)
    return a.reshape(SRC, SRC, 4).astype(np.float32) / 255.0


def downsample(prem, size):
    # prem: premultiplied float RGBA. Resize each channel with Lanczos (float mode), clamp, then
    # un-premultiply so semi-transparent edges keep their true colour.
    chans = []
    for c in range(4):
        im = Image.fromarray(prem[:, :, c], mode="F").resize((size, size), Image.LANCZOS)
        chans.append(np.asarray(im))
    out = np.clip(np.stack(chans, axis=-1), 0.0, 1.0)
    a = out[:, :, 3:4]
    rgb = np.where(a > 1e-4, out[:, :, :3] / np.maximum(a, 1e-4), 0.0)
    rgb = np.clip(rgb, 0.0, 1.0)
    a8 = np.round(a[:, :, 0] * 255.0)
    a8[a8 < 2] = 0                      # drop the faint ringing halo
    rgb8 = np.round(rgb * 255.0)
    rgb8[a8 == 0] = 0                    # fully transparent pixels: black (compresses better)
    return Image.fromarray(np.dstack([rgb8, a8]).astype(np.uint8), "RGBA")


def save_png(img, path):
    img.save(path, optimize=True, compress_level=9)
    return os.path.getsize(path)


def font(size):
    for f in ("/usr/share/fonts/opentype/inter/Inter-Medium.otf", os.path.join(HERE, "..", "props", "fonts", "DejaVuSans.ttf")):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def sheet(files, out_path, cell=192, cols=8, bg=(32, 36, 42), small=False):
    if not files:
        return
    rows = (len(files) + cols - 1) // cols
    lab = 22
    W, H = cols * cell, rows * (cell + lab)
    im = Image.new("RGBA", (W, H), bg + (255,))
    dr = ImageDraw.Draw(im)
    fnt = font(13)
    for i, f in enumerate(files):
        x, y = (i % cols) * cell, (i // cols) * (cell + lab)
        # alternate cell shade so the transparent edges are visible
        dr.rectangle([x, y, x + cell - 1, y + cell + lab - 1], fill=(bg[0] + 6, bg[1] + 6, bg[2] + 8, 255) if (i // cols + i) % 2 else bg + (255,))
        p = Image.open(f).convert("RGBA").resize((cell - 12, cell - 12), Image.LANCZOS)
        im.alpha_composite(p, (x + 6, y + 6))
        if small:   # 64 px preview in the corner (inventory slot size)
            s = Image.open(f).convert("RGBA").resize((64, 64), Image.LANCZOS)
            dr.rectangle([x + cell - 70, y + 4, x + cell - 4, y + 70], fill=(22, 25, 30, 255))
            im.alpha_composite(s, (x + cell - 69, y + 5))
        name = os.path.splitext(os.path.basename(f))[0]
        dr.text((x + cell / 2, y + cell + 3), name, fill=(220, 226, 232, 255), font=fnt, anchor="ma")
    im.convert("RGB").save(out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="/tmp/nza-work/items/raw")
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(HERE, "..", "..")))
    ap.add_argument("--sets", default="items,tools")
    ap.add_argument("--only", default=None)
    ap.add_argument("--sheets", default=os.environ.get("NZA_SHEETS", "/tmp/nza-work/items/sheets"))
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    os.makedirs(a.sheets, exist_ok=True)
    for s in a.sets.split(","):
        sub, size = OUT[s]
        out_dir = os.path.join(a.repo, sub)
        os.makedirs(out_dir, exist_ok=True)
        raw_dir = os.path.join(a.raw, s)
        if not os.path.isdir(raw_dir):
            continue
        total = 0
        for fn in sorted(os.listdir(raw_dir)):
            if not fn.endswith(".rgba"):
                continue
            name = fn[:-5]
            if only and name not in only:
                continue
            img = downsample(load_raw(os.path.join(raw_dir, fn)), size)
            n = save_png(img, os.path.join(out_dir, name + ".png"))
            total += n
            print(f"  {sub}/{name}.png {n // 1024} KB")
        files = sorted(os.path.join(out_dir, f) for f in os.listdir(out_dir) if f.endswith(".png"))
        if s == "tools":
            idx = {os.path.splitext(os.path.basename(f))[0]: f"img/tools/{os.path.basename(f)}" for f in files}
            with open(os.path.join(out_dir, "index.json"), "w") as fh:
                json.dump(idx, fh, indent=2, sort_keys=True)
                fh.write("\n")
        sheet(files, os.path.join(a.sheets, f"contact_{s}.png"), cell=192 if s == "items" else 160, cols=8 if s == "items" else 9, small=True)
        print(f"{s}: wrote {total // 1024} KB this run, sheet -> {os.path.join(a.sheets, f'contact_{s}.png')}")


if __name__ == "__main__":
    main()
