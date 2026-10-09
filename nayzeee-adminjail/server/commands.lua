local cmds = Config.Commands

local function reply(src, msg, kind)
    Bridge.Notify(src, msg, kind)
end

lib.addCommand(cmds.jail, {
    help = locale('cmd_jail'),
    params = {
        { name = 'target', type = 'playerId', help = locale('cmd_target') },
        { name = 'minutes', type = 'number', help = locale('cmd_minutes') },
        { name = 'reason', type = 'longString', help = locale('cmd_reason'), optional = true },
    },
}, function(src, args)
    if not Bridge.HasPermission(src) then return reply(src, locale('no_permission'), 'error') end

    local ok, res = Sentences.Jail({
        source = args.target,
        minutes = args.minutes,
        reason = args.reason,
        admin = Bridge.GetAccountName(src),
    })
    if not ok then return reply(src, res, 'error') end
    reply(src, locale('jailed_admin', res.name, math.floor(args.minutes)), 'success')
end)

lib.addCommand(cmds.unjail, {
    help = locale('cmd_unjail'),
    params = {
        { name = 'target', type = 'playerId', help = locale('cmd_target') },
    },
}, function(src, args)
    if not Bridge.HasPermission(src) then return reply(src, locale('no_permission'), 'error') end

    local e = Sentences.BySource(args.target)
    if not e then return reply(src, locale('not_jailed'), 'error') end

    Sentences.Release(e, 'released', Bridge.GetAccountName(src))
    reply(src, locale('released_admin', e.name), 'success')
end)
