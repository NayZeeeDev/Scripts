-----------------------------------------------------------------
-- Outfit bag (client)
--
-- Use the item: set it down (it opens by itself) or quick change
-- straight from your pockets. Save what you wear, wear a whole outfit
-- or one piece, hover to preview, pin, tag, share, undo.
--
-- Zero idle cost: the only loops run while a bag is on the ground
-- nearby or the menu is open.
-----------------------------------------------------------------

local cfg = Config.OutfitBag
if not cfg or not cfg.enabled then return end

local open = nil        -- { handle, entity?, isOwner } while the menu is up
local busy = false
local known = {}        -- [netId] = { entity, state } bags on the ground we know about
local myNetId = nil     -- our own bag on the ground
local undo = nil        -- what we wore before the last change
local watcher = false
local targetSystem = nil

local function notify(msg, kind) Config.Notify(msg, kind) end
local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end

-----------------------------------------------------------------
-- clothes
-----------------------------------------------------------------

local setHair = SetPedHairTint or SetPedHairColor

local function currentOutfit()
    local ped = PlayerPedId()
    local o = {}
    for name, id in pairs(cfg.components) do
        o[name] = { dId = GetPedDrawableVariation(ped, id), tId = GetPedTextureVariation(ped, id) }
    end
    for name, id in pairs(cfg.props) do
        local d = GetPedPropIndex(ped, id)
        if d ~= -1 then o[name] = { dId = d, tId = GetPedPropTextureIndex(ped, id) } end
    end
    if cfg.saveHair then
        o.hair = {
            dId = GetPedDrawableVariation(ped, 2), tId = GetPedTextureVariation(ped, 2),
            c = GetPedHairColor(ped), h = GetPedHairHighlightColor(ped),
        }
    end
    return o
end

local function applyPiece(ped, name, data)
    if name == 'hair' then
        if data then
            SetPedComponentVariation(ped, 2, data.dId, data.tId, 0)
            if data.c then setHair(ped, data.c, data.h or data.c) end
        end
        return
    end
    local comp, prop = cfg.components[name], cfg.props[name]
    if data and comp then
        SetPedComponentVariation(ped, comp, data.dId, data.tId, 0)
    elseif data and prop then
        SetPedPropIndex(ped, prop, data.dId, data.tId, true)
    elseif not data and prop then
        ClearPedProp(ped, prop)
    end
end

local function applyOutfit(ped, outfit, which)
    if which == 'all' then
        for name, id in pairs(cfg.props) do
            if outfit[name] == nil then ClearPedProp(ped, id) end
        end
        for name, data in pairs(outfit) do applyPiece(ped, name, data) end
    else
        applyPiece(ped, which, outfit[which])
    end
end

local function saveSkin()
    if not cfg.saveSkin then return end
    local ped = PlayerPedId()
    if GetResourceState('illenium-appearance') == 'started' then
        TriggerServerEvent('illenium-appearance:server:saveAppearance', exports['illenium-appearance']:getPedAppearance(ped))
    elseif GetResourceState('fivem-appearance') == 'started' then
        TriggerServerEvent('fivem-appearance:save', exports['fivem-appearance']:getPedAppearance(ped))
    elseif GetResourceState('qb-clothing') == 'started' then
        TriggerEvent('qb-clothing:client:saveOutfit')
    end
end

-----------------------------------------------------------------
-- preview ped (one pause-menu session per menu open)
-----------------------------------------------------------------

local previewPed, previewing = nil, false

local function startPreview()
    if previewing or not cfg.previewPed then return end
    local me = PlayerPedId()
    local c = GetEntityCoords(me)
    previewPed = CreatePed(4, GetEntityModel(me), c.x, c.y, c.z - 100.0, 0.0, false, false)
    if not previewPed or previewPed == 0 then previewPed = nil return end
    FreezeEntityPosition(previewPed, true)
    SetEntityInvincible(previewPed, true)
    SetEntityCollision(previewPed, false, false)
    SetBlockingOfNonTemporaryEvents(previewPed, true)
    ClonePedToTarget(me, previewPed)

    ReplaceHudColourWithRgba(117, 0, 0, 0, 0)
    SetFrontendActive(true)
    ActivateFrontendMenu(`FE_MENU_VERSION_EMPTY_NO_BACKGROUND`, false, -1)
    SetPauseMenuPedLighting(true)
    SetPauseMenuPedSleepState(true)
    previewing = true
end

local function showPreview(outfit)
    if not previewing then startPreview() end
    if not previewing then return end
    ClonePedToTarget(PlayerPedId(), previewPed)
    applyOutfit(previewPed, outfit, 'all')
    GivePedToPauseMenu(previewPed, cfg.previewSlot or 2)
end

local function hidePreview()
    if previewing then ClearPedInPauseMenu() end
end

local function endPreview()
    if not previewing then return end
    ClearPedInPauseMenu()
    SetPauseMenuPedLighting(false)
    SetPauseMenuPedSleepState(false)
    SetFrontendActive(false)
    if previewPed and DoesEntityExist(previewPed) then DeleteEntity(previewPed) end
    previewPed, previewing = nil, false
end

-----------------------------------------------------------------
-- menu
-----------------------------------------------------------------

local function closeMenu()
    if not open then return end
    open = nil
    endPreview()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'obClose' })
end

local function sendOpen(outfits, public, isOwner)
    local access = cfg.access or {}
    local wardrobe = cfg.wardrobe or {}
    SendNUIMessage({
        action = 'obOpen',
        data = {
            outfits = outfits or {},
            public = public == true,
            isOwner = isOwner,
            canSave = isOwner or access.othersCanSave == true,
            canCopy = not isOwner and access.othersCanCopy == true,
            canImport = (isOwner or access.othersCanSave) and wardrobe.enabled == true
                and GetResourceState('illenium-appearance') == 'started',
            canShare = cfg.sharing ~= false,
            maxOutfits = cfg.maxOutfits,
            maxLabel = cfg.maxLabelLength or 30,
            preview = cfg.previewPed ~= false,
            tags = cfg.tags or {},
            model = GetEntityModel(PlayerPedId()),
            quick = open and open.handle.slot ~= nil,
            undo = undo ~= nil,
        }
    })
end

--- Closes the menu when you die, get knocked down or walk off.
local function watchOpen(session)
    CreateThread(function()
        while open == session do
            local ped = PlayerPedId()
            local st = GetPlayerStatus(GetPlayerServerId(PlayerId()))
            local gone = st.dead or st.cuffed or IsPedRagdoll(ped)
            if not gone and session.entity then
                gone = not DoesEntityExist(session.entity)
                    or #(GetEntityCoords(ped) - GetEntityCoords(session.entity)) > (cfg.closeDistance or 5.0)
            end
            if gone then closeMenu() break end
            Wait(300)
        end
    end)
end

local function openPlaced(netId)
    if open or busy or IsEntityDead(PlayerPedId()) then return end
    local bag = known[netId]
    if not bag then return end
    local isOwner = bag.state.owner == GetPlayerServerId(PlayerId())
    if not isOwner and bag.state.public ~= true then return end

    open = { handle = { netId = netId }, entity = bag.entity, isOwner = isOwner, outfits = bag.state.outfits or {} }
    SetNuiFocus(true, true)
    sendOpen(open.outfits, bag.state.public, isOwner)
    watchOpen(open)
end

local function openQuick(slot)
    if open or busy or IsEntityDead(PlayerPedId()) then return end
    local data = lib.callback.await('nayzeee-backpack:outfit:slot', false, slot)
    if not data then return end
    open = { handle = { slot = slot }, isOwner = true, outfits = data.outfits or {} }
    SetNuiFocus(true, true)
    sendOpen(open.outfits, data.public, true)
    watchOpen(open)
end

-----------------------------------------------------------------
-- bags on the ground (statebag replication -> targets, live sync)
-----------------------------------------------------------------

local function cleanup(netId)
    local b = known[netId]
    if not b then return end
    known[netId] = nil
    if targetSystem == 'ox' then exports.ox_target:removeLocalEntity(b.entity)
    elseif targetSystem == 'qb' then exports['qb-target']:RemoveTargetEntity(b.entity) end
    if open and open.handle.netId == netId then closeMenu() end
    if myNetId == netId then myNetId = nil end
end

local function startWatcher()
    if watcher then return end
    watcher = true
    CreateThread(function()
        while next(known) do
            for netId, b in pairs(known) do
                if not DoesEntityExist(b.entity) then cleanup(netId) end
            end
            Wait(500)
        end
        watcher = false
    end)
end

local function pickup(netId)
    if busy then return end
    local b = known[netId]
    if not b then return end
    busy = true
    TaskTurnPedToFaceEntity(PlayerPedId(), b.entity, 500)
    local a = cfg.pickupAnim
    if lib.progressBar({
        duration = a.duration, label = S('ob_taking'), canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = a.dict, clip = a.clip, flag = a.flag },
    }) then
        lib.callback.await('nayzeee-backpack:outfit:pickup', false)
    end
    busy = false
end

local function addTarget(entity, netId)
    targetSystem = targetSystem
        or (GetResourceState('ox_target') == 'started' and 'ox')
        or (GetResourceState('qb-target') == 'started' and 'qb') or 'none'
    if targetSystem == 'none' then return end

    local me = GetPlayerServerId(PlayerId())
    local function canOpen()
        local b = known[netId]
        if not b then return false end
        return b.state.owner == me or ((cfg.access or {}).othersCanWear and b.state.public == true)
    end
    local function isMine()
        local b = known[netId]
        return b ~= nil and b.state.owner == me
    end

    if targetSystem == 'ox' then
        exports.ox_target:removeLocalEntity(entity)
        exports.ox_target:addLocalEntity(entity, {
            { name = 'nb_ob_open_' .. netId, icon = 'fa-solid fa-shirt', label = S('ob_open'),
              distance = cfg.interactDistance, canInteract = canOpen, onSelect = function() openPlaced(netId) end },
            { name = 'nb_ob_pickup_' .. netId, icon = 'fa-solid fa-hand', label = S('ob_pickup'),
              distance = cfg.interactDistance, canInteract = isMine, onSelect = function() pickup(netId) end },
        })
    else
        exports['qb-target']:RemoveTargetEntity(entity)
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                { icon = 'fa-solid fa-shirt', label = S('ob_open'), canInteract = canOpen, action = function() openPlaced(netId) end },
                { icon = 'fa-solid fa-hand', label = S('ob_pickup'), canInteract = isMine, action = function() pickup(netId) end },
            },
            distance = cfg.interactDistance,
        })
    end
end

AddStateBagChangeHandler('nb_outfitbag', nil, function(bagName, _, state)
    local netId = tonumber(bagName:match('entity:(%d+)'))
    if not netId then return end
    if state == nil then return cleanup(netId) end

    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 then return end

    local b = known[netId]
    local isNew = not b or b.entity ~= entity
    if isNew and b then cleanup(netId) end

    known[netId] = { entity = entity, state = state }
    if state.owner == GetPlayerServerId(PlayerId()) then myNetId = netId end
    startWatcher()
    if isNew then
        PlaceObjectOnGroundProperly(entity)
        addTarget(entity, netId)
    end

    if open and open.handle.netId == netId then
        if not open.isOwner and state.public ~= true then return closeMenu() end
        open.outfits = state.outfits or {}
        SendNUIMessage({ action = 'obSync', data = { outfits = state.outfits or {}, public = state.public == true } })
    end
end)

RegisterNetEvent('nayzeee-backpack:outfit:sync', function(outfits, public)
    if open and open.handle.slot then
        open.outfits = outfits or {}
        SendNUIMessage({ action = 'obSync', data = { outfits = outfits or {}, public = public } })
    end
end)

RegisterNetEvent('nayzeee-backpack:outfit:returned', function()
    myNetId = nil
end)

-----------------------------------------------------------------
-- using the item
-----------------------------------------------------------------

local function setDown(slot)
    local ped = PlayerPedId()
    if busy or myNetId or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        return notify(S('ob_cannot_place'), 'error')
    end

    busy = true
    local a = cfg.placeAnim
    local ok = lib.progressBar({
        duration = a.duration, label = S('ob_placing'), canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = { dict = a.dict, clip = a.clip, flag = a.flag },
    })
    if not ok then busy = false return end

    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local r = math.rad(h)
    local d = cfg.setDownDistance or 0.75
    local x, y = c.x - math.sin(r) * d, c.y + math.cos(r) * d
    local found, gz = GetGroundZFor_3dCoord(x, y, c.z, false)
    local netId = lib.callback.await('nayzeee-backpack:outfit:place', false,
        { x = x, y = y, z = found and gz or (c.z - 0.98), w = (h + 180.0) % 360.0 }, slot)
    busy = false

    if not netId then return notify(S('ob_cannot_place'), 'error') end

    if cfg.openOnPlace then
        -- wait for the prop + its statebag to reach us, then open
        local deadline = GetGameTimer() + 4000
        while not known[netId] and GetGameTimer() < deadline do Wait(50) end
        if known[netId] then openPlaced(netId) end
    end
end

local function useItem(slot)
    lib.registerContext({
        id = 'nayzeee_outfitbag_use',
        title = S('ob_title'),
        options = {
            { title = 'Set it down', description = 'Put the bag down and open it', icon = 'down-long',
              disabled = myNetId ~= nil, onSelect = function() setDown(slot) end },
            { title = 'Quick change', description = 'Open it right here, no set-down', icon = 'shirt',
              onSelect = function() openQuick(slot) end },
            Handoff and { title = Config.Prompts.handoff, description = 'Give it to the person closest to you, outfits and all',
              icon = 'hand-holding', onSelect = function() Handoff.offerNearest(slot) end } or nil,
        },
    })
    lib.showContext('nayzeee_outfitbag_use')
end

-- ox_inventory item: client = { export = 'nayzeee-backpack.useOutfitBag' }
exports('useOutfitBag', function(_, slot)
    useItem(type(slot) == 'table' and slot.slot or slot)
end)

-----------------------------------------------------------------
-- wearing
-----------------------------------------------------------------

local function wear(outfit, which, isUndo)
    if busy then return end
    busy = true
    local before = currentOutfit()

    local a = cfg.wearAnims[which] or cfg.wearAnims.all
    if a and not IsPedInAnyVehicle(PlayerPedId(), false) and Util.loadDict(a.dict) then
        TaskPlayAnim(PlayerPedId(), a.dict, a.clip, 3.0, 3.0, a.duration, a.flag, 0, false, false, false)
        Wait(math.floor(a.duration * 0.6)) -- change mid-animation, it reads naturally
    end

    applyOutfit(PlayerPedId(), outfit, which)
    saveSkin()

    undo = (not isUndo) and before or nil
    SendNUIMessage({ action = 'obUndo', data = { available = undo ~= nil } })
    notify(isUndo and S('ob_undone') or S('ob_changed'), 'success')
    busy = false
end

-----------------------------------------------------------------
-- NUI
-----------------------------------------------------------------

local function act(action, payload, cb)
    if not open then if cb then cb({ ok = false }) end return end
    local result = lib.callback.await('nayzeee-backpack:outfit:action', false, open.handle, action, payload or {})
    if result and result.msg then notify(result.msg, result.ok and 'success' or 'error') end
    if cb then cb(result or { ok = false }) end
end

RegisterNUICallback('ob:close', function(_, cb) cb('ok') closeMenu() end)

RegisterNUICallback('ob:save', function(d, cb)
    cb('ok')
    act('save', { label = d.label, outfit = currentOutfit(), model = GetEntityModel(PlayerPedId()) })
end)

RegisterNUICallback('ob:overwrite', function(d, cb)
    cb('ok')
    act('overwrite', { id = d.id, outfit = currentOutfit(), model = GetEntityModel(PlayerPedId()) })
end)

for _, name in ipairs({ 'rename', 'delete', 'favorite', 'tag', 'togglelock', 'copy', 'importcode' }) do
    RegisterNUICallback('ob:' .. name, function(d, cb)
        cb('ok')
        if name == 'delete' then hidePreview() end
        act(name, d)
    end)
end

-- the page copies the code itself and says so
RegisterNUICallback('ob:share', function(d, cb)
    if not open then return cb({}) end
    local r = lib.callback.await('nayzeee-backpack:outfit:action', false, open.handle, 'share', { id = d.id })
    cb({ code = r and r.code })
end)

RegisterNUICallback('ob:import', function(d, cb)
    cb('ok')
    act('import', { wardrobeId = tonumber(d.id) })
end)

RegisterNUICallback('ob:wardrobe', function(_, cb)
    cb({ outfits = lib.callback.await('nayzeee-backpack:outfit:wardrobe', false) or {} })
end)

local function entryFor(id)
    return open and open.outfits and open.outfits[id]
end

RegisterNUICallback('ob:wear', function(d, cb)
    cb('ok')
    local e = entryFor(d.id)
    if not e then return end
    if e.model and e.model ~= GetEntityModel(PlayerPedId()) then
        return notify(S('ob_wrong_model'), 'error')
    end
    hidePreview()
    wear(e.outfit, d.which or 'all')
end)

RegisterNUICallback('ob:undo', function(_, cb)
    cb('ok')
    if undo then
        hidePreview()
        wear(undo, 'all', true)
    end
end)

RegisterNUICallback('ob:preview', function(d, cb)
    cb('ok')
    local e = entryFor(d.id)
    if e and (not e.model or e.model == GetEntityModel(PlayerPedId())) then showPreview(e.outfit) end
end)

RegisterNUICallback('ob:unpreview', function(_, cb) hidePreview() cb('ok') end)

-----------------------------------------------------------------
-- lifecycle
-----------------------------------------------------------------

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    endPreview()
    if open then SetNuiFocus(false, false) end
end)
