if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  FRAMEWORK
--
--  ESX, QBCore and Qbox, picked with Config.Framework ('auto'
--  finds whichever is running). The rest of the resource talks to
--  one shape of player and one shape of job whatever is underneath:
--
--    player.source, player.identifier (ESX identifier / citizenid)
--    player.job = { name, label, grade, grade_name, grade_label }
--    player.getMoney / addMoney / removeMoney        (cash)
--    player.getAccount('bank') / setAccountMoney      (the bank figure)
--    player.getName / get('firstName') / getGroup
--
--  On QBCore and Qbox the `ESX` table below is a small stand-in with
--  the five calls this resource makes, built on that framework. It
--  lives in this resource only and touches nothing else on the server.
-- ═══════════════════════════════════════════════════════════
Framework = { name = nil }

local function started(res) return GetResourceState(res) == 'started' or GetResourceState(res) == 'starting' end

local function detect()
    local want = (Config.Framework or 'auto'):lower()
    if want == 'qb' or want == 'qb-core' then want = 'qbcore' end
    if want == 'qbx' or want == 'qbx_core' then want = 'qbox' end
    if want ~= 'auto' then return want end

    -- Qbox also answers to qb-core, so it is checked first
    if started('qbx_core') then return 'qbox' end
    if started('qb-core') then return 'qbcore' end
    if started('es_extended') then return 'esx' end
    return 'esx'
end

Framework.name = detect()
local FW = Framework.name

-- ═══════════════════════════════════════════════════════════
--  ESX
-- ═══════════════════════════════════════════════════════════
if FW == 'esx' then
    ESX = exports['es_extended']:getSharedObject()

    function Framework.onPlayerLoaded(fn)
        AddEventHandler('esx:playerLoaded', function(src, xPlayer) fn(src, xPlayer) end)
    end

    function Framework.onJobChanged(fn)
        AddEventHandler('esx:setJob', function(src) fn(src) end)
    end

    --- The job of a player who is offline: name, grade number, grade name.
    function Framework.offlineJob(identifier)
        local row = MySQL.single.await('SELECT job, job_grade FROM users WHERE identifier = ?', { identifier })
        if not row then return nil end
        local jobs = ESX.GetJobs()
        local g = jobs and jobs[row.job] and jobs[row.job].grades and jobs[row.job].grades[tostring(row.job_grade)]
        return row.job, tonumber(row.job_grade) or 0, g and g.name
    end

    function Framework.stopPaycheck(xPlayer)
        if xPlayer.togglePaycheck then xPlayer.togglePaycheck(false) return true end
        return false
    end

    return
end

-- ═══════════════════════════════════════════════════════════
--  QBCORE / QBOX
-- ═══════════════════════════════════════════════════════════
local QBCore = FW == 'qbcore' and exports['qb-core']:GetCoreObject() or nil
local qbx = FW == 'qbox' and exports.qbx_core or nil

local function rawPlayer(src)
    src = tonumber(src)
    if not src then return nil end
    if qbx then return qbx:GetPlayer(src) end
    return QBCore.Functions.GetPlayer(src)
end

local function rawByCitizen(cid)
    if type(cid) ~= 'string' then return nil end
    if qbx then return qbx:GetPlayerByCitizenId(cid) end
    return QBCore.Functions.GetPlayerByCitizenId(cid)
end

local function rawPlayers()
    if qbx then return qbx:GetQBPlayers() or {} end
    return QBCore.Functions.GetQBPlayers() or {}
end

--- Every job in ESX's shape: jobs[name] = { name, label, grades = { ['0'] = { grade, name, label, salary } } }.
--- A boss grade is named 'boss', the same word ESX uses, so Config.Accounts.societyAccess
--- reads the same on every framework; everything else is the grade's name in lower case.
local jobCache, jobCacheAt = nil, 0
local function sharedJobs()
    if jobCache and GetGameTimer() - jobCacheAt < 60000 then return jobCache end
    local src = qbx and qbx:GetJobs() or (QBCore.Shared and QBCore.Shared.Jobs) or {}

    local out = {}
    for name, job in pairs(src) do
        local grades = {}
        for level, g in pairs(job.grades or {}) do
            local n = tonumber(level) or 0
            grades[tostring(n)] = {
                grade  = n,
                name   = g.isboss and 'boss' or tostring(g.name or n):lower(),
                label  = g.name or tostring(n),
                salary = g.payment or 0,
                isboss = g.isboss or false,
            }
        end
        out[name] = { name = name, label = job.label or name, grades = grades }
    end
    jobCache, jobCacheAt = out, GetGameTimer()
    return out
end

local function jobOf(pd)
    local job = pd.job or {}
    local grade = job.grade or {}
    local level = tonumber(grade.level) or 0
    return {
        name        = job.name or 'unemployed',
        label       = job.label or job.name or 'Unemployed',
        grade       = level,
        grade_name  = job.isboss and 'boss' or tostring(grade.name or level):lower(),
        grade_label = grade.name or tostring(level),
        isboss      = job.isboss or false,
        onduty      = job.onduty,
    }
end

local MONEY = { money = 'cash', cash = 'cash', bank = 'bank' }
local REASON = 'nayzeee-banking'

--- A QBCore / Qbox player, dressed as the player object this resource uses.
local function wrap(P)
    if not P or not P.PlayerData then return nil end
    local pd = P.PlayerData
    local src = pd.source
    local x = { source = src, identifier = pd.citizenid, raw = P }

    -- read live, so a job change mid-session is seen straight away
    setmetatable(x, { __index = function(_, key)
        if key == 'job' then return jobOf(P.PlayerData) end
    end })

    local fn = P.Functions
    function x.getMoney() return fn.GetMoney('cash') or 0 end
    function x.addMoney(amount) return fn.AddMoney('cash', amount, REASON) end
    function x.removeMoney(amount) return fn.RemoveMoney('cash', amount, REASON) end
    function x.getAccount(name)
        local t = MONEY[name] or name
        return { name = name, money = fn.GetMoney(t) or 0 }
    end
    function x.setAccountMoney(name, amount) return fn.SetMoney(MONEY[name] or name, amount, REASON) end
    function x.addAccountMoney(name, amount) return fn.AddMoney(MONEY[name] or name, amount, REASON) end
    function x.removeAccountMoney(name, amount) return fn.RemoveMoney(MONEY[name] or name, amount, REASON) end

    function x.get(key)
        local c = P.PlayerData.charinfo or {}
        if key == 'firstName' then return c.firstname end
        if key == 'lastName' then return c.lastname end
        return P.PlayerData[key]
    end
    function x.getName()
        local c = P.PlayerData.charinfo or {}
        return (('%s %s'):format(c.firstname or '', c.lastname or ''):gsub('^%s+', ''):gsub('%s+$', ''))
    end

    --- The first of Config.Admin.allowGroups this player holds. QBCore keeps
    --- permissions as ACE groups (group.admin, group.god), Qbox the same.
    function x.getGroup()
        for _, group in ipairs((Config.Admin and Config.Admin.allowGroups) or {}) do
            if IsPlayerAceAllowed(src, 'group.' .. group) then return group end
            if QBCore and QBCore.Functions.HasPermission and QBCore.Functions.HasPermission(src, group) then return group end
        end
        return 'user'
    end

    return x
end

--- The stand-in. Only what this resource calls.
ESX = {}

function ESX.GetPlayerFromId(src) return wrap(rawPlayer(src)) end
function ESX.GetPlayerFromIdentifier(cid) return wrap(rawByCitizen(cid)) end
function ESX.GetJobs() return sharedJobs() end

--- Online players, optionally only those in one job (ESX's GetExtendedPlayers('job', name)).
function ESX.GetExtendedPlayers(key, value)
    local out = {}
    for _, P in pairs(rawPlayers()) do
        local x = wrap(P)
        if x and (key ~= 'job' or x.job.name == value) then out[#out + 1] = x end
    end
    return out
end

function ESX.RegisterUsableItem(name, cb)
    if qbx then
        return qbx:CreateUseableItem(name, function(source, item) cb(source, item) end)
    end
    return QBCore.Functions.CreateUseableItem(name, function(source, item) cb(source, item) end)
end

function Framework.onPlayerLoaded(fn)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(P)
        local x = wrap(P)
        if x then fn(x.source, x) end
    end)
end

function Framework.onJobChanged(fn)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) fn(src) end)
    if qbx then AddEventHandler('qbx_core:server:onGroupUpdate', function(src) fn(src) end) end
end

--- Qbox keeps every job a player holds ({ [job] = grade }), so no multi-job resource is needed.
function Framework.allJobs(xPlayer)
    if not qbx or not xPlayer.raw then return nil end
    local list = {}
    for name, grade in pairs(xPlayer.raw.PlayerData.jobs or {}) do
        list[#list + 1] = { name = name, grade = tonumber(grade) or 0 }
    end
    return #list > 0 and list or nil
end

function Framework.offlineJob(cid)
    local row = MySQL.single.await('SELECT job FROM players WHERE citizenid = ?', { cid })
    if not row or not row.job then return nil end
    local ok, job = pcall(json.decode, row.job)
    if not ok or type(job) ~= 'table' then return nil end
    local level = tonumber(job.grade and job.grade.level) or 0
    local gname = job.isboss and 'boss' or tostring(job.grade and job.grade.name or level):lower()
    return job.name, level, gname
end

--- QBCore and Qbox pay salaries from their own loop for everyone at once;
--- there is no per-player switch. Payroll mode 'bank' needs that loop off
--- in the framework's own config (see README).
function Framework.stopPaycheck() return false end
