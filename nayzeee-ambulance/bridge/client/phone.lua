--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: phones (client)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore).

      Bridge.Phone.IsOpen() → bool       (hide our HUD panels / block keys while typing on the phone)
      Bridge.Phone.Resource              detected adapter name or nil (kept up to date, same as the server)

    Also the client half of phone adapters whose API only exists on the client
    (npwd notifications, qs-smartphone and roadphone mail). The server sends
    'nza:bridge:phone' (action, payload).

    IsOpen: lb-phone IsOpen and npwd isPhoneVisible are verified exports. For
    other phones the common export names are tried once (pcall) and the one
    that answers is remembered; LocalPlayer.state.phoneOpen is the last resort.
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Phone = Bridge.Phone or {}

local OPEN_EXPORTS = {
    ['lb-phone']          = { 'IsOpen' },
    ['npwd']              = { 'isPhoneVisible' },
    ['qs-smartphone']     = { 'IsPhoneOpen', 'isPhoneOpen', 'IsOpen' },
    ['qs-smartphone-pro'] = { 'IsPhoneOpen', 'isPhoneOpen', 'IsOpen' },
    ['yseries']           = { 'IsOpen', 'IsPhoneOpen', 'isPhoneOpen' },
    ['gksphone']          = { 'IsOpen', 'PhoneOpen', 'isPhoneOpen' },
    ['okokPhone']         = { 'isPhoneOpen', 'IsPhoneOpen', 'isOpen' },
    ['roadphone']         = { 'isPhoneOpen', 'IsPhoneOpen', 'isOpen' },
    ['high-phone']        = { 'isPhoneOpen', 'IsPhoneOpen', 'isOpen' },
    ['renewed-phone']     = { 'isPhoneOpen', 'IsPhoneOpen', 'IsOpen' },
}
Bridge.PhoneOpenExports = OPEN_EXPORTS

local resolvedOnce = false
local workingExport = {}   -- [resource] = export name | false

local function resolve()
    if resolvedOnce then return Bridge.Phone.Resource end
    resolvedOnce = true
    Bridge.Phone.Resource = Bridge.Pick('phone', Bridge.Cfg('phone', 'auto'))
    return Bridge.Phone.Resource
end

function Bridge.Phone.IsOpen()
    local name = resolve()
    if not name then return LocalPlayer.state.phoneOpen == true end
    local resource = Bridge.Resources.phone[name]
    local known = workingExport[resource]
    if known then
        local ok, open = pcall(function() return exports[resource][known](exports[resource]) end)
        if ok then return open == true end
        workingExport[resource] = nil
    elseif known == nil then
        for _, exportName in ipairs(OPEN_EXPORTS[name] or {}) do
            local ok, open = pcall(function() return exports[resource][exportName](exports[resource]) end)
            if ok then
                workingExport[resource] = exportName
                return open == true
            end
        end
        workingExport[resource] = false
    end
    return LocalPlayer.state.phoneOpen == true
end

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('phone', resource) then
        resolvedOnce = false
        Bridge.Phone.Resource = nil
        workingExport[resource] = nil
        SetTimeout(500, resolve)
    end
end
AddEventHandler('onClientResourceStart', reset)
AddEventHandler('onClientResourceStop', reset)

CreateThread(function()
    Wait(1000)
    resolve()
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT HALF OF SERVER PHONE ADAPTERS
-- ═══════════════════════════════════════════════════════════════════════════

local RELAY = {}
Bridge.PhoneClient = RELAY

RELAY['npwd'] = {
    notify = function(p)
        exports.npwd:createNotification({
            notisId = ('nza:%d'):format(GetGameTimer()),
            appId = p.app or 'MESSAGES',
            content = p.message,
            secondaryTitle = p.title,
            keepOpen = false,
            duration = p.duration or 6000,
            path = '/',
        })
    end,
}

local function qsMail(resource)
    return function(p)
        TriggerServerEvent(resource .. ':server:sendNewMail', {
            sender = p.sender, subject = p.subject, message = p.message, button = {},
        })
    end
end

RELAY['qs-smartphone'] = { mail = qsMail('qs-smartphone') }
RELAY['qs-smartphone-pro'] = { mail = qsMail('qs-smartphone-pro') }

RELAY['roadphone'] = {
    mail = function(p)
        exports['roadphone']:sendMail({ sender = p.sender, subject = p.subject, message = p.message })
    end,
}

RegisterNetEvent('nza:bridge:phone', function(action, payload)
    if type(action) ~= 'string' or type(payload) ~= 'table' or type(payload.phone) ~= 'string' then return end
    local adapter = RELAY[payload.phone]
    local fn = adapter and adapter[action]
    if fn then Bridge.Try('phone.' .. payload.phone .. '.' .. action, fn, payload) end
end)
