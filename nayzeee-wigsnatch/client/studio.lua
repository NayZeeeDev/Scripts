-- Wig Studio: photographs every hairstyle on a plain freemode head in front of a chroma
-- background, so every wig item shows its exact hairstyle. Admins only (/wigstudio).
-- Same idea as uz_AutoShot, built in and limited to hair.

Studio = { running = false, cancel = false }

local CS = Config.Studio
local HAIR = 2
local saved -- the admin's own look, put back afterwards
local cam

-- appearance save / restore ------------------------------------------------------------------------

local function saveLook(ped)
    local a = { model = GetEntityModel(ped), coords = GetEntityCoords(ped), heading = GetEntityHeading(ped), comps = {}, props = {}, face = {}, overlays = {} }
    for i = 0, 11 do a.comps[i] = { GetPedDrawableVariation(ped, i), GetPedTextureVariation(ped, i), GetPedPaletteVariation(ped, i) } end
    for i = 0, 7 do a.props[i] = { GetPedPropIndex(ped, i), GetPedPropTextureIndex(ped, i) } end
    local ok, hb = pcall(GetPedHeadBlendData, ped)
    if ok and type(hb) == 'table' then a.blend = hb end
    for i = 0, 19 do a.face[i] = GetPedFaceFeature(ped, i) end
    for i = 0, 12 do
        local okO, v, ct, c1, c2, o = GetPedHeadOverlayData(ped, i)
        a.overlays[i] = okO and { v, o, ct, c1, c2 } or { GetPedHeadOverlayValue(ped, i), 1.0, 0, 0, 0 }
    end
    a.hairColor = { GetPedHairColor(ped), GetPedHairHighlightColor(ped) }
    a.eyes = GetPedEyeColor(ped)
    return a
end

local function loadModel(hash)
    return pcall(lib.requestModel, hash, 8000)
end

local function restoreLook(a)
    if not a then return end
    if loadModel(a.model) then
        SetPlayerModel(PlayerId(), a.model)
        Wait(150)
        SetModelAsNoLongerNeeded(a.model)
    end
    local ped = PlayerPedId()
    local c = a.coords
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(ped, a.heading)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        Wait(0)
    end

    local hb = a.blend
    if hb then
        SetPedHeadBlendData(ped, hb.shapeFirst or hb[1] or 0, hb.shapeSecond or hb[2] or 0, hb.shapeThird or hb[3] or 0,
            hb.skinFirst or hb[4] or 0, hb.skinSecond or hb[5] or 0, hb.skinThird or hb[6] or 0,
            (hb.shapeMix or hb[7] or 0.0) + 0.0, (hb.skinMix or hb[8] or 0.0) + 0.0, (hb.thirdMix or hb[9] or 0.0) + 0.0, false)
    end
    for i = 0, 19 do SetPedFaceFeature(ped, i, a.face[i] or 0.0) end
    for i = 0, 12 do
        local o = a.overlays[i]
        if o and o[1] ~= 255 then
            SetPedHeadOverlay(ped, i, o[1], o[2] or 1.0)
            if (o[3] or 0) > 0 then SetPedHeadOverlayColor(ped, i, o[3], o[4] or 0, o[5] or 0) end
        else
            SetPedHeadOverlay(ped, i, 255, 0.0)
        end
    end
    for i = 0, 11 do
        local cp = a.comps[i]
        SetPedComponentVariation(ped, i, cp[1], cp[2], cp[3])
    end
    for i = 0, 7 do
        local p = a.props[i]
        if p[1] == -1 then ClearPedProp(ped, i) else SetPedPropIndex(ped, i, p[1], p[2], true) end
    end
    SetPedHairColor(ped, a.hairColor[1], a.hairColor[2])
    if a.eyes then SetPedEyeColor(ped, a.eyes) end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)
    -- appearance scripts with a reload command can put tattoos etc. back
    if GetResourceState('illenium-appearance') == 'started' then TriggerEvent('illenium-appearance:client:reloadSkin') end
    Hair.Reapply(800)
end

-- studio set ---------------------------------------------------------------------------------------

local function quad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, r, g, b)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, r, g, b, 255)
    DrawPoly(x3, y3, z3, x4, y4, z4, x1, y1, z1, r, g, b, 255)
    DrawPoly(x3, y3, z3, x2, y2, z2, x1, y1, z1, r, g, b, 255)
    DrawPoly(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, 255)
end

local function drawSet(pos)
    local r, g, b = 255, 0, 255
    if CS.Chroma == 'green' then r, g, b = 0, 177, 64 end
    local box = CS.Box
    local hw, hd = box.width * 0.5, box.depth * 0.5
    local fz = pos.z + box.floorOffset
    local cz = fz + box.height
    local x1, y1, x2, y2 = pos.x - hw, pos.y - hd, pos.x + hw, pos.y - hd
    local x3, y3, x4, y4 = pos.x - hw, pos.y + hd, pos.x + hw, pos.y + hd
    quad(x1, y1, fz, x2, y2, fz, x2, y2, cz, x1, y1, cz, r, g, b)
    quad(x4, y4, fz, x3, y3, fz, x3, y3, cz, x4, y4, cz, r, g, b)
    quad(x3, y3, fz, x1, y1, fz, x1, y1, cz, x3, y3, cz, r, g, b)
    quad(x2, y2, fz, x4, y4, fz, x4, y4, cz, x2, y2, cz, r, g, b)
    quad(x1, y1, fz, x2, y2, fz, x4, y4, fz, x3, y3, fz, r, g, b)
    quad(x3, y3, cz, x4, y4, cz, x2, y2, cz, x1, y1, cz, r, g, b)
    for _, l in ipairs(CS.Lights) do
        DrawLightWithRange(pos.x + l.offset.x, pos.y + l.offset.y, pos.z + l.offset.z, 255, 255, 255, l.range, l.intensity)
    end
end

local function renderLoop()
    CreateThread(function()
        while Studio.running do
            local ped = PlayerPedId()
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            HideHudAndRadarThisFrame()
            drawSet(GetEntityCoords(ped))
            DisableAllControlActions(0)
            if IsDisabledControlJustReleased(0, 177) or IsDisabledControlJustReleased(0, 200) or IsDisabledControlJustReleased(0, 322) then
                Studio.cancel = true
            end
            Wait(0)
        end
    end)
end

local function placeCamera(ped)
    local c = CS.Camera
    local pos = GetEntityCoords(ped)
    local ang = math.rad(c.angle)
    local cx, cy = pos.x + c.dist * math.sin(ang), pos.y - c.dist * math.cos(ang)
    local cz = pos.z + c.zPos + c.camZ
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', cx, cy, cz, 0.0, 0.0, 0.0, c.fov, false, 0)
    local dx, dy, dz = pos.x - cx, pos.y - cy, (pos.z + c.zPos) - cz
    SetCamRot(cam, math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), 0.0, -math.deg(math.atan(dx, dy)), 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function setupPed(model)
    local hash = model == 'm' and Config.Models.male.model or Config.Models.female.model
    if not loadModel(hash) then return nil end
    SetPlayerModel(PlayerId(), hash)
    Wait(150)
    SetModelAsNoLongerNeeded(hash)
    local ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, false)
    for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 0.0) end
    for _, p in ipairs({ 0, 1, 2, 6, 7 }) do ClearPedProp(ped, p) end
    for i = 1, 11 do
        if i ~= HAIR then SetPedComponentVariation(ped, i, i == 3 and 15 or 0, 0, 0) end
    end
    SetEntityCoordsNoOffset(ped, CS.Coords.x, CS.Coords.y, CS.Coords.z, false, false, false)
    SetEntityHeading(ped, CS.Heading)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    return ped
end

local function applyHair(ped, d, t)
    SetPedPreloadVariationData(ped, HAIR, d, t)
    local timeout = GetGameTimer() + 1000
    while not HasPedPreloadVariationDataFinished(ped) and GetGameTimer() < timeout do Wait(0) end
    SetPedComponentVariation(ped, HAIR, d, t, 0)
    SetPedHairColor(ped, CS.HairColor[1], CS.HairColor[2])
    ReleasePedPreloadVariationData(ped)
    OverrideLodscaleThisFrame(1.0)
    SetEntityLodDist(ped, 10000)
end

local function screenshot()
    local done, data = false, nil
    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(d) data = d done = true end)
    end)
    if not ok then return nil end
    local timeout = GetGameTimer() + 10000
    while not done and GetGameTimer() < timeout do Wait(50) end
    return data
end

-- capture --------------------------------------------------------------------------------------------

-- jobs = { { m = 'f', d = 12, t = 0 }, ... } or nil for "everything" on `model`
local function run(model, mode, list, have)
    Studio.running, Studio.cancel = true, false
    NUI.CloseApp()
    saved = saveLook(PlayerPedId())
    TriggerServerEvent('nz-wig:s:studioBucket', true)
    DoScreenFadeOut(300)
    Wait(400)

    local ped = setupPed(model)
    if not ped then
        Studio.running = false
        DoScreenFadeIn(300)
        TriggerServerEvent('nz-wig:s:studioBucket', false)
        return CB.Notify(L('studio_model_fail'), 'error')
    end
    renderLoop()
    Wait(300)
    placeCamera(ped)
    DoScreenFadeIn(300)

    local jobs = {}
    if mode == 'list' then
        for _, j in ipairs(list or {}) do
            if j.m == model then jobs[#jobs + 1] = { d = tonumber(j.d) or 0, t = tonumber(j.t) or 0 } end
        end
    else
        for d = 0, GetNumberOfPedDrawableVariations(ped, HAIR) - 1 do
            local maxT = CS.AllTextures and (GetNumberOfPedTextureVariations(ped, HAIR, d) - 1) or 0
            for t = 0, math.max(0, maxT) do
                if mode ~= 'missing' or not have[('%s/%d_%d'):format(model, d, t)] then jobs[#jobs + 1] = { d = d, t = t } end
            end
        end
    end

    NUI.Send('studio:run', { total = #jobs, model = model })
    for i, j in ipairs(jobs) do
        if Studio.cancel then break end
        applyHair(ped, j.d, j.t)
        Wait(CS.WaitAfterApply)
        local data = screenshot()
        if data and data ~= '' then
            TriggerLatentServerEvent('nz-wig:studioUpload', CS.LatentRate, {
                key = ('%s/%d_%d'):format(model, j.d, j.t), image = data,
                width = CS.Width, height = CS.Height, chroma = CS.Chroma, transparent = true,
            })
        else
            NUI.Send('studio:error', { msg = L('studio_no_screenshot') })
        end
        NUI.Send('studio:run', { total = #jobs, done = i, model = model, d = j.d, t = j.t })
        Wait(CS.WaitAfterShot)
        if i % CS.BatchSize == 0 then
            collectgarbage('collect')
            Wait(CS.BatchPause)
        end
    end

    DoScreenFadeOut(300)
    Wait(400)
    RenderScriptCams(false, false, 0, true, true)
    if cam then DestroyCam(cam, false) cam = nil end
    Studio.running = false
    restoreLook(saved)
    saved = nil
    TriggerServerEvent('nz-wig:s:studioBucket', false)
    DoScreenFadeIn(500)
    NUI.Send('studio:run', { finished = true, cancelled = Studio.cancel })
    CB.Notify(Studio.cancel and L('studio_cancelled') or L('studio_done', #jobs), Studio.cancel and 'warning' or 'success', 8000)
end

-- browser ---------------------------------------------------------------------------------------------

local function open()
    if Studio.running then return end
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    local data = lib.callback.await('nz-wig:studioOpen', false)
    if not data then return CB.Notify(L('studio_no_access'), 'error') end
    data.resource = RESOURCE
    data.screenshot = GetResourceState('screenshot-basic') == 'started'
    NUI.Open('studio', data)
end

if CS.Enabled and CS.Command then
    RegisterCommand(CS.Command, open, false)
end

RegisterNUICallback('studioCapture', function(d, cb)
    cb(1)
    if Studio.running or type(d) ~= 'table' then return end
    local model = d.model == 'm' and 'm' or 'f'
    local have = {}
    for _, k in ipairs(d.have or {}) do have[k] = true end
    CreateThread(function() run(model, d.mode, d.list, have) end)
end)

RegisterNUICallback('studioNames', function(d, cb)
    if type(d) == 'table' and type(d.names) == 'table' then TriggerServerEvent('nz-wig:s:studioNames', d.names) end
    cb(1)
end)

RegisterNUICallback('studioDelete', function(d, cb)
    if d and type(d.key) == 'string' then TriggerServerEvent('nz-wig:studioDelete', d.key) end
    cb(1)
end)

RegisterNetEvent('nz-wig:c:studioSaved', function(key, err)
    NUI.Send('studio:saved', { key = key, err = err })
end)

RegisterNetEvent('nz-wig:c:styleNames', function(names)
    if type(names) == 'table' then StyleNames = names end
end)

function Studio.Cleanup()
    if Studio.running then
        Studio.running = false
        RenderScriptCams(false, false, 0, true, true)
        if cam then DestroyCam(cam, false) end
        -- the resource is stopping, so the look can't be rebuilt here: relog or reload your skin
        TriggerServerEvent('nz-wig:s:studioBucket', false)
    end
end
