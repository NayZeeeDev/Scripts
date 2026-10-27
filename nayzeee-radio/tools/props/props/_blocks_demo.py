"""
Building-blocks demo (NOT shipped, loads only with build.py --examples): one radio that uses most of
radio_common - d-pad, concentric knob pair, ridged PTT with guard ribs, round side buttons, a guarded
emergency key, gooseneck + ball-tip whip on an SMA nut, grille holes, battery pack + latch, belt clip,
lanyard eye, charging contacts, grip overmould, round connector with thumbscrews, labels. A visual
reference for the model engineers: build it and look at the renders.

    python3 tools/props/build.py --examples --only 'nzr_blocks*' --no-convert --quick
"""
from __future__ import annotations

from .common import screws
from .radio_common import (INK, battery_label, battery_pack, belt_clip, boss, charging_contacts, densify, dpad, gooseneck,
                           grille_holes, guard_ring, housing, key, knob_pair, lanyard_eye, latch_tab, light_pipe,
                           m_bumper_rubber, m_grip_rubber, m_keypad_rubber, m_ranger_green, m_sticker_vinyl, model_print,
                           overmould_panel, print_decal, ptt, ptt_guard, rating_label, round_button, round_connector,
                           screen_window, sma_nut, split_groove_y, thumbscrew, volume_dots, well_for, whip_antenna)
from .radio_kit import radio

W, D, H = 0.060, 0.034, 0.120
Z0 = -0.4 * H
ZT = Z0 + H
FY = D / 2
DF = 0.024                    # front shell depth; the battery pack fills the rest


@radio("blocks", parts=["dpad", "kok", "kback", "knob_ch", "knob_vol", "ptt", "side1", "side2", "emerg"], skin="mx905",
       code="BX-01", title="building blocks demo", export=False)
def blocks(r):
    green = m_ranger_green(r)
    rub = m_bumper_rubber(r)
    yb = FY - DF                                   # split between front shell and battery pack
    r.add(housing(r, green, W, DF, H, z0=Z0, center=(0.0, FY - DF / 2), chamfer=0.004, fillet=0.0012, rim=0.0014, dome=0.0005))
    r.add(battery_pack(r, green, W, D - DF - 0.0006, H - 0.004, yb, Z0 + 0.002))
    split_groove_y(r, [green], W, H, Z0 + H / 2, FY - 0.006, D)
    densify(r, 2.0, tags=["housing:side:+y", "housing:top"])
    # face: screen, d-pad with OK / back beside it, grille holes low
    screen_window(r, center=(0.0, FY, ZT - 0.034), view=(0.040, 0.030), margin=(0.003, 0.003))
    print_decal(r, model_print("BX-01", "BLOCKS", w=0.03, h=0.007, rule_color="orange"), center=(0.0, FY + 0.0005, ZT - 0.0085),
                normal=(0, 1, 0))
    floor = well_for(r, green, (0.0, FY, -0.004), (0, 1, 0), (0, 0, 1), (0.018, 0.018), gap=0.0006, corner=0.009)
    dpad(r, "dpad", at=(0.0, FY + floor, -0.004), size=0.018, kind="diamond", arrows="ridge", mat=m_keypad_rubber(r, "grey"))
    key(r, "kok", at=(-0.019, FY, -0.004), size=(0.008, 0.008), corner=0.004, glyph="check", glyph_color=INK["green"], depth=0.0012)
    key(r, "kback", at=(0.019, FY, -0.004), size=(0.008, 0.008), corner=0.004, glyph="back", depth=0.0012)
    r.add(grille_holes(r, (0.0, FY, Z0 + 0.016), cols=9, rows=4, pitch=0.0024, hole_r=0.0006))
    # top deck: concentric knobs on a boss, guarded emergency key, gooseneck + whip on an SMA nut, light pipe
    r.add(boss(r, green, (0.016, -0.002, ZT), d=0.017, h=0.002, shaft_d=0.006, shaft_h=0.004))
    knob_pair(r, "knob_ch", "knob_vol", base=(0.016, -0.002, ZT + 0.002), d_outer=0.016, h_outer=0.008, d_inner=0.010, h_inner=0.007)
    print_decal(r, volume_dots(8, 0.014, 0.003), center=(0.016, 0.009, ZT + 0.0002), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0015,
                mats=[green])
    r.add(guard_ring(r, rub, (0.0, 0.004, ZT), d_in=0.009, d_out=0.014, h=0.003))
    key(r, "emerg", at=(0.0, 0.004, ZT), normal=(0, 0, 1), up=(0, 1, 0), size=(0.0075, 0.0075), corner=0.00375, t=0.0022,
        mat=r.mat("emerg_orange", color=(232, 106, 26), spec=0.4, gloss=0.55, bump="dimple", bump_amp=0.00006, bump_scale=0.0008,
                  edge=0.4), depth=0.0012)
    r.add(sma_nut(r, (-0.015, -0.002, ZT), across=0.008, h=0.004, finish="black"))
    r.add(gooseneck(r, (-0.015, -0.002, ZT + 0.007), length=0.03))
    r.add(whip_antenna(r, (-0.015, -0.002, ZT + 0.037), length=0.12, d0=0.007, d1=0.0045, cap="ball", collar_h=0.006, collar_ribs=2))
    pipe, insert = light_pipe(r, (-0.004, -0.009, ZT), d=0.003, color="green")
    r.add(pipe)
    # left side (+X): guarded PTT and two side buttons
    sx = W / 2
    floor = well_for(r, rub, (sx, FY - 0.012, 0.012), (1, 0, 0), (0, 0, 1), (0.012, 0.030), gap=0.0006, margin=0.0015, corner=0.005)
    ptt(r, "ptt", at=(sx + floor, FY - 0.012, 0.012), length=0.030, width=0.012)
    r.add(ptt_guard(r, rub, (sx + 0.0012, FY - 0.012, 0.012), length=0.034))
    for pid, z in (("side1", -0.012), ("side2", -0.022)):
        f2 = well_for(r, rub, (sx, FY - 0.012, z), (1, 0, 0), (0, 0, 1), (0.006, 0.006), corner=0.003, margin=0.001, t=0.0008)
        round_button(r, pid, (sx + f2, FY - 0.012, z), (1, 0, 0), d=0.006, mat=m_keypad_rubber(r))
    # right side (-X): grip overmould, round connector held by thumbscrews
    r.add(overmould_panel(r, m_grip_rubber(r, "knurl"), (-sx, FY - 0.012, -0.01), (-1, 0, 0), (0, 0, 1), 0.016, 0.05))
    r.add(round_connector(r, (-sx, FY - 0.012, 0.035), (-1, 0, 0), d=0.012))
    for z in (0.024, 0.046):
        r.add(thumbscrew(r, (-sx, FY - 0.012, z), (-1, 0, 0), d=0.005, h=0.0025))
    # back: latch, label, clip; bottom: contacts + lanyard eye
    yback = yb - (D - DF - 0.0006) - 0.0006
    r.add(latch_tab(r, rub, (0.0, yback, Z0 + 0.008), (0, -1, 0), (0, 0, 1), w=0.014, h=0.006))
    print_decal(r, battery_label(0.044, 0.026, pack="BP-01"), center=(0.0, yback, Z0 + 0.03), normal=(0, -1, 0), mats=[green])
    r.add(belt_clip(r, (0.0, yback, ZT - 0.02), w=0.03, length=0.06))
    r.add(charging_contacts(r, (0.0, FY - 0.016, Z0), (0, 0, -1), (0, 1, 0)))
    r.add(lanyard_eye(r, (-W / 2 + 0.006, FY - 0.017, Z0), (0, 0, -1), (0, 1, 0)))
    r.hi_only(screws(r, [(sx * 0.026, FY + 0.0003, z) for sx in (-1, 1) for z in (Z0 + 0.006, ZT - 0.006)], (0, 1, 0), d=0.0028,
                     kind="torx"))
    print_decal(r, rating_label(0.032, 0.013, model="BX-01", serial="SN 26-00002", ident="ID: TXQ-BX01"), center=(-W / 2, -0.002, -0.03),
                normal=(-1, 0, 0), mats=[green])
    r.add(housing(r, rub, W + 0.0012, D + 0.0012, 0.006, z0=Z0 - 0.0006, chamfer=0.0045, fillet=0.0014, rim=0.0016))
    _ = m_sticker_vinyl
    r.anchor(focus=(0.0, FY, ZT - 0.04), camDist=0.36, leds={"tx": insert, "rx": insert}, grip="demo")
