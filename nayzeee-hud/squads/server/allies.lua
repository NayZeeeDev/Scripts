-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Squad affiliations. Allied squads see each other, optionally can't hurt each other,
-- and never trade ELO. Alliances are mutual and capped by SquadsConfig.Affiliations.MaxPerSquad.
Allies = {}

local A = SquadsConfig.Affiliations
local S = SquadsConfig.Strings
local requests = {}   -- [targetSquadId] = { [fromSquadId] = { expires, by } }

local function enabled()
    return SquadsConfig.Features.Affiliations and A.MaxPerSquad > 0
end

function Allies.Enabled() return enabled() end

local function count(sq)
    local n = 0
    for _ in pairs(sq.allies or {}) do n = n + 1 end
    return n
end

Allies.Count = count

---@return boolean
function Allies.Are(a, b)
    if not enabled() or not a or not b then return false end
    if a == b then return true end
    local sq = Squads[a]
    return sq ~= nil and sq.allies ~= nil and sq.allies[b] ~= nil
end

--- Allied squad ids for one squad, as a plain list.
function Allies.List(sq)
    local out = {}
    for id in pairs(sq.allies or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end

--- Small payload for the UI.
function Allies.Payload(sq)
    local out = {}
    for id, at in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then
            local onlineCount = 0
            for _ in pairs(other.online) do onlineCount = onlineCount + 1 end
            out[#out + 1] = {
                id = id, name = other.name, tag = other.tag, image = other.image,
                elo = other.elo, tier = Combat.Tier(other.elo), online = onlineCount,
                blipColor = other.blipColor, since = at,
            }
        end
    end
    table.sort(out, function(x, y) return x.name < y.name end)
    return out
end

--- Pending requests aimed at this squad.
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
                out[#out + 1] = {
                    id = fromId, name = other.name, tag = other.tag, image = other.image,
                    elo = other.elo, tier = Combat.Tier(other.elo), by = req.by,
                    expires = req.expires - now,
                }
            end
        end
    end
    return out
end

--- Members of this squad plus every allied squad, as server ids.
function Allies.NearbyMembers(sq)
    local out = {}
    for id in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then
            for src in pairs(other.online) do out[#out + 1] = src end
        end
    end
    return out
end

local function link(a, b)
    a.allies = a.allies or {}
    b.allies = b.allies or {}
    local now = os.time()
    a.allies[b.id] = now
    b.allies[a.id] = now
    if a.persistent and b.persistent then DB.AddAlly(a.id, b.id) end
end

local function unlink(a, b)
    if a.allies then a.allies[b.id] = nil end
    if b.allies then b.allies[a.id] = nil end
    if a.persistent and b.persistent then DB.RemoveAlly(a.id, b.id) end
end

--- Drops every alliance a squad holds (used when it disbands).
function Allies.ClearAll(sq)
    if not sq.allies then return end
    for id in pairs(sq.allies) do
        local other = Squads[id]
        if other then
            if other.allies then other.allies[sq.id] = nil end
            Broadcast(other, 'nz_squads:notify', S.ally_removed:format(sq.name), 'info')
            SyncSquad(other)
        end
    end
    if sq.persistent then
        for id in pairs(sq.allies) do DB.RemoveAlly(sq.id, id) end
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
    if sq.allies and sq.allies[other.id] then return false, 'You are already allied with them' end
    if count(sq) >= A.MaxPerSquad then return false, S.ally_full end
    if count(other) >= A.MaxPerSquad then return false, 'That squad already has the most allies allowed' end

    -- they already asked us, so this is an accept
    local incoming = requests[sq.id] and requests[sq.id][other.id]
    if incoming and incoming.expires > os.time() then
        requests[sq.id][other.id] = nil
        link(sq, other)
        Broadcast(sq, 'nz_squads:notify', S.ally_added:format(other.name), 'info')
        Broadcast(other, 'nz_squads:notify', S.ally_added:format(sq.name), 'info')
        SyncSquad(sq); SyncSquad(other)
        Webhook.Ally(sq, other, 'formed')
        return true, S.ally_added:format(other.name)
    end

    if not A.RequireBoth then
        link(sq, other)
        Broadcast(sq, 'nz_squads:notify', S.ally_added:format(other.name), 'info')
        Broadcast(other, 'nz_squads:notify', S.ally_added:format(sq.name), 'info')
        SyncSquad(sq); SyncSquad(other)
        Webhook.Ally(sq, other, 'formed')
        return true, S.ally_added:format(other.name)
    end

    requests[other.id] = requests[other.id] or {}
    local rec = sq.roster[sq.online[src]]
    requests[other.id][sq.id] = { expires = os.time() + A.RequestExpiry, by = Nick(rec) }

    Broadcast(other, 'nz_squads:notify', S.ally_request:format(sq.name), 'info')
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
        Broadcast(other, 'nz_squads:notify', S.ally_declined:format(sq.name), 'error')
        SyncSquad(sq)
        return true, 'Request declined'
    end

    if count(sq) >= A.MaxPerSquad then return false, S.ally_full end
    if count(other) >= A.MaxPerSquad then return false, 'That squad already has the most allies allowed' end

    link(sq, other)
    Broadcast(sq, 'nz_squads:notify', S.ally_added:format(other.name), 'info')
    Broadcast(other, 'nz_squads:notify', S.ally_added:format(sq.name), 'info')
    SyncSquad(sq); SyncSquad(other)
    Webhook.Ally(sq, other, 'formed')
    return true, S.ally_added:format(other.name)
end)

lib.callback.register('nz_squads:allyRemove', function(src, targetId)
    if not enabled() then return false end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not HasPerm(sq, src, A.MinRankPerm) then return false, S.no_perm end

    local other = Squads[tonumber(targetId)]
    if not other or not (sq.allies and sq.allies[other.id]) then return false, 'You are not allied with them' end

    unlink(sq, other)
    Broadcast(sq, 'nz_squads:notify', S.ally_removed:format(other.name), 'info')
    Broadcast(other, 'nz_squads:notify', S.ally_removed:format(sq.name), 'info')
    SyncSquad(sq); SyncSquad(other)
    Webhook.Ally(sq, other, 'ended')
    return true, S.ally_removed:format(other.name)
end)
