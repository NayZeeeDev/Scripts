--[[
  nayzeee-garages adapter for the NPWD garage app "npwd_qbx_garages" (Qbox).

  WHERE IT GOES  npwd_qbx_garages/server/server.lua  (replace the file; keep a backup)
  WHAT IT DOES   Answers the app's 'npwd_qbx_garages:server:getPlayerVehicles' callback from
                 nayzeee-garages instead of reading player_vehicles and qbx_garages. The app no
                 longer needs qbx_garages to be started (the original asserts it is).
                 Shared vehicles are listed too; the garage text is nayzeee's garage / house /
                 private garage name (or the impound name); engine / body are sent on the
                 0-1000 scale the UI divides by 10.
  ALSO           client/client.lua from this folder (optional): the "mark" button finds
                 vehicles far away (coordinates from the server) instead of only nearby ones.
  CONFIRMED      against npwd_qbx_garages 1.1.0 (github.com/Qbox-project/npwd_qbx_garages):
                 callback name, GarageItem fields (src/types/garage.ts), engine / body / 10.
  KEEP           the resource folder name: the prebuilt UI calls https://npwd_qbx_garages/...
  NOTE           NPWD has no valet in this app; nothing here takes a vehicle out.
]]

local RESOURCE = 'nayzeee-garages'
local STATES = { garaged = true, out = true, impounded = true }
local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[npwd_qbx_garages / nayzeee-garages] %s^7'):format(message))
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

lib.callback.register('npwd_qbx_garages:server:getPlayerVehicles', function(source)
    local list = nayzeee('GetPhoneVehicles', source)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for i = 1, #list do
        local v = list[i]
        if type(v) == 'table' and type(v.plate) == 'string' then
            local ok, item = pcall(toGarageItem, v)
            if ok then out[#out + 1] = item end
        end
    end
    return out
end)
