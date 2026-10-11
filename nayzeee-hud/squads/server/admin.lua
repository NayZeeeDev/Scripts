-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Staff tools: inspect every squad, remove members, force-disband, adjust ELO.
local function isStaff(src)
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, SquadsConfig.Admin.Ace)
end

RegisterCommand(SquadsConfig.Admin.Command, function(src)
    if src == 0 then return print('[nayzeee-hud:squads] This command is for players.') end
    if not isStaff(src) then
        return TriggerClientEvent('nz_squads:notify', src, 'You do not have access to that', 'error')
    end
    TriggerClientEvent('nz_squads:openAdmin', src)
end, false)

lib.callback.register('nz_squads:admin:list', function(src)
    if not isStaff(src) then return nil end
    local out = {}
    for _, sq in pairs(Squads) do
        local members, online = {}, 0
        for identifier, r in pairs(sq.roster) do
            if r.src then online = online + 1 end
            members[#members + 1] = {
                identifier = identifier, id = r.src, name = r.name, nick = r.nick, online = r.src ~= nil,
                rank = r.rank, rankName = Ranks.Name(sq, r.rank), owner = identifier == sq.owner,
                kills = r.kills or 0, deaths = r.deaths or 0, assists = r.assists or 0,
            }
        end
        table.sort(members, function(a, b) return a.rank > b.rank end)
        out[#out + 1] = {
            id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, elo = sq.elo,
            tier = Combat.Tier(sq.elo), wins = sq.wins, losses = sq.losses,
            kills = sq.kills, deaths = sq.deaths, persistent = sq.persistent,
            created = sq.created, count = #members, online = online, members = members,
        }
    end
    table.sort(out, function(a, b) return a.online > b.online or (a.online == b.online and a.elo > b.elo) end)
    return out
end)

lib.callback.register('nz_squads:admin:action', function(src, action, squadId, target, value)
    if not isStaff(src) then return false, 'No access' end
    local sq = Squads[tonumber(squadId)]
    if not sq then return false, 'Squad not found' end

    if action == 'disband' then
        for s in pairs(sq.online) do
            Players[s] = nil
            sq.online[s] = nil
            TriggerClientEvent('nz_squads:sync', s, false, 'closed')
            TriggerClientEvent('nz_squads:notify', s, 'A staff member closed your squad', 'error')
            Roles.Clear(s)
        end
        Squads[sq.id] = nil
        DB.DeleteSquad(sq.id)
        Webhook.Admin(src, 'Disband', ('Closed **%s** (ID %d)'):format(sq.name, sq.id))
        return true, 'Squad closed'
    end

    if action == 'kick' then
        local rec = sq.roster[target]
        if not rec then return false, 'Member not found' end
        sq.roster[target] = nil
        DB.RemoveMember(sq.id, target)
        if rec.src then
            sq.online[rec.src] = nil
            Players[rec.src] = nil
            TriggerClientEvent('nz_squads:sync', rec.src, false, 'closed')
            TriggerClientEvent('nz_squads:notify', rec.src, 'A staff member removed you from your squad', 'error')
            Roles.Clear(rec.src)
        end
        if target == sq.owner then
            local best, bestRank
            for id, r in pairs(sq.roster) do
                if not bestRank or r.rank > bestRank then best, bestRank = id, r.rank end
            end
            if best then
                sq.owner = best
                sq.roster[best].rank = #sq.ranks
                DB.SaveMember(sq.id, best, sq.roster[best])
            end
        end
        local left = 0
        for _ in pairs(sq.roster) do left = left + 1 end
        if left == 0 then
            Squads[sq.id] = nil
            DB.DeleteSquad(sq.id)
        else
            DB.SaveSquad(sq)
            SyncSquad(sq)
        end
        Webhook.Admin(src, 'Remove member', ('Removed **%s** from **%s**'):format(rec.name, sq.name))
        return true, 'Member removed'
    end

    if action == 'setElo' then
        local elo = tonumber(value)
        if not elo then return false, 'Enter a rating' end
        sq.elo = math.max(SquadsConfig.Elo.Floor, math.min(5000, math.floor(elo)))
        DB.SaveSquad(sq)
        SyncSquad(sq)
        Roles.SyncSquad(sq, true)
        Webhook.Admin(src, 'Set ELO', ('Set **%s** to %d ELO'):format(sq.name, sq.elo))
        return true, ('%s is now %d ELO'):format(sq.name, sq.elo)
    end

    if action == 'resetStats' then
        sq.wins, sq.losses, sq.draws = 0, 0, 0
        sq.kills, sq.deaths, sq.assists = 0, 0, 0
        sq.elo = SquadsConfig.Elo.Start
        for identifier, r in pairs(sq.roster) do
            r.kills, r.deaths, r.assists, r.revives = 0, 0, 0, 0
            DB.SaveMember(sq.id, identifier, r)
        end
        DB.SaveSquad(sq)
        SyncSquad(sq)
        Roles.SyncSquad(sq, true)
        Webhook.Admin(src, 'Reset stats', ('Reset stats for **%s**'):format(sq.name))
        return true, 'Stats reset'
    end

    return false, 'Unknown action'
end)
