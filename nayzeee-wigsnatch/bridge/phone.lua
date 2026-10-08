-- Phone app adapters. The app itself (web/phone) talks to this resource through NUI callbacks,
-- so it works the same inside any phone. Each phone only needs to know how to add the app.
--
-- lb-phone is fully supported. YSeries and qs-smartphone expose different custom-app exports
-- between versions: if the app doesn't show up, check your phone's docs and edit the
-- `register` function for it below. /hairplug always works as a fallback.

PhoneBridge = { name = 'standalone' }

local CP = Config.Phone
local UI_PATH = 'web/phone/index.html'
local ICON = ('https://cfx-nui-%s/web/phone/icon.png'):format(RESOURCE)

local APP = {
    identifier  = CP.Identifier,
    name        = CP.AppName,
    description = 'Sell wigs and hair bundles, take orders and list on the market.',
    developer   = 'NayZeee Development',
}

local ADAPTERS = {}

ADAPTERS['lb-phone'] = {
    resource = 'lb-phone',
    register = function()
        local ok, err = exports['lb-phone']:AddCustomApp({
            identifier  = APP.identifier,
            name        = APP.name,
            description = APP.description,
            developer   = APP.developer,
            defaultApp  = true,
            size        = 2048,
            ui          = RESOURCE .. '/' .. UI_PATH,
            icon        = ICON,
            fixBlur     = true,
        })
        if ok == false then print(('^3[%s] lb-phone refused the app: %s^7'):format(RESOURCE, tostring(err))) end
    end,
    send = function(data)
        exports['lb-phone']:SendCustomAppMessage(APP.identifier, data)
    end,
    notify = function(title, msg)
        exports['lb-phone']:SendNotification({ app = APP.identifier, title = title, content = msg })
    end,
}

ADAPTERS['yseries'] = {
    resource = 'yseries',
    register = function()
        exports.yseries:AddCustomApp({
            key         = APP.identifier,
            name        = APP.name,
            description = APP.description,
            ui          = ('https://cfx-nui-%s/%s'):format(RESOURCE, UI_PATH),
            icon        = ICON,
            developer   = APP.developer,
        })
    end,
}

local function qsRegister(res)
    return function()
        exports[res]:addCustomApp({
            app         = APP.identifier,
            image       = ICON,
            ui          = ('https://cfx-nui-%s/%s'):format(RESOURCE, UI_PATH),
            label       = APP.name,
            job         = false,
            blockedJobs = {},
            timeout     = 5000,
            creator     = APP.developer,
            category    = 'business',
            isGame      = false,
            description = APP.description,
            age         = '16+',
            extraDescription = {},
        })
    end
end

ADAPTERS['qs-smartphone-pro'] = { resource = 'qs-smartphone-pro', register = qsRegister('qs-smartphone-pro') }
ADAPTERS['qs-smartphone']     = { resource = 'qs-smartphone',     register = qsRegister('qs-smartphone') }

local AUTO = { 'lb-phone', 'yseries', 'qs-smartphone-pro', 'qs-smartphone' }

local function pick()
    if not CP.Enabled then return 'none' end
    local p = CP.Phone
    if p ~= 'auto' then return ADAPTERS[p] and p or 'standalone' end
    for _, id in ipairs(AUTO) do
        if GetResourceState(ADAPTERS[id].resource) == 'started' then return id end
    end
    return 'standalone'
end

local function register()
    local a = ADAPTERS[PhoneBridge.name]
    if not a or not a.register then return end
    local ok, err = pcall(a.register)
    if not ok then
        print(('^3[%s] Could not add the %s app to %s: %s. /%s still works.^7'):format(
            RESOURCE, CP.AppName, PhoneBridge.name, tostring(err), tostring(CP.Command)))
    else
        Debug('phone app added to', PhoneBridge.name)
    end
end

function PhoneBridge.Init()
    PhoneBridge.name = pick()
    if PhoneBridge.name == 'none' or PhoneBridge.name == 'standalone' then return end
    CreateThread(function()
        Wait(1000) -- let the phone finish its own start
        register()
    end)
end

-- the phone restarted: add the app again
AddEventHandler('onResourceStart', function(res)
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.resource == res then SetTimeout(1500, register) end
end)

-- push a message to the open app (it also polls, so phones without push still update)
function PhoneBridge.Send(data)
    if NUI.app == 'phone' then NUI.Send('phone:msg', data) end
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.send then pcall(a.send, data) end
end

-- phone banner notification, falls back to a normal notification
function PhoneBridge.Notify(msg, kind)
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.notify and pcall(a.notify, CP.AppName, msg) then return end
    CB.Notify(msg, kind or 'info')
end
