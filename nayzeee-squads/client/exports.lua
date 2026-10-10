exports('GetSquad', function() return Squad end)
exports('IsInSquad', function() return Squad ~= nil end)
exports('IsSquadMember', function(serverId)
    if not Squad then return false end
    serverId = tonumber(serverId)
    for i = 1, #Squad.members do
        if Squad.members[i].id == serverId then return true end
    end
    return false
end)
exports('IsAlly', function(serverId)
    if not Squad or not Squad.allyMembers then return false end
    return Squad.allyMembers[tostring(serverId)] ~= nil
end)
exports('GetSquadRank', function() return Squad and Squad.you and Squad.you.rank or nil end)
exports('HasSquadPerm', function(perm) return Can(perm) end)
exports('GetSquadElo', function() return Squad and Squad.elo or nil end)
exports('OpenMenu', function() ExecuteCommand(Config.Command) end)
exports('CloseMenu', function() CloseMenu() end)
