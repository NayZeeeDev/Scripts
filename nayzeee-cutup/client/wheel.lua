-- Race wheel bridge. The page reads the wheel with the Gamepad API and posts the
-- mapped values here, we inject them into the car every frame.
Wheel = {}

local KVP = 'nayzeee-cutup:wheels'
local profiles = {}

function Wheel.Load()
    local raw = GetResourceKvpString(KVP)
    profiles = raw and json.decode(raw) or {}
end

function Wheel.GetProfiles() return profiles end

local function inUse()
    if not Config.Wheel.Enabled or CU.Veh == 0 or not CU.IsDriver then return false end
    return CU.Active or Config.Everywhere.Wheel
end

RegisterNUICallback('wheelSave', function(data, cb)
    if type(data) == 'table' and type(data.profiles) == 'table' then
        profiles = data.profiles
        SetResourceKvp(KVP, json.encode(profiles))
    end
    cb({ ok = true })
end)

RegisterNUICallback('wheelInput', function(d, cb)
    local w = CU.Wheel
    if type(d) == 'table' then
        w.steer     = Util.Clamp(tonumber(d.s) or 0.0, -1.0, 1.0)
        w.throttle  = Util.Clamp(tonumber(d.t) or 0.0, 0.0, 1.0)
        w.brake     = Util.Clamp(tonumber(d.b) or 0.0, 0.0, 1.0)
        w.clutch    = Util.Clamp(tonumber(d.c) or 0.0, 0.0, 1.0)
        w.handbrake = d.h == true
        w.horn      = d.horn == true
        w.lookBack  = d.lb == true
        w.active    = Config.Wheel.Enabled and d.on == true
        w.lastInput = GetGameTimer()
    end
    cb(1)
end)

local actions = {
    shiftUp   = function() Transmission.ShiftUp() end,
    shiftDown = function() Transmission.ShiftDown() end,
    camera    = function() if Camera then Camera.Cycle() end end,
    flash     = function() CU.Flash.pending = true end,
    hud       = function() ExecuteCommand('cutuphud') end,
    mode      = function() ExecuteCommand('cutup') end,
}

RegisterNUICallback('wheelButton', function(d, cb)
    if type(d) == 'table' and inUse() then
        if d.action == 'gear' then
            Transmission.Select(tonumber(d.value) or 0)
        elseif d.action == 'flash' then
            SetVehicleFullbeam(CU.Veh, d.down == true)
            if d.down then CU.Flash.pending = true end
        elseif d.down and actions[d.action] then
            actions[d.action]()
        end
    end
    cb(1)
end)

-- every frame, before Transmission.Tick
function Wheel.Apply()
    local w = CU.Wheel
    local pull = Collision and Collision.pull or 0.0
    if not inUse() then return end
    if w.active and GetGameTimer() - w.lastInput < Config.Wheel.IdleRelease * 1000 then
        SetControlNormal(0, 59, Util.Clamp(w.steer + pull, -1.0, 1.0))
        SetControlNormal(0, 71, w.throttle)
        SetControlNormal(0, 72, w.brake)
        if w.handbrake then SetControlNormal(0, 76, 1.0) end
        if w.horn then SetControlNormal(0, 86, 1.0) end
    else
        w.active = false
        if pull ~= 0.0 and CU.Speed > 3.0 then
            SetControlNormal(0, 59, Util.Clamp(GetControlNormal(0, 59) + pull, -1.0, 1.0))
        end
    end
end
