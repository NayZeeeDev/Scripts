--[[
    NAYZEEE OPTIMIZER - Server
    Version: 1.1.0

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
    print('^1[NAYZEEE-OPTIMIZER] lock.lua missing — refusing to load.^7')
    StopResource(GetCurrentResourceName())
    return
end

if not NayZeeeResourceLock() then
    return
end

local RES = GetCurrentResourceName()
local VERSION = '1.1.0'

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

local function IsAdmin(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, acfg.ace or 'optimizer.admin')
end

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
                print(('[NAYZEEE-OPTIMIZER] ^1SEVERE HITCH^7 %.0fms drift | %d players online'):format(drift, players))
                SendDiscord(
                    'Severe Server Hitch',
                    ('**Drift:** %.0fms\n**Players online:** %d\n**Total hitches this session:** %d\n\nRun `optimizerhealth` in console for the full report.'):format(drift, players, hitchCount),
                    15158332, 'hitch'
                )
            else
                print(('[NAYZEEE-OPTIMIZER] Hitch detected: %.0fms drift | %d players'):format(drift, players))
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
                print(('[NAYZEEE-OPTIMIZER] ^3MEMORY GROWTH^7 +%.0f MB over the sample window (%s now %d MB)'):format(growth, label, memory))
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
    print(('[NAYZEEE-OPTIMIZER] %s'):format(msg))
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
            scan.error = 'Profiler did not produce a readable file. Run manually: `profiler record 500`, then `profiler saveJSON <path>` and check console output.'
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
        print('[NAYZEEE-OPTIMIZER] Scan top: ' .. table.concat(worst, ' | '))
    end)

    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  PROBE INSTALLER
-- ═══════════════════════════════════════════════════════════════════════════════

local PROBE_REF  = '@' .. RES .. '/probe.lua'
local PROBE_LINE = ("shared_script '%s' -- nayzeee-optimizer probe (remove with `optimizerprobe remove`)"):format(PROBE_REF)
local BOM = '\239\187\191'

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

    SaveResourceFile(res, file .. '.optimizer-backup', content, -1)
    local ok = SaveResourceFile(res, file, bom .. PROBE_LINE .. '\n' .. body, -1)
    return ok and 'installed' or 'failed'
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
    }
end

local function InstallAll(requester)
    local counts = { installed = 0, present = 0, skipped = 0, legacy = 0, nomanifest = 0, failed = 0 }
    local names = {}
    for _, res in ipairs(AllResources()) do
        if res ~= RES and GetResourceState(res) == 'started' then
            local r = InstallProbe(res)
            counts[r] = (counts[r] or 0) + 1
            if r == 'installed' then names[#names + 1] = res end
        end
    end
    local msg = ('Probe install: %d added, %d already present, %d skipped, %d legacy manifests, %d failed. Run `refresh` then restart the resources (or restart the server) to activate.'):format(
        counts.installed, counts.present, counts.skipped + counts.nomanifest, counts.legacy, counts.failed)
    NotifyAdmin(requester, msg, counts.failed > 0 and 'warn' or 'ok')
    if #names > 0 then print('[NAYZEEE-OPTIMIZER] Probe added to: ' .. table.concat(names, ', ')) end
    return counts
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

-- Auto install on start / for resources that start later
CreateThread(function()
    if pcfg.enabled == false then
        SetConvar('nz_probe_disabled', '1')
        return
    end
    SetConvar('nz_probe_disabled', '0')
    SetConvar('nz_probe_interval', tostring(pcfg.reportInterval or 5))

    Wait(3000)
    if pcfg.autoInstall then
        InstallAll(0)
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res == RES or pcfg.enabled == false or not pcfg.autoInstallNew then return end
    CreateThread(function()
        Wait(1000)
        local r = InstallProbe(res)
        if r == 'installed' then
            print(('[NAYZEEE-OPTIMIZER] Probe added to %s. It activates on that resource\'s next restart.'):format(res))
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  UPDATE CHECKER
-- ═══════════════════════════════════════════════════════════════════════════════

local function CheckUpdate()
    local uc = Config.UpdateCheck
    if not uc or not uc.enabled or not uc.url or uc.url == '' then return end
    PerformHttpRequest(uc.url, function(code, body)
        update.checked = os.time()
        if code ~= 200 or not body then return end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' or not data.version then return end
        update.latest = tostring(data.version)
        update.url = data.url
        update.notes = data.notes
        update.outdated = IsNewer(update.latest, VERSION)
        if update.outdated then
            print(('[NAYZEEE-OPTIMIZER] ^3Update available:^7 %s -> %s %s'):format(VERSION, update.latest, update.url or ''))
        end
    end, 'GET', '', { ['Accept'] = 'application/json' })
end

CreateThread(function()
    local uc = Config.UpdateCheck
    if not uc or not uc.enabled then return end
    Wait(15000)
    while true do
        CheckUpdate()
        Wait(math.max(30, uc.interval or 360) * 60000)
    end
end)

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
        InstallAll(src)
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

        print('[NAYZEEE-OPTIMIZER] ─── Health Report ───')
        print(('  Grade: %s | Uptime: %d min | Players: %d | %s: %d MB'):format(NZGrade.LABEL[grade], uptime, players, memLabel, memory))
        print(('  Hitches: %d (severe: %d) | Worst: %.0fms'):format(hitchCount, severeHitchCount, worstHitch))

        if cfg.playerCorrelation and next(hitchByPlayerCount) then
            local peak, peakCount = 0, 0
            for pc, count in pairs(hitchByPlayerCount) do
                if count > peakCount then peakCount = count; peak = pc end
            end
            print(('  Most hitches at %d players (%d occurrences)'):format(peak, peakCount))
        end

        local rows = MergedServerRows()
        if #rows > 0 then
            print('  Top server resources:')
            for i = 1, math.min(5, #rows) do
                local r = rows[i]
                print(('    %-28s %6.2f%%  %-9s %s'):format(r.name, r.load, NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict]))
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
        end

        local agg = BuildClientAggregate()
        if agg.reporting > 0 then
            print(('  Clients reporting: %d | Avg FPS: %d | Avg 1%% low: %d | Under 30 fps: %d%%'):format(agg.reporting, agg.fpsAvg, agg.lowAvg, agg.under30))
            if #agg.rows > 0 then
                print('  Top client-side resources (median ms/frame):')
                for i = 1, math.min(5, #agg.rows) do
                    local r = agg.rows[i]
                    print(('    %-28s %6.3f ms  %-9s %s'):format(r.name, r.load, NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict]))
                end
            end
        end

        print('[NAYZEEE-OPTIMIZER] ─────────────────────')
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  CONSOLE / ADMIN COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════════

local function PrintRows(rows, header, fmtLoad)
    if #rows == 0 then return end
    print('  ' .. header)
    for _, r in ipairs(rows) do
        print(('    %-28s %s  %-9s %-18s %s'):format(r.name, fmtLoad(r), NZGrade.LABEL[r.grade], NZGrade.VERDICT_LABEL[r.verdict], r.hints[1] or ''))
    end
end

RegisterCommand('optimizerhealth', function(source)
    if not IsAdmin(source) then return end

    local payload = BuildHealthPayload()
    local s = payload.server
    print('[NAYZEEE-OPTIMIZER] ═══ Server Health ═══')
    print(('  Grade: %s'):format(NZGrade.LABEL[s.grade]))
    print(('  Monitoring for: %d minutes | Players: %d | Resources started: %d/%d'):format(s.uptimeMin, s.players, s.resourcesStarted, s.resourcesTotal))
    print(('  %s: %d MB'):format(s.memoryLabel, s.memoryMB))
    print(('  Hitches: %d (severe %d) | %.1f per hour | worst %.0fms | avg drift %.1fms'):format(s.tick.hitches, s.tick.severe, s.tick.perHour, s.tick.worst, s.tick.avgDrift))
    print(('  Entities: %d vehicles, %d peds, %d objects'):format(s.entities.vehicles, s.entities.peds, s.entities.objects))

    if cfg.playerCorrelation and next(hitchByPlayerCount) then
        print('  ── Hitches by player count ──')
        local sorted = {}
        for pc, count in pairs(hitchByPlayerCount) do sorted[#sorted + 1] = { pc = pc, count = count } end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        for i = 1, math.min(5, #sorted) do
            print(('    %d players: %d hitches'):format(sorted[i].pc, sorted[i].count))
        end
    end

    local p = payload.probe
    print(('  Probe: %d/%d resources covered, %d reporting, %d missing, %d excluded, %d legacy'):format(p.covered, p.total, p.reporting, #p.missing, p.excluded, p.legacy))
    if #p.missing > 0 then
        print('    Missing: ' .. table.concat(p.missing, ', ', 1, math.min(#p.missing, 25)) .. (#p.missing > 25 and ' ...' or ''))
    end

    PrintRows(payload.resources, '── Server resources (probe + last scan) ──', function(r) return ('%6.2f%%'):format(r.load) end)

    local c = payload.clients
    if c.reporting > 0 then
        print(('  ── Clients: %d reporting | avg %d fps | avg 1%% low %d | %d%% under 30 fps ──'):format(c.reporting, c.fpsAvg, c.lowAvg, c.under30))
        PrintRows(c.rows, 'Client-side resources (median ms/frame across players):', function(r) return ('%6.3f ms'):format(r.load) end)
    end

    if payload.scan.status == 'done' then
        print(('  Last deep scan: %d resources, %d frames, %s'):format(payload.scan.count, payload.scan.frames, os.date('%H:%M:%S', payload.scan.at)))
    elseif payload.scan.status == 'error' then
        print('  Last deep scan failed: ' .. tostring(payload.scan.error))
    end

    if update.outdated then
        print(('  ^3Update available: %s -> %s^7 %s'):format(VERSION, update.latest, update.url or ''))
    end

    print('[NAYZEEE-OPTIMIZER] ═════════════════════')
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
    print('[NAYZEEE-OPTIMIZER] Monitoring stats reset')
end, false)

RegisterCommand('optimizerscan', function(source, args)
    if not IsAdmin(source) then return end
    local ok, err = RunScan(args[1], source)
    if not ok then print('[NAYZEEE-OPTIMIZER] ' .. err) end
end, false)

RegisterCommand('optimizerprobe', function(source, args)
    if not IsAdmin(source) then return end
    local sub = (args[1] or 'status'):lower()
    if sub == 'install' then
        if args[2] then
            local r = InstallProbe(args[2])
            print(('[NAYZEEE-OPTIMIZER] Probe install %s: %s'):format(args[2], r))
        else
            InstallAll(source)
        end
    elseif sub == 'remove' then
        if args[2] then
            local r = RemoveProbe(args[2])
            print(('[NAYZEEE-OPTIMIZER] Probe remove %s: %s'):format(args[2], r))
        else
            RemoveAll(source)
        end
    else
        local p = ProbeStatus()
        print(('[NAYZEEE-OPTIMIZER] Probe: %d/%d started resources covered, %d reporting now, %d excluded, %d legacy manifests'):format(p.covered, p.total, p.reporting, p.excluded, p.legacy))
        if #p.missing > 0 then
            print('  Not covered: ' .. table.concat(p.missing, ', '))
            print('  Run `optimizerprobe install`, then `refresh` and restart those resources.')
        end
    end
end, false)

RegisterCommand(acfg.presetCommand or 'optimizerpreset', function(source, args)
    if not IsAdmin(source) then return end
    local target, preset = args[1], args[2]
    if not target or not preset or not Config.Presets[preset] then
        print('[NAYZEEE-OPTIMIZER] Usage: optimizerpreset <playerId|all> <quality|balanced|performance|potato|streaming|shooter>')
        return
    end
    if target == 'all' then
        TriggerClientEvent('nayzeee-optimizer:applyPreset', -1, preset)
        print(('[NAYZEEE-OPTIMIZER] Preset %s pushed to all players'):format(preset))
    else
        local id = tonumber(target)
        if id and GetPlayerName(id) then
            TriggerClientEvent('nayzeee-optimizer:applyPreset', id, preset)
            print(('[NAYZEEE-OPTIMIZER] Preset %s pushed to %s'):format(preset, GetPlayerName(id)))
        else
            print('[NAYZEEE-OPTIMIZER] Player not found')
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

print(('[NAYZEEE-OPTIMIZER] v%s Server loaded'):format(VERSION))
if cfg.enabled then
    print('[NAYZEEE-OPTIMIZER] Performance monitoring active — optimizerhealth for report')
end
