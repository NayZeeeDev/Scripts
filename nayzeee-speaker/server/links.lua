--[[
    Linked speakers: two or more speakers that play one song in step.
    One of them is the leader; the others mirror its track, position, pause, queue and record.
    Controlling any speaker in the group controls the whole group.
]]
Links = {}

local groups = {}           -- groupId -> { id, leader = emitterId, members = { emitterId, ... } }
local seq = 0

function Links.GroupOf(e) return e and e.group and groups[e.group] or nil end

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

-- silent = the speaker is going away (packed / broken), so nobody needs to hear about it
function Links.Detach(e, silent)
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
        groups[g.id] = nil
    elseif g.leader == e.id then
        g.leader = g.members[1]
        local lead = Emitters[g.leader]
        if lead then Links.Sync(lead) end
    end
    if not silent then Broadcast(e) end
end

function Links.RemoveFrom(e) Links.Detach(e, true) end

-- the group `a` is in, or a new one it leads
local function groupFor(a)
    local g = Links.GroupOf(a)
    if g then return g end
    seq = seq + 1
    g = { id = ('g%d'):format(seq), leader = a.id, members = {} }
    groups[g.id] = g
    return g
end

-- false when the group is full
local function join(g, m)
    if m.group == g.id then return true end
    if #g.members >= Config.Links.maxGroup then return false end
    if m.group then Links.Detach(m, true) end
    m.group = g.id
    g.members[#g.members + 1] = m.id
    return true
end

--[[
    Picks the leader of a group that just grew. Followers copy the leader, so whatever else was on a
    follower is overwritten: a deck holding a record leads (a playing record first), otherwise
    whichever speaker has music. Any other record in the group goes back to `to`, or to whoever put
    it on, instead of disappearing.
]]
local function settle(g, from, to)
    local function weight(m) return (m.vinyl and 2 or 0) + (m.track and 1 or 0) end
    local members = Links.Members(from)
    local lead = Emitters[g.leader] or from
    for _, m in ipairs(members) do
        if weight(m) > weight(lead) then lead = m end
    end
    g.leader = lead.id
    for _, m in ipairs(members) do
        if m ~= lead and m.vinyl and m.vinyl ~= lead.vinyl then Vinyl.Return(m, to or m.vinyl.ownerSrc, m.id) end
    end
    return lead
end

local function canLink(src, e)
    -- a locked speaker (or every speaker, with Config.Links.owner) only links for its owner
    if not Config.Links.owner and e.access ~= 'owner' then return true end
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

    local g = ga or gb or groupFor(a)
    if not join(g, a) or not join(g, b) then return Notify(src, 'link_full') end

    local lead = settle(g, a, src)
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
    Links.Detach(e)
    Notify(src, 'unlinked', 'inform')
end)

-- speakers near this one that could be linked to it
NZ.RegisterCallback('link:nearby', function(src, id)
    local e = Emitters[id]
    local pos = e and EmitterPosition(e)
    if not pos then return {} end
    local me = Bridge.GetIdentifier(src)
    local out = {}
    for oid, other in pairs(Emitters) do
        if oid ~= id and other.kind == 'boombox' and other.state == 'placed' and other.coords then
            local d = #(pos - other.coords)
            if d <= Config.Links.distance then
                out[#out + 1] = {
                    id = oid, label = other.label, distance = math.floor(d),
                    linked = other.group ~= nil and other.group == e.group,
                    busy = other.group ~= nil and other.group ~= e.group,
                    mine = other.owner == me,
                }
            end
        end
    end
    table.sort(out, function(x, y) return x.distance < y.distance end)
    return out
end)

-- other scripts: link two speakers (no distance / owner checks; a record left over goes to its owner)
exports('LinkSpeakers', function(idA, idB)
    local a, b = Emitters[idA], Emitters[idB]
    if not a or not b or a == b then return false end
    local g = groupFor(a)
    if not join(g, a) or not join(g, b) then return false end
    local lead = settle(g, a, nil)
    Broadcast(a) Broadcast(b)
    Links.Sync(lead)
    return true
end)
