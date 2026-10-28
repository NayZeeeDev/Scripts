-- Phone bridge (server).
-- Phone.NotifyPlayer(src, title, message, icon?) sends a phone notification to one player.
-- It uses the phone's server export when there is one, else the client side Phone.Notify.
-- gksphone and okokPhone also take their app from the server (as in their own templates).

if not IsDuplicityVersion() then return end

Phone = Phone or {}

if Phone.ServerLoaded then return end
Phone.ServerLoaded = true

local RES = GetCurrentResourceName()

local ORDER = { 'lb-phone', 'yseries', 'qs-smartphone-pro', 'qs-smartphone', 'npwd', 'gksphone', 'okokPhone', 'roadphone' }

-- Phones that also run under other resource names with the same API.
local ALIASES = {
    ['yseries'] = { 'yseries', 'yphone', 'yflip-phone' },
}

local LANGS = { 'af', 'ar', 'cs', 'de', 'en', 'es', 'fr', 'id', 'nl', 'pt-PT', 'ro', 'sv', 'th', 'tr', 'uk', 'zh-TW' }

local warnedUnknown = false
local hinted = {}
local buckets = {}

local function debugPrint(...)
    if type(DebugPrint) == 'function' then
        DebugPrint(...)
    end
end

local function warn(message)
    print(('^3[%s] %s^0'):format(RES, message))
end

---Calls an export of another resource without throwing.
---@return boolean ok, any ...
function Phone.Call(resource, method, ...)
    if type(resource) ~= 'string' or type(method) ~= 'string' then
        return false, 'bad_call'
    end

    if GetResourceState(resource) ~= 'started' then
        return false, 'not_started'
    end

    local count, args = select('#', ...), { ... }

    return pcall(function()
        local api = exports[resource]

        return api[method](api, table.unpack(args, 1, count))
    end)
end

local function missingExport(err)
    return tostring(err):find('No such export', 1, true) ~= nil
end

local function phoneConfig()
    local devices = Config and Config.Devices

    return (devices and type(devices.Phone) == 'table' and devices.Phone) or {}
end

local function appEnabled()
    return phoneConfig().App ~= false
end

local function encode(value)
    return (tostring(value):gsub('[^%w%-%._~]', function(char)
        return ('%%%02X'):format(char:byte())
    end))
end

-- Same app info as the client (bridge/phones/client.lua Phone.App).
local function appInfo(phone)
    local cfg = phoneConfig()
    local brand = (Config and type(Config.Brand) == 'table' and Config.Brand) or {}
    local icon = type(cfg.Icon) == 'string' and cfg.Icon ~= '' and cfg.Icon or 'html/img/app-icon.png'

    if not icon:find('^https?://') and not icon:find('^nui://') then
        icon = ('https://cfx-nui-%s/%s'):format(RES, (icon:gsub('^/+', '')))
    end

    local path = ('html/index.html?frame=phone&res=%s&phone=%s'):format(encode(RES), encode(phone or 'none'))

    return {
        id = RES,
        name = cfg.Name or brand.Name or 'Pulse',
        description = cfg.Description or 'Watch live streams and go live.',
        developer = 'NayZeee',
        defaultApp = cfg.DefaultApp ~= false,
        enabled = cfg.App ~= false,
        icon = icon,
        url = ('https://cfx-nui-%s/%s'):format(RES, path),
        nui = ('nui://%s/%s'):format(RES, path),
    }
end

local function resourcesOf(name)
    return ALIASES[name] or { name }
end

local function startedResource(name)
    for _, resource in ipairs(resourcesOf(name)) do
        if GetResourceState(resource) == 'started' then
            return resource
        end
    end

    return nil
end

local function bridgeOf(resource)
    for _, name in ipairs(ORDER) do
        for _, candidate in ipairs(resourcesOf(name)) do
            if candidate == resource then
                return name
            end
        end
    end

    return nil
end

local function wanted()
    local value = Config and Config.Phone

    if value == nil then return 'auto' end
    if value == false then return 'none' end
    if type(value) ~= 'string' then return nil end

    local lower = value:lower()

    if lower == 'auto' then return 'auto' end
    if lower == 'none' or lower == '' then return 'none' end

    for _, name in ipairs(ORDER) do
        if name:lower() == lower then return name end

        for _, resource in ipairs(resourcesOf(name)) do
            if resource:lower() == lower then return name end
        end
    end

    return nil
end

---@return string|nil name, string|nil resource
local function detect()
    local want = wanted()

    if want == nil then
        if not warnedUnknown then
            warnedUnknown = true
            warn(('Config.Phone "%s" is not a supported phone. Phone features are off.'):format(tostring(Config and Config.Phone)))
        end

        return nil
    end

    if want == 'none' then return nil end

    if want ~= 'auto' then
        local resource = startedResource(want)

        if resource then return want, resource end

        return nil
    end

    for _, name in ipairs(ORDER) do
        local resource = startedResource(name)

        if resource then return name, resource end
    end

    return nil
end

function Phone.Name()
    return (detect()) or 'none'
end

local function cut(text, limit)
    if #text <= limit then return text end

    local ok, position = pcall(utf8.offset, text, limit + 1)

    if ok and position then
        return text:sub(1, position - 1)
    end

    return text:sub(1, limit)
end

-- Plain text only: phones may render notification text as HTML.
local function clean(value, limit)
    if type(value) ~= 'string' and type(value) ~= 'number' then return '' end

    local text = tostring(value):gsub('%c', ' '):gsub('[<>]', '')

    text = text:gsub('^%s+', ''):gsub('%s+$', '')

    return cut(text, limit)
end

local function cleanIcon(icon)
    if type(icon) ~= 'string' or #icon > 512 then return nil end
    if not icon:find('^https://') and not icon:find('^nui://') then return nil end
    if icon:find('[%s"\'<>\\`]') then return nil end

    return icon
end

local function isPlayer(src)
    return type(src) == 'number' and src > 0 and GetPlayerName(src) ~= nil
end

local function relay(src, title, message, icon)
    TriggerClientEvent('nayzeee-streamer:client:phoneNotify', src, { title = title, message = message, icon = icon })

    return true
end

-- Quasar PRO notifications are addressed by phone number.
local function qsNumber(resource, src)
    local identifiers = {}

    if type(Bridge) == 'table' and type(Bridge.GetIdentifier) == 'function' then
        local ok, identifier = pcall(Bridge.GetIdentifier, src)

        if ok and identifier then identifiers[#identifiers + 1] = tostring(identifier) end
    end

    local license = GetPlayerIdentifierByType(tostring(src), 'license')

    if license then identifiers[#identifiers + 1] = license end

    local first = GetPlayerIdentifier(tostring(src), 0)

    if first then identifiers[#identifiers + 1] = first end

    for _, identifier in ipairs(identifiers) do
        local ok, number = Phone.Call(resource, 'GetPhoneNumberFromIdentifier', identifier, false)

        if ok and number and number ~= '' and number ~= 0 then
            return tostring(number)
        end
    end

    return nil
end

local function qsProNotify(resource, src, app, title, message)
    local number = qsNumber(resource, src)

    if not number then return false, 'no_number' end

    local ok, err = Phone.Call(resource, 'sendNotification', number, {
        app = app.enabled and app.id or nil,
        head = title,
        msg = message,
    }, false)

    return ok, err
end

-- One sender per phone: fn(resource, src, app, title, message, icon) -> ok, err
local SENDERS = {
    ['lb-phone'] = function(resource, src, app, title, message, icon)
        return Phone.Call(resource, 'SendNotification', src, {
            app = app.enabled and app.id or nil,
            title = title,
            content = message,
            thumbnail = icon,
        })
    end,

    ['yseries'] = function(resource, src, app, title, message, icon)
        return Phone.Call(resource, 'SendNotification', {
            app = app.enabled and app.id or nil,
            title = title,
            text = message,
            icon = icon or app.icon,
            timeout = 5000,
        }, 'source', src)
    end,

    ['qs-smartphone'] = function(resource, src, app, title, message)
        local ok, err = Phone.Call(resource, 'sendPhoneNotification', src, {
            appId = app.enabled and app.id or nil,
            title = title,
            text = message,
        })

        if ok then return true end

        -- Smartphone PRO installed in a folder still called qs-smartphone.
        if missingExport(err) then
            return qsProNotify(resource, src, app, title, message)
        end

        return false, err
    end,

    ['qs-smartphone-pro'] = function(resource, src, app, title, message)
        return qsProNotify(resource, src, app, title, message)
    end,

    -- NPWD has no server notification export.
    ['npwd'] = function(_, src, _, title, message, icon)
        return relay(src, title, message, icon)
    end,

    ['gksphone'] = function(resource, src, _, title, message, icon)
        return Phone.Call(resource, 'sendNotification', src, {
            title = title,
            message = message,
            icon = icon or appInfo('gksphone').icon,
            duration = 5000,
        })
    end,

    ['okokPhone'] = function(_, src, app, title, message, icon)
        TriggerClientEvent('okokPhone:client:NotifyDI', src, {
            title = title,
            text = message,
            app = app.enabled and app.id or nil,
            icon = icon or app.icon,
            duration = 5000,
        })

        return true
    end,

    ['roadphone'] = function(_, src, app, title, message, icon)
        TriggerClientEvent('roadphone:sendNotification', src, {
            apptitle = app.name,
            title = title,
            message = message,
            img = icon or app.icon,
        })

        return true
    end,
}

local function deliver(src, title, message, icon, allowRelay)
    if not isPlayer(src) then return false end

    local name, resource = detect()

    if not name then return false end

    local cleanTitle, cleanMessage = clean(title, 64), clean(message, 240)

    if cleanTitle == '' and cleanMessage == '' then return false end

    local app = appInfo(name)

    if cleanTitle == '' then cleanTitle = clean(app.name, 64) end

    icon = cleanIcon(icon)

    local sender = SENDERS[name]
    local ok, sent, err = pcall(sender, resource, src, app, cleanTitle, cleanMessage, icon)

    if ok and sent then return true end

    debugPrint(('Phone notify through %s failed: %s'):format(name, tostring(ok and err or sent)))

    if allowRelay then
        return relay(src, cleanTitle, cleanMessage, icon)
    end

    return false
end

---Sends a phone notification to one player.
---@param src number player server id
---@param title string
---@param message string
---@param icon string|nil https image url (for example a streamer avatar)
---@return boolean sent false when the player has no supported phone
function Phone.NotifyPlayer(src, title, message, icon)
    return deliver(tonumber(src), title, message, icon, true)
end

-- 5 notifications, refilled one every 2 s.
local function allow(src)
    local now = GetGameTimer()
    local bucket = buckets[src]

    if not bucket then
        bucket = { tokens = 5, at = now }
        buckets[src] = bucket
    end

    bucket.tokens = math.min(5, bucket.tokens + (now - bucket.at) / 2000)
    bucket.at = now

    if bucket.tokens < 1 then return false end

    bucket.tokens = bucket.tokens - 1

    return true
end

-- Client side notify for phones whose notification export is server only (yseries, Quasar V3).
-- A player can only notify themselves.
RegisterNetEvent('nayzeee-streamer:server:phoneNotify', function(data)
    local src = source

    if type(data) ~= 'table' or not allow(src) then return end

    deliver(src, data.title, data.message, data.icon, false)
end)

AddEventHandler('playerDropped', function()
    buckets[source] = nil
end)

local function labels(text)
    local out = {}

    for _, lang in ipairs(LANGS) do
        out[lang] = text
    end

    return out
end

-- gksphone and okokPhone register their apps from server scripts in their own templates.
local function registerServerApp()
    if not appEnabled() then return end

    local name, resource = detect()

    if name == 'gksphone' then
        local app = appInfo('gksphone')
        local ok, err = Phone.Call(resource, 'AddCustomApp', {
            name = app.id,
            icons = app.icon,
            categori = 'mix',
            appurl = app.url,
            url = '/customapp', -- fixed gksphone route
            blockedjobs = {},
            allowjob = {},
            signal = false,
            show = true,
            description = app.description,
            startapp = app.defaultApp,
            labelLangs = labels(app.name),
        })

        if ok then
            debugPrint('Phone: gksphone. App added on the server.')
        elseif not missingExport(err) then
            warn(('Could not add the app to gksphone: %s'):format(tostring(err)))
        end
    elseif name == 'okokPhone' then
        local app = appInfo('okokPhone')
        local ok, err = Phone.Call(resource, 'loadApp', {
            id = app.id,
            label = app.name,
            description = app.description,
            custom = true,
            icon = app.icon,
            previewImagesCount = 0,
            notifications = true,
            resourceName = RES,
            webUrl = app.url,
        })

        if ok then
            debugPrint('Phone: okokPhone. App added on the server.')
        elseif not missingExport(err) then
            warn(('Could not add the app to okokPhone: %s'):format(tostring(err)))
        end
    end
end

-- Phones we cannot add an app to from Lua: tell the owner once.
local function installHint()
    if not appEnabled() then return end

    local name = detect()

    if not name or hinted[name] then return end

    if name == 'roadphone' then
        hinted[name] = true
        print(('[%s] RoadPhone adds custom apps from its config only. In roadphone/public/static/config/config.json set:'):format(RES))
        print(('[%s]   "AppStore": { "CustomApp": { "url": "%s", "darkmode": true } }'):format(RES, appInfo('roadphone').nui))
        print(('[%s] Custom apps need RoadPhone Pro. Notifications work without it.'):format(RES))
    elseif name == 'npwd' then
        hinted[name] = true
        local command = (Config and Config.Devices and Config.Devices.Command) or 'pulse'
        print(('[%s] NPWD loads apps as React bundles, not web pages. Phone notifications work. Players open the app with /%s.'):format(RES, command))
    end
end

local function waitStarted(resource, timeout)
    local waited = 0

    while GetResourceState(resource) ~= 'started' do
        if waited >= timeout or GetResourceState(resource) == 'stopped' then
            return false
        end

        Wait(500)
        waited = waited + 500
    end

    return true
end

CreateThread(function()
    Wait(3000)

    local name = detect()

    debugPrint(('Phone: %s.'):format(name or 'none'))

    registerServerApp()
    installHint()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == RES or not bridgeOf(resource) then return end

    CreateThread(function()
        if not waitStarted(resource, 15000) then return end

        Wait(1500)

        local name, active = detect()

        if active ~= resource then return end

        debugPrint(('Phone: %s started.'):format(name))
        registerServerApp()
        installHint()
    end)
end)
