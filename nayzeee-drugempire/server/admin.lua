--[[ Staff commands: /empireadmin <sub> <id> [value]  (ace: Config.Admin.ace) ]]

local USAGE = 'stage <id> <none|texted|meet|steal|setup> | xp <id> <amount> | kit <id> | water <id> | reset <id> | info <id>'

local function reply(src, msg)
    if src == 0 then print('[nzde] ' .. msg) else TriggerClientEvent('nzde:notify', src, msg, 'info') end
end

RegisterCommand(Config.Admin.command, function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Admin.ace) then return end
    local sub, target, value = args[1], tonumber(args[2]), args[3]
    if not sub or not target then return reply(src, USAGE) end
    local P = Profile.get(target)
    if not P then return reply(src, 'That player has no loaded profile') end

    if sub == 'stage' and value then
        P.story.stage = value
        if value == 'setup' then
            P.story.app = true
            P.story.met = true
            if not P.rv.owned then
                P.rv.owned = true
                local c = GetEntityCoords(GetPlayerPed(target))
                P.rv.pos = { x = c.x + 4.0, y = c.y, z = c.z, w = 0.0 }
                RV.spawn(target, P.rv.pos)
            end
            for _, cid in ipairs(Config.Story.starterCustomers) do Customers.unlock(target, cid, true) end
            Products.discover(target, 'ogkush')
            TriggerClientEvent('nzde:story:installed', target)
        elseif value == 'none' or value == 'texted' then
            Story.schedule(target)
        end
        Profile.dirty(target)
        Profile.sync(target)
        reply(src, ('stage set to %s'):format(value))
    elseif sub == 'xp' and tonumber(value) then
        Profile.addXp(target, tonumber(value), 'admin')
        reply(src, ('gave %s xp'):format(value))
    elseif sub == 'kit' then
        for _, it in ipairs(Config.Story.starterKit) do Inv.add(target, it.item, it.count) end
        reply(src, 'starter kit given')
    elseif sub == 'water' then
        P.water = Config.WateringCan.capacity
        TriggerClientEvent('nzde:water', target, P.water)
        reply(src, 'watering can filled')
    elseif sub == 'reset' then
        RV.store(target)
        DB.delete(Profile.identifier(target))
        Profile.unload(target)
        Profile.load(target)
        Story.restore(target)
        Profile.sync(target)
        TriggerClientEvent('nzde:reset', target)
        reply(src, 'profile reset')
    elseif sub == 'info' then
        local lvl = Profile.level(P)
        reply(src, ('%s | stage %s | %s (%d xp) | %d objects | %d products | earned %s'):format(
            P.name or target, P.story.stage, Utils.rankLabel(lvl), P.xp, Utils.count(P.objects), Utils.count(P.products), Utils.money(P.stats.earned)))
    else
        reply(src, USAGE)
    end
end, false)
