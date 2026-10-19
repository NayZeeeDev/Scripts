--[[
    NAYZEEE AMBULANCE - Server: pharmacy shop, stock & staff view (pharmacy module)

    Shop positions are hospital points of type 'pharmacy' (placed in the EMS Manager). A
    'checkin' desk point may open the same window in desk mode (insurance + bills only).

    Everything is checked here: the session point, the player's distance to it (server ped),
    alive, staff-only counters, product restrictions (perm / medic / job + grade / licence),
    stock, quantities, prices (recomputed - the client total must match), money, carry weight.

    Internals shared with pharmacy_billing.lua (NZA.Pharmacy):
      P.Session(src, pointId) → ctx | nil, err      P.OpenData(src, ctx, tab?) → window data
      P.LogSale(ctx, src, lines, totals)            P.Catalogue() → products, byId
      P.Stock(pool, product) → units | false        P.Society(ctx) → society account

    Callbacks:
      nza:pharmacy:open    (pointId, tab?)                → { ok, data }
      nza:pharmacy:refresh (pointId)                      → { ok, data }
      nza:pharmacy:buy     (pointId, lines[{id, qty}], method, expectedTotal) → { ok, receipt, data } | { ok = false, err, msg, data? }
      nza:pharmacy:staff   (pointId)                      → { ok, staff }
      nza:pharmacy:restock (pointId, productId, qty, from = 'order'|'inventory') → { ok, staff, msg }
    Bus: pharmacy:sale (src, sale) · pharmacy:restock (pool, productId, qty, from)
    Tables: nza_pharmacy_stock (pool, item, stock) · nza_pharmacy_sales
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Pharmacy = NZA.Pharmacy or {}
local P = NZA.Pharmacy
local Core = NZA.Core
local U = NZA.Util

local sessions = {}     -- src → { point = id, at = ms }
local stock = {}        -- pool → { [productId] = units }
local catalogue, byId = nil, nil
local images = {}       -- item name → nui url
local dbReady = false

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function L(key, ...) return NZA.L('pharmacy.' .. key, ...) end

local function cfg(section)
    local c = Config.Pharmacy or {}
    if section then return c[section] or {} end
    return c
end

local function bridge(path, ...) return Core.B(path, ...) end

local function hasDB() return MySQL ~= nil and MySQL.query ~= nil end

local function dbQuery(sql, params)
    if not hasDB() then return nil end
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        NZA.Warn('pharmacy SQL failed: ' .. tostring(res))
        return nil
    end
    return res
end

local function dbExec(sql, params)
    if not hasDB() then return end
    local ok, err = pcall(MySQL.query, sql, params or {})
    if not ok then NZA.Warn('pharmacy SQL failed: ' .. tostring(err)) end
end

local function fail(err, extra)
    local out = { ok = false, err = err, msg = L('err_' .. tostring(err)) }
    if type(extra) == 'table' then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function rate(src, kind)
    local r = cfg('rates')[kind] or { 8, 5000 }
    return Core.Rate('pharmacy:' .. kind, src, r[1] or 8, r[2] or 5000)
end

local function pointCoords(pt)
    local c = pt and pt.coords
    if not c then return nil end
    return vector3(tonumber(c.x) or 0.0, tonumber(c.y) or 0.0, tonumber(c.z) or 0.0)
end

local function pointData(pt)
    local d = {}
    for k, v in pairs(cfg('pointDefaults')) do d[k] = v end
    if pt and type(pt.data) == 'table' then
        for k, v in pairs(pt.data) do d[k] = v end
    end
    return d
end

local function startOfDay(t)
    local d = os.date('*t', t or os.time())
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

-- ════════════════════════════════════════════════════════════════════════
-- CATALOGUE
-- ════════════════════════════════════════════════════════════════════════

function P.Catalogue()
    if catalogue then return catalogue, byId end
    catalogue, byId = {}, {}
    local sc = cfg('stock')
    local maxQ = math.max(1, math.floor(tonumber(cfg().maxQuantity) or 25))
    for i, e in ipairs(cfg().products or {}) do
        local name = e.name or (e.item and Config.Items and Config.Items[e.item]) or nil
        if type(name) == 'string' and name ~= '' then
            local id = tostring(e.id or e.item or name)
            if byId[id] then
                NZA.Warn(('pharmacy: product "%s" is listed twice, the second entry is ignored'):format(id))
            else
                local def = (e.item and Config.ItemDefs and Config.ItemDefs[e.item]) or {}
                local base = math.max(0, math.floor(tonumber(e.price) or 0))
                local disc = U.clamp(tonumber(e.discount) or 0, 0, 0.95)
                local unit = math.floor(base * (1 - disc) + 0.5)
                local st = false
                if sc.enabled ~= false and tonumber(e.stock) and tonumber(e.stock) > 0 then st = math.floor(tonumber(e.stock)) end
                local prod = {
                    id = id, name = name, key = e.item, order = i,
                    label = e.label or def.label, description = e.description or def.description or '',
                    category = e.category or (def.category and (cfg().itemCategory or {})[def.category]) or def.category or 'devices',
                    base = base, price = unit, was = disc > 0 and base or nil, discount = disc,
                    stock = st, limit = math.max(1, math.floor(tonumber(e.limit) or maxQ)),
                    perm = e.perm, medicOnly = e.medicOnly == true, jobs = e.jobs, minGrade = tonumber(e.minGrade),
                    license = e.license, featured = e.featured == true,
                }
                catalogue[#catalogue + 1] = prod
                byId[id] = prod
            end
        end
    end
    return catalogue, byId
end

local function labelOf(prod)
    if prod.label then return prod.label end
    local l = bridge('Inv.Label', prod.name)
    if type(l) == 'string' and l ~= '' and l ~= prod.name then
        prod.label = l
        return l
    end
    return prod.name
end

local function imageOf(name)
    if images[name] then return images[name] end
    local url = bridge('Inv.Image', name)
    if type(url) ~= 'string' or url == '' then
        url = ('nui://%s/html/img/items/%s.png'):format(GetCurrentResourceName(), name)
    end
    images[name] = url
    return url
end

-- ════════════════════════════════════════════════════════════════════════
-- STOCK (per department "pool")
-- ════════════════════════════════════════════════════════════════════════

local function saveStock(pool, id, n)
    dbExec('INSERT INTO `nza_pharmacy_stock` (`pool`, `item`, `stock`) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE `stock` = VALUES(`stock`)', { pool, id, n })
end

function P.Stock(pool, prod)
    if not prod.stock then return false end
    local t = stock[pool]
    if not t then
        t = {}
        stock[pool] = t
    end
    if t[prod.id] == nil then
        t[prod.id] = prod.stock
        if dbReady then saveStock(pool, prod.id, prod.stock) end
    end
    return t[prod.id]
end

local function setStock(pool, prod, n)
    if not prod.stock then return end
    stock[pool] = stock[pool] or {}
    n = math.max(0, math.floor(n))
    stock[pool][prod.id] = n
    saveStock(pool, prod.id, n)
end

-- ════════════════════════════════════════════════════════════════════════
-- CONTEXT (who is buying where)
-- ════════════════════════════════════════════════════════════════════════

local function staffRec(src)
    return (NZA.Staff and NZA.Staff.Get and NZA.Staff.Get(src)) or {}
end

function P.Society(ctx)
    if ctx and ctx.dept and NZA.Hospitals and NZA.Hospitals.Society then
        local s = NZA.Hospitals.Society(ctx.dept)
        if s then return s end
    end
    return (Config.Billing and Config.Billing.society) or 'ambulance'
end

local function buildCtx(src, pointId)
    if cfg().enabled == false then return nil, 'disabled' end
    if not (NZA.Hospitals and NZA.Hospitals.Point) then return nil, 'no_point' end
    local pt = NZA.Hospitals.Point(pointId)
    if not pt or (pt.type ~= 'pharmacy' and pt.type ~= 'checkin') then return nil, 'no_point' end
    local pos = pointCoords(pt)
    local me = Core.SrcCoords(src)
    local ic = cfg('interact')
    local reach = (tonumber(ic.maxDistance) or 4.0) + 1.5
    if not pos or not me or #(me - pos) > reach then return nil, 'too_far' end
    local p = NZA.Patients and NZA.Patients.GetBySource and NZA.Patients.GetBySource(src)
    if p and p.state ~= 'alive' then return nil, 'down' end

    local data = pointData(pt)
    local rec = staffRec(src)
    local admin = Core.IsAdmin(src)
    local member = rec.dept ~= nil and pt.hospital ~= nil and rec.dept == pt.hospital
    local onDutyMember = member and rec.onDuty == true
    if pt.type == 'pharmacy' and data.staffOnly == true and not onDutyMember and not admin then
        return nil, 'staff_only'
    end
    local dept = pt.hospital and NZA.Hospitals.Get and NZA.Hospitals.Get(pt.hospital) or nil
    local ctx = {
        src = src, point = pt, pointId = pt.id, mode = pt.type == 'checkin' and 'desk' or 'shop',
        pool = pt.hospital and tostring(pt.hospital) or 'global', dept = pt.hospital,
        deptLabel = dept and dept.label or nil, label = pt.label,
        identifier = Core.Identifier(src), staff = rec, admin = admin,
        medicOnDuty = rec.medic == true and rec.onDuty == true,
        member = member, onDutyMember = onDutyMember,
        allowInsurance = cfg('insurance').enabled ~= false and data.insurance ~= false,
        allowBills = data.bills ~= false,
        canManage = pt.type == 'pharmacy' and (admin or (member and NZA.Staff.Can(src, cfg('staff').perm or 'pharmacy'))),
        licenses = {},
    }
    ctx.society = P.Society(ctx)
    return ctx
end

function P.Session(src, pointId)
    local s = sessions[src]
    if not s or tostring(s.point) ~= tostring(pointId) then return nil, 'no_session' end
    local ctx, err = buildCtx(src, s.point)
    if not ctx then return nil, err end
    s.at = GetGameTimer()
    return ctx
end

-- ════════════════════════════════════════════════════════════════════════
-- RESTRICTIONS & PRICES
-- ════════════════════════════════════════════════════════════════════════

local function hasLicense(src, lic, ctx)
    if ctx.licenses[lic] ~= nil then return ctx.licenses[lic] end
    local has = false
    local fw = Bridge and Bridge.Framework
    if Core.Has('HasLicense') then
        -- the bridge knows every framework's licences (falls back to the nza.license.<name> ace)
        has = bridge('HasLicense', src, tostring(lic)) == true
    elseif fw == 'qbcore' or fw == 'qbox' then
        local pl = bridge('GetPlayer', src)
        local md = pl and pl.PlayerData and pl.PlayerData.metadata
        has = type(md) == 'table' and type(md.licences) == 'table' and md.licences[lic] == true
    elseif fw == 'esx' and GetResourceState('esx_license') == 'started' then
        local p = promise.new()
        TriggerEvent('esx_license:checkLicense', src, lic, function(v) p:resolve(v == true) end)
        SetTimeout(2000, function() if p.state == 0 then p:resolve(false) end end)
        has = Citizen.Await(p) == true
    else
        has = IsPlayerAceAllowed(tostring(src), 'nza.license.' .. tostring(lic)) == true
    end
    ctx.licenses[lic] = has
    return has
end

local function allowed(src, prod, ctx)
    if prod.medicOnly and not ctx.medicOnDuty and not ctx.admin then return false, 'medics' end
    if prod.perm and not NZA.Staff.Can(src, prod.perm) then return false, 'perm' end
    if type(prod.jobs) == 'table' then
        ctx.job = ctx.job or bridge('GetJob', src) or {}
        local ok = false
        for _, j in ipairs(prod.jobs) do
            if j == ctx.job.name then ok = true break end
        end
        if not ok then return false, 'job' end
        if prod.minGrade and (tonumber(ctx.job.grade) or 0) < prod.minGrade then return false, 'grade' end
    end
    if prod.license and not hasLicense(src, prod.license, ctx) then return false, 'license' end
    return true
end

local function discountFor(ctx)
    local ins = ctx.identifier and NZA.Insurance and NZA.Insurance.Get and NZA.Insurance.Get(ctx.identifier) or nil
    local insPct = ins and ins.pharmacy or 0
    local staffPct = 0
    if ctx.medicOnDuty and (ctx.dept == nil or ctx.staff.dept == ctx.dept) then
        staffPct = U.clamp(tonumber(cfg().staffDiscount) or 0, 0, 0.9)
    end
    local out = { insurance = insPct, staff = staffPct, plan = ins and ins.label or nil, planId = ins and ins.plan or nil }
    if cfg().stackDiscounts then
        out.pct = 1 - (1 - insPct) * (1 - staffPct)
        out.kind = (insPct > 0 and staffPct > 0) and 'both' or (insPct > 0 and 'insurance' or (staffPct > 0 and 'staff' or nil))
    elseif insPct >= staffPct then
        out.pct = insPct
        out.kind = insPct > 0 and 'insurance' or nil
    else
        out.pct = staffPct
        out.kind = 'staff'
    end
    return out
end

local function price(ctx, lines)
    local sub = 0
    for _, l in ipairs(lines) do
        l.unit = l.prod.price
        l.total = l.unit * l.qty
        sub = sub + l.total
    end
    local d = discountFor(ctx)
    local discount = math.floor(sub * d.pct + 0.5)
    local taxPct = U.clamp(tonumber(cfg().tax) or 0, 0, 1)
    local tax = math.floor((sub - discount) * taxPct + 0.5)
    return { subtotal = sub, discount = discount, discountKind = d.kind, discountPct = d.pct, plan = d.plan, tax = tax, taxPct = taxPct, total = sub - discount + tax }
end

-- ════════════════════════════════════════════════════════════════════════
-- WINDOW DATA
-- ════════════════════════════════════════════════════════════════════════

local function wallet(src)
    return { cash = math.floor(tonumber(bridge('GetMoney', src, 'cash')) or 0), bank = math.floor(tonumber(bridge('GetMoney', src, 'bank')) or 0) }
end

local function productsFor(src, ctx)
    local list, counts = {}, {}
    if ctx.mode ~= 'shop' then return list, counts end
    local showLocked = cfg().showRestricted ~= false
    local lowAt = U.clamp(tonumber(cfg('stock').lowAt) or 0.25, 0, 1)
    for _, prod in ipairs((P.Catalogue())) do
        local ok, why = allowed(src, prod, ctx)
        if ok or showLocked then
            local st = P.Stock(ctx.pool, prod)
            list[#list + 1] = {
                id = prod.id, name = prod.name, label = labelOf(prod), description = prod.description,
                category = prod.category, price = prod.price, was = prod.was, discount = prod.discount,
                stock = st ~= false and st or nil, max = prod.stock or nil,
                low = st ~= false and st > 0 and st <= math.max(1, math.floor(prod.stock * lowAt)) or nil,
                limit = prod.limit, featured = prod.featured or nil, order = prod.order,
                locked = (not ok) or nil, lock = (not ok) and why or nil, lockText = (not ok) and L('lock_' .. why) or nil,
                image = imageOf(prod.name),
            }
            counts[prod.category] = (counts[prod.category] or 0) + 1
        end
    end
    return list, counts
end

local function insuranceData(ctx)
    if not ctx.allowInsurance or not NZA.Insurance then return { enabled = false } end
    local Ins = NZA.Insurance
    local raw = Ins.Raw(ctx.identifier)
    local now = os.time()
    local current
    if raw then
        local plans = Ins.Plans()
        local def
        for _, p in ipairs(plans) do if p.id == raw.plan then def = p end end
        current = {
            plan = raw.plan, label = def and def.label or raw.plan, icon = def and def.icon or 'shield',
            cover = def and def.cover or 0, pharmacy = def and def.pharmacy or 0, days = def and def.days or 0,
            expires = raw.expires, started = raw.started, serial = raw.serial, active = raw.expires > now,
        }
    end
    local plans = {}
    for _, p in ipairs(Ins.Plans()) do
        local q = Ins.Quote(ctx.identifier, p.id)
        p.action = q.action
        p.credit = q.credit
        p.pay = q.pay
        p.newExpires = q.expires
        p.allowed = q.allowed
        p.reason = (not q.allowed) and L('err_' .. tostring(q.reason), q.waitDays or 0) or nil
        plans[#plans + 1] = p
    end
    return { enabled = true, current = current, plans = plans, maxDays = tonumber(cfg('insurance').maxDays) or 90, card = cfg('insurance').giveCard ~= false }
end

local function billsData(ctx)
    if not ctx.allowBills or not NZA.Billing or not NZA.Billing.Bills then return { enabled = false, list = {}, history = {} } end
    local all = NZA.Billing.Bills(ctx.identifier)
    local open, hist, total = {}, {}, 0
    for _, b in ipairs(all) do
        if b.status == 'unpaid' then
            open[#open + 1] = b
            total = total + b.amount
        elseif b.status == 'paid' and #hist < 10 then
            hist[#hist + 1] = b
        end
    end
    return { enabled = true, list = open, history = hist, total = total }
end

function P.OpenData(src, ctx, tab)
    local products, counts = productsFor(src, ctx)
    local cats = {}
    for _, c in ipairs(cfg().categories or {}) do
        cats[#cats + 1] = { id = c.id, icon = c.icon or 'tag', label = c.label or L('cat_' .. c.id), count = counts[c.id] or 0 }
    end
    -- categories used by products but missing from the list
    local known = {}
    for _, c in ipairs(cats) do known[c.id] = true end
    for id, n in pairs(counts) do
        if not known[id] then cats[#cats + 1] = { id = id, icon = 'tag', label = L('cat_' .. id), count = n } end
    end
    local d = discountFor(ctx)
    local pay = cfg('payment')
    return {
        point = ctx.pointId, mode = ctx.mode, tab = tab,
        shop = { label = ctx.label, dept = ctx.deptLabel, staffOnly = pointData(ctx.point).staffOnly == true },
        categories = cats, products = products,
        wallet = wallet(src),
        payment = { cash = pay.cash ~= false, bank = pay.bank ~= false, default = pay.default == 'cash' and 'cash' or 'bank' },
        tax = U.clamp(tonumber(cfg().tax) or 0, 0, 1),
        discount = { pct = d.pct, kind = d.kind, plan = d.plan, insurance = d.insurance, staff = d.staff },
        maxLines = math.max(1, math.floor(tonumber(cfg().maxLines) or 30)),
        insurance = insuranceData(ctx),
        bills = billsData(ctx),
        canManage = ctx.canManage == true,
        me = { name = Core.Name(src) },
        now = os.time(),
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- SALES LOG
-- ════════════════════════════════════════════════════════════════════════

function P.LogSale(ctx, src, lines, totals)
    local items = {}
    for _, l in ipairs(lines) do
        items[#items + 1] = { id = l.id or (l.prod and l.prod.id), label = l.label or (l.prod and labelOf(l.prod)), qty = l.qty, unit = l.unit, total = l.total }
    end
    local sale = {
        pool = ctx.pool, point = tonumber(ctx.pointId) or 0, identifier = ctx.identifier, name = Core.Name(src),
        items = items, subtotal = totals.subtotal or 0, discount = totals.discount or 0, tax = totals.tax or 0,
        total = totals.total or 0, method = totals.method, kind = totals.kind or 'shop', created = os.time(),
    }
    dbExec('INSERT INTO `nza_pharmacy_sales` (`pool`, `point`, `identifier`, `name`, `items`, `subtotal`, `discount`, `tax`, `total`, `method`, `kind`, `created`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { sale.pool, sale.point, sale.identifier, sale.name, json.encode(items), sale.subtotal, sale.discount, sale.tax, sale.total, sale.method, sale.kind, sale.created })
    NZA.Bus.Emit('pharmacy:sale', src, sale)
    return sale
end

-- ════════════════════════════════════════════════════════════════════════
-- CALLBACKS: open / refresh / buy
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:pharmacy:open', function(src, pointId, tab)
    if not rate(src, 'open') then return fail('rate') end
    local ctx, err = buildCtx(src, pointId)
    if not ctx then return fail(err) end
    sessions[src] = { point = ctx.pointId, at = GetGameTimer() }
    local data = P.OpenData(src, ctx, type(tab) == 'string' and tab:sub(1, 16) or nil)
    data.locale = NZA.LocaleTable('pharmacy')
    return { ok = true, data = data }
end)

lib.callback.register('nza:pharmacy:refresh', function(src, pointId)
    if not rate(src, 'action') then return fail('rate') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    return { ok = true, data = P.OpenData(src, ctx) }
end)

lib.callback.register('nza:pharmacy:buy', function(src, pointId, lines, method, expected)
    if not rate(src, 'buy') then return fail('rate') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    if ctx.mode ~= 'shop' then return fail('no_point') end
    local pay = cfg('payment')
    if (method ~= 'cash' and method ~= 'bank') or pay[method] == false then return fail('bad_method') end
    if type(lines) ~= 'table' then return fail('empty') end

    -- validate & merge lines
    local _, prods = P.Catalogue()
    local merged, order = {}, {}
    local maxLines = math.max(1, math.floor(tonumber(cfg().maxLines) or 30))
    local count = 0
    for _, l in pairs(lines) do
        count = count + 1
        if count > maxLines * 2 then return fail('too_many') end
        if type(l) == 'table' then
            local id = tostring(l.id or '')
            local qty = math.floor(tonumber(l.qty) or 0)
            local prod = prods[id]
            if not prod then return fail('bad_item') end
            if qty < 1 then return fail('bad_qty') end
            if not merged[id] then
                merged[id] = { prod = prod, qty = 0, id = id }
                order[#order + 1] = merged[id]
            end
            merged[id].qty = merged[id].qty + qty
        end
    end
    if #order == 0 then return fail('empty') end
    if #order > maxLines then return fail('too_many') end

    for _, l in ipairs(order) do
        if l.qty > l.prod.limit then return fail('limit', { item = labelOf(l.prod), limit = l.prod.limit, msg = L('err_limit', labelOf(l.prod), l.prod.limit) }) end
        local ok, why = allowed(src, l.prod, ctx)
        if not ok then return fail('locked', { msg = L('err_locked', labelOf(l.prod), L('lock_' .. why)) }) end
        local st = P.Stock(ctx.pool, l.prod)
        if st ~= false and st < l.qty then
            return fail('stock', { msg = L('err_stock', labelOf(l.prod), st), data = P.OpenData(src, ctx) })
        end
        if bridge('Inv.CanCarry', src, l.prod.name, l.qty) == false then
            return fail('carry', { msg = L('err_carry', labelOf(l.prod)) })
        end
    end

    local t = price(ctx, order)
    if expected ~= nil and math.floor(tonumber(expected) or -1) ~= t.total then
        return fail('price_changed', { data = P.OpenData(src, ctx) })
    end
    if (tonumber(bridge('GetMoney', src, method)) or 0) < t.total then return fail('no_money') end

    -- reserve stock first so two buyers can't take the last unit together
    for _, l in ipairs(order) do
        local st = P.Stock(ctx.pool, l.prod)
        if st ~= false then
            if st < l.qty then return fail('stock', { msg = L('err_stock', labelOf(l.prod), st), data = P.OpenData(src, ctx) }) end
            stock[ctx.pool][l.prod.id] = st - l.qty
        end
    end
    local function release(l)
        if l.prod.stock then stock[ctx.pool][l.prod.id] = (stock[ctx.pool][l.prod.id] or 0) + l.qty end
    end

    if t.total > 0 and not bridge('RemoveMoney', src, method, t.total, L('reason_shop')) then
        for _, l in ipairs(order) do release(l) end
        return fail('no_money')
    end

    -- hand out the items; refund lines the inventory refuses
    local given, refund = {}, 0
    local paidRatio = t.subtotal > 0 and (t.total / t.subtotal) or 0
    for _, l in ipairs(order) do
        local ok = bridge('Inv.AddItem', src, l.prod.name, l.qty, nil)
        if ok then
            given[#given + 1] = l
            if l.prod.stock then saveStock(ctx.pool, l.prod.id, stock[ctx.pool][l.prod.id]) end
        else
            release(l)
            refund = refund + math.floor(l.total * paidRatio + 0.5)
        end
    end
    refund = math.min(refund, t.total)
    if refund > 0 then bridge('AddMoney', src, method, refund, L('reason_refund')) end
    if #given == 0 then return fail('carry', { msg = L('err_nothing_given') }) end

    local paid = t.total - refund
    local inc = cfg('income')
    if paid > 0 and inc.toSociety ~= false then
        local share = math.floor(paid * U.clamp(tonumber(inc.share) or 1, 0, 1))
        if share > 0 then bridge('Society.Add', ctx.society, share) end
    end

    local rlines = {}
    for _, l in ipairs(given) do
        rlines[#rlines + 1] = { id = l.prod.id, name = l.prod.name, label = labelOf(l.prod), qty = l.qty, unit = l.unit, total = l.total, image = imageOf(l.prod.name) }
    end
    local sale = P.LogSale(ctx, src, rlines, { subtotal = t.subtotal, discount = t.discount, tax = t.tax, total = paid, method = method })
    local receipt = {
        no = ('RX-%s-%04d'):format(os.date('%y%m%d', sale.created), math.random(0, 9999)),
        lines = rlines, subtotal = t.subtotal, discount = t.discount, discountKind = t.discountKind, discountPct = t.discountPct,
        plan = t.plan, tax = t.tax, total = paid, refund = refund, method = method, time = sale.created,
        partial = #given < #order,
    }
    return { ok = true, receipt = receipt, data = P.OpenData(src, ctx) }
end)

-- ════════════════════════════════════════════════════════════════════════
-- STAFF: stock levels, ordering, sales log
-- ════════════════════════════════════════════════════════════════════════

local function staffData(src, ctx)
    local lowAt = U.clamp(tonumber(cfg('stock').lowAt) or 0.25, 0, 1)
    local orderCost = U.clamp(tonumber(cfg('stock').orderCost) or 0.45, 0, 5)
    local lines, low, out = {}, 0, 0
    for _, prod in ipairs((P.Catalogue())) do
        if prod.stock then
            local st = P.Stock(ctx.pool, prod)
            if st == 0 then out = out + 1 elseif st <= math.max(1, math.floor(prod.stock * lowAt)) then low = low + 1 end
            lines[#lines + 1] = {
                id = prod.id, name = prod.name, label = labelOf(prod), category = prod.category, image = imageOf(prod.name),
                stock = st, max = prod.stock, price = prod.price, orderUnit = math.ceil(prod.base * orderCost),
                have = cfg('stock').fromInventory ~= false and math.floor(tonumber(bridge('Inv.Count', src, prod.name)) or 0) or 0,
            }
        end
    end
    local now = os.time()
    local today, week = startOfDay(now), now - 7 * 86400
    local rows = dbQuery('SELECT `id`, `name`, `items`, `total`, `discount`, `method`, `kind`, `created` FROM `nza_pharmacy_sales` WHERE `pool` = ? ORDER BY `id` DESC LIMIT ?',
        { ctx.pool, math.max(5, math.floor(tonumber(cfg('staff').salesLog) or 60)) }) or {}
    local sales = {}
    for _, r in ipairs(rows) do
        local ok, items = pcall(json.decode, r.items or '[]')
        sales[#sales + 1] = {
            id = tonumber(r.id), name = r.name, items = ok and items or {}, total = tonumber(r.total) or 0,
            discount = tonumber(r.discount) or 0, method = r.method, kind = r.kind, created = tonumber(r.created) or 0,
        }
    end
    local agg = dbQuery('SELECT COALESCE(SUM(CASE WHEN `created` >= ? THEN `total` ELSE 0 END), 0) AS `today`, COALESCE(SUM(CASE WHEN `created` >= ? THEN 1 ELSE 0 END), 0) AS `todayCount`, COALESCE(SUM(`total`), 0) AS `week`, COUNT(*) AS `weekCount` FROM `nza_pharmacy_sales` WHERE `pool` = ? AND `created` >= ?',
        { today, today, ctx.pool, week })
    local a = (agg and agg[1]) or {}
    return {
        products = lines, sales = sales, low = low, out = out,
        stats = { today = tonumber(a.today) or 0, todayCount = tonumber(a.todayCount) or 0, week = tonumber(a.week) or 0, weekCount = tonumber(a.weekCount) or 0 },
        society = { name = ctx.society, balance = math.floor(tonumber(bridge('Society.Get', ctx.society)) or 0) },
        orderMax = math.max(1, math.floor(tonumber(cfg('stock').orderMax) or 50)),
        fromInventory = cfg('stock').fromInventory ~= false,
        dept = ctx.deptLabel,
    }
end

lib.callback.register('nza:pharmacy:staff', function(src, pointId)
    if not rate(src, 'action') then return fail('rate') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    if not ctx.canManage then return fail('no_perm') end
    return { ok = true, staff = staffData(src, ctx) }
end)

lib.callback.register('nza:pharmacy:restock', function(src, pointId, productId, qty, from)
    if not rate(src, 'action') then return fail('rate') end
    local ctx, err = P.Session(src, pointId)
    if not ctx then return fail(err) end
    if not ctx.canManage then return fail('no_perm') end
    local _, prods = P.Catalogue()
    local prod = prods[tostring(productId or '')]
    if not prod or not prod.stock then return fail('bad_item') end
    qty = math.floor(tonumber(qty) or 0)
    local orderMax = math.max(1, math.floor(tonumber(cfg('stock').orderMax) or 50))
    if qty < 1 or qty > orderMax then return fail('bad_qty') end
    local st = P.Stock(ctx.pool, prod)
    local room = prod.stock - st
    if room <= 0 then return fail('shelf_full') end
    qty = math.min(qty, room)

    if from == 'inventory' then
        if cfg('stock').fromInventory == false then return fail('disabled') end
        local have = math.floor(tonumber(bridge('Inv.Count', src, prod.name)) or 0)
        if have <= 0 then return fail('none_in_inventory') end
        qty = math.min(qty, have)
        if not bridge('Inv.RemoveItem', src, prod.name, qty) then return fail('none_in_inventory') end
    else
        local unit = math.ceil(prod.base * U.clamp(tonumber(cfg('stock').orderCost) or 0.45, 0, 5))
        local cost = unit * qty
        if cost > 0 then
            local bal = tonumber(bridge('Society.Get', ctx.society)) or 0
            if bal < cost then return fail('society_funds', { msg = L('err_society_funds', P.Money(cost)) }) end
            if not bridge('Society.Remove', ctx.society, cost) then return fail('society_funds', { msg = L('err_society_funds', P.Money(cost)) }) end
        end
        from = 'order'
    end
    setStock(ctx.pool, prod, P.Stock(ctx.pool, prod) + qty)
    NZA.Bus.Emit('pharmacy:restock', ctx.pool, prod.id, qty, from)
    NZA.Debug('pharmacy restock', ctx.pool, prod.id, qty, from, Core.Name(src))
    return { ok = true, staff = staffData(src, ctx), msg = L('restocked_' .. from, qty, labelOf(prod)) }
end)

-- ════════════════════════════════════════════════════════════════════════
-- AUTO RESTOCK
-- ════════════════════════════════════════════════════════════════════════

local function pools()
    local out = { global = true }
    if NZA.Hospitals and NZA.Hospitals.Points then
        local ok, list = pcall(NZA.Hospitals.Points, 'pharmacy')
        if ok and type(list) == 'table' then
            for _, pt in pairs(list) do
                if pt.hospital then out[tostring(pt.hospital)] = true end
            end
        end
    end
    for pool in pairs(stock) do out[pool] = true end
    return out
end

local function autoRestock()
    local ar = cfg('stock').autoRestock or {}
    local orderCost = U.clamp(tonumber(cfg('stock').orderCost) or 0.45, 0, 5)
    for pool in pairs(pools()) do
        local society = P.Society({ dept = pool ~= 'global' and pool or nil })
        for _, prod in ipairs((P.Catalogue())) do
            if prod.stock then
                local st = P.Stock(pool, prod)
                local add = math.min(prod.stock - st, math.max(1, math.ceil(prod.stock * U.clamp(tonumber(ar.amount) or 0.25, 0, 1))))
                if add > 0 then
                    local okPay = true
                    if ar.charge then
                        local cost = math.ceil(prod.base * orderCost) * add
                        okPay = cost <= 0 or bridge('Society.Remove', society, cost) == true
                    end
                    if okPay then setStock(pool, prod, st + add) end
                end
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- STARTUP & CLEANUP
-- ════════════════════════════════════════════════════════════════════════

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `nza_pharmacy_stock` (
        `pool` VARCHAR(48) NOT NULL,
        `item` VARCHAR(64) NOT NULL,
        `stock` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`pool`, `item`)
    ) DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `nza_pharmacy_sales` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `pool` VARCHAR(48) NOT NULL,
        `point` INT NOT NULL DEFAULT 0,
        `identifier` VARCHAR(80) NULL DEFAULT NULL,
        `name` VARCHAR(80) NULL DEFAULT NULL,
        `items` LONGTEXT NULL,
        `subtotal` INT UNSIGNED NOT NULL DEFAULT 0,
        `discount` INT UNSIGNED NOT NULL DEFAULT 0,
        `tax` INT UNSIGNED NOT NULL DEFAULT 0,
        `total` INT UNSIGNED NOT NULL DEFAULT 0,
        `method` VARCHAR(8) NULL DEFAULT NULL,
        `kind` VARCHAR(16) NOT NULL DEFAULT 'shop',
        `created` INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `pool_created` (`pool`, `created`)
    ) DEFAULT CHARSET=utf8mb4]],
}

CreateThread(function()
    if cfg().enabled == false then return end
    P.Catalogue()
    if hasDB() then
        for _, q in ipairs(SCHEMA) do dbQuery(q) end
        local rows = dbQuery('SELECT `pool`, `item`, `stock` FROM `nza_pharmacy_stock`') or {}
        for _, r in ipairs(rows) do
            stock[r.pool] = stock[r.pool] or {}
            stock[r.pool][r.item] = tonumber(r.stock) or 0
        end
        local keep = tonumber(cfg('staff').keepDays) or 30
        if keep > 0 then
            dbQuery('DELETE FROM `nza_pharmacy_sales` WHERE `created` < ?', { os.time() - keep * 86400 })
        end
    end
    dbReady = true
    -- clamp stored stock to the configured shelf size (owners may shrink shelves)
    for pool, t in pairs(stock) do
        for id, n in pairs(t) do
            local prod = byId[id]
            if prod and prod.stock and n > prod.stock then setStock(pool, prod, prod.stock) end
        end
    end
    local ar = cfg('stock').autoRestock or {}
    if cfg('stock').enabled ~= false and ar.enabled then
        local interval = math.max(1, tonumber(ar.interval) or 45) * 60000
        while true do
            Wait(interval)
            local ok, e = pcall(autoRestock)
            if not ok then NZA.Warn('pharmacy auto restock failed: ' .. tostring(e)) end
        end
    end
end)

-- sessions end when the player leaves or after 10 idle minutes
AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then sessions[src] = nil end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for src, s in pairs(sessions) do
            if now - s.at > 600000 or not Core.Online(src) then sessions[src] = nil end
        end
    end
end)
