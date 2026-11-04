--[[
  nayzeee-garages — client/towtruck.lua (NZ.Tow, client)

  Impound flatbed tow truck (docs/CARLOCK.md §11), client side. The server (server/towtruck.lua)
  stays the authority: it locks the impounded vehicle, picks one player client (the "runner")
  to play the scene, creates the truck + driver itself, follows every step through the
  `nz:tow:progress` callback, hands the job to another player when needed and removes the
  vehicle, the truck and the driver at the end or on any failure. Nothing here decides
  anything valuable, and this client never creates an entity.

  - Runner (`nz:client:tow:start`): checks the vehicle fits on the bed (class, type, size from
    GetModelDimensions), picks a road node Config.Tow.spawnDistance away (out of sight and
    away from players when possible) and proposes it (`node`; the next best one when the
    server answers 'retry': another tow or a player is there); the server creates the flatbed
    + driver there and hands them to the client that simulates them (normally this one). The
    runner adopts them, drives to a parking spot in line with the vehicle, beyond it so the
    truck arrives rear first (long range, then a slow final approach; re-paths when stuck,
    skips ahead unseen as a last resort; loads only with the vehicle behind the bed: a truck
    that stops beside it carries on to the spot, one that stops the wrong way round drives past
    the vehicle to the spot on its other side, or is turned while nobody watches), the driver
    steps out, walks to the bed controls and works them while the vehicle is pulled onto the
    bed, gets back in and wanders off. A job handed over from another player (truck / driver
    net ids in the event) adopts the NPCs the same way.
  - Attacher (`nz:client:tow:attach`): the client that owns the impounded vehicle pulls it onto
    the bed (attachments are synced by the attached entity's owner).
  - `nz:client:tow:fade`: entities this client simulates fade out before the server deletes them.
  - Every client: players cannot enter or drive a vehicle being towed (state bag `nzTowing`) or
    the tow truck (`nzTowTruck`).
  - `nz:client:tow:stop` ends the local part of a job; resource stop removes the blips (the
    server removes the entities).
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
local STUCK_MS = 10000           -- no progress for this long: stuck
local PROGRESS_STEP = 3.0        -- metres closer that count as progress
local MAX_REPATH = 3             -- the last attempt skips ahead unseen
local RECOVERED_DIST = 30.0      -- metres of progress after a re-path that count as unstuck
local HEADING_TOLERANCE = 35.0   -- degrees between the parked truck and its spot
local MAX_TURNS = 3              -- wrong-way stops corrected before giving up
local NEAR_SPEED = 5.0           -- m/s on the final approach
local AVOID_STYLE = 786469       -- goes around traffic and obstacles
local SPOT_GAP = 1.5             -- metres between the vehicle and the truck's rear
local MOVED_RANGE = 5.0          -- the vehicle moved this far: new parking spot
local MOVED_LIMIT = 80.0         -- this far from where it was impounded: give up
local PLAYER_CLEARANCE = 45.0    -- spawn nodes this close to a player are avoided
local PLAYER_MIN = 8.0           -- ... and never this close (the server refuses them)
local NODE_CLEARANCE = 6.0       -- no vehicle this close to a spawn node
local SPOT_CLEARANCE = 3.5       -- no other vehicle this close to the parking spot
local RESERVE_MS = 15000         -- a picked spawn node is not used by another job meanwhile
local EXIT_TIMEOUT_MS = 6000
local WALK_TIMEOUT_MS = 9000
local ENTER_TIMEOUT_MS = 12000
local ATTACH_EXTRA_MS = 12000    -- waiting for another client's attachment: loadSeconds + this
local REMOTE_MARGIN_MS = 1000    -- another client pulls the vehicle on: its pull ends this much later
local DONE_GRACE_MS = 20000
local GUARD_MS = 150
local RAMP_SHARE = 0.35          -- share of the loading time spent lining up behind the truck
local SIDE_SHARE = 0.15          -- ... of it backing out along the truck's side first (stood beside it)
local NODE_TRIES = 4             -- spawn nodes proposed (the server refuses a taken one: 'retry')
local LOAD_MAX_SECONDS = 20      -- Config.Tow.loadSeconds is clamped to 1..this (both sides)
local MAX_FADE = 8               -- entities per fade event

local jobs = {}                  -- [id] = runner job
local attaching = {}             -- [id] = { cancelled } while this client pulls a vehicle on
local guarded = {}               -- [bagName] = misses: towed vehicles / trucks players may not use
local reservedNodes = {}         -- { { pos, untilAt } }
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

--- End the local part of a job (server stop, new start for the same id, resource stop). The
--- truck and driver are the server's: removed there, or adopted by the next runner.
local function cancel(job)
  job.cancelled = true
  removeBlip(job)
  if jobs[job.id] == job then jobs[job.id] = nil end
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

--- Something failed on this client: the server falls back to removing the vehicle.
local function giveUp(job, reason)
  if active(job) then report(job, 'failed', { reason = reason }) end
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

--- Best node: free, out of sight of this client, away from players, mid-range. The scoring
--- never yields (the vehicle pool is read once), so two jobs never reserve the same node.
local function pickNode(center, minD, maxD, hiddenOnly)
  local nodes = roadNodes(center, minD, maxD)
  local players = playerPositions()
  local vehicles = vehiclePositions()
  local best, bestScore = nil, math.huge
  for _, c in ipairs(nodes) do
    local near = nearestPlayer(players, c.pos)
    if near >= PLAYER_MIN and spotFree(c.pos, NODE_CLEARANCE, vehicles) and not isReserved(c.pos) then
      local visible = truthy(IsSphereVisible(c.pos.x, c.pos.y, c.pos.z + 1.5, 4.0))
      if not (hiddenOnly and visible) then
        local score = math.abs(c.dist - (minD + maxD) / 2)
        if visible then score = score + 1000.0 end
        if near < PLAYER_CLEARANCE then score = score + 500.0 + (PLAYER_CLEARANCE - near) end
        if score < bestScore then best, bestScore = c, score end
      end
    end
  end
  if best then reservedNodes[#reservedNodes + 1] = { pos = best.pos, untilAt = GetGameTimer() + RESERVE_MS } end
  return best
end

local function spawnNode(job)
  local range = type(config().spawnDistance) == 'table' and config().spawnDistance or {}
  local minD = number(range.min, 80.0, 20.0, 400.0)
  local maxD = math.max(minD + 10.0, number(range.max, 150.0, 30.0, 450.0))
  local center = GetEntityCoords(job.target)
  -- the server accepts nodes up to spawnDistance.max + 40 m (+ a little slack) from the vehicle
  return pickNode(center, minD, maxD, false) or pickNode(center, math.max(30.0, minD * 0.5), maxD + 40.0, false)
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

--- Where the truck parks, and the other spot. A spot counts as reachable when the truck gets
--- there driving along the spot's heading: it passes the vehicle and stops beyond it, rear
--- towards it. Coming from the other side it would stop facing the vehicle.
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
--- simulate the driver: the tasks are given here. Returns false + reason on failure; false
--- without a reason when another client simulates them (the server hands the job over).
local function adoptNpcs(job)
  local untilAt = GetGameTimer() + ADOPT_WAIT_MS
  local truck, driver
  while true do
    truck, driver = entityOf(job.adoptTruck), entityOf(job.adoptDriver)
    if truck and driver and owns(truck) and owns(driver) then break end
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

local function driveSettings()
  local cfg = config()
  return number(cfg.speed, 14.0, 3.0, 40.0), math.floor(number(cfg.drivingStyle, 786603, 0, 2147483647))
end

local function halt(job)
  TaskVehicleTempAction(job.driver, job.truck, 27, 3000)
  local untilAt = GetGameTimer() + 3000
  while GetGameTimer() < untilAt and not truthy(IsVehicleStopped(job.truck)) do
    if not sleep(job, 200) then return end
  end
end

--- Move the truck onto `spot` while nobody watches; false when it is on screen or the spot is
--- taken.
local function placeUnseen(job, spot)
  if truthy(IsEntityOnScreen(job.truck)) then return false end
  if truthy(IsSphereVisible(spot.pos.x, spot.pos.y, spot.pos.z + 1.0, 5.0)) and spot.visibleOk ~= true then
    return false
  end
  if not spotFree(spot.pos, SPOT_CLEARANCE, vehiclePositions(job.truck, job.target)) then return false end
  SetEntityCoords(job.truck, spot.pos.x, spot.pos.y, spot.pos.z + 0.5, false, false, false, false)
  SetEntityHeading(job.truck, spot.heading + 0.0)
  SetVehicleOnGroundProperly(job.truck)
  return true
end

--- Last resort when stuck: move the truck while nobody watches (to the parking spot when it
--- is hidden and free, else to a hidden free road node closer to the vehicle).
local function skipAhead(job, spot)
  if truthy(IsEntityOnScreen(job.truck)) then return false end
  if placeUnseen(job, spot) then return true end
  local node = pickNode(GetEntityCoords(job.target), 25.0, 60.0, true)
  if not node then return false end
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

--- Drive to the parking spot. Returns true when parked in line with the vehicle, close enough
--- to load, else false + reason ('targetGone' | 'moved' | 'npc' | 'stuck' | 'heading'); false
--- without a reason when the job ended.
local function approach(job)
  local speed, style = driveSettings()
  local spot, other = parkingSpot(job)
  local phase = 'far'
  local repaths, repathDist, turns = 0, math.huge, 0
  local anchor = GetEntityCoords(job.target)
  local best, lastProgress = math.huge, GetGameTimer()
  local nearSince = 0

  local function drive(avoid)
    if not owns(job.driver) then return end -- the server hands the job to the new owner
    if phase == 'far' then
      TaskVehicleDriveToCoordLongrange(job.driver, job.truck, spot.pos.x, spot.pos.y, spot.pos.z, speed,
        avoid and AVOID_STYLE or style, 10.0)
    else
      TaskVehicleDriveToCoord(job.driver, job.truck, spot.pos.x, spot.pos.y, spot.pos.z, NEAR_SPEED, 0,
        GetEntityModel(job.truck), AVOID_STYLE, 1.0, 40.0)
    end
    SetPedKeepTask(job.driver, true)
  end

  drive(false)
  while true do
    if not sleep(job, POLL_MS) then return false end
    local problem = npcProblem(job)
    if problem then return false, problem end
    if not exists(job.target) then return false, 'targetGone' end
    local targetPos = GetEntityCoords(job.target)
    if Utils.dist(targetPos, job.origin) > MOVED_LIMIT or foreignAttach(job) then return false, 'moved' end

    local now = GetGameTimer()
    if Utils.dist(targetPos, anchor) > MOVED_RANGE then
      -- pushed or bumped: new spot from where it stands now
      anchor = targetPos
      spot, other = parkingSpot(job)
      best, lastProgress = math.huge, now
      drive(repaths > 1)
    end

    local d = Utils.dist(GetEntityCoords(job.truck), spot.pos)
    if d < best - PROGRESS_STEP then best, lastProgress = d, now end
    -- driving well again after a re-path (a red light, a jam): back to the normal style
    if repaths > 0 and repaths < MAX_REPATH and d < repathDist - RECOVERED_DIST then
      repaths, repathDist = 0, math.huge
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
        if inLine and behindTruck(job) then return true end
        turns = turns + 1
        if turns > MAX_TURNS then return false, 'heading' end
        if inLine and Utils.dist(GetEntityCoords(job.truck), spot.pos) > PARKED_RANGE then
          -- the right way round but beside or short of the vehicle (passing it, waiting in
          -- traffic): carry on to the spot
          Utils.debug(('tow %d: stopped beside the vehicle, carries on to the spot (%d)'):format(job.id, turns))
          nearSince, lastProgress, best = now, now, math.huge
          drive(true)
        else
          local turned, nextSpot = realign(job, spot, other)
          if turned then return active(job) end
          if not nextSpot then return false, 'heading' end
          Utils.debug(('tow %d: wrong way round, parks on the other side (%d)'):format(job.id, turns))
          spot, other = nextSpot, spot
          nearSince, lastProgress, best = now, now, math.huge
          drive(true) -- around the vehicle
        end
      end
    end

    if now - lastProgress > STUCK_MS then
      repaths = repaths + 1
      if repaths > MAX_REPATH then return false, 'stuck' end
      if repaths == MAX_REPATH then
        if not skipAhead(job, spot) then return false, 'stuck' end
        spot, other = parkingSpot(job)
        phase = 'far'
      end
      Utils.debug(('tow %d: stuck, re-path %d'):format(job.id, repaths))
      best, lastProgress, nearSince = math.huge, now, now
      repathDist = Utils.dist(GetEntityCoords(job.truck), spot.pos)
      drive(repaths >= 2)
    end
  end
end

---------------------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------------------

--- Bed height above the bone, measured with a ray onto the truck (nil when it misses).
local function measureSurface(truck, boneLocal, bedY)
  local top = offset(truck, 0.0, boneLocal.y + bedY, boneLocal.z + 4.0)
  local bottom = offset(truck, 0.0, boneLocal.y + bedY, boneLocal.z - 1.5)
  local success, handle = pcall(StartExpensiveSynchronousShapeTestLosProbe, top.x, top.y, top.z,
    bottom.x, bottom.y, bottom.z, 2, 0, 7)
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
  local surface = measureSurface(truck, boneLocal, bedY) or number(bed.surface, 0.55, -1.0, 3.0)

  local size = dims(GetEntityModel(target))
  local truckSize = dims(GetEntityModel(truck))
  local relative = headingDiff(GetEntityHeading(target), GetEntityHeading(truck))
  local flipped = math.abs(relative) > 90.0
  local dir = flipped and -1.0 or 1.0
  local centreY = (size.min.y + size.max.y) / 2
  local final = { x = 0.0, y = bedY - dir * centreY, z = surface - size.min.z, h = flipped and 180.0 or 0.0 }
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
      { pose = final, share = 1.0 - RAMP_SHARE, climb = true },
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
      end
      return pose
    end
    start = start + leg.share
    from = leg.pose
  end
  return plan.final
end

local function attachAt(target, truck, bone, pose, final)
  AttachEntityToEntity(target, truck, bone, pose.x + 0.0, pose.y + 0.0, pose.z + 0.0, 0.0, 0.0, pose.h + 0.0,
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
  if exists(job.driver) then ClearPedTasks(job.driver) end
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

--- After leaving: tell the server once the truck is out of this player's sight and range (it
--- removes everything when every player is far, or after despawnSeconds).
local function watchLeaving(job)
  local cfg = config()
  local range = number(cfg.despawnDistance, 150.0, 30.0, 1000.0)
  local untilAt = GetGameTimer() + number(cfg.despawnSeconds, 60, 10, 600) * 1000 + DONE_GRACE_MS
  local told = false
  while active(job) and GetGameTimer() < untilAt do
    Wait(1000)
    if not exists(job.truck) then break end
    if not told and Utils.dist(GetEntityCoords(PlayerPedId()), GetEntityCoords(job.truck)) > range
      and not truthy(IsEntityOnScreen(job.truck)) then
      told = true
      report(job, 'done')
    end
  end
  if jobs[job.id] == job then jobs[job.id] = nil end
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
  -- a handed-over job may find the truck parked and the driver already out at the bed
  local parked = not job.fresh and not truthy(IsPedInVehicle(job.driver, job.truck, false))
    and (truthy(IsEntityAttachedToEntity(job.target, job.truck))
      or (rearGap(job) <= GOOD_GAP + 4.0 and behindTruck(job)))
  if not parked and not boardTruck(job) then return giveUp(job, npcProblem(job) or 'board') end

  -- 3. drive to the vehicle
  if not parked then
    local problem
    parked, problem = approach(job)
    if not active(job) then return end
    if problem == 'targetGone' then return leaveEmpty(job) end
    if not parked then return giveUp(job, problem or 'stuck') end
  end
  if not step(job, 'arrived') then return end

  -- 4. the driver works the controls while the vehicle is pulled onto the bed
  if not toControls(job) then
    if active(job) then giveUp(job, npcProblem(job) or 'controls') end
    return
  end
  if not exists(job.target) then return leaveEmpty(job) end
  local accepted, result = step(job, 'load')
  if not accepted then return stopWorking(job) end
  local attacher = type(result.data) == 'table' and result.data.attacher or 'remote'
  local seconds = loadSeconds(cfg.loadSeconds)
  local loaded = load(job, attacher, seconds)
  stopWorking(job)
  if not active(job) then return end
  if not loaded then
    if not exists(job.target) then return leaveEmpty(job) end
    return giveUp(job, 'attach')
  end
  if not step(job, 'loaded') then return end

  -- 5. back in and away
  if not boardTruck(job) then
    if active(job) then giveUp(job, npcProblem(job) or 'board') end
    return
  end
  if not step(job, 'leaving') then return end
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
-- Events
---------------------------------------------------------------------------------------

-- { id, netId, model, timeout, truck?, driver?, officer? }: run the tow (truck + driver given:
-- adopt them, the server created them for this client or the job was handed over).
RegisterNetEvent('nz:client:tow:start', function(data)
  if stopping or type(data) ~= 'table' then return end
  local id, netId = toInt(data.id, 1), toInt(data.netId, 1)
  if not id or not netId then return end
  local previous = jobs[id]
  if previous then cancel(previous) end
  local job = {
    id = id,
    netId = netId,
    model = toSigned(data.model),
    adoptTruck = toInt(data.truck, 1),
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
      return pullOntoBed(target, truck, data.seconds, function() return token.cancelled or stopping end)
    end)
    if not success then warnOnce('attach', tostring(attached)) end
    if attaching[id] == token then attaching[id] = nil end
    if token.cancelled or stopping then return end
    report({ id = id }, 'attached', { ok = success and attached == true })
  end)
end)

-- { id }: the server ended the job or gave it to another player.
RegisterNetEvent('nz:client:tow:stop', function(data)
  local id = type(data) == 'table' and toInt(data.id, 1) or nil
  if not id then return end
  local job = jobs[id]
  if job then cancel(job) end
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
