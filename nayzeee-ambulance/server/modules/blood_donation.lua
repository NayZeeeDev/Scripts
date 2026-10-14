--[[
    NAYZEEE AMBULANCE - Blood donation (server)

    Point type 'donation' (chair + collection mixer). A player sits in the chair; then either
    the donor runs the donation alone (self-service) or a medic with Config.Blood.Donation.perm
    draws it ("Draw blood" on the chair) - Config.Blood.Donation.mode = 'self' | 'medic' | 'both'.

    Procedure (NZA.Proc): 'donation'   target = the seated donor (player), payload { point }
        onStart   chair + seat + eligibility (alive, blood volume, pain, no open injuries,
                  cooldown days) + mode / permission → data for the minigame
        onFinish  collected mL (client value clamped by elapsed time and the bag size; easy
                  mode = a full unit) → AddBlood(-mL) to the donor, a labelled unit
                  (NZA.Blood.CreateBag, donor's blood group) into the bank / donor / collector,
                  reward, cooldown, weakness, the donor's blood group goes on record
        onAbort   blood already drawn is lost (AddBlood(-mL), no unit)

    Chair state is replicated to every client in GlobalState.nzaBloodChairs:
        { ['<pointId>'] = { d = donor src, m = runner src | nil, a = active, ml, t = target mL,
                            s = bag size, done = bool, bt = group (after a finished donation) } }

    Callbacks: nza:blood:donation:check (pointId) → { ok, eligible, reason, msg, mode, ... }
               nza:blood:donation:sit (pointId) → { ok, mode, msg }
               nza:blood:me () → { weakUntil, count, last, next }
    Net events: C→S nza:blood:donation:leave (pointId)
                C→S nza:blood:donation:progress (pointId, ml)     (runner, ≤ 5/s)
                S→C nza:blood:weak (seconds)                      donor weakness after donating
                S→C nza:blood:donation:stood (pointId)            server freed the seat (donor stands up)
    Bus (server): blood:donated (src, p, ml, meta|nil)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local Core = NZA.Core
local U = NZA.Util

local DAY = 86400

local function dc() return (Config.Blood or {}).Donation or {} end
local function bags() return (Config.Blood or {}).Bags or {} end
local function L(key, ...) return NZA.L('blood.' .. key, ...) end

local chairs = {}     -- [pointId] = { id, donor, runner, medic, token, ml, done, bt, since }
local donors = {}     -- [identifier] = { last, count, weakUntil }

-- ════════════════════════════════════════════════════════════════════════
-- CHAIR STATE
-- ════════════════════════════════════════════════════════════════════════

local function publish()
    local out = {}
    for id, c in pairs(chairs) do
        out[tostring(id)] = {
            d = c.donor, m = c.runner, a = c.token ~= nil, ml = math.floor(c.ml or 0),
            t = tonumber(bags().ml) or 450, s = tonumber(bags().bagSize) or 500, done = c.done == true, bt = c.bt,
        }
    end
    GlobalState.nzaBloodChairs = out
end

local publishQueued = false
local function publishSoon()
    if publishQueued then return end
    publishQueued = true
    SetTimeout(350, function()
        publishQueued = false
        publish()
    end)
end

local function chairOf(src)
    for id, c in pairs(chairs) do
        if c.donor == src then return id, c end
    end
    return nil
end

local function freeChair(id, notify)
    local c = chairs[id]
    if not c then return end
    if c.token and NZA.Proc and NZA.Proc.Abort then pcall(NZA.Proc.Abort, c.token, 'cancelled') end
    chairs[id] = nil
    if notify and c.donor and GetPlayerName(c.donor) then TriggerClientEvent('nza:blood:donation:stood', c.donor, id) end
    publish()
end

local function chairPoint(pointId)
    if not (NZA.Hospitals and NZA.Hospitals.Point) then return nil end
    local pt = NZA.Hospitals.Point(pointId)
    if not pt or pt.type ~= 'donation' then return nil end
    return pt
end

local function pointPos(pt)
    local c = pt and pt.coords
    if not c then return nil end
    return vector3(c.x, c.y, c.z)
end

local function nearPoint(src, pt, reach)
    local pos, me = pointPos(pt), Core.SrcCoords(src)
    return pos ~= nil and me ~= nil and #(me - pos) <= reach
end

-- ════════════════════════════════════════════════════════════════════════
-- DONORS (cooldown, count, weakness)
-- ════════════════════════════════════════════════════════════════════════

local function donorRec(identifier)
    if not identifier then return { last = 0, count = 0, weakUntil = 0 } end
    local r = donors[identifier]
    if r then return r end
    r = { last = 0, count = 0, weakUntil = 0 }
    local rows = B.Query and B.Query('SELECT `last`, `count`, `weak_until` FROM `nza_blood_donors` WHERE `identifier` = ?', { identifier }) or nil
    if rows and rows[1] then
        r.last = tonumber(rows[1].last) or 0
        r.count = tonumber(rows[1].count) or 0
        r.weakUntil = tonumber(rows[1].weak_until) or 0
    end
    donors[identifier] = r
    return r
end

local function saveDonor(identifier, r)
    if not identifier or not B.Exec then return end
    B.Exec('INSERT INTO `nza_blood_donors` (`identifier`, `last`, `count`, `weak_until`) VALUES (?, ?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `last` = VALUES(`last`), `count` = VALUES(`count`), `weak_until` = VALUES(`weak_until`)',
        { identifier, r.last, r.count, r.weakUntil })
end

local function waitText(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= DAY then return L('wait_days', math.floor(sec / DAY), math.floor((sec % DAY) / 3600)) end
    if sec >= 3600 then return L('wait_hours', math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
    return L('wait_minutes', math.max(1, math.floor(sec / 60)))
end

-- → ok, reasonKey, message
local function eligible(src)
    local p = NZA.Patients.GetBySource(src)
    if not p then return false, 'no_patient', L('err_no_patient') end
    if p.state ~= 'alive' then return false, 'down', L('elig_down') end
    local d = dc()
    local bmax = tonumber(p.bloodMax) or 5000
    if (tonumber(p.blood) or bmax) < bmax * (tonumber(d.minBloodPct) or 0.95) then
        return false, 'low_blood', L('elig_low_blood')
    end
    if (tonumber(p.pain) or 0) > (tonumber(d.maxPain) or 25) then return false, 'pain', L('elig_pain') end
    if d.noInjuries ~= false then
        for _, inj in pairs(p.injuries or {}) do
            if inj.status == 'open' or (tonumber(inj.bleed) or 0) > 0.2 then return false, 'injured', L('elig_injured') end
        end
    end
    for _, inf in ipairs(p.infusions or {}) do
        if (inf.left or 0) > 0 then return false, 'infusion', L('elig_infusion') end
    end
    local rec = donorRec(p.identifier)
    local wait = rec.last + (tonumber(d.cooldownDays) or 3) * DAY - os.time()
    if rec.last > 0 and wait > 0 then return false, 'cooldown', L('elig_cooldown', waitText(wait)) end
    return true, nil, nil, p, rec
end
B.DonorEligible = eligible

local function modeAllows(isSelf)
    local mode = dc().mode or 'both'
    if isSelf then return mode == 'self' or mode == 'both' end
    return mode == 'medic' or mode == 'both'
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:blood:donation:check', function(src, pointId)
    if not Core.Rate('blood:don', src, 6, 4000) then return { ok = false, msg = L('err_rate') } end
    if dc().enabled == false then return { ok = false, msg = L('err_disabled') } end
    local pt = chairPoint(pointId)
    if not pt then return { ok = false, msg = L('err_no_point') } end
    local ok, reason, msg, _, rec = eligible(src)
    local c = chairs[pt.id]
    return {
        ok = true, eligible = ok, reason = reason, msg = msg, mode = dc().mode or 'both',
        taken = c ~= nil and c.donor ~= src, count = rec and rec.count or 0,
    }
end)

lib.callback.register('nza:blood:donation:sit', function(src, pointId)
    if not Core.Rate('blood:don', src, 6, 4000) then return { ok = false, msg = L('err_rate') } end
    if dc().enabled == false then return { ok = false, msg = L('err_disabled') } end
    local pt = chairPoint(pointId)
    if not pt then return { ok = false, msg = L('err_no_point') } end
    if not nearPoint(src, pt, 3.5) then return { ok = false, msg = L('err_too_far') } end
    local c = chairs[pt.id]
    if c and c.donor ~= src then
        if c.donor and GetPlayerName(c.donor) then return { ok = false, msg = L('err_taken') } end
        chairs[pt.id] = nil
    end
    local mine = chairOf(src)
    if mine and mine ~= pt.id then freeChair(mine, false) end
    local ok, _, msg = eligible(src)
    if not ok then return { ok = false, msg = msg } end
    chairs[pt.id] = { id = pt.id, donor = src, since = os.time(), ml = 0 }
    publish()
    return { ok = true, mode = dc().mode or 'both' }
end)

RegisterNetEvent('nza:blood:donation:leave', function(pointId)
    local src = tonumber(source)
    if not src or not Core.Rate('blood:leave', src, 4, 3000) then return end
    local id = chairOf(src)
    if not id then return end
    if pointId ~= nil and tostring(pointId) ~= tostring(id) then return end
    freeChair(id, false)
end)

RegisterNetEvent('nza:blood:donation:progress', function(pointId, ml)
    local src = tonumber(source)
    if not src or not Core.Rate('blood:prog', src, 6, 1000) then return end
    local c = chairs[tonumber(pointId) or pointId]
    if not c or c.runner ~= src or not c.token then return end
    local s = NZA.Proc.Session and NZA.Proc.Session(c.token) or nil
    if not s then return end
    local elapsed = (GetGameTimer() - (s.startedAt or GetGameTimer())) / 1000
    local cap = math.max(0, elapsed - 2) * (tonumber((dc().flow or {}).maxFlow) or 14) * 1.15
    local target = tonumber(bags().ml) or 450
    ml = U.clamp(tonumber(ml) or 0, 0, math.min(cap, target))
    if ml > (c.ml or 0) then
        c.ml = ml
        publishSoon()
    end
end)

lib.callback.register('nza:blood:me', function(src)
    if not Core.Rate('blood:me', src, 3, 5000) then return nil end
    local id = Core.Identifier(src)
    local r = donorRec(id)
    local nextAt = r.last > 0 and (r.last + (tonumber(dc().cooldownDays) or 3) * DAY) or 0
    return { weakUntil = r.weakUntil, count = r.count, last = r.last, next = nextAt, now = os.time() }
end)

-- ════════════════════════════════════════════════════════════════════════
-- PROCEDURE
-- ════════════════════════════════════════════════════════════════════════

local function itemsFor(isSelf)
    local map = isSelf and (dc().selfItems or {}) or (dc().items or {})
    return B.Items and B.Items(map) or {}
end

local function giveReward(src, p, ml, medicSrc)
    local r = dc().reward or {}
    local money = math.floor(tonumber(r.money) or 0)
    if money > 0 and p.src then
        Core.B('AddMoney', p.src, r.account or 'bank', money, L('reward_reason'))
    end
    for key, n in pairs(r.items or {}) do
        local name = B.ItemName(key)
        if name and (tonumber(n) or 0) > 0 and p.src then Core.B('Inv.AddItem', p.src, name, math.floor(n)) end
    end
    local pay = math.floor(tonumber(r.medicPay) or 0)
    if medicSrc and pay > 0 then
        Core.B('AddMoney', medicSrc, r.account or 'bank', pay, L('reward_medic_reason'))
    end
    return money
end

NZA.Proc.Register('donation', {
    label = L('proc_label'),
    perm = nil, self = true, player = true, npc = false,
    states = { alive = true },
    maxDist = 3.5,
    minTime = tonumber(dc().minTime) or 30,
    maxTime = tonumber(dc().maxTime) or 600,
    easyTime = tonumber(dc().easyTime) or 10,
    consume = 'finish',
    items = function(src, p)
        return itemsFor(p and p.src == src)
    end,
    onStart = function(src, p, payload, info)
        if dc().enabled == false then return false, { err = 'disabled', msg = L('err_disabled') } end
        local pointId = type(payload) == 'table' and (tonumber(payload.point) or payload.point) or nil
        local pt = pointId and chairPoint(pointId) or nil
        if not pt then return false, { err = 'no_point', msg = L('err_no_point') } end
        local c = chairs[pt.id]
        if not c or c.donor ~= p.src then return false, { err = 'not_seated', msg = L('err_not_seated') } end
        if c.token then return false, { err = 'busy', msg = L('err_busy_chair') } end
        if c.done then return false, { err = 'done', msg = L('err_done_chair') } end
        local isSelf = p.src == src
        if not modeAllows(isSelf) then
            return false, { err = 'mode', msg = isSelf and L('err_mode_medic') or L('err_mode_self') }
        end
        if not isSelf and not NZA.Staff.Can(src, dc().perm or 'blood') then
            return false, { err = 'no_perm', msg = L('err_no_perm') }
        end
        if not nearPoint(src, pt, 4.0) then return false, { err = 'too_far', msg = L('err_too_far') } end
        local ok, _, msg, _, rec = eligible(p.src)
        if not ok then return false, { err = 'ineligible', msg = msg } end
        local v = p.vitals or {}
        local data = {
            point = pt.id, self = isSelf, name = p.name, count = rec and rec.count or 0,
            bpm = math.floor(U.clamp(tonumber(v.hr) or 72, 50, 130)),
            target = tonumber(bags().ml) or 450, bagSize = tonumber(bags().bagSize) or 500,
            flow = dc().flow or {}, minTime = tonumber(dc().minTime) or 30,
            typed = (rec and rec.count or 0) > 0 or B.IsTyped(p),
        }
        if data.typed then data.bloodType = p.bloodType end
        return true, data
    end,
    onFinish = function(src, p, session, result)
        local pointId = session.data and session.data.point
        local c = pointId and chairs[pointId] or nil
        local target = tonumber(bags().ml) or 450
        local ml
        if session.easy or result.easy then
            ml = target
        else
            local elapsed = tonumber(session.elapsed) or 0
            local cap = math.max(0, elapsed - 2) * (tonumber((dc().flow or {}).maxFlow) or 14) * 1.15
            ml = U.clamp(tonumber(result.ml) or 0, 0, math.min(target, cap))
        end
        ml = math.floor(ml + 0.5)
        local isSelf = p.src == src
        NZA.Patients.AddBlood(p.pid, -ml)
        NZA.Patients.SetMeta(p.pid, 'bloodTyped', true)

        local usable = ml >= (tonumber(dc().minUsable) or 300)
        local meta, dest = nil, nil
        if usable then
            local pt = chairPoint(pointId)
            local bankKey = B.BankKey(pt)
            local how = dc().bagTo or 'bank'
            local base = { type = p.bloodType, ml = ml, donor = p.name, donorId = p.identifier }
            if how == 'donor' or how == 'collector' then
                meta = B.CreateBag(base)
                local to = how == 'donor' and p.src or src
                if B.GiveBag(to, meta) then
                    dest = how
                else
                    B.SetUsed(meta.serial, 0, bankKey)
                    B.AddToBank(bankKey, meta, p.name)
                    dest = 'bank'
                end
            else
                base.bank = bankKey
                meta = B.CreateBag(base)
                B.Log(bankKey, 'donated', meta, p.name)
                dest = 'bank'
            end
        end

        -- donor record: cooldown, count, weakness
        local rec = donorRec(p.identifier)
        local now = os.time()
        local w = dc().weakness or {}
        local weakSec = math.floor((tonumber(w.minutes) or 8) * 60 * U.clamp(ml / target, 0.3, 1.0))
        rec.last = now
        rec.count = rec.count + (usable and 1 or 0)
        rec.weakUntil = now + weakSec
        saveDonor(p.identifier, rec)
        if p.src then TriggerClientEvent('nza:blood:weak', p.src, weakSec) end

        local paid = usable and giveReward(src, p, ml, (not isSelf) and src or nil) or 0
        if c then
            c.token, c.runner = nil, nil
            c.done = true
            c.ml = ml
            c.bt = p.bloodType
            publish()
        end
        if p.src and not isSelf then
            Core.Notify(p.src, {
                title = L('don_title'),
                message = usable and L('don_thanks_donor', ml, p.bloodType or '?') or L('don_short_donor', ml),
                type = usable and 'success' or 'warning', duration = 9000,
            })
        end
        if usable and paid > 0 and p.src then
            Core.Notify(p.src, { title = L('don_title'), message = L('don_paid', paid), type = 'success' })
        end
        NZA.Bus.Emit('blood:donated', src, p, ml, meta)
        local msgKey = usable and (dest == 'bank' and 'ok_don_bank' or 'ok_don_item') or 'ok_don_short'
        return {
            ml = ml, usable = usable, serial = meta and meta.serial or nil, bloodType = p.bloodType, dest = dest,
            count = rec.count, label = meta,
            msg = L(msgKey, ml, p.bloodType or '?'),
            record = L('rec_donation', ml, p.bloodType or '?'),
        }
    end,
    onAbort = function(src, p, session, reason)
        local pointId = session.data and session.data.point
        local c = pointId and chairs[pointId] or nil
        if c then
            local drawn = math.floor(tonumber(c.ml) or 0)
            if drawn > 0 and p then
                NZA.Patients.AddBlood(p.pid, -drawn)
                if p.src then
                    Core.Notify(p.src, { title = L('don_title'), message = L('don_aborted_donor', drawn), type = 'warning' })
                end
            end
            c.token, c.runner = nil, nil
            c.ml = 0
            publish()
        end
    end,
})

-- remember the session token on the chair (the proc callback returns it to the runner only)
NZA.Bus.On('proc:started', function(src, p, name, session)
    if name ~= 'donation' or not session or not session.data then return end
    local c = chairs[session.data.point]
    if not c then return end
    c.token = session.token
    c.runner = src
    c.ml = 0
    c.done = false
    publish()
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    for id, c in pairs(chairs) do
        if c.donor == src or c.runner == src then
            if c.donor == src then
                chairs[id] = nil
            else
                c.token, c.runner = nil, nil
            end
        end
    end
    publish()
end)

NZA.Bus.On('state:changed', function(p, old, new)
    if new == 'alive' or not p or not p.src then return end
    local id = chairOf(p.src)
    if id then freeChair(id, true) end
end)

-- a seat nobody uses for a long time is freed (donor walked off without the event)
CreateThread(function()
    while true do
        Wait(15000)
        local changed = false
        for id, c in pairs(chairs) do
            local pt = chairPoint(id)
            local gone = not c.donor or not GetPlayerName(c.donor)
            local far = not gone and pt and not nearPoint(c.donor, pt, 6.0)
            if gone or (far and not c.token) or not pt then
                chairs[id] = nil
                changed = true
            end
        end
        if changed then publish() end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then GlobalState.nzaBloodChairs = {} end
end)
