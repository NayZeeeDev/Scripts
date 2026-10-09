# illenium-appearance addon

The chains **you list** in `Config.Appearance.Block` (nayzeee-chainsnatch/config.lua) are sold at the jewelry
store, so the clothing store won't put them on. Trying one shows *"This chain must be purchased at the jewelry
store."* Nothing else in your clothing packs is touched. It covers the clothing menu, saved outfits, outfit
codes and loading a skin, because they all go through one function.

## Install (3 steps)

1. Copy `game/nayzeee_chains.lua` into `illenium-appearance/game/`.
2. `illenium-appearance/fxmanifest.lua`, in `client_scripts`, add it right after `game/constants.lua`:

   ```lua
     "game/constants.lua",
     "game/nayzeee_chains.lua",
     "game/util.lua",
   ```

3. `illenium-appearance/game/util.lua`, in `setPedComponent`, add one line before `SetPedComponentVariation`:

   ```lua
   local function setPedComponent(ped, component)
       if component then
           if isPedFreemodeModel(ped) and (component.component_id == 0 or component.component_id == 2) then
               return
           end

           -- nayzeee-chainsnatch: jewellery chains are bought at the jewelry store, not worn as clothing
           if NZC_BlockComponent and NZC_BlockComponent(ped, component) then return end

           SetPedComponentVariation(ped, component.component_id, component.drawable, component.texture, 0)
       end
   end
   ```

`illenium-appearance.patch` is the same change as a diff. If nayzeee-chainsnatch isn't running, the addon does
nothing.

## Which chains are blocked

Only what's in `Config.Appearance.Block`:

```lua
Config.Appearance = {
    Enforce = true,
    Block = {
        'm|mp_m_mychains|3',                                     -- one chain (key from /chainlist or the studio)
        { collection = 'mp_m_mychains', drawables = { 0, 1, 4 } }, -- those numbers of a pack
        { collection = 'mp_f_mychains' },                          -- a whole pack
    },
}
```

illenium's job outfits set clothing directly (not through `setPedComponent`), and a skin can load a moment
before the chain list arrives on join: `Enforce` takes a blocked chain back off within two seconds in both cases,
and with any other clothing script.
