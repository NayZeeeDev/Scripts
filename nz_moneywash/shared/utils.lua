NZ = NZ or {}

NZ.Resource = GetCurrentResourceName()
NZ.StatePrefix = 'nzmw:st:'

function NZ.dbg(...)
    if Config.Debug then print('^6[nz_moneywash]^7', ...) end
end

function NZ.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function NZ.round(n, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(n * m + 0.5) / m
end

function NZ.money(n)
    local s = tostring(math.floor(n or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return '$' .. out:gsub('^,', '')
end

function NZ.stateKey(id) return NZ.StatePrefix .. id end

-- Ordered list of enabled machine stages. The washer is always first.
function NZ.pipeline()
    local list = { 'washer' }
    if Config.Stages.printer.enabled then list[#list + 1] = 'printer' end
    if Config.Stages.cutter.enabled then list[#list + 1] = 'cutter' end
    return list
end

function NZ.stageIndex(stageType)
    for i, t in ipairs(NZ.pipeline()) do
        if t == stageType then return i end
    end
end

-- Item a station consumes (nil for the washer, which eats dirty money)
function NZ.inputItem(stageType)
    local p = NZ.pipeline()
    local i = NZ.stageIndex(stageType)
    if not i or i == 1 then return nil end
    return Config.Stages[p[i - 1]].outputItem
end

-- The item the books accept
function NZ.finalItem()
    local p = NZ.pipeline()
    return Config.Stages[p[#p]].outputItem
end

function NZ.dyeBand(dye)
    for _, band in ipairs(Config.Wash.dyeBands) do
        if dye <= band.max then return band end
    end
    return Config.Wash.dyeBands[#Config.Wash.dyeBands]
end

local tempOrder = { cold = 1, warm = 2, hot = 3 }
function NZ.tempPenalty(dye, temp)
    local diff = math.abs((tempOrder[NZ.dyeBand(dye).ideal] or 2) - (tempOrder[temp] or 2))
    if diff == 0 then return 0 end
    if diff == 1 then return Config.Wash.penaltyOneOff end
    return Config.Wash.penaltyTwoOff
end

function NZ.cycleTime(stageType, amount, spin)
    local s = Config.Stages[stageType]
    local t = s.baseTime + (amount / 1000) * s.perThousand
    if spin and Config.Wash.spins[spin] then t = t * Config.Wash.spins[spin].time end
    return math.floor(t)
end

function NZ.jamChance(wear, spin)
    local c = Config.Wear.jamBase + (wear or 0) * Config.Wear.jamPerWear
    if spin and Config.Wash.spins[spin] then c = c * Config.Wash.spins[spin].jam end
    return NZ.clamp(c, 0.0, 0.9)
end

--[[
    Suspicion for a declaration at a front (0..1). Mirrored in web/app.js for the live preview.
    alloc       : { [catKey] = share 0..1 }
    amount      : $ being declared now
    declared    : $ declared at this front in the last 24h
    heat        : weighted heat 0..100
    flags       : flagged entries on this front in the last 24h
]]
function NZ.suspicion(front, alloc, amount, declared, heat, flags)
    local dev = 0.0
    for _, c in ipairs(front.categories) do
        dev = dev + math.abs((alloc[c.key] or 0) - c.share)
    end
    dev = dev / 2 -- total variation distance (0..1)

    local over = math.max(0, (declared + amount) - front.dailyCap) / front.dailyCap
    local b = Config.Books
    local s = dev * b.wDeviation + over * b.wOverCap + (heat / 100) * b.wHeat + (flags or 0) * b.wRecentFlags
    return NZ.clamp(s, 0.0, 1.0)
end

function NZ.auditChance(suspicion)
    return NZ.clamp(Config.Audit.base + suspicion * Config.Audit.scale, 0.0, 1.0)
end

function NZ.isPoliceJob(job)
    if not job or not job.name then return false end
    local min = Config.PoliceJobs[job.name]
    return min ~= nil and (job.grade or 0) >= min and job.onduty ~= false
end

function NZ.isAuditJob(job)
    if not job or not job.name then return false end
    local min = Config.AuditJobs[job.name]
    return min ~= nil and (job.grade or 0) >= min and job.onduty ~= false
end

function NZ.findFront(id)
    for _, f in ipairs(Config.Fronts) do
        if f.id == id then return f end
    end
end

-- Main prop model for a station in a given state
function NZ.mainModel(stType, state)
    if stType == 'washer' then
        return state == 'running' and Config.Props.washerRunning or Config.Props.washer
    elseif stType == 'printer' then
        return state == 'running' and Config.Props.printerRunning or Config.Props.printerIdle
    elseif stType == 'cutter' then
        return Config.Props.cutter
    elseif stType == 'pallet' then
        return state == 'done' and Config.Props.palletFull or Config.Props.palletEmpty
    end
end
