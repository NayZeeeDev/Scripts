--[[
    NAYZEEE RADIO - Admin (client): the /radioadmin window

    Config.Commands.admin asks the server for the panel data ('nzr:admin:open'). The server
    checks the permission on every call (the ace in Config.Admin, then the framework's admin
    groups); a refusal only shows a toast here. The window (NUI app 'admin', focused) saves
    through this file, which hands the server's answer straight back to the page. The chat
    suggestion for the command is only added for players the server says are admins.

      NZR.Admin.Open() → bool              NZR.Admin.CurrentVehicle() → { model, label, radio } | nil

    CALLBACKS        nzr:admin:open, nzr:admin:save ({ channels, vehicles }), nzr:admin:jammerRemove (id),
                     nzr:admin:live, nzr:admin:check (C→S, lib.callback)
    NUI SENT         admin open (the nzr:admin:open reply + current = the car the admin sits in, me = server id)
    NUI HANDLED      'admin:save' { channels, vehicles } → { ok, channels, vehicles } | { ok = false, error }
                     'admin:jammerRemove' { id } → { ok }      'admin:live' → { ok, live }
                     'admin:current' → { ok, current }        'admin:waypoint' { x, y } → { ok }
                     'admin:close' (focus released by ui.lua)
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Admin = NZR.Admin or {}
local AD = NZR.Admin

local APP = 'admin'
local opening = false

local function L(key, ...) return NZR.L('world.' .. key, ...) end

local function toast(key, kind)
    NZR.UI.Toast({ title = L('title_admin'), message = L(key), type = kind or 'error' })
end

local function await(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok then
        NZR.Debug('callback failed', name, tostring(res))
        return nil
    end
    return res
end

-- The spawn name of the car the admin sits in, for "add this car" on the Vehicles page.
function AD.CurrentVehicle()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local hash = GetEntityModel(veh)
    local name = nil
    local ok, arch = pcall(GetEntityArchetypeName, veh)
    if ok and type(arch) == 'string' and arch ~= '' then name = arch:lower() end
    if not name then
        local okD, display = pcall(GetDisplayNameFromVehicleModel, hash)
        if okD and type(display) == 'string' and display ~= '' then name = display:lower() end
    end
    if not name or name == 'carnotfound' or not name:match('^[%w_]+$') or #name > 32 then return nil end
    local label = nil
    local okD, display = pcall(GetDisplayNameFromVehicleModel, hash)
    if okD and type(display) == 'string' and display ~= '' then
        local okL, text = pcall(GetLabelText, display)
        if okL and type(text) == 'string' and text ~= '' and text ~= 'NULL' then label = text:sub(1, 32) end
    end
    local radio = NZR.Vehicle and NZR.Vehicle.IsRadioVehicle and NZR.Vehicle.IsRadioVehicle(veh) or false
    return { model = name, label = label, radio = radio }
end

function AD.Open()
    if opening or NZR.UI.IsOpen(APP) then return false end
    opening = true
    CreateThread(function()
        local res = await('nzr:admin:open')
        opening = false
        if type(res) ~= 'table' then return toast('admin_error') end
        if not res.ok then return toast(res.reason == 'busy' and 'admin_busy' or 'admin_denied') end
        if NZR.Radio.State.raised then NZR.Radio.API.Lower() end
        res.current = AD.CurrentVehicle()
        res.me = GetPlayerServerId(PlayerId())
        NZR.UI.Open(APP, res, { focus = true, cursor = true })
    end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(0)

    NZR.UI.On(APP, 'save', function(data, cb)
        CreateThread(function()
            local res = await('nzr:admin:save', { channels = data.channels, vehicles = data.vehicles })
            if type(res) ~= 'table' then res = { ok = false, error = L('admin_error') } end
            cb(res)
        end)
    end)

    NZR.UI.On(APP, 'jammerRemove', function(data, cb)
        CreateThread(function()
            local id = type(data.id) == 'string' and data.id or nil
            local res = id and await('nzr:admin:jammerRemove', id) or nil
            cb(type(res) == 'table' and res or { ok = false })
        end)
    end)

    NZR.UI.On(APP, 'live', function(_, cb)
        CreateThread(function()
            local res = await('nzr:admin:live')
            cb(type(res) == 'table' and res or { ok = false })
        end)
    end)

    NZR.UI.On(APP, 'current', function(_, cb)
        cb({ ok = true, current = AD.CurrentVehicle() })
    end)

    NZR.UI.On(APP, 'waypoint', function(data, cb)
        local x, y = tonumber(data.x), tonumber(data.y)
        if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
        cb({ ok = x ~= nil and y ~= nil })
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMMAND
-- ════════════════════════════════════════════════════════════════════════

local cmd = Config.Commands and Config.Commands.admin
if cmd then
    RegisterCommand(cmd, function()
        AD.Open()
    end, false)

    -- only admins get the chat suggestion: ask the server once the character is in
    local suggested = false
    local function suggest()
        if suggested then return end
        CreateThread(function()
            Wait(2000)
            local res = await('nzr:admin:check')
            if type(res) == 'table' and res.admin and not suggested then
                suggested = true
                TriggerEvent('chat:addSuggestion', '/' .. cmd, L('cmd_admin'), {})
            end
        end)
    end
    CreateThread(function()
        Wait(0)
        if Bridge and Bridge.OnPlayerLoaded then
            Bridge.OnPlayerLoaded(suggest, true)
        else
            suggest()
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    if NZR.UI.IsOpen(APP) then NZR.UI.Close(APP) end
end)
