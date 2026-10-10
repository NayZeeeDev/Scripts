-- Squad affiliations. Allied squads see each other, optionally can't hurt each other,
-- and never trade ELO. Alliances are mutual and capped by Config.Affiliations.MaxPerSquad.
Allies = {}

local A = Config.Affiliations
local S = Config.Strings
local requests = {}   -- [targetSquadId] = { [fromSquadId] = { expires, by } }

local function enabled() return Config.Features.Affiliations and A.MaxPerSquad > 0 end
function Allies.Enabled() return enabled() end

local function count(sq)
    local n = 0
    for _ in pairs(sq.allies or {}) do n = n + 1 end
    return n
end
Allies.Count = count

function Allies.Are(a, b)
    if not enabled() or not a or not b then return false end
    if a == b then return true end
    local sq = Squads[a]
    return sq ~= nil and sq.allies ~= nil and sq.allies[b] ~= nil
end

function Allies.Payload(sq)
    local out = {}
    for id, at in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then
            out[#out + 1] = {
                id = id, name = other.name, tag = other.tag, image = other.image,
                elo = other.elo, tier = Combat.Tier(other.elo), online = OnlineCount(other),
                blipColor = other.blipColor, since = at,
            }
        end
    end
    table.sort(out, function(x, y) return x.name < y.name end)
    return out
end

function Allies.Pending(sq)
    local out, now = {}, os.time()
    local box = requests[sq.id]
    if not box then return out end
    for fromId, req in pairs(box) do
        if req.expires <= now then
            box[fromId] = nil
        else
            local other = Squads[fromId]
            if other then
                out[#out + 1] = { id = fromId, name = other.name, tag = other.tag, image = other.image,
                                  elo = other.elo, tier = Combat.Tier(other.elo), by = req.by, expires = req.expires - now }
            end
        end
    end
    return out
end

local function link(a, b)
    local now = os.time()
    a.allies[b.id] = now
    b.allies[a.id] = now
    if a.persistent and b.persistent then DB.AddAlly(a.id, b.id) end
    Log(a, 'ally', ('Allied with %s'):format(b.name))
    Log(b, 'ally', ('Allied with %s'):format(a.name))
    NotifySquad(a, S.ally_added:format(b.name), 'success', 'ally')
    NotifySquad(b, S.ally_added:format(a.name), 'success', 'ally')
    SyncSquad(a); SyncSquad(b)
    MarkListDirty()
    Webhook.Ally(a, b, 'formed')
end

local function unlink(a, b)
    a.allies[b.id] = nil
    b.allies[a.id] = nil
    if a.persistent and b.persistent then DB.RemoveAlly(a.id, b.id) end
    Log(a, 'ally', ('Alliance with %s ended'):format(b.name))
    Log(b, 'ally', ('Alliance with %s ended'):format(a.name))
end

--- Drops every alliance a squad holds (used when it disbands).
function Allies.ClearAll(sq)
    for id in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then
            other.allies[sq.id] = nil
            NotifySquad(other, S.ally_removed:format(sq.name), 'inform', 'ally')
            SyncSquad(other)
        end
        if sq.persistent then DB.RemoveAlly(sq.id, id) end
    end
    sq.allies = {}
    requests[sq.id] = nil
    for _, box in pairs(requests) do box[sq.id] = nil end
end

-- ─── callbacks ─────────────────────────────────────────────
lib.callback.register('nz_squads:allyRequest', function(src, targetId)
    if not enabled() then return false, 'Alliances are turned off' end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if sq.temporary then return false, 'Temporary squads cannot form alliances' end
    if not HasPerm(sq, src, A.MinRankPerm) then return false, S.no_perm end

    local other = Squads[tonumber(targetId)]
    if not other or other.id == sq.id then return false, 'That squad no longer exists' end
    if other.temporary then return false, 'You cannot ally with a temporary squad' end
    if sq.allies[other.id] then return false, 'You are already allied with them' end
    if count(sq) >= A.MaxPerSquad then return false, S.ally_full end
    if count(other) >= A.MaxPerSquad then return false, 'That squad already has the most allies allowed' end

    -- they already asked us, so this is an accept
    local incoming = requests[sq.id] and requests[sq.id][other.id]
    if (incoming and incoming.expires > os.time()) or not A.RequireBoth then
        if incoming then requests[sq.id][other.id] = nil end
        link(sq, other)
        return true, S.ally_added:format(other.name)
    end

    requests[other.id] = requests[other.id] or {}
    if requests[other.id][sq.id] and requests[other.id][sq.id].expires > os.time() then
        return false, 'You already sent them a request'
    end
    requests[other.id][sq.id] = { expires = os.time() + A.RequestExpiry, by = Nick(sq.roster[sq.online[src]]) }

    for s in pairs(other.online) do
        if HasPerm(other, s, A.MinRankPerm) then Notify(s, S.ally_request:format(sq.name), 'inform', 'ally') end
    end
    SyncSquad(other)
    return true, ('Request sent to %s'):format(other.name)
end)

lib.callback.register('nz_squads:allyRespond', function(src, fromId, accept)
    if not enabled() then return false end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not HasPerm(sq, src, A.MinRankPerm) then return false, S.no_perm end

    local box = requests[sq.id]
    local req = box and box[tonumber(fromId)]
    if not req or req.expires <= os.time() then return false, 'That request expired' end
    box[tonumber(fromId)] = nil

    local other = Squads[tonumber(fromId)]
    if not other then return false, 'That squad no longer exists' end

    if not accept then
        NotifySquad(other, S.ally_declined:format(sq.name), 'error', 'ally')
        SyncSquad(sq)
        return true, 'Request declined'
    end
    if count(sq) >= A.MaxPerSquad then return false, S.ally_full end
    if count(other) >= A.MaxPerSquad then return false, 'That squad already has the most allies allowed' end

    link(sq, other)
    return true, S.ally_added:format(other.name)
end)

lib.callback.register('nz_squads:allyRemove', function(src, targetId)
    if not enabled() then return false end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not HasPerm(sq, src, A.MinRankPerm) then return false, S.no_perm end

    local other = Squads[tonumber(targetId)]
    if not other or not sq.allies[other.id] then return false, 'You are not allied with them' end

    unlink(sq, other)
    NotifySquad(sq, S.ally_removed:format(other.name), 'inform', 'ally')
    NotifySquad(other, S.ally_removed:format(sq.name), 'inform', 'ally')
    SyncSquad(sq); SyncSquad(other)
    MarkListDirty()
    Webhook.Ally(sq, other, 'ended')
    return true, S.ally_removed:format(other.name)
end)
