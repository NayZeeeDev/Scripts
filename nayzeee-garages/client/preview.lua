--[[
  nayzeee-garages — 3D vehicle preview for the garage / impound showroom (NZ.Preview).

  While a garage or impound menu is open, the selected vehicle is spawned as a LOCAL
  (never networked, invisible to everyone else) entity at a hidden "studio" spot — by default
  high in the sky above the player, out of reach of every building and hill — with its stored
  properties and damage. A scripted camera frames it so the car fills the stage rectangle the
  interface reports ('garage:previewRect'), the car turns slowly on the spot, swaps fade
  (entity alpha) and everything is cleaned up when the menu closes, the player dies / is
  downed, or the resource stops. The interface makes its stage transparent only while
  NZ.Preview.show() reported the car as shown; otherwise it keeps drawing the image.

  Nothing here is trusted by the server: the vehicle data comes from the server callbacks
  'nz:garage:preview' / 'nz:impound:preview' (props of a vehicle listed in the open menu) and
  the entity only exists on this client.

  Pure helpers (normalizeRect, basis, project, computeFrame) carry no natives and are covered
  by tools/smoke/preview.lua.
]]

local Preview = NZ.Preview

local DEFAULTS = {
  enabled = true,
  fov = 30.0,           -- vertical field of view of the preview camera (GTA cams use vertical FOV)
  pitch = -9.0,         -- camera pitch in degrees (negative looks down onto the car)
  yaw = 20.0,           -- direction the camera looks along (0 = north)
  fill = 0.9,           -- share of the stage box the turning car may take (worst angle)
  speed = 9.0,          -- turntable speed in degrees per second (one turn in 40 s)
  height = 260.0,       -- studio height above the player ...
  minZ = 650.0,         -- ... but never lower than this (above every building / hill)
  studio = nil,         -- optional fixed studio spot { x, y, z, w } (streamed with SetFocusPosAndVel)
  lights = true,        -- soft key / rim lights at night
  fadeIn = 260,         -- ms
  fadeOut = 150,        -- ms
  renderDelay = 100,    -- ms between telling the interface and switching to the camera (the
                        -- interface needs a frame or two to clear the stage and dim around it)
  dataTimeout = 4000,   -- ms to wait for the server's vehicle data
  modelTimeout = 6000,  -- ms to wait for the model to stream in
}

local DEFAULT_RECT = { x = 0.43, y = 0.17, w = 0.36, h = 0.2, aspect = 16 / 9 }

---------------------------------------------------------------------------------------
-- Pure helpers (no natives)
---------------------------------------------------------------------------------------

local function num(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

--- Turn the interface's stage rectangle (CSS px of a vw x vh viewport) into screen fractions.
--- raw = { x, y, w, h, vw?, vh?, dpr? }; screenW / screenH (px) are used when vw / vh are
--- missing (divided by dpr). Returns { x, y, w, h (0-1), aspect } or nil.
---@param raw table|nil
---@param screenW number|nil
---@param screenH number|nil
---@return table|nil
function Preview.normalizeRect(raw, screenW, screenH)
  if type(raw) ~= 'table' then return nil end
  local x, y, w, h = num(raw.x), num(raw.y), num(raw.w), num(raw.h)
  if not (x and y and w and h) or w <= 1 or h <= 1 then return nil end
  local dpr = num(raw.dpr)
  if not dpr or dpr <= 0 then dpr = 1 end
  local vw, vh = num(raw.vw), num(raw.vh)
  if not vw or vw <= 1 or not vh or vh <= 1 then
    vw, vh = num(screenW), num(screenH)
    if not vw or vw <= 1 or not vh or vh <= 1 then return nil end
    vw, vh = vw / dpr, vh / dpr
  end
  local fx, fy = clamp(x / vw, 0, 1), clamp(y / vh, 0, 1)
  local fw, fh = clamp(w / vw, 0, 1 - fx), clamp(h / vh, 0, 1 - fy)
  if fw < 0.02 or fh < 0.02 then return nil end
  return { x = fx, y = fy, w = fw, h = fh, aspect = clamp(vw / vh, 0.5, 6.0) }
end

--- Camera basis for a rotation (order 2: pitch around X, yaw around Z, no roll):
--- forward, right, up as { x, y, z }.
---@param pitch number degrees
---@param yaw number degrees
function Preview.basis(pitch, yaw)
  local p, z = math.rad(pitch), math.rad(yaw)
  local sp, cp, sz, cz = math.sin(p), math.cos(p), math.sin(z), math.cos(z)
  local forward = { x = -sz * cp, y = cz * cp, z = sp }
  local right = { x = cz, y = sz, z = 0.0 }
  local up = { x = sz * sp, y = -cz * sp, z = cp }
  return forward, right, up
end

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

--- Project a world point through a camera to screen fractions (0,0 top-left).
--- cam = { pos, pitch, yaw, fov (vertical), aspect }. Returns sx, sy, depth (nil behind).
function Preview.project(cam, point)
  local f, r, u = Preview.basis(cam.pitch, cam.yaw)
  local v = { x = point.x - cam.pos.x, y = point.y - cam.pos.y, z = point.z - cam.pos.z }
  local depth = dot(v, f)
  if depth <= 0.01 then return nil end
  local tanV = math.tan(math.rad(cam.fov) / 2)
  local tanH = tanV * cam.aspect
  local ndx = dot(v, r) / (depth * tanH)
  local ndy = dot(v, u) / (depth * tanV)
  return (ndx + 1) / 2, (1 - ndy) / 2, depth
end

--- The 8 corners of the model box turned by `heading` around the origin, relative to `pivot`.
local function corners(dims, heading)
  local out = {}
  local h = math.rad(heading)
  local s, c = math.sin(h), math.cos(h)
  local xs, ys, zs = { dims.min.x, dims.max.x }, { dims.min.y, dims.max.y }, { dims.min.z, dims.max.z }
  for i = 1, 2 do
    for j = 1, 2 do
      for k = 1, 2 do
        local x, y = xs[i], ys[j]
        out[#out + 1] = { x = x * c - y * s, y = x * s + y * c, z = zs[k] }
      end
    end
  end
  return out
end

local SAMPLE_STEP = 15   -- degrees between the headings the fit is checked at

--- Camera that frames a turning vehicle inside a screen rectangle.
--- origin: entity position { x, y, z }; dims: { min = {x,y,z}, max = {x,y,z} } (model box,
--- relative to the origin); rect: normalizeRect() result; opts: { fov, pitch, yaw, fill }.
--- The camera looks along (pitch, yaw) and is placed so the box centre lands on the rect
--- centre; its distance is the smallest one where every corner, at every heading, stays
--- inside the rect shrunk by `fill`. Returns { pos, rot = { x, y, z }, fov, distance, target }.
---@return table
function Preview.computeFrame(origin, dims, rect, opts)
  opts = type(opts) == 'table' and opts or {}
  rect = rect or DEFAULT_RECT
  local fov = clamp(num(opts.fov) or DEFAULTS.fov, 10.0, 90.0)
  local pitch = clamp(num(opts.pitch) or DEFAULTS.pitch, -60.0, 30.0)
  local yaw = num(opts.yaw) or DEFAULTS.yaw
  local fill = clamp(num(opts.fill) or DEFAULTS.fill, 0.3, 1.0)
  local aspect = clamp(num(rect.aspect) or 16 / 9, 0.5, 6.0)

  local mn = type(dims) == 'table' and dims.min or nil
  local mx = type(dims) == 'table' and dims.max or nil
  if type(mn) ~= 'table' or type(mx) ~= 'table' or not (num(mn.x) and num(mx.x)) then
    mn, mx = { x = -1.0, y = -2.3, z = -0.6 }, { x = 1.0, y = 2.3, z = 0.9 }
  end
  dims = { min = mn, max = mx }
  local zc = (mn.z + mx.z) / 2
  local target = { x = origin.x, y = origin.y, z = origin.z + zc }

  local tanV = math.tan(math.rad(fov) / 2)
  local tanH = tanV * aspect
  local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
  local ndx, ndy = cx * 2 - 1, 1 - cy * 2
  local f, r, u = Preview.basis(pitch, yaw)
  local dir = {
    x = f.x + ndx * tanH * r.x + ndy * tanV * u.x,
    y = f.y + ndx * tanH * r.y + ndy * tanV * u.y,
    z = f.z + ndx * tanH * r.z + ndy * tanV * u.z,
  }
  -- allowed box (fractions), shrunk around its centre
  local hw, hh = rect.w * fill / 2, rect.h * fill / 2
  local left, right, top, bottom = cx - hw, cx + hw, cy - hh, cy + hh

  local samples = {}
  for heading = 0, 359, SAMPLE_STEP do
    local list = corners(dims, heading)
    for i = 1, #list do
      local c = list[i]
      samples[#samples + 1] = { x = origin.x + c.x, y = origin.y + c.y, z = origin.z + c.z }
    end
  end

  local function camAt(d)
    return {
      pos = { x = target.x - d * dir.x, y = target.y - d * dir.y, z = target.z - d * dir.z },
      pitch = pitch, yaw = yaw, fov = fov, aspect = aspect,
    }
  end
  local function fits(d)
    local pos = camAt(d).pos
    for i = 1, #samples do
      local q = samples[i]
      local v = { x = q.x - pos.x, y = q.y - pos.y, z = q.z - pos.z }
      local depth = dot(v, f)
      if depth <= 0.01 then return false end
      local sx = (dot(v, r) / (depth * tanH) + 1) / 2
      local sy = (1 - dot(v, u) / (depth * tanV)) / 2
      if sx < left or sx > right or sy < top or sy > bottom then return false end
    end
    return true
  end

  local lo, hi = 0.5, 400.0
  if fits(lo) then
    hi = lo
  elseif fits(hi) then
    for _ = 1, 40 do
      local mid = (lo + hi) / 2
      if fits(mid) then hi = mid else lo = mid end
      if hi - lo < 0.01 then break end
    end
  end
  local cam = camAt(hi)
  return { pos = cam.pos, rot = { x = pitch, y = 0.0, z = yaw }, fov = fov, distance = hi, target = target }
end

---------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------

local function cfg(key)
  local c = type(Config) == 'table' and type(Config.Preview) == 'table' and Config.Preview or nil
  local v = c and c[key]
  if v == nil then return DEFAULTS[key] end
  return v
end

--- Whether the 3D preview is on (Config.Preview.enabled and settings.interface.vehiclePreview).
---@return boolean
function Preview.enabled()
  if cfg('enabled') == false then return false end
  local s = NZ.State and NZ.State.settings
  local ui = type(s) == 'table' and s.interface or nil
  if type(ui) == 'table' and ui.vehiclePreview == false then return false end
  return true
end

---------------------------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------------------------

local state = {
  active = false,     -- scripted camera rendering + render loop running
  app = nil,          -- 'garage' | 'impound'
  key = nil,          -- key of the target the vehicle shows
  vehicle = nil,
  dims = nil,
  heading = 0.0,
  alphaFrom = 0, alphaTo = 0, alphaStart = 0, alphaDur = 0,
  cam = nil,
  rendering = false,  -- RenderScriptCams(true) is in effect
  pendingRender = false,
  studio = nil,
  focus = false,
  frame = nil,
}
local rect = nil          -- last normalized rect from the interface
local token = 0           -- bumped by every show / stop: a running show() checks it
local pendingHash = nil   -- model the newest show() request wants (kept loaded)
local loopId = 0
local stops = 0           -- sent to the interface when the preview ends on its own
local dataCache = {}      -- plate -> server data (cleared when the menu closes)
-- server callback -> failed-answer count (older server files that lack it). Two misses mark
-- it unavailable; Preview.reset() (menu close) forgets them so one slow reply never disables
-- the preview for good.
local unavailable = {}
local UNAVAILABLE_AFTER = 2
local RATE_RETRY_MS = 300 -- server rate limit hit (fast browsing): wait this long, retry once

local function ok(data) return NZ.Utils.ok(data) end

-- PlayerPedId(), not ox_lib's cache.ped: always the current ped, even right after a respawn.
local function incapacitated()
  local ped = PlayerPedId()
  if ped and ped ~= 0 and IsEntityDead(ped) then return true end
  return type(NZ.Points.incapacitated) == 'function' and NZ.Points.incapacitated() == true
end

local function validEntity(e)
  return type(e) == 'number' and e ~= 0 and DoesEntityExist(e)
end

local function deleteVehicle(vehicle)
  if not validEntity(vehicle) then return end
  SetEntityAsMissionEntity(vehicle, true, true)
  local okDel = pcall(NZ.Veh.delete, vehicle)
  if (not okDel or DoesEntityExist(vehicle)) then
    DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
  end
end

local function dimsOf(hash)
  local mn, mx = GetModelDimensions(hash)
  if mn == nil or mx == nil then return nil end
  local okRead, res = pcall(function()
    return { min = { x = mn.x + 0.0, y = mn.y + 0.0, z = mn.z + 0.0 }, max = { x = mx.x + 0.0, y = mx.y + 0.0, z = mx.z + 0.0 } }
  end)
  if not okRead or type(res) ~= 'table' then return nil end
  if res.max.x - res.min.x < 0.2 or res.max.y - res.min.y < 0.2 then return nil end
  return res
end

local function studioSpot()
  local fixed = NZ.Utils.v4(cfg('studio'))
  if fixed then return { x = fixed.x, y = fixed.y, z = fixed.z, w = fixed.w or 0.0, fixed = true } end
  local p = GetEntityCoords(PlayerPedId())
  local px, py, pz = 0.0, 0.0, 0.0
  if p then px, py, pz = p.x or 0.0, p.y or 0.0, p.z or 0.0 end
  local z = math.max(pz + (tonumber(cfg('height')) or DEFAULTS.height), tonumber(cfg('minZ')) or DEFAULTS.minZ)
  return { x = px, y = py, z = z, w = 0.0, fixed = false }
end

local function frameOptions()
  return { fov = cfg('fov'), pitch = cfg('pitch'), yaw = cfg('yaw'), fill = cfg('fill') }
end

--- Point the camera at the current vehicle for the current rect (no interpolation: the
--- vehicle is faded out whenever this changes the framing noticeably).
local function applyFrame()
  if not state.cam or not state.studio then return end
  local frame = Preview.computeFrame(state.studio, state.dims, rect, frameOptions())
  state.frame = frame
  SetCamCoord(state.cam, frame.pos.x + 0.0, frame.pos.y + 0.0, frame.pos.z + 0.0)
  SetCamRot(state.cam, frame.rot.x + 0.0, frame.rot.y + 0.0, frame.rot.z + 0.0, 2)
  SetCamFov(state.cam, frame.fov + 0.0)
end

local function setAlpha(vehicle, alpha)
  if not validEntity(vehicle) then return end
  if alpha >= 255 then
    ResetEntityAlpha(vehicle)
  else
    SetEntityAlpha(vehicle, math.max(0, math.floor(alpha)), false)
  end
end

local function fadeTo(target, ms)
  state.alphaFrom = state.alphaTo
  if validEntity(state.vehicle) then
    local cur = GetEntityAlpha(state.vehicle)
    if tonumber(cur) then state.alphaFrom = tonumber(cur) end
  end
  state.alphaTo = target
  state.alphaStart = GetGameTimer()
  state.alphaDur = math.max(1, ms)
end

local function lights()
  if cfg('lights') == false or not state.frame then return end
  local hour = tonumber(GetClockHours()) or 12
  local night = hour < 7 or hour >= 20
  local t, c = state.frame.target, state.frame.pos
  local d = state.frame.distance or 8.0
  local strength = night and 2.6 or 0.7
  -- key light between camera and car, above; rim light behind the car
  local kx, ky, kz = c.x + (t.x - c.x) * 0.45, c.y + (t.y - c.y) * 0.45, c.z + (t.z - c.z) * 0.45 + 2.5
  DrawLightWithRange(kx + 0.0, ky + 0.0, kz + 0.0, 255, 250, 240, d * 1.5 + 0.0, strength + 0.0)
  local rx, ry, rz = t.x + (t.x - c.x) * 0.35, t.y + (t.y - c.y) * 0.35, t.z + 2.0
  DrawLightWithRange(rx + 0.0, ry + 0.0, rz + 0.0, 200, 230, 255, d * 1.1 + 0.0, strength * 0.6 + 0.0)
end

---------------------------------------------------------------------------------------
-- Camera session
---------------------------------------------------------------------------------------

local function notifyStopped()
  if not state.app then return end
  stops = stops + 1
  NZ.NUI.send('update', { app = state.app, data = { previewStopped = stops } })
end

local function endCamera()
  if state.cam then
    if DoesCamExist(state.cam) then
      SetCamActive(state.cam, false)
      DestroyCam(state.cam, false)
    end
    state.cam = nil
  end
  if state.rendering then
    RenderScriptCams(false, false, 0, true, true)
    state.rendering = false
  end
  state.pendingRender = false
  if state.focus then
    ClearFocus()
    state.focus = false
  end
end

--- End the preview: delete the vehicle, give the gameplay camera back.
--- `tell` = true informs the interface (the menu stays open: stage back to the image).
---@param tell boolean|nil
function Preview.stop(tell)
  token = token + 1
  pendingHash = nil
  loopId = loopId + 1
  local wasActive = state.active or state.vehicle ~= nil or state.cam ~= nil
  deleteVehicle(state.vehicle)
  state.vehicle = nil
  state.key = nil
  state.dims = nil
  state.frame = nil
  endCamera()
  state.active = false
  if tell and wasActive then notifyStopped() end
  state.app = nil
end

--- Whether a preview vehicle is on screen.
---@return boolean
function Preview.active()
  return state.active and validEntity(state.vehicle)
end

local function renderLoop(id)
  CreateThread(function()
    local last = GetGameTimer()
    local nextCheck = 0
    local speed = tonumber(cfg('speed')) or DEFAULTS.speed
    while loopId == id and state.active do
      local now = GetGameTimer()
      local dt = math.min(0.1, math.max(0, (now - last) / 1000))
      last = now
      HideHudAndRadarThisFrame()
      local vehicle = state.vehicle
      if validEntity(vehicle) then
        state.heading = (state.heading + speed * dt) % 360.0
        SetEntityRotation(vehicle, 0.0, 0.0, state.heading + 0.0, 2, true)
        if state.alphaDur > 0 then
          local k = math.min(1.0, (now - state.alphaStart) / state.alphaDur)
          setAlpha(vehicle, state.alphaFrom + (state.alphaTo - state.alphaFrom) * k)
          if k >= 1.0 then state.alphaDur = 0 end
        end
        lights()
      end
      if now >= nextCheck then
        nextCheck = now + 400
        if not state.app or not NZ.NUI.isOpen(state.app) then
          Preview.stop(false)
          break
        end
        if incapacitated() then
          Preview.stop(true)
          break
        end
      end
      Wait(0)
    end
  end)
end

local function beginCamera(app)
  state.app = app
  if state.active then return true end
  state.studio = studioSpot()
  if state.studio.fixed then
    SetFocusPosAndVel(state.studio.x + 0.0, state.studio.y + 0.0, state.studio.z + 0.0, 0.0, 0.0, 0.0)
    state.focus = true
  end
  local frame = Preview.computeFrame(state.studio, state.dims, rect, frameOptions())
  local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', frame.pos.x + 0.0, frame.pos.y + 0.0, frame.pos.z + 0.0,
    frame.rot.x + 0.0, frame.rot.y + 0.0, frame.rot.z + 0.0, frame.fov + 0.0, false, 2)
  if not cam or cam == -1 or cam == 0 then
    endCamera()
    return false
  end
  state.cam = cam
  state.frame = frame
  SetCamActive(cam, true)
  -- RenderScriptCams follows in show(), once the interface has been told (renderDelay)
  state.pendingRender = true
  state.active = true
  loopId = loopId + 1
  renderLoop(loopId)
  return true
end

---------------------------------------------------------------------------------------
-- Vehicle
---------------------------------------------------------------------------------------

local function missed(callback, permanent)
  unavailable[callback] = permanent and UNAVAILABLE_AFTER or (unavailable[callback] or 0) + 1
end

--- One server round trip: result table, or nil on timeout.
local function askServer(callback, plate)
  local result, done = nil, false
  CreateThread(function()
    result = NZ.NUI.await(callback, { plate = plate })
    done = true
  end)
  local deadline = GetGameTimer() + (tonumber(cfg('dataTimeout')) or DEFAULTS.dataTimeout)
  while not done and GetGameTimer() < deadline do Wait(25) end
  if not done then return nil end
  return result
end

--- Server data of a stored vehicle (cached for the menu session), or nil.
--- Without a server callback (spawner vehicles) the target's own `data` is used.
local function vehicleData(target, my)
  local callback = target.callback
  if not callback then return type(target.data) == 'table' and target.data or {} end
  local p = NZ.Utils.plate(target.plate)
  if not p then return nil end
  if dataCache[p] then return dataCache[p] end
  if (unavailable[callback] or 0) >= UNAVAILABLE_AFTER then return nil end
  local wait = L('Please wait a moment before trying again')
  local result
  for attempt = 1, 2 do
    result = askServer(callback, p)
    if type(result) == 'table' and result.ok and type(result.data) == 'table' then
      dataCache[p] = result.data -- kept for the menu session even when this request went stale
    end
    if my ~= token then return nil end
    -- An ox_lib without callback validation never answers a callback nobody registered;
    -- a single slow reply only counts once (see UNAVAILABLE_AFTER).
    if result == nil then missed(callback, false) return nil end
    -- Browsing one key press at a time can outrun the server's rate limit: wait and retry
    -- once instead of dropping the camera (the stage would flicker back to the image).
    if attempt == 1 and type(result) == 'table' and not result.ok and result.error == wait then
      Wait(RATE_RETRY_MS)
      if my ~= token then return nil end
    else
      break
    end
  end
  if type(result) ~= 'table' or not result.ok or type(result.data) ~= 'table' then
    if type(result) == 'table' and result.error == L('The server did not respond, try again') then
      missed(callback, true)
    end
    return nil
  end
  return result.data
end

local function decode(value)
  if type(value) == 'table' then return value end
  if type(value) == 'string' and value ~= '' then
    local okDec, res = pcall(json.decode, value)
    if okDec and type(res) == 'table' then return res end
  end
  return nil
end

local function applyData(vehicle, data, plate)
  local props = decode(data.props)
  if props then
    local okSet, err = pcall(lib.setVehicleProperties, vehicle, props)
    if not okSet then NZ.Utils.debug('preview setVehicleProperties failed:', err) end
  end
  local text = plate or (props and props.plate)
  if type(text) == 'string' and text ~= '' then SetVehicleNumberPlateText(vehicle, text:sub(1, 8)) end
  -- spawner (job / rental) vehicles: configured livery, extras, performance mods
  if type(data.mods) == 'table' and NZ.JobsClient and type(NZ.JobsClient.applyMods) == 'function' then
    local okMods, err = pcall(NZ.JobsClient.applyMods, vehicle, data.mods)
    if not okMods then NZ.Utils.debug('preview applyMods failed:', err) end
  end
  local damage = decode(data.damage)
  if damage then
    local copy = {}
    for k, v in pairs(damage) do copy[k] = v end
    local engine, body = tonumber(data.engine), tonumber(data.body)
    if not copy.engine and engine then copy.engine = engine * 10.0 end
    if not copy.body and body then copy.body = body * 10.0 end
    pcall(NZ.Damage.apply, vehicle, copy)
  end
end

local function spawnLocal(hash, data, plate)
  local s = state.studio
  local vehicle = CreateVehicle(hash, s.x + 0.0, s.y + 0.0, s.z + 0.0, state.heading + 0.0, false, false)
  SetModelAsNoLongerNeeded(hash)
  if not validEntity(vehicle) then return nil end
  -- Frozen in the same frame it is created: no physics tick, so the suspension never droops.
  FreezeEntityPosition(vehicle, true)
  SetEntityCollision(vehicle, false, false)
  SetEntityAlpha(vehicle, 0, false)
  SetEntityAsMissionEntity(vehicle, true, true)
  SetEntityInvincible(vehicle, true)
  SetVehicleDoorsLocked(vehicle, 2)
  SetVehicleEngineOn(vehicle, false, true, true)
  SetVehRadioStation(vehicle, 'OFF')
  SetVehicleRadioEnabled(vehicle, false)
  SetEntityLodDist(vehicle, 1000)
  local okApply, err = pcall(applyData, vehicle, data or {}, plate)
  if not okApply then lib.print.warn(('[nayzeee-garages] preview data failed: %s'):format(err)) end
  SetEntityCoordsNoOffset(vehicle, s.x + 0.0, s.y + 0.0, s.z + 0.0, false, false, false)
  return vehicle
end

local function waitAlpha(my)
  while state.alphaDur > 0 and my == token do Wait(0) end
  return my == token
end

--- A superseded request loaded a model it will not spawn: let the game evict it again,
--- unless the vehicle on show or the newest request still needs it.
local function releaseModel(hash)
  if not hash or hash == pendingHash then return end
  if validEntity(state.vehicle) and GetEntityModel(state.vehicle) == hash then return end
  SetModelAsNoLongerNeeded(hash)
end

--- Show a vehicle in the preview (call from a thread; it waits for data and the model).
--- target = { key, hash, plate?, callback? ('nz:garage:preview' | 'nz:impound:preview'),
--- data? (used when there is no callback: { props?, mods? }) }.
--- Returns ok({ shown = boolean, disabled = true? }) — shown = false means the interface
--- keeps (or goes back to) the image.
---@param app string 'garage' | 'impound'
---@param target table|nil
---@return table
function Preview.show(app, target)
  if not Preview.enabled() then
    if state.active then Preview.stop(false) end
    return ok({ shown = false, disabled = true })
  end
  if type(target) ~= 'table' or not tonumber(target.hash) or not NZ.NUI.isOpen(app) then
    Preview.stop(false)
    return ok({ shown = false })
  end
  if incapacitated() or (NZ.Camera.isPlaying and NZ.Camera.isPlaying()) then
    Preview.stop(false)
    return ok({ shown = false })
  end
  if state.active and state.app == app and state.key == target.key and validEntity(state.vehicle) then
    -- Back to the car on show while a swap to another one may still be loading / fading it
    -- out: cancel that swap (its token checks make it return stale without deleting this car)
    -- and bring this one back to full alpha.
    token = token + 1
    pendingHash = GetEntityModel(state.vehicle)
    if state.alphaTo ~= 255 then fadeTo(255, tonumber(cfg('fadeIn')) or DEFAULTS.fadeIn) end
    return ok({ shown = true })
  end

  token = token + 1
  local my = token
  local hash = math.tointeger(tonumber(target.hash)) or tonumber(target.hash)
  pendingHash = hash

  local data = vehicleData(target, my)
  if my ~= token then return ok({ shown = false, stale = true }) end
  if not data then
    Preview.stop(false)
    return ok({ shown = false })
  end
  if not NZ.Veh.requestModel(hash, tonumber(cfg('modelTimeout')) or DEFAULTS.modelTimeout) then
    if my == token then Preview.stop(false) end
    return ok({ shown = false })
  end
  if my ~= token then
    releaseModel(hash)
    return ok({ shown = false, stale = true })
  end

  -- fade the previous vehicle out (the camera keeps rendering it while it turns)
  if validEntity(state.vehicle) then
    fadeTo(0, tonumber(cfg('fadeOut')) or DEFAULTS.fadeOut)
    if not waitAlpha(my) then
      releaseModel(hash)
      return ok({ shown = false, stale = true })
    end
    deleteVehicle(state.vehicle)
    state.vehicle = nil
  end
  if not NZ.NUI.isOpen(app) then
    Preview.stop(false)
    return ok({ shown = false })
  end

  state.dims = dimsOf(hash)
  if not beginCamera(app) then
    Preview.stop(false)
    return ok({ shown = false })
  end
  local vehicle = spawnLocal(hash, data, target.plate)
  if my ~= token then
    deleteVehicle(vehicle)
    return ok({ shown = false, stale = true })
  end
  if not vehicle then
    Preview.stop(false)
    return ok({ shown = false })
  end
  state.vehicle = vehicle
  state.key = target.key
  applyFrame()
  state.alphaTo = 0
  local fadeIn = tonumber(cfg('fadeIn')) or DEFAULTS.fadeIn
  if state.pendingRender then
    -- First vehicle of the session: switch cameras only after the interface went see-through,
    -- so the studio never flashes around the window.
    state.pendingRender = false
    local cam = state.cam
    CreateThread(function()
      Wait(tonumber(cfg('renderDelay')) or DEFAULTS.renderDelay)
      if state.cam ~= cam or not state.active then return end
      -- the camera is needed by a newer request too; the fade-in only by this one (a newer
      -- swap may already be fading this car out)
      RenderScriptCams(true, false, 0, true, true)
      state.rendering = true
      if my == token then fadeTo(255, fadeIn) end
    end)
  else
    fadeTo(255, fadeIn)
  end
  return ok({ shown = true })
end

--- New stage rectangle from the interface ({ x, y, w, h, vw?, vh?, dpr? } CSS px).
---@param raw table
---@return boolean changed
function Preview.setRect(raw)
  local sw, sh = GetActiveScreenResolution()
  local nextRect = Preview.normalizeRect(raw, sw, sh)
  if not nextRect then return false end
  if rect and math.abs(rect.x - nextRect.x) < 0.001 and math.abs(rect.y - nextRect.y) < 0.001
    and math.abs(rect.w - nextRect.w) < 0.001 and math.abs(rect.h - nextRect.h) < 0.001
    and math.abs(rect.aspect - nextRect.aspect) < 0.001 then
    return false
  end
  rect = nextRect
  if state.active then applyFrame() end
  return true
end

--- Forget cached vehicle data and missed server callbacks (menu closed / reopened).
function Preview.reset()
  dataCache = {}
  unavailable = {}
end

---------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  Preview.stop(false)
end)
