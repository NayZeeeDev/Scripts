--[[
  nayzeee-garages — ESX Legacy server adapter.
  Defines the framework-specific NZ.Bridge primitives (players, money accounts, jobs, admin
  groups, offline character lookups) and forwards character load/unload events.
  ESX has no gangs: hasGangs = false, getGang -> nil, getGangs -> {}.
  Framework-agnostic logic (pay, isAdmin, name cache, fallbacks) is in bridge/server/common.lua.
]]

if NZ.Framework ~= 'esx' then return end

local Bridge = NZ.Bridge
local Utils = NZ.Utils

-- Internal hooks consumed by bridge/server/common.lua (not part of the public contract).
local fw = Bridge._fw or {}
Bridge._fw = fw

local ESX

--- Lazily resolve the ESX shared object.
---@return table|nil
local function core()
  if ESX then return ESX end
  local ok, obj = pcall(function() return exports.es_extended:getSharedObject() end)
  if ok and type(obj) == 'table' then
    ESX = obj
  else
    lib.print.error('[nayzeee-garages] Could not get the ESX shared object from es_extended.')
  end
  return ESX
end

---------------------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------------------

-- Contract account -> ESX account name.
local ACCOUNTS = { cash = 'money', bank = 'bank' }

---@return integer|nil
local function toSrc(src)
  src = tonumber(src)
  if not src or src <= 0 then return nil end
  return math.tointeger(src)
end

--- Whole, finite, non-negative amount or nil.
---@return integer|nil
local function toAmount(n)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge or n < 0 then return nil end
  return math.tointeger(math.floor(n))
end

---@return string|nil
local function fullName(first, last)
  first = type(first) == 'string' and first or ''
  last = type(last) == 'string' and last or ''
  local full = Utils.trim(first .. ' ' .. last)
  if full == '' then return nil end
  return full
end

--- ESX job -> contract shape { name, label, grade, gradeLabel, onDuty, isBoss }.
---@return table|nil
local function normalizeJob(job)
  if type(job) ~= 'table' or type(job.name) ~= 'string' or job.name == '' then return nil end
  return {
    name = job.name,
    label = tostring(job.label or job.name),
    grade = math.tointeger(math.floor(tonumber(job.grade) or 0)) or 0,
    gradeLabel = tostring(job.grade_label or job.grade_name or ''),
    onDuty = job.onDuty ~= false and job.onduty ~= false,
    isBoss = job.grade_name == 'boss',
  }
end

---@return table|nil
local function xPlayerOf(src)
  src = toSrc(src)
  local esx = core()
  if not src or not esx then return nil end
  local xPlayer = esx.GetPlayerFromId(src)
  if type(xPlayer) ~= 'table' then return nil end
  return xPlayer
end

--- Character name of an xPlayer (field first, method second).
---@return string|nil
local function xPlayerName(xPlayer)
  local name = xPlayer.name
  if (type(name) ~= 'string' or name == '') and xPlayer.getName then
    local ok, res = pcall(xPlayer.getName)
    name = ok and res or nil
  end
  if type(name) ~= 'string' then return nil end
  name = Utils.trim(name)
  if name == '' then return nil end
  return name
end

---@return integer|nil
local function balanceOf(xPlayer, accountName)
  if not xPlayer.getAccount then return nil end
  local account = xPlayer.getAccount(accountName)
  if type(account) ~= 'table' then return nil end
  return math.tointeger(math.floor(tonumber(account.money) or 0)) or 0
end

--- Server-local events can only come from the server; if some resource registered one of
--- them as a net event, a client may only ever report about itself.
local function trustedFor(src)
  local invoker = tonumber(source)
  return not invoker or invoker <= 0 or invoker == src
end

---------------------------------------------------------------------------------------
-- Public primitives (contract §5.1)
---------------------------------------------------------------------------------------

Bridge.hasGangs = false

--- Framework player object (xPlayer) or nil.
---@param src integer
---@return table|nil
function Bridge.getPlayer(src)
  return xPlayerOf(src)
end

--- Character identifier (xPlayer.identifier) or nil.
---@param src integer
---@return string|nil
function Bridge.getIdentifier(src)
  local xPlayer = xPlayerOf(src)
  local identifier = xPlayer and xPlayer.identifier
  if type(identifier) ~= 'string' or identifier == '' then return nil end
  return identifier
end

--- Character name (falls back to the FiveM name).
---@param src integer
---@return string
function Bridge.getName(src)
  local xPlayer = xPlayerOf(src)
  local name = xPlayer and xPlayerName(xPlayer)
  if name then return name end
  local id = toSrc(src)
  return (id and GetPlayerName(tostring(id))) or L('Unknown')
end

--- Normalized job or nil.
---@param src integer
---@return table|nil
function Bridge.getJob(src)
  local xPlayer = xPlayerOf(src)
  if not xPlayer then return nil end
  local job = xPlayer.job
  if type(job) ~= 'table' and xPlayer.getJob then job = xPlayer.getJob() end
  return normalizeJob(job)
end

--- ESX has no gangs.
---@return nil
function Bridge.getGang(src)
  return nil
end

--- Balance of 'cash' (ESX 'money' account) or 'bank'.
---@param src integer
---@param account 'cash'|'bank'
---@return integer
function Bridge.getMoney(src, account)
  local name = ACCOUNTS[account]
  if not name then return 0 end
  local xPlayer = xPlayerOf(src)
  if not xPlayer then return 0 end
  return balanceOf(xPlayer, name) or 0
end

--- Remove money; never lets the account go below zero (ESX does not check this itself).
---@return boolean
function Bridge.removeMoney(src, account, amount, reason)
  local name = ACCOUNTS[account]
  amount = toAmount(amount)
  if not name or not amount then return false end
  if amount == 0 then return true end
  local xPlayer = xPlayerOf(src)
  if not xPlayer or not xPlayer.removeAccountMoney then return false end
  local balance = balanceOf(xPlayer, name)
  if not balance or balance < amount then return false end
  xPlayer.removeAccountMoney(name, amount, reason or L('Garage services'))
  return true
end

--- Add money to 'cash' or 'bank'.
---@return boolean
function Bridge.addMoney(src, account, amount, reason)
  local name = ACCOUNTS[account]
  amount = toAmount(amount)
  if not name or not amount then return false end
  if amount == 0 then return true end
  local xPlayer = xPlayerOf(src)
  if not xPlayer or not xPlayer.addAccountMoney or not balanceOf(xPlayer, name) then return false end
  xPlayer.addAccountMoney(name, amount, reason or L('Garage services'))
  return true
end

--- Server id of the online character with this identifier, or nil.
---@param identifier string
---@return integer|nil
function Bridge.getSourceByIdentifier(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return nil end
  local esx = core()
  if not esx then return nil end
  local xPlayer = esx.GetPlayerFromIdentifier(identifier)
  return type(xPlayer) == 'table' and toSrc(xPlayer.source) or nil
end

--- Every online player with a loaded character, sorted by name.
---@return { source: integer, identifier: string, name: string }[]
function Bridge.getOnlinePlayers()
  local out = {}
  local esx = core()
  if not esx then return out end
  local players = esx.GetExtendedPlayers()
  if type(players) ~= 'table' then return out end
  for _, xPlayer in pairs(players) do
    local src = type(xPlayer) == 'table' and toSrc(xPlayer.source)
    if src and type(xPlayer.identifier) == 'string' and xPlayer.identifier ~= '' then
      out[#out + 1] = {
        source = src,
        identifier = xPlayer.identifier,
        name = xPlayerName(xPlayer) or GetPlayerName(tostring(src)) or L('Unknown'),
      }
    end
  end
  table.sort(out, function(a, b)
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then return na < nb end
    return a.source < b.source
  end)
  return out
end

--- Jobs from ESX.GetJobs(); grade tables may be maps (keyed by grade) or arrays.
function Bridge.getJobs()
  local out = {}
  local esx = core()
  local jobs = esx and esx.GetJobs and esx.GetJobs()
  if type(jobs) ~= 'table' then return out end
  for key, def in pairs(jobs) do
    if type(def) == 'table' then
      local name = type(def.name) == 'string' and def.name or (type(key) == 'string' and key or nil)
      if name then
        local grades, seen = {}, {}
        if type(def.grades) == 'table' then
          for gradeKey, gradeDef in pairs(def.grades) do
            if type(gradeDef) == 'table' then
              local level = tonumber(gradeDef.grade) or tonumber(gradeKey)
              level = level and math.tointeger(math.floor(level))
              if level and not seen[level] then
                seen[level] = true
                grades[#grades + 1] = {
                  grade = level,
                  label = tostring(gradeDef.label or gradeDef.name or level),
                  isBoss = gradeDef.name == 'boss',
                }
              end
            end
          end
        end
        table.sort(grades, function(a, b) return a.grade < b.grade end)
        out[#out + 1] = { name = name, label = tostring(def.label or name), grades = grades }
      end
    end
  end
  table.sort(out, function(a, b)
    local la, lb = a.label:lower(), b.label:lower()
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

--- ESX has no gangs.
function Bridge.getGangs()
  return {}
end

---------------------------------------------------------------------------------------
-- Internal hooks for common.lua
---------------------------------------------------------------------------------------

--- True when the player's ESX group is one of `groups`.
function fw.hasAnyGroup(src, groups)
  local xPlayer = xPlayerOf(src)
  if not xPlayer or not xPlayer.getGroup then return false end
  local group = xPlayer.getGroup()
  if type(group) ~= 'string' then return false end
  for _, g in ipairs(groups) do
    if g == group then return true end
  end
  return false
end

-- Whether `users` has firstname/lastname (esx_identity). Checked once.
local hasNameColumns

local function nameColumns()
  if hasNameColumns == nil then
    local count = MySQL.scalar.await([[
      SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME IN ('firstname', 'lastname')
    ]])
    hasNameColumns = (tonumber(count) or 0) >= 2
    if not hasNameColumns then
      lib.print.warn('[nayzeee-garages] `users` has no firstname/lastname columns: offline character names are unavailable.')
    end
  end
  return hasNameColumns
end

--- Offline character name from the users table.
---@return string|nil
function fw.fetchName(identifier)
  if not nameColumns() then return nil end
  local row = MySQL.single.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier` = ? LIMIT 1', { identifier })
  return row and fullName(row.firstname, row.lastname) or nil
end

--- Paged character search. `pattern` is an escaped LIKE pattern (escape char '!').
---@return { identifier: string, name: string|nil }[] rows, integer total
function fw.searchCharacters(pattern, limit, offset)
  local named = nameColumns()
  local where, params
  if named then
    where = [[ WHERE LOWER(`identifier`) LIKE LOWER(?) ESCAPE '!'
      OR LOWER(CONCAT_WS(' ', `firstname`, `lastname`)) LIKE LOWER(?) ESCAPE '!' ]]
    params = { pattern, pattern }
  else
    where = [[ WHERE LOWER(`identifier`) LIKE LOWER(?) ESCAPE '!' ]]
    params = { pattern }
  end

  local total = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `users`' .. where, params)) or 0
  local rows = {}
  if total > 0 and offset < total then
    local columns = named and '`identifier`, `firstname`, `lastname`' or '`identifier`'
    local order = named and ' ORDER BY `firstname`, `lastname`, `identifier`' or ' ORDER BY `identifier`'
    local query = ('SELECT %s FROM `users`%s%s LIMIT ? OFFSET ?'):format(columns, where, order)
    params[#params + 1] = limit
    params[#params + 1] = offset
    local result = MySQL.query.await(query, params) or {}
    for i = 1, #result do
      local row = result[i]
      rows[#rows + 1] = { identifier = row.identifier, name = named and fullName(row.firstname, row.lastname) or nil }
    end
  end
  return rows, math.tointeger(total) or 0
end

---------------------------------------------------------------------------------------
-- Character lifecycle -> nz:server:playerLoaded / nz:server:playerUnloaded
---------------------------------------------------------------------------------------

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
  local src = toSrc(playerId)
  if not src or not trustedFor(src) or not Bridge._playerLoaded then return end
  local identifier, name
  if type(xPlayer) == 'table' then
    identifier = xPlayer.identifier
    name = type(xPlayer.name) == 'string' and xPlayer.name or nil
  end
  Bridge._playerLoaded(src, identifier, name)
end)

AddEventHandler('esx:playerLogout', function(playerId)
  local src = toSrc(playerId)
  if not src or not trustedFor(src) or not Bridge._playerUnloaded then return end
  Bridge._playerUnloaded(src)
end)
