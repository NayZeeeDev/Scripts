import sys, numpy as np
from PIL import Image
sys.path.insert(0, sys.path[0])
from dxt import read_dxt5

COLOURS = {
    'black':  (30, 30, 33),
    'white':  (236, 234, 229),
    'red':    (196, 28, 36),
    'blue':   (32, 84, 200),
    'green':  (34, 136, 70),
    'pink':   (236, 118, 166),
    'purple': (118, 58, 176),
    'teal':   (8, 160, 148),
}
DARK = np.array([34, 34, 38], np.float32)
WHITE = np.array([255, 255, 255], np.float32)

def recolor(img, target):
    f = img.astype(np.float32)
    h, w, _ = f.shape
    yy, xx = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    card = (xx >= 0.745) & (yy >= 0.63)
    # the orange: mean of strongly orange pixels
    orange_mask = (f[..., 0] > 180) & (f[..., 2] < 90) & ~card
    O = f[orange_mask].mean(0)
    # how much orange each pixel is, unmixing orange from white (blue channel), only where red is high
    a = np.clip((255 - f[..., 2]) / (255 - O[2]), 0, 1)
    a[(f[..., 0] < 170) | card] = 0
    # grain: brightness of the orange relative to its average
    lum = f.mean(2)
    grain = np.clip(lum / O.mean(), 0.7, 1.3)[..., None]
    # the white sticker: near-white rows/cols in the lower left
    white = (f.min(2) > 225) & (yy > 0.64) & (xx < 0.72)
    ys, xs = np.nonzero(white)
    label = np.zeros_like(card)
    if len(ys):
        label[ys.min():ys.max() + 1, xs.min():xs.max() + 1] = True
    t = np.array(target, np.float32)
    light = t.mean() > 200
    detail = DARK if light else WHITE
    out = f.copy()
    # the orange seam along the cardboard's edge belongs to the box
    seam = card & (f[..., 0] > 180) & (f[..., 2] < 90) & (f[..., 1] < 140)
    out[seam] = t
    body = ~card & ~label & (f[..., 0] >= 170)          # orange + white printing on the box
    col = t * np.where(a[..., None] > 0.9, grain, 1.0)
    mixed = a[..., None] * col + (1 - a[..., None]) * detail
    out[body] = mixed[body]
    # on the sticker only the orange text changes (dark text on a light box colour)
    text = t if not light else DARK
    lab = label & (a > 0.02)
    out[lab] = (a[..., None] * text + (1 - a[..., None]) * WHITE)[lab]
    return np.clip(out, 0, 255).astype(np.uint8)

if __name__ == '__main__':
    src, out_dir = sys.argv[1], sys.argv[2]
    img = read_dxt5(src)
    import os
    os.makedirs(out_dir, exist_ok=True)
    for name, c in COLOURS.items():
        Image.fromarray(recolor(img, c)).save(os.path.join(out_dir, name + '.png'))
