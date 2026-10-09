--[[
    Crafting at a table: the workbench menu, then the pair is made in stages
    at the table in first person. The shoes build up on the table top as the
    stages go, with a skill check on the fiddly ones.

    Also the supplier NPC who sells the materials.
]]

Crafting = {}

local C = Config.Crafting
local WORK = { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' }
local SCISSORS = `prop_cs_scissors`
local R_HAND = 28422

-- Everything the workbench shows, built once from the config
local catalogue
local function buildCatalogue()
    if catalogue then return catalogue end
    local function mats(recipe)
        local out = {}
        for name, count in pairs(recipe) do out[#out + 1] = { name = name, label = Shared.ItemLabel(name), count = count } end
        table.sort(out, function(a, b) return a.label < b.label end)
        return out
    end
    catalogue = { models = {}, realLevel = C.realLevel, stages = {} }
    for box, list in pairs(C.stages) do
        local out = {}
        for i, st in ipairs(list) do out[i] = { label = st.label, check = C.skillChecks and st.check and true or false } end
        catalogue.stages[box] = out
    end
    for id, m in pairs(Config.ShoeModels) do
        local colours = {}
        for letter, name in pairs(m.colourways) do
            colours[#colours + 1] = { letter = letter, name = name, image = ('nzs_%s_%s'):format(id, letter) }
        end
        table.sort(colours, function(a, b) return a.letter < b.letter end)
        local time = 0
        for _, s in ipairs(Config.Crafting.stages[m.box] or Config.Crafting.stages.shoe) do time = time + s.time end
        catalogue.models[#catalogue.models + 1] = {
            id = id, label = m.label, gender = m.gender, box = m.box,
            boxLabel = Config.BoxTypes[m.box] and Config.BoxTypes[m.box].label or '',
            level = Shared.ModelLevel(id),
            colours = colours,
            sizes = Config.Sizes[m.gender == 'female' and 'female' or 'male'],
            fake = mats(Shared.Recipe(id, false)),
            real = mats(Shared.Recipe(id, true)),
            stages = #(Config.Crafting.stages[m.box] or Config.Crafting.stages.shoe),
            time = time,
        }
    end
    table.sort(catalogue.models, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.label < b.label
    end)
    return catalogue
end

-- Workbench menu ----------------------------------------------------------------

local benchEnt

function Crafting.Open(ent)
    if Busy then return end
    local id = Tables.FromEntity(ent)
    if not id then return end
    local data = lib.callback.await('nayzeee-sneakers:craftData', false)
    if not data then return end
    benchEnt = ent
    SetNuiFocus(true, true)
    local views
    if Config.Camera.Switch and Config.FirstPerson then
        views = { current = Views.Get(), label = Config.Text.camera, list = {} }
        for _, v in ipairs(Views.order) do views.list[#views.list + 1] = { id = v, label = Views.Label(v) } end
    end
    SendNUIMessage({ action = 'bench', data = data, catalogue = buildCatalogue(), speedPerLevel = C.speedPerLevel, views = views })
end

RegisterNUICallback('benchClose', function(_, cb)
    cb('ok')
    SetNuiFocus(false, false)
    benchEnt = nil
end)

RegisterNUICallback('craft', function(req, cb)
    cb('ok')
    SetNuiFocus(false, false)
    local ent = benchEnt
    benchEnt = nil
    if ent and DoesEntityExist(ent) then
        CreateThread(function() Crafting.Run(ent, req) end)
    end
end)

RegisterNetEvent('nayzeee-sneakers:client:xp', function(info)
    SendNUIMessage({ action = 'xp', data = info })
    if info.gained > 0 then UI.Notify(Config.Text.xpGained:format(info.gained), 'success') end
    if info.levelUp then UI.Notify(Config.Text.levelUp:format(info.level), 'success') end
end)

-- Making a pair -----------------------------------------------------------------

local function playWork()
    if not LoadAnimDict(WORK[1]) then return end
    TaskPlayAnim(PlayerPedId(), WORK[1], WORK[2], 3.0, -3.0, -1, 1, 0.0, false, false, false)
end

local function holdScissors()
    if not LoadModel(SCISSORS) then return end
    local ped = PlayerPedId()
    local obj = CreateObject(SCISSORS, 0.0, 0.0, 0.0, false, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, R_HAND), 0.04, 0.0, -0.01, 0.0, 90.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(SCISSORS)
    return obj
end

local function walkTo(stand, heading)
    local ped = PlayerPedId()
    TaskGoStraightToCoord(ped, stand.x, stand.y, stand.z, 1.0, 3000, heading, 0.05)
    local timeout = GetGameTimer() + 3000
    while #(GetEntityCoords(ped).xy - stand.xy) > 0.25 and GetGameTimer() < timeout do Wait(50) end
    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
end

--- The three ways to shoot the work at a table. { pos, look, fov }
local function tableShots(stand, work, along, out)
    local ped = PlayerPedId()
    local eye = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0) + GetEntityForwardVector(ped) * 0.14 + vector3(0.0, 0.0, 0.03)
    local up = vector3(0.0, 0.0, 1.0)
    return {
        -- 3/4: over your shoulder, a step back and to the side, so you see yourself and the whole table
        three = { stand + along * 1.45 + out * 0.6 + up * 1.7, work - along * 0.05 + up * 0.06, 50.0 },
        -- first person: your own eyes, looking down at your hands
        first = { eye, work + up * 0.06, 48.0 },
        -- close-up: low across the table from the far side, the shoes up front and you working behind them
        close = { work - out * 0.42 + along * 0.28 + up * 0.2, work + up * 0.07, 40.0 },
    }
end

local function cancelPressed()
    return IsControlJustPressed(0, 73) or IsControlJustPressed(0, 177)   -- X / Backspace
end

function Crafting.Run(ent, req)
    if Busy then return end
    local tableId = Tables.FromEntity(ent)
    if not tableId then return end
    local ok, token, stages = lib.callback.await('nayzeee-sneakers:craftStart', false, tableId, {
        model = req.model, letter = req.letter, size = req.size, real = req.real == true,
    })
    if not ok then return end
    Busy = true

    local stand, work, heading, along, out = Tables.WorkSpot(ent)
    walkTo(stand, heading)
    local view = req.view
    if not Config.Camera.Switch or (view ~= 'three' and view ~= 'first' and view ~= 'close') then view = Views.Get() end
    Views.Set(view)

    -- the pair builds up on the table as the stages go
    local shoe = Config.Shoes[('%s_%s'):format(req.model, req.letter)]
    local obj
    if shoe and LoadModel(shoe.prop) then
        obj = CreateObjectNoOffset(shoe.prop, work.x, work.y, work.z, false, false, false)
        SetEntityHeading(obj, heading + 90.0)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
        SetEntityAlpha(obj, 0, false)
        SetModelAsNoLongerNeeded(shoe.prop)
    end
    local shots = tableShots(stand, work, along, out)
    local s = shots[view]
    Cam.Shot(s[1], s[2], s[3])
    playWork()

    local results, cancelled = {}, false
    for i, st in ipairs(stages) do
        local tool = st.anim == 'cut' and holdScissors() or nil
        UI.Progress({ label = st.label, step = i, steps = #stages, time = st.time,
                      hint = Config.Camera.Switch and Config.Text.craftHintView or Config.Text.craftHint })
        local t0 = GetGameTimer()
        while GetGameTimer() - t0 < st.time do
            Wait(0)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            if obj then
                local f = ((i - 1) + (GetGameTimer() - t0) / st.time) / #stages
                SetEntityAlpha(obj, math.floor(25 + 210 * f), false)
            end
            if cancelPressed() then cancelled = true break end
            view = Views.Poll(view, shots)
            if not IsEntityPlayingAnim(PlayerPedId(), WORK[1], WORK[2], 3) then playWork() end
        end
        UI.Progress(nil)
        if tool then DeleteEntity(tool) end
        if cancelled then break end
        if st.check then
            results[i] = lib.skillCheck(st.check) == true
            UI.Notify(results[i] and Config.Text.checkPassed or Config.Text.checkFailed, results[i] and 'success' or 'warning')
        end
    end

    if cancelled then
        lib.callback.await('nayzeee-sneakers:craftCancel', false)
        UI.Notify(Config.Text.craftCancelled, 'inform')
    else
        local done, info = lib.callback.await('nayzeee-sneakers:craftFinish', false, token, results)
        if done and info then
            if obj then ResetEntityAlpha(obj) end
            UI.Result({
                name = info.name, real = info.real, quality = info.quality,
                passed = info.passed, checks = info.checks, image = shoe and shoe.image,
            })
            Wait(1800)
        end
    end

    if obj then DeleteEntity(obj) end
    Cam.Stop()
    ClearPedTasks(PlayerPedId())
    RemoveAnimDict(WORK[1])
    Busy = false
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and benchEnt then SetNuiFocus(false, false) end
end)

-- Supplier ----------------------------------------------------------------------

local S = Config.Supplier
local supplierPed

local function shopItems()
    local out = {}
    for name, m in pairs(Shared.SupplierGoods()) do
        out[#out + 1] = { name = name, label = m.label, price = m.price, level = m.level or 1 }
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.price < b.price
    end)
    return out
end

local function openShop()
    if Busy then return end
    local data = lib.callback.await('nayzeee-sneakers:supplierData', false)
    if not data then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'shop', shop = {
        title = S.label, money = data.money, level = data.level, account = S.account,
        max = S.maxPerItem, items = shopItems(),
    } })
end

RegisterNUICallback('buy', function(d, cb)
    local ok, spent, money = lib.callback.await('nayzeee-sneakers:buy', false, d.cart or {})
    if ok then UI.Notify(Config.Text.bought:format(spent), 'success') end
    cb({ ok = ok == true, money = money })
end)

RegisterNUICallback('shopClose', function(_, cb)
    cb('ok')
    SetNuiFocus(false, false)
end)

local function spawnSupplier()
    if not LoadModel(S.ped) then return end
    local c = S.coords
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    supplierPed = CreatePed(4, S.ped, c.x, c.y, found and z or c.z - 1.0, c.w, false, false)
    SetEntityInvincible(supplierPed, true)
    SetBlockingOfNonTemporaryEvents(supplierPed, true)
    FreezeEntityPosition(supplierPed, true)
    TaskStartScenarioInPlace(supplierPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(S.ped)
    Target.AddEntity(supplierPed, {
        { name = 'nzs_supplier', label = Config.Text.browseSupplies, icon = 'fa-solid fa-box-open', onSelect = openShop },
    }, 2.5)
end

if S.enabled then
    CreateThread(function()
        if S.blip then
            local b = AddBlipForCoord(S.coords.x, S.coords.y, S.coords.z)
            SetBlipSprite(b, S.blip.sprite)
            SetBlipColour(b, S.blip.colour)
            SetBlipScale(b, S.blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(S.label)
            EndTextCommandSetBlipName(b)
        end
        while true do
            local near = #(GetEntityCoords(PlayerPedId()) - S.coords.xyz) < 80.0
            if near and not supplierPed then spawnSupplier()
            elseif not near and supplierPed then DeleteEntity(supplierPed) supplierPed = nil end
            Wait(1500)
        end
    end)

    AddEventHandler('onResourceStop', function(res)
        if res == GetCurrentResourceName() and supplierPed then DeleteEntity(supplierPed) end
    end)
end
