--[[
    Sneaker Studio, client side.

    Every player: keeps the shoe list in step with the server's studio shoes (server/studio.lua),
    so shoes switched on in /sneakerstudio can be crafted, worn and sold straight away.

    Admins: /sneakerstudio. Built the same way as the wig snatch and backpack studios:
      * the shoe (its prop, or the pair in its open box) floats in a lit chroma box under the map;
        your own character never changes
      * an orbit camera frames it between the two panels (drag / scroll / angle presets)
      * screenshot-basic grabs the frame, the NUI keys it into a small PNG (web/keyer.js)
      * the server writes shots/nzs_<shoe>_<letter>(_box).png and copies it into ox_inventory
    Shoes without a 3D prop yet are shown on a model's feet so they can still be named and priced;
    3D props builds their props on the server (server/props.lua).
]]

SneakerStudio = {}

local S = Config.Studio
local applied = {}      -- ids this client added to Config.ShoeModels
local lastScan          -- { base, drawables = { [key] = textures } }

-- ------------------------------------------------------------------ shoe list (every player)

local function apply(payload)
    payload = payload or {}
    local models = payload.models or {}
    for id in pairs(applied) do Config.ShoeModels[id] = nil end
    applied = {}
    Shared.ApplyBuiltinOverrides(payload.builtin)
    for id, m in pairs(models) do
        if not Config.ShoeModels[id] then
            Config.ShoeModels[id] = m
            applied[id] = true
        end
    end
    BuildShoes()
    if Crafting and Crafting.Invalidate then Crafting.Invalidate() end
end

RegisterNetEvent('nayzeee-sneakers:client:studioShoes', apply)

-- tells the NUI where icons can be, so it never waits on a resource this server doesn't run
local function iconSources()
    local function on(r) return GetResourceState(r) == 'started' end
    SendNUIMessage({ action = 'init', propsResource = S.PropsResource,
        sources = { props = on(S.PropsResource), ox = on('ox_inventory'), qb = on('qb-inventory') } })
end
AddEventHandler('onClientResourceStart', function(res)
    if res == S.PropsResource or res == 'ox_inventory' or res == 'qb-inventory' then iconSources() end
end)

CreateThread(function()
    iconSources()
    apply(lib.callback.await('nayzeee-sneakers:studio:shoes', false))
end)

-- ------------------------------------------------------------------ drawable scan

local function hiddenPed(model)
    if not LoadModel(model) then return nil end
    local c = GetEntityCoords(PlayerPedId())
    local ped = CreatePed(4, model, c.x, c.y, c.z - 60.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    local timeout = GetGameTimer() + 2000
    while not DoesEntityExist(ped) and GetGameTimer() < timeout do Wait(0) end
    if not DoesEntityExist(ped) then return nil end
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    return ped
end

--- Every feet drawable on the server, from a hidden ped of each gender:
--- { base = bool, drawables = { ['m:mypack:007'] = textures, ... } }, or nil on FiveM builds without
--- the clothing collection natives
function SneakerStudio.Scan(includeBase)
    if not GetPedCollectionsCount or not GetNumberOfPedCollectionDrawableVariations then return nil end
    local out = { base = includeBase == true, drawables = {} }
    for _, g in ipairs({ { 'm', `mp_m_freemode_01` }, { 'f', `mp_f_freemode_01` } }) do
        local ped = hiddenPed(g[2])
        if ped then
            for i = 0, GetPedCollectionsCount(ped) - 1 do
                local name = GetPedCollectionName(ped, i) or ''
                if i > 0 or includeBase then
                    local pack = i == 0 and '' or Shoes.PackKey(name)
                    for d = 0, GetNumberOfPedCollectionDrawableVariations(ped, 6, name) - 1 do
                        local t = GetNumberOfPedCollectionTextureVariations(ped, 6, name, d)
                        if t and t > 0 then out.drawables[('%s:%s:%03d'):format(g[1], pack, d)] = t end
                    end
                end
            end
            DeleteEntity(ped)
        end
    end
    return out
end

local function scanAndReport()
    lastScan = SneakerStudio.Scan(S.BaseGame)
    if not lastScan then
        UI.Notify(Config.Text.studioOld, 'error')
        return lib.callback.await('nayzeee-sneakers:studio:open', false)
    end
    local res = lib.callback.await('nayzeee-sneakers:studio:report', false, lastScan)
    return res and res.data
end

-- ------------------------------------------------------------------ photo studio

local CHROMA = { green = { 0, 177, 64 }, magenta = { 255, 0, 255 }, blue = { 0, 71, 187 } }
local L_FOOT, R_FOOT = 14201, 52301

local active = false
local data                              -- what the server sent: shoes, fresh, gone, shots, kit ...
local entries = {}                      -- [key] = shoe entry or a new drawable from the scan
local cur = { key = nil, letter = 'a' }
local subject = 'loose'                 -- 'loose' | 'box'
local mode = 'none'                     -- what's in the box right now: 'loose' | 'box' | 'feet' | 'none'
local objs, ped, cam = {}, nil, nil
local centre, radius = vector3(0.0, 0.0, 0.0), 0.3
local orbit = { yaw = S.Orbit.yaw, elev = S.Orbit.elev, zoom = S.Orbit.zoom, lift = S.Orbit.lift }
local chroma = CHROMA[S.Chroma] and S.Chroma or 'green'
local batch = nil                       -- { i, n } while a batch runs
local waiting = nil                     -- file name we're waiting on the keyer + server for
local busy = false

local function stage() return S.Coords end
local function hasScreenshot() return GetResourceState('screenshot-basic') == 'started' end
local function letterIndex(l) return (l or 'a'):byte() - 97 end

local function indexEntries()
    entries = {}
    for _, e in ipairs(data and data.shoes or {}) do entries[e.key] = e end
    for _, f in ipairs(data and data.fresh or {}) do
        local colours = {}
        for i = 1, math.min(26, f.textures or 1) do colours[i] = { letter = string.char(96 + i), name = ('Texture %d'):format(i) } end
        entries[f.key] = { key = f.key, fresh = true, label = ('%s %03d'):format(f.collection ~= '' and f.collection or 'Base game', f.index),
            gender = f.gender, colours = colours, link = { collection = f.collection, index = f.index } }
    end
end

local function entry() return cur.key and entries[cur.key] or nil end

--- The prop for a colourway, or nil when the shoe has none (yet) on this client
local function propOf(e, letter)
    if not e or not e.props or not e.id then return nil end
    local h = GetHashKey(('nzs_%s_%s'):format(e.id, letter))
    return IsModelInCdimage(h) and h or nil
end

local function shotName(e, letter, sub)
    return ('nzs_%s_%s%s'):format(e.id, letter, sub == 'box' and '_box' or '')
end

local function sendState()
    SendNUIMessage({ action = 'studio:state', state = {
        key = cur.key, letter = cur.letter, subject = subject, mode = mode, chroma = chroma, orbit = orbit,
        batch = batch, screenshot = hasScreenshot(),
    } })
end

local function sendData()
    SendNUIMessage({ action = 'studio:data', data = data })
end

-- the subject ------------------------------------------------------------------------------------

local function clearSubject()
    for _, o in ipairs(objs) do if DoesEntityExist(o) then DeleteEntity(o) end end
    objs = {}
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    ped = nil
    mode = 'none'
end

local function spawnObj(model, pos)
    if not LoadModel(model) then return nil end
    local o = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not o or o == 0 then return nil end
    SetEntityHeading(o, 0.0)
    FreezeEntityPosition(o, true)
    SetEntityCollision(o, false, false)
    SetEntityLodDist(o, 1000)
    objs[#objs + 1] = o
    return o
end

local function middle(ent, model)
    local mn, mx = GetModelDimensions(model)
    return GetOffsetFromEntityInWorldCoords(ent, (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.5), #(mx - mn) * 0.5
end

local function showLoose(model)
    local o = spawnObj(model, stage())
    if not o then return false end
    centre, radius = middle(o, model)
    mode = 'loose'
    return true
end

local function showBox(e, model)
    local t = Config.BoxTypes[e.box or 'shoe'] or Config.BoxTypes.shoe
    local s = stage()
    local base = spawnObj(t.base, s)
    local lid = base and spawnObj(t.lid, s)
    local shoe = lid and spawnObj(model, s)
    if not shoe then return false end
    AttachEntityToEntity(lid, base, 0, t.hinge.x, t.hinge.y, t.hinge.z, Config.Box.openAngle, 0.0, 0.0, false, false, false, false, 2, true)
    AttachEntityToEntity(shoe, base, 0, 0.0, 0.0, Config.Box.floor, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    local mn, mx = GetModelDimensions(t.base)
    -- the open lid stands up behind the box: aim a little higher and fit a bigger sphere
    centre = GetOffsetFromEntityInWorldCoords(base, (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5 - 0.03, t.hinge.z * 0.8)
    radius = #(mx - mn) * 0.62
    mode = 'box'
    return true
end

local function showFeet(e, letter)
    local model = e.gender == 'female' and `mp_f_freemode_01` or `mp_m_freemode_01`
    if not LoadModel(model) then return false end
    local s = stage()
    ped = CreatePed(4, model, s.x, s.y, s.z + 0.95, 180.0, false, false)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 then ped = nil return false end
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, false, false)
    SetPedDefaultComponentVariation(ped)
    TaskStandStill(ped, -1)
    local d = e.link and Shoes.Drawable(ped, { collection = e.link.collection or '', index = tonumber(e.link.index) })
    if d then SetPedComponentVariation(ped, 6, d, letterIndex(letter), 0) end
    Wait(250)
    local l, r = GetPedBoneCoords(ped, L_FOOT, 0.0, 0.0, 0.0), GetPedBoneCoords(ped, R_FOOT, 0.0, 0.0, 0.0)
    centre = (l + r) * 0.5 + vector3(0.0, 0.0, 0.02)
    radius = 0.34
    mode = 'feet'
    return true
end

--- Puts the current shoe / colourway / subject in the box
local function showCurrent()
    clearSubject()
    local e = entry()
    if not e then return end
    local model = propOf(e, cur.letter)
    if model and subject == 'box' then
        if not showBox(e, model) then clearSubject() end
    elseif model then
        if not showLoose(model) then clearSubject() end
    elseif e.link then
        showFeet(e, cur.letter)
    end
end

-- camera -------------------------------------------------------------------------------------------

local function target() return vector3(centre.x, centre.y, centre.z + orbit.lift) end

local function camDistance()
    return (radius / math.tan(math.rad(S.Fov) * 0.5)) * 1.25 * orbit.zoom
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
    for _, l in ipairs(S.Lights) do
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

-- enter / leave ------------------------------------------------------------------------------------

local function firstKey()
    for _, e in ipairs(data.shoes or {}) do if not e.removed then return e.key end end
    local f = (data.fresh or {})[1]
    return f and f.key or nil
end

local function enter()
    TriggerServerEvent('nayzeee-sneakers:server:studioBucket', true)
    DoScreenFadeOut(250)
    Wait(300)

    local me = PlayerPedId()
    FreezeEntityPosition(me, true)
    SetEntityVisible(me, false, false)
    SetEntityInvincible(me, true)

    local s = stage()
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    if not cur.key or not entries[cur.key] then cur.key, cur.letter = firstKey(), 'a' end
    showCurrent()

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', s.x, s.y + 2.0, s.z, 0.0, 0.0, 0.0, S.Fov, false, 0)
    updateCam()
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)

    active = true
    CreateThread(loop)

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'studio:open', data = data, size = S.Size, screenshot = hasScreenshot(),
        saveToInventory = data.saveToInventory, version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) })
    sendState()
    DoScreenFadeIn(300)
end

function SneakerStudio.Leave()
    local was = active
    active = false
    batch, waiting = nil, nil
    SendNUIMessage({ action = 'studio:close' })
    SetNuiFocus(false, false)
    clearSubject()
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
    TriggerServerEvent('nayzeee-sneakers:server:studioBucket', false)
    if was and IsScreenFadedOut() then DoScreenFadeIn(300) end
    Busy = false
end

RegisterNetEvent('nayzeee-sneakers:client:studioOpen', function()
    if active or Busy then return end
    Busy = true
    local d = scanAndReport()
    if not d then
        Busy = false
        return UI.Notify(Config.Text.studioNoAccess, 'error')
    end
    data = d
    indexEntries()
    CreateThread(enter)
end)
exports('OpenSneakerStudio', function() ExecuteCommand(S.Command) end)

-- capture ------------------------------------------------------------------------------------------

local function shoot(name)
    if not hasScreenshot() then
        UI.Notify(Config.Text.studioNoScreenshot, 'error')
        return false
    end
    SendNUIMessage({ action = 'studio:hide' })
    Wait(0) Wait(0) Wait(0)

    local done = false
    waiting = name
    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(img)
            SendNUIMessage({ action = 'studio:process', job = { image = img, name = name, chroma = chroma, size = S.Size, padding = S.Padding } })
            done = true
        end)
    end)
    if not ok then waiting = nil end
    local timeout = GetGameTimer() + 10000
    while ok and not done and GetGameTimer() < timeout do Wait(50) end
    SendNUIMessage({ action = 'studio:show' })
    if not done then waiting = nil end
    return done
end

-- wait for the keyer + server round trip, so a batch never floods anything
local function awaitSaved(name)
    local timeout = GetGameTimer() + 20000
    while waiting == name and active and GetGameTimer() < timeout do Wait(50) end
end

local function captureCurrent()
    local e = entry()
    if not e or (mode ~= 'loose' and mode ~= 'box') then
        UI.Notify(Config.Text.studioNoProp, 'error')
        return
    end
    local name = shotName(e, cur.letter, mode)
    if shoot(name) then awaitSaved(name) end
end

local function runBatch(opts)
    local have = {}
    if opts.missing ~= false then for _, n in ipairs(data.shots or {}) do have[n] = true end end
    local subs = {}
    if opts.loose ~= false then subs[#subs + 1] = 'loose' end
    if opts.box then subs[#subs + 1] = 'box' end
    local jobs = {}
    for _, e in ipairs(data.shoes or {}) do
        if not e.removed and e.props and (opts.gender == 'all' or e.gender == opts.gender) then
            for i, c in ipairs(e.colours or {}) do
                if i == 1 or opts.colours then
                    for _, sub in ipairs(subs) do
                        if not have[shotName(e, c.letter, sub)] and propOf(e, c.letter) then
                            jobs[#jobs + 1] = { key = e.key, letter = c.letter, sub = sub }
                        end
                    end
                end
            end
        end
    end
    if #jobs == 0 then return UI.Notify(Config.Text.studioNothing, 'inform') end

    local start = { key = cur.key, letter = cur.letter, subject = subject }
    batch = { i = 0, n = #jobs }
    for i, j in ipairs(jobs) do
        if not active or not batch then break end
        batch.i = i
        cur.key, cur.letter, subject = j.key, j.letter, j.sub
        showCurrent()
        updateCam()
        sendState()
        Wait(S.TextureWait)
        captureCurrent()
        if i % 25 == 0 then collectgarbage('step', 200) end
    end
    local finished = batch ~= nil
    batch = nil
    if not active then return end
    cur.key, cur.letter, subject = start.key, start.letter, start.subject
    showCurrent()
    updateCam()
    sendState()
    UI.Notify(finished and Config.Text.studioPhotoDone:format(#jobs) or Config.Text.studioCancelled, finished and 'success' or 'warning')
end

-- NUI ------------------------------------------------------------------------------------------------

local function on(name, fn)
    RegisterNUICallback(name, function(d, cb)
        cb(1)
        if not active then return end
        CreateThread(function() fn(type(d) == 'table' and d or {}) end)
    end)
end

on('st:close', function() if not batch then SneakerStudio.Leave() end end)

on('st:pick', function(d)
    if batch or busy then return end
    local e = entries[tostring(d.key or '')]
    if not e then return end
    local letter = type(d.letter) == 'string' and d.letter:match('^%l$') or nil
    if d.key == cur.key and (letter or 'a') == cur.letter and not d.force then return end
    busy = true
    cur.key, cur.letter = e.key, letter or 'a'
    showCurrent()
    updateCam()
    busy = false
    sendState()
end)

-- a plain download being linked: show the drawable that was picked on the model
on('st:preview', function(d)
    if batch or busy or type(d.link) ~= 'table' then return end
    local e = entries[tostring(d.key or '')]
    if not e or e.key ~= cur.key then return end
    busy = true
    clearSubject()
    showFeet({ gender = e.gender, link = { collection = tostring(d.link.collection or ''), index = tonumber(d.link.index) } }, cur.letter)
    updateCam()
    busy = false
    sendState()
end)

on('st:subject', function(d)
    if batch or busy then return end
    subject = d.subject == 'box' and 'box' or 'loose'
    busy = true
    showCurrent()
    updateCam()
    busy = false
    sendState()
end)

on('st:orbit', function(d)
    orbit.yaw = (orbit.yaw - (tonumber(d.dx) or 0) * 0.4) % 360.0
    orbit.elev = math.max(-60.0, math.min(85.0, orbit.elev + (tonumber(d.dy) or 0) * 0.3))
    if d.yaw then orbit.yaw = (tonumber(d.yaw) or 0) % 360.0 end
    if d.elev then orbit.elev = math.max(-60.0, math.min(85.0, tonumber(d.elev) or 0)) end
    updateCam()
    sendState()
end)

on('st:zoom', function(d)
    if d.set then orbit.zoom = tonumber(d.set) or 1.0 else orbit.zoom = orbit.zoom + (tonumber(d.delta) or 0) end
    orbit.zoom = math.max(0.4, math.min(3.0, orbit.zoom))
    updateCam()
    sendState()
end)

on('st:lift', function(d)
    orbit.lift = math.max(-0.3, math.min(0.3, tonumber(d.set) or 0))
    updateCam()
    sendState()
end)

on('st:chroma', function(d)
    if CHROMA[d.color] then chroma = d.color end
    sendState()
end)

on('st:capture', function()
    if batch or waiting then return end
    captureCurrent()
end)

on('st:batch', function(d)
    if batch or waiting then return end
    runBatch({ gender = d.gender == 'male' and 'male' or d.gender == 'female' and 'female' or 'all', colours = d.colours == true,
        loose = d.loose ~= false, box = d.box == true, missing = d.missing ~= false })
end)

RegisterNUICallback('st:cancel', function(_, cb)
    cb(1)
    if batch then batch = nil end
end)

-- shoe settings: same server callbacks as before, the answer is the fresh studio data
local function refresh(d)
    if not d then return end
    data = d
    indexEntries()
    sendData()
    if cur.key and not entries[cur.key] then cur.key, cur.letter = firstKey(), 'a' showCurrent() updateCam() end
    sendState()
end

on('st:save', function(d)
    if type(d.key) ~= 'string' then return end
    local res = lib.callback.await('nayzeee-sneakers:studio:save', false, d.key, type(d.fields) == 'table' and d.fields or {})
    if res then UI.Notify(Config.Text.studioSaved, 'success') end
    refresh(res)
end)

on('st:add', function(d)
    if type(d.key) ~= 'string' then return end
    refresh(lib.callback.await('nayzeee-sneakers:studio:add', false, d.key))
    if entries[d.key] then cur.key = d.key showCurrent() updateCam() sendState() end
end)

on('st:forget', function(d)
    if type(d.key) ~= 'string' then return end
    refresh(lib.callback.await('nayzeee-sneakers:studio:forget', false, d.key))
end)

on('st:rescan', function()
    if batch then return end
    refresh(scanAndReport())
end)

-- 3D props: scan / build the shoe props (the server runs sneakerkit)
on('st:kit', function(d)
    if d.mode == 'scan' or d.mode == 'build' or d.mode == 'rebuild' then TriggerServerEvent('nayzeee-sneakers:server:kit', d.mode) end
end)

RegisterNetEvent('nayzeee-sneakers:client:kit', function(d)
    SendNUIMessage({ action = 'studio:kit', kit = d })
    if d.kind == 'done' and active then
        -- the new props are streamed by now: refresh the list so they show up
        SetTimeout(7000, function()
            if not active then return end
            refresh(lib.callback.await('nayzeee-sneakers:studio:open', false))
            if not batch then showCurrent() updateCam() sendState() end
        end)
    end
end)

-- the keyer finished: hand the small PNG to the server
RegisterNUICallback('st:processed', function(d, cb)
    cb(1)
    if type(d) ~= 'table' or type(d.png) ~= 'string' or type(d.name) ~= 'string' then
        waiting = nil
        return
    end
    TriggerLatentServerEvent('nayzeee-sneakers:server:studioPhoto', S.LatentRate, d.name, d.png)
end)

RegisterNUICallback('st:failed', function(d, cb)
    cb(1)
    waiting = nil
    UI.Notify(Config.Text.studioKeyFailed:format(tostring(d and d.reason)), 'error')
end)

RegisterNetEvent('nayzeee-sneakers:client:studioPhoto', function(name, ok, where)
    if waiting == name then waiting = nil end
    if ok and data then
        data.shots = data.shots or {}
        local known = false
        for _, n in ipairs(data.shots) do if n == name then known = true break end end
        if not known then data.shots[#data.shots + 1] = name end
    end
    if not batch then
        UI.Notify(ok and Config.Text.studioPhotoSaved:format(name, where or '') or Config.Text.studioPhotoFailed:format(name), ok and 'success' or 'error')
    end
    SendNUIMessage({ action = 'studio:saved', name = name, ok = ok })
end)

-- leave cleanly if something else takes the screen (death, another script ...)
CreateThread(function()
    while true do
        Wait(1000)
        if active and not busy and IsEntityDead(PlayerPedId()) then SneakerStudio.Leave() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and active then SneakerStudio.Leave() end
end)

-- ------------------------------------------------------------------ admins hear about changes

if S.Enabled and S.AlertAdmins then
    Bridge.OnPlayerLoaded(function()
        SetTimeout(20000, function()
            if not lib.callback.await('nayzeee-sneakers:studio:isAdmin', false) then return end
            lastScan = SneakerStudio.Scan(S.BaseGame)
            if not lastScan then return end
            local res = lib.callback.await('nayzeee-sneakers:studio:report', false, lastScan)
            if res and (res.fresh > 0 or res.gone > 0) then
                UI.Notify(Config.Text.studioAlert:format(res.fresh, res.gone, S.Command), 'inform')
            end
        end)
    end)
end
