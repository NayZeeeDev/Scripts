-----------------------------------------------------------------
-- Chain menus (ox_lib context), like nayzeee-backpack
--
-- Use the chain in your inventory (drag it to use) -> its menu:
-- put on / take off, hold up, set down, hand to someone, put it on
-- them, swap. /chain (K) shows the chain you wear and the ones in
-- your pockets. A worn chain stays in the inventory.
-----------------------------------------------------------------

Menu = { open = false }

local TX = Config.Text
local ID, LIST = 'nzc_chain_item', 'nzc_chain_list'

function Menu.close()
    if Menu.open then lib.hideContext(false) end
    Menu.open = false
end

local function blocked()
    if (Studio and Studio.open) or (Store and Store.open) or Place.active() or Hold.active() or Snatch.tug then return true end
    local ped = PlayerPedId()
    return IsEntityDead(ped)
end

local function about(info)
    local bits = { info.value }
    if info.broken then bits[1] = 'BROKEN · ' .. (info.value or '') end
    if info.madeFor then bits[#bits + 1] = 'made for ' .. info.madeFor end
    if info.stolenFrom then bits[#bits + 1] = 'snatched from ' .. info.stolenFrom end
    return table.concat(bits, ' · ')
end

--- The menu of one chain. info = { slot, key, variant, label, worn, broken, value, madeFor, stolenFrom }
function Menu.item(info, parent)
    if not info or blocked() then return end
    local options = {}

    if info.worn then
        options[#options + 1] = {
            title = TX.menu_hold or 'Hold up', icon = 'hand',
            description = TX.menu_hold_d or 'Show it off: throw it or set it down from your hand',
            onSelect = function() Hold.start() end,
        }
    end

    if Config.Place.Enabled then
        options[#options + 1] = {
            title = TX.menu_place or 'Set down', icon = 'down-long',
            description = TX.menu_place_d or 'Set it down anywhere you look',
            onSelect = function()
                if info.worn then Place.start(info.key, info.variant, 'worn') else Place.start(info.key, info.variant, 'slot', info.slot) end
            end,
        }
    end

    if Config.Give.Enabled then
        options[#options + 1] = {
            title = TX.menu_give or 'Hand to someone', icon = 'hand-holding',
            description = TX.menu_give_d or 'Give it to the person in front of you',
            onSelect = function() Give.start('give', info.slot) end,
        }
        if not info.broken then
            options[#options + 1] = {
                title = TX.menu_puton or 'Put it on them', icon = 'user-plus',
                description = TX.menu_puton_d or 'Straight on their neck, theirs goes in their pockets',
                onSelect = function() Give.start('puton', info.worn and nil or info.slot) end,
            }
        end
        if info.worn then
            options[#options + 1] = {
                title = TX.menu_swap or 'Swap chains', icon = 'right-left',
                description = TX.menu_swap_d or 'You both wear the other one\'s chain',
                onSelect = function() Give.start('swap', nil) end,
            }
        end
    end

    if info.worn then
        options[#options + 1] = {
            title = TX.menu_takeoff or 'Take off', icon = 'arrow-down',
            description = TX.menu_takeoff_d or 'It stays in your pockets',
            onSelect = function() TriggerServerEvent('nzc:s:takeOff') end,
        }
    else
        options[#options + 1] = {
            title = TX.menu_wear or 'Put on', icon = 'arrow-up',
            description = info.broken and (TX.broken or 'It\'s broken') or (TX.menu_wear_d or 'Wear it'),
            disabled = info.broken,
            onSelect = function() TriggerServerEvent('nzc:s:wear', info.slot) end,
        }
    end

    lib.registerContext({
        id = ID,
        title = info.label or 'Chain',
        menu = parent,
        options = {
            { title = about(info), icon = 'gem', readOnly = true },
            table.unpack(options),
        },
        onExit = function() Menu.open = false end,
    })
    Menu.open = true
    lib.showContext(ID)
end

--- /chain: the one you wear and the ones in your pockets
function Menu.show()
    if blocked() then return end
    local data = lib.callback.await('nzc:menu', false)
    if not data then return end
    local list = {}
    for _, p in ipairs(data.pockets or {}) do
        list[#list + 1] = p
    end
    if #list == 0 then return CB.Notify(TX.no_chain, 'error') end
    -- only one chain: straight to its menu
    if #list == 1 then
        return Menu.item(list[1])
    end
    local options = {}
    for _, p in ipairs(list) do
        options[#options + 1] = {
            title = p.label, icon = p.worn and 'circle-check' or 'gem', iconColor = p.worn and '#08afa2' or nil,
            description = p.worn and (TX.menu_wearing or 'Wearing') or (p.broken and 'Broken' or nil),
            arrow = true,
            onSelect = function() Menu.item(p, LIST) end,
        }
    end
    lib.registerContext({ id = LIST, title = TX.menu_title or 'Chains', options = options, onExit = function() Menu.open = false end })
    Menu.open = true
    lib.showContext(LIST)
end

-- using the item in the inventory
RegisterNetEvent('nzc:c:itemMenu', function(info)
    if lib.getOpenContextMenu and lib.getOpenContextMenu() then lib.hideContext(false) end
    -- the inventory closes on use; open the menu right after
    SetTimeout(120, function() Menu.item(info) end)
end)

if Config.Wear.Command then
    RegisterCommand(Config.Wear.Command, function() Menu.show() end, false)
    if Config.Wear.Keybind then
        RegisterKeyMapping(Config.Wear.Command, 'Chain menu', 'keyboard', Config.Wear.Keybind)
    end
end
