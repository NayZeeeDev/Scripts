--[[
  nayzeee-garages — car lock: security profiles and helpers shared by server and client
  (NZ.CarLock). docs/CARLOCK.md §1-3.

  Pure functions over Config.CarLock / Config.Integrations: whether the built-in system is
  active, the security profile of a model / class, item names, ranges, the key mode
  (keyMode: flexible / limited / virtual; resolveMode: item storage or not) and the key item
  metadata label, the hotwire method of a vehicle, the admin key settings schema
  (settingsSchema / validateSetting / applySettings: values written into Config.CarLock; clients
  apply GlobalState.nzKeySettings) and the per-player key settings (normalizePlayerSettings).
  Natives: joaat, GetResourceState (once, at load); clients: the GlobalState handler.

  Config.Integrations.keys = 'auto': the built-in car lock runs unless another key resource
  (qbx_vehiclekeys, qb-vehiclekeys, wasabi_carlock, ...) is started when this resource loads
  or starts after it while the server boots (no player connected yet); 'nayzeee' forces it.
  The server decides and publishes the result in GlobalState.nzCarLockOther
  (server/carlock/keys.lua) so every client agrees with it.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local DEFAULT_PROFILE = {
  label = 'Standard',
  keyItem = 'key',
  remote = false,
  accessTools = {},
  hotwire = { method = 'skillcheck', difficulty = { 'easy', 'medium' }, duration = 6000, alertChance = 25 },
  tracker = false,
  alarm = 'native',
}

local DEFAULT_ITEMS = { key = 'vehicle_key', fob = 'vehicle_fob' }
local DEFAULT_RANGES = { key = 5.0, fob = 30.0, give = 3.0, compat = 8.0 }

---------------------------------------------------------------------------------------
-- Config access
---------------------------------------------------------------------------------------

--- Config.CarLock (empty table when missing).
---@return table
function CarLock.cfg()
  local cfg = Config.CarLock
  return type(cfg) == 'table' and cfg or {}
end

-- Key resources that take over locks and the engine themselves (same list and order as
-- bridge/server/keys.lua). With Config.Integrations.keys = 'auto' a running one wins.
local OTHER_KEY_RESOURCES = {
  'qbx_vehiclekeys', 'qb-vehiclekeys', 'wasabi_carlock', 'MrNewbVehicleKeys', 'qs-vehiclekeys',
  'Renewed-Vehiclekeys', 'vehicles_keys',
}

--- First key resource of OTHER_KEY_RESOURCES that is started right now, or nil. Only
--- 'started' counts: this resource is still 'starting' while it loads, so a `provide` of one
--- of those names in our own manifest never matches.
---@return string|nil
function CarLock.detectOtherKeys()
  for _, name in ipairs(OTHER_KEY_RESOURCES) do
    local ok, state = pcall(GetResourceState, name)
    if ok and state == 'started' then return name end
  end
  return nil
end

--- The list above (copy), for warnings and the listener file.
---@return string[]
function CarLock.otherKeyResources()
  local out = {}
  for i, name in ipairs(OTHER_KEY_RESOURCES) do out[i] = name end
  return out
end

local function readGlobal()
  local ok, value = pcall(function() return GlobalState.nzCarLockOther end)
  if not ok then return nil end
  return value
end

-- Decided at load. The server may hand over once more while it boots (a key resource that
-- starts after this one before any player is connected, server/carlock/keys.lua); later a
-- key resource starting only gets a warning. Clients take the server's decision
-- (GlobalState) and detect locally only when it has not replicated yet.
local otherKeys = nil
do
  local isServer = type(IsDuplicityVersion) == 'function' and IsDuplicityVersion() == true
  local published = (not isServer) and readGlobal() or nil
  if type(published) == 'string' and published ~= '' then
    otherKeys = published
  elseif published ~= false then
    otherKeys = CarLock.detectOtherKeys()
  end
end

--- Key resource that was running when this resource started (nil = none).
---@return string|nil
function CarLock.otherKeyResource()
  return otherKeys
end

--- Hand keys over to another key resource (server boot window only: it started after this
--- one before any player joined). Config.Integrations.keys = 'auto' then turns the built-in
--- car lock off.
---@param name string
function CarLock.setOtherKeyResource(name)
  if type(name) == 'string' and name ~= '' then otherKeys = name end
end

--- Config.Integrations.keys, lower case ('auto' when empty).
---@return string
function CarLock.keysSetting()
  local keys = Config.Integrations and Config.Integrations.keys or 'auto'
  if type(keys) ~= 'string' or keys == '' then keys = 'auto' end
  return keys:lower()
end

--- Is the built-in car lock in charge of keys? Config.CarLock.enabled and
--- Config.Integrations.keys = 'nayzeee', or 'auto' while no other key resource runs.
---@return boolean
function CarLock.enabled()
  if CarLock.cfg().enabled ~= true then return false end
  local keys = CarLock.keysSetting()
  if keys == 'nayzeee' then return true end
  return keys == 'auto' and otherKeys == nil
end

--- Is compatibility with other key resources' events / exports on?
---@return boolean
function CarLock.compatEnabled()
  return CarLock.enabled() and CarLock.cfg().compat ~= false
end

--- Configured range in metres ('key' | 'fob' | 'give' | 'compat').
---@param kind string
---@return number
function CarLock.range(kind)
  local ranges = CarLock.cfg().ranges
  local value = type(ranges) == 'table' and tonumber(ranges[kind]) or nil
  if not value or value <= 0 then value = DEFAULT_RANGES[kind] or 5.0 end
  return value + 0.0
end

--- Temporary key lifetime in hours (default 24, at least 0.05 = 3 minutes).
---@return number
function CarLock.tempHours()
  local hours = tonumber(CarLock.cfg().tempKeyHours) or 24
  if hours < 0.05 then hours = 0.05 end
  return hours
end

---------------------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------------------

--- Item name of a Config.CarLock.items entry ('key', 'fob', 'lockpick', ...); for unknown
--- entries the value itself is returned (profiles may name items directly).
---@param kind string
---@return string|nil
function CarLock.itemName(kind)
  if type(kind) ~= 'string' or kind == '' then return nil end
  local items = CarLock.cfg().items
  local name = type(items) == 'table' and items[kind] or nil
  if type(name) == 'string' and name ~= '' then return name end
  return DEFAULT_ITEMS[kind] or kind
end

--- Physical key kind ('key' | 'fob') of an item name, nil for other items.
---@param name string
---@return 'key'|'fob'|nil
function CarLock.keyKindOfItem(name)
  if type(name) ~= 'string' then return nil end
  if name == CarLock.itemName('key') then return 'key' end
  if name == CarLock.itemName('fob') then return 'fob' end
  return nil
end

--- Both physical key item names: { key = 'vehicle_key', fob = 'vehicle_fob' }.
---@return table
function CarLock.keyItems()
  return { key = CarLock.itemName('key'), fob = CarLock.itemName('fob') }
end

--- Item label shown on a key: "Vehicle key · ABC123" / "Key fob · ABC123".
---@param kind 'key'|'fob'
---@param plate string
---@return string
function CarLock.keyLabel(kind, plate)
  if kind == 'fob' then return L('Key fob · {plate}', { plate = plate }) end
  return L('Vehicle key · {plate}', { plate = plate })
end

---------------------------------------------------------------------------------------
-- Profiles
---------------------------------------------------------------------------------------

local modelIndex = nil   -- { [hash] = profileName }, built on first use

local function toSignedHash(value)
  local n = tonumber(value)
  if not n then return nil end
  n = math.floor(n) % 4294967296
  if n > 2147483647 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function hashOf(model)
  if type(model) == 'number' then return toSignedHash(model) end
  if type(model) ~= 'string' or model == '' then return nil end
  local n = tonumber(model)
  if n then return toSignedHash(n) end
  return toSignedHash(joaat(model:lower()))
end

local function buildModelIndex()
  local index = {}
  local byModel = CarLock.cfg().profileByModel
  if type(byModel) == 'table' then
    for model, profile in pairs(byModel) do
      local hash = hashOf(model)
      if hash and type(profile) == 'string' then index[hash] = profile end
    end
  end
  modelIndex = index
  return index
end

--- Forget the model index (call after editing Config.CarLock.profileByModel at runtime).
function CarLock.resetProfiles()
  modelIndex = nil
end

--- Profile table by name (falls back to 'standard', then to a built-in default).
---@param name string|nil
---@return string name, table profile
function CarLock.profile(name)
  local profiles = CarLock.cfg().profiles
  profiles = type(profiles) == 'table' and profiles or {}
  if type(name) == 'string' and type(profiles[name]) == 'table' then return name, profiles[name] end
  if type(profiles.standard) == 'table' then return 'standard', profiles.standard end
  return 'standard', DEFAULT_PROFILE
end

--- Security profile of a vehicle: model override > class > 'standard'.
---@param modelNameOrHash string|number|nil spawn name or model hash
---@param class number|nil GTA vehicle class (0-22)
---@return string name, table profile
function CarLock.profileOf(modelNameOrHash, class)
  local index = modelIndex or buildModelIndex()
  local hash = hashOf(modelNameOrHash)
  if hash and index[hash] then return CarLock.profile(index[hash]) end
  class = tonumber(class)
  local byClass = CarLock.cfg().profileByClass
  if class and type(byClass) == 'table' then
    local name = byClass[math.floor(class)]
    if type(name) == 'string' then return CarLock.profile(name) end
  end
  return CarLock.profile('standard')
end

--- 'key' | 'fob': the physical key a profile uses (profile.keyItem).
---@param profile table|string|nil
---@return 'key'|'fob'
function CarLock.keyKindOf(profile)
  if type(profile) == 'string' then
    local _, p = CarLock.profile(profile)
    profile = p
  end
  if type(profile) == 'table' and profile.keyItem == 'fob' then return 'fob' end
  return 'key'
end

--- Item name of a profile's physical key.
---@param profile table|string|nil
---@return string
function CarLock.keyItemOf(profile)
  return CarLock.itemName(CarLock.keyKindOf(profile))
end

--- Lock range of a profile: fob range for remote profiles, key range otherwise.
---@param profile table|nil
---@return number
function CarLock.lockRange(profile)
  if type(profile) == 'table' and profile.remote == true then return CarLock.range('fob') end
  return CarLock.range('key')
end

---------------------------------------------------------------------------------------
-- Key mode
---------------------------------------------------------------------------------------

local KEY_MODES = { flexible = true, limited = true, virtual = true }

--- Configured key policy: 'flexible' | 'limited' | 'virtual' (docs/CARLOCK.md §1).
--- Older values: 'physical' / 'auto' / anything unknown = 'flexible'. The storage that results
--- (key items or not) is CarLock.resolveMode / server NZ.CarLock.mode(): item modes fall back
--- to virtual keys without an inventory that stores metadata.
---@return 'flexible'|'limited'|'virtual'
function CarLock.keyMode()
  local mode = CarLock.cfg().keyMode
  if type(mode) == 'string' and KEY_MODES[mode:lower()] then return mode:lower() end
  return 'flexible'
end

--- Effective key storage for a given inventory capability: 'physical' (key / fob items:
--- flexible and limited) or 'virtual'. Item modes fall back to 'virtual' when the inventory
--- cannot store item metadata.
---@param supportsMetadata boolean
---@return 'physical'|'virtual'
function CarLock.resolveMode(supportsMetadata)
  if CarLock.keyMode() == 'virtual' then return 'virtual' end
  if supportsMetadata then return 'physical' end
  return 'virtual'
end

--- Do owners / shared players / fleet members always have a key in this mode?
---@param mode 'physical'|'virtual'
---@return boolean
function CarLock.ownerHasKey(mode)
  local value = CarLock.cfg().ownerHasKey
  if value == nil then return mode ~= 'physical' end
  return value == true
end

---------------------------------------------------------------------------------------
-- Ignition bypass rules (model / class part; jobs are checked by the server)
---------------------------------------------------------------------------------------

local bypassModelIndex = nil

--- Does this model / class start without a key (Config.CarLock.ignition)?
---@param modelNameOrHash string|number|nil
---@param class number|nil
---@return boolean
function CarLock.ignitionBypass(modelNameOrHash, class)
  local ignition = CarLock.cfg().ignition
  if type(ignition) ~= 'table' then return false end
  if ignition.requireKey == false then return true end
  class = tonumber(class)
  if class and type(ignition.bypassClasses) == 'table' then
    for _, c in ipairs(ignition.bypassClasses) do
      if tonumber(c) == class then return true end
    end
  end
  if not bypassModelIndex then
    bypassModelIndex = {}
    for k, v in pairs(type(ignition.bypassModels) == 'table' and ignition.bypassModels or {}) do
      -- list ({ 'bmx' }) or set ({ bmx = true })
      local model = type(k) == 'number' and v or k
      local hash = hashOf(model)
      if hash and v ~= false then bypassModelIndex[hash] = true end
    end
  end
  local hash = hashOf(modelNameOrHash)
  return hash ~= nil and bypassModelIndex[hash] == true
end

---------------------------------------------------------------------------------------
-- Hotwire method of a vehicle (Config.CarLock.hotwiring; docs/CARLOCK.md §8)
---------------------------------------------------------------------------------------

local function listHas(list, hash, class)
  if type(list) ~= 'table' then return false end
  for k, v in pairs(list) do
    local entry = type(k) == 'number' and v or k
    if class ~= nil and tonumber(entry) == class then return true end
    if hash ~= nil and type(entry) == 'string' and hashOf(entry) == hash then return true end
  end
  return false
end

--- Hotwire method of a vehicle: 'reader' (signal reader: hotwiring.readerClasses /
--- readerModels), 'wires' (hotwiring.style = 'wires', or a model in wireModels), else the
--- security profile's own method ('skillcheck' | 'progress' | 'hack').
---@param modelNameOrHash string|number|nil
---@param class number|nil
---@param profile table|nil
---@return string
function CarLock.hotwireMethodOf(modelNameOrHash, class, profile)
  local hw = CarLock.cfg().hotwiring
  hw = type(hw) == 'table' and hw or {}
  local hash = hashOf(modelNameOrHash)
  class = tonumber(class)
  if listHas(hw.wireModels, hash, nil) then return 'wires' end
  if listHas(hw.readerModels, hash, nil) then return 'reader' end
  if hw.style == 'wires' then
    if class ~= nil and listHas(hw.readerClasses, nil, class) then return 'reader' end
    return 'wires'
  end
  local method = type(profile) == 'table' and type(profile.hotwire) == 'table' and profile.hotwire.method or nil
  if method == 'skillcheck' or method == 'progress' or method == 'hack' then return method end
  return 'skillcheck'
end

---------------------------------------------------------------------------------------
-- Admin key settings (docs/CARLOCK.md §15): a schema over Config.CarLock. The server keeps
-- the admin's values in the database (nz_settings 'carlock_settings') and writes them INTO
-- Config.CarLock (every reader sees them at once); clients get the same values through
-- GlobalState.nzKeySettings. A value nobody set is the config file's.
---------------------------------------------------------------------------------------

-- type: bool | number (min, max, step, integer) | enum (options) | color ('#rrggbb') |
-- classes (GTA classes 0-22) | models (spawn names) | strings (short names, e.g. jobs)
local SETTINGS = {
  -- Keys
  { id = 'keys.mode', tab = 'keys', type = 'enum', path = 'keyMode', options = { 'flexible', 'limited', 'virtual' },
    label = 'Key mode', description = 'Flexible: key items, sharing makes a copy. Limited: a fixed set of key items per vehicle, sharing gives yours away. Virtual: no items, the server issues access.' },
  { id = 'keys.limitedKeys', tab = 'keys', type = 'number', path = 'limitedKeys', min = 1, max = 10, step = 1, integer = true,
    label = 'Limited: keys per vehicle', description = 'Starting set of each vehicle in the limited key mode.' },
  { id = 'keys.giveKeyOnRetrieve', tab = 'keys', type = 'bool', path = 'giveKeyOnRetrieve',
    label = 'Cut a key on retrieval', description = 'Flexible mode: a garage retrieval cuts a key when the owner has none.' },
  { id = 'keys.ownerHasKey', tab = 'keys', type = 'enum', path = 'ownerHasKey', options = { 'auto', 'yes', 'no' },
    label = 'Owners always have a key', description = 'Auto: yes with virtual keys, no with key items (owners need the item).' },
  { id = 'keys.tempKeyHours', tab = 'keys', type = 'number', path = 'tempKeyHours', min = 0.05, max = 720, step = 0.05,
    label = 'Temporary keys last (hours)', description = 'Hotwired, robbed, staff and other scripts\' keys.' },
  { id = 'keys.defaultFob', tab = 'keys', type = 'enum', path = 'fob.defaultDesign', optionsPath = 'fob.designs',
    label = 'Default fob design', description = 'Fob drawn for keys that have no design of their own.' },
  { id = 'keys.remoteRange', tab = 'keys', type = 'number', path = 'ranges.fob', min = 5, max = 150, step = 1,
    label = 'Remote range (m)', description = 'Fobs lock, unlock and start from this far.' },
  { id = 'keys.keyRange', tab = 'keys', type = 'number', path = 'ranges.key', min = 1, max = 20, step = 0.5,
    label = 'Key range (m)', description = 'A plain key works from this far.' },
  { id = 'keys.giveRange', tab = 'keys', type = 'number', path = 'ranges.give', min = 1, max = 10, step = 0.5,
    label = 'Hand-over range (m)', description = 'Players this close can be given a key.' },
  { id = 'keys.lockPrefer', tab = 'keys', type = 'enum', path = 'lockPrefer', options = { 'nearest', 'owned', 'last' },
    label = 'Lock selection', description = 'Which vehicle the lock key picks when several are in range.' },
  { id = 'keys.maxShares', tab = 'keys', type = 'number', path = 'maxVirtualKeys', min = 1, max = 50, step = 1, integer = true,
    label = 'Virtual shares per vehicle', description = 'Players one owner can give a virtual key of one vehicle.' },
  { id = 'keys.maxCopies', tab = 'keys', type = 'number', path = 'sharing.maxKeys', min = 1, max = 50, step = 1, integer = true,
    label = 'Key copies per vehicle', description = 'Flexible mode: copies of the current locks that may exist.' },
  { id = 'keys.shareHours', tab = 'keys', type = 'number', path = 'sharing.hours', min = 0, max = 720, step = 1,
    label = 'Shared keys last (hours)', description = '0 = until revoked.' },
  { id = 'keys.trackWho', tab = 'keys', type = 'enum', path = 'tracker.who', options = { 'real', 'any', 'owner' },
    label = 'Who can track', description = 'Real: owners, shares and real keys. Any: every key. Owner: owners and garage shares only.' },
  { id = 'keys.keyless', tab = 'keys', type = 'bool', path = 'keyless.enabled',
    label = 'Keyless entry and exit', description = 'Fob keys unlock on entry and lock when the player walks away.' },
  { id = 'keys.keylessMin', tab = 'keys', type = 'number', path = 'keyless.minDistance', min = 1, max = 50, step = 0.5,
    label = 'Keyless: shortest lock distance (m)', description = 'Players cannot pick a shorter auto-lock distance.' },
  { id = 'keys.keylessMax', tab = 'keys', type = 'number', path = 'keyless.maxDistance', min = 2, max = 100, step = 0.5,
    label = 'Keyless: longest lock distance (m)', description = 'Players cannot pick a longer auto-lock distance.' },

  -- Ground keys
  { id = 'ground.enabled', tab = 'ground', type = 'bool', path = 'ground.enabled',
    label = 'Keys on the ground', description = 'Drop, throw and toss key items; anyone can pick them up.' },
  { id = 'ground.animateDrops', tab = 'ground', type = 'bool', path = 'ground.animateDrops',
    label = 'Animate drops', description = 'Players play an animation when they drop or throw a key.' },
  { id = 'ground.persist', tab = 'ground', type = 'bool', path = 'ground.persist',
    label = 'Keep after a restart', description = 'Keys on the ground survive a server restart (database).' },
  { id = 'ground.removeAfter', tab = 'ground', type = 'number', path = 'ground.removeAfter', min = 0, max = 10080, step = 1, integer = true,
    label = 'Remove after (minutes)', description = 'An untouched key on the ground is gone after this long. 0 = never.' },
  { id = 'ground.pickupRange', tab = 'ground', type = 'number', path = 'ground.pickupRange', min = 0.5, max = 5, step = 0.1,
    label = 'Pick-up range (m)', description = 'Distance from the player to a key on the ground.' },
  { id = 'ground.throwRange', tab = 'ground', type = 'number', path = 'ground.throwRange', min = 2, max = 20, step = 0.5,
    label = 'Throw range (m)', description = 'Keys can be thrown to a player this far away.' },
  { id = 'ground.catchWindow', tab = 'ground', type = 'number', path = 'ground.catchWindow', min = 500, max = 5000, step = 100, integer = true,
    label = 'Catch window (ms)', description = 'Time to catch a thrown key before it falls.' },
  { id = 'ground.markerStyle', tab = 'ground', type = 'enum', path = 'ground.marker.style', options = { 'none', 'chevron', 'ring', 'dot' },
    label = 'Marker style', description = 'Shape drawn above keys on the ground.' },
  { id = 'ground.markerColor', tab = 'ground', type = 'color', path = 'ground.marker.color',
    label = 'Marker colour', description = 'Colour of the marker.' },
  { id = 'ground.markerSize', tab = 'ground', type = 'number', path = 'ground.marker.size', min = 0.05, max = 2, step = 0.05,
    label = 'Marker size', description = 'Size of the marker (m).' },
  { id = 'ground.markerHeight', tab = 'ground', type = 'number', path = 'ground.marker.height', min = 0, max = 2, step = 0.05,
    label = 'Marker height', description = 'Height of the marker above the key (m).' },

  -- Vehicles
  { id = 'vehicles.requireKey', tab = 'vehicles', type = 'bool', path = 'ignition.requireKey',
    label = 'Engine needs a key', description = 'Without a key the engine stays off.' },
  { id = 'vehicles.keepEngineRunning', tab = 'vehicles', type = 'bool', path = 'ignition.keepEngineRunning',
    label = 'Engine may keep running', description = 'Players may leave the engine running when they get out (their own setting).' },
  { id = 'vehicles.allowRunningEngine', tab = 'vehicles', type = 'bool', path = 'ignition.allowRunningEngine',
    label = 'Drive a running car without a key', description = 'A car left running can be driven away.' },
  { id = 'vehicles.bypassClasses', tab = 'vehicles', type = 'classes', path = 'ignition.bypassClasses',
    label = 'Classes without a key', description = 'These classes start without a key (13 = cycles).' },
  { id = 'vehicles.bypassModels', tab = 'vehicles', type = 'models', path = 'ignition.bypassModels',
    label = 'Models without a key', description = 'These models start without a key.' },
  { id = 'vehicles.highendClasses', tab = 'vehicles', type = 'classes', path = 'profileByClass',
    label = 'High-end classes', description = 'Classes that use the high-end profile (fob, remote range, tracker).' },
  { id = 'vehicles.lockNotify', tab = 'vehicles', type = 'bool', path = 'lockNotify',
    label = 'Lock notifications', description = 'Show "Vehicle locked / unlocked".' },
  { id = 'vehicles.immobiliser', tab = 'vehicles', type = 'bool', path = 'immobiliser.enabled',
    label = 'Immobilisers', description = 'Standard immobilisers block hotwiring; Ghost asks for a PIN.' },

  -- Lockpicking
  { id = 'lockpick.style', tab = 'lockpicking', type = 'enum', path = 'lockpicking.style', options = { 'skillcheck', 'pins' },
    label = 'Lock picking', description = 'Skill checks, or the five-pin lock (players whose client cannot show the pin lock get skill checks).' },
  { id = 'lockpick.pins', tab = 'lockpicking', type = 'number', path = 'lockpicking.pins', min = 3, max = 7, step = 1, integer = true,
    label = 'Pins', description = 'Pins of the pin lock.' },
  { id = 'lockpick.snapChance', tab = 'lockpicking', type = 'number', path = 'lockpicking.snapChance', min = 0, max = 100, step = 1, integer = true,
    label = 'Snap chance (%)', description = 'Chance the pick snaps when a pin is overset.' },
  { id = 'lockpick.alarmOnSnap', tab = 'lockpicking', type = 'bool', path = 'lockpicking.alarmOnSnap',
    label = 'Alarm on a snapped pick', description = 'A snapped pick sets the alarm off.' },

  -- Hotwiring
  { id = 'hotwire.style', tab = 'hotwiring', type = 'enum', path = 'hotwiring.style', options = { 'profile', 'wires' },
    label = 'Hotwiring', description = 'Each profile\'s method, or splicing wires (players whose client cannot show the minigame get the profile\'s method, but still need the reader / kit).' },
  { id = 'hotwire.kitRequired', tab = 'hotwiring', type = 'bool', path = 'hotwiring.kitRequired',
    label = 'Wires need a hotwire kit', description = 'Splicing wires needs the hotwire_kit item (also when the client falls back to another minigame).' },
  { id = 'hotwire.readerClasses', tab = 'hotwiring', type = 'classes', path = 'hotwiring.readerClasses',
    label = 'Classes that need the reader', description = 'Only with Hotwiring = wires: these classes are started with the signal reader.' },
  { id = 'hotwire.readerModels', tab = 'hotwiring', type = 'models', path = 'hotwiring.readerModels',
    label = 'Models that need the reader', description = 'Model overrides: always the signal reader.' },
  { id = 'hotwire.wireModels', tab = 'hotwiring', type = 'models', path = 'hotwiring.wireModels',
    label = 'Models with wires', description = 'Model overrides: always wires.' },

  -- NPC keys
  { id = 'npc.robbery', tab = 'npc', type = 'bool', path = 'npc.robbery',
    label = 'Hold-ups', description = 'Aim at an NPC driver to get the key.' },
  { id = 'npc.handover', tab = 'npc', type = 'number', path = 'npc.reactions.handover', min = 0, max = 100, step = 1, integer = true,
    label = 'Hands the key over', description = 'Weight of this reaction.' },
  { id = 'npc.drop', tab = 'npc', type = 'number', path = 'npc.reactions.drop', min = 0, max = 100, step = 1, integer = true,
    label = 'Drops the key and runs', description = 'Weight of this reaction.' },
  { id = 'npc.fight', tab = 'npc', type = 'number', path = 'npc.reactions.fight', min = 0, max = 100, step = 1, integer = true,
    label = 'Fights back', description = 'Weight of this reaction.' },
  { id = 'npc.flee', tab = 'npc', type = 'number', path = 'npc.reactions.flee', min = 0, max = 100, step = 1, integer = true,
    label = 'Drives away', description = 'Weight of this reaction.' },
  { id = 'npc.policeRequired', tab = 'npc', type = 'number', path = 'npc.policeRequired', min = 0, max = 50, step = 1, integer = true,
    label = 'Police needed', description = 'On-duty officers needed for a hold-up.' },
  { id = 'npc.dispatchDelay', tab = 'npc', type = 'number', path = 'npc.dispatchDelay', min = 0, max = 600, step = 1, integer = true,
    label = 'Dispatch delay (s)', description = 'Seconds before the police alert of a hold-up goes out.' },
  { id = 'npc.robTime', tab = 'npc', type = 'number', path = 'npc.robTime', min = 500, max = 30000, step = 100, integer = true,
    label = 'Hand-over time (ms)', description = 'Aiming time before the key is handed over.' },
  { id = 'npc.alertChance', tab = 'npc', type = 'number', path = 'npc.alertChance', min = 0, max = 100, step = 1, integer = true,
    label = 'Alert chance (%)', description = 'Chance a hold-up alerts the police.' },
  { id = 'npc.cooldown', tab = 'npc', type = 'number', path = 'npc.cooldown', min = 0, max = 3600, step = 1, integer = true,
    label = 'Cooldown (s)', description = 'Seconds between hold-ups per player.' },
  { id = 'npc.deadDriverKeys', tab = 'npc', type = 'bool', path = 'npc.deadDriverKeys',
    label = 'Search dead drivers', description = 'The key can be taken from the original driver\'s body.' },

  -- Job vehicles
  { id = 'jobs.bypass', tab = 'jobs', type = 'bool', path = 'ignition.bypassJobVehicles',
    label = 'Fleet vehicles start without a key', description = 'On-duty job / gang members in their fleet vehicles.' },
  { id = 'jobs.keyHours', tab = 'jobs', type = 'number', path = 'jobVehicles.keyHours', min = 0, max = 720, step = 0.5,
    label = 'Spawner keys last (hours)', description = '0 = like other temporary keys.' },
  { id = 'jobs.assistJobs', tab = 'jobs', type = 'strings', path = 'npc.assistJobs',
    label = 'Jobs that can request vehicles', description = 'These jobs (on duty) ask NPC drivers for their vehicle.' },

  -- Security
  { id = 'security.trustUnsignedKeys', tab = 'security', type = 'bool', path = 'trustUnsignedKeys',
    label = 'Accept unsigned key items', description = 'Not recommended: anyone able to write item metadata could make keys.' },
  { id = 'security.compat', tab = 'security', type = 'bool', path = 'compat',
    label = 'Other scripts\' key events', description = 'Answer the key events of other key resources.' },
  { id = 'security.compatAmbient', tab = 'security', type = 'bool', path = 'compatAmbient',
    label = 'Client events on traffic cars', description = 'Other scripts\' client events may give keys of NPC cars.' },
  { id = 'security.clientGiveKey', tab = 'security', type = 'bool', path = 'clientGiveKeyExport',
    label = 'Client GiveKey export', description = 'Client code may ask for temporary keys.' },
  { id = 'security.pinAttempts', tab = 'security', type = 'number', path = 'immobiliser.pinAttempts', min = 1, max = 10, step = 1, integer = true,
    label = 'Ghost PIN attempts', description = 'Wrong PINs before the alarm and the cooldown.' },
  { id = 'security.pinCooldown', tab = 'security', type = 'number', path = 'immobiliser.pinCooldown', min = 10, max = 3600, step = 5, integer = true,
    label = 'Ghost PIN cooldown (s)', description = 'No PIN attempts this long after too many wrong ones.' },
  { id = 'security.pinSession', tab = 'security', type = 'number', path = 'immobiliser.pinSession', min = 30, max = 86400, step = 30, integer = true,
    label = 'Ghost PIN valid (s)', description = 'A correct PIN stays valid this long for that driver.' },
  { id = 'security.alarmAlertChance', tab = 'security', type = 'number', path = 'alarm.alertChance', min = 0, max = 100, step = 1, integer = true,
    label = 'Car alarm alert chance (%)', description = 'Chance a car alarm alerts the police.' },
}

local SETTING_TABS = { 'keys', 'ground', 'vehicles', 'lockpicking', 'hotwiring', 'npc', 'jobs', 'security' }
local TAB_LABELS = {
  keys = 'Keys', ground = 'Ground keys', vehicles = 'Vehicles', lockpicking = 'Lockpicking',
  hotwiring = 'Hotwiring', npc = 'NPC keys', jobs = 'Job vehicles', security = 'Security',
}

local settingById = {}
for _, entry in ipairs(SETTINGS) do settingById[entry.id] = entry end

local function splitPath(path)
  local parts = {}
  for part in path:gmatch('[^%.]+') do parts[#parts + 1] = part end
  return parts
end

local function deepCopy(v)
  if type(v) ~= 'table' then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end

local function readPath(root, path)
  local node = root
  for _, part in ipairs(splitPath(path)) do
    if type(node) ~= 'table' then return nil end
    node = node[part]
  end
  return node
end

local function writePath(root, path, value)
  local parts = splitPath(path)
  local node = root
  for i = 1, #parts - 1 do
    if type(node[parts[i]]) ~= 'table' then node[parts[i]] = {} end
    node = node[parts[i]]
  end
  node[parts[#parts]] = value
end

-- Settings whose config shape differs from the setting value.
local CONVERT = {
  ['keys.ownerHasKey'] = {
    get = function(v) if v == true then return 'yes' elseif v == false then return 'no' end return 'auto' end,
    set = function(v) if v == 'yes' then return true elseif v == 'no' then return false end return nil end,
  },
  ['keys.mode'] = {
    get = function() return CarLock.keyMode() end,
    set = function(v) return v end,
  },
  ['vehicles.highendClasses'] = {
    -- profileByClass { [class] = 'highend' }: the classes set to 'highend' (other entries kept)
    get = function(map)
      local out = {}
      for class, name in pairs(type(map) == 'table' and map or {}) do
        if name == 'highend' and tonumber(class) then out[#out + 1] = math.tointeger(tonumber(class)) end
      end
      table.sort(out)
      return out
    end,
    set = function(list, current)
      local out = {}
      for class, name in pairs(type(current) == 'table' and current or {}) do
        if name ~= 'highend' then out[class] = name end
      end
      for _, class in ipairs(list) do out[class] = 'highend' end
      return out
    end,
  },
  ['vehicles.bypassModels'] = {
    get = function(v)
      local out = {}
      for k, x in pairs(type(v) == 'table' and v or {}) do
        local model = type(k) == 'number' and x or k
        if type(model) == 'string' and x ~= false then out[#out + 1] = model end
      end
      table.sort(out)
      return out
    end,
    set = function(v) return v end,
  },
}

local pristine = nil   -- [id] = config file value (setting shape), captured before any override

local function capturePristine()
  if pristine then return pristine end
  pristine = {}
  local cfg = CarLock.cfg()
  for _, entry in ipairs(SETTINGS) do
    local raw = readPath(cfg, entry.path)
    local conv = CONVERT[entry.id]
    pristine[entry.id] = deepCopy(conv and conv.get(raw) or raw)
  end
  return pristine
end

local function optionsOf(entry)
  if entry.options then return entry.options end
  if entry.optionsPath then
    local list = readPath(CarLock.cfg(), entry.optionsPath)
    if type(list) == 'table' then
      local out = {}
      for _, v in ipairs(list) do if type(v) == 'string' then out[#out + 1] = v end end
      return out
    end
  end
  return {}
end

local function cleanList(value, maxItems, check)
  if type(value) ~= 'table' then return nil end
  local out, seen = {}, {}
  for _, v in ipairs(value) do
    local item = check(v)
    if item == nil then return nil end
    if not seen[item] then
      seen[item] = true
      out[#out + 1] = item
      if #out > maxItems then return nil end
    end
  end
  return out
end

--- Validate one admin setting value. Returns ok, normalized value | error text (English, for L()).
---@param id string
---@param value any
---@return boolean ok, any valueOrError
function CarLock.validateSetting(id, value)
  local entry = settingById[id]
  if not entry then return false, 'Unknown setting' end
  local t = entry.type
  if t == 'bool' then
    if type(value) ~= 'boolean' then return false, 'Expected on / off' end
    return true, value
  elseif t == 'number' then
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return false, 'Expected a number' end
    if (entry.min and n < entry.min) or (entry.max and n > entry.max) then return false, 'Out of range' end
    if entry.integer then
      if n ~= math.floor(n) then return false, 'Expected a whole number' end
      n = math.tointeger(n)
    end
    return true, n
  elseif t == 'enum' then
    for _, option in ipairs(optionsOf(entry)) do
      if value == option then return true, value end
    end
    return false, 'Unknown option'
  elseif t == 'color' then
    if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then return false, 'Expected a colour (#rrggbb)' end
    return true, value:lower()
  elseif t == 'classes' then
    local list = cleanList(value, 23, function(v)
      local n = tonumber(v)
      if not n or n ~= math.floor(n) or n < 0 or n > 22 then return nil end
      return math.tointeger(n)
    end)
    if not list then return false, 'Expected vehicle classes (0-22)' end
    table.sort(list)
    return true, list
  elseif t == 'models' then
    local list = cleanList(value, 200, function(v)
      if type(v) ~= 'string' or #v > 32 or not v:match('^[%w_%-]+$') then return nil end
      return v:lower()
    end)
    if not list then return false, 'Expected model names' end
    return true, list
  elseif t == 'strings' then
    local list = cleanList(value, 50, function(v)
      if type(v) ~= 'string' or #v > 32 or not v:match('^[%w_%-]+$') then return nil end
      return v
    end)
    if not list then return false, 'Expected names' end
    return true, list
  end
  return false, 'Unknown setting'
end

--- Write admin values into Config.CarLock. Every setting without a valid value goes back to
--- the config file's value (so removing an override restores the default). Returns the
--- values that were applied ({ [id] = value }).
---@param overrides table|nil { [id] = value }
---@return table applied
function CarLock.applySettings(overrides)
  local base = capturePristine()
  overrides = type(overrides) == 'table' and overrides or {}
  local cfg = Config.CarLock
  if type(cfg) ~= 'table' then return {} end
  local applied = {}
  for _, entry in ipairs(SETTINGS) do
    local value = base[entry.id]
    local raw = overrides[entry.id]
    if raw ~= nil then
      local ok, v = CarLock.validateSetting(entry.id, raw)
      if ok then
        value = v
        applied[entry.id] = v
      end
    end
    local conv = CONVERT[entry.id]
    if conv then
      writePath(cfg, entry.path, deepCopy(conv.set(value, readPath(cfg, entry.path))))
    else
      writePath(cfg, entry.path, deepCopy(value))
    end
  end
  -- derived caches: model / class indexes
  CarLock.resetProfiles()
  bypassModelIndex = nil
  return applied
end

--- The schema with current values, for the admin UI (labels translated):
--- { tabs = { { id, label } }, settings = { { id, tab, type, label, description, value,
---   default, overridden, options?, min?, max?, step?, integer? } } }
---@param overrides table|nil the stored admin values
---@return table
function CarLock.settingsSchema(overrides)
  local base = capturePristine()
  overrides = type(overrides) == 'table' and overrides or {}
  local cfg = CarLock.cfg()
  local tabs, list = {}, {}
  for _, tab in ipairs(SETTING_TABS) do tabs[#tabs + 1] = { id = tab, label = L(TAB_LABELS[tab]) } end
  for _, entry in ipairs(SETTINGS) do
    local conv = CONVERT[entry.id]
    local raw = readPath(cfg, entry.path)
    local current = conv and conv.get(raw) or raw
    list[#list + 1] = {
      id = entry.id, tab = entry.tab, type = entry.type,
      label = L(entry.label), description = L(entry.description),
      value = deepCopy(current), default = deepCopy(base[entry.id]),
      overridden = overrides[entry.id] ~= nil,
      options = entry.type == 'enum' and optionsOf(entry) or nil,
      min = entry.min, max = entry.max, step = entry.step, integer = entry.integer,
    }
  end
  return { tabs = tabs, settings = list }
end

--- Every admin setting id (for validation of saves).
---@return string[]
function CarLock.settingIds()
  local out = {}
  for i, entry in ipairs(SETTINGS) do out[i] = entry.id end
  return out
end

-- Clients take the server's admin values (GlobalState.nzKeySettings: { [id] = value }).
if not (type(IsDuplicityVersion) == 'function' and IsDuplicityVersion() == true) then
  local function applyGlobal(value)
    if type(value) == 'table' then CarLock.applySettings(value) end
  end
  local okRead, current = pcall(function() return GlobalState.nzKeySettings end)
  if okRead then applyGlobal(current) end
  if type(AddStateBagChangeHandler) == 'function' then
    AddStateBagChangeHandler('nzKeySettings', 'global', function(_, _, value)
      applyGlobal(value)
      TriggerEvent('nz:client:carlock:settingsChanged')
    end)
  end
end

---------------------------------------------------------------------------------------
-- Per-player settings (docs/CARLOCK.md §16): defaults from Config.CarLock.playerDefaults
---------------------------------------------------------------------------------------

local PLAYER_BOOLS = {
  'keylessUnlock', 'keylessLock', 'engineOnEnter', 'keepEngineRunning', 'fobBeep', 'hints',
  'combinedKeyring', 'groundPrompts', 'alertLock', 'alertEngine', 'alertShare', 'shareRecall',
}
local PLAYER_ENUMS = {
  keyOrder = { recent = true, name = true, plate = true, distance = true },
  units = { metric = true, imperial = true },
}
local PLAYER_DEFAULTS = {
  keylessUnlock = true, keylessLock = true, keylessDistance = 10.0, engineOnEnter = false,
  keepEngineRunning = true, fobBeep = true, hints = true, fobPosition = { x = 0.86, y = 0.72, scale = 1.0 },
  keyOrder = 'recent', combinedKeyring = true, groundPrompts = true, units = 'metric',
  alertLock = true, alertEngine = true, alertShare = true, shareRecall = true,
}

--- Allowed keyless distance (Config.CarLock.keyless.minDistance / maxDistance).
---@return number min, number max
function CarLock.keylessLimits()
  local k = CarLock.cfg().keyless
  k = type(k) == 'table' and k or {}
  local min = tonumber(k.minDistance) or 3.0
  local max = tonumber(k.maxDistance) or 30.0
  if min < 1 then min = 1.0 end
  if max < min then max = min end
  return min + 0.0, max + 0.0
end

local function num01(v, min, max, default)
  local n = tonumber(v)
  if not n or n ~= n then return default end
  if n < min then n = min elseif n > max then n = max end
  return n
end

--- The full per-player settings: `input` fields that are valid, else `base`, else the
--- configured defaults (Config.CarLock.playerDefaults), else built-in defaults.
---@param input table|nil
---@param base table|nil
---@return table
function CarLock.normalizePlayerSettings(input, base)
  input = type(input) == 'table' and input or {}
  base = type(base) == 'table' and base or {}
  local cfgDefaults = CarLock.cfg().playerDefaults
  cfgDefaults = type(cfgDefaults) == 'table' and cfgDefaults or {}
  local function pick(key, valid)
    if valid(input[key]) then return input[key] end
    if valid(base[key]) then return base[key] end
    if valid(cfgDefaults[key]) then return cfgDefaults[key] end
    return PLAYER_DEFAULTS[key]
  end
  local out = {}
  for _, key in ipairs(PLAYER_BOOLS) do
    out[key] = pick(key, function(v) return type(v) == 'boolean' end)
  end
  for key, options in pairs(PLAYER_ENUMS) do
    out[key] = pick(key, function(v) return type(v) == 'string' and options[v] == true end)
  end
  local min, max = CarLock.keylessLimits()
  local dist = pick('keylessDistance', function(v) return tonumber(v) ~= nil end)
  out.keylessDistance = Utils.round(num01(dist, min, max, PLAYER_DEFAULTS.keylessDistance), 1)
  local pos = pick('fobPosition', function(v) return type(v) == 'table' and tonumber(v.x) and tonumber(v.y) end)
  out.fobPosition = {
    x = Utils.round(num01(pos.x, 0, 1, 0.86), 3),
    y = Utils.round(num01(pos.y, 0, 1, 0.72), 3),
    scale = Utils.round(num01(pos.scale, 0.5, 2, 1.0), 2),
  }
  return out
end
