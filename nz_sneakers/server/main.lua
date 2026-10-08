-- Client says its character has loaded: hand back anything left in boxes while offline
RegisterNetEvent('nz_sneakers:server:loaded', function()
    local src = source
    SetTimeout(2000, function() Pending.Deliver(src) end)
end)

local function shoeList()
    local ids = {}
    for id in pairs(Config.Shoes) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ', ')
end

-- /givesneakers [id] [shoe] [size] [fake 0/1] [boxed 0/1]
RegisterCommand(Config.Commands.give, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local shoeId = args[2]
    if not shoeId or not Config.Shoes[shoeId] then
        local msg = 'Usage: /' .. Config.Commands.give .. ' [id] [shoe] [size] [fake 0/1] [boxed 0/1]  shoes: ' .. shoeList()
        if src == 0 then print(msg) else Bridge.Notify(src, msg, 'inform') end
        return
    end
    local meta = Items.NewPair(shoeId, args[3], args[4] ~= '1')
    local ok = Items.GivePair(target, meta, args[5] == '1')
    local msg = ok and ('Gave %s (US %s, %s) to %d'):format(Shared.ShoeName(meta), meta.size, meta.real and 'real' or 'fake', target)
        or 'Could not give the item (inventory full?)'
    if src == 0 then print(msg) else Bridge.Notify(src, msg, ok and 'success' or 'error') end
end, false)

-- /giveshoebox [id] [amount]
RegisterCommand(Config.Commands.giveBox, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local amount = math.max(1, math.min(50, tonumber(args[2]) or 1))
    local ok = Inv.Add(target, Config.Items.emptyBox, amount)
    local msg = ok and ('Gave %d empty box(es) to %d'):format(amount, target) or 'Could not give the item'
    if src == 0 then print(msg) else Bridge.Notify(src, msg, ok and 'success' or 'error') end
end, false)

-- Shoes with no clothing id yet can't be worn; say so once on start
CreateThread(function()
    local missing = {}
    for id, shoe in pairs(Config.Shoes) do
        if not Shared.ClothingFor(shoe, shoe.gender == 'female' and 'female' or 'male') then missing[#missing + 1] = id end
    end
    if #missing > 0 then
        table.sort(missing)
        print(('^3[nz_sneakers]^7 no clothing drawable set for: %s (config/shoes.lua) - they can be boxed and inspected but not worn yet'):format(table.concat(missing, ', ')))
    end
end)
