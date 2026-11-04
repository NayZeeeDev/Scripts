--[[
  nayzeee-garages — inventory integration (client): NZ.Inventory. docs/CARLOCK.md §4.

  Best-effort item checks for prompts and hints (show "Lockpick" only when the player carries
  one). The server always re-checks with bridge/server/inventory.lua. Same detection order and
  Config.Integrations.inventory values as the server. Every third-party call is protected.
]]

local Inventory = NZ.Inventory
local Utils = NZ.Utils

local ORDER = {
  'ox_inventory', 'qs-inventory-pro', 'qs-inventory', 'codem-inventory', 'tgiann-inventory',
  'origen_inventory', 'core_inventory', 'ps-inventory', 'lj-inventory', 'qb-inventory',
}
local KNOWN = {}
for i = 1, #ORDER do KNOWN[ORDER[i]] = true end

local warned = {}
local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  Utils.debug(('inventory: %s'):format(message))
end

local function started(name)
  return type(name) == 'string' and Utils.resourceStarted(name)
end

local function try(label, fn, ...)
  local res = table.pack(pcall(fn, ...))
  if not res[1] then
    warnOnce(label, ('%s failed: %s'):format(label, tostring(res[2])))
    return false
  end
  return true, table.unpack(res, 2, res.n)
end

--- Sum of counts of `item` in any inventory table (array or keyed by slot / name).
local function countIn(raw, item)
  local total = 0
  if type(raw) ~= 'table' then return 0 end
  for k, v in pairs(raw) do
    if type(v) == 'table' and (v.name == item or (k == item and v.name == nil)) then
      total = total + (tonumber(v.count) or tonumber(v.amount) or 1)
    end
  end
  return total
end

local function qbItems()
  local ok, core = try('qb-core GetCoreObject', function() return exports['qb-core']:GetCoreObject() end)
  if not ok or type(core) ~= 'table' or not core.Functions or not core.Functions.GetPlayerData then return nil end
  local okData, data = try('QBCore GetPlayerData', core.Functions.GetPlayerData)
  return okData and type(data) == 'table' and data.items or nil
end

local function esxItems()
  local ok, esx = try('es_extended getSharedObject', function() return exports.es_extended:getSharedObject() end)
  if not ok or type(esx) ~= 'table' or not esx.GetPlayerData then return nil end
  local okData, data = try('ESX GetPlayerData', esx.GetPlayerData)
  return okData and type(data) == 'table' and data.inventory or nil
end

local function frameworkCount(item)
  if NZ.Framework == 'esx' then return countIn(esxItems(), item) end
  if NZ.Framework == 'qb' or NZ.Framework == 'qbx' then return countIn(qbItems(), item) end
  return 0
end

-- count(item) -> number per inventory
local counters = {
  ox_inventory = function(item)
    local _, n = try('ox_inventory GetItemCount', function() return exports.ox_inventory:GetItemCount(item) end)
    return tonumber(n) or 0
  end,
  ['qs-inventory'] = function(item)
    local _, inv = try('qs-inventory getUserInventory', function() return exports['qs-inventory']:getUserInventory() end)
    return countIn(inv, item)
  end,
  ['qs-inventory-pro'] = function(item)
    local _, inv = try('qs-inventory-pro getUserInventory', function() return exports['qs-inventory-pro']:getUserInventory() end)
    return countIn(inv, item)
  end,
  ['codem-inventory'] = function(item)
    local _, inv = try('codem-inventory GetClientPlayerInventory', function()
      return exports['codem-inventory']:GetClientPlayerInventory()
    end)
    return countIn(inv, item)
  end,
  ['tgiann-inventory'] = function(item)
    local _, n = try('tgiann-inventory GetItemCount', function() return exports['tgiann-inventory']:GetItemCount(item) end)
    return tonumber(n) or 0
  end,
  origen_inventory = function(item)
    local _, n = try('origen_inventory Search', function() return exports.origen_inventory:Search('count', item) end)
    return tonumber(n) or 0
  end,
  core_inventory = function(item)
    local _, n = try('core_inventory getItemCount', function() return exports.core_inventory:getItemCount(item) end)
    return tonumber(n) or 0
  end,
  ['ps-inventory'] = function(item) return countIn(qbItems(), item) end,
  ['lj-inventory'] = function(item) return countIn(qbItems(), item) end,
  ['qb-inventory'] = function(item) return countIn(qbItems(), item) end,
  framework = frameworkCount,
}

---------------------------------------------------------------------------------------
-- CUSTOM (client): return how many `item` the local player carries.
---------------------------------------------------------------------------------------
counters.custom = function(item) -- luacheck: ignore 212
  return 0
end

local function pick()
  local configured = Config.Integrations and Config.Integrations.inventory or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'none' then return nil end
  if configured == 'custom' then return 'custom' end
  if KNOWN[configured] then
    -- forced: that inventory, else the framework items (same as the server)
    if started(configured) then return configured end
  elseif configured ~= 'framework' then
    for i = 1, #ORDER do
      if started(ORDER[i]) then return ORDER[i] end
    end
  end
  if NZ.Framework == 'esx' or NZ.Framework == 'qb' or NZ.Framework == 'qbx' then return 'framework' end
  return nil
end

local current = false   -- false = not resolved yet

--- Inventory in use on this client (same values as the server), or nil.
---@return string|nil
function Inventory.name()
  if current == false then current = pick() end
  return current
end

--- How many `item` the local player carries (best effort).
---@param item string
---@return number
function Inventory.count(item)
  if type(item) ~= 'string' or item == '' then return 0 end
  local name = Inventory.name()
  local fn = name and counters[name]
  if not fn then return 0 end
  local ok, n = pcall(fn, item)
  return ok and (tonumber(n) or 0) or 0
end

--- Does the local player carry at least `count` (default 1) of `item`? Best effort: the
--- server re-checks every action.
---@param item string
---@param count number|nil
---@return boolean
function Inventory.hasItem(item, count)
  return Inventory.count(item) >= (tonumber(count) or 1)
end

-- ox_inventory shows extra metadata fields only when told: show the plate on key items.
local function oxDisplay()
  if Inventory.name() ~= 'ox_inventory' then return end
  try('ox_inventory displayMetadata', function()
    exports.ox_inventory:displayMetadata({ plate = L('Plate') })
  end)
end

local WATCH = {}
for i = 1, #ORDER do WATCH[ORDER[i]] = true end

AddEventHandler('onClientResourceStart', function(resource)
  if resource == NZ.ResourceName then
    CreateThread(function()
      Wait(1000)
      oxDisplay()
    end)
    return
  end
  if WATCH[resource] then
    current = false
    if resource == 'ox_inventory' then
      CreateThread(function()
        Wait(1000)
        oxDisplay()
      end)
    end
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if WATCH[resource] then current = false end
end)
