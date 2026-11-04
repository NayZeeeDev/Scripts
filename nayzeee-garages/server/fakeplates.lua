--[[
  nayzeee-garages — fake plates (server): NZ.FakePlates. docs/CARLOCK.md §13.

  Install: the fake_plate item (Config.CarLock.items.fakePlate) + the screwdriver
  (Config.FakePlates.requireScrewdriver, not consumed, Config.FakePlates.screwdriverBreakChance)
  at the rear of a vehicle. Remove: the screwdriver; the fake_plate item comes back.

  Two steps, the server keeps the time:
    'nz:fakeplates:start'  { netId, action = 'install'|'remove' } -> { token, duration }
        every rule is checked on the server (vehicle in the same routing bucket, the player
        on foot behind it within reach of the SERVER ped position, nobody inside, not being
        towed, a plate to change, the items) and the job is remembered (one per player and
        one per vehicle);
    'nz:fakeplates:finish' { token, cancel? } -> { plate }
        one attempt per started job, only after the job's duration has passed on the server
        clock; everything is checked again before anything changes.
  Installing: a new plate from Config.FakePlates.pattern that is not in the vehicle table nor
  on any vehicle, NZ.CarLock.setRealPlate(entity, realPlate) BEFORE the plate text changes
  (SetVehicleNumberPlateText, server RPC), 'nzPlate' = the real plate (clients' key checks),
  'nzFakePlate' = the fake plate (replicated: target options), optional police alert.
  Removing restores the real plate text.

  Keys, locks and garages keep using the real plate (NZ.CarLock.realPlate,
  NZ.FakePlates.plateOf); everyone else, police plate checks included, sees the fake one.
  External key resources that key on the plate text (qb-vehiclekeys, wasabi_carlock...): the
  installer, when they have access to the real registration, and the owner (online) get keys
  for the fake text, so the car stays theirs; nobody else does. qbx_vehiclekeys keys follow
  the entity, not the text.
  Storing in a garage takes the fake plate off (server/vehicles.lua -> NZ.FakePlates.onStore;
  the item goes back with Config.FakePlates.returnOnStore). A fake plate survives a restart of
  this resource (KVP snapshot, same server session only) and ends with its vehicle.
]]

local FakePlates = NZ.FakePlates
local Utils = NZ.Utils

local RESOURCE = GetCurrentResourceName()
local SNAPSHOT_KVP = 'nz:fakeplates:session'
local REACH = 7.5                 -- m from the vehicle centre (the rear of long vehicles)
local EARLY_MS = 750              -- the client may finish this much before the server clock
local LATE_MS = 30000             -- a job not finished this long after its duration is dropped
local PLATE_TRIES = 12
local RATE = { use = 1000, start = 1200, finish = 300 }
local BLOCKED_TYPES = { boat = true, heli = true, plane = true, submarine = true, train = true }
local SIDE_REACH = 1.6            -- m sideways from the vehicle's long axis
local ENTITY_KEYED = { qbx_vehiclekeys = true } -- key resources whose keys follow the entity, not the text

local records = {}                -- [entity] = { real, fake, by, at, bagSet }
local jobs = {}                   -- [src] = { token, action, entity, netId, startedAt, duration }
local busy = {}                   -- [entity] = src working on it
local bagWritten = {}             -- [entity] = value this file wrote to 'nzFakePlate'

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function num(value, min, max, default)
  local n = tonumber(value)
  if not n or n ~= n then return default end
  return math.max(min, math.min(max, n))
end

local function cfg()
  local c = type(Config.FakePlates) == 'table' and Config.FakePlates or {}
  local anim = type(c.animation) == 'table' and c.animation or {}
  return {
    enabled = c.enabled ~= false,
    requireScrewdriver = c.requireScrewdriver ~= false,
    breakChance = num(c.screwdriverBreakChance, 0, 100, 5),
    installMs = math.floor(num(c.installSeconds, 1, 60, 6) * 1000),
    removeMs = math.floor(num(c.removeSeconds, 1, 60, 5) * 1000),
    returnOnStore = c.returnOnStore ~= false,
    pattern = type(c.pattern) == 'string' and c.pattern ~= '' and c.pattern or '11AAA111',
    alertChance = num(c.alertChance, 0, 100, 0),
    distance = num(c.distance, 1.0, 5.0, 2.0),
    animation = anim,
  }
end

local function itemName(key)
  if NZ.CarLock and type(NZ.CarLock.itemName) == 'function' then
    local okName, name = pcall(NZ.CarLock.itemName, key)
    if okName and type(name) == 'string' and name ~= '' then return name end
  end
  return key == 'screwdriver' and 'screwdriver' or 'fake_plate'
end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function identifierOf(src)
  local okId, id = pcall(NZ.Bridge.getIdentifier, src)
  if okId and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function textOf(entity)
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function notify(src, kind, message)
  if validSrc(src) then TriggerClientEvent('nz:client:notify', src, { type = kind, message = message }) end
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local okLog, err = pcall(NZ.Logs.add, event, src, data)
  if not okLog then lib.print.warn(('[nayzeee-garages] fakeplates: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function limited(src, bucket)
  return not NZ.Access.rateLimit(src, 'fakeplates:' .. bucket, RATE[bucket] or 1000)
end

local function hasItem(src, item)
  local okHas, has = pcall(NZ.Inventory.hasItem, src, item, 1)
  return okHas and has == true
end

local function incapacitated(src)
  if type(NZ.Vehicles.incapacitated) ~= 'function' then return false end
  local okI, res = pcall(NZ.Vehicles.incapacitated, src)
  return okI and res == true
end

local function towing(entity)
  if type(NZ.Tow) ~= 'table' or type(NZ.Tow.isTowing) ~= 'function' then return false end
  local okT, res = pcall(NZ.Tow.isTowing, entity)
  return okT and res == true
end

local function occupied(entity)
  for seat = -1, 6 do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 then return true end
  end
  return false
end

local function writeBag(entity, value)
  bagWritten[entity] = value == nil and false or value
  Entity(entity).state:set('nzFakePlate', value, true)
end

-- The server's value of 'nzFakePlate' wins: a client that changes it gets it put back.
AddStateBagChangeHandler('nzFakePlate', nil, function(bagName, _, value)
  local okE, entity = pcall(GetEntityFromStateBagName, bagName)
  if not okE or type(entity) ~= 'number' or entity == 0 then return end
  local mine = bagWritten[entity]
  if mine == nil then mine = false end
  if (value == nil and mine == false) or value == mine then return end
  SetTimeout(0, function()
    if not isVehicle(entity) then return end
    local want = records[entity] and records[entity].fake or nil
    Entity(entity).state:set('nzFakePlate', want, true)
  end)
end)

---------------------------------------------------------------------------------------
-- Real plates
---------------------------------------------------------------------------------------

--- The real plate under a fake plate, or nil when the vehicle wears its own plate.
---@param entity number
---@return string|nil
function FakePlates.realPlateOf(entity)
  local rec = records[entity]
  if rec and isVehicle(entity) then return rec.real end
  return nil
end

--- Does this vehicle wear a fake plate?
---@param entity number
---@return boolean
function FakePlates.isFake(entity)
  return FakePlates.realPlateOf(entity) ~= nil
end

--- The identity of a vehicle: the plate under a fake plate, else NZ.CarLock.realPlate (the
--- plate the server recorded for it, nil for a copy of a tracked vehicle), else the text.
---@param entity number
---@return string|nil
function FakePlates.plateOf(entity)
  if not isVehicle(entity) then return nil end
  local real = FakePlates.realPlateOf(entity)
  if real then return real end
  local carLock = NZ.CarLock
  if type(carLock) == 'table' and type(carLock.realPlate) == 'function' then
    local okR, plate = pcall(carLock.realPlate, entity)
    if okR then return plate end
  end
  return textOf(entity)
end

--- The vehicle wearing the fake plate `text` and its record (internal; not exported: other
--- resources only see the fake plate).
---@param text string
---@return number|nil entity, table|nil record { real, fake, at }
function FakePlates.lookup(text)
  local plate = Utils.plate(text)
  if not plate then return nil end
  for entity, rec in pairs(records) do
    if rec.fake == plate and isVehicle(entity) then
      return entity, { real = rec.real, fake = rec.fake, at = rec.at }
    end
  end
  return nil
end

---------------------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------------------

--- Config pattern ('1' digit, 'A' letter, others as written) -> Utils.generatePlate template.
local function template(pattern)
  local out = {}
  for i = 1, math.min(#pattern, 8) do
    local c = pattern:sub(i, i)
    if c == '1' then out[#out + 1] = '#'
    elseif c == 'A' or c == 'a' then out[#out + 1] = '@'
    elseif c == ' ' then out[#out + 1] = ' ' -- ESX style 'AAA 111' (Utils.plate trims the ends only)
    elseif c:match('[%w#@%*]') then out[#out + 1] = c:upper()
    end
  end
  if #out == 0 then return '##@@@###' end
  return table.concat(out)
end

local function plateInWorld(plate)
  for entity, rec in pairs(records) do
    if rec.fake == plate and isVehicle(entity) then return true end
  end
  if type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] then return true end
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and textOf(entity) == plate then return true end
  end
  return false
end

--- A plate from the pattern that no registered vehicle and no vehicle in the world carries.
local function newPlate()
  local tpl = template(cfg().pattern)
  for _ = 1, PLATE_TRIES do
    local candidate = Utils.plate(Utils.generatePlate(tpl))
    if candidate and #candidate >= 2 and not plateInWorld(candidate) then
      local okDb, exists = pcall(NZ.DB.plateExists, candidate, false)
      if okDb and exists == false then return candidate end
    end
  end
  return nil
end

---------------------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------------------

--- Is the player on foot behind the vehicle and close enough (server positions)? Within
--- REACH of the centre (the rear of long vehicles), at most SIDE_REACH off the long axis and
--- clearly behind it (not at a rear corner or beside the boot).
local function behind(src, entity)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return false end
  if GetPlayerRoutingBucket(tostring(src)) ~= GetEntityRoutingBucket(entity) then return false end
  local pos, center = GetEntityCoords(ped), GetEntityCoords(entity)
  local dx, dy, dz = pos.x - center.x, pos.y - center.y, pos.z - center.z
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist > REACH or math.abs(dz) > 3.0 then return false end
  if dist < 0.5 then return true end
  local heading = math.rad(tonumber(GetEntityHeading(entity)) or 0.0)
  local fx, fy = -math.sin(heading), math.cos(heading)   -- forward
  local rx, ry = math.cos(heading), math.sin(heading)    -- right
  if math.abs(dx * rx + dy * ry) > SIDE_REACH then return false end
  return (dx * fx + dy * fy) / math.max(math.sqrt(dx * dx + dy * dy), 0.001) <= -0.5
end

--- Common rules of both steps. Returns nil or a translated error.
local function vehicleProblem(src, entity, action)
  if not isVehicle(entity) then return L('Vehicle not found') end
  if not behind(src, entity) then return L('Stand at the rear of the vehicle') end
  if occupied(entity) then return L('Someone is inside this vehicle') end
  if towing(entity) then return L('This vehicle is being towed') end
  local okType, vtype = pcall(GetVehicleType, entity)
  if okType and BLOCKED_TYPES[vtype] then return L('This vehicle has no plate to change') end
  local c = cfg()
  if c.requireScrewdriver and not hasItem(src, itemName('screwdriver')) then
    return L('You need a screwdriver')
  end
  if action == 'install' then
    if records[entity] then return L('This vehicle already has a fake plate') end
    if not hasItem(src, itemName('fakePlate')) then return L('You need a fake plate') end
    if not FakePlates.plateOf(entity) then return L('This vehicle has no plate to change') end
  else
    if not records[entity] then return L('This vehicle has no fake plate') end
    local okCarry, carry = pcall(NZ.Inventory.canCarry, src, itemName('fakePlate'), 1)
    if okCarry and carry == false then return L('You cannot carry the fake plate') end
  end
  return nil
end

local function vehicleOf(netId)
  local id = tonumber(netId)
  if not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return nil end
  local entity = NetworkGetEntityFromNetworkId(math.tointeger(id))
  return isVehicle(entity) and entity or nil
end

local function dropJob(src)
  local job = jobs[src]
  if not job then return end
  jobs[src] = nil
  if busy[job.entity] == src then busy[job.entity] = nil end
end

---------------------------------------------------------------------------------------
-- Install / remove
---------------------------------------------------------------------------------------

local function breakScrewdriver(src)
  local c = cfg()
  if not c.requireScrewdriver or c.breakChance <= 0 then return end
  if math.random() * 100 >= c.breakChance then return end
  local okRem, removed = pcall(NZ.Inventory.removeItem, src, itemName('screwdriver'), 1)
  if okRem and removed then notify(src, 'error', L('Your screwdriver broke')) end
end

local function alertPolice(src, entity, plate)
  local chance = cfg().alertChance
  if chance <= 0 or math.random() * 100 >= chance then return end
  if type(NZ.Dispatch) ~= 'table' or type(NZ.Dispatch.alert) ~= 'function' then return end
  local okA, err = pcall(NZ.Dispatch.alert, src, {
    kind = 'fakeplate', plate = plate, modelHash = GetEntityModel(entity), coords = GetEntityCoords(entity),
  })
  if not okA then lib.print.warn(('[nayzeee-garages] fakeplates: dispatch failed: %s'):format(tostring(err))) end
end

--- The key resource in use when it keys on the plate text (the built-in car lock and
--- entity-keyed resources follow the real plate / the entity), else nil.
local function textKeyedResource()
  if NZ.CarLock and type(NZ.CarLock.enabled) == 'function' then
    local okOn, on = pcall(NZ.CarLock.enabled)
    if okOn and on == true then return nil end
  end
  if type(NZ.KeysServer) ~= 'table' or type(NZ.KeysServer.resource) ~= 'function' then return nil end
  local okR, name = pcall(NZ.KeysServer.resource)
  if not okR or type(name) ~= 'string' or name == '' or name == 'nayzeee' or ENTITY_KEYED[name] then return nil end
  if NZ.Settings and type(NZ.Settings.get) == 'function' then
    local okS, give = pcall(NZ.Settings.get, 'vehicles.giveKeys', true)
    if okS and give == false then return nil end
  end
  return name
end

--- After a fake plate went on (external text-keyed key resource only): may the installer get
--- keys for the fake text (access to the real registration: owner, share, fleet)? The owner,
--- online and not the installer, gets them through 'nz:client:fakeplates:keys'.
---@return boolean installerKeys
local function keysForFake(src, entity, real, fake)
  if not textKeyedResource() then return false end
  local okRow, row = pcall(NZ.DB.getVehicle, real)
  if not okRow or type(row) ~= 'table' then return false end
  local id = identifierOf(src)
  local access = nil
  if id and type(NZ.Vehicles.accessOf) == 'function' then
    local okA, res = pcall(NZ.Vehicles.accessOf, src, row, nil, { identifier = id })
    if okA then access = res end
  end
  if row.owner and row.owner ~= id and type(NZ.Bridge.getSourceByIdentifier) == 'function' then
    local okO, owner = pcall(NZ.Bridge.getSourceByIdentifier, row.owner)
    owner = okO and validSrc(owner) or nil
    if owner and owner ~= src then
      TriggerClientEvent('nz:client:fakeplates:keys', owner, { netId = NetworkGetNetworkIdFromEntity(entity), plate = fake })
    end
  end
  return access ~= nil
end

local function install(src, entity)
  local real = FakePlates.plateOf(entity)
  if not real then return nil, L('This vehicle has no plate to change') end
  local fake = newPlate()
  if not fake then return nil, L('Something went wrong') end
  if not NZ.Inventory.removeItem(src, itemName('fakePlate'), 1) then return nil, L('You need a fake plate') end

  -- the real plate is recorded BEFORE the text changes: keys / locks never see the fake one
  if NZ.CarLock and type(NZ.CarLock.setRealPlate) == 'function' then pcall(NZ.CarLock.setRealPlate, entity, real) end
  local state = Entity(entity).state
  local bagSet = Utils.plate(state.nzPlate) ~= real
  if bagSet then state:set('nzPlate', real, true) end
  records[entity] = { real = real, fake = fake, by = identifierOf(src), at = os.time(), bagSet = bagSet }
  SetVehicleNumberPlateText(entity, fake)
  writeBag(entity, fake)

  local keys = keysForFake(src, entity, real, fake)
  breakScrewdriver(src)
  alertPolice(src, entity, fake)
  log('vehicle.fakeplate', src, { action = 'install', plate = real, fake = fake, keys = keys or nil })
  return fake, nil, keys
end

--- Take the fake plate off (the real text comes back). Returns the record or nil.
local function takeOff(entity)
  local rec = records[entity]
  if not rec then return nil end
  records[entity] = nil
  if isVehicle(entity) then
    SetVehicleNumberPlateText(entity, rec.real)
    writeBag(entity, nil)
    if rec.bagSet then
      local state = Entity(entity).state
      if Utils.plate(state.nzPlate) == rec.real then state:set('nzPlate', nil, true) end
    end
  end
  return rec
end

local function remove(src, entity)
  local rec = takeOff(entity)
  if not rec then return nil, L('This vehicle has no fake plate') end
  local okAdd, added = pcall(NZ.Inventory.addItem, src, itemName('fakePlate'), 1)
  if not okAdd or not added then notify(src, 'warning', L('You cannot carry the fake plate')) end
  breakScrewdriver(src)
  log('vehicle.fakeplate', src, { action = 'remove', plate = rec.real, fake = rec.fake, by = rec.by })
  return rec.real, nil
end

--- A vehicle is stored in a garage (server/vehicles.lua, after the database update, before
--- the entity is deleted): its fake plate comes off; the item goes to `src` when
--- Config.FakePlates.returnOnStore. Returns true when it wore one.
---@param src number
---@param entity number
---@return boolean
function FakePlates.onStore(src, entity)
  local rec = takeOff(entity)
  if not rec then return false end
  if busy[entity] then
    local worker = busy[entity]
    dropJob(worker)
  end
  local returned = false
  if cfg().returnOnStore and validSrc(src) then
    local okAdd, added = pcall(NZ.Inventory.addItem, src, itemName('fakePlate'), 1)
    returned = okAdd and added == true
    if returned then
      notify(src, 'info', L('The fake plate came off and went back into your inventory'))
    else
      notify(src, 'warning', L('You cannot carry the fake plate'))
    end
  end
  log('vehicle.fakeplate', src, { action = 'store', plate = rec.real, fake = rec.fake, returned = returned })
  return true
end

---------------------------------------------------------------------------------------
-- Item use and callbacks
---------------------------------------------------------------------------------------

--- Usable fake_plate item (bridge/server/listeners.lua): the client picks the vehicle behind
--- the player and starts the install (nothing is consumed here).
---@param src number
---@return boolean handled
function FakePlates.useItem(src)
  src = validSrc(src)
  if not src then return false end
  if limited(src, 'use') then return true end
  if not cfg().enabled then
    notify(src, 'error', L('Fake plates are disabled'))
    return true
  end
  TriggerClientEvent('nz:client:fakeplates:use', src)
  return true
end

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(src, payload)
    src = validSrc(src)
    if not src then return Utils.fail(L('Invalid request')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

-- { netId, action } -> { token, duration }
register('nz:fakeplates:start', function(src, payload)
  local c = cfg()
  if not c.enabled then return Utils.fail(L('Fake plates are disabled')) end
  if limited(src, 'start') then return Utils.fail(L('Please wait a moment before trying again')) end
  local action = payload.action
  if action ~= 'install' and action ~= 'remove' then return Utils.fail(L('Invalid request')) end
  if not identifierOf(src) then return Utils.fail(L('Your character is not loaded')) end
  if incapacitated(src) then return Utils.fail(L('You cannot do that right now')) end
  if jobs[src] then dropJob(src) end
  local entity = vehicleOf(payload.netId)
  if not entity then return Utils.fail(L('Vehicle not found')) end
  if busy[entity] and busy[entity] ~= src then return Utils.fail(L('Someone is already working on this vehicle')) end
  local problem = vehicleProblem(src, entity, action)
  if problem then return Utils.fail(problem) end

  local token = ('%08x'):format(math.random(0, 0x7fffffff))
  local duration = action == 'install' and c.installMs or c.removeMs
  jobs[src] = {
    token = token, action = action, entity = entity, netId = NetworkGetNetworkIdFromEntity(entity),
    startedAt = GetGameTimer(), duration = duration,
  }
  busy[entity] = src
  local job = jobs[src]
  SetTimeout(duration + LATE_MS, function()
    if jobs[src] == job then dropJob(src) end
  end)
  return Utils.ok({ token = token, duration = duration })
end)

-- { token, cancel? } -> { plate, keys? } (the plate the vehicle shows now; keys = the client
-- gives itself keys for the fake text through the external key resource)
register('nz:fakeplates:finish', function(src, payload)
  if limited(src, 'finish') then return Utils.fail(L('Please wait a moment before trying again')) end
  local job = jobs[src]
  if not job or type(payload.token) ~= 'string' or payload.token ~= job.token then
    return Utils.fail(L('Nothing to finish'))
  end
  dropJob(src) -- one attempt per started job
  if payload.cancel == true then return Utils.ok(nil) end
  if not cfg().enabled then return Utils.fail(L('Fake plates are disabled')) end

  local elapsed = GetGameTimer() - job.startedAt
  if elapsed + EARLY_MS < job.duration then
    log('security.fakeplate', src, { reason = 'finished too early', elapsed = elapsed, duration = job.duration })
    return Utils.fail(L('You stopped too early'))
  end
  if elapsed > job.duration + LATE_MS then return Utils.fail(L('You took too long')) end
  local entity = job.entity
  if not isVehicle(entity) or NetworkGetNetworkIdFromEntity(entity) ~= job.netId then
    return Utils.fail(L('Vehicle not found'))
  end
  if incapacitated(src) then return Utils.fail(L('You cannot do that right now')) end
  local problem = vehicleProblem(src, entity, job.action)
  if problem then return Utils.fail(problem) end

  local plate, err, keys
  if job.action == 'install' then
    plate, err, keys = install(src, entity)
  else
    plate, err = remove(src, entity)
  end
  if not plate then return Utils.fail(err) end
  return Utils.ok({ plate = plate, keys = keys == true })
end)

---------------------------------------------------------------------------------------
-- Lifecycle: vehicles removed, players leaving, resource restart
---------------------------------------------------------------------------------------

AddEventHandler('entityRemoved', function(entity)
  records[entity] = nil
  bagWritten[entity] = nil
  local worker = busy[entity]
  if worker then dropJob(worker) end
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then dropJob(math.tointeger(src) or src) end
end)

local function serverBoot()
  return os.time() - math.floor(GetGameTimer() / 1000)
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= RESOURCE then return end
  local list = {}
  for entity, rec in pairs(records) do
    if isVehicle(entity) then
      list[tostring(NetworkGetNetworkIdFromEntity(entity))] = {
        real = rec.real, fake = rec.fake, by = rec.by, at = rec.at, bagSet = rec.bagSet,
      }
    end
  end
  local okEnc, encoded = pcall(json.encode, { boot = serverBoot(), list = list })
  if okEnc and type(encoded) == 'string' then pcall(SetResourceKvp, SNAPSHOT_KVP, encoded) end
end)

-- Fake plates of vehicles still in the world after a restart of this resource (same server
-- session, the vehicle still shows that fake plate).
local function restore()
  local okRead, raw = pcall(GetResourceKvpString, SNAPSHOT_KVP)
  if not okRead or type(raw) ~= 'string' or raw == '' then return end
  pcall(DeleteResourceKvp, SNAPSHOT_KVP)
  local okDec, data = pcall(json.decode, raw)
  if not okDec or type(data) ~= 'table' or type(data.list) ~= 'table' then return end
  if math.abs((tonumber(data.boot) or 0) - serverBoot()) > 15 then return end
  local count = 0
  for netId, rec in pairs(data.list) do
    local entity = NetworkGetEntityFromNetworkId(math.tointeger(tonumber(netId) or 0) or 0)
    local real, fake = type(rec) == 'table' and Utils.plate(rec.real) or nil, type(rec) == 'table' and Utils.plate(rec.fake) or nil
    if real and fake and isVehicle(entity) and textOf(entity) == fake then
      records[entity] = { real = real, fake = fake, by = type(rec.by) == 'string' and rec.by or nil,
        at = tonumber(rec.at) or os.time(), bagSet = rec.bagSet == true }
      bagWritten[entity] = fake
      if NZ.CarLock and type(NZ.CarLock.setRealPlate) == 'function' then pcall(NZ.CarLock.setRealPlate, entity, real) end
      count = count + 1
    end
  end
  if count > 0 then lib.print.info(('[nayzeee-garages] fakeplates: %d fake plate(s) kept across the restart'):format(count)) end
end

CreateThread(function()
  local okR, err = pcall(restore)
  if not okR then lib.print.warn(('[nayzeee-garages] fakeplates: restore failed: %s'):format(tostring(err))) end
end)
