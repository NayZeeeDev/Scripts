-- Quasar Smartphone PRO (qs-smartphone-pro)
-- App: addCustomApp / removeCustomApp. Notify: SendTempNotification.
-- Open state: InPhone / IsPhoneOpen.
-- No Lua to app channel: the app page gets updates over BroadcastChannel and refetches on focus.
-- No export opens a given app.
-- Docs: https://docs.quasar-store.com/player-systems/smartphone-pro/create-custom-apps

PhoneBridges = PhoneBridges or {}

local NAME = 'qs-smartphone-pro'
local APP_ID = GetCurrentResourceName()

-- PRO is also found in a folder still called qs-smartphone, so the adapter takes the resource name.
local function build(resource)
    local bridge = {
        resources = { resource },
        hasApp = true,
    }

    bridge.register = function()
        local app = Phone.App(NAME)

        Phone.Call(resource, 'removeCustomApp', APP_ID)

        local ok, added = Phone.Call(resource, 'addCustomApp', {
            app = app.id,
            label = app.name,
            ui = app.url,
            image = app.icon,
            icon = app.icon,
            description = app.description,
            creator = app.developer,
            category = 'social',
            age = '13+',
            isGame = false,
            job = false,
            blockedJobs = {},
            timeout = 5000,
            extraDescription = {},
        })

        if not ok then return false, added end
        if added == false then return false, 'refused' end

        return true
    end

    bridge.unregister = function()
        Phone.Call(resource, 'removeCustomApp', APP_ID)
    end

    bridge.notify = function(title, message)
        local ok = Phone.Call(resource, 'SendTempNotification', {
            title = title,
            text = message,
            app = Phone.HasApp() and APP_ID or nil,
            timeout = 5000,
        })

        return ok
    end

    bridge.isOpen = function()
        local ok, open = Phone.Call(resource, 'InPhone')

        if ok then return open == true end

        ok, open = Phone.Call(resource, 'IsPhoneOpen')

        return ok and open == true
    end

    return bridge
end

PhoneBridges[NAME] = build(NAME)
PhoneBridges[NAME].build = build
