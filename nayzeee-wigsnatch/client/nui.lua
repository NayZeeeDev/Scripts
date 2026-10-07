-- NUI bridge

NUI = { ready = false, app = nil, prompt = nil, keys = false }

function NUI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Focus is shared between the app panel, prompts and the clash.
local function refocus()
    if NUI.app or NUI.prompt then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
    elseif NUI.keys then
        SetNuiFocus(true, false)
        SetNuiFocusKeepInput(false)
    else
        SetNuiFocus(false, false)
    end
end
NUI.Refocus = refocus

function NUI.Open(view, data)
    NUI.app = view
    NUI.Send('app:open', { view = view, data = data })
    refocus()
end

function NUI.CloseApp()
    if not NUI.app then return end
    local was = NUI.app
    NUI.app = nil
    NUI.Send('app:close')
    refocus()
    if was == 'cuts' and Tools.PickerId then
        TriggerServerEvent('nz-wig:s:toolCancel', Tools.PickerId)
        Tools.PickerId = nil
    end
end

function NUI.Keys(on)
    NUI.keys = on
    refocus()
end

RegisterNUICallback('ready', function(_, cb)
    NUI.ready = true
    local tiers = {}
    for i, t in ipairs(Config.Tiers) do tiers[i] = { id = t.id, label = t.label, color = t.color, lace = t.lace } end
    cb({
        version = VERSION,
        tiers = tiers,
        notifyPosition = Config.NotifyPosition,
        clashKey = Config.Clash.Key,
        locale = {
            title = L('title'),
        },
    })
end)

RegisterNUICallback('close', function(_, cb)
    NUI.CloseApp()
    cb(1)
end)

-- prompts (trade offers, haircut requests) -------------------------------------------------------

RegisterNetEvent('nz-wig:c:prompt', function(data)
    NUI.prompt = data
    NUI.Send('prompt:open', data)
    refocus()
end)

RegisterNetEvent('nz-wig:c:promptClose', function(id)
    if NUI.prompt and NUI.prompt.id == id then
        NUI.prompt = nil
        NUI.Send('prompt:close')
        refocus()
    end
end)

RegisterNUICallback('promptReply', function(d, cb)
    local p = NUI.prompt
    NUI.prompt = nil
    refocus()
    if p and d and d.id == p.id then
        TriggerServerEvent('nz-wig:s:promptReply', p.kind, p.id, d.accept == true)
    end
    cb(1)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    SetNuiFocus(false, false)
end)
