-----------------------------------------------------------------
-- Backpack studio
--
-- Browse every configured backpack, preview it on your back,
-- swap texture variants, tune the attach offset, and frame the
-- prop for an inventory icon. Only loads when Config.Debug.
-----------------------------------------------------------------

if not Config.Debug then return end

local open       = false
local preview    = nil
local currentKey = nil
local variant    = 0

local iconMode   = false
local iconCam    = nil
local iconProp   = nil

-- studio camera: frames the ped between the two panels
local studioCam  = nil
local camOrbit   = 155.0  -- angle around the ped
local camDist    = 2.05
local camHeight  = 0.55
-- With panels pinned to both top corners the middle of the screen is clear,
-- so the ped sits dead centre. Raise this to nudge them off-centre.
local camShift   = 0.0

local tune = {
    bone = Config.DefaultOffset.bone,
    pos  = { x = Config.DefaultOffset.pos.x, y = Config.DefaultOffset.pos.y, z = Config.DefaultOffset.pos.z },
    rot  = { x = Config.DefaultOffset.rot.x, y = Config.DefaultOffset.rot.y, z = Config.DefaultOffset.rot.z },
}

local BONES = {
    { id = 24818, label = 'Spine Root' },
    { id = 24817, label = 'Spine 1' },
    { id = 24816, label = 'Spine 2' },
    { id = 0,     label = 'Root' },
    { id = 31086, label = 'Head' },
    { id = 28252, label = 'Right Hand' },
    { id = 60309, label = 'Left Hand' },
    { id = 10706, label = 'Left Shoulder' },
    { id = 64729, label = 'Right Shoulder' },
    { id = 11816, label = 'Left Forearm' },
    { id = 28422, label = 'Right Forearm' },
    { id = 51826, label = 'Right Foot' },
}

-- Starting points for the common ways a bag is worn. These get you close;
-- fine-tune from there with the sliders.
local CARRY = {
    {
        key = 'back', label = 'Back',
        bone = 24818,
        pos = { x = -0.270, y = 0.010, z = -0.020 },
        rot = { x = 0.0, y = 90.0, z = 175.0 },
    },
    {
        key = 'crossbody', label = 'Crossbody',
        bone = 24817,  -- spine 1, sits higher and to the side
        pos = { x = -0.140, y = 0.150, z = -0.050 },
        rot = { x = 0.0, y = 75.0, z = 200.0 },
    },
    {
        key = 'shoulder_l', label = 'Left shoulder',
        bone = 10706,
        pos = { x = 0.050, y = 0.090, z = -0.020 },
        rot = { x = 0.0, y = 90.0, z = 180.0 },
    },
    {
        key = 'shoulder_r', label = 'Right shoulder',
        bone = 64729,
        pos = { x = 0.050, y = -0.090, z = -0.020 },
        rot = { x = 0.0, y = 90.0, z = 0.0 },
    },
    {
        key = 'hip', label = 'Hip / waist',
        bone = 0,
        pos = { x = -0.180, y = 0.120, z = 0.640 },
        rot = { x = 0.0, y = 90.0, z = 185.0 },
    },
    {
        key = 'hand_r', label = 'In right hand',
        bone = 28252,
        pos = { x = 0.090, y = 0.020, z = -0.030 },
        rot = { x = 90.0, y = 0.0, z = 0.0 },
    },
}

-----------------------------------------------------------------
-- model helpers
-----------------------------------------------------------------

local function loadModel(model)
    local hash = joaat(model)

    if not IsModelInCdimage(hash) then
        Config.Notify(('Model "%s" is not registered — check its .ytyp is declared in fxmanifest.'):format(model), 'error')
        print(('^1[nayzeee-backpack] "%s" missing. Needs .ydr + .ytd + .ytyp in stream/, and a data_file DLC_ITYP_REQUEST line for the ytyp.^0'):format(model))
        return nil
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then
            Config.Notify(('Model "%s" failed to load.'):format(model), 'error')
            return nil
        end
    end
    return hash
end

local function destroyPreview()
    if preview and DoesEntityExist(preview) then
        DetachEntity(preview, true, true)
        DeleteEntity(preview)
    end
    preview = nil
end

local function applyOffset()
    if not preview or not DoesEntityExist(preview) then return end
    local ped = PlayerPedId()
    AttachEntityToEntity(
        preview, ped, GetPedBoneIndex(ped, tune.bone),
        tune.pos.x, tune.pos.y, tune.pos.z,
        tune.rot.x, tune.rot.y, tune.rot.z,
        true, true, false, true, 1, true
    )
end

local function applyVariant()
    if preview and DoesEntityExist(preview) then
        SetObjectTextureVariation(preview, variant)
    end
    if iconProp and DoesEntityExist(iconProp) then
        SetObjectTextureVariation(iconProp, variant)
    end
end

local function spawnPreview(bagKey)
    destroyPreview()

    local bag = Config.Backpacks[bagKey]
    if not bag then return false end

    local hash = loadModel(bag.model)
    if not hash then return false end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    preview = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetEntityCollision(preview, false, false)
    SetModelAsNoLongerNeeded(hash)

    currentKey = bagKey
    variant = 0

    -- start from this bag's own offset if it has one
    local o, d = bag.offset, Config.DefaultOffset
    tune.bone = (o and o.bone) or d.bone
    local p = (o and o.pos) or d.pos
    local r = (o and o.rot) or d.rot
    tune.pos = { x = p.x, y = p.y, z = p.z }
    tune.rot = { x = r.x, y = r.y, z = r.z }

    applyOffset()
    applyVariant()
    return true
end

-----------------------------------------------------------------
-- studio camera
-----------------------------------------------------------------

local function updateStudioCam()
    if not studioCam then return end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local rad = math.rad(camOrbit)

    local camX = c.x + math.sin(rad) * camDist
    local camY = c.y + math.cos(rad) * camDist
    local camZ = c.z + camHeight

    -- aim at chest height so the ped is centred in frame rather than
    -- sitting low with empty space above their head
    local aimZ = c.z + 0.45

    if camShift ~= 0.0 then
        local perp = rad + math.pi / 2
        camX = camX + math.sin(perp) * camShift
        camY = camY + math.cos(perp) * camShift
    end

    SetCamCoord(studioCam, camX, camY, camZ)
    PointCamAtCoord(studioCam, c.x, c.y, aimZ)
end

local function startStudioCam()
    if studioCam then return end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)

    studioCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        c.x, c.y + camDist, c.z + camHeight, 0.0, 0.0, 0.0, 45.0, false, 0)

    SetCamActive(studioCam, true)
    RenderScriptCams(true, true, 550, true, true)
    updateStudioCam()
end

local function stopStudioCam()
    if not studioCam then return end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(studioCam, false)
    studioCam = nil
end

-----------------------------------------------------------------
-- icon capture
--
-- Frames the prop against the sky with the world hidden, so the
-- shot has a clean edge to cut out.
-----------------------------------------------------------------

local function stopIconMode()
    iconMode = false

    if iconProp and DoesEntityExist(iconProp) then DeleteEntity(iconProp) end
    iconProp = nil

    if iconCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(iconCam, false)
        iconCam = nil
    end

    DisplayRadar(true)
    SetEntityVisible(PlayerPedId(), true, false)
    FreezeEntityPosition(PlayerPedId(), false)

    if open then startStudioCam() end
end

-- Hide the HUD while framing an icon.
-- Started on demand instead of looping forever: the old version ran a
-- per-frame thread for the whole session even with the studio closed.
local function runIconHudThread()
    CreateThread(function()
        while iconMode do
            HideHudAndRadarThisFrame()
            for i = 1, 21 do HideHudComponentThisFrame(i) end
            Wait(0)
        end
    end)
end

local function startIconMode()
    local bag = Config.Backpacks[currentKey]
    if not bag then return false end

    stopStudioCam()

    local hash = loadModel(bag.model)
    if not hash then return false end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)

    -- Default: lift well above the map so nothing but sky is behind the prop.
    -- With stagingCoords set, use that instead — point it at a green screen
    -- MLO and you get a flat key colour that cuts out cleanly.
    local staging = Config.IconCapture.stagingCoords
    local x, y, z

    if staging then
        x, y, z = staging.x, staging.y, staging.z
    else
        x, y, z = c.x, c.y, c.z + (Config.IconCapture.stagingHeight or 180.0)
    end

    iconProp = CreateObject(hash, x, y, z, false, false, false)
    SetEntityCollision(iconProp, false, false)
    FreezeEntityPosition(iconProp, true)
    SetEntityHeading(iconProp, Config.IconCapture.heading or 210.0)
    SetModelAsNoLongerNeeded(hash)
    applyVariant()

    -- centre on the model rather than its origin, or tall bags sit off-frame
    local minDim, maxDim = GetModelDimensions(hash)
    local midZ = (minDim.z + maxDim.z) * 0.5

    local dist = Config.IconCapture.distance or 1.15
    iconCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        x, y - dist, z + midZ,
        Config.IconCapture.pitch or -8.0, 0.0, 0.0,
        40.0, false, 0)

    PointCamAtEntity(iconCam, iconProp, 0.0, 0.0, midZ, true)
    SetCamActive(iconCam, true)
    RenderScriptCams(true, false, 0, true, true)

    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)

    iconMode = true
    runIconHudThread()
    return true
end


local function captureIcon(cb)
    -- screenshot-basic is optional; without it the prop stays framed
    -- and the user grabs the shot themselves
    if GetResourceState('screenshot-basic') ~= 'started' then
        Config.Notify('Framed. Screenshot manually, or install screenshot-basic to save automatically.', 'inform')
        if cb then cb(false) end
        return
    end

    exports['screenshot-basic']:requestScreenshotUpload(
        'https://api.fivemanage.com/api/image', -- replace with your own upload target
        'files[]',
        { encoding = 'png', quality = 1.0 },
        function(data)
            Config.Notify('Icon captured.', 'success')
            print('[nayzeee-backpack] screenshot response: ' .. tostring(data))
            if cb then cb(true) end
        end
    )
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

local function payload()
    local bags = {}
    for key, bag in pairs(Config.Backpacks) do
        local storage = Config.GetStorage(key)
        local vars = {}

        if bag.variants then
            for idx, label in pairs(bag.variants) do
                vars[#vars + 1] = { index = idx, label = label }
            end
            table.sort(vars, function(a, b) return a.index < b.index end)
        end

        bags[#bags + 1] = {
            key      = key,
            label    = bag.label or key,
            model    = bag.model,
            slots    = storage.slots,
            weight   = storage.weight,
            variants = vars,
            hasOffset = bag.offset ~= nil,
        }
    end
    table.sort(bags, function(a, b) return a.label < b.label end)

    return {
        bags     = bags,
        bones    = BONES,
        carry    = CARRY,
        current  = currentKey,
        variant  = variant,
        tune     = tune,
        iconMode = iconMode,
        cam      = { orbit = camOrbit, dist = camDist, height = camHeight },
        heading  = GetEntityHeading(PlayerPedId()),
    }
end

local function push(action)
    SendNUIMessage({ action = action or 'refresh', data = payload() })
end

local function setOpen(state)
    open = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = state and 'open' or 'close', data = state and payload() or nil })

    if state then
        startStudioCam()
    else
        stopIconMode()
        stopStudioCam()
        destroyPreview()
    end
end

RegisterCommand('bagtune', function()
    if open then return setOpen(false) end

    local first
    for key in pairs(Config.Backpacks) do first = first or key end
    if not first then
        return Config.Notify('No backpacks defined in Config.Backpacks.', 'error')
    end

    if spawnPreview(currentKey or first) then setOpen(true) end
end, false)

RegisterKeyMapping('bagtune', 'Open backpack studio', 'keyboard', '')

RegisterNUICallback('close', function(_, cb) setOpen(false); cb('ok') end)

RegisterNUICallback('update', function(data, cb)
    if data.pos then
        tune.pos.x = tonumber(data.pos.x) or tune.pos.x
        tune.pos.y = tonumber(data.pos.y) or tune.pos.y
        tune.pos.z = tonumber(data.pos.z) or tune.pos.z
    end
    if data.rot then
        tune.rot.x = tonumber(data.rot.x) or tune.rot.x
        tune.rot.y = tonumber(data.rot.y) or tune.rot.y
        tune.rot.z = tonumber(data.rot.z) or tune.rot.z
    end
    if data.bone then tune.bone = tonumber(data.bone) or tune.bone end
    applyOffset()
    cb('ok')
end)

RegisterNUICallback('selectBag', function(data, cb)
    if data.key and Config.Backpacks[data.key] then
        local wasIcon = iconMode
        if wasIcon then stopIconMode() end
        spawnPreview(data.key)
        if wasIcon then startIconMode() end
        push()
    end
    cb('ok')
end)

RegisterNUICallback('setVariant', function(data, cb)
    variant = tonumber(data.index) or 0
    applyVariant()
    push()
    cb('ok')
end)

--- Jump to one of the preset carry styles.
RegisterNUICallback('carry', function(data, cb)
    for _, preset in ipairs(CARRY) do
        if preset.key == data.key then
            tune.bone = preset.bone
            tune.pos = { x = preset.pos.x, y = preset.pos.y, z = preset.pos.z }
            tune.rot = { x = preset.rot.x, y = preset.rot.y, z = preset.rot.z }
            applyOffset()
            push()
            break
        end
    end
    cb('ok')
end)

RegisterNUICallback('reset', function(_, cb)
    local d = Config.DefaultOffset
    tune.bone = d.bone
    tune.pos = { x = d.pos.x, y = d.pos.y, z = d.pos.z }
    tune.rot = { x = d.rot.x, y = d.rot.y, z = d.rot.z }
    applyOffset()
    push()
    cb('ok')
end)

--- Spin the ped. `absolute` sets the heading outright, for slider dragging.
RegisterNUICallback('camera', function(data, cb)
    local ped = PlayerPedId()

    if data.absolute then
        SetEntityHeading(ped, (tonumber(data.absolute) or 0.0) % 360.0)
    else
        SetEntityHeading(ped, GetEntityHeading(ped) + (tonumber(data.delta) or 45.0))
    end

    updateStudioCam()
    cb('ok')
end)

--- Orbit / zoom the studio camera itself.
RegisterNUICallback('orbit', function(data, cb)
    if data.orbit  then camOrbit  = (tonumber(data.orbit) or camOrbit) % 360.0 end
    if data.dist   then camDist   = math.max(0.9, math.min(4.5, tonumber(data.dist) or camDist)) end
    if data.height then camHeight = math.max(-0.8, math.min(1.4, tonumber(data.height) or camHeight)) end
    updateStudioCam()
    cb('ok')
end)

RegisterNUICallback('anim', function(data, cb)
    Anim.playAsync(data.name or 'equip')
    cb('ok')
end)

RegisterNUICallback('iconMode', function(data, cb)
    if data.on then
        if startIconMode() then push() end
    else
        stopIconMode()
        push()
    end
    cb('ok')
end)

RegisterNUICallback('iconSpin', function(data, cb)
    if iconProp and DoesEntityExist(iconProp) then
        SetEntityHeading(iconProp, GetEntityHeading(iconProp) + (tonumber(data.delta) or 15.0))
    end
    cb('ok')
end)

RegisterNUICallback('iconZoom', function(data, cb)
    if iconCam and iconProp then
        local c = GetEntityCoords(iconProp)
        local d = math.max(0.4, math.min(4.0, (tonumber(data.distance) or 1.15)))
        SetCamCoord(iconCam, c.x, c.y - d, c.z + 0.12)
    end
    cb('ok')
end)

RegisterNUICallback('capture', function(_, cb)
    -- drop the UI for a frame so it isn't in the shot
    SendNUIMessage({ action = 'hideForShot' })
    SetNuiFocus(false, false)
    Wait(250)
    captureIcon(function()
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'showAfterShot' })
    end)
    cb('ok')
end)

RegisterNUICallback('copied', function(_, cb)
    Config.Notify('Copied to clipboard.', 'success')
    cb('ok')
end)

-----------------------------------------------------------------

-- Track the ped with the studio camera, but only while the studio is open.
-- Idles at 1s instead of 120ms when there's nothing to follow.
CreateThread(function()
    while true do
        if studioCam and not iconMode then
            updateStudioCam()
            Wait(120)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then SetNuiFocus(false, false) end
    stopIconMode()
    stopStudioCam()
    destroyPreview()
end)
