if not NAYZEEE_LOCK_OK then return end

--[[
    Client framework hooks. Edit freely - this file is not escrowed.
]]

ClientBridge = {}

-- Notifications (in-game, outside the selection UI)
function ClientBridge.Notify(msg, kind)
    if GetResourceState('nayzeee-notify') == 'started' then
        local ok = pcall(function() exports['nayzeee-notify']:Notify({ type = kind or 'info', message = msg }) end)
        if ok then return end
    end
    lib.notify({ description = msg, type = kind == 'error' and 'error' or (kind == 'success' and 'success' or 'inform') })
end

-- Hide / show your HUD while in character selection
function ClientBridge.Hud(visible)
    DisplayRadar(visible)
    DisplayHud(visible)
    if GetResourceState('nayzeee-hud') == 'started' then pcall(function() exports['nayzeee-hud']:Toggle(visible) end) end
    TriggerEvent('nayzeee-multicharacter:hud', visible)
    if GetResourceState('chat') == 'started' then pcall(function() exports.chat:setEnabled(visible) end) end
end

-- Fired after the player is in the world. isNew = brand new character.
function ClientBridge.PlayerSpawned(isNew)
    if NZ.IsESX then
        TriggerServerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:onPlayerSpawn')
        TriggerEvent('playerSpawned')
        if not isNew then TriggerEvent('esx:restoreLoadout') end
    else
        TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
        TriggerEvent('QBCore:Client:OnPlayerLoaded')
        TriggerEvent('playerSpawned')
        if GetResourceState('qb-clothing') == 'started' then TriggerServerEvent('qb-clothes:loadPlayerSkin') end
    end
    TriggerEvent('nayzeee-multicharacter:spawned', isNew)
end

-- Loading screen handoff
function ClientBridge.LoadingScreenOff()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    if NZ.IsESX then TriggerEvent('esx:loadingScreenOff') end
end
