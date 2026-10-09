-- Framework / inventory bridge (server). Edit freely.
Bridge = {}

local FW, Core = nil, nil
local function detect()
    local want = Config.Framework
    if (want == 'auto' or want == 'esx') and GetResourceState('es_extended') == 'started' then
        FW, Core = 'esx', exports['es_extended']:getSharedObject()
    elseif (want == 'auto' or want == 'qbox') and GetResourceState('qbx_core') == 'started' then
        FW, Core = 'qbox', nil
    elseif (want == 'auto' or want == 'qbcore') and GetResourceState('qb-core') == 'started' then
        FW, Core = 'qb', exports['qb-core']:GetCoreObject()
    else
        FW = 'standalone'
    end
end
detect()

local useOx = Config.Inventory == 'ox_inventory'
    or (Config.Inventory == 'auto' and GetResourceState('ox_inventory') == 'started')

Bridge.Framework = FW

local function qbPlayer(src)
    if FW == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    return Core.Functions.GetPlayer(src)
end

function Bridge.GetIdentifier(src)
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if x then return x.identifier end
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        if p then return p.PlayerData.citizenid end
    end
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. src)
end

function Bridge.GetName(src)
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if x then return x.getName() end
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        if p then return ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) end
    end
    return GetPlayerName(src)
end

function Bridge.HasItem(src, item)
    if useOx then return (exports.ox_inventory:Search(src, 'count', item) or 0) > 0 end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        local it = x and x.getInventoryItem(item)
        return it and (it.count or 0) > 0
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.GetItemByName(item) ~= nil
    end
    return true
end

function Bridge.RemoveItem(src, item)
    if useOx then return exports.ox_inventory:RemoveItem(src, item, 1) end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.removeInventoryItem(item, 1) return true
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.RemoveItem(item, 1)
    end
    return true
end

function Bridge.AddItem(src, item)
    if useOx then return exports.ox_inventory:AddItem(src, item, 1) end
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        if not x then return false end
        x.addInventoryItem(item, 1) return true
    elseif FW == 'qb' or FW == 'qbox' then
        local p = qbPlayer(src)
        return p and p.Functions.AddItem(item, 1)
    end
    return true
end

function Bridge.RegisterUsable(item, cb)
    if FW == 'esx' then
        Core.RegisterUsableItem(item, function(src) cb(src) end)
    elseif FW == 'qbox' then
        exports.qbx_core:CreateUseableItem(item, function(src) cb(src) end)
    elseif FW == 'qb' then
        Core.Functions.CreateUseableItem(item, function(src) cb(src) end)
    end
end

function Bridge.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.Admin.ace) then return true end
    local group
    if FW == 'esx' then
        local x = Core.GetPlayerFromId(src)
        group = x and x.getGroup()
    elseif FW == 'qb' then
        for _, g in ipairs(Config.Admin.groups) do
            if Core.Functions.HasPermission(src, g) then return true end
        end
    end
    if group then
        for _, g in ipairs(Config.Admin.groups) do if g == group then return true end end
    end
    return false
end

-- Vehicle owner check for CarPlay unit removal
function Bridge.OwnsVehicle(src, plate)
    local id = Bridge.GetIdentifier(src)
    plate = plate and plate:gsub('^%s+', ''):gsub('%s+$', '')
    if FW == 'esx' then
        local r = MySQL.scalar.await('SELECT owner FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        return r == id
    elseif FW == 'qb' or FW == 'qbox' then
        local r = MySQL.scalar.await('SELECT citizenid FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
        return r == id
    end
    return true
end

-- ox_inventory: player used the item from the inventory
if useOx then
    exports('useItem', function(event, item, inventory)
        if event == 'usingItem' then
            local src = inventory.id
            local name = item.name
            if Bridge.OnUse and Bridge.OnUse[name] then
                SetTimeout(0, function() Bridge.OnUse[name](src) end)
            end
            return false -- item is only removed when actually placed / installed
        end
    end)
end
Bridge.UsingOx = useOx
Bridge.OnUse = {}
