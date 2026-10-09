if BankLocked then return end

ESX = exports['es_extended']:getSharedObject()

Bank = { isOpen = false, context = 'bank', peds = {} }

--- Console noise, only when Config.Debug is on.
function Bank.debug(...)
    if not Config.Debug then return end
    print('^5[nayzeee-banking]^7', ...)
end

-- ═══════════════════════════════════════════════════════════
--  NUI BRIDGE
-- ═══════════════════════════════════════════════════════════
--- Only these server callbacks may be reached from the UI.
local ALLOWED = {
    ['nz_bank:getData']         = true,
    ['nz_bank:getTransactions'] = true,
    ['nz_bank:deposit']         = true,
    ['nz_bank:withdraw']        = true,
    ['nz_bank:transfer']        = true,
    ['nz_bank:createShared']    = true,
    ['nz_bank:getMembers']      = true,
    ['nz_bank:addMember']       = true,
    ['nz_bank:removeMember']    = true,
    ['nz_bank:setMemberPerms']  = true,
    ['nz_bank:renameAccount']   = true,
    ['nz_bank:closeShared']     = true,
    ['nz_bank:createCard']      = true,
    ['nz_bank:updateCard']      = true,
    ['nz_bank:verifyPin']       = true,
    ['nz_bank:pinRequired']     = true,
    ['nz_bank:reportCard']      = true,
    ['nz_bank:requestLoan']     = true,
    ['nz_bank:payLoan']         = true,
    ['nz_bank:payOffLoan']      = true,
    ['nz_bank:cancelLoan']      = true,
    ['nz_bank:settleDefault']   = true,
    ['nz_bank:openSavings']     = true,
    ['nz_bank:setSavingsGoal']  = true,
    ['nz_bank:payBill']         = true,
    ['nz_bank:issueBill']       = true,
    ['nz_bank:createScheduled'] = true,
    ['nz_bank:updateScheduled'] = true,
    ['nz_bank:saveSettings']    = true,
    ['nz_bank:changeNumber']    = true,
    ['nz_bank:atmStart']        = true,
    ['nz_bank:atmEnd']          = true,
    ['nz_bank:trade']           = true,
    ['nz_bank:getPayroll']      = true,
    ['nz_bank:setPayroll']      = true,
    ['nz_bank:payCard']         = true,
    ['nz_bank:getStatement']    = true,
    ['nz_bank:accountStatement']= true,
    ['nz_bank:setOverdraft']    = true,
    ['nz_bank:getPayees']       = true,
    ['nz_bank:savePayee']       = true,
    ['nz_bank:deletePayee']     = true
}

--- Settings that live on the client and never reach the server payload.
local function withClientConfig(data)
    if type(data) == 'table' and type(data.config) == 'table' then
        data.config.sounds = (Config.Sounds and Config.Sounds.enabled) and true or false
    end
    return data
end

RegisterNUICallback('request', function(data, cb)
    local name = data and data.name
    if not name or not ALLOWED[name] then return cb({ ok = false, msg = L('blocked_request') }) end
    local args = data.args or {}
    local res = lib.callback.await(name, false, table.unpack(args, 1, args.n or #args))
    if name == 'nz_bank:getData' then res = withClientConfig(res) end
    cb(res)
end)

--- Every notification in the resource goes through here.
function Bank.notify(title, description, kind)
    kind = kind or 'inform'

    if Config.Notify == 'custom' then
        local c = Config.CustomNotify or {}
        if c.export and c.export.resource and c.export.method then
            return exports[c.export.resource][c.export.method](nil, {
                title = title, description = description, type = kind
            })
        end
        if c.event then
            return TriggerEvent(c.event, { title = title, description = description, type = kind })
        end
    end

    if Config.Notify == 'esx' then
        return ESX.ShowNotification(('%s: %s'):format(title, description or ''))
    end

    lib.notify({ title = title, description = description, type = kind, position = 'top-right' })
end

RegisterNetEvent('nz_bank:notify', function(title, description, kind)
    Bank.notify(title, description, kind)
end)

RegisterNUICallback('notify', function(data, cb)
    Bank.notify(data.title, data.description, data.type)
    cb(1)
end)

RegisterNUICallback('close', function(_, cb)
    Bank.close()
    cb(1)
end)

--- Branches keep hours; ATMs do not care.
function Bank.branchOpen()
    local w = Config.WorkingHours
    if not w or not w.enabled then return true end

    local hour = GetClockHours()
    if w.openHour == w.closeHour then return true end

    if w.openHour < w.closeHour then
        return hour >= w.openHour and hour < w.closeHour
    end
    return hour >= w.openHour or hour < w.closeHour
end

--- Returns true only when the UI actually opened.
function Bank.openUI(context)
    if Bank.isOpen then return false end

    if context ~= 'atm' and not Bank.branchOpen() then
        Bank.notify(L('branch_closed'), L('branch_opens', Config.WorkingHours.openHour), 'error')
        return false
    end

    local data = lib.callback.await('nz_bank:getData', false, context or 'bank')

    -- A brand new character really is still being created. Anything
    -- else is the server failing to build the payload, and saying
    -- "still being set up" to someone who has banked for weeks sends
    -- them hunting in the wrong place — the console has the reason.
    if not data or not data.player then
        Bank.notify(L('bank_title'), L('bank_no_answer'), 'error')
        print('^1[nayzeee-banking]^7 nz_bank:getData came back empty. ' ..
              'Check the server console for the line above this one.')
        return false
    end

    Bank.isOpen = true
    Bank.context = context or 'bank'
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = withClientConfig(data) })
    return true
end

function Bank.close()
    if not Bank.isOpen then return end
    Bank.isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })

    if Bank.context == 'atm' and Bank.leaveATM then
        Bank.leaveATM()
    end
end

RegisterNetEvent('nz_bank:refresh', function()
    if not Bank.isOpen then return end
    local data = lib.callback.await('nz_bank:getData', false, Bank.context)
    if data then SendNUIMessage({ action = 'update', data = withClientConfig(data) }) end
end)

RegisterNetEvent('nz_bank:open', function(context)
    Bank.openUI(context)
end)

-- ESC handling is done in the UI; this is the fallback
CreateThread(function()
    while true do
        if Bank.isOpen then
            if IsControlJustReleased(0, 200) then Bank.close() end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  BRANCHES
-- ═══════════════════════════════════════════════════════════
local function spawnPed(model, coords)
    local hash = joaat(model)
    lib.requestModel(hash, 10000)

    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    SetModelAsNoLongerNeeded(hash)

    -- tag it, so a later run can find it wherever it ended up
    Entity(ped).state:set('nzBankTeller', true, false)

    return ped
end

local branchZones = {}       -- [bank index] = ox_target zone id or qb-target zone name
local branchesReady = false  -- tellers are spawned, targets can go on

--- The configured third-eye, but only if it is actually running.
--- Checked every time, so stopping it hands over to the key press.
local function targetActive()
    local t = Config.Target
    if t ~= 'ox_target' and t ~= 'qb-target' then return false end
    return GetResourceState(t) == 'started'
end

local function tellerOption(i) return 'nz_bank_teller_' .. i end

--- Every option name this resource can have put on a teller.
local function tellerOptions()
    local names = {}
    for i = 1, #Config.Banks do names[#names + 1] = tellerOption(i) end
    return names
end

--- "Open banking" goes on the teller, or on a small zone where the
--- marker stands when tellers are switched off.
local function addTargets()
    if not targetActive() then return end

    local label = L('target_open')
    local reach = Config.TargetDistance or 2.0
    local open  = function() Bank.openUI('bank') end

    for i, bank in ipairs(Config.Banks) do
        local ped = Bank.peds[i]
        local hasPed = ped and DoesEntityExist(ped)
        local at = vector3(bank.coords.x, bank.coords.y, bank.coords.z)

        local ok, err = pcall(function()
            if Config.Target == 'ox_target' then
                local options = {{
                    name     = tellerOption(i),
                    icon     = 'fa-solid fa-building-columns',
                    label    = label,
                    distance = reach,
                    onSelect = open
                }}
                if hasPed then
                    exports.ox_target:addLocalEntity(ped, options)
                else
                    branchZones[i] = exports.ox_target:addSphereZone({
                        coords = at, radius = 1.2, options = options
                    })
                end
            else
                local options = {
                    options  = {{ icon = 'fa-solid fa-building-columns', label = label, action = open }},
                    distance = reach
                }
                if hasPed then
                    exports['qb-target']:AddTargetEntity(ped, options)
                else
                    local name = 'nz_bank_branch_' .. i
                    exports['qb-target']:AddCircleZone(name, at, 1.2,
                        { name = name, debugPoly = false, useZ = true }, options)
                    branchZones[i] = name
                end
            end
        end)

        if not ok then
            print(('^3[nayzeee-banking]^7 %s refused the branch target: %s'):format(Config.Target, tostring(err)))
        end
    end
end

--- Target options outlive the entity they were attached to, so a restart
--- leaves an eye floating wherever the last ped stood. Clear them first.
--- Option names are always passed, so nobody else's options go with ours.
local function clearTargets()
    if targetActive() then
        local label = L('target_open')

        for i, ped in pairs(Bank.peds) do
            if DoesEntityExist(ped) then
                pcall(function()
                    if Config.Target == 'ox_target' then
                        exports.ox_target:removeLocalEntity(ped, { tellerOption(i) })
                    else
                        exports['qb-target']:RemoveTargetEntity(ped, { label })
                    end
                end)
            end
        end

        for _, zone in pairs(branchZones) do
            pcall(function()
                if Config.Target == 'ox_target' then
                    exports.ox_target:removeZone(zone)
                else
                    exports['qb-target']:RemoveZone(zone)
                end
            end)
        end
    end

    branchZones = {}
end

-- a target resource that (re)starts after us has none of our options
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= Config.Target or not branchesReady then return end
    branchZones = {}
    CreateThread(function()
        Wait(500)   -- let its exports register
        addTargets()
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    -- its zones went with it; the key press takes over on its own
    if resource == Config.Target then branchZones = {} end
end)

CreateThread(function()
    if Config.Blip.enabled then
        for _, bank in ipairs(Config.Banks) do
            local blip = AddBlipForCoord(bank.coords.x, bank.coords.y, bank.coords.z)
            SetBlipSprite(blip, Config.Blip.sprite)
            SetBlipColour(blip, Config.Blip.colour)
            SetBlipScale(blip, Config.Blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(Config.Blip.name)
            EndTextCommandSetBlipName(blip)
        end
    end

    if Config.SpawnPeds then
        Bank.sweepTellers()

        for i, bank in ipairs(Config.Banks) do
            Bank.peds[i] = spawnPed(bank.ped or 'ig_bankman', bank.coords)
        end
    end

    branchesReady = true
    addTargets()
end)

-- key press with a marker, whenever no target system is actually running
local textShown = false   -- only ever hide a TextUI this resource put up

CreateThread(function()
    while true do
        local sleep = 800
        local near = false
        local useKey = not targetActive() and not Bank.isOpen
        local pos = GetEntityCoords(PlayerPedId())

        for _, bank in ipairs(Config.Banks) do
            local dist = #(pos - vector3(bank.coords.x, bank.coords.y, bank.coords.z))
            if dist < 12.0 and not Config.SpawnPeds then
                -- a marker has to be drawn every frame or it flickers
                sleep = 0
                local m = Config.Marker
                DrawMarker(m.id, bank.coords.x, bank.coords.y, bank.coords.z - 0.95,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, m.scale, m.scale, m.scale,
                    m.color.r, m.color.g, m.color.b, m.color.a,
                    false, false, 2, false, nil, nil, false)
            end

            if useKey and dist < 2.5 then
                sleep = 0
                near = true
                if not textShown then
                    lib.showTextUI(L('textui_open', Config.OpenKey))
                    textShown = true
                end
                if IsControlJustReleased(0, 38) then
                    lib.hideTextUI()
                    textShown = false
                    Bank.openUI('bank')
                end
            elseif dist < 12.0 and sleep ~= 0 then
                sleep = 250
            end
        end

        if textShown and not near then
            lib.hideTextUI()
            textShown = false
        end
        Wait(sleep)
    end
end)

--- Using a card item shows what it is and who it belongs to.
--- ox_inventory: client = { export = 'nayzeee-banking.useCard' }
--- Stood at an ATM, using the card puts that card in the machine. Anywhere
--- else it shows whose card it is.
function Bank.useCardItem(meta)
    meta = meta or {}

    -- an item with no card id on it (an inventory without metadata) still opens
    -- the machine, which then asks which card
    if Bank.atmNearby and Bank.atmNearby() then
        return CreateThread(function() Bank.useATM(nil, meta.cardId) end)
    end

    if not meta.cardId then
        return Bank.notify(L('card_title'), L('card_blank'), 'error')
    end

    Bank.notify(meta.type or L('card_default'),
        ('%s · %s'):format(meta.holder or L('card_no_holder'), meta.account or ''), 'inform')
end

exports('useCard', function(data, slot)
    Bank.useCardItem(slot and slot.metadata)
end)

-- qs-inventory / the ESX usable-item route: the server hands over the item's info
RegisterNetEvent('nz_bank:useCardItem', function(meta) Bank.useCardItem(meta) end)

local LEGACY_REACH = 3.0   -- how far from a branch an untagged teller may stand and still be ours

--- Is this point next to a configured branch?
local function atBranch(pos)
    for _, bank in ipairs(Config.Banks) do
        if #(pos - vector3(bank.coords.x, bank.coords.y, bank.coords.z)) <= LEGACY_REACH then
            return true
        end
    end
    return false
end

--- Delete the tellers this resource spawned. Tagged peds are found by
--- their state bag wherever they stand. Older ones, from before the tag
--- existed, are matched on model and on being a mission entity — but only
--- right at a branch, so another resource's bank NPC elsewhere is left alone.
--- With a radius (/bankclean) the model match reaches that far around you.
function Bank.sweepTellers(radius)
    local me = GetEntityCoords(PlayerPedId())
    local models = {}
    for _, bank in ipairs(Config.Banks) do
        models[joaat(bank.ped or 'ig_bankman')] = true
    end
    models[joaat('ig_bankman')] = true
    models[joaat('u_m_m_bankman')] = true

    local removed = 0
    local names = tellerOptions()
    local label = L('target_open')

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local pos = GetEntityCoords(ped)
            local tagged = Entity(ped).state and Entity(ped).state.nzBankTeller
            local legacy = models[GetEntityModel(ped)] and IsEntityAMissionEntity(ped)
            local ours

            if radius then
                ours = (tagged or legacy) and #(pos - me) <= radius
            else
                ours = tagged or (legacy and atBranch(pos))
            end

            if ours then
                if GetResourceState('ox_target') == 'started' then
                    pcall(function() exports.ox_target:removeLocalEntity(ped, names) end)
                end
                if GetResourceState('qb-target') == 'started' then
                    pcall(function() exports['qb-target']:RemoveTargetEntity(ped, { label }) end)
                end

                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
                removed = removed + 1
            end
        end
    end

    return removed
end

--- One-off cleanup for ghosts left by an older build, which were never
--- tagged and may be standing at coordinates no longer in the config.
RegisterCommand('bankclean', function()
    local removed = Bank.sweepTellers(60.0)
    Bank.notify(L('banking_title'), L('tellers_cleared', removed, removed == 1 and '' or 's'),
        removed > 0 and 'success' or 'inform')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- cl_atm checks this and skips anything that would wait
    Bank.stopping = true
    local atATM = Bank.atmCard ~= nil or (Bank.isOpen and Bank.context == 'atm')

    -- Nothing here may yield: a Wait or a callback during a stop never
    -- comes back, so all of this runs before the ATM gets its turn.
    clearTargets()
    for _, ped in pairs(Bank.peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    Bank.sweepTellers()
    Bank.peds = {}

    if textShown then
        lib.hideTextUI()
        textShown = false
    end
    SetNuiFocus(false, false)
    -- only off the ATM idle; doing this in a car would throw the player out of it
    local ped = PlayerPedId()
    if atATM and not IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end

    -- last, because it waits on an animation and the server
    if Bank.leaveATM then Bank.leaveATM() end
end)
