-- Boot, lifecycle and exports

math.randomseed(os.time() + GetGameTimer())

CreateThread(function()
    DB.Init()
    Social.LoadBounties()
    Social.LoadFeed()
    Wigs.LoadShotIndex()
    Hair.RegisterItems()
    Restrain.RegisterItems()
    Cutting.RegisterItems()
    Products.RegisterItems()

    Bridge.OnLoaded(function(src)
        SetTimeout(500, function() LoadPlayer(src) end)
    end)
    Bridge.OnUnloaded(function(src) UnloadPlayer(src) end)

    -- resource restart: pick up everyone already in the city
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if Bridge.IsLoaded(s) then LoadPlayer(s) end
    end

    local n = 0
    for _ in pairs(Players) do n = n + 1 end
    print(('^2[%s]^7 v%s ready · %s · %s · %d players loaded'):format(RESOURCE, VERSION, Bridge.Name, Inv.Name, n))
end)

-- client asks for its state after its own init (resource restart / late load)
RegisterNetEvent('nz-wig:s:ready', function()
    local src = source
    local P = GetP(src)
    if P then
        Hair.Push(P, 'load')
        SyncP(P)
    elseif Bridge.IsLoaded(src) then
        LoadPlayer(src)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    for _, P in pairs(Players) do
        P.row.last_seen = os.time()
        SaveP(P)
        -- nobody stays tied / held / in a studio bucket across a restart
        local st = Player(P.src).state
        for _, k in ipairs({ ST.tied, ST.held, ST.holding, ST.down, ST.busy, ST.fx, ST.wig }) do
            if st[k] then st:set(k, nil, true) end
        end
    end
end)

-- exports -----------------------------------------------------------------------------

exports('IsBald', function(src)
    local P = GetP(src)
    return P ~= nil and P.hair.bald ~= nil
end)

exports('GetHairState', function(src)
    local P = GetP(src)
    return P and Hair.State(P) or nil
end)

exports('RestoreHair', function(src)
    local P = GetP(src)
    if not P then return false end
    P.hair.bald, P.hair.cut, P.hair.face = nil, nil, nil
    Hair.Schedule(P)
    SaveP(P)
    Hair.Push(P, 'export')
    return true
end)

-- Safezones / events: exports['nayzeee-wigsnatchv2']:SetProtected(source, true)
exports('SetProtected', function(src, state)
    local P = GetP(src)
    if P then P.protected = state == true end
end)

exports('GiveWig', function(src, tier)
    local P = GetP(src)
    if not P then return false end
    local m = Hair.PedModelKey(src) or 'f'
    local meta = Wigs.Create(tier and TierIndex[tier] and tier or Wigs.RollTier(0),
        { m = m, d = math.random(1, 15), t = 0, c = math.random(0, 20), h = 0 }, 'Unknown', P.name)
    return Wigs.Give(src, meta), meta
end)

exports('GiveBundle', function(src, grade)
    local P = GetP(src)
    if not P then return false end
    local m = Hair.PedModelKey(src) or 'f'
    local meta = Wigs.CreateBundle({ m = m, d = math.random(1, 15), t = 0, c = math.random(0, 20), h = 0 }, 'Unknown',
        grade and GradeIndex[grade] and grade or nil)
    return Wigs.Give(src, meta), meta
end)

exports('GetStats', function(src)
    local P = GetP(src)
    if not P then return nil end
    local lvl, data = GetLevel(P.row.xp)
    return { xp = P.row.xp, level = lvl, title = data.title, snatches = P.row.snatches, defends = P.row.defends,
        snatched = P.row.snatched, streak = P.row.streak, best_streak = P.row.best_streak,
        tackles = P.row.tackles, ties = P.row.ties, crafted = P.row.crafted, stolen_back = P.row.stolen_back }
end)

exports('SetHairStatus', function(src, kind, minutes)
    local P = GetP(src)
    if not P or not Config.Products.Status[kind] then return false end
    Hair.SetStatus(P, kind, minutes or 10)
    SaveP(P)
    Hair.Push(P, 'export')
    return true
end)

exports('IsInClash', function(src) return Clash.InClash(tonumber(src)) end)
exports('IsTied', function(src) return Restrain.IsTied(tonumber(src)) end)
exports('Untie', function(src) Restrain.Untie(tonumber(src), 'export') end)
exports('IsBeingCut', function(src) return Cutting.InSession(tonumber(src)) end)

-- photo URL of a hairstyle from the Wig Studio, or nil if it hasn't been photographed
exports('GetWigImage', function(model, drawable, texture)
    return Wigs.ShotUrl({ m = model, d = drawable, t = texture or 0 })
end)
