--[[
  nayzeee-garages — job & spawner vehicles (NZ.JobsClient).
  Spawner flow behind the garage app's 'garage:spawner' callback, livery / extras /
  max-mods application and the vehicle setup app ('setup') shown after a job spawn.
  While the setup app is open a scripted orbit camera circles the frozen vehicle; the
  interface drives it with 'setup:camera' (mouse drag / A D W S / scroll deltas, held keys,
  presets). The camera is purely cosmetic: nothing it does reaches the server.
]]

local Jobs = NZ.JobsClient

local setup = nil        -- { vehicle, mode = 'livery'|'mod'|nil } while the setup app is open
local orbit = nil        -- orbit camera state while the setup app is open (see startOrbit)
local spawning = false
local PERFORMANCE_MODS = { 11, 12, 13, 15, 16 } -- engine, brakes, transmission, suspension, armour
local MOD_IDS = { [11] = 'engine', [12] = 'brakes', [13] = 'transmission', [15] = 'suspension', [16] = 'armour' }

-- Orbit camera tuning (degrees, metres, seconds). Values marked * want an in-game look.
local ORBIT = {
  fov = 50.0,             -- * vertical field of view
  pitchMin = 2.0,         -- * just above the centre: a lower line meets the ground far out at max zoom
  pitchMax = 60.0,
  yawDefault = 145.0,     -- 0 = behind the vehicle, 180 = in front; 145 = front three-quarter
  pitchDefault = 10.0,
  yawRate = 100.0,        -- held A / D, degrees per second
  pitchRate = 60.0,       -- held W / S
  zoomRate = 1.1,         -- held zoom key: distance * e^(rate * s)
  zoomStep = 1.12,        -- one wheel step: distance * 1.12 (out) or / 1.12 (in)
  smooth = 9.0,           -- * exponential follow rate of yaw / pitch / distance (1/s)
  clearOut = 4.0,         -- follow rate when a blocked camera moves back out
  margin = 0.3,           -- stay this far in front of a wall / ground hit
  minClear = 0.6,         -- never closer to the centre than this, even against a wall
  lookDrop = 0.14,        -- * aim this far (x distance) below the centre until the menu reports its top
  frameMin = 0.4,         -- menu top edge (fraction of the screen height) accepted from the interface
  frameMax = 0.9,
  frameBias = 0.9,        -- * 1 = the car's centre exactly in the middle of the space above the menu
  groundClear = 0.35,     -- * keep the camera this far above the ground right under it
  playerLeave = 8.0,      -- close the menu when the player is out of the vehicle and this far away
  playerCheck = 500,      -- ms between those checks
  ease = 650,             -- ms blend from / back to the gameplay camera
  holdTimeout = 1000,     -- ms: held keys are dropped when the interface stops re-sending them
  probeFlags = 1 + 2 + 16, -- * world + vehicles + objects (the setup vehicle itself is ignored)
  groundFlags = 1 + 16,   -- ground probe under the camera: world + objects
  maxDeltaYaw = 180.0,    -- per 'setup:camera' message
  maxDeltaPitch = 90.0,
  maxDeltaZoom = 6.0,
}
-- Presets: yaw / pitch, distance as a factor of the opening distance.
local ORBIT_VIEWS = {
  reset = { yaw = ORBIT.yawDefault, pitch = ORBIT.pitchDefault, zoom = 1.0 },
  front = { yaw = 180.0, pitch = 6.0, zoom = 1.0 },
  rear = { yaw = 0.0, pitch = 8.0, zoom = 1.0 },
  side = { yaw = -90.0, pitch = 4.0, zoom = 0.95 },   -- driver side
  top = { yaw = ORBIT.yawDefault, pitch = 58.0, zoom = 1.15 },
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function validVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle)
end

--- Ask for network control so mod natives apply to a server-created entity.
local function ensureControl(vehicle, timeout)
  if not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle) then return true end
  NetworkRequestControlOfEntity(vehicle)
  local limit = GetGameTimer() + (timeout or 1000)
  while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < limit do
    Wait(25)
    NetworkRequestControlOfEntity(vehicle)
  end
  return NetworkHasControlOfEntity(vehicle)
end

local function textLabel(key)
  if type(key) ~= 'string' or key == '' then return nil end
  local text = GetLabelText(key)
  if type(text) ~= 'string' or text == '' or text == 'NULL' then return nil end
  return text
end

local function vehicleLabel(vehicle)
  if NZ.Veh and NZ.Veh.label then
    local ok, label = pcall(NZ.Veh.label, GetEntityModel(vehicle))
    if ok and type(label) == 'string' and label ~= '' then return label end
  end
  return L('Vehicle')
end

--- Livery list of a vehicle: list, mode ('livery' | 'mod' | nil), current index.
local function readLiveries(vehicle)
  local list = {}
  local count = GetVehicleLiveryCount(vehicle)
  if count and count > 0 then
    for i = 0, count - 1 do
      list[#list + 1] = { index = i, label = textLabel(GetLiveryName(vehicle, i)) or L('Livery {n}', { n = i + 1 }) }
    end
    return list, 'livery', GetVehicleLivery(vehicle)
  end
  SetVehicleModKit(vehicle, 0)
  local mods = GetNumVehicleMods(vehicle, 48)
  if mods and mods > 0 then
    list[1] = { index = -1, label = L('Default') }
    for i = 0, mods - 1 do
      list[#list + 1] = { index = i, label = textLabel(GetModTextLabel(vehicle, 48, i)) or L('Livery {n}', { n = i + 1 }) }
    end
    return list, 'mod', GetVehicleMod(vehicle, 48)
  end
  return list, nil, -1
end

local function readExtras(vehicle)
  local list = {}
  for id = 0, 20 do
    if DoesExtraExist(vehicle, id) then
      local on = IsVehicleExtraTurnedOn(vehicle, id)
      list[#list + 1] = { id = id, enabled = on == true or on == 1 }
    end
  end
  return list
end

--- Performance mods as fitted: { id, level (0 = stock), max } for the mods the model offers.
local function readMods(vehicle)
  SetVehicleModKit(vehicle, 0)
  local list = {}
  for i = 1, #PERFORMANCE_MODS do
    local modType = PERFORMANCE_MODS[i]
    local count = math.floor(tonumber(GetNumVehicleMods(vehicle, modType)) or 0)
    if count > 0 then
      local current = math.floor(tonumber(GetVehicleMod(vehicle, modType)) or -1)
      list[#list + 1] = { id = MOD_IDS[modType], level = math.max(0, math.min(count, current + 1)), max = count }
    end
  end
  local turbo = IsToggleModOn(vehicle, 18)
  list[#list + 1] = { id = 'turbo', level = (turbo == true or turbo == 1) and 1 or 0, max = 1 }
  return list
end

---------------------------------------------------------------------------------------
-- Orbit camera: pure math (exposed as Jobs.orbitMath for tools/smoke/setup_camera.lua)
---------------------------------------------------------------------------------------

local Orbit = { config = ORBIT, views = ORBIT_VIEWS }

local function finite(n)
  return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function clampNum(n, lo, hi)
  if not finite(n) then return lo end
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function sign(v)
  v = tonumber(v)
  if not finite(v) or v == 0 then return 0 end
  return v > 0 and 1 or -1
end

--- Angle in (-180, 180].
function Orbit.wrap(deg)
  deg = deg % 360.0
  if deg > 180.0 then deg = deg - 360.0 end
  return deg
end

--- Frame-rate independent follow of `current` toward `target`.
function Orbit.follow(current, target, rate, dt)
  if dt <= 0 then return current end
  return current + (target - current) * (1.0 - math.exp(-rate * dt))
end

--- Same for an angle, the short way round.
function Orbit.followAngle(current, target, rate, dt)
  if dt <= 0 then return current end
  return Orbit.wrap(current + Orbit.wrap(target - current) * (1.0 - math.exp(-rate * dt)))
end

--- Distance limits from the model's bounding box (GetModelDimensions min / max).
--- { radius, min, max, default }: never inside the bounding sphere, wider for big vehicles.
function Orbit.limits(minDim, maxDim)
  local radius = 2.6
  if type(minDim) ~= 'nil' and type(maxDim) ~= 'nil' then
    local dx = (tonumber(maxDim.x) or 0) - (tonumber(minDim.x) or 0)
    local dy = (tonumber(maxDim.y) or 0) - (tonumber(minDim.y) or 0)
    local dz = (tonumber(maxDim.z) or 0) - (tonumber(minDim.z) or 0)
    local r = 0.5 * math.sqrt(dx * dx + dy * dy + dz * dz)
    if finite(r) and r > 0.3 then radius = math.min(r, 30.0) end
  end
  local lo = radius + 0.75
  local hi = radius * 3.0 + 4.0
  return { radius = radius, min = lo, max = hi, default = clampNum(radius * 2.1 + 1.2, lo, hi) }
end

--- Camera position around `center` for a vehicle heading `heading` (yaw 0 = behind it,
--- 90 = its right side, 180 = in front; pitch > 0 = above the centre).
function Orbit.position(center, heading, yaw, pitch, dist)
  local h, p = math.rad(heading + yaw), math.rad(pitch)
  local flat = dist * math.cos(p)
  return { x = center.x + flat * math.sin(h), y = center.y - flat * math.cos(h), z = center.z + dist * math.sin(p) }
end

--- Cam rotation (order 2: x = pitch, z = heading) looking from `from` at `to`.
function Orbit.lookRotation(from, to)
  local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
  local flat = math.sqrt(dx * dx + dy * dy)
  return { x = math.deg(math.atan(dz, flat)), y = 0.0, z = math.deg(math.atan(-dx, dy)) }
end

--- Usable distance when a probe toward the camera hit something `hitDist` from the centre.
function Orbit.clearance(wanted, hitDist)
  if not finite(hitDist) then return wanted end
  return math.max(ORBIT.minClear, math.min(wanted, hitDist - ORBIT.margin))
end

--- Aim drop (x distance) that puts the vehicle's centre in the middle of the screen space
--- above the menu, whose top edge is at `frame` (fraction of the screen height from the top).
--- The centre projects at tan(angle) / tan(fov / 2) above the screen middle and the free
--- space's middle is (1 - frame) above it, so drop = tan(fov / 2) * (1 - frame).
function Orbit.lookDropFor(frame)
  frame = clampNum(tonumber(frame), ORBIT.frameMin, ORBIT.frameMax)
  return math.tan(math.rad(ORBIT.fov / 2.0)) * (1.0 - frame) * ORBIT.frameBias
end

--- Point the cam looks at: `drop` x the distance below the centre, measured across the line
--- of sight (a steep view needs a longer vertical drop for the same offset on screen).
function Orbit.lookTarget(center, dist, pitch, drop)
  local c = math.max(0.5, math.cos(math.rad(tonumber(pitch) or 0.0)))
  return { x = center.x, y = center.y, z = center.z - dist * drop / c }
end

--- Camera height kept `ORBIT.groundClear` above a ground hit at `groundZ` (nil = no ground).
function Orbit.aboveGround(z, groundZ)
  if not finite(groundZ) then return z end
  return math.max(z, groundZ + ORBIT.groundClear)
end

--- Fresh state for the given limits, at the opening view.
function Orbit.new(limits)
  return {
    limits = limits,
    lookDrop = ORBIT.lookDrop,
    yaw = ORBIT.yawDefault, tYaw = ORBIT.yawDefault,
    pitch = ORBIT.pitchDefault, tPitch = ORBIT.pitchDefault,
    dist = limits.default, tDist = limits.default,
    clear = nil, hold = nil, holdAt = 0,
  }
end

--- Apply one 'setup:camera' message to the camera targets. Every value is clamped, unknown
--- fields are ignored. Returns true when something changed.
function Orbit.input(o, data, now)
  if type(o) ~= 'table' or type(data) ~= 'table' then return false end
  local lim, changed = o.limits, false
  local view = type(data.view) == 'string' and ORBIT_VIEWS[data.view] or nil
  if view then
    o.tYaw = Orbit.wrap(view.yaw)
    o.tPitch = clampNum(view.pitch, ORBIT.pitchMin, ORBIT.pitchMax)
    o.tDist = clampNum(lim.default * view.zoom, lim.min, lim.max)
    changed = true
  end
  local yaw = tonumber(data.yaw)
  if finite(yaw) and yaw ~= 0 then
    o.tYaw = Orbit.wrap(o.tYaw + clampNum(yaw, -ORBIT.maxDeltaYaw, ORBIT.maxDeltaYaw))
    changed = true
  end
  local pitch = tonumber(data.pitch)
  if finite(pitch) and pitch ~= 0 then
    o.tPitch = clampNum(o.tPitch + clampNum(pitch, -ORBIT.maxDeltaPitch, ORBIT.maxDeltaPitch), ORBIT.pitchMin, ORBIT.pitchMax)
    changed = true
  end
  local zoom = tonumber(data.zoom)
  if finite(zoom) and zoom ~= 0 then
    zoom = clampNum(zoom, -ORBIT.maxDeltaZoom, ORBIT.maxDeltaZoom)
    o.tDist = clampNum(o.tDist * ORBIT.zoomStep ^ zoom, lim.min, lim.max)
    changed = true
  end
  local frame = tonumber(data.frame)
  if finite(frame) then
    o.lookDrop = Orbit.lookDropFor(frame)
    changed = true
  end
  if type(data.hold) == 'table' then
    local hold = { yaw = sign(data.hold.yaw), pitch = sign(data.hold.pitch), zoom = sign(data.hold.zoom) }
    if hold.yaw == 0 and hold.pitch == 0 and hold.zoom == 0 then hold = nil end
    o.hold, o.holdAt = hold, tonumber(now) or 0
    changed = true
  end
  return changed
end

--- Advance by `dt` seconds at game time `now` (ms): held keys move the targets (dropped when
--- the interface stopped re-sending them), then yaw / pitch / distance follow their targets.
function Orbit.step(o, dt, now)
  local lim = o.limits
  local hold = o.hold
  if hold and (tonumber(now) or 0) - (o.holdAt or 0) > ORBIT.holdTimeout then
    hold = nil
    o.hold = nil
  end
  if hold then
    o.tYaw = Orbit.wrap(o.tYaw + hold.yaw * ORBIT.yawRate * dt)
    o.tPitch = clampNum(o.tPitch + hold.pitch * ORBIT.pitchRate * dt, ORBIT.pitchMin, ORBIT.pitchMax)
    if hold.zoom ~= 0 then
      o.tDist = clampNum(o.tDist * math.exp(hold.zoom * ORBIT.zoomRate * dt), lim.min, lim.max)
    end
  end
  o.yaw = Orbit.followAngle(o.yaw, o.tYaw, ORBIT.smooth, dt)
  o.pitch = Orbit.follow(o.pitch, o.tPitch, ORBIT.smooth, dt)
  o.dist = Orbit.follow(o.dist, o.tDist, ORBIT.smooth, dt)
end

--- Settle the collision distance (snap in at once, ease back out); returns the distance to use.
function Orbit.settle(o, clear, dt)
  if not o.clear or clear < o.clear then
    o.clear = clear
  else
    o.clear = Orbit.follow(o.clear, clear, ORBIT.clearOut, dt)
  end
  return math.min(o.dist, o.clear)
end

Jobs.orbitMath = Orbit

---------------------------------------------------------------------------------------
-- Orbit camera: natives
---------------------------------------------------------------------------------------

local function orbitCenter(o)
  local c = o.offset
  local p = GetOffsetFromEntityInWorldCoords(o.vehicle, c.x, c.y, c.z)
  if not p then return nil end
  return { x = tonumber(p.x) or 0.0, y = tonumber(p.y) or 0.0, z = tonumber(p.z) or 0.0 }
end

--- Distance from `from` to the first wall / ground / object / other vehicle toward `to`
--- (the setup vehicle and its occupants are ignored); nil when the line is clear.
local function probeHit(vehicle, from, to)
  local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z,
    ORBIT.probeFlags, vehicle, 7)
  if not handle then return nil end
  local _, hit, hitAt = GetShapeTestResult(handle)
  if not (hit == true or hit == 1) or not hitAt then return nil end
  local dx, dy, dz = hitAt.x - from.x, hitAt.y - from.y, hitAt.z - from.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Height of the ground (world / objects) within `ORBIT.groundClear` under `pos`, or nil.
--- A short straight-down probe: it never reaches a floor above or a roof below the camera.
local function groundUnder(vehicle, pos)
  local handle = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z + 0.05, pos.x, pos.y,
    pos.z - ORBIT.groundClear, ORBIT.groundFlags, vehicle, 7)
  if not handle then return nil end
  local _, hit, hitAt = GetShapeTestResult(handle)
  if not (hit == true or hit == 1) or not hitAt then return nil end
  return tonumber(hitAt.z)
end

--- Place the scripted cam for the current state.
local function applyOrbit(o, dt)
  local center = orbitCenter(o)
  if not center then return end
  local heading = tonumber(GetEntityHeading(o.vehicle)) or 0.0
  local reach = Orbit.position(center, heading, o.yaw, o.pitch, o.dist + ORBIT.margin)
  local dist = Orbit.settle(o, Orbit.clearance(o.dist, probeHit(o.vehicle, center, reach)), dt)
  local pos = Orbit.position(center, heading, o.yaw, o.pitch, dist)
  -- Uphill or on a kerb the line of sight can end just above the ground: lift the camera.
  pos.z = Orbit.aboveGround(pos.z, groundUnder(o.vehicle, pos))
  local rot = Orbit.lookRotation(pos, Orbit.lookTarget(center, dist, o.pitch, o.lookDrop or ORBIT.lookDrop))
  SetCamCoord(o.cam, pos.x, pos.y, pos.z)
  SetCamRot(o.cam, rot.x, 0.0, rot.z, 2)
end

--- Stop the orbit camera: blend back to the gameplay camera (behind the vehicle) unless
--- `instant`. Leaves another module's camera path alone.
local function stopOrbit(instant)
  local o = orbit
  orbit = nil
  if not o or not o.cam or not DoesCamExist(o.cam) then return end
  local cam = o.cam
  local busy = NZ.Camera.isPlaying() == true
  if not busy then
    RenderScriptCams(false, not instant, instant and 0 or ORBIT.ease, true, true)
    SetGameplayCamRelativeHeading(0.0)
    SetGameplayCamRelativePitch(0.0, 1.0)
  end
  if instant or busy then
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    return
  end
  CreateThread(function()
    Wait(ORBIT.ease + 50)
    if DoesCamExist(cam) then
      SetCamActive(cam, false)
      DestroyCam(cam, false)
    end
  end)
end

local function finishSetup()
  local current = setup
  setup = nil
  stopOrbit(false)
  if current and validVehicle(current.vehicle) then
    FreezeEntityPosition(current.vehicle, false)
  end
end

--- Vehicle of the open setup app, closing the app when it no longer exists.
local function setupVehicle()
  if not setup then return nil end
  if validVehicle(setup.vehicle) then return setup.vehicle end
  finishSetup()
  NZ.NUI.close('setup')
  return nil
end

--- The player left the frozen vehicle and is not near it any more (teleported by an admin or
--- another resource): the menu and its camera must not stay behind.
local function playerLeftVehicle(vehicle)
  local ped = cache.ped
  if GetVehiclePedIsIn(ped, false) == vehicle then return false end
  local a, b = GetEntityCoords(ped), GetEntityCoords(vehicle)
  if not a or not b then return true end
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz > ORBIT.playerLeave * ORBIT.playerLeave
end

local function orbitLoop(o)
  local last = GetGameTimer()
  local checkAt = last + ORBIT.playerCheck
  while orbit == o do
    if not validVehicle(o.vehicle) or not DoesCamExist(o.cam) then
      if setup and setup.vehicle == o.vehicle then setupVehicle() end
      if orbit == o then stopOrbit(true) end
      break
    end
    local now = GetGameTimer()
    if now >= checkAt then
      checkAt = now + ORBIT.playerCheck
      if playerLeftVehicle(o.vehicle) then
        if setup and setup.vehicle == o.vehicle then
          finishSetup()
          NZ.NUI.close('setup')
        end
        if orbit == o then stopOrbit(false) end
        break
      end
    end
    local dt = math.max(0.0, math.min(0.1, (now - last) / 1000.0))
    last = now
    Orbit.step(o, dt, now)
    applyOrbit(o, dt)
    HideHudAndRadarThisFrame()
    Wait(0)
  end
end

--- Start the orbit camera around `vehicle` (eases in from the gameplay camera).
--- Returns false when it cannot run (another camera path is playing, no cam).
local function startOrbit(vehicle)
  stopOrbit(true)
  if NZ.Camera.isPlaying() == true then return false end
  local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
  local o = Orbit.new(Orbit.limits(minDim, maxDim))
  o.vehicle = vehicle
  o.offset = { x = 0.0, y = 0.0, z = 0.0 }
  if minDim and maxDim then
    o.offset = {
      x = ((tonumber(minDim.x) or 0) + (tonumber(maxDim.x) or 0)) / 2.0,
      y = ((tonumber(minDim.y) or 0) + (tonumber(maxDim.y) or 0)) / 2.0,
      z = ((tonumber(minDim.z) or 0) + (tonumber(maxDim.z) or 0)) / 2.0,
    }
  end
  local center = orbitCenter(o)
  if not center then return false end
  local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', center.x, center.y, center.z + 2.0, 0.0, 0.0, 0.0,
    ORBIT.fov, false, 2)
  if not cam or cam == -1 then return false end
  o.cam = cam
  applyOrbit(o, 0.0)
  SetCamActive(cam, true)
  RenderScriptCams(true, true, ORBIT.ease, true, true)
  orbit = o
  CreateThread(function() orbitLoop(o) end)
  return true
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Apply a spawner vehicle's livery, extras and max performance mods.
---@param vehicle integer
---@param info table|nil { livery = -1|n, extras = { ['1'] = true }, maxMods = boolean }
function Jobs.applyMods(vehicle, info)
  if not validVehicle(vehicle) or type(info) ~= 'table' then return end
  ensureControl(vehicle)

  local livery = tonumber(info.livery)
  if livery and livery >= 0 then
    livery = math.floor(livery)
    local count = GetVehicleLiveryCount(vehicle)
    if count and count > 0 then
      if livery < count then SetVehicleLivery(vehicle, livery) end
    else
      SetVehicleModKit(vehicle, 0)
      if livery < GetNumVehicleMods(vehicle, 48) then SetVehicleMod(vehicle, 48, livery, false) end
    end
  end

  if type(info.extras) == 'table' then
    for key, value in pairs(info.extras) do
      local id, enabled = tonumber(key), value
      if type(value) == 'table' then id, enabled = tonumber(value.id), value.enabled end
      if id and id >= 0 and id <= 20 and DoesExtraExist(vehicle, id) then
        SetVehicleExtra(vehicle, math.floor(id), not enabled)
      end
    end
  end

  if info.maxMods then
    SetVehicleModKit(vehicle, 0)
    for i = 1, #PERFORMANCE_MODS do
      local modType = PERFORMANCE_MODS[i]
      local count = GetNumVehicleMods(vehicle, modType)
      if count and count > 0 then SetVehicleMod(vehicle, modType, count - 1, false) end
    end
    ToggleVehicleMod(vehicle, 18, true)
  end
end

local function infoText(value, max)
  if type(value) ~= 'string' then return nil end
  value = NZ.Utils.trim(value)
  if value == '' then return nil end
  return value:sub(1, max)
end

--- Open the vehicle setup app (liveries / extras) with the player in the frozen vehicle and
--- the orbit camera around it. Returns false when the vehicle has nothing to configure.
---@param vehicle integer
---@param info table|nil { label?, model?, plateTemplate? ('' = random), garage?, maxMods? }
---@return boolean
function Jobs.openSetup(vehicle, info)
  if not validVehicle(vehicle) then return false end
  info = type(info) == 'table' and info or {}
  if setup then finishSetup() end

  local liveries, mode, current = readLiveries(vehicle)
  local extras = readExtras(vehicle)
  if #liveries <= 1 and #extras == 0 then return false end

  local ped = cache.ped
  if GetVehiclePedIsIn(ped, false) ~= vehicle then
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
  end
  ensureControl(vehicle)
  FreezeEntityPosition(vehicle, true)
  setup = { vehicle = vehicle, mode = mode }

  local label = infoText(info.label, 60) or vehicleLabel(vehicle)
  local plate = infoText(GetVehicleNumberPlateText(vehicle), 8)
  local camera = startOrbit(vehicle) == true
  NZ.NUI.open('setup', {
    label = label,
    liveries = liveries,
    livery = tonumber(current) or -1,
    extras = extras,
    model = infoText(info.model, 32),
    plate = plate,
    plateTemplate = type(info.plateTemplate) == 'string' and NZ.Utils.trim(info.plateTemplate):sub(1, 8) or nil,
    garage = infoText(info.garage, 60),
    liveryMode = mode,
    maxMods = info.maxMods == true,
    mods = readMods(vehicle),
    camera = camera,
  })
  return true
end

local function findSpawnerEntry(list, index)
  if type(list) ~= 'table' then return nil end
  for _, entry in pairs(list) do
    if type(entry) == 'table' and tonumber(entry.index) == index then return entry end
  end
  return list[index]
end

local function spawnAndSetup(data, point, entry, location)
  local src = type(data.vehicle) == 'table' and data.vehicle or data
  local info = (type(data.info) == 'table' and data.info) or (type(data.spawner) == 'table' and data.spawner) or data
  local extra = {
    hash = tonumber(src.hash) or tonumber(entry.hash),
    model = src.model or entry.model,
    plate = src.plate or data.plate,
  }
  if src.fuel == nil then extra.fuel = 100 end

  local vehicle = NZ.Garage.spawnFromServer(data, point, extra)
  if not vehicle then return end
  Jobs.applyMods(vehicle, info)

  local setupMenu
  if info.setupMenu ~= nil then
    setupMenu = info.setupMenu == true
  else
    setupMenu = type(location) == 'table' and location.kind == 'job' and location.setupMenu ~= false
  end
  if setupMenu then
    local label = type(info.label) == 'string' and info.label ~= '' and info.label or entry.label
    Jobs.openSetup(vehicle, {
      label = label,
      model = type(src.model) == 'string' and src.model or entry.model,
      plateTemplate = type(entry.plate) == 'string' and entry.plate or nil,
      garage = type(location) == 'table' and location.name or nil,
      maxMods = info.maxMods == true,
    })
  end
end

--- Spawn spawner vehicle `index` of the open garage (job / public spawner).
---@param index number SpawnerVehicleView.index
---@return table result
function Jobs.spawn(index)
  index = tonumber(index)
  local ctx = NZ.Garage.current()
  if not index or not ctx or not ctx.location then return NZ.Utils.fail(L('Vehicle not found')) end
  if spawning then return NZ.Utils.fail(L('Please wait')) end
  if NZ.Points.incapacitated() then return NZ.Utils.fail(L('You cannot do that right now')) end
  local entry = findSpawnerEntry(ctx.data and ctx.data.spawner, index)
  if not entry then return NZ.Utils.fail(L('Vehicle not found')) end
  local hash = tonumber(entry.hash) or (type(entry.model) == 'string' and joaat(entry.model)) or nil
  if not hash then return NZ.Utils.fail(L('Vehicle not found')) end

  local spawnIndex, point = NZ.Garage.findSpawn(ctx.location)
  if not spawnIndex then return NZ.Utils.fail(L('All parking spots are occupied')) end

  spawning = true
  local result = NZ.NUI.await('nz:garage:spawner', {
    index = index,
    spawnIndex = spawnIndex,
    entityType = NZ.Veh.entityTypeOf(hash),
  })
  if not result.ok or type(result.data) ~= 'table' then
    spawning = false
    if result.ok then return NZ.Utils.fail(L('Something went wrong')) end
    return result
  end

  NZ.NUI.close('garage')
  local location = ctx.location
  CreateThread(function()
    local ok, err = pcall(spawnAndSetup, result.data, point, entry, location)
    if not ok then
      lib.print.error(('[nayzeee-garages] spawner vehicle failed: %s'):format(err))
      NZ.NUI.notify('error', L('The vehicle could not be spawned'))
    end
    spawning = false
  end)
  return NZ.Utils.ok(nil)
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('setup:livery', function(data)
  local vehicle = setupVehicle()
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  local index = tonumber(data.index)
  if not index then return NZ.Utils.fail(L('Something went wrong')) end
  index = math.floor(index)
  local mode = setup.mode
  if mode ~= 'livery' and mode ~= 'mod' then return NZ.Utils.fail(L('This vehicle has no liveries')) end
  ensureControl(vehicle, 500)
  -- The set natives return nothing: read the value back. A livery that is out of range or not
  -- streamed (or a vehicle we could not get control of) keeps the old value.
  local function applied()
    if mode == 'livery' then return GetVehicleLivery(vehicle) == index end
    return index < 0 or GetVehicleMod(vehicle, 48) == index
  end
  if mode == 'livery' then
    if index < 0 then return NZ.Utils.fail(L('This livery is not available')) end
    SetVehicleLivery(vehicle, index)
  else
    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, 48, index, false)
  end
  if not applied() then
    Wait(0) -- one frame for the entity to take it
    if not validVehicle(vehicle) then return NZ.Utils.fail(L('Vehicle not found')) end
    if not applied() then return NZ.Utils.fail(L('This livery is not available')) end
  end
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('setup:extra', function(data)
  local vehicle = setupVehicle()
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  local id = tonumber(data.id)
  if not id or id < 0 or id > 20 or not DoesExtraExist(vehicle, math.floor(id)) then
    return NZ.Utils.fail(L('Something went wrong'))
  end
  ensureControl(vehicle, 500)
  SetVehicleExtra(vehicle, math.floor(id), not data.enabled)
  -- Some extras switch each other off: send the real state back.
  NZ.NUI.send('update', { app = 'setup', data = { extras = readExtras(vehicle) } })
  return NZ.Utils.ok(nil)
end)

-- Orbit camera input (cosmetic, client only): drag / key / wheel deltas, held keys, presets.
NZ.NUI.register('setup:camera', function(data)
  if not setupVehicle() then return NZ.Utils.fail(L('Vehicle not found')) end
  if orbit then Orbit.input(orbit, data, GetGameTimer()) end
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('setup:drive', function()
  finishSetup()
  NZ.NUI.close('setup')
  return NZ.Utils.ok(nil)
end)

-- Closing the setup app (Escape / close button) behaves like "Drive".
NZ.NUI.onClose('setup', function()
  finishSetup()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  stopOrbit(true)
  if setup and validVehicle(setup.vehicle) then
    FreezeEntityPosition(setup.vehicle, false)
  end
end)
