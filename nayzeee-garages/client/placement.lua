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

local ghosts = {}             -- [entity] = true, every ghost created by this module
local toolActive = false      -- vehicle() / point() running
local managing = false        -- manage() running

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

local function updateProbe(probe, ignore)
  if probe.handle then
    local status, hit, endCoords = GetShapeTestResult(probe.handle)
    if status == 2 then
      probe.handle = nil
      local didHit = hit == true or hit == 1
      local c = didHit and Utils.v3(endCoords) or nil
      if c and (c.x ~= 0.0 or c.y ~= 0.0 or c.z ~= 0.0) then
        probe.hit = c
      else
        probe.hit = probe.endPoint
      end
    elseif status ~= 1 then
      probe.handle = nil
    end
    return probe.hit
  end
  local from = Utils.v3(GetGameplayCamCoord())
  local rot = Utils.v3(GetGameplayCamRot(2))
  if not from or not rot then return probe.hit end
  local dx, dy, dz = rotationToDirection(rot)
  local tx, ty, tz = from.x + dx * RAY_DISTANCE, from.y + dy * RAY_DISTANCE, from.z + dz * RAY_DISTANCE
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
  return toolActive or managing
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
  if toolActive or managing then NZ.NUI.hint(nil) end
end)
