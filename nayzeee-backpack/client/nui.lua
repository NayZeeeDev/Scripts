RegisterNetEvent('nayzeee-backpack:open', function(stashId)
    if Config.Animations and Config.Animations.enabled then
        Anim.play('open')
    end
    exports.ox_inventory:openInventory('stash', stashId)
end)

RegisterNetEvent('nayzeee-backpack:notify', function(msg, type)
    Config.Notify(msg, type)
end)
