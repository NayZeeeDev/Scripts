-- Phone app adapters. The app itself (web/phone) talks to this resource through NUI callbacks,
-- so it works the same inside any phone. Each phone only needs to know how to add the app.
--
-- There is no built-in phone: the app only lives inside a phone resource.
-- lb-phone is fully supported. YSeries and qs-smartphone expose different custom-app exports
-- between versions: if the app doesn't show up, check your phone's docs and edit the
-- `register` function for it below.

PhoneBridge = { name = 'none' }

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

-- a phone not listed here: copy one of the adapters above, then add its id to AUTO

local AUTO = { 'lb-phone', 'yseries', 'qs-smartphone-pro', 'qs-smartphone' }

local function pick()
    if not CP.Enabled then return 'none' end
    local p = CP.Phone
    if p ~= 'auto' then
        if ADAPTERS[p] then return p end
        print(('^1[%s] Config.Phone.Phone = %s is not a supported phone.^7'):format(RESOURCE, tostring(p)))
        return 'none'
    end
    for _, id in ipairs(AUTO) do
        if GetResourceState(ADAPTERS[id].resource) == 'started' then return id end
    end
    print(('^3[%s] No supported phone found (lb-phone, yseries, qs-smartphone). The %s app is disabled.^7'):format(RESOURCE, CP.AppName))
    return 'none'
end

local function register()
    local a = ADAPTERS[PhoneBridge.name]
    if not a or not a.register then return end
    local ok, err = pcall(a.register)
    if not ok then
        print(('^3[%s] Could not add the %s app to %s: %s^7'):format(
            RESOURCE, CP.AppName, PhoneBridge.name, tostring(err)))
    else
        Debug('phone app added to', PhoneBridge.name)
    end
end

function PhoneBridge.Init()
    PhoneBridge.name = pick()
    if PhoneBridge.name == 'none' then return end
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
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.send then pcall(a.send, data) end
end

-- every message from the app goes out as an ox_lib notification
function PhoneBridge.Notify(msg, kind)
    CB.Notify(msg, kind or 'info')
end
