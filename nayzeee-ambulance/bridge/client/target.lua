--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: target / interaction (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Adapters: ox_target, qb-target, qtarget,
    interact (darktrc), sleepless_interact and a built-in fallback ([E] prompt
    via lib.showTextUI, ox_lib context menu when several options apply).

    API
      Bridge.Target.Player(options)                 Bridge.Target.RemovePlayer(names)
      Bridge.Target.Ped(options)                    Bridge.Target.RemovePed(names)       (non-player peds)
      Bridge.Target.Entity(entity, options)         Bridge.Target.RemoveEntity(entity, names)
      Bridge.Target.Model(models, options)          Bridge.Target.RemoveModel(models, names)
      Bridge.Target.Sphere(name, coords, radius, options)      → id
      Bridge.Target.Box(name, coords, size, heading, options)  → id
      Bridge.Target.Remove(id)
      Bridge.Target.Resource() → adapter name
      Bridge.Target.IsActive() → bool               the third eye is open right now

    OPTION FORMAT
      { name = 'nza_pulse', label = 'Check Pulse', icon = 'heart' (NAYZEEE icon or 'fa-solid fa-...'),
        distance = 2.0, order = 30,
        canInteract = function(entity, distance, coords) return true end,
        onSelect = function(entity, data) end }      -- data = adapter response (zone, coords, ...)

    Everything registered is kept in a registry and re-applied when the target
    resource restarts, so other modules never need to re-register.
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Target = Bridge.Target or {}

local T = {}
Bridge.TargetAdapters = T

local DEFAULT_DISTANCE = 2.0
local nameCounter = 0

-- ═══════════════════════════════════════════════════════════════════════════
-- REGISTRY
-- ═══════════════════════════════════════════════════════════════════════════

local R = {
    player = {},     -- array of options
    ped = {},        -- array of options
    entity = {},     -- [entity] = array of options
    model = {},      -- [hash] = array of options
    zone = {},       -- [id] = { kind = 'sphere'|'box', name, coords, radius, size, heading, options, raw }
}
Bridge.Target.Registry = R

local function builtinCfg()
    return Bridge.Cfg('builtinTarget', {}) or {}
end

local function optDistance(opt)
    return tonumber(opt.distance) or tonumber(builtinCfg().distance) or DEFAULT_DISTANCE
end

local function normalizeOptions(options)
    local out = {}
    if type(options) ~= 'table' then return out end
    if options.label and not options[1] then options = { options } end
    for _, opt in ipairs(options) do
        if type(opt) == 'table' and opt.label then
            if not opt.name then
                nameCounter = nameCounter + 1
                opt.name = ('nza_target_%d'):format(nameCounter)
            end
            out[#out + 1] = opt
        end
    end
    table.sort(out, function(a, b) return (tonumber(a.order) or 50) < (tonumber(b.order) or 50) end)
    return out
end

local function namesList(names)
    if names == nil then return nil end
    if type(names) == 'string' then return { names } end
    local out = {}
    for _, v in pairs(names) do out[#out + 1] = v end
    return out
end

local function addTo(list, options)
    for _, opt in ipairs(options) do
        for i = #list, 1, -1 do
            if list[i].name == opt.name then table.remove(list, i) end
        end
        list[#list + 1] = opt
    end
    table.sort(list, function(a, b) return (tonumber(a.order) or 50) < (tonumber(b.order) or 50) end)
end

local function removeFrom(list, names)
    if not names then
        for i = #list, 1, -1 do list[i] = nil end
        return
    end
    local set = {}
    for _, n in ipairs(names) do set[n] = true end
    for i = #list, 1, -1 do
        if set[list[i].name] then table.remove(list, i) end
    end
end

local function modelHash(model)
    if type(model) == 'string' then return joaat(model) end
    return tonumber(model)
end

local function modelList(models)
    if type(models) ~= 'table' then models = { models } end
    local out = {}
    for _, m in pairs(models) do
        local h = modelHash(m)
        if h then out[#out + 1] = h end
    end
    return out
end

-- Safe wrappers around the module's callbacks
local function canUse(opt, entity, distance, coords)
    if not opt.canInteract then return true end
    local ok, result = pcall(opt.canInteract, entity, distance, coords)
    if not ok then
        Bridge.Debug(('canInteract of "%s" failed: %s'):format(tostring(opt.name), tostring(result)))
        return false
    end
    return result and true or false
end

local function fireOption(opt, entity, data)
    if not opt.onSelect then return end
    local ok, err = pcall(opt.onSelect, entity or 0, data)
    if not ok then
        print(('^1[nayzeee-ambulance:bridge]^7 target option "%s" failed: %s'):format(tostring(opt.name), tostring(err)))
    end
end

local function entityCoords(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then return GetEntityCoords(entity) end
    return nil
end

local function distanceTo(entity, coords)
    local here = GetEntityCoords(PlayerPedId())
    local there = entityCoords(entity) or Bridge.ToVec3(coords)
    return there and #(here - there) or 0.0
end

local function maxDistance(options)
    local d = 0.0
    for _, opt in ipairs(options) do
        local od = optDistance(opt)
        if od > d then d = od end
    end
    return d > 0 and d or DEFAULT_DISTANCE
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ox_target  (and sleepless_interact's ox_target compat)
-- ═══════════════════════════════════════════════════════════════════════════

local function oxOptions(options)
    local out = {}
    for i, opt in ipairs(options) do
        out[i] = {
            name = opt.name,
            label = opt.label,
            icon = Bridge.FaIcon(opt.icon),
            iconColor = opt.iconColor,
            distance = optDistance(opt),
            bones = opt.bones,
            offset = opt.offset,
            canInteract = function(entity, distance, coords)
                return canUse(opt, entity, distance, coords)
            end,
            onSelect = function(data)
                fireOption(opt, type(data) == 'table' and data.entity or data, data)
            end,
        }
    end
    return out
end

local function oxNames(options)
    local out = {}
    for i, opt in ipairs(options) do out[i] = opt.name end
    return out
end

T['ox_target'] = {
    player = function(options) exports.ox_target:addGlobalPlayer(oxOptions(options)) end,
    ped = function(options) exports.ox_target:addGlobalPed(oxOptions(options)) end,
    entity = function(entity, options)
        if NetworkGetEntityIsNetworked(entity) then
            exports.ox_target:addEntity(NetworkGetNetworkIdFromEntity(entity), oxOptions(options))
        else
            exports.ox_target:addLocalEntity(entity, oxOptions(options))
        end
    end,
    model = function(models, options) exports.ox_target:addModel(models, oxOptions(options)) end,
    sphere = function(zone)
        return exports.ox_target:addSphereZone({
            name = zone.name, coords = zone.coords, radius = zone.radius, debug = false,
            options = oxOptions(zone.options),
        })
    end,
    box = function(zone)
        return exports.ox_target:addBoxZone({
            name = zone.name, coords = zone.coords, size = zone.size, rotation = zone.heading, debug = false,
            options = oxOptions(zone.options),
        })
    end,
    remove = function(zone) exports.ox_target:removeZone(zone.raw, true) end,
    removePlayer = function(names) exports.ox_target:removeGlobalPlayer(names) end,
    removePed = function(names) exports.ox_target:removeGlobalPed(names) end,
    removeEntity = function(entity, names)
        if NetworkGetEntityIsNetworked(entity) then
            exports.ox_target:removeEntity(NetworkGetNetworkIdFromEntity(entity), names)
        else
            exports.ox_target:removeLocalEntity(entity, names)
        end
    end,
    removeModel = function(models, names) exports.ox_target:removeModel(models, names) end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- qb-target / qtarget (options are keyed by LABEL: we remember name → label)
-- ═══════════════════════════════════════════════════════════════════════════

local labelsByName = {}

local function qbParams(options)
    local out = {}
    for _, opt in ipairs(options) do
        labelsByName[opt.name] = opt.label
        out[#out + 1] = {
            label = opt.label,
            icon = Bridge.FaIcon(opt.icon),
            num = tonumber(opt.order),
            distance = optDistance(opt),
            canInteract = function(entity, distance)
                return canUse(opt, entity, distance, entityCoords(entity))
            end,
            action = function(entity)
                fireOption(opt, entity, { entity = entity })
            end,
        }
    end
    return { options = out, distance = maxDistance(options) }
end

local function qbLabels(names)
    if not names then return nil end
    local out = {}
    for _, n in ipairs(names) do out[#out + 1] = labelsByName[n] or n end
    return out
end

local function makeQbTarget(res, fn)
    local function ex() return exports[res] end
    return {
        player = function(options) ex()[fn.player](ex(), qbParams(options)) end,
        ped = function(options) ex()[fn.ped](ex(), qbParams(options)) end,
        entity = function(entity, options) ex():AddTargetEntity(entity, qbParams(options)) end,
        model = function(models, options) ex():AddTargetModel(models, qbParams(options)) end,
        sphere = function(zone)
            ex():AddCircleZone(zone.name, zone.coords, zone.radius, { name = zone.name, debugPoly = false, useZ = true }, qbParams(zone.options))
            return zone.name
        end,
        box = function(zone)
            local z = zone.coords.z
            ex():AddBoxZone(zone.name, zone.coords, zone.size.y, zone.size.x, {
                name = zone.name, heading = zone.heading, debugPoly = false,
                minZ = z - zone.size.z / 2, maxZ = z + zone.size.z / 2,
            }, qbParams(zone.options))
            return zone.name
        end,
        remove = function(zone) ex():RemoveZone(zone.raw) end,
        removePlayer = function(names) ex()[fn.removePlayer](ex(), qbLabels(names)) end,
        removePed = function(names) ex()[fn.removePed](ex(), qbLabels(names)) end,
        removeEntity = function(entity, names) ex():RemoveTargetEntity(entity, qbLabels(names)) end,
        removeModel = function(models, names) ex():RemoveTargetModel(models, qbLabels(names)) end,
    }
end

T['qb-target'] = makeQbTarget('qb-target', {
    player = 'AddGlobalPlayer', ped = 'AddGlobalPed', removePlayer = 'RemoveGlobalPlayer', removePed = 'RemoveGlobalPed',
})

T['qtarget'] = makeQbTarget('qtarget', {
    player = 'Player', ped = 'Ped', removePlayer = 'RemovePlayer', removePed = 'RemovePed',
})

-- ═══════════════════════════════════════════════════════════════════════════
-- sleepless_interact
-- ═══════════════════════════════════════════════════════════════════════════

local function sleeplessOptions(options, minDistance)
    local out = {}
    for i, opt in ipairs(options) do
        out[i] = {
            name = opt.name,
            label = opt.label,
            icon = Bridge.FaIcon(opt.icon),
            distance = math.max(optDistance(opt), minDistance or 0),
            bones = opt.bones,
            offset = opt.offset,
            canInteract = function(entity, distance, coords)
                return canUse(opt, entity, distance, coords)
            end,
            onSelect = function(data)
                fireOption(opt, type(data) == 'table' and data.entity or 0, data)
            end,
        }
    end
    return out
end

local SL = 'sleepless_interact'

T['sleepless_interact'] = {
    player = function(options) exports[SL]:addGlobalPlayer(sleeplessOptions(options)) end,
    ped = function(options) exports[SL]:addGlobalPed(sleeplessOptions(options)) end,
    entity = function(entity, options)
        if NetworkGetEntityIsNetworked(entity) then
            exports[SL]:addEntity(NetworkGetNetworkIdFromEntity(entity), sleeplessOptions(options))
        else
            exports[SL]:addLocalEntity(entity, sleeplessOptions(options))
        end
    end,
    model = function(models, options) exports[SL]:addModel(models, sleeplessOptions(options)) end,
    sphere = function(zone)
        return exports[SL]:addCoords(zone.coords, sleeplessOptions(zone.options, zone.radius))
    end,
    box = function(zone)
        local reach = math.max(zone.size.x, zone.size.y) / 2
        return exports[SL]:addCoords(zone.coords, sleeplessOptions(zone.options, reach))
    end,
    remove = function(zone) exports[SL]:removeCoords(zone.raw) end,
    removePlayer = function(names) exports[SL]:removeGlobalPlayer(names) end,
    removePed = function(names) exports[SL]:removeGlobalPed(names) end,
    removeEntity = function(entity, names)
        if NetworkGetEntityIsNetworked(entity) then
            exports[SL]:removeEntity(NetworkGetNetworkIdFromEntity(entity), names)
        else
            exports[SL]:removeLocalEntity(entity, names)
        end
    end,
    removeModel = function(models, names) exports[SL]:removeModel(models, names) end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- interact (darktrc) - interactions are grouped by id; there is no global ped
-- target, so nearby peds get a local interaction from a small tracker.
-- ═══════════════════════════════════════════════════════════════════════════

local function interactOptions(options)
    local out = {}
    for i, opt in ipairs(options) do
        out[i] = {
            name = opt.name,
            label = opt.label,
            canInteract = function(entity, coords)
                return canUse(opt, entity, distanceTo(entity, coords), coords)
            end,
            action = function(entity)
                fireOption(opt, entity, { entity = entity })
            end,
        }
    end
    return out
end

local IX = 'interact'
local ixPeds = {}         -- [ped] = interaction id
local ixPedThread = false

local function ixPedOptionsChanged()
    for ped, id in pairs(ixPeds) do
        if DoesEntityExist(ped) then exports[IX]:RemoveLocalEntityInteraction(ped, id) end
        ixPeds[ped] = nil
    end
    if ixPedThread or #R.ped == 0 then return end
    ixPedThread = true
    CreateThread(function()
        while #R.ped > 0 and Bridge.Target.Resource() == 'interact' do
            local here = GetEntityCoords(PlayerPedId())
            local reach = maxDistance(R.ped)
            local seen = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and #(here - GetEntityCoords(ped)) < 12.0 then
                    seen[ped] = true
                    if not ixPeds[ped] then
                        local id = ('nza:ped:%d'):format(ped)
                        exports[IX]:AddLocalEntityInteraction({
                            entity = ped, id = id, name = id, distance = 8.0, interactDst = reach,
                            ignoreLos = false, options = interactOptions(R.ped),
                        })
                        ixPeds[ped] = id
                    end
                end
            end
            for ped, id in pairs(ixPeds) do
                if not seen[ped] then
                    if DoesEntityExist(ped) then exports[IX]:RemoveLocalEntityInteraction(ped, id) end
                    ixPeds[ped] = nil
                end
            end
            Wait(1000)
        end
        for ped, id in pairs(ixPeds) do
            if DoesEntityExist(ped) then pcall(function() exports[IX]:RemoveLocalEntityInteraction(ped, id) end) end
            ixPeds[ped] = nil
        end
        ixPedThread = false
    end)
end

local ixPlayerId = 'nza:players'
local ixEntityIds = {}    -- [entity] = id
local ixModelIds = {}     -- [hash] = id

local function ixEntity(entity)
    local id = ixEntityIds[entity]
    if id then
        if NetworkGetEntityIsNetworked(entity) then
            exports[IX]:RemoveEntityInteraction(NetworkGetNetworkIdFromEntity(entity), id)
        else
            exports[IX]:RemoveLocalEntityInteraction(entity, id)
        end
        ixEntityIds[entity] = nil
    end
    local options = R.entity[entity]
    if not options or #options == 0 then return end
    id = ('nza:ent:%d'):format(entity)
    local data = { id = id, name = id, distance = 8.0, interactDst = maxDistance(options), options = interactOptions(options) }
    if NetworkGetEntityIsNetworked(entity) then
        data.netId = NetworkGetNetworkIdFromEntity(entity)
        exports[IX]:AddEntityInteraction(data)
    else
        data.entity = entity
        exports[IX]:AddLocalEntityInteraction(data)
    end
    ixEntityIds[entity] = id
end

local function ixModel(hash)
    if ixModelIds[hash] then
        exports[IX]:RemoveModelInteraction(hash, ixModelIds[hash])
        ixModelIds[hash] = nil
    end
    local options = R.model[hash]
    if not options or #options == 0 then return end
    local id = ('nza:model:%d'):format(hash)
    exports[IX]:AddModelInteraction({
        model = hash, id = id, name = id, distance = 8.0, interactDst = maxDistance(options), options = interactOptions(options),
    })
    ixModelIds[hash] = id
end

local function ixPlayers()
    pcall(function() exports[IX]:RemoveGlobalPlayerInteraction(ixPlayerId) end)
    if #R.player == 0 then return end
    exports[IX]:addGlobalPlayerInteraction({
        id = ixPlayerId, distance = 8.0, interactDst = maxDistance(R.player), options = interactOptions(R.player),
    })
end

local function ixZone(zone)
    local reach = zone.radius or (math.max(zone.size.x, zone.size.y) / 2)
    local id = 'nza:zone:' .. zone.id
    exports[IX]:AddInteraction({
        coords = zone.coords, distance = reach + 6.0, interactDst = math.max(reach, 1.0),
        id = id, name = id, options = interactOptions(zone.options),
    })
    return id
end

T['interact'] = {
    -- the registry is already updated: rebuild the affected interaction
    player = function() ixPlayers() end,
    ped = function() ixPedOptionsChanged() end,
    entity = function(entity) ixEntity(entity) end,
    model = function(models) for _, h in ipairs(models) do ixModel(h) end end,
    sphere = ixZone,
    box = ixZone,
    remove = function(zone) exports[IX]:RemoveInteraction(zone.raw) end,
    removePlayer = function() ixPlayers() end,
    removePed = function() ixPedOptionsChanged() end,
    removeEntity = function(entity) ixEntity(entity) end,
    removeModel = function(models) for _, h in ipairs(models) do ixModel(h) end end,
    reset = function()
        ixEntityIds, ixModelIds = {}, {}
        for ped in pairs(ixPeds) do ixPeds[ped] = nil end
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILT-IN FALLBACK  ([E] prompt, context menu for several options)
-- Reads the registry directly; the adapter functions only wake it up.
-- ═══════════════════════════════════════════════════════════════════════════

local BI = { current = nil, shown = nil, running = false, gen = 0 }

local function validOptions(options, entity, distance, coords)
    local out = {}
    for _, opt in ipairs(options) do
        if distance <= optDistance(opt) and canUse(opt, entity, distance, coords) then
            out[#out + 1] = opt
        end
    end
    return out
end

local function insideBox(zone, pos)
    local rel = pos - zone.coords
    local h = math.rad(-(zone.heading or 0.0))
    local x = rel.x * math.cos(h) - rel.y * math.sin(h)
    local y = rel.x * math.sin(h) + rel.y * math.cos(h)
    return math.abs(x) <= zone.size.x / 2 and math.abs(y) <= zone.size.y / 2 and math.abs(rel.z) <= zone.size.z / 2 + 1.0
end

local function hasAnything()
    return #R.player > 0 or #R.ped > 0 or next(R.entity) ~= nil or next(R.model) ~= nil or next(R.zone) ~= nil
end

-- entities near you, shared with the rest of the resource (NZA.Scan refreshes them every 2 s)
local function nearPool(pool)
    if NZA.Scan and NZA.Scan.Near then return NZA.Scan.Near(pool) end
    return GetGamePool(pool)
end

local function scan()
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestDist = nil, math.huge

    local function consider(entity, coords, distance, options)
        if distance >= bestDist then return end
        local valid = validOptions(options, entity, distance, coords)
        if #valid > 0 then
            best = { entity = entity, coords = coords, options = valid }
            bestDist = distance
        end
    end

    for _, zone in pairs(R.zone) do
        local d = #(pos - zone.coords)
        if zone.kind == 'sphere' then
            if d <= zone.radius then consider(0, zone.coords, math.max(0.0, d - zone.radius + 0.01), zone.options) end
        elseif d < 30.0 and insideBox(zone, pos) then
            consider(0, zone.coords, 0.0, zone.options)
        end
    end

    for entity, options in pairs(R.entity) do
        if DoesEntityExist(entity) then
            local c = GetEntityCoords(entity)
            local d = #(pos - c)
            if d <= maxDistance(options) then consider(entity, c, d, options) end
        end
    end

    if #R.player > 0 then
        local reach = maxDistance(R.player)
        local myId = PlayerId()
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= myId then
                local ped = GetPlayerPed(pid)
                local c = GetEntityCoords(ped)
                local d = #(pos - c)
                if d <= reach then consider(ped, c, d, R.player) end
            end
        end
    end

    local wantPeds, wantModels = #R.ped > 0, next(R.model) ~= nil
    if wantPeds or wantModels then
        local pedReach = wantPeds and maxDistance(R.ped) or 0.0
        for _, ped in ipairs(nearPool('CPed')) do
            if ped ~= me and DoesEntityExist(ped) then
                local c = GetEntityCoords(ped)
                local d = #(pos - c)
                if d <= 6.0 then
                    if wantPeds and d <= pedReach and not IsPedAPlayer(ped) then consider(ped, c, d, R.ped) end
                    local mopts = wantModels and R.model[GetEntityModel(ped)]
                    if mopts then consider(ped, c, d, mopts) end
                end
            end
        end
    end

    if wantModels then
        for _, pool in ipairs({ 'CObject', 'CVehicle' }) do
            for _, ent in ipairs(nearPool(pool)) do
                local mopts = DoesEntityExist(ent) and R.model[GetEntityModel(ent)]
                if mopts then
                    local c = GetEntityCoords(ent)
                    local d = #(pos - c)
                    if d <= maxDistance(mopts) then consider(ent, c, d, mopts) end
                end
            end
        end
    end

    return best
end

local function promptText(target)
    local cfg = builtinCfg()
    local text = NZA.L('bridge.target_prompt', cfg.keyLabel or 'E', target.options[1].label)
    if #target.options > 1 then text = text .. NZA.L('bridge.target_more', #target.options - 1) end
    return text
end

-- the [E] pill of the resource's own prompt layer (the same style as every other prompt);
-- ox_lib's text UI only when the NUI is not there
local function usePills() return NZA and NZA.UI and NZA.UI.Prompt ~= nil end

local function hidePrompt()
    if BI.shown then
        if usePills() then NZA.UI.HidePrompt('nza_builtin_target') else lib.hideTextUI() end
        BI.shown = nil
    end
end

local function openMenu(target)
    local items = {}
    for _, opt in ipairs(target.options) do
        items[#items + 1] = {
            title = opt.label,
            icon = Bridge.FaIcon(opt.icon),
            onSelect = function()
                local d = target.entity ~= 0 and distanceTo(target.entity) or distanceTo(nil, target.coords)
                if canUse(opt, target.entity, d, target.coords) then
                    fireOption(opt, target.entity, { entity = target.entity, coords = target.coords, distance = d })
                end
            end,
        }
    end
    lib.registerContext({ id = 'nza_bridge_target', title = NZA.L('bridge.target_menu'), options = items })
    lib.showContext('nza_bridge_target')
end

local function startBuiltin()
    if BI.running then return end
    BI.running = true
    BI.gen = BI.gen + 1
    local gen = BI.gen
    local function alive() return BI.running and BI.gen == gen end

    -- scanner
    CreateThread(function()
        while alive() do
            local cfg = builtinCfg()
            if hasAnything() and Bridge.Target.Resource() == 'builtin' and not IsNuiFocused() and not IsPauseMenuActive()
                and not IsPedInAnyVehicle(PlayerPedId(), false) then
                BI.current = scan()
            else
                BI.current = nil
            end
            Wait(tonumber(cfg.scan) or 250)
        end
        if BI.gen == gen then BI.current = nil end
    end)

    -- prompt + key (per frame only while something is in reach)
    CreateThread(function()
        while alive() do
            local target = BI.current
            if target then
                local text = promptText(target)
                if BI.shown ~= text then
                    if usePills() then
                        local more = #target.options > 1 and NZA.L('bridge.target_more', #target.options - 1) or nil
                        NZA.UI.Prompt('nza_builtin_target', { key = builtinCfg().keyLabel or 'E', label = target.options[1].label, sub = more and more:match('^%s*(.-)%s*$') or nil })
                    else
                        lib.showTextUI(text)
                    end
                    BI.shown = text
                end
                local cfg = builtinCfg()
                if cfg.markers and target.coords then
                    DrawMarker(28, target.coords.x, target.coords.y, target.coords.z + 1.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.05, 0.05, 0.05, 8, 175, 162, 200, false, false, 2, false, nil, nil, false)
                end
                if IsControlJustReleased(0, tonumber(cfg.key) or 38) and not IsNuiFocused() then
                    hidePrompt()
                    if #target.options == 1 then
                        local opt = target.options[1]
                        fireOption(opt, target.entity, { entity = target.entity, coords = target.coords })
                    else
                        openMenu(target)
                    end
                    BI.current = nil
                    Wait(300)
                end
                Wait(0)
            else
                hidePrompt()
                Wait(250)
            end
        end
        if BI.gen == gen then hidePrompt() end
    end)
end

local function stopBuiltin()
    BI.running = false
    BI.current = nil
    if BI.shown then
        lib.hideTextUI()
        BI.shown = nil
    end
end

T['builtin'] = {
    player = startBuiltin, ped = startBuiltin, entity = startBuiltin, model = startBuiltin,
    sphere = function(zone) startBuiltin() return zone.id end,
    box = function(zone) startBuiltin() return zone.id end,
    remove = function() end, removePlayer = function() end, removePed = function() end,
    removeEntity = function() end, removeModel = function() end,
    reset = stopBuiltin,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local resolved, resolvedOnce = nil, false

local function resolve()
    if resolvedOnce then return resolved end
    resolvedOnce = true
    resolved = Bridge.Pick('target', Bridge.Cfg('target', 'auto'), {
        has = function(name) return T[name] ~= nil end,
    }) or 'builtin'
    Bridge.Debug('target:', resolved)
    return resolved
end

-- true while the player holds the third eye open ([E] prompts step aside meanwhile)
function Bridge.Target.IsActive()
    local res = Bridge.Target.Resource()
    if res == 'ox_target' then
        local ok, v = pcall(function() return exports.ox_target:isActive() end)
        if ok and v ~= nil then return v == true end
    elseif res == 'qb-target' or res == 'qtarget' then
        local ok, v = pcall(function() return exports[res]:IsTargetActive() end)
        if ok and v ~= nil then return v == true end
    end
    -- no export to ask: the usual third-eye key (left Alt) held down
    return IsControlPressed(0, 19) or IsDisabledControlPressed(0, 19)
end

function Bridge.Target.Resource()
    return resolve()
end

local function run(method, ...)
    local name = resolve()
    local A = T[name]
    if not A or not A[method] then return false end
    return Bridge.Try(('target.%s.%s'):format(name, method), A[method], ...)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.Target.Player(options)
    options = normalizeOptions(options)
    if #options == 0 then return end
    addTo(R.player, options)
    run('player', options)
end

function Bridge.Target.Ped(options)
    options = normalizeOptions(options)
    if #options == 0 then return end
    addTo(R.ped, options)
    run('ped', options)
end

function Bridge.Target.Entity(entity, options)
    entity = tonumber(entity)
    options = normalizeOptions(options)
    if not entity or entity == 0 or #options == 0 then return end
    R.entity[entity] = R.entity[entity] or {}
    addTo(R.entity[entity], options)
    run('entity', entity, options)
end

function Bridge.Target.Model(models, options)
    local hashes = modelList(models)
    options = normalizeOptions(options)
    if #hashes == 0 or #options == 0 then return end
    for _, h in ipairs(hashes) do
        R.model[h] = R.model[h] or {}
        addTo(R.model[h], options)
    end
    run('model', hashes, options)
end

local zoneCounter = 0

local function addZone(kind, name, coords, options, extra)
    coords = Bridge.ToVec3(coords)
    options = normalizeOptions(options)
    if not coords or #options == 0 then return nil end
    zoneCounter = zoneCounter + 1
    local id = (type(name) == 'string' and name ~= '') and name or ('nza_zone_%d'):format(zoneCounter)
    if R.zone[id] then Bridge.Target.Remove(id) end
    local zone = { id = id, kind = kind, name = id, coords = coords, options = options }
    for k, v in pairs(extra) do zone[k] = v end
    R.zone[id] = zone
    local ok, raw = run(kind, zone)
    zone.raw = ok and raw or id
    return id
end

function Bridge.Target.Sphere(name, coords, radius, options)
    return addZone('sphere', name, coords, options, { radius = tonumber(radius) or 1.5 })
end

function Bridge.Target.Box(name, coords, size, heading, options)
    local s = Bridge.ToVec3(size) or vector3(1.5, 1.5, 2.0)
    return addZone('box', name, coords, options, { size = s, heading = tonumber(heading) or 0.0 })
end

function Bridge.Target.Remove(id)
    local zone = R.zone[id]
    if not zone then return end
    R.zone[id] = nil
    run('remove', zone)
end

function Bridge.Target.RemovePlayer(names)
    names = namesList(names)
    removeFrom(R.player, names)
    run('removePlayer', names)
end

function Bridge.Target.RemovePed(names)
    names = namesList(names)
    removeFrom(R.ped, names)
    run('removePed', names)
end

function Bridge.Target.RemoveEntity(entity, names)
    entity = tonumber(entity)
    if not entity or not R.entity[entity] then return end
    names = namesList(names)
    removeFrom(R.entity[entity], names)
    if #R.entity[entity] == 0 then R.entity[entity] = nil end
    if DoesEntityExist(entity) then run('removeEntity', entity, names) end
end

function Bridge.Target.RemoveModel(models, names)
    local hashes = modelList(models)
    names = namesList(names)
    for _, h in ipairs(hashes) do
        if R.model[h] then
            removeFrom(R.model[h], names)
            if #R.model[h] == 0 then R.model[h] = nil end
        end
    end
    run('removeModel', hashes, names)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RE-APPLY EVERYTHING (target resource restarted / switched)
-- ═══════════════════════════════════════════════════════════════════════════

local function reapply()
    local name = resolve()
    local A = T[name]
    if A and A.reset and name ~= 'builtin' then pcall(A.reset) end
    if #R.player > 0 then run('player', R.player) end
    if #R.ped > 0 then run('ped', R.ped) end
    for entity, options in pairs(R.entity) do
        if DoesEntityExist(entity) then run('entity', entity, options) else R.entity[entity] = nil end
    end
    for h, options in pairs(R.model) do
        run('model', { h }, options)
    end
    for _, zone in pairs(R.zone) do
        local ok, raw = run(zone.kind, zone)
        zone.raw = ok and raw or zone.id
    end
end

local function onResource(resource)
    if resource == GetCurrentResourceName() or not Bridge.IsKnownResource('target', resource) then return end
    local before = resolved
    resolvedOnce, resolved = false, nil
    SetTimeout(1000, function()
        local now = resolve()
        -- another target script started/stopped while ours keeps running: nothing to do
        if before == now and Bridge.Resources.target[now] ~= resource then return end
        if before and before ~= now and T[before] and T[before].reset then pcall(T[before].reset) end
        reapply()
    end)
end

AddEventHandler('onClientResourceStart', onResource)
AddEventHandler('onClientResourceStop', onResource)

-- drop deleted entities from the registry
CreateThread(function()
    while true do
        Wait(10000)
        for entity in pairs(R.entity) do
            if not DoesEntityExist(entity) then R.entity[entity] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if BI.shown then lib.hideTextUI() end
end)
