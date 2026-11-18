if not NAYZEEE_LOCK_OK then return end

--[[
    Pet hooks (client). Edit freely - this file is not escrowed.
    Link your own pet resource here: swap models, dress the pet (collars / textures) or play your own idle.

      PetBridge.Model(def, name)            -> model name / hash to spawn (nil = def.model)
      PetBridge.Idle(ped, def)              -> return true when you started your own idle anim (skip the default)
      PetBridge.Spawned(ped, def, name)     -> called once the lobby pet is placed, posed and frozen
      PetBridge.Removed(ped)                -> called right before the lobby pet is deleted
    def = Config.Pets.list entry ({ id, label, model, kind, ... }), name = the pet's name (may be nil)
]]

PetBridge = {}

function PetBridge.Model(def, name)
    return nil
end

function PetBridge.Idle(ped, def)
    return false
end

function PetBridge.Spawned(ped, def, name)
    -- e.g. SetPedComponentVariation(ped, 3, 0, 1, 0)   -- collar texture on a_c_husky
end

function PetBridge.Removed(ped)
end
