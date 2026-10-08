--[[ /heistadmin - staff tools. Requires the ACE in ServerConfig.AdminAce (console always allowed). ]]

local function reply(src, msg)
    if src == 0 then print('[nzh] ' .. msg) else FW.notify(src, msg, 'info') end
end

local commands = {}

commands.list = function(src)
    local n = 0
    for uid, inst in pairs(Engine.instances) do
        if not inst.finished then
            n = n + 1
            reply(src, ('%s | %s | stage %d/%d | members %d | %ds'):format(uid, inst.heistId, inst.stageIndex, #inst.stages, #inst.members, os.time() - inst.startedAt))
        end
    end
    if n == 0 then reply(src, 'No heists running.') end
end

commands.stop = function(src, args)
    local target = args[1]
    local n = 0
    for uid, inst in pairs(Engine.instances) do
        if not inst.finished and (target == 'all' or target == uid) then
            Engine.fail(inst, 'admin')
            n = n + 1
        end
    end
    reply(src, ('Stopped %d heist(s).'):format(n))
end

commands.cooldowns = function(src, args)
    Cooldowns.reset(args[1] or 'all')
    reply(src, 'Cooldowns reset: ' .. (args[1] or 'all'))
end

commands.xp = function(src, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount or not GetPlayerName(target) then return reply(src, 'usage: /heistadmin xp <id> <amount>') end
    Profile.addXp(target, amount)
    reply(src, ('Gave %d xp to %s'):format(amount, GetPlayerName(target)))
end

commands.setxp = function(src, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount or not GetPlayerName(target) then return reply(src, 'usage: /heistadmin setxp <id> <xp>') end
    Profile.setXp(target, amount)
    reply(src, ('Set %s xp to %d'):format(GetPlayerName(target), amount))
end

commands.featured = function(src, args)
    if not args[1] or not Heists.defs[args[1]] then return reply(src, 'usage: /heistadmin featured <heistId>') end
    GlobalState:set('nzh:featured', args[1], true)
    reply(src, 'Featured heist set to ' .. args[1])
end

RegisterCommand('heistadmin', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, ServerConfig.AdminAce) then
        return reply(src, locale('no_permission'))
    end
    local sub = table.remove(args, 1)
    local fn = sub and commands[sub]
    if not fn then
        return reply(src, 'heistadmin: list | stop <uid|all> | cooldowns [all|heist|player|location] | xp <id> <n> | setxp <id> <n> | featured <heistId>')
    end
    fn(src, args)
end, false)
