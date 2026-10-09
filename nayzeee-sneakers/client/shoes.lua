Shoes = {}
Shoes.worn = nil   -- metadata of the pair on your feet (nil = none of ours)

local FEET = { 14201, 52301 }   -- SKEL_L_Foot, SKEL_R_Foot

local function feetCentre(ped)
    local a = GetPedBoneCoords(ped, FEET[1], 0.0, 0.0, 0.0)
    local b = GetPedBoneCoords(ped, FEET[2], 0.0, 0.0, 0.0)
    return (a + b) / 2
end

local function myGender() return Shared.PedGender(GetEntityModel(PlayerPedId())) end

local function cardData(meta)
    local shoe = Config.Shoes[meta.shoe]
    return {
        name = shoe and shoe.label or 'Shoes',
        colourway = shoe and shoe.colourway or '',
        image = shoe and shoe.image,
        size = meta.size,
        condition = Shared.ConditionLabel(meta.condition),
        dirt = tonumber(meta.dirt) or 0,
        serial = meta.serial,
    }
end

--------------------------------------------------------------------------------
-- Inspect: hold the pair up and turn it with the mouse
--------------------------------------------------------------------------------

function Shoes.Inspect(meta)
    local shoe = Config.Shoes[meta.shoe]
    if Busy or not shoe or not LoadModel(shoe.prop) then return end
    Busy = true

    local ped = PlayerPedId()
    local fwd = GetEntityForwardVector(ped)
    local eye = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) + fwd * 0.16
    local dist, yaw, pitch = 0.6, GetEntityHeading(ped) + 120.0, 18.0
    local focus = eye + fwd * dist - vector3(0.0, 0.0, 0.05)

    local obj = CreateObject(shoe.prop, focus.x, focus.y, focus.z, false, false, false)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(shoe.prop)
    local mn, mx = GetModelDimensions(shoe.prop)
    local centre = (mn + mx) / 2

    Cam.Create(eye, focus, 50.0)
    UI.Inspect(true, cardData(meta))

    local last = GetGameTimer()
    while true do
        local now = GetGameTimer()
        local dt = (now - last) / 1000
        last = now
        DisableAllControlActions(0)
        EnableControlAction(0, 249, true)   -- push to talk

        if IsDisabledControlPressed(0, 24) then
            yaw = yaw - GetDisabledControlNormal(0, 1) * 12.0
            pitch = math.max(-80.0, math.min(80.0, pitch - GetDisabledControlNormal(0, 2) * 12.0))
        else
            yaw = yaw + 14.0 * dt                -- slow turntable when not dragging
        end
        if IsDisabledControlJustPressed(0, 15) then dist = math.max(0.38, dist - 0.04) end
        if IsDisabledControlJustPressed(0, 14) then dist = math.min(0.95, dist + 0.04) end
        focus = eye + fwd * dist - vector3(0.0, 0.0, 0.05)

        -- rotate about the pair's middle, not its base
        SetEntityRotation(obj, pitch, 0.0, yaw, 2, true)
        local c = GetOffsetFromEntityInWorldCoords(obj, centre.x, centre.y, centre.z)
        SetEntityCoordsNoOffset(obj, GetEntityCoords(obj) + (focus - c), false, false, false)

        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200)
            or IsDisabledControlJustPressed(0, 194) then
            break
        end
        Wait(0)
    end

    UI.Inspect(false)
    Cam.Stop()
    DeleteEntity(obj)
    Busy = false
end

--------------------------------------------------------------------------------
-- Wearing
--------------------------------------------------------------------------------

local function kneelAtFeet()
    Anim.Kneel()
    Wait(450)
    Cam.LookAt(feetCentre(PlayerPedId()) + vector3(0.0, 0.0, 0.05), 60.0)
end

local function standUp()
    Wait(500)
    Cam.Stop()
    Anim.Stop()
end

function Shoes.PutOn(slot, meta)
    if Busy then return end
    local shoe = Config.Shoes[meta.shoe]
    local gender = myGender()
    if not gender then return UI.Notify(Config.Text.notFreemode, 'error') end
    if Config.GenderLock and shoe.gender ~= 'unisex' and shoe.gender ~= gender then
        return UI.Notify(Config.Text.wrongGender, 'error')
    end
    if not Shared.ClothingFor(shoe, gender) then return UI.Notify(Config.Text.noClothing, 'error') end

    Busy = true
    local ped = PlayerPedId()
    local prev = { drawable = GetPedDrawableVariation(ped, 6), texture = GetPedTextureVariation(ped, 6) }
    kneelAtFeet()
    Wait(900)
    Dirt.Flush()   -- the pair coming off keeps its last few seconds of dirt
    local ok, clothing = lib.callback.await('nayzeee-sneakers:wear', false, slot, prev)
    if ok and clothing then
        SetPedComponentVariation(ped, 6, clothing.drawable, clothing.texture or 0, 0)
        Shoes.worn = meta
        UI.Notify(Config.Text.putOn, 'success')
    end
    standUp()
    Busy = false
end

function Shoes.TakeOff()
    if Busy or IsPedInAnyVehicle(PlayerPedId(), false) then return end
    Busy = true
    kneelAtFeet()
    Wait(700)
    Dirt.Flush()
    local ok, prev = lib.callback.await('nayzeee-sneakers:takeOff', false)
    if ok and prev then
        SetPedComponentVariation(PlayerPedId(), 6, prev.drawable, prev.texture or 0, 0)
        Shoes.worn = nil
        UI.Notify(Config.Text.tookOff, 'success')
    end
    standUp()
    Busy = false
end

RegisterCommand(Config.Wear.takeOffCommand, function() Shoes.TakeOff() end, false)

--- Put worn shoes back on after spawning
function Shoes.Reapply()
    local worn = lib.callback.await('nayzeee-sneakers:getWorn', false)
    Shoes.worn = worn and worn.meta or nil
    if worn and worn.clothing then
        SetPedComponentVariation(PlayerPedId(), 6, worn.clothing.drawable, worn.clothing.texture or 0, 0)
    end
end

--------------------------------------------------------------------------------
-- Using the shoes item
--------------------------------------------------------------------------------

RegisterNetEvent('nayzeee-sneakers:client:useShoes', function(slot, meta, hasEmptyBox, hasKit)
    if Busy then return end
    local shoe = Config.Shoes[meta.shoe]
    if not shoe then return end
    local T = Config.Text
    local dirt = math.floor(tonumber(meta.dirt) or 0)
    local options = {
        { id = 'inspect', label = T.inspect, icon = 'search', description = T.inspectDesc },
        { id = 'wear', label = T.wear, icon = 'shoe', description = T.wearDesc },
    }
    if hasEmptyBox then
        options[#options + 1] = { id = 'box', label = T.boxUp, icon = 'box', description = T.boxUpDesc }
    end
    if hasKit and dirt > 0 then
        options[#options + 1] = { id = 'clean', label = T.clean, icon = 'spark', description = T.cleanDesc:format(dirt) }
    end
    local choice = UI.Menu({
        title = Shared.ShoeName(meta),
        subtitle = ('US %s · %s · %s'):format(meta.size, Shared.ConditionLabel(meta.condition), meta.serial),
        image = shoe.image,
        options = options,
    })
    if choice == 'inspect' then Shoes.Inspect(meta)
    elseif choice == 'wear' then Shoes.PutOn(slot, meta)
    elseif choice == 'box' then Boxes.PackFromInventory(slot)
    elseif choice == 'clean' then Cleaning.Run(slot, meta) end
end)

exports('Inspect', Shoes.Inspect)
exports('TakeOff', Shoes.TakeOff)
