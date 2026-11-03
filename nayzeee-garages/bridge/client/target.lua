--[[
  nayzeee-garages — third-eye target integration (client): NZ.Target.

  One neutral API over ox_target and qb-target (Config.Integrations.target, 'auto' prefers
  ox_target). Options use a neutral shape:
    { label, icon, onSelect = function(data) end, canInteract = function(entity, distance, coords) end, distance }
  onSelect receives { entity, coords, distance } whatever the target resource is.
  Everything registered is remembered so it can be re-created when the target resource
  restarts and removed when this resource stops.

  API: Target.addSphere(id, coords, radius, options)   sphere zone
       Target.addLocalEntity(id, entity, options)      options on one local entity (garage NPC)
       Target.addVehicleOption(id, option)             option on every vehicle
       Target.remove(id)                               removes any of the above
       Target.available() / Target.resource()
]]

local Target = NZ.Target
local Utils = NZ.Utils

local TARGET_RESOURCES = { 'ox_target', 'qb-target' }
local DEFAULT_VEHICLE_DISTANCE = 2.5
local DEFAULT_ENTITY_DISTANCE = 3.0
local MAX_DISTANCE = 10.0

-- [id] = { kind = 'zone'|'entity'|'vehicle', resource, handle, spec }
local registry = {}

---------------------------------------------------------------------------------------
-- Resolution
---------------------------------------------------------------------------------------

--- Target resource in use right now, or nil. A configured resource that is not running
--- falls back to any other supported target resource.
---@return string|nil
function Target.resource()
  local configured = Config.Integrations and Config.Integrations.target or 'auto'
  if configured == 'none' then return nil end
  if type(configured) == 'string' and configured ~= 'auto' and Utils.resourceStarted(configured) then
    for i = 1, #TARGET_RESOURCES do
      if TARGET_RESOURCES[i] == configured then return configured end
    end
  end
  for i = 1, #TARGET_RESOURCES do
    if Utils.resourceStarted(TARGET_RESOURCES[i]) then return TARGET_RESOURCES[i] end
  end
  return nil
end

--- True when a supported target resource runs and Config.Integrations.target ~= 'none'.
---@return boolean
function Target.available()
  return Target.resource() ~= nil
end

---------------------------------------------------------------------------------------
-- Option conversion
---------------------------------------------------------------------------------------

local function scopedName(id)
  return ('%s:%s'):format(NZ.ResourceName, tostring(id))
end

local function clampDistance(value, default)
  local n = tonumber(value)
  if not n or n ~= n or n <= 0 then n = default end
  if n > MAX_DISTANCE then n = MAX_DISTANCE end
  return n + 0.0
end

local function safeCanInteract(option, entity, distance, coords)
  if type(option.canInteract) ~= 'function' then return true end
  local ok, res = pcall(option.canInteract, entity, distance, coords)
  if not ok then
    Utils.debug(('target: canInteract of "%s" failed: %s'):format(tostring(option.label), tostring(res)))
    return false
  end
  return res ~= false and res ~= nil
end

local function safeSelect(option, data)
  if type(option.onSelect) ~= 'function' then return end
  local ok, err = pcall(option.onSelect, data)
  if not ok then
    lib.print.error(('[nayzeee-garages] target option "%s" failed: %s'):format(tostring(option.label), tostring(err)))
  end
end

local function entityCoords(entity)
  if type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) then
    return GetEntityCoords(entity)
  end
  return nil
end

local function toOx(option, name, distance)
  return {
    name = name,
    label = tostring(option.label or ''),
    icon = option.icon,
    distance = distance,
    canInteract = function(entity, dist, coords)
      return safeCanInteract(option, entity, dist, coords)
    end,
    onSelect = function(data)
      local entity = type(data) == 'table' and data.entity or nil
      safeSelect(option, {
        entity = entity,
        coords = type(data) == 'table' and data.coords or entityCoords(entity),
        distance = type(data) == 'table' and data.distance or nil,
      })
    end,
  }
end

local function toQb(option)
  return {
    type = 'client',
    label = tostring(option.label or ''),
    icon = option.icon,
    canInteract = function(entity, dist)
      return safeCanInteract(option, entity, dist, entityCoords(entity))
    end,
    action = function(entity)
      local ent = type(entity) == 'number' and entity or nil
      safeSelect(option, { entity = ent, coords = entityCoords(ent), distance = nil })
    end,
  }
end

---------------------------------------------------------------------------------------
-- Per-resource create / delete
---------------------------------------------------------------------------------------

local function createZone(resource, id, spec)
  local name = scopedName(id)
  if resource == 'ox_target' then
    local options = {}
    for i = 1, #spec.options do
      options[i] = toOx(spec.options[i], ('%s:%d'):format(name, i), spec.distances[i])
    end
    local handle = exports.ox_target:addSphereZone({
      name = name,
      coords = spec.coords,
      radius = spec.radius,
      debug = Config.Debug == true,
      options = options,
    })
    return handle or name
  end
  local options, maxDistance = {}, 0.0
  for i = 1, #spec.options do
    options[i] = toQb(spec.options[i])
    if spec.distances[i] > maxDistance then maxDistance = spec.distances[i] end
  end
  exports['qb-target']:AddCircleZone(name, spec.coords, spec.radius, {
    name = name,
    debugPoly = Config.Debug == true,
    useZ = true,
  }, {
    options = options,
    distance = maxDistance,
  })
  return name
end

local function deleteZone(resource, handle)
  if resource == 'ox_target' then
    exports.ox_target:removeZone(handle)
  else
    exports['qb-target']:RemoveZone(handle)
  end
end

local function createVehicleOption(resource, id, spec)
  if resource == 'ox_target' then
    local name = scopedName(id)
    exports.ox_target:addGlobalVehicle({ toOx(spec.option, name, spec.distance) })
    return name
  end
  local qbOption = toQb(spec.option)
  exports['qb-target']:AddGlobalVehicle({ options = { qbOption }, distance = spec.distance })
  return qbOption.label
end

local function deleteVehicleOption(resource, handle)
  if resource == 'ox_target' then
    exports.ox_target:removeGlobalVehicle({ handle })
  else
    exports['qb-target']:RemoveGlobalVehicle(handle)
  end
end

--- Options on one entity. The handle keeps the entity and the option names / labels so only
--- our options are removed (ox_target: removeLocalEntity, qb-target: RemoveTargetEntity).
local function createEntity(resource, id, spec)
  local entity = spec.entity
  if not DoesEntityExist(entity) then error('entity does not exist') end
  local name = scopedName(id)
  if resource == 'ox_target' then
    local options, names = {}, {}
    for i = 1, #spec.options do
      options[i] = toOx(spec.options[i], ('%s:%d'):format(name, i), spec.distances[i])
      names[i] = options[i].name
    end
    exports.ox_target:addLocalEntity(entity, options)
    return { entity = entity, names = names }
  end
  local options, labels, maxDistance = {}, {}, 0.0
  for i = 1, #spec.options do
    options[i] = toQb(spec.options[i])
    labels[i] = options[i].label
    if spec.distances[i] > maxDistance then maxDistance = spec.distances[i] end
  end
  exports['qb-target']:AddTargetEntity(entity, { options = options, distance = maxDistance })
  return { entity = entity, labels = labels }
end

local function deleteEntity(resource, handle)
  if type(handle) ~= 'table' then return end
  if resource == 'ox_target' then
    exports.ox_target:removeLocalEntity(handle.entity, handle.names)
  else
    exports['qb-target']:RemoveTargetEntity(handle.entity, handle.labels)
  end
end

local function create(entry, id)
  if entry.kind == 'zone' then return createZone(entry.resource, id, entry.spec) end
  if entry.kind == 'entity' then return createEntity(entry.resource, id, entry.spec) end
  return createVehicleOption(entry.resource, id, entry.spec)
end

local function destroy(entry)
  if entry.handle == nil or not Utils.resourceStarted(entry.resource) then return end
  local ok, err
  if entry.kind == 'zone' then
    ok, err = pcall(deleteZone, entry.resource, entry.handle)
  elseif entry.kind == 'entity' then
    ok, err = pcall(deleteEntity, entry.resource, entry.handle)
  else
    ok, err = pcall(deleteVehicleOption, entry.resource, entry.handle)
  end
  if not ok then Utils.debug(('target: remove failed: %s'):format(tostring(err))) end
end

local function register(id, kind, spec)
  local resource = Target.resource()
  if not resource then return false end
  Target.remove(id)
  local entry = { kind = kind, resource = resource, spec = spec }
  local ok, handle = pcall(create, entry, id)
  if not ok then
    lib.print.warn(('[nayzeee-garages] %s: could not add target "%s": %s'):format(resource, tostring(id), tostring(handle)))
    return false
  end
  entry.handle = handle
  registry[id] = entry
  return true
end

local function cleanOptions(options)
  local list = {}
  if type(options) ~= 'table' then return list end
  if options.label ~= nil or options.onSelect ~= nil then options = { options } end
  for _, option in ipairs(options) do
    if type(option) == 'table' and (type(option.onSelect) == 'function' or option.label ~= nil) then
      list[#list + 1] = option
    end
  end
  return list
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Add (or replace) a sphere interaction zone.
---@param id string unique id inside this resource
---@param coords vector3|table {x,y,z}
---@param radius number metres
---@param options table list of neutral options
---@return boolean added
function Target.addSphere(id, coords, radius, options)
  if id == nil then return false end
  local center = Utils.toVec3(coords)
  if not center then return false end
  local r = tonumber(radius) or 2.0
  if r ~= r or r <= 0 then r = 2.0 end
  local list = cleanOptions(options)
  if #list == 0 then return false end
  local distances = {}
  for i = 1, #list do
    distances[i] = clampDistance(list[i].distance, r + 1.5)
  end
  return register(id, 'zone', { coords = center, radius = r + 0.0, options = list, distances = distances })
end

--- Add (or replace) options on one local (non-networked) entity, e.g. a garage NPC.
--- Remove them with Target.remove(id) BEFORE deleting the entity (handles are reused).
---@param id string unique id inside this resource
---@param entity number entity handle
---@param options table list of neutral options
---@return boolean added
function Target.addLocalEntity(id, entity, options)
  if id == nil or type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return false end
  local list = cleanOptions(options)
  if #list == 0 then return false end
  local distances = {}
  for i = 1, #list do
    distances[i] = clampDistance(list[i].distance, DEFAULT_ENTITY_DISTANCE)
  end
  return register(id, 'entity', { entity = entity, options = list, distances = distances })
end

--- Add (or replace) an option shown on every vehicle.
---@param id string unique id inside this resource
---@param option table neutral option
---@return boolean added
function Target.addVehicleOption(id, option)
  if id == nil then return false end
  local list = cleanOptions(option)
  if #list == 0 then return false end
  return register(id, 'vehicle', {
    option = list[1],
    distance = clampDistance(list[1].distance, DEFAULT_VEHICLE_DISTANCE),
  })
end

--- Remove a zone, entity or vehicle option added with addSphere / addLocalEntity / addVehicleOption.
---@param id string
function Target.remove(id)
  local entry = id ~= nil and registry[id] or nil
  if not entry then return end
  registry[id] = nil
  destroy(entry)
end

---------------------------------------------------------------------------------------
-- Lifecycle: re-create after a target resource (re)start, clean up on stop
---------------------------------------------------------------------------------------

AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= 'ox_target' and resource ~= 'qb-target' then return end
  if next(registry) == nil then return end
  -- Give the target resource a moment to register its exports.
  SetTimeout(500, function()
    local active = Target.resource()
    if not active then return end
    for id, entry in pairs(registry) do
      if entry.kind == 'entity' and not DoesEntityExist(entry.spec.entity) then
        -- the NPC is gone: NZ.Peds registers it again when it is re-created
        registry[id] = nil
      elseif entry.resource == resource or not Utils.resourceStarted(entry.resource) then
        entry.resource = active
        local ok, handle = pcall(create, entry, id)
        if ok then
          entry.handle = handle
        else
          entry.handle = nil
          Utils.debug(('target: re-create of "%s" failed: %s'):format(tostring(id), tostring(handle)))
        end
      end
    end
  end)
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource ~= 'ox_target' and resource ~= 'qb-target' then return end
  for _, entry in pairs(registry) do
    if entry.resource == resource then entry.handle = nil end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for id, entry in pairs(registry) do
    registry[id] = nil
    destroy(entry)
  end
end)
