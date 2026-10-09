-- NUI bridge

NUI = { ready = false, app = nil, prompt = nil, keys = false, cursor = false }

function NUI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Focus is shared between the app panel, prompts, minigames and first person cutting.
--   app / prompt : mouse + keyboard in the UI, game input off
--   cursor       : mouse in the UI, game input stays on (first person tools)
--   keys         : keyboard in the UI only (minigames, struggling)
local function refocus()
    if NUI.app or NUI.prompt then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
    elseif NUI.cursor then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)
    elseif NUI.keys then
        SetNuiFocus(true, false)
        SetNuiFocusKeepInput(false)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
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
    NUI.app = nil
    NUI.Send('app:close')
    refocus()
end

-- the side window (wig table / supplier), the same window as the sneakers script's
function NUI.Side(kind, data)
    NUI.app = kind
    NUI.Send('side:open', { kind = kind, data = data })
    refocus()
end

function NUI.CloseSide()
    if NUI.app ~= 'bench' and NUI.app ~= 'shop' and NUI.app ~= 'dye' then return end
    NUI.app = nil
    refocus()
end

function NUI.Keys(on)
    NUI.keys = on
    refocus()
end

function NUI.Cursor(on)
    NUI.cursor = on
    refocus()
end

RegisterNUICallback('ready', function(_, cb)
    NUI.ready = true
    local tiers = {}
    for i, t in ipairs(Config.Tiers) do tiers[i] = { id = t.id, label = t.label, color = t.color, lace = t.lace } end
    local grades = {}
    for i, g in ipairs(Config.Bundles.Grades) do grades[i] = { id = g.id, label = g.label } end
    local games = {}
    for id, g in pairs(Config.Minigames) do games[id] = { label = g.Label, icon = g.Icon } end
    local tools = {}
    for _, id in ipairs(ToolOrder) do
        local t = Config.Cutting.Tools[id]
        if t then tools[#tools + 1] = { id = id, label = t.Label, icon = t.Icon, mode = t.Mode, key = t.Key } end
    end
    local statuses = {}
    for id, s in pairs(Config.Products.Status) do statuses[id] = { label = s.Label, color = s.Color } end
    cb({
        version = VERSION,
        shotBase = ('https://cfx-nui-%s/'):format(Config.Studio.Resource or 'nzw_shots'),
        shotRes = Config.Studio.Resource or 'nzw_shots',
        resource = RESOURCE,
        tiers = tiers,
        grades = grades,
        games = games,
        tools = tools,
        statuses = statuses,
        prefs = Prefs.All(),
        appName = Config.Phone.AppName,
        locale = { title = L('title') },
    })
end)

-- messages from the UI (and the phone app) go out through ox_lib like every other notification
RegisterNUICallback('notify', function(d, cb)
    if type(d) == 'table' and d.message then CB.Notify(tostring(d.message), d.kind, tonumber(d.duration)) end
    cb(1)
end)

RegisterNUICallback('close', function(_, cb)
    NUI.CloseApp()
    cb(1)
end)

-- prompts (trades, haircuts, wigs put on you) ----------------------------------------------------

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
    SetNuiFocusKeepInput(false)
end)
