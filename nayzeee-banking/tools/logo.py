"""The bank's logo (Fleeca Bank), in the same badge style as the Sneaker Co. boxes: a white disc with the
monogram in the brand colour, the name in bold capitals, a small line of print under it.

    pip install pillow
    python3 logo.py                     # writes the three files below
    python3 logo.py --press out/ 4      # the same at 4x, transparent, for thumbnails and print
                                        # (adds a dark-ink logo for light backgrounds)

    ../web/images/mark.png      the badge on its own: the title bar, the ATM screen
    ../web/images/logo.png      badge + name + tagline: intro, PIN pad, ATM boot
    ../web/phone/icon.png       the phone app icon: the badge and name on a brand tile

Change the name, the monogram or the colours below and run it again.
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, 'Lexend.woff2')

MONOGRAM = 'F'
NAME     = 'FLEECA'
NAME_2   = 'BANK'               # printed in the brand colour after the name
TAGLINE  = 'SECURE BANKING'

BRAND    = (8, 175, 162)        # Config.UI.accent
BRAND_HI = (15, 212, 196)       # Config.UI.accentLight
BRAND_LO = (4, 107, 99)         # gradient base
WHITE    = (255, 255, 255)
INK      = (11, 12, 13)

SS = 4                          # supersampling, for clean edges


def font(size, weight):
    try:
        f = ImageFont.truetype(FONT, size)
        f.set_variation_by_axes([weight])
        return f
    except Exception:
        return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)


def spaced(draw, xy, text, f, fill, tracking, anchor='lm'):
    """Text with letter spacing (PIL has none), anchored on its full width."""
    widths = [draw.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor[0] == 'm':
        x -= total / 2
    elif anchor[0] == 'r':
        x -= total
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=f, fill=fill, anchor='l' + anchor[1])
        x += w + tracking
    return total


def gradient(size, top, bottom):
    w, h = size
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))


def badge(d, ss=SS):
    """The disc: white, a hairline ring inside, the monogram in the brand colour.
    `ss`: supersampling inside the badge; 1 when the caller's canvas is already supersampled."""
    s = d * ss
    img = Image.new('RGBA', (s, s), 0)
    dr = ImageDraw.Draw(img)
    dr.ellipse((0, 0, s - 1, s - 1), fill=WHITE + (255,))
    # the ring is the brand colour washed into the white, drawn solid so nothing shows through
    ring = tuple(int(255 + (c - 255) * 0.35) for c in BRAND) + (255,)
    inset = int(s * 0.07)
    dr.ellipse((inset, inset, s - 1 - inset, s - 1 - inset), outline=ring, width=max(2, int(s * 0.014)))
    f = font(int(s * (0.56 if len(MONOGRAM) == 1 else 0.42)), 800)
    spaced(dr, (s / 2, s / 2 + s * 0.02), MONOGRAM, f, BRAND + (255,), -s * 0.01, anchor='mm')
    return img.resize((d, d), Image.LANCZOS)


def shadow(img, radius, alpha=150, offset=(0, 0)):
    a = img.getchannel('A').point(lambda v: v * alpha // 255)
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(radius))
    out = Image.new('RGBA', img.size, 0)
    out.alpha_composite(sh, offset)
    return out


def mark(out, k=1, drop=True):
    """`k` scales everything (1 = the 256 px UI file). `drop` = the soft shadow under it."""
    size = 256 * k
    canvas = Image.new('RGBA', (size, size), 0)
    b = badge(232 * k)
    layer = Image.new('RGBA', (size, size), 0)
    layer.alpha_composite(b, (12 * k, 10 * k))
    if drop:
        canvas.alpha_composite(shadow(layer, 6 * k, 120, (0, 4 * k)))
    canvas.alpha_composite(layer)
    canvas.save(out, optimize=True)


def lockup(out, k=1, ink=WHITE):
    """Badge on the left, the name and the print stacked beside it. Light artwork by
    default, because every surface it lands on in game is dark; `ink` = INK for light ones."""
    w, h = 1100 * k, 240 * k      # cropped to the artwork afterwards
    big = Image.new('RGBA', (w * SS, h * SS), 0)
    dr = ImageDraw.Draw(big)

    d = int(h * 0.78)
    b = badge(d * SS, ss=1)
    by = (h * SS - d * SS) // 2
    big.alpha_composite(b, (int(8 * k * SS), by))

    x = int((8 * k + d + 34 * k) * SS)
    fn = font(int(70 * k * SS), 800)
    nw = spaced(dr, (x, int(h * 0.45 * SS)), NAME, fn, ink + (255,), 3 * k * SS, 'ls')
    second = BRAND_HI if ink == WHITE else BRAND
    spaced(dr, (x + nw + 20 * k * SS, int(h * 0.45 * SS)), NAME_2, fn, second + (255,), 3 * k * SS, 'ls')

    fp = font(int(21 * k * SS), 400)
    spaced(dr, (x + 2 * k * SS, int(h * 0.66 * SS)), TAGLINE, fp, ink + (150 if ink == WHITE else 170,), 7 * k * SS, 'lm')

    img = big.resize((w, h), Image.LANCZOS)
    bbox = img.getchannel('A').getbbox()
    if bbox:
        img = img.crop((0, 0, min(w, bbox[2] + 10 * k), h))
    img.save(out, optimize=True)


def icon(out, k=1):
    """The phone tile, like the boxes: brand colour, the badge, the name under it."""
    size = 512 * k
    big = Image.new('RGBA', (size * SS, size * SS), 0)
    tile = gradient((size * SS, size * SS), BRAND_HI, BRAND_LO).convert('RGBA')
    m = Image.new('L', (size * SS, size * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), int(size * 0.22 * SS), fill=255)
    big.paste(tile, (0, 0), m)

    # a soft sheen across the top, like the cards
    sheen = Image.new('RGBA', big.size, 0)
    ImageDraw.Draw(sheen).ellipse((-size * SS * 0.3, -size * SS * 0.85, size * SS * 1.3, size * SS * 0.45),
                                  fill=(255, 255, 255, 34))
    sheen.putalpha(Image.composite(sheen.getchannel('A'), Image.new('L', big.size, 0), m))
    big.alpha_composite(sheen)

    d = int(size * 0.5)
    b = badge(d * SS, ss=1)
    layer = Image.new('RGBA', big.size, 0)
    layer.alpha_composite(b, ((size * SS - d * SS) // 2, int(size * 0.13 * SS)))
    big.alpha_composite(shadow(layer, 10 * k * SS, 90, (0, 6 * k * SS)))
    big.alpha_composite(layer)

    dr = ImageDraw.Draw(big)
    fn = font(int(54 * k * SS), 800)
    spaced(dr, (size * SS / 2, int(size * 0.78 * SS)), f'{NAME} {NAME_2}', fn, WHITE + (255,), 1.5 * k * SS, 'mm')
    fp = font(int(19 * k * SS), 400)
    spaced(dr, (size * SS / 2, int(size * 0.88 * SS)), TAGLINE, fp, (255, 255, 255, 170), 5 * k * SS, 'mm')

    big.resize((size, size), Image.LANCZOS).save(out, optimize=True)


def press(out, k):
    os.makedirs(out, exist_ok=True)
    mark(os.path.join(out, 'fleeca_badge.png'), k, drop=False)
    mark(os.path.join(out, 'fleeca_badge_shadow.png'), k)
    lockup(os.path.join(out, 'fleeca_logo_light.png'), k)
    lockup(os.path.join(out, 'fleeca_logo_dark.png'), k, ink=INK)
    icon(os.path.join(out, 'fleeca_app_icon.png'), k)


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 2 and sys.argv[1] == '--press':
        press(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 4)
        print('press logos written to', sys.argv[2])
        sys.exit(0)
    web = os.path.join(HERE, '..', 'web')
    mark(os.path.join(web, 'images', 'mark.png'))
    lockup(os.path.join(web, 'images', 'logo.png'))
    icon(os.path.join(web, 'phone', 'icon.png'))
    print('mark.png, logo.png, phone/icon.png')
