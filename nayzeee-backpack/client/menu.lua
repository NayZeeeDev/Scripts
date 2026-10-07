-----------------------------------------------------------------
-- Context menu
--
-- Using the bag opens this instead of jumping straight into the
-- stash, so open / set down / take off / pose are one click away.
-----------------------------------------------------------------

local P = Config.Prompts

local function worn()
    return LocalPlayer.state.nayzeee_backpack or {}
end

--- Pose picker for purses / pocketbooks.
function ShowPoseMenu(bagKey)
    local st = worn()
    local active = Bags.poseFor(bagKey, st.pose)
    local options = {}

    for _, pose in ipairs(Config.Carry.Poses or {}) do
        options[#options + 1] = {
            title = pose.label,
            icon = (active and active.key == pose.key) and 'circle-check' or 'person-dress',
            iconColor = (active and active.key == pose.key) and '#08afa2' or nil,
            onSelect = function()
                TriggerServerEvent('nayzeee-backpack:setPose', pose.key)
            end,
        }
    end

    lib.registerContext({
        id = 'nayzeee_backpack_pose',
        title = P.pose,
        menu = 'nayzeee_backpack_menu',
        options = options,
    })
    lib.showContext('nayzeee_backpack_pose')
end

--- Build and show the menu for the bag the player is carrying.
function OpenBackpackMenu(bagKey)
    bagKey = bagKey or worn().bag

    if not Bags.exists(bagKey) then
        return Config.Notify(Strings.no_bag, 'error')
    end

    local storage = Bags.storage(bagKey)
    local stowed = worn().stowed and true or false
    local options = {}

    options[#options + 1] = {
        title = P.openWorn,
        description = ('%d slots · %.1fkg'):format(storage.slots, storage.weight / 1000),
        icon = 'box-open',
        onSelect = function()
            TriggerServerEvent('nayzeee-backpack:openWorn')
        end,
    }

    if Config.Placement and Config.Placement.enabled then
        options[#options + 1] = {
            title = P.place,
            description = 'Set it down anywhere you look',
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

    if Config.Carry and Config.Carry.enabled and Config.Carry.letPlayersPick
       and not stowed and Bags.carryStyle(bagKey) then
        local pose = Bags.poseFor(bagKey, worn().pose)
        options[#options + 1] = {
            title = P.pose,
            description = pose and pose.label or nil,
            icon = 'person-dress',
            arrow = true,
            onSelect = function() ShowPoseMenu(bagKey) end,
        }
    end

    options[#options + 1] = {
        title = stowed and P.wear or P.stow,
        description = stowed and 'Wear it again' or 'Carry it out of sight',
        icon = stowed and 'arrow-up' or 'arrow-down',
        onSelect = function()
            if Anim and Config.Animations and Config.Animations.enabled then
                Anim.play(stowed and 'equip' or 'unequip')
            end
            TriggerServerEvent('nayzeee-backpack:setStowed', not stowed)
        end,
    }

    lib.registerContext({
        id = 'nayzeee_backpack_menu',
        title = Bags.label(bagKey) or P.menuTitle,
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
