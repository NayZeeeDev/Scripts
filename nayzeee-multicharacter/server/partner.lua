if not NAYZEEE_LOCK_OK then return end
if not Config.Partner.enabled then return end

local T = NZ.T
local pending = {}   -- [target] = { from = src, fromChar, type, at }

local function active(src)
    local s = Sessions[src]
    return s and s.stage == 'playing' and s.active or nil
end

local function nameOf(src)
    local list = Characters.FetchByIds({ active(src) })
    local c = list[1]
    return c and (c.firstname .. ' ' .. c.lastname) or GetPlayerName(src)
end

lib.addCommand(Config.Partner.command, {
    help = T('c_partner'),
    params = {
        { name = 'id', type = 'playerId', help = 'Player id' },
        { name = 'type', type = 'string', help = 'couple | friend', optional = true },
    },
}, function(src, args)
    local target = args.id
    if not target or target == src then return TriggerClientEvent('nzm:client:notify', src, T('t_partner_self'), 'error') end
    local mine, theirs = active(src), active(target)
    if not mine or not theirs then return TriggerClientEvent('nzm:client:notify', src, T('t_relog_busy'), 'error') end
    local kind = (args.type == 'couple') and 'couple' or 'friend'
    pending[target] = { from = src, fromChar = mine, toChar = theirs, type = kind, at = os.time() }
    TriggerClientEvent('nzm:client:notify', src, T('t_partner_sent', GetPlayerName(target)), 'success')
    TriggerClientEvent('nzm:client:partnerInvite', target, nameOf(src), T(kind == 'couple' and 'couple' or 'friend'):lower())
end)

RegisterNetEvent('nzm:server:partnerAnswer', function(accept)
    local target = source
    local inv = pending[target]
    pending[target] = nil
    if not inv or os.time() - inv.at > 60 then return end
    if active(target) ~= inv.toChar or active(inv.from) ~= inv.fromChar then return end
    if accept == true then
        DB.Set(inv.fromChar, 'partner', inv.toChar); DB.Set(inv.fromChar, 'partner_type', inv.type)
        DB.Set(inv.toChar, 'partner', inv.fromChar); DB.Set(inv.toChar, 'partner_type', inv.type)
        TriggerClientEvent('nzm:client:notify', inv.from, T('t_partner_ok', nameOf(target)), 'success')
        TriggerClientEvent('nzm:client:notify', target, T('t_partner_ok', nameOf(inv.from)), 'success')
    else
        TriggerClientEvent('nzm:client:notify', inv.from, T('t_partner_no', GetPlayerName(target)), 'error')
    end
end)

AddEventHandler('playerDropped', function() pending[source] = nil end)
