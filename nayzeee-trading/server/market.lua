Market = {
    list = {},        -- symbols in config order
    by = {},          -- symbol -> state
    viewers = {},     -- src -> true while the app is open
    news = {},
    calendar = {},
    session = 'open',
    dayKey = nil,
}

local M = Config.Market
local H = M.hours
local DT = M.tickMs / 1000
local HORIZON = M.horizonMinutes * 60
local TREND_TAU = 240
local MARKET_VOL = { stock = 0.011, index = 0.011, crypto = 0.035 }
local DOLLAR_VOL = { stock = 150e6, index = 0, crypto = 300e6 }

local newsId, calId = 0, 0
local nextNews, nextEarnings, nextSave = 0, 0, 0

-- ── helpers ─────────────────────────────────────────────────────

local function gauss()
    local u = math.random()
    if u < 1e-12 then u = 1e-12 end
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * math.random())
end

local function clamp(v, lo, hi) return v < lo and lo or v > hi and hi or v end
local function r4(v) return math.floor(v * 10000 + 0.5) / 10000 end
local function between(range) return range[1] + math.random() * (range[2] - range[1]) end

function Market.TickSize(p) return p >= 1 and 0.01 or 0.0001 end

function Market.Round(p)
    local t = Market.TickSize(p)
    return math.floor(p / t + 0.5) * t
end

function Market.Broadcast(event, payload)
    for src in pairs(Market.viewers) do TriggerClientEvent(event, src, payload) end
end

-- ── session clock ───────────────────────────────────────────────

local function localTime(t) return os.date('!*t', t + H.utcOffset * 3600) end

local function computeSession(t)
    if not H.enabled then return 'open' end
    local d = localTime(t)
    if not H.weekends and (d.wday == 1 or d.wday == 7) then return 'closed' end
    local h = d.hour + d.min / 60
    if h >= H.open and h < H.close then return 'open' end
    if h >= H.pre and h < H.open then return 'pre' end
    if h >= H.close and h < H.post then return 'post' end
    return 'closed'
end

local function computeDayKey(t)
    return os.date('!%Y-%m-%d', t + H.utcOffset * 3600 - M.rolloverHour * 3600)
end

local function nextBoundary(t)
    if not H.enabled then return nil end
    local d = localTime(t)
    local h = d.hour + d.min / 60 + d.sec / 3600
    for _, mark in ipairs({ H.pre, H.open, H.close, H.post }) do
        if mark > h then return t + math.floor((mark - h) * 3600) end
    end
    return t + math.floor((24 - h + H.pre) * 3600)
end

function Market.SessionInfo()
    return { code = Market.session, next = nextBoundary(os.time()), enabled = H.enabled }
end

function Market.Active(s)
    return s.type == 'crypto' or Market.session ~= 'closed'
end

-- ── symbols ─────────────────────────────────────────────────────

local function newSymbol(i, c)
    local kind = c.type or 'stock'
    local s = {
        i = i, sym = c.symbol, name = c.name, type = kind, sector = c.sector or kind,
        ex = Config.Exchanges[kind], tradable = kind ~= 'index',
        base = c.price, anchor = c.price, price = c.price, prev = c.price, open = c.price,
        hi = c.price, lo = c.price, bid = c.price, ask = c.price, volume = 0,
        vol = c.vol or 0.02, beta = c.beta or 1.0, revert = kind == 'index' and 1.0 or 0.08,
        members = c.members,
        trend = 0, shockPer = 0, shockTicks = 0, heat = 1,
        bandRef = c.price, bandAt = 0, haltUntil = 0,
        c5 = {}, c1 = {},
    }
    s.vpt = (c.dollarVolume or DOLLAR_VOL[kind]) / c.price / (HORIZON / DT)
    return s
end

local function resolveMembers(idx)
    local list = {}
    for _, s in ipairs(Market.list) do
        if s.type == 'stock' then
            if idx.members == 'all' then
                list[#list + 1] = s
            else
                for _, sec in ipairs(idx.members) do
                    if s.sector == sec then list[#list + 1] = s break end
                end
            end
        end
    end
    idx.members = list
end

local function indexLevel(idx, field, k)
    local sum = 0
    for _, m in ipairs(idx.members) do
        local v = k and m[field][k][5] or m.price
        sum = sum + v / m.base
    end
    return idx.base * sum / math.max(#idx.members, 1)
end

local function setSpread(s)
    if s.type == 'index' then s.bid, s.ask = s.price, s.price return end
    local tick = Market.TickSize(s.price)
    local extended = s.type ~= 'crypto' and (Market.session == 'pre' or Market.session == 'post')
    local bps = s.type == 'crypto' and 0.0006 or 0.0004
    local spread = math.max(tick * 2, s.price * bps * s.heat * (extended and 2.5 or 1))
    s.bid = Market.Round(s.price - spread / 2)
    s.ask = Market.Round(s.price + spread / 2)
    if s.ask <= s.bid then s.ask = s.bid + tick end
end

-- ── history seeding (so charts are full on first open) ──────────

local function seed(now, zM, zC, steps)
    local last5 = now - now % 5
    for _, s in ipairs(Market.list) do
        if not s.members then
            local dt = 5
            local sig = s.vol * math.sqrt(dt / HORIZON)
            local mv = MARKET_VOL[s.type] * math.sqrt(dt / HORIZON)
            local z = s.type == 'crypto' and zC or zM
            local path, lp, trend = { 0 }, 0, 0
            for k = 1, steps do
                trend = trend - trend * dt / TREND_TAU + s.vol * 2.5 * math.sqrt(2 * dt / TREND_TAU) * gauss()
                lp = lp + s.beta * mv * z[k] + sig * gauss() + trend * dt / HORIZON - s.revert * lp * dt / HORIZON
                path[k + 1] = lp
            end
            local scale = s.price / math.exp(lp)
            local c5 = {}
            for k = 1, steps do
                local o = Market.Round(math.exp(path[k]) * scale)
                local c = Market.Round(math.exp(path[k + 1]) * scale)
                local wick = math.abs(gauss()) * sig * 0.35
                local v = s.vpt * dt * (0.4 + math.random() * 0.6 + math.abs(path[k + 1] - path[k]) / sig * 0.3)
                v = s.type == 'crypto' and r4(v) or math.floor(v)
                c5[k] = { last5 - (steps - k) * 5, o, Market.Round(math.max(o, c) * (1 + wick)), Market.Round(math.min(o, c) * (1 - wick)), c, v }
            end
            s.c5 = c5
        end
    end

    for _, s in ipairs(Market.list) do
        if s.members then
            local c5 = {}
            for k = 1, steps do
                local c = r4(indexLevel(s, 'c5', k))
                local o = k > 1 and c5[k - 1][5] or c
                c5[k] = { last5 - (steps - k) * 5, o, math.max(o, c), math.min(o, c), c, 0 }
            end
            s.c5 = c5
        end
    end

    for _, s in ipairs(Market.list) do
        local c1, cur = {}, nil
        for _, c in ipairs(s.c5) do
            local b = c[1] - c[1] % 60
            if not cur or cur[1] ~= b then
                cur = { b, c[2], c[3], c[4], c[5], c[6] }
                c1[#c1 + 1] = cur
            else
                if c[3] > cur[3] then cur[3] = c[3] end
                if c[4] < cur[4] then cur[4] = c[4] end
                cur[5], cur[6] = c[5], cur[6] + c[6]
            end
        end
        while #c1 > M.keep1m do table.remove(c1, 1) end
        local c5 = s.c5
        if #c5 > M.keep5s then
            local trimmed = {}
            for k = #c5 - M.keep5s + 1, #c5 do trimmed[#trimmed + 1] = c5[k] end
            s.c5 = trimmed
        end
        s.c1 = c1
    end
end

function Market.Init()
    for i, c in ipairs(Config.Symbols) do
        local s = newSymbol(i, c)
        Market.list[i] = s
        Market.by[s.sym] = s
    end
    for _, s in ipairs(Market.list) do
        if s.members then resolveMembers(s) end
    end

    local now = os.time()
    Market.session = computeSession(now)
    Market.dayKey = computeDayKey(now)

    local saved = {}
    for _, row in ipairs(DB.GetMarket()) do saved[row.symbol] = row end
    for _, s in ipairs(Market.list) do
        local row = saved[s.sym]
        if row and not s.members then
            s.price = Market.Round(tonumber(row.price))
            s.anchor = tonumber(row.anchor)
        end
    end

    local steps = M.keep1m * 12
    local zM, zC = {}, {}
    for k = 1, steps do zM[k], zC[k] = gauss(), gauss() end
    seed(now, zM, zC, steps)

    for _, s in ipairs(Market.list) do
        if s.members then s.price = r4(indexLevel(s)) end
        local row = saved[s.sym]
        local first = s.c1[1]
        if row and row.day_key == Market.dayKey then
            s.prev = tonumber(row.prev_close)
        else
            s.prev = first and first[2] or s.price
        end
        s.open = s.prev
        s.hi, s.lo, s.volume = s.price, s.price, 0
        for _, c in ipairs(s.c1) do
            if c[3] > s.hi then s.hi = c[3] end
            if c[4] < s.lo then s.lo = c[4] end
            s.volume = s.volume + c[6]
        end
        s.bandRef, s.bandAt = s.price, now
        setSpread(s)
    end

    nextNews = now + between(Config.News.interval)
    nextEarnings = now + 30
    nextSave = now + M.saveInterval
    print(('[nayzeee-trading] market ready: %d symbols, session %s'):format(#Market.list, Market.session))
end

-- ── simulation ──────────────────────────────────────────────────

local function step(s, zM, zC)
    local sig = s.vol * math.sqrt(DT / HORIZON) * s.heat
    local mv = MARKET_VOL[s.type] * math.sqrt(DT / HORIZON)
    s.trend = s.trend - s.trend * DT / TREND_TAU + s.vol * 2.5 * math.sqrt(2 * DT / TREND_TAU) * gauss()

    local ret = s.beta * mv * (s.type == 'crypto' and zC or zM)
        + sig * gauss()
        + s.trend * DT / HORIZON
        - s.revert * math.log(s.price / s.anchor) * DT / HORIZON

    if s.shockTicks > 0 then
        ret = ret + s.shockPer
        s.shockTicks = s.shockTicks - 1
    end

    s.price = math.max(Market.TickSize(s.price), Market.Round(s.price * math.exp(ret)))
    s.heat = 1 + (s.heat - 1) * math.exp(-DT / 120)

    local z = math.abs(ret) / math.max(sig, 1e-9)
    local extended = s.type ~= 'crypto' and Market.session ~= 'open'
    local v = s.vpt * (0.35 + 0.45 * math.random() + 0.35 * math.min(z, 4)) * s.heat * (extended and 0.25 or 1)
    return s.type == 'crypto' and r4(v) or math.floor(v + 0.5)
end

local function candle(arr, bucket, p, v, keep)
    local c = arr[#arr]
    if not c or c[1] ~= bucket then
        c = { bucket, p, p, p, p, 0 }
        arr[#arr + 1] = c
        if #arr > keep then table.remove(arr, 1) end
    end
    if p > c[3] then c[3] = p end
    if p < c[4] then c[4] = p end
    c[5], c[6] = p, c[6] + v
end

local function halt(s, now, on)
    if on then
        s.haltUntil = now + M.halts.duration
        Market.PushNews({ kind = 'halt', symbol = s.sym, text = ('%s halted: volatility trading pause'):format(s.name), impact = 0 })
    else
        s.haltUntil, s.bandRef, s.bandAt = 0, s.price, now
    end
    Market.Broadcast('nz_trading:client:halt', { sym = s.sym, ['until'] = s.haltUntil })
end

function Market.ApplyShock(s, impact)
    local gap = impact * 0.4
    s.price = math.max(Market.TickSize(s.price), Market.Round(s.price * (1 + gap)))
    local n = math.random(25, 80)
    s.shockPer, s.shockTicks = (impact - gap) / n, n
    s.heat = math.min(4, s.heat + math.abs(impact) * 25)
    s.anchor = clamp(s.anchor * (1 + impact * 0.5), s.base * 0.5, s.base * 2)
end

function Market.Rollover(key)
    Market.dayKey = key
    local prevs = {}
    for i, s in ipairs(Market.list) do
        s.prev, s.open, s.hi, s.lo, s.volume = s.price, s.price, s.price, s.price, 0
        prevs[i] = r4(s.prev)
    end
    Broker.OnRollover()
    Market.Broadcast('nz_trading:client:rollover', prevs)
end

function Market.Step(now)
    local session = computeSession(now)
    if session ~= Market.session then
        Market.session = session
        Market.Broadcast('nz_trading:client:session', Market.SessionInfo())
    end
    local key = computeDayKey(now)
    if key ~= Market.dayKey then Market.Rollover(key) end

    local zM, zC = gauss(), gauss()
    local b5, b1 = now - now % 5, now - now % 60

    for _, s in ipairs(Market.list) do
        if not s.members then
            local v = 0
            if s.haltUntil > 0 and now >= s.haltUntil then halt(s, now, false) end
            if s.haltUntil == 0 and Market.Active(s) then v = step(s, zM, zC) end
            s.tickVol = v
        end
    end

    for _, s in ipairs(Market.list) do
        if s.members then
            s.price = r4(indexLevel(s))
            s.tickVol = 0
        end
        local p, v = s.price, s.tickVol
        s.volume = s.volume + v
        if p > s.hi then s.hi = p end
        if p < s.lo then s.lo = p end
        setSpread(s)
        candle(s.c5, b5, p, v, M.keep5s)
        candle(s.c1, b1, p, v, M.keep1m)

        if M.halts.enabled and s.type == 'stock' and s.haltUntil == 0 then
            if now - s.bandAt >= M.halts.window then s.bandRef, s.bandAt = p, now end
            if math.abs(p / s.bandRef - 1) >= M.halts.percent then halt(s, now, true) end
        end
    end

    if now >= nextNews then
        nextNews = now + between(Config.News.interval)
        Market.RandomNews()
    end

    if Config.Earnings.enabled then
        if now >= nextEarnings then
            nextEarnings = now + between(Config.Earnings.schedule)
            Market.ScheduleEarnings(now)
        end
        local ev = Market.calendar[1]
        if ev and now >= ev.at then
            table.remove(Market.calendar, 1)
            Market.ReleaseEarnings(ev)
            Market.Broadcast('nz_trading:client:calendar', Market.calendar)
        end
    end

    if now >= nextSave then
        nextSave = now + M.saveInterval
        Market.Save()
    end
end

function Market.Save()
    local rows = {}
    for _, s in ipairs(Market.list) do
        if not s.members then rows[#rows + 1] = { s.sym, s.price, s.prev, s.anchor, Market.dayKey } end
    end
    DB.SaveMarket(rows)
end

-- ── news & earnings ─────────────────────────────────────────────

function Market.PushNews(item)
    newsId = newsId + 1
    item.id, item.time = newsId, os.time()
    table.insert(Market.news, 1, item)
    if #Market.news > 40 then Market.news[41] = nil end
    Market.Broadcast('nz_trading:client:news', item)
end

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

function Market.RandomNews()
    local list = Config.News.templates
    local tpl = list[math.random(#list)]
    local mult = 0.6 + math.random() * 0.8

    if tpl.scope then
        local crypto = tpl.scope == 'crypto'
        for _, s in ipairs(Market.list) do
            if not s.members and (s.type == 'crypto') == crypto then
                Market.ApplyShock(s, tpl.impact * mult * s.beta * (0.7 + math.random() * 0.6))
            end
        end
        Market.PushNews({ kind = 'macro', scope = tpl.scope, text = tpl.text, impact = r4(tpl.impact * mult) })
        return
    end

    local pool = {}
    for _, s in ipairs(Market.list) do
        if s.tradable and s.haltUntil == 0 and inList(tpl.sectors, s.sector) then pool[#pool + 1] = s end
    end
    if #pool == 0 then return end
    local s = pool[math.random(#pool)]
    local impact = tpl.impact * mult
    Market.ApplyShock(s, impact)
    Market.PushNews({ kind = 'company', symbol = s.sym, text = tpl.text:format(s.name), impact = r4(impact) })
end

function Market.ScheduleEarnings(now)
    local E = Config.Earnings
    if #Market.calendar >= E.maxPending then return end
    local busy = {}
    for _, ev in ipairs(Market.calendar) do busy[ev.symbol] = true end
    local pool = {}
    for _, s in ipairs(Market.list) do
        if s.type == 'stock' and not busy[s.sym] then pool[#pool + 1] = s end
    end
    if #pool == 0 then return end
    local s = pool[math.random(#pool)]
    calId = calId + 1
    Market.calendar[#Market.calendar + 1] = {
        id = calId, symbol = s.sym, name = s.name,
        at = now + math.floor(between(E.lead)),
        est = math.floor(s.price / (18 + math.random() * 22) / 4 * 100 + 0.5) / 100,
        q = math.floor((tonumber(os.date('!%m', now)) - 1) / 3) + 1,
    }
    table.sort(Market.calendar, function(a, b) return a.at < b.at end)
    Market.Broadcast('nz_trading:client:calendar', Market.calendar)
end

function Market.ReleaseEarnings(ev)
    local s = Market.by[ev.symbol]
    if not s then return end
    local E = Config.Earnings
    local beat = math.random() < E.beatChance
    local move = between(E.move) * (beat and 1 or -1)
    local eps = ev.est * (1 + (0.03 + math.random() * 0.2) * (beat and 1 or -1))
    Market.ApplyShock(s, move)
    Market.PushNews({
        kind = 'earnings', symbol = s.sym, impact = r4(move),
        text = ('%s Q%d earnings: EPS $%.2f vs $%.2f est. — %s'):format(s.name, ev.q, eps, ev.est, beat and 'beat' or 'miss'),
    })
end

-- ── client payloads ─────────────────────────────────────────────

function Market.Quotes()
    local q = {}
    for i, s in ipairs(Market.list) do
        q[i] = { r4(s.price), r4(s.bid), r4(s.ask), r4(s.volume), r4(s.hi), r4(s.lo) }
    end
    return q
end

function Market.Meta()
    local out = {}
    for i, s in ipairs(Market.list) do
        local spark, c1 = {}, s.c1
        for k = math.max(1, #c1 - 59), #c1 do spark[#spark + 1] = r4(c1[k][5]) end
        out[i] = {
            s = s.sym, n = s.name, type = s.type, sector = s.sector, ex = s.ex,
            prev = r4(s.prev), open = r4(s.open), tradable = s.tradable,
            vpt = s.vpt, halt = s.haltUntil, spark = spark,
        }
    end
    return out
end

local TIMEFRAMES = { [5] = true, [15] = true, [60] = true, [300] = true, [900] = true }

function Market.Candles(sym, tf)
    local s = Market.by[sym]
    if not s or not TIMEFRAMES[tf] then return nil end
    local src = tf < 60 and s.c5 or s.c1
    local out, cur = {}, nil
    for _, c in ipairs(src) do
        local b = c[1] - c[1] % tf
        if not cur or cur[1] ~= b then
            cur = { b, c[2], c[3], c[4], c[5], c[6] }
            out[#out + 1] = cur
        else
            if c[3] > cur[3] then cur[3] = c[3] end
            if c[4] < cur[4] then cur[4] = c[4] end
            cur[5], cur[6] = c[5], cur[6] + c[6]
        end
    end
    local from = math.max(1, #out - 399)
    local res = {}
    for k = from, #out do
        local c = out[k]
        res[#res + 1] = { c[1], r4(c[2]), r4(c[3]), r4(c[4]), r4(c[5]), r4(c[6]) }
    end
    return res
end

function Market.SendQuotes(now)
    if not next(Market.viewers) then return end
    Market.Broadcast('nz_trading:client:quotes', { t = now, q = Market.Quotes() })
end
