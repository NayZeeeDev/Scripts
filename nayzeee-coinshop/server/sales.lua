if not NAYZEEE_LOCK_OK then return end

--[[
    Scheduled sales: X% off every package in a scope (all packages or one category) between a start and an end time.
    Catalog.Price picks the cheapest of a package's own sale price and the biggest live sale.
]]

Sales = { list = {} }

local ADMIN = { admin = true }

function Sales.Load()
    local rows = MySQL.query.await([[SELECT id, name, percent, scope, enabled, UNIX_TIMESTAMP(starts_at) AS starts, UNIX_TIMESTAMP(ends_at) AS ends
        FROM nayzeee_coinshop_sales ORDER BY starts_at ASC, id ASC]]) or {}
    for _, s in ipairs(rows) do s.enabled = s.enabled == 1 or s.enabled == true end
    Sales.list = rows
end

local function category(id)
    for _, c in ipairs(Catalog.categories) do if c.id == id then return c end end
end

local function inScope(s, it)
    if s.scope == 'all' then return true end
    local c = category(s.scope:match('^cat:(.+)$') or '')
    if not c then return false end
    if c.type and c.type ~= '' then return it.category == c.type end
    return it.customCategory == c.id
end

local function live(s, now) return s.enabled and s.starts and s.ends and s.starts <= now and s.ends > now end

-- Biggest live sale for a package: percent, endsAt, name
function Sales.Best(it, now)
    local best
    for _, s in ipairs(Sales.list) do
        if live(s, now) and inScope(s, it) and (not best or s.percent > best.percent) then best = s end
    end
    if best then return best.percent, best.ends, best.name end
end

function Sales.ScopeName(scope)
    if scope == 'all' then return T('SALE_ALL') end
    local c = category(scope:match('^cat:(.+)$') or '')
    return c and c.name or scope
end

-- Live sales + sales starting within 7 days (players), or every sale (admins)
function Sales.Public(admin)
    local out, now = {}, os.time()
    for _, s in ipairs(Sales.list) do
        local isLive = live(s, now)
        local soon = s.enabled and s.starts and s.starts > now and s.starts - now < 7 * 86400
        if admin or isLive or soon then
            local count
            if admin then
                count = 0
                for _, it in ipairs(Catalog.items) do if inScope(s, it) then count = count + 1 end end
            end
            out[#out + 1] = {
                id = s.id, name = s.name, percent = s.percent, scope = s.scope, scopeName = Sales.ScopeName(s.scope), enabled = s.enabled,
                live = isLive, startsIn = math.max(0, (s.starts or now) - now), endsIn = math.max(0, (s.ends or now) - now),
                starts = s.starts, ends = s.ends, packages = count,
            }
        end
    end
    return out
end

-- When a sale (or a package's own sale) starts or ends, open shops reload their prices by themselves
CreateThread(function()
    local last
    while true do
        Wait(15000)
        if DB.ready then
            local ids = {}
            for _, it in ipairs(Catalog.items) do
                local _, sale = Catalog.Price(it)
                if sale then ids[#ids + 1] = it.id end
            end
            local key = table.concat(ids, ',')
            if last and key ~= last then
                for src in pairs(Core.Open) do Push(src, 'catalog', true) end
            end
            last = key
        end
    end
end)

-- ── admin ───────────────────────────────────────────────────────────────
Handle('admin:sales', function() return Sales.Public(true) end, ADMIN)

Handle('admin:sale:save', function(src, _, d)
    local name = NZC.Trim(d.name):sub(1, 100)
    if name == '' then return nil, 'ERR_NAME_REQUIRED' end
    local max = math.max(1, math.min(99, Config.Sales.MaxPercent or 90))
    local percent = NZC.Int(d.percent, 0, 100, 0)
    if percent < 1 or percent > max then return nil, 'ERR_SALE_PERCENT', { max } end
    local scope = NZC.Trim(d.scope)
    if scope ~= 'all' and not category(scope:match('^cat:(.+)$') or '') then return nil, 'ERR_SALE_SCOPE' end
    local starts, ends, now = math.floor(tonumber(d.starts) or 0), math.floor(tonumber(d.ends) or 0), os.time()
    if starts <= 0 then starts = now end
    if ends <= starts or ends <= now or ends - starts > 366 * 86400 then return nil, 'ERR_SALE_TIME' end
    local enabled = d.enabled == false and 0 or 1
    local id = tonumber(d.id)
    if id then
        local n = MySQL.update.await([[UPDATE nayzeee_coinshop_sales SET name = ?, percent = ?, scope = ?, starts_at = FROM_UNIXTIME(?), ends_at = FROM_UNIXTIME(?), enabled = ?
            WHERE id = ?]], { name, percent, scope, starts, ends, enabled, id })
        if n ~= 1 then return nil, 'ERR_NOT_FOUND' end
    else
        id = MySQL.insert.await([[INSERT INTO nayzeee_coinshop_sales (name, percent, scope, starts_at, ends_at, enabled)
            VALUES (?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?)]], { name, percent, scope, starts, ends, enabled })
    end
    MySQL.update('DELETE FROM nayzeee_coinshop_sales WHERE ends_at < NOW() - INTERVAL 30 DAY')
    Catalog.Changed()
    AdminLog(src, d.id and T('LOG_SALE_EDITED') or T('LOG_SALE_CREATED'), {
        { 'Sale', ('%s (#%s)'):format(name, id) }, { 'Discount', percent .. '%' }, { 'Scope', Sales.ScopeName(scope) },
        { 'Runs', ('<t:%d:f> → <t:%d:f>'):format(starts, ends), false },
    })
    return { id = id }
end, ADMIN)

Handle('admin:sale:toggle', function(src, _, d)
    local n = MySQL.update.await('UPDATE nayzeee_coinshop_sales SET enabled = 1 - enabled WHERE id = ?', { tonumber(d.id) or 0 })
    if n ~= 1 then return nil, 'ERR_NOT_FOUND' end
    Catalog.Changed()
    AdminLog(src, T('LOG_SALE_EDITED'), { { 'Sale', '#' .. tostring(d.id) }, { 'Toggled', 'enabled' } })
    return true
end, ADMIN)

Handle('admin:sale:delete', function(src, _, d)
    MySQL.update.await('DELETE FROM nayzeee_coinshop_sales WHERE id = ?', { tonumber(d.id) or 0 })
    Catalog.Changed()
    AdminLog(src, T('LOG_SALE_DELETED'), { { 'Sale', '#' .. tostring(d.id) } })
    return true
end, ADMIN)
