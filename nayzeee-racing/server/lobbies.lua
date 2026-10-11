if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby requests from the tablet and race events from the client.
]]

local function lobbyOf(id)
    local l = Core.Lobbies[tostring(id or '')]
    if not l then return nil, 'LOBBY_NOT_FOUND' end
    return l
end

local function clean(v, min, max, default)
    v = math.floor(tonumber(v) or default)
    if v < min then v = min elseif v > max then v = max end
    return v
end

local function classAllowed(p, class, ranked)
    if not ranked then return true end
    local need = Config.ELO.ClassRestrictions[class]
    return not need or p.elo >= need
end

-- Vehicle chosen in the picker. Only plate + display info are trusted from the client;
-- the real vehicle is checked on start.
local function vehicleOf(d)
    local v = type(d.vehicle) == 'table' and d.vehicle or nil
    if not v or type(v.plate) ~= 'string' or #v.plate > 12 then return nil end
    return {
        plate = NZR.CleanPlate(v.plate),
        label = tostring(v.label or v.name or '?'):sub(1, 40),
        name = tostring(v.name or ''):sub(1, 30),
        class = tostring(v.class or 'All'):sub(1, 8),
    }
end

Handle('lobby:list', function()
    local out = {}
    for _, l in pairs(Core.Lobbies) do out[#out + 1] = l:Dto() end
    table.sort(out, function(a, b)
        if a.featured ~= b.featured then return a.featured == true end
        return a.created > b.created
    end)
    return out
end)

Handle('lobby:get', function(_, _, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    return l:Dto()
end)

Handle('lobby:create', function(src, p, d)
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    local track = Tracks.Load(tonumber(d.trackId) or 0)
    if not track or not Tracks.CanSee({ private = track.private and 1 or 0, creator = track.creator, creatorCrew = track.creatorCrew }, p) then
        return nil, 'TRACK_NOT_FOUND'
    end
    local vehicle = vehicleOf(d)
    if not vehicle then return nil, 'LOBBY_PICK_VEHICLE' end

    local ltype = (d.type == LobbyType.RANKED or d.type == LobbyType.CREW) and d.type or LobbyType.UNRANKED
    local mode = (d.mode == RaceMode.DRIFT or d.mode == RaceMode.TIME_TRIAL) and d.mode or RaceMode.STANDARD
    local class = 'Open'
    for _, c in ipairs(Config.Vehicles.Classes) do if c == d.class then class = c end end
    if not NZR.ClassFits(class, vehicle.class) then return nil, 'LOBBY_WRONG_CLASS' end
    if not classAllowed(p, class, ltype == LobbyType.RANKED) then return nil, 'LOBBY_ELO_TOO_LOW' end
    if ltype == LobbyType.CREW and not Crews.Can(p, CrewPerm.RACES) then return nil, 'LOBBY_CREW_PERMISSION' end

    local laps = track.type == TrackType.CIRCUIT and clean(d.laps, 0, Config.Races.MaxLaps, 1) or 0
    if mode == RaceMode.TIME_TRIAL and laps == 0 and track.type == TrackType.CIRCUIT then laps = 1 end
    local minRacers = ltype == LobbyType.RANKED and Config.Races.RequiredParticipantsForRankedLobby
        or (ltype == LobbyType.CREW and Config.Races.MinCrewSize * 2 or 1)
    local max = clean(d.max, minRacers, Config.Races.MaxParticipants, 8)

    local wager, currency = 0, nil
    if #Config.Races.WagerCurrencies > 0 and tonumber(d.wager) and tonumber(d.wager) > 0 then
        wager = clean(d.wager, 0, Config.Races.MaxWager, 0)
        for _, c in ipairs(Config.Races.WagerCurrencies) do if c == d.currency then currency = c end end
        currency = currency or Config.Races.WagerCurrencies[1]
    end

    local name = NZR.Trim(d.name)
    if name == '' then name = track.name end
    local password = NZR.Trim(d.password)

    local lobby = Lobby.New(p, {
        name = name:sub(1, 40), type = ltype, mode = mode, class = class, laps = laps, max = max, ghost = d.ghost == true,
        wager = wager > 0 and wager or nil, currency = currency, password = password ~= '' and password:sub(1, 20) or nil,
        featured = d.featured == true and CanCreateEvents(src) or false,
    }, track)
    local ok, err = lobby:Add(p, vehicle, true)
    if not ok then
        Core.Lobbies[lobby.id] = nil
        return nil, err
    end
    lobby:Changed()

    local target = lobby.featured and 'all' or Config.Notifications.NewLobby
    if target then
        local msg = L(lobby.featured and 'N_FEATURED_LOBBY' or 'N_NEW_LOBBY', lobby.name)
        if target == 'all' then
            for _, s in ipairs(GetPlayers()) do if tonumber(s) ~= src then Notify(tonumber(s), msg, 'inform') end end
        else
            for s in pairs(Core.Sessions) do if s ~= src then Notify(s, msg, 'inform') end end
        end
    end
    return lobby:Dto()
end)

Handle('lobby:join', function(src, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    if l.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    if #l.order >= l.max then return nil, 'LOBBY_FULL' end
    if l.password and NZR.Trim(d.password) ~= l.password then return nil, 'LOBBY_WRONG_PASSWORD' end
    local vehicle = vehicleOf(d)
    if not vehicle then return nil, 'LOBBY_PICK_VEHICLE' end
    if not NZR.ClassFits(l.class, vehicle.class) then return nil, 'LOBBY_WRONG_CLASS' end
    if not classAllowed(p, l.class, l.type == LobbyType.RANKED) then return nil, 'LOBBY_ELO_TOO_LOW' end
    if l.type == LobbyType.CREW then
        if not p.crewId then return nil, 'LOBBY_CREW_NEEDED' end
        local crews = l:Crews()
        local inIt = false
        for _, c in ipairs(crews) do if c == p.crewId then inIt = true end end
        if not inIt and #crews >= 2 then return nil, 'LOBBY_CREW_FULL' end
        local mine = 0
        l:Each(function(part) if part.profile.crewId == p.crewId then mine = mine + 1 end end)
        if mine >= math.floor(l.max / 2) then return nil, 'LOBBY_CREW_SLOTS' end
    end
    if l.wager and Bridge.GetBalance(src, l.currency) < l.wager then return nil, 'LOBBY_INSUFFICIENT_FUNDS' end
    l:Add(p, vehicle, false)
    l:Changed()
    local ownerSrc = Core.Online[l.owner.id]
    if ownerSrc then Notify(ownerSrc, L('N_JOIN_REQUEST', p.alias, l.name), 'inform') end
    return l:Dto()
end)

Handle('lobby:leave', function(_, p, d)
    local l, err = lobbyOf(d.id or Core.Active[p.id])
    if not l then return nil, err end
    return l:Leave(p.id)
end)

Handle('lobby:manage', function(_, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    if l.owner.id ~= p.id then return nil, 'ERR_NO_PERMISSION' end
    if l.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    local target = tonumber(d.profileId)
    if d.action == 'accept' then
        return l:Accept(target)
    elseif d.action == 'decline' or d.action == 'kick' then
        if target == p.id or not l.participants[target] then return nil, 'LOBBY_PARTICIPANT_NOT_FOUND' end
        l:Drop(target, d.action == 'kick' and 'LOBBY_KICKED' or 'LOBBY_DECLINED')
        l:Changed()
        return true
    end
    return nil, 'ERR_INVALID'
end)

Handle('lobby:start', function(_, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    if l.owner.id ~= p.id then return nil, 'ERR_NO_PERMISSION' end
    local ok, e, who = l:Start()
    if not ok then return nil, e, who end
    return true
end)

Handle('lobby:disband', function(_, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    if l.owner.id ~= p.id then return nil, 'ERR_NO_PERMISSION' end
    if l.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    l:Disband('LOBBY_DISBANDED')
    return true
end)

-- ── race events (client) ────────────────────────────────────────────────
local function racing(src)
    local p = Profiles.BySource(src)
    if not p then return nil end
    local l = Core.Lobbies[Core.Active[p.id] or '']
    return l, p
end

RegisterNetEvent('nzr:race:gate', function(k)
    local src = source
    local l, p = racing(src)
    if l then l:Gate(src, p.id, tonumber(k) or 0) end
end)

RegisterNetEvent('nzr:race:drift', function(total)
    local l, p = racing(source)
    if l then l:Drift(p.id, total) end
end)

RegisterNetEvent('nzr:race:respawn', function()
    local l, p = racing(source)
    if l then l:Respawned(p.id) end
end)

RegisterNetEvent('nzr:race:dnf', function()
    local l, p = racing(source)
    if l then l:Leave(p.id) end
end)

-- Player died / left the driver seat
RegisterNetEvent('nzr:race:dq', function(reason)
    local l, p = racing(source)
    if l then l:Disqualify(p.id, reason == 'dead' and 'dead' or 'vehicle') end
end)
