--[[ Crews (lobbies). Every player that opens the tablet gets a solo crew they can invite others into. ]]

Crew = { byId = {}, of = {} }

local MAX_SIZE = 8
local seq = 0
local invites = {} -- target src -> { crew, from, expires }

local function newCrew(leader)
    seq = seq + 1
    local c = { id = seq, leader = leader, members = { leader }, ready = {}, heist = nil }
    Crew.byId[c.id] = c
    Crew.of[leader] = c.id
    return c
end

function Crew.get(src)
    local id = Crew.of[src]
    return id and Crew.byId[id] or nil
end

function Crew.ensure(src)
    return Crew.get(src) or newCrew(src)
end

function Crew.isLeader(src)
    local c = Crew.get(src)
    return c ~= nil and c.leader == src
end

function Crew.state(c)
    local members = {}
    for i = 1, #c.members do
        local src = c.members[i]
        local p = Profile.public(src)
        members[i] = {
            source = src,
            nickname = p and p.nickname or GetPlayerName(src),
            avatar = p and p.avatar or 1,
            level = p and p.level or 1,
            ready = c.ready[src] == true or src == c.leader,
            leader = src == c.leader,
        }
    end
    return { id = c.id, leader = c.leader, members = members, heist = c.heist and Engine.publicSummary(c.heist) or nil }
end

function Crew.broadcast(c)
    if not c then return end
    local state = Crew.state(c)
    for i = 1, #c.members do
        TriggerClientEvent('nzh:crew:update', c.members[i], state)
    end
end

function Crew.refreshFor(src)
    Crew.broadcast(Crew.get(src))
end

function Crew.allReady(c)
    if not Config.Crew.readyCheck then return true end
    for i = 1, #c.members do
        local m = c.members[i]
        if m ~= c.leader and not c.ready[m] then return false end
    end
    return true
end

local function removeMember(c, src)
    for i = #c.members, 1, -1 do
        if c.members[i] == src then table.remove(c.members, i) end
    end
    c.ready[src] = nil
    Crew.of[src] = nil
    if #c.members == 0 then
        Crew.byId[c.id] = nil
        return
    end
    if c.leader == src then
        c.leader = c.members[1]
        c.ready[c.leader] = nil
    end
end

--- Moves `src` out of their current crew. Running heists are informed by the engine.
function Crew.leave(src, silent)
    local c = Crew.get(src)
    if not c then return end
    local uid = c.heist
    removeMember(c, src)
    if uid then Engine.memberLeft(uid, src, 'left') end
    if Crew.byId[c.id] then
        Crew.broadcast(c)
        if not silent then
            for i = 1, #c.members do
                FW.notify(c.members[i], locale('crew_member_left', Profile.cached(src) and Profile.cached(src).nickname or src), 'info')
            end
        end
    end
    local solo = newCrew(src)
    Crew.broadcast(solo)
end

function Crew.join(src, c)
    local cur = Crew.get(src)
    if cur and cur.id ~= c.id then
        removeMember(cur, src)
        if Crew.byId[cur.id] then Crew.broadcast(cur) end
    end
    c.members[#c.members + 1] = src
    Crew.of[src] = c.id
    Crew.broadcast(c)
end

--[[ ------------------------------ callbacks ------------------------------ ]]

Guard.callback('nzh:crew:get', function(src)
    return Crew.state(Crew.ensure(src))
end)

Guard.callback('nzh:crew:invite', function(src, target)
    target = tonumber(target)
    if not Guard.rate(src, 'invite', 1500) then return false, locale('slow_down') end
    local c = Crew.ensure(src)
    if c.leader ~= src then return false, locale('only_leader') end
    if c.heist then return false, locale('crew_busy') end
    if not target or target == src or not GetPlayerName(target) then return false, locale('player_not_found') end
    if #c.members >= MAX_SIZE then return false, locale('crew_full') end
    local tc = Crew.get(target)
    if tc and (tc.heist or #tc.members > 1) then return false, locale('player_unavailable') end
    if Config.Crew.inviteDistance > 0 then
        local a, b = Guard.coords(src), Guard.coords(target)
        if not a or not b or #(a - b) > Config.Crew.inviteDistance then return false, locale('player_too_far') end
    end
    invites[target] = { crew = c.id, from = src, expires = os.time() + Config.Crew.inviteTimeout }
    local p = Profile.public(src)
    TriggerClientEvent('nzh:crew:invited', target, {
        from = src, nickname = p and p.nickname or GetPlayerName(src), avatar = p and p.avatar or 1,
        level = p and p.level or 1, members = #c.members, timeout = Config.Crew.inviteTimeout,
    })
    return true, locale('invite_sent')
end)

Guard.callback('nzh:crew:respond', function(src, accept)
    local inv = invites[src]
    invites[src] = nil
    if not inv or inv.expires < os.time() then return false, locale('invite_expired') end
    local c = Crew.byId[inv.crew]
    if not c or c.heist then return false, locale('invite_expired') end
    if not accept then
        FW.notify(inv.from, locale('invite_declined', Profile.cached(src) and Profile.cached(src).nickname or src), 'error')
        return true
    end
    if #c.members >= MAX_SIZE then return false, locale('crew_full') end
    local cur = Crew.get(src)
    if cur and cur.heist then return false, locale('crew_busy') end
    Crew.join(src, c)
    for i = 1, #c.members do
        if c.members[i] ~= src then
            FW.notify(c.members[i], locale('crew_member_joined', Profile.cached(src) and Profile.cached(src).nickname or src), 'success')
        end
    end
    return true
end)

Guard.callback('nzh:crew:leave', function(src)
    local c = Crew.get(src)
    if not c or #c.members <= 1 then return false end
    Crew.leave(src)
    return true
end)

Guard.callback('nzh:crew:kick', function(src, target)
    target = tonumber(target)
    local c = Crew.get(src)
    if not c or c.leader ~= src or target == src then return false, locale('only_leader') end
    if Crew.of[target] ~= c.id then return false end
    Crew.leave(target, true)
    FW.notify(target, locale('crew_kicked'), 'error')
    return true
end)

Guard.callback('nzh:crew:promote', function(src, target)
    target = tonumber(target)
    local c = Crew.get(src)
    if not c or c.leader ~= src or Crew.of[target] ~= c.id then return false, locale('only_leader') end
    c.leader = target
    c.ready[target] = nil
    Crew.broadcast(c)
    if c.heist then Engine.syncCrew(c.heist) end
    return true
end)

Guard.callback('nzh:crew:ready', function(src, state)
    local c = Crew.get(src)
    if not c then return false end
    c.ready[src] = state == true
    Crew.broadcast(c)
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    invites[src] = nil
    local c = Crew.get(src)
    if not c then return end
    local uid = c.heist
    removeMember(c, src)
    if uid then Engine.memberLeft(uid, src, 'disconnect') end
    if Crew.byId[c.id] then Crew.broadcast(c) end
end)
