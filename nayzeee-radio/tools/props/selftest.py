#!/usr/bin/env python3
"""
Self-test of the props pipeline + radio kit (no .NET needed, ~1 minute):

    python3 tools/props/selftest.py                # build the example radio --quick --no-convert + checks
    python3 tools/props/selftest.py --no-preview   # skip the renders (no node / chromium)
    python3 tools/props/selftest.py --keep         # keep the temp build folder for a look

It builds props/_example_radio.py (nzr_example, _body, _k1, _k2, _knob_ch) into a private folder with
build.py --examples --only 'nzr_example*' --quick --no-convert --no-xml --layout <tmp> (the real
shared/props_layout.lua and tools/props/xml are never touched), then checks:
  * parts are excluded from the body (body tris + part tris == complete tris; no part geometry in the body)
  * every part model's origin is its anchor (part bbox + anchor == the part's bbox inside the radio)
  * the generated layout parses (luac5.4 -p) and loads in lua5.4 with every key's fields present
  * the memory budget check runs (estimate for every model + the RSC7 page-flag decoder)
  * the medium LOD exists for the complete model only, collisions are present, screens are named nzr_scr
  * (with previews) the assembled render matches the complete model (alignment) and icons render
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PASS, FAIL = [], []


def check(ok, what, detail=""):
    (PASS if ok else FAIL).append(what)
    print(f"  [{'ok' if ok else 'FAIL'}] {what}{(' - ' + detail) if detail else ''}", flush=True)
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--work", default="/tmp/nzr-work/props", help="shared tool cache (node modules)")
    args = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="nzr-selftest-")
    out = os.path.join(tmp, "out")
    lua = os.path.join(tmp, "props_layout.lua")
    print(f"[selftest] building the example radio into {tmp}")
    cmd = [sys.executable, os.path.join(HERE, "build.py"), "--examples", "--only", "nzr_example*", "--quick", "--no-convert",
           "--out", out, "--work", args.work, "--no-xml", "--layout", lua, "--layout-radios", "example,handheld"]
    if args.no_preview:
        cmd.append("--no-preview")
    t0 = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True)
    dt = time.time() - t0
    print("\n".join("    " + ln for ln in r.stdout.strip().splitlines()[-14:]))
    if not check(r.returncode == 0, f"build.py exit code 0 ({dt:.1f}s)", r.stderr.strip()[-600:]):
        finish(tmp, args.keep)
        return

    def man(n):
        with open(os.path.join(out, n, "manifest.json")) as f:
            return json.load(f)
    full, body = man("nzr_example"), man("nzr_example_body")
    parts = {p: man(f"nzr_example_{p}") for p in ("k1", "k2", "knob_ch")}
    keys = full["anchors"]["keys"]

    print("[selftest] parts / body split")
    check([k["id"] for k in keys] == ["k1", "k2", "knob_ch"], "layout keys in declared order", ", ".join(k["id"] for k in keys))
    s = body["tris"] + sum(k["tris"] for k in keys)
    check(s == full["tris"], "body tris + part tris == complete tris", f"{body['tris']} + {sum(k['tris'] for k in keys)} vs {full['tris']}")
    check(all(parts[p]["tris"] == k["tris"] for p, k in zip(parts, keys)), "each part model holds exactly its part's triangles")
    # no body vertex inside a key cap volume above the plate: sample the body glb positions
    import numpy as np
    body_pos = _glb_positions(os.path.join(out, "nzr_example_body", "nzr_example_body.glb"))
    inside = 0
    for k in keys:
        if k["action"] == "knob":
            continue                                    # the boss shaft legitimately runs up inside a knob
        # the central 80 % of the key footprint, from its face down to its base, must be empty on the body
        pos, u, v, pr = (np.array(k[x]) for x in ("pos", "u", "v", "press"))
        lo, hi = np.array(k["bbox"][0]), np.array(k["bbox"][1])
        height = float(np.abs((hi - lo) @ pr))
        rel = body_pos - pos
        a = np.abs(rel @ (u / np.linalg.norm(u))) < 0.8 * np.linalg.norm(u)
        b = np.abs(rel @ (v / np.linalg.norm(v))) < 0.8 * np.linalg.norm(v)
        dpt = rel @ pr
        c = (dpt > 0.0001) & (dpt < height - 0.0001)
        inside += int((a & b & c).sum())
    check(inside == 0, "no body geometry inside any key / button volume", f"{inside} vertices")

    print("[selftest] part origins = anchors")
    worst = 0.0
    for p, k in zip(parts, keys):
        a = parts[p]["anchors"]
        loc_lo = np.array(parts[p]["geoMin"])
        loc_hi = np.array(parts[p]["geoMax"])
        pos = np.array(k["pos"])
        worst = max(worst, float(np.abs(loc_lo + pos - np.array(k["bbox"][0])).max()), float(np.abs(loc_hi + pos - np.array(k["bbox"][1])).max()))
        check(np.allclose(a["origin"], k["pos"], atol=1e-6), f"{p}: part manifest origin == layout pos")
    check(worst < 2e-5, "part geometry + pos == part inside the complete model", f"worst {worst * 1000:.4f} mm")
    for k in keys:
        n = np.array(k["press"])
        check(abs(np.linalg.norm(n) - 1) < 1e-6 and 0.0002 <= k["depth"] <= 0.005, f"{k['id']}: press unit / depth {k['depth'] * 1000:.2f} mm")

    print("[selftest] layout Lua")
    luac = shutil.which("luac5.4") or shutil.which("luac")
    if luac:
        r2 = subprocess.run([luac, "-p", lua], capture_output=True, text=True)
        check(r2.returncode == 0, "luac5.4 -p props_layout.lua", r2.stderr.strip())
    else:
        check(False, "luac5.4 available")
    lua_exe = shutil.which("lua5.4") or shutil.which("lua")
    if lua_exe:
        probe = os.path.join(tmp, "probe.lua")
        with open(probe, "w") as f:
            f.write(
                "NAYZEEE_LOCK_OK = true\n"
                "function vec3(x, y, z) return { x = x, y = y, z = z } end\n"
                "function vec2(x, y) return { x = x, y = y } end\n"
                f"dofile({json.dumps(lua)})\n"
                "local e = PropsLayout.example\n"
                "assert(e and e.full == 'nzr_example' and e.body == 'nzr_example_body' and e.skin == 'px740')\n"
                "assert(e.screen.tex == 'nzr_scr' and e.screen.txd == 'nzr_example_body' and e.screen.w == 512)\n"
                "assert(e.focus.y and e.camDist > 0 and e.leds.tx.z and e.leds.rx.z)\n"
                "assert(#e.keys == 3)\n"
                "for _, k in ipairs(e.keys) do\n"
                "  assert(k.id and k.model and k.pos.x and k.press.y and k.depth and k.u.x and k.v.z and k.shape and k.action)\n"
                "end\n"
                "assert(e.keys[3].action == 'knob' and e.keys[3].value == 'channel' and e.keys[3].axis.z == 1 and e.keys[3].detents == 16)\n"
                "assert(PropsLayout.handheld and PropsLayout.handheld.keys and PropsLayout.jammers.heavy.model == 'nzr_jammer_heavy')\n"
                "print('lua ok')\n")
        r3 = subprocess.run([lua_exe, probe], capture_output=True, text=True)
        check(r3.returncode == 0 and "lua ok" in r3.stdout, "layout loads in lua5.4 with every key field", r3.stderr.strip()[-300:])

    print("[selftest] memory budget + LOD + collisions + screens")
    from nzprops.budget import PAGE_LIMIT, assign_pages
    import build
    allm = [full, body] + list(parts.values())
    check(all(m.get("mem_est") and 0 < m["mem_est"]["physical"] <= PAGE_LIMIT and 0 < m["mem_est"]["virtual"] <= PAGE_LIMIT for m in allm),
          "memory estimate present and under 16 MiB for every model", f"complete ~{full['mem_est']['physical'] / 1048576:.2f} MiB physical")
    over = build.budget_report({"x": {"mem_est": {"virtual": 20 << 20, "physical": 1}}}, ["x"])
    check(len(over) == 1, "budget check flags a 20 MiB drawable")
    tot, shift, counts = assign_pages([3 << 20, 1 << 20, 700000, 4096])
    check(tot >= (3 << 20) + (1 << 20) + 700000, "page packer allocates at least the data", f"{tot} bytes, pages {counts}")
    fake = os.path.join(tmp, "fake.ydr")
    with open(fake, "wb") as f:   # one 0x2000 << 4 page system, two 0x2000 << 3 pages graphics (base shift 4)
        f.write(struct.pack("<4sIII", b"RSC7", 165, (1 << 17) | 4, (2 << 11) | 4))
    pg = build.rsc_pages(fake)
    check(pg == (0x200 << 4 << 4, 2 * (0x200 << 4 << 5)), "RSC7 page-flag decoder", str(pg))
    check(full.get("tris_med") and full["tris_med"] < full["tris"] and not body.get("tris_med"), "medium LOD on the complete model only",
          f"{full['tris']} / {full.get('tris_med')}")
    check(all(m["collision"] for m in allm), "every model has collision")
    check(any(c["type"] == "cylinder" for c in full["collision"]), "complete radio: housing box + antenna cylinder")
    check(full["screens"] == ["nzr_scr"] and body["screens"] == ["nzr_scr"] and not parts["k1"]["screens"], "screen texture nzr_scr on full + body only")
    check(not full["export"], "example is not exported (never streamed)")
    ytyp = open(os.path.join(out, "nzr_props.ytyp.xml")).read()
    check("nzr_example" not in ytyp, "example not in nzr_props.ytyp.xml")
    xml = open(os.path.join(out, "nzr_example", "source", "nzr_example.ydr.xml")).read()
    check("<DrawableModelsMedium>" in xml and "<LodDistHigh value=\"6\" />" in xml, "drawable XML carries the medium model + LodDistHigh 6")

    if not args.no_preview:
        print("[selftest] renders")
        rd = os.path.join(out, "renders")
        need = [f"nzr_example_{v}.png" for v in ("face", "front", "left", "right", "back", "top", "keypad", "topdeck", "screen")]
        need += [f"nzr_example_assembled_{v}.png" for v in ("face", "keypad")] + ["nzr_example_k1_front.png"]
        missing = [n for n in need if not os.path.exists(os.path.join(rd, n))]
        check(not missing, "review renders written (views, close-ups, assembled, parts)", ", ".join(missing))
        al = json.load(open(os.path.join(rd, "nzr_example_assembled_alignment.json")))
        worst = max(v for k, v in al.items() if k != "screen")
        check(worst < 0.01, "assembled body + parts match the complete model", f"worst {worst * 100:.2f} % pixels differ")
        dest = os.path.join(tmp, "icons")
        r4 = subprocess.run([sys.executable, os.path.join(HERE, "icons.py"), "--out", out, "--work", args.work, "--dest", dest,
                             "--only", "none", "--map", "test_radio=nzr_example"], capture_output=True, text=True)
        ok = r4.returncode == 0 and os.path.exists(os.path.join(dest, "test_radio.png"))
        if ok:
            from PIL import Image
            im = Image.open(os.path.join(dest, "test_radio.png"))
            ok = im.size == (512, 512) and im.mode == "RGBA" and im.getpixel((0, 0))[3] == 0
        check(ok, "icon renders 512x512 with a transparent background", r4.stderr.strip()[-300:])
    finish(tmp, args.keep)


def _glb_positions(path):
    """All vertex positions of a .glb (GTA axes)."""
    import numpy as np
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + jlen])
    bin_off = 20 + jlen + 8
    out = []
    for mesh in js["meshes"]:
        for p in mesh["primitives"]:
            acc = js["accessors"][p["attributes"]["POSITION"]]
            bv = js["bufferViews"][acc["bufferView"]]
            a = np.frombuffer(data, np.float32, acc["count"] * 3, bin_off + bv.get("byteOffset", 0)).reshape(-1, 3)
            out.append(np.stack([a[:, 0], -a[:, 2], a[:, 1]], axis=1))
    return np.concatenate(out)


def finish(tmp, keep):
    print(f"\n[selftest] {len(PASS)} passed, {len(FAIL)} failed")
    if keep or FAIL:
        print(f"[selftest] build folder kept: {tmp}")
    else:
        shutil.rmtree(tmp, ignore_errors=True)
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
