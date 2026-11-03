--[[
  nayzeee-garages — car lock: security profiles and helpers shared by server and client
  (NZ.CarLock). docs/CARLOCK.md §1-3.

  Pure functions over Config.CarLock / Config.Integrations: whether the built-in system is
  active, the security profile of a model / class, item names, ranges, the key mode and the
  key item metadata label. No side effects, no natives besides joaat.
]]

local CarLock = NZ.CarLock

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

--- Is the built-in car lock in charge of keys? Config.CarLock.enabled and
--- Config.Integrations.keys = 'auto' (built-in wins) or 'nayzeee'.
---@return boolean
function CarLock.enabled()
  if CarLock.cfg().enabled ~= true then return false end
  local keys = Config.Integrations and Config.Integrations.keys or 'auto'
  if type(keys) ~= 'string' or keys == '' then keys = 'auto' end
  keys = keys:lower()
  return keys == 'auto' or keys == 'nayzeee'
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

--- Effective key mode for a given inventory capability.
--- 'physical' falls back to 'virtual' when the inventory cannot store item metadata.
---@param supportsMetadata boolean
---@return 'physical'|'virtual'
function CarLock.resolveMode(supportsMetadata)
  local mode = CarLock.cfg().keyMode
  if mode == 'virtual' then return 'virtual' end
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
