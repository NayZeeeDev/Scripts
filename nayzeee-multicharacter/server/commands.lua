if not NAYZEEE_LOCK_OK then return end

local T = NZ.T
local ADMIN = ServerConfig.AdminAce

local function reply(src, msg, kind)
    if src <= 0 then print('[nzm] ' .. msg) else TriggerClientEvent('nzm:client:notify', src, msg, kind or 'info') end
end

-- "12" (online id) or a raw owner key (license)
local function ownerOf(target)
    local id = tonumber(target)
    if id and GetPlayerName(id) then return Bridge.Owner(id), id end
    if type(target) == 'string' and #target > 8 and #target <= 64 then return target, nil end
end

-- ── player: relog ─────────────────────────────────────────────────────────
local rc = Config.Relog.command
if rc.enabled then
    lib.addCommand(rc.name, { help = T('c_relog'), restricted = rc.ace or false }, function(src)
        if src > 0 then Relog(src, false) end
    end)
end

-- ── admin: slots ──────────────────────────────────────────────────────────
lib.addCommand('mc_setslots', {
    help = T('c_setslots'), restricted = ADMIN,
    params = { { name = 'target', type = 'string', help = 'Server id or license' }, { name = 'extra', type = 'number', help = 'Extra slots' } },
}, function(src, args)
    local owner = ownerOf(args.target)
    if not owner then return reply(src, T('not_found'), 'error') end
    DB.SetExtra(owner, math.floor(args.extra))
    Logs.Send('slots', src, { { 'Owner', owner }, { 'Extra', args.extra } })
    reply(src, T('done'), 'success')
end)

lib.addCommand('mc_addslots', {
    help = T('c_addslots'), restricted = ADMIN,
    params = { { name = 'target', type = 'string', help = 'Server id or license' }, { name = 'amount', type = 'number', help = 'Slots to add (negative removes)' } },
}, function(src, args)
    local owner = ownerOf(args.target)
    if not owner then return reply(src, T('not_found'), 'error') end
    local extra = DB.AddExtra(owner, math.floor(args.amount))
    Logs.Send('slots', src, { { 'Owner', owner }, { 'Extra', extra } })
    reply(src, T('done') .. (' (%s)'):format(extra), 'success')
end)

lib.addCommand('mc_slotsinfo', {
    help = T('c_slotsinfo'), restricted = ADMIN,
    params = { { name = 'id', type = 'playerId', help = 'Server id' } },
}, function(src, args)
    local owner = Bridge.Owner(args.id)
    local total, info = Slots.Get(args.id, owner)
    reply(src, ('%s: %s slots (base %s from %s, +%s granted, cap %s)'):format(GetPlayerName(args.id), total, info.base, info.source, info.extra, info.max))
end)

-- Redeem code players type in Settings > Account
lib.addCommand('mc_code', {
    help = T('c_code'), restricted = ADMIN,
    params = {
        { name = 'code', type = 'string', help = 'Code (letters, numbers, - and _)' },
        { name = 'slots', type = 'number', help = 'Extra slots per redemption' },
        { name = 'uses', type = 'number', help = 'Total redemptions (one per player)', optional = true },
    },
}, function(src, args)
    local code = tostring(args.code)
    if #code > 64 or not code:match('^[%w%-_]+$') then return reply(src, T('t_invalid'), 'error') end
    local slots, uses = math.floor(args.slots), math.max(1, math.floor(args.uses or 1))
    MySQL.insert.await([[INSERT INTO `multichar_codes` (code, slots, uses, used, created_at) VALUES (?, ?, ?, 0, ?)
        ON DUPLICATE KEY UPDATE slots = VALUES(slots), uses = VALUES(uses)]], { code, slots, uses, os.time() })
    Logs.Send('admin', src, { { 'Action', 'code' }, { 'Code', code }, { 'Slots', slots }, { 'Uses', uses } })
    reply(src, T('done'), 'success')
end)

-- ── admin: characters ─────────────────────────────────────────────────────
lib.addCommand('mc_delchar', {
    help = T('c_delchar'), restricted = ADMIN,
    params = { { name = 'charid', type = 'string', help = 'ESX identifier (char1:xxx) or citizenid' } },
}, function(src, args)
    if not Validate.Id(args.charid) then return reply(src, T('not_found'), 'error') end
    if Sessions.Playing(args.charid) then return reply(src, T('t_relog_busy'), 'error') end
    local ok, done = pcall(Bridge.Delete, 0, args.charid)
    if not ok or not done then return reply(src, T('t_error'), 'error') end
    DB.Delete(args.charid)
    Squads.Purge(args.charid)
    Weapons.Forget(args.charid)
    Logs.Send('admin', src, { { 'Action', 'delete' }, { 'Character', args.charid } })
    reply(src, T('done'), 'success')
end)

local function toggle(disabled)
    return function(src, args)
        if not Validate.Id(args.charid) then return reply(src, T('not_found'), 'error') end
        DB.Ensure(args.charid, Characters.OwnerOf(args.charid) or 'unknown')
        DB.Set(args.charid, 'disabled', disabled)
        Squads.Notify(args.charid)
        Logs.Send('admin', src, { { 'Action', disabled and 'disable' or 'enable' }, { 'Character', args.charid } })
        reply(src, T('done'), 'success')
    end
end

lib.addCommand('mc_disable', {
    help = T('c_disable'), restricted = ADMIN,
    params = { { name = 'charid', type = 'string', help = 'Character id' } },
}, toggle(true))

lib.addCommand('mc_enable', {
    help = T('c_enable'), restricted = ADMIN,
    params = { { name = 'charid', type = 'string', help = 'Character id' } },
}, toggle(false))

lib.addCommand('mc_forcerelog', {
    help = T('c_forcerelog'), restricted = ADMIN,
    params = { { name = 'id', type = 'playerId', help = 'Server id' } },
}, function(src, args)
    local ok = Relog(args.id, true)
    reply(src, ok and T('done') or T('t_relog_busy'), ok and 'success' or 'error')
end)

-- ── admin: scene building ─────────────────────────────────────────────────
lib.addCommand('mc_coords', { help = T('c_coords'), restricted = ADMIN }, function(src)
    if src > 0 then TriggerClientEvent('nzm:client:coords', src) end
end)

lib.addCommand('mc_lobby', {
    help = T('c_lobby'), restricted = ADMIN,
    params = { { name = 'theme', type = 'string', help = table.concat(NZ.ThemeIds(), ' | ') } },
}, function(src, args)
    if src <= 0 then return end
    if not NZ.Theme(args.theme) then return reply(src, T('not_found') .. ': ' .. table.concat(NZ.ThemeIds(), ', '), 'error') end
    TriggerClientEvent('nzm:client:editor', src, args.theme)
end)

-- ── install doctor ────────────────────────────────────────────────────────
-- Catches the setup mistakes that break multicharacter scripts. Runs on start (Config.Doctor) and with /mc_doctor.
local function doctor()
    local problems, notes = {}, {}

    if NZ.Framework == 'none' then problems[#problems + 1] = 'No framework found (es_extended, qb-core or qbx_core).' end
    for _, dep in ipairs({ 'ox_lib', 'oxmysql' }) do
        if GetResourceState(dep) ~= 'started' then problems[#problems + 1] = dep .. ' is not started before this resource.' end
    end
    for _, res in ipairs(ServerConfig.Conflicts) do
        local st = GetResourceState(res)
        if st == 'started' or st == 'starting' then problems[#problems + 1] = ('"%s" is running. Stop or remove it; two multicharacters fight over the same player.'):format(res) end
    end

    if NZ.IsESX and Bridge.Ready then
        local deadline = GetGameTimer() + 10000
        while not Bridge.Ready() and GetGameTimer() < deadline do Wait(200) end
        local mc = Bridge.MulticharEnabled and Bridge.MulticharEnabled()
        if mc == false then
            problems[#problems + 1] = 'ESX multicharacter mode is OFF. In es_extended config set Config.Multichar = true, then restart.'
        elseif mc == nil then
            notes[#notes + 1] = 'Could not read ESX Config.Multichar. Make sure it is true.'
        end
    elseif NZ.IsQbox then
        notes[#notes + 1] = 'Qbox: set characters.useExternalCharacters = true in qbx_core/config/client.lua.'
    end

    -- config sanity
    if not NZ.Theme(Config.Scene.defaultTheme) then problems[#problems + 1] = ('Config.Scene.defaultTheme "%s" is not in config/themes.lua.'):format(tostring(Config.Scene.defaultTheme)) end
    for job, id in pairs(Config.Scene.autoByJob or {}) do
        if not NZ.Theme(id) then notes[#notes + 1] = ('Config.Scene.autoByJob.%s -> unknown theme "%s".'):format(job, id) end
    end
    for id, th in pairs(Config.LobbyThemes) do
        if th.mood and not NZ.MoodById(th.mood) then notes[#notes + 1] = ('Theme "%s" uses unknown mood "%s".'):format(id, th.mood) end
    end
    if Config.Pets.enabled and Config.Pets.access == 'bridge' then
        notes[#notes + 1] = 'Config.Pets.access = "bridge": link your pet script in bridge/server/pets.lua (PetBridge.Owned).'
    end

    if ServerConfig.Logs.enabled and GetConvar(ServerConfig.Logs.convar, '') == '' then
        notes[#notes + 1] = ('Logs are enabled but the "%s" convar is empty.'):format(ServerConfig.Logs.convar)
    end
    if ServerConfig.Tebex.enabled and GetConvar(ServerConfig.Tebex.convar, '') == '' then
        notes[#notes + 1] = ('Tebex redeem is enabled but "%s" is not set.'):format(ServerConfig.Tebex.convar)
    end
    if Config.Slots.discord.enabled and GetConvar(ServerConfig.DiscordTokenConvar, '') == '' then
        notes[#notes + 1] = ('Discord role slots are enabled but "%s" is not set.'):format(ServerConfig.DiscordTokenConvar)
    end

    print(('^6[nayzeee-multicharacter]^7 v%s  framework: ^5%s^7'):format(NZ.Version, NZ.Framework))
    if #problems == 0 then
        print('^2  Install looks good.^7')
    else
        for _, p in ipairs(problems) do print('^1  x ' .. p .. '^7') end
    end
    for _, n in ipairs(notes) do print('^3  ! ' .. n .. '^7') end
end

lib.addCommand('mc_doctor', { help = T('c_doctor'), restricted = ADMIN }, function(src)
    doctor()
    if src > 0 then reply(src, T('done'), 'success') end
end)

if Config.Doctor then
    CreateThread(function()
        Wait(4000)
        doctor()
    end)
end
