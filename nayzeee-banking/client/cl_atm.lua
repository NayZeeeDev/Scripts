if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  ATMs
-- ═══════════════════════════════════════════════════════════

local pinPromise = nil
local cardProp, atStandby, inSession = nil, false, false
local inSessionAt = 0   -- when inSession was claimed, so a stuck claim heals itself
local promptShown = false   -- only ever hide the TextUI this file showed

local function destroyProp()
    if cardProp and DoesEntityExist(cardProp) then DeleteEntity(cardProp) end
    cardProp = nil
end

--- The card in the player's hand. A local prop: nobody else needs to see
--- a two-second gesture, and a networked one is one more thing to leak.
local function cardInHand()
    local cfg = Config.ATM.animation or {}
    if not cfg.cardProp then return end

    local model = joaat(cfg.cardProp)
    if not IsModelValid(model) or not pcall(lib.requestModel, model, 2500) then return end

    local ped = PlayerPedId()
    destroyProp()   -- never two: only the latest one would ever be cleaned up
    cardProp = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    AttachEntityToEntity(cardProp, ped, GetPedBoneIndex(ped, 28422),
        0.13, 0.02, 0.02, -90.0, 0.0, -75.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

--- A hand-forward gesture that exists on every build.
local function gesture(clip)
    local ped = PlayerPedId()
    local ok = pcall(lib.requestAnimDict, 'mp_common', 1500)
    if not ok or not HasAnimDictLoaded('mp_common') then return false end
    TaskPlayAnim(ped, 'mp_common', clip, 8.0, -8.0, -1, 48, 0, false, false, false)
    RemoveAnimDict('mp_common')
    return true
end

--- Face the machine and put the card in, then settle into an idle.
--- One card: it leaves the hand as the hand reaches the slot and carries
--- on into the reader. Blocks until the card is in, so the screen never
--- opens early.
function Bank.atmEnter(entity, model)
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

    atStandby = true   -- kept so exit knows an ATM session was running

    local insertMs = cfg.insertMs or 1700
    local reach = math.floor(insertMs * 0.45)   -- when the hand is at the slot

    cardInHand()
    gesture('givetake1_a')
    Wait(reach)

    destroyProp()
    if entity and model and DoesEntityExist(entity) then
        CreateThread(function() Bank.atmCardSlide(entity, model, 'in') end)
    end

    Wait(insertMs - reach)
    ClearPedTasks(ped)

    -- then stand at the machine. The scenario is used rather than a raw
    -- dict because it is guaranteed to exist on every game build.
    if cfg.idle ~= false then
        TaskStartScenarioInPlace(ped, 'PROP_HUMAN_ATM', 0, true)
    end
end

--- The card comes back out of the reader and waits at the slot, the hand
--- reaches for it and takes it, and the player steps away. `onCardOut`
--- runs once the card is showing (the screen mode hands the camera back
--- there). On a resource stop nothing here may wait.
--- Is the player free to play the walk-away? Not in a car (clearing tasks there
--- throws them out), not ragdolled, cuffed or being led away by someone.
function Bank.atmFree(ped)
    ped = ped or PlayerPedId()
    return not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped)
        and not IsPedCuffed(ped) and not IsEntityAttached(ped)
end

function Bank.atmExit(entity, model, onCardOut)
    destroyProp()

    local ped = PlayerPedId()
    local was = atStandby
    atStandby = false

    -- nothing may wait on a resource stop, and a player who is not free (dead,
    -- in a car, ragdolled, cuffed, escorted) plays no gestures and keeps their task
    if Bank.stopping or not Bank.atmFree(ped) then
        if onCardOut then onCardOut() end
        if was and Bank.atmFree(ped) then ClearPedTasksImmediately(ped) end
        return
    end

    local waiting
    local animate = (Config.ATM.animation or {}).enabled ~= false
    if was and animate and entity and model and DoesEntityExist(entity) then
        waiting = Bank.atmCardSlide(entity, model, 'out', true)
    end

    if onCardOut then onCardOut() end
    if not was then
        if waiting then Bank.atmDropProp(waiting) end
        return
    end

    ClearPedTasksImmediately(ped)
    if not animate then return end

    if gesture('givetake2_a') then
        Wait(380)                     -- the hand reaches the slot
        if waiting then Bank.atmDropProp(waiting) waiting = nil end
        cardInHand()                  -- and comes away with the card
        Wait(720)
        destroyProp()
        ClearPedTasks(ped)
    end

    if waiting then Bank.atmDropProp(waiting) end
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

    -- a server that doesn't answer means asking for the PIN, never skipping it
    local needed = lib.callback.await('nz_bank:pinRequired', false, card.id, nil)
    if needed == false then return true end

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

    -- the closest machine of any model that the player is stood in front of: a
    -- Fleeca wall unit behind the counter is near but faces the other way
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestModel, bestDist
    for _, m in ipairs(Config.ATMModels) do
        local found = GetClosestObjectOfType(pos.x, pos.y, pos.z,
            (Config.ATM.targetDistance or 2.5) + 1.0, m, false, false, false)

        if found ~= 0 and DoesEntityExist(found) then
            local ok, model = pcall(GetEntityModel, found)
            if ok and model and model ~= 0 then
                local d = #(pos - GetEntityCoords(found))
                local rel = GetOffsetFromEntityGivenWorldCoords(found, pos.x, pos.y, pos.z)
                -- the screen side is the machine's -Y; a little slack for standing to one side
                if rel.y < 0.25 and (not bestDist or d < bestDist) then
                    best, bestModel, bestDist = found, model, d
                end
            end
        end
    end
    if best then
        Bank.debug('the targeted ATM handle was no good; found it again by proximity')
        return best, bestModel
    end
end

--- More than one card on you: say which one goes in.
local function pickCard(cards)
    if #cards == 1 then return cards[1] end

    local picked, done = nil, false
    local options = {}
    for _, c in ipairs(cards) do
        options[#options + 1] = {
            title       = c.label,
            description = c.holder,
            icon        = 'credit-card',
            onSelect    = function() picked, done = c, true end
        }
    end

    lib.registerContext({
        id      = 'nz_bank_atm_cards',
        title   = L('atm_which_card'),
        options = options,
        onExit  = function() done = true end
    })
    lib.showContext('nz_bank_atm_cards')

    -- the menu can be closed or replaced by another resource without onExit
    -- running; waiting on it forever would leave every machine dead
    local deadline = GetGameTimer() + 60000
    Wait(250)
    while not done do
        if lib.getOpenContextMenu() ~= 'nz_bank_atm_cards' or GetGameTimer() > deadline then break end
        Wait(100)
    end
    if not done and lib.getOpenContextMenu() == 'nz_bank_atm_cards' then lib.hideContext(false) end
    return picked
end

--- A server answer with a time limit, so a reply that never comes cannot
--- leave the machine stuck as busy.
local function timed(name, ...)
    local args, result, finished = table.pack(...), nil, false
    CreateThread(function()
        result = lib.callback.await(name, false, table.unpack(args, 1, args.n))
        finished = true
    end)
    local limit = GetGameTimer() + (Config.ATM.timeoutSeconds or 10) * 1000
    while not finished and GetGameTimer() < limit do Wait(50) end
    return result
end

--- Reasons a player can't step up to a machine right now.
local function cantUse()
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedFatallyInjured(ped) then return L('atm_cant_now') end
    if IsPedInAnyVehicle(ped, false) then return L('atm_in_vehicle') end
    if IsPedRagdoll(ped) or IsPedCuffed(ped) then return L('atm_cant_now') end
    -- a claim much older than any start can take is a stuck one: let it go
    if inSession and GetGameTimer() - (inSessionAt or 0) > 90000 then inSession = false end
    if inSession or Bank.isOpen or Bank.atmClosing or (Bank.screenActive and Bank.screenActive()) then return 'busy' end
end

--- The machine the player is stood at, if any (for using a card item there).
function Bank.atmNearby()
    return resolveATM(nil) ~= nil
end

--- `cardId`: the card item the player used at the machine. It goes in
--- without asking which.
function Bank.useATM(targeted, cardId)
    local why = cantUse()
    if why then
        Bank.notify(L('atm_title'), why == 'busy' and L('atm_busy') or why, 'error')
        return
    end

    local entity, model = resolveATM(targeted)
    if not entity then return end
    inSession, inSessionAt = true, GetGameTimer()

    -- which card goes in: with physical cards, one you are carrying
    local card
    if Config.ATM.requireCard then
        local res = timed('nz_bank:atmCards') or {}
        local cards = res.cards or {}
        if #cards == 0 then
            inSession = false
            return Bank.notify(L('atm_title'), res.declined or (Config.Cards.physicalItem
                and L('atm_no_card_on') or L('no_card')), 'error')
        end
        if cardId then
            for _, c in ipairs(cards) do
                if c.id == tonumber(cardId) then card = c break end
            end
            if not card then
                inSession = false
                return Bank.notify(L('atm_title'), res.declined or L('atm_card_refused'), 'error')
            end
        else
            card = pickCard(cards)
        end
        if not card then inSession = false return end
    end

    -- the server checks we are at the machine and keeps the card until we leave
    local start = timed('nz_bank:atmStart', card and card.id, GetEntityCoords(entity))
    if not start or not start.ok then
        inSession = false
        return Bank.notify(L('atm_title'), start and start.msg or L('atm_no_answer'), 'error')
    end
    card = start.card or card

    local data = timed('nz_bank:getData', 'atm')
    -- an error comes back as { ok = false }, which is not an account to show
    if not data or not data.player or not DoesEntityExist(entity) then
        inSession = false
        lib.callback.await('nz_bank:atmEnd', false)
        return Bank.notify(L('atm_title'), data and L('atm_moved') or L('atm_bank_silent'), 'error')
    end

    -- The machine's own screen is the interface when it is on.
    -- Quietly dropping to a different one because the session
    -- could not start is more confusing than saying so.
    if Config.ATM.screen and Config.ATM.screen.enabled then
        -- still claimed while the screen spins up, so a second press can't start another
        local started = Bank.useATMScreen(entity, model, card, data)
        inSession = false
        if started then return end

        lib.callback.await('nz_bank:atmEnd', false)
        return Bank.notify(L('atm_title'), L('atm_busy'), 'error')
    end

    Bank.atmEntity, Bank.atmModel, Bank.atmCard = entity, model, card or true

    local entered, err = pcall(Bank.atmEnter, entity, model)
    if not entered then print('^1[nayzeee-banking]^7 ATM insert failed: ' .. tostring(err)) end

    if not pinGate(card, data.config and data.config.ui) then
        inSession = false
        return Bank.leaveATM()
    end

    inSession = false
    if Bank.openUI('atm') == false or not Bank.isOpen then Bank.leaveATM() end
end

--- Give the card back whenever the ATM closes, however it closes.
function Bank.leaveATM()
    local entity, model = Bank.atmEntity, Bank.atmModel
    Bank.atmEntity, Bank.atmModel = nil, nil
    -- busy from the very start of the walk-away, not only once it has played
    local holding = Bank.atmCard ~= nil
    if holding then Bank.atmClosing = true end

    local ok, err = pcall(Bank.atmExit, entity, model)
    if not ok then print('^1[nayzeee-banking]^7 ATM exit failed: ' .. tostring(err)) end

    if not Bank.atmCard then Bank.atmClosing = false return end
    Bank.atmCard = nil
    -- busy until the server has closed it, so a quick re-use is not wiped by this end
    Bank.atmClosing = true
    if not Bank.stopping then pcall(lib.callback.await, 'nz_bank:atmEnd', false) end
    Bank.atmClosing = false
end

-- ═══════════════════════════════════════════════════════════
--  REACHING A MACHINE
--  The target is used whenever it is actually running. If it is
--  missing, or starts after this resource, the key press covers
--  the gap until it arrives.
-- ═══════════════════════════════════════════════════════════
local targetActive = false

local function addTargets()
    if targetActive then return end

    if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        exports.ox_target:addModel(Config.ATMModels, {{
            name     = 'nz_bank_atm',
            icon     = 'fa-solid fa-credit-card',
            label    = L('atm_use'),
            distance = Config.ATM.targetDistance or 2.5,
            onSelect = function(data) Bank.useATM(data and data.entity) end
        }})
        targetActive = true

    elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
        exports['qb-target']:AddTargetModel(Config.ATMModels, {
            options = {{
                icon   = 'fa-solid fa-credit-card',
                label  = L('atm_use'),
                action = function(entity) Bank.useATM(entity) end
            }},
            distance = Config.ATM.targetDistance or 2.5
        })
        targetActive = true
    end
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == Config.Target then
        targetActive = false
        addTargets()
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == Config.Target then targetActive = false end
end)

--- Model-wide target options persist too, so drop ours on the way out.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        pcall(function() exports.ox_target:removeModel(Config.ATMModels, { 'nz_bank_atm' }) end)
    elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
        pcall(function() exports['qb-target']:RemoveTargetModel(Config.ATMModels, { L('atm_use') }) end)
    end

    if promptShown then lib.hideTextUI() promptShown = false end
    destroyProp()
end)

CreateThread(function()
    addTargets()

    -- key-press fallback, for as long as no target is running
    while true do
        local sleep = 900

        if targetActive then
            if promptShown then lib.hideTextUI() promptShown = false end
            sleep = 2000
        else
            local pos = GetEntityCoords(PlayerPedId())
            local found

            for _, model in ipairs(Config.ATMModels) do
                local obj = GetClosestObjectOfType(pos.x, pos.y, pos.z, 1.6, model, false, false, false)
                if obj ~= 0 then found = obj break end
            end

            if found and not Bank.isOpen and not inSession and not (Bank.screenActive and Bank.screenActive()) then
                sleep = 0
                if not promptShown then
                    lib.showTextUI(('[%s]  %s'):format(Config.OpenKey, L('atm_use')))
                    promptShown = true
                end
                if IsControlJustReleased(0, 38) then
                    lib.hideTextUI()
                    promptShown = false
                    Bank.useATM(found)
                end
            elseif promptShown then
                lib.hideTextUI()
                promptShown = false
            end
        end

        Wait(sleep)
    end
end)
