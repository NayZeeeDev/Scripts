-----------------------------------------------------------------
-- Snatching
--
-- Works on chains worn through this script AND (Config.Snatch.Clothing)
-- on chains people wear as clothing, when chainkit converted that
-- clothing. Restrained / hands up / downed victims can't fight back;
-- everyone else gets a tug of war that the server referees.
-----------------------------------------------------------------

local cfg = Config.Snatch
local tug = Config.Tug
local T = Config.Text

local cooldown = {}    -- [src] = os.time() it ends
local busy = {}        -- [src] = session id
local sessions = {}
local nextId = 1

local function ped(src) return GetPlayerPed(src) end

-- A ripped-off clothing chain comes back when the victim reloads their outfit. Remember which
-- drawable we took, so the same chain can't be snatched again (and again) until it's really changed.
local RIP_MEMORY = 6 * 3600
local function ripKey(src)
    local ident = Bridge.GetIdentifier(src)
    return ident and ('rip:' .. ident) or nil
end

local function clothingDrawable(src)
    local p = ped(src)
    if not p or p == 0 then return -1 end
    return GetPedDrawableVariation(p, 7)
end

local function ripped(src, drawable)
    local k = ripKey(src)
    if not k then return true end
    local ok, r = pcall(json.decode, GetResourceKvpString(k) or 'null')
    if not ok or type(r) ~= 'table' then return false end
    if (r.t or 0) + RIP_MEMORY < os.time() or r.d ~= drawable then
        DeleteResourceKvp(k)
        return false
    end
    return true
end

local function rememberRip(src, drawable)
    local k = ripKey(src)
    if k then SetResourceKvp(k, json.encode({ d = drawable, t = os.time() })) end
end

--- In a snatch right now (either side)? Other files refuse wear / take off / throw / place then.
function SnatchBusy(src) return busy[src] ~= nil end

local function protected(src)
    local job, duty = Bridge.GetJob(src)
    if not job or not duty then return false end
    for _, j in ipairs(cfg.ProtectedJobs or {}) do
        if j == job then return true end
    end
    return false
end

local function restrained(src, report)
    local st = Player(src).state
    for _, k in ipairs(Config.RestrainedStates) do if st[k] then return true end end
    for _, k in ipairs(Config.DownedStates) do if st[k] then return true end end
    return report and (report.handsUp or report.dead) or false
end

local function behind(snatcher, victim)
    local sp, vp = ped(snatcher), ped(victim)
    local sc, vc = GetEntityCoords(sp), GetEntityCoords(vp)
    local h = math.rad(GetEntityHeading(vp))
    local fx, fy = -math.sin(h), math.cos(h)
    local dx, dy = sc.x - vc.x, sc.y - vc.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return false end
    local dot = math.max(-1.0, math.min(1.0, (fx * dx + fy * dy) / len))
    return math.deg(math.acos(dot)) >= 180 - (tug.Blindside.Angle or 70)
end

-----------------------------------------------------------------
-- the chain changes hands
-----------------------------------------------------------------

local function take(snatcher, victim, what)
    local meta
    if what.kind == 'worn' then
        meta = Worn.strip(victim)
        if not meta then return false end
    else
        -- the server checks the outfit itself: the drawable must still be on and not already ripped once
        local d = clothingDrawable(victim)
        if d <= 0 or d == (cfg.ClothingNone or 0) or d ~= what.drawable or ripped(victim, d) then return false end
        rememberRip(victim, d)
        meta = Worn.newMeta(what.key, what.letter, victim)
        TriggerClientEvent('nzc:c:ripClothing', victim, cfg.ClothingNone or 0)
    end
    meta.stolenFrom = Bridge.GetCharName(victim)
    meta = Chains.meta(Chains.fromMeta(meta), meta.variant, meta)
    local label = meta.label or 'chain'

    TriggerClientEvent('nzc:c:anim', snatcher, 'snatch')
    TriggerClientEvent('nzc:c:anim', victim, 'snatched')

    local vc = GetEntityCoords(ped(victim))
    local function drop()
        local h = math.random() * 360.0
        Drops.add({ meta = meta, coords = { x = vc.x + math.sin(h) * 0.5, y = vc.y + math.cos(h) * 0.5, z = vc.z - 0.9 },
            rot = { x = -90.0, y = 0.0, z = h }, thrown = true, snapped = true })
    end

    if math.random() < (cfg.SnapChance or 0) then
        SetTimeout(450, drop)
        Worn.notify(snatcher, T.snapped, 'warning')
        Worn.notify(victim, T.snapped, 'warning')
    elseif Inv.CanCarry(snatcher, meta) and Inv.Add(snatcher, meta) then
        Worn.notify(snatcher, T.snatched:format(label), 'success')
        Worn.notify(victim, T.got_snatched:format(Bridge.GetCharName(snatcher), label), 'error')
    else
        SetTimeout(450, drop)
        Worn.notify(snatcher, T.no_room, 'error')
        Worn.notify(victim, T.got_snatched:format(Bridge.GetCharName(snatcher), label), 'error')
    end

    if math.random() < (cfg.Dispatch or 0) then
        TriggerClientEvent('nzc:c:dispatch', victim, vc)
    end
    Logs.send('snatch', 'Chain snatched', ('%s snatched %s (%s) from %s'):format(Logs.who(snatcher), label,
        what.kind == 'worn' and 'worn' or 'clothing', Logs.who(victim)))
    return true
end

-----------------------------------------------------------------
-- tug of war
-----------------------------------------------------------------

local function finish(id, cancelled)
    local s = sessions[id]
    if not s then return end
    sessions[id] = nil
    busy[s.snatcher], busy[s.victim] = nil, nil

    local win
    if cancelled then win = false
    elseif s.rope >= tug.WinAt then win = true
    elseif s.rope <= -tug.WinAt then win = false
    elseif s.rope == 0 then win = tug.TieGoesTo == 'snatcher'
    else win = s.rope > 0 end

    TriggerClientEvent('nzc:c:tugEnd', s.snatcher, { id = id, role = 'snatcher', win = win, cancelled = cancelled,
        ragdoll = (not win and not cancelled) and (cfg.FailRagdoll or 0) or 0 })
    TriggerClientEvent('nzc:c:tugEnd', s.victim, { id = id, role = 'victim', win = not win, cancelled = cancelled })

    if cancelled then return end
    if win then
        if not take(s.snatcher, s.victim, s.what) then Worn.notify(s.snatcher, T.nothing_to_take, 'error') end
    else
        Worn.notify(s.snatcher, T.lost_tug, 'error')
        Worn.notify(s.victim, T.held_on, 'success')
        Logs.send('snatch', 'Snatch failed', ('%s held on to their chain against %s'):format(Logs.who(s.victim), Logs.who(s.snatcher)))
    end
end

local function startTug(snatcher, victim, what)
    local id = nextId
    nextId = id + 1
    local rope = 0
    local blind = tug.Blindside.Enabled and behind(snatcher, victim)
    if blind then rope = tug.Blindside.Start or 25 end
    local s = {
        id = id, snatcher = snatcher, victim = victim, what = what, rope = rope,
        ends = GetGameTimer() + tug.Duration, hits = {},
    }
    sessions[id] = s
    busy[snatcher], busy[victim] = id, id

    local base = { id = id, duration = tug.Duration, rope = rope, winAt = tug.WinAt, key = tug.KeyLabel, control = tug.Key,
                   label = Chains.label(what.key, what.letter), image = Chains.model(what.key, what.letter), blind = blind }
    local a, b = {}, {}
    for k, v in pairs(base) do a[k] = v; b[k] = v end
    a.role, a.opp, a.oppSrc = 'snatcher', Bridge.GetCharName(victim), victim
    b.role, b.opp, b.oppSrc = 'victim', Bridge.GetCharName(snatcher), snatcher
    TriggerClientEvent('nzc:c:tugStart', snatcher, a)
    TriggerClientEvent('nzc:c:tugStart', victim, b)

    CreateThread(function()
        while sessions[id] do
            if GetGameTimer() >= s.ends then return finish(id) end
            if not GetPlayerName(snatcher) or not GetPlayerName(victim) then return finish(id, true) end
            Wait(100)
        end
    end)
end

RegisterNetEvent('nzc:s:tugHit', function(id)
    local src = source
    local s = sessions[tonumber(id)]
    if not s or (src ~= s.snatcher and src ~= s.victim) then return end
    local now = GetGameTimer()
    if s.hits[src] and now - s.hits[src] < (tug.MinHitInterval or 85) then return end
    s.hits[src] = now
    if src == s.snatcher then s.rope = s.rope + tug.Push.snatcher else s.rope = s.rope - tug.Push.victim end
    s.rope = math.max(-tug.WinAt, math.min(tug.WinAt, s.rope))
    TriggerClientEvent('nzc:c:tugTick', s.snatcher, s.rope)
    TriggerClientEvent('nzc:c:tugTick', s.victim, s.rope)
    if math.abs(s.rope) >= tug.WinAt then finish(s.id) end
end)

--- Called by server/main.lua when a player leaves, BEFORE their worn chain is cleared.
--- Leaving in the middle of a tug of war forfeits it: the victim's chain goes to the snatcher.
function SnatchForfeit(src)
    local id = busy[src]
    cooldown[src] = nil
    if not id then return end
    local s = sessions[id]
    if not s then busy[src] = nil return end
    if src == s.victim then
        s.rope = tug.WinAt
        finish(id)
    else
        finish(id, true)
    end
end

-----------------------------------------------------------------
-- the request
-----------------------------------------------------------------

RegisterNetEvent('nzc:s:snatch', function(target)
    local src = source
    target = tonumber(target)
    if not cfg.Enabled or not target or target == src or not GetPlayerName(target) then return end
    if busy[src] or busy[target] then return Worn.notify(src, T.busy, 'error') end

    local left = (cooldown[src] or 0) - os.time()
    if left > 0 then return Worn.notify(src, T.cooldown:format(left), 'error') end

    local sp, tp = ped(src), ped(target)
    if #(GetEntityCoords(sp) - GetEntityCoords(tp)) > (cfg.Distance or 1.8) + 1.5 then
        return Worn.notify(src, T.too_far, 'error')
    end
    if not cfg.AllowInVehicle and (GetVehiclePedIsIn(sp, false) ~= 0 or GetVehiclePedIsIn(tp, false) ~= 0) then return end
    if protected(target) then return Worn.notify(src, T.protected, 'error') end

    -- what is there to take?
    local what
    local w = Worn.get(target)
    if w then what = { kind = 'worn', key = w.key, letter = w.letter } end

    -- both sides are taken while we ask, so nobody else can grab the same victim meanwhile
    busy[src], busy[target] = 'asking', 'asking'
    local ok, report = pcall(lib.callback.await, 'nzc:state', target)
    busy[src], busy[target] = nil, nil
    report = ok and type(report) == 'table' and report or {}
    if not GetPlayerName(src) or not GetPlayerName(target) then return end
    if report.noZone then return Worn.notify(src, T.protected, 'error') end

    if not what and cfg.Clothing and type(report.clothing) == 'string' then
        local d = Chains.def(report.clothing)
        local drawable = clothingDrawable(target)
        if d and d.origin == 'server' and drawable > 0 and drawable ~= (cfg.ClothingNone or 0) and not ripped(target, drawable) then
            local v = Chains.variant(report.clothing, report.letter)
            what = { kind = 'clothing', key = report.clothing, letter = v and v.letter or 'a', drawable = drawable }
        end
    end
    if not what then return Worn.notify(src, T.nothing_to_take, 'error') end

    cooldown[src] = os.time() + (cfg.Cooldown or 60)

    if not tug.Enabled or restrained(target, report) then
        if not take(src, target, what) then Worn.notify(src, T.nothing_to_take, 'error') end
        return
    end
    startTug(src, target, what)
end)
