-- Snatch requests + The Clash (server-authoritative tug-of-war)

Clash = {}

local active  = {}  -- [id] = clash
local bySrc   = {}  -- [src] = id
local queries = {}  -- [token] = { p = promise, src = n }
local requesting = {}
local seq, qseq = 0, 0

local CC = Config.Clash

-- victim hair query ------------------------------------------------------------

local function queryHair(target, timeout)
    qseq = qseq + 1
    local token = qseq
    local p = promise.new()
    queries[token] = { p = p, src = target }
    TriggerClientEvent('nz-wig:c:query', target, token)
    SetTimeout(timeout, function()
        if queries[token] then
            queries[token] = nil
            p:resolve(nil)
        end
    end)
    return Citizen.Await(p)
end

local function int(v, lo, hi)
    v = math.floor(tonumber(v) or 0)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

Clash.QueryHair = queryHair

RegisterNetEvent('nz-wig:s:queryReply', function(token, data)
    local q = queries[token]
    if not q or q.src ~= source then return end
    queries[token] = nil
    if type(data) ~= 'table' then return q.p:resolve(nil) end
    q.p:resolve({
        d = int(data.d, 0, 1000), t = int(data.t, 0, 64), c = int(data.c, 0, 63), h = int(data.h, 0, 63),
        restrained = data.restrained == true, handsUp = data.handsUp == true, downed = data.downed == true,
    })
end)

-- helpers -----------------------------------------------------------------------

local function isBehind(attacker, victim)
    local va, vv = GetPlayerPed(attacker), GetPlayerPed(victim)
    local ca, cv = GetEntityCoords(va), GetEntityCoords(vv)
    local h = math.rad(GetEntityHeading(vv))
    local fx, fy = -math.sin(h), math.cos(h)
    local dx, dy = ca.x - cv.x, ca.y - cv.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return false end
    local dot = (fx * dx + fy * dy) / len
    local ang = math.deg(math.acos(math.max(-1, math.min(1, dot))))
    return ang >= 180 - CC.Blindside.Angle
end

local function release(...)
    for _, src in ipairs({ ... }) do
        local P = Players[src]
        if P then P.busy = false end
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

-- request -----------------------------------------------------------------------

RegisterNetEvent('nz-wig:s:snatch', function(target)
    local src = source
    target = tonumber(target)
    local A = GetP(src)
    if not A or requesting[src] then return end
    local V = target and GetP(target)
    if not V or V == A then return Notify(src, L('no_one_close'), 'error') end

    local ok, key, extra = CanAttack(A)
    if not ok then return Notify(src, key == 'cooldown' and L('cooldown', extra) or L(key), 'error') end
    if not Config.Snatch.AllowInVehicle and (InVehicle(src) or InVehicle(target)) then return Notify(src, L('in_vehicle'), 'error') end
    if PedDistance(src, target) > Config.Snatch.Distance + 1.0 then return Notify(src, L('no_one_close'), 'error') end

    local vModel = Hair.PedModelKey(target)
    if not vModel or not ModelEnabled(vModel) then return Notify(src, L('wrong_model'), 'error') end

    local okT, keyT = CanBeTarget(V)
    if not okT then return Notify(src, L(keyT), 'error') end

    local layer = Hair.Layer(V)
    if layer == 'bald' then return Notify(src, L('already_bald'), 'error') end

    requesting[src] = true
    A.busy, V.busy = true, true
    local q = queryHair(target, 2500)
    requesting[src] = nil

    -- either player may have left while we waited
    if Players[src] ~= A or Players[target] ~= V then return release(src, target) end
    if not q then release(src, target) return Notify(src, L('invalid'), 'error') end

    local downed = q.downed or StateFlag(target, Config.DownedStates)
    local restrained = q.restrained or q.handsUp or StateFlag(target, Config.RestrainedStates)
    if downed and not Config.Snatch.AllowDowned then
        release(src, target)
        return Notify(src, L('cant_snatch'), 'error')
    end

    local hair
    if layer == 'wig' then
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

    if not Wigs.CanCarry(src, layer == 'wig' and V.hair.wig or { tier = 'common' }) then
        release(src, target)
        return Notify(src, L('pockets_full'), 'error')
    end

    StartCooldown(A)
    if Config.Protection.NewPlayerEndsOnAttack then EndNewPlayer(A) end
    SyncP(A)

    local c = {
        a = src, v = target, layer = layer, hair = hair,
        blind = CC.Blindside.Enabled and isBehind(src, target),
        glued = Hair.IsGlued(V),
    }

    if not CC.Enabled or downed or (restrained and CC.SkipIfRestrained) then
        c.skipped = true
        c.p = CC.WinAt
        return Clash.Resolve(c, true)
    end
    Clash.Start(c)
end)

-- clash ---------------------------------------------------------------------------

function Clash.Start(c)
    local A, V = Players[c.a], Players[c.v]
    seq = seq + 1
    c.id = seq
    c.p = c.blind and CC.Blindside.Start or 0
    c.endsAt = GetGameTimer() + CC.Duration
    c.lastA, c.lastV, c.hitsA, c.hitsV = 0, 0, 0, 0

    local pa, pv = GetPerks(A.row.xp), GetPerks(V.row.xp)
    c.pushA = CC.Push.snatcher
    c.pushV = CC.Push.victim * (c.glued and Config.Glue.PushMultiplier or 1.0)
    local zoneA = CC.Zone.snatcher + pa.zone - (c.glued and Config.Glue.SnatcherZonePenalty or 0)
    local zoneV = CC.Zone.victim + pv.zone + (c.glued and Config.Glue.ZoneBonus or 0)

    active[c.id] = c
    bySrc[c.a], bySrc[c.v] = c.id, c.id

    local base = { id = c.id, duration = CC.Duration, winAt = CC.WinAt, p = c.p, key = CC.Key,
        lockout = CC.MissLockout, blind = c.blind, glued = c.glued, layer = c.layer }

    local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
    local sa = copy(base)
    sa.role, sa.me, sa.opp, sa.oppSrc, sa.zone, sa.speed = 'snatcher', A.name, V.name, c.v, zoneA, CC.Speed.snatcher
    local sv = copy(base)
    sv.role, sv.me, sv.opp, sv.oppSrc, sv.zone, sv.speed = 'victim', V.name, A.name, c.a, zoneV, CC.Speed.victim

    TriggerClientEvent('nz-wig:c:clashStart', c.a, sa)
    TriggerClientEvent('nz-wig:c:clashStart', c.v, sv)

    local id = c.id
    SetTimeout(CC.Duration + 300, function()
        if active[id] == c and not c.done then Clash.Finish(c, 'time') end
    end)
end

RegisterNetEvent('nz-wig:s:clashHit', function(id)
    local src = source
    local c = active[tonumber(id) or -1]
    if not c or c.done then return end
    local now = GetGameTimer()
    if now > c.endsAt + 200 then return end

    if src == c.a then
        if now - c.lastA < CC.MinHitInterval then return end
        c.lastA, c.hitsA = now, c.hitsA + 1
        c.p = math.min(CC.WinAt, c.p + c.pushA)
    elseif src == c.v then
        if now - c.lastV < CC.MinHitInterval then return end
        c.lastV, c.hitsV = now, c.hitsV + 1
        c.p = math.max(-CC.WinAt, c.p - c.pushV)
    else
        return
    end

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
        win = true -- logging out mid-clash doesn't save you
    elseif PedDistance(c.a, c.v) > Config.Snatch.Distance + 3.0 then
        win = false
    elseif c.p == 0 then
        win = CC.TieGoesTo == 'snatcher'
    else
        win = c.p > 0
    end
    Clash.Resolve(c, win)
end

function Clash.OnDrop(src)
    local id = bySrc[src]
    local c = id and active[id]
    if c then Clash.Finish(c, src == c.a and 'drop_a' or 'drop_v') end
end

function Clash.InClash(src)
    return bySrc[src] ~= nil
end

-- outcome -------------------------------------------------------------------------

local function announce(A, V, meta, tier)
    local vped = GetPlayerPed(V.src)
    local coords = vped ~= 0 and GetEntityCoords(vped) or vec3(0, 0, 0)
    local payload = { kind = 'snatch', actor = A.name, target = V.name, tier = tier.id, tierLabel = tier.label,
        color = tier.color, label = meta.label }

    if tier.broadcast and Config.Announce.Broadcast then
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
    local isNew = DB.CatalogAdd(A.id, meta.style, meta.tier)
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

function Clash.Resolve(c, win)
    local A, V = Players[c.a], Players[c.v]
    release(c.a, c.v)
    local now = os.time()

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
        Log('clash', 'Snatch defended', ('%s held off %s (rope %s, hits %s vs %s)'):format(V.name, A.name, c.p, c.hitsA or 0, c.hitsV or 0))
        SaveP(A) SaveP(V) SyncP(A) SyncP(V)
        return
    end

    -- snatcher wins -------------------------------------------------------------
    local revenge = DB.HasSnatched(V.id, A.id, now - Config.Bounty.RevengeHours * 3600)
    local bountyOpen = Social.HasBounty(V.id)
    local meta, tier

    if c.layer == 'wig' and V.hair.wig then
        meta = V.hair.wig
        V.hair.wig = nil
        Wigs.Hop(meta, V.name, A.name)
        if Config.Snatch.WornWigReveals == 'bald' and not V.hair.bald then Hair.SetBald(V, c.hair.m) end
    else
        local luck = computeLuck(A, V, revenge, bountyOpen)
        meta = Wigs.Create(Wigs.RollTier(luck), c.hair, V.name, A.name)
        Hair.SetBald(V, c.hair.m)
    end
    tier = GetTier(meta.tier)

    if not Wigs.Give(c.a, meta) then
        -- inventory changed during the clash: put everything back
        if c.layer == 'wig' then V.hair.wig = meta else Hair.ClearBald(V) end
        TriggerClientEvent('nz-wig:c:clashEnd', c.a, { win = false, role = 'snatcher', cancelled = true })
        TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = true, role = 'victim', cancelled = true })
        Notify(c.a, L('pockets_full'), 'error')
        return
    end

    V.immuneUntil = now + Config.Protection.VictimImmunity
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

    DB.AddFeed('snatch', A.id, A.name, V.id, V.name, meta.tier, meta.label, bounty)
    Social.PushFeed({ kind = 'snatch', actor_name = A.name, target_name = V.name, tier = meta.tier, label = meta.label, amount = bounty, created = now })

    TriggerClientEvent('nz-wig:c:clashEnd', c.a, {
        win = true, role = 'snatcher', opp = V.name, p = c.p, skipped = c.skipped,
        reveal = {
            wig = Wigs.Public(meta, Wigs.Value(meta, GetPerks(A.row.xp).sell)),
            xp = xp, streak = A.row.streak, revenge = revenge, bounty = bounty,
            newStyle = newStyle, worn = c.layer == 'wig', blind = c.blind,
        },
    })
    TriggerClientEvent('nz-wig:c:clashEnd', c.v, { win = false, role = 'victim', opp = A.name, p = c.p, layer = c.layer, skipped = c.skipped })
    Notify(c.v, c.layer == 'wig' and L('clash_lost_wig', A.name) or L('clash_lost', A.name), 'error')
    if revenge then Notify(c.a, L('revenge', V.name), 'success') end
    if bounty > 0 then Notify(c.a, L('bounty_claimed', bounty), 'success', 7000) end

    SetTimeout(650, function()
        if Players[c.v] == V then Hair.Push(V, 'snatched') end
    end)

    announce(A, V, meta, tier)
    if Config.StreakAnnounce and A.row.streak >= Config.StreakAnnounce then
        TriggerClientEvent('nz-wig:c:banner', -1, { kind = 'streak', actor = A.name, streak = A.row.streak, city = true })
    end

    Log('snatch', 'Wig snatched', ('**%s** snatched **%s** from **%s**\nSerial `%s` · rope %s · %s'):format(
        A.name, meta.label, V.name, meta.serial, c.p or 0, c.skipped and 'no clash' or 'clash'), tier.color)

    SaveP(A) SaveP(V) SyncP(A) SyncP(V)
end

-- admin / export helpers
function Clash.ResetCooldown(src)
    local P = GetP(src)
    if P then P.cooldownUntil = 0 SyncP(P) end
end
