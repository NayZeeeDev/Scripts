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

--[[
    A speaker that stops following its group keeps nothing of the group's: followers share the
    leader's record, queue and song tables (Links.Sync), and two speakers that are no longer linked
    must never share them, or one record could be handed back twice and two speakers would take
    songs off each other's queue.
]]
local function release(m)
    m.vinyl, m.track, m.playing, m.pos, m.queue = nil, nil, false, 0, {}
    m.xfade, m.endReported = nil, nil
end

--[[
    Takes a speaker out of its group. The music stays with the group and the speaker that leaves goes
    quiet, except that a record stays on the deck that holds it: a leader that leaves with a record on
    keeps it (and its music), and the speakers it leaves behind go quiet.
      how  nil     a player unlinked it (everyone involved hears about it)
           'move'  it is about to join another group (the caller tells everyone afterwards)
           'gone'  it is being packed up / broken / removed, so the group simply carries on without it
]]
function Links.Detach(e, how)
    local g = Links.GroupOf(e)
    if not g then return end
    for i, id in ipairs(g.members) do
        if id == e.id then table.remove(g.members, i) break end
    end
    e.group = nil
    local rest = {}
    for _, id in ipairs(g.members) do
        local m = Emitters[id]
        if m then rest[#rest + 1] = m end
    end

    local heir = rest[1]
    if g.leader ~= e.id then
        if how ~= 'gone' then release(e) end
    elseif how ~= 'gone' and e.vinyl then
        for _, m in ipairs(rest) do release(m) end
    else
        -- the next speaker carries on with the music it was already mirroring
        if heir then heir.xfade, heir.endReported = e.xfade, e.endReported end
        if how ~= 'gone' then release(e) end
    end

    if #rest <= 1 then
        for _, m in ipairs(rest) do m.group = nil Broadcast(m) end
        groups[g.id] = nil
    elseif g.leader == e.id then
        g.leader = heir.id
        Broadcast(heir)
        Links.Sync(heir)
    else
        for _, m in ipairs(rest) do Broadcast(m) end      -- one fewer in the group
    end
    if not how then Broadcast(e) end
end

function Links.RemoveFrom(e) Links.Detach(e, 'gone') end

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
    if m.group then Links.Detach(m, 'move') end
    m.group = g.id
    g.members[#g.members + 1] = m.id
    return true
end

--[[
    Picks the leader of a group that just grew. Followers copy the leader, so whatever else was on a
    follower is overwritten: a deck holding a record leads (a playing record first), otherwise
    whichever speaker has music. Any other record in the group goes back to whoever put it on (never
    to the player linking, who may not be anywhere near it), instead of disappearing.
]]
local function settle(g, from)
    local function weight(m) return (m.vinyl and 2 or 0) + (m.track and 1 or 0) end
    local members = Links.Members(from)
    local lead = Emitters[g.leader] or from
    for _, m in ipairs(members) do
        if weight(m) > weight(lead) then lead = m end
    end
    g.leader = lead.id
    for _, m in ipairs(members) do
        if m ~= lead and m.vinyl and m.vinyl ~= lead.vinyl then Vinyl.Return(m, m.vinyl.ownerSrc, m.id) end
    end
    return lead
end

local function canLink(src, e)
    -- a locked speaker (or every speaker, with Config.Links.owner) only links for its owner
    if not Config.Links.owner and e.access ~= 'owner' then return true end
    return e.owner == Bridge.GetIdentifier(src) or Bridge.IsAdmin(src)
end

-- one link / unlink per player every 0.6 s (each one is sent to everyone, and logged)
local lastLink = {}
local function tooSoon(src)
    local t = GetGameTimer()
    if lastLink[src] and t - lastLink[src] < 600 then
        Notify(src, 'shop_slow', 'inform')
        return true
    end
    lastLink[src] = t
    return false
end
AddEventHandler('playerDropped', function() lastLink[source] = nil end)

--[[
    The player stands at speaker `id` and links `otherId` to it. Someone else's speaker only links
    while you are standing at it too: a link lets either speaker control the other's music (and its
    record), so it must not reach further than walking up to it would.
]]
RegisterNetEvent(RES .. ':link', function(id, otherId)
    local src = source
    if not Config.Links.enabled then return Notify(src, 'feature_off', 'inform') end
    if tooSoon(src) then return end
    local a = Guard(src, id, true)
    local b = Emitters[otherId]
    if not a or not b or a.id == b.id or b.spawning then return end
    if a.kind == 'vehicle' or b.kind == 'vehicle' then return Notify(src, 'link_vehicle') end
    if not canLink(src, a) or not canLink(src, b) then return Notify(src, 'not_owner') end

    local pa, pb = EmitterPosition(a), EmitterPosition(b)
    if not pa or not pb or #(pa - pb) > Config.Links.distance then return Notify(src, 'link_far') end
    if b.owner ~= Bridge.GetIdentifier(src) and not Bridge.IsAdmin(src) then
        if not InReach(src, b) then return Notify(src, 'too_far') end
        if LockedFor(src, b) then return Notify(src, 'no_access') end
    end

    local ga, gb = Links.GroupOf(a), Links.GroupOf(b)
    if ga and gb and ga.id == gb.id then return end

    local g = ga or gb or groupFor(a)
    if not join(g, a) or not join(g, b) then return Notify(src, 'link_full') end

    local lead = settle(g, a)
    Broadcast(a) Broadcast(b)
    Links.Sync(lead)
    Notify(src, 'linked', 'success', #g.members)
    Log('Speakers linked', ('**%s** linked `%s` + `%s` (%d in group)'):format(GetPlayerName(src), a.id, b.id, #g.members))
end)

RegisterNetEvent(RES .. ':unlink', function(id)
    local src = source
    if tooSoon(src) then return end
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
    local lead = settle(g, a)
    Broadcast(a) Broadcast(b)
    Links.Sync(lead)
    return true
end)
