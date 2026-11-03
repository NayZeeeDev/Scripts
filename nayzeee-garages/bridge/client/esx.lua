--[[
  nayzeee-garages — ESX Legacy client adapter.
  Tracks the local character (logged in, identifier, job), keeps NZ.State.job in the
  contract shape and fires the local bridge events nz:client:playerLoaded /
  playerUnloaded / jobUpdated. ESX has no gangs: NZ.State.gang stays nil.
]]

if NZ.Framework ~= 'esx' then return end

local Bridge = NZ.Bridge
local State = NZ.State

local ESX
local playerData = {}
local loggedIn = false

--- Lazily resolve the ESX shared object.
---@return table|nil
local function core()
  if ESX then return ESX end
  local ok, obj = pcall(function() return exports.es_extended:getSharedObject() end)
  if ok and type(obj) == 'table' then ESX = obj end
  return ESX
end

---------------------------------------------------------------------------------------
-- Normalization
---------------------------------------------------------------------------------------

--- ESX job -> { name, label, grade, gradeLabel, onDuty, isBoss }.
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

local function sameJob(a, b)
  if a == nil or b == nil then return a == b end
  return a.name == b.name and a.label == b.label and a.grade == b.grade
    and a.gradeLabel == b.gradeLabel and a.onDuty == b.onDuty and a.isBoss == b.isBoss
end

---@return table|nil
local function fetchPlayerData()
  local esx = core()
  if not esx or not esx.GetPlayerData then return nil end
  local ok, data = pcall(esx.GetPlayerData)
  if ok and type(data) == 'table' then return data end
  return nil
end

---@return boolean
local function frameworkLoaded()
  local esx = core()
  if not esx or not esx.IsPlayerLoaded then return false end
  local ok, res = pcall(esx.IsPlayerLoaded)
  return ok and res == true
end

--- Set NZ.State.job; fires nz:client:jobUpdated on change while logged in.
local function setJob(raw)
  local job = normalizeJob(raw)
  if sameJob(State.job, job) then return end
  State.job = job
  if loggedIn then TriggerEvent('nz:client:jobUpdated', job) end
end

---------------------------------------------------------------------------------------
-- Public API (contract §6)
---------------------------------------------------------------------------------------

--- True while a character is loaded.
---@return boolean
function Bridge.isLoggedIn()
  return loggedIn
end

--- Identifier of the loaded character, or nil.
---@return string|nil
function Bridge.getIdentifier()
  if not loggedIn then return nil end
  if type(playerData.identifier) ~= 'string' then
    playerData = fetchPlayerData() or playerData
  end
  return type(playerData.identifier) == 'string' and playerData.identifier or nil
end

--- Normalized job or nil.
---@return table|nil
function Bridge.getJob()
  return State.job
end

--- ESX has no gangs.
---@return nil
function Bridge.getGang()
  return nil
end

---------------------------------------------------------------------------------------
-- Framework events
---------------------------------------------------------------------------------------

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
  playerData = type(xPlayer) == 'table' and xPlayer or fetchPlayerData() or {}
  State.job = normalizeJob(playerData.job)
  State.gang = nil
  if loggedIn then return end
  loggedIn = true
  TriggerEvent('nz:client:playerLoaded')
end)

RegisterNetEvent('esx:onPlayerLogout', function()
  playerData = {}
  State.job, State.gang = nil, nil
  if not loggedIn then return end
  loggedIn = false
  TriggerEvent('nz:client:playerUnloaded')
end)

RegisterNetEvent('esx:setJob', function(job)
  if type(job) ~= 'table' then return end
  playerData.job = job
  setJob(job)
end)

---------------------------------------------------------------------------------------
-- Resource (re)start while a character is already loaded: seed state, no loaded event.
---------------------------------------------------------------------------------------

do
  if frameworkLoaded() then
    local data = fetchPlayerData()
    if data then
      playerData = data
      loggedIn = true
      State.job = normalizeJob(data.job)
      State.gang = nil
    end
  end
end
