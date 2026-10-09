--[[
    Linked speakers: two or more speakers that play one song in step.
    One of them is the leader; the others mirror its track, position, pause and queue.
    Controlling any speaker in the group controls the whole group.
]]
Links = {}
local RES = GetCurrentResourceName()

Groups = {}             -- groupId -> { leader = emitterId, members = { emitterId, ... } }
local seq = 0

local function newGroupId()
    seq = seq + 1
    return ('g%d'):format(seq)
end

function Links.GroupOf(e) return e and e.group and Groups[e.group] or nil end

function Links.Members(e)
    local g = Links.GroupOf(e)
    if not g then return { e } end
    local out = {}
    for _, id in ipairs(g.members) do
        local m = Emitters[id]
        if m then out[#out + 1] = m end
    end
    return out
end

-- the speaker that actually owns the music for this group
function Links.Leader(e)
    local g = Links.GroupOf(e)
    if not g then return e end
    return Emitters[g.leader] or e
end

-- copy the leader's playback onto every follower, then tell everyone
function Links.Sync(leader)
    local g = Links.GroupOf(leader)
    if not g then return end
    for _, id in ipairs(g.members) do
        local m = Emitters[id]
        if m and m.id ~= leader.id then
            m.track = leader.track
            m.playing = leader.playing
            m.startedAt = leader.startedAt
            m.pos = leader.pos
            m.queue = leader.queue
            m.loop, m.shuffle = leader.loop, leader.shuffle
            m.vinyl = leader.vinyl
            Broadcast(m)
        end
    end
end

local function detach(e, silent)
    local g = Links.GroupOf(e)
    if not g then return end
    for i, id in ipairs(g.members) do
        if id == e.id then table.remove(g.members, i) break end
    end
    e.group = nil
    if #g.members <= 1 then
        for _, id in ipairs(g.members) do
            local m = Emitters[id]
            if m then m.group = nil if not silent then Broadcast(m) end end
        end
        Groups[g.id] = nil
    elseif g.leader == e.id then
        g.leader = g.members[1]
        local lead = Emitters[g.leader]
        if lead then Links.Sync(lead) end
    end
    if not silent then Broadcast(e) end
end
Links.Detach = detach

function Links.RemoveFrom(e) detach(e, true) end

local function canLink(src, e)
    if not Config.Links.owner then return true end
    return e.owner == Bridge.GetIdentifier(src) or Bridge.IsAdmin(src)
end

RegisterNetEvent(RES .. ':link', function(id, otherId)
    local src = source
    if not Config.Links.enabled then return end
    local a = Guard(src, id, true)
    local b = Emitters[otherId]
    if not a or not b or a.id == b.id then return end
    if a.kind == 'vehicle' or b.kind == 'vehicle' then return Notify(src, 'link_vehicle') end
    if not canLink(src, a) or not canLink(src, b) then return Notify(src, 'not_owner') end

    local pa, pb = EmitterPosition(a), EmitterPosition(b)
    if not pa or not pb or #(pa - pb) > Config.Links.distance then return Notify(src, 'link_far') end

    local ga, gb = Links.GroupOf(a), Links.GroupOf(b)
    if ga and gb and ga.id == gb.id then return end

    local g = ga or gb
    if not g then
        g = { id = newGroupId(), leader = a.id, members = {} }
        Groups[g.id] = g
    end
    local function add(m)
        if m.group == g.id then return true end
        if #g.members >= Config.Links.maxGroup then return false end
        if m.group then detach(m, true) end
        m.group = g.id
        g.members[#g.members + 1] = m.id
        return true
    end
    if not add(a) or not add(b) then return Notify(src, 'link_full') end

    local lead = Emitters[g.leader] or a
    -- whichever side already has music becomes the leader
    if not lead.track then
        for _, m in ipairs(Links.Members(a)) do
            if m.track then g.leader = m.id lead = m break end
        end
    end
    Broadcast(a) Broadcast(b)
    Links.Sync(lead)
    Notify(src, 'linked', 'success', #g.members)
    Log('Speakers linked', ('**%s** linked `%s` + `%s` (%d in group)'):format(GetPlayerName(src), a.id, b.id, #g.members))
end)

RegisterNetEvent(RES .. ':unlink', function(id)
    local src = source
    local e = Guard(src, id, true)
    if not e or not e.group then return end
    if not canLink(src, e) then return Notify(src, 'not_owner') end
    detach(e)
    Notify(src, 'unlinked', 'inform')
end)

-- speakers near this one that could be linked to it
NZ.RegisterCallback('link:nearby', function(src, id)
    local e = Emitters[id]
    if not e then return {} end
    local pos = EmitterPosition(e)
    if not pos then return {} end
    local out = {}
    for oid, other in pairs(Emitters) do
        if oid ~= id and other.kind == 'boombox' and other.state == 'placed' then
            local p = EmitterPosition(other)
            if p and #(pos - p) <= Config.Links.distance then
                out[#out + 1] = {
                    id = oid, label = other.label,
                    distance = math.floor(#(pos - p)),
                    linked = other.group ~= nil and other.group == e.group,
                    busy = other.group ~= nil and other.group ~= e.group,
                    mine = other.owner == Bridge.GetIdentifier(src),
                }
            end
        end
    end
    table.sort(out, function(x, y) return x.distance < y.distance end)
    return out
end)

exports('LinkSpeakers', function(idA, idB)
    local a, b = Emitters[idA], Emitters[idB]
    if not a or not b then return false end
    local g = Links.GroupOf(a) or { id = newGroupId(), leader = a.id, members = {} }
    Groups[g.id] = g
    for _, m in ipairs({ a, b }) do
        if m.group ~= g.id and #g.members < Config.Links.maxGroup then
            m.group = g.id
            g.members[#g.members + 1] = m.id
            Broadcast(m)
        end
    end
    Links.Sync(Emitters[g.leader] or a)
    return true
end)
