--[[
    NAYZEEE OPTIMIZER - Grading (shared)

    Turns raw probe / scan numbers into the grade + verdict shown on the
    Health tab and in console reports. Shared so the client (its own
    resource table) and the server (everything else) agree on the rules.

    Grades:   excellent | good | ok | poor | bad
    Verdicts: healthy | monitor | edit | edit-required | remove
]]

NZGrade = {}

NZGrade.ORDER = { excellent = 1, good = 2, ok = 3, poor = 4, bad = 5 }
NZGrade.LABEL = { excellent = 'Excellent', good = 'Good', ok = 'OK', poor = 'Poor', bad = 'Bad' }
NZGrade.VERDICT_LABEL = {
    healthy          = 'Healthy',
    monitor          = 'Monitor',
    edit             = 'Edit recommended',
    ['edit-required'] = 'Edit required',
    remove           = 'Remove or replace',
}

local function T()
    return (Config.Health and Config.Health.thresholds) or {}
end

-- value against ascending thresholds { excellent, good, ok, poor }
function NZGrade.band(value, t)
    if not t or value == nil then return 'ok' end
    if value < t.excellent then return 'excellent' end
    if value < t.good then return 'good' end
    if value < t.ok then return 'ok' end
    if value < t.poor then return 'poor' end
    return 'bad'
end

-- value against descending thresholds (higher is better), e.g. 1% low FPS
function NZGrade.bandDesc(value, t)
    if not t or value == nil then return 'ok' end
    if value >= t.excellent then return 'excellent' end
    if value >= t.good then return 'good' end
    if value >= t.ok then return 'ok' end
    if value >= t.poor then return 'poor' end
    return 'bad'
end

function NZGrade.worse(a, b)
    return (NZGrade.ORDER[a] or 3) >= (NZGrade.ORDER[b] or 3) and a or b
end

function NZGrade.bump(grade, steps)
    local i = math.min(5, (NZGrade.ORDER[grade] or 3) + (steps or 1))
    for k, v in pairs(NZGrade.ORDER) do
        if v == i then return k end
    end
    return grade
end

--[[
    r = {
        side      = 'client' | 'server',
        load      = number,  -- client: ms per frame, server: % of main thread
        peakMs    = number,  -- longest single slice in the window
        loops     = number,  -- client only: threads waking every frame (slices / frames)
        eventsPs  = number,  -- handler invocations per second
        memGrowth = number,  -- Lua heap MB per hour (nil if unknown)
        slicesPs  = number,  -- server: slices per second
    }
    returns grade, verdict, hints (array of strings)
]]
function NZGrade.resource(r)
    local t = T()
    local hints = {}
    local severe, warn = false, false

    local grade
    if r.side == 'server' then
        grade = NZGrade.band(r.load or 0, t.serverPct)
    else
        grade = NZGrade.band(r.load or 0, t.clientMs)
    end

    local peak = t.peakSliceMs or { warn = 5, severe = 50 }
    if r.peakMs and r.peakMs >= peak.severe then
        severe = true
        hints[#hints + 1] = ('A single call blocked for %.0f ms. Look for loops without Wait(), synchronous HTTP/DB waits, or GetGamePool scans every tick.'):format(r.peakMs)
    elseif r.peakMs and r.peakMs >= peak.warn then
        warn = true
        hints[#hints + 1] = ('Longest slice %.1f ms. Occasional stutter from this resource.'):format(r.peakMs)
    end

    local loops = t.perFrameLoops or { warn = 3, severe = 8 }
    if r.side == 'client' and r.loops then
        if r.loops >= loops.severe then
            severe = true
            hints[#hints + 1] = ('About %d threads wake every frame. Add Wait(250+) to idle loops.'):format(math.floor(r.loops + 0.5))
        elseif r.loops >= loops.warn then
            warn = true
            hints[#hints + 1] = ('About %d per-frame threads. Sleep them while nothing is happening.'):format(math.floor(r.loops + 0.5))
        end
    end

    local ev = t.eventsPerSecond or { warn = 50, severe = 200 }
    if r.eventsPs then
        if r.eventsPs >= ev.severe then
            severe = true
            hints[#hints + 1] = ('%.0f event handlers fire per second. Event spam, throttle or batch them.'):format(r.eventsPs)
        elseif r.eventsPs >= ev.warn then
            warn = true
            hints[#hints + 1] = ('%.0f event handlers per second. Check for unthrottled triggers.'):format(r.eventsPs)
        end
    end

    local mem = t.memoryGrowthMBph or { warn = 10, severe = 50 }
    if r.memGrowth then
        if r.memGrowth >= mem.severe then
            severe = true
            hints[#hints + 1] = ('Lua memory growing +%.0f MB per hour. Likely a leak (tables that never clear, cached entities, timers).'):format(r.memGrowth)
        elseif r.memGrowth >= mem.warn then
            warn = true
            hints[#hints + 1] = ('Lua memory growing +%.0f MB per hour. Watch it over a longer session.'):format(r.memGrowth)
        end
    end

    local verdict
    if grade == 'bad' and severe then
        verdict = 'remove'
    elseif grade == 'bad' then
        verdict = 'edit-required'
    elseif grade == 'poor' or severe then
        verdict = 'edit'
    elseif grade == 'ok' or warn then
        verdict = 'monitor'
    else
        verdict = 'healthy'
    end

    if #hints == 0 then
        if verdict == 'healthy' then
            hints[1] = 'No issues found.'
        elseif verdict == 'monitor' then
            hints[1] = 'Measurable but acceptable load. Keep an eye on it as player count grows.'
        else
            hints[1] = r.side == 'server'
                and 'High main-thread usage. Profile its ticks and reduce per-tick work.'
                or  'High per-frame cost. Reduce work done every frame.'
        end
    end

    return grade, verdict, hints
end
