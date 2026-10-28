-- RoadPhone Pro (roadphone)
-- RoadPhone has no export to add an app: the owner points AppStore.CustomApp in
-- roadphone/public/static/config/config.json at our page (the server prints the exact line).
-- We cannot tell from Lua whether that was done, so hasApp is false and our own phone frame stays.
-- Notify: event roadphone:sendNotification. Open state: isPhoneOpen.
-- No Lua to app channel: the app page gets updates over BroadcastChannel and refetches on focus.
-- Docs: https://docs.roadshop.org/roadphonepro/custom-apps

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'roadphone'

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = false,

    register = function()
        return true
    end,

    unregister = function() end,

    notify = function(title, message, icon)
        local app = Phone.App(RESOURCE)

        TriggerEvent('roadphone:sendNotification', {
            apptitle = app.name,
            title = title,
            message = message,
            img = icon or app.icon,
        })

        return true
    end,

    isOpen = function()
        local ok, open = Phone.Call(RESOURCE, 'isPhoneOpen')

        return ok and open == true
    end,
}
