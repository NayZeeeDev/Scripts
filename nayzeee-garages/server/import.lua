--[[
  nayzeee-garages — import garages from other garage scripts (NZ.Import), server side.

  Sources (ServerConfig.ImportSources):
    'qb-garages'  — reads config.lua of the resource
    'qbx_garages' — reads config/shared.lua, config/server.lua (and config.lua)
    'json'        — a JSON array of Location-like objects pasted in the admin panel
  Config files are executed in an empty sandbox: only Config, vector helpers, math, string,
  table, a few pure builtins and a no-op `lib` exist; every other global resolves to an inert
  value. Nothing in the sandbox can reach natives, exports, events or the file system.
  Every location goes through NZ.Locations.save (normalized, logged, synced). Locations that
  already exist with the same name and kind are skipped.
]]

local Import = NZ.Import
local Utils = NZ.Utils

local MAX_JSON_BYTES = 1048576     -- 1 MiB of pasted JSON
local MAX_ITEMS = 500              -- locations per import
local MAX_INSTRUCTIONS = 20000000  -- config execution budget (VM instructions)

local QBX_FILES = { 'config/shared.lua', 'config/server.lua', 'config.lua' }
local QB_FILES = { 'config.lua', 'config/shared.lua', 'config/server.lua' }

local TYPE_ALIASES = {
  car = 'car', rig = 'car', truck = 'car', bike = 'car', automobile = 'car', land = 'car',
  sea = 'sea', boat = 'sea', water = 'sea', submarine = 'sea',
  air = 'air', plane = 'air', heli = 'air', helicopter = 'air', aircraft = 'air',
}

---------------------------------------------------------------------------------------
-- Inert sandbox values
---------------------------------------------------------------------------------------

local inert = setmetatable({}, {})
do
  local function self() return inert end
  local function zero() return 0 end
  local mt = getmetatable(inert)
  mt.__index = function(_, k)
    if type(k) == 'number' then return nil end -- keeps ipairs() finite
    return inert
  end
  mt.__newindex = function() end
  mt.__call = self
  mt.__len = zero
  mt.__concat = function() return '' end
  mt.__tostring = function() return '' end
  mt.__unm = zero
  mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__mod, mt.__pow, mt.__idiv = zero, zero, zero, zero, zero, zero, zero
  mt.__band, mt.__bor, mt.__bxor, mt.__shl, mt.__shr, mt.__bnot = zero, zero, zero, zero, zero, zero
  mt.__lt = function() return false end
  mt.__le = function() return false end
  mt.__pairs = function() return function() return nil end, inert, nil end
  mt.__metatable = false
end

local function isInert(v) return rawequal(v, inert) end

local function copyLib(src)
  local out = {}
  for k, v in pairs(src) do out[k] = v end
  return out
end

local function newSandbox()
  local env = {
    Config = {},
    vector2 = vector2, vector3 = vector3, vector4 = vector4,
    vec2 = vec2 or vector2, vec3 = vec3 or vector3, vec4 = vec4 or vector4,
    math = copyLib(math), string = copyLib(string), table = copyLib(table),
    pairs = pairs, ipairs = ipairs, next = next, type = type, select = select,
    tostring = tostring, tonumber = tonumber, unpack = table.unpack,
    lib = inert,
    -- enums used by qbx_garages configs
    VehicleType = { CAR = 'car', AIR = 'air', SEA = 'sea' },
    GarageType = { PUBLIC = 'public', JOB = 'job', GANG = 'gang', DEPOT = 'depot', HOUSE = 'house' },
  }
  setmetatable(env, { __index = function() return inert end })
  return env
end

--- Execute a config chunk inside the sandbox with an instruction budget.
---@return boolean ok, any returned value or error message
local function runChunk(code, chunkName, env)
  local chunk, err = load(code, '@' .. chunkName, 't', env)
  if not chunk then return false, err end
  local hooked = type(debug) == 'table' and type(debug.sethook) == 'function' and type(debug.gethook) == 'function'
  local previous, previousMask, previousCount
  if hooked then
    previous, previousMask, previousCount = debug.gethook()
    debug.sethook(function() error('the config file took too long to run', 2) end, '', MAX_INSTRUCTIONS)
  end
  local success, result = pcall(chunk)
  if hooked then
    if previous then
      debug.sethook(previous, previousMask or '', previousCount or 0)
    else
      debug.sethook()
    end
  end
  return success, result
end

---------------------------------------------------------------------------------------
-- Field helpers (every value read from a config may be inert or of the wrong type)
---------------------------------------------------------------------------------------

local function str(v)
  if type(v) ~= 'string' then return nil end
  local s = Utils.trim(v)
  if s == '' then return nil end
  return s
end

local function isTable(v)
  return type(v) == 'table' and not isInert(v)
end

local function isPoint(v)
  local t = type(v)
  if t == 'vector3' or t == 'vector4' then return true end
  return isTable(v) and Utils.v3(v) ~= nil
end

--- A point or a list of points -> list of plain {x,y,z,w} tables.
local function points4(value)
  local out = {}
  if value == nil or isInert(value) then return out end
  if isPoint(value) and not (isTable(value) and value[1] ~= nil and isPoint(value[1])) then
    local v = Utils.v4(value)
    if v then out[1] = v end
    return out
  end
  if isTable(value) then
    for _, item in ipairs(value) do
      if isPoint(item) then
        local v = Utils.v4(item)
        if v then out[#out + 1] = v end
      end
    end
  end
  return out
end

local function point3(value)
  if not isPoint(value) then return nil end
  return Utils.v3(value)
end

--- Vehicle category from a qb `vehicle` string, qbx `vehicleType` or a qb class list.
local function vehicleTypeOf(raw)
  local declared = str(raw.vehicleType) or str(raw.vehicle) or (type(raw.category) == 'string' and str(raw.category)) or nil
  if declared and TYPE_ALIASES[declared:lower()] then return TYPE_ALIASES[declared:lower()] end
  if isTable(raw.category) then
    local land, sea, air = false, false, false
    for _, class in ipairs(raw.category) do
      class = tonumber(class)
      if class == 14 then sea = true
      elseif class == 15 or class == 16 then air = true
      elseif class then land = true end
    end
    if land then return 'car' end
    if air then return 'air' end
    if sea then return 'sea' end
  end
  return 'car'
end

--- Job / gang rules from a string, a list of names or a { name = minGrade } map.
local function rulesOf(value)
  local rules = {}
  if type(value) == 'string' then
    local name = str(value)
    if name then rules[1] = { name = name, minGrade = 0 } end
  elseif isTable(value) then
    if value[1] ~= nil then
      for _, name in ipairs(value) do
        name = str(name)
        if name then rules[#rules + 1] = { name = name, minGrade = 0 } end
      end
    else
      for name, grade in pairs(value) do
        name = str(name)
        if name then
          local g = tonumber(type(grade) == 'table' and grade[1] or grade)
          rules[#rules + 1] = { name = name, minGrade = math.max(0, math.floor(g or 0)) }
        end
      end
      table.sort(rules, function(a, b) return a.name < b.name end)
    end
  end
  return rules
end

local gangNames = nil
local function isGang(name)
  if not gangNames then
    gangNames = {}
    if NZ.Bridge.hasGangs and type(NZ.Bridge.getGangs) == 'function' then
      local success, list = pcall(NZ.Bridge.getGangs)
      if success and type(list) == 'table' then
        for _, gang in ipairs(list) do
          if type(gang) == 'table' and type(gang.name) == 'string' then gangNames[gang.name] = true end
        end
      end
    end
  end
  return gangNames[name] == true
end

local function humanize(key)
  if type(key) ~= 'string' then return nil end
  local s = key:gsub('[_%-]+', ' '):gsub('(%l)(%u)', '%1 %2')
  s = Utils.trim(s)
  if s == '' then return nil end
  return (s:gsub('^%l', string.upper))
end

local function blipOf(raw, kind)
  local blip = { enabled = true }
  if isTable(raw.blip) then
    blip.sprite = tonumber(raw.blip.sprite)
    blip.color = tonumber(raw.blip.color or raw.blip.colour)
    blip.scale = tonumber(raw.blip.scale)
  end
  if raw.showBlip == false or (isTable(raw.blip) and raw.blip.enabled == false) then blip.enabled = false end
  blip.sprite = blip.sprite or tonumber(raw.blipNumber)
  blip.color = blip.color or tonumber(raw.blipColor or raw.blipColour)
  if kind == 'job' and raw.blip == nil and raw.showBlip == nil then blip.enabled = false end
  return blip
end

--- Build a Location-like table from one garage entry of qb-garages / qbx_garages.
---@return table|nil location, string|nil reasonSkipped
local function mapGarage(key, raw, forcedType)
  if not isTable(raw) then return nil, 'not a table' end
  local gtype = (str(forcedType) or str(raw.type) or 'public'):lower()
  if gtype == 'house' or raw.isHouseGarage == true then return nil, 'house garage' end

  local vehicleType = vehicleTypeOf(raw)
  local name = str(raw.label) or humanize(key)
  if not name then return nil, 'no name' end

  local openPoints, spawnPoints, storePoints = {}, {}, {}
  if isTable(raw.accessPoints) then
    -- qbx_garages: { { coords = vec4, spawn = vec4?, dropPoint = vec3? }, ... }
    for _, access in ipairs(raw.accessPoints) do
      if isTable(access) then
        local coords = point3(access.coords)
        if coords then openPoints[#openPoints + 1] = { coords = coords } end
        local spawn = Utils.v4(isPoint(access.spawn) and access.spawn or nil)
        if spawn then spawnPoints[#spawnPoints + 1] = spawn end
        for _, p in ipairs(points4(access.spawnPoints)) do spawnPoints[#spawnPoints + 1] = p end
        local drop = point3(access.dropPoint)
        if drop then storePoints[#storePoints + 1] = { coords = drop } end
      end
    end
  else
    -- qb-garages: takeVehicle, spawnPoint(s), putVehicle
    local take = point3(raw.takeVehicle) or point3(raw.coords) or point3(raw.pos)
    if take then openPoints[1] = { coords = take } end
    for _, p in ipairs(points4(raw.spawnPoint)) do spawnPoints[#spawnPoints + 1] = p end
    for _, p in ipairs(points4(raw.spawnPoints)) do spawnPoints[#spawnPoints + 1] = p end
    local put = point3(raw.putVehicle)
    if put then storePoints[1] = { coords = put } end
  end

  if #openPoints == 0 then
    if spawnPoints[1] then
      openPoints[1] = { coords = { x = spawnPoints[1].x, y = spawnPoints[1].y, z = spawnPoints[1].z } }
    else
      return nil, 'no coordinates'
    end
  end
  if #spawnPoints == 0 then
    local c = openPoints[1].coords
    spawnPoints[1] = { x = c.x, y = c.y, z = c.z, w = 0.0 }
  end

  local location = {
    name = name,
    vehicleType = vehicleType,
    enabled = true,
    spawnPoints = spawnPoints,
    openPoints = openPoints,
    useOpenForStore = #storePoints == 0,
    storePoints = storePoints,
    returnToEntrance = false,
  }

  local jobRules = rulesOf(raw.job)
  local gangRules = rulesOf(raw.gang)
  local groupRules = rulesOf(raw.groups)

  if gtype == 'depot' or gtype == 'impound' then
    location.kind = 'impound'
    location.jobs = #jobRules > 0 and jobRules or groupRules
    location.society = ''
    location.blip = blipOf(raw, 'impound')
    return location
  end

  if gtype == 'job' or gtype == 'gang' or #jobRules > 0 or #gangRules > 0 or #groupRules > 0 then
    local owner = 'job'
    local rules = jobRules
    if gtype == 'gang' or (#gangRules > 0 and #jobRules == 0) then
      owner, rules = 'gang', gangRules
    end
    if #rules == 0 then
      rules = groupRules
      if gtype ~= 'job' and rules[1] and isGang(rules[1].name) then owner = 'gang' end
    end
    if #rules == 0 then return nil, 'job garage without a job' end
    if owner == 'gang' and not NZ.Bridge.hasGangs then return nil, 'gangs are not supported' end
    location.kind = 'job'
    location.source = 'owned'
    location.owner = owner
    location.jobs = rules
    location.blip = blipOf(raw, 'job')
    return location
  end

  location.kind = 'garage'
  location.source = 'personal'
  location.blip = blipOf(raw, 'garage')
  return location
end

---------------------------------------------------------------------------------------
-- Readers
---------------------------------------------------------------------------------------

--- Every garage entry found in the sandbox globals / chunk return value.
--- Returns a list of { key, raw, forcedType }.
local function collectGarages(env, returned, into)
  local function addMap(map, forcedType)
    if not isTable(map) then return end
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      into[#into + 1] = { key = tostring(k), raw = map[k], forcedType = forcedType }
    end
  end

  local config = rawget(env, 'Config')
  if isTable(config) then
    addMap(rawget(config, 'Garages'), nil)
    addMap(rawget(config, 'JobGarages'), 'job')
    addMap(rawget(config, 'GangGarages'), 'gang')
    addMap(rawget(config, 'Depots'), 'depot')
    addMap(rawget(config, 'Impounds'), 'depot')
  end
  -- Very old qb-garages versions used globals instead of Config fields.
  addMap(rawget(env, 'Garages'), nil)
  addMap(rawget(env, 'JobGarages'), 'job')
  addMap(rawget(env, 'GangGarages'), 'gang')
  addMap(rawget(env, 'Depots'), 'depot')

  if isTable(returned) then
    if isTable(rawget(returned, 'garages')) then
      addMap(rawget(returned, 'garages'), nil)
    elseif isTable(rawget(returned, 'Garages')) then
      addMap(rawget(returned, 'Garages'), nil)
    end
  end
end

--- Load and run the config files of a garage resource.
---@return table[]|nil entries, string|nil error (translated)
local function readResource(resource, files)
  local state = GetResourceState(resource)
  if state == 'missing' or state == 'unknown' then
    return nil, L('The resource {resource} is not installed', { resource = resource })
  end
  local entries, found, errors = {}, 0, {}
  for _, file in ipairs(files) do
    local code = LoadResourceFile(resource, file)
    if type(code) == 'string' and code ~= '' then
      found = found + 1
      local env = newSandbox()
      local success, result = runChunk(code, resource .. '/' .. file, env)
      if not success then
        errors[#errors + 1] = ('%s: %s'):format(file, tostring(result))
        lib.print.warn(('import: %s/%s did not run completely: %s'):format(resource, file, tostring(result)))
      end
      -- Fields assigned before an error are still usable.
      collectGarages(env, success and result or nil, entries)
    end
  end
  if found == 0 then
    return nil, L('No config file was found in {resource}', { resource = resource })
  end
  if #entries == 0 and #errors > 0 then
    return nil, L('The config of {resource} could not be read', { resource = resource })
  end
  return entries, nil
end

--- Parse pasted JSON into Location-like tables.
---@return table[]|nil items, string|nil error (translated)
local function readJson(text)
  if type(text) ~= 'string' or Utils.trim(text) == '' then return nil, L('Paste the JSON to import') end
  if #text > MAX_JSON_BYTES then return nil, L('The JSON is too large') end
  local success, decoded = pcall(json.decode, text)
  if not success or type(decoded) ~= 'table' then return nil, L('The JSON could not be read') end
  if type(decoded.locations) == 'table' then decoded = decoded.locations end
  if decoded[1] == nil and type(decoded.kind) == 'string' then decoded = { decoded } end
  local items = {}
  for _, item in ipairs(decoded) do
    if type(item) == 'table' then items[#items + 1] = item end
  end
  if #items == 0 then return nil, L('The JSON does not contain any location') end
  return items, nil
end

---------------------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------------------

local function dedupeKey(name, kind)
  return (tostring(kind) .. '|' .. Utils.trim(tostring(name)):lower())
end

--- Interior references must exist; anything else falls back to the quick menu.
local function cleanAccess(location)
  local access = location.access
  if type(access) ~= 'table' then return end
  local interiorId = tonumber(access.interiorId)
  if not interiorId or type(NZ.Interiors.get) ~= 'function' or not NZ.Interiors.get(interiorId) then
    location.access = { mode = 'quick' }
  end
end

--- Import garages from another garage script or from JSON.
---@param source string import source key ('qb-garages' | 'qbx_garages' | 'json')
---@param text string|nil JSON text (source 'json')
---@param src number|nil admin who started the import (for logs)
---@return table|nil result { imported, skipped }, string|nil error (translated)
function Import.run(source, text, src)
  if type(source) ~= 'string' then return nil, L('Unknown import source') end
  local allowed = false
  for _, key in ipairs(type(ServerConfig.ImportSources) == 'table' and ServerConfig.ImportSources or {}) do
    if key == source then allowed = true break end
  end
  if not allowed then return nil, L('Unknown import source') end

  local candidates = {}
  if source == 'json' then
    local items, err = readJson(text)
    if not items then return nil, err end
    for _, item in ipairs(items) do
      local copy = Utils.deepCopy(item)
      copy.id = nil
      candidates[#candidates + 1] = { location = copy }
    end
  else
    local files = source == 'qbx_garages' and QBX_FILES or QB_FILES
    local entries, err = readResource(source, files)
    if not entries then return nil, err end
    for _, entry in ipairs(entries) do
      local location, reason = mapGarage(entry.key, entry.raw, entry.forcedType)
      candidates[#candidates + 1] = { location = location, reason = reason, key = entry.key }
    end
  end

  gangNames = nil
  local seen = {}
  for _, location in ipairs(NZ.Locations.all() or {}) do
    seen[dedupeKey(location.name, location.kind)] = true
  end

  local imported, skipped, reasons = 0, 0, {}
  for i, candidate in ipairs(candidates) do
    local location = candidate.location
    if i > MAX_ITEMS then
      skipped = skipped + 1
    elseif type(location) ~= 'table' then
      skipped = skipped + 1
      reasons[#reasons + 1] = ('%s: %s'):format(tostring(candidate.key), tostring(candidate.reason))
    else
      cleanAccess(location)
      local normalized = NZ.Locations.normalize(location)
      local dkey = normalized and dedupeKey(normalized.name, normalized.kind) or nil
      if not normalized then
        skipped = skipped + 1
        reasons[#reasons + 1] = ('%s: invalid'):format(tostring(candidate.key or location.name))
      elseif seen[dkey] then
        skipped = skipped + 1
      else
        local saved, saveErr = NZ.Locations.save(location, src)
        if saved then
          seen[dkey] = true
          imported = imported + 1
        else
          skipped = skipped + 1
          reasons[#reasons + 1] = ('%s: %s'):format(tostring(location.name), tostring(saveErr))
        end
      end
    end
  end

  if #reasons > 0 then
    lib.print.info(('import from %s skipped %d entr%s: %s'):format(source, #reasons, #reasons == 1 and 'y' or 'ies',
      table.concat(reasons, '; ', 1, math.min(#reasons, 20))))
  end
  return { imported = imported, skipped = skipped }, nil
end
