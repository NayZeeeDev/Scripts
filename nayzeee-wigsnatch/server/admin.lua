-- /wigadmin <action> <id> [value]
--   restore  <id>          give their hair back (clears bald + haircut)
--   givewig  <id> [tier]   give a freshly rolled wig (uses their current hair, or a default style)
--   resetcd  <id>          clear their snatch cooldown
--   protect  <id> [mins]   protect them (0 = remove)
--   xp       <id> <amount> add reputation
--   glue     <id> [mins]   apply lace glue

local function reply(src, msg)
    if src == 0 then print('[wigadmin] ' .. msg) else Notify(src, msg, 'info') end
end

lib.addCommand('wigadmin', {
    help = 'Wig Snatch admin',
    params = {
        { name = 'action', type = 'string', help = 'restore | givewig | resetcd | protect | xp | glue' },
        { name = 'target', type = 'playerId', help = 'Server ID' },
        { name = 'value', type = 'string', help = 'Tier / minutes / amount', optional = true },
    },
    restricted = ServerConfig.AdminAce,
}, function(src, args)
    local P = GetP(args.target)
    if not P then return reply(src, 'Player not loaded') end
    local action, value = args.action, args.value
    local who = src == 0 and 'console' or (GetP(src) and GetP(src).name or GetPlayerName(src))

    if action == 'restore' then
        Hair.ClearBald(P)
        P.hair.cut = nil
        P.immuneUntil = 0
        SaveP(P)
        Hair.Push(P, 'admin')
        Notify(P.src, L('restored'), 'success')
    elseif action == 'givewig' then
        local tier = value and TierIndex[value] and value or Wigs.RollTier(0)
        local m = Hair.PedModelKey(P.src) or 'f'
        local meta = Wigs.Create(tier, { m = m, d = math.random(1, 15), t = 0, c = math.random(0, 20), h = 0 }, 'Admin', P.name)
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
    else
        return reply(src, 'Unknown action')
    end
    reply(src, ('%s done for %s'):format(action, P.name))
    Log('admin', 'Admin action', ('**%s** used `%s` on **%s** %s'):format(who, action, P.name, value or ''))
end)
