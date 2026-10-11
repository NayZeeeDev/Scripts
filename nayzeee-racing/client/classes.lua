if not NAYZEEE_LOCK_OK then return end

--[[
    Vehicle class: Config.Vehicles.GetClass wins. When it returns 'auto' the class comes from the
    model's handling (top speed, acceleration, braking, traction) mapped through Config.Vehicles.AutoClass.
]]

local AC = Config.Vehicles.AutoClass
local hidden = {}
for _, c in ipairs(AC.Hidden or {}) do hidden[c] = true end
local cache = {}

-- Performance index ~500 (slow compact) .. ~950 (fastest supers)
function PerformanceIndex(model)
    local speed = GetVehicleModelEstimatedMaxSpeed(model) or 0.0
    local accel = GetVehicleModelAcceleration(model) or 0.0
    local brake = GetVehicleModelMaxBraking(model) or 0.0
    local trac = GetVehicleModelMaxTraction(model) or 0.0
    local function n(v, ref, cap) return math.min(v / ref, cap) end
    local pi = 0.40 * n(speed, 50.0, 1.3) + 0.30 * n(accel, 0.4, 1.5) + 0.12 * n(brake, 1.2, 1.5) + 0.18 * n(trac, 3.0, 1.3)
    return math.floor(pi * 1000 + 0.5), { speed = speed, accel = accel, brake = brake, traction = trac }
end

function AutoClass(model)
    local c = cache[model]
    if c ~= nil then return c or nil end
    local gta = GetVehicleClassFromName(model)
    if hidden[gta] then cache[model] = false return nil end
    local list = gta == 8 and AC.Bikes or AC.Cars
    local pi = PerformanceIndex(model)
    local out = list[1] and list[1].class or nil
    for _, t in ipairs(list) do if pi >= t.min then out = t.class end end
    cache[model] = out or false
    return out
end

function VehicleClass(model)
    local c = Config.Vehicles.GetClass(model)
    if c == 'auto' then return AutoClass(model) end
    return c
end

if AC.Command then
    RegisterCommand(AC.Command, function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if not veh or veh == 0 then return Config.Notify(L('CLASS_NOT_IN_CAR'), 'error') end
        local model = GetEntityModel(veh)
        local pi, s = PerformanceIndex(model)
        local msg = L('CLASS_INFO', GetDisplayNameFromVehicleModel(model), tostring(VehicleClass(model) or '-'), pi,
            s.speed * 3.6, s.accel, s.brake, s.traction)
        print(('[racing] %s'):format(msg))
        Config.Notify(msg, 'inform')
    end, false)
end
