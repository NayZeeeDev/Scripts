--[[
  nayzeee-garages — client vehicle damage (NZ.Damage).
  Captures and restores engine / body / petrol tank health, dirt, broken doors, smashed
  windows, burst tyres and body deformation (format: docs/ARCHITECTURE.md §7.3).
  Deformation is sampled on a grid inside the model bounds and restored over several frames
  in a thread, so spawning a vehicle is never blocked by it.
]]

local Damage = NZ.Damage

local FORMAT_VERSION = 1
local DOOR_INDEXES = { 0, 1, 2, 3, 4, 5 }             -- front L/R, rear L/R, bonnet, boot
local WINDOW_INDEXES = { 0, 1, 2, 3, 4, 5, 6, 7 }     -- side windows, windscreen, rear windscreen
local TYRE_INDEXES = { 0, 1, 2, 3, 4, 5, 45, 47 }     -- 45/47: middle wheels of 6-wheelers
-- Bone of each window index: a window the model does not have (trailers, bikes, open cars)
-- reads as "not intact" and must not be saved as smashed.
local WINDOW_BONES = {
  [0] = 'window_lf', [1] = 'window_rf', [2] = 'window_lr', [3] = 'window_rr',
  [4] = 'window_lm', [5] = 'window_rm', [6] = 'windscreen', [7] = 'windscreen_r',
}

local DEFORM_MIN = 0.05          -- sampled deformation below this magnitude is ignored
local MAX_DEFORM_POINTS = 64     -- hard cap on restored points (stored data is never larger)
local MAX_PASSES = 20            -- restore passes, one every PASS_INTERVAL ms
local PASS_INTERVAL = 50
local START_DELAY = 100          -- let a fresh entity settle before denting it
local BASE_MULTIPLIER = 400.0    -- SetVehicleDamage force per unit of missing deformation
local GROWTH = 1.5               -- multiplier growth when a point barely moved in a pass
local MAX_MULTIPLIER = 25000.0
local MAX_HIT = 2500.0           -- force cap of a single SetVehicleDamage call

-- Sample layout as fractions of the model bounding box
-- (x: left -> right, y: rear -> front, z: bottom -> top). 36 points.
local LAYOUT = {}
do
  local function add(fx, fy, fz) LAYOUT[#LAYOUT + 1] = { fx, fy, fz } end
  for _, fy in ipairs({ 0.96, 0.04 }) do             -- front and rear faces incl. corners (12)
    for _, fx in ipairs({ 0.15, 0.5, 0.85 }) do
      add(fx, fy, 0.3)
      add(fx, fy, 0.6)
    end
  end
  for _, fx in ipairs({ 0.04, 0.96 }) do             -- left and right sides (16)
    for _, fy in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do
      add(fx, fy, 0.3)
      add(fx, fy, 0.6)
    end
  end
  for _, fy in ipairs({ 0.3, 0.5, 0.7 }) do          -- roof (6)
    add(0.3, fy, 0.92)
    add(0.7, fy, 0.92)
  end
  add(0.5, 0.85, 0.7)                                -- bonnet lid
  add(0.5, 0.15, 0.7)                                -- boot lid
end

local offsetsByModel = {}  -- [model hash] = { {x, y, z}, ... } sample offsets in model space
local tokens = {}          -- [vehicle] = token of the newest apply() call on that entity
local pending = {}         -- [vehicle] = { deform, engine, body, tank, before } while restoring
local sequence = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function round(n, decimals)
  return NZ.Utils.round(n, decimals)
end

local function clampf(n, min, max)
  return NZ.Utils.clamp(n, min, max) + 0.0
end

local function magnitude(x, y, z)
  x, y, z = tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0
  return math.sqrt(x * x + y * y + z * z)
end

local function exists(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle)
end

--- Accepts a table or a JSON string (as stored by the server).
local function decode(value)
  if type(value) == 'table' then return value end
  if type(value) == 'string' and value ~= '' then
    local ok, res = pcall(json.decode, value)
    if ok and type(res) == 'table' then return res end
  end
  return nil
end

--- { [index] = value } from a table that may use numeric or JSON string keys ("0", "1"...).
local function indexMap(t)
  local out = {}
  if type(t) ~= 'table' then return out end
  for k, v in pairs(t) do
    local n = tonumber(k)
    local i = n and math.tointeger(n)
    if i and i >= 0 and i <= 63 then out[i] = v end
  end
  return out
end

local function truthy(v)
  return v == true or v == 1 or v == 'true'
end

--- Whether this client may change the entity (local entity, or network owner).
local function controllable(vehicle)
  if not NetworkGetEntityIsNetworked(vehicle) then return true end
  return NetworkGetEntityOwner(vehicle) == PlayerId()
end

local function deformationEnabled()
  local settings = NZ.State and NZ.State.settings
  local vehicles = type(settings) == 'table' and settings.vehicles or nil
  if type(vehicles) ~= 'table' then vehicles = Config.DefaultSettings.vehicles or {} end
  return vehicles.saveDamage ~= false and vehicles.saveDeformation ~= false
end

--- Sample offsets for a model (cached per model).
local function sampleOffsets(model)
  local cached = offsetsByModel[model]
  if cached then return cached end
  local min, max = GetModelDimensions(model)
  local list = {}
  if min and max then
    for i = 1, #LAYOUT do
      local f = LAYOUT[i]
      list[i] = {
        min.x + (max.x - min.x) * f[1],
        min.y + (max.y - min.y) * f[2],
        min.z + (max.z - min.z) * f[3],
      }
    end
    offsetsByModel[model] = list
  end
  return list
end

local function deformationAt(vehicle, x, y, z)
  local d = GetVehicleDeformationAtPos(vehicle, x + 0.0, y + 0.0, z + 0.0)
  if not d then return 0.0, 0.0, 0.0, 0.0 end
  return magnitude(d.x, d.y, d.z), d.x, d.y, d.z
end

--- Impact radius used when restoring dents, scaled with the vehicle size.
local function hitRadius(vehicle)
  local min, max = GetModelDimensions(GetEntityModel(vehicle))
  if not min or not max then return 0.5 end
  local size = math.max(max.y - min.y, max.x - min.x)
  return clampf(size * 0.1, 0.3, 1.0)
end

---------------------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------------------

local function hasWindow(vehicle, index)
  local bone = WINDOW_BONES[index]
  if not bone then return true end
  return GetEntityBoneIndexByName(vehicle, bone) ~= -1
end

local function readDoors(vehicle)
  local doors = {}
  for _, i in ipairs(DOOR_INDEXES) do
    doors[i] = IsVehicleDoorDamaged(vehicle, i) == true
  end
  return doors
end

local function readWindows(vehicle)
  local windows = {}
  for _, i in ipairs(WINDOW_INDEXES) do
    local intact = not hasWindow(vehicle, i) or IsVehicleWindowIntact(vehicle, i)
    if not intact then
      -- A rolled-down window reads as "not intact"; rolling it up tells both cases apart.
      RollUpWindow(vehicle, i)
      intact = IsVehicleWindowIntact(vehicle, i)
    end
    windows[i] = not intact
  end
  return windows
end

local function readTyres(vehicle)
  local tyres = {}
  for _, i in ipairs(TYRE_INDEXES) do
    local state = 0
    if IsVehicleTyreBurst(vehicle, i, false) then
      state = IsVehicleTyreBurst(vehicle, i, true) and 2 or 1
    end
    tyres[i] = state
  end
  return tyres
end

local function readDeformation(vehicle)
  local out = {}
  local offsets = sampleOffsets(GetEntityModel(vehicle))
  for i = 1, #offsets do
    local o = offsets[i]
    local mag, dx, dy, dz = deformationAt(vehicle, o[1], o[2], o[3])
    if mag > DEFORM_MIN then
      out[#out + 1] = {
        round(o[1], 3), round(o[2], 3), round(o[3], 3),
        round(dx, 3), round(dy, 3), round(dz, 3),
      }
    end
  end
  return out
end

--- Read the damage state of a vehicle (format §7.3).
--- While a deformation restore is still running on the entity, the target values of that
--- restore are returned so a quick store right after spawning loses nothing.
---@param vehicle integer
---@param includeDeformation boolean|nil  nil = follow settings.vehicles.saveDeformation
---@return table|nil
function Damage.get(vehicle, includeDeformation)
  if not exists(vehicle) then return nil end
  if includeDeformation == nil then includeDeformation = deformationEnabled() end
  local restoring = pending[vehicle]

  local data = {
    v = FORMAT_VERSION,
    engine = round(GetVehicleEngineHealth(vehicle), 1),
    body = round(GetVehicleBodyHealth(vehicle), 1),
    tank = round(GetVehiclePetrolTankHealth(vehicle), 1),
    dirt = round(GetVehicleDirtLevel(vehicle), 2),
    doors = readDoors(vehicle),
    windows = readWindows(vehicle),
    tyres = readTyres(vehicle),
  }
  if restoring then
    data.engine = restoring.engine or data.engine
    data.body = restoring.body or data.body
    data.tank = restoring.tank or data.tank
    -- Ignore collateral breakage of the dents being restored (repaired when they finish).
    for i, wasIntact in pairs(restoring.before.windows) do
      if wasIntact then data.windows[i] = false end
    end
    for i, wasOk in pairs(restoring.before.tyres) do
      if wasOk then data.tyres[i] = 0 end
    end
  end
  if includeDeformation then
    data.deform = restoring and NZ.Utils.deepCopy(restoring.deform) or readDeformation(vehicle)
  end
  return data
end

---------------------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------------------

local function applyHealth(vehicle, health)
  if health.engine then SetVehicleEngineHealth(vehicle, health.engine) end
  if health.body then SetVehicleBodyHealth(vehicle, health.body) end
  if health.tank then SetVehiclePetrolTankHealth(vehicle, health.tank) end
end

--- Valid deformation entries { offX, offY, offZ, dmgX, dmgY, dmgZ } (numbers only).
local function sanitizeDeform(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for _, entry in pairs(list) do
    if type(entry) == 'table' and #out < MAX_DEFORM_POINTS then
      local values = {}
      for i = 1, 6 do
        values[i] = tonumber(entry[i] or entry[tostring(i)])
      end
      if values[1] and values[2] and values[3] and values[4] and values[5] and values[6] then
        out[#out + 1] = values
      end
    end
  end
  return out
end

local function buildTargets(deform)
  local targets = {}
  for i = 1, #deform do
    local p = deform[i]
    local target = magnitude(p[4], p[5], p[6])
    if target > DEFORM_MIN then
      targets[#targets + 1] = {
        x = p[1] + 0.0, y = p[2] + 0.0, z = p[3] + 0.0,
        target = target,
        tolerance = math.max(0.02, target * 0.15),
        mult = BASE_MULTIPLIER,
      }
    end
  end
  -- Biggest dents first: their spread often satisfies smaller neighbours.
  table.sort(targets, function(a, b) return a.target > b.target end)
  return targets
end

--- One restore pass. Returns how many points still need work.
local function runPass(vehicle, targets, radius)
  local remaining = 0
  for i = 1, #targets do
    local t = targets[i]
    if not t.done then
      local current = deformationAt(vehicle, t.x, t.y, t.z)
      local deficit = t.target - current
      if deficit <= t.tolerance then
        t.done = true
      else
        if t.lastDeficit and (t.lastDeficit - deficit) < t.lastDeficit * 0.25 then
          t.mult = math.min(t.mult * GROWTH, MAX_MULTIPLIER)
        end
        t.lastDeficit = deficit
        SetVehicleDamage(vehicle, t.x, t.y, t.z, math.min(deficit * t.mult, MAX_HIT) + 0.0, radius, true)
        remaining = remaining + 1
      end
    end
  end
  return remaining
end

--- What is intact right now (after the saved breakage was applied), to undo collateral
--- damage caused by the dents afterwards.
local function snapshot(vehicle)
  local windows, tyres = {}, {}
  for _, i in ipairs(WINDOW_INDEXES) do windows[i] = IsVehicleWindowIntact(vehicle, i) end
  for _, i in ipairs(TYRE_INDEXES) do tyres[i] = not IsVehicleTyreBurst(vehicle, i, false) end
  return { windows = windows, tyres = tyres }
end

local function repairCollateral(vehicle, before)
  for i, wasIntact in pairs(before.windows) do
    if wasIntact and not IsVehicleWindowIntact(vehicle, i) and FixVehicleWindow then
      FixVehicleWindow(vehicle, i)
    end
  end
  for i, wasOk in pairs(before.tyres) do
    if wasOk and IsVehicleTyreBurst(vehicle, i, false) then
      SetVehicleTyreFixed(vehicle, i)
    end
  end
end

local function canContinue(vehicle, token)
  return tokens[vehicle] == token and DoesEntityExist(vehicle) and controllable(vehicle)
end

local function restoreDeformation(vehicle, token, deform, health)
  local targets = buildTargets(deform)
  if #targets == 0 then
    tokens[vehicle] = nil
    return
  end
  local before = snapshot(vehicle)
  pending[vehicle] = {
    deform = deform, engine = health.engine, body = health.body, tank = health.tank, before = before,
  }

  CreateThread(function()
    Wait(START_DELAY)
    if canContinue(vehicle, token) then
      local radius = hitRadius(vehicle)
      for _ = 1, MAX_PASSES do
        if not canContinue(vehicle, token) then break end
        local remaining = runPass(vehicle, targets, radius)
        -- Dents also lower engine/body health; keep it at the saved values (no fires).
        applyHealth(vehicle, health)
        if remaining == 0 then break end
        Wait(PASS_INTERVAL)
      end
      if canContinue(vehicle, token) then
        Wait(0)
        applyHealth(vehicle, health)
        repairCollateral(vehicle, before)
      end
    end
    if tokens[vehicle] == token then
      tokens[vehicle] = nil
      pending[vehicle] = nil
    end
  end)
end

--- Apply saved damage (format §7.3) to a vehicle. Health, dirt, doors, windows and tyres
--- are applied immediately; deformation is restored over the next frames in a thread.
--- Accepts the table or its JSON string. Returns false when nothing could be applied.
---@param vehicle integer
---@param data table|string|nil
---@return boolean
function Damage.apply(vehicle, data)
  data = decode(data)
  if type(data) ~= 'table' or not exists(vehicle) then return false end

  local engine, body, tank = tonumber(data.engine), tonumber(data.body), tonumber(data.tank)
  local health = {
    engine = engine and clampf(engine, -4000.0, 1000.0) or nil,
    body = body and clampf(body, 0.0, 1000.0) or nil,
    tank = tank and clampf(tank, -1000.0, 1000.0) or nil,
  }
  applyHealth(vehicle, health)

  local dirt = tonumber(data.dirt)
  if dirt then SetVehicleDirtLevel(vehicle, clampf(dirt, 0.0, 15.0)) end

  for i, broken in pairs(indexMap(data.doors)) do
    if truthy(broken) then SetVehicleDoorBroken(vehicle, i, true) end
  end
  for i, smashed in pairs(indexMap(data.windows)) do
    if truthy(smashed) then SmashVehicleWindow(vehicle, i) end
  end
  for i, state in pairs(indexMap(data.tyres)) do
    state = tonumber(state) or (truthy(state) and 1 or 0)
    if state >= 1 then SetVehicleTyreBurst(vehicle, i, state >= 2, 1000.0) end
  end

  sequence = sequence + 1
  local token = sequence
  tokens[vehicle] = token
  pending[vehicle] = nil

  local deform = sanitizeDeform(data.deform)
  if #deform > 0 and controllable(vehicle) then
    restoreDeformation(vehicle, token, deform, health)
  else
    tokens[vehicle] = nil
  end
  return true
end
