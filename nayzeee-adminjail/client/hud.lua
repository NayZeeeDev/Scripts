--[[ NUI bridge — player HUD + admin panel ]]

Hud = {}

local Event = AJ.Event
local panelOpen = false

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function Hud.PanelOpen() return panelOpen end

function Hud.Show(data, avatar)
    send('hud:show', {
        sentence = data,
        avatar = avatar,
        rules = Config.Rules,
        work = Config.Work.enabled,
        key = Config.HudKey,
        cancelKey = 'X',
    })
end

function Hud.Sync(data) send('hud:sync', data) end
function Hud.Work(data) send('hud:work', data) end
function Hud.Hide() send('hud:hide') end
function Hud.Flash(kind, text) send('hud:flash', { kind = kind, text = text }) end

--- Cinematic overlays: booking, resume, release, alarm, flash
function Hud.Fx(kind, data) send('fx:' .. kind, data) end

--- Interaction prompt ("E  Sweep the floor"); nil hides it
function Hud.Prompt(label) send('prompt', label and { key = 'E', label = label } or nil) end

--- Built-in work progress
function Hud.Task(data) send('task:start', data) end
function Hud.TaskEnd(ok, data) send('task:end', { ok = ok, data = data }) end

--[[ Admin panel ]]

local requests = {
    overview = true, inmates = true, players = true, history = true,
    jail = true, release = true, adjust = true, transfer = true, teleport = true,
}

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    send('panel:close')
end

RegisterCommand(Config.Commands.panel, function()
    if panelOpen then return end
    local res = lib.callback.await(Event('server:admin:open'), false)
    if not res then
        return Bridge.Notify('Admin jail did not respond - check the server console', 'error')
    end
    if not res.ok then
        return Bridge.Notify(res.msg or locale('no_permission'), 'error')
    end
    panelOpen = true
    SetNuiFocus(true, true)
    send('panel:open', res)
end, false)

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.panel, locale('cmd_panel'))
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.jail, locale('cmd_jail'), {
    { name = 'id', help = locale('cmd_target') },
    { name = 'minutes', help = locale('cmd_minutes') },
    { name = 'reason', help = locale('cmd_reason') },
})
TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.unjail, locale('cmd_unjail'), {
    { name = 'id', help = locale('cmd_target') },
})

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb(1)
end)

RegisterNUICallback('request', function(body, cb)
    if not panelOpen or type(body) ~= 'table' or not requests[body.name] then
        return cb({ ok = false })
    end
    local res = lib.callback.await(Event('server:admin:' .. body.name), false, body.data)
    cb(res or { ok = false, msg = 'No response from server' })

    if body.name == 'teleport' and res and res.ok and res.coords then
        closePanel()
        Fx.Fade(function() Fx.Place(res.coords) end)
    end
end)

-- Escape attempts, live, for staff.
RegisterNetEvent(AJ.Event('client:staffAlert'), function(alert)
    if panelOpen then
        send('panel:alert', alert)
    else
        Bridge.Notify(locale('staff_escape', alert.name, alert.location, alert.penalty), 'error')
    end
end)

--[[ HUD collapse keybind ]]

RegisterCommand('adminjail_hud', function() send('hud:toggle') end, false)
RegisterKeyMapping('adminjail_hud', locale('hud_toggle'), 'keyboard', Config.HudKey)

AddEventHandler('onResourceStop', function(res)
    if res == AJ.Resource and panelOpen then SetNuiFocus(false, false) end
end)
