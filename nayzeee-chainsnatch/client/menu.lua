-----------------------------------------------------------------
-- The chain menu (/chain, K): what you wear, what's in your
-- pockets, and what you can do with each.
-----------------------------------------------------------------

Menu = { open = false }

local function close()
    if not Menu.open then return end
    Menu.open = false
    SetNuiFocus(false, false)
    NUI.send('menu:close')
end
Menu.close = close

function Menu.show()
    if Menu.open or (Studio and Studio.open) or Place.active() or Hold.active() or Snatch.tug then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    local data = lib.callback.await('nzc:menu', false)
    if not data then return end
    data.text = Config.Text
    data.canPlace = Config.Place.Enabled
    data.canGive = Config.Give.Enabled
    Menu.open = true
    SetNuiFocus(true, true)
    NUI.send('menu:open', data)
end

if Config.Wear.Command then
    RegisterCommand(Config.Wear.Command, function() if Menu.open then close() else Menu.show() end end, false)
    if Config.Wear.Keybind then
        RegisterKeyMapping(Config.Wear.Command, 'Chain menu', 'keyboard', Config.Wear.Keybind)
    end
end

RegisterNUICallback('menu:close', function(_, cb) cb('ok'); close() end)

RegisterNUICallback('menu:action', function(d, cb)
    cb('ok')
    local act, slot = d and d.act, d and tonumber(d.slot)
    close()
    if act == 'takeoff' then
        TriggerServerEvent('nzc:s:takeOff')
    elseif act == 'wear' and slot then
        TriggerServerEvent('nzc:s:wear', slot)
    elseif act == 'hold' then
        Hold.start()
    elseif act == 'place' then
        local key, letter = WornProps.mine()
        if key then Place.start(key, letter, 'worn') end
    elseif act == 'placeSlot' and slot and d.key then
        Place.start(d.key, d.variant, 'slot', slot)
    elseif act == 'give' or act == 'puton' or act == 'swap' then
        Give.start(act, nil)
    elseif act == 'giveSlot' and slot then
        Give.start('give', slot)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Menu.open then SetNuiFocus(false, false) end
end)
