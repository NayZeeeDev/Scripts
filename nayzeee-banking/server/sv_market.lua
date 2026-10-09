if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  INVESTMENTS
--  Prices tick here unless nayzeee-trading is running, in which
--  case that resource becomes the price source automatically.
-- ═══════════════════════════════════════════════════════════

Bank.market = {}   -- [assetId] = { price, open, history = {} }

local HISTORY_POINTS = 24   -- points kept for the sparkline

local function assetConfig(id)
    for _, a in ipairs(Config.Market.assets) do
        if a.id == id then return a end
    end
end

--- nayzeee-trading takes over as the price feed whenever it is running.
local function usingTrading()
    return GetResourceState('nayzeee-trading') == 'started'
end

--- Pull a price from nayzeee-trading when it is available.
local function externalPrice(id)
    local ok, price = pcall(function()
        return exports['nayzeee-trading']:getPrice(id)
    end)
    if ok and tonumber(price) then return tonumber(price) end
    return nil
end

local function persist(id)
    local m = Bank.market[id]
    MySQL.query([[
        INSERT INTO nz_bank_market (asset, price, open_price, history, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE price = VALUES(price), open_price = VALUES(open_price),
          history = VALUES(history), updated_at = VALUES(updated_at)
    ]], { id, m.price, m.open, json.encode(m.history), os.time() })
end

local function loadMarket()
    local saved = MySQL.query.await('SELECT * FROM nz_bank_market') or {}
    local byId = {}
    for _, r in ipairs(saved) do byId[r.asset] = r end

    for _, a in ipairs(Config.Market.assets) do
        local r = byId[a.id]
        local price = r and tonumber(r.price) or a.start
        local history = {}
        if r and r.history then
            local ok, decoded = pcall(json.decode, r.history)
            if ok and type(decoded) == 'table' then history = decoded end
        end
        if #history == 0 then history = { price } end

        Bank.market[a.id] = {
            price   = price,
            open    = r and tonumber(r.open_price) or price,
            history = history
        }
    end
end

local function tick()
    for _, a in ipairs(Config.Market.assets) do
        local m = Bank.market[a.id]
        if m then
            local next

            if usingTrading() then
                next = externalPrice(a.id)
            end

            if not next then
                -- random walk with a gentle pull back toward the starting value
                local drift = (a.start - m.price) / a.start * 0.08
                local shock = (math.random() - 0.5) * 2 * a.volatility
                next = m.price * (1 + drift + shock)
            end

            next = math.max(a.floor, math.min(a.ceiling, next))
            m.price = math.floor(next * 100) / 100

            m.history[#m.history + 1] = m.price
            while #m.history > HISTORY_POINTS do table.remove(m.history, 1) end

            persist(a.id)
        end
    end
end

CreateThread(function()
    if not Config.Market.enabled then return end
    Wait(3000)
    loadMarket()

    -- reset the day's opening price on the hour
    local lastOpen = os.date('%H')

    while true do
        Wait(Config.Market.tickMinutes * 60000)
        tick()

        local hour = os.date('%H')
        if hour ~= lastOpen then
            lastOpen = hour
            for id, m in pairs(Bank.market) do
                m.open = m.price
                persist(id)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════
function Bank.getMarketState(identifier)
    local assets = {}
    for _, a in ipairs(Config.Market.assets) do
        local m = Bank.market[a.id]
        if m then
            local change = m.open > 0 and ((m.price - m.open) / m.open) * 100 or 0
            assets[#assets + 1] = {
                id      = a.id,
                label   = a.label,
                price   = m.price,
                change  = math.floor(change * 100) / 100,
                history = m.history
            }
        end
    end

    local rows = MySQL.query.await('SELECT * FROM nz_bank_holdings WHERE identifier = ? AND units > 0',
        { identifier }) or {}

    local holdings, value, cost, realised = {}, 0, 0, 0
    for _, h in ipairs(rows) do
        local m = Bank.market[h.asset]
        local price = m and m.price or 0
        local units = tonumber(h.units)
        local worth = units * price
        local basis = units * tonumber(h.avg_price)

        value = value + worth
        cost = cost + basis
        realised = realised + h.realised

        local cfg = assetConfig(h.asset)
        holdings[#holdings + 1] = {
            asset    = h.asset,
            label    = cfg and cfg.label or h.asset,
            units    = math.floor(units * 1000000) / 1000000,
            avgPrice = tonumber(h.avg_price),
            price    = price,
            value    = math.floor(worth),
            pl       = math.floor(worth - basis)
        }
    end

    return {
        assets   = assets,
        holdings = holdings,
        value    = math.floor(value),
        cost     = math.floor(cost),
        pl       = math.floor(value - cost),
        realised = realised,
        fee      = Config.Market.tradeFee,
        minTrade = Config.Market.minTrade,
        tick     = Config.Market.tickMinutes
    }
end

-- ═══════════════════════════════════════════════════════════
--  TRADING
-- ═══════════════════════════════════════════════════════════
local trade

-- one order at a time per player, so two sells can't both cash out the same units
Bank.callback('nz_bank:trade', function(src, ...)
    local res, busy = Bank.serial('trade:' .. src, trade, src, ...)
    if res == false then return { ok = false, msg = busy } end
    return res
end)

function trade(src, side, assetId, spend, accountId)
    if not Config.Market.enabled then return { ok = false, msg = 'Trading is closed.' } end
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end

    local cfg = assetConfig(assetId)
    local m = Bank.market[assetId]
    if not cfg or not m then return { ok = false, msg = 'Unknown asset.' } end

    local acc, perms = Bank.access(src, accountId)
    if not acc then return { ok = false, msg = 'You cannot use that account.' } end
    if acc.type == 'society' then return { ok = false, msg = 'Society funds cannot be traded.' } end

    local holding = MySQL.single.await(
        'SELECT * FROM nz_bank_holdings WHERE identifier = ? AND asset = ?', { xPlayer.identifier, assetId })

    -- ── BUY ──────────────────────────────────────────────────
    if side == 'buy' then
        if not perms.withdraw then return { ok = false, msg = 'You cannot spend from that account.' } end

        spend = Bank.round(spend)
        if spend < Config.Market.minTrade then
            return { ok = false, msg = ('The smallest order is %s%s.'):format(Config.Currency, Config.Market.minTrade) }
        end

        local fee = Bank.round(spend * Config.Market.tradeFee)
        local units = spend / m.price

        local heldValue = holding and (tonumber(holding.units) * m.price) or 0
        if (heldValue + spend) > Config.Market.maxHolding then
            return { ok = false, msg = ('Your position in %s is capped at %s%s.'):format(
                cfg.label, Config.Currency, Config.Market.maxHolding) }
        end

        local ok = Bank.debit(accountId, spend + fee, {
            category = 'transfer',
            label    = ('Bought %s'):format(cfg.label),
            actor    = xPlayer.identifier,
            actorName= Bank.fullName(xPlayer)
        })
        if not ok then return { ok = false, msg = 'Not enough in that account.' } end

        if holding then
            local oldUnits = tonumber(holding.units)
            local newUnits = oldUnits + units
            local avg = ((oldUnits * tonumber(holding.avg_price)) + spend) / newUnits
            MySQL.update.await('UPDATE nz_bank_holdings SET units = ?, avg_price = ? WHERE id = ?',
                { newUnits, avg, holding.id })
        else
            MySQL.insert.await(
                'INSERT INTO nz_bank_holdings (identifier, asset, units, avg_price) VALUES (?, ?, ?, ?)',
                { xPlayer.identifier, assetId, units, m.price })
        end

        return { ok = true, msg = ('Bought %.4f %s at %s%s.'):format(units, assetId, Config.Currency, m.price) }
    end

    -- ── SELL ─────────────────────────────────────────────────
    if side == 'sell' then
        if not holding or tonumber(holding.units) <= 0 then
            return { ok = false, msg = ('You hold no %s.'):format(cfg.label) }
        end

        local held = tonumber(holding.units)
        local maxValue = held * m.price
        local target = Bank.round(spend)
        if target <= 0 or target > maxValue then target = Bank.round(maxValue) end

        local units = math.min(held, target / m.price)
        local gross = units * m.price
        local fee = Bank.round(gross * Config.Market.tradeFee)
        local net = Bank.round(gross - fee)
        local basis = units * tonumber(holding.avg_price)
        local pl = Bank.round(gross - basis)

        local remaining = held - units
        if remaining <= 0.000001 then
            MySQL.update.await('UPDATE nz_bank_holdings SET units = 0, realised = realised + ? WHERE id = ?',
                { pl, holding.id })
        else
            MySQL.update.await('UPDATE nz_bank_holdings SET units = ?, realised = realised + ? WHERE id = ?',
                { remaining, pl, holding.id })
        end

        Bank.credit(accountId, net, {
            category = 'transfer',
            label    = ('Sold %s'):format(cfg.label),
            actor    = xPlayer.identifier,
            actorName= Bank.fullName(xPlayer)
        })

        return { ok = true, msg = ('Sold for %s%s · %s%s%s'):format(
            Config.Currency, net, pl >= 0 and '+' or '-', Config.Currency, math.abs(pl)) }
    end

    return { ok = false, msg = 'Unknown order type.' }
end

-- ═══════════════════════════════════════════════════════════
--  EXPORTS — let another market resource drive or read prices
-- ═══════════════════════════════════════════════════════════
exports('getMarketPrice', function(assetId)
    local m = Bank.market[assetId]
    return m and m.price or nil
end)

exports('setMarketPrice', function(assetId, price)
    local m = Bank.market[assetId]
    local cfg = assetConfig(assetId)
    if not m or not cfg or not tonumber(price) then return false end

    m.price = math.max(cfg.floor, math.min(cfg.ceiling, tonumber(price)))
    m.history[#m.history + 1] = m.price
    while #m.history > HISTORY_POINTS do table.remove(m.history, 1) end
    persist(assetId)
    return true
end)

exports('getHoldings', function(identifier)
    return Bank.getMarketState(identifier).holdings
end)
