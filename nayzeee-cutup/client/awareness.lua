-- NPC awareness: mirror checks, high beam flashes, near miss spooks, crash reactions.
Awareness = {}

local HORN = GetHashKey('HELDDOWN')
local lastHighbeam = false

local function rand(a, b) return a + math.random() * (b - a) end

local function resumeLater(m, ms)
    m.resumeAt = GetGameTimer() + ms
end

local function honk(veh, m, ms)
    local now = GetGameTimer()
    if now - m.lastHorn < 2500 then return end
    m.lastHorn = now
    StartVehicleHorn(veh, ms or 700, HORN, false)
end

local function angryFlash(veh)
    CreateThread(function()
        for _ = 1, 2 do
            if not DoesEntityExist(veh) then return end
            SetVehicleFullbeam(veh, true)
            Wait(160)
            SetVehicleFullbeam(veh, false)
            Wait(140)
        end
    end)
end

-- Which way should this car move over? Away from the player, else right, else left.
local function yieldDir(veh)
    local p = GetEntityCoords(CU.Veh)
    local lo = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
    local away = lo.x > 0.6 and -1 or (lo.x < -0.6 and 1 or 1)
    return away, -away
end

local function react(n, m, forced)
    local veh, driver = n.veh, n.driver
    if not Traffic.Controlled(veh) or not Traffic.Controlled(driver) then return end
    local kind = forced or m.personality
    if kind == 'yielder' then
        local a, b = yieldDir(veh)
        if not Traffic.ChangeLane(veh, a) then Traffic.ChangeLane(veh, b) end
    elseif kind == 'stubborn' then
        SetDriveTaskCruiseSpeed(driver, m.cruise * rand(1.05, 1.18))
        m.cruiseUntil = GetGameTimer() + 6000
        if math.random() < 0.3 then angryFlash(veh) end
    elseif kind == 'nervous' then
        TaskVehicleTempAction(driver, veh, 1, 450)
        resumeLater(m, 800)
        if math.random() < 0.5 then honk(veh, m, 500) end
    end
end

-- every 200 ms
function Awareness.Update()
    local a = Config.Awareness
    if not a.Enabled or CU.Veh == 0 then return end
    local now = GetGameTimer()
    local myVeh = CU.Veh
    local myPos = GetEntityCoords(myVeh)
    local mySpeed = CU.Speed

    -- high beam flash (our key or the game's own high beams)
    local _, _, highbeams = GetVehicleLightsState(myVeh)
    local hb = highbeams == 1 or highbeams == true
    if hb and not lastHighbeam then CU.Flash.pending = true end
    lastHighbeam = hb

    local flash = CU.Flash.pending
    CU.Flash.pending = false

    for _, n in ipairs(CU.NearbyNPC) do
        local veh = n.veh
        if DoesEntityExist(veh) then
            local m = Traffic.Meta(veh)

            -- timed resumes / cruise resets
            if m.resumeAt and now > m.resumeAt then
                m.resumeAt = nil
                if Traffic.Controlled(n.driver) and not m.changing then Traffic.Wander(veh, n.driver, m.cruise) end
            end
            if m.cruiseUntil and now > m.cruiseUntil then
                m.cruiseUntil = nil
                if Traffic.Controlled(n.driver) then SetDriveTaskCruiseSpeed(n.driver, m.cruise) end
            end

            if now > m.hitAt + 8000 then
                -- where is the player from this driver's point of view?
                local lo = GetOffsetFromEntityGivenWorldCoords(veh, myPos.x, myPos.y, myPos.z)
                local closing = mySpeed - GetEntitySpeed(veh)
                local sameDir = math.abs(Util.AngleDiff(GetEntityHeading(veh), GetEntityHeading(myVeh))) < 60.0

                -- mirror check: player coming up fast in the same lane
                if sameDir and lo.y < -3.0 and lo.y > -a.NoticeDistance and math.abs(lo.x) < 2.6 and closing > a.ClosingSpeed then
                    if not m.noticed then
                        m.noticed, m.reacted = true, false
                        m.reactAt = now + math.floor(rand(a.ReactionMin, a.ReactionMax) * 1000)
                    end
                elseif lo.y > 2.0 or lo.y < -(a.NoticeDistance + 20.0) then
                    m.noticed, m.reacted, m.forced = false, false, nil
                end

                -- flash: cars ahead of the player inside the cone
                if flash and sameDir and n.dist < a.FlashRange then
                    local vp = GetEntityCoords(veh)
                    local pl = GetOffsetFromEntityGivenWorldCoords(myVeh, vp.x, vp.y, vp.z)
                    if pl.y > 4.0 then
                        local ang = math.deg(math.atan(math.abs(pl.x), pl.y))
                        if ang < a.FlashCone then
                            m.noticed, m.reacted = true, false
                            m.forced = math.random() < a.FlashYieldChance and 'yielder' or 'stubborn'
                            m.reactAt = now + math.floor(rand(a.ReactionMin * 0.6, a.ReactionMax * 0.8) * 1000)
                        end
                    end
                end

                if m.noticed and not m.reacted and now >= m.reactAt then
                    m.reacted = true
                    react(n, m, m.forced)
                end
            end
        end
    end
end

-- called by scoring when you thread past a car
function Awareness.NearMiss(veh, gap)
    local a = Config.Awareness
    if not a.Enabled or not DoesEntityExist(veh) then return end
    local m = Traffic.Meta(veh)
    local spook = Util.Clamp(1.2 - gap, 0.2, 1.0)
    if math.random() < a.HornChance * spook * 1.6 then honk(veh, m, 600 + math.random(600)) end
    if math.random() < a.SwerveChance * spook * 1.6 then
        local away = yieldDir(veh)
        -- they swerve away from where you just were
        Traffic.ChangeLane(veh, away)
    elseif m.personality == 'stubborn' and math.random() < 0.25 then
        angryFlash(veh)
    end
end

-- called by collision when you hit an NPC car
function Awareness.Hit(veh)
    if not DoesEntityExist(veh) then return end
    local m = Traffic.Meta(veh)
    m.hitAt = GetGameTimer()
    local driver = GetPedInVehicleSeat(veh, -1)
    if driver == 0 or IsPedAPlayer(driver) then return end
    if not Traffic.Controlled(veh) or not Traffic.Controlled(driver) then return end
    SetVehicleIndicatorLights(veh, 0, true)
    SetVehicleIndicatorLights(veh, 1, true)
    honk(veh, m, 1400)
    TaskVehicleTempAction(driver, veh, 27, 3000)
    m.cruise = m.cruise * 0.85
    m.changing = false
    resumeLater(m, 4500)
end
