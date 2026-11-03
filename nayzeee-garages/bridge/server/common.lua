--[[
  nayzeee-garages — framework-agnostic server bridge (loaded after the framework adapters).
  Builds pay(), isAdmin(), addSocietyMoney(), notify(), the character-name cache and
  character search on top of the adapter primitives, de-duplicates character load/unload
  events, and guarantees every NZ.Bridge function exists and never throws (standalone
  fallbacks + error guards).
]]

local Bridge = NZ.Bridge
local Utils = NZ.Utils

-- Framework internals provided by bridge/server/<framework>.lua (may be empty).
local fw = Bridge._fw or {}
Bridge._fw = fw

local STANDALONE = NZ.Framework == 'standalone'

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

---@return integer|nil
local function toSrc(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  return math.tointeger(src)
end

--- Whole, finite amount (may be negative) or nil.
---@return integer|nil
local function toAmount(n)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return math.tointeger(math.floor(n + 0.5))
end

--- Clamp to an integer range with a default for invalid input.
---@return integer
local function clampInt(n, min, max, default)
  n = tonumber(n)
  if not n or n ~= n then return default end
  n = math.floor(n)
  if n < min then n = min elseif n > max then n = max end
  return math.tointeger(n) or default
end

--- Escape LIKE wildcards with '!' as the escape character (queries use ESCAPE '!').
local function escapeLike(s)
  return (s:gsub('[!%%_]', '!%0'))
end

local function started(name)
  return Utils.resourceStarted and Utils.resourceStarted(name) or GetResourceState(name) == 'started'
end

local TOAST_TYPES = {
  success = 'success', error = 'error', info = 'info', warning = 'warning',
  inform = 'info', warn = 'warning', primary = 'info',
}

---------------------------------------------------------------------------------------
-- Character name cache
---------------------------------------------------------------------------------------

local NAME_TTL = 600        -- seconds a resolved name stays cached
local MISS_TTL = 60         -- seconds an unknown identifier stays cached
local CACHE_SOFT_LIMIT = 4000

local nameCache = {}        -- [identifier] = { name = string|false, expires = unix }
local cacheSize = 0

local function cacheSweep(now)
  local size = 0
  for id, entry in pairs(nameCache) do
    if entry.expires <= now then
      nameCache[id] = nil
    else
      size = size + 1
    end
  end
  if size > CACHE_SOFT_LIMIT then
    nameCache, size = {}, 0
  end
  cacheSize = size
end

--- Store a name (or a miss when `name` is false).
local function cacheName(identifier, name, ttl)
  if type(identifier) ~= 'string' or identifier == '' then return end
  local now = os.time()
  if not nameCache[identifier] then
    cacheSize = cacheSize + 1
    if cacheSize > CACHE_SOFT_LIMIT then cacheSweep(now) end
  end
  nameCache[identifier] = { name = name, expires = now + (ttl or NAME_TTL) }
end

---------------------------------------------------------------------------------------
-- Fallbacks: used when the framework adapter did not define a primitive (standalone).
---------------------------------------------------------------------------------------

local fallback = {}

function fallback.getPlayer() return nil end

function fallback.getIdentifier(src)
  src = toSrc(src)
  if not STANDALONE or not src then return nil end
  local id = tostring(src)
  return GetPlayerIdentifierByType(id, 'license2') or GetPlayerIdentifierByType(id, 'license')
end

function fallback.getName(src)
  src = toSrc(src)
  return (src and GetPlayerName(tostring(src))) or L('Unknown')
end

function fallback.getJob() return nil end
function fallback.getGang() return nil end
function fallback.getMoney() return 0 end
function fallback.removeMoney() return false end
function fallback.addMoney() return false end
function fallback.getJobs() return {} end
function fallback.getGangs() return {} end

function fallback.getOnlinePlayers()
  local out = {}
  for _, id in ipairs(GetPlayers()) do
    local src = toSrc(id)
    local identifier = src and Bridge.getIdentifier(src)
    if identifier then
      out[#out + 1] = { source = src, identifier = identifier, name = Bridge.getName(src) }
    end
  end
  return out
end

function fallback.getSourceByIdentifier(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return nil end
  for _, id in ipairs(GetPlayers()) do
    local src = toSrc(id)
    if src and Bridge.getIdentifier(src) == identifier then return src end
  end
  return nil
end

-- Values returned by the error guard when a call throws (functions get the call's args).
local onError = {
  getPlayer = fallback.getPlayer,
  getIdentifier = function() return nil end,
  getName = fallback.getName,
  getJob = fallback.getJob,
  getGang = fallback.getGang,
  getMoney = fallback.getMoney,
  removeMoney = fallback.removeMoney,
  addMoney = fallback.addMoney,
  pay = function() return false, nil end,
  addSocietyMoney = function() return false end,
  getSourceByIdentifier = function() return nil end,
  getOnlinePlayers = function() return {} end,
  getCharacterName = function() return L('Unknown') end,
  searchCharacters = function() return {}, 0 end,
  isAdmin = function(src) return tonumber(src) == 0 end,
  getJobs = fallback.getJobs,
  getGangs = fallback.getGangs,
  notify = function() end,
}

for name, fn in pairs(fallback) do
  if type(Bridge[name]) ~= 'function' then Bridge[name] = fn end
end
if type(Bridge.hasGangs) ~= 'boolean' then Bridge.hasGangs = false end

---------------------------------------------------------------------------------------
-- Framework-agnostic API (contract §5.1)
---------------------------------------------------------------------------------------

--- Configured payment account: 'cash' | 'bank' | 'both'.
local function economyAccount()
  local account
  if NZ.Settings and type(NZ.Settings.get) == 'function' then
    local ok, value = pcall(NZ.Settings.get, 'economy.account', 'bank')
    if ok then account = value end
  end
  if account == 'cash' or account == 'both' then return account end
  return 'bank'
end

--- Charge a player using settings.economy.account ('both' = cash when it covers the whole
--- amount, otherwise bank). Amounts <= 0 succeed without charging.
---@param src integer
---@param amount number
---@param reason string|nil
---@return boolean success, 'cash'|'bank'|nil accountUsed
function Bridge.pay(src, amount, reason)
  local account = economyAccount()
  local primary = account == 'both' and 'cash' or account
  amount = toAmount(amount)
  if not amount then return false, nil end
  if amount <= 0 then return true, primary end
  if not toSrc(src) then return false, nil end
  reason = type(reason) == 'string' and reason or L('Garage services')

  if account == 'both' then
    if Bridge.getMoney(src, 'cash') >= amount and Bridge.removeMoney(src, 'cash', amount, reason) then
      return true, 'cash'
    end
    if Bridge.getMoney(src, 'bank') >= amount and Bridge.removeMoney(src, 'bank', amount, reason) then
      return true, 'bank'
    end
    return false, nil
  end

  if Bridge.removeMoney(src, account, amount, reason) then
    return true, account
  end
  return false, nil
end

--- Call a banking export; nil/true results count as success, false as failure.
local function tryBank(label, fn)
  local ok, res = pcall(fn)
  if not ok then
    lib.print.warn(('[nayzeee-garages] %s deposit failed: %s'):format(label, tostring(res)))
    return false
  end
  return res ~= false
end

--- Deposit into a society/job account. Tries qb-banking, Renewed-Banking, qb-management
--- and esx_addonaccount (only resources that are started), stopping at the first success.
---@param society string job name ('police'); a 'society_' prefix is accepted
---@param amount number
---@return boolean
function Bridge.addSocietyMoney(society, amount)
  if type(society) ~= 'string' then return false end
  society = Utils.trim(society)
  if society == '' then return false end
  amount = toAmount(amount)
  if not amount then return false end
  if amount <= 0 then return true end

  local account = society:gsub('^society_', '')
  if account == '' then return false end
  local reason = L('Garage fees')

  if started('qb-banking') and tryBank('qb-banking', function()
    return exports['qb-banking']:AddMoney(account, amount, reason)
  end) then
    return true
  end

  if started('Renewed-Banking') and tryBank('Renewed-Banking', function()
    return exports['Renewed-Banking']:addAccountMoney(account, amount)
  end) then
    return true
  end

  if started('qb-management') and tryBank('qb-management', function()
    return exports['qb-management']:AddMoney(account, amount)
  end) then
    return true
  end

  if started('esx_addonaccount') then
    local deposited = false
    local ok, err = pcall(TriggerEvent, 'esx_addonaccount:getSharedAccount', 'society_' .. account, function(shared)
      if type(shared) == 'table' and shared.addMoney then
        shared.addMoney(amount)
        deposited = true
      end
    end)
    if not ok then
      lib.print.warn(('[nayzeee-garages] esx_addonaccount deposit failed: %s'):format(tostring(err)))
    end
    if deposited then return true end
  end

  lib.print.warn(('[nayzeee-garages] Could not deposit %d into society account "%s" (no supported banking resource accepted it).'):format(amount, account))
  return false
end

--- Admin check: console, ace 'nayzeee-garages.admin', or a framework group listed in
--- ServerConfig.AdminGroups.
---@param src integer
---@return boolean
function Bridge.isAdmin(src)
  local n = tonumber(src)
  if n == 0 then return true end
  src = toSrc(src)
  if not src then return false end
  if IsPlayerAceAllowed(tostring(src), 'nayzeee-garages.admin') then return true end
  local groups = ServerConfig and ServerConfig.AdminGroups
  if type(groups) ~= 'table' or next(groups) == nil or type(fw.hasAnyGroup) ~= 'function' then
    return false
  end
  return fw.hasAnyGroup(src, groups) == true
end

--- Character name for an identifier: cache, then online player, then database.
---@param identifier string
---@return string
function Bridge.getCharacterName(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return L('Unknown') end
  local now = os.time()
  local hit = nameCache[identifier]
  if hit and hit.expires > now then
    return hit.name or L('Unknown')
  end

  local name
  local src = Bridge.getSourceByIdentifier(identifier)
  if src then
    name = Bridge.getName(src)
  elseif type(fw.fetchName) == 'function' then
    local ok, res = pcall(fw.fetchName, identifier)
    if ok then
      name = res
    else
      lib.print.warn(('[nayzeee-garages] Character name lookup failed: %s'):format(tostring(res)))
      return L('Unknown') -- do not cache transient database errors
    end
  end

  if type(name) == 'string' and name ~= '' then
    cacheName(identifier, name, NAME_TTL)
    return name
  end
  cacheName(identifier, false, MISS_TTL)
  return L('Unknown')
end

--- Case-insensitive character search on first/last name and identifier.
---@param query string|nil
---@param limit number|nil max 50
---@param offset number|nil
---@return { identifier: string, name: string }[] rows, integer total
function Bridge.searchCharacters(query, limit, offset)
  query = type(query) == 'string' and Utils.trim(query:gsub('%c', '')) or ''
  if #query > 64 then query = query:sub(1, 64) end
  limit = clampInt(limit, 1, 50, 20)
  offset = clampInt(offset, 0, 1000000000, 0)

  if type(fw.searchCharacters) == 'function' then
    local rows, total = fw.searchCharacters('%' .. escapeLike(query) .. '%', limit, offset)
    rows = type(rows) == 'table' and rows or {}
    for i = 1, #rows do
      local row = rows[i]
      if type(row.name) == 'string' and row.name ~= '' then
        cacheName(row.identifier, row.name, NAME_TTL)
      else
        row.name = L('Unknown')
      end
    end
    return rows, math.tointeger(tonumber(total) or 0) or 0
  end

  -- No character table (standalone): search online players only.
  local needle = query:lower()
  local matches = {}
  for _, p in ipairs(Bridge.getOnlinePlayers()) do
    if needle == '' or p.name:lower():find(needle, 1, true) or p.identifier:lower():find(needle, 1, true) then
      matches[#matches + 1] = { identifier = p.identifier, name = p.name }
    end
  end
  local rows = {}
  for i = offset + 1, math.min(offset + limit, #matches) do
    rows[#rows + 1] = matches[i]
  end
  return rows, #matches
end

--- Toast through our NUI (nz:client:notify). src 0 prints to the console, -1 broadcasts.
---@param src integer
---@param message string
---@param kind 'success'|'error'|'info'|'warning'|nil
function Bridge.notify(src, message, kind)
  if message == nil then return end
  local n = tonumber(src)
  if n == 0 then
    lib.print.info(('[nayzeee-garages] %s'):format(tostring(message)))
    return
  end
  if n ~= -1 then
    n = toSrc(n)
    if not n then return end
  end
  TriggerClientEvent('nz:client:notify', n, { type = TOAST_TYPES[kind] or 'info', message = tostring(message) })
end

---------------------------------------------------------------------------------------
-- Character lifecycle (called by the framework adapters)
---------------------------------------------------------------------------------------

local DEDUPE_MS = 5000
local loadedAt, unloadedAt = {}, {}

--- Fire nz:server:playerLoaded once per character load (frameworks may report twice).
---@param src integer
---@param identifier string|nil known identifier (refreshes the name cache)
---@param name string|nil known character name
function Bridge._playerLoaded(src, identifier, name)
  src = toSrc(src)
  if not src then return end
  local now = GetGameTimer()
  local last = loadedAt[src]
  if last and now - last < DEDUPE_MS then return end
  loadedAt[src] = now
  unloadedAt[src] = nil
  if type(identifier) == 'string' and identifier ~= '' and type(name) == 'string' and name ~= '' then
    cacheName(identifier, name, NAME_TTL)
  end
  TriggerEvent('nz:server:playerLoaded', src)
end

--- Fire nz:server:playerUnloaded once per logout.
---@param src integer
function Bridge._playerUnloaded(src)
  src = toSrc(src)
  if not src then return end
  local now = GetGameTimer()
  local last = unloadedAt[src]
  if last and now - last < DEDUPE_MS then return end
  unloadedAt[src] = now
  loadedAt[src] = nil
  TriggerEvent('nz:server:playerUnloaded', src)
end

AddEventHandler('playerDropped', function()
  local src = toSrc(source)
  if not src then return end
  loadedAt[src] = nil
  unloadedAt[src] = nil
end)

---------------------------------------------------------------------------------------
-- Error guards: a failing framework call logs and returns a safe value instead of throwing.
---------------------------------------------------------------------------------------

local lastErrorAt = {}

local function guard(name, fn, safe)
  return function(...)
    local res = table.pack(pcall(fn, ...))
    if res[1] then return table.unpack(res, 2, res.n) end
    local now = GetGameTimer()
    if not lastErrorAt[name] or now - lastErrorAt[name] > 30000 then
      lastErrorAt[name] = now
      lib.print.error(('[nayzeee-garages] NZ.Bridge.%s failed: %s'):format(name, tostring(res[2])))
    end
    return safe(...)
  end
end

for name, safe in pairs(onError) do
  local fn = Bridge[name]
  if type(fn) == 'function' then
    Bridge[name] = guard(name, fn, safe)
  else
    Bridge[name] = safe
  end
end
