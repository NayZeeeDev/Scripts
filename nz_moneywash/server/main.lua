--[[ THE WASH — boot ]]

local function boot()
    math.randomseed(os.time())
    DB.init()
    MySQL.query.await('DELETE FROM nzmw_batches WHERE updated_at < (NOW() - INTERVAL 7 DAY)')

    Batches.list = DB.loadBatches()
    local meta = DB.loadStationMeta()

    for _, op in ipairs(Config.Operations) do
        local access = op.access
        if access and not next(access) then access = nil end
        for i, s in ipairs(op.stations) do
            local id = ('%s:%d'):format(op.id, i)
            Stations.add({
                id = id, type = s.type, x = s.coords.x, y = s.coords.y, z = s.coords.z, h = s.coords.w,
                label = s.label, op = op.id, opLabel = op.label, access = access,
            }, meta[id])
        end
    end

    if Config.Placement.enabled then
        local rows = MySQL.query.await('SELECT * FROM nzmw_equipment') or {}
        for _, row in ipairs(rows) do
            local def = Placement.def(row)
            Stations.add(def, meta[def.id])
        end
    end

    Pallet.build()
    Market.start()
    Books.start()
    Stations.startTicker()

    local n = 0
    for _ in pairs(Stations.list) do n = n + 1 end
    print(('^2[nz_moneywash]^7 THE WASH online · %s/%s · %d machines · market %d%%'):format(
        Bridge.framework or '?', Bridge.inventory or '?', n, math.floor(Market.rate * 100)))
end

CreateThread(boot)

-- Admin: force a market event / audit (ace: command.nzmw)
lib.addCommand('nzmw', {
    help = 'THE WASH admin',
    params = {
        { name = 'action', type = 'string', help = 'event | audit | rate' },
        { name = 'arg', type = 'string', help = 'front id for audit', optional = true },
    },
    restricted = 'group.admin',
}, function(src, args)
    if args.action == 'event' then
        Market.event = nil
        local old = Config.Market.eventChance
        Config.Market.eventChance = 1.0
        Market.rollEvent()
        Config.Market.eventChance = old
        Bridge.notify(src, 'Market', Market.event and Market.event.label or 'No event', 'info')
    elseif args.action == 'audit' and args.arg then
        Books.startAudit(args.arg, 'admin')
    elseif args.action == 'rate' then
        Bridge.notify(src, 'Market', ('Rate %d%% · saturation %d%%'):format(math.floor(Market.rate * 100), math.floor((Market.saturation or 0) * 100)), 'info')
    end
end)
