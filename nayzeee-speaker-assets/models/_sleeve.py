"""Shared by nayzeee_sleeve_a / _b / _c: the record sleeve model and the default cover art.

Shared contract ("Shop sleeves"): origin = centre of the sleeve's bottom edge, standing upright,
cover facing +Y, size 0.315 x 0.315 x 0.004.  Each sleeve draws its front with texture
nayzeee_cover_<letter> (runtime-replaceable: the record shop puts the album cover there with a DUI),
UV 0..1 over the whole front.

The sleeve is a real pocket: two 0.5 mm cards joined along the top, the bottom and the +X edge,
open along the -X edge (viewer's right), so the record can slide out where client/shop.lua moves it
(sleeve-local x < 0, centred in the thickness).  Inner gap 3 mm; the record is 2.5 mm thick.

The three default covers are one abstract "nayzeee record shop" design in three colourways:
a record half out of its sleeve above a crate of records, with the mark and small type.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from lib import mesh as M
from lib import textures as tx
from lib.spec import Anchor, Box, LodSettings, ModelSpec
from models import _tt_common as C

SIZE = 0.315
THICK = 0.004
CARD = 0.0005                      # card thickness -> inner gap 3 mm
CORNER = 0.0025

# --------------------------------------------------------------------------- cover art
COLOURWAYS = {
    #      background top/bottom,  accent,    accent hi,  ink (type/record), paper (light elements), label
    "a": dict(bg=("#121517", "#08090a"), acc="#08afa2", hi="#0fd4c4", ink="#08090a", paper="#f2f4f5",
              crate=("#1c2023", "#2a3034", "#3a4247"), sel="SELECTION  A", dark=True),
    "b": dict(bg=("#1a1012", "#0b0708"), acc="#e5484d", hi="#ff7a7e", ink="#0b0708", paper="#f6ece4",
              crate=("#2a1a1c", "#3a2427", "#4d3134"), sel="SELECTION  B", dark=True),
    "c": dict(bg=("#efe9dc", "#ddd5c3"), acc="#e09a2e", hi="#f2b552", ink="#15181b", paper="#15181b",
              crate=("#cfc6b2", "#bdb39c", "#a89e87"), sel="SELECTION  C", dark=False),
}


def _rgba(c, a=255):
    v = tx.hex_rgb(c)
    return (int(v[0] * 255 + 0.5), int(v[1] * 255 + 0.5), int(v[2] * 255 + 0.5), a)


def _record(img, cx, cy, R, cw):
    """A record seen from the front: black disc, groove rings with a soft sheen, accent label."""
    S = img.size[0]
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) + 0.5
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / R
    ang = np.arctan2(yy - cy, xx - cx)
    disc = np.clip((1.0 - r) * R / 1.2, 0, 1)                           # anti-aliased edge
    grooves = 0.5 + 0.5 * np.sin(r * 2 * math.pi * 44)
    tracks = np.ones_like(r)
    for g in (0.86, 0.74, 0.63):                                        # track gaps
        tracks *= tx.smoothstep(0.004, 0.012, np.abs(r - g))
    sheen = np.clip(np.cos(2 * (ang + 0.7)), 0, 1) ** 6 * 0.55 + np.clip(np.cos(2 * (ang - 1.2)), 0, 1) ** 10 * 0.25
    base = tx.hex_rgb("#0b0c0d")
    groove_lum = (0.035 + 0.05 * grooves * tracks) * (1 + 2.2 * sheen)
    col = base[None, None, :] + groove_lum[:, :, None]
    lab = r < 0.36
    lab_col = tx.hex_rgb(cw["acc"])
    col[lab] = lab_col * (0.92 + 0.08 * np.cos(ang[lab] - 0.8))[:, None]
    rim = (np.abs(r - 0.36) < 0.006)
    col[rim] = col[rim] * 0.6
    hole = r < 0.03
    col[hole] = tx.hex_rgb(cw["bg"][1])
    layer = np.concatenate([np.clip(col, 0, 1), disc[:, :, None]], 2)
    img.alpha_composite(Image.fromarray((layer * 255 + 0.5).astype(np.uint8), "RGBA"))
    # print on the label: mark + a line of type
    ms = R * 0.2
    tx.draw_mark(img, cx - ms / 2, cy - R * 0.27, ms, "ink")
    d = ImageDraw.Draw(img)
    tx.draw_text(d, (cx, cy + R * 0.17), "33 RPM", R * 0.055, 600, _rgba(cw["ink"], 220), "mm", 0.2)


def _cover(letter: str, w: int, h: int) -> np.ndarray:
    cw = COLOURWAYS[letter]
    ss = 2
    S = w * ss
    # background: vertical gradient, paper grain, soft vignette
    yy = np.linspace(0, 1, S)[:, None]
    bg = tx.lerp_colors(np.repeat(yy, S, axis=1), [(0.0, cw["bg"][0]), (1.0, cw["bg"][1])])
    g = tx.blur(tx.white(S, S, 141 + ord(letter)), 0.8) * 0.010 + tx.fbm(S, S, 3, 4, seed=150 + ord(letter)) * 0.012
    Y, X = np.mgrid[0:S, 0:S] / S
    vig = 1 - 0.18 * np.clip(((X - 0.5) ** 2 + (Y - 0.45) ** 2) * 2.2, 0, 1) if cw["dark"] else 1 - 0.06 * Y
    bg = np.clip(bg * vig[:, :, None] + g[:, :, None], 0, 1)
    img = Image.fromarray((np.concatenate([bg, np.ones((S, S, 1))], 2) * 255 + 0.5).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    # the crate: a row of record spines standing in a bin (lower third)
    r = tx.rng(300 + ord(letter))
    floor = S * 0.865
    x = S * 0.06
    k = 0
    while x < S * 0.94:
        wd = S * r.uniform(0.010, 0.022)
        ht = S * r.uniform(0.17, 0.25)
        lean = S * r.uniform(-0.012, 0.012)
        tone = cw["crate"][k % 3] if r.uniform() > 0.18 else (cw["acc"] if r.uniform() > 0.5 else cw["paper"])
        a = 255 if tone not in (cw["paper"],) else (210 if cw["dark"] else 255)
        d.polygon([(x, floor), (x + wd, floor), (x + wd + lean, floor - ht), (x + lean, floor - ht)], fill=_rgba(tone, a))
        x += wd + S * r.uniform(0.002, 0.006)
        k += 1
    # crate front board with a slot, the shop's counter line
    board = cw["ink"] if not cw["dark"] else cw["crate"][0]
    d.rounded_rectangle([S * 0.04, S * 0.80, S * 0.96, S * 0.885], radius=S * 0.008, fill=_rgba(board))
    d.rectangle([S * 0.048, S * 0.80, S * 0.952, S * 0.803], fill=_rgba(cw["crate"][2] if cw["dark"] else "#3a3f44"))
    d.rounded_rectangle([S * 0.40, S * 0.822, S * 0.60, S * 0.838], radius=S * 0.008, fill=_rgba(cw["bg"][1]))
    d.rectangle([S * 0.04, S * 0.885, S * 0.96, S * 0.889], fill=_rgba(cw["acc"]))
    # hero: the featured sleeve with its record slid half out (like the shop's carousel)
    sx0, sy0, ss_ = S * 0.10, S * 0.20, S * 0.46
    cx, cy, R = sx0 + ss_ * 0.98, sy0 + ss_ / 2, ss_ * 0.47
    _record(img, cx, cy, R, cw)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([sx0 + S * 0.012, sy0 + S * 0.014, sx0 + ss_ + S * 0.012, sy0 + ss_ + S * 0.014],
                                     fill=(0, 0, 0, 110 if cw["dark"] else 60))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)))
    d = ImageDraw.Draw(img)
    d.rectangle([sx0, sy0, sx0 + ss_, sy0 + ss_], fill=_rgba(cw["acc"]))
    # sleeve print: concentric quarter arcs + mark (an abstract cover on the cover)
    for k2 in range(7):
        rr = ss_ * (0.18 + 0.1 * k2)
        d.arc([sx0 - rr, sy0 + ss_ - rr, sx0 + rr, sy0 + ss_ + rr], 270, 360, fill=_rgba(cw["hi"] if k2 % 2 else cw["ink"], 200 if k2 % 2 else 90),
              width=max(2, int(S * 0.006)))
    tx.draw_mark(img, sx0 + ss_ * 0.70, sy0 + ss_ * 0.08, ss_ * 0.2, "ink")
    # type: wordmark top left, micro labels, selection letter
    tx.draw_mark(img, S * 0.06, S * 0.055, S * 0.06, "color" if cw["dark"] else "ink")
    tx.draw_text(d, (S * 0.135, S * 0.088), "nayzeee", S * 0.055, 600, _rgba(cw["paper"] if cw["dark"] else cw["ink"]), "lm")
    tx.draw_text(d, (S * 0.94, S * 0.088), "RECORD  SHOP", S * 0.024, 600, _rgba(cw["acc"]), "rm", 0.32)
    tx.draw_text(d, (S * 0.06, S * 0.935), cw["sel"], S * 0.026, 600,
                 _rgba(cw["paper"] if cw["dark"] else cw["ink"], 235), "lm", 0.3)
    tx.draw_text(d, (S * 0.94, S * 0.935), "33 RPM  ·  STEREO", S * 0.020, 500,
                 _rgba("#8b9298" if cw["dark"] else "#6b6458"), "rm", 0.3)
    return tx.finish(img, ss)[:, :, :3]


def _install_covers():
    """Make the three runtime-replaceable cover defaults (registered in lib.textures) use this art."""
    for letter in "abc":
        d = tx.get(f"nayzeee_cover_{letter}")
        d.fn = (lambda L: (lambda w, h: _cover(L, w, h)))(letter)
        d.description = (f"Default sleeve art {letter.upper()} (runtime-replaceable): abstract nayzeee record shop, "
                         f"{('teal', 'coral', 'ivory/amber')['abc'.index(letter)]} colourway.")
    cached = getattr(tx, "_image_cached", None)
    if cached is not None and hasattr(cached, "cache_clear"):
        cached.cache_clear()


_install_covers()


@C._tex("nz_tt_sleeve_back_d", 512, description="Record sleeve back: black card, abstract track list, barcode.")
def _sleeve_back(w, h):
    ss = 2
    S = w * ss
    f = tx.blur(tx.white(S, S, 161), 0.8) * 0.035 + tx.fbm(S, S, 3, 4, seed=162) * 0.02
    base = tx.hex_rgb("#121315")[None, None, :] * (1 + f[:, :, None])
    img = Image.fromarray((np.concatenate([np.clip(base, 0, 1), np.ones((S, S, 1))], 2) * 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    grey, dim, teal = (150, 156, 160, 255), (80, 85, 89, 255), _rgba(tx.TEAL)
    tx.draw_mark(img, S * 0.07, S * 0.07, S * 0.07, "white")
    tx.draw_text(d, (S * 0.165, S * 0.105), "nayzeee  records", S * 0.034, 600, (235, 238, 240, 255), "lm", 0.04)
    d.rectangle([S * 0.07, S * 0.18, S * 0.93, S * 0.182], fill=dim)
    r = tx.rng(171)
    for col, side in ((0.07, "SIDE  A"), (0.52, "SIDE  B")):
        tx.draw_text(d, (S * col, S * 0.225), side, S * 0.022, 600, teal, "lm", 0.3)
        for i in range(6):
            y = S * (0.27 + i * 0.052)
            tx.draw_text(d, (S * col, y), f"{i + 1:02d}", S * 0.020, 500, grey, "lm", 0.1)
            ln = S * r.uniform(0.17, 0.32)
            d.rounded_rectangle([S * (col + 0.05), y - S * 0.006, S * (col + 0.05) + ln, y + S * 0.006],
                                radius=S * 0.006, fill=dim)
            d.rounded_rectangle([S * (col + 0.36), y - S * 0.006, S * (col + 0.40), y + S * 0.006],
                                radius=S * 0.006, fill=(60, 64, 67, 255))
    d.rectangle([S * 0.07, S * 0.62, S * 0.93, S * 0.622], fill=dim)
    for i, ln in enumerate((0.62, 0.55, 0.66, 0.40)):
        y = S * (0.66 + i * 0.03)
        d.rounded_rectangle([S * 0.07, y - S * 0.004, S * (0.07 + ln * 0.6), y + S * 0.004], radius=S * 0.004,
                            fill=(58, 62, 65, 255))
    # barcode + fine print
    bx, by = S * 0.70, S * 0.80
    d.rectangle([bx - S * 0.012, by - S * 0.012, bx + S * 0.232, by + S * 0.132], fill=(232, 234, 235, 255))
    x = bx
    while x < bx + S * 0.21:
        wd = S * (0.003 if r.uniform() > 0.4 else 0.0065)
        d.rectangle([x, by, x + wd, by + S * 0.09], fill=(14, 15, 16, 255))
        x += wd + S * (0.003 if r.uniform() > 0.5 else 0.005)
    tx.draw_text(d, (bx + S * 0.11, by + S * 0.112), "8 80512 30033 7", S * 0.016, 500, (14, 15, 16, 255), "mm", 0.12)
    tx.draw_text(d, (S * 0.07, S * 0.90), "33 RPM  ·  STEREO  ·  HIGH FIDELITY", S * 0.018, 500, grey, "lm", 0.25)
    tx.draw_text(d, (S * 0.07, S * 0.93), "NAYZEEE AUDIO  ·  RECORD SHOP EDITION", S * 0.016, 500, dim, "lm", 0.25)
    return tx.finish(img, ss)[:, :, :3]


C._ns("tt_sleeve_back", "nz_tt_sleeve_back_d", "nz_paper_n", "nz_paper_s", 1.0,
      C.PBR(roughness=0.62), "CARDBOARD_SHEET", "Printed sleeve back (UV 0..1, read from behind).",
      specularIntensityMult=0.22, specularFalloffMult=22.0, specularFresnel=0.86, bumpiness=0.5)


# --------------------------------------------------------------------------- model
def build_sleeve(letter: str) -> ModelSpec:
    half = SIZE / 2
    outline = M.rounded_rect_2d(SIZE, SIZE, CORNER, 3)
    inner = THICK / 2 - CARD                        # 0.0015: inside faces of the cards
    parts = []
    # front card: the cover print on its outside face
    front = M.extrude(outline, CARD, material="sleeve_card").orient("+y", (0, inner, half))
    cover, rest = C.facing(front, (0, 1, 0), 0.999)
    cover = cover.with_material(f"sleeve_cover_{letter}", rescale_uvs=False).uv_fit((0, 0, 1, 1), "+y")
    parts += [cover.named("cover"), rest.named("card_front")]
    # back card: printed back on its outside face
    back = M.extrude(outline, CARD, material="sleeve_card").orient("-y", (0, -inner, half))
    bprint, brest = C.facing(back, (0, -1, 0), 0.999)
    bprint = bprint.with_material("tt_sleeve_back", rescale_uvs=False).uv_fit((0, 0, 1, 1), "-y")
    parts += [bprint.named("back_print"), brest.named("card_back")]
    # glued folds closing the pocket along the top, the bottom and the +X edge (open along -X)
    t = 0.0006
    span = SIZE - 2 * CORNER
    for size, centre in (((span, 2 * inner, t), (0, 0, SIZE - t / 2 - 0.0001)),
                         ((span, 2 * inner, t), (0, 0, t / 2 + 0.0001)),
                         ((t, 2 * inner, span), (half - t / 2 - 0.0001, 0, half))):
        parts.append(M.box(size, centre, material="sleeve_card").named("fold"))
    return ModelSpec(
        name=f"nayzeee_sleeve_{letter}",
        parts=parts,
        collision=[Box((0, 0, half), (SIZE, THICK, SIZE), "CARDBOARD_SHEET")],
        anchors={
            "bottom_centre": Anchor((0, 0, 0), note="model origin = centre of the bottom edge"),
            "record_mouth": Anchor((-half, 0, half), note="open edge (-X): the record slides out here, centred in "
                                                          "the thickness"),
            "cover_centre": Anchor((0, THICK / 2, half), note="front cover centre (+Y)"),
        },
        lod=LodSettings(high_dist=5.0, archetype_lod_dist=50.0, hd_texture_dist=4.0, med_detail=0.5),
        description=f"Record sleeve {letter.upper()} for the shop display: a real pocket open on the -X edge; front "
                    f"texture nayzeee_cover_{letter} is runtime-replaceable (UV 0..1 over the front).",
        meta={"size": [SIZE, THICK, SIZE], "cover_texture": f"nayzeee_cover_{letter}", "open_edge": "-X",
              "inner_gap": 2 * inner, "render": {"pitch": 10, "yaw": 20}},
    )
