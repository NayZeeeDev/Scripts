--[[ Inventory bridge (server). Falls back to framework inventory functions. ]]

Inv = {}

local function detect()
    if Config.Inventory ~= 'auto' then return Config.Inventory end
    if GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if GetResourceState('qs-inventory') == 'started' then return 'qs' end
    if GetResourceState('codem-inventory') == 'started' then return 'codem' end
    if GetResourceState('qb-inventory') == 'started' or GetResourceState('ps-inventory') == 'started'
        or GetResourceState('lj-inventory') == 'started' then return 'qb' end
    return 'framework'
end

Inv.name = detect()

local qbInv = (GetResourceState('ps-inventory') == 'started' and 'ps-inventory')
    or (GetResourceState('lj-inventory') == 'started' and 'lj-inventory')
    or 'qb-inventory'

function Inv.count(src, name)
    if Inv.name == 'ox' then
        return exports.ox_inventory:GetItemCount(src, name) or 0
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:GetItemTotalAmount(src, name) or 0
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:GetItemsTotalAmount(src, name) or 0
    end
    local p = FW.getPlayer(src)
    if not p then return 0 end
    if FW.name == 'esx' then
        local it = p.getInventoryItem(name)
        return it and (it.count or it.amount) or 0
    end
    local total = 0
    for _, it in pairs(p.PlayerData.items or {}) do
        if it and it.name == name then total = total + (it.amount or it.count or 0) end
    end
    return total
end

function Inv.has(src, name, count)
    return Inv.count(src, name) >= (count or 1)
end

function Inv.remove(src, name, count, metadata)
    count = count or 1
    if Inv.count(src, name) < count then return false end
    if Inv.name == 'ox' then
        return exports.ox_inventory:RemoveItem(src, name, count, metadata) and true or false
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:RemoveItem(src, name, count)
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:RemoveItem(src, name, count)
    elseif Inv.name == 'qb' then
        local ok = exports[qbInv]:RemoveItem(src, name, count, false, 'nayzeee-weedlab')
        if ok ~= false then TriggerClientEvent('qb-inventory:client:ItemBox', src, Inv.qbItem(name), 'remove', count) end
        return ok ~= false
    end
    local p = FW.getPlayer(src)
    if not p then return false end
    if FW.name == 'esx' then p.removeInventoryItem(name, count) return true end
    return p.Functions.RemoveItem(name, count)
end

function Inv.canCarry(src, name, count)
    if Inv.name == 'ox' then
        return exports.ox_inventory:CanCarryItem(src, name, count or 1)
    elseif Inv.name == 'qb' then
        local ok, can = pcall(function() return exports[qbInv]:CanAddItem(src, name, count or 1) end)
        return not ok or can ~= false
    elseif FW.name == 'esx' and Inv.name == 'framework' then
        local p = FW.getPlayer(src)
        return p and p.canCarryItem(name, count or 1) or false
    end
    return true
end

function Inv.add(src, name, count, metadata)
    count = count or 1
    if count <= 0 then return false end
    if Inv.name == 'ox' then
        local ok = exports.ox_inventory:AddItem(src, name, count, metadata)
        return ok and true or false
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:AddItem(src, name, count, nil, metadata)
    elseif Inv.name == 'codem' then
        return exports['codem-inventory']:AddItem(src, name, count, nil, metadata)
    elseif Inv.name == 'qb' then
        local ok = exports[qbInv]:AddItem(src, name, count, false, metadata, 'nayzeee-weedlab')
        if ok ~= false then TriggerClientEvent('qb-inventory:client:ItemBox', src, Inv.qbItem(name), 'add', count) end
        return ok ~= false
    end
    local p = FW.getPlayer(src)
    if not p then return false end
    if FW.name == 'esx' then p.addInventoryItem(name, count, metadata) return true end
    return p.Functions.AddItem(name, count, false, metadata)
end

function Inv.qbItem(name)
    if FW.name == 'qbx' then return exports.ox_inventory:Items(name) end
    local QB = exports['qb-core']:GetCoreObject()
    return QB.Shared.Items[name] or { name = name, label = name }
end

local labelCache = {}
function Inv.label(name)
    if labelCache[name] then return labelCache[name] end
    local label = name
    if Inv.name == 'ox' then
        local it = exports.ox_inventory:Items(name)
        label = it and it.label or name
    elseif FW.name == 'qb' then
        local ok, it = pcall(Inv.qbItem, name)
        label = ok and it and it.label or name
    end
    labelCache[name] = label
    return label
end

--[[ metadata-aware helpers (products carry { pid, label, quality, units }) ]]

local function qbInventory(src)
    local p = FW.getPlayer(src)
    return p and p.PlayerData and p.PlayerData.items or {}
end

--- every stack of `name`: { { slot, count, meta } }
function Inv.slots(src, name)
    local out = {}
    if Inv.name == 'ox' then
        local list = exports.ox_inventory:Search(src, 'slots', name) or {}
        for _, it in pairs(list) do
            out[#out + 1] = { slot = it.slot, count = it.count, meta = it.metadata or {} }
        end
        return out
    end
    local items
    if Inv.name == 'qs' then
        items = exports['qs-inventory']:GetInventory(src) or {}
    elseif Inv.name == 'qb' or ((FW.name == 'qb' or FW.name == 'qbx') and Inv.name == 'framework') then
        items = qbInventory(src)
    elseif Inv.name == 'codem' then
        local ok, inv = pcall(function() return exports['codem-inventory']:GetInventory(nil, src) end)
        items = ok and inv or {}
    end
    if items then
        for _, it in pairs(items) do
            if it and it.name == name then
                out[#out + 1] = { slot = it.slot, count = it.amount or it.count or 0, meta = it.info or it.metadata or {} }
            end
        end
        return out
    end
    -- no metadata (plain ESX): one anonymous stack
    local n = Inv.count(src, name)
    if n > 0 then out[1] = { slot = nil, count = n, meta = {} } end
    return out
end

--- remove `count` from one specific stack
function Inv.removeSlot(src, name, count, slot, meta)
    if Inv.name == 'ox' then
        return exports.ox_inventory:RemoveItem(src, name, count, nil, slot) and true or false
    elseif Inv.name == 'qs' then
        return exports['qs-inventory']:RemoveItem(src, name, count, slot) and true or false
    elseif Inv.name == 'qb' then
        local ok = exports[qbInv]:RemoveItem(src, name, count, slot, 'nayzeee-weedlab')
        if ok ~= false then TriggerClientEvent('qb-inventory:client:ItemBox', src, Inv.qbItem(name), 'remove', count) end
        return ok ~= false
    elseif (FW.name == 'qb' or FW.name == 'qbx') and Inv.name == 'framework' then
        local p = FW.getPlayer(src)
        return p and p.Functions.RemoveItem(name, count, slot) or false
    end
    return Inv.remove(src, name, count)
end

--- remove `count` units of `name` whose metadata matches `match(meta)`; all or nothing
function Inv.removeMatching(src, name, count, match)
    local stacks, have = {}, 0
    for _, s in ipairs(Inv.slots(src, name)) do
        if match(s.meta or {}) then
            stacks[#stacks + 1] = s
            have = have + s.count
        end
    end
    if have < count then return false end
    local left = count
    for _, s in ipairs(stacks) do
        if left <= 0 then break end
        local take = math.min(left, s.count)
        if not Inv.removeSlot(src, name, take, s.slot, s.meta) then return false end
        left = left - take
    end
    return true
end
