-- /wigadmin <action> <id> [value]
--   restore    <id>          give everything back (hair, haircut, eyebrows, beard, statuses)
--   givewig    <id> [tier]   give a freshly rolled wig (default style for their model)
--   givebundle <id> [grade]  give a hair bundle
--   resetcd    <id>          clear their snatch + tackle cooldowns
--   protect    <id> [mins]   protect them (0 = remove)
--   xp         <id> <amount> add reputation
--   glue       <id> [mins]   apply lace glue
--   status     <id> <kind>   burn | lice | dirt for 10 minutes ('clear' removes all)
--   free       <id>          untie them and release any hold on them

local function reply(src, msg)
    if src == 0 then print('[wigadmin] ' .. msg) else Notify(src, msg, 'info') end
end

local function randomHair(P)
    local m = Hair.PedModelKey(P.src) or 'f'
    return { m = m, d = math.random(1, 15), t = 0, c = math.random(0, 20), h = 0 }
end

lib.addCommand('wigadmin', {
    help = 'Wig Snatch admin',
    params = {
        { name = 'action', type = 'string', help = 'restore | givewig | givebundle | resetcd | protect | xp | glue | status | free' },
        { name = 'target', type = 'playerId', help = 'Server ID' },
        { name = 'value', type = 'string', help = 'Tier / grade / minutes / amount / status', optional = true },
    },
    restricted = ServerConfig.AdminAce,
}, function(src, args)
    local P = GetP(args.target)
    if not P then return reply(src, 'Player not loaded') end
    local action, value = args.action, args.value
    local who = src == 0 and 'console' or (GetP(src) and GetP(src).name or GetPlayerName(src))

    if action == 'restore' then
        P.hair.bald, P.hair.cut, P.hair.face, P.hair.status = nil, nil, nil, nil
        P.immuneUntil = 0
        Hair.Schedule(P)
        SaveP(P)
        Hair.Push(P, 'admin')
        Notify(P.src, L('restored'), 'success')
    elseif action == 'givewig' then
        local tier = value and TierIndex[value] and value or Wigs.RollTier(0)
        local meta = Wigs.Create(tier, randomHair(P), 'Admin', P.name)
        if not Wigs.Give(P.src, meta) then return reply(src, 'Inventory full') end
    elseif action == 'givebundle' then
        local meta = Wigs.CreateBundle(randomHair(P), 'Admin', value and GradeIndex[value] and value or nil)
        if not Wigs.Give(P.src, meta) then return reply(src, 'Inventory full') end
    elseif action == 'resetcd' then
        Clash.ResetCooldown(P.src)
    elseif action == 'protect' then
        local mins = tonumber(value) or 30
        P.protected = mins > 0
        if mins > 0 then
            local id = P.id
            SetTimeout(mins * 60000, function()
                local cur = GetP(P.src)
                if cur and cur.id == id then cur.protected = false end
            end)
        end
    elseif action == 'xp' then
        AddXP(P, tonumber(value) or 0)
        SaveP(P)
        SyncP(P)
    elseif action == 'glue' then
        P.row.glue_until = os.time() + (tonumber(value) or 20) * 60
        SaveP(P)
        SyncP(P)
    elseif action == 'status' then
        if value == 'clear' then
            P.hair.status = nil
            Hair.Schedule(P)
        elseif Config.Products.Status[value or ''] then
            Hair.SetStatus(P, value, 10)
        else
            return reply(src, 'Status must be burn, lice, dirt or clear')
        end
        SaveP(P)
        Hair.Push(P, 'admin')
    elseif action == 'free' then
        Restrain.Untie(P.src, 'admin')
        local holder = Restrain.HeldBy(P.src)
        if holder then Restrain.Release(holder, 'admin') end
        Restrain.Release(P.src, 'admin')
    else
        return reply(src, 'Unknown action')
    end
    reply(src, ('%s done for %s'):format(action, P.name))
    Log('admin', 'Admin action', ('**%s** used `%s` on **%s** %s'):format(who, action, P.name, value or ''))
end)
