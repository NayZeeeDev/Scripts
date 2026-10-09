-----------------------------------------------------------------
-- Jewelry store
--
-- The backpack store's counter, for chains. Walk up to the jeweller
-- and the camera moves over the counter; the chains float above it
-- on a tilted display, the featured one slowly turning, the
-- previous / next either side. The name + price float above it.
--
-- [A]/[D] or wheel  browse    drag  spin    [T] try it on
-- [ENTER] buy       [ESC] leave            tabs: Buy · Craft · Repair
--
-- Only runs while the store is open.
-----------------------------------------------------------------

Store = { open = false }

local cfg = Config.Store
if not cfg or not cfg.Enabled then return end

local open = false
local mode = 'counter'      -- 'counter' | 'tryon'
local storePeds = {}
local view = nil
local counterCam, tryCam = nil, nil
local live = {}
local spinNudge, spinBoost = 0.0, 0.0
local anim = nil
local current = nil         -- { key, letter }
local tryProp = nil
local tryHeading, pedTurn, savedHeading = 0.0, 0.0, nil
local preloaded = {}

local UP = vector3(0.0, 0.0, 1.0)
local PITCH = -70.0          -- the display tilts each chain toward the customer

-----------------------------------------------------------------
-- counter geometry (same as the backpack store)
-----------------------------------------------------------------

local function buildView(location)
    local d = location and location.display or {}
    local base, h
    if location then
        base, h = location.coords, location.heading or 0.0
    else
        local ped = PlayerPedId()
        base = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.4, 0.0)
        h = (GetEntityHeading(ped) + 180.0) % 360.0
    end
    local r = math.rad(h)
    local fwd = vector3(-math.sin(r), math.cos(r), 0.0)
    local anchor = d.chain or (base + fwd * (d.forward or 0.70) + UP * (d.height or 0.30))
    local camPos = d.cam or (anchor + fwd * (d.camDistance or 0.85) + UP * (d.camHeight or 0.12))
    local look = anchor - camPos
    local flat = vector3(look.x, look.y, 0.0)
    local len = #flat
    flat = len < 0.001 and vector3(0.0, 1.0, 0.0) or flat / len
    return {
        anchor = anchor, cam = camPos, fwd = flat, right = vector3(flat.y, -flat.x, 0.0),
        heading = GetHeadingFromVector_2d(flat.x, flat.y), fov = d.fov or 38.0,
    }
end

local SLOT = {
    [-2] = { side = -0.70, depth = 0.40, alpha = 0 },
    [-1] = { side = -0.36, depth = 0.20, alpha = 150 },
    [0]  = { side = 0.0,   depth = 0.0,  alpha = 255 },
    [1]  = { side = 0.36,  depth = 0.20, alpha = 150 },
    [2]  = { side = 0.70,  depth = 0.40, alpha = 0 },
}

local function slotAt(o)
    o = math.max(-2.0, math.min(2.0, o))
    local lo = math.floor(o)
    local hi = math.min(2, lo + 1)
    local t = o - lo
    local a, b = SLOT[lo], SLOT[hi]
    if not cfg.SideChains then
        a = { side = a.side, depth = a.depth, alpha = lo == 0 and 255 or 0 }
        b = { side = b.side, depth = b.depth, alpha = hi == 0 and 255 or 0 }
    end
    return a.side + (b.side - a.side) * t, a.depth + (b.depth - a.depth) * t, a.alpha + (b.alpha - a.alpha) * t
end

local function ease(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end

-----------------------------------------------------------------
-- carousel
-----------------------------------------------------------------

local function spawnSlot(key, letter, offset)
    local entity, hash = Util.spawnChain(key, letter, view.anchor - UP * 3.0)
    if not entity then return nil end
    FreezeEntityPosition(entity, true)
    SetEntityAlpha(entity, 0, false)
    local c, mn, mx = Util.modelCentre(hash)
    local it = {
        entity = entity, key = key, letter = letter, c = c,
        top = math.max(mx.x - c.x, mx.y - c.y, mx.z - c.z),
        from = offset, to = offset, o = offset, alpha = -1, yaw = 0.0,
    }
    live[#live + 1] = it
    return it
end

local function clearSlots()
    for _, it in ipairs(live) do Util.delete(it.entity) end
    live = {}
    anim = nil
end

--- Mesh centre at `p`, tilted toward the customer, turned `heading` about the vertical.
local function place(it, p, heading)
    local R = M3.mul(M3.rz(heading), M3.rx(PITCH))
    local o = p - M3.apply(R, it.c)
    local right, fwd, up = M3.apply(R, vector3(1, 0, 0)), M3.apply(R, vector3(0, 1, 0)), M3.apply(R, vector3(0, 0, 1))
    SetEntityMatrix(it.entity, fwd.x, fwd.y, fwd.z, right.x, right.y, right.z, up.x, up.y, up.z, o.x, o.y, o.z)
end

local function sendLabel()
    local centre
    for _, it in ipairs(live) do if it.to == 0 then centre = it end end
    if not centre then return end
    local point = view.anchor + UP * (centre.top + 0.05)
    local ok, x, y = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
    if ok then NUI.send('store:label', { x = x, y = y }) end
end

local function settle()
    if not anim then return end
    local keep = {}
    for _, it in ipairs(live) do
        it.o, it.from = it.to, it.to
        if math.abs(it.to) > 1 then Util.delete(it.entity) else keep[#keep + 1] = it end
    end
    live = keep
    anim = nil
end

local function rebuild(prev, cur, nxt)
    clearSlots()
    anim = { start = GetGameTimer(), duration = cfg.TransitionTime or 420, rise = true }
    if cur then spawnSlot(cur.key, cur.letter, 0) end
    if cfg.SideChains then
        if prev then spawnSlot(prev.key, prev.letter, -1) end
        if nxt then spawnSlot(nxt.key, nxt.letter, 1) end
    end
    anim.start = GetGameTimer()
end

local function shift(dir, incoming)
    settle()
    for _, it in ipairs(live) do it.from = it.o; it.to = it.o - dir end
    if incoming and cfg.SideChains then
        local it = spawnSlot(incoming.key, incoming.letter, dir * 2)
        if it then it.from, it.o, it.to = dir * 2, dir * 2, dir end
    end
    anim = { start = GetGameTimer(), duration = cfg.TransitionTime or 420 }
    spinBoost = 0.0
end

local function setCentreLetter(key, letter)
    for i, it in ipairs(live) do
        if it.to == 0 and it.key == key then
            Util.delete(it.entity)
            table.remove(live, i)
            local n = spawnSlot(key, letter, 0)
            if n then n.alpha = -1 end
            return
        end
    end
end

-----------------------------------------------------------------
-- per-frame loop (only while open)
-----------------------------------------------------------------

local function frameLoop()
    local last = GetGameTimer()
    local speed = cfg.SpinSpeed or 18.0
    while open do
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now
        HideHudAndRadarThisFrame()
        if cfg.DepthOfField and mode == 'counter' then SetUseHiDof() end
        if mode == 'counter' then
            SetLocalPlayerInvisibleLocally(true)
            SetEntityLocallyInvisible(PlayerPedId())
        end

        local spinRate = speed + spinBoost
        if spinBoost > 0 then spinBoost = math.max(0.0, spinBoost - 600.0 * dt) end
        local nudge = spinNudge
        spinNudge = 0.0

        local t = anim and math.min(1.0, (now - anim.start) / anim.duration) or 1.0
        local e = ease(t)
        local bob = math.sin(now / 620.0) * 0.006

        for _, it in ipairs(live) do
            if anim and not anim.rise then it.o = it.from + (it.to - it.from) * e end
            local side, depth, alpha = slotAt(it.o)
            local weight = math.max(0.0, 1.0 - math.abs(it.o))
            local p = view.anchor + view.right * side + view.fwd * depth
            if weight > 0.0 then p = p + UP * (bob * weight) end
            if anim and anim.rise then
                p = p - UP * ((1.0 - e) * 0.12)
                alpha = alpha * e
            end
            if weight > 0.5 then it.yaw = it.yaw + nudge end
            it.yaw = (it.yaw + spinRate * dt * weight) % 360.0
            if weight < 0.999 then
                local y = it.yaw > 180.0 and it.yaw - 360.0 or it.yaw
                it.yaw = (y * (1.0 - math.min(1.0, dt * 5.0 * (1.0 - weight)))) % 360.0
            end
            -- facing the customer = the chain's front toward the camera
            place(it, p, view.heading + 180.0 + it.yaw - it.o * 22.0)
            local a = math.floor(alpha)
            if a ~= it.alpha then
                it.alpha = a
                if a >= 255 then ResetEntityAlpha(it.entity) else SetEntityAlpha(it.entity, a, false) end
            end
        end

        if anim and t >= 1.0 then
            anim = nil
            local keep = {}
            for _, it in ipairs(live) do
                it.o, it.from = it.to, it.to
                if math.abs(it.to) > 1 then Util.delete(it.entity) else keep[#keep + 1] = it end
            end
            live = keep
            sendLabel()
        end
        Wait(0)
    end
end

-----------------------------------------------------------------
-- clear the counter (tills, monitors) for the shopper only
-----------------------------------------------------------------

local hiddenEnts, modelHides = {}, {}

local function hideCounterProps()
    local h = cfg.HideProps
    if not h or h.Enabled == false then return end
    local radius, maxSize = h.Radius or 1.4, h.MaxSize or 1.2
    local spots = { view.anchor, view.anchor + view.right * 0.36 + view.fwd * 0.2, view.anchor - view.right * 0.36 + view.fwd * 0.2 }
    local function near(c)
        for _, p in ipairs(spots) do if #(c - p) < radius then return true end end
        return false
    end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if IsEntityVisible(obj) and not IsEntityAttached(obj) and near(GetEntityCoords(obj)) then
            local mn, mx = GetModelDimensions(GetEntityModel(obj))
            if #(mx - mn) <= maxSize then
                SetEntityVisible(obj, false, false)
                hiddenEnts[#hiddenEnts + 1] = obj
            end
        end
    end
    local a, r = view.anchor, radius + 0.5
    for _, m in ipairs(h.Models or {}) do
        local hash = type(m) == 'number' and m or joaat(m)
        if IsModelInCdimage(hash) then
            CreateModelHide(a.x, a.y, a.z, r, hash, true)
            modelHides[#modelHides + 1] = hash
        end
    end
end

local function restoreCounterProps()
    for _, obj in ipairs(hiddenEnts) do if DoesEntityExist(obj) then SetEntityVisible(obj, true, false) end end
    hiddenEnts = {}
    if view then
        local a, r = view.anchor, ((cfg.HideProps and cfg.HideProps.Radius) or 1.4) + 0.5
        for _, hash in ipairs(modelHides) do RemoveModelHide(a.x, a.y, a.z, r, hash, false) end
    end
    modelHides = {}
end

-----------------------------------------------------------------
-- cameras + try on
-----------------------------------------------------------------

local function makeCounterCam()
    counterCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', view.cam.x, view.cam.y, view.cam.z, 0.0, 0.0, 0.0, view.fov, false, 0)
    PointCamAtCoord(counterCam, view.anchor.x, view.anchor.y, view.anchor.z - 0.01)
    if cfg.DepthOfField then
        local dist = #(view.anchor - view.cam)
        SetCamUseShallowDofMode(counterCam, true)
        SetCamNearDof(counterCam, 0.1)
        SetCamFarDof(counterCam, dist + 0.6)
        SetCamDofStrength(counterCam, 0.85)
    end
end

local function updateTryCam()
    if not tryCam then return end
    local ped = PlayerPedId()
    local c = GetPedBoneCoords(ped, 39317, 0.0, 0.0, 0.0)
    local r = math.rad(tryHeading)
    SetCamCoord(tryCam, c.x - math.sin(r) * 0.95, c.y + math.cos(r) * 0.95, c.z + 0.05)
    PointCamAtCoord(tryCam, c.x, c.y, c.z - 0.08)
end

local function clearTryOn()
    Util.delete(tryProp)
    tryProp = nil
end

local function applyTryOn()
    clearTryOn()
    if not current then return end
    local ped = PlayerPedId()
    tryProp = Util.spawnChain(current.key, current.letter, GetEntityCoords(ped))
    if not tryProp then return end
    local f = Chains.fit(current.key, 'worn', Util.isFemale(ped))
    Util.attach(tryProp, ped, f.bone, f.pos, f.rot)
end

local function setMode(m)
    if m == mode then return end
    local ped = PlayerPedId()
    if m == 'tryon' then
        tryHeading = (view.heading + 180.0) % 360.0
        pedTurn = 180.0
        SetEntityHeading(ped, (tryHeading + pedTurn) % 360.0)
        tryCam = tryCam or CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0, 0, 0, 0, 0, 0, 32.0, false, 0)
        updateTryCam()
        applyTryOn()
        SetCamActiveWithInterp(tryCam, counterCam, 650, 1, 1)
        for _, it in ipairs(live) do SetEntityVisible(it.entity, false, false) end
    else
        clearTryOn()
        SetCamActiveWithInterp(counterCam, tryCam, 650, 1, 1)
        for _, it in ipairs(live) do SetEntityVisible(it.entity, true, false) end
        SetTimeout(700, sendLabel)
    end
    mode = m
    NUI.send('store:mode', { mode = m })
end

-----------------------------------------------------------------
-- open / close
-----------------------------------------------------------------

local pending, working, collapsed = nil, false, false

local function closeStore()
    if not open then return end
    open = false
    Store.open = false
    SetNuiFocus(false, false)
    NUI.send('store:close')
    clearTryOn()
    clearSlots()
    restoreCounterProps()
    for h in pairs(preloaded) do SetModelAsNoLongerNeeded(h) end
    preloaded = {}
    pending, working, collapsed = nil, false, false
    RenderScriptCams(false, true, 600, true, true)
    if counterCam then DestroyCam(counterCam, false) end
    if tryCam then DestroyCam(tryCam, false) end
    counterCam, tryCam = nil, nil
    local ped = PlayerPedId()
    if savedHeading then SetEntityHeading(ped, savedHeading) end
    savedHeading = nil
    FreezeEntityPosition(ped, false)
    WornProps.hideSelf(false)
    mode = 'counter'
end

function Store.show(location)
    if open or Menu.open or (Studio and Studio.open) or Hold.active() or Place.active() or Snatch.tug then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return CB.Notify('Not while you are in a vehicle.', 'error') end
    local data = lib.callback.await('nzc:store:open', false)
    if not data then return CB.Notify(Config.Text.too_far, 'error') end
    if #data.items == 0 and #data.repairs == 0 then return CB.Notify('Nothing for sale here.', 'error') end

    view = buildView(location)
    for _, item in ipairs(data.items) do
        for _, v in ipairs(item.variants) do
            local h = joaat(v.prop)
            if IsModelInCdimage(h) and not preloaded[h] then preloaded[h] = true; RequestModel(h) end
        end
    end
    savedHeading = GetEntityHeading(ped)
    FreezeEntityPosition(ped, true)
    WornProps.hideSelf(true)
    hideCounterProps()
    makeCounterCam()
    SetCamActive(counterCam, true)
    RenderScriptCams(true, true, 900, true, true)

    open = true
    Store.open = true
    mode = 'counter'
    spinNudge = 0.0
    CreateThread(frameLoop)

    data.title = location and location.label or Config.Text.store_title
    data.text = Config.Text
    SetNuiFocus(true, true)
    NUI.send('store:open', data)
    SetTimeout(950, sendLabel)
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

local function entryOf(t)
    if type(t) ~= 'table' or not Chains.exists(t.key) then return nil end
    return { key = t.key, letter = Chains.variant(t.key, t.letter).letter }
end

local function applyView(data, force)
    local prev, cur, nxt = entryOf(data.prev), entryOf(data.cur), entryOf(data.next)
    current = cur
    local dir = tonumber(data.dir) or 0
    if force or dir == 0 or #live == 0 then rebuild(prev, cur, nxt) else shift(dir, dir > 0 and nxt or prev) end
    if mode == 'tryon' then applyTryOn() end
end

RegisterNUICallback('store:close', function(_, cb) cb('ok'); closeStore() end)

RegisterNUICallback('store:view', function(data, cb)
    cb('ok')
    if not open then return end
    if working then
        collapsed = pending ~= nil or collapsed
        pending = data
        return
    end
    working = true
    applyView(data, false)
    while pending and open do
        local d, force = pending, collapsed
        pending, collapsed = nil, false
        applyView(d, force)
    end
    working = false
end)

RegisterNUICallback('store:variant', function(data, cb)
    cb('ok')
    if not current or data.key ~= current.key then return end
    current.letter = Chains.variant(current.key, data.letter).letter
    setCentreLetter(current.key, current.letter)
    if mode == 'tryon' then applyTryOn() end
end)

RegisterNUICallback('store:spin', function(data, cb)
    cb('ok')
    local d = tonumber(data.delta) or 0.0
    if mode == 'tryon' then
        pedTurn = (pedTurn + d) % 360.0
        SetEntityHeading(PlayerPedId(), (tryHeading + pedTurn) % 360.0)
    else
        spinNudge = spinNudge + d
    end
end)

RegisterNUICallback('store:mode', function(data, cb) cb('ok'); setMode(data.mode == 'tryon' and 'tryon' or 'counter') end)
RegisterNUICallback('store:buy', function(d, cb) cb('ok'); TriggerServerEvent('nzc:store:buy', d.key, d.letter) end)
RegisterNUICallback('store:craft', function(d, cb) cb('ok'); TriggerServerEvent('nzc:store:craft', d.key, d.letter) end)
RegisterNUICallback('store:repair', function(d, cb) cb('ok'); TriggerServerEvent('nzc:store:repair', tonumber(d.slot)) end)

RegisterNetEvent('nzc:store:result', function(ok, msg, data)
    CB.Notify(msg, ok and 'success' or 'error')
    if ok then spinBoost = 720.0 end
    if open then NUI.send('store:result', { ok = ok, items = data and data.items, repairs = data and data.repairs, wallet = data and data.wallet }) end
end)

RegisterNetEvent('nzc:store:working', function(ms, kind)
    if open then NUI.send('store:working', { ms = ms, kind = kind }) end
end)

-----------------------------------------------------------------
-- world: jeweller, blip, prompts
-----------------------------------------------------------------

local wantsWorld = cfg.OpenMode ~= 'command'

CreateThread(function()
    if not wantsWorld then return end
    for _, loc in ipairs(cfg.Locations or {}) do
        if loc.blip then
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, loc.blip.sprite or 617)
            SetBlipColour(blip, loc.blip.color or 46)
            SetBlipScale(blip, loc.blip.scale or 0.75)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(loc.blip.label or Config.Text.store_title)
            EndTextCommandSetBlipName(blip)
        end
        if loc.ped then
            local hash = Util.loadModel(loc.ped, true)
            if hash then
                local ped = CreatePed(4, hash, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, loc.heading or 0.0, false, false)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetModelAsNoLongerNeeded(hash)
                storePeds[#storePeds + 1] = ped
                if CB.Target == 'ox_target' then
                    exports.ox_target:addLocalEntity(ped, { {
                        name = 'nzc_store', label = 'Browse chains', icon = 'fa-solid fa-gem', distance = 2.5,
                        onSelect = function() Store.show(loc) end,
                    } })
                elseif CB.Target == 'qb-target' then
                    exports['qb-target']:AddTargetEntity(ped, { options = { {
                        icon = 'fa-solid fa-gem', label = 'Browse chains', action = function() Store.show(loc) end,
                    } }, distance = 2.5 })
                end
            end
        end
    end
end)

-- [E] prompt without a target script (or for a location with no jeweller)
CreateThread(function()
    if not wantsWorld then return end
    local showing = false
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local near = nil
        for _, loc in ipairs(cfg.Locations or {}) do
            if (CB.Target == 'none' or not loc.ped) and #(coords - loc.coords) < 2.5 then near = loc break end
        end
        if near and not open then
            if not showing then showing = true; NUI.hint('<kc>E</kc> Browse chains', 'store') end
            if IsControlJustPressed(0, 38) then
                showing = false; NUI.hint(nil)
                Store.show(near)
            end
        elseif showing then
            showing = false
            if NUI.hintText == '<kc>E</kc> Browse chains' then NUI.hint(nil) end
        end
        Wait(near and 0 or 900)
    end
end)

if cfg.OpenMode == 'command' or cfg.OpenMode == 'both' then
    RegisterCommand(cfg.Command or 'chainstore', function()
        if open then return end
        local best, bd = nil, 8.0
        local c = GetEntityCoords(PlayerPedId())
        for _, loc in ipairs(cfg.Locations or {}) do
            local d = #(c - loc.coords)
            if d < bd then best, bd = loc, d end
        end
        Store.show(best)
    end, false)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then closeStore() end
    for _, ped in ipairs(storePeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
end)
