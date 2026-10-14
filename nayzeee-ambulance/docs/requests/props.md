# Requests from the props module

The props module owns `tools/props/**` and `stream/**` only. Everything below needs a change in a
file owned by someone else. Offsets / screens are documented in `docs/modules/props.md`.

## 1. lead — `fxmanifest.lua` (already satisfied, keep it)

All 43 models are plain drawables with embedded textures + collision, plus ONE archetype file. The
manifest already has what the stream folder needs:

```lua
files {
    -- ...
    'stream/*.ytyp',
}
data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'
```

Equivalent explicit form if you prefer naming the file:
`data_file 'DLC_ITYP_REQUEST' 'stream/nz_amb_props.ytyp'`. No `.ytd`, `.ybn`, `.ymap` or
`this_is_a_map` entries are needed. Do not rename `stream/nz_amb_props.ytyp` - the build writes
exactly that name and deletes stale `nz_amb_*.ydr` itself.

## 2. lead — `config/props.lua`

### 2a. new model (requested by the angio module)

```lua
    injector_plunger = 'nz_amb_injector_plunger', -- moving syringe plunger + ram of the contrast injector
```

(under "hospital equipment", after `injector`). The model is built and streamed; the angio module
already reads `Config.Props.injector_plunger` (`Config.Angio.suite.plunger`). The injector itself no
longer contains a plunger, so the plunger must always be spawned with it (see section 4).

### 2b. `Config.PropScreens` - the other DUI-ready screens

Every screen texture is `nz_amb_screen` in the model's own dictionary. Please add:

```lua
    defib         = { txd = 'nz_amb_defib',         tex = 'nz_amb_screen' },
    pager         = { txd = 'nz_amb_pager',         tex = 'nz_amb_screen' },
    lightbox      = { txd = 'nz_amb_lightbox',      tex = 'nz_amb_screen' },   -- show the film being read
    blood_mixer   = { txd = 'nz_amb_blood_mixer',   tex = 'nz_amb_screen' },   -- live mL counter
    bay_shell     = { txd = 'nz_amb_bay_shell',     tex = 'nz_amb_screen' },   -- treatment bay wall monitor
```

### 2c. optional native fallbacks for the new hospital models

```lua
    xray_table     = 'v_med_emptybed',
    donation_chair = 'v_med_emptybed',
    us_cart        = 'prop_laptop_01a',
    angio_monitor  = 'prop_tv_flat_01',
    lightbox       = 'prop_tv_flat_01',
    surgery_tray   = 'v_med_cor_emblmtable',
    injector       = 'v_med_cor_emblmtable',
```

## 3. transport — `config/modules/transport.lua` (`Config.Transport.Bay`)

The defaults were written before the shell existed and put the cot on the bench side. The shell's
layout (prop space, origin = floor centre, +Y = cab): patient side -X, bench + counter +X,
supply cabinets on both long walls from z 1.34. Suggested defaults:

```lua
        stretcher = vec4(-0.42, 0.10, 0.0, 0.0),      -- nz_amb_stretcher origin, head end towards the cab
        medics = {                                     -- one spot per medic, in order
            vec4(0.15, 0.35, 0.0, 90.0),               -- beside the patient's chest, facing the cot
            vec4(-0.42, 1.42, 0.0, 180.0),             -- head end (airway), facing the patient
            vec4(0.10, -0.85, 0.0, 60.0),              -- at the legs
            vec4(0.30, -1.62, 0.0, 0.0),               -- just inside the rear doors
        },
        shelves   = vec3(0.85, -0.45, 1.65),           -- 'Supplies' target: right-wall cabinets over the bench
        lights = {
            { pos = vec3(0.0, -1.0, 1.95), color = { 245, 248, 255 }, range = 4.5, intensity = 3.5 },
            { pos = vec3(0.0, 0.95, 1.95), color = { 245, 248, 255 }, range = 4.5, intensity = 3.5 },
            { pos = vec3(-0.42, 0.10, 1.75), color = { 235, 245, 255 }, range = 2.2, intensity = 1.5 },  -- over the cot
        },
```

Other useful points (all in `docs/modules/props.md` §5): IV hooks `(-0.18, 0.95, 1.86)` /
`(-0.18, -0.30, 1.86)` (bag origin = its hanging slot), patient monitor shelf top `(-1.02, 0.30, 1.10)`
(`nz_amb_monitor` rot `(0, 0, -90)`), bulkhead wall monitor screen `(-0.20, 2.1045, 1.68)` facing -Y
(DUI target for the F4 "big patient monitor"), exit marker `(0.0, -1.90, 0.0)`, bench seats
`(0.93, -1.317 / -0.450 / 0.417, 0.50)` heading +90, attendant seat `(-0.42, 1.86, 0.48)` heading
+180, and the 24 labelled cabinet slots with their categories (table in §5) if you want one target per
category. While inside, call `SetRainLevel(0.0)` locally (the shell is a prop, rain particles are not
occluded) and `SetRainLevel(-1.0)` when leaving.

## 4. angio — injector plunger delivered

`nz_amb_injector_plunger` exists: origin = the plunger face, ram along +X. Attach it to the injector
entity at `(0.03, 0.05, 1.04)` rot `(0, 0, 0)` with collision off and slide it 0 .. 0.20 m along -X -
exactly your `Config.Angio.suite.plunger`. Please spawn it **every time** the injector is spawned
(also when no run is in progress), because the injector model no longer contains a static plunger.

## 5. blood / checkin / xray — placement facts (no change required, FYI)

* blood: bag on `nz_amb_blood_mixer` → pos `(-0.15, 0.0, 0.326)` lying label-up along +X;
  donation chair donor at `(0.0, -0.08, 0.53)` facing +Y, donor arm on the +X armrest, mixer on the
  floor at `(0.62, 0.15, 0)`, IV stand at `(-0.55, 0, 0)` (chair space).
* checkin: `nz_amb_tv_board` origin = the BACK centre of the screen (place the point on the wall
  surface, heading = into the room); embedded `nz_amb_screen` is 1024 x 576.
* xray: `nz_amb_xray_table` patient surface z 0.825, tube focal spot `(0, 0.35, 1.66)`; the lightbox
  panel `(0, 0.1465, 1.47)` 0.60 x 0.75 is DUI-ready (`Config.PropScreens.lightbox`, 2b).
