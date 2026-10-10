--[[ Stations — authoritative state machine for every machine (fixed + player placed).

     Public state (GlobalState 'nzmw:st:<id>') drives the synced props on every client.
     Private state (batch id, jam / alert schedule, settings) never leaves the server.

     washer  : idle → open → loaded → ready → running ⇄ jammed → done → idle
     printer : idle → running ⇄ jammed → done → idle
     cutter  : idle → cutting → done → idle
]]

Stations = { list = {}, priv = {} }
local index = {}

local now = os.time

---------------------------------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------------------------------
local function publishIndex()
    GlobalState['nzmw:index'] = index
end

function Stations.publish(id)
    GlobalState[NZ.stateKey(id)] = Stations.list[id]
end

function Stations.persist(id)
    local st, p = Stations.list[id], Stations.priv[id]
    if not st then return end
    DB.saveStation(id, {
        state = st.state, endsAt = st.endsAt, total = st.total, cut = st.cut, seq = st.seq, wear = st.wear,
        pos = st.moved and { x = st.x, y = st.y, z = st.z, h = st.h } or nil,
        priv = { batch = p.batch, remaining = p.remaining, settings = p.settings, solvent = p.solvent,
                 jamAt = p.jamAt, alertAt = p.alertAt, startedBy = p.startedBy, batches = p.batches },
    })
end

function Stations.commit(id)
    Stations.publish(id)
    Stations.persist(id)
end

function Stations.add(def, meta)
    local st = {
        id = def.id, type = def.type,
        x = def.x, y = def.y, z = def.z, h = def.h,
        label = def.label or (Config.Stages[def.type] and Config.Stages[def.type].label)
            or (def.type == 'counter' and Config.Counter.label) or Config.Pallet.label,
        bucket = def.bucket or 0, facility = def.facility,
        op = def.op, opLabel = def.opLabel,
        placed = def.placed or false, owner = def.owner, ownerName = def.ownerName, share = def.share,
        access = def.access,
        state = 'idle', user = nil, lockUntil = nil, endsAt = nil, total = nil,
        cut = 0, seq = 0, wear = 0.0, hasBatch = false, count = 0,
    }
    local p = {}
    if meta then
        if meta.pos then -- moved in game with the admin tool
            st.x, st.y, st.z, st.h, st.moved = meta.pos.x, meta.pos.y, meta.pos.z, meta.pos.h, true
        end
        st.wear = meta.wear or 0.0
        st.seq = meta.seq or 0
        local mp = meta.priv or {}
        local b = mp.batch and Batches.get(mp.batch)
        if b then
            st.state, st.endsAt, st.total, st.cut = meta.state or 'idle', meta.endsAt, meta.total, meta.cut or 0
            p.batch, p.remaining, p.settings, p.solvent = b.id, mp.remaining, mp.settings, mp.solvent
            p.jamAt, p.alertAt, p.startedBy = mp.jamAt, mp.alertAt, mp.startedBy
            st.hasBatch = true
        end
        if def.type == 'pallet' and mp.batches then
            p.batches = {}
            for _, bid in ipairs(mp.batches) do
                if Batches.get(bid) then p.batches[#p.batches + 1] = bid end
            end
            st.count = #p.batches
            st.state, st.hasBatch = st.count > 0 and 'done' or 'idle', st.count > 0
        end
    end
    if def.type == 'pallet' then p.batches = p.batches or {} end
    if st.state == 'open' and not p.batch then st.state = 'idle' end
    if def.type == 'counter' then st.state = 'idle' end -- a half-finished count doesn't survive a restart
    if st.state == 'done' then p.doneAt = now() end -- restart: the pallet countdown starts over
    Stations.list[st.id], Stations.priv[st.id] = st, p
    index[#index + 1] = st.id
    Stations.publish(st.id)
    publishIndex()
    return st
end

function Stations.remove(id)
    Stations.list[id], Stations.priv[id] = nil, nil
    for i, v in ipairs(index) do
        if v == id then table.remove(index, i) break end
    end
    GlobalState[NZ.stateKey(id)] = nil
    publishIndex()
    DB.deleteStation(id)
end

---------------------------------------------------------------------------------------------------
-- Access + guards
---------------------------------------------------------------------------------------------------
function Stations.hasAccess(src, st)
    if st.placed then
        if Bridge.getIdentifier(src) == st.owner then return true end
        if st.share then
            local kind, name = st.share:match('^(%a+):(.+)$')
            if kind == 'gang' then
                local g = Bridge.getGang(src)
                return g ~= nil and g.name == name
            elseif kind == 'job' then
                return Bridge.getJob(src).name == name
            elseif kind == 'facility' then
                return Facility.isMember(src, tonumber(name))
            end
        end
        return false
    end
    local acc = st.access
    if not acc or (not acc.jobs and not acc.gangs and not acc.items) then return true end
    if acc.jobs then
        local j = Bridge.getJob(src)
        if acc.jobs[j.name] and j.grade >= acc.jobs[j.name] then return true end
    end
    if acc.gangs then
        local g = Bridge.getGang(src)
        if g and acc.gangs[g.name] and g.grade >= acc.gangs[g.name] then return true end
    end
    if acc.items then
        for _, item in ipairs(acc.items) do
            if Inv.count(src, item) > 0 then return true end
        end
    end
    return false
end

-- open operation = no access rules, so anyone can run the machines but only the owner collects a load
function Stations.isOpen(st)
    local a = st.access
    return not st.placed and (not a or (not a.jobs and not a.gangs and not a.items))
end

local function near(src, st)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= (st.bucket or 0) then return false end -- other wash units are invisible
    return #(GetEntityCoords(ped) - vec3(st.x, st.y, st.z)) <= Config.MaxInteractDistance
end

local function lockFree(src, st)
    if not st.user or st.user == src then return true end
    if st.lockUntil and now() > st.lockUntil then return true end
    if not GetPlayerName(st.user) then return true end -- reserved by someone who left
    return false
end

-- 911 call from a machine: units point police to the door and name the unit number
function Stations.alert(st, title, message, code)
    if st.facility and Facility.get(st.facility) then
        Facility.flag(st.facility)
        return Police.alert(Facility.entranceCoords(), title, ('%s (unit #%d)'):format(message, st.facility), code)
    end
    Police.alert(vec3(st.x, st.y, st.z), title, message, code)
end

local function stateIn(state, list)
    if type(list) == 'string' then return state == list end
    for _, s in ipairs(list) do if s == state then return true end end
    return false
end

local function fail(msg) return { ok = false, err = msg } end

-- opts: { type, state, access = bool, lock = bool }
local function guard(src, id, opts)
    local st = Stations.list[id]
    if not st then return nil, nil, fail('That machine no longer exists.') end
    if opts.type and st.type ~= opts.type then return nil, nil, fail('Wrong machine.') end
    if not near(src, st) then return nil, nil, fail('You are too far away.') end
    if opts.access ~= false and not Stations.hasAccess(src, st) then return nil, nil, fail('You do not have the keys to this operation.') end
    if opts.state and not stateIn(st.state, opts.state) then return nil, nil, fail('The machine is not ready for that.') end
    if opts.lock and not lockFree(src, st) then return nil, nil, fail('Someone else is working this machine.') end
    return st, Stations.priv[id]
end

local function reserve(st, src)
    st.user = src
    st.lockUntil = now() + Config.SessionLock
end

local function release(st)
    st.user, st.lockUntil = nil, nil
end

local function enoughPolice()
    return (Config.Heat.minPolice or 0) <= 0 or Bridge.countPolice() >= Config.Heat.minPolice
end

local function scheduleRun(st, p, duration, spinKey, noise)
    local t = now()
    st.state, st.endsAt, st.total = 'running', t + duration, duration
    p.jamAt, p.alertAt = nil, nil
    if math.random() < NZ.jamChance(st.wear, spinKey) then
        p.jamAt = t + math.floor(duration * (0.25 + math.random() * 0.5))
    end
    local b = Batches.get(p.batch)
    local chance = (Config.Heat.alertBase + (b and b.heat or 0) * Config.Heat.alertPerHeat) * (noise or 1.0) * Facility.noiseMult(st)
    if math.random() < chance then
        p.alertAt = t + math.floor(duration * (0.15 + math.random() * 0.7))
    end
end

---------------------------------------------------------------------------------------------------
-- Dirty money
---------------------------------------------------------------------------------------------------
local function sourceTotal(src, s)
    if s.type == 'item' then return Inv.count(src, s.name) end
    if s.type == 'worth' then
        local total = 0
        for _, slot in ipairs(Inv.slots(src, s.name)) do
            total = total + (tonumber(slot.metadata[s.worthKey]) or 0) * (slot.count or 1)
        end
        return total
    end
    if s.type == 'account' then return Bridge.getAccount(src, s.name) end
    return 0
end

function Stations.dirtySources(src)
    local out, seen = {}, {}
    for _, s in ipairs(Config.DirtySources) do
        if not s.frameworks or s.frameworks[Bridge.framework] then
            local total = sourceTotal(src, s)
            -- ox_inventory mirrors ESX accounts as items; don't list the same money twice
            if total > 0 and not seen[s.name] then
                seen[s.name] = true
                out[#out + 1] = { key = s.key, label = s.label, total = math.floor(total), heat = s.heat }
            end
        end
    end
    return out
end

local function findSource(key)
    for _, s in ipairs(Config.DirtySources) do if s.key == key then return s end end
end

local function takeDirty(src, s, amount)
    if sourceTotal(src, s) < amount then return false end
    if s.type == 'item' then return Inv.remove(src, s.name, amount) end
    if s.type == 'account' then return Bridge.removeAccount(src, s.name, amount, 'nz_moneywash') end
    if s.type == 'worth' then
        local slots = Inv.slots(src, s.name)
        table.sort(slots, function(a, b) return (tonumber(a.metadata[s.worthKey]) or 0) < (tonumber(b.metadata[s.worthKey]) or 0) end)
        local taken = 0
        for _, slot in ipairs(slots) do
            if taken >= amount then break end
            local worth = tonumber(slot.metadata[s.worthKey]) or 0
            for _ = 1, slot.count or 1 do
                if taken >= amount then break end
                if not Inv.remove(src, s.name, 1, slot.slot) then return false end
                taken = taken + worth
            end
        end
        local change = taken - amount
        if change > 0 then Inv.add(src, s.name, 1, { [s.worthKey] = change }) end
        return taken >= amount
    end
    return false
end

---------------------------------------------------------------------------------------------------
-- Completion
---------------------------------------------------------------------------------------------------
local function finish(id)
    local st, p = Stations.list[id], Stations.priv[id]
    local b = Batches.get(p.batch)
    if not b then
        st.state, st.endsAt, st.total, st.hasBatch = 'idle', nil, nil, false
        p.batch = nil
        Stations.commit(id)
        return
    end

    if st.type == 'washer' then
        local s = p.settings or { temp = 'warm', spin = 'med' }
        local dye = b.dye
        if p.solvent then
            dye = math.floor(dye / 2)
            Batches.adjustQuality(b, Config.Wash.solventBonus)
        end
        Batches.adjustQuality(b, -NZ.tempPenalty(dye, s.temp))
        Batches.adjustHeat(b, -(Config.Stages.washer.heatDrop + (Config.Wash.temps[s.temp] and Config.Wash.temps[s.temp].heatBonus or 0)))
        b.washedDye, b.dye = b.dye, 0
        Batches.trail(b, ('Washed (%s / %s spin)'):format(s.temp, s.spin))
    elseif st.type == 'printer' then
        local old = b.serial
        Batches.reserial(b)
        Batches.adjustHeat(b, -Config.Stages.printer.heatDrop)
        Batches.trail(b, ('Re-serialised %s → %s'):format(old, b.serial))
    end

    b.stage = NZ.stageIndex(st.type)
    if p.startedBy then b.handlers[st.type] = p.startedBy end
    Batches.save(b)

    st.wear = NZ.clamp(st.wear + Config.Stages[st.type].wearPerRun, 0, 100)
    st.state, st.endsAt, st.total = 'done', nil, nil
    p.jamAt, p.alertAt, p.remaining = nil, nil, nil
    p.doneAt = now()
    Stations.commit(id)

    local runner = p.startedBy or b.owner -- whoever ran this machine gets the ping
    local owner = runner and Bridge.getSourceByIdentifier(runner)
    if owner then
        Bridge.notify(owner, Config.Stages[st.type].label .. ' finished', ('%s is ready to collect at %s.'):format(b.serial, st.opLabel or st.label), 'success')
    end
end

---------------------------------------------------------------------------------------------------
-- Ticker
---------------------------------------------------------------------------------------------------
function Stations.startTicker()
    CreateThread(function()
        while true do
            Wait(1000)
            local t = now()
            for id, st in pairs(Stations.list) do
                local p = Stations.priv[id]
                if st.state == 'running' then
                    if p.jamAt and t >= p.jamAt then
                        p.remaining = math.max(5, (st.endsAt or t) - t)
                        p.jamAt = nil
                        st.state, st.endsAt = 'jammed', nil
                        Stations.commit(id)
                        local b = Batches.get(p.batch)
                        local runner = p.startedBy or (b and b.owner)
                        local owner = runner and Bridge.getSourceByIdentifier(runner)
                        if owner then Bridge.notify(owner, 'Machine jammed', ('%s at %s needs a hand.'):format(st.label, st.opLabel or 'your op'), 'error') end
                    elseif p.alertAt and t >= p.alertAt then
                        p.alertAt = nil
                        Stations.alert(st, 'Suspicious machinery',
                            'Caller reports chemical fumes and industrial noise from a building.', '10-66')
                    elseif st.endsAt and t >= st.endsAt then
                        finish(id)
                    end
                end
                if st.user and st.lockUntil and t > st.lockUntil then
                    release(st)
                    if st.state == 'open' and not p.batch then st.state = 'idle' end
                    Stations.commit(id)
                end
                if st.type == 'counter' then Counter.tick(id, st, p, t) end
                if st.state == 'done' and st.type ~= 'pallet' and p.doneAt and Config.Pallet.enabled
                    and t - p.doneAt >= Config.Pallet.moveAfter then
                    Pallet.tryMove(id)
                end
                if st.pryBy and st.pryAt and t - st.pryAt > 45 then
                    st.pryBy, st.pryAt = nil, nil
                end
            end
        end
    end)
end

---------------------------------------------------------------------------------------------------
-- Callbacks : shared
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:dirtySources', function(src)
    return Stations.dirtySources(src)
end)

lib.callback.register('nzmw:inspect', function(src, id)
    local st = Stations.list[id]
    if not st or not near(src, st) then return fail('Too far.') end
    local p = Stations.priv[id]
    local res = {
        ok = true, label = st.label, type = st.type, state = st.state, wear = NZ.round(st.wear, 1),
        jam = NZ.round(NZ.jamChance(st.wear) * 100, 1), op = st.opLabel, placed = st.placed, owner = st.ownerName,
        remaining = st.endsAt and math.max(0, st.endsAt - now()) or nil, total = st.total,
    }
    if Stations.hasAccess(src, st) and p.batch and Batches.get(p.batch) then
        res.batch = Batches.summary(Batches.get(p.batch))
    end
    return res
end)

lib.callback.register('nzmw:repair', function(src, id)
    local st, _, err = guard(src, id, { state = { 'idle', 'done' } })
    if not st then return err end
    if Inv.count(src, Config.Wear.repairItem) < 1 then return fail('You need a repair kit.') end
    Inv.remove(src, Config.Wear.repairItem, 1)
    st.wear = Config.Wear.repairTo
    Stations.commit(id)
    return { ok = true }
end)

lib.callback.register('nzmw:unjam', function(src, id, success)
    local st, p, err = guard(src, id, { state = 'jammed' })
    if not st then return err end
    if p.lastUnjam and now() - p.lastUnjam < 2 then return fail('Easy...') end
    p.lastUnjam = now()
    local b = Batches.get(p.batch)
    if success then
        st.state, st.endsAt = 'running', now() + (p.remaining or 10)
        p.remaining = nil
        Stations.commit(id)
        return { ok = true, resumed = true }
    end
    if b then
        Batches.adjustQuality(b, -Config.Wear.failPenalty)
        Batches.trail(b, 'Jam fix failed — bills shredded')
        Batches.save(b)
    end
    return { ok = true, resumed = false }
end)

-- Generic collect for any 'done' station (washer / printer / cutter)
lib.callback.register('nzmw:collect', function(src, id)
    local st, p, err = guard(src, id, { state = 'done' })
    if not st then return err end
    if st.type == 'pallet' then return fail('Use the duffel bag.') end
    local b = Batches.get(p.batch)
    if not b then
        st.state, st.hasBatch, p.batch = 'idle', false, nil
        Stations.commit(id)
        return fail('The machine was empty.')
    end
    if Stations.isOpen(st) and (p.startedBy or b.owner) ~= Bridge.getIdentifier(src) then
        return fail('That load isn\'t yours. You\'d have to pry it out.')
    end
    local item = Config.Stages[st.type].outputItem
    if not Batches.giveItem(src, b, item) then return fail('You cannot carry that.') end
    Batches.trail(b, ('Collected from %s by %s'):format(st.label, Bridge.getName(src)))
    Batches.save(b)
    st.state, st.hasBatch, st.cut = 'idle', false, 0
    p.batch, p.settings, p.solvent, p.startedBy, p.doneAt = nil, nil, nil, nil, nil
    release(st)
    Stations.commit(id)
    return { ok = true, item = item, batch = Batches.summary(b) }
end)

---------------------------------------------------------------------------------------------------
-- Callbacks : washer
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:washer:open', function(src, id)
    local st, _, err = guard(src, id, { type = 'washer', state = 'idle', lock = true })
    if not st then return err end
    reserve(st, src)
    st.state = 'open'
    Stations.commit(id)
    return { ok = true }
end)

lib.callback.register('nzmw:washer:shut', function(src, id) -- close an empty open washer
    local st, p, err = guard(src, id, { type = 'washer', state = { 'open', 'loaded' }, lock = true })
    if not st then return err end
    if st.state == 'loaded' then
        st.state = 'ready'
    else
        st.state = 'idle'
    end
    release(st)
    Stations.commit(id)
    return { ok = true, state = st.state, batch = p.batch and Batches.summary(Batches.get(p.batch)) or nil }
end)

lib.callback.register('nzmw:washer:load', function(src, id, sourceKey, amount)
    local st, p, err = guard(src, id, { type = 'washer', state = 'open', lock = true })
    if not st then return err end
    local s = findSource(sourceKey)
    amount = math.floor(tonumber(amount) or 0)
    local cfg = Config.Stages.washer
    if not s then return fail('Unknown money.') end
    if s.frameworks and not s.frameworks[Bridge.framework] then return fail('Unknown money.') end
    if amount < cfg.min or amount > cfg.max then
        return fail(('Load between %s and %s.'):format(NZ.money(cfg.min), NZ.money(cfg.max)))
    end
    if not takeDirty(src, s, amount) then return fail('You do not have that much.') end

    local b = Batches.create(src, s, amount)
    p.batch = b.id
    st.state, st.hasBatch = 'loaded', true
    reserve(st, src)
    Stations.commit(id)
    Bridge.log('Batch loaded', { { 'Player', Bridge.getName(src) .. ' (' .. src .. ')' }, { 'Amount', NZ.money(amount) },
        { 'Source', s.label }, { 'Serial', b.serial }, { 'Station', id } })
    return { ok = true, batch = Batches.summary(b) }
end)

lib.callback.register('nzmw:washer:info', function(src, id)
    local st, p, err = guard(src, id, { type = 'washer', state = { 'ready', 'loaded' } })
    if not st then return err end
    local b = Batches.get(p.batch)
    if not b then return fail('The drum is empty.') end
    local spins = {}
    for k, v in pairs(Config.Wash.spins) do
        spins[k] = { time = NZ.cycleTime('washer', b.amount, k), jam = NZ.round(NZ.jamChance(st.wear, k) * 100, 1), noise = v.noise }
    end
    return {
        ok = true, batch = Batches.summary(b), wear = NZ.round(st.wear, 1), spins = spins,
        solvent = Inv.count(src, Config.Stages.washer.solventItem),
        idealHint = NZ.dyeBand(b.dye).ideal,
    }
end)

lib.callback.register('nzmw:washer:start', function(src, id, temp, spin, useSolvent)
    local st, p, err = guard(src, id, { type = 'washer', state = 'ready' })
    if not st then return err end
    if not Config.Wash.temps[temp] or not Config.Wash.spins[spin] then return fail('Invalid program.') end
    if not enoughPolice() then return fail('Too quiet out there... (not enough police on duty)') end
    local b = Batches.get(p.batch)
    if not b then return fail('The drum is empty.') end
    if Stations.isOpen(st) and b.owner ~= Bridge.getIdentifier(src) then
        return fail('That load isn\'t yours.')
    end

    p.solvent = false
    if useSolvent and Inv.count(src, Config.Stages.washer.solventItem) > 0 then
        Inv.remove(src, Config.Stages.washer.solventItem, 1)
        p.solvent = true
    end
    p.settings = { temp = temp, spin = spin }
    p.startedBy = Bridge.getIdentifier(src)
    scheduleRun(st, p, NZ.cycleTime('washer', b.amount, spin), spin, Config.Wash.spins[spin].noise)
    release(st)
    Stations.commit(id)
    return { ok = true, endsAt = st.endsAt }
end)

---------------------------------------------------------------------------------------------------
-- Callbacks : printer
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:printer:load', function(src, id)
    local st, p, err = guard(src, id, { type = 'printer', state = 'idle' })
    if not st then return err end
    if not enoughPolice() then return fail('Too quiet out there... (not enough police on duty)') end
    local inItem = NZ.inputItem('printer')
    local b, slot = Batches.findInInventory(src, inItem)
    if not b then return fail(('You need %s.'):format(Config.ItemLabels[inItem] or inItem)) end
    local cfg = Config.Stages.printer
    local rolls = math.max(1, math.ceil(b.amount / cfg.paperPer))
    if Inv.count(src, cfg.paperItem) < rolls then
        return fail(('This load needs %d× %s.'):format(rolls, Config.ItemLabels[cfg.paperItem] or cfg.paperItem))
    end
    if not Inv.remove(src, inItem, 1, slot) then return fail('Could not take the cash.') end
    Inv.remove(src, cfg.paperItem, rolls)

    p.batch, p.startedBy = b.id, Bridge.getIdentifier(src)
    st.hasBatch = true
    scheduleRun(st, p, NZ.cycleTime('printer', b.amount), nil, 0.6)
    Batches.trail(b, 'Fed into the press by ' .. Bridge.getName(src))
    Batches.save(b)
    Stations.commit(id)
    return { ok = true, rolls = rolls, endsAt = st.endsAt }
end)

---------------------------------------------------------------------------------------------------
-- Callbacks : cutter
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:cutter:feed', function(src, id)
    local st, p, err = guard(src, id, { type = 'cutter', state = 'idle', lock = true })
    if not st then return err end
    local inItem = NZ.inputItem('cutter')
    local b, slot = Batches.findInInventory(src, inItem)
    if not b then return fail(('You need %s.'):format(Config.ItemLabels[inItem] or inItem)) end
    if not Inv.remove(src, inItem, 1, slot) then return fail('Could not take the sheets.') end

    p.batch, p.startedBy, p.lastCut = b.id, Bridge.getIdentifier(src), nil
    st.state, st.cut, st.hasBatch = 'cutting', 0, true
    reserve(st, src)
    Batches.trail(b, 'Guillotine fed by ' .. Bridge.getName(src))
    Batches.save(b)
    Stations.commit(id)
    return { ok = true, cuts = Config.Stages.cutter.cuts, cut = 0 }
end)

lib.callback.register('nzmw:cutter:cut', function(src, id, result)
    local st, p, err = guard(src, id, { type = 'cutter', state = 'cutting', lock = true })
    if not st then return err end
    local cfg = Config.Stages.cutter
    if p.lastCut and (GetGameTimer() - p.lastCut) / 1000 < cfg.minInterval then return fail('The blade is still resetting.') end
    if result ~= 'perfect' and result ~= 'good' and result ~= 'miss' then result = 'miss' end
    p.lastCut = GetGameTimer()

    local b = Batches.get(p.batch)
    if b then
        Batches.adjustQuality(b, Config.Cut[result] or 0)
        Batches.save(b)
    end
    st.cut, st.seq = st.cut + 1, st.seq + 1
    reserve(st, src)
    if st.cut >= cfg.cuts then
        st.state = 'done'
        p.doneAt = now()
        st.wear = NZ.clamp(st.wear + cfg.wearPerRun, 0, 100)
        release(st)
        if b then
            b.stage = NZ.stageIndex('cutter')
            b.handlers.cutter = p.startedBy
            Batches.trail(b, 'Cut and banded')
            Batches.save(b)
        end
    end
    Stations.commit(id)
    return { ok = true, cut = st.cut, done = st.state == 'done', quality = b and NZ.round(b.quality, 3) }
end)

---------------------------------------------------------------------------------------------------
-- Callbacks : theft (pry open someone else's machine)
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:pry', function(src, id, phase)
    if not Config.Theft.enabled then return fail('Disabled.') end
    local st, p, err = guard(src, id, { state = { 'running', 'done', 'jammed' }, access = false })
    if not st then return err end
    if st.type == 'cutter' or st.type == 'pallet' then return fail('Nothing to pry here.') end
    if not Stations.isOpen(st) and Stations.hasAccess(src, st) then return fail('Just use your keys.') end
    local tool = false
    for _, item in ipairs(Config.Theft.items) do
        if Inv.count(src, item) > 0 then tool = true break end
    end
    if not tool then return fail('You need something to pry it with.') end

    local b = Batches.get(p.batch)
    if not b then return fail('It is empty.') end
    if (p.startedBy or b.owner) == Bridge.getIdentifier(src) then return fail('It\'s your own load.') end

    if phase == 'start' then
        if st.pryBy and st.pryBy ~= src then return fail('Someone is already on it.') end
        st.pryBy, st.pryAt = src, now()
        p.pryBatch = b.id
        if Config.Theft.notifyOwner then
            local owner = Bridge.getSourceByIdentifier(b.owner)
            if owner and owner ~= src then
                Bridge.notify(owner, 'Break-in!', ('Someone is prying open your %s at %s.'):format(st.label, st.opLabel or 'your op'), 'error', 9000)
            end
        end
        if math.random() < Config.Theft.alertChance then
            Stations.alert(st, 'Break-in in progress', 'Alarm triggered on industrial equipment.', '10-31')
        end
        return { ok = true }
    end

    if st.pryBy ~= src or p.pryBatch ~= b.id or now() - (st.pryAt or 0) < math.floor(Config.Theft.duration / 1000 * 0.8) then
        return fail('You were interrupted.')
    end
    st.pryBy, st.pryAt, p.pryBatch = nil, nil, nil

    local done = st.state == 'done'
    local item
    if done then
        item = Config.Stages[st.type].outputItem
    elseif st.type == 'washer' then
        item = Config.Stages.washer.outputItem -- half-washed: no heat drop, quality hit
    else
        item = NZ.inputItem(st.type)        -- ripped out of the press before re-serialising
    end
    -- check before touching the batch so a full inventory can't be used to grief quality
    if not Inv.canCarry(src, item, 1, Batches.metadata(b, item)) then return fail('You cannot carry that.') end
    if not done then
        if st.type == 'washer' then b.stage = 1 end
        Batches.adjustQuality(b, -Config.Theft.runningPenalty)
    end
    if not Batches.giveItem(src, b, item) then return fail('You cannot carry that.') end
    Batches.trail(b, 'Stolen from ' .. st.label)
    Batches.save(b)

    st.state, st.endsAt, st.total, st.hasBatch = 'idle', nil, nil, false
    p.batch, p.jamAt, p.alertAt, p.remaining, p.settings, p.solvent, p.doneAt = nil, nil, nil, nil, nil, nil, nil
    release(st)
    Stations.commit(id)
    Bridge.log('Machine robbed', { { 'Thief', Bridge.getName(src) .. ' (' .. src .. ')' }, { 'Victim', b.ownerName },
        { 'Serial', b.serial }, { 'Amount', NZ.money(b.amount) } })
    return { ok = true, item = item }
end)

-- shared with server/pallet.lua
Stations.guard, Stations.fail, Stations.near = guard, fail, near
