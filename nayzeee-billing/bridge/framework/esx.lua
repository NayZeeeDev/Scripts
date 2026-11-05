--[[
    NAYZEEE BILLING - ESX bridge (server)
    Editable: everything ESX-specific lives in this file.
]]

if Shared.GetFramework() ~= 'esx' then return end

local ESX = exports['es_extended']:getSharedObject()
Framework = { Name = 'esx' }

function Framework.GetPlayer(source)
    source = tonumber(source)
    return source and ESX.GetPlayerFromId(source) or nil
end

function Framework.GetIdentifier(source)
    local p = Framework.GetPlayer(source)
    return p and p.identifier or nil
end

function Framework.GetName(source)
    local p = Framework.GetPlayer(source)
    if not p then return 'Unknown' end
    return p.getName() or GetPlayerName(source) or 'Unknown'
end

function Framework.GetJob(source)
    local p = Framework.GetPlayer(source)
    if not p or not p.job then return nil end
    local job = p.job
    return {
        name = job.name, label = job.label or job.name,
        grade = tonumber(job.grade) or 0, gradeLabel = job.grade_label or job.grade_name or '',
        isBoss = job.grade_name == 'boss', onDuty = true,
    }
end

local function account(name) return name == 'cash' and 'money' or name end

function Framework.GetMoney(source, acc)
    local p = Framework.GetPlayer(source)
    if not p then return 0 end
    local a = p.getAccount(account(acc))
    return a and tonumber(a.money) or 0
end

function Framework.RemoveMoney(source, acc, amount, reason)
    local p = Framework.GetPlayer(source)
    if not p then return false end
    local a = p.getAccount(account(acc))
    if not a or (tonumber(a.money) or 0) < amount then return false end
    p.removeAccountMoney(account(acc), amount, reason)
    return true
end

function Framework.AddMoney(source, acc, amount, reason)
    local p = Framework.GetPlayer(source)
    if not p then return false end
    p.addAccountMoney(account(acc), amount, reason)
    return true
end

function Framework.GetSource(identifier)
    if not identifier then return nil end
    local p = ESX.GetPlayerFromIdentifier(identifier)
    return p and p.source or nil
end

function Framework.IsAdminGroup(source)
    local p = Framework.GetPlayer(source)
    local group = p and p.getGroup and p.getGroup() or 'user'
    return Shared.Contains(Config.Admin.Groups, group)
end

function Framework.GetJobLabel(job)
    local jobs = ESX.GetJobs and ESX.GetJobs() or {}
    return jobs[job] and jobs[job].label or nil
end

--  ██████╗ ███████╗███████╗██╗     ██╗███╗   ██╗███████╗
-- ██╔═══██╗██╔════╝██╔════╝██║     ██║████╗  ██║██╔════╝
-- ██║   ██║█████╗  █████╗  ██║     ██║██╔██╗ ██║█████╗
-- ██║   ██║██╔══╝  ██╔══╝  ██║     ██║██║╚██╗██║██╔══╝
-- ╚██████╔╝██║     ██║     ███████╗██║██║ ╚████║███████╗
--  ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝

function Framework.SearchCharacters(query, limit)
    local like = '%' .. query .. '%'
    local rows = MySQL.query.await(
        "SELECT identifier, firstname, lastname FROM users WHERE identifier = ? OR CONCAT(firstname, ' ', lastname) LIKE ? LIMIT ?",
        { query, like, limit or 10 }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { identifier = r.identifier, name = ('%s %s'):format(r.firstname or '', r.lastname or '') } end
    return out
end

function Framework.GetCharacterName(identifier)
    local src = Framework.GetSource(identifier)
    if src then return Framework.GetName(src) end
    local r = MySQL.single.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { identifier })
    return r and ('%s %s'):format(r.firstname or '', r.lastname or '') or nil
end

function Framework.GetOfflineBank(identifier)
    local v = MySQL.scalar.await("SELECT JSON_EXTRACT(accounts, '$.bank') FROM users WHERE identifier = ?", { identifier })
    return tonumber(v)
end

-- Atomic: only succeeds if the balance covers it (unless allowNegative)
function Framework.RemoveOfflineBank(identifier, amount, allowNegative)
    local sql = "UPDATE users SET accounts = JSON_SET(accounts, '$.bank', ROUND(JSON_EXTRACT(accounts, '$.bank') - ?, 2)) WHERE identifier = ?"
    local params = { amount, identifier }
    if not allowNegative then
        sql = sql .. " AND JSON_EXTRACT(accounts, '$.bank') >= ?"
        params[#params + 1] = amount
    end
    return (MySQL.update.await(sql, params) or 0) == 1
end

function Framework.AddOfflineBank(identifier, amount)
    return (MySQL.update.await("UPDATE users SET accounts = JSON_SET(accounts, '$.bank', ROUND(JSON_EXTRACT(accounts, '$.bank') + ?, 2)) WHERE identifier = ?",
        { amount, identifier }) or 0) == 1
end

-- Everyone with this job, online or not: { identifier, name, grade, gradeLabel, isBoss, online }
function Framework.GetSocietyMembers(job)
    local grades = (ESX.GetJobs and ESX.GetJobs() or {})[job]
    grades = grades and grades.grades or {}
    local out, seen = {}, {}
    for _, p in pairs(ESX.GetExtendedPlayers('job', job)) do
        seen[p.identifier] = true
        out[#out + 1] = { identifier = p.identifier, name = p.getName(), grade = tonumber(p.job.grade) or 0,
            gradeLabel = p.job.grade_label or '', isBoss = p.job.grade_name == 'boss', online = true }
    end
    for _, r in ipairs(MySQL.query.await('SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ? LIMIT 200', { job }) or {}) do
        if not seen[r.identifier] then
            local g = grades[tostring(r.job_grade)] or {}
            out[#out + 1] = { identifier = r.identifier, name = ('%s %s'):format(r.firstname or '', r.lastname or ''),
                grade = tonumber(r.job_grade) or 0, gradeLabel = g.label or '', isBoss = g.name == 'boss', online = false }
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
    ESX.RegisterUsableItem(name, function(source, _, item)
        cb(source, item and (item.metadata or item.info) or {})
    end)
end

function Framework.OnPlayerLoaded(cb)
    AddEventHandler('esx:playerLoaded', function(playerId) cb(tonumber(playerId)) end)
end
