--[[
  Headless test for the vehicle setup menu and its orbit camera (client/jobs.lua, no FiveM).

    Pure math (Jobs.orbitMath): angle wrap, orbit position (yaw 0 = behind, 90 = right side,
    180 = in front, pitch up = above), look-at rotation in GTA's heading convention, distance
    limits from the model box, clearance against a probe hit, follow smoothing, input
    validation (NaN / huge / unknown fields, presets, held keys) and the held-key timeout,
    framing above the menu (frame -> lookDrop), ground clearance under the camera.

    Flow (stubbed natives, scripted world): Jobs.openSetup -> setup app data (detail fields,
    mods, camera = true) + scripted cam eased in, placed outside the vehicle and looking at it
    -> setup:camera drag / zoom / pitch clamps / preset / hold (and hold drop after 1 s without
    a repeat) -> a wall between car and camera pulls the camera in at once and it eases back
    out when clear -> ground under the camera lifts it -> frame message aims lower ->
    setup:livery reads the livery back ('not available' when it does not take, livery and
    mod-slot modes) / setup:extra unchanged -> setup:drive blends back to the
    gameplay cam, destroys the cam after the blend, unfreezes, closes -> vehicle deleted while
    open closes the app and blends back -> a playing cutscene camera keeps the orbit
    off (camera = false) -> player teleported away closes the menu (not when just next to
    the vehicle) -> calls without an open setup fail -> resource stop.

  Usage (from the resource root):  lua5.4 tools/smoke/setup_camera.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end
local function near(a, b, eps) return type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= (eps or 1e-6) end

-- scheduler ---------------------------------------------------------------------------
local clock = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function GetGameTimer() return clock end
local function runDue()
  local list = {}
  for i = 1, #threads do list[i] = threads[i] end
  for _, t in ipairs(list) do
    if coroutine.status(t.co) == 'suspended' and t.wake <= clock then
      local okR, res = coroutine.resume(t.co)
      if not okR then failures[#failures + 1] = 'thread error: ' .. debug.traceback(t.co, tostring(res)) end
      t.wake = clock + (tonumber(res) or 0)
    end
  end
  for i = #threads, 1, -1 do
    if coroutine.status(threads[i].co) == 'dead' then table.remove(threads, i) end
  end
end
--- Advance the game clock in 16 ms frames.
local function advance(ms)
  local target = clock + ms
  runDue()
  while clock < target do
    clock = math.min(target, clock + 16)
    runDue()
  end
end

-- events ------------------------------------------------------------------------------
local events = {}
function AddEventHandler(name, fn) events[name] = events[name] or {}; table.insert(events[name], fn) end
local function fire(name, ...) for _, fn in ipairs(events[name] or {}) do fn(...) end end

-- world -------------------------------------------------------------------------------
local VEH, PED = 300, 101
local world = {
  exists = { [VEH] = true },
  pos = { x = 100.0, y = 200.0, z = 30.0 },
  heading = 90.0,
  frozen = false,
  livery = 1, liveryCount = 3,
  extras = { [1] = true, [2] = false, [4] = true },
  mods = { [11] = { count = 4, cur = 3 }, [12] = { count = 3, cur = -1 }, [15] = { count = 4, cur = 1 } },
  turbo = true,
  plate = ' JOB 042 ',
  wall = nil,  -- distance from the vehicle centre at which every probe hits
  groundZ = nil, -- ground height for the straight-down probe under the camera
  probes = 0,
  pedVehicle = VEH, -- vehicle the player sits in (0 = on foot)
  pedPos = nil,     -- player position while on foot (nil = at the vehicle)
  liveryStreamed = nil, -- set: SetVehicleLivery ignores indexes not in it (livery not streamed)
}
local DIM_MIN = { x = -1.0, y = -2.4, z = -0.6 }
local DIM_MAX = { x = 1.0, y = 2.4, z = 0.9 }

function DoesEntityExist(h) return world.exists[h] == true end
function GetEntityModel() return 12345 end
function GetModelDimensions() return DIM_MIN, DIM_MAX end
function GetEntityHeading() return world.heading end
function GetOffsetFromEntityInWorldCoords(_, x, y, z)
  local h = math.rad(world.heading)
  -- local +x = right (cos h, sin h), local +y = forward (-sin h, cos h)
  return {
    x = world.pos.x + x * math.cos(h) - y * math.sin(h),
    y = world.pos.y + x * math.sin(h) + y * math.cos(h),
    z = world.pos.z + z,
  }
end
function GetVehiclePedIsIn() return world.pedVehicle end
function GetEntityCoords(h)
  if h == PED and world.pedPos then return world.pedPos end
  return { x = world.pos.x, y = world.pos.y, z = world.pos.z }
end
function TaskWarpPedIntoVehicle() end
function NetworkGetEntityIsNetworked() return false end
function NetworkHasControlOfEntity() return true end
function NetworkRequestControlOfEntity() end
function FreezeEntityPosition(_, v) world.frozen = v end
function GetVehicleLiveryCount() return world.liveryCount end
function GetLiveryName(_, i) return 'LIV_' .. i end
function GetLabelText(key) return key == 'LIV_0' and 'Patrol' or 'NULL' end
function GetVehicleLivery() return world.livery end
function SetVehicleLivery(_, i)
  if i < 0 or i >= world.liveryCount then return end
  if world.liveryStreamed and not world.liveryStreamed[i] then return end
  world.livery = i
end
function SetVehicleModKit() end
function GetNumVehicleMods(_, t) return world.mods[t] and world.mods[t].count or 0 end
function GetVehicleMod(_, t) return world.mods[t] and world.mods[t].cur or -1 end
function GetModTextLabel() return nil end
function SetVehicleMod(_, t, i)
  -- only the livery slot is tracked (the performance mods are read, never set, in this test)
  if t == 48 and world.mods[48] and i < world.mods[48].count then world.mods[48].cur = i end
end
function ToggleVehicleMod() end
function IsToggleModOn() return world.turbo end
function DoesExtraExist(_, id) return world.extras[id] ~= nil end
function IsVehicleExtraTurnedOn(_, id) return world.extras[id] == true end
function SetVehicleExtra(_, id, disable) world.extras[id] = not disable end
function GetVehicleNumberPlateText() return world.plate end

-- camera natives
local cams, nextCam = {}, 40
local renders = {}
local lastCam = nil
function CreateCamWithParams(name, x, y, z, rx, ry, rz, fov)
  nextCam = nextCam + 1
  cams[nextCam] = { name = name, active = false, coord = { x = x, y = y, z = z }, rot = { x = rx, y = ry, z = rz }, fov = fov }
  lastCam = nextCam
  return nextCam
end
function DoesCamExist(c) return cams[c] ~= nil end
function SetCamActive(c, v) if cams[c] then cams[c].active = v end end
function DestroyCam(c) cams[c] = nil end
function SetCamCoord(c, x, y, z) if cams[c] then cams[c].coord = { x = x, y = y, z = z } end end
function SetCamRot(c, x, y, z, order) if cams[c] then cams[c].rot = { x = x, y = y, z = z, order = order } end end
function RenderScriptCams(on, ease, ms) renders[#renders + 1] = { on = on, ease = ease, ms = ms } end
function HideHudAndRadarThisFrame() end
local gameplayHeading = nil
function SetGameplayCamRelativeHeading(h) gameplayHeading = h end
function SetGameplayCamRelativePitch() end
local probeHandles = {}
function StartExpensiveSynchronousShapeTestLosProbe(x1, y1, z1, x2, y2, z2, flags, ignore)
  world.probes = world.probes + 1
  local id = #probeHandles + 1
  probeHandles[id] = { from = { x = x1, y = y1, z = z1 }, to = { x = x2, y = y2, z = z2 }, flags = flags, ignore = ignore }
  return id
end
function GetShapeTestResult(id)
  local p = probeHandles[id]
  local dx, dy, dz = p.to.x - p.from.x, p.to.y - p.from.y, p.to.z - p.from.z
  if dx == 0 and dy == 0 then -- straight down: the ground probe under the camera
    local g = world.groundZ
    if g and p.from.z >= g and p.to.z <= g then return 2, true, { x = p.from.x, y = p.from.y, z = g }, {}, 0 end
    return 2, false, { x = 0.0, y = 0.0, z = 0.0 }, {}, 0
  end
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if world.wall and len > world.wall then
    local f = world.wall / len
    return 2, true, { x = p.from.x + dx * f, y = p.from.y + dy * f, z = p.from.z + dz * f }, {}, 0
  end
  return 2, false, { x = 0.0, y = 0.0, z = 0.0 }, {}, 0
end

-- resource env --------------------------------------------------------------------------
function L(text, vars)
  if vars then text = text:gsub('{(%w+)}', function(k) return tostring(vars[k]) end) end
  return text
end
cache = { ped = PED }
lib = { print = { error = function(m) failures[#failures + 1] = 'lib.print.error: ' .. tostring(m) end, warn = function() end } }
function joaat(s) return #tostring(s) end

local nuiHandlers, closeHooks = {}, {}
local opened, sent, closed = {}, {}, {}
local cameraPlaying = false
NZ = {
  ResourceName = 'nayzeee-garages',
  JobsClient = {},
  Camera = { isPlaying = function() return cameraPlaying end },
  Veh = { label = function() return 'Vapid Stanier' end, entityTypeOf = function() return 'automobile' end },
  Utils = {
    trim = function(s) if type(s) ~= 'string' then return s end return (s:gsub('^%s+', ''):gsub('%s+$', '')) end,
    ok = function(d) return { ok = true, data = d } end,
    fail = function(e) return { ok = false, error = e } end,
  },
  NUI = {
    register = function(name, fn) nuiHandlers[name] = fn end,
    onClose = function(app, fn) closeHooks[app] = closeHooks[app] or {}; table.insert(closeHooks[app], fn) end,
    open = function(app, data) opened[#opened + 1] = { app = app, data = data } end,
    send = function(action, data) sent[#sent + 1] = { action = action, data = data } end,
    close = function(app) closed[#closed + 1] = app; for _, fn in ipairs(closeHooks[app] or {}) do fn(app, 'lua') end end,
    notify = function() end,
    await = function() return { ok = false } end,
  },
  Garage = { current = function() return nil end },
  Points = { incapacitated = function() return false end },
}

local chunk = assert(loadfile('client/jobs.lua'))
chunk()
local Jobs = NZ.JobsClient
local O = Jobs.orbitMath
check(type(O) == 'table', 'Jobs.orbitMath exposed')
local C = O.config

---------------------------------------------------------------------------------------
-- 1. pure math
---------------------------------------------------------------------------------------
check(near(O.wrap(190), -170) and near(O.wrap(-190), 170) and near(O.wrap(180), 180) and near(O.wrap(-180), 180) and near(O.wrap(725), 5),
  'wrap keeps angles in (-180, 180]')

local c0 = { x = 0, y = 0, z = 0 }
local behind = O.position(c0, 0, 0, 0, 5)
check(near(behind.x, 0) and near(behind.y, -5) and near(behind.z, 0), 'yaw 0 = behind a north-facing vehicle')
local right = O.position(c0, 0, 90, 0, 5)
check(near(right.x, 5) and near(right.y, 0), 'yaw 90 = its right (east) side')
local front = O.position(c0, 0, 180, 0, 5)
check(near(front.y, 5, 1e-9), 'yaw 180 = in front')
local up = O.position(c0, 0, 0, 30, 4)
check(near(up.z, 2) and near(up.y, -4 * math.cos(math.rad(30))), 'pitch raises the camera')
local turned = O.position(c0, 90, 0, 0, 5) -- facing west (-x): behind = east
check(near(turned.x, 5) and near(turned.y, 0), 'yaw is relative to the vehicle heading')

local rotN = O.lookRotation({ x = 0, y = -5, z = 0 }, c0)
check(near(rotN.z, 0) and near(rotN.x, 0), 'looking north = heading 0')
local rotW = O.lookRotation({ x = 5, y = 0, z = 0 }, c0)
check(near(rotW.z, 90), 'looking west = heading 90 (GTA heading convention)')
local rotDown = O.lookRotation({ x = 0, y = -4, z = 4 }, c0)
check(near(rotDown.x, -45), 'looking down = negative pitch')

local lim = O.limits(DIM_MIN, DIM_MAX)
local r = 0.5 * math.sqrt(2 * 2 + 4.8 * 4.8 + 1.5 * 1.5)
check(near(lim.radius, r) and lim.min > r and lim.default >= lim.min and lim.default <= lim.max, 'limits keep the camera outside the bounding sphere')
local fallback = O.limits(nil, nil)
check(fallback.radius == 2.6 and fallback.min < fallback.max, 'limits fall back without model dimensions')
local huge = O.limits({ x = -500, y = -500, z = -500 }, { x = 500, y = 500, z = 500 })
check(huge.radius == 30.0, 'limits cap absurd model boxes')

check(O.clearance(6, nil) == 6, 'clear line keeps the wanted distance')
check(near(O.clearance(6, 3), 3 - C.margin), 'a hit pulls the camera in front of the surface')
check(O.clearance(6, 0.2) == C.minClear, 'never closer than minClear')
check(O.clearance(6, 0 / 0) == 6, 'NaN hit distance is ignored')

local f1 = O.follow(0, 10, C.smooth, 1 / 60)
check(f1 > 0 and f1 < 10 and O.follow(0, 10, C.smooth, 0) == 0, 'follow moves part of the way, not at dt 0')
check(near(O.followAngle(170, -170, 1000, 1), -170, 1e-3), 'followAngle goes the short way round')
local mid = O.followAngle(170, -170, C.smooth, 1 / 60)
check(mid > 170 or mid < -170, 'followAngle never swings through 0')

local st = O.new(lim)
check(O.input(st, { yaw = 0 / 0, pitch = math.huge, zoom = 'x', foo = 1 }, 0) == false, 'NaN / inf / junk input ignored')
check(st.tYaw == C.yawDefault and st.tPitch == C.pitchDefault and st.tDist == lim.default, 'targets untouched by junk input')
O.input(st, { yaw = 1e9 }, 0)
check(near(st.tYaw, O.wrap(C.yawDefault + C.maxDeltaYaw)), 'yaw delta clamped per message')
O.input(st, { pitch = 1000 }, 0)
check(st.tPitch == C.pitchMax, 'pitch clamped to pitchMax')
O.input(st, { pitch = -1000 }, 0)
check(st.tPitch == C.pitchMin, 'pitch clamped to pitchMin')
O.input(st, { zoom = 1000 }, 0)
check(st.tDist == lim.max, 'zoom clamped to max distance')
for _ = 1, 3 do O.input(st, { zoom = -1000 }, 0) end
check(st.tDist == lim.min, 'zoom clamped to min distance')
O.input(st, { view = 'rear' }, 0)
check(st.tYaw == 0 and st.tPitch == O.views.rear.pitch and near(st.tDist, lim.default), 'rear preset')
check(O.input(st, { view = 'nope' }, 0) == false, 'unknown preset ignored')
O.input(st, { hold = { yaw = 5, pitch = -0.2, zoom = 0 } }, 1000)
check(st.hold and st.hold.yaw == 1 and st.hold.pitch == -1 and st.hold.zoom == 0, 'hold values reduced to -1 / 0 / 1')
local y0 = st.tYaw
O.step(st, 0.5, 1500)
check(near(O.wrap(st.tYaw - y0), C.yawRate * 0.5), 'held key turns at yawRate')
O.step(st, 0.5, 1000 + C.holdTimeout + 1)
check(st.hold == nil, 'hold dropped after holdTimeout without a repeat')
O.input(st, { hold = { yaw = 0, pitch = 0, zoom = 0 } }, 3000)
check(st.hold == nil, 'all-zero hold clears')

-- framing above the menu
check(C.pitchMin >= 0, 'pitchMin keeps the camera above the centre (no line into the ground at max zoom)')
local tanHalf = math.tan(math.rad(C.fov / 2))
check(near(O.lookDropFor(0.6), tanHalf * 0.4 * C.frameBias), 'lookDropFor: tan(fov/2) * (1 - frame) * bias')
check(near(O.lookDropFor(0.05), O.lookDropFor(C.frameMin)) and near(O.lookDropFor(5), O.lookDropFor(C.frameMax)), 'frame clamped to frameMin..frameMax')
check(near(O.lookDropFor(0 / 0), O.lookDropFor(C.frameMin)), 'NaN frame clamped')
check(O.lookDropFor(0.52) > O.lookDropFor(0.65), 'a taller menu (720p) aims lower, so the car rises above it')
local fr = O.new(lim)
check(fr.lookDrop == C.lookDrop, 'default lookDrop until the menu reports its top')
check(O.input(fr, { frame = 0.52 }, 0) == true and near(fr.lookDrop, O.lookDropFor(0.52)), 'frame input sets lookDrop')
check(O.input(fr, { frame = 0 / 0 }, 0) == false and near(fr.lookDrop, O.lookDropFor(0.52)), 'NaN frame ignored')
local tgt = O.lookTarget({ x = 1, y = 2, z = 10 }, 5, 0, 0.2)
check(near(tgt.x, 1) and near(tgt.y, 2) and near(tgt.z, 9), 'lookTarget: drop x distance below the centre')
check(near(O.lookTarget({ x = 0, y = 0, z = 10 }, 5, 60, 0.2).z, 8), 'lookTarget: steep view drops further (/ cos pitch)')
check(near(O.lookTarget({ x = 0, y = 0, z = 10 }, 5, 89, 0.2).z, 8), 'lookTarget: cos pitch floored at 0.5')
check(O.aboveGround(5, nil) == 5 and O.aboveGround(5, 4) == 5 and near(O.aboveGround(5, 4.9), 4.9 + C.groundClear), 'aboveGround lifts only a camera too close to the ground')

local settleState = { dist = 6, clear = nil }
check(O.settle(settleState, 2, 1 / 60) == 2, 'settle snaps in at once')
local out = O.settle(settleState, 6, 1 / 60)
check(out > 2 and out < 6, 'settle eases back out')

---------------------------------------------------------------------------------------
-- 2. open: data + camera
---------------------------------------------------------------------------------------
local function camState() return lastCam and cams[lastCam] end
local function camDistance()
  local cam = camState()
  local center = GetOffsetFromEntityInWorldCoords(VEH, 0, 0, (DIM_MIN.z + DIM_MAX.z) / 2)
  local dx, dy, dz = cam.coord.x - center.x, cam.coord.y - center.y, cam.coord.z - center.z
  return math.sqrt(dx * dx + dy * dy + dz * dz), center
end
--- Camera yaw relative to the vehicle (0 = behind), from its position.
local function camYaw()
  local cam = camState()
  local center = GetOffsetFromEntityInWorldCoords(VEH, 0, 0, (DIM_MIN.z + DIM_MAX.z) / 2)
  local dx, dy = cam.coord.x - center.x, cam.coord.y - center.y
  -- position = center + flat * (sin h, -cos h)  =>  h = atan(dx, -dy)
  return O.wrap(math.deg(math.atan(dx, -dy)) - world.heading)
end

local okOpen = Jobs.openSetup(VEH, { label = '  Police Cruiser  ', model = 'police', plateTemplate = 'job ###', garage = 'Mission Row', maxMods = true })
check(okOpen == true, 'openSetup returns true')
local o1 = opened[#opened]
check(o1 and o1.app == 'setup', 'setup app opened')
local d = o1 and o1.data or {}
check(d.label == 'Police Cruiser' and d.model == 'police' and d.plate == 'JOB 042' and d.garage == 'Mission Row', 'detail fields trimmed and sent')
check(d.plateTemplate == 'job ###' and d.liveryMode == 'livery' and d.maxMods == true and d.camera == true, 'template, livery mode, maxMods, camera flag')
check(#d.liveries == 3 and d.liveries[1].label == 'Patrol' and d.liveries[2].label == 'Livery 2' and d.livery == 1, 'liveries read')
check(#d.extras == 3, 'extras read')
local modsById = {}
for _, m in ipairs(d.mods or {}) do modsById[m.id] = m end
check(modsById.engine and modsById.engine.level == 4 and modsById.engine.max == 4, 'engine 4/4')
check(modsById.brakes and modsById.brakes.level == 0 and modsById.brakes.max == 3, 'brakes stock 0/3')
check(modsById.suspension and modsById.suspension.level == 2, 'suspension 2/4')
check(modsById.transmission == nil and modsById.armour == nil, 'mods the model lacks are left out')
check(modsById.turbo and modsById.turbo.level == 1 and modsById.turbo.max == 1, 'turbo on')
check(world.frozen == true, 'vehicle frozen')
check(renders[#renders] and renders[#renders].on == true and renders[#renders].ease == true and renders[#renders].ms == C.ease, 'cam eased in')
check(camState() and camState().active == true, 'scripted cam active')

local dist0 = camDistance()
check(dist0 >= lim.min - 1e-6 and near(dist0, lim.default, 1e-3), 'opening distance = default, outside the vehicle')
check(near(camYaw(), C.yawDefault, 1e-3), 'opening view = front three-quarter')
check(camState().rot.order == 2, 'rotation order 2')
-- the cam looks at a point just below the centre: its heading points at the vehicle
do
  local cam = camState()
  local _, center = camDistance()
  local want = math.deg(math.atan(-(center.x - cam.coord.x), center.y - cam.coord.y))
  check(near(O.wrap(cam.rot.z - want), 0, 1e-3), 'cam heading points at the vehicle')
  check(cam.rot.x < 0, 'cam pitches down toward the vehicle')
end

---------------------------------------------------------------------------------------
-- 3. input through the NUI callback
---------------------------------------------------------------------------------------
local cb = nuiHandlers['setup:camera']
check(type(cb) == 'function', 'setup:camera registered')
local res = cb({ yaw = 90 })
check(res.ok == true, 'setup:camera ok while open')
advance(2000)
check(near(camYaw(), O.wrap(C.yawDefault + 90), 0.5), 'drag yaw applied (smoothed to target)')

cb({ zoom = 1000 })
advance(2000)
check(near(camDistance(), lim.max, 0.05), 'zoom clamps to max distance')
cb({ zoom = -1000 })
cb({ zoom = -1000 })
cb({ zoom = -1000 })
advance(2000)
check(near(camDistance(), lim.min, 0.05), 'zoom clamps to min distance (6 steps per message at most)')

cb({ pitch = 500 })
advance(2000)
do
  local cam = camState()
  local dist, center = camDistance()
  local pitch = math.deg(math.asin((cam.coord.z - center.z) / dist))
  check(near(pitch, C.pitchMax, 0.5), 'pitch clamped to pitchMax in the world too')
end

cb({ view = 'reset' })
advance(2000)
check(near(camYaw(), C.yawDefault, 0.5) and near(camDistance(), lim.default, 0.05), 'reset preset back to the opening view')

-- held key: turns while repeated, stops when the repeats stop
local yawBefore = camYaw()
cb({ hold = { yaw = 1, pitch = 0, zoom = 0 } })
advance(400)
cb({ hold = { yaw = 1, pitch = 0, zoom = 0 } }) -- the interface repeats every 400 ms
advance(400)
local turnedBy = O.wrap(camYaw() - yawBefore)
check(turnedBy > 40, 'held key keeps turning while repeated')
advance(C.holdTimeout + 600)
local stopped = camYaw()
advance(1000)
check(near(camYaw(), stopped, 0.05), 'hold dropped when the repeats stop (lost key-up)')

---------------------------------------------------------------------------------------
-- 4. collision
---------------------------------------------------------------------------------------
cb({ view = 'reset' })
advance(2000)
check(world.probes > 0, 'probes run while orbiting')
local lastProbe, groundProbe
for i = #probeHandles, 1, -1 do
  local p = probeHandles[i]
  if p.flags == C.probeFlags and not lastProbe then lastProbe = p end
  if p.flags == C.groundFlags and not groundProbe then groundProbe = p end
end
check(lastProbe and lastProbe.ignore == VEH, 'probe ignores the setup vehicle, world + vehicles + objects')
check(groundProbe and groundProbe.ignore == VEH and groundProbe.from.x == groundProbe.to.x and groundProbe.from.y == groundProbe.to.y
  and near(groundProbe.from.z - groundProbe.to.z, C.groundClear + 0.05), 'ground probe: straight down, groundClear long, world + objects')
world.wall = 2.0
advance(32)
check(camDistance() <= 2.0 - C.margin + 1e-6 and camDistance() >= C.minClear, 'wall pulls the camera in at once')
world.wall = nil
advance(100)
local midOut = camDistance()
check(midOut > 2.0 - C.margin and midOut < lim.default, 'camera eases back out')
advance(3000)
check(near(camDistance(), lim.default, 0.05), 'back at the wanted distance')

-- ground right under the camera (uphill): the camera is lifted clear of it
do
  local camZ = camState().coord.z
  world.groundZ = camZ - 0.1
  advance(32)
  check(near(camState().coord.z, world.groundZ + C.groundClear, 1e-3), 'camera lifted groundClear above the ground under it')
  world.groundZ = camZ - 1.0
  advance(32)
  check(near(camState().coord.z, camZ, 1e-3), 'ground well below: camera height unchanged')
  world.groundZ = nil
end

-- framing: the menu reports its top edge, the camera aims lower so the car sits above it
do
  local before = camState().rot.x
  check(cb({ frame = 0.52 }).ok == true, 'setup:camera frame ok')
  advance(32)
  local cam = camState()
  local dist, center = camDistance()
  local pitch = math.deg(math.asin((cam.coord.z - center.z) / dist))
  local want = O.lookRotation(cam.coord, O.lookTarget(center, dist, pitch, O.lookDropFor(0.52)))
  check(near(cam.rot.x, want.x, 0.05) and cam.rot.x < before, 'frame 0.52 (720p) aims below the default')
end

---------------------------------------------------------------------------------------
-- 5. setup callbacks unchanged
---------------------------------------------------------------------------------------
check(nuiHandlers['setup:livery']({ index = 2 }).ok and world.livery == 2, 'setup:livery still applies')
-- a livery that does not take (not streamed / out of range) is reported, after one frame
do
  local function liveryCall(index)
    local result
    CreateThread(function() result = nuiHandlers['setup:livery']({ index = index }) end)
    advance(50)
    return result
  end
  world.liveryStreamed = { [0] = true, [2] = true }
  local r1 = liveryCall(1)
  check(r1 and r1.ok == false and r1.error == 'This livery is not available' and world.livery == 2, 'livery that does not apply -> not available')
  world.liveryStreamed = nil
  local r2 = liveryCall(7)
  check(r2 and r2.ok == false and r2.error == 'This livery is not available', 'out-of-range livery -> not available')
  local r3 = liveryCall(-1)
  check(r3 and r3.ok == false and world.livery == 2, 'negative index in livery mode refused')
  local r4 = liveryCall(0)
  check(r4 and r4.ok == true and world.livery == 0, 'streamed livery applies')
end
local sentBefore = #sent
check(nuiHandlers['setup:extra']({ id = 2, enabled = true }).ok and world.extras[2] == true, 'setup:extra still applies')
check(#sent == sentBefore + 1 and sent[#sent].action == 'update', 'extras state sent back')

---------------------------------------------------------------------------------------
-- 6. drive: blend back, destroy after the blend
---------------------------------------------------------------------------------------
local driveCam = lastCam
check(nuiHandlers['setup:drive']({}).ok, 'setup:drive ok')
check(renders[#renders].on == false and renders[#renders].ease == true and renders[#renders].ms == C.ease, 'blends back to the gameplay cam')
check(gameplayHeading == 0.0, 'gameplay cam put behind the vehicle')
check(world.frozen == false, 'vehicle unfrozen')
check(closed[#closed] == 'setup', 'app closed')
check(cams[driveCam] ~= nil, 'cam kept during the blend')
advance(C.ease + 100)
check(cams[driveCam] == nil, 'cam destroyed after the blend')
check(cb({ yaw = 10 }).ok == false, 'setup:camera fails without an open setup')
local rendersAfter = #renders
advance(500)
check(#renders == rendersAfter, 'no more camera work after drive')

---------------------------------------------------------------------------------------
-- 7. vehicle deleted while open
---------------------------------------------------------------------------------------
Jobs.openSetup(VEH, {})
local delCam = lastCam
check(opened[#opened].data.camera == true and opened[#opened].data.plateTemplate == nil, 'reopen without spawner info: no template')
advance(100)
world.exists[VEH] = nil
local closedBefore = #closed
advance(100)
check(#closed == closedBefore + 1 and closed[#closed] == 'setup', 'deleted vehicle closes the app')
check(renders[#renders].on == false, 'deleted vehicle: back to the gameplay cam')
advance(C.ease + 100)
check(cams[delCam] == nil, 'deleted vehicle: cam destroyed')
world.exists[VEH] = true

---------------------------------------------------------------------------------------
-- 8. another camera path playing: no orbit
---------------------------------------------------------------------------------------
cameraPlaying = true
local camsBefore = nextCam
Jobs.openSetup(VEH, {})
check(opened[#opened].data.camera == false and nextCam == camsBefore, 'cutscene camera playing: orbit stays off')
check(cb({ yaw = 30 }).ok == true, 'camera input ignored quietly without an orbit')
local rendersBefore = #renders
nuiHandlers['setup:drive']({})
check(#renders == rendersBefore, 'drive leaves the other camera alone')
cameraPlaying = false

---------------------------------------------------------------------------------------
-- 8b. player taken away from the vehicle while the menu is open (admin /tp, another script)
---------------------------------------------------------------------------------------
Jobs.openSetup(VEH, {})
local tpCam = lastCam
advance(100)
world.pedVehicle = 0
world.pedPos = { x = world.pos.x + 3.0, y = world.pos.y, z = world.pos.z } -- got out, next to it
local closedBeforeTp = #closed
advance(C.playerCheck * 2)
check(#closed == closedBeforeTp and cams[tpCam] and cams[tpCam].active, 'out of the vehicle but next to it: menu stays')
world.pedPos = { x = world.pos.x + 400.0, y = world.pos.y, z = world.pos.z }
advance(C.playerCheck + 50)
check(#closed == closedBeforeTp + 1 and closed[#closed] == 'setup', 'teleported away: menu closed')
check(renders[#renders].on == false and world.frozen == false, 'teleported away: back to the gameplay cam, vehicle unfrozen')
advance(C.ease + 100)
check(cams[tpCam] == nil, 'teleported away: cam destroyed')
check(nuiHandlers['setup:camera']({ yaw = 5 }).ok == false, 'no setup left after the teleport')
world.pedVehicle, world.pedPos = VEH, nil

---------------------------------------------------------------------------------------
-- 8c. mod-slot liveries (slot 48): read back too
---------------------------------------------------------------------------------------
do
  local savedCount = world.liveryCount
  world.liveryCount = 0
  world.mods[48] = { count = 3, cur = -1 }
  Jobs.openSetup(VEH, {})
  check(opened[#opened].data.liveryMode == 'mod', 'mod-slot livery mode')
  local result
  CreateThread(function() result = nuiHandlers['setup:livery']({ index = 1 }) end)
  advance(50)
  check(result and result.ok == true and world.mods[48].cur == 1, 'mod livery applies and reads back')
  CreateThread(function() result = nuiHandlers['setup:livery']({ index = 5 }) end)
  advance(50)
  check(result and result.ok == false and result.error == 'This livery is not available' and world.mods[48].cur == 1, 'missing mod livery -> not available')
  CreateThread(function() result = nuiHandlers['setup:livery']({ index = -1 }) end)
  advance(50)
  check(result and result.ok == true and world.mods[48].cur == -1, 'mod livery -1 = default')
  nuiHandlers['setup:drive']({})
  advance(C.ease + 100)
  world.mods[48] = nil
  world.liveryCount = savedCount
end

---------------------------------------------------------------------------------------
-- 9. nothing to configure / resource stop
---------------------------------------------------------------------------------------
local saved = { world.liveryCount, world.extras, world.mods }
world.liveryCount, world.extras, world.mods = 1, {}, {}
check(Jobs.openSetup(VEH, {}) == false, 'nothing to configure -> false, no app')
world.liveryCount, world.extras, world.mods = saved[1], saved[2], saved[3]

Jobs.openSetup(VEH, {})
local stopCam = lastCam
advance(50)
fire('onResourceStop', 'nayzeee-garages')
check(cams[stopCam] == nil and renders[#renders].on == false and world.frozen == false, 'resource stop drops the cam and unfreezes')
advance(200)

---------------------------------------------------------------------------------------
if #failures > 0 then
  print(('setup_camera: %d/%d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('setup_camera OK (%d checks)'):format(checks))
