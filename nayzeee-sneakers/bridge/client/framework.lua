Bridge = {}

local fw = Config.Framework
if fw == 'auto' then
    if GetResourceState('qbx_core') == 'started' then fw = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then fw = 'qb'
    elseif GetResourceState('es_extended') == 'started' then fw = 'esx'
    else fw = 'none' end
end
Bridge.Framework = fw

local loadedHandlers = {}

--- cb runs every time the local character finishes loading (and once on resource start if already loaded)
function Bridge.OnPlayerLoaded(cb)
    loadedHandlers[#loadedHandlers + 1] = cb
end

local function fireLoaded()
    for _, cb in ipairs(loadedHandlers) do CreateThread(cb) end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', fireLoaded)   -- qb + qbx
RegisterNetEvent('esx:playerLoaded', fireLoaded)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(1000)
    local loaded = LocalPlayer.state.isLoggedIn
    if fw == 'esx' then
        local ok, ESX = pcall(function() return exports.es_extended:getSharedObject() end)
        loaded = ok and ESX and ESX.IsPlayerLoaded and ESX.IsPlayerLoaded()
    elseif fw == 'none' then
        loaded = NetworkIsPlayerActive(PlayerId())
    end
    if loaded then fireLoaded() end
end)

function Bridge.FrameworkNotify(text, kind)
    if fw == 'qb' then
        TriggerEvent('QBCore:Notify', text, kind == 'inform' and 'primary' or kind)
    elseif fw == 'qbx' then
        exports.qbx_core:Notify(text, kind)
    elseif fw == 'esx' then
        TriggerEvent('esx:showNotification', text)
    else
        lib.notify({ description = text, type = kind })
    end
end
