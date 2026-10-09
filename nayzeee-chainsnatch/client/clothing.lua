-----------------------------------------------------------------
-- Chains worn as CLOTHING (accessory slot 7, "teef")
--
-- chainkit keys clothing chains as "m|mp_m_mypack|3" (gender,
-- collection, number inside the pack). The game's collection
-- natives turn a ped's drawable back into that key, so it stays
-- right however your clothing packs are ordered.
-----------------------------------------------------------------

Clothing = {}

local COMP = 7

--- The chainkit key of accessory drawable `d` on this ped (any drawable, not just the one worn), and its collection
function Clothing.keyFor(ped, d)
    local model = GetEntityModel(ped)
    local g = model == `mp_m_freemode_01` and 'm' or model == `mp_f_freemode_01` and 'f' or nil
    if not g or not d or d <= 0 then return nil end
    local okN, coll = pcall(GetPedCollectionNameFromDrawable, ped, COMP, d)
    local okL, idx = pcall(GetPedCollectionLocalIndexFromDrawable, ped, COMP, d)
    if okN and okL and coll ~= nil and idx and idx >= 0 then
        coll = string.lower(coll)
        return ('%s|%s|%d'):format(g, coll, idx), coll
    end
    return ('%s||%d'):format(g, d), '' -- old game build: only base-game slots line up
end

function Clothing.key(ped)
    local key = Clothing.keyFor(ped, GetPedDrawableVariation(ped, COMP))
    if not key then return nil end
    local tex = GetPedTextureVariation(ped, COMP)
    return key, string.char(97 + math.max(0, math.min(25, tex)))
end

--- Is this ped wearing a clothing chain we have a prop for?
function Clothing.has(ped)
    if not Config.Snatch.Clothing then return false end
    local key = Clothing.key(ped)
    local d = key and Chains.def(key)
    return d ~= nil and d.origin == 'server'
end

local function handsUp(ped)
    local a = Config.HandsUpAnim
    return a and IsEntityPlayingAnim(ped, a.dict, a.clip, 3) or false
end

-- the server asks before a snatch
lib.callback.register('nzc:state', function()
    local ped = PlayerPedId()
    local key, letter = Clothing.key(ped)
    return {
        clothing = key, letter = letter,
        handsUp = handsUp(ped),
        dead = IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPedRagdoll(ped),
        noZone = Config.IsInNoSnatchZone(GetEntityCoords(ped)) == true,
    }
end)

RegisterNetEvent('nzc:c:ripClothing', function(none)
    local ped = PlayerPedId()
    SetTimeout(450, function()
        SetPedComponentVariation(ped, COMP, tonumber(none) or 0, 0, 0)
        pcall(Config.OnClothingChainRemoved, ped)
    end)
end)
