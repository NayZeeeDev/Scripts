--[[
  nayzeee-garages — housing integration (server): NZ.Housing.

  House garages are runtime-only locations (NZ.Locations.registerHouse, garage key
  'H' .. houseId). This module
    - loads them from qb-houses (houselocations + player_houses) and ps-housing
      (properties) when those resources run and Config.Integrations.housing allows it,
      refreshing every 5 minutes and when a client asks ('nz:housing:refresh');
    - backs the RegisterHouseGarage / RemoveHouseGarage / SetHouseAccess exports;
    - keeps who may use each house garage (owners + key holders) and answers
      hasAccess / viewsFor;
    - pushes 'nz:client:houses' (list of client views) to online players whose house
      garages changed.
  House ids from the built-in loaders are 'qb:<house name>' and 'ps:<property id>'.
]]

local Housing = NZ.Housing
local Utils = NZ.Utils

local REFRESH_MS = 5 * 60 * 1000   -- periodic reload of the housing tables
local MIN_RELOAD_MS = 10000        -- reloads requested by clients are throttled globally
local PUSH_DELAY_MS = 500          -- coalesce change pushes
local LOAD_WAIT_MS = 10000         -- max wait for a reload already running
local CLIENT_RATE_MS = 2000        -- per player rate limit of the refresh callback
local MAX_ACCESS = 200             -- identifiers per house and per access source
local MAX_ID_LENGTH = 60

local registry = {}       -- [houseId] = { source = 'qb'|'ps'|'export', sig = string, name = string }
local loaderAccess = {}   -- [houseId] = { [identifier] = true } (from qb-houses / ps-housing)
local exportAccess = {}   -- [houseId] = { [identifier] = true } (from SetHouseAccess)
local index = {}          -- [identifier] = { [houseId] = true } (union of both access sources)
local dirty = {}          -- [identifier] = true, players whose house list must be re-sent
local lastSent = {}       -- [src] = fingerprint of the last 'nz:client:houses' push

local booted = false
local loading = false
local lastLoadAt = nil
local trailingReload = false
local pushScheduled = false

---------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------

--- House id normalisation; mirrors NZ.Locations so both modules use the same strings.
---@param value string|number
---@return string|nil
local function canonicalId(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    value = tostring(math.tointeger(value) or value)
  end
  if type(value) ~= 'string' then return nil end
  local s = Utils.cleanText(value, MAX_ID_LENGTH)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

--- Resolve an id that may carry the 'H' garage-key prefix.
local function knownId(value)
  local id = canonicalId(value)
  if not id then return nil end
  if registry[id] or loaderAccess[id] or exportAccess[id] then return id end
  if id:sub(1, 1) == 'H' and #id > 1 then
    local stripped = id:sub(2)
    if registry[stripped] or loaderAccess[stripped] or exportAccess[stripped] then return stripped end
  end
  return id
end

local function cleanIdentifier(value)
  if type(value) == 'number' then value = tostring(math.tointeger(value) or value) end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' or #s > 64 or s:find('%c') then return nil end
  return s
end

local function decodeJson(value)
  if type(value) == 'table' then return value end
  if type(value) ~= 'string' or value == '' or value == 'null' then return nil end
  local ok, res = pcall(json.decode, value)
  if ok and type(res) == 'table' then return res end
  return nil
end

--- Identifier set from a JSON list (strings or { citizenid / identifier = ... } entries).
local function addIdentifiers(set, list)
  local decoded = decodeJson(list)
  if not decoded then return end
  local count = 0
  for _, entry in pairs(decoded) do
    if count >= MAX_ACCESS then break end
    local id
    if type(entry) == 'table' then
      id = cleanIdentifier(entry.citizenid or entry.identifier or entry.cid)
    else
      id = cleanIdentifier(entry)
    end
    if id and not set[id] then
      set[id] = true
      count = count + 1
    end
  end
end

local function round(n)
  return ('%.2f'):format(tonumber(n) or 0)
end

local function coordSig(v)
  if not v then return '-' end
  return table.concat({ round(v.x), round(v.y), round(v.z), round(v.w) }, ',')
end

local function registrationSig(name, coords, spawn)
  return table.concat({ tostring(name or ''), coordSig(coords), coordSig(spawn) }, '|')
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function housingMode()
  local mode = Config.Integrations and Config.Integrations.housing or 'auto'
  if type(mode) ~= 'string' or mode == '' then return 'auto' end
  return mode
end

---------------------------------------------------------------------------------------
-- Access index
---------------------------------------------------------------------------------------

local function effectiveAccess(id)
  local out = {}
  local a, b = loaderAccess[id], exportAccess[id]
  if a then for identifier in pairs(a) do out[identifier] = true end end
  if b then for identifier in pairs(b) do out[identifier] = true end end
  return out
end

--- Update the identifier index after the access of one house changed.
local function reindex(id, before, after)
  for identifier in pairs(before) do
    if not after[identifier] then
      local set = index[identifier]
      if set then
        set[id] = nil
        if next(set) == nil then index[identifier] = nil end
      end
      dirty[identifier] = true
    end
  end
  for identifier in pairs(after) do
    if not before[identifier] then
      local set = index[identifier]
      if not set then
        set = {}
        index[identifier] = set
      end
      set[id] = true
      dirty[identifier] = true
    end
  end
end

local function sameSet(a, b)
  a, b = a or {}, b or {}
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

local function setAccessSource(store, id, set)
  if set and next(set) == nil then set = nil end
  if sameSet(store[id], set) then return end
  local before = effectiveAccess(id)
  store[id] = set
  reindex(id, before, effectiveAccess(id))
end

local function markHouseDirty(id)
  for identifier in pairs(effectiveAccess(id)) do dirty[identifier] = true end
end

---------------------------------------------------------------------------------------
-- Pushing house lists to players
---------------------------------------------------------------------------------------

local function viewsFingerprint(views)
  local parts = {}
  for i = 1, #views do
    local view = views[i]
    local rec = registry[view.houseId or '']
    parts[#parts + 1] = tostring(view.id) .. '=' .. (rec and rec.sig or tostring(view.name))
  end
  return table.concat(parts, ';')
end

local function pushTo(src, identifier)
  local views = Housing.viewsFor(identifier)
  local fp = viewsFingerprint(views)
  if lastSent[src] == fp then return end
  lastSent[src] = fp
  TriggerClientEvent('nz:client:houses', src, views)
end

local function flushPush()
  pushScheduled = false
  if next(dirty) == nil then return end
  local targets = dirty
  dirty = {}
  -- During boot server/main.lua sends every player its full list (incl. houses).
  if NZ.Ready == false then return end
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    local identifier = src and identifierOf(src)
    if identifier and targets[identifier] then
      local ok, err = pcall(pushTo, src, identifier)
      if not ok then lib.print.warn(('housing: push to %s failed: %s'):format(id, tostring(err))) end
    end
  end
end

local function schedulePush()
  if pushScheduled or next(dirty) == nil then return end
  pushScheduled = true
  SetTimeout(PUSH_DELAY_MS, flushPush)
end

---------------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------------

--- Register / update one house garage. Returns the canonical id or nil, error.
local function registerInternal(id, data, source)
  local coords = Utils.v4(data.coords)
  if not coords then return nil, L('Invalid house coordinates') end
  local spawn = data.spawn ~= nil and Utils.v4(data.spawn) or nil
  local name = type(data.name) == 'string' and data.name or nil
  local sig = registrationSig(name, coords, spawn)

  local rec = registry[id]
  if rec and rec.sig == sig and NZ.Locations.get(Utils.key.house(id)) then
    rec.source = source
    return id
  end

  local loc, err = NZ.Locations.registerHouse(id, { name = name, coords = coords, spawn = spawn })
  if type(loc) ~= 'table' then return nil, err or L('Invalid house data') end
  local canonical = type(loc.houseId) == 'string' and loc.houseId or id
  if canonical ~= id then
    -- Should not happen (same normalisation), but never lose track of a registration.
    registry[id] = nil
  end
  registry[canonical] = { source = source, sig = sig, name = loc.name }
  markHouseDirty(canonical)
  return canonical
end

local function removeInternal(id)
  if not registry[id] then return false end
  markHouseDirty(id)
  registry[id] = nil
  NZ.Locations.removeHouse(id)
  setAccessSource(loaderAccess, id, nil)
  return true
end

---------------------------------------------------------------------------------------
-- Loaders (qb-houses / ps-housing)
---------------------------------------------------------------------------------------

local function query(sql, params)
  local ok, rows = pcall(MySQL.query.await, sql, params or {})
  if not ok then
    Utils.debug('housing: query failed:', tostring(rows))
    return nil
  end
  if type(rows) ~= 'table' then return nil end
  return rows
end

--- Garage coordinates from a housing JSON column ({x,y,z,w|h} or { takeVehicle = {...} }).
local function garageCoords(value)
  local decoded = decodeJson(value)
  if not decoded then return nil end
  local v = Utils.v4(decoded)
  if v then return v end
  for _, key in ipairs({ 'takeVehicle', 'coords', 'spawn' }) do
    if type(decoded[key]) == 'table' then
      v = Utils.v4(decoded[key])
      if v then return v end
    end
  end
  return nil
end

local function loaderId(prefix, value)
  if type(value) == 'number' then value = tostring(math.tointeger(value) or value) end
  if type(value) ~= 'string' then return nil end
  local raw = Utils.cleanText(value, MAX_ID_LENGTH - #prefix)
  if not raw then return nil end
  return canonicalId(prefix .. raw)
end

local LOADERS = {
  {
    source = 'qb',
    resource = 'qb-houses',
    --- qb-houses: houselocations (name, label, garage JSON) + player_houses (house, citizenid, keyholders JSON).
    load = function(found)
      local houses = query("SELECT `name`, `label`, `garage` FROM `houselocations` WHERE `garage` IS NOT NULL AND `garage` <> ''")
      if not houses then return false end
      local owners = query('SELECT `house`, `citizenid`, `keyholders` FROM `player_houses`')
      if not owners then return false end

      local access = {}
      for _, row in ipairs(owners) do
        local house = type(row.house) == 'string' and row.house or nil
        if house then
          local set = access[house]
          if not set then
            set = {}
            access[house] = set
          end
          local owner = cleanIdentifier(row.citizenid)
          if owner then set[owner] = true end
          addIdentifiers(set, row.keyholders)
        end
      end

      for _, row in ipairs(houses) do
        local coords = garageCoords(row.garage)
        local id = coords and loaderId('qb:', row.name)
        if id then
          local label = Utils.cleanText(row.label, 60) or Utils.cleanText(row.name, 60)
          found[id] = { source = 'qb', name = label, coords = coords, access = access[row.name] or {} }
        end
      end
      return true
    end,
  },
  {
    source = 'ps',
    resource = 'ps-housing',
    --- ps-housing: properties (property_id, owner_citizenid, has_access JSON, garage_data JSON, street).
    load = function(found)
      local rows = query('SELECT `property_id`, `owner_citizenid`, `has_access`, `garage_data`, `street` FROM `properties` WHERE `garage_data` IS NOT NULL')
      if not rows then return false end
      for _, row in ipairs(rows) do
        local coords = garageCoords(row.garage_data)
        local propertyId = tonumber(row.property_id)
        local id = coords and propertyId and loaderId('ps:', propertyId)
        if id then
          local set = {}
          local owner = cleanIdentifier(row.owner_citizenid)
          if owner then set[owner] = true end
          addIdentifiers(set, row.has_access)
          local street = Utils.cleanText(row.street, 50) or L('Property')
          found[id] = {
            source = 'ps',
            name = ('%s %s'):format(street, tostring(math.tointeger(propertyId) or propertyId)),
            coords = coords,
            access = set,
          }
        end
      end
      return true
    end,
  },
}

local function loaderEnabled(loader, mode)
  if mode == 'none' then return false end
  if mode ~= 'auto' and mode ~= loader.resource then return false end
  return Utils.resourceStarted(loader.resource)
end

--- Reload every enabled loader and apply the differences.
local function doReload()
  local mode = housingMode()
  local found, loaded = {}, {}
  for i = 1, #LOADERS do
    local loader = LOADERS[i]
    if loaderEnabled(loader, mode) then
      local ok, res = pcall(loader.load, found)
      if ok and res == true then
        loaded[loader.source] = true
      else
        lib.print.warn(('housing: could not read %s data%s'):format(loader.resource,
          ok and '' or (': ' .. tostring(res))))
      end
    end
  end

  local seen, count = {}, 0
  for id, entry in pairs(found) do
    local rec = registry[id]
    if rec and rec.source == 'export' then
      -- An export registration wins over the loader position; keep its access current.
      seen[id] = true
      setAccessSource(loaderAccess, id, entry.access)
    else
      local canonical, err = registerInternal(id, entry, entry.source)
      if canonical then
        seen[canonical] = true
        count = count + 1
        setAccessSource(loaderAccess, canonical, entry.access)
      else
        Utils.debug(('housing: skipped %s: %s'):format(id, tostring(err)))
      end
    end
  end

  -- Houses that disappeared from a loader that read its data successfully.
  for id, rec in pairs(registry) do
    if rec.source ~= 'export' and loaded[rec.source] and not seen[id] then
      removeInternal(id)
    end
  end
  return count
end

local function reload()
  if loading then return false end
  loading = true
  local ok, res = pcall(doReload)
  loading = false
  lastLoadAt = GetGameTimer()
  if not ok then
    lib.print.error(('housing: reload failed: %s'):format(tostring(res)))
    return false
  end
  Utils.debug(('housing: %d loader house garages'):format(res))
  schedulePush()
  return true
end

--- Reload now when allowed, otherwise schedule one trailing reload.
---@param wait boolean wait for the reload (or one already running) to finish
local function requestReload(wait)
  if loading then
    if wait then
      local deadline = GetGameTimer() + LOAD_WAIT_MS
      while loading and GetGameTimer() < deadline do Wait(50) end
    end
    return
  end
  local now = GetGameTimer()
  local since = lastLoadAt and (now - lastLoadAt) or math.huge
  if since >= MIN_RELOAD_MS then
    if wait then
      reload()
    else
      CreateThread(reload)
    end
    return
  end
  if trailingReload then return end
  trailingReload = true
  SetTimeout(MIN_RELOAD_MS - since, function()
    trailingReload = false
    reload()
  end)
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Load house garages from the supported housing resources and start the periodic refresh.
--- Called once by server/main.lua during boot (inside a thread).
function Housing.boot()
  if booted then return end
  booted = true
  reload()
  -- server/main.lua syncs every online player right after boot (houses included).
  dirty = {}
  lastSent = {}
  local count = 0
  for _ in pairs(registry) do count = count + 1 end
  if count > 0 or housingMode() ~= 'none' then
    lib.print.info(('housing: %d house garage(s) loaded'):format(count))
  end
  CreateThread(function()
    while true do
      Wait(REFRESH_MS)
      local ok, err = pcall(requestReload, true)
      if not ok then lib.print.warn(('housing: periodic refresh failed: %s'):format(tostring(err))) end
    end
  end)
end

--- Ask for a reload of the housing data (throttled; runs asynchronously).
function Housing.refresh()
  requestReload(false)
end

--- May this identifier use the garage of this house?
---@param identifier string
---@param houseId string|number house id (with or without the 'H' key prefix)
---@return boolean
function Housing.hasAccess(identifier, houseId)
  if type(identifier) ~= 'string' or identifier == '' then return false end
  local id = knownId(houseId)
  if not id then return false end
  local a, b = loaderAccess[id], exportAccess[id]
  return (a ~= nil and a[identifier] == true) or (b ~= nil and b[identifier] == true)
end

--- Client views (NZ.Locations.clientView) of every house garage this identifier may use.
---@param identifier string
---@return table[] views sorted by id
function Housing.viewsFor(identifier)
  local views = {}
  if type(identifier) ~= 'string' then return views end
  local set = index[identifier]
  if not set then return views end
  local ids = {}
  for id in pairs(set) do
    if registry[id] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for i = 1, #ids do
    local loc = NZ.Locations.get(Utils.key.house(ids[i]))
    if loc then
      local view = NZ.Locations.clientView(loc)
      if view then views[#views + 1] = view end
    end
  end
  return views
end

--- Register (or move / rename) a house garage. Backs the RegisterHouseGarage export.
---@param houseId string|number
---@param data table { name, coords = vec4, spawn = vec4|nil }
---@return boolean ok, string|nil error (translated)
function Housing.register(houseId, data)
  local id = canonicalId(houseId)
  if not id then return false, L('Invalid house id') end
  if type(data) ~= 'table' then return false, L('Invalid house data') end
  local canonical, err = registerInternal(id, data, 'export')
  if not canonical then return false, err end
  schedulePush()
  return true
end

--- Remove a house garage. Vehicles stored there keep their 'H..' garage key.
---@param houseId string|number
---@return boolean ok
function Housing.remove(houseId)
  local id = knownId(houseId)
  if not id then return false, L('Invalid house id') end
  if not removeInternal(id) then NZ.Locations.removeHouse(id) end
  schedulePush()
  return true
end

--- Replace the identifiers allowed to use a house garage (owner + key holders). Merged with
--- what the built-in loaders know. May be called before RegisterHouseGarage.
---@param houseId string|number
---@param identifiers string[]
---@return boolean ok, string|nil error (translated)
function Housing.setAccess(houseId, identifiers)
  local id = knownId(houseId)
  if not id then return false, L('Invalid house id') end
  if type(identifiers) ~= 'table' then return false, L('Invalid identifier list') end
  local set, count = {}, 0
  for _, value in pairs(identifiers) do
    if count >= MAX_ACCESS then break end
    local identifier = cleanIdentifier(value)
    if identifier and not set[identifier] then
      set[identifier] = true
      count = count + 1
    end
  end
  setAccessSource(exportAccess, id, set)
  schedulePush()
  return true
end

--- Player cleanup (called by server/main.lua through the onPlayerDropped hook).
---@param src number
function Housing.onPlayerDropped(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end

-- A (re)loaded character gets its full list from server-core: forget what we pushed.
AddEventHandler('nz:server:playerLoaded', function(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end)

AddEventHandler('nz:server:playerUnloaded', function(src)
  src = tonumber(src)
  if src then lastSent[src] = nil end
end)

---------------------------------------------------------------------------------------
-- Callback
---------------------------------------------------------------------------------------

lib.callback.register('nz:housing:refresh', Utils.safe(function(source)
  local src = tonumber(source)
  if not src or src <= 0 then return Utils.fail(L('Invalid request')) end
  if not booted or NZ.Ready == false then return Utils.fail(L('Garages are still loading')) end

  if NZ.Access.rateLimit(src, 'housing:refresh', CLIENT_RATE_MS) then
    requestReload(true)
  else
    requestReload(false)
  end

  local identifier = identifierOf(src)
  if not identifier then return Utils.ok({}) end
  local views = Housing.viewsFor(identifier)
  lastSent[src] = viewsFingerprint(views)
  return Utils.ok(views)
end))
