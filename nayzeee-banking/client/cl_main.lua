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
    ['nz_bank:setOverdraft']    = true
}

RegisterNUICallback('request', function(data, cb)
    local name = data and data.name
    if not name or not ALLOWED[name] then return cb({ ok = false, msg = 'Blocked request.' }) end
    local args = data.args or {}
    cb(lib.callback.await(name, false, table.unpack(args, 1, args.n or #args)))
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

function Bank.openUI(context)
    if Bank.isOpen then return end

    if context ~= 'atm' and not Bank.branchOpen() then
        return Bank.notify('Bank closed',
            ('The branch opens at %02d:00.'):format(Config.WorkingHours.openHour), 'error')
    end

    local data = lib.callback.await('nz_bank:getData', false, context or 'bank')

    -- A brand new character really is still being created. Anything
    -- else is the server failing to build the payload, and saying
    -- "still being set up" to someone who has banked for weeks sends
    -- them hunting in the wrong place — the console has the reason.
    if not data or not data.player then
        Bank.notify('Bank',
            'The bank did not answer. Try again in a moment — if it keeps happening, the server console says why.',
            'error')
        print('^1[nayzeee-banking]^7 nz_bank:getData came back empty. ' ..
              'Check the server console for the line above this one.')
        return
    end

    Bank.isOpen = true
    Bank.context = context or 'bank'
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data })
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
    if data then SendNUIMessage({ action = 'update', data = data }) end
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

    if not Config.SpawnPeds then return end

    Bank.sweepTellers()

    for i, bank in ipairs(Config.Banks) do
        local ped = spawnPed(bank.ped or 'ig_bankman', bank.coords)
        Bank.peds[i] = ped

        if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
            exports.ox_target:addLocalEntity(ped, {{
                name     = 'nz_bank_teller_' .. i,
                icon     = 'fa-solid fa-building-columns',
                label    = 'Open banking',
                distance = Config.TargetDistance or 2.0,
                onSelect = function() Bank.openUI('bank') end
            }})

        elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
            exports['qb-target']:AddTargetEntity(ped, {
                options = {{
                    icon   = 'fa-solid fa-building-columns',
                    label  = 'Open banking',
                    action = function() Bank.openUI('bank') end
                }},
                distance = Config.TargetDistance or 2.0
            })
        end
    end
end)

-- key-press fallback with a marker, when no target system is in use
if Config.Target ~= 'ox_target' and Config.Target ~= 'qb-target' then
    CreateThread(function()
        while true do
            local sleep = 800
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            for _, bank in ipairs(Config.Banks) do
                local dist = #(pos - vector3(bank.coords.x, bank.coords.y, bank.coords.z))
                if dist < 12.0 and not Config.SpawnPeds then
                    local m = Config.Marker
                    DrawMarker(m.id, bank.coords.x, bank.coords.y, bank.coords.z - 0.95,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, m.scale, m.scale, m.scale,
                        m.color.r, m.color.g, m.color.b, m.color.a,
                        false, false, 2, false, nil, nil, false)
                end

                if dist < 2.5 then
                    sleep = 0
                    lib.showTextUI(('[%s]  Open banking'):format(Config.OpenKey))
                    if IsControlJustReleased(0, 38) then
                        lib.hideTextUI()
                        Bank.openUI('bank')
                    end
                elseif dist < 12.0 then
                    sleep = 250
                end
            end

            if sleep ~= 0 then lib.hideTextUI() end
            Wait(sleep)
        end
    end)
end

--- Using a card item shows what it is and who it belongs to.
--- ox_inventory: client = { export = 'nayzeee-banking.useCard' }
exports('useCard', function(data, slot)
    local meta = slot and slot.metadata or {}
    if not meta.cardId then
        return Bank.notify('Card', 'This card has no details on it.', 'error')
    end
    Bank.notify(meta.type or 'Bank card',
        ('%s · %s'):format(meta.holder or 'Unknown holder', meta.account or ''), 'inform')
end)

--- Target options outlive the entity they were attached to, so a restart
--- leaves an eye floating wherever the last ped stood. Clear them first.
local function clearTargets()
    for i, ped in pairs(Bank.peds) do
        if DoesEntityExist(ped) then
            if Config.Target == 'ox_target' and GetResourceState('ox_target') == 'started' then
                pcall(function()
                    exports.ox_target:removeLocalEntity(ped, { 'nz_bank_teller_' .. i })
                end)
            elseif Config.Target == 'qb-target' and GetResourceState('qb-target') == 'started' then
                pcall(function()
                    exports['qb-target']:RemoveTargetEntity(ped, { 'Open banking' })
                end)
            end
        end
    end
end

--- Delete every teller this resource has ever spawned, wherever it stands.
--- Tagged peds are found by their state bag; older ones, from before the tag
--- existed, are matched on model and on being a mission entity.
function Bank.sweepTellers(radius)
    local me = GetEntityCoords(PlayerPedId())
    local models = {}
    for _, bank in ipairs(Config.Banks) do
        models[joaat(bank.ped or 'ig_bankman')] = true
    end
    models[joaat('ig_bankman')] = true
    models[joaat('u_m_m_bankman')] = true

    local removed = 0

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            local tagged = Entity(ped).state and Entity(ped).state.nzBankTeller
            local ours = tagged or (models[GetEntityModel(ped)] and IsEntityAMissionEntity(ped))

            if ours then
                local near = not radius or #(GetEntityCoords(ped) - me) <= radius

                if near then
                    if GetResourceState('ox_target') == 'started' then
                        pcall(function() exports.ox_target:removeLocalEntity(ped) end)
                    end
                    if GetResourceState('qb-target') == 'started' then
                        pcall(function() exports['qb-target']:RemoveTargetEntity(ped) end)
                    end

                    SetEntityAsMissionEntity(ped, true, true)
                    DeleteEntity(ped)
                    removed = removed + 1
                end
            end
        end
    end

    return removed
end

--- One-off cleanup for ghosts left by an older build, which were never
--- tagged and may be standing at coordinates no longer in the config.
RegisterCommand('bankclean', function()
    local removed = Bank.sweepTellers(60.0)
    Bank.notify('Banking',
        ('Cleared %s teller%s within 60m. Restart the resource to respawn them.')
            :format(removed, removed == 1 and '' or 's'),
        removed > 0 and 'success' or 'inform')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Bank.leaveATM then Bank.leaveATM() end

    clearTargets()
    Bank.sweepTellers()
    Bank.peds = {}

    lib.hideTextUI()
    SetNuiFocus(false, false)
end)
