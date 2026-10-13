--[[
    NAYZEEE MULTIJOB - Server Main
    Version: 1.0.0
    Discord: discord.gg/nayzeeedev

    The server owns every decision here: which jobs a player has, whether
    they are on duty, cooldowns and staff permissions. Clients only ask.
]]

if not NAYZEEE_LOCK_OK then return end

local VERSION = '1.0.0'

-- oxmysql returns TINYINT(1) as a number on some builds and a boolean on
-- others. Treat both as truthy so the UI shows the right actions either way.
local function IsTrue(v)
    return v == 1 or v == true or v == '1'
end

local function DebugLog(...)
    if Config.Debug then
        print('^3[nayzeee-multijob]^7', ...)
    end
end

local Ready = false -- set once tables exist and jobs are loaded
local JobInfo = {}
local lastJobLoad = 0

local Shifts = {}     -- [src] = open shift
local AfkPaused = {}  -- [src] = true when the default job was paused for inactivity
local LastSwitch = {} -- [identifier] = os.time() of the last switch (cooldowns)
local RateTimes = {}  -- [src] = { [key] = GetGameTimer() }

-- Drops a client event if the same client sent the same kind within `ms`
local function RateLimit(src, key, ms)
    local now = GetGameTimer()
    local t = RateTimes[src]
    if not t then
        t = {}
        RateTimes[src] = t
    end
    if t[key] and now - t[key] < ms then return false end
    t[key] = now
    return true
end

local function Say(src, title, message, nType)
    Notify(src, { title = title, message = message, type = nType or 'info' })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAMEWORK BRIDGE
-- ═══════════════════════════════════════════════════════════════════════════

local function Core() return Shared.GetFrameworkObject() end
local function IsESX() return Shared.GetFramework() == 'esx' end
local function IsQB()
    local fw = Shared.GetFramework()
    return fw == 'qbcore' or fw == 'qbox'
end

local function GetPlayer(src)
    local core = Core()
    if not core or not src then return nil end
    if IsESX() then return core.GetPlayerFromId(src) end
    if IsQB() then return core.Functions.GetPlayer(src) end
    return nil
end

local function IdentifierOf(player)
    if not player then return nil end
    if IsESX() then return player.identifier end
    return player.PlayerData and player.PlayerData.citizenid
end

local function GetIdentifier(src)
    return IdentifierOf(GetPlayer(src))
end

-- Current framework job, normalised: { name, grade, salary, onduty }
-- onduty is only set on QBCore / QBox, which track it themselves
local function GetFrameworkJob(src)
    local player = GetPlayer(src)
    if not player then return nil end

    if IsESX() then
        local job = player.job or (player.getJob and player.getJob())
        if not job or not job.name then return nil end
        return {
            name = job.name,
            grade = tonumber(job.grade) or 0,
            salary = tonumber(job.grade_salary) or 0,
        }
    end

    local job = player.PlayerData and player.PlayerData.job
    if not job or not job.name then return nil end
    local grade = type(job.grade) == 'table' and job.grade or {}
    return {
        name = job.name,
        grade = tonumber(grade.level) or 0,
        salary = tonumber(job.payment) or 0,
        onduty = job.onduty == true,
    }
end

-- Character name where the framework has one, FiveM name otherwise
local function GetDisplayName(src)
    local player = GetPlayer(src)
    if player then
        if IsESX() and player.getName then
            local ok, name = pcall(player.getName)
            if ok and type(name) == 'string' and name ~= '' then return name end
        elseif player.PlayerData and player.PlayerData.charinfo then
            local info = player.PlayerData.charinfo
            local name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
            if name ~= '' then return name end
        end
    end
    return GetPlayerName(src) or 'Unknown'
end

local function ForEachPlayer(cb)
    local core = Core()
    if not core then return end

    if IsESX() then
        if core.GetExtendedPlayers then
            for _, xPlayer in pairs(core.GetExtendedPlayers() or {}) do
                cb(xPlayer.source, xPlayer)
            end
        else
            for _, src in ipairs(core.GetPlayers() or {}) do
                local xPlayer = core.GetPlayerFromId(src)
                if xPlayer then cb(src, xPlayer) end
            end
        end
    elseif IsQB() then
        for _, player in pairs(core.Functions.GetQBPlayers() or {}) do
            if player.PlayerData then cb(player.PlayerData.source, player) end
        end
    end
end

-- Mirrors our duty onto QBCore's own on-duty flag (what its paychecks check)
local function SetFrameworkDuty(src, onDuty)
    if not (Config.DutyTracking.syncFrameworkDuty and IsQB()) then return end
    local player = GetPlayer(src)
    if not player or not player.Functions or not player.Functions.SetJobDuty then return end
    local job = player.PlayerData and player.PlayerData.job
    if job and job.onduty == onDuty then return end
    player.Functions.SetJobDuty(onDuty)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- JOB INFO
-- ═══════════════════════════════════════════════════════════════════════════

-- ESX keys grades by string, QBCore by string, QBox by number. Labels and pay
-- live under different names too. Everything below reads this one shape.
local function NormaliseGrades(grades)
    local out = {}
    for key, g in pairs(grades or {}) do
        local level = tonumber(g.grade) or tonumber(key)
        if level then
            out[level] = {
                label = g.label or g.name or ('Grade ' .. level),
                salary = tonumber(g.salary or g.payment) or 0,
            }
        end
    end
    return out
end

local function LoadJobInfo()
    local fw = Shared.GetFramework()
    local core = Core()
    local fresh = {}

    if fw == 'esx' then
        local jobs = core and core.GetJobs and core.GetJobs()
        if jobs and next(jobs) then
            for name, job in pairs(jobs) do
                fresh[name] = { label = job.label or name, grades = NormaliseGrades(job.grades) }
            end
        else
            for _, job in ipairs(MySQL.query.await('SELECT name, label FROM jobs') or {}) do
                fresh[job.name] = { label = job.label or job.name, grades = {} }
            end
            for _, g in ipairs(MySQL.query.await('SELECT job_name, grade, name, label, salary FROM job_grades') or {}) do
                local job = fresh[g.job_name]
                if job then
                    job.grades[tonumber(g.grade) or 0] = { label = g.label or g.name, salary = tonumber(g.salary) or 0 }
                end
            end
        end
    elseif fw == 'qbcore' or fw == 'qbox' then
        local jobs
        if fw == 'qbox' then
            local ok, result = pcall(function() return exports.qbx_core:GetJobs() end)
            if ok then jobs = result end
        end
        jobs = jobs or (core and core.Shared and core.Shared.Jobs) or {}
        for name, job in pairs(jobs) do
            fresh[name] = { label = job.label or name, grades = NormaliseGrades(job.grades) }
        end
    end

    JobInfo = fresh
    lastJobLoad = os.time()

    local count = 0
    for _ in pairs(JobInfo) do count = count + 1 end
    return count
end

-- Reloads on a miss so jobs created after start still work
local function GetJob(name)
    if type(name) ~= 'string' or name == '' then return nil end
    local job = JobInfo[name]
    if not job and os.time() - lastJobLoad > 30 then
        LoadJobInfo()
        job = JobInfo[name]
    end
    return job
end

local function JobLabel(name)
    local job = JobInfo[name]
    return job and job.label or name
end

local function GradeExists(jobName, grade)
    local job = GetJob(jobName)
    if not job then return false end
    if not next(job.grades) then return true end -- grades unknown, let the framework decide
    return job.grades[grade] ~= nil
end

local function SetPlayerJob(src, jobName, grade)
    local player = GetPlayer(src)
    grade = math.floor(tonumber(grade) or 0)
    if not player or not GetJob(jobName) or not GradeExists(jobName, grade) then
        DebugLog('SetPlayerJob refused', src, jobName, grade)
        return false
    end

    if IsESX() then
        player.setJob(jobName, grade)
        local job = player.job or (player.getJob and player.getJob())
        return job ~= nil and job.name == jobName
    end

    return player.Functions.SetJob(jobName, grade) ~= false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PERMISSIONS
-- ═══════════════════════════════════════════════════════════════════════════

local function IsAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'nayzeee-multijob.admin') then return true end

    if IsESX() then
        local player = GetPlayer(src)
        local group = player and player.getGroup and player.getGroup()
        if type(group) ~= 'string' then return false end
        for _, g in ipairs(Config.AdminGroups) do
            if group:lower() == g:lower() then return true end
        end
        return false
    end

    local core = Core()
    for _, g in ipairs(Config.AdminGroups) do
        if IsPlayerAceAllowed(src, 'group.' .. g) then return true end
        if core and core.Functions and core.Functions.HasPermission then
            local ok, has = pcall(core.Functions.HasPermission, src, g)
            if ok and has then return true end
        end
    end
    return false
end

local function HasPerm(src, perm)
    return IsAdmin(src) and (Config.AdminPermissions or {})[perm] ~= false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LOGGING (database + optional Discord)
-- ═══════════════════════════════════════════════════════════════════════════

local DiscordQueue = {}

local DISCORD_CATEGORY = {
    job_switch = 'jobSwitch', quit_job = 'jobSwitch', job_removed = 'jobSwitch', job_added = 'jobSwitch',
    clock_in = 'clockIn', clock_out = 'clockOut',
}

local DISCORD_COLOR = {
    jobSwitch = 0x08afa2, clockIn = 0x08afa2, clockOut = 0x63696d, adminAction = 0xe5484d,
}

local function DiscordWebhook()
    local cfg = ServerConfig and ServerConfig.Discord
    if not cfg or not cfg.enabled then return nil end
    local url = cfg.webhook
    if not url or url == '' or url == 'YOUR_WEBHOOK_HERE' then
        url = GetConvar('nayzeee_multijob_webhook', '')
    end
    return url ~= '' and url or nil
end

local function QueueDiscord(action, name, job, details, adminName)
    local cfg = ServerConfig and ServerConfig.Discord
    if not DiscordWebhook() then return end

    local category = action:find('^admin_') and 'adminAction' or DISCORD_CATEGORY[action]
    if not category or (cfg.logEvents and cfg.logEvents[category] == false) then return end

    local fields = {
        { name = 'Player', value = tostring(name or 'Unknown'), inline = true },
        { name = 'Job', value = tostring(job and JobLabel(job) or '-'), inline = true },
    }
    if adminName then fields[#fields + 1] = { name = 'Staff', value = tostring(adminName), inline = true } end
    if details and details ~= '' then fields[#fields + 1] = { name = 'Details', value = tostring(details) } end

    DiscordQueue[#DiscordQueue + 1] = {
        title = action:gsub('_', ' '):gsub('^%l', string.upper),
        color = DISCORD_COLOR[category],
        fields = fields,
        footer = { text = 'nayzeee-multijob v' .. VERSION },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
end

-- One embed per second keeps us well under Discord's webhook rate limit
CreateThread(function()
    while true do
        Wait(1000)
        local embed = table.remove(DiscordQueue, 1)
        local url = embed and DiscordWebhook()
        if url then
            local cfg = ServerConfig.Discord
            PerformHttpRequest(url, function() end, 'POST', json.encode({
                username = cfg.username or 'Job Center',
                avatar_url = (cfg.avatar and cfg.avatar ~= '') and cfg.avatar or nil,
                embeds = { embed },
            }), { ['Content-Type'] = 'application/json' })
        end
    end
end)

local function LogAction(identifier, name, action, job, details, adminId, adminName)
    MySQL.insert('INSERT INTO nayzeee_multijob_logs (identifier, player_name, action, job, details, admin_id, admin_name) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { identifier, name, action, job, details, adminId, adminName })
    QueueDiscord(action, name, job, details, adminName)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DUTY
-- ═══════════════════════════════════════════════════════════════════════════

local function EarningsMode()
    local mode = Config.Earnings and Config.Earnings.mode or 'auto'
    if mode == 'auto' then return IsESX() and 'paycheck' or 'estimate' end
    return mode
end

local function PaycheckSeconds()
    local minutes = Config.Earnings and Config.Earnings.paycheckMinutes
    if not minutes then minutes = IsESX() and 7 or 10 end
    return math.max(60, minutes * 60)
end

local function EstimateEarnings(session, duration)
    return math.floor((session.salary or 0) * duration / PaycheckSeconds())
end

local function SendDutyState(src)
    local s = Shifts[src]
    TriggerClientEvent('nayzeee-multijob:dutyState', src, {
        onDuty = s ~= nil,
        elapsed = s and (os.time() - s.startTime) or 0,
        job = s and s.job or nil,
        afkPaused = AfkPaused[src] == true,
    })
end

-- Never yields, so it is safe inside exports and framework event handlers
local function StartShift(src, opts)
    opts = opts or {}
    if Shifts[src] then return false end

    local info = GetFrameworkJob(src)
    local identifier = GetIdentifier(src)
    if not info or not identifier then return false end

    local session = {
        identifier = identifier,
        name = GetDisplayName(src),
        job = info.name,
        grade = info.grade,
        salary = info.salary,
        startTime = os.time(),
        earned = 0,
    }
    Shifts[src] = session
    AfkPaused[src] = nil

    SetFrameworkDuty(src, true)
    SendDutyState(src)

    MySQL.insert('INSERT INTO nayzeee_multijob_shifts (identifier, job, clock_in) VALUES (?, ?, NOW())', { identifier, info.name }, function(shiftId)
        session.shiftId = shiftId
        if session.closed and shiftId then
            -- the shift ended before the insert came back
            MySQL.update('UPDATE nayzeee_multijob_shifts SET clock_out = NOW(), duration_seconds = ?, earnings = ? WHERE id = ?',
                { session.closedDuration or 0, session.closedEarnings or session.earned, shiftId })
        end
    end)

    MySQL.update('INSERT INTO nayzeee_multijob_stats (identifier, job, sessions, last_clocked) VALUES (?, ?, 1, NOW()) ON DUPLICATE KEY UPDATE sessions = sessions + 1, last_clocked = NOW()',
        { identifier, info.name })

    if not opts.silent then
        Say(src, 'Duty', Shared.L('clocked_in'), 'success')
    end

    -- the default job clocks in on every login; logging it would bury the log
    if not Shared.IsDefaultJob(info.name) then
        LogAction(identifier, session.name, 'clock_in', info.name, opts.reason)
    end
    return true
end

-- reason: manual | afk | switch | jobchange | framework | admin | logout | disconnect | restart
local function EndShift(src, reason)
    local s = Shifts[src]
    if not s then return false end
    Shifts[src] = nil

    local duration = math.max(0, os.time() - s.startTime)
    local hours = duration / 3600
    local estimate = EarningsMode() == 'estimate'
    local earnings = estimate and EstimateEarnings(s, duration) or s.earned

    s.closed = true
    s.closedDuration = duration
    s.closedEarnings = earnings

    if s.shiftId then
        MySQL.update('UPDATE nayzeee_multijob_shifts SET clock_out = NOW(), duration_seconds = ?, earnings = ? WHERE id = ?',
            { duration, earnings, s.shiftId })
    end

    -- In paycheck mode the money was already added as each paycheck landed
    MySQL.update('INSERT INTO nayzeee_multijob_stats (identifier, job, total_hours, total_earnings, sessions) VALUES (?, ?, ?, ?, 0) ON DUPLICATE KEY UPDATE total_hours = total_hours + ?, total_earnings = total_earnings + ?',
        { s.identifier, s.job, hours, estimate and earnings or 0, hours, estimate and earnings or 0 })

    -- Only turn the framework flag off when the player actually stopped working.
    -- After a job change the framework already set duty for the NEW job.
    if reason == 'manual' or reason == 'afk' or reason == 'switch' or reason == 'admin' then
        SetFrameworkDuty(src, false)
    end

    local online = reason ~= 'disconnect' and reason ~= 'logout' and reason ~= 'restart'
    if online then
        SendDutyState(src)
        TriggerClientEvent('nayzeee-multijob:shiftEnded', src, { job = s.job, duration = duration, earnings = earnings })

        if reason == 'manual' or reason == 'admin' then
            Say(src, 'Duty', Shared.L('clocked_out', Shared.FormatTime(duration)), 'info')
        elseif reason == 'afk' then
            Say(src, 'Duty', Shared.L('auto_clock_out'), 'warning')
        end
    end

    if not Shared.IsDefaultJob(s.job) then
        LogAction(s.identifier, s.name, 'clock_out', s.job,
            ('%s · $%d · %s'):format(Shared.FormatTime(duration), earnings, reason or 'manual'))
    end

    return true
end

local function TrackPaycheck(src, amount, jobName)
    src = tonumber(src)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return false end

    if EarningsMode() ~= 'paycheck' then
        DebugLog('TrackPaycheck ignored - Config.Earnings.mode is estimate')
        return false
    end

    local s = Shifts[src]
    local identifier = (s and s.identifier) or GetIdentifier(src)
    if not jobName then
        local info = GetFrameworkJob(src)
        jobName = (s and s.job) or (info and info.name)
    end
    if not identifier or type(jobName) ~= 'string' then return false end

    MySQL.update('INSERT INTO nayzeee_multijob_stats (identifier, job, total_earnings, total_hours, sessions) VALUES (?, ?, ?, 0, 0) ON DUPLICATE KEY UPDATE total_earnings = total_earnings + ?',
        { identifier, jobName, amount, amount })

    if s and s.job == jobName then
        s.earned = s.earned + amount
        if s.shiftId then
            MySQL.update('UPDATE nayzeee_multijob_shifts SET earnings = earnings + ? WHERE id = ?', { amount, s.shiftId })
        end
    end

    DebugLog(('Tracked paycheck $%d for %s (%s)'):format(amount, src, jobName))
    return true
end

-- Server-only event fired by install/REPLACE_paycheck.lua (not a net event)
AddEventHandler('nayzeee-multijob:trackPaycheck', TrackPaycheck)

-- Open shifts are written down every saveInterval so a crash loses at most that
local function StartShiftSaver()
    CreateThread(function()
        while true do
            Wait(math.max(15, Config.DutyTracking.saveInterval or 60) * 1000)
            local now = os.time()
            local estimate = EarningsMode() == 'estimate'
            for _, s in pairs(Shifts) do
                if s.shiftId then
                    local duration = now - s.startTime
                    if estimate then
                        MySQL.update('UPDATE nayzeee_multijob_shifts SET duration_seconds = ?, earnings = ? WHERE id = ?',
                            { duration, EstimateEarnings(s, duration), s.shiftId })
                    else
                        MySQL.update('UPDATE nayzeee_multijob_shifts SET duration_seconds = ? WHERE id = ?', { duration, s.shiftId })
                    end
                end
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- JOB RECORDS
-- ═══════════════════════════════════════════════════════════════════════════

local function CountJobs(identifier)
    return MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_multijob WHERE identifier = ? AND job <> ?',
        { identifier, Config.DefaultJob.name }) or 0
end

local function EnsureDefaultJob(identifier)
    MySQL.update.await('INSERT INTO nayzeee_multijob (identifier, job, grade, removeable) VALUES (?, ?, ?, 0) ON DUPLICATE KEY UPDATE removeable = 0',
        { identifier, Config.DefaultJob.name, Config.DefaultJob.grade or 0 })
end

-- Adds the player's CURRENT framework job to their list (never a client value)
local function SyncJobRecord(src)
    local identifier = GetIdentifier(src)
    local info = GetFrameworkJob(src)
    if not identifier or not info or Shared.IsBlacklisted(info.name) then return end

    if Shared.IsDefaultJob(info.name) then
        EnsureDefaultJob(identifier)
        return
    end

    local row = MySQL.single.await('SELECT grade FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, info.name })
    if row then
        if tonumber(row.grade) ~= info.grade then
            MySQL.update('UPDATE nayzeee_multijob SET grade = ? WHERE identifier = ? AND job = ?', { info.grade, identifier, info.name })
        end
        return
    end

    if CountJobs(identifier) >= (Config.MaxJobs or 4) then
        -- two hooks can report the same change; only warn once
        if RateLimit(src, 'maxjobs', 3000) then
            Say(src, 'Job', Shared.L('max_jobs_reached'), 'warning')
        end
        return
    end

    local added = MySQL.update.await('INSERT IGNORE INTO nayzeee_multijob (identifier, job, grade, removeable) VALUES (?, ?, ?, 1)',
        { identifier, info.name, info.grade })
    if added and added > 0 then
        Say(src, 'Job', Shared.L('job_added'), 'success')
        LogAction(identifier, GetDisplayName(src), 'job_added', info.name, 'Hired · grade ' .. info.grade)
    end
end

-- Runs whenever the framework job or duty may have changed. Reads the
-- framework every time, so firing it twice for one change is harmless.
local function HandleJobChange(src, context)
    src = tonumber(src)
    -- before startup finishes, the startup pass picks every player up anyway
    if not src or not Ready then return end
    local info = GetFrameworkJob(src)
    if not info then return end

    -- shift bookkeeping first: no yields until StartShift has claimed the slot
    local s = Shifts[src]
    if s then
        if s.job ~= info.name then
            EndShift(src, 'jobchange')
        else
            s.grade, s.salary = info.grade, info.salary
        end
    end

    local quiet = context == 'load'
    if Shared.IsDefaultJob(info.name) then
        if not Shifts[src] and not AfkPaused[src] then
            StartShift(src, { silent = true, reason = 'auto' })
        end
    else
        AfkPaused[src] = nil
        if Config.DutyTracking.syncFrameworkDuty and info.onduty ~= nil then
            if info.onduty and not Shifts[src] then
                StartShift(src, { silent = quiet, reason = 'framework' })
            elseif not info.onduty and Shifts[src] then
                EndShift(src, 'framework')
            end
        end
    end

    SyncJobRecord(src)
    TriggerClientEvent('nayzeee-multijob:refresh', src)
end

local function HandleJobChangeAsync(src, context)
    CreateThread(function() HandleJobChange(src, context) end)
end

-- Framework hooks. Only the ones for the running framework ever fire.
AddEventHandler('esx:setJob', function(src) HandleJobChangeAsync(src) end)
AddEventHandler('esx:playerLoaded', function(src) HandleJobChangeAsync(src, 'load') end)
AddEventHandler('esx:playerLogout', function(src)
    EndShift(src, 'logout')
    AfkPaused[src] = nil
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src) HandleJobChangeAsync(src) end)
AddEventHandler('QBCore:Server:SetDuty', function(src) HandleJobChangeAsync(src) end)
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then HandleJobChangeAsync(src, 'load') end
end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    EndShift(src, 'logout')
    AfkPaused[src] = nil
end)

-- Fallback ping from the client in case a framework build doesn't fire the
-- server-side hooks. It carries no data - the server reads the framework.
RegisterNetEvent('nayzeee-multijob:syncJob', function()
    local src = source
    if not RateLimit(src, 'sync', 1000) then return end
    HandleJobChange(src)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SWITCH / QUIT / REMOVE / FAVORITE
-- ═══════════════════════════════════════════════════════════════════════════

local function CooldownLeft(identifier, jobName)
    if not (Config.Cooldowns and Config.Cooldowns.enabled) then return 0 end
    local cooldown = Shared.GetJobCooldown(jobName)
    local last = LastSwitch[identifier]
    if not last or cooldown <= 0 then return 0 end
    return math.max(0, cooldown - (os.time() - last))
end

local function SwitchPlayerJob(src, jobName, opts)
    opts = opts or {}
    local identifier = GetIdentifier(src)
    if not identifier or type(jobName) ~= 'string' then return false end

    local current = GetFrameworkJob(src)
    if current and current.name == jobName then return false end

    if Shared.IsBlacklisted(jobName) then
        Say(src, 'Job', Shared.L('job_blacklisted'), 'error')
        return false
    end
    if not GetJob(jobName) then
        Say(src, 'Job', Shared.L('job_not_found'), 'error')
        return false
    end

    -- Only the default job can be taken without being on the player's record
    local grade
    if Shared.IsDefaultJob(jobName) then
        grade = Config.DefaultJob.grade or 0
    else
        local row = MySQL.single.await('SELECT grade FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
        if not row then
            Say(src, 'Job', Shared.L('job_not_owned'), 'error')
            return false
        end
        grade = tonumber(row.grade) or 0
    end

    if not opts.ignoreCooldown then
        local left = CooldownLeft(identifier, jobName)
        if left > 0 then
            Say(src, 'Cooldown', Shared.L('cooldown_active', Shared.FormatTime(left)), 'error')
            return false
        end
    end

    if not SetPlayerJob(src, jobName, grade) then
        Say(src, 'Job', Shared.L('job_switch_failed'), 'error')
        return false
    end

    LastSwitch[identifier] = os.time()
    HandleJobChange(src) -- closes the old shift even if the framework hook is slow

    Say(src, 'Job', Shared.L('job_switched', JobLabel(jobName)), 'success')
    LogAction(identifier, GetDisplayName(src), 'job_switch', jobName,
        (opts.scheduled and 'Scheduled · ' or '') .. 'Grade ' .. grade)
    return true
end

RegisterNetEvent('nayzeee-multijob:switchJob', function(jobName)
    local src = source
    if not RateLimit(src, 'switch', 1500) then return end
    SwitchPlayerJob(src, jobName)
end)

RegisterNetEvent('nayzeee-multijob:quitJob', function(jobName)
    local src = source
    if not RateLimit(src, 'switch', 1500) then return end
    local identifier = GetIdentifier(src)
    if not identifier or type(jobName) ~= 'string' then return end

    if Shared.IsNonRemovable(jobName) then
        Say(src, 'Job', Shared.L('job_not_removable'), 'error')
        return
    end

    local row = MySQL.single.await('SELECT removeable FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
    local current = GetFrameworkJob(src)
    local isCurrent = current ~= nil and current.name == jobName

    if not row and not isCurrent then
        Say(src, 'Job', Shared.L('job_not_owned'), 'error')
        return
    end
    if row and not IsTrue(row.removeable) then
        Say(src, 'Job', Shared.L('job_not_removable'), 'error')
        return
    end

    if isCurrent then
        EndShift(src, 'switch')
        if not SetPlayerJob(src, Config.DefaultJob.name, Config.DefaultJob.grade or 0) then
            Say(src, 'Job', Shared.L('job_switch_failed'), 'error')
            return
        end
    end

    MySQL.update.await('DELETE FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
    if isCurrent then HandleJobChange(src) end

    Say(src, 'Job', Shared.L('job_quit', JobLabel(jobName)), 'info')
    LogAction(identifier, GetDisplayName(src), 'quit_job', jobName, 'Voluntarily quit')
    TriggerClientEvent('nayzeee-multijob:refresh', src)
end)

RegisterNetEvent('nayzeee-multijob:removeJob', function(jobName)
    local src = source
    if not RateLimit(src, 'remove', 1000) then return end
    local identifier = GetIdentifier(src)
    if not identifier or type(jobName) ~= 'string' then return end

    if Shared.IsNonRemovable(jobName) then
        Say(src, 'Job', Shared.L('job_not_removable'), 'error')
        return
    end

    local current = GetFrameworkJob(src)
    if current and current.name == jobName then
        Say(src, 'Job', Shared.L('job_is_active'), 'error')
        return
    end

    local row = MySQL.single.await('SELECT removeable FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
    if not row then return end
    if not IsTrue(row.removeable) then
        Say(src, 'Job', Shared.L('job_not_removable'), 'error')
        return
    end

    MySQL.update.await('DELETE FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
    Say(src, 'Job', Shared.L('job_removed'), 'info')
    LogAction(identifier, GetDisplayName(src), 'job_removed', jobName, 'Self-removed')
    TriggerClientEvent('nayzeee-multijob:refresh', src)
end)

RegisterNetEvent('nayzeee-multijob:toggleFavorite', function(jobName)
    local src = source
    if not RateLimit(src, 'favorite', 300) then return end
    local identifier = GetIdentifier(src)
    if not identifier or type(jobName) ~= 'string' then return end

    MySQL.update.await('UPDATE nayzeee_multijob SET favorite = IF(favorite = 1, 0, 1) WHERE identifier = ? AND job = ?', { identifier, jobName })
    TriggerClientEvent('nayzeee-multijob:refresh', src)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- CLOCK IN / OUT
-- ═══════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nayzeee-multijob:clockIn', function()
    local src = source
    if not Ready or not RateLimit(src, 'duty', 1000) then return end

    if Shifts[src] then
        Say(src, 'Duty', Shared.L('already_on_duty'), 'error')
        return
    end

    local info = GetFrameworkJob(src)
    if not info then return end

    local resumed = AfkPaused[src] == true
    if StartShift(src, { silent = resumed, reason = resumed and 'resumed' or nil }) and resumed then
        Say(src, 'Duty', Shared.L('afk_resumed'), 'success')
    end
end)

RegisterNetEvent('nayzeee-multijob:clockOut', function(auto)
    local src = source
    if not RateLimit(src, 'duty', 1000) then return end

    local s = Shifts[src]
    if not s then
        if auto ~= true then Say(src, 'Duty', Shared.L('not_on_duty'), 'error') end
        return
    end

    if auto == true then
        local cfg = Config.DutyTracking
        if not (cfg.enabled and cfg.autoClockOut and cfg.autoClockOut.enabled) then return end
        -- set before EndShift so the framework duty hook doesn't restart it
        if Shared.IsDefaultJob(s.job) then AfkPaused[src] = true end
        EndShift(src, 'afk')
        return
    end

    if Shared.IsDefaultJob(s.job) then
        Say(src, 'Duty', Shared.L('default_no_clockout', JobLabel(s.job)), 'error')
        return
    end

    EndShift(src, 'manual')
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER DATA
-- ═══════════════════════════════════════════════════════════════════════════

local function FormatJob(name, grade, removeable, favorite)
    local job = JobInfo[name]
    local gradeData = job and job.grades[grade]
    return {
        name = name,
        grade = grade,
        label = job and job.label or name,
        gradeLabel = gradeData and gradeData.label or ('Grade ' .. grade),
        salary = gradeData and gradeData.salary or 0,
        removeable = removeable and not Shared.IsNonRemovable(name),
        favorite = favorite,
    }
end

local function DaysList(days)
    local list = {}
    for d in tostring(days or ''):gmatch('%d') do
        list[#list + 1] = tonumber(d)
    end
    return list
end

lib.callback.register('nayzeee-multijob:getPlayerData', function(src)
    local identifier = Ready and GetIdentifier(src)
    if not identifier then
        return { jobs = {}, favorites = {}, stats = { jobs = {} }, schedules = {}, shifts = {} }
    end

    EnsureDefaultJob(identifier)

    local jobs = MySQL.query.await('SELECT job, grade, removeable, favorite FROM nayzeee_multijob WHERE identifier = ?', { identifier }) or {}
    local stats = MySQL.query.await('SELECT job, total_hours, total_earnings, sessions FROM nayzeee_multijob_stats WHERE identifier = ?', { identifier }) or {}
    local schedules = MySQL.query.await('SELECT id, job, hour, minute, days, enabled FROM nayzeee_multijob_schedules WHERE identifier = ? ORDER BY hour, minute', { identifier }) or {}
    local shifts = MySQL.query.await('SELECT id, job, clock_in, clock_out, duration_seconds, earnings FROM nayzeee_multijob_shifts WHERE identifier = ? ORDER BY clock_in DESC LIMIT 15', { identifier }) or {}

    local current = GetFrameworkJob(src) or { name = Config.DefaultJob.name, grade = Config.DefaultJob.grade or 0 }

    local formattedJobs, favorites = {}, {}
    local hasCurrent = false
    for _, row in ipairs(jobs) do
        local grade = tonumber(row.grade) or 0
        local entry = FormatJob(row.job, grade, IsTrue(row.removeable), IsTrue(row.favorite))
        formattedJobs[#formattedJobs + 1] = entry
        if entry.favorite then favorites[row.job] = true end
        if row.job == current.name then hasCurrent = true end
    end

    -- The active job isn't on the record when the list was full - still show it
    if not hasCurrent then
        local entry = FormatJob(current.name, current.grade, false, false)
        entry.untracked = true
        formattedJobs[#formattedJobs + 1] = entry
    end

    local formattedStats = { jobs = {} }
    for _, stat in ipairs(stats) do
        formattedStats.jobs[stat.job] = {
            totalHours = tonumber(stat.total_hours) or 0,
            totalEarnings = tonumber(stat.total_earnings) or 0,
            sessions = tonumber(stat.sessions) or 0,
        }
    end

    local formattedSchedules = {}
    for _, row in ipairs(schedules) do
        formattedSchedules[#formattedSchedules + 1] = {
            id = row.id,
            job = row.job,
            jobLabel = JobLabel(row.job),
            hour = tonumber(row.hour) or 0,
            minute = tonumber(row.minute) or 0,
            days = DaysList(row.days),
            enabled = IsTrue(row.enabled),
        }
    end

    local formattedShifts = {}
    for _, row in ipairs(shifts) do
        formattedShifts[#formattedShifts + 1] = {
            id = row.id,
            job = row.job,
            jobLabel = JobLabel(row.job),
            clockIn = row.clock_in,
            clockOut = row.clock_out,
            duration = tonumber(row.duration_seconds) or 0,
            earnings = tonumber(row.earnings) or 0,
        }
    end

    local s = Shifts[src]
    return {
        jobs = formattedJobs,
        favorites = favorites,
        stats = formattedStats,
        schedules = formattedSchedules,
        shifts = formattedShifts,
        currentJob = current.name,
        currentGrade = current.grade,
        isOnDuty = s ~= nil,
        dutyTime = s and (os.time() - s.startTime) or 0,
        afkPaused = AfkPaused[src] == true,
        name = GetDisplayName(src),
    }
end)

lib.callback.register('nayzeee-multijob:canOpenAdmin', function(src)
    return IsAdmin(src)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEDULES
-- ═══════════════════════════════════════════════════════════════════════════

local function ValidSchedule(identifier, data)
    if type(data) ~= 'table' or type(data.job) ~= 'string' then return nil end
    local job = data.job
    if Shared.IsBlacklisted(job) or not GetJob(job) then return nil end

    if not Shared.IsDefaultJob(job) then
        local has = MySQL.scalar.await('SELECT 1 FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, job })
        if not has then return nil end
    end

    local hour = math.floor(tonumber(data.hour) or -1)
    local minute = math.floor(tonumber(data.minute) or -1)
    -- x ~= x catches NaN, which msgpack can carry and every comparison lets through
    if hour ~= hour or minute ~= minute then return nil end
    if hour < 0 or hour > 23 or minute < 0 or minute > 59 then return nil end

    local seen, days = {}, {}
    for _, d in ipairs(type(data.days) == 'table' and data.days or {}) do
        d = math.floor(tonumber(d) or 0)
        if d >= 1 and d <= 7 and not seen[d] then
            seen[d] = true
            days[#days + 1] = d
        end
    end
    if #days == 0 then return nil end
    table.sort(days)

    return { job = job, hour = hour, minute = minute, days = table.concat(days), enabled = data.enabled ~= false }
end

lib.callback.register('nayzeee-multijob:saveSchedule', function(src, data)
    if not Config.Schedule.enabled or not RateLimit(src, 'schedule', 500) then return false end
    if not Config.Schedule.playerCanCreate then
        Say(src, 'Schedule', Shared.L('schedule_disabled'), 'error')
        return false
    end

    local identifier = GetIdentifier(src)
    if not identifier then return false end

    local s = ValidSchedule(identifier, data)
    if not s then
        Say(src, 'Schedule', Shared.L('schedule_invalid'), 'error')
        return false
    end

    local id = type(data) == 'table' and tonumber(data.id)
    if id then
        MySQL.update.await('UPDATE nayzeee_multijob_schedules SET job = ?, hour = ?, minute = ?, days = ?, enabled = ? WHERE id = ? AND identifier = ?',
            { s.job, s.hour, s.minute, s.days, s.enabled and 1 or 0, id, identifier })
    else
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_multijob_schedules WHERE identifier = ?', { identifier }) or 0
        local max = Config.Schedule.maxSchedules or 5
        if count >= max then
            Say(src, 'Schedule', Shared.L('schedule_limit', max), 'error')
            return false
        end
        MySQL.insert.await('INSERT INTO nayzeee_multijob_schedules (identifier, job, grade, hour, minute, days, enabled) VALUES (?, ?, 0, ?, ?, ?, ?)',
            { identifier, s.job, s.hour, s.minute, s.days, s.enabled and 1 or 0 })
    end

    Say(src, 'Schedule', Shared.L('schedule_saved'), 'success')
    return true
end)

lib.callback.register('nayzeee-multijob:deleteSchedule', function(src, id)
    if not RateLimit(src, 'schedule', 500) then return false end
    local identifier = GetIdentifier(src)
    if not identifier or not tonumber(id) then return false end
    MySQL.update.await('DELETE FROM nayzeee_multijob_schedules WHERE id = ? AND identifier = ?', { tonumber(id), identifier })
    Say(src, 'Schedule', Shared.L('schedule_deleted'), 'info')
    return true
end)

lib.callback.register('nayzeee-multijob:toggleSchedule', function(src, id)
    if not RateLimit(src, 'schedule', 300) then return false end
    local identifier = GetIdentifier(src)
    if not identifier or not tonumber(id) then return false end
    MySQL.update.await('UPDATE nayzeee_multijob_schedules SET enabled = IF(enabled = 1, 0, 1) WHERE id = ? AND identifier = ?', { tonumber(id), identifier })
    return true
end)

local function ProcessSchedules(now)
    local online = {}
    ForEachPlayer(function(src, player)
        local identifier = IdentifierOf(player)
        if identifier then online[identifier] = src end
    end)
    if not next(online) then return end

    local rows = MySQL.query.await('SELECT identifier, job, hour, minute, days FROM nayzeee_multijob_schedules WHERE enabled = 1') or {}
    local nowMinute = now.hour * 60 + now.min
    local before = math.floor(tonumber(Config.Schedule.notifyBefore) or 0)

    for _, row in ipairs(rows) do
        local src = online[row.identifier]
        if src then
            local target = (tonumber(row.hour) or 0) * 60 + (tonumber(row.minute) or 0)
            local days = tostring(row.days or '')
            local current = GetFrameworkJob(src)
            local already = current and current.name == row.job

            if not already then
                if target == nowMinute and days:find(tostring(now.wday), 1, true) then
                    SwitchPlayerJob(src, row.job, { scheduled = true })
                elseif before > 0 then
                    -- the reminder can land on the day before (e.g. a 00:02 switch)
                    local remind, day = target - before, now.wday
                    if remind < 0 then
                        remind = remind + 1440
                        day = now.wday % 7 + 1
                    end
                    if remind == nowMinute and days:find(tostring(day), 1, true) then
                        Say(src, 'Schedule', Shared.L('schedule_reminder', JobLabel(row.job), before), 'info')
                    end
                end
            end
        end
    end
end

-- Ticks every 10s and acts once per clock minute, so drift never skips one
local function StartScheduleChecker()
    CreateThread(function()
        local lastMinute
        while true do
            Wait(10000)
            local key = os.date('%Y%m%d%H%M')
            if key ~= lastMinute then
                lastMinute = key
                local ok, err = pcall(ProcessSchedules, os.date('*t'))
                if not ok then print('^1[nayzeee-multijob]^7 Schedule check failed: ' .. tostring(err)) end
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LEADERBOARDS
-- ═══════════════════════════════════════════════════════════════════════════

local LeaderboardCache = { at = 0, data = nil }

local function Placeholders(n)
    return string.rep('?', n, ', ')
end

local function Concat(a, b)
    local out = {}
    for _, v in ipairs(a) do out[#out + 1] = v end
    for _, v in ipairs(b) do out[#out + 1] = v end
    return out
end

local function ResolveNames(identifiers)
    local names = {}
    if #identifiers == 0 then return names end

    -- online players: use the live character name
    ForEachPlayer(function(src, player)
        local identifier = IdentifierOf(player)
        if identifier then names[identifier] = GetDisplayName(src) end
    end)

    local missing = {}
    for _, id in ipairs(identifiers) do
        if not names[id] then missing[#missing + 1] = id end
    end
    if #missing == 0 then return names end

    local ok, rows = pcall(function()
        if IsESX() then
            return MySQL.query.await(('SELECT identifier, firstname, lastname FROM users WHERE identifier IN (%s)'):format(Placeholders(#missing)), missing)
        elseif IsQB() then
            return MySQL.query.await(('SELECT citizenid AS identifier, charinfo FROM players WHERE citizenid IN (%s)'):format(Placeholders(#missing)), missing)
        end
    end)

    for _, row in ipairs(ok and rows or {}) do
        local first, last = row.firstname, row.lastname
        if row.charinfo then
            local info = type(row.charinfo) == 'string' and json.decode(row.charinfo) or row.charinfo
            if type(info) == 'table' then first, last = info.firstname, info.lastname end
        end
        local name = ((first or '') .. ' ' .. (last or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then names[row.identifier] = name end
    end

    return names
end

local function BuildLeaderboards()
    local limit = Config.Leaderboards.maxEntries or 10
    local exclude = Config.Leaderboards.excludeJobs or {}
    local where = #exclude > 0 and (' WHERE job NOT IN (%s)'):format(Placeholders(#exclude)) or ''

    local hours = MySQL.query.await(
        'SELECT identifier, SUM(total_hours) AS value FROM nayzeee_multijob_stats' .. where ..
        ' GROUP BY identifier HAVING value > 0 ORDER BY value DESC LIMIT ?', Concat(exclude, { limit })) or {}

    local earnings = MySQL.query.await(
        'SELECT identifier, SUM(total_earnings) AS value FROM nayzeee_multijob_stats' .. where ..
        ' GROUP BY identifier HAVING value > 0 ORDER BY value DESC LIMIT ?', Concat(exclude, { limit })) or {}

    local held = MySQL.query.await(
        'SELECT identifier, COUNT(*) AS value FROM nayzeee_multijob WHERE job <> ?' ..
        ' GROUP BY identifier ORDER BY value DESC LIMIT ?', { Config.DefaultJob.name, limit }) or {}

    local ids, seen = {}, {}
    for _, list in ipairs({ hours, earnings, held }) do
        for _, row in ipairs(list) do
            if not seen[row.identifier] then
                seen[row.identifier] = true
                ids[#ids + 1] = row.identifier
            end
        end
    end
    local names = ResolveNames(ids)

    local function shape(list)
        local out = {}
        for _, row in ipairs(list) do
            out[#out + 1] = { identifier = row.identifier, name = names[row.identifier] or 'Unknown worker', value = tonumber(row.value) or 0 }
        end
        return out
    end

    return { total_hours = shape(hours), total_earnings = shape(earnings), jobs_held = shape(held) }
end

lib.callback.register('nayzeee-multijob:getLeaderboards', function(src)
    if not Config.Leaderboards.enabled or not RateLimit(src, 'leaderboard', 500) then return {} end

    local ttl = Config.Leaderboards.refreshInterval or 300
    if not LeaderboardCache.data or os.time() - LeaderboardCache.at >= ttl then
        LeaderboardCache.data = BuildLeaderboards()
        LeaderboardCache.at = os.time()
    end

    -- identifiers stay on the server; the client only learns which row is theirs
    local me = GetIdentifier(src)
    local out = {}
    for board, list in pairs(LeaderboardCache.data) do
        out[board] = {}
        for i, row in ipairs(list) do
            out[board][i] = { name = row.name, value = row.value, me = row.identifier == me }
        end
    end
    return out
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- ADMIN
-- ═══════════════════════════════════════════════════════════════════════════

local function AdminPermissions(src)
    local perms = {}
    for key, value in pairs(Config.AdminPermissions or {}) do
        perms[key] = value ~= false and IsAdmin(src)
    end
    return perms
end

local function JobList()
    local list = {}
    for name, job in pairs(JobInfo) do
        if not Shared.IsBlacklisted(name) then
            local grades = {}
            for level, g in pairs(job.grades) do
                grades[#grades + 1] = { grade = level, label = g.label }
            end
            table.sort(grades, function(a, b) return a.grade < b.grade end)
            list[#list + 1] = { name = name, label = job.label, grades = grades }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

lib.callback.register('nayzeee-multijob:getAdminData', function(src)
    if not IsAdmin(src) then return nil end
    if os.time() - lastJobLoad > 30 then LoadJobInfo() end

    local perms = AdminPermissions(src)
    local data = { permissions = perms, players = {}, logs = {}, analytics = {}, jobs = JobList() }

    if perms.viewPlayers or perms.bulkOperations then
        ForEachPlayer(function(id)
            local info = GetFrameworkJob(id)
            data.players[#data.players + 1] = {
                id = id,
                name = GetDisplayName(id),
                job = info and info.name,
                jobLabel = info and JobLabel(info.name),
                grade = info and info.grade or 0,
                onDuty = Shifts[id] ~= nil,
            }
        end)
        table.sort(data.players, function(a, b) return a.id < b.id end)
    end

    if perms.viewLogs then
        data.logs = MySQL.query.await('SELECT player_name, action, job, details, admin_name, created_at FROM nayzeee_multijob_logs ORDER BY id DESC LIMIT 100') or {}
    end

    if perms.viewAnalytics then
        local topJobs = MySQL.query.await([[
            SELECT job, COUNT(DISTINCT identifier) AS players, COALESCE(SUM(total_hours), 0) AS hours
            FROM nayzeee_multijob_stats
            GROUP BY job ORDER BY hours DESC LIMIT 10
        ]]) or {}
        for _, row in ipairs(topJobs) do
            row.label = JobLabel(row.job)
            row.hours = tonumber(row.hours) or 0
            row.players = tonumber(row.players) or 0
        end

        data.analytics = {
            totalPlayers = MySQL.scalar.await('SELECT COUNT(DISTINCT identifier) FROM nayzeee_multijob') or 0,
            totalHours = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(total_hours), 0) FROM nayzeee_multijob_stats')) or 0,
            jobsInUse = MySQL.scalar.await('SELECT COUNT(DISTINCT job) FROM nayzeee_multijob WHERE job <> ?', { Config.DefaultJob.name }) or 0,
            topJobs = topJobs,
        }
    end

    return data
end)

lib.callback.register('nayzeee-multijob:adminGetPlayer', function(src, targetId)
    if not (HasPerm(src, 'viewPlayers') or HasPerm(src, 'editJobs')) then return nil end
    targetId = tonumber(targetId)
    local identifier = targetId and GetIdentifier(targetId)
    if not identifier then return nil end

    local rows = MySQL.query.await('SELECT job, grade, removeable FROM nayzeee_multijob WHERE identifier = ?', { identifier }) or {}
    local jobs = {}
    for _, row in ipairs(rows) do
        local entry = FormatJob(row.job, tonumber(row.grade) or 0, IsTrue(row.removeable), false)
        entry.isDefault = Shared.IsDefaultJob(row.job)
        jobs[#jobs + 1] = entry
    end

    local current = GetFrameworkJob(targetId)
    return {
        jobs = jobs,
        currentJob = current and current.name,
        onDuty = Shifts[targetId] ~= nil,
        canEdit = HasPerm(src, 'editJobs'),
    }
end)

local function AdminUpsertJob(identifier, jobName, grade)
    MySQL.update.await('INSERT INTO nayzeee_multijob (identifier, job, grade, removeable) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE grade = ?',
        { identifier, jobName, grade, grade })
end

-- Returns ok, reason
local function AdminApply(src, action, targetId, jobName, grade)
    targetId = tonumber(targetId)
    local identifier = targetId and GetIdentifier(targetId)
    if not identifier then return false, Shared.L('player_not_found') end
    if type(jobName) ~= 'string' or not GetJob(jobName) then return false, Shared.L('job_not_found') end
    if Shared.IsBlacklisted(jobName) then return false, Shared.L('job_blacklisted') end
    grade = math.max(0, math.floor(tonumber(grade) or 0))

    local adminId, adminName = GetIdentifier(src), GetDisplayName(src)
    local targetName = GetDisplayName(targetId)
    local current = GetFrameworkJob(targetId)

    if action == 'add' then
        if not GradeExists(jobName, grade) then return false, 'Grade ' .. grade .. ' does not exist' end
        AdminUpsertJob(identifier, jobName, grade)
        -- promote / demote straight away if it's the job they are working
        if current and current.name == jobName and current.grade ~= grade then
            SetPlayerJob(targetId, jobName, grade)
        end
        Say(targetId, 'Job', Shared.L('job_added'), 'success')
        LogAction(identifier, targetName, 'admin_add_job', jobName, 'Grade ' .. grade, adminId, adminName)

    elseif action == 'remove' then
        if Shared.IsDefaultJob(jobName) then return false, Shared.L('job_not_removable') end
        if current and current.name == jobName then
            EndShift(targetId, 'admin')
            SetPlayerJob(targetId, Config.DefaultJob.name, Config.DefaultJob.grade or 0)
        end
        MySQL.update.await('DELETE FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
        Say(targetId, 'Job', Shared.L('job_removed'), 'info')
        LogAction(identifier, targetName, 'admin_remove_job', jobName, nil, adminId, adminName)

    elseif action == 'setjob' then
        if not GradeExists(jobName, grade) then return false, 'Grade ' .. grade .. ' does not exist' end
        if not Shared.IsDefaultJob(jobName) then AdminUpsertJob(identifier, jobName, grade) end
        if not SetPlayerJob(targetId, jobName, grade) then return false, Shared.L('job_switch_failed') end
        Say(targetId, 'Job', Shared.L('job_switched', JobLabel(jobName)), 'success')
        LogAction(identifier, targetName, 'admin_set_job', jobName, 'Grade ' .. grade, adminId, adminName)

    else
        return false, 'Unknown action'
    end

    HandleJobChangeAsync(targetId)
    return true
end

lib.callback.register('nayzeee-multijob:adminAddJob', function(src, targetId, jobName, grade)
    if not HasPerm(src, 'editJobs') then return false end
    local ok, reason = AdminApply(src, 'add', targetId, jobName, grade)
    Say(src, 'Admin', ok and Shared.L('admin_done', JobLabel(jobName) .. ' added') or reason, ok and 'success' or 'error')
    return ok
end)

lib.callback.register('nayzeee-multijob:adminRemoveJob', function(src, targetId, jobName)
    if not HasPerm(src, 'editJobs') then return false end
    local ok, reason = AdminApply(src, 'remove', targetId, jobName, 0)
    Say(src, 'Admin', ok and Shared.L('admin_done', JobLabel(jobName) .. ' removed') or reason, ok and 'success' or 'error')
    return ok
end)

lib.callback.register('nayzeee-multijob:adminBulkAction', function(src, action, playerIds, jobName, grade)
    if not HasPerm(src, 'bulkOperations') then return false end
    if action ~= 'add' and action ~= 'remove' and action ~= 'setjob' then return false end
    if type(playerIds) ~= 'table' then return false end

    local done, total, lastError = 0, 0, nil
    for i, targetId in ipairs(playerIds) do
        if i > 128 then break end
        total = total + 1
        local ok, reason = AdminApply(src, action, targetId, jobName, grade)
        if ok then done = done + 1 else lastError = reason end
    end

    Say(src, 'Admin', Shared.L('admin_bulk_done', done, total) .. (lastError and (' · ' .. lastError) or ''), done > 0 and 'success' or 'error')
    return done > 0
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- PLAYER DISCONNECT / RESOURCE STOP
-- ═══════════════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local src = source
    EndShift(src, 'disconnect')
    AfkPaused[src] = nil
    RateTimes[src] = nil
end)

local RESUME_KEY = 'nayzeee_multijob_resume'

-- Close every shift cleanly and remember who was working, so a resource
-- restart doesn't silently clock the whole server out
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local resume = { at = os.time(), players = {} }
    for src, s in pairs(Shifts) do
        resume.players[s.identifier] = s.job
        EndShift(src, 'restart')
    end
    SetResourceKvp(RESUME_KEY, json.encode(resume))
end)

local function ResumeAfterRestart()
    local raw = GetResourceKvpString(RESUME_KEY)
    DeleteResourceKvp(RESUME_KEY)
    if not raw then return end

    local resume = json.decode(raw)
    if type(resume) ~= 'table' or type(resume.players) ~= 'table' then return end
    if os.time() - (tonumber(resume.at) or 0) > 600 then return end

    ForEachPlayer(function(src, player)
        local job = resume.players[IdentifierOf(player)]
        local info = GetFrameworkJob(src)
        if job and info and info.name == job then
            StartShift(src, { silent = true, reason = 'resumed after restart' })
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DATABASE
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_multijob` (
            `identifier` VARCHAR(60) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `grade` INT DEFAULT 0,
            `removeable` TINYINT(1) DEFAULT 1,
            `favorite` TINYINT(1) DEFAULT 0,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `job`),
            INDEX `idx_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_multijob_stats` (
            `identifier` VARCHAR(60) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `total_hours` FLOAT DEFAULT 0,
            `total_earnings` INT DEFAULT 0,
            `sessions` INT DEFAULT 0,
            `last_clocked` TIMESTAMP NULL,
            PRIMARY KEY (`identifier`, `job`),
            INDEX `idx_hours` (`total_hours`),
            INDEX `idx_earnings` (`total_earnings`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_multijob_logs` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `player_name` VARCHAR(100),
            `action` VARCHAR(50) NOT NULL,
            `job` VARCHAR(50),
            `details` TEXT,
            `admin_id` VARCHAR(60),
            `admin_name` VARCHAR(100),
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_identifier` (`identifier`),
            INDEX `idx_action` (`action`),
            INDEX `idx_created` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_multijob_shifts` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `clock_in` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `clock_out` TIMESTAMP NULL,
            `duration_seconds` INT DEFAULT 0,
            `earnings` INT DEFAULT 0,
            INDEX `idx_identifier` (`identifier`),
            INDEX `idx_job` (`job`),
            INDEX `idx_open` (`clock_out`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nayzeee_multijob_schedules` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `identifier` VARCHAR(60) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `grade` INT DEFAULT 0,
            `hour` INT NOT NULL,
            `minute` INT NOT NULL,
            `days` VARCHAR(20) NOT NULL,
            `enabled` TINYINT(1) DEFAULT 1,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

-- Older installs created clock_in as plain 'TIMESTAMP NOT NULL'. On MariaDB and
-- MySQL 5.7 that silently adds ON UPDATE CURRENT_TIMESTAMP, so every update to
-- a shift reset its clock-in time to now. Strip that attribute once.
local function MigrateTables()
    local ok, extra = pcall(MySQL.scalar.await, [[
        SELECT EXTRA FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'nayzeee_multijob_shifts' AND COLUMN_NAME = 'clock_in'
    ]])
    if ok and extra and tostring(extra):lower():find('on update', 1, true) then
        MySQL.query.await('ALTER TABLE `nayzeee_multijob_shifts` MODIFY `clock_in` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
        print('^3[nayzeee-multijob]^7 Fixed shift clock-in column (removed ON UPDATE CURRENT_TIMESTAMP)')
    end
end

-- Shifts still open from a crash: close them at their last saved length and
-- credit the hours that were actually recorded
local function RecoverOpenShifts()
    local open = MySQL.query.await('SELECT id, identifier, job, duration_seconds, earnings FROM nayzeee_multijob_shifts WHERE clock_out IS NULL') or {}
    local estimate = EarningsMode() == 'estimate'

    for _, row in ipairs(open) do
        local duration = tonumber(row.duration_seconds) or 0
        local hours = duration / 3600
        local earnings = estimate and (tonumber(row.earnings) or 0) or 0
        MySQL.update.await('UPDATE nayzeee_multijob_shifts SET clock_out = DATE_ADD(clock_in, INTERVAL ? SECOND) WHERE id = ?', { duration, row.id })
        MySQL.update.await('INSERT INTO nayzeee_multijob_stats (identifier, job, total_hours, total_earnings, sessions) VALUES (?, ?, ?, ?, 0) ON DUPLICATE KEY UPDATE total_hours = total_hours + ?, total_earnings = total_earnings + ?',
            { row.identifier, row.job, hours, earnings, hours, earnings })
    end

    if #open > 0 then
        print(('^3[nayzeee-multijob]^7 Closed ^5%d^7 shift(s) left open by a crash'):format(#open))
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1000)

    print('^2')
    print('    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗')
    print('    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝')
    print('    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗  ')
    print('    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝  ')
    print('    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗')
    print('    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝')
    print('^7')
    print('^5    NAYZEEE MULTIJOB ^7| ^3v' .. VERSION .. ' ^7| ^5discord.gg/nayzeeedev^7')
    print('')

    local fw = Shared.GetFramework()
    if fw == 'standalone' then
        print('^1[nayzeee-multijob]^7 No supported framework found (ESX, QBCore, QBox). The resource is idle.')
        return
    end

    CreateTables()
    MigrateTables()
    RecoverOpenShifts()

    local count = LoadJobInfo()
    print(('^2[nayzeee-multijob]^7 Loaded ^5%d^7 jobs from ^5%s^7 | earnings: ^3%s^7'):format(count, fw, EarningsMode()))

    Ready = true
    ResumeAfterRestart()

    -- players already in the server (resource restart)
    ForEachPlayer(function(src) HandleJobChangeAsync(src, 'load') end)

    StartShiftSaver()
    if Config.Schedule and Config.Schedule.enabled then
        StartScheduleChecker()
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local function IsOnDuty(src)
    src = tonumber(src)
    local s = src and Shifts[src]
    if not s then return false end

    -- job changed without a hook firing: never pay the old shift
    local info = GetFrameworkJob(src)
    if info and info.name ~= s.job then
        EndShift(src, 'jobchange')
        HandleJobChangeAsync(src)
        return false
    end
    return true
end

exports('IsPlayerOnDuty', IsOnDuty)

exports('GetDutyTime', function(src)
    local s = Shifts[tonumber(src) or -1]
    return s and (os.time() - s.startTime) or 0
end)

exports('ClockIn', function(src)
    return StartShift(tonumber(src))
end)

exports('ClockOut', function(src)
    return EndShift(tonumber(src), 'manual')
end)

exports('SwitchJob', function(src, jobName)
    return SwitchPlayerJob(tonumber(src), jobName, { ignoreCooldown = true })
end)

exports('GetPlayerJobs', function(src)
    local identifier = GetIdentifier(src)
    if not identifier then return {} end
    return MySQL.query.await('SELECT job, grade, removeable, favorite FROM nayzeee_multijob WHERE identifier = ?', { identifier }) or {}
end)

exports('AddPlayerJob', function(src, jobName, grade)
    local identifier = GetIdentifier(src)
    grade = math.max(0, math.floor(tonumber(grade) or 0))
    if not identifier or not GetJob(jobName) or Shared.IsBlacklisted(jobName) or not GradeExists(jobName, grade) then return false end
    AdminUpsertJob(identifier, jobName, grade)
    TriggerClientEvent('nayzeee-multijob:refresh', src)
    return true
end)

exports('RemovePlayerJob', function(src, jobName)
    local identifier = GetIdentifier(src)
    if not identifier or type(jobName) ~= 'string' or Shared.IsDefaultJob(jobName) then return false end
    MySQL.update.await('DELETE FROM nayzeee_multijob WHERE identifier = ? AND job = ?', { identifier, jobName })
    TriggerClientEvent('nayzeee-multijob:refresh', src)
    return true
end)

exports('GetJobHours', function(src, jobName)
    local identifier = GetIdentifier(src)
    if not identifier then return 0 end
    return tonumber(MySQL.scalar.await('SELECT total_hours FROM nayzeee_multijob_stats WHERE identifier = ? AND job = ?', { identifier, jobName })) or 0
end)

exports('GetJobEarnings', function(src, jobName)
    local identifier = GetIdentifier(src)
    if not identifier then return 0 end
    return tonumber(MySQL.scalar.await('SELECT total_earnings FROM nayzeee_multijob_stats WHERE identifier = ? AND job = ?', { identifier, jobName })) or 0
end)

-- Call from any paycheck loop: exports['nayzeee-multijob']:TrackPaycheck(src, amount)
exports('TrackPaycheck', function(src, amount, jobName)
    return TrackPaycheck(src, amount, jobName)
end)

exports('IsAdmin', IsAdmin)
