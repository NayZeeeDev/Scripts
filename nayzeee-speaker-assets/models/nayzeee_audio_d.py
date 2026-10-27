"""nayzeee_audio_d -- "Orb": a 0.28 m spherical speaker resting in a slim ring stand.

The upper shell is perforated steel (round holes; conformal UVs, so the perforations never stretch:
they shrink smoothly toward the top like a graded pressing).  A glowing teal LED band runs around the
equator between two polished chrome beads.  The lower shell is satin graphite; a bass port fires
straight down through a bell-mouth flare and a recessed dust grille.  A spun-aluminium top cap carries
the soft rubber carry loop (clamped in two brushed blocks with chrome screws, teal stripe along its
back) and five push buttons with printed icons.  The orb sits on three rubber pads in a brushed ring
on three splayed legs with rubber feet, which leaves the downward port room to breathe.  Back: rubber
port plug and printed model name; front: small raised nayzeee mark.

Model space: origin = floor centre under the model, +Y = front, +X = viewer's left, +Z up.
"""
import math

import numpy as np

from lib import materials as mats
from lib import mesh as M
from lib import textures as tx
from lib.materials import PBR, Material
from lib.spec import Anchor, Capsule, Cylinder, LodSettings, ModelSpec, Sphere

R = 0.140                 # orb radius
ZS = 0.172                # orb centre height
RG = R - 0.0015           # perforated upper shell radius (recessed under the chrome bead and top cap)
RT = R + 0.0010           # top cap radius (stands 2.5 mm proud of the grille)
LAT_CAP = 56.0            # top cap edge latitude
BEAD_Z = 0.0052           # chrome bead centres (+-, relative to the orb centre)
BEAD_R = 0.0013
LED_R = R - 0.0012        # LED band radius (recessed between the beads)
PORT_RT = 0.022           # port throat radius
PORT_RF = 0.010           # bell-mouth flare radius
PORT_DEPTH = 0.040        # throat length above the flare
RING_R = 0.092            # stand ring centre radius
RING_W, RING_H = 0.0100, 0.0075     # ring section (radial, vertical)
FOOT_R = 0.114            # leg feet radius
LEG_A = (30.0, 150.0, 270.0)        # leg azimuths (deg from +X; 270 = back)
STRAP_X = 0.050           # strap clamp positions (+-X) on the top cap
STRAP_ARC = 0.050         # strap arch radius
STRAP_T, STRAP_W = 0.0062, 0.024    # strap thickness (radial) and width (along Y)
DECAL_OFF = 0.0005

# The equator band is a large emitter (8 mm x 0.88 m): the shared led_teal (x6, made for pin-point LEDs)
# blooms into a halo on it, so the band gets its own softer diffuser material.
if "orb_led_band" not in mats.names():
    _c = (0.05, 0.72, 0.65)
    mats.register(Material("orb_led_band", "emissive", {"DiffuseSampler": "nz_led_teal_e"}, {"emissiveMultiplier": 1.8},
                           PBR(base_color=_c, roughness=0.35, emissive=_c, emissive_strength=1.8), 1.0,
                           "EMISSIVE_PLASTIC", "Frosted teal LED diffuser band (Orb equator)."))
# Dark spun (concentric-brushed) anodised metal for the top cap dome: the gunmetal colour with the radial
# brushing normal/spec maps (all three already in the texture dictionary).  Map with uv_radial().
if "orb_cap_spun" not in mats.names():
    mats.register(Material("orb_cap_spun", "normal_spec",
                           {"DiffuseSampler": "nz_gunmetal_d", "BumpSampler": "nz_radial_n", "SpecSampler": "nz_radial_s"},
                           {"specularIntensityMult": 0.75, "specularFalloffMult": 120.0, "specularFresnel": 0.95,
                            "bumpiness": 0.5},
                           PBR(metallic=0.9, roughness=0.30, normal_scale=0.6), 1.0, "METAL_SOLID_SMALL",
                           "Dark spun anodised metal (Orb top cap); map with uv_radial()."))


# --------------------------------------------------------------------------- helpers
def _polar(lat, rho):
    """(r, z relative to the orb centre) of a point at latitude ``lat`` (deg) and distance rho."""
    a = math.radians(lat)
    return (rho * math.cos(a), rho * math.sin(a))


def _sphere_prof(rho, lat0, lat1, n):
    """Lathe profile along a sphere of radius rho from lat0 to lat1 with analytic normals."""
    out = []
    for lat in np.linspace(lat0, lat1, M.seg(n, 2) + 1):
        a = math.radians(lat)
        out.append((rho * math.cos(a), rho * math.sin(a), math.cos(a), math.sin(a)))
    return out


def _lathe(profile, segments, material, crease=40.0):
    return M.lathe(profile, segments, crease=crease, material=material).translate(0, 0, ZS)


def _sg(n, low):
    """Nominal segment count that gives n in the High LOD and never fewer than ``low`` in the Medium LOD
    (keeps the big round silhouettes round at distance)."""
    return max(float(n), low / max(M.get_detail(), 1e-6))


def _uv_conformal(mesh, repeats):
    """Mercator UVs around the orb centre: u = azimuth * repeats / 2pi (seamless, ``repeats`` integer),
    v = -repeats / 2pi * ln(tan(pi/4 + lat/2)).  Conformal: textures scale with cos(lat) but never stretch."""
    m = mesh.copy()
    p = m.positions - np.array([0.0, 0.0, ZS])
    ang = np.arctan2(p[:, 1], p[:, 0]) % (2 * math.pi)
    seam = (ang < 1e-6) & (m.uvs[:, 0] > 1e-9)          # the lathe's closing column
    ang[seam] = 2 * math.pi
    lat = np.arcsin(np.clip(p[:, 2] / np.linalg.norm(p, axis=1), -1, 1))
    k = repeats / (2 * math.pi)
    m.uvs = np.column_stack([ang * k, -k * np.log(np.tan(math.pi / 4 + lat / 2))])
    m.uv_tile = None
    m.tangents = None
    return m


def _cull_inside(mesh, rho):
    """Drop triangles lying entirely inside the orb (radius rho): faces buried in the shell are never seen."""
    P, F = mesh.positions, mesh.indices
    d = np.linalg.norm(P - np.array([0.0, 0.0, ZS]), axis=1)
    m = mesh.copy()
    m.indices = F[~(d[F] < rho).all(axis=1)].copy()
    m.tangents = None
    return m.compact()


def _rot_to(n):
    """Rotation matrix taking +Z to the unit vector n (minimal rotation)."""
    n = np.asarray(n, float) / np.linalg.norm(n)
    z = np.array([0.0, 0.0, 1.0])
    ax = np.cross(z, n)
    s = float(np.linalg.norm(ax))
    if s < 1e-9:
        return np.eye(3) if n[2] > 0 else M.rotation_matrix("x", 180.0)
    return M.rotation_matrix(ax / s, math.degrees(math.atan2(s, float(np.dot(z, n)))))


def _on_cap(mesh, x, y, rho=RT):
    """Place a part built for a flat top (+Z up, readable from the front, origin on the surface) at (x, y) on
    the dome of radius rho, tilted to the dome normal."""
    n = np.array([x, y, math.sqrt(rho * rho - x * x - y * y)])
    pos = n + np.array([0.0, 0.0, ZS])
    return mesh.transform(M.compose(M.translation_matrix(pos), _rot_to(n / rho)))


def _on_sphere(mesh, lat, lon, rho):
    """Bend a flat design (x = right and y = up for a viewer facing the surface, z = out of it) onto the
    sphere of radius rho around the orb centre, centred at latitude/longitude (deg; lon 90 = front)."""
    la, lo = math.radians(lat), math.radians(lon)
    n0 = np.array([math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)])
    e_r = np.cross([0.0, 0.0, 1.0], n0)
    e_r /= np.linalg.norm(e_r)
    e_u = np.cross(n0, e_r)
    m = mesh.copy()
    p, nrm = m.positions, m.normals
    d = np.hypot(p[:, 0], p[:, 1]) / rho
    t = np.where(d[:, None] > 1e-12, (p[:, 0:1] * e_r + p[:, 1:2] * e_u) / np.maximum(np.hypot(p[:, 0], p[:, 1]),
                                                                                    1e-12)[:, None], 0.0)
    dirs = np.cos(d)[:, None] * n0 + np.sin(d)[:, None] * t
    m.positions = dirs * (rho + p[:, 2:3]) + np.array([0.0, 0.0, ZS])
    out = []
    for i in range(len(dirs)):                     # local frame at each vertex (right / up / out)
        er = np.cross([0.0, 0.0, 1.0], dirs[i])
        er /= np.linalg.norm(er)
        eu = np.cross(dirs[i], er)
        out.append(nrm[i, 0] * er + nrm[i, 1] * eu + nrm[i, 2] * dirs[i])
    out = np.array(out)
    m.normals = out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)
    m.tangents = None
    return m


def _decal(entry, width, segments=1):
    """Print-atlas decal quad in design space (XY, facing +Z)."""
    h = width / tx.atlas_aspect(entry)
    return M.plane(width, h, center=(0, 0, 0), facing="design", segments=(segments, 1), rect=tx.atlas_rect(entry),
                   material="print_decal")


def _screw(facing, pos, r=0.0016):
    """Chrome dome screw with a dark slot -> [head, slot]."""
    head = M.hemisphere(r, 12, 3, cap=False, material="chrome").scale(1, 1, 0.42)
    slot = M.box((1.5 * r, 0.22 * r, 0.12 * r), center=(0, 0, 0.42 * r - 0.03 * r), material="gloss_black_plastic")
    return [head.orient(facing, pos).named("screw"), slot.orient(facing, pos).named("screw_slot")]


# --------------------------------------------------------------------------- shell
def _shell(parts):
    lat_s = -math.degrees(math.asin(0.0058 / R))          # lower shell ends inside the chrome bead
    # bell-mouth port flare: convex fillet tangent to the throat and to the sphere
    lat_f = -math.degrees(math.acos((PORT_RT + PORT_RF) / (R - PORT_RF)))
    cx, cz = PORT_RT + PORT_RF, (R - PORT_RF) * math.sin(math.radians(lat_f))
    flare = []
    for t in np.linspace(180.0, 360.0 + lat_f, M.seg(5, 3) + 1):
        a = math.radians(t)
        flare.append((cx + PORT_RF * math.cos(a), cz + PORT_RF * math.sin(a), math.cos(a), math.sin(a)))
    lower = flare + _sphere_prof(R, lat_f, lat_s, 14)[1:]
    parts.append(_uv_conformal(_lathe(lower, 64, "satin_graphite"), 7).named("lower_shell"))
    # port throat + recessed dust grille
    z_top = cz + PORT_DEPTH
    throat = [(PORT_RT, z_top, -1.0, 0.0), (PORT_RT, cz, -1.0, 0.0)]
    parts.append(_lathe(throat, 48, "matte_black_plastic").named("port_throat"))
    disc = M.disc(PORT_RT + 0.0002, 0.0, 48, facing="-z", material="speaker_grille_round")
    parts.append(disc.translate(0, 0, ZS + z_top).uv_planar("-z").named("port_grille"))
    # equator: two chrome beads around a recessed teal LED band.  Each bead is walked counter-clockwise
    # around its centre; the lower one starts inside the graphite shell, the upper one ends inside the grille.
    def bead(zc, t0, t1, n):
        return [(R - 0.0002 + BEAD_R * math.cos(t), zc + BEAD_R * math.sin(t), math.cos(t), math.sin(t))
                for t in np.radians(np.linspace(t0, t1, M.seg(n, 4) + 1))]
    z_step = BEAD_Z - BEAD_R * math.sin(math.radians(70.0))       # bead top / bottom next to the LED band
    lower = bead(-BEAD_Z, -120.0, 110.0, 6) + [(LED_R - 0.0002, -z_step, 0.0, 1.0)]
    upper = [(LED_R - 0.0002, z_step, 0.0, -1.0)] + bead(BEAD_Z, -110.0, 180.0, 7)
    parts.append(_lathe(lower, 64, "chrome", crease=50).named("bead_lower"))
    parts.append(_lathe(upper, 64, "chrome", crease=50).named("bead_upper"))
    zl = z_step + 0.0002
    band = [(LED_R, -zl, 1.0, 0.0), (LED_R, zl, 1.0, 0.0)]
    parts.append(_lathe(band, 64, "orb_led_band").named("led_band"))
    # perforated upper shell (starts inside the upper bead, ends under the top cap lip)
    lat_g = math.degrees(math.asin(0.0058 / RG))
    grille = _sphere_prof(RG, lat_g, LAT_CAP + 0.6, 13)
    parts.append(_uv_conformal(_lathe(grille, 64, "speaker_grille_round"), 14).named("grille"))


def _top_cap(parts):
    """Top cap: a bright diamond-cut aluminium edge (step face + 45 deg chamfer) around a dark bead-blasted
    spun dark-metal dome that carries the controls and the carry loop."""
    a = math.radians(LAT_CAP)
    un, ut = np.array([math.cos(a), math.sin(a)]), np.array([-math.sin(a), math.cos(a)])
    ch = 0.0016                                           # chamfer leg
    d45 = (un + ut) / math.sqrt(2.0)                      # chamfer face normal
    edge = [tuple((RG - 0.0010) * un) + tuple(-ut), tuple((RT - ch) * un) + tuple(-ut),
            tuple((RT - ch) * un) + tuple(d45), tuple(RT * un + ch * ut) + tuple(d45)]
    ring = _lathe(edge, _sg(64, 28), "brushed_aluminium_radial", crease=30)
    parts.append(ring.uv_radial(RT * math.cos(a) + 0.001, center=(0, 0, 0)).named("cap_edge"))
    lat0 = LAT_CAP + math.degrees(ch / RT)
    dome = _lathe(_sphere_prof(RT, lat0, 90.0, 8), _sg(64, 28), "orb_cap_spun", crease=30)
    parts.append(dome.uv_radial(RT * math.cos(a) + 0.001, center=(0, 0, 0)).named("top_cap"))


# --------------------------------------------------------------------------- carry loop
def _strap(parts):
    zr = math.sqrt(RT * RT - STRAP_X ** 2)                # cap surface (relative) at the clamps
    blk_h, blk_w, blk_d = 0.013, 0.014, STRAP_W + 0.008
    z_blk = ZS + zr - 0.004                               # clamp bottom (sunk into the cap)
    z0 = z_blk + blk_h + 0.010                            # arch centre height
    for sx in (-1, 1):
        blk = M.rounded_box((blk_w, blk_d, blk_h), 0.0025, 3, center=(sx * STRAP_X, 0, z_blk + blk_h / 2),
                            material="brushed_aluminium")
        parts.append(_cull_inside(blk, RT - 0.0002).named("strap_clamp"))
        # dark slot frame on the clamp top where the strap dives in (reads as the slot's depth)
        slot = M.extrude(M.rounded_rect_2d(STRAP_T + 0.0024, STRAP_W + 0.0024, 0.0014, 3), 0.0004,
                         holes=[M.rounded_rect_2d(STRAP_T + 0.0002, STRAP_W + 0.0002, 0.0012, 3)], cap_bottom=False,
                         material="gloss_black_plastic", z0=z_blk + blk_h - 0.0001)
        parts.append(slot.translate(sx * STRAP_X, 0, 0).named("strap_slot"))
        for sy in (-1, 1):
            parts += _screw("+x" if sx > 0 else "-x", (sx * (STRAP_X + blk_w / 2), sy * 0.0085, z_blk + blk_h * 0.62))
    path = np.vstack([[(STRAP_X, 0, z_blk + blk_h - 0.004)],
                      M.arc_path((0, 0, z0), STRAP_ARC, 0.0, 180.0, 24, plane="xz"),
                      [(-STRAP_X, 0, z_blk + blk_h - 0.004)]])
    strap = M.sweep(M.rounded_rect_section(STRAP_T, STRAP_W, 0.0028, 3), path, material="rubber", caps=False)
    parts.append(strap.named("carry_loop"))
    # teal stripe inlaid along the outside of the loop
    outer = np.vstack([[(STRAP_X + STRAP_T / 2, 0, z_blk + blk_h + 0.001)],
                       M.arc_path((0, 0, z0), STRAP_ARC + STRAP_T / 2, 0.0, 180.0, 24, plane="xz"),
                       [(-STRAP_X - STRAP_T / 2, 0, z_blk + blk_h + 0.001)]])
    stripe = M.sweep(M.rounded_rect_section(0.0009, 0.0036, 0.0004, 1), outer, material="teal_plastic")
    parts.append(stripe.named("loop_stripe"))
    return z0


def _button(parts, x, y, r, icon, accent=False):
    """Push button on the dome: chamfered bezel ring, domed cap, printed icon; built flat, then tilted."""
    n = 32 if r > 0.008 else 20
    ro, ri, hb, c = r + 0.0020, r + 0.0004, 0.0009, 0.0003
    bits = [M.lathe([(ro, -0.0006, 1.0, 0.0), (ro, hb - c), (ro - c, hb, 0.0, 1.0), (ri, hb, 0.0, 1.0),
                     (ri, -0.0006, -1.0, 0.0)], n, crease=30, material="gloss_black_plastic").named("button_bezel")]
    if accent:
        bits.append(M.lathe([(ro + 0.0013, 0.0002, 0.0, 1.0), (ro + 0.0001, 0.0002, 0.0, 1.0)], n,
                            material="teal_plastic").named("button_accent"))
    h = 0.0030
    prof = [(r, -0.0006, 1.0, 0.0), (r, h - 0.0011, 1.0, 0.0)]
    prof += M.arc_profile((r - 0.0011, h - 0.0011), 0.0011, 0, 90, 2) + [(0.0, h + 0.0003, 0.0, 1.0)]
    cap = M.lathe(prof, n, crease=45, material="satin_graphite")
    bits.append(cap.named("button"))
    bits.append(M.plane(r * 1.05, r * 1.05, center=(0, 0, h + 0.0003 + DECAL_OFF), facing="+z",
                        rect=tx.atlas_rect(icon), material="print_decal").named("button_icon"))
    parts += [_on_cap(b, x, y) for b in bits]


def _controls(parts):
    # front row (minus on the user's left = +X), back row (power, pairing), status LED
    _button(parts, 0.024, 0.030, 0.0065, "icon_minus")
    _button(parts, 0.000, 0.033, 0.0085, "icon_play", accent=True)
    _button(parts, -0.024, 0.030, 0.0065, "icon_plus")
    _button(parts, 0.013, -0.032, 0.0060, "icon_power")
    _button(parts, -0.013, -0.032, 0.0060, "icon_bluetooth")
    led = M.hemisphere(0.0016, 12, 3, cap=False, material="led_teal").scale(1, 1, 0.7)
    bez = M.lathe([(0.0027, -0.0004, 1.0, 0.0), (0.0027, 0.0005, 0.0, 1.0), (0.0016, 0.0005, 0.0, 1.0)], 16,
                  material="chrome")
    parts += [_on_cap(led, 0.034, -0.026).named("status_led"), _on_cap(bez, 0.034, -0.026).named("led_bezel")]


# --------------------------------------------------------------------------- stand
def _stand(parts):
    # ring height: its inner top edge sits 2.5 mm under the orb (the rubber pads fill the gap)
    ri = RING_R - RING_W / 2
    z_contact = ZS - math.sqrt(R * R - (ri + 0.0015) ** 2)
    zr = z_contact - 0.0025 - RING_H / 2
    w, h, b = RING_W / 2, RING_H / 2, 0.0022
    prof = [(RING_R - w + b, zr - h, 0.0, -1.0)] + M.arc_profile((RING_R + w - b, zr - h + b), b, -90, 0, 1)
    prof += M.arc_profile((RING_R + w - b, zr + h - b), b, 0, 90, 2)
    prof += M.arc_profile((RING_R - w + b, zr + h - b), b, 90, 180, 2)
    prof += M.arc_profile((RING_R - w + b, zr - h + b), b, 180, 270, 1)
    ring = M.lathe(prof, 64, closed=True, material="brushed_aluminium", crease=40)
    parts.append(ring.named("stand_ring"))
    # three rubber wedge pads the orb rests on (between the legs); their tops follow the orb's slope
    zb = zr + h - 0.0006
    rp = ri + 0.0032

    def z_orb(r_):
        return ZS - math.sqrt(R * R - r_ * r_) + 0.0003          # just inside the orb surface

    hw = 0.0034
    wedge = [(-hw, zb), (hw, zb), (hw, z_orb(rp + hw)), (-hw, z_orb(rp - hw))]
    pad = M.extrude(wedge, 0.016, bevel=0.0010, bevel_segments=2, z0=-0.008, material="rubber")
    for a in LEG_A:
        t = math.radians(a + 60.0)
        e1 = np.array([math.cos(t), math.sin(t), 0.0])            # radial
        e3 = np.array([math.sin(t), -math.cos(t), 0.0])           # = e1 x Z (right-handed with e2 = Z)
        rot = np.column_stack([e1, [0.0, 0.0, 1.0], e3])
        pad_w = pad.transform(rot).translate(rp * math.cos(t), rp * math.sin(t), 0.0)
        parts.append(_cull_inside(pad_w, R).named("stand_pad"))
    # three splayed legs with rubber feet
    foot_h = 0.0070
    for a in LEG_A:
        t = math.radians(a)
        p0 = np.array([RING_R * math.cos(t), RING_R * math.sin(t), zr])
        p1 = np.array([FOOT_R * math.cos(t), FOOT_R * math.sin(t), foot_h - 0.0015])
        path = M.bezier_path(p0, p0 + [0, 0, -0.020], p1 + [0, 0, 0.022], p1, 10)
        leg = M.sweep(M.circle_section(0.0042, 12), path, material="brushed_aluminium", caps=False)
        parts.append(leg.uv_transform(rotate=90).named("stand_leg"))
        foot = M.lathe([(0.0, 0.0, 0.0, -1.0)] + M.arc_profile((0.0066, 0.0016), 0.0016, -90, 0, 2)
                       + [(0.0082, foot_h - 0.0016)] + M.arc_profile((0.0066, foot_h - 0.0016), 0.0016, 0, 90, 2)
                       + [(0.0045, foot_h, 0.0, 1.0)], 18, crease=40, material="rubber")
        parts.append(foot.translate(p1[0], p1[1], 0.0).named("stand_foot"))
        parts.append(M.lathe([(0.0047, 0.0, 1.0, 0.0), (0.0047, 0.0012, 1.0, 0.0), (0.0036, 0.0016, 0.0, 1.0)], 16,
                             material="chrome").translate(p1[0], p1[1], foot_h - 0.0001).named("foot_ferrule"))
    return zr


# --------------------------------------------------------------------------- prints, badge, ports
def _details(parts):
    # small raised brushed-aluminium mark on the front, low on the graphite shell, its bar inlaid in teal
    mark, bar = M.mark_2d(0.018, 4)
    mk = M.extrude(mark, 0.0010, holes=[bar], bevel=0.0003, bevel_segments=1, cap_bottom=False, bevel_bottom=False,
                   material="brushed_aluminium", z0=-0.0004)
    parts.append(_on_sphere(mk.uv_planar("+z"), -24.0, 90.0, R).named("front_mark"))
    inlay = M.extrude(bar, 0.0007, cap_bottom=False, material="teal_plastic", z0=-0.0004)
    parts.append(_on_sphere(inlay, -24.0, 90.0, R).named("front_mark_bar"))
    # back: rubber port plug (USB-C / AUX) with a ridge, printed model name below
    plug = M.extrude(M.rounded_rect_2d(0.036, 0.015, 0.0055, 4), 0.0020, bevel=0.0008, bevel_segments=2,
                     cap_bottom=False, bevel_bottom=False, material="rubber", z0=-0.0005)
    parts.append(_on_sphere(plug, -20.0, -90.0, R).named("port_plug"))
    ridge = M.extrude(M.rounded_rect_2d(0.010, 0.0022, 0.0011, 3), 0.0010, bevel=0.0004, bevel_segments=1,
                      cap_bottom=False, bevel_bottom=False, material="rubber", z0=0.0013)
    parts.append(_on_sphere(ridge, -20.0, -90.0, R).named("port_plug_ridge"))
    for entry, lat, w in (("orb", -27.0, 0.016), ("nayzeee_audio", -30.2, 0.042)):
        d = _decal(entry, w, 8).translate(0, 0, DECAL_OFF)
        parts.append(_on_sphere(d, lat, -90.0, R).named("back_print"))


# --------------------------------------------------------------------------- model
def build(detail: float) -> ModelSpec:
    parts = []
    _shell(parts)
    _top_cap(parts)
    z0 = _strap(parts)
    _controls(parts)
    zr = _stand(parts)
    _details(parts)

    lo, hi = M.parts_bounds(parts)[:2]
    top, size = float(hi[2]), hi - lo
    grip = (0.0, 0.0, z0 + STRAP_ARC)
    collision = [
        Sphere((0.0, 0.0, ZS), R, "PLASTIC"),
        Cylinder.vertical((0.0, 0.0), 0.0, zr + RING_H / 2, FOOT_R + 0.008, "METAL_SOLID_SMALL"),
        Capsule((-STRAP_X + 0.010, 0.0, z0 + 0.030), (STRAP_X - 0.010, 0.0, z0 + 0.030), 0.020, "RUBBER"),
    ]
    anchors = {
        "grip": Anchor(grip, note="top of the carry loop, centre of the strap (hand closes here)"),
        "top": Anchor((0.0, 0.0, top), note="highest point (outside of the carry loop)"),
        "orb_centre": Anchor((0.0, 0.0, ZS), note="centre of the sphere"),
        "led_band": Anchor((0.0, R, ZS), note="front of the teal equator LED band"),
        "port": Anchor((0.0, 0.0, ZS - R + 0.004), (180, 0, 0), note="downward-firing bass port mouth"),
        "controls": Anchor((0.0, 0.033, ZS + math.sqrt(RT * RT - 0.033 ** 2)), note="play button on the top cap"),
    }
    return ModelSpec(
        name="nayzeee_audio_d",
        parts=parts,
        collision=collision,
        anchors=anchors,
        lod=LodSettings(high_dist=14.0, archetype_lod_dist=100.0, hd_texture_dist=6.0, med_detail=0.45),
        description="Orb: spherical speaker with a perforated steel upper shell, teal LED equator, spun-aluminium "
                    "top cap with a rubber carry loop, downward bass port, on a slim brushed ring stand.",
        meta={"render": {"yaw": 30, "pitch": 16}, "size_m": [round(float(v), 4) for v in size]},
    )
