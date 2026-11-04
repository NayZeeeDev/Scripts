--[[
  nayzeee-garages — server/towtruck.lua (NZ.Tow)

  Impound flatbed tow truck (docs/CARLOCK.md §11). The impound is already committed in the
  database when NZ.Tow.start runs (server/impound.lua); everything here is the visual of an
  NPC collecting the vehicle, with the server as the authority:

  - the vehicle is locked (SetVehicleDoorsLocked 2 + replicated state bag `nzTowing = true`,
    every client refuses entering / driving it) and never survives the tow: it is deleted at
    the end, or at once on any failure;
  - one player client, the "runner" (the impounding officer when in range, else the nearest
    player in the vehicle's routing bucket), creates the networked flatbed + driver and plays
    the scene, reporting each step through the `nz:tow:progress` callback;
  - the vehicle is attached to the bed by the client that owns it (attachments are synced by
    the attached entity's owner): `nz:client:tow:attach`;
  - a 1 s watchdog hands the job to another nearby player when the runner drops, leaves,
    changes bucket, loses the NPCs to another client or stops reporting, and falls back to
    deleting the vehicle (+ truck and driver) on Config.Tow.timeout or any failure;
  - after loading, the truck drives away and is removed once every player is farther than
    Config.Tow.despawnDistance or after Config.Tow.despawnSeconds;
  - resource stop removes every vehicle, truck and driver still in a job.
]]

local Tow = NZ.Tow
local Utils = NZ.Utils

local TICK_MS = 1000
local RUNNER_RANGE = 150.0          -- metres: players this close to the vehicle can run the tow
local KEEP_RANGE = 350.0            -- runner farther than this from the vehicle: hand the job over
local SILENT_MS = 25000             -- no report from the runner for this long: hand the job over
local OWNER_GRACE_MS = 4000         -- driver owned by another client (migration) this long: hand over
local REPORT_WAIT_MS = 3000         -- reported entities must reach the server within this time
local MAX_HANDOVERS = 2
local HANDOVER_MIN_LEFT_MS = 30000  -- less time than this left: fall back instead of handing over
local SPAWN_SLACK = 80.0            -- metres beyond spawnDistance.max a reported truck may stand
local LOAD_RANGE = 30.0             -- metres between truck and vehicle when loading starts
local LEFT_BEHIND = 25.0            -- leaving truck this far from a vehicle not attached to it
local TARGET_GONE_GRACE_MS = 15000  -- vehicle deleted by someone else: time for the truck to leave
local ATTACH_ATTEMPTS = 3
local LOAD_EXTRA_MS = 25000         -- loading may take loadSeconds + this before falling back
local LOADED_STALL_MS = 30000       -- driver not back in the truck after this: clean up from here
local LAST_SEAT = 14
local REPORT_GAP_MS = 150           -- per job, between two reports of its runner
local TOWABLE = { automobile = true, bike = true }  -- server GetVehicleType values
local STAGES = { start = 1, spawned = 2, arrived = 3, load = 4, loaded = 5, leaving = 6 }

local jobs = {}                     -- [id] = job
local owned = {}                    -- [entity] = job (vehicle, truck and driver of every job)
local nextId = 0
local watchdogRunning = false
local stopping = false
local warned = {}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message, code)
  local result = Utils.fail(message)
  result.code = code
  return result
end

local function config()
  return type(Config.Tow) == 'table' and Config.Tow or {}
end

--- Finite number within [min, max], else `default`.
local function number(value, default, min, max)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then n = default end
  if min and n < min then n = min end
  if max and n > max then n = max end
  return n
end

local function toInt(value, min)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if min and n < min then return nil end
  return math.tointeger(n) or n
end

--- Model hash in the signed 32-bit form GTA uses.
local function toSigned(hash)
  local n = tonumber(hash)
  if not n or n ~= n then return nil end
  n = math.floor(n) % 4294967296
  if n >= 2147483648 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function modelHash(name)
  if type(name) == 'number' then return toSigned(name) end
  if type(name) ~= 'string' or name == '' then return nil end
  return toSigned(joaat(name))
end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] tow: %s'):format(message))
end

local function log(event, src, data)
  if stopping or type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then warnOnce('log', ('could not log %s: %s'):format(event, tostring(err))) end
end

local function notify(src, kind, message)
  if not src then return end
  TriggerClientEvent('nz:client:notify', src, { type = kind, message = message })
end

local function snapshot()
  local list = {}
  for _, job in pairs(jobs) do list[#list + 1] = job end
  return list
end

---------------------------------------------------------------------------------------
-- Entities and players
---------------------------------------------------------------------------------------

local function exists(entity, etype)
  if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then return false end
  return etype == nil or GetEntityType(entity) == etype
end

local function entityOf(netId, etype)
  netId = toInt(netId, 1)
  if not netId then return nil end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if exists(entity, etype) then return entity end
  return nil
end

local function netIdOf(entity)
  local success, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
  netId = success and toInt(netId, 1) or nil
  return netId
end

--- Server id of the client that owns (simulates) the entity, or nil (-1 = nobody).
local function ownerOf(entity)
  local success, owner = pcall(NetworkGetEntityOwner, entity)
  owner = success and tonumber(owner) or nil
  if owner and owner > 0 then return owner end
  return nil
end

local function bucketOf(entity)
  local success, bucket = pcall(GetEntityRoutingBucket, entity)
  return success and tonumber(bucket) or 0
end

local function playerBucket(src)
  local success, bucket = pcall(GetPlayerRoutingBucket, src)
  return success and tonumber(bucket) or 0
end

local function modelOf(entity)
  return toSigned(GetEntityModel(entity))
end

local function plateOf(entity)
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function playerPed(src)
  if not src then return nil end
  local ped = GetPlayerPed(src)
  if type(ped) == 'number' and ped ~= 0 and DoesEntityExist(ped) then return ped end
  return nil
end

local function connected(src)
  return src ~= nil and GetPlayerName(src) ~= nil and playerPed(src) ~= nil
end

local function isPlayerPed(entity)
  for _, id in ipairs(GetPlayers()) do
    if GetPlayerPed(id) == entity then return true end
  end
  return false
end

--- True when any ped (player or NPC) sits in the vehicle.
local function occupied(entity)
  for seat = -1, LAST_SEAT do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 then return true end
  end
  return false
end

local function playerInside(entity)
  for seat = -1, LAST_SEAT do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 and isPlayerPed(ped) then return true end
  end
  return false
end

local function setState(entity, key, value)
  local success, err = pcall(function() Entity(entity).state:set(key, value, true) end)
  if not success then warnOnce('state:' .. key, ('could not set state bag %s: %s'):format(key, tostring(err))) end
end

--- Players in `bucket` within `range` of `origin`, nearest first (not in `excluded`).
local function candidates(origin, bucket, excluded, range)
  local list = {}
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    local ped = src and not excluded[src] and playerPed(src) or nil
    if ped and playerBucket(src) == bucket then
      local d = Utils.dist(GetEntityCoords(ped), origin)
      if d <= range then list[#list + 1] = { src = src, dist = d } end
    end
  end
  table.sort(list, function(a, b) return a.dist < b.dist end)
  return list
end

--- `preferred` when it is a candidate, else the nearest candidate.
local function pickRunner(origin, bucket, preferred, excluded)
  local list = candidates(origin, bucket, excluded, RUNNER_RANGE)
  for _, c in ipairs(list) do
    if c.src == preferred then return c.src end
  end
  return list[1] and list[1].src or nil
end

---------------------------------------------------------------------------------------
-- Job entities
---------------------------------------------------------------------------------------

--- Still the impounded vehicle (a recycled handle never matches its model).
local function targetAlive(job)
  return exists(job.target, 2) and modelOf(job.target) == job.model
end

local function truckAlive(job)
  return job.truck ~= nil and exists(job.truck, 2) and modelOf(job.truck) == job.truckModel
end

local function driverAlive(job)
  return job.driver ~= nil and exists(job.driver, 1) and modelOf(job.driver) == job.driverModel
end

local function targetCoords(job)
  if targetAlive(job) then return GetEntityCoords(job.target) end
  return job.origin
end

local function removeNpcs(job)
  if driverAlive(job) and not isPlayerPed(job.driver) then DeleteEntity(job.driver) end
  if truckAlive(job) then DeleteEntity(job.truck) end
  if job.driver then owned[job.driver] = nil end
  if job.truck then owned[job.truck] = nil end
  job.truck, job.driver, job.truckNet, job.driverNet = nil, nil, nil, nil
end

--- End a job: the vehicle, truck and driver are deleted whatever the outcome
--- ('done' = the scene played to the end, 'fallback' = something failed on the way).
local function finish(job, outcome, reason)
  if jobs[job.id] ~= job then return end
  jobs[job.id] = nil
  if owned[job.target] == job then owned[job.target] = nil end
  if targetAlive(job) then DeleteEntity(job.target) end
  removeNpcs(job)
  if not stopping then
    if connected(job.runner) then TriggerClientEvent('nz:client:tow:stop', job.runner, { id = job.id }) end
    if job.attacher and job.attacher ~= job.runner and connected(job.attacher) then
      TriggerClientEvent('nz:client:tow:stop', job.attacher, { id = job.id })
    end
  end
  log('impound.tow', job.officer, {
    plate = job.plate,
    outcome = outcome,
    reason = reason,
    runner = job.runner,
    handovers = job.handovers,
    stage = job.stage,
    seconds = math.floor((GetGameTimer() - job.startedAt) / 1000),
  })
  if outcome ~= 'done' then
    Utils.debug(('tow %d (%s) fell back: %s'):format(job.id, tostring(job.plate), tostring(reason)))
  end
end

local function startLeaving(job)
  job.stage = 'leaving'
  job.stageAt = GetGameTimer()
  job.leavingAt = job.stageAt
end

local function sendStart(job, adopt)
  local left = math.max(5, (job.deadline - GetGameTimer()) // 1000)
  TriggerClientEvent('nz:client:tow:start', job.runner, {
    id = job.id,
    netId = job.netId,
    model = job.model,
    timeout = left,
    truck = adopt and job.truckNet or nil,
    driver = adopt and job.driverNet or nil,
  })
end

local function attachPayload(job)
  return {
    id = job.id,
    netId = job.netId,
    truck = job.truckNet,
    seconds = number(config().loadSeconds, 6, 1, 30),
  }
end

--- Give the job to another player near the vehicle (the current runner is excluded when
--- `exclude`); the new runner adopts the truck + driver when it already owns both, otherwise
--- they are deleted and it sends a new truck. Falls back when nobody can take it.
local function handover(job, reason, exclude)
  local now = GetGameTimer()
  local old = job.runner
  if exclude then job.excluded[old] = true end
  if connected(old) then TriggerClientEvent('nz:client:tow:stop', old, { id = job.id }) end
  if job.handovers >= MAX_HANDOVERS or job.deadline - now < HANDOVER_MIN_LEFT_MS then
    return finish(job, 'fallback', 'runner:' .. reason)
  end
  local preferred = driverAlive(job) and ownerOf(job.driver) or nil
  local runner = pickRunner(targetCoords(job), job.bucket, preferred, job.excluded)
  if not runner then return finish(job, 'fallback', 'runner:' .. reason) end

  local adopt = truckAlive(job) and driverAlive(job)
    and ownerOf(job.truck) == runner and ownerOf(job.driver) == runner
  if adopt then
    job.stage = 'spawned'
    job.adoptPending = true
  else
    removeNpcs(job)
    job.stage = 'start'
    job.adoptPending = nil
  end
  job.runner = runner
  job.handovers = job.handovers + 1
  job.lastSeen, job.stageAt = now, now
  job.ownerMismatchAt, job.droppedAt, job.runnerDropped = nil, nil, nil
  job.attacher, job.attachAttempts = nil, 0
  sendStart(job, adopt)
  Utils.debug(('tow %d handed to %d (%s, adopt=%s)'):format(job.id, runner, reason, tostring(adopt)))
end

--- Why the runner can no longer run the job, or nil.
local function runnerProblem(job, now)
  local src = job.runner
  if job.runnerDropped or not connected(src) then
    -- give the NPCs a moment to migrate to another client, which can then adopt them
    if job.stage ~= 'start' and driverAlive(job) then
      job.droppedAt = job.droppedAt or now
      local owner = ownerOf(job.driver)
      if (owner == nil or owner == src) and now - job.droppedAt < OWNER_GRACE_MS then return nil end
    end
    return 'dropped'
  end
  if playerBucket(src) ~= job.bucket then return 'bucket' end
  if Utils.dist(GetEntityCoords(playerPed(src)), targetCoords(job)) > KEEP_RANGE then return 'far' end
  if now - job.lastSeen > SILENT_MS then return 'silent' end
  if job.stage ~= 'start' and driverAlive(job) then
    if ownerOf(job.driver) ~= src then
      job.ownerMismatchAt = job.ownerMismatchAt or now
      if now - job.ownerMismatchAt > OWNER_GRACE_MS then return 'owner' end
    else
      job.ownerMismatchAt = nil
    end
  end
  return nil
end

--- Every player of the job's bucket is farther than despawnDistance from the truck.
local function everyoneFar(job)
  local range = number(config().despawnDistance, 150.0, 30.0, 1000.0)
  local pos = GetEntityCoords(job.truck)
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    local ped = src and playerPed(src) or nil
    if ped and playerBucket(src) == job.bucket and Utils.dist(GetEntityCoords(ped), pos) <= range then
      return false
    end
  end
  return true
end

--- The vehicle is not on the leaving truck (attach failed or it fell off).
local function leftBehind(job)
  local success, parent = pcall(GetEntityAttachedTo, job.target)
  if success and parent == job.truck then return false end
  return Utils.dist(GetEntityCoords(job.target), GetEntityCoords(job.truck)) > LEFT_BEHIND
end

local function check(job, now)
  local cfg = config()
  if job.stage == 'leaving' then
    if not truckAlive(job) then return finish(job, 'done', 'truckGone') end
    if targetAlive(job) and leftBehind(job) then
      DeleteEntity(job.target)
    end
    local despawnMs = number(cfg.despawnSeconds, 60, 10, 600) * 1000
    if now - job.leavingAt >= despawnMs then return finish(job, 'done', 'time') end
    if everyoneFar(job) then return finish(job, 'done', 'far') end
    return
  end

  if not targetAlive(job) then
    if job.stage == 'start' or not truckAlive(job) then return finish(job, 'fallback', 'targetGone') end
    -- deleted by something else: the runner sends its truck away ('leaving', targetGone)
    job.targetGoneAt = job.targetGoneAt or now
    if now - job.targetGoneAt >= TARGET_GONE_GRACE_MS then return finish(job, 'fallback', 'targetGone') end
  elseif bucketOf(job.target) ~= job.bucket then
    return finish(job, 'fallback', 'bucket')
  end
  if now >= job.deadline then return finish(job, 'fallback', 'timeout') end

  if job.stage ~= 'start' and not job.adoptPending and (not truckAlive(job) or not driverAlive(job)) then
    if job.stage == 'loaded' then return finish(job, 'fallback', 'truckGone') end
    return handover(job, 'truckGone', false)
  end

  local problem = runnerProblem(job, now)
  if problem then
    if job.stage == 'loaded' then return finish(job, 'fallback', 'runner:' .. problem) end
    return handover(job, problem, true)
  end

  local loadMs = number(cfg.loadSeconds, 6, 1, 30) * 1000
  if job.stage == 'load' and now - job.stageAt > loadMs + LOAD_EXTRA_MS then
    return finish(job, 'fallback', 'attach')
  end
  if job.stage == 'loaded' and now - job.stageAt > LOADED_STALL_MS then
    startLeaving(job)
  end
end

local function ensureWatchdog()
  if watchdogRunning then return end
  watchdogRunning = true
  CreateThread(function()
    while next(jobs) ~= nil and not stopping do
      Wait(TICK_MS)
      local now = GetGameTimer()
      for _, job in ipairs(snapshot()) do
        if jobs[job.id] == job then
          local success, err = pcall(check, job, now)
          if not success then
            lib.print.error(('[nayzeee-garages] tow %d watchdog: %s'):format(job.id, tostring(err)))
            pcall(finish, job, 'fallback', 'error')
          end
        end
      end
    end
    watchdogRunning = false
  end)
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Send an NPC flatbed to collect an impounded vehicle. Returns false when the tow cannot
--- run (disabled, boat / aircraft / train, someone inside, too many tows, nobody nearby to
--- run it): the caller then deletes the vehicle as before. Never yields.
---@param entity number vehicle entity (server handle)
---@param officerSrc number|nil player who impounded it (runs the tow when in range, gets a notification)
---@return boolean started, string|nil reason
function Tow.start(entity, officerSrc)
  local cfg = config()
  if cfg.enabled ~= true or stopping then return false, 'disabled' end
  if not exists(entity, 2) then return false, 'entity' end

  local existing = owned[entity]
  if existing then
    -- impounded again while on its way: nothing to add
    if existing.target == entity then return true, nil end
    -- the tow truck itself is impounded: end that tow (deletes truck, driver and its vehicle)
    finish(existing, 'fallback', 'truckImpounded')
    return true, nil
  end

  local typed, vtype = pcall(GetVehicleType, entity)
  if typed and type(vtype) == 'string' and not TOWABLE[vtype] then return false, 'type' end
  if occupied(entity) then return false, 'occupied' end

  local active = 0
  for _ in pairs(jobs) do active = active + 1 end
  if active >= math.floor(number(cfg.maxActive, 6, 0, 50)) then return false, 'busy' end

  local truckModel, driverModel = modelHash(cfg.truck or 'flatbed'), modelHash(cfg.driver or 's_m_m_trucker_01')
  local netId = netIdOf(entity)
  if not truckModel or not driverModel or not netId then return false, 'config' end

  local origin = GetEntityCoords(entity)
  local bucket = bucketOf(entity)
  officerSrc = toInt(officerSrc, 1)
  local runner = pickRunner(origin, bucket, officerSrc, {})
  if not runner then return false, 'runner' end

  nextId = nextId + 1
  local now = GetGameTimer()
  local job = {
    id = nextId,
    target = entity,
    netId = netId,
    model = modelOf(entity),
    plate = plateOf(entity),
    bucket = bucket,
    origin = origin,
    officer = officerSrc,
    runner = runner,
    excluded = {},
    handovers = 0,
    stage = 'start',
    startedAt = now,
    stageAt = now,
    lastSeen = now,
    lastReport = 0,
    deadline = now + math.floor(number(cfg.timeout, 150, 30, 900) * 1000),
    attachAttempts = 0,
    truckModel = truckModel,
    driverModel = driverModel,
  }
  jobs[job.id] = job
  owned[entity] = job

  local locked = pcall(SetVehicleDoorsLocked, entity, 2)
  if not locked then warnOnce('lock', 'SetVehicleDoorsLocked is not available on this server build') end
  setState(entity, 'nzTowing', true)
  sendStart(job, false)
  if officerSrc and connected(officerSrc) then notify(officerSrc, 'info', L('Tow truck dispatched')) end
  ensureWatchdog()
  return true, nil
end

--- NZ.Tow.start for a network id (exports / other modules).
---@param netId number
---@param officerSrc number|nil
---@return boolean started, string|nil reason
function Tow.startByNetId(netId, officerSrc)
  local entity = entityOf(netId, 2)
  if not entity then return false, 'entity' end
  return Tow.start(entity, officerSrc)
end

--- Is this vehicle (or truck / driver) part of a running tow?
---@param entity number
---@return boolean
function Tow.isTowing(entity)
  return owned[entity] ~= nil
end

--- End every tow at once (vehicles, trucks and drivers are deleted).
function Tow.stopAll(reason)
  for _, job in ipairs(snapshot()) do
    local success, err = pcall(finish, job, 'fallback', reason or 'stopAll')
    if not success then lib.print.warn(('[nayzeee-garages] tow %d cleanup failed: %s'):format(job.id, tostring(err))) end
  end
end

---------------------------------------------------------------------------------------
-- Progress reports (runner / attacher clients)
---------------------------------------------------------------------------------------

local function invalid()
  return fail(L('Invalid request'))
end

local function securityLog(src, job, what, data)
  data = data or {}
  data.reason = what
  data.tow = job.id
  data.plate = job.plate
  log('security.tow', src, data)
end

local handlers = {}

-- { truck, driver } net ids of the NPC truck + driver the runner created (or adopted)
function handlers.spawned(job, src, payload)
  local truckNet, driverNet = toInt(payload.truck, 1), toInt(payload.driver, 1)
  if not truckNet or not driverNet then return invalid() end
  local resume = job.stage == 'spawned' and truckNet == job.truckNet and driverNet == job.driverNet
  if job.stage ~= 'start' and not resume and not (job.stage == 'spawned' and job.adoptPending) then
    return invalid()
  end

  -- client-created entities need a moment to reach the server and settle their owner
  local truck, driver
  local deadline = GetGameTimer() + REPORT_WAIT_MS
  while true do
    truck, driver = entityOf(truckNet, 2), entityOf(driverNet, 1)
    if truck and driver and ownerOf(truck) == src and ownerOf(driver) == src then break end
    if GetGameTimer() >= deadline then break end
    Wait(100)
    if jobs[job.id] ~= job or job.runner ~= src then return fail(L('This tow is no longer active'), 'gone') end
  end

  local cfg = config()
  local problem = nil
  if not truck or not driver then
    problem = 'missing'
  elseif modelOf(truck) ~= job.truckModel or modelOf(driver) ~= job.driverModel then
    problem = 'model'
  elseif ownerOf(truck) ~= src or ownerOf(driver) ~= src then
    problem = 'owner'
  elseif truck == job.target or isPlayerPed(driver) or playerInside(truck) then
    problem = 'entity'
  elseif (owned[truck] and owned[truck] ~= job) or (owned[driver] and owned[driver] ~= job) then
    problem = 'taken'
  elseif bucketOf(truck) ~= job.bucket then
    problem = 'bucket'
  else
    local range = cfg.spawnDistance or {}
    local maxDistance = number(range.max, 150.0, 20.0, 500.0) + SPAWN_SLACK
    if Utils.dist(GetEntityCoords(truck), targetCoords(job)) > maxDistance then problem = 'distance' end
  end
  if problem then
    securityLog(src, job, 'spawn:' .. problem, { truck = truckNet, driver = driverNet })
    finish(job, 'fallback', 'spawn:' .. problem)
    return fail(L('The tow truck could not be sent'))
  end

  if job.truck and job.truck ~= truck then removeNpcs(job) end
  job.truck, job.driver, job.truckNet, job.driverNet = truck, driver, truckNet, driverNet
  owned[truck], owned[driver] = job, job
  job.adoptPending = nil
  -- deleted explicitly by this module; the server must not drop them with their creator
  if not pcall(SetEntityOrphanMode, truck, 2) then warnOnce('orphan', 'SetEntityOrphanMode is not available on this server build') end
  pcall(SetEntityOrphanMode, driver, 2)
  setState(truck, 'nzTowTruck', true)
  setState(driver, 'nzTowDriver', true)
  job.stage = 'spawned'
  job.stageAt = GetGameTimer()
  return ok(nil)
end

function handlers.arrived(job)
  if job.stage ~= 'spawned' then return invalid() end
  job.stage = 'arrived'
  job.stageAt = GetGameTimer()
  return ok(nil)
end

-- The driver works the controls: who attaches the vehicle to the bed?
function handlers.load(job, src)
  if job.stage ~= 'arrived' then return invalid() end
  if not targetAlive(job) or not truckAlive(job) or not driverAlive(job) then
    finish(job, 'fallback', 'loadMissing')
    return fail(L('The tow truck could not load the vehicle'))
  end
  if Utils.dist(GetEntityCoords(job.truck), GetEntityCoords(job.target)) > LOAD_RANGE then
    finish(job, 'fallback', 'loadDistance')
    return fail(L('The tow truck could not load the vehicle'))
  end
  job.stage = 'load'
  job.stageAt = GetGameTimer()
  local owner = ownerOf(job.target)
  if owner == src then
    job.attacher = src
    return ok({ attacher = 'self' })
  end
  if owner and connected(owner) and playerBucket(owner) == job.bucket then
    job.attacher = owner
    job.attachAttempts = 1
    TriggerClientEvent('nz:client:tow:attach', owner, attachPayload(job))
    return ok({ attacher = 'remote' })
  end
  finish(job, 'fallback', 'attachOwner')
  return fail(L('The tow truck could not load the vehicle'))
end

-- { ok } from the client asked to attach the vehicle
function handlers.attached(job, src, payload)
  if job.stage ~= 'load' then return invalid() end
  if payload.ok == true then return ok(nil) end
  -- the vehicle changed hands before it could be attached: ask its new owner (bounded)
  local owner = ownerOf(job.target)
  if job.attachAttempts < ATTACH_ATTEMPTS and owner and owner ~= src and connected(owner)
    and playerBucket(owner) == job.bucket then
    job.attacher = owner
    job.attachAttempts = job.attachAttempts + 1
    TriggerClientEvent('nz:client:tow:attach', owner, attachPayload(job))
  end
  -- otherwise the runner gives up waiting for the attachment and reports the failure
  return ok(nil)
end

function handlers.loaded(job)
  if job.stage ~= 'load' then return invalid() end
  job.stage = 'loaded'
  job.stageAt = GetGameTimer()
  return ok(nil)
end

-- { reason? } the truck drives away: loaded, or reason 'targetGone' (vehicle deleted meanwhile)
function handlers.leaving(job, src, payload)
  if job.stage == 'loaded' then
    startLeaving(job)
    return ok(nil)
  end
  if payload.reason == 'targetGone' and STAGES[job.stage] >= STAGES.spawned and STAGES[job.stage] <= STAGES.load then
    if targetAlive(job) then
      -- the runner's view was wrong (out of scope?): never leave the vehicle behind
      finish(job, 'fallback', 'targetGoneClaim')
      return fail(L('This tow is no longer active'), 'gone')
    end
    startLeaving(job)
    return ok(nil)
  end
  return invalid()
end

function handlers.tick()
  return ok(nil)
end

-- { reason } the runner gave up (no road, vehicle too big, stuck, ...): delete everything now
function handlers.failed(job, src, payload)
  local reason = type(payload.reason) == 'string' and payload.reason:gsub('[^%w:_%-]', ''):sub(1, 32) or 'client'
  finish(job, 'fallback', 'client:' .. reason)
  return ok(nil)
end

-- { id, stage, ... } -> null | { attacher = 'self'|'remote' } (load)
lib.callback.register('nz:tow:progress', Utils.safe(function(source, payload)
  local src = tonumber(source)
  if not src or src <= 0 then return fail(L('Something went wrong')) end
  if type(payload) ~= 'table' then return invalid() end
  local id = toInt(payload.id, 1)
  local stage = type(payload.stage) == 'string' and payload.stage or nil
  local handler = stage and handlers[stage] or nil
  if not id or not handler then return invalid() end
  if not NZ.Access.rateLimit(src, 'tow:progress', 50) then
    return fail(L('Please wait a moment before trying again'), 'rate')
  end

  local job = jobs[id]
  if not job then return fail(L('This tow is no longer active'), 'gone') end
  if stage == 'attached' then
    if src ~= job.attacher then return fail(L('This tow is no longer active'), 'gone') end
  else
    if src ~= job.runner then return fail(L('This tow is no longer active'), 'gone') end
    local now = GetGameTimer()
    if now - job.lastReport < REPORT_GAP_MS then return fail(L('Please wait a moment before trying again'), 'rate') end
    job.lastReport = now
    job.lastSeen = now
  end
  return handler(job, src, payload)
end))

---------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if not src then return end
  for _, job in ipairs(snapshot()) do
    if job.officer == src then job.officer = nil end
    if job.attacher == src then job.attacher = nil end
    -- the watchdog hands the job over (or falls back) on its next tick
    if job.runner == src then job.runnerDropped = true end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  stopping = true
  Tow.stopAll('resourceStop')
end)
