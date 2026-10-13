--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE MULTIJOB - Notification Adapters
    ═══════════════════════════════════════════════════════════════════════════

    This file is OPEN (escrow_ignore) so you can add or fix adapters yourself.

    Two separate lists:
      NayNotify.Systems  -> CLIENT side notify resources (ox_lib, okok, etc.)
      NayNotify.Phones   -> SERVER side phone resources (lb-phone, qs, etc.)

    Which one the player sees is decided by Config.Notifications.output:
      - 'notify'  on-screen only
      - 'phone'   phone only (falls back to on-screen if no phone is running)
      - 'both'    both at once

    ADDING YOUR OWN:
      NayNotify.Systems['myNotify'] = function(data) ... end       -- client
      NayNotify.Phones['my-phone']  = function(src, data) ... end  -- server
      Then set Config.Notifications.system = 'myNotify'
      or     Config.Notifications.phone.resource = 'my-phone'

    data = {
        title    = string,
        message  = string,
        type     = 'success' | 'error' | 'warning' | 'info',
        duration = number (ms),
        icon     = string (Font Awesome),
        color    = string (hex),
        app      = string (phone app name),
    }
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

NayNotify = NayNotify or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- TYPE STYLING (NAYZEEE palette)
-- ═══════════════════════════════════════════════════════════════════════════

NayNotify.TypeMeta = {
    success = { color = '#08afa2', icon = 'fa-solid fa-circle-check' },
    error   = { color = '#ef4444', icon = 'fa-solid fa-circle-xmark' },
    warning = { color = '#f59e0b', icon = 'fa-solid fa-triangle-exclamation' },
    info    = { color = '#ffffff', icon = 'fa-solid fa-circle-info' },
}

function NayNotify.Meta(nType)
    return NayNotify.TypeMeta[nType or 'info'] or NayNotify.TypeMeta.info
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO-DETECT ORDER
-- Reorder these if you have more than one installed and want a specific one.
-- ═══════════════════════════════════════════════════════════════════════════

NayNotify.SystemPriority = {
    'nayzeee',      -- nayzeee-notify
    'ox_lib',       -- ox_lib
    'okok',         -- okokNotify
    'codem',        -- codem-notification
    'mythic',       -- mythic_notify
    'brutal',       -- brutal_notify
    't-notify',     -- t-notify
    'qb',           -- qb-core
    'esx',          -- es_extended
}

NayNotify.SystemResources = {
    nayzeee     = 'nayzeee-notify',
    ox_lib      = 'ox_lib',
    okok        = 'okokNotify',
    codem       = 'codem-notification',
    mythic      = 'mythic_notify',
    brutal      = 'brutal_notify',
    ['t-notify'] = 't-notify',
    qb          = 'qb-core',
    esx         = 'es_extended',
}

NayNotify.PhonePriority = {
    'lb-phone',
    'qs-smartphone-pro',
    'qs-smartphone',
    'gksphone',
    'roadphone',
    'yflip-phone',
    'high-phone',
    'npwd',
    'qb-phone',
}

NayNotify.PhoneResources = {
    ['lb-phone']          = 'lb-phone',
    ['qs-smartphone-pro'] = 'qs-smartphone-pro',
    ['qs-smartphone']     = 'qs-smartphone',
    ['gksphone']          = 'gksphone',
    ['roadphone']         = 'roadphone',
    ['yflip-phone']       = 'yflip-phone',
    ['high-phone']        = 'high-phone',
    ['npwd']              = 'npwd',
    ['qb-phone']          = 'qb-phone',
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CLIENT NOTIFY ADAPTERS
-- ═══════════════════════════════════════════════════════════════════════════

NayNotify.Systems = {}

NayNotify.Systems['ox_lib'] = function(data)
    -- ox_lib calls 'info' 'inform'
    local oxType = (data.type == 'info' or not data.type) and 'inform' or data.type
    lib.notify({
        title = data.title,
        description = data.message,
        type = oxType,
        duration = data.duration,
        icon = data.icon,
        iconColor = data.color,
        position = Config.Notifications.position,
    })
end

NayNotify.Systems['nayzeee'] = function(data)
    if GetResourceState('nayzeee-notify') ~= 'started' then return false end
    exports['nayzeee-notify']:Notify({
        title = data.title,
        message = data.message,
        type = data.type or 'info',
        duration = data.duration,
        icon = data.icon,
    })
end

NayNotify.Systems['esx'] = function(data)
    local prefix = ''
    if data.type == 'success' then prefix = '~g~'
    elseif data.type == 'error' then prefix = '~r~'
    elseif data.type == 'warning' then prefix = '~o~' end

    TriggerEvent('esx:showNotification', prefix .. (data.title and (data.title .. ': ') or '') .. '~s~' .. data.message)
end

NayNotify.Systems['esx_advanced'] = function(data)
    local prefix = data.type == 'error' and '~r~' or data.type == 'warning' and '~o~' or '~g~'
    TriggerEvent('esx:showAdvancedNotification',
        data.title or 'Job',
        prefix .. (data.subtitle or ''),
        data.message,
        data.dict or 'CHAR_BANK_MAZE',
        9
    )
end

NayNotify.Systems['qb'] = function(data)
    -- QBCore only knows primary / success / error
    local qbType = (data.type == 'success' or data.type == 'error') and data.type or 'primary'
    TriggerEvent('QBCore:Notify', data.message, qbType, data.duration)
end

NayNotify.Systems['okok'] = function(data)
    exports['okokNotify']:Alert(data.title or 'Job', data.message, data.duration, data.type or 'info', true)
end

NayNotify.Systems['codem'] = function(data)
    exports['codem-notification']:sendAlert({
        type = data.type or 'info',
        text = data.message,
        title = data.title,
        duration = data.duration,
    })
end

NayNotify.Systems['mythic'] = function(data)
    local mType = (data.type == 'success' or data.type == 'error') and data.type or 'inform'
    exports['mythic_notify']:DoHudText(mType, data.message)
end

NayNotify.Systems['brutal'] = function(data)
    exports['brutal_notify']:SendAlert(data.title or 'Job', data.message, data.duration, data.type or 'info')
end

NayNotify.Systems['t-notify'] = function(data)
    exports['t-notify']:Alert({
        style = data.type or 'info',
        message = data.message,
        title = data.title,
        duration = data.duration,
    })
end

NayNotify.Systems['chat'] = function(data)
    TriggerEvent('chat:addMessage', {
        color = { 8, 175, 162 },
        multiline = true,
        args = { data.title or 'JOB', data.message },
    })
end

-- Native GTA notification, always available, no dependency
NayNotify.Systems['native'] = function(data)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(data.message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVER PHONE ADAPTERS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- NOTE: phone resources change their export signatures between versions.
-- If a phone below does not fire on your build, fix the one function here -
-- nothing else in the resource needs to change.
--
-- ═══════════════════════════════════════════════════════════════════════════

NayNotify.Phones = {}

-- Verified against lb-phone current docs
NayNotify.Phones['lb-phone'] = function(src, data)
    exports['lb-phone']:SendNotification(src, {
        app = data.app or 'Wallet',
        title = data.title,
        content = data.message,
    })
end

NayNotify.Phones['qs-smartphone'] = function(src, data)
    TriggerClientEvent('qs-smartphone:client:notification', src, {
        title = data.title,
        text = data.message,
        icon = data.phoneIcon or 'fas fa-wallet',
        color = data.color,
        timeout = data.duration,
        app = data.app or 'wallet',
    })
end

NayNotify.Phones['qs-smartphone-pro'] = function(src, data)
    TriggerClientEvent('qs-smartphone-pro:client:notification', src, {
        title = data.title,
        text = data.message,
        icon = data.phoneIcon or 'fas fa-wallet',
        color = data.color,
        timeout = data.duration,
        app = data.app or 'wallet',
    })
end

NayNotify.Phones['gksphone'] = function(src, data)
    TriggerClientEvent('gksphone:NotificationShow', src, {
        title = data.title,
        message = data.message,
        icon = data.phoneIcon or 'bank',
        time = data.duration,
    })
end

NayNotify.Phones['roadphone'] = function(src, data)
    TriggerClientEvent('roadphone:notify', src, {
        app = data.app or 'bank',
        title = data.title,
        message = data.message,
        timeout = data.duration,
    })
end

NayNotify.Phones['yflip-phone'] = function(src, data)
    exports['yflip-phone']:SendNotification(src, {
        app = data.app or 'Wallet',
        title = data.title,
        content = data.message,
    })
end

NayNotify.Phones['high-phone'] = function(src, data)
    TriggerClientEvent('high_phone:notification', src, {
        title = data.title,
        message = data.message,
        app = data.app or 'bank',
        timeout = data.duration,
    })
end

NayNotify.Phones['npwd'] = function(src, data)
    TriggerClientEvent('npwd:createNotification', src, {
        notisId = 'nayzeee-multijob:' .. tostring(os.time()),
        appId = data.app or 'BANK',
        message = data.message,
        keepOpen = false,
        duration = data.duration,
    })
end

NayNotify.Phones['qb-phone'] = function(src, data)
    TriggerClientEvent('qb-phone:client:customNotification', src,
        data.title,
        data.message,
        data.phoneIcon or 'fas fa-wallet',
        data.color or '#08afa2',
        data.duration
    )
end
