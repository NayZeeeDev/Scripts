--[[
    NAYZEEE BILLING - Framework Bridge (server)
    ESX / QBCore / Qbox abstraction. Everything framework-specific lives here.
]]

Bridge = {}

local FW = nil
local fwName = nil

local function Framework()
    if fwName then return fwName, FW end
    fwName = Shared.GetFramework()
    if fwName == 'esx' then
        FW = exports['es_extended']:getSharedObject()
    elseif fwName == 'qbcore' then
        FW = exports['qb-core']:GetCoreObject()
    elseif fwName == 'qbox' then
        -- Qbox keeps the QB core object for compatibility, but prefer its exports where they exist
        FW = GetResourceState('qb-core') == 'started' and exports['qb-core']:GetCoreObject() or nil
    end
    return fwName, FW
end

-- ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗
-- ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
-- ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
-- ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
-- ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝

function Bridge.GetPlayer(source)
    local fw, core = Framework()
    source = tonumber(source)
    if not source then return nil end
    if fw == 'esx' then
        return core.GetPlayerFromId(source)
    elseif fw == 'qbox' then
        return exports.qbx_core:GetPlayer(source)
    elseif fw == 'qbcore' then
        return core.Functions.GetPlayer(source)
    end
    return nil
end

function Bridge.GetIdentifier(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end
    if fwName == 'esx' then
        return player.identifier
    end
    return player.PlayerData.citizenid
end

function Bridge.GetName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return 'Unknown' end
    if fwName == 'esx' then
        return player.getName() or GetPlayerName(source) or 'Unknown'
    end
    local c = player.PlayerData.charinfo or {}
    if c.firstname then
        return (c.firstname .. ' ' .. (c.lastname or ''))
    end
    return GetPlayerName(source) or 'Unknown'
end

-- Returns { name, label, grade, gradeLabel, isBoss, onDuty }
function Bridge.GetJob(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end

    if fwName == 'esx' then
        local job = player.job or {}
        return {
            name = job.name,
            label = job.label or job.name,
            grade = tonumber(job.grade) or 0,
            gradeLabel = job.grade_label or job.grade_name or '',
            isBoss = job.grade_name == 'boss',
            onDuty = true,
        }
    end

    local job = player.PlayerData.job or {}
    local grade = job.grade or {}
    return {
        name = job.name,
        label = job.label or job.name,
        grade = tonumber(type(grade) == 'table' and grade.level or grade) or 0,
        gradeLabel = type(grade) == 'table' and (grade.name or '') or '',
        isBoss = job.isboss == true,
        onDuty = job.onduty ~= false,
    }
end

function Bridge.GetMoney(source, account)
    local player = Bridge.GetPlayer(source)
    if not player then return 0 end
    if account == 'bank' and Banking.HasPersonal() then
        return Banking.PersonalBalance(Bridge.GetIdentifier(source)) or 0
    end
    if fwName == 'esx' then
        local acc = player.getAccount(account == 'cash' and 'money' or account)
        return acc and tonumber(acc.money) or 0
    end
    return tonumber(player.PlayerData.money[account]) or 0
end

function Bridge.RemoveMoney(source, account, amount, reason)
    local player = Bridge.GetPlayer(source)
    if not player then return false end
    amount = Shared.Round(amount)
    if amount <= 0 then return true end
    if account == 'bank' and Banking.HasPersonal() then
        return Banking.RemovePersonal(Bridge.GetIdentifier(source), amount, reason)
    end

    if fwName == 'esx' then
        local accName = account == 'cash' and 'money' or account
        local acc = player.getAccount(accName)
        if not acc or (tonumber(acc.money) or 0) < amount then return false end
        player.removeAccountMoney(accName, amount, reason)
        return true
    end
    return player.Functions.RemoveMoney(account, amount, reason) == true
end

function Bridge.AddMoney(source, account, amount, reason)
    local player = Bridge.GetPlayer(source)
    if not player then return false end
    amount = Shared.Round(amount)
    if amount <= 0 then return true end
    if account == 'bank' and Banking.HasPersonal() then
        return Banking.AddPersonal(Bridge.GetIdentifier(source), amount, reason)
    end

    if fwName == 'esx' then
        player.addAccountMoney(account == 'cash' and 'money' or account, amount, reason)
        return true
    end
    return player.Functions.AddMoney(account, amount, reason) ~= false
end

function Bridge.GetSourceFromIdentifier(identifier)
    if not identifier then return nil end
    local fw, core = Framework()
    if fw == 'esx' then
        local xPlayer = core.GetPlayerFromIdentifier(identifier)
        return xPlayer and xPlayer.source or nil
    elseif fw == 'qbox' then
        local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
        return player and player.PlayerData.source or nil
    elseif fw == 'qbcore' then
        local player = core.Functions.GetPlayerByCitizenId(identifier)
        return player and player.PlayerData.source or nil
    end
    return nil
end

--  █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
-- ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
-- ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
-- ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
-- ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
-- ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

function Bridge.IsAdmin(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if Config.AdminAce and IsPlayerAceAllowed(source, Config.AdminAce) then return true end

    local fw, core = Framework()
    if fw == 'esx' then
        local player = Bridge.GetPlayer(source)
        local group = player and player.getGroup and player.getGroup() or 'user'
        return Shared.TableContains(Config.AdminGroups, group)
    end

    for _, group in ipairs(Config.AdminGroups) do
        if IsPlayerAceAllowed(source, 'group.' .. group) then return true end
        if fw == 'qbcore' and core.Functions.HasPermission(source, group) then return true end
    end
    return false
end

--  ██████╗ ███████╗███████╗██╗     ██╗███╗   ██╗███████╗
-- ██╔═══██╗██╔════╝██╔════╝██║     ██║████╗  ██║██╔════╝
-- ██║   ██║█████╗  █████╗  ██║     ██║██╔██╗ ██║█████╗
-- ██║   ██║██╔══╝  ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝
-- ╚██████╔╝██║     ██║     ███████╗██║██║ ╚████║███████╗
--  ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝

-- Search characters in the database (online or not). Returns { identifier, name }
function Bridge.SearchCharacters(query, limit)
    query = Shared.Sanitize(query, 40)
    if #query < 2 then return {} end
    limit = limit or 10
    local like = '%' .. query .. '%'
    local results = {}

    if fwName == 'esx' then
        local rows = MySQL.query.await(
            "SELECT identifier, firstname, lastname FROM users WHERE identifier = ? OR CONCAT(firstname, ' ', lastname) LIKE ? LIMIT ?",
            { query, like, limit }) or {}
        for _, row in ipairs(rows) do
            results[#results + 1] = { identifier = row.identifier, name = ((row.firstname or '') .. ' ' .. (row.lastname or '')) }
        end
    elseif fwName == 'qbcore' or fwName == 'qbox' then
        local rows = MySQL.query.await(
            'SELECT citizenid, charinfo FROM players WHERE citizenid = ? OR charinfo LIKE ? LIMIT ?',
            { query, like, limit * 2 }) or {}
        local lower = query:lower()
        for _, row in ipairs(rows) do
            local ok, info = pcall(json.decode, row.charinfo or '{}')
            info = ok and info or {}
            local name = ((info.firstname or '') .. ' ' .. (info.lastname or ''))
            if row.citizenid == query or name:lower():find(lower, 1, true) then
                results[#results + 1] = { identifier = row.citizenid, name = name }
                if #results >= limit then break end
            end
        end
    end

    return results
end

function Bridge.GetCharacterName(identifier)
    local src = Bridge.GetSourceFromIdentifier(identifier)
    if src then return Bridge.GetName(src) end

    if fwName == 'esx' then
        local row = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
        return row and ((row.firstname or '') .. ' ' .. (row.lastname or '')) or nil
    elseif fwName == 'qbcore' or fwName == 'qbox' then
        local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
        if not row then return nil end
        local ok, info = pcall(json.decode, row.charinfo or '{}')
        info = ok and info or {}
        return ((info.firstname or '') .. ' ' .. (info.lastname or ''))
    end
    return nil
end

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

function Bridge.RegisterUsableItem(name, cb)
    local fw, core = Framework()
    if fw == 'esx' then
        core.RegisterUsableItem(name, function(source, _, item)
            cb(source, item and (item.metadata or item.info) or {})
        end)
    elseif fw == 'qbox' then
        exports.qbx_core:CreateUseableItem(name, function(source, item)
            cb(source, item and (item.metadata or item.info) or {})
        end)
    elseif fw == 'qbcore' then
        core.Functions.CreateUseableItem(name, function(source, item)
            cb(source, item and (item.info or item.metadata) or {})
        end)
    end
end

-- ███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
-- ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
-- █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
-- ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
-- ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
-- ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

-- cb(source) whenever a character finishes loading
function Bridge.OnPlayerLoaded(cb)
    AddEventHandler('esx:playerLoaded', function(playerId)
        cb(tonumber(playerId))
    end)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = player and player.PlayerData and player.PlayerData.source
        if src then cb(src) end
    end)
end

CreateThread(function()
    Wait(0)
    Framework()
    print(('^2[NAYZEEE-BILLING]^7 Framework: ^5%s^7'):format(fwName))
end)
