--[[
  Headless test for the admin key manager CLIENT side (no FiveM needed):
  client/carlock/keyadmin.lua with shared/utils.lua and a stubbed NUI bridge / server.

    CarLock.openKeyAdmin (default page, deep link options cleaned, refused while another
    window is open, open once) -> every keyadmin:* callback forwards to its nz:carlock:admin:*
    server callback with only the allowed fields (bad identifiers / plates / types never reach
    the server) -> rows and plate data get labels and makes from the client (spawn name, else a
    visible entity) -> keyadmin:waypoint sets the waypoint at the SERVER's position and refuses
    a vehicle that is not out (no waypoint from page data) -> settings forward values and
    reset ids (junk ids dropped).

  Usage (from the resource root):  lua5.4 tools/smoke/keyadmin_client.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

-- runtime stubs ---------------------------------------------------------------------
NZ = { Utils = {}, NUI = {}, CarLock = {}, Veh = {} }
Config = { CarLock = { fob = { defaultDesign = 'sport' }, tempKeyHours = 12 } }
lib = { print = { error = function() end, warn = function() end, info = function() end } }
function L(text, vars)
  if vars then text = text:gsub('{(%w+)}', function(k) return tostring(vars[k]) end) end
  return text
end
dofile('shared/utils.lua')
local Utils = NZ.Utils

function joaat(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end return h end
local cdimage = { [joaat('jester4')] = true, [joaat('italigto')] = true }
function IsModelInCdimage(h) return cdimage[h] == true end
local entities = { [77] = { model = joaat('italigto') } }
function NetworkDoesNetworkIdExist(id) return entities[id] ~= nil end
function NetToVeh(id) return entities[id] and id or 0 end
function DoesEntityExist(e) return entities[e] ~= nil end
function GetEntityModel(e) return entities[e].model end
local waypoint = nil
function SetNewWaypoint(x, y) waypoint = { x = x, y = y } end

NZ.Veh.label = function(hash)
  if hash == joaat('jester4') then return 'Dinka Jester RR', 'Dinka', 'Jester RR' end
  if hash == joaat('italigto') then return 'Grotti Itali GTO', 'Grotti', 'Itali GTO' end
  return 'Unknown vehicle', '', 'Unknown vehicle'
end

local CarLock = NZ.CarLock
function CarLock.cfg() return Config.CarLock end
function CarLock.keyMode() return 'limited' end

-- NUI bridge
local nui = { handlers = {}, open = {}, notified = {}, sent = {} }
function NZ.NUI.register(name, fn) nui.handlers[name] = fn end
function NZ.NUI.isOpen(app)
  if app == nil then return next(nui.open) ~= nil end
  return nui.open[app] ~= nil
end
function NZ.NUI.open(app, data) nui.open[app] = data end
function NZ.NUI.onClose(app, fn) nui.closeHook = fn end
function NZ.NUI.notify(kind, msg) nui.notified[#nui.notified + 1] = { kind, msg } end
function NZ.NUI.send(action, data) nui.sent[#nui.sent + 1] = { action, data } end

-- scripted server
local calls = {}
local answers = {}
function NZ.NUI.await(name, payload)
  calls[#calls + 1] = { name = name, payload = payload }
  local a = answers[name]
  if type(a) == 'function' then return a(payload) end
  return a or Utils.ok({})
end
local function lastCall() return calls[#calls] end

dofile('client/carlock/keyadmin.lua')
local function cb(name, data) return nui.handlers[name](data or {}) end

-- opening ----------------------------------------------------------------------------
nui.open.garage = {}
check(CarLock.openKeyAdmin() == false, 'refused while another window is open')
check(#nui.notified == 1 and nui.notified[1][1] == 'error', 'told to close the other window')
nui.open.garage = nil

check(CarLock.openKeyAdmin({ page = 'nope', settingsTab = 'evil', identifier = 'char1:AB\n', plate = ' gto 88 ', query = string.rep('x', 70) }) == true, 'opens')
local od = nui.open.keyadmin
check(od ~= nil, 'keyadmin app open')
check(od.page == 'keys', 'unknown page -> keys')
check(od.settingsTab == nil, 'unknown settings tab dropped')
check(od.identifier == 'char1:AB', 'control characters stripped from the identifier')
check(od.plate == 'GTO 88', 'plate trimmed and upper case')
check(od.query == nil, 'too long query dropped')
check(od.fobDesign == 'sport' and od.tempKeyHours == 12 and od.keyMode == 'limited', 'config hints passed')
check(CarLock.openKeyAdmin({ page = 'settings' }) == true and nui.open.keyadmin == od, 'already open: not re-opened')
nui.open.keyadmin = nil
CarLock.openKeyAdmin({ page = 'settings', settingsTab = 'ground' })
check(nui.open.keyadmin.page == 'settings' and nui.open.keyadmin.settingsTab == 'ground', 'settings deep link')
nui.open.keyadmin = nil

-- search / player ---------------------------------------------------------------------
cb('keyadmin:search', { query = 'ma\tr' .. string.rep('a', 80) })
check(lastCall().name == 'nz:carlock:admin:search', 'search forwarded')
check(#lastCall().payload.query <= 64 and not lastCall().payload.query:find('%c'), 'query cleaned and capped')

local n = #calls
local res = cb('keyadmin:player', { identifier = '' })
check(res.ok == false and #calls == n, 'empty identifier never reaches the server')
answers['nz:carlock:admin:player'] = function()
  return Utils.ok({ player = { identifier = 'char1:X', name = 'Mara', online = true }, totals = {},
    keys = {
      { id = 'owner:52MZL952', plate = '52MZL952', model = 'jester4', type = 'owner' },
      { id = 'item:GTO 88:a1', plate = 'GTO 88', type = 'fob', netId = 77 },
      { id = 'temp:ZZZ', plate = 'ZZZ', type = 'temp' },
      { id = 'temp:BAD', plate = 'BAD', model = 'notamodel', type = 'temp' },
    } })
end
res = cb('keyadmin:player', { identifier = 'char1:X', extra = 'x' })
check(lastCall().payload.extra == nil and lastCall().payload.identifier == 'char1:X', 'only the identifier is sent')
local rows = res.data.keys
check(rows[1].label == 'Dinka Jester RR' and rows[1].make == 'Dinka' and rows[1].hash == joaat('jester4'), 'label / make from the spawn name')
check(rows[2].label == 'Grotti Itali GTO' and rows[2].make == 'Grotti', 'label from a visible entity without a model')
check(rows[3].label == nil and rows[3].hash == nil, 'unknown vehicle: no label')
check(rows[4].hash == nil, 'a model that is not in the game files is ignored')

-- give / delete -----------------------------------------------------------------------
n = #calls
check(cb('keyadmin:give', { identifier = 'char1:X', plate = 'ABC', type = 'owner' }).ok == false and #calls == n, 'unknown give type refused')
check(cb('keyadmin:give', { identifier = 'char1:X', plate = 'TOOLONGPLATE', type = 'temp' }).ok == false and #calls == n, 'plate over 8 refused')
cb('keyadmin:give', { identifier = 'char1:X', plate = 'abc 1', type = 'item', keyKind = 'fob', hours = 5 })
local p = lastCall().payload
check(lastCall().name == 'nz:carlock:admin:give' and p.plate == 'ABC 1' and p.keyKind == 'fob' and p.hours == nil, 'item give: kind, no hours')
cb('keyadmin:give', { identifier = 'char1:X', plate = 'ABC', type = 'temp', keyKind = 'fob', hours = '6' })
p = lastCall().payload
check(p.hours == 6 and p.keyKind == nil, 'temp give: hours, no kind')
cb('keyadmin:give', { identifier = 'char1:X', plate = 'ABC', type = 'item', keyKind = 'gold' })
check(lastCall().payload.keyKind == nil, 'unknown kind dropped (server picks)')
cb('keyadmin:delete', { identifier = 'char1:X', id = 'item:ABC:a1' })
check(lastCall().name == 'nz:carlock:admin:delete' and lastCall().payload.id == 'item:ABC:a1', 'delete forwarded')
n = #calls
check(cb('keyadmin:delete', { identifier = 'char1:X', id = string.rep('a', 65) }).ok == false and #calls == n, 'long id refused')

-- plate / track / waypoint ------------------------------------------------------------
answers['nz:carlock:admin:plate'] = Utils.ok({ plate = 'GTO 88', model = 'italigto', custody = {} })
res = cb('keyadmin:plate', { plate = 'gto 88' })
check(lastCall().payload.plate == 'GTO 88' and res.data.label == 'Grotti Itali GTO' and res.data.make == 'Grotti', 'plate view labelled')

answers['nz:carlock:admin:track'] = function(pl)
  if pl.plate == 'GTO 88' then return Utils.ok({ plate = 'GTO 88', spawned = true, coords = { x = 100.5, y = -200.25, z = 30 } }) end
  return Utils.ok({ plate = pl.plate, spawned = false })
end
res = cb('keyadmin:track', { plate = 'GTO 88' })
check(res.ok and res.data.spawned, 'track forwarded')
res = cb('keyadmin:waypoint', { plate = 'GTO 88', x = 9999, y = 9999 })
check(lastCall().name == 'nz:carlock:admin:track', 'waypoint asks the server')
check(res.ok and waypoint and waypoint.x == 100.5 and waypoint.y == -200.25, 'waypoint at the server position, page coordinates ignored')
waypoint = nil
res = cb('keyadmin:waypoint', { plate = 'NOPE' })
check(res.ok == false and waypoint == nil, 'no waypoint for a vehicle that is not out')

-- settings ----------------------------------------------------------------------------
cb('keyadmin:settings')
check(lastCall().name == 'nz:carlock:admin:settings', 'settings forwarded')
cb('keyadmin:saveSettings', { values = { ['keys.remoteRange'] = 40 }, reset = { 'ground.markerColor', 5, string.rep('x', 70) } })
p = lastCall().payload
check(lastCall().name == 'nz:carlock:admin:saveSettings' and p.values['keys.remoteRange'] == 40, 'values forwarded')
check(#p.reset == 1 and p.reset[1] == 'ground.markerColor', 'junk reset ids dropped')
cb('keyadmin:saveSettings', {})
p = lastCall().payload
check(type(p.values) == 'table' and #p.reset == 0, 'empty save is well formed')

if #failures > 0 then
  print(('keyadmin_client: %d of %d checks FAILED'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('keyadmin_client: all %d checks passed'):format(checks))
