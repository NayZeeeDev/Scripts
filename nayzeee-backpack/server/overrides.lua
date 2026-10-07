-----------------------------------------------------------------
-- Live bag overrides
--
-- What admins change in /bagtune (offsets, slots, weight, price,
-- carry style) is saved to data/overrides.json and pushed to every
-- client through GlobalState. It survives restarts and wins over
-- config.lua, so nobody has to copy-paste offsets by hand any more.
-----------------------------------------------------------------

local RES = GetCurrentResourceName()
local FILE = 'data/overrides.json'

local overrides = {}

local function publish()
    Bags.setOverrides(overrides)
    GlobalState.nayzeee_bag_overrides = overrides
end

local function load()
    local raw = LoadResourceFile(RES, FILE)
    local ok, data = pcall(json.decode, raw or '{}')
    overrides = (ok and type(data) == 'table') and data or {}

    -- drop entries for bags that were removed from the config
    for key in pairs(overrides) do
        if not Config.Backpacks[key] then overrides[key] = nil end
    end
    publish()
end

local function save()
    local ok = SaveResourceFile(RES, FILE, json.encode(overrides, { indent = true }), -1)
    if not ok then print('^1[nayzeee-backpack] could not write ' .. FILE .. '^0') end
    return ok
end

load()

lib.callback.register('nayzeee-backpack:isAdmin', function(src)
    return Framework.isAdmin(src)
end)

-----------------------------------------------------------------
-- validation: nothing from the client is written without this
-----------------------------------------------------------------

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.max(lo, math.min(hi, v))
end

local function vec(t, lo, hi)
    if type(t) ~= 'table' then return nil end
    local x, y, z = num(t.x, lo, hi), num(t.y, lo, hi), num(t.z, lo, hi)
    if not x or not y or not z then return nil end
    return {
        x = math.floor(x * 10000 + 0.5) / 10000,
        y = math.floor(y * 10000 + 0.5) / 10000,
        z = math.floor(z * 10000 + 0.5) / 10000,
    }
end

local function clean(patch)
    if type(patch) ~= 'table' then return nil end
    local out, changed = {}, {}

    if type(patch.offset) == 'table' then
        local bone = num(patch.offset.bone, 0, 65535)
        local pos = vec(patch.offset.pos, -3.0, 3.0)
        local rot = vec(patch.offset.rot, -360.0, 360.0)
        if bone and pos and rot then
            out.offset = { bone = math.floor(bone), pos = pos, rot = rot }
            changed[#changed + 1] = 'offset'
        end
    end

    if patch.slots ~= nil then
        local v = num(patch.slots, 1, 200)
        if v then out.slots = math.floor(v); changed[#changed + 1] = ('slots=%d'):format(out.slots) end
    end
    if patch.weight ~= nil then
        local v = num(patch.weight, 0, 10000000)
        if v then out.weight = math.floor(v); changed[#changed + 1] = ('weight=%d'):format(out.weight) end
    end
    if patch.price ~= nil then
        local v = num(patch.price, 0, 100000000)
        if v then out.price = math.floor(v); changed[#changed + 1] = ('price=%d'):format(out.price) end
    end
    if type(patch.label) == 'string' and #patch.label > 0 then
        out.label = patch.label:sub(1, 64):gsub('[<>]', '')
        changed[#changed + 1] = 'label'
    end
    if type(patch.carry) == 'string' then
        if patch.carry == 'none' or (Config.Carry and Config.Carry.Styles and Config.Carry.Styles[patch.carry]) then
            out.carry = patch.carry
            changed[#changed + 1] = 'carry=' .. patch.carry
        end
    end
    if type(patch.pose) == 'string' and Bags.pose(patch.pose) then
        out.pose = patch.pose
        changed[#changed + 1] = 'pose=' .. patch.pose
    end

    return out, table.concat(changed, ', ')
end

RegisterNetEvent('nayzeee-backpack:admin:save', function(bagKey, patch)
    local src = source
    if not Framework.isAdmin(src) then
        return TriggerClientEvent('nayzeee-backpack:admin:result', src, false, Strings.no_admin)
    end
    if not Config.Backpacks[bagKey] then return end

    local out, what = clean(patch)
    if not out or what == '' then
        return TriggerClientEvent('nayzeee-backpack:admin:result', src, false, 'Nothing valid to save.')
    end

    local entry = overrides[bagKey] or {}
    for k, v in pairs(out) do entry[k] = v end
    overrides[bagKey] = entry

    publish()
    local ok = save()

    if Logs then Logs.admin(src, bagKey, what) end
    TriggerClientEvent('nayzeee-backpack:admin:result', src, ok,
        ok and ('Saved %s (%s).'):format(Bags.label(bagKey), what) or 'Could not write data/overrides.json')
end)

RegisterNetEvent('nayzeee-backpack:admin:clear', function(bagKey)
    local src = source
    if not Framework.isAdmin(src) then return end
    if not overrides[bagKey] then
        return TriggerClientEvent('nayzeee-backpack:admin:result', src, false, 'Nothing saved for that bag.')
    end
    overrides[bagKey] = nil
    publish()
    save()
    if Logs then Logs.admin(src, bagKey, 'cleared all studio edits') end
    TriggerClientEvent('nayzeee-backpack:admin:result', src, true, 'Back to config.lua values.')
end)
