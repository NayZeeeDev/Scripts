NZ.Groups  = {}     -- name -> group
NZ.Staff   = {}     -- src  -> staff session
NZ.Online  = {}     -- src  -> { license, name, joined, discord }
NZ.Started = os.time()

local Routes = {}

-- ─── identifiers ────────────────────────────────────────────────────────
function NZ.Ids(src)
    local out = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        local kind = id and id:match('^(%w+):')
        if kind then out[kind] = id end
    end
    return out
end

function NZ.License(src)
    return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifierByType(src, 'license2')
end

function NZ.Name(src)
    if tonumber(src) == 0 then return 'Console' end
    local s = NZ.Staff[tonumber(src)]
    if s and s.nickname and s.nickname ~= '' then return s.nickname end
    return GetPlayerName(src) or ('#' .. tostring(src))
end

function NZ.Teleport(id, coords)
    if Hooks and Hooks.AllowMovement then pcall(Hooks.AllowMovement, id, 5) end
    TriggerClientEvent('nzadmin:cl:teleport', id, coords, true)
end

function NZ.Notify(src, msg, kind, title)
    TriggerClientEvent('nzadmin:cl:notify', src, msg, kind or 'info', title)
end

local function isOwner(src)
    local ids = NZ.Ids(src)
    for _, lic in ipairs(Config.Owners) do
        if ids.license == lic or ids.license2 == lic then return true end
    end
    return false
end

-- ─── groups ─────────────────────────────────────────────────────────────
function NZ.LoadGroups()
    local rows = MySQL.query.await('SELECT * FROM nz_admin_groups ORDER BY hierarchy DESC') or {}
    local groups = {}
    for _, r in ipairs(rows) do
        local list = json.decode(r.permissions or '[]') or {}
        local set, all = {}, false
        for _, p in ipairs(list) do if p == '*' then all = true else set[p] = true end end
        groups[r.name] = {
            id = r.id, name = r.name, label = r.label, color = r.color, hierarchy = r.hierarchy,
            list = list, perms = set, all = all, discord_role = r.discord_role,
            outfit = r.outfit and json.decode(r.outfit) or nil, sprite = r.sprite,
        }
    end
    NZ.Groups = groups
end

function NZ.GroupList()
    local out = {}
    for _, g in pairs(NZ.Groups) do
        out[#out + 1] = { id = g.id, name = g.name, label = g.label, color = g.color, hierarchy = g.hierarchy,
            permissions = g.list, discord_role = g.discord_role, sprite = g.sprite, hasOutfit = g.outfit ~= nil }
    end
    table.sort(out, function(a, b) return a.hierarchy > b.hierarchy end)
    return out
end

-- ─── discord role sync ──────────────────────────────────────────────────
local function discordRoles(discordId)
    local d = Config.Discord
    if not d.RoleSync or d.Token == '' or d.Guild == '' or not discordId then return nil end
    local p = promise.new()
    PerformHttpRequest(('https://discord.com/api/v10/guilds/%s/members/%s'):format(d.Guild, discordId), function(code, body)
        if code ~= 200 or not body then return p:resolve(nil) end
        local ok, data = pcall(json.decode, body)
        p:resolve(ok and data and data.roles or nil)
    end, 'GET', '', { Authorization = 'Bot ' .. d.Token })
    return Citizen.Await(p)
end

-- ─── staff session ──────────────────────────────────────────────────────
local function closeDuty(s)
    if not s or not s.duty or not Config.Staff.TrackDuty then return end
    local secs = os.time() - (s.dutyStart or os.time())
    if secs < 30 then return end
    MySQL.insert('INSERT INTO nz_admin_duty (license, started, ended, seconds) VALUES (?, FROM_UNIXTIME(?), NOW(), ?)', { s.license, s.dutyStart, secs })
    MySQL.update('UPDATE nz_admin_members SET total_duty = total_duty + ? WHERE license = ?', { secs, s.license })
end

function NZ.StaffPayload(src)
    local s = NZ.Staff[src]
    if not s then return { isStaff = false } end
    local g = s.group
    local perms = {}
    if g.all then perms = { '*' } else for p in pairs(g.perms) do perms[#perms + 1] = p end end
    return {
        isStaff = true, id = src, name = NZ.Name(src), license = s.license, duty = s.duty,
        group = { name = g.name, label = g.label, color = g.color, hierarchy = g.hierarchy },
        perms = perms,
    }
end

local function applyAce(src, group, add)
    if not Config.Ace.Enabled then return end
    local lic = NZ.License(src); if not lic then return end
    ExecuteCommand(('%s identifier.%s %s'):format(add and 'add_principal' or 'remove_principal', lic, Config.Ace.Principal:format(group)))
end

function NZ.SyncStaff(src)
    local s = NZ.Staff[src]
    Player(src).state:set('nzStaff', s and { label = s.group.label, color = s.group.color, duty = s.duty } or nil, true)
    TriggerClientEvent('nzadmin:cl:staff', src, NZ.StaffPayload(src))
end

function NZ.LoadStaff(src)
    src = tonumber(src)
    local ids = NZ.Ids(src)
    local lic = ids.license or ids.license2
    if not lic then return end
    local discordId = ids.discord and ids.discord:gsub('discord:', '')
    local member = MySQL.single.await('SELECT * FROM nz_admin_members WHERE license = ? OR license = ?', { ids.license or '', ids.license2 or '' })

    -- discord role sync can add, move or remove members
    local roles = discordRoles(discordId)
    if roles then
        local best
        for _, g in pairs(NZ.Groups) do
            if g.discord_role and g.discord_role ~= '' then
                for _, r in ipairs(roles) do
                    if r == g.discord_role and (not best or g.hierarchy > best.hierarchy) then best = g end
                end
            end
        end
        if best and (not member or member.group_name ~= best.name) then
            MySQL.query.await('INSERT INTO nz_admin_members (license, name, group_name, discord) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE group_name = VALUES(group_name)',
                { lic, GetPlayerName(src), best.name, discordId })
            member = MySQL.single.await('SELECT * FROM nz_admin_members WHERE license = ?', { lic })
        elseif not best and member then
            -- only members that came from a Discord linked group lose it, manual members stay
            local g = NZ.Groups[member.group_name]
            if g and g.discord_role and g.discord_role ~= '' then
                MySQL.update.await('DELETE FROM nz_admin_members WHERE id = ?', { member.id })
                member = nil
            end
        end
    end

    local group = member and NZ.Groups[member.group_name]
    if not group and isOwner(src) then
        group = { name = 'owner', label = 'Owner', color = Config.UI.Danger, hierarchy = 255, list = { '*' }, perms = {}, all = true }
        if NZ.Groups.owner then group = NZ.Groups.owner end
    end

    local was = NZ.Staff[src]
    if not group then
        if was then -- lost staff: close the duty session and drop ACE
            closeDuty(was)
            applyAce(src, was.group.name, false)
        end
        NZ.Staff[src] = nil
        NZ.SyncStaff(src)
        return
    end

    if isOwner(src) then -- config owners can never be locked out
        group = setmetatable({ all = true, hierarchy = 255 }, { __index = group })
    end

    if was and was.group.name ~= group.name then applyAce(src, was.group.name, false) end
    NZ.Staff[src] = {
        src = src, license = lic, group = group, member = member, nickname = member and member.nickname,
        duty = was and was.duty or Config.DefaultDuty, dutyStart = was and was.dutyStart or os.time(), discord = discordId,
    }
    if member then MySQL.update('UPDATE nz_admin_members SET name = ?, last_seen = NOW(), discord = COALESCE(?, discord) WHERE id = ?', { GetPlayerName(src), discordId, member.id }) end
    applyAce(src, group.name, true)
    NZ.SyncStaff(src)
    if not was and Config.StaffLoginNotify then
        NZ.ToStaff('nzadmin:cl:notify', { ('%s (%s) joined'):format(NZ.Name(src), group.label), 'info', 'Staff' }, nil, true, src)
    end
end

function NZ.HasPerm(src, perm)
    if src == 0 then return true end
    local s = NZ.Staff[tonumber(src)]
    if not s then return false end
    if s.group.all then return true end
    return s.group.perms[perm] == true
end

function NZ.Hierarchy(src)
    local s = NZ.Staff[tonumber(src)]
    return s and s.group.hierarchy or 0
end

--- Can src act on target? Blocks acting on staff at the same or higher level.
function NZ.CanTarget(src, target)
    if src == 0 or not Config.HierarchyProtection then return true end
    if tonumber(src) == tonumber(target) then return true end
    local th = NZ.Hierarchy(target)
    return th == 0 or NZ.Hierarchy(src) > th
end

--- Send a client event to staff. perm = required permission, dutyOnly = on duty only, skip = src to leave out.
function NZ.ToStaff(event, args, perm, dutyOnly, skip)
    for src, s in pairs(NZ.Staff) do
        if src ~= skip and (not dutyOnly or s.duty) and (not perm or NZ.HasPerm(src, perm)) then
            if type(args) == 'table' and args[1] ~= nil then TriggerClientEvent(event, src, table.unpack(args))
            else TriggerClientEvent(event, src, args) end
        end
    end
end

-- ─── duty ───────────────────────────────────────────────────────────────
function NZ.SetDuty(src, state)
    local s = NZ.Staff[src]; if not s then return false end
    if s.duty == state then return true end
    if not state then closeDuty(s) end
    s.duty = state
    s.dutyStart = os.time()
    NZ.SyncStaff(src)
    TriggerClientEvent('nzadmin:cl:duty', src, state, Config.Staff.DutyOutfits and s.group.outfit or nil)
    NZ.Log('staff', state and 'duty_on' or 'duty_off', src, nil, state and 'went on duty' or 'went off duty')
    return true
end

-- ─── logging ────────────────────────────────────────────────────────────
local colors = { staff = 0x08afa2, moderation = 0xe5484d, reports = 0xe5a50a, joins = 0x58a6ff, deaths = 0x63696d, money = 0x2ea043, developer = 0x9146ff, screenshots = 0x08afa2, chat = 0x9ea5aa }

function NZ.Webhook(category, title, description, fields, image)
    local url = Config.Logs.Webhooks[category]
    if not url or url == '' then return end
    local embed = { title = title, description = description, color = colors[category] or 0x08afa2, fields = fields,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), footer = { text = 'nayzeee-admin' } }
    if image then embed.image = { url = image } end
    PerformHttpRequest(url, function() end, 'POST', json.encode({ username = 'Admin Logs', embeds = { embed } }), { ['Content-Type'] = 'application/json' })
end

--- Log an action. staff and target can be server ids, a { name, license } table or nil.
function NZ.Log(category, action, staff, target, message, coords)
    if not Config.Logs.Enabled then return end
    local sName, sLic, tName, tLic
    if type(staff) == 'number' then
        if staff == 0 then sName = 'Console' else sName, sLic = NZ.Name(staff), NZ.License(staff) end
    elseif type(staff) == 'table' then sName, sLic = staff.name, staff.license end
    if type(target) == 'number' then tName, tLic = GetPlayerName(target), NZ.License(target)
    elseif type(target) == 'table' then tName, tLic = target.name, target.license end
    local x, y, z
    if type(coords) == 'table' or type(coords) == 'vector3' or type(coords) == 'vector4' then x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z) end
    message = tostring(message or '')
    action = tostring(action or 'action')

    MySQL.insert('INSERT INTO nz_admin_logs (category, action, staff_name, staff_license, target_name, target_license, message, x, y, z) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { category, action, sName, sLic, tName, tLic, message, x, y, z })

    local fields = {}
    if sName then fields[#fields + 1] = { name = 'Staff', value = sName, inline = true } end
    if tName then
        local val = tName
        if Config.Logs.TagDiscord and type(target) == 'number' then
            local d = GetPlayerIdentifierByType(target, 'discord')
            if d then val = val .. ' · <@' .. d:gsub('discord:', '') .. '>' end
        end
        fields[#fields + 1] = { name = 'Player', value = val, inline = true }
        if tLic then fields[#fields + 1] = { name = 'License', value = tLic } end
    end
    NZ.Webhook(category, action:gsub('_', ' '):gsub('^%l', string.upper), message, fields)
    NZ.ToStaff('nzadmin:cl:push', { 'log', { category = category, action = action, staff = sName, target = tName, message = message, time = os.time() } }, 'logs.view')
end

-- ─── rpc router ─────────────────────────────────────────────────────────
--- Register a panel action. perm may be a string, a list (any of) or false (any staff) or 'public' (anyone).
function NZ.Route(name, perm, fn) Routes[name] = { perm = perm, fn = fn } end

local function allowed(src, perm)
    if perm == 'public' then return true end
    if not NZ.Staff[src] then return false end
    if perm == false or perm == nil then return true end
    if type(perm) == 'table' then
        for _, p in ipairs(perm) do if NZ.HasPerm(src, p) then return true end end
        return false
    end
    return NZ.HasPerm(src, perm)
end

lib.callback.register('nzadmin:rpc', function(src, name, data)
    local r = Routes[name]
    if not r then return { ok = false, err = 'Unknown action' } end
    if not allowed(src, r.perm) then return { ok = false, err = 'You do not have permission for that.' } end
    local ok, res, err = pcall(r.fn, src, data or {})
    if not ok then
        print(('^1[nayzeee-admin] %s failed:^7 %s'):format(name, res))
        return { ok = false, err = 'Server error, check the console.' }
    end
    if res == false then return { ok = false, err = err or 'Action failed' } end
    return { ok = true, data = res }
end)

--- Common target check for player actions.
function NZ.Target(src, id, needHierarchy)
    id = tonumber(id)
    if not id or not GetPlayerName(id) then return nil, 'Player is not online.' end
    if needHierarchy ~= false and not NZ.CanTarget(src, id) then return nil, 'That staff member is above you.' end
    return id
end

-- ─── player tracking ────────────────────────────────────────────────────
local function trackJoin(src)
    local ids = NZ.Ids(src)
    local lic = ids.license or ids.license2; if not lic then return end
    NZ.Online[src] = { license = lic, name = GetPlayerName(src), joined = os.time(), discord = ids.discord and ids.discord:gsub('discord:', '') }
    MySQL.insert('INSERT INTO nz_admin_players (license, name, discord, sessions) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE name = VALUES(name), discord = COALESCE(VALUES(discord), discord), last_seen = NOW(), sessions = sessions + 1',
        { lic, GetPlayerName(src), NZ.Online[src].discord })
end

AddEventHandler('playerJoining', function()
    local src = source
    trackJoin(src)
    if Config.Logs.Joins then NZ.Log('joins', 'join', nil, src, ('%s joined'):format(GetPlayerName(src))) end
    if NZ.Booted then
        NZ.LoadStaff(src)
        if NZ.Online[src] then NZ.Online[src].staffLoaded = true end
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    local o = NZ.Online[src]
    if o then
        MySQL.update('UPDATE nz_admin_players SET playtime = playtime + ?, last_seen = NOW() WHERE license = ?', { os.time() - o.joined, o.license })
    end
    if Config.Logs.Joins then NZ.Log('joins', 'leave', nil, { name = GetPlayerName(src), license = o and o.license }, ('left: %s'):format(reason or '?')) end
    local s = NZ.Staff[src]
    if s then closeDuty(s); applyAce(src, s.group.name, false) end
    NZ.Staff[src] = nil
    NZ.Online[src] = nil
    TriggerEvent('nzadmin:sv:dropped', src)
end)

-- the client is ready to receive events now, staff was already loaded on join so only resend it
RegisterNetEvent('nzadmin:sv:ready', function()
    local src = source
    if not NZ.Online[src] then trackJoin(src) end
    local o = NZ.Online[src]
    if NZ.Booted and o and o.staffLoaded then NZ.SyncStaff(src)
    else
        NZ.LoadStaff(src)
        if o and NZ.Booted then o.staffLoaded = true end
    end
    TriggerEvent('nzadmin:sv:clientReady', src)
end)

-- chat log (Config.Logs.Chat), event driven
AddEventHandler('chatMessage', function(src, author, message)
    if not Config.Logs.Enabled or not Config.Logs.Chat then return end
    if type(message) ~= 'string' or message:sub(1, 1) == '/' then return end
    NZ.Log('chat', 'message', nil, tonumber(src), NZ.Trim(message, 500))
end)

-- ─── boot ───────────────────────────────────────────────────────────────
CreateThread(function()
    while not MySQL do Wait(100) end
    NZ.InstallSchema()
    NZ.LoadGroups()
    NZ.Booted = true
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        trackJoin(id)
        NZ.LoadStaff(id)
        if NZ.Online[id] then NZ.Online[id].staffLoaded = true end
    end
    TriggerEvent('nzadmin:sv:booted')
    print(('^6[nayzeee-admin]^7 v%s ready · %d groups'):format(NZ.Version, #NZ.GroupList()))
end)

-- player count samples (every 5 min) + daily cleanup
CreateThread(function()
    Wait(60000)
    while true do
        local staff = 0
        for _, s in pairs(NZ.Staff) do if s.duty then staff = staff + 1 end end
        MySQL.insert('INSERT IGNORE INTO nz_admin_stats (ts, players, staff) VALUES (?, ?, ?)', { os.time(), #GetPlayers(), staff })
        Wait(300000)
    end
end)

CreateThread(function()
    Wait(120000)
    while true do
        MySQL.update('DELETE FROM nz_admin_logs WHERE created_at < NOW() - INTERVAL ? DAY', { Config.Logs.KeepDays })
        MySQL.update('DELETE FROM nz_admin_stats WHERE ts < ?', { os.time() - 30 * 86400 })
        Wait(86400000)
    end
end)

-- ─── exports ────────────────────────────────────────────────────────────
exports('HasPermission', NZ.HasPerm)
exports('IsStaff', function(src) return NZ.Staff[tonumber(src)] ~= nil end)
exports('IsOnDuty', function(src) local s = NZ.Staff[tonumber(src)]; return s and s.duty or false end)
exports('GetStaffGroup', function(src) local s = NZ.Staff[tonumber(src)]; return s and s.group.name or nil end)
exports('Log', function(category, action, staff, target, message) NZ.Log(category, action, staff, target, message) end)
