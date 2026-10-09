-----------------------------------------------------------------
-- Warehouses: broker sales, doors (enter / knock / exit), laptop
-- data, upgrades, floor layouts, repairs, associates, leaderboard.
-----------------------------------------------------------------
Warehouse = {}

local function locationOf(w) return DB.Locations[w.location] end

function Warehouse.RepairCost(w, s)
    local r = Cargo.Upgrade('repair', w.upgrades.repair)
    local missing = (100 - (s.condition or 100)) / 100
    return math.floor(s.value * missing * Config.Repair.CostOfValue * (r and r.costMult or 1.0))
end

local function stockView(w, s)
    return {
        id = s.id, model = s.model, label = s.label, base_rarity = s.base_rarity, rarity = s.rarity,
        value = s.value, condition = s.condition, score = s.score, build = s.build, status = s.status,
        plate = s.plate, floor = s.floor, baseValue = Cargo.BaseValue(s, w.upgrades.contacts), repairCost = Warehouse.RepairCost(w, s),
        insured = s.insured, hot = s.hot, insurable = Raid.Insurable(s), premium = Raid.Premium(w, s),
        dirty = s.props and (tonumber(s.props.dirtLevel) or 0) > 1.0 or false,
    }
end

-- What each floor shows (local display cars, in slot order)
function Warehouse.Display(wid)
    local main, lower = {}, {}
    local w = DB.Warehouses[wid]
    local contacts = w and w.upgrades.contacts or 0
    for _, s in ipairs(DB.GetStock(wid)) do
        if s.status == 'stored' then
            local entry = { id = s.id, model = s.model, label = s.label, rarity = s.rarity, base_rarity = s.base_rarity, condition = s.condition, plate = s.plate, props = s.props, score = s.score, value = s.value,
                            baseValue = Cargo.BaseValue(s, contacts), hot = s.hot, insured = s.insured }
            if s.floor == 'lower' then lower[#lower + 1] = entry else main[#main + 1] = entry end
        end
    end
    return { main = main, lower = lower }
end

function Warehouse.Refresh(wid, withInterior)
    local occupants = Server.Occupants(wid)
    if #occupants == 0 then return end
    local list = Warehouse.Display(wid)
    local interior = withInterior and Server.InteriorFor(DB.Warehouses[wid]) or nil
    for _, src in ipairs(occupants) do
        if interior then TriggerClientEvent('nz_cargo:interior', src, interior) end
        TriggerClientEvent('nz_cargo:display', src, list)
    end
end

local function cooldownLeft(ts) return math.max(0, (ts or 0) - Server.Now()) end

function Warehouse.Payload(src, wid)
    local w = DB.Warehouses[wid]
    local role = Server.Access(src, wid)
    if not w or not role or role == 'guest' or role == 'police' then return nil end
    local p = Server.Profile(src)
    local level, into, need = Cargo.LevelFromXp(p.xp)
    local unlockLevel = Server.Level(p)
    local loc = locationOf(w)

    local stock, mainCount, lowerCount = {}, 0, 0
    for _, s in ipairs(DB.GetStock(wid)) do
        stock[#stock + 1] = stockView(w, s)
        if s.floor == 'lower' then lowerCount = lowerCount + 1 else mainCount = mainCount + 1 end
    end

    local intel = Cargo.Upgrade('intel', w.upgrades.intel)
    local lowerOpen = (w.upgrades.lower or 0) >= 1
    local contracts = {}
    for _, r in ipairs(Config.Rarities) do
        contracts[#contracts + 1] = {
            rarity = r.id, label = r.label, color = r.color, level = r.level, fee = r.fee,
            unlocked = unlockLevel >= r.level, pool = #Server.PoolFor(r.id), xp = r.xp, cd = Source.CooldownLeft(p, r.id),
        }
    end
    for _, c in ipairs(Config.SpecialContracts or {}) do
        contracts[#contracts + 1] = {
            rarity = c.id, label = c.label, color = c.color, icon = c.icon, desc = c.desc, level = c.level, fee = c.fee, xp = c.xp,
            unlocked = unlockLevel >= c.level, pool = #((Config.SpecialVehicles or {})[c.id] or {}), special = true, cd = Source.CooldownLeft(p, c.id),
        }
    end
    local I = Config.Illegal
    contracts[#contracts + 1] = {
        rarity = I.id, label = I.label, color = I.color, level = I.level, fee = I.fee, xp = I.xp,
        unlocked = unlockLevel >= I.level and lowerOpen, needsLower = not lowerOpen, pool = #Server.PoolFor(I.id), illegal = true,
        cd = Source.CooldownLeft(p, I.id),
    }
    local assoc = {}
    for _, a in ipairs(w.associates) do assoc[#assoc + 1] = { identifier = a.identifier, name = a.name, role = Server.Role(a.role).id } end
    local P, R = Config.Prestige, Config.Raids

    local ledger = {}
    for _, row in ipairs(DB.GetLedger(wid, 40)) do
        ledger[#ledger + 1] = { kind = row.kind, label = row.label, rarity = row.rarity ~= '' and row.rarity or nil, amount = row.amount, t = row.t, data = DB.Decode(row.data) }
    end

    local presets = {}
    for _, pr in ipairs(Server.Presets()) do presets[#presets + 1] = { id = pr.id, label = pr.label, slots = pr.slots, admin = pr.admin } end
    local trk = Cargo.Upgrade('tracker', w.upgrades.tracker)

    return {
        version = Cargo.Version,
        role = role,
        isAdmin = Bridge.IsAdmin(src),
        policeOk = Config.Sourcing.MinPolice <= 0 or Bridge.CountPolice() >= Config.Sourcing.MinPolice,
        profile = {
            name = p.name, level = level, xp = p.xp, xpInto = into, xpNeed = need, maxLevel = Config.Levels.Max,
            sourced = p.sourced, sold = p.sold, failed = p.failed, earned = p.earned, best = p.best_sale,
            streak = p.clean_streak, sourceCd = Config.Sourcing.CooldownMode == 'contract' and 0 or cooldownLeft(p.source_cd), sellCd = cooldownLeft(p.sell_cd),
            prestige = Server.PrestigeOf(p), prestigeMax = P.Enabled and P.Max or 0, prestigeCost = P.Cost,
            canPrestige = P.Enabled and level >= Config.Levels.Max and (p.prestige or 0) < P.Max or false,
            saleBonus = Server.SaleMult(src) - 1, xpBonus = Server.PrestigeOf(p) * (P.XpBonus or 0),
        },
        crewRole = Server.RoleOf(src, wid),
        perms = Server.Perms(src, wid),
        crewJobs = Source.CrewJobs(src, wid),
        cooldownMode = Config.Sourcing.CooldownMode,
        warehouse = {
            id = w.id, name = loc and loc.name or ('Warehouse #' .. w.id), owner = w.owner_name,
            upgrades = w.upgrades, capacity = Server.Capacity(w), lowerCapacity = Server.Capacity(w, 'lower'),
            stockCount = mainCount, lowerCount = lowerCount, lowerOpen = lowerOpen,
            associates = assoc, maxAssociates = Config.Associates.Max,
            heat = Raid.Heat(w), heatWarn = R.Warn, heatMax = R.Threshold, raid = w.raid ~= nil, raids = R.Enabled,
            claims = math.floor(w.claims or 0),
            trackerSpot = w.trackerSpot, trackerCustom = trk and trk.custom or false, trackerGarage = trk and trk.garage or false,
            scanner = intel and intel.scanner or false,
        },
        layout = {
            presets = presets, preset = w.preset, custom = w.layout and #w.layout > 0 or false,
            slots = Server.Slots(w), max = Config.Layout.MaxSlots, interior = Server.Interior().coords, area = Server.FloorArea(),
        },
        hot = (intel and intel.scanner) and Source.HotList(src) or {},
        prefs = Server.Prefs(w),
        radioChannel = Config.Radio.Enabled and (Config.Radio.Base + w.id) or nil,
        stock = stock,
        contracts = contracts,
        ledger = ledger,
        mission = Server.Players[src] and Server.Players[src].mission and Server.Players[src].mission.kind or nil,
    }
end

-- Static data the UI needs once
lib.callback.register('nz_cargo:static', function(src)
    return {
        version = Cargo.Version,
        rarities = Config.Rarities,
        illegal = Config.Illegal,
        upgrades = Config.Upgrades,
        workshop = Config.Workshop,
        wants = Config.Selling.Wants,
        damage = Config.Selling.Damage,
        buyerTypes = Config.Selling.BuyerTypes,
        quickSale = Config.Selling.QuickSale,
        conditionWeight = Config.Selling.ConditionWeight,
        repairCostOfValue = Config.Repair.CostOfValue,
        associateCut = Config.Associates.Cut,
        levels = Config.Levels,
        layoutMax = Config.Layout.MaxSlots,
        hudCommand = Config.Hud.Command,
        layoutCommand = Config.Layout.Command,
        prefOptions = { accents = Config.Prefs.Accents, finishes = Config.Prefs.Finishes, wallpapers = Config.Prefs.Wallpapers },
        radio = Config.Radio.Enabled,
        roles = Config.Roles.List,
        insurance = Config.Insurance,
        bribe = Config.Raids.Bribe,
        washPrice = Config.Workshop.WashPrice,
        crewSale = { Enabled = Config.CrewSale.Enabled, MinCars = Config.CrewSale.MinCars, MaxCars = Config.CrewSale.MaxCars, Cut = Config.CrewSale.Cut },
    }
end)

-----------------------------------------------------------------
-- Locations, brokers, blips
-----------------------------------------------------------------
lib.callback.register('nz_cargo:locations', function(src)
    local list, mine = {}, {}
    for _, a in ipairs(Server.Accessible(src)) do mine[a.location] = true end
    for id, l in pairs(DB.Locations) do
        if l.enabled or mine[id] then
            list[#list + 1] = { id = id, name = l.name, price = l.price, door = l.door, garage = l.garage, spawn = l.spawn, enabled = l.enabled }
        end
    end
    return { locations = list, access = Server.Accessible(src), interior = Server.Interior(), brokers = DB.Settings.brokers or {}, prefs = Server.MyPrefs(src) }
end)

-- Broker NPC: every location for sale (players can own the same one, it is bucketed)
lib.callback.register('nz_cargo:shop', function(src)
    local s = Server.Get(src)
    if not s then return nil end
    local mine = {}
    for _, w in ipairs(Server.Owned(s.identifier)) do mine[w.location] = true end
    local owners = {}
    for _, w in pairs(DB.Warehouses) do owners[w.location] = (owners[w.location] or 0) + 1 end
    local list = {}
    for id, loc in pairs(DB.Locations) do
        if loc.enabled then
            list[#list + 1] = { id = id, name = loc.name, price = loc.price, owned = mine[id] or false, owners = owners[id] or 0, door = loc.door }
        end
    end
    table.sort(list, function(a, b) return a.price < b.price end)
    local WS = Config.WarehouseSale
    local own = {}
    for _, w in ipairs(Server.Owned(s.identifier)) do
        local loc = locationOf(w)
        own[#own + 1] = {
            id = w.id, location = w.location, name = loc and loc.name or ('Warehouse #' .. w.id), paid = w.paid,
            cars = #DB.GetStock(w.id), quote = Warehouse.SaleQuote(w), tradeIn = Warehouse.TradeIn(w),
        }
    end
    return {
        version = Cargo.Version,
        locations = list,
        mine = own,
        sale = { enabled = WS.Enabled, refund = WS.Refund, upgradeRefund = WS.UpgradeRefund, stockRefund = WS.StockRefund, tradeIn = WS.TradeIn },
        owned = #Server.Owned(s.identifier),
        max = Config.MaxWarehousesPerPlayer,
        cash = Bridge.GetMoney(src, Config.Accounts.Purchase),
        capacity = Config.Upgrades.capacity.levels[1].slots,
        maxCapacity = Config.Layout.MaxSlots,
    }
end)

lib.callback.register('nz_cargo:buy', Server.Once('player', function(src, locationId)
    local s = Server.Get(src)
    local l = DB.Locations[tonumber(locationId)]
    if not s or not l or not l.enabled then return false end
    if #Server.Owned(s.identifier) >= Config.MaxWarehousesPerPlayer then
        Server.Notify(src, L('max_warehouses'), 'error') return false
    end
    if not Server.Charge(src, l.price, 'vehiclecargo-warehouse') then return false end
    local w = DB.CreateWarehouse(s.identifier, s.name, l.id, l.price)
    DB.Log(s.identifier, w.id, 'purchase', l.name, nil, -l.price)
    Server.Notify(src, L('bought_warehouse', l.name), 'success', 'Vehicle Cargo')
    Server.Webhook('Warehouse purchased', { Player = s.name, Location = l.name, Price = '$' .. lib.math.groupdigits(l.price) })
    TriggerClientEvent('nz_cargo:accessChanged', src, Server.Accessible(src))
    return { id = w.id, door = l.door, name = l.name }
end))

-----------------------------------------------------------------
-- Selling / moving a warehouse at the broker
-----------------------------------------------------------------
-- Everything spent on upgrades and interior styles
local function upgradeSpend(w)
    local total = 0
    for track, cfg in pairs(Config.Upgrades) do
        if cfg.levels then
            for i = 2, (tonumber(w.upgrades[track]) or 0) + 1 do
                total = total + (cfg.levels[i] and cfg.levels[i].price or 0)
            end
        elseif cfg.styles then
            for _, sty in ipairs(cfg.styles) do
                if (w.upgrades.owned_styles or {})[sty.id] then total = total + (sty.price or 0) end
            end
        end
    end
    return total
end

function Warehouse.SaleQuote(w)
    local WS = Config.WarehouseSale
    local building = math.floor((w.paid or 0) * WS.Refund)
    local upgrades = math.floor(upgradeSpend(w) * WS.UpgradeRefund)
    local cars = 0
    for _, s in ipairs(DB.GetStock(w.id)) do cars = cars + math.floor(Cargo.BaseValue(s, 0) * WS.StockRefund) end
    return { building = building, upgrades = upgrades, cars = cars, total = building + upgrades + cars }
end

function Warehouse.TradeIn(w)
    return math.floor((w.paid or 0) * Config.WarehouseSale.TradeIn)
end

-- Owner check plus everything that would break if the building changed hands now
local function saleCtx(src, wid)
    local s = Server.Get(src)
    local w = DB.Warehouses[tonumber(wid)]
    if not s or not w or w.owner ~= s.identifier then Server.Notify(src, L('not_owner'), 'error') return nil end
    if not Config.WarehouseSale.Enabled then Server.Notify(src, L('wh_sale_off'), 'error') return nil end
    if s.mission or s.inside then Server.Notify(src, L('busy'), 'error') return nil end
    if w.raid then Server.Notify(src, L('wh_raided'), 'error') return nil end
    if #Server.Occupants(w.id) > 0 then Server.Notify(src, L('wh_occupied'), 'error') return nil end
    for _, st in pairs(Server.Players) do
        if st.mission and st.mission.wid == w.id then Server.Notify(src, L('wh_job_running'), 'error') return nil end
    end
    for _, item in ipairs(DB.GetStock(w.id)) do
        if item.status ~= 'stored' then Server.Notify(src, L('wh_job_running'), 'error') return nil end
    end
    -- no yield between this check and the claim, so a double click can't pay out twice
    if w.closing then return nil end
    w.closing = true
    return s, w
end

-- Tell everyone who could open this warehouse that its doors changed
local function crewChanged(w, oldAssociates)
    local ids = { [w.owner] = true }
    for _, a in ipairs(oldAssociates or w.associates) do ids[a.identifier] = true end
    for tsrc, st in pairs(Server.Players) do
        if ids[st.identifier] then TriggerClientEvent('nz_cargo:accessChanged', tsrc, Server.Accessible(tsrc)) end
    end
end

-- Sell for good: building, upgrades, cars and crew access are gone
lib.callback.register('nz_cargo:warehouse:sell', function(src, wid)
    local s, w = saleCtx(src, wid)
    if not s then return false end
    local loc = locationOf(w)
    local name = loc and loc.name or ('Warehouse #' .. w.id)
    local q = Warehouse.SaleQuote(w)
    local crew = w.associates
    DB.DeleteWarehouse(w.id)
    Bridge.AddMoney(src, Config.Accounts.Payout, q.total, 'vehiclecargo-warehouse-sale')
    DB.Log(s.identifier, w.id, 'wh_sold', name, nil, q.total, q)
    Server.Notify(src, L('sold_warehouse', lib.math.groupdigits(q.total)), 'success', 'Vehicle Cargo')
    Server.Webhook('Warehouse sold', { Player = s.name, Location = name, Payout = '$' .. lib.math.groupdigits(q.total) })
    crewChanged(w, crew)
    return true
end)

-- Move: buy another building and take everything with you (same warehouse, new address)
lib.callback.register('nz_cargo:warehouse:move', function(src, wid, locationId)
    local s, w = saleCtx(src, wid)
    if not s then return false end
    local l = DB.Locations[tonumber(locationId)]
    if not l or not l.enabled or l.id == w.location then w.closing = nil return false end
    for _, o in ipairs(Server.Owned(s.identifier)) do
        if o.location == l.id then w.closing = nil Server.Notify(src, L('max_warehouses'), 'error') return false end
    end
    local from = locationOf(w)
    local net = l.price - Warehouse.TradeIn(w)
    if net > 0 then
        if not Server.Charge(src, net, 'vehiclecargo-warehouse-move') then w.closing = nil return false end
    elseif net < 0 then
        Bridge.AddMoney(src, Config.Accounts.Payout, -net, 'vehiclecargo-warehouse-move')
    end
    DB.MoveWarehouse(w, l.id, l.price)
    w.closing = nil
    DB.Log(s.identifier, w.id, 'wh_moved', l.name, nil, -net, { from = from and from.name or nil })
    Server.Notify(src, L('moved_warehouse', l.name), 'success', 'Vehicle Cargo')
    Server.Webhook('Warehouse moved', { Player = s.name, From = from and from.name or '?', To = l.name, Paid = '$' .. lib.math.groupdigits(net) })
    crewChanged(w)
    return { id = w.id, door = l.door, name = l.name }
end)

-----------------------------------------------------------------
-- Doors: enter, knock, exit, stairs
-----------------------------------------------------------------
local function enterPayload(src, w, role)
    local styleSet
    for _, sty in ipairs(Config.Upgrades.style.styles) do if sty.id == w.upgrades.style then styleSet = sty.set end end
    return {
        id = w.id, role = role, interior = Server.InteriorFor(w), style = styleSet or 'basic_style_set',
        display = Warehouse.Display(w.id), capacity = Server.Capacity(w),
        workshopMode = Config.Workshop.Mode,
    }
end
Warehouse.EnterPayload = enterPayload

lib.callback.register('nz_cargo:enter', function(src, wid)
    wid = tonumber(wid)
    local role = Server.Access(src, wid)
    if not role then Server.Notify(src, L('not_owner'), 'error') return nil end
    local st = Server.Get(src)
    if st.mission and st.mission.kind == 'sell' then Server.Notify(src, L('busy'), 'error') return nil end
    local w = DB.Warehouses[wid]
    if w.closing then Server.Notify(src, L('busy'), 'error') return nil end
    Server.PutInBucket(src, wid)
    return enterPayload(src, w, role)
end)

-- Knock: list occupied warehouses at this door so the visitor picks who to knock for.
lib.callback.register('nz_cargo:knockList', function(src, locationId)
    if not Config.Doors.Knock then return {} end
    local out = {}
    for _, w in pairs(DB.Warehouses) do
        if w.location == tonumber(locationId) and #Server.Occupants(w.id) > 0 then
            out[#out + 1] = { id = w.id, owner = w.owner_name }
        end
    end
    return out
end)

lib.callback.register('nz_cargo:knock', function(src, wid)
    wid = tonumber(wid)
    local w = DB.Warehouses[wid]
    local st = Server.Get(src)
    if not w or not st or not Config.Doors.Knock then return false end
    -- ask someone with real access who is inside
    local host
    for _, o in ipairs(Server.Occupants(wid)) do
        local r = Server.Access(o, wid)
        if r == 'owner' or r == 'associate' then host = o break end
    end
    if not host then return false end
    local ok, accepted = pcall(lib.callback.await, 'nz_cargo:knockPrompt', host, st.name)
    if not ok or not accepted then Server.Notify(src, L('knock_denied'), 'error') return false end
    w.guests = w.guests or {}
    w.guests[st.identifier] = true
    Server.PutInBucket(src, wid)
    return enterPayload(src, w, 'guest')
end)

-- mode: 'front' | 'garage'
lib.callback.register('nz_cargo:exit', function(src, mode)
    local s = Server.Get(src)
    if s and s.preview then
        -- leaving an admin setup copy: back to where they started
        local back = s.preview
        s.preview = nil
        Server.PutInBucket(src, nil)
        return back
    end
    if not s or not s.inside then return nil end
    local w = DB.Warehouses[s.inside]
    if w and w.guests then w.guests[s.identifier] = nil end
    Server.PutInBucket(src, nil)
    local l = w and locationOf(w)
    if not l then return nil end
    if mode == 'garage' and Config.Doors.GarageExit then return l.garageExit or l.garage end
    return l.door
end)

-- Loaded in standing in the interior (restart, relog, character switch) without
-- being inside anything: back into their own warehouse, or out the front door.
lib.callback.register('nz_cargo:resume', function(src)
    local s = Server.Get(src)
    if not s or s.inside or s.preview or s.mission then return nil end
    -- another resource has them in its own bucket: not ours to move
    if GetPlayerRoutingBucket(src) ~= 0 then return nil end
    local p = Server.Profile(src)
    local wid = p and p.last_inside or 0
    local w = DB.Warehouses[wid]
    local role = w and Server.Access(src, wid)
    -- guest passes and police warrants don't survive a restart
    if Config.Resume.PutBackInside and (role == 'owner' or role == 'associate') then
        Server.PutInBucket(src, wid)
        return { enter = enterPayload(src, w, role) }
    end
    Server.PutInBucket(src, nil)
    return { door = Server.FallbackDoor(src, w) }
end)

-----------------------------------------------------------------
-- Laptop
-----------------------------------------------------------------
lib.callback.register('nz_cargo:terminal', function(src)
    local s = Server.Get(src)
    if not s or not s.inside then return nil end
    return Warehouse.Payload(src, s.inside)
end)

-- perm: a Config.Roles permission, or 'owner'
local function ownerCtx(src, perm)
    local s = Server.Get(src)
    if not s or not s.inside or not Server.Can(src, s.inside, perm or 'owner') then
        if s and s.inside and Server.Access(src, s.inside) == 'associate' then Server.Notify(src, L('no_perm'), 'error') end
        return nil
    end
    return s, DB.Warehouses[s.inside]
end
Warehouse.Ctx = ownerCtx

lib.callback.register('nz_cargo:upgrade', function(src, track, choice)
    local s, w = ownerCtx(src, 'upgrades')
    if not s then return false end
    local cfg = Config.Upgrades[track]
    if not cfg then return false end

    if track == 'style' then
        local pick
        for _, sty in ipairs(cfg.styles) do if sty.id == choice then pick = sty end end
        if not pick or w.upgrades.style == pick.id then return false end
        w.upgrades.owned_styles = w.upgrades.owned_styles or { basic = true }
        if not w.upgrades.owned_styles[pick.id] then
            if not Server.Charge(src, pick.price, 'vehiclecargo-style') then return false end
            w.upgrades.owned_styles[pick.id] = true
            DB.Log(s.identifier, w.id, 'upgrade', 'Style: ' .. pick.label, nil, -pick.price)
        end
        w.upgrades.style = pick.id
        DB.SaveWarehouse(w)
        Server.Notify(src, L('style_done', pick.label), 'success')
        for _, o in ipairs(Server.Occupants(w.id)) do TriggerClientEvent('nz_cargo:style', o, pick.set) end
        return Warehouse.Payload(src, w.id)
    end

    local cur = w.upgrades[track] or 0
    local nextLvl = cfg.levels[cur + 2]
    if not nextLvl then return false end
    if not Server.Charge(src, nextLvl.price, 'vehiclecargo-upgrade') then return false end
    w.upgrades[track] = cur + 1
    DB.SaveWarehouse(w)
    DB.Log(s.identifier, w.id, 'upgrade', cfg.label .. ' ' .. (cur + 1), nil, -nextLvl.price)
    Server.Notify(src, L('upgrade_done', cfg.label), 'success')
    Server.Webhook('Warehouse upgrade', { Player = s.name, Upgrade = cfg.label, Level = cur + 1, Price = nextLvl.price })
    if track == 'capacity' or track == 'lower' then Warehouse.Refresh(w.id, true) end
    return Warehouse.Payload(src, w.id)
end)

lib.callback.register('nz_cargo:repair', Server.Once('stock', function(src, stockId)
    local s, w = ownerCtx(src, 'repair')
    if not s then return false end
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' or item.condition >= 100 then return false end
    local cost = Warehouse.RepairCost(w, item)
    if not Server.Charge(src, cost, 'vehiclecargo-repair') then return false end
    item.condition = 100
    DB.UpdateStock(item)
    DB.Log(s.identifier, w.id, 'repair', item.label, item.rarity, -cost)
    Server.Notify(src, L('repair_done', lib.math.groupdigits(cost)), 'success')
    Warehouse.Refresh(w.id)
    return Warehouse.Payload(src, w.id)
end))

-- Scrap a car for parts (frees the slot, small refund)
lib.callback.register('nz_cargo:scrap', Server.Once('stock', function(src, stockId)
    local s, w = ownerCtx(src, 'sell')
    if not s then return false end
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' then return false end
    local refund = math.floor(Cargo.BaseValue(item, 0) * 0.10)
    DB.DeleteStock(item.id)
    Bridge.AddMoney(src, Config.Accounts.Payout, refund, 'vehiclecargo-scrap')
    DB.Log(s.identifier, w.id, 'scrap', item.label, item.rarity, refund)
    Warehouse.Refresh(w.id)
    return Warehouse.Payload(src, w.id)
end))

-----------------------------------------------------------------
-- Floor layout (owner): preset, custom spots, reset
-----------------------------------------------------------------
lib.callback.register('nz_cargo:layout:preset', function(src, id)
    local s, w = ownerCtx(src, 'layout')
    if not s or not Server.Preset(id) then return false end
    w.preset, w.layout = id, nil
    DB.SaveWarehouse(w)
    Warehouse.Refresh(w.id, true)
    Server.Notify(src, L('layout_saved'), 'success')
    return Warehouse.Payload(src, w.id)
end)

lib.callback.register('nz_cargo:layout:custom', function(src, slots)
    local s, w = ownerCtx(src, 'layout')
    if not s or type(slots) ~= 'table' or #slots == 0 then return false end
    local origin = vector3(Config.Interior.Coords.x, Config.Interior.Coords.y, Config.Interior.Coords.z)
    local clean = {}
    for _, p in ipairs(slots) do
        local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
        if x and y and z and #(vector3(x, y, z) - origin) < 80.0 and #clean < Config.Layout.MaxSlots then
            clean[#clean + 1] = { x = x, y = y, z = z, w = (tonumber(p.w) or 0.0) % 360 }
        end
    end
    if #clean == 0 then return false end
    w.layout, w.preset = clean, nil
    DB.SaveWarehouse(w)
    Warehouse.Refresh(w.id, true)
    Server.Notify(src, L('layout_saved'), 'success')
    return true
end)

lib.callback.register('nz_cargo:layout:reset', function(src)
    local s, w = ownerCtx(src, 'layout')
    if not s then return false end
    w.layout, w.preset = nil, nil
    DB.SaveWarehouse(w)
    Warehouse.Refresh(w.id, true)
    return Warehouse.Payload(src, w.id)
end)

-- Owner preferences from the laptop Settings app
lib.callback.register('nz_cargo:prefs', function(src, p)
    local s, w = ownerCtx(src)
    if not s or type(p) ~= 'table' then return false end
    local clean = {}
    for _, k in ipairs({ 'accent', 'finish', 'wallpaper', 'clock' }) do
        if type(p[k]) == 'string' then clean[k] = p[k]:sub(1, 24) end
    end
    for _, k in ipairs({ 'fastboot', 'sounds', 'glass', 'radio' }) do
        if type(p[k]) == 'boolean' then clean[k] = p[k] end
    end
    w.prefs = clean
    w.prefs = Server.Prefs(w)    -- keep only valid values
    DB.SaveWarehouse(w)
    return Warehouse.Payload(src, w.id)
end)

-- Custom tracker removal spot (Tracker Workshop level 3)
lib.callback.register('nz_cargo:tracker:spot', function(src, coords)
    local s = Server.Get(src)
    if not s then return false end
    local w = Server.Owned(s.identifier)[1]
    local trk = w and Cargo.Upgrade('tracker', w.upgrades.tracker)
    if not w or not trk or not trk.custom or type(coords) ~= 'table' or not tonumber(coords.x) then return false end
    w.trackerSpot = { x = tonumber(coords.x), y = tonumber(coords.y), z = tonumber(coords.z) }
    DB.SaveWarehouse(w)
    Server.Notify(src, L('tracker_spot_saved'), 'success')
    return true
end)

-----------------------------------------------------------------
-- Associates
-----------------------------------------------------------------
-- Standing with you: same warehouse copy (routing bucket) and within talking distance
local NEAR = 25.0
function Warehouse.Near(src, other)
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(other) then return false end
    local a, b = GetPlayerPed(src), GetPlayerPed(other)
    if a == 0 or b == 0 then return false end
    return #(GetEntityCoords(a) - GetEntityCoords(b)) < NEAR
end

lib.callback.register('nz_cargo:addAssociate', function(src, target)
    local s, w = ownerCtx(src, 'crew')
    target = tonumber(target)
    if not s or not target or target == src then return false end
    -- only someone actually standing with you (the picker only lists them, a forged request could name anyone)
    if not Warehouse.Near(src, target) then return false end
    if #w.associates >= Config.Associates.Max then Server.Notify(src, L('assoc_full'), 'error') return false end
    local t = Server.Get(target)
    if not t then return false end
    for _, a in ipairs(w.associates) do if a.identifier == t.identifier then return false end end
    w.associates[#w.associates + 1] = { identifier = t.identifier, name = t.name, role = Config.Roles.Default }
    DB.SaveWarehouse(w)
    Server.Notify(src, L('assoc_added', t.name), 'success')
    Server.Notify(target, L('assoc_invited', s.name), 'info', 'Vehicle Cargo')
    TriggerClientEvent('nz_cargo:accessChanged', target, Server.Accessible(target))
    return Warehouse.Payload(src, w.id)
end)

lib.callback.register('nz_cargo:removeAssociate', function(src, identifier)
    local s, w = ownerCtx(src, 'crew')
    if not s then return false end
    -- managers can't remove other managers
    if Server.RoleOf(src, w.id) ~= 'owner' then
        for _, a in ipairs(w.associates) do
            if a.identifier == identifier and Server.Role(a.role).perms.crew then Server.Notify(src, L('no_perm'), 'error') return false end
        end
    end
    for i = #w.associates, 1, -1 do
        if w.associates[i].identifier == identifier then table.remove(w.associates, i) end
    end
    DB.SaveWarehouse(w)
    for tsrc, st in pairs(Server.Players) do
        if st.identifier == identifier then
            TriggerClientEvent('nz_cargo:accessChanged', tsrc, Server.Accessible(tsrc))
            if st.inside == w.id then TriggerClientEvent('nz_cargo:kick', tsrc) end
        end
    end
    Server.Notify(src, L('assoc_removed'), 'success')
    return Warehouse.Payload(src, w.id)
end)

-- Owner sets an associate's role
lib.callback.register('nz_cargo:setRole', function(src, identifier, roleId)
    local s, w = ownerCtx(src, 'owner')
    if not s then return false end
    local valid = false
    for _, r in ipairs(Config.Roles.List) do if r.id == roleId then valid = true end end
    if not valid then return false end
    for _, a in ipairs(w.associates) do
        if a.identifier == identifier then
            a.role = roleId
            for tsrc, st in pairs(Server.Players) do
                if st.identifier == identifier then Server.Notify(tsrc, L('role_set', Server.Role(roleId).label), 'info', 'Vehicle Cargo') end
            end
        end
    end
    DB.SaveWarehouse(w)
    return Warehouse.Payload(src, w.id)
end)

-- Nearby players for the associate picker
lib.callback.register('nz_cargo:nearbyPlayers', function(src)
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if id ~= src and Warehouse.Near(src, id) then out[#out + 1] = { id = id, name = Bridge.GetName(id) } end
    end
    return out
end)

-----------------------------------------------------------------
-- Leaderboard
-----------------------------------------------------------------
lib.callback.register('nz_cargo:leaderboard', function(src)
    local earned = MySQL.query.await('SELECT name, xp, earned, sold, sourced, best_sale FROM nz_cargo_profiles ORDER BY earned DESC LIMIT 15') or {}
    local levels = MySQL.query.await('SELECT name, xp, earned, sold, sourced, best_sale FROM nz_cargo_profiles ORDER BY xp DESC LIMIT 15') or {}
    local function map(rows)
        for _, r in ipairs(rows) do r.level = Cargo.LevelFromXp(r.xp) end
        return rows
    end
    return { earned = map(earned), levels = map(levels) }
end)

-----------------------------------------------------------------
-- Insurance, claims and prestige
-----------------------------------------------------------------
lib.callback.register('nz_cargo:insure', Server.Once('stock', function(src, stockId)
    local s, w = ownerCtx(src, 'insurance')
    if not s then return false end
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' or item.insured then return false end
    if not Raid.Insurable(item) then Server.Notify(src, L('ins_denied'), 'error') return false end
    local cost = Raid.Premium(w, item)
    if not Server.Charge(src, cost, 'vehiclecargo-insurance') then return false end
    item.insured = true
    DB.SetStockInsured(item.id, true)
    DB.Log(s.identifier, w.id, 'insure', item.label, item.rarity, -cost)
    Server.Notify(src, L('ins_done', item.label), 'success', 'Insurance')
    return Warehouse.Payload(src, w.id)
end))

lib.callback.register('nz_cargo:claims', function(src)
    local s, w = ownerCtx(src, 'owner')
    if not s or (w.claims or 0) <= 0 then return false end
    local amount = math.floor(w.claims)
    w.claims = 0
    DB.SaveWarehouse(w)
    Bridge.AddMoney(src, Config.Accounts.Payout, amount, 'vehiclecargo-claims')
    Server.Notify(src, L('claim_collected', lib.math.groupdigits(amount)), 'success', 'Insurance')
    return Warehouse.Payload(src, w.id)
end)

lib.callback.register('nz_cargo:prestige', function(src)
    local P = Config.Prestige
    local s = Server.Get(src)
    if not P.Enabled or not s or not s.inside then return false end
    local p = Server.Profile(src)
    if Cargo.LevelFromXp(p.xp) < Config.Levels.Max then Server.Notify(src, L('prestige_level', Config.Levels.Max), 'error') return false end
    if (p.prestige or 0) >= P.Max then Server.Notify(src, L('prestige_max'), 'error') return false end
    if not Server.Charge(src, P.Cost, 'vehiclecargo-prestige') then return false end
    p.prestige = (p.prestige or 0) + 1
    p.xp = 0
    DB.SaveProfile(p)
    DB.Log(s.identifier, s.inside, 'prestige', ('Prestige %d'):format(p.prestige), nil, -P.Cost)
    Server.Notify(src, L('prestige_done', p.prestige), 'success', 'Prestige')
    Server.Webhook('Prestige', { Player = s.name, Prestige = p.prestige })
    TriggerClientEvent('nz_cargo:levelUp', src, 1, p.prestige)
    return Warehouse.Payload(src, s.inside)
end)
