-----------------------------------------------------------------
-- Icon studio  (/chainstudio > Icon)
--
-- The backpack icon studio, for chains:
--   * the chain floats in a flat chroma box under the map, lit by
--     studio lights
--   * an orbit camera frames it (fitted to the model's size)
--   * screenshot-basic grabs the frame, the NUI keys the backdrop
--     out, trims, centres it on a transparent square, the server
--     writes the PNG (icons/ + ox_inventory/web/images)
--
-- Every texture is its own picture, named after its prop, which is
-- what the item's metadata.image points at.
-----------------------------------------------------------------

Icons = {}

local cfg = Config.Icons
local active = false
local prop, cam = nil, nil
local key, letter = nil, nil
local centre, radius = vector3(0, 0, 0), 0.2
local orbit = { yaw = 200.0, elev = 55.0, zoom = 1.0 }
local chroma = cfg.Chroma or 'green'
local batch = nil
local waiting = nil

local COLORS = {
    green   = { 0, 177, 64 },
    magenta = { 255, 0, 255 },
    blue    = { 0, 71, 187 },
}

local function stage() return cfg.Coords or vector3(0.0, 0.0, -150.0) end

function Icons.active() return active end

function Icons.state()
    return {
        active = active, chroma = chroma, orbit = orbit, batch = batch and { i = batch.i, n = #batch.list } or nil,
        hasScreenshot = GetResourceState('screenshot-basic') == 'started', size = cfg.Size or 512,
    }
end

local function sendState() NUI.send('icon:state', Icons.state()) end

local function placeProp()
    if not prop then return end
    local s = stage()
    SetEntityCoordsNoOffset(prop, s.x - centre.x, s.y - centre.y, s.z - centre.z, false, false, false)
    SetEntityRotation(prop, 0.0, 0.0, 0.0, 2, false)
end

local function spawnProp(k, l)
    Util.delete(prop)
    prop = nil
    local entity, hash = Util.spawnChain(k, l, stage())
    if not entity then return false end
    FreezeEntityPosition(entity, true)
    SetEntityLodDist(entity, 1000)
    prop, key, letter = entity, k, l
    local c, a, b = Util.modelCentre(hash)
    centre = c
    radius = math.max(0.05, #(b - a) * 0.5)
    placeProp()
    return true
end

local function camDistance()
    local fov = cfg.Fov or 30.0
    return (radius / math.tan(math.rad(fov) * 0.5)) * 1.4 * orbit.zoom
end

local function updateCam()
    if not cam then return end
    local s = stage()
    local d = camDistance()
    local yaw, el = math.rad(orbit.yaw), math.rad(orbit.elev)
    SetCamCoord(cam, s.x - math.sin(yaw) * math.cos(el) * d, s.y + math.cos(yaw) * math.cos(el) * d, s.z + math.sin(el) * d)
    PointCamAtCoord(cam, s.x, s.y, s.z)
end

local function quad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, r, g, b)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, r, g, b, 255)
    DrawPoly(x3, y3, z3, x4, y4, z4, x1, y1, z1, r, g, b, 255)
    DrawPoly(x3, y3, z3, x2, y2, z2, x1, y1, z1, r, g, b, 255)
    DrawPoly(x1, y1, z1, x4, y4, z4, x3, y3, z3, r, g, b, 255)
end

local function drawBox()
    local s = stage()
    local h = math.max(2.0, camDistance() + 1.0)
    local col = COLORS[chroma] or COLORS.green
    local r, g, b = col[1], col[2], col[3]
    local x1, x2, y1, y2, z1, z2 = s.x - h, s.x + h, s.y - h, s.y + h, s.z - h, s.z + h
    quad(x1, y1, z1, x2, y1, z1, x2, y1, z2, x1, y1, z2, r, g, b)
    quad(x2, y2, z1, x1, y2, z1, x1, y2, z2, x2, y2, z2, r, g, b)
    quad(x1, y2, z1, x1, y1, z1, x1, y1, z2, x1, y2, z2, r, g, b)
    quad(x2, y1, z1, x2, y2, z1, x2, y2, z2, x2, y1, z2, r, g, b)
    quad(x1, y1, z1, x2, y1, z1, x2, y2, z1, x1, y2, z1, r, g, b)
    quad(x1, y2, z2, x2, y2, z2, x2, y1, z2, x1, y1, z2, r, g, b)
    for _, l in ipairs(cfg.Lights or {}) do
        DrawLightWithRange(s.x + l.offset.x, s.y + l.offset.y, s.z + l.offset.z, 255, 255, 255, l.range or 5.0, l.intensity or 2.0)
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

function Icons.start()
    if active then return true end
    local k, l = Studio.current()
    if not k or not spawnProp(k, l) then return false end
    local s = stage()
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    Studio.pauseCam(true)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y + 2.0, s.z, 0.0, 0.0, 0.0, cfg.Fov or 30.0, false, 0)
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
    if cam then SetCamActive(cam, false); DestroyCam(cam, false); cam = nil end
    ClearFocus()
    Studio.pauseCam(false)
end

function Icons.refreshProp()
    if not active then return end
    local k, l = Studio.current()
    spawnProp(k, l)
    updateCam()
end

-----------------------------------------------------------------
-- capture
-----------------------------------------------------------------

local function shoot(name)
    if GetResourceState('screenshot-basic') ~= 'started' then
        CB.Notify('screenshot-basic is not running.', 'error')
        return false
    end
    NUI.send('icon:hide')
    Wait(0); Wait(0); Wait(0)
    local done = false
    exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(data)
        waiting = name
        NUI.send('icon:process', { image = data, name = name, chroma = chroma, size = cfg.Size or 512, padding = cfg.Padding or 0.08 })
        done = true
    end)
    local timeout = GetGameTimer() + 10000
    while not done and GetGameTimer() < timeout do Wait(50) end
    NUI.send('icon:show')
    return done
end

local function awaitSaved(name)
    local timeout = GetGameTimer() + 15000
    while waiting == name and GetGameTimer() < timeout do Wait(50) end
end

local function captureOne(k, l)
    if not spawnProp(k, l) then return false end
    updateCam()
    Wait(cfg.TextureWait or 700)
    local name = Chains.model(k, l)
    if not shoot(name) then return false end
    awaitSaved(name)
    return true
end

local function runBatch()
    local list = {}
    for _, k in ipairs(Chains.keys()) do
        for _, v in ipairs(Chains.def(k).variants) do list[#list + 1] = { k, v.letter } end
    end
    batch = { list = list, i = 0 }
    sendState()
    local startKey, startLetter = Studio.current()
    for i, entry in ipairs(list) do
        if not active or not batch then break end
        batch.i = i
        sendState()
        captureOne(entry[1], entry[2])
    end
    local finished = batch ~= nil
    batch = nil
    if active then spawnProp(startKey, startLetter); updateCam() end
    sendState()
    if finished then CB.Notify(('Captured %d icons.'):format(#list), 'success') end
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

on('icon:toggle', function(d) if d.on then Icons.start() else Icons.stop() end end)

on('icon:orbit', function(d)
    orbit.yaw = (orbit.yaw - (tonumber(d.dx) or 0) * 0.4) % 360.0
    orbit.elev = math.max(-80.0, math.min(89.0, orbit.elev + (tonumber(d.dy) or 0) * 0.3))
    if d.yaw then orbit.yaw = tonumber(d.yaw) % 360.0 end
    if d.elev then orbit.elev = math.max(-80.0, math.min(89.0, tonumber(d.elev))) end
    updateCam()
end)

on('icon:zoom', function(d)
    if d.set then orbit.zoom = tonumber(d.set) or 1.0 else orbit.zoom = orbit.zoom + (tonumber(d.delta) or 0) end
    orbit.zoom = math.max(0.4, math.min(3.0, orbit.zoom))
    updateCam()
end)

on('icon:chroma', function(d) if COLORS[d.color] then chroma = d.color end end)

on('icon:capture', function()
    if not active or not key then return end
    local name = Chains.model(key, letter)
    if shoot(name) then awaitSaved(name) end
end)

on('icon:batch', function()
    if not active or batch then return end
    runBatch()
end)

RegisterNUICallback('icon:cancel', function(_, cb) cb('ok'); batch = nil end)

RegisterNUICallback('icon:processed', function(data, cb)
    cb('ok')
    if type(data.png) ~= 'string' or type(data.name) ~= 'string' then waiting = nil return end
    TriggerLatentServerEvent('nzc:icon:save', 4000000, data.name, data.png)
end)

RegisterNUICallback('icon:failed', function(data, cb)
    cb('ok')
    waiting = nil
    CB.Notify('Icon processing failed: ' .. tostring(data and data.reason), 'error')
end)

RegisterNetEvent('nzc:icon:saved', function(name, ok, where)
    if waiting == name then waiting = nil end
    if not batch then
        CB.Notify(ok and ('Saved %s.png%s'):format(name, where or '') or ('Could not save %s'):format(name), ok and 'success' or 'error')
    end
    NUI.send('icon:saved', { name = name, ok = ok })
end)
