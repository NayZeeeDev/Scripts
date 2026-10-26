"""
The bags. Each design returns one Mesh (UVs already in atlas space) built
around the grip: the top of the handles sits at the origin, the bag hangs
below it (-Z), front faces -Y here (build.py turns it to +Y, the way GTA
props face). Sizes are in metres, from real bags.
"""
import math

import numpy as np

import mesh as M
from textures import BODY, TRIM, METAL, S

PPM = 1300                      # body texture pixels per metre (prints keep real scale)
DENS = PPM / S                  # uv units per metre


def sub(region, du=0.0, dv=0.0, w=None, h=None):
    """A slice of a region (keeps the same texel scale)."""
    u0, v0, u1, v1 = region
    return (u0 + du, v0 + dv, u0 + du + (w or (u1 - u0 - du)), v0 + dv + (h or (v1 - v0 - dv)))


def handles(mesh, xs, ys, z0, height, r, region=TRIM, lean=0.0):
    for y in ys:
        path = M.arc_path((-xs, y, z0), (xs, y, z0), height, n=36, bow=lean * (1 if y > 0 else -1))
        mesh.add(M.sweep(path, r, sides=10, region=region))


def rings_and_tabs(mesh, pts, tab=(0.026, 0.024, 0.006), ring=0.008, tab_region=TRIM, metal=METAL):
    for (x, y, z) in pts:
        t = M.box(*tab, region=tab_region); t.transform(t=(x, y, z))
        mesh.add(t)
        rg = M.torus(ring, ring * 0.28, region=metal, sides=6, n=16); rg.transform(t=(x, y, z + ring * 0.9))
        mesh.add(rg)


def feet(mesh, pts, r=0.0065):
    for p in pts:
        s = M.sphere(r, n=8, region=METAL, scale=(1, 1, 0.55)); s.transform(t=p)
        mesh.add(s)


def zipper(mesh, path, w=0.0045):
    mesh.add(M.sweep(path, w, sides=6, region=METAL, flat=0.35))


def padlock(mesh, at):
    x, y, z = at
    body = M.box(0.022, 0.010, 0.024, r=0.004, region=METAL); body.transform(t=(x, y, z))
    shackle = M.sweep([np.array((x - 0.006 + 0.012 * k / 12, y, z + 0.012 + 0.012 * math.sin(math.pi * k / 12))) for k in range(13)], 0.0018, sides=6, region=METAL)
    mesh.add(body); mesh.add(shackle)


# ---------------------------------------------------------------------------
# 1. Barrel bag: soft doctor-style barrel, rolled handles, piped ends
# ---------------------------------------------------------------------------
def barrel(scale=1.0):
    m = M.Mesh()
    L, D, H = 0.32 * scale, 0.15 * scale, 0.19 * scale
    hh = 0.105 * scale                       # handle rise above the body
    zc = -(hh + H / 2)
    sec = M.rounded_rect(D, H, 0.055 * scale, n=72, bulge=0.05)
    body = M.pillow(sec, L, k=7, nt=44, region=BODY, density=DENS, axis='x', swell=0.03)
    body.transform(t=(0, 0, zc)); m.add(body)

    # piping round both ends
    for sx in (-1, 1):
        t = 0.9; s = (1 - t ** 7) ** (1 / 7) * (1 + 0.03 * (1 - t * t)) * 1.01
        ring = [np.array((sx * t * L / 2, y * s, zc + z * s)) for (y, z) in sec[::2]]
        m.add(M.sweep(ring + [ring[0]], 0.0035 * scale, sides=6, region=TRIM))

    ztop = zc + H / 2 + 0.002
    hx, hy = 0.085 * scale, 0.034 * scale
    handles(m, hx, (hy, -hy), ztop - 0.004, hh + 0.004, 0.0075 * scale)
    rings_and_tabs(m, [(sx * hx, sy * hy, ztop) for sx in (-1, 1) for sy in (-1, 1)])
    zipper(m, [np.array((x, 0, ztop + 0.001)) for x in np.linspace(-L * 0.44, L * 0.44, 30)])
    pull = M.box(0.012, 0.004, 0.022, r=0.002, region=METAL); pull.transform(t=(L * 0.44, -0.004, ztop - 0.012))
    m.add(pull)
    feet(m, [(sx * L * 0.33, sy * D * 0.3, zc - H / 2 - 0.002) for sx in (-1, 1) for sy in (-1, 1)])
    return m


# ---------------------------------------------------------------------------
# 2. Dome satchel: bowling-bag arch, zip over the dome, padlock fob
# ---------------------------------------------------------------------------
def dome_satchel(scale=1.0):
    m = M.Mesh()
    W, H, D = 0.30 * scale, 0.20 * scale, 0.13 * scale
    hh = 0.10 * scale
    sec = M.dome(W, H, flat=0.25, n=80)
    top = max(y for _, y in sec)
    zoff = -(hh + top)
    # round the ends about the section's middle, not its base, so the rim is even
    yc = (top + min(y for _, y in sec)) / 2
    sec = [(x, y - yc) for x, y in sec]
    body = M.pillow(sec, D, k=5, nt=36, region=BODY, density=DENS, axis='y', swell=0.03)
    body.transform(t=(0, 0, zoff + yc)); m.add(body)

    def topz(x):
        c = max(-1.0, min(1.0, x / (W / 2)))
        return zoff + H * (math.sin(math.acos(c)) ** 0.85)

    hx, hy = 0.068 * scale, 0.026 * scale
    z0 = topz(hx)
    handles(m, hx, (hy, -hy), z0 - 0.004, -z0 + 0.004, 0.0075 * scale)
    rings_and_tabs(m, [(sx * hx, sy * hy, z0) for sx in (-1, 1) for sy in (-1, 1)])
    arch = [np.array((W / 2 * math.cos(a) * 0.98, 0, topz(W / 2 * math.cos(a) * 0.98) + 0.002)) for a in np.linspace(math.radians(18), math.radians(162), 40)]
    zipper(m, arch)
    # key fob: leather strap from the right handle with a little padlock
    fy = -D / 2 - 0.012 * scale                # just proud of the front face
    fob = [np.array((hx + 0.004, -hy - 0.006, z0 + 0.004)), np.array((hx + 0.012, fy - 0.01, z0 + 0.002)),
           np.array((hx + 0.016, fy, z0 - 0.03)), np.array((hx + 0.018, fy, z0 - 0.06))]
    m.add(M.sweep(M.bezier(fob, 16), 0.0045 * scale, sides=6, region=TRIM, flat=0.3))
    padlock(m, (hx + 0.018, fy, z0 - 0.074))
    zb = zoff - 0.25 * H
    feet(m, [(sx * W * 0.32, sy * D * 0.28, zb - 0.002) for sx in (-1, 1) for sy in (-1, 1)])
    return m


# ---------------------------------------------------------------------------
# 3. Croc top-handle: structured trapezoid, front flap, clasp plate
# ---------------------------------------------------------------------------
def tophandle(scale=1.0, W=0.30, D=0.14, H=0.22, flap=True, hearts=False):
    m = M.Mesh()
    W, D, H = W * scale, D * scale, H * scale
    hh = 0.10 * scale
    zc = -(hh + H / 2)
    sec = M.rounded_rect(W, D, 0.025 * scale, n=80, bulge=0.04)
    body = M.pillow(sec, H, k=14, nt=30, region=BODY, density=DENS, axis='z', swell=0.02,
                    taper=lambda t: 1 - 0.10 * (t + 1) / 2)
    body.transform(t=(0, 0, zc)); m.add(body)
    ztop = zc + H / 2
    hx, hy = 0.062 * scale, 0.03 * scale
    handles(m, hx, (hy, -hy), ztop - 0.004, hh + 0.004, 0.008 * scale)
    rings_and_tabs(m, [(sx * hx, sy * hy, ztop) for sx in (-1, 1) for sy in (-1, 1)])
    if flap:
        f = M.box(W * 0.80, 0.008, 0.075 * scale, r=0.003, region=sub(BODY, w=0.3, h=0.2), density=DENS)
        f.transform(M.rot_x(-7), (0, -D / 2 - 0.006, ztop - 0.038 * scale)); m.add(f)
        plate = M.box(0.036 * scale, 0.006, 0.02 * scale, r=0.003, region=METAL)
        plate.transform(t=(0, -D / 2 - 0.013, ztop - 0.07 * scale)); m.add(plate)
    if hearts:
        for (x, y, z, s) in ((-hx, -hy - 0.012, ztop - 0.03, 1.0), (hx, -hy - 0.012, ztop - 0.03, 1.0), (0, -D / 2 - 0.012, ztop - 0.05, 1.3)):
            hm = M.pillow(M.heart(0.03 * s * scale, 0.028 * s * scale), 0.007, k=4, nt=8, region=METAL, axis='y')
            hm.transform(t=(x, y, z - 0.03 * s)); m.add(hm)
            if abs(x) > 0:
                m.add(M.sweep([np.array((x, y + 0.006, ztop)), np.array((x, y, z - 0.012))], 0.004, sides=6, region=TRIM, flat=0.3))
    feet(m, [(sx * W * 0.4, sy * D * 0.32, zc - H / 2 - 0.002) for sx in (-1, 1) for sy in (-1, 1)])
    return m


# ---------------------------------------------------------------------------
# 4. Crochet hobo: soft rounded body, wide knitted handle
# ---------------------------------------------------------------------------
def crochet_hobo(scale=1.0):
    m = M.Mesh()
    W, D, H = 0.30 * scale, 0.11 * scale, 0.22 * scale
    hh = 0.12 * scale
    zc = -(hh + H / 2)
    sec = M.superellipse(W, D, e=2.4, n=80)
    body = M.pillow(sec, H, k=3.2, nt=34, region=BODY, density=DENS, axis='z', swell=0.10,
                    taper=lambda t: 1 - 0.16 * (t + 1) / 2)
    body.transform(t=(0, 0, zc)); m.add(body)
    ztop = zc + H / 2
    path = M.arc_path((-W * 0.33, 0, ztop - 0.025), (W * 0.33, 0, ztop - 0.025), hh + 0.025, n=40)
    m.add(M.sweep(path, 0.03 * scale, sides=14, region=sub(BODY, du=0.0, dv=0.6, w=0.25, h=0.35), flat=0.32))
    return m


# ---------------------------------------------------------------------------
# 5. Weekender duffel: big barrel, leather wraps, luggage tag
# ---------------------------------------------------------------------------
def weekender(scale=1.0):
    m = M.Mesh()
    L, D, H = 0.50 * scale, 0.24 * scale, 0.27 * scale
    hh = 0.14 * scale
    zc = -(hh + H / 2)
    sec = M.rounded_rect(D, H, 0.08 * scale, n=80, bulge=0.04)
    body = M.pillow(sec, L, k=9, nt=46, region=BODY, density=DENS, axis='x', swell=0.02)
    body.transform(t=(0, 0, zc)); m.add(body)
    ztop = zc + H / 2 + 0.003
    hx, hy = 0.10 * scale, 0.045 * scale
    # leather wraps under the handles, round the whole body
    for sx in (-1, 1):
        ring = [np.array((sx * hx, y * 1.02, zc + z * 1.02)) for (y, z) in sec[::2]]
        m.add(M.sweep(ring + [ring[0]], 0.013 * scale, sides=8, region=TRIM, flat_n=0.22, twist_up=(1, 0, 0)))
    handles(m, hx, (hy, -hy), ztop - 0.004, hh + 0.004, 0.0105 * scale)
    rings_and_tabs(m, [(sx * hx, sy * hy, ztop) for sx in (-1, 1) for sy in (-1, 1)], tab=(0.03, 0.03, 0.007), ring=0.011)
    zipper(m, [np.array((x, 0, ztop + 0.001)) for x in np.linspace(-L * 0.45, L * 0.45, 36)], w=0.006)
    # luggage tag
    m.add(M.sweep([np.array((hx + 0.006, -hy - 0.01, ztop)), np.array((hx + 0.02, -hy - 0.03, ztop - 0.05))], 0.005, sides=6, region=TRIM, flat=0.3))
    tag = M.box(0.05 * scale, 0.006, 0.07 * scale, r=0.008, region=TRIM)
    tag.transform(M.rot_z(10), (hx + 0.028, -hy - 0.034, ztop - 0.09)); m.add(tag)
    feet(m, [(sx * L * 0.36, sy * D * 0.3, zc - H / 2 - 0.003) for sx in (-1, 1) for sy in (-1, 1)], r=0.009)
    return m


DESIGNS = {
    'barrel': barrel,
    'dome': dome_satchel,
    'tophandle': tophandle,
    'sweetheart': lambda: tophandle(W=0.28, D=0.13, H=0.20, flap=False, hearts=True),
    'crochet': crochet_hobo,
    'weekender': weekender,
}
