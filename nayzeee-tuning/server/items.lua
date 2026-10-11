--[[ Usable items, driver remotes (lighting controller / stancer kit / assists) and synced install sounds. ]]

local U = Config.UsableItems

local function nearVeh(src, netId, dist)
    local veh = Core.VehicleFromNet(netId)
    if not veh then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(veh)) > (dist or 6.0) then return nil end
    return veh
end

local function isDriver(src, veh) return GetPedInVehicleSeat(veh, -1) == GetPlayerPed(src) end

--------------------------------------------------------------------- usable items

CreateThread(function()
    while not Core.Ready do Wait(500) end
    local function reg(item, event)
        if item then Bridge.RegisterUsableItem(item, function(src) TriggerClientEvent(event, src) end) end
    end
    if Config.Tablet.Enabled then reg(Config.Tablet.Item, 'nayzeee-tuning:useTablet') end
    reg(U.LightingController, 'nayzeee-tuning:useLighting')
    reg(U.StancerKit, 'nayzeee-tuning:useStancer')
    reg(U.RepairKit and U.RepairKit.item, 'nayzeee-tuning:useRepairKit')
    reg(U.DuctTape and U.DuctTape.item, 'nayzeee-tuning:useDuctTape')
    reg(U.CleaningKit and U.CleaningKit.item, 'nayzeee-tuning:useCleaningKit')
end)

-- consume a kit once the client finished the progress bar
lib.callback.register('nayzeee-tuning:useKit', function(src, kind, netId)
    local veh = nearVeh(src, netId, 5.0)
    if not veh then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    if kind == 'repair' then
        if U.RepairKit.mechanicsOnly and not Shops_IsAnyEmployee(src) then return false, L('no_permission') end
        if not Bridge.RemoveItem(src, U.RepairKit.item, 1) then return false, L('missing_item') end
        return true, { engine = U.RepairKit.engine, body = U.RepairKit.body }
    elseif kind == 'tape' then
        local d = Vehicles.Get(plate)
        if (d.tape or 0) >= U.DuctTape.maxUses then return false, L('tape_limit') end
        if not Bridge.RemoveItem(src, U.DuctTape.item, 1) then return false, L('missing_item') end
        Vehicles.Update(plate, veh, function(x) x.tape = (x.tape or 0) + 1 end)
        return true, { engine = U.DuctTape.minEngine }
    elseif kind == 'clean' then
        if not Bridge.RemoveItem(src, U.CleaningKit.item, 1) then return false, L('missing_item') end
        return true, {}
    end
    return false
end)

function Shops_IsAnyEmployee(src)
    for id, shop in pairs(Config.Shops) do
        if shop.job and Core.IsEmployee(src, id) then return true end
    end
    return false
end

-- a full repair at a shop clears the duct tape counter
AddEventHandler('nayzeee-tuning:repaired', function(plate)
    local d = Vehicles.Get(plate)
    if d.tape then Vehicles.Update(plate, Vehicles.FindByPlate(plate), function(x) x.tape = nil end) end
end)

--------------------------------------------------------------------- lighting controller

lib.callback.register('nayzeee-tuning:lighting', function(src, netId, data)
    if not U.LightingController or Bridge.ItemCount(src, U.LightingController) < 1 then return false, L('missing_item') end
    local veh = nearVeh(src, netId, 4.0)
    if not veh or not isDriver(src, veh) then return false, L('must_drive') end
    if type(data) ~= 'table' or type(data.color) ~= 'table' then return false end
    local c = data.color
    local rgb = { NZ.Clamp(math.floor(tonumber(c.r) or 255), 0, 255), NZ.Clamp(math.floor(tonumber(c.g) or 255), 0, 255), NZ.Clamp(math.floor(tonumber(c.b) or 255), 0, 255) }
    local sides = { data.l == true, data.r == true, data.f == true, data.b == true }
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)

    if data.pattern ~= nil then
        if not d.neonOwned and not d.neonPattern and data.pattern ~= 'static' then return false, L('need_neon_pattern') end
        if data.pattern ~= 'static' and not NZ.PatternIds[data.pattern] then return false end
        Vehicles.Update(plate, veh, function(x)
            if data.pattern == 'static' then x.neonPattern = nil
            else x.neonPattern = { id = data.pattern, speed = NZ.Clamp(math.floor(tonumber(data.speed) or 5), 1, 10), color2 = x.neonPattern and x.neonPattern.color2 } end
        end)
    end

    local partial = { neonEnabled = sides, neonColor = rgb }
    Vehicles.SendProps(veh, partial)
    local stored = Bridge.GetVehicleProps(plate)
    if stored then
        stored.neonEnabled, stored.neonColor = sides, rgb
        Bridge.SaveVehicleProps(plate, stored)
    end
    return true
end)

--------------------------------------------------------------------- stancer kit

lib.callback.register('nayzeee-tuning:stancer', function(src, netId, stance, height)
    if not U.StancerKit or Bridge.ItemCount(src, U.StancerKit) < 1 then return false, L('missing_item') end
    local veh = nearVeh(src, netId, 5.0)
    if not veh then return false, L('too_far') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local d = Vehicles.Get(plate)
    if U.StancerNeedsFitment and not d.stance and not d.stanceKit then return false, L('need_fitment') end
    if stance and not NZ.Validate('stance', stance) then return false end
    if height ~= nil and not NZ.Validate('height', height) then return false end
    if d.airride then height = nil end
    Vehicles.Update(plate, veh, function(x)
        if stance then
            NZ.ApplyToExtras(x, 'stance', stance)
            x.stanceKit = true
        end
        if height ~= nil then x.height = height ~= 0 and height or nil end
    end)
    return true
end)

--------------------------------------------------------------------- driver assists

RegisterNetEvent('nayzeee-tuning:assist', function(netId, which, on)
    local src = source
    if not Config.DriverAssists.Enabled or (which ~= 'tcs' and which ~= 'esc') then return end
    if not Core.Throttle(src, 'assist', 500) then return end
    local veh = nearVeh(src, netId, 4.0)
    if not veh or not isDriver(src, veh) then return end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    Vehicles.Update(plate, veh, function(x) x[which] = on == true or nil end)
end)

--------------------------------------------------------------------- install sounds heard by everyone nearby

RegisterNetEvent('nayzeee-tuning:sfx', function(name, coords)
    local src = source
    if type(name) ~= 'string' or not Config.Install.Sounds[name] then return end
    if not Core.Throttle(src, 'sfx', 700) then return end
    local pos = GetEntityCoords(GetPlayerPed(src))
    local range = Config.Install.SoundRange
    for _, id in ipairs(GetPlayers()) do
        local t = tonumber(id)
        if t ~= src then
            local d = #(GetEntityCoords(GetPlayerPed(t)) - pos)
            if d <= range then TriggerClientEvent('nayzeee-tuning:sfx', t, name, 1.0 - d / range) end
        end
    end
end)
