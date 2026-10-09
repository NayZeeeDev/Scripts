"""
Remove brand logos from clothing textures.

    python debrand.py spec.json            (needs opencv-python-headless, numpy, pillow)

spec.json:
{
  "ref": "path/to/reference_variant.png",        # masks are built from this colourway
  "inputs": {"a": "a.png", ...},                 # every colourway to clean
  "out": "out_dir",
  "normal": {"in": "normal.png", "out": "normal_clean.png"},   # optional: flatten embossed logos too
  "regions": [
    {"rect": [x0, y0, x1, y1], "rule": "dark|black|light|blue|red|rect", "thr": 0.55, "mirror": 512, "how": "inpaint"},
    {"rect": [...], "key": [x0, y0, x1, y1], "rule": "red", "how": "flatten", "blur": 61},
    {"rect": [...], "rule": "dark", "open": 2, "grain": [x0, y0, x1, y1]}
  ]
}

Coordinates are in a 1024 x 1024 space whatever the texture size. "mirror": N repeats the
region N units to the right (textures that hold both shoes side by side).
"only": "diffuse" | "normal" limits a region to one of the two passes.
"open" drops thin lines (fabric patterns) from a mask, "grain" re-adds fine detail from a
clean patch over the fill, "blur" sets how far a flatten averages.

  inpaint  fills the masked pixels from their surroundings (logos printed on a material)
  flatten  replaces the masked pixels with a smoothed average of same-coloured pixels
           (logos embossed into a coloured tab or stripe)
"""

import json
import sys

import cv2
import numpy as np
from PIL import Image


def load(path):
    return np.array(Image.open(path).convert("RGBA"))


def rule_mask(img, rule, thr):
    rgb = img[..., :3].astype(np.float32)
    luma = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    if rule == "dark":
        return luma < np.median(luma) * (thr or 0.55)
    if rule == "black":
        return luma < (thr or 45)
    if rule == "light":
        return luma > np.median(luma) + 255 * (thr or 0.18)
    if rule == "blue":
        return (b - np.maximum(r, g)) > (thr or 30)
    if rule == "red":
        return (r - np.maximum(g, b)) > (thr or 45)
    return np.ones(luma.shape, bool)


def scaled(rect, w, h, dx=0):
    x0, y0, x1, y1 = rect
    return (int((x0 + dx) / 1024 * w), int(y0 / 1024 * h), int((x1 + dx) / 1024 * w), int(y1 / 1024 * h))


def build_masks(ref, regions):
    """One (fill mask, key mask, how) per region instance, at the reference resolution."""
    h, w = ref.shape[:2]
    out = []
    for reg in regions:
        for dx in [0] + ([reg["mirror"]] if reg.get("mirror") else []):
            x0, y0, x1, y1 = scaled(reg["rect"], w, h, dx)
            m = np.zeros((h, w), np.uint8)
            if reg.get("how") == "flatten" and reg.get("rule") != "rect" and "key" not in reg:
                m[y0:y1, x0:x1] = rule_mask(ref[y0:y1, x0:x1], reg.get("rule"), reg.get("thr")).astype(np.uint8)
            elif reg.get("rule") == "rect" or reg.get("how") == "flatten":
                m[y0:y1, x0:x1] = 1
            else:
                m[y0:y1, x0:x1] = rule_mask(ref[y0:y1, x0:x1], reg.get("rule"), reg.get("thr")).astype(np.uint8)
            if reg.get("open"):
                k = max(1, int(reg["open"] * w / 1024)) * 2 + 1
                m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((k, k), np.uint8))
            if reg.get("minarea"):
                # keep solid shapes (logos), drop what's left of thin pattern lines
                n, labels, stats, _ = cv2.connectedComponentsWithStats(m)
                min_px = reg["minarea"] * (w / 1024) ** 2
                keep = [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= min_px]
                if reg.get("interior"):
                    # drop shapes touching the rect edge (borders, panel edges), keep the logo inside
                    keep = [i for i in keep
                            if stats[i, cv2.CC_STAT_LEFT] > x0 and stats[i, cv2.CC_STAT_TOP] > y0
                            and stats[i, cv2.CC_STAT_LEFT] + stats[i, cv2.CC_STAT_WIDTH] < x1
                            and stats[i, cv2.CC_STAT_TOP] + stats[i, cv2.CC_STAT_HEIGHT] < y1]
                m = np.isin(labels, keep).astype(np.uint8)
                if reg.get("close"):
                    k = max(1, int(reg["close"] * w / 1024)) * 2 + 1
                    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((k, k), np.uint8))
            grow =max(1, int(reg.get("grow", 2) * w / 1024))
            m = cv2.dilate(m, np.ones((grow * 2 + 1, grow * 2 + 1), np.uint8))
            key = None
            if reg.get("how") == "flatten":
                kx0, ky0, kx1, ky1 = scaled(reg.get("key", reg["rect"]), w, h, dx)
                key = np.zeros((h, w), np.uint8)
                key[ky0:ky1, kx0:kx1] = rule_mask(ref[ky0:ky1, kx0:kx1], reg.get("rule", "red"), reg.get("thr")).astype(np.uint8)
                key &= (1 - m) if reg.get("key") else 1
            grain = scaled(reg["grain"], w, h, dx) if reg.get("grain") else None
            out.append((m, key, reg.get("how", "inpaint"), reg.get("radius", 6), reg.get("blur", 21), grain, reg.get("only")))
    return out


def resize_mask(m, w, h):
    return m if m.shape == (h, w) else cv2.resize(m, (w, h), interpolation=cv2.INTER_NEAREST)


def add_grain(rgb, m, grain, w, h):
    """Smooth fills look painted on: tile the fine detail of a clean patch back over them."""
    gx0, gy0, gx1, gy1 = grain
    gx0, gx1 = sorted((gx0, gx1)); gy0, gy1 = sorted((gy0, gy1))
    src = rgb[gy0:gy1, gx0:gx1].astype(np.float32)
    if src.size == 0:
        return rgb
    detail = src - cv2.GaussianBlur(src, (0, 0), max(1.5, w / 1024 * 3))
    reps = (h // detail.shape[0] + 1, w // detail.shape[1] + 1, 1)
    tiled = np.tile(detail, reps)[:h, :w]
    soft = cv2.GaussianBlur(m.astype(np.float32), (0, 0), max(1.0, w / 1024 * 1.5))[..., None]
    return np.clip(rgb.astype(np.float32) + tiled * soft, 0, 255).astype(np.uint8)


def apply(img, masks):
    h, w = img.shape[:2]
    rgb = np.ascontiguousarray(img[..., :3])
    for m, key, how, radius, blur, grain, *_ in masks:
        m = resize_mask(m, w, h)
        if not m.any():
            continue
        if how == "flatten":
            k = resize_mask(key, w, h).astype(np.float32)
            if k.sum() < 10:
                continue
            ks = max(5, int(w / 1024 * blur)) | 1
            num = cv2.GaussianBlur(rgb.astype(np.float32) * k[..., None], (ks, ks), 0)
            den = cv2.GaussianBlur(k, (ks, ks), 0)[..., None]
            avg = np.where(den > 1e-3, num / np.maximum(den, 1e-3), rgb)
            # far from any key pixel: fall back to inpainting
            far = (den[..., 0] < 0.02) & (m > 0)
            rgb = np.where(m[..., None] > 0, avg, rgb).astype(np.uint8)
            if far.any():
                rgb = cv2.inpaint(rgb, far.astype(np.uint8), radius, cv2.INPAINT_TELEA)
        else:
            rgb = cv2.inpaint(rgb, m, max(3, int(radius * w / 2048)), cv2.INPAINT_TELEA)
        if grain:
            rgb = add_grain(rgb, m, grain, w, h)
    out = img.copy()
    out[..., :3] = rgb
    return out


def main():
    spec = json.load(open(sys.argv[1]))
    ref = load(spec["ref"])
    masks = build_masks(ref, spec["regions"])
    import os
    os.makedirs(spec["out"], exist_ok=True)
    diffuse_masks = [mk for mk in masks if mk[6] != "normal"]
    for name, path in spec["inputs"].items():
        Image.fromarray(apply(load(path), diffuse_masks)).save(os.path.join(spec["out"], name + ".png"))
    if spec.get("normal"):
        n = load(spec["normal"]["in"])
        # embossing spreads a little past the printed logo: widen the masks for the normal map
        extra = max(1, int(spec["normal"].get("grow", 3) * ref.shape[1] / 1024))
        kernel = np.ones((extra * 2 + 1, extra * 2 + 1), np.uint8)
        nmasks = [(cv2.dilate(m, kernel) if how == "inpaint" else m, k, how, r, b, None, only)
                  for m, k, how, r, b, _, only in masks if only != "diffuse"]
        Image.fromarray(apply(n, nmasks)).save(spec["normal"]["out"])
    print("cleaned", len(spec["inputs"]), "textures,", len(masks), "regions")


if __name__ == "__main__":
    main()
