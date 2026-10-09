--[[
    Work program — the server picks every task, checks the ped is at the point when it
    starts and when it ends, and checks the task actually took its full duration.
]]

Work = {}

local Event = AJ.Event
local cfg = Config.Work

local function now() return os.time() end

local function rollHour(e)
    if now() - (e.hourStart or 0) >= 3600 then
        e.hourStart = now()
        e.hourReduced = 0
    end
end

local function capped(e)
    rollHour(e)
    return e.hourReduced >= cfg.maxPerHour * 60
end

local function pickPoint(e)
    local points = AJ.GetLocation(e.location).work
    if not points or #points == 0 then return nil end
    local idx = 1
    if #points > 1 then
        repeat idx = math.random(#points) until idx ~= e.work.point
    end
    e.work.point = idx
    e.work.startedAt = nil
    return idx
end

local function state(e)
    local data = {
        enabled = cfg.enabled,
        cycles = e.cycles,
        reduced = e.reduced,
        hourReduced = e.hourReduced,
        hourCap = cfg.maxPerHour * 60,
        step = e.work.step,
        of = cfg.pointsPerCycle,
    }
    if capped(e) then
        data.locked = true
        data.resetIn = math.max(0, e.hourStart + 3600 - now())
        return data
    end
    local point = e.work.point and AJ.GetLocation(e.location).work[e.work.point]
    if point then
        local task = cfg.tasks[point.task] or cfg.tasks.sweep
        data.point = { index = e.work.point, coords = point.coords, task = point.task, label = task.label, duration = task.duration }
    end
    return data
end

local function push(e)
    if e.source then TriggerClientEvent(Event('client:work'), e.source, state(e)) end
end

local function atPoint(e, maxDist)
    local point = AJ.GetLocation(e.location).work[e.work.point]
    local ped = GetPlayerPed(e.source)
    if not point or ped == 0 then return false end
    return AJ.Dist(GetEntityCoords(ped), point.coords) <= maxDist
end

function Work.Reset(e)
    e.work = { step = 0 }
end

function Work.OnActive(e)
    if not cfg.enabled then return end
    e.work = e.work or { step = 0 }
    if not e.work.point then pickPoint(e) end
    push(e)
end

lib.callback.register(Event('server:work:begin'), function(src, index)
    local e = Sentences.BySource(src)
    if not cfg.enabled or not e or e.state ~= 'active' then return false end
    if e.work.point ~= index or capped(e) then return false end
    if not atPoint(e, 3.0) then return false end
    e.work.startedAt = GetGameTimer()
    return true
end)

lib.callback.register(Event('server:work:finish'), function(src, index)
    local e = Sentences.BySource(src)
    if not e or e.state ~= 'active' or e.work.point ~= index or not e.work.startedAt then return { ok = false } end

    local point = AJ.GetLocation(e.location).work[index]
    local task = cfg.tasks[point.task] or cfg.tasks.sweep
    local elapsed = GetGameTimer() - e.work.startedAt
    e.work.startedAt = nil

    if elapsed < task.duration - 750 then return { ok = false } end
    if not atPoint(e, 3.5) then return { ok = false, moved = true } end

    e.work.step = e.work.step + 1
    local result = { ok = true }

    if e.work.step >= cfg.pointsPerCycle then
        e.work.step = 0
        rollHour(e)
        local reduction = math.min(cfg.reduction * 60, cfg.maxPerHour * 60 - e.hourReduced)
        if reduction > 0 then
            Sentences.Stamp(e)
            e.remaining = math.max(0, e.remaining - reduction)
            e.reduced = e.reduced + reduction
            e.hourReduced = e.hourReduced + reduction
        end
        e.cycles = e.cycles + 1
        result.cycle = true
        result.reduction = math.floor(reduction / 60)

        if e.remaining <= 0 then
            Sentences.Release(e, 'served', 'Time served (work)')
            result.released = true
            return result
        end
        DB.Save(e)
        Sentences.Sync(e)
    end

    pickPoint(e)
    push(e)
    return result
end)

RegisterNetEvent(Event('server:work:cancel'), function()
    local e = Sentences.BySource(source)
    if e and e.work then e.work.startedAt = nil end
end)

-- Hourly cap expired while the player is online: hand out a new task.
RegisterNetEvent(Event('server:work:refresh'), function()
    local e = Sentences.BySource(source)
    if e and e.state == 'active' and cfg.enabled then
        if not e.work.point then pickPoint(e) end
        push(e)
    end
end)
