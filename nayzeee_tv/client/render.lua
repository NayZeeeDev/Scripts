--[[ Screen geometry, DUI pool, drawing, 3D audio ]]

Render = { slots = {}, active = {} }  -- active: tvId → slot

local RES = NZ.res
local DUI_URL = ('https://cfx-nui-%s/html/tv/index.html'):format(RES)
local txdSeq = 0

-- ═══════════════ geometry ═══════════════
local AXES = {
    ['-y'] = { n = vector3(0, -1, 0), r = vector3(1, 0, 0) },
    ['+y'] = { n = vector3(0, 1, 0),  r = vector3(-1, 0, 0) },
    ['-x'] = { n = vector3(-1, 0, 0), r = vector3(0, -1, 0) },
    ['+x'] = { n = vector3(1, 0, 0),  r = vector3(0, 1, 0) },
}

--- Fit the picture to a model's front face when no calibration exists.
function Render.autoScreen(model, def)
    local hash = GetHashKey(model)
    local mn, mx = GetModelDimensions(hash)
    local sx, sy, sz = mx.x - mn.x, mx.y - mn.y, mx.z - mn.z
    local aspect = (def and def.aspect) or (16 / 9)
    local style = def and def.style or 'flat'
    local cat = def and def.cat or 'flat'

    -- which horizontal axis is the width?
    local face, widthSpan, depthMin, depthMax, cx = '-y', sx, mn.y, mx.y, (mn.x + mx.x) / 2
    if sx < sy * 0.5 then face, widthSpan, depthMin, depthMax, cx = '-x', sy, mn.x, mx.x, (mn.y + mx.y) / 2 end

    local w, h, z, depth
    if cat == 'cinema' or cat == 'facility' then
        -- flat panels: the face IS the screen
        w, h = widthSpan * 0.985, sz * 0.985
        z = (mn.z + mx.z) / 2
        depth = depthMin
    elseif style == 'crt' then
        w = widthSpan * 0.74
        h = w / aspect
        if h > sz * 0.72 then h = sz * 0.70 w = h * aspect end
        z = (mn.z + mx.z) / 2 + sz * 0.05
        depth = depthMin
    elseif style == 'laptop' then
        w = widthSpan * 0.86
        h = w / aspect
        z = mn.z + sz * 0.58
        depth = (depthMin + depthMax) / 2 + (depthMax - depthMin) * 0.22
    elseif style == 'arcade' then
        w = widthSpan * 0.72
        h = w / aspect
        if h > sz * 0.38 then h = sz * 0.36 w = h * aspect end
        z = mn.z + sz * 0.66
        depth = depthMin + (depthMax - depthMin) * 0.25
    else
        w = widthSpan * 0.93
        h = w / aspect
        if h > sz * 0.94 then h = sz * 0.9 w = h * aspect end
        local bezel = (widthSpan - w) / 2
        z = mx.z - bezel - h / 2
        local mid = (depthMin + depthMax) / 2
        depth = math.max(depthMin, mid - 0.045)
    end

    local s = { w = w, h = h, face = face, z = z }
    if face == '-y' then s.x, s.y = cx, depth else s.x, s.y = depth, cx end
    return s
end

function Render.screenDef(tv)
    if tv.kind == 'wall' then return nil end
    return NZ.calibPreview[tv.model] or NZ.calibration[tv.model] or (NZ.prop(tv) and NZ.prop(tv).screen) or Render.autoScreen(tv.model, NZ.prop(tv))
end

--- World-space corners, normal and centre for a screen (cached until moved / recalibrated).
function Render.geometry(tv)
    if tv._screen then return tv._screen end
    local off = Config.Render.ScreenOffset
    local tl, tr, bl, br, n, center, w, h

    if tv.kind == 'wall' then
        w, h = tv.wall.w, tv.wall.h
        local hd = math.rad(tv.heading or 0.0)
        n = vector3(-math.sin(hd), math.cos(hd), 0.0)
        local f = n * -1.0
        local r = vector3(f.y, -f.x, 0.0) -- forward × up
        local up = vector3(0, 0, 1)
        center = vector3(tv.coords.x, tv.coords.y, tv.coords.z) + n * off
        tl = center - r * (w / 2) + up * (h / 2)
        tr = center + r * (w / 2) + up * (h / 2)
        bl = center - r * (w / 2) - up * (h / 2)
        br = center + r * (w / 2) - up * (h / 2)
    else
        local ent = tv._entity
        if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
        local s = Render.screenDef(tv)
        local ax = AXES[s.face] or AXES['-y']
        w, h = s.w, s.h
        local c = vector3(s.x, s.y, s.z) + ax.n * off
        local function W(v) return GetOffsetFromEntityInWorldCoords(ent, v.x, v.y, v.z) end
        local up = vector3(0, 0, 1)
        tl = W(c - ax.r * (w / 2) + up * (h / 2))
        tr = W(c + ax.r * (w / 2) + up * (h / 2))
        bl = W(c - ax.r * (w / 2) - up * (h / 2))
        br = W(c + ax.r * (w / 2) - up * (h / 2))
        center = (tl + br) / 2
        local e1, e2 = tr - tl, bl - tl
        local cx = vector3(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
        n = cx / math.max(#cx, 0.0001)
    end

    tv._screen = { tl = tl, tr = tr, bl = bl, br = br, n = n, center = center, w = w, h = h }
    return tv._screen
end

-- ═══════════════ DUI pool ═══════════════
local function sendSlot(slot, msg)
    if slot.ready then
        SendDuiMessage(slot.dui, json.encode(msg))
    else
        slot.queue[#slot.queue + 1] = msg
    end
end
Render.send = sendSlot

local function createSlot(i, hd)
    local res = hd and Config.Render.CinemaResolution or Config.Render.Resolution
    txdSeq = txdSeq + 1
    local txdName = ('nztv_%d_%d'):format(i, txdSeq)
    local dui = CreateDui(DUI_URL .. '?slot=' .. i, res[1], res[2])
    local handle = GetDuiHandle(dui)
    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', handle)
    return { i = i, dui = dui, txd = txdName, w = res[1], h = res[2], hd = hd, ready = false, queue = {}, tv = nil, audio = {} }
end

local function destroySlot(slot)
    if slot.dui then DestroyDui(slot.dui) end
    slot.dui = nil
end

local function tvPayload(tv)
    return {
        id = tv.id, label = tv.label, style = tv.style, aspect = tv.aspect, settings = tv.settings,
        volume = tv.volume, muted = tv.muted, power = tv.power, media = tv.media or false, queue = tv.queue,
        history = tv.history, ui = tv.ui, loop = tv.loop, channel = tv.channel, group = tv.group,
    }
end

local function bindSlot(slot, tv)
    slot.tv = tv.id
    slot.audio = {}
    Render.active[tv.id] = slot
    sendSlot(slot, {
        type = 'init', tv = tvPayload(tv), now = NZ.serverNow(), me = NZ.me,
        brand = Config.Brand, featured = Config.Featured, channels = Config.Channels, library = Config.Library,
        res = RES, sync = Config.Sync,
        w = slot.w, h = slot.h,
        booting = tv._onAt ~= nil and (GetGameTimer() - tv._onAt) < 1500,
    })
end

local function releaseSlot(slot)
    if slot.tv then Render.active[slot.tv] = nil end
    slot.tv = nil
    sendSlot(slot, { type = 'unload' })
end

--- Pick which screens get a browser: powered, in range, nearest first.
local function assign()
    local want = {}
    for _, tv in pairs(NZ.tvs) do
        local fading = tv._offAt and (GetGameTimer() - tv._offAt) < 900
        if (tv.power or fading) and tv._entity and tv._dist and tv._dist <= (tv.range or 20.0) + Config.Render.RenderPadding then
            want[#want + 1] = tv
        end
    end
    table.sort(want, function(a, b) return a._dist < b._dist end)

    local keep = {}
    for i = 1, math.min(#want, Config.Render.MaxScreens) do keep[want[i].id] = want[i] end

    -- release what is no longer wanted
    for _, slot in pairs(Render.slots) do
        if slot.tv and not keep[slot.tv] then releaseSlot(slot) end
    end

    -- bind new screens
    for id, tv in pairs(keep) do
        if not Render.active[id] then
            local hd = tv.hd == true
            local free
            for _, slot in pairs(Render.slots) do
                if not slot.tv and slot.hd == hd then free = slot break end
            end
            if not free then
                local count = 0
                for _ in pairs(Render.slots) do count = count + 1 end
                if count < Config.Render.MaxScreens then
                    local idx = count + 1
                    while Render.slots[idx] do idx = idx + 1 end
                    free = createSlot(idx, hd)
                    Render.slots[idx] = free
                else
                    -- recycle an idle slot of the other resolution
                    for k, slot in pairs(Render.slots) do
                        if not slot.tv then
                            destroySlot(slot)
                            free = createSlot(k, hd)
                            Render.slots[k] = free
                            break
                        end
                    end
                end
            end
            if free then bindSlot(free, tv) end
        end
    end
end

NZ.on('scan', assign)
NZ.on('boot', function()
    for _, slot in pairs(Render.slots) do if slot.tv then releaseSlot(slot) end end
end)

NZ.on('patch', function(tv, patch)
    if patch.power == true then tv._onAt, tv._offAt = GetGameTimer(), nil
    elseif patch.power == false then tv._offAt = GetGameTimer() SetTimeout(950, assign) end
    local slot = Render.active[tv.id]
    if slot then
        local p = {}
        for k, v in pairs(patch) do p[k] = v end
        sendSlot(slot, { type = 'patch', patch = p, now = NZ.serverNow() })
    end
    if patch.power ~= nil then assign() end
end)

NZ.on('removed', function(tv)
    local slot = Render.active[tv.id]
    if slot then releaseSlot(slot) end
end)

NZ.on('despawned', function(tv)
    local slot = Render.active[tv.id]
    if slot then releaseSlot(slot) end
end)

-- TV OS remote keys / typed text relayed from the server
RegisterNetEvent('nztv:key', function(id, key, by, seq)
    local slot = Render.active[id]
    if slot then sendSlot(slot, { type = 'key', key = key, mine = by == NZ.me, seq = seq }) end
    NZ.emit('key', id, key, by)
end)

RegisterNetEvent('nztv:typed', function(id, text, by)
    local slot = Render.active[id]
    if slot then sendSlot(slot, { type = 'typed', text = text, mine = by == NZ.me }) end
end)

-- clock pulses for drift correction
CreateThread(function()
    while true do
        Wait(Config.Sync.Interval)
        local now = NZ.serverNow()
        for _, slot in pairs(Render.slots) do
            if slot.tv then sendSlot(slot, { type = 'clock', now = now }) end
        end
    end
end)

-- ═══════════════ drawing ═══════════════
local function camPosition() return GetFinalRenderedCamCoord() end

local function drawQuad(txd, s, flip)
    local tl, tr, bl, br = s.tl, s.tr, s.bl, s.br
    -- both windings so the picture shows regardless of the engine's cull order
    DrawSpritePoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z, 255, 255, 255, 255, txd, 'screen', 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0)
    DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z, 255, 255, 255, 255, txd, 'screen', 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0)
    DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, bl.x, bl.y, bl.z, 255, 255, 255, 255, txd, 'screen', 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
    DrawSpritePoly(tl.x, tl.y, tl.z, tr.x, tr.y, tr.z, br.x, br.y, br.z, 255, 255, 255, 255, txd, 'screen', 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
end

Render.debugOutline = nil -- tvId drawn with a calibration outline

CreateThread(function()
    local gc = Config.Render.GlowColor
    while true do
        local any = false
        for _, slot in pairs(Render.slots) do
            if slot.tv and slot.ready then
                local tv = NZ.tvs[slot.tv]
                local s = tv and (tv.power or (tv._offAt and GetGameTimer() - tv._offAt < 800)) and Render.geometry(tv)
                if s then
                    any = true
                    local cam = camPosition()
                    local front = ((cam.x - s.center.x) * s.n.x + (cam.y - s.center.y) * s.n.y + (cam.z - s.center.z) * s.n.z) > 0
                    if front or Config.Render.DoubleSided then drawQuad(slot.txd, s) end
                    if Config.Render.Glow and front and slot.glow then
                        local p = s.center + s.n * math.min(1.2, 0.35 + s.w * 0.25)
                        DrawLightWithRange(p.x, p.y, p.z, gc[1], gc[2], gc[3], math.min(14.0, 1.6 + s.w * 1.4), Config.Render.GlowIntensity * slot.glow)
                    end
                end
            end
        end
        if Render.debugOutline then
            local tv = NZ.tvs[Render.debugOutline]
            local s = tv and Render.geometry(tv)
            if s then
                any = true
                DrawLine(s.tl.x, s.tl.y, s.tl.z, s.tr.x, s.tr.y, s.tr.z, 8, 175, 162, 255)
                DrawLine(s.tr.x, s.tr.y, s.tr.z, s.br.x, s.br.y, s.br.z, 8, 175, 162, 255)
                DrawLine(s.br.x, s.br.y, s.br.z, s.bl.x, s.bl.y, s.bl.z, 8, 175, 162, 255)
                DrawLine(s.bl.x, s.bl.y, s.bl.z, s.tl.x, s.tl.y, s.tl.z, 8, 175, 162, 255)
                local e = s.center + s.n * 0.25
                DrawLine(s.center.x, s.center.y, s.center.z, e.x, e.y, e.z, 229, 72, 77, 255)
            end
        end
        Wait(any and 0 or 300)
    end
end)

-- DUI readiness
CreateThread(function()
    while true do
        local waiting = false
        for _, slot in pairs(Render.slots) do
            if slot.dui and not slot.ready then
                waiting = true
                if IsDuiAvailable(slot.dui) then
                    slot.ready = true
                    Wait(150)
                    for _, msg in ipairs(slot.queue) do SendDuiMessage(slot.dui, json.encode(msg)) end
                    slot.queue = {}
                end
            end
        end
        Wait(waiting and 100 or 500)
    end
end)

-- ═══════════════ 3D audio ═══════════════
local occl = {} -- tvId → { t, wall, room }

local function occlusion(tv, s, cam)
    local o = occl[tv.id]
    local now = GetGameTimer()
    if o and now - o.t < 450 then return o end
    o = o or {}
    o.t = now
    local target = s.center + s.n * 0.35
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, target.x, target.y, target.z, 1, PlayerPedId(), 4)
    local _, hit = GetShapeTestResult(ray)
    o.wall = hit == 1

    local ped = PlayerPedId()
    local myInt = GetInteriorFromEntity(ped)
    local tvInt = (tv._entity and tv._entity ~= 0) and GetInteriorFromEntity(tv._entity) or GetInteriorAtCoords(s.center.x, s.center.y, s.center.z)
    if myInt ~= tvInt then
        o.room = true
    elseif myInt ~= 0 and tv._entity and tv._entity ~= 0 then
        o.room = GetRoomKeyFromEntity(ped) ~= GetRoomKeyFromEntity(tv._entity)
    else
        o.room = false
    end
    occl[tv.id] = o
    return o
end

CreateThread(function()
    local A = Config.Audio
    while true do
        local busy = false
        local cam = camPosition()
        local rot = GetFinalRenderedCamRot(2)
        local rz = math.rad(rot.z)
        local right = vector3(math.cos(rz), math.sin(rz), 0.0)
        local groups = {}

        for _, slot in pairs(Render.slots) do
            local tv = slot.tv and NZ.tvs[slot.tv]
            local s = tv and Render.geometry(tv)
            if s and slot.ready then
                busy = true
                local d = #(cam - s.center)
                local R = tv.range or 20.0
                local inner = R * A.InnerRadius
                local att = 0.0
                if d <= inner then att = 1.0
                elseif d < R then att = (1.0 - (d - inner) / (R - inner)) ^ A.Rolloff end

                local lowpass = 22000
                local o = occlusion(tv, s, cam)
                if o.room then att = att * A.RoomVolume lowpass = A.RoomLowpass
                elseif o.wall then att = att * A.WallVolume lowpass = A.WallLowpass end

                local vol = att * (tv.volume or 0.5)
                if tv.muted or not tv.power then vol = 0.0 end

                local pan = 0.0
                if A.Stereo and d > 0.8 then
                    local dir = (s.center - cam) / d
                    pan = Utils.clamp((dir.x * right.x + dir.y * right.y) * 0.85, -0.85, 0.85)
                end

                slot._vol, slot._lp, slot._pan = vol, lowpass, pan
                slot.glow = (tv.media and not (tv.media.paused)) and Utils.clamp(1.0 - d / (R + 10.0), 0.15, 1.0) or 0.0

                if A.GroupSingleSource and tv.group then
                    local g = groups[tv.group]
                    if not g or vol > g._vol then groups[tv.group] = slot end
                end
            end
        end

        for _, slot in pairs(Render.slots) do
            if slot.tv and slot.ready and slot._vol then
                local tv = NZ.tvs[slot.tv]
                local vol = slot._vol
                if A.GroupSingleSource and tv and tv.group and groups[tv.group] ~= slot then vol = 0.0 end
                local a = slot.audio
                if not a.v or math.abs(a.v - vol) > 0.008 or a.lp ~= slot._lp or math.abs((a.pan or 0) - slot._pan) > 0.04 then
                    a.v, a.lp, a.pan = vol, slot._lp, slot._pan
                    SendDuiMessage(slot.dui, json.encode({ type = 'audio', volume = vol, lowpass = slot._lp, pan = slot._pan }))
                end
            end
        end
        Wait(busy and A.UpdateRate or 500)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, slot in pairs(Render.slots) do destroySlot(slot) end
end)

-- DUI → client reports (duration, title, playlists, OS actions)
RegisterNUICallback('tv:report', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    local tv = data.tv and NZ.tvs[data.tv]
    if not tv then return end
    if data.kind == 'ui' then
        NZ.rpc('uiState', tv.id, data.data)
    elseif data.kind == 'action' then
        NZ.emit('osAction', tv, data.data)
    else
        NZ.rpc('report', tv.id, data.key, data.kind, data.data)
    end
end)
