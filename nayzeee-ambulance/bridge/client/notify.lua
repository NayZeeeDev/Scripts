--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: notifications (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore).

      Bridge.Notify({ title, message, type = 'success'|'error'|'warning'|'info', duration })
      Bridge.NotifyExternal(data)    skip our NUI toast, use the notify resource

    Default ('auto' / 'nza'): our own NUI toast through the local event
    'nza:ui:toast' (client/core shows it). If client/core falls back to
    Bridge.Notify while handling that event, the message goes to the notify
    resource instead (no loop).

    ADDING YOUR OWN
      Bridge.NotifyAdapters['myNotify'] = function(data) ... end
      Bridge.Resources.notify['myNotify'] = 'my-notify-resource'
      then Config.Bridge.notify = 'myNotify' (or add it to Bridge.Priority.notify)

    EVENTS
      nza:bridge:notify (S→C, registered here)   data → NotifyExternal
      nza:ui:toast      (local, triggered here)  handled by client/core
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

local N = {}
Bridge.NotifyAdapters = N

-- ═══════════════════════════════════════════════════════════════════════════
-- ADAPTERS
-- ═══════════════════════════════════════════════════════════════════════════

N['nayzeee'] = function(data)
    exports['nayzeee-notify']:Notify({
        title = data.title,
        message = data.message,
        type = data.type,
        duration = data.duration,
        icon = data.icon,
    })
end

N['ox_lib'] = function(data)
    lib.notify({
        title = data.title,
        description = data.message,
        type = data.type == 'info' and 'inform' or data.type,
        duration = data.duration,
    })
end

N['okok'] = function(data)
    exports['okokNotify']:Alert(data.title or 'EMS', data.message, data.duration, data.type, true)
end

N['codem'] = function(data)
    exports['codem-notification']:sendAlert({
        type = data.type,
        text = data.message,
        title = data.title,
        duration = data.duration,
    })
end

N['mythic'] = function(data)
    local mType = (data.type == 'success' or data.type == 'error') and data.type or 'inform'
    local ok = pcall(function() exports['mythic_notify']:SendAlert(mType, data.message, data.duration) end)
    if not ok then exports['mythic_notify']:DoHudText(mType, data.message) end
end

N['brutal'] = function(data)
    exports['brutal_notify']:SendAlert(data.title or 'EMS', data.message, data.duration, data.type, false)
end

N['t-notify'] = function(data)
    exports['t-notify']:Alert({
        style = data.type,
        message = data.message,
        title = data.title,
        duration = data.duration,
    })
end

N['qb'] = function(data)
    local qbType = (data.type == 'success' or data.type == 'error') and data.type or 'primary'
    TriggerEvent('QBCore:Notify', data.title and (data.title .. ': ' .. data.message) or data.message, qbType, data.duration)
end

N['esx'] = function(data)
    local prefix = ''
    if data.type == 'success' then prefix = '~g~'
    elseif data.type == 'error' then prefix = '~r~'
    elseif data.type == 'warning' then prefix = '~o~' end
    TriggerEvent('esx:showNotification', prefix .. (data.title and (data.title .. ': ') or '') .. '~s~' .. data.message, data.type, data.duration)
end

-- GTA feed message, always available
N['native'] = function(data)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName((data.title and ('~h~' .. data.title .. '~h~~n~') or '') .. data.message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local TYPES = { success = true, error = true, warning = true, info = true }
local external, externalResolved = nil, false
local insideToast = false

local function useNza()
    local wanted = Bridge.Cfg('notify', 'auto')
    return wanted == nil or wanted == 'auto' or wanted == 'nza' or wanted == true
end

local function resolveExternal()
    if externalResolved then return external end
    externalResolved = true
    local wanted = Bridge.Cfg('notify', 'auto')
    if wanted == 'nza' then wanted = 'auto' end
    external = Bridge.Pick('notify', wanted, {
        exclude = { nza = true },
        has = function(name) return N[name] ~= nil end,
    }) or 'native'
    return external
end

local function clean(data)
    if type(data) == 'string' then data = { message = data } end
    if type(data) ~= 'table' then return nil end
    local message = data.message or data.description or data.text
    if message == nil then return nil end
    return {
        title = data.title and tostring(data.title) or nil,
        message = tostring(message),
        type = TYPES[data.type] and data.type or 'info',
        duration = tonumber(data.duration) or 5000,
        icon = data.icon,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

function Bridge.NotifyExternal(data)
    data = clean(data)
    if not data then return false end
    local name = resolveExternal()
    local ok = Bridge.Try('notify.' .. name, N[name], data)
    if not ok and name ~= 'native' then N['native'](data) end
    return true
end

function Bridge.Notify(data)
    data = clean(data)
    if not data then return false end
    if useNza() and not insideToast then
        insideToast = true
        local ok, err = pcall(TriggerEvent, 'nza:ui:toast', data)
        insideToast = false
        if ok then return true end
        Bridge.Debug('nza:ui:toast failed: ' .. tostring(err))
    end
    return Bridge.NotifyExternal(data)
end

RegisterNetEvent('nza:bridge:notify', function(data)
    Bridge.NotifyExternal(data)
end)

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('notify', resource) then
        externalResolved, external = false, nil
    end
end

AddEventHandler('onClientResourceStart', reset)
AddEventHandler('onClientResourceStop', reset)
