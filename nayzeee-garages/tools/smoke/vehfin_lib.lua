--[[
  Shared harness for tools/smoke/trailer.lua and tools/smoke/finance.lua (no FiveM needed).

  Installs a stubbed FiveM server runtime in the global environment: a fake clock and
  scheduler (CreateThread / Wait / SetTimeout), local events, ox_lib callbacks, exports, a small
  OneSync world (vehicles with net ids, seats, models, coords, state bags, attachments,
  routing buckets, CreateVehicleServerSetter) and a fake oxmysql (`MySQL`) that runs the SQL
  server/db.lua builds against in-memory framework tables: QBCore `player_vehicles` (finance
  columns), Qbox `player_vehicles` + `vehicle_financing`, ESX `owned_vehicles`.

  Usage:  local H = dofile('tools/smoke/vehfin_lib.lua'); H.setup('qb')
]]

local H = {}
local failures, checks = {}, 0
H.failures = failures

function H.check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = (H.scenario and ('[' .. H.scenario .. '] ') or '') .. label end
  return cond
end
function H.count() return checks end

---------------------------------------------------------------------------------------
-- Clock, scheduler, events
---------------------------------------------------------------------------------------

local clock = 0
H.BASE_TIME = 1700000000
local realTime = os.time
os.time = function(t) -- luacheck: ignore 122
  if t then return realTime(t) end
  return H.BASE_TIME + clock // 1000
end
function H.now() return os.time() end

local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
Citizen = { CreateThread = CreateThread, Wait = Wait, SetTimeout = SetTimeout }
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

function H.advance(ms)
  local target = clock + ms
  runDue()
  while clock < target do
    clock = math.min(target, clock + 100)
    runDue()
  end
end

--- Jump the clock forward without running threads (days pass between finance checks).
function H.skip(ms) clock = clock + ms end

--- Run fn(...) inside a thread until it returns (yields are driven by the fake clock).
function H.run(fn, ...)
  local args = table.pack(...)
  local results
  CreateThread(function() results = table.pack(fn(table.unpack(args, 1, args.n))) end)
  runDue()
  local guard = 0
  while not results do
    clock = clock + 50
    runDue()
    guard = guard + 1
    if guard > 20000 then error('run(): the call never returned') end
  end
  return table.unpack(results, 1, results.n)
end

local handlers = {}
H.clientEvents = {}
H.serverEvents = {}
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  table.insert(handlers[name], fn)
  return name
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
  H.serverEvents[#H.serverEvents + 1] = { name = name, args = table.pack(...) }
  for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
function TriggerClientEvent(name, target, ...)
  H.clientEvents[#H.clientEvents + 1] = { name = name, target = target, args = table.pack(...) }
end
function H.events(name)
  local out = {}
  for _, e in ipairs(H.serverEvents) do if e.name == name then out[#out + 1] = e end end
  return out
end
function H.notified(target, pattern)
  for i = #H.clientEvents, 1, -1 do
    local e = H.clientEvents[i]
    local payload = e.args[1]
    if e.name == 'nz:client:notify' and e.target == target and type(payload) == 'table'
      and tostring(payload.message):find(pattern, 1, true) then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------------------
-- Natives: players, world, state bags, KVP
---------------------------------------------------------------------------------------

local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vmeta) end
H.vec3 = vec3
vector3 = vec3
function vector4(x, y, z, w) return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 } end
vec4 = vector4

local function joaat_(s)
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
joaat = joaat_
GetHashKey = joaat_
H.joaat = joaat_

H.online = { [1] = 'CID001', [2] = 'CID002' }
H.playerPos = { [1] = vec3(10, 0, 0), [2] = vec3(400, 400, 0) }
function GetPlayerName(src) return H.online[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetPlayerPed(src) return H.online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetPlayerRoutingBucket() return 0 end
function GetPlayers() local out = {} for src in pairs(H.online) do out[#out + 1] = tostring(src) end table.sort(out) return out end
function IsPlayerAceAllowed() return false end
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
H.invoker = nil
function GetInvokingResource() return H.invoker end
function GetConvar(_, default) return default end
function GetResourceState() return 'missing' end
function LoadResourceFile() return nil end
function GetEntityHealth() return 1000 end
GlobalState = {}
function Player() return { state = {} } end

local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function DeleteResourceKvp(k) kvp[k] = nil end

-- [handle] = { plate, model, netId, seats, coords, heading, vtype, attachedTo, bucket, engine, body }
H.entities = {}
local nextHandle, nextNet = 5000, 100
local states = {}
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = bagHandlers[key] or {} table.insert(bagHandlers[key], fn) end
function GetEntityFromStateBagName(name) return tonumber(tostring(name):match('^entity:(%d+)$')) or 0 end
local function stateOf(handle)
  local s = states[handle]
  if not s then
    s = setmetatable({}, { __index = { set = function(self, k, v)
      rawset(self, k, v)
      for _, fn in ipairs(bagHandlers[k] or {}) do fn('entity:' .. tostring(handle), k, v) end
    end } })
    states[handle] = s
  end
  return s
end
function Entity(handle) return { state = stateOf(handle) } end
H.stateOf = stateOf

--- Create a world vehicle. model = spawn name; opts = { vtype, coords, heading, owner }.
function H.spawn(plate, model, opts)
  opts = opts or {}
  nextHandle, nextNet = nextHandle + 1, nextNet + 1
  H.entities[nextHandle] = {
    plate = plate, model = type(model) == 'number' and model or joaat_(model), netId = nextNet, seats = {},
    coords = opts.coords or vec3(12, 0, 0), heading = opts.heading or 0.0, vtype = opts.vtype or 'automobile',
    attachedTo = 0, bucket = 0, engine = 900.0, body = 950.0, owner = opts.owner,
  }
  return nextHandle, nextNet
end

function H.seat(src, handle)
  for _, e in pairs(H.entities) do
    for s, ped in pairs(e.seats) do if ped == 1000 + src then e.seats[s] = nil end end
  end
  if handle then H.entities[handle].seats[-1] = 1000 + src end
end

function H.find(pred)
  local out = {}
  for h, e in pairs(H.entities) do if pred(e, h) then out[#out + 1] = h end end
  table.sort(out)
  return out
end

function DoesEntityExist(h) return H.entities[h] ~= nil or (type(h) == 'number' and h > 1000 and h < 2000 and H.online[h - 1000] ~= nil) end
function GetEntityType(h) return H.entities[h] and 2 or ((type(h) == 'number' and h > 1000 and h < 2000) and 1 or 0) end
function GetAllVehicles() local out = {} for h in pairs(H.entities) do out[#out + 1] = h end table.sort(out) return out end
function GetVehicleNumberPlateText(h) local e = H.entities[h] return e and (e.plate .. '        '):sub(1, 8) or '' end
function SetVehicleNumberPlateText(h, text) if H.entities[h] then H.entities[h].plate = tostring(text) end end
function NetworkGetEntityFromNetworkId(netId)
  for h, e in pairs(H.entities) do if e.netId == netId then return h end end
  return 0
end
function NetworkGetNetworkIdFromEntity(h) return H.entities[h] and H.entities[h].netId or 0 end
function GetPedInVehicleSeat(h, s) local e = H.entities[h] return e and e.seats[s] or 0 end
function GetEntityModel(h) return H.entities[h] and H.entities[h].model or 0 end
function GetVehicleType(h) return H.entities[h] and H.entities[h].vtype or nil end
function GetEntityHeading(h) return H.entities[h] and H.entities[h].heading or 0.0 end
function GetEntityCoords(h)
  if H.entities[h] then return H.entities[h].coords end
  return H.playerPos[h - 1000] or vec3(0, 0, 0)
end
-- network owner: opts.owner of H.spawn / entity.owner (default player 1, the test driver)
function NetworkGetEntityOwner(h) local e = H.entities[h] if not e then return -1 end return e.owner or 1 end
H.frozen = {}
function FreezeEntityPosition(h, state) H.frozen[h] = state == true end
function GetEntityAttachedTo(h) return H.entities[h] and H.entities[h].attachedTo or 0 end
function GetVehicleEngineHealth(h) return H.entities[h] and H.entities[h].engine or 1000.0 end
function GetVehicleBodyHealth(h) return H.entities[h] and H.entities[h].body or 1000.0 end
function GetVehiclePetrolTankHealth() return 1000.0 end
function SetEntityRoutingBucket(h, b) if H.entities[h] then H.entities[h].bucket = b end end
function SetEntityOrphanMode() end
function DeleteEntity(h)
  if not H.entities[h] then return end
  H.entities[h], states[h] = nil, nil
  TriggerEvent('entityRemoved', h)
end

-- entity types the server knows how to create
H.serverSpawns = {}
function CreateVehicleServerSetter(hash, vtype, x, y, z, w)
  local h = H.spawn('', hash, { vtype = vtype, coords = vec3(x, y, z), heading = w })
  H.entities[h].plate = 'SRV' .. tostring(h)
  H.serverSpawns[#H.serverSpawns + 1] = { handle = h, vtype = vtype, x = x, y = y, z = z, w = w }
  return h
end

setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

---------------------------------------------------------------------------------------
-- ox_lib, exports, json
---------------------------------------------------------------------------------------

H.printed = { info = {}, warn = {}, error = {} }
H.callbacks = {}
lib = {
  print = {
    info = function(...) H.printed.info[#H.printed.info + 1] = table.concat({ ... }, ' ') end,
    warn = function(...) H.printed.warn[#H.printed.warn + 1] = table.concat({ ... }, ' ') end,
    error = function(...) H.printed.error[#H.printed.error + 1] = table.concat({ ... }, ' ') end,
    debug = function() end,
  },
  callback = { register = function(name, fn) H.callbacks[name] = fn end },
}
H.exports = {}
exports = setmetatable({}, {
  __call = function(_, name, fn) H.exports[name] = fn end,
  __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
})
function RegisterCommand() end

local dk = require('dkjson')
json = { encode = function(v) return dk.encode(v) end, decode = function(s) if type(s) ~= 'string' then return nil end return (dk.decode(s)) end }

--- Call an export as another resource.
function H.export(name, ...)
  local fn = H.exports[name]
  if not fn then failures[#failures + 1] = 'export missing: ' .. name return nil end
  H.invoker = 'nz_dealership'
  local args = table.pack(...)
  local res = table.pack(H.run(function() return fn(table.unpack(args, 1, args.n)) end))
  H.invoker = nil
  return table.unpack(res, 1, res.n)
end

function H.cb(name, src, payload)
  local fn = H.callbacks[name]
  if not fn then failures[#failures + 1] = 'callback missing: ' .. name return { ok = false } end
  return H.run(fn, src, payload)
end

function H.load(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local chunk = assert(load(src, '@' .. file, 't', _ENV))
  local okLoad, err = xpcall(chunk, debug.traceback)
  if not okLoad then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end

---------------------------------------------------------------------------------------
-- Fake oxmysql over in-memory framework tables
---------------------------------------------------------------------------------------

local db = { rows = {}, financing = {}, nextId = 1, columns = {}, statements = {} }
H.db = db

local function trim(s) return (tostring(s):gsub('^%s+', ''):gsub('%s+$', '')) end
local function upperTrim(s) return trim(s):upper() end

local function rowsOf()
  local out = {}
  for _, r in ipairs(db.rows) do out[#out + 1] = r end
  return out
end

local function financeOfRow(r)
  if db.framework == 'qbx' then return db.financing[r.id] end
  return nil
end

--- Project a raw row through "v.`col` AS `col`" / "f.`col` AS `nzf_col`" select items.
local function project(selectList, r)
  local out = {}
  local fin = financeOfRow(r)
  for alias, col, as in selectList:gmatch('(%a)%.`([%w_]+)` AS `([%w_]+)`') do
    if alias == 'v' then
      out[as] = r[col]
    elseif alias == 'f' and fin then
      out[as] = fin[col]
    end
  end
  return out
end

local function matchWhere(where, params, r)
  if where:find('`plate` = ? OR', 1, true) then
    return r.plate == params[1] or r.plate == params[2], 2
  end
  if where:find('UPPER(TRIM(', 1, true) or where:find('nz_plate_norm', 1, true) then
    return upperTrim(r.plate) == params[1], 1
  end
  if where:find('IS NOT NULL OR', 1, true) or where:find('balance` > 0', 1, true) or where:find('`nz_finance` IS NOT NULL', 1, true) then
    local fin = financeOfRow(r)
    local ok = (r.nz_finance ~= nil and db.columns.nz_finance)
      or (db.framework == 'qb' and (tonumber(r.balance) or 0) > 0)
      or (fin ~= nil and (tonumber(fin.balance) or 0) > 0)
    return ok, 0
  end
  error('fake MySQL: unsupported WHERE: ' .. where)
end

local function selectRows(sql, params)
  local selectList, where = sql:match('^SELECT (.-) FROM `[%w_]+` v.- WHERE (.*)$')
  if not selectList then error('fake MySQL: unsupported SELECT: ' .. sql) end
  where = where:gsub(' LIMIT 1$', '')
  local out = {}
  for _, r in ipairs(rowsOf()) do
    if matchWhere(where, params, r) then out[#out + 1] = project(selectList, r) end
  end
  return out
end

local function applyAssignments(target, assignments, params)
  local i = 1
  for part in (assignments .. ', '):gmatch('(.-), ') do
    local col, value = part:match('^`([%w_]+)` = (.*)$')
    if col then
      if value == '?' then
        target[col] = params[i]
        i = i + 1
      elseif value == 'NULL' then
        target[col] = nil
      else
        local _, n = value:gsub('%?', '')
        target[col] = params[i]
        i = i + n
      end
    end
  end
  return i
end

local function query(sql, params)
  sql = trim(sql:gsub('%s+', ' '))
  params = params or {}
  db.statements[#db.statements + 1] = sql
  if sql:match('^ALTER TABLE') then
    local col = sql:match('ADD COLUMN `([%w_]+)`')
    if db.failAlter then error('ALTER refused') end
    db.columns[col] = true
    return {}
  end
  if sql:match('^SELECT `plate`, `nz_trailer`') then
    local out = {}
    for _, r in ipairs(rowsOf()) do if r.nz_trailer ~= nil then out[#out + 1] = { plate = r.plate, nz_trailer = r.nz_trailer } end end
    return out
  end
  if sql:match('^SELECT 1 FROM `vehicle_financing`') then
    return db.financing[params[1]] and 1 or nil
  end
  if sql:match('^SELECT') then return selectRows(sql, params) end
  if sql:match('^UPDATE `vehicle_financing` SET') then
    local assignments = sql:match('SET (.-) WHERE `vehicleId` = %?$')
    local fin = db.financing[params[#params]]
    if not fin then return 0 end
    applyAssignments(fin, assignments, params)
    return 1
  end
  if sql:match('^INSERT INTO `vehicle_financing`') then
    db.financing[params[1]] = { vehicleid = params[1], balance = params[2], paymentamount = params[3], paymentsleft = params[4], financetime = params[5] }
    return 1
  end
  if sql:match('^UPDATE `[%w_]+` SET') then
    local assignments = sql:match('SET (.-) WHERE `plate` = %?$')
    if not assignments then error('fake MySQL: unsupported UPDATE: ' .. sql) end
    local plate = params[#params]
    for _, r in ipairs(db.rows) do
      if r.plate == plate then
        for col in assignments:gmatch('`([%w_]+)` =') do
          if not db.columns[col] then error('fake MySQL: unknown column ' .. col) end
        end
        applyAssignments(r, assignments, params)
        return 1
      end
    end
    return 0
  end
  if sql:match('^DELETE FROM `vehicle_financing`') then
    db.financing[params[1]] = nil
    return 1
  end
  error('fake MySQL: unsupported statement: ' .. sql)
end

local function single(sql, params)
  local res = query(sql, params)
  if type(res) == 'table' then return res[1] end
  return res
end

MySQL = {
  query = { await = function(sql, params) return query(sql, params) end },
  single = { await = function(sql, params) return single(sql, params) end },
  scalar = { await = function(sql, params) local r = query(sql, params) if type(r) == 'table' then r = r[1] end return r end },
  update = { await = function(sql, params) return query(sql, params) end },
  insert = { await = function(sql, params) return query(sql, params) end },
  transaction = { await = function() return true end },
}

local BASE_COLUMNS = {
  qb = { 'id', 'citizenid', 'license', 'vehicle', 'hash', 'mods', 'plate', 'garage', 'fuel', 'engine', 'body', 'state',
    'depotprice', 'balance', 'paymentamount', 'paymentsleft', 'financetime' },
  qbx = { 'id', 'citizenid', 'license', 'vehicle', 'hash', 'mods', 'plate', 'garage', 'fuel', 'engine', 'body', 'state', 'depotprice' },
  esx = { 'owner', 'plate', 'vehicle', 'type', 'stored', 'parking', 'pound' },
}
local NZ_COLUMNS = { 'nz_garage', 'nz_state', 'nz_nickname', 'nz_type', 'nz_job', 'nz_gang', 'nz_mileage', 'nz_damage',
  'nz_trailer', 'nz_impound', 'nz_blocked', 'nz_last_out', 'nz_finance_total', 'nz_key_version', 'nz_key_owner' }

--- Add a framework row. fields: plate, owner, model, garage key, state code, extra columns.
function H.addRow(fields)
  local r = { id = db.nextId, nz_state = 1, nz_mileage = 0, nz_blocked = 0 }
  db.nextId = db.nextId + 1
  local esx = db.framework == 'esx'
  r.plate = fields.plate
  local props = fields.props or { model = joaat_(fields.model or 'sultan'), plate = fields.plate }
  if esx then
    r.owner = fields.owner or 'CID001'
    props.model = props.model or joaat_(fields.model or 'sultan')
    r.vehicle = json.encode(props)
    r.type = 'car'
    r.stored = (fields.state or 1) == 1 and 1 or 0
  else
    r.citizenid = fields.owner or 'CID001'
    r.vehicle = fields.model or 'sultan'
    r.hash = tostring(joaat_(fields.model or 'sultan'))
    r.mods = json.encode(props)
    r.state = fields.state or 1
    r.fuel, r.engine, r.body = 100, 1000, 1000
    if db.framework == 'qb' then r.balance, r.paymentamount, r.paymentsleft, r.financetime = 0, 0, 0, 0 end
  end
  r.nz_garage = fields.garage or 'L1'
  r.nz_state = fields.state or 1
  r.nz_type = 'car'
  for k, v in pairs(fields.extra or {}) do r[k] = v end
  db.rows[#db.rows + 1] = r
  return r
end

function H.raw(plate)
  for _, r in ipairs(db.rows) do if r.plate == plate then return r end end
  return nil
end

---------------------------------------------------------------------------------------
-- Resource bootstrap
---------------------------------------------------------------------------------------

--- Load the shared files and server/db.lua for `framework` with the fake schema.
--- opts.financeColumn = true: nz_finance exists already.
function H.setup(framework, opts)
  opts = opts or {}
  db.framework = framework
  for _, c in ipairs(BASE_COLUMNS[framework]) do db.columns[c] = true end
  for _, c in ipairs(NZ_COLUMNS) do db.columns[c] = true end
  if opts.financeColumn then db.columns.nz_finance = true end

  H.load('config/config.lua')
  H.load('config/carlock.lua')
  H.load('shared/init.lua')
  H.load('shared/utils.lua')
  H.load('bridge/shared.lua')
  NZ.Framework = framework

  NZ.DB.schema = { loaded = false, exists = false, columns = {}, financeMode = 'none', financeColumns = {}, version = 0 }
  function NZ.DB.loadSchema()
    local s = NZ.DB.schema
    local cols = {}
    for c in pairs(db.columns) do cols[c] = true end
    s.columns = cols
    s.exists = cols.plate == true
    if framework == 'qb' then
      s.financeMode = 'columns'
    elseif framework == 'qbx' then
      s.financeMode = 'table'
      s.financeColumns = { vehicleid = true, balance = true, paymentamount = true, paymentsleft = true, financetime = true }
    else
      s.financeMode = 'none'
    end
    s.loaded = true
    s.version = (s.version or 0) + 1
    return s.exists
  end
  H.load('server/db.lua')
  NZ.DB.loadSchema()

  NZ.Settings.get = function(path, default)
    if H.settings and H.settings[path] ~= nil then return H.settings[path] end
    local node = Config.DefaultSettings
    for part in path:gmatch('[^%.]+') do
      if type(node) ~= 'table' then return default end
      node = node[part]
    end
    if node == nil then return default end
    return node
  end
  H.settings = {}

  H.logs = {}
  NZ.Logs.add = function(event, src, data) H.logs[#H.logs + 1] = { event = event, src = src, data = data or {} } end

  H.bank = { [1] = 100000, [2] = 0 }
  NZ.Bridge.getIdentifier = function(src) return H.online[tonumber(src)] end
  NZ.Bridge.getName = function(src) return 'Name ' .. tostring(src) end
  NZ.Bridge.getCharacterName = function(id) return 'Name ' .. tostring(id) end
  NZ.Bridge.getSourceByIdentifier = function(id) for src, cid in pairs(H.online) do if cid == id then return src end end return nil end
  NZ.Bridge.getJob = function() return nil end
  NZ.Bridge.getGang = function() return nil end
  NZ.Bridge.notify = function(src, message, kind) TriggerClientEvent('nz:client:notify', src, { type = kind, message = message }) end
  NZ.Bridge.pay = function(src, amount)
    src = tonumber(src)
    if (H.bank[src] or 0) < amount then return false, nil end
    H.bank[src] = H.bank[src] - amount
    return true, 'bank'
  end
  NZ.Bridge.addMoney = function(src, _, amount)
    H.bank[tonumber(src)] = (H.bank[tonumber(src)] or 0) + amount
    return true
  end
  NZ.Bridge.isAdmin = function() return false end

  -- locations: one public garage at the origin, one impound
  H.locations = {
    [1] = { id = 1, kind = 'garage', name = 'Legion Square', vehicleType = 'car', enabled = true, source = 'personal',
      restriction = { type = 'everyone', rules = {}, identifiers = {} },
      openPoints = { { coords = vec3(10, 0, 0), radius = 4.0 } }, storePoints = {}, useOpenForStore = true,
      spawnPoints = { vector4(100, 0, 0, 90.0) } },
    [5] = { id = 5, kind = 'impound', name = 'Davis Impound', vehicleType = 'car', enabled = true, jobs = {},
      openPoints = { { coords = vec3(500, 0, 0), radius = 2.0 } }, spawnPoints = { vector4(510, 0, 0, 0) } },
  }
  NZ.Locations.get = function(id) return H.locations[tonumber(id)] end
  NZ.Locations.all = function(kind)
    local out = {}
    for _, l in pairs(H.locations) do if not kind or l.kind == kind then out[#out + 1] = l end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end
  NZ.Locations.resolveKey = function(key)
    local kind, id = NZ.Utils.key.parse(key)
    if kind == 'L' and H.locations[id] then return { kind = 'L', key = key, location = H.locations[id], locationId = id } end
    return nil
  end
  NZ.Locations.keyName = function(key)
    local r = NZ.Locations.resolveKey(key)
    return r and r.location.name or nil
  end
  H.capacityFull = false
  NZ.Locations.capacity = function()
    if H.capacityFull then return { mode = 'limited', total = 1, used = 1 } end
    return nil
  end
  NZ.Private.role = function() return nil end
  NZ.Private.groupsFor = function() return {} end
  NZ.Private.getGroup = function() return nil end
  NZ.Jobs.isSpawnerVehicle = function() return false end
  NZ.Interiors.instances = {}
  H.sessions = {}
  NZ.Access.openSession = function(src, key, location, extra)
    local s = { garageKey = key, location = location, groupId = extra and extra.groupId or nil }
    H.sessions[src] = s
    return s
  end
  NZ.Access.getSession = function(src) return H.sessions[src] end
  NZ.Access.requireSession = function(src) return H.sessions[src], H.sessions[src] == nil and 'The garage is not open' or nil end
  NZ.Access.rateLimit = function() return true end
  NZ.Access.canUse = function() return true end
  NZ.Access.jobAllowed = function() return false end
  NZ.Access.isNear = function() return true end
  NZ.Access.nearLocation = function() return true end
  NZ.Access.inZone = function() return false end
  NZ.DB.shares = { forPlate = function() return {} end, forIdentifier = function() return {} end, clear = function() return true end,
    counts = function() return {} end }
  NZ.DB.favourites = { get = function() return {} end, set = function() return true end }
  NZ.DB.events = { add = function() return 1 end, list = function() return {} end }
  return H
end

function H.finish(name)
  H.scenario = 'console'
  H.check(#H.printed.error == 0, 'no errors printed: ' .. table.concat(H.printed.error, ' | '))
  if #failures > 0 then
    print(('%s: %d of %d checks failed'):format(name, #failures, checks))
    for _, f in ipairs(failures) do print('  - ' .. f) end
    os.exit(1)
  end
  print(('%s OK (%d checks)'):format(name, checks))
end

return H
