-- GKS Phone v2 (gksphone)
-- App: AddCustomApp. The official template adds it from a server script, which bridge/phones/server.lua
-- does; this client side call covers builds that take it on the client. Same name replaces the entry.
-- No export removes an app.
-- Push: NuiSendMessage (reaches the app this resource added). Notify: Notification.
-- Open state: isPhoneOpen / CheckOpenPhone. No export opens a given app.
-- Docs: https://docs.gkshop.org/gksphone-v2/custom-app

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'gksphone'
local LANGS = { 'af', 'ar', 'cs', 'de', 'en', 'es', 'fr', 'id', 'nl', 'pt-PT', 'ro', 'sv', 'th', 'tr', 'uk', 'zh-TW' }

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = true,

    register = function()
        local app = Phone.App(RESOURCE)
        local labels = {}

        for _, lang in ipairs(LANGS) do
            labels[lang] = app.name
        end

        local ok, result = Phone.Call(RESOURCE, 'AddCustomApp', {
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
            labelLangs = labels,
        })

        if ok then
            if result == false then return false, 'refused' end

            return true
        end

        -- Server only export on this build: the server already added the app.
        if tostring(result):find('No such export', 1, true) then
            return true
        end

        return false, result
    end,

    unregister = function() end,

    notify = function(title, message, icon)
        local ok = Phone.Call(RESOURCE, 'Notification', {
            title = title,
            message = message,
            icon = icon or Phone.App(RESOURCE).icon,
            duration = 5000,
            type = 'success',
            buttonactive = false,
        })

        return ok
    end,

    isOpen = function()
        local ok, open = Phone.Call(RESOURCE, 'isPhoneOpen')

        if ok then return open == true end

        ok, open = Phone.Call(RESOURCE, 'CheckOpenPhone')

        return ok and open == true
    end,

    send = function(action, data)
        local ok = Phone.Call(RESOURCE, 'NuiSendMessage', { action = action, data = data })

        return ok
    end,
}
