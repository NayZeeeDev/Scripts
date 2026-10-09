--[[
    Crafting at a table, and buying materials from the supplier.

    A craft runs in two calls: craftStart checks everything and hands the
    client the stages; craftFinish (after the stages have played out) checks
    again, takes the materials and gives the pair. Nothing is taken if the
    player cancels or leaves part way.
]]

local C = Config.Crafting
local sessions = {}     -- [src] = { token, tableId, shoeId, size, real, stages, started, minTime }

local function fail(src, text)
    if text then Bridge.Notify(src, text, 'error') end
    return false
end

local function hasMaterials(src, recipe)
    for name, count in pairs(recipe) do
        if Inv.Count(src, name) < count then return false, name end
    end
    return true
end

--- Takes every material or none
local function takeMaterials(src, recipe)
    local taken = {}
    for name, count in pairs(recipe) do
        if not Inv.Remove(src, name, count) then
            for n, c in pairs(taken) do Inv.Add(src, n, c) end
            return false
        end
        taken[name] = count
    end
    return true, taken
end

local function fakeQuality(level, passed, failed)
    local q = C.fakeQuality
    local v = q.base + level * q.perLevel + passed * q.pass - failed * q.fail + math.random(-q.spread, q.spread)
    return math.floor(math.max(q.min, math.min(q.max, v)))
end

local function release(src)
    local s = sessions[src]
    if not s then return end
    sessions[src] = nil
    local t = Tables.Get(s.tableId)
    if t and t.user == src then t.user = nil end
end

lib.callback.register('nayzeee-sneakers:craftData', function(src)
    local xp = XP.Get(src)
    local level, from, to = Shared.LevelFor(xp)
    local have = {}
    for name in pairs(Config.Materials) do have[name] = Inv.Count(src, name) end
    return { xp = xp, level = level, from = from, to = to, have = have }
end)

lib.callback.register('nayzeee-sneakers:craftStart', function(src, tableId, req)
    local t = Tables.Get(tableId)
    if not t or type(req) ~= 'table' or not Tables.Near(src, t) then return false end
    if not Tables.CanUse(src, t) then return fail(src, Config.Text.notYourTable) end
    local user = Tables.InUseBy(t)
    if user and user ~= src then return fail(src, Config.Text.tableBusy) end

    local m = Config.ShoeModels[req.model]
    local shoeId = ('%s_%s'):format(tostring(req.model), tostring(req.letter))
    if not m or not Config.Shoes[shoeId] then return false end
    local size = tostring(req.size)
    local okSize = false
    for _, s in ipairs(Config.Sizes[m.gender == 'female' and 'female' or 'male']) do
        if s == size then okSize = true end
    end
    if not okSize then return false end

    local real = req.real == true
    local level = XP.Level(src)
    if level < Shared.ModelLevel(req.model) then return fail(src, Config.Text.levelTooLow:format(Shared.ModelLevel(req.model))) end
    if real and level < C.realLevel then return fail(src, Config.Text.levelTooLow:format(C.realLevel)) end

    local recipe = Shared.Recipe(req.model, real)
    local ok, missing = hasMaterials(src, recipe)
    if not ok then return fail(src, Config.Text.missingMaterial:format(Shared.ItemLabel(missing))) end
    if not Inv.CanCarry(src, Config.Items.shoes, 1) then return fail(src, Config.Text.noSpace) end

    release(src)
    local stages = Shared.Stages(req.model, level)
    local total = 0
    for _, s in ipairs(stages) do total = total + s.time end
    local token = ('%d-%d'):format(src, math.random(100000, 999999))
    sessions[src] = {
        token = token, tableId = tableId, shoeId = shoeId, model = req.model, size = size, real = real,
        recipe = recipe, stages = stages, started = GetGameTimer(), minTime = total,
    }
    t.user = src
    return true, token, stages
end)

lib.callback.register('nayzeee-sneakers:craftCancel', function(src)
    release(src)
    return true
end)

lib.callback.register('nayzeee-sneakers:craftFinish', function(src, token, results)
    local s = sessions[src]
    if not s or s.token ~= token then return false end
    release(src)

    local t = Tables.Get(s.tableId)
    if not t or not Tables.Near(src, t, 3.0) then return false end
    if GetGameTimer() - s.started < s.minTime * 0.85 then return false end

    local passed, failed = 0, 0
    results = type(results) == 'table' and results or {}
    for i, st in ipairs(s.stages) do
        if st.check then
            if results[i] == true then passed = passed + 1 else failed = failed + 1 end
        end
    end

    local ok = takeMaterials(src, s.recipe)
    if not ok then return fail(src, Config.Text.materialsGone) end

    local level = XP.Level(src)
    local meta = Items.NewPair(s.shoeId, s.size, s.real, 'DS')
    meta.quality = s.real and 100 or fakeQuality(level, passed, failed)
    if not Items.GivePair(src, meta, false) then
        for name, count in pairs(s.recipe) do Inv.Add(src, name, count) end
        return fail(src, Config.Text.noSpace)
    end

    local box = Config.ShoeModels[s.model].box
    local gain = (C.xp[box] or C.xp.shoe) * (s.real and C.xp.realBonus or 1)
    if failed == 0 and passed > 0 then gain = gain + C.xp.perfectBonus end
    XP.Add(src, gain)
    Stats.Add(src, { made = 1 })

    return true, {
        name = Shared.ShoeName(meta),
        real = s.real,
        quality = meta.quality,
        passed = passed,
        checks = passed + failed,
    }
end)

AddEventHandler('playerDropped', function()
    release(source)
end)

--------------------------------------------------------------------------------
-- Supplier
--------------------------------------------------------------------------------

local S = Config.Supplier

local function nearSupplier(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - S.coords.xyz) < 6.0
end

lib.callback.register('nayzeee-sneakers:supplierData', function(src)
    return { level = XP.Level(src), money = Bridge.GetMoney(src, S.account) }
end)

lib.callback.register('nayzeee-sneakers:buy', function(src, cart)
    if not S.enabled or type(cart) ~= 'table' or not nearSupplier(src) then return false end
    local level = XP.Level(src)
    local goods = Shared.SupplierGoods()
    local total, lines = 0, {}
    for name, qty in pairs(cart) do
        local m = goods[name]
        qty = math.floor(tonumber(qty) or 0)
        if m and qty > 0 then
            if qty > S.maxPerItem then return false end
            if level < (m.level or 1) then return fail(src, Config.Text.levelTooLow:format(m.level)) end
            if not Inv.CanCarry(src, name, qty) then return fail(src, Config.Text.noSpace) end
            total = total + m.price * qty
            lines[#lines + 1] = { name = name, qty = qty }
        end
    end
    if #lines == 0 then return false end
    if not Bridge.RemoveMoney(src, S.account, total, 'nayzeee-sneakers supplies') then
        return fail(src, Config.Text.noMoney)
    end
    local refund = 0
    for _, l in ipairs(lines) do
        if not Inv.Add(src, l.name, l.qty) then refund = refund + goods[l.name].price * l.qty end
    end
    if refund > 0 then
        Bridge.AddMoney(src, S.account, refund, 'nayzeee-sneakers refund')
        Bridge.Notify(src, Config.Text.noSpace, 'error')
    end
    return true, total - refund, Bridge.GetMoney(src, S.account)
end)
