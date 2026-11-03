--[[
  nayzeee-garages adapter for lb-phone's Garage app  (framework folder: qb)

  WHERE IT GOES  lb-phone/server/custom/frameworks/qb/vehicles.lua
  WHAT IT DOES   Replaces that file. lb-phone calls the two global functions below:
                   GetPlayerVehicles(source) -> the vehicle list of the Garage app
                   GetVehicle(source, plate) -> the valet ("bring my car"): must return the
                                                spawn data and mark the vehicle out
                 Both go through nayzeee-garages, so the app shows nayzeee's garage names,
                 impounds, fuel / engine / body, and the valet follows nayzeee's rules
                 (ownership / shares, blocked, impounded, finance, already out, garage
                 access) and is tracked like a normal retrieve (keys, duplicate protection,
                 storing it later, damage / fuel / mileage kept).
  BACK UP        the original file first; it is restored by putting it back.
  CONFIRMED      against lb-phone 2.9.0 open files (github.com/lbphone/files): the two
                 function names, the VehicleData fields, the vehicleData fields read by
                 client/custom/frameworks/<fw>/vehicles.lua (hash, mods, plate, fuel / ESX:
                 vehicle JSON) and by CreateServerVehicle (model).
  UNCONFIRMED    how the (escrowed) UI uses Config.Valet.VehicleTypes: vehicles that are not
                 cars are sent as type 'boat' / 'aircraft' so the valet button should stay
                 hidden for them (nayzeee refuses them anyway unless Config.Phone.valetTypes
                 allows them). impoundReason.retrievable is sent in JS milliseconds like
                 lb-phone's own ConvertJSTimestamp.
  OPTIONAL       the two small patches in install/phone/README.md (lb-phone section) make the
                 hand-over instant; without them nayzeee finds the valet car by its plate
                 within ~2 s and puts an undelivered car back after Config.Phone.claimTimeout.
]]

if Config.Framework ~= 'qb' then
    return
end

local RESOURCE = 'nayzeee-garages'
local PHONE_TYPE = { car = 'car', sea = 'boat', air = 'aircraft' }
local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[lb-phone / nayzeee-garages] %s^7'):format(message))
end

--- Call a nayzeee-garages export; never throws. Returns its results or nil, error.
local function nayzeee(name, ...)
    if GetResourceState(RESOURCE) ~= 'started' then
        warnOnce('stopped', RESOURCE .. ' is not started: the Garage app shows no vehicles')
        return nil, 'nayzeee-garages is not started'
    end
    local args = table.pack(...)
    local ok, a, b = pcall(function()
        return exports[RESOURCE][name](exports[RESOURCE], table.unpack(args, 1, args.n))
    end)
    if not ok then
        warnOnce('call:' .. name, ('%s failed: %s'):format(name, tostring(a)))
        return nil, 'nayzeee-garages error'
    end
    return a, b
end

local function whole(value, default)
    local n = tonumber(value)
    if not n or n ~= n then return default end
    return math.floor(n + 0.5)
end

--- One lb-phone VehicleData from a nayzeee phone vehicle.
local function toVehicleData(vehicle)
    local state = vehicle.state
    local impound = type(vehicle.impound) == 'table' and vehicle.impound or nil
    local location = 'out'
    if state == 'garaged' and not vehicle.valetPending then
        location = vehicle.garageName or 'Garage'
    elseif state == 'impounded' then
        location = (impound and impound.location) or vehicle.garageName or 'Impound'
    end

    local impoundReason = nil
    if state == 'impounded' and impound then
        local releaseAt = tonumber(impound.releaseAt)
        impoundReason = {
            reason = impound.reason,
            price = tonumber(impound.fee),
            impounder = impound.by,
            retrievable = releaseAt and releaseAt * 1000 or nil, -- JS milliseconds
        }
    end

    return {
        plate = vehicle.plate,
        model = tonumber(vehicle.hash) or vehicle.model, -- the lb-phone client turns it into a label
        type = PHONE_TYPE[vehicle.vehicleType] or 'car',
        location = location,
        impounded = state == 'impounded',
        statistics = {
            engine = whole(vehicle.engine, 100),
            body = whole(vehicle.body, 100),
            fuel = whole(vehicle.fuel, 100),
        },
        impoundReason = impoundReason,
    }
end

---@param source number
---@return table[] vehicles VehicleData[] (see lb-phone/server/apps/framework/garage.lua)
function _G.GetPlayerVehicles(source)
    local list = nayzeee('GetPhoneVehicles', source)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for i = 1, #list do
        local vehicle = list[i]
        if type(vehicle) == 'table' and type(vehicle.plate) == 'string' then
            local ok, data = pcall(toVehicleData, vehicle)
            if ok then out[#out + 1] = data end
        end
    end
    return out
end

---@param source number
---@param plate string
---@return table|nil vehicleData spawn data for CreateServerVehicle / CreateFrameworkVehicle
function _G.GetVehicle(source, plate)
    local data, err = nayzeee('ClaimVehicleForValet', source, plate)
    if type(data) ~= 'table' then
        -- tell the player why (nayzeee-garages toast); lb-phone itself just stops
        if type(err) == 'string' and err ~= '' then
            TriggerClientEvent('nz:client:notify', source, { type = 'error', message = err })
        end
        return nil
    end

    local props = type(data.props) == 'table' and data.props or {}
    props.fuel = tonumber(data.fuel)   -- ESX ApplyVehicleMods reads vehicle.fuel
    local ok, encoded = pcall(json.encode, props)

    return {
        plate = data.plateText or data.plate,  -- QB / Qbox SetVehicleNumberPlateText
        model = data.hash,                     -- CreateServerVehicle(model) (Config.ServerSideSpawn)
        hash = data.hash,                      -- QB / Qbox CreateFrameworkVehicle
        mods = props,                          -- QB / Qbox ApplyVehicleMods
        fuel = tonumber(data.fuel),            -- QB / Qbox LegacyFuel
        vehicle = ok and encoded or '{}',      -- ESX CreateFrameworkVehicle / ApplyVehicleMods (JSON)
    }
end
