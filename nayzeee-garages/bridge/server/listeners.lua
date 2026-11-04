--[[
  nayzeee-garages — listener file (server): usable items and compatibility with other key
  scripts. docs/CARLOCK.md §5. Open file: add your own mappings at the bottom.

  1. Usable items: key / fob (toggle the lock), lockpicks / screwdriver / hacking device,
     fake plate, contracts. Each item is registered through NZ.Inventory.registerUsable only
     when its handler exists (other modules add NZ.CarLock.useAccessTool,
     NZ.FakePlates.useItem, NZ.Contracts.useItem); items are never consumed here.

  2. Compatibility (Config.CarLock.enabled + Config.CarLock.compat): many scripts give keys
     with the events / exports of qb-vehiclekeys, qbx_vehiclekeys, wasabi_carlock,
     MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys, vehicles_keys (jaksam) or
     cd_garage. While such a resource is NOT running we answer for it:
       - their server net events (sent by clients): same rules as our own callbacks
         (NZ.CarLock.compatRequest: temporary key only, the player must sit in / stand next
         to the vehicle, never another player's owned car, ambient NPC cars only with
         Config.CarLock.compatAmbient),
       - their server exports (Config.CarLock.compatExports): trusted server code, so they map
         straight to NZ.CarLock.grantTemp / revokeTemp / hasKey / setLocked.
     A resource that starts later takes its names back (our handlers step aside); a key
     resource that turns the built-in car lock off while the server boots silences them all.

  Export shims are '__cfx_export_<resource>_<name>' handlers (how exports are looked up),
  registered when this file loads. Scripts started BEFORE nayzeee-garages that cached a failed
  lookup, and scripts that check GetResourceState('<resource>') first, only see them after a
  restart / with `provide` in fxmanifest.lua (see docs/CARLOCK.md §5).
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local RESOURCE = GetCurrentResourceName()

---------------------------------------------------------------------------------------
-- 1. Usable items
---------------------------------------------------------------------------------------

-- Config.CarLock.items key -> handler NZ[module][fn](src, item, slot, metadata, key), looked up
-- when the item is used (modules of other features may be missing).
-- shared = true: other scripts use the item too (qb-smallresources' lockpick opens houses and
-- stores). On QBCore / Qbox the handler registered before ours is kept and runs whenever ours
-- returns false (no locked vehicle in range); ox_inventory: see install/items/README.md.
local USABLE = {
  { key = 'key', module = 'CarLock', fn = 'useKeyItem' },
  { key = 'fob', module = 'CarLock', fn = 'useKeyItem' },
  { key = 'lockpick', module = 'CarLock', fn = 'useAccessTool', shared = true },
  { key = 'advancedLockpick', module = 'CarLock', fn = 'useAccessTool', shared = true },
  { key = 'screwdriver', module = 'CarLock', fn = 'useAccessTool', shared = true },
  { key = 'hackingDevice', module = 'CarLock', fn = 'useAccessTool', shared = true },
  { key = 'fakePlate', module = 'FakePlates', fn = 'useItem' },
  { key = 'contract', module = 'Contracts', fn = 'useItem' },
  { key = 'signedContract', module = 'Contracts', fn = 'useItem' },
}

local function handlerOf(entry)
  local mod = NZ[entry.module]
  local fn = type(mod) == 'table' and mod[entry.fn] or nil
  return type(fn) == 'function' and fn or nil
end

CreateThread(function()
  local carLockOn = CarLock.enabled()
  local done = {}
  for _, entry in ipairs(USABLE) do
    local item = CarLock.itemName(entry.key)
    -- car lock items only while the built-in car lock runs; other features check their own switch
    if item and not done[item] and handlerOf(entry) and (entry.module ~= 'CarLock' or carLockOn) then
      done[item] = true
      NZ.Inventory.registerUsable(item, function(src, name, slot, metadata)
        local fn = handlerOf(entry)
        if not fn then return false end
        return fn(src, name, slot, metadata, entry.key)
      end, { fallthrough = entry.shared == true })
    end
  end
  -- key items: their metadata only ever comes from the server (no client-made copies)
  if carLockOn and type(NZ.Inventory.protect) == 'function' then
    for _, item in pairs(CarLock.keyItems()) do NZ.Inventory.protect(item) end
  end
end)

---------------------------------------------------------------------------------------
-- 2. Compatibility: who do we answer for?
---------------------------------------------------------------------------------------

local ALIASES = {
  'qb-vehiclekeys', 'qbx_vehiclekeys', 'wasabi_carlock', 'MrNewbVehicleKeys', 'qs-vehiclekeys',
  'Renewed-Vehiclekeys', 'vehicles_keys', 'cd_garage',
}
-- qbx_vehiclekeys answers the qb-vehiclekeys names itself (its bridge)
local ALSO_SERVED_BY = { ['qb-vehiclekeys'] = 'qbx_vehiclekeys' }
-- key resources that turn the built-in car lock off ('auto')
local OTHER_KEYS = {}
for _, name in ipairs(CarLock.otherKeyResources()) do OTHER_KEYS[name] = true end

local on = {}          -- [alias] = true while we answer for it
local exportsOf = {}   -- [alias] = { [name] = fn }
local handles = {}     -- [alias] = { eventData, ... } export shim handlers

local function compatOn()
  return CarLock.compatEnabled()
end

local function exportsOn()
  return compatOn() and CarLock.cfg().compatExports ~= false
end

-- At load our own state is 'starting': 'started' here means the real resource (or another
-- provider of that name) is running.
local function realRunning(alias)
  if GetResourceState(alias) == 'started' then return true end
  local other = ALSO_SERVED_BY[alias]
  return other ~= nil and GetResourceState(other) == 'started'
end

for _, alias in ipairs(ALIASES) do
  on[alias] = compatOn() and not realRunning(alias)
end

local function addShims(alias)
  if not exportsOn() or handles[alias] then return end
  local list = {}
  for name, fn in pairs(exportsOf[alias] or {}) do
    list[#list + 1] = AddEventHandler(('__cfx_export_%s_%s'):format(alias, name), function(setCB)
      setCB(fn)
    end)
  end
  handles[alias] = list
end

local function removeShims(alias)
  for _, h in ipairs(handles[alias] or {}) do RemoveEventHandler(h) end
  handles[alias] = nil
end

--- Register the exports we answer for `alias` (call at load time, before anyone asks).
local function provideExports(alias, map)
  exportsOf[alias] = map
  if on[alias] then addShims(alias) end
end

--- Server net event of another key script, sent by clients (or locally by server scripts:
--- source is not a number then).
local function onEvent(alias, name, fn)
  RegisterNetEvent(name, function(...)
    if not on[alias] then return end
    local src = source
    local ok, err = pcall(fn, src, ...)
    if not ok then Utils.debug(('carlock compat %s failed: %s'):format(name, tostring(err))) end
  end)
end

AddEventHandler('onResourceStart', function(resource)
  if resource == RESOURCE then return end
  -- a key resource starting while the server boots can turn the built-in car lock off
  -- (server/carlock/keys.lua decides in its own handler): then answer for nobody
  if OTHER_KEYS[resource] then
    SetTimeout(0, function()
      if compatOn() then return end
      for alias in pairs(on) do
        on[alias] = false
        removeShims(alias)
      end
    end)
  end
  for alias, other in pairs(ALSO_SERVED_BY) do
    if other == resource then on[alias] = false removeShims(alias) end
  end
  if on[resource] then
    on[resource] = false
    removeShims(resource)
    lib.print.info(('[nayzeee-garages] %s started: its key events / exports are no longer answered by nayzeee-garages'):format(resource))
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == RESOURCE or not compatOn() then return end
  for _, alias in ipairs(ALIASES) do
    if (alias == resource or ALSO_SERVED_BY[alias] == resource) and on[alias] == false then
      -- the stopping resource still reports 'started' / 'stopping' here: check a moment later
      SetTimeout(1000, function()
        if on[alias] == false and not realRunning(alias) then
          on[alias] = true
          addShims(alias)
        end
      end)
    end
  end
end)

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function playerSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

--- Vehicle argument of a server export: an entity handle or a network id (`preferNet`
--- tries the network id first).
local function vehicleArg(value, preferNet)
  local n = tonumber(value)
  if not n or n ~= math.floor(n) or n <= 0 then return nil end
  n = math.tointeger(n)
  local function asNet()
    local ok, e = pcall(NetworkGetEntityFromNetworkId, n)
    return ok and isVehicle(e) and e or nil
  end
  if preferNet then return asNet() or (isVehicle(n) and n or nil) end
  return (isVehicle(n) and n or nil) or asNet()
end

--- Real plate from a plate text (fake plates near the player map to the real one).
local function plateArg(src, plate)
  if type(plate) == 'number' then plate = tostring(math.tointeger(plate) or plate) end
  if type(plate) ~= 'string' or #plate > 16 then return nil end
  return CarLock.plateFromText(plate, src)
end

local function currentVehiclePlate(src)
  local ped = GetPlayerPed(tostring(src))
  local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
  if not isVehicle(vehicle) then return nil end
  return CarLock.realPlate(vehicle)
end

-- Trusted server-side calls (exports): no distance rules, temporary keys.
local function give(src, plate)
  src = playerSrc(src)
  if not src or not plate then return false end
  return CarLock.grantTemp(src, plate, 'compat') == true
end

local function remove(src, plate)
  src = playerSrc(src)
  if not src or not plate then return false end
  CarLock.revokeTemp(src, plate)
  return true
end

local function has(src, plate)
  src = playerSrc(src)
  if not src or not plate then return false end
  return CarLock.hasKey(src, plate) == true
end

local function guarded(name, fn, fallback)
  return function(...)
    local res = table.pack(pcall(fn, ...))
    if not res[1] then
      Utils.debug(('carlock compat export %s failed: %s'):format(name, tostring(res[2])))
      return fallback
    end
    return table.unpack(res, 2, res.n)
  end
end

--- Client-originated request through the shared rules.
local function clientRequest(src, payload, opts)
  src = playerSrc(src)
  if not src then return nil end
  local res = CarLock.compatRequest(src, payload, opts)
  return type(res) == 'table' and res.ok == true and res.data == true
end

---------------------------------------------------------------------------------------
-- qb-vehiclekeys (also the names community scripts / bridges use)
---------------------------------------------------------------------------------------

-- netId (current qb) or plate (older qb, qbx bridge, community_bridge)
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:AcquireVehicleKeys', function(src, arg)
  if type(arg) == 'number' then
    clientRequest(src, { action = 'acquire', netId = arg })
  elseif type(arg) == 'string' then
    clientRequest(src, { action = 'acquire', plate = arg })
  end
end)

-- receiver: a server id or a list of them; the giver must hold the key
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:GiveVehicleKeys', function(src, receiver, plate)
  if type(plate) ~= 'string' or not playerSrc(src) then return end
  if not NZ.Access.rateLimit(src, 'carlock:compat', 400) then return end
  local list = type(receiver) == 'table' and receiver or { receiver }
  for i = 1, math.min(#list, 4) do
    clientRequest(src, { action = 'lend', plate = plate, target = list[i] }, { noRate = true })
  end
end)

local function selfRemove(src, plate)
  if type(plate) == 'string' then clientRequest(src, { action = 'remove', plate = plate }) end
end
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:RemoveVehicleKeys', selfRemove)
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:removeKeys', selfRemove) -- qbx bridge spelling

-- No authorization upstream: here the client needs a key and the lock range; server
-- scripts (local TriggerEvent) are trusted.
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:setVehLockState', function(src, netId, state)
  local locked = tonumber(state) ~= nil and tonumber(state) >= 2
  if type(src) ~= 'number' then
    -- a local TriggerEvent of a server script (source is not a player number)
    local entity = vehicleArg(netId, true)
    if entity then CarLock.setLocked(entity, locked) end
    return
  end
  local client = playerSrc(src)
  if not client then return end
  if not NZ.Access.rateLimit(client, 'carlock:compat', 400) then return end
  local entity, dist, inside = CarLock.vehicleFromNet(client, netId)
  if not entity then return end
  local plate = CarLock.realPlate(entity)
  if not plate or not CarLock.hasKey(client, plate) then return end
  if not inside and (dist or math.huge) > CarLock.lockRangeOf(entity) then return end
  CarLock.setLocked(entity, locked, true)
end)

-- Removes one of the caller's own lockpicks (scripts that let qb-vehiclekeys break them).
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:server:breakLockpick', function(src, itemName)
  src = playerSrc(src)
  if not src or type(itemName) ~= 'string' then return end
  local allowed = { [CarLock.itemName('lockpick')] = true, [CarLock.itemName('advancedLockpick')] = true }
  if not allowed[itemName] or not NZ.Access.rateLimit(src, 'carlock:breakLockpick', 1000) then return end
  NZ.Inventory.removeItem(src, itemName, 1)
end)

provideExports('qb-vehiclekeys', {
  GiveKeys = guarded('qb GiveKeys', function(src, plate)
    plate = plate == nil and currentVehiclePlate(src) or plateArg(src, plate)
    return give(src, plate)
  end, false),
  RemoveKeys = guarded('qb RemoveKeys', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
  HasKeys = guarded('qb HasKeys', function(src, plate) return has(src, plateArg(src, plate)) end, false),
})

-- QBCore callbacks some scripts / libraries query (zyke_lib, qb-vehiclekeys clients).
CreateThread(function()
  if not on['qb-vehiclekeys'] or (NZ.Framework ~= 'qb' and NZ.Framework ~= 'qbx') then return end
  local okCore, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
  -- a function reference of qb-core (a callable table, not a 'function')
  local create = okCore and type(core) == 'table' and core.Functions and core.Functions.CreateCallback or nil
  if create == nil then return end
  pcall(create, 'qb-vehiclekeys:server:GetVehicleKeys', function(source, cb)
    local out = {}
    if on['qb-vehiclekeys'] and NZ.Access.rateLimit(source, 'carlock:qbcb', 1000) then
      for _, key in ipairs(CarLock.keysOf(source) or {}) do out[key.plate] = true end
    end
    cb(out)
  end)
  pcall(create, 'qb-vehiclekeys:server:checkPlayerOwned', function(source, cb, plate)
    if not on['qb-vehiclekeys'] or not NZ.Access.rateLimit(source, 'carlock:qbcbOwned', 1000) then return cb(false) end
    local p = plateArg(source, plate)
    cb(p ~= nil and CarLock.isOwner(source, p) or false)
  end)
end)

---------------------------------------------------------------------------------------
-- qbx_vehiclekeys (Qbox calls these unconditionally: /car, persistence, vehicle shop, police)
---------------------------------------------------------------------------------------

provideExports('qbx_vehiclekeys', {
  -- true when newly given, nil otherwise (qbx contract)
  GiveKeys = guarded('qbx GiveKeys', function(src, vehicle)
    local entity = vehicleArg(vehicle, false)
    local plate = entity and CarLock.realPlate(entity) or nil
    if not plate or not playerSrc(src) then return nil end
    if CarLock.hasKey(src, plate) then return nil end
    return give(src, plate) or nil
  end, nil),
  RemoveKeys = guarded('qbx RemoveKeys', function(src, vehicle)
    local entity = vehicleArg(vehicle, false)
    local plate = entity and CarLock.realPlate(entity) or nil
    if not plate or not playerSrc(src) then return nil end
    return CarLock.revokeTemp(src, plate) or nil
  end, nil),
  HasKeys = guarded('qbx HasKeys', function(src, vehicle)
    local entity = vehicleArg(vehicle, false)
    return has(src, entity and CarLock.realPlate(entity) or nil)
  end, false),
  SetLockState = guarded('qbx SetLockState', function(vehicle, state)
    if state ~= 'lock' and state ~= 'unlock' then return end
    local entity = vehicleArg(vehicle, false)
    if entity then CarLock.setLocked(entity, state == 'lock') end
  end, nil),
  IsPlayerNearVehicle = guarded('qbx IsPlayerNearVehicle', function(src, vehicle)
    local entity = vehicleArg(vehicle, false)
    src = playerSrc(src)
    if not entity or not src then return false end
    local ped = GetPlayerPed(tostring(src))
    if GetVehiclePedIsIn(ped, false) == entity then return true end
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= CarLock.range('compat')
  end, false),
})

---------------------------------------------------------------------------------------
-- wasabi_carlock, MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys
---------------------------------------------------------------------------------------

provideExports('wasabi_carlock', {
  GiveKey = guarded('wasabi GiveKey', function(src, plate) return give(src, plateArg(src, plate)) end, false),
  RemoveKey = guarded('wasabi RemoveKey', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
  HasKey = guarded('wasabi HasKey', function(src, plate) return has(src, plateArg(src, plate)) end, false),
})

local function plateOfNet(netId)
  local entity = vehicleArg(netId, true)
  return entity and CarLock.realPlate(entity) or nil
end

provideExports('MrNewbVehicleKeys', {
  GiveKeysByPlate = guarded('MrNewb GiveKeysByPlate', function(src, plate) return give(src, plateArg(src, plate)) end, false),
  RemoveKeysByPlate = guarded('MrNewb RemoveKeysByPlate', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
  HasKeysByPlate = guarded('MrNewb HasKeysByPlate', function(src, plate) return has(src, plateArg(src, plate)) end, false),
  GiveKeys = guarded('MrNewb GiveKeys', function(src, netId) return give(src, plateOfNet(netId)) end, false),
  RemoveKeys = guarded('MrNewb RemoveKeys', function(src, netId) return remove(src, plateOfNet(netId)) end, false),
  HaveKeys = guarded('MrNewb HaveKeys', function(src, netId) return has(src, plateOfNet(netId)) end, false),
})

provideExports('qs-vehiclekeys', {
  GiveServerKeys = guarded('qs GiveServerKeys', function(src, plate) return give(src, plateArg(src, plate)) end, false),
  RemoveServerKeys = guarded('qs RemoveServerKeys', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
})

provideExports('Renewed-Vehiclekeys', {
  addKey = guarded('Renewed addKey', function(src, plate) return give(src, plateArg(src, plate)) end, false),
  removeKey = guarded('Renewed removeKey', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
  hasKey = guarded('Renewed hasKey', function(src, plate) return has(src, plateArg(src, plate)) end, false),
})

---------------------------------------------------------------------------------------
-- vehicles_keys (jaksam)
---------------------------------------------------------------------------------------

onEvent('vehicles_keys', 'vehicles_keys:selfGiveVehicleKeys', function(src, plate)
  if type(plate) == 'string' then clientRequest(src, { action = 'acquire', plate = plate }) end
end)

onEvent('vehicles_keys', 'vehicles_keys:selfGiveCurrentVehicleKeys', function(src)
  src = playerSrc(src)
  if not src then return end
  local ped = GetPlayerPed(tostring(src))
  local vehicle = GetVehiclePedIsIn(ped, false)
  if not isVehicle(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
  clientRequest(src, { action = 'acquire', netId = NetworkGetNetworkIdFromEntity(vehicle) })
end)

onEvent('vehicles_keys', 'vehicles_keys:selfRemoveKeys', selfRemove)

provideExports('vehicles_keys', {
  giveVehicleKeysToPlayerId = guarded('jaksam give', function(src, plate) return give(src, plateArg(src, plate)) end, false),
  removeKeysFromPlayerId = guarded('jaksam remove', function(src, plate) return remove(src, plateArg(src, plate)) end, false),
  giveVehicleKeysToIdentifier = guarded('jaksam giveIdentifier', function(identifier, plate)
    if type(identifier) ~= 'string' then return false end
    local ok, src = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
    return ok and give(src, plateArg(src, plate)) or false
  end, false),
  removeKeysFromIdentifier = guarded('jaksam removeIdentifier', function(identifier, plate)
    plate = Utils.plate(plate)
    if type(identifier) ~= 'string' or not plate then return false end
    CarLock.revokeTemp(identifier, plate)
    return true
  end, false),
  isPlayerOwnerOfVehiclePlate = guarded('jaksam isOwner', function(src, plate)
    plate = plateArg(src, plate)
    return plate ~= nil and playerSrc(src) ~= nil and CarLock.isOwner(src, plate)
  end, false),
  -- vehicle shops call this after a purchase so the buyer's key list is fresh
  refreshPlayerOwnedVehicles = guarded('jaksam refreshPlayerOwnedVehicles', function(src)
    src = playerSrc(src)
    if not src then return false end
    -- a vehicle row was just written (plate unknown): forget the cached rows / versions
    if type(CarLock.invalidate) == 'function' then CarLock.invalidate(nil) end
    TriggerClientEvent('nz:client:carlock:keys', src, {})
    return true
  end, false),
  getIdentifierKeys = guarded('jaksam getIdentifierKeys', function(identifier)
    local out = {}
    if type(identifier) ~= 'string' or identifier == '' or #identifier > 64 then return out end
    if CarLock.mode() == 'virtual' and NZ.DB.keys and type(NZ.DB.keys.forIdentifier) == 'function' then
      for _, plate in ipairs(NZ.DB.keys.forIdentifier(identifier) or {}) do out[plate] = { type = 'temporary' } end
    end
    return out
  end, {}),
  getPlayerIdKeys = guarded('jaksam getPlayerIdKeys', function(src)
    local out = {}
    if not playerSrc(src) then return out end
    for _, key in ipairs(CarLock.keysOf(src) or {}) do
      out[key.plate] = { type = key.kind == 'owner' and 'owned' or 'temporary', model = key.model }
    end
    return out
  end, {}),
})

---------------------------------------------------------------------------------------
-- Your own mappings: onEvent('<alias of ALIASES>', '<event>', function(src, ...) end) for
-- client-sent events (use clientRequest for the rules), provideExports('<alias>', { ... }).
---------------------------------------------------------------------------------------
