-- YSeries (TeamsGG: YPhone, YFlip). Same API under yseries, yphone and yflip-phone.
-- App: AddCustomApp / RemoveCustomApp (after GetDataLoaded). Push: SendAppMessage.
-- Notify: server export SendNotification only, so the client hands it to our server.
-- Open state: IsOpen. There is no export to open a given app.
-- Docs: https://docs.yseries.live/phone/custom-apps

PhoneBridges = PhoneBridges or {}

local NAME = 'yseries'
local RESOURCES = { 'yseries', 'yphone', 'yflip-phone' }
local APP_ID = GetCurrentResourceName()

local function resource()
    for _, name in ipairs(RESOURCES) do
        if GetResourceState(name) == 'started' then
            return name
        end
    end

    return nil
end

PhoneBridges[NAME] = {
    resources = RESOURCES,
    hasApp = true,

    register = function()
        local res = resource()

        if not res then return false, 'not_started' end

        -- AddCustomApp is dropped until the phone has loaded its data.
        local waited = 0

        while true do
            local ok, loaded = Phone.Call(res, 'GetDataLoaded')

            if ok and loaded then break end
            if not ok and tostring(loaded):find('No such export', 1, true) then break end

            if waited >= 60000 or GetResourceState(res) ~= 'started' then
                return false, 'phone data not loaded'
            end

            Wait(500)
            waited = waited + 500
        end

        local app = Phone.App(NAME)

        Phone.Call(res, 'RemoveCustomApp', APP_ID)

        local ok, result = Phone.Call(res, 'AddCustomApp', {
            key = app.id,
            name = app.name,
            description = app.description,
            defaultApp = app.defaultApp,
            ui = app.url,
            icon = { yos = app.icon, humanoid = app.icon },
        })

        if not ok then return false, result end
        if result == false then return false, 'refused' end

        return true
    end,

    unregister = function()
        local res = resource()

        if res then Phone.Call(res, 'RemoveCustomApp', APP_ID) end
    end,

    notify = function(title, message, icon)
        TriggerServerEvent('nayzeee-streamer:server:phoneNotify', { title = title, message = message, icon = icon })

        return true
    end,

    isOpen = function()
        local ok, open = Phone.Call(resource(), 'IsOpen')

        return ok and open == true
    end,

    send = function(action, data)
        local ok = Phone.Call(resource(), 'SendAppMessage', APP_ID, { action = action, data = data })

        return ok
    end,
}
