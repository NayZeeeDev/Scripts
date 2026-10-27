--[[
    Record shop (client)

    Walk up to the counter and the camera moves over it. The records stand above the counter in a
    carousel: the featured sleeve in the middle gently turning with its record slid half out, the
    previous / next sleeves dimmer either side. Browsing slides the row with an eased transition and
    the album, artist and price float above the featured sleeve.

    [A]/[D] or wheel  browse      [ENTER]  buy
    drag              spin        [L]      listen (a short preview, in your own ears)
    [ESC]             leave

    The 3D row needs the sleeve props (nayzeee_sleeve_a/_b/_c, and nayzeee_vinyl for the record) in
    stream/. Without them, or with Config.RecordShop.display = '2d', the same UI shows the records as
    cover cards instead. Everything below only runs while the shop is open, except the shopkeepers
    and prompts, which sleep while nobody is near a shop.

    Three sleeve models exist so each slot can show its own cover (a DUI per slot replaces
    nayzeee_cover_a/_b/_c). A sleeve sliding out of view is reused for the one sliding in: it fades
    out in the first half of the slide and fades back in, with the new cover, in the second half.
]]
local cfg = Config.RecordShop
if not cfg or cfg.enabled == false then return end

local RES = GetCurrentResourceName()
local LOCS = cfg.locations or {}
local P = cfg.preview or {}
local UP = vector3(0.0, 0.0, 1.0)

local SLEEVE = 0.315                 -- sleeve size (contract): origin = centre of its bottom edge, cover facing +Y
local HALF = SLEEVE / 2
local DISC_OUT = 0.158               -- how far the record slides out of the featured sleeve (the record is 0.303 across)
local DISC_MID = 0.0011              -- half the record's thickness: it sits in the middle of the sleeve
local LEAN = cfg.lean or 6.0         -- sleeves lean back a little, like on a display stand
local SIDE_ANGLE = cfg.sideAngle or 32.0
local TRANSITION = cfg.transitionTime or 420
local SWAY = cfg.swayAngle or 14.0
local SPIN = cfg.spinSpeed or 14.0
local TURN = cfg.turn == 'spin' and 'spin' or 'sway'
local INTERACT = cfg.interactDistance or 2.5
local PREVIEW_ID = 'nzshop_preview'  -- not 'preview': the player UI uses that id for its card editor
local MODELS = { a = 'nayzeee_sleeve_a', b = 'nayzeee_sleeve_b', c = 'nayzeee_sleeve_c' }
local DISC_MODEL = 'nayzeee_vinyl'
local TXD = 'nayzeee_console_texture'     -- the record console upgrade's dictionary (sleeves + record)

-- carousel slots: sideways / backwards from the featured spot (metres) and alpha
local SIDE_ALPHA = cfg.sideSleeves == false and 0 or (cfg.sideAlpha or 170)
local SLOT = {
    [-2] = { side = -1.05, depth = 0.75, alpha = 0 },
    [-1] = { side = -0.58, depth = 0.40, alpha = SIDE_ALPHA },
    [0]  = { side = -0.076, depth = 0.0, alpha = 255 },   -- left by half the record that sticks out: the pair is centred
    [1]  = { side = 0.58,  depth = 0.40, alpha = SIDE_ALPHA },
    [2]  = { side = 1.05,  depth = 0.75, alpha = 0 },
}

---------------------------------------------------------------- text
local L = NZ.L

-- the shop screen's strings in the server's language, with English under them
local function uiText()
    local t = {}
    for _, pack in ipairs({ Locales.en or {}, Locales[Config.Locale] or {} }) do
        if type(pack.shop_ui) == 'table' then
            for k, v in pairs(pack.shop_ui) do t[k] = v end
        end
    end
    return t
end

---------------------------------------------------------------- state
local open, opening = false, false
local nuiReady = false
local mode3d = false
local view = nil              -- anchor / axes / camera of the current counter
local catalog = {}            -- item -> { cover, album, artist }
local current = nil           -- featured item
local cam = nil
local slots = {}              -- the three sleeves
local disc = { ent = nil, owner = nil, lin = 0.0, alpha = -1 }
local anim = nil              -- { start, rise } while the row slides / rises
local nudge, lastDrag = 0.0, 0
local savedHeading = nil
local labelAt, labelX, labelY = 0, -1, -1
local preview, previewSeq = nil, 0
local coverTxd, coverSerial = nil, 0
local loadedModels = {}

local function sound(name, set)
    if cfg.sounds ~= false then PlaySoundFrontend(-1, name, set, true) end
end

local function ease(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end
local function easeOut(t) return 1 - (1 - t) ^ 3 end
local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

---------------------------------------------------------------- counter geometry
local function buildView(loc)
    local d = loc and loc.display or {}
    local anchor, face
    if loc then
        local h = d.heading or loc.heading or 0.0
        local r = math.rad(h)
        face = vector3(-math.sin(r), math.cos(r), 0.0)       -- the way the shopkeeper faces: towards the shopper
        anchor = d.point or (loc.coords + face * (d.forward or 0.75) + UP * (d.height or 0.05))
    else
        -- /recordshop: the row stands in front of you
        local ped = PlayerPedId()
        local r = math.rad(GetEntityHeading(ped))
        face = vector3(math.sin(r), -math.cos(r), 0.0)
        anchor = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.95, -0.05)
    end
    local centre = anchor + UP * HALF
    local camPos = d.cam or (centre + face * (d.camDistance or 1.05) + UP * (d.camHeight or 0.08))
    local look = centre + UP * (d.lookHeight or 0.04)
    local flat = vector3(look.x - camPos.x, look.y - camPos.y, 0.0)
    local len = #flat
    flat = len < 0.001 and vector3(0.0, 1.0, 0.0) or flat / len
    local heading = GetHeadingFromVector_2d(flat.x, flat.y)
    return {
        anchor = anchor, cam = camPos, look = look,
        fwd = flat,                                   -- away from the camera
        right = vector3(flat.y, -flat.x, 0.0),        -- camera right
        cover = (heading + 180.0) % 360.0,            -- heading that turns a cover to the camera
        fov = d.fov or 40.0,
    }
end

local function slotAt(o)
    o = clamp(o, -2.0, 2.0)
    local lo = math.floor(o)
    local hi = math.min(2, lo + 1)
    local t = o - lo
    local a, b = SLOT[lo], SLOT[hi]
    return a.side + (b.side - a.side) * t, a.depth + (b.depth - a.depth) * t, a.alpha + (b.alpha - a.alpha) * t
end

-- a point in a sleeve's own space (lean, then heading) to world offset
local function rotate(h, x, y, z)
    local l = math.rad(LEAN)
    local y1, z1 = y * math.cos(l) - z * math.sin(l), y * math.sin(l) + z * math.cos(l)
    local r = math.rad(h)
    return x * math.cos(r) - y1 * math.sin(r), x * math.sin(r) + y1 * math.cos(r), z1
end

---------------------------------------------------------------- covers (one DUI per sleeve)
local function urlencode(s)
    return (tostring(s):gsub('[^%w%-%._~]', function(c) return ('%%%02X'):format(c:byte()) end))
end

-- html/dui/sleeve.html shows the cover from its #fragment (JSON: s = { c = url, t = album, a = artist },
-- p = urls to warm up). Changing only the fragment doesn't reload it, so a cached cover swaps instantly.
-- (A DUI only opens http(s)://, nui:// and about: links: FiveM puts https:// in front of anything
-- else, so the page is a file and not a data: link.)
local PAGE = ('nui://%s/html/dui/sleeve.html'):format(RES)

local function coverOf(item) return item and catalog[item] and catalog[item].cover or nil end

-- what a sleeve's page shows (its item) and warms up (s.warm items, plus the item it is about to take)
local function syncDui(s)
    if not s.dui then return end
    local c = s.item and catalog[s.item] or {}
    local warm = {}
    for _, item in ipairs(s.warm or {}) do warm[#warm + 1] = coverOf(item) end
    if s.pending then warm[#warm + 1] = coverOf(s.pending.item) end
    local state = json.encode({ s = { c = c.cover or '', t = c.album or '', a = c.artist or '' }, p = warm })
    if state == s.duiState then s.duiLate = nil return end
    -- the page's browser isn't up yet and would drop it: frame() sends it again once it is
    if not IsDuiAvailable(s.dui) then s.duiLate = true return end
    s.duiState, s.duiLate = state, nil
    SetDuiUrl(s.dui, PAGE .. '#' .. urlencode(state))
end

local function makeDui(s)
    local px = cfg.coverSize or 512
    coverSerial = coverSerial + 1
    if not coverTxd then coverTxd = CreateRuntimeTxd('nzspk_shop_covers') end
    s.dui = CreateDui(PAGE, px, px)
    local t = GetGameTimer()
    while not IsDuiAvailable(s.dui) and GetGameTimer() - t < 2000 do Wait(0) end
    s.tex = ('cover_%s_%d'):format(s.letter, coverSerial)
    CreateRuntimeTextureFromDuiHandle(coverTxd, s.tex, GetDuiHandle(s.dui))
    AddReplaceTexture(TXD, 'nayzeee_cover_' .. s.letter, 'nzspk_shop_covers', s.tex)
    s.duiState = nil
end

---------------------------------------------------------------- props
local function want3d()
    if (cfg.display or 'auto') == '2d' then return false end
    for _, m in pairs(MODELS) do
        if not IsModelInCdimage(joaat(m)) then
            NZ.Debug('record shop: ' .. m .. ' is not in stream/, using the 2D shop')
            return false
        end
    end
    return true
end

local function spawnProp(model)
    local hash = Bridge.LoadModel(model)
    if not hash then return nil end
    loadedModels[hash] = true
    local p = view.anchor - UP * 4.0
    local ent = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
    if not ent or ent == 0 then return nil end
    SetEntityCollision(ent, false, false)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityVisible(ent, false, false)
    return ent
end

local function setAlpha(rec, ent, a)
    a = math.floor(a + 0.5)
    if a == rec.alpha then return end
    if a <= 2 then
        SetEntityVisible(ent, false, false)
    else
        if rec.alpha <= 2 then SetEntityVisible(ent, true, false) end
        if a >= 255 then ResetEntityAlpha(ent) else SetEntityAlpha(ent, a, false) end
    end
    rec.alpha = a
end

local function clear3d()
    for _, s in ipairs(slots) do
        if s.ent and DoesEntityExist(s.ent) then DeleteEntity(s.ent) end
        RemoveReplaceTexture(TXD, 'nayzeee_cover_' .. s.letter)
        if s.dui then DestroyDui(s.dui) end
    end
    slots = {}
    if disc.ent and DoesEntityExist(disc.ent) then DeleteEntity(disc.ent) end
    disc = { ent = nil, owner = nil, lin = 0.0, alpha = -1 }
    for hash in pairs(loadedModels) do SetModelAsNoLongerNeeded(hash) end
    loadedModels = {}
    anim = nil
end

local function load3d()
    for _, letter in ipairs({ 'a', 'b', 'c' }) do
        local ent = spawnProp(MODELS[letter])
        if not ent then clear3d() return false end
        slots[#slots + 1] = { letter = letter, ent = ent, alpha = 0, item = nil, o = 0, from = 0, to = 0,
            mode = 'idle', spin = 0.0, idle = 0.0 }
    end
    if IsModelInCdimage(joaat(DISC_MODEL)) then disc.ent = spawnProp(DISC_MODEL) end
    for _, s in ipairs(slots) do makeDui(s) end
    return true
end

---------------------------------------------------------------- the row
local function featured()
    for _, s in ipairs(slots) do
        if s.item and s.to == 0 and s.mode ~= 'out' then return s end
    end
end

local function handoff(s)
    local p = s.pending
    s.pending = nil
    s.item, s.from, s.to, s.o, s.mode, s.spin = p.item, p.from, p.to, p.from, 'in', 0.0
    syncDui(s)
end

-- finish a running slide at once (when the player browses faster than it plays)
local function settle()
    if not anim then return end
    for _, s in ipairs(slots) do
        if s.pending then handoff(s) end
        if s.mode == 'out' then s.item = nil s.mode = 'idle' end
        s.from, s.o = s.to, s.to
        if s.mode ~= 'idle' then s.mode = 'idle' end
    end
    anim = nil
end

--[[
    target = { [-1] = item, [0] = item, [1] = item } (nil where nothing shows), dir = +1 / -1 for a
    one-step slide, 0 to rebuild the row (opening, filters). warm = { left, right }: the items that
    come into view next, so their covers are cached before they are needed.
]]
local function applyView(target, dir, warm)
    settle()
    local now = GetGameTimer()
    local stays, at = {}, {}
    if dir ~= 0 then
        for _, s in ipairs(slots) do
            local nt = s.to - dir
            if s.item and nt >= -1 and nt <= 1 and target[nt] == s.item and not at[nt] then
                s.from, s.mode = s.to, 'move'
                s.to = nt
                at[nt], stays[s] = s, true
            end
        end
    end
    local free = {}
    for _, s in ipairs(slots) do
        if not stays[s] then
            if s.item and dir ~= 0 then
                s.from, s.to, s.mode = s.to, s.to - dir, 'out'
            else
                s.item, s.mode = nil, 'idle'
            end
            free[#free + 1] = s
        end
    end
    -- empty sleeves first, then the ones sliding away
    table.sort(free, function(a, b) return (a.item and 1 or 0) < (b.item and 1 or 0) end)
    for k = -1, 1 do
        local item = target[k]
        if item and not at[k] then
            local s = table.remove(free, 1)
            if s then
                if dir == 0 then
                    s.item, s.o, s.from, s.to, s.mode, s.spin = item, k, k, k, 'idle', 0.0
                else
                    s.pending = { item = item, from = k + dir, to = k }
                end
                at[k] = s
            end
        end
    end
    -- warm the covers that come next: the sleeve on the left is reused for the one coming in on
    -- the right when browsing on, and the other way round
    for _, s in ipairs(slots) do
        s.warm = nil
        if s.to == -1 and s.mode ~= 'out' then s.warm = { warm and warm[2] } end
        if s.to == 1 and s.mode ~= 'out' then s.warm = { warm and warm[1] } end
        syncDui(s)
    end
    anim = { start = now, rise = dir == 0 }
end

local function frame(now, dt)
    local t = anim and math.min(1.0, (now - anim.start) / TRANSITION) or 1.0
    local e = ease(t)
    if anim and not anim.rise and t >= 0.5 then
        for _, s in ipairs(slots) do if s.pending then handoff(s) end end
    end
    local nd = nudge
    nudge = 0.0
    local dragging = now - lastDrag < 450
    local bob = math.sin(now / 700.0) * 0.005
    local sway = math.sin(now / 9000.0 * 2.0 * math.pi) * SWAY

    for _, s in ipairs(slots) do
        if s.duiLate and IsDuiAvailable(s.dui) then syncDui(s) end
        if s.item then
            local o = s.to
            if anim and not anim.rise then o = s.from + (s.to - s.from) * e end
            s.o = o
            local side, depth, alpha = slotAt(o)
            local lift = 0.0
            if anim then
                if anim.rise then
                    alpha, lift = alpha * e, -(1.0 - e) * 0.10
                elseif s.mode == 'out' then
                    alpha = alpha * math.max(0.0, 1.0 - t * 2.0)
                elseif s.mode == 'in' then
                    alpha = alpha * math.max(0.0, t * 2.0 - 1.0)
                end
            end
            local w = math.max(0.0, 1.0 - math.abs(o))

            -- dragging spins the featured sleeve; let go and it settles back to the nearest full turn
            if w > 0.5 then s.spin = s.spin + nd end
            if s.flourish then
                local ft = (now - s.flourish.start) / 1000.0
                if ft >= 1.0 then s.spin, s.flourish = s.flourish.to, nil
                else s.spin = s.flourish.from + (s.flourish.to - s.flourish.from) * easeOut(ft) end
            elseif not dragging or w <= 0.5 then
                local home = math.floor(s.spin / 360.0 + 0.5) * 360.0
                s.spin = s.spin + (home - s.spin) * (1.0 - math.exp(-dt * (w > 0.5 and 3.5 or 7.0)))
            end
            local idle
            if TURN == 'spin' then
                s.idle = (s.idle + SPIN * dt * w) % 360.0
                if w < 0.999 then
                    local y = s.idle > 180.0 and s.idle - 360.0 or s.idle
                    s.idle = (y * (1.0 - math.min(1.0, dt * 5.0 * (1.0 - w)))) % 360.0
                end
                idle = s.idle
            else
                idle = sway * w
            end

            local h = view.cover + idle + s.spin - clamp(o, -1.0, 1.0) * SIDE_ANGLE
            local p = view.anchor + view.right * side + view.fwd * depth + UP * (lift + bob * w)
            SetEntityCoordsNoOffset(s.ent, p.x, p.y, p.z, false, false, false)
            SetEntityRotation(s.ent, LEAN, 0.0, h, 2, false)
            setAlpha(s, s.ent, alpha)
            s.p, s.h = p, h
        else
            setAlpha(s, s.ent, 0)
        end
    end

    if anim and t >= 1.0 then
        for _, s in ipairs(slots) do
            if s.mode == 'out' then s.item = nil setAlpha(s, s.ent, 0) end
            s.mode, s.from, s.o = 'idle', s.to, s.to
        end
        anim = nil
    end

    -- the record: tucked into the sleeve that is leaving (0.25 s), then eased out of the new featured
    -- one once the row has settled (0.6 s)
    if disc.ent then
        local f = featured()
        local goal = 0.0
        if disc.owner ~= f then
            if disc.lin <= 0.0 then disc.owner = f end
        elseif not anim then
            goal = 1.0
        end
        if goal > disc.lin then disc.lin = math.min(goal, disc.lin + dt / 0.6)
        elseif goal < disc.lin then disc.lin = math.max(goal, disc.lin - dt / 0.25) end
        local s = disc.owner
        if s and s.item and s.p and s.alpha > 2 then
            local x, y, z = rotate(s.h, -ease(disc.lin) * DISC_OUT, DISC_MID, HALF)
            SetEntityCoordsNoOffset(disc.ent, s.p.x + x, s.p.y + y, s.p.z + z, false, false, false)
            -- stood up on its edge facing the camera (side B is the one that faces out)
            SetEntityRotation(disc.ent, LEAN + 90.0, 0.0, s.h, 2, false)
            setAlpha(disc, disc.ent, s.alpha)
        else
            setAlpha(disc, disc.ent, 0)
        end
    end
end

-- the album / price label floats above the featured sleeve
local function sendLabel(now)
    if not view or now - labelAt < 100 then return end
    labelAt = now
    local point = view.anchor + UP * (SLEEVE + 0.035)     -- centred over the sleeve + record pair
    local ok, x, y = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
    if not ok then return end
    if math.abs(x - labelX) < 0.001 and math.abs(y - labelY) < 0.001 then return end
    labelX, labelY = x, y
    SendNUIMessage({ action = 'shop:label', data = { x = x, y = y } })
end

---------------------------------------------------------------- clear the counter
-- Tills, monitors and the like around the display are hidden for the shopper only, and come back
-- when they leave. Props baked into an MLO need their model in hideProps.models.
-- A prop that has become networked (knocked over, moved) syncs its visibility to everyone, so it is
-- hidden locally every frame instead (frameLoop).
local hiddenEnts, localHides, modelHides = {}, {}, {}

local function hideCounterProps()
    local h = cfg.hideProps
    if not h or h.enabled == false then return end
    local radius, maxSize = h.radius or 1.6, h.maxSize or 1.6
    local spots = {
        view.anchor,
        view.anchor + view.right * SLOT[-1].side + view.fwd * SLOT[-1].depth,
        view.anchor + view.right * SLOT[1].side + view.fwd * SLOT[1].depth,
    }
    for _, obj in ipairs(GetGamePool('CObject')) do
        if IsEntityVisible(obj) and not IsEntityAttached(obj) and not IsEntityAMissionEntity(obj) then
            local c = GetEntityCoords(obj)
            for _, p in ipairs(spots) do
                if #(c - p) < radius then
                    local mn, mx = GetModelDimensions(GetEntityModel(obj))
                    if #(mx - mn) <= maxSize then
                        if NetworkGetEntityIsNetworked(obj) then
                            localHides[#localHides + 1] = obj
                        else
                            SetEntityVisible(obj, false, false)
                            hiddenEnts[#hiddenEnts + 1] = obj
                        end
                    end
                    break
                end
            end
        end
    end
    local a = view.anchor
    for _, m in ipairs(h.models or {}) do
        local hash = type(m) == 'number' and m or joaat(m)
        if IsModelInCdimage(hash) then
            CreateModelHide(a.x, a.y, a.z, radius + 0.6, hash, true)
            modelHides[#modelHides + 1] = hash
        end
    end
end

local function restoreCounterProps()
    for _, obj in ipairs(hiddenEnts) do
        if DoesEntityExist(obj) then SetEntityVisible(obj, true, false) end
    end
    hiddenEnts, localHides = {}, {}
    if view then
        local a = view.anchor
        local r = ((cfg.hideProps and cfg.hideProps.radius) or 1.6) + 0.6
        for _, hash in ipairs(modelHides) do RemoveModelHide(a.x, a.y, a.z, r, hash, false) end
    end
    modelHides = {}
end

---------------------------------------------------------------- listening
local function dropPreview()
    if Emitters[PREVIEW_ID] then
        Emitters[PREVIEW_ID] = nil
        ForgetEmitter(PREVIEW_ID)
        SendNUIMessage({ action = 'remove', id = PREVIEW_ID })
    end
end

-- fade = a short fade out instead of a cut; quiet = don't tell the UI (it already moved on)
local function stopPreview(fade, quiet)
    previewSeq = previewSeq + 1           -- cancels a search still running and the end timer
    preview = nil
    local e = Emitters[PREVIEW_ID]
    if e and fade then
        CreateThread(function()
            local v0 = e.volume or 0.8
            for i = 1, 6 do
                Wait(100)
                if Emitters[PREVIEW_ID] ~= e then return end
                e.volume = v0 * (1.0 - i / 6)
                SendNUIMessage({ action = 'emitter', data = e })
            end
            if Emitters[PREVIEW_ID] == e then dropPreview() end
        end)
    else
        dropPreview()
    end
    if not quiet then SendNUIMessage({ action = 'shop:preview', data = { state = 'idle' } }) end
end

local function startPreview(item)
    stopPreview(false, true)
    local seq = previewSeq
    preview = { item = item }
    SendNUIMessage({ action = 'shop:preview', data = { item = item, state = 'loading' } })
    CreateThread(function()
        local track, err = NZ.Callback('shop:preview', item)
        if seq ~= previewSeq or not open then return end
        if type(track) ~= 'table' then
            preview = nil
            SendNUIMessage({ action = 'shop:preview', data = { item = item, state = 'idle', error = L(err or 'shop_preview_fail') } })
            return
        end
        local length = P.length or 30
        local dur = tonumber(track.duration) or 0
        local from = P.start or 30
        if dur > 0 then from = clamp(dur * (P.at or 0.3), 0, math.max(0, dur - length - 1)) end
        local e = {
            id = PREVIEW_ID, kind = 'preview', volume = P.volume or 0.8, playing = true, pos = 0,
            startedAt = ServerTime() - math.floor(from * 1000) + 250,
            track = { mode = track.mode, src = track.src, id = track.id, url = track.url, title = track.title,
                author = track.author, duration = dur, thumb = track.thumb },
        }
        Emitters[PREVIEW_ID] = e
        SendNUIMessage({ action = 'emitter', data = e })
        SendNUIMessage({ action = 'shop:preview', data = { item = item, state = 'playing', length = length, title = track.title } })
        Wait(length * 1000)
        if seq == previewSeq then stopPreview(true) end
    end)
end

---------------------------------------------------------------- open / close
local function closeShop(instant)
    if not open then return end
    open = false
    stopPreview(not instant, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shop:close' })
    TriggerServerEvent(RES .. ':shop:closed')
    clear3d()
    restoreCounterProps()
    RenderScriptCams(false, not instant, 600, true, true)
    if cam then DestroyCam(cam, false) cam = nil end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if savedHeading then SetEntityHeading(ped, savedHeading) end
    savedHeading, view, current = nil, nil, nil
end

local function frameLoop()
    local last = GetGameTimer()
    while open do
        local now = GetGameTimer()
        local dt = math.min(0.1, (now - last) / 1000.0)
        last = now
        local ped = PlayerPedId()
        HideHudAndRadarThisFrame()
        DisableControlAction(0, 199, true)       -- pause menu
        DisableControlAction(0, 200, true)
        if cfg.depthOfField ~= false then SetUseHiDof() end
        -- the camera stands where the shopper is, so hide them for themselves only
        SetLocalPlayerInvisibleLocally(true)
        SetEntityLocallyInvisible(ped)
        for i = 1, #localHides do
            local obj = localHides[i]
            if DoesEntityExist(obj) then SetEntityLocallyInvisible(obj) end
        end
        if mode3d then frame(now, dt) sendLabel(now) end
        if IsEntityDead(ped) then closeShop(true) end
        Wait(0)
    end
end

-- the page may have loaded before this script registered 'shopReady', so ask again when needed
local function uiLoaded()
    if nuiReady then return true end
    SendNUIMessage({ action = 'shop:ping' })
    local t = GetGameTimer()
    while not nuiReady and GetGameTimer() - t < 600 do Wait(50) end
    return nuiReady
end

local function openShop(at)
    if open or opening then return end
    if not uiLoaded() then
        print('^3[nayzeee-speaker] ' .. L('shop_no_ui') .. ' See the record shop install notes.^7')
        return Notify(L('shop_no_ui'), 'error')
    end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if IsPedInAnyVehicle(ped, false) then return Notify(L('shop_vehicle'), 'error') end
    opening = true
    if UI.open then CloseUI() end

    local data, err = NZ.Callback('shop:open', at)
    if type(data) ~= 'table' then
        opening = false
        return Notify(L(err or 'shop_far'), 'error')
    end

    view = buildView(at ~= 'admin' and LOCS[at] or nil)
    catalog = {}
    for _, it in ipairs(data.items) do catalog[it.item] = { cover = it.cover, album = it.album, artist = it.artist } end
    mode3d = want3d() and load3d()

    savedHeading = GetEntityHeading(ped)
    FreezeEntityPosition(ped, true)
    ClearPedTasks(ped)
    hideCounterProps()

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', view.cam.x, view.cam.y, view.cam.z, 0.0, 0.0, 0.0, view.fov, false, 0)
    PointCamAtCoord(cam, view.look.x, view.look.y, view.look.z)
    if cfg.depthOfField ~= false then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, 0.12)
        SetCamFarDof(cam, #(view.look - view.cam) + 0.9)
        SetCamDofStrength(cam, 0.8)
    end
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 900, true, true)

    open, opening = true, false
    labelX, labelY, labelAt, nudge = -1, -1, 0, 0.0
    CreateThread(frameLoop)

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({
        action = 'shop:open',
        data = {
            items = data.items, genres = data.genres, owned = data.owned or {}, wallet = data.wallet or 0,
            account = data.account, title = data.title, mode = mode3d and '3d' or '2d',
            text = uiText(), streamer = Settings.streamer,
            preview = P.enabled ~= false, previewLength = P.length or 30,
            brand = { watermark = Config.Brand.watermark, logo = Config.Brand.logo },
        },
    })
end

---------------------------------------------------------------- NUI
RegisterNUICallback('shopReady', function(_, cb) nuiReady = true cb(1) end)

RegisterNUICallback('shopClose', function(_, cb) closeShop() cb(1) end)

-- the UI owns the (filtered) list and says what stands where
RegisterNUICallback('shopView', function(data, cb)
    cb(1)
    if not open or type(data) ~= 'table' then return end
    local function known(v) return type(v) == 'string' and catalog[v] and v or nil end
    local cur = known(data.cur)
    if preview and preview.item ~= cur then stopPreview(true) end
    local dir = tonumber(data.dir) or 0
    if current and cur ~= current and dir ~= 0 then sound('NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET') end
    current = cur
    if mode3d then
        applyView({ [-1] = known(data.prev), [0] = cur, [1] = known(data.next) },
            (dir == 1 or dir == -1) and dir or 0,
            { known(type(data.warm) == 'table' and data.warm[1]), known(type(data.warm) == 'table' and data.warm[2]) })
    end
end)

RegisterNUICallback('shopSpin', function(data, cb)
    cb(1)
    nudge = nudge + clamp(tonumber(data and data.delta) or 0.0, -90.0, 90.0)
    lastDrag = GetGameTimer()
end)

RegisterNUICallback('shopListen', function(data, cb)
    cb(1)
    if not open then return end
    local item = data and data.item
    if type(item) ~= 'string' or not catalog[item] then return end
    if preview and preview.item == item then return stopPreview(true) end
    startPreview(item)
end)

RegisterNUICallback('shopBuy', function(data, cb)
    cb(1)
    local item = data and data.item
    if not open or type(item) ~= 'string' or not catalog[item] then return end
    CreateThread(function()
        local res = NZ.Callback('shop:buy', item)
        if not open then return end
        if type(res) ~= 'table' then res = { ok = false, reason = 'shop_busy' } end
        if res.ok then
            if preview then stopPreview(true) end
            sound('PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET')
            local f = featured()
            if f and f.item == item then f.flourish = { start = GetGameTimer(), from = f.spin, to = f.spin + 360.0 } end
        else
            sound('ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET')
        end
        SendNUIMessage({ action = 'shop:result', data = {
            ok = res.ok == true, item = item, reason = not res.ok and L(res.reason or 'shop_busy') or nil,
            wallet = res.wallet, owned = res.owned,
        } })
    end)
end)

RegisterNetEvent(RES .. ':client:shopCovers', function(found)
    if not open or type(found) ~= 'table' then return end
    for item, url in pairs(found) do
        if catalog[item] then catalog[item].cover = url end
    end
    for _, s in ipairs(slots) do syncDui(s) end
    SendNUIMessage({ action = 'shop:covers', data = found })
end)

-- /recordshop (admins, for testing): the server checked the permission and checks it again on open
RegisterNetEvent(RES .. ':client:shopOpen', function(at)
    if at == 'admin' then openShop('admin') end
end)

---------------------------------------------------------------- shopkeepers, blips, prompts
local peds, blips = {}, {}
local PED_IN, PED_OUT = cfg.pedDistance or 60.0, (cfg.pedDistance or 60.0) + 15.0
local TARGET = 'nzspk_recordshop'
local PROMPT = L('shop_prompt')

local function spawnPed(i, loc)
    peds[i] = false                           -- loading
    local ped = Bridge.SpawnShopPed(loc.ped or 'a_m_y_hipster_01', loc.coords, loc.heading or 0.0, loc.scenario)
    if not ped then peds[i] = nil return end
    peds[i] = ped
    if Bridge.Target then
        Bridge.AddEntityTarget(ped, { {
            name = TARGET, label = L('shop_target'), icon = 'fa-solid fa-record-vinyl',
            action = function() CreateThread(function() openShop(i) end) end,
        } }, INTERACT)
    end
end

local function despawnPed(i)
    local ped = peds[i]
    peds[i] = nil
    if not ped then return end
    if Bridge.Target then Bridge.RemoveEntityTarget(ped, { TARGET }) end
    if DoesEntityExist(ped) then DeleteEntity(ped) end
end

CreateThread(function()
    for i, loc in ipairs(LOCS) do
        if loc.blip ~= false and loc.coords then
            local b = loc.blip or {}
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, b.sprite or 52)
            SetBlipColour(blip, b.color or 26)
            SetBlipScale(blip, b.scale or 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label or loc.label or 'Record Shop')
            EndTextCommandSetBlipName(blip)
            blips[i] = blip
        end
    end
end)

-- one loop for every shop: keeps the shopkeeper spawned while you're near and shows the [E]
-- prompt (no target resource, or a shop without a shopkeeper). Sleeps a second when nothing is near.
CreateThread(function()
    while true do
        local sleep = 1000
        local me = GetEntityCoords(PlayerPedId())
        for i, loc in ipairs(LOCS) do
            if loc.coords then
                local d = #(me - loc.coords)
                if loc.ped ~= false then
                    if d < PED_IN and peds[i] == nil then spawnPed(i, loc)
                    elseif d > PED_OUT and peds[i] then despawnPed(i) end
                end
                local ped = peds[i]
                if not open and d < 12.0 and (not ped or not Bridge.Target) then
                    sleep = 0
                    if not ped and loc.marker ~= false then
                        local m = loc.marker or {}
                        DrawMarker(m.type or 21, loc.coords.x, loc.coords.y, loc.coords.z + 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            m.scale or 0.45, m.scale or 0.45, m.scale or 0.45, 8, 175, 162, 150, true, true, 2, false, nil, nil, false)
                    end
                    if d < INTERACT then
                        Bridge.DrawPrompt(loc.coords + vector3(0.0, 0.0, ped and 1.0 or 0.8), PROMPT)
                        if IsControlJustPressed(0, 38) and not opening then CreateThread(function() openShop(i) end) end
                    end
                elseif d < 60.0 and sleep > 400 then
                    sleep = 400
                end
            end
        end
        Wait(sleep)
    end
end)

exports('OpenRecordShop', function(index)
    index = tonumber(index) or 1
    if LOCS[index] then CreateThread(function() openShop(index) end) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    if open then closeShop(true) end
    for i in pairs(peds) do despawnPed(i) end
    for _, b in pairs(blips) do RemoveBlip(b) end
end)
