-- Wig Studio (/wigstudio, admins): built the same way as the nayzeee-backpack icon studio.
--   * a local freemode head floats in a lit chroma box under the map, your own ped never changes
--   * an orbit camera frames the hair (drag / scroll / angle presets) between the two panels
--   * screenshot-basic grabs the frame, the NUI keys it into a small PNG (web/js/keyer.js)
--   * the server writes shots/wig_<m|f>_<drawable>_<texture>.png (+ a copy in the database) and copies it into ox_inventory
-- One hairstyle at a time, or every hairstyle in a batch that waits for each save.

Studio = {}

local CS = Config.Studio
local HAIR = 2
local HEAD_BONE = 31086
local CHROMA = { green = { 0, 177, 64 }, magenta = { 255, 0, 255 }, blue = { 0, 71, 187 } }

local active = false
local ped, cam = nil, nil
local model, drawable, texture = 'f', 0, 0
local list = {}                         -- { { d, n, bald } } for the current model
local centre = vector3(0, 0, 0)         -- head position the camera orbits
local orbit = { yaw = CS.Orbit.yaw, elev = CS.Orbit.elev, zoom = CS.Orbit.zoom, lift = CS.Orbit.lift }
local chroma = CHROMA[CS.Chroma] and CS.Chroma or 'green'
local batch = nil                       -- { i, n } while a batch runs
local waiting = nil                     -- file name we're waiting on the keyer + server for

local function stage() return CS.Coords end
local function hasScreenshot() return GetResourceState('screenshot-basic') == 'started' end
local function fileName(m, d, t) return ('wig_%s_%d_%d'):format(m, d, t) end

local function sendState(full)
    NUI.Send('studio:state', {
        model = model, d = drawable, t = texture, list = full and list or nil,
        chroma = chroma, orbit = orbit, batch = batch, screenshot = hasScreenshot(),
    })
end

-- the head --------------------------------------------------------------------------------------------

local function deletePed()
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    ped = nil
end

local function applyHair(d, t)
    if not ped then return end
    SetPedPreloadVariationData(ped, HAIR, d, t)
    local timeout = GetGameTimer() + 1500
    while not HasPedPreloadVariationDataFinished(ped) and GetGameTimer() < timeout do Wait(0) end
    SetPedComponentVariation(ped, HAIR, d, t, Hair.Palette({}))   -- the same palette players' hair uses
    ;(SetPedHairTint or SetPedHairColor)(ped, CS.HairColor[1], CS.HairColor[2])
    ReleasePedPreloadVariationData(ped)
    drawable, texture = d, t
end

local function buildList()
    list = {}
    if not ped then return end
    for d = 0, GetNumberOfPedDrawableVariations(ped, HAIR) - 1 do
        list[#list + 1] = { d = d, n = math.max(1, GetNumberOfPedTextureVariations(ped, HAIR, d)), bald = IsBaldDrawable(model, d) or nil,
                            three = HairProps.Has(model, d) or nil }
    end
end

local function spawnPed(m)
    deletePed()
    local hash = m == 'm' and Config.Models.male.model or Config.Models.female.model
    if not pcall(lib.requestModel, hash, 8000) then return false end
    local s = stage()
    -- local only: nobody else streams it, and your own character is never touched
    ped = CreatePed(4, hash, s.x, s.y, s.z, CS.Heading, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then ped = nil return false end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityLodDist(ped, 1000)
    SetPedDefaultComponentVariation(ped)
    SetPedHeadBlendData(ped, CS.Face[1], CS.Face[2], 0, CS.Face[3], CS.Face[4], 0, 0.5, 0.5, 0.0, false)
    for i = 0, 12 do SetPedHeadOverlay(ped, i, 255, 0.0) end
    ClearAllPedProps(ped)
    -- bare shoulders so nothing but the head and hair is in frame
    for comp, v in pairs(m == 'm' and CS.Clothes.male or CS.Clothes.female) do SetPedComponentVariation(ped, comp, v[1], v[2], 0) end
    TaskStandStill(ped, -1)
    model = m
    buildList()
    -- let the ped settle so the head bone is where it'll stay
    Wait(250)
    centre = GetPedBoneCoords(ped, HEAD_BONE, 0.0, 0.0, 0.0)
    return true
end

-- camera -------------------------------------------------------------------------------------------

local function target()
    return vector3(centre.x, centre.y, centre.z + CS.HeadOffset + orbit.lift)
end

local function camDistance()
    -- the hair's bounding sphere fits inside the 80% guide square
    return (CS.Radius / math.tan(math.rad(CS.Fov) * 0.5)) * 1.4 * orbit.zoom
end

local function updateCam()
    if not cam then return end
    local c = target()
    local d = camDistance()
    local yaw, el = math.rad(orbit.yaw), math.rad(orbit.elev)
    SetCamCoord(cam, c.x - math.sin(yaw) * math.cos(el) * d, c.y + math.cos(yaw) * math.cos(el) * d, c.z + math.sin(el) * d)
    PointCamAtCoord(cam, c.x, c.y, c.z)
end

-- chroma box + lights, every frame -----------------------------------------------------------------

local function quad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, r, g, b)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, r, g, b, 255)
    DrawPoly(x3, y3, z3, x4, y4, z4, x1, y1, z1, r, g, b, 255)
    DrawPoly(x3, y3, z3, x2, y2, z2, x1, y1, z1, r, g, b, 255)
    DrawPoly(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, 255)
end

local function drawBox()
    local s = target()
    local h = math.max(3.0, camDistance() + 1.5)
    local col = CHROMA[chroma]
    local r, g, b = col[1], col[2], col[3]
    local x1, x2, y1, y2, z1, z2 = s.x - h, s.x + h, s.y - h, s.y + h, s.z - h, s.z + h
    quad(x1, y1, z1, x2, y1, z1, x2, y1, z2, x1, y1, z2, r, g, b)
    quad(x2, y2, z1, x1, y2, z1, x1, y2, z2, x2, y2, z2, r, g, b)
    quad(x1, y2, z1, x1, y1, z1, x1, y1, z2, x1, y2, z2, r, g, b)
    quad(x2, y1, z1, x2, y2, z1, x2, y2, z2, x2, y1, z2, r, g, b)
    quad(x1, y1, z1, x2, y1, z1, x2, y2, z1, x1, y2, z1, r, g, b)
    quad(x1, y2, z2, x2, y2, z2, x2, y1, z2, x1, y1, z2, r, g, b)
    for _, l in ipairs(CS.Lights) do
        DrawLightWithRange(s.x + l.offset.x, s.y + l.offset.y, s.z + l.offset.z, 255, 255, 255, l.range, l.intensity)
    end
end

local function loop()
    while active do
        HideHudAndRadarThisFrame()
        OverrideLodscaleThisFrame(1.0)
        DisableAllControlActions(0)
        drawBox()
        Wait(0)
    end
end

-- enter / leave ---------------------------------------------------------------------------------

local function enter(data)
    TriggerServerEvent('nz-wig:s:studioBucket', true)
    DoScreenFadeOut(250)
    Wait(300)

    local me = PlayerPedId()
    FreezeEntityPosition(me, true)
    SetEntityVisible(me, false, false)
    SetEntityInvincible(me, true)

    local s = stage()
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    if not spawnPed(model) then
        Studio.Leave()
        return CB.Notify(L('studio_model_fail'), 'error')
    end
    applyHair(drawable < #list and drawable or 0, 0)

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y + 2.0, s.z, 0.0, 0.0, 0.0, CS.Fov, false, 0)
    updateCam()
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    active = true
    CreateThread(loop)

    data.resource = RESOURCE
    data.screenshot = hasScreenshot()
    NUI.Open('studio', data)
    sendState(true)
    DoScreenFadeIn(300)
end

function Studio.Leave()
    local was = active
    active = false
    batch, waiting = nil, nil
    if NUI.app == 'studio' then NUI.CloseApp() end
    deletePed()
    if cam then
        SetCamActive(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
    ClearFocus()
    local me = PlayerPedId()
    SetEntityVisible(me, true, false)
    SetEntityInvincible(me, false)
    FreezeEntityPosition(me, false)
    TriggerServerEvent('nz-wig:s:studioBucket', false)
    if was and IsScreenFadedOut() then DoScreenFadeIn(300) end
end

local function open()
    if active then return end
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    local data = lib.callback.await('nz-wig:studioOpen', false)
    if not data then return CB.Notify(L('studio_no_access'), 'error') end
    data.hair = Config.HairProps.Enabled and lib.callback.await('nz-wig:hairkitStatus', false) or nil
    CreateThread(function() enter(data) end)
end

if CS.Enabled and CS.Command then
    RegisterCommand(CS.Command, open, false)
end
exports('OpenWigStudio', open)

-- capture ----------------------------------------------------------------------------------------

local function shoot(name)
    if not hasScreenshot() then
        CB.Notify(L('studio_no_screenshot'), 'error')
        return false
    end
    NUI.Send('studio:hide')
    Wait(0) Wait(0) Wait(0)

    local done = false
    waiting = name
    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(data)
            NUI.Send('studio:process', { image = data, name = name, chroma = chroma, size = CS.Size, padding = CS.Padding })
            done = true
        end)
    end)
    if not ok then waiting = nil end
    local timeout = GetGameTimer() + 10000
    while ok and not done and GetGameTimer() < timeout do Wait(50) end
    NUI.Send('studio:show')
    if not done then waiting = nil end
    return done
end

-- wait for the keyer + server round trip, so a batch never floods anything
local function awaitSaved(name)
    local timeout = GetGameTimer() + 20000
    while waiting == name and active and GetGameTimer() < timeout do Wait(50) end
end

local function captureCurrent()
    local name = fileName(model, drawable, texture)
    if shoot(name) then awaitSaved(name) end
end

local function runBatch(withTextures, skip)
    local jobs = {}
    for _, x in ipairs(list) do
        if not x.bald then
            for t = 0, withTextures and (x.n - 1) or 0 do
                if not skip[('%s/%d_%d'):format(model, x.d, t)] then jobs[#jobs + 1] = { x.d, t } end
            end
        end
    end
    if #jobs == 0 then return CB.Notify(L('studio_nothing'), 'info') end

    local startD, startT = drawable, texture
    batch = { i = 0, n = #jobs }
    for i, j in ipairs(jobs) do
        if not active or not batch then break end
        batch.i = i
        applyHair(j[1], j[2])
        sendState(false)
        Wait(CS.TextureWait)
        captureCurrent()
        if i % 25 == 0 then collectgarbage('step', 200) end
    end
    local finished = batch ~= nil
    batch = nil
    if not active then return end
    applyHair(startD, startT)
    sendState(false)
    CB.Notify(finished and L('studio_done', #jobs) or L('studio_cancelled'), finished and 'success' or 'warning', 8000)
end

-- NUI ------------------------------------------------------------------------------------------------

local busy = false
local function on(name, fn)
    RegisterNUICallback(name, function(d, cb)
        cb(1)
        if not active then return end
        CreateThread(function() fn(type(d) == 'table' and d or {}) end)
    end)
end

on('st:close', function() if not batch then Studio.Leave() end end)

on('st:model', function(d)
    if batch or busy then return end
    local m = d.m == 'm' and 'm' or 'f'
    if m == model then return end
    busy = true
    if spawnPed(m) then applyHair(0, 0) end
    updateCam()
    busy = false
    sendState(true)
end)

on('st:pick', function(d)
    if batch or busy or not ped then return end
    local dd, tt = math.floor(tonumber(d.d) or 0), math.floor(tonumber(d.t) or 0)
    local x = list[dd + 1]
    if not x then return end
    busy = true
    applyHair(dd, math.max(0, math.min(x.n - 1, tt)))
    busy = false
    sendState(false)
end)

on('st:orbit', function(d)
    orbit.yaw = (orbit.yaw - (tonumber(d.dx) or 0) * 0.4) % 360.0
    orbit.elev = math.max(-60.0, math.min(75.0, orbit.elev + (tonumber(d.dy) or 0) * 0.3))
    if d.yaw then orbit.yaw = (tonumber(d.yaw) or 0) % 360.0 end
    if d.elev then orbit.elev = math.max(-60.0, math.min(75.0, tonumber(d.elev) or 0)) end
    updateCam()
    sendState(false)
end)

on('st:zoom', function(d)
    if d.set then orbit.zoom = tonumber(d.set) or 1.0 else orbit.zoom = orbit.zoom + (tonumber(d.delta) or 0) end
    orbit.zoom = math.max(0.4, math.min(3.0, orbit.zoom))
    updateCam()
    sendState(false)
end)

on('st:lift', function(d)
    orbit.lift = math.max(-0.5, math.min(0.25, tonumber(d.set) or 0))
    updateCam()
    sendState(false)
end)

on('st:chroma', function(d)
    if CHROMA[d.color] then chroma = d.color end
    sendState(false)
end)

on('st:capture', function()
    if batch or waiting then return end
    captureCurrent()
end)

on('st:batch', function(d)
    if batch or waiting then return end
    local skip = {}
    if d.missing ~= false then
        local have = lib.callback.await('nz-wig:studioShots', false) or {}
        for _, k in ipairs(have) do skip[k] = true end
    end
    runBatch(d.textures == true, skip)
end)

RegisterNUICallback('st:cancel', function(_, cb)
    cb(1)
    if batch then batch = nil end
end)

on('st:name', function(d)
    if type(d.key) ~= 'string' then return end
    TriggerServerEvent('nz-wig:s:studioNames', { [d.key] = tostring(d.name or '') })
end)

-- 3D wigs: scan / build the hairstyle props (server runs hairkit)
on('st:hairkit', function(d)
    if d.mode == 'scan' or d.mode == 'build' or d.mode == 'rebuild' then TriggerServerEvent('nz-wig:s:hairkit', d.mode) end
end)

RegisterNetEvent('nz-wig:c:hairkit', function(d)
    NUI.Send('studio:hairkit', d)
    if d.kind == 'done' and active then
        SetTimeout(6000, function() if active then buildList() sendState(true) end end) -- the new props are streamed by now
    end
end)

-- the keyer finished: hand the small PNG to the server
RegisterNUICallback('st:processed', function(d, cb)
    cb(1)
    if type(d) ~= 'table' or type(d.png) ~= 'string' or type(d.name) ~= 'string' then
        waiting = nil
        return
    end
    TriggerLatentServerEvent('nz-wig:s:studioSave', CS.LatentRate, d.name, d.png)
end)

RegisterNUICallback('st:failed', function(d, cb)
    cb(1)
    waiting = nil
    CB.Notify(L('studio_key_failed', tostring(d and d.reason)), 'error')
end)

RegisterNetEvent('nz-wig:c:studioSaved', function(name, ok, key, where)
    if waiting == name then waiting = nil end
    if not batch then
        CB.Notify(ok and L('studio_saved', name, where or '') or L('studio_save_failed', name), ok and 'success' or 'error')
    end
    NUI.Send('studio:saved', { name = name, ok = ok, key = key })
end)

RegisterNetEvent('nz-wig:c:styleNames', function(names)
    if type(names) == 'table' then StyleNames = names end
end)

-- leave cleanly if something else takes the screen (death, another script opening its UI...)
CreateThread(function()
    while true do
        Wait(1000)
        if active and not busy and (IsEntityDead(PlayerPedId()) or not DoesEntityExist(ped or 0)) then Studio.Leave() end
    end
end)

function Studio.Cleanup()
    if active then Studio.Leave() end
end
