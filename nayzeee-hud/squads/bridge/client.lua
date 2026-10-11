-- Part of the squads module (nayzeee-squads), merged into nayzeee-hud.
if not SquadsConfig.Enabled then return end

-- Framework bridge (client). Reports downed state and performs the actual revive.
Bridge = {}

local downed = false

function Bridge.IsDowned() return downed end

local function setDowned(state)
    state = state == true
    if downed == state then return end
    downed = state
    TriggerServerEvent('nz_squads:setDowned', state)
end

Bridge.SetDowned = setDowned

if GetResourceState('es_extended') ~= 'missing' then
    AddEventHandler('esx:onPlayerDeath', function() setDowned(true) end)
    AddEventHandler('esx:onPlayerSpawn', function() setDowned(false) end)
    RegisterNetEvent('esx_ambulancejob:revive', function() setDowned(false) end)
elseif GetResourceState('qbx_core') ~= 'missing' or GetResourceState('qb-core') ~= 'missing' then
    RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
        local md = data and data.metadata
        if md then setDowned(md.isdead or md.inlaststand) end
    end)
end

-- fallback for servers with no ambulance job wired in
CreateThread(function()
    while true do
        Wait(1000)
        if IsPedDeadOrDying(PlayerPedId(), true) then
            if not downed then setDowned(true) end
        elseif downed and GetEntityHealth(PlayerPedId()) > 101 then
            setDowned(false)
        end
    end
end)

--- Called by the server once a revive is approved.
RegisterNetEvent('nz_squads:client:revive', function(health)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    if GetResourceState('es_extended') ~= 'missing' then
        TriggerEvent('esx_ambulancejob:revive')
    end

    if IsPedDeadOrDying(ped, true) then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    end

    local max = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.floor(100 + (max - 100) * (math.min(100, health or 50) / 100)))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    SetPlayerInvincible(PlayerId(), false)
    setDowned(false)
end)

-- ─── notifications ─────────────────────────────────────────
-- Every squad notification goes through Bridge.Notify, so this is the one place to point them
-- at a different system. SquadsConfig.Notify.System picks which one.
--   kind: 'info' | 'success' | 'error' | 'warning'
local N = SquadsConfig.Notify
local ESX, QB
local system

local function resolveSystem()
    local want = N.System
    if want ~= 'auto' then return want end
    if GetResourceState(N.NayzeeeResource) == 'started' then return 'nayzeee' end
    return 'ox_lib' -- nayzeee-hud: the squad UI's own toast box is off unless System = 'builtin'
end

local adapters = {
    -- the squad UI's own toasts
    builtin = function(title, text, kind, duration)
        SendNUIMessage({ action = 'toast', data = { title = title, text = text, kind = kind, duration = duration, native = true } })
    end,

    -- NayZeee Notify. Change this call if your notify resource exposes a different export.
    nayzeee = function(title, text, kind, duration)
        exports[N.NayzeeeResource]:Notify({ title = title, message = text, type = kind, duration = duration })
    end,

    ox_lib = function(title, text, kind, duration)
        local map = { info = 'inform', success = 'success', error = 'error', warning = 'warning' }
        lib.notify({ title = title, description = text, type = map[kind] or 'inform', duration = duration, position = N.Position })
    end,

    esx = function(title, text, kind, duration)
        ESX = ESX or exports['es_extended']:getSharedObject()
        ESX.ShowNotification(('%s: %s'):format(title, text), kind == 'error' and 'error' or (kind == 'success' and 'success' or 'info'), duration)
    end,

    qb = function(title, text, kind, duration)
        QB = QB or exports['qb-core']:GetCoreObject()
        local map = { info = 'primary', success = 'success', error = 'error', warning = 'warning' }
        QB.Functions.Notify(('%s: %s'):format(title, text), map[kind] or 'primary', duration)
    end,

    qbx = function(title, text, kind, duration)
        local map = { info = 'inform', success = 'success', error = 'error', warning = 'warning' }
        exports.qbx_core:Notify(text, map[kind] or 'inform', duration, title)
    end,

    okok = function(title, text, kind, duration)
        exports['okokNotify']:Alert(title, text, duration, kind == 'warning' and 'warning' or kind, false)
    end,

    mythic = function(title, text, kind, duration)
        local map = { info = 'inform', success = 'success', error = 'error', warning = 'error' }
        exports['mythic_notify']:DoHudText(map[kind] or 'inform', ('%s: %s'):format(title, text))
    end,

    -- no squad notifications at all
    none = function() end,

    -- Your own system: replace the body of this function.
    custom = function(title, text, kind, duration)
        TriggerEvent('chat:addMessage', { args = { title, text } })
    end,
}

function Bridge.NotifySystem()
    system = system or resolveSystem()
    return system
end

function Bridge.Notify(title, text, kind, duration)
    local fn = adapters[Bridge.NotifySystem()] or adapters.builtin
    local ok, err = pcall(fn, title or 'Squads', text or '', kind or 'info', duration or N.Duration)
    if not ok then
        -- a missing export or a typo in the system name should never swallow the message
        print(('^3[nayzeee-squads]^7 Notify system "%s" failed (%s), using the built-in toasts.'):format(system, err))
        system = 'builtin'
        adapters.builtin(title, text, kind, duration or N.Duration)
    end
end
