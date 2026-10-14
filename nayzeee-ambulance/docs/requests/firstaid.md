# Requests from the firstaid module

## 1. Two prop models for worn devices (config/props.lua + props module)

`Config.Firstaid.Props` refers to two `Config.Props` keys that do not exist yet:

| Key | What | Attach (current defaults in `config/modules/firstaid.lua`) |
|---|---|---|
| `oxygen_mask` | Clear non-rebreather face mask with reservoir bag and green tubing | `SKEL_Head` 31086, pos (0.04, 0.12, 0.0), rot (0, 90, 180) |
| `foil_blanket` | Gold/silver rescue blanket draped over the torso (open at the neck) | `SKEL_Spine3` 24818, pos (0, 0, 0), rot (0, 90, 0) |

Until they exist the worn-prop renderer silently skips them (the device flags `devices.oxygen` /
`devices.foil` and all gameplay effects work without the models). Please add
`oxygen_mask = 'nz_amb_o2mask'` and `foil_blanket = 'nz_amb_foil'` to `Config.Props` when the props
module builds them, and update the attach offsets in `docs/modules/props.md` so they can be copied
into `Config.Firstaid.Props`.

## 2. Reserved state bag name

The module sets a replicated state bag `nzaFa` on player / NPC patient entities (server only):
`{ o2 = true|nil, foil = true|nil, tq = { [region] = { s = 'upper'|'lower', f = 0..1 } | false } }`.
Please list it in ARCHITECTURE §4.3 next to `nza` so no other module reuses the name.

## 3. ARCHITECTURE §5 note (optional)

`NZA.ExamRoutes` entries from this module pass `payload.injury` to the instant treatments
`fa_bandage`, `fa_ice`, `fa_burn` so the exam's chosen wound is the one treated. Other modules may
want the same convention (documented in `docs/modules/firstaid.md`).
