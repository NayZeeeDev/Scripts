--[[
    Target bridge (client): ox_target, qb-target, or the built-in prompt system.

    option = { name, label, icon, distance?, onSelect = function(entity), canInteract = function(entity) }

    Built-in mode costs nothing while no prompts are registered: a single scan
    thread exists only while entries exist and sleeps 500ms unless one is in reach.
]]

Target = {}

local function detect()
    if Config.Target ~= 'auto' then return Config.Target end
    if GetResourceState('ox_target') == 'started' then return 'ox' end
    if GetResourceState('qb-target') == 'started' then return 'qb' end
    return 'none'
end

Target.name = detect()

local zoneSeq = 0

--[[ ----------------------------- built-in prompts ----------------------------- ]]
local entries = {}  -- id -> entry
local scanning = false
local KEYS = { 38, 47, 74 } -- E, G, H
local KEY_LABELS = { 'E', 'G', 'H' }

local function entryCoords(e)
    if e.kind == 'zone' then return e.coords end
    if e.kind == 'entity' then
        if not DoesEntityExist(e.entity) then return nil end
        if e.offset then return GetOffsetFromEntityInWorldCoords(e.entity, e.offset.x, e.offset.y, e.offset.z) end
        return GetEntityCoords(e.entity)
    end
    if e.kind == 'model' then
        local pc = GetEntityCoords(cache.ped)
        for i = 1, #e.models do
            local obj = GetClosestObjectOfType(pc.x, pc.y, pc.z, 2.5, e.models[i], false, false, false)
            if obj ~= 0 then
                e.entity = obj
                return GetEntityCoords(obj)
            end
        end
        e.entity = nil
    end
end

local function usableOptions(e)
    local list = {}
    for i = 1, #e.options do
        local o = e.options[i]
        if not o.canInteract or o.canInteract(e.entity) then list[#list + 1] = o end
    end
    return list
end

local function startScan()
    if scanning then return end
    scanning = true
    CreateThread(function()
        local shown
        while next(entries) do
            local ped = cache.ped
            local pc = GetEntityCoords(ped)
            local best, bestDist
            for _, e in pairs(entries) do
                local c = entryCoords(e)
                if c then
                    local d = #(pc - c)
                    if d <= (e.radius or 1.5) and (not bestDist or d < bestDist) then best, bestDist = e, d end
                end
            end

            if best and not cache.vehicle and not LocalPlayer.state.nzwlBusy then
                local opts = usableOptions(best)
                if #opts > 0 then
                    local lines = {}
                    for i = 1, math.min(#opts, 3) do lines[i] = { key = KEY_LABELS[i], label = opts[i].label } end
                    local sig = best.id .. #opts
                    if shown ~= sig then UI.textui(lines) shown = sig end
                    for i = 1, math.min(#opts, 3) do
                        if IsControlJustReleased(0, KEYS[i]) then
                            UI.hideTextui() shown = nil
                            opts[i].onSelect(best.entity)
                            Wait(250)
                            break
                        end
                    end
                    Wait(0)
                else
                    if shown then UI.hideTextui() shown = nil end
                    Wait(300)
                end
            else
                if shown then UI.hideTextui() shown = nil end
                Wait(best == nil and 500 or 250)
            end
        end
        if shown then UI.hideTextui() end
        scanning = false
    end)
end

local function addEntry(e)
    zoneSeq = zoneSeq + 1
    e.id = 'nzwl_p' .. zoneSeq
    entries[e.id] = e
    startScan()
    return e.id
end

--[[ ----------------------------- public api ----------------------------- ]]

local function oxOptions(options)
    local out = {}
    for i = 1, #options do
        local o = options[i]
        out[i] = {
            name = o.name, label = o.label, icon = o.icon, distance = o.distance or 2.0,
            onSelect = function(data) o.onSelect(data and data.entity) end,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
        }
    end
    return out
end

local function qbOptions(options)
    local out = {}
    for i = 1, #options do
        local o = options[i]
        out[i] = {
            label = o.label, icon = o.icon,
            action = function(entity) o.onSelect(entity) end,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end or nil,
        }
    end
    return out
end

---@return any handle
function Target.addZone(coords, radius, options)
    coords = Utils.vec3(coords)
    if Target.name == 'ox' then
        return exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = oxOptions(options) })
    elseif Target.name == 'qb' then
        zoneSeq = zoneSeq + 1
        local name = 'nzwl_zone_' .. zoneSeq
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = Config.Debug, useZ = true },
            { options = qbOptions(options), distance = options[1] and options[1].distance or 2.0 })
        return name
    end
    return addEntry({ kind = 'zone', coords = coords, radius = math.max(radius, 1.2), options = options })
end

function Target.removeZone(handle)
    if not handle then return end
    if Target.name == 'ox' then
        exports.ox_target:removeZone(handle)
    elseif Target.name == 'qb' then
        exports['qb-target']:RemoveZone(handle)
    else
        entries[handle] = nil
    end
end

--- offset (built-in prompts only): the prompt sits at this offset from the entity instead of its centre
function Target.addEntity(entity, options, offset)
    if Target.name == 'ox' then
        exports.ox_target:addLocalEntity(entity, oxOptions(options))
        return { entity = entity, names = (function() local n = {} for i = 1, #options do n[i] = options[i].name end return n end)() }
    elseif Target.name == 'qb' then
        exports['qb-target']:AddTargetEntity(entity, { options = qbOptions(options), distance = 2.5 })
        return { entity = entity, labels = (function() local n = {} for i = 1, #options do n[i] = options[i].label end return n end)() }
    end
    return addEntry({ kind = 'entity', entity = entity, radius = offset and 1.6 or 2.2, offset = offset, options = options })
end

function Target.removeEntity(handle)
    if not handle then return end
    if Target.name == 'ox' then
        if DoesEntityExist(handle.entity) then exports.ox_target:removeLocalEntity(handle.entity, handle.names) end
    elseif Target.name == 'qb' then
        if DoesEntityExist(handle.entity) then exports['qb-target']:RemoveTargetEntity(handle.entity, handle.labels) end
    else
        entries[handle] = nil
    end
end

function Target.addModels(models, options)
    if Target.name == 'ox' then
        exports.ox_target:addModel(models, oxOptions(options))
        local names = {}
        for i = 1, #options do names[i] = options[i].name end
        return { models = models, names = names }
    elseif Target.name == 'qb' then
        exports['qb-target']:AddTargetModel(models, { options = qbOptions(options), distance = 2.0 })
        local labels = {}
        for i = 1, #options do labels[i] = options[i].label end
        return { models = models, labels = labels }
    end
    return addEntry({ kind = 'model', models = models, radius = 2.0, options = options })
end

function Target.removeModels(handle)
    if not handle then return end
    if Target.name == 'ox' then
        exports.ox_target:removeModel(handle.models, handle.names)
    elseif Target.name == 'qb' then
        exports['qb-target']:RemoveTargetModel(handle.models, handle.labels)
    else
        entries[handle] = nil
    end
end
