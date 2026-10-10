-- Exports for other resources. Every table returned is a copy, so callers can't mutate squad state.
local function copySquad(sq)
    if not sq then return nil end
    return {
        id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, description = sq.description, motd = sq.motd,
        limit = sq.limit, owner = sq.owner, temporary = sq.temporary,
        elo = sq.elo, tier = Combat.Tier(sq.elo).name, wins = sq.wins, losses = sq.losses, draws = sq.draws,
        kills = sq.kills, deaths = sq.deaths, assists = sq.assists, members = MemberList(sq),
        allies = Allies.Payload(sq), created = sq.created,
    }
end

exports('GetSquad', function(id) return copySquad(Squads[tonumber(id)]) end)
exports('GetPlayerSquad', function(src) return copySquad(SquadOf(tonumber(src))) end)
exports('IsInSquad', function(src) return Players[tonumber(src)] ~= nil end)
exports('AreInSameSquad', function(a, b)
    local sa = Players[tonumber(a)]
    return sa ~= nil and sa == Players[tonumber(b)]
end)
exports('AreAllied', function(a, b)
    local sa, sb = Players[tonumber(a)], Players[tonumber(b)]
    return sa ~= nil and sb ~= nil and (sa == sb or Allies.Are(sa, sb))
end)
exports('GetAllSquads', function()
    local out = {}
    for _, sq in pairs(Squads) do out[#out + 1] = copySquad(sq) end
    return out
end)
exports('GetSquadRank', function(src)
    local sq = SquadOf(tonumber(src))
    if not sq then return nil end
    local rec = sq.roster[sq.online[tonumber(src)]]
    return rec and { level = rec.rank, name = Ranks.Name(sq, rec.rank) } or nil
end)
exports('HasSquadPerm', function(src, perm)
    local sq = SquadOf(tonumber(src))
    if not sq then return false end
    local rec = sq.roster[sq.online[tonumber(src)]]
    return rec ~= nil and Ranks.Can(sq, rec.rank, perm)
end)
exports('AddSquadElo', function(squadId, amount)
    local sq = Squads[tonumber(squadId)]
    if not sq then return false end
    sq.elo = math.max(Config.Elo.Floor, sq.elo + math.floor(tonumber(amount) or 0))
    DB.SaveSquad(sq)
    SyncSquad(sq)
    MarkListDirty()
    return sq.elo
end)
exports('SquadMessage', function(squadId, text)
    local sq = Squads[tonumber(squadId)]
    if not sq or type(text) ~= 'string' then return false end
    SystemMessage(sq, text:sub(1, Config.ChatMaxLength))
    return true
end)
exports('NotifySquad', function(squadId, text, kind)
    local sq = Squads[tonumber(squadId)]
    if not sq then return false end
    NotifySquad(sq, text, kind)
    return true
end)
