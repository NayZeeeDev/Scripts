-----------------------------------------------------------------
-- Weight tracking
--
-- Recomputes how full a player's bag is and pushes it to them.
-----------------------------------------------------------------

if not Config.WeightEffects or not Config.WeightEffects.enabled then return end

local ox = exports.ox_inventory

--- Push the current fill fraction of a player's bag.
function UpdateLoad(src)
    local state = Player(src).state.nayzeee_backpack

    if not state or not state.bag then
        TriggerClientEvent('nayzeee-backpack:setLoad', src, 0.0)
        return
    end

    local item = FindBagItem(src)
    local bagid = item and item.metadata and item.metadata.bagid

    if not bagid then
        TriggerClientEvent('nayzeee-backpack:setLoad', src, 0.0)
        return
    end

    local inv = ox:GetInventory(('backpack_%s'):format(bagid))
    if not inv then
        TriggerClientEvent('nayzeee-backpack:setLoad', src, 0.0)
        return
    end

    local max = inv.maxWeight or Bags.storage(state.bag).weight
    local load = max > 0 and ((inv.weight or 0) / max) or 0.0

    TriggerClientEvent('nayzeee-backpack:setLoad', src, load)
end

-- recompute whenever a backpack stash is touched
ox:registerHook('swapItems', function(payload)
    local function check(inv)
        if type(inv) == 'string' and inv:find('^backpack_') then return true end
        return false
    end

    if check(payload.fromInventory) or check(payload.toInventory) then
        SetTimeout(120, function()
            local owner = payload.source
            if owner then UpdateLoad(owner) end
        end)
    end

    return true
end)

RegisterNetEvent('nayzeee-backpack:requestLoad', function()
    UpdateLoad(source)
end)
