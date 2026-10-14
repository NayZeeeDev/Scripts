--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: clothing (client, optional)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Used around the hospital gown / body bag:
    save what the player wears, change it, put it back afterwards.

      Bridge.Clothing.Save()    → bool    remember the current outfit
      Bridge.Clothing.Restore() → bool    put the remembered outfit back
      Bridge.Clothing.HasSaved()          Bridge.Clothing.Resource()

    illenium-appearance / fivem-appearance: getPedAppearance / setPedAppearance
    esx_skin (skinchanger):                 skinchanger:getSkin / skinchanger:loadSkin
    qb-clothing / rcore_clothing / native:  components + props snapshot
    (qb-clothing falls back to reloading the saved skin from its database)
    Config.Bridge.clothing = false disables all of it.
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Clothing = Bridge.Clothing or {}

local C = {}
Bridge.ClothingAdapters = C

local saved = nil   -- { adapter = name, data = ... }

-- ═══════════════════════════════════════════════════════════════════════════
-- NATIVE SNAPSHOT (works with every clothing script)
-- ═══════════════════════════════════════════════════════════════════════════

local function snapshot(ped)
    local data = { model = GetEntityModel(ped), components = {}, props = {} }
    for i = 0, 11 do
        data.components[i + 1] = { i, GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i), GetPedPaletteVariation(ped, i) }
    end
    for i = 0, 7 do
        data.props[#data.props + 1] = { i, GetPedPropIndex(ped, i), GetPedPropTextureIndex(ped, i) }
    end
    return data
end

local function applySnapshot(ped, data)
    if type(data) ~= 'table' or GetEntityModel(ped) ~= data.model then return false end
    for _, c in ipairs(data.components or {}) do
        SetPedComponentVariation(ped, c[1], c[2], c[3], c[4] or 0)
    end
    for _, p in ipairs(data.props or {}) do
        if p[2] == -1 then
            ClearPedProp(ped, p[1])
        else
            SetPedPropIndex(ped, p[1], p[2], p[3], true)
        end
    end
    return true
end

C['native'] = {
    save = function(ped) return snapshot(ped) end,
    restore = function(ped, data) return applySnapshot(ped, data) end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- ADAPTERS
-- ═══════════════════════════════════════════════════════════════════════════

local function appearance(resource)
    return {
        save = function(ped) return exports[resource]:getPedAppearance(ped) end,
        restore = function(ped, data)
            exports[resource]:setPedAppearance(ped, data)
            return true
        end,
    }
end

C['illenium-appearance'] = appearance('illenium-appearance')
C['fivem-appearance'] = appearance('fivem-appearance')

C['esx_skin'] = {
    save = function()
        local p = promise.new()
        TriggerEvent('skinchanger:getSkin', function(skin) p:resolve(skin or false) end)
        SetTimeout(2000, function() if p.state == 0 then p:resolve(false) end end)
        return Citizen.Await(p) or nil
    end,
    restore = function(_, data)
        TriggerEvent('skinchanger:loadSkin', data)
        return true
    end,
}

C['qb-clothing'] = {
    save = function(ped) return snapshot(ped) end,
    restore = function(ped, data)
        if applySnapshot(ped, data) then return true end
        TriggerServerEvent('qb-clothes:loadPlayerSkin')
        return true
    end,
}

C['rcore_clothing'] = C['native']

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE & API
-- ═══════════════════════════════════════════════════════════════════════════

local function resolve()
    if Bridge.Cfg('clothing', 'auto') == false then return nil end
    return Bridge.Pick('clothing', Bridge.Cfg('clothing', 'auto'), { has = function(n) return C[n] ~= nil end }) or 'native'
end

function Bridge.Clothing.Resource()
    return resolve()
end

function Bridge.Clothing.HasSaved()
    return saved ~= nil
end

function Bridge.Clothing.Save()
    local name = resolve()
    if not name then return false end
    local ped = PlayerPedId()
    local ok, data = Bridge.Try('clothing.' .. name .. '.save', C[name].save, ped)
    if ok and data then
        saved = { adapter = name, data = data, native = snapshot(ped) }
        return true
    end
    saved = { adapter = 'native', data = snapshot(ped), native = nil }
    return true
end

function Bridge.Clothing.Restore()
    if not saved then return false end
    local ped = PlayerPedId()
    local entry = saved
    saved = nil
    local adapter = C[entry.adapter]
    local ok, done = Bridge.Try('clothing.' .. entry.adapter .. '.restore', adapter and adapter.restore, ped, entry.data)
    if ok and done ~= false then return true end
    if entry.native then return applySnapshot(ped, entry.native) end
    return false
end
