if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby requests from the tablet (create, join, quick race, practice, spectate, invites, bets)
    and race events from the client.
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

local validClass = { All = true }
for _, c in ipairs(Config.Vehicles.Classes) do validClass[c] = true end

-- Vehicle chosen in the picker. Only plate + display info are trusted from the client;
-- the real vehicle is checked on start.
local function vehicleOf(d)
    local v = type(d.vehicle) == 'table' and d.vehicle or nil
    if not v or type(v.plate) ~= 'string' or #v.plate > 12 then return nil end
    local class = tostring(v.class or '')
    return {
        plate = NZR.CleanPlate(v.plate),
        label = tostring(v.label or v.name or '?'):sub(1, 40),
        name = tostring(v.name or ''):sub(1, 30),
        class = validClass[class] and class or nil,
    }
end

local function notifyNew(src, lobby)
    local target = lobby.featured and 'all' or Config.Notifications.NewLobby
    if not target then return end
    local msg = L(lobby.featured and 'N_FEATURED_LOBBY' or 'N_NEW_LOBBY', lobby.name)
    if target == 'all' then
        for _, s in ipairs(GetPlayers()) do if tonumber(s) ~= src then Notify(tonumber(s), msg, 'inform') end end
    else
        for s in pairs(Core.Sessions) do if s ~= src then Notify(s, msg, 'inform') end end
    end
end

Handle('lobby:list', function()
    local out = {}
    for _, l in pairs(Core.Lobbies) do
        if not l.practice then out[#out + 1] = l:Dto() end
    end
    table.sort(out, function(a, b)
        if a.featured ~= b.featured then return a.featured == true end
        return a.created > b.created
    end)
    return out
end)

Handle('lobby:get', function(_, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    return l:Dto(p.id)
end)

-- ── create ──────────────────────────────────────────────────────────────
local function createLobby(src, p, d, track)
    local practice = d.practice == true
    local hostOnly = not practice and d.hostOnly == true and Config.Spectate.Enabled and Config.Spectate.HostOnly
    local vehicle = vehicleOf(d)
    if not hostOnly and (not vehicle or not vehicle.class) then return nil, 'LOBBY_PICK_VEHICLE' end

    local ltype = (d.type == LobbyType.RANKED or d.type == LobbyType.CREW) and d.type or LobbyType.UNRANKED
    if practice then ltype = LobbyType.PRACTICE end
    local modes = { [RaceMode.DRIFT] = true, [RaceMode.TIME_TRIAL] = true, [RaceMode.ELIMINATION] = not practice }
    local mode = modes[d.mode] and d.mode or RaceMode.STANDARD
    local class = 'Open'
    if not practice then for _, c in ipairs(Config.Vehicles.Classes) do if c == d.class then class = c end end end
    if vehicle and not NZR.ClassFits(class, vehicle.class) then return nil, 'LOBBY_WRONG_CLASS' end
    if not classAllowed(p, class, ltype == LobbyType.RANKED) then return nil, 'LOBBY_ELO_TOO_LOW' end
    if ltype == LobbyType.CREW and not Crews.Can(p, CrewPerm.RACES) then return nil, 'LOBBY_CREW_PERMISSION' end

    local circuit = track.type == TrackType.CIRCUIT
    local maxLaps = practice and Config.Practice.MaxLaps or Config.Races.MaxLaps
    local laps = circuit and clean(d.laps, 0, maxLaps, 1) or 0
    if (mode == RaceMode.TIME_TRIAL or practice) and laps == 0 and circuit then laps = 1 end
    if mode == RaceMode.ELIMINATION then
        if not circuit then return nil, 'LOBBY_ELIM_CIRCUIT' end
        laps = math.max(laps, Config.Races.Elimination.MinLaps)
    end

    local pinkSlip = not practice and not hostOnly and d.pinkSlip == true
    if pinkSlip then
        local cfg = Config.PinkSlips
        if not cfg.Enabled or ltype == LobbyType.CREW or (ltype == LobbyType.RANKED and not cfg.AllowRanked) then return nil, 'LOBBY_PINK_DISABLED' end
        if not Bridge.OwnsVehicle(src, vehicle.plate) then return nil, 'LOBBY_PINK_NOT_OWNED' end
    end

    local minRacers = ltype == LobbyType.RANKED and Config.Races.RequiredParticipantsForRankedLobby
        or (ltype == LobbyType.CREW and Config.Races.MinCrewSize * 2 or 1)
    if mode == RaceMode.ELIMINATION then minRacers = math.max(minRacers, Config.Races.Elimination.MinRacers) end
    local maxRacers = pinkSlip and math.max(2, Config.PinkSlips.MaxRacers) or Config.Races.MaxParticipants
    local max = practice and 1 or clean(d.max, math.min(minRacers, maxRacers), maxRacers, 8)

    local wager, currency = 0, nil
    if not practice and #Config.Races.WagerCurrencies > 0 and tonumber(d.wager) and tonumber(d.wager) > 0 then
        wager = clean(d.wager, 0, Config.Races.MaxWager, 0)
        for _, c in ipairs(Config.Races.WagerCurrencies) do if c == d.currency then currency = c end end
        currency = currency or Config.Races.WagerCurrencies[1]
    end

    local name = NZR.Trim(d.name)
    if name == '' then name = practice and L('PRACTICE_NAME', track.name) or track.name end
    local password = NZR.Trim(d.password)

    local lobby = Lobby.New(p, {
        name = name:sub(1, 40), type = ltype, mode = mode, class = class, laps = laps, max = max, ghost = not practice and d.ghost == true,
        wager = wager > 0 and wager or nil, currency = currency, password = not practice and password ~= '' and password:sub(1, 20) or nil,
        featured = not practice and d.featured == true and CanCreateEvents(src) or false,
        practice = practice, hostOnly = hostOnly, autoAccept = not practice and d.autoAccept == true, pinkSlip = pinkSlip, quick = d.quick == true,
    }, track)
    if not hostOnly then
        local ok, err = lobby:Add(p, vehicle, true)
        if not ok then
            Core.Lobbies[lobby.id] = nil
            return nil, err
        end
    end
    if not practice then
        lobby:Changed()
        notifyNew(src, lobby)
    end
    return lobby
end

Handle('lobby:create', function(src, p, d)
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    local track = Tracks.Load(tonumber(d.trackId) or 0)
    if not track or not Tracks.CanSee(track, p) then return nil, 'TRACK_NOT_FOUND' end
    d.practice = nil
    local lobby, err = createLobby(src, p, d, track)
    if not lobby then return nil, err end
    return lobby:Dto(p.id)
end)

-- ── join ────────────────────────────────────────────────────────────────
local function joinLobby(src, p, l, vehicle, password)
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    if l.practice then return nil, 'LOBBY_NOT_FOUND' end
    if l.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    if #l.order >= l.max then return nil, 'LOBBY_FULL' end
    local inviter = l.invites[p.id]
    if l.password and not inviter and NZR.Trim(password) ~= l.password then return nil, 'LOBBY_WRONG_PASSWORD' end
    if not vehicle or not vehicle.class then return nil, 'LOBBY_PICK_VEHICLE' end
    if not NZR.ClassFits(l.class, vehicle.class) then return nil, 'LOBBY_WRONG_CLASS' end
    if not classAllowed(p, l.class, l.type == LobbyType.RANKED) then return nil, 'LOBBY_ELO_TOO_LOW' end
    if l:BetOf(p.id) then return nil, 'BET_CANT_JOIN' end
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
    if l.pinkSlip and not Bridge.OwnsVehicle(src, vehicle.plate) then return nil, 'LOBBY_PINK_NOT_OWNED' end
    l:Add(p, vehicle, false)
    -- auto-accept lobbies and invites from the host skip the queue
    local accepted = false
    if l.autoAccept or inviter == l.owner.id then accepted = l:Accept(p.id) == true end
    if not accepted then
        l:Changed()
        local ownerSrc = Core.Online[l.owner.id]
        if ownerSrc then Notify(ownerSrc, L('N_JOIN_REQUEST', p.alias, l.name), 'inform') end
    end
    return l:Dto(p.id)
end

Handle('lobby:join', function(src, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    return joinLobby(src, p, l, vehicleOf(d), d.password)
end)

-- ── quick race ──────────────────────────────────────────────────────────
-- Best open lobby for the car's class (auto-accept first, then the fullest), else a new one
Handle('quickrace', function(src, p, d)
    if not Config.QuickRace.Enabled then return nil, 'ERR_UNKNOWN' end
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    local vehicle = vehicleOf(d)
    if not vehicle or not vehicle.class then return nil, 'LOBBY_PICK_VEHICLE' end
    local best, bestScore
    for _, l in pairs(Core.Lobbies) do
        local fits = l.status == LobbyStatus.PENDING and not l.practice and not l.pinkSlip and l.type ~= LobbyType.CREW
            and not l.password and #l.order < l.max and NZR.ClassFits(l.class, vehicle.class)
            and classAllowed(p, l.class, l.type == LobbyType.RANKED)
            and (not l.wager or (Config.QuickRace.AllowWagers and Bridge.GetBalance(src, l.currency) >= l.wager))
        if fits then
            local score = (l.autoAccept and 1000 or 0) + l:Count(PStatus.ACCEPTED) * 10 - (os.time() - l.created) / 600
            if not bestScore or score > bestScore then best, bestScore = l, score end
        end
    end
    if best then
        local dto, err = joinLobby(src, p, best, vehicle)
        if dto then return { lobby = dto, created = false } end
        if err ~= 'LOBBY_FULL' then return nil, err end
    end

    -- nothing fits: closest public track, else the most played one
    local tracks = Tracks.Public()
    if #tracks == 0 then return nil, 'TRACK_NOT_FOUND' end
    local pos = GetEntityCoords(GetPlayerPed(src))
    local pick, pickDist = nil, Config.QuickRace.Create.MaxDistance
    for _, r in ipairs(tracks) do
        if r.start then
            local dist = #(NZR.V3(r.start) - pos)
            if dist < pickDist then pick, pickDist = r, dist end
        end
    end
    local track = Tracks.Load((pick or tracks[1]).id)
    if not track then return nil, 'TRACK_NOT_FOUND' end
    local q = Config.QuickRace.Create
    local lobby, err = createLobby(src, p, {
        name = L('QUICK_NAME', track.name), type = LobbyType.UNRANKED, mode = RaceMode.STANDARD,
        class = vehicle.class ~= 'All' and vehicle.class or 'Open', laps = q.Laps, max = q.Max, ghost = q.Ghost,
        autoAccept = true, quick = true, vehicle = d.vehicle,
    }, track)
    if not lobby then return nil, err end
    return { lobby = lobby:Dto(p.id), created = true }
end)

-- ── practice ────────────────────────────────────────────────────────────
-- Solo run in the car you are driving. Starts right away when you are at the start line.
Handle('practice:start', function(src, p, d)
    if not Config.Practice.Enabled then return nil, 'ERR_UNKNOWN' end
    if Core.Active[p.id] then return nil, 'LOBBY_ALREADY_IN' end
    local track = Tracks.Load(tonumber(d.trackId) or 0)
    if not track or not Tracks.CanSee(track, p) then return nil, 'TRACK_NOT_FOUND' end
    local veh, model, plate = DrivenVehicle(src)
    if not veh then return nil, 'PRACTICE_NO_VEHICLE' end
    if Config.Vehicles.IsBlacklisted(model) then return nil, 'LOBBY_VEHICLE_NOT_OK' end
    local start = track.gates[1].center
    if Config.Races.RequirePlayersInStartRadius and #(GetEntityCoords(GetPlayerPed(src)) - NZR.V3(start)) > Config.Races.StartRadius then
        return nil, 'PRACTICE_GO_TO_START', { x = start.x, y = start.y }
    end
    local lobby, err = createLobby(src, p, {
        practice = true, mode = d.mode == RaceMode.TIME_TRIAL and RaceMode.TIME_TRIAL or RaceMode.STANDARD, laps = d.laps,
        vehicle = { plate = plate, label = tostring(d.label or '?'), name = tostring(d.name or ''), class = 'All' },
    }, track)
    if not lobby then return nil, err end
    local ok, e, who = lobby:Start()
    if not ok then
        -- never listed, nothing paid: just forget it
        lobby.status = LobbyStatus.CANCELLED
        Core.Lobbies[lobby.id] = nil
        Core.Active[p.id] = nil
        return nil, e, who
    end
    return true
end)

-- ── membership ──────────────────────────────────────────────────────────
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

-- ── invites ─────────────────────────────────────────────────────────────
Handle('lobby:invite', function(_, p, d)
    local l, err = lobbyOf(Core.Active[p.id])
    if not l then return nil, 'INVITE_NO_LOBBY' end
    if l.status ~= LobbyStatus.PENDING or l.practice then return nil, 'LOBBY_ALREADY_STARTED' end
    local me = l.participants[p.id]
    if l.owner.id ~= p.id and not (me and me.status == PStatus.ACCEPTED) then return nil, 'ERR_NO_PERMISSION' end
    local target = Profiles.Get(tonumber(d.profileId) or 0)
    if not target or target.identifier == 'SYSTEM' or target.id == p.id then return nil, 'PROFILE_NOT_FOUND' end
    if l.participants[target.id] then return nil, 'INVITE_ALREADY_IN' end
    if l.invites[target.id] then return nil, 'INVITE_ALREADY' end
    if #l.order >= l.max then return nil, 'LOBBY_FULL' end
    l.invites[target.id] = p.id
    Profiles.Message(target.id, MsgType.LOBBY_INVITE, L('MSG_LOBBY_INVITE', p.alias, l.name),
        { lobbyId = l.id, lobbyName = l.name, track = l.track.name, from = p.alias, mode = l.mode })
    local src = Core.Online[target.id]
    if src then Notify(src, L('N_LOBBY_INVITE', p.alias, l.name), 'inform') end
    return true
end)

-- ── spectate ────────────────────────────────────────────────────────────
Handle('lobby:spectate', function(src, p, d)
    if not Config.Spectate.Enabled then return nil, 'ERR_UNKNOWN' end
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    if not Lobby.LIVE[l.status] then return nil, 'SPECTATE_NOT_LIVE' end
    local part = l.participants[p.id]
    if part and Lobby.ACTIVE[part.status] then return nil, 'SPECTATE_RACING' end
    local other = Core.Lobbies[Core.Active[p.id] or '']
    if other and other ~= l and other.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_IN' end
    local allowed = part ~= nil or l.owner.id == p.id or (Config.Spectate.Anyone and not l.practice)
    if not allowed then return nil, 'ERR_NO_PERMISSION' end
    if l.status == LobbyStatus.RACING and l:Count(PStatus.RACING) == 0 then return nil, 'SPECTATE_NOT_LIVE' end
    for _, other2 in pairs(Core.Lobbies) do other2.spectators[src] = nil end
    l:AddSpectator(src, p.id)
    return true
end)

Handle('lobby:unspectate', function(src)
    for _, l in pairs(Core.Lobbies) do l.spectators[src] = nil end
    return true
end)

-- ── bets ────────────────────────────────────────────────────────────────
Handle('bet:place', function(src, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    local ok, e = l:PlaceBet(src, p, tonumber(d.racer) or 0, d.amount)
    if not ok then return nil, e end
    return l:Dto(p.id)
end)

Handle('bet:cancel', function(_, p, d)
    local l, err = lobbyOf(d.id)
    if not l then return nil, err end
    local ok, e = l:CancelBet(p.id)
    if not ok then return nil, e end
    return l:Dto(p.id)
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

-- Modded vehicle found by the racer's client
RegisterNetEvent('nzr:race:flag', function(reason, info)
    if not Config.AntiCheat.ModdedVehicles then return end
    local l, p = racing(source)
    if l then l:Flag(p.id, tostring(reason or 'modded'):sub(1, 24), type(info) == 'string' and info:sub(1, 120) or nil) end
end)
