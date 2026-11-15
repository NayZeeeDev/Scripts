-- Auto / sequential / H-pattern gearbox, rev limiter, ABS + TC lights.
Transmission = { absLight = false, tcLight = false }

local gear        = 1        -- -1 R, 0 N, 1..n
local cutToggle   = false
local cutAt       = 0
local heldBrake   = false

local LABELS = { auto = 'Automatic', sequential = 'Sequential', hpattern = 'H-Pattern' }

local function inUse()
    if CU.Veh == 0 or not CU.IsDriver then return false end
    return CU.Active or Config.Everywhere.Transmission
end

function Transmission.Reset()
    gear = 1
    heldBrake = false
end

function Transmission.SetMode(mode)
    if not LABELS[mode] then return end
    CU.Trans.mode = mode
    CU.Settings.gameplay.transmission = mode
    gear = 1
    UI.Toast(L('gearbox', LABELS[mode]), nil, 'info')
end

local function clutchIn()
    return CU.Trans.clutchKey or (CU.Wheel.active and CU.Wheel.clutch > 0.5)
end

local function maxGear()
    return math.max(1, GetVehicleHighGear(CU.Veh))
end

function Transmission.ShiftUp()
    if not inUse() or CU.Trans.mode == 'auto' then return end
    if CU.Trans.mode == 'hpattern' and Config.Transmission.RequireClutchHPattern and not clutchIn() then
        UI.Toast(L('no_clutch'), nil, 'warn') UI.Send('sound', 'grind') return
    end
    gear = math.min(maxGear(), gear + 1)
    UI.Send('sound', 'shift')
end

function Transmission.ShiftDown()
    if not inUse() or CU.Trans.mode == 'auto' then return end
    if CU.Trans.mode == 'hpattern' and Config.Transmission.RequireClutchHPattern and not clutchIn() then
        UI.Toast(L('no_clutch'), nil, 'warn') UI.Send('sound', 'grind') return
    end
    gear = math.max(-1, gear - 1)
    UI.Send('sound', 'shift')
end

-- H-pattern shifter: g = -1 (R), 0 (released = neutral), 1..7
function Transmission.Select(g)
    if not inUse() or CU.Trans.mode ~= 'hpattern' then return end
    if g ~= 0 and Config.Transmission.RequireClutchHPattern and not clutchIn() then
        UI.Send('sound', 'grind')
        gear = 0
        return
    end
    gear = Util.Clamp(g, -1, maxGear())
    if g ~= 0 then UI.Send('sound', 'shift') end
end

function Transmission.DisplayGear()
    local veh = CU.Veh
    if veh == 0 then return 'N' end
    if CU.Trans.mode == 'auto' then
        local fwd = GetEntitySpeedVector(veh, true).y
        if fwd < -0.5 then return 'R' end
        if CU.Speed < 0.5 and GetControlNormal(0, 71) < 0.05 then return 'N' end
        local g = GetVehicleCurrentGear(veh)
        return g == 0 and 'R' or tostring(g)
    end
    if gear == -1 then return 'R' elseif gear == 0 then return 'N' end
    return tostring(gear)
end

local function lights(veh, thr, brk)
    local speed = CU.Speed
    local abs, tc = false, false
    if speed > 6.0 then
        local wheels = GetVehicleNumberOfWheels(veh)
        for i = 0, wheels - 1 do
            local ws = math.abs(GetVehicleWheelSpeed(veh, i))
            if brk > 0.6 and ws < speed * 0.75 then abs = true end
            if thr > 0.6 and ws > speed * 1.15 + 1.5 then tc = true end
        end
    elseif thr > 0.7 and speed > 0.5 then
        for i = 0, GetVehicleNumberOfWheels(veh) - 1 do
            if math.abs(GetVehicleWheelSpeed(veh, i)) > speed + 3.0 then tc = true end
        end
    end
    Transmission.absLight, Transmission.tcLight = abs, tc
end

-- runs every frame AFTER Wheel.Apply so wheel pedals are already injected
function Transmission.Tick(dt)
    local veh = CU.Veh
    if not inUse() then return end
    local thr = GetControlNormal(0, 71)
    local brk = GetControlNormal(0, 72)
    lights(veh, thr, brk)
    CU.Bonus.physics = CU.Trans.mode ~= 'auto' or CU.Wheel.active
    if CU.Trans.mode == 'auto' then return end

    local fwd = GetEntitySpeedVector(veh, true).y
    local high = maxGear()
    if gear > high then gear = high end

    if gear == 0 then
        -- neutral: no drive, free revving
        DisableControlAction(0, 71, true)
        local rpm = GetVehicleCurrentRpm(veh)
        SetVehicleCurrentRpm(veh, Util.Lerp(rpm, 0.2 + thr * 0.8, Util.Clamp(dt * 6.0, 0, 1)))
        if brk > 0.05 and fwd < 1.0 then SetControlNormal(0, 72, 0.0) end
    elseif gear == -1 then
        -- reverse: throttle drives backwards, brake pedal brakes
        if fwd < 1.0 then
            SetControlNormal(0, 72, thr)
            SetControlNormal(0, 71, brk)
        else
            SetControlNormal(0, 71, 0.0)
            SetControlNormal(0, 72, math.max(thr, brk))
        end
    else
        SetVehicleNextGear(veh, gear)
        SetVehicleCurrentGear(veh, gear)
        -- brake never turns into reverse while in a forward gear
        if brk > 0.05 and fwd < 0.8 then
            SetControlNormal(0, 72, 0.0)
            SetVehicleHandbrake(veh, true)
            heldBrake = true
        elseif heldBrake then
            SetVehicleHandbrake(veh, false)
            heldBrake = false
        end
        -- bounce off the limiter
        if Config.Transmission.RevLimiterCut and thr > 0.1 and GetVehicleCurrentRpm(veh) >= 0.985 then
            local now = GetGameTimer()
            if now - cutAt > 55 then cutToggle = not cutToggle cutAt = now end
            if cutToggle then SetControlNormal(0, 71, 0.0) end
        end
    end
end
