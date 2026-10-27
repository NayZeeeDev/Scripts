"""nayzeee_audio_c -- "Drum Hub": a horizontal drum / barrel portable.

A 0.52 m long, 0.244 m diameter barrel lying along X.  The body is a wrap-around perforated steel
grille, recessed 7 mm below two end-cap "hubs": a bead-blasted gunmetal band, a diamond-cut aluminium
seam ring and a soft rubber bumper wrapping onto a satin face.  Each hub holds a passive radiator
(rubber surround, graphite diaphragm, spun-aluminium centre badge with the nayzeee mark) deep behind
a polished chrome trim ring held by six socket screws, with a teal light ring glowing around the
radiator.  A raised soft-touch rubber control spine runs along the top (power, pairing, battery gauge,
minus / play / plus, light mode); a graphite keel runs along the bottom and two cradle saddles with
rubber soles give the drum a flat, stable base.  A brushed-aluminium bar handle rises from the two
hubs, with a knurled rubber grip and teal end rings in the middle.  Back: rubber port flap with a pull
tab and the printed model name.

Model space: origin = floor centre under the model, +Y = front, +X = viewer's left, +Z up.
Barrel axis along X at height ZC.
"""
import math

import numpy as np

from lib import fonts
from lib import mesh as M
from lib import textures as tx
from lib.spec import Anchor, Box, Capsule, Cylinder, LodSettings, ModelSpec

L = 0.52                  # overall length (end cap face to end cap face)
XE = L / 2                # outer face of the hubs
XI = 0.222                # inner face of the hubs: grille / spine / keel run between +-XI
ZC = 0.142                # barrel axis height
RC = 0.122                # hub (end cap) radius
RG = 0.1150               # grille radius (recessed below the hubs, spine and keel)
SPINE_A = 17.0            # spine edges, degrees from the top
SPINE_Z = 0.1195          # spine plateau height above the axis
SPINE_W = 0.024           # spine plateau half width
KEEL_A = 34.0             # keel edges, degrees from the bottom
KEEL_R = 0.1195           # keel outer radius
SADDLE_X = 0.145          # saddle centres (+-)
SADDLE_L = 0.046          # saddle length along X
SADDLE_A = 42.0           # saddle arc half angle around the bottom
SOLE_H = 0.0045           # rubber sole thickness under the saddles
BOSS_X = 0.241            # handle bosses on top of the hubs
BAR_Z = ZC + 0.192        # handle bar centre height
BAR_R = 0.0085            # handle bar radius
GRIP_R = 0.0145           # rubber grip radius
GRIP_L = 0.136            # rubber grip length
DECAL_OFF = 0.0005        # printed decals float this far above their surface
TOP_Z = ZC + SPINE_Z      # spine plateau (control strip) height

# design (a, b, e) -> world (x, y, z) = (e, a, b): outlines drawn in the YZ plane, extruded along X
_PERM = np.array([[0.0, 0.0, 1.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])


# --------------------------------------------------------------------------- helpers
def _yz(alpha, r):
    """Point on the barrel cross-section: ``alpha`` degrees from the top (+ toward the front), radius r
    -> (y, z relative to the axis)."""
    a = math.radians(alpha)
    return (r * math.sin(a), r * math.cos(a))


def _fillet(points, radius, segments=3, only=None):
    """Round the corners of a closed 2D polygon (indices in ``only``, default all)."""
    P = np.asarray(points, float)
    n = len(P)
    seg = M.seg(segments, 1)
    out = []
    for i in range(n):
        a, b, c = P[i - 1], P[i], P[(i + 1) % n]
        if only is not None and i not in only:
            out.append(b)
            continue
        u, v = a - b, c - b
        lu, lv = np.linalg.norm(u), np.linalg.norm(v)
        u, v = u / lu, v / lv
        ang = math.acos(float(np.clip(np.dot(u, v), -1.0, 1.0)))
        if ang < 1e-3 or abs(ang - math.pi) < 1e-3:
            out.append(b)
            continue
        t = min(radius / math.tan(ang / 2), lu * 0.45, lv * 0.45)
        r = t * math.tan(ang / 2)
        p0, p1 = b + u * t, b + v * t
        bis = (u + v) / np.linalg.norm(u + v)
        cc = b + bis * (r / math.sin(ang / 2))
        a0 = math.atan2(*(p0 - cc)[::-1])
        a1 = math.atan2(*(p1 - cc)[::-1])
        da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
        for k in range(seg + 1):
            t_ = a0 + da * k / seg
            out.append(cc + r * np.array([math.cos(t_), math.sin(t_)]))
    return np.array(out)


def _arc(r, a0, a1, n):
    """Points on the barrel cross-section circle of radius r from alpha a0 to a1 (degrees)."""
    return [_yz(a, r) for a in np.linspace(a0, a1, M.seg(n, 2) + 1)]


def _prism(outline, x0, x1, material, **kw):
    """Extrude a (y, z-above-axis) outline along X from x0 to x1."""
    return M.extrude(outline, x1 - x0, z0=x0, material=material, **kw).transform(_PERM).translate(0, 0, ZC)


def _sg(n, low):
    """Nominal segment count that gives n in the High LOD and never fewer than ``low`` in the Medium LOD
    (keeps the hub silhouettes round at distance)."""
    return max(float(n), low / max(M.get_detail(), 1e-6))


def _lathe_x(profile, segments, material, start=0.0, sweep=360.0, crease=40.0):
    """Lathe an (r, x) profile around the barrel axis.  Lathe angle 0 = bottom, 90 = front, 180 = top."""
    m = M.lathe(profile, segments, sweep=sweep, start=start, crease=crease, material=material)
    return m.rotate_y(90).translate(0, 0, ZC)


def _cull_inside(mesh, r_max):
    """Drop triangles lying entirely inside the barrel radius ``r_max`` (hidden behind the grille)."""
    P, F = mesh.positions, mesh.indices
    r = np.hypot(P[:, 1], P[:, 2] - ZC)
    inside = (r[F] < r_max).all(axis=1)
    m = mesh.copy()
    m.indices = F[~inside].copy()
    m.tangents = None
    return m.compact()


def _wrap(mesh, alpha_c, x_c, r0):
    """Bend a flat design (x = right and y = up for a viewer facing the surface, z = out of it) onto the
    barrel surface of radius r0, centred at angle ``alpha_c`` (degrees from the top) and axial ``x_c``.
    The barrel only curves across X, so panels are laid out long along X: a 26 mm wide panel's cap
    chords sag 0.7 mm at most, well inside the 1.2-3 mm the panels stand proud."""
    sgn = 1.0 if alpha_c >= 0 else -1.0
    m = mesh.copy()
    p, n = m.positions, m.normals
    a = math.radians(alpha_c) - sgn * p[:, 1] / r0
    r = r0 + p[:, 2]
    sa, ca = np.sin(a), np.cos(a)
    m.positions = np.column_stack([x_c - sgn * p[:, 0], r * sa, ZC + r * ca])
    e_right = np.array([-sgn, 0.0, 0.0])
    e_up = sgn * np.column_stack([np.zeros_like(a), -ca, sa])
    e_out = np.column_stack([np.zeros_like(a), sa, ca])
    nn = n[:, 0:1] * e_right[None, :] + n[:, 1:2] * e_up + n[:, 2:3] * e_out
    m.normals = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
    m.tangents = None
    return m


def _decal(entry, width, center, facing="+z"):
    """Print-atlas decal quad, ``width`` along the image u axis (top faces read from the front)."""
    h = width / tx.atlas_aspect(entry)
    m = M.plane(width, h, center=(0, 0, 0), facing="design", rect=tx.atlas_rect(entry), material="print_decal")
    return m.orient(facing, center)


def _socket_screw(pos, facing, r=0.0019):
    """Low button-head socket screw (gunmetal) with a dark hex recess -> [head, recess]."""
    head = M.lathe([(r, 0.0, 1.0, 0.0), (r, 0.00035, 1.0, 0.0)] + M.arc_profile((r - 0.0005, 0.00035), 0.0005, 0, 90, 2)
                   + [(0.0, 0.00085, 0.0, 1.0)], 8, crease=50, material="gunmetal")
    hexa = M.extrude(M.regular_polygon_2d(r * 0.42, 6), 0.00025, z0=0.0009, cap_bottom=False,
                     material="gloss_black_plastic")
    return [head.orient(facing, pos).named("screw"), hexa.orient(facing, pos).named("screw_socket")]


# --------------------------------------------------------------------------- body
def _grille(parts):
    """Wrap-around perforated grille: one front and one back panel between the spine and the keel
    (they run 0.5 deg under both so no seam shows)."""
    a0, a1 = SPINE_A - 0.5, 180.0 - KEEL_A + 0.5
    prof = [(RG, -XI - 0.001, 1.0, 0.0), (RG, XI + 0.001, 1.0, 0.0)]
    for side, start in (("front", 180.0 - a1), ("back", 180.0 + a0)):
        g = _lathe_x(prof, 56, "speaker_grille_metal", start=start, sweep=a1 - a0)
        parts.append(g.named(f"grille_{side}"))


def _spine(parts):
    """Raised soft-touch control spine along the top, sloped sides dropping into the grille."""
    foot_r = _yz(SPINE_A, RG - 0.0025)
    pts = [foot_r, (SPINE_W, SPINE_Z), (-SPINE_W, SPINE_Z), (-foot_r[0], foot_r[1])]
    out = _fillet(pts, 0.0045, 4, only={1, 2})
    spine = _prism(out, -XI - 0.001, XI + 0.001, "rubber", cap_top=False, cap_bottom=False, crease=30)
    parts.append(_cull_inside(spine, RG + 0.0004).named("spine"))


def _keel(parts):
    """Graphite keel band along the bottom (the saddles clamp it)."""
    a0, a1 = 180.0 - KEEL_A, 180.0 + KEEL_A
    pts = [_yz(a0, RG - 0.0025)] + _arc(KEEL_R, a0 + 2.0, a1 - 2.0, 24) + [_yz(a1, RG - 0.0025)]
    out = _fillet(pts, 0.0025, 3, only={1, len(pts) - 2})
    keel = _prism(out, -XI - 0.001, XI + 0.001, "satin_graphite", cap_top=False, cap_bottom=False, crease=30)
    parts.append(_cull_inside(keel, RG + 0.0004).named("keel"))


def _saddles(parts):
    """Two cradle saddles under the barrel with flat rubber soles (the drum's feet)."""
    a0, a1 = 180.0 - SADDLE_A, 180.0 + SADDLE_A
    zb = -ZC + SOLE_H - 0.0005                      # saddle bottom (relative to the axis)
    top_r = np.array(_yz(a0, RG + 0.0003))
    half = 0.086
    # flared, concave side walls (quadratic Bezier from the barrel down to the foot)
    ctrl = np.array([top_r[0] - 0.002, zb + 0.016])
    t = np.linspace(0.0, 1.0, M.seg(6, 3) + 1)[:, None]
    wall = (1 - t) ** 2 * top_r + 2 * (1 - t) * t * ctrl + t ** 2 * np.array([half, zb])
    back = wall[::-1] * [-1, 1]
    pts = [tuple(p) for p in wall] + [tuple(p) for p in back]
    pts += _arc(RG + 0.0003, a1 - 1.0, a0 + 1.0, 14)
    nw = len(wall)
    out = _fillet(pts, 0.0035, 3, only={0, 2 * nw - 1})
    out = _fillet(out, 0.0045, 3, only={i for i, p in enumerate(out) if abs(p[1] - zb) < 1e-9})
    for sx in (-1, 1):
        x0 = sx * SADDLE_X - SADDLE_L / 2
        s = _prism(out, x0, x0 + SADDLE_L, "satin_graphite", bevel=0.0028, bevel_segments=2, crease=30)
        parts.append(_cull_inside(s, RG + 0.0009).named("saddle"))
        sole = M.rounded_box((SADDLE_L - 0.004, 2 * half - 0.010, SOLE_H + 0.0005), (0.0025, 0.0025, 0.0016), 2,
                             center=(sx * SADDLE_X, 0, (SOLE_H + 0.0005) / 2), material="rubber")
        parts.append(sole.named("saddle_sole"))
        # teal hairline inlaid in the saddle's outer side walls (front and back), low on the flare
        k = int(len(wall) * 0.72)
        A, B = wall[k - 1], wall[k]
        d = (B - A) / np.linalg.norm(B - A)
        nrm = np.array([d[1], -d[0]]) if d[1] < 0 else np.array([-d[1], d[0]])
        if nrm[0] < 0:
            nrm = -nrm
        p = (A + B) / 2 + nrm * 0.0002
        tilt = math.degrees(math.atan2(nrm[1], nrm[0]))
        line = M.box((SADDLE_L - 0.012, 0.0010, 0.0018), material="teal_plastic")
        line = line.rotate_x(tilt).translate(sx * SADDLE_X, p[0], ZC + p[1])
        parts += [line.named("saddle_accent"), line.mirror("y").named("saddle_accent")]


# --------------------------------------------------------------------------- hubs (end caps)
def _hub(sign):
    """One end-cap hub at x = sign * XE (built for +X, turned 180 deg about Z for -X so prints read)."""
    parts = []
    hs = _sg(48, 24)                              # one count for every hub ring so their edges stay nested
    r_ring_o, r_ring_i = 0.1005, 0.0900
    ring_top = XE + 0.0026                        # chrome ring stands 2.6 mm proud of the face
    edge = 0.009
    # bead-blasted gunmetal band: inner face (toward the grille), small bevel, cylinder to the seam
    xs = XE - 0.0150                              # seam between the band and the rubber bumper
    band = [(RG - 0.003, XI, 0.0, -1.0), (RC - 0.002, XI, 0.0, -1.0)]
    band += M.arc_profile((RC - 0.002, XI + 0.002), 0.002, -90, 0, 2)
    band += [(RC, xs - 0.0008, 1.0, 0.0), (RC - 0.0008, xs, 0.0, 1.0), (RC - 0.0030, xs, 0.0, 1.0)]
    parts.append(_lathe_x(band, hs, "gunmetal", crease=30).named("hub_band"))
    # diamond-cut aluminium ring in the seam between the band and the bumper (catches the light)
    cut = [(RC - 0.0030, xs - 0.0002), (RC + 0.0002, xs + 0.0004), (RC + 0.0002, xs + 0.0010),
           (RC - 0.0030, xs + 0.0016)]
    parts.append(_lathe_x(cut, hs, "brushed_aluminium", crease=30).named("hub_cut_ring"))
    # soft rubber bumper wrapping the outer edge onto the face
    rb = RC + 0.0006
    bump = [(RC - 0.0030, xs + 0.0015, 0.0, -1.0), (rb - 0.0020, xs + 0.0015, 0.0, -1.0)]
    bump += M.arc_profile((rb - 0.0020, xs + 0.0035), 0.0020, -90, 0, 1)
    bump += [(rb, XE - edge, 1.0, 0.0)] + M.arc_profile((rb - edge, XE - edge), edge, 0, 90, 3)
    bump += [(0.1125, XE, 0.0, 1.0)]
    parts.append(_lathe_x(bump, hs, "rubber", crease=30).named("hub_bumper"))
    # flat outer face annulus (planar UVs: no stretching)
    face = M.lathe([(0.1127, XE - 0.0001, 0.0, 1.0), (r_ring_o - 0.0006, XE - 0.0001, 0.0, 1.0)], hs,
                   material="satin_graphite")
    parts.append(face.rotate_y(90).translate(0, 0, ZC).uv_planar("+x").named("hub_face"))
    # polished chrome trim ring standing proud of the face
    ring = [(r_ring_o, XE - 0.0010, 1.0, 0.0), (r_ring_o, ring_top - 0.0012, 1.0, 0.0)]
    ring += M.arc_profile((r_ring_o - 0.0012, ring_top - 0.0012), 0.0012, 0, 90, 2)
    ring += M.arc_profile((r_ring_i + 0.0018, ring_top - 0.0018), 0.0018, 90, 180, 2)
    ring += [(r_ring_i, XE - 0.0030, -1.0, 0.0)]
    parts.append(_lathe_x(ring, hs, "chrome", crease=50).named("hub_trim_ring"))
    # six socket screws on the ring top
    for k in range(6):
        a = math.radians(30 + 60 * k)
        rr = (r_ring_o + r_ring_i) / 2 - 0.0002
        pos = (ring_top - 0.0003, rr * math.sin(a), ZC - rr * math.cos(a))
        parts += _socket_screw(pos, "+x", 0.0017)
    # cavity: matte wall, teal light ring floor, passive radiator
    floor = XE - 0.017
    wall = [(r_ring_i + 0.0006, XE - 0.0015, -1.0, 0.0), (r_ring_i + 0.0006, floor, -1.0, 0.0)]
    parts.append(_lathe_x(wall, hs, "matte_black_plastic").named("hub_cavity"))
    led = M.lathe([(r_ring_i + 0.0006, floor, 0.0, 1.0), (0.0858, floor, 0.0, 1.0)], hs, material="led_teal")
    parts.append(led.rotate_y(90).translate(0, 0, ZC).named("hub_light_ring"))
    # rubber surround (half roll) between the light ring and the diaphragm
    rs, rm = 0.0062, 0.0858 - 0.0062
    sur = [(rm + rs * math.cos(t), floor + rs * math.sin(t), math.cos(t), math.sin(t))
           for t in np.radians(np.linspace(0.0, 180.0, M.seg(4, 3) + 1))]       # >= 3 steps even in the Medium LOD
    parts.append(_lathe_x(sur, hs, "rubber", crease=60).named("radiator_surround"))
    # diaphragm: very shallow cone rising toward the badge
    rd = rm - rs
    dia = [(rd, floor, 0.0, 1.0), (0.0335, floor + 0.0016), (0.0, floor + 0.0016, 0.0, 1.0)]
    d = M.lathe(dia, hs, crease=35, material="satin_graphite").rotate_y(90).translate(0, 0, ZC)
    parts.append(d.uv_planar("+x").named("radiator_diaphragm"))
    # spun aluminium centre badge with a raised gloss mark
    bz = floor + 0.0016
    badge = M.cylinder(0.0320, 0.0016, 32, bevel=0.0007, bevel_segments=2, bottom=False,
                       material="brushed_aluminium_radial")
    badge = badge.uv_radial(0.032).rotate_y(90).translate(bz - 0.0002, 0, ZC)
    parts.append(badge.named("radiator_badge"))
    mark, bar = M.mark_2d(0.030, 4)
    mk = M.extrude(mark, 0.0007, holes=[bar], bevel=0.0002, bevel_segments=1, cap_bottom=False, bevel_bottom=False,
                   material="gloss_black_plastic")
    parts.append(mk.orient("+x", (bz + 0.0014, 0, ZC)).named("radiator_mark"))
    # handle boss on top of the hub (open bottom: it sinks into the hub)
    boss_top = ZC + RC + 0.013
    boss = M.cylinder(0.0135, boss_top - (ZC + RC - 0.010), 32, bevel=0.003, bevel_segments=2, bottom=False,
                      material="gunmetal").translate(BOSS_X, 0, ZC + RC - 0.010)
    parts.append(boss.named("handle_boss"))
    parts.append(M.lathe([(0.0137, 0.0, 1.0, 0.0), (0.0137, 0.0012, 1.0, 0.0), (0.0128, 0.0012, 0.0, 1.0)], 24,
                         material="teal_plastic").translate(BOSS_X, 0, ZC + RC + 0.0025).named("boss_accent"))
    ferrule = M.cylinder(BAR_R + 0.0020, 0.0040, 24, bevel=0.0010, bevel_segments=2, bottom=False, material="chrome")
    parts.append(ferrule.translate(BOSS_X, 0, boss_top - 0.0008).named("bar_ferrule"))
    if sign < 0:
        parts = [p.rotate_z(180) for p in parts]
    return parts


# --------------------------------------------------------------------------- handle
def _handle(parts):
    zb = ZC + RC + 0.013 - 0.004
    path = M.polyline_path([(BOSS_X, 0, zb), (BOSS_X, 0, BAR_Z), (-BOSS_X, 0, BAR_Z), (-BOSS_X, 0, zb)],
                           radius=0.034, segments=7)
    bar = M.sweep(M.circle_section(BAR_R, 20), path, material="brushed_aluminium", caps=False)
    parts.append(bar.uv_transform(rotate=90).named("handle_bar"))
    # knurled rubber grip with soft chamfered ends and teal end rings
    g = GRIP_L / 2
    prof = [(BAR_R + 0.0002, -g, 0.0, -1.0), (GRIP_R - 0.0030, -g, 0.0, -1.0)]
    prof += M.arc_profile((GRIP_R - 0.0030, -g + 0.0030), 0.0030, -90, 0, 2)
    prof += [(GRIP_R, g - 0.0030, 1.0, 0.0)] + M.arc_profile((GRIP_R - 0.0030, g - 0.0030), 0.0030, 0, 90, 2)
    prof += [(BAR_R + 0.0002, g, 0.0, 1.0)]
    grip = M.lathe(prof, 32, crease=50, material="rubber_grip").uv_cylindrical("z")
    parts.append(grip.rotate_y(90).translate(0, 0, BAR_Z).named("handle_grip"))
    ro = BAR_R + 0.0032
    ring = M.lathe([(BAR_R, -0.0015, 0.0, -1.0), (ro - 0.0006, -0.0015, 0.0, -1.0), (ro, -0.0009, 1.0, 0.0),
                    (ro, 0.0009, 1.0, 0.0), (ro - 0.0006, 0.0015, 0.0, 1.0), (BAR_R, 0.0015, 0.0, 1.0)],
                   20, crease=30, material="teal_plastic").rotate_y(90)
    for sx in (-1, 1):
        parts.append(ring.translate(sx * (g + 0.0016), 0, BAR_Z).named("grip_ring"))


# --------------------------------------------------------------------------- control strip
def _button(parts, x, r, icon, accent=False, icon_w=None):
    """Round push button set in a gunmetal bezel on the spine plateau, icon printed on top."""
    z = TOP_Z
    n = 32 if r > 0.009 else 16
    ro, ri, hb, c = r + 0.0022, r + 0.0004, 0.0009, 0.0003
    bez = M.lathe([(ro, -0.0003, 1.0, 0.0), (ro, hb - c), (ro - c, hb, 0.0, 1.0), (ri, hb, 0.0, 1.0),
                   (ri, -0.0003, -1.0, 0.0)], n, crease=30, material="gunmetal")
    parts.append(bez.translate(x, 0, z).named("button_bezel"))
    if accent:
        parts.append(M.lathe([(r + 0.0036, z + 0.0002, 0.0, 1.0), (ro + 0.0002, z + 0.0002, 0.0, 1.0)], n,
                             material="teal_plastic").translate(x, 0, 0).named("button_accent"))
    h = 0.0032
    prof = [(r, 0.0, 1.0, 0.0), (r, h - 0.0012, 1.0, 0.0)]
    prof += M.arc_profile((r - 0.0012, h - 0.0012), 0.0012, 0, 90, 2) + [(0.0, h + 0.0003, 0.0, 1.0)]
    cap = M.lathe(prof, n, crease=45, material="satin_graphite")
    parts.append(cap.translate(x, 0, z - 0.0004).named("button"))
    w = icon_w if icon_w else r * 1.05
    parts.append(_decal(icon, w, (x, 0, z - 0.0004 + h + 0.0003 + DECAL_OFF)).named("button_icon"))


def _controls(parts):
    """Laid out for a user standing at the front: power / pairing / battery on the left (+X), minus, play,
    plus in the middle, light mode and the printed wordmark on the right (-X)."""
    _button(parts, 0.192, 0.0072, "icon_power")
    _button(parts, 0.160, 0.0072, "icon_bluetooth")
    _button(parts, 0.036, 0.0078, "icon_minus")
    _button(parts, 0.000, 0.0102, "icon_play", accent=True, icon_w=0.0092)
    _button(parts, -0.036, 0.0078, "icon_plus")
    _button(parts, -0.112, 0.0072, "icon_note")
    # battery gauge: five LEDs in one gunmetal slot bezel (four lit)
    x0, pitch = 0.128, -0.0075
    xc = x0 + 2 * pitch
    w = 5 * abs(pitch)
    slot = M.extrude(M.rounded_rect_2d(w + 0.0010, 0.0052, 0.0026, 4), 0.0008, bevel=0.0003, bevel_segments=1,
                     holes=[M.rounded_rect_2d(w - 0.0012, 0.0034, 0.0017, 4)], cap_bottom=False, bevel_bottom=False,
                     material="gunmetal", z0=-0.0002)
    parts.append(slot.translate(xc, 0, TOP_Z).named("battery_bezel"))
    parts.append(M.box((w - 0.0010, 0.0034, 0.0004), (xc, 0, TOP_Z + 0.0001), material="gloss_black_plastic")
                 .named("battery_window"))
    for k in range(5):
        mat = "led_teal" if k < 4 else "gloss_black_plastic"
        parts.append(M.hemisphere(0.0013, 12, 2, cap=False, material=mat).scale(1, 1, 0.6)
                     .translate(x0 + pitch * k, 0, TOP_Z + 0.0003).named("battery_led"))
    # wordmark printed on the spine (reads from the front)
    parts.append(_decal("wordmark", 0.050, (-0.170, 0, TOP_Z + DECAL_OFF)).named("spine_wordmark"))


# --------------------------------------------------------------------------- front wordmark, back panel
def _badges(parts):
    # front: raised brushed-aluminium wordmark, low on the grille
    word = []
    for outer, holes in fonts.text_polygons("nayzeee", 0.0118, weight=600, quality=24, tolerance=0.3):
        word.append(M.extrude(outer, 0.0013, holes=holes, bevel=0.00035, bevel_segments=1, cap_bottom=False,
                              bevel_bottom=False, material="brushed_aluminium", z0=-0.0003))
    parts.append(_wrap(M.merge(word).uv_planar("+z"), 116.0, 0.0, RG).named("front_wordmark"))
    # back: rubber port flap with a pull tab, model name printed beside it
    flap = M.extrude(M.rounded_rect_2d(0.074, 0.026, 0.006, 4), 0.0030, bevel=0.0012, bevel_segments=3,
                     cap_bottom=False, bevel_bottom=False, material="rubber", z0=-0.0006)
    parts.append(_wrap(flap, -110.0, 0.120, RG).named("port_flap"))
    tab = M.extrude(M.rounded_rect_2d(0.014, 0.006, 0.0025, 3), 0.0022, bevel=0.0008, bevel_segments=2,
                    cap_bottom=False, bevel_bottom=False, material="rubber", z0=0.0020)
    parts.append(_wrap(tab.translate(0.030, 0, 0), -110.0, 0.120, RG).named("port_tab"))
    plate = M.extrude(M.rounded_rect_2d(0.104, 0.024, 0.005, 4), 0.0016, bevel=0.0006, bevel_segments=2,
                      cap_bottom=False, bevel_bottom=False, material="satin_graphite", z0=-0.0004)
    parts.append(_wrap(plate, -110.0, -0.100, RG).named("name_plate"))
    for entry, dy, w in (("drum_hub", 0.0035, 0.056), ("nayzeee_audio", -0.0055, 0.046)):
        d = M.plane(w, w / tx.atlas_aspect(entry), center=(0, dy, 0.0012 + DECAL_OFF), facing="design",
                    rect=tx.atlas_rect(entry), material="print_decal")
        parts.append(_wrap(d, -110.0, -0.100, RG).named("back_print"))


# --------------------------------------------------------------------------- model
def build(detail: float) -> ModelSpec:
    parts = []
    _grille(parts)
    _spine(parts)
    _keel(parts)
    _saddles(parts)
    for s in (1, -1):
        parts += _hub(s)
    _handle(parts)
    _controls(parts)
    _badges(parts)

    lo, hi = M.parts_bounds(parts)[:2]
    top, size = float(hi[2]), hi - lo
    collision = [
        Cylinder((-XE, 0, ZC), (XE, 0, ZC), RC, "PLASTIC"),
        Box((SADDLE_X, 0, 0.012), (SADDLE_L, 0.162, 0.024), "RUBBER"),
        Box((-SADDLE_X, 0, 0.012), (SADDLE_L, 0.162, 0.024), "RUBBER"),
        Capsule((-BOSS_X, 0, BAR_Z), (BOSS_X, 0, BAR_Z), GRIP_R, "METAL_SOLID_SMALL"),
        Cylinder((BOSS_X, 0, ZC + RC - 0.01), (BOSS_X, 0, BAR_Z), BAR_R + 0.002, "METAL_SOLID_SMALL"),
        Cylinder((-BOSS_X, 0, ZC + RC - 0.01), (-BOSS_X, 0, BAR_Z), BAR_R + 0.002, "METAL_SOLID_SMALL"),
    ]
    anchors = {
        "grip": Anchor((0.0, 0.0, BAR_Z), note="centre of the rubber handle grip (hand closes here)"),
        "top": Anchor((0.0, 0.0, top), note="highest point (top of the handle grip)"),
        "front": Anchor((0.0, RG, ZC), note="front centre of the grille"),
        "controls": Anchor((0.0, 0.0, TOP_Z), note="play button on the top control spine"),
        "radiator_left": Anchor((XE, 0.0, ZC), (0, 90, 0), note="+X passive radiator centre (viewer's left)"),
        "radiator_right": Anchor((-XE, 0.0, ZC), (0, -90, 0), note="-X passive radiator centre (viewer's right)"),
    }
    return ModelSpec(
        name="nayzeee_audio_c",
        parts=parts,
        collision=collision,
        anchors=anchors,
        lod=LodSettings(high_dist=14.0, archetype_lod_dist=100.0, hd_texture_dist=6.0, med_detail=0.35),
        description="Drum Hub: horizontal barrel portable with a wrap-around steel grille, chrome-ringed passive "
                    "radiator hubs with teal light rings, rubber control spine and a brushed bar handle.",
        meta={"render": {"yaw": 30, "pitch": 20}, "size_m": [round(float(v), 4) for v in size]},
    )
