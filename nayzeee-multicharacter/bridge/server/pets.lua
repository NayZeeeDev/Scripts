if not NAYZEEE_LOCK_OK then return end

--[[
    Which companion pets a character may pick in the lobby (Config.Pets.access).

      'all'     every pet in Config.Pets.list
      'ace'     pets without `ace` are free, pets with `ace` need that permission on the player
      'bridge'  PetBridge.Owned below decides — link your own pet script there

    PetBridge.Allowed(src, charId) -> { 'husky', 'pug', ... }
]]

PetBridge = {}

--[[
    EDIT ME when Config.Pets.access = 'bridge'.
    Return the list of Config.Pets.list ids this character owns, e.g. from your pet shop table:

        local rows = MySQL.query.await('SELECT model FROM my_pets WHERE citizenid = ?', { charId }) or {}
        local ids = {}
        for _, r in ipairs(rows) do
            for _, p in ipairs(Config.Pets.list) do
                if p.model == r.model then ids[#ids + 1] = p.id end
            end
        end
        return ids

    Returning nil (the default) means "no pet script linked" and falls back to 'ace' rules,
    so nothing breaks before you wire it up.
]]
function PetBridge.Owned(src, charId)
    return nil
end

local function aceList(src)
    local out = {}
    for _, p in ipairs(Config.Pets.list) do
        if not p.ace or (src and src > 0 and IsPlayerAceAllowed(src, p.ace)) then out[#out + 1] = p.id end
    end
    return out
end

function PetBridge.Allowed(src, charId)
    local cfg = Config.Pets
    if not cfg.enabled then return {} end
    if cfg.access == 'all' then
        local out = {}
        for _, p in ipairs(cfg.list) do out[#out + 1] = p.id end
        return out
    elseif cfg.access == 'bridge' then
        local ok, ids = pcall(PetBridge.Owned, src, charId)
        if ok and type(ids) == 'table' then
            local out = {}
            for _, id in ipairs(ids) do if NZ.PetById(id) then out[#out + 1] = id end end
            return out
        end
        if not ok then NZ.Debug('PetBridge.Owned failed', ids) end
    end
    return aceList(src)
end

function PetBridge.Can(src, charId, petId)
    for _, id in ipairs(PetBridge.Allowed(src, charId)) do
        if id == petId then return true end
    end
    return false
end
