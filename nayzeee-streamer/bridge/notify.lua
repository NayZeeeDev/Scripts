-- Notify bridge (client + server). Open under escrow.
-- Client: Bridge.Notify(message, type, title), Bridge.ShowTextUI(text), Bridge.HideTextUI()
-- Server: Bridge.Notify(src, message, type, title)
-- type: 'success' | 'error' | 'info' | 'warning'

Bridge = Bridge or {}

local EVENT = 'nayzeee-streamer:client:notify'

local function brandTitle(title)
    if type(title) == 'string' and title ~= '' then return title end
    return Config.Brand and Config.Brand.Name or 'Pulse'
end

if IsDuplicityVersion() then
    function Bridge.Notify(src, message, notifyType, title)
        src = tonumber(src)
        if not src or message == nil then return end
        TriggerClientEvent(EVENT, src, { type = notifyType or 'info', title = brandTitle(title), message = tostring(message) })
    end
    return
end

---------------------------------------------------------------------------------------------------
-- Client

local function started(name)
    return GetResourceState(name) == 'started'
end

local function resolveProvider()
    local wanted = Config.Notify
    if wanted == 'qbcore' or wanted == 'qbox' then wanted = 'qb' end
    if wanted == 'ox' then wanted = 'ox_lib' end
    if wanted and wanted ~= 'auto' then return wanted end
    if started('nayzeee-notify') then return 'nayzeee-notify' end
    if started('ox_lib') and lib and lib.notify then return 'ox_lib' end
    if Bridge.Framework == 'esx' then return 'esx' end
    if Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then return 'qb' end
    return 'native'
end

local function normalType(notifyType)
    if notifyType == 'success' or notifyType == 'error' or notifyType == 'warning' then return notifyType end
    if notifyType == 'warn' then return 'warning' end
    return 'info'
end

local function nativeNotify(message, title)
    local text = message
    if title and title ~= '' then text = ('~h~%s~h~~n~%s'):format(title, message) end
    BeginTextCommandThefeedPost('STRING')
    for i = 1, #text, 99 do
        AddTextComponentSubstringPlayerName(text:sub(i, i + 98))
    end
    EndTextCommandThefeedPostTicker(false, true)
end

local senders = {
    ['nayzeee-notify'] = function(message, notifyType, title)
        if not started('nayzeee-notify') then return false end
        return pcall(function()
            exports['nayzeee-notify']:Notify({ title = title, message = message, type = notifyType })
        end)
    end,
    ox_lib = function(message, notifyType, title)
        if not (lib and lib.notify) then return false end
        local oxType = notifyType == 'info' and 'inform' or notifyType
        return pcall(lib.notify, { title = title, description = message, type = oxType })
    end,
    esx = function(message, notifyType, title)
        if not started('es_extended') then return false end
        return pcall(function()
            local ESX = exports.es_extended:getSharedObject()
            local esxType = notifyType == 'warning' and 'info' or notifyType
            ESX.ShowNotification(message, esxType, 5000, title)
        end)
    end,
    qb = function(message, notifyType, title)
        local qbType = (notifyType == 'info' or notifyType == 'warning') and 'primary' or notifyType
        if Bridge.Framework == 'qbox' and started('qbx_core') then
            -- qbx_core: Notify(title, type, duration, description)
            local qbxType = notifyType == 'info' and 'inform' or notifyType
            return pcall(function() exports.qbx_core:Notify(title, qbxType, 5000, message) end)
        end
        if not started('qb-core') then return false end
        return pcall(function()
            local QBCore = exports['qb-core']:GetCoreObject()
            QBCore.Functions.Notify({ text = message, caption = title }, qbType, 5000)
        end)
    end,
    custom = function(message, notifyType, title)
        if type(Config.CustomNotify) ~= 'function' then return false end
        return pcall(Config.CustomNotify, message, notifyType, title)
    end,
    native = function(message, _, title)
        nativeNotify(message, title)
        return true
    end,
}

local provider

--- Shows a notification. While the app is open it shows inside the app instead.
function Bridge.Notify(message, notifyType, title)
    if message == nil then return end
    message = tostring(message)
    notifyType = normalType(notifyType)
    title = brandTitle(title)

    if type(State) == 'table' and State.uiOpen then
        SendNUIMessage({ action = 'notify', data = { type = notifyType, title = title, message = message } })
        return
    end

    provider = provider or resolveProvider()
    local send = senders[provider] or senders.native
    if not send(message, notifyType, title) then
        nativeNotify(message, title)
    end
end

RegisterNetEvent(EVENT, function(data)
    if type(data) ~= 'table' or data.message == nil then return end
    Bridge.Notify(data.message, data.type, data.title)
end)

---------------------------------------------------------------------------------------------------
-- Text UI (prompts like "[E] Adjust light")

local textUI = { text = nil, via = nil }

function Bridge.ShowTextUI(text)
    if type(text) ~= 'string' or text == '' then return Bridge.HideTextUI() end
    if textUI.text == text then return end
    if textUI.text then Bridge.HideTextUI() end

    local wantNayzeee = Config.Notify == 'auto' or Config.Notify == 'nayzeee-notify'
    if wantNayzeee and started('nayzeee-notify') then
        local ok = pcall(function() exports['nayzeee-notify']:ShowTextUI(text) end)
        if ok then textUI.text, textUI.via = text, 'nayzeee-notify' return end
    end
    if lib and lib.showTextUI then
        lib.showTextUI(text, { position = 'right-center' })
        textUI.text, textUI.via = text, 'ox_lib'
    end
end

function Bridge.HideTextUI()
    if not textUI.text then return end
    if textUI.via == 'nayzeee-notify' then
        if started('nayzeee-notify') then pcall(function() exports['nayzeee-notify']:HideTextUI() end) end
    elseif textUI.via == 'ox_lib' and lib and lib.hideTextUI then
        lib.hideTextUI()
    end
    textUI.text, textUI.via = nil, nil
end

function Bridge.IsTextUIOpen()
    return textUI.text ~= nil
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Bridge.HideTextUI() end
end)
