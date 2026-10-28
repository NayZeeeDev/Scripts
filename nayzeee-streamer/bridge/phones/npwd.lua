-- NPWD (Project Error)
-- NPWD renders apps as React bundles inside its own page (Module Federation in v3, IIFE bundles
-- in v4), not as iframes, and has no export to add a web page app. So only notifications and the
-- open state are supported. Players open the app with the command or keybind instead.
-- Notify: createSystemNotification (createNotification needs an app NPWD knows).
-- Open state: isPhoneVisible.
-- Docs: https://projecterror.dev/docs/npwd/dev/setup

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'npwd'
local APP_ID = GetCurrentResourceName()

local counter = 0

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = false,

    register = function()
        return true
    end,

    unregister = function() end,

    notify = function(title, message)
        counter = counter + 1

        local ok = Phone.Call(RESOURCE, 'createSystemNotification', {
            uniqId = ('%s:%d:%d'):format(APP_ID, GetGameTimer(), counter),
            content = message ~= '' and message or title,
            secondaryTitle = title,
            keepOpen = false,
            duration = 5000,
        })

        return ok
    end,

    isOpen = function()
        local ok, open = Phone.Call(RESOURCE, 'isPhoneVisible')

        return ok and open == true
    end,
}
