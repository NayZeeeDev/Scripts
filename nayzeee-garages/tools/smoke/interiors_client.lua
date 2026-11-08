--[[
  Headless test for garage interiors, client side (no FiveM needed): client/camera.lua and
  client/interior.lua in a stubbed client runtime.

    arrival ride curve (starts / ends exactly on its keys, even speed with a gentle top
    speed, no sudden turns) -> automatic ride of every profile with presets (unhurried
    length, 6-9 s) -> creator camera points -> presetsFrom derivation (the four CEO level 1
    garages map onto each other) -> vehicle card target (nearest, kept without flicker).

  Usage (from the resource root):  lua5.4 tools/smoke/interiors_client.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

-- Runtime stubs -----------------------------------------------------------------------
setmetatable(_ENV, {
  __index = function(_, k)
    if type(k) == 'string' and k:match('^[A-Z]') then return function() return nil end end
    return nil
  end,
})
function IsDuplicityVersion() return false end
function GetCurrentResourceName() return 'nayzeee-garages' end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, { __name = 'vector3' }) end
function vector4(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, { __name = 'vector4' }) end
function joaat(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
function CreateThread() end
function Wait() end
function AddEventHandler() end
function RegisterNetEvent() end
function GetGameTimer() return 0 end
exports = setmetatable({}, { __call = function() end })
json = { encode = function() return '{}' end, decode = function() return {} end }
lib = setmetatable({
  print = { info = function() end, warn = function() end, error = function(...) failures[#failures + 1] = 'lib.print.error: ' .. table.concat({ ... }, ' ') end },
}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local ok, err = xpcall(assert(load(src, '@' .. file, 't', _ENV)), debug.traceback)
  if not ok then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end

load_('config/config.lua')
load_('config/interiors.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
NZ.NUI.register = function() end
NZ.NUI.onClose = function() end
load_('client/camera.lua')
load_('client/interior.lua')
if #failures > 0 then
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
local Camera, Interior, Utils = NZ.Camera, NZ.Interior, NZ.Utils

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
local function angleDiff(a, b) return math.abs((a - b + 180) % 360 - 180) end

--- Walk a ride in `steps`: travelled distance per step, largest turn per step.
local function walk(keys, steps)
  local prevP, prevR = Camera.sampleKeys(keys, 0)
  local moves, maxTurn, total = {}, 0, 0
  for i = 1, steps do
    local p, r = Camera.sampleKeys(keys, i / steps)
    local d = dist(p, prevP)
    moves[i] = d
    total = total + d
    maxTurn = math.max(maxTurn, angleDiff(r.z, prevR.z), math.abs(r.x - prevR.x))
    prevP, prevR = p, r
  end
  return moves, total, maxTurn
end

-- 1. the curve itself -----------------------------------------------------------------
local keys = {
  { pos = { x = 0, y = 0, z = 3 }, look = { x = 0, y = 10, z = 0 }, fov = 46 },
  { pos = { x = 0, y = 8, z = 2 }, look = { x = 2, y = 20, z = 0 }, fov = 48 },
  { pos = { x = 1, y = 9, z = 2 }, look = { x = 5, y = 12, z = 1 }, fov = 50 },   -- close to the previous key
  { pos = { x = 6, y = 14, z = 1.5 }, look = { x = 6, y = 24, z = 1 }, fov = 50 },
}
local p0, r0, f0 = Camera.sampleKeys(keys, 0)
local p1, r1, f1 = Camera.sampleKeys(keys, 1)
check(dist(p0, keys[1].pos) < 1e-6 and dist(p1, keys[4].pos) < 1e-6, 'ride starts and ends exactly on its first / last key')
check(math.abs(f0 - 46) < 1e-6 and math.abs(f1 - 50) < 1e-6, 'fov follows the keys')
check(angleDiff(r1.z, 0) < 0.5 and r1.x < 0, 'last frame looks at the last look target (north, slightly down)')
local moves, total, maxTurn = walk(keys, 600)
local avg = total / #moves
check(moves[1] < avg * 0.05 and moves[#moves] < avg * 0.05, 'ride starts and ends at rest')
check(maxTurn < 2.5, ('no sudden turn (largest %.2f deg per 1/600 of the ride)'):format(maxTurn))
-- a dolly (the view moves with the camera): even speed, gentle top speed
local dolly = {}
for i, k in ipairs({ { 0, 0, 3 }, { 0, 9, 2.5 }, { 3, 13, 2 }, { 9, 15, 1.8 } }) do
  dolly[i] = { pos = { x = k[1], y = k[2], z = k[3] }, look = { x = k[1], y = k[2] + 10, z = 0 }, fov = 50 }
end
local dMoves, dTotal = walk(dolly, 600)
local dAvg, peak = dTotal / #dMoves, 0
for i = 1, #dMoves do peak = math.max(peak, dMoves[i]) end
check(peak / dAvg < 1.4, ('top speed stays gentle (%.2fx the average)'):format(peak / dAvg))
for i = 2, #moves - 1 do
  if math.abs(moves[i] - moves[i - 1]) > avg * 0.2 then
    check(false, ('speed jumps at step %d'):format(i))
    break
  end
end

-- 2. creator camera points --------------------------------------------------------------
local fromPoints = Camera.keysFromPoints({
  { coords = { x = 10, y = 0, z = 2 }, rot = { x = 0, y = 0, z = 90 }, fov = 40 },
  { coords = { x = 0, y = 0, z = 2 }, rot = { x = -90, y = 0, z = 0 }, fov = 55 },
  { coords = 'nope' },
})
check(#fromPoints == 2, 'invalid camera points are skipped')
-- creator path that ends in front of the player: the ride swings round them, then behind
local player = { x = 0, y = 0, z = 1, w = 0 }
local ride = Camera.keysFromPoints({ { coords = { x = 0, y = 12, z = 3 }, rot = { x = -5, y = 0, z = 180 }, fov = 50 },
  { coords = { x = 0.5, y = 2, z = 2 }, rot = { x = -10, y = 0, z = 180 }, fov = 50 } })
Camera.arrivalKeys(ride, player)
check(#ride == 4, 'arrival adds a key beside the player and one behind')
local closest = math.huge
for i = 0, 600 do
  local p = Camera.sampleKeys(ride, i / 600)
  closest = math.min(closest, math.sqrt(p.x ^ 2 + p.y ^ 2))
end
check(closest > 2.0, ('the camera never flies through the player (closest %.2f m)'):format(closest))
local fromBehind = Camera.keysFromPoints({ { coords = { x = 0.2, y = -8, z = 3 }, rot = { x = -5, y = 0, z = 0 }, fov = 50 } })
Camera.arrivalKeys(fromBehind, player)
check(#fromBehind == 2, 'a ride already behind the player goes straight to the end')
check(fromPoints[1] and math.abs(fromPoints[1].look.x - 2) < 1e-6 and math.abs(fromPoints[1].look.y) < 1e-6, 'heading 90 looks towards -x')
check(fromPoints[2] and math.abs(fromPoints[2].look.z - (2 - 8)) < 1e-6, 'pitch -90 looks straight down')

-- 3. automatic ride of every profile with presets ------------------------------------
for key, profile in pairs(Config.IplProfiles) do
  if profile.presets then
    local entry = Utils.v4(profile.coords)
    local tour = Camera.tourKeys(profile.presets, entry)
    check(tour and #tour >= 3, key .. ': automatic ride keys')
    if tour then
      tour[#tour + 1] = Camera.playerKey(entry)
      local ok = true
      for _, k in ipairs(tour) do
        ok = ok and finite(k.pos.x) and finite(k.pos.y) and finite(k.pos.z) and finite(k.look.x) and finite(k.fov)
      end
      check(ok, key .. ': keys are finite')
      local len = Camera.keysLength(tour)
      local ms = Camera.rideDuration(tour, Config.InteriorOptions.cinematic.duration)
      check(len < 46, ('%s: ride of %.1f m stays unhurried'):format(key, len))
      check(ms >= 6000 and ms <= 9000, ('%s: ride lasts 6-9 s (%d ms)'):format(key, ms))
      check(len * 1000 / ms < 5.2, ('%s: average speed %.1f m/s'):format(key, len * 1000 / ms))
      -- ends behind the player, looking the way they face
      local last = tour[#tour]
      local h = math.rad(entry.w)
      local back = (last.pos.x - entry.x) * -math.sin(h) + (last.pos.y - entry.y) * math.cos(h)
      check(back < -3.0, key .. ': ride ends behind the player')
      local _, rot = Camera.sampleKeys(tour, 1)
      check(angleDiff(rot.z, entry.w) < 1.0, key .. ': last frame faces where the player faces')
      local _, _, turn = walk(tour, 600)
      check(turn < 4.0, ('%s: no sudden turn (%.2f deg)'):format(key, turn))
      -- multi-deck garages: the ride stays on the arrival deck
      for i = 1, #tour - 1 do
        check(tour[i].pos.z < entry.z + 4.5, ('%s key %d: on the arrival deck'):format(key, i))
      end
    end
  end
end
check(Camera.tourKeys({}, { x = 0, y = 0, z = 0, w = 0 }) == nil, 'no positions: no automatic ride')
local single = Camera.tourKeys({ { x = 5, y = 0, z = 0.5, w = 90 } }, { x = 0, y = 0, z = 1, w = 270 })
check(single and #single >= 3, 'one vehicle: short orbit + player keys')
local clampCalls = 0
Camera.tourKeys(Config.IplProfiles.garage_10car.presets, Config.IplProfiles.garage_10car.coords, function(p)
  clampCalls = clampCalls + 1
  return p
end)
check(clampCalls >= 4, 'every ride key goes through the wall / ceiling clamp')

-- 4. presetsFrom: the four CEO level 1 garages are one interior model placed four times --
local function frame(origin, yawDeg)
  local y = math.rad(yawDeg)
  return {
    o = origin,
    x = { x = math.cos(y), y = math.sin(y), z = 0 },
    y = { x = -math.sin(y), y = math.cos(y), z = 0 },
    z = { x = 0, y = 0, z = 1 },
  }
end
local P = Config.IplProfiles
local arcadius = frame(Utils.v3(P.ceo_arcadius_garage_1.interiorCoords), 0)
-- relative turns of the other buildings' garages (least-squares fit of their positions)
for key, yaw in pairs({ ceo_maze_bank_garage_1 = -28.2, ceo_lom_bank_garage_1 = -59.74, ceo_maze_bank_west_garage_1 = 3.52 }) do
  local target = frame(Utils.v3(P[key].interiorCoords), yaw)
  local moved = Interior.transformSlots(P.ceo_arcadius_garage_1.presets, arcadius, target)
  local worst, worstH = 0, 0
  for i, v in ipairs(moved) do
    local want = Utils.v4(P[key].presets[i])
    worst = math.max(worst, math.sqrt((v.x - want.x) ^ 2 + (v.y - want.y) ^ 2))
    worstH = math.max(worstH, angleDiff(v.w, want.w))
    check(math.abs(v.z - want.z) < 0.5, ('%s #%d: deck height carried over'):format(key, i))
  end
  -- (the published GTA Online spots differ a little per building: up to ~3.4 m / 20 deg)
  check(worst < 3.5, ('%s: derived positions within %.2f m of the published ones'):format(key, worst))
  check(worstH < 22, ('%s: derived headings within %.1f deg'):format(key, worstH))
  local entry = Interior.transformSlots({ P.ceo_arcadius_garage_1.coords }, arcadius, target)[1]
  check(Utils.dist(entry, P[key].coords) < 3.0, key .. ': derived arrival point near the published one')
end
local a, b = frame({ x = 1, y = 2, z = 3 }, 40), frame({ x = -50, y = 7, z = 90 }, -75)
local there = Interior.transformSlots({ { x = 4, y = -3, z = 5, w = 10 } }, a, b)
local back = Interior.transformSlots(there, b, a)[1]
check(math.abs(back.x - 4) < 0.01 and math.abs(back.y + 3) < 0.01 and math.abs(back.z - 5) < 0.01 and angleDiff(back.w, 10) < 0.05, 'transform round trip')

-- 5. vehicle card target ------------------------------------------------------------------
local coords = { [11] = vector3(0, 0, 0), [12] = vector3(4, 0, 0), [13] = vector3(30, 0, 0) }
function DoesEntityExist(e) return coords[e] ~= nil end
function GetEntityCoords(e) return coords[e] end
local recA, recB, recC = { plate = 'A' }, { plate = 'B' }, { plate = 'C' }
local byEntity = { [11] = recA, [12] = recB, [13] = recC }
local rec = Interior.pickTagVehicle(byEntity, { x = 1, y = 0, z = 0 }, nil, 5.0)
check(rec == recA, 'card on the nearest vehicle')
rec = Interior.pickTagVehicle(byEntity, { x = 2.2, y = 0, z = 0 }, recA, 5.0)
check(rec == recA, 'card stays while the other vehicle is barely closer')
rec = Interior.pickTagVehicle(byEntity, { x = 3.5, y = 0, z = 0 }, recA, 5.0)
check(rec == recB, 'card moves once another vehicle is clearly closer')
rec = Interior.pickTagVehicle(byEntity, { x = -5.6, y = 0, z = 0 }, recA, 5.0)
check(rec == recA, 'card kept a little beyond the range')
rec = Interior.pickTagVehicle(byEntity, { x = -7, y = 0, z = 0 }, recA, 5.0)
check(rec == nil, 'card gone when far from every vehicle')
coords[11] = nil
rec = Interior.pickTagVehicle(byEntity, { x = 0, y = 0, z = 0 }, recA, 5.0)
check(rec == recB, 'deleted vehicle loses the card')

if #failures > 0 then
  print(('interiors_client: %d/%d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('interiors_client: %d checks OK'):format(checks))
