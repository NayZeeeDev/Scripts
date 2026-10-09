--[[
    nz_cpuchip - server

    Registers `Config.ItemName` as a usable item for qb-core / es_extended.
    ox_inventory does not need this: it calls the client export declared in its
    items.lua (client = { export = 'nz_cpuchip.cpu_chip' }).
]]

local function framework()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('ox_inventory') == 'started' then return 'ox_inventory' end
    if GetResourceState('qb-core') == 'started' then return 'qb-core' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'none'
end

CreateThread(function()
    local fw = framework()
    if fw == 'qb-core' then
        local QBCore = exports['qb-core']:GetCoreObject()
        QBCore.Functions.CreateUseableItem(Config.ItemName, function(source)
            TriggerClientEvent('nz_cpuchip:client:inspect', source)
        end)
    elseif fw == 'esx' then
        local ESX = exports['es_extended']:getSharedObject()
        ESX.RegisterUsableItem(Config.ItemName, function(source)
            TriggerClientEvent('nz_cpuchip:client:inspect', source)
        end)
    end
    print(('[nz_cpuchip] loaded (framework hook: %s)'):format(fw))
end)
