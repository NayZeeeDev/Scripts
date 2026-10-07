-----------------------------------------------------------------
-- Bag store
--
-- The bag is attached to the player's own character, not floated in
-- mid-air, so what they see is exactly how it will sit on them. The
-- camera frames them on the left with the catalogue on the right.
-----------------------------------------------------------------

if not Config.Shop or not Config.Shop.enabled then return end

local cfg = Config.Shop

local open       = false
local previewEnt = nil
local previewCam = nil
local currentKey = nil
local currentVariant = 0
local shopPeds   = {}

local savedHeading = nil
local pedHeading   = 0.0
local camDist      = 1.55
local camHeight    = 0.25

-----------------------------------------------------------------
-- helpers
-----------------------------------------------------------------

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then return nil end
    end
    return hash
end

--- Offset for a bag, falling back to the default.
local function bagOffset(bag)
    local d = Config.DefaultOffset
    local o = bag.offset
    if not o then return d.bone, d.pos, d.rot end
    return o.bone or d.bone, o.pos or d.pos, o.rot or d.rot
end

--- Every bag the player is allowed to see.
local function catalog()
    local list = {}

    for key, bag in pairs(Config.Backpacks) do
        if bag.price and (not bag.job or CanUseBag(bag)) then
            local storage = Config.GetStorage(key)
            local variants = {}

            if bag.variants then
                for idx, label in pairs(bag.variants) do
                    variants[#variants + 1] = { index = idx, label = label }
                end
                table.sort(variants, function(a, b) return a.index < b.index end)
            end

            local jobLabel
            if bag.job then
                jobLabel = type(bag.job) == 'table' and bag.job[1] or bag.job
            end

            list[#list + 1] = {
                key = key, label = bag.label or key, model = bag.model,
                category = bag.category or 'backpack',
                theme = bag.theme or 'realistic',
                price = bag.price,
                slots = storage.slots, weight = storage.weight,
                variants = variants, job = jobLabel,
            }
        end
    end

    table.sort(list, function(a, b) return a.price < b.price end)
    return list
end

-----------------------------------------------------------------
-- preview on the player
-----------------------------------------------------------------

local function clearPreview()
    if previewEnt and DoesEntityExist(previewEnt) then
        DetachEntity(previewEnt, true, true)
        DeleteEntity(previewEnt)
    end
    previewEnt = nil
end

local function showPreview(bagKey, variant)
    local bag = Config.Backpacks[bagKey]
    if not bag then return end

    clearPreview()

    local hash = loadModel(bag.model)
    if not hash then
        print(('^1[nayzeee-backpack] shop: model "%s" is not registered — check its .ytyp is declared with data_file DLC_ITYP_REQUEST^0'):format(bag.model))
        return
    end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)

    previewEnt = CreateObject(hash, c.x, c.y, c.z, false, false, false)
    SetEntityCollision(previewEnt, false, false)

    -- attach exactly how it would be worn, so the preview is honest
    local bone, pos, rot = bagOffset(bag)
    AttachEntityToEntity(
        previewEnt, ped, GetPedBoneIndex(ped, bone),
        pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(hash)

    currentKey = bagKey
    currentVariant = variant or 0
    if currentVariant > 0 then
        SetObjectTextureVariation(previewEnt, currentVariant)
    end
end

-----------------------------------------------------------------
-- camera
-----------------------------------------------------------------

local function updateCam()
    if not previewCam then return end

    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)

    -- the catalogue sits on the right, so push the camera sideways and the
    -- character lands in the clear left third of the screen
    local rad = math.rad(pedHeading)
    local shift = cfg.previewShift or 0.62

    local camX = c.x + math.sin(rad) * camDist + math.cos(rad) * shift
    local camY = c.y + math.cos(rad) * camDist - math.sin(rad) * shift
    local camZ = c.z + camHeight

    SetCamCoord(previewCam, camX, camY, camZ)
    PointCamAtCoord(previewCam, c.x, c.y, c.z + camHeight - 0.05)
end

local function startCam()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        c.x, c.y + camDist, c.z + camHeight, 0.0, 0.0, 0.0,
        cfg.previewFov or 34.0, false, 0)

    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 600, true, true)
    updateCam()
end

local function stopCam()
    if not previewCam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(previewCam, false)
    previewCam = nil
end

-----------------------------------------------------------------
-- backdrop
-----------------------------------------------------------------

local function setBackdrop(on)
    if on then
        if cfg.blurBackground ~= false then
            TriggerScreenblurFadeIn(500)
        end
        if cfg.timecycle then
            SetTimecycleModifier(cfg.timecycle)
            SetTimecycleModifierStrength(cfg.timecycleStrength or 0.7)
        end
    else
        if cfg.blurBackground ~= false then
            TriggerScreenblurFadeOut(400)
        end
        if cfg.timecycle then
            ClearTimecycleModifier()
        end
    end
end

-----------------------------------------------------------------
-- open / close
-----------------------------------------------------------------

local function closeShop()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shopClose' })

    clearPreview()
    stopCam()
    setBackdrop(false)

    local ped = PlayerPedId()
    if savedHeading then
        SetEntityHeading(ped, savedHeading)
        savedHeading = nil
    end

    FreezeEntityPosition(ped, false)

    -- show the bag they were already wearing again
    if SetWornPropVisible then SetWornPropVisible(true) end
end

function OpenShop(location)
    if open then return end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return Config.Notify('Not while you are in a vehicle.', 'error')
    end

    savedHeading = GetEntityHeading(ped)
    pedHeading = savedHeading
    camDist = cfg.previewDistance or 1.55

    FreezeEntityPosition(ped, true)

    -- hide the worn bag so the preview doesn't stack on top of it
    if SetWornPropVisible then SetWornPropVisible(false) end

    startCam()
    setBackdrop(true)

    local items = catalog()
    open = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'shopOpen',
        data = {
            items = items,
            themes = cfg.useThemes ~= false and cfg.Themes or nil,
            categories = cfg.useCategories ~= false and cfg.Categories or nil,
            showSearch = cfg.showSearch ~= false,
            useJobTab = cfg.useJobTab ~= false,
            jobTabLabel = cfg.jobTabLabel or 'Issued',
            myJob = Job and Job.name or nil,
            currency = cfg.currency,
            canSell = cfg.canSell,
            sellRate = cfg.sellRate,
            title = location and location.label or 'Bag Store',
        }
    })

    if items[1] then showPreview(items[1].key, 0) end
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

RegisterNUICallback('shopClose', function(_, cb) closeShop(); cb('ok') end)

RegisterNUICallback('shopSelect', function(data, cb)
    if data.key then showPreview(data.key, tonumber(data.variant) or 0) end
    cb('ok')
end)

RegisterNUICallback('shopVariant', function(data, cb)
    currentVariant = tonumber(data.index) or 0
    if previewEnt and DoesEntityExist(previewEnt) then
        SetObjectTextureVariation(previewEnt, currentVariant)
    end
    cb('ok')
end)

--- Spin the character. `delta` nudges, `absolute` sets outright for dragging.
RegisterNUICallback('shopRotate', function(data, cb)
    if data.absolute then
        pedHeading = (tonumber(data.absolute) or 0.0) % 360.0
    else
        pedHeading = (pedHeading + (tonumber(data.delta) or 0.0)) % 360.0
    end

    SetEntityHeading(PlayerPedId(), pedHeading)
    updateCam()
    cb('ok')
end)

RegisterNUICallback('shopZoom', function(data, cb)
    camDist = math.max(0.9, math.min(3.2, tonumber(data.distance) or camDist))
    updateCam()
    cb('ok')
end)

RegisterNUICallback('shopBuy', function(data, cb)
    TriggerServerEvent('nayzeee-backpack:buy', data.key, tonumber(data.variant) or 0)
    cb('ok')
end)

RegisterNUICallback('shopSell', function(data, cb)
    TriggerServerEvent('nayzeee-backpack:sell', data.key)
    cb('ok')
end)

RegisterNetEvent('nayzeee-backpack:shopResult', function(ok, msg)
    Config.Notify(msg, ok and 'success' or 'error')
    SendNUIMessage({ action = 'shopResult', data = { ok = ok } })
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
            local hash = loadModel(loc.ped)
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
            if not loc.ped and loc.marker then
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
