--[[ Cook the Books — declare washed stacks as front-business revenue.
     Suspicion → audits. Clearing house → delayed, full-rate bank deposits that an audit can freeze. ]]

Books = { fronts = {} }

local now = os.time
local B, A = Config.Books, Config.Audit

local function front(id)
    local f = NZ.findFront(id)
    if f and not Books.fronts[id] then Books.fronts[id] = { entries = {}, auditUntil = 0 } end
    return f, Books.fronts[id]
end

local function publishFronts()
    local pub = {}
    for id, s in pairs(Books.fronts) do pub[id] = { auditUntil = s.auditUntil } end
    GlobalState['nzmw:fronts'] = pub
end

local function prune(s)
    local cutoff, keep = now() - 86400, {}
    for _, e in ipairs(s.entries) do if e.t >= cutoff then keep[#keep + 1] = e end end
    s.entries = keep
end

local function stats(s)
    prune(s)
    local declared, flags = 0, 0
    for _, e in ipairs(s.entries) do
        declared = declared + e.amount
        if e.flagged then flags = flags + 1 end
    end
    return declared, flags
end

local function near(src, f)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - f.coords) <= (f.radius or 1.0) + 3.0
end

local function crewBonus(b, declarer)
    if not Config.Crew.enabled then return 0, 1 end
    local seen, n = {}, 0
    for _, cid in pairs(b.handlers or {}) do
        if cid and not seen[cid] then seen[cid] = true; n = n + 1 end
    end
    if declarer and not seen[declarer] then n = n + 1 end
    if now() - (b.createdAt or 0) > Config.Crew.windowMinutes * 60 then return 0, n end
    return math.min(Config.Crew.cap, Config.Crew.perMember * math.max(0, n - 1)), n
end

local function batchValue(b, rate, declarer)
    local crew, members = crewBonus(b, declarer)
    local heatCut = (b.heat / 100) * Config.Heat.payoutPenaltyMax
    local value = b.amount * rate * b.quality * (1 + crew) * (1 - heatCut)
    return math.floor(value), crew, members, heatCut
end

-- All final-stage batches the player is carrying (deduped)
local function carried(src)
    local out, seen = {}, {}
    for _, s in ipairs(Inv.batchSlots(src, NZ.finalItem())) do
        local b = Batches.get(s.metadata.batch)
        if b and not seen[b.id] and b.stage >= #NZ.pipeline() then
            seen[b.id] = true
            out[#out + 1] = { batch = b, slot = s.slot }
        end
    end
    return out
end

---------------------------------------------------------------------------------------------------
-- Audits
---------------------------------------------------------------------------------------------------
function Books.startAudit(frontId, reason)
    local f, s = front(frontId)
    if not f then return end
    s.auditUntil = now() + A.durationMin * 60
    publishFronts()

    local hit = MySQL.query.await('SELECT id, citizenid, amount FROM nzmw_clearing WHERE front = ? AND status = ?', { frontId, 'pending' }) or {}
    for _, row in ipairs(hit) do
        local seized = math.floor(row.amount * A.seizePct)
        MySQL.update.await('UPDATE nzmw_clearing SET amount = amount - ?, seized = seized + ? WHERE id = ?', { seized, seized, row.id })
        local target = Bridge.getSourceByIdentifier(row.citizenid)
        if target then
            Bridge.notify(target, 'Treasury audit', ('%s is being audited. %s of your clearing was frozen.'):format(f.label, NZ.money(seized)), 'error', 10000)
        end
    end

    if A.notifyJobs then
        Bridge.eachPlayer(function(src)
            local job = Bridge.getJob(src)
            if NZ.isAuditJob(job) or NZ.isPoliceJob(job) then
                Bridge.notify(src, 'Treasury flag', ('%s flagged for irregular revenue (%s). Books are open for inspection.'):format(f.label, reason or 'auto'), 'error', 10000)
            end
        end)
    end
    Bridge.log('Treasury audit', { { 'Front', f.label }, { 'Reason', reason or 'auto' }, { 'Clearings frozen', #hit } })
end

---------------------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------------------
lib.callback.register('nzmw:books:open', function(src, frontId)
    local f, s = front(frontId)
    if not f or not near(src, f) then return { ok = false, err = 'You are not at the office.' } end
    local declared, flags = stats(s)
    local rate = Market.rate
    local cid = Bridge.getIdentifier(src)

    local list = {}
    for _, c in ipairs(carried(src)) do
        local value, crew, members, heatCut = batchValue(c.batch, rate, cid)
        local sum = Batches.summary(c.batch)
        sum.value, sum.crew, sum.members, sum.heatCut = value, crew, members, NZ.round(heatCut, 3)
        list[#list + 1] = sum
    end

    local pending = MySQL.query.await('SELECT front, amount, seized, release_at FROM nzmw_clearing WHERE citizenid = ? AND status = ? ORDER BY release_at ASC LIMIT 8',
        { cid, 'pending' }) or {}

    return {
        ok = true,
        front = { id = f.id, label = f.label, sub = f.sub, dailyCap = f.dailyCap, categories = f.categories },
        declared = declared, flags = flags, auditUntil = s.auditUntil, now = now(),
        batches = list, pending = pending,
        market = GlobalState['nzmw:market'],
        rules = {
            instantFee = B.instantFee, clearingMinutes = B.clearingMinutes,
            wDeviation = B.wDeviation, wOverCap = B.wOverCap, wHeat = B.wHeat, wRecentFlags = B.wRecentFlags,
            auditBase = A.base, auditScale = A.scale, flagAt = A.flagAt,
        },
        name = Bridge.getName(src),
    }
end)

lib.callback.register('nzmw:books:submit', function(src, frontId, ids, alloc, mode)
    local f, s = front(frontId)
    if not f or not near(src, f) then return { ok = false, err = 'You are not at the office.' } end
    if s.auditUntil > now() then return { ok = false, err = 'The books are sealed — Treasury audit in progress.' } end
    if type(ids) ~= 'table' or #ids == 0 then return { ok = false, err = 'Select at least one batch.' } end
    if mode ~= 'instant' and mode ~= 'clearing' then mode = 'clearing' end

    -- allocation must cover 100% of the declared revenue
    local clean, sum = {}, 0
    for _, c in ipairs(f.categories) do
        local v = NZ.clamp(tonumber(type(alloc) == 'table' and alloc[c.key] or 0) or 0, 0, 1)
        clean[c.key], sum = v, sum + v
    end
    if math.abs(sum - 1.0) > 0.02 then return { ok = false, err = 'Your revenue lines must add up to 100%.' } end

    local cid = Bridge.getIdentifier(src)
    local have = {}
    for _, c in ipairs(carried(src)) do have[c.batch.id] = c end

    local picked, amount, heatSum = {}, 0, 0
    for _, id in ipairs(ids) do
        local c = have[id]
        if not c then return { ok = false, err = 'You are not carrying one of those batches.' } end
        picked[#picked + 1] = c
        amount = amount + c.batch.amount
        heatSum = heatSum + c.batch.heat * c.batch.amount
        have[id] = nil -- no duplicates
    end

    local declared, flags = stats(s)
    local heat = heatSum / math.max(1, amount)
    local suspicion = NZ.suspicion(f, clean, amount, declared, heat, flags)
    local flagged = suspicion >= A.flagAt
    local rate = Market.rate

    -- remove items first; hand back anything already taken if one removal fails
    local taken = {}
    for _, c in ipairs(picked) do
        if not Inv.remove(src, NZ.finalItem(), 1, c.slot) then
            for _, back in ipairs(taken) do Batches.giveItem(src, back.batch, NZ.finalItem()) end
            return { ok = false, err = 'Inventory error — try again.' }
        end
        taken[#taken + 1] = c
    end

    local payout, lines, serials, crewMax = 0, {}, {}, 0
    for _, c in ipairs(picked) do
        local value, crew = batchValue(c.batch, rate, cid)
        payout = payout + value
        crewMax = math.max(crewMax, crew)
        lines[#lines + 1] = { serial = c.batch.serial, amount = c.batch.amount, value = value }
        serials[#serials + 1] = c.batch.serial
        Batches.remove(c.batch.id)
    end

    local releaseAt
    if mode == 'instant' then
        payout = math.floor(payout * (1 - B.instantFee))
        Bridge.addMoney(src, B.instantAccount, payout, 'nz_moneywash instant')
    else
        releaseAt = now() + B.clearingMinutes * 60
        MySQL.insert.await('INSERT INTO nzmw_clearing (citizenid, front, amount, release_at) VALUES (?, ?, ?, ?)',
            { cid, f.id, payout, releaseAt })
    end

    local name = Bridge.getName(src)
    MySQL.insert('INSERT INTO nzmw_ledger (front, citizenid, name, amount, payout, allocation, suspicion, flagged, serials, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { f.id, cid, name, amount, payout, json.encode(clean), suspicion, flagged and 1 or 0, table.concat(serials, ','), now() })
    s.entries[#s.entries + 1] = { t = now(), amount = amount, flagged = flagged }
    Market.addVolume(amount)

    local audited = math.random() < NZ.auditChance(suspicion)

    Bridge.log('Books cooked', {
        { 'Player', name .. ' (' .. src .. ')' }, { 'Front', f.label }, { 'Declared', NZ.money(amount) },
        { 'Payout', NZ.money(payout) .. ' · ' .. mode }, { 'Suspicion', ('%d%%'):format(math.floor(suspicion * 100)) },
        { 'Audit', audited and 'YES' or 'no' },
    })

    if audited then
        -- let the receipt land first so the player sees what happened
        SetTimeout(4000, function() Books.startAudit(f.id, ('suspicion %d%%'):format(math.floor(suspicion * 100))) end)
    end

    return {
        ok = true, mode = mode, payout = payout, releaseAt = releaseAt, now = now(), lines = lines,
        suspicion = suspicion, flagged = flagged, audited = audited, crew = crewMax, rate = rate,
    }
end)

lib.callback.register('nzmw:audit:open', function(src, frontId)
    local f, s = front(frontId)
    if not f or not near(src, f) then return { ok = false, err = 'You are not at the office.' } end
    if not NZ.isAuditJob(Bridge.getJob(src)) then return { ok = false, err = 'You have no authority here.' } end
    local rows = MySQL.query.await('SELECT id, name, amount, allocation, suspicion, flagged, serials, created_at FROM nzmw_ledger WHERE front = ? AND created_at > ? ORDER BY created_at DESC LIMIT 60',
        { f.id, now() - 172800 }) or {}
    for _, r in ipairs(rows) do
        -- the signature on clean entries is a scrawl; flagged entries were pulled for review
        if r.flagged ~= 1 and r.flagged ~= true then
            local a, b = (r.name or ''):match('^(%S)%S*%s+(%S)')
            r.name = a and (a .. '. ' .. b .. '.') or '—'
        end
        r.allocation = json.decode(r.allocation or '{}')
    end
    local declared, flags = stats(s)
    return {
        ok = true, front = { id = f.id, label = f.label, sub = f.sub, dailyCap = f.dailyCap, categories = f.categories },
        rows = rows, declared = declared, flags = flags, auditUntil = s.auditUntil, now = now(),
    }
end)

lib.callback.register('nzmw:audit:start', function(src, frontId)
    local f, s = front(frontId)
    if not f or not near(src, f) then return { ok = false, err = 'You are not at the office.' } end
    if not NZ.isAuditJob(Bridge.getJob(src)) then return { ok = false, err = 'You have no authority here.' } end
    if s.auditUntil > now() then return { ok = false, err = 'Already under audit.' } end
    Books.startAudit(f.id, 'ordered by ' .. Bridge.getName(src))
    return { ok = true, auditUntil = s.auditUntil }
end)

---------------------------------------------------------------------------------------------------
-- Boot + clearing house
---------------------------------------------------------------------------------------------------
function Books.start()
    for _, f in ipairs(Config.Fronts) do front(f.id) end
    local rows = MySQL.query.await('SELECT front, amount, flagged, created_at FROM nzmw_ledger WHERE created_at > ?', { now() - 86400 }) or {}
    for _, r in ipairs(rows) do
        local _, s = front(r.front)
        if s then s.entries[#s.entries + 1] = { t = r.created_at, amount = r.amount, flagged = r.flagged == 1 or r.flagged == true } end
    end
    publishFronts()

    CreateThread(function()
        while true do
            Wait(B.clearingTick * 1000)
            local due = MySQL.query.await('SELECT id, citizenid, front, amount, seized FROM nzmw_clearing WHERE status = ? AND release_at <= ? LIMIT 50',
                { 'pending', now() }) or {}
            for _, row in ipairs(due) do
                local target = Bridge.getSourceByIdentifier(row.citizenid)
                if target then
                    local changed = MySQL.update.await('UPDATE nzmw_clearing SET status = ? WHERE id = ? AND status = ?', { 'paid', row.id, 'pending' })
                    if changed and changed > 0 and row.amount > 0 then
                        Bridge.addMoney(target, B.clearingAccount, row.amount, 'nz_moneywash clearing')
                        local f = NZ.findFront(row.front)
                        Bridge.notify(target, 'Deposit cleared', ('%s from %s landed in your account.%s'):format(
                            NZ.money(row.amount), f and f.label or 'a front',
                            row.seized > 0 and (' (' .. NZ.money(row.seized) .. ' frozen by audit)') or ''), 'success', 8000)
                    end
                end
            end
            -- audits expiring → republish so clients reopen the books
            local changed = false
            for _, s in pairs(Books.fronts) do
                if s.auditUntil ~= 0 and s.auditUntil <= now() then s.auditUntil = 0; changed = true end
            end
            if changed then publishFronts() end
        end
    end)
end
