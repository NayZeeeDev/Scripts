-----------------------------------------------------------------
-- Bag store
--
-- Walk up to the counter and the camera moves over it. The bags
-- float above the counter in a carousel: the featured bag in the
-- middle slowly turning, the previous / next ones either side.
-- Swapping slides the whole row with an eased transition, and the
-- name + price float above the bag itself.
--
-- [A]/[D] or wheel   swap        [ENTER]  buy
-- drag               spin        [T]      try it on (character view)
-- [ESC]/[BACKSPACE]  leave
--
-- Everything here only runs while the store is open.
-----------------------------------------------------------------

if not Config.Shop or not Config.Shop.enabled then return end

local cfg = Config.Shop

local open = false
local mode = 'counter'      -- 'counter' | 'tryon'
local shopPeds = {}

local view = nil            -- anchor / axes for the current counter
local counterCam, tryCam = nil, nil
local live = {}             -- carousel entities
local spinNudge = 0.0       -- drag input waiting to be applied to the featured bag
local spinBoost = 0.0
local anim = nil            -- { start, duration } while sliding
local current = nil         -- { key, variant }
local tryProp = nil
local tryHeading = 0.0      -- where the try-on camera sits around the ped
local pedTurn = 0.0         -- how far the player has spun their character
local savedHeading = nil
local preloaded = {}

local UP = vec3(0.0, 0.0, 1.0)

-----------------------------------------------------------------
-- catalogue
-----------------------------------------------------------------

local function catalog()
    local list = {}

    for key, bag in pairs(Config.Backpacks) do
        local price = Bags.price(key)
        if price and (not bag.job or CanUseBag(key)) then
            local storage = Bags.storage(key)
            local variants = {}
            for _, v in ipairs(Bags.variants(key)) do
                variants[#variants + 1] = { id = v.id, label = v.label }
            end

            local jobs = Bags.jobs(key)
            list[#list + 1] = {
                key = key, label = Bags.label(key), model = bag.model,
                category = bag.category or 'backpack',
                theme = bag.theme or 'realistic',
                price = price,
                slots = storage.slots, weight = storage.weight,
                variants = variants,
                job = jobs and jobs[1] or nil,
                carry = Bags.carryStyle(key) and true or false,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.label < b.label
    end)
    return list
end

local function ownedMap()
    local owned = {}
    local items = exports.ox_inventory:GetPlayerItems() or {}
    for _, item in pairs(items) do
        if item and Bags.exists(item.name) then owned[item.name] = true end
    end
    return owned
end

-----------------------------------------------------------------
-- counter geometry
-----------------------------------------------------------------

local function buildView(location)
    local d = location and location.display or {}
    local anchor, camPos

    if d.bag and d.cam then
        anchor, camPos = d.bag, d.cam
    elseif d.bag then
        -- exact float spot; the camera stands back towards the customer
        local h = d.heading or (location and location.heading) or 0.0
        local r = math.rad(h)
        local fwd = vec3(-math.sin(r), math.cos(r), 0.0)
        anchor = d.bag
        camPos = anchor + fwd * (d.camDistance or 1.25) + UP * (d.camHeight or 0.22)
    else
        -- work it out from the shop keeper: bag floats over the counter in
        -- front of them, camera stands on the customer's side looking in
        local base, h
        if location then
            base, h = location.coords, location.heading or 0.0
        else
            local ped = PlayerPedId()
            base = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.6, 0.0)
            h = (GetEntityHeading(ped) + 180.0) % 360.0
        end
        local r = math.rad(h)
        local fwd = vec3(-math.sin(r), math.cos(r), 0.0)
        anchor = base + fwd * (d.forward or 0.70) + UP * (d.height or 0.30)
        camPos = anchor + fwd * (d.camDistance or 1.25) + UP * (d.camHeight or 0.22)
    end

    local look = anchor - camPos
    local flat = vec3(look.x, look.y, 0.0)
    local len = #flat
    if len < 0.001 then flat = vec3(0.0, 1.0, 0.0) else flat = flat / len end

    return {
        anchor  = anchor,
        cam     = camPos,
        fwd     = flat,                          -- away from the camera
        right   = vec3(flat.y, -flat.x, 0.0),   -- camera right
        heading = GetHeadingFromVector_2d(flat.x, flat.y),
        fov     = d.fov or 42.0,
    }
end

--- World position + alpha for a (fractional) carousel slot.
local SLOT = {
    [-2] = { side = -1.20, depth = 0.65, alpha = 0 },
    [-1] = { side = -0.62, depth = 0.32, alpha = 160 },
    [0]  = { side = 0.0,   depth = 0.0,  alpha = 255 },
    [1]  = { side = 0.62,  depth = 0.32, alpha = 160 },
    [2]  = { side = 1.20,  depth = 0.65, alpha = 0 },
}

local function slotAt(o)
    o = math.max(-2.0, math.min(2.0, o))
    local lo = math.floor(o)
    local hi = math.min(2, lo + 1)
    local t = o - lo
    local a, b = SLOT[lo], SLOT[hi]
    if not cfg.sideBags then
        a = { side = a.side, depth = a.depth, alpha = lo == 0 and 255 or 0 }
        b = { side = b.side, depth = b.depth, alpha = hi == 0 and 255 or 0 }
    end
    return a.side + (b.side - a.side) * t,
           a.depth + (b.depth - a.depth) * t,
           a.alpha + (b.alpha - a.alpha) * t
end

local function ease(t) return t < 0.5 and 4 * t * t * t or 1 - (-2 * t + 2) ^ 3 / 2 end

-----------------------------------------------------------------
-- carousel entities
-----------------------------------------------------------------

local function spawnSlot(key, variant, offset)
    local entity, hash = Util.spawnBag(key, variant, view.anchor - UP * 3.0)
    if not entity then return nil end
    FreezeEntityPosition(entity, true)
    SetEntityAlpha(entity, 0, false)

    local c, mn, mx = Util.modelCentre(hash)
    local bag = Bags.def(key)

    local item = {
        entity = entity, key = key, variant = variant,
        c = c, top = mx.z - c.z,
        turn = (bag and bag.shopHeading) or 0.0,
        from = offset, to = offset, o = offset, alpha = -1, yaw = 0.0,
    }
    live[#live + 1] = item
    return item
end

local function clearSlots()
    for _, it in ipairs(live) do Util.delete(it.entity) end
    live = {}
    anim = nil
end

--- Put an entity's MESH centre (not its far-off clothing pivot) at `p`.
local function place(it, p, heading)
    local r = math.rad(heading)
    local co, si = math.cos(r), math.sin(r)
    local c = it.c
    SetEntityCoordsNoOffset(it.entity,
        p.x - (c.x * co - c.y * si),
        p.y - (c.x * si + c.y * co),
        p.z - c.z, false, false, false)
    SetEntityHeading(it.entity, heading)
end

local function sendLabel()
    local centre
    for _, it in ipairs(live) do if it.to == 0 then centre = it end end
    if not centre then return end

    local point = view.anchor + UP * (centre.top + 0.07)
    local ok, x, y = GetScreenCoordFromWorldCoord(point.x, point.y, point.z)
    if ok then SendNUIMessage({ action = 'shopLabel', data = { x = x, y = y } }) end
end

--- Finish a running slide instantly (used when the player swaps fast).
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

--- Rebuild the whole row (opening, filters changed).
local function rebuild(prev, cur, nxt)
    clearSlots()
    -- rise from the counter; set first so nothing pops in while models load
    anim = { start = GetGameTimer(), duration = cfg.transitionTime or 420, rise = true }
    if cur then spawnSlot(cur.key, cur.variant, 0) end
    if cfg.sideBags then
        if prev then spawnSlot(prev.key, prev.variant, -1) end
        if nxt then spawnSlot(nxt.key, nxt.variant, 1) end
    end
    if anim then anim.start = GetGameTimer() end
end

--- Slide one step. dir = 1 moves to the next bag, -1 to the previous.
local function shift(dir, incoming)
    settle()
    for _, it in ipairs(live) do
        it.from = it.o
        it.to = it.o - dir
    end
    if incoming and cfg.sideBags then
        local it = spawnSlot(incoming.key, incoming.variant, dir * 2)
        if it then it.from, it.o, it.to = dir * 2, dir * 2, dir end
    end
    anim = { start = GetGameTimer(), duration = cfg.transitionTime or 420 }
    spinBoost = 0.0
end

local function setCentreVariant(key, variant)
    for i, it in ipairs(live) do
        if it.to == 0 and it.key == key then
            local model, texture = Bags.resolve(key, variant)
            local oldModel = Bags.resolve(key, it.variant)
            if model == oldModel then
                SetObjectTextureVariation(it.entity, texture or 0)
                it.variant = variant
            else
                Util.delete(it.entity)
                table.remove(live, i)
                local n = spawnSlot(key, variant, 0)
                if n then n.alpha = -1 end
            end
            return
        end
    end
end

-----------------------------------------------------------------
-- per-frame loop (only while open)
-----------------------------------------------------------------

local function frameLoop()
    local last = GetGameTimer()
    local speed = cfg.spinSpeed or 14.0

    while open do
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now

        HideHudAndRadarThisFrame()
        if cfg.depthOfField and mode == 'counter' then SetUseHiDof() end
        if mode == 'counter' then
            -- the camera stands where the customer is, so hide them for ourselves only
            SetLocalPlayerInvisibleLocally(true)
            SetEntityLocallyInvisible(PlayerPedId())
        end

        local spinRate = speed + spinBoost
        if spinBoost > 0 then spinBoost = math.max(0.0, spinBoost - 600.0 * dt) end
        local nudge = spinNudge
        spinNudge = 0.0

        local t = 1.0
        if anim then
            t = math.min(1.0, (now - anim.start) / anim.duration)
        end
        local e = ease(t)
        local bob = math.sin(now / 620.0) * 0.012

        for _, it in ipairs(live) do
            if anim and not anim.rise then it.o = it.from + (it.to - it.from) * e end
            local side, depth, alpha = slotAt(it.o)
            local weight = math.max(0.0, 1.0 - math.abs(it.o))

            local p = view.anchor + view.right * side + view.fwd * depth
            if weight > 0.0 then p = p + UP * (bob * weight) end
            if anim and anim.rise then
                p = p - UP * ((1.0 - e) * 0.18)
                alpha = alpha * e
            end

            -- the featured bag turns; one sliding away eases back to face the
            -- camera by the shortest way round instead of unwinding
            if weight > 0.5 then it.yaw = it.yaw + nudge end
            it.yaw = (it.yaw + spinRate * dt * weight) % 360.0
            if weight < 0.999 then
                local y = it.yaw > 180.0 and it.yaw - 360.0 or it.yaw
                it.yaw = (y * (1.0 - math.min(1.0, dt * 5.0 * (1.0 - weight)))) % 360.0
            end

            local heading = view.heading + it.turn + it.yaw - it.o * 24.0
            place(it, p, heading)

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
-- cameras
-----------------------------------------------------------------

local function makeCounterCam()
    counterCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        view.cam.x, view.cam.y, view.cam.z, 0.0, 0.0, 0.0, view.fov, false, 0)
    PointCamAtCoord(counterCam, view.anchor.x, view.anchor.y, view.anchor.z - 0.02)

    if cfg.depthOfField then
        local dist = #(view.anchor - view.cam)
        SetCamUseShallowDofMode(counterCam, true)
        SetCamNearDof(counterCam, 0.15)
        SetCamFarDof(counterCam, dist + 0.9)
        SetCamDofStrength(counterCam, 0.85)
    end
end

local function updateTryCam()
    if not tryCam then return end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local dist = cfg.previewDistance or 1.55
    local r = math.rad(tryHeading)
    SetCamCoord(tryCam, c.x - math.sin(r) * dist, c.y + math.cos(r) * dist, c.z + 0.25)
    PointCamAtCoord(tryCam, c.x, c.y, c.z + 0.15)
end

local function clearTryOn()
    Util.delete(tryProp)
    tryProp = nil
    Carry.stopPreview()
end

local function applyTryOn()
    clearTryOn()
    if not current then return end
    local ped = PlayerPedId()
    tryProp = Util.spawnBag(current.key, current.variant, GetEntityCoords(ped))
    if not tryProp then return end
    local bone, pos, rot = Bags.offset(current.key)
    Util.attach(tryProp, ped, bone, pos, rot)
    local pose = Bags.poseFor(current.key)
    if pose then Carry.preview(pose.key) end
end

local function setMode(m)
    if m == mode then return end
    local ped = PlayerPedId()

    if m == 'tryon' then
        tryHeading = (view.heading + 180.0) % 360.0
        pedTurn = 160.0
        SetEntityHeading(ped, (tryHeading + pedTurn) % 360.0)
        tryCam = tryCam or CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0, 0, 0, 0, 0, 0, cfg.previewFov or 34.0, false, 0)
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
    SendNUIMessage({ action = 'shopMode', data = { mode = m } })
end

-----------------------------------------------------------------
-- open / close
-----------------------------------------------------------------

local function closeShop()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shopClose' })

    clearTryOn()
    clearSlots()
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

    if SetWornPropVisible then SetWornPropVisible(true) end
    Carry.suspended = false
    mode = 'counter'
end

function OpenShop(location)
    if open then return end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return Config.Notify('Not while you are in a vehicle.', 'error')
    end

    local items = catalog()
    if #items == 0 then return Config.Notify('Nothing for sale here.', 'error') end

    view = buildView(location)

    -- request every model up front so swaps never wait on streaming
    for _, item in ipairs(items) do
        for _, m in ipairs(Bags.models(item.key)) do
            local h = joaat(m)
            if IsModelInCdimage(h) and not preloaded[h] then
                preloaded[h] = true
                RequestModel(h)
            end
        end
    end
    savedHeading = GetEntityHeading(ped)
    FreezeEntityPosition(ped, true)
    if SetWornPropVisible then SetWornPropVisible(false) end
    Carry.suspended = true

    makeCounterCam()
    SetCamActive(counterCam, true)
    RenderScriptCams(true, true, 900, true, true)

    open = true
    mode = 'counter'
    spinNudge = 0.0
    CreateThread(frameLoop)

    local wallet = lib.callback.await('nayzeee-backpack:shop:wallet', false)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'shopOpen',
        data = {
            items = items,
            owned = ownedMap(),
            wallet = wallet,
            themes = cfg.useThemes ~= false and cfg.Themes or nil,
            categories = cfg.useCategories ~= false and cfg.Categories or nil,
            useJobTab = cfg.useJobTab ~= false,
            jobTabLabel = cfg.jobTabLabel or 'Issued',
            currency = cfg.currency == 'bank' and 'Bank' or 'Cash',
            canSell = cfg.canSell,
            sellRate = cfg.sellRate,
            title = location and location.label or 'Bag Store',
        }
    })

    -- the label needs the camera to have arrived
    SetTimeout(950, sendLabel)
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

local function entryOf(t)
    if type(t) ~= 'table' or not Bags.exists(t.key) then return nil end
    return { key = t.key, variant = tonumber(t.variant) or Bags.defaultVariant(t.key) }
end

RegisterNUICallback('shopClose', function(_, cb) closeShop(); cb('ok') end)

-- Swaps are applied one at a time. If the player mashes the arrows while a
-- model is still loading, the backlog collapses into a single rebuild so the
-- row always ends up matching the UI.
local pending, working, collapsed = nil, false, false

local function applyView(data, forceRebuild)
    local prev, cur, nxt = entryOf(data.prev), entryOf(data.cur), entryOf(data.next)
    current = cur
    local dir = tonumber(data.dir) or 0

    if forceRebuild or dir == 0 or #live == 0 then
        rebuild(prev, cur, nxt)
    else
        shift(dir, dir > 0 and nxt or prev)
    end

    if mode == 'tryon' then applyTryOn() end
end

--- The UI owns the filtered list; it tells us what should be either side.
RegisterNUICallback('shopView', function(data, cb)
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

RegisterNUICallback('shopVariant', function(data, cb)
    cb('ok')
    if not current or data.key ~= current.key then return end
    current.variant = tonumber(data.variant)
    setCentreVariant(current.key, current.variant)
    if mode == 'tryon' then applyTryOn() end
end)

RegisterNUICallback('shopSpin', function(data, cb)
    cb('ok')
    local d = tonumber(data.delta) or 0.0
    if mode == 'tryon' then
        pedTurn = (pedTurn + d) % 360.0
        SetEntityHeading(PlayerPedId(), (tryHeading + pedTurn) % 360.0)
    else
        spinNudge = spinNudge + d
    end
end)

RegisterNUICallback('shopMode', function(data, cb)
    cb('ok')
    setMode(data.mode == 'tryon' and 'tryon' or 'counter')
end)

RegisterNUICallback('shopBuy', function(data, cb)
    cb('ok')
    TriggerServerEvent('nayzeee-backpack:buy', data.key, tonumber(data.variant))
end)

RegisterNUICallback('shopSell', function(data, cb)
    cb('ok')
    TriggerServerEvent('nayzeee-backpack:sell', data.key)
end)

RegisterNetEvent('nayzeee-backpack:shopResult', function(ok, msg, wallet)
    Config.Notify(msg, ok and 'success' or 'error')
    if ok then spinBoost = 720.0 end
    if open then
        SetTimeout(400, function()
            SendNUIMessage({ action = 'shopResult', data = { ok = ok, wallet = wallet, owned = ownedMap() } })
        end)
    end
end)

-----------------------------------------------------------------
-- world setup
-----------------------------------------------------------------

local wantsWorld = cfg.openMode ~= 'command'

CreateThread(function()
    if not wantsWorld then return end

    for _, loc in ipairs(cfg.Locations or {}) do
        if loc.blip then
            local blip = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(blip, loc.blip.sprite or 52)
            SetBlipColour(blip, loc.blip.color or 26)
            SetBlipScale(blip, loc.blip.scale or 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(loc.blip.label or 'Bag Store')
            EndTextCommandSetBlipName(blip)
        end

        if loc.ped then
            local hash = Util.loadModel(loc.ped)
            if hash then
                local ped = CreatePed(4, hash, loc.coords.x, loc.coords.y, loc.coords.z - 1.0,
                    loc.heading or 0.0, false, false)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetModelAsNoLongerNeeded(hash)
                shopPeds[#shopPeds + 1] = ped

                if Config.Prompts.useTarget and GetResourceState('ox_target') == 'started' then
                    exports.ox_target:addLocalEntity(ped, {{
                        name = 'nayzeee_bagshop',
                        label = 'Browse bags',
                        icon = 'fa-solid fa-bag-shopping',
                        distance = 2.5,
                        onSelect = function() OpenShop(loc) end,
                    }})
                end
            end
        end
    end
end)

-- markers for locations with no ped
CreateThread(function()
    if not wantsWorld then return end

    local anyMarker = false
    for _, loc in ipairs(cfg.Locations or {}) do
        if not loc.ped and loc.marker then anyMarker = true break end
    end
    if not anyMarker then return end

    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local sleep = 1200

        for _, loc in ipairs(cfg.Locations or {}) do
            if not loc.ped and loc.marker and not open then
                if #(coords - loc.coords) < 15.0 then
                    sleep = 0
                    local m = loc.marker
                    DrawMarker(m.type or 21, loc.coords.x, loc.coords.y, loc.coords.z + 0.6,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        m.scale or 0.6, m.scale or 0.6, m.scale or 0.6,
                        m.r or 8, m.g or 175, m.b or 162, m.a or 140,
                        true, true, 2, nil, nil, false)
                end
            end
        end

        Wait(sleep)
    end
end)

-- proximity prompt for markers, and for peds when ox_target is absent
CreateThread(function()
    if not wantsWorld then return end

    local hasTarget = Config.Prompts.useTarget and GetResourceState('ox_target') == 'started'
    local showing = false

    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local near = nil

        for _, loc in ipairs(cfg.Locations or {}) do
            local needsPrompt = (not hasTarget) or (not loc.ped)
            if needsPrompt and #(coords - loc.coords) < 2.5 then near = loc break end
        end

        if near and not open then
            if not showing then showing = true; lib.showTextUI('[E] Browse bags') end
            if IsControlJustPressed(0, 38) then
                lib.hideTextUI(); showing = false
                OpenShop(near)
            end
        elseif showing then
            showing = false; lib.hideTextUI()
        end

        Wait(near and 0 or 900)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if open then closeShop() end
    for _, ped in ipairs(shopPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end)

-----------------------------------------------------------------
-- command access
-----------------------------------------------------------------

if cfg.openMode == 'command' or cfg.openMode == 'both' then
    local name = cfg.command or 'bagstore'

    RegisterCommand(name, function()
        if open then return end
        OpenShop(nil)
    end, false)

    if cfg.keybind then
        RegisterKeyMapping(name, 'Open the bag store', 'keyboard', '')
    end
end
