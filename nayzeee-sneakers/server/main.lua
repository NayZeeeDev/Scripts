-- Client says its character has loaded: hand back anything left in boxes while offline
RegisterNetEvent('nayzeee-sneakers:server:loaded', function()
    local src = source
    SetTimeout(2000, function() Pending.Deliver(src) end)
end)

local function shoeList()
    local ids = {}
    for id, m in pairs(Config.ShoeModels) do
        local letters = {}
        for l in pairs(m.colourways) do letters[#letters + 1] = l end
        table.sort(letters)
        ids[#ids + 1] = ('%s_[%s-%s]'):format(id, letters[1], letters[#letters])
    end
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

-- /giveshoebox [id] [amount] [shoe|heel|boot]
RegisterCommand(Config.Commands.giveBox, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local amount = math.max(1, math.min(50, tonumber(args[2]) or 1))
    local boxType = Config.BoxTypes[args[3] or 'shoe'] and (args[3] or 'shoe') or 'shoe'
    local ok = Inv.Add(target, Config.BoxTypes[boxType].item, amount)
    local msg = ok and ('Gave %d empty %s(es) to %d'):format(amount, Config.BoxTypes[boxType].label:lower(), target) or 'Could not give the item'
    if src == 0 then print(msg) else Bridge.Notify(src, msg, ok and 'success' or 'error') end
end, false)

-- /givematerials [id] [pairs]: enough of every material for that many pairs of anything (real or fake)
RegisterCommand(Config.Commands.materials, function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    local pairs_ = math.max(1, math.min(20, tonumber(args[2]) or 1))
    local need = {}
    for modelId in pairs(Config.ShoeModels) do
        for name, count in pairs(Shared.Recipe(modelId, true)) do
            need[name] = math.max(need[name] or 0, count)
        end
    end
    local given = 0
    for name, count in pairs(need) do
        if Inv.Add(target, name, count * pairs_) then given = given + 1 end
    end
    local msg = ('Gave %d kinds of materials (enough for %d pair%s) to %d'):format(given, pairs_, pairs_ == 1 and '' or 's', target)
    if src == 0 then print(msg) else Bridge.Notify(src, msg, given > 0 and 'success' or 'error') end
end, false)

-- Shoe models with no clothing id yet can't be worn; say so once on start
CreateThread(function()
    local missing = {}
    for id, m in pairs(Config.ShoeModels) do
        if not m.drawable then missing[#missing + 1] = id end
    end
    if #missing > 0 then
        table.sort(missing)
        print(('^3[nayzeee-sneakers]^7 no clothing drawable set for: %s (config/shoes.lua) - they can be boxed and inspected but not worn yet'):format(table.concat(missing, ', ')))
    end
end)
