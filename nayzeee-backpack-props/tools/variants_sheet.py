#!/usr/bin/env python3
"""Front view of a converted bag in every colour: variants_sheet.py <model> <conv dir> <out.png>"""
import glob, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, sys.argv[0].rsplit('/', 1)[0])
import render_bag as rb

M, W, out = sys.argv[1:4]
rb.W = rb.H = 220
tris = rb.load(f'{W}/out_{M}/{M}.ydr.xml')
ts = sorted(glob.glob(f'{W}/out_{M}/t*/'), key=lambda p: int(p.rstrip('/').split('/t')[-1]))
tiles = []
for i, t in enumerate(ts):
    dds = glob.glob(t + '*/' + M + '_d.dds')[0]
    tex = np.array(Image.open(dds).convert('RGBA').resize((512, 512)))
    im = rb.render(tris, tex, 160, 8)
    ImageDraw.Draw(im).text((6, 6), str(i + 1), fill=(255, 255, 255))
    tiles.append(im)
cols = 6
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new('RGB', (cols * 220, rows * 220), (14, 16, 17))
for i, im in enumerate(tiles):
    sheet.paste(im, ((i % cols) * 220, (i // cols) * 220))
sheet.save(out)
