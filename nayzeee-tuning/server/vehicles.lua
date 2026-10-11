--[[
    Custom vehicle data ('extras'): stance, wheel size, ride height, air ride, engine swap, nitrous,
    ECU, anti-lag, launch control, underglow modes, wear, mileage and GPS trackers.
    Stored per plate and pushed to every client through the 'nzTune' state bag.
]]

Vehicles = { cache = {} }  -- [plate] = { data = {}, model = 'name' }

local function emptyWear()
    return { engine = 100, transmission = 100, brakes = 100, suspension = 100, tyres = 100, turbo = 100 }
end

function Vehicles.Load(plate)
    plate = NZ.TrimPlate(plate)
    if plate == '' then return nil end
    local c = Vehicles.cache[plate]
    if c then return c end
    local row = MySQL.single.await('SELECT model, data FROM nz_tuning_vehicles WHERE plate = ?', { plate })
    c = { data = row and DB.Decode(row.data, {}) or {}, model = row and row.model, exists = row ~= nil }
    Vehicles.cache[plate] = c
    return c
end

function Vehicles.Get(plate)
    local c = Vehicles.Load(plate)
    return c and c.data or {}
end

function Vehicles.Save(plate, data, model)
    plate = NZ.TrimPlate(plate)
    local c = Vehicles.Load(plate)
    if not c then return end   -- blank plate
    c.data = data
    c.model = model or c.model
    c.exists = true
    MySQL.insert('INSERT INTO nz_tuning_vehicles (plate, model, data) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE model = VALUES(model), data = VALUES(data)',
        { plate, c.model, json.encode(data) })
end

-- only what other clients need goes into the state bag (wear/km stay server-side)
local function publicData(data)
    local pub = {}
    for k, v in pairs(data) do
        if k ~= 'wear' and k ~= 'km' and k ~= 'locator' then pub[k] = v end
    end
    if data.wear then
        -- clients get performance scaling only
        local eff = {}
        for part, e in pairs(Config.Wear.Effects) do
            local cond = data.wear[part] or 100
            if cond < e.at then eff[part] = NZ.Round(e.floor + (1 - e.floor) * (cond / e.at), 3) end
        end
        if next(eff) then pub.wearFx = eff end
    end
    return next(pub) and pub or nil
end

function Vehicles.Push(veh, plate)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local data = Vehicles.Get(plate or GetVehicleNumberPlateText(veh))
    Entity(veh).state:set('nzTune', publicData(data), true)
end

function Vehicles.Update(plate, veh, mutate, model)
    plate = NZ.TrimPlate(plate)
    local data = NZ.Copy(Vehicles.Get(plate))
    mutate(data)
    Vehicles.Save(plate, data, model)
    if veh then Vehicles.Push(veh, plate) end
    return data
end

-- find a spawned vehicle by plate
function Vehicles.FindByPlate(plate)
    plate = NZ.TrimPlate(plate)
    for _, veh in ipairs(GetAllVehicles()) do
        if NZ.TrimPlate(GetVehicleNumberPlateText(veh)) == plate then return veh end
    end
end

-- tell the entity owner to apply full GTA properties (order completion, police strip)
function Vehicles.SendProps(veh, props)
    Entity(veh).state:set('nzProps', { props = props, t = os.time() }, true)
end

--------------------------------------------------------------------- attach data to spawned cars

-- garages spawn the car first and set the real plate a moment later (and it takes a sync to reach
-- the server): check often early on so the sound / nitrous / stance are there as soon as the plate is
local ATTACH_DELAYS = { 150, 250, 250, 250, 250, 250, 500, 500, 500, 1000, 1000, 2000, 4000 }
local pending = {}
local function attach(veh)
    if pending[veh] then return end
    pending[veh] = true
    CreateThread(function()
        local checked
        for _, delay in ipairs(ATTACH_DELAYS) do
            Wait(delay)
            if not DoesEntityExist(veh) then break end
            local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
            if plate ~= '' and plate ~= checked then
                checked = plate
                local c = Vehicles.Load(plate)
                if c and c.exists then
                    Vehicles.Push(veh, plate)
                    break
                end
            end
        end
        pending[veh] = nil
    end)
end

-- a garage just spawned this car: push its data as soon as the server sees the plate
-- hint: the plate the garage is setting (only waited for, never trusted on its own)
-- trusted: the hint comes from server code (the garage's own DB plate), push it right away
local watching = {}
function Vehicles.Watch(veh, hint, trusted)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    hint = type(hint) == 'string' and NZ.TrimPlate(hint) or nil
    if trusted and hint and hint ~= '' then
        local c = Vehicles.Load(hint)
        if c and c.exists then Vehicles.Push(veh, hint) end
        return
    end
    if watching[veh] then return end
    watching[veh] = true
    CreateThread(function()
        for _ = 1, 50 do
            if not DoesEntityExist(veh) then break end
            local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
            if plate ~= '' and (not hint or plate == hint) then
                local c = Vehicles.Load(plate)
                if c and c.exists then Vehicles.Push(veh, plate) break end
                if hint then break end
            end
            Wait(100)
        end
        watching[veh] = nil
    end)
end

AddEventHandler('entityCreated', function(ent)
    if not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then return end
    attach(ent)
end)

-- a client has a car with no data yet (fresh from a garage, plate changed after spawn, resource restart, ...)
-- seen: the plate that client sees. Only a hint: the data is looked up by the plate the server sees,
-- we just wait (briefly) for the server's copy to catch up with the garage's plate change
RegisterNetEvent('nayzeee-tuning:requestData', function(netId, seen)
    local src = source
    if not Core.Throttle(src, 'reqdata', 900) then return end
    local veh = Core.VehicleFromNet(netId)
    if not veh then return end
    seen = type(seen) == 'string' and NZ.TrimPlate(seen) or nil
    for _ = 1, 30 do
        local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
        if not seen or plate == seen then
            local c = Vehicles.Load(plate)
            if c and c.exists then Vehicles.Push(veh, plate) end
            return
        end
        Wait(100)
        if not DoesEntityExist(veh) then return end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        while not Core.Ready do Wait(200) end
        for _, veh in ipairs(GetAllVehicles()) do attach(veh) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, veh in ipairs(GetAllVehicles()) do
        if Entity(veh).state.nzTune then Entity(veh).state:set('nzTune', nil, true) end
    end
end)

--------------------------------------------------------------------- driving telemetry (wear + mileage)

local function isDriver(src, veh)
    return GetPedInVehicleSeat(veh, -1) == GetPlayerPed(src)
end

RegisterNetEvent('nayzeee-tuning:telemetry', function(netId, km, hardKm, hasTurbo)
    local src = source
    if not Config.Wear.Enabled then return end
    if not Core.Throttle(src, 'telemetry', 20000) then return end
    local veh = Core.VehicleFromNet(netId)
    if not veh or not isDriver(src, veh) then return end
    km, hardKm = NZ.Num(km) or 0, NZ.Num(hardKm) or 0
    -- a car can't honestly do more than ~ 6 km in the sync window
    local maxKm = Config.Wear.SyncEvery * 0.1 + 1.0
    if km <= 0 or km > maxKm then return end
    hardKm = NZ.Clamp(hardKm, 0, km)

    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    if Config.Wear.OwnedOnly and not Bridge.GetVehicleOwner(plate) then return end

    Vehicles.Update(plate, veh, function(d)
        d.km = NZ.Round((d.km or 0) + km, 2)
        d.wear = d.wear or emptyWear()
        local effKm = (km - hardKm) + hardKm * Config.Wear.HardDriving
        local knock = d.ecu and d.ecu.knock or 0
        for part, rate in pairs(Config.Wear.RatePerKm) do
            if part ~= 'turbo' or hasTurbo == true then
                local r = rate
                if part == 'brakes' and d.ceramic then r = r * Config.CeramicBrakes.WearRate end
                if part == 'engine' and knock > 0 then r = r * (1 + knock * Config.ECU.Map.KnockWear) end
                d.wear[part] = NZ.Round(math.max(0, (d.wear[part] or 100) - r * effKm), 2)
            end
        end
    end)
end)

--------------------------------------------------------------------- nitrous

RegisterNetEvent('nayzeee-tuning:nitrousUsed', function(netId, used)
    local src = source
    local veh = Core.VehicleFromNet(netId)
    used = NZ.Num(used)
    -- the last flush can arrive just after the driver got out, so being next to the car is enough
    if not veh or not used or used <= 0 then return end
    if not isDriver(src, veh) and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > 8.0 then return end
    if not Core.Throttle(src, 'nitro', 100) then return end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    Vehicles.Update(plate, veh, function(d)
        if d.nitrous then d.nitrous.amount = NZ.Round(math.max(0, (d.nitrous.amount or 0) - used), 1) end
    end)
end)

if Config.Nitrous.Enabled and Config.Nitrous.RefillItem then
    CreateThread(function()
        while not Core.Ready do Wait(500) end
        Bridge.RegisterUsableItem(Config.Nitrous.RefillItem, function(src)
            TriggerClientEvent('nayzeee-tuning:useNitrousBottle', src)
        end)
    end)
end

lib.callback.register('nayzeee-tuning:refillNitrous', function(src, netId)
    local veh = Core.VehicleFromNet(netId)
    if not veh then return false end
    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 5.0 then return false end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)
    if not d.nitrous then return false, L('no_nitrous') end
    local lvl = Config.Nitrous.Levels[d.nitrous.level]
    if (d.nitrous.amount or 0) >= (lvl and lvl.capacity or 100) then return false, L('nitrous_full') end
    if not Bridge.RemoveItem(src, Config.Nitrous.RefillItem, 1) then return false, L('missing_item') end
    if Config.UsableItems.EmptyNitrous then Bridge.AddItem(src, Config.UsableItems.EmptyNitrous, 1) end
    Vehicles.Update(plate, veh, function(x)
        x.nitrous.amount = math.min(lvl and lvl.capacity or 100, (x.nitrous.amount or 0) + Config.Nitrous.RefillItemAmount)
    end)
    return true
end)

--------------------------------------------------------------------- air ride

RegisterNetEvent('nayzeee-tuning:airRide', function(netId, preset)
    local src = source
    local veh = Core.VehicleFromNet(netId)
    if not veh or not isDriver(src, veh) then return end
    if not Core.Throttle(src, 'airride', 600) then return end
    preset = NZ.Int(preset)
    if not preset or not Config.AirRide.Presets[preset] then return end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)
    if not d.airride then return end
    Vehicles.Update(plate, veh, function(x) x.air = preset end)
end)

--------------------------------------------------------------------- locator

lib.callback.register('nayzeee-tuning:locatorList', function(src)
    local id = Bridge.GetIdentifier(src)
    if not id then return {} end
    local out = {}
    for _, plate in ipairs(Bridge.GetOwnedPlates(id)) do
        local d = Vehicles.Get(plate)
        if d.locator then
            local c = Vehicles.cache[plate]
            out[#out + 1] = { plate = plate, model = c and c.model or '' }
        end
    end
    return out
end)

lib.callback.register('nayzeee-tuning:locate', function(src, plate)
    if not Core.Throttle(src, 'locate', Config.Locator.Cooldown * 1000) then return false, L('locator_cooldown') end
    local id = Bridge.GetIdentifier(src)
    plate = NZ.TrimPlate(tostring(plate or ''))
    if not id or Bridge.GetVehicleOwner(plate) ~= id then return false, L('not_owner') end
    if not Vehicles.Get(plate).locator then return false, L('no_locator') end
    local veh = Vehicles.FindByPlate(plate)
    if not veh then return false, L('locator_no_signal') end
    local c = GetEntityCoords(veh)
    return true, { x = c.x, y = c.y, z = c.z }
end)

--------------------------------------------------------------------- exports

exports('GetVehicleData', function(plate) return NZ.Copy(Vehicles.Get(plate)) end)
exports('SetVehicleData', function(plate, data)
    Vehicles.Save(plate, data)
    local veh = Vehicles.FindByPlate(plate)
    if veh then Vehicles.Push(veh, plate) end
end)
-- call right after a garage has set the plate: pushes the data now (falls back to watching the car)
exports('RefreshVehicle', function(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local c = plate ~= '' and Vehicles.Load(plate)
    if c and c.exists then Vehicles.Push(veh, plate) return true end
    Vehicles.Watch(veh)
    return false
end)
