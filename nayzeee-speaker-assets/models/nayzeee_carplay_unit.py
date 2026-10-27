"""nayzeee_carplay_unit -- image-only model (export=False) for the inventory image of the CarPlay item.

A double-DIN car head unit: gloss black faceplate (182 x 104 mm) with a glossy 2:1 touch screen showing a
dark nayzeee music player (teal accents, Lexend), a left control strip with three icon keys, a knurled
volume knob on a teal light ring, small prints, and the galvanised steel DIN cage behind it (top vent,
side mounting holes, rear connector).

Not exported to the game (no ydr / ytyp entry): it only feeds `tools/item_images.py`, which renders
nayzeee-speaker/install/images/nayzeee_carplay.png.  Model space: origin = floor centre under the unit,
+Y = front (the screen), +X = viewer's left.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from lib import materials as mats
from lib import mesh as M
from lib import textures as tx
from lib.materials import PBR, Material
from lib.spec import Anchor, Box, LodSettings, ModelSpec
from models import _tt_common as C

FACE_W, FACE_H, FACE_T = 0.182, 0.104, 0.012      # faceplate
CAGE_W, CAGE_H, CAGE_D = 0.178, 0.100, 0.135      # DIN cage behind it
FY = 0.085                                        # faceplate front (y)
ZC = FACE_H / 2                                   # faceplate centre height (it stands on the floor)
SCREEN = (0.140, 0.070)                           # lit area (2:1, the UI texture)
GLASS = (0.146, 0.080)                            # glass incl. its black border
SCREEN_X = 0.0145                                 # design x (viewer's right = +) of the screen centre
STRIP_X = -0.074                                  # design x of the left control strip


# --------------------------------------------------------------------------- screen UI texture
def _rgba(c, a=255):
    v = tx.hex_rgb(c)
    return (int(v[0] * 255 + 0.5), int(v[1] * 255 + 0.5), int(v[2] * 255 + 0.5), a)


def _album_art(S: int) -> Image.Image:
    """Abstract square cover for the now-playing card: teal gradient, record rings, the mark."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) / S
    col = tx.lerp_colors(np.clip(xx * 0.6 + yy * 0.6, 0, 1), [(0.0, tx.TEAL_HI), (0.55, tx.TEAL), (1.0, "#05453f")])
    r = np.hypot(xx - 0.72, yy - 0.78)
    rings = (np.sin(r * 2 * math.pi * 14) > 0.75) & (r < 0.62)
    col = np.where(rings[:, :, None], col * 0.82, col)
    disc = r < 0.20
    col = np.where(disc[:, :, None], tx.hex_rgb("#08090a")[None, None, :], col)
    img = Image.fromarray((np.dstack([col, np.ones((S, S))]) * 255).astype(np.uint8), "RGBA")
    tx.draw_mark(img, S * 0.09, S * 0.09, S * 0.26, "ink")
    return img


@tx.register("nz_cp_screen_e", (1024, 512), kind="emissive",
             description="CarPlay unit screen: dark nayzeee music player with teal accents (2:1).")
def _screen_ui(w, h):
    ss = 2
    W, H = w * ss, h * ss
    u = W / 1024.0                                                       # 1 design px
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    base = tx.lerp_colors(yy / H, [(0.0, "#0d1011"), (1.0, "#07080a")])
    glow = np.exp(-(((xx - 270 * u) / (330 * u)) ** 2 + ((yy - 250 * u) / (230 * u)) ** 2))
    base = base + glow[:, :, None] * tx.hex_rgb(tx.TEAL)[None, None, :] * 0.16
    img = Image.fromarray((np.dstack([np.clip(base, 0, 1), np.ones((H, W))]) * 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    white, grey, dim = (242, 244, 245, 255), (150, 158, 164, 255), (58, 64, 69, 255)
    teal = _rgba(tx.TEAL)
    # status bar
    tx.draw_text(d, (118 * u, 34 * u), "12:45", 26 * u, 600, white, "lm")
    for i, hgt in enumerate((8, 13, 18, 23)):                            # signal bars
        x = (930 + i * 9) * u
        d.rounded_rectangle([x, (44 - hgt) * u, x + 5 * u, 44 * u], radius=1.5 * u, fill=white)
    d.rounded_rectangle([972 * u, 23 * u, 1004 * u, 44 * u], radius=4 * u, outline=white, width=int(2 * u))
    d.rounded_rectangle([976 * u, 27 * u, 996 * u, 40 * u], radius=2 * u, fill=teal)
    tx.draw_text(d, (512 * u, 34 * u), "NAYZEEE  AUDIO", 17 * u, 600, grey, "mm", 0.3)
    # dock on the left: home, music (active), map pin, phone
    d.rounded_rectangle([14 * u, 64 * u, 92 * u, 498 * u], radius=22 * u, fill=(18, 21, 23, 255))
    cx = 53 * u
    for k, y in enumerate((118, 214, 310, 406)):
        y = y * u
        if k == 1:
            d.rounded_rectangle([cx - 30 * u, y - 30 * u, cx + 30 * u, y + 30 * u], radius=16 * u, fill=teal)
        col = (8, 9, 10, 255) if k == 1 else grey
        if k == 0:                                                       # home
            d.polygon([(cx - 17 * u, y - 1 * u), (cx, y - 17 * u), (cx + 17 * u, y - 1 * u)], fill=col)
            d.rectangle([cx - 12 * u, y - 2 * u, cx + 12 * u, y + 15 * u], fill=col)
            d.rectangle([cx - 4 * u, y + 5 * u, cx + 4 * u, y + 15 * u], fill=(18, 21, 23, 255))
        elif k == 1:                                                     # music note
            tx._icon(d, "icon_note", cx - 26 * u, y - 26 * u, 52 * u, col)
        elif k == 2:                                                     # map pin
            d.ellipse([cx - 13 * u, y - 18 * u, cx + 13 * u, y + 8 * u], fill=col)
            d.polygon([(cx - 11 * u, y - 1 * u), (cx + 11 * u, y - 1 * u), (cx, y + 19 * u)], fill=col)
            d.ellipse([cx - 5 * u, y - 10 * u, cx + 5 * u, y], fill=(18, 21, 23, 255))
        else:                                                            # phone handset
            d.rounded_rectangle([cx - 10 * u, y - 17 * u, cx + 10 * u, y + 17 * u], radius=5 * u, fill=col)
            d.rectangle([cx - 6 * u, y - 11 * u, cx + 6 * u, y + 9 * u], fill=(18, 21, 23, 255))
    # now playing: album art card
    S = int(300 * u)
    art = _album_art(S)
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1], radius=22 * u, fill=255)
    art.putalpha(m)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([126 * u, 112 * u, 426 * u, 412 * u], radius=22 * u, fill=(0, 0, 0, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14 * u)))
    img.alpha_composite(art, (int(120 * u), int(96 * u)))
    d = ImageDraw.Draw(img)
    # track info
    x0 = 462 * u
    tx.draw_text(d, (x0, 122 * u), "NOW PLAYING  ·  RECORD", 17 * u, 600, teal, "lm", 0.28)
    tx.draw_text(d, (x0, 176 * u), "Midnight Drive", 50 * u, 600, white, "lm")
    tx.draw_text(d, (x0, 226 * u), "nayzeee sessions", 30 * u, 400, grey, "lm")
    # progress
    y = 296 * u
    x1 = 982 * u
    d.rounded_rectangle([x0, y - 4 * u, x1, y + 4 * u], radius=4 * u, fill=dim)
    xp = x0 + (x1 - x0) * 0.38
    d.rounded_rectangle([x0, y - 4 * u, xp, y + 4 * u], radius=4 * u, fill=teal)
    d.ellipse([xp - 11 * u, y - 11 * u, xp + 11 * u, y + 11 * u], fill=white)
    tx.draw_text(d, (x0, y + 32 * u), "1:24", 20 * u, 500, grey, "lm")
    tx.draw_text(d, (x1, y + 32 * u), "3:41", 20 * u, 500, grey, "rm")
    # controls: shuffle, previous, pause (teal), next, repeat
    cy = 410 * u
    mid = (x0 + x1) / 2
    r = 46 * u
    d.ellipse([mid - r, cy - r, mid + r, cy + r], fill=teal)
    for ox in (-13, 5):
        d.rounded_rectangle([mid + ox * u, cy - 18 * u, mid + (ox + 9) * u, cy + 18 * u], radius=2 * u, fill=(8, 9, 10, 255))
    for sgn in (-1, 1):
        cx2 = mid + sgn * 128 * u
        tri = [(cx2 - sgn * 14 * u, cy - 17 * u), (cx2 - sgn * 14 * u, cy + 17 * u), (cx2 + sgn * 12 * u, cy)]
        d.polygon(tri, fill=white)
        xa, xb = sorted((cx2 + sgn * 12 * u, cx2 + sgn * 18 * u))
        d.rectangle([xa, cy - 17 * u, xb, cy + 17 * u], fill=white)
        cx3 = mid + sgn * 222 * u
        if sgn < 0:                                                      # like (heart outline)
            hrt = [(cx3 + 17 * u * math.sin(t) ** 3,
                    cy - u * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * 1.05)
                   for t in np.linspace(0, 2 * math.pi, 60)]
            d.line(hrt + [hrt[0]], fill=teal, width=int(4 * u), joint="curve")
        else:                                                            # queue (three lines)
            for k in range(3):
                yk = cy + (k - 1) * 11 * u
                d.rounded_rectangle([cx3 - 16 * u, yk - 2 * u, cx3 + (16 - 8 * (k == 2)) * u, yk + 2 * u],
                                    radius=2 * u, fill=grey)
    # soft vignette towards the glass border
    a = tx.finish(img, ss)[:, :, :3]
    hh, ww = a.shape[:2]
    Y, X = np.mgrid[0:hh, 0:ww]
    e = np.minimum(np.minimum(X, ww - 1 - X) / ww, np.minimum(Y, hh - 1 - Y) / hh)
    return np.clip(a * (0.86 + 0.14 * tx.smoothstep(0.0, 0.05, e))[:, :, None], 0, 1)


def _mat(m: Material) -> Material:
    return mats.get(m.name) if m.name in mats.names() else mats.register(m)


@tx.register("nz_cp_zinc_d", 512, description="Galvanised (zinc-plated) steel with a faint spangle.")
def _zinc_d(w, h):
    r = tx.rng(331)
    n = 700
    pts = np.column_stack([r.uniform(0, w, n), r.uniform(0, h, n)])
    tone = r.uniform(-1, 1, n)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    best = np.full((h, w), np.inf)
    val = np.zeros((h, w))
    for (px, py), t in zip(pts, tone):                  # wrapped Voronoi cells = zinc crystals
        dx = np.abs(xx - px); dx = np.minimum(dx, w - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, h - dy)
        dd = dx * dx + dy * dy
        m = dd < best
        best[m] = dd[m]
        val[m] = t
    grain = tx.blur(tx.white(w, h, 332), 0.7)
    lum = 0.90 + 0.022 * val + 0.012 * tx.standardize(grain) + 0.008 * tx.fbm(w, h, 3, 4, seed=333)
    return np.clip(lum[:, :, None] * tx.hex_rgb("#dfe3e6")[None, None, :], 0, 1)


_mat(Material("cp_zinc", "normal_spec", {"DiffuseSampler": "nz_cp_zinc_d", "BumpSampler": "nz_metal_fine_n",
                                         "SpecSampler": "nz_spec_full"},
              {"specularIntensityMult": 0.9, "specularFalloffMult": 90.0, "bumpiness": 0.4},
              PBR(metallic=1.0, roughness=0.34), 0.20, "METAL_SOLID_SMALL", "Galvanised steel DIN cage."))
_mat(Material("cp_screen", "emissive", {"DiffuseSampler": "nz_cp_screen_e"}, {"emissiveMultiplier": 1.0},
              PBR(base_color=(0.03, 0.03, 0.03), roughness=0.07, emissive=(1.0, 1.0, 1.0), emissive_strength=1.15),
              1.0, "GLASS_OPAQUE", "Lit touch screen (UV 0..1, 2:1) under glossy glass."))


# --------------------------------------------------------------------------- geometry
def _print(entry: str, height: float, x: float, y: float, z: float = C.DECAL_OFF) -> M.Mesh:
    """Print-atlas decal in design space (image upright on the face), ``height`` tall."""
    w = height * tx.atlas_aspect(entry)
    return M.plane(w, height, center=(x, y, z), facing="design", rect=tx.atlas_rect(entry), material="print_decal")


def _face(parts):
    """Everything on the front, built in design space (x = viewer's right, y = up, +z out of the face)."""
    def put(m, z=0.0):
        return m.translate(0, 0, z).orient("+y", (0, FY, ZC))

    plate = M.rounded_box((FACE_W, FACE_H, FACE_T), (0.004, 0.004, 0.0022), 3,
                          center=(0, 0, -FACE_T / 2), material="gloss_black_plastic")
    parts.append(put(plate).named("faceplate"))
    # glass with a black border, the lit UI just above it
    glass = M.plane(GLASS[0], GLASS[1], center=(SCREEN_X, 0.004, 0.0003), facing="design", material="screen_glass_dark")
    parts.append(put(glass).named("glass"))
    ui = M.plane(SCREEN[0], SCREEN[1], center=(SCREEN_X, 0.004, 0.0007), facing="design", material="cp_screen")
    parts.append(put(ui).named("screen"))
    # thin brushed trim around the glass
    hole = M.rounded_rect_2d(GLASS[0] + 0.0006, GLASS[1] + 0.0006, 0.0015, 2, center=(SCREEN_X, 0.004))
    trim = M.extrude(M.rounded_rect_2d(GLASS[0] + 0.0030, GLASS[1] + 0.0030, 0.0028, 3, center=(SCREEN_X, 0.004)),
                     0.0006, holes=[hole], cap_bottom=False, material="brushed_aluminium")
    parts.append(put(trim).named("glass_trim"))
    # left strip: mark, three icon keys, volume knob on a teal light ring
    parts.append(put(_print("mark_white", 0.0075, STRIP_X, 0.042)).named("print"))
    for y, icon in ((0.026, "icon_note"), (0.012, "icon_bluetooth"), (-0.002, "icon_power")):
        key = M.rounded_box((0.023, 0.0098, 0.0026), (0.0018, 0.0018, 0.0008), 3, center=(STRIP_X, y, 0.0013),
                            material="satin_graphite")
        parts.append(put(key).named("key"))
        parts.append(put(_print(icon, 0.0062, STRIP_X, y, 0.0026 + C.DECAL_OFF)).named("key_icon"))
    kx, ky, r = STRIP_X, -0.026, 0.0112
    ring = M.tube(r + 0.0016, r + 0.0002, 0.0007, 48, material="led_teal")
    parts.append(put(ring.translate(kx, ky, 0)).named("knob_ring"))
    grip = M.lathe([(r - 0.0006, 0.0, 0.0, -1.0), (r, 0.0006, 1.0, 0.0), (r, 0.0085, 1.0, 0.0)], 56,
                   material="tt_alu_knurl").uv_cylindrical("z")
    cap = M.lathe([(r, 0.0085), (r - 0.0010, 0.0098), (r - 0.0016, 0.0101, 0.0, 1.0), (0.0, 0.0101, 0.0, 1.0)], 56,
                  crease=35, material="brushed_aluminium_radial").uv_radial(r)
    for p, n in ((grip, "knob_grip"), (cap, "knob_cap")):
        parts.append(put(p.translate(kx, ky, 0.0003)).named(n))
    dot = M.cylinder(0.0009, 0.0002, 16, material="teal_plastic").translate(kx, ky + r * 0.62, 0.0101 + 0.0003)
    parts.append(put(dot).named("knob_dot"))
    parts.append(put(_print("volume", 0.0034, kx, -0.044)).named("print"))
    # small prints along the bottom edge under the screen
    parts.append(put(_print("wordmark", 0.0046, SCREEN_X + 0.055, -0.0435)).named("print"))
    parts.append(put(_print("hi_fi_stereo", 0.0030, SCREEN_X - 0.045, -0.0435)).named("print"))
    # microphone pin hole above the screen
    parts.append(put(M.cylinder(0.0007, 0.0002, 12, material="gloss_black_plastic").translate(SCREEN_X + 0.060, 0.0475, 0.0)).named("mic"))


def _cage(parts):
    y1 = FY - FACE_T
    y0 = y1 - CAGE_D
    yc = (y0 + y1) / 2
    cage = M.rounded_box((CAGE_W, CAGE_D, CAGE_H), 0.0015, 2, center=(0, yc, ZC), material="cp_zinc").uv_box()
    parts.append(cage.named("cage"))
    top = ZC + CAGE_H / 2
    vent = M.plane(0.120, 0.080, center=(0, y0 + 0.055, top + 0.0003), facing="+z", material="speaker_grille_round")
    parts.append(vent.uv_planar("+z").named("vent"))
    for sx in (-1, 1):                                    # side mounting holes (two rows)
        for y in np.linspace(y1 - 0.025, y0 + 0.030, 5):
            for z in (ZC - 0.022, ZC + 0.022):
                h = M.disc(0.0024, 0.0, 16, facing="+x" if sx > 0 else "-x", material="gloss_black_plastic")
                parts.append(h.translate(sx * (CAGE_W / 2 + 0.0003), float(y), z).named("mount_hole"))
    # rear connector block + antenna socket
    parts.append(M.rounded_box((0.070, 0.010, 0.028), 0.0015, 2, center=(0.02, y0 - 0.005, ZC - 0.018),
                               material="matte_black_plastic").named("connector"))
    parts.append(M.cylinder(0.0045, 0.012, 16, material="chrome").orient("-y", (-0.05, y0, ZC + 0.02))
                 .named("antenna_socket"))


def build(detail: float) -> ModelSpec:
    parts = []
    _face(parts)
    _cage(parts)
    y0 = FY - FACE_T - CAGE_D
    return ModelSpec(
        name="nayzeee_carplay_unit",
        parts=parts,
        collision=[Box.from_minmax((-FACE_W / 2, y0, 0.0), (FACE_W / 2, FY, FACE_H), "PLASTIC")],
        anchors={"screen_centre": Anchor((-SCREEN_X, FY + 0.0007, ZC + 0.004), note="centre of the lit screen")},
        lod=LodSettings(high_dist=10.0, archetype_lod_dist=60.0, hd_texture_dist=5.0, med_detail=0.5),
        export=False,
        description="Image-only: double-DIN CarPlay head unit for the nayzeee_carplay inventory image.",
        meta={"render": {"yaw": 35, "pitch": 18}},
    )
