if not NAYZEEE_LOCK_OK then return end

-- Client bridge (open file): vehicle keys, fuel and notifications for purchased / test drive vehicles.

ClientBridge = {
    Keys   = 'default',   -- default (fires the common key events) | qb-vehiclekeys | qs-vehiclekeys | wasabi_carlock | okokVehicleKey | mk_vehiclekeys | custom
    Fuel   = 'auto',      -- auto | ox_fuel | LegacyFuel | ps-fuel | cdn-fuel | okokGasStation | lj-fuel | none
    NotifyWith = 'ox_lib', -- ox_lib | esx | qb | okokNotify | custom
}

function ClientBridge.GiveKeys(vehicle, plate)
    local k = ClientBridge.Keys
    if k == 'qs-vehiclekeys' then
        pcall(function() exports['qs-vehiclekeys']:GiveKeys(plate, GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)), true) end)
    elseif k == 'wasabi_carlock' then pcall(function() exports.wasabi_carlock:GiveKey(plate) end)
    elseif k == 'okokVehicleKey' then TriggerEvent('okokVehicleKey:AddKey', plate)
    elseif k == 'mk_vehiclekeys' then pcall(function() exports.mk_vehiclekeys:AddKey(vehicle) end)
    elseif k == 'custom' then
        -- exports['my-keys']:GiveKeys(plate)
    else
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
        TriggerEvent('qb-vehiclekeys:client:AddKeys', plate)
    end
end

local fuelResources = { 'ox_fuel', 'LegacyFuel', 'ps-fuel', 'cdn-fuel', 'okokGasStation', 'lj-fuel' }

function ClientBridge.SetFuel(vehicle, level)
    local f = ClientBridge.Fuel
    if f == 'none' then return end
    if f == 'auto' then
        f = nil
        for _, r in ipairs(fuelResources) do if GetResourceState(r) == 'started' then f = r break end end
    end
    if f == 'ox_fuel' then Entity(vehicle).state.fuel = level
    elseif f then pcall(function() exports[f]:SetFuel(vehicle, level) end)
    else SetVehicleFuelLevel(vehicle, level) end
end

function ClientBridge.Notify(message, kind)
    kind = kind or 'inform'
    local n = ClientBridge.NotifyWith
    if n == 'esx' then TriggerEvent('esx:showNotification', message, kind)
    elseif n == 'qb' then TriggerEvent('QBCore:Notify', message, kind == 'inform' and 'primary' or kind)
    elseif n == 'okokNotify' then exports.okokNotify:Alert(T('APP_TITLE'), message, 5000, kind == 'inform' and 'info' or kind)
    elseif n == 'custom' then
        -- exports['my-notify']:Notify(message, kind)
    else
        lib.notify({ title = T('APP_TITLE'), description = message, type = kind })
    end
end
