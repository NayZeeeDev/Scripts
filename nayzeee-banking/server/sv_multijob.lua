if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  MULTI-JOB BRIDGE
--
--  ESX only ever knows about the job a player is clocked into.
--  Multi-job resources keep the rest in their own table, so without
--  this a police officer who clocks into mechanic loses the police
--  society tab and stops being paid as police — even though they are
--  still on the roster.
--
--  Adapters are tried in order and the first that answers wins:
--    1. an export on the configured resource
--    2. a generic SQL table (covers most forks)
--    3. the active job only (what ESX gives us)
-- ═══════════════════════════════════════════════════════════

local cache = {}   -- [identifier] = { jobs = {...}, at = os.time() }
local CACHE_SECONDS = 30

--- Each resource wants a different argument. `arg` says which.
local KNOWN_EXPORTS = {
    ['nayzeee-multijob'] = { method = 'GetPlayerJobs', arg = 'source' },
    ['esx_multijob']     = { method = 'GetPlayerJobs', arg = 'identifier' },
    ['qb-multijob']      = { method = 'GetPlayerJobs', arg = 'source' },
    ['multijob']         = { method = 'getJobs',       arg = 'identifier' }
}

local function detectResource()
    if Config.MultiJob.resource ~= 'auto' then
        return Config.MultiJob.resource ~= 'none' and Config.MultiJob.resource or nil
    end
    for res in pairs(KNOWN_EXPORTS) do
        if GetResourceState(res) == 'started' then return res end
    end
    return nil
end

local function fromExport(identifier, src)
    local res = detectResource()
    if not res then return nil end

    local known = KNOWN_EXPORTS[res] or {}
    local method = Config.MultiJob.export or known.method
    if not method then return nil end

    local payload = (known.arg == 'source') and src or identifier
    if payload == nil then return nil end

    local ok, result = pcall(function()
        return exports[res][method](nil, payload)
    end)
    if not ok or type(result) ~= 'table' then return nil end

    local jobs = {}
    for _, row in pairs(result) do
        local name = row.job or row.name or row.job_name
        if name then
            jobs[#jobs + 1] = {
                name  = name,
                grade = tonumber(row.grade or row.job_grade or 0) or 0,
                label = row.label or row.grade_label
            }
        end
    end
    return #jobs > 0 and jobs or nil
end

local function fromTable(identifier)
    local t = Config.MultiJob.fallbackTable
    if not t or not t.name then return nil end

    local ok, rows = pcall(function()
        return MySQL.query.await(
            ('SELECT `%s` AS job, `%s` AS grade FROM `%s` WHERE `%s` = ?'):format(
                t.job, t.grade, t.name, t.identifier),
            { identifier })
    end)
    if not ok or type(rows) ~= 'table' or #rows == 0 then return nil end

    local jobs = {}
    for _, row in ipairs(rows) do
        jobs[#jobs + 1] = { name = row.job, grade = tonumber(row.grade) or 0 }
    end
    return jobs
end

--- Grade name for a job and grade number (and whether it is a boss grade), from the framework.
local function gradeName(job, grade)
    local jobs = ESX.GetJobs()
    local data = jobs and jobs[job]
    if not data or not data.grades then return tostring(grade) end
    local g = data.grades[tostring(grade)]
    return g and (g.name or g.label) or tostring(grade), g and g.isboss or false
end

--- Every job this player holds, active one first.
function Bank.jobsFor(xPlayer)
    if not xPlayer then return {} end

    local active = {
        name       = xPlayer.job.name,
        grade      = xPlayer.job.grade,
        grade_name = xPlayer.job.grade_name,
        isboss     = xPlayer.job.isboss,
        active     = true
    }

    if not Config.MultiJob.enabled then return { active } end

    local hit = cache[xPlayer.identifier]
    if hit and (os.time() - hit.at) < CACHE_SECONDS then
        return hit.jobs
    end

    -- Qbox holds every job itself; elsewhere a multi-job resource does
    local found = (Framework.allJobs and Framework.allJobs(xPlayer))
        or fromExport(xPlayer.identifier, xPlayer.source) or fromTable(xPlayer.identifier)
    local jobs = { active }

    if found then
        for _, j in ipairs(found) do
            if j.name ~= active.name then
                local gname, boss = gradeName(j.name, j.grade)
                jobs[#jobs + 1] = {
                    name       = j.name,
                    grade      = j.grade,
                    grade_name = j.label or gname,
                    isboss     = boss,
                    active     = false
                }
            end
        end
    end

    cache[xPlayer.identifier] = { jobs = jobs, at = os.time() }
    return jobs
end

--- Jobs whose society account this player may reach.
function Bank.societyJobs(xPlayer)
    local out = {}
    for _, job in ipairs(Bank.jobsFor(xPlayer)) do
        if job.active or Config.MultiJob.allowInactiveJobs then
            if Bank.canUseSociety(job.name, job.grade_name, job.isboss) then
                out[#out + 1] = job.name
            end
        end
    end
    return out
end

--- Duty state from the multi-job resource, when it tracks one.
function Bank.onDuty(xPlayer)
    if not Config.MultiJob.enabled or not Config.MultiJob.useDutyState then return nil end

    local res = detectResource()
    if not res then return nil end

    local ok, duty = pcall(function()
        return exports[res]:IsPlayerOnDuty(xPlayer.source)
    end)
    if ok and type(duty) == 'boolean' then return duty end
    return nil
end

function Bank.holdsJob(xPlayer, jobName)
    for _, job in ipairs(Bank.jobsFor(xPlayer)) do
        if job.name == jobName then
            return true, job.active
        end
    end
    return false, false
end

--- Drop the cache when a player's jobs change.
local function invalidate(identifier)
    cache[identifier] = nil
end

Framework.onJobChanged(function(src)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return end
    invalidate(xPlayer.identifier)
    TriggerClientEvent('nz_bank:refresh', src)
end)

RegisterNetEvent('nz_bank:jobsChanged', function(target)
    local xPlayer = Bank.getPlayer(target or source)
    if not xPlayer then return end
    invalidate(xPlayer.identifier)
    TriggerClientEvent('nz_bank:refresh', xPlayer.source)
end)

AddEventHandler('playerDropped', function()
    local xPlayer = Bank.getPlayer(source)
    if xPlayer then invalidate(xPlayer.identifier) end
end)

--- Multi-job resources can tell us directly when someone's roster changes.
exports('refreshJobs', function(identifier)
    invalidate(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if xPlayer then TriggerClientEvent('nz_bank:refresh', xPlayer.source) end
    return true
end)

exports('getPlayerSocieties', function(identifier)
    local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
    if not xPlayer then return {} end
    return Bank.societyJobs(xPlayer)
end)
