-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

local function copySquad(sq)
    if not sq then return nil end
    local members = {}
    for identifier, r in pairs(sq.roster) do
        members[#members + 1] = {
            id = r.src, identifier = identifier, name = Nick(r), realName = r.name, nick = r.nick, rank = r.rank,
            rankName = Ranks.Name(sq, r.rank), owner = identifier == sq.owner, online = r.src ~= nil,
            kills = r.kills or 0, deaths = r.deaths or 0, assists = r.assists or 0, revives = r.revives or 0,
        }
    end
    return {
        id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, limit = sq.limit, owner = sq.owner,
        elo = sq.elo, tier = Combat.Tier(sq.elo).name, wins = sq.wins, losses = sq.losses, draws = sq.draws,
        kills = sq.kills, deaths = sq.deaths, assists = sq.assists, members = members,
    }
end

exports('GetSquad', function(id) return copySquad(Squads[tonumber(id)]) end)
exports('GetPlayerSquad', function(src) return copySquad(SquadOf(tonumber(src))) end)
exports('IsInSquad', function(src) return Players[tonumber(src)] ~= nil end)
exports('AreInSameSquad', function(a, b)
    local sa = Players[tonumber(a)]
    return sa ~= nil and sa == Players[tonumber(b)]
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
    sq.elo = math.max(SquadsConfig.Elo.Floor, sq.elo + math.floor(tonumber(amount) or 0))
    DB.SaveSquad(sq)
    SyncSquad(sq)
    return sq.elo
end)
