Me = { isStaff = false, perms = {} }
local permSet, allPerms = {}, false
UI = { open = false, mode = nil }

function Can(perm)
    if not Me.isStaff then return false end
    return allPerms or permSet[perm] == true
end

function Notify(msg, kind, title) Bridge.Notify(msg, kind, title) end

function NUI(type, data)
    SendNUIMessage({ type = type, data = data })
end

--- Server call with the panel router. Returns ok, data|err
function RPC(name, data)
    local res = lib.callback.await('nzadmin:rpc', false, name, data)
    if not res then return false, 'No response' end
    return res.ok, res.ok and res.data or res.err
end

-- ─── settings (saved on the player's PC) ────────────────────────────────
Settings = { scale = Config.UI.Scale, sounds = Config.UI.Sounds, coordsPos = 'top-center', inspectorPos = 'right', noclipPos = 'bottom-center', chatPos = 'bottom-right', autoDuty = Config.DefaultDuty }
do
    local raw = GetResourceKvpString('nzadmin:settings')
    if raw then
        local ok, s = pcall(json.decode, raw)
        if ok and type(s) == 'table' then for k, v in pairs(s) do Settings[k] = v end end
    end
end

-- ─── staff payload ──────────────────────────────────────────────────────
RegisterNetEvent('nzadmin:cl:staff', function(p)
    local was = Me.isStaff
    Me = p
    permSet, allPerms = {}, false
    for _, perm in ipairs(p.perms or {}) do
        if perm == '*' then allPerms = true else permSet[perm] = true end
    end
    if not p.isStaff then
        if UI.open and UI.mode ~= 'report' then CloseUI() end
        if was then StopAllToggles() end
    elseif not was and Settings.autoDuty == false and p.duty then
        RPC('staff:duty', { state = false })
    end
    NUI('staff', p)
end)

RegisterNetEvent('nzadmin:cl:duty', function(state, outfit)
    Notify(state and 'You are on duty.' or 'You are off duty.', state and 'success' or 'info', 'Staff')
    if outfit then
        if state then Bridge.SetAppearance(outfit) else Bridge.ReloadSkin() end
    end
    if not state then StopAllToggles() end
end)

lib.callback.register('nzadmin:getAppearance', function() return Bridge.GetAppearance() end)

RegisterNetEvent('nzadmin:cl:notify', function(msg, kind, title) Notify(msg, kind, title) end)

-- ─── key labels ─────────────────────────────────────────────────────────
-- The key a player actually bound to a command (they can rebind in GTA settings).
-- Only read when a menu opens, never in a loop.
function KeyLabel(command)
    local ok, raw = pcall(GetControlInstructionalButton, 0, joaat(command) | 0x80000000, true)
    if not ok or type(raw) ~= 'string' or not raw:find('^t_') then return nil end
    return raw:sub(3)
end

local function keyLabels()
    local out = {}
    for k, c in pairs(Config.Commands) do
        if c.enabled and c.key ~= nil then out[k] = KeyLabel(c.name) or (c.key or nil) end
    end
    return out
end

-- ─── panel open / close ─────────────────────────────────────────────────
function OpenPanel(page, extra)
    if not Me.isStaff or not Can('self.panel') then return end
    UI.open, UI.mode = true, 'panel'
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    NUI('open', { mode = 'panel', page = page, extra = extra, settings = Settings, toggles = Toggles, me = Me, keys = keyLabels(), binds = BindLabels and BindLabels() or {} })
end

function OpenQuick()
    if not Me.isStaff or not Can('self.quickmenu') then return end
    UI.open, UI.mode = true, 'quick'
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    NUI('open', { mode = 'quick', settings = Settings, toggles = Toggles, me = Me, teleports = Teleports.quick, keys = keyLabels() })
end

function CloseUI()
    UI.open, UI.mode = false, nil
    SetNuiFocus(false, false)
    NUI('close')
end

RegisterNUICallback('close', function(_, cb) CloseUI(); cb(1) end)

RegisterNUICallback('rpc', function(body, cb)
    local ok, data = RPC(body.name, body.data)
    if ok and body.name == 'vehicles:world' and type(data) == 'table' then
        for _, v in ipairs(data) do v.model = GetDisplayNameFromVehicleModel(v.hash):lower(); v.label = GetLabelText(GetDisplayNameFromVehicleModel(v.hash)) end
    end
    cb({ ok = ok, data = ok and data or nil, err = not ok and data or nil })
end)

RegisterNUICallback('saveSettings', function(s, cb)
    if type(s) == 'table' then for k, v in pairs(s) do Settings[k] = v end end
    SetResourceKvp('nzadmin:settings', json.encode(Settings))
    cb(1)
end)

-- server pushes (logs, chat messages, reports, console...) go straight to the panel
RegisterNetEvent('nzadmin:cl:push', function(kind, data)
    if kind == 'report:new' then
        Notify(('%s: %s'):format(data.player, (data.message or ''):sub(1, 80)), 'warning', 'New report #' .. data.id)
    end
    NUI('push', { kind = kind, data = data })
end)

-- ─── local actions from the panel ───────────────────────────────────────
local Local = {}
LocalActions = Local

RegisterNUICallback('local', function(body, cb)
    local fn = Local[body.action]
    if not fn then return cb({ ok = false, err = 'Unknown' }) end
    local ok, res = pcall(fn, body.data or {})
    if not ok then print('^1[nayzeee-admin]^7 ' .. tostring(res)); return cb({ ok = false, err = 'Client error' }) end
    if res == false then return cb({ ok = false }) end
    cb({ ok = true, data = res })
end)

local modelCache
Local.vehicleModels = function()
    if modelCache then return modelCache end
    local out = {}
    for _, m in ipairs(GetAllVehicleModels()) do
        local hash = joaat(m)
        local disp = GetDisplayNameFromVehicleModel(hash)
        local label = GetLabelText(disp)
        if label == 'NULL' then label = disp end
        local make = GetLabelText(GetMakeNameFromVehicleModel(hash))
        out[#out + 1] = { model = m:lower(), label = label, make = make ~= 'NULL' and make or '', class = GetVehicleClassFromName(hash) }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    modelCache = out
    return out
end

Local.copy = function(d) lib.setClipboard(d.text or ''); return true end

Local.myCoords = function()
    local c = GetEntityCoords(cache.ped)
    return { x = NZ.Round(c.x), y = NZ.Round(c.y), z = NZ.Round(c.z), w = NZ.Round(GetEntityHeading(cache.ped)) }
end

Local.focus = function(d)
    -- release the mouse for in-world tools without closing the panel state
    SetNuiFocus(d.on and true or false, d.on and true or false)
    return true
end

-- ─── announcements / warnings / messages ────────────────────────────────
RegisterNetEvent('nzadmin:cl:announce', function(p) NUI('announce', p) end)
RegisterNetEvent('nzadmin:cl:warned', function(p)
    NUI('warned', p)
    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
end)
RegisterNetEvent('nzadmin:cl:staffMessage', function(p) NUI('staffMessage', p) end)
RegisterNetEvent('nzadmin:cl:staffChat', function(p)
    if not Me.isStaff or type(p) ~= 'table' then return end
    Notify(p.message, 'info', ('Staff · %s'):format(p.from or '?'))
    NUI('push', { kind = 'staffchat', data = p })
end)

-- ─── player reports (everyone) ──────────────────────────────────────────
function OpenReport()
    if UI.open then return end
    UI.open, UI.mode = true, 'report'
    SetNuiFocus(true, true)
    NUI('open', { mode = 'report', settings = Settings })
end

RegisterNetEvent('nzadmin:cl:report', function(kind, data)
    NUI('report', { kind = kind, data = data })
    if kind == 'message' and not UI.open then Notify(data.message:sub(1, 90), 'info', 'Staff replied to your report') end
    if kind == 'closed' then Notify('Your report was closed by ' .. (data.by or 'staff') .. '.', 'info', 'Report') end
end)

-- ─── commands + keys ────────────────────────────────────────────────────
local C = Config.Commands
local function cmd(key, fn, desc)
    local c = C[key]
    if not c or not c.enabled then return end
    RegisterCommand(c.name, fn, false)
    if c.key ~= nil then RegisterKeyMapping(c.name, desc, 'keyboard', c.key or '') end
end

cmd('panel', function() if UI.open then CloseUI() else OpenPanel() end end, 'Admin: open panel')
cmd('quick', function() if UI.open then CloseUI() else OpenQuick() end end, 'Admin: quick menu')
cmd('palette', function() if UI.open and UI.mode == 'report' then return end OpenPanel(nil, { palette = true }) end, 'Admin: search')
cmd('report', function() if Config.Reports.Enabled then OpenReport() end end, 'Open a report')
cmd('sentence', function() TriggerServerEvent('nzadmin:sv:sentence') end, 'Check jail time')
cmd('spectate', function(_, a)
    if not Can('player.spectate') then return end
    local id = tonumber(a[1])
    if not id then return Notify('Usage: /' .. C.spectate.name .. ' id', 'error') end
    CreateThread(function()
        local ok, err = RPC('player:spectate', { id = id })
        if not ok then Notify(err, 'error') end
    end)
end, 'Spectate')
cmd('admincar', function()
    if not Can('vehicles.give') then return end
    if not cache.vehicle then return Notify('Sit in a vehicle first.', 'error') end
    TriggerServerEvent('nzadmin:sv:admincar', lib.getVehicleProperties(cache.vehicle), GetDisplayNameFromVehicleModel(GetEntityModel(cache.vehicle)):lower())
end, 'Save vehicle to garage')
cmd('car', function(_, a)
    if not Can('vehicles.spawn') then return end
    local model = a[1]
    if not model then return Notify('Usage: /' .. C.car.name .. ' model', 'error') end
    CreateThread(function()
        local ok, err = RPC('vehicles:spawn', { model = model, keep = false })
        if not ok then Notify(err, 'error') end
    end)
end, 'Admin: spawn vehicle')
cmd('dv', function() if Me.isStaff then if not LocalActions.vehDelete() then Notify('No vehicle near you.', 'error') end end end, 'Admin: delete vehicle')
cmd('fix', function() if Me.isStaff then if not LocalActions.vehRepair() then Notify('Sit in a vehicle first.', 'error') end end end, 'Admin: repair vehicle')

RegisterNetEvent('nzadmin:cl:sentence', function(info)
    if not info then return Notify('You are not in jail.', 'info') end
    Notify(('%s left · %s'):format(NZ.FormatDuration(info.remaining), info.reason), 'warning', 'Jail')
end)

-- ─── ready ──────────────────────────────────────────────────────────────
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(1500)
    TriggerServerEvent('nzadmin:sv:ready')
    NUI('config', { accent = Config.UI.Accent, danger = Config.UI.Danger, version = NZ.Version, locale = Locales and Locales.ui or {} })
end)

RegisterNetEvent('esx:playerLoaded', function() TriggerServerEvent('nzadmin:sv:loaded') end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() TriggerServerEvent('nzadmin:sv:loaded') end)

AddEventHandler('onResourceStop', function(r)
    if r ~= NZ.Resource then return end
    if UI.open then SetNuiFocus(false, false) end
    -- don't leave staff stuck invisible, frozen or in noclip after a restart
    if StopAllToggles then pcall(StopAllToggles) end
end)
