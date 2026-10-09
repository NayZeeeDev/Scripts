--[[
    Cleaning a pair with a kit: kneel down, the pair goes on the ground in front
    of you, close-up camera, a brush in your hand, and the work in stages.
]]

Cleaning = {}

local C = Config.Cleaning
local WASH = { 'amb@world_human_bum_wash@male@low@idle_a', 'idle_a' }
local R_HAND = 28422

local function playWash()
    if not LoadAnimDict(WASH[1]) then return end
    TaskPlayAnim(PlayerPedId(), WASH[1], WASH[2], 3.0, -3.0, -1, 1, 0.0, false, false, false)
end

local function holdBrush()
    if not C.Brush or not LoadModel(C.Brush) then return end
    local ped = PlayerPedId()
    local obj = CreateObject(C.Brush, 0.0, 0.0, 0.0, false, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, R_HAND), 0.05, 0.0, -0.02, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(C.Brush)
    return obj
end

--- The pair on the ground just in front of the player
local function placePair(shoe)
    local model = ShoeProp(shoe)
    if not shoe or not LoadModel(model) then return end
    local ped = PlayerPedId()
    local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.62, 0.0)
    local found, z = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 0.5, false)
    local obj = CreateObjectNoOffset(model, spot.x, spot.y, found and z or spot.z - 0.98, false, false, false)
    SetEntityHeading(obj, GetEntityHeading(ped) + 90.0)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

--- The three ways to shoot cleaning. { pos, look, fov }
local function groundShots(ped, pairPos)
    local eye = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) + GetEntityForwardVector(ped) * 0.14 + vector3(0.0, 0.0, 0.03)
    local up = vector3(0.0, 0.0, 1.0)
    return {
        -- 3/4: in front and to the side, looking back at you kneeling over the pair
        three = { GetOffsetFromEntityInWorldCoords(ped, 1.25, 1.45, 0.25), pairPos + vector3(0.0, 0.0, 0.25) - GetEntityForwardVector(ped) * 0.25, 50.0 },
        first = 'native',   -- the game's own first-person camera
        close = { GetOffsetFromEntityInWorldCoords(ped, 0.42, 0.9, -0.72), pairPos + up * 0.07, 38.0 },
    }
end

function Cleaning.Run(slot, meta)
    local ped = PlayerPedId()
    if Busy or IsPedInAnyVehicle(ped, false) then return end
    local ok, stages = lib.callback.await('nayzeee-sneakers:cleanStart', false, slot)
    if not ok then return end
    Busy = true

    local pair = placePair(Config.Shoes[meta.shoe])
    playWash()
    Wait(500)
    local view, shots = Views.Get(), nil
    if pair then
        shots = groundShots(ped, GetEntityCoords(pair))
        Views.Show(view, shots)
    end

    local results, cancelled = {}, false
    for i, st in ipairs(stages) do
        local brush = holdBrush()
        UI.Progress({ label = st.label, step = i, steps = #stages, time = st.time,
                      hint = Config.Camera.Switch and Config.Text.craftHintView or Config.Text.cleanHint })
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < st.time do
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            if IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177) then cancelled = true break end
            if shots then view = Views.Poll(view, shots) end
            if not IsEntityPlayingAnim(ped, WASH[1], WASH[2], 3) then playWash() end
        end
        UI.Progress(nil)
        if brush then DeleteEntity(brush) end
        if cancelled then break end
        if st.check then
            results[i] = lib.skillCheck(st.check) == true
            UI.Notify(results[i] and Config.Text.checkPassed or Config.Text.checkFailed, results[i] and 'success' or 'warning')
        end
    end

    if cancelled then
        lib.callback.await('nayzeee-sneakers:cleanCancel', false)
    else
        local done, dirt = lib.callback.await('nayzeee-sneakers:cleanFinish', false, results)
        if done then UI.Notify(Config.Text.cleaned:format(dirt), 'success') end
    end

    Wait(300)
    if pair then DeleteEntity(pair) end
    Cam.Stop()
    ClearPedTasks(ped)
    RemoveAnimDict(WASH[1])
    Busy = false
end

-- Using the kit from the inventory: pick a dirty pair
RegisterNetEvent('nayzeee-sneakers:client:useKit', function()
    if Busy then return end
    local list = {}
    for _, p in ipairs(lib.callback.await('nayzeee-sneakers:myShoes', false) or {}) do
        if (tonumber(p.meta.dirt) or 0) > 0 then list[#list + 1] = p end
    end
    if #list == 0 then return UI.Notify(Config.Text.alreadyClean, 'inform') end
    local pick = list[1]
    if #list > 1 then
        local options = {}
        for i, p in ipairs(list) do
            local shoe = Config.Shoes[p.meta.shoe]
            options[i] = {
                id = i, label = Shared.ShoeName(p.meta), image = shoe and shoe.image,
                description = ('US %s · %d%% dirty'):format(p.meta.size, math.floor(tonumber(p.meta.dirt) or 0)),
            }
        end
        local i = UI.Menu({ title = Config.Text.choosePair, options = options })
        pick = i and list[i]
    end
    if pick then Cleaning.Run(pick.slot, pick.meta) end
end)
