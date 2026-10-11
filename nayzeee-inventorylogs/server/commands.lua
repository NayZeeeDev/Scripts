-- Commands and exports.
local C = Config.Commands

lib.addCommand(C.open, { help = 'Open the inventory manager' }, function(src)
    if src <= 0 then return NZ.Print('Open the panel in game.') end
    local perms = NZ.Perms(src)
    if not perms.view then return NZ.Notify(src, 'You do not have permission to use this.', 'error') end
    TriggerClientEvent('nzinv:open', src)
end)

local function reply(src, ok, msg)
    if src <= 0 then return NZ.Print(msg, ok and nil or 'error') end
    NZ.Notify(src, msg, ok and 'success' or 'error')
end

local function guard(src, tier)
    if src <= 0 or NZ.Can(src, tier) then return true end
    NZ.Notify(src, 'You do not have permission to use this.', 'error')
end

if C.give then
    lib.addCommand(C.give, {
        help = 'Give an item (logged)',
        params = {
            { name = 'target', type = 'playerId', help = 'Player id' },
            { name = 'item', type = 'string', help = 'Item name' },
            { name = 'count', type = 'number', help = 'Amount', optional = true },
        },
    }, function(src, a)
        if not guard(src, 'manage') then return end
        local ok, err = NZ.Call(src, 'inventory:give', { target = { id = a.target }, item = a.item, count = a.count or 1 })
        reply(src, ok, ok and ('Gave %s x%s to %s'):format(a.item, a.count or 1, GetPlayerName(a.target)) or err)
    end)
end

if C.remove then
    lib.addCommand(C.remove, {
        help = 'Remove an item (logged)',
        params = {
            { name = 'target', type = 'playerId', help = 'Player id' },
            { name = 'item', type = 'string', help = 'Item name' },
            { name = 'count', type = 'number', help = 'Amount, leave empty for all', optional = true },
        },
    }, function(src, a)
        if not guard(src, 'manage') then return end
        local ok, res = NZ.Call(src, 'inventory:remove', { target = { id = a.target }, item = a.item, count = a.count or 'all' })
        reply(src, ok, ok and ('Removed %s x%s from %s'):format(a.item, res, GetPlayerName(a.target)) or res)
    end)
end

if C.giveAll then
    lib.addCommand(C.giveAll, {
        help = 'Give an item to every player online (logged)',
        params = {
            { name = 'item', type = 'string', help = 'Item name' },
            { name = 'count', type = 'number', help = 'Amount each', optional = true },
        },
    }, function(src, a)
        if not guard(src, 'global') then return end
        local ok, res = NZ.Call(src, 'global:give', { item = a.item, count = a.count or 1 })
        reply(src, ok, ok and ('Gave %s to %d players (%d could not carry it)'):format(a.item, res.players, #res.full) or res)
    end)
end

if C.removeAll then
    lib.addCommand(C.removeAll, {
        help = 'Remove every copy of an item from online players (logged)',
        params = { { name = 'item', type = 'string', help = 'Item name' } },
    }, function(src, a)
        if not guard(src, 'global') then return end
        local ok, res = NZ.Call(src, 'global:remove', { item = a.item, scope = { online = true } })
        reply(src, ok, ok and ('Removed %s x%s from %d players'):format(a.item, res.total, res.inventories) or res)
    end)
end

-- ─── exports for other resources ───────────────────────────────────────────
local function logAdmin(kind, adminSource, target, itemName, itemLabel, count, method)
    local me = NZ.Actor(adminSource)
    local tgt = tonumber(target) and NZ.Actor(target) or { name = tostring(target), identifier = tostring(target) }
    InsertLog({ type = kind, source_name = me.name, source_identifier = me.identifier, source_id = me.id,
        target_name = tgt.name, target_identifier = tgt.identifier, target_id = tgt.id,
        item_name = itemName, item_label = itemLabel or itemName, item_count = count or 1, coords = me.coords,
        resource = GetInvokingResource(),
        details = ('%s %s %s x%s %s %s via %s'):format(me.name, kind == 'admin_give' and 'gave' or 'removed', itemLabel or itemName, count or 1,
            kind == 'admin_give' and 'to' or 'from', tgt.name, method or GetInvokingResource() or 'script') })
    local inv = tonumber(target)
    SendWebhook(kind, kind == 'admin_give' and 'Admin gave item' or 'Admin removed item', { admin = me, target = tgt,
        item = { name = itemName, label = itemLabel or itemName, count = count or 1 },
        from = kind == 'admin_remove' and inv or nil, to = kind == 'admin_give' and inv or nil,
        resource = GetInvokingResource(), coords = me.coords,
        details = ('%s %s %s x%s %s %s'):format(me.name, kind == 'admin_give' and 'gave' or 'removed', itemLabel or itemName, count or 1, kind == 'admin_give' and 'to' or 'from', tgt.name),
        extra = { { 'Method', method, true } } })
end

exports('LogAdminGive', function(...) logAdmin('admin_give', ...) end)
exports('LogAdminRemove', function(...) logAdmin('admin_remove', ...) end)
exports('InsertLog', function(l)
    if type(l) ~= 'table' then return end
    l.resource = l.resource or GetInvokingResource()
    InsertLog(l)
end)
exports('HasPermission', function(src, tier) return NZ.Can(src, tier or 'view') end)
