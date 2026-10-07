-----------------------------------------------------------------
-- Context menu
--
-- Using the bag opens this instead of jumping straight into the
-- stash, so open / set down / take off are all one click away.
-----------------------------------------------------------------

local P = Config.Prompts

local function myBag()
    local state = LocalPlayer.state.nayzeee_backpack
    return state and state.bag or nil
end

local function isStowed()
    local state = LocalPlayer.state.nayzeee_backpack
    return state and state.stowed or false
end

--- Build and show the menu for the bag the player is carrying.
function OpenBackpackMenu(bagKey)
    bagKey = bagKey or myBag()

    local bag = bagKey and Config.Backpacks[bagKey]
    if not bag then
        return Config.Notify(Strings.no_bag, 'error')
    end

    local storage = Config.GetStorage(bagKey)
    local stowed = isStowed()
    local options = {}

    options[#options + 1] = {
        title = P.openWorn,
        description = ('%d slots · %.1fkg'):format(storage.slots, storage.weight / 1000),
        icon = 'box-open',
        onSelect = function()
            TriggerServerEvent('nayzeee-backpack:openWorn')
        end,
    }

    if Config.Placement and Config.Placement.enabled and not stowed then
        options[#options + 1] = {
            title = P.place,
            description = 'Leave it on the ground',
            icon = 'down-long',
            onSelect = function()
                if Config.Placement.askAccess then
                    ShowAccessMenu(bagKey)
                elseif StartPlacing then
                    StartPlacing(bagKey, Config.Placement.defaultAccess or 'private')
                end
            end,
        }
    end

    options[#options + 1] = {
        title = stowed and P.wear or P.stow,
        description = stowed and 'Wear it again' or 'Carry it out of sight',
        icon = stowed and 'arrow-up' or 'arrow-down',
        onSelect = function()
            TriggerServerEvent('nayzeee-backpack:setStowed', not stowed)
        end,
    }

    lib.registerContext({
        id = 'nayzeee_backpack_menu',
        title = bag.label or P.menuTitle,
        options = options,
    })

    lib.showContext('nayzeee_backpack_menu')
end

--- Private or public, asked before placement mode starts.
function ShowAccessMenu(bagKey)
    lib.registerContext({
        id = 'nayzeee_backpack_access',
        title = P.menuTitle,
        menu = 'nayzeee_backpack_menu',
        options = {
            {
                title = P.accessPrivate,
                description = 'Only you can open or pick it up',
                icon = 'lock',
                onSelect = function()
                    if StartPlacing then StartPlacing(bagKey, 'private') end
                end,
            },
            {
                title = P.accessPublic,
                description = 'Anyone can open or pick it up',
                icon = 'lock-open',
                onSelect = function()
                    if StartPlacing then StartPlacing(bagKey, 'public') end
                end,
            },
        },
    })

    lib.showContext('nayzeee_backpack_access')
end

RegisterNetEvent('nayzeee-backpack:menu', function(bagKey)
    OpenBackpackMenu(bagKey)
end)
