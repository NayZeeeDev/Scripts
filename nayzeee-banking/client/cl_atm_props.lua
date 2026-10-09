if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  WHAT THE MACHINE DOES WITH ITS HANDS
--
--  Cash pushes out of the dispenser when you withdraw and gets
--  pulled back in when you deposit. The card slides into the reader
--  on the way in and back out on the way out. A statement comes out
--  of the receipt slot.
--
--  Each slot is a point on the prop plus how far the item travels,
--  set per model in config. /atmslot places them against a real
--  machine and prints a block to paste.
--
--  Sounds go through the main NUI page, which is always loaded even
--  while it is hidden. A DUI cannot be relied on for audio.
-- ═══════════════════════════════════════════════════════════

local active = {}        -- props in flight, so a resource stop cleans them up
local warnedModels = {}  -- so a bad model name is said once, not every use

-- ═══════════════════════════════════════════════════════════
--  SOUND
-- ═══════════════════════════════════════════════════════════
--- One place every sound in the resource goes through.
function Bank.atmSound(name, volume)
    local s = Config.Sounds
    if not s or not s.enabled then return end

    local file = s.files and s.files[name]
    if not file then return end

    SendNUIMessage({
        action = 'sound',
        name   = file,
        volume = (volume or 1.0) * (s.volume or 0.6)
    })
end

exports('playSound', function(name, volume) Bank.atmSound(name, volume) end)

-- ═══════════════════════════════════════════════════════════
--  SLOTS
-- ═══════════════════════════════════════════════════════════
local function slotConfig(model, slot)
    local slots = Config.ATM.slots or {}
    local per = slots.models and slots.models[model]
    return (per and per[slot]) or (slots.default and slots.default[slot])
end

--- Slide a prop from one offset to another along the machine's own axes.
local function slide(entity, model, spec, opts)
    if not spec or not entity or not DoesEntityExist(entity) then return end
    if not Config.ATM.slots or not Config.ATM.slots.enabled then return end

    -- config holds prop names as strings, natives want the hash
    local propModel = type(opts.model) == 'string' and joaat(opts.model) or opts.model

    -- ox_lib raises on an invalid model rather than returning false,
    -- and a typo in config should not throw inside a thread nobody
    -- is watching. Check first and say so once.
    if not IsModelValid(propModel) then
        if not warnedModels[propModel] then
            warnedModels[propModel] = true
            print(('^3[nayzeee-banking]^7 %s is not a model in this game build — ' ..
                   'that ATM prop is skipped. Check Config.ATM.slots.'):format(tostring(opts.model)))
        end
        return
    end

    if not lib.requestModel(propModel, 2000) then return end

    local from = GetOffsetFromEntityInWorldCoords(entity, spec.x, spec.from, spec.z)
    local prop = CreateObject(propModel, from.x, from.y, from.z, false, false, false)
    if not DoesEntityExist(prop) then
        SetModelAsNoLongerNeeded(propModel)
        return
    end

    active[#active + 1] = prop
    SetEntityCollision(prop, false, false)
    SetEntityInvincible(prop, true)
    FreezeEntityPosition(prop, true)

    local heading = GetEntityHeading(entity)
    if opts.rotation then
        SetEntityRotation(prop, opts.rotation.x, opts.rotation.y, heading + opts.rotation.z, 2, true)
    else
        SetEntityHeading(prop, heading + (opts.headingOffset or 0.0))
    end

    -- ease out, so it decelerates into the slot rather than snapping
    local duration = opts.duration or 900
    local start = GetGameTimer()

    while true do
        local elapsed = GetGameTimer() - start
        if elapsed >= duration then break end
        if not DoesEntityExist(entity) or not DoesEntityExist(prop) then break end

        local t = elapsed / duration
        local eased = 1 - ((1 - t) ^ 3)
        local y = spec.from + (spec.to - spec.from) * eased
        local at = GetOffsetFromEntityInWorldCoords(entity, spec.x, y, spec.z)

        SetEntityCoordsNoOffset(prop, at.x, at.y, at.z, false, false, false)
        Wait(0)
    end

    if opts.hold and opts.hold > 0 then Wait(opts.hold) end

    if DoesEntityExist(prop) then DeleteEntity(prop) end
    for i = #active, 1, -1 do if active[i] == prop then table.remove(active, i) end end
    SetModelAsNoLongerNeeded(propModel)
end

-- ═══════════════════════════════════════════════════════════
--  CASH
-- ═══════════════════════════════════════════════════════════
--- direction 'out' dispenses, 'in' takes a deposit.
function Bank.atmCashProp(entity, model, direction)
    local spec = slotConfig(model, 'cash')
    if not spec then return end

    CreateThread(function()
        Bank.atmSound('dispense')

        local travel = {
            x = spec.x, z = spec.z,
            from = direction == 'out' and spec.inner or spec.outer,
            to   = direction == 'out' and spec.outer or spec.inner
        }

        slide(entity, model, travel, {
            model    = Config.ATM.slots.cashProp or 'prop_anim_cash_pile_01',
            duration = direction == 'out' and 1000 or 900,
            hold     = direction == 'out' and 700 or 0,
            rotation = { x = 0.0, y = 0.0, z = spec.rotation or 0.0 }
        })
    end)
end

-- ═══════════════════════════════════════════════════════════
--  CARD
-- ═══════════════════════════════════════════════════════════
function Bank.atmCardProp(entity, model, direction)
    local spec = slotConfig(model, 'card')
    if not spec then return end
    if not Config.ATM.animation or not Config.ATM.animation.enabled then return end

    CreateThread(function()
        Bank.atmSound('card')

        local travel = {
            x = spec.x, z = spec.z,
            from = direction == 'in' and spec.outer or spec.inner,
            to   = direction == 'in' and spec.inner or spec.outer
        }

        slide(entity, model, travel, {
            model    = Config.ATM.animation.cardProp or 'prop_cs_credit_card',
            duration = 700,
            hold     = direction == 'out' and 600 or 0,
            rotation = { x = 90.0, y = 90.0, z = spec.rotation or 0.0 }
        })
    end)
end

-- ═══════════════════════════════════════════════════════════
--  RECEIPT
-- ═══════════════════════════════════════════════════════════
function Bank.atmReceiptProp(entity, model)
    local spec = slotConfig(model, 'receipt')
    if not spec then return end

    CreateThread(function()
        slide(entity, model, {
            x = spec.x, z = spec.z, from = spec.inner, to = spec.outer
        }, {
            model    = Config.ATM.slots.receiptProp or 'prop_fib_letter',
            duration = 1100,
            hold     = 900,
            rotation = { x = 0.0, y = 0.0, z = spec.rotation or 0.0 }
        })
    end)
end

-- ═══════════════════════════════════════════════════════════
--  CLEANUP
-- ═══════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, prop in ipairs(active) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    active = {}
end)

-- ═══════════════════════════════════════════════════════════
--  /atmslot — place the dispenser, card reader and receipt slot
--
--  Walk up to a machine, run it, and a marker sits where the item
--  will come from. Arrows move it, TAB cycles axis, [ ] cycles slot,
--  ENTER prints the block.
-- ═══════════════════════════════════════════════════════════
if Config.Debug then
    local SLOTS = { 'cash', 'card', 'receipt' }
    local tune = { on = false, slot = 1, axis = 'z', step = 0.01, edge = 'outer' }

    RegisterCommand('atmslot', function()
        tune.on = not tune.on
        Bank.notify('ATM slots', tune.on
            and 'Arrows move · TAB axis · ] next slot · G inner/outer · ENTER print'
            or 'Slot tuning off', 'inform')
        if not tune.on then return end

        CreateThread(function()
            while tune.on do
                local pos = GetEntityCoords(PlayerPedId())
                local atm

                for _, m in ipairs(Config.ATMModels) do
                    local found = GetClosestObjectOfType(pos.x, pos.y, pos.z, 4.0, m, false, false, false)
                    if found ~= 0 and DoesEntityExist(found) then atm = found break end
                end

                if atm then
                    local model = GetEntityModel(atm)
                    local name = SLOTS[tune.slot]
                    local spec = slotConfig(model, name)

                    if spec then
                        local inner = GetOffsetFromEntityInWorldCoords(atm, spec.x, spec.inner, spec.z)
                        local outer = GetOffsetFromEntityInWorldCoords(atm, spec.x, spec.outer, spec.z)

                        DrawMarker(28, inner.x, inner.y, inner.z, 0,0,0, 0,0,0,
                            0.02, 0.02, 0.02, 120, 120, 120, 180, false, false, 2, nil, nil, false)
                        DrawMarker(28, outer.x, outer.y, outer.z, 0,0,0, 0,0,0,
                            0.025, 0.025, 0.025, 8, 175, 162, 220, false, false, 2, nil, nil, false)

                        local function apply(fn)
                            local slots = Config.ATM.slots
                            local per = slots.models and slots.models[model]
                            local target = (per and per[name]) or slots.default[name]
                            fn(target)
                        end

                        if IsControlJustPressed(0, 172) then
                            apply(function(s)
                                if tune.axis == 'x' then s.x = s.x + tune.step
                                elseif tune.axis == 'z' then s.z = s.z + tune.step
                                else s[tune.edge] = s[tune.edge] + tune.step end
                            end)
                        end
                        if IsControlJustPressed(0, 173) then
                            apply(function(s)
                                if tune.axis == 'x' then s.x = s.x - tune.step
                                elseif tune.axis == 'z' then s.z = s.z - tune.step
                                else s[tune.edge] = s[tune.edge] - tune.step end
                            end)
                        end
                        if IsControlJustPressed(0, 37) then
                            tune.axis = tune.axis == 'x' and 'y' or tune.axis == 'y' and 'z' or 'x'
                        end
                        if IsControlJustPressed(0, 40) then
                            tune.slot = tune.slot < #SLOTS and tune.slot + 1 or 1
                        end
                        if IsControlJustPressed(0, 47) then
                            tune.edge = tune.edge == 'outer' and 'inner' or 'outer'
                        end
                        if IsControlJustPressed(0, 191) then
                            print(('^3[atmslot]^7 %s = { x = %.3f, z = %.3f, inner = %.3f, outer = %.3f }')
                                :format(name, spec.x, spec.z, spec.inner, spec.outer))
                        end

                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(
                            ('Slot ~g~%s~s~  Axis ~g~%s~s~  Edge ~g~%s~s~  Step ~g~%.3f~s~')
                            :format(name, tune.axis, tune.edge, tune.step))
                        EndTextCommandDisplayHelp(0, false, true, -1)
                    end
                end

                Wait(0)
            end
        end)
    end, false)
end
