-- The buyer: text him, he runs over, you sell from the menu. Plus optional permanent fences.

Buyer = { ped = nil, active = false }

local CBY = Config.Buyer
local SELL_OPT = { { name = 'nzwig_sell', label = 'Sell Wigs', icon = 'fa-solid fa-sack-dollar', distance = 2.5 } }

local function openFence(kind, idx)
    local data, err = lib.callback.await('nz-wig:fenceOpen', false, kind, idx)
    if not data then return CB.Notify(err or L('buyer_session'), 'error') end
    data.kind = kind
    NUI.Open('fence', data)
end

RegisterNUICallback('fenceSell', function(d, cb)
    local ok, res = lib.callback.await('nz-wig:fenceSell', false, d and d.keys or {})
    if not ok then CB.Notify(res or L('invalid'), 'error') end
    cb({ ok = ok, result = ok and res or nil })
end)

local function phoneAnim()
    local a = CBY.PhoneAnim
    local me = PlayerPedId()
    local prop
    if pcall(lib.requestModel, a.prop, 1500) then
        local c = GetEntityCoords(me)
        prop = CreateObject(a.prop, c.x, c.y, c.z + 0.2, true, true, false)
        AttachEntityToEntity(prop, me, GetPedBoneIndex(me, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(a.prop)
    end
    PlayAnim({ dict = a.dict, clip = a.clip, flag = 49 }, a.duration)
    Wait(a.duration)
    ClearPedSecondaryTask(me)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

local function despawn(walkAway)
    local ped = Buyer.ped
    Buyer.ped = nil
    Buyer.active = false
    TriggerServerEvent('nz-wig:s:buyerGone')
    if not ped or not DoesEntityExist(ped) then return end
    if CB.Target ~= 'none' then CB.RemoveLocalEntity(ped, SELL_OPT) end
    if walkAway then
        FreezeEntityPosition(ped, false)
        TaskWanderStandard(ped, 10.0, 10)
        SetTimeout(8000, function() if DoesEntityExist(ped) then DeleteEntity(ped) end end)
    else
        DeleteEntity(ped)
    end
end

local function spawnPoint(me)
    local mc = GetEntityCoords(me)
    for _ = 1, 8 do
        local ang = math.random() * math.pi * 2
        local x, y = mc.x + math.cos(ang) * CBY.SpawnDistance, mc.y + math.sin(ang) * CBY.SpawnDistance
        local ok, z = GetGroundZFor_3dCoord(x, y, mc.z + 30.0, false)
        if ok and math.abs(z - mc.z) < 8.0 then return vec3(x, y, z) end
    end
    local f = GetOffsetFromEntityInWorldCoords(me, 0.0, -12.0, 0.0)
    return vec3(f.x, f.y, mc.z - 1.0)
end

local function keyLoop(ped)
    CreateThread(function()
        local shown = false
        while Buyer.ped == ped and DoesEntityExist(ped) do
            local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
            if d < 2.2 and not NUI.app then
                if not shown then lib.showTextUI('[E] Sell Wigs') shown = true end
                if IsControlJustReleased(0, 38) then openFence('buyer') end
                Wait(0)
            else
                if shown then lib.hideTextUI() shown = false end
                Wait(400)
            end
        end
        if shown then lib.hideTextUI() end
    end)
end

local function call()
    if Buyer.active then return CB.Notify(L('buyer_active'), 'error') end
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    local ok, err = lib.callback.await('nz-wig:buyerCall', false)
    if not ok then return CB.Notify(err or L('invalid'), 'error') end
    Buyer.active = true
    CB.Notify(L('buyer_calling'), 'info')
    phoneAnim()

    local me = PlayerPedId()
    if not pcall(lib.requestModel, CBY.Model, 3000) then return despawn(false) end
    local p = spawnPoint(me)
    local ped = CreatePed(4, CBY.Model, p.x, p.y, p.z, 0.0, false, true)
    SetModelAsNoLongerNeeded(CBY.Model)
    Buyer.ped = ped
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    CB.Notify(L('buyer_coming'), 'info')

    TaskGoToEntity(ped, me, -1, 1.6, CBY.RunSpeed, 1073741824.0, 0)
    local started = GetGameTimer()
    while Buyer.ped == ped and DoesEntityExist(ped) do
        local d = #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId()))
        if d < 2.6 then break end
        if GetGameTimer() - started > 45000 then
            CB.Notify(L('buyer_lost'), 'error')
            return despawn(false)
        end
        Wait(300)
    end
    if Buyer.ped ~= ped then return end

    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1500)
    Wait(1500)
    FreezeEntityPosition(ped, true)
    if CBY.Greeting then NUI.Send('speech', { text = CBY.Greeting }) end
    CB.Notify(L('buyer_arrived'), 'success')

    if CB.Target ~= 'none' then
        CB.AddLocalEntity(ped, { { name = SELL_OPT[1].name, label = SELL_OPT[1].label, icon = SELL_OPT[1].icon, distance = 2.5,
            onSelect = function() openFence('buyer') end } })
    else
        keyLoop(ped)
    end

    SetTimeout(CBY.WaitTime * 1000, function()
        if Buyer.ped == ped then
            if NUI.app == 'fence' then NUI.CloseApp() end
            CB.Notify(L('buyer_left'), 'info')
            despawn(true)
        end
    end)
end

if CBY.Enabled and CBY.Command then
    RegisterCommand(CBY.Command, function() CreateThread(call) end, false)
end

-- permanent fences --------------------------------------------------------------------------------

Buyer.fences = {}

CreateThread(function()
    for i, f in ipairs(Config.Fences) do
        local point = lib.points.new({ coords = vec3(f.coords.x, f.coords.y, f.coords.z), distance = 40.0 })
        function point:onEnter()
            if not pcall(lib.requestModel, f.model, 3000) then return end
            local ped = CreatePed(4, f.model, f.coords.x, f.coords.y, f.coords.z - 1.0, f.coords.w or 0.0, false, true)
            SetModelAsNoLongerNeeded(f.model)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            self.ped = ped
            if CB.Target ~= 'none' then
                CB.AddLocalEntity(ped, { { name = 'nzwig_fence_' .. i, label = f.label or 'Sell Wigs', icon = 'fa-solid fa-sack-dollar', distance = 2.5,
                    onSelect = function() openFence('fence', i) end } })
            end
        end
        function point:onExit()
            if self.ped and DoesEntityExist(self.ped) then DeleteEntity(self.ped) end
            self.ped = nil
        end
        if CB.Target == 'none' then
            function point:nearby()
                if self.currentDistance < 2.0 and not NUI.app then
                    lib.showTextUI('[E] ' .. (f.label or 'Sell Wigs'))
                    self.shown = true
                    if IsControlJustReleased(0, 38) then openFence('fence', i) end
                elseif self.shown then
                    lib.hideTextUI()
                    self.shown = false
                end
            end
        end
        Buyer.fences[i] = point
    end
end)

function Buyer.Cleanup()
    if Buyer.ped and DoesEntityExist(Buyer.ped) then DeleteEntity(Buyer.ped) end
    for _, p in pairs(Buyer.fences) do
        if p.ped and DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
    end
end
