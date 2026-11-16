--[[
  Headless test for the fob HUD and physical key actions (client/carlock/fob.lua) on top of
  client/carlock/lock.lua, in a stubbed client runtime with a scripted server (no FiveM):
    keybinds (toggle on, side prompts off until the key is held) -> a lock press opens the HUD
    with the pressed button and hides it again -> lock.lua's feedback event and the item event
    count once -> taking the key out: prop from Config.CarLock.fobProps (design model, fallback
    when missing) on the configured hand bone -> fob:save validates and clamps, saves
    fobPosition -> placement: G cancels without a server call, E drops (slot, heading, never a
    position) -> throw: aim + E sends the target's server id -> driver seat: window toss ->
    virtual keys cannot be dropped -> edit mode takes focus, fob:cancel gives it back -> resource
    stop deletes every prop.

  Usage (from the resource root):  lua5.4 tools/smoke/fobhud.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

local clock = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function GetGameTimer() return clock end
local function runDue()
  local list = {}
  for i = 1, #threads do list[i] = threads[i] end
  for _, t in ipairs(list) do
    if coroutine.status(t.co) == 'suspended' and t.wake <= clock then
      local okR, res = coroutine.resume(t.co)
      if not okR then failures[#failures + 1] = 'thread error: ' .. debug.traceback(t.co, tostring(res)) end
      t.wake = clock + (tonumber(res) or 0)
    end
  end
  for i = #threads, 1, -1 do
    if coroutine.status(threads[i].co) == 'dead' then table.remove(threads, i) end
  end
end
local function advance(ms)
  local target = clock + ms
  runDue()
  while clock < target do
    clock = math.min(target, clock + 50)
    runDue()
  end
end
local function run(fn, ...)
  local args = table.pack(...)
  local results
  CreateThread(function() results = table.pack(fn(table.unpack(args, 1, args.n))) end)
  local guard = 0
  runDue()
  while not results do
    clock = clock + 50
    runDue()
    guard = guard + 1
    if guard > 5000 then error('run(): never returned') end
  end
  return table.unpack(results, 1, results.n)
end

local handlers = {}
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  table.insert(handlers[name], { name = name, fn = fn })
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...) for _, e in ipairs(handlers[name] or {}) do e.fn(...) end end
function TriggerServerEvent() end
function RegisterCommand() end

-- world -------------------------------------------------------------------------------
local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
vector3 = vec3
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec4 = vector4
local function joaat_(s)
  local h = 0
  for i = 1, #tostring(s) do h = (h * 31 + tostring(s):lower():byte(i)) & 0x7fffffff end
  return h
end
joaat = joaat_
GetHashKey = joaat_

local PED, OTHER = 101, 102
local vehicles = { [201] = { plate = 'ABC123', net = 55, coords = vec3(3, 0, 0), class = 0 } }
local seated = nil
local states = {}
function Entity(h)
  states[h] = states[h] or setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })
  return { state = states[h] }
end
local objects, nextObject, created, attached, deleted = {}, 500, {}, {}, {}
local missingModels = {}
function CreateObject(hash) nextObject = nextObject + 1 objects[nextObject] = hash created[#created + 1] = hash return nextObject end
function IsModelInCdimage(hash) return not missingModels[hash] end
function IsModelValid(hash) return not missingModels[hash] end
function HasModelLoaded() return true end
function AttachEntityToEntity(prop, ped, bone) attached[#attached + 1] = { prop = prop, ped = ped, bone = bone } end
function GetPedBoneIndex(_, id) return 'bone' .. tostring(id) end
function DeleteEntity(h) objects[h] = nil deleted[#deleted + 1] = h end
function PlayerPedId() return PED end
function PlayerId() return 0 end
function GetPlayerServerId(p) return p == 1 and 2 or 1 end
function GetActivePlayers() return { 0, 1 } end
function GetPlayerPed(p) return p == 1 and OTHER or PED end
function GetPlayerFromServerId(id) return id == 2 and 1 or -1 end
function HasEntityClearLosToEntity() return true end
function DoesEntityExist(h) return vehicles[h] ~= nil or h == PED or h == OTHER or objects[h] ~= nil end
function IsEntityAVehicle(h) return vehicles[h] ~= nil end
function NetworkGetEntityIsNetworked(h) return vehicles[h] ~= nil end
function NetworkGetNetworkIdFromEntity(h) return vehicles[h] and vehicles[h].net or 0 end
function NetworkDoesNetworkIdExist(net) return net == 55 end
function NetworkGetEntityFromNetworkId(net) return net == 55 and 201 or 0 end
function GetVehicleNumberPlateText(h) return vehicles[h] and vehicles[h].plate or '' end
function GetEntityModel() return joaat_('sultan') end
function GetVehicleClass(h) return vehicles[h] and vehicles[h].class or 0 end
function GetEntityCoords(h)
  if vehicles[h] then return vehicles[h].coords end
  if h == OTHER then return vec3(4, 0, 0) end
  return vec3(0, 0, 0)
end
function GetPedBoneCoords() return vec3(0, 0, 1) end
function GetEntityHeading() return 90.0 end
function GetGameplayCamRot() return vec3(0, 0, -90) end
function GetGameplayCamCoord() return vec3(0, 0, 1) end
function GetGroundZFor_3dCoord() return true, -1.0 end
function GetVehiclePedIsIn() return seated or 0 end
function GetPedInVehicleSeat(h, s) if seated == h and s == -1 then return PED end return 0 end
function IsPedInAnyVehicle() return seated ~= nil end
function IsPauseMenuActive() return false end
local nuiFocus = false
function IsNuiFocused() return nuiFocus end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
local pressed = {}
function IsDisabledControlJustPressed(_, c) if pressed[c] then pressed[c] = nil return true end return false end
function IsControlJustPressed() return false end
function GetCloudTimeAsInt() return 1000 end
function GetMakeNameFromVehicleModel() return 'KARIN' end
function GetResourceState(name) if name == 'qb-core' or name == 'ox_inventory' then return 'started' end return 'missing' end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return false end
function AddStateBagChangeHandler() return 1 end
setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

-- ox_lib + scripted server ------------------------------------------------------------
local server, calls = {}, {}
local function answer(name, payload)
  calls[name] = calls[name] or {}
  table.insert(calls[name], payload)
  local fn = server[name]
  if not fn then return { ok = false, error = 'no server' } end
  return fn(payload)
end
local keybinds = {}
lib = {
  print = { info = function() end, warn = function() end, error = function(...) failures[#failures + 1] = 'lib.print.error ' .. table.concat({ ... }, ' ') end },
  callback = setmetatable({ await = function(name, _, payload) Wait(50) return answer(name, payload) end },
    { __call = function(_, name, _, cb, payload) CreateThread(function() Wait(50) local r = answer(name, payload) if cb then cb(r) end end) end }),
  onCache = function() end,
  addKeybind = function(o)
    o.disable = function(self, v) self.disabled = v end
    o.getCurrentKey = function(self) return self.defaultKey end
    keybinds[o.name] = o
    return o
  end,
  getNearbyVehicles = function(coords, dist)
    local out = {}
    for h, v in pairs(vehicles) do if #(v.coords - coords) <= dist then out[#out + 1] = { vehicle = h, coords = v.coords } end end
    return out
  end,
  requestAnimDict = function() return true end,
  requestModel = function() return true end,
}
cache = { ped = PED, playerId = 0 }
exports = setmetatable({}, { __call = function() end, __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end })
json = { encode = function() return '{}' end, decode = function() return {} end }

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local okLoad, err = xpcall(assert(load(src, '@' .. file, 't', _ENV)), debug.traceback)
  if not okLoad then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end
load_('config/config.lua')
load_('config/carlock.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
load_('shared/carlock.lua')
load_('bridge/shared.lua')

-- NUI bridge stub: records what the fob app gets
local nui = { opened = {}, sent = {}, closed = 0, focus = false, hints = {}, notes = {}, handlers = {}, closeHooks = {} }
NZ.NUI.notify = function(kind, message) nui.notes[#nui.notes + 1] = { kind = kind, message = message } end
NZ.NUI.prompt = function() end
NZ.NUI.hint = function(d) nui.hints[#nui.hints + 1] = d or false end
NZ.NUI.open = function(app, data, focus) nui.isOpen = app == 'fob' nui.opened[#nui.opened + 1] = { app = app, data = data } nui.focus = focus ~= false nuiFocus = nui.focus end
NZ.NUI.send = function(action, data) nui.sent[#nui.sent + 1] = { action = action, data = data } end
NZ.NUI.close = function() nui.isOpen = false nui.closed = nui.closed + 1 nui.focus = false nuiFocus = false for _, fn in ipairs(nui.closeHooks) do fn('fob', 'lua') end end
NZ.NUI.isOpen = function() return nui.isOpen == true end
NZ.NUI.hasFocus = function() return nui.focus end
NZ.NUI.setFocus = function(_, on) nui.focus = on nuiFocus = on end
NZ.NUI.onClose = function(_, fn) nui.closeHooks[#nui.closeHooks + 1] = fn end
NZ.NUI.register = function(name, fn) nui.handlers[name] = fn end
NZ.State.settings = {}
NZ.Veh = { label = function() return 'Karin Sultan', 'Karin' end }
load_('client/carlock/lock.lua')
load_('client/carlock/fob.lua')
advance(2500)
local CarLock = NZ.CarLock
local function lastPush() return nui.sent[#nui.sent] and nui.sent[#nui.sent].data and nui.sent[#nui.sent].data.data or nil end
local function cb(name, data) return run(nui.handlers[name], data or {}) end

server['nz:carlock:keys'] = function()
  return { ok = true, data = { mode = 'physical', keys = {
    { plate = 'ABC123', kind = 'item', keyKind = 'fob', slot = 3, keyId = 'K1', model = 'sultan' },
    { plate = 'VIRT01', kind = 'owner' },
  } } }
end
server['nz:carlock:ground:list'] = function() return { ok = true, data = {} } end

-- 1. keybinds ------------------------------------------------------------------------
check(keybinds.nz_fob_toggle and keybinds.nz_fob_toggle.disabled ~= true, 'toggle keybind registered and on')
check(keybinds.nz_fob_throw and keybinds.nz_fob_throw.disabled == true, 'side prompt keys off until a key is held')
check(nui.handlers['fob:save'] and nui.handlers['fob:cancel'] and nui.handlers['fob:action'], 'fob:* NUI callbacks registered')

-- 2. a lock press opens the HUD, then it hides --------------------------------------------
server['nz:carlock:toggleLock'] = function(p) return { ok = true, data = { netId = p.netIds[1], plate = 'ABC123', locked = true, kind = 'item' } } end
run(CarLock.toggleLock)
advance(300)
local open = nui.opened[#nui.opened]
check(open and open.app == 'fob' and open.data.key and open.data.key.plate == 'ABC123', 'lock press opens the fob HUD with that key')
check(open and open.data.key.design == 'classic' and open.data.key.kind == 'fob' and open.data.key.make == 'Karin', 'HUD key: default design, fob, make')
check(nui.focus == false, 'HUD without NUI focus')
local p = lastPush()
check(p and p.press and p.press.button == 'lock' and p.press.beep == false, 'lock button pressed, no NUI beep (the game beeps)')
advance(5000)
check(nui.isOpen == false, 'HUD hides after a few seconds')

-- 3. two hooks for one press count once ---------------------------------------------------
local pushes = #nui.sent
TriggerEvent('nz:client:carlock:feedback', { plate = 'ABC123', netId = 55, locked = false })
TriggerEvent('nz:client:carlock:used', { plate = 'ABC123', locked = false })
advance(400)
local presses = 0
for i = pushes + 1, #nui.sent do
  local d = nui.sent[i].data and nui.sent[i].data.data
  if d and d.press and d.press.button == 'unlock' then presses = presses + 1 end
end
check(presses == 1, 'feedback event + item event: one press')
advance(5000)

-- 4. take the key out: props from Config.CarLock.fobProps ---------------------------------
local cfgProps = Config.CarLock.fobProps
missingModels[joaat_(cfgProps.byDesign.classic)] = true
local customFallback = cfgProps.fallback
cfgProps.fallback = 'p_car_keys_01'
keybinds.nz_fob_toggle.onPressed()
advance(400)
check(keybinds.nz_fob_throw.disabled == false, 'side prompt keys on while holding')
local lastOpen = nui.opened[#nui.opened]
check(nui.isOpen and lastOpen.data.holding ~= nil, 'holding opens the HUD')
check(created[#created] == joaat_('p_car_keys_01'), 'design model missing: fobProps.fallback used')
check(attached[#attached] and attached[#attached].bone == 'bone' .. tostring(cfgProps.hand.bone), 'prop on the configured hand bone')
missingModels = {}
cfgProps.fallback = customFallback

-- 5. fob:save ----------------------------------------------------------------------------
server['nz:carlock:savePlayerSettings'] = function(pl) return { ok = true, data = { settings = { fobPosition = pl.settings.fobPosition } } } end
local bad = cb('fob:save', { x = 'a', y = 1, scale = 1 })
check(type(bad) == 'table' and bad.ok == false, 'fob:save refuses non-numbers')
local res = cb('fob:save', { x = 1.5, y = 0.2, scale = 9 })
local saved = calls['nz:carlock:savePlayerSettings'] and calls['nz:carlock:savePlayerSettings'][1]
check(res and res.ok and saved and saved.settings.fobPosition.x == 1 and saved.settings.fobPosition.scale == 2, 'fob:save clamps and saves fobPosition')

-- 6. edit mode focus ---------------------------------------------------------------------
keybinds.nz_fob_move.onPressed()
advance(100)
check(nui.focus == true and lastPush().mode == 'edit', 'Move: edit mode with focus')
cb('fob:cancel')
check(nui.focus == false and lastPush().mode == 'hud', 'fob:cancel leaves edit mode and the focus')

-- 7. placement: G cancels, E drops --------------------------------------------------------
server['nz:carlock:ground:drop'] = function() return { ok = true, data = { id = 'g1' } } end
CreateThread(function() Wait(300) pressed[47] = true end)
local placed = run(CarLock.startKeyPlacement, 'ABC123')
check(placed == false and not calls['nz:carlock:ground:drop'], 'G cancels the placement without a server call')
local hintShown = false
for _, h in ipairs(nui.hints) do if h and h.keys and #h.keys == 4 then hintShown = true end end
check(hintShown, 'placement prompt bar (E / H / G / Scroll)')
CreateThread(function() Wait(300) pressed[14] = true Wait(100) pressed[38] = true end)
placed = run(CarLock.startKeyPlacement, 'ABC123')
local drop = calls['nz:carlock:ground:drop'] and calls['nz:carlock:ground:drop'][1]
check(placed == true and drop and drop.slot == 3 and drop.x == nil and drop.coords == nil, 'E drops the key item (slot), never a position')
check(nui.isOpen == false, 'the dropped key leaves the hand and the HUD')

-- 8. virtual keys cannot be dropped --------------------------------------------------------
local before = #nui.notes
check(run(CarLock.startKeyPlacement, 'VIRT01') == false and #nui.notes == before + 1, 'virtual / owner keys: refused with a message')

-- 9. throw: aim + E sends the target's server id -------------------------------------------
server['nz:carlock:ground:throw'] = function() return { ok = true, data = { id = 'f1', window = 1800 } } end
run(CarLock.holdKey, 'ABC123')
CreateThread(function() Wait(300) pressed[38] = true end)
run(CarLock.startKeyThrow)
local throw = calls['nz:carlock:ground:throw'] and calls['nz:carlock:ground:throw'][1]
check(throw and throw.target == 2 and throw.slot == 3, 'throw goes to the aimed player (server id)')
advance(1500)

-- 10. driver seat: window toss --------------------------------------------------------------
seated = 201
calls['nz:carlock:ground:drop'] = nil
run(CarLock.tossKeyFromVehicle, 'ABC123')
local toss = calls['nz:carlock:ground:drop'] and calls['nz:carlock:ground:drop'][1]
check(toss and toss.toss == true and toss.slot == 3, 'driver seat: toss out of the window')
seated = nil
advance(1000)

-- 11. catch visual and cleanup -----------------------------------------------------------
TriggerEvent('nz:client:carlock:catch', { id = 'x', from = 2, window = 1500, keyKind = 'fob' })
advance(200)
run(CarLock.holdKey, 'ABC123')
advance(300)
TriggerEvent('onResourceStop', NZ.ResourceName)
local alive = 0
for _ in pairs(objects) do alive = alive + 1 end
check(alive == 0, 'resource stop deletes every key prop')

if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('fob hud OK (%d checks)'):format(checks))
