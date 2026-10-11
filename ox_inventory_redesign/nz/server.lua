--[[
    NZ Inventory UI - server
    Supplies the player card (name, bank, job) and optional character names
    for the give menu. Only runs when a client asks; nothing ticks.
]]

if not lib then return end

local config = NZConfig
local framework = GetConvar('inventory:framework', 'esx')

-- call obj:fn(...) or obj.fn(...), whichever the framework object expects
local function call(obj, fn, ...)
    if type(obj) ~= 'table' or not obj[fn] then return end

    local ok, value = pcall(obj[fn], obj, ...)

    if ok and value ~= nil then return value end

    ok, value = pcall(obj[fn], ...)

    if ok then return value end
end

local getters = {}

local ESX
getters.esx = function(source)
    ESX = ESX or exports.es_extended:getSharedObject()
    local player = ESX.GetPlayerFromId(source)

    if not player then return end

    local bank = player.getAccount('bank')
    local job = player.getJob and player.getJob() or player.job

    return {
        name = player.getName(),
        bank = bank and bank.money,
        job = job and job.label,
        grade = job and job.grade_label ~= job.label and job.grade_label or nil,
    }
end

local function fromQbPlayerData(data)
    if not data then return end

    local char = data.charinfo or {}
    local job = data.job or {}

    return {
        name = char.firstname and ('%s %s'):format(char.firstname, char.lastname or ''),
        bank = data.money and data.money.bank,
        job = job.label,
        grade = job.grade and job.grade.name,
    }
end

getters.qbx = function(source)
    local player = exports.qbx_core:GetPlayer(source)
    return player and fromQbPlayerData(player.PlayerData)
end

local QBCore
getters.qb = function(source)
    QBCore = QBCore or exports['qb-core']:GetCoreObject()
    local player = QBCore.Functions.GetPlayer(source)
    return player and fromQbPlayerData(player.PlayerData)
end

getters.ox = function(source)
    local player = exports.ox_core:GetPlayer(source)

    if not player then return end

    local first = call(player, 'get', 'firstName') or player.firstName
    local last = call(player, 'get', 'lastName') or player.lastName
    local info = { name = first and ('%s %s'):format(first, last or '') or player.username }

    local account = call(player, 'getAccount')

    if account then
        info.bank = call(account, 'get', 'balance') or account.balance
    end

    local group = call(player, 'get', 'activeGroup')

    if group then
        local ok, data = pcall(function() return exports.ox_core:GetGroup(group) end)
        local grade = call(player, 'getGroup', group)

        info.job = ok and data and data.label or group

        if ok and data and grade and data.grades then
            local g = data.grades[grade]
            info.grade = type(g) == 'table' and g.label or g
        end
    end

    return info
end

getters.nd = function(source)
    local player = exports.ND_Core:getPlayer(source)

    if not player then return end

    local jobInfo = player.jobInfo or {}

    return {
        name = player.fullname or (player.firstname and ('%s %s'):format(player.firstname, player.lastname or '')),
        bank = player.bank,
        job = jobInfo.label or player.job,
        grade = jobInfo.rankName,
    }
end

local function getPlayerInfo(source)
    local info

    if config.GetPlayerInfo then
        local ok, result = pcall(config.GetPlayerInfo, source)
        if ok then info = result end
    end

    if not info and getters[framework] then
        local ok, result = pcall(getters[framework], source)

        if ok then
            info = result
        else
            lib.print.verbose(('nz playerInfo (%s) failed: %s'):format(framework, result))
        end
    end

    info = info or {}

    if type(info.name) ~= 'string' or not info.name:find('%S') then
        info.name = GetPlayerName(source)
    end

    if type(info.bank) ~= 'number' then info.bank = tonumber(info.bank) end
    if not config.PlayerCard.showBank then info.bank = nil end
    if not config.PlayerCard.showJob then info.job, info.grade = nil, nil end

    return info
end

lib.callback.register('nz_inventory:playerInfo', function(source)
    if not config.PlayerCard.enabled then return {} end
    return getPlayerInfo(source)
end)

-- Character names for the give menu. Only answers for players that are really
-- next to the requester so names can't be harvested from across the map.
lib.callback.register('nz_inventory:names', function(source, ids)
    if config.GiveMenu.names ~= 'character' or type(ids) ~= 'table' then return {} end

    local origin = GetEntityCoords(GetPlayerPed(source))
    local names = {}

    for i = 1, math.min(#ids, 16) do
        local id = tonumber(ids[i])
        local ped = id and GetPlayerPed(id)

        if ped and ped ~= 0 and #(GetEntityCoords(ped) - origin) <= config.GiveMenu.distance + 5.0 then
            names[tostring(id)] = getPlayerInfo(id).name
        end
    end

    return names
end)
