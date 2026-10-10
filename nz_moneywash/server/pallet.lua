--[[ Money pallet — unclaimed finished loads get moved here so the machine frees up.
     The crew loads them into a duffel; anyone else can try to grab one; police can seize the lot. ]]

Pallet = { forOp = {} }

local now = os.time
local C = Config.Pallet

-- which pallet each operation sends its overflow to (an op can borrow another op's pallet with palletOp)
function Pallet.build()
    Pallet.forOp = {}
    for id, st in pairs(Stations.list) do
        if st.type == 'pallet' and st.op then Pallet.forOp[st.op] = id end
    end
    for _, op in ipairs(Config.Operations) do
        if op.palletOp and Pallet.forOp[op.palletOp] then Pallet.forOp[op.id] = Pallet.forOp[op.palletOp] end
    end
end

-- item a batch comes off the pallet as: the output of the last stage it finished
local function itemFor(b)
    local stage = NZ.pipeline()[math.max(1, b.stage)]
    return Config.Stages[stage].outputItem
end

local function holder(b) return b.lastBy or b.owner end

local function ownersOf(p)
    local seen, out = {}, {}
    for _, bid in ipairs(p.batches) do
        local b = Batches.get(bid)
        if b and holder(b) and not seen[holder(b)] then
            seen[holder(b)] = true
            local src = Bridge.getSourceByIdentifier(holder(b))
            if src then out[#out + 1] = src end
        end
    end
    return out
end

local isOpen = function(st) return Stations.isOpen(st) end

local function sync(pid)
    local st, p = Stations.list[pid], Stations.priv[pid]
    st.count = #p.batches
    st.state, st.hasBatch = st.count > 0 and 'done' or 'idle', st.count > 0
    Stations.commit(pid)
end

function Pallet.tryMove(id)
    local st, p = Stations.list[id], Stations.priv[id]
    local pid = st.op and Pallet.forOp[st.op]
    if not pid then p.doneAt = nil return end -- no pallet for this machine: it simply waits
    local pal = Stations.priv[pid]
    if #pal.batches >= C.capacity then return end

    local b = Batches.get(p.batch)
    if not b then p.doneAt = nil return end
    b.lastBy = p.startedBy or b.owner
    -- whoever ran the machine is still around: leave it in there for them
    local owner = b.lastBy and Bridge.getSourceByIdentifier(b.lastBy)
    if owner then
        local ped = GetPlayerPed(owner)
        if ped ~= 0 and #(GetEntityCoords(ped) - vec3(st.x, st.y, st.z)) <= C.ownerRadius then return end
    end

    pal.batches[#pal.batches + 1] = b.id
    Batches.trail(b, ('Moved from %s to the pallet'):format(st.label))
    Batches.save(b)

    st.state, st.hasBatch, st.cut = 'idle', false, 0
    p.batch, p.settings, p.solvent, p.startedBy, p.doneAt = nil, nil, nil, nil, nil
    st.user, st.lockUntil = nil, nil
    Stations.commit(id)
    sync(pid)

    if owner then
        Bridge.notify(owner, 'Moved to the pallet', ('Nobody came for %s, so it was stacked on the pallet at %s.'):format(
            b.serial, Stations.list[pid].opLabel or 'the op'), 'info', 8000)
    end
end

-- Crew: load everything you can carry into the duffel
lib.callback.register('nzmw:pallet:take', function(src, id)
    local st, p, err = Stations.guard(src, id, { type = 'pallet', state = 'done' })
    if not st then return err end
    local taken, total = 0, 0
    local keep = {}
    local onlyMine = isOpen(st) and Bridge.getIdentifier(src)
    for _, bid in ipairs(p.batches) do
        local b = Batches.get(bid)
        if b then
            if onlyMine and holder(b) ~= onlyMine then
                keep[#keep + 1] = bid
            elseif Batches.giveItem(src, b, itemFor(b)) then
                Batches.trail(b, 'Loaded into a duffel by ' .. Bridge.getName(src))
                Batches.save(b)
                taken, total = taken + 1, total + b.amount
            else
                keep[#keep + 1] = bid
            end
        end
    end
    p.batches = keep
    sync(id)
    if taken == 0 then return Stations.fail(onlyMine and 'None of these loads are yours.' or 'Your bag is full.') end
    return { ok = true, taken = taken, total = total, left = #keep }
end)

-- Anyone without access: grab one load (slow, noisy)
lib.callback.register('nzmw:pallet:grab', function(src, id, phase)
    if not C.theft then return Stations.fail('Disabled.') end
    local st, p, err = Stations.guard(src, id, { type = 'pallet', state = 'done', access = false })
    if not st then return err end
    local open = isOpen(st)
    if not open and Stations.hasAccess(src, st) then return Stations.fail('It is yours — just load the bag.') end
    -- newest load that isn't the thief's own
    local me, target, idx = Bridge.getIdentifier(src), nil, nil
    for i = #p.batches, 1, -1 do
        local b = Batches.get(p.batches[i])
        if b and holder(b) ~= me then target, idx = p.batches[i], i break end
    end
    if not target then return Stations.fail('Nothing here that isn\'t yours.') end

    if phase == 'start' then
        if st.pryBy and st.pryBy ~= src then return Stations.fail('Someone is already on it.') end
        st.pryBy, st.pryAt, p.grabBatch = src, now(), target
        for _, owner in ipairs(ownersOf(p)) do
            if owner ~= src then
                Bridge.notify(owner, 'Pallet hit!', ('Someone is stuffing a bag at %s.'):format(st.opLabel or 'your pallet'), 'error', 9000)
            end
        end
        if math.random() < C.theftAlert then
            Stations.alert(st, 'Possible burglary', 'Caller saw someone hauling bags of cash out of a back room.', '10-31')
        end
        return { ok = true }
    end

    if st.pryBy ~= src or p.grabBatch ~= target or now() - (st.pryAt or 0) < math.floor(C.theftTime / 1000 * 0.8) then
        return Stations.fail('You were interrupted.')
    end
    st.pryBy, st.pryAt, p.grabBatch = nil, nil, nil
    local b = Batches.get(target)
    if not b then return Stations.fail('Nothing left.') end
    local item = itemFor(b)
    if not Batches.giveItem(src, b, item) then return Stations.fail('You cannot carry that.') end
    Batches.trail(b, 'Grabbed off the pallet')
    Batches.save(b)
    table.remove(p.batches, idx)
    sync(id)
    Bridge.log('Pallet robbed', { { 'Thief', Bridge.getName(src) .. ' (' .. src .. ')' }, { 'Victim', b.ownerName },
        { 'Serial', b.serial }, { 'Amount', NZ.money(b.amount) } })
    return { ok = true, item = item, amount = b.amount }
end)

-- Police: seize everything on the pallet
lib.callback.register('nzmw:pallet:seize', function(src, id)
    if not NZ.isPoliceJob(Bridge.getJob(src)) then return Stations.fail('Police only.') end
    local st, p, err = Stations.guard(src, id, { type = 'pallet', state = 'done', access = false })
    if not st then return err end
    local total, n = 0, 0
    for _, owner in ipairs(ownersOf(p)) do
        Bridge.notify(owner, 'Raided', ('Police seized the pallet at %s.'):format(st.opLabel or 'your op'), 'error', 10000)
    end
    for _, bid in ipairs(p.batches) do
        local b = Batches.get(bid)
        if b then total, n = total + b.amount, n + 1; Batches.remove(bid) end
    end
    p.batches = {}
    sync(id)
    Bridge.log('Pallet seized', { { 'Officer', Bridge.getName(src) }, { 'Loads', n }, { 'Cash', NZ.money(total) } })
    return { ok = true, seized = total, loads = n }
end)
