-- 3D wigs on this client: which prop shows a hairstyle on the foam head.
-- The server sends hairmap ("m|mp_m_mypack|3" -> "nzw_m_1a2b3c4d_3"); a hairstyle number is turned into
-- that key with the game's collection natives, so props stay right when hair packs are added or reordered.

HairProps = { map = {} }

local keys = {}      -- [m] = { [drawable] = key }
local natives = nil  -- whether this game build has the collection natives

local function buildKeys(m)
    if keys[m] then return keys[m] end
    local out = {}
    local hash = m == 'm' and Config.Models.male.model or Config.Models.female.model
    if not pcall(lib.requestModel, hash, 5000) then return out end
    local c = GetEntityCoords(PlayerPedId())
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 50.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return out end
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    for d = 0, GetNumberOfPedDrawableVariations(ped, 2) - 1 do
        local okN, coll = pcall(GetPedCollectionNameFromDrawable, ped, 2, d)
        local okL, idx = pcall(GetPedCollectionLocalIndexFromDrawable, ped, 2, d)
        if okN and okL and coll ~= nil and idx and idx >= 0 then
            natives = true
            out[d] = ('%s|%s|%d'):format(m, string.lower(coll), idx)
        else
            natives = false
            out[d] = ('%s||%d'):format(m, d) -- old game build: only base-game slots line up
        end
    end
    DeleteEntity(ped)
    keys[m] = out
    return out
end

function HairProps.Key(m, d)
    return buildKeys(m == 'm' and 'm' or 'f')[d]
end

-- the hairstyle's own prop if it's built and streamed
function HairProps.Model(m, d)
    if not Config.HairProps.Enabled or not m or not d then return nil end
    local key = HairProps.Key(m, d)
    local prop = key and HairProps.map[key]
    if not prop then return nil end
    local h = GetHashKey(prop)
    return IsModelInCdimage(h) and h or nil
end

function HairProps.Has(m, d)
    local key = HairProps.Key(m, d)
    return key ~= nil and HairProps.map[key] ~= nil
end

RegisterNetEvent('nz-wig:c:hairmap', function(map)
    HairProps.map = type(map) == 'table' and map or {}
end)

CB.OnLoaded(function() TriggerServerEvent('nz-wig:s:hairmap') end)
CreateThread(function() if CB.IsLoaded() then TriggerServerEvent('nz-wig:s:hairmap') end end)

exports('HairPropModel', HairProps.Model)
