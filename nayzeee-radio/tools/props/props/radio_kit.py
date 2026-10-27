"""
Radio kit - ONE design function produces every model of a radio (SPEC section 9.1):

    nzr_<m>           complete radio, every part baked in, idle screen image      (seen by everyone else)
    nzr_<m>_body      the same radio WITHOUT the pressable parts (their wells / bosses stay visible) and a
                      near-black screen placeholder that the client replaces with the live DUI
    nzr_<m>_<partid>  one model per pressable part, origin = the part's anchor (its rest position on the
                      body), same orientation as the body - the client attaches it to the body at `pos`

Writing a radio (tools/props/props/<radio>.py):

    from .radio_kit import radio
    from .radio_common import *

    @radio("handheld", title="PX-740 patrol handheld")          # parts default to SPEC section 9.2's list
    def handheld(r):                                           # r: RadioBuilder (a nzprops Builder)
        body = m_soft_black(r)
        r.add(housing(r, body, 0.058, 0.038, 0.132, z0=-0.053))
        screen_window(r, center=(0, 0.0195, 0.03), view=(0.036, 0.027))
        key(r, "k1", at=(0.012, 0.019, -0.02), size=(0.011, 0.0065), legend="1", sub=".,?")
        knob(r, "knob_ch", base=(0.014, 0, 0.079), d=0.012, h=0.014, value="channel", detents=16)
        ...
        r.anchor(focus=(0, 0.019, 0.005), camDist=0.34, leds={"tx": (...), "rx": (...)}, grip="...")

Every pressable part is created inside `with r.part(pid, ...)` (the radio_common helpers key(), dpad(),
knob(), knob_pair(), ptt(), round_button() do that for you) with its metadata:

    origin   anchor = the part model's origin: centre of the clickable face at rest (keys / buttons) or
             the point on the rotation axis at half height (knobs)
    press    unit vector the part moves along when pressed (into the body), depth = travel in metres
    u, v     half-extent vectors of the clickable face (hit test: origin +- u +- v), shape 'rect' | 'round'
    action / value   firmware vocabulary (SPEC section 6); inferred from the part id when omitted
    axis / detents   knobs (rotation axis, steps per turn);   tilt   d-pad rocker tilt in degrees

Everything added inside the block (geometry AND decals) belongs to that part: decals only print on
their own part, so key legends never bleed onto the body and body prints never land on a key cap.
The body model keeps everything added outside part blocks; part models keep only their part, moved so
the anchor is the origin. The kit computes collisions (housing box + antenna cylinder) unless you call
r.col_box / r.col_cyl, adds review cameras (face, 3/4, sides, back, top, keypad, top deck, screen, PTT
close-ups) and an 'assembled' render (body + every part placed at its anchor) that build.py compares
with the complete model pixel by pixel.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from dataclasses import replace as dc_replace

import numpy as np

from nzprops import REGISTRY, Builder, Geo, register
from nzprops.bake import Decal
from nzprops.mesh import normalize, vec

from .radio_screens import SKINS, idle_screen, placeholder_screen

# ---------------------------------------------------------------------------------------------
# contract (SPEC sections 3, 6, 9)
# ---------------------------------------------------------------------------------------------
_DIGITS = [f"k{i}" for i in range(10)]
RADIO_PARTS = {
    "handheld": _DIGITS + ["kstar", "khash", "kok", "kback", "kp1", "kp2", "dpad", "knob_ch", "knob_vol", "emerg", "ptt",
                           "side1", "side2"],
    "fieldpro": _DIGITS + ["kstar", "khash", "kup", "kdown", "kmenu", "kset", "kband", "kpower", "knob_ch", "knob_vol", "ptt",
                           "side1", "emerg"],
    "military": _DIGITS + ["kstar", "khash", "kok", "kback", "kup", "dpad", "knob_ch", "knob_vol", "emerg", "ptt", "side1",
                           "side2"],
}
RADIO_SKINS = {"handheld": "px740", "fieldpro": "fx280", "military": "mx905"}
ACTIONS = {"digit", "star", "hash", "ok", "back", "menu", "up", "down", "left", "right", "dpad", "p1", "p2", "power", "emerg",
           "ptt", "side1", "side2", "knob", "mute", "pre"}
# part id -> (action, value) when the design does not say otherwise (SPEC 9.2 arrows: kset -> ok ...)
_INFER = {"kstar": ("star", None), "khash": ("hash", None), "kok": ("ok", None), "kback": ("back", None),
          "kp1": ("p1", None), "kp2": ("p2", None), "kup": ("up", None), "kdown": ("down", None), "kmenu": ("menu", None),
          "kset": ("ok", None), "kband": ("back", None), "kpower": ("power", None), "dpad": ("dpad", None),
          "knob_ch": ("knob", "channel"), "knob_vol": ("knob", "volume"), "emerg": ("emerg", None), "ptt": ("ptt", None),
          "side1": ("side1", None), "side2": ("side2", None), "kleft": ("left", None), "kright": ("right", None),
          "kmute": ("mute", None), "kpre": ("pre", None)}
BUDGETS = {"full": 24000, "body": 20000, "part": 1200}


def infer_action(pid):
    """(action, value) for a SPEC part id: k0..k9 -> ('digit', '0'..'9'), knob_ch -> ('knob', 'channel') ..."""
    if len(pid) == 2 and pid[0] == "k" and pid[1].isdigit():
        return "digit", pid[1]
    return _INFER.get(pid, (None, None))


@dataclass
class RadioSpec:
    key: str
    fn: object
    parts: list
    skin: str
    title: str = ""
    code: str = ""
    screen_px: tuple = (512, 384)
    atlas: int = 1024
    alpha_atlas: int = 256
    glow_atlas: int = 64
    part_atlas: int = 256
    lod: float = 40.0
    lod_high: float = 6.0
    body_lod: float = 20.0
    part_lod: float = 20.0
    hd: float = 8.0
    med_drop: float = 0.0025
    export: bool = True
    module: str = ""
    doc: dict = field(default_factory=dict)
    budgets: dict = field(default_factory=lambda: dict(BUDGETS))
    maps: dict = field(default_factory=dict)
    layers: dict = field(default_factory=dict)
    part_boost: float = 2.5

    @property
    def full(self):
        return f"nzr_{self.key}"

    @property
    def body(self):
        return f"nzr_{self.key}_body"

    def part_model(self, pid):
        return f"nzr_{self.key}_{pid}"


RADIOS: dict[str, RadioSpec] = {}


def radio(key, parts=None, skin=None, title="", code=None, screen_px=None, atlas=1024, alpha_atlas=256, glow_atlas=64,
          part_atlas=256, lod=40.0, lod_high=6.0, body_lod=20.0, part_lod=20.0, hd=8.0, med_drop=0.0025, export=True,
          doc=None, budgets=None, maps=None, layers=None, part_boost=2.5):
    """Register a radio design: nzr_<key> + nzr_<key>_body + nzr_<key>_<pid> for every part id.

    parts      ordered part ids (default: SPEC 9.2's list for handheld / fieldpro / military); the order is
               the order of `keys` in props_layout.lua
    skin       DUI skin (default from the key); code = model code printed on the idle screen
    screen_px  screen texture size (default: the skin's, handheld 512x384, fieldpro 512x256, military 512x384)
    atlas      full + body atlas (1024), part_atlas for each part model (256)
    lod / lod_high   archetype lodDist of the complete model / high -> medium switch distance; body_lod and
               part_lod are the archetype lodDist of the body and parts (only seen while raised)
    med_drop   charts smaller than this are left out of the complete model's medium LOD
    export     False: built and rendered, never streamed nor written to the layout (examples)
    layers     extra normal_spec atlases of the complete + body models, e.g. {"face": 1024} with a material
               Mat(layer="face") on the printed front plate: more texels for fine prints (part models fold
               every custom layer into their own small atlas)
    part_boost texel density multiplier of the pressable parts inside the complete model (legends on the
               key caps stay legible on the one atlas; the part models have their own atlas anyway)
    budgets    triangle budgets {"full": 24000, "body": 20000, "part": 1200} (warnings)"""
    def deco(fn):
        if key in RADIOS:
            raise ValueError(f"radio {key} registered twice")
        pl = list(parts if parts is not None else RADIO_PARTS.get(key, []))
        if not pl:
            raise ValueError(f"radio {key}: give parts=[...] (only handheld / fieldpro / military have a SPEC list)")
        if len(set(pl)) != len(pl):
            raise ValueError(f"radio {key}: duplicate part ids")
        sk = skin or RADIO_SKINS.get(key, "px740")
        spx = tuple(screen_px or SKINS.get(sk, SKINS["px740"])["px"])
        rs = RadioSpec(key=key, fn=fn, parts=pl, skin=sk, title=title or key, code=code or SKINS.get(sk, {}).get("code", ""),
                       screen_px=spx, atlas=atlas, alpha_atlas=alpha_atlas, glow_atlas=glow_atlas, part_atlas=part_atlas,
                       lod=lod, lod_high=lod_high, body_lod=body_lod, part_lod=part_lod, hd=hd, med_drop=med_drop,
                       export=export, module=getattr(fn, "__module__", ""), doc=dict(doc or {}),
                       budgets={**BUDGETS, **(budgets or {})}, maps=dict(maps or {}), layers=dict(layers or {}),
                       part_boost=float(part_boost))
        RADIOS[key] = rs
        group = f"radio:{key}"
        base_doc = {"origin": "grip point: body cross-section centre at 40 % of the body height from its bottom",
                    "axes": "+Y = front face (screen / keys), +Z up (antenna), +X = viewer's left"}
        try:
            register(rs.full, _variant(key, "full"), module=rs.module, atlas=atlas, alpha_atlas=alpha_atlas,
                     glow_atlas=glow_atlas, lod=lod, hd=hd, lod_high=lod_high, med_drop=med_drop, export=export,
                     budget=rs.budgets["full"], group=group, maps=rs.maps, layers=rs.layers,
                     doc={"title": f"{rs.title} - complete radio", **base_doc,
                          "attach": "held: PH_R_Hand (28422) with Config.Radios.Models[m].grip",
                          "screen": "nzr_scr (idle image), quad = layout screen.center / size", **rs.doc})
            register(rs.body, _variant(key, "body"), module=rs.module, atlas=atlas, alpha_atlas=alpha_atlas,
                     glow_atlas=glow_atlas, lod=body_lod, hd=hd, export=export, budget=rs.budgets["body"], group=group,
                     maps={k: v for k, v in rs.maps.items()}, layers=rs.layers,
                     doc={"title": f"{rs.title} - body without pressable parts (raised view)", **base_doc,
                          "attach": "replaces nzr_<m> in the local player's hand while raised; parts attach to it",
                          "screen": "nzr_scr (placeholder, replaced by the DUI: AddReplaceTexture(body, 'nzr_scr', ...))"})
            for pid in pl:
                register(rs.part_model(pid), _variant(key, "part", pid), module=rs.module, atlas=part_atlas,
                         alpha_atlas=min(alpha_atlas, 128), glow_atlas=min(glow_atlas, 32), lod=part_lod, hd=hd,
                         export=export, budget=rs.budgets["part"], group=group,
                         preview={"views": ["front", "face", "top"]},
                         doc={"title": f"{rs.title} - part {pid}",
                              "origin": "the part anchor (layout keys[].pos): clickable face centre / knob axis centre",
                              "axes": "same orientation as the body",
                              "attach": "AttachEntityToEntity(part, body, 0, pos, 0, 0, 0, ...)"})
        except Exception:
            for n in [rs.full, rs.body] + [rs.part_model(p) for p in pl]:
                REGISTRY.pop(n, None)
            RADIOS.pop(key, None)
            raise
        return fn
    return deco


# ---------------------------------------------------------------------------------------------
# design builder
# ---------------------------------------------------------------------------------------------
class RadioBuilder(Builder):
    """The Builder a radio design function receives. Adds part metadata, the screen anchor and
    model-level anchors on top of the nzprops Builder (mat / add / hi_only / decal / col_box ...)."""

    def __init__(self, spec, rs: RadioSpec):
        super().__init__(spec)
        self.radio = rs
        self.key = rs.key
        self.skin = rs.skin
        self.screen_anchor = None

    def part(self, pid, origin=None, press=None, depth=None, u=None, v=None, shape=None, action=None, value=None,
             axis=None, detents=None, tilt=None, **extra):
        """Context for a pressable part (see the module doc). Metadata may be given in several calls."""
        if pid not in self.radio.parts:
            raise ValueError(f"{self.key}: part '{pid}' is not in this radio's part list {self.radio.parts}")
        meta = {k: val for k, val in (("origin", origin), ("press", press), ("depth", depth), ("u", u), ("v", v),
                                      ("shape", shape), ("action", action), ("value", value), ("axis", axis),
                                      ("detents", detents), ("tilt", tilt)) if val is not None}
        meta.update(extra)
        return Builder.part(self, pid, **meta)

    def part_meta(self, pid, **meta):
        """Add / change metadata of a part outside its block."""
        if pid not in self.radio.parts:
            raise ValueError(f"{self.key}: unknown part '{pid}'")
        self.parts.setdefault(pid, {}).update({k: val for k, val in meta.items() if val is not None})

    def screen(self, geo: Geo, texname="nzr_scr", image=None, mult=1.0, size=None):
        """The radio screen: a quad(..., fixed_uv=True) (top-left of the texture at (-right, +up)). The
        kit stores its centre / size / pixels as the layout's screen anchor; the complete model gets the
        idle image of the skin (or `image`), the body a dark placeholder."""
        if texname != "nzr_scr":
            raise ValueError("radio screens use the texture name 'nzr_scr' (SPEC 9.1)")
        size = tuple(size or self.radio.screen_px)
        if image is None:
            image = idle_screen(self.skin, size, self.radio.code)
        c = geo.charts[0]
        P = c.pos
        if len(geo.charts) != 1 or len(P) != 4:
            raise ValueError("radio screen must be one quad(..., fixed_uv=True)")
        fu = c.fixed_uv
        tl = P[int(np.argmin(fu[:, 0] + fu[:, 1]))]
        tr = P[int(np.argmin(-fu[:, 0] + fu[:, 1]))]
        bl = P[int(np.argmin(fu[:, 0] - fu[:, 1]))]
        right, down = tr - tl, bl - tl
        self.screen_anchor = {"center": (P.mean(axis=0)).tolist(), "size": [float(np.linalg.norm(right)), float(np.linalg.norm(down))],
                              "w": int(size[0]), "h": int(size[1]), "right": normalize(right).tolist(),
                              "up": (-normalize(down)).tolist(), "normal": c.nrm[0].tolist()}
        return Builder.screen(self, geo, texname, image, mult, size)


# ---------------------------------------------------------------------------------------------
# design evaluation (memoised per process)
# ---------------------------------------------------------------------------------------------
_DESIGNS: dict = {}


class Design:
    def __init__(self, rs: RadioSpec, b: RadioBuilder):
        self.rs = rs
        self.b = b
        self.parts = {}          # pid -> normalised metadata
        self.part_bbox = {}      # pid -> (min, max) in body space


def get_design(key) -> Design:
    d = _DESIGNS.get(key)
    if d is None:
        rs = RADIOS[key]
        b = RadioBuilder(REGISTRY[rs.full], rs)
        rs.fn(b)
        d = Design(rs, b)
        _validate(d)
        _DESIGNS[key] = d
    return d


def _v3(x, what):
    a = np.asarray(x, np.float64).reshape(-1)
    if a.shape != (3,) or not np.all(np.isfinite(a)):
        raise ValueError(f"{what} must be a 3-vector, got {x!r}")
    return a


def _validate(d: Design):
    rs, b = d.rs, d.b
    errs = []
    used = {c.part for c in b.geo.charts if c.part is not None}
    missing = [p for p in rs.parts if p not in used]
    extra = sorted(used - set(rs.parts))
    if missing:
        errs.append(f"parts without geometry: {', '.join(missing)}")
    if extra:
        errs.append(f"geometry tagged with unknown parts: {', '.join(extra)}")
    for pid in rs.parts:
        if pid in missing:
            continue
        m = dict(b.parts.get(pid, {}))
        try:
            act, val = infer_action(pid)
            m.setdefault("action", act)
            if m.get("value") is None and val is not None and m.get("action") == act:
                m["value"] = val
            if m.get("action") not in ACTIONS:
                raise ValueError(f"action {m.get('action')!r} is not in the firmware vocabulary")
            origin = _v3(m.get("origin"), "origin")
            press = _v3(m.get("press"), "press")
            if np.linalg.norm(press) < 1e-9:
                raise ValueError("press must not be zero")
            press = press / np.linalg.norm(press)
            depth = float(m.get("depth") or 0.0)
            if not 0.0002 <= depth <= 0.005:
                raise ValueError(f"depth {depth} m is outside 0.2 - 5 mm")
            u, v = _v3(m.get("u"), "u"), _v3(m.get("v"), "v")
            if np.linalg.norm(u) < 1e-5 or np.linalg.norm(v) < 1e-5:
                raise ValueError("u / v half extents must be > 0.01 mm")
            shape = m.get("shape") or "rect"
            if shape not in ("rect", "round"):
                raise ValueError(f"shape {shape!r} must be 'rect' or 'round'")
            out = {"id": pid, "model": rs.part_model(pid), "pos": origin, "press": press, "depth": depth, "u": u, "v": v,
                   "shape": shape, "action": m["action"], "value": None if m.get("value") is None else str(m["value"])}
            if m["action"] == "knob":
                if out["value"] not in ("channel", "volume"):
                    raise ValueError("knob value must be 'channel' or 'volume'")
                ax = _v3(m.get("axis"), "axis")
                out["axis"] = ax / np.linalg.norm(ax)
                det = int(m.get("detents") or 0)
                if det < 2:
                    raise ValueError("knobs need detents >= 2")
                out["detents"] = det
            if m["action"] == "dpad":
                tilt = float(m.get("tilt") or 0.0)
                if not 0.5 <= tilt <= 20:
                    raise ValueError("d-pad tilt must be 0.5 - 20 degrees")
                out["tilt"] = tilt
            if m["action"] == "digit" and (out["value"] is None or out["value"] not in "0123456789" or len(out["value"]) != 1):
                raise ValueError("digit keys need value '0'..'9'")
            if abs(float(np.dot(normalize(u), press))) > 0.35 or abs(float(np.dot(normalize(v), press))) > 0.35:
                if m["action"] != "knob":
                    b.warn(f"{pid}: u / v are not perpendicular to the press axis")
            d.parts[pid] = out
            pts = np.concatenate([c.pos for c in b.geo.charts if c.part == pid])
            d.part_bbox[pid] = (pts.min(axis=0), pts.max(axis=0))
            lo, hi = d.part_bbox[pid]
            slack = 0.0015
            if np.any(origin < lo - slack) or np.any(origin > hi + slack):
                b.warn(f"{pid}: origin {np.round(origin, 4).tolist()} lies outside its geometry")
        except ValueError as e:
            errs.append(f"{pid}: {e}")
    if b.screen_anchor is None:
        errs.append("no screen: call screen_window(...) or r.screen(quad(..., fixed_uv=True))")
    for c in b.geo.charts:
        if c.mat.startswith("screen:") and c.part is not None:
            errs.append("the screen must belong to the body, not to a part")
            break
    a = b.anchors
    try:
        _v3(a.get("focus"), "anchor focus")
        cd = float(a.get("camDist") or 0)
        if not 0.1 <= cd <= 1.5:
            raise ValueError(f"anchor camDist {cd} must be 0.1 - 1.5 m")
        leds = a.get("leds") or {}
        _v3(leds.get("tx"), "anchor leds.tx")
        _v3(leds.get("rx"), "anchor leds.rx")
    except (ValueError, TypeError) as e:
        errs.append(f"{e} - set r.anchor(focus=(x, y, z), camDist=0.34, leds={{'tx': (...), 'rx': (...)}}, grip='...')")
    if errs:
        raise ValueError(f"radio '{rs.key}' design errors:\n  - " + "\n  - ".join(errs))


# ---------------------------------------------------------------------------------------------
# variants
# ---------------------------------------------------------------------------------------------
def _tris(charts, shift=None):
    if not charts:
        return np.zeros((0, 3, 3))
    t = np.concatenate([c.pos[c.tri] for c in charts])
    return t - shift if shift is not None else t


def _auto_collision(d: Design, b: Builder):
    """Housing box over everything that is not antenna + one cylinder around the antenna charts."""
    ch = d.b.geo.charts
    ant = [c for c in ch if c.tag.startswith("antenna")]
    rest = [c for c in ch if not c.tag.startswith("antenna")]
    pts = np.concatenate([c.pos for c in rest])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    b.col_box(lo, hi, "PLASTIC_HIGH_DENSITY")
    if ant:
        ap = np.concatenate([c.pos for c in ant])
        alo, ahi = ap.min(axis=0), ap.max(axis=0)
        ctr = (alo + ahi) / 2
        r = float(max(ahi[0] - alo[0], ahi[1] - alo[1]) / 2)
        b.col_cyl(ctr, max(r, 0.003), float(ahi[2] - alo[2]), "z", "RUBBER")


def _review(d: Design):
    """Preview views + close-up cameras for the complete / body / assembled renders."""
    rs, b = d.rs, d.b
    ch = [c for c in b.geo.charts if not c.tag.startswith("antenna")]
    pts = np.concatenate([c.pos for c in ch])
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    ctr = (lo + hi) / 2
    tan15 = math.tan(math.radians(15))
    cams = []

    def cam(name, target, direction, extent, fov=30.0, fill=0.78):
        dist = (extent / 2) / (math.tan(math.radians(fov / 2)) * fill)
        dirn = normalize(vec(direction))
        cams.append({"name": name, "pos": (vec(target) + dirn * dist).tolist(), "target": list(map(float, target)), "fov": fov})

    keys = [p for p in d.parts.values() if p["action"] in ("digit", "star", "hash")]
    if keys:
        kp = np.concatenate([np.stack(d.part_bbox[p["id"]]) for p in keys])
        klo, khi = kp.min(axis=0), kp.max(axis=0)
        kc = (klo + khi) / 2
        cam("keypad", kc, (0.12, 1.0, 0.32), max(khi[0] - klo[0], khi[2] - klo[2]) * 1.25)
    top_parts = [p for p in d.parts.values() if d.part_bbox[p["id"]][1][2] > ctr[2] + (hi[2] - lo[2]) * 0.3]
    tz = hi[2]
    if top_parts:
        tp = np.concatenate([np.stack(d.part_bbox[p["id"]]) for p in top_parts])
        tz = float(tp[:, 2].max())
    deck = vec(ctr[0], ctr[1], tz - 0.006)
    cam("topdeck", deck, (0.25, 0.85, 0.95), max(hi[0] - lo[0], hi[1] - lo[1]) * 1.35)
    sa = b.screen_anchor
    cam("screen", sa["center"], vec(sa["normal"]) + vec(0, 0, 0.25), max(sa["size"]) * 1.7)
    if "ptt" in d.parts:
        p = d.parts["ptt"]
        out = -p["press"]
        cam("ptt", p["pos"], out + vec(0, 0.55, 0.25), max(np.linalg.norm(p["u"]), np.linalg.norm(p["v"])) * 2 * 2.4)
    _ = tan15
    return {"views": ["face", "front", "left", "right", "back", "top"], "cams": cams}


def _variant(key, kind, pid=None):
    def fill(b: Builder):
        d = get_design(key)
        rs, src = d.rs, d.b
        b.mats = dict(src.mats)
        if kind == "part":
            b.mats = {k: (dc_replace(m, layer="main") if m.layer not in ("main", "alpha", "glow") else m) for k, m in src.mats.items()}
        b.notes = {"radio": key}
        for w in src.warnings:
            if w not in b.warnings:
                b.warnings.append(w)
        if kind == "part":
            origin = d.parts[pid]["pos"]
            mine = [c for c in src.geo.charts if c.part == pid and c.lod != "m"]
            others = [c for c in src.geo.charts if c.part != pid and c.lod != "m"]
            for c in mine:
                cc = c.copy()
                cc.pos = cc.pos - origin
                cc.lod = "hm"
                b.geo.charts.append(cc)
            for dc in src.decals:
                if dc.part == pid or dc.part == "*":
                    b.decals.append(Decal(dc.canvas, tuple(np.asarray(dc.center) - origin), dc.normal, dc.up, dc.depth, dc.mats,
                                          dc.min_dot, dc.part))
            b.chart_decals = [cd for cd in src.chart_decals if cd.part in (pid, "*")]
            b.occluders.append(_tris(others, origin))
            b.col_box((-0.001, -0.001, -0.001), (0.001, 0.001, 0.001), "PLASTIC")
            lo, hi = d.part_bbox[pid]
            meta = {k: (v.tolist() if isinstance(v, np.ndarray) else v) for k, v in d.parts[pid].items()}
            b.anchor(kind="radio_part", radio=key, part=pid, origin=origin, bbox_body=[lo, hi], bbox_local=[lo - origin, hi - origin],
                     meta=meta)
            b.preview = {}
            return
        keep_parts = kind == "full"
        for c in src.geo.charts:
            if c.part is not None and not keep_parts:
                continue
            cc = c.copy()
            if kind == "body":
                if cc.lod == "m":
                    continue
                cc.lod = "hm"
            elif cc.part is not None:
                cc.density *= rs.part_boost
            b.geo.charts.append(cc)
        if keep_parts:
            b.decals = list(src.decals)
            b.chart_decals = list(src.chart_decals)
        else:
            b.decals = [x for x in src.decals if x.part in ("", "*")]
            b.chart_decals = [x for x in src.chart_decals if x.part in ("", "*")]
            b.occluders.append(_tris([c for c in src.geo.charts if c.part is not None and c.lod != "m"]))
        for tex, (img, mult, size) in src.screens.items():
            b.screens[tex] = (img if kind == "full" else placeholder_screen(size), mult, size)
        if src.shapes:
            b.shapes = list(src.shapes)
        else:
            _auto_collision(d, b)
        review = _review(d)
        b.preview = {"views": review["views"], "cams": review["cams"]}
        if kind == "full":
            keys = []
            for p in rs.parts:
                m = d.parts[p]
                e = {k: (v.tolist() if isinstance(v, np.ndarray) else v) for k, v in m.items()}
                lo, hi = d.part_bbox[p]
                e["bbox"] = [lo.tolist(), hi.tolist()]
                e["tris"] = int(sum(len(c.tri) for c in src.geo.charts if c.part == p and c.lod != "m"))
                keys.append(e)
            sa = dict(src.screen_anchor)
            sa.update({"tex": "nzr_scr", "txd": rs.body})
            a = src.anchors
            b.anchor(kind="radio_full", radio=key, skin=rs.skin, code=rs.code, full=rs.full, body=rs.body, screen=sa,
                     focus=a["focus"], camDist=float(a["camDist"]), leds=a["leds"], grip=a.get("grip", ""), keys=keys,
                     body_tris=int(sum(len(c.tri) for c in src.geo.charts if c.part is None and c.lod != "m")),
                     export=rs.export, **{k: v for k, v in a.items() if k not in ("focus", "camDist", "leds", "grip")})
            b.preview["assembly"] = {"name": f"nzr_{key}_assembled", "base": rs.body, "compare": rs.full,
                                     "parts": [{"name": rs.part_model(p), "pos": d.parts[p]["pos"].tolist()} for p in rs.parts]}
        else:
            b.anchor(kind="radio_body", radio=key, full=rs.full)
    fill.__name__ = f"{key}_{kind}{'_' + pid if pid else ''}"
    return fill


def designs_loaded():
    return dict(_DESIGNS)


__all__ = ["ACTIONS", "BUDGETS", "RADIOS", "RADIO_PARTS", "RADIO_SKINS", "RadioBuilder", "RadioSpec", "get_design",
           "infer_action", "radio"]
