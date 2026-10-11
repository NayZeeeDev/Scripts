if not NAYZEEE_LOCK_OK then return end

NZR = {}
NZR.Resource = GetCurrentResourceName()

LobbyStatus = { PENDING = 'pending', MOBILIZING = 'mobilizing', COUNTDOWN = 'countdown', RACING = 'racing', FINISHED = 'finished', CANCELLED = 'cancelled' }
PStatus     = { QUEUING = 'queuing', ACCEPTED = 'accepted', MOBILIZING = 'mobilizing', COUNTDOWN = 'countdown', RACING = 'racing', FINISHED = 'finished', DISQUALIFIED = 'disqualified' }
TrackType   = { CIRCUIT = 'circuit', SPRINT = 'sprint' }
LobbyType   = { UNRANKED = 'unranked', RANKED = 'ranked', CREW = 'crew', PRACTICE = 'practice' }
RaceMode    = { STANDARD = 'standard', DRIFT = 'drift', TIME_TRIAL = 'time_trial', ELIMINATION = 'elimination' }
MsgType     = { STANDARD = 'standard', REWARD = 'reward', CREW_INVITE = 'crew_invite', LOBBY_INVITE = 'lobby_invite' }
CrewPerm    = { MEMBERS = 1, MANAGE = 2, RACES = 3 }

local levels = { debug = 1, info = 2, warn = 3, error = 4 }
function Log(level, fmt, ...)
    if (levels[level] or 2) < (levels[Config.LogLevel] or 3) then return end
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    print(('^5[racing]^0 [%s] %s'):format(level, ok and msg or tostring(fmt)))
end

-- ── locale ───────────────────────────────────────────────────────────────
local strings = {}
function NZR.LoadLocale(code)
    local raw = LoadResourceFile(NZR.Resource, ('locales/%s.json'):format(code or 'en'))
    if not raw then raw = LoadResourceFile(NZR.Resource, 'locales/en.json') end
    local ok, data = pcall(json.decode, raw or '{}')
    strings = ok and data or {}
    return strings
end
NZR.LoadLocale(Config.UI.DefaultLocale)

function L(key, ...)
    local s = strings[key] or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end

-- ── helpers ──────────────────────────────────────────────────────────────
function NZR.V3(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

function NZR.Trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function NZR.CleanPlate(p) return (tostring(p or ''):gsub('%s+', ''):upper()) end

-- Route of gate indices a racer must pass. Circuit: 2..N,1 per lap. Sprint: 2..N.
function NZR.BuildRoute(count, laps, circuit)
    local route = {}
    if circuit and laps and laps > 0 then
        for _ = 1, laps do
            for i = 2, count do route[#route + 1] = i end
            route[#route + 1] = 1
        end
    else
        for i = 2, count do route[#route + 1] = i end
    end
    return route
end

-- Track length in metres (center to center, closing segment for circuits)
function NZR.TrackLength(cps, circuit)
    local total = 0.0
    for i = 2, #cps do total = total + #(NZR.V3(cps[i].center) - NZR.V3(cps[i - 1].center)) end
    if circuit and #cps > 2 then total = total + #(NZR.V3(cps[1].center) - NZR.V3(cps[#cps].center)) end
    return math.floor(total + 0.5)
end

function NZR.RankFor(elo)
    local ranks = Config.ELO.Ranks
    for i = #ranks, 1, -1 do
        if elo >= ranks[i].min then return ranks[i], i end
    end
    return ranks[1], 1
end

-- m:ss.mmm
function NZR.Clock(ms)
    ms = math.max(0, math.floor(tonumber(ms) or 0))
    return ('%d:%02d.%03d'):format(ms // 60000, (ms % 60000) // 1000, ms % 1000)
end

-- Challenge periods (UTC). Day / week numbers since the epoch, weeks start on Monday.
function NZR.DayIndex(t) return (t or os.time()) // 86400 end
function NZR.WeekIndex(t) return ((t or os.time()) // 86400 + 3) // 7 end

function NZR.ClassFits(lobbyClass, vehicleClass)
    if not lobbyClass or lobbyClass == 'Open' then return true end
    if vehicleClass == 'All' then return true end
    return lobbyClass == vehicleClass
end

-- Config safe to send to the UI (functions stripped)
function NZR.PublicConfig()
    local function strip(t, depth)
        if depth > 6 then return nil end
        local out = {}
        for k, v in pairs(t) do
            local tv = type(v)
            if tv == 'table' then out[k] = strip(v, depth + 1)
            elseif tv ~= 'function' then out[k] = v end
        end
        return out
    end
    return {
        version = GetResourceMetadata(NZR.Resource, 'version', 0) or '1.0.0',
        General = { VehicleImagesUrl = Config.General.VehicleImagesUrl },
        Profiles = strip(Config.Profiles, 1),
        Crews = strip(Config.Crews, 1),
        Trackbuilder = { MinCheckpoints = Config.Trackbuilder.MinCheckpoints, MaxCheckpoints = Config.Trackbuilder.MaxCheckpoints, CrewTracks = Config.Trackbuilder.CrewTracks },
        Races = {
            WagerCurrencies = Config.Races.WagerCurrencies, MaxWager = Config.Races.MaxWager, MaxParticipants = Config.Races.MaxParticipants,
            MaxLaps = Config.Races.MaxLaps, RequiredParticipantsForRankedLobby = Config.Races.RequiredParticipantsForRankedLobby,
            MinCrewSize = Config.Races.MinCrewSize, ResultsTime = Config.Races.ResultsTime,
            Respawn = { Enabled = Config.Races.Respawn.Enabled, Penalty = Config.Races.Respawn.Penalty },
            Elimination = Config.Races.Elimination,
        },
        Practice = { Enabled = Config.Practice.Enabled, MaxLaps = Config.Practice.MaxLaps },
        Spectate = { Enabled = Config.Spectate.Enabled, Anyone = Config.Spectate.Anyone, HostOnly = Config.Spectate.HostOnly },
        Splits = { Enabled = Config.Splits.Enabled },
        QuickRace = { Enabled = Config.QuickRace.Enabled },
        PinkSlips = { Enabled = Config.PinkSlips.Enabled, MaxRacers = Config.PinkSlips.MaxRacers, AllowRanked = Config.PinkSlips.AllowRanked },
        Betting = { Enabled = Config.Betting.Enabled, Currency = Config.Betting.Currency, Min = Config.Betting.Min, Max = Config.Betting.Max, HouseCut = Config.Betting.HouseCut },
        Seasons = { Enabled = Config.Seasons.Enabled, Badges = strip(Config.Seasons.Badges, 1) },
        Challenges = { Enabled = Config.Challenges.Enabled },
        Rewards = { Currencies = strip(Config.Rewards.Currencies, 1), Winners = Config.Rewards.Winners },
        ELO = { Ranks = strip(Config.ELO.Ranks, 1), ClassRestrictions = Config.ELO.ClassRestrictions },
        Achievements = strip(Config.Achievements, 1),
        Classes = Config.Vehicles.Classes,
        UI = strip(Config.UI, 1),
    }
end
