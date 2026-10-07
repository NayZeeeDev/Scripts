-----------------------------------------------------------------
-- Prompts on your own bag
--
-- Third-eye your own back to open, take off, or set the bag down,
-- instead of digging through the inventory every time.
-----------------------------------------------------------------

local function worn()
    local st = LocalPlayer.state.nayzeee_backpack
    return st and st.bag or nil, st
end

CreateThread(function()
    if not Config.Prompts.useTarget then return end
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
                return entity == PlayerPedId() and worn() ~= nil
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
                return worn() ~= nil
            end,
            onSelect = function()
                local bagKey = worn()
                if not bagKey then return end
                if Config.Placement.askAccess then ShowAccessMenu(bagKey) else StartPlacing(bagKey) end
            end,
        },
    })
end)

-----------------------------------------------------------------
-- keybinds
-----------------------------------------------------------------

RegisterCommand('openbag', function()
    if not worn() then
        return Config.Notify(Strings.no_bag, 'error')
    end
    TriggerServerEvent('nayzeee-backpack:openWorn')
end, false)

RegisterKeyMapping('openbag', 'Open your backpack', 'keyboard', '')

RegisterCommand('bagmenu', function()
    local bagKey = worn()
    if not bagKey then return Config.Notify(Strings.no_bag, 'error') end
    OpenBackpackMenu(bagKey)
end, false)

RegisterKeyMapping('bagmenu', 'Backpack menu', 'keyboard', '')

RegisterCommand('placebag', function()
    local bagKey = worn()
    if not bagKey then
        return Config.Notify(Strings.no_bag, 'error')
    end
    if StartPlacing then StartPlacing(bagKey) end
end, false)

RegisterKeyMapping('placebag', 'Set your backpack down', 'keyboard', '')
