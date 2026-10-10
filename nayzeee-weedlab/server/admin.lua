--[[ Staff commands: /weedlabadmin <sub> <id> [value]  (ace: Config.Admin.ace) ]]

local USAGE = 'stage <id> <none|steal|deaddrop|hardware|setup|pack|sell|done> | xp <id> <amount> | level <id> <level> | rv <id> | lab <id> <small|warehouse> [entrance] | kit <id> | water <id> | reset <id> | info <id> | benson'

local function reply(src, msg)
    if src == 0 then print('[nzwl] ' .. msg) else TriggerClientEvent('nzwl:notify', src, msg, 'info') end
end

local KIT = {
    { 'nzw_pot', 3 }, { 'nzw_soil', 3 }, { 'nzw_seed_ogkush', 3 }, { 'nzw_wateringcan', 1 }, { 'nzw_trimmers', 1 },
    { 'nzw_packstation', 1 }, { 'nzw_baggie_empty', 20 }, { 'nzw_fertilizer', 2 },
}

local function giveRV(target, P)
    if P.labs.rv.owned then return end
    P.labs.rv.owned = true
    local c = GetEntityCoords(GetPlayerPed(target))
    P.labs.rv.pos = { x = c.x + 4.0, y = c.y, z = c.z, w = 0.0 }
    Labs.spawnRV(target, P.labs.rv.pos)
end

RegisterCommand(Config.Admin.command, function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Admin.ace) then return end
    local sub, target, value = args[1], tonumber(args[2]), args[3]
    if sub == 'benson' then
        local c = Config.Benson.spots[Story.spot]
        return reply(src, ('Uncle Benson: spot %d at %.1f, %.1f, %.1f'):format(Story.spot, c.x, c.y, c.z))
    end
    if not sub or not target then return reply(src, USAGE) end
    local P = Profile.get(target)
    if not P then return reply(src, 'That player has no loaded profile') end

    if sub == 'stage' and value then
        P.story.stage = value
        if value ~= 'none' and value ~= 'steal' then giveRV(target, P) end
        if value == 'deaddrop' then P.story.drop = P.story.drop or 1 end
        Profile.dirty(target)
        Profile.sync(target)
        reply(src, ('stage set to %s'):format(value))
    elseif sub == 'xp' and tonumber(value) then
        Profile.addXp(target, tonumber(value), 'Admin')
        reply(src, ('gave %s xp'):format(value))
    elseif sub == 'level' and tonumber(value) then
        local want, xp = math.floor(tonumber(value)), 0
        for l = 0, want - 1 do xp = xp + Utils.levelCost(l) end
        P.xp = xp
        Profile.dirty(target)
        Profile.sync(target)
        reply(src, ('level set to %d'):format(want))
    elseif sub == 'rv' then
        giveRV(target, P)
        Profile.sync(target)
        reply(src, 'RV given')
    elseif sub == 'lab' and Config.Labs[value or ''] and value ~= 'rv' then
        P.labs[value].owned = true
        P.labs[value].entrance = math.floor(tonumber(args[4]) or 1)
        Profile.dirty(target)
        Profile.sync(target)
        reply(src, ('%s given'):format(Config.Labs[value].label))
    elseif sub == 'kit' then
        for _, it in ipairs(KIT) do Inv.add(target, it[1], it[2]) end
        reply(src, 'starter kit given')
    elseif sub == 'water' then
        P.water = Config.WateringCan.capacity
        TriggerClientEvent('nzwl:water', target, P.water)
        reply(src, 'watering can filled')
    elseif sub == 'reset' then
        Labs.storeRV(target)
        DB.delete(Profile.identifier(target))
        Profile.unload(target)
        Profile.load(target)
        Profile.sync(target)
        TriggerClientEvent('nzwl:reset', target)
        reply(src, 'profile reset')
    elseif sub == 'info' then
        local lvl = Profile.level(P)
        local labs = {}
        for _, id in ipairs(Config.LabOrder) do
            if P.labs[id].owned then labs[#labs + 1] = ('%s (%d)'):format(id, Utils.count(P.labs[id].objects)) end
        end
        reply(src, ('%s | stage %s | %s (%d xp) | labs: %s | harvests %d | packaged %d'):format(
            P.name or target, P.story.stage, Utils.levelLabel(lvl), P.xp, #labs > 0 and table.concat(labs, ', ') or 'none',
            P.stats.harvests or 0, P.stats.packaged or 0))
    else
        reply(src, USAGE)
    end
end, false)
