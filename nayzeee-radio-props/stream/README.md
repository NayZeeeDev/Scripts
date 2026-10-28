# nayzeee-radio-props/stream

This folder holds the streamed models of NAYZEEE Radio: **80 `.ydr` drawables + `nzr_props.ytyp`**
(81 files). Textures are embedded in each `.ydr`, so there are no `.ytd` files.

The binaries are already here, converted and checked (each one loaded back, every drawable under
16 MiB). You only need the steps below after changing a prop. They are converted from the
CodeWalker XML that the prop pipeline writes, which is committed too:

| Where (in the `nayzeee-radio` resource) | What |
|---|---|
| `tools/props/xml/<name>.ydr.xml` | CodeWalker drawable XML of every streamed model (high + medium LOD, collision) |
| `tools/props/xml/<name>/` | its DDS textures (`<name>_d/_n/_s.dds`, `_ad/_an/_as`, `_g`, `nzr_scr.dds` ...). CodeWalker looks for this folder next to the XML |
| `tools/props/xml/nzr_props.ytyp.xml` | the one ytyp: an archetype for each of the 80 models |
| `tools/props/xml/<name>.json` | build manifest (bounds, triangles, memory estimate). Not converted |

Keep that folder layout as it is: every `.ydr.xml` needs its texture folder beside it.

## Route 1: a machine with the .NET 8 SDK and git (Linux, macOS, Windows WSL)

```bash
cd nayzeee-radio
tools/props/convert.sh             # converts the committed tools/props/xml as it is (no rebuild)
tools/props/convert.sh --rebuild   # rebuilds every prop from tools/props/props/*.py first, then converts
```

The script clones CodeWalker into the work folder (`/tmp/nzr-work/props`, never into the repository) and
builds `tools/props/cwtool` against it. It then converts every `.ydr.xml` and `nzr_props.ytyp.xml`, loads
each binary back to validate it, and refuses any drawable above 16 MiB of memory pages (FiveM's streaming
limit). Only after all of that does it copy the files into this folder; stale `nzr_*.ydr` files here are
removed.

Requirements: .NET 8 SDK (`dotnet`), git, python3 with `numpy`, `Pillow` and `fonttools`.

## Route 2: Windows with the CodeWalker GUI (no .NET SDK)

1. Start CodeWalker (release build from https://github.com/dexyfex/CodeWalker). When it asks for the game
   folder, pick **GTA V Legacy**, **not GTA V Enhanced**. FiveM streams legacy (gen8) resources;
   files written by the Enhanced setup are gen9 and FiveM cannot load them.
2. Tools → RPF Explorer, switch on **Edit mode**, and open (or create) an `.rpf` to import into.
3. **Import XML** → select every `nayzeee-radio/tools/props/xml/nzr_*.ydr.xml` and
   `nzr_props.ytyp.xml`. Import them from inside the `xml` folder so each one finds its texture folder.
4. Select all the imported `nzr_*.ydr` files and `nzr_props.ytyp` → right-click → **Extract Raw…** into
   `nayzeee-radio-props/stream/`.
5. Check the list below: 80 `.ydr` files plus `nzr_props.ytyp`, nothing missing and nothing extra.

The GUI route has no automatic memory check. The pipeline's estimate is in each
`tools/props/xml/<name>.json` (`mem_est`). The largest drawables are the complete radios and their
`_body` models, at about 11 MiB physical plus 1.6 MiB virtual, which is under the 16 MiB limit.

## Every file that must be in this folder

```
nzr_props.ytyp

nzr_handheld.ydr          nzr_handheld_body.ydr
nzr_handheld_k0.ydr       nzr_handheld_k1.ydr       nzr_handheld_k2.ydr       nzr_handheld_k3.ydr
nzr_handheld_k4.ydr       nzr_handheld_k5.ydr       nzr_handheld_k6.ydr       nzr_handheld_k7.ydr
nzr_handheld_k8.ydr       nzr_handheld_k9.ydr       nzr_handheld_kstar.ydr    nzr_handheld_khash.ydr
nzr_handheld_kok.ydr      nzr_handheld_kback.ydr    nzr_handheld_kp1.ydr      nzr_handheld_kp2.ydr
nzr_handheld_dpad.ydr     nzr_handheld_knob_ch.ydr  nzr_handheld_knob_vol.ydr nzr_handheld_emerg.ydr
nzr_handheld_ptt.ydr      nzr_handheld_side1.ydr    nzr_handheld_side2.ydr

nzr_fieldpro.ydr          nzr_fieldpro_body.ydr
nzr_fieldpro_k0.ydr       nzr_fieldpro_k1.ydr       nzr_fieldpro_k2.ydr       nzr_fieldpro_k3.ydr
nzr_fieldpro_k4.ydr       nzr_fieldpro_k5.ydr       nzr_fieldpro_k6.ydr       nzr_fieldpro_k7.ydr
nzr_fieldpro_k8.ydr       nzr_fieldpro_k9.ydr       nzr_fieldpro_kstar.ydr    nzr_fieldpro_khash.ydr
nzr_fieldpro_kup.ydr      nzr_fieldpro_kdown.ydr    nzr_fieldpro_kmenu.ydr    nzr_fieldpro_kset.ydr
nzr_fieldpro_kband.ydr    nzr_fieldpro_kpower.ydr   nzr_fieldpro_knob_ch.ydr  nzr_fieldpro_knob_vol.ydr
nzr_fieldpro_ptt.ydr      nzr_fieldpro_side1.ydr    nzr_fieldpro_emerg.ydr

nzr_military.ydr          nzr_military_body.ydr
nzr_military_k0.ydr       nzr_military_k1.ydr       nzr_military_k2.ydr       nzr_military_k3.ydr
nzr_military_k4.ydr       nzr_military_k5.ydr       nzr_military_k6.ydr       nzr_military_k7.ydr
nzr_military_k8.ydr       nzr_military_k9.ydr       nzr_military_kstar.ydr    nzr_military_khash.ydr
nzr_military_kok.ydr      nzr_military_kback.ydr    nzr_military_kup.ydr      nzr_military_dpad.ydr
nzr_military_knob_ch.ydr  nzr_military_knob_vol.ydr nzr_military_emerg.ydr    nzr_military_ptt.ydr
nzr_military_side1.ydr    nzr_military_side2.ydr

nzr_led_red.ydr           nzr_led_green.ydr         nzr_led_amber.ydr

nzr_jammer_pocket.ydr     nzr_jammer_case.ydr       nzr_jammer_heavy.ydr
```

Counts: handheld 25, field pro 25, military 24, LED inserts 3, jammers 3. With `nzr_props.ytyp`, that
is 81 files. `nzr_earpiece` is only used for the item picture and is never streamed.

Quick check from `nayzeee-radio-props/`: `ls stream/*.ydr | wc -l` prints `80`, and `stream/nzr_props.ytyp`
exists.

This README is documentation only. If your server warns about it, delete it from the server copy.
