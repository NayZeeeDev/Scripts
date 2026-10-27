"""Shared helpers, materials and textures for the portable speakers

    nayzeee_audio_a  Pulse Tower   (tall party tower, integrated top handle)
    nayzeee_audio_e  Carry Cube    (rounded cube, rubber corner caps, fold handle)
    nayzeee_audio_b  Echo Column   (fabric column, machined top cap, strap)

Not a model (the registry ignores files starting with "_").  Everything here is registered
tolerantly (a module reload or a second importer never raises) and prefixed ``spk_`` / ``nz_spk_``
so it never clashes with other lanes.

Geometry helpers
  loft()        walls through a 2D contour at a list of (offset, z) rings -- an extrude with a free
                profile: back bevel, straight wall, front bevel, flat bezel face, recess wall, floor ...
  cap()         flat triangulated face of a contour (optionally with holes)
  ring2d()/lathe_n()  circles and lathes with an EXACT segment count, so a cap hole and the lathe that
                starts at its edge share every vertex (no cracks, no T-junctions)
  cull_inside() drop triangles that lie completely inside a convex solid (no hidden faces)
  wrap_cyl()    bend a flat design (x = arc length, y = height, z = radial offset) onto a cylinder
  decal()/screw()/facing() small parts
Design space (as everywhere in the pipeline): x right, y up, extruded toward +Z, then
``Mesh.orient(facing, origin)`` puts it on a face, upright for a viewer looking at that face.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from lib import materials as mats
from lib import mesh as M
from lib import textures as tx
from lib.materials import PBR, Material

DECAL_OFF = 0.0006            # printed decals float this far above their surface (>= 0.5 mm: no z-fighting)


# --------------------------------------------------------------------------- exact-count circles
def ring2d(r: float, n: int, center=(0.0, 0.0), start: float = 0.0) -> np.ndarray:
    """CCW circle with exactly ``n`` points, first point at angle ``start`` (deg) -- the same angles as
    ``lathe_n(..., n, start=start)`` so both share their rim vertices."""
    t = math.radians(start) + np.linspace(0.0, 2.0 * math.pi, int(n), endpoint=False)
    return np.column_stack([center[0] + r * np.cos(t), center[1] + r * np.sin(t)])


def lathe_n(profile, n: int, **kw) -> M.Mesh:
    """``M.lathe`` with exactly ``n`` segments (not scaled again by the detail factor)."""
    with M.detail(1.0):
        return M.lathe(profile, int(n), **kw)


def nseg(n: float, minimum: int = 8, multiple: int = 4) -> int:
    """Detail-scaled segment count, rounded to a multiple (use once, pass to ring2d / lathe_n)."""
    return M.seg(n, minimum, multiple=multiple)


# --------------------------------------------------------------------------- loft
def loft(contour, rings, material: str | None = None, tile: float | None = None, crease: float = 35.0,
         prof_crease: float = 40.0, hole: bool = False, name: str = "loft") -> M.Mesh:
    """Walls through a closed 2D ``contour`` placed at successive ``rings``.

    rings : (offset, z) or (offset, z, nh, nz).  ``offset`` moves the contour AWAY from the solid
            (outer contour: grows it; ``hole=True``: shrinks the hole), z is the height along +Z.
            Walk the rings with the solid on your LEFT in the (offset, z) plane -- for an outer
            contour that is back -> front up the outside, then inward across a front face, then down
            a recess wall (same rule as ``lathe``).  (nh, nz) = explicit profile normal (use
            ``M.arc_profile`` for fillets); otherwise profile corners sharper than ``prof_crease``
            are split, contour corners sharper than ``crease`` get hard normals.
    UVs   : u = contour length, v = -profile length (both / tile): a seamless unwrap of the walls.
            Re-map flat faces with ``uv_planar`` after orienting when a texture has a direction.
    """
    c = M.ensure_ccw_2d(M._dedupe_2d(np.asarray(contour, dtype=float)))
    if hole:
        c = c[::-1].copy()
    if tile is None:
        tile = mats.get(material).tile if material else 0.25
    tile = float(tile)
    pts, enrm = [], []
    for r in rings:
        r = tuple(float(x) for x in r)
        if pts and abs(r[0] - pts[-1][0]) < 1e-10 and abs(r[1] - pts[-1][1]) < 1e-10:
            if len(r) >= 4:
                enrm[-1] = r[2:4]
            continue
        pts.append(r[:2])
        enrm.append(r[2:4] if len(r) >= 4 else (np.nan, np.nan))
    P = np.array(pts, dtype=float)
    EN = np.array(enrm, dtype=float)
    K = len(P)
    if K < 2:
        raise ValueError("loft(): needs two distinct rings")
    S = K - 1
    d = P[1:] - P[:-1]
    sl = np.linalg.norm(d, axis=1)
    sn = np.column_stack([d[:, 1], -d[:, 0]]) / sl[:, None]          # right-hand normal (h, z)
    cum_v = np.concatenate([[0.0], np.cumsum(sl)])
    cos_pc = math.cos(math.radians(prof_crease))
    rows = []                                                         # (offset, z, nh, nz, v)
    seg_start, seg_end = [None] * S, [None] * S

    def add_row(k, nv):
        nv = np.asarray(nv, float)
        nv = nv / max(np.linalg.norm(nv), 1e-12)
        rows.append((P[k, 0], P[k, 1], nv[0], nv[1], cum_v[k]))
        return len(rows) - 1

    for k in range(K):
        if not np.isnan(EN[k]).any():
            r_prev = r_next = add_row(k, EN[k])
        else:
            na = sn[k - 1] if k > 0 else None
            nb = sn[k] if k < S else None
            if na is None:
                r_prev = r_next = add_row(k, nb)
            elif nb is None:
                r_prev = r_next = add_row(k, na)
            elif float(np.dot(na, nb)) >= cos_pc:
                r_prev = r_next = add_row(k, na + nb)
            else:
                r_prev, r_next = add_row(k, na), add_row(k, nb)
        if k > 0:
            seg_end[k - 1] = r_prev
        if k < S:
            seg_start[k] = r_next

    # contour slots (one per smooth vertex, two per sharp vertex) -- as lib.mesh.extrude
    n = len(c)
    e = np.roll(c, -1, axis=0) - c
    el = np.linalg.norm(e, axis=1)
    en = np.column_stack([e[:, 1], -e[:, 0]]) / np.maximum(el, 1e-15)[:, None]
    prev_n = np.roll(en, 1, axis=0)
    smooth = np.einsum("ij,ij->i", prev_n, en) >= math.cos(math.radians(crease))
    slot_vtx, slot_n, slot_in, slot_out = [], [], [], []
    for i in range(n):
        s = len(slot_vtx)
        if smooth[i]:
            v = prev_n[i] + en[i]
            slot_vtx.append(i)
            slot_n.append(v / max(np.linalg.norm(v), 1e-15))
            slot_in.append(s)
            slot_out.append(s)
        else:
            slot_vtx += [i, i]
            slot_n += [prev_n[i], en[i]]
            slot_in.append(s)
            slot_out.append(s + 1)
    slot_vtx = np.array(slot_vtx)
    slot_n = np.array(slot_n)
    ns = len(slot_vtx)
    cum_u = np.concatenate([[0.0], np.cumsum(el)])
    slot_u = cum_u[slot_vtx]
    total_u = cum_u[-1]

    pos, nrm, uv = [], [], []
    for (off, z, nh, nz, v) in rows:
        cc = M._offset_contour(c, -off)
        p2 = cc[slot_vtx]
        pos.append(np.column_stack([p2, np.full(ns, z)]))
        nn = np.column_stack([slot_n * nh, np.full(ns, nz)])
        nrm.append(nn / np.linalg.norm(nn, axis=1, keepdims=True))
        uv.append(np.column_stack([slot_u / tile, np.full(ns, -v / tile)]))
        s0 = slot_in[0]                                             # seam copy of vertex 0
        pos.append(np.array([[cc[0, 0], cc[0, 1], z]]))
        n0 = np.array([slot_n[s0, 0] * nh, slot_n[s0, 1] * nh, nz])
        nrm.append((n0 / np.linalg.norm(n0))[None, :])
        uv.append(np.array([[total_u / tile, -v / tile]]))
    stride = ns + 1
    idx = []
    for s in range(S):
        A, B = seg_start[s] * stride, seg_end[s] * stride
        for i in range(n):
            j = (i + 1) % n
            a0, a1 = A + slot_out[i], B + slot_out[i]
            b0 = A + (ns if j == 0 else slot_in[j])
            b1 = B + (ns if j == 0 else slot_in[j])
            idx += [(a0, b0, b1), (a0, b1, a1)]
    m = M.Mesh(np.vstack(pos), np.array(idx, dtype=np.int64), np.vstack(nrm), np.vstack(uv),
               material=material, name=name, uv_tile=tile)
    m.fix_winding()
    return m.remove_degenerate(1e-16)


def offset2d(contour, offset: float) -> np.ndarray:
    """Grow (offset > 0) or shrink a CCW outline (miter joins)."""
    c = M.ensure_ccw_2d(M._dedupe_2d(np.asarray(contour, dtype=float)))
    return M._offset_contour(c, -offset)


def densify2d(c, max_len: float) -> np.ndarray:
    """Split the edges of a closed 2D contour so none is longer than ``max_len`` (points kept)."""
    c = np.asarray(c, float)
    out = []
    for i in range(len(c)):
        a, b = c[i], c[(i + 1) % len(c)]
        k = max(1, int(math.ceil(float(np.linalg.norm(b - a)) / max_len)))
        out += [a + (b - a) * (t / k) for t in range(k)]
    return np.array(out)


def cap(contour, z: float = 0.0, offset: float = 0.0, holes=(), up: bool = True,
        material: str | None = None, name: str = "cap") -> M.Mesh:
    """Flat face of ``contour`` (grown by ``offset``) at height z, facing +Z (or -Z), with ``holes``
    (exact point lists, e.g. ``ring2d``).  UVs: call ``uv_planar`` after orienting."""
    c = offset2d(contour, offset) if offset else M.ensure_ccw_2d(np.asarray(contour, dtype=float))
    if len(holes):
        # lib.mesh.triangulate_polygon can bridge a hole across another hole when the outer contour has
        # long straight edges (seen with two stacked circular holes in a rounded rectangle: overlapping
        # triangles cover the second hole).  Splitting long edges keeps every bridge short and correct.
        c = densify2d(c, 0.012)
    P2, T = M.triangulate_polygon(c, [np.asarray(h, float) for h in holes])
    pos = np.column_stack([P2, np.full(len(P2), z)])
    nrm = np.tile([0.0, 0.0, 1.0 if up else -1.0], (len(P2), 1))
    m = M.Mesh(pos, T, nrm, material=material, name=name)
    m.fix_winding()
    return m.remove_degenerate(1e-18)


# --------------------------------------------------------------------------- solids / culling
def sdf_rounded_box(center, size, radius):
    """Signed distance function of a rounded box (negative inside)."""
    c = np.asarray(center, float)
    h = np.asarray(size, float) / 2.0 - radius

    def f(p):
        q = np.abs(np.asarray(p, float) - c) - h
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - radius
    return f


def cull_inside(mesh: M.Mesh, sdf, margin: float = 0.0003) -> M.Mesh:
    """Remove triangles whose three corners are deeper than ``margin`` inside a CONVEX solid given by
    its SDF (for a convex solid the whole triangle is then hidden)."""
    d = sdf(mesh.positions)
    inside = (d[mesh.indices] < -margin).all(axis=1)
    if not inside.any():
        return mesh
    m = mesh.copy()
    m.indices = mesh.indices[~inside].copy()
    return m.compact()


def facing(mesh: M.Mesh, direction, cos_min: float = 0.95):
    """Split a mesh by triangle orientation -> (triangles facing ``direction``, the rest)."""
    P, F = mesh.positions, mesh.indices
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-18)
    sel = n @ np.asarray(direction, float) >= cos_min

    def sub(mask):
        m = mesh.copy()
        m.indices = F[mask].copy()
        m.tangents = None
        return m.compact()
    return sub(sel), sub(~sel)


# --------------------------------------------------------------------------- cylinders
def wrap_cyl(mesh: M.Mesh, radius: float, angle0: float = 90.0) -> M.Mesh:
    """Bend a design-space mesh onto the cylinder of ``radius`` around world Z: design x = arc length
    (x > 0 = viewer's right when looking at the angle0 direction from outside), y = world z,
    z = radial offset.  angle0 = 90 puts design x = 0 on the +Y (front) side."""
    p = mesh.positions
    th = np.radians(angle0) + p[:, 0] / radius
    r = radius + p[:, 2]
    ct, st = np.cos(th), np.sin(th)
    pos = np.column_stack([r * ct, r * st, p[:, 1]])
    t_hat = np.column_stack([-st, ct, np.zeros_like(st)])
    r_hat = np.column_stack([ct, st, np.zeros_like(st)])
    z_hat = np.tile([0.0, 0.0, 1.0], (len(p), 1))
    nn = mesh.normals
    nrm = nn[:, 0:1] * t_hat + nn[:, 1:2] * z_hat + nn[:, 2:3] * r_hat
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    return M.Mesh(pos, mesh.indices.copy(), nrm, mesh.uvs.copy(), mesh.colors.copy(), None, mesh.material,
                  mesh.name, uv_tile=mesh.uv_tile).fix_winding()


def uv_around(mesh: M.Mesh, repeats: float, z0: float, z1: float, aspect: float = 1.0) -> M.Mesh:
    """UVs for a band around world Z: u = angle * repeats / 360 deg (seam-free when repeats is an
    integer and the lathe seam column is at angle 0), v = (z1 - z) * repeats * aspect / circumference
    scaled so texels stay square when ``aspect`` = 1 (pass the band radius via repeats)."""
    m = mesh.copy()
    p = m.positions
    ang = np.degrees(np.arctan2(p[:, 1], p[:, 0])) % 360.0
    seam = (ang < 1e-6) & (m.uvs[:, 0] > 1e-9)
    ang[seam] = 360.0
    r = np.hypot(p[:, 0], p[:, 1]).max()
    circ = 2.0 * math.pi * r
    m.uvs = np.column_stack([ang / 360.0 * repeats, (z1 - p[:, 2]) / circ * repeats * aspect])
    m.uv_tile = None
    m.tangents = None
    return m


# --------------------------------------------------------------------------- small parts
def decal(entry: str, center, facing_dir="+z", width: float | None = None, height: float | None = None,
          rotate: float = 0.0, material: str = "print_decal", rect=None, aspect=None) -> M.Mesh:
    """Quad for a print-atlas entry (or an explicit ``rect``/``aspect``) on a face."""
    a = aspect if aspect is not None else tx.atlas_aspect(entry)
    if width is None:
        width = height * a
    h = width / a
    m = M.plane(width, h, center=(0, 0, 0), facing="design", rect=rect or tx.atlas_rect(entry), material=material)
    if rotate:
        m = m.rotate_z(rotate)
    return m.orient(facing_dir, center).named("decal")


def screw(pos, facing_dir="+z", r: float = 0.0022, material: str = "gunmetal", detail: float = 1.0):
    """Low dome-head Phillips screw on a face -> parts.  The head has no base cap (it sits on the face);
    the recessed cross is one dark plus-shaped inlay just under the dome top."""
    head = M.hemisphere(r, 10, 2, cap=False, material=material).scale(1, 1, 0.45)
    parts = [head.orient(facing_dir, pos).named("screw")]
    if detail >= 0.6:
        a, b = 0.62 * r, 0.12 * r
        cross = [(a, -b), (a, b), (b, b), (b, a), (-b, a), (-b, b), (-a, b), (-a, -b), (-b, -b), (-b, -a), (b, -a),
                 (b, -b)]
        cr = cap(np.array(cross), 0.45 * r + 0.00008, material="gloss_black_plastic").rotate_z(45.0)
        parts.append(cr.orient(facing_dir, pos).named("screw_slot"))
    return parts


def jack(pos, facing_dir, r_ring: float, ring_mat: str):
    """3.5 mm jack standing on a face: coloured collar, chrome barrel, dark bore -> parts."""
    ring = M.lathe([(r_ring, 0.0, 1.0, 0.0), (r_ring, 0.0009, 1.0, 0.0), (r_ring - 0.0003, 0.0012, 0.0, 1.0),
                    (0.0042, 0.0012, 0.0, 1.0)], 20, crease=45, material=ring_mat)
    barrel = M.lathe([(0.0042, 0.0012, 1.0, 0.0), (0.0042, 0.0040, 1.0, 0.0), (0.0035, 0.0047),
                      (0.0021, 0.0047, 0.0, 1.0)], 24, crease=45, material="chrome")
    bore = M.lathe([(0.0021, 0.0047, -1.0, 0.0), (0.0021, 0.0012, -1.0, 0.0), (0.0, 0.0012, 0.0, 1.0)], 16,
                   crease=45, material="gloss_black_plastic")
    return [ring.orient(facing_dir, pos).named("jack_ring"), barrel.orient(facing_dir, pos).named("jack"),
            bore.orient(facing_dir, pos).named("jack_bore")]


def usb_c(pos, facing_dir, rotate: float = 0.0):
    """USB-C receptacle standing 1.2 mm proud of a face: stadium chrome shell, dark opening, tongue."""
    shell_o = M.rounded_rect_2d(0.0094, 0.0036, 0.0018, 3)
    shell_i = M.rounded_rect_2d(0.0082, 0.0024, 0.0012, 3)
    shell = M.extrude(shell_o, 0.0012, holes=[shell_i], bevel=0.0002, bevel_segments=1, cap_bottom=False,
                      material="chrome")
    bore = cap(shell_i, 0.0005, material="gloss_black_plastic")
    tongue = M.box((0.0062, 0.0007, 0.0006), center=(0, 0, 0.0006 + 0.0003), material="gunmetal")
    out = []
    for p, nm in ((shell, "usb_shell"), (bore, "usb_bore"), (tongue, "usb_tongue")):
        if rotate:
            p = p.rotate_z(rotate)
        out.append(p.orient(facing_dir, pos).named(nm))
    return out


def dc_inlet(pos, facing_dir):
    """Round DC power inlet standing on a face: black bezel ring, dark socket, chrome centre pin."""
    bez = M.lathe([(0.0058, 0.0, 1.0, 0.0), (0.0058, 0.0016, 1.0, 0.0), (0.0054, 0.0021, 0.0, 1.0),
                   (0.0040, 0.0021, 0.0, 1.0), (0.0036, 0.0016, -1.0, 0.0), (0.0036, 0.0005, -1.0, 0.0)], 20,
                  crease=45, material="matte_black_plastic")
    floor = M.disc(0.0036, 0.0, 20, material="gloss_black_plastic").translate(0, 0, 0.0005)
    pin = M.cylinder(0.0009, 0.0013, 10, bottom=False, material="chrome").translate(0, 0, 0.0005)
    return [bez.orient(facing_dir, pos).named("dc_bezel"), floor.orient(facing_dir, pos).named("dc_bore"),
            pin.orient(facing_dir, pos).named("dc_pin")]


# --------------------------------------------------------------------------- materials / textures
def _tex(name, size, fmt="DXT1", kind="color", description=""):
    """textures.register that tolerates a second import."""
    def deco(fn):
        if not tx.exists(name):
            tx.register(name, size, fmt, kind, description)(fn)
        return fn
    return deco


def _mat(mat: Material) -> Material:
    if mat.name in mats.names():
        return mats.get(mat.name)
    return mats.register(mat)


def _ns(name, d, n, s, tile, pbr, collision, description, **params):
    return _mat(Material(name, "normal_spec", {"DiffuseSampler": d, "BumpSampler": n, "SpecSampler": s},
                         params, pbr, tile, collision, description))


# --- woven aramid / carbon twill for woofer cones (map planar along the driver axis, tile 0.032 m)
def _twill(w, h, threads=16, seed=301):
    """2/2 twill: height field, fibre streaks and which yarn is on top."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    cell = w / threads
    u, v = x / cell, y / cell
    iu, iv = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - iu, v - iv
    over = ((iu - iv) % 4) < 2                            # 2-over-2 diagonal twill
    prof = lambda t: np.sqrt(np.clip(1 - (2 * t - 1) ** 2 * 1.08, 0, 1))
    weft = prof(fv) * (0.75 + 0.25 * np.sin(math.pi * fu))
    warp = prof(fu) * (0.75 + 0.25 * np.sin(math.pi * fv))
    hm = np.where(over, weft, warp)
    fx = tx.blur(tx.white(w, h, seed), 5.0, 0.5)
    fy = tx.blur(tx.white(w, h, seed + 1), 0.5, 5.0)
    fib = tx.standardize(np.where(over, fx, fy))
    return hm, fib, over


@_tex("nz_spk_twill_d", 256, description="Woven aramid/carbon twill (woofer cones), 16 yarns per tile.")
def _twill_d(w, h):
    hm, fib, over = _twill(w, h)
    tone = 0.62 + 0.38 * hm + 0.05 * fib
    tone *= np.where(over, 1.0, 0.86)                    # yarn directions catch the light differently
    c = tx.hex_rgb("#2a2d31")[None, None, :] * tone[:, :, None]
    return np.clip(c, 0, 1)


@_tex("nz_spk_twill_n", 256, kind="normal", description="Twill weave relief.")
def _twill_n(w, h):
    hm, fib, over = _twill(w, h)
    return tx.height_to_normal(tx.blur(hm, 0.7) * 2.2 + fib * 0.05, 1.0)


@_tex("nz_spk_twill_s", 256, kind="spec", description="Twill spec: resin-coated yarn crowns are glossy.")
def _twill_s(w, h):
    hm, fib, over = _twill(w, h)
    v = 0.35 + 0.55 * hm ** 1.5 * np.where(over, 1.0, 0.8)
    return np.repeat(np.clip(v, 0, 1)[:, :, None], 3, axis=2)


# --- nylon webbing for the Echo Column strap: one texture repeat = one trip around the strap section
WEB_W, WEB_T = 0.024, 0.0032          # strap width / thickness (m)
WEB_R = 0.0011                        # section corner radius
WEB_RIBS = 26                         # weave ribs per texture repeat (one repeat = 52 mm of strap)


def web_section():
    """Strap cross-section: x = width (sweep frame normal), y = thickness (binormal)."""
    return M.rounded_rect_2d(WEB_W, WEB_T, WEB_R, 3)


def _web_layout():
    """Perimeter positions (fraction 0..1 of the section loop) of the two broad faces."""
    sec = M.ensure_ccw_2d(M._dedupe_2d(np.asarray(web_section(), float)))
    e = np.roll(sec, -1, axis=0) - sec
    L = np.concatenate([[0.0], np.cumsum(np.linalg.norm(e, axis=1))])
    return sec, L


@_tex("nz_spk_webbing_d", (256, 256), description="Charcoal nylon webbing with teal edge tracers; u = around the "
                                                  "strap section, v = along the strap.")
def _webbing_d(w, h):
    sec, L = _web_layout()
    total = L[-1]
    x = (np.arange(w) + 0.5) / w * total                   # perimeter coordinate of each column
    # for each column: position across the broad face (y of the section point)
    loop = np.vstack([sec, sec[:1]])
    px = np.interp(x, L, loop[:, 0])                       # across the width
    py = np.interp(x, L, loop[:, 1])                       # through the thickness
    across = np.clip(np.abs(px) / (WEB_W / 2), 0, 1)       # 0 centre .. 1 edge
    yy = (np.arange(h) + 0.5)[:, None] * np.ones((1, w))
    ribs = 0.5 + 0.5 * np.sin(yy / h * 2 * math.pi * WEB_RIBS)
    fib = tx.standardize(tx.blur(tx.white(w, h, 331), 0.6, 4.0))
    tone = 0.80 + 0.16 * ribs + 0.05 * fib
    base = tx.hex_rgb("#26292c")[None, None, :] * tone[:, :, None]
    teal = tx.hex_rgb(tx.TEAL)[None, None, :] * (0.85 + 0.15 * ribs[:, :, None])
    on_face = (np.abs(py) > WEB_T / 2 - WEB_R * 0.3)[None, :]
    stripe = (np.abs(across - 0.80) < 0.055)[None, :] & on_face
    return np.clip(np.where(stripe[:, :, None], teal, base), 0, 1)


@_tex("nz_spk_webbing_n", (256, 256), kind="normal", description="Webbing ribs (across the strap).")
def _webbing_n(w, h):
    yy = (np.arange(h) + 0.5)[:, None] * np.ones((1, w))
    ribs = np.sin(yy / h * 2 * math.pi * WEB_RIBS)
    fib = tx.standardize(tx.blur(tx.white(w, h, 332), 0.8, 4.0))
    return tx.height_to_normal(ribs * 1.6 + fib * 0.05, 0.5)


# --- box-X stitching where the strap is sewn round its anchor pin (decal, white/teal thread on alpha)
@_tex("nz_spk_stitch", (128, 128), fmt="DXT5", description="Box-X bar-tack stitch in teal thread (decal).")
def _stitch(w, h):
    ss = 4
    img = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    W, H = w * ss, h * ss
    col = tuple(int(v * 255) for v in tx.hex_rgb(tx.TEAL_HI)) + (235,)
    m = 0.12
    box = [(W * m, H * m), (W * (1 - m), H * m), (W * (1 - m), H * (1 - m)), (W * m, H * (1 - m))]

    def dashed(p0, p1, n):
        for k in range(n):
            a, b = k / n, (k + 0.62) / n
            d.line([(p0[0] + (p1[0] - p0[0]) * a, p0[1] + (p1[1] - p0[1]) * a),
                    (p0[0] + (p1[0] - p0[0]) * b, p0[1] + (p1[1] - p0[1]) * b)], fill=col, width=int(3.2 * ss))
    for i in range(4):
        dashed(box[i], box[(i + 1) % 4], 9)
    dashed(box[0], box[2], 12)
    dashed(box[1], box[3], 12)
    return np.asarray(img.reduce(ss), np.float32) / 255.0


@_tex("nz_spk_spec_low", (16, 16), kind="spec", description="Low spec (webbing).")
def _spec_low(w, h):
    return np.full((h, w, 3), 0.4, np.float32)


_ns("spk_cone_twill", "nz_spk_twill_d", "nz_spk_twill_n", "nz_spk_twill_s", 0.032,
    PBR(roughness=0.38), "PLASTIC", "Resin-coated woven twill woofer cone (map planar along the driver axis).",
    specularIntensityMult=0.7, specularFalloffMult=90.0, specularFresnel=0.93, bumpiness=1.0)
_ns("spk_webbing", "nz_spk_webbing_d", "nz_spk_webbing_n", "nz_spk_spec_low", 1.0,
    PBR(roughness=0.78), "CARPET_SOLID",
    "Nylon webbing strap with teal tracers; sweep with tile = section perimeter (u around, v along).",
    specularIntensityMult=0.22, specularFalloffMult=18.0, specularFresnel=0.82, bumpiness=1.0)
_mat(Material("spk_stitch", "decal", {"DiffuseSampler": "nz_spk_stitch"}, {}, PBR(roughness=0.7, alpha_mode="BLEND"),
              1.0, "PLASTIC", "Bar-tack stitching decal (UV 0..1)."))


def web_tile() -> float:
    sec, L = _web_layout()
    return float(L[-1])


# --------------------------------------------------------------------------- domes
def _dome_circle(rim_r, rim_z, apex_z):
    s = apex_z - rim_z
    R = (rim_r * rim_r + s * s) / (2.0 * s)
    return R, apex_z - R


def dome_z(rim_r, rim_z, apex_z, r):
    """Height of the spherical dome through (rim_r, rim_z) with its apex at apex_z, at radius r."""
    R, zc = _dome_circle(rim_r, rim_z, apex_z)
    return zc + math.sqrt(R * R - r * r)


def dome(rim_r, rim_z, apex_z, n: int = 4, r_end: float = 0.0):
    """Lathe profile (rim -> centre, explicit normals) of a spherical dome; stops at radius r_end."""
    R, zc = _dome_circle(rim_r, rim_z, apex_z)
    a0 = math.degrees(math.atan2(rim_z - zc, rim_r))
    a1 = 90.0 if r_end <= 0 else math.degrees(math.acos(r_end / R))
    prof = M.arc_profile((0.0, zc), R, a0, a1, n)
    if r_end <= 0:
        prof[-1] = (0.0, apex_z, 0.0, 1.0)
    return prof


def sdf_cylinder_z(center_xy, radius, z0, z1):
    """SDF of a vertical cylinder (negative inside)."""
    cx, cy = center_xy

    def f(p):
        p = np.asarray(p, float)
        dr = np.hypot(p[:, 0] - cx, p[:, 1] - cy) - radius
        dz = np.maximum(z0 - p[:, 2], p[:, 2] - z1)
        out = np.stack([dr, dz], axis=1)
        return np.linalg.norm(np.maximum(out, 0.0), axis=1) + np.minimum(out.max(axis=1), 0.0)
    return f


def cyl_decal(entry: str, z: float, radius: float, height: float, angle0: float = 90.0, offset: float = DECAL_OFF,
              material: str = "print_decal", segments: int = 8) -> M.Mesh:
    """Print-atlas decal bent around a vertical cylinder (centred on the ``angle0`` direction)."""
    w = height * tx.atlas_aspect(entry)
    m = M.plane(w, height, center=(0.0, z, offset), facing="design", segments=(segments, 1),
                rect=tx.atlas_rect(entry), material=material)
    return wrap_cyl(m, radius, angle0).named("decal")


# --- lighter graphite powder-coat grille (the shared round-hole grille, metal lifted so the holes read)
@_tex("nz_spk_grille_d", 512, description="Graphite powder-coated perforated steel (round holes), lighter than "
                                          "nz_grille_round_d so the perforation reads on dark props.")
def _grille_graphite_d(w, h):
    src = np.asarray(tx.image("nz_grille_round_d"), np.float32)[:, :, :3]
    if src.shape[0] != h or src.shape[1] != w:
        src = np.asarray(Image.fromarray((src * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS),
                         np.float32) / 255.0
    lum = src.mean(axis=2, keepdims=True)
    metal = np.clip((lum - 0.02) / 0.10, 0.0, 1.0)            # 0 in the holes, 1 on the metal
    return np.clip(src * (1.0 + 1.05 * metal), 0, 1)


_ns("spk_grille_graphite", "nz_spk_grille_d", "nz_grille_round_n", "nz_grille_round_s", 0.064,
    PBR(metallic=0.5, roughness=0.45), "METAL_SOLID_SMALL",
    "Graphite powder-coated perforated steel grille, round holes (map planar).",
    specularIntensityMult=0.7, specularFalloffMult=55.0, specularFresnel=0.9, bumpiness=1.0)
