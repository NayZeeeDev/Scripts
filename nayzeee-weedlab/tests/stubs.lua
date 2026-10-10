--[[ Minimal FiveM / ox_lib / oxmysql stubs for headless server tests (Lua 5.4) ]]

local S = { time = 1700000000, timer = 0, net = {}, events = {}, callbacks = {}, client = {}, timeouts = {}, threads = {},
    entities = {}, nextEnt = 100, peds = {}, pos = {}, inveh = {}, buckets = {}, db = {}, commands = {} }
_G.Stubs = S

-- time --------------------------------------------------------------------
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return S.time end
function GetGameTimer() return S.timer end

-- vectors -----------------------------------------------------------------
local V = {}
V.__index = function(t, k)
    if k == 'xyz' then return vec3(t.x, t.y, t.z) end
    return rawget(V, k)
end
local function mk(x, y, z, w) return setmetatable({ x = x, y = y, z = z, w = w }, V) end
function vec2(x, y) return mk(x + 0.0, y + 0.0, nil, nil) end
function vec3(x, y, z)
    if type(x) == 'table' then return mk(x.x, x.y, x.z) end
    return mk(x + 0.0, y + 0.0, z + 0.0)
end
function vec4(x, y, z, w) return mk(x + 0.0, y + 0.0, z + 0.0, w + 0.0) end
vector2, vector3, vector4 = vec2, vec3, vec4
V.__add = function(a, b) return mk(a.x + b.x, a.y + b.y, (a.z or 0) + (b.z or 0)) end
V.__sub = function(a, b) return mk(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)) end
V.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return mk(a.x * b, a.y * b, (a.z or 0) * b) end
V.__div = function(a, b) return mk(a.x / b, a.y / b, (a.z or 0) / b) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + (a.z or 0) ^ 2) end

-- json --------------------------------------------------------------------
json = {}
local function enc(v, out)
    local t = type(v)
    if t == 'table' then
        if next(v) == nil then out[#out + 1] = '[]' return end
        if #v > 0 then
            out[#out + 1] = '['
            for i = 1, #v do if i > 1 then out[#out + 1] = ',' end enc(v[i], out) end
            out[#out + 1] = ']'
        else
            out[#out + 1] = '{'
            local first = true
            for k, val in pairs(v) do
                if not first then out[#out + 1] = ',' end
                first = false
                out[#out + 1] = string.format('%q:', tostring(k))
                enc(val, out)
            end
            out[#out + 1] = '}'
        end
    elseif t == 'string' then out[#out + 1] = string.format('%q', v)
    elseif t == 'nil' then out[#out + 1] = 'null'
    else out[#out + 1] = tostring(v) end
end
function json.encode(v) local out = {} enc(v, out) return table.concat(out) end
json.decode = function() return {} end

-- runtime -----------------------------------------------------------------
function GetCurrentResourceName() return 'nayzeee-weedlab' end
function IsDuplicityVersion() return true end
function GetResourceState() return 'missing' end
function GetInvokingResource() return nil end
function joaat(s) local h = 0 for i = 1, #tostring(s) do h = (h * 31 + tostring(s):byte(i)) % 4294967296 end return h end
function GetPlayers() local o = {} for src in pairs(S.peds) do o[#o + 1] = tostring(src) end return o end
function GetPlayerName(src) return 'Player' .. src end
function GetPlayerIdentifierByType(src) return 'license:test' .. src end
function DropPlayer(src, why) S.dropped = { src, why } end
function IsPlayerAceAllowed() return true end
function RegisterCommand(name, fn) S.commands[name] = fn end
function PerformHttpRequest() end
function print_(...) end

Citizen = {}
function Citizen.Await(p) return p.value end
promise = {}
function promise.new() return { value = nil, resolve = function(self, v) self.value = v end } end

function CreateThread(fn)
    local co = coroutine.create(fn)
    S.threads[#S.threads + 1] = co
    local ok, err = coroutine.resume(co)
    if not ok then error(err) end
end

--- resume every thread that is waiting (one tick of the scheduler)
function S.runThreads()
    for i = #S.threads, 1, -1 do
        local co = S.threads[i]
        if coroutine.status(co) == 'dead' then
            table.remove(S.threads, i)
        else
            local ok, err = coroutine.resume(co)
            if not ok then error(err) end
        end
    end
end

GlobalState = {}
function Wait(ms) if coroutine.isyieldable() then coroutine.yield(ms) end end
function SetTimeout(ms, fn) S.timeouts[#S.timeouts + 1] = { at = S.timer + ms, fn = fn } end

--- move time forward: game timer (ms) + os.time (s), firing timeouts
function S.advance(ms)
    S.timer = S.timer + ms
    S.time = S.time + math.floor(ms / 1000)
    local again = true
    while again do
        again = false
        for i, t in ipairs(S.timeouts) do
            if t.at <= S.timer then
                table.remove(S.timeouts, i)
                t.fn()
                again = true
                break
            end
        end
    end
end

-- events ------------------------------------------------------------------
function RegisterNetEvent(name, fn) if fn then S.net[name] = S.net[name] or {} table.insert(S.net[name], fn) end end
function AddEventHandler(name, fn) S.events[name] = S.events[name] or {} table.insert(S.events[name], fn) end
function TriggerEvent(name, ...) for _, fn in ipairs(S.events[name] or {}) do fn(...) end end
function TriggerClientEvent(name, src, ...) S.client[#S.client + 1] = { name = name, src = src, args = { ... } } end
function S.fire(src, name, ...)
    for _, fn in ipairs(S.net[name] or {}) do
        source = src
        fn(...)
    end
    source = nil
end
function S.lastClient(name)
    for i = #S.client, 1, -1 do if S.client[i].name == name then return S.client[i] end end
end

-- ox_lib ------------------------------------------------------------------
lib = { callback = {} }
function lib.callback.register(name, fn) S.callbacks[name] = fn end
function lib.locale() end
function S.call(src, name, ...)
    local fn = S.callbacks[name]
    assert(fn, 'no callback ' .. name)
    return fn(src, ...)
end

-- oxmysql -----------------------------------------------------------------
MySQL = { query = {}, single = {} }
function MySQL.query.await(q) return {} end
function MySQL.single.await(q, p) local d = S.db[p[1]] return d and { data = d } or nil end
function MySQL.prepare(q, p) if q:find('nayzeee_weedlab`') and q:find('INSERT') then S.db[p[1]] = p[2] end end
function MySQL.insert() end

-- entities ----------------------------------------------------------------
local function newEnt(kind, x, y, z, h)
    S.nextEnt = S.nextEnt + 1
    S.entities[S.nextEnt] = { kind = kind, pos = vec3(x, y, z), h = h or 0.0, state = {}, health = 1000.0 }
    return S.nextEnt
end
function CreateVehicleServerSetter(model, t, x, y, z, h) return newEnt('veh', x, y, z, h) end
function DoesEntityExist(e) return S.entities[e] ~= nil end
function DeleteEntity(e) S.entities[e] = nil end
function GetEntityCoords(e)
    for src, ped in pairs(S.peds) do if ped == e then return S.pos[src] end end
    return S.entities[e] and S.entities[e].pos or vec3(0, 0, 0)
end
function GetEntityHeading(e) return S.entities[e] and S.entities[e].h or 0.0 end
function GetPlayerPed(src) return S.peds[src] or 0 end
function GetVehiclePedIsIn(ped) for src, p in pairs(S.peds) do if p == ped then return S.inveh[src] or 0 end end return 0 end
function NetworkGetNetworkIdFromEntity(e) return e + 5000 end
function NetworkGetEntityFromNetworkId(n) return n - 5000 end
function Entity(e) return { state = { set = function(_, k, v) if S.entities[e] then S.entities[e].state[k] = v end end } } end
function SetVehicleDoorsLocked() end
function SetVehicleNumberPlateText() end
function SetEntityOrphanMode() end
function GetVehicleEngineHealth(e) return S.entities[e] and S.entities[e].health or -4000.0 end
function SetPlayerRoutingBucket(src, b) S.buckets[src] = b end

function S.join(src, pos)
    S.peds[src] = newEnt('ped', 0, 0, 0)
    S.pos[src] = pos or vec3(0, 0, 0)
end
function S.move(src, p) S.pos[src] = vec3(p.x, p.y, p.z) end
function S.moveEnt(e, p) S.entities[e].pos = vec3(p.x, p.y, p.z) end

return S
