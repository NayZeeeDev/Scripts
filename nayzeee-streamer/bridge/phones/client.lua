-- Phone bridge (client).
-- Finds the phone, adds the app to it, and sends phone notifications.
--
-- Each bridge/phones/<phone>.lua file fills PhoneBridges['<phone>'] with:
--   resources  = { 'name', ... }   resource names the adapter answers to (default { '<phone>' })
--   hasApp     = bool              false when the phone cannot host our page from Lua
--   register   = fn() -> ok, err   add the app (runs after the phone started)
--   unregister = fn()              remove the app
--   notify     = fn(title, message, icon?) -> bool
--   isOpen     = fn() -> bool
--   send       = fn(action, data) -> bool   (left out when the phone has no Lua to app channel)
--   open       = fn(view?) -> bool          (left out when the phone cannot open an app from Lua)
--
-- Phone API for the rest of the client:
--   Phone.Name()                    active phone name, or 'none'
--   Phone.Resource()                resource name of the active phone, or nil
--   Phone.Register(force?)          add the app (also runs by itself once the player is loaded)
--   Phone.HasApp()                  true when our app is in the active phone
--   Phone.Notify(title, message, icon?) -> bool   false when there is no phone
--   Phone.IsOpen() -> bool
--   Phone.Open(view?) -> true | nil  nil when the phone cannot open our app (use our own phone frame)
--   Phone.Send(action, data) -> bool | nil
--       Pushes a { action, data } message into the app page, the same shape as SendNUIMessage.
--       Only lb-phone, yseries and gksphone have this channel. The root NUI page also relays its
--       messages to the phone page over BroadcastChannel('nayzeee-streamer'), and the phone page
--       refetches on focus, so this is a best-effort extra and never required.
--   Phone.App(phone?)               app info (id, name, description, icon, url, nui, short, ...)
--   Phone.Call(resource, export, ...) -> ok, ...   guarded export call

if IsDuplicityVersion() then return end

PhoneBridges = PhoneBridges or {}
Phone = Phone or {}

if Phone.ClientLoaded then return end
Phone.ClientLoaded = true

local RES = GetCurrentResourceName()

-- Detection order for Config.Phone = 'auto'.
local ORDER = { 'lb-phone', 'yseries', 'qs-smartphone-pro', 'qs-smartphone', 'npwd', 'gksphone', 'okokPhone', 'roadphone' }

-- Messages the phone page never needs (root frame only, or sent many times a second).
local SKIP_SEND = {
    ['stream:light'] = true,
    ['placement'] = true,
    ['booth:ready'] = true,
    ['booth:end'] = true,
    ['hud'] = true,
    ['gear:panel'] = true,
    ['gear:panelClose'] = true,
    ['deck:open'] = true,
    ['deck:close'] = true,
    ['chat:focus'] = true,
}

local registeredFor = nil -- phone the app setup ran for
local appAdded = false    -- true when the phone accepted our app
local registering = false
local playerLoaded = false
local warnedUnknown = false

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

-- Runs an adapter function. Returns the adapter's own results, or false and the error.
local function run(fn, ...)
    if type(fn) ~= 'function' then
        return false, 'unsupported'
    end

    local ok, first, second = pcall(fn, ...)

    if not ok then
        return false, first
    end

    return first, second
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

---App info used by every adapter.
---@param phone string|nil phone name, passed to the page as ?phone=
function Phone.App(phone)
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
        accent = brand.Accent or '#08afa2',
        defaultApp = cfg.DefaultApp ~= false,
        icon = icon,
        path = path,
        url = ('https://cfx-nui-%s/%s'):format(RES, path), -- full https form
        nui = ('nui://%s/%s'):format(RES, path),           -- nui:// form
        short = ('%s/%s'):format(RES, path),               -- "<resource>/<path>" form
    }
end

local function resourcesOf(name)
    local bridge = PhoneBridges[name]

    if bridge and type(bridge.resources) == 'table' and #bridge.resources > 0 then
        return bridge.resources
    end

    return { name }
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
    end

    for _, name in ipairs(ORDER) do
        for _, resource in ipairs(resourcesOf(name)) do
            if resource:lower() == lower then return name end
        end
    end

    return nil
end

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
        if PhoneBridges[want] and startedResource(want) then
            return want
        end

        return nil
    end

    for _, name in ipairs(ORDER) do
        if PhoneBridges[name] and startedResource(name) then
            return name
        end
    end

    return nil
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

function Phone.Name()
    return detect() or 'none'
end

function Phone.Resource()
    local name = detect()

    return name and startedResource(name) or nil
end

function Phone.HasApp()
    return appAdded and registeredFor ~= nil and startedResource(registeredFor) ~= nil
end

---Adds the app to the active phone. Safe to call more than once.
---@param force boolean|nil run again even if it already ran for this phone
function Phone.Register(force)
    local name = detect()

    if not name then return false end
    if registering then return true end
    if registeredFor == name and not force then return true end

    registering = true

    CreateThread(function()
        local bridge = PhoneBridges[name]

        -- The phone's exports show up a moment after it starts.
        Wait(1500)

        if not bridge or not startedResource(name) then
            registering = false
            return
        end

        if not appEnabled() or bridge.hasApp == false then
            registeredFor, appAdded = name, false
            registering = false
            debugPrint(('Phone: %s (notifications only).'):format(name))
            return
        end

        local ok, err = false, nil

        for attempt = 1, 4 do
            ok, err = run(bridge.register)

            if ok or not startedResource(name) then break end

            Wait(2000 * attempt)
        end

        if ok then
            registeredFor, appAdded = name, true
            debugPrint(('Phone: %s. App added.'):format(name))
        else
            registeredFor, appAdded = nil, false
            warn(('Could not add the app to %s: %s'):format(name, tostring(err)))
        end

        registering = false
    end)

    return true
end

---Shows a notification on the player's phone.
---@return boolean sent false when there is no phone or it refused
function Phone.Notify(title, message, icon)
    local name = detect()

    if not name then return false end

    local bridge = PhoneBridges[name]
    local cleanTitle, cleanMessage = clean(title, 64), clean(message, 240)

    if cleanTitle == '' and cleanMessage == '' then return false end
    if cleanTitle == '' then cleanTitle = clean(Phone.App(name).name, 64) end

    return run(bridge.notify, cleanTitle, cleanMessage, cleanIcon(icon)) == true
end

function Phone.IsOpen()
    local name = detect()

    if not name then return false end

    return run(PhoneBridges[name].isOpen) == true
end

---Opens our app inside the phone.
---@param view string|nil route to show
---@return true|nil opened nil when the phone cannot open it
function Phone.Open(view)
    local name = detect()

    if not name or not Phone.HasApp() or registeredFor ~= name then return nil end

    local bridge = PhoneBridges[name]

    if type(bridge.open) ~= 'function' then return nil end
    if type(view) ~= 'string' or view == '' then view = nil end

    if run(bridge.open, view) ~= true then return nil end

    if view then
        SetTimeout(600, function()
            Phone.Send('open', { device = 'phone', view = view })
        end)
    end

    return true
end

---Pushes a message into the app page (best effort, see the header).
---@return boolean|nil sent nil when the phone has no push channel
function Phone.Send(action, data)
    if type(action) ~= 'string' or SKIP_SEND[action] then return false end
    if not Phone.HasApp() then return false end

    local bridge = PhoneBridges[registeredFor]

    if not bridge or type(bridge.send) ~= 'function' then return nil end

    return run(bridge.send, action, data) == true
end

-- Server asks for a phone notification (phones without a server export, or a failed one).
RegisterNetEvent('nayzeee-streamer:client:phoneNotify', function(data)
    if type(data) ~= 'table' then return end

    Phone.Notify(data.title, data.message, data.icon)
end)

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

AddEventHandler('onResourceStart', function(resource)
    if resource == RES then return end

    local name = bridgeOf(resource)

    if not name then return end

    -- Our phone restarted: its app list is fresh, so the app goes in again.
    if name == registeredFor then
        registeredFor, appAdded = nil, false
    end

    CreateThread(function()
        if not waitStarted(resource, 15000) then return end

        if playerLoaded and detect() ~= registeredFor then
            Phone.Register()
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RES then
        if appAdded and registeredFor and PhoneBridges[registeredFor] then
            run(PhoneBridges[registeredFor].unregister)
        end

        return
    end

    local name = bridgeOf(resource)

    if not name or name ~= registeredFor then return end

    registeredFor, appAdded = nil, false

    -- With 'auto' another phone may still be running.
    SetTimeout(1000, function()
        if playerLoaded and detect() then
            Phone.Register()
        end
    end)
end)

local function onLoaded()
    playerLoaded = true
    Phone.Register()
end

local function isLoaded()
    if type(Bridge) ~= 'table' or type(Bridge.IsLoaded) ~= 'function' then
        return false
    end

    local ok, loaded = pcall(Bridge.IsLoaded)

    return ok and loaded == true
end

-- Hook into the framework bridge once every file of the resource has loaded.
CreateThread(function()
    if type(Bridge) ~= 'table' or type(Bridge.OnLoaded) ~= 'function' then
        onLoaded()
        return
    end

    pcall(Bridge.OnLoaded, onLoaded)

    if type(Bridge.OnUnloaded) == 'function' then
        pcall(Bridge.OnUnloaded, function()
            playerLoaded = false
        end)
    end

    -- Resource restart while the player is already loaded.
    for _, delay in ipairs({ 0, 2000, 3000 }) do
        Wait(delay)

        if playerLoaded then return end

        if isLoaded() then
            onLoaded()
            return
        end
    end
end)
