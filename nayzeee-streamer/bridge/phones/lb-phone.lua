-- lb-phone (LB Scripts)
-- App: AddCustomApp / RemoveCustomApp. Push: SendCustomAppMessage. Notify: SendNotification.
-- Open state: IsOpen / ToggleOpen. Open our app: OpenApp.
-- Docs: https://docs.lbscripts.com/phone/custom-apps/

PhoneBridges = PhoneBridges or {}

local RESOURCE = 'lb-phone'
local APP_ID = GetCurrentResourceName()

PhoneBridges[RESOURCE] = {
    resources = { RESOURCE },
    hasApp = true,

    register = function()
        local app = Phone.App(RESOURCE)

        -- Same identifier twice is refused, so a re-register clears the old entry first.
        Phone.Call(RESOURCE, 'RemoveCustomApp', APP_ID)

        local ok, added, err = Phone.Call(RESOURCE, 'AddCustomApp', {
            identifier = app.id,
            name = app.name,
            description = app.description,
            developer = app.developer,
            defaultApp = app.defaultApp,
            size = 20480,
            ui = app.short, -- "<resource>/<path>": lb-phone builds the https://cfx-nui- origin itself
            icon = app.icon,
            fixBlur = true,
        })

        if not ok then return false, added end
        if added == false then return false, err or 'refused' end

        return true
    end,

    unregister = function()
        Phone.Call(RESOURCE, 'RemoveCustomApp', APP_ID)
    end,

    notify = function(title, message, icon)
        local ok = Phone.Call(RESOURCE, 'SendNotification', {
            app = Phone.HasApp() and APP_ID or nil,
            title = title,
            content = message,
            thumbnail = icon,
        })

        return ok
    end,

    isOpen = function()
        local ok, open = Phone.Call(RESOURCE, 'IsOpen')

        return ok and open == true
    end,

    send = function(action, data)
        local ok = Phone.Call(RESOURCE, 'SendCustomAppMessage', APP_ID, { action = action, data = data })

        return ok
    end,

    open = function(view)
        local okState, isOpen = Phone.Call(RESOURCE, 'IsOpen')

        if not okState or isOpen ~= true then
            Phone.Call(RESOURCE, 'ToggleOpen', true, false)
        end

        local ok, result = Phone.Call(RESOURCE, 'OpenApp', APP_ID, view and { view = view } or nil)

        return ok and result ~= false
    end,
}
