if not NAYZEEE_LOCK_OK then return end

--[[
    Crews: create / edit / disband, invites through the inbox, member permissions,
    activity feed and crew statistics.
    Permissions: 1 = manage members, 2 = manage crew, 3 = start crew races. The owner has all of them.
]]

Crews = { brief = {} }

local function row(id) return MySQL.single.await('SELECT * FROM nayzeee_racing_crews WHERE id = ?', { id }) end

function Crews.Brief(id)
    if not id then return nil end
    local c = Crews.brief[id]
    if c then return c end
    local r = row(id)
    if not r then return nil end
    c = { id = r.id, name = r.name, tag = r.tag, color = r.color, avatar = r.avatar, owner = r.owner }
    Crews.brief[id] = c
    return c
end

function Crews.Activity(crewId, kind, message)
    MySQL.insert('INSERT INTO nayzeee_racing_crew_activity (crew_id, type, message) VALUES (?, ?, ?)', { crewId, kind, message })
end

local function has(list, v)
    for _, x in ipairs(list or {}) do if tonumber(x) == v then return true end end
    return false
end

function Crews.Can(p, perm)
    if not p.crewId then return false end
    local c = Crews.Brief(p.crewId)
    if not c then return false end
    return c.owner == p.id or has(p.crewPerms, perm)
end

local function cleanPerms(list)
    local out = {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do
        v = tonumber(v)
        if (v == 1 or v == 2 or v == 3) and not has(out, v) then out[#out + 1] = v end
    end
    table.sort(out)
    return out
end

-- Update one member's crew columns, keep caches in sync
local function setMember(profileId, crewId, perms)
    MySQL.update.await('UPDATE nayzeee_racing_profiles SET crew_id = ?, crew_perms = ?, crew_joined = ? WHERE id = ?',
        { crewId, crewId and json.encode(perms or {}) or nil, crewId and os.date('%Y-%m-%d %H:%M:%S') or nil, profileId })
    local p = Profiles.cache[profileId]
    if p then
        p.crewId, p.crewPerms = crewId, perms or {}
        if p.source then Push(p.source, 'profile', Profiles.Dto(p)) end
    end
    Profiles.InvalidateBoard()
end

local function validate(d, current)
    local name = NZR.Trim(d.name)
    local tag = NZR.Trim(d.tag):upper()
    if #name < 3 or #name > 30 then return nil, 'CREW_NAME_LENGTH' end
    if #tag < Config.Crews.TagMin or #tag > Config.Crews.TagMax or not tag:match('^[A-Z0-9]+$') then return nil, 'CREW_TAG_INVALID' end
    local desc = NZR.Trim(d.description):sub(1, 250)
    local color = type(d.color) == 'string' and d.color:match('^#%x%x%x%x%x%x$') and d.color or nil
    if not color then return nil, 'ERR_INVALID' end
    if not ValidImage(d.avatar, Config.Crews) then return nil, 'ERR_IMAGE' end
    local nameId = MySQL.scalar.await('SELECT id FROM nayzeee_racing_crews WHERE LOWER(name) = LOWER(?)', { name })
    if nameId and nameId ~= current then return nil, 'CREW_NAME_TAKEN' end
    local tagId = MySQL.scalar.await('SELECT id FROM nayzeee_racing_crews WHERE tag = ?', { tag })
    if tagId and tagId ~= current then return nil, 'CREW_TAG_TAKEN' end
    return { name = name, tag = tag, description = desc, color = color, avatar = d.avatar or '' }
end

Handle('crew:available', function(_, _, d)
    local field = d.field == 'tag' and 'tag' or 'name'
    local value = NZR.Trim(d.value)
    if field == 'tag' then value = value:upper() end
    if value == '' then return false end
    local id = MySQL.scalar.await(('SELECT id FROM nayzeee_racing_crews WHERE LOWER(%s) = LOWER(?)'):format(field), { value })
    return id == nil or id == tonumber(d.except)
end)

Handle('crew:create', function(_, p, d)
    if p.crewId then return nil, 'CREW_ALREADY_IN' end
    local v, err = validate(d)
    if not v then return nil, err end
    local id = MySQL.insert.await('INSERT INTO nayzeee_racing_crews (name, tag, description, color, avatar, owner) VALUES (?, ?, ?, ?, ?, ?)',
        { v.name, v.tag, v.description, v.color, v.avatar, p.id })
    if not id then return nil, 'ERR_GENERIC' end
    setMember(p.id, id, { 1, 2, 3 })
    Crews.Activity(id, 'CREW_CREATED', L('ACT_CREW_CREATED', p.alias))
    MySQL.update('DELETE FROM nayzeee_racing_crew_invites WHERE profile_id = ?', { p.id })
    DiscordLog('Crews', L('LOG_CREW_CREATED'), { ('**%s** [%s]'):format(v.name, v.tag), L('LOG_BY', p.alias) })
    return Crews.Extended(id)
end)

Handle('crew:update', function(_, p, d)
    if not Crews.Can(p, CrewPerm.MANAGE) then return nil, 'ERR_NO_PERMISSION' end
    local v, err = validate(d, p.crewId)
    if not v then return nil, err end
    MySQL.update.await('UPDATE nayzeee_racing_crews SET name = ?, tag = ?, description = ?, color = ?, avatar = ? WHERE id = ?',
        { v.name, v.tag, v.description, v.color, v.avatar, p.crewId })
    Crews.brief[p.crewId] = nil
    Crews.Activity(p.crewId, 'CREW_UPDATED', L('ACT_CREW_UPDATED', p.alias))
    return Crews.Extended(p.crewId)
end)

function Crews.Disband(crewId)
    local c = Crews.Brief(crewId)
    local members = MySQL.query.await('SELECT id FROM nayzeee_racing_profiles WHERE crew_id = ?', { crewId }) or {}
    MySQL.update.await('DELETE FROM nayzeee_racing_crews WHERE id = ?', { crewId })
    for _, m in ipairs(members) do
        local cp = Profiles.cache[m.id]
        if cp then
            cp.crewId, cp.crewPerms = nil, {}
            if cp.source then Push(cp.source, 'profile', Profiles.Dto(cp)) end
        end
    end
    Crews.brief[crewId] = nil
    Profiles.InvalidateBoard()
    if c then DiscordLog('Crews', L('LOG_CREW_DISBANDED'), { ('**%s** [%s]'):format(c.name, c.tag) }) end
end

Handle('crew:disband', function(_, p)
    local c = p.crewId and Crews.Brief(p.crewId)
    if not c or c.owner ~= p.id then return nil, 'ERR_NO_PERMISSION' end
    Crews.Disband(c.id)
    return true
end)

Handle('crew:leave', function(_, p)
    local c = p.crewId and Crews.Brief(p.crewId)
    if not c then return nil, 'CREW_NOT_IN' end
    local lid = Core.Active[p.id]
    local lobby = lid and Core.Lobbies[lid]
    if lobby and lobby.type == LobbyType.CREW then return nil, 'CREW_IN_RACE' end
    local others = MySQL.query.await('SELECT id, crew_perms FROM nayzeee_racing_profiles WHERE crew_id = ? AND id <> ? ORDER BY crew_joined', { c.id, p.id }) or {}
    if #others == 0 then
        Crews.Disband(c.id)
        return true
    end
    if c.owner == p.id then
        -- hand the crew to the longest serving member with "manage crew", else the longest serving member
        local heir = others[1]
        for _, o in ipairs(others) do
            if has(DB.Decode(o.crew_perms, {}), CrewPerm.MANAGE) then heir = o break end
        end
        MySQL.update.await('UPDATE nayzeee_racing_crews SET owner = ? WHERE id = ?', { heir.id, c.id })
        setMember(heir.id, c.id, { 1, 2, 3 })
        Crews.brief[c.id] = nil
        local hp = Profiles.Get(heir.id)
        Crews.Activity(c.id, 'CREW_OWNER', L('ACT_CREW_OWNER', hp and hp.alias or '?'))
    end
    setMember(p.id, nil)
    Crews.Activity(c.id, 'CREW_LEFT', L('ACT_CREW_LEFT', p.alias))
    return true
end)

function Crews.Stats(crewId)
    local s = MySQL.single.await([[SELECT COUNT(h.id) AS races, IFNULL(SUM(h.position = 1 AND h.status = 'finished'), 0) AS wins
        FROM nayzeee_racing_history h JOIN nayzeee_racing_profiles p ON p.id = h.profile_id WHERE p.crew_id = ?]], { crewId }) or {}
    local e = MySQL.single.await('SELECT AVG(elo) AS avg, MAX(elo) AS top FROM nayzeee_racing_profiles WHERE crew_id = ?', { crewId }) or {}
    local cw = MySQL.single.await([[SELECT SUM(type = 'WON_RACE') AS won, SUM(type = 'LOST_RACE') AS lost
        FROM nayzeee_racing_crew_activity WHERE crew_id = ?]], { crewId }) or {}
    local races, wins = tonumber(s.races) or 0, tonumber(s.wins) or 0
    return {
        races = races, wins = wins, winRate = races > 0 and math.floor(wins / races * 100 + 0.5) or 0,
        avgElo = math.floor((tonumber(e.avg) or 0) + 0.5), topElo = tonumber(e.top) or 0,
        crewWins = tonumber(cw.won) or 0, crewLosses = tonumber(cw.lost) or 0,
    }
end

function Crews.Extended(id)
    local r = row(id)
    if not r then return nil end
    local members = MySQL.query.await([[SELECT p.id, p.alias, p.avatar, p.color, p.elo, p.crew_perms AS perms, UNIX_TIMESTAMP(p.crew_joined) AS joined,
        (SELECT COUNT(*) FROM nayzeee_racing_history h WHERE h.profile_id = p.id) AS races,
        (SELECT COUNT(*) FROM nayzeee_racing_history h WHERE h.profile_id = p.id AND h.position = 1 AND h.status = 'finished') AS wins
        FROM nayzeee_racing_profiles p WHERE p.crew_id = ? ORDER BY p.elo DESC]], { id }) or {}
    for _, m in ipairs(members) do
        m.perms = DB.Decode(m.perms, {})
        m.owner = m.id == r.owner
        m.online = Core.Online[m.id] ~= nil
    end
    local invites = MySQL.query.await([[SELECT i.id, i.profile_id AS profileId, i.perms, UNIX_TIMESTAMP(i.created) AS created, p.alias, p.avatar, p.color, p.elo
        FROM nayzeee_racing_crew_invites i JOIN nayzeee_racing_profiles p ON p.id = i.profile_id WHERE i.crew_id = ?]], { id }) or {}
    for _, i in ipairs(invites) do i.perms = DB.Decode(i.perms, {}) end
    local activity = MySQL.query.await([[SELECT id, type, message, UNIX_TIMESTAMP(created) AS created FROM nayzeee_racing_crew_activity
        WHERE crew_id = ? ORDER BY id DESC LIMIT 40]], { id }) or {}
    return {
        id = r.id, name = r.name, tag = r.tag, description = r.description, color = r.color, avatar = r.avatar, owner = r.owner,
        created = r.created, members = members, invites = invites, activity = activity, stats = Crews.Stats(id),
    }
end

Handle('crew:get', function(_, p, d)
    local id = tonumber(d.id) or p.crewId
    if not id then return nil, 'CREW_NOT_FOUND' end
    local c = Crews.Extended(id)
    if not c then return nil, 'CREW_NOT_FOUND' end
    if id ~= p.crewId then c.invites = nil end
    return c
end)

Handle('crew:search', function(_, _, d)
    local q = NZR.Trim(d.q):gsub('[%%_]', '')
    local rows = MySQL.query.await([[SELECT c.id, c.name, c.tag, c.color, c.avatar, COUNT(p.id) AS members, IFNULL(ROUND(AVG(p.elo)), 0) AS avgElo
        FROM nayzeee_racing_crews c LEFT JOIN nayzeee_racing_profiles p ON p.crew_id = c.id
        WHERE c.name LIKE ? OR c.tag LIKE ? GROUP BY c.id ORDER BY avgElo DESC LIMIT 20]], { '%' .. q .. '%', q:upper() .. '%' }) or {}
    return rows
end)

Handle('crew:invite', function(_, p, d)
    if not Crews.Can(p, CrewPerm.MEMBERS) then return nil, 'ERR_NO_PERMISSION' end
    local target = Profiles.Get(tonumber(d.profileId) or 0)
    if not target or target.identifier == 'SYSTEM' then return nil, 'PROFILE_NOT_FOUND' end
    if target.crewId then return nil, 'CREW_TARGET_IN_CREW' end
    if Config.Crews.MemberCap then
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_racing_profiles WHERE crew_id = ?', { p.crewId })
        if n >= Config.Crews.MemberCap then return nil, 'CREW_FULL' end
    end
    local perms = cleanPerms(d.perms)
    local c = Crews.Brief(p.crewId)
    if c.owner ~= p.id then
        -- members can only hand out permissions they hold
        local own = {}
        for _, v in ipairs(perms) do if has(p.crewPerms, v) then own[#own + 1] = v end end
        perms = own
    end
    local ok, inviteId = pcall(MySQL.insert.await, 'INSERT INTO nayzeee_racing_crew_invites (crew_id, profile_id, perms) VALUES (?, ?, ?)',
        { p.crewId, target.id, json.encode(perms) })
    if not ok or not inviteId then return nil, 'CREW_ALREADY_INVITED' end
    Profiles.Message(target.id, MsgType.CREW_INVITE, L('MSG_CREW_INVITE', c.name, p.alias),
        { inviteId = inviteId, crewId = c.id, crewName = c.name, crewTag = c.tag, crewColor = c.color, from = p.alias })
    return true
end)

Handle('crew:revoke', function(_, p, d)
    if not Crews.Can(p, CrewPerm.MEMBERS) then return nil, 'ERR_NO_PERMISSION' end
    MySQL.update.await('DELETE FROM nayzeee_racing_crew_invites WHERE crew_id = ? AND profile_id = ?', { p.crewId, tonumber(d.profileId) or 0 })
    return true
end)

Handle('crew:perms', function(_, p, d)
    if not Crews.Can(p, CrewPerm.MEMBERS) then return nil, 'ERR_NO_PERMISSION' end
    local c = Crews.Brief(p.crewId)
    local target = Profiles.Get(tonumber(d.profileId) or 0)
    if not target or target.crewId ~= c.id then return nil, 'PROFILE_NOT_FOUND' end
    if target.id == c.owner then return nil, 'CREW_OWNER_LOCKED' end
    local perms = cleanPerms(d.perms)
    if c.owner ~= p.id then
        for _, v in ipairs(perms) do if not has(p.crewPerms, v) then return nil, 'ERR_NO_PERMISSION' end end
    end
    setMember(target.id, c.id, perms)
    Crews.Activity(c.id, 'PERMISSIONS_UPDATED', L('ACT_PERMISSIONS', p.alias, target.alias))
    return true
end)

Handle('crew:kick', function(_, p, d)
    if not Crews.Can(p, CrewPerm.MEMBERS) then return nil, 'ERR_NO_PERMISSION' end
    local c = Crews.Brief(p.crewId)
    local target = Profiles.Get(tonumber(d.profileId) or 0)
    if not target or target.crewId ~= c.id then return nil, 'PROFILE_NOT_FOUND' end
    if target.id == c.owner or target.id == p.id then return nil, 'ERR_NO_PERMISSION' end
    setMember(target.id, nil)
    Crews.Activity(c.id, 'CREW_KICKED', L('ACT_CREW_KICKED', p.alias, target.alias))
    Profiles.Message(target.id, MsgType.STANDARD, L('MSG_CREW_KICKED', c.name))
    return true
end)

Handle('crew:respond', function(_, p, d)
    local msg = MySQL.single.await('SELECT metadata FROM nayzeee_racing_messages WHERE id = ? AND profile_id = ? AND type = ?',
        { tonumber(d.messageId) or 0, p.id, MsgType.CREW_INVITE })
    if not msg then return nil, 'MSG_NOT_FOUND' end
    local meta = DB.Decode(msg.metadata, {})
    local invite = MySQL.single.await('SELECT * FROM nayzeee_racing_crew_invites WHERE id = ? AND profile_id = ?', { meta.inviteId or 0, p.id })
    MySQL.update.await('DELETE FROM nayzeee_racing_messages WHERE id = ?', { tonumber(d.messageId) })
    if not invite then return nil, 'CREW_INVITE_GONE' end
    MySQL.update.await('DELETE FROM nayzeee_racing_crew_invites WHERE id = ?', { invite.id })
    if not d.accept then return true end
    if p.crewId then return nil, 'CREW_ALREADY_IN' end
    if not Crews.Brief(invite.crew_id) then return nil, 'CREW_NOT_FOUND' end
    if Config.Crews.MemberCap then
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM nayzeee_racing_profiles WHERE crew_id = ?', { invite.crew_id })
        if n >= Config.Crews.MemberCap then return nil, 'CREW_FULL' end
    end
    setMember(p.id, invite.crew_id, DB.Decode(invite.perms, {}))
    MySQL.update('DELETE FROM nayzeee_racing_crew_invites WHERE profile_id = ?', { p.id })
    Crews.Activity(invite.crew_id, 'CREW_JOINED', L('ACT_CREW_JOINED', p.alias))
    return true
end)
