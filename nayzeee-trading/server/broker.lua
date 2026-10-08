Broker = {
    accounts = {},   -- id -> account
    owners = {},     -- owner -> { practice = account, live = account }
    online = {},     -- owner -> src
    orders = {},     -- id -> working order
    bySym = {},      -- symbol -> { [id] = order }
    dirty = {},
    nextId = 0,
}

Alerts = { byOwner = {}, bySym = {} }

local T = Config.Trading
local ORDER_TYPES = { market = true, limit = true, stop = true, trail = true }

-- ── helpers ─────────────────────────────────────────────────────

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function num(v)
    v = tonumber(v)
    if not v or v ~= v or v <= 0 or v == math.huge then return nil end
    return v
end

local function isCrypto(sym)
    local s = Market.by[sym]
    return s ~= nil and s.type == 'crypto'
end

function Broker.RoundQty(sym, q)
    local m = isCrypto(sym) and 10 ^ T.cryptoDecimals or 1
    return math.floor(q * m + 0.5) / m
end

local function mark(sym)
    local s = Market.by[sym]
    return s and s.price or 0
end

local function notify(owner, event, payload)
    local src = Broker.online[owner]
    if src then TriggerClientEvent(event, src, payload) end
end

-- ── account math ────────────────────────────────────────────────

function Broker.Equity(a)
    local e = a.cash
    for sym, p in pairs(a.positions) do e = e + p.qty * mark(sym) end
    return e
end

function Broker.Exposure(a)
    local x = 0
    for sym, p in pairs(a.positions) do x = x + math.abs(p.qty) * mark(sym) end
    return x
end

function Broker.Withdrawable(a)
    return math.max(0, math.min(a.cash, Broker.Equity(a) - Broker.Exposure(a) / T.leverage))
end

function Broker.Fee(sym, qty, price)
    if isCrypto(sym) then return round2(qty * price * Config.Fees.crypto.pct) end
    local f = Config.Fees.stock
    return round2(math.min(math.max(f.min, qty * f.perShare), qty * price * f.maxPct))
end

function Broker.Affordable(a, sym, signed, price)
    local pos = a.positions[sym]
    local cur = pos and pos.qty or 0
    local grow = (math.abs(cur + signed) - math.abs(cur)) * price
    if grow <= 0 then return true end
    local fee = Broker.Fee(sym, math.abs(signed), price)
    return Broker.Exposure(a) + grow <= (Broker.Equity(a) - fee) * T.leverage + 1e-6
end

local function marketPrice(s, side, qty)
    local p = side == 'buy' and s.ask or s.bid
    if T.slippage and s.vpt > 0 then
        local over = qty / (s.vpt * 30)
        if over > 1 then
            local slip = math.min(0.02, (over - 1) * 0.0008) * p
            p = Market.Round(p + (side == 'buy' and slip or -slip))
        end
    end
    return p
end

function Broker.Tradable(s, otype)
    if s.haltUntil > 0 then return false, s.sym .. ' is halted' end
    if s.type == 'crypto' then return true end
    local ses = Market.session
    if ses == 'open' then return true end
    if ses == 'closed' then return false, 'Market is closed' end
    if otype == 'limit' then return true end
    return false, 'Only limit orders trade in extended hours'
end

function Broker.TouchDay(a)
    if a.dayKey ~= Market.dayKey then
        a.dayStart, a.dayKey = Broker.Equity(a), Market.dayKey
        DB.SaveAccount(a)
    end
end

-- ── loading ─────────────────────────────────────────────────────

local function track(o)
    local a = Broker.accounts[o.acc]
    Broker.orders[o.id] = o
    a.orders[o.id] = o
    local set = Broker.bySym[o.sym]
    if not set then set = {} Broker.bySym[o.sym] = set end
    set[o.id] = o
end

local function untrack(o)
    Broker.orders[o.id] = nil
    local a = Broker.accounts[o.acc]
    if a then a.orders[o.id] = nil end
    local set = Broker.bySym[o.sym]
    if set then set[o.id] = nil end
end

local function hydrate(row)
    if Broker.accounts[row.id] then return Broker.accounts[row.id] end
    local a = {
        id = row.id, owner = row.owner, type = row.type,
        cash = tonumber(row.cash), realized = tonumber(row.realized), fees = tonumber(row.fees),
        trades = row.trades, dayStart = tonumber(row.day_start), dayKey = row.day_key, resetAt = row.reset_at,
        positions = {}, orders = {},
    }
    Broker.accounts[a.id] = a

    for _, p in ipairs(DB.GetPositions(a.id)) do
        if Market.by[p.symbol] then
            a.positions[p.symbol] = { qty = tonumber(p.qty), avg = tonumber(p.avg_price) }
        end
    end
    for _, r in ipairs(DB.GetWorkingOrders(a.id)) do
        if Market.by[r.symbol] then
            track({
                id = r.id, acc = a.id, sym = r.symbol, side = r.side, type = r.type, qty = tonumber(r.qty),
                limit = tonumber(r.limit_price), stop = tonumber(r.stop_price), trail = tonumber(r.trail),
                tif = r.tif, tp = tonumber(r.tp), sl = tonumber(r.sl), oco = r.oco, reduce = r.reduce == 1,
                status = 'working', created = r.created, updated = r.updated,
            })
        end
    end

    local set = Broker.owners[a.owner] or {}
    set[a.type] = a
    Broker.owners[a.owner] = set
    return a
end

function Broker.Init()
    Broker.nextId = DB.MaxOrderId()
    for _, row in ipairs(DB.ActiveAccountIds()) do
        local r = DB.GetAccount(row.account_id)
        if r then hydrate(r) end
    end
end

function Broker.LoadOwner(owner)
    local set = Broker.owners[owner]
    if set and set.practice and set.live then return set end
    for _, row in ipairs(DB.GetAccounts(owner)) do hydrate(row) end
    return Broker.owners[owner]
end

function Broker.Unload(owner)
    local set = Broker.owners[owner]
    if not set then return end
    for _, a in pairs(set) do
        if next(a.positions) or next(a.orders) then return end
    end
    for _, a in pairs(set) do Broker.accounts[a.id] = nil end
    Broker.owners[owner] = nil
end

function Broker.CreateAccounts(owner)
    MySQL.insert.await('INSERT IGNORE INTO nz_trading_accounts (owner, type, cash, day_start) VALUES (?, ?, ?, ?), (?, ?, ?, ?)', {
        owner, 'practice', Config.Practice.startingCash, Config.Practice.startingCash,
        owner, 'live', 0, 0,
    })
end

-- ── snapshots ───────────────────────────────────────────────────

local function orderView(o)
    return {
        id = o.id, sym = o.sym, side = o.side, type = o.type, qty = o.qty,
        limit = o.limit, stop = o.stop, trail = o.trail, tif = o.tif,
        tp = o.tp, sl = o.sl, oco = o.oco, reduce = o.reduce, created = o.created,
    }
end

function Broker.Snapshot(a)
    if not a then return nil end
    Broker.TouchDay(a)
    local positions, orders = {}, {}
    for sym, p in pairs(a.positions) do positions[#positions + 1] = { sym = sym, qty = p.qty, avg = p.avg } end
    for _, o in pairs(a.orders) do orders[#orders + 1] = orderView(o) end
    table.sort(orders, function(x, y) return x.id > y.id end)
    return {
        id = a.id, type = a.type, cash = a.cash, realized = a.realized, fees = a.fees, trades = a.trades,
        dayStart = a.dayStart, resetAt = a.resetAt, positions = positions, orders = orders,
    }
end

function Broker.MarkDirty(a) Broker.dirty[a.id] = a end

function Broker.Flush()
    for id, a in pairs(Broker.dirty) do
        Broker.dirty[id] = nil
        notify(a.owner, 'nz_trading:client:account', Broker.Snapshot(a))
    end
end

-- ── orders ──────────────────────────────────────────────────────

local function newOrder(a, t)
    Broker.nextId = Broker.nextId + 1
    local ts = os.time()
    return {
        id = Broker.nextId, acc = a.id, sym = t.sym, side = t.side, type = t.type, qty = t.qty,
        limit = t.limit, stop = t.stop, trail = t.trail, tif = t.tif or 'gtc', tp = t.tp, sl = t.sl,
        oco = t.oco, reduce = t.reduce or false, status = 'working', created = ts, updated = ts, isNew = true,
    }
end

local function persist(o)
    if o.isNew then
        o.isNew = nil
        DB.InsertOrder(o)
    else
        DB.UpdateOrder(o)
    end
end

function Broker.Cancel(a, o, status, reason)
    o.status, o.reason, o.updated = status or 'cancelled', reason, os.time()
    untrack(o)
    persist(o)
    notify(a.owner, 'nz_trading:client:order', { acc = a.type, kind = o.status, id = o.id, sym = o.sym, side = o.side, type = o.type, qty = o.qty, reason = reason })
    Broker.MarkDirty(a)
end

local function exitOrder(a, parent, t)
    local o = newOrder(a, {
        sym = parent.sym, side = parent.side == 'buy' and 'sell' or 'buy', qty = parent.qty,
        type = t.type, limit = t.limit, stop = t.stop, oco = parent.id, reduce = true, tif = 'gtc',
    })
    track(o)
    persist(o)
end

function Broker.Fill(a, o, px)
    local signed = o.side == 'buy' and o.qty or -o.qty
    local fee = Broker.Fee(o.sym, o.qty, px)
    local pos = a.positions[o.sym] or { qty = 0, avg = 0 }
    local cur, realized = pos.qty, 0

    if cur == 0 or (cur > 0) == (signed > 0) then
        local nq = Broker.RoundQty(o.sym, cur + signed)
        pos.avg = (math.abs(cur) * pos.avg + o.qty * px) / math.abs(nq)
        pos.qty = nq
    else
        local closing = math.min(math.abs(cur), o.qty)
        realized = round2(closing * (px - pos.avg) * (cur > 0 and 1 or -1))
        local nq = Broker.RoundQty(o.sym, cur + signed)
        if nq ~= 0 and (nq > 0) ~= (cur > 0) then pos.avg = px end
        pos.qty = nq
    end

    a.positions[o.sym] = pos.qty ~= 0 and pos or nil
    a.cash = a.cash - signed * px - fee
    a.realized = a.realized + realized
    a.fees = a.fees + fee
    a.trades = a.trades + 1

    o.status, o.fillPrice, o.updated = 'filled', px, os.time()
    untrack(o)
    persist(o)
    DB.InsertFill({ acc = a.id, order = o.id, sym = o.sym, side = o.side, qty = o.qty, price = px, fee = fee, realized = realized, time = o.updated })
    DB.SavePosition(a.id, o.sym, a.positions[o.sym])
    DB.SaveAccount(a)

    local s = Market.by[o.sym]
    if s then s.volume = s.volume + o.qty end

    if o.oco then
        for _, other in pairs(a.orders) do
            if other.oco == o.oco then Broker.Cancel(a, other, 'cancelled', 'OCO: other leg filled') end
        end
    end

    if not o.reduce and (o.tp or o.sl) then
        if o.tp then exitOrder(a, o, { type = 'limit', limit = o.tp }) end
        if o.sl then exitOrder(a, o, { type = 'stop', stop = o.sl }) end
    end

    notify(a.owner, 'nz_trading:client:fill', {
        acc = a.type, id = o.id, sym = o.sym, side = o.side, type = o.type, qty = o.qty,
        price = px, fee = fee, realized = realized, time = o.updated,
    })
    Broker.MarkDirty(a)
end

function Broker.Place(a, d)
    local sym = type(d.symbol) == 'string' and d.symbol or ''
    local s = Market.by[sym]
    if not s or not s.tradable then return nil, 'This symbol is not tradable' end

    local side = (d.side == 'buy' or d.side == 'sell') and d.side or nil
    local otype = ORDER_TYPES[d.type] and d.type or nil
    if not side or not otype then return nil, 'Invalid order' end

    local qty = Broker.RoundQty(sym, num(d.qty) or 0)
    if qty <= 0 then return nil, 'Enter a quantity' end
    if qty * s.price > T.maxNotional then return nil, 'Order exceeds the maximum order value' end

    local limit, stop, trail = num(d.limit), num(d.stop), num(d.trail)
    if otype == 'limit' and not limit then return nil, 'Enter a limit price' end
    if otype == 'stop' and not stop then return nil, 'Enter a stop price' end
    if otype == 'trail' and not trail then return nil, 'Enter a trail amount' end
    limit = limit and Market.Round(limit)
    stop = stop and Market.Round(stop)

    local tp, sl = num(d.tp), num(d.sl)
    tp, sl = tp and Market.Round(tp), sl and Market.Round(sl)
    if tp or sl then
        local ref = limit or stop or (side == 'buy' and s.ask or s.bid)
        local up = side == 'buy'
        if tp and (up and tp <= ref or not up and tp >= ref) then return nil, 'Take profit is on the wrong side of entry' end
        if sl and (up and sl >= ref or not up and sl <= ref) then return nil, 'Stop loss is on the wrong side of entry' end
    end

    local pos = a.positions[sym]
    local cur = pos and pos.qty or 0
    local signed = side == 'buy' and qty or -qty
    if cur + signed < 0 and (not T.allowShort or (s.type == 'crypto' and not T.shortCrypto)) then
        return nil, 'Short selling is not available for ' .. sym
    end

    local spec = {
        sym = sym, side = side, type = otype, qty = qty, limit = limit, stop = stop, trail = trail,
        tif = d.tif == 'day' and 'day' or 'gtc', tp = tp, sl = sl,
    }

    if otype == 'market' then
        local ok, why = Broker.Tradable(s, 'market')
        if not ok then return nil, why end
        local px = marketPrice(s, side, qty)
        if not Broker.Affordable(a, sym, signed, px) then return nil, 'Insufficient buying power' end
        local o = newOrder(a, spec)
        Broker.Fill(a, o, px)
        return o
    end

    local count = 0
    for _ in pairs(a.orders) do count = count + 1 end
    if count >= T.maxWorking then return nil, 'Too many working orders' end

    local ref = limit or stop or s.price
    if not Broker.Affordable(a, sym, signed, ref) then return nil, 'Insufficient buying power' end

    if otype == 'trail' then
        spec.stop = Market.Round(side == 'sell' and s.bid - trail or s.ask + trail)
    end

    local o = newOrder(a, spec)
    track(o)
    persist(o)
    notify(a.owner, 'nz_trading:client:order', { acc = a.type, kind = 'working', id = o.id, sym = sym, side = side, type = otype, qty = qty })
    Broker.MarkDirty(a)
    return o
end

local function evaluate(a, o, s, now)
    if not Broker.Tradable(s, o.type) then return end
    local px
    if o.type == 'limit' then
        if o.side == 'buy' and s.ask <= o.limit then px = math.min(o.limit, s.ask)
        elseif o.side == 'sell' and s.bid >= o.limit then px = math.max(o.limit, s.bid) end
    elseif o.type == 'stop' then
        if (o.side == 'buy' and s.ask >= o.stop) or (o.side == 'sell' and s.bid <= o.stop) then
            px = marketPrice(s, o.side, o.qty)
        end
    elseif o.type == 'trail' then
        local moved
        if o.side == 'sell' then
            local ns = Market.Round(s.bid - o.trail)
            if ns > o.stop then o.stop, moved = ns, true end
            if s.bid <= o.stop then px = marketPrice(s, 'sell', o.qty) end
        else
            local ns = Market.Round(s.ask + o.trail)
            if ns < o.stop then o.stop, moved = ns, true end
            if s.ask >= o.stop then px = marketPrice(s, 'buy', o.qty) end
        end
        if moved and not px then
            Broker.MarkDirty(a)
            if now - (o.savedAt or 0) >= 10 then
                o.savedAt, o.updated = now, now
                DB.UpdateOrder(o)
            end
        end
    end
    if not px then return end

    if o.reduce then
        local pos = a.positions[o.sym]
        local cur = pos and pos.qty or 0
        local closes = (o.side == 'sell' and cur > 0) or (o.side == 'buy' and cur < 0)
        if not closes then return Broker.Cancel(a, o, 'cancelled', 'Position already closed') end
        o.qty = math.min(o.qty, math.abs(cur))
    end

    local signed = o.side == 'buy' and o.qty or -o.qty
    if not Broker.Affordable(a, o.sym, signed, px) then
        return Broker.Cancel(a, o, 'rejected', 'Insufficient buying power')
    end
    Broker.Fill(a, o, px)
end

function Broker.Flatten(a, sym, force)
    for _, o in pairs(a.orders) do
        if not sym or o.sym == sym then Broker.Cancel(a, o, 'cancelled', 'Flatten') end
    end
    local closed, err = 0, nil
    for psym, p in pairs(a.positions) do
        if not sym or psym == sym then
            local s = Market.by[psym]
            local ok, why = Broker.Tradable(s, 'market')
            if ok or force then
                local side = p.qty > 0 and 'sell' or 'buy'
                local qty = math.abs(p.qty)
                local o = newOrder(a, { sym = psym, side = side, type = 'market', qty = qty, reduce = true })
                Broker.Fill(a, o, ok and marketPrice(s, side, qty) or s.price)
                closed = closed + 1
            else
                err = why
            end
        end
    end
    return closed, err
end

function Broker.Reset(a)
    for _, o in pairs(a.orders) do Broker.Cancel(a, o, 'cancelled', 'Account reset') end
    a.positions = {}
    DB.ClearPositions(a.id)
    a.cash, a.realized, a.fees, a.trades = Config.Practice.startingCash, 0, 0, 0
    a.dayStart, a.dayKey, a.resetAt = a.cash, Market.dayKey, os.time()
    DB.SaveAccount(a)
    DB.InsertLedger(a.id, 'reset', a.cash)
    Broker.MarkDirty(a)
end

function Broker.OnRollover()
    for _, a in pairs(Broker.accounts) do
        for _, o in pairs(a.orders) do
            if o.tif == 'day' then Broker.Cancel(a, o, 'expired', 'Day order expired') end
        end
        Broker.TouchDay(a)
        Broker.MarkDirty(a)
    end
end

function Broker.Tick(now)
    for sym, set in pairs(Broker.bySym) do
        local s = Market.by[sym]
        if s and next(set) then
            local ids = {}
            for id in pairs(set) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local o = Broker.orders[id]
                local a = o and Broker.accounts[o.acc]
                if a then evaluate(a, o, s, now) end
            end
        end
    end

    for _, a in pairs(Broker.accounts) do
        if next(a.positions) then
            local ex = Broker.Exposure(a)
            if ex > 0 and Broker.Equity(a) < ex * T.maintenance then
                Broker.Flatten(a, nil, true)
                notify(a.owner, 'nz_trading:client:margin', { acc = a.type })
            end
        end
    end

    Alerts.Check()
    Broker.Flush()
end

-- ── price alerts ────────────────────────────────────────────────

local function addAlert(owner, id, sym, cond, price)
    local al = { id = id, owner = owner, sym = sym, cond = cond, price = price }
    Alerts.byOwner[owner] = Alerts.byOwner[owner] or {}
    Alerts.byOwner[owner][id] = al
    Alerts.bySym[sym] = Alerts.bySym[sym] or {}
    Alerts.bySym[sym][id] = al
end

local function dropAlert(al)
    if Alerts.byOwner[al.owner] then Alerts.byOwner[al.owner][al.id] = nil end
    if Alerts.bySym[al.sym] then Alerts.bySym[al.sym][al.id] = nil end
end

function Alerts.Load(owner)
    if Alerts.byOwner[owner] then return end
    Alerts.byOwner[owner] = {}
    for _, r in ipairs(DB.GetAlerts(owner)) do
        if Market.by[r.symbol] then addAlert(owner, r.id, r.symbol, r.cond, tonumber(r.price)) end
    end
end

function Alerts.Unload(owner)
    for _, al in pairs(Alerts.byOwner[owner] or {}) do dropAlert(al) end
    Alerts.byOwner[owner] = nil
end

function Alerts.List(owner)
    local out = {}
    for _, al in pairs(Alerts.byOwner[owner] or {}) do
        out[#out + 1] = { id = al.id, sym = al.sym, cond = al.cond, price = al.price }
    end
    table.sort(out, function(x, y) return x.id < y.id end)
    return out
end

function Alerts.Add(owner, sym, cond, price)
    local n = 0
    for _ in pairs(Alerts.byOwner[owner] or {}) do n = n + 1 end
    if n >= Config.MaxAlerts then return nil, 'Alert limit reached' end
    local id = DB.InsertAlert(owner, sym, cond, price)
    if not id then return nil, 'Could not save alert' end
    addAlert(owner, id, sym, cond, price)
    return id
end

function Alerts.Remove(owner, id)
    local al = Alerts.byOwner[owner] and Alerts.byOwner[owner][id]
    if not al then return false end
    dropAlert(al)
    DB.DeleteAlert(id)
    return true
end

function Alerts.Check()
    for sym, set in pairs(Alerts.bySym) do
        local s = Market.by[sym]
        if s and next(set) then
            for id, al in pairs(set) do
                if (al.cond == 'above' and s.price >= al.price) or (al.cond == 'below' and s.price <= al.price) then
                    dropAlert(al)
                    DB.DeleteAlert(id)
                    notify(al.owner, 'nz_trading:client:alert', { id = id, sym = sym, cond = al.cond, price = al.price, last = s.price })
                end
            end
        end
    end
end
