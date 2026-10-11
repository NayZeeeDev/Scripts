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
    if type(target) == 'string' and #target > 8 then return target, nil end
end

local function inUse(charId)
    for _, s in pairs(Sessions) do
        if s.active == charId and s.stage == 'playing' then return true end
    end
    return false
end

-- ── player: relog ─────────────────────────────────────────────────────────
local rc = Config.Relog.command
if rc.enabled then
    lib.addCommand(rc.name, { help = T('c_relog'), restricted = rc.ace or false }, function(src)
        if src > 0 then Relog(src, false) end
    end)
end

-- ── admin ────────────────────────────────────────────────────────────────
lib.addCommand('mc_setslots', {
    help = T('c_setslots'), restricted = ADMIN,
    params = { { name = 'target', type = 'string', help = 'Server id or license' }, { name = 'extra', type = 'number', help = 'Extra slots' } },
}, function(src, args)
    local owner = ownerOf(args.target)
    if not owner then return reply(src, T('not_found'), 'error') end
    DB.SetExtra(owner, math.floor(args.extra), 'admin')
    Logs.Send('slots', src, { { 'Owner', owner }, { 'Extra', args.extra } })
    reply(src, T('done'), 'success')
end)

lib.addCommand('mc_addslots', {
    help = T('c_addslots'), restricted = ADMIN,
    params = { { name = 'target', type = 'string', help = 'Server id or license' }, { name = 'amount', type = 'number', help = 'Slots to add (negative removes)' } },
}, function(src, args)
    local owner = ownerOf(args.target)
    if not owner then return reply(src, T('not_found'), 'error') end
    local extra = math.max(0, DB.Extra(owner) + math.floor(args.amount))
    DB.SetExtra(owner, extra, 'admin')
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

lib.addCommand('mc_delchar', {
    help = T('c_delchar'), restricted = ADMIN,
    params = { { name = 'charid', type = 'string', help = 'ESX identifier (char1:xxx) or citizenid' } },
}, function(src, args)
    if inUse(args.charid) then return reply(src, T('t_relog_busy'), 'error') end
    if not Bridge.Delete(0, args.charid) then return reply(src, T('t_error'), 'error') end
    DB.Delete(args.charid)
    Logs.Send('admin', src, { { 'Action', 'delete' }, { 'Character', args.charid } })
    reply(src, T('done'), 'success')
end)

local function toggle(disabled)
    return function(src, args)
        DB.Ensure(args.charid, Characters.OwnerOf(args.charid) or 'unknown')
        DB.Set(args.charid, 'disabled', disabled and 1 or 0)
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

lib.addCommand('mc_coords', { help = T('c_coords'), restricted = ADMIN }, function(src)
    if src > 0 then TriggerClientEvent('nzm:client:coords', src) end
end)
