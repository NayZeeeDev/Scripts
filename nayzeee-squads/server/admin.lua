-- Staff tools: inspect every squad, remove members, force-disband, rename, adjust ELO, season reset.
local function isStaff(src)
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, Config.Admin.Ace)
end

RegisterCommand(Config.Admin.Command, function(src)
    if src == 0 then return print('[nayzeee-squads] This command is for players.') end
    if not isStaff(src) then return Notify(src, 'You do not have access to that', 'error') end
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
                identifier = identifier, id = r.src, name = Nick(r), realName = r.name, online = r.src ~= nil,
                rank = r.rank, rankName = Ranks.Name(sq, r.rank), owner = identifier == sq.owner,
                kills = r.kills or 0, deaths = r.deaths or 0, assists = r.assists or 0, lastSeen = r.lastSeen,
            }
        end
        table.sort(members, function(a, b) return a.rank > b.rank end)
        out[#out + 1] = {
            id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, elo = sq.elo, motd = sq.motd,
            tier = Combat.Tier(sq.elo), wins = sq.wins, losses = sq.losses, draws = sq.draws,
            kills = sq.kills, deaths = sq.deaths, persistent = sq.persistent, temporary = sq.temporary,
            created = sq.created, count = #members, online = online, members = members,
            allies = Allies.Count(sq), log = sq.log,
        }
    end
    table.sort(out, function(a, b) return a.online > b.online or (a.online == b.online and a.elo > b.elo) end)
    return out
end)

lib.callback.register('nz_squads:admin:action', function(src, action, squadId, target, value)
    if not isStaff(src) then return false, 'No access' end

    if action == 'seasonReset' then
        local n = 0
        for _, sq in pairs(Squads) do
            if sq.persistent then
                sq.elo = Config.Elo.Start
                sq.wins, sq.losses, sq.draws = 0, 0, 0
                sq.kills, sq.deaths, sq.assists = 0, 0, 0
                for identifier, r in pairs(sq.roster) do
                    r.kills, r.deaths, r.assists, r.revives = 0, 0, 0, 0
                    DB.SaveMember(sq.id, identifier, r)
                end
                Log(sq, 'match', 'Season reset by staff')
                DB.SaveSquad(sq)
                SyncSquad(sq)
                Roles.SyncSquad(sq, true)
                n = n + 1
            end
        end
        MarkListDirty()
        Webhook.Admin(src, 'Season reset', ('Reset ratings and stats for %d squads'):format(n))
        return true, ('Season reset for %d squads'):format(n)
    end

    local sq = Squads[tonumber(squadId)]
    if not sq then return false, 'Squad not found' end

    if action == 'disband' then
        NotifySquad(sq, 'A staff member closed your squad', 'error')
        Disband(sq, nil, 'staff')
        Webhook.Admin(src, 'Disband', ('Closed **%s** (ID %d)'):format(sq.name, sq.id))
        return true, 'Squad closed'
    end

    if action == 'kick' then
        local rec = sq.roster[target]
        if not rec then return false, 'Member not found' end
        local name = Nick(rec)
        if rec.src then
            Notify(rec.src, 'A staff member removed you from your squad', 'error')
            RemoveMember(sq, rec.src, 'kicked', true)
        else
            sq.roster[target] = nil
            DB.RemoveMember(sq.id, target)
            Log(sq, 'kick', ('%s was removed by staff'):format(name))
            if RosterCount(sq) == 0 then
                Disband(sq, nil, 'empty')
            else
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
                DB.SaveSquad(sq)
                SyncSquad(sq)
                MarkListDirty()
            end
        end
        Webhook.Admin(src, 'Remove member', ('Removed **%s** from **%s**'):format(name, sq.name))
        return true, 'Member removed'
    end

    if action == 'setElo' then
        local elo = tonumber(value)
        if not elo then return false, 'Enter a rating' end
        sq.elo = math.max(Config.Elo.Floor, math.min(5000, math.floor(elo)))
        Log(sq, 'match', ('Rating set to %d by staff'):format(sq.elo))
        DB.SaveSquad(sq)
        SyncSquad(sq)
        MarkListDirty()
        Roles.SyncSquad(sq, true)
        Webhook.Admin(src, 'Set ELO', ('Set **%s** to %d ELO'):format(sq.name, sq.elo))
        return true, ('%s is now %d ELO'):format(sq.name, sq.elo)
    end

    if action == 'resetStats' then
        sq.wins, sq.losses, sq.draws = 0, 0, 0
        sq.kills, sq.deaths, sq.assists = 0, 0, 0
        sq.elo = Config.Elo.Start
        for identifier, r in pairs(sq.roster) do
            r.kills, r.deaths, r.assists, r.revives = 0, 0, 0, 0
            DB.SaveMember(sq.id, identifier, r)
        end
        Log(sq, 'match', 'Stats reset by staff')
        DB.SaveSquad(sq)
        SyncSquad(sq)
        MarkListDirty()
        Roles.SyncSquad(sq, true)
        Webhook.Admin(src, 'Reset stats', ('Reset stats for **%s**'):format(sq.name))
        return true, 'Stats reset'
    end

    if action == 'rename' then
        local ok, name = ValidName(value, sq.id)
        if not ok then return false, name end
        local old = sq.name
        sq.name = name
        Log(sq, 'edit', ('Renamed from %s to %s by staff'):format(old, name))
        NotifySquad(sq, ('Staff renamed your squad to %s'):format(name), 'warning')
        DB.SaveSquad(sq)
        SyncSquad(sq)
        SyncAllies(sq)
        MarkListDirty()
        Webhook.Admin(src, 'Rename', ('Renamed **%s** to **%s**'):format(old, name))
        return true, ('Renamed to %s'):format(name)
    end

    if action == 'clearMotd' then
        sq.motd = nil
        DB.SaveSquad(sq)
        SyncSquad(sq)
        Webhook.Admin(src, 'Clear MOTD', ('Cleared the message of **%s**'):format(sq.name))
        return true, 'Message cleared'
    end

    return false, 'Unknown action'
end)
