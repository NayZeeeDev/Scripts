# Custom key fob props (optional)

The car lock uses GTA's own key props by default (`lr_prop_carkey_fob` for fobs,
`p_car_keys_01` for plain keys), set in `config/carlock.lua` -> `Config.CarLock.fobProps`.
They are used for the key in your hand, keys dropped / thrown on the ground, catching and picking up.

To use the original nayzeee fob models instead (one per fob design: generic, sport, luxury,
classic, leather, compact, plus a metal car key):

1. Build the models with Blender 4.x or 5.x on your PC:
   `blender --background --python tools/fobprops/make_fobs.py -- --out install/fobprops`
   (or open the script in Blender's Scripting tab and press Run). This writes
   `nz_keyfobs.blend` and one `.glb` per prop.
2. Install the Sollumz add-on in Blender, open `nz_keyfobs.blend`, and for each collection
   (`nz_keyfob_generic` ... `nz_carkey`) convert the objects to a Sollumz drawable and export it
   as `nz_keyfob_<design>.ydr` / `nz_carkey.ydr`. Create one archetype file `nz_keyfobs.ytyp`
   containing the 7 archetypes (lodDist about 60).
3. Put the `.ydr` files and `nz_keyfobs.ytyp` in `nayzeee-garages/stream/` and add to
   `fxmanifest.lua`:
   ```lua
   data_file 'DLC_ITYP_REQUEST' 'stream/nz_keyfobs.ytyp'
   ```
4. In `config/carlock.lua`, point `Config.CarLock.fobProps.byDesign` at the new models
   (`generic = 'nz_keyfob_generic'`, ..., `key = 'nz_carkey'`) and tune
   `fobProps.hand.offset` / `rotation` in game so the fob sits right in the palm.
