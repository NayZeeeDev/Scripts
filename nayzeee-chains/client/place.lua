-----------------------------------------------------------------
-- Setting a chain down
--
-- The ghost follows where you look (a raycast from the camera), so
-- it goes on the floor, a table, the bar, anywhere in reach.
-- [E] place  [SCROLL] turn (SHIFT fine)  [UP/DOWN] tilt  [BACKSPACE] cancel
--
-- Written for resmon like the backpack one: natives as upvalues, an
-- async shape test read the next frame, the ghost only moved when
-- something changed, the hint sent once.
-----------------------------------------------------------------

Place = {}

local cfg = Config.Place
local placing = false

local Wait = Wait
local PlayerPedId = PlayerPedId
local DisableControlAction = DisableControlAction
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local IsDisabledControlPressed = IsDisabledControlPressed
local GetFinalRenderedCamCoord = GetFinalRenderedCamCoord
local GetFinalRenderedCamRot = GetFinalRenderedCamRot
local StartShapeTestLosProbe = StartShapeTestLosProbe
local GetShapeTestResult = GetShapeTestResult
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SetEntityRotation = SetEntityRotation
local GetEntityCoords = GetEntityCoords
local msin, mcos, mrad, mabs = math.sin, math.cos, math.rad, math.abs

local BLOCK = { 14, 15, 16, 17, 24, 25, 37, 38, 44, 45, 47, 140, 141, 142, 172, 173, 177, 194, 200, 241, 242, 257, 263, 264 }
local NBLOCK = #BLOCK

function Place.active() return placing end

--- Where the entity origin goes so the lowest point of the turned mesh rests on the hit.
local function originFor(hit, rot, centre, mn, mx)
    local R = M3.euler(rot.x, rot.y, rot.z)
    local low = math.huge
    for _, cx in ipairs({ mn.x, mx.x }) do
        for _, cy in ipairs({ mn.y, mx.y }) do
            for _, cz in ipairs({ mn.z, mx.z }) do
                local p = M3.apply(R, vector3(cx, cy, cz) - centre)
                if p.z < low then low = p.z end
            end
        end
    end
    local meshCentre = hit + vector3(0.0, 0.0, -low + 0.004)
    return meshCentre - M3.apply(R, centre)
end

--- Start placing. from = 'worn' (off the neck / hand) or 'slot' (straight from the pockets).
function Place.start(key, letter, from, slot)
    if placing or not cfg.Enabled or not Chains.exists(key) then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return CB.Notify(Config.Text.bad_spot, 'error') end

    local ghost, hash = Util.spawnChain(key, letter, GetEntityCoords(ped))
    if not ghost then return end
    FreezeEntityPosition(ghost, true)
    SetEntityAlpha(ghost, 210, false)
    local centre, mn, mx = Util.modelCentre(hash)

    placing = true
    if from == 'worn' then WornProps.hideSelf(true) end
    NUI.hint(Config.Text.hint_place, 'place')

    CreateThread(function()
        local rot = { x = 0.0, y = 0.0, z = (GetEntityHeading(ped) + 180.0) % 360.0 }
        local step, tilt = cfg.RotateStep or 10.0, cfg.TiltStep or 10.0
        local reach = cfg.MaxDistance or 3.5
        local slope = cfg.MaxSlope or 0.55
        local reachSq = reach * reach
        local shape, hit = nil, nil
        local valid, shownValid = false, true
        local last, lastRot = vector3(0, 0, 0), ''
        local placed = false

        while placing do
            for i = 1, NBLOCK do DisableControlAction(0, BLOCK[i], true) end

            if shape then
                local status, h, endCoords, normal = GetShapeTestResult(shape)
                if status ~= 1 then
                    shape = nil
                    if status == 2 then
                        if h == 1 and normal.z >= slope then
                            local pc = GetEntityCoords(ped)
                            local d = endCoords - pc
                            valid = (d.x * d.x + d.y * d.y + d.z * d.z) <= reachSq
                            hit = endCoords
                        else
                            valid = false
                        end
                    end
                end
            end
            if not shape then
                local cam = GetFinalRenderedCamCoord()
                local r = GetFinalRenderedCamRot(2)
                local rx, rz = mrad(r.x), mrad(r.z)
                local cxr = mabs(mcos(rx))
                local len = reach + 8.0
                shape = StartShapeTestLosProbe(cam.x, cam.y, cam.z,
                    cam.x - msin(rz) * cxr * len, cam.y + mcos(rz) * cxr * len, cam.z + msin(rx) * len,
                    1 | 16, ped, 7)
            end

            local fine = IsDisabledControlPressed(0, 21)
            local s = fine and step * 0.2 or step
            if IsDisabledControlJustPressed(0, 241) then rot.z = (rot.z + s) % 360.0
            elseif IsDisabledControlJustPressed(0, 242) then rot.z = (rot.z - s) % 360.0 end
            local t = fine and tilt * 0.3 or tilt
            if IsDisabledControlJustPressed(0, 172) then rot.x = Util.wrap180(rot.x + t)
            elseif IsDisabledControlJustPressed(0, 173) then rot.x = Util.wrap180(rot.x - t) end

            local rk = ('%.2f|%.2f'):format(rot.x, rot.z)
            if hit and (#(hit - last) > 0.002 or rk ~= lastRot) then
                last, lastRot = hit, rk
                local o = originFor(hit, rot, centre, mn, mx)
                SetEntityCoordsNoOffset(ghost, o.x, o.y, o.z, false, false, false)
                SetEntityRotation(ghost, rot.x, rot.y, rot.z, 2, false)
            end
            if valid ~= shownValid then
                shownValid = valid
                SetEntityAlpha(ghost, valid and 210 or 70, false)
            end

            if IsDisabledControlJustPressed(0, 38) then -- E
                if valid and hit then
                    local o = originFor(hit, rot, centre, mn, mx)
                    placing = false
                    Util.delete(ghost)
                    ghost = nil
                    NUI.hint(nil)
                    TaskTurnPedToFaceCoord(ped, hit.x, hit.y, hit.z, 500)
                    Wait(450)
                    local a = Config.Drops.PickupAnim
                    if Util.loadDict(a.dict) then
                        TaskPlayAnim(ped, a.dict, a.clip, 6.0, -4.0, a.duration or 1100, 48, 0, false, false, false)
                        Wait(650)
                    end
                    TriggerServerEvent('nzc:s:place', from, slot, { x = o.x, y = o.y, z = o.z }, { x = rot.x, y = rot.y, z = rot.z })
                    placed = true
                    break
                else
                    CB.Notify(hit and Config.Text.too_far or Config.Text.bad_spot, 'error')
                end
            end

            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
                break
            end
            Wait(0)
        end

        placing = false
        if ghost then Util.delete(ghost) end
        NUI.hint(nil)
        if from == 'worn' then
            -- keep it hidden until the server has taken it off, so it doesn't flash back on the neck
            if placed then Wait(600) end
            WornProps.hideSelf(false)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then placing = false end
end)
