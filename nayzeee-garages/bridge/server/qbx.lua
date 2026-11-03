--[[
  nayzeee-garages — Qbox (qbx_core) server adapter.
  Defines the framework-specific NZ.Bridge primitives (players, money, jobs/gangs, admin
  groups, offline character lookups) and forwards character load/unload events.
  Framework-agnostic logic (pay, isAdmin, name cache, fallbacks) is in bridge/server/common.lua.
]]

if NZ.Framework ~= 'qbx' then return end

local Bridge = NZ.Bridge
local Utils = NZ.Utils

-- Internal hooks consumed by bridge/server/common.lua (not part of the public contract).
local fw = Bridge._fw or {}
Bridge._fw = fw

local qbx = exports.qbx_core

---------------------------------------------------------------------------------------
-- Local helpers
---------------------------------------------------------------------------------------

local ACCOUNTS = { cash = 'cash', bank = 'bank' }

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

--- "First Last" from a charinfo table or JSON string.
---@return string|nil
local function charName(charinfo)
  if type(charinfo) == 'string' then
    local ok, decoded = pcall(json.decode, charinfo)
    charinfo = ok and decoded or nil
  end
  if type(charinfo) ~= 'table' then return nil end
  local first = type(charinfo.firstname) == 'string' and charinfo.firstname or ''
  local last = type(charinfo.lastname) == 'string' and charinfo.lastname or ''
  local full = Utils.trim(first .. ' ' .. last)
  if full == '' then return nil end
  return full
end

--- Qbox job/gang table -> contract shape { name, label, grade, gradeLabel, onDuty, isBoss }.
---@return table|nil
local function normalizeGroup(raw)
  if type(raw) ~= 'table' or type(raw.name) ~= 'string' or raw.name == '' then return nil end
  local grade, gradeLabel, gradeBoss
  local g = raw.grade
  if type(g) == 'table' then
    grade = tonumber(g.level) or tonumber(g.grade) or 0
    gradeLabel = g.name or g.label or ''
    gradeBoss = g.isboss == true
  else
    grade, gradeLabel, gradeBoss = tonumber(g) or 0, '', false
  end
  return {
    name = raw.name,
    label = tostring(raw.label or raw.name),
    grade = math.tointeger(math.floor(grade)) or 0,
    gradeLabel = tostring(gradeLabel),
    onDuty = raw.onduty ~= false,
    isBoss = raw.isboss == true or gradeBoss,
  }
end

--- GetJobs() / GetGangs() result -> sorted { { name, label, grades = { { grade, label, isBoss } } } }.
local function groupList(defs)
  local out = {}
  if type(defs) ~= 'table' then return out end
  for name, def in pairs(defs) do
    if type(name) == 'string' and type(def) == 'table' then
      local grades = {}
      if type(def.grades) == 'table' then
        for key, gradeDef in pairs(def.grades) do
          local level = tonumber(key)
          if level and type(gradeDef) == 'table' then
            grades[#grades + 1] = {
              grade = math.tointeger(math.floor(level)) or 0,
              label = tostring(gradeDef.name or gradeDef.label or level),
              isBoss = gradeDef.isboss == true,
            }
          end
        end
      end
      table.sort(grades, function(a, b) return a.grade < b.grade end)
      out[#out + 1] = { name = name, label = tostring(def.label or name), grades = grades }
    end
  end
  table.sort(out, function(a, b)
    local la, lb = a.label:lower(), b.label:lower()
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

---@return table|nil player, table|nil playerData
local function playerOf(src)
  src = toSrc(src)
  if not src then return nil end
  local player = qbx:GetPlayer(src)
  if type(player) ~= 'table' or type(player.PlayerData) ~= 'table' then return nil end
  return player, player.PlayerData
end

---@return integer
local function balanceOf(player, key)
  local money = player.PlayerData and player.PlayerData.money
  local amount = type(money) == 'table' and tonumber(money[key]) or 0
  return math.tointeger(math.floor(amount or 0)) or 0
end

--- Run a money operation through the player object's Functions table, or through the
--- qbx_core export of the same name when the player object has no Functions. Exactly one
--- path is attempted so an error can never charge twice.
---@return boolean
local function moneyOp(src, player, fnName, key, amount, reason)
  local fn = player.Functions and player.Functions[fnName]
  if fn then
    return fn(key, amount, reason) ~= false
  end
  return qbx[fnName](qbx, src, key, amount, reason) == true
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

Bridge.hasGangs = true

--- Framework player object (Qbox player) or nil.
---@param src integer
---@return table|nil
function Bridge.getPlayer(src)
  return (playerOf(src))
end

--- Character identifier (citizenid) or nil.
---@param src integer
---@return string|nil
function Bridge.getIdentifier(src)
  local _, pd = playerOf(src)
  if not pd or type(pd.citizenid) ~= 'string' or pd.citizenid == '' then return nil end
  return pd.citizenid
end

--- Character name "First Last" (falls back to the FiveM name).
---@param src integer
---@return string
function Bridge.getName(src)
  local _, pd = playerOf(src)
  local name = pd and charName(pd.charinfo)
  if name then return name end
  local id = toSrc(src)
  return (id and GetPlayerName(tostring(id))) or L('Unknown')
end

--- Normalized job or nil.
---@param src integer
---@return table|nil
function Bridge.getJob(src)
  local _, pd = playerOf(src)
  return pd and normalizeGroup(pd.job) or nil
end

--- Normalized gang or nil.
---@param src integer
---@return table|nil
function Bridge.getGang(src)
  local _, pd = playerOf(src)
  return pd and normalizeGroup(pd.gang) or nil
end

--- Balance of 'cash' or 'bank'.
---@param src integer
---@param account 'cash'|'bank'
---@return integer
function Bridge.getMoney(src, account)
  local key = ACCOUNTS[account]
  if not key then return 0 end
  local player = playerOf(src)
  if not player then return 0 end
  return balanceOf(player, key)
end

--- Remove money; never lets the account go below zero.
---@return boolean
function Bridge.removeMoney(src, account, amount, reason)
  local key = ACCOUNTS[account]
  amount = toAmount(amount)
  if not key or not amount then return false end
  if amount == 0 then return true end
  local player = playerOf(src)
  if not player or balanceOf(player, key) < amount then return false end
  return moneyOp(toSrc(src), player, 'RemoveMoney', key, amount, reason or L('Garage services'))
end

--- Add money to 'cash' or 'bank'.
---@return boolean
function Bridge.addMoney(src, account, amount, reason)
  local key = ACCOUNTS[account]
  amount = toAmount(amount)
  if not key or not amount then return false end
  if amount == 0 then return true end
  local player = playerOf(src)
  if not player then return false end
  return moneyOp(toSrc(src), player, 'AddMoney', key, amount, reason or L('Garage services'))
end

--- Server id of the online character with this citizenid, or nil.
---@param identifier string
---@return integer|nil
function Bridge.getSourceByIdentifier(identifier)
  if type(identifier) ~= 'string' or identifier == '' then return nil end
  local player = qbx:GetPlayerByCitizenId(identifier)
  local pd = type(player) == 'table' and player.PlayerData
  return pd and toSrc(pd.source) or nil
end

--- Every online player with a loaded character, sorted by name.
---@return { source: integer, identifier: string, name: string }[]
function Bridge.getOnlinePlayers()
  local out = {}
  local players = qbx:GetQBPlayers()
  if type(players) ~= 'table' then return out end
  for key, player in pairs(players) do
    local pd = type(player) == 'table' and player.PlayerData
    local src = pd and (toSrc(pd.source) or toSrc(key))
    if src and type(pd.citizenid) == 'string' and pd.citizenid ~= '' then
      out[#out + 1] = {
        source = src,
        identifier = pd.citizenid,
        name = charName(pd.charinfo) or GetPlayerName(tostring(src)) or L('Unknown'),
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

--- Jobs from qbx_core.
function Bridge.getJobs()
  return groupList(qbx:GetJobs())
end

--- Gangs from qbx_core.
function Bridge.getGangs()
  return groupList(qbx:GetGangs())
end

---------------------------------------------------------------------------------------
-- Internal hooks for common.lua
---------------------------------------------------------------------------------------

--- True when the player has any of the given ace groups (group.<name>).
function fw.hasAnyGroup(src, groups)
  src = toSrc(src)
  if not src then return false end
  local id = tostring(src)
  for _, group in ipairs(groups) do
    if type(group) == 'string' and IsPlayerAceAllowed(id, 'group.' .. group) then return true end
  end
  return false
end

--- Offline character name from the players table.
---@return string|nil
function fw.fetchName(identifier)
  local charinfo = MySQL.scalar.await('SELECT `charinfo` FROM `players` WHERE `citizenid` = ? LIMIT 1', { identifier })
  return charName(charinfo)
end

local SEARCH_FROM = [[
  FROM (
    SELECT `citizenid` AS identifier, `charinfo`,
      IF(JSON_VALID(`charinfo`),
        CONCAT_WS(' ', JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.firstname')), JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.lastname'))),
        '') AS fullname
    FROM `players`
  ) c
  WHERE LOWER(c.identifier) LIKE LOWER(?) ESCAPE '!' OR LOWER(c.fullname) LIKE LOWER(?) ESCAPE '!'
]]

--- Paged character search. `pattern` is an escaped LIKE pattern (escape char '!').
---@return { identifier: string, name: string|nil }[] rows, integer total
function fw.searchCharacters(pattern, limit, offset)
  local total = tonumber(MySQL.scalar.await('SELECT COUNT(*) ' .. SEARCH_FROM, { pattern, pattern })) or 0
  local rows = {}
  if total > 0 and offset < total then
    local result = MySQL.query.await(
      'SELECT c.identifier, c.charinfo ' .. SEARCH_FROM .. ' ORDER BY c.fullname, c.identifier LIMIT ? OFFSET ?',
      { pattern, pattern, limit, offset }
    ) or {}
    for i = 1, #result do
      local row = result[i]
      rows[#rows + 1] = { identifier = row.identifier, name = charName(row.charinfo) }
    end
  end
  return rows, math.tointeger(total) or 0
end

---------------------------------------------------------------------------------------
-- Character lifecycle -> nz:server:playerLoaded / nz:server:playerUnloaded
-- Qbox fires the QBCore compat events and its own; common.lua de-duplicates per source.
---------------------------------------------------------------------------------------

--- Accepts a player object or a server id.
local function onLoaded(arg)
  local src, identifier, name
  if type(arg) == 'table' then
    local pd = arg.PlayerData
    if type(pd) ~= 'table' then return end
    src, identifier, name = toSrc(pd.source), pd.citizenid, charName(pd.charinfo)
  else
    src = toSrc(arg)
  end
  if not src or not trustedFor(src) or not Bridge._playerLoaded then return end
  Bridge._playerLoaded(src, identifier, name)
end

local function onUnloaded(src)
  src = toSrc(src)
  if not src or not trustedFor(src) or not Bridge._playerUnloaded then return end
  Bridge._playerUnloaded(src)
end

AddEventHandler('QBCore:Server:PlayerLoaded', onLoaded)
AddEventHandler('qbx_core:server:playerLoaded', onLoaded)
AddEventHandler('QBCore:Server:OnPlayerUnload', onUnloaded)
AddEventHandler('qbx_core:server:playerLoggedOut', onUnloaded)
