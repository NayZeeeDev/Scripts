-- okokPhone (okokPhone)
-- App: loadApp. The official template runs it on both client and server; bridge/phones/server.lua
-- does the server half. No export removes an app.
-- Notify: event okokPhone:client:NotifyDI (Dynamic Island).
-- No Lua to app channel: the app page gets updates over BroadcastChannel and refetches on focus.
-- No documented export reads the open state or opens a given app, so isOpen is always false.
-- Docs: https://github.com/luxu-gg/okokphone_custom_app

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'okokPhone'
local APP_ID = GetCurrentResourceName()

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = true,

    register = function()
        local app = Phone.App(RESOURCE)
        local ok, err = Phone.Call(RESOURCE, 'loadApp', {
            id = app.id,
            label = app.name,
            description = app.description,
            custom = true,
            icon = app.icon,
            previewImagesCount = 0,
            notifications = true,
            resourceName = APP_ID,
            webUrl = app.url,
        })

        if not ok then return false, err end

        return true
    end,

    unregister = function() end,

    notify = function(title, message, icon)
        TriggerEvent('okokPhone:client:NotifyDI', {
            title = title,
            text = message,
            app = Phone.HasApp() and APP_ID or nil,
            icon = icon or Phone.App(RESOURCE).icon,
            duration = 5000,
        })

        return true
    end,

    isOpen = function()
        return false
    end,
}
