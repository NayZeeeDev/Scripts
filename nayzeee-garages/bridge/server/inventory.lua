--[[
  nayzeee-garages — inventory integration (server): NZ.Inventory. docs/CARLOCK.md §4.

  One small adapter per inventory resource behind a common API used by the car lock (key /
  fob items with metadata), crime tools, contracts and fake plates. Every third-party call is
  protected (pcall): a missing or broken inventory never throws into the caller, it logs one
  warning and returns false / 0 / {}.

  Config.Integrations.inventory:
    'auto'      first started of ox_inventory, qs-inventory-pro, qs-inventory, codem-inventory,
                tgiann-inventory, origen_inventory, core_inventory, ps-inventory, lj-inventory,
                qb-inventory, then the framework fallback (ps / lj / qs may `provide` qb-inventory,
                so qb-inventory is checked after them)
    '<name>'    force one of the above
    'framework' ESX / QBCore / Qbox player items, no metadata (car lock uses virtual keys)
    'custom'    the CUSTOM adapter below (edit it)
    'none'      no items at all

  Metadata is never matched with an inventory's own metadata filters (ox matches values,
  not keys): items are read by name and compared key by key here.

  Usable items: registerUsable(item, fn(src, item, slot, metadata)) registers through the
  inventory's own path (ox: the 'useNzItem' export named in the item definition, plus the
  framework path for definitions without it; qs / origen: CreateUsableItem; others: the
  framework's usable items). Several paths may fire for one use: they are de-duplicated.
]]

local Inventory = NZ.Inventory
local Utils = NZ.Utils

---------------------------------------------------------------------------------------
-- CUSTOM ADAPTER — edit this for an inventory that is not supported out of the box and set
-- Config.Integrations.inventory = 'custom'. Every function receives the player source.
-- items(src) must return a list of { slot = number|nil, name = string, count = number,
-- metadata = table }. Return true / false from the write functions.
---------------------------------------------------------------------------------------

local CUSTOM = {
  resource = nil,          -- e.g. 'my_inventory' (only used for the started check and logs)
  metadata = false,        -- true when items can carry metadata (enables physical keys)
  items = function(src) -- luacheck: ignore 212
    return {}
  end,
  add = function(src, name, count, metadata) -- luacheck: ignore 212
    return false
  end,
  removeSlot = function(src, name, count, slot) -- luacheck: ignore 212
    return false
  end,
  removeName = function(src, name, count) -- luacheck: ignore 212
    return false
  end,
  setMeta = function(src, name, slot, metadata) -- luacheck: ignore 212
    return false
  end,
  canCarry = function(src, name, count, metadata) -- luacheck: ignore 212
    return true
  end,
  -- usable = function(name, handler) handler(src, name, slot, metadata) end,  -- optional
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local RESOURCE = GetCurrentResourceName()
local REASON = 'nayzeee-garages'
local USE_DEDUPE_MS = 2000

local warned = {}

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] inventory: %s'):format(message))
end

local function started(name)
  return type(name) == 'string' and Utils.resourceStarted(name)
end

--- pcall a third-party function; warn once per label on failure. Returns ok, results...
local function try(label, fn, ...)
  if type(fn) ~= 'function' then return false end
  local res = table.pack(pcall(fn, ...))
  if not res[1] then
    warnOnce('err:' .. label, ('%s failed: %s'):format(label, tostring(res[2])))
    return false
  end
  return true, table.unpack(res, 2, res.n)
end

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  return math.tointeger(src)
end

local function validCount(count)
  count = tonumber(count) or 1
  if count ~= count or count < 1 then return nil end
  return math.tointeger(math.floor(count)) or 1
end

local function validName(name)
  if type(name) ~= 'string' or name == '' or #name > 64 then return nil end
  return name
end

--- One inventory entry -> { slot, name, count, metadata } (nil when unusable).
local function norm(v, slotHint)
  if type(v) ~= 'table' then return nil end
  local name = v.name
  if type(name) ~= 'string' or name == '' then return nil end
  local slot = tonumber(v.slot) or tonumber(v.id) or tonumber(slotHint)
  local count = tonumber(v.count) or tonumber(v.amount) or 1
  local md = v.metadata
  if type(md) ~= 'table' then md = v.info end
  if type(md) ~= 'table' then md = {} end
  return { slot = slot and math.tointeger(slot) or slot, name = name, count = count, metadata = md }
end

--- Any inventory table (array or keyed by slot) -> normalized list.
local function list(raw)
  local out = {}
  if type(raw) ~= 'table' then return out end
  for k, v in pairs(raw) do
    -- tgiann mixes numeric slots with non-item keys: only numeric keys or real entries
    local entry = (type(k) == 'number' or type(v) == 'table') and norm(v, type(k) == 'number' and k or nil) or nil
    if entry then out[#out + 1] = entry end
  end
  table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
  return out
end

local function samePlate(a, b)
  return Utils.plate(a) ~= nil and Utils.plate(a) == Utils.plate(b)
end

--- Key-by-key metadata match (plates compared normalized). nil / empty `want` matches.
local function matches(md, want)
  if type(want) ~= 'table' then return true end
  md = type(md) == 'table' and md or {}
  for k, v in pairs(want) do
    if k == 'plate' then
      if not samePlate(md.plate, v) then return false end
    elseif type(v) ~= 'table' and md[k] ~= v then
      return false
    end
  end
  return true
end

local function copy(t)
  local out = {}
  for k, v in pairs(type(t) == 'table' and t or {}) do out[k] = v end
  return out
end

---------------------------------------------------------------------------------------
-- Framework objects (cached; cross-resource tables are snapshots, refreshed every minute)
---------------------------------------------------------------------------------------

local qbCache = { obj = nil, at = -1e9 }
local function qbCore()
  local now = GetGameTimer()
  if qbCache.obj and now - qbCache.at < 60000 then return qbCache.obj end
  if not started('qb-core') then return nil end
  local ok, core = try('qb-core GetCoreObject', function() return exports['qb-core']:GetCoreObject() end)
  if ok and type(core) == 'table' then
    qbCache.obj, qbCache.at = core, now
  end
  return qbCache.obj
end

local esxCache = nil
local function esxObj()
  if esxCache then return esxCache end
  if not started('es_extended') then return nil end
  local ok, obj = try('es_extended getSharedObject', function() return exports.es_extended:getSharedObject() end)
  if ok and type(obj) == 'table' then esxCache = obj end
  return esxCache
end

local function qbPlayer(src)
  if type(NZ.Bridge.getPlayer) ~= 'function' then return nil end
  local ok, player = pcall(NZ.Bridge.getPlayer, src)
  if ok and type(player) == 'table' and type(player.PlayerData) == 'table' then return player end
  return nil
end

local function qbItems(src)
  local player = qbPlayer(src)
  return list(player and player.PlayerData.items)
end

local function qbSharedItem(name)
  local core = qbCore()
  local items = core and core.Shared and core.Shared.Items
  return type(items) == 'table' and items[name] or nil
end

--- QBCore-style ItemBox popup (qb-inventory, lj-inventory: they do not send one themselves).
local function itemBox(event)
  return function(src, name, action, count)
    local def = qbSharedItem(name)
    if def then TriggerClientEvent(event, src, def, action, count) end
  end
end

--- qb / ps / lj: write info straight into PlayerData (no remove + add, no popups).
local function qbSetInfo(src, slot, md)
  local player = qbPlayer(src)
  local items = player and player.PlayerData.items
  if type(items) ~= 'table' then return false end
  local entry = items[slot]
  if type(entry) ~= 'table' then
    for _, v in pairs(items) do
      if type(v) == 'table' and tonumber(v.slot) == slot then entry = v break end
    end
  end
  if type(entry) ~= 'table' then return false end
  entry.info = md
  local ok = try('SetPlayerData items', function() player.Functions.SetPlayerData('items', items) end)
  return ok
end

---------------------------------------------------------------------------------------
-- Usable-item dispatch (shared by every registration path)
---------------------------------------------------------------------------------------

local handlers = {}       -- [itemName] = fn(src, item, slot, metadata)
local lastUse = {}        -- ['src:item:slot'] = GetGameTimer()

local function dispatch(src, name, slot, metadata, via)
  src = validSrc(src)
  local fn = type(name) == 'string' and handlers[name] or nil
  if not src or not fn then return false end
  slot = tonumber(slot)
  local key = ('%d:%s:%s'):format(src, name, tostring(slot))
  local now = GetGameTimer()
  if lastUse[key] and now - lastUse[key] < USE_DEDUPE_MS then return true end
  lastUse[key] = now
  if math.random(1, 50) == 1 then
    for k, at in pairs(lastUse) do
      if now - at > USE_DEDUPE_MS then lastUse[k] = nil end
    end
  end
  metadata = type(metadata) == 'table' and metadata or {}
  CreateThread(function()
    local ok, err = pcall(fn, src, name, slot and math.tointeger(slot) or slot, metadata)
    if not ok then
      lib.print.error(('[nayzeee-garages] inventory: use of %s (%s) failed: %s'):format(name, tostring(via), tostring(err)))
    end
  end)
  return true
end

--- Normalize the arguments every framework / inventory passes to usable callbacks:
--- (src, itemTable) | (src, itemName, itemTable) | (src, itemName).
local function wrapUse(name, via)
  return function(src, a, b)
    local data = (type(b) == 'table' and b) or (type(a) == 'table' and a) or {}
    local itemName = (type(data.name) == 'string' and data.name) or (type(a) == 'string' and a) or name
    if itemName ~= name then itemName = name end
    local md = data.metadata
    if type(md) ~= 'table' then md = data.info end
    dispatch(src, itemName, data.slot or data.id, md, via)
  end
end

--- Framework usable items (QBCore, Qbox, ESX). Returns true when registered.
local function frameworkUsable(name)
  if NZ.Framework == 'qbx' and started('qbx_core') then
    local ok = try('qbx_core CreateUseableItem', function()
      exports.qbx_core:CreateUseableItem(name, wrapUse(name, 'qbx'))
    end)
    if ok then return true end
  end
  if NZ.Framework == 'qb' or NZ.Framework == 'qbx' then
    local core = qbCore()
    local create = core and core.Functions and core.Functions.CreateUseableItem
    if create then
      local ok = try('QBCore CreateUseableItem', create, name, wrapUse(name, 'qb'))
      if ok then return true end
    end
  end
  if NZ.Framework == 'esx' then
    local esx = esxObj()
    if esx and esx.RegisterUsableItem then
      local ok = try('ESX RegisterUsableItem', esx.RegisterUsableItem, name, wrapUse(name, 'esx'))
      if ok then return true end
    end
  end
  return false
end

local oxExportItems = {}  -- items whose ox definition uses the export (their usedItem event is skipped)

-- ox_inventory item definitions: server = { export = 'nayzeee-garages.useNzItem' }, consume = 0.
-- ox calls (event, item, inventory, slot); only 'usingItem' is acted on (consume = 0 never
-- reaches 'usedItem'). Returning nothing lets the use go on (nothing is consumed).
exports('useNzItem', function(event, item, inventory, slot)
  if event ~= 'usingItem' then return end
  local name = type(item) == 'table' and item.name or nil
  local src = type(inventory) == 'table' and (inventory.id or inventory.player and inventory.player.source) or nil
  if type(name) ~= 'string' or not handlers[name] then return false end
  oxExportItems[name] = true
  local md
  local entry = type(inventory) == 'table' and type(inventory.items) == 'table' and inventory.items[slot] or nil
  if type(entry) == 'table' and entry.name == name then md = entry.metadata end
  if type(md) ~= 'table' then
    local ok, fresh = try('ox_inventory GetSlot', function() return exports.ox_inventory:GetSlot(src, slot) end)
    md = ok and type(fresh) == 'table' and fresh.metadata or {}
  end
  dispatch(src, name, slot, md, 'ox export')
end)

-- ox_inventory raises this (locally) after every confirmed use, also for definitions with
-- consume = 0 and no export. Items already handled by the export above are skipped (the
-- export always runs first); the de-duplication drops a framework-path double.
AddEventHandler('ox_inventory:usedItem', function(playerId, name, slot, metadata)
  if type(source) == 'number' and source > 0 then return end -- never from the network
  if type(name) ~= 'string' or not handlers[name] or oxExportItems[name] then return end
  dispatch(playerId, name, slot, metadata, 'ox event')
end)

---------------------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------------------

local adapters = {}

adapters.ox_inventory = {
  metadata = true,
  items = function(src)
    local _, raw = try('ox_inventory GetInventoryItems', function() return exports.ox_inventory:GetInventoryItems(src) end)
    return list(raw)
  end,
  getSlot = function(src, slot)
    local _, raw = try('ox_inventory GetSlot', function() return exports.ox_inventory:GetSlot(src, slot) end)
    return norm(raw, slot)
  end,
  add = function(src, name, count, md)
    local _, success = try('ox_inventory AddItem', function() return exports.ox_inventory:AddItem(src, name, count, md) end)
    return success == true
  end,
  removeSlot = function(src, name, count, slot)
    local _, success = try('ox_inventory RemoveItem', function() return exports.ox_inventory:RemoveItem(src, name, count, nil, slot) end)
    return success == true
  end,
  removeName = function(src, name, count)
    local _, success = try('ox_inventory RemoveItem', function() return exports.ox_inventory:RemoveItem(src, name, count) end)
    return success == true
  end,
  setMeta = function(src, _, slot, md)
    return (try('ox_inventory SetMetadata', function() exports.ox_inventory:SetMetadata(src, slot, md) end))
  end,
  canCarry = function(src, name, count, md)
    local ok, res = try('ox_inventory CanCarryItem', function() return exports.ox_inventory:CanCarryItem(src, name, count, md) end)
    return ok and res == true
  end,
  -- The 'useNzItem' export (item definition) is always live; this adds the framework path
  -- (Qbox / ESX) for definitions written without an export.
  usable = function(name)
    frameworkUsable(name)
    return true
  end,
}

adapters['qb-inventory'] = {
  metadata = true,
  items = qbItems,
  getSlot = function(src, slot)
    local ok, raw = try('qb-inventory GetItemBySlot', function() return exports['qb-inventory']:GetItemBySlot(src, slot) end)
    if ok and raw then return norm(raw, slot) end
    for _, entry in ipairs(qbItems(src)) do
      if entry.slot == slot then return entry end
    end
    return nil
  end,
  add = function(src, name, count, md)
    local _, success = try('qb-inventory AddItem', function()
      return exports['qb-inventory']:AddItem(src, name, count, false, md, REASON)
    end)
    return success == true
  end,
  removeSlot = function(src, name, count, slot)
    local _, success = try('qb-inventory RemoveItem', function()
      return exports['qb-inventory']:RemoveItem(src, name, count, slot, REASON)
    end)
    return success == true
  end,
  removeName = function(src, name, count)
    local _, success = try('qb-inventory RemoveItem', function()
      return exports['qb-inventory']:RemoveItem(src, name, count, false, REASON)
    end)
    return success == true
  end,
  setMeta = function(src, name, slot, md)
    local ok, res = try('qb-inventory SetItemData', function()
      return exports['qb-inventory']:SetItemData(src, name, 'info', md, slot)
    end)
    if ok and res ~= false then return true end
    return qbSetInfo(src, slot, md)
  end,
  canCarry = function(src, name, count)
    local ok, res = try('qb-inventory CanAddItem', function() return exports['qb-inventory']:CanAddItem(src, name, count) end)
    if not ok then return true end
    return res == true
  end,
  box = itemBox('qb-inventory:client:ItemBox'),
}

--- ps-inventory / lj-inventory (QBCore forks): RemoveItem does not check the slot's item, so
--- NZ.Inventory.removeItem always re-reads the slot first.
local function qbFork(resource, boxEvent)
  return {
    metadata = true,
    items = qbItems,
    getSlot = function(src, slot)
      local ok, raw = try(resource .. ' GetItemBySlot', function() return exports[resource]:GetItemBySlot(src, slot) end)
      if ok and raw then return norm(raw, slot) end
      for _, entry in ipairs(qbItems(src)) do
        if entry.slot == slot then return entry end
      end
      return nil
    end,
    add = function(src, name, count, md)
      local _, success = try(resource .. ' AddItem', function()
        return exports[resource]:AddItem(src, name, count, nil, md, REASON)
      end)
      return success == true
    end,
    removeSlot = function(src, name, count, slot)
      local _, success = try(resource .. ' RemoveItem', function()
        return exports[resource]:RemoveItem(src, name, count, slot)
      end)
      return success == true
    end,
    removeName = function(src, name, count)
      local _, success = try(resource .. ' RemoveItem', function()
        return exports[resource]:RemoveItem(src, name, count)
      end)
      return success == true
    end,
    setMeta = function(src, _, slot, md) return qbSetInfo(src, slot, md) end,
    canCarry = function() return true end,
    box = boxEvent and itemBox(boxEvent) or nil,
  }
end

adapters['ps-inventory'] = qbFork('ps-inventory', nil)            -- sends its own ItemBox
adapters['lj-inventory'] = qbFork('lj-inventory', 'inventory:client:ItemBox')

--- qs-inventory / qs-inventory-pro (same exports under two resource names).
local function quasar(resource)
  return {
    metadata = true,
    items = function(src)
      local _, raw = try(resource .. ' GetInventory', function() return exports[resource]:GetInventory(src) end)
      return list(raw)
    end,
    add = function(src, name, count, md)
      local _, success = try(resource .. ' AddItem', function() return exports[resource]:AddItem(src, name, count, nil, md) end)
      return success == true or success == 1
    end,
    removeSlot = function(src, name, count, slot)
      local _, success = try(resource .. ' RemoveItem', function() return exports[resource]:RemoveItem(src, name, count, slot) end)
      return success == true or success == 1
    end,
    removeName = function(src, name, count)
      local _, success = try(resource .. ' RemoveItem', function() return exports[resource]:RemoveItem(src, name, count) end)
      return success == true or success == 1
    end,
    setMeta = function(src, _, slot, md)
      return (try(resource .. ' SetItemMetadata', function() exports[resource]:SetItemMetadata(src, slot, md) end))
    end,
    canCarry = function(src, name, count)
      local ok, res = try(resource .. ' CanCarryItem', function() return exports[resource]:CanCarryItem(src, name, count) end)
      if not ok then return true end
      return res ~= false
    end,
    usable = function(name)
      local ok = try(resource .. ' CreateUsableItem', function()
        exports[resource]:CreateUsableItem(name, wrapUse(name, resource))
      end)
      return ok or frameworkUsable(name)
    end,
  }
end

adapters['qs-inventory'] = quasar('qs-inventory')
adapters['qs-inventory-pro'] = quasar('qs-inventory-pro')

adapters['codem-inventory'] = {
  metadata = true,
  items = function(src)
    local identifier = type(NZ.Bridge.getIdentifier) == 'function' and NZ.Bridge.getIdentifier(src) or nil
    local _, raw = try('codem-inventory GetInventory', function()
      return exports['codem-inventory']:GetInventory(identifier, src)
    end)
    return list(raw)
  end,
  getSlot = function(src, slot)
    local _, raw = try('codem-inventory GetItemBySlot', function() return exports['codem-inventory']:GetItemBySlot(src, slot) end)
    return norm(raw, slot)
  end,
  add = function(src, name, count, md)
    local _, success = try('codem-inventory AddItem', function() return exports['codem-inventory']:AddItem(src, name, count, nil, md) end)
    return success ~= false and success ~= nil
  end,
  removeSlot = function(src, name, count, slot)
    local _, success = try('codem-inventory RemoveItem', function() return exports['codem-inventory']:RemoveItem(src, name, count, slot) end)
    return success ~= false and success ~= nil
  end,
  removeName = function(src, name, count)
    local _, success = try('codem-inventory RemoveItem', function() return exports['codem-inventory']:RemoveItem(src, name, count) end)
    return success ~= false and success ~= nil
  end,
  setMeta = function(src, _, slot, md)
    return (try('codem-inventory SetItemMetadata', function() exports['codem-inventory']:SetItemMetadata(src, slot, md) end))
  end,
  canCarry = function() return true end, -- no export: AddItem's result decides
}

adapters['tgiann-inventory'] = {
  metadata = true,
  items = function(src)
    local _, raw = try('tgiann-inventory GetPlayerItems', function() return exports['tgiann-inventory']:GetPlayerItems(src) end)
    return list(raw)
  end,
  getSlot = function(src, slot)
    local _, raw = try('tgiann-inventory GetItemBySlot', function() return exports['tgiann-inventory']:GetItemBySlot(src, slot) end)
    return norm(raw, slot)
  end,
  add = function(src, name, count, md)
    local _, success = try('tgiann-inventory AddItem', function()
      return exports['tgiann-inventory']:AddItem(src, name, count, nil, md, false)
    end)
    return success ~= false and success ~= nil
  end,
  removeSlot = function(src, name, count, slot)
    local _, success = try('tgiann-inventory RemoveItem', function()
      return exports['tgiann-inventory']:RemoveItem(src, name, count, slot)
    end)
    return success ~= false and success ~= nil
  end,
  removeName = function(src, name, count)
    local _, success = try('tgiann-inventory RemoveItem', function() return exports['tgiann-inventory']:RemoveItem(src, name, count) end)
    return success ~= false and success ~= nil
  end,
  setMeta = function(src, name, slot, md)
    return (try('tgiann-inventory UpdateItemMetadata', function()
      exports['tgiann-inventory']:UpdateItemMetadata(src, name, slot, md)
    end))
  end,
  canCarry = function(src, name, count)
    local ok, res = try('tgiann-inventory CanCarryItem', function() return exports['tgiann-inventory']:CanCarryItem(src, name, count) end)
    if not ok then return true end
    return res ~= false
  end,
}

adapters.origen_inventory = {
  metadata = true,
  items = function(src)
    local ok, raw = try('origen_inventory getItems', function() return exports.origen_inventory:getItems(src) end)
    if ok and type(raw) == 'table' then return list(raw) end
    local _, inv = try('origen_inventory GetInventory', function() return exports.origen_inventory:GetInventory(src) end)
    if type(inv) == 'table' and type(inv.inventory) == 'table' then inv = inv.inventory end
    return list(inv)
  end,
  add = function(src, name, count, md)
    local _, success = try('origen_inventory addItem', function() return exports.origen_inventory:addItem(src, name, count, md) end)
    return success ~= false and success ~= nil
  end,
  removeSlot = function(src, name, count, slot)
    local _, success = try('origen_inventory removeItem', function()
      return exports.origen_inventory:removeItem(src, name, count, nil, slot)
    end)
    return success ~= false and success ~= nil
  end,
  removeName = function(src, name, count)
    local _, success = try('origen_inventory removeItem', function() return exports.origen_inventory:removeItem(src, name, count) end)
    return success ~= false and success ~= nil
  end,
  setMeta = function(src, _, slot, md)
    return (try('origen_inventory setMetadata', function() exports.origen_inventory:setMetadata(src, slot, md) end))
  end,
  canCarry = function(src, name, count)
    local ok, res = try('origen_inventory canCarryItem', function() return exports.origen_inventory:canCarryItem(src, name, count) end)
    if not ok then return true end
    return res ~= false
  end,
  usable = function(name)
    local ok = try('origen_inventory CreateUseableItem', function()
      exports.origen_inventory:CreateUseableItem(name, wrapUse(name, 'origen_inventory'))
    end)
    return ok or frameworkUsable(name)
  end,
}

adapters.core_inventory = {
  metadata = true,
  items = function(src)
    local _, raw = try('core_inventory getInventory', function() return exports.core_inventory:getInventory(src) end)
    if type(raw) == 'table' and type(raw.items) == 'table' then raw = raw.items end
    return list(raw)
  end,
  add = function(src, name, count, md)
    local _, success = try('core_inventory addItem', function() return exports.core_inventory:addItem(src, name, count, md) end)
    return success ~= false and success ~= nil
  end,
  -- removeItemExact semantics differ between versions: NZ.Inventory.removeItem verifies the
  -- slot afterwards.
  removeSlot = function(src, _, count, slot)
    local ok = try('core_inventory removeItemExact', function() return exports.core_inventory:removeItemExact(src, slot, count) end)
    return ok
  end,
  removeName = function(src, name, count)
    local _, success = try('core_inventory removeItem', function() return exports.core_inventory:removeItem(src, name, count) end)
    return success ~= false
  end,
  setMeta = function(src, _, slot, md)
    return (try('core_inventory setMetadata', function() exports.core_inventory:setMetadata(src, slot, md) end))
  end,
  canCarry = function(src, name, count)
    local ok, res = try('core_inventory canCarry', function() return exports.core_inventory:canCarry(src, name, count) end)
    if not ok then return true end
    return res ~= false
  end,
  verifyRemoval = true,
}

--- Framework fallback: player items without metadata (ESX default inventory, QBCore player
--- functions). Physical keys need metadata, so the car lock switches to virtual keys.
adapters.framework = {
  metadata = false,
  items = function(src)
    if NZ.Framework == 'esx' then
      local esx = esxObj()
      local ok, xPlayer = try('ESX GetPlayerFromId', function() return esx and esx.GetPlayerFromId(src) end)
      if not ok or type(xPlayer) ~= 'table' or not xPlayer.getInventory then return {} end
      local _, inv = try('xPlayer.getInventory', function() return xPlayer.getInventory() end)
      local out = {}
      for _, v in pairs(type(inv) == 'table' and inv or {}) do
        local entry = norm(v)
        if entry and entry.count > 0 then
          entry.slot = nil
          out[#out + 1] = entry
        end
      end
      return out
    end
    return qbItems(src)
  end,
  add = function(src, name, count)
    if NZ.Framework == 'esx' then
      local esx = esxObj()
      local ok, xPlayer = try('ESX GetPlayerFromId', function() return esx and esx.GetPlayerFromId(src) end)
      if not ok or type(xPlayer) ~= 'table' or not xPlayer.addInventoryItem then return false end
      return (try('xPlayer.addInventoryItem', function() xPlayer.addInventoryItem(name, count) end))
    end
    local player = qbPlayer(src)
    local fn = player and player.Functions and player.Functions.AddItem
    if not fn then return false end
    local _, res = try('Player.Functions.AddItem', fn, name, count)
    return res ~= false
  end,
  removeName = function(src, name, count)
    if NZ.Framework == 'esx' then
      local esx = esxObj()
      local ok, xPlayer = try('ESX GetPlayerFromId', function() return esx and esx.GetPlayerFromId(src) end)
      if not ok or type(xPlayer) ~= 'table' or not xPlayer.removeInventoryItem then return false end
      return (try('xPlayer.removeInventoryItem', function() xPlayer.removeInventoryItem(name, count) end))
    end
    local player = qbPlayer(src)
    local fn = player and player.Functions and player.Functions.RemoveItem
    if not fn then return false end
    local _, res = try('Player.Functions.RemoveItem', fn, name, count)
    return res ~= false
  end,
  removeSlot = function(src, name, count, slot)
    if NZ.Framework == 'esx' then return false end
    local player = qbPlayer(src)
    local fn = player and player.Functions and player.Functions.RemoveItem
    if not fn then return false end
    local _, res = try('Player.Functions.RemoveItem', fn, name, count, slot)
    return res ~= false
  end,
  setMeta = function() return false end,
  canCarry = function(src, name, count)
    if NZ.Framework ~= 'esx' then return true end
    local esx = esxObj()
    local ok, xPlayer = try('ESX GetPlayerFromId', function() return esx and esx.GetPlayerFromId(src) end)
    if not ok or type(xPlayer) ~= 'table' or not xPlayer.canCarryItem then return true end
    local _, res = try('xPlayer.canCarryItem', function() return xPlayer.canCarryItem(name, count) end)
    return res ~= false
  end,
  usable = frameworkUsable,
}

adapters.custom = CUSTOM

-- 'auto' detection order (qb-inventory last: ps / lj / qs may provide its name).
local ORDER = {
  'ox_inventory', 'qs-inventory-pro', 'qs-inventory', 'codem-inventory', 'tgiann-inventory',
  'origen_inventory', 'core_inventory', 'ps-inventory', 'lj-inventory', 'qb-inventory',
}
local KNOWN = {}
for i = 1, #ORDER do KNOWN[ORDER[i]] = true end

---------------------------------------------------------------------------------------
-- Resolution
---------------------------------------------------------------------------------------

local resolved = nil      -- { name, adapter } | false (none) | nil (not resolved yet)

local function frameworkAvailable()
  return NZ.Framework == 'esx' or NZ.Framework == 'qb' or NZ.Framework == 'qbx'
end

local function pick()
  local configured = Config.Integrations and Config.Integrations.inventory or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'none' then return false end
  if configured == 'custom' then
    if CUSTOM.resource and not started(CUSTOM.resource) then
      warnOnce('custom', ('custom inventory "%s" is not started'):format(CUSTOM.resource))
    end
    return { name = 'custom', adapter = CUSTOM }
  end
  if configured ~= 'auto' and configured ~= 'framework' then
    if KNOWN[configured] then
      if started(configured) then return { name = configured, adapter = adapters[configured] } end
      warnOnce('forced:' .. configured, ('"%s" is configured but not started: using the framework items'):format(configured))
    else
      warnOnce('unknown:' .. configured, ('unknown Config.Integrations.inventory "%s": using auto detection'):format(configured))
      for i = 1, #ORDER do
        if started(ORDER[i]) then return { name = ORDER[i], adapter = adapters[ORDER[i]] } end
      end
    end
  elseif configured == 'auto' then
    for i = 1, #ORDER do
      if started(ORDER[i]) then return { name = ORDER[i], adapter = adapters[ORDER[i]] } end
    end
  end
  if frameworkAvailable() then return { name = 'framework', adapter = adapters.framework } end
  return false
end

local function resolve()
  if resolved == nil then
    resolved = pick()
    if resolved then
      Utils.debug(('inventory: using %s (metadata: %s)'):format(resolved.name, tostring(resolved.adapter.metadata == true)))
    end
  end
  return resolved or nil
end

local function adapter()
  local r = resolve()
  return r and r.adapter or nil
end

---------------------------------------------------------------------------------------
-- Public API (server)
---------------------------------------------------------------------------------------

--- Inventory in use: resource name, 'framework', 'custom' or nil (none).
---@return string|nil
function Inventory.name()
  local r = resolve()
  return r and r.name or nil
end

--- Can items carry metadata (plate-bound key items)?
---@return boolean
function Inventory.supportsMetadata()
  local a = adapter()
  return a ~= nil and a.metadata == true
end

--- Every item of a player, normalized: { { slot, name, count, metadata } }.
---@param src number
---@return table[]
function Inventory.items(src)
  src = validSrc(src)
  local a = adapter()
  if not src or not a or type(a.items) ~= 'function' then return {} end
  local ok, res = try(Inventory.name() .. ' items', a.items, src)
  return ok and type(res) == 'table' and res or {}
end

--- Items of one name, optionally filtered: matchFn(metadata, entry) -> boolean.
---@param src number
---@param item string
---@param matchFn function|nil
---@return table[] { { slot, count, metadata, name } }
function Inventory.find(src, item, matchFn)
  item = validName(item)
  if not item then return {} end
  local out = {}
  for _, entry in ipairs(Inventory.items(src)) do
    if entry.name == item and entry.count > 0 then
      local keep = true
      if type(matchFn) == 'function' then
        local ok, res = pcall(matchFn, entry.metadata, entry)
        keep = ok and res == true
      end
      if keep then out[#out + 1] = entry end
    end
  end
  return out
end

--- Number of `item` the player carries (only entries whose metadata contains `metadata`).
---@param src number
---@param item string
---@param metadata table|nil
---@return number
function Inventory.count(src, item, metadata)
  local total = 0
  for _, entry in ipairs(Inventory.find(src, item, function(md) return matches(md, metadata) end)) do
    total = total + (tonumber(entry.count) or 0)
  end
  return total
end

--- Does the player carry at least `count` (default 1) of `item` (with `metadata`)?
---@param src number
---@param item string
---@param count number|nil
---@param metadata table|nil
---@return boolean
function Inventory.hasItem(src, item, count, metadata)
  return Inventory.count(src, item, metadata) >= (validCount(count) or 1)
end

--- One slot of the player's inventory, normalized, or nil.
---@param src number
---@param slot number
---@return table|nil
function Inventory.getSlot(src, slot)
  src, slot = validSrc(src), tonumber(slot)
  local a = adapter()
  if not src or not slot or not a then return nil end
  slot = math.tointeger(slot) or slot
  if type(a.getSlot) == 'function' then
    local ok, entry = try(Inventory.name() .. ' getSlot', a.getSlot, src, slot)
    if ok then return entry end
  end
  for _, entry in ipairs(Inventory.items(src)) do
    if entry.slot == slot then return entry end
  end
  return nil
end

--- Can the player carry `count` more of `item`?
---@param src number
---@param item string
---@param count number|nil
---@param metadata table|nil
---@return boolean
function Inventory.canCarry(src, item, count, metadata)
  src, item, count = validSrc(src), validName(item), validCount(count)
  local a = adapter()
  if not src or not item or not count or not a then return false end
  if type(a.canCarry) ~= 'function' then return true end
  local ok, res = try(Inventory.name() .. ' canCarry', a.canCarry, src, item, count, metadata)
  return not ok or res ~= false
end

--- Give the player `count` of `item` (with `metadata` when supported). Checks canCarry first.
---@param src number
---@param item string
---@param count number|nil
---@param metadata table|nil
---@return boolean
function Inventory.addItem(src, item, count, metadata)
  src, item, count = validSrc(src), validName(item), validCount(count)
  local a = adapter()
  if not src or not item or not count or not a or type(a.add) ~= 'function' then return false end
  if type(metadata) == 'table' and a.metadata ~= true then metadata = nil end
  if not Inventory.canCarry(src, item, count, metadata) then return false end
  local ok, res = try(Inventory.name() .. ' add', a.add, src, item, count, metadata)
  if not ok or res ~= true then return false end
  if type(a.box) == 'function' then pcall(a.box, src, item, 'add', count) end
  return true
end

local function removeFromSlot(a, src, item, count, entry)
  local before = entry.count
  local ok, res = try(Inventory.name() .. ' removeSlot', a.removeSlot, src, item, count, entry.slot)
  if not ok or res == false then return false end
  if a.verifyRemoval then
    local after = Inventory.getSlot(src, entry.slot)
    local left = (after and after.name == item) and after.count or 0
    if left > before - count then return false end
  end
  if type(a.box) == 'function' then pcall(a.box, src, item, 'remove', count) end
  return true
end

--- Remove `count` of `item`. With `slot`, only that slot (its item and metadata are
--- re-read and checked first); with `metadata`, only matching entries.
---@param src number
---@param item string
---@param count number|nil
---@param metadata table|nil
---@param slot number|nil
---@return boolean
function Inventory.removeItem(src, item, count, metadata, slot)
  src, item, count = validSrc(src), validName(item), validCount(count)
  local a = adapter()
  if not src or not item or not count or not a then return false end

  if slot ~= nil then
    local entry = Inventory.getSlot(src, slot)
    if not entry or entry.name ~= item or entry.count < count or not matches(entry.metadata, metadata) then
      return false
    end
    if type(a.removeSlot) ~= 'function' then return false end
    return removeFromSlot(a, src, item, count, entry)
  end

  if metadata == nil and type(a.removeName) == 'function' then
    if Inventory.count(src, item) < count then return false end
    local ok, res = try(Inventory.name() .. ' removeName', a.removeName, src, item, count)
    if not ok or res == false then return false end
    if type(a.box) == 'function' then pcall(a.box, src, item, 'remove', count) end
    return true
  end

  local entries = Inventory.find(src, item, function(md) return matches(md, metadata) end)
  local total = 0
  for _, e in ipairs(entries) do total = total + e.count end
  if total < count or type(a.removeSlot) ~= 'function' then return false end
  local remaining = count
  for _, entry in ipairs(entries) do
    if remaining <= 0 then break end
    if entry.slot then
      local take = math.min(remaining, entry.count)
      if removeFromSlot(a, src, item, take, entry) then remaining = remaining - take end
    end
  end
  return remaining <= 0
end

--- Update the metadata of the item in `slot` (merged into the current metadata unless
--- `replace` is true).
---@param src number
---@param slot number
---@param metadata table
---@param replace boolean|nil
---@return boolean
function Inventory.setMetadata(src, slot, metadata, replace)
  src = validSrc(src)
  local a = adapter()
  if not src or type(metadata) ~= 'table' or not a or a.metadata ~= true or type(a.setMeta) ~= 'function' then
    return false
  end
  local entry = Inventory.getSlot(src, slot)
  if not entry then return false end
  local md = replace and copy(metadata) or copy(entry.metadata)
  if not replace then
    for k, v in pairs(metadata) do md[k] = v end
  end
  local ok, res = try(Inventory.name() .. ' setMeta', a.setMeta, src, entry.name, entry.slot, md)
  return ok and res ~= false
end

---------------------------------------------------------------------------------------
-- Usable items
---------------------------------------------------------------------------------------

local registeredWith = {}   -- [adapterName] = { [item] = true }
local syncQueued = false

local function syncUsables()
  local r = resolve()
  if not r then return end
  local done = registeredWith[r.name]
  if not done then
    done = {}
    registeredWith[r.name] = done
  end
  for item in pairs(handlers) do
    if not done[item] then
      local ok
      if type(r.adapter.usable) == 'function' then
        local called, res = try(r.name .. ' usable', r.adapter.usable, item, dispatch)
        ok = called and res ~= false
      else
        ok = frameworkUsable(item)
      end
      if ok then
        done[item] = true
      else
        warnOnce('usable:' .. r.name .. ':' .. item, ('could not register usable item "%s" with %s'):format(item, r.name))
      end
    end
  end
end

local function queueSync(delay)
  if syncQueued then return end
  syncQueued = true
  CreateThread(function()
    Wait(delay or 0)
    syncQueued = false
    local ok, err = pcall(syncUsables)
    if not ok then lib.print.error(('[nayzeee-garages] inventory: usable registration failed: %s'):format(tostring(err))) end
  end)
end

--- Register a usable item: fn(src, item, slot, metadata) runs on every use (the item is never
--- consumed by this resource; the handler removes it when it should be).
---@param item string
---@param fn function
---@return boolean
function Inventory.registerUsable(item, fn)
  item = validName(item)
  if not item or type(fn) ~= 'function' then return false end
  handlers[item] = fn
  queueSync(1000)  -- after every resource of this start finished loading
  return true
end

--- Item names with a registered use handler (for diagnostics).
---@return string[]
function Inventory.usableItems()
  local out = {}
  for item in pairs(handlers) do out[#out + 1] = item end
  table.sort(out)
  return out
end

-- Re-detect when an inventory or the framework (re)starts / stops: their usable item
-- registries are lost on restart.
local WATCH = { ['qb-core'] = true, qbx_core = true, es_extended = true }
for i = 1, #ORDER do WATCH[ORDER[i]] = true end

AddEventHandler('onResourceStart', function(resource)
  if resource == RESOURCE then return end
  if WATCH[resource] or (CUSTOM.resource and resource == CUSTOM.resource) then
    resolved = nil
    registeredWith = {}
    if resource == 'qb-core' then qbCache.obj = nil end
    if resource == 'es_extended' then esxCache = nil end
    queueSync(2000)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == RESOURCE then return end
  if WATCH[resource] then
    resolved = nil
    registeredWith[resource] = nil
    if resource == 'qb-core' then qbCache.obj = nil end
    if resource == 'es_extended' then esxCache = nil end
  end
end)

AddEventHandler('playerDropped', function()
  local src = validSrc(source)
  if not src then return end
  local prefix = tostring(src) .. ':'
  for key in pairs(lastUse) do
    if key:sub(1, #prefix) == prefix then lastUse[key] = nil end
  end
end)
