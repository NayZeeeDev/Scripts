--[[
    Custom inventory bridge (server). Open under escrow.

    Set Config.Inventory = 'custom' in config.lua and fill in the functions below for your
    inventory. Every function gets the player's server id (src). Return values matter:
    the streamer only hands out items, takes money or consumes spark cards when these say it worked.

    Required: GetItemCount, AddItem, RemoveItem
    Optional: CanCarry (defaults to true), RegisterUsableItem (defaults to your framework's
              usable items), GetItemLabel (defaults to the locale label), HasItemDefinition
              (used for the missing item warning on start)

    The example bodies call a made-up resource 'my_inventory'. Replace them.
]]

Bridge = Bridge or {}

Bridge.CustomInventory = {
    --- How many of an item the player has.
    ---@param src number
    ---@param item string
    ---@return number
    GetItemCount = function(src, item)
        if GetResourceState('my_inventory') ~= 'started' then return 0 end
        local ok, count = pcall(function()
            return exports['my_inventory']:GetItemCount(src, item)
        end)
        return ok and tonumber(count) or 0
    end,

    --- Give items. Return true only when they were added.
    ---@param src number
    ---@param item string
    ---@param count number
    ---@param meta table|nil
    ---@return boolean
    AddItem = function(src, item, count, meta)
        if GetResourceState('my_inventory') ~= 'started' then return false end
        local ok, added = pcall(function()
            return exports['my_inventory']:AddItem(src, item, count, meta)
        end)
        return ok and added == true
    end,

    --- Take items. Return true only when they were removed.
    ---@param src number
    ---@param item string
    ---@param count number
    ---@return boolean
    RemoveItem = function(src, item, count)
        if GetResourceState('my_inventory') ~= 'started' then return false end
        local ok, removed = pcall(function()
            return exports['my_inventory']:RemoveItem(src, item, count)
        end)
        return ok and removed == true
    end,

    --- Can the player fit these items (weight / slots).
    ---@return boolean
    CanCarry = function(src, item, count)
        if GetResourceState('my_inventory') ~= 'started' then return false end
        local ok, fits = pcall(function()
            return exports['my_inventory']:CanCarryItem(src, item, count)
        end)
        if not ok then return true end
        return fits ~= false
    end,

    --- Make an item usable. Call cb(src) when the player uses it.
    --- Remove this function to use your framework's usable items instead.
    -- RegisterUsableItem = function(item, cb)
    --     exports['my_inventory']:RegisterUsableItem(item, function(src) cb(src) end)
    --     return true
    -- end,

    --- Label shown in the inventory. Return nil to use the locale label.
    -- GetItemLabel = function(item)
    --     return exports['my_inventory']:GetItemLabel(item)
    -- end,

    --- Does the item exist in your item list. Return nil to skip the start-up check.
    -- HasItemDefinition = function(item)
    --     return exports['my_inventory']:ItemExists(item)
    -- end,
}
