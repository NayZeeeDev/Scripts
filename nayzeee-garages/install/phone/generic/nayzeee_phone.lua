--[[
  nayzeee-garages: generic server helper for phone garage apps WITHOUT a dedicated adapter
  (qs-smartphone, qs-smartphone-pro, yseries, gksphone, okokPhone, high-phone, others).

  STATUS         UNCONFIRMED for these phones: their garage code is escrowed and their docs
                 could not be checked, so the file / function names you edit in the phone are
                 NOT known here. This helper only gives you ready-made calls; you wire them
                 into the phone's own editable garage file (most phones ship one per garage
                 script, e.g. a "qb-garages" / "esx_garage" / "default" server file that runs
                 SELECT ... FROM player_vehicles / owned_vehicles).
  WHERE IT GOES  copy this file into the phone resource (e.g. <phone>/server/nayzeee_phone.lua)
                 and add it to the phone's fxmanifest.lua server scripts BEFORE the file that
                 uses it:   server_script 'server/nayzeee_phone.lua'
  WHAT IT GIVES  a global table NayzeeePhone (server side):

    NayzeeePhone.list(source)          -> neutral list (nayzeee export GetPhoneVehicles), {} on error
    NayzeeePhone.qbRows(source)        -> the same vehicles shaped like `player_vehicles` rows:
        { citizenid, plate, vehicle (spawn name), hash, mods (JSON), garage (name),
          state (0 out | 1 garaged | 2 impounded), fuel 0-100, engine 0-1000, body 0-1000,
          depotprice (impound fee), nickname, label, shared }
    NayzeeePhone.esxRows(source)       -> shaped like `owned_vehicles` rows:
        { owner, plate, vehicle (JSON props), type ('car'|'boat'|'aircraft'), job,
          stored (1 garaged | 0 out or impounded), parking (name), pound (impound name|nil),
          label, shared }
    NayzeeePhone.claim(source, plate)  -> valet data | nil, error
        Marks the vehicle out with nayzeee's garage rules. The result carries what the
        common spawn helpers read: plate, model / hash (number), mods (props table), props,
        vehicle (JSON props, ESX style), fuel, engine / body 0-100, damage (nayzeee format).
        Call it INSTEAD of the phone's "UPDATE ... SET state = 0 / stored = 0" valet query.
    NayzeeePhone.release(source, plate) -> boolean   the valet could not deliver: put it back
    NayzeeePhone.spawned(source, plate, netId) -> boolean   the phone's SERVER created the
        vehicle and its plate is already set (otherwise report from the client, see below)

  CLIENT SIDE    (in the phone's editable valet client code, after the vehicle exists / failed)
        TriggerServerEvent('nz:phone:spawned', plate, NetworkGetNetworkIdFromEntity(vehicle))
        TriggerServerEvent('nz:phone:failed', plate)
  Both are optional: without them nayzeee finds the delivered vehicle by its plate within
  ~2 s, and puts a vehicle that never appears back after Config.Phone.claimTimeout (60 s).

  NO EDITS AT ALL  pick the phone's stock framework garage option (qb-garages / qbx_garages /
                 esx_garage / "default"): the LIST then reads the framework columns nayzeee
                 keeps in sync. Its VALET ("bring my car") must then be turned off in the phone:
                 a valet that writes state = 0 itself is ignored by nayzeee (the vehicle still
                 counts as parked) and skips its checks.
]]

_G.NayzeeePhone = _G.NayzeeePhone or {}
local NayzeeePhone = _G.NayzeeePhone

local RESOURCE = 'nayzeee-garages'
local PHONE_TYPE = { car = 'car', sea = 'boat', air = 'aircraft' }
local STATE_CODE = { out = 0, garaged = 1, impounded = 2 }
local warned = {}

local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    print(('^3[%s / nayzeee-garages] %s^7'):format(GetCurrentResourceName(), message))
end

--- Call a nayzeee-garages export; never throws. Returns its results or nil, error.
local function nayzeee(name, ...)
    if GetResourceState(RESOURCE) ~= 'started' then
        warnOnce('stopped', RESOURCE .. ' is not started')
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

local function text(value)
    if type(value) ~= 'string' or value == '' then return nil end
    return value
end

local function encode(value)
    local ok, out = pcall(json.encode, value)
    return ok and out or '{}'
end

local function number(value, default)
    local n = tonumber(value)
    if not n or n ~= n then return default end
    return n
end

--- The player's vehicles (and vehicles shared with them), nayzeee's neutral list.
function NayzeeePhone.list(source)
    local list = nayzeee('GetPhoneVehicles', source)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for i = 1, #list do
        if type(list[i]) == 'table' and type(list[i].plate) == 'string' then out[#out + 1] = list[i] end
    end
    return out
end

local function stateOf(v)
    if v.valetPending then return 'out' end
    return STATE_CODE[v.state] and v.state or 'out'
end

local function placeOf(v, state)
    local impound = type(v.impound) == 'table' and v.impound or nil
    if state == 'impounded' then return (impound and text(impound.location)) or 'Impound', impound end
    if state == 'garaged' then return text(v.garageName) or 'Garage', impound end
    return nil, impound
end

--- player_vehicles-shaped rows (QBCore / Qbox phones).
function NayzeeePhone.qbRows(source)
    local rows = {}
    for _, v in ipairs(NayzeeePhone.list(source)) do
        local state = stateOf(v)
        local place, impound = placeOf(v, state)
        rows[#rows + 1] = {
            citizenid = '',
            plate = v.plate,
            vehicle = text(v.model) or tostring(v.hash or ''),
            hash = tostring(v.hash or ''),
            mods = '{}',                       -- not in the list; claim() returns the props
            garage = place or 'out',
            state = STATE_CODE[state],
            fuel = math.floor(number(v.fuel, 100) + 0.5),
            engine = math.floor(number(v.engine, 100) * 10 + 0.5),
            body = math.floor(number(v.body, 100) * 10 + 0.5),
            depotprice = state == 'impounded' and impound and math.floor(number(impound.fee, 0)) or 0,
            nickname = text(v.nickname),
            label = text(v.nickname) or text(v.label),
            shared = v.shared == true,
        }
    end
    return rows
end

--- owned_vehicles-shaped rows (ESX phones).
function NayzeeePhone.esxRows(source)
    local rows = {}
    for _, v in ipairs(NayzeeePhone.list(source)) do
        local state = stateOf(v)
        local place = placeOf(v, state)
        rows[#rows + 1] = {
            owner = '',
            plate = v.plate,
            vehicle = encode({ model = v.hash, plate = v.plateText or v.plate, fuelLevel = v.fuel }),
            type = PHONE_TYPE[v.vehicleType] or 'car',
            job = '',
            stored = state == 'garaged' and 1 or 0,
            parking = place,
            pound = state == 'impounded' and place or nil,
            label = text(v.nickname) or text(v.label),
            shared = v.shared == true,
        }
    end
    return rows
end

--- Valet: mark the vehicle out under nayzeee's rules and return its spawn data.
function NayzeeePhone.claim(source, plate)
    local data, err = nayzeee('ClaimVehicleForValet', source, plate)
    if type(data) ~= 'table' then
        if type(err) == 'string' and err ~= '' then
            TriggerClientEvent('nz:client:notify', source, { type = 'error', message = err })
        end
        return nil, err
    end
    local props = type(data.props) == 'table' and data.props or {}
    props.fuel = tonumber(data.fuel)
    return {
        plate = data.plateText or data.plate,
        model = data.hash,
        hash = data.hash,
        modelName = data.model,
        mods = props,
        props = props,
        vehicle = encode(props),
        fuel = tonumber(data.fuel),
        engine = tonumber(data.engine),
        body = tonumber(data.body),
        damage = data.damage,
        label = text(data.nickname) or text(data.label),
    }
end

function NayzeeePhone.release(source, plate)
    return nayzeee('ReleaseValetClaim', source, plate) == true
end

function NayzeeePhone.spawned(source, plate, netId)
    return nayzeee('MarkValetSpawned', source, plate, netId) == true
end
