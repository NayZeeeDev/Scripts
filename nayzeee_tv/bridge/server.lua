--[[ Framework / inventory bridge (server) ]]

Bridge = { framework = 'standalone', inventory = 'none' }

local QB, ESX

local function started(res) return GetResourceState(res) == 'started' end

CreateThread(function()
    local fw = Config.Framework
    if fw == 'auto' then
        if started('qbx_core') then fw = 'qbx'
        elseif started('qb-core') then fw = 'qb'
        elseif started('es_extended') then fw = 'esx'
        else fw = 'standalone' end
    end
    Bridge.framework = fw
    if fw == 'qb' then QB = exports['qb-core']:GetCoreObject() end
    if fw == 'esx' then ESX = exports.es_extended:getSharedObject() end

    local inv = Config.Inventory
    if inv == 'auto' then
        if started('ox_inventory') then inv = 'ox_inventory'
        elseif fw == 'qb' or fw == 'qbx' then inv = 'qb'
        elseif fw == 'esx' then inv = 'esx'
        else inv = 'none' end
    end
    Bridge.inventory = inv
    print(('^2[nayzeee_tv]^7 framework: ^5%s^7 · inventory: ^5%s^7'):format(fw, inv))
    TriggerEvent('nztv:bridgeReady')
end)

local function qbPlayer(src)
    if Bridge.framework == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    if Bridge.framework == 'qb' and QB then return QB.Functions.GetPlayer(src) end
end

function Bridge.identifier(src)
    local p = qbPlayer(src)
    if p then return p.PlayerData.citizenid end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x then return x.identifier end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('^license:') then return id end
    end
    return 'src:' .. tostring(src)
end

function Bridge.name(src)
    local p = qbPlayer(src)
    if p and p.PlayerData.charinfo then
        return ('%s %s'):format(p.PlayerData.charinfo.firstname or '', p.PlayerData.charinfo.lastname or '')
    end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x and x.getName then return x.getName() end
    end
    return GetPlayerName(src) or ('Player ' .. src)
end

function Bridge.job(src)
    local p = qbPlayer(src)
    if p and p.PlayerData.job then
        local g = p.PlayerData.job.grade
        return p.PlayerData.job.name, type(g) == 'table' and (g.level or 0) or (g or 0), p.PlayerData.job.label
    end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x and x.job then return x.job.name, x.job.grade or 0, x.job.label end
    end
    return nil, 0
end

function Bridge.gang(src)
    local p = qbPlayer(src)
    if p and p.PlayerData.gang then
        local g = p.PlayerData.gang.grade
        return p.PlayerData.gang.name, type(g) == 'table' and (g.level or 0) or (g or 0)
    end
    return nil, 0
end

function Bridge.isAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    for _, group in ipairs(Config.AdminGroups) do
        if IsPlayerAceAllowed(src, 'group.' .. group) then return true end
        if Bridge.framework == 'qb' and QB and QB.Functions.HasPermission(src, group) then return true end
        if Bridge.framework == 'esx' and ESX then
            local x = ESX.GetPlayerFromId(src)
            if x and x.getGroup and x.getGroup() == group then return true end
        end
    end
    return false
end

-- ─── items ─────────────────────────────────────────────────────
function Bridge.removeItem(src, item, count)
    count = count or 1
    if Bridge.inventory == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(src, item, count) and true or false
    end
    local p = qbPlayer(src)
    if p then return p.Functions.RemoveItem(item, count) and true or false end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x and x.getInventoryItem(item) and x.getInventoryItem(item).count >= count then
            x.removeInventoryItem(item, count)
            return true
        end
        return false
    end
    return true -- standalone: items are not tracked
end

function Bridge.addItem(src, item, count)
    count = count or 1
    if Bridge.inventory == 'ox_inventory' then
        return exports.ox_inventory:AddItem(src, item, count) and true or false
    end
    local p = qbPlayer(src)
    if p then return p.Functions.AddItem(item, count) and true or false end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        if x then x.addInventoryItem(item, count) return true end
    end
    return true
end

function Bridge.hasItem(src, item)
    if Bridge.inventory == 'ox_inventory' then
        return (exports.ox_inventory:Search(src, 'count', item) or 0) > 0
    end
    local p = qbPlayer(src)
    if p then
        local i = p.Functions.GetItemByName(item)
        return i ~= nil and (i.amount or i.count or 0) > 0
    end
    if Bridge.framework == 'esx' and ESX then
        local x = ESX.GetPlayerFromId(src)
        local i = x and x.getInventoryItem(item)
        return i ~= nil and i.count > 0
    end
    return true
end

--- Register a usable item. ox_inventory items call the `useItem` export instead (see README).
function Bridge.registerUsable(item, cb)
    if Bridge.inventory == 'ox_inventory' then return end
    if Bridge.framework == 'qbx' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    elseif Bridge.framework == 'qb' and QB then
        QB.Functions.CreateUseableItem(item, function(src) cb(src) end)
    elseif Bridge.framework == 'esx' and ESX then
        ESX.RegisterUsableItem(item, function(src) cb(src) end)
    end
end

function Bridge.notify(src, msg, kind, title)
    TriggerClientEvent('nztv:notify', src, msg, kind or 'info', title)
end
