if not NAYZEEE_LOCK_OK then return end

-- Client bridge (open file)

-- Called when the racing tablet item should also close an inventory UI
function Bridge_CloseInventory()
    if GetResourceState('ox_inventory') == 'started' then
        pcall(function() exports.ox_inventory:closeInventory() end)
    end
end
