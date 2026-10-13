#!/usr/bin/env python3
"""
Nayzeee minimap recolour tool.

Turns GTA's exported radar map textures into a clean custom style (dark, midnight teal, light ...).
You export the textures with OpenIV / CodeWalker, run this on the folder, then import the results back
and stream the .ytd files from nayzeee-hud/stream/ (see README.md next to this file).

    pip install pillow
    python recolor.py <input folder> <output folder> --style dark
    python recolor.py in out --style teal --preview          # also writes _preview.png (a contact sheet)
    python recolor.py in out --style custom --bg "#0b0d0f" --block "#1a1e22" --road "#8a939a" --highway "#e6e9eb" --water "#0d2a33"

Works on .png, .dds, .tga, .jpg, .bmp. Output is always .png (OpenIV and CodeWalker turn PNG back into DDS on import).
"""
import argparse
import os
import sys

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit('Pillow is missing: run  pip install pillow')

# bg = empty land, block = buildings / blocks, road = normal roads, highway = the brightest roads, water = sea / lakes
STYLES = {
    'dark':     {'bg': '#0c0e10', 'block': '#1b1f23', 'road': '#7d868d', 'highway': '#e9ecee', 'water': '#10151b'},
    'teal':     {'bg': '#071312', 'block': '#0f2423', 'road': '#3f8f88', 'highway': '#bdf5ef', 'water': '#05211f'},
    'midnight': {'bg': '#0a0d16', 'block': '#151a29', 'road': '#5a6a8c', 'highway': '#dfe6ff', 'water': '#0a1730'},
    'light':    {'bg': '#e9ebee', 'block': '#d6d9de', 'road': '#ffffff', 'highway': '#ffffff', 'water': '#b9cfe0'},
    'mono':     {'bg': '#141414', 'block': '#232323', 'road': '#8c8c8c', 'highway': '#f2f2f2', 'water': '#191919'},
}


def hex_rgb(h):
    h = h.lstrip('#')
    if len(h) != 6:
        raise ValueError(f'not a #rrggbb colour: {h}')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def build_lut(p, contrast):
    """Brightness (0-255) -> colour: dark parts become land, mid becomes blocks, bright becomes roads / highways."""
    land = max(20, min(110, int(70 * contrast)))
    stops = [(0, p['bg']), (land, p['bg']), (120, p['block']), (175, p['road']), (235, p['highway']), (255, p['highway'])]
    lut = []
    for v in range(256):
        for i in range(len(stops) - 1):
            a, b = stops[i], stops[i + 1]
            if a[0] <= v <= b[0]:
                t = 0 if b[0] == a[0] else (v - a[0]) / (b[0] - a[0])
                lut.append(lerp(a[1], b[1], t))
                break
        else:
            lut.append(stops[-1][1])
    return lut


def recolor(img, p, lut, water_sens):
    # whole-image Pillow ops (no per-pixel Python loop) so 4k radar tiles take seconds, not minutes
    img = img.convert('RGBA')
    r, g, b, a = img.split()
    lum = img.convert('L')
    out = Image.merge('RGB', [lum.point([c[i] for c in lut]) for i in range(3)])
    # GTA draws water in blue: blue clearly above red and green
    over_r = ImageChops.subtract(b, r).point(lambda v: 255 if v > water_sens else 0)
    over_g = ImageChops.subtract(b, g).point(lambda v: 255 if v > water_sens * 0.4 else 0)
    out.paste(p['water'], (0, 0, *img.size), ImageChops.multiply(over_r, over_g))
    out.putalpha(a)
    return out


def contact_sheet(paths, out, size=180):
    imgs = [Image.open(p).convert('RGBA') for p in paths[:24]]
    if not imgs:
        return
    cols = min(6, len(imgs))
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * size, rows * size), (20, 22, 24, 255))
    for i, im in enumerate(imgs):
        im.thumbnail((size, size))
        sheet.paste(im, ((i % cols) * size, (i // cols) * size), im)
    sheet.save(out)


def main():
    ap = argparse.ArgumentParser(description='Recolour exported GTA radar textures into a custom minimap style.')
    ap.add_argument('input', help='folder with the exported textures')
    ap.add_argument('output', help='folder to write the recoloured PNGs to')
    ap.add_argument('--style', default='dark', choices=list(STYLES) + ['custom'])
    for k in ('bg', 'block', 'road', 'highway', 'water'):
        ap.add_argument('--' + k, help=f'#rrggbb for {k} (overrides the style)')
    ap.add_argument('--water-sens', type=int, default=18, help='how blue a pixel must be to count as water (lower = more water)')
    ap.add_argument('--contrast', type=float, default=1.0, help='raise (e.g. 1.2) to turn more of the map into empty land')
    ap.add_argument('--preview', action='store_true', help='also write _preview.png, a contact sheet of the results')
    a = ap.parse_args()

    base = dict(STYLES.get(a.style, STYLES['dark']))
    for k in ('bg', 'block', 'road', 'highway', 'water'):
        if getattr(a, k):
            base[k] = getattr(a, k)
    pal = {k: hex_rgb(v) for k, v in base.items()}
    lut = build_lut(pal, a.contrast)

    exts = ('.png', '.dds', '.tga', '.jpg', '.jpeg', '.bmp')
    files = sorted(f for f in os.listdir(a.input) if f.lower().endswith(exts))
    if not files:
        sys.exit(f'No images in {a.input} (looked for {", ".join(exts)})')
    os.makedirs(a.output, exist_ok=True)
    done = []
    for f in files:
        try:
            im = Image.open(os.path.join(a.input, f))
        except Exception as e:  # some DDS formats Pillow can't read: export those as PNG instead
            print(f'skip {f}: {e}')
            continue
        out = os.path.join(a.output, os.path.splitext(f)[0] + '.png')
        recolor(im, pal, lut, a.water_sens).save(out)
        done.append(out)
        print(f'ok   {f}')
    if a.preview and done:
        contact_sheet(done, os.path.join(a.output, '_preview.png'))
        print('preview written: _preview.png')
    print(f'{len(done)} texture(s) recoloured with the "{a.style}" style.')


if __name__ == '__main__':
    main()
