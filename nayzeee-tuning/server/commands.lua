Admin = { free = {} }

function Admin.IsFree(src) return Admin.free[src] == true end

RegisterNetEvent('nayzeee-tuning:closed', function() Admin.free[source] = nil end)
AddEventHandler('playerDropped', function() Admin.free[source] = nil end)

local function reply(src, msg, kind)
    if src == 0 then print(msg) else Core.Notify(src, msg, kind) end
end

lib.addCommand(Config.Admin.FreeCommand, { help = L('cmd_admintune'), restricted = Config.Admin.Ace }, function(src)
    if src == 0 then return end
    Admin.free[src] = true
    TriggerClientEvent('nayzeee-tuning:openAdmin', src)
end)

lib.addCommand(Config.Admin.CodeCommand, {
    help = L('cmd_tunecode'), restricted = Config.Admin.Ace,
    params = {
        { name = 'code', type = 'string', help = '0 = random' },
        { name = 'shop', type = 'string', help = 'shop id or all' },
        { name = 'percent', type = 'number' },
        { name = 'uses', type = 'number' },
    },
}, function(src, args)
    if args.shop ~= 'all' and not Config.Shops[args.shop] then return reply(src, L('shop_unknown'), 'error') end
    local pct, uses = math.floor(args.percent or 0), math.floor(args.uses or 0)
    if pct < 1 or pct > 100 or uses < 1 then return reply(src, L('amount_invalid'), 'error') end
    local code = Business.CreateCode(args.shop, pct, uses, src == 0 and 'console' or Bridge.GetName(src), args.code ~= '0' and args.code or nil)
    reply(src, L('code_created', code), 'success')
    Core.Log('code', 'Admin discount code', { Code = code, Shop = args.shop, Percent = pct .. '%', Uses = uses }, src ~= 0 and src or nil)
end)

lib.addCommand(Config.Admin.DelCodeCommand, {
    help = L('cmd_deltunecode'), restricted = Config.Admin.Ace,
    params = { { name = 'code', type = 'string' } },
}, function(src, args)
    MySQL.update.await('DELETE FROM nz_tuning_codes WHERE code = ?', { args.code:upper() })
    reply(src, L('code_deleted', args.code:upper()), 'success')
end)

lib.addCommand(Config.Admin.ResetCommand, { help = L('cmd_resettune'), restricted = Config.Admin.Ace }, function(src)
    if src == 0 then return end
    local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
    if not veh or veh == 0 then return reply(src, L('no_vehicle'), 'error') end
    local plate = NZ.TrimPlate(GetVehicleNumberPlateText(veh))
    Vehicles.Save(plate, {})
    Vehicles.Push(veh, plate)
    reply(src, L('extras_reset', plate), 'success')
    Core.Log('admin', 'Custom tuning reset', { Plate = plate }, src)
end)

--------------------------------------------------------------------- exports

exports('GetShopBalance', function(shopId) return Core.ShopBalance(shopId) end)
exports('AddShopMoney', function(shopId, amount, note) Core.ShopAdd(shopId, amount, 'external', 'export', note) end)
exports('GetIllegalParts', function(plate, props) return NZ.IllegalParts(props or {}, Vehicles.Get(plate)) end)
exports('CreateDiscountCode', function(shopId, percent, uses, code) return Business.CreateCode(shopId, percent, uses, 'export', code) end)
exports('GetWear', function(plate) return NZ.Copy(Vehicles.Get(plate).wear or {}) end)
exports('SetWear', function(plate, wear)
    local veh = Vehicles.FindByPlate(plate)
    Vehicles.Update(plate, veh, function(d) d.wear = wear end)
end)
exports('GetMileage', function(plate) return Vehicles.Get(plate).km or 0 end)

-- /testsound <audio name>: hear an engine sound on the car you're in (only you, nothing saved)
lib.addCommand('testsound', { help = L('cmd_testsound'), restricted = Config.Admin.Ace, params = { { name = 'audio', type = 'string' } } }, function(src, args)
    if src == 0 then return end
    TriggerClientEvent('nayzeee-tuning:testSound', src, args.audio)
end)

-- /carryadjust [part id | hoist | jacks]: line up a carried prop in game and copy the attach line
lib.addCommand('carryadjust', { help = L('cmd_carryadjust'), restricted = Config.Admin.Ace, params = { { name = 'part', type = 'string', optional = true } } }, function(src, args)
    if src == 0 then return end
    TriggerClientEvent('nayzeee-tuning:carryAdjust', src, args.part)
end)
