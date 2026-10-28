# Custom props

Pulse works with base game models out of the box. The tripod is a studio TV camera (`prop_tv_cam_02`) and the
ring light is a studio light (`prop_studio_light_02`) with a glowing ring drawn on top. You can swap in your own
models, for example a real ring light or a bare camera tripod.

## 1. Add the files

Put the model files in this `stream/` folder:

- `.ydr` - the model (one per prop)
- `.ytyp` - the archetype file that lists your models
- `.ytd` - textures, if they are not embedded in the `.ydr`

```
nayzeee-streamer/
  stream/
    nz_props.ytyp
    nz_ringlight_01.ydr
    nz_tripod_01.ydr
    nz_props.ytd
```

FiveM streams everything in `stream/` by itself. No `files {}` entry is needed for models.

## 2. Load the .ytyp

Open `fxmanifest.lua` and remove the `--` in front of this line:

```lua
data_file 'DLC_ITYP_REQUEST' 'stream/*.ytyp'
```

Without it the models load, but placed props can fall through the floor or have no collision.

## 3. Point the config at your models

In `config.lua`, set the model names (the `.ydr` file name without the extension):

```lua
Config.Studio.Tripod.Model = 'nz_tripod_01'
Config.Studio.Tripod.ShowCamera = true          -- a bare tripod needs the mounted camera drawn on top
Config.Studio.Tripod.MountOffset = vec3(0.0, 0.0, 1.45)
Config.Studio.Tripod.LensOffset = vec3(0.0, 0.12, 1.50)

Config.Studio.RingLight.Model = 'nz_ringlight_01'
Config.Studio.RingLight.RingOffset = vec3(0.0, 0.0, 1.62)
Config.Studio.RingLight.RingRadius = 0.25
Config.Studio.RingLight.Glow = true             -- false if your model already has an emissive ring
```

Camera and mic props work the same way: change `model` (and `hold.model`) under `Config.Cameras` or
`Config.Microphones`.

## 4. Line it up

Offsets are in metres from the model's origin: x = right, y = forward, z = up.

1. Set `Config.Debug = true` and restart the resource.
2. Place the prop and check where the ring or lens sits.
3. Adjust the offset, `restart nayzeee-streamer`, and check again.

## Tips

- Keep models small. A ring light needs no more than a few thousand polygons.
- Model names must be unique on your server. A prefix like `nz_` avoids clashes.
- If a prop shows as an error model, the `.ytyp` is not loaded or the name in config does not match the `.ydr`.
