--[[
  nayzeee-garages — client/towtruck.lua (NZ.Tow, client)

  Impound flatbed tow truck (docs/CARLOCK.md §11), client side. The server (server/towtruck.lua)
  stays the authority: it locks the impounded vehicle, picks one player client (the "runner")
  to play the scene, creates the truck + driver itself, follows every step through the
  `nz:tow:progress` callback, sends a new truck or hands the job to another player when needed
  and removes the vehicle, the truck and the driver once nobody is near. Nothing here decides
  anything valuable, and this client never creates an entity.

  - Runner (`nz:client:tow:start`): checks the vehicle fits on the bed (class, type, size from
    GetModelDimensions), picks a road node Config.Tow.spawnDistance away (out of sight, away
    from players, with a route to the vehicle, facing it when possible) and proposes it
    (`node`; the next best one when the server answers 'retry': another tow or a player is
    there); the server creates the flatbed + driver there. The runner takes control of them
    (NetworkRequestControlOfEntity: OneSync gives new entities to the player nearest to them)
    and keeps it while it runs the scene (SetNetworkIdCanMigrate false; released on stop), so
    every task runs on the client that simulates the NPCs. It drives to the spot in front of
    the vehicle, in line with it (rear of the bed towards its nose; behind it only when the
    front is taken), long range first, then a slow final approach that steers around parked
    cars. Stuck (no progress for STUCK_MS standing, LOST_MS moving; waiting at traffic lights
    does not count): re-path, then reverse a little and re-path, then, while nobody watches,
    move the truck to a hidden road node closer to the vehicle (nobody watching: neither this
    client's camera nor another player near it with a line of sight). A truck that stops beside
    the vehicle carries on to the spot, one that stops the wrong way round drives past the
    vehicle to the spot on its other side or is turned while nobody watches; when neither works
    and the vehicle is near the bed it loads from where it stands (bedPlan's side / lift path).
    Parked in line but a few metres short, it backs up to the vehicle. The driver steps out,
    walks to the bed controls (left side, near the rear) and works them while the vehicle
    slides up onto the bed (lerped attach offsets, tilted up the ramp); the driver gets back in
    and drives off with the vehicle attached, holding the truck whenever it comes off the bed.
    Out of sight (or far away) the leaving truck may migrate again to a player near its route.
    A step that fails reports `failed` (the server sends a new truck or ends the job); the
    empty truck drives off on its own when it can. A job handed over from another player
    (truck / driver net ids in the event) adopts the NPCs the same way.
  - Attacher (`nz:client:tow:attach`): the client that owns the impounded vehicle pulls it onto
    the bed (attachments are synced by the attached entity's owner). Normally the runner,
    which takes control of the vehicle before loading.
  - `nz:client:tow:fade`: entities this client simulates fade out before the server deletes them.
  - Every client: players cannot enter or drive a vehicle being towed (state bag `nzTowing`) or
    the tow truck (`nzTowTruck`).
  - `nz:client:tow:stop` ends the local part of a job (the NPCs and the vehicle may migrate
    again); with `dismiss` the server gave up on that truck: the client that simulates its
    driver gets him back in and drives the empty truck off (never with the vehicle on its bed).
    Resource stop removes the blips (the server removes the entities).
]]

local Tow = NZ.Tow
local Utils = NZ.Utils

local TARGET_WAIT_MS = 4000      -- the impounded vehicle must exist on this client within this time
local ADOPT_WAIT_MS = 3000       -- the truck + driver must exist here, simulated by this client
local POLL_MS = 400
local TICK_EVERY_MS = 8000       -- keep-alive report while no step is reported (server: 25 s)
local NEAR_RANGE = 22.0          -- metres from the parking spot: slow final approach
local PARKED_RANGE = 3.0         -- metres from the parking spot: stop
local GOOD_GAP = 9.0             -- truck rear this close to the vehicle: close enough to load
local NEAR_TIMEOUT_MS = 15000
local STUCK_MS = 10000           -- no progress for this long, standing: stuck
local LOST_MS = 30000            -- no progress for this long while moving (circling, lost): stuck
local MOVING_SPEED = 1.5         -- m/s: faster than this counts as moving
local LIGHTS_MAX_MS = 45000      -- waiting at traffic lights is no lack of progress, up to this long
local PROGRESS_STEP = 3.0        -- metres closer that count as progress
local MAX_RECOVER = 5            -- recoveries (re-path, reverse, skip ahead unseen) before giving up
local NUDGE_ACTION = 3           -- TaskVehicleTempAction: brake + reverse (backs out of what blocks it)
local NUDGE_MS = 2500
local RECOVERED_DIST = 30.0      -- metres of progress after a recovery that count as unstuck
local HEADING_TOLERANCE = 35.0   -- degrees between the parked truck and its spot
local MAX_TURNS = 3              -- wrong-way stops corrected before giving up
local NEAR_SPEED = 5.0           -- m/s on the final approach
local APPROACH_STYLE = 786492    -- steers around parked cars, peds and objects, never waits behind them
local SPOT_GAP = 1.5             -- metres between the vehicle and the truck's rear
local REAR_SPOT_PENALTY = 25.0   -- the truck stops in front of the vehicle unless that spot is much worse
local MOVED_RANGE = 5.0          -- the vehicle moved this far: new parking spot
local MOVED_LIMIT = 80.0         -- this far from where it was impounded: give up
local PLAYER_CLEARANCE = 45.0    -- spawn nodes this close to a player are avoided
local PLAYER_MIN = 8.0           -- ... and never this close (the server refuses them)
local SKIP_PLAYER_MIN = 25.0     -- a stuck truck is moved unseen only to a node this far from players
local NODE_CLEARANCE = 6.0       -- no vehicle this close to a spawn node
local NODE_SIGHT_RADIUS = 6.0    -- a truck-sized sphere at the node must be out of sight
local ROUTE_CHECKS = 6           -- best spawn nodes whose route to the vehicle is checked
local ROUTE_FACTOR = 3.0         -- route longer than this times the straight line (+ 60 m): detour
local NO_ROUTE = 99999.0         -- CalculateTravelDistanceBetweenPoints: no route (100000)
local CONTROL_WAIT_MS = 2500     -- asking for control of the vehicle before loading
local SCOPE_RANGE = 320.0        -- spawn nodes within this of the runner: in its OneSync scope (culling
                                 -- radius 424 m by default), so it receives the new NPCs and can take them
local SPOT_CLEARANCE = 3.5       -- no other vehicle this close to the parking spot
local RESERVE_MS = 15000         -- a picked spawn node is not used by another job meanwhile
local EXIT_TIMEOUT_MS = 6000
local WALK_TIMEOUT_MS = 9000
local ENTER_TIMEOUT_MS = 12000
local ATTACH_EXTRA_MS = 12000    -- waiting for another client's attachment: loadSeconds + this
local REMOTE_MARGIN_MS = 1000    -- another client pulls the vehicle on: its pull ends this much later
local DONE_GRACE_MS = 20000
local HOLD_MS = 2000             -- leaving: the truck waits this long per check while the vehicle is off the bed
local LEAVE_TRIES = 6            -- `leaving` refused while the vehicle is being put back on the bed
local GUARD_MS = 150
local RAMP_SHARE = 0.35          -- share of the loading time spent lining up behind the truck
local SIDE_SHARE = 0.15          -- ... of it backing out along the truck's side first (stood beside it)
local NODE_TRIES = 4             -- spawn nodes proposed (the server refuses a taken one: 'retry')
local LOAD_MAX_SECONDS = 20      -- Config.Tow.loadSeconds is clamped to 1..this (both sides)
local MAX_FADE = 8               -- entities per fade event
local LATERAL_REACH = 6.0        -- metres beside the truck a vehicle may stand and still be loaded (bedPlan)
local CLOSE_GAP = 4.0            -- parked with the vehicle farther than this behind the bed: backs up ...
local CLOSE_TO = 2.0             -- ... to this gap
local REVERSE_SPEED = 2.0        -- m/s while backing up to the vehicle
local REVERSE_MS = 6000
local REVERSE_STYLE = 1024 | 2   -- DriveInReverse + StopForPeds
local CAREFUL_SPEED = 8.0        -- m/s at most on the way after a recovery
local STOP_AT_LIGHTS = 128       -- driving style flag: stops at red lights
local WATCH_RANGE = 60.0         -- other players this close (with a line of sight) see the truck move
local UNPIN_RANGE = 200.0        -- the leaving truck this far from the runner: it may migrate again
local DISMISS_ENTER_MS = 10000   -- a dismissed driver walks back to the wheel this long, then warps

local jobs = {}                  -- [id] = runner job
local attaching = {}             -- [id] = { cancelled } while this client pulls a vehicle on
local guarded = {}               -- [bagName] = misses: towed vehicles / trucks players may not use
local reservedNodes = {}         -- { { pos, untilAt } }
local dismissing = {}            -- [driver] = true while a dismissed driver gets back in and leaves
local ended = {}                 -- [id] = the last job of that id cancelled here (a `dismiss` may follow)
local endedCount = 0
local guardRunning = false
local reportBusy = false
local stopping = false
local warned = {}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

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

--- Model hash in the signed 32-bit form (the server sends that form).
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

--- Natives return BOOL as a boolean or as 0 / 1 depending on the build.
local function truthy(value)
  return value == true or value == 1
end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] tow: %s'):format(message))
end

local function loadSeconds(value)
  return number(value, 6, 1, LOAD_MAX_SECONDS)
end

local function exists(entity)
  return type(entity) == 'number' and entity ~= 0 and truthy(DoesEntityExist(entity))
end

local function entityOf(netId)
  netId = toInt(netId, 1)
  if not netId or not truthy(NetworkDoesNetworkIdExist(netId)) then return nil end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if exists(entity) then return entity end
  return nil
end

--- This client simulates the entity (local entities count as owned).
local function owns(entity)
  if not exists(entity) then return false end
  if not truthy(NetworkGetEntityIsNetworked(entity)) then return true end
  return NetworkGetEntityOwner(entity) == PlayerId()
end

--- Ask OneSync for the entity (it gives new and migrating entities to the nearest player): true
--- once this client simulates it, within `ms`.
local function control(entity, ms)
  if owns(entity) then return true end
  if not exists(entity) then return false end
  local untilAt = GetGameTimer() + (ms or CONTROL_WAIT_MS)
  repeat
    NetworkRequestControlOfEntity(entity)
    Wait(100)
    if owns(entity) then return true end
  until GetGameTimer() >= untilAt or not exists(entity)
  return owns(entity)
end

--- Keep (`keep` true) or let go of the entity: while this client runs the scene nobody else may
--- take it over (tasks and attachments only work on the client that simulates the entity).
local function pin(entity, keep)
  if not owns(entity) or not truthy(NetworkGetEntityIsNetworked(entity)) then return end
  local netId = NetworkGetNetworkIdFromEntity(entity)
  if netId and netId ~= 0 then SetNetworkIdCanMigrate(netId, not keep) end
end

local function headingDiff(a, b)
  return (a - b + 180.0) % 360.0 - 180.0
end

local function dist2d(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function dims(model)
  local mn, mx = GetModelDimensions(model)
  mn = Utils.v3(mn) or { x = -1.0, y = -2.5, z = -0.6 }
  mx = Utils.v3(mx) or { x = 1.0, y = 2.5, z = 1.0 }
  return {
    min = mn,
    max = mx,
    length = mx.y - mn.y,
    width = mx.x - mn.x,
    height = mx.z - mn.z,
  }
end

local function offset(entity, x, y, z)
  return GetOffsetFromEntityInWorldCoords(entity, x + 0.0, y + 0.0, z + 0.0)
end

local function loadModel(hash, kind)
  if not hash or not truthy(IsModelInCdimage(hash)) then return false end
  if kind == 'vehicle' and not truthy(IsModelAVehicle(hash)) then return false end
  if kind == 'ped' and not truthy(IsModelAPed(hash)) then return false end
  if truthy(HasModelLoaded(hash)) then return true end
  local success = pcall(lib.requestModel, hash, 10000)
  return success and truthy(HasModelLoaded(hash))
end

---------------------------------------------------------------------------------------
-- Jobs and reports
---------------------------------------------------------------------------------------

local function active(job)
  return not stopping and not job.cancelled and jobs[job.id] == job
end

local function removeBlip(job)
  if job.blip and truthy(DoesBlipExist(job.blip)) then RemoveBlip(job.blip) end
  job.blip = nil
end

--- Let the job's entities migrate again (another runner may take them over).
local function unpinAll(job)
  if job.pinned then
    job.pinned = nil
    pin(job.truck, false)
    pin(job.driver, false)
    pin(job.target, false)
  end
end

--- End the local part of a job (server stop, new start for the same id, resource stop). The
--- truck and driver are the server's: removed there, or adopted by the next runner.
local function cancel(job)
  job.cancelled = true
  removeBlip(job)
  unpinAll(job)
  if jobs[job.id] == job then jobs[job.id] = nil end
  if ended[job.id] == nil then
    endedCount = endedCount + 1
    if endedCount > 32 then ended, endedCount = {}, 1 end
  end
  ended[job.id] = job
end

--- One `nz:tow:progress` report. Reports of every job of this client go one at a time (the
--- server rate-limits them per player) and are retried when rate-limited. Never throws.
---@return table result { ok, data?, error?, code? }
local function report(job, stage, data)
  local payload = type(data) == 'table' and data or {}
  payload.id, payload.stage = job.id, stage
  for attempt = 1, 6 do
    while reportBusy do Wait(50) end
    reportBusy = true
    job.lastReport = GetGameTimer()
    local success, result = pcall(lib.callback.await, 'nz:tow:progress', false, payload)
    reportBusy = false
    if not success then
      warnOnce('report', ('progress report failed: %s'):format(tostring(result)))
      return { ok = false, code = 'error' }
    end
    if type(result) ~= 'table' then return { ok = false, code = 'error' } end
    if result.ok or result.code ~= 'rate' then return result end
    Wait(200 * attempt)
  end
  return { ok = false, code = 'rate' }
end

--- Report a step; a refusal means the server ended or moved the job: stop here.
local function step(job, stage, data)
  if not active(job) then return false end
  local result = report(job, stage, data)
  if not result.ok then
    job.cancelled = true
    return false, result
  end
  return true, result
end

--- The empty truck drives off on its own (the server retires it and removes it once nobody is
--- near): never with the vehicle hanging on it, never when the driver is not at the wheel.
local function wanderOff(truck, driver, target)
  if not exists(truck) or not exists(driver) or not owns(driver) then return false end
  if not truthy(IsPedInVehicle(driver, truck, false)) or truthy(IsEntityDead(driver)) then return false end
  if target and exists(target) and truthy(IsEntityAttachedToEntity(target, truck)) then return false end
  SetVehicleIndicatorLights(truck, 0, false)
  SetVehicleIndicatorLights(truck, 1, false)
  TaskVehicleDriveWander(driver, truck, number(config().speed, 14.0, 3.0, 40.0),
    math.floor(number(config().drivingStyle, 786603, 0, 2147483647)))
  SetPedKeepTask(driver, true)
  return true
end

local function sendAway(job)
  if wanderOff(job.truck, job.driver, job.target) then job.sentAway = true end
end

--- Something failed on this client: the server sends a new truck or ends the job (the vehicle
--- does not fit: it is removed at once; otherwise everything goes once nobody is near).
local function giveUp(job, reason)
  if active(job) then
    pcall(sendAway, job)
    report(job, 'failed', { reason = reason })
  end
  job.cancelled = true
  Utils.debug(('tow %d: gave up (%s)'):format(job.id, tostring(reason)))
end

local function keepAlive(job)
  if GetGameTimer() - (job.lastReport or 0) < TICK_EVERY_MS then return end
  local result = report(job, 'tick')
  if not result.ok and result.code ~= 'rate' then job.cancelled = true end
end

--- Wait `ms`, keeping the job alive; false when the job ended meanwhile.
local function sleep(job, ms)
  local untilAt = GetGameTimer() + ms
  while GetGameTimer() < untilAt do
    Wait(math.min(POLL_MS, math.max(0, untilAt - GetGameTimer())))
    if not active(job) then return false end
    keepAlive(job)
  end
  return active(job)
end

--- The truck or the driver is gone or destroyed.
local function npcProblem(job)
  if not exists(job.truck) or not exists(job.driver) then return 'npc' end
  if truthy(IsEntityDead(job.driver)) or truthy(IsEntityDead(job.truck)) then return 'npc' end
  return nil
end

---------------------------------------------------------------------------------------
-- The impounded vehicle
---------------------------------------------------------------------------------------

local function waitForEntity(job, netId, ms)
  local untilAt = GetGameTimer() + ms
  repeat
    local entity = entityOf(netId)
    if entity then return entity end
    Wait(100)
  until GetGameTimer() >= untilAt or not active(job)
  return nil
end

local function anyoneInside(vehicle)
  if not truthy(IsVehicleSeatFree(vehicle, -1)) then return true end
  return (tonumber(GetVehicleNumberOfPassengers(vehicle)) or 0) > 0
end

--- Why this vehicle cannot go on the bed, or nil. `ownTruck`: the truck of a handed-over job
--- (the vehicle may already hang on its bed).
local function unsuitable(vehicle, ownTruck)
  local cfg = config()
  local model = GetEntityModel(vehicle)
  local class = GetVehicleClass(vehicle)
  for _, skipped in ipairs(type(cfg.skipClasses) == 'table' and cfg.skipClasses or {}) do
    if class == skipped then return 'class' end
  end
  if truthy(IsThisModelABoat(model)) or truthy(IsThisModelAHeli(model))
    or truthy(IsThisModelAPlane(model)) or truthy(IsThisModelATrain(model)) then
    return 'type'
  end
  local size = dims(model)
  local limit = type(cfg.maxSize) == 'table' and cfg.maxSize or {}
  if size.length > number(limit.length, 6.9, 1.0, 30.0) or size.width > number(limit.width, 2.9, 0.5, 10.0)
    or size.height > number(limit.height, 3.4, 0.5, 10.0) then
    return 'size'
  end
  if truthy(IsEntityAttached(vehicle)) and not (ownTruck and truthy(IsEntityAttachedToEntity(vehicle, ownTruck))) then
    return 'attached'
  end
  if truthy(IsVehicleAttachedToTrailer(vehicle)) then return 'trailer' end
  if anyoneInside(vehicle) then return 'occupied' end
  return nil
end

--- The impounded vehicle still exists here (and its handle was not given to another entity).
local function targetHere(job)
  if not exists(job.target) then return false end
  if not truthy(NetworkGetEntityIsNetworked(job.target)) then return true end
  return NetworkGetNetworkIdFromEntity(job.target) == job.netId
end

--- The vehicle hangs on something other than our truck (another tow, a cargobob ...).
local function foreignAttach(job)
  if not truthy(IsEntityAttached(job.target)) then return false end
  return not truthy(IsEntityAttachedToEntity(job.target, job.truck))
end

---------------------------------------------------------------------------------------
-- Places: spawn node and parking spot
---------------------------------------------------------------------------------------

local function playerPositions()
  local list = {}
  for _, player in ipairs(GetActivePlayers() or {}) do
    local ped = GetPlayerPed(player)
    if exists(ped) then list[#list + 1] = GetEntityCoords(ped) end
  end
  return list
end

local function nearestPlayer(players, pos)
  local best = math.huge
  for i = 1, #players do
    local d = Utils.dist(players[i], pos)
    if d < best then best = d end
  end
  return best
end

--- Positions of the vehicles around (one walk over the pool), without the given ones; nil
--- when the pool cannot be read.
local function vehiclePositions(ignoreA, ignoreB)
  local success, pool = pcall(GetGamePool, 'CVehicle')
  if not success or type(pool) ~= 'table' then return nil end
  local list = {}
  for _, vehicle in ipairs(pool) do
    if vehicle ~= ignoreA and vehicle ~= ignoreB then list[#list + 1] = GetEntityCoords(vehicle) end
  end
  return list
end

--- No vehicle (from `vehicles`, see vehiclePositions) within `radius` of `pos`.
local function spotFree(pos, radius, vehicles)
  if not vehicles then return not truthy(IsAnyVehicleNearPoint(pos.x, pos.y, pos.z, radius + 0.0)) end
  for i = 1, #vehicles do
    if Utils.dist(vehicles[i], pos) < radius then return false end
  end
  return true
end

local function isReserved(pos)
  local now = GetGameTimer()
  for i = #reservedNodes, 1, -1 do
    local r = reservedNodes[i]
    if r.untilAt < now then
      table.remove(reservedNodes, i)
    elseif Utils.dist(r.pos, pos) < 12.0 then
      return true
    end
  end
  return false
end

--- Path nodes stream around the player; ask for the area around the vehicle (best effort).
local function loadNodes(center, radius)
  local x1, y1, x2, y2 = center.x - radius, center.y - radius, center.x + radius, center.y + radius
  local untilAt = GetGameTimer() + 2000
  while GetGameTimer() < untilAt do
    local success, loaded = pcall(AreNodesLoadedForArea, x1, y1, x2, y2)
    if not success or truthy(loaded) then return end
    pcall(RequestPathNodesInAreaThisFrame, x1, y1, x2, y2)
    Wait(0)
  end
end

--- Road nodes between minD and maxD (2D) from `center`.
local function roadNodes(center, minD, maxD)
  loadNodes(center, maxD + 20.0)
  local seen, list = {}, {}
  local function consider(found, pos, heading)
    if not truthy(found) then return end
    pos = Utils.v3(pos)
    if not pos then return end
    local key = ('%d:%d'):format(math.floor(pos.x), math.floor(pos.y))
    if seen[key] then return end
    seen[key] = true
    local d = dist2d(pos, center)
    if d < minD or d > maxD or math.abs(pos.z - center.z) > 35.0 then return end
    list[#list + 1] = { pos = vector3(pos.x, pos.y, pos.z), heading = tonumber(heading) or 0.0, dist = d }
  end
  for ring = 1, 3 do
    local r = minD + (maxD - minD) * (ring - 0.5) / 3
    for i = 0, 11 do
      local a = (i + ring * 0.5) * math.pi / 6
      consider(GetClosestVehicleNodeWithHeading(center.x + math.cos(a) * r, center.y + math.sin(a) * r, center.z, 0, 3.0, 0))
    end
  end
  if #list < 4 then
    for n = 5, 150, 3 do
      consider(GetNthClosestVehicleNodeWithHeading(center.x, center.y, center.z, n, 0, 3.0, 0.0))
    end
  end
  return list
end

--- Route length by road between two places, or nil when the game cannot tell (NO_ROUTE and
--- above: no route at all).
local function routeLength(from, to)
  local success, length = pcall(CalculateTravelDistanceBetweenPoints, from.x, from.y, from.z, to.x, to.y, to.z)
  length = success and tonumber(length) or nil
  if not length or length ~= length or length <= 0 then return nil end
  return length
end

--- Best node: free, out of sight of this client, away from players, mid-range, facing the
--- vehicle, with a route to it. `opts.hidden`: out of sight only; `opts.playerMin`: never this
--- close to a player. The scoring never yields (the vehicle pool is read once), so two jobs
--- never reserve the same node.
local function pickNode(center, minD, maxD, opts)
  opts = opts or {}
  local playerMin = opts.playerMin or PLAYER_MIN
  local nodes = roadNodes(center, minD, maxD)
  local players = playerPositions()
  local self = GetEntityCoords(PlayerPedId())
  local vehicles = vehiclePositions()
  local ranked = {}
  for _, c in ipairs(nodes) do
    local near = nearestPlayer(players, c.pos)
    if near >= playerMin and Utils.dist(c.pos, self) <= SCOPE_RANGE and spotFree(c.pos, NODE_CLEARANCE, vehicles)
      and not isReserved(c.pos) then
      local visible = truthy(IsSphereVisible(c.pos.x, c.pos.y, c.pos.z + 1.5, NODE_SIGHT_RADIUS))
      if not (opts.hidden and visible) then
        local score = math.abs(c.dist - (minD + maxD) / 2)
        if visible then score = score + 1000.0 end
        if near < PLAYER_CLEARANCE then score = score + 500.0 + (PLAYER_CLEARANCE - near) end
        -- the lane heads away from the vehicle: the truck would have to turn first
        local h = math.rad(c.heading)
        if (center.x - c.pos.x) * -math.sin(h) + (center.y - c.pos.y) * math.cos(h) < 0 then score = score + 30.0 end
        c.score = score
        ranked[#ranked + 1] = c
      end
    end
  end
  table.sort(ranked, function(x, y) return x.score < y.score end)
  -- a clear path: the best nodes with a sensible route to the vehicle first (an island of road,
  -- a car park exit the wrong way, the other side of a motorway are skipped)
  local best
  for i = 1, math.min(#ranked, ROUTE_CHECKS) do
    local c = ranked[i]
    local route = routeLength(c.pos, center)
    if route == nil or (route < NO_ROUTE and route <= c.dist * ROUTE_FACTOR + 60.0) then
      best = c
      break
    end
  end
  best = best or ranked[1]
  if best then reservedNodes[#reservedNodes + 1] = { pos = best.pos, untilAt = GetGameTimer() + RESERVE_MS } end
  return best
end

local function spawnNode(job)
  local range = type(config().spawnDistance) == 'table' and config().spawnDistance or {}
  local minD = number(range.min, 80.0, 20.0, 400.0)
  local maxD = math.max(minD + 10.0, number(range.max, 150.0, 30.0, 450.0))
  local center = GetEntityCoords(job.target)
  -- the server accepts nodes up to spawnDistance.max + 40 m (+ a little slack) from the vehicle
  return pickNode(center, minD, maxD) or pickNode(center, math.max(30.0, minD * 0.5), maxD + 40.0)
end

--- Propose spawn nodes until the server accepts one and creates the truck + driver there. It
--- refuses a node another tow (another runner's reservations are not visible here) or a player
--- is on with code 'retry': pickNode reserved that node, so the next one differs. Returns the
--- accepted result; nil + reason to give up; nil when the job ended or moved to another client
--- (the job is cancelled then).
local function proposeNode(job)
  for _ = 1, NODE_TRIES do
    local node = spawnNode(job)
    if not active(job) then return nil end
    if not node then return nil, 'node' end
    local result = report(job, 'node', { x = node.pos.x, y = node.pos.y, z = node.pos.z, heading = node.heading })
    if result.ok then return result end
    if result.code ~= 'retry' or not active(job) then
      job.cancelled = true
      return nil
    end
    Utils.debug(('tow %d: spawn node taken, trying another one'):format(job.id))
  end
  return nil, 'node'
end

--- The two places the truck can load from, in line with the vehicle: ahead of it (same
--- heading: loads nose first) and behind it (opposite heading: loads tail first).
local function parkingSpots(job)
  local pos, heading = GetEntityCoords(job.target), GetEntityHeading(job.target)
  local fwd = Utils.v3(GetEntityForwardVector(job.target)) or { x = 0.0, y = 1.0, z = 0.0 }
  local tMin, tMax = job.targetSize.min, job.targetSize.max
  local truckRear = -job.truckSize.min.y
  local function at(distance, h)
    return { pos = vector3(pos.x + fwd.x * distance, pos.y + fwd.y * distance, pos.z), heading = h % 360.0 }
  end
  return {
    at(tMax.y + SPOT_GAP + truckRear, heading),
    at(-(-tMin.y + SPOT_GAP + truckRear), heading + 180.0),
  }
end

--- Where the truck parks, and the other spot. In front of the vehicle unless that spot is much
--- worse (taken, off the road, the truck would arrive from the wrong side). A spot counts as
--- reachable when the truck gets there driving along the spot's heading: it passes the
--- vehicle and stops beyond it, rear towards it. Coming from the other side it would stop
--- facing the vehicle.
local function parkingSpot(job)
  local spots = parkingSpots(job)
  local truckPos = exists(job.truck) and GetEntityCoords(job.truck) or GetEntityCoords(job.target)
  local vehicles = vehiclePositions(job.truck, job.target)
  local bestIndex, bestScore = 1, math.huge
  for i, spot in ipairs(spots) do
    local score = Utils.dist(truckPos, spot.pos)
    local h = math.rad(spot.heading)
    if (spot.pos.x - truckPos.x) * -math.sin(h) + (spot.pos.y - truckPos.y) * math.cos(h) < 0 then
      score = score + 500.0
    end
    if not spotFree(spot.pos, SPOT_CLEARANCE, vehicles) then score = score + 1000.0 end
    if not truthy(IsPointOnRoad(spot.pos.x, spot.pos.y, spot.pos.z, 0)) then score = score + 60.0 end
    if i == 2 then score = score + REAR_SPOT_PENALTY end
    if score < bestScore then bestIndex, bestScore = i, score end
  end
  return spots[bestIndex], spots[3 - bestIndex]
end

--- The truck faces the spot's way (the vehicle then is behind its bed).
local function aligned(job, spot)
  return math.abs(headingDiff(GetEntityHeading(job.truck), spot.heading)) <= HEADING_TOLERANCE
end

--- The vehicle stands behind the truck, in line with it (ready to be pulled on).
local function behindTruck(job)
  local at = GetEntityCoords(job.target)
  local here = Utils.v3(GetOffsetFromEntityGivenWorldCoords(job.truck, at.x, at.y, at.z))
  if not here then return false end
  local relative = math.abs(headingDiff(GetEntityHeading(job.target), GetEntityHeading(job.truck)))
  return here.y < job.truckSize.min.y and math.abs(here.x) < 2.5
    and (relative <= HEADING_TOLERANCE or relative >= 180.0 - HEADING_TOLERANCE)
end

--- Gap between the truck's rear and the vehicle (metres, footprints approximated).
local function rearGap(job)
  local rear = offset(job.truck, 0.0, job.truckSize.min.y, 0.0)
  local centre = offset(job.target, 0.0, (job.targetSize.min.y + job.targetSize.max.y) / 2, 0.0)
  return math.max(0.0, Utils.dist(rear, centre) - job.targetSize.length / 2)
end

---------------------------------------------------------------------------------------
-- Truck and driver
---------------------------------------------------------------------------------------

--- Take over the truck + driver the server created (or a handed-over job's). This client must
--- simulate the driver: the tasks are given here. OneSync hands new entities to the player
--- nearest to them, so control is asked for; once here they stay here (pinned) until the job
--- ends on this client. Returns false + reason on failure; false without a reason when another
--- client keeps them (the server hands the job over).
local function adoptNpcs(job)
  local untilAt = GetGameTimer() + ADOPT_WAIT_MS
  local truck, driver
  while true do
    truck, driver = entityOf(job.adoptTruck), entityOf(job.adoptDriver)
    if truck and driver then
      if owns(truck) and owns(driver) then break end
      if not owns(truck) then NetworkRequestControlOfEntity(truck) end
      if not owns(driver) then NetworkRequestControlOfEntity(driver) end
    end
    if GetGameTimer() >= untilAt or not active(job) then break end
    Wait(100)
  end
  if not active(job) then return false end
  if not truck or not driver then return false, 'adopt' end
  if not owns(driver) then
    job.cancelled = true
    return false
  end
  if not owns(truck) then warnOnce('truckOwner', 'the tow truck is simulated by another client than its driver') end
  job.truck, job.driver = truck, driver
  job.truckNet, job.driverNet = job.adoptTruck, job.adoptDriver
  job.pinned = true
  pin(truck, true)
  pin(driver, true)
  return true
end

local function prepareNpcs(job)
  local driver, truck = job.driver, job.truck
  SetEntityAsMissionEntity(truck, true, true)
  SetEntityAsMissionEntity(driver, true, true)
  SetBlockingOfNonTemporaryEvents(driver, true)
  SetPedKeepTask(driver, true)
  SetPedCanBeDraggedOut(driver, false)
  SetPedFleeAttributes(driver, 0, false)
  SetPedCombatAttributes(driver, 17, false)  -- never flee
  SetPedConfigFlag(driver, 32, false)        -- not thrown through the windscreen
  SetEntityInvincible(driver, true)
  SetDriverAbility(driver, 1.0)
  SetDriverAggressiveness(driver, 0.0)
  SetVehicleEngineOn(truck, true, true, false)
  SetVehicleHasBeenOwnedByPlayer(truck, false)
  SetVehicleNeedsToBeHotwired(truck, false)
  SetVehicleDoorsLockedForAllPlayers(truck, true)
  if job.fresh then
    -- just created out of sight: seat the driver when the server's seat request did not land
    if not truthy(IsPedInVehicle(driver, truck, false)) then SetPedIntoVehicle(driver, truck, -1) end
    local plate = config().plate
    if type(plate) == 'string' and plate ~= '' then SetVehicleNumberPlateText(truck, plate:sub(1, 8)) end
    SetVehicleOnGroundProperly(truck)
  end
end

local function addBlip(job)
  local cfg = type(config().blip) == 'table' and config().blip or {}
  if not job.officer or cfg.enabled == false or job.blip then return end
  local blip = AddBlipForEntity(job.truck)
  if not blip or blip == 0 then return end
  SetBlipSprite(blip, math.floor(number(cfg.sprite, 68, 0, 1000)))
  SetBlipColour(blip, math.floor(number(cfg.color, 17, 0, 100)))
  SetBlipScale(blip, number(cfg.scale, 0.8, 0.1, 3.0))
  SetBlipAsShortRange(blip, false)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(L('Tow truck'))
  EndTextCommandSetBlipName(blip)
  job.blip = blip
end

local function hazards(job, on)
  if not exists(job.truck) then return end
  SetVehicleIndicatorLights(job.truck, 0, on)
  SetVehicleIndicatorLights(job.truck, 1, on)
end

--- Driver into the driver seat (walks, then warps after a timeout).
local function boardTruck(job)
  local driver, truck = job.driver, job.truck
  if truthy(IsPedInVehicle(driver, truck, false)) then return true end
  ClearPedTasks(driver)
  TaskEnterVehicle(driver, truck, ENTER_TIMEOUT_MS, -1, 1.0, 1, 0)
  local untilAt = GetGameTimer() + ENTER_TIMEOUT_MS + 1000
  while GetGameTimer() < untilAt do
    if not sleep(job, POLL_MS) or npcProblem(job) then return false end
    if truthy(IsPedInVehicle(driver, truck, false)) then return true end
  end
  TaskWarpPedIntoVehicle(driver, truck, -1)
  Wait(300)
  return truthy(IsPedInVehicle(driver, truck, false))
end

---------------------------------------------------------------------------------------
-- Driving to the vehicle
---------------------------------------------------------------------------------------

--- speed, normal driving style, style of the final approach and of recoveries
local function driveSettings()
  local cfg = config()
  return number(cfg.speed, 14.0, 3.0, 40.0), math.floor(number(cfg.drivingStyle, 786603, 0, 2147483647)),
    math.floor(number(cfg.approachStyle, APPROACH_STYLE, 0, 2147483647))
end

local function halt(job)
  TaskVehicleTempAction(job.driver, job.truck, 27, 3000)
  local untilAt = GetGameTimer() + 3000
  while GetGameTimer() < untilAt and not truthy(IsVehicleStopped(job.truck)) do
    if not sleep(job, 200) then return end
  end
end

--- Another player (a second officer, the vehicle's owner ...) may see the truck move: one
--- within WATCH_RANGE of the truck with a line of sight to it, or within WATCH_RANGE of `pos`
--- (a spot beside the vehicle) with a line of sight to the vehicle. This client's own view is
--- checked with IsEntityOnScreen / IsSphereVisible.
local function watchedByOthers(job, pos)
  local truckPos = GetEntityCoords(job.truck)
  for _, player in ipairs(GetActivePlayers() or {}) do
    if player ~= PlayerId() then
      local ped = GetPlayerPed(player)
      if exists(ped) then
        local at = GetEntityCoords(ped)
        if Utils.dist(at, truckPos) <= WATCH_RANGE and truthy(HasEntityClearLosToEntity(ped, job.truck, 17)) then
          return true
        end
        if pos and Utils.dist(at, pos) <= WATCH_RANGE and exists(job.target)
          and truthy(HasEntityClearLosToEntity(ped, job.target, 17)) then
          return true
        end
      end
    end
  end
  return false
end

--- Move the truck onto `spot` while nobody watches; false when it is on screen (here or for
--- another player near it) or the spot is taken. `spot.visibleOk`: the spot itself may be in
--- this client's view (the truck is only turned where it stands).
local function placeUnseen(job, spot)
  if truthy(IsEntityOnScreen(job.truck)) then return false end
  if truthy(IsSphereVisible(spot.pos.x, spot.pos.y, spot.pos.z + 1.0, 5.0)) and spot.visibleOk ~= true then
    return false
  end
  if watchedByOthers(job, spot.pos) then return false end
  if not spotFree(spot.pos, SPOT_CLEARANCE, vehiclePositions(job.truck, job.target)) then return false end
  SetEntityCoords(job.truck, spot.pos.x, spot.pos.y, spot.pos.z + 0.5, false, false, false, false)
  SetEntityHeading(job.truck, spot.heading + 0.0)
  SetVehicleOnGroundProperly(job.truck)
  return true
end

--- Last resort when stuck: move the truck while nobody watches (to the parking spot when it
--- is hidden and free, else to a hidden free road node closer to the vehicle, away from
--- players).
local function skipAhead(job, spot)
  if truthy(IsEntityOnScreen(job.truck)) or watchedByOthers(job) then return false end
  if placeUnseen(job, spot) then return true end
  local targetPos = GetEntityCoords(job.target)
  local node = pickNode(targetPos, 25.0, 60.0, { hidden = true, playerMin = SKIP_PLAYER_MIN })
  if not node or Utils.dist(node.pos, targetPos) >= Utils.dist(GetEntityCoords(job.truck), targetPos) then
    return false
  end
  SetEntityCoords(job.truck, node.pos.x, node.pos.y, node.pos.z + 0.5, false, false, false, false)
  SetEntityHeading(job.truck, node.heading + 0.0)
  SetVehicleOnGroundProperly(job.truck)
  return true
end

--- The truck stopped by the vehicle the wrong way round (TASK_VEHICLE_* can end facing either
--- way). Off screen it is turned in place: true. On screen: false + the spot on the vehicle's
--- other side (driving there from here ends with the right heading: the truck passes the
--- vehicle), or nil when that spot is taken.
local function realign(job, spot, other)
  local unseen = { pos = spot.pos, heading = spot.heading, visibleOk = true }
  if placeUnseen(job, unseen) then return true end
  if other and spotFree(other.pos, SPOT_CLEARANCE, vehiclePositions(job.truck, job.target)) then
    return false, other
  end
  return false, nil
end

--- Close enough to load from where the truck stopped although it is not in line with the
--- vehicle (wrong way round, at an angle, beside it): bedPlan brings a vehicle beside or ahead
--- of the bed on along a path that never goes through the truck.
local function closeEnough(job)
  if rearGap(job) > GOOD_GAP + 4.0 then return false end
  local at = GetEntityCoords(job.target)
  local here = Utils.v3(GetOffsetFromEntityGivenWorldCoords(job.truck, at.x, at.y, at.z))
  if not here then return false end
  return math.abs(here.x) <= job.truckSize.max.x + LATERAL_REACH
end

--- Parked in line with the vehicle but a few metres short: the truck backs up slowly until the
--- rear of the bed is CLOSE_TO from it (bounded), so the vehicle is not dragged a long way
--- along the ground before the ramp.
local function closeIn(job)
  if not owns(job.driver) or not truthy(IsPedInVehicle(job.driver, job.truck, false)) then return end
  if not behindTruck(job) then return end
  local gap = rearGap(job)
  if gap <= CLOSE_GAP then return end
  local to = offset(job.truck, 0.0, -(gap - CLOSE_TO), 0.0)
  TaskVehicleDriveToCoord(job.driver, job.truck, to.x, to.y, to.z, REVERSE_SPEED, 0, GetEntityModel(job.truck),
    REVERSE_STYLE, 0.5, -1.0)
  local untilAt = GetGameTimer() + REVERSE_MS
  while GetGameTimer() < untilAt do
    if not sleep(job, 200) or npcProblem(job) or not targetHere(job) then return end
    if rearGap(job) <= CLOSE_TO + 0.5 or not behindTruck(job) then break end
  end
  halt(job)
end

--- Drive to the parking spot. Returns true when parked in line with the vehicle, close enough
--- to load (or, out of ways to line up, with the vehicle near the bed: see closeEnough), else false + reason ('targetGone' | 'moved' | 'npc' | 'stuck' | 'heading'); false
--- without a reason when the job ended.
---
--- Stuck = no progress towards the spot for STUCK_MS while standing (LOST_MS while moving:
--- circling, lost), not counting the wait at traffic lights. Each time it recovers one step
--- further: 1 re-path with the approach style (steers around what blocks it), 2 reverse a
--- little then re-path, 3+ move the truck to a hidden road node closer to the vehicle while
--- nobody watches (else reverse + re-path again); after MAX_RECOVER it gives up ('stuck').
local function approach(job)
  local speed, style, approachStyle = driveSettings()
  local spot, other = parkingSpot(job)
  local phase = 'far'
  local recoveries, recoverDist, turns = 0, math.huge, 0
  local anchor = GetEntityCoords(job.target)
  local best, lastProgress = math.huge, GetGameTimer()
  local nearSince, lightsWaited = 0, 0

  local function drive(careful)
    if not owns(job.driver) then return end -- the server hands the job to the new owner
    if phase == 'far' then
      -- after a recovery: steers around what blocked it, but slower and still stops at red lights
      TaskVehicleDriveToCoordLongrange(job.driver, job.truck, spot.pos.x, spot.pos.y, spot.pos.z,
        careful and math.min(speed, CAREFUL_SPEED) or speed, careful and (approachStyle | STOP_AT_LIGHTS) or style, 10.0)
    else
      TaskVehicleDriveToCoord(job.driver, job.truck, spot.pos.x, spot.pos.y, spot.pos.z, NEAR_SPEED, 0,
        GetEntityModel(job.truck), approachStyle, 1.0, 40.0)
    end
    SetPedKeepTask(job.driver, true)
  end

  --- Back out of whatever blocks the truck (a wall, a parked car), then drive on.
  local function nudge()
    if not owns(job.driver) then return end
    TaskVehicleTempAction(job.driver, job.truck, NUDGE_ACTION, NUDGE_MS)
    sleep(job, NUDGE_MS + 100)
  end

  --- One recovery step (see above); false when there is nothing left to try.
  local function recover()
    recoveries = recoveries + 1
    if recoveries > MAX_RECOVER then return false end
    Utils.debug(('tow %d: stuck, recovery %d'):format(job.id, recoveries))
    if recoveries >= 3 and skipAhead(job, spot) then
      spot, other = parkingSpot(job)
      phase = 'far'
    elseif recoveries >= 2 then
      nudge()
      if not active(job) then return true end
    end
    local now = GetGameTimer()
    best, lastProgress, nearSince = math.huge, now, now
    recoverDist = Utils.dist(GetEntityCoords(job.truck), spot.pos)
    drive(true)
    return true
  end

  drive(false)
  while true do
    if not sleep(job, POLL_MS) then return false end
    local problem = npcProblem(job)
    if problem then return false, problem end
    if not targetHere(job) then return false, 'targetGone' end
    local targetPos = GetEntityCoords(job.target)
    if Utils.dist(targetPos, job.origin) > MOVED_LIMIT or foreignAttach(job) then return false, 'moved' end

    local now = GetGameTimer()
    if Utils.dist(targetPos, anchor) > MOVED_RANGE then
      -- pushed or bumped: new spot from where it stands now
      anchor = targetPos
      spot, other = parkingSpot(job)
      best, lastProgress = math.huge, now
      drive(recoveries > 1)
    end

    local d = Utils.dist(GetEntityCoords(job.truck), spot.pos)
    if d < best - PROGRESS_STEP then best, lastProgress = d, now end
    -- a red light is no lack of progress (up to LIGHTS_MAX_MS in all)
    if lightsWaited < LIGHTS_MAX_MS and truthy(IsVehicleStoppedAtTrafficLights(job.truck)) then
      lightsWaited = lightsWaited + POLL_MS
      lastProgress = now
    end
    -- driving well again after a recovery (a jam, a parked car): back to the normal style
    if recoveries > 0 and d < recoverDist - RECOVERED_DIST then
      recoveries, recoverDist = 0, math.huge
      drive(false)
    end
    if phase == 'far' and d <= NEAR_RANGE then
      phase, nearSince, lastProgress, best = 'near', now, now, d
      drive(false)
    end
    if phase == 'near' then
      local gap = rearGap(job)
      local stopped = d <= PARKED_RANGE
        or (gap <= GOOD_GAP and truthy(IsVehicleStopped(job.truck)) and now - nearSince > 4000)
      if not stopped and now - nearSince > NEAR_TIMEOUT_MS then
        -- close and the vehicle behind the bed: load from here; else stuck (below)
        if gap <= GOOD_GAP + 4.0 and behindTruck(job) then stopped = true else lastProgress = 0 end
      end
      if stopped then
        halt(job)
        if not active(job) then return false end
        -- never load a vehicle that is not behind the bed: it would be dragged through the truck
        local inLine = aligned(job, spot)
        if inLine and behindTruck(job) then
          closeIn(job)
          return active(job)
        end
        turns = turns + 1
        if turns > MAX_TURNS then
          -- out of tries: load from here when the vehicle is near the bed (side / lift path)
          if closeEnough(job) then return true end
          return false, 'heading'
        end
        if inLine and Utils.dist(GetEntityCoords(job.truck), spot.pos) > PARKED_RANGE then
          -- the right way round but beside or short of the vehicle (passing it, waiting in
          -- traffic): carry on to the spot
          Utils.debug(('tow %d: stopped beside the vehicle, carries on to the spot (%d)'):format(job.id, turns))
          nearSince, lastProgress, best = now, now, math.huge
          drive(true)
        else
          local turned, nextSpot = realign(job, spot, other)
          if turned then return active(job) end
          if not nextSpot then
            -- on screen and the other side is taken: load from here when the vehicle is near
            -- the bed (bedPlan's side / lift path), else this truck cannot load it
            if closeEnough(job) then
              Utils.debug(('tow %d: not in line, loads from where it stands'):format(job.id))
              return true
            end
            return false, 'heading'
          end
          Utils.debug(('tow %d: wrong way round, parks on the other side (%d)'):format(job.id, turns))
          spot, other = nextSpot, spot
          nearSince, lastProgress, best = now, now, math.huge
          drive(true) -- around the vehicle
        end
      end
    end

    local moving = (tonumber(GetEntitySpeed(job.truck)) or 0.0) > MOVING_SPEED
    if now - lastProgress > (moving and LOST_MS or STUCK_MS) then
      if not recover() then return false, 'stuck' end
      if not active(job) then return false end
    end
  end
end

---------------------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------------------

--- Bed height above the bone, measured with a ray onto the truck (nil when it misses). The
--- vehicle being loaded is ignored (a handed-over job's may already sit on the bed).
local function measureSurface(truck, boneLocal, bedY, ignore)
  local top = offset(truck, 0.0, boneLocal.y + bedY, boneLocal.z + 4.0)
  local bottom = offset(truck, 0.0, boneLocal.y + bedY, boneLocal.z - 1.5)
  local success, handle = pcall(StartExpensiveSynchronousShapeTestLosProbe, top.x, top.y, top.z,
    bottom.x, bottom.y, bottom.z, 2, ignore or 0, 7)
  if not success or not handle then return nil end
  local _, hit, endCoords, _, entityHit = GetShapeTestResult(handle)
  if not truthy(hit) or entityHit ~= truck or not endCoords then return nil end
  local hitLocal = Utils.v3(GetOffsetFromEntityGivenWorldCoords(truck, endCoords.x, endCoords.y, endCoords.z))
  if not hitLocal then return nil end
  local surface = hitLocal.z - boneLocal.z
  if surface < -0.5 or surface > 2.5 then return nil end
  return surface
end

--- How the vehicle gets onto the bed, as poses relative to the truck bone: from where it stands
--- (`current`) along `path` to `final` (centred on the bed, wheels on the deck; its size
--- decides where it sits). Normally lined up behind the bed, then up the ramp; already hanging
--- on the truck (handed-over job): straight on; not behind the bed (the truck stopped beside
--- or ahead of it): lifted over the truck, never dragged through it.
local function bedPlan(truck, target)
  local bed = type(config().bed) == 'table' and config().bed or {}
  local bone = GetEntityBoneIndexByName(truck, type(bed.bone) == 'string' and bed.bone or 'bodyshell')
  if not bone or bone < 0 then bone = 0 end
  local boneLocal = { x = 0.0, y = 0.0, z = 0.0 }
  if bone > 0 then
    local world = Utils.v3(GetWorldPositionOfEntityBone(truck, bone))
    if world then boneLocal = Utils.v3(GetOffsetFromEntityGivenWorldCoords(truck, world.x, world.y, world.z)) or boneLocal end
  end
  local bedY = number(bed.y, -2.35, -15.0, 10.0)
  local rear = number(bed.rear, -6.0, -20.0, 5.0)
  local front = number(bed.front, 1.2, -10.0, 10.0)
  local surface = measureSurface(truck, boneLocal, bedY, target) or number(bed.surface, 0.55, -1.0, 3.0)
  local pitch = number(bed.pitch, 10.0, -30.0, 30.0)

  local size = dims(GetEntityModel(target))
  local truckSize = dims(GetEntityModel(truck))
  local relative = headingDiff(GetEntityHeading(target), GetEntityHeading(truck))
  local flipped = math.abs(relative) > 90.0
  local dir = flipped and -1.0 or 1.0
  local centreY = (size.min.y + size.max.y) / 2
  local final = { x = 0.0, y = bedY - dir * centreY, z = surface - size.min.z, h = flipped and 180.0 or 0.0 }
  -- long vehicles: never into the cab (the front end of the bed is `bed.front`); what does not
  -- fit hangs over the rear end
  local reach = final.y + math.max(dir * size.min.y, dir * size.max.y)
  if reach > front then final.y = final.y - (reach - front) end
  local ground = truckSize.min.z - boneLocal.z
  local ramp = { x = 0.0, y = rear - size.length / 2 - 0.4 - dir * centreY, z = ground - size.min.z, h = final.h }
  local at = GetEntityCoords(target)
  local here = Utils.v3(GetOffsetFromEntityGivenWorldCoords(truck, at.x, at.y, at.z)) or { x = 0.0, y = 0.0, z = 0.0 }
  local current = { x = here.x - boneLocal.x, y = here.y - boneLocal.y, z = here.z - boneLocal.z, h = relative }

  local path
  if truthy(IsEntityAttachedToEntity(target, truck)) then
    path = { { pose = final, share = 1.0 } }
  elseif current.y > ramp.y + size.length then
    local lift = truckSize.max.z - boneLocal.z + 0.5 - size.min.z
    path = {
      { pose = { x = current.x, y = current.y, z = math.max(lift, current.z), h = current.h }, share = 0.3 },
      { pose = { x = final.x, y = final.y, z = math.max(lift, current.z), h = final.h }, share = 0.4 },
      { pose = final, share = 0.3 },
    }
  else
    path = {
      { pose = ramp, share = RAMP_SHARE },
      -- up the ramp: the end that climbs first (the nose when it loads nose first) tilts up
      { pose = final, share = 1.0 - RAMP_SHARE, climb = true, pitch = dir * pitch },
    }
    -- beside the bed (the truck stopped next to it): straight back along the truck's side
    -- first, then across behind the bed, never diagonally through its rear corner
    local clear = (truckSize.max.x - truckSize.min.x) / 2 + size.width / 2 - 0.2
    if math.abs(current.x) > clear and current.y + size.length / 2 > rear then
      path[1].share = RAMP_SHARE - SIDE_SHARE
      table.insert(path, 1, { pose = { x = current.x, y = ramp.y, z = ramp.z, h = current.h }, share = SIDE_SHARE })
    end
  end
  return { bone = bone, current = current, final = final, path = path }
end

local function smooth(t)
  t = math.max(0.0, math.min(1.0, t))
  return t * t * (3.0 - 2.0 * t)
end

local function lerpPose(a, b, t)
  return {
    x = a.x + (b.x - a.x) * t,
    y = a.y + (b.y - a.y) * t,
    z = a.z + (b.z - a.z) * t,
    h = a.h + headingDiff(b.h, a.h) * t,
    p = (a.p or 0.0) + ((b.p or 0.0) - (a.p or 0.0)) * t,
  }
end

--- Pose at `t` (0..1) along the plan.
local function poseAt(plan, t)
  local from, start = plan.current, 0.0
  for i, leg in ipairs(plan.path) do
    if t <= start + leg.share or i == #plan.path then
      local u = math.max(0.0, math.min(1.0, (t - start) / leg.share))
      local pose = lerpPose(from, leg.pose, smooth(u))
      if leg.climb then
        -- up the ramp: the vehicle rises sooner than it moves forward
        pose.z = from.z + (leg.pose.z - from.z) * math.sin(math.min(1.0, u * 1.6) * math.pi / 2)
        -- tilted while it rises, level again once it reaches the deck
        pose.p = (leg.pitch or 0.0) * math.sin(math.min(1.0, u * 1.6) * math.pi)
      end
      return pose
    end
    start = start + leg.share
    from = leg.pose
  end
  return plan.final
end

local function attachAt(target, truck, bone, pose, final)
  AttachEntityToEntity(target, truck, bone, pose.x + 0.0, pose.y + 0.0, pose.z + 0.0, (pose.p or 0.0) + 0.0, 0.0, pose.h + 0.0,
    false, false, false, false, 2, true)
  if final then
    SetVehicleEngineOn(target, false, true, true)
    SetVehicleUndriveable(target, true)
  end
end

--- Pull the vehicle onto the bed over `seconds` (runs on the client that owns the vehicle:
--- attachments are synced by the attached entity's owner). `ended()` aborts.
---@return boolean attached
local function pullOntoBed(target, truck, seconds, ended)
  if not exists(target) or not exists(truck) or not owns(target) then return false end
  local plan = bedPlan(truck, target)
  local duration = math.floor(loadSeconds(seconds) * 1000)
  local direct = Utils.dist(plan.current, plan.final) < 1.0 -- already on the bed (handed-over job)
  local started = GetGameTimer()
  while not direct do
    if ended() or not exists(target) or not exists(truck) or not owns(target) then return false end
    local t = (GetGameTimer() - started) / duration
    if t >= 1.0 then break end
    attachAt(target, truck, plan.bone, poseAt(plan, t), false)
    Wait(0)
  end
  if ended() or not exists(target) or not exists(truck) or not owns(target) then return false end
  attachAt(target, truck, plan.bone, plan.final, true)
  return truthy(IsEntityAttachedToEntity(target, truck))
end

--- The driver walks to the bed controls (left side, near the rear) and works them.
local function toControls(job)
  local driver, truck = job.driver, job.truck
  TaskLeaveVehicle(driver, truck, 0)
  local untilAt = GetGameTimer() + EXIT_TIMEOUT_MS
  while truthy(IsPedInVehicle(driver, truck, false)) do
    if not sleep(job, 250) or npcProblem(job) then return false end
    if GetGameTimer() > untilAt then
      TaskLeaveVehicle(driver, truck, 16) -- out at once
      Wait(500)
      break
    end
  end
  hazards(job, true)
  local controls = offset(truck, job.truckSize.min.x - 0.55, job.truckSize.min.y + 1.6, 0.0)
  local face = (GetEntityHeading(truck) - 90.0) % 360.0 -- facing the side of the bed
  TaskGoStraightToCoord(driver, controls.x, controls.y, controls.z, 1.0, WALK_TIMEOUT_MS, face, 0.5)
  untilAt = GetGameTimer() + WALK_TIMEOUT_MS
  while GetGameTimer() < untilAt do
    if not sleep(job, 250) or npcProblem(job) then return false end
    if dist2d(GetEntityCoords(driver), controls) < 1.2 then break end
  end
  TaskAchieveHeading(driver, face, 800)
  if not sleep(job, 800) then return false end

  local anim = type(config().animation) == 'table' and config().animation or {}
  local dict, clip = anim.dict, anim.clip
  local loaded = type(dict) == 'string' and type(clip) == 'string' and pcall(lib.requestAnimDict, dict, 3000)
  if loaded then
    TaskPlayAnim(driver, dict, clip, 4.0, -4.0, -1, 1, 0.0, false, false, false)
    job.animDict = dict
  else
    TaskStartScenarioInPlace(driver, 'WORLD_HUMAN_CLIPBOARD', 0, true)
  end
  return true
end

local function stopWorking(job)
  -- a dismissed driver is already on his way back to the wheel (see dismiss)
  if exists(job.driver) and not job.dismissed then ClearPedTasks(job.driver) end
  if job.animDict then
    RemoveAnimDict(job.animDict)
    job.animDict = nil
  end
end

--- Another client attaches the vehicle: wait until it shows on the bed here.
local function waitAttached(job, ms)
  local untilAt = GetGameTimer() + ms
  while GetGameTimer() < untilAt do
    if not sleep(job, 250) then return false end
    if not exists(job.target) or not exists(job.truck) then return false end
    if truthy(IsEntityAttachedToEntity(job.target, job.truck)) then return true end
  end
  return false
end

--- Load the vehicle: this client pulls it on ('self') or waits for its owner ('remote').
local function load(job, attacher, seconds)
  local started = GetGameTimer()
  local attached
  if attacher == 'self' then
    attached = pullOntoBed(job.target, job.truck, seconds, function() return not active(job) end)
    if not attached and active(job) then
      -- the vehicle changed hands meanwhile: the server asks its new owner
      if not step(job, 'attached', { ok = false }) then return false end
      attached = waitAttached(job, seconds * 1000 + ATTACH_EXTRA_MS)
    end
  else
    attached = waitAttached(job, seconds * 1000 + ATTACH_EXTRA_MS)
  end
  -- the driver keeps working the controls for the whole loading time (another client's pull
  -- started a moment after ours: give it that moment to reach the bed)
  local left = seconds * 1000 - (GetGameTimer() - started) + (attacher == 'self' and 0 or REMOTE_MARGIN_MS)
  if attached and left > 0 and not sleep(job, left) then return false end
  if attached and active(job) and not owns(job.target) and control(job.target, CONTROL_WAIT_MS) then
    -- on the bed: from here the vehicle stays with the client that drives the truck
    pin(job.target, true)
  end
  return attached and active(job)
end

---------------------------------------------------------------------------------------
-- Leaving
---------------------------------------------------------------------------------------

local function driveAway(job)
  local speed, style = driveSettings()
  hazards(job, false)
  removeBlip(job)
  if owns(job.driver) then
    TaskVehicleDriveWander(job.driver, job.truck, speed, style)
    SetPedKeepTask(job.driver, true)
  end
end

--- The vehicle hangs on the truck (or is gone: nothing to wait for).
local function carrying(job)
  return not targetHere(job) or truthy(IsEntityAttachedToEntity(job.target, job.truck))
end

--- After leaving: the truck never drives on without the vehicle (it stops while the server
--- has it pulled back onto the bed, and goes on once it is there); tell the server once the
--- truck is out of this player's sight and range (it removes everything when every player is
--- far, or retires it after despawnSeconds). Once it is out of sight or UNPIN_RANGE away with
--- the vehicle on the bed, truck, driver and vehicle may migrate again: a player near its
--- route simulates it from there (this client no longer streams the roads it drives on);
--- the server then asks the vehicle's new owner to put it back if it comes off (the
--- `nz:client:tow:attach` handler holds the truck on the client that drives it).
local function watchLeaving(job)
  local cfg = config()
  local range = number(cfg.despawnDistance, 150.0, 30.0, 1000.0)
  local untilAt = GetGameTimer() + number(cfg.despawnSeconds, 60, 10, 600) * 1000 + DONE_GRACE_MS
  local told, held = false, false
  while active(job) and GetGameTimer() < untilAt do
    Wait(1000)
    if not exists(job.truck) then break end
    if not carrying(job) then
      if owns(job.driver) then TaskVehicleTempAction(job.driver, job.truck, 27, HOLD_MS) end
      if not held then Utils.debug(('tow %d: the vehicle came off the bed, the truck waits'):format(job.id)) end
      held = true
    elseif held then
      held = false
      driveAway(job)
    end
    local away = Utils.dist(GetEntityCoords(PlayerPedId()), GetEntityCoords(job.truck))
    if not told and not held and away > range and not truthy(IsEntityOnScreen(job.truck)) then
      told = true
      report(job, 'done')
    end
    if job.pinned and not held and (told or away > UNPIN_RANGE) and carrying(job) then
      unpinAll(job)
      Utils.debug(('tow %d: the leaving truck may migrate again'):format(job.id))
    end
  end
  if jobs[job.id] == job then jobs[job.id] = nil end
end

--- Report `leaving`; the server refuses it (code 'attach') while it does not see the vehicle on
--- the bed and has it pulled back on: the truck waits and asks again (bounded).
local function reportLeaving(job)
  for _ = 1, LEAVE_TRIES do
    if not active(job) then return false end
    local result = report(job, 'leaving')
    if result.ok then return true end
    if result.code ~= 'attach' then
      job.cancelled = true
      return false
    end
    if not sleep(job, HOLD_MS) then return false end
  end
  return false, 'attach'
end

--- The vehicle vanished (deleted by somebody else): the empty truck drives off.
local function leaveEmpty(job)
  if not step(job, 'leaving', { reason = 'targetGone' }) then return end
  stopWorking(job)
  if not boardTruck(job) then return end
  driveAway(job)
  watchLeaving(job)
end

---------------------------------------------------------------------------------------
-- The scene (runner)
---------------------------------------------------------------------------------------

local function scene(job)
  local cfg = config()

  -- 1. the impounded vehicle is here and fits on the bed
  local target = waitForEntity(job, job.netId, TARGET_WAIT_MS)
  if not active(job) then return end
  if not target or (job.model and toSigned(GetEntityModel(target)) ~= job.model) then return giveUp(job, 'target') end
  job.target = target
  local why = unsuitable(target, job.adoptTruck and entityOf(job.adoptTruck) or nil)
  if why then return giveUp(job, why) end
  job.origin = GetEntityCoords(target)
  job.targetSize = dims(GetEntityModel(target))

  -- 2. truck + driver: created by the server on a road node this client picks, or adopted
  local truckModel = modelHash(cfg.truck or 'flatbed')
  local driverModel = modelHash(cfg.driver or 's_m_m_trucker_01')
  if not loadModel(truckModel, 'vehicle') or not loadModel(driverModel, 'ped') then return giveUp(job, 'model') end
  job.truckSize = dims(truckModel)
  SetModelAsNoLongerNeeded(truckModel)
  SetModelAsNoLongerNeeded(driverModel)
  if not active(job) then return end
  if not job.adoptTruck or not job.adoptDriver then
    local result, problem = proposeNode(job)
    if not active(job) then return end
    if not result then return giveUp(job, problem or 'node') end
    local data = type(result.data) == 'table' and result.data or {}
    job.adoptTruck, job.adoptDriver, job.fresh = toInt(data.truck, 1), toInt(data.driver, 1), true
  end
  local ready, reason = adoptNpcs(job)
  if not active(job) then return end
  if not ready then return giveUp(job, reason or 'adopt') end
  if not step(job, 'spawned', { truck = job.truckNet, driver = job.driverNet }) then return end
  prepareNpcs(job)
  addBlip(job)
  -- a handed-over job may find the truck parked and the driver already out at the bed, or the
  -- vehicle already on the bed with the driver back at the wheel (it only has to leave)
  local onBed = not job.fresh and truthy(IsEntityAttachedToEntity(job.target, job.truck))
  local seated = truthy(IsPedInVehicle(job.driver, job.truck, false))
  local parked = not job.fresh and not seated
    and (onBed or (rearGap(job) <= GOOD_GAP + 4.0 and behindTruck(job)))
  local loadedAlready = onBed and seated
  if not parked and not loadedAlready and not boardTruck(job) then return giveUp(job, npcProblem(job) or 'board') end

  -- 3. drive to the vehicle
  if not parked and not loadedAlready then
    local problem
    parked, problem = approach(job)
    if not active(job) then return end
    if problem == 'targetGone' then return leaveEmpty(job) end
    if not parked then return giveUp(job, problem or 'stuck') end
  end
  if not step(job, 'arrived') then return end

  -- 4. the driver works the controls while the vehicle is pulled onto the bed. This client
  -- pulls it on itself when it simulates the vehicle (asked for while the driver walks)
  if exists(job.target) and not owns(job.target) then NetworkRequestControlOfEntity(job.target) end
  if not loadedAlready and not toControls(job) then
    if active(job) then giveUp(job, npcProblem(job) or 'controls') end
    return
  end
  if not targetHere(job) then return leaveEmpty(job) end
  if control(job.target, 1000) then
    job.pinned = true
    pin(job.target, true)
  end
  local accepted, result = step(job, 'load')
  if not accepted then return stopWorking(job) end
  local attacher = type(result.data) == 'table' and result.data.attacher or 'remote'
  -- already on the bed: it is only fixed in place (no slide, the driver stays at the wheel)
  local seconds = loadedAlready and 1 or loadSeconds(cfg.loadSeconds)
  local loaded = load(job, attacher, seconds)
  if not loadedAlready then stopWorking(job) end
  if not active(job) then return end
  if not loaded then
    if not targetHere(job) then return leaveEmpty(job) end
    return giveUp(job, 'attach')
  end
  if not step(job, 'loaded') then return end

  -- 5. back in and away, never without the vehicle
  if not boardTruck(job) then
    if active(job) then giveUp(job, npcProblem(job) or 'board') end
    return
  end
  local leaving, problem = reportLeaving(job)
  if not leaving then
    if problem and active(job) then giveUp(job, problem) end
    return
  end
  driveAway(job)
  watchLeaving(job)
end

local function run(job)
  local success, err = pcall(scene, job)
  if not success then
    lib.print.error(('[nayzeee-garages] tow %d: %s'):format(job.id, tostring(err)))
    giveUp(job, 'error')
  end
  removeBlip(job)
  if job.cancelled then cancel(job) end
  -- the scene is over here: the truck (and what it carries) may migrate to whoever is nearest
  unpinAll(job)
end

---------------------------------------------------------------------------------------
-- Guard: nobody uses a vehicle being towed or the tow truck
---------------------------------------------------------------------------------------

local function guardedVehicle(vehicle)
  if not exists(vehicle) or not truthy(NetworkGetEntityIsNetworked(vehicle)) then return false end
  local state = Entity(vehicle).state
  return state.nzTowing == true or state.nzTowTruck == true
end

local function guardTick()
  local ped = PlayerPedId()
  local entering = GetVehiclePedIsTryingToEnter(ped)
  if entering and entering ~= 0 and guardedVehicle(entering) then ClearPedTasks(ped) end
  local inside = GetVehiclePedIsIn(ped, false)
  if inside and inside ~= 0 and guardedVehicle(inside) then TaskLeaveVehicle(ped, inside, 16) end
end

--- Forget guarded vehicles whose network id is gone (deleted, or far out of scope).
local function sweepGuarded()
  for bagName, misses in pairs(guarded) do
    local netId = tonumber(bagName:match('^entity:(%d+)$'))
    if netId and truthy(NetworkDoesNetworkIdExist(netId)) then
      guarded[bagName] = 0
    elseif misses >= 2 then
      guarded[bagName] = nil
    else
      guarded[bagName] = misses + 1
    end
  end
end

local function startGuard()
  if guardRunning then return end
  guardRunning = true
  CreateThread(function()
    local sweepAt = 0
    while next(guarded) ~= nil and not stopping do
      Wait(GUARD_MS)
      local success, err = pcall(guardTick)
      if not success then warnOnce('guard', tostring(err)) end
      if GetGameTimer() >= sweepAt then
        sweepAt = GetGameTimer() + 3000
        sweepGuarded()
      end
    end
    guardRunning = false
  end)
end

local function onGuardBag(bagName, key, value)
  if type(bagName) ~= 'string' then return end
  if value ~= true then
    guarded[bagName] = nil
    return
  end
  guarded[bagName] = 0
  if key == 'nzTowing' then
    -- the server locked it already; keep this client's copy locked and stopped as well
    local entity = GetEntityFromStateBagName(bagName)
    if exists(entity) then
      SetVehicleDoorsLocked(entity, 2)
      if owns(entity) then
        SetVehicleEngineOn(entity, false, true, true)
        SetVehicleUndriveable(entity, true)
      end
    end
  end
  startGuard()
end

AddStateBagChangeHandler('nzTowing', nil, function(bagName, key, value)
  local success, err = pcall(onGuardBag, bagName, key, value)
  if not success then warnOnce('bag', tostring(err)) end
end)

AddStateBagChangeHandler('nzTowTruck', nil, function(bagName, key, value)
  local success, err = pcall(onGuardBag, bagName, key, value)
  if not success then warnOnce('bag', tostring(err)) end
end)

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Is this vehicle being towed, or is it a tow truck (nobody may use it)?
---@param vehicle number
---@return boolean
function Tow.isTowing(vehicle)
  local success, result = pcall(guardedVehicle, vehicle)
  return success and result == true
end

--- Tow jobs this client is running (debug / other modules).
---@return integer
function Tow.activeCount()
  local n = 0
  for _ in pairs(jobs) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------------------
-- Dismissed trucks
---------------------------------------------------------------------------------------

--- The server gave up on this truck (a new one comes, or the tow ended) while players may see
--- it: the driver stops working the controls, turns the hazards off, gets back in (walks, then
--- warps after DISMISS_ENTER_MS) and drives the empty truck off, so the spot at the vehicle is
--- free for the next truck and nothing stands around in front of the officer. A truck with the
--- vehicle on its bed never leaves: the driver only waits at the wheel (the server removes both
--- once nobody is near). Runs on the client that simulates the driver, with or without a local
--- job (`job`: this client's job for that truck, if any). Never throws.
local function dismiss(truck, driver, target, job)
  if stopping or not exists(truck) or not exists(driver) or dismissing[driver] then return end
  if not owns(driver) or truthy(IsEntityDead(driver)) then return end
  -- only the tow's own NPCs (the server sets these bags)
  if Entity(truck).state.nzTowTruck ~= true or Entity(driver).state.nzTowDriver ~= true then return end
  if job then
    if job.dismissed or job.sentAway then return end
    job.dismissed = true
  end
  dismissing[driver] = true
  CreateThread(function()
    local success, err = pcall(function()
      local seated = truthy(IsPedInVehicle(driver, truck, false))
      if not seated then ClearPedTasks(driver) end
      if job and job.animDict then
        RemoveAnimDict(job.animDict)
        job.animDict = nil
      end
      if exists(truck) then
        SetVehicleIndicatorLights(truck, 0, false)
        SetVehicleIndicatorLights(truck, 1, false)
      end
      if not seated then
        TaskEnterVehicle(driver, truck, DISMISS_ENTER_MS, -1, 1.0, 1, 0)
        local untilAt = GetGameTimer() + DISMISS_ENTER_MS + 1000
        while GetGameTimer() < untilAt and not stopping do
          Wait(250)
          if not exists(truck) or not exists(driver) or not owns(driver) or truthy(IsEntityDead(driver)) then return end
          if truthy(IsPedInVehicle(driver, truck, false)) then break end
        end
        if stopping then return end
        if not truthy(IsPedInVehicle(driver, truck, false)) then
          TaskWarpPedIntoVehicle(driver, truck, -1)
          Wait(300)
        end
      end
      if not stopping and wanderOff(truck, driver, target) then
        if job then job.sentAway = true end
      elseif exists(driver) and owns(driver) then
        SetPedKeepTask(driver, true)
      end
    end)
    if not success then warnOnce('dismiss', tostring(err)) end
    dismissing[driver] = nil
  end)
end

--- dismiss() for a local job (its own truck, driver and vehicle).
local function dismissJob(job)
  if not job.truck or not job.driver then return end
  dismiss(job.truck, job.driver, job.target, job)
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

-- { id, netId, model, timeout, truck?, driver?, officer? }: run the tow (truck + driver given:
-- adopt them, the server created them for this client or the job was handed over).
RegisterNetEvent('nz:client:tow:start', function(data)
  if stopping or type(data) ~= 'table' then return end
  local id, netId = toInt(data.id, 1), toInt(data.netId, 1)
  if not id or not netId then return end
  local previous = jobs[id]
  local adoptTruck = toInt(data.truck, 1)
  if previous then
    cancel(previous)
    -- a new truck replaces this client's one (the server normally dismisses it first)
    if previous.truckNet and previous.truckNet ~= adoptTruck then dismissJob(previous) end
  end
  local job = {
    id = id,
    netId = netId,
    model = toSigned(data.model),
    adoptTruck = adoptTruck,
    adoptDriver = toInt(data.driver, 1),
    officer = data.officer == true,
    lastReport = GetGameTimer(),
  }
  jobs[id] = job
  CreateThread(function() run(job) end)
end)

-- { id, netId, truck, seconds }: this client owns the impounded vehicle: pull it onto the bed.
RegisterNetEvent('nz:client:tow:attach', function(data)
  if stopping or type(data) ~= 'table' then return end
  local id = toInt(data.id, 1)
  if not id or attaching[id] then return end
  local token = { cancelled = false }
  attaching[id] = token
  CreateThread(function()
    local success, attached = pcall(function()
      local target, truck = entityOf(data.netId), entityOf(data.truck)
      if not target or not truck or Entity(target).state.nzTowing ~= true then return false end
      -- the vehicle came off a leaving truck that this client drives (it migrated here): the
      -- truck waits while it is pulled back on, then drives on
      local driver = GetPedInVehicleSeat(truck, -1)
      local hold = exists(driver) and owns(driver) and Entity(driver).state.nzTowDriver == true
        and not truthy(IsEntityAttachedToEntity(target, truck))
      if hold then TaskVehicleTempAction(driver, truck, 27, math.floor(loadSeconds(data.seconds) * 1000) + 2000) end
      local attached = pullOntoBed(target, truck, data.seconds, function() return token.cancelled or stopping end)
      if hold and attached and not token.cancelled and not stopping then
        local speed, style = driveSettings()
        if owns(driver) and truthy(IsPedInVehicle(driver, truck, false)) then
          TaskVehicleDriveWander(driver, truck, speed, style)
          SetPedKeepTask(driver, true)
        end
      end
      return attached
    end)
    if not success then warnOnce('attach', tostring(attached)) end
    if attaching[id] == token then attaching[id] = nil end
    if token.cancelled or stopping then return end
    report({ id = id }, 'attached', { ok = success and attached == true })
  end)
end)

-- { id, dismiss?, truck?, driver?, netId? }: the server ended the job or gave it to another
-- player. `dismiss`: it gave up on that truck (net ids given): the client that simulates its
-- driver sends it off (see dismiss).
RegisterNetEvent('nz:client:tow:stop', function(data)
  local id = type(data) == 'table' and toInt(data.id, 1) or nil
  if not id then return end
  local job = jobs[id]
  if data.dismiss == true then
    local truckNet, driverNet = toInt(data.truck, 1), toInt(data.driver, 1)
    -- only the job of that truck ends here (a new job for the same tow may already run); one
    -- ended a moment ago (plain `stop` first) still knows its animation
    if job and (job.truckNet or job.adoptTruck) ~= truckNet then job = nil end
    if not job and ended[id] and (ended[id].truckNet or ended[id].adoptTruck) == truckNet then job = ended[id] end
    if job then cancel(job) end
    local truck, driver = entityOf(truckNet), entityOf(driverNet)
    if truck and driver then
      if job and job.truck == truck and job.driver == driver then
        dismissJob(job)
      else
        dismiss(truck, driver, entityOf(data.netId), nil)
      end
    end
  elseif job then
    cancel(job)
  end
  local token = attaching[id]
  if token then
    token.cancelled = true
    attaching[id] = nil
  end
end)

-- { netId, ... }: tow entities this client simulates fade out (the server deletes them a moment
-- later). Only entities carrying a tow state bag.
RegisterNetEvent('nz:client:tow:fade', function(netIds)
  if type(netIds) ~= 'table' then return end
  for i = 1, math.min(#netIds, MAX_FADE) do
    local entity = entityOf(netIds[i])
    if entity and owns(entity) then
      local state = Entity(entity).state
      if state.nzTowing == true or state.nzTowTruck == true or state.nzTowDriver == true then
        pcall(NetworkFadeOutEntity, entity, false, true)
      end
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  stopping = true
  -- the server deletes the vehicles, trucks and drivers (server-side: its own entities)
  for _, job in pairs(jobs) do removeBlip(job) end
  for _, token in pairs(attaching) do token.cancelled = true end
end)
