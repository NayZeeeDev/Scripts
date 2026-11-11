--[[
  nayzeee-garages — car lock: the NUI minigames (client, NZ.CarLock). docs/CARLOCK.md §8.
  docs/V2_CHANGES.md G.6 (3D pin lock) and G.7 (hotwire wires, signal reader).

  The server makes every puzzle and checks every answer (server/carlock/crime.lua); this file
  only shows the puzzle and hands the player's answer back to crime.lua, which sends it with
  the 'finish' step.

  - CarLock.minigameSupport() -> { pins, wires, reader } once the page said 'minigame:ready'
    (else nil: the start payload has no `minigames` and the server hands out skill checks).
  - CarLock.playMinigame(game, puzzle, opts) (yields) -> { success, answer?, snapped?, cancelled? }
      game 'pins' | 'wires' | 'reader'; opts { vehicle, since, snapChance }
      Opens the 'minigame' app and waits for 'minigame:finish'. Ends early (failure) when the
      player dies, walks away from the door (pins) or leaves the driver seat (wires / reader), or
      after TIME_LIMIT_MS (the server session ends at 90 s). A page that cannot draw the game
      ('minigame:started' ok = false, or no answer within START_TIMEOUT_MS) falls back to ox_lib
      skill checks; passing them sends the puzzle's solution (the server sent it to draw the
      puzzle anyway: the puzzles are skill-gated, not cheat-proof).
      A success is held back until the server's minimum play time has passed since `since`
      (the moment the start answer arrived), so a fast player is never refused as too fast.
  NUI callbacks (client only): 'minigame:ready' {}, 'minigame:started' { token, ok },
  'minigame:finish' { token, success, answer?, snapped?, cancelled? }.
]]

local CarLock = NZ.CarLock

local APP = 'minigame'
local START_TIMEOUT_MS = 4000
local TIME_LIMIT_MS = 85000          -- server: MINIGAME_MAX_MS = 90000
local POLL_MS = 50
local MIN_MARGIN_MS = 150
-- the server's minimum play times (server/carlock/crime.lua, before its GRACE_MS)
local DOOR_TURN_MS, PIN_MIN_MS = 800, 450
local MIN_MS = { wires = 2400, reader = 2000 }
local DOOR_RANGE = 4.0               -- m: the lock pick ends when the player is further from the car
local ANCHOR_UPDATES_MS = { 400, 1000, 1800 }
local ANCHOR_MOVE = 0.015            -- screen share before the lock follows the door handle
local DOOR_BONES = { 'handle_dside_f', 'handle_pside_f', 'handle_dside_r', 'handle_pside_r',
  'door_dside_f', 'door_pside_f' }
local FALLBACK_CHECKS = {
  pins = { 'medium', 'medium', 'hard' },
  wires = { 'easy', 'medium', 'medium' },
  reader = { 'medium', 'hard' },
}
local WIRE_COLOURS = { red = true, blue = true, yellow = true, green = true, white = true, orange = true }

local ready = false
local active = nil                   -- { token, game, started, result }
local seq = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function int(v)
  local n = tonumber(v)
  if not n or n ~= n or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

--- The puzzle the server sent, checked before anything is drawn.
local function validPuzzle(game, p)
  if type(p) ~= 'table' then return false end
  if game == 'pins' then
    local n = int(p.pins)
    if not n or n < 3 or n > 7 or type(p.order) ~= 'table' or type(p.heights) ~= 'table' then return false end
    if #p.order ~= n or #p.heights ~= n then return false end
    local seen = {}
    for i = 1, n do
      local pin = int(p.order[i])
      if not pin or pin < 1 or pin > n or seen[pin] or not tonumber(p.heights[i]) then return false end
      seen[pin] = true
    end
    return true
  elseif game == 'wires' then
    if type(p.left) ~= 'table' or type(p.right) ~= 'table' or #p.left ~= 3 or #p.right ~= 3 then return false end
    for i = 1, 3 do
      if not WIRE_COLOURS[p.left[i]] or not WIRE_COLOURS[p.right[i]] then return false end
    end
    return true
  elseif game == 'reader' then
    return tonumber(p.frequency) ~= nil and tonumber(p.phase) ~= nil
  end
  return false
end

--- The answer from the page, bounded to the shape the server reads (it checks the content).
local function cleanAnswer(game, answer)
  if type(answer) ~= 'table' then return nil end
  if game == 'pins' or game == 'wires' then
    local out = {}
    local max = game == 'pins' and 7 or 3
    for i = 1, math.min(#answer, max) do
      local v = int(answer[i])
      if not v or v < 1 or v > max then return nil end
      out[i] = v
    end
    return out
  end
  local f, ph = tonumber(answer.frequency), tonumber(answer.phase)
  if not f or not ph or f ~= f or ph ~= ph then return nil end
  return { frequency = math.max(0, math.min(2000, f)), phase = math.max(0, math.min(360, ph)) }
end

--- The puzzle's own solution (skill-check fallback only).
local function solution(game, p)
  if game == 'pins' then
    local out = {}
    for i = 1, #p.order do out[i] = int(p.order[i]) end
    return out
  elseif game == 'wires' then
    local out, used = {}, {}
    for i = 1, 3 do
      for j = 1, 3 do
        if not used[j] and p.right[j] == p.left[i] then
          out[i], used[j] = j, true
          break
        end
      end
    end
    return out
  end
  return { frequency = tonumber(p.frequency), phase = tonumber(p.phase) }
end

local function minimumMs(game, p)
  if game == 'pins' then return DOOR_TURN_MS + (int(p.pins) or 5) * PIN_MIN_MS end
  return MIN_MS[game] or 0
end

--- The door handle nearest to the player on screen (shares 0..1), or nil (the lock is centred).
local function doorAnchor(vehicle)
  if not isVehicle(vehicle) then return nil end
  local ped = PlayerPedId()
  local from = GetEntityCoords(ped)
  local best, bestDist = nil, math.huge
  for _, bone in ipairs(DOOR_BONES) do
    local index = GetEntityBoneIndexByName(vehicle, bone)
    if index and index ~= -1 then
      local pos = GetWorldPositionOfEntityBone(vehicle, index)
      local d = #(pos - from)
      if d < bestDist then best, bestDist = pos, d end
    end
  end
  if not best then return nil end
  local onScreen, x, y = GetScreenCoordFromWorldCoord(best.x, best.y, best.z)
  if not onScreen or not tonumber(x) or not tonumber(y) or x < 0.05 or x > 0.95 or y < 0.05 or y > 0.95 then return nil end
  return { x = math.floor(x * 1000 + 0.5) / 1000, y = math.floor(y * 1000 + 0.5) / 1000 }
end

local function vehicleInfo(vehicle)
  if not isVehicle(vehicle) then return nil end
  local label = NZ.Dispatch and NZ.Dispatch.modelLabel and NZ.Dispatch.modelLabel(GetEntityModel(vehicle)) or nil
  local plate = NZ.Utils.trim(GetVehicleNumberPlateText(vehicle) or '') or ''
  return { label = label, plate = plate ~= '' and plate or nil }
end

--- Is the attempt still possible (alive, at the door / in the driver seat)?
local function stillThere(game, vehicle)
  local ped = PlayerPedId()
  if IsEntityDead(ped) or not isVehicle(vehicle) then return false end
  if game == 'pins' then
    return not IsPedInAnyVehicle(ped, false) and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= DOOR_RANGE
  end
  return GetPedInVehicleSeat(vehicle, -1) == ped
end

local DIFFICULTIES = { easy = true, medium = true, hard = true }

local function skillFallback(game, puzzle)
  local checks = {}
  for _, c in ipairs(FALLBACK_CHECKS[game] or { 'medium' }) do
    if DIFFICULTIES[c] then checks[#checks + 1] = c end
  end
  local ok, res = pcall(lib.skillCheck, checks)
  if ok and res == true then return { success = true, answer = solution(game, puzzle) } end
  return { success = false }
end

---------------------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------------------

--- Runs the page minigame; returns the result, or { fallback = true } when it cannot be drawn.
local function runNui(game, puzzle, opts)
  seq = seq + 1
  local session = { token = seq, game = game, started = nil, result = nil }
  active = session
  local vehicle = opts.vehicle
  local data = {
    token = session.token,
    game = game,
    puzzle = puzzle,
    timeLimit = math.floor(TIME_LIMIT_MS / 1000),
    vehicle = vehicleInfo(vehicle),
  }
  if game == 'pins' then
    data.snapChance = math.max(0, math.min(100, tonumber(opts.snapChance) or 35))
    data.anchor = doorAnchor(vehicle)
  end
  NZ.NUI.open(APP, data)
  local opened = GetGameTimer()
  local anchor = data.anchor
  local nextAnchor = 1
  while not session.result do
    Wait(POLL_MS)
    local elapsed = GetGameTimer() - opened
    if session.result then break end
    if session.started == false then
      session.result = { fallback = true }
    elseif session.started == nil and elapsed > START_TIMEOUT_MS then
      session.result = { fallback = true }
    elseif elapsed > TIME_LIMIT_MS then
      session.result = { success = false, timeout = true }
    elseif not stillThere(game, vehicle) then
      session.result = { success = false, cancelled = true }
    elseif game == 'pins' and ANCHOR_UPDATES_MS[nextAnchor] and elapsed >= ANCHOR_UPDATES_MS[nextAnchor] then
      -- the camera settles after the turn to the door: the lock follows the handle a few times
      nextAnchor = nextAnchor + 1
      local now = doorAnchor(vehicle)
      if now and (not anchor or math.abs(now.x - anchor.x) > ANCHOR_MOVE or math.abs(now.y - anchor.y) > ANCHOR_MOVE) then
        anchor = now
        NZ.NUI.send('update', { app = APP, data = { anchor = now } })
      end
    end
  end
  active = nil
  if NZ.NUI.isOpen(APP) then NZ.NUI.close(APP) end
  return session.result
end

NZ.NUI.register('minigame:ready', function()
  ready = true
  return nil
end)

NZ.NUI.register('minigame:started', function(data)
  local session = active
  if session and not session.result and int(data.token) == session.token then
    session.started = data.ok ~= false
  end
  return nil
end)

NZ.NUI.register('minigame:finish', function(data)
  local session = active
  if not session or session.result or int(data.token) ~= session.token then return nil end
  local success = data.success == true
  session.result = {
    success = success,
    answer = success and cleanAnswer(session.game, data.answer) or nil,
    snapped = not success and session.game == 'pins' and data.snapped == true or nil,
    cancelled = data.cancelled == true or nil,
  }
  return nil
end)

-- closed from anywhere else (another script, NZ.NUI.close()): the attempt ends as given up
NZ.NUI.onClose(APP, function()
  local session = active
  if session and not session.result then session.result = { success = false, cancelled = true } end
end)

---------------------------------------------------------------------------------------
-- API (crime.lua)
---------------------------------------------------------------------------------------

--- The NUI minigames this client can play (start payload `minigames`), or nil.
---@return table|nil
function CarLock.minigameSupport()
  if not ready then return nil end
  return { pins = true, wires = true, reader = true }
end

--- Play a server puzzle (yields). See the header.
---@param game string 'pins'|'wires'|'reader'
---@param puzzle table
---@param opts table|nil { vehicle, since, snapChance }
---@return table { success, answer?, snapped?, cancelled? }
function CarLock.playMinigame(game, puzzle, opts)
  opts = type(opts) == 'table' and opts or {}
  local since = tonumber(opts.since) or GetGameTimer()
  if not validPuzzle(game, puzzle) then return { success = false } end
  local result = nil
  if ready and not active then result = runNui(game, puzzle, opts) end
  if not result or result.fallback then result = skillFallback(game, puzzle) end
  if result.success then
    local due = since + minimumMs(game, puzzle) + MIN_MARGIN_MS
    while GetGameTimer() < due do Wait(50) end
  end
  return result
end
