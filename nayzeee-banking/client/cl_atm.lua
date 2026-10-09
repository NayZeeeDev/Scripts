if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  ATMs
-- ═══════════════════════════════════════════════════════════

local pinPromise = nil
local animBase, cardProp, atStandby = nil, nil, false

--- GTA ships male and female ATM sets; pick the right one.
local function atmDicts()
    local ped = PlayerPedId()
    local male = IsPedMale(ped)
    return male and 'amb@prop_human_atm@male@' or 'amb@prop_human_atm@female@'
end

local function destroyProp()
    if cardProp and DoesEntityExist(cardProp) then DeleteEntity(cardProp) end
    cardProp = nil
end

--- Face the machine, put the card in, then settle into an idle.
--- Blocks until the insert is finished, so the pad never opens early.
function Bank.atmEnter(entity)
    -- default ON when the key is missing, so an older config still animates
    local cfg = Config.ATM.animation or {}
    if cfg.enabled == false then return end

    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    if entity and DoesEntityExist(entity) then
        local c = GetEntityCoords(entity)
        TaskTurnPedToFaceCoord(ped, c.x, c.y, c.z, 900)
        Wait(650)
    end

    animBase = atmDicts()   -- kept so exit knows an ATM session was running

    if cfg.cardProp then
        local model = joaat(cfg.cardProp)
        if lib.requestModel(model, 2500) then
            cardProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
            AttachEntityToEntity(cardProp, ped, GetPedBoneIndex(ped, 28422),
                0.13, 0.02, 0.02, -90.0, 0.0, -75.0, true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(model)
        end
    end

    -- the insert itself: a hand-forward gesture that exists on every build
    local ok = pcall(function() return lib.requestAnimDict('mp_common', 2500) end)
    if ok and HasAnimDictLoaded('mp_common') then
        TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, -1, 48, 0, false, false, false)
    end

    Wait(cfg.insertMs or 1700)
    destroyProp()
    ClearPedTasks(ped)

    -- then stand at the machine. The scenario is used rather than a raw
    -- dict because it is guaranteed to exist on every game build.
    if cfg.idle ~= false then
        TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
        atStandby = true
    end
end

--- Take the card back out and step away.
function Bank.atmExit()
    destroyProp()
    if not atStandby and not animBase then return end

    local ped = PlayerPedId()
    atStandby, animBase = false, nil

    ClearPedTasksImmediately(ped)

    -- a short take-the-card-back gesture on the way out
    local ok = pcall(function() return lib.requestAnimDict('mp_common', 1500) end)
    if ok and HasAnimDictLoaded('mp_common') then
        TaskPlayAnim(ped, 'mp_common', 'givetake2_a', 8.0, -8.0, -1, 48, 0, false, false, false)
        Wait(700)
        ClearPedTasks(ped)
    end
end

--- The keypad lives in the NUI, so it matches the rest of the UI.
RegisterNUICallback('pinResult', function(data, cb)
    SetNuiFocus(false, false)
    if pinPromise then
        pinPromise:resolve(data and data.ok or false)
        pinPromise = nil
    end
    cb(1)
end)

local function pinGate(card, ui)
    if not card then return true end

    local needed = lib.callback.await('nz_bank:pinRequired', false, card.id, nil)
    if not needed then return true end

    pinPromise = promise.new()

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'pinpad',
        data = {
            card       = card,
            ui         = ui,
            serverName = Config.ServerName,
            animation  = Config.ATM.padAnimation or 'vertical'
        }
    })

    return Citizen.Await(pinPromise)
end

--- Turn whatever the target handed us into a handle we can trust.
---
--- ox_target passes back what its raycast hit, and for a static map
--- object that can be a handle the engine reports as existing and then
--- crashes on when asked for its model. DoesEntityExist is not enough
--- of a check on its own. So the model read is guarded, and if it does
--- not come back clean the machine is found again by proximity, which
--- always yields a real handle.
local function resolveATM(entity)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        local ok, model = pcall(GetEntityModel, entity)
        if ok and model and model ~= 0 then
            for _, m in ipairs(Config.ATMModels) do
                if m == model then return entity, model end
            end
        end
    end

    local pos = GetEntityCoords(PlayerPedId())
    for _, m in ipairs(Config.ATMModels) do
        local found = GetClosestObjectOfType(pos.x, pos.y, pos.z,
            (Config.ATM.targetDistance or 2.5) + 1.0, m, false, false, false)

        if found ~= 0 and DoesEntityExist(found) then
            local ok, model = pcall(GetEntityModel, found)
            if ok and model and model ~= 0 then
                Bank.debug('the targeted ATM handle was no good; found it again by proximity')
                return found, model
            end
        end
    end
end

function Bank.useATM(targeted)
    local entity, model = resolveATM(targeted)
    if not entity then return end

    local data = lib.callback.await('nz_bank:getData', false, 'atm')
    if not data then return end
    if not DoesEntityExist(entity) then return end

    local card
    if Config.ATM.requireCard then
        for _, c in ipairs(data.cards or {}) do
            if c.account == data.primary and c.status == 'active' then card = c break end
        end
        if not card then
            return Bank.notify('ATM', 'You need an active bank card. Order one at any branch.', 'error')
        end

        -- the card leaves the inventory before anything else happens
        lib.callback.await('nz_bank:atmStart', false, card.id)

        if not DoesEntityExist(entity) then
            lib.callback.await('nz_bank:atmEnd', false)
            return Bank.notify('ATM', 'You moved away from the machine.', 'error')
        end

        -- The machine's own screen is the interface when it is on.
        -- Quietly dropping to a different one because the session
        -- could not start is more confusing than saying so.
        if Config.ATM.screen and Config.ATM.screen.enabled then
            if Bank.useATMScreen(entity, model, card, data) then return end

            lib.callback.await('nz_bank:atmEnd', false)
            return Bank.notify('ATM', 'That machine is still busy. Try again in a moment.', 'error')
        end

        Bank.atmEnter(entity)

        if not pinGate(card, data.config and data.config.ui) then
            Bank.atmExit()
            lib.callback.await('nz_bank:atmEnd', false)
            return
        end
    else
        Bank.atmEnter(entity)
    end

    Bank.atmCard = card
    Bank.openUI('atm')
end

--- Give the card back whenever the ATM closes, however it closes.
function Bank.leaveATM()
    Bank.atmExit()
    if not Bank.atmCard then return end
    Bank.atmCard = nil
    lib.callback.await('nz_bank:atmEnd', false)
end

--- Model-wide target options persist too, so drop ours on the way out.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeModel(Config.ATMModels, { 'nz_bank_atm' }) end)
    elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
        pcall(function() exports['qb-target']:RemoveTargetModel(Config.ATMModels, { 'Use ATM' }) end)
    end

    lib.hideTextUI()
end)

CreateThread(function()
    if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        exports.ox_target:addModel(Config.ATMModels, {{
            name     = 'nz_bank_atm',
            icon     = 'fa-solid fa-credit-card',
            label    = 'Use ATM',
            distance = Config.ATM.targetDistance or 2.5,
            onSelect = function(data) Bank.useATM(data and data.entity) end
        }})
        return

    elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetModel(Config.ATMModels, {
            options = {{
                icon   = 'fa-solid fa-credit-card',
                label  = 'Use ATM',
                action = function(entity) Bank.useATM(entity) end
            }},
            distance = Config.ATM.targetDistance or 2.5
        })
        return
    end

    -- key-press fallback
    while true do
        local sleep = 900
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local found

        for _, model in ipairs(Config.ATMModels) do
            local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, 1.6, model, false, false, false)
            if obj ~= 0 then found = obj break end
        end

        if found then
            sleep = 0
            lib.showTextUI(('[%s]  Use ATM'):format(Config.OpenKey))
            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                Bank.useATM(found)
            end
        else
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)
