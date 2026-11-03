--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_esx_garage" (ESX).

  WHERE IT GOES  npwd_esx_garage/server/server.lua  (replace the file; keep a backup)
  WHAT IT DOES   Answers the app's 'npwd:esx-garage:getVehicles' event from nayzeee-garages
                 instead of reading owned_vehicles directly, and always answers (an empty
                 list for a player without vehicles). Shared vehicles are listed too.
                 Field mapping (GarageItem in the app's src/types/garage.ts):
                   stored   true when the vehicle is in a garage OR impounded (the app only
                            shows the place, and enables the map button, for stored = true)
                   parking  nayzeee's garage / house / private garage name, or the impound
                            name followed by "(impounded)"
                   pound    the impound name when impounded, else nil
                   type     'car' | 'boat' | 'aircraft' (nayzeee car / sea / air)
                 Every item also carries `coords` and `key` (extras the app ignores) that the
                 client/client.lua of this folder uses for the map button. The UI's map button
                 only sends the parking text, so two different places with the same name (two
                 house garages called "House garage") get a suffix, e.g. "House garage (Hgrove_1)".
  ALSO           client/client.lua from this folder (REQUIRED with this file: the original
                 client asks esx_garage / esx_boat for garage positions, which do not know
                 nayzeee's garages).
  MANIFEST       keep the original fxmanifest.lua. This file no longer uses oxmysql or ESX;
                 leaving '@oxmysql/lib/MySQL.lua' / '@es_extended/imports.lua' in it is harmless.
  CONFIRMED      against npwd_esx_garage (github.com/itschip/npwd_esx_garage, main): event
                 names, GarageItem fields, how the UI groups by `type` and uses `stored` /
                 `parking`.
  KEEP           the resource folder name: the prebuilt UI calls https://npwd_esx_garage/...
  NOTE           this app has no valet; nothing here takes a vehicle out.
]]

local RESOURCE = 'nayzeee-garages'
local PHONE_TYPE = { car = 'car', sea = 'boat', air = 'aircraft' }
local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[npwd_esx_garage / nayzeee-garages] %s^7'):format(message))
end

--- Call a nayzeee-garages export; never throws.
local function nayzeee(name, ...)
    if GetResourceState(RESOURCE) ~= 'started' then
        warnOnce('stopped', RESOURCE .. ' is not started: the garage app shows no vehicles')
        return nil
    end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[RESOURCE][name](exports[RESOURCE], table.unpack(args, 1, args.n))
    end)
    if not ok then
        warnOnce('call:' .. name, ('%s failed: %s'):format(name, tostring(result)))
        return nil
    end
    return result
end

local function text(value)
    if type(value) ~= 'string' or value == '' then return nil end
    return value
end

local function sameCoords(a, b)
    if a == nil or b == nil then return a == b end
    local ax, ay, az = tonumber(a.x), tonumber(a.y), tonumber(a.z) or 0
    local bx, by, bz = tonumber(b.x), tonumber(b.y), tonumber(b.z) or 0
    if not (ax and ay and bx and by) then return false end
    return math.abs(ax - bx) < 1.0 and math.abs(ay - by) < 1.0 and math.abs(az - bz) < 1.0
end

--- The parking text the map button sends back must name one place: a name already used
--- for another position gets a suffix (garage key / impound id, then the plate).
---@param seen table [parking] = coords | false (this answer only)
local function uniqueParking(parking, coords, tag, plate, seen)
    if not parking then return nil end
    for _, candidate in ipairs({ parking, ('%s (%s)'):format(parking, tostring(tag or plate)),
        ('%s (%s)'):format(parking, tostring(plate)) }) do
        local known = seen[candidate]
        if known == nil then
            seen[candidate] = coords or false
            return candidate
        end
        if sameCoords(known or nil, coords) then return candidate end
    end
    return ('%s (%s)'):format(parking, tostring(plate))
end

--- One GarageItem from a nayzeee phone vehicle.
local function toGarageItem(v, seen)
    local impound = type(v.impound) == 'table' and v.impound or nil
    local state = v.valetPending and 'out' or v.state
    local coords = type(v.coords) == 'table' and v.coords or nil
    local parking, pound, tag = nil, nil, nil
    if state == 'impounded' then
        pound = (impound and text(impound.location)) or 'Impound'
        parking = pound .. ' (impounded)'
        tag = impound and impound.locationId and ('#' .. tostring(impound.locationId)) or nil
    elseif state == 'garaged' then
        parking = text(v.garageName) or 'Garage'
        tag = text(v.garageKey)
    end
    parking = uniqueParking(parking, coords, tag, v.plate, seen)
    return {
        owner = '',
        plate = v.plate,
        vehicle = text(v.nickname) or text(v.label) or text(v.model) or v.plate,
        type = PHONE_TYPE[v.vehicleType] or 'car',
        job = '',
        stored = state ~= 'out',
        parking = parking,
        pound = pound,
        coords = coords,   -- extra: map button (client.lua of this folder)
        key = parking,     -- extra: the client maps parking -> coords
        shared = v.shared == true,
    }
end

RegisterNetEvent('npwd:esx-garage:getVehicles', function()
    local src = source
    local out = {}
    local list = nayzeee('GetPhoneVehicles', src)
    local seen = {}
    if type(list) == 'table' then
        for i = 1, #list do
            local v = list[i]
            if type(v) == 'table' and type(v.plate) == 'string' then
                local ok, item = pcall(toGarageItem, v, seen)
                if ok then out[#out + 1] = item end
            end
        end
    end
    TriggerClientEvent('npwd:esx-garage:sendVehicles', src, out)
end)
