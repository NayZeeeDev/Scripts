--[[
    Crafting at a table: the workbench menu, then the pair is made in stages
    at the table in first person. The shoes build up on the table top as the
    stages go, with a skill check on the fiddly ones.

    Also the supplier NPC who sells the materials.
]]

Crafting = {}

local C = Config.Crafting
local WORK = { Config.Tables.anim.dict, Config.Tables.anim.clip }
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
        if m.hidden then goto next end
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
        ::next::
    end
    table.sort(catalogue.models, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.label < b.label
    end)
    return catalogue
end

--- Shoes changed (the studio added or switched some): build the list again next time
function Crafting.Invalidate() catalogue = nil end

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

--- Walks to the work spot, then puts the player exactly on it (front and centre, facing the
--- table) and holds them there while they work
local function walkTo(stand, heading)
    local ped = PlayerPedId()
    TaskGoStraightToCoord(ped, stand.x, stand.y, stand.z, 1.0, 3000, heading, 0.05)
    local timeout = GetGameTimer() + 3000
    while #(GetEntityCoords(ped).xy - stand.xy) > 0.15 and GetGameTimer() < timeout do Wait(50) end
    ClearPedTasks(ped)
    local z = GetEntityCoords(ped).z
    SetEntityCoordsNoOffset(ped, stand.x, stand.y, z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
end

--- The three ways to shoot the work at a table. { pos, look, fov }
--- `work` is the middle of the table top, `out` points from it to the player.
local function tableShots(stand, work, along, out)
    local up = vector3(0.0, 0.0, 1.0)
    return {
        -- 3/4: high over your shoulder and off to the side, looking down on you and the whole table
        three = { work + out * 1.55 + along * 0.95 + up * 1.0, work + out * 0.12 + up * 0.04, 52.0 },
        -- first person: the game's own first-person camera, through your eyes
        first = 'native',
        -- close-up: low across the table, the shoes up front and your hands working behind them
        close = { work - out * 0.6 + along * 0.32 + up * 0.3, work + up * 0.07, 40.0 },
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
    local model = ShoeProp(shoe)
    if shoe and LoadModel(model) then
        obj = CreateObjectNoOffset(model, work.x, work.y, work.z, false, false, false)
        SetEntityHeading(obj, heading + 90.0)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
        SetEntityAlpha(obj, 0, false)
        SetModelAsNoLongerNeeded(model)
    end
    local shots = tableShots(stand, work, along, out)
    playWork()
    Views.Show(view, shots)

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
                -- a ghost of the pair that fills in stage by stage; solid when it's finished
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
    FreezeEntityPosition(PlayerPedId(), false)
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
