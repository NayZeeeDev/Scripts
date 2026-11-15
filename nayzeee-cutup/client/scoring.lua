-- No Hesi style scoring: near misses, combo, speed multiplier, bonuses, hearts, runs.
Scoring = {}

local tracks    = {}      -- [veh] = { ahead, minGap, counted, cooldown }
local aggroHits = {}
local sampleAt  = 0

local function tierFor(gap)
    for _, t in ipairs(Config.Scoring.Tiers) do
        if gap <= t.gap then return t end
    end
    return Config.Scoring.Tiers[#Config.Scoring.Tiers]
end

local function bump(tbl, key, amount)
    tbl[key] = (tbl[key] or 0) + (amount or 1)
end

local function mostUsed(tbl, fallback)
    local best, bestV = fallback, -1
    for k, v in pairs(tbl) do if v > bestV then best, bestV = k, v end end
    return best
end

function Scoring.StartRun()
    tracks, aggroHits = {}, {}
    CU.Run = {
        points = 0.0, combo = 0.0, maxCombo = 0, time = 0.0, distance = 0.0,
        hearts = Config.Run.Hearts, passes = 0, proxSum = 0.0, crashes = 0,
        holdT = 0.0, holdPct = 0.0, speedMult = 1.0, totalMult = 1.0, idle = 0.0,
        crewFlowTime = 0.0, zones = {}, cams = {}, trans = {},
        car = CU.VehicleLabel(CU.Veh), density = CU.Settings.gameplay.density,
    }
    UI.Popup(L('run_start'), nil, CU.Settings.ui.hudAccent)
    UI.Send('sound', 'start')
end

function Scoring.EndRun(reasonKey)
    local r = CU.Run
    if not r then return end
    CU.Run = nil
    tracks, aggroHits = {}, {}
    CU.Bonus.aggro = 0

    local time = math.max(1.0, r.time)
    local crewData = LocalPlayer.state.cutupCrew
    local payload = {
        points       = math.floor(r.points),
        maxCombo     = math.floor(r.maxCombo),
        car          = r.car,
        avgSpeed     = r.distance / time,
        distance     = math.floor(r.distance),
        time         = math.floor(r.time),
        map          = mostUsed(r.zones, 'San Andreas'),
        density      = Util.DensityLabel(r.density),
        transmission = mostUsed(r.trans, 'auto'),
        camera       = mostUsed(r.cams, 'GTA Native'),
        carsPassed   = r.passes,
        avgProximity = r.passes > 0 and Util.Round(r.proxSum / r.passes, 1) or 0,
        crashes      = r.crashes,
        crewRun      = crewData ~= nil and (r.crewFlowTime / time) >= Config.Run.CrewRunShare,
    }
    UI.Send('summary', { run = payload, reason = L(reasonKey or 'run_over'), units = CU.Settings.gameplay.units })
    UI.Send('sound', 'end')

    if payload.points >= Config.Run.MinSubmit then
        TriggerServerEvent('nayzeee-cutup:server:submitRun', payload)
    else
        UI.Notify(L('run_over'), L('run_too_small'), 'warn')
    end
end

function Scoring.OnImpact(isCrash, severity, other)
    local r = CU.Run
    if not r then return end
    if other ~= 0 and tracks[other] then tracks[other].counted = true end
    if isCrash then
        r.crashes = r.crashes + 1
        r.hearts = r.hearts - 1
        r.combo, r.holdT = 0.0, 0.0
        aggroHits = {}
        local lost = math.floor(r.points * Config.Run.CrashPenalty)
        r.points = r.points - lost
        UI.Popup(L('crash'), r.hearts > 0 and L('hearts_left', r.hearts) or L('out_of_hearts'), CU.Settings.ui.alert, lost > 0 and -lost or nil)
        UI.Send('sound', 'crash')
        if r.hearts <= 0 then Scoring.EndRun('out_of_hearts') end
    else
        r.combo = math.floor(r.combo * 0.75)
        UI.Popup(L('scrape'), nil, CU.Settings.ui.alert)
    end
end

local function award(veh, gap, oncoming)
    local r = CU.Run
    local sc = Config.Scoring
    local tier = tierFor(gap)
    local pts = sc.PassBase * tier.mult * (oncoming and sc.OncomingMult or 1.0) * r.totalMult * (1.0 + r.combo * sc.ComboStep)
    r.points = r.points + pts
    r.combo = r.combo + tier.combo
    if r.combo > r.maxCombo then r.maxCombo = r.combo end
    r.holdT = sc.ComboHold
    r.passes = r.passes + 1
    r.proxSum = r.proxSum + tier.mult
    if gap <= 0.8 then
        aggroHits[#aggroHits + 1] = GetGameTimer()
        Awareness.NearMiss(veh, gap)
    end
    UI.Popup(tier.label, oncoming and 'ONCOMING' or nil, tier.color, math.floor(pts))
    UI.Send('sound', gap <= 0.35 and 'insane' or 'pass')
    if Config.Wheel.Rumble and gap <= 0.35 then
        UI.Send('wheel:rumble', { strong = 0.25, weak = 0.5, duration = 90 })
    end
end

local function detectPasses()
    local myVeh = CU.Veh
    local myD = CU.Dimensions(GetEntityModel(myVeh))
    local myFwd = GetEntityForwardVector(myVeh)
    local mySpeedF = GetEntitySpeedVector(myVeh, true).y
    local now = GetGameTimer()
    local seen = {}
    for _, n in ipairs(CU.NearbyNPC) do
        local v = n.veh
        if n.dist < 45.0 and DoesEntityExist(v) then
            seen[v] = true
            local p = GetEntityCoords(v)
            local lo = GetOffsetFromEntityGivenWorldCoords(myVeh, p.x, p.y, p.z)
            local od = CU.Dimensions(GetEntityModel(v))
            local halfLen = (myD.length + od.length) * 0.5 + 0.5
            local tr = tracks[v]
            if not tr then
                tr = { ahead = lo.y > halfLen * 0.5, minGap = 99.0, counted = false, cooldown = 0 }
                tracks[v] = tr
            end
            if lo.y > halfLen then
                if tr.counted and now > tr.cooldown then tr.counted = false end
                tr.ahead, tr.minGap = true, 99.0
            end
            if math.abs(lo.y) < halfLen and math.abs(lo.z) < 3.0 then
                local gap = math.abs(lo.x) - (myD.width + od.width) * 0.5
                if gap < tr.minGap then tr.minGap = gap end
            end
            if tr.ahead and not tr.counted and lo.y < -halfLen then
                tr.counted, tr.ahead, tr.cooldown = true, false, now + 4000
                local vel = GetEntityVelocity(v)
                local theirAlong = vel.x * myFwd.x + vel.y * myFwd.y
                local oncoming = theirAlong < -3.0
                local rel = mySpeedF - theirAlong
                if tr.minGap <= Config.Scoring.MaxLateralGap and rel >= Config.Scoring.PassMinRelative
                    and CU.Speed >= Config.Scoring.MinSpeed * 0.8 then
                    award(v, math.max(0.0, tr.minGap), oncoming)
                end
            end
        end
    end
    for v in pairs(tracks) do
        if not seen[v] then tracks[v] = nil end
    end
end

-- every frame
function Scoring.Tick(dt)
    local sc = Config.Scoring
    if not CU.Active or not CU.IsDriver or CU.Veh == 0 or IsEntityDead(CU.Ped) then
        if CU.Run then Scoring.EndRun('left_vehicle') end
        return
    end
    local r = CU.Run
    local kmh = CU.Kmh(CU.Speed)
    if not r then
        if CU.Speed >= Config.Run.StartSpeed then Scoring.StartRun() end
        return
    end

    r.time = r.time + dt
    r.distance = r.distance + CU.Speed * dt
    if r.time >= Config.Run.Duration then Scoring.EndRun('time_up') return end
    if CU.Speed < 5.5 then
        r.idle = r.idle + dt
        if r.idle > Config.Run.IdleTimeout then Scoring.EndRun('idle_end') return end
    else
        r.idle = 0.0
    end

    -- multipliers
    local now = GetGameTimer()
    local keep = {}
    for _, t in ipairs(aggroHits) do
        if now - t < sc.AggroWindow * 1000 then keep[#keep + 1] = t end
    end
    aggroHits = keep
    CU.Bonus.aggro = math.min(4, #aggroHits)
    CU.Bonus.physics = CU.Trans.mode ~= 'auto' or CU.Wheel.active

    r.speedMult = Util.Round(Util.Clamp(1.0 + (kmh - sc.SpeedMultMin) / sc.SpeedMultStep, 1.0, sc.SpeedMultMax), 1)
    local bonus = 1.0 + CU.Bonus.aggro * sc.AggroPerSegment
        + (CU.Bonus.physics and sc.PhysicsBonus or 0.0)
        + (CU.Bonus.fpv and sc.FpvBonus or 0.0)
        + CU.Bonus.sync
    r.totalMult = Util.Round(r.speedMult * bonus, 1)

    if CU.Speed >= sc.MinSpeed then
        r.points = r.points + kmh * sc.DrivePerSecond * r.totalMult * (1.0 + r.combo * sc.ComboStep) * dt
    end

    -- combo hold + bleed
    if r.holdT > 0.0 then
        r.holdT = r.holdT - dt
    elseif r.combo > 0.0 then
        r.combo = r.combo * (1.0 - sc.ComboBleed * dt) - dt * 0.25
        if r.combo < 1.0 then r.combo = 0.0 end
    end
    r.holdPct = Util.Clamp(r.holdT / sc.ComboHold, 0.0, 1.0)

    detectPasses()

    -- stats sampling
    if now > sampleAt then
        sampleAt = now + 2000
        local p = GetEntityCoords(CU.Veh)
        local zone = GetLabelText(GetNameOfZone(p.x, p.y, p.z))
        if zone and zone ~= 'NULL' then bump(r.zones, zone) end
        bump(r.cams, Camera.Label())
        bump(r.trans, CU.Trans.mode)
    end
end
