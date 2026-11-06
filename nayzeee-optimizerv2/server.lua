--[[
    NAYZEEE OPTIMIZER - Server
    Version: see fxmanifest.lua

    Server-side performance tracker:
      - tick / hitch detection (wall clock, works on Linux and Windows)
      - process memory (Linux RSS, Lua heap fallback on Windows)
      - per-resource grades from three sources:
          probe reports (probe.lua inside each Lua resource, server + client)
          profiler deep scan (built-in FXServer profiler, every runtime)
          client telemetry (FPS + per-resource client load across players)
      - probe installer / remover
      - admin layer: Health tab data, preset push, ACE gated
      - update checker, Discord alerts

    NOTE: For deep sync/network hitch attribution with automatic profiler
    trace capture, pair this with nayzeee-hitchwatch.
]]

-- Resource name lock (see lock.lua). Fails closed.
if type(NayZeeeResourceLock) ~= 'function' then
    -- Report it in the startup block, then stop once the block has printed.
    Console.check('lock', 'error', 'Resource lock', 'lock.lua is missing from fxmanifest.lua: restore it and restart')
    SetTimeout(1000, function() StopResource(GetCurrentResourceName()) end)
    return
end

if not NayZeeeResourceLock() then
    return
end

local RES = GetCurrentResourceName()
local VERSION = GetResourceMetadata(RES, 'version', 0) or '1.0.0'

local cfg    = Config.Server or { enabled = false }
local hcfg   = Config.Health or { enabled = false }
local pcfg   = Config.Probe or { enabled = false }
local acfg   = Config.Admin or { ace = 'optimizer.admin' }

local hitchCount = 0
local severeHitchCount = 0
local worstHitch = 0
local driftSum, driftSamples = 0, 0
local lastSevereAt = 0
local hitchByPlayerCount = {}
local memorySamples = {}
local monitorStart = os.time()

-- 60 one-minute buckets of hitch counts (ring)
local timeline = {}
for i = 1, 60 do timeline[i] = { h = 0, s = 0 } end
local timelineMinute = math.floor(os.time() / 60)

-- Server-side probe reports: res -> { r = report, at = os.time() }
local probeServer = {}
local probeMem = {}        -- res -> { t0, m0 }

-- Client telemetry: src -> record
local clients = {}
local lastTelemetry = {}

-- Profiler scan
local scan = { status = 'idle', at = 0, frames = 0, rows = nil, error = nil }

-- Update checker
local update = { current = VERSION, latest = nil, outdated = false, url = nil, notes = nil, checked = 0 }

-- Discord per-key cooldowns
local alertAt = {}

-- Health request cooldown per admin
local lastHealthRequest = {}

-- ═══════════════════════════════════════════════════════════════════════════════
--  HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════

local function GetPlayerCount()
    return #GetPlayers()
end

-- txAdmin tells resources who is logged in as an admin in game
local txAdmins = {}

local ADMIN_GROUPS = { admin = true, superadmin = true, owner = true, developer = true, god = true }

-- Every reason this player counts as an admin (empty = not an admin)
local function AdminReasons(src)
    local why = {}
    local ace = acfg.ace or 'optimizer.admin'
    if IsPlayerAceAllowed(src, ace) then why[#why + 1] = ('ace %s'):format(ace) end
    if acfg.commandAce ~= false and IsPlayerAceAllowed(src, 'command') then why[#why + 1] = "ace 'command'" end
    if acfg.frameworkAdmins ~= false then
        -- qb-core and qbx_core permissions are aces named after the level
        if IsPlayerAceAllowed(src, 'god') or IsPlayerAceAllowed(src, 'admin') then
            why[#why + 1] = 'qb/qbx admin permission'
        end
        if GetResourceState('es_extended') == 'started' then
            local ok, group = pcall(function()
                local ESX = exports.es_extended:getSharedObject()
                local xPlayer = ESX and ESX.GetPlayerFromId(src)
                return xPlayer and xPlayer.getGroup and xPlayer.getGroup()
            end)
            if ok and type(group) == 'string' and ADMIN_GROUPS[group] then why[#why + 1] = ('ESX group %s'):format(group) end
        end
    end
    if acfg.txAdmin ~= false and txAdmins[src] then why[#why + 1] = 'txAdmin login' end
    if type(acfg.identifiers) == 'table' and #acfg.identifiers > 0 then
        local wanted = {}
        for _, v in ipairs(acfg.identifiers) do wanted[tostring(v):lower()] = true end
        for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
            if wanted[id:lower()] then why[#why + 1] = ('listed identifier %s'):format(id) break end
        end
    end
    return why
end

local function IsAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end
    return #AdminReasons(src) > 0
end

AddEventHandler('txAdmin:events:adminAuth', function(data)
    if type(data) ~= 'table' then return end
    local id = tonumber(data.netid)
    if not id or id < 0 then txAdmins = {} return end
    txAdmins[id] = data.isAdmin == true
    TriggerClientEvent('nayzeee-optimizer:admin:result', id, IsAdmin(id))
end)

AddEventHandler('playerDropped', function() txAdmins[source] = nil end)

-- Can this resource run a restricted console command (refresh, profiler)?
local function CanRunCommand(cmd)
    return IsPrincipalAceAllowed('resource.' .. GetCurrentResourceName(), 'command.' .. cmd)
end
local ACE_FIX = ('add "add_ace resource.%s command allow" to server.cfg'):format(GetCurrentResourceName())

local function SendDiscord(title, description, color, key, cooldown)
    if not cfg.discordWebhook or cfg.discordWebhook == '' then return end
    key = key or 'default'
    local now = os.time()
    if now - (alertAt[key] or 0) < (cooldown or cfg.alertCooldown or 300) then return end
    alertAt[key] = now

    PerformHttpRequest(cfg.discordWebhook, function() end, 'POST', json.encode({
        username = 'Optimizer Monitor',
        embeds = { {
            title = title,
            description = description,
            color = color or 8564130,
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') },
        } },
    }), { ['Content-Type'] = 'application/json' })
end

-- Real process memory on Linux. FiveM gives Lua no process API on Windows.
local function ProcessMemoryMB()
    if io and io.open then
        local f = io.open('/proc/self/statm', 'r')
        if f then
            local line = f:read('*l')
            f:close()
            local rss = line and line:match('^%d+%s+(%d+)')
            if rss then
                return math.floor(tonumber(rss) * 4096 / 1048576), 'Process RSS'
            end
        end
    end
    return math.floor(collectgarbage('count') / 1024), 'Lua heap (optimizer only)'
end

local function ParseVersion(v)
    local out = {}
    for n in tostring(v or ''):gmatch('%d+') do out[#out + 1] = tonumber(n) end
    return out
end

local function IsNewer(latest, current)
    local a, b = ParseVersion(latest), ParseVersion(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x > y then return true end
        if x < y then return false end
    end
    return false
end

local function Round(v, d)
    local m = 10 ^ (d or 1)
    return math.floor((v or 0) * m + 0.5) / m
end

local function Median(list)
    local n = #list
    if n == 0 then return 0 end
    table.sort(list)
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return (list[n / 2] + list[n / 2 + 1]) / 2
end

local function AllResources()
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local n = GetResourceByFindIndex(i)
        if n then list[#list + 1] = n end
    end
    return list
end

-- Startup row: what the server monitor watches
if not cfg.enabled then
    Console.check('monitor', 'info', 'Monitoring', 'off: Config.Server.enabled is false')
else
    local _, memLabel = ProcessMemoryMB()
    local parts = {}
    if cfg.tickMonitor then parts[#parts + 1] = ('hitches over %d ms'):format(cfg.hitchThreshold or 150) end
    if cfg.memoryMonitor then
        parts[#parts + 1] = memLabel == 'Process RSS' and 'process memory' or 'Lua heap only (Windows has no process memory)'
    end
    if #parts == 0 then parts[1] = 'reports only' end
    Console.check('monitor', 'ok', 'Monitoring', ('%s, report every %d min'):format(table.concat(parts, ' + '), cfg.reportInterval or 15))
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  TICK / HITCH MONITOR (wall clock)
-- ═══════════════════════════════════════════════════════════════════════════════

local function TimelineTick()
    local m = math.floor(os.time() / 60)
    while timelineMinute < m do
        timelineMinute = timelineMinute + 1
        table.remove(timeline, 1)
        timeline[#timeline + 1] = { h = 0, s = 0 }
    end
end

CreateThread(function()
    if not cfg.enabled or not cfg.tickMonitor then return end

    local interval = cfg.tickInterval or 1000
    local threshold = cfg.hitchThreshold or 150
    local severe = cfg.severeHitchThreshold or 500

    Wait(10000)
    local last = GetGameTimer()

    while true do
        Wait(interval)

        local now = GetGameTimer()
        local drift = (now - last) - interval
        last = now
        if drift < 0 then drift = 0 end

        driftSum = driftSum + drift
        driftSamples = driftSamples + 1
        TimelineTick()

        if drift > threshold then
            hitchCount = hitchCount + 1
            timeline[60].h = timeline[60].h + 1
            local players = GetPlayerCount()

            hitchByPlayerCount[players] = (hitchByPlayerCount[players] or 0) + 1
            if drift > worstHitch then worstHitch = drift end

            if drift > severe then
                severeHitchCount = severeHitchCount + 1
                timeline[60].s = timeline[60].s + 1
                lastSevereAt = os.time()
                Console.log('warn', 'Severe hitch: %.0f ms drift, %d players online', drift, players)
                SendDiscord(
                    'Severe Server Hitch',
                    ('**Drift:** %.0fms\n**Players online:** %d\n**Total hitches this session:** %d\n\nRun `optimizerhealth` in console for the full report.'):format(drift, players, hitchCount),
                    15158332, 'hitch'
                )
            else
                Console.log('info', 'Hitch: %.0f ms drift, %d players online', drift, players)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  MEMORY MONITOR
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    if not cfg.enabled or not cfg.memoryMonitor then return end

    local interval = (cfg.memoryInterval or 60) * 1000
    local maxSamples = cfg.memorySamples or 30
    local leakThreshold = cfg.leakGrowthMB or 100

    Wait(30000)

    while true do
        local memory, label = ProcessMemoryMB()
        memorySamples[#memorySamples + 1] = memory

        if #memorySamples > maxSamples then
            table.remove(memorySamples, 1)
        end

        if #memorySamples >= maxSamples then
            local third = math.floor(maxSamples / 3)
            local earlySum, lateSum = 0, 0
            for i = 1, third do earlySum = earlySum + memorySamples[i] end
            for i = #memorySamples - third + 1, #memorySamples do lateSum = lateSum + memorySamples[i] end
            local growth = (lateSum / third) - (earlySum / third)

            if growth > leakThreshold then
                Console.log('warn', 'Memory grew +%.0f MB over the sample window (%s now %d MB): check the Health tab for the resource', growth, label, memory)
                SendDiscord(
                    'Possible Memory Leak',
                    ('**Growth:** +%.0f MB across the sample window\n**%s:** %d MB\n\nA resource may be leaking. Check the Health tab for per-resource memory growth.'):format(growth, label, memory),
                    16098851, 'memory'
                )
                memorySamples = {}
            end
        end

        Wait(interval)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  PROBE REPORTS (server side resources)
-- ═══════════════════════════════════════════════════════════════════════════════

AddEventHandler('nayzeee-optimizer:probe:report', function(r)
    -- Local event only: never registered as a net event, so clients cannot
    -- spoof it. `source` is empty for resource-to-resource triggers.
    if type(r) ~= 'table' or type(r.res) ~= 'string' or r.side ~= 'server' then return end
    local now = os.time()
    probeServer[r.res] = { r = r, at = now }
    local mem = tonumber(r.mem)
    if mem and not probeMem[r.res] then
        probeMem[r.res] = { t0 = now, m0 = mem }
    end
end)

local function MemGrowthMBph(res, memKB)
    local h = probeMem[res]
    if not h or not memKB then return nil end
    local hours = (os.time() - h.t0) / 3600
    if hours < (10 / 60) then return nil end
    return ((memKB - h.m0) / 1024) / hours
end

local function BuildServerProbeRows()
    local rows = {}
    local now = os.time()
    local maxAge = ((pcfg.reportInterval or 5) * 4)
    for name, e in pairs(probeServer) do
        if now - e.at > maxAge then
            probeServer[name] = nil
        else
            local r = e.r
            local win = tonumber(r.win) or 5
            local ms = tonumber(r.ms) or 0
            local row = {
                name      = name,
                side      = 'server',
                source    = 'probe',
                load      = (ms / (win * 1000)) * 100,       -- % of main thread
                msPerSec  = ms / win,
                peakMs    = tonumber(r.peak) or 0,
                slicesPs  = (tonumber(r.slices) or 0) / win,
                eventsPs  = (tonumber(r.events) or 0) / win,
                memMB     = (tonumber(r.mem) or 0) / 1024,
                memGrowth = MemGrowthMBph(name, tonumber(r.mem)),
                longSlices = tonumber(r.long) or 0,
            }
            row.grade, row.verdict, row.hints = NZGrade.resource(row)
            rows[#rows + 1] = row
        end
    end
    return rows
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  CLIENT TELEMETRY
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nayzeee-optimizer:telemetry', function(payload)
    local src = source
    if not hcfg.enabled or not hcfg.clientTelemetry then return end
    if type(payload) ~= 'table' then return end

    local now = os.time()
    local minGap = math.max(10, (hcfg.clientReportInterval or 60) - 10)
    if now - (lastTelemetry[src] or 0) < minGap then return end
    lastTelemetry[src] = now

    local function num(v, lo, hi)
        v = tonumber(v)
        if not v or v ~= v or v < lo or v > hi then return nil end
        return v
    end

    local rec = {
        at     = now,
        fps    = num(payload.fps, 0, 1000) or 0,
        low    = num(payload.low, 0, 1000) or 0,
        maxFt  = num(payload.maxFt, 0, 100000) or 0,
        tier   = tostring(payload.tier or ''):sub(1, 16),
        gpu    = tostring(payload.gpu or ''):sub(1, 80),
        preset = tostring(payload.preset or ''):sub(1, 24),
        probes = num(payload.probes, 0, 10000) or 0,
        res    = {},
    }

    local maxRes = hcfg.maxResourcesPerReport or 40
    if type(payload.res) == 'table' then
        for i, r in ipairs(payload.res) do
            if i > maxRes then break end
            if type(r) == 'table' and type(r.n) == 'string' and #r.n <= 64 then
                rec.res[#rec.res + 1] = {
                    n = r.n,
                    l = num(r.l, 0, 10000) or 0,
                    p = num(r.p, 0, 100000) or 0,
                    o = num(r.o, 0, 10000) or 0,
                    e = num(r.e, 0, 100000) or 0,
                    m = num(r.m, 0, 100000) or 0,
                    g = num(r.g, -100000, 100000),
                }
            end
        end
    end

    clients[src] = rec
end)

AddEventHandler('playerDropped', function()
    clients[source] = nil
    lastTelemetry[source] = nil
    lastHealthRequest[source] = nil
end)

local function BuildClientAggregate()
    local now = os.time()
    local maxAge = (hcfg.clientReportInterval or 60) * 3
    local fpsSum, lowSum, n, under30, under45 = 0, 0, 0, 0, 0
    local perRes = {}
    local tiers = {}

    for src, rec in pairs(clients) do
        if now - rec.at > maxAge then
            clients[src] = nil
        else
            n = n + 1
            fpsSum = fpsSum + rec.fps
            lowSum = lowSum + rec.low
            if rec.fps < 30 then under30 = under30 + 1 end
            if rec.fps < 45 then under45 = under45 + 1 end
            if rec.tier ~= '' then tiers[rec.tier] = (tiers[rec.tier] or 0) + 1 end
            for _, r in ipairs(rec.res) do
                local p = perRes[r.n]
                if not p then
                    p = { loads = {}, loops = {}, events = {}, mems = {}, peak = 0, growth = nil }
                    perRes[r.n] = p
                end
                p.loads[#p.loads + 1] = r.l
                p.loops[#p.loops + 1] = r.o
                p.events[#p.events + 1] = r.e
                p.mems[#p.mems + 1] = r.m
                if r.p > p.peak then p.peak = r.p end
                if r.g and (not p.growth or r.g > p.growth) then p.growth = r.g end
            end
        end
    end

    local rows = {}
    for name, p in pairs(perRes) do
        local row = {
            name      = name,
            side      = 'client',
            source    = 'clients',
            clients   = #p.loads,
            load      = Median(p.loads),
            maxLoad   = p.loads[#p.loads],   -- sorted by Median()
            peakMs    = p.peak,
            loops     = Median(p.loops),
            eventsPs  = Median(p.events),
            memMB     = Median(p.mems),
            memGrowth = p.growth,
        }
        row.grade, row.verdict, row.hints = NZGrade.resource(row)
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.load > b.load end)

    return {
        reporting = n,
        players   = GetPlayerCount(),
        fpsAvg    = n > 0 and Round(fpsSum / n, 0) or 0,
        lowAvg    = n > 0 and Round(lowSum / n, 0) or 0,
        under30   = n > 0 and Round(under30 / n * 100, 0) or 0,
        under45   = n > 0 and Round(under45 / n * 100, 0) or 0,
        tiers     = tiers,
        rows      = rows,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  PROFILER DEEP SCAN
--  Uses the built-in FXServer profiler: `profiler record N` then
--  `profiler saveJSON <file>`. The JSON is Chrome trace format; resource
--  entries are named "tick (resname)" / "event:<name> (resname)" with
--  ph "B"/"E" pairs on one thread id, so self-time per resource can be
--  reconstructed exactly.
-- ═══════════════════════════════════════════════════════════════════════════════

local function ParseTrace(trace)
    local events = type(trace) == 'table' and trace.traceEvents or nil
    if type(events) ~= 'table' then return nil, 'no traceEvents in profiler output' end

    local stacks = {}
    local res = {}
    local frames, firstTs, lastTs = 0, nil, nil

    for i = 1, #events do
        local e = events[i]
        local ph, name = e.ph, e.name
        if ph == 'I' and name == 'BeginFrame' then
            frames = frames + 1
            if not firstTs then firstTs = e.ts end
            lastTs = e.ts
        elseif ph == 'B' then
            local st = stacks[e.tid]
            if not st then st = {}; stacks[e.tid] = st end
            local cause, rname
            if type(name) == 'string' then cause, rname = name:match('^(.-) %((.+)%)$') end
            st[#st + 1] = { res = rname, cause = cause, ts = e.ts or 0, child = 0 }
        elseif ph == 'E' then
            local st = stacks[e.tid]
            if st and #st > 0 then
                local top = st[#st]
                st[#st] = nil
                local dur = (e.ts or 0) - top.ts
                if dur < 0 then dur = 0 end
                local parent = st[#st]
                if top.res then
                    local r = res[top.res]
                    if not r then
                        r = { self = 0, incl = 0, calls = 0, peak = 0, events = 0, ticks = 0 }
                        res[top.res] = r
                    end
                    local selfT = dur - top.child
                    if selfT < 0 then selfT = 0 end
                    r.self = r.self + selfT
                    r.incl = r.incl + dur
                    r.calls = r.calls + 1
                    if selfT > r.peak then r.peak = selfT end
                    if top.cause == 'tick' then r.ticks = r.ticks + 1 else r.events = r.events + 1 end
                    if parent then parent.child = parent.child + dur end
                else
                    -- Named scope (thread name etc.): transparent, pass child time up
                    if parent then parent.child = parent.child + top.child end
                end
            end
        end
    end

    if frames == 0 or not firstTs or not lastTs or lastTs <= firstTs then
        return nil, 'profiler output has no frames'
    end

    local wallUs = lastTs - firstTs
    local wallSec = wallUs / 1000000
    local rows = {}
    for name, r in pairs(res) do
        local row = {
            name      = name,
            side      = 'server',
            source    = 'scan',
            load      = (r.self / wallUs) * 100,
            msPerTick = Round(r.self / frames / 1000, 3),
            peakMs    = Round(r.peak / 1000, 2),
            slicesPs  = r.calls / wallSec,
            eventsPs  = r.events / wallSec,
            ticks     = r.ticks,
        }
        row.grade, row.verdict, row.hints = NZGrade.resource(row)
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return a.load > b.load end)
    return rows, nil, frames, wallSec
end

local function NotifyAdmin(src, msg, kind)
    if src and src ~= 0 then
        TriggerClientEvent('nayzeee-optimizer:health:status', src, msg, kind or 'info')
    end
    local level = (kind == 'ok' or kind == 'warn' or kind == 'error') and kind or 'info'
    Console.log(level, '%s', msg)
end

local function RunScan(frames, requester)
    if scan.status == 'running' then return false, 'A scan is already running' end
    if ProfilerIsRecording() then return false, 'The profiler is already recording (someone ran `profiler record`)' end

    frames = tonumber(frames) or (hcfg.scan and hcfg.scan.frames) or 500
    frames = math.max(50, math.min(5000, math.floor(frames)))
    local timeout = ((hcfg.scan and hcfg.scan.timeout) or 60) * 1000

    scan.status = 'running'
    scan.frames = frames
    scan.error = nil
    scan.at = os.time()

    CreateThread(function()
        local fileName = 'optimizer_scan.json'
        local path = GetResourcePath(RES) .. '/' .. fileName
        NotifyAdmin(requester, ('Deep scan: recording %d server frames...'):format(frames), 'info')

        ExecuteCommand(('profiler record %d'):format(frames))
        Wait(500)
        local deadline = GetGameTimer() + timeout
        while ProfilerIsRecording() and GetGameTimer() < deadline do Wait(250) end
        if ProfilerIsRecording() then
            ExecuteCommand('profiler record stop')
            Wait(500)
        end

        ExecuteCommand(('profiler saveJSON "%s"'):format(path))

        local data, parsed
        local fileDeadline = GetGameTimer() + 20000
        while GetGameTimer() < fileDeadline do
            Wait(500)
            data = LoadResourceFile(RES, fileName)
            if data and #data > 16 then
                local ok, res = pcall(json.decode, data)
                if ok and type(res) == 'table' then parsed = res break end
            end
        end

        if not parsed then
            scan.status = 'error'
            scan.error = CanRunCommand('profiler')
                and 'Profiler did not produce a readable file. Run manually: profiler record 500, then profiler saveJSON <path>, and check console output.'
                or ('The server blocked this resource from running the profiler: %s, then try again.'):format(ACE_FIX)
            NotifyAdmin(requester, 'Deep scan failed: ' .. scan.error, 'error')
            return
        end

        local rows, err, nFrames, wallSec = ParseTrace(parsed)
        if os and os.remove then pcall(os.remove, path) end

        if not rows then
            scan.status = 'error'
            scan.error = err
            NotifyAdmin(requester, 'Deep scan failed: ' .. tostring(err), 'error')
            return
        end

        scan.status = 'done'
        scan.rows = rows
        scan.frames = nFrames
        scan.wallSec = wallSec
        scan.at = os.time()
        NotifyAdmin(requester, ('Deep scan complete: %d resources over %d frames (%.1fs).'):format(#rows, nFrames, wallSec), 'ok')

        local worst = {}
        for i = 1, math.min(5, #rows) do
            worst[#worst + 1] = ('%s %.2f%% (%s)'):format(rows[i].name, rows[i].load, NZGrade.LABEL[rows[i].grade])
        end
        Console.log('info', 'Scan top: %s', table.concat(worst, ' | '))
    end)

    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  PROBE INSTALLER
-- ═══════════════════════════════════════════════════════════════════════════════

local PROBE_REF  = '@' .. RES .. '/probe.lua'
local PROBE_LINE = ("shared_script '%s' -- nayzeee-optimizer probe (remove with `optimizerprobe remove`)"):format(PROBE_REF)
local BOM = '\239\187\191'

-- FXServer only lets a resource write into ANOTHER resource's folder when
-- server.cfg grants it, one line per target resource, at boot:
--     add_filesystem_permission nayzeee-optimizerv2 write <resource>
-- (SaveResourceFile, io.open and os.remove all go through that check, and
-- there is no wildcard.) So the optimizer writes those lines into a .cfg
-- in its OWN folder, which it is always allowed to do, and server.cfg
-- loads it with a single line:  exec @nayzeee-optimizerv2/probe_permissions.cfg
local PERMS_FILE = 'probe_permissions.cfg'
local PERMS_EXEC = ('exec @%s/%s'):format(RES, PERMS_FILE)

-- What this boot was granted: the file as server.cfg ran it, before we
-- regenerate it below. The file sets nz_probe_permissions so we can tell
-- whether server.cfg loaded it at all.
local permsLoaded = GetConvar('nz_probe_permissions', '') ~= ''
local writeAccess = {}
if permsLoaded then
    for name in (LoadResourceFile(RES, PERMS_FILE) or ''):gmatch('add_filesystem_permission%s+%S+%s+write%s+(%S+)') do
        writeAccess[name] = true
    end
end

local function IsExcluded(res)
    local lower = res:lower()
    for _, ex in ipairs(pcfg.exclude or {}) do
        if ex:lower() == lower then return true end
    end
    return false
end

local function ReadManifest(res)
    for _, f in ipairs({ 'fxmanifest.lua', '__resource.lua' }) do
        local c = LoadResourceFile(res, f)
        if c and #c > 0 then return f, c end
    end
    return nil
end

local function HasProbe(content)
    return content:find(RES .. '/probe.lua', 1, true) ~= nil
end

local function InstallProbe(res)
    if res == RES or IsExcluded(res) then return 'skipped' end
    local file, content = ReadManifest(res)
    if not file then return 'nomanifest' end
    if file == '__resource.lua' then return 'legacy' end
    if HasProbe(content) then return 'present' end

    local body = content
    local bom = ''
    if body:sub(1, 3) == BOM then
        bom = BOM
        body = body:sub(4)
    end

    local ok = SaveResourceFile(res, file, bom .. PROBE_LINE .. '\n' .. body, -1)
    if not ok then
        -- Without a grant FXServer refuses every write; with one, a refusal
        -- means the disk itself said no.
        return writeAccess[res] and 'failed' or 'noperm'
    end
    SaveResourceFile(res, file .. '.optimizer-backup', content, -1)
    return 'installed'
end

-- Regenerate probe_permissions.cfg with every resource the probe could go
-- into. Returns how many it lists and how many of those this boot has no
-- grant for yet (they get it on the next server restart).
local function WritePermissionsFile()
    local names = {}
    for _, res in ipairs(AllResources()) do
        if res ~= RES and not IsExcluded(res) then
            local file = ReadManifest(res)
            if file == 'fxmanifest.lua' then names[#names + 1] = res end
        end
    end
    table.sort(names)
    local lines = {
        '# NayZeee Optimizer: lets the optimizer add its probe line to these resources.',
        '# Generated on every start, so new resources are added automatically. Do not edit.',
        '# Load it from server.cfg with:  ' .. PERMS_EXEC,
        '',
    }
    local missing = 0
    for _, res in ipairs(names) do
        lines[#lines + 1] = ('add_filesystem_permission %s write %s'):format(RES, res)
        if not writeAccess[res] then missing = missing + 1 end
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('set nz_probe_permissions "%d"'):format(#names)
    local content = table.concat(lines, '\n') .. '\n'
    if LoadResourceFile(RES, PERMS_FILE) ~= content then
        SaveResourceFile(RES, PERMS_FILE, content, -1)
    end
    return #names, missing
end

local function RemoveProbe(res)
    local file, content = ReadManifest(res)
    if not file or not HasProbe(content) then return 'absent' end
    local out = {}
    for line in (content .. '\n'):gmatch('(.-)\r?\n') do
        if not line:find(RES .. '/probe.lua', 1, true) then out[#out + 1] = line end
    end
    local ok = SaveResourceFile(res, file, table.concat(out, '\n'), -1)
    if ok and os and os.remove then
        pcall(os.remove, GetResourcePath(res) .. '/' .. file .. '.optimizer-backup')
    end
    return ok and 'removed' or 'failed'
end

-- Resources whose manifest has the probe but whose running copy does not.
-- Cleared when the resource (re)starts.
local pendingRestart = {}

AddEventHandler('onResourceStart', function(res) pendingRestart[res] = nil end)

local function PendingList()
    local list = {}
    for res in pairs(pendingRestart) do
        if GetResourceState(res) == 'started' then list[#list + 1] = res else pendingRestart[res] = nil end
    end
    table.sort(list)
    return list
end

local function ProbeStatus()
    local now = os.time()
    local total, covered, reporting, excluded, legacy = 0, 0, 0, 0, 0
    local missing = {}
    for _, res in ipairs(AllResources()) do
        if res ~= RES then
            local state = GetResourceState(res)
            if state == 'started' then
                total = total + 1
                if IsExcluded(res) then
                    excluded = excluded + 1
                else
                    local file, content = ReadManifest(res)
                    if file == '__resource.lua' then
                        legacy = legacy + 1
                    elseif content and HasProbe(content) then
                        covered = covered + 1
                        local e = probeServer[res]
                        if e and now - e.at <= (pcfg.reportInterval or 5) * 4 then reporting = reporting + 1 end
                    else
                        missing[#missing + 1] = res
                    end
                end
            end
        end
    end
    table.sort(missing)
    return {
        enabled = pcfg.enabled ~= false,
        total = total, covered = covered, reporting = reporting,
        excluded = excluded, legacy = legacy, missing = missing,
        autoInstall = pcfg.autoInstall == true, autoInstallNew = pcfg.autoInstallNew == true,
        pending = PendingList(), canRefresh = CanRunCommand('refresh'),
        writeAccess = permsLoaded, permExec = PERMS_EXEC,
    }
end


-- Resources other running scripts depend on: restarting them live would
-- stop their dependents, so they wait for the next server restart.
local function NeverRestart()
    local set = {}
    for _, name in ipairs(pcfg.neverRestart or {}) do set[name] = true end
    for _, r in ipairs(AllResources()) do
        if GetResourceState(r) == 'started' then
            local n = GetNumResourceMetadata(r, 'dependency') or 0
            for i = 0, n - 1 do
                local d = GetResourceMetadata(r, 'dependency', i)
                if d and d:sub(1, 1) ~= '/' then set[d] = true end
            end
        end
    end
    return set
end

local function RestartPending(requester)
    local list = PendingList()
    if #list == 0 then
        NotifyAdmin(requester, 'No resources are waiting for a restart.', 'info')
        return
    end

    local blocked = NeverRestart()
    local now, later = {}, {}
    for _, res in ipairs(list) do
        if blocked[res] then later[#later + 1] = res else now[#now + 1] = res end
    end

    local refreshed = CanRunCommand('refresh')
    if refreshed then ExecuteCommand('refresh') end

    CreateThread(function()
        Wait(1000)
        for _, res in ipairs(now) do
            if GetResourceState(res) == 'started' then
                StopResource(res)
                Wait(250)
                StartResource(res)
                Wait(250)
            end
        end
        if #now > 0 then
            NotifyAdmin(requester, ('Restarted %d resource(s): their probes report within %d seconds.'):format(#now, (pcfg.reportInterval or 5) * 2), 'ok')
        end
        if #later > 0 then
            NotifyAdmin(requester, ('%d resource(s) other scripts depend on were not restarted live, they activate on the next server restart: %s'):format(#later, table.concat(later, ', ')), 'info')
        end
        if not refreshed then
            NotifyAdmin(requester, ('Could not run refresh automatically, so restarted resources may still use their old manifest: %s, or type refresh in the console and run optimizerprobe restart again.'):format(ACE_FIX), 'warn')
        end
    end)
end

-- opts: quiet (return counts only), restart (restart changed resources),
-- auto (startup auto-install: say nothing when there is nothing to add)
local function InstallAll(requester, opts)
    opts = opts or {}
    local counts = { installed = 0, present = 0, skipped = 0, legacy = 0, nomanifest = 0, failed = 0, noperm = 0 }
    local names, failedNames = {}, {}
    WritePermissionsFile()
    for _, res in ipairs(AllResources()) do
        if res ~= RES and GetResourceState(res) == 'started' then
            local r = InstallProbe(res)
            counts[r] = (counts[r] or 0) + 1
            if r == 'installed' then
                names[#names + 1] = res
                pendingRestart[res] = true
            elseif r == 'failed' then
                failedNames[#failedNames + 1] = res
            end
        end
    end
    if opts.quiet then return counts, names end
    if opts.auto and counts.installed == 0 and counts.failed == 0 and counts.noperm == 0 then return counts, names end

    if counts.noperm > 0 then
        if permsLoaded then
            NotifyAdmin(requester, ('%d resource(s) are new since the server started, so FiveM has not given the optimizer write access to them yet. They are in %s now and work after the next server restart.'):format(counts.noperm, PERMS_FILE), 'warn')
        else
            NotifyAdmin(requester, ('FiveM blocks one resource from editing another unless server.cfg allows it. Add this line to server.cfg once, restart the server, then press Install again:  %s'):format(PERMS_EXEC), 'warn')
        end
    end

    if counts.installed == 0 and counts.failed == 0 and counts.noperm > 0 then
        -- nothing else to say
    elseif counts.installed == 0 and counts.failed == 0 then
        NotifyAdmin(requester, ('Probe install: nothing to add. %d resource(s) already have it, %d skipped, %d legacy manifest(s).'):format(
            counts.present, counts.skipped + counts.nomanifest, counts.legacy), 'ok')
    else
        NotifyAdmin(requester, ('Probe added to %d resource(s), %d already had it.'):format(counts.installed, counts.present), 'ok')
        if #names > 0 then Console.log('info', 'Probe added to: %s', table.concat(names, ', ')) end
    end
    if counts.failed > 0 then
        NotifyAdmin(requester, ('Could not write the manifest of %d resource(s) even with permission, check that the server can write to those folders: %s'):format(counts.failed, table.concat(failedNames, ', ')), 'warn')
    end
    if counts.legacy > 0 then
        Console.log('info', '%d resource(s) use __resource.lua: add the probe line to those by hand', counts.legacy)
    end

    if #PendingList() > 0 then
        if opts.restart or pcfg.restartAfterInstall then
            RestartPending(requester)
        else
            NotifyAdmin(requester, 'They start measuring once restarted: run optimizerprobe restart, press Restart in the Health tab, or restart the server.', 'info')
        end
    end
    return counts, names
end

local function RemoveAll(requester)
    local removed, failed = 0, 0
    for _, res in ipairs(AllResources()) do
        if res ~= RES then
            local r = RemoveProbe(res)
            if r == 'removed' then removed = removed + 1 elseif r == 'failed' then failed = failed + 1 end
        end
    end
    NotifyAdmin(requester, ('Probe removed from %d manifests (%d failed). Restart the resources to unload it.'):format(removed, failed), failed > 0 and 'warn' or 'ok')
end

-- Probe setup at start (coverage row in the startup block, auto install)
if pcfg.enabled == false then
    SetConvar('nz_probe_disabled', '1')
    Console.check('probe', 'info', 'Probe', 'off: Config.Probe.enabled is false, use optimizerscan instead')
else
    SetConvar('nz_probe_disabled', '0')
    SetConvar('nz_probe_interval', tostring(pcfg.reportInterval or 5))

    local total, covered, legacy = 0, 0, 0
    for _, res in ipairs(AllResources()) do
        if res ~= RES and not IsExcluded(res) then
            local file, content = ReadManifest(res)
            if file == '__resource.lua' then
                legacy = legacy + 1
            elseif content then
                total = total + 1
                if HasProbe(content) then covered = covered + 1 end
            end
        end
    end

    local listed, notYet = WritePermissionsFile()

    local text = ('in %d of %d resources'):format(covered, total)
    if legacy > 0 then text = text .. (', %d legacy manifest(s) need the line by hand'):format(legacy) end
    if not permsLoaded and covered < total then
        Console.check('probe', 'warn', 'Probe', text .. (': to let it install itself, add "%s" to server.cfg and restart'):format(PERMS_EXEC))
    elseif pcfg.autoInstall then
        text = text .. ', auto-install runs once the server has started'
        Console.check('probe', 'ok', 'Probe', text)
    elseif covered == 0 then
        Console.check('probe', 'info', 'Probe', text .. ': run optimizerprobe install to grade them')
    else
        Console.check('probe', 'ok', 'Probe', text)
    end
    if permsLoaded and notYet > 0 then
        Console.log('info', '%d new resource(s) added to %s, the optimizer can write to them after the next restart', notYet, PERMS_FILE)
    end

    -- Auto install once every resource has finished starting, so it covers
    -- everything the server actually runs.
    if pcfg.autoInstall then
        CreateThread(function()
            Wait(5000)
            local deadline = GetGameTimer() + 60000
            while GetGameTimer() < deadline do
                local busy = false
                for _, res in ipairs(AllResources()) do
                    if GetResourceState(res) == 'starting' then busy = true break end
                end
                if not busy then break end
                Wait(1000)
            end
            InstallAll(0, { auto = true, restart = pcfg.restartAfterInstall })
        end)
    end

    -- A while after start, flag resources whose manifest has the probe but
    -- whose running copy never reported (manifest changed, not restarted).
    CreateThread(function()
        Wait(((pcfg.reportInterval or 5) * 4 + 15) * 1000)
        local silent = {}
        for _, res in ipairs(AllResources()) do
            if res ~= RES and GetResourceState(res) == 'started' and not probeServer[res] then
                local file, content = ReadManifest(res)
                if file == 'fxmanifest.lua' and content and HasProbe(content) then
                    silent[#silent + 1] = res
                    pendingRestart[res] = true
                end
            end
        end
        if #silent > 0 then
            table.sort(silent)
            Console.log('warn', '%d resource(s) have the probe line but are not reporting yet, they need a refresh and restart: run optimizerprobe restart (%s%s)',
                #silent, table.concat(silent, ', ', 1, math.min(#silent, 8)), #silent > 8 and ', ...' or '')
        end
    end)
end

-- Startup row: permission to run refresh (probe restarts) and the profiler (deep scan)
do
    local okRefresh, okProfiler = CanRunCommand('refresh'), CanRunCommand('profiler')
    if okRefresh and okProfiler then
        Console.check('perms', 'ok', 'Permissions', 'can run refresh and the profiler')
    else
        Console.check('perms', 'warn', 'Permissions', ACE_FIX .. ': needed for probe restarts and the deep scan')
    end
end

AddEventHandler('onResourceStart', function(res)
    if res == RES or pcfg.enabled == false or not pcfg.autoInstallNew then return end
    CreateThread(function()
        Wait(1000)
        local r = InstallProbe(res)
        if r == 'installed' then
            pendingRestart[res] = true
            if pcfg.restartAfterInstall then
                Console.log('info', 'Probe added to %s, restarting it now.', res)
                RestartPending(0)
            else
                Console.log('info', 'Probe added to %s. It activates when it restarts (optimizerprobe restart).', res)
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  UPDATE CHECKER
-- ═══════════════════════════════════════════════════════════════════════════════

local function UpdateCheckOn()
    local uc = Config.UpdateCheck
    return uc and uc.enabled and type(uc.url) == 'string' and uc.url ~= ''
end

-- atStartup: report as a row in the startup block instead of a log line
local function CheckUpdate(atStartup)
    if not UpdateCheckOn() then return end
    local announced = update.outdated and update.latest
    PerformHttpRequest(Config.UpdateCheck.url, function(code, body)
        update.checked = os.time()
        local ok, data = false, nil
        if code == 200 and body then ok, data = pcall(json.decode, body) end
        if not ok or type(data) ~= 'table' or not data.version then
            if atStartup then
                Console.check('update', 'warn', 'Updates', ('check failed (HTTP %s): check Config.UpdateCheck.url'):format(tostring(code)))
                Console.done('update')
            end
            return
        end
        update.latest = tostring(data.version)
        update.url = data.url
        update.notes = data.notes
        update.outdated = IsNewer(update.latest, VERSION)
        if atStartup then
            if update.outdated then
                Console.check('update', 'warn', 'Updates', ('v%s available%s'):format(update.latest, update.url and (': ' .. update.url) or ''))
            else
                Console.check('update', 'ok', 'Updates', ('v%s is the latest'):format(VERSION))
            end
            Console.done('update')
        elseif update.outdated and announced ~= update.latest then
            Console.log('warn', 'Update available: v%s -> v%s %s', VERSION, update.latest, update.url or '')
        end
    end, 'GET', '', { ['Accept'] = 'application/json' })
end

if UpdateCheckOn() then
    Console.wait('update')
    CheckUpdate(true)
    CreateThread(function()
        while true do
            Wait(math.max(30, Config.UpdateCheck.interval or 360) * 60000)
            CheckUpdate(false)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  HEALTH PAYLOAD
-- ═══════════════════════════════════════════════════════════════════════════════

local function ServerGrade()
    local uptimeMin = math.max(10, (os.time() - monitorStart) / 60)
    local perHour = hitchCount / uptimeMin * 60
    local t = hcfg.thresholds and hcfg.thresholds.hitchRate
    local grade = NZGrade.band(perHour, t)
    if lastSevereAt > 0 and os.time() - lastSevereAt < 900 then
        grade = NZGrade.bump(grade, 1)
    end
    return grade, perHour
end

local function MergedServerRows()
    local rows = BuildServerProbeRows()
    local byName = {}
    for _, r in ipairs(rows) do byName[r.name] = r end
    if scan.rows then
        for _, s in ipairs(scan.rows) do
            local existing = byName[s.name]
            if existing then
                existing.scanLoad = Round(s.load, 2)
                existing.msPerTick = s.msPerTick
            else
                rows[#rows + 1] = s
            end
        end
    end
    table.sort(rows, function(a, b) return a.load > b.load end)
    return rows
end

local function BuildHealthPayload()
    local memory, memLabel = ProcessMemoryMB()
    local grade, perHour = ServerGrade()
    local resources = AllResources()
    local started = 0
    for _, r in ipairs(resources) do if GetResourceState(r) == 'started' then started = started + 1 end end

    local tl = {}
    for i = 1, 60 do tl[i] = { timeline[i].h, timeline[i].s } end

    local entities = {
        vehicles = #GetAllVehicles(),
        peds = #GetAllPeds(),
        objects = #GetAllObjects(),
    }

    return {
        version = VERSION,
        server = {
            grade = grade,
            uptimeMin = math.floor((os.time() - monitorStart) / 60),
            players = GetPlayerCount(),
            memoryMB = memory,
            memoryLabel = memLabel,
            memoryHistory = memorySamples,
            memoryIntervalSec = cfg.memoryInterval or 60,
            tick = {
                hitches = hitchCount,
                severe = severeHitchCount,
                worst = Round(worstHitch, 0),
                perHour = Round(perHour, 1),
                avgDrift = driftSamples > 0 and Round(driftSum / driftSamples, 1) or 0,
                lastSevereAgo = lastSevereAt > 0 and (os.time() - lastSevereAt) or nil,
            },
            timeline = tl,
            entities = entities,
            resourcesTotal = #resources,
            resourcesStarted = started,
        },
        resources = MergedServerRows(),
        clients = BuildClientAggregate(),
        scan = { status = scan.status, at = scan.at, frames = scan.frames, error = scan.error, count = scan.rows and #scan.rows or 0 },
        probe = ProbeStatus(),
        update = update,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  NET EVENTS (admin)
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nayzeee-optimizer:admin:check', function()
    local src = source
    TriggerClientEvent('nayzeee-optimizer:admin:result', src, IsAdmin(src))
end)

RegisterNetEvent('nayzeee-optimizer:health:request', function()
    local src = source
    if not hcfg.enabled or not IsAdmin(src) then return end
    local now = os.time()
    if now - (lastHealthRequest[src] or 0) < (hcfg.requestCooldown or 3) then return end
    lastHealthRequest[src] = now
    TriggerClientEvent('nayzeee-optimizer:health:data', src, BuildHealthPayload())
end)

RegisterNetEvent('nayzeee-optimizer:health:action', function(what, arg)
    local src = source
    if not hcfg.enabled or not IsAdmin(src) then return end
    if what == 'scan' then
        local ok, err = RunScan(arg, src)
        if not ok then NotifyAdmin(src, err, 'warn') end
    elseif what == 'probeInstall' then
        InstallAll(src, { restart = arg == true })
    elseif what == 'probeRestart' then
        RestartPending(src)
    elseif what == 'probeRemove' then
        RemoveAll(src)
    elseif what == 'update' then
        CheckUpdate()
        NotifyAdmin(src, 'Update check requested.', 'info')
    end
    CreateThread(function()
        Wait(1500)
        TriggerClientEvent('nayzeee-optimizer:health:data', src, BuildHealthPayload())
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  PERIODIC HEALTH REPORT + RESOURCE ALERTS
-- ═══════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    if not cfg.enabled then return end

    local interval = (cfg.reportInterval or 15) * 60000

    while true do
        Wait(interval)

        local memory, memLabel = ProcessMemoryMB()
        local players = GetPlayerCount()
        local uptime = math.floor((os.time() - monitorStart) / 60)
        local grade = ServerGrade()

        Console.log('info', 'Health report: %s, up %d min, %d players, %s %d MB', NZGrade.LABEL[grade], uptime, players, memLabel, memory)
        Console.log(severeHitchCount > 0 and 'warn' or 'info', 'Hitches: %d (%d severe), worst %.0f ms', hitchCount, severeHitchCount, worstHitch)

        if cfg.playerCorrelation and next(hitchByPlayerCount) then
            local peak, peakCount = 0, 0
            for pc, count in pairs(hitchByPlayerCount) do
                if count > peakCount then peakCount = count; peak = pc end
            end
            Console.log('info', 'Most hitches at %d players (%d occurrences)', peak, peakCount)
        end

        local rows = MergedServerRows()
        for i = 1, math.min(5, #rows) do
            local r = rows[i]
            Console.log((r.grade == 'bad' or r.grade == 'poor') and 'warn' or 'info', 'Server  %-28s %6.2f%%  %-9s %s', r.name, r.load, NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict])
        end
        for _, r in ipairs(rows) do
            if r.verdict == 'remove' or r.verdict == 'edit-required' then
                SendDiscord(
                    ('Resource needs attention: %s'):format(r.name),
                    ('**Grade:** %s\n**Verdict:** %s\n**Load:** %.2f%% of server main thread\n**Peak slice:** %.1f ms\n\n%s'):format(
                        NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict], r.load, r.peakMs or 0, r.hints[1] or ''),
                    15158332, 'res:' .. r.name, 21600
                )
            end
        end

        local agg = BuildClientAggregate()
        if agg.reporting > 0 then
            Console.log('info', 'Clients: %d reporting, avg %d fps, avg 1%% low %d, %d%% under 30 fps', agg.reporting, agg.fpsAvg, agg.lowAvg, agg.under30)
            for i = 1, math.min(5, #agg.rows) do
                local r = agg.rows[i]
                Console.log((r.grade == 'bad' or r.grade == 'poor') and 'warn' or 'info', 'Client  %-28s %6.3f ms  %-9s %s', r.name, r.load, NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict])
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  CONSOLE / ADMIN COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════════

local function LogRows(rows, side, fmtLoad)
    for _, r in ipairs(rows) do
        local level = (r.grade == 'bad' or r.grade == 'poor') and 'warn' or 'info'
        Console.log(level, '%s  %-28s %s  %-9s %-18s %s', side, r.name, fmtLoad(r), NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict], r.hints[1] or '')
    end
end

RegisterCommand('optimizerhealth', function(source)
    if not IsAdmin(source) then return end

    local payload = BuildHealthPayload()
    local s = payload.server
    local gradeLevel = (s.grade == 'bad' or s.grade == 'poor') and 'warn' or 'ok'
    Console.log(gradeLevel, 'Server health: %s, up %d min, %d players, %d/%d resources started',
        NZGrade.LABEL[s.grade], s.uptimeMin, s.players, s.resourcesStarted, s.resourcesTotal)
    Console.log('info', '%s: %d MB | Entities: %d vehicles, %d peds, %d objects',
        s.memoryLabel, s.memoryMB, s.entities.vehicles, s.entities.peds, s.entities.objects)
    Console.log(s.tick.severe > 0 and 'warn' or 'info', 'Hitches: %d (%d severe), %.1f per hour, worst %.0f ms, avg drift %.1f ms',
        s.tick.hitches, s.tick.severe, s.tick.perHour, s.tick.worst, s.tick.avgDrift)

    if cfg.playerCorrelation and next(hitchByPlayerCount) then
        local sorted = {}
        for pc, count in pairs(hitchByPlayerCount) do sorted[#sorted + 1] = { pc = pc, count = count } end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        local parts = {}
        for i = 1, math.min(5, #sorted) do parts[i] = ('%d players: %d'):format(sorted[i].pc, sorted[i].count) end
        Console.log('info', 'Hitches by player count: %s', table.concat(parts, ', '))
    end

    local p = payload.probe
    Console.log(#p.missing > 0 and 'warn' or 'ok', 'Probe: %d/%d resources covered, %d reporting, %d missing, %d excluded, %d legacy',
        p.covered, p.total, p.reporting, #p.missing, p.excluded, p.legacy)
    if #p.missing > 0 then
        Console.log('info', 'Missing: %s%s', table.concat(p.missing, ', ', 1, math.min(#p.missing, 25)), #p.missing > 25 and ', ...' or '')
    end

    LogRows(payload.resources, 'Server', function(r) return ('%6.2f%%'):format(r.load) end)

    local c = payload.clients
    if c.reporting > 0 then
        Console.log('info', 'Clients: %d reporting, avg %d fps, avg 1%% low %d, %d%% under 30 fps', c.reporting, c.fpsAvg, c.lowAvg, c.under30)
        LogRows(c.rows, 'Client', function(r) return ('%6.3f ms'):format(r.load) end)
    end

    if payload.scan.status == 'done' then
        Console.log('info', 'Last deep scan: %d resources, %d frames, at %s', payload.scan.count, payload.scan.frames, os.date('%H:%M:%S', payload.scan.at))
    elseif payload.scan.status == 'error' then
        Console.log('warn', 'Last deep scan failed: %s', tostring(payload.scan.error))
    end

    if update.outdated then
        Console.log('warn', 'Update available: v%s -> v%s %s', VERSION, update.latest, update.url or '')
    end
end, false)

RegisterCommand('optimizerreset', function(source)
    if not IsAdmin(source) then return end
    hitchCount = 0
    severeHitchCount = 0
    worstHitch = 0
    driftSum, driftSamples = 0, 0
    lastSevereAt = 0
    hitchByPlayerCount = {}
    memorySamples = {}
    for i = 1, 60 do timeline[i] = { h = 0, s = 0 } end
    probeMem = {}
    monitorStart = os.time()
    Console.log('ok', 'Monitoring stats reset')
end, false)

RegisterCommand('optimizerscan', function(source, args)
    if not IsAdmin(source) then return end
    local ok, err = RunScan(args[1], source)
    if not ok then Console.log('warn', '%s', err) end
end, false)

RegisterCommand('optimizerprobe', function(source, args)
    if not IsAdmin(source) then return end
    local sub = (args[1] or 'status'):lower()
    if sub == 'install' then
        local wantRestart = (args[2] or ''):lower() == 'restart'
        if args[2] and not wantRestart then
            local r = InstallProbe(args[2])
            Console.log(r == 'failed' and 'warn' or 'info', 'Probe install %s: %s', args[2], r)
            if r == 'installed' then
                pendingRestart[args[2]] = true
                if (args[3] or ''):lower() == 'restart' or pcfg.restartAfterInstall then RestartPending(source)
                else Console.log('info', 'Run optimizerprobe restart to activate it now.') end
            end
        else
            InstallAll(source, { restart = wantRestart })
        end
    elseif sub == 'restart' then
        RestartPending(source)
    elseif sub == 'permissions' then
        local listed, notYet = WritePermissionsFile()
        Console.log('ok', 'Wrote %s with %d resource(s).', PERMS_FILE, listed)
        if not permsLoaded then
            Console.log('warn', 'Add this line to server.cfg, then restart the server:  %s', PERMS_EXEC)
        elseif notYet > 0 then
            Console.log('info', '%d of them are new and get write access after the next server restart.', notYet)
        end
    elseif sub == 'remove' then
        if args[2] then
            Console.log('info', 'Probe remove %s: %s', args[2], RemoveProbe(args[2]))
        else
            RemoveAll(source)
        end
    else
        local p = ProbeStatus()
        Console.log(#p.missing > 0 and 'warn' or 'ok', 'Probe: %d/%d started resources covered, %d reporting now, %d excluded, %d legacy manifests',
            p.covered, p.total, p.reporting, p.excluded, p.legacy)
        if #p.missing > 0 then
            Console.log('info', 'Not covered: %s', table.concat(p.missing, ', '))
            Console.log('info', 'Run optimizerprobe install restart to add it and restart them in one go')
        end
        if #p.pending > 0 then
            Console.log('warn', 'Waiting for a restart: %s. Run optimizerprobe restart', table.concat(p.pending, ', '))
        end
        if not p.writeAccess then
            Console.log('warn', 'No write access to other resources yet: add "%s" to server.cfg and restart the server', PERMS_EXEC)
        end
        if not p.canRefresh then
            Console.log('warn', 'Automatic restarts need permission: %s', ACE_FIX)
        end
    end
end, false)

RegisterCommand('optimizeradmin', function(source, args)
    if not IsAdmin(source) then return end
    local id = tonumber(args[1])
    if not id or not GetPlayerName(id) then
        Console.log('warn', 'Usage: optimizeradmin <playerId> (player must be online)')
        return
    end
    local why = AdminReasons(id)
    if #why > 0 then
        Console.log('ok', '%s (%d) is an admin: %s', GetPlayerName(id), id, table.concat(why, ', '))
    else
        Console.log('warn', '%s (%d) is NOT an admin. Give them the ace (add_ace group.admin %s allow) and make sure they are in group.admin, or add one of these to Config.Admin.identifiers:',
            GetPlayerName(id), id, acfg.ace or 'optimizer.admin')
        for _, ident in ipairs(GetPlayerIdentifiers(id) or {}) do
            if not ident:find('^ip:') then Console.log('info', "    '%s',", ident) end
        end
    end
    TriggerClientEvent('nayzeee-optimizer:admin:result', id, #why > 0)
end, false)

RegisterCommand(acfg.presetCommand or 'optimizerpreset', function(source, args)
    if not IsAdmin(source) then return end
    local target, preset = args[1], args[2]
    if not target or not preset or not Config.Presets[preset] then
        Console.log('warn', 'Usage: %s <playerId|all> <quality|balanced|performance|potato|streaming|shooter>', acfg.presetCommand or 'optimizerpreset')
        return
    end
    if target == 'all' then
        TriggerClientEvent('nayzeee-optimizer:applyPreset', -1, preset)
        Console.log('ok', 'Preset %s pushed to all players', preset)
    else
        local id = tonumber(target)
        if id and GetPlayerName(id) then
            TriggerClientEvent('nayzeee-optimizer:applyPreset', id, preset)
            Console.log('ok', 'Preset %s pushed to %s (%d)', preset, GetPlayerName(id), id)
        else
            Console.log('warn', 'Player %s not found', tostring(target))
        end
    end
end, false)

-- ═══════════════════════════════════════════════════════════════════════════════
--  EXPORTS
-- ═══════════════════════════════════════════════════════════════════════════════

exports('GetHealthStats', function()
    local memory, memLabel = ProcessMemoryMB()
    return {
        hitches = hitchCount,
        severeHitches = severeHitchCount,
        worstHitch = worstHitch,
        memory = memory,
        memoryLabel = memLabel,
        players = GetPlayerCount(),
        uptimeMinutes = math.floor((os.time() - monitorStart) / 60),
        hitchByPlayerCount = hitchByPlayerCount,
    }
end)

exports('GetHealth', function() return BuildHealthPayload() end)
exports('GetServerResources', function() return MergedServerRows() end)
exports('GetClientAggregate', function() return BuildClientAggregate() end)
exports('RunScan', function(frames) return RunScan(frames, 0) end)
