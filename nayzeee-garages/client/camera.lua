--[[
  nayzeee-garages — scripted camera paths (NZ.Camera).
  Plays a cinematic path through CameraPoints ({ coords, rot, fov }) with interpolated
  scripted cams and returns to the gameplay camera; also reads the current gameplay
  camera as a CameraPoint (interior creator). Used by the interior entry cutscene and the
  creator preview (docs/ARCHITECTURE.md §4.3, §6, §7.7).
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
