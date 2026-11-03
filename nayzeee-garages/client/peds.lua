--[[
  nayzeee-garages — garage NPCs (client): NZ.Peds.

  NZ.Points.rebuild() hands the wanted NPCs to NZ.Peds.sync(specs) (locations whose
  interaction mode resolves to 'target' or 'both' and that have interaction.ped). Each NPC is
  created locally (never networked) while the player is within Config.Peds.spawnDistance of
  it: frozen, invincible, ignoring events, playing its scenario, carrying the target options
  of the first open point (NZ.Target.addLocalEntity). It is deleted again when the player
  leaves, when its location is removed / disabled / changed, when the points are cleared
  (unload, placement tool) and when the resource stops. A model that cannot be loaded falls
  back to a sphere zone with the same options so the garage stays usable.

  spec = { id, coords = vector3 (open point), heading, model, scenario ('' = none),
           radius (fallback zone radius), options = { neutral target options } }

  API: Peds.sync(specs) ; Peds.clear() ; Peds.entity(id) -> ped handle|nil
]]

local Peds = NZ.Peds

local MODEL_TIMEOUT = 5000     -- ms
local entries = {}             -- [id] = entry
local warnedModels = {}

local function spawnDistance()
  local cfg = Config.Peds or {}
  local d = tonumber(cfg.spawnDistance) or 60.0
  if d ~= d or d < 10.0 then d = 10.0 elseif d > 300.0 then d = 300.0 end
  return d
end

--- Identity of an NPC: changing any of these re-creates it; option changes do not.
local function signature(spec)
  local c = spec.coords
  return ('%s|%s|%.2f|%.2f|%.2f|%.1f'):format(spec.model, spec.scenario or '', c.x, c.y, c.z, spec.heading or 0.0)
end

local function validSpec(spec)
  return type(spec) == 'table' and spec.id ~= nil and type(spec.model) == 'string' and spec.model ~= ''
    and spec.coords ~= nil and type(spec.options) == 'table'
end

--- Ground under the open point (points are recorded at the player's position, ~1 m up).
local function groundZ(c)
  RequestCollisionAtCoord(c.x, c.y, c.z)
  for _ = 1, 10 do
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    if found and math.abs(z - c.z) < 3.0 then return z end
    Wait(100)
  end
  return c.z - 1.0
end

--- Load a ped model, giving up after MODEL_TIMEOUT. The caller releases it.
local function loadModel(hash)
  if not IsModelInCdimage(hash) or not IsModelAPed(hash) then return false end
  if HasModelLoaded(hash) then return true end
  RequestModel(hash)
  local deadline = GetGameTimer() + MODEL_TIMEOUT
  while not HasModelLoaded(hash) do
    if GetGameTimer() > deadline then return false end
    Wait(50)
  end
  return true
end

--- Still wanted: same entry, not removed, player in range, no newer spawn / despawn since.
local function alive(entry, gen)
  return entries[entry.id] == entry and not entry.removed and entry.inside and entry.gen == gen
end

---------------------------------------------------------------------------------------
-- Target options (on the NPC, or the fallback zone)
---------------------------------------------------------------------------------------

local function addZone(entry)
  local spec = entry.spec
  local ok, added = pcall(NZ.Target.addSphere, entry.zoneId, spec.coords, spec.radius or 2.0, spec.options)
  entry.zone = ok and added == true
end

local function removeTargets(entry)
  pcall(NZ.Target.remove, entry.targetId)
  if entry.zone then
    pcall(NZ.Target.remove, entry.zoneId)
    entry.zone = false
  end
end

local function applyTargets(entry)
  if entry.ped and DoesEntityExist(entry.ped) then
    local ok, added = pcall(NZ.Target.addLocalEntity, entry.targetId, entry.ped, entry.spec.options)
    if not ok or not added then NZ.Utils.debug(('peds: target options of NPC %s not added'):format(entry.id)) end
  elseif entry.zone then
    addZone(entry)
  end
end

---------------------------------------------------------------------------------------
-- Spawn / despawn
---------------------------------------------------------------------------------------

local function setupPed(ped, spec)
  SetEntityAsMissionEntity(ped, true, true)
  SetEntityHeading(ped, (spec.heading or 0.0) + 0.0)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedFleeAttributes(ped, 0, false)
  SetPedCanRagdoll(ped, false)
  SetPedDiesWhenInjured(ped, false)
  SetPedCanBeTargetted(ped, false)
  SetPedCanPlayAmbientAnims(ped, true)
  SetPedDefaultComponentVariation(ped)
  if type(spec.scenario) == 'string' and spec.scenario ~= '' then
    TaskStartScenarioInPlace(ped, spec.scenario, 0, true)
  end
end

local function deletePed(ped)
  if ped and DoesEntityExist(ped) then
    SetEntityAsMissionEntity(ped, true, true)
    DeleteEntity(ped)
  end
end

local function spawn(entry, gen)
  local spec = entry.spec
  if entry.badModel then
    if alive(entry, gen) then addZone(entry) end
    return
  end
  local z = groundZ(spec.coords)
  if not alive(entry, gen) then return end

  local hash = joaat(spec.model)
  if not loadModel(hash) then
    entry.badModel = true
    if not warnedModels[spec.model] then
      warnedModels[spec.model] = true
      lib.print.warn(('[nayzeee-garages] garage NPC model "%s" could not be loaded: using a target zone instead'):format(spec.model))
    end
    if alive(entry, gen) then addZone(entry) end
    return
  end
  if not alive(entry, gen) then
    SetModelAsNoLongerNeeded(hash)
    return
  end

  -- No Wait between the model check and CreatePed (the model could be released meanwhile).
  local c = spec.coords
  local ped = CreatePed(4, hash, c.x + 0.0, c.y + 0.0, z + 0.0, (spec.heading or 0.0) + 0.0, false, true)
  SetModelAsNoLongerNeeded(hash)
  if not ped or ped == 0 or not DoesEntityExist(ped) then
    if alive(entry, gen) then addZone(entry) end
    return
  end
  setupPed(ped, spec)
  entry.ped = ped
  applyTargets(entry)
end

local function despawn(entry)
  entry.gen = entry.gen + 1
  -- target options first: entity handles are reused by the game
  removeTargets(entry)
  if entry.ped then
    deletePed(entry.ped)
    entry.ped = nil
  end
end

local function onEnter(self)
  local entry = entries[self.pedId]
  if not entry or entry.removed then return end
  entry.inside = true
  if entry.ped or entry.zone then return end
  entry.gen = entry.gen + 1
  local gen = entry.gen
  CreateThread(function()
    local ok, err = pcall(spawn, entry, gen)
    if not ok then lib.print.error(('[nayzeee-garages] garage NPC %s failed: %s'):format(entry.id, err)) end
  end)
end

local function onExit(self)
  local entry = entries[self.pedId]
  if not entry then return end
  entry.inside = false
  despawn(entry)
end

local function addEntry(spec)
  local entry = {
    id = spec.id,
    spec = spec,
    sig = signature(spec),
    gen = 0,
    inside = false,
    zone = false,
    targetId = 'nz_ped_' .. spec.id,
    zoneId = 'nz_ped_zone_' .. spec.id,
  }
  entries[spec.id] = entry
  entry.point = lib.points.new({
    coords = spec.coords,
    distance = spawnDistance(),
    pedId = spec.id,
    onEnter = onEnter,
    onExit = onExit,
  })
end

local function removeEntry(entry)
  entry.removed = true
  entry.inside = false
  if entries[entry.id] == entry then entries[entry.id] = nil end
  if entry.point then pcall(entry.point.remove, entry.point) end
  despawn(entry)
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Make the NPCs match `specs`: removes the ones no longer wanted or changed (model,
--- scenario, position, heading), adds new ones and refreshes the target options of the rest.
---@param specs table[]
function Peds.sync(specs)
  local wanted = {}
  if type(specs) == 'table' then
    for _, spec in ipairs(specs) do
      if validSpec(spec) then
        spec.id = tostring(spec.id)
        wanted[spec.id] = spec
      end
    end
  end
  for id, entry in pairs(entries) do
    local spec = wanted[id]
    if not spec or signature(spec) ~= entry.sig then removeEntry(entry) end
  end
  for id, spec in pairs(wanted) do
    local entry = entries[id]
    if entry then
      entry.spec = spec
      applyTargets(entry)
    else
      addEntry(spec)
    end
  end
end

--- Delete every NPC and forget them.
function Peds.clear()
  for _, entry in pairs(entries) do
    removeEntry(entry)
  end
  entries = {}
end

--- The NPC entity of a location (string id), or nil while it is not spawned.
---@param id string|number
---@return number|nil
function Peds.entity(id)
  local entry = entries[tostring(id)]
  if entry and entry.ped and DoesEntityExist(entry.ped) then return entry.ped end
  return nil
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for _, entry in pairs(entries) do
    entry.removed = true
    if entry.ped then deletePed(entry.ped) end
  end
  entries = {}
end)
