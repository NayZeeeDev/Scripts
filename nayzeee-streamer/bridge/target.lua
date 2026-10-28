-- Target bridge (client): ox_target, qb-target or a light text prompt. Open under escrow.
--
-- options = { { name, label, icon, distance, onSelect = fn(entity), canInteract = fn(entity) } }
-- Target.AddLocalEntity(entity, options)      Target.RemoveLocalEntity(entity, names?)
-- Target.AddSphere(name, coords, radius, options)   Target.RemoveZone(name)

Target = Target or {}

local DEFAULT_DISTANCE = 2.0

local function started(name)
    return GetResourceState(name) == 'started'
end

local function resolve()
    local wanted = Config.Target
    if wanted == 'ox' then wanted = 'ox_target' end
    if wanted == 'qb' or wanted == 'qb_target' then wanted = 'qb-target' end
    if wanted == 'ox_target' or wanted == 'qb-target' or wanted == 'textui' then return wanted end
    if started('ox_target') then return 'ox_target' end
    if started('qb-target') then return 'qb-target' end
    return 'textui'
end

Target.System = resolve()

local function faIcon(icon, prefix)
    if type(icon) ~= 'string' or icon == '' then icon = 'circle' end
    if icon:find('fa-', 1, true) then return icon end
    return prefix .. icon
end

local function maxDistance(options)
    local dist = 0.0
    for _, opt in ipairs(options) do
        local d = tonumber(opt.distance) or DEFAULT_DISTANCE
        if d > dist then dist = d end
    end
    return dist > 0.0 and dist or DEFAULT_DISTANCE
end

local function canUse(opt, entity)
    if type(opt.canInteract) ~= 'function' then return true end
    local ok, allowed = pcall(opt.canInteract, entity)
    return ok and allowed ~= false and allowed ~= nil
end

local function runOption(opt, entity)
    if type(opt.onSelect) ~= 'function' then return end
    CreateThread(function()
        local ok, err = pcall(opt.onSelect, entity)
        if not ok then Utils.Print('error', ('target option %s failed: %s'):format(tostring(opt.name), err)) end
    end)
end

local function nameList(names)
    if names == nil then return nil end
    if type(names) == 'string' then return { names } end
    return names
end

-- Bookkeeping shared by every system: [entity] = options, [zoneName] = { coords, radius, options, id }
local entities = {}
local zones = {}

---------------------------------------------------------------------------------------------------
-- ox_target

local function oxOptions(options)
    local list = {}
    for _, opt in ipairs(options) do
        list[#list + 1] = {
            name = opt.name,
            label = opt.label,
            icon = faIcon(opt.icon, 'fa-solid fa-'),
            distance = tonumber(opt.distance) or DEFAULT_DISTANCE,
            onSelect = function(data)
                local entity
                if type(data) == 'table' then entity = data.entity elseif type(data) == 'number' then entity = data end
                runOption(opt, entity)
            end,
            canInteract = function(entity)
                return canUse(opt, entity)
            end,
        }
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- qb-target

local function qbOptions(options)
    local list = {}
    for _, opt in ipairs(options) do
        list[#list + 1] = {
            type = 'client',
            label = opt.label,
            icon = faIcon(opt.icon, 'fas fa-'),
            action = function(entity)
                runOption(opt, type(entity) == 'number' and entity or nil)
            end,
            canInteract = function(entity)
                return canUse(opt, entity)
            end,
        }
    end
    return list
end

---------------------------------------------------------------------------------------------------
-- Text prompt fallback: proximity check every 500 ms, keys polled per frame only while a prompt shows.

local prompt = nil        -- { text, actions = { { control, opt, entity } } }
local loopRunning = false
local keysRunning = false

local function blocked()
    if IsNuiFocused() or IsPauseMenuActive() then return true end
    if type(Placement) == 'table' and type(Placement.Active) == 'function' and Placement.Active() then return true end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then return true end
    return false
end

local function keyList()
    local keys = Config.TextUI and Config.TextUI.Keys
    if type(keys) ~= 'table' or #keys == 0 then
        keys = { { key = 'E', control = 38 }, { key = 'G', control = 47 } }
    end
    return keys
end

local function hidePrompt()
    if prompt then
        prompt = nil
        Bridge.HideTextUI()
    end
end

local function bestTarget(pcoords)
    local best, bestDist

    for entity, options in pairs(entities) do
        if not DoesEntityExist(entity) then
            entities[entity] = nil
        else
            local dist = #(pcoords - GetEntityCoords(entity))
            if dist <= maxDistance(options) and (not bestDist or dist < bestDist) then
                local valid = {}
                for _, opt in ipairs(options) do
                    if dist <= (tonumber(opt.distance) or DEFAULT_DISTANCE) and canUse(opt, entity) then
                        valid[#valid + 1] = opt
                    end
                end
                if #valid > 0 then best, bestDist = { entity = entity, options = valid }, dist end
            end
        end
    end

    for _, zone in pairs(zones) do
        local dist = #(pcoords - zone.coords)
        if dist <= zone.radius and (not bestDist or dist < bestDist) then
            local valid = {}
            for _, opt in ipairs(zone.options) do
                if canUse(opt, nil) then valid[#valid + 1] = opt end
            end
            if #valid > 0 then best, bestDist = { entity = nil, options = valid }, dist end
        end
    end

    return best
end

local function startKeys()
    if keysRunning then return end
    keysRunning = true
    CreateThread(function()
        while prompt do
            local current = prompt
            for _, action in ipairs(current.actions) do
                if IsControlJustReleased(0, action.control) then
                    hidePrompt()
                    runOption(action.opt, action.entity)
                    break
                end
            end
            Wait(0)
        end
        keysRunning = false
    end)
end

local function showPrompt(target)
    local keys = keyList()
    local parts, actions = {}, {}
    for i, opt in ipairs(target.options) do
        local key = keys[i]
        if not key then break end
        parts[#parts + 1] = ('[%s] %s'):format(key.key, opt.label or opt.name or '?')
        actions[#actions + 1] = { control = key.control, opt = opt, entity = target.entity }
    end
    local text = table.concat(parts, '   ')
    if prompt and prompt.text == text and prompt.entity == target.entity then
        prompt.actions = actions
        return
    end
    prompt = { text = text, entity = target.entity, actions = actions }
    Bridge.ShowTextUI(text)
    startKeys()
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        while next(entities) or next(zones) do
            if blocked() then
                hidePrompt()
            else
                local target = bestTarget(GetEntityCoords(PlayerPedId()))
                if target then showPrompt(target) else hidePrompt() end
            end
            Wait(500)
        end
        hidePrompt()
        loopRunning = false
    end)
end

---------------------------------------------------------------------------------------------------
-- Public API

function Target.AddLocalEntity(entity, options)
    if not entity or entity == 0 or type(options) ~= 'table' or #options == 0 then return end
    local system = Target.System

    -- merge with options already on this entity (same name replaces)
    local current = entities[entity] or {}
    local replaced = {}
    for _, opt in ipairs(options) do
        for i = #current, 1, -1 do
            if current[i].name == opt.name then
                replaced[#replaced + 1] = opt.name
                table.remove(current, i)
            end
        end
        current[#current + 1] = opt
    end
    entities[entity] = current

    if system == 'ox_target' and started('ox_target') then
        pcall(function()
            if #replaced > 0 then exports.ox_target:removeLocalEntity(entity, replaced) end
            exports.ox_target:addLocalEntity(entity, oxOptions(options))
        end)
    elseif system == 'qb-target' and started('qb-target') then
        pcall(function()
            exports['qb-target']:AddTargetEntity(entity, { options = qbOptions(current), distance = maxDistance(current) })
        end)
    else
        startLoop()
    end
end

function Target.RemoveLocalEntity(entity, names)
    if not entity then return end
    local current = entities[entity]
    if not current then return end
    names = nameList(names)

    local removed, kept = {}, {}
    for _, opt in ipairs(current) do
        if not names or Utils.Contains(names, opt.name) then removed[#removed + 1] = opt else kept[#kept + 1] = opt end
    end
    entities[entity] = #kept > 0 and kept or nil

    local system = Target.System
    if system == 'ox_target' and started('ox_target') then
        local list = {}
        for _, opt in ipairs(removed) do list[#list + 1] = opt.name end
        pcall(function() exports.ox_target:removeLocalEntity(entity, list) end)
    elseif system == 'qb-target' and started('qb-target') then
        local labels = {}
        for _, opt in ipairs(removed) do labels[#labels + 1] = opt.label end
        pcall(function() exports['qb-target']:RemoveTargetEntity(entity, labels) end)
    elseif prompt and prompt.entity == entity then
        hidePrompt()
    end
end

function Target.AddSphere(name, coords, radius, options)
    if type(name) ~= 'string' or type(options) ~= 'table' or #options == 0 then return end
    coords = Utils.ToVec3(coords)
    if not coords then return end
    radius = tonumber(radius) or DEFAULT_DISTANCE
    if zones[name] then Target.RemoveZone(name) end

    local zone = { coords = coords, radius = radius, options = options }
    zones[name] = zone

    local system = Target.System
    if system == 'ox_target' and started('ox_target') then
        local ok, id = pcall(function()
            return exports.ox_target:addSphereZone({
                name = ('%s:%s'):format(GetCurrentResourceName(), name),
                coords = coords,
                radius = radius,
                debug = Config.Debug,
                options = oxOptions(options),
            })
        end)
        if ok then zone.id = id end
    elseif system == 'qb-target' and started('qb-target') then
        pcall(function()
            exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = Config.Debug, useZ = true },
                { options = qbOptions(options), distance = maxDistance(options) })
        end)
    else
        startLoop()
    end
end

function Target.RemoveZone(name)
    local zone = zones[name]
    if not zone then return end
    zones[name] = nil
    local system = Target.System
    if system == 'ox_target' and started('ox_target') then
        if zone.id then pcall(function() exports.ox_target:removeZone(zone.id) end) end
    elseif system == 'qb-target' and started('qb-target') then
        pcall(function() exports['qb-target']:RemoveZone(name) end)
    elseif prompt and prompt.entity == nil then
        hidePrompt()
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for entity in pairs(entities) do Target.RemoveLocalEntity(entity) end
    for name in pairs(zones) do Target.RemoveZone(name) end
    hidePrompt()
end)

CreateThread(function()
    DebugPrint(L('console.target', Target.System))
end)
