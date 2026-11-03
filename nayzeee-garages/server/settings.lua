--[[
  nayzeee-garages — admin-editable settings (NZ.Settings), server side.

  Loads the settings document from `nz_settings` (through NZ.DB), merges it over
  Config.DefaultSettings and validates every value against a schema (unknown keys are
  dropped, wrong types fall back to defaults, enums are checked, numbers are clamped).
  Saving validates, persists, logs and broadcasts 'nz:client:settings' to every client.
]]

local Settings = NZ.Settings
local Utils = NZ.Utils

local MAX_MONEY = 10000000

---------------------------------------------------------------------------------------
-- Schema
--   t        'boolean' | 'number' | 'enum' | 'string' | 'url' | 'color' | 'impound'
--   def      fallback when Config.DefaultSettings lacks the key or holds an invalid value
--   min/max  number range (clamped) | max = string length
--   int      round numbers down to integers
--   values   allowed enum values
---------------------------------------------------------------------------------------

local schema = {
  vehicles = {
    spawnOutside = { t = 'boolean', def = false },
    saveMods = { t = 'boolean', def = true },
    checkModel = { t = 'boolean', def = true },
    serverSpawn = { t = 'boolean', def = false },
    saveDamage = { t = 'boolean', def = true },
    saveDeformation = { t = 'boolean', def = true },
    trailers = { t = 'boolean', def = true },
    giveKeys = { t = 'boolean', def = true },
    needsServiceBelow = { t = 'number', min = 0, max = 100, int = true, def = 60 },
  },
  garages = {
    retrieveMode = { t = 'enum', values = { 'anywhere', 'last' }, def = 'last' },
    showBlips = { t = 'boolean', def = true },
    suggestWhenFull = { t = 'boolean', def = true },
    outOnRestart = { t = 'enum', values = { 'garage', 'impound', 'keep' }, def = 'garage' },
    restartImpound = { t = 'impound' },
    recoverFee = { t = 'number', min = 0, max = MAX_MONEY, int = true, def = 250 },
    storeOnlyOwned = { t = 'boolean', def = true },
    maxDistance = { t = 'number', min = 5, max = 100, def = 25.0 },
  },
  transfers = {
    garageEnabled = { t = 'boolean', def = true },
    garageFee = { t = 'number', min = 0, max = MAX_MONEY, int = true, def = 2500 },
    playerEnabled = { t = 'boolean', def = true },
    playerFee = { t = 'number', min = 0, max = MAX_MONEY, int = true, def = 0 },
    sellEnabled = { t = 'boolean', def = true },
    shareEnabled = { t = 'boolean', def = true },
    maxShares = { t = 'number', min = 0, max = 50, int = true, def = 5 },
  },
  impound = {
    defaultFee = { t = 'number', min = 0, max = MAX_MONEY, int = true, def = 500 },
    defaultHours = { t = 'number', min = 0, max = 720, def = 0 },
    staffBypassFee = { t = 'boolean', def = true },
  },
  economy = {
    account = { t = 'enum', values = { 'bank', 'cash', 'both' }, def = 'bank' },
  },
  interface = {
    defaultView = { t = 'enum', values = { 'grid', 'list' }, def = 'grid' },
    distanceUnit = { t = 'enum', values = { 'mi', 'km' }, def = 'mi' },
    currency = { t = 'string', max = 8, def = '$' },
    imageUrl = { t = 'url', max = 300, def = 'https://docs.fivem.net/vehicles/{model}.webp' },
    showImages = { t = 'boolean', def = true },
    accent = { t = 'color', def = '#08afa2' },
    interaction = { t = 'enum', values = { 'prompt', 'target', 'both' }, def = 'prompt' },
  },
}

-- Turn enum value lists into lookup sets once.
for _, section in pairs(schema) do
  for _, rule in pairs(section) do
    if rule.values then
      local set = {}
      for _, v in ipairs(rule.values) do set[v] = true end
      rule.set = set
    end
  end
end

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('settings: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function isFinite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
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

--- Strip a trailing, truncated UTF-8 sequence so the text stays valid for JSON / NUI.
local function safeText(value, maxLen)
  local s = Utils.cleanText(value, maxLen)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

--- Validate one value against its rule.
---@return boolean ok, any value
local function check(rule, value, checkRefs)
  local t = rule.t
  if t == 'boolean' then
    if type(value) == 'boolean' then return true, value end
    return false
  elseif t == 'number' then
    local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
    if not isFinite(n) then return false end
    if rule.min and n < rule.min then n = rule.min end
    if rule.max and n > rule.max then n = rule.max end
    if rule.int then n = math.floor(n) end
    return true, n
  elseif t == 'enum' then
    if type(value) == 'string' and rule.set[value] then return true, value end
    return false
  elseif t == 'string' then
    local s = safeText(value, rule.max or 256)
    if s then return true, s end
    return false
  elseif t == 'url' then
    if type(value) ~= 'string' then return false end
    local s = Utils.trim(value)
    if #s == 0 or #s > (rule.max or 300) or s:find('[%s%c<>"\']') then return false end
    if not (s:match('^https?://') or s:match('^nui://')) then return false end
    return true, s
  elseif t == 'color' then
    if type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') then return true, value:lower() end
    return false
  elseif t == 'impound' then
    if value == nil then return true, nil end
    local n = tonumber(value)
    if not isFinite(n) or n < 1 then return false end
    n = math.floor(n)
    if checkRefs then
      local loc = NZ.Locations.get(n)
      if not loc or loc.kind ~= 'impound' then return false end
    end
    return true, n
  elseif t == 'generic' then
    -- Keys added to Config.DefaultSettings that this schema does not know yet:
    -- accept them when they keep the type of their default.
    local expected = type(rule.def)
    if type(value) ~= expected then return false end
    if expected == 'number' then
      if not isFinite(value) then return false end
      return true, value
    elseif expected == 'string' then
      local s = safeText(value, 256)
      if s then return true, s end
      return false
    elseif expected == 'table' then
      return true, Utils.deepCopy(value)
    end
    return true, value
  end
  return false
end

local function configDefault(section, key)
  local defaults = Config.DefaultSettings
  if type(defaults) ~= 'table' then return nil end
  if key == nil then return defaults[section] end
  local sec = defaults[section]
  if type(sec) ~= 'table' then return nil end
  return sec[key]
end

--- Default value for a key: Config.DefaultSettings when valid, otherwise the schema fallback.
local function defaultFor(rule, section, key)
  local cfg = configDefault(section, key)
  if rule.t == 'generic' then return Utils.deepCopy(cfg) end
  local ok, value = check(rule, cfg, false)
  if ok then return value end
  return Utils.deepCopy(rule.def)
end

--- Union of the schema keys and the Config.DefaultSettings keys of one section.
local function sectionKeys(section)
  local keys = {}
  if schema[section] then
    for k in pairs(schema[section]) do keys[k] = true end
  end
  local cfg = configDefault(section)
  if type(cfg) == 'table' then
    for k in pairs(cfg) do keys[k] = true end
  end
  return keys
end

local function sectionNames()
  local names = {}
  for k in pairs(schema) do names[k] = true end
  if type(Config.DefaultSettings) == 'table' then
    for k, v in pairs(Config.DefaultSettings) do
      if type(v) == 'table' then names[k] = true end
    end
  end
  return names
end

--- Build a complete, valid settings table from untrusted input.
---@param raw table|nil
---@param checkRefs boolean verify references to other data (restartImpound -> impound location)
---@return table
local function validate(raw, checkRefs)
  raw = type(raw) == 'table' and raw or {}
  local out = {}
  for section in pairs(sectionNames()) do
    local input = type(raw[section]) == 'table' and raw[section] or {}
    local result = {}
    for key in pairs(sectionKeys(section)) do
      local rule = schema[section] and schema[section][key]
      if not rule then rule = { t = 'generic', def = configDefault(section, key) } end
      local value = input[key]
      local ok, clean = false, nil
      if value ~= nil then ok, clean = check(rule, value, checkRefs) end
      if ok then
        result[key] = clean
      else
        result[key] = defaultFor(rule, section, key)
      end
    end
    out[section] = result
  end
  return out
end

local function describe(value)
  if value == nil then return 'none' end
  if type(value) == 'table' then return json.encode(value) end
  return tostring(value)
end

--- List of human readable "section.key: old -> new" changes (for logs).
local function diff(old, new)
  local changes = {}
  for section, values in pairs(new) do
    local before = type(old[section]) == 'table' and old[section] or {}
    for key, value in pairs(values) do
      if not deepEqual(before[key], value) then
        changes[#changes + 1] = ('%s.%s: %s -> %s'):format(section, key, describe(before[key]), describe(value))
      end
    end
    for key, value in pairs(before) do
      if values[key] == nil and value ~= nil then
        changes[#changes + 1] = ('%s.%s: %s -> none'):format(section, key, describe(value))
      end
    end
  end
  table.sort(changes)
  return changes
end

-- Live settings. Valid defaults until NZ.Settings.load() runs, so get() works at any time.
local current = validate(nil, false)

local pathCache, pathCacheSize = {}, 0

local function splitPath(path)
  local parts = pathCache[path]
  if parts then return parts end
  parts = {}
  for segment in path:gmatch('[^%.]+') do parts[#parts + 1] = segment end
  if pathCacheSize < 512 then
    pathCache[path] = parts
    pathCacheSize = pathCacheSize + 1
  end
  return parts
end

local function persist(tbl)
  if type(NZ.DB.settings) ~= 'table' or type(NZ.DB.settings.save) ~= 'function' then return false end
  local ok, res = pcall(NZ.DB.settings.save, tbl)
  if not ok then
    lib.print.error(('settings: could not write nz_settings: %s'):format(tostring(res)))
    return false
  end
  return res ~= false
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Load settings from the database (first boot writes the defaults). Called once at boot.
function Settings.load()
  local raw = NZ.DB.settings.load()
  if type(raw) ~= 'table' then
    current = validate(nil, false)
    if persist(current) then
      lib.print.info('settings: first start, default settings written to nz_settings')
    else
      lib.print.warn('settings: using default settings (could not write them to nz_settings)')
    end
    return
  end
  current = validate(raw, false)
  -- Keys added/removed by an update or invalid values: store the cleaned document.
  if not deepEqual(current, raw) then
    if persist(current) then
      Utils.debug('settings: stored settings were upgraded / cleaned')
    end
  end
end

--- Drop references to data that no longer exists. Called at boot once locations are loaded.
--- garages.restartImpound must point to an existing impound location, else it is ignored.
function Settings.checkReferences()
  local garages = current.garages
  local id = type(garages) == 'table' and garages.restartImpound or nil
  if id == nil then return end
  local loc = NZ.Locations.get(id)
  if not loc or loc.kind ~= 'impound' then
    lib.print.warn(('settings: garages.restartImpound (%s) is not an impound location, ignoring it'):format(tostring(id)))
    garages.restartImpound = nil
  end
end

--- Copy of every setting.
---@return table
function Settings.all()
  return Utils.deepCopy(current)
end

--- Read one setting by dotted path, e.g. NZ.Settings.get('vehicles.saveDamage', true).
--- Tables are returned as copies.
---@param path string
---@param default any returned when the path does not exist
---@return any
function Settings.get(path, default)
  if type(path) ~= 'string' or path == '' then return default end
  local node = current
  local parts = splitPath(path)
  for i = 1, #parts do
    if type(node) ~= 'table' then return default end
    node = node[parts[i]]
    if node == nil then return default end
  end
  if type(node) == 'table' then return Utils.deepCopy(node) end
  return node
end

--- The `interface` section (sent to the NUI).
---@return table
function Settings.interface()
  return Utils.deepCopy(current.interface or {})
end

--- Validate, persist and broadcast new settings. Missing or invalid values fall back to
--- their defaults; unknown keys are dropped.
---@param newSettings table full Settings object (admin panel)
---@param src number|nil player who made the change (for logs)
---@return table|nil settings validated copy (nil only when the input is not a table)
---@return boolean|string persisted true when stored in the database (or an error message)
function Settings.save(newSettings, src)
  if type(newSettings) ~= 'table' then return nil, L('Invalid settings') end
  local validated = validate(newSettings, true)
  local changes = diff(current, validated)
  local persisted = persist(validated)
  if not persisted then
    lib.print.error('settings: new settings are active but could not be saved to the database')
  end
  current = validated
  TriggerClientEvent('nz:client:settings', -1, Utils.deepCopy(current))
  log('admin.settings', src, { changes = changes, persisted = persisted })
  return Utils.deepCopy(current), persisted
end
