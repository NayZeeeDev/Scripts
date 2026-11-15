-- Crews: create, invite, join, leave, kick, promote, disband. Membership is mirrored to
-- player state bags (cutupCrew) so every client knows who is in whose crew.
Crews = { invites = {} }

local ROLE_RANK = { member = 1, officer = 2, owner = 3 }

local function key()
    local s = ''
    for _ = 1, 10 do s = s .. string.char(math.random(97, 122)) end
    return s
end

local function toast(src, msg, kind) TriggerClientEvent('nayzeee-cutup:client:toast', src, 'CREW', msg, kind or 'info') end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function validColor(c)
    return type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') ~= nil
end

function Crews.Get(id) return id and DB.crews[id] or nil end

function Crews.Recalc(id)
    local crew = DB.crews[id]
    if not crew then return end
    local total = 0
    for ident in pairs(crew.members) do
        local p = DB.players[ident]
        if p and p.bestCrew then total = total + p.bestCrew.points end
    end
    crew.points = total
    DB.SaveCrew(crew)
    Leaderboard.Dirty()
end

function Crews.SyncState(identifier)
    local src = Online.ByIdent(identifier)
    if not src then return end
    local p = DB.players[identifier]
    local crew = p and Crews.Get(p.crewId)
    Player(src).state:set('cutupCrew', crew and { id = crew.id, tag = crew.tag, color = crew.color, name = crew.name } or nil, true)
end

-- full crew view for one player
function Crews.Send(src)
    local ident = Online.Ident(src)
    local p = ident and DB.players[ident]
    if not p then return end
    local crew = Crews.Get(p.crewId)
    local data = { crew = nil, invites = {} }
    if crew then
        local members = {}
        for mIdent, m in pairs(crew.members) do
            local mp = DB.players[mIdent]
            members[#members + 1] = {
                key = m.key, name = mp and mp.name or m.name, role = m.role,
                online = Online.ByIdent(mIdent) ~= nil, me = mIdent == ident,
                pbCrew = mp and mp.bestCrew and mp.bestCrew.points or 0,
                pbSolo = mp and mp.bestSolo and mp.bestSolo.points or 0,
            }
        end
        table.sort(members, function(a, b)
            if ROLE_RANK[a.role] ~= ROLE_RANK[b.role] then return ROLE_RANK[a.role] > ROLE_RANK[b.role] end
            return a.pbCrew > b.pbCrew
        end)
        local pos, total = Leaderboard.Position('crews', crew.id)
        data.crew = {
            id = crew.id, name = crew.name, tag = crew.tag, color = crew.color, points = crew.points or 0,
            position = pos, totalCrews = total, members = members, myRole = crew.members[ident].role,
            max = Config.Crew.MaxMembers,
        }
    end
    local inv = Crews.invites[src]
    if inv and os.time() < inv.expires and DB.crews[inv.crewId] then
        local c = DB.crews[inv.crewId]
        data.invites[1] = { crewName = c.name, tag = c.tag, color = c.color, from = inv.fromName }
    end
    TriggerClientEvent('nayzeee-cutup:client:crew', src, data)
end

local function sendAll(crew)
    for ident in pairs(crew.members) do
        local s = Online.ByIdent(ident)
        if s then Crews.Send(s) end
    end
end

local function notifyAll(crew, msg, except)
    for ident in pairs(crew.members) do
        local s = Online.ByIdent(ident)
        if s and s ~= except then toast(s, msg) end
    end
end

local function nameTaken(name, tag)
    local ln, lt = name:lower(), tag:lower()
    for _, c in pairs(DB.crews) do
        if c.name:lower() == ln or c.tag:lower() == lt then return true end
    end
    return false
end

local function memberCount(crew)
    local n = 0
    for _ in pairs(crew.members) do n = n + 1 end
    return n
end

local function byKey(crew, k)
    for ident, m in pairs(crew.members) do if m.key == k then return ident, m end end
end

local Actions = {}

function Actions.create(src, p, data)
    if p.crewId then return toast(src, L('crew_in_one'), 'error') end
    local name, tag = trim(data.name), trim(data.tag):upper()
    local nl, tl = Config.Crew.NameLength, Config.Crew.TagLength
    if #name < nl[1] or #name > nl[2] or name:find('[<>]') then return toast(src, L('crew_bad_name', nl[1], nl[2]), 'error') end
    if #tag < tl[1] or #tag > tl[2] or not tag:match('^[%w]+$') then return toast(src, L('crew_bad_tag', tl[1], tl[2]), 'error') end
    if nameTaken(name, tag) then return toast(src, L('crew_taken'), 'error') end
    local id = DB.nextCrewId
    DB.nextCrewId = id + 1
    local crew = {
        id = id, name = name, tag = tag, color = validColor(data.color) and data.color or Config.Crew.Colors[1],
        owner = p.identifier, points = 0, created = os.time(),
        members = { [p.identifier] = { role = 'owner', name = p.name, key = key(), joined = os.time() } },
    }
    DB.crews[id] = crew
    p.crewId = id
    DB.SaveCrew(crew) DB.SavePlayer(p)
    Crews.Recalc(id)
    Crews.SyncState(p.identifier)
    toast(src, L('crew_created', tag, name), 'success')
    Crews.Send(src)
end

function Actions.invite(src, p, data)
    local crew = Crews.Get(p.crewId)
    if not crew then return toast(src, L('crew_not_in'), 'error') end
    if ROLE_RANK[crew.members[p.identifier].role] < 2 then return toast(src, L('crew_no_perm'), 'error') end
    if memberCount(crew) >= Config.Crew.MaxMembers then return toast(src, L('crew_full'), 'error') end
    local target = tonumber(data.target)
    local tIdent = target and Online.Ident(target)
    if not tIdent or target == src then return toast(src, L('crew_no_player'), 'error') end
    if DB.players[tIdent] and DB.players[tIdent].crewId then return toast(src, L('crew_target_in'), 'error') end
    Crews.invites[target] = { crewId = crew.id, from = p.identifier, fromName = p.name, expires = os.time() + Config.Crew.InviteTimeout }
    toast(src, L('crew_invite_sent', GetPlayerName(target) or target), 'success')
    toast(target, L('crew_invite', p.name, crew.tag, crew.name))
    Crews.Send(target)
end

function Actions.accept(src, p)
    local inv = Crews.invites[src]
    Crews.invites[src] = nil
    if not inv or os.time() > inv.expires then return toast(src, L('crew_no_invite'), 'error') end
    if p.crewId then return toast(src, L('crew_in_one'), 'error') end
    local crew = Crews.Get(inv.crewId)
    if not crew then return toast(src, L('crew_no_invite'), 'error') end
    if memberCount(crew) >= Config.Crew.MaxMembers then return toast(src, L('crew_full'), 'error') end
    crew.members[p.identifier] = { role = 'member', name = p.name, key = key(), joined = os.time() }
    p.crewId = crew.id
    DB.SavePlayer(p)
    Crews.Recalc(crew.id)
    Crews.SyncState(p.identifier)
    toast(src, L('crew_joined', crew.tag, crew.name), 'success')
    notifyAll(crew, L('crew_member_join', p.name), src)
    sendAll(crew)
end

function Actions.decline(src)
    Crews.invites[src] = nil
    Crews.Send(src)
end

local function removeMember(crew, ident)
    crew.members[ident] = nil
    local mp = DB.players[ident]
    if mp then mp.crewId = nil DB.SavePlayer(mp) end
    Crews.SyncState(ident)
end

local function disband(crew)
    local idents = {}
    for ident in pairs(crew.members) do idents[#idents + 1] = ident end
    DB.crews[crew.id] = nil
    DB.DeleteCrew(crew.id)
    for _, ident in ipairs(idents) do
        local mp = DB.players[ident]
        if mp then mp.crewId = nil DB.SavePlayer(mp) end
        Crews.SyncState(ident)
        local s = Online.ByIdent(ident)
        if s then toast(s, L('crew_disbanded'), 'warn') Crews.Send(s) end
    end
    Leaderboard.Dirty()
end

function Actions.leave(src, p)
    local crew = Crews.Get(p.crewId)
    if not crew then return toast(src, L('crew_not_in'), 'error') end
    if crew.members[p.identifier].role == 'owner' then
        -- hand the crew to the highest ranked member, or disband if alone
        local heir, heirRank = nil, 0
        for ident, m in pairs(crew.members) do
            if ident ~= p.identifier and ROLE_RANK[m.role] > heirRank then heir, heirRank = ident, ROLE_RANK[m.role] end
        end
        if not heir then return disband(crew) end
        crew.members[heir].role = 'owner'
        crew.owner = heir
    end
    removeMember(crew, p.identifier)
    Crews.Recalc(crew.id)
    toast(src, L('crew_left'))
    notifyAll(crew, L('crew_member_left', p.name))
    Crews.Send(src)
    sendAll(crew)
end

function Actions.kick(src, p, data)
    local crew = Crews.Get(p.crewId)
    if not crew then return toast(src, L('crew_not_in'), 'error') end
    local tIdent, tm = byKey(crew, data.key)
    local myRank = ROLE_RANK[crew.members[p.identifier].role]
    if not tIdent or tIdent == p.identifier or ROLE_RANK[tm.role] >= myRank or myRank < 2 then
        return toast(src, L('crew_no_perm'), 'error')
    end
    removeMember(crew, tIdent)
    Crews.Recalc(crew.id)
    local ts = Online.ByIdent(tIdent)
    if ts then toast(ts, L('crew_kicked'), 'warn') Crews.Send(ts) end
    notifyAll(crew, L('crew_member_left', tm.name))
    sendAll(crew)
end

local function setRole(src, p, data, role)
    local crew = Crews.Get(p.crewId)
    if not crew then return toast(src, L('crew_not_in'), 'error') end
    if crew.members[p.identifier].role ~= 'owner' then return toast(src, L('crew_no_perm'), 'error') end
    local tIdent, tm = byKey(crew, data.key)
    if not tIdent or tIdent == p.identifier then return toast(src, L('crew_no_perm'), 'error') end
    if role == 'owner' then
        crew.members[p.identifier].role = 'officer'
        crew.owner = tIdent
    end
    tm.role = role
    DB.SaveCrew(crew)
    notifyAll(crew, L('crew_promoted', tm.name, role))
    sendAll(crew)
end

function Actions.promote(src, p, data) setRole(src, p, data, 'officer') end
function Actions.demote(src, p, data) setRole(src, p, data, 'member') end
function Actions.transfer(src, p, data) setRole(src, p, data, 'owner') end

function Actions.disband(src, p)
    local crew = Crews.Get(p.crewId)
    if not crew then return toast(src, L('crew_not_in'), 'error') end
    if crew.members[p.identifier].role ~= 'owner' then return toast(src, L('crew_no_perm'), 'error') end
    disband(crew)
end

function Actions.color(src, p, data)
    local crew = Crews.Get(p.crewId)
    if not crew or crew.members[p.identifier].role ~= 'owner' or not validColor(data.color) then
        return toast(src, L('crew_no_perm'), 'error')
    end
    crew.color = data.color
    DB.SaveCrew(crew)
    for ident in pairs(crew.members) do Crews.SyncState(ident) end
    Leaderboard.Dirty()
    sendAll(crew)
end

function Actions.refresh(src) Crews.Send(src) end

function Crews.Handle(src, action, data)
    local fn = Actions[action]
    local ident = Online.Ident(src)
    local p = ident and DB.players[ident]
    if not fn or not p then return end
    fn(src, p, type(data) == 'table' and data or {})
end

function Crews.Dropped(src)
    Crews.invites[src] = nil
end
