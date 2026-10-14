--[[
    NAYZEEE AMBULANCE - Crutches (client)

    Anyone with Config.Items.crutches can walk on crutches: use the item, the keybind 'nza_crutches'
    (Config.Splint.Crutches.key, unbound by default) or the command Config.Splint.Crutches.command.
    The server owns the on/off state (player state bag 'nzaCrutch'); this file
      - plays the crutch walk on the local player (NZA.Self.SetMoveOverride('crutch', clipset)), walk only,
        no sprint / jump / weapons (Config.Splint.Crutches.blockControls), optional upper-body loop,
      - draws two Config.Props.crutch props in the hands of EVERY player whose bag says 'nzaCrutch'
        (local props, within Config.Splint.Props.range, hidden in vehicles),
      - adds the medic option nza_crutches_give 'Give crutches' (NZA.Treat 'crutches_give').
    Net event handled: nza:splint:crutch (on, silent)
    Callback used: nza:splint:crutch:toggle
    Lua API: NZA.Splint.CrutchesOn() → bool, NZA.Splint.ToggleCrutches()
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Splint = NZA.Splint or {}
local SP = NZA.Splint

local function C(section)
    local c = Config.Splint or {}
    return c[section] or {}
end

local function CR() return C('Crutches') end

local function L(key, ...)
    return NZA.L('splint.' .. key, ...)
end

local function toast(key, kind, ...)
    NZA.UI.Toast({ title = L('crutches'), message = L(key, ...), type = kind or 'info' })
end

local on = false
local gen = 0
local UNARMED = joaat('WEAPON_UNARMED')

function SP.CrutchesOn()
    return on
end

-- ════════════════════════════════════════════════════════════════════════
-- LOCAL WALK
-- ════════════════════════════════════════════════════════════════════════

local function hud(state)
    if not SP.HudSet then return end
    if not state or CR().hud == false then SP.HudSet('crutch', nil) return end
    local key = CR().command and ('/' .. CR().command) or nil
    SP.HudSet('crutch', {
        kind = 'crutch', title = L('hud_crutch'), sub = state,
        keys = key and { { keys = { key }, label = L('k_put_away') } } or {},
    })
end

local function upperAnim(ped, play)
    local up = CR().upper
    if type(up) ~= 'table' or not up.dict then return end
    if play then
        if not IsEntityPlayingAnim(ped, up.dict, up.clip, 3) then
            NZA.Anim.Play(ped, up.dict, up.clip, { flag = 49 })
        end
    elseif IsEntityPlayingAnim(ped, up.dict, up.clip, 3) then
        StopAnimTask(ped, up.dict, up.clip, 2.0)
    end
end

local function startWalk()
    gen = gen + 1
    local my = gen
    NZA.Self.SetMoveOverride('crutch', CR().clipset or 'move_lester_CaneUp')
    hud(L('hud_crutch_walk'))
    CreateThread(function()
        local blend = tonumber(CR().maxMoveBlend) or 1.0
        local rate = tonumber(CR().moveRate) or 0.86
        local block = CR().blockControls or {}
        local lastMoving = nil
        while on and gen == my do
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                SetPedMaxMoveBlendRatio(ped, blend)
                SetPedMoveRateOverride(ped, rate)
                for i = 1, #block do DisableControlAction(0, block[i], true) end
                DisablePlayerFiring(PlayerId(), true)
                if GetSelectedPedWeapon(ped) ~= UNARMED then SetCurrentPedWeapon(ped, UNARMED, true) end
                local moving = GetEntitySpeed(ped) > 0.3
                if moving ~= lastMoving then
                    lastMoving = moving
                    upperAnim(ped, moving)
                    hud(moving and L('hud_crutch_walk') or L('hud_crutch_stand'))
                end
            elseif lastMoving ~= 'veh' then
                lastMoving = 'veh'
                upperAnim(ped, false)
                hud(L('hud_crutch_vehicle'))
            end
            Wait(0)
        end
    end)
end

local function stopWalk()
    gen = gen + 1
    NZA.Self.SetMoveOverride('crutch', nil)
    upperAnim(PlayerPedId(), false)
    hud(nil)
end

RegisterNetEvent('nza:splint:crutch', function(state, silent)
    state = state == true
    if state == on then return end
    on = state
    if on then
        startWalk()
        if not silent then toast('crutches_on', 'success') end
    else
        stopWalk()
        if not silent then toast('crutches_off', 'info') end
    end
    SP.RefreshCrutches()
end)

function SP.ToggleCrutches()
    if CR().enabled == false then return end
    if IsNuiFocused() or IsPauseMenuActive() then return end
    local r = lib.callback.await('nza:splint:crutch:toggle', false)
    if type(r) == 'table' and r.ok == false and r.msg then
        NZA.UI.Toast({ title = L('crutches'), message = r.msg, type = 'error' })
    end
end

if CR().enabled ~= false then
    if lib and lib.addKeybind then
        lib.addKeybind({
            name = 'nza_crutches',
            description = L('key_crutches'),
            defaultKey = CR().key or '',
            onPressed = function() CreateThread(SP.ToggleCrutches) end,
        })
    end
    if CR().command then
        RegisterCommand(CR().command, function() CreateThread(SP.ToggleCrutches) end, false)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CRUTCH PROPS ON EVERY PLAYER THAT USES THEM
-- ════════════════════════════════════════════════════════════════════════

local held = {}       -- [ped] = { r, l }
local wake = false

local function drop(ped)
    local h = held[ped]
    if not h then return end
    NZA.Props.Delete(h.r)
    NZA.Props.Delete(h.l)
    held[ped] = nil
end

local function attach(ped)
    local function one(side)
        local a = CR()[side] or {}
        return NZA.Props.Spawn(CR().prop or 'crutch', {
            attach = { entity = ped, bone = a.bone or (side == 'right' and 28422 or 60309),
                       pos = a.pos or vector3(0.0, 0.0, 0.0), rot = a.rot or vector3(0.0, 0.0, 0.0), collision = false },
        }, { group = 'splint_crutch', network = false, collision = false, fallbackKey = 'crutch', timeout = 4000 })
    end
    local r = one('right')
    local l = one('left')
    held[ped] = { r = r, l = l }
end

function SP.RefreshCrutches()
    wake = true
end

local function tick()
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local range = tonumber(C('Props').range) or 45.0
    local seen = {}
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        local ply = Player(GetPlayerServerId(pl))
        local using = ply and ply.state and ply.state.nzaCrutch == true
        if pl == PlayerId() then using = using or on end
        if using and DoesEntityExist(ped) and #(GetEntityCoords(ped) - mc) <= range
            and not (CR().hideInVehicle ~= false and IsPedInAnyVehicle(ped, false)) and not IsEntityDead(ped) then
            seen[ped] = true
            local h = held[ped]
            if h and (not DoesEntityExist(h.r) or not DoesEntityExist(h.l) or not IsEntityAttachedToEntity(h.r, ped)) then
                drop(ped)
                h = nil
            end
            if not h then attach(ped) end
        end
    end
    for ped in pairs(held) do
        if not seen[ped] then drop(ped) end
    end
end

CreateThread(function()
    while true do
        if CR().enabled ~= false then
            local ok, err = pcall(tick)
            if not ok then NZA.Debug('splint crutch props: ' .. tostring(err)) end
        end
        local t = 0
        while t < 600 and not wake do Wait(100) t = t + 100 end
        wake = false
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- MEDIC: GIVE CRUTCHES
-- ════════════════════════════════════════════════════════════════════════

if CR().enabled ~= false and CR().give ~= false and C('Interact').crutches ~= false then
    NZA.Interact.Add({
        name = 'nza_crutches_give', label = L('opt_crutches'), icon = (C('Interact').icons or {}).crutches or 'crutch',
        order = 52, perm = CR().givePerm or 'splint', npc = false, player = true,
        states = { alive = true, wounded = true }, distance = tonumber(C('Interact').distance) or 2.2,
        canInteract = function(_, _, st)
            if type(st) ~= 'table' or st.carried or st.bag then return false end
            if not Bridge or not Bridge.Inv or not Bridge.Inv.Has then return true end
            local name = Config.Items and Config.Items[CR().item or 'crutches']
            return name ~= nil and Bridge.Inv.Has(name, 1) ~= false
        end,
        onSelect = function(_, target)
            NZA.Treat.Do('crutches_give', target, {})
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and on then
        on = false
        stopWalk()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ped in pairs(held) do drop(ped) end
    if on then
        on = false
        NZA.Self.SetMoveOverride('crutch', nil)
    end
end)
