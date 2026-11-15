-- Impact detection + dynamic damage (deformation at the real contact point, tyres, glass, hood, alignment, limp mode).
Collision = { pull = 0.0 }

local lastVel     = nil
local lastImpact  = 0
local setupVeh    = 0

local function rand(a, b) return a + math.random() * (b - a) end

function Collision.Reset()
    lastVel, setupVeh = nil, 0
    Collision.pull = 0.0
end

local function setup(veh)
    setupVeh = veh
    lastVel = nil
    Collision.pull = 0.0
    if Config.Damage.Enabled then
        SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDeformationDamageMult', Config.Damage.DeformationMult)
    end
end

local function closestVehicle(veh, pos, maxDist)
    local best, bestD = 0, maxDist
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if v ~= veh then
            local d = #(GetEntityCoords(v) - pos)
            if d < bestD then best, bestD = v, d end
        end
    end
    return best
end

local function impact(veh, severity, dv)
    local cfg = Config.Damage
    local pos = GetEntityCoords(veh)
    local d = CU.Dimensions(GetEntityModel(veh))
    local other = closestVehicle(veh, pos, math.max(d.length, 5.0) + 2.0)

    -- contact direction in the car's local space
    local dir
    if other ~= 0 then
        local op = GetEntityCoords(other)
        dir = GetOffsetFromEntityGivenWorldCoords(veh, op.x, op.y, op.z)
    else
        local p = pos - dv
        dir = GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
    end
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if len < 0.001 then dir, len = vector3(0.0, 1.0, 0.0), 1.0 end
    local nx, ny = dir.x / len, dir.y / len
    local front, side = ny > 0.55, math.abs(nx) > 0.6

    local isCrash = severity >= cfg.CrashSpeedLoss
    local heavy = severity >= cfg.CrashSpeedLoss * 1.6

    if cfg.Enabled then
        -- dent where we actually got hit
        local ox, oy = nx * d.width * 0.5, ny * d.length * 0.5
        SetVehicleDamage(veh, ox, oy, 0.1, severity * cfg.ExtraDeform, math.max(0.6, severity * 0.12), true)

        local eh = GetVehicleEngineHealth(veh)
        SetVehicleEngineHealth(veh, math.max(-50.0, eh - severity * cfg.EngineDamage * (front and 1.0 or 0.35)))
        SetVehicleBodyHealth(veh, math.max(0.0, GetVehicleBodyHealth(veh) - severity * cfg.BodyDamage))

        if heavy then
            if side and math.random() < cfg.TyreBurstChance then
                local left = nx < 0
                local idx = ny >= 0 and (left and 0 or 1) or (left and 4 or 5)
                SetVehicleTyreBurst(veh, idx, false, 1000.0)
            end
            if math.random() < cfg.WindowSmashChance then
                if front then SmashVehicleWindow(veh, 6)
                elseif side then SmashVehicleWindow(veh, nx < 0 and (ny >= 0 and 0 or 2) or (ny >= 0 and 1 or 3))
                else SmashVehicleWindow(veh, 7) end
            end
            if front and math.random() < cfg.HoodPopChance then
                SetVehicleDoorOpen(veh, 4, false, false)
            end
            if cfg.SteeringPull and (front or side) then
                Collision.pull = Util.Clamp(Collision.pull + rand(-0.035, 0.035) * (severity / 8.0), -0.14, 0.14)
            end
        end
    end

    Camera.Impact(severity)
    if Config.Wheel.Rumble then
        UI.Send('wheel:rumble', { strong = Util.Clamp(severity / 14.0, 0.2, 1.0), weak = 0.6, duration = isCrash and 320 or 140 })
    end
    if other ~= 0 and CU.IsNPCVehicle(other) then Awareness.Hit(other) end
    Scoring.OnImpact(isCrash, severity, other)
end

function Collision.Tick(dt)
    local veh = CU.Veh
    if veh == 0 then lastVel = nil return end
    if setupVeh ~= veh then setup(veh) end

    local vel = GetEntityVelocity(veh)
    local flat = vector3(vel.x, vel.y, 0.0)
    if lastVel and HasEntityCollidedWithAnything(veh) then
        local dv = lastVel - flat
        local loss = #dv
        local now = GetGameTimer()
        if loss >= Config.Damage.ScrapeSpeedLoss and now - lastImpact > 450 then
            lastImpact = now
            impact(veh, loss, dv)
        end
    end
    lastVel = flat

    if Config.Damage.Enabled and Config.Damage.LimpMode then
        local eh = GetVehicleEngineHealth(veh)
        if eh < 650.0 then
            SetVehicleCheatPowerIncrease(veh, Util.Clamp((eh - 100.0) / 550.0, 0.35, 1.0))
        end
    end
end

function Collision.Repair(veh)
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehicleDirtLevel(veh, 0.0)
    Collision.pull = 0.0
end
