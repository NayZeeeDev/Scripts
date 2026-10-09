# illenium-appearance addon

Chains that nayzeee-chainsnatch converted from a clothing pack are **jewellery**: they're sold at the jewelry
store, so the clothing store won't put them on. Trying one shows *"This chain must be purchased at the jewelry
store."* It covers every way illenium sets clothing: the menu, saved outfits, outfit codes, job outfits and
loading a skin, because they all go through one function.

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

- every chain chainkit converted from a **clothing resource** (`Config.Convert.ScanResources`)
- plus every accessory of the collections in `Config.Appearance.BlockCollections`

Chains from the `chains/` folder aren't clothing on your server, so there is nothing to block for them.
Without illenium (or with another clothing script) `Config.Appearance.Enforce` takes a jewellery chain back off
within two seconds.
