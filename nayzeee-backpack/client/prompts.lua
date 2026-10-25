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

local K = Config.Keybinds or {}

RegisterCommand('openbag', function()
    if not worn() then
        return Config.Notify(Strings.no_bag, 'error')
    end
    TriggerServerEvent('nayzeee-backpack:openWorn')
end, false)

RegisterKeyMapping('openbag', 'Open your backpack', 'keyboard', K.open or '')

RegisterCommand('bagmenu', function()
    local bagKey = worn()
    if not bagKey then return Config.Notify(Strings.no_bag, 'error') end
    OpenBackpackMenu(bagKey)
end, false)

RegisterKeyMapping('bagmenu', 'Backpack menu', 'keyboard', K.menu or '')

RegisterCommand('placebag', function()
    local bagKey = worn()
    if not bagKey then
        return Config.Notify(Strings.no_bag, 'error')
    end
    if StartPlacing then StartPlacing(bagKey) end
end, false)

RegisterKeyMapping('placebag', 'Set your backpack down', 'keyboard', K.place or '')

RegisterCommand('mybags', function() ShowPlacedMenu() end, false)

-----------------------------------------------------------------
-- first bag: one hint, once per player (remembered client side)
-----------------------------------------------------------------

if Config.FirstBagHint ~= false then
    local HINT = 'nayzeee_backpack_hint_v1'
    AddStateBagChangeHandler('nayzeee_backpack', ('player:%s'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        if not value or GetResourceKvpInt(HINT) == 1 then return end
        SetResourceKvpInt(HINT, 1)
        SetTimeout(1500, function()
            Config.Notify(Strings.first_hint, 'inform')
        end)
    end)
end
