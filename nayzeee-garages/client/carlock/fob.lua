--[[
  nayzeee-garages — car lock: on-screen key fob HUD and physical key actions (client).
  docs/V2_CHANGES.md G.4 / G.5. NUI app 'fob' (web/src/apps/fob).

  Fob HUD
  - Shown for a moment when you lock / unlock (local event 'nz:client:carlock:feedback', the
    item event 'nz:client:carlock:used', or the lock toggle as a fallback), the pressed button
    lights up; the beep of presses the game does not beep for follows the fobBeep setting.
  - Keybind (Config.CarLock.fobHud.keys.toggle, default K): take the key in your hand. While
    holding: side prompts Throw / Inspect / Move / Help / Close (rebindable key mappings, ESC /
    Backspace close), the key prop in the right hand (Config.CarLock.fobProps).
  - Move = edit mode (focus): drag / resize, prompts toggle (browser storage), Reset / Save
    (player setting fobPosition through CarLock.savePlayerSettings).
  Physical keys (on top of lock.lua's CarLock.dropKey / tossKey / throwKey / keepGroundKey):
  - Throw on foot: aim at a player within ground.throwRange (marker + prompt bar), E throws
    (animation, the key flies to them), the receiver sees it fly and catches with lock.lua's
    prompt (a caught key shows in their hand).
  - Throw in the driver seat: out of the window (cars) or a seated toss (bikes / quads).
  - Drop: placement bar E Place, H Hold in hand, G Cancel, Scroll Rotate with a ghost prop
    where the server will put it (the server decides the position; the client never sends one).
  - Inspect: the key ring's inspect card (CarLock.openKeyInspect).
  The server decides everything (key ownership, ranges, catches); this file only draws, animates
  and asks. Props are local (non-networked) visuals: the real ground key is the server's prop.

  API for other files: CarLock.fobShow(plate, opts?), CarLock.holdKey(key?), CarLock.putAwayKey(),
  CarLock.fobPress(button, opts?), CarLock.startKeyPlacement(key), CarLock.startKeyThrow(key?),
  CarLock.tossKeyFromVehicle(key?), CarLock.fobBusy().
  key = { plate, slot?, keyId? } (a key item: slot / keyId) or a plate.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local APP = 'fob'
local SHOW_MS = 4500          -- HUD after a lock / unlock press (not holding)
local KEYS_TTL = 30000        -- ms: the key list ('nz:carlock:keys')
local DEDUPE_MS = 1200        -- one lock press reported by two hooks
local MODEL_TIMEOUT = 1500
local FALLBACK_PROPS = { 'lr_prop_carkey_fob', 'p_car_keys_01', 'prop_cuff_keys_01' }
local CONTROL = {
  pickup = 38, cancelG = 47, headlight = 74, wheelNext = 14, wheelPrev = 15, pause = 200, pauseAlt = 199,
  back = 177, aim = 25, attack = 24, weaponWheel = 37, melee = 140, melee2 = 141, melee3 = 142,
}
-- animations (dict, clip, ms, flag); names to confirm in game
local ANIM = {
  tossCar = { 'veh@driveby@first_person@driver@throw', 'throw_90l', 1100, 48 },
  tossBike = { 'mp_common', 'givetake1_a', 1000, 48 },
  catch = { 'mp_common', 'givetake1_b', 800, 48 },
  hold = { 'amb@world_human_stand_mobile@male@text@base', 'base', -1, 49 },
}

local state = {
  open = false,
  mode = 'hud',               -- 'hud' | 'edit' | 'help'
  key = nil,                  -- FobHudKey
  ref = nil,                  -- { plate, slot?, keyId?, design, kind } of the shown key
  holding = false,
  hideAt = nil,
  seq = 0,
  press = nil,
  busy = nil,                 -- 'place' | 'aim' | 'throw' | 'toss' while an action runs
  lastFeedback = 0,
  lastPlate = nil,
}
local handProp = nil          -- the prop in the hand while holding
local tempProps = {}          -- [entity] = true: flying / momentary props (cleanup)
local keyList = { at = -1e9, byPlate = {} }
local keybinds = {}
local catchWatch = nil        -- { deadline, keyKind } after someone threw us a key

local function now() return GetGameTimer() end

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

local function hudCfg()
  local c = CarLock.cfg().fobHud
  return type(c) == 'table' and c or {}
end

local function groundCfg()
  local g = CarLock.cfg().ground
  return type(g) == 'table' and g or {}
end

local function propCfg()
  local p = CarLock.cfg().fobProps
  return type(p) == 'table' and p or {}
end

---------------------------------------------------------------------------------------
-- Props (Config.CarLock.fobProps): model per design, fallback, hand attachment
---------------------------------------------------------------------------------------

--- Load a prop model (yields up to MODEL_TIMEOUT). Returns the hash or nil.
local function loadModel(name)
  if type(name) ~= 'string' or name == '' then return nil end
  local hash = joaat(name)
  if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
  RequestModel(hash)
  local deadline = now() + MODEL_TIMEOUT
  while not HasModelLoaded(hash) do
    if now() > deadline then return nil end
    Wait(0)
  end
  return hash
end

--- Model names to try for a design: fobProps.byDesign[design], fobProps.fallback, built-ins.
local function propModels(design)
  local cfg = propCfg()
  local by = type(cfg.byDesign) == 'table' and cfg.byDesign or {}
  local list = {}
  local function add(m) if type(m) == 'string' and m ~= '' then list[#list + 1] = m end end
  add(by[design])
  add(cfg.fallback)
  for _, m in ipairs(FALLBACK_PROPS) do add(m) end
  return list
end

--- A local (non-networked) key prop of `design` at `coords` (yields). Returns the entity or nil.
local function createKeyProp(design, coords)
  for _, name in ipairs(propModels(design)) do
    local hash = loadModel(name)
    if hash then
      local c = coords or GetEntityCoords(PlayerPedId())
      local prop = CreateObject(hash, c.x, c.y, c.z, false, false, false)
      SetModelAsNoLongerNeeded(hash)
      if prop and prop ~= 0 then
        SetEntityCollision(prop, false, false)
        return prop
      end
    end
  end
  return nil
end

local function vec(v, dx, dy, dz)
  if type(v) ~= 'table' and type(v) ~= 'vector3' then return dx, dy, dz end
  return tonumber(v.x) or dx, tonumber(v.y) or dy, tonumber(v.z) or dz
end

local function attachToHand(prop, ped)
  local hand = type(propCfg().hand) == 'table' and propCfg().hand or {}
  local ox, oy, oz = vec(hand.offset, 0.04, 0.0, -0.01)
  local rx, ry, rz = vec(hand.rotation, -90.0, 0.0, 0.0)
  AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, tonumber(hand.bone) or 28422), ox, oy, oz, rx, ry, rz,
    true, true, false, true, 1, true)
end

local function deleteProp(prop)
  if prop and DoesEntityExist(prop) then
    DetachEntity(prop, false, false)
    DeleteEntity(prop)
  end
  if prop then tempProps[prop] = nil end
end

--- A prop in the hand for `ms` (drop / pick up / catch), in its own thread.
local function propInHand(design, ms, delay)
  CreateThread(function()
    if delay and delay > 0 then Wait(delay) end
    local ped = PlayerPedId()
    local prop = createKeyProp(design)
    if not prop then return end
    tempProps[prop] = true
    attachToHand(prop, ped)
    Wait(ms)
    deleteProp(prop)
  end)
end

--- A key flying from `from` to `to` (vector3s or entity getters) along a small arc, in `ms`.
local function flyProp(design, from, to, ms)
  CreateThread(function()
    local prop = createKeyProp(design, from())
    if not prop then return end
    tempProps[prop] = true
    local start = now()
    local spin = math.random(0, 359) + 0.0
    while now() - start < ms and DoesEntityExist(prop) do
      local t = (now() - start) / ms
      local a, b = from(), to()
      local x = a.x + (b.x - a.x) * t
      local y = a.y + (b.y - a.y) * t
      local z = a.z + (b.z - a.z) * t + math.sin(t * math.pi) * 0.6
      SetEntityCoordsNoOffset(prop, x, y, z, false, false, false)
      SetEntityRotation(prop, t * 540.0, 0.0, spin + t * 360.0, 2, true)
      Wait(0)
    end
    deleteProp(prop)
  end)
end

local function playAnim(spec)
  local dict, clip, ms, flag = spec[1], spec[2], spec[3], spec[4]
  if not pcall(lib.requestAnimDict, dict, 1000) then return false end
  TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, -8.0, ms, flag, 0, false, false, false)
  if ms and ms > 0 then SetTimeout(ms + 300, function() RemoveAnimDict(dict) end) end
  return true
end

local function handBone(ped)
  return GetPedBoneCoords(ped, tonumber(propCfg().hand and propCfg().hand.bone) or 28422, 0.0, 0.0, 0.0)
end

---------------------------------------------------------------------------------------
-- Keys: the server's list, the HUD key of a plate
---------------------------------------------------------------------------------------

local function refreshKeys(force)
  if not force and now() - keyList.at < KEYS_TTL then return keyList.byPlate end
  local ok, res = pcall(lib.callback.await, 'nz:carlock:keys', false, {})
  keyList.at = now()
  if ok and type(res) == 'table' and res.ok and type(res.data) == 'table' and type(res.data.keys) == 'table' then
    local by = {}
    for _, k in ipairs(res.data.keys) do
      local p = type(k) == 'table' and Utils.plate(k.plate) or nil
      if p then by[p] = k end
    end
    keyList.byPlate = by
  end
  return keyList.byPlate
end

RegisterNetEvent('nz:client:carlock:keys', function(data)
  keyList.at = -1e9
  -- a key thrown to us arrived in our pocket: show it in the hand for a moment
  if catchWatch and now() < catchWatch.deadline and type(data) == 'table' and Utils.plate(data.plate) then
    local design = catchWatch.keyKind == 'key' and 'key' or nil
    catchWatch = nil
    propInHand(design or CarLock.defaultFobDesign(), 1300, 150)
  end
end)

--- The admin's default fob design (Config.CarLock.fob.defaultDesign).
function CarLock.defaultFobDesign()
  local f = CarLock.cfg().fob
  return type(f) == 'table' and type(f.defaultDesign) == 'string' and f.defaultDesign or 'classic'
end

local function vehicleOfPlate(plate)
  local ped = PlayerPedId()
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 and CarLock.plateOf(current) == plate then return current end
  for _, entry in ipairs(lib.getNearbyVehicles(GetEntityCoords(ped), CarLock.range('fob') + 30.0, true) or {}) do
    if CarLock.plateOf(entry.vehicle) == plate then return entry.vehicle end
  end
  return nil
end

--- 'key' | 'fob' of a key list entry (key items carry it; other keys follow the model's profile).
local function kindOf(entry, vehicle)
  if type(entry) == 'table' and (entry.keyKind == 'key' or entry.keyKind == 'fob') then return entry.keyKind end
  local model = vehicle and GetEntityModel(vehicle) or (type(entry) == 'table' and entry.model) or nil
  if model then
    local _, profile = CarLock.profileOf(model, vehicle and GetVehicleClass(vehicle) or nil)
    return CarLock.keyKindOf(profile)
  end
  return 'fob'
end

--- FobHudKey + key reference of a plate (yields: the key list). nil when we have no key.
local function buildKey(plate, vehicle)
  plate = Utils.plate(plate)
  if not plate then return nil end
  local entry = refreshKeys(false)[plate]
  if not entry then entry = refreshKeys(true)[plate] end
  if not entry then return nil end
  vehicle = vehicle or vehicleOfPlate(plate)
  local kind = kindOf(entry, vehicle)
  local design = kind == 'key' and 'key' or (type(entry.design) == 'string' and entry.design or CarLock.defaultFobDesign())
  local label, make = nil, ''
  local model = vehicle and GetEntityModel(vehicle) or entry.model
  if model and NZ.Veh and NZ.Veh.label then
    local l, m = NZ.Veh.label(model)
    label, make = l, m or ''
    if make == '' then
      local raw = GetMakeNameFromVehicleModel(type(model) == 'string' and joaat(model) or model)
      if type(raw) == 'string' and raw ~= '' and raw ~= 'CARNOTFOUND' then make = raw end
    end
  end
  local locked = nil
  if vehicle then
    local bag = Entity(vehicle).state.nzLocked
    if bag ~= nil then locked = bag == true end
  end
  return {
    plate = plate, label = label or (type(entry.label) == 'string' and entry.label) or plate, make = make,
    design = design, kind = kind, locked = locked,
  }, { plate = plate, slot = tonumber(entry.slot), keyId = type(entry.keyId) == 'string' and entry.keyId or nil,
    item = entry.kind == 'item', design = design, kind = kind }
end

---------------------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------------------

local function defaults()
  local d = type(CarLock.cfg().playerDefaults) == 'table' and CarLock.cfg().playerDefaults.fobPosition or nil
  return CarLock.normalizePlayerSettings({ fobPosition = d }).fobPosition
end

local function layout()
  local s = type(CarLock.playerSettings) == 'function' and CarLock.playerSettings() or {}
  return type(s.fobPosition) == 'table' and s.fobPosition or defaults()
end

local function keyLabel(name, fallback)
  local kb = keybinds[name]
  if kb and type(kb.getCurrentKey) == 'function' then
    local ok, key = pcall(kb.getCurrentKey, kb)
    if ok and type(key) == 'string' and key ~= '' then return key end
  end
  return fallback
end

local function keyLabels()
  local k = type(hudCfg().keys) == 'table' and hudCfg().keys or {}
  return {
    throw = keyLabel('throw', k.throw or 'Y'), inspect = keyLabel('inspect', k.inspect or 'I'),
    move = keyLabel('move', k.move or 'M'), help = keyLabel('help', k.help or 'H'), close = 'ESC',
  }
end

local function payload()
  return { mode = state.mode, key = state.key, layout = layout(), defaults = defaults(), holding = state.holding,
    keys = keyLabels(), press = state.press }
end

local function push(partial)
  if state.open then NZ.NUI.send('update', { app = APP, data = partial }) end
end

local function showHud()
  if not state.key then return end
  if state.open then
    push(payload())
  else
    state.open = true
    NZ.NUI.open(APP, payload(), state.mode ~= 'hud')
  end
end

local function hideHud()
  if not state.open then return end
  state.open = false
  state.mode = 'hud'
  NZ.NUI.close(APP)
end

NZ.NUI.onClose(APP, function()
  -- closed by Lua (hideHud) or by another script closing every app
  state.open = false
  state.mode = 'hud'
  if state.holding then CarLock.putAwayKey() end
end)

local function setMode(mode)
  state.mode = mode
  NZ.NUI.setFocus(APP, mode ~= 'hud')
  push({ mode = mode, layout = layout(), keys = keyLabels() })
end

--- Light a fob button on the HUD: button 'lock'|'unlock'|'trunk'|'panic'; opts.plate shows that
--- key first, opts.beep plays the NUI beep (only presses the game does not beep for; the
--- player's fobBeep setting decides).
---@param button string
---@param opts table|nil
function CarLock.fobPress(button, opts)
  if button ~= 'lock' and button ~= 'unlock' and button ~= 'trunk' and button ~= 'panic' then return end
  opts = type(opts) == 'table' and opts or {}
  local mine = type(CarLock.playerSettings) == 'function' and CarLock.playerSettings() or {}
  state.seq = state.seq + 1
  state.press = { button = button, seq = state.seq, beep = opts.beep == true and mine.fobBeep ~= false }
  if state.open then push({ press = state.press, key = state.key }) else showHud() end
end

--- Show the fob of `plate` for a moment (yields: the key list). opts.locked / opts.vehicle.
---@param plate string
---@param opts table|nil
---@return boolean shown
function CarLock.fobShow(plate, opts)
  opts = type(opts) == 'table' and opts or {}
  if state.busy or (IsNuiFocused() and not NZ.NUI.isOpen(APP)) then return false end
  local key, ref = buildKey(plate, opts.vehicle)
  if not key then return false end
  if opts.locked ~= nil then key.locked = opts.locked == true end
  -- holding another key: keep holding it, only flash this press
  if state.holding and state.key and state.key.plate ~= key.plate then return false end
  state.key = key
  if not state.holding then state.ref = ref end
  state.lastPlate = key.plate
  if not state.holding and state.mode == 'hud' then state.hideAt = now() + (tonumber(hudCfg().showMs) or SHOW_MS) end
  showHud()
  return true
end

-- auto-hide after a press (not while holding / editing)
CreateThread(function()
  while true do
    Wait(250)
    if state.open and not state.holding and state.mode == 'hud' and state.hideAt and now() > state.hideAt then
      state.hideAt = nil
      hideHud()
    end
  end
end)

---------------------------------------------------------------------------------------
-- Lock / unlock presses
---------------------------------------------------------------------------------------

local function onFeedback(data)
  if type(data) ~= 'table' then return end
  local plate = Utils.plate(data.plate)
  if not plate then return end
  -- one press can arrive through several hooks (lock.lua feedback, the item event): count it once
  local sig = plate .. ':' .. tostring(data.locked)
  if state.lastSig == sig and now() - state.lastFeedback <= DEDUPE_MS then return end
  state.lastSig = sig
  state.lastFeedback = now()
  local vehicle = nil
  local netId = tonumber(data.netId)
  if netId and NetworkDoesNetworkIdExist(netId) then vehicle = NetworkGetEntityFromNetworkId(netId) end
  CreateThread(function()
    local shown = CarLock.fobShow(plate, { locked = data.locked, vehicle = vehicle ~= 0 and vehicle or nil })
    if shown or (state.open and state.key and state.key.plate == plate) then
      -- the game already played the lock beep (lock.lua feedback): no NUI beep
      CarLock.fobPress(data.locked and 'lock' or 'unlock', { beep = false })
    end
  end)
end

-- lock.lua feedback (see notesForLead: TriggerEvent('nz:client:carlock:feedback', data))
AddEventHandler('nz:client:carlock:feedback', onFeedback)
-- a key / fob item was used (server)
RegisterNetEvent('nz:client:carlock:used', function(data)
  if now() - state.lastFeedback > DEDUPE_MS then onFeedback(data) end
end)

-- Fallback until lock.lua raises 'nz:client:carlock:feedback': the toggle's answer has no
-- plate, so take the vehicle we sit in, else the nearest vehicle whose lock now matches.
local baseToggle = CarLock.toggleLock
if type(baseToggle) == 'function' then
  CarLock.toggleLock = function(vehicle)
    local ok, locked = baseToggle(vehicle)
    if ok and now() - state.lastFeedback > DEDUPE_MS then
      local ped = PlayerPedId()
      local target = vehicle
      if not target or target == 0 then target = GetVehiclePedIsIn(ped, false) end
      if not target or target == 0 then
        local best, bestDist = nil, math.huge
        local from = GetEntityCoords(ped)
        for _, entry in ipairs(lib.getNearbyVehicles(from, CarLock.range('fob') + 2.0, false) or {}) do
          local bag = Entity(entry.vehicle).state.nzLocked
          local d = #(entry.coords - from)
          if (bag == nil or (bag == true) == (locked == true)) and d < bestDist then best, bestDist = entry.vehicle, d end
        end
        target = best
      end
      local plate = target and target ~= 0 and CarLock.plateOf(target) or nil
      if plate then
        state.lastFeedback = now()
        CreateThread(function()
          local shown = CarLock.fobShow(plate, { locked = locked, vehicle = target })
          if shown or (state.open and state.key and state.key.plate == plate) then
            CarLock.fobPress(locked and 'lock' or 'unlock', { beep = false })
          end
        end)
      end
    end
    return ok, locked
  end
end

-- the panic button lights while the shown vehicle's alarm sounds
AddStateBagChangeHandler('nzAlarm', nil, function(bagName, _, value)
  if not state.open or not state.key or type(value) ~= 'table' then return end
  local entity = GetEntityFromStateBagName(bagName)
  if entity and entity ~= 0 and CarLock.plateOf(entity) == state.key.plate then
    CarLock.fobPress('panic', { beep = false })
  end
end)

---------------------------------------------------------------------------------------
-- Holding the key
---------------------------------------------------------------------------------------

local function canAct()
  local ped = PlayerPedId()
  return not IsPauseMenuActive() and not IsEntityDead(ped) and not IsPedRagdoll(ped)
end

--- Which key to take out: the given one, the vehicle we sit in, the last one used, the nearest
--- vehicle we have a key for, else the first key item.
local function pickPlate(key)
  if type(key) == 'string' then return Utils.plate(key) end
  if type(key) == 'table' and Utils.plate(key.plate) then return Utils.plate(key.plate) end
  local list = refreshKeys(false)
  local ped = PlayerPedId()
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 then
    local p = CarLock.plateOf(current)
    if p and list[p] then return p end
  end
  if state.lastPlate and list[state.lastPlate] then return state.lastPlate end
  local best, bestDist = nil, math.huge
  local from = GetEntityCoords(ped)
  for _, entry in ipairs(lib.getNearbyVehicles(from, CarLock.range('fob'), false) or {}) do
    local p = CarLock.plateOf(entry.vehicle)
    local d = #(entry.coords - from)
    if p and list[p] and d < bestDist then best, bestDist = p, d end
  end
  if best then return best end
  for p, entry in pairs(list) do
    if entry.kind == 'item' then return p end
  end
  return next(list)
end

local function attachHandProp()
  if handProp or not state.ref then return end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return end
  local prop = createKeyProp(state.ref.design)
  if not prop then return end
  if not state.holding then
    deleteProp(prop)
    return
  end
  attachToHand(prop, ped)
  handProp = prop
end

local function dropHandProp()
  deleteProp(handProp)
  handProp = nil
end

--- Take a key in the hand (yields): the fob HUD with live side prompts. Returns true when held.
---@param key table|string|nil
---@return boolean
function CarLock.holdKey(key)
  if state.busy or not CarLock.enabled() or not canAct() then return false end
  local plate = pickPlate(key)
  local hud, ref = buildKey(plate)
  if not hud then
    notify('error', L('You do not have any keys'))
    return false
  end
  if state.holding then dropHandProp() end
  state.key, state.ref, state.holding, state.hideAt = hud, ref, true, nil
  state.lastPlate = hud.plate
  for name, kb in pairs(keybinds) do
    if name ~= 'toggle' and type(kb.disable) == 'function' then kb:disable(false) end
  end
  showHud()
  push({ holding = true, key = hud })
  attachHandProp()
  -- per frame only while holding: ESC / Backspace put the key away (the pause menu stays
  -- closed), the prop follows getting in / out
  CreateThread(function()
    local lastCheck = 0
    while state.holding do
      if not state.busy and state.mode == 'hud' then
        DisableControlAction(0, CONTROL.pause, true)
        DisableControlAction(0, CONTROL.pauseAlt, true)
        if IsDisabledControlJustPressed(0, CONTROL.pause) or IsControlJustPressed(0, CONTROL.back) then
          CarLock.putAwayKey()
          break
        end
      end
      if now() - lastCheck > 300 then
        lastCheck = now()
        local ped = PlayerPedId()
        if IsEntityDead(ped) then
          CarLock.putAwayKey()
          break
        end
        local inVehicle = IsPedInAnyVehicle(ped, false)
        if inVehicle and handProp then dropHandProp() end
        if not inVehicle and not handProp and not state.busy then CreateThread(attachHandProp) end
      end
      Wait(0)
    end
  end)
  return true
end

--- Put the key away: HUD closed, prop gone, side prompt keys off.
function CarLock.putAwayKey()
  local wasHolding = state.holding
  state.holding = false
  dropHandProp()
  for name, kb in pairs(keybinds) do
    if name ~= 'toggle' and type(kb.disable) == 'function' then kb:disable(true) end
  end
  if wasHolding then
    if state.mode ~= 'hud' then NZ.NUI.setFocus(APP, false) end
    hideHud()
  end
end

--- The key thrown / tossed / placed is gone from the pocket: stop holding it.
local function keyGone()
  state.ref = nil
  CarLock.putAwayKey()
  hideHud()
  state.key = nil
end

local function keyPayload(ref)
  return { slot = ref.slot, keyId = ref.keyId, plate = ref.plate }
end

local function itemRef(key)
  local ref = state.ref
  if key ~= nil then
    local _, r = buildKey(pickPlate(key))
    ref = r
    if ref and type(key) == 'table' then
      ref.slot = tonumber(key.slot) or ref.slot
      ref.keyId = type(key.keyId) == 'string' and key.keyId or ref.keyId
    end
  end
  if not ref then return nil, L('You do not have any keys') end
  if not ref.item or (not ref.slot and not ref.keyId) then return nil, L('Only key items can be dropped or thrown') end
  if groundCfg().enabled == false then return nil, L('Keys cannot be dropped on this server') end
  return ref
end

---------------------------------------------------------------------------------------
-- Throw (on foot: aim at a player) / toss (driver seat)
---------------------------------------------------------------------------------------

local function hint(keys)
  NZ.NUI.hint(keys and { keys = keys } or nil)
end

local function throwTargets(range)
  local ped = PlayerPedId()
  local from = GetEntityCoords(ped)
  local me = PlayerId()
  local out = {}
  for _, player in ipairs(GetActivePlayers() or {}) do
    if player ~= me then
      local other = GetPlayerPed(player)
      if other ~= 0 and DoesEntityExist(other) and not IsEntityDead(other) then
        local d = #(GetEntityCoords(other) - from)
        if d <= range and HasEntityClearLosToEntity(ped, other, 17) then
          out[#out + 1] = { player = player, ped = other, serverId = GetPlayerServerId(player), distance = d }
        end
      end
    end
  end
  return out
end

--- The target closest to where the camera looks.
local function aimed(targets)
  local rot = GetGameplayCamRot(2)
  local rx, rz = math.rad(rot.x), math.rad(rot.z)
  local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
  local cam = GetGameplayCamCoord()
  local best, bestDot = nil, -2
  for i, t in ipairs(targets) do
    local v = GetEntityCoords(t.ped) - cam
    local len = #v
    if len > 0.01 then
      local dot = (v.x * dir.x + v.y * dir.y + v.z * dir.z) / len
      if dot > bestDot then best, bestDot = i, dot end
    end
  end
  return best
end

--- Out of the window (cars) / seated toss (bikes, quads): the server puts it on the ground.
---@param key table|string|nil
function CarLock.tossKeyFromVehicle(key)
  if state.busy then return false end
  local ref, err = itemRef(key)
  if not ref then
    notify('error', err)
    return false
  end
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
    notify('error', L('You are not in the driver seat'))
    return false
  end
  state.busy = 'toss'
  local class = GetVehicleClass(vehicle)
  local seated = class == 8 or class == 13 or IsThisModelAQuadbike(GetEntityModel(vehicle))
  if groundCfg().animateDrops ~= false then playAnim(seated and ANIM.tossBike or ANIM.tossCar) end
  Wait(450)
  -- the visual leaves the hand towards the left side; the server's prop lands there
  local side = seated and 0.9 or 1.6
  local function fromHand() return handBone(ped) end
  local function toGround()
    local c = GetEntityCoords(vehicle)
    local h = math.rad(GetEntityHeading(vehicle))
    return vector3(c.x - math.cos(h) * side, c.y - math.sin(h) * side, c.z - 0.4)
  end
  flyProp(ref.design, fromHand, toGround, 450)
  local ok = CarLock.tossKey(keyPayload(ref))
  state.busy = nil
  if ok then keyGone() end
  return ok
end

--- Aim at a nearby player and throw (on foot); in the driver seat this is the window toss.
---@param key table|string|nil
function CarLock.startKeyThrow(key)
  if state.busy then return false end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return CarLock.tossKeyFromVehicle(key) end
  local ref, err = itemRef(key)
  if not ref then
    notify('error', err)
    return false
  end
  local range = Utils.clamp(tonumber(groundCfg().throwRange) or 8.0, 2.0, 20.0)
  if #throwTargets(range) == 0 then
    notify('error', L('Nobody close enough to throw the key to'))
    return false
  end
  state.busy = 'aim'
  local manual = nil
  local result = nil
  local lastScan, targets = 0, {}
  local shownFor = nil
  while state.busy == 'aim' do
    if now() - lastScan > 250 then
      lastScan = now()
      targets = throwTargets(range)
      if #targets == 0 then break end
      if manual and manual > #targets then manual = nil end
    end
    local index = manual or aimed(targets)
    local target = index and targets[index]
    for _, c in ipairs({ CONTROL.pickup, CONTROL.cancelG, CONTROL.wheelNext, CONTROL.wheelPrev, CONTROL.weaponWheel,
      CONTROL.attack, CONTROL.aim, CONTROL.melee, CONTROL.melee2, CONTROL.melee3, CONTROL.pause }) do
      DisableControlAction(0, c, true)
    end
    if target then
      local c = GetEntityCoords(target.ped)
      DrawMarker(2, c.x, c.y, c.z + 1.15, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.18, 0.18, 0.18, 8, 175, 162, 210,
        true, true, 2, false, nil, nil, false)
      if shownFor ~= target.serverId then
        shownFor = target.serverId
        hint({
          { keys = { 'E' }, label = L('Throw to player {id}', { id = target.serverId }) },
          { keys = { 'Scroll' }, label = L('Next player') },
          { keys = { 'G' }, label = L('Cancel') },
        })
      end
    end
    if IsDisabledControlJustPressed(0, CONTROL.wheelNext) or IsDisabledControlJustPressed(0, CONTROL.wheelPrev) then
      local step = IsDisabledControlJustPressed(0, CONTROL.wheelNext) and 1 or -1
      manual = (((manual or index or 1) - 1 + step) % math.max(#targets, 1)) + 1
    elseif IsDisabledControlJustPressed(0, CONTROL.pickup) and target then
      result = target
      break
    elseif IsDisabledControlJustPressed(0, CONTROL.cancelG) or IsDisabledControlJustPressed(0, CONTROL.pause)
      or IsControlJustPressed(0, CONTROL.back) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
      break
    end
    Wait(0)
  end
  hint(nil)
  if not result then
    state.busy = nil
    return false
  end
  state.busy = 'throw'
  TaskTurnPedToFaceEntity(ped, result.ped, 400)
  Wait(350)
  -- lock.lua plays the throw animation and asks the server; the key leaves the hand ~0.5 s in
  local window = nil
  CreateThread(function()
    Wait(520)
    dropHandProp()
    local target = result.ped
    flyProp(ref.design, function() return handBone(ped) end, function()
      return DoesEntityExist(target) and GetPedBoneCoords(target, 57005, 0.0, 0.0, 0.0) or GetEntityCoords(ped)
    end, 520)
  end)
  local ok, data = CarLock.throwKey(keyPayload(ref), result.serverId)
  if type(data) == 'table' then window = data.window end
  state.busy = nil
  if ok then
    keyGone()
  elseif state.holding then
    CreateThread(attachHandProp)
  end
  return ok, window
end

-- someone threw us a key: see it fly in; lock.lua shows the catch prompt and asks the server
RegisterNetEvent('nz:client:carlock:catch', function(data)
  if type(data) ~= 'table' then return end
  local from = tonumber(data.from)
  local player = from and GetPlayerFromServerId(from) or -1
  local thrower = player ~= -1 and GetPlayerPed(player) or 0
  local window = Utils.clamp(tonumber(data.window) or 1800, 300, 6000)
  catchWatch = { deadline = now() + window + 2500, keyKind = data.keyKind }
  if thrower == 0 or not DoesEntityExist(thrower) then return end
  local design = data.keyKind == 'key' and 'key' or CarLock.defaultFobDesign()
  local me = PlayerPedId()
  flyProp(design, function() return GetPedBoneCoords(thrower, 57005, 0.0, 0.0, 0.0) end,
    function() return GetPedBoneCoords(me, 57005, 0.0, 0.0, 0.0) end, math.min(window * 0.45, 800))
end)

---------------------------------------------------------------------------------------
-- Drop: placement bar (E Place, H Hold in hand, G Cancel, Scroll Rotate)
---------------------------------------------------------------------------------------

--- Place a key on the ground with a preview (yields until placed / held / cancelled).
--- The ghost shows where the server puts it (0.45 m in front of you, on the ground).
---@param key table|string|nil
---@return boolean placed
function CarLock.startKeyPlacement(key)
  if state.busy then return false end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return CarLock.tossKeyFromVehicle(key) end
  local ref, err = itemRef(key)
  if not ref then
    notify('error', err)
    return false
  end
  state.busy = 'place'
  local ghost = createKeyProp(ref.design)
  if ghost then
    tempProps[ghost] = true
    SetEntityAlpha(ghost, 170, false)
    FreezeEntityPosition(ghost, true)
  end
  dropHandProp()
  hint({
    { keys = { 'E' }, label = L('Place') },
    { keys = { 'H' }, label = L('Hold in hand') },
    { keys = { 'G' }, label = L('Cancel') },
    { keys = { 'Scroll' }, label = L('Rotate') },
  })
  local rotation = 0.0
  local outcome = 'cancel'
  local zOffset = tonumber(type(propCfg().ground) == 'table' and propCfg().ground.zOffset) or 0.0
  while true do
    for _, c in ipairs({ CONTROL.pickup, CONTROL.cancelG, CONTROL.headlight, CONTROL.wheelNext, CONTROL.wheelPrev,
      CONTROL.weaponWheel, CONTROL.attack, CONTROL.aim, CONTROL.melee, CONTROL.melee2, CONTROL.melee3, CONTROL.pause }) do
      DisableControlAction(0, c, true)
    end
    if ghost and DoesEntityExist(ghost) then
      local c = GetEntityCoords(ped)
      local h = math.rad(GetEntityHeading(ped))
      local x, y = c.x - math.sin(h) * 0.45, c.y + math.cos(h) * 0.45
      local found, gz = GetGroundZFor_3dCoord(x, y, c.z + 0.5, false)
      SetEntityCoordsNoOffset(ghost, x, y, (found and gz or c.z - 0.95) + zOffset, false, false, false)
      SetEntityHeading(ghost, (GetEntityHeading(ped) + rotation) % 360.0)
    end
    if IsDisabledControlJustPressed(0, CONTROL.wheelNext) then rotation = rotation + 15.0 end
    if IsDisabledControlJustPressed(0, CONTROL.wheelPrev) then rotation = rotation - 15.0 end
    if IsDisabledControlJustPressed(0, CONTROL.pickup) then
      outcome = 'place'
      break
    elseif IsDisabledControlJustPressed(0, CONTROL.headlight) then
      outcome = 'hold'
      break
    elseif IsDisabledControlJustPressed(0, CONTROL.cancelG) or IsDisabledControlJustPressed(0, CONTROL.pause)
      or IsControlJustPressed(0, CONTROL.back) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
      break
    end
    Wait(0)
  end
  hint(nil)
  deleteProp(ghost)
  state.busy = nil
  if outcome == 'place' then
    -- the drop animation (lock.lua) with the key in the hand until it reaches the ground
    if groundCfg().animateDrops ~= false then propInHand(ref.design, 600) end
    local payload = keyPayload(ref)
    payload.heading = (GetEntityHeading(ped) + rotation) % 360.0
    local ok = CarLock.dropKey(payload)
    if ok then keyGone() elseif state.holding then CreateThread(attachHandProp) end
    return ok
  elseif outcome == 'hold' then
    if not state.holding then return CarLock.holdKey({ plate = ref.plate, slot = ref.slot, keyId = ref.keyId }) end
    CreateThread(attachHandProp)
  elseif state.holding then
    CreateThread(attachHandProp)
  end
  return false
end

--- Is a key action running (placement, aiming, throwing)? Other keybinds can stand back.
---@return boolean
function CarLock.fobBusy()
  return state.busy ~= nil
end

---------------------------------------------------------------------------------------
-- Side prompt actions, keybinds, NUI callbacks
---------------------------------------------------------------------------------------

local function inspectHeld()
  local ref = state.ref
  if not ref then return end
  if type(CarLock.openKeyInspect) ~= 'function' then
    notify('error', L('Something went wrong'))
    return
  end
  local ped = PlayerPedId()
  local posed = not IsPedInAnyVehicle(ped, false) and playAnim(ANIM.hold)
  local opts = ref.item and (ref.slot and { slot = ref.slot } or { keyId = ref.keyId, plate = ref.plate }) or nil
  if opts then
    CarLock.openKeyInspect(opts)
  else
    -- a virtual / owner key: there is no item to look at; the key ring shows it instead
    if type(CarLock.openKeyRing) == 'function' then CarLock.openKeyRing(ref.plate) end
  end
  if posed then
    SetTimeout(2500, function()
      if not IsNuiFocused() then StopAnimTask(PlayerPedId(), ANIM.hold[1], ANIM.hold[2], 1.0) end
    end)
  end
end

local ACTIONS = {
  throw = function() CarLock.startKeyThrow() end,
  inspect = inspectHeld,
  move = function() setMode('edit') end,
  help = function() setMode('help') end,
  close = function() CarLock.putAwayKey() end,
}

local function runAction(name)
  if not state.holding or state.busy or not ACTIONS[name] then return end
  if state.mode ~= 'hud' and name ~= 'close' then return end
  if IsNuiFocused() or IsPauseMenuActive() then return end
  CreateThread(ACTIONS[name])
end

NZ.NUI.register('fob:save', function(data)
  local x, y, scale = tonumber(data.x), tonumber(data.y), tonumber(data.scale)
  if not x or not y or not scale or x ~= x or y ~= y or scale ~= scale then return Utils.fail(L('Invalid request')) end
  local position = { x = Utils.clamp(x, 0, 1), y = Utils.clamp(y, 0, 1), scale = Utils.clamp(scale, 0.5, 2) }
  local ok, res = CarLock.savePlayerSettings({ fobPosition = position })
  if not ok then return Utils.fail(type(res) == 'string' and res or L('Something went wrong')) end
  setMode('hud')
  return Utils.ok(layout())
end)

NZ.NUI.register('fob:cancel', function()
  if state.mode ~= 'hud' then setMode('hud') end
  if not state.holding and not state.hideAt then state.hideAt = now() + 1500 end
  return Utils.ok(nil)
end)

NZ.NUI.register('fob:action', function(data)
  local name = type(data.action) == 'string' and data.action or nil
  if not name or not ACTIONS[name] then return Utils.fail(L('Invalid request')) end
  if name == 'throw' or name == 'inspect' then
    -- leave the focused mode first: these act in the world / open the key ring's card
    setMode('hud')
    CreateThread(function()
      Wait(100)
      runAction(name)
    end)
  elseif name == 'help' then
    setMode('help')
  else
    setMode('hud')
    if name == 'close' then CarLock.putAwayKey() end
  end
  return Utils.ok(nil)
end)

if CarLock.enabled() then
  local keys = type(hudCfg().keys) == 'table' and hudCfg().keys or {}
  local function bind(name, label, default, fn)
    if keys[name] == false then return end
    keybinds[name] = lib.addKeybind({
      name = 'nz_fob_' .. name,
      description = label,
      defaultKey = type(keys[name]) == 'string' and keys[name] or default,
      disabled = name ~= 'toggle',
      onPressed = fn,
    })
  end
  bind('toggle', L('Key fob: take out / put away'), 'K', function()
    if state.busy or IsNuiFocused() or not canAct() then return end
    if state.holding then
      CarLock.putAwayKey()
    else
      CreateThread(function() CarLock.holdKey(nil) end)
    end
  end)
  bind('throw', L('Key fob: throw / toss the key'), 'Y', function() runAction('throw') end)
  bind('inspect', L('Key fob: inspect the key'), 'I', function() runAction('inspect') end)
  bind('move', L('Key fob: move / resize'), 'M', function() runAction('move') end)
  bind('help', L('Key fob: help'), 'H', function() runAction('help') end)
end

-- the player's position / size changed elsewhere (settings screen)
AddEventHandler('nz:client:carlock:playerSettings', function()
  if state.open then push({ layout = layout() }) end
end)

AddEventHandler('nz:client:playerUnloaded', function()
  CarLock.putAwayKey()
  hideHud()
  state.key, state.ref, state.lastPlate = nil, nil, nil
  keyList.at = -1e9
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  dropHandProp()
  for prop in pairs(tempProps) do deleteProp(prop) end
  if state.busy then NZ.NUI.hint(nil) end
end)
