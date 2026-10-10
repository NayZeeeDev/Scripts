--[[
    NAYZEEE BILLING - Client Bridge
    Framework player data, notifications and target abstraction.
]]

ClientBridge = { job = nil, loaded = false }

local function setJob(name)
    local changed = ClientBridge.job ~= name
    ClientBridge.job = name
    if changed then TriggerEvent('nayzeee-billing:client:jobChanged', name) end
end

local function fetchPlayerData()
    local fw = Shared.GetFramework()
    if fw == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        local data = ESX.GetPlayerData()
        return data and data.job and data.job.name, ESX.IsPlayerLoaded and ESX.IsPlayerLoaded()
    elseif fw == 'qbox' then
        local data = exports.qbx_core:GetPlayerData()
        return data and data.job and data.job.name, data and data.citizenid ~= nil
    elseif fw == 'qbcore' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local data = QBCore.Functions.GetPlayerData()
        return data and data.job and data.job.name, data and data.citizenid ~= nil
    end
    return nil, true
end

function ClientBridge.Init()
    CreateThread(function()
        local tries = 0
        while true do
            local job, loaded = fetchPlayerData()
            if loaded then
                ClientBridge.loaded = true
                setJob(job)
                TriggerEvent('nayzeee-billing:client:playerReady')
                return
            end
            tries = tries + 1
            Wait(tries < 50 and 500 or 2000)
        end
    end)
end

-- ESX
RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    ClientBridge.loaded = true
    setJob(xPlayer and xPlayer.job and xPlayer.job.name)
    TriggerEvent('nayzeee-billing:client:playerReady')
end)
RegisterNetEvent('esx:setJob', function(job) setJob(job and job.name) end)

-- QBCore / Qbox
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SetTimeout(500, function()
        local job = fetchPlayerData()
        ClientBridge.loaded = true
        setJob(job)
        TriggerEvent('nayzeee-billing:client:playerReady')
    end)
end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) setJob(job and job.name) end)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() ClientBridge.loaded = false end)
RegisterNetEvent('esx:onPlayerLogout', function() ClientBridge.loaded = false end)

-- ███╗   ██╗ ██████╗ ████████╗██╗███████╗██╗   ██╗
-- ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔════╝╚██╗ ██╔╝
-- ██╔██╗ ██║██║   ██║   ██║   ██║█████╗   ╚████╔╝
-- ██║╚██╗██║██║   ██║   ██║   ██║██╔══╝    ╚██╔╝
-- ██║ ╚████║╚██████╔╝   ██║   ██║██║        ██║
-- ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝╚═╝        ╚═╝

function ClientBridge.Notify(title, message, notifType)
    notifType = notifType or 'info'
    local system = Config.Notifications.System or 'ox_lib'

    if system == 'ox_lib' then
        lib.notify({ title = title, description = message, type = notifType == 'warning' and 'warning' or notifType, duration = 5000 })
    elseif system == 'esx' then
        exports['es_extended']:getSharedObject().ShowNotification(message)
    elseif system == 'qb' then
        exports['qb-core']:GetCoreObject().Functions.Notify(message, notifType == 'info' and 'primary' or notifType, 5000)
    elseif system == 'okokNotify' then
        exports['okokNotify']:Alert(title, message, 5000, notifType)
    elseif system == 'mythic' then
        exports['mythic_notify']:DoHudText(notifType == 'info' and 'inform' or notifType, message)
    elseif system == 'custom' and Config.Notifications.CustomFunction then
        Config.Notifications.CustomFunction(title, message, notifType)
    else
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

-- options = { { name, label, icon, canInteract = fn, onSelect = fn } }
function ClientBridge.AddSphereZone(name, coords, radius, options, debug)
    local sys = targetSystem()
    if sys == 'ox' then
        local oxOptions = {}
        for _, opt in ipairs(options) do
            oxOptions[#oxOptions + 1] = {
                name = opt.name, label = opt.label, icon = opt.icon, distance = radius + 1.0,
                canInteract = opt.canInteract, onSelect = opt.onSelect,
            }
        end
        return { sys = 'ox', id = exports.ox_target:addSphereZone({
            coords = coords, radius = radius, debug = debug, options = oxOptions,
        }) }
    elseif sys == 'qb' then
        local qbOptions = {}
        for _, opt in ipairs(options) do
            qbOptions[#qbOptions + 1] = {
                type = 'client', label = opt.label, icon = opt.icon,
                canInteract = opt.canInteract, action = opt.onSelect,
            }
        end
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, debugPoly = debug, useZ = true },
            { options = qbOptions, distance = radius + 1.0 })
        return { sys = 'qb', id = name }
    end
    return nil
end

function ClientBridge.RemoveZone(handle)
    if not handle then return end
    pcall(function()
        if handle.sys == 'ox' then
            exports.ox_target:removeZone(handle.id)
        elseif handle.sys == 'qb' then
            exports['qb-target']:RemoveZone(handle.id)
        end
    end)
end

function ClientBridge.HasTarget()
    return targetSystem() ~= nil
end
