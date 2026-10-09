Inv = {}

local inv = Config.Inventory
if inv == 'auto' then
    if GetResourceState('ox_inventory') == 'started' then inv = 'ox'
    elseif GetResourceState('qb-inventory') == 'started'
        or GetResourceState('ps-inventory') == 'started'
        or GetResourceState('lj-inventory') == 'started' then inv = 'qb'
    else inv = 'custom' end
end
Inv.Type = inv

local function item(name, slot, metadata)
    return { name = name, slot = slot, metadata = metadata or {} }
end

if inv == 'ox' then
    local ox = exports.ox_inventory
    local usable = {}

    function Inv.Add(src, name, count, metadata) return (ox:AddItem(src, name, count or 1, metadata)) == true end
    function Inv.Remove(src, name, count, slot) return (ox:RemoveItem(src, name, count or 1, nil, slot)) == true end
    function Inv.GetSlot(src, slot)
        local it = ox:GetSlot(src, slot)
        return it and item(it.name, it.slot, it.metadata)
    end
    function Inv.List(src, name)
        local out = {}
        for _, it in pairs(ox:Search(src, 'slots', name) or {}) do out[#out + 1] = item(it.name, it.slot, it.metadata) end
        return out
    end
    function Inv.CanCarry(src, name, count, metadata) return ox:CanCarryItem(src, name, count or 1, metadata) and true or false end
    function Inv.Count(src, name) return ox:Search(src, 'count', name) or 0 end
    function Inv.RegisterUsable(name, cb) usable[name] = cb end

    -- Items point here from install/ox_items.lua: server = { export = 'nayzeee-sneakers.useItem' }
    exports('useItem', function(event, itemData, inventory, slot)
        if event ~= 'usingItem' then return end
        local src = inventory.id
        local slotNum = type(slot) == 'table' and slot.slot or slot
        local cb = usable[itemData.name]
        local it = slotNum and Inv.GetSlot(src, slotNum)
        if cb and it then cb(src, it) end
    end)

elseif inv == 'qb' then
    local function player(src) return Bridge.GetQBPlayer(src) end
    local function itemBox(src, name, kind, count)
        local shared = Bridge.QBSharedItem(name)
        if shared then TriggerClientEvent('qb-inventory:client:ItemBox', src, shared, kind, count or 1) end
    end

    function Inv.Add(src, name, count, metadata)
        local p = player(src)
        if p and p.Functions.AddItem(name, count or 1, false, metadata) then
            itemBox(src, name, 'add', count)
            return true
        end
        return false
    end
    function Inv.Remove(src, name, count, slot)
        local p = player(src)
        if p and p.Functions.RemoveItem(name, count or 1, slot) then
            itemBox(src, name, 'remove', count)
            return true
        end
        return false
    end
    function Inv.GetSlot(src, slot)
        local p = player(src)
        local it = p and p.Functions.GetItemBySlot(slot)
        return it and item(it.name, it.slot, it.info)
    end
    function Inv.List(src, name)
        local out, p = {}, player(src)
        for _, it in pairs(p and p.PlayerData.items or {}) do
            if it and it.name == name then out[#out + 1] = item(it.name, it.slot, it.info) end
        end
        return out
    end
    function Inv.CanCarry(src, name, count)
        local ok, res = pcall(function() return exports['qb-inventory']:CanAddItem(src, name, count or 1) end)
        if ok and res ~= nil then return res and true or false end
        return true
    end
    function Inv.Count(src, name)
        local n, p = 0, player(src)
        for _, it in pairs(p and p.PlayerData.items or {}) do
            if it and it.name == name then n = n + (it.amount or it.count or 1) end
        end
        return n
    end
    function Inv.RegisterUsable(name, cb) Bridge.RegisterUsable(name, cb) end

else
    Inv.Add = CustomInventory.Add
    Inv.Remove = CustomInventory.Remove
    Inv.GetSlot = CustomInventory.GetSlot
    Inv.List = CustomInventory.List
    Inv.CanCarry = CustomInventory.CanCarry
    Inv.Count = CustomInventory.Count
    Inv.RegisterUsable = CustomInventory.RegisterUsable
end

--- First slot holding `name`, or nil
function Inv.Find(src, name)
    return Inv.List(src, name)[1]
end

print(('^5[nayzeee-sneakers]^7 inventory: %s'):format(inv))
