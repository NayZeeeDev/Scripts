--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_qb_garage" (QBCore).

  WHERE IT GOES  npwd_qb_garage/server/server.lua  (replace the file; keep a backup)
  WHAT IT DOES   Answers the app's 'npwd:qb-garage:getVehicles' event from nayzeee-garages
                 instead of player_vehicles + qb-garages' Garages table, and ALWAYS answers
                 (the original sends nothing to a player without vehicles, so the app keeps
                 loading). Shared vehicles are listed too; the garage text is nayzeee's garage /
                 house / private garage name (or the impound name); engine / body are sent on
                 the 0-1000 scale the UI divides by 10.
  ALSO           fxmanifest.lua from this folder (drops '@qb-garages/config.lua', which is no
                 longer needed) and client/client.lua (fixes a handler leak, waypoint for
                 vehicles far away).
  CONFIRMED      against npwd_qb_garage (github.com/npwd-community/npwd_qb_garage, main):
                 event names, GarageItem fields (src/types/garage.ts), engine / body / 10.
  KEEP           the resource folder name: the prebuilt UI calls https://npwd_qb_garage/...
  NOTE           NPWD has no valet in this app; nothing here takes a vehicle out.
]]

local RESOURCE = 'nayzeee-garages'
local STATES = { garaged = true, out = true, impounded = true }
local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[npwd_qb_garage / nayzeee-garages] %s^7'):format(message))
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

local function scaled(value)
    local n = tonumber(value)
    if not n or n ~= n then n = 100 end
    return math.floor(math.max(0, math.min(100, n)) * 10 + 0.5)
end

--- One GarageItem (src/types/garage.ts) from a nayzeee phone vehicle.
local function toGarageItem(v)
    local state = v.valetPending and 'out' or v.state
    if not STATES[state] then state = 'unknown' end
    local garage
    if state == 'impounded' then
        garage = (type(v.impound) == 'table' and v.impound.location) or 'Impound'
    elseif state == 'out' then
        garage = v.garageName or 'Out'
    else
        garage = v.garageName or 'Garage'
    end
    local nickname = type(v.nickname) == 'string' and v.nickname ~= '' and v.nickname or nil
    return {
        plate = v.plate,
        hash = tostring(v.hash or ''),
        model = v.model or v.hash,          -- client: GetVehicleClassFromName(model) -> type
        vehicle = nickname or v.label or v.model or 'Unknown',
        brand = nickname and '' or (v.brand or 'Vehicle'),
        state = state,
        garage = garage,
        engine = scaled(v.engine),          -- the UI shows engine / 10
        body = scaled(v.body),
        fuel = math.floor((tonumber(v.fuel) or 100) + 0.5),
        coords = type(v.coords) == 'table' and v.coords or nil, -- extra: waypoint (client.lua)
        shared = v.shared == true,
    }
end

RegisterNetEvent('npwd:qb-garage:getVehicles', function()
    local src = source
    local out = {}
    local list = nayzeee('GetPhoneVehicles', src)
    if type(list) == 'table' then
        for i = 1, #list do
            local v = list[i]
            if type(v) == 'table' and type(v.plate) == 'string' then
                local ok, item = pcall(toGarageItem, v)
                if ok then out[#out + 1] = item end
            end
        end
    end
    TriggerClientEvent('npwd:qb-garage:sendVehicles', src, out)
end)
