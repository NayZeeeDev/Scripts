-- HUD server side: stress (qb-hud compatible events). Kept in a local table so it can't
-- collide with the squads module's server globals.

local S = Config.Stress
local framework = 'standalone'
local QBCore
local memory = {} -- standalone stress per player

local function detect()
    local f = Config.Framework
    if f == 'qbcore' then f = 'qb' end
    if f ~= 'auto' then return f end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

CreateThread(function()
    framework = detect()
    if framework == 'qb' then QBCore = exports['qb-core']:GetCoreObject() end
end)

local function getPlayer(src)
    if framework == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if framework == 'qb' and QBCore then return QBCore.Functions.GetPlayer(src) end
end

local function jobWhitelisted(player)
    local job = player and player.PlayerData and player.PlayerData.job
    return job and (S.whitelistedJobs[job.name] or (job.type and S.whitelistedJobs[job.type]))
end

local function changeStress(src, delta)
    if not S.enabled then return end
    if framework == 'qb' or framework == 'qbx' then
        local player = getPlayer(src)
        if not player then return end
        if delta > 0 and jobWhitelisted(player) then return end
        local md = player.PlayerData.metadata or {}
        local value = math.max(0, math.min(100, (tonumber(md.stress) or 0) + delta))
        if player.Functions and player.Functions.SetMetaData then
            player.Functions.SetMetaData('stress', value)
        elseif player.SetMetaData then
            player.SetMetaData('stress', value)
        end
        TriggerClientEvent('hud:client:UpdateStress', src, value)
    elseif framework == 'esx' then
        if GetResourceState('esx_status') ~= 'started' then return end
        -- esx_status runs 0 - 1,000,000
        TriggerClientEvent(delta > 0 and 'esx_status:add' or 'esx_status:remove', src, 'stress', math.abs(delta) * 10000)
    else
        local value = math.max(0, math.min(100, (memory[src] or 0) + delta))
        memory[src] = value
        TriggerClientEvent('hud:client:UpdateStress', src, value)
    end
end

RegisterNetEvent('hud:server:GainStress', function(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    changeStress(source, math.min(100, math.floor(amount)))
end)

RegisterNetEvent('hud:server:RelieveStress', function(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    changeStress(source, -math.min(100, math.floor(amount)))
end)

AddEventHandler('playerDropped', function() memory[source] = nil end)

-- server-side scripts can use these directly
exports('GainStress', function(src, amount) changeStress(src, math.abs(tonumber(amount) or 0)) end)
exports('RelieveStress', function(src, amount) changeStress(src, -math.abs(tonumber(amount) or 0)) end)
