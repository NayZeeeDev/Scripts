"""
Example radio (NOT shipped): the smallest complete use of the radio kit - two keys, a knob, a screen,
a rubber-duck antenna and a light pipe. build.py only imports modules whose name starts with '_' when it runs
with --examples (or NZR_PROPS_EXAMPLE=1); selftest.py builds it to prove the kit end to end:
full / body / part models, anchors, the generated layout and the assembled review render.

Models: nzr_example, nzr_example_body, nzr_example_k1, nzr_example_k2, nzr_example_knob_ch
(export=False: never streamed, never in nzr_props.ytyp, never in shared/props_layout.lua).
"""
from __future__ import annotations

from .radio_common import (boss, densify, housing, ink, keypad, knob, knob_scale, light_pipe, m_bumper_rubber, m_soft_black, model_print,
                           print_decal, rating_label, rubber_duck, screen_window, sma_nut, split_groove_z)
from .radio_kit import radio
from .common import screws

W, D, H = 0.046, 0.028, 0.090        # body (without knob / antenna)
Z0 = -0.4 * H                        # origin = grip point: 40 % of the body height from its bottom
ZT = Z0 + H                          # top deck
FY = D / 2                           # front face


@radio("example", parts=["k1", "k2", "knob_ch"], skin="px740", code="EX-100", title="EX-100 demo radio", export=False,
       atlas=512, part_atlas=128)
def example(r):
    shell = m_soft_black(r)
    r.add(housing(r, shell, W, D, H, z0=Z0, chamfer=0.0025, fillet=0.001, rim=0.001, dome=0.0004))
    densify(r, 2.0, tags="housing:side:+y")         # the printed front gets twice the texels
    split_groove_z(r, [shell], W, D, Z0 + 0.012)
    # screen window high on the front, model print above it
    screen_window(r, center=(0.0, FY, ZT - 0.026), view=(0.028, 0.021))
    print_decal(r, model_print("EX-100", "DEMO", w=0.024, h=0.0065), center=(0.0, FY + 0.0004, ZT - 0.0075), normal=(0, 1, 0))
    # two keys in a surround plate
    keypad(r, [[("k1", "1", ".,?"), ("k2", "2", "ABC")]], center=(0.0, FY, Z0 + 0.028), pitch=(0.0145, 0.009), size=(0.012, 0.007))
    # top deck: channel knob on a boss, antenna on an SMA nut, light pipe between them
    r.add(boss(r, shell, (0.012, 0.0, ZT), d=0.014, h=0.0025, shaft_d=0.0055, shaft_h=0.005))
    knob(r, "knob_ch", base=(0.012, 0.0, ZT + 0.0025), d=0.012, h=0.013, ribs=16, value="channel", detents=16)
    deck = knob_scale(0.012, n=16, color="white")
    print_decal(r, deck, center=(0.012, 0.0, ZT + 0.0001), normal=(0, 0, 1), up=(0, 1, 0), depth=0.0015, mats=[shell])
    r.add(sma_nut(r, (-0.011, 0.0, ZT), across=0.008, h=0.0035))
    r.add(rubber_duck(r, (-0.011, 0.0, ZT + 0.0065), length=0.07, d=0.0095))
    pipe, insert = light_pipe(r, (0.0, 0.004, ZT), normal=(0, 0, 1), up=(0, 1, 0), d=0.003)
    r.add(pipe)
    # bottom bumper + back screws + rating plate
    r.add(housing(r, m_bumper_rubber(r), W + 0.001, D + 0.001, 0.004, z0=Z0 - 0.0005, chamfer=0.003, fillet=0.0012, rim=0.0012))
    r.hi_only(screws(r, [(sx * 0.016, -FY, Z0 + z) for sx in (-1, 1) for z in (0.012, 0.075)], (0, -1, 0), d=0.0032, kind="torx"))
    print_decal(r, rating_label(0.03, 0.012, model="EX-100", serial="SN 26-00001", ident="ID: TXQ-EX100"), center=(0.0, -FY - 0.0002, Z0 + 0.04),
                normal=(0, -1, 0), mats=[shell])
    _ = ink
    r.anchor(focus=(0.0, FY, ZT - 0.03), camDist=0.30, leds={"tx": insert, "rx": insert},
             grip="PH_R_Hand (28422), palm on the back, thumb on the side; tune with /radiogrip")
