--[[
    NAYZEEE AMBULANCE - Transport (client): fireman carry

      NZA.Transport.Carry.Start(entity, target)   bend down, lift (server 'nza:transport:carry'), carry
      NZA.Transport.Carry.Drop(opts?)             put down (opts = { veh = net, seat = n } → vehicle seat)
      NZA.Transport.Carry.End()                   local cleanup (anims, prompts)
      NZA.Transport.Carry.Active() → state | nil

    While carrying: walk only, no weapons / vehicles. [G] put down, [E] context when one is near:
    a free stretcher (place on it), a hospital bed / table (place on it), a vehicle with a free
    rear seat (put in the seat). The carried patient's own client (player) or this client (NPC)
    attaches the body and plays the synced over-the-shoulder animation.
    Net events handled: nza:transport:carryEnd (the server ended the carry)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local Tr = NZA.Transport
Tr.Carry = Tr.Carry or {}
local C = Tr.Carry

local BLOCK = { 22, 23, 24, 25, 36, 37, 44, 45, 140, 141, 142, 143, 257, 263, 264 }
local PROMPT, PROMPT_CTX = 'nza_tr_carry', 'nza_tr_carry_ctx'

local function S() return Tr.S end

function C.Active()
    return S().carrying
end

function C.End()
    local cur = S().carrying
    S().carrying = nil
    NZA.UI.HidePrompt(PROMPT)
    NZA.UI.HidePrompt(PROMPT_CTX)
    local me = PlayerPedId()
    Tr.StopAnim(me, Tr.Cfg('Carry').carrier)
    if cur and cur.npc then
        local ent = NZA.Target.Entity(cur.target)
        -- an NPC still hanging off us (server ended the carry): drop it
        if ent ~= 0 and IsEntityAttachedToEntity(ent, me) and NetworkHasControlOfEntity(ent) then
            DetachEntity(ent, true, false)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- CONTEXT (what [E] does right now)
-- ════════════════════════════════════════════════════════════════════════

local function seatNear(pos)
    local c = Tr.Cfg('Carry')
    local range = (c.seatRange or 3.2) + 1.0
    local best, bestSeat, bestD = nil, nil, range
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local d = #(pos - GetEntityCoords(veh))
        if d <= bestD and not Tr.VehCfg(veh) then
            local class = GetVehicleClass(veh)
            if class ~= 8 and class ~= 13 and class ~= 14 and class ~= 15 and class ~= 16 and class ~= 21
                and GetEntitySpeed(veh) < 1.0 and NetworkGetEntityIsNetworked(veh) then
                local maxP = GetVehicleMaxNumberOfPassengers(veh)
                for _, seat in ipairs(c.seats or { 1, 2, 0 }) do
                    if seat < maxP and IsVehicleSeatFree(veh, seat) then
                        best, bestSeat, bestD = veh, seat, d
                        break
                    end
                end
            end
        end
    end
    return best, bestSeat
end

local function findContext()
    local pos = GetEntityCoords(PlayerPedId())
    if Tr.Cfg('Stretcher').enabled ~= false and NZA.Perm(Tr.Cfg().perm or 'transport') and Tr.Str and Tr.Str.FreeNear then
        local se = Tr.Str.FreeNear(pos, 2.6)
        if se then return { kind = 'str', ent = se, label = Tr.L('p_on_stretcher') } end
    end
    if Tr.Cfg('Beds').enabled ~= false and NZA.Perm(Tr.Cfg().perm or 'transport') and Tr.Bed and Tr.Bed.Nearest then
        local pt = Tr.Bed.Nearest(pos, Tr.Cfg('Beds').range or 3.0, true)
        if pt then return { kind = 'bed', pt = pt, label = Tr.L('p_bed', Tr.Bed.Label(pt)) } end
    end
    local veh, seat = seatNear(pos)
    if veh then return { kind = 'seat', veh = veh, seat = seat, label = Tr.L('p_seat') } end
    return nil
end

local function runContext(ctx)
    local cur = S().carrying
    if not cur or cur.acting then return end
    if ctx.kind == 'seat' then
        local net = Tr.Net(ctx.veh)
        if net then C.Drop({ veh = net, seat = ctx.seat }) end
    elseif ctx.kind == 'str' then
        cur.acting = true
        local ok = Tr.Str.PlacePatient(ctx.ent, cur.ent, cur.target)
        if S().carrying == cur then
            cur.acting = false
            if ok then C.End() end
        end
    elseif ctx.kind == 'bed' then
        cur.acting = true
        local ok = Tr.Bed.PlaceFromCarry(ctx.pt, cur.target)
        if S().carrying == cur then
            cur.acting = false
            if ok then C.End() end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- LOOP
-- ════════════════════════════════════════════════════════════════════════

local function loop()
    CreateThread(function()
        local c = Tr.Cfg('Carry')
        local keys = c.keys or {}
        local dropK = keys.drop or { control = 47, label = 'G' }
        local ctxK = keys.context or { control = 38, label = 'E' }
        local nextCheck, ctx, shownCtx = 0, nil, nil
        local cur = S().carrying
        NZA.UI.Prompt(PROMPT, { key = dropK.label, label = Tr.L('p_drop'), sub = Tr.L('sub_carry', cur and cur.name or '') })
        while S().carrying do
            local me = PlayerPedId()
            local now = GetGameTimer()
            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
            if (c.maxSpeed or 1.0) < 2.0 then DisableControlAction(0, 21, true) end
            DisableControlAction(0, dropK.control, true)
            DisableControlAction(0, ctxK.control, true)
            SetPedMaxMoveBlendRatio(me, c.maxSpeed or 1.0)
            if now >= nextCheck then
                nextCheck = now + 300
                cur = S().carrying
                local ent = cur and NZA.Target.Entity(cur.target) or 0
                if not cur or ent == 0 or IsPedInAnyVehicle(me, false) or (NZA.Self and NZA.Self.State() ~= 'alive') then
                    if cur and ent ~= 0 and not cur.acting then C.Drop() end
                    if S().carrying then C.End() end
                    break
                end
                if not cur.acting and not Tr.Playing(me, c.carrier) then Tr.Play(me, c.carrier) end
                ctx = (not cur.acting) and findContext() or nil
                local label = ctx and ctx.label or nil
                if label ~= shownCtx then
                    shownCtx = label
                    if label then
                        NZA.UI.Prompt(PROMPT_CTX, { key = ctxK.label, label = label, sub = Tr.L('sub_carry', cur.name or '') })
                    else
                        NZA.UI.HidePrompt(PROMPT_CTX)
                    end
                end
            end
            cur = S().carrying
            if cur and not cur.acting then
                if IsDisabledControlJustPressed(0, dropK.control) then
                    CreateThread(function() C.Drop() end)
                elseif ctx and IsDisabledControlJustPressed(0, ctxK.control) then
                    local which = ctx
                    CreateThread(function() runContext(which) end)
                end
            end
            Wait(0)
        end
        NZA.UI.HidePrompt(PROMPT)
        NZA.UI.HidePrompt(PROMPT_CTX)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- START / DROP
-- ════════════════════════════════════════════════════════════════════════

function C.Start(entity, target)
    if Tr.Busy() then return Tr.Toast(Tr.L('err_busy'), 'error') end
    local c = Tr.Cfg('Carry')
    local me = PlayerPedId()
    if target.kind == 'npc' then Tr.Control(entity, 1500) end
    TaskTurnPedToFaceEntity(me, entity, 600)
    Wait(450)
    local pick = type(c.pickup) == 'table' and c.pickup or nil
    if pick then
        Tr.Play(me, pick, { flag = 0 })
        Wait(math.floor(pick.ms or 900))
    end
    local ok, res = Tr.Call('carry', target)
    if pick then Tr.StopAnim(me, pick) end
    if not ok then return Tr.Err(res) end
    S().carrying = { target = res.target or target, ent = entity, npc = res.npc, name = res.name }
    if res.npc then Tr.ApplyNpc(res.target or target, res.cmd) end
    Tr.Play(me, c.carrier, { blendIn = 8.0 })
    loop()
end

function C.Drop(opts)
    local cur = S().carrying
    if not cur or cur.acting then return end
    cur.acting = true
    NZA.UI.HidePrompt(PROMPT_CTX)
    local ok, res = Tr.Call('drop', opts)
    if S().carrying ~= cur then return end
    if not ok then
        cur.acting = false
        Tr.Err(res)
        if res.err == 'no_patient' then C.End() end
        return
    end
    if res.npc then Tr.ApplyNpc(res.target or cur.target, res.cmd) end
    if res.msg then Tr.Toast(res.msg, 'success') end
    C.End()
end

RegisterNetEvent('nza:transport:carryEnd', function()
    if S().carrying and not S().carrying.acting then C.End() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if S().carrying then C.End() end
end)
