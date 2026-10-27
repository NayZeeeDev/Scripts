"""
Shared building blocks for the radios (PX-740, FX-280, MX-905 and the example radio). Everything
here is generic hardware - no maker name, wordmark or NAYZEEE mark (Rule B).

Conventions
    Every helper works in the radio's GTA prop space (metres, +X = viewer's left, +Y = front, +Z up).
    Surface helpers take `at` (a point on the surface), `normal` (out of the surface) and `up` (the
    direction of the part's top / the canvas top); they build around +Z and align() the result, so the
    viewer looking at that surface sees local +X to the right and +Y up.
    m_*(b) register a material by a fixed name and return the name (call them as often as you like).
    Geometry helpers RETURN a Geo (add it with r.add / r.hi_only) unless their name says otherwise;
    part helpers (key, dpad, knob, knob_pair, ptt, round_button) ADD their part themselves inside
    r.part(...) with full metadata and return the part's origin (anchor).

Index
    materials   m_soft_black m_keypad_rubber m_ranger_green m_bumper_rubber m_grip_rubber m_gunmetal m_sma
                m_spring_steel m_smoked_glass m_led_lens m_led_off m_anodised_black m_olive_steel
                m_eggcrate_foam m_hardcase m_coax m_sticker_vinyl m_mesh m_contact_gold m_print_dark
    inks        INK (white orange teal red yellow grey green), ink(name), PRINT
    housing     housing, housing_frame, densify, split_groove_z, split_groove_y, overmould_panel, battery_pack,
                latch_tab, boss, guard_ring, wells, well_for
    parts       key_cap, key, keypad, dpad, knob, knob_pair, ptt, ptt_guard, round_button
    antennas    whip_antenna, rubber_duck, sma_nut, gooseneck
    details     speaker_bars, grille_holes, light_pipe, led_dome, belt_clip, lanyard_eye, charging_contacts,
                thumbscrew, round_connector, screen_window (+ the screen quad and its anchor)
    labels      legend_canvas, model_print, rating_label, battery_label, knob_scale, volume_dots,
                print_decal, perforation_decal, slots_decal  (+ common.caution_label / rating_plate)
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (DecalCanvas, Geo, box, chamfer_fillet_rect, cylinder, extrude, helix, lathe, normalize, quad, rr_lathe,
                     rrect, sweep, tube, vec, well_plate)
from nzprops.mesh import polyline_fillet, split_by_normal

from .common import align, m_led, rating_plate, screw

# ---------------------------------------------------------------------------------------------
# inks (printed legends) - pass **ink("white") to DecalCanvas text / glyph / rect calls
# ---------------------------------------------------------------------------------------------
INK = {
    "white": (238, 241, 243),
    "orange": (238, 120, 32),
    "teal": (24, 196, 184),
    "red": (226, 52, 48),
    "yellow": (236, 196, 40),
    "grey": (150, 156, 162),
    "green": (70, 214, 110),
    "black": (18, 19, 21),
}
PRINT = {"spec": 0.30, "gloss": 0.48, "height": 0.000006}   # pad print: a hair glossier and proud of the surface


def ink(name="white", **over):
    """Ink kwargs for DecalCanvas calls: color + the pad-print spec / gloss / height."""
    k = dict(PRINT)
    k["color"] = INK.get(name, name) if isinstance(name, str) else tuple(name)
    k.update(over)
    return k


# ---------------------------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------------------------
def m_soft_black(b):
    """Soft-touch black glass-filled polymer (housings): matte, fine stipple, edges wear a little lighter."""
    return b.mat("soft_black", color=(27, 28, 31), spec=0.16, gloss=0.26, bump="stipple", bump_amp=0.000035,
                 bump_scale=0.00045, grain=0.03, grain_scale=0.03, edge=0.55, dirt=0.12, wear_color=(70, 72, 76), cavity=0.6)


def m_keypad_rubber(b, tone="black"):
    """Silicone keypad rubber with a slight sheen: tone 'black' | 'grey'."""
    col = {"black": (26, 27, 30), "grey": (88, 92, 97)}[tone]
    return b.mat(f"keypad_{tone}", color=col, spec=0.24, gloss=0.40, bump="rubber", bump_amp=0.00002, bump_scale=0.0004,
                 grain=0.025, grain_scale=0.02, edge=0.35, dirt=0.08, wear_color=tuple(min(255, c + 40) for c in col),
                 scratch=0.05)


def m_ranger_green(b):
    """Ranger-green / dark olive polymer (#3b4034 range), matte with fine texture."""
    return b.mat("ranger_green", color=(59, 64, 52), spec=0.18, gloss=0.28, bump="stipple", bump_amp=0.00004,
                 bump_scale=0.0005, grain=0.035, grain_scale=0.03, edge=0.6, dirt=0.18, wear_color=(96, 102, 86), cavity=0.6)


def m_bumper_rubber(b):
    """Black rubber bumpers / armour."""
    return b.mat("bumper_rubber", color=(22, 23, 25), spec=0.10, gloss=0.18, bump="rubber", bump_amp=0.00006,
                 bump_scale=0.0006, grain=0.05, grain_scale=0.03, edge=0.3, dirt=0.2, wear_color=(60, 62, 66))


def m_grip_rubber(b, pattern="knurl", tone=(24, 25, 27), scale=0.0012, amp=0.00012):
    """Rubber overmould with a grip texture: pattern 'knurl' (fine diamond knurl), 'diamond' (raised
    lozenges), 'dimple', 'ribs' (horizontal) or 'ribs_u'."""
    return b.mat(f"grip_{pattern}", color=tone, spec=0.11, gloss=0.2, bump=pattern, bump_amp=amp, bump_scale=scale,
                 grain=0.04, grain_scale=0.03, edge=0.3, dirt=0.18, wear_color=(62, 64, 68))


def m_gunmetal(b):
    return b.mat("gunmetal", color=(62, 65, 70), spec=0.62, gloss=0.52, metal=1.0, bump="brushed", bump_amp=0.000008,
                 bump_scale=0.0004, grain=0.03, grain_scale=0.03, edge=0.45, dirt=0.1)


def m_sma(b, finish="nickel"):
    """SMA connector / antenna nut metal: finish 'nickel' | 'brass' | 'black' (black chrome)."""
    col = {"nickel": (176, 178, 182), "brass": (184, 150, 84), "black": (40, 41, 44)}[finish]
    return b.mat(f"sma_{finish}", color=col, spec=0.85, gloss=0.72, metal=1.0, bump="brushed", bump_amp=0.000006,
                 bump_scale=0.0003, grain=0.02, grain_scale=0.02, edge=0.3, dirt=0.15, scratch=0.25)


def m_spring_steel(b):
    """Blued / dark spring steel (belt clips)."""
    return b.mat("spring_steel", color=(74, 77, 82), spec=0.72, gloss=0.58, metal=1.0, bump="brushed", bump_amp=0.00001,
                 bump_scale=0.0004, grain=0.03, grain_scale=0.03, edge=0.6, dirt=0.12, wear_color=(170, 172, 176), scratch=0.4)


def m_smoked_glass(b, alpha=0.24):
    """Smoked cover glass over screens (alpha layer -> normal_spec_alpha)."""
    return b.mat("smoked_glass", color=(10, 12, 14), spec=0.95, gloss=0.94, alpha=alpha, layer="alpha", grain=0.0, edge=0.0,
                 scratch=0.12, smudge=0.35)


LED_COLORS = {"red": (255, 46, 40), "green": (60, 255, 120), "amber": (255, 170, 30), "teal": (30, 240, 220),
              "white": (240, 246, 255)}


def m_led_lens(b, color="red"):
    """Lit LED lens (glow layer -> emissive)."""
    return m_led(b, f"led_{color}", LED_COLORS.get(color, color))


def m_led_off(b, color="red"):
    """Unlit, tinted light-pipe lens (glossy, dark)."""
    c = LED_COLORS.get(color, color)
    return b.mat(f"lens_off_{color}", color=tuple(int(v * 0.22) + 8 for v in c), spec=0.9, gloss=0.92, edge=0.1, ao=0.5)


def m_anodised_black(b):
    return b.mat("anodised_black", color=(30, 31, 34), spec=0.5, gloss=0.46, metal=0.8, bump="brushed", bump_amp=0.000006,
                 bump_scale=0.0005, grain=0.02, grain_scale=0.03, edge=0.7, wear_color=(150, 154, 160), dirt=0.1)


def m_olive_steel(b):
    """Olive drab painted steel with chipped edges (bare steel shows through)."""
    return b.mat("olive_steel", color=(78, 84, 60), spec=0.26, gloss=0.34, metal=0.2, bump="orange_peel", bump_amp=0.00002,
                 bump_scale=0.002, grain=0.05, grain_scale=0.08, edge=0.8, wear=0.75, wear_color=(140, 140, 136), dirt=0.35,
                 scratch=0.35)


def m_eggcrate_foam(b):
    return b.mat("eggcrate_foam", color=(34, 35, 37), spec=0.03, gloss=0.05, bump="eggcrate", bump_amp=0.006, bump_scale=0.03,
                 grain=0.05, grain_scale=0.05, ao=1.0)


def m_hardcase(b, color=(42, 44, 40)):
    return b.mat("hardcase", color=color, spec=0.22, gloss=0.32, bump="stipple", bump_amp=0.00008, bump_scale=0.0012,
                 grain=0.04, grain_scale=0.08, edge=0.6, dirt=0.3, wear_color=tuple(min(255, c + 45) for c in color))


def m_coax(b):
    return b.mat("coax", color=(20, 21, 23), spec=0.36, gloss=0.52, grain=0.02, grain_scale=0.02, edge=0.15, dirt=0.15)


def m_sticker_vinyl(b, color=(236, 236, 230), name=None):
    return b.mat(name or f"vinyl_{color[0]}_{color[1]}_{color[2]}", color=color, spec=0.38, gloss=0.55, grain=0.01,
                 edge=0.15, dirt=0.1)


def m_mesh(b):
    """Dark acoustic mesh behind speaker bars / grilles."""
    return b.mat("acoustic_mesh", color=(12, 13, 14), spec=0.05, gloss=0.1, bump="perf", bump_amp=0.00015, bump_scale=0.0006,
                 ao=1.0, cavity=0.2)


def m_contact_gold(b):
    return b.mat("contact_gold", color=(208, 166, 78), spec=0.9, gloss=0.75, metal=1.0, grain=0.02, edge=0.2, dirt=0.15)


def m_print_dark(b):
    """Dark gloss panel behind screens (bezel floor)."""
    return b.mat("bezel_black", color=(9, 10, 11), spec=0.55, gloss=0.75, grain=0.01, edge=0.2, ao=0.6)


# ---------------------------------------------------------------------------------------------
# frame helpers
# ---------------------------------------------------------------------------------------------
def _frame(normal, up):
    """(right, up, normal) of a surface as align() sees it (viewer looks at the surface)."""
    n = normalize(vec(normal))
    u = vec(up) - n * float(np.dot(vec(up), n))
    if np.linalg.norm(u) < 1e-6:
        u = vec(0, 1, 0) if abs(n[1]) < 0.9 else vec(1, 0, 0)
        u = u - n * float(np.dot(u, n))
    u = normalize(u)
    return np.cross(u, n), u, n


def _require_body(r, what):
    if getattr(r, "current_part", None) is not None:
        raise ValueError(f"{what} is body geometry - call it outside r.part(...)")


# ---------------------------------------------------------------------------------------------
# housing
# ---------------------------------------------------------------------------------------------
def housing(b, mat, w, d, h, z0=0.0, center=(0.0, 0.0), chamfer=0.003, fillet=0.0012, rim=0.0012, dome=0.0, segs=3,
            tag="housing"):
    """Moulded shell: plan outline w (X) x d (Y) with the vertical edges chamfered (45 deg, `chamfer`) and
    every resulting corner filleted (`fillet`), extruded from z0 to z0 + h with rounded top / bottom rims
    (`rim`). dome > 0 bulges the front face (+Y) outward by that much at its centre (soft, moulded look)."""
    poly = chamfer_fillet_rect(w, d, chamfer, fillet, segs)
    if dome > 0:
        g = extrude(poly, h, mat, bevel=rim, bevel_seg=3, z0=z0, mid_rings=10, max_seg=min(w, h) / 14, tag=tag,
                    smooth_angle=50)
        zc, hw, hh = z0 + h / 2, w / 2, h / 2

        def fn(p):
            q = p.copy()
            fy = np.clip(p[:, 1] / (d / 2), 0, 1) ** 3
            fx = np.clip(1 - (p[:, 0] / hw) ** 2, 0, 1)
            fz = np.clip(1 - ((p[:, 2] - zc) / hh) ** 2, 0, 1)
            q[:, 1] = p[:, 1] + dome * fy * fx * fz
            return q
        g.deform(fn)
    else:
        g = extrude(poly, h, mat, bevel=rim, bevel_seg=3, z0=z0, tag=tag, smooth_angle=50)
    # one chart per face (front / back / sides / top / bottom): better packing, and densify() can give the
    # printed front more texels (tags 'housing:side:+y' ...)
    g = split_by_normal(g)
    return g.translate(center[0], center[1], 0)


def housing_frame(w, d, chamfer=0.003, fillet=0.0012, segs=3):
    """The plan outline housing() uses (CCW, metres) - for grooves, bumper layouts, seam rings."""
    return chamfer_fillet_rect(w, d, chamfer, fillet, segs)


def densify(b, k, tags=None, mats=None, part=None):
    """Multiply the texel density of charts already added - by tag prefix (e.g. 'housing:side:+y', the
    printed front of a housing), by material and / or by part id. Prints on those charts get sharper at
    the cost of the rest of the atlas. Returns how many charts changed."""
    n = 0
    for c in b.geo.charts:
        if tags is not None and not any(c.tag.startswith(t) for t in ([tags] if isinstance(tags, str) else tags)):
            continue
        if mats is not None and c.mat not in mats:
            continue
        if part is not None and c.part != part:
            continue
        c.density *= k
        n += 1
    return n


def split_groove_z(r, mats, w, d, z, center=(0.0, 0.0), width=0.0005, depth=0.00025, margin=0.004):
    """Moulded split line running horizontally round the body at height z (decals from +-X and +-Y)."""
    cx, cy = center
    for sx in (1, -1):
        dc = DecalCanvas(d + 2 * margin, 0.004, ppm=6000)
        dc.groove([(0.0, 0.002), (d + 2 * margin, 0.002)], width=width, depth=depth)
        r.decal(dc, center=(cx + sx * w / 2, cy, z), normal=(sx, 0, 0), up=(0, 0, 1), mats=mats, depth=w / 2 + 0.002, min_dot=0.3)
    for sy in (1, -1):
        dc = DecalCanvas(w + 2 * margin, 0.004, ppm=6000)
        dc.groove([(0.0, 0.002), (w + 2 * margin, 0.002)], width=width, depth=depth)
        r.decal(dc, center=(cx, cy + sy * d / 2, z), normal=(0, sy, 0), up=(0, 0, 1), mats=mats, depth=d / 2 + 0.002, min_dot=0.3)


def split_groove_y(r, mats, w, h, zc, y, d, cx=0.0, width=0.0005, depth=0.00025, margin=0.004):
    """Front / rear shell split line at depth y, running over both sides, the top and the bottom."""
    for sx in (1, -1):
        dc = DecalCanvas(d + 2 * margin, h + 2 * margin, ppm=5000)
        xx = (d + 2 * margin) / 2 + y * sx
        dc.groove([(xx, 0.0), (xx, h + 2 * margin)], width=width, depth=depth)
        r.decal(dc, center=(cx + sx * w / 2, 0.0, zc), normal=(sx, 0, 0), up=(0, 0, 1), mats=mats, depth=w / 2 + 0.002, min_dot=0.3)
    for sz in (1, -1):
        dc = DecalCanvas(w + 2 * margin, d + 2 * margin, ppm=5000)
        yy = (d + 2 * margin) / 2 - y * sz
        dc.groove([(0.0, yy), (w + 2 * margin, yy)], width=width, depth=depth)
        r.decal(dc, center=(cx, 0.0, zc + sz * h / 2), normal=(0, 0, sz), up=(0, sz, 0), mats=mats, depth=h / 2 + 0.002, min_dot=0.3)


def overmould_panel(b, mat, at, normal, up, w, h, t=0.0012, corner=None, bevel=None):
    """Raised rubber overmould panel (grip insert) standing `t` proud of the surface: w across, h along up."""
    corner = min(w, h) * 0.3 if corner is None else corner
    bv = min(bevel or t * 0.7, t * 0.9, min(w, h) * 0.3)
    prof = [(0.0, 0.0), (0.0, t - bv)] + [(bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(0.2, math.pi / 2, 4)]
    prof += [(min(w, h) / 2 * 0.6, t)]
    return align(rr_lathe(w, h, corner, prof, mat, n=4, tag="overmould", close=True), normal, up, at)


def battery_pack(b, mat, w, d, h, y_front, z0, gap=0.0006, inset=0.0004, chamfer=0.003, fillet=0.0012, rim=0.0012,
                 center_x=0.0):
    """Rear battery pack shell: the housing outline inset by `inset`, from y_front - gap backwards by d -
    the gap to the front shell reads as a real seam all the way round."""
    g = housing(b, mat, w - 2 * inset, d, h - 2 * inset, z0=z0 + inset, center=(center_x, y_front - gap - d / 2),
                chamfer=max(chamfer - inset, 0.0), fillet=fillet, rim=rim, tag="battery")
    return g


def latch_tab(b, mat, at, normal, up, w=0.012, h=0.006, t=0.0014, ribs=5):
    """Ribbed thumb tab of a battery latch (ribs run across w)."""
    g = rr_lathe(w, h, min(w, h) * 0.3, [(0, 0), (0, t * 0.5), (t * 0.25, t * 0.9), (t * 0.5, t), (min(w, h) / 2 * 0.6, t)], mat,
                 tag="latch", close=True)
    for k in range(ribs):
        y = -h * 0.32 + h * 0.64 * k / max(ribs - 1, 1)
        g += box((w * 0.78, h * 0.06, t * 0.5), mat, r=t * 0.2, seg=1, center=(0, y, t + t * 0.12))
    return align(g, normal, up, at)


def boss(b, mat, at, axis=(0, 0, 1), d=0.014, h=0.003, shaft_d=0.006, shaft_h=0.006, shaft_mat=None, flat=True, front=(0, 1, 0)):
    """Raised knob boss on the top deck + the D-shaft stub a knob sits on (visible on the body model
    once the knob is pulled off)."""
    g = cylinder(d / 2, h, mat, segs=36, bevel=min(0.0008, h * 0.4), caps=(False, True))
    shaft = lathe([(0.0, h), (shaft_d / 2, h), (shaft_d / 2, h + shaft_h - 0.0005), (shaft_d / 2 - 0.0005, h + shaft_h),
                   (0.0, h + shaft_h)], shaft_mat or mat, segs=20, smooth_angle=40)
    if flat:
        lim = shaft_d / 2 - shaft_d * 0.18
        for c in shaft.charts:
            m = c.pos[:, 1] > lim
            c.pos[m, 1] = lim
            c.nrm[m] = normalize(c.nrm[m] * np.array([0.25, 1.0, 0.25]) + np.array([0.0, 2.0, 0.0]))
            c.clean()
    g += shaft
    return align(g, axis, front, at)


def guard_ring(b, mat, at, normal=(0, 0, 1), up=(0, 1, 0), d_in=0.009, d_out=0.014, h=0.003, segs=36):
    """Raised ring guarding a button (emergency key in a guard)."""
    ri, ro = d_in / 2, d_out / 2
    bv = min(0.0006, (ro - ri) * 0.3)
    prof = [(ri, 0.0), (ro, 0.0), (ro, h - bv), (ro - bv * 0.3, h - bv * 0.3), (ro - bv, h), (ri + bv, h), (ri + bv * 0.3, h - bv * 0.3),
            (ri, h - bv), (ri, 0.0)]
    return align(lathe(prof, mat, segs=segs, smooth_angle=50, tag="guard"), normal, up, at)


def wells(r, mat, center, normal, up, size, t, holes, depth=None, floor_mat=None, wall_mat=None, bevel=0.0004,
          hole_bevel=0.0003, corner_n=4):
    """Body plate (keypad surround, bezel, button pocket) standing `t` proud of the surface at `center`,
    with openings that fall into wells. holes: [(x, y, hw, hh, r)] in the plate's own frame (x = viewer's
    right, y = up, origin = center). Returns the Geo (already added to the body)."""
    _require_body(r, "wells()")
    g = well_plate(size[0], size[1], t, holes, mat, depth=depth, floor_mat=floor_mat, wall_mat=wall_mat, bevel=bevel,
                   hole_bevel=hole_bevel, corner_n=corner_n, tag="wells")
    g = align(g, normal, up, center)
    r.add(g)
    return g


def well_for(r, mat, at, normal, up, size, gap=0.0005, margin=0.0012, t=0.0012, corner=None, depth=None, floor_mat=None):
    """A single-opening bezel for one part: opening = size + 2 gap, plate = opening + 2 margin. `at` is the
    centre of the bezel's bottom on the surface. Returns the z (along normal) of the well floor relative to
    `at` - stand the part there."""
    hw, hh = size[0] / 2 + gap, size[1] / 2 + gap
    cr = min(hw, hh) * 0.35 if corner is None else min(corner + gap, hw, hh)
    dep = t if depth is None else depth
    wells(r, mat, at, normal, up, (2 * (hw + margin), 2 * (hh + margin)), t, [(0.0, 0.0, hw, hh, cr)], depth=dep, floor_mat=floor_mat)
    return t - dep


# ---------------------------------------------------------------------------------------------
# keys and buttons (parts)
# ---------------------------------------------------------------------------------------------
def key_cap(mat, w, h, t, corner=None, dome=0.00025, bevel=None, n=4):
    """Rubber / plastic key cap standing on z = 0 facing +Z: rounded-rectangle plan, bevelled top rim and
    a slight dome (top centre at z = t + dome). round when corner >= min(w, h) / 2."""
    corner = min(w, h) * 0.28 if corner is None else min(corner, min(w, h) / 2)
    bv = min(bevel if bevel is not None else 0.0006, t * 0.45, min(w, h) * 0.25)
    hm = min(w, h) / 2
    prof = [(0.0, 0.0), (0.0, t - bv)]
    prof += [(bv * (1 - math.cos(a)), t - bv + bv * math.sin(a)) for a in np.linspace(math.pi / 8, math.pi / 2, 4)]
    for f in (0.22, 0.45, 0.66):
        prof.append((bv + (hm - bv) * f, t))
    ax, ay = max(w / 2 - bv, 1e-6), max(h / 2 - bv, 1e-6)

    def dome_fn(x, y):
        # pillow dome: t at the bevel line, t + dome in the middle, smooth everywhere
        u, v = np.clip(x / ax, -1, 1), np.clip(y / ay, -1, 1)
        fu, fv = 1 - u * u, 1 - v * v
        return t + dome * fu * fv, dome * (-2 * u / ax) * fv, dome * fu * (-2 * v / ay)
    return rr_lathe(w, h, corner, prof, mat, n=n, tag="cap", top_fn=dome_fn if dome > 0 else None, close=True)


def legend_canvas(w, h, legend=None, sub=None, glyph=None, color="white", sub_color=None, size=None, layout="row",
                  font="label", sub_font="label-semi", ppm=None, glyph_color=None):
    """Legend for a key top of w x h metres. layout 'row': big legend left, small sub legend right
    ("2 ABC"); 'stack': big legend top, sub below; 'center': legend only. glyph: a DecalCanvas.glyph
    kind drawn left of the legend (or centred when there is no legend)."""
    ppm = ppm or max(9000, int(260 / max(w, 1e-4)))
    dc = DecalCanvas(w, h, ppm)
    ik = ink(color)
    sk = ink(sub_color or color)
    gk = ink(glyph_color or color)
    hs = size or h * 0.56
    if legend is None and sub is None and glyph:
        dc.glyph(glyph, w / 2, h / 2, hs, **gk)
        return dc
    if glyph and legend:
        dc.glyph(glyph, w * 0.3, h / 2, hs * 0.85, **gk)
        dc.text(w * 0.66, h / 2, legend, hs * 0.72, fnt=font, max_w=w * 0.42, **ik)
        return dc
    if sub and layout == "row":
        dc.text(w * 0.34, h / 2, legend or "", hs, fnt=font, max_w=w * 0.42, **ik)
        dc.text(w * 0.72, h * 0.54, sub, hs * 0.5, fnt=sub_font, max_w=w * 0.46, **sk)
    elif sub and layout == "stack":
        dc.text(w / 2, h * 0.38, legend or "", hs * 0.9, fnt=font, max_w=w * 0.86, **ik)
        dc.text(w / 2, h * 0.78, sub, hs * 0.42, fnt=sub_font, max_w=w * 0.86, **sk)
    else:
        dc.text(w / 2, h / 2, legend or sub or "", hs, fnt=font, max_w=w * 0.86, **ik)
    return dc


def key(r, pid, at, normal=(0, 1, 0), up=(0, 0, 1), size=(0.011, 0.0065), t=0.002, mat=None, corner=None, dome=0.00025,
        bevel=None, legend=None, sub=None, glyph=None, color="white", sub_color=None, glyph_color=None, legend_size=None,
        layout="row", depth=0.0014, action=None, value=None, shape=None, canvas=None, font="label"):
    """A pressable key: the cap stands on `at` (centre of its base on the well floor / surface), facing
    `normal`; size = (across, along up). Legend printed on the cap top (or pass a ready `canvas`). Adds the
    part with metadata (press = -normal, u / v = half extents of the cap face) and returns its origin
    (cap top centre = the part model's origin)."""
    mat = mat or m_keypad_rubber(r)
    w, h = size
    right, upv, n = _frame(normal, up)
    corner = min(w, h) * 0.28 if corner is None else corner
    origin = vec(at) + n * (t + dome)
    shape = shape or ("round" if corner >= min(w, h) / 2 - 1e-6 else "rect")
    with r.part(pid, origin=origin, press=-n, depth=depth, u=right * w / 2, v=upv * h / 2, shape=shape, action=action, value=value):
        r.add(align(key_cap(mat, w, h, t, corner, dome, bevel), n, upv, at))
        cv = canvas
        if cv is None and (legend or sub or glyph):
            cv = legend_canvas(w * 0.92, h * 0.9, legend, sub, glyph, color, sub_color, legend_size, layout, font=font,
                               glyph_color=glyph_color)
        if cv is not None:
            r.decal(cv, center=origin, normal=n, up=upv, depth=dome + 0.0012, min_dot=0.55)
    return origin


def keypad(r, layout, center, normal=(0, 1, 0), up=(0, 0, 1), pitch=(0.0135, 0.0085), size=(0.011, 0.0065), t=0.002,
           plate=True, plate_t=0.0012, margin=0.0016, gap=0.0005, well_depth=None, plate_mat=None, key_mat=None, floor_mat=None,
           color="white", sub_color=None, **key_kw):
    """A grid of keys in wells. layout: rows top to bottom, each a list of cells: None (empty) or
    (pid, legend, sub) / (pid, legend, sub, {extra key() kwargs}) / {"pid": ..., "legend": ..., ...}.
    center: centre of the keypad on the housing surface. With plate=True a surround plate (plate_t thick,
    proud of the surface) holds one well per key (key + gap all round). Returns {pid: origin}."""
    right, upv, n = _frame(normal, up)
    rows = len(layout)
    cols = max(len(rw) for rw in layout)
    px, py = pitch
    cells = []
    for ri, rw in enumerate(layout):
        for ci, cell in enumerate(rw):
            if cell is None:
                continue
            if isinstance(cell, dict):
                spec = dict(cell)
            else:
                spec = {"pid": cell[0], "legend": cell[1] if len(cell) > 1 else None, "sub": cell[2] if len(cell) > 2 else None}
                if len(cell) > 3:
                    spec.update(cell[3])
            x = (ci - (cols - 1) / 2) * px
            y = ((rows - 1) / 2 - ri) * py
            cells.append((x, y, spec))
    dep = plate_t if well_depth is None else well_depth
    base_lift = 0.0
    if plate:
        holes = []
        for x, y, spec in cells:
            w, h = spec.get("size", size)
            cr = spec.get("corner", min(w, h) * 0.28)
            holes.append((x, y, w / 2 + gap, h / 2 + gap, min(cr + gap, w / 2 + gap, h / 2 + gap)))
        xs = [abs(hh[0]) + hh[2] for hh in holes]
        ys = [abs(hh[1]) + hh[3] for hh in holes]
        pw = 2 * (max(xs) + margin + 0.0003)
        ph = 2 * (max(ys) + margin + 0.0003)
        wells(r, plate_mat or m_soft_black(r), center, n, upv, (pw, ph), plate_t, holes, depth=dep, floor_mat=floor_mat)
        base_lift = plate_t - dep
    out = {}
    for x, y, spec in cells:
        kw = dict(key_kw)
        kw.update({k: v for k, v in spec.items() if k not in ("pid",)})
        kw.setdefault("size", size)
        kw.setdefault("t", t)
        kw.setdefault("mat", key_mat)
        kw.setdefault("color", color)
        kw.setdefault("sub_color", sub_color)
        at = vec(center) + n * base_lift + right * x + upv * y
        out[spec["pid"]] = key(r, spec["pid"], at, n, upv, **kw)
    return out


def dpad(r, pid="dpad", at=(0, 0, 0), normal=(0, 1, 0), up=(0, 0, 1), size=0.016, kind="diamond", t=0.0024, mat=None,
         arrows="print", arrow_color="white", tilt=5.0, depth=0.0010, dome=0.0004, center_mark=False, action=None):
    """Four-way rocker. kind 'diamond' (rounded square turned 45 deg, `size` = tip to tip), 'round' (disc,
    `size` = diameter) or 'square' (rounded square). arrows 'print' (triangles printed near the edges),
    'ridge' (raised arrow ridges) or None. The part is 'round' for the hit test (u / v = size / 2) and the
    client resolves up / down / left / right from the hit point. Returns the origin."""
    mat = mat or m_keypad_rubber(r)
    right, upv, n = _frame(normal, up)
    if kind == "diamond":
        side = size / math.sqrt(2)
        cap = key_cap(mat, side, side, t, corner=side * 0.22, dome=dome).rotate(0, 0, 45)
    elif kind == "round":
        cap = key_cap(mat, size, size, t, corner=size / 2, dome=dome)
    else:
        cap = key_cap(mat, size, size, t, corner=size * 0.2, dome=dome)
    origin = vec(at) + n * (t + dome)
    with r.part(pid, origin=origin, press=-n, depth=depth, u=right * size / 2, v=upv * size / 2, shape="round",
                action=action or "dpad", tilt=tilt):
        g = cap
        if arrows == "ridge":
            for ang in (0, 90, 180, 270):
                tri_ = np.array([(0.0, size * 0.36), (size * 0.075, size * 0.25), (-size * 0.075, size * 0.25)])
                rg = extrude(tri_, 0.0005, mat, bevel=0.00015, bevel_seg=1, z0=t + dome * 0.5).rotate(0, 0, ang)
                g = g + rg
        r.add(align(g, n, upv, at))
        if arrows == "print":
            dc = DecalCanvas(size, size, ppm=max(9000, int(300 / size)))
            for k_, (gx, gy) in (("up", (0.5, 0.2)), ("down", (0.5, 0.8)), ("left", (0.2, 0.5)), ("right", (0.8, 0.5))):
                dc.glyph(k_, size * gx, size * gy, size * 0.16, **ink(arrow_color))
            if center_mark:
                dc.circle(size / 2, size / 2, size * 0.06, fill=False, width=size * 0.015, **ink(arrow_color))
            r.decal(dc, center=origin, normal=n, up=upv, depth=dome + 0.0015, min_dot=0.5)
    return origin


def round_button(r, pid, at, normal, up=(0, 0, 1), d=0.006, t=0.0015, mat=None, legend=None, glyph=None, color="white",
                 depth=0.0010, action=None, value=None, dome=0.0002):
    """Round push button (side keys, monitor key): cap stands on `at`. Returns the origin."""
    return key(r, pid, at, normal, up, size=(d, d), t=t, mat=mat, corner=d / 2, dome=dome, legend=legend, glyph=glyph,
               color=color, layout="center", depth=depth, action=action, value=value, shape="round")


def ptt(r, pid="ptt", at=(0, 0, 0), normal=(1, 0, 0), up=(0, 0, 1), length=0.030, width=0.012, t=0.0025, ridges=5,
        ridge_h=0.00045, mat=None, emboss="PTT", depth=0.0016, corner=None, dome=0.0005, ridge_span=0.62):
    """Ridged push-to-talk rocker on a side: `length` along up, `width` across, cap standing on `at`
    (base centre). Horizontal ridges across the upper part, "PTT" embossed (raised, unprinted) below.
    Returns the origin."""
    mat = mat or m_keypad_rubber(r)
    right, upv, n = _frame(normal, up)
    corner = min(length, width) * 0.42 if corner is None else corner
    origin = vec(at) + n * (t + dome)
    with r.part(pid, origin=origin, press=-n, depth=depth, u=right * width / 2, v=upv * length / 2, shape="rect", action="ptt"):
        g = key_cap(mat, width, length, t, corner, dome, bevel=min(0.0009, t * 0.4))
        top = length * 0.5 - length * 0.12
        for k in range(ridges):
            y = top - (length * ridge_span) * k / max(ridges - 1, 1)
            g += box((width * 0.74, length * 0.035, ridge_h * 2.2), mat, r=ridge_h * 0.95, seg=1,
                     center=(0, y, t + dome * 0.8 - ridge_h * 0.1), faces="+x -x +y -y +z")
        r.add(align(g, n, upv, at))
        if emboss:
            dc = DecalCanvas(width * 0.9, length * 0.22, ppm=max(9000, int(300 / width)))
            dc.text(width * 0.45, length * 0.11, emboss, length * 0.09, fnt="label", spacing=length * 0.008, height=0.00012,
                    spec=0.28, gloss=0.42)
            y_txt = -length * 0.5 + length * 0.17
            r.decal(dc, center=origin - n * dome * 0.3 + upv * y_txt, normal=n, up=upv, depth=0.0015, min_dot=0.5)
    return origin


def ptt_guard(b, mat, at, normal=(1, 0, 0), up=(0, 0, 1), length=0.034, rib_h=0.003, rib_w=0.003, span=None):
    """Two raised guard ribs above and below a PTT (body geometry, military style). `at` = PTT base centre."""
    right, upv, n = _frame(normal, up)
    span = span or length + rib_w + 0.002
    g = Geo()
    for s in (1, -1):
        g += box((0.016, rib_w, rib_h), mat, r=min(rib_w, rib_h) * 0.4, seg=2, center=(0, s * span / 2, rib_h / 2))
    return align(g, n, upv, at)


# ---------------------------------------------------------------------------------------------
# knobs (parts)
# ---------------------------------------------------------------------------------------------
def _knob_geo(mat, cap_mat, d, h, style, ribs, rib_depth, skirt, skirt_d, skirt_h, dome, segs):
    R = d / 2
    Rs = (skirt_d or d * 1.18) / 2
    sh = skirt_h if skirt_h is not None else (h * 0.14 if skirt else 0.0)
    bev = min(0.0008, R * 0.15, h * 0.12)
    # the underside sits on the boss / deck and is never seen: the profile starts at the outer rim
    if skirt and sh > 0:
        prof = [(Rs * 0.92, 0.0), (Rs, sh * 0.25), (Rs, sh * 0.6), (R, sh)]
    else:
        prof = [(R * 0.92, 0.0), (R, 0.0003)]
    band0 = prof[-1][1]
    prof += [(R, band0 + 0.0004), (R, h - bev - 0.0004), (R, h - bev), (R - bev, h)]
    body = lathe(prof, mat, segs=segs, smooth_angle=40, tag="knob")
    top = lathe([(R - bev, h), (R * 0.55, h + dome * 0.7), (0.0, h + dome)], cap_mat, segs=segs, smooth_angle=60, tag="knobtop")
    if style == "ribbed" and ribs > 0:
        rd = rib_depth if rib_depth is not None else R * 0.07
        z_a, z_b = band0, h - bev

        def fn(p):
            q = p.copy()
            rr = np.hypot(p[:, 0], p[:, 1])
            ph = np.arctan2(p[:, 1], p[:, 0])
            ramp = np.clip((p[:, 2] - z_a) / 0.0004, 0, 1) * np.clip((z_b - p[:, 2]) / 0.0004, 0, 1)
            groove = np.clip(np.cos(ribs * ph), 0, 1) ** 6
            k = 1 - (rd / np.maximum(rr, 1e-6)) * groove * ramp * (rr > R * 0.9)
            q[:, 0] = p[:, 0] * k
            q[:, 1] = p[:, 1] * k
            return q
        body.deform(fn)
    return body + top


def knob(r, pid, base, axis=(0, 0, 1), front=(0, 1, 0), d=0.012, h=0.014, style="ribbed", ribs=16, rib_depth=None,
         skirt=True, skirt_d=None, skirt_h=None, mat=None, cap_mat=None, index="line", index_color="white", value="channel",
         detents=16, depth=0.0008, dome=0.0004, segs=None):
    """Rotary knob standing on `base` (centre of its underside) along `axis`. style 'ribbed' (geometric
    vertical ribs - silhouette), 'knurled' (diamond knurl in the normal map) or 'smooth'. A flange skirt at
    the base, a domed top, an index mark ('line' from the centre to the edge facing `front`, 'dot', None).
    The part origin is on the axis at half height (the client rotates about `axis` through it); u / v span
    the knob's silhouette seen from `front`. Returns the origin."""
    if style == "knurled":
        mat = mat or r.mat("knob_knurl", color=(30, 31, 34), spec=0.26, gloss=0.38, bump="knurl", bump_amp=0.00012,
                           bump_scale=0.0009, grain=0.03, edge=0.5, dirt=0.15, wear_color=(80, 82, 86))
    else:
        mat = mat or r.mat("knob_black", color=(28, 29, 32), spec=0.24, gloss=0.36, bump="stipple", bump_amp=0.00002,
                           bump_scale=0.0004, grain=0.03, edge=0.55, dirt=0.15, wear_color=(84, 86, 90))
    cap_mat = cap_mat or mat
    ax = normalize(vec(axis))
    fr = vec(front) - ax * float(np.dot(vec(front), ax))
    fr = normalize(fr)
    right = normalize(np.cross(fr, ax))
    segs = segs or (max(48, ribs * 4) if style == "ribbed" else 40)
    origin = vec(base) + ax * (h / 2)
    with r.part(pid, origin=origin, press=-ax, depth=depth, u=right * d / 2, v=ax * h / 2, shape="rect", action="knob",
                value=value, axis=ax, detents=detents):
        g = _knob_geo(mat, cap_mat, d, h, style, ribs, rib_depth, skirt, skirt_d, skirt_h, dome, segs)
        r.add(align(g, ax, fr, base))
        top_c = vec(base) + ax * (h + dome)
        if index == "line":
            dc = DecalCanvas(d, d, ppm=max(9000, int(300 / d)))
            dc.rect(d / 2 - d * 0.035, d * 0.06, d * 0.07, d * 0.36, r=d * 0.02, **ink(index_color))
            r.decal(dc, center=top_c, normal=ax, up=fr, depth=dome + 0.002, min_dot=0.3)
            side = DecalCanvas(d * 0.2, h, ppm=max(9000, int(300 / d)))
            side.rect(d * 0.07, h * 0.16, d * 0.06, h * 0.62, r=d * 0.02, **ink(index_color))
            r.decal(side, center=vec(base) + ax * (h * 0.55) + fr * (d / 2), normal=fr, up=ax, depth=d * 0.12, min_dot=0.5)
        elif index == "dot":
            dc = DecalCanvas(d, d, ppm=max(9000, int(300 / d)))
            dc.circle(d / 2, d * 0.2, d * 0.07, **ink(index_color))
            r.decal(dc, center=top_c, normal=ax, up=fr, depth=dome + 0.002, min_dot=0.3)
    return origin


def knob_pair(r, outer_id, inner_id, base, axis=(0, 0, 1), front=(0, 1, 0), d_outer=0.014, h_outer=0.008, d_inner=0.009,
              h_inner=0.007, gap=0.0004, outer_mat=None, inner_mat=None, index_color="white", outer_value="channel",
              inner_value="volume", outer_detents=16, inner_detents=24, depth=0.0008):
    """Concentric dual knob: an outer knurled ring (outer_id) and an inner cap on the same axis standing
    above it (inner_id) - two separate part models. Returns (outer origin, inner origin)."""
    ax = normalize(vec(axis))
    fr = normalize(vec(front) - ax * float(np.dot(vec(front), ax)))
    right = normalize(np.cross(fr, ax))
    om = outer_mat or r.mat("knob_ring", color=(34, 35, 38), spec=0.3, gloss=0.4, bump="knurl", bump_amp=0.00012,
                            bump_scale=0.0009, grain=0.03, edge=0.5, dirt=0.15, wear_color=(90, 92, 96))
    im = inner_mat or r.mat("knob_cap", color=(28, 29, 32), spec=0.26, gloss=0.38, bump="knurl", bump_amp=0.00008,
                            bump_scale=0.0007, grain=0.03, edge=0.5, dirt=0.12, wear_color=(84, 86, 90))
    Ro, ri = d_outer / 2, d_inner / 2 + gap
    bv = min(0.0007, (Ro - ri) * 0.3)
    o_origin = vec(base) + ax * (h_outer / 2)
    with r.part(outer_id, origin=o_origin, press=-ax, depth=depth, u=right * Ro, v=ax * h_outer / 2, shape="rect", action="knob",
                value=outer_value, axis=ax, detents=outer_detents):
        prof = [(ri, 0.0), (Ro, 0.0), (Ro, h_outer - bv), (Ro - bv * 0.3, h_outer - bv * 0.3), (Ro - bv, h_outer),
                (ri + bv * 0.5, h_outer), (ri, h_outer - bv * 0.5), (ri, 0.0)]
        r.add(align(lathe(prof, om, segs=48, smooth_angle=45, tag="knobring"), ax, fr, base))
        dc = DecalCanvas(d_outer, d_outer, ppm=max(9000, int(300 / d_outer)))
        dc.rect(d_outer / 2 - d_outer * 0.03, d_outer * 0.02, d_outer * 0.06, (Ro - ri) * 0.8, r=d_outer * 0.015, **ink(index_color))
        r.decal(dc, center=vec(base) + ax * h_outer, normal=ax, up=fr, depth=0.0015, min_dot=0.4)
    i_base = vec(base) + ax * (h_outer - 0.0015)
    hi = h_inner + 0.0015
    i_origin = vec(base) + ax * (h_outer + h_inner / 2)
    with r.part(inner_id, origin=i_origin, press=-ax, depth=depth, u=right * d_inner / 2, v=ax * h_inner / 2, shape="rect",
                action="knob", value=inner_value, axis=ax, detents=inner_detents):
        g = _knob_geo(im, im, d_inner, hi, "knurled", 0, None, False, None, None, 0.0003, 40)
        r.add(align(g, ax, fr, i_base))
        dc = DecalCanvas(d_inner, d_inner, ppm=max(9000, int(300 / d_inner)))
        dc.circle(d_inner / 2, d_inner * 0.2, d_inner * 0.075, **ink(index_color))
        r.decal(dc, center=i_base + ax * (hi + 0.0003), normal=ax, up=fr, depth=0.0015, min_dot=0.3)
    return o_origin, i_origin


# ---------------------------------------------------------------------------------------------
# antennas (charts tagged 'antenna...': the kit wraps them in a collision cylinder)
# ---------------------------------------------------------------------------------------------
def whip_antenna(b, base, length=0.155, d0=0.009, d1=0.006, mat=None, collar_h=0.012, collar_ribs=4, cap="round", segs=20,
                 axis=(0, 0, 1)):
    """Flexible whip: ribbed collar at the base, tapering body d0 -> d1, rounded cap or ball tip."""
    mat = mat or b.mat("antenna_rubber", color=(24, 25, 27), spec=0.2, gloss=0.32, bump="rubber", bump_amp=0.00003,
                       bump_scale=0.0006, grain=0.03, grain_scale=0.02, edge=0.3, dirt=0.12, wear_color=(66, 68, 72))
    R0, R1 = d0 / 2, d1 / 2
    prof = [(0.0, 0.0), (R0 * 1.06, 0.0)]
    for k in range(collar_ribs):
        z0 = collar_h * (k + 0.15) / collar_ribs
        z1 = collar_h * (k + 0.75) / collar_ribs
        prof += [(R0 * 1.06, z0), (R0 * 1.14, z0 + 0.0004), (R0 * 1.14, z1 - 0.0004), (R0 * 1.06, z1)]
    prof += [(R0, collar_h), (R0 * 0.97, collar_h + 0.004)]
    body_len = length - collar_h
    for f in np.linspace(0.12, 0.92, 6):
        prof.append((R0 * 0.97 + (R1 - R0 * 0.97) * f, collar_h + body_len * f))
    if cap == "ball":
        rb = R1 * 1.45
        zc = length - rb
        prof.append((R1, zc - rb * 0.6))
        for a in np.linspace(-math.pi / 2 + 0.5, math.pi / 2, 7):
            prof.append((rb * math.cos(a), zc + rb * math.sin(a)))
    else:
        zc = length - R1
        for a in np.linspace(0, math.pi / 2, 6):
            prof.append((R1 * math.cos(a), zc + R1 * math.sin(a)))
    prof[-1] = (0.0, prof[-1][1])
    g = lathe(prof, mat, segs=segs, smooth_angle=50, tag="antenna_whip")
    return align(g, axis, (0, 1, 0) if abs(vec(axis)[1]) < 0.9 else (1, 0, 0), base)


def rubber_duck(b, base, length=0.085, d=0.011, mat=None, band=(0.012, 0.004, (226, 184, 36)), boot_h=0.014, segs=24,
                axis=(0, 0, 1)):
    """Chunky rubber-duck antenna: ribbed boot, body with a slight taper, rounded tip and an optional
    coloured band (distance of its top below the tip, width, colour)."""
    mat = mat or b.mat("duck_rubber", color=(22, 23, 25), spec=0.16, gloss=0.26, bump="rubber", bump_amp=0.00004,
                       bump_scale=0.0007, grain=0.03, edge=0.3, dirt=0.15, wear_color=(66, 68, 72))
    R = d / 2
    tipR = R * 0.92
    g = Geo()
    prof = [(0.0, 0.0), (R * 1.12, 0.0)]
    for k in range(3):
        z0 = boot_h * (k + 0.2) / 3
        prof += [(R * 1.12, z0), (R * 1.2, z0 + 0.0006), (R * 1.2, z0 + boot_h / 3 * 0.55), (R * 1.12, z0 + boot_h / 3 * 0.7)]
    prof += [(R * 1.04, boot_h), (R, boot_h + 0.003)]
    zb1 = length - (band[0] if band else 0) if band else None
    zb0 = zb1 - band[1] if band else None
    zt = length - tipR

    def rad(z):
        f = (z - boot_h) / max(zt - boot_h, 1e-6)
        return R + (tipR - R) * f
    if band:
        prof += [(rad(zb0), zb0)]
        g += lathe(prof, mat, segs=segs, smooth_angle=50, tag="antenna_duck")
        bm = b.mat(f"duck_band_{band[2][0]}_{band[2][1]}_{band[2][2]}", color=band[2], spec=0.3, gloss=0.45, grain=0.02, edge=0.3,
                   dirt=0.2)
        g += lathe([(rad(zb0), zb0), (rad(zb0) + 0.00012, zb0 + 0.0002), (rad(zb1) + 0.00012, zb1 - 0.0002), (rad(zb1), zb1)], bm,
                   segs=segs, smooth_angle=60, tag="antenna_band")
        top = [(rad(zb1), zb1)]
    else:
        top = prof
    top += [(rad(zt), zt)] + [(tipR * math.cos(a), zt + tipR * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 5)]
    top[-1] = (0.0, top[-1][1])
    g += lathe(top, mat, segs=segs, smooth_angle=50, tag="antenna_duck")
    return align(g, axis, (0, 1, 0) if abs(vec(axis)[1]) < 0.9 else (1, 0, 0), base)


def sma_nut(b, at, axis=(0, 0, 1), across=0.008, h=0.004, finish="nickel", barrel_h=0.003, front=(0, 1, 0)):
    """Hex antenna nut (`across` flats) with a threaded barrel stub above it."""
    m = m_sma(b, finish)
    r_hex = across / 2 / math.cos(math.radians(30))
    hexp = np.array([(r_hex * math.cos(math.radians(60 * k)), r_hex * math.sin(math.radians(60 * k))) for k in range(6)])
    g = extrude(hexp, h, m, bevel=min(0.0005, h * 0.2), bevel_seg=1, smooth_angle=20, tag="antenna_nut")
    thr = b.mat(f"sma_thread_{finish}", color=b.mats[m].color, spec=0.8, gloss=0.6, metal=1.0, bump="ribs", bump_amp=0.00008,
                bump_scale=0.0005, edge=0.3)
    g += cylinder(across * 0.38, barrel_h, thr, segs=20, bevel=0.0003, z0=h, tag="antenna_thread")
    return align(g, axis, front, at)


def gooseneck(b, base, length=0.04, coil_r=0.0045, wire_r=0.0011, mat=None, axis=(0, 0, 1), n_per_turn=14, segs=6,
              core_mat=None):
    """Coil-spring gooseneck: a close-wound wire helix (sweep along helix) over a dark core."""
    mat = mat or b.mat("coil_steel", color=(40, 41, 44), spec=0.7, gloss=0.55, metal=1.0, edge=0.5, dirt=0.15,
                       wear_color=(150, 152, 156))
    pitch = wire_r * 2.15
    turns = max(1.0, (length - wire_r * 2) / pitch)
    ax = normalize(vec(axis))
    pts = helix(vec(base) + ax * wire_r, ax, coil_r, pitch, turns, n_per_turn)
    g = tube(pts, wire_r, mat, segs=segs, split=0.06, tag="antenna_coil")
    core = cylinder(coil_r - wire_r * 0.6, length, core_mat or b.mat("coil_core", color=(14, 15, 16), spec=0.2, gloss=0.3),
                    segs=16, caps=(False, True), tag="antenna_core")
    g += align(core, ax, (0, 1, 0) if abs(ax[1]) < 0.9 else (1, 0, 0), base)
    return g


# ---------------------------------------------------------------------------------------------
# speaker, light pipe, clips, contacts, connectors
# ---------------------------------------------------------------------------------------------
def speaker_bars(b, center, normal=(0, 1, 0), up=(0, 0, 1), w=0.044, h=0.026, n=4, bar_h=None, bar_t=0.0012, mat=None,
                 mesh_mat=None, margin=0.0):
    """Speaker grille of n raised rounded horizontal bars over a dark acoustic mesh panel (the mesh
    shows in the gaps). `center` is on the housing surface."""
    mat = mat or m_soft_black(b)
    mesh_mat = mesh_mat or m_mesh(b)
    bar_h = bar_h or h / (n * 1.65)
    g = Geo()
    g += box((w, h, 0.0003), mesh_mat, r=0.0001, seg=1, center=(0, 0, 0.00015), faces="+z")
    gap = (h - n * bar_h) / max(n - 1, 1)
    for k in range(n):
        y = h / 2 - bar_h / 2 - k * (bar_h + gap)
        g += box((w - 2 * margin, bar_h, bar_t * 2), mat, r=min(bar_h, bar_t) * 0.48, seg=3, center=(0, y, 0.0))
    return align(g, normal, up, center)


def grille_holes(b, center, normal=(0, 1, 0), up=(0, 0, 1), cols=11, rows=9, pitch=0.002, hole_r=0.00045, t=0.0006,
                 depth=None, margin=0.0012, mat=None, floor_mat=None, corner_n=2):
    """A plate (t proud of the surface) with a real round hole matrix falling into dark wells. Costs ~40
    triangles per hole: past ~60 holes prefer perforation_decal()."""
    mat = mat or m_soft_black(b)
    holes = []
    for j in range(rows):
        for i in range(cols):
            holes.append(((i - (cols - 1) / 2) * pitch, ((rows - 1) / 2 - j) * pitch, hole_r, hole_r, hole_r))
    w = (cols - 1) * pitch + 2 * hole_r + 2 * margin
    h = (rows - 1) * pitch + 2 * hole_r + 2 * margin
    g = well_plate(w, h, t, holes, mat, depth=depth, floor_mat=floor_mat or m_mesh(b), bevel=min(0.0003, t * 0.4), hole_bevel=0.0,
                   corner_n=corner_n, tag="grille")
    return align(g, normal, up, center)


def light_pipe(b, at, normal=(0, 0, 1), up=(0, 1, 0), d=0.003, color="red", bezel_mat=None, bezel_h=0.0004):
    """Light-pipe socket: a thin raised bezel ring + recessed, unlit tinted lens. Returns (Geo, insert
    point) - the insert point is where an LED insert model (nzr_led_*) sits (leds.tx / leds.rx)."""
    bezel_mat = bezel_mat or b.mat("pipe_bezel", color=(16, 17, 19), spec=0.4, gloss=0.55, edge=0.4)
    rl = d / 2
    ro = rl + 0.0007
    g = lathe([(rl, -0.0004), (rl, bezel_h * 0.5), (rl + 0.0002, bezel_h), (ro - 0.0002, bezel_h), (ro, bezel_h * 0.5), (ro, 0.0)],
              bezel_mat, segs=24, smooth_angle=50, tag="pipe")
    g += cylinder(rl, 0.0001, m_led_off(b, color), segs=20, z0=-0.0003, caps=(False, True), tag="pipe_lens")
    _, _, n = _frame(normal, up)
    return align(g, normal, up, at), (vec(at) - n * 0.0002)


def led_dome(b, color="red", d=0.003, h=None, base_h=0.0003):
    """LED insert model geometry (nzr_led_red / _green / _amber): a small emissive dome lens on a thin
    dark collar, origin at the lens base, facing +Z - it sits on a light_pipe() insert point. Build it
    in a plain @prop and attach it to the body at layout leds.tx / leds.rx."""
    h = h if h is not None else d * 0.45
    R = d / 2
    lens = m_led_lens(b, color)
    g = cylinder(R * 1.05, base_h, b.mat("led_collar", color=(14, 15, 16), spec=0.4, gloss=0.5), segs=20, caps=(False, True))
    prof = [(R, base_h)] + [(R * math.cos(a), base_h + h * math.sin(a)) for a in np.linspace(0.15, math.pi / 2, 6)]
    prof[-1] = (0.0, prof[-1][1])
    g += lathe(prof, lens, segs=20, smooth_angle=60, tag="led")
    return g


def belt_clip(b, top, normal=(0, -1, 0), up=(0, 0, 1), w=0.032, length=0.07, t=0.002, standoff=0.0035, lip=0.008, mat=None,
              block_mat=None, screws_n=2, screw_kind="phillips"):
    """Spring-steel belt clip on the back: a mount block at `top` (on the back surface), the plate running
    down `length` at `standoff` from the surface and a bent lip at the bottom, held by screws."""
    mat = mat or m_spring_steel(b)
    block_mat = block_mat or m_soft_black(b)
    right, upv, n = _frame(normal, up)
    path = [(0.0, 0.004, 0.0), (0.0, 0.0, standoff), (0.0, -length * 0.5, standoff + 0.0006), (0.0, -length + lip * 0.6, standoff),
            (0.0, -length, standoff + lip * 0.55)]
    P = polyline_fillet(np.asarray(path), 0.004, 6)
    plate = sweep(rrect(w, t, t * 0.45, 2), P, mat, side=(1, 0, 0), tag="clip", smooth_angle=55)
    g = Geo()
    g += plate
    g += box((w + 0.004, 0.012, standoff + 0.0005), block_mat, r=0.0012, seg=2, center=(0, 0.002, (standoff + 0.0005) / 2))
    out = align(g, n, upv, top)
    for k in range(screws_n):
        x = (k - (screws_n - 1) / 2) * (w * 0.5)
        p = vec(top) + right * x + upv * (-0.003) + n * (standoff + t * 0.5 + 0.0001)
        out += screw(b, p, n, upv, d=0.0042, kind=screw_kind, segs=12)
    return out


def lanyard_eye(b, at, normal, up=(0, 0, 1), r=0.0032, wire=0.0011, mat=None):
    """Moulded lanyard eye: a half loop standing out of the surface (moulded into a bottom corner)."""
    mat = mat or m_soft_black(b)
    pts = np.array([(r * math.cos(a), 0.0, r * math.sin(a)) for a in np.linspace(0, math.pi, 13)])
    pts[:, 2] = pts[:, 2] * 1.1
    g = tube(pts, wire, mat, segs=10, tag="eye")
    g += box((2 * r + 2 * wire, 2.4 * wire, wire), mat, r=wire * 0.4, seg=1, center=(0, 0, wire * 0.2))
    return align(g, normal, up, at)


def charging_contacts(b, center, normal=(0, 0, -1), up=(0, 1, 0), n=2, pitch=0.008, size=(0.004, 0.0025), proud=0.0002):
    """Gold charging contacts: rounded pads standing `proud` of the surface, n in a row along right."""
    m = m_contact_gold(b)
    g = Geo()
    for k in range(n):
        x = (k - (n - 1) / 2) * pitch
        g += box((size[0], size[1], proud * 2), m, r=proud * 0.9, seg=1, center=(x, 0, 0))
    return align(g, normal, up, center)


def thumbscrew(b, at, normal, up=(0, 0, 1), d=0.006, h=0.003, mat=None):
    """Knurled captive thumbscrew head (accessory covers)."""
    mat = mat or b.mat("thumb_knurl", color=(150, 152, 156), spec=0.75, gloss=0.55, metal=1.0, bump="knurl", bump_amp=0.0001,
                       bump_scale=0.0007, edge=0.4, dirt=0.15)
    g = lathe([(0.0, 0.0), (d / 2, 0.0), (d / 2, h * 0.75), (d / 2 - h * 0.2, h), (0.0, h)], mat, segs=28, smooth_angle=45, tag="thumb")
    return align(g, normal, up, at)


def round_connector(b, at, normal, up=(0, 0, 1), d=0.012, pins=6, depth=0.003, mat=None, insert_mat=None):
    """Round accessory connector with a bayonet ring and a pin insert (military side connector)."""
    mat = mat or m_gunmetal(b)
    insert_mat = insert_mat or b.mat("conn_insert", color=(20, 21, 22), spec=0.3, gloss=0.4)
    R = d / 2
    g = lathe([(R * 0.62, depth * 0.2), (R * 0.62, depth), (R, depth), (R, depth * 0.2), (R * 1.08, 0.0), (R * 1.08, -0.0003)], mat,
              segs=36, smooth_angle=40, tag="conn")
    for k in range(3):
        a = 2 * math.pi * k / 3
        g += box((R * 0.25, R * 0.12, depth * 0.35), mat, r=0.0002, seg=1,
                 center=(math.cos(a) * R * 1.0, math.sin(a) * R * 1.0, depth * 0.7)).rotate(0, 0, math.degrees(a), origin=(0, 0, 0))
    g += cylinder(R * 0.6, depth * 0.55, insert_mat, segs=28, caps=(False, True))
    pm = m_contact_gold(b)
    for k in range(pins):
        a = 2 * math.pi * k / pins
        g += cylinder(R * 0.06, depth * 0.62, pm, segs=8, caps=(False, True)).translate(math.cos(a) * R * 0.35, math.sin(a) * R * 0.35, 0)
    return align(g, normal, up, at)


# ---------------------------------------------------------------------------------------------
# screen window (bezel + screen quad + glass) - records the layout's screen anchor
# ---------------------------------------------------------------------------------------------
def screen_window(r, center, normal=(0, 1, 0), up=(0, 0, 1), view=(0.036, 0.027), bezel=0.001, recess=0.0012,
                  margin=(0.0025, 0.0025), frame_mat=None, bezel_mat=None, glass=True, glass_mat=None, image=None, px=None,
                  mult=1.0, glass_gap=0.0003, corner=0.0012):
    """Screen window: a frame plate (proud of the surface at `center`) with an opening of view + 2 bezel
    falling `recess` deep to a black bezel floor; the screen quad (`view` size, fixed UVs, texture
    'nzr_scr') lies on that floor and a smoked glass sheet covers the opening `glass_gap` above it. The
    radio's screen anchor (centre, size, pixel size) is recorded from the screen quad.
    Returns {"screen": centre, "glass": centre, "top": frame top centre}."""
    _require_body(r, "screen_window()")
    right, upv, n = _frame(normal, up)
    vw, vh = view
    ow, oh = vw + 2 * bezel, vh + 2 * bezel
    t = recess + 0.0004
    frame_mat = frame_mat or m_soft_black(r)
    bezel_mat = bezel_mat or m_print_dark(r)
    pw, ph = ow + 2 * margin[0], oh + 2 * margin[1]
    wells(r, frame_mat, center, n, upv, (pw, ph), t, [(0.0, 0.0, ow / 2, oh / 2, min(corner, ow / 2, oh / 2))], depth=recess,
          floor_mat=bezel_mat, wall_mat=bezel_mat)
    floor = vec(center) + n * (t - recess)
    sc = floor + n * 0.00005
    r.screen(quad(sc, right, upv, vw, vh, "x", fixed_uv=True), image=image, size=px, mult=mult)
    gc = floor + n * glass_gap
    if glass:
        gm = glass_mat or m_smoked_glass(r)
        r.add(quad(gc, right, upv, ow - 0.0002, oh - 0.0002, gm, tag="glass"))
    return {"screen": sc, "glass": gc, "top": vec(center) + n * t}


# ---------------------------------------------------------------------------------------------
# labels / prints
# ---------------------------------------------------------------------------------------------
def print_decal(r, canvas, center, normal, up=(0, 0, 1), depth=0.003, mats=None, min_dot=0.4):
    """Project a print onto the body (or the current part) with sensible defaults."""
    r.decal(canvas, center=center, normal=normal, up=up, depth=depth, mats=mats, min_dot=min_dot)


def model_print(code, word=None, w=0.03, h=0.008, color="white", word_color=None, rule_color="teal", ppm=None, align_="left",
                spacing=0.06):
    """Model code print: bold code (e.g. 'PX-740') + a small function word ('PATROL') + a thin accent rule.
    No logo (Rule B)."""
    ppm = ppm or max(9000, int(420 / w))
    dc = DecalCanvas(w, h, ppm)
    hs = h * (0.55 if word else 0.7)
    x0 = 0.0 if align_ == "left" else w / 2
    anc = "lm" if align_ == "left" else "mm"
    dc.text(x0 + (h * 0.05 if align_ == "left" else 0), h * (0.36 if word else 0.5), code, hs, fnt="label-black", anchor=anc,
            spacing=hs * spacing, max_w=w * 0.98, **ink(color))
    if word:
        dc.text(x0 + (h * 0.05 if align_ == "left" else 0), h * 0.83, word, hs * 0.42, fnt="label-semi", anchor=anc,
                spacing=hs * 0.42 * 0.25, max_w=w * 0.98, **ink(word_color or color))
    if rule_color:
        tw = min(dc.text_width(code, hs, "label-black", hs * spacing), w)
        rx = h * 0.05 if align_ == "left" else (w - tw) / 2
        dc.rect(rx, h * 0.66, tw * 0.35, h * 0.045, **ink(rule_color))
    return dc


def rating_label(w=0.034, h=0.014, model="PX-740", serial="SN 26-07412", ident="ID: TXQ-PX740A", rating="7.4 V  2250 mAh  Li-ion",
                 title="TWO-WAY RADIO", foot="IP54", ppm=None):
    """Silver rating plate for a radio: device type, MODEL / SN / ID lines, rating, generic symbols,
    barcode + data-matrix. Fictitious identifiers only."""
    return rating_plate(w, h, title, model, serial, ref=ident.replace("ID: ", ""), rating=rating, ppm=ppm or max(9000, int(380 / w)),
                        ref_label="ID", foot=foot, icons=("factory", "date", "book", "bin"))


def battery_label(w=0.044, h=0.03, pack="PB-74", chem="Li-ion", volts="7.4 V", cap="2250 mAh", serial="SN B26-11873",
                  bg=(24, 25, 27), color="white", accent="teal", ppm=None):
    """Battery pack label: pack code, chemistry / voltage / capacity, handling fine print, recycling,
    crossed-out bin and caution symbols. Generic, no maker name."""
    ppm = ppm or max(8000, int(420 / w))
    dc = DecalCanvas(w, h, ppm)
    dc.rect(0, 0, w, h, r=h * 0.05, color=bg, spec=0.32, gloss=0.5)
    dc.rect(0, 0, w * 0.018, h, color=INK[accent] if accent in INK else accent)
    pad = h * 0.08
    dc.text(pad + w * 0.02, h * 0.15, pack, h * 0.12, fnt="label-black", anchor="lm", **ink(color))
    dc.text(w - pad, h * 0.15, f"{chem} {volts}", h * 0.085, fnt="label-semi", anchor="rm", **ink(color))
    dc.text(pad + w * 0.02, h * 0.34, f"{cap}  RECHARGEABLE", h * 0.075, fnt="label-semi", anchor="lm", max_w=w * 0.8, **ink(color))
    fine = ["Charge only with the matching charger.", "Do not short-circuit, crush or burn.", "Keep away from heat above 60 C."]
    for k, t in enumerate(fine):
        dc.text(pad + w * 0.02, h * (0.5 + k * 0.09), t, h * 0.052, fnt="label-reg", anchor="lm", max_w=w * 0.62, **ink("grey"))
    isz = h * 0.2
    for k, kind in enumerate(("recycle", "bin", "warn")):
        dc.icon(kind, w - pad - (3 - k) * isz * 1.12, h * 0.48, isz, color=INK["white"] if kind != "warn" else (16, 16, 18))
    dc.text(pad + w * 0.02, h * 0.9, serial, h * 0.055, fnt="mono", anchor="lm", **ink("grey"))
    dc.barcode(w * 0.55, h * 0.76, w * 0.4, h * 0.18, seed=sum(map(ord, serial)) % 997, color=INK["white"])
    return dc


def knob_scale(d, n=16, r0=None, r1=None, color="white", start=-135.0, sweep=270.0, labels=None, label_size=None, dot=False,
               ppm=None, size=None):
    """Printed scale around a knob (deck print): n ticks (or dots) on an arc from `start` (deg, 0 = up,
    clockwise) over `sweep`, optional labels. Canvas size = `size` (default 2.2 d) centred on the knob."""
    S = size or d * 2.2
    ppm = ppm or max(8000, int(400 / S))
    dc = DecalCanvas(S, S, ppm)
    c = S / 2
    r0 = r0 or d * 0.62
    r1 = r1 or d * 0.78
    for k in range(n):
        a = math.radians(start + sweep * k / max(n - 1, 1)) if sweep < 360 else math.radians(start + 360 * k / n)
        sx, sy = math.sin(a), -math.cos(a)
        if dot:
            dc.circle(c + sx * (r0 + r1) / 2, c + sy * (r0 + r1) / 2, (r1 - r0) * 0.35, **ink(color))
        else:
            dc.line([(c + sx * r0, c + sy * r0), (c + sx * r1, c + sy * r1)], S * 0.012, **ink(color))
        if labels and k < len(labels) and labels[k]:
            rl = r1 + (label_size or S * 0.05) * 1.1
            dc.text(c + sx * rl, c + sy * rl, labels[k], label_size or S * 0.05, fnt="label-semi", **ink(color))
    return dc


def volume_dots(n=8, w=0.016, h=0.004, color="white", grow=True, ppm=None):
    """Row of growing dots (volume scale printed on the deck next to a knob)."""
    ppm = ppm or max(9000, int(400 / w))
    dc = DecalCanvas(w, h, ppm)
    for k in range(n):
        rr = h * (0.12 + (0.3 * k / max(n - 1, 1) if grow else 0.15))
        dc.circle(w * (0.08 + 0.84 * k / max(n - 1, 1)), h / 2, rr, **ink(color))
    return dc


def perforation_decal(w, h, cols, rows, pitch, r, depth=0.0006, stagger=False, ppm=None):
    """Hole matrix as a decal: dark recessed discs (normal map). Cheap alternative to grille_holes()."""
    ppm = ppm or max(8000, int(500 / w))
    dc = DecalCanvas(w, h, ppm)
    gw = (cols - 1) * pitch
    gh = (rows - 1) * pitch
    dc.perforate((w - gw) / 2, (h - gh) / 2, cols, rows, pitch, r, depth=depth, stagger=stagger)
    return dc


def slots_decal(w, h, n, vertical=False, fill=0.45, depth=0.0006, ppm=None):
    ppm = ppm or max(8000, int(500 / w))
    dc = DecalCanvas(w, h, ppm)
    dc.slots(0, 0, w, h, n, vertical=vertical, fill=fill, depth=depth)
    return dc


__all__ = [k for k in dir() if not k.startswith("_") and k not in ("annotations", "math", "np")]
