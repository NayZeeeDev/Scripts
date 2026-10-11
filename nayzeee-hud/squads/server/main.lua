-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- nayzeee-squads · server core
Squads  = {}   -- [id] = squad
Players = {}   -- [src] = squadId

local MenuOpen  = {}   -- [src] = true while the menu is open
local Vitals    = {}   -- [src] = { h, a, x, y, z }
local Cooldowns = {}
local nextId, nextMsg = 0, 0
-- temporary squads live above this offset so their ids can never collide with database ids
local TEMP_ID_BASE = 1000000
local nextTempId = TEMP_ID_BASE

local S = SquadsConfig.Strings
local floor, lower = math.floor, string.lower

-- ─── helpers ───────────────────────────────────────────────
local function cooldown(src, action, ms)
    local now = GetGameTimer()
    local c = Cooldowns[src]
    if not c then c = {}; Cooldowns[src] = c end
    if c[action] and now - c[action] < ms then return true end
    c[action] = now
    return false
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

--- The name a member goes by: their squad nickname when they've set one, otherwise their character name.
function Nick(rec)
    if not rec then return '' end
    return rec.nick or rec.name or ''
end

function SquadOf(src)
    local id = Players[src]
    return id and Squads[id] or nil
end

function Broadcast(sq, event, ...)
    for src in pairs(sq.online) do TriggerClientEvent(event, src, ...) end
end

local function identifierOf(src)
    return Bridge.GetIdentifier(src)
end

local function myRank(sq, src)
    local id = sq.online[src]
    local r = id and sq.roster[id]
    return r and r.rank or nil
end

local function can(sq, src, perm)
    return Ranks.Can(sq, myRank(sq, src), perm)
end

--- Permission check other modules can call.
function HasPerm(sq, src, perm) return can(sq, src, perm) end

local function onlineCount(sq)
    local n = 0
    for _ in pairs(sq.online) do n = n + 1 end
    return n
end

local function rosterCount(sq)
    local n = 0
    for _ in pairs(sq.roster) do n = n + 1 end
    return n
end

local function ownerOnline(sq)
    for src, id in pairs(sq.online) do
        if id == sq.owner then return src end
    end
    return nil
end

-- ─── validation ────────────────────────────────────────────
local function blocked(text)
    local l = lower(text)
    for i = 1, #SquadsConfig.BlockedWords do
        if l:find(SquadsConfig.BlockedWords[i], 1, true) then return true end
    end
    return false
end

local function validName(name, ignoreId)
    if type(name) ~= 'string' then return false, 'Enter a squad name' end
    name = trim(name)
    if #name < SquadsConfig.NameMin then return false, ('Use at least %d characters'):format(SquadsConfig.NameMin) end
    if #name > SquadsConfig.NameMax then return false, ('Keep it under %d characters'):format(SquadsConfig.NameMax + 1) end
    if not name:match("^[%w%s%-_%.']+$") then return false, 'Letters, numbers, spaces and - _ . only' end
    if blocked(name) then return false, 'That name is not allowed' end
    for id, sq in pairs(Squads) do
        if id ~= ignoreId and lower(sq.name) == lower(name) then return false, 'That name is taken' end
    end
    return true, name
end

local function validTag(tag, ignoreId)
    if tag == nil or tag == '' then return true, nil end
    if type(tag) ~= 'string' then return false, 'Invalid tag' end
    tag = trim(tag):upper()
    if #tag < SquadsConfig.TagMin or #tag > SquadsConfig.TagMax then
        return false, ('Tags are %d to %d characters'):format(SquadsConfig.TagMin, SquadsConfig.TagMax)
    end
    if not tag:match('^[%u%d]+$') then return false, 'Tags use letters and numbers only' end
    if blocked(tag) then return false, 'That tag is not allowed' end
    for id, sq in pairs(Squads) do
        if id ~= ignoreId and sq.tag and sq.tag:upper() == tag then return false, 'That tag is taken' end
    end
    return true, tag
end

local function validImage(url)
    if url == nil or url == '' then return true, nil end
    if type(url) ~= 'string' or #url > 300 or not url:match('^https://[^%s"\'<>]+$') then return false end
    if #SquadsConfig.ImageHosts == 0 then return true, url end
    local host = url:match('^https://([^/]+)')
    for i = 1, #SquadsConfig.ImageHosts do
        if host == SquadsConfig.ImageHosts[i] then return true, url end
    end
    return false
end

function validBlipColor(n)
    n = tonumber(n)
    if not n then return SquadsConfig.SquadBlip.DefaultColor end
    return math.max(0, math.min(85, math.floor(n)))
end

function validBlipSprite(n)
    n = tonumber(n)
    if not n then return SquadsConfig.SquadBlip.DefaultSprite end
    for i = 1, #SquadsConfig.SquadBlip.Sprites do
        if SquadsConfig.SquadBlip.Sprites[i].id == n then return n end
    end
    return SquadsConfig.SquadBlip.DefaultSprite
end

local function clampLimit(n)
    n = tonumber(n) or SquadsConfig.MaxMembers
    return math.max(SquadsConfig.MinMembers, math.min(SquadsConfig.MaxMembers, floor(n)))
end

-- ─── payloads ──────────────────────────────────────────────
local function memberList(sq)
    local out = {}
    for identifier, r in pairs(sq.roster) do
        out[#out + 1] = {
            id = r.src, identifier = identifier, name = Nick(r), realName = r.name, nick = r.nick, avatar = r.avatar,
            rank = r.rank, rankName = Ranks.Name(sq, r.rank), rankIcon = sq.ranks[r.rank] and sq.ranks[r.rank].icon or 'fa-user',
            owner = identifier == sq.owner, online = r.src ~= nil, downed = r.downed or false,
            kills = r.kills or 0, deaths = r.deaths or 0, assists = r.assists or 0, revives = r.revives or 0,
            joined = r.joined,
        }
    end
    table.sort(out, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

local function publicSquad(sq)
    local names = {}
    for _, r in pairs(sq.roster) do
        names[#names + 1] = { name = Nick(r), avatar = r.avatar, online = r.src ~= nil }
        if #names >= 12 then break end
    end
    local ownerRec = sq.roster[sq.owner]
    return {
        id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, locked = sq.password ~= nil,
        inviteOnly = sq.inviteOnly, limit = sq.limit, count = rosterCount(sq), online = onlineCount(sq),
        elo = sq.elo, tier = Combat.Tier(sq.elo), wins = sq.wins, losses = sq.losses,
        temporary = sq.temporary, blipColor = sq.blipColor, blipSprite = sq.blipSprite,
        allies = Allies.Count(sq), owner = Nick(ownerRec), members = names,
    }
end

--- Online members of every allied squad, keyed by server id, for blips and nametags.
local function allyMembers(sq)
    local out = {}
    if not SquadsConfig.Features.Affiliations then return out end
    for id in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then
            for src, identifier in pairs(other.online) do
                local rec = other.roster[identifier]
                if rec then
                    out[tostring(src)] = {
                        name = Nick(rec), squad = other.name, tag = other.tag,
                        rankName = Ranks.Name(other, rec.rank), blipColor = other.blipColor,
                        blipSprite = other.blipSprite,
                    }
                end
            end
        end
    end
    return out
end

local function privateSquad(sq)
    local vit = {}
    for src in pairs(sq.online) do
        local v = Vitals[src]
        if v then vit[tostring(src)] = v end
    end
    local progress, nextTier = Combat.TierProgress(sq.elo)
    return {
        id = sq.id, name = sq.name, tag = sq.tag, image = sq.image, locked = sq.password ~= nil,
        inviteOnly = sq.inviteOnly, limit = sq.limit, owner = sq.owner, persistent = sq.persistent,
        temporary = sq.temporary, blipColor = sq.blipColor, blipSprite = sq.blipSprite,
        allies = Allies.Payload(sq), allyRequests = Allies.Pending(sq), allyMax = SquadsConfig.Affiliations.MaxPerSquad,
        allyMembers = allyMembers(sq),
        ranks = sq.ranks, members = memberList(sq), vitals = vit, created = sq.created,
        elo = sq.elo, tier = Combat.Tier(sq.elo), tierProgress = progress, nextTier = nextTier,
        wins = sq.wins, losses = sq.losses, draws = sq.draws,
        kills = sq.kills, deaths = sq.deaths, assists = sq.assists,
        rally = sq.rally, ready = sq.ready and { ends = sq.ready.ends, answers = sq.ready.answers } or nil,
    }
end

--- Re-syncs every squad allied to this one, so their ally lists stay current.
function SyncAllies(sq)
    if not SquadsConfig.Features.Affiliations then return end
    for id in pairs(sq.allies or {}) do
        local other = Squads[id]
        if other then SyncSquad(other) end
    end
end

function SyncSquad(sq)
    local data = privateSquad(sq)
    for src in pairs(sq.online) do
        data.you = { rank = myRank(sq, src), perms = {} }
        for i = 1, #Ranks.Perms do
            data.you.perms[Ranks.Perms[i]] = can(sq, src, Ranks.Perms[i])
        end
        TriggerClientEvent('nz_squads:sync', src, data)
    end
end

local function listPayload()
    local list = {}
    for _, sq in pairs(Squads) do list[#list + 1] = publicSquad(sq) end
    table.sort(list, function(a, b) return a.elo > b.elo end)
    return list
end

local listDirty = false
local function markListDirty()
    if listDirty then return end
    listDirty = true
    SetTimeout(250, function()
        listDirty = false
        if not next(MenuOpen) then return end
        local list = listPayload()
        for src in pairs(MenuOpen) do TriggerClientEvent('nz_squads:list', src, list) end
    end)
end

-- ─── chat ──────────────────────────────────────────────────
local function pushChat(sq, msg)
    nextMsg = nextMsg + 1
    msg.id = nextMsg
    msg.t = os.time()
    local chat = sq.chat
    chat[#chat + 1] = msg
    if #chat > SquadsConfig.ChatHistory then table.remove(chat, 1) end
    Broadcast(sq, 'nz_squads:chat', msg)
end

local function system(sq, text)
    pushChat(sq, { system = true, text = text })
end

-- ─── membership ────────────────────────────────────────────
local function attach(sq, src, identifier, rec)
    sq.online[src] = identifier
    rec.src = src
    rec.downed = false
    rec.avatar = rec.avatar or Discord.Peek(src)
    sq.roster[identifier] = rec
    Players[src] = sq.id

    TriggerClientEvent('nz_squads:history', src, sq.chat)
    Roles.Sync(src)
    if not rec.avatar then
        Discord.Get(src, function(avatar)
            if not avatar or Squads[sq.id] ~= sq or sq.roster[identifier] ~= rec then return end
            rec.avatar = avatar
            SyncSquad(sq)
            markListDirty()
        end)
    end
end

local function addMember(sq, src, rank)
    local identifier = identifierOf(src)
    if not identifier then return false end
    local rec = sq.roster[identifier] or {
        name = Bridge.GetName(src), rank = rank or 1,
        kills = 0, deaths = 0, assists = 0, revives = 0, joined = os.time(),
    }
    rec.name = Bridge.GetName(src)
    attach(sq, src, identifier, rec)
    sq.invites[src] = nil
    DB.SaveMember(sq.id, identifier, rec)
    system(sq, S.joined:format(Nick(rec)))
    SyncSquad(sq)
    SyncAllies(sq)
    markListDirty()
    Webhook.Join(sq, src)
    return true
end

local function disband(sq, by, reason)
    Allies.ClearAll(sq)
    for src in pairs(sq.online) do
        Players[src] = nil
        sq.online[src] = nil
        TriggerClientEvent('nz_squads:sync', src, false, src == by and 'left' or 'closed')
        Roles.Clear(src)
    end
    Squads[sq.id] = nil
    DB.DeleteSquad(sq.id)
    markListDirty()
    Webhook.Disband(sq, by, reason)
end

--- Detaches an online player. `forget` also drops them from the roster.
local function removeMember(sq, src, reason, forget)
    local identifier = sq.online[src]
    if not identifier then return end
    local rec = sq.roster[identifier]
    local name = rec and Nick(rec) or ('Player %s'):format(src)

    sq.online[src] = nil
    Players[src] = nil
    if rec then rec.src = nil end
    TriggerClientEvent('nz_squads:sync', src, false, reason)
    Roles.Clear(src)

    if forget then
        sq.roster[identifier] = nil
        DB.RemoveMember(sq.id, identifier)
        if reason == 'kicked' then system(sq, S.kicked:format(name)) else system(sq, S.left:format(name)) end
    else
        system(sq, S.left:format(name))
    end

    local remaining = rosterCount(sq)
    if remaining == 0 or (not sq.persistent and onlineCount(sq) == 0) then
        if SquadsConfig.DisbandOnEmpty or not sq.persistent or remaining == 0 then
            return disband(sq, nil, 'empty')
        end
    end

    -- hand the squad over if the owner left for good
    if forget and identifier == sq.owner then
        local best, bestRank
        for id, r in pairs(sq.roster) do
            if not bestRank or r.rank > bestRank then best, bestRank = id, r.rank end
        end
        if best then
            sq.owner = best
            sq.roster[best].rank = #sq.ranks
            DB.SaveMember(sq.id, best, sq.roster[best])
            system(sq, S.new_leader:format(Nick(sq.roster[best])))
        end
    end

    DB.SaveSquad(sq)
    SyncSquad(sq)
    SyncAllies(sq)
    markListDirty()
end

-- ─── ready check & rally ───────────────────────────────────
local function endReady(sq)
    if not sq.ready then return end
    local answers = sq.ready.answers
    sq.ready = nil
    Broadcast(sq, 'nz_squads:readyResult', answers)
    SyncSquad(sq)
end

-- ─── callbacks ─────────────────────────────────────────────
lib.callback.register('nz_squads:getList', function(src)
    local invites, now = {}, os.time()
    for _, sq in pairs(Squads) do
        local exp = sq.invites[src]
        if exp then
            if exp > now then
                local ownerRec = sq.roster[sq.owner]
                invites[#invites + 1] = {
                    id = sq.id, name = sq.name, tag = sq.tag, image = sq.image,
                    owner = Nick(ownerRec), count = rosterCount(sq), limit = sq.limit,
                    elo = sq.elo, tier = Combat.Tier(sq.elo), expires = exp - now,
                }
            else
                sq.invites[src] = nil
            end
        end
    end
    return listPayload(), invites, { permanent = DB.On() and SquadsConfig.SquadTypes.AllowPermanent, reason = DB.Unavailable() }
end)

lib.callback.register('nz_squads:checkName', function(src, name)
    if cooldown(src, 'checkName', 150) then return true end
    local sq = SquadOf(src)
    local ok, res = validName(name, sq and sq.id or nil)
    return ok, not ok and res or nil
end)

lib.callback.register('nz_squads:create', function(src, data)
    if type(data) ~= 'table' then return false, 'Invalid request' end
    if not Bridge.CanUse(src) then return false, 'You cannot use squads' end
    if Players[src] then return false, 'Leave your current squad first' end
    if cooldown(src, 'create', 2000) then return false, S.cooldown end

    local identifier = identifierOf(src)
    if not identifier then return false, 'Could not identify your character' end

    local okName, name = validName(data.name)
    if not okName then return false, name end
    local okTag, tag = validTag(data.tag)
    if not okTag then return false, tag end
    local okImg, image = validImage(data.image)
    if not okImg then return false, 'Use an https image link from an allowed host' end

    -- temporary squads are never saved and never rated
    local T = SquadsConfig.SquadTypes
    local temporary
    if data.temporary == true then temporary = true
    elseif data.temporary == false then temporary = false
    else temporary = T.Default == 'temporary' end

    -- never quietly swap the type the player picked: say why it can't be made instead
    if temporary and not T.AllowTemporary then
        return false, 'Temporary squads are turned off on this server'
    end
    if not temporary then
        if not T.AllowPermanent then return false, 'Permanent squads are turned off on this server' end
        if not DB.On() then return false, DB.Unavailable() or 'Squads cannot be saved right now' end
    end

    local password = data.password
    if type(password) ~= 'string' or trim(password) == '' then password = nil
    elseif #password > 32 then return false, 'Password is too long' end

    if DB.On() and SquadsConfig.MaxSquadsPerPlayer > 0 then
        local owned = 0
        for _, sq in pairs(Squads) do
            if sq.owner == identifier then owned = owned + 1 end
        end
        if owned >= SquadsConfig.MaxSquadsPerPlayer then
            return false, 'You already own a squad. Disband it first.'
        end
    end

    local sq = {
        name = name, tag = tag, image = image, password = password,
        blipColor = validBlipColor(data.blipColor), blipSprite = validBlipSprite(data.blipSprite),
        limit = clampLimit(data.limit), inviteOnly = data.inviteOnly == true, temporary = temporary,
        owner = identifier, ranks = Ranks.Default(), created = os.time(),
        elo = SquadsConfig.Elo.Start, wins = 0, losses = 0, draws = 0, kills = 0, deaths = 0, assists = 0,
        roster = {}, online = {}, chat = {}, invites = {}, allies = {},
        persistent = (not temporary) and DB.On(),
    }

    if sq.persistent then
        local id = DB.CreateSquad(sq)
        if not id then return false, 'Could not save the squad' end
        sq.id = id
        if id > nextId then nextId = id end
    else
        nextTempId = nextTempId + 1
        sq.id = nextTempId
    end

    Squads[sq.id] = sq
    addMember(sq, src, #sq.ranks)
    Webhook.Create(sq, src)
    return true
end)

lib.callback.register('nz_squads:edit', function(src, data)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'edit') then return false, S.no_perm end
    if type(data) ~= 'table' then return false, 'Invalid request' end
    if cooldown(src, 'edit', 1000) then return false, S.cooldown end

    local okName, name = validName(data.name, sq.id)
    if not okName then return false, name end
    local okTag, tag = validTag(data.tag, sq.id)
    if not okTag then return false, tag end
    local okImg, image = validImage(data.image)
    if not okImg then return false, 'Use an https image link from an allowed host' end

    local limit = clampLimit(data.limit)
    if limit < rosterCount(sq) then return false, ('Your squad already has %d members'):format(rosterCount(sq)) end

    sq.name, sq.tag, sq.image, sq.limit, sq.inviteOnly = name, tag, image, limit, data.inviteOnly == true
    if data.blipColor ~= nil then sq.blipColor = validBlipColor(data.blipColor) end
    if data.blipSprite ~= nil then sq.blipSprite = validBlipSprite(data.blipSprite) end
    if data.clearPassword then
        sq.password = nil
    elseif type(data.password) == 'string' and trim(data.password) ~= '' then
        if #data.password > 32 then return false, 'Password is too long' end
        sq.password = data.password
    end

    DB.SaveSquad(sq)
    SyncSquad(sq)
    markListDirty()
    return true
end)

lib.callback.register('nz_squads:setRanks', function(src, list)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'ranks') then return false, S.no_perm end
    if cooldown(src, 'ranks', 800) then return false, S.cooldown end

    local ok, result = Ranks.Validate(list)
    if not ok then return false, result end

    local oldTop, newTop = #sq.ranks, #result
    sq.ranks = result

    -- keep everyone inside the new rank list, and keep the owner at the top
    for identifier, r in pairs(sq.roster) do
        if identifier == sq.owner then
            r.rank = newTop
        elseif r.rank > newTop then
            r.rank = newTop - 1
        elseif r.rank == oldTop and newTop ~= oldTop then
            r.rank = newTop - 1
        end
        DB.SaveMember(sq.id, identifier, r)
    end

    DB.SaveSquad(sq)
    SyncSquad(sq)
    Roles.SyncSquad(sq, true)
    return true
end)

lib.callback.register('nz_squads:setRank', function(src, target, level)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'promote') then return false, S.no_perm end

    local identifier = type(target) == 'string' and target or nil
    if not identifier then return false, 'Unknown member' end
    local rec = sq.roster[identifier]
    if not rec then return false, 'Unknown member' end
    if identifier == sq.owner then return false, 'You cannot change the owner\'s rank' end

    local mine = myRank(sq, src)
    level = Ranks.Clamp(sq, level)
    if mine < #sq.ranks then
        if rec.rank >= mine then return false, 'You can only manage ranks below your own' end
        if level >= mine then return false, 'You cannot set a rank at or above your own' end
    end
    if level >= #sq.ranks then return false, 'Transfer ownership instead' end

    rec.rank = level
    DB.SaveMember(sq.id, identifier, rec)
    system(sq, S.rank_set:format(Nick(rec), Ranks.Name(sq, level)))
    SyncSquad(sq)
    Roles.SyncSquad(sq)
    Webhook.Rank(sq, src, rec.src, Ranks.Name(sq, level))
    return true
end)

lib.callback.register('nz_squads:transfer', function(src, target)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if sq.online[src] ~= sq.owner then return false, 'Only the owner can transfer the squad' end
    local rec = type(target) == 'string' and sq.roster[target]
    if not rec or target == sq.owner then return false, 'Unknown member' end

    sq.roster[sq.owner].rank = #sq.ranks - 1
    DB.SaveMember(sq.id, sq.owner, sq.roster[sq.owner])
    sq.owner = target
    rec.rank = #sq.ranks
    DB.SaveMember(sq.id, target, rec)
    DB.SaveSquad(sq)
    system(sq, S.new_leader:format(Nick(rec)))
    SyncSquad(sq)
    markListDirty()
    Roles.SyncSquad(sq)
    Webhook.Rank(sq, src, rec.src, 'Owner')
    return true
end)

lib.callback.register('nz_squads:join', function(src, id, password)
    if not Bridge.CanUse(src) then return false, 'You cannot use squads' end
    if Players[src] then return false, 'Leave your current squad first' end
    if cooldown(src, 'join', 800) then return false, S.cooldown end

    local sq = Squads[tonumber(id)]
    if not sq then return false, 'That squad no longer exists' end

    local identifier = identifierOf(src)
    if not identifier then return false, 'Could not identify your character' end

    -- members already on the roster walk straight back in
    if sq.roster[identifier] then
        attach(sq, src, identifier, sq.roster[identifier])
        system(sq, S.joined:format(Nick(sq.roster[identifier])))
        SyncSquad(sq)
        markListDirty()
        return true
    end

    if rosterCount(sq) >= sq.limit then return false, 'That squad is full' end
    local invited = sq.invites[src] and sq.invites[src] > os.time()
    if not invited then
        if sq.inviteOnly then return false, 'This squad is invite only' end
        if sq.password and sq.password ~= password then return false, 'Wrong password' end
    end

    addMember(sq, src)
    return true
end)

lib.callback.register('nz_squads:leave', function(src, forget)
    local sq = SquadOf(src)
    if not sq then return false end
    local identifier = sq.online[src]
    if identifier == sq.owner and rosterCount(sq) > 1 and forget then
        return false, 'Transfer the squad to someone else first'
    end
    Webhook.Leave(sq, src)
    removeMember(sq, src, 'left', forget == true or not sq.persistent)
    return true
end)

lib.callback.register('nz_squads:kick', function(src, target)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'kick') then return false, S.no_perm end

    local identifier = type(target) == 'string' and target or nil
    local rec = identifier and sq.roster[identifier]
    if not rec or identifier == sq.online[src] then return false, 'You cannot remove that member' end
    if identifier == sq.owner then return false, 'You cannot remove the owner' end

    local mine = myRank(sq, src)
    if mine < #sq.ranks and rec.rank >= mine then return false, 'You can only remove members below your rank' end

    Webhook.Kick(sq, src, rec.src)
    if rec.src then
        TriggerClientEvent('nz_squads:notify', rec.src, S.you_kicked, 'error')
        removeMember(sq, rec.src, 'kicked', true)
    else
        sq.roster[identifier] = nil
        DB.RemoveMember(sq.id, identifier)
        system(sq, S.kicked:format(Nick(rec)))
        SyncSquad(sq)
        markListDirty()
    end
    return true
end)

lib.callback.register('nz_squads:disband', function(src)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'disband') then return false, S.no_perm end
    disband(sq, src, 'manual')
    return true
end)

lib.callback.register('nz_squads:invite', function(src, target)
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if not can(sq, src, 'invite') then return false, S.no_perm end
    if cooldown(src, 'invite', 1500) then return false, S.cooldown end

    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return false, 'No player with that ID' end
    if Players[target] then return false, 'That player is already in a squad' end
    if rosterCount(sq) >= sq.limit then return false, 'Your squad is full' end
    if not Bridge.CanUse(target) then return false, 'That player cannot use squads' end

    sq.invites[target] = os.time() + SquadsConfig.InviteExpireSec
    local me = sq.roster[sq.online[src]]
    TriggerClientEvent('nz_squads:invite', target, {
        id = sq.id, name = sq.name, tag = sq.tag, image = sq.image,
        from = Nick(me), fromAvatar = me and me.avatar,
        owner = Nick(sq.roster[sq.owner]),
        count = rosterCount(sq), limit = sq.limit, elo = sq.elo, tier = Combat.Tier(sq.elo),
        expires = SquadsConfig.InviteExpireSec,
    })
    return true, S.invite_sent:format(Bridge.GetName(target))
end)

lib.callback.register('nz_squads:declineInvite', function(src, id)
    local sq = Squads[tonumber(id)]
    if sq then sq.invites[src] = nil end
    return true
end)

lib.callback.register('nz_squads:chat', function(src, text)
    local sq = SquadOf(src)
    if not sq or type(text) ~= 'string' then return false end
    if cooldown(src, 'chat', SquadsConfig.ChatCooldownMs) then return false, S.cooldown end
    text = trim(text:gsub('[%c]', ' '))
    if text == '' then return false end
    if #text > SquadsConfig.ChatMaxLength then text = text:sub(1, SquadsConfig.ChatMaxLength) end
    local rec = sq.roster[sq.online[src]]
    pushChat(sq, { from = src, name = Nick(rec), avatar = rec and rec.avatar,
                   rank = rec and Ranks.Name(sq, rec.rank) or nil, text = text })
    return true
end)

-- ─── nicknames ─────────────────────────────────────────────
--- Checks a nickname and returns the cleaned value, or nil to clear it.
local function validNick(sq, identifier, nick)
    local N = SquadsConfig.Nicknames
    if nick == nil or nick == false then return true, nil end
    if type(nick) ~= 'string' then return false, 'Invalid nickname' end
    nick = trim(nick):gsub('%s+', ' ')
    if nick == '' then return true, nil end
    if #nick < N.MinLength then return false, ('Use at least %d characters'):format(N.MinLength) end
    if #nick > N.MaxLength then return false, ('Keep it to %d characters'):format(N.MaxLength) end
    if not nick:match("^[%w%s%-_%.']+$") then return false, 'Letters, numbers, spaces and - _ . only' end
    if blocked(nick) then return false, 'That nickname is not allowed' end

    -- nobody gets to pass themselves off as another member of the same squad
    local low = lower(nick)
    for id, r in pairs(sq.roster) do
        if id ~= identifier and (lower(r.name or '') == low or lower(r.nick or '') == low) then
            return false, 'Someone in your squad already goes by that name'
        end
    end
    return true, nick
end

local function applyNick(sq, identifier, nick, by)
    local rec = sq.roster[identifier]
    local before = Nick(rec)
    rec.nick = nick
    DB.SaveMember(sq.id, identifier, rec)
    if before ~= Nick(rec) then
        system(sq, nick and S.nick_set:format(before, nick) or S.nick_cleared:format(rec.name))
    end
    SyncSquad(sq)
    SyncAllies(sq)
    markListDirty()
end

--- Set your own nickname, or (with the kick permission) reset someone else's.
lib.callback.register('nz_squads:setNick', function(src, nick, target)
    if not SquadsConfig.Nicknames.Enabled then return false, 'Nicknames are turned off' end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    if cooldown(src, 'nick', SquadsConfig.Nicknames.CooldownSec * 1000) then
        return false, ('You can change it again in a moment')
    end

    local mine = sq.online[src]
    local identifier = mine
    if type(target) == 'string' and target ~= mine then
        -- someone else's nickname: staff-style reset only
        if not can(sq, src, 'kick') then return false, S.no_perm end
        if not sq.roster[target] then return false, 'Unknown member' end
        local myLevel, theirLevel = myRank(sq, src), sq.roster[target].rank
        if myLevel < #sq.ranks and theirLevel >= myLevel then
            return false, 'You can only reset nicknames below your rank'
        end
        applyNick(sq, target, nil, src)
        return true, 'Nickname reset'
    end

    if sq.temporary and not SquadsConfig.Nicknames.AllowInTemporary then
        return false, 'Nicknames are for permanent squads'
    end

    local ok, clean = validNick(sq, identifier, nick)
    if not ok then return false, clean end
    applyNick(sq, identifier, clean, src)
    return true, clean and ('You now go by %s'):format(clean) or 'Nickname cleared'
end)

if SquadsConfig.Nicknames.Enabled and SquadsConfig.Nicknames.Command and SquadsConfig.Nicknames.Command ~= '' then
    RegisterCommand(SquadsConfig.Nicknames.Command, function(src, args)
        if src == 0 then return end
        local sq = SquadOf(src)
        if not sq then return TriggerClientEvent('nz_squads:notify', src, 'You are not in a squad', 'error') end
        local nick = table.concat(args, ' ')
        local valid, clean = validNick(sq, sq.online[src], nick)
        if not valid then return TriggerClientEvent('nz_squads:notify', src, clean, 'error') end
        if cooldown(src, 'nick', SquadsConfig.Nicknames.CooldownSec * 1000) then
            return TriggerClientEvent('nz_squads:notify', src, 'You can change it again in a moment', 'error')
        end
        applyNick(sq, sq.online[src], clean, src)
        TriggerClientEvent('nz_squads:notify', src, clean and ('You now go by %s'):format(clean) or 'Nickname cleared', 'info')
    end, false)
end

lib.callback.register('nz_squads:readyCheck', function(src)
    local sq = SquadOf(src)
    if not sq or not SquadsConfig.Features.ReadyCheck then return false end
    if not can(sq, src, 'ready') then return false, S.no_perm end
    if sq.ready then return false, 'A ready check is already running' end
    if cooldown(src, 'ready', 10000) then return false, S.cooldown end

    local rec = sq.roster[sq.online[src]]
    sq.ready = { ends = os.time() + SquadsConfig.ReadyCheck.Duration, answers = {}, by = src }
    sq.ready.answers[tostring(src)] = true

    Broadcast(sq, 'nz_squads:readyCheck', { by = Nick(rec), duration = SquadsConfig.ReadyCheck.Duration })
    SyncSquad(sq)
    SetTimeout(SquadsConfig.ReadyCheck.Duration * 1000 + 200, function()
        if Squads[sq.id] == sq and sq.ready and sq.ready.ends <= os.time() then endReady(sq) end
    end)
    return true
end)

lib.callback.register('nz_squads:readyAnswer', function(src, answer)
    local sq = SquadOf(src)
    if not sq or not sq.ready then return false end
    sq.ready.answers[tostring(src)] = answer == true
    local answered = 0
    for _ in pairs(sq.ready.answers) do answered = answered + 1 end
    SyncSquad(sq)
    if answered >= onlineCount(sq) then endReady(sq) end
    return true
end)

lib.callback.register('nz_squads:rally', function(src, data)
    local sq = SquadOf(src)
    if not sq or not SquadsConfig.Features.Rally then return false end
    if not can(sq, src, 'rally') then return false, S.no_perm end

    if data == false then
        sq.rally = nil
        Broadcast(sq, 'nz_squads:rally', false)
        system(sq, S.rally_clear)
        SyncSquad(sq)
        return true
    end

    if type(data) ~= 'table' then return false end
    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z then return false end

    local rec = sq.roster[sq.online[src]]
    sq.rally = { x = x, y = y, z = z, by = Nick(rec), at = os.time() }
    Broadcast(sq, 'nz_squads:rally', sq.rally)
    system(sq, S.rally_set:format(sq.rally.by))
    SyncSquad(sq)
    return true
end)

lib.callback.register('nz_squads:stats', function(src)
    local sq = SquadOf(src)
    if not sq then return nil end
    local history = promise.new()
    DB.MatchHistory(sq.id, 10, function(rows) history:resolve(rows) end)
    return {
        members = memberList(sq),
        active = Combat.ActiveFor(sq.id),
        history = Citizen.Await(history),
    }
end)

lib.callback.register('nz_squads:leaderboard', function(src)
    if not SquadsConfig.Features.Leaderboard then return nil end
    local squads, players = promise.new(), promise.new()
    DB.TopSquads(25, function(rows) squads:resolve(rows) end)
    DB.TopPlayers(25, function(rows) players:resolve(rows) end)
    local sqRows = Citizen.Await(squads)
    for i = 1, #sqRows do sqRows[i].tierInfo = Combat.Tier(sqRows[i].elo) end
    return { squads = sqRows, players = Citizen.Await(players), persistent = DB.On() }
end)

-- ─── revive ────────────────────────────────────────────────
lib.callback.register('nz_squads:revive', function(src, target, item)
    if not SquadsConfig.Features.Revive then return false end
    local sq = SquadOf(src)
    if not sq then return false, 'You are not in a squad' end
    target = tonumber(target)
    if not target or target == src or not sq.online[target] then return false, 'They are not in your squad' end
    if cooldown(src, 'revive', SquadsConfig.Revive.Cooldown * 1000) then return false, 'Wait before reviving again' end

    local srcPed, tgtPed = GetPlayerPed(src), GetPlayerPed(target)
    if srcPed == 0 or tgtPed == 0 then return false, 'They are too far away' end
    if #(GetEntityCoords(srcPed) - GetEntityCoords(tgtPed)) > SquadsConfig.Revive.Distance + 2.0 then
        return false, 'They are too far away'
    end

    local def
    if item then
        for i = 1, #SquadsConfig.Revive.Items do
            if SquadsConfig.Revive.Items[i].item == item then def = SquadsConfig.Revive.Items[i] break end
        end
        if not def then return false, 'Unknown item' end
        if not Bridge.HasItem(src, def.item, 1) then return false, 'You do not have that item' end
    else
        if SquadsConfig.Revive.RequireItem then return false, 'You need a medical item' end
        def = SquadsConfig.Revive.Bare
    end

    if def.remove and not Bridge.RemoveItem(src, def.item, 1) then return false, 'You do not have that item' end

    Bridge.Revive(target, def.health)
    Combat.AddRevive(sq, src)

    local me  = sq.roster[sq.online[src]]
    local them = sq.roster[sq.online[target]]
    if them then them.downed = false end
    system(sq, S.revived:format(Nick(me), Nick(them)))
    Broadcast(sq, 'nz_squads:revived', { by = Nick(me), target = target, item = def.label })
    SyncSquad(sq)
    return true
end)

--- Items the player is actually carrying, so the picker only offers what they have.
lib.callback.register('nz_squads:reviveOptions', function(src)
    local out = {}
    for i = 1, #SquadsConfig.Revive.Items do
        local it = SquadsConfig.Revive.Items[i]
        if Bridge.HasItem(src, it.item, 1) then
            out[#out + 1] = { item = it.item, label = it.label, icon = it.icon, time = it.time, health = it.health }
        end
    end
    if not SquadsConfig.Revive.RequireItem then
        local b = SquadsConfig.Revive.Bare
        out[#out + 1] = { item = false, label = b.label, icon = b.icon, time = b.time, health = b.health }
    end
    return out
end)

-- ─── events ────────────────────────────────────────────────
RegisterNetEvent('nz_squads:menuState', function(open)
    MenuOpen[source] = open == true or nil
end)

RegisterNetEvent('nz_squads:playerReady', function()
    local src = source
    if Players[src] then return end
    local identifier = identifierOf(src)
    if not identifier then return end
    for _, sq in pairs(Squads) do
        if sq.roster[identifier] then
            attach(sq, src, identifier, sq.roster[identifier])
            system(sq, S.joined:format(Nick(sq.roster[identifier])))
            SyncSquad(sq)
            markListDirty()
            return
        end
    end
end)

RegisterNetEvent('nz_squads:setDowned', function(state)
    local src = source
    local sq = SquadOf(src)
    if not sq then return end
    local rec = sq.roster[sq.online[src]]
    if not rec then return end
    state = state == true
    if rec.downed == state then return end
    rec.downed = state
    Broadcast(sq, 'nz_squads:downed', src, state)

    if state and SquadsConfig.Features.DownedAlert then
        local ped = GetPlayerPed(src)
        if ped ~= 0 then
            local c = GetEntityCoords(ped)
            Broadcast(sq, 'nz_squads:ping', {
                type = 'downed', x = c.x, y = c.y, z = c.z, from = src, name = Nick(rec), auto = true,
            })
        end
    end
end)

RegisterNetEvent('nz_squads:ping', function(data)
    local src = source
    if not SquadsConfig.Features.Pings or type(data) ~= 'table' then return end
    local sq = SquadOf(src)
    if not sq then return end
    local def = SquadsConfig.Ping.Types[data.type]
    if not def or data.type == 'downed' then return end
    if cooldown(src, 'ping', SquadsConfig.Ping.CooldownMs) then return end

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if not x or not y or not z then return end

    if data.type ~= 'waypoint' then
        local ped = GetPlayerPed(src)
        if ped ~= 0 and #(GetEntityCoords(ped) - vec3(x, y, z)) > SquadsConfig.Ping.MaxDistance + 25.0 then return end
    elseif not SquadsConfig.Features.Waypoint then
        return
    end

    local rec = sq.roster[sq.online[src]]
    Broadcast(sq, 'nz_squads:ping', {
        type = data.type, x = x, y = y, z = z,
        net = tonumber(data.net), from = src, name = Nick(rec),
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    local sq = SquadOf(src)
    if sq then removeMember(sq, src, 'left', not sq.persistent) end
    MenuOpen[src], Vitals[src], Cooldowns[src] = nil, nil, nil
    Roles.Forget(src)
    for _, s in pairs(Squads) do s.invites[src] = nil end
end)

-- ─── vitals sync (only sends what changed) ─────────────────
CreateThread(function()
    local tick = 0
    local hasMax = GetEntityMaxHealth ~= nil
    while true do
        Wait(SquadsConfig.VitalsIntervalMs)
        tick = tick + 1
        local withCoords = tick % SquadsConfig.CoordsEveryTicks == 0

        for _, sq in pairs(Squads) do
            if onlineCount(sq) > 1 then
                local changed, count = {}, 0
                for src in pairs(sq.online) do
                    local ped = GetPlayerPed(src)
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local hp = GetEntityHealth(ped)
                        local max = hasMax and GetEntityMaxHealth(ped) or 200
                        local pct = max > 100 and floor(math.max(0, math.min(1, (hp - 100) / (max - 100))) * 100) or 0
                        local ar = GetPedArmour(ped)
                        local v = Vitals[src]
                        if not v then v = { h = -1, a = -1 }; Vitals[src] = v end

                        local dirty = v.h ~= pct or v.a ~= ar
                        v.h, v.a = pct, ar

                        if withCoords then
                            local c = GetEntityCoords(ped)
                            if not v.x or math.abs(c.x - v.x) > 3.0 or math.abs(c.y - v.y) > 3.0 then
                                v.x, v.y, v.z = floor(c.x), floor(c.y), floor(c.z)
                                dirty = true
                            end
                        end

                        if dirty then
                            changed[tostring(src)] = v
                            count = count + 1
                        end
                    end
                end
                if count > 0 then Broadcast(sq, 'nz_squads:vitals', changed) end
            end
        end
    end
end)

-- ─── temporary squad expiry ────────────────────────────────
if SquadsConfig.SquadTypes.TempMaxHours > 0 then
    CreateThread(function()
        local maxAge = SquadsConfig.SquadTypes.TempMaxHours * 3600
        while true do
            Wait(60000)
            local now = os.time()
            for _, sq in pairs(Squads) do
                if sq.temporary and now - sq.created >= maxAge then
                    for src in pairs(sq.online) do
                        TriggerClientEvent('nz_squads:notify', src, 'Your temporary squad timed out', 'error')
                    end
                    disband(sq, nil, 'expired')
                end
            end
        end
    end)
end

-- ─── boot ──────────────────────────────────────────────────
CreateThread(function()
    DB.Init()
    DB.PruneInactive()
    local stored, maxId = DB.LoadAll()
    for id, sq in pairs(stored) do
        sq.online = {}
        Squads[id] = sq
    end
    nextId = maxId
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, sq in pairs(Squads) do
        DB.SaveSquad(sq)
        for identifier, r in pairs(sq.roster) do DB.SaveMember(sq.id, identifier, r) end
    end
end)
