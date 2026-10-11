if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby: one race from creation to results. Server authoritative - every checkpoint is
    validated against the racer's real position and timing before it counts.
    Also: practice runs, spectators, sector splits, elimination, pink slips, bets, swap detection.
]]

Lobby = {}
Lobby.__index = Lobby

local ACTIVE = { [PStatus.MOBILIZING] = true, [PStatus.COUNTDOWN] = true, [PStatus.RACING] = true }
local LIVE = { [LobbyStatus.MOBILIZING] = true, [LobbyStatus.COUNTDOWN] = true, [LobbyStatus.RACING] = true }
Lobby.ACTIVE, Lobby.LIVE = ACTIVE, LIVE
local CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function newId()
    for _ = 1, 20 do
        local id = ''
        for _ = 1, 6 do
            local i = math.random(1, #CHARS)
            id = id .. CHARS:sub(i, i)
        end
        if not Core.Lobbies[id] then return id end
    end
    return tostring(os.time())
end

local function now() return GetGameTimer() end

function Lobby.New(owner, data, track)
    local self = setmetatable({}, Lobby)
    self.id = newId()
    self.name = data.name
    self.type = data.type
    self.mode = data.mode
    self.class = data.class
    self.laps = data.laps
    self.circuit = track.type == TrackType.CIRCUIT and data.laps > 0
    self.max = data.max
    self.ghost = data.ghost
    self.wager = data.wager
    self.currency = data.currency
    self.password = data.password
    self.featured = data.featured
    self.practice = data.practice == true
    self.hostOnly = data.hostOnly == true
    self.autoAccept = data.autoAccept == true
    self.pinkSlip = data.pinkSlip == true
    self.quick = data.quick == true
    self.owner = { id = owner.id, alias = owner.alias }
    self.ownerCrew = owner.crewId
    self.track = track
    self.route = NZR.BuildRoute(#track.gates, data.laps, self.circuit)
    self.status = LobbyStatus.PENDING
    self.participants = {}
    self.order = {}
    self.paid = 0
    self.created = os.time()
    self.results = nil
    self.invites = {}       -- [profileId] = inviter profileId
    self.spectators = {}    -- [source] = profileId
    self.bets = {}          -- { pid, alias, racer, amount }
    self.elimNext = 1
    Core.Lobbies[self.id] = self
    if self.hostOnly then Core.Active[owner.id] = self.id end
    return self
end

-- ── helpers ─────────────────────────────────────────────────────────────
function Lobby:Each(fn, status)
    for _, id in ipairs(self.order) do
        local part = self.participants[id]
        if part and (not status or part.status == status) then fn(part) end
    end
end

function Lobby:Count(status)
    local n = 0
    self:Each(function() n = n + 1 end, status)
    return n
end

function Lobby:Send(part, event, data)
    local src = Core.Online[part.id]
    if src then TriggerClientEvent('nzr:race', src, event, data) end
end

function Lobby:SendAll(event, data, filter)
    self:Each(function(part)
        if not filter or filter(part) then self:Send(part, event, data) end
    end)
end

-- Spectators who are not racers in this lobby (racers already get SendAll)
function Lobby:SendWatchers(event, data)
    for src, pid in pairs(self.spectators) do
        if not self.participants[pid] then TriggerClientEvent('nzr:race', src, event, data) end
    end
end

function Lobby:Crews()
    local ids, seen = {}, {}
    self:Each(function(part)
        local c = part.profile.crewId
        if c and not seen[c] then seen[c] = true ids[#ids + 1] = c end
    end)
    return ids
end

function Lobby:AverageElo(status)
    local total, n = 0, 0
    self:Each(function(part) total = total + part.profile.elo n = n + 1 end, status)
    return n > 0 and math.floor(total / n) or 0
end

function Lobby:Star()
    if self.type ~= LobbyType.RANKED or not Config.Races.AllowStarredLobbies then return false end
    return self:Count(PStatus.ACCEPTED) >= 2 and self:AverageElo(PStatus.ACCEPTED) >= Config.Races.MinimumAverageForStarredLobby
end

function Lobby:PartDto(part)
    return {
        id = part.id, alias = part.profile.alias, avatar = part.profile.avatar, color = part.profile.color, elo = part.profile.elo,
        crew = part.profile.crewId and Crews.Brief(part.profile.crewId) or nil, crewId = part.profile.crewId,
        status = part.status, vehicle = part.vehicle and { label = part.vehicle.label, class = part.vehicle.class, name = part.vehicle.name } or nil,
        position = part.position, owner = part.id == self.owner.id,
    }
end

function Lobby:BetsDto()
    if not Config.Betting.Enabled or self.practice then return nil end
    local per, pool = {}, 0
    for _, b in ipairs(self.bets) do
        pool = pool + b.amount
        per[b.racer] = (per[b.racer] or 0) + b.amount
    end
    local racers = {}
    for id, amount in pairs(per) do racers[#racers + 1] = { id = id, amount = amount } end
    return { pool = pool, count = #self.bets, racers = racers, currency = Config.Betting.Currency, cut = Config.Betting.HouseCut }
end

function Lobby:BetOf(pid)
    for i, b in ipairs(self.bets) do if b.pid == pid then return b, i end end
end

-- viewer: profile id that gets its own bet in the result
function Lobby:Dto(viewer)
    local parts = {}
    self:Each(function(part) parts[#parts + 1] = self:PartDto(part) end)
    local crews = {}
    if self.type == LobbyType.CREW then
        for _, id in ipairs(self:Crews()) do crews[#crews + 1] = Crews.Brief(id) end
    end
    local t = self.track
    local mine = viewer and self:BetOf(viewer)
    return {
        id = self.id, name = self.name, type = self.type, mode = self.mode, class = self.class, laps = self.laps,
        max = self.max, ghost = self.ghost, wager = self.wager, currency = self.currency, featured = self.featured,
        practice = self.practice, hostOnly = self.hostOnly, autoAccept = self.autoAccept, pinkSlip = self.pinkSlip, quick = self.quick,
        hasPassword = self.password ~= nil, status = self.status, owner = self.owner, created = self.created,
        star = self:Star(), avgElo = self:AverageElo(), pot = self.wager and self.wager > 0 and self.wager * math.max(self.paid, 1) or 0,
        track = { id = t.id, name = t.name, type = t.type, length = t.length, description = t.description, checkpoints = #t.gates,
            preview = t.preview, worldRecord = t.worldRecord, owner = t.owner },
        participants = parts, crews = crews, results = self.results, bets = self:BetsDto(),
        myBet = mine and { racer = mine.racer, amount = mine.amount } or nil,
        racing = self:Count(PStatus.RACING),
    }
end

-- Publish to the lobby room and the lobby list (practice runs are never listed)
function Lobby:Changed()
    local dto = self:Dto()
    Publish('lobby:' .. self.id, { event = 'update', lobby = dto })
    if not self.practice then Publish('lobbies', { event = 'upsert', lobby = dto }) end
end

function Lobby:Remove()
    if Core.Lobbies[self.id] ~= self then return end
    Core.Lobbies[self.id] = nil
    if not self.practice then Publish('lobbies', { event = 'remove', id = self.id }) end
    Publish('lobby:' .. self.id, { event = 'removed' })
end

function Lobby:ClearOwner()
    if self.hostOnly and Core.Active[self.owner.id] == self.id then Core.Active[self.owner.id] = nil end
end

-- ── wagers ──────────────────────────────────────────────────────────────
function Lobby:TakeWager(part)
    if not self.wager or self.wager <= 0 or part.paid then return true end
    local src = Core.Online[part.id]
    if not src or not Bridge.RemoveMoney(src, self.wager, self.currency, 'race wager') then return false end
    part.paid = true
    self.paid = self.paid + 1
    DiscordLog('Wagers', L('LOG_WAGER_TAKEN'), { ('%s → %s'):format(part.profile.alias, self.name), ('%d %s'):format(self.wager, self.currency) })
    return true
end

function Lobby:Refund(part)
    if not part.paid then return end
    part.paid = false
    self.paid = self.paid - 1
    Profiles.Message(part.id, MsgType.REWARD, L('MSG_REFUND', self.name), { rewardType = self.currency, amount = self.wager })
end

-- ── bets ────────────────────────────────────────────────────────────────
function Lobby:PlaceBet(src, p, racerId, amount)
    local cfg = Config.Betting
    if not cfg.Enabled or self.practice then return nil, 'ERR_INVALID' end
    if self.status ~= LobbyStatus.PENDING then return nil, 'BET_CLOSED' end
    if self.participants[p.id] then return nil, 'BET_RACER' end
    if self:BetOf(p.id) then return nil, 'BET_ALREADY' end
    local racer = self.participants[racerId]
    if not racer or racer.status ~= PStatus.ACCEPTED then return nil, 'LOBBY_PARTICIPANT_NOT_FOUND' end
    amount = math.floor(tonumber(amount) or 0)
    if amount < cfg.Min or amount > cfg.Max then return nil, 'BET_AMOUNT_RANGE' end
    if not Bridge.RemoveMoney(src, amount, cfg.Currency, 'race bet') then return nil, 'LOBBY_INSUFFICIENT_FUNDS' end
    self.bets[#self.bets + 1] = { pid = p.id, alias = p.alias, racer = racerId, amount = amount }
    DiscordLog('Bets', L('LOG_BET_PLACED'), { ('%s → %s (%s)'):format(p.alias, racer.profile.alias, self.name), ('%d %s'):format(amount, cfg.Currency) })
    self:Changed()
    return true
end

-- Refund bets through the inbox. racerId = only bets on that racer, nil = all
function Lobby:RefundBets(racerId, reason)
    local keep = {}
    for _, b in ipairs(self.bets) do
        if racerId == nil or b.racer == racerId then
            Profiles.Message(b.pid, MsgType.REWARD, L(reason or 'MSG_BET_REFUND', self.name), { rewardType = Config.Betting.Currency, amount = b.amount })
        else
            keep[#keep + 1] = b
        end
    end
    self.bets = keep
end

function Lobby:CancelBet(pid)
    local b, i = self:BetOf(pid)
    if not b then return nil, 'BET_NONE' end
    if self.status ~= LobbyStatus.PENDING then return nil, 'BET_CLOSED' end
    table.remove(self.bets, i)
    Profiles.Message(pid, MsgType.REWARD, L('MSG_BET_REFUND', self.name), { rewardType = Config.Betting.Currency, amount = b.amount })
    self:Changed()
    return true
end

-- ── membership ──────────────────────────────────────────────────────────
function Lobby:Add(p, vehicle, owner)
    local part = {
        id = p.id, profile = p, vehicle = vehicle,
        status = owner and PStatus.ACCEPTED or PStatus.QUEUING,
        k = 0, laps = {}, drift = 0, penalty = 0, respawns = 0, position = #self.order + 1,
    }
    self.participants[p.id] = part
    self.order[#self.order + 1] = p.id
    Core.Active[p.id] = self.id
    if owner then
        if not self:TakeWager(part) then
            self.participants[p.id] = nil
            table.remove(self.order)
            Core.Active[p.id] = nil
            return false, 'LOBBY_INSUFFICIENT_FUNDS'
        end
        if not self.practice then self:Send(part, 'accepted', self.track.gates[1].center) end
    end
    return true
end

-- Take someone out of the lobby entirely (pending only)
function Lobby:Drop(pid, reason)
    local part = self.participants[pid]
    if not part then return end
    if part.status == PStatus.ACCEPTED then self:Refund(part) end
    self:RefundBets(pid, 'MSG_BET_REFUND_RACER')
    self.participants[pid] = nil
    for i, id in ipairs(self.order) do if id == pid then table.remove(self.order, i) break end end
    if Core.Active[pid] == self.id then Core.Active[pid] = nil end
    self:Send(part, 'removed', reason)
end

function Lobby:Accept(pid)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.QUEUING then return nil, 'LOBBY_PARTICIPANT_NOT_FOUND' end
    local src = Core.Online[pid]
    if self.pinkSlip and (not src or not Bridge.OwnsVehicle(src, part.vehicle.plate)) then return nil, 'LOBBY_PINK_NOT_OWNED' end
    if not self:TakeWager(part) then return nil, 'LOBBY_THEY_CANT_AFFORD' end
    part.status = PStatus.ACCEPTED
    self:Send(part, 'accepted', self.track.gates[1].center)
    if src then Notify(src, L('N_ACCEPTED', self.name), 'success') end
    self:Changed()
    return true
end

function Lobby:Leave(pid)
    local part = self.participants[pid]
    if not part then
        -- host-only owner (not racing)
        if pid == self.owner.id and self.hostOnly then
            if self.status == LobbyStatus.PENDING then self:Disband('LOBBY_DISBANDED') else self:ClearOwner() end
            return true
        end
        return nil, 'LOBBY_PARTICIPANT_NOT_FOUND'
    end
    if ACTIVE[part.status] then
        self:Disqualify(pid, 'left')
        return true
    end
    if self.status ~= LobbyStatus.PENDING then
        if Core.Active[pid] == self.id then Core.Active[pid] = nil end
        return true
    end
    if pid == self.owner.id then
        self:Disband('LOBBY_DISBANDED')
        return true
    end
    self:Drop(pid, 'left')
    self:Changed()
    return true
end

function Lobby:Disconnected(pid)
    local part = self.participants[pid]
    if not part then
        if pid == self.owner.id and self.hostOnly then
            if self.status == LobbyStatus.PENDING then self:Disband('LOBBY_DISBANDED_OWNER') else self:ClearOwner() end
        end
        return
    end
    if ACTIVE[part.status] then
        self:Disqualify(pid, 'disconnect')
    elseif self.status == LobbyStatus.PENDING then
        if pid == self.owner.id then self:Disband('LOBBY_DISBANDED_OWNER')
        else self:Drop(pid, 'disconnect') self:Changed() end
    end
end

function Lobby:Disband(reason, silent)
    if self.status ~= LobbyStatus.PENDING then return end
    self.status = LobbyStatus.CANCELLED
    self:RefundBets(nil, 'MSG_BET_REFUND')
    self:Each(function(part)
        if part.status == PStatus.ACCEPTED then self:Refund(part) end
        if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
        if not silent then self:Send(part, 'removed', reason or 'LOBBY_DISBANDED') end
    end)
    self:ClearOwner()
    self:Remove()
end

-- Resource stop: every unfinished lobby pays back wagers and bets
function Lobby:Abort()
    if self.status == LobbyStatus.FINISHED or self.status == LobbyStatus.CANCELLED then return end
    self.status = LobbyStatus.CANCELLED
    self:RefundBets(nil, 'MSG_BET_REFUND')
    self:Each(function(part)
        if part.paid then self:Refund(part) end
        if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
    end)
    self:ClearOwner()
    self:ResetCulling()
end

-- ── start ───────────────────────────────────────────────────────────────
function Lobby:CanStart()
    if self.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    local accepted = self:Count(PStatus.ACCEPTED)
    if accepted < 1 then return nil, 'LOBBY_NO_RACERS' end
    if self.type == LobbyType.RANKED and accepted < Config.Races.RequiredParticipantsForRankedLobby then
        return nil, 'LOBBY_MIN_RANKED'
    end
    if self.mode == RaceMode.ELIMINATION and accepted < Config.Races.Elimination.MinRacers then return nil, 'LOBBY_MIN_ELIMINATION' end
    if self.pinkSlip and accepted < 2 then return nil, 'LOBBY_MIN_PINK' end
    if self.type == LobbyType.CREW then
        local counts = {}
        self:Each(function(part) local c = part.profile.crewId or 0 counts[c] = (counts[c] or 0) + 1 end, PStatus.ACCEPTED)
        local crews = {}
        for id, n in pairs(counts) do crews[#crews + 1] = { id = id, n = n } end
        if #crews ~= 2 then return nil, 'LOBBY_CREW_MISSING' end
        for _, c in ipairs(crews) do if c.n < Config.Races.MinCrewSize then return nil, 'LOBBY_CREW_TOO_SMALL' end end
        if not Config.Races.AllowUnevenCrewSize and crews[1].n ~= crews[2].n then return nil, 'LOBBY_CREW_UNEVEN' end
    end
    return true
end

-- Vehicle + start radius checks. Returns lists of aliases that fail
function Lobby:Precheck()
    local wrongCar, far = {}, {}
    local start = NZR.V3(self.track.gates[1].center)
    self:Each(function(part)
        local src = Core.Online[part.id]
        local ped = src and GetPlayerPed(src)
        if not ped or ped == 0 then wrongCar[#wrongCar + 1] = part.profile.alias return end
        local veh, model, plate = DrivenVehicle(src)
        local ok = veh ~= nil and plate == NZR.CleanPlate(part.vehicle.plate) and not Config.Vehicles.IsBlacklisted(model)
        if ok then
            local cls = Config.Vehicles.GetClass(model)
            -- 'auto': the class was worked out from the handling on the racer's client
            if cls == 'auto' then cls = part.vehicle.class ~= 'All' and part.vehicle.class or nil end
            ok = NZR.ClassFits(self.class, cls)
        end
        if ok and self.pinkSlip then ok = Bridge.OwnsVehicle(src, plate) end
        if ok then
            part.netId = NetworkGetNetworkIdFromEntity(veh)
            part.model = model
        else
            wrongCar[#wrongCar + 1] = part.profile.alias
        end
        if Config.Races.RequirePlayersInStartRadius and #(GetEntityCoords(ped) - start) > Config.Races.StartRadius then
            far[#far + 1] = part.profile.alias
        end
    end, PStatus.ACCEPTED)
    return wrongCar, far
end

function Lobby:Start()
    local ok, err = self:CanStart()
    if not ok then return nil, err end
    local wrongCar, far = self:Precheck()
    if #wrongCar > 0 then return nil, 'LOBBY_VEHICLE_NOT_OK', wrongCar end
    if #far > 0 then return nil, 'LOBBY_OUT_OF_REACH', far end
    if self.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end

    -- queued racers who were never accepted are removed
    local queued = {}
    self:Each(function(part) queued[#queued + 1] = part.id end, PStatus.QUEUING)
    for _, pid in ipairs(queued) do self:Drop(pid, 'LOBBY_NOT_ACCEPTED') end

    self.status = LobbyStatus.MOBILIZING
    if not self.practice then MySQL.update('UPDATE nayzeee_racing_tracks SET plays = plays + 1 WHERE id = ?', { self.track.id }) end

    -- split references: world record + each racer's personal best on this layout
    local refs = self.mode ~= RaceMode.DRIFT
    self.wrRef = refs and Tracks.Reference(self.track.id, self.circuit) or nil
    local netIds, racers = {}, {}
    self:Each(function(part)
        part.status = PStatus.MOBILIZING
        part.started = true
        part.ref = refs and Tracks.Reference(self.track.id, self.circuit, part.id) or nil
        netIds[#netIds + 1] = part.netId
        racers[#racers + 1] = { id = part.id, alias = part.profile.alias, color = part.profile.color }
    end)

    local mobilizeMs = self.practice and Config.Practice.MobilizeTimer or Config.Races.MobilizeTimer
    local wr = self.wrRef and { time = self.wrRef.time, holder = self.wrRef.holder } or nil
    self:Each(function(part)
        local pb = part.ref and (self.circuit and { lap = part.ref.time } or { time = part.ref.time }) or nil
        self:Send(part, 'mobilize', {
            id = self.id, name = self.name, mode = self.mode, type = self.type, laps = self.laps, circuit = self.circuit,
            gates = self.track.gates, route = self.route, ghost = self.ghost and netIds or nil, myNet = part.netId,
            mobilizeMs = mobilizeMs, countdownMs = Config.Races.CountdownTimer, practice = self.practice, pinkSlip = self.pinkSlip,
            track = { name = self.track.name, type = self.track.type, length = self.track.length, worldRecord = wr },
            racers = racers, pb = pb, me = part.id, plate = part.vehicle.plate,
        })
    end)

    local target = Config.Notifications.LobbyStarting
    if not self.practice and target and target ~= 'participants' then
        NotifyGroup(target, L('N_LOBBY_STARTING', self.name), 'inform')
    end
    self:Changed()

    -- a host who is not racing watches from the start
    if self.hostOnly and Config.Spectate.Enabled then
        local src = Core.Online[self.owner.id]
        if src then self:AddSpectator(src, self.owner.id) end
    end
    self:PositionLoop()
    SetTimeout(mobilizeMs, function() self:Countdown() end)
    return true
end

function Lobby:Countdown()
    if self.status ~= LobbyStatus.MOBILIZING then return end
    -- whoever drove off from the start line during the line-up is out
    if Config.Races.RequirePlayersInStartRadius then
        local start = NZR.V3(self.track.gates[1].center)
        local away = {}
        self:Each(function(part)
            local src = Core.Online[part.id]
            local ped = src and GetPlayerPed(src)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - start) > Config.Races.StartRadius * 1.5 then away[#away + 1] = part.id end
        end, PStatus.MOBILIZING)
        for _, pid in ipairs(away) do self:Disqualify(pid, 'start') end
        if self.status ~= LobbyStatus.MOBILIZING then return end
    end
    self.status = LobbyStatus.COUNTDOWN
    self:Each(function(part) part.status = PStatus.COUNTDOWN end, PStatus.MOBILIZING)
    self:SendAll('countdown', Config.Races.CountdownTimer, function(part) return part.status == PStatus.COUNTDOWN end)
    SetTimeout(Config.Races.CountdownTimer, function() self:Go() end)
end

function Lobby:Go()
    if self.status ~= LobbyStatus.COUNTDOWN then return end
    self.status = LobbyStatus.RACING
    self.startTime = now()
    self:Each(function(part)
        part.status = PStatus.RACING
        part.lapStart = self.startTime
        part.lastGateAt = self.startTime
        part.splits, part.curLap = {}, {}
    end, PStatus.COUNTDOWN)
    self:SendAll('start', { t = self.startTime }, function(part) return part.status == PStatus.RACING end)
    self:Changed()
    self:CheckDone()
end

-- ── racing ──────────────────────────────────────────────────────────────
function Lobby:Gate(src, pid, k)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.RACING or self.status ~= LobbyStatus.RACING then return end
    if k ~= part.k + 1 then
        -- client is ahead of the server (a gate was rejected): bring it back
        if k > part.k + 1 then self:Send(part, 'resync', part.k) end
        return
    end
    local idx = self.route[k]
    local gate = idx and self.track.gates[idx]
    if not gate then return end

    local t = now()
    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    local center = NZR.V3(gate.center)
    local half = #(NZR.V3(gate.left) - NZR.V3(gate.right)) * 0.5
    local d2 = #(vector2(pos.x, pos.y) - vector2(center.x, center.y))
    if d2 > half + Config.Races.CheckpointTolerance then
        Log('warn', '%s gate %d rejected: %.1fm from gate', part.profile.alias, k, d2)
        self:Send(part, 'resync', part.k)
        return
    end
    local prevIdx = k > 1 and self.route[k - 1] or 1
    local seg = #(center - NZR.V3(self.track.gates[prevIdx].center))
    local dt = math.max(1, t - (part.lastGateAt or self.startTime)) / 1000
    if seg / dt > Config.Races.MaxCheckpointSpeed then
        Log('warn', '%s gate %d rejected: %.0f m/s', part.profile.alias, k, seg / dt)
        self:Send(part, 'resync', part.k)
        return
    end

    part.k = k
    part.lastGateAt = t
    local elapsed = t - self.startTime + part.penalty
    part.splits[k] = elapsed

    -- splits: circuits compare inside the lap against the best lap, sprints the whole run
    local value, slot = elapsed, k
    local lapDone = self.circuit and idx == 1
    if self.circuit then
        value = t - (part.lapStart or self.startTime)
        part.curLap[#part.curLap + 1] = value
        slot = #part.curLap
    end
    if Config.Splits.Enabled and self.mode ~= RaceMode.DRIFT then
        local pbS = part.ref and part.ref.splits
        local wrS = self.wrRef and self.wrRef.splits
        local d = {
            k = k,
            pb = type(pbS) == 'table' and pbS[slot] and (value - pbS[slot]) or nil,
            wr = type(wrS) == 'table' and wrS[slot] and (value - wrS[slot]) or nil,
        }
        if d.pb or d.wr then self:Send(part, 'split', d) end
    end

    if lapDone then
        local lap = value
        part.laps[#part.laps + 1] = lap
        part.lapStart = t
        if not part.bestLap or lap < part.bestLap then
            part.bestLap = lap
            part.bestLapSplits = part.curLap
        end
        part.curLap = {}
        self:Send(part, 'lap', { time = lap, best = part.bestLap, lap = #part.laps })
        self:EliminationSweep()
    end
    if k >= #self.route then self:Finish(part) end
end

function Lobby:Drift(pid, total)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.RACING or self.mode ~= RaceMode.DRIFT then return end
    local t = now()
    local dt = math.max(0.1, (t - (part.driftAt or self.startTime)) / 1000)
    local cap = part.drift + dt * 4000
    part.drift = math.max(part.drift, math.min(math.floor(tonumber(total) or 0), cap))
    part.driftAt = t
end

function Lobby:Respawned(pid)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.RACING then return end
    local t = now()
    if part.respawnAt and t - part.respawnAt < Config.Races.Respawn.Cooldown - 500 then return end
    part.respawnAt = t
    part.respawns = part.respawns + 1
    part.penalty = part.penalty + (Config.Races.Respawn.Penalty or 0)
    part.lastGateAt = t
end

function Lobby:Finish(part)
    if part.status ~= PStatus.RACING then return end
    local t = now()
    part.status = PStatus.FINISHED
    local time = t - self.startTime + part.penalty
    local best = part.bestLap
    local score = 0
    if self.mode == RaceMode.DRIFT then
        score = math.floor((part.drift * 0.9) / ((math.max(time, 1000) / 1000) ^ 0.7))
    elseif self.mode == RaceMode.TIME_TRIAL then
        score = best or time
    else
        score = time
    end
    part.result = { time = time, bestLap = best, score = score, drift = part.drift, penalty = part.penalty, respawns = part.respawns }

    -- personal best / world record (circuits: best lap, sprints: total time)
    local mark = self.mode ~= RaceMode.DRIFT and (self.circuit and best or (not self.circuit and time)) or nil
    if mark then
        local pb = part.ref and part.ref.time
        if not pb or mark < pb then part.result.newPb = true end
        local wr = self.wrRef and self.wrRef.time
        if not wr or mark < wr then
            part.result.newWr = true
            self.wrRef = { time = mark, splits = self.circuit and part.bestLapSplits or part.splits, holder = { id = part.id, alias = part.profile.alias } }
            if Config.Splits.AnnounceRecords then
                NotifyGroup('profiles', L('N_NEW_WR', part.profile.alias, self.track.name, NZR.Clock(mark)), 'success')
            end
        end
    end

    if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
    self:Send(part, 'finished', part.result)
    if not self.deadline then
        self.deadline = true
        local ms = math.max(math.floor(time / 1.5), Config.Races.Deadline)
        self:SendAll('deadline', ms, function(p) return p.status == PStatus.RACING end)
        SetTimeout(ms, function()
            if self.status ~= LobbyStatus.RACING then return end
            local late = {}
            self:Each(function(p) late[#late + 1] = p.id end, PStatus.RACING)
            for _, pid in ipairs(late) do self:Disqualify(pid, 'deadline') end
        end)
    end
    self:CheckDone()
end

function Lobby:Disqualify(pid, reason)
    local part = self.participants[pid]
    if not part or not ACTIVE[part.status] then return end
    part.status = PStatus.DISQUALIFIED
    part.dqReason = reason
    part.result = { dnf = true, reason = reason }
    if Core.Active[pid] == self.id then Core.Active[pid] = nil end
    self:Send(part, 'dq', reason)
    if self.status == LobbyStatus.RACING then
        self:EliminationSweep()
        self:CheckDone()
    else
        -- disqualified before the start: the race still runs for everyone else
        local left = self:Count(PStatus.MOBILIZING) + self:Count(PStatus.COUNTDOWN)
        if left == 0 then self:Finalize() end
    end
end

-- Anti-cheat report (modded vehicle) from the racer's client
function Lobby:Flag(pid, reason, info)
    local part = self.participants[pid]
    if not part or not ACTIVE[part.status] then return end
    local src = Core.Online[pid]
    Log('warn', '%s flagged: %s %s', part.profile.alias, reason, tostring(info or ''))
    DiscordLog('AntiCheat', L('LOG_AC_FLAG'), { ('**%s** · %s'):format(part.profile.alias, self.name), ('%s %s'):format(reason, tostring(info or '')) })
    self:Disqualify(pid, 'modded')
    if Config.AntiCheat.Action == 'kick' and src then DropPlayer(src, L('AC_KICK')) end
end

function Lobby:CheckDone()
    if self.status ~= LobbyStatus.RACING then return false end
    if self:Count(PStatus.RACING) > 0 then return false end
    self:Finalize()
    return true
end

-- ── elimination ─────────────────────────────────────────────────────────
-- Once every racer but one has completed lap L, the one left behind is out. Last one standing wins.
function Lobby:Eliminate(part, lap)
    part.elimLap = lap
    local alias = part.profile.alias
    self:Disqualify(part.id, 'eliminated')
    self:SendAll('eliminated', { alias = alias, lap = lap })
    self:SendWatchers('eliminated', { alias = alias, lap = lap })
end

function Lobby:EliminationSweep()
    if self.mode ~= RaceMode.ELIMINATION or self.status ~= LobbyStatus.RACING or self.sweeping then return end
    self.sweeping = true
    while self.elimNext < self.laps do
        local L = self.elimNext
        local active, behind = {}, {}
        self:Each(function(p)
            active[#active + 1] = p
            if #p.laps < L then behind[#behind + 1] = p end
        end, PStatus.RACING)
        if #active <= 1 or #behind > 1 then break end
        self.elimNext = L + 1
        if #behind == 1 then self:Eliminate(behind[1], L) end
    end
    self.sweeping = false
    if self.status ~= LobbyStatus.RACING or self.elimNext <= 1 then return end
    local active = {}
    self:Each(function(p) active[#active + 1] = p end, PStatus.RACING)
    if #active == 1 and self:Count(PStatus.FINISHED) == 0 then self:Finish(active[1]) end
end

-- ── spectators ──────────────────────────────────────────────────────────
function Lobby:SpectateInit()
    local racers = {}
    self:Each(function(part)
        if part.started then racers[#racers + 1] = { id = part.id, alias = part.profile.alias, color = part.profile.color } end
    end)
    return {
        id = self.id, name = self.name, track = self.track.name, mode = self.mode, laps = self.circuit and self.laps or 0,
        circuit = self.circuit, total = #self.route, racers = racers, board = self.board,
    }
end

-- Racers stay streamed for spectators who are far away (OneSync culling)
function Lobby:EnsureCulling()
    local radius = Config.Spectate.CullingRadius or 0
    if radius <= 0 then return end
    self:Each(function(part)
        if not ACTIVE[part.status] then return end
        local src = Core.Online[part.id]
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 and part.culledPed ~= ped then SetEntityDistanceCullingRadius(ped, radius) part.culledPed = ped end
        local veh = part.netId and NetworkGetEntityFromNetworkId(part.netId)
        if veh and veh ~= 0 and part.culledVeh ~= veh then SetEntityDistanceCullingRadius(veh, radius) part.culledVeh = veh end
    end)
end

function Lobby:ResetCulling()
    self:Each(function(part)
        for _, key in ipairs({ 'culledPed', 'culledVeh' }) do
            local ent = part[key]
            if ent and DoesEntityExist(ent) then SetEntityDistanceCullingRadius(ent, 0.0) end
            part[key] = nil
        end
    end)
end

function Lobby:AddSpectator(src, pid)
    self.spectators[src] = pid
    self:EnsureCulling()
    self:PositionLoop()
    TriggerClientEvent('nzr:race', src, 'spectate', self:SpectateInit())
end

-- Where every racer is, for spectator cameras
function Lobby:Feed()
    local list = {}
    self:Each(function(part)
        if not ACTIVE[part.status] then return end
        local src = Core.Online[part.id]
        local ped = src and GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            list[#list + 1] = { id = part.id, net = part.netId, x = math.floor(c.x * 10) / 10, y = math.floor(c.y * 10) / 10, z = math.floor(c.z * 10) / 10,
                h = math.floor(GetEntityHeading(ped)) }
        end
    end)
    for src in pairs(self.spectators) do TriggerClientEvent('nzr:race', src, 'feed', list) end
end

-- Racer changed car mid-race (model or plate differs from the one checked at the start)
function Lobby:SwapCheck()
    local swapped = {}
    self:Each(function(part)
        local src = Core.Online[part.id]
        if not src or not part.model then return end
        local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
        if veh == 0 then return end
        local model, plate = GetEntityModel(veh), NZR.CleanPlate(GetVehicleNumberPlateText(veh))
        if model ~= part.model or plate ~= NZR.CleanPlate(part.vehicle.plate) then
            swapped[#swapped + 1] = { part = part, plate = plate }
        else
            local net = NetworkGetNetworkIdFromEntity(veh)
            if net ~= part.netId then part.netId = net if next(self.spectators) then self:EnsureCulling() end end
        end
    end, PStatus.RACING)
    for _, s in ipairs(swapped) do
        Log('warn', '%s swapped vehicle (%s -> %s)', s.part.profile.alias, s.part.vehicle.plate, s.plate)
        DiscordLog('AntiCheat', L('LOG_AC_SWAP'), { ('**%s** · %s'):format(s.part.profile.alias, self.name), ('%s → %s'):format(s.part.vehicle.plate, s.plate) })
        self:Disqualify(s.part.id, 'swap')
    end
end

-- Positions (most gates passed, then closest to the next gate), spectator feed and swap checks.
-- Runs from the line-up until the race is over.
function Lobby:PositionLoop()
    if self.looping then return end
    self.looping = true
    CreateThread(function()
        local last, lastSent, lastSwap = '', 0, 0
        while LIVE[self.status] do
            local t = now()
            local n = 0
            if self.status == LobbyStatus.RACING then
                local finished, racing = {}, {}
                self:Each(function(part)
                    if part.status == PStatus.FINISHED then
                        finished[#finished + 1] = part
                    elseif part.status == PStatus.RACING then
                        local src = Core.Online[part.id]
                        local nextIdx = self.route[part.k + 1] or self.route[#self.route]
                        local c = NZR.V3(self.track.gates[nextIdx].center)
                        part.dist = src and #(GetEntityCoords(GetPlayerPed(src)) - c) or 99999
                        racing[#racing + 1] = part
                    end
                end)
                local drift = self.mode == RaceMode.DRIFT
                table.sort(finished, function(a, b)
                    if drift then return a.result.score > b.result.score end
                    return a.result.score < b.result.score
                end)
                table.sort(racing, function(a, b)
                    if a.k ~= b.k then return a.k > b.k end
                    return a.dist < b.dist
                end)
                for i, part in ipairs(finished) do part.position = i end
                for i, part in ipairs(racing) do part.position = #finished + i end
                local board, key = {}, {}
                self:Each(function(part)
                    if not part.started then return end
                    board[#board + 1] = { id = part.id, alias = part.profile.alias, color = part.profile.color, pos = part.position,
                        status = part.status, k = part.k, drift = drift and part.drift or nil, out = part.dqReason == 'eliminated' or nil,
                        lap = self.circuit and math.min(#part.laps + 1, self.laps) or nil }
                    key[#key + 1] = part.id .. ':' .. part.position .. ':' .. part.status
                end)
                key = table.concat(key, ',')
                self.board = board
                if key ~= last or t - lastSent > 2000 then
                    last, lastSent = key, t
                    self:SendAll('positions', board)
                    self:SendWatchers('positions', board)
                end
                n = #racing
            end
            if next(self.spectators) then self:Feed() end
            if self.status == LobbyStatus.RACING and Config.AntiCheat.SwapDetection and t - lastSwap > 1000 then
                lastSwap = t
                self:SwapCheck()
            end
            Wait(n <= 4 and 300 or n <= 8 and 500 or 800)
        end
        self.looping = false
    end)
end

-- ── results ─────────────────────────────────────────────────────────────
local function resultStatus(part)
    if part.status == PStatus.FINISHED then return 'finished' end
    if part.dqReason == 'eliminated' then return 'eliminated' end
    return 'disqualified'
end

function Lobby:Finalize()
    if self.status == LobbyStatus.FINISHED then return end
    self.status = LobbyStatus.FINISHED
    self:ResetCulling()
    local finished, eliminated, dnf = {}, {}, {}
    self:Each(function(part)
        if part.status == PStatus.FINISHED then finished[#finished + 1] = part
        elseif part.dqReason == 'eliminated' then eliminated[#eliminated + 1] = part
        else dnf[#dnf + 1] = part end
    end)
    if self.mode == RaceMode.DRIFT then
        table.sort(finished, function(a, b) return a.result.score > b.result.score end)
    else
        table.sort(finished, function(a, b) return a.result.score < b.result.score end)
    end
    table.sort(eliminated, function(a, b)
        if (a.elimLap or 0) ~= (b.elimLap or 0) then return (a.elimLap or 0) > (b.elimLap or 0) end
        return (a.k or 0) > (b.k or 0)
    end)
    table.sort(dnf, function(a, b) return (a.k or 0) > (b.k or 0) end)

    -- classified = finished + eliminated (elimination places count like finishes)
    local classified, ordered = {}, {}
    for _, part in ipairs(finished) do classified[#classified + 1] = part end
    for _, part in ipairs(eliminated) do classified[#classified + 1] = part end
    for i, part in ipairs(classified) do
        part.position = i
        part.winnerStatus = i == 1 and 'winner' or (i <= Config.Rewards.Winners and 'topX' or 'participant')
        ordered[#ordered + 1] = part
    end
    for _, part in ipairs(dnf) do
        part.position = #ordered + 1
        ordered[#ordered + 1] = part
    end

    local laps = self.circuit and self.laps or 1
    local total = #self.route
    for _, part in ipairs(ordered) do
        local fraction = part.status == PStatus.FINISHED and 1 or (total > 0 and part.k / total or 0)
        part.distance = math.floor(self.track.length * laps * fraction)
    end

    local crewScore
    if not self.practice then
        Rewards.Wagers(self, classified)
        if self.type == LobbyType.RANKED then
            Rewards.Ranked(self, classified)
            Rewards.Elo(self, ordered)
        end
        Rewards.Xp(self, classified)
        crewScore = self.type == LobbyType.CREW and Rewards.CrewScore(self, ordered) or nil
        Rewards.PinkSlips(self, ordered)
        Rewards.Bets(self, ordered)
    end

    local results = {}
    for _, part in ipairs(ordered) do
        local r = part.result or {}
        results[#results + 1] = {
            id = part.id, alias = part.profile.alias, avatar = part.profile.avatar, color = part.profile.color,
            crew = part.profile.crewId and Crews.Brief(part.profile.crewId) or nil,
            position = part.position, status = resultStatus(part), time = r.time, bestLap = r.bestLap, score = r.score, drift = r.drift,
            penalty = r.penalty, vehicle = part.vehicle and part.vehicle.label, eloDelta = part.eloDelta, elo = part.profile.elo,
            payout = part.payout, reason = part.dqReason, newPb = r.newPb, newWr = r.newWr, pinkWon = part.pinkWon, pinkLost = part.pinkLost,
        }
    end
    self.results = { list = results, mode = self.mode, crews = crewScore, practice = self.practice }
    self:Persist(ordered)

    local practice = self.practice and { trackId = self.track.id, laps = self.laps, mode = self.mode } or nil
    local payload = { results = self.results, track = self.track.name, lobby = self.name, practice = practice }
    self:Each(function(part)
        if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
        payload.me = part.id
        self:Send(part, 'results', payload)
    end)
    payload.me = nil
    self:SendWatchers('results', payload)
    self.spectators = {}
    self:ClearOwner()
    self:Changed()
    Profiles.InvalidateBoard()
    CreateThread(function()
        local ok, err = pcall(Challenges.Record, self, ordered)
        if not ok then Log('error', 'Challenges failed: %s', tostring(err)) end
    end)

    if not self.practice then
        local lines = { ('**%s** · %s · %s'):format(self.name, self.track.name, self.mode) }
        for _, r in ipairs(results) do
            lines[#lines + 1] = r.status == 'finished' and ('`%d.` %s — %.3fs'):format(r.position, r.alias, (r.time or 0) / 1000)
                or r.status == 'eliminated' and ('`%d.` %s — OUT (lap %d)'):format(r.position, r.alias, self.participants[r.id].elimLap or 0)
                or ('`DNF` %s'):format(r.alias)
        end
        DiscordLog('Results', L('LOG_RACE_RESULT'), lines)
    end

    local keep = self.practice and 0 or (Config.Races.FinishedLobbyVisibilityTime or 0)
    if keep > 0 then SetTimeout(keep, function() self:Remove() end) else self:Remove() end
end

function Lobby:Persist(ordered)
    local laps = self.circuit and self.laps or 0
    local pending = #ordered
    local trackId = self.track.id
    local function done()
        pending = pending - 1
        if pending <= 0 then Tracks.InvalidateRecord(trackId) end
    end
    if pending == 0 then Tracks.InvalidateRecord(trackId) return end
    for _, part in ipairs(ordered) do
        local r = part.result or {}
        local finished = part.status == PStatus.FINISHED
        local splits = finished and self.mode ~= RaceMode.DRIFT and (self.circuit and part.bestLapSplits or part.splits) or nil
        MySQL.insert([[INSERT INTO nayzeee_racing_history (lobby_id, track_id, profile_id, position, status, time_ms, best_lap_ms, distance, mode, type, vehicle, elo_delta, laps, splits)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            self.id, trackId, part.id, math.min(part.position, 255), resultStatus(part),
            r.time, r.bestLap, part.distance or 0, self.mode, self.practice and LobbyType.PRACTICE or self.type, part.vehicle and part.vehicle.label, part.eloDelta,
            laps, splits and json.encode(splits) or nil,
        }, function()
            Profiles.Invalidate(part.id)
            done()
        end)
    end
end
