--[[
    NAYZEEE BILLING - Client bridge
    Editable. Player job tracking, notifications and target zones.
]]

ClientBridge = { job = nil, loaded = false }

local function setJob(name)
    local changed = ClientBridge.job ~= name
    ClientBridge.job = name
    if changed then TriggerEvent('nayzeee-billing:client:jobChanged', name) end
end

local function fetch()
    local fw = Shared.GetFramework()
    if fw == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local d = ESX.GetPlayerData()
        return d and d.job and d.job.name, ESX.IsPlayerLoaded and ESX.IsPlayerLoaded()
    elseif fw == 'qbox' then
        local d = exports.qbx_core:GetPlayerData()
        return d and d.job and d.job.name, d and d.citizenid ~= nil
    elseif fw == 'qbcore' then
        local d = exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
        return d and d.job and d.job.name, d and d.citizenid ~= nil
    end
    return nil, true
end

local function ready()
    ClientBridge.loaded = true
    TriggerEvent('nayzeee-billing:client:playerReady')
end

function ClientBridge.Init()
    CreateThread(function()
        local tries = 0
        while not ClientBridge.loaded do
            local job, loaded = fetch()
            if loaded then setJob(job) ready() return end
            tries = tries + 1
            Wait(tries < 60 and 500 or 2000)
        end
    end)
end

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    setJob(xPlayer and xPlayer.job and xPlayer.job.name)
    ready()
end)
RegisterNetEvent('esx:setJob', function(job) setJob(job and job.name) end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SetTimeout(500, function() local job = fetch() setJob(job) ready() end)
end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) setJob(job and job.name) end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() ClientBridge.loaded = false end)

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

-- Every billing notification (server, UI and placement) goes through here
local ESXObj, QBObj
local function notifySystem()
    local system = Config.Notify.System or 'auto'
    if system ~= 'auto' then return system end
    if GetResourceState('ox_lib') == 'started' then return 'ox_lib' end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'chat'
end

function ClientBridge.Notify(title, message, kind)
    kind = kind or 'info'
    title = title or Config.UI.Title
    message = tostring(message or '')
    local duration = Config.Notify.Duration or 5000
    local system = notifySystem()
    local ok, err = pcall(function()
        if system == 'ox_lib' then
            lib.notify({ title = title, description = message, type = kind, duration = duration, position = Config.Notify.Position })
        elseif system == 'esx' then
            ESXObj = ESXObj or exports['es_extended']:getSharedObject()
            ESXObj.ShowNotification(message, kind == 'warning' and 'info' or kind, duration, title)
        elseif system == 'qb' then
            QBObj = QBObj or exports['qb-core']:GetCoreObject()
            QBObj.Functions.Notify(message, kind == 'info' and 'primary' or kind, duration)
        elseif system == 'qbx' then
            exports.qbx_core:Notify(message, kind == 'info' and 'inform' or kind, duration, title)
        elseif system == 'okokNotify' then
            exports['okokNotify']:Alert(title, message, duration, kind)
        elseif system == 'mythic' then
            exports['mythic_notify']:DoHudText(kind == 'info' and 'inform' or kind, message)
        elseif system == 'custom' and Config.Notify.Custom then
            Config.Notify.Custom(title, message, kind)
        else
            TriggerEvent('chat:addMessage', { args = { '[' .. title .. ']', message } })
        end
    end)
    if not ok then
        print(('^1[NAYZEEE-BILLING]^7 Notify (%s) failed: %s'):format(system, err))
        TriggerEvent('chat:addMessage', { args = { '[' .. title .. ']', message } })
    end
end

-- ████████╗ █████╗ ██████╗  ██████╗ ███████╗████████╗
-- ╚══██╔══╝██╔══██╗██╔══██╗██╔════╝ ██╔════╝╚══██╔══╝
--    ██║   ███████║██████╔╝██║  ███╗█████╗     ██║
--    ██║   ██╔══██║██╔══██╗██║   ██║██╔══╝     ██║
--    ██║   ██║  ██║██║  ██║╚██████╔╝███████╗   ██║
--    ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝

local function targetSystem()
    if GetResourceState('ox_target') == 'started' then return 'ox' end
    if GetResourceState('qb-target') == 'started' then return 'qb' end
    return nil
end

function ClientBridge.HasTarget() return targetSystem() ~= nil end

-- options = { { name, label, icon, canInteract, onSelect } }
function ClientBridge.AddSphereZone(name, coords, radius, options, debug)
    local sys = targetSystem()
    if sys == 'ox' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = { name = o.name, label = o.label, icon = o.icon, distance = radius + 1.0, canInteract = o.canInteract, onSelect = o.onSelect }
        end
        return { sys = 'ox', id = exports.ox_target:addSphereZone({ coords = coords, radius = radius, debug = debug, options = list }) }
    elseif sys == 'qb' then
        local list = {}
        for _, o in ipairs(options) do
            list[#list + 1] = { type = 'client', label = o.label, icon = o.icon, canInteract = o.canInteract, action = o.onSelect }
        end
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = debug, useZ = true }, { options = list, distance = radius + 1.0 })
        return { sys = 'qb', id = name }
    end
    return nil
end

function ClientBridge.RemoveZone(handle)
    if not handle then return end
    pcall(function()
        if handle.sys == 'ox' then exports.ox_target:removeZone(handle.id)
        elseif handle.sys == 'qb' then exports['qb-target']:RemoveZone(handle.id) end
    end)
end
