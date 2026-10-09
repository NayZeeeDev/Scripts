--[[ NUI bridge — player HUD + admin panel ]]

Hud = {}

local Event = AJ.Event
local panelOpen = false

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function Hud.PanelOpen() return panelOpen end

function Hud.Show(data)
    send('hud:show', {
        sentence = data,
        rules = Config.Rules,
        work = Config.Work.enabled,
        key = Config.HudKey,
    })
end

function Hud.Sync(data) send('hud:sync', data) end
function Hud.Work(data) send('hud:work', data) end
function Hud.Hide() send('hud:hide') end
function Hud.Flash(kind, text) send('hud:flash', { kind = kind, text = text }) end

--[[ Admin panel ]]

local requests = {
    overview = true, inmates = true, players = true, history = true,
    jail = true, release = true, adjust = true, transfer = true,
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
    if not res or not res.ok then
        return Bridge.Notify(res and res.msg or locale('no_permission'), 'error')
    end
    panelOpen = true
    SetNuiFocus(true, true)
    send('panel:open', res)
end, false)

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.panel, locale('cmd_panel'))

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
end)

--[[ HUD collapse keybind ]]

RegisterCommand('adminjail_hud', function() send('hud:toggle') end, false)
RegisterKeyMapping('adminjail_hud', locale('hud_toggle'), 'keyboard', Config.HudKey)

AddEventHandler('onResourceStop', function(res)
    if res == AJ.Resource and panelOpen then SetNuiFocus(false, false) end
end)
