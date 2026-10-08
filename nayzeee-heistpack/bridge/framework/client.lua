--[[ Framework bridge (client) ]]

FW = {}

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'none'
end

FW.name = detect()

local QB, ESX
if FW.name == 'qb' then
    QB = exports['qb-core']:GetCoreObject()
elseif FW.name == 'esx' then
    ESX = exports.es_extended:getSharedObject()
end

function FW.isLoaded()
    if FW.name == 'esx' then return ESX.IsPlayerLoaded() end
    if FW.name == 'qbx' or FW.name == 'qb' then return LocalPlayer.state.isLoggedIn == true end
    return NetworkIsPlayerActive(PlayerId())
end

function FW.job()
    if FW.name == 'esx' then
        local pd = ESX.GetPlayerData()
        return { name = pd.job and pd.job.name or 'unemployed' }
    elseif FW.name == 'qbx' then
        local pd = exports.qbx_core:GetPlayerData() or {}
        return { name = pd.job and pd.job.name or 'unemployed', gang = pd.gang and pd.gang.name }
    elseif FW.name == 'qb' then
        local pd = QB.Functions.GetPlayerData() or {}
        return { name = pd.job and pd.job.name or 'unemployed', gang = pd.gang and pd.gang.name }
    end
    return { name = 'unemployed' }
end

function FW.isMale()
    return GetEntityModel(cache.ped) ~= joaat('mp_f_freemode_01')
end

function FW.onLoaded(cb)
    if FW.name == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function() cb() end)
    else
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end
end

function FW.onUnloaded(cb)
    if FW.name == 'esx' then
        RegisterNetEvent('esx:onPlayerLogout', function() cb() end)
    else
        RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() cb() end)
    end
end

--[[ Vehicle keys + fuel ]]
local function keysSystem()
    if Config.VehicleKeys ~= 'auto' then return Config.VehicleKeys end
    if GetResourceState('qbx_vehiclekeys') == 'started' then return 'qbx' end
    if GetResourceState('qb-vehiclekeys') == 'started' then return 'qb' end
    if GetResourceState('wasabi_carlock') == 'started' then return 'wasabi' end
    if GetResourceState('MrNewbVehicleKeys') == 'started' then return 'mk' end
    if GetResourceState('Renewed-Vehiclekeys') == 'started' then return 'renewed' end
    return 'none'
end

local KEYS = keysSystem()

function FW.giveKeys(vehicle)
    if not vehicle or vehicle == 0 then return end
    local plate = GetVehicleNumberPlateText(vehicle)
    pcall(function()
        if KEYS == 'qb' then
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        elseif KEYS == 'qbx' then
            TriggerServerEvent('nzh:keys:qbx', VehToNet(vehicle))
        elseif KEYS == 'wasabi' then
            exports.wasabi_carlock:GiveKey(plate)
        elseif KEYS == 'mk' then
            exports.MrNewbVehicleKeys:GiveKeys(vehicle)
        elseif KEYS == 'renewed' then
            exports['Renewed-Vehiclekeys']:addKey(plate)
        end
    end)
    SetVehicleDoorsLocked(vehicle, 1)
end

function FW.setFuel(vehicle, value)
    if GetResourceState('ox_fuel') == 'started' then
        Entity(vehicle).state.fuel = value
    elseif GetResourceState('LegacyFuel') == 'started' then
        pcall(function() exports.LegacyFuel:SetFuel(vehicle, value) end)
    elseif GetResourceState('cdn-fuel') == 'started' then
        pcall(function() exports['cdn-fuel']:SetFuel(vehicle, value) end)
    elseif GetResourceState('ps-fuel') == 'started' then
        pcall(function() exports['ps-fuel']:SetFuel(vehicle, value) end)
    end
    SetVehicleFuelLevel(vehicle, value + 0.0)
end
