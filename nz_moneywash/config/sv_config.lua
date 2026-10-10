--[[ THE WASH — server-only configuration (never sent to clients) ]]

SvConfig = {}

-- Discord webhook for laundering logs ('' = off)
SvConfig.Webhook = ''
SvConfig.WebhookName = 'THE WASH'
SvConfig.WebhookColour = 569250 -- #08afa2

--[[
    Dispatch hook. Return true if you handled it, otherwise the built-in alert
    (NUI toast + temporary blip for every on-duty police job) is used.

    data = { coords = vector3, title = string, message = string, code = string }

    Example (ps-dispatch, server side):
        SvConfig.Dispatch = function(data)
            exports['ps-dispatch']:CustomAlert({ coords = data.coords, message = data.title,
                description = data.message, code = data.code, icon = 'fas fa-money-bill-wave',
                jobs = { 'leo' }, alert = { radius = 0, sprite = 500, color = 2, scale = 1.0, length = 3, flash = false } })
            return true
        end
]]
SvConfig.Dispatch = nil
