--[[
    NZ Inventory UI - client
    Everything here is driven by NUI callbacks or events. There are no ticking
    threads, so idle resmon cost is 0.00ms.
]]

if not lib then return end

local config = NZConfig
local resource = GetCurrentResourceName()
local KVP_SETTINGS = 'nz_inventory:settings'

-------------------------------------------------------------------------------
-- settings / init payload
-------------------------------------------------------------------------------

local function loadSettings()
    local settings = {}

    for k, v in pairs(config.DefaultSettings) do settings[k] = v end

    local raw = GetResourceKvpString(KVP_SETTINGS)
    local ok, saved = pcall(json.decode, raw or '')

    if ok and type(saved) == 'table' then
        for k, v in pairs(saved) do
            if settings[k] ~= nil and type(v) == type(settings[k]) then settings[k] = v end
        end
    end

    return settings
end

local rarityCache

local function buildRarity()
    if rarityCache then return rarityCache end

    local map = {}

    for name, value in pairs(config.Rarity or {}) do map[name] = value end

    local ok, items = pcall(function() return exports[resource]:Items() end)

    if ok and type(items) == 'table' and next(items) then
        for name, item in pairs(items) do
            if type(item) == 'table' and type(item.rarity) == 'string' then
                map[name] = item.rarity
            end
        end

        rarityCache = map
    end

    return map
end

local function readyPayload()
    local card = config.PlayerCard

    return {
        config = {
            brandName = config.Brand.name,
            brandTagline = config.Brand.tagline,
            brandLogo = config.Brand.logo,
            playerCard = card.enabled,
            showBank = card.showBank,
            showJob = card.showJob,
            currency = card.currency,
            giveMenu = config.GiveMenu.enabled,
            clothing = config.Clothing.enabled,
            colors = config.Colors,
        },
        settings = loadSettings(),
        rarity = buildRarity(),
        strings = config.Strings,
    }
end

RegisterNUICallback('nz:ready', function(_, cb)
    cb(readyPayload())
end)

-- push once the ox UI reports it has loaded, in case nz:ready raced the script start
CreateThread(function()
    local timeout = GetGameTimer() + 60000

    while not (client and client.uiLoaded) do
        if GetGameTimer() > timeout then return end
        Wait(250)
    end

    SendNUIMessage({ action = 'nz:init', data = readyPayload() })
end)

RegisterNUICallback('nz:saveSettings', function(data, cb)
    cb(1)

    if type(data) == 'table' then
        SetResourceKvp(KVP_SETTINGS, json.encode(data))
    end
end)

-------------------------------------------------------------------------------
-- player card
-------------------------------------------------------------------------------

local headshot = { handle = nil, ped = nil, txd = nil, time = 0 }

local function releaseHeadshot()
    if headshot.handle then UnregisterPedheadshot(headshot.handle) end
    headshot = { time = 0 }
end

local function getHeadshot()
    if config.PlayerCard.avatar ~= 'headshot' then return end

    local ped = cache.ped
    local now = GetGameTimer()

    if headshot.txd and headshot.ped == ped and now - headshot.time < 60000 and IsPedheadshotValid(headshot.handle) then
        return headshot.txd
    end

    releaseHeadshot()

    local handle = RegisterPedheadshotTransparent(ped)
    local timeout = now + 2000

    while not IsPedheadshotReady(handle) or not IsPedheadshotValid(handle) do
        if GetGameTimer() > timeout then
            UnregisterPedheadshot(handle)
            return
        end

        Wait(20)
    end

    headshot = { handle = handle, ped = ped, txd = GetPedheadshotTxdString(handle), time = GetGameTimer() }

    return headshot.txd
end

local function getWallet()
    local ok, count = pcall(function() return exports[resource]:GetItemCount(config.PlayerCard.walletItem) end)
    return ok and count or 0
end

local serverInfo, serverInfoTime = nil, 0

RegisterNUICallback('nz:getPlayerInfo', function(_, cb)
    if not config.PlayerCard.enabled then return cb(false) end

    -- don't hit the server again for quick re-opens
    if not serverInfo or GetGameTimer() - serverInfoTime > 5000 then
        serverInfo = lib.callback.await('nz_inventory:playerInfo', false) or {}
        serverInfoTime = GetGameTimer()
    end

    local info = {
        name = serverInfo.name,
        bank = serverInfo.bank,
        job = serverInfo.job,
        grade = serverInfo.grade,
        id = cache.serverId,
        wallet = getWallet(),
    }

    local txd = getHeadshot()

    if txd then info.avatar = ('https://nui-img/%s/%s'):format(txd, txd) end

    cb(info)
end)

-- keep the wallet value live while the inventory is open
AddEventHandler('ox_inventory:updateInventory', function()
    if not config.PlayerCard.enabled then return end
    SendNUIMessage({ action = 'nz:wallet', data = getWallet() })
end)

-------------------------------------------------------------------------------
-- give menu
-------------------------------------------------------------------------------

RegisterNUICallback('nz:getNearbyPlayers', function(_, cb)
    local coords = GetEntityCoords(cache.ped)
    local nearby = lib.getNearbyPlayers(coords, config.GiveMenu.distance, false)
    local list = {}

    for i = 1, #nearby do
        local player = nearby[i]

        if IsEntityVisible(player.ped) then
            list[#list + 1] = {
                id = GetPlayerServerId(player.id),
                distance = #(coords - player.coords),
            }
        end
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)

    if config.GiveMenu.names == 'character' and #list > 0 then
        local ids = {}

        for i = 1, #list do ids[i] = list[i].id end

        local names = lib.callback.await('nz_inventory:names', false, ids) or {}

        for i = 1, #list do list[i].name = names[tostring(list[i].id)] end
    end

    cb(list)
end)

RegisterNUICallback('nz:giveTo', function(data, cb)
    cb(1)

    local target = tonumber(data?.target)
    local slot = tonumber(data?.slot)
    local count = tonumber(data?.count)

    if not target or not slot then return end

    local player = GetPlayerFromServerId(target)

    if player == -1 then return end

    local ped = GetPlayerPed(player)

    if #(GetEntityCoords(cache.ped) - GetEntityCoords(ped)) > config.GiveMenu.distance + 1.0 then return end

    exports[resource]:giveItemToTarget(target, slot, count)
end)

-------------------------------------------------------------------------------
-- clothing
-------------------------------------------------------------------------------

local clothing = config.Clothing
local cam
local saved = {}

local ANIMS = {
    head = { dict = 'mp_masks@standard_car@ds@', clip = 'put_on_mask', time = 800 },
    body = { dict = 'clothingtie', clip = 'try_tie_negative_a', time = 1200 },
    legs = { dict = 'random@domestic', clip = 'pickup_low', time = 1100 },
}

local PIECE_ANIM = {
    hat = 'head', glasses = 'head', ears = 'head', mask = 'head',
    neck = 'body', top = 'body', vest = 'body', bag = 'body', watch = 'body', bracelet = 'body',
    pants = 'legs', shoes = 'legs',
}

local function isFemale(ped)
    return GetEntityModel(ped) == `mp_f_freemode_01`
end

local function isWorn(ped, piece)
    if piece.prop then return GetPedPropIndex(ped, piece.prop) ~= -1 end

    return GetPedDrawableVariation(ped, piece.component) ~= piece.off[isFemale(ped) and 2 or 1]
end

local function clothingState()
    local ped = cache.ped
    local state = {}

    for name, piece in pairs(clothing.pieces) do state[name] = isWorn(ped, piece) end

    return state
end

local function playAnim(name)
    if not clothing.playAnimation or cache.vehicle then return end

    local anim = ANIMS[PIECE_ANIM[name] or 'body']

    if not pcall(lib.requestAnimDict, anim.dict, 1000) then return end

    TaskPlayAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, anim.time, 51, 0, false, false, false)
    RemoveAnimDict(anim.dict)
    Wait(math.floor(anim.time * 0.6))
end

local function togglePiece(name)
    local piece = clothing.pieces[name]

    if not piece then return end

    local ped = cache.ped
    local worn = isWorn(ped, piece)

    -- nothing to put back on
    if not worn and not saved[name] then return end

    playAnim(name)

    if piece.prop then
        if worn then
            saved[name] = { GetPedPropIndex(ped, piece.prop), GetPedPropTextureIndex(ped, piece.prop) }
            ClearPedProp(ped, piece.prop)
        else
            SetPedPropIndex(ped, piece.prop, saved[name][1], saved[name][2], true)
            saved[name] = nil
        end

        return
    end

    local gender = isFemale(ped) and 2 or 1

    if worn then
        local store = {}

        store[piece.component] = { GetPedDrawableVariation(ped, piece.component), GetPedTextureVariation(ped, piece.component) }
        SetPedComponentVariation(ped, piece.component, piece.off[gender], 0, 0)

        for component, off in pairs(piece.extra or {}) do
            store[component] = { GetPedDrawableVariation(ped, component), GetPedTextureVariation(ped, component) }
            SetPedComponentVariation(ped, component, off[gender], 0, 0)
        end

        saved[name] = store
    else
        for component, value in pairs(saved[name]) do
            SetPedComponentVariation(ped, component, value[1], value[2], 0)
        end

        saved[name] = nil
    end
end

local function openCamera()
    if cam or cache.vehicle then return end

    local ped = cache.ped
    local c = clothing.camera
    local pos = GetOffsetFromEntityInWorldCoords(ped, c.offset.x, c.offset.y, c.offset.z)
    local look = GetOffsetFromEntityInWorldCoords(ped, c.target.x, c.target.y, c.target.z)

    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, c.fov, false, 2)
    PointCamAtCoord(cam, look.x, look.y, look.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 450, true, true)
    TriggerScreenblurFadeOut(0)
end

local function closeCamera(reblur)
    if not cam then return end

    RenderScriptCams(false, true, 350, true, true)
    DestroyCam(cam, false)
    cam = nil

    if reblur and client?.screenblur then TriggerScreenblurFadeIn(250) end
end

RegisterNUICallback('nz:clothing', function(data, cb)
    if not clothing.enabled then return cb(false) end

    local action = data?.action

    if action == 'open' then
        openCamera()
        cb(clothingState())
    elseif action == 'close' then
        closeCamera(data.reblur)
        cb(1)
    elseif action == 'toggle' then
        togglePiece(data.piece)
        headshot.time = 0
        cb(clothingState())
    else
        cb(clothingState())
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end

    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
    end

    releaseHeadshot()
end)
