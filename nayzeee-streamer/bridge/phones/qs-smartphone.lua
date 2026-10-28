-- Quasar Smartphone V3 (qs-smartphone)
-- App: addCustomApp (iframe.url + JS bridge origin) / removeCustomApp. Open our app: OpenPhoneApp.
-- Notify: server export sendPhoneNotification only, so the client hands it to our server.
-- Open state: IsPhoneOpen.
-- No Lua to app channel: the app page gets updates over BroadcastChannel and refetches on focus.
-- The same folder name can hold Smartphone PRO (handled by the PRO adapter) or the classic phone
-- (no custom apps: notifications are not supported there either).
-- Docs: https://www.quasar-store.com/docs/smartphone/developer-api

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'qs-smartphone'
local APP_ID = GetCurrentResourceName()

local flavour = nil -- 'v3' | 'pro' | 'classic'
local pro = nil

-- Only V3 lists its custom apps. PRO answers InPhone.
local function probe()
    if flavour then return flavour end
    if GetResourceState(RESOURCE) ~= 'started' then return nil end

    if Phone.Call(RESOURCE, 'getCustomApps') then
        flavour = 'v3'
    elseif Phone.Call(RESOURCE, 'InPhone') then
        flavour = 'pro'
    else
        flavour = 'classic'
    end

    return flavour
end

local function proBridge()
    if not pro then
        local base = PhoneBridges['qs-smartphone-pro']

        if base and type(base.build) == 'function' then
            pro = base.build(RESOURCE)
        end
    end

    return pro
end

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = true,

    register = function()
        flavour = nil

        local using = probe()

        if using == 'pro' then
            local bridge = proBridge()

            if not bridge then return false, 'qs-smartphone-pro adapter missing' end

            return bridge.register()
        end

        if using ~= 'v3' then
            return false, 'this qs-smartphone build has no custom apps (Smartphone V3 or PRO needed)'
        end

        local app = Phone.App(RESOURCE)

        Phone.Call(RESOURCE, 'removeCustomApp', APP_ID)

        local ok, added, reason = Phone.Call(RESOURCE, 'addCustomApp', {
            id = app.id,
            label = app.name,
            icon = app.icon,
            category = 'Social', -- required since 3.2.64
            creator = app.developer,
            description = app.description,
            age = '13+',
            appStoreOnly = not app.defaultApp,
            sizeMb = 20,
            extraDescription = {},
            iframe = { url = app.url },
            custom = {
                bridge = {
                    allowedOrigins = { 'https://cfx-nui-' .. APP_ID },
                },
            },
        })

        if not ok then return false, added end
        if added == false then return false, reason or 'refused' end

        return true
    end,

    unregister = function()
        if probe() == 'pro' and proBridge() then
            return pro.unregister()
        end

        Phone.Call(RESOURCE, 'removeCustomApp', APP_ID)
    end,

    notify = function(title, message, icon)
        local using = probe()

        if using == 'pro' and proBridge() then
            return pro.notify(title, message, icon)
        end

        if using ~= 'v3' then return false end

        TriggerServerEvent('nayzeee-streamer:server:phoneNotify', { title = title, message = message, icon = icon })

        return true
    end,

    isOpen = function()
        if probe() == 'pro' and proBridge() then
            return pro.isOpen()
        end

        local ok, open = Phone.Call(RESOURCE, 'IsPhoneOpen')

        return ok and open == true
    end,

    open = function()
        if probe() ~= 'v3' then return nil end

        local ok, result = Phone.Call(RESOURCE, 'OpenPhoneApp', APP_ID)

        return ok and result ~= false
    end,
}
