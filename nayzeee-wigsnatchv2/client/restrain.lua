-- Tackles, zip ties, holding someone still, and the timed actions (tying, products, crafting...)

Restrain = { tied = false, held = nil, holding = nil, acting = false }

local CT, CTi, CH = Config.Tackle, Config.Tie, Config.Hold

-- controls a tied / held player can't use
local LOCKED = { 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 47, 58, 75, 140, 141, 142, 143, 257, 263, 264 }

local function lockControls()
    for i = 1, #LOCKED do DisableControlAction(0, LOCKED[i], true) end
end

-- struggling: alternate A / D (they're disabled for movement, so read them as disabled controls)
local lastTok
local function readStruggle()
    local tok
    if IsDisabledControlJustPressed(0, 34) then tok = 'L'
    elseif IsDisabledControlJustPressed(0, 35) then tok = 'R' end
    if tok and tok ~= lastTok then
        lastTok = tok
        TriggerServerEvent('nz-wig:s:struggle', tok)
    end
end

RegisterNetEvent('nz-wig:c:struggleTick', function(frac)
    NUI.Send('struggle', { value = frac })
end)

-- tackle -------------------------------------------------------------------------------------------

local function tackle()
    if not CT.Enabled or Snatch.busy or NUI.app or Restrain.tied or Restrain.held or Restrain.holding then return end
    local me = PlayerPedId()
    if IsPedInAnyVehicle(me, false) or IsPedRagdoll(me) or IsPedFalling(me) or IsPedSwimming(me) then return end
    if CT.RequireSprint and not IsPedSprinting(me) and not IsPedRunning(me) then return CB.Notify(L('tackle_sprint'), 'error') end
    local left = (Snatch.profile.tackleUntil or 0) - Snatch.ServerNow()
    if left > 0 then return CB.Notify(L('tackle_cooldown', left), 'error') end
    local target = ClosestInFront(CT.Range)
    if not target then return end
    local sid = ServerIdOf(target)
    if sid then TriggerServerEvent('nz-wig:s:tackle', sid) end
end

if CT.Enabled and CT.Command then
    RegisterCommand(CT.Command, tackle, false)
    if CT.Key then RegisterKeyMapping(CT.Command, 'Tackle someone', 'keyboard', CT.Key) end
end

RegisterNetEvent('nz-wig:c:tackle', function(targetSrc)
    local me = PlayerPedId()
    local other = PedOf(targetSrc)
    if other ~= 0 then FaceEntity(me, other) end
    PlayAnim({ dict = CT.Anim.dict, clip = CT.Anim.tackler, flag = 0 }, 1200)
    if (CT.SelfRagdoll or 0) > 0 then
        SetTimeout(450, function() SetPedToRagdoll(PlayerPedId(), CT.SelfRagdoll, CT.SelfRagdoll, 0, false, false, false) end)
    end
end)

RegisterNetEvent('nz-wig:c:tackled', function()
    if Restrain.holding then TriggerServerEvent('nz-wig:s:release') end
    PlayAnim({ dict = CT.Anim.dict, clip = CT.Anim.target, flag = 0 }, 600)
    SetTimeout(250, function()
        SetPedToRagdoll(PlayerPedId(), CT.TargetRagdoll, CT.TargetRagdoll, 0, false, false, false)
    end)
    Reaction('tackled', CT.TargetRagdoll + 400)
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.12)
end)

-- tied -------------------------------------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:tied', function(on, d)
    Restrain.tied = on
    local me = PlayerPedId()
    if not on then
        NUI.Send('struggle', { hide = true })
        ClearPedTasks(me)
        return
    end
    NUI.Send('struggle', { value = 1, kind = 'tied', show = d and d.struggle })
    lastTok = nil
    CreateThread(function()
        local a = CTi.Anims.tied
        local nextAnim = 0
        while Restrain.tied do
            local ped = PlayerPedId()
            lockControls()
            if d and d.struggle then readStruggle() end
            if GetGameTimer() > nextAnim then
                nextAnim = GetGameTimer() + 1000
                if not Restrain.held and not IsPedRagdoll(ped) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                    LoopAnim({ dict = a.dict, clip = a.clip, flag = 49 }, ped)
                end
            end
            Wait(0)
        end
    end)
end)

-- holding ----------------------------------------------------------------------------------------------

RegisterNetEvent('nz-wig:c:holdStart', function(d)
    local me = PlayerPedId()
    lastTok = nil
    if d.role == 'holder' then
        Restrain.holding = d.other
        NUI.Send('hint', { show = true, keys = { CH.ReleaseKey or ('/' .. CH.ReleaseCommand) }, text = L('hold_hint') })
        CreateThread(function()
            local a = CH.Anims.holder
            local nextAnim = 0
            while Restrain.holding == d.other do
                local ped = PlayerPedId()
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                for _, c in ipairs({ 140, 141, 142 }) do DisableControlAction(0, c, true) end
                if GetGameTimer() > nextAnim then
                    nextAnim = GetGameTimer() + 1000
                    if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then LoopAnim({ dict = a.dict, clip = a.clip, flag = 49 }, ped) end
                end
                Wait(0)
            end
        end)
    else
        Restrain.held = d.other
        NUI.Send('struggle', { value = 1, kind = 'held', show = true })
        local holder = PedOf(d.other)
        if holder ~= 0 then
            local o = CH.Offset
            AttachEntityToEntity(me, holder, 0, o.x, o.y, o.z, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
        end
        CreateThread(function()
            local a = CH.Anims.held
            local nextAnim = 0
            while Restrain.held == d.other do
                local ped = PlayerPedId()
                lockControls()
                readStruggle()
                if GetGameTimer() > nextAnim then
                    nextAnim = GetGameTimer() + 1000
                    if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then LoopAnim({ dict = a.dict, clip = a.clip, flag = 49 }, ped) end
                    -- holder streamed back in / respawned: re-attach
                    local h = PedOf(d.other)
                    if h ~= 0 and not IsEntityAttachedToEntity(ped, h) then
                        local o = CH.Offset
                        AttachEntityToEntity(ped, h, 0, o.x, o.y, o.z, 0.5, 0.5, 0.0, false, false, false, false, 2, false)
                    end
                end
                Wait(0)
            end
        end)
    end
end)

RegisterNetEvent('nz-wig:c:holdEnd', function(d)
    local me = PlayerPedId()
    if d.role == 'holder' then
        Restrain.holding = nil
        NUI.Send('hint', { show = false })
        ClearPedSecondaryTask(me)
        if d.reason == 'broke' then SetPedToRagdoll(me, 1200, 1200, 0, false, false, false) end
    else
        Restrain.held = nil
        NUI.Send('struggle', { hide = true })
        DetachEntity(me, true, false)
        ClearPedTasks(me)
        if Restrain.tied then lastTok = nil end
    end
end)

if CH.Enabled then
    RegisterCommand(CH.ReleaseCommand, function()
        if Restrain.holding then TriggerServerEvent('nz-wig:s:release') end
    end, false)
    if CH.ReleaseKey then RegisterKeyMapping(CH.ReleaseCommand, 'Let go of who you\'re holding', 'keyboard', CH.ReleaseKey) end
end

-- timed actions: tying, untying, products, crafting, dyeing ------------------------------------------------

local ACTION_ANIM = {
    tie     = function() return CTi.Anims.tier end,
    untie   = function() return CTi.Anims.tier end,
    product = function() return Config.Anims.Apply end,
    craft   = function() return Config.Workshop.CraftAnim end,
    dye     = function() return Config.Anims.Apply end,
}

RegisterNetEvent('nz-wig:c:actionRun', function(d)
    local me = PlayerPedId()
    Restrain.acting = true
    if d.other then
        local o = PedOf(d.other)
        if o ~= 0 then FaceEntity(me, o) end
    end
    NUI.CloseApp()
    local a = ACTION_ANIM[d.kind] and ACTION_ANIM[d.kind]()
    FreezeEntityPosition(me, true)
    if a then LoopAnim({ dict = a.dict, clip = a.clip, flag = a.flag or 49 }, me) end
    NUI.Send('progress', { label = d.label or L('action_' .. d.kind), duration = d.duration })
    local held = d.kind == 'dye' and AttachLocalProp(Config.TableProps.dye) or nil
    SetTimeout(d.duration, function()
        FreezeEntityPosition(PlayerPedId(), false)
        ClearPedSecondaryTask(PlayerPedId())
        DeleteProp(held)
        Restrain.acting = false
    end)
end)

RegisterNetEvent('nz-wig:c:hurt', function(amount)
    local ped = PlayerPedId()
    ApplyDamageToPed(ped, math.floor(tonumber(amount) or 0), false)
end)

-- target options ------------------------------------------------------------------------------------------

local function free()
    return not Snatch.busy and not NUI.app and not Restrain.tied and not Restrain.held and not Restrain.acting
end

local function helpless(entity)
    local sid = ServerIdOf(entity)
    return CB.Helpless(entity, sid)
end

Restrain.TargetOptions = {}

if CTi.Enabled then
    Restrain.TargetOptions[#Restrain.TargetOptions + 1] = {
        name = 'nzwig_tie', label = CTi.Label, icon = 'fa-solid fa-link', distance = 1.8, item = CTi.Item,
        canInteract = function(e)
            local sid = ServerIdOf(e)
            return free() and sid and not Player(sid).state[ST.tied] and helpless(e)
        end,
        onSelect = function(e) local sid = ServerIdOf(e) if sid then TriggerServerEvent('nz-wig:s:tie', sid) end end,
    }
    Restrain.TargetOptions[#Restrain.TargetOptions + 1] = {
        name = 'nzwig_untie', label = CTi.UntieLabel, icon = 'fa-solid fa-link-slash', distance = 1.8,
        canInteract = function(e)
            local sid = ServerIdOf(e)
            return free() and sid and Player(sid).state[ST.tied] == true
        end,
        onSelect = function(e) local sid = ServerIdOf(e) if sid then TriggerServerEvent('nz-wig:s:untie', sid) end end,
    }
end

if CH.Enabled then
    Restrain.TargetOptions[#Restrain.TargetOptions + 1] = {
        name = 'nzwig_hold', label = CH.Label, icon = 'fa-solid fa-people-pulling', distance = 1.6,
        canInteract = function(e)
            local sid = ServerIdOf(e)
            if not free() or Restrain.holding or not sid or Player(sid).state[ST.held] then return false end
            return not CH.RequireBehind or helpless(e) or IsBehind(PlayerPedId(), e, 75)
        end,
        onSelect = function(e) local sid = ServerIdOf(e) if sid then TriggerServerEvent('nz-wig:s:hold', sid) end end,
    }
end

-- using zip ties from the inventory
RegisterNetEvent('nz-wig:c:useTies', function()
    local ped = ClosestInFront(2.0)
    if not ped then return CB.Notify(L('no_one_close'), 'error') end
    local sid = ServerIdOf(ped)
    if sid then TriggerServerEvent('nz-wig:s:tie', sid) end
end)

function Restrain.Cleanup()
    local me = PlayerPedId()
    if Restrain.held then DetachEntity(me, true, false) end
    if Restrain.tied or Restrain.held or Restrain.holding then ClearPedTasks(me) end
    if Restrain.acting then FreezeEntityPosition(me, false) end
    Restrain.tied, Restrain.held, Restrain.holding = false, nil, nil
end

-- commands for servers without a target system ---------------------------------------------------------------

local function inFront(range)
    local ped = ClosestInFront(range)
    if not ped then CB.Notify(L('no_one_close'), 'error') return nil end
    return ServerIdOf(ped)
end

if CH.Enabled then
    RegisterCommand('wighold', function()
        if not free() or Restrain.holding then return end
        local sid = inFront(1.6)
        if sid then TriggerServerEvent('nz-wig:s:hold', sid) end
    end, false)
end

if CTi.Enabled then
    RegisterCommand('wiguntie', function()
        if not free() then return end
        local sid = inFront(1.8)
        if sid then TriggerServerEvent('nz-wig:s:untie', sid) end
    end, false)
end

if Config.Cutting.Enabled then
    RegisterCommand('wigcut', function()
        TriggerEvent('nz-wig:c:useTool')
    end, false)
end
