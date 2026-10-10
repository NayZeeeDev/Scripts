--[[
    Dealers sell for you. Hire one, hand them bagged product, assign customers, and come
    back for the cash. They keep a cut. Assigned customers stop texting you directly.

    P.dealers[id] = { hired, stock = { { pid, q, n } }, cash, sold, next }
]]

Dealers = {}

local DC = Config.Dealers

local function dealerState(P, id)
    local d = P.dealers[id]
    if not d then
        d = { hired = false, stock = {}, cash = 0, sold = 0 }
        P.dealers[id] = d
    end
    return d
end

local function assigned(P, id)
    local list = {}
    for cid, c in pairs(P.customers) do
        if c.dealer == id and c.u then list[#list + 1] = cid end
    end
    table.sort(list)
    return list
end

local function stockUnits(d)
    local n = 0
    for _, s in ipairs(d.stock) do n = n + s.n end
    return n
end

Guard.callback('nzde:dealer:hire', function(src, id, account)
    local P = Profile.get(src)
    local cfg = Config.DealerList[id]
    if not P or not cfg then return false end
    local d = dealerState(P, id)
    if d.hired then return false, 'Already working for you' end
    if Profile.level(P) < cfg.unlock then return false, 'Unlocks at ' .. Utils.rankLabel(cfg.unlock) end
    account = Utils.contains(Config.Money.shopAccounts, account) and account or Config.Money.shopAccounts[1]
    if not FW.removeMoney(src, account, cfg.fee, 'drugempire-dealer') then return false, 'Not enough money' end
    d.hired = true
    d.next = os.time() + DC.tickMinutes * 60
    Profile.dirty(src)
    Messages.push(src, id, { f = 'them', m = "I'm in. Bring me product and tell me who to sell to. Find me on the map." })
    Quests.progress(src, 'dealer:hire')
    Profile.sync(src)
    return true
end)

Guard.callback('nzde:dealer:fire', function(src, id)
    local P = Profile.get(src)
    local d = P and P.dealers[id]
    if not d or not d.hired then return false end
    if d.cash > 0 then return false, 'Collect their cash first' end
    for _, cid in ipairs(assigned(P, id)) do P.customers[cid].dealer = nil end
    P.dealers[id] = nil
    Profile.dirty(src)
    Profile.sync(src)
    return true
end)

Guard.callback('nzde:dealer:assign', function(src, id, cid, on)
    local P = Profile.get(src)
    local d = P and P.dealers[id]
    local c = P and P.customers[cid]
    if not d or not d.hired or not c or not c.u then return false end
    if on then
        if c.dealer == id then return true end
        if #assigned(P, id) >= DC.maxCustomers then return false, 'This dealer has enough customers' end
        -- drop any open deals with that customer
        for i = #P.deals, 1, -1 do
            if P.deals[i].cid == cid then table.remove(P.deals, i) end
        end
        c.dealer = id
        Quests.progress(src, 'dealer:assign')
    elseif c.dealer == id then
        c.dealer = nil
    end
    Profile.dirty(src)
    Profile.sync(src)
    return true
end)

local function nearDealer(src, id)
    local cfg = Config.DealerList[id]
    return cfg and Guard.near(src, cfg.coords, 5.0)
end

Guard.callback('nzde:dealer:give', function(src, id, pid, q, units)
    local P = Profile.get(src)
    local d = P and P.dealers[id]
    if not d or not d.hired or not nearDealer(src, id) then return false end
    units = math.floor(tonumber(units) or 0)
    q = math.floor(tonumber(q) or 0)
    if units < 1 or units > 200 or not Products.get(pid) then return false end
    local got = Products.takePackaged(src, pid, units, q)
    if not got then return false, 'You don\'t have that much bagged' end
    local merged = false
    for _, s in ipairs(d.stock) do
        if s.pid == pid and s.q == got then s.n = s.n + units merged = true break end
    end
    if not merged then d.stock[#d.stock + 1] = { pid = pid, q = got, n = units } end
    Profile.dirty(src)
    return true, Dealers.one(P, id)
end)

Guard.callback('nzde:dealer:collect', function(src, id)
    local P = Profile.get(src)
    local d = P and P.dealers[id]
    if not d or not d.hired or not nearDealer(src, id) then return false end
    local cash = math.floor(d.cash)
    if cash <= 0 then return false, 'Nothing to collect' end
    d.cash = 0
    Inv.payMoney(src, cash, nil, 'drugempire-dealer')
    P.stats.earned = P.stats.earned + cash
    Profile.dirty(src)
    return true, cash
end)

--- one sale run per due dealer
function Dealers.tick(src)
    local P = Profile.get(src)
    if not P then return end
    local now = os.time()
    for id, d in pairs(P.dealers) do
        if d.hired and now >= (d.next or 0) then
            d.next = now + DC.tickMinutes * 60
            local cfg = Config.DealerList[id]
            local list = assigned(P, id)
            if #list > 0 and #d.stock > 0 then
                local cid = Utils.pick(list)
                local ccfg = Config.Customers[cid]
                -- a stock line the customer actually buys
                local line
                for _, s in ipairs(d.stock) do
                    local p = Products.get(s.pid)
                    if p and Utils.contains(ccfg.buys, Mix.kind(p.base)) then line = s break end
                end
                if line then
                    local units = math.min(line.n, Utils.range(DC.unitsPerRun))
                    local p = Products.get(line.pid)
                    local price = Mix.value(p.base, p.effects) * units * Utils.standards(ccfg.standards).spend
                    line.n = line.n - units
                    if line.n <= 0 then
                        for i, s in ipairs(d.stock) do if s == line then table.remove(d.stock, i) break end end
                    end
                    d.cash = d.cash + price * (1.0 - cfg.cut)
                    d.sold = (d.sold or 0) + units
                    local c = Customers.state(P, cid)
                    c.add = math.min(1.0, (c.add or 0) + Mix.addictiveness(p.base, p.effects) * 0.05)
                    c.rel = math.min(5.0, c.rel + 0.05)
                    P.stats.sold = P.stats.sold + units
                    Profile.dirty(src)
                    if stockUnits(d) == 0 then
                        Messages.push(src, id, { f = 'them', m = ("I'm out. Got %s for you, come grab it."):format(Utils.money(d.cash)) })
                    end
                end
            end
        end
    end
end

function Dealers.one(P, id)
    local cfg = Config.DealerList[id]
    local d = P.dealers[id] or { hired = false, stock = {}, cash = 0, sold = 0 }
    local stock = {}
    for _, s in ipairs(d.stock) do
        stock[#stock + 1] = { pid = s.pid, q = s.q, n = s.n, name = Products.label(s.pid) }
    end
    return {
        id = id, name = cfg.name, region = cfg.region, fee = cfg.fee, cut = cfg.cut, unlock = cfg.unlock,
        coords = { x = cfg.coords.x, y = cfg.coords.y }, hired = d.hired, cash = math.floor(d.cash), sold = d.sold or 0,
        stock = stock, units = stockUnits(d), customers = assigned(P, id), max = DC.maxCustomers,
    }
end

function Dealers.view(P)
    local out = {}
    for id in pairs(Config.DealerList) do out[#out + 1] = Dealers.one(P, id) end
    table.sort(out, function(a, b) return a.unlock < b.unlock end)
    return out
end
