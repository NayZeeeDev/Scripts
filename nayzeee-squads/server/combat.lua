-- Squad vs squad combat: kills, deaths, assists, streaks, engagements and ELO.
Combat = {}

local E = Config.Elo
local engagements = {}   -- ['a:b'] = { a, b, killsA, killsB, last, started }

-- ─── tiers ─────────────────────────────────────────────────
function Combat.Tier(elo)
    local tier = E.Tiers[1]
    for i = 1, #E.Tiers do
        if elo >= E.Tiers[i].min then tier = E.Tiers[i] end
    end
    return tier
end

--- Progress through the current tier, 0-1, for the UI bar.
function Combat.TierProgress(elo)
    local idx = 1
    for i = 1, #E.Tiers do
        if elo >= E.Tiers[i].min then idx = i end
    end
    local floorV = E.Tiers[idx].min
    local nextT  = E.Tiers[idx + 1]
    if not nextT then return 1.0, nil end
    local span = nextT.min - floorV
    if span <= 0 then return 1.0, nextT end
    return math.max(0, math.min(1, (elo - floorV) / span)), nextT
end

-- ─── elo maths ─────────────────────────────────────────────
local function kFactor(elo)
    local scaled = E.K - math.floor(math.max(0, elo - E.Start) / 100) * 2
    return math.max(E.MinK, scaled)
end

local function expected(a, b) return 1 / (1 + 10 ^ ((b - a) / 400)) end

--- Returns the ELO change for each side and A's score (1 win, 0 loss, 0.5 draw).
function Combat.Rate(eloA, eloB, killsA, killsB)
    local scoreA = killsA > killsB and 1 or (killsA < killsB and 0 or 0.5)
    local margin = 1.0
    if E.MarginBonus then
        local diff = math.abs(killsA - killsB)
        if diff > 1 then margin = math.min(1.6, 1 + (diff - 1) * 0.12) end
    end
    local deltaA = math.floor((kFactor(eloA) * (scoreA - expected(eloA, eloB)) * margin) + 0.5)
    local deltaB = math.floor((kFactor(eloB) * ((1 - scoreA) - expected(eloB, eloA)) * margin) + 0.5)
    return deltaA, deltaB, scoreA
end

-- ─── engagements ───────────────────────────────────────────
local function key(a, b)
    if a < b then return a .. ':' .. b end
    return b .. ':' .. a
end

local function resolve(eng, k)
    engagements[k] = nil
    local a, b = Squads[eng.a], Squads[eng.b]
    if not a or not b then return end
    if eng.killsA + eng.killsB < E.MinKillsToScore then return end

    local deltaA, deltaB, scoreA = Combat.Rate(a.elo, b.elo, eng.killsA, eng.killsB)
    local tierA, tierB = Combat.Tier(a.elo).name, Combat.Tier(b.elo).name
    a.elo = math.max(E.Floor, a.elo + deltaA)
    b.elo = math.max(E.Floor, b.elo + deltaB)

    if Combat.Tier(a.elo).name ~= tierA then Roles.SyncSquad(a, true) end
    if Combat.Tier(b.elo).name ~= tierB then Roles.SyncSquad(b, true) end

    if scoreA == 1 then
        a.wins = a.wins + 1; b.losses = b.losses + 1
    elseif scoreA == 0 then
        b.wins = b.wins + 1; a.losses = a.losses + 1
    else
        a.draws = a.draws + 1; b.draws = b.draws + 1
    end

    DB.SaveSquad(a); DB.SaveSquad(b)
    DB.SaveMatch({
        a = a.id, b = b.id, nameA = a.name, nameB = b.name,
        killsA = eng.killsA, killsB = eng.killsB, deltaA = deltaA, deltaB = deltaB,
        winner = scoreA == 1 and a.id or (scoreA == 0 and b.id or nil),
    })
    Webhook.Match(a, b, eng, deltaA, deltaB)

    local function tell(sq, mine, theirs, delta, other)
        local result = delta > 0 and 'win' or (delta < 0 and 'loss' or 'draw')
        Log(sq, 'match', ('%s vs %s %d-%d (%+d ELO)'):format(result == 'win' and 'Won' or result == 'loss' and 'Lost' or 'Drew', other.name, mine, theirs, delta))
        Broadcast(sq, 'nz_squads:matchResult', {
            squad = other.name, tag = other.tag, kills = mine, enemyKills = theirs,
            delta = delta, elo = sq.elo, tier = Combat.Tier(sq.elo).name, result = result,
        })
        SyncSquad(sq)
    end
    tell(a, eng.killsA, eng.killsB, deltaA, b)
    tell(b, eng.killsB, eng.killsA, deltaB, a)
    TriggerEvent('nz_squads:server:matchScored', a.id, b.id, eng.killsA, eng.killsB, deltaA, deltaB)
end

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        for k, eng in pairs(engagements) do
            if now - eng.last >= E.EngagementTimeout then resolve(eng, k) end
        end
    end
end)

local function touch(aId, bId, aScored)
    local k = key(aId, bId)
    local eng = engagements[k]
    if not eng then
        eng = { a = math.min(aId, bId), b = math.max(aId, bId), killsA = 0, killsB = 0, started = os.time() }
        engagements[k] = eng
    end
    if (aScored and aId == eng.a) or (not aScored and bId == eng.a) then
        eng.killsA = eng.killsA + 1
    else
        eng.killsB = eng.killsB + 1
    end
    eng.last = os.time()
    return eng
end

-- ─── stat helpers ──────────────────────────────────────────
local function rated(sq) return sq ~= nil and not sq.temporary end
Combat.Rated = rated

local function recOf(sq, src)
    local identifier = sq.online[src]
    return identifier and sq.roster[identifier], identifier
end

local function bump(sq, src, field, amount)
    if not rated(sq) then return end
    local rec, identifier = recOf(sq, src)
    if not rec then return end
    rec[field] = (rec[field] or 0) + amount
    sq[field]  = (sq[field] or 0) + amount
    DB.SaveMember(sq.id, identifier, rec)
    DB.SaveSquad(sq)
end

function Combat.AddRevive(sq, src) bump(sq, src, 'revives', 1) end

--- Called when a player reports their own death.
---@param victim number
---@param killer number|nil
---@param assists table list of server ids that damaged the victim recently
function Combat.Death(victim, killer, assists)
    if not Config.Features.Combat then return end
    local vSquad = SquadOf(victim)
    if not vSquad then return end

    local vRec = recOf(vSquad, victim)
    if vRec then vRec.streak = 0 end
    bump(vSquad, victim, 'deaths', 1)

    if not killer or killer == victim then SyncSquad(vSquad) return end

    local kSquad = SquadOf(killer)
    if not kSquad or kSquad.id == vSquad.id then SyncSquad(vSquad) return end
    if Config.Affiliations.IgnoreInElo and Allies.Are(kSquad.id, vSquad.id) then SyncSquad(vSquad) return end

    local kRec = recOf(kSquad, killer)
    if kRec then kRec.streak = (kRec.streak or 0) + 1 end
    bump(kSquad, killer, 'kills', 1)

    -- a temporary squad on either side means there is nothing to rate
    if not rated(kSquad) or not rated(vSquad) then
        SyncSquad(kSquad); SyncSquad(vSquad)
        return
    end

    if type(assists) == 'table' then
        local seen = { [killer] = true }
        for i = 1, math.min(#assists, 5) do
            local a = tonumber(assists[i])
            if a and not seen[a] then
                seen[a] = true
                local aSquad = SquadOf(a)
                if aSquad and aSquad.id == kSquad.id then bump(aSquad, a, 'assists', 1) end
            end
        end
    end

    local eng = touch(kSquad.id, vSquad.id, true)
    local mine = kSquad.id == eng.a and eng.killsA or eng.killsB
    local theirs = kSquad.id == eng.a and eng.killsB or eng.killsA
    local streak = kRec and kRec.streak >= E.StreakFrom and kRec.streak or nil
    local killerName, victimName = Nick(kRec), Nick(vRec)

    if Config.Features.Killfeed then
        Broadcast(kSquad, 'nz_squads:killfeed', { killer = killerName, victim = victimName, squad = vSquad.name, tag = vSquad.tag, good = true, score = { mine, theirs }, streak = streak })
        Broadcast(vSquad, 'nz_squads:killfeed', { killer = killerName, victim = victimName, squad = kSquad.name, tag = kSquad.tag, good = false, score = { theirs, mine }, streak = streak })
    end
    SyncSquad(kSquad)
    SyncSquad(vSquad)
end

--- Live engagements involving a squad, for the stats tab.
function Combat.ActiveFor(squadId)
    local out = {}
    for _, eng in pairs(engagements) do
        if eng.a == squadId or eng.b == squadId then
            local otherId = eng.a == squadId and eng.b or eng.a
            local other = Squads[otherId]
            out[#out + 1] = {
                squad = other and other.name or 'Unknown', tag = other and other.tag or nil, elo = other and other.elo or 0,
                mine = eng.a == squadId and eng.killsA or eng.killsB,
                theirs = eng.a == squadId and eng.killsB or eng.killsA,
                since = eng.started, last = eng.last,
            }
        end
    end
    return out
end

RegisterNetEvent('nz_squads:reportDeath', function(killer, assists)
    local src = source
    killer = tonumber(killer)
    if killer and not GetPlayerName(killer) then killer = nil end
    Combat.Death(src, killer, assists)
end)
