Bridge = {}

lib.locale(Config.Locale)

local framework = Config.Framework
if framework == 'qbox' then framework = 'qbx' end
if framework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then framework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then framework = 'qb'
    elseif GetResourceState('es_extended') == 'started' then framework = 'esx'
    else framework = 'standalone' end
end
Bridge.Framework = framework

local QB, ESX
if framework == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
elseif framework == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

function Bridge.IsLoaded()
    if framework == 'qb' or framework == 'qbx' then
        return LocalPlayer.state.isLoggedIn == true
    elseif framework == 'esx' then
        return ESX.IsPlayerLoaded()
    end
    return NetworkIsPlayerActive(cache.playerId) and DoesEntityExist(cache.ped)
end

function Bridge.Notify(msg, kind)
    kind = kind or 'inform'
    if Config.Notify == 'nayzeee' then
        exports['nayzeee-notify']:Notify(msg, kind, 5000)
    elseif Config.Notify == 'qb' and QB then
        QB.Functions.Notify(msg, kind == 'inform' and 'primary' or kind)
    elseif Config.Notify == 'esx' and ESX then
        ESX.ShowNotification(msg)
    else
        lib.notify({ title = 'Admin Jail', description = msg, type = kind })
    end
end

RegisterNetEvent(AJ.Event('client:notify'), Bridge.Notify)

--[[ Lifecycle hooks — client/main.lua fills these in ]]

Bridge.onLoaded = function() end   -- character loaded (before or after a spawn selector)
Bridge.onSpawned = function() end  -- ped (re)spawned somewhere (spawnmanager / framework / death respawn)
Bridge.onUnloaded = function() end -- logged out / character switch

if framework == 'qb' or framework == 'qbx' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() Bridge.onLoaded() end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() Bridge.onUnloaded() end)
elseif framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function() Bridge.onLoaded() end)
    RegisterNetEvent('esx:onPlayerLogout', function() Bridge.onUnloaded() end)
    AddEventHandler('esx:onPlayerSpawn', function() Bridge.onSpawned() end)
end

AddEventHandler('playerSpawned', function() Bridge.onSpawned() end)
