--[[
  nayzeee-garages — car lock: lockpick, hotwire, search, NPC robbery / assist / dead driver,
  alarms and police alerts (server, NZ.CarLock). docs/CARLOCK.md §8.

  Every crime action is a two-step callback with a server session:
    step 'start'   validates everything on the server (OneSync entities, distances from the
                   SERVER ped, routing bucket, locks, keys, items, jobs, cooldowns) and opens
                   ONE session for the player: { action, vehicle, ped, timing window }.
    step 'finish'  { id, success } closes it. Only the session's own id is accepted, once; the
                   time since 'start' must fit the expected duration (skill checks: the
                   earliest pass ox_lib allows per check, a third of an indicator turn at that
                   speed, + the lockpick's turn to the door; progress bars / NPC hold-ups:
                   their duration), distances and states are checked again. A late finish
                   counts as a failure. Peds / vehicles a session holds are free again once it
                   expires (a stopped NPC is released by the server then).
  Callbacks (lib.callback, { ok, data, error }), payload { step, ... }:
    nz:carlock:lockpick    start { netId, tool?, slot? } -> { id, method = 'skillcheck', difficulty, inputs, tool }
                                                         | { id, method = 'pins', puzzle = { pins, order, heights },
                                                             snapChance, tool }   (lockpicking.style = 'pins')
    nz:carlock:hotwire     start { netId }               -> { id, method, difficulty, inputs, duration }
                                                         | { id, method = 'wires', puzzle = { left, right }, item? }
                                                         | { id, method = 'reader', puzzle = { frequency, phase,
                                                             tolerance }, item }   (Config.CarLock.hotwiring)
                           refused for vehicles with an immobiliser (standard or Ghost)
    nz:carlock:search      start { netId }               -> { id, duration }
    nz:carlock:npcRob      start { netId, pedNetId }     -> { id?, outcome = 'comply'|'drop'|'flee'|'fight', duration }
                           npc.reactions weights (handover = 'comply' after robTime, drop = the key on
                           the ground next to the driver door, fight, flee = drives away);
                           npc.policeRequired on-duty officers; npc.dispatchDelay seconds before the alert
    nz:carlock:npcAssist   start { netId, pedNetId }     -> { id, duration }
    nz:carlock:deadDriver  start { netId, pedNetId }     -> { id, duration }
    every one              finish { id, success, answer?, snapped? } -> { success, broke?, alarm?, found? }
                           answer: the minigame's solution (pins: the order the pins were set;
                           wires: answer[i] = right position of left wire i; reader: { frequency,
                           phase }); a wrong answer is a failure. snapped (pins): an overset pin
                           breaks the pick at lockpicking.snapChance % (+ alarm with alarmOnSnap)
    (start may also carry `street` and `label`: display text for police alerts only.)

  Outcomes: lockpick unlocks the doors; hotwire / robbery / assist / dead driver give a
  temporary key ('hotwire' | 'robbery' | 'assist'); search rolls Config.CarLock.search loot once
  per vehicle. Failed attempts roll the tool's break and alarm chances; every attempt rolls its
  alert chance (NZ.Dispatch.alert with the VISIBLE plate text, model, colour and the vehicle's
  position; one alert per player and vehicle within dispatch.cooldown).

  NPC drivers: the server picks the outcome (comply / flee with the car / fight) and tells the
  client that owns the ped what to do ('nz:client:carlock:npc'); it remembers the original
  driver of the vehicle for the dead-driver search. Only traffic peds (npc.ambientOnly), never
  players, never vehicles owned by a player (npc.ownedVehicles), never a vehicle being towed.

  Item use: NZ.CarLock.useAccessTool (registered by bridge/server/listeners.lua) starts the
  lockpick flow on the locked vehicle the player faces (2.5 m from its centre, buses / trucks
  7 m; nobody alive at the wheel; its profile takes that tool; no key) or a hack hotwire in the
  driver seat, and returns false when there is nothing to do or a crime action is already
  running, so the item's owner script (house / store robberies ...) runs.
  Search: traffic / parked GTA vehicles only (search.ambientOnly), never job vehicles of the
  player's job, one successful search per player every search.cooldown seconds.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local ACCESS_RANGE = 3.5       -- m: vehicle centre to the server ped (doors)
local BIG_ACCESS_RANGE = 7.0   -- m: the same for buses, trucks, industrial / service vehicles (not taxis)
local ITEM_RANGE = 2.5         -- m: a used tool picks a vehicle this close, in front of the player
local BIG_CLASSES = { [10] = true, [17] = true, [20] = true } -- industrial, service, commercial
local BODY_RANGE = 3.5         -- m: a dead driver's body to the server ped
local LAST_DRIVER_RANGE = 15.0 -- m: a vehicle's last driver counts as its driver this close to it
local ASSIST_RANGE = 6.0       -- m: officer to the vehicle
local SLACK = 2.0              -- m: extra allowed at 'finish' (peds and vehicles move a little)
local GRACE_MS = 400           -- network latency allowance on minimum durations
-- ox_lib skill checks: the target area starts at least 120° after the indicator, so the
-- earliest pass is a third of a turn. One turn at speed 1: 2000 ms (ox_lib 3.32.3+ (communityox)
-- / 3.33+ (overextended): requestAnimationFrame), older versions 1° per interval tick (4 ms in
-- CEF) = 1440 ms. 10 % slack.
local CHECK_SHARE = 0.9 / 3
local CHECK_SPEED = { easy = 1.0, medium = 1.5, hard = 1.75 }
local TURN_MS, TURN_MS_OLD = 2000, 1440
local CHECK_MAX_MS = 10000     -- slowest check (a full turn at speed 0.2)
local LEAD_MS = 2500           -- turning to the door / animation before the first check
local DOOR_TURN_MS = 800       -- the client turns to the door before the lockpick checks (fixed)
local LATE_MS = 15000          -- extra time after a progress bar / hold-up
local BODY_MS = 4500
local ASSIST_MS = 4000
local MAX_CHECKS = 8
local MAX_MEMORY = 4000        -- searched plates kept per server session
local POP_AMBIENT = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
local function u32(hash) return math.floor(tonumber(hash) or 0) % 4294967296 end
local UNARMED = u32(joaat('WEAPON_UNARMED'))
-- class 17 (service) models the size of a car: the normal reach and facing rules
local CAR_SIZED = { [u32(joaat('taxi'))] = true, [u32(joaat('vivanite2'))] = true }

--- Does the player hold a weapon (server view; true when the native is not available)?
local function armed(ped)
  local ok, weapon = pcall(GetSelectedPedWeapon, ped)
  if not ok or weapon == nil then return true end
  weapon = u32(weapon)
  return weapon ~= 0 and weapon ~= UNARMED
end

local sessions = {}            -- [src] = session
local cooldowns = {}           -- [src] = { [bucket] = GetGameTimer() when it ends }
local drivers = {}             -- [vehicle] = { ped, at } original NPC driver (an interaction started)
local busyPeds = {}            -- [ped] = src while a robbery / request runs
local searching = {}           -- [vehicle] = src while a search runs
local searched = {}            -- [vehicle] = true
local searchedPlates, searchedCount = {}, 0
local searchedBodies = {}      -- [ped] = true
local alerted = {}             -- ['src|kind|plate'] = GetGameTimer()
local counter = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function cfg() return CarLock.cfg() end
local function section(name)
  local value = cfg()[name]
  return type(value) == 'table' and value or {}
end
local function now() return GetGameTimer() end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function pedOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return ped
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function isPed(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 1
end

local function netIdOf(entity)
  local ok, id = pcall(NetworkGetNetworkIdFromEntity, entity)
  return ok and id or nil
end

local function distance(a, b)
  return #(GetEntityCoords(a) - GetEntityCoords(b))
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('carlock: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function roll(percent)
  percent = tonumber(percent) or 0
  if percent <= 0 then return false end
  if percent >= 100 then return true end
  return math.random() * 100 < percent
end

local function towing(entity)
  if type(NZ.Tow.isTowing) ~= 'function' then return false end
  local ok, res = pcall(NZ.Tow.isTowing, entity)
  return ok and res == true
end

--- Health of a ped from the server's view (nil when unknown).
local function healthOf(ped)
  local ok, health = pcall(GetEntityHealth, ped)
  return ok and tonumber(health) or nil
end

local function alive(ped)
  local health = healthOf(ped)
  return health ~= nil and health > 100
end

local function isNpc(ped)
  if not isPed(ped) then return false end
  local ok, player = pcall(IsPedAPlayer, ped)
  return ok and player ~= true and player ~= 1
end

--- Created by the GTA population (traffic, parked cars, pedestrians), not by a script?
local function ambientEntity(entity)
  local ok, pop = pcall(GetEntityPopulationType, entity)
  return ok and POP_AMBIENT[tonumber(pop) or -1] == true
end

--- Traffic ped (not a script / mission ped) when npc.ambientOnly is on.
local function ambientPed(ped)
  if section('npc').ambientOnly == false then return true end
  return ambientEntity(ped)
end

--- Bus, truck, industrial / service vehicle (doors far from the centre)? Taxis are car-sized.
local function bigVehicle(entity)
  return BIG_CLASSES[CarLock.classOf(entity) or -1] == true and not CAR_SIZED[u32(GetEntityModel(entity))]
end

--- How far from a vehicle's centre its doors can be worked on.
local function accessRange(entity)
  return bigVehicle(entity) and BIG_ACCESS_RANGE or ACCESS_RANGE
end

local function speedOf(entity)
  local ok, velocity = pcall(GetEntityVelocity, entity)
  if not ok or not velocity then return 0.0 end
  return #velocity
end

local function onCooldown(src, bucket)
  local list = cooldowns[src]
  return list ~= nil and list[bucket] ~= nil and list[bucket] > now()
end

local function setCooldown(src, bucket, seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return end
  cooldowns[src] = cooldowns[src] or {}
  cooldowns[src][bucket] = now() + math.floor(seconds * 1000)
end

--- Owned by a player (a row with an owner)?
local function ownedPlate(plate)
  local row = CarLock.vehicleRow(plate)
  return row ~= nil and row.owner ~= nil
end

--- Display text a client sent (street, model label): no control characters and no markup
--- (police MDT / dispatch UIs may render it as HTML), at most `max` bytes, whole UTF-8 chars.
local function text(value, max)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('[%c]', ' '):gsub('[<>&`\\]', ''):gsub("'", '\u{2019}'):gsub('"', '\u{201D}')
  value = value:gsub('^%s+', ''):gsub('%s+$', '')
  if #value > max then
    value = value:sub(1, max)
    for _ = 1, 3 do
      if utf8.len(value) then break end
      value = value:sub(1, -2)
    end
  end
  if value == '' then return nil end
  return value
end

---------------------------------------------------------------------------------------
-- Vehicle description for police alerts
---------------------------------------------------------------------------------------

-- GTA colour index ranges -> plain colour name
local COLOUR_RANGES = {
  { 0, 2, 'Black' }, { 3, 9, 'Silver' }, { 10, 11, 'Grey' }, { 12, 12, 'Black' }, { 13, 14, 'Grey' },
  { 15, 16, 'Black' }, { 17, 18, 'Silver' }, { 19, 19, 'Grey' }, { 20, 20, 'Silver' }, { 21, 21, 'Black' },
  { 22, 22, 'Grey' }, { 23, 26, 'Silver' }, { 27, 35, 'Red' }, { 36, 36, 'Orange' }, { 37, 37, 'Gold' },
  { 38, 38, 'Orange' }, { 39, 40, 'Red' }, { 41, 41, 'Orange' }, { 42, 42, 'Yellow' }, { 43, 48, 'Red' },
  { 49, 60, 'Green' }, { 61, 87, 'Blue' }, { 88, 89, 'Yellow' }, { 90, 90, 'Brown' }, { 91, 91, 'Yellow' },
  { 92, 92, 'Green' }, { 93, 95, 'Beige' }, { 96, 104, 'Brown' }, { 105, 107, 'Beige' }, { 108, 110, 'Brown' },
  { 111, 112, 'White' }, { 113, 113, 'Beige' }, { 114, 115, 'Brown' }, { 116, 116, 'Beige' }, { 117, 117, 'Silver' },
  { 118, 118, 'Black' }, { 119, 119, 'Silver' }, { 120, 120, 'Chrome' }, { 121, 122, 'White' }, { 123, 124, 'Orange' },
  { 125, 125, 'Green' }, { 126, 126, 'Yellow' }, { 127, 127, 'Blue' }, { 128, 128, 'Green' }, { 129, 129, 'Brown' },
  { 130, 130, 'Orange' }, { 131, 132, 'White' }, { 133, 133, 'Green' }, { 134, 134, 'White' }, { 135, 137, 'Pink' },
  { 138, 138, 'Orange' }, { 139, 139, 'Green' }, { 140, 141, 'Blue' }, { 142, 142, 'Purple' }, { 143, 143, 'Red' },
  { 144, 144, 'Green' }, { 145, 145, 'Purple' }, { 146, 146, 'Blue' }, { 147, 147, 'Black' }, { 148, 149, 'Purple' },
  { 150, 150, 'Red' }, { 151, 152, 'Green' }, { 153, 153, 'Brown' }, { 154, 154, 'Beige' }, { 155, 155, 'Green' },
  { 156, 156, 'Silver' }, { 157, 157, 'Blue' }, { 158, 160, 'Gold' },
}

local function colourOfIndex(index)
  index = tonumber(index)
  if not index then return nil end
  for _, r in ipairs(COLOUR_RANGES) do
    if index >= r[1] and index <= r[2] then return r[3] end
  end
  return nil
end

local function colourOfRgb(r, g, b)
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if not r or not g or not b then return nil end
  local max, min = math.max(r, g, b), math.min(r, g, b)
  if max < 45 then return 'Black' end
  if max - min < 30 then return max > 200 and 'White' or 'Grey' end
  local hue
  if max == r then hue = ((g - b) / (max - min)) % 6
  elseif max == g then hue = (b - r) / (max - min) + 2
  else hue = (r - g) / (max - min) + 4 end
  hue = hue * 60
  if hue < 15 or hue >= 345 then return 'Red' end
  if hue < 40 then return max < 140 and 'Brown' or 'Orange' end
  if hue < 70 then return 'Yellow' end
  if hue < 165 then return 'Green' end
  if hue < 255 then return 'Blue' end
  if hue < 290 then return 'Purple' end
  return 'Pink'
end

--- Main colour of a vehicle ("Red"), translated, or nil.
local function colourOf(entity)
  local name = nil
  local okCustom, custom = pcall(GetIsVehiclePrimaryColourCustom, entity)
  if okCustom and (custom == true or custom == 1) then
    local okRgb, r, g, b = pcall(GetVehicleCustomPrimaryColour, entity)
    if okRgb then name = colourOfRgb(r, g, b) end
  end
  if not name then
    local ok, primary = pcall(GetVehicleColours, entity)
    if ok then name = colourOfIndex(primary) end
  end
  return name and L(name) or nil
end

local modelNames = nil   -- [hash] = 'Brand Name' (QBCore / Qbox shared vehicles)

local function loadModelNames()
  modelNames = {}
  local list = nil
  if NZ.Framework == 'qbx' then
    local ok, res = pcall(function() return exports.qbx_core:GetVehiclesByHash() end)
    if ok and type(res) == 'table' then list = res end
  end
  if not list and (NZ.Framework == 'qb' or NZ.Framework == 'qbx') then
    local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and type(core) == 'table' and type(core.Shared) == 'table' and type(core.Shared.Vehicles) == 'table' then
      list = core.Shared.Vehicles
    end
  end
  for key, v in pairs(list or {}) do
    if type(v) == 'table' and type(v.name) == 'string' then
      local hash = tonumber(v.hash) or (type(v.model) == 'string' and joaat(v.model))
        or (type(key) == 'number' and key) or (type(key) == 'string' and joaat(key)) or nil
      if hash then
        hash = math.floor(hash) % 4294967296
        if hash > 2147483647 then hash = hash - 4294967296 end
        local brand = type(v.brand) == 'string' and v.brand ~= '' and v.brand or nil
        modelNames[math.tointeger(hash) or hash] = brand and ('%s %s'):format(brand, v.name) or v.name
      end
    end
  end
end

--- Model label: shared vehicle list, else the owned row's model, else the label the client
--- sent (display only), else nil (clients fill it in from the model hash). The second value is
--- true when the label is the client's (officers' clients then look it up themselves).
local function modelOf(entity, plate, clientLabel)
  local hash = GetEntityModel(entity)
  if modelNames == nil then pcall(loadModelNames) end
  if modelNames and modelNames[hash] then return modelNames[hash], false end
  local row = plate and CarLock.vehicleRow(plate) or nil
  if row and type(row.model) == 'string' and row.model ~= '' then
    return row.model:sub(1, 1):upper() .. row.model:sub(2), false
  end
  return clientLabel, clientLabel ~= nil
end

--- Police alert for a crime on `entity` (rolled by the caller). One alert per player and
--- vehicle within dispatch.cooldown seconds (one incident, one call).
---@param src number
---@param kind string
---@param entity number
---@param session table|nil (street / label the client sent)
---@return boolean sent
function CarLock.crimeAlert(src, kind, entity, session)
  if not isVehicle(entity) or type(NZ.Dispatch.alert) ~= 'function' then return false end
  local plate = CarLock.realPlate(entity) or '?'
  local key = ('%s|%s'):format(tostring(src), plate)
  local seconds = tonumber(section('dispatch').cooldown) or 30
  local last = alerted[key]
  if last and now() - last < seconds * 1000 then return false end
  alerted[key] = now()
  if math.random(1, 40) == 1 then
    for k, at in pairs(alerted) do
      if now() - at > seconds * 1000 then alerted[k] = nil end
    end
  end
  local coords = GetEntityCoords(entity)
  local visible = Utils.plate(GetVehicleNumberPlateText(entity))
  session = type(session) == 'table' and session or {}
  local model, modelFromClient = modelOf(entity, CarLock.realPlate(entity), session.label)
  local ok, sent = pcall(NZ.Dispatch.alert, src, {
    kind = kind,
    coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
    plate = visible,
    model = model,
    modelHash = GetEntityModel(entity),
    color = colourOf(entity),
    street = session.street,
    -- text the offender's client sent: officers' clients replace it with their own lookup
    -- (server coordinates / model hash); server-side systems keep it (no street names here)
    streetFromClient = session.street ~= nil or nil,
    modelFromClient = modelFromClient or nil,
  })
  return ok and sent == true
end

--- Roll the alert of an attempt: the action's chance (reported as that crime, alarm or not),
--- else (when the alarm went off) alarm.alertChance as a car alarm report.
local function rollAlert(src, kind, entity, chance, alarmOn, session)
  if roll(chance) then
    return CarLock.crimeAlert(src, kind, entity, session)
  end
  if alarmOn and roll(section('alarm').alertChance) then
    return CarLock.crimeAlert(src, 'alarm', entity, session)
  end
  return false
end

---------------------------------------------------------------------------------------
-- Profiles, tools, skill checks
---------------------------------------------------------------------------------------

local DIFFICULTIES = { easy = true, medium = true, hard = true }

--- Skill check list the client may show: 'easy' | 'medium' | 'hard' | { areaSize, speedMultiplier }.
local function checksOf(list)
  local out = {}
  if type(list) == 'string' then list = { list } end
  for _, entry in ipairs(type(list) == 'table' and list or {}) do
    if type(entry) == 'string' and DIFFICULTIES[entry] then
      out[#out + 1] = entry
    elseif type(entry) == 'table' then
      local area, speed = tonumber(entry.areaSize), tonumber(entry.speedMultiplier)
      if area and speed then
        out[#out + 1] = { areaSize = Utils.clamp(area, 5, 100), speedMultiplier = Utils.clamp(speed, 0.2, 5) }
      end
    end
    if #out >= MAX_CHECKS then break end
  end
  if #out == 0 then out[1] = 'medium' end
  return out
end

local function inputsOf(list)
  if type(list) ~= 'table' then return nil end
  local out = {}
  for _, key in ipairs(list) do
    if type(key) == 'string' and #key == 1 then out[#out + 1] = key:lower() end
    if #out >= 8 then break end
  end
  return #out > 0 and out or nil
end

--- The profile's access tool entry for a Config.CarLock.items key (or item name).
local function accessTool(profile, toolKey)
  for _, entry in ipairs(type(profile.accessTools) == 'table' and profile.accessTools or {}) do
    if type(entry) == 'table' and type(entry.item) == 'string'
      and (entry.item == toolKey or CarLock.itemName(entry.item) == toolKey) then
      return entry
    end
  end
  return nil
end

--- Config.CarLock.items key of an item name used as a tool ('lockpick', ...).
local TOOL_KEYS = { 'lockpick', 'advancedLockpick', 'screwdriver', 'hackingDevice' }
local function toolKeyOf(item, key)
  if type(key) == 'string' and CarLock.itemName(key) == item then return key end
  for _, k in ipairs(TOOL_KEYS) do
    if CarLock.itemName(k) == item then return k end
  end
  return nil
end

--- A slot of `item` the player really has there (else nil: any slot).
local function slotOf(src, item, slot)
  slot = tonumber(slot)
  if not slot then return nil end
  local entry = NZ.Inventory.getSlot(src, slot)
  if entry and entry.name == item and (tonumber(entry.count) or 0) > 0 then return math.tointeger(slot) or slot end
  return nil
end

local function breakItem(src, item, slot)
  if slot and NZ.Inventory.removeItem(src, item, 1, nil, slot) then return true end
  return NZ.Inventory.removeItem(src, item, 1) == true
end

---------------------------------------------------------------------------------------
-- NPC behaviour (run by the client that owns the ped)
---------------------------------------------------------------------------------------

--- Tell the owner of the session's ped (else the player) to run an NPC step.
local function npcStep(session, step, extra)
  if not isPed(session.ped) then return end
  local okOwner, owner = pcall(NetworkGetEntityOwner, session.ped)
  local target = okOwner and validSrc(owner) or nil
  target = target or session.src
  local payload = { step = step, ped = session.pedNetId, vehicle = session.netId, robber = session.src }
  for k, v in pairs(extra or {}) do payload[k] = v end
  TriggerClientEvent('nz:client:carlock:npc', target, payload)
end

local function fightWeapon()
  local weapon = section('npc').fightWeapon
  if type(weapon) ~= 'string' or weapon == '' then return nil end
  return weapon:upper():sub(1, 48)
end

---------------------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------------------

local function closeSession(session)
  if sessions[session.src] == session then sessions[session.src] = nil end
  if session.ped and busyPeds[session.ped] == session.src then busyPeds[session.ped] = nil end
  if session.action == 'search' and searching[session.entity] == session.src then searching[session.entity] = nil end
end

--- Is `key` (a ped in busyPeds / a vehicle in searching) still held by a running session of
--- its player? A lock whose session finished, expired or was replaced is dropped.
local function held(map, key)
  local owner = map[key]
  if owner == nil then return false end
  local s = sessions[owner]
  if s and not s.finished and (s.ped == key or s.entity == key) and now() <= s.maxAt then return true end
  map[key] = nil
  return false
end

--- A stopped NPC (hold-up / request) whose player never finished: release it once the session
--- runs out (flee after a hold-up, drive on after a request).
local function releaseOnExpiry(session, step)
  SetTimeout(math.max(0, session.maxAt - now()) + 100, function()
    if session.finished then return end
    session.finished = true
    closeSession(session)
    if isPed(session.ped) and alive(session.ped) then npcStep(session, step) end
  end)
end

--- A running session blocks a new one until it ends or expires.
local function freeForSession(src)
  local current = sessions[src]
  if not current then return true end
  if now() > current.maxAt then
    closeSession(current)
    return true
  end
  return false
end

local function openSession(src, data, minMs, maxMs)
  counter = counter + 1
  local session = data
  session.id = counter
  session.src = src
  session.startedAt = now()
  session.minAt = session.startedAt + math.max(0, math.floor(minMs))
  session.maxAt = session.startedAt + math.floor(maxMs)
  sessions[src] = session
  return session
end

local turnMs = nil

--- One turn of the ox_lib skill-check indicator at speed 1, for the ox_lib version running.
local function indicatorTurnMs()
  if turnMs then return turnMs end
  local ok, version = pcall(GetResourceMetadata, 'ox_lib', 'version', 0)
  local major, minor, patch = nil, nil, nil
  if ok and type(version) == 'string' then major, minor, patch = version:match('^%s*v?(%d+)%.(%d+)%.?(%d*)') end
  major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch) or 0
  -- communityox 3.32.3 and overextended 3.33.0 moved to requestAnimationFrame (2000 ms a turn);
  -- unknown version: the older (faster) timing, so honest players are never refused
  local modern = major ~= nil and minor ~= nil
    and (major > 3 or (major == 3 and (minor > 32 or (minor == 32 and patch >= 3))))
  turnMs = modern and TURN_MS or TURN_MS_OLD
  return turnMs
end

-- an updated ox_lib (restarted) may change the timing: read its version again
AddEventHandler('onResourceStart', function(name)
  if name == 'ox_lib' then turnMs = nil end
end)

--- Earliest pass of one check ('easy' | 'medium' | 'hard' | { areaSize, speedMultiplier }).
local function checkMinMs(check)
  local speed = type(check) == 'table' and tonumber(check.speedMultiplier) or CHECK_SPEED[check] or 1.0
  return math.floor(CHECK_SHARE * indicatorTurnMs() / math.max(speed, 0.2))
end

--- Timing window of a list of skill checks: the fastest a person can pass them all (after the
--- `leadMs` the client always spends before the first one) and the slowest.
local function skillWindow(checks, leadMs)
  leadMs = leadMs or 0
  local min = leadMs
  for _, check in ipairs(checks) do min = min + checkMinMs(check) end
  return min, LEAD_MS + leadMs + #checks * CHECK_MAX_MS + 5000
end

local function progressWindow(duration)
  return duration - GRACE_MS, duration + LATE_MS
end

--- Common vehicle checks of a 'start'. Returns entity, dist, inside, plate or nil, error.
local function vehicleOf(src, payload, allowKey)
  local entity, dist, inside = CarLock.vehicleFromNet(src, payload.netId)
  if not entity then return nil, L('Vehicle not found') end
  if towing(entity) then return nil, L('This vehicle is being towed') end
  local plate = CarLock.realPlate(entity)
  if not plate then return nil, L('Vehicle not found') end
  if not allowKey and CarLock.hasKey(src, plate) then return nil, L('You already have the keys of this vehicle') end
  return entity, dist, inside, plate
end

--- An NPC driver of `entity` from a client's ped net id: ped or nil, error.
local function driverOf(entity, pedNetId)
  local id = tonumber(pedNetId)
  if not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return nil, L('Invalid request') end
  local ped = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not isNpc(ped) then return nil, L('Invalid request') end
  if GetPedInVehicleSeat(entity, -1) ~= ped then return nil, L('Nobody is driving this vehicle') end
  if not alive(ped) then return nil, L('The driver cannot react any more') end
  if not ambientPed(ped) then return nil, L('This driver will not give you the keys') end
  if held(busyPeds, ped) then return nil, L('Someone else is dealing with this driver') end
  return ped, nil
end

local function displayInfo(payload)
  return text(payload.street, 64), text(payload.label, 48)
end

---------------------------------------------------------------------------------------
-- NUI minigames (pin lock, wires, signal reader): the server makes the puzzle, the client
-- plays it and sends its answer with `finish`; a wrong answer is a failure.
---------------------------------------------------------------------------------------

local WIRE_COLOURS = { 'red', 'blue', 'yellow', 'green', 'white', 'orange' }
local MINIGAME_MAX_MS = 90000
local PIN_MIN_MS = 450          -- per pin: tension, find the binding pin, lift it
local WIRES_MIN_MS = 2400       -- three splices
local READER_MIN_MS = 2000      -- tune frequency and phase
local READER_TOLERANCE = { frequency = 1.5, phase = 8 }

local function shuffled(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = math.random(1, i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

local function pinsPuzzle(count)
  local order = {}
  for i = 1, count do order[i] = i end
  order = shuffled(order)
  local heights = {}
  for i = 1, count do heights[i] = math.random(25, 90) / 100 end
  -- the client is told the heights (to draw them) and the binding order (to make the pin it
  -- has to lift bind first); the answer is the order the pins were set
  return { pins = count, order = order, heights = heights }
end

local function wiresPuzzle()
  local left = {}
  local pool = shuffled(WIRE_COLOURS)
  for i = 1, 3 do left[i] = pool[i] end
  return { left = left, right = shuffled(left) }
end

local function readerPuzzle()
  return { frequency = math.random(3000, 9000) / 10, phase = math.random(0, 359), tolerance = READER_TOLERANCE }
end

--- Is `answer` (client) the solution of `puzzle`?
local function solved(method, puzzle, answer)
  if type(puzzle) ~= 'table' then return true end
  if type(answer) ~= 'table' then return false end
  if method == 'pins' then
    for i = 1, puzzle.pins do
      if tonumber(answer[i]) ~= puzzle.order[i] then return false end
    end
    return #answer == puzzle.pins
  elseif method == 'wires' then
    -- answer[i] = the position on the right that left wire i was spliced to
    if #answer ~= 3 then return false end
    local used = {}
    for i = 1, 3 do
      local j = math.tointeger(tonumber(answer[i]))
      if not j or j < 1 or j > 3 or used[j] or puzzle.right[j] ~= puzzle.left[i] then return false end
      used[j] = true
    end
    return true
  elseif method == 'reader' then
    local f, ph = tonumber(answer.frequency), tonumber(answer.phase)
    if not f or not ph then return false end
    local dPhase = math.abs((ph - puzzle.phase + 180) % 360 - 180)
    return math.abs(f - puzzle.frequency) <= READER_TOLERANCE.frequency and dPhase <= READER_TOLERANCE.phase
  end
  return true
end

---------------------------------------------------------------------------------------
-- Lockpick
---------------------------------------------------------------------------------------

local function lockpickStart(src, payload)
  local entity, dist, inside, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(dist) end
  if inside or dist > accessRange(entity) then return Utils.fail(L('You are too far from the vehicle')) end
  if not CarLock.isLocked(entity) then return Utils.fail(L('This vehicle is not locked')) end
  local driver = GetPedInVehicleSeat(entity, -1)
  if driver and driver ~= 0 and alive(driver) then return Utils.fail(L('Someone is sitting in this vehicle')) end
  local _, profile = CarLock.profileOfEntity(entity)
  local toolKey = type(payload.tool) == 'string' and payload.tool or nil
  local tool, item = nil, nil
  if toolKey then
    tool = accessTool(profile, toolKey)
    if not tool then return Utils.fail(L('This tool does not work on this vehicle')) end
    item = CarLock.itemName(tool.item)
    if not NZ.Inventory.hasItem(src, item) then return Utils.fail(L('You do not have the right tool')) end
  else
    -- target option: the first tool of the profile the player carries
    for _, entry in ipairs(type(profile.accessTools) == 'table' and profile.accessTools or {}) do
      local name = type(entry) == 'table' and CarLock.itemName(entry.item) or nil
      if name and NZ.Inventory.hasItem(src, name) then tool, item = entry, name break end
    end
    if not tool then return Utils.fail(L('You do not have the right tool for this vehicle')) end
  end
  local checks = checksOf(tool.difficulty)
  local street, label = displayInfo(payload)
  local picking = section('lockpicking')
  if picking.style == 'pins' then
    -- the five-pin lock of the NUI (G.6): the server picks the binding order
    local count = math.floor(Utils.clamp(tonumber(picking.pins) or 5, 3, 7))
    local puzzle = pinsPuzzle(count)
    local session = openSession(src, {
      action = 'lockpick', entity = entity, netId = netIdOf(entity), plate = plate, tool = tool, item = item,
      slot = slotOf(src, item, payload.slot), street = street, label = label, method = 'pins', puzzle = puzzle,
    }, DOOR_TURN_MS + count * PIN_MIN_MS - GRACE_MS, MINIGAME_MAX_MS)
    return Utils.ok({ id = session.id, method = 'pins', puzzle = puzzle, tool = tool.item, item = item,
      snapChance = Utils.clamp(tonumber(picking.snapChance) or 35, 0, 100) })
  end
  local session = openSession(src, {
    action = 'lockpick', entity = entity, netId = netIdOf(entity), plate = plate, tool = tool, item = item,
    slot = slotOf(src, item, payload.slot), street = street, label = label,
  }, skillWindow(checks, DOOR_TURN_MS))
  return Utils.ok({ id = session.id, method = 'skillcheck', difficulty = checks, inputs = inputsOf(tool.inputs),
    tool = tool.item, item = item })
end

local function lockpickFinish(src, session, success, payload)
  local entity = session.entity
  if not isVehicle(entity) then return Utils.fail(L('Vehicle not found')) end
  local ped = pedOf(src)
  if success and (not ped or distance(ped, entity) > accessRange(entity) + SLACK) then success = false end
  if success and not NZ.Inventory.hasItem(src, session.item) then success = false end
  if success and session.method == 'pins' and not solved('pins', session.puzzle, type(payload) == 'table' and payload.answer or nil) then
    success = false
  end
  local result = { success = success }
  if success then
    CarLock.setLocked(entity, false)
  else
    -- pin lock: an overset pin (the client says so) snaps the pick at snapChance %, else the tool's break chance
    local picking = section('lockpicking')
    local snapped = session.method == 'pins' and type(payload) == 'table' and payload.snapped == true
    local breakChance = snapped and Utils.clamp(tonumber(picking.snapChance) or 35, 0, 100) or session.tool.breakChance
    if roll(breakChance) and breakItem(src, session.item, session.slot) then result.broke = true end
    if (snapped and result.broke and picking.alarmOnSnap ~= false and CarLock.alarm(entity))
      or (not result.alarm and roll(session.tool.alarmChance) and CarLock.alarm(entity)) then
      result.alarm = true
    end
  end
  rollAlert(src, 'lockpick', entity, session.tool.alertChance, result.alarm, session)
  log('vehicle.lockpick', src, { plate = session.plate, tool = session.item, success = success, broke = result.broke })
  return Utils.ok(result)
end

---------------------------------------------------------------------------------------
-- Hotwire
---------------------------------------------------------------------------------------

local METHODS = { skillcheck = true, progress = true, hack = true }

local function hotwireStart(src, payload)
  local entity, dist, inside, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(dist) end
  local ped = pedOf(src)
  if not inside or GetPedInVehicleSeat(entity, -1) ~= ped then return Utils.fail(L('You are not in the driver seat')) end
  if CarLock.jobBypass(src, plate) then return Utils.fail(L('You can start this vehicle')) end
  -- an immobiliser (standard or Ghost) cannot be hotwired
  if CarLock.immobiliserOf(plate) ~= 'none' then return Utils.fail(L('An immobiliser stops you from hotwiring this vehicle')) end
  local _, profile = CarLock.profileOfEntity(entity)
  local hotwire = type(profile.hotwire) == 'table' and profile.hotwire or {}
  local game = CarLock.hotwireMethodOf(GetEntityModel(entity), CarLock.classOf(entity), profile)
  if game == 'wires' or game == 'reader' then
    -- the NUI minigames (G.7): wires (hotwiring.kitRequired: items.hotwireKit) or the signal reader
    local need = nil
    if game == 'reader' then
      need = CarLock.itemName('signalReader')
    elseif section('hotwiring').kitRequired == true then
      need = CarLock.itemName('hotwireKit')
    end
    if need and not NZ.Inventory.hasItem(src, need) then
      return Utils.fail(game == 'reader' and L('You need a signal reader to start this vehicle') or L('You need a hotwire kit'))
    end
    local puzzle = game == 'reader' and readerPuzzle() or wiresPuzzle()
    local street, label = displayInfo(payload)
    local session = openSession(src, { action = 'hotwire', entity = entity, netId = netIdOf(entity), plate = plate,
      hotwire = hotwire, method = game, puzzle = puzzle, street = street, label = label },
      (game == 'reader' and READER_MIN_MS or WIRES_MIN_MS) - GRACE_MS, MINIGAME_MAX_MS)
    return Utils.ok({ id = session.id, method = game, puzzle = puzzle, item = need })
  end
  local method = METHODS[hotwire.method] and hotwire.method or 'skillcheck'
  local item = nil
  if method == 'hack' then
    item = CarLock.itemName(hotwire.item or 'hackingDevice')
    if not item or not NZ.Inventory.hasItem(src, item) then
      return Utils.fail(L('You need a hacking device to start this vehicle'))
    end
  end
  local street, label = displayInfo(payload)
  local data = { action = 'hotwire', entity = entity, netId = netIdOf(entity), plate = plate, hotwire = hotwire,
    method = method, item = item, slot = item and slotOf(src, item, payload.slot) or nil, street = street, label = label }
  if method == 'progress' then
    local duration = math.floor(Utils.clamp(tonumber(hotwire.duration) or 6000, 1000, 60000))
    local session = openSession(src, data, progressWindow(duration))
    return Utils.ok({ id = session.id, method = method, duration = duration })
  end
  local checks = checksOf(hotwire.difficulty)
  local session = openSession(src, data, skillWindow(checks))
  return Utils.ok({ id = session.id, method = method, difficulty = checks, inputs = inputsOf(hotwire.inputs), item = item })
end

local function hotwireFinish(src, session, success, payload)
  local entity = session.entity
  if not isVehicle(entity) then return Utils.fail(L('Vehicle not found')) end
  local ped = pedOf(src)
  if success and (not ped or GetPedInVehicleSeat(entity, -1) ~= ped) then success = false end
  if success and session.item and not NZ.Inventory.hasItem(src, session.item) then success = false end
  if success and session.puzzle and not solved(session.method, session.puzzle, type(payload) == 'table' and payload.answer or nil) then
    success = false
  end
  local result = { success = success }
  if success then
    CarLock.grantTemp(src, session.plate, 'hotwire')
  else
    if session.item and roll(session.hotwire.breakChance) and breakItem(src, session.item, session.slot) then result.broke = true end
    if roll(session.hotwire.alarmChance) and CarLock.alarm(entity) then result.alarm = true end
  end
  rollAlert(src, 'hotwire', entity, session.hotwire.alertChance, result.alarm, session)
  log('vehicle.hotwire', src, { plate = session.plate, method = session.method, success = success })
  return Utils.ok(result)
end

---------------------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------------------

local function rememberPlate(plate)
  if searchedPlates[plate] then return end
  if searchedCount >= MAX_MEMORY then searchedPlates, searchedCount = {}, 0 end
  searchedPlates[plate] = true
  searchedCount = searchedCount + 1
end

local function searchStart(src, payload)
  local search = section('search')
  if search.enabled == false then return Utils.fail(L('You cannot search this vehicle')) end
  local entity, dist, inside, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(dist) end
  local ped = pedOf(src)
  if not inside or GetPedInVehicleSeat(entity, -1) ~= ped then return Utils.fail(L('You are not in the driver seat')) end
  -- never job / gang vehicles of the player's own job, never script- or player-spawned cars
  if CarLock.jobBypass(src, plate) then return Utils.fail(L('You cannot search this vehicle')) end
  if search.ambientOnly ~= false and not ambientEntity(entity) then return Utils.fail(L('You cannot search this vehicle')) end
  if search.ownedVehicles ~= true and ownedPlate(plate) then return Utils.fail(L('You cannot search this vehicle')) end
  if searched[entity] or searchedPlates[plate] then return Utils.fail(L('This vehicle was already searched')) end
  if held(searching, entity) then return Utils.fail(L('Someone is already searching this vehicle')) end
  if onCooldown(src, 'search') then return Utils.fail(L('Wait a moment before searching another vehicle')) end
  local duration = math.floor(Utils.clamp(tonumber(search.duration) or 7000, 1000, 60000))
  local street, label = displayInfo(payload)
  searching[entity] = src
  local session = openSession(src, { action = 'search', entity = entity, netId = netIdOf(entity), plate = plate,
    street = street, label = label }, progressWindow(duration))
  return Utils.ok({ id = session.id, duration = duration })
end

--- Roll the loot of a search: returns a list of lines for the player.
local function rollLoot(src, plate, entity)
  local search = section('search')
  local found = {}
  local money = type(search.money) == 'table' and search.money or nil
  if money and roll(money.chance) then
    local min = math.max(0, math.floor(tonumber(money.min) or 0))
    local max = math.max(min, math.floor(tonumber(money.max) or min))
    local amount = math.random(min, max)
    local account = money.account == 'bank' and 'bank' or 'cash'
    if amount > 0 and type(NZ.Bridge.addMoney) == 'function' then
      local ok, added = pcall(NZ.Bridge.addMoney, src, account, amount, 'vehicle-search')
      if ok and added then found[#found + 1] = L('${amount}', { amount = amount }) end
    end
  end
  for _, entry in ipairs(type(search.items) == 'table' and search.items or {}) do
    if type(entry) == 'table' and type(entry.item) == 'string' and roll(entry.chance) then
      local min = math.max(1, math.floor(tonumber(entry.min) or 1))
      local max = math.max(min, math.floor(tonumber(entry.max) or min))
      local count = math.random(min, max)
      if NZ.Inventory.addItem(src, entry.item, count) then
        found[#found + 1] = L('{count}x {item}', { count = count, item = entry.item })
      end
    end
  end
  if roll(search.spareKeyChance) then
    local given = false
    if search.spareKeyItem ~= false and CarLock.mode() == 'physical' then
      local _, profile = CarLock.profileOfEntity(entity)
      given = CarLock.giveKeyItem(src, plate, { kind = CarLock.keyKindOf(profile), reason = 'search', origin = 'search' }) == true
    end
    if not given then given = CarLock.grantTemp(src, plate, 'search') end
    if given then found[#found + 1] = L('a spare key') end
  end
  return found
end

local function searchFinish(src, session, success)
  local entity = session.entity
  if not isVehicle(entity) then return Utils.fail(L('Vehicle not found')) end
  local ped = pedOf(src)
  if success and (not ped or GetPedInVehicleSeat(entity, -1) ~= ped) then success = false end
  if not success then return Utils.ok({ success = false }) end
  searched[entity] = true
  setCooldown(src, 'search', tonumber(section('search').cooldown) or 30)
  rememberPlate(session.plate)
  pcall(function() Entity(entity).state:set('nzSearched', true, true) end)
  local found = rollLoot(src, session.plate, entity)
  rollAlert(src, 'search', entity, section('search').alertChance, false, session)
  log('vehicle.search', src, { plate = session.plate, found = #found })
  return Utils.ok({ success = true, found = found })
end

---------------------------------------------------------------------------------------
-- NPC robbery (aim at the driver)
---------------------------------------------------------------------------------------

local function robRange() return Utils.clamp(tonumber(section('npc').range) or 6.0, 2.0, 15.0) end

local REACTIONS = { 'handover', 'drop', 'fight', 'flee' }

--- How a held-up driver reacts (Config.CarLock.npc.reactions weights; older configs:
--- resistChance / fightChance). 'drop' needs keys on the ground (else 'handover').
local function pickReaction(npc)
  local weights = type(npc.reactions) == 'table' and npc.reactions or nil
  if not weights then
    if not roll(npc.resistChance) then return 'handover' end
    return roll(npc.fightChance) and 'fight' or 'flee'
  end
  local total = 0
  for _, name in ipairs(REACTIONS) do total = total + math.max(tonumber(weights[name]) or 0, 0) end
  if total <= 0 then return 'handover' end
  local pick = math.random() * total
  local reaction = 'handover'
  for _, name in ipairs(REACTIONS) do
    local w = math.max(tonumber(weights[name]) or 0, 0)
    if w > 0 then
      if pick < w then reaction = name break end
      pick = pick - w
    end
  end
  local ground = section('ground')
  if reaction == 'drop' and (ground.enabled == false or type(CarLock.groundDropTemp) ~= 'function') then return 'handover' end
  return reaction
end

--- On-duty officers (Config.CarLock.dispatch.jobs); nil when the dispatch bridge cannot tell.
local function policeOnline()
  local receivers = type(NZ.Dispatch) == 'table' and rawget(NZ.Dispatch, 'receivers') or nil
  if type(receivers) ~= 'function' then return nil end
  local jobs = section('dispatch').jobs
  local ok, list = pcall(receivers, type(jobs) == 'table' and jobs or { 'police' })
  return ok and type(list) == 'table' and #list or nil
end

--- The hold-up's police alert, after npc.dispatchDelay seconds.
local function robberyAlert(src, entity, session)
  local npc = section('npc')
  local delay = math.floor(Utils.clamp(tonumber(npc.dispatchDelay) or 0, 0, 600))
  if delay <= 0 then return rollAlert(src, 'robbery', entity, npc.alertChance, false, session) end
  if not roll(npc.alertChance) then return false end
  SetTimeout(delay * 1000, function()
    if isVehicle(entity) then CarLock.crimeAlert(src, 'robbery', entity, session) end
  end)
  return true
end

local function robStart(src, payload)
  local npc = section('npc')
  if npc.robbery == false then return Utils.fail(L('You cannot do that')) end
  if onCooldown(src, 'rob') then return Utils.fail(L('Wait a moment before robbing someone again')) end
  local entity, dist, inside, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(dist) end
  if inside or dist > robRange() + 1.0 then return Utils.fail(L('You are too far from the vehicle')) end
  local ped, err = driverOf(entity, payload.pedNetId)
  if not ped then return Utils.fail(err) end
  if npc.ownedVehicles ~= true and ownedPlate(plate) then return Utils.fail(L('This driver will not give you the keys')) end
  if speedOf(entity) > (tonumber(npc.maxSpeed) or 8.0) + 1.0 then return Utils.fail(L('The vehicle is moving too fast')) end
  if not armed(pedOf(src)) then return Utils.fail(L('You need a weapon')) end
  local needPolice = math.floor(tonumber(npc.policeRequired) or 0)
  if needPolice > 0 then
    local online = policeOnline()
    if online ~= nil and online < needPolice then return Utils.fail(L('There are not enough police officers around')) end
  end

  setCooldown(src, 'rob', npc.cooldown or 60)
  drivers[entity] = { ped = ped, at = now() }
  local street, label = displayInfo(payload)
  local base = { action = 'rob', entity = entity, netId = netIdOf(entity), plate = plate, ped = ped,
    pedNetId = netIdOf(ped), street = street, label = label }

  local reaction = pickReaction(npc)
  if reaction == 'fight' or reaction == 'flee' then
    -- resists: no key; drives off or fights
    base.src = src
    npcStep(base, reaction, { weapon = reaction == 'fight' and fightWeapon() or nil })
    robberyAlert(src, entity, base)
    log('vehicle.robbery', src, { plate = plate, outcome = reaction })
    return Utils.ok({ outcome = reaction })
  end
  if reaction == 'drop' then
    -- drops the key next to the driver door and runs: a key on the ground anyone can pick up
    base.src = src
    busyPeds[ped] = src
    npcStep(base, 'drop', {})
    CarLock.setLocked(entity, false)
    local bucket = GetEntityRoutingBucket(entity)
    local _, profile = CarLock.profileOfEntity(entity)
    local keyKind = CarLock.keyKindOf(profile)
    SetTimeout(2600, function()
      if busyPeds[ped] == src then busyPeds[ped] = nil end
      local spot = nil
      -- at the driver's feet once out (z: ped origin ~1 m above the ground), else by the driver door
      if isPed(ped) and isVehicle(entity) and GetVehiclePedIsIn(ped, false) ~= entity and distance(ped, entity) <= 6.0 then
        local c = GetEntityCoords(ped)
        spot = vector3(c.x, c.y, c.z - 0.9)
      elseif isVehicle(entity) then
        local h = math.rad(tonumber(GetEntityHeading(entity)) or 0.0)
        local c = GetEntityCoords(entity)
        spot = vector3(c.x - math.cos(h) * 1.4, c.y - math.sin(h) * 1.4, c.z - 0.3)
      end
      if spot then CarLock.groundDropTemp(plate, spot, bucket, 'robbery', keyKind) end
    end)
    robberyAlert(src, entity, base)
    log('vehicle.robbery', src, { plate = plate, outcome = 'drop' })
    return Utils.ok({ outcome = 'drop' })
  end

  local robTime = math.floor(Utils.clamp(tonumber(npc.robTime) or 3500, 500, 30000))
  busyPeds[ped] = src
  local session = openSession(src, base, progressWindow(robTime))
  npcStep(session, 'holdup', { ms = robTime + 5000 })
  releaseOnExpiry(session, 'flee')
  return Utils.ok({ id = session.id, outcome = 'comply', duration = robTime })
end

local function robFinish(src, session, success)
  local entity, ped = session.entity, session.ped
  if not isVehicle(entity) then return Utils.fail(L('Vehicle not found')) end
  local player = pedOf(src)
  if success then
    if not player or distance(player, entity) > robRange() + SLACK then success = false
    elseif not isPed(ped) or not alive(ped) then success = false
    elseif GetVehiclePedIsIn(ped, false) ~= entity and distance(ped, entity) > 6.0 then success = false
    elseif not armed(player) then success = false
    end
  end
  if success then
    CarLock.grantTemp(src, session.plate, 'robbery')
    CarLock.setLocked(entity, false)
    npcStep(session, 'release')
    robberyAlert(src, entity, session)
  elseif isPed(ped) and alive(ped) then
    npcStep(session, 'flee')
  end
  log('vehicle.robbery', src, { plate = session.plate, outcome = success and 'comply' or 'aborted' })
  return Utils.ok({ success = success })
end

---------------------------------------------------------------------------------------
-- Assistance (authorized jobs ask an NPC driver for the vehicle)
---------------------------------------------------------------------------------------

local function assistAllowed(src)
  local jobs = section('npc').assistJobs
  if type(jobs) ~= 'table' or type(NZ.Bridge.getJob) ~= 'function' then return false end
  local ok, job = pcall(NZ.Bridge.getJob, src)
  if not ok or type(job) ~= 'table' or type(job.name) ~= 'string' or job.onDuty == false then return false end
  local name = job.name:lower()
  for _, allowed in ipairs(jobs) do
    if type(allowed) == 'string' and allowed:lower() == name then return true end
  end
  return false
end

local function assistStart(src, payload)
  if not assistAllowed(src) then return Utils.fail(L('You are not allowed to do that')) end
  if onCooldown(src, 'assist') then return Utils.fail(L('Please wait a moment')) end
  local entity, dist, inside, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(dist) end
  if inside or dist > ASSIST_RANGE then return Utils.fail(L('You are too far from the vehicle')) end
  local ped, err = driverOf(entity, payload.pedNetId)
  if not ped then return Utils.fail(err) end
  if section('npc').ownedVehicles ~= true and ownedPlate(plate) then return Utils.fail(L('This driver will not give you the keys')) end
  setCooldown(src, 'assist', section('npc').assistCooldown or 10)
  drivers[entity] = { ped = ped, at = now() }
  busyPeds[ped] = src
  local session = openSession(src, { action = 'assist', entity = entity, netId = netIdOf(entity), plate = plate,
    ped = ped, pedNetId = netIdOf(ped) }, progressWindow(ASSIST_MS))
  npcStep(session, 'pullover', { ms = ASSIST_MS + 5000 })
  releaseOnExpiry(session, 'resume')
  return Utils.ok({ id = session.id, duration = ASSIST_MS })
end

local function assistFinish(src, session, success)
  local entity, ped = session.entity, session.ped
  if not isVehicle(entity) then return Utils.fail(L('Vehicle not found')) end
  local player = pedOf(src)
  if success and (not player or distance(player, entity) > ASSIST_RANGE + SLACK) then success = false end
  if success and (not isPed(ped) or not alive(ped)) then success = false end
  if success then
    CarLock.grantTemp(src, session.plate, 'assist')
    CarLock.setLocked(entity, false)
    npcStep(session, 'handover')
  elseif isPed(ped) and alive(ped) then
    npcStep(session, 'resume')
  end
  log('vehicle.assist', src, { plate = session.plate, success = success })
  return Utils.ok({ success = success })
end

---------------------------------------------------------------------------------------
-- Dead original driver: search the body for the key
---------------------------------------------------------------------------------------

--- Was `ped` the driver of `entity`? The server's record of an interaction, the driver seat,
--- or the vehicle's last driver still near it (server-side facts only).
local function wasDriver(entity, ped)
  local record = drivers[entity]
  if record and record.ped == ped then return true end
  if GetPedInVehicleSeat(entity, -1) == ped then return true end
  local ok, last = pcall(GetLastPedInVehicleSeat, entity, -1)
  return ok and last == ped and distance(ped, entity) <= LAST_DRIVER_RANGE
end

local function deadDriverStart(src, payload)
  if section('npc').deadDriverKeys == false then return Utils.fail(L('You cannot do that')) end
  local entity, err, _, plate = vehicleOf(src, payload)
  if not entity then return Utils.fail(err) end
  local id = tonumber(payload.pedNetId)
  if not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return Utils.fail(L('Invalid request')) end
  local ped = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not isNpc(ped) then return Utils.fail(L('Invalid request')) end
  local health = healthOf(ped)
  if health == nil or health > 100 then return Utils.fail(L('This person is not dead')) end
  if searchedBodies[ped] then return Utils.fail(L('This body was already searched')) end
  if held(busyPeds, ped) then return Utils.fail(L('Someone else is dealing with this driver')) end
  -- traffic drivers only (npc.ambientOnly): never the driver of another script's mission
  -- vehicle, never a ped a client spawned and put in a seat. A recorded driver passed that
  -- check when its robbery / request started.
  local record = drivers[entity]
  local recorded = record ~= nil and record.ped == ped
  if not recorded and not ambientPed(ped) then return Utils.fail(L('There is no key on this body')) end
  -- an unrecorded driver only counts in a TRAFFIC vehicle (population 1/3/4/5, kept when the
  -- driver dies): never a random parked car (2) or a script vehicle (7) with an ambient
  -- pedestrian a modified client warped into the seat
  if not recorded and section('npc').ambientOnly ~= false then
    local okPop, vpop = pcall(GetEntityPopulationType, entity)
    vpop = okPop and tonumber(vpop) or -1
    if not (vpop == 1 or vpop == 3 or vpop == 4 or vpop == 5) then
      return Utils.fail(L('There is no key on this body'))
    end
  end
  if not wasDriver(entity, ped) then return Utils.fail(L('This person did not drive that vehicle')) end
  if section('npc').ownedVehicles ~= true and ownedPlate(plate) then return Utils.fail(L('There is no key on this body')) end
  local player = pedOf(src)
  if not player or distance(player, ped) > BODY_RANGE then return Utils.fail(L('You are too far away')) end
  busyPeds[ped] = src
  local session = openSession(src, { action = 'deadDriver', entity = entity, netId = netIdOf(entity), plate = plate,
    ped = ped, pedNetId = netIdOf(ped) }, progressWindow(BODY_MS))
  return Utils.ok({ id = session.id, duration = BODY_MS })
end

local function deadDriverFinish(src, session, success)
  local ped = session.ped
  local player = pedOf(src)
  if success and (not player or not isPed(ped) or distance(player, ped) > BODY_RANGE + SLACK) then success = false end
  if not success then return Utils.ok({ success = false }) end
  searchedBodies[ped] = true
  CarLock.grantTemp(src, session.plate, 'robbery')
  log('vehicle.deadDriver', src, { plate = session.plate })
  return Utils.ok({ success = true })
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local ACTIONS = {
  lockpick = { start = lockpickStart, finish = lockpickFinish },
  hotwire = { start = hotwireStart, finish = hotwireFinish },
  search = { start = searchStart, finish = searchFinish },
  rob = { start = robStart, finish = robFinish },
  assist = { start = assistStart, finish = assistFinish },
  deadDriver = { start = deadDriverStart, finish = deadDriverFinish },
}

local function handle(action, source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  local impl = ACTIONS[action]
  if payload.step == 'start' then
    if not NZ.Access.rateLimit(src, 'carlock:crime', 750) then return Utils.fail(L('Please wait a moment')) end
    if not freeForSession(src) then return Utils.fail(L('You are already busy')) end
    return impl.start(src, payload)
  elseif payload.step == 'finish' then
    local session = sessions[src]
    local id = math.tointeger(tonumber(payload.id))
    if not session or session.action ~= action or session.id ~= id or session.finished then return Utils.fail(L('Invalid request')) end
    session.finished = true
    closeSession(session)
    local t = now()
    local success = payload.success == true
    if success and t < session.minAt then
      log('security.crimeTooFast', src, { action = action, plate = session.plate, ms = t - session.startedAt })
      success = false
    end
    if t > session.maxAt then success = false end
    return impl.finish(src, session, success, payload)
  end
  return Utils.fail(L('Invalid request'))
end

local CALLBACKS = {
  lockpick = 'nz:carlock:lockpick', hotwire = 'nz:carlock:hotwire', search = 'nz:carlock:search',
  rob = 'nz:carlock:npcRob', assist = 'nz:carlock:npcAssist', deadDriver = 'nz:carlock:deadDriver',
}
for action, name in pairs(CALLBACKS) do
  lib.callback.register(name, Utils.safe(function(source, payload)
    return handle(action, source, payload)
  end))
end

---------------------------------------------------------------------------------------
-- Access tool items (registered by bridge/server/listeners.lua)
---------------------------------------------------------------------------------------

--- The locked vehicle a used tool is meant for: the nearest one IN FRONT of the player within
--- ITEM_RANGE of its centre (big vehicles BIG_ACCESS_RANGE), nobody alive at the wheel, its
--- profile takes `toolKey`, no key. A car behind the player facing a door or a register (their
--- own car on the driveway ...) leaves the item to its owner script.
local function nearestLockable(src, ped, toolKey)
  local origin = GetEntityCoords(ped)
  local okHeading, heading = pcall(GetEntityHeading, ped)
  local h = math.rad(okHeading and tonumber(heading) or 0.0)
  local fx, fy = -math.sin(h), math.cos(h)
  local bucket = GetPlayerRoutingBucket(tostring(src))
  local best, bestDist = nil, math.huge
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicle(entity) and GetEntityRoutingBucket(entity) == bucket then
      local d = GetEntityCoords(entity) - origin
      local dist = #d
      if dist < bestDist and dist <= BIG_ACCESS_RANGE then
        local big = bigVehicle(entity)
        local flat = math.sqrt(d.x * d.x + d.y * d.y)
        local facing = flat < 0.01 and 1.0 or (d.x * fx + d.y * fy) / flat
        local driver = GetPedInVehicleSeat(entity, -1)
        if dist <= (big and BIG_ACCESS_RANGE or ITEM_RANGE) and facing >= (big and 0.0 or 0.3)
          and not (driver and driver ~= 0 and alive(driver))
          and CarLock.isLocked(entity) and not towing(entity) then
          local _, profile = CarLock.profileOfEntity(entity)
          local plate = accessTool(profile, toolKey) and CarLock.realPlate(entity) or nil
          if plate and not CarLock.hasKey(src, plate) then best, bestDist = entity, dist end
        end
      end
    end
  end
  return best
end

--- A player used a lockpick / screwdriver / hacking device. Starts the lockpick of the locked
--- vehicle in front of them that takes it (or the hack hotwire in the driver seat). False when
--- there is nothing to do, a crime action of theirs is running, or the car lock is off: the
--- item's owner script gets the use then.
---@param src number
---@param item string item name
---@param slot number|nil
---@param metadata table|nil
---@param key string|nil Config.CarLock.items key
---@return boolean handled
function CarLock.useAccessTool(src, item, slot, metadata, key)
  src = validSrc(src)
  if not src or not CarLock.enabled() then return false end
  local open = sessions[src]
  if open and not open.finished and now() <= open.maxAt then return false end
  local toolKey = toolKeyOf(item, key)
  local ped = toolKey and pedOf(src) or nil
  if not ped then return false end
  local current = GetVehiclePedIsIn(ped, false)
  if current and current ~= 0 and isVehicle(current) then
    if GetPedInVehicleSeat(current, -1) ~= ped or towing(current) then return false end
    local _, profile = CarLock.profileOfEntity(current)
    local hotwire = type(profile.hotwire) == 'table' and profile.hotwire or {}
    if hotwire.method ~= 'hack' or CarLock.itemName(hotwire.item or 'hackingDevice') ~= item then return false end
    local plate = CarLock.realPlate(current)
    if not plate or CarLock.hasKey(src, plate) then return false end
    TriggerClientEvent('nz:client:carlock:crime', src, { action = 'hotwire', netId = netIdOf(current), slot = slot })
    return true
  end
  local entity = nearestLockable(src, ped, toolKey)
  if not entity then return false end
  TriggerClientEvent('nz:client:carlock:crime', src, { action = 'lockpick', netId = netIdOf(entity), tool = toolKey, slot = slot })
  return true
end

---------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  src = math.tointeger(src) or src
  local session = sessions[src]
  if session then closeSession(session) end
  cooldowns[src] = nil
  for ped, owner in pairs(busyPeds) do
    if owner == src then busyPeds[ped] = nil end
  end
  for entity, owner in pairs(searching) do
    if owner == src then searching[entity] = nil end
  end
end)

AddEventHandler('entityRemoved', function(entity)
  drivers[entity], searched[entity], searching[entity] = nil, nil, nil
  searchedBodies[entity], busyPeds[entity] = nil, nil
end)
