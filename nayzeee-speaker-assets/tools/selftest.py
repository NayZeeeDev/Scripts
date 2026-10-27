#!/usr/bin/env python3
"""Pipeline self-test:  python3 tools/selftest.py

1. mesh primitives: watertight, outward winding, analytic volumes, detail scaling
2. DDS: BC1/BC3 round trip on synthetic test images (PSNR > 30 dB), header parse
3. build twice into temp folders -> identical bytes (determinism) + validator OK
4. validator negative tests: tampered XML must be rejected
"""
from __future__ import annotations

import hashlib
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import numpy as np  # noqa: E402

from lib import dds, mesh as M, textures as tx, validate  # noqa: E402

FAILS = []


def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def _volume(m):
    P, F = m.positions, m.indices
    return float(np.einsum("ij,ij->i", P[F[:, 0]], np.cross(P[F[:, 1]], P[F[:, 2]])).sum() / 6)


def _open_edges(m):
    key = np.round(m.positions / 1e-7).astype(np.int64)
    _, pid = np.unique(key, axis=0, return_inverse=True)
    F = pid.reshape(-1)[m.indices]
    e = np.vstack([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    c = Counter(map(tuple, e))
    return sum(1 for (a, b), n in c.items() if c.get((b, a), 0) != n)


def test_mesh():
    print("mesh")
    cases = {
        "box": (M.box((0.2, 0.3, 0.4)), 0.024, 1e-9),
        "cylinder": (M.cylinder(0.1, 0.2, 64), math.pi * 0.01 * 0.2, 0.01),
        "tube": (M.tube(0.1, 0.06, 0.05, 64), math.pi * (0.01 - 0.0036) * 0.05, 0.01),
        "sphere": (M.uv_sphere(0.1, 64, 32), 4 / 3 * math.pi * 1e-3, 0.01),
        "torus": (M.torus(0.1, 0.02, 64, 24), 2 * math.pi ** 2 * 0.1 * 0.0004, 0.02),
        "rounded_box": (M.rounded_box((0.2, 0.2, 0.2), 0.1, 8), 4 / 3 * math.pi * 1e-3, 0.03),
        "rr_prism": (M.rounded_box((0.2, 0.3, 0.4), (0.03, 0.03, 0.0), 6), None, None),
        "bevel_box": (M.bevel_box((0.2, 0.3, 0.4), 0.02), None, None),
        "extrude_holes": (M.extrude(M.circle_2d(0.1, 64), 0.02, holes=[M.circle_2d(0.03, 32, (0.03, 0))],
                                    bevel=0.003, bevel_segments=2), None, None),
        "sweep": (M.sweep(M.circle_section(0.01, 16),
                          M.bezier_path((0, 0, 0), (0, 0, 0.1), (0.2, 0, 0.1), (0.2, 0, 0), 16)), None, None),
    }
    for name, (m, vol, tol) in cases.items():
        v = _volume(m)
        check(not m.check() and _open_edges(m) == 0 and v > 0, f"{name}: watertight, outward ({m.tri_count} tris)")
        if vol:
            check(abs(v - vol) / vol < tol, f"{name}: volume {v:.6g} ~ {vol:.6g}")
    with M.detail(0.35):
        lo = M.cylinder(0.1, 0.2, 64).tri_count
    check(lo < M.cylinder(0.1, 0.2, 64).tri_count / 2, "detail(0.35) reduces segment counts")
    p = M.plane(0.2, 0.1, facing="+y").compute_tangents()
    up = np.cross(p.normals[0], p.tangents[0, :3]) * p.tangents[0, 3]
    check(np.allclose(up, [0, 0, 1]), "tangent frame: cross(N,T)*w points to image-up")


def test_dds():
    print("dds")
    h = w = 128
    yy, xx = np.mgrid[0:h, 0:w] / 127.0
    rgb = np.clip(np.stack([0.5 + 0.5 * np.sin(xx * 6 + yy * 2), yy, 0.5 + 0.4 * np.cos(xx * yy * 12)], 2)
                  + tx.blur(tx.white(w, h, 3), 2.0)[:, :, None] * 0.05, 0, 1)
    rgba = np.concatenate([rgb, (0.5 + 0.5 * np.sin(xx * 9))[:, :, None]], 2)
    for fmt, img in (("DXT1", rgb), ("DXT5", rgba)):
        data, mips = dds.encode_dds(img, fmt)
        info, lv = dds.read_dds(data)
        ref = dds.to_u8(img)
        p = dds.psnr(lv[0][:, :, :3], ref[:, :, :3])
        check(info["format"] == fmt and info["mips"] == mips == 6, f"{fmt}: header parses, {mips} mips")
        check(p > 30, f"{fmt}: colour PSNR {p:.1f} dB > 30")
        if fmt == "DXT5":
            pa = dds.psnr(lv[0][:, :, 3], ref[:, :, 3])
            check(pa > 30, f"{fmt}: alpha PSNR {pa:.1f} dB > 30")
        check(len(data) == 128 + sum(s for _, _, s in dds.level_sizes(w, h, mips, fmt)), f"{fmt}: exact data size")


def _hash_tree(d):
    out = {}
    for base, _, files in os.walk(d):
        for f in files:
            p = os.path.join(base, f)
            out[os.path.relpath(p, d)] = hashlib.sha1(open(p, "rb").read()).hexdigest()
    return out


def test_build_and_validator():
    print("build + validator")
    tmp = tempfile.mkdtemp(prefix="nz_selftest_")
    try:
        a, b = os.path.join(tmp, "a"), os.path.join(tmp, "b")
        for d in (a, b):
            r = subprocess.run([sys.executable, os.path.join(ROOT, "build.py"), "--out", d], capture_output=True,
                               text=True)
            check(r.returncode == 0, f"build into {os.path.basename(d)} exits 0")
        ha, hb = _hash_tree(a), _hash_tree(b)
        check(ha == hb and len(ha) > 3, f"deterministic output ({len(ha)} files identical)")
        xml = os.path.join(a, "xml")
        names = sorted(os.listdir(xml))
        check("nayzeee_console_texture.ytd.xml" in names and "nayzeee_console.ytyp.xml" in names
              and not any(n.startswith("nayzeee_audio") for n in names),
              "own txd/ytyp (nayzeee_console_texture / nayzeee_console), nothing named like the speaker pack")
        ydr = sorted(f for f in os.listdir(xml) if f.endswith(".ydr.xml"))[0]
        src = open(os.path.join(xml, ydr), encoding="utf-8").read()
        tampered = {
            "unknown shader parameter": src.replace('name="bumpiness"', 'name="bumpinezz"', 1),
            "missing texture": re.sub(r'(type="Texture">\n\s*<Name>)[^<]+(</Name>)', r"\1nz_missing_n\2", src, count=1),
            "bad layout for shader": src.replace("       <Tangent />\n", "", 1),
            "NaN vertex": re.sub(r"(<Data>\n\s+)(\S+)", r"\1nan", src, count=1),
            "index out of range": re.sub(r"(<IndexBuffer>\n\s+<Data>\n\s+)(\d+)", r"\g<1>99999", src, count=1),
            "bad composite flag": src.replace("MAP_WEAPON,", "MAP_WEAPONS,", 1),
            "LOD order": src.replace('<LodDistHigh value="', '<LodDistHigh value="99999', 1),
            "unknown shader": src.replace("<Name>normal_spec</Name>", "<Name>normal_spek</Name>", 1),
        }
        for label, text in tampered.items():
            check(text != src, f"tamper applies: {label}")
            bad = os.path.join(tmp, "bad")
            shutil.rmtree(bad, ignore_errors=True)
            shutil.copytree(xml, bad)
            with open(os.path.join(bad, ydr), "w", encoding="utf-8") as f:
                f.write(text)
            rep = validate.validate_dir(bad)
            check(not rep.ok, f"validator rejects: {label}")
        # ytyp mismatch
        bad = os.path.join(tmp, "bad")
        shutil.rmtree(bad, ignore_errors=True)
        shutil.copytree(xml, bad)
        yt = [f for f in os.listdir(bad) if f.endswith(".ytyp.xml")][0]
        t = open(os.path.join(bad, yt), encoding="utf-8").read()
        open(os.path.join(bad, yt), "w", encoding="utf-8").write(re.sub(r'<bsRadius value="[^"]+"', '<bsRadius value="9"', t))
        check(not validate.validate_dir(bad).ok, "validator rejects: archetype bounds != drawable")
        # broken dds
        dd = [d for d in os.listdir(bad) if os.path.isdir(os.path.join(bad, d))][0]
        f0 = sorted(os.listdir(os.path.join(bad, dd)))[0]
        with open(os.path.join(bad, dd, f0), "r+b") as f:
            f.truncate(200)
        check(not validate.validate_dir(bad).ok, "validator rejects: truncated DDS")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_example_model(keep_dir=None):
    """Build models/_example_speaker.py (multi-material, decal, emissive, sweeps, 3D text) and validate it."""
    print("example model")
    import build
    import models
    from lib import cwxml, glb
    hi = models.build("_example_speaker", 1.0)
    med = models.build("_example_speaker", hi.lod.med_detail)
    check(not hi.problems() or hi.problems() == ["_example_speaker: name must be lowercase without spaces"],
          f"spec problems: {hi.problems()}")
    tmp = keep_dir or tempfile.mkdtemp(prefix="nz_example_")
    xml = os.path.join(tmp, "xml")
    os.makedirs(xml, exist_ok=True)
    os.makedirs(os.path.join(tmp, "glb"), exist_ok=True)
    build.write_texture_dictionary(build.textures_for([hi, med]), xml, os.path.join(ROOT, "cache", "dds"))
    cwxml.write_text(os.path.join(xml, "example_speaker.ydr.xml"),
                     cwxml.ydr_xml("example_speaker", {"High": hi.parts, "Medium": med.parts}, hi.collision, hi.lod))
    glb.write_glb(os.path.join(tmp, "glb", "example_speaker.glb"), "example_speaker", hi.parts)
    rep = validate.validate_dir(xml)
    for e in rep.errors:
        print("     ", e)
    d = rep.info["drawables"]["example_speaker"]
    check(rep.ok, f"example validates ({d['tris']['DrawableModelsHigh']} high / "
                  f"{d['tris']['DrawableModelsMedium']} medium tris, {len(rep.info['textures'])} textures)")
    if keep_dir is None:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    test_mesh()
    test_dds()
    test_build_and_validator()
    test_example_model(sys.argv[1] if len(sys.argv) > 1 else None)
    print(f"\n{'ALL OK' if not FAILS else str(len(FAILS)) + ' FAILURE(S)'}")
    sys.exit(1 if FAILS else 0)
