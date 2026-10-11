if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby: one race from creation to results. Server authoritative - every checkpoint is
    validated against the racer's real position and timing before it counts.
]]

Lobby = {}
Lobby.__index = Lobby

local ACTIVE = { [PStatus.MOBILIZING] = true, [PStatus.COUNTDOWN] = true, [PStatus.RACING] = true }
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
    Core.Lobbies[self.id] = self
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

function Lobby:Dto()
    local parts = {}
    self:Each(function(part) parts[#parts + 1] = self:PartDto(part) end)
    local crews = {}
    if self.type == LobbyType.CREW then
        for _, id in ipairs(self:Crews()) do crews[#crews + 1] = Crews.Brief(id) end
    end
    local t = self.track
    return {
        id = self.id, name = self.name, type = self.type, mode = self.mode, class = self.class, laps = self.laps,
        max = self.max, ghost = self.ghost, wager = self.wager, currency = self.currency, featured = self.featured,
        hasPassword = self.password ~= nil, status = self.status, owner = self.owner, created = self.created,
        star = self:Star(), avgElo = self:AverageElo(), pot = self.wager and self.wager > 0 and self.wager * math.max(self.paid, 1) or 0,
        track = { id = t.id, name = t.name, type = t.type, length = t.length, description = t.description, checkpoints = #t.gates,
            preview = t.preview, worldRecord = t.worldRecord, owner = t.owner },
        participants = parts, crews = crews, results = self.results,
    }
end

-- Publish to the lobby room and the lobby list
function Lobby:Changed()
    local dto = self:Dto()
    Publish('lobby:' .. self.id, { event = 'update', lobby = dto })
    Publish('lobbies', { event = 'upsert', lobby = dto })
end

function Lobby:Remove()
    Core.Lobbies[self.id] = nil
    Publish('lobbies', { event = 'remove', id = self.id })
    Publish('lobby:' .. self.id, { event = 'removed' })
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
        self:Send(part, 'accepted', self.track.gates[1].center)
    end
    return true
end

-- Take someone out of the lobby entirely (pending only)
function Lobby:Drop(pid, reason)
    local part = self.participants[pid]
    if not part then return end
    if part.status == PStatus.ACCEPTED then self:Refund(part) end
    self.participants[pid] = nil
    for i, id in ipairs(self.order) do if id == pid then table.remove(self.order, i) break end end
    if Core.Active[pid] == self.id then Core.Active[pid] = nil end
    self:Send(part, 'removed', reason)
end

function Lobby:Accept(pid)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.QUEUING then return nil, 'LOBBY_PARTICIPANT_NOT_FOUND' end
    if not self:TakeWager(part) then return nil, 'LOBBY_THEY_CANT_AFFORD' end
    part.status = PStatus.ACCEPTED
    self:Send(part, 'accepted', self.track.gates[1].center)
    local src = Core.Online[pid]
    if src then Notify(src, L('N_ACCEPTED', self.name), 'success') end
    self:Changed()
    return true
end

function Lobby:Leave(pid)
    local part = self.participants[pid]
    if not part then return nil, 'LOBBY_PARTICIPANT_NOT_FOUND' end
    if ACTIVE[part.status] then
        self:Disqualify(pid, 'left')
        return true
    end
    if self.status ~= LobbyStatus.PENDING then
        Core.Active[pid] = nil
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
    if not part then return end
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
    self:Each(function(part)
        if part.status == PStatus.ACCEPTED then self:Refund(part) end
        if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
        if not silent then self:Send(part, 'removed', reason or 'LOBBY_DISBANDED') end
    end)
    self:Remove()
end

-- ── start ───────────────────────────────────────────────────────────────
function Lobby:CanStart()
    if self.status ~= LobbyStatus.PENDING then return nil, 'LOBBY_ALREADY_STARTED' end
    local accepted = self:Count(PStatus.ACCEPTED)
    if self.type == LobbyType.RANKED and accepted < Config.Races.RequiredParticipantsForRankedLobby then
        return nil, 'LOBBY_MIN_RANKED'
    end
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

-- Vehicle + start radius checks. Returns list of aliases that fail
function Lobby:Precheck()
    local wrongCar, far = {}, {}
    local start = NZR.V3(self.track.gates[1].center)
    self:Each(function(part)
        local src = Core.Online[part.id]
        local ped = src and GetPlayerPed(src)
        if not ped or ped == 0 then wrongCar[#wrongCar + 1] = part.profile.alias return end
        local veh = GetVehiclePedIsIn(ped, false)
        local ok = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
        if ok then
            local model = GetEntityModel(veh)
            ok = NZR.CleanPlate(GetVehicleNumberPlateText(veh)) == NZR.CleanPlate(part.vehicle.plate)
                and not Config.Vehicles.IsBlacklisted(model)
                and NZR.ClassFits(self.class, Config.Vehicles.GetClass(model))
        end
        if ok then part.netId = NetworkGetNetworkIdFromEntity(veh) else wrongCar[#wrongCar + 1] = part.profile.alias end
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

    -- queued racers who were never accepted are removed
    local queued = {}
    self:Each(function(part) queued[#queued + 1] = part.id end, PStatus.QUEUING)
    for _, pid in ipairs(queued) do self:Drop(pid, 'LOBBY_NOT_ACCEPTED') end

    self.status = LobbyStatus.MOBILIZING
    MySQL.update('UPDATE nayzeee_racing_tracks SET plays = plays + 1 WHERE id = ?', { self.track.id })

    local netIds, racers = {}, {}
    self:Each(function(part)
        part.status = PStatus.MOBILIZING
        netIds[#netIds + 1] = part.netId
        racers[#racers + 1] = { id = part.id, alias = part.profile.alias, color = part.profile.color }
    end)

    local gates = self.track.gates
    local pbRows = MySQL.query.await([[SELECT profile_id, MIN(NULLIF(time_ms, 0)) AS best, MIN(NULLIF(best_lap_ms, 0)) AS lap
        FROM nayzeee_racing_history WHERE track_id = ? AND status = 'finished' AND mode <> 'drift' GROUP BY profile_id]], { self.track.id }) or {}
    local pbs = {}
    for _, r in ipairs(pbRows) do pbs[r.profile_id] = { time = r.best, lap = r.lap } end

    self:Each(function(part)
        self:Send(part, 'mobilize', {
            id = self.id, name = self.name, mode = self.mode, type = self.type, laps = self.laps, circuit = self.circuit,
            gates = gates, route = self.route, ghost = self.ghost and netIds or nil, myNet = part.netId,
            mobilizeMs = Config.Races.MobilizeTimer, countdownMs = Config.Races.CountdownTimer,
            track = { name = self.track.name, type = self.track.type, length = self.track.length, worldRecord = self.track.worldRecord },
            racers = racers, pb = pbs[part.id], me = part.id, plate = part.vehicle.plate,
        })
    end)

    local target = Config.Notifications.LobbyStarting
    if target == 'participants' then
        -- racers already get the race HUD
    elseif target then
        NotifyGroup(target, L('N_LOBBY_STARTING', self.name), 'inform')
    end
    self:Changed()

    SetTimeout(Config.Races.MobilizeTimer, function() self:Countdown() end)
    return true
end

function Lobby:Countdown()
    if self.status ~= LobbyStatus.MOBILIZING then return end
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
    end, PStatus.COUNTDOWN)
    self:SendAll('start', { t = self.startTime }, function(part) return part.status == PStatus.RACING end)
    self:Changed()
    if not self:CheckDone() then self:PositionLoop() end
end

-- ── racing ──────────────────────────────────────────────────────────────
function Lobby:Gate(src, pid, k)
    local part = self.participants[pid]
    if not part or part.status ~= PStatus.RACING or self.status ~= LobbyStatus.RACING then return end
    if k ~= part.k + 1 then return end
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
    if self.circuit and idx == 1 then
        local lap = t - (part.lapStart or self.startTime)
        part.laps[#part.laps + 1] = lap
        part.lapStart = t
        local best
        for _, l in ipairs(part.laps) do if not best or l < best then best = l end end
        self:Send(part, 'lap', { time = lap, best = best, lap = #part.laps })
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

local function bestOf(list)
    local b
    for _, v in ipairs(list) do if not b or v < b then b = v end end
    return b
end

function Lobby:Finish(part)
    local t = now()
    part.status = PStatus.FINISHED
    local time = t - self.startTime + part.penalty
    local best = bestOf(part.laps)
    local score = 0
    if self.mode == RaceMode.DRIFT then
        score = math.floor((part.drift * 0.9) / ((math.max(time, 1000) / 1000) ^ 0.7))
    elseif self.mode == RaceMode.TIME_TRIAL then
        score = best or time
    else
        score = time
    end
    part.result = { time = time, bestLap = best, score = score, drift = part.drift, penalty = part.penalty, respawns = part.respawns }
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
        self:CheckDone()
    else
        -- disqualified before the start: the race still runs for everyone else
        local left = self:Count(PStatus.MOBILIZING) + self:Count(PStatus.COUNTDOWN)
        if left == 0 then self:Finalize() end
    end
end

function Lobby:CheckDone()
    if self.status ~= LobbyStatus.RACING then return false end
    if self:Count(PStatus.RACING) > 0 then return false end
    self:Finalize()
    return true
end

-- Positions: most gates passed, then closest to the next gate
function Lobby:PositionLoop()
    CreateThread(function()
        local last = ''
        local lastSent = 0
        while self.status == LobbyStatus.RACING do
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
            table.sort(finished, function(a, b) return a.result.time < b.result.time end)
            table.sort(racing, function(a, b)
                if a.k ~= b.k then return a.k > b.k end
                return a.dist < b.dist
            end)
            local board, key = {}, {}
            for i, part in ipairs(finished) do part.position = i end
            for i, part in ipairs(racing) do part.position = #finished + i end
            self:Each(function(part)
                board[#board + 1] = { id = part.id, alias = part.profile.alias, color = part.profile.color, pos = part.position,
                    status = part.status, k = part.k, drift = self.mode == RaceMode.DRIFT and part.drift or nil }
                key[#key + 1] = part.id .. ':' .. part.position .. ':' .. part.status
            end)
            key = table.concat(key, ',')
            local t = now()
            if key ~= last or t - lastSent > 2000 then
                last, lastSent = key, t
                self:SendAll('positions', board)
            end
            local n = #racing
            Wait(n <= 4 and 300 or n <= 8 and 500 or 800)
        end
    end)
end

-- ── results ─────────────────────────────────────────────────────────────
function Lobby:Finalize()
    if self.status == LobbyStatus.FINISHED then return end
    self.status = LobbyStatus.FINISHED
    local finished, dnf = {}, {}
    self:Each(function(part)
        if part.status == PStatus.FINISHED then finished[#finished + 1] = part else dnf[#dnf + 1] = part end
    end)
    if self.mode == RaceMode.DRIFT then
        table.sort(finished, function(a, b) return a.result.score > b.result.score end)
    else
        table.sort(finished, function(a, b) return a.result.score < b.result.score end)
    end
    local ordered = {}
    for i, part in ipairs(finished) do
        part.position = i
        part.winnerStatus = i == 1 and 'winner' or (i <= Config.Rewards.Winners and 'topX' or 'participant')
        ordered[#ordered + 1] = part
    end
    table.sort(dnf, function(a, b) return (a.k or 0) > (b.k or 0) end)
    for _, part in ipairs(dnf) do
        part.position = #ordered + 1
        ordered[#ordered + 1] = part
    end

    Rewards.Wagers(self, finished)
    if self.type == LobbyType.RANKED then
        Rewards.Ranked(self, finished)
        Rewards.Elo(self, ordered)
    end
    Rewards.Xp(self, finished)
    local crewScore = self.type == LobbyType.CREW and Rewards.CrewScore(self, ordered) or nil

    local results = {}
    for _, part in ipairs(ordered) do
        local r = part.result or {}
        results[#results + 1] = {
            id = part.id, alias = part.profile.alias, avatar = part.profile.avatar, color = part.profile.color,
            crew = part.profile.crewId and Crews.Brief(part.profile.crewId) or nil,
            position = part.position, status = part.status, time = r.time, bestLap = r.bestLap, score = r.score, drift = r.drift,
            penalty = r.penalty, vehicle = part.vehicle and part.vehicle.label, eloDelta = part.eloDelta, elo = part.profile.elo,
            payout = part.payout, reason = part.dqReason,
        }
    end
    self.results = { list = results, mode = self.mode, crews = crewScore }
    self:Persist(ordered)

    self:Each(function(part)
        if Core.Active[part.id] == self.id then Core.Active[part.id] = nil end
        self:Send(part, 'results', { results = self.results, me = part.id, track = self.track.name, lobby = self.name })
    end)
    self:Changed()
    Profiles.InvalidateBoard()

    local lines = { ('**%s** · %s · %s'):format(self.name, self.track.name, self.mode) }
    for _, r in ipairs(results) do
        lines[#lines + 1] = r.status == PStatus.FINISHED and ('`%d.` %s — %.3fs'):format(r.position, r.alias, (r.time or 0) / 1000)
            or ('`DNF` %s'):format(r.alias)
    end
    DiscordLog('Results', L('LOG_RACE_RESULT'), lines)

    local keep = Config.Races.FinishedLobbyVisibilityTime or 0
    if keep > 0 then SetTimeout(keep, function() self:Remove() end) else self:Remove() end
end

function Lobby:Persist(ordered)
    local laps = self.circuit and self.laps or 1
    local total = #self.route
    for _, part in ipairs(ordered) do
        local r = part.result or {}
        local fraction = part.status == PStatus.FINISHED and 1 or (total > 0 and part.k / total or 0)
        local distance = math.floor(self.track.length * laps * fraction)
        MySQL.insert([[INSERT INTO nayzeee_racing_history (lobby_id, track_id, profile_id, position, status, time_ms, best_lap_ms, distance, mode, type, vehicle, elo_delta)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
            self.id, self.track.id, part.id, math.min(part.position, 255), part.status == PStatus.FINISHED and 'finished' or 'disqualified',
            r.time, r.bestLap, distance, self.mode, self.type, part.vehicle and part.vehicle.label, part.eloDelta,
        }, function() Profiles.Invalidate(part.id) end)
    end
end
