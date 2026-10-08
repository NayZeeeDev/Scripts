--[[
    Headless end-to-end test: loads the real server code with stubbed natives and plays
    every heist from start to finish, simulating the client (spawns, claims, finishes,
    guard deaths, deliveries, escape). Run: tests/run.sh
]]

local root = arg[1]
local Stubs = dofile(arg[2] .. '/fivem_stubs.lua')
Stubs.root = root
Stubs.strings = dofile(arg[3])

local function load(path) local f, err = loadfile(root .. '/' .. path) if not f then error(err) end f() end

-- integration stubs (bridges talk to real resources, so they are replaced here)
local given = {}
FW = { name = 'test' }
function FW.getPlayer(src) return Stubs.players[src] end
function FW.identifier(src) return 'char:' .. src end
function FW.charName(src) return 'Char ' .. src end
function FW.job() return { name = 'unemployed', onduty = false } end
function FW.isPolice() return false end
function FW.policeCount() return 10 end
function FW.policePlayers() return {} end
function FW.getMoney() return 1e9 end
function FW.removeMoney() return true end
function FW.addMoney(src, acc, amount) given[#given + 1] = { src = src, item = 'money:' .. acc, amount = amount } return true end
function FW.notify() end
function FW.registerUsable() end
function FW.onLoaded() end
function FW.onUnloaded() end
Inv = { name = 'test' }
function Inv.count() return 99 end
function Inv.has() return true end
function Inv.remove() return true end
function Inv.canCarry() return true end
function Inv.add(src, name, count) given[#given + 1] = { src = src, item = name, amount = count } return true end
function Inv.label(n) return n end
function Inv.payMoney(src, amount) given[#given + 1] = { src = src, item = 'money', amount = amount } return true end
local alerts = 0
Dispatch = { name = 'test', alert = function() alerts = alerts + 1 end }

load('config/main.lua')
Config.Crew.readyCheck = false
load('shared/utils.lua')
load('shared/registry.lua')
load('config/server.lua')
ServerConfig.Exploit.maxCallsPerSecond = 100000
for _, f in ipairs({ 'guard', 'db', 'profile', 'crew', 'chat', 'market', 'fence', 'heist/cooldowns', 'heist/rewards', 'heist/engine', 'heist/watchers', 'admin', 'main' }) do
    load('server/' .. f .. '.lua')
end
Stubs.advance(10)

local function fail(msg) error(msg, 0) end

-- players
local MEMBERS = 8
for src = 1, MEMBERS do Stubs.addPlayer(src, vec3(736.0, -1332.0, 25.0)) end
for src = 1, MEMBERS do
    local ok = Stubs.call(src, 'nzh:menu:open')
    if not ok then fail('menu open failed for ' .. src) end
    Profile.get(src).xp = 999999
end

local function ped(src) return GetPlayerPed(src) end
local function moveAll(c) for src = 1, MEMBERS do Stubs.setCoords(ped(src), c) end end

local function buildCrew(n)
    for src = 1, MEMBERS do if Crew.get(src) and #Crew.get(src).members > 1 then Stubs.call(src, 'nzh:crew:leave') end end
    for target = 2, n do
        Stubs.advance(2000)
        local ok, err = Stubs.call(1, 'nzh:crew:invite', target)
        if not ok then fail('invite: ' .. tostring(err)) end
        local ok2, err2 = Stubs.call(target, 'nzh:crew:respond', true)
        if not ok2 then fail('accept: ' .. tostring(err2)) end
    end
end

local function clientEventsFor(name)
    local out = {}
    for _, e in ipairs(Stubs.clientEvents) do if e.name == name then out[#out + 1] = e end end
    return out
end

local function simulateSpawn(inst, idx, spec)
    local result = { guards = {}, entities = {} }
    local function c3(c) return vec3(c.x, c.y, c.z) end
    for _, g in ipairs(spec.guards or {}) do
        local id = Stubs.newEntity('ped', c3(g.coords))
        local grp = g.group or 'guards'
        result.guards[grp] = result.guards[grp] or {}
        table.insert(result.guards[grp], id)
    end
    for _, v in ipairs(spec.vehicles or {}) do
        local id = Stubs.newEntity('vehicle', c3(v.coords))
        if v.key then result.entities[v.key] = id end
        local grp = v.driver and v.driver.group or v.group
        if grp then
            result.guards[grp] = result.guards[grp] or {}
            if v.driver then table.insert(result.guards[grp], Stubs.newEntity('ped', c3(v.coords))) end
            for _ = 1, #(v.passengers or {}) do table.insert(result.guards[grp], Stubs.newEntity('ped', c3(v.coords))) end
        end
    end
    for _, p in ipairs(spec.peds or {}) do
        local id = Stubs.newEntity('ped', c3(p.coords))
        if p.key then result.entities[p.key] = id end
    end
    for _, o in ipairs(spec.objects or {}) do
        local id = Stubs.newEntity('object', c3(o.coords))
        if o.key then result.entities[o.key] = id end
    end
    local ok = Stubs.call(1, 'nzh:heist:spawned', inst.uid, idx, result)
    if not ok then fail('spawned callback rejected for stage ' .. idx) end
end

local function prereqsMet(inst, node)
    for _, r in ipairs(node.requires or {}) do
        if not (inst.nodeState[r] and inst.nodeState[r].done) then return false end
    end
    if node.requiresFlag and not inst.flags[node.requiresFlag] then return false end
    return true
end

local function nodeCoords(inst, node)
    if node.attach then
        local ent = inst.entities[node.attach.entity]
        if not ent then return nil end
        return GetEntityCoords(ent)
    end
    return node.coords and vec3(node.coords.x, node.coords.y, node.coords.z)
end

local spotX = 0
local function actOn(inst, node)
    local st = inst.nodeState[node.id]
    local t = node.type
    local src = 1
    if t == 'zone' then
        if node.decoy then return false end
        if node.requiresFlag and not inst.flags[node.requiresFlag] then return false end
        moveAll(node.coords)
        local ok = Stubs.call(src, 'nzh:heist:reach', inst.uid, node.id)
        return ok
    elseif t == 'eliminate' then
        local g = inst.guards[node.group or 'guards']
        if not g or #g == 0 then return false end
        for _, id in ipairs(g) do if Stubs.entities[id] then Stubs.entities[id].health = 0 end end
        Stubs.advance(2000)
        return true
    elseif t == 'deliver' then
        local keys = node.entities or { node.entity }
        for _, k in ipairs(keys) do
            local id = inst.entities[k]
            if not id then return false end
            Stubs.setCoords(id, node.dropoff)
        end
        Stubs.advance(2000)
        return true
    elseif t == 'escape' then
        moveAll(vec3(node.coords.x + node.radius + 50, node.coords.y, node.coords.z))
        for s = 1, MEMBERS do Stubs.buckets[s] = 0 end
        Stubs.advance(2000)
        return true
    elseif t == 'scan' then
        moveAll(node.coords)
        local found = {}
        local i = 0
        for model in pairs(node.models) do
            i = i + 1
            found[#found + 1] = { model = model, coords = vec3(node.coords.x + i * 0.3, node.coords.y, node.coords.z) }
            if i >= 3 then break end
        end
        return Stubs.call(src, 'nzh:heist:scan', inst.uid, node.id, found)
    elseif t == 'portal' then
        if not prereqsMet(inst, node) or node.bucket == 'exit' or inst._entered then return false end
        moveAll(node.coords)
        for m = 1, #inst.members do
            Stubs.setCoords(ped(inst.members[m]), node.coords)
            local ok = Stubs.call(inst.members[m], 'nzh:heist:portal', inst.uid, node.id)
            if not ok then fail('portal failed ' .. node.id) end
        end
        inst._entered = true
        return false -- portals never complete
    elseif t == 'tracker' or t == 'prop' or t == 'hazard' then
        return false
    end
    -- claim / finish types
    if not prereqsMet(inst, node) then return false end
    local extra
    if node.dynamic then
        spotX = spotX + 10
        local c = vec3(100.0 + spotX, -1000.0, 30.0)
        moveAll(c)
        local method
        for k in pairs(node.methods) do method = k break end
        extra = { coords = c, method = method }
    else
        local c = nodeCoords(inst, node)
        if not c then return false end
        moveAll(c)
    end
    local ok, res = Stubs.call(src, 'nzh:heist:claim', inst.uid, node.id, extra)
    if not ok then fail(('claim failed %s (%s): %s'):format(node.id, t, tostring(res))) end
    Stubs.advance(20000)
    local ok2 = Stubs.call(src, 'nzh:heist:finish', inst.uid, node.id, true)
    if not ok2 then print('DEBUG', node.id, 'busy=', tostring(st.busy), 'claimAt=', st.claimAt, 'now=', GetGameTimer(), 'carry=', tostring(node.carry), 'ped=', tostring(GetEntityCoords(GetPlayerPed(1))), 'node=', tostring(node.coords)) end
    if not ok2 then fail(('finish failed %s (%s)'):format(node.id, t)) end
    return true
end

local results = {}
for _, id in ipairs(Heists.order) do
    local def = Heists.defs[id]
    local okRun, err = pcall(function()
        Cooldowns.reset('all')
        buildCrew(math.max(def.members.min, math.min(def.members.max, 3)))
        moveAll(vec3(736.0, -1332.0, 25.0))
        Stubs.clientEvents = {}
        given = {}
        local ok, e = Stubs.call(1, 'nzh:heist:start', id)
        if not ok then fail('start: ' .. tostring(e)) end
        local inst
        for _, i in pairs(Engine.instances) do if i.heistId == id and not i.finished then inst = i end end
        if not inst then fail('no instance') end
        if #clientEventsFor('nzh:heist:begin') == 0 then fail('no begin event') end

        local guard = 0
        while not inst.finished do
            guard = guard + 1
            if guard > 200 then fail('stalled at stage ' .. inst.stageIndex .. ' (' .. tostring(inst.stages[inst.stageIndex].id) .. ')') end
            -- pending spawns
            for _, s in ipairs(Engine.pendingSpawns(inst)) do
                Stubs.clientEvents = {}
                Stubs.netEvent(1, 'nzh:heist:spawnReady', inst.uid, s.index)
                local ev = clientEventsFor('nzh:heist:doSpawn')[1]
                if not ev then fail('no doSpawn for stage ' .. s.index) end
                simulateSpawn(inst, s.index, ev.args[3])
            end
            local progressed = false
            local ids = {}
            for nid in pairs(inst.nodes) do ids[#ids + 1] = nid end
            table.sort(ids)
            local escapeNode
            for _, nid in ipairs(ids) do
                if inst.finished then break end
                local node = inst.nodes[nid]
                local st = node and inst.nodeState[nid]
                if node and st and not st.done then
                    if node.type == 'escape' then escapeNode = node
                    elseif actOn(inst, node) then progressed = true end
                end
            end
            if not progressed and escapeNode and not inst.finished then
                local done, total = 0, 0
                for nid, node in pairs(inst.nodes) do
                    if node.reward then total = total + 1 if inst.nodeState[nid].done then done = done + 1 end end
                end
                inst._loot = ('%d/%d'):format(done, total)
                actOn(inst, escapeNode)
                progressed = true
            end
            if not progressed then Stubs.advance(2000) end
        end
        if not inst.success then fail('heist failed: ' .. tostring(inst.success)) end
        local total = 0
        for _, g in ipairs(given) do if g.item:find('money') then total = total + g.amount end end
        results[#results + 1] = ('PASS  %-14s loot=%-5s stages=%d nodes=%d payouts=%d cash=$%d'):format(id, inst._loot or '-', #inst.stages, (function() local n = 0 for _ in pairs(inst.nodes) do n = n + 1 end return n end)(), #given, total)
    end)
    if not okRun then results[#results + 1] = ('FAIL  %-14s %s'):format(id, tostring(err)) end
    Stubs.advance(10000)
end

-- ---------------------------------------------------------------- failure paths
local function startFresh(id, n)
    Cooldowns.reset('all')
    buildCrew(n)
    moveAll(vec3(736.0, -1332.0, 25.0))
    local ok, e = Stubs.call(1, 'nzh:heist:start', id)
    if not ok then fail('start ' .. id .. ': ' .. tostring(e)) end
    for _, i in pairs(Engine.instances) do if i.heistId == id and not i.finished then return i end end
end

local function check(name, fn)
    local ok, err = pcall(fn)
    results[#results + 1] = (ok and 'PASS  ' or 'FAIL  ') .. name .. (ok and '' or (': ' .. tostring(err)))
    Stubs.advance(10000)
end

check('time limit fails heist', function()
    local inst = startFresh('fleeca', 2)
    Stubs.advance((Heists.defs.fleeca.timeLimit * 60 + 5) * 1000)
    if not inst.finished or inst.success then fail('expected time-out failure') end
end)

check('leader abort', function()
    local inst = startFresh('store', 2)
    local ok = Stubs.call(1, 'nzh:heist:stop')
    if not ok or not inst.finished or inst.success then fail('abort did not fail heist') end
end)

check('non-leader cannot abort', function()
    local inst = startFresh('store', 2)
    local ok = Stubs.call(2, 'nzh:heist:stop')
    if ok or inst.finished then fail('member aborted heist') end
    Stubs.call(1, 'nzh:heist:stop')
end)

check('claim rejected when too far', function()
    local inst = startFresh('fleeca', 1)
    moveAll(vec3(0, 0, 0))
    local ok = Stubs.call(1, 'nzh:heist:claim', inst.uid, 'vault_pad')
    if ok then fail('far claim accepted') end
    Stubs.call(1, 'nzh:heist:stop')
end)

check('instant finish flagged', function()
    local inst = startFresh('fleeca', 1)
    local node = inst.nodes.vault_pad
    moveAll(node.coords)
    local ok = Stubs.call(1, 'nzh:heist:claim', inst.uid, 'vault_pad')
    if not ok then fail('claim failed') end
    local ok2 = Stubs.call(1, 'nzh:heist:finish', inst.uid, 'vault_pad', true)
    if ok2 then fail('instant finish accepted') end
    Stubs.call(1, 'nzh:heist:stop')
end)

check('outsider cannot claim', function()
    local inst = startFresh('fleeca', 1)
    local node = inst.nodes.vault_pad
    Stubs.setCoords(ped(5), node.coords)
    local ok = Stubs.call(5, 'nzh:heist:claim', inst.uid, 'vault_pad')
    if ok then fail('outsider claim accepted') end
    Stubs.call(1, 'nzh:heist:stop')
end)

check('disconnect + reconnect restore', function()
    local inst = startFresh('fleeca', 2)
    -- player 2 drops
    _G.source = 2
    TriggerEvent('playerDropped')
    if #inst.members ~= 1 then fail('member not removed') end
    Engine.restore(2)
    if #inst.members ~= 2 or inst.finished then fail('member not restored') end
    Stubs.call(1, 'nzh:heist:stop')
end)

check('last member leaving fails heist', function()
    local inst = startFresh('store', 1)
    _G.source = 1
    Stubs.clientEvents = {}
    -- voluntary leave of the only member (simulate via Crew.leave)
    Crew.leave(1, true)
    if not inst.finished then fail('heist still running') end
end)

for _, r in ipairs(results) do print(r) end
local missing = {}
for k in pairs(Stubs.missingLocale) do missing[#missing + 1] = k end
if #missing > 0 then print('MISSING LOCALE KEYS: ' .. table.concat(missing, ', ')) end
print(('alerts sent: %d'):format(alerts))
