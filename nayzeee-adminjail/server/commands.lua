--[[
    Chat / console commands. Parsed here (not by ox_lib) so every failure tells the admin
    why: wrong usage, unknown player, not jailed, no permission.
]]

local cmds = Config.Commands

local function reply(src, msg, kind)
    Bridge.Notify(src, msg, kind)
end

local function resolveTarget(src, arg)
    if arg == 'me' and src ~= 0 then return src end
    local id = tonumber(arg)
    if id and GetPlayerName(id) then return id end
end

local function command(name, handler)
    RegisterCommand(name, function(src, args, raw)
        if not Bridge.HasPermission(src) then
            AJ.Debug(('/%s denied for %s (%s) - run "adminjail_perms %s" in the server console'):format(name, src, GetPlayerName(src), src))
            return reply(src, locale('no_permission'), 'error')
        end
        local ok, err = pcall(handler, src, args, raw)
        if not ok then
            print(('^1[%s] /%s failed:^7 %s'):format(AJ.Resource, name, err))
            reply(src, 'Command failed - see the server console', 'error')
        end
    end, false)
end

-- /ajail [id] [minutes] [reason...]
command(cmds.jail, function(src, args, raw)
    local minutes = tonumber(args[2])
    if not args[1] or not minutes then
        return reply(src, locale('usage_jail', cmds.jail), 'error')
    end

    local target = resolveTarget(src, args[1])
    if not target then return reply(src, locale('player_not_found'), 'error') end

    local reason = raw:match('^%S+%s+%S+%s+%S+%s+(.+)$')
    local ok, res = Sentences.Jail({
        source = target,
        minutes = minutes,
        reason = reason,
        admin = Bridge.GetAccountName(src),
    })
    if not ok then return reply(src, res, 'error') end
    reply(src, locale('jailed_admin', res.name, math.floor(minutes)), 'success')
end)

-- /aunjail [id]
command(cmds.unjail, function(src, args)
    if not args[1] then return reply(src, locale('usage_unjail', cmds.unjail), 'error') end

    local target = resolveTarget(src, args[1])
    if not target then return reply(src, locale('player_not_found'), 'error') end

    local e = Sentences.BySource(target)
    if not e then return reply(src, locale('not_jailed'), 'error') end

    Sentences.Release(e, 'released', Bridge.GetAccountName(src))
    reply(src, locale('released_admin', e.name), 'success')
end)

-- Server console only: explains why a player does or doesn't have access.
RegisterCommand('adminjail_perms', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    if not target or not GetPlayerName(target) then
        return print(('[%s] usage: adminjail_perms [server id]'):format(AJ.Resource))
    end
    local ok, via = Bridge.HasPermission(target)
    print(('[%s] %s (%s) - framework: %s - access: %s'):format(
        AJ.Resource, GetPlayerName(target), target, Bridge.Framework,
        ok and ('^2YES^7 via ' .. via) or '^1NO^7'))
    if not ok then
        print(('    checked aces %s and groups %s (as group.<name>, <name>, framework permission)'):format(
            json.encode(Config.Permissions.aces), json.encode(Config.Permissions.groups)))
        print(('    quick fix in server.cfg:  add_ace identifier.%s nayzeee.adminjail allow'):format(
            Bridge.GetLicense(target) or 'license:xxxx'))
    end
end, true)
