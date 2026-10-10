--[[
    Phone app adapters. The app (web/phone) talks to this resource through NUI callbacks,
    so it works the same inside any phone. Each phone only needs to know how to add the app.

    lb-phone is fully supported. YSeries and qs-smartphone expose different custom-app exports
    between versions: if the app doesn't show up, check your phone's docs and edit the
    `register` function for it below. /empire (Config.Phone.Command) always works as a fallback.

    The app is only added once the player has the RV (the story "installs" it).
]]

PhoneBridge = { name = 'standalone', installed = false }

local CP = Config.Phone
local UI_PATH = 'web/phone/index.html'
local ICON = ('https://cfx-nui-%s/web/phone/icon.svg'):format(RES)

local APP = {
    identifier  = CP.Identifier,
    name        = CP.AppName,
    description = 'Messages, journal, products, contacts, map, dealers and deliveries.',
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
            size        = 4096,
            ui          = RES .. '/' .. UI_PATH,
            icon        = ICON,
            fixBlur     = true,
        })
        if ok == false then print(('^3[%s] lb-phone refused the app: %s^7'):format(RES, tostring(err))) end
    end,
    remove = function() exports['lb-phone']:RemoveCustomApp(APP.identifier) end,
    send = function(data) exports['lb-phone']:SendCustomAppMessage(APP.identifier, data) end,
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
            ui          = ('https://cfx-nui-%s/%s'):format(RES, UI_PATH),
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
            ui          = ('https://cfx-nui-%s/%s'):format(RES, UI_PATH),
            label       = APP.name,
            job         = false,
            blockedJobs = {},
            timeout     = 5000,
            creator     = APP.developer,
            category    = 'business',
            isGame      = false,
            description = APP.description,
            age         = '18+',
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

PhoneBridge.name = pick()

local function register()
    local a = ADAPTERS[PhoneBridge.name]
    if not a or not a.register or not PhoneBridge.installed then return end
    local ok, err = pcall(a.register)
    if not ok then
        print(('^3[%s] Could not add the %s app to %s: %s. /%s still works.^7'):format(
            RES, CP.AppName, PhoneBridge.name, tostring(err), tostring(CP.Command)))
    else
        Utils.debug('phone app added to', PhoneBridge.name)
    end
end

--- called when the server says the player owns the app
function PhoneBridge.Install()
    if PhoneBridge.installed then return end
    PhoneBridge.installed = true
    if PhoneBridge.name == 'none' or PhoneBridge.name == 'standalone' then return end
    SetTimeout(1000, register)
end

function PhoneBridge.Uninstall()
    if not PhoneBridge.installed then return end
    PhoneBridge.installed = false
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.remove then pcall(a.remove) end
end

-- the phone restarted: add the app again
AddEventHandler('onResourceStart', function(res)
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.resource == res then SetTimeout(1500, register) end
end)

--- push a message to the open app (it also refreshes on open, so phones without push still update)
function PhoneBridge.Send(data)
    UI.send('phone:push', data)
    local a = ADAPTERS[PhoneBridge.name]
    if a and a.send and PhoneBridge.installed then pcall(a.send, data) end
end

--- phone banner notification, falls back to a normal notification
function PhoneBridge.Notify(title, msg, kind)
    local a = ADAPTERS[PhoneBridge.name]
    if PhoneBridge.installed and a and a.notify and pcall(a.notify, title, msg) then return end
    UI.notify(msg, kind or 'info', nil, title)
end
