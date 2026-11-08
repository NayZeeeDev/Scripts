--[[
  Headless test for garage zones (docs/V2_CHANGES.md §F). No FiveM needed.

  server: loads shared/init.lua, shared/utils.lua, server/locations.lua and server/access.lua in
  a stubbed server runtime and checks the zone validation (corner count, duplicate corners,
  self-intersection, area / span / height limits, distance to the open interaction), normalize /
  save / load / clientView, point-in-polygon with margins and height range (convex and concave),
  and the server proximity checks with the SERVER ped position: Access.inZone,
  Access.nearLocation and Access.requireSession accept a player anywhere inside the zone and
  refuse one outside it or above / below its height range.
  client: loads client/points.lua and client/placement.lua in a stubbed client runtime and
  checks that a zone location creates an ox_lib poly zone (no store circles), that the prompt
  offers "Open garage" on foot and "Store vehicle" to a driver anywhere inside the polygon and
  nothing outside, the target-mode rule, client / server containment agreement on random
  points, and the in-world zone tool end to end with scripted controls and raycasts (add,
  refused crossing edge, undo, close on corner #1, height with Scroll / Ctrl + Scroll, save,
  cancel, refused shape far from the open interaction).

  Usage (from the resource root):  lua5.4 tools/smoke/zones.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

---------------------------------------------------------------------------------------
-- Shared stubs
---------------------------------------------------------------------------------------

local vmeta = {}
vmeta.__index = vmeta
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }, vmeta) end
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = (a.z or 0) + (b.z or 0) }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + (a.z or 0) ^ 2) end
function vector3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vmeta) end
function vector4(x, y, z, w) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 }, vmeta) end
vec3 = vector3

local dk = require('dkjson')
json = { encode = function(v) return dk.encode(v) end, decode = function(s) return (dk.decode(s)) end }

local warnings = {}
local clock = 0
function GetGameTimer() return clock end
function GetCurrentResourceName() return 'nayzeee-garages' end

local function freshLib()
  return {
    print = {
      warn = function(msg) warnings[#warnings + 1] = tostring(msg) end,
      error = function(msg) failures[#failures + 1] = 'lib.print.error: ' .. tostring(msg) end,
      info = function() end,
      debug = function() end,
    },
  }
end

local function load(path)
  local chunk, err = loadfile(path)
  if not chunk then error(err) end
  chunk()
end

---------------------------------------------------------------------------------------
-- Server
---------------------------------------------------------------------------------------

local serverContains

do
  function IsDuplicityVersion() return true end
  lib = freshLib()
  lib.callback = { register = function() end }
  Config = { Locale = 'en', Interaction = { openRadius = 2.0, storeRadius = 4.0 }, Peds = {} }
  local triggered = {}
  function TriggerClientEvent(name, target) triggered[#triggered + 1] = { name = name, target = target } end
  function GetPlayers() return { '1' } end
  function SetTimeout(_, fn) fn() end
  function IsPlayerAceAllowed() return false end

  -- ped positions by source (server side: GetEntityCoords(GetPlayerPed(src)))
  local peds = { [1] = vector3(0, 0, 0) }
  function GetPlayerPed(src) return peds[tonumber(src)] and (1000 + tonumber(src)) or 0 end
  function GetEntityCoords(ped) return peds[ped - 1000] end

  load('shared/init.lua')
  load('shared/utils.lua')

  local rows, nextId = {}, 1
  NZ.DB.locations = {
    all = function() return rows end,
    insert = function(kind, name, enabled, data)
      local id = nextId
      nextId = nextId + 1
      rows[#rows + 1] = { id = id, kind = kind, name = name, enabled = enabled, data = json.encode(data) }
      return id
    end,
    update = function() return true end,
    delete = function() return true end,
  }
  NZ.DB.countInGarage = function() return 0 end
  NZ.Settings.get = function(_, default) return default end
  NZ.Settings.all = function() return {} end
  NZ.Logs.add = function() end
  NZ.Interiors.get = function() return nil end
  NZ.Bridge.getIdentifier = function() return 'CID1' end

  load('server/locations.lua')
  load('server/access.lua')
  local Locations, Access = NZ.Locations, NZ.Access
  serverContains = Locations.zoneContains

  local open = { { coords = { x = 0.0, y = 0.0, z = 30.0 }, radius = 2.0 } }
  -- 40 × 30 m rectangle, the open point at a corner
  local rect = { { x = 0, y = 0 }, { x = 40, y = 0 }, { x = 40, y = 30 }, { x = 0, y = 30 } }

  local z, err = Locations.validateZone({ points = rect, minZ = 28, maxZ = 36 }, open)
  check(z and not err, 'valid rectangle accepted: ' .. tostring(err))
  check(z and #z.points == 4 and z.minZ == 28 and z.maxZ == 36, 'rectangle kept as given')

  -- duplicates merged (consecutive and closing), rounding to 2 decimals, vectors / arrays accepted
  z = Locations.validateZone({ points = {
    { x = 0.001, y = 0.004 }, { x = 0.2, y = 0.1 }, vector3(40, 0, 5), { 40, 30 }, { x = 0, y = 30 }, { x = 0.1, y = 0.1 },
  }, minZ = 28, maxZ = 36 }, open)
  check(z and #z.points == 4, 'duplicate corners merged (' .. tostring(z and #z.points) .. ')')
  check(z and z.points[1].x == 0 and z.points[1].y == 0, 'corners rounded to 2 decimals')

  -- empty values mean "no zone"
  for label, raw in pairs({ ['nil'] = nil, ['false'] = false, ['{}'] = {}, ['no points'] = { points = {} } }) do
    local zz, e = Locations.validateZone(raw, open)
    check(zz == nil and e == nil, 'empty zone (' .. label .. ') is no zone')
  end
  local _, e1 = Locations.validateZone('square', open)
  check(e1 ~= nil, 'non-table zone refused')

  local function refused(raw, pattern, label, openPoints)
    local zz, e = Locations.validateZone(raw, openPoints or open)
    check(zz == nil and type(e) == 'string' and e:find(pattern, 1, true) ~= nil,
      label .. ' refused with "' .. pattern .. '" (got ' .. tostring(e) .. ')')
  end
  refused({ points = { { x = 0, y = 0 }, { x = 10, y = 0 } } }, 'at least 3', 'two corners')
  local many = {}
  for i = 1, 41 do
    local a = i / 41 * math.pi * 2
    many[i] = { x = math.cos(a) * 30, y = math.sin(a) * 30 }
  end
  refused({ points = many, minZ = 28, maxZ = 36 }, 'at most 40', '41 corners')
  refused({ points = { { x = 0, y = 0 }, { x = 20, y = 20 }, { x = 20, y = 0 }, { x = 0, y = 20 } }, minZ = 28, maxZ = 36 },
    'cross each other', 'bow tie')
  refused({ points = { { x = 0, y = 0 }, { x = 20, y = 0 }, { x = 10, y = 0 }, { x = 10, y = 10 } }, minZ = 28, maxZ = 36 },
    'cross each other', 'edge folding back on itself')
  refused({ points = { { x = 0, y = 0 }, { x = 3, y = 0 }, { x = 3, y = 3 } }, minZ = 28, maxZ = 36 }, 'too small', '4.5 m² triangle')
  refused({ points = { { x = 0, y = 0 }, { x = 260, y = 0 }, { x = 260, y = 20 } }, minZ = 28, maxZ = 36 }, 'across', '260 m span')
  local round = {}
  for i = 1, 40 do
    local a = i / 40 * math.pi * 2
    round[i] = { x = math.cos(a) * 120, y = math.sin(a) * 120 }
  end
  refused({ points = round, minZ = 28, maxZ = 36 }, 'too large', '45 000 m² disc')
  refused({ points = rect, minZ = 30, maxZ = 31 }, 'at least 2 m', '1 m high')
  refused({ points = rect, minZ = 0, maxZ = 150 }, 'at most 100 m', '150 m high')
  refused({ points = rect, minZ = 28, maxZ = 36 }, 'open interaction', 'no open interaction', {})
  refused({ points = rect, minZ = 28, maxZ = 36 }, 'at most 30 m', 'open point 50 m away',
    { { coords = { x = 90.0, y = 15.0, z = 30.0 }, radius = 2.0 } })
  refused({ points = rect, minZ = 28, maxZ = 36 }, 'at most 30 m', 'open point 40 m above',
    { { coords = { x = 10.0, y = 10.0, z = 76.0 }, radius = 2.0 } })
  z = Locations.validateZone({ points = rect, minZ = 28, maxZ = 36 }, { { coords = { x = 60.0, y = 15.0, z = 30.0 }, radius = 2.0 } })
  check(z ~= nil, 'open point 20 m outside the zone accepted')

  -- default height range from the open point
  z = Locations.validateZone({ points = rect }, open)
  check(z and z.minZ == 28 and z.maxZ == 36, 'missing height range = open z -2 .. +6')

  -- containment
  local zone = { points = rect, minZ = 28, maxZ = 36 }
  check(Locations.zoneContains(zone, vector3(20, 15, 30)), 'centre inside')
  check(not Locations.zoneContains(zone, vector3(42, 15, 30)), '2 m outside an edge is outside')
  check(Locations.zoneContains(zone, vector3(42, 15, 30), 3.0), '2 m outside inside the 3 m margin')
  check(not Locations.zoneContains(zone, vector3(20, 15, 40)), 'above the ceiling is outside')
  check(Locations.zoneContains(zone, vector3(20, 15, 37), 0, 2.0), '1 m above the ceiling within the z margin')
  local u = { points = { { x = 0, y = 0 }, { x = 30, y = 0 }, { x = 30, y = 30 }, { x = 20, y = 30 }, { x = 20, y = 10 },
    { x = 10, y = 10 }, { x = 10, y = 30 }, { x = 0, y = 30 } }, minZ = 0, maxZ = 10 }
  check(not Locations.zoneContains(u, vector3(15, 20, 5)), 'concave notch is outside')
  check(Locations.zoneContains(u, vector3(25, 20, 5)), 'concave arm is inside')
  check(math.abs(Locations.zoneArea(u) - 700) < 1e-6, 'concave area 700 m²')

  -- normalize / save / clientView / load
  local raw = { kind = 'garage', name = 'Zone lot', openPoints = open, spawnPoints = { { x = 5, y = 5, z = 30, w = 0 } },
    zone = { points = rect, minZ = 28, maxZ = 36 } }
  local loc, nerr, zerr = Locations.normalize(raw)
  check(loc and loc.zone and not nerr and not zerr, 'normalize keeps a valid zone')
  local bad = { kind = 'garage', name = 'Bad lot', openPoints = open,
    zone = { points = { { x = 0, y = 0 }, { x = 20, y = 20 }, { x = 20, y = 0 }, { x = 0, y = 20 } }, minZ = 28, maxZ = 36 } }
  loc, nerr, zerr = Locations.normalize(bad)
  check(loc and loc.zone == nil and nerr == nil and type(zerr) == 'string', 'normalize drops an invalid zone and reports it')
  local saved, serr = Locations.save(bad, 1)
  check(saved == nil and type(serr) == 'string' and serr:find('cross', 1, true), 'save refuses an invalid zone')
  saved, serr = Locations.save(raw, 1)
  check(saved and saved.zone and #saved.zone.points == 4, 'save stores a valid zone: ' .. tostring(serr))
  local view = Locations.clientView(Locations.get(saved.id))
  check(view and view.zone and view.zone.minZ == 28 and #view.zone.points == 4, 'clientView carries the zone')
  local plain = Locations.save({ kind = 'garage', name = 'Plain', openPoints = open, zone = {} }, 1)
  check(plain and plain.zone == nil, 'zone {} saves a point-based location')
  check(Locations.clientView(Locations.get(plain.id)).zone == nil, 'point-based client view has no zone')

  -- a stored zone that became invalid: the location loads, the zone is ignored with a warning
  rows[#rows + 1] = { id = 99, kind = 'garage', name = 'Legacy', enabled = true, data = json.encode({
    openPoints = open, zone = { points = { { x = 0, y = 0 }, { x = 1, y = 0 } }, minZ = 0, maxZ = 5 } }) }
  warnings = {}
  Locations.load()
  check(Locations.get(99) and Locations.get(99).zone == nil, 'legacy row loads without its broken zone')
  local warned = false
  for _, w in ipairs(warnings) do if w:find('garage zone ignored', 1, true) then warned = true end end
  check(warned, 'broken stored zone logged')
  check(Locations.get(saved.id) and Locations.get(saved.id).zone ~= nil, 'valid zone survives a reload')

  -- server proximity with the server ped position
  local stored = Locations.get(saved.id)
  NZ.Settings.get = function(path, default) if path == 'garages.maxDistance' then return 25.0 end return default end
  peds[1] = vector3(38, 28, 30)      -- far corner: 47 m from the open point, inside the zone
  check(not Access.isNear(1, stored.openPoints, 25.0), 'far corner is not near the open point')
  check(Access.inZone(1, stored), 'far corner is inside the zone')
  check(Access.nearLocation(1, stored, 25.0), 'nearLocation accepts the far corner')
  peds[1] = vector3(41.5, 28, 30)    -- 1.5 m outside an edge: server tolerance
  check(Access.inZone(1, stored), '1.5 m outside within the server margin')
  peds[1] = vector3(60, 28, 30)      -- 20 m outside
  check(not Access.inZone(1, stored) and not Access.nearLocation(1, stored, 25.0), '20 m outside refused')
  peds[1] = vector3(20, 15, 45)      -- above the zone
  check(not Access.inZone(1, stored), 'above the height range refused')
  peds[1] = vector3(1, 1, 30)
  check(Access.nearLocation(1, Locations.get(plain.id), 25.0), 'point-based location: open point still works')
  peds[1] = vector3(38, 28, 30)
  check(not Access.nearLocation(1, Locations.get(plain.id), 25.0), 'point-based location: no zone shortcut')
  check(not Access.inZone(1, nil) and not Access.inZone(nil, stored), 'inZone guards bad input')

  NZ.Interiors.playerInstance = nil
  Access.openSession(1, 'L' .. stored.id, stored)
  peds[1] = vector3(38, 28, 30)
  local session, rerr = Access.requireSession(1, 25.0)
  check(session ~= nil, 'requireSession accepts the player inside the zone: ' .. tostring(rerr))
  peds[1] = vector3(80, 80, 30)
  session, rerr = Access.requireSession(1, 25.0)
  check(session == nil and rerr ~= nil, 'requireSession refuses the player outside')
end

---------------------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------------------

do
  NZ, Locales = nil, nil
  function IsDuplicityVersion() return false end
  lib = freshLib()
  Config = { Locale = 'en', Interaction = { openRadius = 2.0, storeRadius = 4.0, drawMarkers = true, markerDistance = 15.0 },
    Keys = { interact = 'E' }, Peds = {}, DefaultSettings = { interface = { interaction = 'prompt' }, garages = { showBlips = true } } }

  -- threads: resumed by tick()
  local threads = {}
  function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
  local frameHook = nil
  function Wait(ms)
    if frameHook then frameHook(ms) end
    if coroutine.isyieldable() and coroutine.running() and not frameHook then coroutine.yield(ms) end
  end
  local function tick()
    for i = #threads, 1, -1 do
      local co = threads[i]
      if coroutine.status(co) == 'suspended' then
        local ok, e = coroutine.resume(co)
        if not ok then failures[#failures + 1] = 'client thread: ' .. tostring(e) end
      end
      if coroutine.status(co) == 'dead' then table.remove(threads, i) end
    end
  end
  function SetTimeout() end
  function RegisterNetEvent() end
  function AddEventHandler() end
  function RegisterNUICallback() end

  -- world
  local me = { pos = vector3(0, 0, 31), vehicle = 0 }
  cache = { ped = 101 }
  function PlayerPedId() return 101 end
  function GetEntityCoords(e) if e == 101 then return me.pos end return me.pos end
  function GetEntityHeading() return 0.0 end
  function GetVehiclePedIsIn(_, last) if last then return me.vehicle end return me.vehicle end
  function GetPedInVehicleSeat(veh, seat) if veh ~= 0 and seat == -1 and me.driver then return 101 end return 0 end
  function GetVehicleClass() return 0 end
  function GetEntityModel() return 1 end
  function IsPauseMenuActive() return false end
  function IsEntityDead() return false end
  function IsPedFatallyInjured() return false end
  function IsPedCuffed() return false end
  function IsEntityAttachedToAnyPed() return false end
  function DoesBlipExist() return false end
  function GetGroundZFor_3dCoord() return true, 30.0 end
  for _, name in ipairs({ 'AddBlipForCoord', 'SetBlipSprite', 'SetBlipColour', 'SetBlipScale', 'SetBlipDisplay',
    'SetBlipAsShortRange', 'BeginTextCommandSetBlipName', 'AddTextComponentSubstringPlayerName', 'EndTextCommandSetBlipName',
    'DrawMarker', 'DrawLine', 'DrawPoly', 'PlaySoundFrontend', 'DisableControlAction', 'SetTextScale', 'SetTextFont',
    'SetTextProportional', 'SetTextColour', 'SetTextOutline', 'SetTextCentre', 'BeginTextCommandDisplayText',
    'EndTextCommandDisplayText', 'SetCamCoord', 'SetCamRot', 'SetCamFov', 'RenderScriptCams', 'DestroyCam',
    'SetFocusPosAndVel', 'ClearFocus', 'RemoveBlip' }) do
    _G[name] = function() return 0 end
  end
  function GetScreenCoordFromWorldCoord() return false, 0, 0 end
  function GetFrameTime() return 1 / 60 end

  local zonesMade, pointsMade, prompts = {}, {}, {}
  lib.points = { new = function(o) pointsMade[#pointsMade + 1] = o return setmetatable({ remove = function() end }, { __index = o }) end }
  lib.zones = { poly = function(o) zonesMade[#zonesMade + 1] = o return setmetatable({ remove = function() end }, { __index = o }) end }
  lib.addKeybind = function() return {} end
  lib.getClosestVehicle = function() return nil end

  load('shared/init.lua')
  load('shared/utils.lua')
  NZ.NUI.prompt = function(label) prompts[#prompts + 1] = label or false end
  local notes, hints = {}, {}
  NZ.NUI.notify = function(kind, msg) notes[#notes + 1] = { kind = kind, msg = msg } end
  NZ.NUI.hint = function(h) hints[#hints + 1] = h or false end
  NZ.NUI.isOpen = function() return false end
  NZ.Target.available = function() return false end
  NZ.Garage.store = function() end

  load('client/points.lua')
  load('client/placement.lua')
  local Points, Placement = NZ.Points, NZ.Placement

  local rect = { { x = 0, y = 0 }, { x = 40, y = 0 }, { x = 40, y = 30 }, { x = 0, y = 30 } }
  NZ.State.settings = { interface = { interaction = 'prompt' }, garages = { showBlips = false } }
  NZ.State.locations = {
    [1] = { id = 1, kind = 'garage', name = 'Zone lot', vehicleType = 'car', enabled = true,
      openPoints = { { coords = { x = 0.0, y = 0.0, z = 31.0 }, radius = 2.0 } }, storePoints = {}, useOpenForStore = true,
      spawnPoints = { { x = 5, y = 5, z = 30, w = 0 } }, blip = { enabled = false }, access = { mode = 'quick' },
      zone = { points = rect, minZ = 28, maxZ = 36 } },
  }
  NZ.State.ready = true
  Points.rebuild()
  tick()

  check(#zonesMade == 1, 'one ox_lib poly zone for the zone location (' .. #zonesMade .. ')')
  local zo = zonesMade[1]
  check(zo and #zo.points == 4 and zo.points[1].z == 32, 'poly zone corners at the middle of the height range')
  check(zo and zo.thickness >= 8, 'poly zone thickness covers the height range')
  local storeCircles = 0
  for _, p in ipairs(pointsMade) do if p.rec and p.rec.store then storeCircles = storeCircles + 1 end end
  check(storeCircles == 0, 'no store circle for a zone location')
  check(Points.inZone(NZ.State.locations[1], vector3(38, 28, 30)), 'Points.inZone: far corner inside')
  check(not Points.inZone(NZ.State.locations[1], vector3(45, 28, 30)), 'Points.inZone: outside')

  -- on foot, far corner of the zone (47 m from the open point): open prompt
  me.pos, me.vehicle, me.driver = vector3(38, 28, 30), 0, false
  zo.onEnter(setmetatable({}, { __index = zo }))
  tick()
  check(prompts[#prompts] == 'Open garage', 'on foot in the zone: "Open garage" (got ' .. tostring(prompts[#prompts]) .. ')')
  local cur = Points.current()
  check(cur and cur.action == 'garage' and cur.location.id == 1, 'Points.current: garage action')
  -- driving inside: store anywhere
  me.vehicle, me.driver = 555, true
  tick()
  check(prompts[#prompts] == 'Store vehicle', 'driver in the zone: "Store vehicle" (got ' .. tostring(prompts[#prompts]) .. ')')
  -- outline ground heights: corners without collision yet are asked again every 2 s, the rest once
  do
    local zself = setmetatable({}, { __index = zo })
    local asked, streamed = {}, false
    local savedGround = GetGroundZFor_3dCoord
    GetGroundZFor_3dCoord = function(x)
      asked[#asked + 1] = x
      if x == 40 and not streamed then return false, 0.0 end
      return true, 30.0
    end
    local lines = {}
    local savedLine = DrawLine
    DrawLine = function(ax, ay, az) lines[#lines + 1] = { x = ax, y = ay, z = az } end
    zo.rec.groundZs = nil
    zo.inside(zself)
    check(#asked == 4, 'outline: 4 corners queried on the first frame (' .. #asked .. ')')
    asked = {}
    zo.inside(zself)
    check(#asked == 0, 'outline: no query on the next frame')
    clock = clock + 2100
    zo.inside(zself)
    check(#asked == 2 and asked[1] == 40 and asked[2] == 40, 'outline: only the 2 missing corners asked again after 2 s')
    streamed, asked = true, {}
    clock = clock + 2100
    lines = {}
    zo.inside(zself)
    local fixed = true
    for _, l in ipairs(lines) do if l.x == 40 and math.abs(l.z - 30.06) > 1e-6 and math.abs(l.z - 30.96) > 1e-6 then fixed = false end end
    check(#asked == 2 and fixed and #lines > 0, 'outline: corners get their real ground once streamed')
    asked = {}
    clock = clock + 5000
    zo.inside(zself)
    check(#asked == 0, 'outline: nothing asked again once every corner has a hit')
    GetGroundZFor_3dCoord, DrawLine = savedGround, savedLine
  end
  -- passenger: nothing
  me.driver = false
  tick()
  check(prompts[#prompts] == false, 'passenger: no prompt')
  -- driver outside the polygon (still within the ox zone loop): nothing
  me.driver, me.pos = true, vector3(45, 28, 30)
  tick()
  check(prompts[#prompts] == false, 'driver outside the polygon: no prompt')
  -- under the floor (tunnel below the lot)
  me.pos = vector3(20, 15, 20)
  tick()
  check(prompts[#prompts] == false, 'driver under the zone: no prompt')
  check(Points.nearestLocation(nil, 5.0) == nil, 'nearestLocation: nothing within 5 m from below')
  me.pos = vector3(20, 15, 30)
  check(Points.nearestLocation(nil, 1.0) and Points.nearestLocation(nil, 1.0).id == 1, 'nearestLocation: inside the zone = 0 m')
  zo.onExit(setmetatable({}, { __index = zo }))
  tick()

  -- client and server agree on random points (no margins)
  local zone = { points = rect, minZ = 28, maxZ = 36 }
  local seed = 7
  local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
  local agree = true
  for _ = 1, 500 do
    local p = vector3(rnd() * 60 - 10, rnd() * 50 - 10, 26 + rnd() * 12)
    if (serverContains(zone, p, 0, 1.0) == true) ~= Points.inZone({ zone = zone }, p) then agree = false end
  end
  check(agree, 'client and server containment agree on 500 random points')

  -- target mode: the zone gives no on-foot prompt (targets stay at the open point), drivers still park
  NZ.Target.available = function() return true end
  NZ.Target.addSphere = function() return true end
  NZ.Target.remove = function() end
  NZ.State.locations[1].interaction = { mode = 'target' }
  zonesMade = {}
  Points.rebuild()
  local zt = zonesMade[1]
  me.vehicle, me.driver, me.pos = 0, false, vector3(38, 28, 30)
  prompts = {}
  zt.onEnter(setmetatable({}, { __index = zt }))
  tick()
  check(prompts[#prompts] == nil or prompts[#prompts] == false, 'target mode: no on-foot prompt in the zone')
  me.vehicle, me.driver = 555, true
  tick()
  check(prompts[#prompts] == 'Store vehicle', 'target mode: drivers still get "Store vehicle"')
  zt.onExit(setmetatable({}, { __index = zt }))
  tick()
  NZ.State.locations[1].interaction = nil
  NZ.Target.available = function() return false end

  -- impound / for-sale zones: opened anywhere inside the zone (the server accepts the zone too)
  NZ.State.locations[1].kind = 'impound'
  zonesMade, pointsMade = {}, {}
  Points.rebuild()
  local impoundOpen = 0
  for _, p in ipairs(pointsMade) do if p.rec and p.rec.open and p.rec.openAction == 'impound' then impoundOpen = impoundOpen + 1 end end
  check(#zonesMade == 1, 'impound zone: the zone opens the impound (' .. #zonesMade .. ', ' .. impoundOpen .. ')')
  NZ.State.locations[1].kind = 'garage'

  -- point-based location: unchanged (store circle at the open point, no poly zone)
  zonesMade, pointsMade = {}, {}
  NZ.State.locations[1].zone = nil
  Points.rebuild()
  storeCircles = 0
  for _, p in ipairs(pointsMade) do if p.rec and p.rec.store then storeCircles = storeCircles + 1 end end
  check(#zonesMade == 0 and storeCircles == 1, 'point-based location keeps its store circle')

  -----------------------------------------------------------------------------------
  -- Zone tool, scripted
  -----------------------------------------------------------------------------------
  local frame = 0
  local script = {}         -- [frame] = { released = { id = true }, justPressed = {}, pressed = {} }
  local aim = nil           -- current raycast hit
  local function at(f) script[f] = script[f] or { released = {}, justPressed = {}, pressed = {} } return script[f] end
  function IsDisabledControlJustReleased(_, id) local s = script[frame] return s ~= nil and s.released[id] == true end
  function IsDisabledControlJustPressed(_, id) local s = script[frame] return s ~= nil and s.justPressed[id] == true end
  function IsDisabledControlPressed(_, id) local s = script[frame] return s ~= nil and s.pressed[id] == true end
  function GetDisabledControlNormal() return 0.0 end
  function GetGameplayCamCoord() return vector3(0, 0, 40) end
  function GetGameplayCamRot() return vector3(-60, 0, 0) end
  function GetGameplayCamFov() return 50.0 end
  function CreateCam() return 77 end
  function StartShapeTestLosProbe() return 1 end
  function GetShapeTestResult()
    if aim then return 2, true, vector3(aim.x, aim.y, aim.z), vector3(0, 0, 1), 0 end
    return 2, false, vector3(0, 0, 0), vector3(0, 0, 0), 0
  end

  -- every step: aim for 4 frames, then the key on the 5th
  local steps
  local function build(list)
    script, steps = {}, list
    local f = 30   -- after the 300 ms grace
    for _, st in ipairs(list) do
      st.from = f
      for k = f, f + 4 do at(k) end
      local s = at(f + 4)
      if st.key then s.released[st.key] = true end
      if st.scroll then s.justPressed[st.scroll] = true end
      if st.ctrl then s.pressed[36] = true end
      if st.shift then s.pressed[21] = true end
      f = f + 5
    end
    return f
  end
  local lastFrame = 0
  frameHook = function()
    frame = frame + 1
    clock = clock + 16
    for _, st in ipairs(steps) do
      if frame >= st.from and frame < st.from + 5 then aim = st.aim end
      if st.run and frame == st.from then st.run() end
    end
    if frame > lastFrame + 50 then error('zone tool did not finish') end
  end

  local E, X, ENTER, ESC, BACK = 38, 73, 191, 200, 194
  local SUP, SDOWN = 15, 14
  local function runTool(list, opts)
    frame, aim, notes = 0, nil, {}
    lastFrame = build(list)
    local res = Placement.zone(opts or {
      openPoints = { { coords = { x = 0.0, y = 0.0, z = 31.0 } } },
      spawnPoints = {},
    })
    return res
  end

  local result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { aim = { x = 40, y = 0, z = 30 }, key = E },
    { aim = { x = 40, y = 30, z = 31 }, key = E },
    { aim = { x = 20, y = -10, z = 30 }, key = E },   -- would cross edge 1-2: refused
    { aim = { x = 10, y = 40, z = 30 }, key = E },
    { aim = { x = 10, y = 40, z = 30 }, key = X },    -- undo it
    { aim = { x = 0, y = 30, z = 30 }, key = E },
    { aim = { x = 0.5, y = 0.5, z = 30 }, key = E },  -- on corner #1: closes the shape
    { scroll = SUP },                                 -- ceiling +0.25
    { scroll = SUP, shift = true },                   -- ceiling +1
    { scroll = SDOWN, ctrl = true },                  -- floor -0.25
    { key = ENTER },
  })
  check(type(result) == 'table', 'zone tool returns a zone')
  if type(result) == 'table' then
    check(#result.points == 4, 'four corners kept (crossing refused, undo applied): ' .. #result.points)
    check(result.points[4] and result.points[4].x == 0 and result.points[4].y == 30, 'undone corner replaced by (0, 30)')
    check(result.minZ == 28.75, 'floor: lowest corner 30 - 1 - 0.25 = 28.75 (got ' .. tostring(result.minZ) .. ')')
    check(result.maxZ == 37.25, 'ceiling: highest corner 31 + 5 + 1.25 = 37.25 (got ' .. tostring(result.maxZ) .. ')')
    check(result.points[1].z == nil, 'exported corners are x / y only')
  end
  local crossed = false
  for _, n in ipairs(notes) do if n.msg:find('cross', 1, true) then crossed = true end end
  check(crossed, 'crossing corner refused with a warning')
  check(hints[#hints] == false, 'hint hidden after the tool')
  check(not Placement.isActive(), 'tool inactive afterwards')

  -- Esc cancels
  result = runTool({ { aim = { x = 0, y = 0, z = 30 }, key = E }, { key = ESC } })
  check(result == nil, 'Esc cancels the zone tool')

  -- Backspace in the height step goes back to the corners; Enter with 2 corners is refused
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { aim = { x = 20, y = 0, z = 30 }, key = E },
    { key = ENTER },                                  -- only 2 corners: refused
    { aim = { x = 20, y = 20, z = 30 }, key = E },
    { key = ENTER },                                  -- height step
    { key = BACK },                                   -- back to corners
    {}, {}, {}, {},                                   -- the 300 ms grace after switching back
    { aim = { x = 0, y = 20, z = 30 }, key = E },
    { key = ENTER },
    { key = ENTER },
  })
  check(type(result) == 'table' and #result.points == 4, 'Backspace returns to the corners, then 4 corners saved')
  local tooFew = false
  for _, n in ipairs(notes) do if n.msg:find('at least 3', 1, true) then tooFew = true end end
  check(tooFew, 'closing two corners refused')

  -- a shape far from the open interaction cannot be closed
  result = runTool({
    { aim = { x = 100, y = 100, z = 30 }, key = E },
    { aim = { x = 120, y = 100, z = 30 }, key = E },
    { aim = { x = 120, y = 120, z = 30 }, key = E },
    { key = ENTER },
    { key = ESC },
  })
  local far = false
  for _, n in ipairs(notes) do if n.msg:find('at most 30 m', 1, true) then far = true end end
  check(result == nil and far, 'zone far from the open interaction refused when closing')

  -- the old zone is accepted as a reference and its height range reused when it fits
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { aim = { x = 30, y = 0, z = 30 }, key = E },
    { aim = { x = 30, y = 30, z = 30 }, key = E },
    { key = ENTER },
    { key = ENTER },
  }, { zone = { points = rect, minZ = 25, maxZ = 40 }, openPoints = { { coords = { x = 0.0, y = 0.0, z = 31.0 } } } })
  check(type(result) == 'table' and result.minZ == 25 and result.maxZ == 40, 'redraw keeps the old height range when it fits')

  -- concave shapes: the next corner replaces the closing edge, so a corner is never refused
  -- only because closing right there would cross (U / C / T drawn from any corner, both ways)
  local function drawShapeOf(corners, label)
    local list = {}
    for _, c in ipairs(corners) do list[#list + 1] = { aim = { x = c[1], y = c[2], z = 30 }, key = E } end
    list[#list + 1] = { key = ENTER }
    list[#list + 1] = { key = ENTER }
    local res = runTool(list)
    local refused = false
    for _, n in ipairs(notes) do if n.msg:find('cross', 1, true) then refused = true end end
    check(type(res) == 'table' and #res.points == #corners and not refused,
      label .. ': all ' .. #corners .. ' corners kept (' .. (type(res) == 'table' and #res.points or 'nil') .. ')')
  end
  local function rotations(shape, name)
    local n = #shape
    for start = 1, n do
      local fwd, rev = {}, {}
      for k = 0, n - 1 do
        fwd[#fwd + 1] = shape[(start - 1 + k) % n + 1]
        rev[#rev + 1] = shape[(start - 1 - k) % n + 1]
      end
      drawShapeOf(fwd, ('%s from corner %d'):format(name, start))
      drawShapeOf(rev, ('%s from corner %d, reversed'):format(name, start))
    end
  end
  local U = { { 0, 0 }, { 0, 10 }, { 3, 10 }, { 3, 3 }, { 7, 3 }, { 7, 10 }, { 10, 10 }, { 10, 0 } }
  local Cshape = { { 0, 0 }, { 10, 0 }, { 10, 3 }, { 3, 3 }, { 3, 7 }, { 10, 7 }, { 10, 10 }, { 0, 10 } }
  local T = { { 0, 7 }, { 0, 10 }, { 12, 10 }, { 12, 7 }, { 8, 7 }, { 8, 0 }, { 4, 0 }, { 4, 7 } }
  rotations(U, 'U shape')
  rotations(Cshape, 'C shape')
  rotations(T, 'T shape')

  -- a new edge that really crosses an earlier edge is still refused (U drawn, then a corner
  -- whose edge cuts through the left arm)
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { aim = { x = 0, y = 10, z = 30 }, key = E },
    { aim = { x = 3, y = 10, z = 30 }, key = E },
    { aim = { x = 3, y = 3, z = 30 }, key = E },
    { aim = { x = -4, y = 5, z = 30 }, key = E },     -- 3,3 -> -4,5 crosses edge 0,0-0,10
    { key = ESC },
  })
  local cut = false
  for _, n in ipairs(notes) do if n.msg:find('cross', 1, true) then cut = true end end
  check(result == nil and cut, 'a new edge through an earlier edge is refused')
  -- closing a shape whose closing edge crosses is refused by closeShape (corners kept, no save)
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { aim = { x = 0, y = 10, z = 30 }, key = E },
    { aim = { x = 3, y = 10, z = 30 }, key = E },
    { aim = { x = 3, y = 3, z = 30 }, key = E },
    { aim = { x = 7, y = 3, z = 30 }, key = E },
    { aim = { x = 7, y = 10, z = 30 }, key = E },     -- closing 7,10 -> 0,0 crosses 3,3-7,3
    { key = ENTER },
    { key = ESC },
  })
  local closeRefused = false
  for _, n in ipairs(notes) do if n.msg:find('edges of the garage zone cross', 1, true) then closeRefused = true end end
  check(result == nil and closeRefused, 'closing across an inner edge is refused when closing')

  -- death and teleport end the tool
  local deadNow = false
  IsEntityDead = function() return deadNow end
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { run = function() deadNow = true end },
    { key = ENTER },
  })
  local cancelled = false
  for _, n in ipairs(notes) do if n.msg:find('cancelled', 1, true) then cancelled = true end end
  check(result == nil and cancelled and not Placement.isActive(), 'dying ends the zone tool')
  deadNow = false
  IsEntityDead = function() return false end
  local home = me.pos
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { run = function() me.pos = vector3(home.x + 500, home.y, home.z) end },
    { key = ENTER },
  })
  cancelled = false
  for _, n in ipairs(notes) do if n.msg:find('cancelled', 1, true) then cancelled = true end end
  check(result == nil and cancelled, 'a teleport ends the zone tool')
  me.pos = home
  -- a long hitch (1 s frame, 60 m moved: falling / streaming) does not cancel a half-drawn zone
  result = runTool({
    { aim = { x = 0, y = 0, z = 30 }, key = E },
    { run = function() clock = clock + 1000 me.pos = vector3(home.x + 60, home.y, home.z) end },
    { key = ESC },
  })
  cancelled = false
  for _, n in ipairs(notes) do if n.msg:find('cancelled', 1, true) then cancelled = true end end
  check(result == nil and not cancelled, 'a 60 m move over a 1 s hitch does not end the zone tool')
  me.pos = home
  frameHook = nil
end

---------------------------------------------------------------------------------------

if #failures > 0 then
  print(('zones: %d / %d checks FAILED'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('zones: all %d checks passed'):format(checks))
