"""
nz_amb_bay_shell - the walk-in ambulance treatment bay interior (a closed room prop).

Room (inside): 2.30 W (X) x 4.30 L (Y) x 2.05 H (Z), origin = floor centre, +Y = towards the cab
(bulkhead), -Y = rear doors. Patient side (stretcher + O2 panel) on -X, bench + counter on +X.

Texture sets:
    shell  walls / floor / ceiling                        <name>_shell_d/_n/_s   2048 (normal / spec 1024)
    main   furniture, doors, fixtures                     <name>_d/_n/_s         2048 (normal / spec 1024)
    supl   left supply cabinets + their labelled stock    <name>_supl_d/_n/_s    1024
    supr   right supply cabinets + their labelled stock   <name>_supr_d/_n/_s    1024
    alpha  cabinet glass                                  <name>_ad/_an/_as       512
    glow   ceiling panels, under-cabinet LEDs             <name>_g                128
    screen bulkhead monitor 'nz_amb_screen' 512 x 256 (dark standby; DUI-replaceable)
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import (TEAL, DecalCanvas, Geo, box, catmull, cylinder, extrude, lathe, pillow, polyline_fillet, prop, quad, rrect,
                     sweep, torus, tube)

from .common import (align, biohazard, caution_label, cross_mark, knob, label_canvas, m_alu, m_black_plastic, m_chrome,
                     m_gloss_black, m_led, m_webbing, rating_plate)
from .parts import m_hosp_dark, m_hosp_grey, m_hosp_white
from .screens import draw_bay_monitor

# ---------------------------------------------------------------------------------------------
# layout constants (prop space, metres)
# ---------------------------------------------------------------------------------------------
BAY_W, BAY_L, BAY_H = 2.30, 4.30, 2.05
XW = BAY_W / 2          # side walls at x = +-1.15
YR = -BAY_L / 2         # rear doors wall
YF = BAY_L / 2          # cab bulkhead
CAB_D = 0.34            # cabinet depth (wall -> front plane)
CAB_RAIL_B = (1.34, 1.39)   # bottom front rail (label strip of the lower row)
CAB_FLOOR_L = 1.38          # lower row floor
CAB_SHELF = (1.69, 1.71)    # middle shelf
CAB_RAIL_M = (1.69, 1.735)  # middle front rail (label strip of the upper row)
CAB_TOP = 2.01              # underside of the top rail
BAYS_L = np.linspace(-1.85, 1.95, 7)    # left wall bay edges (y)
BAYS_R = np.linspace(-1.85, 2.15, 7)    # right wall bay edges (y)
STRETCHER = (-0.42, 0.10)               # nz_amb_stretcher origin (x, y), heading 0 (head end towards +Y)
IV_RAIL_X = -0.18
IV_HOOKS = ((IV_RAIL_X, 0.95, 1.86), (IV_RAIL_X, -0.30, 1.86))
BENCH = (0.70, -1.75, 0.85)             # x front, y from, y to
SEAT_Z = 0.50
COUNTER = (0.72, 0.95, 0.95)            # x front, y from, top z
MON_C = (-0.20, YF - 0.0455, 1.68)       # bulkhead monitor screen centre
MON_SCREEN = (0.84, 0.40)
PM_SHELF = (-1.15 + 0.13, 0.30, 1.10)    # patient-monitor wall shelf (x centre, y, top z)
EXIT = (0.0, -1.90, 0.0)
MEDIC_SPAWN = (0.30, -1.62, 0.0)
LIGHTS = ((0.0, -1.0, 1.95), (0.0, 0.95, 1.95))

CAT_COLORS = {
    "BANDAGES": (34, 112, 206), "GAUZE & DRESSINGS": (30, 140, 210), "IV FLUIDS": (40, 104, 220),
    "SYRINGES & NEEDLES": (8, 160, 148), "IV ACCESS & EXTENSION SETS": (224, 150, 10),
    "OXYGEN MASKS & NASAL CANNULA": (36, 160, 84), "CPAP / BVM": (60, 110, 200), "CERVICAL COLLARS": (226, 182, 18),
    "SPINAL IMMOBILIZATION": (232, 106, 26), "AIRWAY & RESUSCITATION": (138, 78, 196), "BURN CARE": (222, 74, 40),
    "TRAUMA SUPPLIES": (196, 30, 36), "MEDICAL TAPE & WRAP": (104, 116, 128),
}
# (wall, bay index 0 = rear, row) -> category
ASSIGN = {
    ("l", 0, "U"): "BANDAGES", ("l", 0, "L"): "GAUZE & DRESSINGS",
    ("l", 1, "U"): "MEDICAL TAPE & WRAP", ("l", 1, "L"): "BURN CARE",
    ("l", 2, "U"): "TRAUMA SUPPLIES", ("l", 2, "L"): "TRAUMA SUPPLIES",
    ("l", 3, "U"): "IV FLUIDS", ("l", 3, "L"): "IV ACCESS & EXTENSION SETS",
    ("l", 4, "U"): "SYRINGES & NEEDLES", ("l", 4, "L"): "IV FLUIDS",
    ("l", 5, "U"): "AIRWAY & RESUSCITATION", ("l", 5, "L"): "OXYGEN MASKS & NASAL CANNULA",
    ("r", 0, "U"): "SPINAL IMMOBILIZATION", ("r", 0, "L"): "SPINAL IMMOBILIZATION",
    ("r", 1, "U"): "CERVICAL COLLARS", ("r", 1, "L"): "CERVICAL COLLARS",
    ("r", 2, "U"): "CPAP / BVM", ("r", 2, "L"): "OXYGEN MASKS & NASAL CANNULA",
    ("r", 3, "U"): "GAUZE & DRESSINGS", ("r", 3, "L"): "BANDAGES",
    ("r", 4, "U"): "SYRINGES & NEEDLES", ("r", 4, "L"): "IV ACCESS & EXTENSION SETS",
    ("r", 5, "U"): "AIRWAY & RESUSCITATION", ("r", 5, "L"): "MEDICAL TAPE & WRAP",
}
PRODUCTS = {
    "BANDAGES": ["CREPE 10 cm", "CREPE 7.5 cm", "TRIANGULAR", "ELASTIC 15 cm"],
    "GAUZE & DRESSINGS": ["GAUZE 10x10", "ABD PAD 20x25", "NON-ADHERENT", "GAUZE ROLL", "DRESSING PAD"],
    "IV FLUIDS": ["NaCl 0.9%", "LACTATED RINGER", "NaCl 0.9%", "GLUCOSE 5%", "NaCl 0.9%"],
    "SYRINGES & NEEDLES": ["SYRINGE 10 mL", "SYRINGE 5 mL", "SYRINGE 20 mL", "NEEDLE 18G", "NEEDLE 21G"],
    "IV ACCESS & EXTENSION SETS": ["IV CATH 18G", "IV CATH 20G", "EXT SET", "GIVING SET", "IO NEEDLE"],
    "OXYGEN MASKS & NASAL CANNULA": ["NRB MASK", "NASAL CANNULA", "NEB MASK", "NRB MASK"],
    "CPAP / BVM": ["BVM ADULT", "CPAP 10", "BVM PAED", "PEEP VALVE"],
    "CERVICAL COLLARS": ["ADJ ADULT", "ADJ ADULT", "PAED", "NO-NECK"],
    "SPINAL IMMOBILIZATION": ["HEAD BLOCKS", "SPIDER STRAP", "STRAPS x4", "VACUUM SPLINT"],
    "AIRWAY & RESUSCITATION": ["OPA SET", "NPA SET", "ETT 7.5", "ETT 8.0", "LMA 4"],
    "BURN CARE": ["BURN GEL", "BURN DRESS 20x20", "FOIL BLANKET", "CLING FILM"],
    "TRAUMA SUPPLIES": ["TRAUMA DRESSING", "HEMOSTATIC GAUZE", "CHEST SEAL", "TOURNIQUET"],
    "MEDICAL TAPE & WRAP": ["TAPE 2.5 cm", "TAPE 5 cm", "COHESIVE WRAP"],
}
INK = (32, 35, 38)


def _lighten(c, k):
    return tuple(int(v + (255 - v) * k) for v in c)


class Wall:
    """Mapping for one long wall: slot-local (u along the viewer's right, d out of the wall, z) -> prop space.
    left wall (-X): faces +X, the viewer's right is +Y; right wall (+X): faces -X, the viewer's right is -Y."""

    def __init__(self, b, side):
        self.b = b
        self.side = side
        self.n = 1.0 if side == "l" else -1.0
        self.r = 1.0 if side == "l" else -1.0
        self.xw = -XW if side == "l" else XW
        self.layer = "sup" + side
        self.front = "+x" if side == "l" else "-x"
        self.edges = BAYS_L if side == "l" else BAYS_R
        self.normal = (self.n, 0.0, 0.0)

    def mat(self, name, **kw):
        return self.b.mat(f"{name}_{self.side}", layer=self.layer, **kw)

    def x(self, d):
        return self.xw + self.n * d

    def slot_left_y(self, bay):
        """y where u = 0 for a bay (the viewer's left edge)."""
        return self.edges[bay] if self.side == "l" else self.edges[bay + 1]

    def P(self, bay, u, d, z):
        return (self.x(d), self.slot_left_y(bay) + self.r * u, z)

    def box(self, bay, u0, w, d0, d1, z0, h, mat, r=0.0, seg=1, front=2.0, rest=0.45, faces=None, tag=""):
        """Axis box spanning u0..u0+w along the wall, d0..d1 out of it, z0..z0+h."""
        cx = self.x((d0 + d1) / 2)
        cy = self.slot_left_y(bay) + self.r * (u0 + w / 2)
        fs = faces or f"{self.front} +z +y -y"
        return box((d1 - d0, w, h), mat, r=r, seg=seg, center=(cx, cy, z0 + h / 2), faces=fs,
                   density=rest, face_density={self.front: front}, tag=tag)


# ---------------------------------------------------------------------------------------------
# supply stock generators (geometry + the printed front canvas of one cabinet slot)
# ---------------------------------------------------------------------------------------------
def _carton_print(cv, x, y, w, h, name, col, seed):
    """Printed carton face at canvas (x, y) size w x h."""
    body = ((244, 245, 244), (236, 240, 244), (246, 244, 238), _lighten(col, 0.86))[seed % 4]
    cv.rect(x, y, w, h, r=0.002, color=body, spec=0.25, gloss=0.4)
    band = min(h * 0.30, 0.036)
    cv.rect(x, y + h * 0.10, w, band, color=col, spec=0.3, gloss=0.45)
    fs = min(band * 0.46, w * 0.10)
    cv.text(x + w / 2, y + h * 0.10 + band / 2, name, fs, fnt="label", color=(255, 255, 255), max_w=w * 0.88, spacing=fs * 0.06)
    ms = min(w * 0.14, h * 0.18, 0.018)
    cv.cross(x + w * 0.08 + ms * 0.5, y + h * 0.10 + band + h * 0.08 + ms * 0.5, ms * 0.8, color=col)
    cv.text(x + w * 0.08 + ms * 1.3, y + h * 0.10 + band + h * 0.08 + ms * 0.5, ("STERILE", "SINGLE USE", "LATEX FREE", "MEDICAL")[seed % 4],
            ms * 0.42, fnt="label", anchor="lm", color=INK, max_w=w * 0.6)
    rng = np.random.default_rng(seed)
    if h > 0.08:
        qty = ("50 PCS", "25 PCS", "100 PCS", "10 PCS", "STERILE", "SINGLE USE")[int(rng.integers(0, 6))]
        cv.text(x + w * 0.08, y + h * 0.80, qty, min(h * 0.07, 0.008), fnt="label-semi", anchor="lm", color=(90, 96, 100), max_w=w * 0.84)
        bx = x + w * 0.62
        while bx < x + w * 0.92:
            bw = 0.0006 + rng.random() * 0.0012
            cv.rect(bx, y + h * 0.66, bw, h * 0.12, color=INK)
            bx += bw + 0.0006 + rng.random() * 0.001


def _fill_slot(wl: Wall, bay, row, cat):
    """Build the stock of one cabinet slot and return its front canvas + where to project it."""
    y0e, y1e = wl.edges[bay], wl.edges[bay + 1]
    width = (y1e - y0e) - 0.024
    u_off = 0.012
    z0 = CAB_FLOOR_L if row == "L" else CAB_SHELF[1]
    zt = CAB_SHELF[0] if row == "L" else CAB_TOP
    hav = zt - z0 - 0.01
    col = CAT_COLORS[cat]
    seed = (0 if wl.side == "l" else 50) + bay * 7 + (0 if row == "L" else 3)
    rng = np.random.default_rng(seed)
    names = PRODUCTS[cat]
    cv = DecalCanvas(width, hav, ppm=1500)
    card = wl.mat("carton", color=(244, 245, 244), spec=0.22, gloss=0.38, edge=0.15, grain=0.015)
    printed = [card]
    g = Geo()
    cz = z0
    dfront = 0.30

    def ctop(z):
        return zt - 0.01 - z    # canvas y of a world z (canvas top = zt - 0.01)

    kind = {"BANDAGES": "rolls", "MEDICAL TAPE & WRAP": "tape", "IV FLUIDS": "bags", "OXYGEN MASKS & NASAL CANNULA": "pouch",
            "CPAP / BVM": "bvm", "CERVICAL COLLARS": "collars", "SPINAL IMMOBILIZATION": "spinal", "TRAUMA SUPPLIES": "trauma"}.get(cat, "cartons")
    u = 0.0
    k = 0

    def carton(u_, w_, h_, dd, name, colr):
        g.charts.extend(wl.box(bay, u_off + u_, w_, dfront - dd, dfront, cz, h_, card, r=0.002, seg=1).charts)
        _carton_print(cv, u_, ctop(cz + h_), w_, h_, name, colr, seed + int(u_ * 1000))

    if kind == "cartons":
        while u < width - 0.07:
            w_ = float(min(width - u, rng.uniform(0.11, 0.17)))
            if width - u - w_ < 0.07:
                w_ = width - u
            h_ = float(rng.uniform(0.55, 0.92) * hav)
            dd = float(rng.uniform(0.17, 0.26))
            carton(u, w_ - 0.006, h_, dd, names[k % len(names)], col)
            u += w_
            k += 1
    elif kind == "trauma":
        # red cartons + a row of rolled tourniquets
        while u < width * 0.62:
            w_ = float(rng.uniform(0.11, 0.15))
            h_ = float(rng.uniform(0.6, 0.85) * hav)
            carton(u, w_ - 0.006, h_, float(rng.uniform(0.18, 0.24)), names[k % 3], col)
            u += w_
            k += 1
        blk = wl.mat("tq_black", color=(30, 31, 33), spec=0.18, gloss=0.25, bump="webbing", bump_amp=0.00012, bump_scale=0.0015, edge=0.15)
        red = wl.mat("tq_red", color=(200, 34, 40), spec=0.35, gloss=0.5, edge=0.2)
        printed += [blk]
        while u < width - 0.05:
            for lvl in range(2):
                zz = cz + lvl * 0.075
                g.charts.extend(wl.box(bay, u_off + u, 0.045, dfront - 0.20, dfront, zz, 0.07, blk, r=0.008, seg=2).charts)
                g.charts.extend(wl.box(bay, u_off + u + 0.012, 0.02, dfront - 0.005, dfront + 0.004, zz + 0.04, 0.025, red, r=0.003,
                                       seg=1, faces=f"{wl.front} +z +y -y").charts)
                cv.rect(u + 0.004, ctop(zz + 0.022), 0.037, 0.014, r=0.002, color=(214, 216, 216))
                cv.text(u + 0.0225, ctop(zz + 0.015), "TQ", 0.006, fnt="label", color=INK)
            u += 0.05
    elif kind == "rolls":
        crepe = wl.mat("crepe", color=(240, 232, 214), spec=0.06, gloss=0.12, bump="fabric", bump_amp=0.0001, bump_scale=0.0015,
                       grain=0.04, grain_scale=0.02, edge=0.1, color2=(226, 216, 196))
        # two tiers of standing rolls on the left, cartons on the right
        nroll = int((width * 0.55) // 0.075)
        for lvl in range(2):
            for i in range(nroll):
                rr = 0.034
                cx_, cy_, _ = wl.P(bay, u_off + 0.04 + i * 0.075, dfront - 0.05, 0)
                g += cylinder(rr, 0.095, crepe, segs=18, bevel=0.004, z0=cz + lvl * 0.10).translate(cx_, cy_, 0).set_density(0.7)
                if lvl == 0 and i % 2 == 0:
                    cv.rect(u + 0.04 + i * 0.075 - 0.02, ctop(cz + 0.07), 0.04, 0.028, r=0.002, color=(250, 250, 250))
                    cv.rect(u + 0.04 + i * 0.075 - 0.02, ctop(cz + 0.07), 0.04, 0.008, color=col)
                    cv.text(u + 0.04 + i * 0.075, ctop(cz + 0.052), "10cm", 0.0055, fnt="label", color=INK)
        printed += [crepe]
        u = nroll * 0.075 + 0.01
        while u < width - 0.07:
            w_ = float(min(width - u, rng.uniform(0.12, 0.16)))
            carton(u, w_ - 0.006, float(rng.uniform(0.6, 0.85) * hav), 0.2, names[k % len(names)], col)
            u += w_
            k += 1
    elif kind == "tape":
        cols = [(242, 242, 240), (8, 160, 148), (232, 216, 190), (60, 110, 200), (242, 242, 240), (226, 80, 60)]
        core = wl.mat("tape_core", color=(222, 214, 196), spec=0.1, gloss=0.2, edge=0.1)
        u = 0.0
        ncol = int((width * 0.62) // 0.075)
        for i in range(ncol):
            for lvl in range(3):
                c = cols[(i + lvl) % len(cols)]
                tm = wl.mat(f"tape{(i + lvl) % len(cols)}", color=c, spec=0.3, gloss=0.45, edge=0.15)
                ro, ri, tw = 0.034, 0.019, 0.026
                prof = [(ri, 0.0), (ro, 0.0), (ro, tw), (ri, tw)]
                ring = lathe(prof, tm, segs=20, smooth_angle=60)
                ring += lathe([(ri - 0.003, 0.0), (ri, 0.0), (ri, tw), (ri - 0.003, tw)], core, segs=20, smooth_angle=60)
                ring.rotate(0, 90 * wl.n, 0)   # axis -> +-X (towards the room)
                cx_, cy_, _ = wl.P(bay, u_off + 0.038 + i * 0.075, dfront - 0.03, 0)
                g += ring.translate(cx_ - wl.n * tw * 0.0, cy_, cz + 0.036 + lvl * 0.074).set_density(1.0)
                printed.append(tm)
        printed.append(core)
        u = ncol * 0.075 + 0.01
        while u < width - 0.07:
            w_ = float(min(width - u, rng.uniform(0.12, 0.16)))
            carton(u, w_ - 0.006, float(rng.uniform(0.65, 0.9) * hav), 0.2, names[k % len(names)], col)
            u += w_
            k += 1
    elif kind == "bags":
        film = wl.mat("ivbag", color=(236, 242, 246), spec=0.7, gloss=0.85, edge=0.1, grain=0.0)
        printed.append(film)
        n = int(width // 0.105)
        for i in range(n):
            bw, bh = 0.095, min(hav * 0.92, 0.27)
            pg = pillow(bw, bh, 0.045, film, nx=10, nz=12, seam=0.004)
            pg.rotate(0, 0, -90 if wl.side == "l" else 90)       # front (+Y of the pillow) -> towards the room
            cx_, cy_, _ = wl.P(bay, u_off + 0.052 + i * 0.105, dfront - 0.04, 0)
            g += pg.translate(cx_, cy_, cz + bh / 2 + 0.004).set_density(1.6)
            x_ = 0.052 + i * 0.105 - bw / 2 + 0.008
            yb = ctop(cz + bh * 0.82)
            nm = names[i % len(names)]
            cv.rect(x_, yb, bw - 0.016, bh * 0.55, r=0.002, color=(250, 252, 252))
            cv.rect(x_, yb, bw - 0.016, 0.018, color=col)
            cv.text(x_ + (bw - 0.016) / 2, yb + 0.009, nm, 0.0062, fnt="label", color=(255, 255, 255), max_w=bw - 0.022)
            cv.text(x_ + (bw - 0.016) / 2, yb + 0.034, "1000 mL" if i % 3 else "500 mL", 0.0095, fnt="label", color=INK, max_w=bw - 0.022)
            cv.text(x_ + 0.004, yb + 0.055, "STERILE  ·  Rx", 0.0042, fnt="label", anchor="lm", color=INK)
            cv.text(x_ + (bw - 0.016) / 2, yb + 0.075, "FOR IV USE", 0.0045, fnt="label-semi", color=(90, 96, 100), max_w=bw - 0.022)
    elif kind == "pouch":
        film = wl.mat("pouch", color=(232, 240, 236), spec=0.65, gloss=0.8, edge=0.1, grain=0.0)
        printed.append(film)
        n = int(width // 0.14)
        for i in range(n):
            bw, bh = 0.13, min(hav * 0.88, 0.24)
            pg = pillow(bw, bh, 0.05, film, nx=10, nz=12, seam=0.004)
            pg.rotate(0, 0, -90 if wl.side == "l" else 90)
            cx_, cy_, _ = wl.P(bay, u_off + 0.07 + i * 0.14, dfront - 0.05, 0)
            g += pg.translate(cx_, cy_, cz + bh / 2 + 0.004).set_density(1.6)
            x_ = 0.07 + i * 0.14
            ym = ctop(cz + bh * 0.62)
            green = (60, 176, 110)
            cv.circle(x_, ym, 0.034, color=_lighten(green, 0.35), alpha=0.85)
            cv.circle(x_, ym, 0.022, color=_lighten(green, 0.55), alpha=0.9)
            cv.line([(x_ - 0.03, ym + 0.04), (x_ - 0.05, ym + 0.065), (x_ - 0.01, ym + 0.08), (x_ + 0.04, ym + 0.07)], 0.003, color=green)
            yl = ctop(cz + bh * 0.95)
            cv.rect(x_ - bw / 2 + 0.01, yl, bw - 0.02, 0.022, r=0.002, color=(250, 252, 252))
            cv.rect(x_ - bw / 2 + 0.01, yl, 0.012, 0.022, color=col)
            cv.text(x_ + 0.006, yl + 0.011, names[i % len(names)], 0.0068, fnt="label", color=INK, max_w=bw - 0.04)
    elif kind == "bvm":
        bag = wl.mat("bvm_bag", color=(70, 128, 212), spec=0.45, gloss=0.6, edge=0.15)
        bag2 = wl.mat("bvm_bag_w", color=(236, 238, 236), spec=0.45, gloss=0.6, edge=0.15)
        teal = wl.mat("bvm_teal", color=(10, 158, 147), spec=0.45, gloss=0.6, edge=0.2)
        printed += [bag, bag2]
        bp = [(0.0, 0.0), (0.012, 0.0), (0.03, 0.025), (0.05, 0.06), (0.056, 0.10), (0.05, 0.15), (0.03, 0.19), (0.012, 0.205), (0.0, 0.205)]
        for i in range(2):
            m = bag if i == 0 else bag2
            g_ = lathe(bp, m, segs=24, smooth_angle=40)
            g_ += cylinder(0.016, 0.03, teal, segs=16, bevel=0.003, z0=0.205)
            # lay it along the wall (+u)
            g_.rotate(-90, 0, 0)          # axis -> +Y
            if wl.side == "r":
                g_.rotate(0, 0, 180)      # axis -> -Y (the viewer's right on the right wall)
            cx_, cy_, _ = wl.P(bay, u_off + 0.02 + i * 0.0, dfront - 0.09, 0)
            g += g_.translate(cx_, cy_, cz + 0.057 + i * 0.118).set_density(1.0)
        u = 0.28
        while u < width - 0.07:
            w_ = float(min(width - u, rng.uniform(0.12, 0.16)))
            carton(u, w_ - 0.006, float(rng.uniform(0.6, 0.85) * hav), 0.2, names[k % len(names)], col)
            u += w_
            k += 1
    elif kind == "collars":
        cols = [(238, 196, 26), (60, 110, 200), (232, 106, 26), (10, 158, 147), (138, 78, 196)]
        sizes = ["ADJUSTABLE", "REGULAR", "TALL", "SHORT", "NO-NECK"]
        velcro = wl.mat("velcro", color=(28, 29, 31), spec=0.1, gloss=0.2, bump="fabric", bump_amp=0.0001, bump_scale=0.0012, edge=0.1)
        printed.append(velcro)
        tt = np.linspace(0, 1, 16)
        bot = [(-0.12 + 0.24 * t, 0.012 * math.sin(math.pi * t)) for t in tt]
        top = [(0.12 - 0.24 * t, 0.082 + 0.034 * math.sin(math.pi * t) ** 2) for t in tt]
        poly = np.asarray(bot + top)
        M = np.array([[0.0, 0.0, wl.n], [wl.r, 0.0, 0.0], [0.0, 1.0, 0.0]])   # (u, z, thickness) -> prop axes
        ncol = max(1, int(width // 0.27))
        for i in range(ncol):
            for lvl in range(2):
                idx = (i * 2 + lvl + bay) % len(cols)
                cm = wl.mat(f"collar{idx}", color=cols[idx], spec=0.3, gloss=0.45, edge=0.2)
                printed.append(cm)
                sh = extrude(poly, 0.012, cm, bevel=0.002, bevel_seg=1)
                sh.deform(lambda p: np.stack([p[:, 0], p[:, 1], p[:, 2] - 0.035 * (p[:, 0] / 0.12) ** 2], axis=1))
                sh += box((0.035, 0.05, 0.004), velcro, center=(0.095, 0.05, 0.0135))
                sh.transform(M)
                uc = 0.135 + i * 0.27
                cx_, cy_, _ = wl.P(bay, u_off + uc, dfront - 0.03, 0)
                zz = cz + 0.004 + lvl * 0.135
                g += sh.translate(cx_, cy_, zz).set_density(1.0)
                cv.text(uc, ctop(zz + 0.069), "CERVICAL COLLAR", 0.0046, fnt="label", color=INK, max_w=0.12)
                cv.text(uc, ctop(zz + 0.045), sizes[idx], 0.0068, fnt="label", color=INK, max_w=0.12)
    elif kind == "spinal":
        orange = wl.mat("headblock", color=(232, 106, 26), spec=0.2, gloss=0.3, bump="foam", bump_amp=0.0002, bump_scale=0.003, edge=0.2)
        yellow = wl.mat("strap_y", color=(238, 196, 26), spec=0.18, gloss=0.28, bump="webbing", bump_amp=0.00012, bump_scale=0.0015, edge=0.15)
        buckle = wl.mat("buckle", color=(30, 31, 33), spec=0.4, gloss=0.55, edge=0.3)
        printed += [orange, yellow, buckle]
        if row == "U":
            for i in range(3):
                g.charts.extend(wl.box(bay, u_off + 0.01 + i * 0.13, 0.12, dfront - 0.20, dfront, cz, 0.14, orange, r=0.015, seg=2).charts)
                cv.rect(0.03 + i * 0.13, ctop(cz + 0.12), 0.08, 0.05, r=0.003, color=(250, 250, 250))
                cv.text(0.07 + i * 0.13, ctop(cz + 0.105), "HEAD", 0.0068, fnt="label", color=INK)
                cv.text(0.07 + i * 0.13, ctop(cz + 0.09), "BLOCK", 0.0068, fnt="label", color=INK)
                g.charts.extend(wl.box(bay, u_off + 0.01 + i * 0.13, 0.12, dfront - 0.20, dfront, cz + 0.142, 0.03, orange, r=0.01, seg=2).charts)
            u = 0.40
        else:
            for i in range(int((width * 0.6) // 0.075)):
                for lvl in range(2):
                    ccx, ccy, _ = wl.P(bay, u_off + 0.04 + i * 0.075, dfront - 0.12, 0)
                    roll = cylinder(0.034, 0.05, yellow, segs=16, bevel=0.004, z0=-0.025).rotate(0, 90, 0)
                    g += roll.translate(ccx, ccy, cz + 0.036 + lvl * 0.07).set_density(1.0)
                    bx_, by_, _ = wl.P(bay, u_off + 0.04 + i * 0.075, dfront - 0.09, 0)
                    g += box((0.03, 0.036, 0.02), buckle, r=0.004, seg=1, center=(bx_ + wl.n * 0.012, by_, cz + 0.07 + lvl * 0.07)).set_density(0.8)
            u = int((width * 0.6) // 0.075) * 0.075 + 0.01
        while u < width - 0.07:
            w_ = float(min(width - u, rng.uniform(0.12, 0.16)))
            carton(u, w_ - 0.006, float(rng.uniform(0.6, 0.85) * hav), 0.22, names[(k + 1) % len(names)], col)
            u += w_
            k += 1
    for c in g.charts:
        if c.mat not in printed:
            pass
    return g, cv, printed, (y0e, y1e, z0, zt, width, u_off)


def _label_strip(text, col, w, h, code):
    cv = DecalCanvas(w, h, ppm=2200)
    cv.rect(0, 0, w, h, r=0.003, color=(246, 247, 247), spec=0.3, gloss=0.5)
    cv.rect(h * 0.18, h * 0.18, h * 0.64, h * 0.64, r=0.002, color=col)
    cross_mark(cv, h * 0.5, h * 0.5, h * 0.38, color=(255, 255, 255))
    ts = h * 0.46
    cv.text(h * 1.0, h * 0.53, text, ts, fnt="label", anchor="lm", color=INK, spacing=ts * 0.04, max_w=w - h * 2.4)
    cv.text(w - h * 0.25, h * 0.53, code, h * 0.24, fnt="mono-bold", anchor="rm", color=(120, 126, 130))
    return cv


def _cabinet_run(b, side):
    """Glass-front supply cabinet run on one long wall, with stock + labels. Returns collision box."""
    wl = Wall(b, side)
    white = wl.mat("cab_white", color=(236, 238, 238), spec=0.3, gloss=0.5, bump="orange_peel", bump_amp=0.00001, bump_scale=0.002,
                   grain=0.015, grain_scale=0.1, edge=0.2, dirt=0.05)
    back = wl.mat("cab_back", color=(222, 226, 228), spec=0.2, gloss=0.35, grain=0.02, grain_scale=0.1, ao=1.0)
    alu = wl.mat("cab_alu", color=(176, 182, 188), spec=0.75, gloss=0.62, metal=1.0, bump="brushed", bump_amp=0.00001, bump_scale=0.0004, edge=0.25)
    rail = wl.mat("cab_rail", color=(196, 200, 204), spec=0.55, gloss=0.55, metal=0.6, edge=0.25)
    glass = b.mat("cab_glass", color=(226, 236, 240), spec=0.95, gloss=0.95, alpha=0.12, layer="alpha", grain=0.0)
    led = b.mat("cab_led", color=(240, 246, 255), layer="glow")
    e = wl.edges
    y0, y1 = float(e[0]), float(e[-1])
    L = y1 - y0
    yc = (y0 + y1) / 2
    xd = lambda d: wl.x(d)  # noqa: E731
    g = Geo()
    # back panel, bottom, top, shelf, end panels, dividers
    g += box((0.012, L, CAB_TOP - CAB_FLOOR_L + 0.04), back, center=(xd(0.006), yc, (CAB_FLOOR_L + CAB_TOP) / 2), faces=wl.front,
             density=0.25)
    g += box((CAB_D, L, 0.04), white, center=(xd(CAB_D / 2), yc, CAB_RAIL_B[0] + 0.02), faces="+z -z", density=0.35)
    g += box((CAB_D, L, 0.02), white, center=(xd(CAB_D / 2), yc, (CAB_SHELF[0] + CAB_SHELF[1]) / 2), faces="+z -z", density=0.28)
    g += box((CAB_D, L, 0.04), white, center=(xd(CAB_D / 2), yc, CAB_TOP + 0.02), faces="-z", density=0.35)
    for k, yy in enumerate(e):
        th = 0.018
        g += box((CAB_D, th, CAB_TOP - CAB_FLOOR_L), white, r=0.002, seg=1, center=(xd(CAB_D / 2), yy, (CAB_FLOOR_L + CAB_TOP) / 2),
                 faces="+y -y " + wl.front, density=0.4)
    # front rails (label strips) + top rail + mullions
    for (za, zb_) in (CAB_RAIL_B, CAB_RAIL_M, (CAB_TOP, BAY_H)):
        g += box((0.02, L + 0.02, zb_ - za), rail, r=0.003, seg=1, center=(xd(CAB_D - 0.01), yc, (za + zb_) / 2),
                 faces=wl.front + " +z -z +y -y", density=0.4, face_density={wl.front: 3.4})
    for yy in e:
        g += box((0.02, 0.024, CAB_TOP - CAB_RAIL_B[1]), alu, r=0.003, seg=1, center=(xd(CAB_D - 0.008), yy, (CAB_RAIL_B[1] + CAB_TOP) / 2),
                 faces=wl.front + " +y -y", density=0.5)
    # sliding glass doors: two panels per bay and row, the second one slightly behind
    glass_g = Geo()
    for k in range(6):
        ya, yb_ = float(e[k]) + 0.012, float(e[k + 1]) - 0.012
        half = (yb_ - ya) / 2
        for row, (za, zb_) in (("L", (CAB_RAIL_B[1], CAB_RAIL_M[0])), ("U", (CAB_RAIL_M[1], CAB_TOP))):
            for j in range(2):
                yy0 = ya + j * half - (0.01 if j else 0)
                yy1 = ya + (j + 1) * half + (0.01 if not j else 0)
                dd = CAB_D - 0.02 - j * 0.008
                glass_g += quad((xd(dd), (yy0 + yy1) / 2, (za + zb_) / 2), (0, wl.r, 0), (0, 0, 1), yy1 - yy0, zb_ - za, glass,
                                density=0.25)
                # vertical frame edges of each panel + finger pull
                for yy in (yy0 + 0.006, yy1 - 0.006):
                    g += box((0.012, 0.012, zb_ - za), alu, r=0.002, seg=1, center=(xd(dd + 0.002), yy, (za + zb_) / 2),
                             faces=wl.front + " +y -y", density=0.4)
                py = (yy1 - 0.03) if j == 0 else (yy0 + 0.03)
                g += box((0.01, 0.018, 0.06), alu, r=0.003, seg=1, center=(xd(dd + 0.006), py, (za + zb_) / 2), density=0.6)
    b.add(g)
    b.add(glass_g)
    # under-cabinet LED strip
    b.add(box((0.03, L - 0.06, 0.004), led, center=(xd(CAB_D - 0.05), yc, CAB_RAIL_B[0] - 0.002), faces="-z"))
    # stock + labels
    for bay in range(6):
        for row in ("L", "U"):
            cat = ASSIGN[(side, bay, row)]
            stock, cv, printed, (ya, yb_, z0, zt, width, u_off) = _fill_slot(wl, bay, row, cat)
            b.add(stock)
            cu = u_off + width / 2
            cx_, cy_, _ = wl.P(bay, cu, 0.0, 0.0)
            b.decal(cv, center=(xd(0.20), cy_, zt - 0.01 - cv.h_m / 2), normal=wl.normal, up=(0, 0, 1),
                    mats=[f"{m}" for m in printed], depth=0.13, min_dot=0.55)
            za, zb_ = CAB_RAIL_B if row == "L" else CAB_RAIL_M
            lw = (yb_ - ya) - 0.05
            code = f"{'L' if side == 'l' else 'R'}{bay + 1}-{row}"
            lab = _label_strip(cat, CAT_COLORS[cat], lw, (zb_ - za) - 0.008, code)
            b.decal(lab, center=(xd(CAB_D + 0.0001), (ya + yb_) / 2, (za + zb_) / 2), normal=wl.normal, up=(0, 0, 1),
                    mats=[rail], depth=0.006)
    lo = min(wl.x(0.0), wl.x(CAB_D))
    hi = max(wl.x(0.0), wl.x(CAB_D))
    return (lo, y0, CAB_RAIL_B[0]), (hi, y1, BAY_H)


# ---------------------------------------------------------------------------------------------
@prop("nz_amb_bay_shell", atlas=2048, alpha_atlas=256, glow_atlas=128, layers={"shell": 2048, "supl": 1024, "supr": 1024},
      lod=120, hd=25, static=True, falloff=70, glow_mult=1.6, doc={
          "title": "Ambulance treatment bay interior (walk-in patient compartment)",
          "origin": "floor centre of the room",
          "axes": "+Y = towards the cab bulkhead, -Y = the rear doors, patient side (stretcher, O2 panel) -X, bench + "
                  "counter +X, +Z up; inside 2.30 W x 4.30 L x 2.05 H, walls / floor / ceiling face inwards (a thin "
                  "outer skin closes it from outside)",
          "screen": f"nz_amb_screen - bulkhead monitor quad {MON_SCREEN[0]} x {MON_SCREEN[1]} m centred at "
                    f"({MON_C[0]}, {MON_C[1]:.4f}, {MON_C[2]}) facing -Y, UV 0..1 = visible screen, top-left = (0,0); "
                    "default = dark standby screen with clock, cabin temperature and O2 supply (txd 'nz_amb_bay_shell')",
          "attach": f"stretcher: nz_amb_stretcher at ({STRETCHER[0]}, {STRETCHER[1]}, 0.0) heading +0 (head end towards the "
                    f"cab); IV hooks (bag origin = hanging slot) at {IV_HOOKS[0]} and {IV_HOOKS[1]}; patient monitor shelf "
                    f"top at {PM_SHELF} - place nz_amb_monitor there with rot (0, 0, -90) (screen faces +X); medic spawn "
                    f"{MEDIC_SPAWN} heading +0; exit marker {EXIT}; bench seats (0.93, "
                    + " / ".join(f"{BENCH[1] + (BENCH[2] - BENCH[1]) / 3 * (k + 0.5):.3f}" for k in range(3))
                    + f", {SEAT_Z}) heading +90; attendant seat (-0.42, 1.86, 0.48) heading +180; supply cabinet slots: "
                    "see docs/modules/props.md section 5",
      }, preview={
          "views": ["int_rear", "int_front", "plan"],
          "cams": [
              {"name": "int_rear", "pos": [0.52, -2.05, 1.70], "target": [-0.45, 0.9, 0.95], "fov": 78},
              {"name": "int_front", "pos": [0.25, 1.95, 1.70], "target": [-0.10, -1.6, 0.9], "fov": 78},
              {"name": "plan", "pos": [0.0, 0.0, 10.5], "target": [0.0, 0.001, 0.0], "fov": 30, "clipZ": 1.98},
              {"name": "cab_left", "pos": [0.35, -0.95, 1.55], "target": [-1.15, -0.95, 1.70], "fov": 62},
              {"name": "cab_right", "pos": [-0.35, 0.35, 1.55], "target": [1.15, 0.35, 1.70], "fov": 62},
              {"name": "head_end", "pos": [0.35, -0.6, 1.45], "target": [-0.6, 1.9, 1.15], "fov": 70},
          ],
          "lights": [
              {"pos": [0.0, -1.0, 1.9], "intensity": 3.5, "distance": 7},
              {"pos": [0.0, 0.95, 1.9], "intensity": 3.5, "distance": 7},
              {"pos": [0.3, -1.9, 1.5], "intensity": 1.2, "distance": 5},
          ],
      })
def bay_shell(b):
    # ---- materials -------------------------------------------------------------------------
    wall = b.mat("bay_wall", layer="shell", color=(236, 238, 238), spec=0.22, gloss=0.42, bump="orange_peel", bump_amp=0.00002,
                 bump_scale=0.004, grain=0.025, grain_scale=0.3, edge=0.0, dirt=0.08)
    ceil = b.mat("bay_ceiling", layer="shell", color=(222, 226, 229), spec=0.18, gloss=0.35, grain=0.02, grain_scale=0.3)
    floor = b.mat("bay_floor", layer="shell", color=(60, 64, 70), spec=0.28, gloss=0.38, bump="stipple", bump_amp=0.00018,
                  bump_scale=0.008, grain=0.12, grain_scale=0.012, edge=0.0, dirt=0.15)
    kick = b.mat("bay_kick", layer="shell", color=(48, 52, 57), spec=0.3, gloss=0.42, grain=0.03, grain_scale=0.1)
    stripe = b.mat("bay_stripe", layer="shell", color=(10, 158, 147), spec=0.35, gloss=0.5, grain=0.02)
    skin = b.mat("bay_skin", color=(214, 218, 220), spec=0.25, gloss=0.4, grain=0.02, grain_scale=0.4)
    white = m_hosp_white(b)
    grey = m_hosp_grey(b)
    dark = m_hosp_dark(b)
    alu = m_alu(b)
    chrome = m_chrome(b)
    blk = m_black_plastic(b)
    gloss = m_gloss_black(b)
    seat_blue = b.mat("bench_vinyl", color=(34, 92, 164), spec=0.34, gloss=0.5, bump="orange_peel", bump_amp=0.00006, bump_scale=0.03,
                      grain=0.03, grain_scale=0.2, edge=0.35, dirt=0.1)
    web = m_webbing(b, "belt", (28, 30, 34))
    plate = b.mat("diamond_plate", color=(170, 176, 182), spec=0.8, gloss=0.6, metal=1.0, bump="knurl", bump_amp=0.0005,
                  bump_scale=0.02, grain=0.03, edge=0.3)
    tint = b.mat("door_glass", color=(12, 16, 20), spec=0.95, gloss=0.92, edge=0.1)
    o2green = b.mat("o2_green", color=(34, 150, 80), spec=0.4, gloss=0.55, edge=0.3)
    red = b.mat("ext_red", color=(196, 30, 36), spec=0.55, gloss=0.7, edge=0.3)
    kitred = b.mat("kit_red", color=(178, 30, 36), spec=0.22, gloss=0.3, bump="fabric", bump_amp=0.00018, bump_scale=0.0018,
                   edge=0.2, color2=(150, 22, 28))
    yellow = b.mat("sharps_yellow", color=(238, 202, 40), spec=0.3, gloss=0.45, edge=0.2)
    orange = b.mat("sharps_lid", color=(236, 118, 34), spec=0.3, gloss=0.45, edge=0.3)
    lamp = b.mat("ceiling_lamp", color=(244, 248, 255), layer="glow")
    led_g = m_led(b, "led_green", (70, 255, 140))

    # ---- room surfaces (inward) ------------------------------------------------------------------
    room = box((BAY_W, BAY_L, BAY_H), wall, center=(0, 0, BAY_H / 2), face_mat={"-z": floor, "+z": ceil},
               face_density={"-z": 1.0, "+z": 0.55, "+x": 0.6, "-x": 0.6, "+y": 0.6, "-y": 0.5}, tag="room")
    b.add(room.flip())
    # kick plates + teal accent line on the side walls / bulkhead
    for sx in (-1, 1):
        b.add(box((0.006, BAY_L - 0.01, 0.12), kick, center=(sx * (XW - 0.003), 0, 0.06), faces="+x" if sx < 0 else "-x", density=0.6))
        b.add(box((0.004, BAY_L - 0.01, 0.025), stripe, center=(sx * (XW - 0.002), 0, 1.255), faces="+x" if sx < 0 else "-x", density=0.6))
    b.add(box((BAY_W - 0.01, 0.006, 0.12), kick, center=(0, YF - 0.003, 0.06), faces="-y", density=0.6))
    # outer skin (closes the shell when seen from outside)
    b.add(box((BAY_W + 0.12, BAY_L + 0.12, BAY_H + 0.16), skin, r=0.04, seg=1, center=(0, 0, BAY_H / 2), density=0.04, tag="skin"))

    # ---- floor details ---------------------------------------------------------------------------
    sx_, sy_ = STRETCHER
    for dx in (-0.17, 0.17):
        b.add(box((0.05, 2.9, 0.008), alu, r=0.002, seg=1, center=(sx_ + dx, -0.25, 0.004), faces="+z +x -x +y -y", density=0.5))
        b.add(box((0.012, 2.88, 0.002), dark, center=(sx_ + dx, -0.25, 0.0085), faces="+z", density=0.5))
    b.add(box((0.26, 0.16, 0.11), dark, r=0.02, seg=2, center=(sx_, 1.30, 0.055)))
    for dx in (-0.1, 0.1):
        b.add(box((0.04, 0.05, 0.12), yellow, r=0.01, seg=2, center=(sx_ + dx, 1.22, 0.06)))
    b.add(box((BAY_W - 0.02, 0.16, 0.012), plate, r=0.003, seg=1, center=(0, YR + 0.08, 0.006), faces="+z +y", density=0.8))

    # ---- rear doors (inner side) -------------------------------------------------------------------
    yd = YR + 0.004
    for sx in (-1, 1):
        cxd = sx * 0.5
        b.add(box((0.985, 0.03, 1.78), white, r=0.01, seg=2, center=(cxd, yd + 0.015, 0.09 + 0.89), faces="+y +x -x +z -z", density=0.55))
        b.add(box((0.84, 0.012, 0.86), grey, r=0.02, seg=2, center=(cxd, yd + 0.034, 0.62), faces="+y +x -x +z -z", density=0.55))
        b.add(box((0.62, 0.008, 0.47), dark, r=0.03, seg=2, center=(cxd, yd + 0.032, 1.42), faces="+y +x -x +z -z", density=0.6))
        b.add(quad((cxd, yd + 0.0365, 1.42), (-1, 0, 0), (0, 0, 1), 0.56, 0.41, tint, density=0.5))
        # lever handle + grab handle
        hx = sx * 0.12
        b.add(box((0.05, 0.03, 0.09), dark, r=0.008, seg=2, center=(hx, yd + 0.045, 1.04)))
        lv = polyline_fillet([(hx, yd + 0.06, 1.06), (hx, yd + 0.085, 1.06), (hx + sx * 0.13, yd + 0.085, 1.06)], 0.012, 4)
        b.add(tube(lv, 0.009, chrome, segs=12, tag="lever"))
        gp = polyline_fillet([(sx * 0.80, yd + 0.03, 0.80), (sx * 0.80, yd + 0.09, 0.82), (sx * 0.80, yd + 0.09, 1.28), (sx * 0.80, yd + 0.03, 1.30)], 0.03, 5)
        b.add(tube(gp, 0.013, chrome, segs=12, tag="grab"))
        # hinges on the outer edges
        for zh in (0.35, 1.0, 1.65):
            b.add(cylinder(0.016, 0.12, chrome, segs=12, bevel=0.003, z0=zh - 0.06).translate(sx * 0.985, yd + 0.035, 0))
    b.add(box((0.012, 0.03, 1.78), blk, center=(0, yd + 0.016, 0.98), faces="+y"))
    b.add(box((BAY_W - 0.02, 0.05, 0.19), white, r=0.01, seg=2, center=(0, YR + 0.025, BAY_H - 0.095), faces="+y -z", density=0.5))
    for sx in (-1, 1):
        b.add(box((0.15, 0.05, 1.86), white, r=0.01, seg=2, center=(sx * (XW - 0.075), YR + 0.025, 0.93), faces="+y +x -x", density=0.5))

    # ---- supply cabinets ---------------------------------------------------------------------------
    cab_l = _cabinet_run(b, "l")
    cab_r = _cabinet_run(b, "r")

    # ---- O2 / suction wall panel + patient monitor shelf (left wall) -----------------------------
    px = -XW + 0.012
    b.add(box((0.024, 0.95, 0.36), grey, r=0.01, seg=2, center=(px, 1.10, 1.13), faces="+x +y -y +z -z"))
    fx = px + 0.012
    # O2 flowmeter: green knob + clear tube on a chrome body
    b.add(box((0.05, 0.05, 0.12), chrome, r=0.008, seg=2, center=(fx + 0.025, 0.80, 1.15)))
    b.add(cylinder(0.014, 0.10, b.mat("flow_tube", color=(220, 236, 240), spec=0.9, gloss=0.9), segs=16, z0=1.10).translate(fx + 0.05, 0.80, 0))
    b.add(align(knob(o2green, 0.034, 0.02), (1, 0, 0), (0, 0, 1), (fx + 0.05, 0.80, 1.06)))
    # suction regulator gauge
    b.add(align(cylinder(0.036, 0.03, chrome, segs=32, bevel=0.004, caps=(False, True)), (1, 0, 0), (0, 0, 1), (fx, 1.06, 1.17)))
    b.add(align(cylinder(0.031, 0.002, b.mat("gauge_face", color=(236, 238, 238), spec=0.3, gloss=0.5), segs=32, caps=(False, True)),
                (1, 0, 0), (0, 0, 1), (fx + 0.03, 1.06, 1.17)))
    b.add(align(knob(dark, 0.03, 0.018), (1, 0, 0), (0, 0, 1), (fx, 1.06, 1.065)))
    # outlets: O2 (green) x2, vacuum (yellow), power x2
    for k, (yy, m) in enumerate(((1.28, o2green), (1.36, o2green), (1.46, yellow))):
        b.add(align(cylinder(0.022, 0.012, m, segs=24, bevel=0.003, caps=(False, True)), (1, 0, 0), (0, 0, 1), (fx, yy, 1.22)))
        b.add(align(cylinder(0.009, 0.014, chrome, segs=14, caps=(False, True)), (1, 0, 0), (0, 0, 1), (fx, yy, 1.22)))
    for yy in (1.30, 1.42):
        b.add(box((0.012, 0.07, 0.07), white, r=0.008, seg=2, center=(fx + 0.004, yy, 1.04)))
        for dz in (-0.012, 0.012):
            b.add(box((0.004, 0.012, 0.004), blk, center=(fx + 0.011, yy, 1.04 + dz)))
    # monitor wall shelf (dark bracket + lip)
    sx0 = PM_SHELF[0]
    b.add(box((0.26, 0.40, 0.025), dark, r=0.006, seg=2, center=(sx0, PM_SHELF[1], PM_SHELF[2] - 0.0125)))
    b.add(box((0.012, 0.40, 0.04), dark, r=0.004, seg=1, center=(sx0 + 0.125, PM_SHELF[1], PM_SHELF[2] + 0.01)))
    for yy in (-0.15, 0.15):
        b.add(box((0.10, 0.02, 0.18), dark, r=0.006, seg=1, center=(-XW + 0.05, PM_SHELF[1] + yy, PM_SHELF[2] - 0.1)))
    # O2 cylinder in its bracket (front-left corner)
    cyl = lathe([(0.0, 0.0), (0.085, 0.0), (0.09, 0.02), (0.09, 0.86), (0.07, 0.93), (0.03, 0.96), (0.0, 0.96)], o2green, segs=32, smooth_angle=40)
    cyl += lathe([(0.0, 0.96), (0.03, 0.96), (0.03, 1.0), (0.02, 1.04), (0.0, 1.04)], chrome, segs=20, smooth_angle=40)
    b.add(cyl.translate(-0.95, 1.95, 0.0))
    b.add(box((0.10, 0.04, 0.20), white, r=0.01, seg=2, center=(-0.95, 1.95 + 0.07, 0.70)))
    for zb_ in (0.35, 0.75):
        b.add(torus(0.094, 0.008, dark, segs=32, tube_segs=6).translate(-0.95, 1.95, zb_))
    b.add(box((0.10, 0.18, 0.16), b.mat("reg_grey", color=(150, 156, 162), spec=0.6, gloss=0.6, metal=0.7, edge=0.3), r=0.01, seg=2,
              center=(-0.95, 1.95, 1.10)))
    b.add(align(cylinder(0.03, 0.01, chrome, segs=24, caps=(False, True)), (1, 0, 0), (0, 0, 1), (-0.90, 1.95, 1.12)))

    # ---- attendant (captain's) seat at the bulkhead, facing the rear --------------------------------
    cxs = -0.42
    b.add(box((0.46, 0.44, 0.42), dark, r=0.03, seg=2, center=(cxs, YF - 0.30, 0.21)))
    b.add(box((0.50, 0.48, 0.09), seat_blue, r=0.035, seg=3, center=(cxs, YF - 0.30, 0.465)))
    b.add(box((0.50, 0.09, 0.64), seat_blue, r=0.035, seg=3, center=(cxs, YF - 0.06, 0.89)))
    b.add(box((0.32, 0.09, 0.17), seat_blue, r=0.03, seg=3, center=(cxs, YF - 0.06, 1.30)))
    b.add(box((0.06, 0.06, 0.06), dark, r=0.01, seg=2, center=(cxs, YF - 0.05, 1.20)))
    sb = polyline_fillet([(cxs + 0.20, YF - 0.105, 1.18), (cxs + 0.05, YF - 0.11, 0.85), (cxs - 0.21, YF - 0.30, 0.52)], 0.05, 5)
    b.add(sweep(rrect(0.048, 0.003, 0.0, 1), sb, web, side=(0, 1, 0), tag="belt"))
    # ---- squad bench (+X) ---------------------------------------------------------------------------
    bx0, by0, by1 = BENCH
    blen = by1 - by0
    b.add(box((XW - bx0, blen, SEAT_Z - 0.08), white, r=0.02, seg=2, center=((XW + bx0) / 2, (by0 + by1) / 2, (SEAT_Z - 0.08) / 2),
              faces="-x +y -y +z", density=0.6))
    b.add(box((0.02, blen - 0.02, 0.10), dark, r=0.006, seg=1, center=(bx0 - 0.006, (by0 + by1) / 2, 0.05), faces="-x"))
    nseat = 3
    sl = blen / nseat
    for k in range(nseat):
        yc = by0 + sl * (k + 0.5)
        b.add(box((XW - bx0 - 0.02, sl - 0.016, 0.08), seat_blue, r=0.03, seg=3, center=((XW + bx0) / 2 - 0.01, yc, SEAT_Z - 0.04)))
        b.add(box((0.08, sl - 0.03, 0.46), seat_blue, r=0.03, seg=3, center=(XW - 0.045, yc, SEAT_Z + 0.31)))
        # storage lid front + latch
        b.add(box((0.012, sl - 0.06, 0.24), white, r=0.006, seg=1, center=(bx0 - 0.004, yc, 0.24), faces="-x +y -y +z -z"))
        b.add(box((0.014, 0.08, 0.025), dark, r=0.005, seg=1, center=(bx0 - 0.01, yc, 0.33)))
        # lap belt halves
        for s_ in (-1, 1):
            bp = polyline_fillet([(XW - 0.09, yc + s_ * 0.16, SEAT_Z - 0.01), (XW - 0.13, yc + s_ * 0.13, SEAT_Z + 0.004),
                                  (bx0 + 0.12, yc + s_ * 0.04, SEAT_Z + 0.004)], 0.02, 4)
            b.add(sweep(rrect(0.045, 0.003, 0.0, 1), bp, web, up=(0, 0, 1), tag="lapbelt"))
        b.add(box((0.07, 0.05, 0.016), chrome, r=0.004, seg=1, center=(bx0 + 0.10, yc, SEAT_Z + 0.012)))
    # ---- counter with kit + sharps (front right) -------------------------------------------------------
    cx0, cy0, ctop = COUNTER
    b.add(box((XW - cx0, YF - cy0, ctop - 0.03), white, r=0.015, seg=2, center=((XW + cx0) / 2, (YF + cy0) / 2, (ctop - 0.03) / 2),
              faces="-x -y +z", density=0.6))
    b.add(box((XW - cx0 + 0.02, YF - cy0 + 0.01, 0.03), grey, r=0.008, seg=2, center=((XW + cx0) / 2 - 0.01, (YF + cy0) / 2 - 0.005, ctop - 0.015)))
    for (ya, yb_, za, zb_) in ((cy0 + 0.03, cy0 + 0.58, 0.12, 0.70), (cy0 + 0.62, YF - 0.03, 0.12, 0.70), (cy0 + 0.03, YF - 0.03, 0.74, ctop - 0.06)):
        b.add(box((0.012, yb_ - ya, zb_ - za), white, r=0.006, seg=1, center=(cx0 - 0.004, (ya + yb_) / 2, (za + zb_) / 2), faces="-x +y -y +z -z"))
        b.add(box((0.014, 0.10, 0.02), dark, r=0.005, seg=1, center=(cx0 - 0.012, (ya + yb_) / 2, zb_ - 0.06)))
    # red kit case lying on the counter
    kc = (0.93, cy0 + 0.25, ctop)
    b.add(box((0.30, 0.42, 0.16), kitred, r=0.03, seg=3, center=(kc[0], kc[1], kc[2] + 0.08)))
    b.add(box((0.31, 0.43, 0.02), blk, r=0.008, seg=2, center=(kc[0], kc[1], kc[2] + 0.10)))
    kh = polyline_fillet([(kc[0] - 0.05, kc[1] - 0.08, kc[2] + 0.16), (kc[0] - 0.05, kc[1] - 0.08, kc[2] + 0.19),
                          (kc[0] - 0.05, kc[1] + 0.08, kc[2] + 0.19), (kc[0] - 0.05, kc[1] + 0.08, kc[2] + 0.16)], 0.02, 4)
    b.add(tube(kh, 0.011, blk, segs=12))
    # sharps bin
    sc = (0.98, YF - 0.16, ctop)
    b.add(box((0.15, 0.20, 0.22), yellow, r=0.015, seg=2, center=(sc[0], sc[1], sc[2] + 0.11)))
    b.add(box((0.16, 0.21, 0.035), orange, r=0.012, seg=2, center=(sc[0], sc[1], sc[2] + 0.235)))
    b.add(box((0.06, 0.12, 0.006), blk, center=(sc[0] - 0.02, sc[1], sc[2] + 0.253), faces="+z"))
    # glove dispenser (3 boxes) on the wall above the counter
    gx = XW - 0.07
    gy = 1.62
    b.add(box((0.14, 0.42, 0.22), white, r=0.01, seg=2, center=(gx, gy, 1.15), faces="-x +y -y +z -z"))
    for k, (gc, gs) in enumerate((((60, 110, 200), "S"), ((10, 158, 147), "M"), ((138, 78, 196), "L"))):
        gm = b.mat(f"glove_{gs}", color=_lighten(gc, 0.0), spec=0.3, gloss=0.45, edge=0.2)
        b.add(box((0.012, 0.12, 0.16), gm, r=0.004, seg=1, center=(gx - 0.073, gy - 0.13 + k * 0.13, 1.13), faces="-x +y -y +z -z"))
    # ---- bulkhead: monitor, clock, emblem --------------------------------------------------------------
    mx, my, mz = MON_C
    b.add(box((MON_SCREEN[0] + 0.06, 0.045, MON_SCREEN[1] + 0.06), gloss, r=0.01, seg=2, center=(mx, YF - 0.0225, mz)))
    b.screen(quad((mx, my, mz), (1, 0, 0), (0, 0, 1), MON_SCREEN[0], MON_SCREEN[1], "x", fixed_uv=True),
             image=draw_bay_monitor(512, 256), size=(512, 256), mult=0.9)
    b.add(box((0.24, 0.03, 0.08), gloss, r=0.008, seg=2, center=(0.48, YF - 0.015, 1.80)))
    # ---- ceiling: light panels, IV rail + hooks, grab rail, vents --------------------------------------
    for lx in (-0.55, 0.55):
        for (ya, yb_) in ((-1.70, -0.30), (0.20, 1.60)):
            yc = (ya + yb_) / 2
            b.add(box((0.44, yb_ - ya + 0.04, 0.02), grey, r=0.006, seg=1, center=(lx, yc, BAY_H - 0.01), faces="-z +x -x +y -y", density=0.5))
            b.add(box((0.38, yb_ - ya - 0.02, 0.004), lamp, center=(lx, yc, BAY_H - 0.0215), faces="-z"))
    b.add(box((0.04, 3.2, 0.025), alu, r=0.004, seg=1, center=(IV_RAIL_X, 0.1, BAY_H - 0.0125), faces="-z +x -x +y -y"))
    for (hx, hy, hz) in IV_HOOKS:
        b.add(box((0.05, 0.06, 0.03), dark, r=0.008, seg=2, center=(hx, hy, BAY_H - 0.04)))
        b.add(cylinder(0.006, BAY_H - 0.055 - (hz + 0.03), chrome, segs=10, z0=hz + 0.03).translate(hx, hy, 0))
        for s_ in (-1, 1):
            hk = np.array([(hx, hy, hz + 0.03), (hx + s_ * 0.03, hy, hz + 0.02), (hx + s_ * 0.045, hy, hz + 0.0), (hx + s_ * 0.04, hy, hz - 0.012),
                           (hx + s_ * 0.03, hy, hz - 0.006)])
            b.add(tube(catmull(hk, n=5), 0.0035, chrome, segs=8, tag="hook"))
    gr = polyline_fillet([(0.30, -1.65, BAY_H), (0.30, -1.6, BAY_H - 0.09), (0.30, 1.0, BAY_H - 0.09), (0.30, 1.05, BAY_H)], 0.04, 5)
    b.add(tube(gr, 0.016, chrome, segs=14, tag="grabrail"))
    for yy in (-0.6, 0.3):
        b.add(cylinder(0.012, 0.09, chrome, segs=10, z0=BAY_H - 0.09).translate(0.30, yy, 0))
    for vy in (-1.95, 1.85):
        b.add(box((0.30, 0.16, 0.012), grey, r=0.004, seg=1, center=(0, vy, BAY_H - 0.006), faces="-z +x -x +y -y"))
    # ---- extinguisher (rear right) ------------------------------------------------------------------
    ex = (XW - 0.09, YR + 0.25)
    ext = lathe([(0.0, 0.0), (0.065, 0.0), (0.07, 0.02), (0.07, 0.40), (0.05, 0.45), (0.0, 0.46)], red, segs=28, smooth_angle=40)
    ext += lathe([(0.0, 0.46), (0.02, 0.46), (0.02, 0.50), (0.0, 0.50)], blk, segs=12)
    b.add(ext.translate(ex[0], ex[1], 0.12))
    b.add(box((0.04, 0.10, 0.30), dark, r=0.006, seg=1, center=(XW - 0.02, ex[1], 0.35)))
    b.add(tube(np.array([(ex[0] - 0.02, ex[1], 0.62), (ex[0] - 0.05, ex[1] + 0.02, 0.6), (ex[0] - 0.07, ex[1] + 0.02, 0.4)]), 0.006, blk, segs=8))
    b.add(align(cylinder(0.002, 0.002, led_g, segs=8, caps=(False, True)), (0, -1, 0), (0, 0, 1), (0.48, YF - 0.0305, 1.83)))

    # ---- decals ------------------------------------------------------------------------------------------
    clock = DecalCanvas(0.24, 0.08, ppm=3000)
    clock.text(0.12, 0.04, "14:32", 0.03, fnt="mono-bold", color=(40, 230, 210), spacing=0.003)
    b.decal(clock, center=(0.48, YF - 0.0301, 1.80), normal=(0, -1, 0), up=(0, 0, 1), mats=["gloss_black"], depth=0.004)
    emb = DecalCanvas(0.40, 0.36, ppm=1800)
    emb.star_of_life(0.20, 0.12, 0.20, color=(30, 88, 186), border=(255, 255, 255))
    emb.text(0.20, 0.27, "AMBULANCE", 0.034, fnt="label", color=(46, 50, 54), spacing=0.005)
    emb.text(0.20, 0.32, "PATIENT COMPARTMENT", 0.016, fnt="label-semi", color=TEAL, spacing=0.003)
    b.decal(emb, center=(0.55, YF - 0.0001, 1.15), normal=(0, -1, 0), up=(0, 0, 1), mats=["bay_wall"], depth=0.01)
    o2l = DecalCanvas(0.95, 0.06, ppm=1500)
    for (yy, t) in ((0.80, "O2  FLOW"), (1.06, "SUCTION"), (1.32, "OXYGEN"), (1.46, "VAC"), (1.36, "")):
        if t:
            o2l.text(yy - 0.625, 0.03, t, 0.014, fnt="label", color=(40, 44, 48), max_w=0.16)
    b.decal(o2l, center=(px + 0.0121, 1.10, 1.285), normal=(1, 0, 0), up=(0, 0, 1), mats=["hosp_grey"], depth=0.006)
    gd = DecalCanvas(0.062, 0.062, ppm=6000)
    for k in range(0, 13):
        a = math.radians(225 - k * 22.5)
        gd.line([(0.031 + math.cos(a) * 0.022, 0.031 - math.sin(a) * 0.022), (0.031 + math.cos(a) * 0.027, 0.031 - math.sin(a) * 0.027)],
                0.0009, color=(30, 32, 34))
    a = math.radians(225 - 5 * 22.5)
    gd.line([(0.031, 0.031), (0.031 + math.cos(a) * 0.022, 0.031 - math.sin(a) * 0.022)], 0.0012, color=(206, 40, 44))
    gd.text(0.031, 0.045, "-mmHg", 0.0034, fnt="label-semi", color=(80, 86, 90))
    b.decal(gd, center=(fx + 0.0321, 1.06, 1.17), normal=(1, 0, 0), up=(0, 0, 1), mats=["gauge_face"], depth=0.002)
    ex_l = DecalCanvas(0.08, 0.12, ppm=3000)
    ex_l.rect(0, 0, 0.08, 0.12, r=0.004, color=(246, 246, 244))
    ex_l.text(0.04, 0.025, "FIRE", 0.014, fnt="label", color=(196, 30, 36))
    ex_l.text(0.04, 0.05, "EXTINGUISHER", 0.0068, fnt="label", color=INK, max_w=0.07)
    ex_l.text(0.04, 0.08, "ABC  2 kg", 0.009, fnt="label-semi", color=INK)
    b.decal(ex_l, center=(ex[0] - 0.07, ex[1], 0.32), normal=(-1, 0, 0), up=(0, 0, 1), mats=["ext_red"], depth=0.03, min_dot=0.6)
    sh = DecalCanvas(0.20, 0.20, ppm=2500)
    sh.text(0.10, 0.03, "SHARPS", 0.026, fnt="label", color=INK)
    biohazard(sh, 0.10, 0.11, 0.045, color=INK)
    sh.text(0.10, 0.18, "DO NOT OVERFILL", 0.01, fnt="label-semi", color=INK)
    b.decal(sh, center=(sc[0] - 0.0751, sc[1], sc[2] + 0.11), normal=(-1, 0, 0), up=(0, 0, 1), mats=["sharps_yellow"], depth=0.01)
    kl = label_canvas(0.26, 0.05, "TRAUMA KIT", "TK-62  ·  UNIT 07-A", ppm=2800, color=(255, 255, 255), sub_color=(255, 220, 220),
                      icon="star", icon_color=(255, 255, 255))
    b.decal(kl, center=(kc[0] - 0.1501, kc[1], kc[2] + 0.05), normal=(-1, 0, 0), up=(0, 0, 1), mats=["kit_red"], depth=0.02)
    gl = DecalCanvas(0.40, 0.024, ppm=2500)
    for k, s_ in enumerate(("L", "M", "S")):
        gl.text(0.07 + k * 0.13, 0.012, f"GLOVES  {s_}", 0.0095, fnt="label", color=INK)
    b.decal(gl, center=(gx - 0.0701, gy, 1.24), normal=(-1, 0, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    for sx in (-1, 1):
        dl = DecalCanvas(0.62, 0.08, ppm=2000)
        dl.text(0.31, 0.025, "EMERGENCY EXIT", 0.022, fnt="label", color=(40, 44, 48), spacing=0.003)
        dl.text(0.31, 0.06, "LIFT LEVER TO OPEN", 0.013, fnt="label-semi", color=(100, 106, 110), spacing=0.002)
        b.decal(dl, center=(sx * 0.5, yd + 0.0401, 0.95), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_grey"], depth=0.01)
        st = DecalCanvas(0.06, 1.70, ppm=500)
        for k in range(18):
            st.polygon([(0, k * 0.1), (0.06, k * 0.1 - 0.06), (0.06, k * 0.1 - 0.01), (0, k * 0.1 + 0.05)], color=(206, 36, 40))
        b.decal(st, center=(sx * 0.03, yd + 0.0301, 0.98), normal=(0, 1, 0), up=(0, 0, 1), mats=["hosp_white"], depth=0.01)
    b.decal(rating_plate(0.10, 0.035, "PATIENT COMPARTMENT", "PC-43", "SN 26-00701", rating="12 V DC / 230 V~ inverter  ·  BAY 4.3 m",
                         ppm=3500), center=(XW - 0.0001, YR + 0.13, 1.10), normal=(-1, 0, 0), up=(0, 0, 1), mats=["bay_wall"], depth=0.01)
    b.decal(caution_label(0.12, 0.05, "WARNING", ["OXYGEN IN USE  -  NO SMOKING", "No naked flames in the patient compartment"],
                          kind="warning", ppm=3000), center=(-XW + 0.0001, YR + 0.42, 1.25), normal=(1, 0, 0), up=(0, 0, 1),
            mats=["bay_wall"], depth=0.01)

    # wall panel joints with riveted cover strips below the cabinets, anti-slip tread plate at the rear step
    for side, xw, nx in (("l", -XW, 1.0), ("r", XW, -1.0)):
        for y in np.arange(YR + 0.75, YF - 0.3, 0.72):
            sc = DecalCanvas(0.04, 1.30, ppm=1400)
            sc.rect(0.008, 0.0, 0.024, 1.30, color=(214, 218, 220), height=0.0006, spec=0.4, gloss=0.5)
            sc.groove([(0.008, 0.0), (0.008, 1.30)], width=0.0008, depth=0.0003)
            sc.groove([(0.032, 0.0), (0.032, 1.30)], width=0.0008, depth=0.0003)
            for k in range(7):
                sc.rivet(0.02, 0.06 + k * 0.195, 0.0035)
            b.decal(sc, center=(xw + nx * 0.0001, float(y), 0.66), normal=(nx, 0, 0), up=(0, 0, 1), mats=["bay_wall"], depth=0.01)
    tread = b.mat("tread_plate", layer="shell", color=(168, 172, 178), spec=0.7, gloss=0.55, metal=1.0, bump="diamond", bump_amp=0.0009,
                  bump_scale=0.03, grain=0.03, grain_scale=0.2, edge=0.4, dirt=0.45)
    b.add(box((BAY_W - 0.12, 0.22, 0.006), tread, r=0.002, seg=1, center=(0.0, YR + 0.12, 0.003), faces="+z +y -y +x -x", density=0.6))

    # ---- collision ---------------------------------------------------------------------------------------
    hw, hl = XW, BAY_L / 2
    b.col_box((-hw - 0.06, -hl - 0.06, -0.10), (hw + 0.06, hl + 0.06, 0.0), "PLASTIC_HIGH_DENSITY")
    b.col_box((-hw - 0.06, -hl - 0.06, BAY_H), (hw + 0.06, hl + 0.06, BAY_H + 0.10), "FIBREGLASS")
    b.col_box((-hw - 0.06, -hl, 0.0), (-hw, hl, BAY_H), "FIBREGLASS")
    b.col_box((hw, -hl, 0.0), (hw + 0.06, hl, BAY_H), "FIBREGLASS")
    b.col_box((-hw, hl, 0.0), (hw, hl + 0.06, BAY_H), "FIBREGLASS")
    b.col_box((-hw, -hl - 0.06, 0.0), (hw, -hl + 0.04, BAY_H), "METAL_HOLLOW_MEDIUM")
    for (mn, mx_) in (cab_l, cab_r):
        b.col_box(mn, mx_, "PLASTIC_HIGH_DENSITY")
    b.col_box((bx0, by0, 0.0), (hw, by1, SEAT_Z), "LEATHER")
    b.col_box((hw - 0.09, by0, SEAT_Z), (hw, by1, SEAT_Z + 0.55), "LEATHER")
    b.col_box((cx0, cy0, 0.0), (hw, hl, ctop), "PLASTIC_HIGH_DENSITY")
    b.col_box((cxs - 0.25, hl - 0.54, 0.0), (cxs + 0.25, hl, 0.51), "LEATHER")
    b.col_box((cxs - 0.25, hl - 0.11, 0.51), (cxs + 0.25, hl, 1.39), "LEATHER")
    b.col_box((-1.05, 1.85, 0.0), (-0.85, hl, 1.18), "METAL_SOLID_MEDIUM")
    b.col_box((-hw, PM_SHELF[1] - 0.2, PM_SHELF[2] - 0.2), (-hw + 0.26, PM_SHELF[1] + 0.2, PM_SHELF[2]), "METAL_SOLID_SMALL")
    b.col_box((sx_ - 0.13, 1.22, 0.0), (sx_ + 0.13, 1.38, 0.12), "METAL_SOLID_MEDIUM")
