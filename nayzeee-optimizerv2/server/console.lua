-----------------------------------------------------------------
-- Console
--
-- Everything this script says while the server starts (dependencies,
-- database, what it restored, warnings) is collected and printed as ONE
-- block under the banner, instead of scattered through the server log.
-- After that every line goes out the same way:
--   [NayZeee Optimizer] WARN  something to look at
--
--   Console.wait(task)                     a startup step is still running
--   Console.done(task)                     ...and finished
--   Console.check(key, level, label, text) a row in the Server section
--   Console.log(level, text, ...)          anything else (format string)
-- levels: 'ok', 'info', 'warn', 'error'
-----------------------------------------------------------------

Console = {}

local RESOURCE = GetCurrentResourceName()
local NAME     = 'NayZeee Optimizer'   -- CHANGE: this script's display name
local VERSION  = GetResourceMetadata(RESOURCE, 'version', 0) or '1.0.0'
local ABOUT    = 'FPS boost, kill & hit effects, server performance tracker'  -- CHANGE

local LEVEL = {
    ok    = '^2 OK   ',
    info  = '^5 INFO ',
    warn  = '^3 WARN ',
    error = '^1 FAIL ',
}

-- the order rows appear in, whatever order the checks finish in
local ORDER = { 'lock', 'config', 'admin', 'perms', 'monitor', 'profiler', 'probe', 'telemetry', 'discord', 'update' } -- CHANGE: add this script's row keys in display order
local rank = {}
for i, k in ipairs(ORDER) do rank[k] = i end

local started = GetGameTimer()
local rows, notes, pending = {}, {}, {}
local flushed = false
local nextRank = #ORDER

local function pad(s, n)
    s = tostring(s)
    return s .. string.rep(' ', math.max(0, n - #s))
end

local WIDTH = 66 -- where every rule line ends

--- '   ┌─ Title ───────' padded with ─ out to WIDTH (colour codes don't count)
local function rule(corner, title)
    local head = ('^5   %s─ %s ^5'):format(corner, title)
    local visible = utf8.len((head:gsub('%^%d', ''))) or #head
    return head .. string.rep('─', math.max(3, WIDTH - visible))
end

local function line(level, text)
    return ('^5[%s]^7%s^7%s^0'):format(NAME, LEVEL[level] or LEVEL.info, text)
end

local function flush()
    if flushed then return end
    flushed = true

    table.sort(rows, function(a, b) return a.rank < b.rank end)
    local worst = 'ok'
    for _, r in ipairs(rows) do
        if r.level == 'error' then worst = 'error' elseif r.level == 'warn' and worst ~= 'error' then worst = 'warn' end
    end
    for _, n in ipairs(notes) do
        if n.level == 'error' then worst = 'error' elseif n.level == 'warn' and worst ~= 'error' then worst = 'warn' end
    end

    local out = {
        '',
        '^5   ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗',
        '^5   ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝',
        '^5   ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗',
        '^5   ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝',
        '^5   ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗',
        '^5   ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝',
        ('^7   %s ^5v%s  ^7%s'):format(NAME, VERSION, ABOUT),
        '',
        rule('┌', '^7About'),
        ('^5   │ ^7%s^5NayZeee Development'):format(pad('Developer', 13)),
        ('^5   │ ^7%s^5discord.gg/nayzeeedev'):format(pad('Discord', 13)),
        ('^5   │ ^7%s^5%s'):format(pad('Resource', 13), RESOURCE),
        rule('├', '^7Server'),
    }
    for _, r in ipairs(rows) do
        out[#out + 1] = ('^5   │%s^7%s^7%s'):format(LEVEL[r.level] or LEVEL.info, pad(r.label, 15), r.text)
    end
    if #notes > 0 then
        out[#out + 1] = rule('├', '^7Notes')
        for _, n in ipairs(notes) do
            out[#out + 1] = ('^5   │%s^7%s'):format(LEVEL[n.level] or LEVEL.info, n.text)
        end
    end
    local took = (GetGameTimer() - started) / 1000
    local status = ({ ok = '^2Ready', warn = '^3Ready, with warnings', error = '^1Started with errors' })[worst]
    out[#out + 1] = rule('└', ('%s ^7in %.1fs'):format(status, took))
    out[#out + 1] = '^0'
    print(table.concat(out, '\n'))
end

--- A startup step that has to finish before the block prints.
function Console.wait(task) pending[task] = true end

--- That step is done; prints the block once nothing is left running.
function Console.done(task)
    pending[task] = nil
    if not flushed and next(pending) == nil then SetTimeout(0, flush) end
end

--- A row in the Server section. `key` places it (see ORDER); text is plain.
function Console.check(key, level, label, text)
    local r = { rank = rank[key], level = level, label = label, text = text or '' }
    if not r.rank then nextRank = nextRank + 1; r.rank = nextRank end
    for i, old in ipairs(rows) do
        if old.label == label then rows[i] = r return end
    end
    rows[#rows + 1] = r
    if flushed then print(line(level, ('%s: %s'):format(label, text or ''))) end
end

--- Anything else. Before the block prints it lands under Notes, after
--- that it prints straight away with the script's prefix.
function Console.log(level, text, ...)
    if select('#', ...) > 0 then text = text:format(...) end
    if flushed then
        print(line(level, text))
    else
        notes[#notes + 1] = { level = level, text = text }
    end
end

-----------------------------------------------------------------
-- the checks that need nothing but the server itself
-----------------------------------------------------------------

local function dep(key, res, required, missingText)
    local state = GetResourceState(res)
    if state == 'started' or state == 'starting' then
        Console.check(key, 'ok', res, 'started')
    else
        Console.check(key, required and 'error' or 'warn', res, missingText or state)
    end
end

-- CHANGE: only the resources THIS script uses; required = true if it can't work without it
-- The optimizer has no resource dependencies (no ox_lib, no database).

-- Add this script's own instant checks here (framework, config sanity, ...):

-- Config sanity: every problem says what is wrong and how to fix it.
do
    local problems = {}
    local function bad(fmt, ...) problems[#problems + 1] = fmt:format(...) end
    local defaults = Config.DefaultSettings or {}

    for key, value in pairs(Config.Locked or {}) do
        if defaults[key] == nil then
            bad('Config.Locked.%s is not a setting: remove it or fix the spelling', key)
        elseif type(value) ~= type(defaults[key]) then
            bad('Config.Locked.%s must be %s, not %s', key, type(defaults[key]), type(value))
        end
    end

    for name, preset in pairs(Config.Presets or {}) do
        for key in pairs(preset) do
            if defaults[key] == nil then
                bad('preset "%s" sets unknown option %s: remove it from Config.Presets', name, key)
            end
        end
    end

    local th = Config.Health and Config.Health.thresholds or {}
    for _, name in ipairs({ 'clientMs', 'serverPct', 'hitchRate' }) do
        local t = th[name]
        if t and not (t.excellent < t.good and t.good < t.ok and t.ok < t.poor) then
            bad('Config.Health.thresholds.%s must go up: excellent < good < ok < poor', name)
        end
    end
    local low = th.clientLow
    if low and not (low.excellent > low.good and low.good > low.ok and low.ok > low.poor) then
        bad('Config.Health.thresholds.clientLow must go down: excellent > good > ok > poor')
    end

    if Config.Probe and (tonumber(Config.Probe.reportInterval) or 5) < 2 then
        bad('Config.Probe.reportInterval is below 2 seconds: the probe will use 2')
    end

    if #problems == 0 then
        Console.check('config', 'ok', 'Config', 'settings valid')
    else
        Console.check('config', 'warn', 'Config', ('%d problem(s): %s'):format(#problems, problems[1]))
        for i = 2, #problems do Console.log('warn', problems[i]) end
    end
end

-- Who can open the Health tab and use the admin commands
do
    local a = Config.Admin or {}
    local ace = a.ace or 'optimizer.admin'
    local ways = {}
    if type(IsPrincipalAceAllowed) == 'function' and IsPrincipalAceAllowed('group.admin', ace) then ways[#ways + 1] = 'group.admin ace' end
    if a.commandAce ~= false then ways[#ways + 1] = "'command' ace" end
    if a.frameworkAdmins ~= false then ways[#ways + 1] = 'framework admins' end
    if a.txAdmin ~= false then ways[#ways + 1] = 'txAdmin' end
    if type(a.identifiers) == 'table' and #a.identifiers > 0 then ways[#ways + 1] = ('%d listed id(s)'):format(#a.identifiers) end
    if #ways == 0 then
        Console.check('admin', 'warn', 'Admin access',
            ('nobody can open the Health tab: add "add_ace group.admin %s allow" to server.cfg or list ids in Config.Admin.identifiers'):format(ace))
    else
        Console.check('admin', 'ok', 'Admin access', table.concat(ways, ', ') .. ' (check a player with optimizeradmin <id>)')
    end
end

-- Deep scan needs the FXServer profiler natives
if type(ProfilerIsRecording) == 'function' then
    Console.check('profiler', 'ok', 'Deep scan', 'profiler ready, run optimizerscan')
else
    Console.check('profiler', 'warn', 'Deep scan', 'profiler natives missing: update your server artifacts')
end

-- Client telemetry feeding the Health tab
do
    local h = Config.Health or {}
    if h.enabled and h.clientTelemetry then
        Console.check('telemetry', 'info', 'Telemetry', ('players report every %ds, they can opt out in the menu'):format(h.clientReportInterval or 60))
    else
        Console.check('telemetry', 'info', 'Telemetry', 'off: the All clients view stays empty')
    end
end

-- Discord alerts
do
    local hook = Config.Server and Config.Server.discordWebhook or ''
    if hook == '' then
        Console.check('discord', 'info', 'Discord', 'alerts off: set Config.Server.discordWebhook')
    elseif hook:find('^https://discord%.com/api/webhooks/') or hook:find('^https://discordapp%.com/api/webhooks/') or hook:find('^https://%a+%.discord%.com/api/webhooks/') then
        Console.check('discord', 'ok', 'Discord', 'alerts on')
    else
        Console.check('discord', 'warn', 'Discord', 'webhook is not a Discord webhook URL: check Config.Server.discordWebhook')
    end
end

-- nothing left waiting (or something hung): print anyway after 15s
CreateThread(function()
    Wait(0)
    if next(pending) == nil then return flush() end
    Wait(15000)
    if not flushed then
        for task in pairs(pending) do Console.log('warn', 'startup step "%s" took too long', task) end
        flush()
    end
end)
