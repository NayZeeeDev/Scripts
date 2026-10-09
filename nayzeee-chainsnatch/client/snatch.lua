-----------------------------------------------------------------
-- Snatching (client): asking, and the tug of war.
-- Input is read here, the server decides who wins.
-----------------------------------------------------------------

Snatch = { tug = nil }

local cfg = Config.Snatch
local ANIM_PULL = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 }
local ANIM_HOLD = { dict = 'anim@mp_player_intuppersurrender', clip = 'idle_a', flag = 49 }

local function canTarget(ped)
    if not cfg.Enabled or Snatch.tug or Place.active() then return false end
    if ped == PlayerPedId() or not IsPedAPlayer(ped) then return false end
    if not cfg.AllowInVehicle and (IsPedInAnyVehicle(PlayerPedId(), false) or IsPedInAnyVehicle(ped, false)) then return false end
    return WornProps.of(ped) ~= nil or Clothing.has(ped)
end
Snatch.canTarget = canTarget

function Snatch.request(ped)
    if Snatch.tug then return CB.Notify(Config.Text.busy, 'error') end
    if Config.IsInNoSnatchZone(GetEntityCoords(PlayerPedId())) then return CB.Notify(Config.Text.protected, 'error') end
    local sid = Util.serverIdOf(ped)
    if sid then TriggerServerEvent('nzc:s:snatch', sid) end
end

if cfg.Enabled then
    CB.AddPlayerOptions({
        {
            name = 'nzc_snatch', label = cfg.TargetLabel, icon = 'fa-solid fa-gem', distance = cfg.Distance,
            canInteract = canTarget,
            onSelect = function(entity) Snatch.request(entity) end,
        },
    })

    if cfg.Command then
        RegisterCommand(cfg.Command, function()
            local ped = Util.closestInFront(cfg.Distance)
            if not ped then return CB.Notify(Config.Text.no_target, 'error') end
            if not canTarget(ped) then return CB.Notify(Config.Text.nothing_to_take, 'error') end
            Snatch.request(ped)
        end, false)
        if cfg.Keybind then RegisterKeyMapping(cfg.Command, 'Snatch a chain', 'keyboard', cfg.Keybind) end
    end
end

-----------------------------------------------------------------
-- tug of war
-----------------------------------------------------------------

RegisterNetEvent('nzc:c:tugStart', function(d)
    if Snatch.tug then return end
    Snatch.tug = d
    if Hold.active() then Hold.stop(false) end
    if Menu.open then Menu.close() end
    local me = PlayerPedId()
    local opp = Util.pedOf(d.oppSrc)
    if opp ~= 0 and DoesEntityExist(opp) then Util.face(me, opp) end
    FreezeEntityPosition(me, true)
    local a = d.role == 'snatcher' and ANIM_PULL or ANIM_HOLD
    if Util.loadDict(a.dict) then TaskPlayAnim(me, a.dict, a.clip, 4.0, -4.0, -1, a.flag, 0.0, false, false, false) end

    d.text = { you = Config.Text.tug_you, them = Config.Text.tug_them }
    NUI.send('tug:start', d)

    CreateThread(function()
        local control = d.control or 22
        while Snatch.tug and Snatch.tug.id == d.id do
            DisableControlAction(0, control, true)
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 140, true)
            if IsDisabledControlJustPressed(0, control) then
                TriggerServerEvent('nzc:s:tugHit', d.id)
                NUI.send('tug:press')
            end
            Wait(0)
        end
    end)
end)

RegisterNetEvent('nzc:c:tugTick', function(rope)
    if Snatch.tug then NUI.send('tug:tick', { rope = rope }) end
end)

RegisterNetEvent('nzc:c:tugEnd', function(r)
    local me = PlayerPedId()
    Snatch.tug = nil
    NUI.send('tug:end', r)
    FreezeEntityPosition(me, false)
    ClearPedSecondaryTask(me)
    if (r.ragdoll or 0) > 0 then
        SetTimeout(250, function() SetPedToRagdoll(PlayerPedId(), r.ragdoll, r.ragdoll, 0, false, false, false) end)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Snatch.tug then FreezeEntityPosition(PlayerPedId(), false) end
    if cfg.Enabled then CB.RemovePlayerOptions({ { name = 'nzc_snatch', label = cfg.TargetLabel } }) end
end)
