--[[
  nayzeee-garages — server/towtruck.lua (NZ.Tow)

  Impound flatbed tow truck (docs/CARLOCK.md §11). The impound is already committed in the
  database when NZ.Tow.start runs (server/impound.lua); everything here is the visual of an
  NPC collecting the vehicle, with the server as the authority:

  - NZ.Tow.start refuses boats / aircraft / trailers, vehicles somebody sits in, too many tows
    and vehicles nobody is near enough to run the scene for: the caller deletes them at once;
  - the vehicle is locked (SetVehicleDoorsLocked 2, the car lock's `nzLocked` and the
    replicated state bag `nzTowing = true`: every client refuses entering / driving it) and
    kept by the server (orphan mode 2: it never disappears with the client that simulates it);
  - one player client, the "runner" (the impounding officer when in range, else the nearest
    player in the vehicle's routing bucket), checks the vehicle fits on the bed and picks a
    road node out of sight with a route to the vehicle (`node`); the SERVER creates the
    flatbed + driver there (CreateVehicleServerSetter / CreatePed: server-script entities, so
    the tow works with any entity lockdown mode and no client ever tells the server which
    entities are "the truck"). The runner takes control of them (and later of the vehicle)
    and keeps it (no migration while it runs the scene), plays the scene and reports each
    step through the `nz:tow:progress` callback (node -> spawned -> arrived -> load -> loaded
    -> leaving -> done, tick keep-alives, failed);
  - the vehicle is attached to the bed by the client that owns it (attachments are synced by
    the attached entity's owner; normally the runner): `nz:client:tow:attach`. The server
    sees the attachment itself before the truck may leave, and while it leaves: a vehicle that
    comes off the bed is pulled back on (the runner holds the truck meanwhile);
  - once a truck has been sent (`spawned`), the vehicle never disappears in front of players
    before it is on the bed: a failed attempt (stuck, wrong way round, the pull failed ...)
    sends a new truck (Config.Tow.attempts), the old one is retired and dismissed (the client
    that simulates its driver gets him back in and drives it off empty, never with the vehicle
    on its bed); when nothing more can be tried, the vehicle stays where it is, locked, and the
    officer is told the tow truck could not collect it. Retired entities are deleted once every
    player of the bucket is farther than Config.Tow.despawnDistance from them, at the latest
    after Config.Tow.cleanupSeconds (faded out on the client that simulates them first).
    Failures before any truck was sent (a vehicle that does not fit, no road node, the NPCs
    could not be created) delete it at once (faded), as without a tow;
  - a 1 s watchdog hands the job to another nearby player when the runner drops, leaves,
    changes bucket, loses the NPCs to another client or stops reporting (the new runner adopts
    the NPCs when it already simulates them, else a new truck comes), and ends the job on
    Config.Tow.timeout;
  - after loading, the truck drives away and everything is removed once every player is
    farther than Config.Tow.despawnDistance (the leaving stage lasts despawnSeconds at most,
    then the entities are retired as above);
  - every entity is identified by server-side data only: handle + model, and the server's
    `entityRemoved` event marks it gone (a handle is recycled only after that event), so a
    recycled handle never matches and nothing else is ever deleted. The state bags
    (`nzTowing`, `nzTowTruck`, `nzTowDriver`) only drive the client guard: the owner of an
    entity can write them, so the server puts them back when anybody clears them;
  - a player in the impounded vehicle or in the tow truck ends the tow: that entity is
    deleted under them at once (no fade);
  - resource stop removes every vehicle, truck and driver still in a job or retired at once.
]]

local Tow = NZ.Tow
local Utils = NZ.Utils

local TICK_MS = 1000
local RUNNER_RANGE = 150.0          -- metres: players this close to the vehicle can run the tow
local KEEP_RANGE = 350.0            -- runner farther than this from the vehicle: hand the job over
local SILENT_MS = 25000             -- no report from the runner for this long: hand the job over
local OWNER_GRACE_MS = 4000         -- driver owned by another client (migration) this long: hand over
local REPORT_WAIT_MS = 3000         -- ownership of adopted NPCs may take this long to settle
local OWNER_WAIT_MS = 5000          -- a client must take over the new truck + driver within this time
local SEAT_WAIT_MS = 3000           -- the driver must be in the driver seat within this time
local SAME_OWNER_WAIT_MS = 3000     -- truck and driver end up on the same client within this time
local MAX_HANDOVERS = 2
local HANDOVER_MIN_LEFT_MS = 30000  -- less time than this left: fall back instead of handing over
local NODE_SLACK = 10.0             -- metres of tolerance on the node distance (client vs server view)
local NODE_MAX_DZ = 45.0            -- metres between the node height and the vehicle's
local NODE_PLAYER_MIN = 5.0         -- no player this close to the node (the truck would land on them)
local NODE_SEPARATION = 12.0        -- metres between the nodes / trucks of two tows
local NODE_BUSY_MS = 20000          -- an accepted node stays taken this long (the truck is created there)
local MAX_NODE_RETRIES = 3          -- refused nodes (another tow, a player) before falling back
local LOAD_RANGE = 30.0             -- metres between truck and vehicle when loading starts / is retried
local TARGET_GONE_GRACE_MS = 15000  -- vehicle deleted by someone else: time for the truck to leave
local ATTACH_SEEN_MS = 3000         -- the server must see the vehicle on the bed this soon after `loaded`
local DETACHED_LIMIT_MS = 20000     -- leaving: the vehicle off the bed this long -> give up (retired)
local REATTACH_GAP_MS = 6000        -- leaving: between two requests to pull it back on
local REATTACH_SECONDS = 2          -- ... and how long that pull takes
local RETRY_MIN_LEFT_MS = 40000     -- less time than this left: no new truck
-- `failed` reasons of a vehicle that cannot go on a flatbed at all (no new truck for those)
local UNSUITABLE = {
  class = true, type = true, size = true, attached = true, trailer = true, occupied = true,
  model = true, target = true, moved = true,
}
local ATTACH_ATTEMPTS = 3
local LOAD_MAX_SECONDS = 20         -- Config.Tow.loadSeconds is clamped to 1..this (both sides)
local LOAD_EXTRA_MS = 25000         -- loading may take loadSeconds + this before falling back
local LOADED_STALL_MS = 30000       -- driver not back in the truck after this: clean up from here
local FADE_MS = 1200                -- entities fade out on their owner this long before deletion
local LAST_SEAT = 14
local REPORT_GAP_MS = 150           -- per job, between two reports of its runner
-- server GetVehicleType values that fit on a flatbed (class / size are checked by the runner)
local TOWABLE = {
  automobile = true, bike = true, quadbike = true,
  amphibious_automobile = true, amphibious_quadbike = true,
}
local STAGES = { start = 1, spawned = 2, arrived = 3, load = 4, loaded = 5, leaving = 6 }
local TARGET_BAG, TRUCK_BAG, DRIVER_BAG = 'nzTowing', 'nzTowTruck', 'nzTowDriver'
-- the three entities of a job: job[role] is the handle, job[MODEL_FIELD[role]] its model
local ROLE_BAG = { target = TARGET_BAG, truck = TRUCK_BAG, driver = DRIVER_BAG }
local MODEL_FIELD = { target = 'model', truck = 'truckModel', driver = 'driverModel' }
local ROLE_TYPE = { target = 2, truck = 2, driver = 1 }

local jobs = {}                     -- [id] = job
local owned = {}                    -- [entity] = job (vehicle, truck and driver of every job)
local fading = {}                   -- [entity] = item: fading out, deleted FADE_MS later
local retired = {}                  -- [entity] = item: kept until no player is near (see retire)
local leftovers = {}                -- { group }: retired entities of one job, deleted together
local nextId = 0
local watchdogRunning = false
local stopping = false
local hurry = false                 -- Tow.stopAll: finish() deletes at once
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

--- Finite number, or nil.
local function finite(value)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

local function toInt(value, min)
  local n = finite(value)
  if not n then return nil end
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

local function loadSeconds()
  return number(config().loadSeconds, 6, 1, LOAD_MAX_SECONDS)
end

local function despawnRange()
  return number(config().despawnDistance, 150.0, 30.0, 1000.0)
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
  if type(entity) ~= 'number' then return nil end
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
  local success, result = pcall(IsPedAPlayer, entity)
  if success and result ~= nil then return result == true or result == 1 end
  -- older server builds: compare with every player's ped
  warnOnce('isPedAPlayer', 'IsPedAPlayer is not available on this server build')
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

--- The entity carries our state bag `key` (only to check a bag the server just set stuck: the
--- entity's owner can write bags, so they never prove which entity is which).
local function hasBag(entity, key)
  local success, value = pcall(function() return Entity(entity).state[key] end)
  return success and value == true
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

--- Still the job's `role` entity ('target' | 'truck' | 'driver'): it exists with the right type
--- and model, and the server never saw it removed (`entityRemoved` sets job.gone[role]; a
--- handle is only recycled after that event). Server-side data only: no state bag.
local function alive(job, role)
  local entity = job[role]
  return entity ~= nil and not job.gone[role] and exists(entity, ROLE_TYPE[role])
    and modelOf(entity) == job[MODEL_FIELD[role]]
end

local function targetAlive(job) return alive(job, 'target') end
local function truckAlive(job) return alive(job, 'truck') end
local function driverAlive(job) return alive(job, 'driver') end

local function targetCoords(job)
  if targetAlive(job) then return GetEntityCoords(job.target) end
  return job.origin
end

--- A dispose() item for the job's `role` entity. `instant`: deleted at once (a player sits in it).
local function itemOf(job, role, instant)
  return {
    entity = job[role], model = job[MODEL_FIELD[role]], bag = ROLE_BAG[role],
    job = job, role = role, instant = instant == true,
  }
end

--- Still the entity that was handed to dispose(): `entityRemoved` sets item.gone.
local function sameEntity(item)
  return not item.gone and exists(item.entity) and modelOf(item.entity) == item.model
end

--- The item's entity was just deleted here: its job stops counting it at once (the
--- `entityRemoved` event comes a moment later). Only while the job still has that entity.
local function markGone(item)
  local job = item.job
  if job and item.role and job[item.role] == item.entity then job.gone[item.role] = true end
end

--- Delete job entities. `fade`: a client that simulates one fades it out first and it is
--- deleted FADE_MS later (nothing pops out of existence in front of players); entities nobody
--- simulates, `instant` items (a player sits in them) and everything while the resource
--- stops go at once. An entity already fading out keeps its own timer (disposing it again
--- would only postpone its deletion), unless it must go at once.
---@param items table[] see itemOf
local function dispose(items, fade)
  local byOwner, later = {}, {}
  for _, item in ipairs(items) do
    if retired[item.entity] then retired[item.entity] = nil end
    local pending = fading[item.entity]
    if not pending or item.instant then
      if pending then fading[item.entity] = nil end
      local owner = (fade and not item.instant and not stopping) and ownerOf(item.entity) or nil
      local netId = owner and connected(owner) and netIdOf(item.entity) or nil
      if netId then
        byOwner[owner] = byOwner[owner] or {}
        table.insert(byOwner[owner], netId)
        later[#later + 1] = item
        fading[item.entity] = item
      else
        DeleteEntity(item.entity)
        markGone(item)
      end
    end
  end
  if #later == 0 then return end
  for owner, netIds in pairs(byOwner) do TriggerClientEvent('nz:client:tow:fade', owner, netIds) end
  SetTimeout(FADE_MS, function()
    for _, item in ipairs(later) do
      if fading[item.entity] == item then
        fading[item.entity] = nil
        if sameEntity(item) then
          DeleteEntity(item.entity)
          markGone(item)
        end
      end
    end
  end)
end

--- No player of `bucket` within `range` of `pos`.
local function nobodyNear(pos, bucket, range)
  for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    local ped = src and playerPed(src) or nil
    if ped and playerBucket(src) == bucket and Utils.dist(GetEntityCoords(ped), pos) <= range then return false end
  end
  return true
end

--- Check one group of retired entities (one job's): what a player sits in goes at once, what
--- no player is near goes now (nobody sees it), the rest with a fade after
--- Config.Tow.cleanupSeconds. A vehicle on a truck's bed goes together with that truck (the
--- vehicle first: it never drops off a truck deleted before it). True once the group is empty.
local function sweepGroup(group, now)
  local live, gone, near = {}, {}, {}
  local range = despawnRange()
  local late = now - group.since >= number(config().cleanupSeconds, 300, 30, 3600) * 1000
  for _, item in ipairs(group.items) do
    if retired[item.entity] == item and sameEntity(item) then
      if ROLE_TYPE[item.role] == 2 and playerInside(item.entity) then
        item.instant = true
        gone[#gone + 1] = item
      else
        live[#live + 1] = item
        near[item.entity] = not stopping and not nobodyNear(GetEntityCoords(item.entity), group.bucket, range)
      end
    elseif retired[item.entity] == item then
      retired[item.entity] = nil
    end
  end
  -- the vehicle on the bed and the driver at the wheel share the truck's fate (deleting one of
  -- them alone would drop the vehicle on the road or stop the truck at the edge of the range)
  local links = {}
  for _, item in ipairs(live) do
    local success, parent
    if ROLE_TYPE[item.role] == 1 then
      success, parent = pcall(GetVehiclePedIsIn, item.entity, false)
    else
      success, parent = pcall(GetEntityAttachedTo, item.entity)
    end
    if success and parent and near[parent] ~= nil then links[#links + 1] = { item.entity, parent } end
  end
  for _ = 1, 2 do
    for _, link in ipairs(links) do
      if near[link[1]] or near[link[2]] then near[link[1]], near[link[2]] = true, true end
    end
  end
  local keep = {}
  for _, item in ipairs(live) do
    if near[item.entity] then keep[#keep + 1] = item else gone[#gone + 1] = item end
  end
  if #gone > 0 then dispose(gone, false) end
  if late and #keep > 0 then
    dispose(keep, true)
    keep = {}
  end
  group.items = keep
  return #keep == 0
end

local function sweepLeftovers(now)
  for i = #leftovers, 1, -1 do
    local success, done = pcall(sweepGroup, leftovers[i], now)
    if not success then
      lib.print.error(('[nayzeee-garages] tow cleanup: %s'):format(tostring(done)))
      dispose(leftovers[i].items, false)
      done = true
    end
    if done then table.remove(leftovers, i) end
  end
end

local ensureWatchdog -- defined with the watchdog below

--- Keep entities of a job that a player may have seen until nobody is near them (see
--- sweepGroup): a truck is never removed in front of players, the vehicle never before it is
--- on the bed. `instant` items (a player sits in them) go at once.
local function retire(items, bucket)
  local group = { items = {}, bucket = bucket, since = GetGameTimer() }
  local now = {}
  for _, item in ipairs(items) do
    if item.instant or stopping then
      now[#now + 1] = item
    elseif not retired[item.entity] and not fading[item.entity] then
      retired[item.entity] = item
      group.items[#group.items + 1] = item
    end
  end
  if #now > 0 then dispose(now, false) end
  if #group.items == 0 then return end
  if not sweepGroup(group, GetGameTimer()) then
    leftovers[#leftovers + 1] = group
    ensureWatchdog()
  end
end

local function npcItems(job)
  local items = {}
  if driverAlive(job) and not isPlayerPed(job.driver) then items[#items + 1] = itemOf(job, 'driver') end
  -- a player took the truck: deleted under them at once, never driven off during a fade
  if truckAlive(job) then items[#items + 1] = itemOf(job, 'truck', playerInside(job.truck)) end
  return items
end

local function forgetNpcs(job)
  if job.driver and owned[job.driver] == job then owned[job.driver] = nil end
  if job.truck and owned[job.truck] == job then owned[job.truck] = nil end
  job.truck, job.driver, job.truckNet, job.driverNet = nil, nil, nil, nil
  job.gone.truck, job.gone.driver = nil, nil
end

--- The job gives up on its truck + driver while players may see them (a new truck comes, the
--- job moves to another player without them, or it ends without the vehicle): the client that
--- simulates the driver gets him back in and drives the empty truck off (`stop` + `dismiss`;
--- never with the vehicle on its bed), so nothing stands at the vehicle working the controls
--- with the hazards on, in the way of the next truck. Before forgetNpcs (it needs the net ids).
---@return number|nil owner the client that was told
local function dismissNpcs(job)
  if not job.shown or stopping or hurry then return nil end
  if not truckAlive(job) or not driverAlive(job) or not job.truckNet or not job.driverNet then return nil end
  local owner = ownerOf(job.driver)
  if not owner or not connected(owner) then return nil end
  TriggerClientEvent('nz:client:tow:stop', owner, {
    id = job.id, dismiss = true, truck = job.truckNet, driver = job.driverNet, netId = job.netId,
  })
  return owner
end

--- Remove the job's truck + driver: retired (kept until nobody is near) once players may have
--- seen them, else faded out and deleted now.
local function dropNpcs(job)
  local items = npcItems(job)
  forgetNpcs(job)
  if job.shown then retire(items, job.bucket) else dispose(items, true) end
end

--- The vehicle hangs on the job's truck as the server sees it: true / false, nil = unknown
--- (GetEntityAttachedTo missing on this server build).
local function attachedTo(job)
  if not targetAlive(job) or not truckAlive(job) then return false end
  local success, parent = pcall(GetEntityAttachedTo, job.target)
  if not success or parent == nil then
    warnOnce('attachedTo', 'GetEntityAttachedTo is not available on this server build')
    return nil
  end
  return parent == job.truck
end

--- End a job ('done' = the scene played to the end, 'fallback' = something failed on the
--- way). The vehicle, truck and driver go: retired (deleted once nobody is near) when a truck
--- was sent, else (nothing was shown yet) faded out and deleted at once, as without a tow.
-- `finish` reasons after which the officer is not told the tow failed (the vehicle left the
-- impound some other way, or the tow truck itself was impounded)
local QUIET_REASONS = { released = true, truckImpounded = true }

local function finish(job, outcome, reason)
  if jobs[job.id] ~= job then return end
  jobs[job.id] = nil
  -- the truck leaves empty instead of standing at the vehicle
  local dismissed = outcome ~= 'done' and dismissNpcs(job) or nil
  local items = npcItems(job)
  if targetAlive(job) then
    -- somebody sits in it: gone at once, never driven away (already fading out: dispose()
    -- leaves its timer alone)
    table.insert(items, 1, itemOf(job, 'target', playerInside(job.target)))
  end
  if owned[job.target] == job then owned[job.target] = nil end
  forgetNpcs(job)
  if stopping or hurry then
    dispose(items, false)
  elseif job.shown then
    retire(items, job.bucket)
  else
    dispose(items, true)
  end
  if not stopping then
    if connected(job.runner) and job.runner ~= dismissed then
      TriggerClientEvent('nz:client:tow:stop', job.runner, { id = job.id })
    end
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
    attempts = job.attempt,
    retries = job.retries,     -- why earlier trucks were replaced
    stage = job.stage,
    seconds = math.floor((GetGameTimer() - job.startedAt) / 1000),
  })
  if outcome ~= 'done' then
    Utils.debug(('tow %d (%s) fell back: %s'):format(job.id, tostring(job.plate), tostring(reason)))
    -- told "Tow truck dispatched" before: say it did not work (the vehicle stays, locked, until
    -- nobody is near)
    if job.notified and not job.released and not stopping and not hurry and not QUIET_REASONS[reason]
      and connected(job.officer) then
      notify(job.officer, 'error', L('The tow truck could not collect the vehicle'))
    end
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
    officer = job.runner == job.officer, -- the runner shows a blip on its truck
  })
end

local function attachPayload(job)
  return {
    id = job.id,
    netId = job.netId,
    truck = job.truckNet,
    seconds = loadSeconds(),
  }
end

--- `src` may run the job: connected, in the vehicle's bucket, near it, not excluded.
local function canRun(job, src)
  if not connected(src) or job.excluded[src] or playerBucket(src) ~= job.bucket then return false end
  return Utils.dist(GetEntityCoords(playerPed(src)), targetCoords(job)) <= KEEP_RANGE
end

--- Give the job to `src`, which simulates the truck + driver: it adopts them.
local function reassign(job, src)
  local now = GetGameTimer()
  local old = job.runner
  job.runner = src
  job.stage = 'spawned'
  job.adoptPending = true
  job.lastSeen, job.stageAt = now, now
  job.ownerMismatchAt, job.droppedAt, job.runnerDropped = nil, nil, nil
  if old ~= src and connected(old) then TriggerClientEvent('nz:client:tow:stop', old, { id = job.id }) end
  sendStart(job, true)
end

--- The vehicle may hang on the job's truck (attached, or the server cannot tell and loading
--- has begun): no new truck can take it then.
local function onBed(job)
  local attached = attachedTo(job)
  if attached == nil then return STAGES[job.stage] ~= nil and STAGES[job.stage] >= STAGES.load end
  return attached
end

--- Reset the job to its first step: the runner picks a node for a new truck.
local function restart(job, runner)
  local now = GetGameTimer()
  job.stage = 'start'
  job.adoptPending = nil
  job.node, job.nodeAt, job.nodeTries = nil, nil, 0
  job.attacher, job.attachAttempts = nil, 0
  job.targetGoneAt = nil
  job.runner = runner
  job.lastSeen, job.stageAt = now, now
  job.ownerMismatchAt, job.droppedAt, job.runnerDropped = nil, nil, nil
  sendStart(job, false)
end

--- Give the job to another player near the vehicle (the current runner is excluded when
--- `exclude`). The new runner adopts the truck + driver when it simulates both, or when the
--- old runner is still there to let them go (it walked away or changed bucket: it gets `stop`
--- and lets the NPCs migrate; the new runner takes control of them); otherwise they are
--- retired and a new truck comes. Falls back when nobody can take it.
local function handover(job, reason, exclude)
  local now = GetGameTimer()
  local old = job.runner
  if exclude then job.excluded[old] = true end
  if connected(old) then TriggerClientEvent('nz:client:tow:stop', old, { id = job.id }) end
  -- a client still pulling the vehicle onto the old truck stops as well
  if job.attacher and job.attacher ~= old and connected(job.attacher) then
    TriggerClientEvent('nz:client:tow:stop', job.attacher, { id = job.id })
  end
  if job.handovers >= MAX_HANDOVERS or job.deadline - now < HANDOVER_MIN_LEFT_MS then
    return finish(job, 'fallback', 'runner:' .. reason)
  end
  local preferred = driverAlive(job) and ownerOf(job.driver) or nil
  local runner = pickRunner(targetCoords(job), job.bucket, preferred, job.excluded)
  if not runner then return finish(job, 'fallback', 'runner:' .. reason) end

  local npcs = truckAlive(job) and driverAlive(job)
  local simulates = npcs and ownerOf(job.truck) == runner and ownerOf(job.driver) == runner
  local released = npcs and (reason == 'far' or reason == 'bucket') and connected(old)
  local adopt = simulates or released
  -- the vehicle hangs on the old truck: only that truck can take it away
  if not adopt and npcs and onBed(job) then return finish(job, 'fallback', 'runner:' .. reason) end
  job.handovers = job.handovers + 1
  job.attacher, job.attachAttempts = nil, 0
  if adopt then
    reassign(job, runner)
  else
    dismissNpcs(job)
    dropNpcs(job)
    restart(job, runner)
  end
  Utils.debug(('tow %d handed to %d (%s, adopt=%s)'):format(job.id, runner, reason, tostring(adopt)))
end

--- A step of the scene failed on the runner (stuck, wrong way round, the pull failed ...):
--- retire this truck and send a new one (Config.Tow.attempts trucks in all), else end the job
--- (the vehicle stays, locked, until nobody is near).
local function retry(job, reason)
  if jobs[job.id] ~= job then return end
  local now = GetGameTimer()
  local attempts = math.floor(number(config().attempts, 2, 1, 5))
  if job.attempt >= attempts or not targetAlive(job) or job.deadline - now < RETRY_MIN_LEFT_MS
    or (truckAlive(job) and onBed(job)) then
    return finish(job, 'fallback', reason)
  end
  local runner = pickRunner(targetCoords(job), job.bucket, job.runner, job.excluded)
  if not runner then return finish(job, 'fallback', reason) end
  local old = job.runner
  if old ~= runner and connected(old) then TriggerClientEvent('nz:client:tow:stop', old, { id = job.id }) end
  if job.attacher and job.attacher ~= runner and connected(job.attacher) then
    TriggerClientEvent('nz:client:tow:stop', job.attacher, { id = job.id })
  end
  job.attempt = job.attempt + 1
  job.retries = job.retries or {}
  job.retries[#job.retries + 1] = reason
  -- the old truck drives off empty (its client gets `dismiss` before the new `start`)
  dismissNpcs(job)
  dropNpcs(job)
  restart(job, runner)
  Utils.debug(('tow %d: %s, new truck (attempt %d)'):format(job.id, tostring(reason), job.attempt))
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
  -- loading reports nothing while the vehicle is pulled on (bounded by loadSeconds + LOAD_EXTRA_MS)
  if job.stage ~= 'load' and now - job.lastSeen > SILENT_MS then return 'silent' end
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
  return nobodyNear(GetEntityCoords(job.truck), job.bucket, despawnRange())
end

--- Ask the client that owns the vehicle to pull it onto the truck's bed (attachments are synced
--- by the attached entity's owner). False when nobody in the job's bucket simulates it.
local function requestAttach(job, seconds)
  local owner = ownerOf(job.target)
  if not owner or not connected(owner) or playerBucket(owner) ~= job.bucket then return false end
  job.attacher = owner
  TriggerClientEvent('nz:client:tow:attach', owner, {
    id = job.id,
    netId = job.netId,
    truck = job.truckNet,
    seconds = seconds or loadSeconds(),
  })
  return true
end

--- Leaving: the truck never goes without the vehicle. Off the bed (fell off, a client cleared
--- the attachment): the runner holds the truck and the vehicle's owner pulls it back on while
--- the truck is near; after DETACHED_LIMIT_MS both are retired (deleted once nobody is near).
local function checkLeaving(job, now)
  if not truckAlive(job) then return finish(job, 'done', 'truckGone') end
  if targetAlive(job) then
    if playerInside(job.target) then return finish(job, 'fallback', 'occupied') end
    if attachedTo(job) == false then
      job.detachedAt = job.detachedAt or now
      if now - job.detachedAt >= DETACHED_LIMIT_MS then return finish(job, 'fallback', 'detached') end
      local near = Utils.dist(GetEntityCoords(job.truck), GetEntityCoords(job.target)) <= LOAD_RANGE
      if near and (job.reattachTries or 0) < ATTACH_ATTEMPTS and now - (job.reattachAt or 0) >= REATTACH_GAP_MS then
        job.reattachTries = (job.reattachTries or 0) + 1
        job.reattachAt = now
        requestAttach(job, REATTACH_SECONDS)
      end
      return -- never 'done' while the vehicle is not on the truck
    end
    job.detachedAt = nil
  end
  local despawnMs = number(config().despawnSeconds, 60, 10, 600) * 1000
  if now - job.leavingAt >= despawnMs then return finish(job, 'done', 'time') end
  if everyoneFar(job) then return finish(job, 'done', 'far') end
end

local function check(job, now)
  -- the `node` handler is creating the truck + driver (bounded wait): it settles the job itself
  if job.creating then return end
  -- a player took the tow truck (only the client guard keeps them out): end it now, the truck
  -- is deleted under them (finish -> npcItems)
  if truckAlive(job) and playerInside(job.truck) then return finish(job, 'fallback', 'truckOccupied') end
  if job.stage == 'leaving' then return checkLeaving(job, now) end

  if not targetAlive(job) then
    if job.stage == 'start' or not truckAlive(job) then return finish(job, 'fallback', 'targetGone') end
    -- deleted by something else: the runner sends its truck away ('leaving', targetGone)
    job.targetGoneAt = job.targetGoneAt or now
    if now - job.targetGoneAt >= TARGET_GONE_GRACE_MS then return finish(job, 'fallback', 'targetGone') end
  elseif bucketOf(job.target) ~= job.bucket then
    return finish(job, 'fallback', 'bucket')
  elseif playerInside(job.target) then
    -- doors are locked and clients refuse it: somebody forced their way in
    return finish(job, 'fallback', 'occupied')
  end
  if now >= job.deadline then return finish(job, 'fallback', 'timeout') end

  if job.stage ~= 'start' and (not truckAlive(job) or not driverAlive(job)) then
    return handover(job, 'truckGone', false)
  end

  local problem = runnerProblem(job, now)
  if problem then return handover(job, problem, true) end

  if job.stage == 'load' and now - job.stageAt > loadSeconds() * 1000 + LOAD_EXTRA_MS then
    return retry(job, 'attach')
  end
  if job.stage == 'loaded' and now - job.stageAt > LOADED_STALL_MS and attachedTo(job) ~= false then
    startLeaving(job)
  end
end

function ensureWatchdog()
  if watchdogRunning then return end
  watchdogRunning = true
  CreateThread(function()
    while (next(jobs) ~= nil or #leftovers > 0) and not stopping do
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
      sweepLeftovers(now)
    end
    watchdogRunning = false
  end)
end

---------------------------------------------------------------------------------------
-- Truck + driver (created here, never by a client)
---------------------------------------------------------------------------------------

--- Poll `cond` every 100 ms for up to `ms` while the job runs; true once it holds.
local function waitFor(job, cond, ms)
  local untilAt = GetGameTimer() + ms
  while jobs[job.id] == job do
    local success, result = pcall(cond)
    if success and result then return true end
    if GetGameTimer() >= untilAt then return false end
    Wait(100)
  end
  return false
end

--- Accepted distances of a road node from the vehicle (the runner picks the node with the
--- same numbers: spawnDistance, then a wider fallback ring).
local function nodeRange()
  local range = type(config().spawnDistance) == 'table' and config().spawnDistance or {}
  local minD = number(range.min, 80.0, 20.0, 400.0)
  local maxD = math.max(minD + 10.0, number(range.max, 150.0, 30.0, 450.0))
  return math.max(30.0, minD * 0.5) - NODE_SLACK, maxD + 40.0 + NODE_SLACK
end

--- Why a proposed node is refused, or nil: 'distance' (never proposed by an honest client),
--- 'player' (somebody stands there) or 'busy' (another tow's node or truck: two runners do not
--- see each other's reservations).
local function nodeProblem(job, x, y, z)
  local origin = GetEntityCoords(job.target)
  local dx, dy = x - origin.x, y - origin.y
  local d = math.sqrt(dx * dx + dy * dy)
  local minD, maxD = nodeRange()
  if d < minD or d > maxD or math.abs(z - origin.z) > NODE_MAX_DZ then return 'distance' end
  local node = vector3(x, y, z)
  for _, id in ipairs(GetPlayers()) do
    local ped = playerPed(tonumber(id))
    if ped and Utils.dist(GetEntityCoords(ped), node) < NODE_PLAYER_MIN then return 'player' end
  end
  local now = GetGameTimer()
  for _, other in pairs(jobs) do
    if other ~= job then
      if other.node and now - other.nodeAt < NODE_BUSY_MS and Utils.dist(other.node, node) < NODE_SEPARATION then
        return 'busy'
      end
      if truckAlive(other) and Utils.dist(GetEntityCoords(other.truck), node) < NODE_SEPARATION then return 'busy' end
    end
  end
  return nil
end

--- Keep a new NPC for the job (`role` 'truck' | 'driver', job[role] already set): its bucket,
--- never dropped with a client, marked with its bag.
local function keep(job, role)
  local entity = job[role]
  owned[entity] = job
  job.gone[role] = nil
  if not pcall(SetEntityRoutingBucket, entity, job.bucket) then
    warnOnce('bucket', 'SetEntityRoutingBucket is not available on this server build')
  end
  if not pcall(SetEntityOrphanMode, entity, 2) then
    warnOnce('orphan', 'SetEntityOrphanMode is not available on this server build')
  end
  setState(entity, ROLE_BAG[role], true)
end

--- The truck + driver could not be created: fall back (whatever exists is removed by finish).
local function spawnFailed(job, reason)
  if jobs[job.id] ~= job then return fail(L('This tow is no longer active'), 'gone') end
  finish(job, 'fallback', 'spawn:' .. reason)
  return fail(L('The tow truck could not be sent'))
end

--- Create the truck + driver at the node, wait for a client to simulate them and give the job
--- to that client. Returns the callback result for the runner `src`.
local function createNpcs(job, src, x, y, z, heading)
  local made, truck = pcall(CreateVehicleServerSetter, job.truckModel, 'automobile', x + 0.0, y + 0.0, z + 0.5, heading + 0.0)
  if not made then warnOnce('setter', ('CreateVehicleServerSetter failed: %s'):format(tostring(truck))) end
  truck = made and toInt(truck, 1) or nil
  if not truck or not exists(truck, 2) then return spawnFailed(job, 'truck') end
  job.truck = truck
  keep(job, 'truck')
  -- the driver appears beside the driver door (inside the truck's body physics would throw
  -- him around) and is seated once a client simulates both
  local right = math.rad(heading)
  local px, py = x - math.cos(right) * 2.5, y - math.sin(right) * 2.5
  local driver
  made, driver = pcall(CreatePed, 4, job.driverModel, px, py, z + 1.0, heading + 0.0, true, true)
  if not made then warnOnce('ped', ('CreatePed failed: %s'):format(tostring(driver))) end
  driver = made and toInt(driver, 1) or nil
  if not driver or not exists(driver, 1) then return spawnFailed(job, 'driver') end
  job.driver = driver
  keep(job, 'driver')
  if not hasBag(truck, TRUCK_BAG) or not hasBag(driver, DRIVER_BAG) then
    -- the bags did not stick: no client would keep players out of the truck
    DeleteEntity(driver)
    DeleteEntity(truck)
    forgetNpcs(job)
    return spawnFailed(job, 'state')
  end
  job.truckNet, job.driverNet = netIdOf(truck), netIdOf(driver)
  if not job.truckNet or not job.driverNet then return spawnFailed(job, 'network') end

  -- server entities have no owner until a client near them takes them over
  if not waitFor(job, function() return ownerOf(truck) ~= nil and ownerOf(driver) ~= nil end, OWNER_WAIT_MS) then
    return spawnFailed(job, 'owner')
  end
  -- RPC natives: run by the owner, hence after the wait
  if not pcall(SetPedIntoVehicle, driver, truck, -1) then warnOnce('seat', 'SetPedIntoVehicle is not available on this server build') end
  local plate = config().plate
  if type(plate) == 'string' and plate ~= '' then pcall(SetVehicleNumberPlateText, truck, plate:sub(1, 8)) end
  -- the runner seats the driver itself if this does not land in time
  waitFor(job, function() return GetPedInVehicleSeat(truck, -1) == driver end, SEAT_WAIT_MS)
  waitFor(job, function() return ownerOf(truck) == ownerOf(driver) end, SAME_OWNER_WAIT_MS)
  if jobs[job.id] ~= job then return fail(L('This tow is no longer active'), 'gone') end
  if not truckAlive(job) or not driverAlive(job) then return spawnFailed(job, 'npc') end

  -- the runner takes control of them when OneSync gave them to another client (the player
  -- nearest to the node): one client simulates the whole scene and keeps it
  if job.runner == src and canRun(job, src) then
    job.stage, job.stageAt, job.adoptPending = 'spawned', GetGameTimer(), true
    return ok({ truck = job.truckNet, driver = job.driverNet })
  end
  -- the runner left meanwhile: the client that simulates them runs the scene from here
  local owner = ownerOf(driver)
  if owner and canRun(job, owner) then
    reassign(job, owner)
    return fail(L('This tow is no longer active'), 'moved')
  end
  return spawnFailed(job, 'owner')
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
  -- already fading out at the end of a tow: it goes in a moment anyway
  if fading[entity] and sameEntity(fading[entity]) then return true, nil end
  local leftover = retired[entity]
  if leftover and sameEntity(leftover) then
    -- a vehicle left after a tow (waiting for nobody to be near): it goes then anyway; a
    -- retired tow truck is impounded like any vehicle (faded out now)
    if leftover.role ~= 'target' then dispose({ leftover }, true) end
    return true, nil
  end

  local existing = owned[entity]
  if existing then
    -- impounded again while on its way: nothing to add
    if existing.target == entity and targetAlive(existing) then return true, nil end
    -- the tow truck itself is impounded: it goes like any impounded vehicle (faded out with its
    -- driver) and that tow ends (its vehicle stays, locked, until nobody is near)
    if (existing.truck == entity and truckAlive(existing)) or (existing.driver == entity and driverAlive(existing)) then
      local npcs = npcItems(existing)
      forgetNpcs(existing)
      dispose(npcs, true)
      finish(existing, 'fallback', 'truckImpounded')
      return true, nil
    end
    owned[entity] = nil -- a deleted entity's handle, reused by another vehicle
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

  -- the bag identifies the vehicle from here on: without it nothing could be deleted safely
  setState(entity, TARGET_BAG, true)
  if not hasBag(entity, TARGET_BAG) then return false, 'state' end

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
    gone = {},          -- [role] = true once the server saw that entity removed
    handovers = 0,
    nodeTries = 0,
    stage = 'start',
    startedAt = now,
    stageAt = now,
    lastSeen = now,
    lastReport = 0,
    deadline = now + math.floor(number(cfg.timeout, 240, 30, 900) * 1000),
    attachAttempts = 0,
    attempt = 1,        -- trucks sent (Config.Tow.attempts)
    shown = false,      -- a truck reached `spawned`: from here the vehicle never vanishes near players
    truckModel = truckModel,
    driverModel = driverModel,
  }
  jobs[job.id] = job
  owned[entity] = job

  -- kept by the server whoever simulates it: OneSync would delete a client-created vehicle with
  -- its owner (or once nobody is near), taking it from under the tow truck
  if not pcall(SetEntityOrphanMode, entity, 2) then
    warnOnce('orphan', 'SetEntityOrphanMode is not available on this server build')
  end
  local locked = pcall(SetVehicleDoorsLocked, entity, 2)
  if not locked then warnOnce('lock', 'SetVehicleDoorsLocked is not available on this server build') end
  -- keep the built-in car lock's state bag in line (its clients apply `nzLocked`)
  if type(NZ.CarLock.setLocked) == 'function' then
    local success, err = pcall(NZ.CarLock.setLocked, entity, true)
    if not success then warnOnce('carlock', ('could not lock through the car lock: %s'):format(tostring(err))) end
  end
  sendStart(job, false)
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

--- Is this vehicle (or truck / driver) part of a running tow, or fading out after one?
---@param entity number
---@return boolean
function Tow.isTowing(entity)
  local item = fading[entity] or retired[entity]
  if item and sameEntity(item) then return true end
  local job = owned[entity]
  if not job then return false end
  return (job.target == entity and targetAlive(job)) or (job.truck == entity and truckAlive(job))
    or (job.driver == entity and driverAlive(job))
end

--- The towed vehicle is needed elsewhere (its owner retrieves it from the impound while the
--- truck is still on its way): delete it now; the truck leaves empty. False when the entity is
--- not a vehicle being towed (delete it yourself).
---@param entity number
---@return boolean released
function Tow.release(entity)
  local item = fading[entity]
  if item then
    fading[entity] = nil
    if sameEntity(item) then
      DeleteEntity(entity)
      markGone(item)
    end
    return true
  end
  item = retired[entity]
  if item and item.role == 'target' then
    -- left after a tow, waiting for nobody to be near: the owner takes it out of the impound
    retired[entity] = nil
    if sameEntity(item) then DeleteEntity(entity) end
    return true
  end
  local job = owned[entity]
  if not job or job.target ~= entity or not targetAlive(job) then return false end
  DeleteEntity(entity)
  -- forgotten at once: the job never takes this handle for its vehicle again
  job.gone.target = true
  owned[entity] = nil
  job.targetGoneAt = job.targetGoneAt or GetGameTimer()
  job.released = true -- its owner took it out of the impound: no failure notice for the officer
  -- no truck yet (or it is being created): nothing to drive away
  if job.stage == 'start' or not truckAlive(job) then finish(job, 'fallback', 'released') end
  return true
end

--- End every tow at once (vehicles, trucks and drivers are deleted).
function Tow.stopAll(reason)
  -- everything goes at once (no fade, no waiting for players to leave)
  hurry = true
  for _, job in ipairs(snapshot()) do
    local success, err = pcall(finish, job, 'fallback', reason or 'stopAll')
    if not success then lib.print.warn(('[nayzeee-garages] tow %d cleanup failed: %s'):format(job.id, tostring(err))) end
  end
  for i = #leftovers, 1, -1 do
    local group = table.remove(leftovers, i)
    for _, item in ipairs(group.items) do
      if retired[item.entity] == item then
        retired[item.entity] = nil
        if sameEntity(item) then DeleteEntity(item.entity) end
      end
    end
  end
  hurry = false
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

-- { x, y, z, heading } the road node the runner picked: the server creates the truck + driver
-- there -> { truck, driver } net ids to adopt; code 'moved' when another client simulates
-- them (that client runs the tow from here); code 'retry' when another tow or a player is on
-- that node (the runner proposes its next one, MAX_NODE_RETRIES times at most)
function handlers.node(job, src, payload)
  if job.stage ~= 'start' or job.creating or job.truck or job.driver then return invalid() end
  local x, y, z, heading = finite(payload.x), finite(payload.y), finite(payload.z), finite(payload.heading)
  if not x or not y or not z or not heading then return invalid() end
  if not targetAlive(job) then
    finish(job, 'fallback', 'targetGone')
    return fail(L('This tow is no longer active'), 'gone')
  end
  local problem = nodeProblem(job, x, y, z)
  if problem == 'distance' then
    -- the runner's own node search never proposes such a place
    securityLog(src, job, 'node:distance', { x = x, y = y, z = z })
    finish(job, 'fallback', 'node:distance')
    return fail(L('The tow truck could not be sent'))
  elseif problem then
    -- a player just walked onto it, or another runner picked it a moment ago
    job.nodeTries = job.nodeTries + 1
    if job.nodeTries > MAX_NODE_RETRIES then
      finish(job, 'fallback', 'node:' .. problem)
      return fail(L('The tow truck could not be sent'))
    end
    return fail(L('The tow truck could not be sent'), 'retry')
  end
  job.node, job.nodeAt = vector3(x, y, z), GetGameTimer()
  job.creating = true
  local success, result = pcall(createNpcs, job, src, x, y, z, heading % 360.0)
  job.creating = nil
  if success then return result end
  lib.print.error(('[nayzeee-garages] tow %d: %s'):format(job.id, tostring(result)))
  finish(job, 'fallback', 'error')
  return fail(L('The tow truck could not be sent'))
end

-- { truck, driver } the runner took over the truck + driver (just created, or a handed-over
-- job's): they must be this job's and simulated by this client
function handlers.spawned(job, src, payload)
  if job.stage ~= 'spawned' then return invalid() end
  local truckNet, driverNet = toInt(payload.truck, 1), toInt(payload.driver, 1)
  if truckNet ~= job.truckNet or driverNet ~= job.driverNet then
    -- only ever the net ids the server sent: anything else comes from a modified client
    securityLog(src, job, 'spawn:entity', { truck = truckNet, driver = driverNet })
    return invalid()
  end
  if not job.adoptPending then return ok(nil) end -- repeated report
  if not truckAlive(job) or not driverAlive(job) then
    return fail(L('The tow truck could not be sent'), 'npc') -- the watchdog replaces them
  end
  waitFor(job, function() return ownerOf(job.driver) == src end, REPORT_WAIT_MS)
  if jobs[job.id] ~= job or job.runner ~= src then return fail(L('This tow is no longer active'), 'gone') end
  -- migrated meanwhile: the watchdog hands the job to the client that simulates them
  if ownerOf(job.driver) ~= src then return fail(L('This tow is no longer active'), 'owner') end
  job.adoptPending = nil
  job.stageAt = GetGameTimer()
  -- players may see the truck from here: the vehicle never vanishes in front of them any more
  job.shown = true
  -- told once the truck really is on its way (a boat or an oversized vehicle never gets here)
  if not job.notified and job.officer and connected(job.officer) then
    job.notified = true
    notify(job.officer, 'info', L('Tow truck dispatched'))
  end
  return ok(nil)
end

function handlers.arrived(job)
  if job.stage ~= 'spawned' or job.adoptPending then return invalid() end
  job.stage = 'arrived'
  job.stageAt = GetGameTimer()
  return ok(nil)
end

-- The driver works the controls: who attaches the vehicle to the bed?
function handlers.load(job, src)
  if job.stage ~= 'arrived' then return invalid() end
  if not targetAlive(job) or not truckAlive(job) or not driverAlive(job) then
    retry(job, 'loadMissing')
    return fail(L('The tow truck could not load the vehicle'))
  end
  -- the server's own positions: the truck really stands at the vehicle
  if Utils.dist(GetEntityCoords(job.truck), GetEntityCoords(job.target)) > LOAD_RANGE then
    retry(job, 'loadDistance')
    return fail(L('The tow truck could not load the vehicle'))
  end
  job.stage = 'load'
  job.stageAt = GetGameTimer()
  -- normally the runner itself (it takes control of the vehicle before loading)
  local owner = ownerOf(job.target)
  if owner == src then
    job.attacher = src
    return ok({ attacher = 'self' })
  end
  if requestAttach(job) then
    job.attachAttempts = 1
    return ok({ attacher = 'remote' })
  end
  retry(job, 'attachOwner')
  return fail(L('The tow truck could not load the vehicle'))
end

-- { ok } from the client asked to attach the vehicle (may arrive just after the runner already
-- saw the vehicle on the bed and moved on)
function handlers.attached(job, src, payload)
  if STAGES[job.stage] < STAGES.load then return invalid() end
  if payload.ok == true or job.stage ~= 'load' then return ok(nil) end
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

-- The runner sees the vehicle on the bed: so must the server (replicated by the vehicle's
-- owner a moment later), else this truck never takes it.
function handlers.loaded(job)
  if job.stage ~= 'load' then return invalid() end
  if attachedTo(job) == false then
    waitFor(job, function() return job.stage ~= 'load' or attachedTo(job) ~= false end, ATTACH_SEEN_MS)
    if jobs[job.id] ~= job or job.stage ~= 'load' then return fail(L('This tow is no longer active'), 'gone') end
    if attachedTo(job) == false then
      retry(job, 'attachSync')
      return fail(L('The tow truck could not load the vehicle'), 'attach')
    end
  end
  job.stage = 'loaded'
  job.stageAt = GetGameTimer()
  return ok(nil)
end

-- { reason? } the truck drives away: loaded, or reason 'targetGone' (vehicle deleted meanwhile).
-- Never without the vehicle on the bed: code 'attach' (its owner is asked to pull it back on;
-- the runner holds the truck and asks again).
function handlers.leaving(job, src, payload)
  if job.stage == 'loaded' then
    if targetAlive(job) and attachedTo(job) == false then
      if Utils.dist(GetEntityCoords(job.truck), GetEntityCoords(job.target)) <= LOAD_RANGE
        and (job.reattachTries or 0) < ATTACH_ATTEMPTS then
        job.reattachTries = (job.reattachTries or 0) + 1
        requestAttach(job, REATTACH_SECONDS)
        return fail(L('The tow truck could not load the vehicle'), 'attach')
      end
      retry(job, 'detached')
      return fail(L('This tow is no longer active'), 'gone')
    end
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

-- The leaving truck is out of the runner's sight: end now when every player is far from it
-- (otherwise the watchdog ends it by distance or time as usual).
function handlers.done(job)
  if job.stage ~= 'leaving' then return invalid() end
  if not truckAlive(job) then
    finish(job, 'done', 'truckGone')
  elseif everyoneFar(job) and (not targetAlive(job) or attachedTo(job) ~= false) then
    finish(job, 'done', 'far')
  end
  return ok(nil)
end

-- { reason } the runner gave up: a vehicle that cannot go on a flatbed (class, size, boat,
-- moved away ...) ends the job; anything else (no road node, stuck, wrong way round, the
-- driver could not get in, the pull failed ...) sends a new truck while attempts are left.
function handlers.failed(job, src, payload)
  if job.creating then return invalid() end
  local reason = type(payload.reason) == 'string' and payload.reason:gsub('[^%w:_%-]', ''):sub(1, 32) or 'client'
  if UNSUITABLE[reason] then
    finish(job, 'fallback', 'client:' .. reason)
  else
    retry(job, 'client:' .. reason)
  end
  return ok(nil)
end

-- { id, stage, ... } -> null | { attacher = 'self'|'remote' } (load) | { truck, driver } (node)
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
-- Export (docs/CARLOCK.md §7)
---------------------------------------------------------------------------------------

-- exports['nayzeee-garages']:StartTow(netId, officerSrc?) -> boolean started, string|nil reason
-- An NPC flatbed collects the vehicle; it is deleted afterwards once no player is near (also
-- when the tow fails after the truck was sent; before that, at once). false + reason ('disabled' | 'entity' | 'type' | 'occupied' | 'busy' | 'runner' |
-- 'config' | 'state' | 'error'): nothing happened, delete the vehicle yourself if it must go.
-- Server code is trusted: no distance or job checks here (the calling script decides).
exports('StartTow', function(netId, officerSrc)
  local success, started, reason = pcall(Tow.startByNetId, netId, officerSrc)
  if not success then
    lib.print.warn(('[nayzeee-garages] export StartTow failed: %s'):format(tostring(started)))
    return false, 'error'
  end
  return started == true, reason
end)

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

-- The server removed an entity (deleted by anybody, culled, its owner left ...). Its handle can
-- only be given to a new entity after this event, so from here on nothing of a job matches it.
AddEventHandler('entityRemoved', function(entity)
  if next(jobs) == nil and next(fading) == nil and next(retired) == nil then return end
  for _, job in pairs(jobs) do
    for role in pairs(ROLE_BAG) do
      if job[role] == entity then job.gone[role] = true end
    end
  end
  if owned[entity] then owned[entity] = nil end
  local item = fading[entity]
  if item then
    item.gone = true
    fading[entity] = nil
  end
  item = retired[entity]
  if item then
    item.gone = true
    retired[entity] = nil
  end
end)

--- The job and role of a tow entity in a running job, or nil.
local function roleOf(entity)
  local job = owned[entity]
  if not job or jobs[job.id] ~= job then return nil end
  for role in pairs(ROLE_BAG) do
    if job[role] == entity and alive(job, role) then return job, role end
  end
  return nil
end

--- The bag `key` of this entity must stay true: it is a job's vehicle / truck / driver with
--- that bag, or one fading out at the end of a tow.
local function bagTracked(entity, key)
  local job, role = roleOf(entity)
  if job and ROLE_BAG[role] == key then return job end
  local item = fading[entity] or retired[entity]
  if item and item.bag == key and sameEntity(item) then return item.job or true end
  return nil
end

--- The owner of an entity can write its state bags (unless sv_stateBagStrictMode): a cleared
--- tow bag would lift every client's guard on it (also on what is retired after a tow). The server never trusts the bags, and puts
--- them back right away (logged once per job and bag).
local function onBagChange(key, bagName, value)
  if value == true or stopping or type(bagName) ~= 'string' then return end
  local success, entity = pcall(GetEntityFromStateBagName, bagName)
  if not success or type(entity) ~= 'number' or entity == 0 then return end
  local tracked = bagTracked(entity, key)
  if not tracked then return end
  if type(tracked) == 'table' then
    tracked.bagLogged = tracked.bagLogged or {}
    if not tracked.bagLogged[key] then
      tracked.bagLogged[key] = true
      log('security.tow', ownerOf(entity), { reason = 'bag:' .. key, tow = tracked.id, plate = tracked.plate })
    end
  end
  -- after this change has been applied
  SetTimeout(0, function()
    if not stopping and bagTracked(entity, key) then setState(entity, key, true) end
  end)
end

for _, key in pairs(ROLE_BAG) do
  AddStateBagChangeHandler(key, nil, function(bagName, _, value)
    local success, err = pcall(onBagChange, key, bagName, value)
    if not success then warnOnce('bagHandler', ('state bag handler failed: %s'):format(tostring(err))) end
  end)
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  stopping = true
  Tow.stopAll('resourceStop')
  -- what was fading out goes now (its timer dies with the resource)
  for entity, item in pairs(fading) do
    fading[entity] = nil
    if sameEntity(item) then DeleteEntity(entity) end
  end
  for entity, item in pairs(retired) do
    retired[entity] = nil
    if sameEntity(item) then DeleteEntity(entity) end
  end
end)
