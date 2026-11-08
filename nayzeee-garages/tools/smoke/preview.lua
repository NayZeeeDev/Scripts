--[[
  Standalone test for the showroom's 3D vehicle preview (client/preview.lua, NZ.Preview) and
  its wiring in client/garage.lua / client/impound.lua ('garage:preview' and
  'garage:previewRect' NUI callbacks, close hooks). No FiveM needed.

  1. Framing math: for real-sized models (sedan, bike, bus, jet, boat) and stage rectangles
     at 1920x1080 / 1280x720 / ultrawide, the camera from NZ.Preview.computeFrame is checked
     with an independent projection: every corner of the model box, at every heading in 3°
     steps, lands inside the stage rectangle, and the car still fills it (no tiny car).
  2. Runtime: the real preview.lua, garage.lua and impound.lua run in a stubbed client with a
     fake clock: show (local, non-networked, frozen, no collision, faded in), swap (old one
     faded out and deleted), stale requests, spawner (no server data), impound (its own
     server callback), missing data / unknown model / server callback that never answers
     (image fallback), rect updates re-framing the camera, menu close, death (interface told),
     setting off, resource stop, and that nothing is left behind (cams, vehicles, focus).

  Usage (from the resource root):  lua5.4 tools/smoke/preview.lua [-v]
]]

local VERBOSE = select(1, ...) == '-v'
local failures, checks = {}, 0
local scenarioName = 'math'
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = ('[%s] %s'):format(scenarioName, label) end
  return cond
end
local function say(...) if VERBOSE then print(...) end end

---------------------------------------------------------------------------------------
-- Clock and threads
---------------------------------------------------------------------------------------

local now = 100000
local threads = {}
local runtimeErrors = {}

local function addThread(fn)
  threads[#threads + 1] = { co = coroutine.create(fn), wake = now }
end

local function resumeAll()
  local list = threads
  threads = {}
  local keep = {}
  for _, t in ipairs(list) do
    if t.wake <= now then
      local ok, res = coroutine.resume(t.co)
      if not ok then
        runtimeErrors[#runtimeErrors + 1] = ('[%s] %s'):format(scenarioName, debug.traceback(t.co, res))
      elseif coroutine.status(t.co) ~= 'dead' then
        t.wake = now + math.max(0, tonumber(res) or 0)
        keep[#keep + 1] = t
      end
    else
      keep[#keep + 1] = t
    end
  end
  for _, t in ipairs(threads) do keep[#keep + 1] = t end
  threads = keep
end

local frames = 0
local function run(ms)
  local stop = now + ms
  repeat
    resumeAll()
    now = now + 16
    frames = frames + 1
  until now >= stop
  resumeAll()
end

---------------------------------------------------------------------------------------
-- Stubbed client
---------------------------------------------------------------------------------------

local function joaat(s)
  local h = 0
  s = tostring(s):lower()
  for i = 1, #s do
    h = (h + s:byte(i)) & 0xffffffff
    h = (h + (h << 10)) & 0xffffffff
    h = h ~ (h >> 6)
  end
  h = (h + (h << 3)) & 0xffffffff
  h = h ~ (h >> 11)
  h = (h + (h << 15)) & 0xffffffff
  if h > 0x7fffffff then h = h - 0x100000000 end
  return h
end

local function vec3(x, y, z) return { x = x + 0.0, y = y + 0.0, z = z + 0.0 } end

local MODELS = {
  sultan = { min = vec3(-0.95, -2.3, -0.6), max = vec3(0.95, 2.3, 0.9) },
  bati = { min = vec3(-0.4, -1.1, -0.55), max = vec3(0.4, 1.1, 0.7) },
  bus = { min = vec3(-1.5, -6.5, -1.2), max = vec3(1.5, 6.5, 2.4) },
  luxor = { min = vec3(-10.6, -11.2, -1.8), max = vec3(10.6, 11.2, 4.1) },
  dinghy = { min = vec3(-1.2, -3.0, -0.8), max = vec3(1.2, 3.0, 1.2) },
}
local BY_HASH = {}
for name, m in pairs(MODELS) do BY_HASH[joaat(name)] = m end

local W -- per scenario world

local function freshWorld()
  W = {
    entities = {}, nextEntity = 100, cams = {}, nextCam = 1, render = false, renderCalls = {},
    focus = false, nuiOpen = {}, sent = {}, awaits = {}, serverData = {}, serverHang = {},
    serverFail = {}, serverRateOnce = {}, mods = {}, models = { sultan = true, bati = true, bus = true, luxor = true, dinghy = true },
    dead = false, hud = 0, lights = 0, settings = { interface = {} }, ped = 7, plateTexts = {},
    props = {}, damage = {}, released = {}, deletedAlpha = {},
  }
end
freshWorld()

local env = setmetatable({}, { __index = _G })
env._ENV = env

-- natives used by the files under test
env.GetGameTimer = function() return now end
env.Wait = function(ms) coroutine.yield(ms or 0) end
env.CreateThread = function(fn) addThread(fn) end
env.SetTimeout = function(ms, fn) addThread(function() coroutine.yield(ms) fn() end) end
env.AddEventHandler = function(name, fn)
  env.__handlers = env.__handlers or {}
  env.__handlers[name] = env.__handlers[name] or {}
  table.insert(env.__handlers[name], fn)
end
env.RegisterNetEvent = function(name, fn) if fn then env.AddEventHandler(name, fn) end end
env.exports = setmetatable({}, { __call = function() end })
env.GetCurrentResourceName = function() return 'nayzeee-garages' end
env.IsDuplicityVersion = function() return false end
env.json = { decode = function() return nil end, encode = function() return '{}' end }
env.vector3 = vec3

env.CreateVehicle = function(hash, x, y, z, h, networked, scriptHost)
  if not BY_HASH[hash] then return 0 end
  W.nextEntity = W.nextEntity + 1
  local e = W.nextEntity
  W.entities[e] = { hash = hash, x = x, y = y, z = z, h = h, networked = networked, scriptHost = scriptHost,
    frozen = false, collision = true, alpha = 255, mission = false, created = now, frozenAtCreate = nil }
  return e
end
env.DoesEntityExist = function(e) return W.entities[e] ~= nil end
env.GetEntityModel = function(e) return W.entities[e] and W.entities[e].hash or 0 end
env.SetModelAsNoLongerNeeded = function(hash) W.released[hash] = (W.released[hash] or 0) + 1 end
env.DeleteVehicle = function(e) W.entities[e] = nil end
env.DeleteEntity = function(e) W.entities[e] = nil end
env.FreezeEntityPosition = function(e, v)
  local en = W.entities[e]
  if en then
    en.frozen = v
    if en.frozenAtCreate == nil then en.frozenAtCreate = (en.created == now) and v end
  end
end
env.SetEntityCollision = function(e, v) if W.entities[e] then W.entities[e].collision = v end end
env.SetEntityAlpha = function(e, a) if W.entities[e] then W.entities[e].alpha = a end end
env.ResetEntityAlpha = function(e) if W.entities[e] then W.entities[e].alpha = 255 end end
env.GetEntityAlpha = function(e) return W.entities[e] and W.entities[e].alpha or 255 end
env.SetEntityAsMissionEntity = function(e) if W.entities[e] then W.entities[e].mission = true end end
env.SetEntityRotation = function(e, _, _, h) if W.entities[e] then W.entities[e].h = h end end
env.SetEntityCoordsNoOffset = function(e, x, y, z) local en = W.entities[e] if en then en.x, en.y, en.z = x, y, z end end
env.SetVehicleNumberPlateText = function(e, t) W.plateTexts[e] = t end
env.GetModelDimensions = function(hash)
  local m = BY_HASH[hash]
  if not m then return nil end
  return m.min, m.max
end
-- Both only ever get the player's ped: a nil / stale handle (e.g. a local shadowing ox_lib's
-- `cache`) puts the studio at the map origin in game, so it fails loudly here.
env.PlayerPedId = function() return W.ped end
env.GetEntityCoords = function(e)
  if e ~= W.ped then error(('GetEntityCoords called with %s, expected the player ped %s'):format(tostring(e), tostring(W.ped)), 2) end
  return vec3(215.0, -810.0, 30.7)
end
env.IsEntityDead = function(e)
  if e ~= W.ped then error(('IsEntityDead called with %s, expected the player ped'):format(tostring(e)), 2) end
  return W.dead
end
env.GetActiveScreenResolution = function() return 1920, 1080 end
env.GetClockHours = function() return 23 end
env.DrawLightWithRange = function() W.lights = W.lights + 1 end
env.HideHudAndRadarThisFrame = function() W.hud = W.hud + 1 end
env.CreateCamWithParams = function(_, x, y, z, rx, ry, rz, fov)
  local c = W.nextCam
  W.nextCam = W.nextCam + 1
  W.cams[c] = { pos = vec3(x, y, z), rot = vec3(rx, ry, rz), fov = fov, active = false }
  return c
end
env.DoesCamExist = function(c) return W.cams[c] ~= nil end
env.SetCamActive = function(c, v) if W.cams[c] then W.cams[c].active = v end end
env.DestroyCam = function(c) W.cams[c] = nil end
env.SetCamCoord = function(c, x, y, z) if W.cams[c] then W.cams[c].pos = vec3(x, y, z) end end
env.SetCamRot = function(c, x, y, z) if W.cams[c] then W.cams[c].rot = vec3(x, y, z) end end
env.SetCamFov = function(c, f) if W.cams[c] then W.cams[c].fov = f end end
env.RenderScriptCams = function(on) W.render = on W.renderCalls[#W.renderCalls + 1] = { on = on, at = now } end
env.SetFocusPosAndVel = function() W.focus = true end
env.ClearFocus = function() W.focus = false end
-- no-ops
for _, n in ipairs({ 'SetEntityInvincible', 'SetVehicleDoorsLocked', 'SetVehicleEngineOn',
  'SetVehRadioStation', 'SetVehicleRadioEnabled', 'SetEntityLodDist', 'SetNewWaypoint', 'DoScreenFadeIn',
  'DoScreenFadeOut' }) do
  env[n] = function() end
end

env.lib = {
  print = {
    error = function(m) runtimeErrors[#runtimeErrors + 1] = ('[%s] lib.print.error %s'):format(scenarioName, tostring(m)) end,
    warn = function(m) say('warn', m) end,
    info = function() end,
  },
  setVehicleProperties = function(e, props) W.props[e] = props end,
  alertDialog = function() return nil end,
}
env.cache = setmetatable({}, { __index = function(_, k) if k == 'ped' then return W.ped end end })

env.Config = { Locale = 'en', DefaultSettings = { interface = {}, garages = {}, vehicles = {} } }
env.Locales = {}

---------------------------------------------------------------------------------------
-- NZ (real shared/init.lua + utils, stubbed neighbours)
---------------------------------------------------------------------------------------

local function loadFile(path)
  local f = assert(io.open(path, 'r'))
  local src = f:read('a')
  f:close()
  local chunk = assert(load(src, '@' .. path, 't', env))
  chunk()
end

loadFile('shared/init.lua')
loadFile('shared/utils.lua')
local NZ = env.NZ
NZ.State.settings = setmetatable({}, { __index = function(_, k) return W.settings[k] end })

NZ.NUI.isOpen = function(app) return W.nuiOpen[app] == true end
NZ.NUI.send = function(action, data) W.sent[#W.sent + 1] = { action = action, data = data } end
NZ.NUI.notify = function() end
NZ.NUI.syncFocus = function() end
local nuiHandlers, closeHooks = {}, {}
NZ.NUI.register = function(name, fn) nuiHandlers[name] = fn end
NZ.NUI.onClose = function(app, fn) closeHooks[app] = closeHooks[app] or {} table.insert(closeHooks[app], fn) end
NZ.NUI.await = function(name, payload)
  W.awaits[#W.awaits + 1] = { name = name, payload = payload }
  if W.serverHang[name] then
    while true do coroutine.yield(1000) end
  end
  coroutine.yield(40)
  if W.serverRateOnce[name] then
    W.serverRateOnce[name] = nil
    return { ok = false, error = env.L('Please wait a moment before trying again') }
  end
  if W.serverFail[name] then return { ok = false, error = W.serverFail[name] } end
  local d = W.serverData[payload.plate]
  if not d then return { ok = false, error = 'Vehicle not found' } end
  return { ok = true, data = d }
end
NZ.NUI.open = function(app) W.nuiOpen[app] = true end
NZ.NUI.close = function(app)
  W.nuiOpen[app] = nil
  for _, fn in ipairs(closeHooks[app] or {}) do fn(app, 'lua') end
end

NZ.Points.incapacitated = function() return W.dead end
NZ.Camera.isPlaying = function() return false end
NZ.Veh.requestModel = function(hash) coroutine.yield(60) return BY_HASH[hash] ~= nil end
NZ.Veh.delete = function(e)
  if W.entities[e] then W.deletedAlpha[e] = W.entities[e].alpha end
  W.entities[e] = nil
  return true
end
NZ.Veh.enrichDeep = function(t) return t end
NZ.Damage.apply = function(e, d) W.damage[e] = d return true end
NZ.Utils.debug = function() end
NZ.JobsClient.applyMods = function(e, info) W.mods[e] = info end

loadFile('client/preview.lua')
loadFile('client/garage.lua')
loadFile('client/impound.lua')

local Preview = NZ.Preview

---------------------------------------------------------------------------------------
-- 1. Framing math (independent projection)
---------------------------------------------------------------------------------------

local function basis(pitch, yaw)
  local p, z = math.rad(pitch), math.rad(yaw)
  local f = { math.cos(p) * -math.sin(z), math.cos(p) * math.cos(z), math.sin(p) }
  local r = { math.cos(z), math.sin(z), 0 }
  -- up = right x forward
  local u = { r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1] }
  return f, r, u
end

local function projectIndep(frame, aspect, q)
  local f, r, u = basis(frame.rot.x, frame.rot.z)
  local v = { q.x - frame.pos.x, q.y - frame.pos.y, q.z - frame.pos.z }
  local depth = v[1] * f[1] + v[2] * f[2] + v[3] * f[3]
  local tanV = math.tan(math.rad(frame.fov / 2))
  local tanH = tanV * aspect
  local x = (v[1] * r[1] + v[2] * r[2] + v[3] * r[3]) / (depth * tanH)
  local y = (v[1] * u[1] + v[2] * u[2] + v[3] * u[3]) / (depth * tanV)
  return (x + 1) / 2, (1 - y) / 2, depth
end

local function extentAt(frame, aspect, origin, m, heading)
  local h = math.rad(heading)
  local s, c = math.sin(h), math.cos(h)
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  local behind = false
  for _, x in ipairs({ m.min.x, m.max.x }) do
    for _, y in ipairs({ m.min.y, m.max.y }) do
      for _, z in ipairs({ m.min.z, m.max.z }) do
        local q = { x = origin.x + x * c - y * s, y = origin.y + x * s + y * c, z = origin.z + z }
        local sx, sy, depth = projectIndep(frame, aspect, q)
        if depth <= 0 then behind = true end
        minX, maxX = math.min(minX, sx), math.max(maxX, sx)
        minY, maxY = math.min(minY, sy), math.max(maxY, sy)
      end
    end
  end
  return minX, maxX, minY, maxY, behind
end

local SCREENS = {
  { label = '1920x1080 right pane', vw = 1920, vh = 1080, rect = { x = 715, y = 154, w = 820, h = 170 } },
  { label = '1280x720 right pane', vw = 1280, vh = 720, rect = { x = 420, y = 128, w = 560, h = 110 } },
  { label = '2560x1080 ultrawide', vw = 2560, vh = 1080, rect = { x = 1100, y = 160, w = 860, h = 180 } },
  { label = 'centred square', vw = 1920, vh = 1080, rect = { x = 760, y = 340, w = 400, h = 400 } },
}

local origin = { x = 215.0, y = -810.0, z = 650.0 }
for _, screen in ipairs(SCREENS) do
  local raw = { x = screen.rect.x, y = screen.rect.y, w = screen.rect.w, h = screen.rect.h, vw = screen.vw, vh = screen.vh, dpr = 1 }
  local rect = Preview.normalizeRect(raw)
  check(rect ~= nil, screen.label .. ': rect normalized')
  if rect then
    check(math.abs(rect.aspect - screen.vw / screen.vh) < 1e-6, screen.label .. ': aspect from the viewport')
    for name, m in pairs(MODELS) do
      for _, opts in ipairs({ {}, { pitch = -25, yaw = 140, fov = 45, fill = 0.8 }, { pitch = 0, yaw = -60, fov = 22 } }) do
        local frame = Preview.computeFrame(origin, m, rect, opts)
        local fill = opts.fill or 0.9
        local label = ('%s / %s / pitch %s'):format(screen.label, name, tostring(opts.pitch or 'default'))
        local worstOut = 0
        local bestFillW, bestFillH = 0, 0
        local behind = false
        for heading = 0, 357, 3 do
          local minX, maxX, minY, maxY, b = extentAt(frame, rect.aspect, origin, m, heading)
          behind = behind or b
          worstOut = math.max(worstOut, rect.x - minX, maxX - (rect.x + rect.w), rect.y - minY, maxY - (rect.y + rect.h))
          bestFillW = math.max(bestFillW, (maxX - minX) / rect.w)
          bestFillH = math.max(bestFillH, (maxY - minY) / rect.h)
        end
        check(not behind, label .. ': every corner in front of the camera')
        check(worstOut <= 1e-4, label .. (': car stays inside the stage at every heading (worst overflow %.4f)'):format(worstOut))
        -- the binding dimension is (nearly) filled: no tiny car in a big stage
        check(math.max(bestFillW, bestFillH) >= fill * 0.85,
          label .. (': car fills the stage (%.2f wide, %.2f high, fill %.2f)'):format(bestFillW, bestFillH, fill))
        -- the box centre is on the stage centre
        local cx, cy = projectIndep(frame, rect.aspect, frame.target)
        check(math.abs(cx - (rect.x + rect.w / 2)) < 1e-6 and math.abs(cy - (rect.y + rect.h / 2)) < 1e-6,
          label .. ': box centre projected on the stage centre')
        say(('%-60s d=%6.2f fill w %.2f h %.2f'):format(label, frame.distance, bestFillW, bestFillH))
      end
    end
  end
end

-- normalizeRect edge cases
check(Preview.normalizeRect(nil) == nil, 'nil rect refused')
check(Preview.normalizeRect({ x = 0, y = 0, w = 0, h = 10, vw = 100, vh = 100 }) == nil, 'zero width refused')
check(Preview.normalizeRect({ x = 'a', y = 0, w = 10, h = 10, vw = 100, vh = 100 }) == nil, 'non-number refused')
check(Preview.normalizeRect({ x = 0, y = 0, w = 1 / 0, h = 10, vw = 100, vh = 100 }) == nil, 'infinity refused')
check(Preview.normalizeRect({ x = 0, y = 0, w = 0 / 0, h = 10, vw = 100, vh = 100 }) == nil, 'NaN refused')
do
  local r = Preview.normalizeRect({ x = 960, y = 540, w = 480, h = 270, dpr = 2 }, 3840, 2160)
  check(r and math.abs(r.x - 0.5) < 1e-9 and math.abs(r.w - 0.25) < 1e-9, 'screen size / dpr used when vw / vh are missing')
  local c = Preview.normalizeRect({ x = 1800, y = 1000, w = 900, h = 900, vw = 1920, vh = 1080 })
  check(c and c.x + c.w <= 1 + 1e-9 and c.y + c.h <= 1 + 1e-9, 'rect clamped to the screen')
end
-- missing model dimensions: a sedan-sized default box
do
  local frame = Preview.computeFrame(origin, nil, nil, {})
  check(frame.distance > 1 and frame.distance < 60, 'default dims / rect give a usable distance')
end

---------------------------------------------------------------------------------------
-- 2. Runtime scenarios
---------------------------------------------------------------------------------------

local respAt = nil
local function nui(name, payload)
  local resp
  addThread(function()
    resp = nuiHandlers[name](payload or {})
    respAt = now
  end)
  return function() return resp end
end

local function liveVehicles()
  local list = {}
  for e in pairs(W.entities) do list[#list + 1] = e end
  return list
end

local function liveCams()
  local n = 0
  for _ in pairs(W.cams) do n = n + 1 end
  return n
end

local function onlyVehicle()
  local list = liveVehicles()
  if #list ~= 1 then return nil end
  return list[1], W.entities[list[1]]
end

local garageData = {
  garage = { key = 'L1', locationId = 1 },
  vehicles = {
    { plate = 'NZ 001', hash = joaat('sultan'), state = 'garaged' },
    { plate = 'NZ 002', hash = joaat('bati'), state = 'garaged' },
    { plate = 'NZ 404', hash = joaat('unknownmodel'), state = 'garaged' },
    { plate = 'NZ 005', hash = joaat('bus'), state = 'garaged' },
  },
  spawner = {
    { index = 2, hash = joaat('bus'), model = 'bus' },
    { index = 3, hash = joaat('sultan'), model = 'sultan', livery = 2, extras = { ['1'] = true }, maxMods = true },
  },
}

local function openGarage()
  -- the real NZ.Garage.open: server answers nz:garage:open, Lua opens the app
  W.serverData.__open = garageData
  local saved = NZ.NUI.await
  NZ.NUI.await = function(name, payload)
    if name == 'nz:garage:open' then return { ok = true, data = garageData } end
    return saved(name, payload)
  end
  addThread(function() NZ.Garage.open(1) end)
  run(100)
  NZ.NUI.await = saved
end

local function scenario(name, fn)
  scenarioName = name
  freshWorld()
  Preview.stop(false)
  Preview.reset()
  W.sent = {}
  W.serverData = {
    ['NZ 001'] = { hash = joaat('sultan'), props = { plate = 'NZ 001', color1 = 12 }, damage = { doors = { [1] = true } }, engine = 80, body = 70 },
    ['NZ 002'] = { hash = joaat('bati'), props = { plate = 'NZ 002' } },
    ['NZ 005'] = { hash = joaat('bus'), props = { plate = 'NZ 005' } },
    ['NZ 404'] = { hash = joaat('unknownmodel'), props = {} },
    ['IMP 9'] = { hash = joaat('dinghy'), props = { plate = 'IMP 9' } },
  }
  fn()
  Preview.stop(false)
  run(50)
end

local RECT = { x = 715, y = 154, w = 820, h = 170, vw = 1920, vh = 1080, dpr = 1 }

scenario('show', function()
  openGarage()
  check(W.nuiOpen.garage, 'garage menu open')
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(600)
  local resp = r()
  check(resp and resp.ok and resp.data.shown == true, 'preview shown')
  local e, en = onlyVehicle()
  check(e ~= nil, 'exactly one preview vehicle')
  if en then
    check(en.networked == false, 'preview vehicle is local (not networked)')
    check(en.frozen == true and en.frozenAtCreate == true, 'frozen in the frame it was created')
    check(en.collision == false, 'no collision')
    check(en.z >= 650.0, 'studio high above the player / every building')
    check(en.mission == true, 'mission entity (not culled)')
    check(W.props[e] and W.props[e].color1 == 12, 'stored props applied')
    check(W.damage[e] and W.damage[e].doors and W.damage[e].engine == 800.0, 'stored damage applied (engine from percent)')
    check(W.plateTexts[e] == 'NZ 001', 'plate text set')
    check(en.alpha == 255, 'faded in')
  end
  check(W.render == true and liveCams() == 1, 'scripted camera rendering')
  local first = W.renderCalls[1]
  check(first and first.on == true and respAt and first.at >= respAt + 90,
    'camera switches only after the interface was told (no studio flash around the window)')
  check(W.awaits[#W.awaits].name == 'nz:garage:preview' and W.awaits[#W.awaits].payload.plate == 'NZ 001', 'server data asked by plate')
  check(W.hud > 10, 'HUD hidden while previewing')
  check(W.lights > 0, 'night lights drawn')
  -- turning
  local h1 = en and en.h
  run(1000)
  check(en and en.h ~= h1 and math.abs(((en.h - h1) % 360) - 9.0) < 1.0, 'turns about 9 degrees per second')
  -- same selection again: nothing respawns
  local before = e
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(100)
  check(r() and r().data.shown == true and onlyVehicle() == before, 'same vehicle kept on a repeated request')
  -- close: everything cleaned
  NZ.NUI.close('garage')
  check(#liveVehicles() == 0 and liveCams() == 0 and W.render == false, 'menu close removes vehicle + camera')
end)

scenario('swap and stale', function()
  openGarage()
  nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(600)
  local first = onlyVehicle()
  local camBefore = W.cams[next(W.cams)] and W.cams[next(W.cams)].pos
  -- two quick selections: the first becomes stale, only the last one stays
  local a = nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  run(20)
  local b = nui('garage:preview', { app = 'garage', plate = 'NZ 005' })
  run(1200)
  check(a() and a().ok and a().data.shown == false and a().data.stale == true, 'superseded request reports stale')
  check(b() and b().data.shown == true, 'last selection shown')
  local e, en = onlyVehicle()
  check(e ~= nil and e ~= first and en.hash == joaat('bus'), 'only the new vehicle exists')
  check(not W.entities[first], 'old vehicle deleted')
  local cam = W.cams[next(W.cams)]
  check(liveCams() == 1, 'one camera reused')
  check(cam and camBefore and (math.abs(cam.pos.x - camBefore.x) + math.abs(cam.pos.y - camBefore.y)) > 1.0, 'camera re-framed for the bigger model')
  -- rect change re-frames immediately
  local p0 = cam.pos
  nui('garage:previewRect', { x = 420, y = 128, w = 560, h = 110, vw = 1280, vh = 720, dpr = 1 })
  run(50)
  check(cam.pos.x ~= p0.x or cam.pos.y ~= p0.y or cam.pos.z ~= p0.z, 'rect update moves the camera')
  -- spawner vehicle: no server data needed
  local awaitsBefore = #W.awaits
  local s = nui('garage:preview', { app = 'garage', index = 2 })
  run(800)
  check(s() and s().data.shown == true, 'spawner vehicle shown')
  check(#W.awaits == awaitsBefore, 'spawner preview asks the server nothing')
  check(W.mods[onlyVehicle()] == nil, 'spawner entry without livery / extras: no mods applied')
  s = nui('garage:preview', { app = 'garage', index = 3 })
  run(800)
  local se = onlyVehicle()
  local m = se and W.mods[se]
  check(s() and s().data.shown == true and m and m.livery == 2 and m.extras and m.extras['1'] == true and m.maxMods == true,
    'spawner livery / extras / max mods applied to the preview')
  -- nothing selected: preview stops
  local n = nui('garage:preview', { app = 'garage' })
  run(100)
  check(n() and n().data.shown == false and #liveVehicles() == 0 and W.render == false, 'empty selection stops the preview')
end)

scenario('back to the shown car while a swap loads', function()
  openGarage()
  local a0 = nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(800)
  local first = onlyVehicle()
  check(a0() and a0().data.shown == true and first ~= nil, 'first car shown')
  -- B is still asking the server / loading its model when A is selected again
  local b = nui('garage:preview', { app = 'garage', plate = 'NZ 005' })
  run(60)
  local a = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(1500)
  check(a() and a().data.shown == true, 'back to A answers shown')
  check(b() and b().data.shown == false and b().data.stale == true, 'the swap to B is cancelled (stale)')
  local e, en = onlyVehicle()
  check(#liveVehicles() == 1, 'exactly one vehicle')
  check(e == first and en and en.hash == joaat('sultan'), 'the remaining vehicle is A, not B')
  check(en and en.alpha == 255, 'A ends at full alpha')
  -- same, but A is selected again while B already fades A out
  b = nui('garage:preview', { app = 'garage', plate = 'NZ 005' })
  run(160) -- B's data is cached now: model 60 ms, then A fades out for 150 ms
  check(W.entities[first] and W.entities[first].alpha < 255, 'A is fading out for B')
  a = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(1500)
  e, en = onlyVehicle()
  check(b() and b().data.stale == true and a() and a().data.shown == true, 'fade-out swap cancelled')
  check(e == first and en and en.alpha == 255, 'A fades back in and stays')
  check((W.released[joaat('bus')] or 0) == 1, 'the model the cancelled swap loaded is released again')
  check((W.released[joaat('sultan')] or 0) == 1, 'the model on show is not released (only once, after its spawn)')
  -- and once more while B's model is still loading (data cached: stale right after the load)
  b = nui('garage:preview', { app = 'garage', plate = 'NZ 005' })
  run(30)
  a = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(1000)
  e, en = onlyVehicle()
  check(b() and b().data.stale == true and e == first and en.alpha == 255, 'cancelled during the model load')
  check((W.released[joaat('bus')] or 0) == 2, 'model released after a stale load')
  check((W.released[joaat('sultan')] or 0) == 1, 'model on show still not released')
end)

scenario('swap within the first render delay', function()
  openGarage()
  nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  run(800)
  nui('garage:preview', { app = 'garage' }) -- stop: the next car starts a new camera session
  run(50)
  check(#liveVehicles() == 0, 'stopped')
  -- both cached: A spawns after its model load (60 ms), B starts fading A out 20 ms later,
  -- before A's delayed render switch (100 ms) runs
  nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(65)
  local first = onlyVehicle()
  check(first ~= nil, 'A spawned (camera switch pending)')
  local b = nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  run(1000)
  check(b() and b().data.shown == true, 'B shown')
  local _, en = onlyVehicle()
  check(en and en.hash == joaat('bati') and en.alpha == 255, 'B on show at full alpha')
  check(W.deletedAlpha[first] ~= nil and W.deletedAlpha[first] < 255, 'A faded out (no pop at full alpha)')
  check(W.render == true, 'camera rendering')
end)

scenario('fallbacks', function()
  openGarage()
  -- unknown model
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 404', rect = RECT })
  run(800)
  check(r() and r().data.shown == false and #liveVehicles() == 0 and W.render == false, 'unknown model -> image fallback, nothing spawned')
  -- server refuses
  W.serverFail['nz:garage:preview'] = 'You do not have access to this vehicle'
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  run(600)
  check(r() and r().data.shown == false and W.render == false, 'refused server data -> image fallback')
  W.serverFail['nz:garage:preview'] = nil
  -- a plate that is not in the menu
  r = nui('garage:preview', { app = 'garage', plate = 'XX 999' })
  run(300)
  check(r() and r().data.shown == false, 'plate not in the menu is refused')
  -- bad payloads
  for _, p in ipairs({ {}, { plate = 12 }, { index = 'x' }, { app = 'admin', plate = 'NZ 001' }, { rect = { x = 'a' } } }) do
    r = nui('garage:preview', p)
    run(200)
    check(r() and r().ok == true and r().data.shown == false, 'bad payload answered with shown = false')
  end
end)

scenario('impound', function()
  W.nuiOpen.impound = true
  local saved = NZ.NUI.await
  NZ.NUI.await = function(name, payload)
    if name == 'nz:impound:open' then
      return { ok = true, data = { impound = { id = 3 }, vehicles = { { plate = 'IMP 9', hash = joaat('dinghy') } } } }
    end
    return saved(name, payload)
  end
  NZ.Garage.locationView = function() return { id = 3, kind = 'impound' } end
  addThread(function() NZ.ImpoundClient.open(3) end)
  run(100)
  NZ.NUI.await = saved
  local r = nui('garage:preview', { app = 'impound', plate = 'IMP 9', rect = RECT })
  run(800)
  check(r() and r().data.shown == true, 'impound vehicle shown')
  check(W.awaits[#W.awaits].name == 'nz:impound:preview', 'impound uses its own server callback')
  -- the garage app is not open: a garage request does nothing
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(300)
  check(r() and r().data.shown == false, 'closed app gets no preview')
  r = nui('garage:preview', { app = 'impound', plate = 'IMP 9' })
  run(800)
  NZ.NUI.close('impound')
  check(#liveVehicles() == 0 and W.render == false, 'impound close cleans up')
end)

scenario('death and close detection', function()
  openGarage()
  nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(600)
  check(#liveVehicles() == 1, 'shown before dying')
  W.dead = true
  run(600)
  check(#liveVehicles() == 0 and liveCams() == 0 and W.render == false, 'death ends the preview')
  local told = false
  for _, m in ipairs(W.sent) do
    if m.action == 'update' and m.data.app == 'garage' and type(m.data.data.previewStopped) == 'number' then told = true end
  end
  check(told, 'interface told (previewStopped) so the stage shows the image again')
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(600)
  check(r() and r().data.shown == false and #liveVehicles() == 0, 'no preview while dead')
  W.dead = false
  -- the menu closed without the hook (e.g. another resource closed NUI): the loop notices
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(600)
  check(#liveVehicles() == 1, 'shown again after revive')
  W.nuiOpen.garage = nil
  run(600)
  check(#liveVehicles() == 0 and W.render == false, 'render loop stops when the app is no longer open')
end)

scenario('setting off and resource stop', function()
  openGarage()
  W.settings.interface = { vehiclePreview = false }
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(600)
  check(r() and r().data.shown == false and r().data.disabled == true and #liveVehicles() == 0, 'setting off -> disabled, nothing spawned')
  W.settings.interface = {}
  env.Config.Preview = { studio = { x = -75.0, y = -819.0, z = 326.0, w = 0.0 } }
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(600)
  local _, en = onlyVehicle()
  check(en and math.abs(en.x + 75.0) < 1e-6 and math.abs(en.z - 326.0) < 1e-6, 'configured studio spot used')
  check(W.focus == true, 'streaming focus moved to a configured studio')
  for _, fn in ipairs(env.__handlers.onResourceStop or {}) do fn('nayzeee-garages') end
  check(#liveVehicles() == 0 and liveCams() == 0 and W.render == false and W.focus == false, 'resource stop cleans everything')
  env.Config.Preview = nil
end)

scenario('rate limited while browsing', function()
  openGarage()
  nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(600)
  check(#liveVehicles() == 1 and W.render == true, 'first vehicle shown')
  local offsBefore = 0
  for _, c in ipairs(W.renderCalls) do if not c.on then offsBefore = offsBefore + 1 end end
  -- next key press 200 ms later: the server's rate limit refuses the first ask
  run(200)
  W.serverRateOnce['nz:garage:preview'] = true
  local asked = #W.awaits
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  local sawStop = false
  for _ = 1, 60 do
    run(20)
    if W.render ~= true then sawStop = true end
  end
  local offs = 0
  for _, c in ipairs(W.renderCalls) do if not c.on then offs = offs + 1 end end
  check(r() and r().data.shown == true, 'rate-limited request retried and shown')
  check(#W.awaits == asked + 2, 'asked exactly twice (one retry)')
  check(not sawStop and offs == offsBefore, 'camera never dropped while retrying (no flicker to the image)')
  local stopped = false
  for _, msg in ipairs(W.sent) do
    if msg.action == 'update' and type(msg.data.data) == 'table' and msg.data.data.previewStopped then stopped = true end
  end
  check(not stopped, 'interface not told to fall back')
  local _, en = onlyVehicle()
  check(en and en.hash == joaat('bati'), 'the new vehicle is the one on screen')
  -- rate limited twice in a row: gives up (image), no endless loop
  W.serverFail['nz:garage:preview'] = env.L('Please wait a moment before trying again')
  asked = #W.awaits
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 005' })
  run(1200)
  check(r() and r().data.shown == false and #W.awaits == asked + 2, 'second refusal ends the attempt')
  W.serverFail['nz:garage:preview'] = nil
end)

scenario('server callback never answers', function()
  openGarage()
  W.serverHang['nz:garage:preview'] = true
  local r = nui('garage:preview', { app = 'garage', plate = 'NZ 005', rect = RECT })
  run(5000)
  check(r() and r().data.shown == false and #liveVehicles() == 0 and W.render == false, 'hanging server callback times out to the image')
  -- one slow reply does not disable the preview: asked again
  local asked = #W.awaits
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 002' })
  run(5000)
  check(#W.awaits == asked + 1, 'a single timeout does not mark the callback unavailable')
  check(r() and r().data.shown == false, 'second timeout -> image')
  asked = #W.awaits
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001' })
  run(300)
  check(r() and r().data.shown == false and #W.awaits == asked, 'two timeouts: the callback is not asked again this menu session')
  -- spawner vehicles need no server data: still previewed
  r = nui('garage:preview', { app = 'garage', index = 2 })
  run(800)
  check(r() and r().data.shown == true, 'spawner preview still works')
  -- next menu session tries again (server answers now)
  NZ.NUI.close('garage')
  W.serverHang['nz:garage:preview'] = nil
  openGarage()
  r = nui('garage:preview', { app = 'garage', plate = 'NZ 001', rect = RECT })
  run(800)
  check(r() and r().data.shown == true, 'menu reopened: the server callback is asked again and the car shown')
end)

---------------------------------------------------------------------------------------

for _, e in ipairs(runtimeErrors) do failures[#failures + 1] = 'runtime: ' .. e end
if #failures > 0 then
  print(('preview: %d / %d checks FAILED'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  ' .. f) end
  os.exit(1)
end
print(('preview: all %d checks passed'):format(checks))
