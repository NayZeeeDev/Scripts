if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  THE TELLER'S COUNTER
--
--  Every branch gets a money counter on the counter beside the
--  teller. Cash changes hands across the middle of the counter:
--
--    withdraw  the teller runs the notes through the machine, turns
--              back and slides them over; the player third-eyes them
--              (or presses E) to pick them up, and only then does the
--              money leave the account
--    deposit   the player puts the notes down, the teller takes them
--              and counts them through the machine
--
--  Positions are from the teller (Config.Teller) and dropped onto
--  whatever surface is under them, so the counter's height never
--  needs setting. Tellers are local to each player, so is all of this.
-- ═══════════════════════════════════════════════════════════
local T = Config.Teller or {}

local machines = {}   -- [bank index] = money counter object
local loose    = {}   -- note props in flight, cleaned up on a stop
local busy     = false
local warned   = {}
local pickup   = { zone = nil, kind = nil, text = false }   -- the live "Collect cash" target and prompt
local scene    = nil  -- { ped, home } of the scene running, so a failure can put the teller back

local function on()
    return T.enabled ~= false and Config.SpawnPeds
end

local function branchCfg(i)
    local per = (T.banks and T.banks[i]) or {}
    return {
        machine        = per.machine or T.machine or vec3(0.5, 0.4, 0.05),
        machineHeading = per.machineHeading or T.machineHeading or 0.0,
        counter        = per.counter or T.counter or vec3(0.0, 0.95, 0.05),
    }
end

--- A model that is really in the game, loaded; nil (said once) if not.
local function model(name)
    if not name then return nil end
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then
        if not warned[name] then
            warned[name] = true
            print(('^3[nayzeee-banking]^7 Config.Teller: model %s is not in the game, skipping it'):format(tostring(name)))
        end
        return nil
    end
    if not pcall(lib.requestModel, hash, 5000) then return nil end
    return hash
end

--- A point from the teller, dropped onto the counter top under it.
local function onCounter(ped, off)
    local p = GetOffsetFromEntityInWorldCoords(ped, off.x, off.y, off.z)
    -- world and objects only (1 | 16), so neither the teller nor the player is hit
    local ray = StartExpensiveSynchronousShapeTestLosProbe(p.x, p.y, p.z + 0.45, p.x, p.y, p.z - 0.7, 17, ped, 7)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 and at then return vector3(p.x, p.y, at.z) end
    return p
end

local function prop(hash, at, heading)
    local obj = CreateObject(hash, at.x, at.y, at.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    Entity(obj).state:set('nzBankCounter', true, false)
    return obj
end

local function drop(obj)
    if obj and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
    loose[obj or 0] = nil
end

-- ── the machines ─────────────────────────────────────────
local function sweep()
    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj) and Entity(obj).state and Entity(obj).state.nzBankCounter then drop(obj) end
    end
end

--- The teller's own heading, from config: a scene that went wrong must not
--- leave every later one facing the machine.
local function homeHeading(i, ped)
    local b = Config.Banks and Config.Banks[i]
    return (b and b.coords and b.coords.w) or GetEntityHeading(ped)
end

--- A machine goes on a branch's counter once the player is near enough for
--- the counter's collision to be loaded, so the drop onto it lands. Tellers
--- spawned late, or put back after /bankclean, get theirs the same way.
CreateThread(function()
    if not on() then return end
    sweep()   -- anything a crashed run left behind
    local hash
    while true do
        local me = GetEntityCoords(PlayerPedId())
        for i, ped in pairs(Bank.peds or {}) do
            if not machines[i] and ped and DoesEntityExist(ped)
                and #(me - GetEntityCoords(ped)) < 40.0 and HasCollisionLoadedAroundEntity(ped) then
                hash = hash or model(T.machineProp)
                if not hash then return end   -- not in the game; said once already
                local c = branchCfg(i)
                machines[i] = prop(hash, onCounter(ped, c.machine), homeHeading(i, ped) + c.machineHeading)
            end
        end
        Wait(1500)
    end
end)

--- Remove every counter prop, for /bankclean and a stop.
function Bank.clearCounters()
    for _, obj in pairs(machines) do drop(obj) end
    for obj in pairs(loose) do drop(obj) end
    machines = {}
end

-- ── moving things ────────────────────────────────────────
local function anim(ped, a, ms, flag)
    if not a or not a.dict then return end
    if not pcall(lib.requestAnimDict, a.dict, 3000) then return end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, ms or -1, flag or 0, 0.0, false, false, false)
end

local function faceTo(ped, at)
    local p = GetEntityCoords(ped)
    SetEntityHeading(ped, GetHeadingFromVector_2d(at.x - p.x, at.y - p.y))
end

--- Ease an object from one point to another.
local function slide(obj, from, to, ms)
    local start = GetGameTimer()
    while DoesEntityExist(obj) do
        local t = math.min(1.0, (GetGameTimer() - start) / ms)
        local e = t * t * (3 - 2 * t)
        SetEntityCoordsNoOffset(obj, from.x + (to.x - from.x) * e, from.y + (to.y - from.y) * e,
            from.z + (to.z - from.z) * e, false, false, false)
        if t >= 1.0 then break end
        Wait(0)
    end
end

--- The teller back on their mark, idling as they were spawned.
local function settle(ped, heading)
    if not DoesEntityExist(ped) then return end
    ClearPedTasks(ped)
    SetEntityHeading(ped, heading)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
end

--- The teller of the branch the player is stood at.
local function nearestTeller()
    local me = GetEntityCoords(PlayerPedId())
    local best, bestI, bestD
    for i, ped in pairs(Bank.peds or {}) do
        if ped and DoesEntityExist(ped) then
            local d = #(me - GetEntityCoords(ped))
            if d < 6.0 and (not bestD or d < bestD) then best, bestI, bestD = ped, i, d end
        end
    end
    return bestI, best
end

--- The notes running through the machine, with its sound.
local function count(ped, machine, notes)
    local secs = tonumber(T.countSeconds) or 4.1
    if machine and DoesEntityExist(machine) then
        faceTo(ped, GetEntityCoords(machine))
        local top = GetOffsetFromEntityInWorldCoords(machine, 0.0, 0.0, T.machineTop or 0.22)
        if notes then
            SetEntityCoordsNoOffset(notes, top.x, top.y, top.z, false, false, false)
            -- lined up with the machine's feed, not with the teller
            SetEntityHeading(notes, GetEntityHeading(machine) + (T.notesHeading or 90.0))
        end
    end
    anim(ped, T.anims and T.anims.count, -1, 1)
    if Bank.atmSound then Bank.atmSound('counter', 1.0) end
    Wait(math.floor(secs * 1000))
end

-- ── picking the notes up ─────────────────────────────────
local function targetActive()
    local t = Config.Target
    if t ~= 'ox_target' and t ~= 'qb-target' then return false end
    return GetResourceState(t) == 'started'
end

--- Take the "Collect cash" target and prompt down, whichever is up.
local function clearPickup()
    if pickup.text then lib.hideTextUI() pickup.text = false end
    if pickup.zone then
        local zone, kind = pickup.zone, pickup.kind
        pcall(function()
            if kind == 'ox_target' then exports.ox_target:removeZone(zone)
            else exports['qb-target']:RemoveZone(zone) end
        end)
    end
    pickup.zone, pickup.kind = nil, nil
end

--- Wait for the player to take the notes off the counter. true when they
--- did; false, 'timeout' / 'walked' when they did not. The target is a small
--- zone over the notes rather than the notes themselves: they have no
--- collision (so they cannot shove anyone), and a third-eye's ray goes
--- straight through an entity without it.
local function waitForPickup(at)
    local picked = false
    local target = targetActive() and Config.Target or nil
    local label = L('teller_collect')
    local option = { icon = 'fa-solid fa-money-bill-wave', label = label }

    if target == 'ox_target' then
        pcall(function()
            option.name, option.distance = 'nz_bank_collect', 2.0
            option.onSelect = function() picked = true end
            pickup.zone = exports.ox_target:addSphereZone({ coords = at, radius = 0.35, options = { option } })
            pickup.kind = target
        end)
    elseif target == 'qb-target' then
        pcall(function()
            option.action = function() picked = true end
            pickup.zone = 'nz_bank_collect'
            pickup.kind = target
            exports['qb-target']:AddCircleZone(pickup.zone, at, 0.35,
                { name = pickup.zone, debugPoly = false, useZ = true }, { options = { option }, distance = 2.0 })
        end)
    end

    local deadline = GetGameTimer() + (tonumber(T.collectSeconds) or 60) * 1000
    local away = tonumber(T.walkAway) or 6.0
    local why = nil

    while not picked do
        local d = #(GetEntityCoords(PlayerPedId()) - at)
        if GetGameTimer() > deadline then why = 'timeout' break end
        if d > away then why = 'walked' break end

        -- the key press, when no third-eye is running (cl_main stands its own
        -- E aside while Bank.tellerBusy, so one press does one thing)
        if not pickup.zone then
            if d < 2.0 then
                if not pickup.text then lib.showTextUI(L('teller_textui')) pickup.text = true end
                if IsControlJustReleased(0, 38) then picked = true end
            elseif pickup.text then
                lib.hideTextUI() pickup.text = false
            end
            Wait(0)
        else
            Wait(150)
        end
    end

    clearPickup()
    return picked, why
end

-- ── the two scenes ───────────────────────────────────────
local function withdraw(info)
    local i, ped = nearestTeller()
    local hash = model(T.cashProp)
    if not ped or not hash then
        -- no teller to hand it over: straight into the player's pocket
        local res = lib.callback.await('nz_bank:tellerCollect', false, info.token)
        return Bank.notify(L('bank_title'), res and res.msg or L('bank_no_answer'), res and res.ok and 'success' or 'error')
    end

    local home = homeHeading(i, ped)
    scene = { ped = ped, home = home }
    local machine = machines[i]
    local mid = onCounter(ped, branchCfg(i).counter)

    -- counted out through the machine
    ClearPedTasks(ped)
    local start = machine and DoesEntityExist(machine)
        and GetOffsetFromEntityInWorldCoords(machine, 0.0, 0.0, T.machineTop or 0.22) or mid
    local notes = prop(hash, start, home)
    loose[notes] = true
    count(ped, machine, notes)

    -- turned back and slid across the counter
    SetEntityHeading(ped, home)
    anim(ped, T.anims and T.anims.give, 1400, 0)
    Wait(350)
    SetEntityHeading(notes, home)
    slide(notes, GetEntityCoords(notes), mid, 700)
    settle(ped, home)

    local picked, why = waitForPickup(mid)
    if picked then
        anim(PlayerPedId(), T.anims and T.anims.take, 1200, 48)
        Wait(500)
        drop(notes)
        local res = lib.callback.await('nz_bank:tellerCollect', false, info.token)
        Bank.notify(L('bank_title'), res and res.msg or L('bank_no_answer'), res and res.ok and 'success' or 'error')
    else
        -- the teller takes it back off the counter
        if DoesEntityExist(ped) then
            anim(ped, T.anims and T.anims.take, 1200, 0)
            Wait(300)
            slide(notes, mid, GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.25, 0.0), 500)
            settle(ped, home)
        end
        drop(notes)
        lib.callback.await('nz_bank:tellerCancel', false, info.token)
        Bank.notify(L('bank_title'), L(why == 'walked' and 'teller_walked' or 'teller_put_away'), 'inform')
    end
end

local function deposit(info)
    local i, ped = nearestTeller()
    local hash = model(T.cashProp)
    if not ped or not hash then
        return Bank.notify(L('bank_title'), info.done, 'success')
    end

    local home = homeHeading(i, ped)
    scene = { ped = ped, home = home }
    local machine = machines[i]
    local mid = onCounter(ped, branchCfg(i).counter)

    -- put down on the counter
    anim(PlayerPedId(), T.anims and T.anims.give, 1200, 48)
    Wait(550)
    local notes = prop(hash, mid, home)
    loose[notes] = true
    Wait(400)

    -- taken by the teller and run through the machine
    ClearPedTasks(ped)
    anim(ped, T.anims and T.anims.take, 1300, 0)
    Wait(350)
    local to = machine and DoesEntityExist(machine)
        and GetOffsetFromEntityInWorldCoords(machine, 0.0, 0.0, T.machineTop or 0.22)
        or GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.3, 0.0)
    slide(notes, mid, to, 700)
    count(ped, machine, notes)

    drop(notes)
    settle(ped, home)
    Bank.notify(L('bank_title'), info.done, 'success')
end

--- Called by the NUI bridge when a branch deposit or withdrawal comes back.
function Bank.tellerScene(info)
    if type(info) ~= 'table' then return end
    if busy then
        -- one scene at a time; a second one just completes
        if info.kind == 'deposit' then return Bank.notify(L('bank_title'), info.done, 'success') end
        local res = lib.callback.await('nz_bank:tellerCollect', false, info.token)
        return Bank.notify(L('bank_title'), res and res.msg or L('bank_no_answer'), res and res.ok and 'success' or 'error')
    end

    busy, Bank.tellerBusy = true, true
    local ok, err = pcall(info.kind == 'withdraw' and withdraw or deposit, info)
    busy, Bank.tellerBusy = false, false
    if not ok then
        print('^1[nayzeee-banking]^7 teller scene failed: ' .. tostring(err))
        -- tidy the counter and put the teller back before anything else
        clearPickup()
        for obj in pairs(loose) do drop(obj) end
        if scene then pcall(settle, scene.ped, scene.home) end
        -- whatever happened on screen, the money still has to land
        if info.kind == 'withdraw' then
            local res = lib.callback.await('nz_bank:tellerCollect', false, info.token)
            Bank.notify(L('bank_title'), res and res.msg or L('bank_no_answer'), res and res.ok and 'success' or 'error')
        else
            Bank.notify(L('bank_title'), info.done, 'success')
        end
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- nothing here yields: the prompt belongs to ox_lib and outlives us
    clearPickup()
    Bank.clearCounters()
end)
