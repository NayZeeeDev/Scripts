-- Tackles, zip ties and holding someone still. Everything here is state the server owns;
-- clients only play the animations and lock their own controls.

Restrain = {}

local CT, CTi, CH = Config.Tackle, Config.Tie, Config.Hold

local ties   = {}   -- [tiedSrc] = { strength, last, lastTok, by, token }
local holds  = {}   -- [holderSrc] = { held, grip, last, lastTok, token }
local heldBy = {}   -- [heldSrc] = holderSrc
local downTokens = {}

local function now() return os.time() end
local function st(src) return Player(src).state end

function Restrain.IsTied(src) return ties[src] ~= nil end
function Restrain.HeldBy(src) return heldBy[src] end

-- tackle -------------------------------------------------------------------------------------------

local function setDown(src, seconds)
    downTokens[src] = (downTokens[src] or 0) + 1
    local token = downTokens[src]
    st(src):set(ST.down, true, true)
    SetTimeout(seconds * 1000, function()
        if downTokens[src] == token then st(src):set(ST.down, nil, true) end
    end)
end

RegisterNetEvent('nz-wig:s:tackle', function(target)
    local src = source
    local A, V = GetP(src), GetP(tonumber(target))
    if not CT.Enabled or not A or not V or A == V then return end
    if now() < (A.tackleUntil or 0) then return Notify(src, L('tackle_cooldown', A.tackleUntil - now()), 'error') end
    local ok, key, extra = CanAttack(A)
    if not ok then return AttackError(src, key, extra) end
    local okT, keyT = CanBeTarget(V, { ignoreImmune = true })
    if not okT then return Notify(src, L(keyT), 'error') end
    if InVehicle(src) or InVehicle(V.src) then return Notify(src, L('in_vehicle'), 'error') end
    if PedDistance(src, V.src) > CT.Range + 1.0 then return Notify(src, L('no_one_close'), 'error') end
    if ties[V.src] or heldBy[V.src] then return Notify(src, L('already_restrained'), 'error') end

    A.tackleUntil = now() + CT.Cooldown
    EndNewPlayer(A)
    SyncP(A)
    if holds[V.src] then Restrain.Release(V.src, 'tackled') end

    setDown(V.src, CT.DownedWindow)
    TriggerClientEvent('nz-wig:c:tackle', src, V.src)
    TriggerClientEvent('nz-wig:c:tackled', V.src, src)
    A.row.tackles = (A.row.tackles or 0) + 1
    AddXP(A, Config.XP.Tackle)
    SaveP(A)
    Notify(V.src, L('tackled_by', A.name), 'error')
    Log('restrain', 'Tackle', ('**%s** tackled **%s**'):format(A.name, V.name))
end)

-- zip ties -------------------------------------------------------------------------------------------

local function setTied(V, byName)
    local r = { strength = CTi.Struggle.Strength, last = 0, token = (ties[V.src] and ties[V.src].token or 0) + 1 }
    ties[V.src] = r
    st(V.src):set(ST.tied, true, true)
    TriggerClientEvent('nz-wig:c:tied', V.src, true, { struggle = CTi.Struggle.Enabled, strength = r.strength })
    Notify(V.src, L('tied_by', byName), 'error')
    if CTi.MaxMinutes > 0 then
        local token = r.token
        SetTimeout(CTi.MaxMinutes * 60000, function()
            if ties[V.src] and ties[V.src].token == token then Restrain.Untie(V.src, 'timeout') end
        end)
    end
end

function Restrain.Untie(src, reason)
    if not ties[src] then return end
    ties[src] = nil
    st(src):set(ST.tied, nil, true)
    TriggerClientEvent('nz-wig:c:tied', src, false)
    if reason == 'struggle' then Notify(src, L('struggle_free'), 'success')
    elseif reason == 'timeout' then Notify(src, L('ties_loose'), 'info') end
end

local acting = {} -- [src] = true while tying / untying

RegisterNetEvent('nz-wig:s:tie', function(target)
    local src = source
    local A, V = GetP(src), GetP(tonumber(target))
    if not CTi.Enabled or not A or not V or A == V or acting[src] then return end
    if ties[V.src] then return Notify(src, L('already_tied'), 'error') end
    local ok, key, extra = CanAttack(A)
    if not ok then return AttackError(src, key, extra) end
    local okT, keyT = CanBeTarget(V, { ignoreImmune = true })
    if not okT then return Notify(src, L(keyT), 'error') end
    if Inv.Count(src, CTi.Item) < 1 then return Notify(src, L('need_item', CTi.Item), 'error') end
    if PedDistance(src, V.src) > 2.2 then return Notify(src, L('no_one_close'), 'error') end

    acting[src] = true
    local helpless = IsRestrainedSrc(V.src) or heldBy[V.src] ~= nil
    if not helpless then
        local q = Clash.QueryHair(V.src, 2000)
        helpless = q and (q.handsUp or q.restrained or q.downed)
    end
    if not helpless then
        acting[src] = nil
        return Notify(src, L('tie_needs_restrain'), 'error')
    end

    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'tie', other = V.src, duration = CTi.Duration })
    SetTimeout(CTi.Duration + 100, function()
        acting[src] = nil
        if Players[src] ~= A or Players[V.src] ~= V or ties[V.src] then return end
        if PedDistance(src, V.src) > 3.0 then return Notify(src, L('too_far_moved'), 'error') end
        if CTi.Consume and not Inv.Remove(src, CTi.Item, 1) then return Notify(src, L('need_item', CTi.Item), 'error') end
        setTied(V, A.name)
        A.row.ties = (A.row.ties or 0) + 1
        AddXP(A, Config.XP.Tie)
        SaveP(A)
        Notify(src, L('tied_them', V.name), 'success')
        Log('restrain', 'Zip tied', ('**%s** tied up **%s**'):format(A.name, V.name))
    end)
end)

RegisterNetEvent('nz-wig:s:untie', function(target)
    local src = source
    local A = GetP(src)
    target = tonumber(target)
    if not A or not target or target == src or not ties[target] or acting[src] then return end
    if ties[src] then return end -- tied people can't untie anyone
    if PedDistance(src, target) > 2.2 then return Notify(src, L('no_one_close'), 'error') end
    acting[src] = true
    TriggerClientEvent('nz-wig:c:actionRun', src, { kind = 'untie', other = target, duration = CTi.UntieTime })
    SetTimeout(CTi.UntieTime + 100, function()
        acting[src] = nil
        if not ties[target] or PedDistance(src, target) > 3.0 then return end
        Restrain.Untie(target, 'untied')
        Notify(target, L('untied_by', A.name), 'success')
        Notify(src, L('untied_them'), 'success')
    end)
end)

-- holding --------------------------------------------------------------------------------------------

function Restrain.Release(holderSrc, reason)
    local h = holds[holderSrc]
    if not h then return end
    holds[holderSrc] = nil
    heldBy[h.held] = nil
    st(holderSrc):set(ST.holding, nil, true)
    st(h.held):set(ST.held, nil, true)
    TriggerClientEvent('nz-wig:c:holdEnd', holderSrc, { role = 'holder', reason = reason })
    TriggerClientEvent('nz-wig:c:holdEnd', h.held, { role = 'held', reason = reason })
    if reason == 'broke' then
        Notify(holderSrc, L('hold_broken'), 'error')
        Notify(h.held, L('broke_free'), 'success')
    end
end

RegisterNetEvent('nz-wig:s:hold', function(target)
    local src = source
    local A, V = GetP(src), GetP(tonumber(target))
    if not CH.Enabled or not A or not V or A == V then return end
    if holds[src] or heldBy[src] or ties[src] then return Notify(src, L('busy'), 'error') end
    if heldBy[V.src] or holds[V.src] then return Notify(src, L('already_restrained'), 'error') end
    local ok, key, extra = CanAttack(A)
    if not ok then return AttackError(src, key, extra) end
    local okT, keyT = CanBeTarget(V, { ignoreImmune = true })
    if not okT then return Notify(src, L(keyT), 'error') end
    if InVehicle(src) or InVehicle(V.src) then return Notify(src, L('in_vehicle'), 'error') end
    if PedDistance(src, V.src) > 2.0 then return Notify(src, L('no_one_close'), 'error') end

    local restrained = IsRestrainedSrc(V.src)
    if CH.RequireBehind and not restrained and not IsBehindSrc(src, V.src, 75) then
        local q = Clash.QueryHair(V.src, 2000)
        if not (q and (q.handsUp or q.restrained)) then return Notify(src, L('hold_behind'), 'error') end
    end
    if Players[src] ~= A or Players[V.src] ~= V or heldBy[V.src] then return end

    local h = { held = V.src, grip = CH.Grip, last = 0, token = math.random(1, 1e9) }
    holds[src], heldBy[V.src] = h, src
    st(src):set(ST.holding, V.src, true)
    st(V.src):set(ST.held, src, true)
    TriggerClientEvent('nz-wig:c:holdStart', src, { role = 'holder', other = V.src, max = CH.MaxSeconds })
    TriggerClientEvent('nz-wig:c:holdStart', V.src, { role = 'held', other = src, max = CH.MaxSeconds, grip = h.grip })
    Notify(V.src, L('held_by', A.name), 'error')
    Log('restrain', 'Hold', ('**%s** grabbed **%s**'):format(A.name, V.name))

    local token = h.token
    SetTimeout(CH.MaxSeconds * 1000, function()
        if holds[src] and holds[src].token == token then Restrain.Release(src, 'timeout') end
    end)
end)

RegisterNetEvent('nz-wig:s:release', function()
    local src = source
    if holds[src] then Restrain.Release(src, 'released') end
end)

-- struggling (tied or held) -----------------------------------------------------------------------------

RegisterNetEvent('nz-wig:s:struggle', function(token)
    local src = source
    if token ~= 'L' and token ~= 'R' then return end
    local t = GetGameTimer()

    local holder = heldBy[src]
    if holder then
        local h = holds[holder]
        if not h or token == h.lastTok or t - h.last < CH.MinHitInterval then return end
        h.lastTok, h.last = token, t
        h.grip = h.grip - CH.StruggleDrain
        TriggerClientEvent('nz-wig:c:struggleTick', src, math.max(0, h.grip) / CH.Grip)
        if h.grip <= 0 then Restrain.Release(holder, 'broke') end
        return
    end

    local r = ties[src]
    if r and CTi.Struggle.Enabled then
        if token == r.lastTok or t - r.last < CTi.Struggle.MinHitInterval then return end
        r.lastTok, r.last = token, t
        r.strength = r.strength - CTi.Struggle.PerPull
        TriggerClientEvent('nz-wig:c:struggleTick', src, math.max(0, r.strength) / CTi.Struggle.Strength)
        if r.strength <= 0 then Restrain.Untie(src, 'struggle') end
    end
end)

-- cleanup ---------------------------------------------------------------------------------------------------

OnPlayerDrop(function(src)
    if holds[src] then Restrain.Release(src, 'left') end
    if heldBy[src] then Restrain.Release(heldBy[src], 'left') end
    ties[src] = nil
    acting[src] = nil
    downTokens[src] = nil
end)

OnPlayerLoad(function(P)
    -- fresh character / relog: never start tied or held
    local s = st(P.src)
    for _, k in ipairs({ ST.tied, ST.held, ST.holding, ST.down }) do
        if s[k] then s:set(k, nil, true) end
    end
end)

-- usable zip ties: tie whoever is closest in front
function Restrain.RegisterItems()
    if not CTi.Enabled then return end
    Bridge.RegisterUsable(CTi.Item, function(src)
        TriggerClientEvent('nz-wig:c:useTies', src)
    end)
end
