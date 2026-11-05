--[[
    NAYZEEE BILLING - QBCore / Qbox bridge (server)
    Editable: everything QBCore / Qbox specific lives in this file.
]]

local fw = Shared.GetFramework()
if fw ~= 'qbcore' and fw ~= 'qbox' then return end

local QBX = fw == 'qbox'
local QBCore = (not QBX or GetResourceState('qb-core') == 'started') and exports['qb-core']:GetCoreObject() or nil
Framework = { Name = fw }

function Framework.GetPlayer(source)
    source = tonumber(source)
    if not source then return nil end
    if QBX then return exports.qbx_core:GetPlayer(source) end
    return QBCore.Functions.GetPlayer(source)
end

function Framework.GetIdentifier(source)
    local p = Framework.GetPlayer(source)
    return p and p.PlayerData.citizenid or nil
end

function Framework.GetName(source)
    local p = Framework.GetPlayer(source)
    local c = p and p.PlayerData.charinfo
    if c and c.firstname then return c.firstname .. ' ' .. (c.lastname or '') end
    return GetPlayerName(source) or 'Unknown'
end

function Framework.GetJob(source)
    local p = Framework.GetPlayer(source)
    if not p then return nil end
    local job = p.PlayerData.job or {}
    local grade = job.grade or {}
    return {
        name = job.name, label = job.label or job.name,
        grade = tonumber(type(grade) == 'table' and grade.level or grade) or 0,
        gradeLabel = type(grade) == 'table' and (grade.name or '') or '',
        isBoss = job.isboss == true, onDuty = job.onduty ~= false,
    }
end

function Framework.GetMoney(source, acc)
    local p = Framework.GetPlayer(source)
    return p and tonumber(p.PlayerData.money[acc]) or 0
end

function Framework.RemoveMoney(source, acc, amount, reason)
    local p = Framework.GetPlayer(source)
    if not p or (tonumber(p.PlayerData.money[acc]) or 0) < amount then return false end
    return p.Functions.RemoveMoney(acc, amount, reason) == true
end

function Framework.AddMoney(source, acc, amount, reason)
    local p = Framework.GetPlayer(source)
    return p and p.Functions.AddMoney(acc, amount, reason) ~= false or false
end

function Framework.GetSource(identifier)
    if not identifier then return nil end
    local p = QBX and exports.qbx_core:GetPlayerByCitizenId(identifier) or (QBCore and QBCore.Functions.GetPlayerByCitizenId(identifier))
    return p and p.PlayerData.source or nil
end

function Framework.IsAdminGroup(source)
    for _, group in ipairs(Config.Admin.Groups) do
        if IsPlayerAceAllowed(source, 'group.' .. group) then return true end
        if QBCore and QBCore.Functions.HasPermission(source, group) then return true end
    end
    return false
end

function Framework.GetJobLabel(job)
    local jobs = QBX and exports.qbx_core:GetJobs() or (QBCore and QBCore.Shared.Jobs) or {}
    return jobs[job] and jobs[job].label or nil
end

--  ██████╗ ███████╗███████╗██╗     ██╗███╗   ██╗███████╗
-- ██╔═══██╗██╔════╝██╔════╝██║     ██║████╗  ██║██╔════╝
-- ██║   ██║█████╗  █████╗  ██║     ██║██╔██╗ ██║█████╗
-- ██║   ██║██╔══╝  ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝
-- ╚██████╔╝██║     ██║     ███████╗██║██║ ╚████║███████╗
--  ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝

local function charName(json_)
    local ok, c = pcall(json.decode, json_ or '{}')
    c = ok and c or {}
    return ((c.firstname or '') .. ' ' .. (c.lastname or ''))
end

function Framework.SearchCharacters(query, limit)
    local rows = MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ? OR charinfo LIKE ? LIMIT ?',
        { query, '%' .. query .. '%', (limit or 10) * 2 }) or {}
    local out, lower = {}, query:lower()
    for _, r in ipairs(rows) do
        local name = charName(r.charinfo)
        if r.citizenid == query or name:lower():find(lower, 1, true) then
            out[#out + 1] = { identifier = r.citizenid, name = name }
            if #out >= (limit or 10) then break end
        end
    end
    return out
end

function Framework.GetCharacterName(identifier)
    local src = Framework.GetSource(identifier)
    if src then return Framework.GetName(src) end
    local r = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { identifier })
    return r and charName(r.charinfo) or nil
end

function Framework.GetOfflineBank(identifier)
    return tonumber(MySQL.scalar.await("SELECT JSON_EXTRACT(money, '$.bank') FROM players WHERE citizenid = ?", { identifier }))
end

function Framework.RemoveOfflineBank(identifier, amount, allowNegative)
    local sql = "UPDATE players SET money = JSON_SET(money, '$.bank', ROUND(JSON_EXTRACT(money, '$.bank') - ?, 2)) WHERE citizenid = ?"
    local params = { amount, identifier }
    if not allowNegative then
        sql = sql .. " AND JSON_EXTRACT(money, '$.bank') >= ?"
        params[#params + 1] = amount
    end
    return (MySQL.update.await(sql, params) or 0) == 1
end

function Framework.AddOfflineBank(identifier, amount)
    return (MySQL.update.await("UPDATE players SET money = JSON_SET(money, '$.bank', ROUND(JSON_EXTRACT(money, '$.bank') + ?, 2)) WHERE citizenid = ?",
        { amount, identifier }) or 0) == 1
end

function Framework.GetSocietyMembers(job)
    local out, seen = {}, {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local j = Framework.GetJob(src)
        if j and j.name == job then
            local cid = Framework.GetIdentifier(src)
            seen[cid] = true
            out[#out + 1] = { identifier = cid, name = Framework.GetName(src), grade = j.grade, gradeLabel = j.gradeLabel, isBoss = j.isBoss, online = true }
        end
    end
    local rows = MySQL.query.await("SELECT citizenid, charinfo, job FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? LIMIT 200", { job }) or {}
    for _, r in ipairs(rows) do
        if not seen[r.citizenid] then
            local ok, j = pcall(json.decode, r.job or '{}')
            j = ok and j or {}
            local g = type(j.grade) == 'table' and j.grade or {}
            out[#out + 1] = { identifier = r.citizenid, name = charName(r.charinfo), grade = tonumber(g.level) or 0,
                gradeLabel = g.name or '', isBoss = j.isboss == true, online = false }
        end
    end
    return out
end

-- ██╗████████╗███████╗███╗   ███╗███████╗
-- ██║╚══██╔══╝██╔════╝████╗ ████║██╔════╝
-- ██║   ██║   █████╗  ██╔████╔██║███████╗
-- ██║   ██║   ██╔══╝  ██║╚██╔╝██║╚════██║
-- ██║   ██║   ███████╗██║ ╚═╝ ██║███████║
-- ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚══════╝

function Framework.RegisterUsableItem(name, cb)
    local handler = function(source, item) cb(source, item and (item.info or item.metadata) or {}) end
    if QBX then exports.qbx_core:CreateUseableItem(name, handler) else QBCore.Functions.CreateUseableItem(name, handler) end
end

function Framework.OnPlayerLoaded(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        local src = player and player.PlayerData and player.PlayerData.source
        if src then cb(src) end
    end)
end
