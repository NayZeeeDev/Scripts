--[[
    nz_cpuchip - server

    Registers `Config.ItemName` as a usable item for qb-core / es_extended.
    ox_inventory does not need this: it calls the client export declared in its
    items.lua (client = { export = 'nz_cpuchip.cpu_chip' }).

    The registration runs when this resource starts and again whenever the
    framework resource (re)starts, so ensure order in server.cfg does not matter
    and a `restart qb-core` / `restart es_extended` does not lose the item.
]]

local FRAMEWORK_RESOURCES = { ['qb-core'] = 'qb-core', ['es_extended'] = 'esx', ['ox_inventory'] = 'ox_inventory' }

local function detectFramework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('ox_inventory') == 'started' then return 'ox_inventory' end
    if GetResourceState('qb-core') == 'started' then return 'qb-core' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'none'
end

local function onUse(source)
    TriggerClientEvent('nz_cpuchip:client:inspect', source)
end

local function register(fw)
    if fw == 'qb-core' then
        if GetResourceState('qb-core') ~= 'started' then return false end
        local ok, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if not ok or not QBCore then return false end
        QBCore.Functions.CreateUseableItem(Config.ItemName, onUse)
        return true
    elseif fw == 'esx' then
        if GetResourceState('es_extended') ~= 'started' then return false end
        local ok, ESX = pcall(function() return exports['es_extended']:getSharedObject() end)
        if not ok or not ESX then return false end
        ESX.RegisterUsableItem(Config.ItemName, onUse)
        return true
    end
    return fw == 'ox_inventory' -- nothing to do server side
end

local function hook(reason)
    local fw = detectFramework()
    local ok = register(fw)
    print(('[nz_cpuchip] %s - framework hook: %s%s'):format(reason, fw, (fw ~= 'none' and not ok) and ' (framework not ready, will retry on its start)' or ''))
end

CreateThread(function() hook('loaded') end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then return end
    if FRAMEWORK_RESOURCES[res] then
        Wait(1000) -- let the framework finish initialising its exports
        hook(('%s started'):format(res))
    end
end)
