-- Snatch requests, the minigames (server-authoritative rope) and stealing your wig back

Clash = {}
StealBack = {}

local active  = {}  -- [id] = clash
local bySrc   = {}  -- [src] = id
local queries = {}  -- [token] = { p = promise, src = n }
local requesting = {}
local seq, qseq, rotate = 0, 0, 0

local CC = Config.Clash
local SEQ_KEYS = { 'U', 'D', 'L', 'R' }

local function now() return os.time() end

-- victim hair query ------------------------------------------------------------------------

local function int(v, lo, hi)
    v = math.floor(tonumber(v) or 0)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function queryHair(target, timeout)
    qseq = qseq + 1
    local token = qseq
    local p = promise.new()
    queries[token] = { p = p, src = target }
    TriggerClientEvent('nz-wig:c:query', target, token)
    SetTimeout(timeout or 2500, function()
        if queries[token] then
            queries[token] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end
Clash.QueryHair = queryHair

RegisterNetEvent('nz-wig:s:queryReply', function(token, data)
    local q = queries[token]
    if not q or q.src ~= source then return end
    queries[token] = nil
    if type(data) ~= 'table' then return q.p:resolve(nil) end
    q.p:resolve({
        d = int(data.d, 0, 1000), t = int(data.t, 0, 64), c = int(data.c, 0, 63), h = int(data.h, 0, 63),
        bv = int(data.bv, 0, 255), fv = int(data.fv, 0, 255),
        restrained = data.restrained == true, handsUp = data.handsUp == true, downed = data.downed == true,
    })
end)

-- steal back ----------------------------------------------------------------------------------
-- records[victimIdentifier][serial] = { from = identifier, fromName, untilAt }

local records = {}

function StealBack.Add(victim, snatcher, serial)
    if not Config.StealBack.Enabled or not serial or serial == 'GEN' then return end
    records[victim.id] = records[victim.id] or {}
    records[victim.id][serial] = { from = snatcher.id, fromName = snatcher.name, untilAt = now() + Config.StealBack.Window }
    local back = ById[snatcher.id]
    SetTimeout(Config.StealBack.Window * 1000 + 1000, function()
        local list = records[victim.id]
        if list and list[serial] and list[serial].untilAt <= now() then
            list[serial] = nil
            local vs = ById[victim.id]
            if vs and Players[vs] then SyncP(Players[vs]) end
        end
    end)
    return back
end

function StealBack.Remove(victimId, serial)
    local list = records[victimId]
    if list then list[serial] = nil end
end

-- which of my lost wigs does `holder` have right now? (pockets or head)
function StealBack.Find(A, holder)
    local list = records[A.id]
    if not list then return nil end
    local t = now()
    for serial, r in pairs(list) do
        if r.untilAt > t then
            if holder.hair.wig and holder.hair.wig.serial == serial then return serial, 'worn' end
            if Wigs.Find(holder.src, serial) then return serial, 'pocket' end
        end
    end
end

-- online players I can steal back from (the original snatchers), for the target label
function StealBack.TargetsFor(P)
    local out, list, t = {}, records[P.id], now()
    if not list then return out end
    for _, r in pairs(list) do
        local s = ById[r.from]
        if s and r.untilAt > t then out[#out + 1] = s end
    end
    return out
end

-- helpers ------------------------------------------------------------------------------------

local function release(...)
    for _, src in ipairs({ ... }) do
        local P = Players[src]
        if P then SetBusy(P, false) end
        bySrc[src] = nil
    end
end

local function computeLuck(A, V, revenge, bountyOpen)
    local perks = GetPerks(A.row.xp)
    local luck = perks.luck + math.min(Config.XP.StreakCap, A.row.streak) * Config.Luck.PerStreak
    if Hair.IsGlued(V) then luck = luck + Config.Luck.Glued end
    if bountyOpen then luck = luck + Config.Luck.Bounty end
    if revenge then luck = luck + Config.Luck.Revenge end
    return math.min(Config.Luck.Max, luck)
end

local function pickGame()
    if Config.Minigames[CC.Mode] then return CC.Mode end
    local pool = {}
    for _, g in ipairs(CC.Games) do
        if Config.Minigames[g] then pool[#pool + 1] = g end
    end
    if #pool == 0 then return 'clash' end
    if CC.Mode == 'rotate' then
        rotate = rotate % #pool + 1
        return pool[rotate]
    end
    return pool[math.random(1, #pool)]
end

local function newSequence(len)
    local out = {}
    for i = 1, len do out[i] = SEQ_KEYS[math.random(1, #SEQ_KEYS)] end
    return out
end

-- the server half and the UI half of one player's minigame settings
local function sideFor(game, role, perks, glued)
    local G = Config.Minigames[game]
    local victimGlue = glued and role == 'victim'
    local zoneMod = perks.zone + (glued and (role == 'victim' and Config.Glue.ZoneBonus or -Config.Glue.SnatcherZonePenalty) or 0)
    local s = {
        push = G.Push[role] * (victimGlue and Config.Glue.PushMultiplier or 1.0),
        interval = G.MinHitInterval or 150,
        last = 0, lock = 0, hits = 0,
    }
    local ui = { game = game }
    if game == 'clash' then
        ui.zone, ui.speed = Clamp(G.Zone[role] + zoneMod, 0.05, 0.6), G.Speed[role]
    elseif game == 'circle' then
        ui.arc, ui.speed = Clamp(G.Arc[role] + zoneMod, 0.05, 0.5), G.Speed[role]
    elseif game == 'balance' then
        ui.zone, ui.tick = Clamp(G.Zone[role] + zoneMod, 0.08, 0.6), G.Tick
    elseif game == 'sequence' then
        s.bonus = G.Bonus[role] * (victimGlue and Config.Glue.PushMultiplier or 1.0)
        s.len = G.Length or 5
        s.seq = newSequence(s.len)
        s.idx = 1
        ui.seq = s.seq
    end
    return s, ui
end

-- request ----------------------------------------------------------------------------------------

RegisterNetEvent('nz-wig:s:snatch', function(target)
    local src = source
    target = tonumber(target)
    local A = GetP(src)
    if not A or requesting[src] then return end
    local V = target and GetP(target)
    if not V or V == A then return Notify(src, L('no_one_close'), 'error') end

    local ok, key, extra = CanAttack(A, { cooldown = true })
    if not ok then return AttackError(src, key, extra) end
    if not Config.Snatch.AllowInVehicle and (InVehicle(src) or InVehicle(target)) then return Notify(src, L('in_vehicle'), 'error') end
    if PedDistance(src, target) > Config.Snatch.Distance + 1.0 then return Notify(src, L('no_one_close'), 'error') end

    local vModel = Hair.PedModelKey(target)
    if not vModel or not ModelEnabled(vModel) then return Notify(src, L('wrong_model'), 'error') end

    -- getting your own wig back skips the "they just lost their hair" immunity
    local steal, stealWhere = StealBack.Find(A, V)
    local okT, keyT = CanBeTarget(V, { ignoreImmune = steal ~= nil })
    if not okT then return Notify(src, L(keyT), 'error') end

    local layer = Hair.Layer(V)
    if layer == 'bald' and not steal then return Notify(src, L('already_bald'), 'error') end

    requesting[src] = true
    SetBusy(A, true)
    SetBusy(V, true)
    local q = queryHair(target, 2500)
    requesting[src] = nil

    -- either player may have left while we waited
    if Players[src] ~= A or Players[target] ~= V then return release(src, target) end
    if not q then release(src, target) return Notify(src, L('invalid'), 'error') end

    local downed = q.downed or StateFlag(target, Config.DownedStates)
    local restrained = q.restrained or q.handsUp or StateFlag(target, Config.RestrainedStates)
    if downed and not Config.Snatch.AllowDowned and not restrained then
        release(src, target)
        return Notify(src, L('cant_snatch'), 'error')
    end

    local hair
    if steal then
        hair = nil
    elseif layer == 'wig' then
        hair = V.hair.wig.hair
    else
        local d, t = q.d, q.t
        if V.hair.cut then d, t = V.hair.cut.d, V.hair.cut.t end
        if IsBaldDrawable(vModel, d) then
            release(src, target)
            return Notify(src, L('already_bald'), 'error')
        end
        hair = { m = vModel, d = d, t = t, c = q.c, h = q.h }
    end

    if not steal and not Wigs.CanCarry(src, layer == 'wig' and V.hair.wig or { tier = 'common' }) then
        release(src, target)
        return Notify(src, L('pockets_full'), 'error')
    end

    StartCooldown(A)
    EndNewPlayer(A)
    SyncP(A)

    local c = {
        a = src, v = target, layer = layer, hair = hair, model = vModel,
        steal = steal, stealWhere = stealWhere,
        blind = CC.Blindside.Enabled and IsBehindSrc(src, target, CC.Blindside.Angle),
        glued = Hair.IsGlued(V),
    }

    if not CC.Enabled or downed or (restrained and CC.SkipIfRestrained) then
        c.skipped = true
        c.p = CC.WinAt
        return Clash.Resolve(c, true)
    end
    Clash.Start(c)
end)

-- the minigame -------------------------------------------------------------------------------------

function Clash.Start(c)
    local A, V = Players[c.a], Players[c.v]
    seq = seq + 1
    c.id = seq
    c.game = pickGame()
    c.p = c.blind and CC.Blindside.Start or 0
    c.endsAt = GetGameTimer() + CC.Duration

    local uiA, uiV
    c.sa, uiA = sideFor(c.game, 'snatcher', GetPerks(A.row.xp), c.glued)
    c.sv, uiV = sideFor(c.game, 'victim', GetPerks(V.row.xp), c.glued)

    active[c.id] = c
    bySrc[c.a], bySrc[c.v] = c.id, c.id

    local G = Config.Minigames[c.game]
    local function payload(ui, role, me, opp, oppSrc)
        ui.id, ui.duration, ui.winAt, ui.p = c.id, CC.Duration, CC.WinAt, c.p
        ui.lockout, ui.blind, ui.glued, ui.layer = CC.MissLockout, c.blind, c.glued, c.layer
        ui.steal = c.steal ~= nil
        ui.role, ui.me, ui.opp, ui.oppSrc = role, me, opp, oppSrc
        ui.label, ui.icon = G.Label, G.Icon
        return ui
    end

    TriggerClientEvent('nz-wig:c:clashStart', c.a, payload(uiA, 'snatcher', A.name, V.name, c.v))
    TriggerClientEvent('nz-wig:c:clashStart', c.v, payload(uiV, 'victim', V.name, A.name, c.a))

    local id = c.id
    SetTimeout(CC.Duration + 300, function()
        if active[id] == c and not c.done then Clash.Finish(c, 'time') end
    end)
end

RegisterNetEvent('nz-wig:s:clashHit', function(id, token)
    local src = source
    local c = active[tonumber(id) or -1]
    if not c or c.done then return end
    local t = GetGameTimer()
    if t > c.endsAt + 200 then return end

    local s, dir
    if src == c.a then s, dir = c.sa, 1
    elseif src == c.v then s, dir = c.sv, -1
    else return end

    if t < s.lock or t - s.last < s.interval then return end

    local delta
    if c.game == 'mash' then
        -- must alternate left / right, holding one key does nothing
        if (token ~= 'L' and token ~= 'R') or token == s.lastTok then return end
        s.lastTok = token
        delta = s.push
    elseif c.game == 'sequence' then
        if type(token) ~= 'string' then return end
        if token ~= s.seq[s.idx] then
            s.lock, s.last, s.idx = t + CC.MissLockout, t, 1
            TriggerClientEvent('nz-wig:c:clashSeq', src, { seq = s.seq, idx = 1, miss = true })
            return
        end
        s.idx = s.idx + 1
        delta = s.push
        if s.idx > #s.seq then
            delta = delta + s.bonus
            s.seq, s.idx = newSequence(s.len), 1
            TriggerClientEvent('nz-wig:c:clashSeq', src, { seq = s.seq, idx = 1, done = true })
        end
    else
        delta = s.push
    end

    s.last, s.hits = t, s.hits + 1
    c.p = Clamp(c.p + delta * dir, -CC.WinAt, CC.WinAt)

    local p = math.floor(c.p * 10 + 0.5) / 10
    TriggerClientEvent('nz-wig:c:clashTick', c.a, p)
    TriggerClientEvent('nz-wig:c:clashTick', c.v, p)
    if c.p >= CC.WinAt or c.p <= -CC.WinAt then Clash.Finish(c, 'ko') end
end)

function Clash.Finish(c, why)
    if c.done then return end
    c.done = true
    active[c.id] = nil

    local win
    if why == 'drop_a' then
        win = false
    elseif why == 'drop_v' then
        win = true -- logging out mid-fight doesn't save you
    elseif PedDistance(c.a, c.v) > Config.Snatch.Distance + 3.0 then
        win = false
    elseif c.p == 0 then
        win = CC.TieGoesTo == 'snatcher'
    else
        win = c.p > 0
    end
    Clash.Resolve(c, win)
end

OnPlayerDrop(function(src)
    local id = bySrc[src]
    local c = id and active[id]
    if c then Clash.Finish(c, src == c.a and 'drop_a' or 'drop_v') end
end)

function Clash.InClash(src)
    return bySrc[src] ~= nil
end

-- outcome ----------------------------------------------------------------------------------------------

local function announce(A, V, meta, tier, kind)
    local coords = PedCoords(V.src) or vec3(0, 0, 0)
    local payload = { kind = kind or 'snatch', actor = A.name, target = V.name, tier = tier.id, tierLabel = tier.label,
        color = tier.color, label = meta.label }

    if kind ~= 'steal' and tier.broadcast and Config.Announce.Broadcast then
        payload.city = true
        TriggerClientEvent('nz-wig:c:banner', -1, payload)
    else
        for _, s in ipairs(PlayersNear(coords, Config.Announce.NearbyRange)) do
            TriggerClientEvent('nz-wig:c:banner', s, payload)
        end
    end
    for _, s in ipairs(PlayersNear(coords, 80.0)) do
        TriggerClientEvent('nz-wig:c:fx', s, V.src)
    end
end

local function catalogCheck(A, meta)
    local key = CatalogKey(meta.hair)
    if not key or meta.generic then return false end
    local isNew = DB.CatalogAdd(A.id, key, meta.tier)
    if not isNew then return false end
    local count = DB.CatalogCount(A.id)
    for i = (A.row.catalog_rewards or 0) + 1, #Config.CatalogRewards do
        local r = Config.CatalogRewards[i]
        if count < r.count then break end
        A.row.catalog_rewards = i
        if r.money and r.money > 0 then Bridge.AddMoney(A.src, r.money, Config.CatalogRewardAccount, 'wig-catalog') end
        if r.xp then AddXP(A, r.xp) end
        Notify(A.src, L('catalog_reward', r.count, r.money or 0), 'success', 7000)
    end
    return true
end
Clash.CatalogCheck = catalogCheck

local function cancelBoth(c)
    TriggerClientEvent('nz-wig:c:clashEnd', c.a, { win = false, role = 'snatcher', cancelled = true })
    TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = true, role = 'victim', cancelled = true })
end

-- getting your own wig back
local function resolveSteal(c, A, V)
    local serial, meta = c.steal, nil
    if V.hair.wig and V.hair.wig.serial == serial then
        meta = V.hair.wig
        V.hair.wig = nil
    else
        local stack = Wigs.Find(V.src, serial)
        if stack and Wigs.Remove(V.src, stack) then meta = stack.meta end
    end
    if not meta then
        cancelBoth(c)
        return Notify(A.src, L('steal_gone'), 'error')
    end
    Wigs.Hop(meta, V.name, A.name)
    if not Wigs.Give(A.src, meta) then
        if c.stealWhere == 'worn' then V.hair.wig = meta else Wigs.Give(V.src, meta) end
        cancelBoth(c)
        return Notify(A.src, L('pockets_full'), 'error')
    end

    StealBack.Remove(A.id, serial)
    A.row.stolen_back = (A.row.stolen_back or 0) + 1
    local xp = AddXP(A, Config.StealBack.XP)
    local tier = GetTier(meta.tier)

    DB.AddFeed('steal', A.id, A.name, V.id, V.name, meta.tier, meta.label, 0)
    Social.PushFeed({ kind = 'steal', actor_name = A.name, target_name = V.name, tier = meta.tier, label = meta.label, created = now() })

    TriggerClientEvent('nz-wig:c:clashEnd', c.a, {
        win = true, role = 'snatcher', opp = V.name, p = c.p, skipped = c.skipped, steal = true,
        reveal = { wig = Wigs.Public(meta, Wigs.Value(meta, GetPerks(A.row.xp).sell)), xp = xp, steal = true, blind = c.blind },
    })
    TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = false, role = 'victim', opp = A.name, p = c.p, steal = true, skipped = c.skipped })
    Notify(A.src, L('steal_back', V.name), 'success')
    Notify(V.src, L('steal_back_victim', A.name), 'error')
    React(V.src, 'snatched', 900)
    if c.stealWhere == 'worn' then
        SetTimeout(650, function() if Players[c.v] == V then Hair.Push(V, 'snatched') end end)
    end
    announce(A, V, meta, tier, 'steal')
    Log('snatch', 'Wig stolen back', ('**%s** took **%s** back from **%s** (`%s`)'):format(A.name, meta.label, V.name, meta.serial))
    SaveP(A) SaveP(V) SyncP(A) SyncP(V)
end

function Clash.Resolve(c, win)
    local A, V = Players[c.a], Players[c.v]
    release(c.a, c.v)
    local t = now()

    if not A or not V then
        -- someone vanished before anything could happen
        if A then TriggerClientEvent('nz-wig:c:clashEnd', c.a, { win = false, role = 'snatcher', cancelled = true }) end
        if V then TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = true, role = 'victim', cancelled = true }) end
        return
    end

    if not win then
        V.row.defends = V.row.defends + 1
        local gainedV = AddXP(V, Config.XP.Defend)
        A.row.fails = A.row.fails + 1
        A.row.streak = 0
        AddXP(A, Config.XP.FailedSnatch)
        TriggerClientEvent('nz-wig:c:clashEnd', c.a, { win = false, role = 'snatcher', opp = V.name, p = c.p, ragdoll = CC.FailRagdoll })
        TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = true, role = 'victim', opp = A.name, p = c.p, xp = gainedV })
        Notify(c.a, L('clash_lose_snatcher', V.name), 'error')
        Notify(c.v, L('clash_defended'), 'success')
        React(c.v, 'defended', 700)
        Log('clash', 'Snatch defended', ('%s held off %s in %s (rope %s, hits %s vs %s)'):format(
            V.name, A.name, c.game or 'no game', c.p, c.sa and c.sa.hits or 0, c.sv and c.sv.hits or 0))
        SaveP(A) SaveP(V) SyncP(A) SyncP(V)
        return
    end

    if c.steal then return resolveSteal(c, A, V) end

    -- snatcher wins ---------------------------------------------------------------
    local revenge = DB.HasSnatched(V.id, A.id, t - Config.Bounty.RevengeHours * 3600)
    local bountyOpen = Social.HasBounty(V.id)
    local meta

    if c.layer == 'wig' and V.hair.wig then
        meta = V.hair.wig
        V.hair.wig = nil
        Wigs.Hop(meta, V.name, A.name)
        if Config.Snatch.WornWigReveals == 'bald' and not V.hair.bald then Hair.SetBald(V, c.hair.m) end
    else
        local luck = computeLuck(A, V, revenge, bountyOpen)
        meta = Wigs.Create(Wigs.RollTier(luck), c.hair, V.name, A.name,
            Hair.HasStatus(V, 'burn') and { burnt = true } or nil)
        Hair.SetBald(V, c.hair.m)
    end
    local tier = GetTier(meta.tier)

    if not Wigs.Give(c.a, meta) then
        -- inventory changed during the fight: put everything back
        if c.layer == 'wig' then V.hair.wig = meta else Hair.ClearBald(V) end
        cancelBoth(c)
        Notify(c.a, L('pockets_full'), 'error')
        return
    end

    V.immuneUntil = t + Config.Protection.VictimImmunity
    V.row.snatched = V.row.snatched + 1
    V.row.streak = 0

    A.row.snatches = A.row.snatches + 1
    A.row.streak = A.row.streak + 1
    if A.row.streak > A.row.best_streak then A.row.best_streak = A.row.streak end
    if (TierIndex[meta.tier] or 1) > (TierIndex[A.row.best_tier] or 0) then A.row.best_tier = meta.tier end

    local mult = 1 + math.min(Config.XP.StreakCap, A.row.streak - 1) * Config.XP.StreakBonus
    local xp = AddXP(A, tier.xp * mult)
    if revenge then
        A.row.revenges = A.row.revenges + 1
        xp = xp + AddXP(A, Config.XP.Revenge)
    end

    local bounty = Social.ClaimBounties(A, V)
    local newStyle = c.layer ~= 'wig' and catalogCheck(A, meta) or false
    StealBack.Add(V, A, meta.serial)
    Products.Spread(V, A) -- lice jump to whoever grabs your head

    DB.AddFeed('snatch', A.id, A.name, V.id, V.name, meta.tier, meta.label, bounty)
    Social.PushFeed({ kind = 'snatch', actor_name = A.name, target_name = V.name, tier = meta.tier, label = meta.label, amount = bounty, created = t })

    TriggerClientEvent('nz-wig:c:clashEnd', c.a, {
        win = true, role = 'snatcher', opp = V.name, p = c.p, skipped = c.skipped,
        reveal = {
            wig = Wigs.Public(meta, Wigs.Value(meta, GetPerks(A.row.xp).sell)),
            xp = xp, streak = A.row.streak, revenge = revenge, bounty = bounty,
            newStyle = newStyle, worn = c.layer == 'wig', blind = c.blind,
        },
    })
    TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = false, role = 'victim', opp = A.name, p = c.p, layer = c.layer, skipped = c.skipped,
        stealBack = Config.StealBack.Enabled and math.floor(Config.StealBack.Window / 60) or nil })
    Notify(c.v, c.layer == 'wig' and L('clash_lost_wig', A.name) or L('clash_lost', A.name), 'error')
    if Config.StealBack.Enabled then Notify(c.v, L('steal_back_hint', math.floor(Config.StealBack.Window / 60)), 'info', 7000) end
    if revenge then Notify(c.a, L('revenge', V.name), 'success') end
    if bounty > 0 then Notify(c.a, L('bounty_claimed', bounty), 'success', 7000) end
    React(c.v, 'snatched', 900)

    SetTimeout(650, function()
        if Players[c.v] == V then Hair.Push(V, 'snatched') end
    end)

    announce(A, V, meta, tier)
    if Config.StreakAnnounce and A.row.streak >= Config.StreakAnnounce then
        TriggerClientEvent('nz-wig:c:banner', -1, { kind = 'streak', actor = A.name, streak = A.row.streak, city = true })
    end

    Log('snatch', 'Wig snatched', ('**%s** snatched **%s** from **%s**\nSerial `%s` · rope %s · %s'):format(
        A.name, meta.label, V.name, meta.serial, c.p or 0, c.skipped and 'no minigame' or (c.game or 'minigame')), tier.color)

    SaveP(A) SaveP(V) SyncP(A) SyncP(V)
end

-- admin / export helpers
function Clash.ResetCooldown(src)
    local P = GetP(src)
    if P then P.cooldownUntil = 0 P.tackleUntil = 0 SyncP(P) end
end
