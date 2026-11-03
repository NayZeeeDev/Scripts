--[[
  nayzeee-garages — QBCore client adapter.
  Tracks the local character (logged in, citizenid, job, gang), keeps NZ.State.job /
  NZ.State.gang in the contract shape and fires the local bridge events
  nz:client:playerLoaded / playerUnloaded / jobUpdated / gangUpdated.
]]

if NZ.Framework ~= 'qb' then return end

local Bridge = NZ.Bridge
local State = NZ.State

local QBCore
local playerData = {}
local loggedIn = false
local loadToken = 0

--- Lazily resolve the QBCore core object.
---@return table|nil
local function core()
  if QBCore then return QBCore end
  local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
  if ok and type(obj) == 'table' then QBCore = obj end
  return QBCore
end

RegisterNetEvent('QBCore:Client:UpdateObject', function()
  QBCore = nil
end)

---------------------------------------------------------------------------------------
-- Normalization
---------------------------------------------------------------------------------------

--- QBCore job/gang -> { name, label, grade, gradeLabel, onDuty, isBoss }.
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

local function sameGroup(a, b)
  if a == nil or b == nil then return a == b end
  return a.name == b.name and a.label == b.label and a.grade == b.grade
    and a.gradeLabel == b.gradeLabel and a.onDuty == b.onDuty and a.isBoss == b.isBoss
end

---@return table|nil
local function fetchPlayerData()
  local qb = core()
  if not qb then return nil end
  local ok, data = pcall(qb.Functions.GetPlayerData)
  if ok and type(data) == 'table' then return data end
  return nil
end

--- Set NZ.State.job; fires nz:client:jobUpdated on change while logged in.
local function setJob(raw)
  local job = normalizeGroup(raw)
  if sameGroup(State.job, job) then return end
  State.job = job
  if loggedIn then TriggerEvent('nz:client:jobUpdated', job) end
end

--- Set NZ.State.gang; fires nz:client:gangUpdated on change while logged in.
local function setGang(raw)
  local gang = normalizeGroup(raw)
  if sameGroup(State.gang, gang) then return end
  State.gang = gang
  if loggedIn then TriggerEvent('nz:client:gangUpdated', gang) end
end

---------------------------------------------------------------------------------------
-- Public API (contract §6)
---------------------------------------------------------------------------------------

--- True while a character is loaded.
---@return boolean
function Bridge.isLoggedIn()
  return loggedIn
end

--- Citizenid of the loaded character, or nil.
---@return string|nil
function Bridge.getIdentifier()
  if not loggedIn then return nil end
  if type(playerData.citizenid) ~= 'string' then
    playerData = fetchPlayerData() or playerData
  end
  return type(playerData.citizenid) == 'string' and playerData.citizenid or nil
end

--- Normalized job or nil.
---@return table|nil
function Bridge.getJob()
  return State.job
end

--- Normalized gang or nil.
---@return table|nil
function Bridge.getGang()
  return State.gang
end

---------------------------------------------------------------------------------------
-- Framework events
---------------------------------------------------------------------------------------

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
  loadToken = loadToken + 1
  local token = loadToken
  CreateThread(function()
    -- PlayerData normally arrives before this event; wait briefly if it has not.
    local data = fetchPlayerData()
    local tries = 0
    while (not data or not data.citizenid) and tries < 50 do
      Wait(100)
      tries = tries + 1
      data = fetchPlayerData()
    end
    if token ~= loadToken then return end
    if data then playerData = data end
    State.job = normalizeGroup(playerData.job)
    State.gang = normalizeGroup(playerData.gang)
    if loggedIn then return end
    loggedIn = true
    TriggerEvent('nz:client:playerLoaded')
  end)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
  loadToken = loadToken + 1
  playerData = {}
  State.job, State.gang = nil, nil
  if not loggedIn then return end
  loggedIn = false
  TriggerEvent('nz:client:playerUnloaded')
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
  if type(data) ~= 'table' then return end
  playerData = data
  setJob(data.job)
  setGang(data.gang)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
  if type(job) ~= 'table' then return end
  playerData.job = job
  setJob(job)
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang)
  if type(gang) ~= 'table' then return end
  playerData.gang = gang
  setGang(gang)
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(onDuty)
  if type(playerData.job) ~= 'table' then return end
  playerData.job.onduty = onDuty == true
  setJob(playerData.job)
end)

---------------------------------------------------------------------------------------
-- Resource (re)start while a character is already loaded: seed state, no loaded event.
---------------------------------------------------------------------------------------

do
  local data = fetchPlayerData()
  if data and type(data.citizenid) == 'string' and LocalPlayer.state.isLoggedIn ~= false then
    playerData = data
    loggedIn = true
    State.job = normalizeGroup(data.job)
    State.gang = normalizeGroup(data.gang)
  end
end
