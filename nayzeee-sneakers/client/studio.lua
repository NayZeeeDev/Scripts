--[[
    Studio, client side.

    Every player: keeps the shoe list in step with the server's studio shoes (server/studio.lua),
    so shoes switched on in /sneakerstudio can be crafted, worn and sold straight away.

    Admins: /sneakerstudio. Their game scans every shoe drawable on the server (male and female
    freemode, every clothing pack), the server compares that with what it knows, and the studio
    window lists new and removed shoes. Picking a shoe shows it on a preview ped on a turntable.
]]

SneakerStudio = {}

local S = Config.Studio
local applied = {}      -- ids this client added to Config.ShoeModels
local lastScan          -- { base, drawables = { [key] = textures } }
local isOpen = false

-- ------------------------------------------------------------------ shoe list

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

CreateThread(function()
    SendNUIMessage({ action = 'init', propsResource = S.PropsResource })
    apply(lib.callback.await('nayzeee-sneakers:studio:shoes', false))
end)

-- ------------------------------------------------------------------ scanning

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

-- ------------------------------------------------------------------ preview ped

local preview = { ped = nil, gender = nil, spin = false }

local function previewSpot()
    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.3, 0.0)
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    return vector3(pos.x, pos.y, found and z or pos.z - 0.98), (GetEntityHeading(ped) + 180.0) % 360.0
end

local function previewCam()
    local ped = preview.ped
    local feet = GetEntityCoords(ped) - vector3(0.0, 0.0, 0.88)
    local me = GetEntityCoords(PlayerPedId())
    local toMe = vector3(me.x - feet.x, me.y - feet.y, 0.0)
    local len = math.max(0.01, #toMe)
    toMe = toMe / len
    local right = vector3(toMe.y, -toMe.x, 0.0)          -- the camera's right, looking at the ped
    local pos = feet + toMe * 1.25 + vector3(0.0, 0.0, 0.42)
    -- aim to the right of the feet so they sit in the left half, clear of the studio window
    Cam.Create(pos, feet + right * 0.42 + vector3(0.0, 0.0, 0.08), 42.0)
end

local function removePreview()
    preview.spin = false
    if preview.ped and DoesEntityExist(preview.ped) then DeleteEntity(preview.ped) end
    preview.ped, preview.gender = nil, nil
    Cam.Stop()
end

local function ensurePreview(gender)
    if preview.ped and preview.gender == gender and DoesEntityExist(preview.ped) then return preview.ped end
    if preview.ped and DoesEntityExist(preview.ped) then DeleteEntity(preview.ped) end
    local model = gender == 'female' and `mp_f_freemode_01` or `mp_m_freemode_01`
    if not LoadModel(model) then return nil end
    local spot, heading = previewSpot()
    local ped = CreatePed(4, model, spot.x, spot.y, spot.z, heading, false, false)
    SetModelAsNoLongerNeeded(model)
    SetPedDefaultComponentVariation(ped)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    preview.ped, preview.gender = ped, gender
    previewCam()
    if not preview.spin then
        preview.spin = true
        CreateThread(function()
            while preview.spin and preview.ped and DoesEntityExist(preview.ped) do
                SetEntityHeading(preview.ped, (GetEntityHeading(preview.ped) + 0.35) % 360.0)
                Wait(0)
            end
        end)
    end
    return ped
end

--- Puts a drawable on the preview ped. d = { gender, collection, index, texture } or a shoe key
function SneakerStudio.Preview(d)
    if type(d) ~= 'table' then return false end
    local ped = ensurePreview(d.gender == 'female' and 'female' or 'male')
    if not ped then return false end
    local drawable = Shoes.Drawable(ped, { collection = d.collection or '', index = tonumber(d.index) })
    if not drawable then return false end
    SetPedComponentVariation(ped, 6, drawable, tonumber(d.texture) or 0, 0)
    return true
end

-- ------------------------------------------------------------------ window

local function scanList()
    local out = {}
    if lastScan then for k, t in pairs(lastScan.drawables) do out[#out + 1] = { key = k, textures = t } end end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

local function send(data)
    if not data then return end
    data.scanList = scanList()
    SendNUIMessage({ action = 'studio', data = data })
end

local function close()
    if not isOpen then return end
    isOpen = false
    removePreview()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'studio', close = true })
    Busy = false
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

RegisterNetEvent('nayzeee-sneakers:client:studioOpen', function()
    if isOpen or Busy then return end
    isOpen, Busy = true, true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'studio', loading = true })
    local data = scanAndReport()
    if not data then return close() end
    send(data)
end)

RegisterNUICallback('studioClose', function(_, cb) cb('ok') close() end)

RegisterNUICallback('studioPreview', function(d, cb)
    cb({ ok = SneakerStudio.Preview(d) })
end)

RegisterNUICallback('studioSave', function(d, cb)
    local data = lib.callback.await('nayzeee-sneakers:studio:save', false, d.key, d.fields or {})
    if data then UI.Notify(Config.Text.studioSaved, 'success') end
    send(data)
    cb({ ok = data ~= nil })
end)

RegisterNUICallback('studioAdd', function(d, cb)
    local data = lib.callback.await('nayzeee-sneakers:studio:add', false, d.key)
    send(data)
    cb({ ok = data ~= nil })
end)

RegisterNUICallback('studioForget', function(d, cb)
    local data = lib.callback.await('nayzeee-sneakers:studio:forget', false, d.key)
    send(data)
    cb({ ok = data ~= nil })
end)

RegisterNUICallback('studioRescan', function(_, cb)
    cb('ok')
    SendNUIMessage({ action = 'studio', loading = true })
    send(scanAndReport())
end)

RegisterNUICallback('studioReload', function(_, cb)
    cb('ok')
    send(lib.callback.await('nayzeee-sneakers:studio:reload', false))
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if preview.ped and DoesEntityExist(preview.ped) then DeleteEntity(preview.ped) end
        if isOpen then SetNuiFocus(false, false) end
    end
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
