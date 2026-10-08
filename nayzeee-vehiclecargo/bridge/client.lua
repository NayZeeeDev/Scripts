Bridge = {}

local function running(r) return GetResourceState(r) == 'started' end

local ESX, QB
local function esx() if not ESX and running('es_extended') then ESX = exports.es_extended:getSharedObject() end return ESX end
local function qb() if not QB and running('qb-core') then QB = exports['qb-core']:GetCoreObject() end return QB end

-----------------------------------------------------------------
-- NOTIFICATIONS   Config.Notify
-----------------------------------------------------------------
local function notifySystem()
    local want = Config.Notify
    if want ~= 'auto' then return want end
    if running('nayzeee-notify') then return 'nayzeee' end
    if running('okokNotify') then return 'okok' end
    return 'ox'
end

function Bridge.Notify(message, ntype, title, duration)
    ntype = ntype or 'info'
    local sys = notifySystem()
    if sys == 'nayzeee' then
        exports['nayzeee-notify']:Notify({ title = title, message = message, type = ntype, duration = duration })
    elseif sys == 'okok' then
        exports['okokNotify']:Alert(title or 'Vehicle Cargo', message, duration or 5000, ntype == 'warning' and 'warning' or ntype)
    elseif sys == 'esx' and esx() then
        esx().ShowNotification(message, ntype, duration)
    elseif sys == 'qb' and qb() then
        qb().Functions.Notify(message, ntype == 'info' and 'primary' or ntype, duration)
    elseif sys == 'custom' then
        -- put your own notification call here
        print(('[vehiclecargo] %s: %s'):format(title or ntype, message))
    else
        lib.notify({ title = title, description = message, type = ntype == 'info' and 'inform' or ntype, duration = duration })
    end
end

RegisterNetEvent('nz_cargo:notify', function(message, ntype, title, duration)
    Bridge.Notify(message, ntype, title, duration)
end)

-----------------------------------------------------------------
-- TEXT UI   Config.TextUI
-----------------------------------------------------------------
local function textSystem()
    local want = Config.TextUI
    if want ~= 'auto' then return want end
    if running('nayzeee-notify') then return 'nayzeee' end
    if running('okokTextUI') then return 'okok' end
    return 'ox'
end

local textShown, textSeen, textWatch = nil, 0, false

-- Every prompt here is redrawn each frame by whatever shows it. One that stops
-- being refreshed (point removed, mission over, you got out of the car, you
-- teleported) hides itself, so nothing can stay stuck on screen.
local function watchText()
    if textWatch then return end
    textWatch = true
    CreateThread(function()
        while textShown do
            if GetGameTimer() - textSeen > 400 then Bridge.HideText() break end
            Wait(100)
        end
        textWatch = false
    end)
end

function Bridge.ShowText(key, label)
    textSeen = GetGameTimer()
    local id = key .. label
    if textShown == id then return end
    textShown = id
    watchText()
    local text = key ~= '' and ('[%s] %s'):format(key, label) or label
    local sys = textSystem()
    if sys == 'nayzeee' then
        exports['nayzeee-notify']:ShowTextUI(label, key ~= '' and { key = key } or nil)
    elseif sys == 'okok' then
        exports['okokTextUI']:Open(text, 'darkgreen', 'left')
    elseif sys == 'esx' and esx() then
        esx().TextUI(text, 'info')
    elseif sys == 'qb' and running('qb-core') then
        exports['qb-core']:DrawText(text, 'left')
    else
        lib.showTextUI(text)
    end
end

function Bridge.HideText()
    if not textShown then return end
    textShown = nil
    local sys = textSystem()
    if sys == 'nayzeee' then
        exports['nayzeee-notify']:HideTextUI()
    elseif sys == 'okok' then
        exports['okokTextUI']:Close()
    elseif sys == 'esx' and esx() then
        esx().HideUI()
    elseif sys == 'qb' and running('qb-core') then
        exports['qb-core']:HideText()
    else
        lib.hideTextUI()
    end
end

-----------------------------------------------------------------
-- THIRD EYE / INTERACTION   Config.Target
-- options = { { label, icon, onSelect = fn, canInteract = fn? }, ... }
-----------------------------------------------------------------
local function targetSystem()
    local want = Config.Target
    if want ~= 'auto' then return want end
    if running('ox_target') then return 'ox_target' end
    if running('qb-target') then return 'qb-target' end
    if running('interact') then return 'interact' end
    return 'textui'
end
Bridge.TargetSystem = targetSystem

local zones = {}   -- [id] = { kind, handle, point }

local function allowed(o) return not o.canInteract or o.canInteract() end

-- Text UI fallback: one key opens the option directly, or a menu when there are several.
local function textPoint(id, coords, radius, options)
    local p = lib.points.new({ coords = coords, distance = math.max(radius + 1.5, 3.0) })
    local function visible()
        local list = {}
        for _, o in ipairs(options) do if allowed(o) then list[#list + 1] = o end end
        return list
    end
    function p:nearby()
        if Client and Client.nui then return end
        if self.currentDistance > radius then Bridge.HideText() return end
        local list = visible()
        if #list == 0 then Bridge.HideText() return end
        Bridge.ShowText(Config.Interact.KeyLabel, #list == 1 and list[1].label or 'Interact')
        if IsControlJustPressed(0, Config.Interact.Key) then
            Bridge.HideText()
            if #list == 1 then list[1].onSelect() return end
            local opts = {}
            for _, o in ipairs(list) do opts[#opts + 1] = { title = o.label, icon = o.icon, onSelect = o.onSelect } end
            lib.registerContext({ id = 'nz_cargo_' .. id, title = 'Options', options = opts })
            lib.showContext('nz_cargo_' .. id)
        end
    end
    function p:onExit() Bridge.HideText() end
    return p
end

function Bridge.AddPoint(id, coords, radius, options)
    Bridge.RemovePoint(id)
    radius = radius or Config.Interact.Distance
    local sys = targetSystem()
    if sys == 'ox_target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { name = id .. ':' .. i, label = o.label, icon = o.icon, distance = radius + 1.0, onSelect = function() o.onSelect() end, canInteract = o.canInteract and function() return o.canInteract() end or nil }
        end
        zones[id] = { kind = 'ox', handle = exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = Config.Debug, options = opts }) }
    elseif sys == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do opts[i] = { icon = o.icon, label = o.label, action = function() o.onSelect() end, canInteract = o.canInteract } end
        exports['qb-target']:AddCircleZone(id, coords, radius, { name = id, debugPoly = Config.Debug, useZ = true }, { options = opts, distance = radius + 1.0 })
        zones[id] = { kind = 'qb' }
    elseif sys == 'interact' then
        local opts = {}
        for i, o in ipairs(options) do opts[i] = { label = o.label, action = function() o.onSelect() end, canInteract = o.canInteract } end
        exports.interact:AddInteraction({ coords = coords, distance = radius + 6.0, interactDst = radius, id = id, name = id, options = opts })
        zones[id] = { kind = 'interact' }
    else
        zones[id] = { kind = 'text', point = textPoint(id, coords, radius, options) }
    end
end

function Bridge.RemovePoint(id)
    local z = zones[id]
    if not z then return end
    if z.kind == 'ox' then pcall(function() exports.ox_target:removeZone(z.handle) end)
    elseif z.kind == 'qb' then pcall(function() exports['qb-target']:RemoveZone(id) end)
    elseif z.kind == 'interact' then pcall(function() exports.interact:RemoveInteraction(id) end)
    elseif z.kind == 'text' and z.point then z.point:remove() Bridge.HideText() end
    zones[id] = nil
end

-- Target on a (local) entity, e.g. a parked display car or an NPC.
function Bridge.AddEntity(entity, id, options, radius)
    Bridge.RemoveEntity(entity, id)
    radius = radius or 2.5
    local sys = targetSystem()
    if sys == 'ox_target' then
        local opts = {}
        for i, o in ipairs(options) do
            opts[i] = { name = id .. ':' .. i, label = o.label, icon = o.icon, distance = radius, onSelect = function() o.onSelect() end, canInteract = o.canInteract and function() return o.canInteract() end or nil }
        end
        exports.ox_target:addLocalEntity(entity, opts)
        zones[id] = { kind = 'oxe', entity = entity, names = (function() local n = {} for i in ipairs(opts) do n[i] = id .. ':' .. i end return n end)() }
    elseif sys == 'qb-target' then
        local opts = {}
        for i, o in ipairs(options) do opts[i] = { icon = o.icon, label = o.label, action = function() o.onSelect() end, canInteract = o.canInteract } end
        exports['qb-target']:AddTargetEntity(entity, { options = opts, distance = radius })
        zones[id] = { kind = 'qbe', entity = entity }
    elseif sys == 'interact' then
        local opts = {}
        for i, o in ipairs(options) do opts[i] = { label = o.label, action = function() o.onSelect() end, canInteract = o.canInteract } end
        exports.interact:AddLocalEntityInteraction({ entity = entity, id = id, name = id, distance = radius + 6.0, interactDst = radius, options = opts })
        zones[id] = { kind = 'interacte', entity = entity }
    else
        -- text UI: follows the entity (NPCs walk around)
        local z = { kind = 'text', point = textPoint(id, GetEntityCoords(entity), radius, options), entity = entity }
        zones[id] = z
        CreateThread(function()
            while zones[id] == z and DoesEntityExist(entity) do
                local c = GetEntityCoords(entity)
                if #(c - z.point.coords) > 0.5 then
                    z.point:remove()
                    z.point = textPoint(id, c, radius, options)
                end
                Wait(400)
            end
        end)
    end
end

function Bridge.RemoveEntity(entity, id)
    local z = zones[id]
    if not z then return end
    if z.kind == 'oxe' then pcall(function() exports.ox_target:removeLocalEntity(z.entity, z.names) end)
    elseif z.kind == 'qbe' then pcall(function() exports['qb-target']:RemoveTargetEntity(z.entity) end)
    elseif z.kind == 'interacte' then pcall(function() exports.interact:RemoveLocalEntityInteraction(z.entity, id) end)
    elseif z.kind == 'text' and z.point then z.point:remove() Bridge.HideText() end
    zones[id] = nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, z in pairs(zones) do
        if z.entity then Bridge.RemoveEntity(z.entity, id) else Bridge.RemovePoint(id) end
    end
    -- the text UI lives in another resource, so it would outlive this one
    Bridge.HideText()
end)

-----------------------------------------------------------------
-- VEHICLE KEYS
-----------------------------------------------------------------
function Bridge.GiveKeys(vehicle, plate)
    plate = plate or GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    if running('wasabi_carlock') then
        pcall(function() exports.wasabi_carlock:GiveKey(plate) end)
    elseif running('qs-vehiclekeys') then
        pcall(function() exports['qs-vehiclekeys']:GiveKeys(plate, model, true) end)
    elseif running('MrNewbVehicleKeys') then
        pcall(function() exports.MrNewbVehicleKeys:GiveKeys(vehicle) end)
    elseif running('Renewed-Vehiclekeys') then
        pcall(function() exports['Renewed-Vehiclekeys']:addKey(plate) end)
    elseif running('qbx_vehiclekeys') or running('qb-vehiclekeys') then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    end
    SetVehicleDoorsLocked(vehicle, 1)
end

function Bridge.SetFuel(vehicle, amount)
    amount = amount or 100.0
    SetVehicleFuelLevel(vehicle, amount + 0.0)
    if running('ox_fuel') then
        Entity(vehicle).state:set('fuel', amount + 0.0, true)
    elseif running('LegacyFuel') then
        pcall(function() exports.LegacyFuel:SetFuel(vehicle, amount) end)
    elseif running('cdn-fuel') then
        pcall(function() exports['cdn-fuel']:SetFuel(vehicle, amount) end)
    end
end

function Bridge.GetProps(vehicle) return lib.getVehicleProperties(vehicle) end
function Bridge.SetProps(vehicle, props) if props and next(props) then lib.setVehicleProperties(vehicle, props) end end

-----------------------------------------------------------------
-- EXTERNAL MECHANIC MENU (Config.Workshop.Mode = 'external' | 'both')
-- The player sits in the car in the design bay. Open your mechanic
-- resource here and call done() when they finish. Return true if you
-- opened something; return false and the player gets a prompt to use
-- their mechanic menu normally and press ENTER when finished.
-----------------------------------------------------------------
function Bridge.OpenMechanic(vehicle, done)
    -- Examples (check your resource's docs for the exact call):
    -- if running('jg-mechanic') then exports['jg-mechanic']:openCustoms(...) return true end
    -- if running('nayzeee-tuning') then exports['nayzeee-tuning']:Open(vehicle, done) return true end
    return false
end

-----------------------------------------------------------------
-- CHARACTER EVENTS
-----------------------------------------------------------------
function Bridge.OnLoaded(cb)
    RegisterNetEvent('esx:playerLoaded', function() cb() end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
end

function Bridge.OnUnload(cb)
    RegisterNetEvent('esx:onPlayerLogout', function() cb() end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() cb() end)
end

-----------------------------------------------------------------
-- CREW RADIO (client side)
-- Join returns the channel the player was on, so we can put them
-- back afterwards. SaltyChat is handled in bridge/server.lua.
-----------------------------------------------------------------
local function radioSystem()
    local s = Config.Radio.System
    if s ~= 'auto' then return s end
    if GetResourceState('pma-voice') == 'started' then return 'pma-voice' end
    if GetResourceState('tokovoip_script') == 'started' then return 'tokovoip' end
    return 'none'
end

function Bridge.RadioCurrent()
    if radioSystem() == 'pma-voice' then return LocalPlayer.state.radioChannel or 0 end
    return 0
end

function Bridge.JoinRadio(channel)
    local sys = radioSystem()
    local ok = pcall(function()
        if sys == 'pma-voice' then exports['pma-voice']:setRadioChannel(channel)
        elseif sys == 'tokovoip' then exports.tokovoip_script:addPlayerToRadio(channel)
        elseif sys == 'custom' then
            -- your radio resource here
        else error('no radio') end
    end)
    return ok
end

function Bridge.LeaveRadio(channel, previous)
    local sys = radioSystem()
    pcall(function()
        if sys == 'pma-voice' then
            -- only move them if they are still on the crew channel
            if (LocalPlayer.state.radioChannel or 0) == channel then
                exports['pma-voice']:setRadioChannel(Config.Radio.Restore and previous or 0)
            end
        elseif sys == 'tokovoip' then
            exports.tokovoip_script:removePlayerFromRadio(channel)
            if Config.Radio.Restore and previous and previous ~= 0 then exports.tokovoip_script:addPlayerToRadio(previous) end
        elseif sys == 'custom' then
            -- your radio resource here
        end
    end)
end

-----------------------------------------------------------------
-- DISPATCH (client-side resources)   Config.Dispatch
-- The server picks the system and asks this client to raise it.
-----------------------------------------------------------------
local outgoing = {
    ['ps-dispatch'] = function(d)
        exports['ps-dispatch']:CustomAlert({
            message = d.title, codeName = 'nz_cargo', code = d.code or '10-60', description = d.message,
            icon = 'fas fa-car', priority = 2, coords = d.coords, plate = d.plate, jobs = { 'leo' },
            alertTime = d.blipTime, sprite = d.blip and d.blip.sprite or 225, color = d.blip and d.blip.colour or 1,
            scale = 1.0, length = 3,
        })
    end,
    ['cd_dispatch'] = function(d)
        local c = d.coords
        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = d.jobs, coords = c, title = ('%s - %s'):format(d.code or '10-60', d.title or 'Alert'),
            message = d.message, flash = 0, unique_id = tostring(math.random(0, 9999999)), sound = 1,
            blip = { sprite = d.blip and d.blip.sprite or 225, scale = 1.0, colour = d.blip and d.blip.colour or 1, flashes = true, text = d.title or 'Alert', time = (d.blipTime or 60) * 1000, radius = 0 },
        })
    end,
    ['qs-dispatch'] = function(d)
        TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = d.jobs, callLocation = d.coords, callCode = { code = d.code or '10-60', snippet = d.title },
            message = d.message, flashes = true, image = nil,
            blip = { sprite = d.blip and d.blip.sprite or 225, scale = 1.0, colour = d.blip and d.blip.colour or 1, flashes = true, text = d.title or 'Alert', time = (d.blipTime or 60) * 1000 },
        })
    end,
}

RegisterNetEvent('nz_cargo:dispatchOut', function(system, data)
    local fn = outgoing[system]
    if not fn then return end
    local ok, err = pcall(fn, data)
    if not ok then print(('^1[nayzeee-vehiclecargo] %s alert failed: %s^7'):format(system, tostring(err))) end
end)
