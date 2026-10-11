Pricing = {}

function Pricing.FindCode(code, shopId)
    if not Config.Discounts.Enabled or type(code) ~= 'string' or code == '' then return nil end
    code = code:upper():gsub('[^A-Z0-9%-]', '')
    local row = MySQL.single.await('SELECT code, shop, percent, uses FROM nz_tuning_codes WHERE code = ? AND uses > 0', { code })
    if not row then return nil end
    if row.shop ~= 'all' and row.shop ~= shopId then return nil end
    return row
end

-- reserves one use before the charge; false when another checkout used the last one first
function Pricing.UseCode(code)
    return (MySQL.update.await('UPDATE nz_tuning_codes SET uses = uses - 1 WHERE code = ? AND uses > 0', { code }) or 0) > 0
end

-- gives the use back when the charge failed
function Pricing.ReturnCode(code)
    MySQL.update('UPDATE nz_tuning_codes SET uses = uses + 1 WHERE code = ?', { code })
end

-- after a successful charge
function Pricing.PurgeCode(code)
    MySQL.update('DELETE FROM nz_tuning_codes WHERE code = ? AND uses <= 0', { code })
end

-- reserve the code, charge, and give the code back if the charge fails
function Pricing.Pay(src, method, res, reason)
    if res.code and not Pricing.UseCode(res.code) then return false, nil, L('code_invalid') end
    local paid, paidWith = Core.Charge(src, method, res.totals.total, reason)
    if not res.code then return paid, paidWith end
    if paid then Pricing.PurgeCode(res.code) else Pricing.ReturnCode(res.code) end
    return paid, paidWith
end

--[[
    items : { { id = 'mod_11', value = 3 }, ... }
    opts  : { class = number, code = string, free = bool }
    -> ok, result | false, error
]]
function Pricing.Cart(shopId, veh, items, opts)
    opts = opts or {}
    if type(items) ~= 'table' or #items == 0 then return false, L('cart_empty') end
    if #items > 80 then return false, L('cart_invalid') end

    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    local hash = GetEntityModel(veh)
    local vehPrice, modelName = Core.VehiclePrice(hash)
    local data = Vehicles.Get(plate)
    local ctx = { extras = data, wear = data.wear }
    local unlocked = Core.Unlocked(shopId)
    local class = tonumber(opts.class)

    local seen, lines = {}, {}
    for i = #items, 1, -1 do                 -- last value of an item wins
        local it = items[i]
        if type(it) == 'table' and type(it.id) == 'string' and not seen[it.id] then
            seen[it.id] = true
            local part = Config.Parts[it.id]
            if not part then return false, L('cart_invalid') end
            if not NZ.Validate(it.id, it.value) then return false, L('cart_invalid_item', part.label) end
            if not opts.free and not NZ.ShopAllows(shopId, it.id, class, unlocked) then return false, L('cart_not_here', part.label) end
            if part.kind == 'nitrous' and it.value == 'refill' and not data.nitrous then return false, L('no_nitrous') end
            if part.kind == 'swap' and it.value then
                local allowed = NZ.SwapsFor(modelName, class)
                if not NZ.InList(allowed, it.value) then return false, L('cart_not_here', part.label) end
            end
            local price = NZ.ItemPrice(it.id, it.value, vehPrice, ctx)
            if not price then return false, L('cart_invalid_item', part.label) end
            if opts.free then price = 0 end
            table.insert(lines, 1, { id = it.id, value = it.value, label = part.label, price = price })
        end
    end

    local code = not opts.free and Pricing.FindCode(opts.code, shopId) or nil
    local margin = Config.Shops[shopId] and Config.Shops[shopId].job and (Core.Shops[shopId] or {}).margin or 0
    local surcharge = 0
    if opts.mode == 'self' and Config.Shops[shopId] and Config.Shops[shopId].mode ~= 'self' and Core.MechanicsOnDuty(shopId) > 0 then
        surcharge = Config.Business.SelfServiceSurcharge or 0
    end
    local labour = Config.Shops[shopId] and Config.Shops[shopId].job and Core.LabourRate(shopId) or Config.Economy.LaborPerItem
    local totals = opts.free and { subtotal = 0, labour = 0, discount = 0, tax = 0, total = 0 }
        or NZ.Totals(lines, code and code.percent or 0, margin, { labour = labour, surcharge = surcharge })

    -- inventory parts needed for these lines
    local required = {}
    for _, l in ipairs(lines) do
        for _, item in ipairs(NZ.RequiredItems(l.id, l.value, data.wear)) do required[item] = (required[item] or 0) + 1 end
    end

    return true, {
        lines = lines, totals = totals, plate = plate, model = modelName or tostring(hash),
        vehPrice = vehPrice, code = code and code.code, codePct = code and code.percent, required = required,
    }
end

-- UI asks for the numbers it needs to price things locally
lib.callback.register('nayzeee-tuning:quoteCart', function(src, shopId, netId, items, class, code, mode)
    if not Core.Throttle(src, 'quote', 250) then return false end
    local veh = Core.VehicleFromNet(netId)
    if not veh or not Config.Shops[shopId] then return false end
    local ok, res = Pricing.Cart(shopId, veh, items, { class = class, code = code, mode = mode, free = Admin and Admin.IsFree(src) })
    if not ok then return false, res end
    return true, { lines = res.lines, totals = res.totals, code = res.code, codePct = res.codePct }
end)

lib.callback.register('nayzeee-tuning:checkCode', function(src, shopId, code)
    if not Core.Throttle(src, 'code', 800) then return false end
    local row = Pricing.FindCode(code, shopId)
    if not row then return false, L('code_invalid') end
    return true, { code = row.code, percent = row.percent }
end)
