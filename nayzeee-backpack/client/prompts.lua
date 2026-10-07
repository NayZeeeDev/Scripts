-----------------------------------------------------------------
-- Prompts on your own bag
--
-- Third-eye your own back to open, take off, or set the bag down,
-- instead of digging through the inventory every time.
-----------------------------------------------------------------

if not Config.Prompts or not Config.Prompts.useTarget then return end

local function myBagKey()
    local state = LocalPlayer.state.nayzeee_backpack
    return state and state.bag or nil
end

CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then
        print('^3[nayzeee-backpack] ox_target not running; prompts disabled^0')
        return
    end

    exports.ox_target:addGlobalPlayer({
        {
            name  = 'nayzeee_backpack_self_open',
            label = Config.Prompts.openWorn,
            icon  = 'fa-solid fa-box-open',
            distance = 1.5,
            canInteract = function(entity)
                return entity == PlayerPedId() and myBagKey() ~= nil
            end,
            onSelect = function()
                TriggerServerEvent('nayzeee-backpack:openWorn')
            end,
        },
        {
            name  = 'nayzeee_backpack_self_place',
            label = Config.Prompts.place,
            icon  = 'fa-solid fa-down-long',
            distance = 1.5,
            canInteract = function(entity)
                if entity ~= PlayerPedId() then return false end
                if not Config.Placement or not Config.Placement.enabled then return false end
                return myBagKey() ~= nil
            end,
            onSelect = function()
                local bagKey = myBagKey()
                if bagKey and StartPlacing then StartPlacing(bagKey) end
            end,
        },
    })
end)

-----------------------------------------------------------------
-- keybinds
-----------------------------------------------------------------

RegisterCommand('openbag', function()
    if not myBagKey() then
        return Config.Notify(Strings.no_bag, 'error')
    end
    TriggerServerEvent('nayzeee-backpack:openWorn')
end, false)

RegisterKeyMapping('openbag', 'Open your backpack', 'keyboard', '')

RegisterCommand('placebag', function()
    local bagKey = myBagKey()
    if not bagKey then
        return Config.Notify(Strings.no_bag, 'error')
    end
    if StartPlacing then StartPlacing(bagKey) end
end, false)

RegisterKeyMapping('placebag', 'Set your backpack down', 'keyboard', '')
