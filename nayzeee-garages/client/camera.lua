--[[
  nayzeee-garages — scripted camera paths (NZ.Camera).

  - Camera.cinematic: the garage interior arrival ride. A single scripted camera follows a
    smooth curve (centripetal Catmull-Rom through position keys and look-at keys, moved at
    an eased, even speed) and settles behind the player's character, then hands over to the
    gameplay camera with a short blend. The keys come from the creator's camera points when
    the interior has them, else from the vehicle positions (Camera.tourKeys). Any key skips.
  - Camera.playPath: the older point-to-point interpolation (kept for callers that want it).
  - Camera.current: the gameplay camera as a CameraPoint (interior creator).
  Used by the interior entry and the creator preview (docs/ARCHITECTURE.md §4.3, §6, §7.7).
]]

local Camera = NZ.Camera
local Utils = NZ.Utils

local MAX_TRANSITION = 60000
local MAX_RETURN = 30000

local cams = {}          -- scripted cams of the path currently playing
local session = 0        -- bumped by every play / stop; a running path checks it to abort
local playing = false
local rendering = false  -- RenderScriptCams(true) is in effect

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function destroyCams()
  for i = 1, #cams do
    local cam = cams[i]
    if cam and DoesCamExist(cam) then
      SetCamActive(cam, false)
      DestroyCam(cam, false)
    end
  end
  cams = {}
end

--- Normalize a CameraPoint. Returns nil when it is unusable.
local function toPoint(p)
  if type(p) ~= 'table' then return nil end
  local coords = Utils.v3(p.coords)
  local rot = Utils.v3(p.rot) or { x = 0.0, y = 0.0, z = 0.0 }
  if not coords then return nil end
  local fov = Utils.clamp(tonumber(p.fov) or 50.0, 5.0, 130.0)
  return { coords = coords, rot = rot, fov = fov + 0.0 }
end

local function skipPressed()
  return IsDisabledControlJustReleased(0, 200)   -- Esc
    or IsDisabledControlJustReleased(0, 202)     -- Esc / Backspace (frontend cancel)
    or IsDisabledControlJustReleased(0, 194)     -- Backspace
end

---------------------------------------------------------------------------------------
-- Curve math (pure: no natives, covered by tools/smoke/interiors_client.lua)
---------------------------------------------------------------------------------------

local function vec(x, y, z) return { x = x + 0.0, y = y + 0.0, z = z + 0.0 } end
local function sub(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
local function addScaled(a, b, k) return vec(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k) end
local function length(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function distance(a, b) return length(sub(a, b)) end

--- Blend of two points: a * wa + b * wb.
local function mix(a, wa, b, wb)
  return vec(a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb)
end

local LOOK_WEIGHT = 0.35   -- turning the view also takes time (pans in place never snap)

--- Catmull-Rom point (Barry-Goldman form) between p1 and p2 at parameter tt, on explicit
--- knots t0..t3.
local function catmull(p0, p1, p2, p3, t0, t1, t2, t3, tt)
  local a1 = mix(p0, (t1 - tt) / (t1 - t0), p1, (tt - t0) / (t1 - t0))
  local a2 = mix(p1, (t2 - tt) / (t2 - t1), p2, (tt - t1) / (t2 - t1))
  local a3 = mix(p2, (t3 - tt) / (t3 - t2), p3, (tt - t2) / (t3 - t2))
  local b1 = mix(a1, (t2 - tt) / (t2 - t0), a2, (tt - t0) / (t2 - t0))
  local b2 = mix(a2, (t3 - tt) / (t3 - t1), a3, (tt - t1) / (t3 - t1))
  return mix(b1, (t2 - tt) / (t2 - t1), b2, (tt - t1) / (t2 - t1))
end

--- One parameter for the whole ride (centripetal: square root of how far the camera and
--- its view travel between keys). Both curves use it, so they stay in step and the motion
--- is continuous through every key (no change of speed at a key, no loops or cusps).
local function knotsOf(keys)
  local knots = { 0.0 }
  for i = 2, #keys do
    local d = distance(keys[i].pos, keys[i - 1].pos) + distance(keys[i].look, keys[i - 1].look) * LOOK_WEIGHT
    knots[i] = knots[i - 1] + math.max(d, 1e-2) ^ 0.5
  end
  return knots
end

--- Segment index i (keys i and i + 1) holding parameter T.
local function segmentOf(knots, T)
  local n = #knots
  local i = 1
  while i < n - 1 and knots[i + 1] < T do i = i + 1 end
  return i
end

--- Point of the curve through `pts` at parameter T (0 .. knots[#knots]). The ends are
--- mirrored so the curve starts and ends exactly on the first / last key.
local function curveAt(pts, knots, T)
  local n = #pts
  if n == 1 then return pts[1] end
  T = math.min(knots[n], math.max(0.0, T))
  local i1 = segmentOf(knots, T)
  local i2 = i1 + 1
  local p1, p2, t1, t2 = pts[i1], pts[i2], knots[i1], knots[i2]
  local p0, t0, p3, t3
  if pts[i1 - 1] then
    p0, t0 = pts[i1 - 1], knots[i1 - 1]
  else
    p0, t0 = addScaled(p1, sub(p1, p2), 1.0), t1 - (t2 - t1)
  end
  if pts[i2 + 1] then
    p3, t3 = pts[i2 + 1], knots[i2 + 1]
  else
    p3, t3 = addScaled(p2, sub(p2, p1), 1.0), t2 + (t2 - t1)
  end
  return catmull(p0, p1, p2, p3, t0, t1, t2, t3, T)
end

local RAMP = 0.22   -- share of the ride spent speeding up (and again slowing down)

--- Travelled share of the ride at time share t: speed rises smoothly (sin²) from rest over
--- the first RAMP, stays even, and falls back to rest over the last RAMP. Top speed is only
--- 1.28x the average (a plain smoothstep peaks at 1.5x), so the glide stays unhurried.
local function ease(t)
  t = math.min(1.0, math.max(0.0, t))
  local a = RAMP
  local function ramp(x) return x / 2.0 - a / (2.0 * math.pi) * math.sin(math.pi * x / a) end
  local total = 1.0 - a
  local travelled
  if t <= a then
    travelled = ramp(t)
  elseif t >= 1.0 - a then
    travelled = total - ramp(1.0 - t)
  else
    travelled = a / 2.0 + (t - a)
  end
  return travelled / total
end

local SAMPLES = 480

--- Travelled-distance table of a key list (camera + view movement): lets the camera move
--- at an even speed whatever the spacing of the keys. s is normalized 0..1.
local function arcTable(keys)
  local pos, look = {}, {}
  for i = 1, #keys do pos[i], look[i] = keys[i].pos, keys[i].look end
  local knots = knotsOf(keys)
  local last = knots[#knots]
  local us, ss = { 0.0 }, { 0.0 }
  local prevP, prevL = curveAt(pos, knots, 0.0), curveAt(look, knots, 0.0)
  local total = 0.0
  for i = 1, SAMPLES do
    local u = last * i / SAMPLES
    local p, l = curveAt(pos, knots, u), curveAt(look, knots, u)
    total = total + distance(p, prevP) + distance(l, prevL) * LOOK_WEIGHT
    us[#us + 1], ss[#ss + 1] = u, total
    prevP, prevL = p, l
  end
  for i = 1, #ss do ss[i] = total > 1e-6 and ss[i] / total or (i - 1) / SAMPLES end
  return { u = us, s = ss, pos = pos, look = look, knots = knots, total = total }
end

--- Curve parameter at normalized travelled distance s (binary search + lerp).
local function paramAt(arc, s)
  local ss, us = arc.s, arc.u
  if s <= 0 then return 0.0 end
  if s >= 1 then return us[#us] end
  local lo, hi = 1, #ss
  while hi - lo > 1 do
    local mid = (lo + hi) // 2
    if ss[mid] < s then lo = mid else hi = mid end
  end
  local span = ss[hi] - ss[lo]
  local k = span > 0 and (s - ss[lo]) / span or 0.0
  return us[lo] + (us[hi] - us[lo]) * k
end

--- GTA camera rotation (pitch, 0, heading) looking from `from` at `to`.
local function lookRotation(from, to)
  local d = sub(to, from)
  local flat = math.sqrt(d.x * d.x + d.y * d.y)
  local pitch = math.deg(math.atan(d.z, math.max(flat, 1e-6)))
  local heading = math.deg(math.atan(-d.x, d.y))
  return vec(pitch, 0.0, heading)
end

--- Unit view direction of a GTA camera rotation { x = pitch, z = heading }.
local function forwardOf(rot)
  local p, h = math.rad(tonumber(rot.x) or 0.0), math.rad(tonumber(rot.z) or 0.0)
  return vec(-math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
end

--- Camera pose of the ride at time fraction t (0..1): pos, rot, fov.
local function sampleRide(arc, keys, t)
  local u = paramAt(arc, ease(t))
  local pos, look = curveAt(arc.pos, arc.knots, u), curveAt(arc.look, arc.knots, u)
  local fov = keys[1].fov or 50.0
  if #keys > 1 then
    local i = segmentOf(arc.knots, u)
    local a, b = keys[i], keys[i + 1]
    local span = arc.knots[i + 1] - arc.knots[i]
    local k = span > 0 and math.min(1.0, math.max(0.0, (u - arc.knots[i]) / span)) or 1.0
    k = k * k * (3 - 2 * k)
    fov = (a.fov or 50.0) + ((b.fov or 50.0) - (a.fov or 50.0)) * k
  end
  return pos, lookRotation(pos, look), fov
end

--- Keys { pos, look, fov } for the creator's CameraPoints (look 8 m ahead of each point).
---@param points table CameraPoint[]
---@return table keys
function Camera.keysFromPoints(points)
  local keys = {}
  if type(points) ~= 'table' then return keys end
  for i = 1, #points do
    local p = toPoint(points[i])
    if p then
      local pos = vec(p.coords.x, p.coords.y, p.coords.z)
      keys[#keys + 1] = { pos = pos, look = addScaled(pos, forwardOf(p.rot), 8.0), fov = p.fov }
    end
  end
  return keys
end

local TOUR_FLOOR_RANGE = 3.5   -- vehicle positions this far above / below the arrival point
                               -- are on the same deck (multi-level garages)
local MAX_RIDE = 34.0          -- metres the automatic ride travels at most (about 4 m/s)
local MIN_LOOK = 6.0           -- look targets at least this far from the camera
local ORBIT_RADIUS = 3.0       -- the end of the ride circles the player at this distance

--- Swing round the player on the side the ride arrives from (never through their face
--- or body): adds a key beside them unless the ride already comes from behind; the caller
--- then adds Camera.playerKey (the spot behind them). Keys keep their distance from the
--- player and aim through look targets at least MIN_LOOK away.
local function appendArrival(keys, e, clamp, fallbackSide)
  local lastKey = keys[#keys]
  if not lastKey then return end
  local h = math.rad(e.w or 0.0)
  local fx, fy = -math.sin(h), math.cos(h)      -- where the player faces
  local lx, ly = -fy, fx                        -- their left
  local rx, ry = lastKey.pos.x - e.x, lastKey.pos.y - e.y
  local near = math.sqrt(rx * rx + ry * ry)
  if near < ORBIT_RADIUS and near > 1e-3 then
    lastKey.pos = clamp(vec(e.x + rx / near * ORBIT_RADIUS, e.y + ry / near * ORBIT_RADIUS, lastKey.pos.z))
    rx, ry = lastKey.pos.x - e.x, lastKey.pos.y - e.y
  end
  local along, across = rx * fx + ry * fy, rx * lx + ry * ly
  -- already behind them (more than ~120 degrees round): straight on to the last key
  if along < 0 and math.abs(across) < -along * math.tan(math.rad(60.0)) then return end
  local side = across >= 0 and 1 or -1
  if math.abs(across) < 0.5 then side = fallbackSide or 1 end
  local phi = math.rad(100.0) * side
  local cosP, sinP = math.cos(phi), math.sin(phi)
  local pos = clamp(vec(e.x + (fx * cosP + lx * sinP) * ORBIT_RADIUS, e.y + (fy * cosP + ly * sinP) * ORBIT_RADIUS, e.z + 0.5))
  local look = vec(e.x, e.y, e.z + 0.45)
  local d = sub(look, pos)
  local len = length(d)
  if len > 1e-3 and len < MIN_LOOK then look = addScaled(pos, d, MIN_LOOK / len) end
  keys[#keys + 1] = { pos = pos, look = look, fov = 50.0 }
end

--- Automatic ride past the vehicle positions, ending beside the arrival point (the
--- caller appends Camera.playerKey). Starts above the far end of the parked vehicles,
--- glides along them (in front of a single row, down the aisle between two rows) and
--- swings round to the side of the player so the last move ends behind them.
--- `clamp(point)` may pull a key out of walls / below ceilings (in game: shape tests).
---@param slots table Vec4[]
---@param entry table Vec4 where the player stands (x, y, z, w)
---@param clamp function|nil
---@return table|nil keys
function Camera.tourKeys(slots, entry, clamp)
  local e = Utils.v4(entry)
  if not e or type(slots) ~= 'table' then return nil end
  clamp = type(clamp) == 'function' and clamp or function(p) return p end

  local list, all = {}, {}
  for i = 1, #slots do
    local v = Utils.v4(slots[i])
    if v then
      all[#all + 1] = v
      if math.abs(v.z - e.z) <= TOUR_FLOOR_RANGE then list[#list + 1] = v end
    end
  end
  if #list == 0 then list = all end
  if #list == 0 then return nil end

  -- Centre, car height and the facing of the parked vehicles.
  local cx, cy, cz, fx, fy = 0.0, 0.0, 0.0, 0.0, 0.0
  for _, v in ipairs(list) do
    cx, cy, cz = cx + v.x, cy + v.y, cz + v.z
    local h = math.rad(v.w or 0.0)
    fx, fy = fx - math.sin(h), fy + math.cos(h)
  end
  local n = #list
  cx, cy, cz = cx / n, cy / n, cz / n

  -- Main direction of the layout (principal axis of the positions).
  local sxx, syy, sxy = 0.0, 0.0, 0.0
  for _, v in ipairs(list) do
    local dx, dy = v.x - cx, v.y - cy
    sxx, syy, sxy = sxx + dx * dx, syy + dy * dy, sxy + dx * dy
  end
  local ux, uy
  if n >= 2 and (sxx + syy) > 0.25 then
    local theta = 0.5 * math.atan(2.0 * sxy, sxx - syy)
    ux, uy = math.cos(theta), math.sin(theta)
  else
    local dx, dy = list[1].x - e.x, list[1].y - e.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.5 then
      local h = math.rad(e.w or 0.0)
      dx, dy, d = -math.sin(h), math.cos(h), 1.0
    end
    ux, uy = dx / d, dy / d
  end
  local vx, vy = -uy, ux

  local tmin, tmax, wide = math.huge, -math.huge, 0.0
  for _, v in ipairs(list) do
    local du, dv = (v.x - cx) * ux + (v.y - cy) * uy, (v.x - cx) * vx + (v.y - cy) * vy
    tmin, tmax = math.min(tmin, du), math.max(tmax, du)
    wide = math.max(wide, math.abs(dv))
  end

  -- The player arrives on the "near" (-u) side: the ride starts at the far end.
  local eu, ev = (e.x - cx) * ux + (e.y - cy) * uy, (e.x - cx) * vx + (e.y - cy) * vy
  if eu > 0 then
    ux, uy, vx, vy = -ux, -uy, -vx, -vy
    ev = -ev
    tmin, tmax = -tmax, -tmin
  end
  local span = tmax - tmin

  -- Sideways offset of the ride: in front of a single row (the side the vehicles face),
  -- down the middle (towards the player) when vehicles stand on both sides.
  local lateral
  if wide < 1.5 then
    local facing = fx * vx + fy * vy
    local side = facing ~= 0 and (facing > 0 and 1 or -1) or (ev >= 0 and 1 or -1)
    lateral = side * 3.2
  else
    lateral = math.max(-2.0, math.min(2.0, ev * 0.5))
  end
  -- Fallback side of the final swing round the player (when the ride arrives head-on).
  local sideOfPlayer = (lateral - ev) >= 0 and 1 or -1
  if math.abs(lateral - ev) < 0.5 then sideOfPlayer = lateral >= 0 and 1 or -1 end

  local function at(t, lat, h) return vec(cx + ux * t + vx * lat, cy + uy * t + vy * lat, cz + h) end

  -- Keep the ride unhurried: long rows are only followed for part of their length (the
  -- rest stays in view), and not at all when the player arrives far from the vehicles.
  local nearPoint = at(tmin, lateral, 0.0)
  local toPlayer = math.sqrt((nearPoint.x - e.x) ^ 2 + (nearPoint.y - e.y) ^ 2)
  local far = math.min(tmax, tmin + math.max(0.0, MAX_RIDE - toPlayer - 6.0))
  local run = far - tmin
  local eyes = vec(e.x, e.y, e.z + 0.4)

  local keys = {}
  local function key(pos, look, fov)
    pos = clamp(pos)
    -- Aim through the target from a few metres away: the view never spins round a point
    -- the camera passes close to.
    local d = sub(look, pos)
    local len = length(d)
    if len < MIN_LOOK then look = len > 1e-3 and addScaled(pos, d, MIN_LOOK / len) or addScaled(pos, vec(ux, uy, 0.0), MIN_LOOK) end
    keys[#keys + 1] = { pos = pos, look = look, fov = fov }
  end
  if span < 1.0 then
    -- One vehicle (or a tight cluster): a slow half orbit round it.
    key(at(3.6, lateral ~= 0 and lateral or 3.0, 2.2), at(0.0, 0.0, 0.3), 45.0)
    key(at(0.0, (lateral ~= 0 and lateral or 3.0) * 1.3, 1.6), at(0.0, 0.0, 0.2), 46.0)
  elseif run >= 3.0 then
    key(at(far + (far >= tmax and 0.6 or 0.0), lateral, 2.6), at(far - run * 0.55, 0.0, 0.2), 46.0)
    key(at(far - run * 0.5, lateral, 2.0), at(tmin - run * 0.05, lateral * 0.3, 0.2), 48.0)
    key(at(tmin, lateral, 1.6), eyes, 50.0)
  else
    -- Above the nearest vehicles looking over the others, then down towards the player.
    key(at(tmin - 1.0, lateral, 2.8), at(tmin + span * 0.5, 0.0, 0.2), 46.0)
    key(at(tmin - 2.0, lateral, 1.8), eyes, 50.0)
  end
  appendArrival(keys, e, clamp, sideOfPlayer)
  return keys
end

--- End a ride on the character at `pose` (x, y, z, w): swing round them when the ride
--- arrives from the front or side, then settle behind them (adds 1-2 keys).
---@param keys table
---@param pose table Vec4
---@param clamp function|nil
---@return table keys
function Camera.arrivalKeys(keys, pose, clamp)
  local e = Utils.v4(pose)
  if not e or type(keys) ~= 'table' then return keys end
  clamp = type(clamp) == 'function' and clamp or function(p) return p end
  appendArrival(keys, e, clamp, 1)
  keys[#keys + 1] = Camera.playerKey(e, clamp)
  return keys
end

--- Final key: where the gameplay camera sits behind a character at `pose` (x, y, z, w).
---@param pose table Vec4
---@param clamp function|nil
---@return table key
function Camera.playerKey(pose, clamp)
  local e = Utils.v4(pose) or { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
  local h = math.rad(e.w or 0.0)
  local fx, fy = -math.sin(h), math.cos(h)
  local pos = vec(e.x - fx * 3.4, e.y - fy * 3.4, e.z + 0.65)
  if type(clamp) == 'function' then pos = clamp(pos) end
  return { pos = pos, look = vec(e.x + fx * 6.0, e.y + fy * 6.0, e.z + 0.3), fov = 50.0 }
end

--- Total length of a key list (positions), metres.
---@param keys table
---@return number
function Camera.keysLength(keys)
  local len = 0.0
  for i = 2, #keys do len = len + distance(keys[i - 1].pos, keys[i].pos) end
  return len
end

--- Ride duration (ms) for a key list: `base` stretched by the path length, kept within
--- 80-120 % of base (6-9 s for the default 7.5 s).
---@param keys table
---@param base number|nil ms
---@return integer
function Camera.rideDuration(keys, base)
  base = Utils.clamp(tonumber(base) or 7500, 4000, 12000)
  local len = Camera.keysLength(keys)
  local ms = base * (0.75 + len / 60.0)
  return math.floor(Utils.clamp(ms, base * 0.8, base * 1.2))
end

--- Pose of a key list at time fraction t (tests / previews): pos, rot, fov.
---@param keys table
---@param t number 0..1
function Camera.sampleKeys(keys, t)
  return sampleRide(arcTable(keys), keys, t)
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Play a camera path and block until it ends (call it from a thread).
--- Every point is a scripted cam; consecutive cams are interpolated over `transitionMs`
--- (a single point is held for `transitionMs`). Afterwards the gameplay camera comes back
--- with an `opts.returnTime` ms blend (RenderScriptCams(false, true, returnTime)).
--- opts = { returnTime = 1000, onStart = function() end (runs once the first cam renders,
---          e.g. to fade the screen in), skippable = false (Esc / Backspace abort) }
---@param points table CameraPoint[]
---@param transitionMs number|nil ms per transition (default 3000)
---@param opts table|nil
---@return boolean completed false when the path was empty, aborted or stopped
function Camera.playPath(points, transitionMs, opts)
  opts = type(opts) == 'table' and opts or {}
  local list = {}
  if type(points) == 'table' then
    for i = 1, #points do
      local p = toPoint(points[i])
      if p then list[#list + 1] = p end
    end
  end
  if #list == 0 then return false end

  Camera.stop()
  session = session + 1
  local my = session
  playing = true

  local transition = math.floor(Utils.clamp(tonumber(transitionMs) or 3000, 0, MAX_TRANSITION))
  local returnTime = math.floor(Utils.clamp(tonumber(opts.returnTime) or 1000, 0, MAX_RETURN))

  for i = 1, #list do
    local p = list[i]
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.coords.x + 0.0, p.coords.y + 0.0,
      p.coords.z + 0.0, p.rot.x + 0.0, p.rot.y + 0.0, p.rot.z + 0.0, p.fov, false, 2)
    if not cam or cam == -1 then
      destroyCams()
      playing = false
      lib.print.warn('[nayzeee-garages] could not create a scripted camera')
      return false
    end
    cams[#cams + 1] = cam
  end

  SetCamActive(cams[1], true)
  RenderScriptCams(true, false, 0, true, true)
  rendering = true

  if type(opts.onStart) == 'function' then
    local ok, err = pcall(opts.onStart)
    if not ok then lib.print.error(('[nayzeee-garages] camera onStart failed: %s'):format(err)) end
  end

  --- Wait `ms` while hiding the HUD; false when stopped or skipped.
  local function hold(ms)
    local deadline = GetGameTimer() + ms
    repeat
      if session ~= my then return false end
      HideHudAndRadarThisFrame()
      if opts.skippable then
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)
        if skipPressed() then return false end
      end
      Wait(0)
    until GetGameTimer() >= deadline
    return session == my
  end

  local completed = true
  if #cams == 1 then
    completed = hold(transition)
  else
    for i = 2, #cams do
      if session ~= my then
        completed = false
        break
      end
      SetCamActiveWithInterp(cams[i], cams[i - 1], transition, 1, 1)
      if not hold(transition) then
        completed = false
        break
      end
    end
  end

  -- Camera.stop() already restored the gameplay camera.
  if session ~= my then return false end

  local blend = completed and returnTime > 0
  RenderScriptCams(false, blend, blend and returnTime or 0, true, true)
  rendering = false
  if blend then hold(returnTime) end

  if session == my then
    destroyCams()
    playing = false
  end
  return completed
end

-- Every keyboard / pad button a player might press to skip (look / mouse axes and push to
-- talk are left out so moving the mouse or talking never skips).
local SKIP_CONTROLS = {
  18, 21, 22, 23, 24, 25, 26, 29, 32, 33, 34, 35, 36, 37, 38, 44, 45, 47, 51, 52, 73, 74,
  140, 166, 167, 168, 170, 176, 177, 191, 194, 199, 200, 201, 202, 244, 245, 246, 288, 289,
  303, 311,
}
local SKIP_ARM_MS = 600       -- ignore the key that opened the garage
local SKIP_FADE_OUT = 250
local SKIP_FADE_IN = 450

local function skipPressedAny()
  for i = 1, #SKIP_CONTROLS do
    if IsDisabledControlJustPressed(0, SKIP_CONTROLS[i]) then return true end
  end
  return false
end

--- Play a key list { pos, look, fov }[] (>= 2) with one scripted camera moved every frame
--- along the curve, then blend back to the gameplay camera. Blocking (call from a thread).
--- opts = { duration = 7500 (ms), skippable = false (any key: quick fade, then the gameplay
---          camera), onStart = function() (first frame rendered), blend = 900 (ms),
---          abort = function() -> true to end the ride at once like a skip (checked every
---          frame, e.g. the player died or was moved away) }
---@param keys table
---@param opts table|nil
---@return boolean completed false when skipped, stopped or invalid
function Camera.playKeys(keys, opts)
  opts = type(opts) == 'table' and opts or {}
  if type(keys) ~= 'table' or #keys < 2 then return false end

  Camera.stop()
  session = session + 1
  local my = session
  playing = true

  local arc = arcTable(keys)
  local duration = math.floor(Utils.clamp(tonumber(opts.duration) or 7500, 1000, MAX_TRANSITION))
  local blend = math.floor(Utils.clamp(tonumber(opts.blend) or 900, 0, MAX_RETURN))
  local pos, rot, fov = sampleRide(arc, keys, 0.0)
  local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, fov, false, 2)
  if not cam or cam == -1 then
    playing = false
    lib.print.warn('[nayzeee-garages] could not create a scripted camera')
    return false
  end
  cams = { cam }
  SetCamActive(cam, true)
  RenderScriptCams(true, false, 0, true, true)
  rendering = true

  if type(opts.onStart) == 'function' then
    local ok, err = pcall(opts.onStart)
    if not ok then lib.print.error(('[nayzeee-garages] camera onStart failed: %s'):format(err)) end
  end

  local started = GetGameTimer()
  local skipped = false
  local abort = type(opts.abort) == 'function' and opts.abort or nil
  while true do
    if session ~= my then return false end
    if abort then
      local okAbort, stop = pcall(abort)
      if not okAbort or stop == true then
        skipped = true
        break
      end
    end
    local now = GetGameTimer()
    local t = math.min(1.0, (now - started) / duration)
    pos, rot, fov = sampleRide(arc, keys, t)
    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    HideHudAndRadarThisFrame()
    if opts.skippable then
      DisableAllControlActions(0)
      if now - started >= SKIP_ARM_MS and skipPressedAny() then
        skipped = true
        break
      end
    end
    if t >= 1.0 then break end
    Wait(0)
  end

  if skipped then
    -- A cut would be a jump: hide it behind a short fade.
    DoScreenFadeOut(SKIP_FADE_OUT)
    local deadline = GetGameTimer() + SKIP_FADE_OUT + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline and session == my do
      DisableAllControlActions(0)
      HideHudAndRadarThisFrame()
      Wait(0)
    end
    if session ~= my then return false end
    RenderScriptCams(false, false, 0, true, true)
    rendering = false
    destroyCams()
    playing = false
    DoScreenFadeIn(SKIP_FADE_IN)
    return false
  end

  RenderScriptCams(false, blend > 0, blend, true, true)
  rendering = false
  local deadline = GetGameTimer() + blend
  while GetGameTimer() < deadline and session == my do
    HideHudAndRadarThisFrame()
    if opts.skippable then DisableAllControlActions(0) end
    Wait(0)
  end
  if session == my then
    destroyCams()
    playing = false
  end
  return true
end

local WALL_MARGIN = 0.6
local CEILING_MARGIN = 0.45

--- World / object line of sight between two points: the hit point or nil.
local function probe(a, b)
  local ok, handle = pcall(StartExpensiveSynchronousShapeTestLosProbe, a.x, a.y, a.z, b.x, b.y, b.z, 1 | 16, PlayerPedId(), 7)
  if not ok or not handle then return nil end
  local _, hit, coords = GetShapeTestResult(handle)
  if hit == true or hit == 1 then return Utils.v3(coords) end
  return nil
end

--- Pull a camera key below the ceiling and in front of walls, as seen from `origin`
--- (where the player stands): the ride never looks through the room's walls.
local function keepInside(origin, p)
  local base = vec(p.x, p.y, p.z - 1.2)
  local up = probe(base, vec(p.x, p.y, p.z + CEILING_MARGIN))
  if up then p = vec(p.x, p.y, math.max(base.z, up.z - CEILING_MARGIN)) end
  local hit = probe(origin, p)
  if hit then
    local d = sub(p, origin)
    local len = length(d)
    if len > 1e-3 then p = addScaled(origin, d, math.max(0.0, distance(origin, hit) - WALL_MARGIN) / len) end
  end
  return p
end

--- The garage arrival ride (blocking): the creator's camera points when the interior has
--- them (cutscene.enabled), else an automatic ride past the vehicle positions (`auto`), in
--- both cases ending behind the player's character. Shows a "skip" prompt when skippable.
--- args = { cutscene = Cutscene|nil, slots = Vec4[], auto = true, duration = 7500,
---          skippable = true, onStart = function(), abort = function() (see playKeys) }
---@param args table
---@return boolean played true when a ride was played to its end
function Camera.cinematic(args)
  args = type(args) == 'table' and args or {}
  local ped = PlayerPedId()
  local c = Utils.v3(GetEntityCoords(ped))
  if not c then return false end
  local pose = { x = c.x, y = c.y, z = c.z, w = tonumber(GetEntityHeading(ped)) or 0.0 }
  local origin = vec(pose.x, pose.y, pose.z + 0.6)
  local function clamp(p) return keepInside(origin, p) end

  local keys, duration = nil, nil
  local cut = type(args.cutscene) == 'table' and args.cutscene or nil
  if cut and cut.enabled == true and type(cut.points) == 'table' and #cut.points > 0 then
    keys = Camera.keysFromPoints(cut.points)
    Camera.arrivalKeys(keys, pose, clamp)
    duration = Utils.clamp((tonumber(cut.transition) or 3000) * (#keys - 1), 3000, 30000)
  elseif args.auto ~= false then
    keys = Camera.tourKeys(args.slots, pose, clamp)
    if keys then
      keys[#keys + 1] = Camera.playerKey(pose, clamp)
      duration = Camera.rideDuration(keys, args.duration)
    end
  end
  if not keys or #keys < 2 then return false end

  -- The gameplay camera waits behind the character for the hand-over at the end.
  SetGameplayCamRelativeHeading(0.0)
  SetGameplayCamRelativePitch(-6.0, 1.0)
  local skippable = args.skippable ~= false
  if skippable then NZ.NUI.prompt(L('Skip'), L('Any key')) end
  local ok, completed = pcall(Camera.playKeys, keys, {
    duration = duration,
    skippable = skippable,
    onStart = args.onStart,
    abort = args.abort,
    blend = cut and cut.enabled == true and Utils.clamp(tonumber(cut.returnTime) or 900, 300, 2000) or 900,
  })
  if skippable then NZ.NUI.prompt(nil) end
  if not ok then
    lib.print.error(('[nayzeee-garages] camera ride failed: %s'):format(completed))
    Camera.stop()
    return false
  end
  return completed == true
end

--- Abort the path that is playing (if any) and return to the gameplay camera at once.
function Camera.stop()
  session = session + 1
  if rendering then
    RenderScriptCams(false, false, 0, true, true)
    rendering = false
  end
  destroyCams()
  playing = false
end

--- Whether a camera path is playing.
---@return boolean
function Camera.isPlaying()
  return playing
end

--- The current gameplay camera as a CameraPoint { coords, rot, fov }.
---@return table
function Camera.current()
  local c = GetGameplayCamCoord()
  local r = GetGameplayCamRot(2)
  local fov = tonumber(GetGameplayCamFov()) or 50.0
  local coords = Utils.v3(c) or { x = 0.0, y = 0.0, z = 0.0 }
  local rot = Utils.v3(r) or { x = 0.0, y = 0.0, z = 0.0 }
  return {
    coords = { x = Utils.round(coords.x, 3), y = Utils.round(coords.y, 3), z = Utils.round(coords.z, 3) },
    rot = { x = Utils.round(rot.x, 2), y = Utils.round(rot.y, 2), z = Utils.round(rot.z, 2) },
    fov = Utils.round(fov, 2),
  }
end

---------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  Camera.stop()
end)
