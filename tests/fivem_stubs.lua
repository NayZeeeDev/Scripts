--[[ Minimal FiveM / ox_lib / oxmysql stubs for headless server-side tests (Lua 5.4) ]]

local Stubs = { now = 1000000, gameTimer = 0, events = {}, netHandlers = {}, callbacks = {}, clientEvents = {}, timers = {}, entities = {}, nextEnt = 100, players = {}, buckets = {} }
_G.Stubs = Stubs

-- vectors ---------------------------------------------------------------
local V = {}
V.__index = function(t, k)
    if k == 'xyz' then return vec3(t.x, t.y, t.z) end
    if k == 'xy' then return vec2(t.x, t.y) end
    return rawget(V, k)
end
local function mk(x, y, z, w, n) return setmetatable({ x = x, y = y, z = z, w = w, n = n }, V) end
function vec2(x, y) return mk(x + 0.0, y + 0.0, nil, nil, 2) end
function vec3(x, y, z)
    if type(x) == 'table' then return mk(x.x, x.y, x.z, nil, 3) end
    return mk(x + 0.0, y + 0.0, z + 0.0, nil, 3)
end
function vec4(x, y, z, w) return mk(x + 0.0, y + 0.0, z + 0.0, w + 0.0, 4) end
vector2, vector3, vector4 = vec2, vec3, vec4
local function comps(v) return v.x, v.y, v.z or 0, v.w or 0 end
V.__add = function(a, b) return mk(a.x + b.x, a.y + b.y, a.z and (a.z + (b.z or 0)), a.w, a.n) end
V.__sub = function(a, b) return mk(a.x - b.x, a.y - b.y, a.z and (a.z - (b.z or 0)), a.w, a.n) end
V.__mul = function(a, b)
    if type(a) == 'number' then a, b = b, a end
    return mk(a.x * b, a.y * b, a.z and a.z * b, a.w, a.n)
end
V.__unm = function(a) return mk(-a.x, -a.y, a.z and -a.z, a.w, a.n) end
V.__len = function(a) local x, y, z = comps(a) return math.sqrt(x * x + y * y + (a.n == 2 and 0 or z * z)) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z and a.w == b.w end
V.__tostring = function(a) return ('vec(%s,%s,%s)'):format(a.x, a.y, a.z) end

-- json ------------------------------------------------------------------
json = {}
local function enc(v, out)
    local t = type(v)
    if t == 'table' then
        if getmetatable(v) == V then out[#out + 1] = ('{"x":%s,"y":%s,"z":%s}'):format(v.x, v.y, v.z or 0) return end
        if #v > 0 or next(v) == nil then
            out[#out + 1] = '['
            for i = 1, #v do if i > 1 then out[#out + 1] = ',' end enc(v[i], out) end
            out[#out + 1] = ']'
        else
            out[#out + 1] = '{'
            local first = true
            for k, val in pairs(v) do
                if not first then out[#out + 1] = ',' end
                first = false
                out[#out + 1] = ('"%s":'):format(tostring(k))
                enc(val, out)
            end
            out[#out + 1] = '}'
        end
    elseif t == 'string' then out[#out + 1] = ('%q'):format(v)
    elseif t == 'nil' then out[#out + 1] = 'null'
    else out[#out + 1] = tostring(v) end
end
function json.encode(v) local out = {} enc(v, out) return table.concat(out) end
function json.decode(s) return {} end

-- scheduler -------------------------------------------------------------
local queue = {}
local function schedule(co, at) queue[#queue + 1] = { co = co, at = at } end
function CreateThread(fn)
    local co = coroutine.create(fn)
    schedule(co, Stubs.gameTimer)
end
Citizen = { CreateThread = CreateThread, Await = function(p) return p end }
function Wait(ms)
    local co, main = coroutine.running()
    if main then return end
    coroutine.yield(Stubs.gameTimer + (ms or 0))
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function Stubs.advance(ms)
    local target = Stubs.gameTimer + ms
    while true do
        table.sort(queue, function(a, b) return a.at < b.at end)
        local job = queue[1]
        if not job or job.at > target then break end
        table.remove(queue, 1)
        if job.at > Stubs.gameTimer then Stubs.gameTimer = job.at end
        local ok, res = coroutine.resume(job.co)
        if not ok then error(res) end
        if coroutine.status(job.co) ~= 'dead' then schedule(job.co, res or Stubs.gameTimer) end
    end
    Stubs.gameTimer = target
end
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return Stubs.now + math.floor(Stubs.gameTimer / 1000) end
function GetGameTimer() return Stubs.gameTimer end

-- events ----------------------------------------------------------------
function RegisterNetEvent(name, fn) if fn then Stubs.netHandlers[name] = Stubs.netHandlers[name] or {} table.insert(Stubs.netHandlers[name], fn) end end
function AddEventHandler(name, fn) Stubs.events[name] = Stubs.events[name] or {} table.insert(Stubs.events[name], fn) end
function TriggerEvent(name, ...) for _, fn in ipairs(Stubs.events[name] or {}) do fn(...) end end
function Stubs.netEvent(src, name, ...)
    for _, fn in ipairs(Stubs.netHandlers[name] or {}) do
        local env = { source = src }
        _G.source = src
        fn(...)
    end
end
function TriggerClientEvent(name, target, ...)
    Stubs.clientEvents[#Stubs.clientEvents + 1] = { name = name, target = target, args = table.pack(...) }
end
function GetInvokingResource() return nil end

-- resource / misc --------------------------------------------------------
function GetCurrentResourceName() return 'nayzeee-heistpack' end
function IsDuplicityVersion() return true end
function GetResourceState() return 'missing' end
local kvp = {}
function SetResourceKvp(k, v) kvp[k] = v end
function GetResourceKvpString(k) return kvp[k] end
function PerformHttpRequest() end
function IsPlayerAceAllowed() return true end
function RegisterCommand() end
function LoadResourceFile(_, path) local f = io.open(Stubs.root .. '/' .. path) if not f then return nil end local s = f:read('a') f:close() return s end
function joaat(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
function GetHashKey(s) return joaat(s) end

-- global state ----------------------------------------------------------
GlobalState = setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })

-- players & entities ----------------------------------------------------
function GetPlayers() local l = {} for src in pairs(Stubs.players) do l[#l + 1] = tostring(src) end return l end
function GetPlayerName(src) local p = Stubs.players[tonumber(src)] return p and p.name or nil end
function GetPlayerPed(src) local p = Stubs.players[src] return p and p.ped or 0 end
function GetPlayerIdentifierByType(src) return 'license:' .. src end
function GetPlayerRoutingBucket(src) return Stubs.buckets[src] or 0 end
function SetPlayerRoutingBucket(src, b) Stubs.buckets[src] = b end
function SetRoutingBucketPopulationEnabled() end
function DropPlayer(src, reason) print('DROP', src, reason) end

function Stubs.newEntity(kind, coords)
    Stubs.nextEnt = Stubs.nextEnt + 1
    local e = { id = Stubs.nextEnt, kind = kind, coords = coords, health = 200, state = {} }
    Stubs.entities[e.id] = e
    return e.id
end
function Stubs.addPlayer(src, coords)
    local ped = Stubs.newEntity('ped', coords)
    Stubs.players[src] = { name = 'Player' .. src, ped = ped }
    return ped
end
function Stubs.setCoords(ent, c) Stubs.entities[ent].coords = vec3(c.x, c.y, c.z) end

function DoesEntityExist(e) return Stubs.entities[e] ~= nil end
function GetEntityCoords(e) local en = Stubs.entities[e] return en and en.coords or vec3(0, 0, 0) end
function GetEntityHealth(e) local en = Stubs.entities[e] return en and en.health or 0 end
function GetEntityType(e) local en = Stubs.entities[e] return en and (en.kind == 'vehicle' and 2 or en.kind == 'ped' and 1 or 3) or 0 end
function NetworkGetEntityFromNetworkId(n) return Stubs.entities[n] and n or 0 end
function NetworkGetNetworkIdFromEntity(e) return e end
function SetEntityOrphanMode() end
function SetVehicleDoorsLocked(e, s) Stubs.entities[e].locked = s end
function GetPedInVehicleSeat() return 0 end
function IsPedAPlayer() return false end
function DeleteEntity(e) Stubs.entities[e] = nil end
function SetEntityCoords(e, x, y, z) Stubs.entities[e].coords = vec3(x, y, z) end
function SetEntityHeading() end
function CreateVehicleServerSetter(_, _, x, y, z) return Stubs.newEntity('vehicle', vec3(x, y, z)) end
function Entity(e)
    return { state = setmetatable({}, { __index = function(_, k)
        if k == 'set' then return function(self, key, v) Stubs.entities[e].state[key] = v end end
        return Stubs.entities[e] and Stubs.entities[e].state[k]
    end }) }
end

-- ox_lib ----------------------------------------------------------------
local locales = {}
lib = {
    callback = { register = function(name, fn) Stubs.callbacks[name] = fn end },
    locale = function() end,
    load = function(mod)
        local path = Stubs.root .. '/' .. mod:gsub('%.', '/') .. '.lua'
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        return chunk()
    end,
}
function locale(key, ...)
    local s = Stubs.strings[key]
    if not s then Stubs.missingLocale[key] = true return key end
    local ok, out = pcall(string.format, s, ...)
    return ok and out or s
end
Stubs.missingLocale = {}

function Stubs.call(src, name, ...)
    local fn = Stubs.callbacks[name]
    if not fn then error('no callback ' .. name) end
    local co = coroutine.create(fn)
    local res = table.pack(coroutine.resume(co, src, ...))
    -- run any yields (await) to completion
    while coroutine.status(co) ~= 'dead' do
        Stubs.advance(100)
        res = table.pack(coroutine.resume(co))
    end
    if not res[1] then error(res[2]) end
    return table.unpack(res, 2, res.n)
end

-- oxmysql ---------------------------------------------------------------
local profiles = {}
MySQL = {
    query = { await = function(q, p)
        if q:find('ORDER BY xp') then local l = {} for _, r in pairs(profiles) do l[#l + 1] = r end return l end
        return {}
    end },
    single = { await = function(_, p) return profiles[p[1]] and setmetatable({}, { __index = profiles[p[1]] }) and (function() local c = {} for k, v in pairs(profiles[p[1]]) do c[k] = v end return c end)() end },
    insert = setmetatable({ await = function(q, p)
        if q:find('nzh_profiles') then profiles[p[1]] = profiles[p[1]] or { identifier = p[1], nickname = p[2], avatar = 1, xp = 0, completed = 0, failed = 0, earned = 0, stats = '{}' } end
        return 1
    end }, { __call = function() return 1 end }),
    update = setmetatable({}, { __call = function() return 1 end }),
    scalar = { await = function() return nil end },
}
Stubs.profiles = profiles

return Stubs
