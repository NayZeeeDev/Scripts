local L = Config.Laptop
local MODEL = joaat(L.model)
local target = GetResourceState('ox_target') == 'started' and 'ox'
    or GetResourceState('qb-target') == 'started' and 'qb'
    or nil

local Props = {}        -- id -> { id, owner, coords, h, obj }
local me                -- our character identifier (for pickup permission)
local placing = false
local using             -- prop id currently in use
local cam, radarHidden

-- ── helpers ─────────────────────────────────────────────────────

local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vec3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function raycast(ignore)
    local origin = GetGameplayCamCoord()
    local dest = origin + rotToDir(GetGameplayCamRot(2)) * (L.placeDistance + 8.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, dest.x, dest.y, dest.z, 1 | 16, ignore, 4)
    local _, hit, coords, normal = GetShapeTestResult(ray)
    return hit == 1, coords, normal
end

local function playOnce(dict, clip, ms)
    lib.requestAnimDict(dict)
    TaskPlayAnim(PlayerPedId(), dict, clip, 5.0, 1.5, ms, 48, 0, false, false, false)
    RemoveAnimDict(dict)
end

local function canPickup(p) return L.anyoneCanPickup or p.owner == me end

-- ── camera ──────────────────────────────────────────────────────

local function zoomIn(obj)
    local c = L.camera
    local pos = GetOffsetFromEntityInWorldCoords(obj, c.offset.x, c.offset.y, c.offset.z)
    local look = GetOffsetFromEntityInWorldCoords(obj, c.target.x, c.target.y, c.target.z)
    local gc, gr = GetGameplayCamCoord(), GetGameplayCamRot(2)

    local from = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', gc.x, gc.y, gc.z, gr.x, gr.y, gr.z, GetGameplayCamFov(), true, 2)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, c.fov, false, 2)
    PointCamAtCoord(cam, look.x, look.y, look.z)

    RenderScriptCams(true, false, 0, true, true)
    SetCamActiveWithInterp(cam, from, c.ease, 1, 1)
    radarHidden = IsRadarHidden()
    DisplayRadar(false)
    Wait(c.ease)
    DestroyCam(from, false)
end

local function zoomOut()
    if not cam then return end
    RenderScriptCams(false, true, L.camera.ease, true, true)
    Wait(L.camera.ease)
    DestroyCam(cam, false)
    cam = nil
    if not radarHidden then DisplayRadar(true) end
end

-- ── use / pick up ───────────────────────────────────────────────

local function useLaptop(p)
    if Trading.busy or Trading.open or not p.obj then return end
    Trading.busy = true

    local ok, err = lib.callback.await('nz_trading:props:use', false, p.id)
    if not ok then
        Trading.busy = false
        return Trading.Notify(err or 'Unavailable', 'error')
    end

    local ped, obj = PlayerPedId(), p.obj
    if L.walkToLaptop then
        local stand = GetOffsetFromEntityInWorldCoords(obj, L.standOffset.x, L.standOffset.y, L.standOffset.z)
        TaskGoStraightToCoord(ped, stand.x, stand.y, GetEntityCoords(ped).z, 1.0, 2500, GetEntityHeading(obj), 0.05)
        local timeout = GetGameTimer() + 2500
        while GetGameTimer() < timeout and #(GetEntityCoords(ped).xy - stand.xy) > 0.3 do Wait(50) end
    end
    TaskTurnPedToFaceEntity(ped, obj, 600)
    Wait(600)

    lib.requestAnimDict(L.anim.dict)
    TaskPlayAnim(ped, L.anim.dict, L.anim.clip, 3.0, 3.0, -1, 1, 0, false, false, false)
    zoomIn(obj)
    using = p.id

    local function done()
        zoomOut()
        StopAnimTask(ped, L.anim.dict, L.anim.clip, 2.0)
        RemoveAnimDict(L.anim.dict)
        TriggerServerEvent('nz_trading:props:release', p.id)
        using = nil
        Trading.busy = false
    end

    if not Trading.Open('laptop', done) then done() end
end

local function pickup(p)
    if Trading.busy or not p.obj then return end
    Trading.busy = true
    TaskTurnPedToFaceEntity(PlayerPedId(), p.obj, 500)
    Wait(450)
    playOnce('pickup_object', 'pickup_low', 1000)
    Wait(800)
    local ok, err = lib.callback.await('nz_trading:props:pickup', false, p.id)
    if not ok then Trading.Notify(err or 'Could not pick up', 'error') end
    Trading.busy = false
end

-- ── placement ───────────────────────────────────────────────────

local BLOCKED = { 14, 15, 16, 17, 24, 25, 37, 44, 140, 141, 142, 257, 263 }

local function placeLaptop()
    if placing or Trading.busy or Trading.open then return end
    placing = true
    Trading.busy = true

    local ped = PlayerPedId()
    lib.requestModel(MODEL)
    local ghost = CreateObjectNoOffset(MODEL, GetEntityCoords(ped), false, false, false)
    SetEntityCollision(ghost, false, false)
    SetEntityAlpha(ghost, 200, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutlineShader(1)
    SetEntityDrawOutline(ghost, true)

    local minDim = GetModelDimensions(MODEL)
    local heading = (GetEntityHeading(ped) + 180.0) % 360.0
    local result

    Trading.Hint('Place laptop', { { 'E', 'Place' }, { 'Scroll', 'Rotate' }, { 'Shift', 'Fine' }, { 'Backspace', 'Cancel' } })

    while placing do
        for i = 1, #BLOCKED do DisableControlAction(0, BLOCKED[i], true) end

        local hit, pos, normal = raycast(ped)
        local valid = hit and normal.z > 0.7 and #(GetEntityCoords(ped) - pos) <= L.placeDistance
        if hit then SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z - minDim.z, false, false, false) end

        local step = IsControlPressed(0, 21) and 1.0 or L.rotateStep
        if IsDisabledControlJustPressed(0, 15) then heading = (heading + step) % 360.0 end
        if IsDisabledControlJustPressed(0, 14) then heading = (heading - step) % 360.0 end
        SetEntityHeading(ghost, heading)

        if valid then SetEntityDrawOutlineColor(8, 175, 162, 255) else SetEntityDrawOutlineColor(229, 72, 77, 255) end

        if valid and IsControlJustPressed(0, 38) then
            result = { coords = GetEntityCoords(ghost), heading = heading }
            placing = false
        elseif IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then
            placing = false
        end
        Wait(0)
    end

    Trading.Hint(false)
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(MODEL)

    if result then
        TaskTurnPedToFaceCoord(ped, result.coords.x, result.coords.y, result.coords.z, 500)
        Wait(400)
        playOnce('pickup_object', 'putdown_low', 1000)
        Wait(700)
        local ok, err = lib.callback.await('nz_trading:props:place', false, result.coords, result.heading)
        if not ok then Trading.Notify(err or 'Could not place laptop', 'error') end
    end
    Trading.busy = false
end

RegisterNetEvent('nz_trading:client:placeLaptop', placeLaptop)
exports('placeLaptop', placeLaptop)

-- ── targets ─────────────────────────────────────────────────────

local function addTarget(p)
    local range = L.interactRange + 0.6
    if target == 'ox' then
        exports.ox_target:addLocalEntity(p.obj, {
            { name = 'nz_trading_use', icon = 'fa-solid fa-chart-line', label = 'Use laptop', distance = range,
              canInteract = function() return not Trading.busy end, onSelect = function() useLaptop(p) end },
            { name = 'nz_trading_pickup', icon = 'fa-solid fa-hand', label = 'Pick up laptop', distance = range,
              canInteract = function() return not Trading.busy and canPickup(p) end, onSelect = function() pickup(p) end },
        })
    elseif target == 'qb' then
        exports['qb-target']:AddTargetEntity(p.obj, {
            options = {
                { icon = 'fas fa-chart-line', label = 'Use laptop', canInteract = function() return not Trading.busy end, action = function() useLaptop(p) end },
                { icon = 'fas fa-hand', label = 'Pick up laptop', canInteract = function() return not Trading.busy and canPickup(p) end, action = function() pickup(p) end },
            },
            distance = range,
        })
    end
end

local function removeTarget(p)
    if target == 'ox' then
        exports.ox_target:removeLocalEntity(p.obj, { 'nz_trading_use', 'nz_trading_pickup' })
    elseif target == 'qb' then
        exports['qb-target']:RemoveTargetEntity(p.obj)
    end
end

-- ── streaming ───────────────────────────────────────────────────

local function spawn(p)
    lib.requestModel(MODEL)
    p.obj = CreateObjectNoOffset(MODEL, p.coords.x, p.coords.y, p.coords.z, false, false, false)
    SetEntityHeading(p.obj, p.h)
    FreezeEntityPosition(p.obj, true)
    SetModelAsNoLongerNeeded(MODEL)
    addTarget(p)
end

local function despawn(p)
    removeTarget(p)
    DeleteEntity(p.obj)
    p.obj = nil
end

local function addProp(d)
    Props[d.id] = { id = d.id, owner = d.owner, coords = vec3(d.x, d.y, d.z), h = d.h }
end

RegisterNetEvent('nz_trading:props:add', addProp)

RegisterNetEvent('nz_trading:props:remove', function(id)
    local p = Props[id]
    if not p then return end
    if using == id then Trading.RequestClose() end
    if p.obj then despawn(p) end
    Props[id] = nil
end)

CreateThread(function()
    me = lib.callback.await('nz_trading:me', false)
    for _, d in ipairs(lib.callback.await('nz_trading:props:list', false) or {}) do addProp(d) end

    while true do
        local sleep = 2000
        if next(Props) then
            sleep = 1000
            local pc = GetEntityCoords(PlayerPedId())
            for _, p in pairs(Props) do
                local d = #(pc - p.coords)
                if d < L.streamDistance then
                    if not p.obj then spawn(p) end
                elseif p.obj and d > L.streamDistance + 10.0 then
                    despawn(p)
                end
            end
        end
        Wait(sleep)
    end
end)

local function refreshIdentity() me = lib.callback.await('nz_trading:me', false) end
RegisterNetEvent('esx:playerLoaded', refreshIdentity)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshIdentity)

-- ── desk terminals ──────────────────────────────────────────────

local function useTerminal()
    if Trading.busy or Trading.open then return end
    Trading.busy = true
    if not Trading.Open('laptop', function() Trading.busy = false end) then Trading.busy = false end
end

for i, t in ipairs(Config.Terminals) do
    if t.blip then
        local blip = AddBlipForCoord(t.coords.x, t.coords.y, t.coords.z)
        SetBlipSprite(blip, t.blip.sprite)
        SetBlipColour(blip, t.blip.color)
        SetBlipScale(blip, t.blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(t.blip.label)
        EndTextCommandSetBlipName(blip)
    end
    if target == 'ox' then
        exports.ox_target:addSphereZone({
            coords = t.coords, radius = t.radius,
            options = { { name = 'nz_trading_terminal', icon = 'fa-solid fa-chart-line', label = t.label, onSelect = useTerminal } },
        })
    elseif target == 'qb' then
        exports['qb-target']:AddCircleZone('nz_trading_terminal_' .. i, t.coords, t.radius, { name = 'nz_trading_terminal_' .. i },
            { options = { { icon = 'fas fa-chart-line', label = t.label, action = useTerminal } }, distance = 2.0 })
    end
end

-- ── proximity fallback when no target resource is running ───────

if not target then
    local function nearest()
        local pc = GetEntityCoords(PlayerPedId())
        for _, p in pairs(Props) do
            if p.obj and #(pc - p.coords) <= L.interactRange then return p, p.coords, L.interactRange end
        end
        for _, t in ipairs(Config.Terminals) do
            if #(pc - t.coords) <= t.radius then return t, t.coords, t.radius end
        end
    end

    CreateThread(function()
        while true do
            local hit, at, range
            if not Trading.busy and not Trading.open then hit, at, range = nearest() end
            if hit then
                local isProp = hit.id ~= nil
                local keys = { { 'E', isProp and 'Use laptop' or hit.label } }
                if isProp and canPickup(hit) then keys[2] = { 'G', 'Pick up' } end
                Trading.Hint(isProp and 'Trading laptop' or hit.label, keys)

                while not Trading.busy and #(GetEntityCoords(PlayerPedId()) - at) <= range do
                    if IsControlJustPressed(0, 38) then
                        Trading.Hint(false)
                        if isProp then useLaptop(hit) else useTerminal() end
                        break
                    elseif isProp and keys[2] and IsControlJustPressed(0, 47) then
                        Trading.Hint(false)
                        pickup(hit)
                        break
                    end
                    Wait(0)
                end
                Trading.Hint(false)
            end
            Wait(hit and 200 or 800)
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in pairs(Props) do
        if p.obj then DeleteEntity(p.obj) end
    end
    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        DisplayRadar(true)
    end
end)
