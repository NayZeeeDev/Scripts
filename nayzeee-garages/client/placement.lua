--[[
  nayzeee-garages — in-world placement tools (NZ.Placement, docs/ARCHITECTURE.md §7.6).
  vehicle(): a ghost vehicle (local, see-through, teal outline) that follows the crosshair
  and is fine-tuned with W/A/S/D, scroll, R/F; point(): the same with a marker;
  manage(): walk around and add / remove the spawn, open or store points of a location.
  Per-frame work only while a tool is active; every ghost is deleted when it ends.
]]

local Placement = NZ.Placement
local Utils = NZ.Utils

local MOVE_STEP = 0.05        -- metres per frame (60 fps) for W/A/S/D and R/F
local FAST = 4.0              -- Shift multiplier
local TURN_STEP = 5.0         -- degrees per scroll notch
local TURN_STEP_FAST = 15.0   -- with Shift
local RAY_DISTANCE = 25.0
local GRACE_MS = 300          -- ignore confirm / cancel right after a tool starts
local REMOVE_RADIUS = 3.0
local LABEL_DISTANCE = 60.0
local GHOST_ALPHA = 180

local OUTLINE = { 8, 175, 162, 255 }

local REPRESENTATIVE = { car = 'sultan', sea = 'dinghy', air = 'frogger' }

-- Controls
local C = {
  W = 32, S = 33, A = 34, D = 35,
  SHIFT = 21,
  UP = { 45, 140 },             -- R
  DOWN = { 23, 49 },            -- F
  SCROLL_UP = { 15, 241 },
  SCROLL_DOWN = { 14, 242 },
  LMB = 24,
  E = 38,
  X = 73,
  CONFIRM = { 191, 201 },       -- Enter
  CANCEL = { 200, 202, 194 },   -- Esc / Backspace
}

-- Disabled every frame while a tool runs: attack, aim, weapon wheel / scroll weapon,
-- jump, cover, melee, reload, enter / exit vehicle, pause menu.
local BLOCKED = {
  24, 25, 37, 14, 15, 16, 17, 99, 100, 115, 116, 241, 242, 261, 262, 22, 44, 140, 141, 142,
  143, 257, 263, 264, 23, 49, 75, 45, 47, 58, 80, 199, 200, 202, 194, 191, 201,
}
-- Additionally disabled while fine-tuning (the ped must not walk while W/A/S/D move the ghost).
local MOVEMENT = { 30, 31, 32, 33, 34, 35, 21, 36 }
-- Additionally disabled by the point manager (E / X are its keys).
local MANAGER_KEYS = { 38, 51, 73 }
-- Vehicle controls (accelerate / brake / steer / handbrake / horn): disabled while zoning, in
-- case the admin ends up in a vehicle (the editor refuses to start the tool in one).
local VEHICLE_KEYS = { 59, 60, 61, 62, 63, 64, 71, 72, 76, 86 }

local ghosts = {}             -- [entity] = true, every ghost created by this module
local toolActive = false      -- vehicle() / point() running
local managing = false        -- manage() running
local zoning = false          -- zone() running
local zoneCam = nil           -- fly camera of the zone tool

---------------------------------------------------------------------------------------
-- Generic helpers
---------------------------------------------------------------------------------------

local function anyJustReleased(list)
  for i = 1, #list do
    if IsDisabledControlJustReleased(0, list[i]) then return true end
  end
  return false
end

local function anyJustPressed(list)
  for i = 1, #list do
    if IsDisabledControlJustPressed(0, list[i]) then return true end
  end
  return false
end

local function anyPressed(list)
  for i = 1, #list do
    if IsDisabledControlPressed(0, list[i]) then return true end
  end
  return false
end

local function disableAll(list)
  for i = 1, #list do DisableControlAction(0, list[i], true) end
end

local function frameScale()
  local ft = tonumber(GetFrameTime()) or (1.0 / 60.0)
  return Utils.clamp(ft * 60.0, 0.25, 3.0)
end

local function normalizeHeading(h)
  h = (tonumber(h) or 0.0) % 360.0
  if h < 0 then h = h + 360.0 end
  return h
end

local function pedPosition()
  local ped = PlayerPedId()
  local c = Utils.v3(GetEntityCoords(ped)) or { x = 0.0, y = 0.0, z = 0.0 }
  return c.x, c.y, c.z, tonumber(GetEntityHeading(ped)) or 0.0
end

local function sound(name)
  PlaySoundFrontend(-1, name, 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function toHash(model)
  if type(model) == 'number' then return math.tointeger(model) or math.floor(model) end
  if type(model) == 'string' and model ~= '' then
    local n = tonumber(model)
    if n then return math.tointeger(n) or math.floor(n) end
    return joaat(model)
  end
  return nil
end

--- Load a vehicle model (blocking). Returns true when it can be used.
local function loadModel(hash)
  if not hash or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end
  if HasModelLoaded(hash) then return true end
  local ok = pcall(lib.requestModel, hash, 10000)
  return (ok and HasModelLoaded(hash)) == true
end

--- Ground (or water surface) height under x, y searching down from z.
local function groundAt(x, y, z, water)
  local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 1.5, false)
  local result = (found and tonumber(gz)) or nil
  if water then
    local wFound, wz = GetWaterHeight(x + 0.0, y + 0.0, z + 1.5)
    wz = tonumber(wz)
    if wFound and wz and (not result or wz > result) then result = wz end
  end
  return result
end

--- Camera forward vector from a rotation (degrees, order 2).
local function rotationToDirection(rot)
  local rx, rz = math.rad(rot.x), math.rad(rot.z)
  local cx = math.abs(math.cos(rx))
  return -math.sin(rz) * cx, math.cos(rz) * cx, math.sin(rx)
end

--- Asynchronous crosshair raycast: start a probe one frame, read it the next.
local function newProbe()
  return { handle = nil, hit = nil }
end

--- `from` / `rot` / `distance`: cast from another camera (fly camera of the zone tool).
local function updateProbe(probe, ignore, from, rot, distance)
  if probe.handle then
    local status, hit, endCoords = GetShapeTestResult(probe.handle)
    if status == 2 then
      probe.handle = nil
      local didHit = hit == true or hit == 1
      local c = didHit and Utils.v3(endCoords) or nil
      if c and (c.x ~= 0.0 or c.y ~= 0.0 or c.z ~= 0.0) then
        probe.hit = c
        probe.missed = false
      else
        probe.hit = probe.endPoint
        probe.missed = true
      end
    elseif status ~= 1 then
      probe.handle = nil
    end
    return probe.hit
  end
  from = from or Utils.v3(GetGameplayCamCoord())
  rot = rot or Utils.v3(GetGameplayCamRot(2))
  if not from or not rot then return probe.hit end
  local dx, dy, dz = rotationToDirection(rot)
  local reach = distance or RAY_DISTANCE
  local tx, ty, tz = from.x + dx * reach, from.y + dy * reach, from.z + dz * reach
  probe.endPoint = { x = tx, y = ty, z = tz }
  probe.handle = StartShapeTestLosProbe(from.x, from.y, from.z, tx, ty, tz, 1 | 16, ignore or PlayerPedId(), 7)
  return probe.hit
end

---------------------------------------------------------------------------------------
-- Drawing helpers (also used by the interior creator)
---------------------------------------------------------------------------------------

--- Draw centred 3D text at a world position (call every frame).
--- Projects the point to the screen and draws 2D text there instead of using
--- SetDrawOrigin: the game accepts only 32 draw origins per frame (shared with every
--- other resource), and the editors can show up to 60+ labels at once.
---@param x number
---@param y number
---@param z number
---@param text string
---@param scale number|nil
function Placement.drawText3D(x, y, z, text, scale)
  local onScreen, sx, sy = GetScreenCoordFromWorldCoord(x + 0.0, y + 0.0, z + 0.0)
  sx, sy = tonumber(sx), tonumber(sy)
  if not onScreen or not sx or not sy then return end
  if type(text) ~= 'string' then text = tostring(text) end
  SetTextScale(0.0, scale or 0.4)
  SetTextFont(4)
  SetTextProportional(true)
  SetTextColour(255, 255, 255, 235)
  SetTextOutline()
  SetTextCentre(true)
  BeginTextCommandDisplayText('STRING')
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(sx, sy)
end

local function drawPointMarker(x, y, z, heading, radius, alpha)
  local r, g, b = OUTLINE[1], OUTLINE[2], OUTLINE[3]
  local d = (radius or 0.6) * 2.0
  DrawMarker(25, x + 0.0, y + 0.0, z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 1.0,
    r, g, b, alpha or 150, false, false, 2, false, nil, nil, false)
  DrawMarker(20, x + 0.0, y + 0.0, z + 1.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.35, 0.35, 0.25,
    r, g, b, 210, true, false, 2, true, nil, nil, false)
  if heading then
    local h = math.rad(heading)
    local fx, fy = -math.sin(h), math.cos(h)
    DrawLine(x + 0.0, y + 0.0, z + 0.05, x + fx * 1.2, y + fy * 1.2, z + 0.05, r, g, b, 255)
  end
end

---------------------------------------------------------------------------------------
-- Ghost vehicles
---------------------------------------------------------------------------------------

--- Delete a ghost created by this module.
---@param entity integer|nil
function Placement.removeGhost(entity)
  if not entity or entity == 0 then return end
  ghosts[entity] = nil
  if DoesEntityExist(entity) then
    SetEntityAsMissionEntity(entity, true, true)
    DeleteVehicle(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
  end
end

--- Create a local, see-through, outlined vehicle without collision at `coords`
--- ({x,y,z,w}; z is the vehicle origin). The model must be loadable.
---@param model string|number spawn name or hash
---@param coords table {x,y,z,w}
---@param alpha integer|nil default 180
---@return integer|nil entity
function Placement.createGhost(model, coords, alpha)
  local hash = toHash(model)
  local c = Utils.v4(coords)
  if not hash or not c or not loadModel(hash) then return nil end
  local veh = CreateVehicle(hash, c.x + 0.0, c.y + 0.0, c.z + 0.0, c.w + 0.0, false, false)
  if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
  ghosts[veh] = true
  SetEntityAsMissionEntity(veh, true, true)
  SetEntityCollision(veh, false, false)
  FreezeEntityPosition(veh, true)
  SetEntityInvincible(veh, true)
  SetEntityCanBeDamaged(veh, false)
  SetVehicleDoorsLocked(veh, 2)
  SetVehicleEngineOn(veh, false, true, true)
  SetVehicleDirtLevel(veh, 0.0)
  SetVehicleNumberPlateText(veh, 'NAYZEEE')
  SetEntityAlpha(veh, alpha or GHOST_ALPHA, false)
  SetEntityDrawOutline(veh, true)
  SetEntityDrawOutlineColor(OUTLINE[1], OUTLINE[2], OUTLINE[3], OUTLINE[4])
  SetEntityDrawOutlineShader(1)
  SetEntityCoordsNoOffset(veh, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
  SetEntityHeading(veh, c.w + 0.0)
  return veh
end

--- Move an existing ghost.
---@param entity integer
---@param coords table {x,y,z,w}
function Placement.moveGhost(entity, coords)
  local c = Utils.v4(coords)
  if not c or not entity or not DoesEntityExist(entity) then return end
  SetEntityCoordsNoOffset(entity, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false)
  SetEntityHeading(entity, c.w + 0.0)
end

---------------------------------------------------------------------------------------
-- Fine-tune tool (vehicle / point)
---------------------------------------------------------------------------------------

local function toolHint(title)
  return {
    title = title,
    keys = {
      { keys = { 'W', 'A', 'S', 'D' }, label = L('Move') },
      { keys = { 'Scroll' }, label = L('Rotate') },
      { keys = { 'R' }, label = L('Up') },
      { keys = { 'F' }, label = L('Down') },
      { keys = { 'LMB' }, label = L('Follow aim') },
      { keys = { 'Enter' }, label = L('Confirm') },
      { keys = { 'Esc' }, label = L('Cancel') },
    },
  }
end

--- Shared loop of vehicle() and point().
--- spec = { hash (vehicle only), baseOffset, water, start, title }
local function runTool(spec)
  local isVehicle = spec.hash ~= nil
  local base = spec.baseOffset or 0.0
  local probe = newProbe()
  local st = { x = 0.0, y = 0.0, ground = 0.0, zOff = 0.0, w = 0.0, follow = true }

  local start = Utils.v4(spec.start)
  local px, py, pz, ph = pedPosition()
  if start then
    st.x, st.y, st.w, st.follow = start.x, start.y, normalizeHeading(start.w), false
    local g = groundAt(start.x, start.y, start.z, spec.water)
    if g and math.abs((start.z - base) - g) < 5.0 then
      st.ground, st.zOff = g, (start.z - base) - g
    else
      st.ground, st.zOff = start.z - base, 0.0
    end
  else
    local h = math.rad(ph)
    st.x, st.y, st.w = px - math.sin(h) * 4.0, py + math.cos(h) * 4.0, normalizeHeading(ph + 90.0)
    st.ground = groundAt(st.x, st.y, pz, spec.water) or (pz - 1.0)
  end

  local ghost = nil
  if isVehicle then
    ghost = Placement.createGhost(spec.hash, { x = st.x, y = st.y, z = st.ground + base, w = st.w }, GHOST_ALPHA)
    if not ghost then
      NZ.NUI.notify('error', L('Could not load the vehicle model'))
      return nil
    end
  end

  NZ.NUI.hint(toolHint(spec.title))
  local graceUntil = GetGameTimer() + GRACE_MS
  local result = nil

  local ok, err = pcall(function()
    while true do
      disableAll(BLOCKED)
      disableAll(MOVEMENT)

      local scale = frameScale()
      local fast = IsDisabledControlPressed(0, C.SHIFT)
      local step = MOVE_STEP * scale * (fast and FAST or 1.0)

      -- Toggle "follow the crosshair".
      if IsDisabledControlJustPressed(0, C.LMB) then st.follow = not st.follow end

      -- Horizontal fine tune relative to the camera heading.
      local fwd, right = 0.0, 0.0
      if IsDisabledControlPressed(0, C.W) then fwd = fwd + 1.0 end
      if IsDisabledControlPressed(0, C.S) then fwd = fwd - 1.0 end
      if IsDisabledControlPressed(0, C.D) then right = right + 1.0 end
      if IsDisabledControlPressed(0, C.A) then right = right - 1.0 end
      local vertical = 0.0
      if anyPressed(C.UP) then vertical = vertical + 1.0 end
      if anyPressed(C.DOWN) then vertical = vertical - 1.0 end

      if fwd ~= 0.0 or right ~= 0.0 or vertical ~= 0.0 then st.follow = false end

      if st.follow then
        local hit = updateProbe(probe, ghost)
        if hit then
          st.x, st.y = hit.x, hit.y
          st.ground = groundAt(hit.x, hit.y, hit.z, spec.water) or hit.z
          st.zOff = 0.0
        end
      elseif fwd ~= 0.0 or right ~= 0.0 then
        local camRot = Utils.v3(GetGameplayCamRot(2)) or { x = 0.0, y = 0.0, z = 0.0 }
        local h = math.rad(camRot.z)
        local fx, fy = -math.sin(h), math.cos(h)
        local rx, ry = math.cos(h), math.sin(h)
        st.x = st.x + (fx * fwd + rx * right) * step
        st.y = st.y + (fy * fwd + ry * right) * step
        local g = groundAt(st.x, st.y, st.ground + st.zOff + 1.0, spec.water)
        if g then
          -- Keep the absolute height when the floor under the new spot changes.
          local absolute = st.ground + st.zOff
          st.ground = g
          st.zOff = absolute - g
          if math.abs(st.zOff) < 0.35 then st.zOff = 0.0 end
        end
      end

      if vertical ~= 0.0 then st.zOff = st.zOff + vertical * step end

      if anyJustPressed(C.SCROLL_UP) then
        st.w = normalizeHeading(st.w + (fast and TURN_STEP_FAST or TURN_STEP))
      elseif anyJustPressed(C.SCROLL_DOWN) then
        st.w = normalizeHeading(st.w - (fast and TURN_STEP_FAST or TURN_STEP))
      end

      local z = st.ground + st.zOff
      if ghost then
        if not DoesEntityExist(ghost) then return end
        SetEntityCoordsNoOffset(ghost, st.x + 0.0, st.y + 0.0, z + base, false, false, false)
        SetEntityHeading(ghost, st.w + 0.0)
      else
        drawPointMarker(st.x, st.y, z, st.w, 0.6, 160)
      end

      if GetGameTimer() >= graceUntil then
        if anyJustReleased(C.CONFIRM) then
          sound('SELECT')
          result = {
            x = Utils.round(st.x, 3),
            y = Utils.round(st.y, 3),
            z = Utils.round(z + base, 3),
            w = Utils.round(st.w, 2),
          }
          return
        elseif anyJustReleased(C.CANCEL) then
          sound('BACK')
          return
        end
      end
      Wait(0)
    end
  end)

  NZ.NUI.hint(nil)
  if ghost then Placement.removeGhost(ghost) end
  if not ok then
    lib.print.error(('[nayzeee-garages] placement tool failed: %s'):format(err))
    return nil
  end
  return result
end

--- Place a vehicle with a ghost preview (§7.6). Blocking; call from a thread.
--- opts = { hash | model (default 'sultan'), start = {x,y,z,w} | nil, title }
--- Without `start` the ghost follows the crosshair (25 m raycast) until a fine-tune key
--- is used; LMB toggles following. Returns the vehicle origin {x,y,z,w} or nil.
---@param opts table|nil
---@return table|nil
function Placement.vehicle(opts)
  opts = type(opts) == 'table' and opts or {}
  if toolActive then return nil end
  local hash = toHash(opts.hash) or toHash(opts.model) or joaat('sultan')
  if not loadModel(hash) then
    NZ.NUI.notify('error', L('Could not load the vehicle model'))
    return nil
  end
  toolActive = true
  local minDim = GetModelDimensions(hash)
  local base = 0.5
  if type(minDim) == 'vector3' or type(minDim) == 'table' then
    base = -(tonumber(minDim.z) or -0.5)
  end
  local water = IsThisModelABoat(hash) or IsThisModelAJetski(hash)
  local ok, res = pcall(runTool, {
    hash = hash,
    baseOffset = base,
    water = water == true or water == 1,
    start = opts.start,
    title = type(opts.title) == 'string' and opts.title or L('Place vehicle'),
  })
  SetModelAsNoLongerNeeded(hash)
  toolActive = false
  if not ok then
    lib.print.error(('[nayzeee-garages] vehicle placement failed: %s'):format(res))
    return nil
  end
  return res
end

--- Place a point with a marker preview. Blocking; call from a thread.
--- The returned z is about one metre above the ground (like a standing ped's coords).
--- opts = { title, start = {x,y,z,w} | nil }
---@param opts table|nil
---@return table|nil {x,y,z,w}
function Placement.point(opts)
  opts = type(opts) == 'table' and opts or {}
  if toolActive then return nil end
  toolActive = true
  local ok, res = pcall(runTool, {
    baseOffset = 1.0,
    water = false,
    start = opts.start,
    title = type(opts.title) == 'string' and opts.title or L('Place point'),
  })
  toolActive = false
  if not ok then
    lib.print.error(('[nayzeee-garages] point placement failed: %s'):format(res))
    return nil
  end
  return res
end

--- Whether any placement tool (or the point manager) is running.
---@return boolean
function Placement.isActive()
  return toolActive or managing or zoning
end

---------------------------------------------------------------------------------------
-- Point manager
---------------------------------------------------------------------------------------

local MANAGER_TITLES = {
  spawn = 'Spawn points',
  open = 'Open points',
  store = 'Store points',
}

local function managerHint(kind, count)
  return {
    title = ('%s (%d)'):format(L(MANAGER_TITLES[kind]), count),
    keys = {
      { keys = { 'E' }, label = L('Add here') },
      { keys = { 'X' }, label = L('Remove nearest') },
      { keys = { 'Enter' }, label = L('Save') },
      { keys = { 'Esc' }, label = L('Cancel') },
    },
  }
end

local function defaultRadius(kind)
  local cfg = Config.Interaction or {}
  if kind == 'store' then return tonumber(cfg.storeRadius) or 4.0 end
  return tonumber(cfg.openRadius) or 2.0
end

--- Normalize the incoming list: Vec4[] for spawn, { coords, radius }[] otherwise.
local function normalizePoints(kind, points)
  local out = {}
  if type(points) ~= 'table' then return out end
  for i = 1, #points do
    local p = points[i]
    if kind == 'spawn' then
      local v = Utils.v4(p)
      if v then out[#out + 1] = v end
    elseif type(p) == 'table' then
      local c = Utils.v3(p.coords) or Utils.v3(p)
      if c then
        out[#out + 1] = { coords = c, radius = Utils.clamp(tonumber(p.radius) or defaultRadius(kind), 0.5, 50.0) }
      end
    end
  end
  return out
end

local function exportPoints(kind, list)
  local out = {}
  for i = 1, #list do
    local p = list[i]
    if kind == 'spawn' then
      out[#out + 1] = {
        x = Utils.round(p.x, 3), y = Utils.round(p.y, 3), z = Utils.round(p.z, 3), w = Utils.round(p.w, 2),
      }
    else
      out[#out + 1] = {
        coords = { x = Utils.round(p.coords.x, 3), y = Utils.round(p.coords.y, 3), z = Utils.round(p.coords.z, 3) },
        radius = Utils.round(p.radius, 2),
      }
    end
  end
  return out
end

local function pointCoords(kind, p)
  if kind == 'spawn' then return p end
  return p.coords
end

local function suspendWorldPoints()
  if NZ.Points and type(NZ.Points.clear) == 'function' then
    local ok, err = pcall(NZ.Points.clear)
    if not ok then lib.print.warn(('[nayzeee-garages] could not pause garage points: %s'):format(err)) end
    return ok
  end
  return false
end

local function resumeWorldPoints()
  if NZ.State.ready and NZ.Points and type(NZ.Points.rebuild) == 'function' then
    local ok, err = pcall(NZ.Points.rebuild)
    if not ok then lib.print.warn(('[nayzeee-garages] could not restore garage points: %s'):format(err)) end
  end
end

local function runManager(kind, list, model)
  local entities = {}   -- spawn ghosts (entity or false), always aligned with list
  local ghostModel = nil
  if kind == 'spawn' then
    local hash = toHash(model)
    if hash and loadModel(hash) then ghostModel = hash end
  end
  for i = 1, #list do
    entities[i] = ghostModel and Placement.createGhost(ghostModel, list[i], 150) or false
  end

  local hintCount = -1
  local graceUntil = GetGameTimer() + GRACE_MS

  while true do
    if hintCount ~= #list then
      hintCount = #list
      NZ.NUI.hint(managerHint(kind, #list))
    end

    disableAll(BLOCKED)
    disableAll(MANAGER_KEYS)

    local px, py, pz = pedPosition()
    for i = 1, #list do
      local c = pointCoords(kind, list[i])
      local dx, dy, dz = c.x - px, c.y - py, c.z - pz
      if dx * dx + dy * dy + dz * dz < LABEL_DISTANCE * LABEL_DISTANCE then
        if kind == 'spawn' then
          if not entities[i] then drawPointMarker(c.x, c.y, c.z, c.w, 1.2, 120) end
          Placement.drawText3D(c.x, c.y, c.z + 1.4, ('#%d'):format(i), 0.5)
        else
          local p = list[i]
          if not p.groundZ then
            local g = groundAt(c.x, c.y, c.z, false)
            p.groundZ = (g and math.abs(g - c.z) < 3.0) and g or (c.z - 1.0)
          end
          local z = p.groundZ
          drawPointMarker(c.x, c.y, z, nil, list[i].radius, 110)
          Placement.drawText3D(c.x, c.y, z + 1.45, ('#%d'):format(i), 0.5)
        end
      end
    end

    if GetGameTimer() >= graceUntil then
      if IsDisabledControlJustReleased(0, C.E) then
        if kind == 'spawn' then
          local pos = Placement.vehicle({
            hash = ghostModel or model,
            title = L('Place spawn point'),
          })
          hintCount = -1
          graceUntil = GetGameTimer() + GRACE_MS
          if pos then
            list[#list + 1] = pos
            entities[#list] = ghostModel and Placement.createGhost(ghostModel, pos, 150) or false
          end
        else
          local x, y, z = pedPosition()
          list[#list + 1] = { coords = { x = x, y = y, z = z }, radius = defaultRadius(kind) }
          entities[#list] = false
          sound('SELECT')
        end
      elseif IsDisabledControlJustReleased(0, C.X) then
        local best, bestDist = nil, REMOVE_RADIUS
        for i = 1, #list do
          local d = Utils.dist(pointCoords(kind, list[i]), { x = px, y = py, z = pz })
          if d <= bestDist then best, bestDist = i, d end
        end
        if best then
          if entities[best] then Placement.removeGhost(entities[best]) end
          table.remove(list, best)
          table.remove(entities, best)
          sound('BACK')
        else
          NZ.NUI.notify('warning', L('No point within {distance} m', { distance = REMOVE_RADIUS }))
        end
      elseif anyJustReleased(C.CONFIRM) then
        sound('SELECT')
        for _, e in pairs(entities) do Placement.removeGhost(e) end
        return exportPoints(kind, list)
      elseif anyJustReleased(C.CANCEL) then
        sound('BACK')
        for _, e in pairs(entities) do Placement.removeGhost(e) end
        return nil
      end
    end
    Wait(0)
  end
end

--- In-world manager for the spawn / open / store points of a location. Blocking; call
--- from a thread. E adds a point (spawn: ghost placement; open/store: where the player
--- stands, default radius from Config.Interaction), X removes the nearest within 3 m,
--- Enter saves, Esc / Backspace cancels. Garage interaction points are paused meanwhile.
--- opts = { kind = 'spawn'|'open'|'store', points, vehicleType = 'car'|'sea'|'air', model? }
--- Returns Vec4[] (spawn) or { coords, radius }[] (open / store), or nil when cancelled.
---@param opts table
---@return table|nil
function Placement.manage(opts)
  opts = type(opts) == 'table' and opts or {}
  local kind = opts.kind
  if kind ~= 'spawn' and kind ~= 'open' and kind ~= 'store' then return nil end
  if managing or toolActive then return nil end
  managing = true

  local vehicleType = Utils.vehicleTypes[opts.vehicleType] and opts.vehicleType or 'car'
  local model = REPRESENTATIVE[vehicleType]
  if type(opts.model) == 'string' and opts.model ~= '' and IsModelInCdimage(joaat(opts.model)) then
    model = opts.model
  end

  local list = normalizePoints(kind, opts.points)
  local paused = suspendWorldPoints()
  NZ.NUI.prompt(nil)

  local ok, res = pcall(runManager, kind, list, model)

  NZ.NUI.hint(nil)
  if paused then resumeWorldPoints() end
  local hash = toHash(model)
  if hash then SetModelAsNoLongerNeeded(hash) end
  managing = false
  if not ok then
    lib.print.error(('[nayzeee-garages] point manager failed: %s'):format(res))
    return nil
  end
  return res
end

---------------------------------------------------------------------------------------
-- Garage zone tool (polygon drawn in the world)
---------------------------------------------------------------------------------------

-- Same limits as server/locations.lua (ZONE): the server decides, this only warns early.
local ZONE = {
  minPoints = 3,
  maxPoints = 40,
  minEdge = 0.5,
  minArea = 10.0,
  maxArea = 40000.0,
  maxSpan = 250.0,
  minHeight = 2.0,
  maxHeight = 100.0,
  openGap = 30.0,
}
local ZONE_AIM = 60.0             -- metres: crosshair reach on foot
local ZONE_AIM_FLY = 150.0        -- ... and from the fly camera (zones are drawn from above)
local TELEPORT_JUMP = 40.0        -- metres between two frames: the player was teleported, the tool stops
local TELEPORT_SPEED = 90.0       -- m/s: over a long frame (hitch) the jump must also beat this
                                  -- speed, well above freefall or vehicle speed (tune in game)
local ZONE_SNAP = 1.5             -- metres: aiming this close to corner #1 closes the shape
local ZONE_FLOOR_BELOW = 1.0      -- default floor: under the lowest corner
local ZONE_CEILING_ABOVE = 5.0    -- default ceiling: over the highest corner (vans, trucks)
local HEIGHT_STEP = 0.25
local HEIGHT_STEP_FAST = 1.0
local FLY_SPEED = 0.18            -- metres per frame at 60 fps
local FLY_FAST = 5.0
local FLY_RANGE = 150.0           -- the camera never goes farther than this from the player
local LOOK_SPEED = 7.0            -- degrees per unit of mouse movement
local REFERENCE_DISTANCE = 80.0   -- open / spawn point markers drawn within this range
local WARN = { 229, 72, 77 }      -- --red of the interface
local GHOST = { 200, 205, 210 }   -- the zone being replaced

-- E (two control ids), X, G, Ctrl: read as disabled controls by the zone tool.
local ZONE_KEYS = { 38, 51, 73, 47, 36 }
local ZK_ADD = { 38, 51 }
local ZK_UNDO = 73
local ZK_FLY = 47
local ZK_CTRL = 36
local ZK_ESC = 200
local ZK_BACK = 194
local FLY_LOOK = { 1, 2 }

local function cross2(ax, ay, bx, by, cx, cy)
  return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local EPS = 1e-9

local function sgn(v)
  if v > EPS then return 1 elseif v < -EPS then return -1 end
  return 0
end

local function onSeg(a, b, c)
  return c.x >= math.min(a.x, b.x) - EPS and c.x <= math.max(a.x, b.x) + EPS
    and c.y >= math.min(a.y, b.y) - EPS and c.y <= math.max(a.y, b.y) + EPS
end

--- Segments a-b and c-d touch or cross (collinear overlaps count).
local function segmentsIntersect(a, b, c, d)
  local d1 = sgn(cross2(c.x, c.y, d.x, d.y, a.x, a.y))
  local d2 = sgn(cross2(c.x, c.y, d.x, d.y, b.x, b.y))
  local d3 = sgn(cross2(a.x, a.y, b.x, b.y, c.x, c.y))
  local d4 = sgn(cross2(a.x, a.y, b.x, b.y, d.x, d.y))
  if d1 * d2 < 0 and d3 * d4 < 0 then return true end
  if d1 == 0 and onSeg(c, d, a) then return true end
  if d2 == 0 and onSeg(c, d, b) then return true end
  if d3 == 0 and onSeg(a, b, c) then return true end
  if d4 == 0 and onSeg(a, b, d) then return true end
  return false
end

local function signedArea2(points)
  local n = #points
  if n < 3 then return 0.0 end
  local ox, oy = points[1].x, points[1].y
  local sum = 0.0
  for i = 1, n do
    local a, b = points[i], points[i % n + 1]
    sum = sum + (a.x - ox) * (b.y - oy) - (b.x - ox) * (a.y - oy)
  end
  return sum
end

local function area(points)
  return math.abs(signedArea2(points)) / 2.0
end

--- Two edges of the closed polygon that share no corner touch or cross.
local function selfIntersects(points)
  local n = #points
  if n < 4 then return false end
  for i = 1, n do
    local a, b = points[i], points[i % n + 1]
    for j = i + 2, n do
      if not (i == 1 and j == n) and segmentsIntersect(a, b, points[j], points[j % n + 1]) then return true end
    end
  end
  return false
end

--- The new edge (last point -> `p`) would cross an earlier edge of the open chain. The closing
--- edge is not checked here: the next corner replaces it (U / C shapes cross it on the way);
--- closeShape() checks the finished shape.
local function wouldCross(points, p)
  local n = #points
  if n < 2 then return false end
  local last = points[n]
  for i = 1, n - 2 do
    if segmentsIntersect(points[i], points[i + 1], last, p) then return true end
  end
  return false
end

--- Closing the shape right after `p` (p -> corner #1) would cross an edge between 2 and n.
--- Only a hint for the preview line, never a reason to refuse the point.
local function closingCrosses(points, p)
  local n = #points
  if n < 2 then return false end
  for i = 2, n - 1 do
    if segmentsIntersect(points[i], points[i + 1], p, points[1]) then return true end
  end
  return false
end

local function dist2d(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function distToSegment(px, py, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  local t = 0.0
  if len2 > 0 then t = Utils.clamp(((px - a.x) * dx + (py - a.y) * dy) / len2, 0.0, 1.0) end
  local cx, cy = a.x + dx * t - px, a.y + dy * t - py
  return math.sqrt(cx * cx + cy * cy)
end

local function pointInPolygon(points, x, y)
  local inside = false
  local n = #points
  local j = n
  for i = 1, n do
    local a, b = points[i], points[j]
    if (a.y > y) ~= (b.y > y) then
      local xi = (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x
      if x < xi then inside = not inside end
    end
    j = i
  end
  return inside
end

local function zoneDistance(points, x, y)
  if pointInPolygon(points, x, y) then return 0.0 end
  local best = math.huge
  for i = 1, #points do
    local d = distToSegment(x, y, points[i], points[i % #points + 1])
    if d < best then best = d end
  end
  return best
end

local function inTriangle(p, a, b, c)
  local d1 = cross2(a.x, a.y, b.x, b.y, p.x, p.y)
  local d2 = cross2(b.x, b.y, c.x, c.y, p.x, p.y)
  local d3 = cross2(c.x, c.y, a.x, a.y, p.x, p.y)
  local neg = d1 < -EPS or d2 < -EPS or d3 < -EPS
  local pos = d1 > EPS or d2 > EPS or d3 > EPS
  return not (neg and pos)
end

--- Ear clipping: triangles { i, j, k } of a simple polygon (for the translucent fill).
local function triangulate(points)
  local n = #points
  local tris = {}
  if n < 3 then return tris end
  local idx = {}
  for i = 1, n do idx[i] = i end
  local ccw = signedArea2(points) > 0
  local guard = 0
  while #idx > 3 and guard < n * n do
    guard = guard + 1
    local m = #idx
    local clipped = false
    for i = 1, m do
      local ia, ib, ic = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
      local a, b, c = points[ia], points[ib], points[ic]
      local cr = cross2(a.x, a.y, b.x, b.y, c.x, c.y)
      if (ccw and cr > EPS) or (not ccw and cr < -EPS) then
        local ear = true
        for j = 1, m do
          local ij = idx[j]
          if ij ~= ia and ij ~= ib and ij ~= ic and inTriangle(points[ij], a, b, c) then
            ear = false
            break
          end
        end
        if ear then
          tris[#tris + 1] = { ia, ib, ic }
          table.remove(idx, i)
          clipped = true
          break
        end
      end
    end
    if not clipped then break end   -- degenerate (collinear) rest: partial fill only
  end
  if #idx == 3 then tris[#tris + 1] = { idx[1], idx[2], idx[3] } end
  return tris
end

--- The first problem of a closed shape (translated, the server's wording), or nil.
local function shapeProblem(points, openPoints)
  local n = #points
  if n < ZONE.minPoints then return L('A garage zone needs at least 3 points') end
  if n > ZONE.maxPoints then return L('A garage zone can have at most {count} points', { count = ZONE.maxPoints }) end
  if selfIntersects(points) then return L('The edges of the garage zone cross each other') end
  local a = area(points)
  if a < ZONE.minArea then return L('The garage zone is too small') end
  if a > ZONE.maxArea then
    return L('The garage zone is too large (at most {size} m², it is {area} m²)', {
      size = math.floor(ZONE.maxArea), area = math.floor(a),
    })
  end
  if type(openPoints) == 'table' and #openPoints > 0 then
    local near = false
    for _, p in ipairs(openPoints) do
      if zoneDistance(points, p.x, p.y) <= ZONE.openGap then
        near = true
        break
      end
    end
    if not near then
      return L('The garage zone must be at most {distance} m from an open interaction', { distance = math.floor(ZONE.openGap) })
    end
  end
  return nil
end

--- Points of an existing zone ({ points, minZ, maxZ }) or nil.
local function readZone(raw)
  if type(raw) ~= 'table' or type(raw.points) ~= 'table' then return nil end
  local points = {}
  for _, p in ipairs(raw.points) do
    local x, y = type(p) == 'table' and tonumber(p.x), type(p) == 'table' and tonumber(p.y)
    if x and y then points[#points + 1] = { x = x, y = y } end
    if #points >= ZONE.maxPoints then break end
  end
  local minZ, maxZ = tonumber(raw.minZ), tonumber(raw.maxZ)
  if #points < 3 or not minZ or not maxZ or maxZ <= minZ then return nil end
  return { points = points, minZ = minZ, maxZ = maxZ }
end

--- Ground height under each corner of `zone` (searching down from its ceiling).
local function groundUnder(zone)
  local fallback = zone.minZ + ZONE_FLOOR_BELOW
  for _, p in ipairs(zone.points) do
    local g = groundAt(p.x, p.y, zone.maxZ, false)
    p.z = (g and g >= zone.minZ - 2.0 and g <= zone.maxZ + 1.0) and g or fallback
  end
end

local function line(a, az, b, bz, col, alpha)
  DrawLine(a.x + 0.0, a.y + 0.0, az + 0.0, b.x + 0.0, b.y + 0.0, bz + 0.0, col[1], col[2], col[3], alpha)
end

--- A triangle seen from both sides.
local function tri(a, az, b, bz, c, cz, col, alpha)
  DrawPoly(a.x + 0.0, a.y + 0.0, az + 0.0, b.x + 0.0, b.y + 0.0, bz + 0.0, c.x + 0.0, c.y + 0.0, cz + 0.0, col[1], col[2], col[3], alpha)
  DrawPoly(c.x + 0.0, c.y + 0.0, cz + 0.0, b.x + 0.0, b.y + 0.0, bz + 0.0, a.x + 0.0, a.y + 0.0, az + 0.0, col[1], col[2], col[3], alpha)
end

local function corner(p, col, size)
  local s = size or 0.22
  DrawMarker(28, p.x + 0.0, p.y + 0.0, p.z + 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, s, s, s,
    col[1], col[2], col[3], 220, false, false, 2, false, nil, nil, false)
end

---------------------------------------------------------------------------------------
-- Fly camera
---------------------------------------------------------------------------------------

local function flyStart(st)
  local from = Utils.v3(GetGameplayCamCoord()) or (function()
    local x, y, z = pedPosition()
    return { x = x, y = y, z = z + 2.0 }
  end)()
  local rot = Utils.v3(GetGameplayCamRot(2)) or { x = -20.0, y = 0.0, z = 0.0 }
  local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
  SetCamCoord(cam, from.x + 0.0, from.y + 0.0, from.z + 0.0)
  SetCamRot(cam, rot.x + 0.0, 0.0, rot.z + 0.0, 2)
  SetCamFov(cam, (tonumber(GetGameplayCamFov()) or 50.0) + 0.0)
  RenderScriptCams(true, true, 350, true, true)
  zoneCam = cam
  st.cam = cam
  st.camPos = { x = from.x, y = from.y, z = from.z }
  st.camRot = { x = Utils.clamp(rot.x, -89.0, 89.0), y = 0.0, z = rot.z }
end

local function flyStop(st)
  if st.cam then
    -- instant switch: destroying the rendering cam during an ease cuts the blend anyway
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(st.cam, false)
  end
  if zoneCam == st.cam then zoneCam = nil end
  st.cam = nil
  ClearFocus()
end

local function flyUpdate(st)
  disableAll(MOVEMENT)
  disableAll(FLY_LOOK)
  local scale = frameScale()
  local rot = st.camRot
  rot.z = normalizeHeading(rot.z - (tonumber(GetDisabledControlNormal(0, 1)) or 0.0) * LOOK_SPEED)
  rot.x = Utils.clamp(rot.x - (tonumber(GetDisabledControlNormal(0, 2)) or 0.0) * LOOK_SPEED, -89.0, 89.0)

  local fwd, right, up = 0.0, 0.0, 0.0
  if IsDisabledControlPressed(0, C.W) then fwd = fwd + 1.0 end
  if IsDisabledControlPressed(0, C.S) then fwd = fwd - 1.0 end
  if IsDisabledControlPressed(0, C.D) then right = right + 1.0 end
  if IsDisabledControlPressed(0, C.A) then right = right - 1.0 end
  if anyPressed(C.UP) then up = up + 1.0 end
  if anyPressed(C.DOWN) then up = up - 1.0 end
  local step = FLY_SPEED * scale * (IsDisabledControlPressed(0, C.SHIFT) and FLY_FAST or 1.0)
  local dx, dy, dz = rotationToDirection(rot)
  local h = math.rad(rot.z)
  local p = st.camPos
  p.x = p.x + (dx * fwd + math.cos(h) * right) * step
  p.y = p.y + (dy * fwd + math.sin(h) * right) * step
  p.z = p.z + (dz * fwd + up) * step

  -- stay near the player (streaming, and the server checks admins by their ped anyway)
  local px, py, pz = pedPosition()
  local ox, oy, oz = p.x - px, p.y - py, p.z - pz
  local d = math.sqrt(ox * ox + oy * oy + oz * oz)
  if d > FLY_RANGE then
    local k = FLY_RANGE / d
    p.x, p.y, p.z = px + ox * k, py + oy * k, pz + oz * k
  end

  SetCamCoord(st.cam, p.x + 0.0, p.y + 0.0, p.z + 0.0)
  SetCamRot(st.cam, rot.x + 0.0, 0.0, rot.z + 0.0, 2)
  -- stream the world (collision for the raycast) around the camera, not only the player
  SetFocusPosAndVel(p.x + 0.0, p.y + 0.0, p.z + 0.0, 0.0, 0.0, 0.0)
end

---------------------------------------------------------------------------------------
-- Zone tool loop
---------------------------------------------------------------------------------------

local function zoneHint(st)
  local n = #st.points
  local parts = { L('Garage zone'), L('{count} points', { count = n }) }
  if n >= 3 then parts[#parts + 1] = ('%s m²'):format(math.floor(area(st.points) + 0.5)) end
  if st.phase == 'height' then
    parts[#parts + 1] = L('{height} m high', { height = ('%.1f'):format(st.maxZ - st.minZ) })
    return {
      title = table.concat(parts, ' · '),
      keys = {
        { keys = { 'Scroll' }, label = L('Ceiling') },
        { keys = { 'Ctrl', 'Scroll' }, label = L('Floor') },
        { keys = { 'Shift' }, label = L('Faster') },
        { keys = { 'Enter' }, label = L('Save') },
        { keys = { 'Backspace' }, label = L('Edit points') },
        { keys = { 'Esc' }, label = L('Cancel') },
      },
    }
  end
  local keys = {
    { keys = { 'E' }, label = L('Add point') },
    { keys = { 'X' }, label = L('Undo') },
    { keys = { 'Enter' }, label = L('Close shape') },
    { keys = { 'G' }, label = st.fly and L('Walk') or L('Fly') },
  }
  if st.fly then
    keys[#keys + 1] = { keys = { 'W', 'A', 'S', 'D' }, label = L('Move') }
    keys[#keys + 1] = { keys = { 'R', 'F' }, label = L('Up / down') }
  end
  keys[#keys + 1] = { keys = { 'Esc' }, label = L('Cancel') }
  return { title = table.concat(parts, ' · '), keys = keys }
end

--- Start the height step: a floor under the lowest corner and a ceiling over the highest one,
--- or the replaced zone's range when it still covers every corner.
local function enterHeight(st)
  local lo, hi = math.huge, -math.huge
  for _, p in ipairs(st.points) do
    lo, hi = math.min(lo, p.z), math.max(hi, p.z)
  end
  local old = st.old
  if old and old.minZ <= lo - 0.5 and old.maxZ >= hi + ZONE.minHeight and old.maxZ - old.minZ <= ZONE.maxHeight then
    st.minZ, st.maxZ = old.minZ, old.maxZ
  else
    st.minZ, st.maxZ = lo - ZONE_FLOOR_BELOW, hi + ZONE_CEILING_ABOVE
    if st.maxZ - st.minZ > ZONE.maxHeight then st.maxZ = st.minZ + ZONE.maxHeight end
  end
  st.phase = 'height'
end

--- Close the shape: the height step when it is valid, else a warning.
local function closeShape(st, openPoints)
  local problem = shapeProblem(st.points, openPoints)
  if problem then
    sound('ERROR')
    NZ.NUI.notify('warning', problem)
    return
  end
  sound('SELECT')
  enterHeight(st)
end

--- Try to add `p` ({x, y, z} with z = ground) after the last point.
local function addPoint(st, p)
  local n = #st.points
  if n >= ZONE.maxPoints then
    sound('ERROR')
    NZ.NUI.notify('warning', L('A garage zone can have at most {count} points', { count = ZONE.maxPoints }))
    return
  end
  if n > 0 and dist2d(st.points[n], p) < ZONE.minEdge then
    sound('ERROR')
    return
  end
  for i = 1, n do
    if dist2d(st.points[i], p) > ZONE.maxSpan then
      sound('ERROR')
      NZ.NUI.notify('warning', L('The garage zone is too large (at most {size} m across)', { size = math.floor(ZONE.maxSpan) }))
      return
    end
  end
  if wouldCross(st.points, p) then
    sound('ERROR')
    NZ.NUI.notify('warning', L('This edge would cross another edge of the zone'))
    return
  end
  st.points[n + 1] = { x = p.x, y = p.y, z = p.z }
  st.rev = st.rev + 1
  sound('SELECT')
end

local function drawReferences(opts, px, py, pz)
  local maxSq = REFERENCE_DISTANCE * REFERENCE_DISTANCE
  for i, p in ipairs(opts.openPoints) do
    local dx, dy, dz = p.x - px, p.y - py, p.z - pz
    if dx * dx + dy * dy + dz * dz < maxSq then
      drawPointMarker(p.x, p.y, p.ground, nil, 0.6, 90)
      Placement.drawText3D(p.x, p.y, p.ground + 1.45, ('%s %d'):format(L('Open'), i), 0.35)
    end
  end
  for i, p in ipairs(opts.spawnPoints) do
    local dx, dy, dz = p.x - px, p.y - py, p.z - pz
    if dx * dx + dy * dy + dz * dz < maxSq then
      local h = math.rad(p.w)
      local fx, fy = -math.sin(h), math.cos(h)
      DrawLine(p.x, p.y, p.z, p.x + fx * 2.0, p.y + fy * 2.0, p.z, 255, 255, 255, 140)
      Placement.drawText3D(p.x, p.y, p.z + 0.8, ('%s %d'):format(L('Spawn'), i), 0.32)
    end
  end
end

local function drawOld(old)
  local n = #old.points
  for i = 1, n do
    local a, b = old.points[i], old.points[i % n + 1]
    line(a, a.z + 0.05, b, b.z + 0.05, GHOST, 110)
  end
end

--- Fill + outline of the placed corners (closed when `closed`).
local function drawShape(st, closed, col)
  local pts = st.points
  local n = #pts
  if closed and n >= 3 then
    if st.trisRev ~= st.rev then
      st.tris = triangulate(pts)
      st.trisRev = st.rev
    end
    for _, t in ipairs(st.tris) do
      local a, b, c = pts[t[1]], pts[t[2]], pts[t[3]]
      tri(a, a.z + 0.04, b, b.z + 0.04, c, c.z + 0.04, col, 34)
    end
  end
  for i = 1, n do
    local a = pts[i]
    if i < n or (closed and n >= 3) then
      local b = pts[i % n + 1]
      line(a, a.z + 0.06, b, b.z + 0.06, col, 230)
    end
    line(a, a.z, a, a.z + 1.2, col, 200)
    corner(a, col)
  end
end

local function drawWalls(st)
  local pts = st.points
  local n = #pts
  local lo, hi = st.minZ, st.maxZ
  for i = 1, n do
    local a, b = pts[i], pts[i % n + 1]
    tri(a, lo, b, lo, b, hi, OUTLINE, 38)
    tri(a, lo, b, hi, a, hi, OUTLINE, 38)
    line(a, hi, b, hi, OUTLINE, 230)
    line(a, lo, b, lo, OUTLINE, 160)
    line(a, lo, a, hi, OUTLINE, 160)
  end
end

local function drawLabels(st, px, py, pz)
  local maxSq = LABEL_DISTANCE * LABEL_DISTANCE
  for i, p in ipairs(st.points) do
    local dx, dy, dz = p.x - px, p.y - py, p.z - pz
    if dx * dx + dy * dy + dz * dz < maxSq then
      Placement.drawText3D(p.x, p.y, p.z + 1.45, tostring(i), 0.45)
    end
  end
  if st.phase == 'height' then
    local sx, sy = 0.0, 0.0
    for _, p in ipairs(st.points) do sx, sy = sx + p.x, sy + p.y end
    local n = #st.points
    Placement.drawText3D(sx / n, sy / n, st.maxZ + 0.4,
      L('Ceiling {z}', { z = ('%.1f'):format(st.maxZ) }), 0.42)
    Placement.drawText3D(sx / n, sy / n, st.minZ - 0.2,
      L('Floor {z}', { z = ('%.1f'):format(st.minZ) }), 0.42)
  end
end

local function exportZone(st)
  local points = {}
  for i, p in ipairs(st.points) do
    points[i] = { x = Utils.round(p.x, 2), y = Utils.round(p.y, 2) }
  end
  return { points = points, minZ = Utils.round(st.minZ, 2), maxZ = Utils.round(st.maxZ, 2) }
end

local function runZone(opts)
  local st = { points = {}, phase = 'draw', fly = false, probe = newProbe(), rev = 0, old = opts.old }
  local graceUntil = GetGameTimer() + GRACE_MS
  local hintKey = nil

  local function cancel()
    sound('BACK')
    return nil
  end
  local lastX, lastY, lastZ = pedPosition()
  local lastT = GetGameTimer()

  while true do
    -- death / downed / cuffed or a teleport ends the tool (Placement.zone cleans up the camera).
    -- The jump limit grows with the frame time so one long hitch (streaming a big lot, a
    -- falling or ragdolling ped) does not cancel a half-drawn zone.
    local ped = PlayerPedId()
    local qx, qy, qz = pedPosition()
    local now = GetGameTimer()
    local jx, jy, jz = qx - lastX, qy - lastY, qz - lastZ
    local limit = math.max(TELEPORT_JUMP, TELEPORT_SPEED * (now - lastT) / 1000.0)
    lastX, lastY, lastZ, lastT = qx, qy, qz, now
    if IsEntityDead(ped) or (NZ.Points.incapacitated and NZ.Points.incapacitated())
      or jx * jx + jy * jy + jz * jz > limit * limit then
      NZ.NUI.notify('warning', L('Zone drawing cancelled'))
      return cancel()
    end

    disableAll(BLOCKED)
    disableAll(ZONE_KEYS)
    disableAll(VEHICLE_KEYS)
    if st.fly then flyUpdate(st) end

    local key = table.concat({ st.phase, #st.points, tostring(st.fly),
      st.phase == 'height' and ('%.2f/%.2f'):format(st.minZ, st.maxZ) or '' }, '|')
    if key ~= hintKey then
      hintKey = key
      NZ.NUI.hint(zoneHint(st))
    end

    local px, py, pz = pedPosition()
    drawReferences(opts, px, py, pz)
    local ready = GetGameTimer() >= graceUntil
    local escape = ready and IsDisabledControlJustReleased(0, ZK_ESC)
    local back = ready and not escape and IsDisabledControlJustReleased(0, ZK_BACK)
    local confirm = ready and anyJustReleased(C.CONFIRM)

    if st.phase == 'draw' then
      if st.old then drawOld(st.old) end
      local hit = updateProbe(st.probe, PlayerPedId(), st.fly and st.camPos or nil, st.fly and st.camRot or nil,
        st.fly and ZONE_AIM_FLY or ZONE_AIM)
      local aim = (hit and not st.probe.missed) and { x = hit.x, y = hit.y, z = hit.z } or nil
      local n = #st.points
      local snap = aim and n >= ZONE.minPoints and dist2d(aim, st.points[1]) <= ZONE_SNAP

      drawShape(st, false, OUTLINE)
      if aim then
        local bad = n > 0 and not snap and (wouldCross(st.points, aim) or n >= ZONE.maxPoints)
        local col = bad and WARN or OUTLINE
        if n > 0 then
          local last = st.points[n]
          line(last, last.z + 0.06, aim, aim.z + 0.06, col, 230)
          if n >= 2 and not snap then
            -- hint only: closing right here would cross (the next corner usually fixes it)
            local closeCol = (bad or closingCrosses(st.points, aim)) and WARN or OUTLINE
            line(aim, aim.z + 0.06, st.points[1], st.points[1].z + 0.06, closeCol, 90)
          end
        end
        if snap then
          corner(st.points[1], { 255, 255, 255 }, 0.45)
        else
          DrawMarker(25, aim.x + 0.0, aim.y + 0.0, aim.z + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 1.0,
            col[1], col[2], col[3], 200, false, false, 2, false, nil, nil, false)
          line(aim, aim.z, aim, aim.z + 1.2, col, 200)
        end
      end
      drawLabels(st, px, py, pz)

      if ready and IsDisabledControlJustReleased(0, ZK_FLY) then
        st.fly = not st.fly
        if st.fly then flyStart(st) else flyStop(st) end
        st.probe = newProbe()
      elseif ready and anyJustReleased(ZK_ADD) then
        if snap then
          closeShape(st, opts.openPoints)
        else
          local p = aim
          if not p and not st.fly then
            local g = groundAt(px, py, pz, false)
            p = { x = px, y = py, z = g or (pz - 1.0) }
          end
          if p then
            addPoint(st, p)
          else
            sound('ERROR')
            NZ.NUI.notify('warning', L('Aim at the ground to place a point'))
          end
        end
      elseif ready and (IsDisabledControlJustReleased(0, ZK_UNDO) or back) then
        if n > 0 then
          st.points[n] = nil
          st.rev = st.rev + 1
          sound('BACK')
        end
      elseif confirm then
        closeShape(st, opts.openPoints)
      elseif escape then
        return cancel()
      end
    else
      drawShape(st, true, OUTLINE)
      drawWalls(st)
      drawLabels(st, px, py, pz)

      local up = anyJustPressed(C.SCROLL_UP)
      local down = not up and anyJustPressed(C.SCROLL_DOWN)
      if up or down then
        local step = (IsDisabledControlPressed(0, C.SHIFT) and HEIGHT_STEP_FAST or HEIGHT_STEP) * (up and 1.0 or -1.0)
        if IsDisabledControlPressed(0, ZK_CTRL) then
          st.minZ = Utils.clamp(st.minZ + step, st.maxZ - ZONE.maxHeight, st.maxZ - ZONE.minHeight)
        else
          st.maxZ = Utils.clamp(st.maxZ + step, st.minZ + ZONE.minHeight, st.minZ + ZONE.maxHeight)
        end
      end

      if confirm then
        sound('SELECT')
        return exportZone(st)
      elseif back then
        sound('BACK')
        st.phase = 'draw'
        graceUntil = GetGameTimer() + GRACE_MS
      elseif escape then
        return cancel()
      end
    end
    Wait(0)
  end
end

--- Normalize the reference points handed to the zone tool (open / spawn markers).
local function referencePoints(openPoints, spawnPoints)
  local open, spawn = {}, {}
  if type(openPoints) == 'table' then
    for _, p in ipairs(openPoints) do
      local c = type(p) == 'table' and Utils.v3(p.coords or p) or nil
      if c and #open < 16 then
        local g = groundAt(c.x, c.y, c.z, false)
        open[#open + 1] = { x = c.x, y = c.y, z = c.z, ground = (g and math.abs(g - c.z) < 3.0) and g or (c.z - 1.0) }
      end
    end
  end
  if type(spawnPoints) == 'table' then
    for _, p in ipairs(spawnPoints) do
      local v = Utils.v4(p)
      if v and #spawn < 64 then spawn[#spawn + 1] = v end
    end
  end
  return open, spawn
end

--- In-world tool for the garage zone of a location (a polygon). Blocking; call from a thread.
--- Walk (crosshair aims at the ground) or fly (G: free camera, W/A/S/D, R/F, mouse). E adds a
--- corner at the crosshair (on foot without a hit: at the player's feet), X / Backspace undo,
--- Enter (or E on corner #1) closes the shape; then Scroll / Ctrl + Scroll set the ceiling /
--- floor, Enter saves, Backspace goes back to the corners, Esc cancels. The zone being replaced
--- is drawn grey; open and spawn points of the location are shown for reference. Garage
--- interaction points are paused meanwhile.
--- opts = { zone = { points, minZ, maxZ } | nil, openPoints = { { coords } }, spawnPoints = Vec4[] }
--- Returns { points = { {x, y} }, minZ, maxZ } or nil when cancelled.
---@param opts table|nil
---@return table|nil
function Placement.zone(opts)
  opts = type(opts) == 'table' and opts or {}
  if zoning or managing or toolActive then return nil end
  zoning = true

  local old = readZone(opts.zone)
  if old then groundUnder(old) end
  local open, spawn = referencePoints(opts.openPoints, opts.spawnPoints)
  local paused = suspendWorldPoints()
  NZ.NUI.prompt(nil)

  local ok, res = pcall(runZone, { old = old, openPoints = open, spawnPoints = spawn })

  -- the fly camera never outlives the tool
  if zoneCam then
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(zoneCam, false)
    zoneCam = nil
    ClearFocus()
  end
  NZ.NUI.hint(nil)
  if paused then resumeWorldPoints() end
  zoning = false
  if not ok then
    lib.print.error(('[nayzeee-garages] zone tool failed: %s'):format(res))
    return nil
  end
  return res
end

---------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for entity in pairs(ghosts) do
    if DoesEntityExist(entity) then
      SetEntityAsMissionEntity(entity, true, true)
      DeleteVehicle(entity)
      if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
  end
  ghosts = {}
  if zoneCam then
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(zoneCam, false)
    zoneCam = nil
    ClearFocus()
  end
  if toolActive or managing or zoning then NZ.NUI.hint(nil) end
end)
