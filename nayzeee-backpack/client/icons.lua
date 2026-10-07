-----------------------------------------------------------------
-- Icon studio  (/bagtune > Icon)
--
-- Built the way uz_AutoShot does clothing, but for bag props:
--   * the bag floats inside a flat chroma box, lit by studio lights,
--     at a spot under the map where nothing else renders
--   * an orbit camera frames it (auto-fitted to the model's size)
--   * screenshot-basic grabs the frame, the browser keys out the
--     chroma colour, trims to the bag, centres it on a transparent
--     square, and the server writes the PNG
--
-- Capture one, or batch every bag (and every variant) in one go.
-- No yarn, no node_modules: the keying happens in the NUI canvas.
-----------------------------------------------------------------

Icons = {}

local cfg = Config.IconCapture or {}
local active = false
local prop, cam = nil, nil
local key, variant = nil, nil
local centre, radius = vector3(0, 0, 0), 0.5
local orbit = { yaw = 200.0, elev = 12.0, zoom = 1.0 }
local chroma = cfg.chroma or 'green'
local batch = nil       -- { list, i, done } while a batch runs
local waiting = nil     -- filename we're waiting on the keyer for

local COLORS = {
    green   = { 0, 177, 64 },
    magenta = { 255, 0, 255 },
    blue    = { 0, 71, 187 },
}

local function stage() return cfg.coords or vector3(0.0, 0.0, -150.0) end

function Icons.active() return active end

function Icons.state()
    return {
        active = active, chroma = chroma, orbit = orbit, batch = batch and { i = batch.i, n = #batch.list } or nil,
        hasScreenshot = GetResourceState('screenshot-basic') == 'started',
        size = cfg.size or 512,
    }
end

local function sendState()
    SendNUIMessage({ action = 'iconState', data = Icons.state() })
end

-----------------------------------------------------------------
-- prop + camera
-----------------------------------------------------------------

local function placeProp()
    if not prop then return end
    local s = stage()
    -- mesh centre on the staging point, not the clothing pivot
    SetEntityCoordsNoOffset(prop, s.x - centre.x, s.y - centre.y, s.z - centre.z, false, false, false)
    SetEntityRotation(prop, 0.0, 0.0, 0.0, 2, false)
end

local function spawnProp(k, v)
    Util.delete(prop)
    prop = nil
    local entity, hash = Util.spawnBag(k, v, stage())
    if not entity then return false end
    FreezeEntityPosition(entity, true)
    SetEntityLodDist(entity, 1000)
    prop, key, variant = entity, k, v

    local c, mn, mx = Util.modelCentre(hash)
    centre = c
    radius = math.max(0.15, #(mx - mn) * 0.5)
    placeProp()
    return true
end

local function camDistance()
    local fov = cfg.fov or 30.0
    -- the whole bounding sphere fits inside the 80% guide square
    return (radius / math.tan(math.rad(fov) * 0.5)) * 1.4 * orbit.zoom
end

local function updateCam()
    if not cam then return end
    local s = stage()
    local d = camDistance()
    local yaw, el = math.rad(orbit.yaw), math.rad(orbit.elev)
    SetCamCoord(cam,
        s.x - math.sin(yaw) * math.cos(el) * d,
        s.y + math.cos(yaw) * math.cos(el) * d,
        s.z + math.sin(el) * d)
    PointCamAtCoord(cam, s.x, s.y, s.z)
end

-----------------------------------------------------------------
-- chroma box + lights, every frame while active
-----------------------------------------------------------------

local function quad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, r, g, b)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, r, g, b, 255)
    DrawPoly(x3, y3, z3, x4, y4, z4, x1, y1, z1, r, g, b, 255)
    DrawPoly(x3, y3, z3, x2, y2, z2, x1, y1, z1, r, g, b, 255)
    DrawPoly(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, 255)
end

local function drawBox()
    local s = stage()
    local h = math.max(3.0, camDistance() + 1.5)
    local col = COLORS[chroma] or COLORS.green
    local r, g, b = col[1], col[2], col[3]
    local x1, x2, y1, y2, z1, z2 = s.x - h, s.x + h, s.y - h, s.y + h, s.z - h, s.z + h

    quad(x1, y1, z1, x2, y1, z1, x2, y1, z2, x1, y1, z2, r, g, b)
    quad(x2, y2, z1, x1, y2, z1, x1, y2, z2, x2, y2, z2, r, g, b)
    quad(x1, y2, z1, x1, y1, z1, x1, y1, z2, x1, y2, z2, r, g, b)
    quad(x2, y1, z1, x2, y2, z1, x2, y2, z2, x2, y1, z2, r, g, b)
    quad(x1, y1, z1, x2, y1, z1, x2, y2, z1, x1, y2, z1, r, g, b)
    quad(x1, y2, z2, x2, y2, z2, x2, y1, z2, x1, y1, z2, r, g, b)

    for _, l in ipairs(cfg.lights or {}) do
        DrawLightWithRange(s.x + l.offset.x, s.y + l.offset.y, s.z + l.offset.z,
            255, 255, 255, l.range or 5.0, l.intensity or 2.0)
    end
end

local function loop()
    while active do
        HideHudAndRadarThisFrame()
        OverrideLodscaleThisFrame(1.0)
        drawBox()
        Wait(0)
    end
end

-----------------------------------------------------------------
-- enter / exit
-----------------------------------------------------------------

function Icons.start()
    if active then return true end
    local k, v = Studio.current()
    if not k then return false end
    if not spawnProp(k, v) then return false end

    local s = stage()
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    Studio.pauseCam(true)

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y + 2.0, s.z, 0.0, 0.0, 0.0, cfg.fov or 30.0, false, 0)
    updateCam()
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    active = true
    CreateThread(loop)
    return true
end

function Icons.stop()
    if not active then return end
    active = false
    batch, waiting = nil, nil
    Util.delete(prop)
    prop = nil
    if cam then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
        cam = nil
    end
    ClearFocus()
    Studio.pauseCam(false)
end

--- Studio switched bag or variant while the icon view is up.
function Icons.refreshProp()
    if not active then return end
    local k, v = Studio.current()
    spawnProp(k, v)
    updateCam()
end

-----------------------------------------------------------------
-- capture
-----------------------------------------------------------------

local function filenameFor(k, v)
    local list = Bags.variants(k)
    if #list == 0 or not v or v == list[1].id then return k end
    return ('%s_%s'):format(k, v)
end

local function shoot(name)
    if GetResourceState('screenshot-basic') ~= 'started' then
        Config.Notify('screenshot-basic is not running.', 'error')
        return false
    end

    SendNUIMessage({ action = 'iconHide' })
    Wait(0); Wait(0); Wait(0)

    local done = false
    exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(data)
        waiting = name
        SendNUIMessage({
            action = 'iconProcess',
            data = {
                image = data, name = name, chroma = chroma,
                size = cfg.size or 512, padding = cfg.padding or 0.08,
            }
        })
        done = true
    end)

    local timeout = GetGameTimer() + 10000
    while not done and GetGameTimer() < timeout do Wait(50) end
    SendNUIMessage({ action = 'iconShow' })
    return done
end

--- Wait for the keyer + server round trip, so a batch never floods anything.
local function awaitSaved(name)
    local timeout = GetGameTimer() + 15000
    while waiting == name and GetGameTimer() < timeout do Wait(50) end
end

local function captureOne(k, v)
    if not spawnProp(k, v) then return false end
    updateCam()
    Wait(cfg.textureWait or 700)
    local name = filenameFor(k, v)
    if not shoot(name) then return false end
    awaitSaved(name)
    return true
end

local function runBatch(withVariants)
    local list = {}
    for _, k in ipairs(Bags.keys()) do
        local vars = Bags.variants(k)
        if withVariants and #vars > 1 then
            for _, v in ipairs(vars) do list[#list + 1] = { k, v.id } end
        else
            list[#list + 1] = { k, vars[1] and vars[1].id or nil }
        end
    end

    batch = { list = list, i = 0 }
    sendState()
    local startKey, startVar = Studio.current()

    for i, entry in ipairs(list) do
        if not active or not batch then break end
        batch.i = i
        sendState()
        captureOne(entry[1], entry[2])
    end

    local finished = batch ~= nil
    batch = nil
    if active then
        spawnProp(startKey, startVar)
        updateCam()
    end
    sendState()
    if finished then Config.Notify(('Captured %d icons.'):format(#list), 'success') end
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

local function on(name, fn)
    RegisterNUICallback(name, function(data, cb)
        cb('ok')
        if not Studio.isOpen() then return end
        Studio.run(function() fn(data or {}); sendState() end)
    end)
end

on('icon:toggle', function(d)
    if d.on then Icons.start() else Icons.stop() end
end)

on('icon:orbit', function(d)
    orbit.yaw = (orbit.yaw - (tonumber(d.dx) or 0) * 0.4) % 360.0
    orbit.elev = math.max(-70.0, math.min(80.0, orbit.elev + (tonumber(d.dy) or 0) * 0.3))
    if d.yaw then orbit.yaw = tonumber(d.yaw) % 360.0 end
    if d.elev then orbit.elev = math.max(-70.0, math.min(80.0, tonumber(d.elev))) end
    updateCam()
end)

on('icon:zoom', function(d)
    if d.set then orbit.zoom = tonumber(d.set) or 1.0
    else orbit.zoom = orbit.zoom + (tonumber(d.delta) or 0) end
    orbit.zoom = math.max(0.4, math.min(3.0, orbit.zoom))
    updateCam()
end)

on('icon:chroma', function(d)
    if COLORS[d.color] then chroma = d.color end
end)

on('icon:capture', function()
    if not active or not key then return end
    local name = filenameFor(key, variant)
    if shoot(name) then awaitSaved(name) end
end)

on('icon:batch', function(d)
    if not active or batch then return end
    runBatch(d.variants ~= false and cfg.variantIcons ~= false)
end)

RegisterNUICallback('icon:cancel', function(_, cb)
    cb('ok')
    batch = nil
end)

-- the keyer finished: hand the PNG to the server
RegisterNUICallback('icon:processed', function(data, cb)
    cb('ok')
    if type(data.png) ~= 'string' or type(data.name) ~= 'string' then
        waiting = nil
        return
    end
    TriggerLatentServerEvent('nayzeee-backpack:icon:save', 4000000, data.name, data.png)
end)

RegisterNUICallback('icon:failed', function(data, cb)
    cb('ok')
    waiting = nil
    Config.Notify('Icon processing failed: ' .. tostring(data and data.reason), 'error')
end)

RegisterNetEvent('nayzeee-backpack:icon:saved', function(name, ok, where)
    if waiting == name then waiting = nil end
    if not batch then
        Config.Notify(ok and ('Saved %s.png%s'):format(name, where or '') or ('Could not save %s'):format(name),
            ok and 'success' or 'error')
    end
    SendNUIMessage({ action = 'iconSaved', data = { name = name, ok = ok } })
end)
