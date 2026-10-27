"""
LED lens inserts (PROPS_BRIEF section 4, SPEC section 9.1): nzr_led_red, nzr_led_green, nzr_led_amber.

A tiny lit dome lens (3 mm) the client attaches to a raised radio body at layout leds.tx / leds.rx while
it transmits (red), receives (green) or signals an emergency (amber, blinking). One insert fits the light
pipe of every radio: origin = the lens base on the light-pipe insert point, facing +Z, same orientation
as the body (AttachEntityToEntity with zero rotation).

Construction: a dark collar ring seated in the light-pipe bezel, the emissive dome lens and a brighter
die spot in its centre (reads as a lit LED die through a diffused lens, not a flat blob).
"""
from __future__ import annotations

import math

import numpy as np

from nzprops import lathe, register

from .common import m_led
from .radio_common import LED_COLORS, led_dome

D_LENS = 0.003


def _hot(color, k=0.55):
    """The LED colour pushed towards white (the lit die)."""
    return tuple(int(c + (255 - c) * k) for c in color)


def _insert(color):
    def build(b):
        R, h, base_h = D_LENS / 2, D_LENS * 0.42, 0.0003
        b.add(led_dome(b, color, d=D_LENS, h=h, base_h=base_h))
        # lit die: a brighter cap following the dome (ellipsoid R x h) 0.03 mm above it, 42 % of the lens across -
        # reads as the LED die glowing through a diffused lens instead of a flat blob
        core = m_led(b, f"led_{color}_die", _hot(LED_COLORS[color]))
        rc = R * 0.42
        prof = [(x, base_h + h * math.sqrt(max(0.0, 1 - (x / R) ** 2)) + 0.00003) for x in np.linspace(rc, 0.0, 5)]
        b.add(lathe(prof, core, segs=16, smooth_angle=70, tag="led_die"))
        b.col_box((-R, -R, 0.0), (R, R, base_h + h), "PLASTIC")
        b.anchor(kind="led_insert", color=color, d=D_LENS, origin="lens base on the light-pipe insert point (layout leds.tx / rx)")
    build.__name__ = f"led_{color}"
    return build


for _c, _word in (("red", "transmit"), ("green", "receive"), ("amber", "emergency")):
    register(f"nzr_led_{_c}", _insert(_c), module=__name__, atlas=64, alpha_atlas=64, glow_atlas=32, lod=12.0, hd=3.0, budget=400,
             preview={"views": ["front", "face", "top"]},
             doc={"title": f"LED lens insert - {_c} ({_word})",
                  "origin": "lens base = the light-pipe insert point (layout leds.tx / leds.rx)",
                  "axes": "+Z out of the light pipe (radio top), same orientation as the radio body",
                  "attach": "AttachEntityToEntity(led, body, 0, leds.tx|rx, 0, 0, 0, ...) while raised: red TX, green RX, amber "
                            "blinking during an emergency (client/modules/held.lua)"})

__all__ = []
