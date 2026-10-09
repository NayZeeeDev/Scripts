--[[
    Custom inventory bridge.

    Set Config.Inventory = 'custom' and fill these in for any inventory that
    isn't ox_inventory or qb-inventory (qs-inventory, codem, tgiann, core...).

    Items carry metadata (a Lua table). Your inventory has to store it per
    item - this script relies on it for size, serial, real/fake and dirt.

    Each function gets the player's server id first. Return values matter:
    the script checks them before it removes or gives anything.
]]

CustomInventory = {
    --- Give an item. Return true if it was added.
    Add = function(src, name, count, metadata)
        -- return exports['your-inventory']:AddItem(src, name, count, nil, metadata)
        return false
    end,

    --- Remove an item, from `slot` when given. Return true if it was removed.
    Remove = function(src, name, count, slot)
        -- return exports['your-inventory']:RemoveItem(src, name, count, slot)
        return false
    end,

    --- The item in one slot: { name = 'nz_shoes', slot = 3, metadata = {...} } or nil
    GetSlot = function(src, slot)
        return nil
    end,

    --- Every slot holding `name`: { { name, slot, metadata }, ... }
    List = function(src, name)
        return {}
    end,

    --- How many of `name` the player has, across all slots
    Count = function(src, name)
        -- return exports['your-inventory']:GetItemCount(src, name)
        return 0
    end,

    --- true if the player has room for the item
    CanCarry = function(src, name, count)
        return true
    end,

    --- Register a usable item. Call cb(src, { name, slot, metadata }) when it's used.
    RegisterUsable = function(name, cb)
        -- Most inventories route item use through the framework:
        Bridge.RegisterUsable(name, cb)
    end,
}
