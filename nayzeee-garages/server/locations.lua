--[[
  nayzeee-garages — garage locations (NZ.Locations), server side.

  Caches every row of `nz_locations` as a normalized Location (docs/ARCHITECTURE.md §4.2),
  keeps runtime-only house garages in a separate cache ('H' .. houseId), builds the views
  clients receive ('nz:client:locations'), resolves garage keys (L / G / H) and computes
  capacity. Cached tables are shared: callers must treat them as read-only.
]]

local Locations = NZ.Locations
local Utils = NZ.Utils

local cache = {}          -- [id:number] = Location
local houses = {}         -- ['H' .. houseId] = house Location
local broadcastPending = false

local BROADCAST_DELAY = 250   -- ms: coalesces bursts of changes (imports, bulk edits)
local MAX_MONEY = 10000000
local MAX_GARAGE_PRICE = 100000000

local LIMITS = {
  spawnPoints = 64,
  points = 16,
  rules = 20,
  spawner = 60,
  identifiers = 200,
  grades = 50,
  extras = 32,
}

local KINDS = { garage = true, job = true, private = true, impound = true }
local GARAGE_SOURCES = { personal = true, spawner = true }
local JOB_SOURCES = { owned = true, spawner = true }
local JOB_OWNERS = { job = true, gang = true }
local STORAGE_MODES = { shared = true, personal = true }
local CAPACITY_MODES = { unlimited = true, limited = true }
local CAPACITY_SCOPES = { player = true, total = true }
local ACCESS_MODES = { quick = true, interior = true, both = true }
local RESTRICTION_TYPES = { everyone = true, job = true, gang = true, identifier = true }
local INTERACTION_MODES = { default = true, prompt = true, target = true, both = true }
local DEFAULT_PED_MODEL = 's_m_y_valet_01'
local DEFAULT_PED_SCENARIO = 'WORLD_HUMAN_CLIPBOARD'

local BLIP_SPRITES = { car = 357, sea = 356, air = 359 }
local BLIP_COLOURS = { garage = 3, job = 38, private = 5, impound = 1 }
local IMPOUND_SPRITE = 68

---------------------------------------------------------------------------------------
-- Sanitizers
---------------------------------------------------------------------------------------

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('locations: log "%s" failed: %s'):format(event, tostring(err))) end
end

--- Clean text and drop a truncated trailing UTF-8 sequence.
local function safeText(value, maxLen)
  local s = Utils.cleanText(value, maxLen)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

local function deepEqual(a, b)
  if a == b then return true end
  if type(a) ~= 'table' or type(b) ~= 'table' then return false end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function bool(value, default)
  if type(value) == 'boolean' then return value end
  if value == 1 then return true end
  if value == 0 then return false end
  return default
end

local function enum(value, allowed, default)
  if type(value) == 'string' and allowed[value] then return value end
  return default
end

local function num(value, min, max, default, integer)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not n or n ~= n or n == math.huge or n == -math.huge then return default end
  if n < min then n = min elseif n > max then n = max end
  if integer then n = math.floor(n) end
  return n
end

--- Positive integer id (database ids, net ids) or nil. Never clamps: 0 / -1 / 1.5 are invalid.
local function positiveId(value)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not n or n ~= n or n < 1 or n > 2147483647 or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

local function coordOk(n, limit)
  return type(n) == 'number' and n == n and n > -limit and n < limit
end

local function vec3(value)
  local v = Utils.v3(value)
  if not v then return nil end
  if not (coordOk(v.x, 20000) and coordOk(v.y, 20000) and coordOk(v.z, 5000)) then return nil end
  return { x = Utils.round(v.x, 3), y = Utils.round(v.y, 3), z = Utils.round(v.z, 3) }
end

local function vec4(value)
  local v = Utils.v4(value)
  if not v then return nil end
  if not (coordOk(v.x, 20000) and coordOk(v.y, 20000) and coordOk(v.z, 5000)) then return nil end
  local w = v.w
  if not coordOk(w, 1e6) then w = 0.0 end
  w = w % 360.0
  return { x = Utils.round(v.x, 3), y = Utils.round(v.y, 3), z = Utils.round(v.z, 3), w = Utils.round(w, 2) }
end

local function isVector(value)
  local t = type(value)
  return t == 'vector3' or t == 'vector4'
end

local function vec4List(list, maxCount)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, item in ipairs(list) do
    if #out >= maxCount then break end
    local v = vec4(item)
    if v then out[#out + 1] = v end
  end
  return out
end

--- Interaction points: { coords = {x,y,z}, radius } (plain vectors are accepted too).
local function pointList(list, maxCount, defaultRadius)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, item in ipairs(list) do
    if #out >= maxCount then break end
    local coords, radius
    if type(item) == 'table' and item.coords ~= nil then
      coords, radius = vec3(item.coords), item.radius
    elseif type(item) == 'table' or isVector(item) then
      coords = vec3(item)
      radius = type(item) == 'table' and item.radius or nil
    end
    if coords then
      out[#out + 1] = { coords = coords, radius = Utils.round(num(radius, 0.5, 25.0, defaultRadius), 2) }
    end
  end
  return out
end

local function jobRules(list)
  local out, seen = {}, {}
  if type(list) ~= 'table' then return out end
  for _, rule in ipairs(list) do
    if #out >= LIMITS.rules then break end
    local name, minGrade
    if type(rule) == 'string' then
      name = rule
    elseif type(rule) == 'table' then
      name, minGrade = rule.name, rule.minGrade
    end
    name = safeText(name, 64)
    if name and not seen[name] then
      seen[name] = true
      out[#out + 1] = { name = name, minGrade = num(minGrade, 0, 1000, 0, true) }
    end
  end
  return out
end

local function plateTemplate(value)
  if type(value) ~= 'string' then return '' end
  local t = Utils.trim(value):upper():gsub('[^%w#@%* ]', '')
  if #t > 8 then t = t:sub(1, 8) end
  return Utils.trim(t)
end

local function spawnerEntry(entry)
  if type(entry) ~= 'table' or type(entry.model) ~= 'string' then return nil end
  local model = Utils.trim(entry.model)
  if #model == 0 or #model > 32 or not model:match('^[%w_%-]+$') then return nil end

  local grades, seenGrade = {}, {}
  if type(entry.grades) == 'table' then
    for _, g in ipairs(entry.grades) do
      if #grades >= LIMITS.grades then break end
      local n = num(g, 0, 1000, nil, true)
      if n and not seenGrade[n] then
        seenGrade[n] = true
        grades[#grades + 1] = n
      end
    end
    table.sort(grades)
  end

  local extras, count = {}, 0
  if type(entry.extras) == 'table' then
    for k, v in pairs(entry.extras) do
      if count >= LIMITS.extras then break end
      local id = num(k, -1, 1000, nil, true)
      if id and id >= 0 and id <= 30 and type(v) == 'boolean' then
        local key = tostring(id)
        if extras[key] == nil then count = count + 1 end
        extras[key] = v
      end
    end
  end

  return {
    model = model,
    label = safeText(entry.label, 60) or '',
    plate = plateTemplate(entry.plate),
    grades = grades,
    livery = num(entry.livery, -1, 1000, -1, true),
    extras = extras,
    maxMods = entry.maxMods == true,
    price = num(entry.price, 0, MAX_MONEY, 0, true),
  }
end

local function spawnerList(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, entry in ipairs(list) do
    if #out >= LIMITS.spawner then break end
    local clean = spawnerEntry(entry)
    if clean then out[#out + 1] = clean end
  end
  return out
end

local function capacityConfig(value)
  value = type(value) == 'table' and value or {}
  return {
    mode = enum(value.mode, CAPACITY_MODES, 'unlimited'),
    appliesTo = enum(value.appliesTo, CAPACITY_SCOPES, 'player'),
    spaces = num(value.spaces, 1, 1000, 8, true),
  }
end

local function accessConfig(value)
  value = type(value) == 'table' and value or {}
  local interiorId = positiveId(value.interiorId)
  local mode = enum(value.mode, ACCESS_MODES, 'quick')
  -- An interior mode without an interior cannot work: fall back to the quick menu.
  if not interiorId then mode = 'quick' end
  return { mode = mode, interiorId = interiorId }
end

local function restrictionConfig(value)
  value = type(value) == 'table' and value or {}
  local identifiers, seen = {}, {}
  if type(value.identifiers) == 'table' then
    for _, identifier in ipairs(value.identifiers) do
      if #identifiers >= LIMITS.identifiers then break end
      local s = safeText(identifier, 64)
      if s and not seen[s] then
        seen[s] = true
        identifiers[#identifiers + 1] = s
      end
    end
  end
  return {
    type = enum(value.type, RESTRICTION_TYPES, 'everyone'),
    rules = jobRules(value.rules),
    identifiers = identifiers,
  }
end

local function blipConfig(value, kind, vehicleType)
  value = type(value) == 'table' and value or {}
  local sprite = kind == 'impound' and IMPOUND_SPRITE or (BLIP_SPRITES[vehicleType] or BLIP_SPRITES.car)
  return {
    enabled = bool(value.enabled, true),
    sprite = num(value.sprite, 1, 1000, sprite, true),
    color = num(value.color, 0, 85, BLIP_COLOURS[kind] or 3, true),
    scale = Utils.round(num(value.scale, 0.1, 2.0, 0.7), 2),
  }
end

--- Ped model name (^[%w_]+$, max 32): nil / '' = Config.Peds.defaultModel, invalid = nil.
local function pedModel(value)
  local default = type(Config.Peds) == 'table' and Config.Peds.defaultModel or nil
  if type(default) ~= 'string' or #default > 32 or not default:match('^[%w_]+$') then default = DEFAULT_PED_MODEL end
  if value == nil then return default end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' then return default end
  if #s > 32 or not s:match('^[%w_]+$') then return nil end
  return s
end

--- Scenario name (^[%w_]*$, max 64, '' = none): nil = Config.Peds.defaultScenario, invalid = nil.
local function pedScenario(value)
  local default = type(Config.Peds) == 'table' and Config.Peds.defaultScenario or nil
  if type(default) ~= 'string' or #default > 64 or not default:match('^[%w_]*$') then default = DEFAULT_PED_SCENARIO end
  if value == nil then return default end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if #s > 64 or not s:match('^[%w_]*$') then return nil end
  return s
end

--- Per-location interaction override: { mode, ped = { model, scenario } | nil }. Anything
--- invalid falls back to the defaults (nil = follow settings.interface.interaction, no NPC),
--- so locations saved before this field existed keep working unchanged.
local function interactionConfig(value)
  if type(value) ~= 'table' then return nil end
  local mode = enum(value.mode, INTERACTION_MODES, 'default')
  local ped = nil
  -- an empty table ([] / {} after a JSON round trip) is "no NPC", not "default NPC"
  if type(value.ped) == 'table' and next(value.ped) ~= nil then
    local model, scenario = pedModel(value.ped.model), pedScenario(value.ped.scenario)
    if model and scenario then ped = { model = model, scenario = scenario } end
  end
  if mode == 'default' and not ped then return nil end
  return { mode = mode, ped = ped }
end

local function societyName(value)
  if type(value) ~= 'string' then return '' end
  local s = Utils.trim(value):gsub('[^%w_%-]', '')
  if #s > 64 then s = s:sub(1, 64) end
  return s
end

local function openRadius()
  return num(Config.Interaction and Config.Interaction.openRadius, 0.5, 25.0, 2.0)
end

local function storeRadius()
  return num(Config.Interaction and Config.Interaction.storeRadius, 0.5, 25.0, 4.0)
end

--- House ids become part of the garage key ('H' .. id, max 64 chars in the database).
local function houseIdString(houseId)
  if type(houseId) == 'number' then
    if houseId ~= houseId or houseId == math.huge or houseId == -math.huge then return nil end
    houseId = tostring(math.tointeger(houseId) or houseId)
  end
  local s = safeText(houseId, 60)
  return s
end

local function sortedLocations(kind)
  local list = {}
  for _, loc in pairs(cache) do
    if kind == nil or loc.kind == kind then list[#list + 1] = loc end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

--- Columns are stored separately, everything else goes into the JSON `data` column.
local function dataOf(loc)
  local data = {}
  for k, v in pairs(loc) do
    if k ~= 'id' and k ~= 'kind' and k ~= 'name' and k ~= 'enabled' then data[k] = v end
  end
  return data
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

--- When the impound used for restarts disappears (deleted / no longer an impound), clear it.
local function releaseRestartImpound(id, src)
  if NZ.Settings.get('garages.restartImpound') ~= id then return end
  local settings = NZ.Settings.all()
  if type(settings.garages) ~= 'table' then return end
  settings.garages.restartImpound = nil
  NZ.Settings.save(settings, src)
end

---------------------------------------------------------------------------------------
-- Normalization
---------------------------------------------------------------------------------------

--- Build a complete Location (every default of §4.2 filled, everything sanitized).
---@param raw table untrusted location table
---@return table|nil location, string|nil error (translated)
function Locations.normalize(raw)
  if type(raw) ~= 'table' then return nil, L('Invalid location data') end
  local kind = raw.kind
  if not KINDS[kind] then return nil, L('Invalid garage type') end
  local name = safeText(raw.name, 60)
  if not name then return nil, L('A name is required') end

  local vehicleType = enum(raw.vehicleType, Utils.vehicleTypes, 'car')
  local loc = {
    id = positiveId(raw.id),
    kind = kind,
    name = name,
    vehicleType = vehicleType,
    enabled = bool(raw.enabled, true),
    spawnPoints = vec4List(raw.spawnPoints, LIMITS.spawnPoints),
    openPoints = pointList(raw.openPoints, LIMITS.points, openRadius()),
    useOpenForStore = bool(raw.useOpenForStore, true),
    storePoints = pointList(raw.storePoints, LIMITS.points, storeRadius()),
    returnToEntrance = bool(raw.returnToEntrance, false),
    blip = blipConfig(raw.blip, kind, vehicleType),
    interaction = interactionConfig(raw.interaction),
  }
  -- Without dedicated store points, vehicles are stored at the open points.
  if not loc.useOpenForStore and #loc.storePoints == 0 then loc.useOpenForStore = true end

  if kind == 'garage' then
    loc.source = enum(raw.source, GARAGE_SOURCES, 'personal')
    loc.spawner = spawnerList(raw.spawner)
    loc.capacity = capacityConfig(raw.capacity)
    loc.access = accessConfig(raw.access)
    loc.restriction = restrictionConfig(raw.restriction)
  elseif kind == 'job' then
    loc.source = enum(raw.source, JOB_SOURCES, 'spawner')
    loc.owner = enum(raw.owner, JOB_OWNERS, 'job')
    loc.jobs = jobRules(raw.jobs)
    loc.spawner = spawnerList(raw.spawner)
    loc.infiniteSpawns = bool(raw.infiniteSpawns, false)
    loc.setupMenu = bool(raw.setupMenu, true)
    loc.capacity = capacityConfig(raw.capacity)
    loc.access = accessConfig(raw.access)
  elseif kind == 'private' then
    loc.purchasable = bool(raw.purchasable, true)
    loc.price = num(raw.price, 0, MAX_GARAGE_PRICE, 50000, true)
    loc.maxCopies = num(raw.maxCopies, 0, 1000, 1, true)
    loc.storage = enum(raw.storage, STORAGE_MODES, 'shared')
    loc.sellRefund = num(raw.sellRefund, 0, 100, 50, true)
    loc.capacity = capacityConfig(raw.capacity)
    loc.access = accessConfig(raw.access)
  elseif kind == 'impound' then
    loc.jobs = jobRules(raw.jobs)
    loc.society = societyName(raw.society)
    loc.defaultFee = num(raw.defaultFee, 0, MAX_MONEY, num(NZ.Settings.get('impound.defaultFee'), 0, MAX_MONEY, 500, true), true)
    loc.defaultHours = Utils.round(num(raw.defaultHours, 0, 720, num(NZ.Settings.get('impound.defaultHours'), 0, 720, 0)), 2)
  end
  return loc
end

---------------------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------------------

--- Load (or reload) every location from the database into the cache.
function Locations.load()
  local rows = NZ.DB.locations.all()
  local fresh, loaded, skipped = {}, 0, 0
  if type(rows) == 'table' then
    for _, row in ipairs(rows) do
      local raw = row.data
      if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        raw = ok and decoded or nil
      end
      if type(raw) ~= 'table' then raw = {} end
      raw.id, raw.kind, raw.name, raw.enabled = row.id, row.kind, row.name, row.enabled
      local loc, err = Locations.normalize(raw)
      if loc and loc.id then
        fresh[loc.id] = loc
        loaded = loaded + 1
      else
        skipped = skipped + 1
        lib.print.warn(('locations: skipped location #%s (%s): %s'):format(tostring(row.id), tostring(row.name), tostring(err or 'invalid id')))
      end
    end
  end
  cache = fresh
  lib.print.info(('locations: %d loaded%s'):format(loaded, skipped > 0 and (', %d skipped'):format(skipped) or ''))
end

--- Every database location (houses excluded), sorted by id. Read-only references.
---@param kind string|nil 'garage' | 'job' | 'private' | 'impound'
---@return table[]
function Locations.all(kind)
  return sortedLocations(kind)
end

--- One location by numeric id, or a house garage by its 'H..' id. Read-only reference.
---@param id number|string
---@return table|nil
function Locations.get(id)
  if type(id) == 'string' then
    if id:sub(1, 1) == 'H' then return houses[id] end
    id = tonumber(id)
  end
  if type(id) ~= 'number' or id ~= id then return nil end
  return cache[id]
end

--- Insert (id == nil) or update a location. Normalizes, persists, refreshes the cache,
--- logs and syncs every client.
---@param location table
---@param src number|nil admin who made the change (for logs)
---@return table|nil location copy of the stored location, string|nil error (translated)
function Locations.save(location, src)
  if type(location) ~= 'table' then return nil, L('Invalid location data') end
  local loc, err = Locations.normalize(location)
  if not loc then return nil, err end

  -- An id that is present but not a valid database id never creates a new row.
  if location.id ~= nil and not loc.id then return nil, L('Location not found') end
  local existing = nil
  if loc.id then
    existing = cache[loc.id]
    if not existing then return nil, L('Location not found') end
  end

  -- Interior access needs an existing interior.
  local rawAccess = type(location.access) == 'table' and location.access or nil
  if loc.access and rawAccess and (rawAccess.mode == 'interior' or rawAccess.mode == 'both') then
    local interiorId = loc.access.interiorId
    if not interiorId then return nil, L('Select an interior for this garage') end
    if type(NZ.Interiors.get) == 'function' and not NZ.Interiors.get(interiorId) then
      return nil, L('The selected interior does not exist')
    end
  end

  local data = dataOf(loc)
  if existing then
    local ok = NZ.DB.locations.update(loc.id, loc.kind, loc.name, loc.enabled, data)
    if not ok then
      -- Some drivers report 0 affected rows when nothing changed: that is not a failure.
      local unchanged = existing.kind == loc.kind and existing.name == loc.name
        and existing.enabled == loc.enabled and deepEqual(dataOf(existing), data)
      if not unchanged then return nil, L('Could not save the location') end
    end
  else
    local id = tonumber(NZ.DB.locations.insert(loc.kind, loc.name, loc.enabled, data))
    if not id or id < 1 then return nil, L('Could not save the location') end
    loc.id = math.floor(id)
  end

  cache[loc.id] = loc
  log(existing and 'admin.location.update' or 'admin.location.create', src, {
    id = loc.id, name = loc.name, kind = loc.kind, vehicleType = loc.vehicleType, enabled = loc.enabled,
  })
  if existing and existing.kind == 'impound' and loc.kind ~= 'impound' then
    releaseRestartImpound(loc.id, src)
  end
  Locations.sync(-1)
  return Utils.deepCopy(loc)
end

--- Delete a location. Vehicles parked there keep their garage key (still retrievable with
--- retrieveMode 'anywhere' or through the admin vehicle manager).
---@param id number
---@param src number|nil admin (for logs)
---@return boolean ok, string|nil error (translated)
function Locations.delete(id, src)
  id = positiveId(id)
  local loc = id and cache[id]
  if not loc then return false, L('Location not found') end
  if not NZ.DB.locations.delete(id) then return false, L('Could not delete the location') end
  cache[id] = nil
  log('admin.location.delete', src, { id = id, name = loc.name, kind = loc.kind })
  releaseRestartImpound(id, src)
  Locations.sync(-1)
  return true
end

--- Enable or disable a location (disabled locations are hidden from players).
---@param id number
---@param enabled boolean
---@param src number|nil admin (for logs)
---@return boolean ok, string|nil error (translated)
function Locations.setEnabled(id, enabled, src)
  id = positiveId(id)
  local loc = id and cache[id]
  if not loc then return false, L('Location not found') end
  enabled = bool(enabled, false)
  if loc.enabled == enabled then return true end
  if not NZ.DB.locations.update(id, loc.kind, loc.name, enabled, dataOf(loc)) then
    return false, L('Could not save the location')
  end
  loc.enabled = enabled
  log('admin.location.toggle', src, { id = id, name = loc.name, kind = loc.kind, enabled = enabled })
  Locations.sync(-1)
  return true
end

---------------------------------------------------------------------------------------
-- House garages (runtime only, registered by the housing integration / exports)
---------------------------------------------------------------------------------------

--- Register (or replace) a house garage. Retrieved with NZ.Locations.get('H' .. houseId).
--- Does not sync clients: the housing integration pushes house views to the players with access.
---@param houseId string|number
---@param data table { name, coords = vec4, spawn = vec4|nil }
---@return table|nil location, string|nil error
function Locations.registerHouse(houseId, data)
  local hid = houseIdString(houseId)
  if not hid then return nil, L('Invalid house id') end
  if type(data) ~= 'table' then return nil, L('Invalid house data') end
  local coords = vec4(data.coords)
  if not coords then return nil, L('Invalid house coordinates') end
  local spawn = vec4(data.spawn) or coords
  local key = Utils.key.house(hid)
  local loc = {
    id = key,
    houseId = hid,
    kind = 'house',
    name = safeText(data.name or data.label, 60) or L('House garage'),
    vehicleType = 'car',
    enabled = true,
    openPoints = { { coords = { x = coords.x, y = coords.y, z = coords.z }, radius = openRadius() } },
    useOpenForStore = true,
    storePoints = {},
    spawnPoints = { spawn },
    returnToEntrance = false,
    blip = { enabled = false, sprite = BLIP_SPRITES.car, color = 3, scale = 0.6 },
    source = 'personal',
    capacity = { mode = 'unlimited', appliesTo = 'player', spaces = 1 },
    access = { mode = 'quick' },
  }
  houses[key] = loc
  return loc
end

--- Forget a house garage. Vehicles stored there keep their 'H..' garage key.
---@param houseId string|number
function Locations.removeHouse(houseId)
  local hid = houseIdString(houseId)
  if not hid then return end
  houses[Utils.key.house(hid)] = nil
end

---------------------------------------------------------------------------------------
-- Client views & sync
---------------------------------------------------------------------------------------

--- What clients receive for a location (no identifier lists, no spawner setup).
---@param location table
---@return table|nil
function Locations.clientView(location)
  if type(location) ~= 'table' then return nil end
  local copy = Utils.deepCopy
  local kind = location.kind
  local view = {
    id = location.id,
    kind = kind,
    name = location.name,
    vehicleType = location.vehicleType or 'car',
    enabled = location.enabled ~= false,
    openPoints = copy(location.openPoints or {}),
    storePoints = copy(location.storePoints or {}),
    useOpenForStore = location.useOpenForStore ~= false,
    spawnPoints = copy(location.spawnPoints or {}),
    returnToEntrance = location.returnToEntrance == true,
    blip = copy(location.blip),
    access = copy(location.access),
    source = location.source,
    interaction = copy(location.interaction),
  }
  if kind == 'garage' then
    local r = location.restriction or {}
    view.restriction = { type = r.type or 'everyone', rules = copy(r.rules or {}) }
    view.capacity = copy(location.capacity)
  elseif kind == 'job' then
    view.owner = location.owner
    view.jobs = copy(location.jobs or {})
    view.setupMenu = location.setupMenu ~= false
    view.capacity = copy(location.capacity)
  elseif kind == 'impound' then
    view.jobs = copy(location.jobs or {})
  elseif kind == 'private' then
    view.purchasable = location.purchasable == true
    view.price = location.price
    view.storage = location.storage
    view.maxCopies = location.maxCopies
    view.capacity = copy(location.capacity)
  elseif kind == 'house' then
    view.houseId = location.houseId
  end
  return view
end

local function sharedViews()
  local list = {}
  for _, loc in ipairs(sortedLocations(nil)) do
    if loc.enabled then list[#list + 1] = Locations.clientView(loc) end
  end
  return list
end

local function houseViewsFor(identifier)
  if not identifier or type(NZ.Housing.viewsFor) ~= 'function' then return nil end
  local ok, views = pcall(NZ.Housing.viewsFor, identifier)
  if not ok then
    lib.print.warn(('locations: housing views failed: %s'):format(tostring(views)))
    return nil
  end
  if type(views) ~= 'table' or #views == 0 then return nil end
  return views
end

local function withHouses(shared, extra)
  if not extra then return shared end
  local list = table.move(shared, 1, #shared, 1, {})
  for i = 1, #extra do list[#list + 1] = extra[i] end
  return list
end

--- Client views of every enabled location plus the house garages this identifier may use.
---@param identifier string|nil
---@return table[]
function Locations.clientViews(identifier)
  return withHouses(sharedViews(), houseViewsFor(identifier))
end

local function broadcast()
  local shared = sharedViews()
  if type(NZ.Housing.viewsFor) ~= 'function' then
    TriggerClientEvent('nz:client:locations', -1, shared)
    return
  end
  local targets, anyHouses = {}, false
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if src then
      local extra = houseViewsFor(identifierOf(src))
      targets[#targets + 1] = { src = src, houses = extra }
      if extra then anyHouses = true end
    end
  end
  if not anyHouses then
    TriggerClientEvent('nz:client:locations', -1, shared)
    return
  end
  for i = 1, #targets do
    local t = targets[i]
    TriggerClientEvent('nz:client:locations', t.src, withHouses(shared, t.houses))
  end
end

--- Send client views to one player (with their house garages) or to everyone (-1).
--- Broadcasts are debounced so bursts of changes send a single update.
---@param target number|nil player source, or -1 / nil for everyone
function Locations.sync(target)
  if target == nil or target == -1 then
    if broadcastPending then return end
    broadcastPending = true
    SetTimeout(BROADCAST_DELAY, function()
      broadcastPending = false
      local ok, err = pcall(broadcast)
      if not ok then lib.print.error(('locations: sync failed: %s'):format(tostring(err))) end
    end)
    return
  end
  local src = tonumber(target)
  if not src or src <= 0 then return end
  TriggerClientEvent('nz:client:locations', src, Locations.clientViews(identifierOf(src)))
end

---------------------------------------------------------------------------------------
-- Garage keys & capacity
---------------------------------------------------------------------------------------

--- Resolve a garage key to its location (and group / house).
---@param garageKey string 'L12' | 'G3' | 'Hgrove_1'
---@return table|nil { kind, key, location, locationId, group|nil, groupId|nil, houseId|nil }
function Locations.resolveKey(garageKey)
  local kind, id = Utils.key.parse(garageKey)
  if not kind then return nil end
  if kind == 'L' then
    local loc = cache[id]
    if not loc then return nil end
    return { kind = 'L', key = garageKey, location = loc, locationId = loc.id }
  elseif kind == 'G' then
    if type(NZ.Private.getGroup) ~= 'function' then return nil end
    local group = NZ.Private.getGroup(id)
    if type(group) ~= 'table' then return nil end
    local loc = cache[tonumber(group.locationId) or -1]
    if not loc then return nil end
    return { kind = 'G', key = garageKey, location = loc, locationId = loc.id, group = group, groupId = id }
  elseif kind == 'H' then
    local loc = houses[garageKey]
    if not loc then return nil end
    return { kind = 'H', key = garageKey, location = loc, locationId = loc.id, houseId = loc.houseId }
  end
  return nil
end

--- Display name of a garage key: location name, private group label or house name.
---@param garageKey string
---@return string|nil
function Locations.keyName(garageKey)
  local resolved = Locations.resolveKey(garageKey)
  if not resolved then return nil end
  if resolved.kind == 'G' then
    local label = resolved.group and resolved.group.label
    if type(label) == 'string' and label ~= '' then return label end
  end
  return resolved.location.name
end

--- Capacity usage of a garage. nil when the location has no limit.
---@param location table
---@param garageKey string|nil defaults to 'L' .. location.id
---@param identifier string|nil player whose vehicles count when appliesTo == 'player'
---@return table|nil { mode, appliesTo, used, total }
function Locations.capacity(location, garageKey, identifier)
  if type(location) ~= 'table' then return nil end
  local cap = location.capacity
  if type(cap) ~= 'table' or cap.mode ~= 'limited' then return nil end
  if type(garageKey) ~= 'string' then
    if type(location.id) ~= 'number' then return nil end
    garageKey = Utils.key.location(location.id)
  end
  local appliesTo = cap.appliesTo == 'total' and 'total' or 'player'
  local used = 0
  if appliesTo == 'total' then
    used = tonumber(NZ.DB.countInGarage(garageKey, nil)) or 0
  elseif type(identifier) == 'string' and identifier ~= '' then
    used = tonumber(NZ.DB.countInGarage(garageKey, identifier)) or 0
  end
  return { mode = 'limited', appliesTo = appliesTo, used = used, total = tonumber(cap.spaces) or 0 }
end
