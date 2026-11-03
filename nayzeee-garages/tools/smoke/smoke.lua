--[[
  Headless smoke test for nayzeee-garages (no FiveM needed).

  Loads every script of one side in fxmanifest order inside a stubbed FiveM + ox_lib +
  oxmysql + framework environment, runs the thread scheduler (boot), then invokes every
  registered server callback / NUI callback / net event with a few payload shapes and
  reports Lua runtime errors (including ones swallowed by NZ.Utils.safe -> lib.print.error).

  Usage (from the resource root):
    lua5.4 tools/smoke/smoke.lua server qb|qbx|esx
    lua5.4 tools/smoke/smoke.lua client qb|qbx|esx
]]

local side = arg[1] or 'server'
local framework = arg[2] or 'qb'
local dk = require('dkjson')

local errors = {}
local function report(kind, msg)
  errors[#errors + 1] = ('[%s] %s'):format(kind, tostring(msg))
end

---------------------------------------------------------------------------------------
-- Universal stub: indexable, callable, returns itself/nil safely.
---------------------------------------------------------------------------------------
local Stub
Stub = setmetatable({}, {
  __index = function() return Stub end,
  __call = function() return nil end,
})

local function vecmeta(n)
  return {
    __add = function(a, b) local r = {} for _, k in ipairs({ 'x', 'y', 'z', 'w' }) do if a[k] then r[k] = a[k] + (b[k] or 0) end end return setmetatable(r, getmetatable(a)) end,
    __sub = function(a, b) local r = {} for _, k in ipairs({ 'x', 'y', 'z', 'w' }) do if a[k] then r[k] = a[k] - (b[k] or 0) end end return setmetatable(r, getmetatable(a)) end,
    __mul = function(a, b) local r = {} if type(a) == 'number' then a, b = b, a end for _, k in ipairs({ 'x', 'y', 'z', 'w' }) do if a[k] then r[k] = a[k] * b end end return setmetatable(r, getmetatable(a)) end,
    __len = function(a) return math.sqrt((a.x or 0) ^ 2 + (a.y or 0) ^ 2 + (a.z or 0) ^ 2) end,
    __index = function(t, k) if k == 'xyz' then return vector3(t.x, t.y, t.z) end if k == 'xy' then return { x = t.x, y = t.y } end end,
    n = n,
  }
end
local v3m, v4m = vecmeta(3), vecmeta(4)
function vector3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, v3m) end
function vector4(x, y, z, w) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 }, v4m) end
function vector2(x, y) return { x = x or 0.0, y = y or 0.0 } end
vec3, vec4, vec2, vec = vector3, vector4, vector2, vector3

json = { encode = function(v) return dk.encode(v) end, decode = function(s) if type(s) ~= 'string' then return nil end return (dk.decode(s)) end }

function joaat(s)
  local h = 0
  s = tostring(s):lower()
  for i = 1, #s do
    h = (h + s:byte(i)) & 0xffffffff
    h = (h + (h << 10)) & 0xffffffff
    h = h ~ (h >> 6)
  end
  h = (h + (h << 3)) & 0xffffffff
  h = h ~ (h >> 11)
  h = (h + (h << 15)) & 0xffffffff
  if h > 0x7fffffff then h = h - 0x100000000 end
  return h
end
GetHashKey = joaat

---------------------------------------------------------------------------------------
-- Scheduler, events, commands, NUI
---------------------------------------------------------------------------------------
local threads = {}
local now = 0
function CreateThread(fn)
  threads[#threads + 1] = { co = coroutine.create(fn), wake = now }
end
Citizen = { CreateThread = CreateThread, Wait = function(ms) coroutine.yield(ms or 0) end, Await = function(p) return p and p.value end, SetTimeout = function(ms, fn) CreateThread(function() Wait(ms) fn() end) end }
function Wait(ms)
  if not coroutine.isyieldable() then return end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function ClearTimeout() end
promise = { new = function() local p = {} function p:resolve(v) self.value = v end function p:reject(e) self.err = e end return p end }

local function runThreads(maxTicks)
  for _ = 1, maxTicks do
    local alive = 0
    for i = #threads, 1, -1 do
      local t = threads[i]
      if coroutine.status(t.co) == 'dead' then
        table.remove(threads, i)
      elseif t.wake <= now then
        local ok, res = coroutine.resume(t.co)
        if not ok then
          report('thread', debug.traceback(t.co, res))
          table.remove(threads, i)
        else
          t.wake = now + (tonumber(res) or 0)
          alive = alive + 1
        end
      else
        alive = alive + 1
      end
    end
    now = now + 100
    if alive == 0 then break end
  end
end

local handlers = {}
local netEvents = {}
local fired = { client = {}, server = {} }
function RegisterNetEvent(name, fn) netEvents[name] = true if fn then AddEventHandler(name, fn) end end
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) return { name = name } end
function RemoveEventHandler() end
local function callHandlers(name, ...)
  for _, fn in ipairs(handlers[name] or {}) do
    local args = table.pack(...)
    CreateThread(function()
      local ok, err = xpcall(fn, debug.traceback, table.unpack(args, 1, args.n))
      if not ok then report('event ' .. name, err) end
    end)
  end
end
function TriggerEvent(name, ...) callHandlers(name, ...) end
function TriggerClientEvent(name, target, ...) fired.client[#fired.client + 1] = name end
function TriggerLatentClientEvent(name, target, bps, ...) fired.client[#fired.client + 1] = name end
function TriggerServerEvent(name, ...) fired.server[#fired.server + 1] = name end
local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end
local nuiCallbacks = {}
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
function SendNUIMessage() end
function SetNuiFocus() end
function SetNuiFocusKeepInput() end

---------------------------------------------------------------------------------------
-- Natives & runtime objects
---------------------------------------------------------------------------------------
local frameworkResource = ({ qb = 'qb-core', qbx = 'qbx_core', esx = 'es_extended' })[framework]
function GetResourceState(name)
  if name == frameworkResource or name == 'ox_lib' or name == 'oxmysql' or (framework == 'qbx' and name == 'qb-core') then return 'started' end
  return 'missing'
end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return side == 'server' end
function GetResourceMetadata() return '1.0.0' end
function GetGameTimer() return now end
function GetPlayers() return side == 'server' and { '1' } or {} end
function GetPlayerPed() return 101 end
function PlayerPedId() return 101 end
function PlayerId() return 0 end
function GetPlayerServerId() return 1 end
function GetEntityCoords() return vector3(0.0, 0.0, 0.0) end
function GetEntityHeading() return 0.0 end
function GetPlayerName() return 'Tester' end
function GetPlayerIdentifierByType(_, t) return t .. ':abc' end
function GetPlayerIdentifiers() return { 'license:abc' } end
function GetAllVehicles() return {} end
function GetConvar(_, d) return d end
function GetConvarInt(_, d) return d end
function IsPlayerAceAllowed() return true end
function LoadResourceFile() return nil end
function SaveResourceFile() return true end
function PerformHttpRequest(_, cb) if cb then cb(204, '', {}) end end
function GetInvokingResource() return nil end
function NetworkGetEntityFromNetworkId() return 0 end
function NetworkGetNetworkIdFromEntity() return 0 end
function DoesEntityExist() return false end
function GetVehicleNumberPlateText() return 'ABC123  ' end
function GetEntityModel() return joaat('sultan') end
function GetNumResources() return 0 end
function AddStateBagChangeHandler() return 1 end
function GetVehicleClassFromName() return 0 end
function GetDisplayNameFromVehicleModel() return 'SULTAN' end
function GetMakeNameFromVehicleModel() return 'KARIN' end
function GetLabelText(s) return s end
function IsControlJustReleased() return false end
function IsControlPressed() return false end
function GetVehiclePedIsIn() return 0 end
function IsPedInAnyVehicle() return false end
function GetGameplayCamCoord() return vector3(0, 0, 0) end
function GetGameplayCamRot() return vector3(0, 0, 0) end
function GetGameplayCamFov() return 50.0 end
function GetModelDimensions() return vector3(-1, -2, -0.5), vector3(1, 2, 1) end
function GetInteriorAtCoords() return 0 end
function GetInteriorFromEntity() return 0 end

local function statebag()
  return setmetatable({ set = function(self, k, v) rawset(self, k, v) end }, {})
end
GlobalState = statebag()
LocalPlayer = { state = statebag() }
function Player() return { state = statebag() } end
function Entity() return { state = statebag() } end

setmetatable(_ENV, {
  __index = function(_, k)
    if type(k) == 'string' and k:match('^[A-Z]') then
      return function() return nil end
    end
    return nil
  end,
})

---------------------------------------------------------------------------------------
-- Fake framework
---------------------------------------------------------------------------------------
local fakeJob = { name = 'police', label = 'Police', grade = { level = 2, name = 'Sergeant' }, onduty = true, isboss = false, type = 'leo' }
local fakeGang = { name = 'ballas', label = 'Ballas', grade = { level = 1, name = 'Member' }, isboss = false }
local function qbPlayer()
  local pd = { source = 1, citizenid = 'CID001', license = 'license:abc', charinfo = { firstname = 'John', lastname = 'Doe' }, job = fakeJob, gang = fakeGang, money = { cash = 5000, bank = 100000 } }
  return {
    PlayerData = pd,
    Functions = {
      GetMoney = function(acc) return pd.money[acc] or 0 end,
      RemoveMoney = function(acc, amt) pd.money[acc] = (pd.money[acc] or 0) - amt return true end,
      AddMoney = function(acc, amt) pd.money[acc] = (pd.money[acc] or 0) + amt return true end,
      SetMetaData = function() end,
    },
  }
end
local qbShared = {
  Jobs = { police = { label = 'Police', grades = { ['0'] = { name = 'Recruit' }, ['1'] = { name = 'Officer' }, ['2'] = { name = 'Sergeant', isboss = true } } } },
  Gangs = { ballas = { label = 'Ballas', grades = { ['0'] = { name = 'Recruit' }, ['1'] = { name = 'Member' } } } },
  Vehicles = {},
}
local QBCore = {
  Functions = {
    GetPlayer = function() return qbPlayer() end,
    GetPlayerByCitizenId = function() return qbPlayer() end,
    GetQBPlayers = function() return { [1] = qbPlayer() } end,
    GetPlayers = function() return { 1 } end,
    HasPermission = function() return true end,
    GetPlayerData = function() return qbPlayer().PlayerData end,
    Notify = function() end,
    CreateCallback = function() end,
    TriggerCallback = function() end,
  },
  Shared = qbShared,
}
local esxPlayer = {
  source = 1, identifier = 'char1:abc', job = { name = 'police', label = 'Police', grade = 2, grade_label = 'Sergeant', grade_name = 'boss' },
  getName = function() return 'John Doe' end,
  getGroup = function() return 'admin' end,
  getMoney = function() return 5000 end,
  getAccount = function() return { money = 100000 } end,
  removeMoney = function() end, addMoney = function() end,
  removeAccountMoney = function() end, addAccountMoney = function() end,
  showNotification = function() end,
  getJob = function(self) return self.job end,
}
local ESX = {
  GetPlayerFromId = function() return esxPlayer end,
  GetPlayerFromIdentifier = function() return esxPlayer end,
  GetExtendedPlayers = function() return { esxPlayer } end,
  GetJobs = function() return { police = { name = 'police', label = 'Police', grades = { ['0'] = { grade = 0, label = 'Recruit', name = 'recruit' } } } } end,
  GetPlayerData = function() return { identifier = 'char1:abc', job = esxPlayer.job } end,
  IsPlayerLoaded = function() return true end,
}
local qbxExports = {
  GetPlayer = function() return qbPlayer() end,
  GetPlayerByCitizenId = function() return qbPlayer() end,
  GetQBPlayers = function() return { [1] = qbPlayer() } end,
  GetJobs = function() return qbShared.Jobs end,
  GetGangs = function() return qbShared.Gangs end,
  GetPlayerData = function() return qbPlayer().PlayerData end,
  AddMoney = function() return true end, RemoveMoney = function() return true end, GetMoney = function() return 100000 end,
  HasPrimaryGroup = function() return true end, HasGroup = function() return true end,
  Notify = function() end,
}

local exportTables = {
  ['qb-core'] = { GetCoreObject = function() return QBCore end },
  ['es_extended'] = { getSharedObject = function() return ESX end },
  ['qbx_core'] = qbxExports,
}
exports = setmetatable({}, {
  __index = function(_, res)
    local t = exportTables[res]
    if t then
      return setmetatable({}, { __index = function(_, fn) local f = t[fn] if not f then return function() return nil end end return function(_, ...) return f(...) end end })
    end
    return setmetatable({}, { __index = function() return function() return nil end end })
  end,
  __call = function() end,
})

---------------------------------------------------------------------------------------
-- ox_lib & oxmysql
---------------------------------------------------------------------------------------
local callbacks = {}
local function printer(level) return function(...) local parts = {} for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end local s = table.concat(parts, ' ') if level == 'error' then report('lib.print.error', s) end end end
lib = setmetatable({
  print = { info = printer('info'), warn = printer('warn'), error = printer('error'), debug = printer('debug'), verbose = printer('verbose') },
  callback = setmetatable({
    register = function(name, fn) callbacks[name] = fn end,
    await = function(name, _, ...) local fn = callbacks[name] if fn then return fn(1, ...) end return { ok = false, error = 'stub' } end,
  }, { __call = function(_, name, _, cb, ...) local fn = callbacks[name] if fn and cb then cb(fn(1, ...)) end end }),
  points = { new = function(o) return setmetatable({ remove = function() end, currentDistance = 99 }, { __index = o }) end, getAllPoints = function() return {} end, getNearbyPoints = function() return {} end, getClosestPoint = function() return nil end },
  addKeybind = function(o) return setmetatable({ disable = function() end, isControlPressed = function() return false end, getCurrentKey = function() return 'E' end }, { __index = o }) end,
  addCommand = function() end,
  requestModel = function(m) return type(m) == 'number' and m or joaat(m) end,
  requestAnimDict = function(d) return d end,
  getVehicleProperties = function() return { plate = 'ABC123', model = joaat('sultan') } end,
  setVehicleProperties = function() return true end,
  getClosestVehicle = function() return nil end,
  getClosestPlayer = function() return nil end,
  getNearbyPlayers = function() return {} end,
  getNearbyVehicles = function() return {} end,
  alertDialog = function() return 'confirm' end,
  inputDialog = function() return nil end,
  notify = function() end,
  waitFor = function(fn) return fn() end,
  showTextUI = function() end, hideTextUI = function() end,
  raycast = { cam = function() return false end },
  locale = function() end,
  versionCheck = function() end,
  cache = {},
  onCache = function() end,
  array = Stub,
  timer = function() return { forceEnd = function() end } end,
  table = { deepclone = function(t) return t end, contains = function() return false end, matches = function() return false end, merge = function(a) return a end },
  math = { round = function(n) return math.floor(n + 0.5) end },
  string = { random = function() return 'ABC12345' end },
  zones = { sphere = function(o) return setmetatable({ remove = function() end }, { __index = o }) end, box = function(o) return setmetatable({ remove = function() end }, { __index = o }) end, poly = function(o) return setmetatable({ remove = function() end }, { __index = o }) end },
  grid = Stub,
  getFilesInDirectory = function() return {} end,
}, { __index = function() return Stub end })
cache = { ped = 101, playerId = 0, serverId = 1, coords = vector3(0, 0, 0), vehicle = false, seat = false, resource = 'nayzeee-garages' }
function locale(s) return s end

local function mysqlStub(default)
  return setmetatable({ await = function() return default end }, { __call = function(_, _, _, cb) if type(cb) == 'function' then cb(default) end return default end })
end
MySQL = {
  query = mysqlStub({}), single = mysqlStub(nil), scalar = mysqlStub(0), insert = mysqlStub(1),
  update = mysqlStub(0), prepare = mysqlStub(nil), transaction = mysqlStub(true), rawExecute = mysqlStub({}),
  ready = function(cb) cb() end, Sync = Stub, Async = Stub,
}

---------------------------------------------------------------------------------------
-- Load files in manifest order
---------------------------------------------------------------------------------------
local function readFile(p) local f = io.open(p, 'r') if not f then return nil end local s = f:read('a') f:close() return s end
local manifest = readFile('fxmanifest.lua')
local function block(name)
  local body = manifest:match(name .. '%s*(%b{})')
  local out = {}
  if body then for f in body:gmatch("'([^']+)'") do if not f:find('^@') then out[#out + 1] = f end end end
  return out
end
local list = {}
for _, f in ipairs(block('shared_scripts')) do list[#list + 1] = f end
for _, f in ipairs(block(side == 'server' and 'server_scripts' or 'client_scripts')) do list[#list + 1] = f end

local function expand(pattern)
  if not pattern:find('%*') then return { pattern } end
  local dir = pattern:match('^(.*)/')
  local out = {}
  local p = io.popen('ls ' .. dir .. ' 2>/dev/null')
  for name in p:lines() do if name:match('%.lua$') then out[#out + 1] = dir .. '/' .. name end end
  p:close()
  return out
end

for _, pat in ipairs(list) do
  for _, file in ipairs(expand(pat)) do
    local src = readFile(file)
    if not src then
      report('load', 'missing ' .. file)
    else
      local chunk, err = load(src, '@' .. file, 't', _ENV)
      if not chunk then
        report('syntax', err)
      else
        local ok, e = xpcall(chunk, debug.traceback)
        if not ok then report('load ' .. file, e) end
      end
    end
  end
end

runThreads(400)

---------------------------------------------------------------------------------------
-- Exercise
---------------------------------------------------------------------------------------
local payloads = {
  {},
  { plate = 'ABC123', locationId = 1, id = 1, index = 1, page = 1, value = true, name = 'Test', serverId = 1, identifier = 'CID001', query = 'jo', role = 'member', mode = 'owner', full = false, enabled = true, groupId = 1, offerId = 1, accept = true, inviteId = 1, netId = 1, spawnIndex = 1, entityType = 'automobile', price = 100, type = 'garage', target = 'L1', kind = 'spawn', vehicleType = 'car', points = {}, coords = { x = 0, y = 0, z = 0 }, data = {}, settings = {}, location = { kind = 'garage', name = 'Smoke', vehicleType = 'car' }, interior = { name = 'Smoke' }, patch = {}, source = 'json', json = '[]' },
  { plate = 12, locationId = 'x', page = -5, value = 'nope', name = {}, serverId = 'abc' },
}

if side == 'server' then
  TriggerEvent('nz:server:playerLoaded', 1)
  runThreads(100)
  local names = {}
  for name in pairs(callbacks) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    for i, p in ipairs(payloads) do
      CreateThread(function()
        local ok, res = xpcall(callbacks[name], debug.traceback, 1, p)
        if not ok then
          report('callback ' .. name .. ' payload#' .. i, res)
        elseif type(res) ~= 'table' or type(res.ok) ~= 'boolean' then
          report('shape ' .. name .. ' payload#' .. i, 'returned ' .. tostring(res) .. ' (expected { ok = boolean })')
        end
      end)
      runThreads(60)
    end
  end
  for name, fn in pairs(commands) do
    CreateThread(function() local ok, e = xpcall(fn, debug.traceback, 1, {}, '') if not ok then report('command ' .. name, e) end end)
  end
  callHandlers('playerDropped', 'quit')
  runThreads(100)
  print(('server: %d callbacks, %d commands registered'):format(#names, (function() local n = 0 for _ in pairs(commands) do n = n + 1 end return n end)()))
else
  TriggerEvent('nz:client:playerLoaded')
  runThreads(100)
  local names = {}
  for name in pairs(nuiCallbacks) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    for i, p in ipairs(payloads) do
      CreateThread(function()
        local ok, e = xpcall(nuiCallbacks[name], debug.traceback, p, function(resp)
          if type(resp) ~= 'table' or type(resp.ok) ~= 'boolean' then
            report('nui shape ' .. name .. ' payload#' .. i, 'responded ' .. tostring(resp))
          end
        end)
        if not ok then report('nui ' .. name .. ' payload#' .. i, e) end
      end)
      runThreads(60)
    end
  end
  for _, ev in ipairs({ 'nz:client:locations', 'nz:client:settings', 'nz:client:groups', 'nz:client:notify', 'nz:client:interior:sync', 'nz:client:interior:kicked', 'nz:client:openAdmin', 'nz:client:impoundForm', 'nz:client:sellOffer' }) do
    callHandlers(ev, {})
  end
  runThreads(100)
  print(('client: %d NUI callbacks registered'):format(#names))
end

if #errors > 0 then
  local seen, unique = {}, {}
  for _, e in ipairs(errors) do
    local key = e:sub(1, 300)
    if not seen[key] then seen[key] = true unique[#unique + 1] = e end
  end
  for _, e in ipairs(unique) do print(e) print('---') end
  print(('%d error(s) on %s/%s'):format(#unique, side, framework))
  os.exit(1)
end
print(('smoke OK (%s/%s)'):format(side, framework))
