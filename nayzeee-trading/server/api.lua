local Ready = false
local Profiles = {}   -- owner -> profile
local Owners = {}     -- src -> owner
local LastCall = {}   -- src -> GetGameTimer()
local Leaderboard = {}

local WALLPAPERS = { teal = true, graphite = true, grid = true, aurora = true }
local DEFAULT_WATCH = { 'FRUT', 'MAZE', 'WHIZ', 'LIFE', 'SHRK', 'BKC', 'ETRM' }

local function OK(data) return { ok = true, data = data } end
local function ERR(msg) return { ok = false, err = msg } end

local function publicConfig()
    return {
        ui = Config.UI,
        leverage = Config.Trading.leverage,
        maintenance = Config.Trading.maintenance,
        allowShort = Config.Trading.allowShort,
        cryptoDecimals = Config.Trading.cryptoDecimals,
        fees = Config.Fees,
        practice = Config.Practice,
        live = { enabled = Config.Live.enabled, minDeposit = Config.Live.minDeposit, maxDeposit = Config.Live.maxDeposit },
        maxAlerts = Config.MaxAlerts,
        hours = Config.Market.hours,
    }
end

local function account(owner, kind)
    local set = Broker.owners[owner]
    if not set then return nil end
    if kind == 'live' then
        return Config.Live.enabled and set.live or nil
    end
    return set.practice
end

local function forget(src)
    local owner = Owners[src]
    if not owner then return end
    Owners[src] = nil
    if Broker.online[owner] == src then Broker.online[owner] = nil end
    Broker.Unload(owner)
    Alerts.Unload(owner)
    Profiles[owner] = nil
end

-- ── handlers ────────────────────────────────────────────────────

local H = {}

function H.boot(src, owner)
    if Owners[src] and Owners[src] ~= owner then forget(src) end

    local profile = Profiles[owner] or DB.GetProfile(owner)
    Profiles[owner] = profile

    local data = {
        player = { name = Bridge.GetName(src) },
        cfg = publicConfig(),
        market = Market.Meta(),
        quotes = Market.Quotes(),
        session = Market.SessionInfo(),
        news = Market.news,
        calendar = Market.calendar,
        t = os.time(),
        profile = profile,
    }

    if profile then
        Owners[src] = owner
        Broker.online[owner] = src
        local set = Broker.LoadOwner(owner)
        if not set or not set.practice then
            Broker.CreateAccounts(owner)
            set = Broker.LoadOwner(owner)
        end
        data.accounts = {
            practice = Broker.Snapshot(set.practice),
            live = Config.Live.enabled and Broker.Snapshot(set.live) or nil,
        }
        Alerts.Load(owner)
        data.alerts = Alerts.List(owner)
    end
    return OK(data)
end

function H.createProfile(src, owner, d)
    if Profiles[owner] or DB.GetProfile(owner) then return ERR('You already have an account') end
    local name = type(d.name) == 'string' and d.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #name < 3 or #name > 24 or not name:match("^[%w%s%._%-']+$") then
        return ERR('Display name must be 3–24 letters or numbers')
    end
    local watch = {}
    for _, sym in ipairs(DEFAULT_WATCH) do
        if Market.by[sym] then watch[#watch + 1] = sym end
    end
    DB.CreateProfile(owner, name, watch)
    Broker.CreateAccounts(owner)
    return H.boot(src, owner)
end

function H.candles(_, _, d)
    local c = Market.Candles(d.symbol, tonumber(d.tf))
    if not c then return ERR('No data') end
    return OK(c)
end

function H.order(_, owner, d)
    local a = account(owner, d.account)
    if not a then return ERR('Account unavailable') end
    local o, err = Broker.Place(a, d)
    Broker.Flush()
    if not o then return ERR(err) end
    return OK({ id = o.id, status = o.status, price = o.fillPrice })
end

function H.cancel(_, owner, d)
    local a = account(owner, d.account)
    local o = a and a.orders[tonumber(d.id)]
    if not o then return ERR('Order not found') end
    Broker.Cancel(a, o, 'cancelled', 'Cancelled')
    Broker.Flush()
    return OK(true)
end

function H.cancelAll(_, owner, d)
    local a = account(owner, d.account)
    if not a then return ERR('Account unavailable') end
    local n = 0
    for _, o in pairs(a.orders) do
        if not d.symbol or o.sym == d.symbol then
            Broker.Cancel(a, o, 'cancelled', 'Cancelled')
            n = n + 1
        end
    end
    Broker.Flush()
    return OK(n)
end

function H.flatten(_, owner, d)
    local a = account(owner, d.account)
    if not a then return ERR('Account unavailable') end
    local n, err = Broker.Flatten(a, d.symbol)
    Broker.Flush()
    if n == 0 and err then return ERR(err) end
    return OK(n)
end

function H.history(_, owner, d)
    local a = account(owner, d.account)
    if not a then return ERR('Account unavailable') end
    local orders, fills, ledger = DB.History(a.id)
    local o, f, l = {}, {}, {}
    for i, r in ipairs(orders) do
        o[i] = { id = r.id, sym = r.symbol, side = r.side, type = r.type, qty = tonumber(r.qty), limit = tonumber(r.limit_price),
            stop = tonumber(r.stop_price), status = r.status, price = tonumber(r.fill_price), reason = r.reason, time = r.updated }
    end
    for i, r in ipairs(fills) do
        f[i] = { id = r.id, order = r.order_id, sym = r.symbol, side = r.side, qty = tonumber(r.qty), price = tonumber(r.price),
            fee = tonumber(r.fee), realized = tonumber(r.realized), time = r.time }
    end
    for i, r in ipairs(ledger) do
        l[i] = { type = r.type, amount = tonumber(r.amount), time = r.time }
    end
    return OK({ orders = o, fills = f, ledger = l })
end

function H.bank(src)
    if not Config.Live.enabled then return ERR('Live trading is disabled') end
    return OK(Bridge.GetMoney(src, Config.Live.moneyAccount))
end

function H.deposit(src, owner, d)
    local a = account(owner, 'live')
    if not a then return ERR('Live trading is disabled') end
    local amount = math.floor(tonumber(d.amount) or 0)
    if amount < Config.Live.minDeposit then return ERR(('Minimum deposit is $%s'):format(Config.Live.minDeposit)) end
    if amount > Config.Live.maxDeposit then return ERR('Deposit exceeds the maximum') end
    if not Bridge.RemoveMoney(src, Config.Live.moneyAccount, amount, 'Brokerage deposit') then
        return ERR('Insufficient bank funds')
    end
    a.cash, a.dayStart = a.cash + amount, a.dayStart + amount
    DB.SaveAccount(a)
    DB.InsertLedger(a.id, 'deposit', amount)
    Broker.MarkDirty(a)
    Broker.Flush()
    return OK(Bridge.GetMoney(src, Config.Live.moneyAccount))
end

function H.withdraw(src, owner, d)
    local a = account(owner, 'live')
    if not a then return ERR('Live trading is disabled') end
    local amount = math.floor(tonumber(d.amount) or 0)
    if amount <= 0 then return ERR('Enter an amount') end
    if amount > math.floor(Broker.Withdrawable(a)) then return ERR('Amount exceeds withdrawable cash') end
    a.cash, a.dayStart = a.cash - amount, a.dayStart - amount
    DB.SaveAccount(a)
    if not Bridge.AddMoney(src, Config.Live.moneyAccount, amount, 'Brokerage withdrawal') then
        a.cash, a.dayStart = a.cash + amount, a.dayStart + amount
        DB.SaveAccount(a)
        return ERR('Transfer failed')
    end
    DB.InsertLedger(a.id, 'withdraw', amount)
    Broker.MarkDirty(a)
    Broker.Flush()
    return OK(Bridge.GetMoney(src, Config.Live.moneyAccount))
end

function H.reset(_, owner)
    local a = account(owner, 'practice')
    if not a then return ERR('Account unavailable') end
    local wait = a.resetAt + Config.Practice.resetCooldown * 60 - os.time()
    if wait > 0 then return ERR(('Reset available in %d min'):format(math.ceil(wait / 60))) end
    Broker.Reset(a)
    Broker.Flush()
    return OK(true)
end

function H.alertAdd(_, owner, d)
    local s = Market.by[d.symbol]
    local price = tonumber(d.price)
    if not s or not price or price <= 0 or (d.cond ~= 'above' and d.cond ~= 'below') then return ERR('Invalid alert') end
    local id, err = Alerts.Add(owner, s.sym, d.cond, price)
    if not id then return ERR(err) end
    return OK(Alerts.List(owner))
end

function H.alertDel(_, owner, d)
    Alerts.Remove(owner, tonumber(d.id))
    return OK(Alerts.List(owner))
end

function H.settings(_, owner, d)
    local p = Profiles[owner]
    if not p then return ERR('No profile') end
    local s = type(d.settings) == 'table' and d.settings or {}
    local clean = {
        volume = math.max(0, math.min(1, tonumber(s.volume) or 0.6)),
        sounds = s.sounds ~= false,
        keySounds = s.keySounds ~= false,
        confirm = s.confirm == true,
        hotkeys = s.hotkeys ~= false,
        compact = s.compact == true,
        wallpaper = WALLPAPERS[s.wallpaper] and s.wallpaper or 'teal',
    }
    p.settings = clean
    DB.SaveProfileField(owner, 'settings', clean)
    return OK(clean)
end

function H.watchlist(_, owner, d)
    local p = Profiles[owner]
    if not p or type(d.list) ~= 'table' then return ERR('Invalid') end
    local list, seen = {}, {}
    for _, sym in ipairs(d.list) do
        if Market.by[sym] and not seen[sym] and #list < 30 then
            seen[sym] = true
            list[#list + 1] = sym
        end
    end
    p.watchlist = list
    DB.SaveProfileField(owner, 'watchlist', list)
    return OK(list)
end

function H.active(_, owner, d)
    local p = Profiles[owner]
    if not p then return ERR('No profile') end
    p.active = (d.account == 'live' and Config.Live.enabled) and 'live' or 'practice'
    DB.SaveProfileField(owner, 'active', p.active)
    return OK(p.active)
end

function H.leaderboard(_, _, d)
    local kind = d.type == 'live' and 'live' or 'practice'
    local cached = Leaderboard[kind]
    if cached and os.time() - cached.at < 60 then return OK(cached.rows) end
    local rows = {}
    for i, r in ipairs(DB.Leaderboard(kind)) do
        rows[i] = { name = r.name, net = tonumber(r.realized) - tonumber(r.fees), trades = r.trades }
    end
    table.sort(rows, function(a, b) return a.net > b.net end)
    Leaderboard[kind] = { at = os.time(), rows = rows }
    return OK(rows)
end

local NEEDS_PROFILE = {
    order = true, cancel = true, cancelAll = true, flatten = true, history = true, deposit = true, withdraw = true,
    reset = true, alertAdd = true, alertDel = true, settings = true, watchlist = true, active = true,
}

lib.callback.register('nz_trading:api', function(src, action, data)
    if not Ready then return ERR('Market is starting up') end
    local handler = H[action]
    if not handler then return ERR('Unknown action') end

    if action ~= 'candles' then
        local now = GetGameTimer()
        local calls = LastCall[src] or {}
        LastCall[src] = calls
        if now - (calls[action] or 0) < 75 then return ERR('Slow down') end
        calls[action] = now
    end

    local owner = Bridge.GetIdentifier(src)
    if not owner then return ERR('Character not loaded') end
    if NEEDS_PROFILE[action] and Owners[src] ~= owner then return ERR('Session expired, reopen the app') end

    local ok, res = pcall(handler, src, owner, type(data) == 'table' and data or {})
    if not ok then
        print(('[nayzeee-trading] %s failed: %s'):format(action, res))
        return ERR('Server error')
    end
    return res
end)

RegisterNetEvent('nz_trading:server:view', function(state)
    Market.viewers[source] = state == true or nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    Market.viewers[src] = nil
    LastCall[src] = nil
    Props.Release(src)
    forget(src)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Ready then Market.Save() end
end)

-- ── main loop ───────────────────────────────────────────────────

MySQL.ready(function()
    CreateThread(function()
        DB.Init()
        Market.Init()
        Broker.Init()
        Props.Init()
        Ready = true

        local wait = Config.Market.tickMs
        while true do
            local now = os.time()
            Market.Step(now)
            Broker.Tick(now)
            Market.SendQuotes(now)
            Wait(wait)
        end
    end)
end)
