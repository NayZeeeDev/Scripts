#!/usr/bin/env python3
"""Numeric check of the turntable props against the shared contract ("Turntable geometry").

    python3 models/_check_turntable.py          (or: python3 -m models._check_turntable)

Builds nayzeee_audio_g, nayzeee_tt_platter, nayzeee_tt_arm and nayzeee_vinyl at High detail, places
them at the contract offsets and asserts:
  * key heights / radii: record top, slipmat top, spindle top + radius, platter radius, stylus tip,
    arm rest top, model origins, anchors in the specs;
  * the stylus lands on the groove radius at the arm angles for the lead-in / run-out (law of cosines)
    and sits within 1 mm of the record top;
  * clearances: the parked arm is clear of the platter and record and lies on the rest; the arm swung
    (level and lifted 3 deg) from the rest to the run-out never goes into the console, the platter, the
    record or the spindle (dense surface samples of the arm vs. a 0.25 mm height field of the rest).
The file name starts with "_" so the model registry skips it.  Exit code 1 on any failure.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import models  # noqa: E402
from lib import mesh as M  # noqa: E402
from models import _tt_common as C  # noqa: E402

FAILS: list = []


def check(cond, msg):
    print(("  ok    " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILS.append(msg)


def near(a, b, tol=1e-6):
    return abs(float(a) - float(b)) <= tol


# --------------------------------------------------------------------------- geometry helpers
def placed(parts, pos=(0, 0, 0), rz=0.0, rx=0.0):
    """Copies of parts transformed by T(pos) * Rz * Rx (GTA entity rotation for these props)."""
    R = M.compose(M.translation_matrix(pos), M.rotation_matrix("z", rz), M.rotation_matrix("x", rx))
    return [p.transform(R) for p in parts]


def surface_samples(parts, spacing=0.0005):
    """Points on every triangle (vertices + a barycentric grid at ``spacing``), with the part index."""
    pts, owner = [], []
    for k, p in enumerate(parts):
        T = p.positions[p.indices]                                       # (n,3,3)
        e = np.maximum(np.linalg.norm(T[:, 1] - T[:, 0], axis=1), np.linalg.norm(T[:, 2] - T[:, 0], axis=1))
        n = np.clip(np.ceil(e / spacing).astype(int), 1, 60)
        for s in np.unique(n):
            sel = T[n == s]
            a, b = np.meshgrid(np.arange(s + 1), np.arange(s + 1), indexing="ij")
            keep = (a + b) <= s
            u, v = a[keep] / s, b[keep] / s
            P = sel[:, 0, None, :] + u[None, :, None] * (sel[:, 1] - sel[:, 0])[:, None, :] \
                + v[None, :, None] * (sel[:, 2] - sel[:, 0])[:, None, :]
            P = P.reshape(-1, 3)
            pts.append(P)
            owner.append(np.full(len(P), k))
    return np.vstack(pts), np.concatenate(owner)


class HeightField:
    """Max surface height on a regular xy grid (cell-centre point samples of every triangle)."""

    def __init__(self, x0, x1, y0, y1, res=0.00025):
        self.x0, self.y0, self.res = x0, y0, res
        self.nx, self.ny = int(round((x1 - x0) / res)), int(round((y1 - y0) / res))
        self.H = np.full((self.ny, self.nx), -np.inf)

    def add(self, parts, zmin=-np.inf):
        for p in parts:
            T = p.positions[p.indices]
            T = T[T[:, :, 2].max(axis=1) > zmin]
            for t in T:
                lo, hi = t[:, :2].min(axis=0), t[:, :2].max(axis=0)
                i0 = max(int(np.floor((lo[0] - self.x0) / self.res - 0.5)), 0)
                i1 = min(int(np.ceil((hi[0] - self.x0) / self.res - 0.5)), self.nx - 1)
                j0 = max(int(np.floor((lo[1] - self.y0) / self.res - 0.5)), 0)
                j1 = min(int(np.ceil((hi[1] - self.y0) / self.res - 0.5)), self.ny - 1)
                if i1 < i0 or j1 < j0:
                    continue
                (ax, ay, az), (bx, by, bz), (cx, cy, cz) = t
                det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
                if abs(det) < 1e-14:
                    continue                                        # vertical wall: its top edge is shared
                xs = self.x0 + (np.arange(i0, i1 + 1) + 0.5) * self.res
                ys = self.y0 + (np.arange(j0, j1 + 1) + 0.5) * self.res
                X, Y = np.meshgrid(xs, ys)
                l1 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / det
                l2 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / det
                l3 = 1 - l1 - l2
                ins = (l1 >= -1e-9) & (l2 >= -1e-9) & (l3 >= -1e-9)
                if not ins.any():
                    continue
                Z = np.where(ins, l1 * az + l2 * bz + l3 * cz, -np.inf)
                sub = self.H[j0:j1 + 1, i0:i1 + 1]
                np.maximum(sub, Z, out=sub)

    def at(self, P):
        i = np.floor((P[:, 0] - self.x0) / self.res).astype(int)
        j = np.floor((P[:, 1] - self.y0) / self.res).astype(int)
        ok = (i >= 0) & (i < self.nx) & (j >= 0) & (j < self.ny)
        out = np.full(len(P), -np.inf)
        out[ok] = self.H[j[ok], i[ok]]
        return out


def main() -> int:
    print("building High LOD models ...")
    con = models.build("nayzeee_audio_g", 1.0)
    pla = models.build("nayzeee_tt_platter", 1.0)
    arm = models.build("nayzeee_tt_arm", 1.0)
    vin = models.build("nayzeee_vinyl", 1.0)
    for s in (con, pla, arm, vin):
        check(not s.problems(), f"{s.name}: spec has no problems {s.problems()[:3]}")

    def bounds(parts):
        P = np.vstack([p.positions for p in parts])
        return P.min(axis=0), P.max(axis=0)

    def part(spec, name):
        ps = [p for p in spec.parts if p.name == name]
        assert ps, f"{spec.name} has no part {name!r}"
        return M.merge(ps, material=ps[0].material)       # geometry only (parts may mix materials)

    print("\ncontract numbers")
    lo, hi = bounds(con.parts)
    check(near(lo[2], 0.0), f"console origin on the floor: min z {lo[2]:.6f} == 0")
    check(lo[0] >= C.CAB_X[0] - 1e-9 and hi[0] <= C.CAB_X[1] + 1e-9 and lo[1] >= C.CAB_Y[0] - 1e-9
          and hi[1] <= C.CAB_Y[1] + 1e-9, f"console within footprint X{C.CAB_X} Y{C.CAB_Y}: "
                                           f"x [{lo[0]:.4f}, {hi[0]:.4f}] y [{lo[1]:.4f}, {hi[1]:.4f}]")
    for nm, z in (("plinth_top", C.DECK_TOP), ("panel_top", C.DECK_TOP)):
        check(near(part(con, nm).bbox()[1][2], z), f"console {nm} at z {z}")
    cab = part(con, "cabinet")
    check(near(cab.bbox()[1][2], C.CAB_TOP) and near(cab.bbox()[0][2], C.LEG_TOP),
          f"cabinet body z {C.LEG_TOP}..{C.CAB_TOP}: {cab.bbox()[0][2]:.4f}..{cab.bbox()[1][2]:.4f}")
    pt = part(con, "plinth_top").bbox()
    check(pt[0][0] > C.PLINTH_X[0] and pt[1][0] < C.PLINTH_X[1] and pt[0][1] > C.PLINTH_Y[0]
          and pt[1][1] < C.PLINTH_Y[1], "deck plinth inside X[0.02,0.48] Y[-0.19,0.19]")
    pb = part(con, "plinth_edge").bbox()
    check(near(pb[0][0], C.PLINTH_X[0], 1e-5) and near(pb[1][0], C.PLINTH_X[1], 1e-5),
          f"deck plinth spans X {pb[0][0]:.4f}..{pb[1][0]:.4f}")

    plo, phi = bounds(pla.parts)
    check(near(plo[2], 0.0), f"platter origin = bottom centre (min z {plo[2]:.6f})")
    check(near(max(abs(plo[0]), abs(phi[0]), abs(plo[1]), abs(phi[1])), C.PLATTER_R, 1e-6),
          f"platter radius {max(phi[0], phi[1]):.6f} == {C.PLATTER_R}")
    slip = part(pla, "slipmat")
    check(near(slip.bbox()[1][2], C.SLIPMAT_TOP), f"slipmat top local z {slip.bbox()[1][2]:.6f} == {C.SLIPMAT_TOP}")
    check(near(C.PLATTER_OFFSET[2] + C.SLIPMAT_TOP, C.RECORD_OFFSET[2]), "slipmat top = record seat (console z 0.811)")
    sp = part(pla, "spindle")
    check(near(sp.bbox()[1][2], C.SPINDLE_TOP), f"spindle top local z {sp.bbox()[1][2]:.6f} == {C.SPINDLE_TOP}")
    spr = np.linalg.norm(sp.positions[:, :2], axis=1).max()
    check(near(spr, C.SPINDLE_R), f"spindle radius {spr:.6f} == {C.SPINDLE_R}")
    above = np.vstack([p.positions for p in pla.parts if p.name != "spindle"])
    check(above[:, 2].max() <= C.SLIPMAT_TOP + 1e-9, "only the spindle rises above the slipmat (record lies flat)")

    vlo, vhi = bounds(vin.parts)
    check(near(vlo[2], 0.0) and near(max(vhi[0], vhi[1]), C.RECORD_R, 1e-6),
          f"record origin = bottom centre, radius {max(vhi[0], vhi[1]):.6f}")
    body = part(vin, "vinyl")
    rr = np.linalg.norm(body.positions[:, :2], axis=1)
    zz = body.positions[:, 2]
    groove = zz[(rr > C.LABEL_R + 0.0002) & (rr < C.RECORD_R - 0.0035) & (zz > 0.001)]     # flat playing annulus
    check(near(groove.max(), C.RECORD_T) and near(groove.min(), C.RECORD_T),
          f"record playing surface at local z {C.RECORD_T} (console {C.RECORD_OFFSET[2] + C.RECORD_T:.4f})")
    hole = part(vin, "spindle_hole")
    hr = np.linalg.norm(hole.positions[:, :2], axis=1).min()
    check(hr > C.SPINDLE_R, f"record hole radius {hr:.5f} > spindle {C.SPINDLE_R}")
    record_top = C.RECORD_OFFSET[2] + C.RECORD_T

    tip = part(arm, "stylus_tip")
    k = int(np.argmin(tip.positions[:, 2]))
    check(np.allclose(tip.positions[k], C.STYLUS_LOCAL, atol=1e-7),
          f"stylus tip at arm-local {np.round(tip.positions[k], 6).tolist()} == {list(C.STYLUS_LOCAL)}")
    arm_all = np.vstack([p.positions for p in arm.parts])
    check(arm_all[:, 2].min() < -0.04 and abs(arm_all[:, 0]).max() < 0.03,
          "arm origin is the pivot (pillar below it, parts around the Z axis)")
    level_tip_z = C.ARM_OFFSET[2] + C.STYLUS_LOCAL[2]
    check(abs(level_tip_z - record_top) <= 0.001, f"level stylus z {level_tip_z:.4f} within 1 mm of the record top "
                                                  f"{record_top:.4f} ({(level_tip_z - record_top) * 1000:+.2f} mm)")
    tube = part(arm, "arm_tube")
    tb = tube.bbox()
    check(near(tb[0][2], C.ARM_REST_TOP - C.ARM_OFFSET[2]) and tb[1][1] > C.ARM_REST_LOCAL_Y,
          f"arm tube underside local z {tb[0][2]:.4f} == rest top - pivot ({C.ARM_REST_TOP - C.ARM_OFFSET[2]:.4f}) "
          f"along y {tb[0][1]:.3f}..{tb[1][1]:.3f} (rest at {C.ARM_REST_LOCAL_Y})")

    cr = part(con, "rest_cradle")
    # notch bottom on the cradle's centre line, away from the rounded front/back edges (bevel 0.7 mm)
    cy = cr.positions[:, 1]
    mid_y = (cy.min() + cy.max()) / 2
    near_axis = cr.positions[(np.abs(cr.positions[:, 0] - C.ARM_REST_XY[0]) < 1e-4)
                             & (np.abs(cy - mid_y) < (cy.max() - cy.min()) / 2 - 0.0007 + 1e-6)]
    check(near(near_axis[:, 2].min(), C.ARM_REST_TOP, 1e-5) and
          near(near_axis[:, 1].mean(), C.ARM_REST_XY[1], 1e-3),
          f"arm rest cradle bottom at console ({C.ARM_REST_XY[0]}, {near_axis[:, 1].mean():.4f}, "
          f"{near_axis[:, 2].min():.5f})")

    print("\nanchors (layout.json)")
    a = con.anchors
    for key, val in (("platter_offset", C.PLATTER_OFFSET), ("record_offset", C.RECORD_OFFSET),
                     ("arm_offset", C.ARM_OFFSET), ("stylus_local", C.STYLUS_LOCAL),
                     ("arm_rest_local", (C.ARM_REST_XY[0], C.ARM_REST_XY[1], C.ARM_REST_TOP)),
                     ("lead_in_radius", (C.LEAD_IN, 0, 0)), ("run_out_radius", (C.RUN_OUT, 0, 0)),
                     ("platter_radius", (C.PLATTER_R, 0, 0)), ("record_radius", (C.RECORD_R, 0, 0))):
        check(key in a and np.allclose(a[key].pos, val, atol=1e-9), f"console anchor {key} = {list(val)}")

    print("\narm angles (law of cosines)")
    piv = np.array(C.ARM_OFFSET)
    centre = np.array(C.PLATTER_OFFSET[:2])
    for r, expect in ((C.LEAD_IN, -27.5), (0.12, -33.6), (C.RUN_OUT, -47.0)):
        th = C.arm_angle(r)
        t = placed([tip], C.ARM_OFFSET, th)[0]
        p = t.positions[int(np.argmin(t.positions[:, 2]))]
        d = np.linalg.norm(p[:2] - centre)
        check(abs(d - r) < 1e-6 and abs(th - expect) < 0.06,
              f"r {r:.3f}: arm {th:+.2f} deg (expected ~{expect}) -> stylus at radius {d:.6f}, z {p[2]:.4f}")

    print("\nheight fields (console deck, platter, record; 0.25 mm)")
    hf_con = HeightField(-0.02, 0.50, -0.21, 0.21)
    con_no_rest = [p for p in con.parts if p.name != "rest_cradle"]
    hf_con.add(con_no_rest, zmin=C.CAB_TOP - 0.01)
    hf_rest = HeightField(-0.02, 0.50, -0.21, 0.21)
    hf_rest.add([p for p in con.parts if p.name == "rest_cradle"])
    hf_tt = HeightField(-0.02, 0.50, -0.21, 0.21)
    hf_tt.add(placed(pla.parts, C.PLATTER_OFFSET))
    hf_tt.add(placed(vin.parts, C.RECORD_OFFSET))
    # platter / record must sit on the deck, not in it
    ps, _ = surface_samples(placed(pla.parts, C.PLATTER_OFFSET), 0.002)
    pen = np.max(hf_con.at(ps) - ps[:, 2])
    check(pen <= 1e-6, f"platter does not sink into the deck (max penetration {pen * 1000:.3f} mm)")

    print("\nclearances")
    collar_parts = {"pillar", "height_ring"}      # designed to sit inside the console collar
    needle_parts = {"stylus_tip", "cantilever"}   # allowed to touch the record when playing
    arm_parts = arm.parts
    samples_local, owner = surface_samples(arm_parts, 0.0005)
    names = np.array([p.name for p in arm_parts])[owner]
    in_collar = np.isin(names, list(collar_parts))
    is_needle = np.isin(names, list(needle_parts))
    print(f"  ({len(samples_local)} surface samples on the arm)")

    def pose(rz, rx):
        R = M.compose(M.translation_matrix(C.ARM_OFFSET), M.rotation_matrix("z", rz), M.rotation_matrix("x", rx))
        return samples_local @ R[:3, :3].T + R[:3, 3]

    # collar: pillar radius vs collar bore, height ring above the collar top
    col = part(con, "arm_collar")
    bore = np.linalg.norm(col.positions[:, :2] - np.array(C.ARM_OFFSET[:2]), axis=1).min()
    pil = part(arm, "pillar")
    pr = np.linalg.norm(pil.positions[:, :2], axis=1).max()
    ring_bottom = C.ARM_OFFSET[2] + part(arm, "height_ring").bbox()[0][2]
    check(pr < bore and ring_bottom > col.bbox()[1][2],
          f"pillar r {pr:.4f} fits the collar bore {bore:.4f}; height ring {ring_bottom:.4f} above collar top "
          f"{col.bbox()[1][2]:.4f}")
    lift_shift = (C.ARM_OFFSET[2] - col.bbox()[1][2]) * math.sin(math.radians(C.ARM_LIFT_DEG))
    check(pr + lift_shift <= bore + 0.0003, f"pillar stays in the bore when lifted {C.ARM_LIFT_DEG} deg "
                                           f"(shift {lift_shift * 1000:.2f} mm, gap {(bore - pr) * 1000:.2f} mm)")

    # parked: on the rest, clear of the platter and record
    P = pose(0.0, 0.0)
    dxy = np.linalg.norm(P[:, :2] - centre, axis=1).min()
    check(dxy > C.PLATTER_R + 0.01, f"parked arm clear of the platter/record by {(dxy - C.PLATTER_R) * 1000:.1f} mm")
    pen = np.max((hf_con.at(P) - P[:, 2])[~in_collar])
    check(pen <= 0.0002, f"parked arm not inside the console (max {pen * 1000:.3f} mm)")
    lowest = P[np.abs(P[:, 1] - C.ARM_REST_XY[1]) < 0.0025][:, 2].min()
    check(near(lowest, C.ARM_REST_TOP, 2e-5), f"parked arm tube rests on the rest top: {lowest:.5f} vs {C.ARM_REST_TOP}")
    # the cradle wraps the tube: notch radius vs tube radius, coaxial
    pen_rest = np.max(hf_rest.at(P) - P[:, 2])
    check(pen_rest <= 0.0015, f"tube sits in the cradle notch (height-field residue {pen_rest * 1000:.2f} mm, "
                              f"grid-limited at the notch walls)")

    # swinging: every 1 deg from the rest to past the run-out, lifted and level
    worst = {"console": (-1, None), "deck": (-1, None), "spindle": (-1, None)}
    stops = np.arange(0.0, C.arm_angle(C.RUN_OUT) - 2.0, -1.0)
    for rz in stops:
        for rx in (C.ARM_LIFT_DEG, 0.0):
            P = pose(rz, rx)
            pc = np.max((hf_con.at(P) - P[:, 2])[~in_collar])
            pr_ = np.max((hf_rest.at(P) - P[:, 2])) if rz < -6 else -1
            over = hf_tt.at(P) - P[:, 2]
            ptt = np.max(over[~is_needle]) if rx == 0.0 else np.max(over)
            for key, v in (("console", max(pc, pr_)), ("deck", ptt)):
                if v > worst[key][0]:
                    worst[key] = (v, (rz, rx))
            # the spindle: closest approach of the arm (below the spindle top) to its axis
            low = P[:, 2] < C.PLATTER_OFFSET[2] + C.SPINDLE_TOP + 0.001
            if low.any():
                dsp = np.linalg.norm(P[low, :2] - centre, axis=1).min()
                if -dsp > worst["spindle"][0] or worst["spindle"][1] is None:
                    worst["spindle"] = (-dsp, (rz, rx))
    v, at = worst["console"]
    check(v <= 0.0002, f"swinging arm never enters the console (worst {v * 1000:+.3f} mm at rz {at[0]:.0f}, rx {at[1]})")
    v, at = worst["deck"]
    check(v <= 0.0, f"swinging arm never enters the platter or record, needle excepted when level "
                    f"(worst {v * 1000:+.3f} mm at rz {at[0]:.0f}, rx {at[1]})")
    v, at = worst["spindle"]
    check(-v > C.SPINDLE_R + 0.002, f"arm parts below the spindle tip stay {(-v) * 1000:.1f} mm from its axis "
                                    f"(rz {at[0]:.0f}, rx {at[1]})")
    # playing: the needle tip on the record, nothing else touching
    for r in (C.LEAD_IN, 0.104, C.RUN_OUT):
        th = C.arm_angle(r)
        P = pose(th, 0.0)
        over = hf_tt.at(P) - P[:, 2]
        tipz = P[is_needle][:, 2].min()
        clear = -np.max(over[~is_needle])
        # contract: tip at pivot z - 0.022 = 0.813, record top 0.8132 -> the tip sits 0.2 mm into the groove
        check(abs(tipz - record_top) <= 0.001 and clear > 0.0005,
              f"playing at r {r:.3f} ({th:+.1f} deg): needle {(tipz - record_top) * 1000:+.2f} mm from the record "
              f"top (in the groove), rest of the arm >= {clear * 1000:.2f} mm clear")
        Pl = pose(th, C.ARM_LIFT_DEG)
        tip_l = Pl[is_needle][:, 2].min() - record_top
        check(tip_l > 0.005, f"lifted {C.ARM_LIFT_DEG} deg at r {r:.3f}: needle {tip_l * 1000:.1f} mm above the record")

    print()
    if FAILS:
        print(f"{len(FAILS)} FAILED")
        return 1
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
