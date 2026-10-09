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

--------------------------------------------------------------------------------
-- NOTIFICATIONS   Config.Notify ('ox' = ox_lib, the default)
--------------------------------------------------------------------------------

local function running(r) return GetResourceState(r) == 'started' end

local function notifySystem()
    local want = Config.Notify or 'ox'
    if want ~= 'auto' then return want end
    if running('nayzeee-notify') then return 'nayzeee' end
    if running('okokNotify') then return 'okok' end
    return 'ox'
end

function Bridge.Notify(text, kind, title, duration)
    kind = kind or 'inform'
    local sys = notifySystem()
    if sys == 'nayzeee' then
        exports['nayzeee-notify']:Notify({ title = title, message = text, type = kind == 'inform' and 'info' or kind, duration = duration })
    elseif sys == 'okok' then
        exports['okokNotify']:Alert(title or 'Sneakers', text, duration or 5000, kind == 'inform' and 'info' or kind)
    elseif sys == 'esx' and fw == 'esx' then
        TriggerEvent('esx:showNotification', text)
    elseif sys == 'qb' and fw == 'qb' then
        TriggerEvent('QBCore:Notify', text, kind == 'inform' and 'primary' or kind)
    elseif sys == 'qb' and fw == 'qbx' then
        exports.qbx_core:Notify(text, kind)
    elseif sys == 'custom' then
        -- put your own notification call here
        print(('[nayzeee-sneakers] %s'):format(text))
    else
        lib.notify({ title = title, description = text, type = kind, duration = duration })
    end
end
