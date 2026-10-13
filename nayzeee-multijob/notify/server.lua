--[[
    NAYZEEE MULTIJOB - Notification Dispatcher (Server)
    Routes every server-side notification through the configured
    phone resource and/or notify resource.
]]

if not NAYZEEE_LOCK_OK then return end

local resolvedPhone = nil
local phoneResolved = false

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE PHONE
-- ═══════════════════════════════════════════════════════════════════════════

local function ResolvePhone()
    if phoneResolved then return resolvedPhone end
    phoneResolved = true

    local top = Config.Notifications or {}
    local cfg = top.phone or {}

    -- 'notify' output never touches a phone
    if top.output == 'notify' then
        resolvedPhone = nil
        return nil
    end

    local wanted = cfg.resource

    if wanted == false or wanted == 'false' or wanted == 'none' then
        resolvedPhone = nil
        return nil
    end

    if wanted and wanted ~= 'auto' then
        if not NayNotify.Phones[wanted] then
            print(('^1[nayzeee-multijob]^7 Unknown phone adapter "%s" - phone notifications disabled'):format(tostring(wanted)))
            resolvedPhone = nil
            return nil
        end

        local res = NayNotify.PhoneResources[wanted] or wanted
        if GetResourceState(res) ~= 'started' then
            print(('^3[nayzeee-multijob]^7 Phone "%s" is configured but not started - phone notifications disabled'):format(res))
            resolvedPhone = nil
            return nil
        end

        resolvedPhone = wanted
        return resolvedPhone
    end

    -- auto detect
    for _, name in ipairs(NayNotify.PhonePriority) do
        local res = NayNotify.PhoneResources[name] or name
        if GetResourceState(res) == 'started' then
            resolvedPhone = name
            if Config.Debug then
                print(('^2[nayzeee-multijob]^7 Phone auto-detected: ^5%s^7'):format(res))
            end
            return resolvedPhone
        end
    end

    resolvedPhone = nil
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN DISPATCH
-- ═══════════════════════════════════════════════════════════════════════════

--- Send a notification to a player.
--- @param src number  player server id
--- @param data table   { title, message, type, duration, icon, app, phoneOnly }
function Notify(src, data)
    if not src or not data or not data.message then return false end

    local cfg = Config.Notifications or {}
    local meta = NayNotify.Meta(data.type)

    data.type     = data.type or 'info'
    data.duration = data.duration or cfg.duration or 5000
    data.icon     = data.icon or meta.icon
    data.color    = data.color or meta.color
    data.app      = data.app or (cfg.phone and cfg.phone.app) or 'Wallet'

    -- 'notify' | 'phone' | 'both'
    local output = cfg.output or 'notify'

    -- the client already rendered the on-screen half of a 'both' message
    if data.phoneOnly then output = 'phone' end

    local sentToPhone = false

    if output ~= 'notify' then
        local phone = ResolvePhone()
        local adapter = phone and NayNotify.Phones[phone]

        if adapter then
            local ok, err = pcall(adapter, src, data)
            if ok then
                sentToPhone = true
            else
                print(('^1[nayzeee-multijob]^7 Phone adapter "%s" errored: %s'):format(phone, tostring(err)))
            end
        end
    end

    -- On-screen notify runs when it is asked for, or as a fallback when
    -- 'phone' was asked for and no phone could take the message.
    local wantNotify = (output == 'notify')
        or (output == 'both')
        or (output == 'phone' and not sentToPhone)

    if wantNotify and not data.phoneOnly then
        TriggerClientEvent('nayzeee-multijob:notify', src, data)
        return true
    end

    return sentToPhone
end

--- Convenience wrapper matching the old inline calls
function NotifyPlayer(src, title, message, nType)
    return Notify(src, {
        title = title,
        message = message,
        type = nType,
    })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORTS (used by install/REPLACE_paycheck.lua and any other resource)
-- ═══════════════════════════════════════════════════════════════════════════

exports('Notify', function(src, data)
    return Notify(src, data)
end)

exports('NotifyPlayer', function(src, title, message, nType)
    return NotifyPlayer(src, title, message, nType)
end)

exports('GetActivePhone', function()
    return ResolvePhone()
end)

-- Allow other resources to force a re-detect after a phone restart
exports('RefreshNotifyTargets', function()
    phoneResolved = false
    resolvedPhone = nil
    return ResolvePhone()
end)

local lastRequest = {}

RegisterNetEvent('nayzeee-multijob:notifyRequest', function(data)
    -- internal only: client asks server to route a phone notification
    local src = source
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return end

    -- a client can only notify itself, but don't let it flood its own phone
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] < 250 then return end
    lastRequest[src] = now

    Notify(src, {
        title = tostring(data.title or ''):sub(1, 64),
        message = data.message:sub(1, 256),
        type = data.type,
        phoneOnly = data.phoneOnly == true,
    })
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)

local function ResetPhone(res)
    if res == GetCurrentResourceName() then return end
    if NayNotify.PhoneResources[res] then
        phoneResolved = false
        resolvedPhone = nil
    end
end

AddEventHandler('onResourceStart', ResetPhone)
AddEventHandler('onResourceStop', ResetPhone)

CreateThread(function()
    Wait(2000)
    local cfg = Config.Notifications or {}
    local output = cfg.output or 'notify'
    local phone = ResolvePhone()

    if output ~= 'notify' and not phone then
        print(('^3[nayzeee-multijob]^7 output is "%s" but no supported phone is running - falling back to on-screen notifications'):format(output))
    end

    print(('^5[nayzeee-multijob]^7 Notifications | output: ^3%s^7 | phone: ^3%s^7 | notify: ^3%s^7')
        :format(output, phone or 'none', tostring(cfg.system or 'auto')))
end)
