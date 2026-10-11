local function rank(src, shopId)
    return {
        access  = Core.HasShopRank(src, shopId, 'access'),
        manager = Core.HasShopRank(src, shopId, 'manager'),
        boss    = Core.HasShopRank(src, shopId, 'boss'),
    }
end

local function randomCode(len)
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    local out = {}
    for i = 1, len do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end
Business = { RandomCode = randomCode }

local function gradesFor(job)
    local jobs = Bridge.GetJobs()
    local out = {}
    for lvl, g in pairs((jobs[job] or {}).grades or {}) do out[#out + 1] = { level = lvl, label = g.label } end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

--------------------------------------------------------------------- dashboard

lib.callback.register('nayzeee-tuning:business', function(src, shopId)
    local shop = Config.Shops[shopId]
    if not shop or not shop.job then return false end
    local r = rank(src, shopId)
    if not r.access then return false, L('no_permission') end
    local s = Core.Shops[shopId]

    local chartRows = MySQL.query.await('SELECT DATE_FORMAT(day, "%m/%d") AS d, revenue, jobs FROM nz_tuning_stats WHERE shop = ? AND day > CURDATE() - INTERVAL 14 DAY ORDER BY day', { shopId }) or {}
    local byDay = {}
    for _, row in ipairs(chartRows) do byDay[row.d] = row end
    local chart = {}
    for i = 13, 0, -1 do
        local d = os.date('%m/%d', os.time() - i * 86400)
        local row = byDay[d]
        chart[#chart + 1] = { day = d, revenue = row and row.revenue or 0, jobs = row and row.jobs or 0 }
    end
    local today, week, jobs7 = chart[#chart].revenue, 0, 0
    for i = #chart - 6, #chart do week = week + chart[i].revenue jobs7 = jobs7 + chart[i].jobs end

    local openOrders = MySQL.scalar.await("SELECT COUNT(*) FROM nz_tuning_orders WHERE shop = ? AND status IN ('open','accepted','working')", { shopId }) or 0
    local ann = MySQL.query.await('SELECT id, author, message, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_announcements WHERE shop = ? ORDER BY id DESC LIMIT 20', { shopId }) or {}
    local board = MySQL.query.await('SELECT identifier, name, installs, earned FROM nz_tuning_mechanics WHERE shop = ? ORDER BY installs DESC LIMIT 8', { shopId }) or {}
    for _, b in ipairs(board) do b.avatar, b.identifier = Avatars.Of(b.identifier), nil end

    local data = {
        shop = { id = shopId, label = shop.label }, rank = r, version = Config.Version,
        me = { name = Bridge.GetName(src), grade = Bridge.GetJob(src).grade },
        balance = Core.ShopBalance(shopId), margin = s.margin, commission = s.commission, labour = Core.LabourRate(shopId),
        marginRange = Config.Business.MarginRange, commissionRange = Config.Business.CommissionRange,
        labourRange = Config.Business.LabourRateRange,
        kpi = { today = today, week = week, jobs = jobs7, orders = openOrders, online = Core.MechanicsOnDuty(shopId) },
        chart = chart, announcements = ann, leaderboard = board,
        discounts = { enabled = Config.Discounts.Enabled, percentages = Config.Discounts.Percentages, uses = Config.Discounts.Uses },
        maxBonus = Config.Business.MaxBonus, annLength = Config.Business.AnnouncementLength,
        missions = Config.Missions.Enabled,
        upgradesEnabled = Config.ShopUpgrades.Enabled,
    }

    if r.manager then
        data.codes = MySQL.query.await('SELECT code, percent, uses, created_by FROM nz_tuning_codes WHERE shop = ? ORDER BY created_at DESC', { shopId }) or {}
        data.employees = Bridge.GetEmployees(shop.job)
        for _, e in ipairs(data.employees) do e.source, e.avatar = nil, Avatars.Of(e.identifier) end
        data.grades = gradesFor(shop.job)
    end
    if r.boss then
        data.tx = MySQL.query.await('SELECT kind, amount, actor, note, UNIX_TIMESTAMP(created_at) AS t FROM nz_tuning_tx WHERE shop = ? ORDER BY id DESC LIMIT 50', { shopId }) or {}
    end
    if Config.ShopUpgrades.Enabled then
        local ups = {}
        for key, u in pairs(Config.ShopUpgrades.List) do
            ups[#ups + 1] = { key = key, label = u.label, icon = u.icon, price = u.price, owned = s.upgrades[key] == true,
                unlocks = u.categories or u.items }
        end
        table.sort(ups, function(a, b) return a.price < b.price end)
        data.upgrades = ups
    end
    return true, data
end)

--------------------------------------------------------------------- announcements

lib.callback.register('nayzeee-tuning:announce', function(src, shopId, msg)
    if not Core.HasShopRank(src, shopId, 'manager') then return false, L('no_permission') end
    if type(msg) ~= 'string' then return false end
    msg = msg:gsub('^%s+', ''):gsub('%s+$', ''):sub(1, Config.Business.AnnouncementLength)
    if #msg < 2 then return false end
    MySQL.insert.await('INSERT INTO nz_tuning_announcements (shop, author, message) VALUES (?, ?, ?)', { shopId, Bridge.GetName(src), msg })
    for _, t in ipairs(Bridge.GetPlayersWithJob(Config.Shops[shopId].job, false)) do
        Core.Notify(t, L('announcement', msg), 'inform')
    end
    return true
end)

lib.callback.register('nayzeee-tuning:deleteAnnouncement', function(src, shopId, id)
    if not Core.HasShopRank(src, shopId, 'manager') then return false end
    MySQL.update.await('DELETE FROM nz_tuning_announcements WHERE id = ? AND shop = ?', { id, shopId })
    return true
end)

--------------------------------------------------------------------- employees

lib.callback.register('nayzeee-tuning:nearbyPlayers', function(src, shopId)
    if not Core.HasShopRank(src, shopId, 'manager') then return {} end
    local out, me = {}, GetEntityCoords(GetPlayerPed(src))
    for _, id in ipairs(GetPlayers()) do
        local t = tonumber(id)
        if t ~= src and #(GetEntityCoords(GetPlayerPed(t)) - me) < 10.0 then
            out[#out + 1] = { id = t, name = Bridge.GetName(t), job = Bridge.GetJob(t).label }
        end
    end
    return out
end)

lib.callback.register('nayzeee-tuning:hire', function(src, shopId, target)
    if not Core.HasShopRank(src, shopId, 'manager') then return false, L('no_permission') end
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false, L('player_gone') end
    if #(GetEntityCoords(GetPlayerPed(target)) - GetEntityCoords(GetPlayerPed(src))) > 10.0 then return false, L('player_gone') end
    -- "hiring" someone who already works here would reset them to grade 0
    if Bridge.GetJob(target).name == Config.Shops[shopId].job then return false, L('no_permission') end
    Bridge.SetJob(target, Config.Shops[shopId].job, 0)
    Core.Notify(target, L('hired', Config.Shops[shopId].label), 'success')
    Core.Log('hire', 'Employee hired', { Shop = Config.Shops[shopId].label, Employee = Bridge.GetName(target) }, src)
    return true
end)

local function targetEmployee(src, shopId, identifier)
    if identifier == Bridge.GetIdentifier(src) then return nil, L('not_yourself') end
    for _, e in ipairs(Bridge.GetEmployees(Config.Shops[shopId].job)) do
        if e.identifier == identifier then return e end
    end
    return nil, L('not_employee')
end

lib.callback.register('nayzeee-tuning:fire', function(src, shopId, identifier)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    local e, err = targetEmployee(src, shopId, identifier)
    if not e then return false, err end
    if (e.grade or 0) > Bridge.GetJob(src).grade then return false, L('no_permission') end
    if e.source then Bridge.SetJob(e.source, 'unemployed', 0) Core.Notify(e.source, L('fired', Config.Shops[shopId].label), 'error')
    else Bridge.SetJobOffline(identifier, 'unemployed', 0) end
    Core.Log('fire', 'Employee fired', { Shop = Config.Shops[shopId].label, Employee = e.name }, src)
    return true
end)

lib.callback.register('nayzeee-tuning:setGrade', function(src, shopId, identifier, grade)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    grade = NZ.Int(grade)
    local myGrade = Bridge.GetJob(src).grade
    if not grade or grade < 0 or grade > myGrade then return false, L('grade_too_high') end
    local e, err = targetEmployee(src, shopId, identifier)
    if not e then return false, err end
    if (e.grade or 0) > myGrade then return false, L('no_permission') end
    local job = Config.Shops[shopId].job
    if e.source then Bridge.SetJob(e.source, job, grade) Core.Notify(e.source, L('grade_changed'), 'inform')
    else Bridge.SetJobOffline(identifier, job, grade) end
    Core.Log('grade', 'Grade changed', { Shop = Config.Shops[shopId].label, Employee = e.name, Grade = grade }, src)
    return true
end)

lib.callback.register('nayzeee-tuning:bonus', function(src, shopId, identifier, amount)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    amount = NZ.Int(amount, 0)
    if amount <= 0 or amount > Config.Business.MaxBonus then return false, L('amount_invalid') end
    local e, err = targetEmployee(src, shopId, identifier)
    if not e then return false, err end
    if not Core.ShopTake(shopId, amount, 'bonus', Bridge.GetName(src), 'Bonus: ' .. e.name) then return false, L('shop_no_money') end
    Bridge.AddBankOffline(identifier, amount)
    if e.source then Core.Notify(e.source, L('bonus_received', amount), 'success') end
    Core.Log('bonus', 'Bonus paid', { Shop = Config.Shops[shopId].label, Employee = e.name, Amount = '$' .. amount }, src)
    return true
end)

--------------------------------------------------------------------- finance

lib.callback.register('nayzeee-tuning:withdraw', function(src, shopId, amount)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    amount = NZ.Int(amount, 0)
    if amount <= 0 then return false, L('amount_invalid') end
    if not Core.ShopTake(shopId, amount, 'withdraw', Bridge.GetName(src), nil) then return false, L('shop_no_money') end
    Bridge.AddMoney(src, 'cash', amount, 'Shop withdraw')
    Core.Log('withdraw', 'Shop withdraw', { Shop = Config.Shops[shopId].label, Amount = '$' .. amount }, src)
    return true
end)

lib.callback.register('nayzeee-tuning:deposit', function(src, shopId, amount)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    amount = NZ.Int(amount, 0)
    if amount <= 0 then return false, L('amount_invalid') end
    if not Bridge.RemoveMoney(src, 'cash', amount, 'Shop deposit') then return false, L('not_enough_money') end
    Core.ShopAdd(shopId, amount, 'deposit', Bridge.GetName(src), nil)
    Core.Log('deposit', 'Shop deposit', { Shop = Config.Shops[shopId].label, Amount = '$' .. amount }, src)
    return true
end)

lib.callback.register('nayzeee-tuning:setRates', function(src, shopId, margin, commission, labour)
    if not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    local mr, cr, lr = Config.Business.MarginRange, Config.Business.CommissionRange, Config.Business.LabourRateRange
    margin, commission = NZ.Int(margin, 0), NZ.Int(commission, 0)
    labour = NZ.Int(labour, Core.LabourRate(shopId))
    if margin < mr[1] or margin > mr[2] or commission < cr[1] or commission > cr[2] then return false, L('amount_invalid') end
    if labour < lr[1] or labour > lr[2] then return false, L('amount_invalid') end
    local s = Core.Shops[shopId]
    s.margin, s.commission, s.labour = margin, commission, labour
    MySQL.update.await('UPDATE nz_tuning_shops SET margin = ?, commission = ?, labour = ? WHERE id = ?', { margin, commission, labour, shopId })
    return true
end)

--------------------------------------------------------------------- discount codes

function Business.CreateCode(shopId, percent, uses, by, custom)
    local code = custom and custom:upper():gsub('[^A-Z0-9%-]', ''):sub(1, 24) or nil
    if not code or #code < 3 then code = randomCode(Config.Discounts.CodeLength) end
    MySQL.insert.await('INSERT INTO nz_tuning_codes (code, shop, percent, uses, created_by) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE shop = VALUES(shop), percent = VALUES(percent), uses = VALUES(uses)',
        { code, shopId, percent, uses, by })
    return code
end

lib.callback.register('nayzeee-tuning:createCode', function(src, shopId, percent, uses)
    if not Config.Discounts.Enabled or not Core.HasShopRank(src, shopId, 'manager') then return false, L('no_permission') end
    percent, uses = NZ.Num(percent), NZ.Num(uses)
    if not NZ.InList(Config.Discounts.Percentages, percent) or not NZ.InList(Config.Discounts.Uses, uses) then return false, L('amount_invalid') end
    local active = MySQL.scalar.await('SELECT COUNT(*) FROM nz_tuning_codes WHERE shop = ? AND uses > 0', { shopId }) or 0
    if active >= Config.Discounts.MaxActivePerShop then return false, L('too_many_codes') end
    local code = Business.CreateCode(shopId, percent, uses, Bridge.GetName(src))
    Core.Log('code', 'Discount code created', { Shop = Config.Shops[shopId].label, Code = code, Percent = percent .. '%', Uses = uses }, src)
    return true, code
end)

lib.callback.register('nayzeee-tuning:deleteCode', function(src, shopId, code)
    if not Core.HasShopRank(src, shopId, 'manager') then return false end
    MySQL.update.await('DELETE FROM nz_tuning_codes WHERE code = ? AND shop = ?', { code, shopId })
    return true
end)

--------------------------------------------------------------------- workshop upgrades

lib.callback.register('nayzeee-tuning:buyUpgrade', function(src, shopId, key)
    if not Config.ShopUpgrades.Enabled or not Core.HasShopRank(src, shopId, 'boss') then return false, L('no_permission') end
    local up = Config.ShopUpgrades.List[key]
    local s = Core.Shops[shopId]
    if not up or s.upgrades[key] then return false end
    if not Core.ShopTake(shopId, up.price, 'upgrade', Bridge.GetName(src), up.label) then return false, L('shop_no_money') end
    s.upgrades[key] = true
    MySQL.update.await('UPDATE nz_tuning_shops SET upgrades = ? WHERE id = ?', { json.encode(s.upgrades), shopId })
    Core.Log('upgrade', 'Workshop upgrade bought', { Shop = Config.Shops[shopId].label, Upgrade = up.label, Price = '$' .. up.price }, src)
    return true
end)
