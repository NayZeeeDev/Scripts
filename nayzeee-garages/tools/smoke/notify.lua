--[[
  Headless test for the notification integration (bridge/client/notify.lua) and the
  'notify' NUI callback / nz:client:notify event in client/nui.lua. No FiveM needed.

  Loads the real files in a stubbed client environment and checks, for every value of
  Config.Integrations.notify, the exact call each notification system receives, plus the
  ox_lib fallback (resource stopped / adapter error), text sanitizing, limits and the
  callback validation + rate limit.

  Usage (from the resource root):  lua5.4 tools/smoke/notify.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

local function deepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function dump(v)
  if type(v) ~= 'table' then return type(v) == 'string' and ('%q'):format(v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. '=' .. dump(v[k]) end
  return '{' .. table.concat(parts, ', ') .. '}'
end

---------------------------------------------------------------------------------------
-- Stubbed runtime
---------------------------------------------------------------------------------------

local calls, warnings, errors, printed = {}, {}, {}, {}
local states = {}
local now = 100000
local throwIn = {}

local function record(name, ...)
  if throwIn[name] then error('boom in ' .. name) end
  calls[#calls + 1] = { name = name, args = table.pack(...) }
end

function GetResourceState(name) return states[name] or 'missing' end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return false end
function GetGameTimer() return now end
function TriggerEvent(name, ...) record('event:' .. name, ...) end
local handlers, nuiCallbacks = {}, {}
function RegisterNetEvent(name, fn) if fn then handlers[name] = fn end end
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
function SendNUIMessage() end
function SetNuiFocus() end
function SetNuiFocusKeepInput() end
function CreateThread(fn) local co = coroutine.create(fn) local ok, e = coroutine.resume(co) if not ok then error(e) end end
function Wait() end
print = function(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end printed[#printed + 1] = table.concat(t, ' ') end

lib = {
  notify = function(data) record('lib.notify', data) end,
  print = {
    warn = function(msg) warnings[#warnings + 1] = msg end,
    error = function(msg) errors[#errors + 1] = msg end,
    info = function() end,
  },
  callback = { await = function() return { ok = false, error = 'stub' } end },
}

exports = setmetatable({}, {
  __index = function(_, resource)
    return setmetatable({}, {
      __index = function(_, fn)
        return function(_, ...) record(resource .. ':' .. fn, ...) end
      end,
    })
  end,
})

local loadChunk = load
local function loadFile(path)
  local f = assert(io.open(path, 'r'))
  local src = f:read('a')
  f:close()
  local chunk = assert(loadChunk(src, '@' .. path, 't', _ENV))
  chunk()
end

loadFile('config/config.lua')
loadFile('shared/init.lua')
loadFile('shared/utils.lua')
loadFile('locales/en.lua')
Config.Locale = 'en'

local baseNotify = { title = 'Garage', position = 'top-right', duration = 5000 }

--- Fresh NZ.Notify with the given integration / framework / running resources.
local function setup(integration, opts)
  opts = opts or {}
  NZ.Notify = {}
  NZ.Framework = opts.framework or 'qb'
  Config.Integrations.notify = integration
  Config.Notify = opts.notify or { title = baseNotify.title, position = baseNotify.position, duration = baseNotify.duration }
  states = { ox_lib = 'started' }
  for _, r in ipairs(opts.running or {}) do states[r] = 'started' end
  calls, warnings, errors, printed, throwIn = {}, {}, {}, {}, {}
  now = now + 10000
  loadFile('bridge/client/notify.lua')
  return NZ.Notify
end

local function expectCall(label, name, ...)
  local want = table.pack(...)
  local got = calls[#calls]
  local ok = got and got.name == name and got.args.n == want.n
  if ok then
    for i = 1, want.n do
      if not deepEq(got.args[i], want[i]) then ok = false break end
    end
  end
  if not ok then
    local desc = got and (got.name .. ' ' .. dump({ table.unpack(got.args, 1, got.args.n) })) or 'no call'
    failures[#failures + 1] = ('%s: expected %s %s, got %s'):format(label, name, dump({ ... }), desc)
  end
  checks = checks + 1
end

---------------------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------------------

local N = setup('ox_lib')
N.show('info', 'Vehicle stored')
expectCall('ox_lib', 'lib.notify', { title = 'Garage', description = 'Vehicle stored', type = 'info', duration = 5000, position = 'top-right' })
N.show('success', 'Saved', 'Settings saved', 8000)
expectCall('ox_lib explicit', 'lib.notify', { title = 'Settings saved', description = 'Saved', type = 'success', duration = 8000, position = 'top-right' })

N = setup('qb', { running = { 'qb-core' } })
N.show('info', 'Vehicle stored')
expectCall('qb config title', 'event:QBCore:Notify', { text = 'Vehicle stored', caption = 'Garage' }, 'primary', 5000)
N.show('warning', 'Changes apply now.', 'Settings saved')
expectCall('qb explicit title', 'event:QBCore:Notify', { text = 'Settings saved', caption = 'Changes apply now.' }, 'warning', 5000)
N = setup('qb', { running = { 'qb-core' }, notify = { title = '', duration = 4000 } })
N.show('error', 'No money')
expectCall('qb no title', 'event:QBCore:Notify', 'No money', 'error', 4000)

N = setup('qbx', { running = { 'qbx_core' } })
N.show('info', 'Vehicle stored')
expectCall('qbx', 'qbx_core:Notify', 'Vehicle stored', 'inform', 5000)
N.show('success', 'Sultan was added.', 'Vehicle assigned')
expectCall('qbx explicit', 'qbx_core:Notify', 'Vehicle assigned', 'success', 5000, 'Sultan was added.')

N = setup('esx', { running = { 'es_extended' } })
N.show('warning', 'Garage almost full')
expectCall('esx', 'event:esx:showNotification', 'Garage almost full', 'warning', 5000, 'Garage')

N = setup('okokNotify', { running = { 'okokNotify' } })
N.show('success', 'Vehicle stored')
expectCall('okokNotify', 'okokNotify:Alert', 'Garage', 'Vehicle stored', 5000, 'success', false)

N = setup('mythic_notify', { running = { 'mythic_notify' } })
N.show('info', 'Vehicle stored')
expectCall('mythic info', 'mythic_notify:DoCustomHudText', 'inform', 'Vehicle stored', 5000, nil)
N.show('warning', 'Payment due soon', 'Finance')
local last = calls[#calls]
check(last and last.args[1] == 'inform' and last.args[2] == 'Finance: Payment due soon' and type(last.args[4]) == 'table',
  'mythic warning: inform + amber style + joined explicit title, got ' .. dump(last and { table.unpack(last.args, 1, last.args.n) }))

N = setup('pNotify', { running = { 'pNotify' } })
N.show('error', 'R&D <b>bold</b>')
expectCall('pNotify', 'pNotify:SendNotification', { text = '<b>Garage</b><br>R&amp;D ‹b›bold‹/b›', type = 'error', timeout = 5000, layout = 'topRight' })

N = setup('wasabi_notify', { running = { 'wasabi_notify' } })
N.show('error', 'No money')
expectCall('wasabi_notify', 'wasabi_notify:notify', 'Garage', 'No money', 5000, 'error')

N = setup('brutal_notify', { running = { 'brutal_notify' } })
N.show('info', 'Waypoint set')
expectCall('brutal_notify', 'brutal_notify:SendAlert', 'Garage', 'Waypoint set', 5000, 'info', false)

N = setup('lation_ui', { running = { 'lation_ui' } })
N.show('success', 'Vehicle stored')
expectCall('lation_ui', 'lation_ui:notify', { title = 'Garage', message = 'Vehicle stored', type = 'success', duration = 5000, position = 'top-right' })

N = setup('t-notify', { running = { 't-notify' } })
N.show('warning', 'Garage almost full')
expectCall('t-notify custom', 't-notify:Custom', { style = 'warning', title = 'Garage', message = 'Garage almost full', duration = 5000 })
N = setup('t-notify', { running = { 't-notify' }, notify = { title = '' } })
N.show('info', 'Vehicle stored')
expectCall('t-notify alert', 't-notify:Alert', { style = 'info', message = 'Vehicle stored', duration = 5000 })

-- framework
for fw, want in pairs({ qb = 'event:QBCore:Notify', qbx = 'qbx_core:Notify', esx = 'event:esx:showNotification', standalone = 'lib.notify' }) do
  N = setup('framework', { framework = fw, running = { 'qb-core', 'qbx_core', 'es_extended' } })
  N.show('info', 'Hello ' .. fw)
  check(calls[#calls] and calls[#calls].name == want, 'framework ' .. fw .. ' -> ' .. want)
end

-- auto
N = setup('auto', { running = { 'brutal_notify' } })
N.show('info', 'Auto')
check(calls[#calls] and calls[#calls].name == 'brutal_notify:SendAlert', 'auto picks a running notify resource')
N = setup('auto')
N.show('info', 'Auto')
check(calls[#calls] and calls[#calls].name == 'lib.notify', 'auto falls back to ox_lib')

-- aliases / unknown value
N = setup('OKOKNOTIFY', { running = { 'okokNotify' } })
N.show('info', 'Alias')
check(calls[#calls] and calls[#calls].name == 'okokNotify:Alert', 'case-insensitive config value')
N = setup('t_notify', { running = { 't-notify' } })
N.show('info', 'Alias')
check(calls[#calls] and calls[#calls].name == 't-notify:Custom', 't_notify alias')
N = setup('nonsense')
N.show('info', 'Unknown')
check(calls[#calls] and calls[#calls].name == 'lib.notify' and #warnings == 1, 'unknown integration -> ox_lib + one warning')

---------------------------------------------------------------------------------------
-- Fallbacks & robustness
---------------------------------------------------------------------------------------

N = setup('okokNotify') -- not started
N.show('info', 'One')
N.show('info', 'Two')
check(#calls == 2 and calls[1].name == 'lib.notify' and calls[2].name == 'lib.notify', 'stopped resource -> ox_lib')
check(#warnings == 1, 'stopped resource warns once (got ' .. #warnings .. ')')

N = setup('wasabi_notify', { running = { 'wasabi_notify' } })
throwIn['wasabi_notify:notify'] = true
check(N.show('error', 'Adapter throws') == true and calls[#calls].name == 'lib.notify', 'adapter error -> ox_lib')

N = setup('custom')
N.show('info', 'Custom default')
check(calls[#calls] and calls[#calls].name == 'lib.notify', 'custom returning false -> ox_lib')
N = setup('custom')
local seen
N.custom = function(kind, message, title, duration) seen = { kind, message, title, duration } end
N.show('warning', 'Custom handled')
check(#calls == 0 and deepEq(seen, { 'warning', 'Custom handled', 'Garage', 5000 }), 'custom receives (kind, message, title, duration) ' .. dump(seen))
N.custom = function() error('custom broke') end
check(N.show('info', 'Custom throws') == true and calls[#calls].name == 'lib.notify', 'custom error -> ox_lib')

N = setup('ox_lib')
throwIn['lib.notify'] = true
local ok, res = pcall(N.show, 'error', 'Everything broken')
check(ok and res == false and #printed == 1, 'ox_lib failure never throws, prints to console')

N = setup('ox_lib')
for _, bad in ipairs({ { nil }, { '' }, { '   ' }, { {} } }) do
  local okCall = pcall(N.show, 'info', bad[1])
  check(okCall, 'bad message never throws')
end
check(#calls == 1 and calls[1].args[1].description:sub(1, 6) == 'table:', 'nil / blank messages are ignored (a table is stringified)')

---------------------------------------------------------------------------------------
-- Normalization
---------------------------------------------------------------------------------------

N = setup('ox_lib')
N.show('inform', 'Alias kind')
check(calls[#calls].args[1].type == 'info', "'inform' -> info")
N.show('banana', 'Unknown kind')
check(calls[#calls].args[1].type == 'info', 'unknown kind -> info')
N.show('WARN', 'Upper alias')
check(calls[#calls].args[1].type == 'warning', "'WARN' -> warning")

N.show('info', '  Line one\r\nline\ttwo \0 ')
check(calls[#calls].args[1].description == 'Line one\nlinetwo', 'control characters stripped: ' .. dump(calls[#calls].args[1].description))

local long = string.rep('é', 320)
N.show('info', long)
local desc = calls[#calls].args[1].description
check(utf8.len(desc) == 300 and desc:sub(-3) == '…', 'message clipped to 300 code points with an ellipsis')
N.show('info', 'Long title', string.rep('T', 80))
check(utf8.len(calls[#calls].args[1].title) == 60, 'title clipped to 60')

N.show('info', 'Sticky', nil, 0)
check(calls[#calls].args[1].duration == 5000, 'duration 0 -> config duration')
N.show('info', 'Huge', nil, 999999)
check(calls[#calls].args[1].duration == 30000, 'duration capped at 30 s')
N.show('info', 'Tiny', nil, 10)
check(calls[#calls].args[1].duration == 1000, 'duration at least 1 s')
check(math.type(calls[#calls].args[1].duration) == 'integer', 'duration is an integer')

local before = #calls
N.show('success', 'Same twice')
N.show('success', 'Same twice')
check(#calls == before + 1, 'identical notification within 1.5 s is shown once')
now = now + 2000
N.show('success', 'Same twice')
check(#calls == before + 2, 'identical notification after 1.5 s is shown again')

N = setup('ox_lib', { notify = { title = '', position = 'middle', duration = 'x' } })
N.show('info', 'No title')
local a = calls[#calls].args[1]
check(a.title == nil and a.position == nil and a.duration == 5000, "title '' omitted, invalid position/duration ignored " .. dump(a))

---------------------------------------------------------------------------------------
-- client/nui.lua: NUI.notify, nz:client:notify, 'notify' NUI callback
---------------------------------------------------------------------------------------

setup('ox_lib')
NZ.NUI = {}
loadFile('client/nui.lua')

NZ.NUI.notify('success', 'Shape one', 'Title one')
check(calls[#calls].args[1].title == 'Title one' and calls[#calls].args[1].type == 'success', 'NUI.notify(type, message, title)')
NZ.NUI.notify({ type = 'warning', message = 'Shape two', duration = 9000 })
check(calls[#calls].args[1].type == 'warning' and calls[#calls].args[1].duration == 9000, 'NUI.notify(table)')

handlers['nz:client:notify']({ type = 'error', message = 'From server' })
check(calls[#calls].args[1].description == 'From server', 'event with a table')
handlers['nz:client:notify']('info', 'Event shape two', 'T')
check(calls[#calls].args[1].description == 'Event shape two' and calls[#calls].args[1].title == 'T', 'event (type, message, title)')
handlers['nz:client:notify']('Lone string')
check(calls[#calls].args[1].description == 'Lone string', 'event with a lone string')
local n0 = #calls
handlers['nz:client:notify'](nil)
handlers['nz:client:notify'](42)
check(#calls == n0, 'event ignores junk')

local cb = nuiCallbacks.notify
check(type(cb) == 'function', "'notify' NUI callback registered")
local function callNotify(payload)
  local response
  cb(payload, function(r) response = r end)
  return response
end

now = now + 10000
local r = callNotify({ type = 'success', message = 'From the interface', title = 'Saved' })
check(r and r.ok == true and calls[#calls].args[1].description == 'From the interface', "valid 'notify' payload shown")
for i, bad in ipairs({
  { type = 'banana', message = 'x' },
  { type = 'info' },
  { type = 'info', message = '' },
  { type = 'info', message = '   ' },
  { type = 'info', message = 42 },
  { type = 'info', message = string.rep('a', 301) },
  { type = 'info', message = 'ok', title = string.rep('t', 61) },
  { type = 'info', message = 'ok', title = {} },
}) do
  r = callNotify(bad)
  check(r and r.ok == false and type(r.error) == 'string', "'notify' rejects bad payload #" .. i)
end
r = callNotify({ type = 'info', message = string.rep('é', 300), title = string.rep('ü', 60) })
check(r and r.ok == true, "'notify' counts characters, not bytes")

now = now + 10000
local accepted = 0
for i = 1, 12 do
  r = callNotify({ type = 'info', message = 'Burst ' .. i })
  if r and r.ok then accepted = accepted + 1 end
end
check(accepted == 8, "'notify' rate limit: 8 per 3 s (accepted " .. accepted .. ')')
now = now + 3500
r = callNotify({ type = 'info', message = 'After the window' })
check(r and r.ok == true, "'notify' accepts again after the window")

---------------------------------------------------------------------------------------

io.stdout:write(('notify: %d checks, %d failed\n'):format(checks, #failures))
for _, f in ipairs(failures) do io.stdout:write('  FAIL ' .. f .. '\n') end
if #errors > 0 then
  for _, e in ipairs(errors) do io.stdout:write('  lib.print.error ' .. e .. '\n') end
end
if #failures > 0 or #errors > 0 then os.exit(1) end
io.stdout:write('notify OK\n')
