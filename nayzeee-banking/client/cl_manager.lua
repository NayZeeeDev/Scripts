if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BANKING MANAGER · CLIENT
--
--  Opens the panel (the server decides who may), carries its
--  requests to the server, and runs the parts that have to happen
--  in the world: teleporting, and the placement tools that move a
--  teller, the money counter and the cash spot by eye.
--
--  Moving a teller
--    arrows        move          SHIFT  faster    ALT  finer
--    PAGE UP/DOWN  up and down   Q / E  turn
--    G             to where you stand
--    ENTER         save          BACKSPACE  cancel
--  Placing a money counter
--    MOUSE         aim: the prop sits where you look
--    SCROLL        turn it (SHIFT for fine steps)
--    E             put it down and save
--    TAB           put it down and move the cash spot next
--    BACKSPACE     cancel
-- ═══════════════════════════════════════════════════════════
Bank.managerOpen = false
Bank.placing = false

local CALLS = {
    boot = true, overview = true, players = true, player = true, adjust = true, freeze = true, rename = true,
    wallet = true, credit = true, loan = true, card = true, bill = true, transactions = true, societies = true,
    accounts = true, audit = true, settings = true, setting = true, resetSettings = true, export = true,
    branches = true, branchSave = true, branchDelete = true, branchesReset = true, counterSave = true,
    market = true, marketSet = true,
}

local function open(page)
    if Bank.isOpen then Bank.close() end
    local res = lib.callback.await('nz_bank:mgr:boot', false)
    if not res or not res.ok then
        return Bank.notify('Banking Manager', res and res.msg or 'The server did not answer.', 'error')
    end
    Bank.managerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'manager', data = res.data, page = page })
end

local function close()
    if not Bank.managerOpen then return end
    Bank.managerOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'managerClose' })
end

RegisterNetEvent('nz_bank:mgrOpen', function() open() end)

RegisterNUICallback('mgr', function(data, cb)
    local name = data and data.name
    if not CALLS[name] then return cb({ ok = false, msg = 'Blocked.' }) end
    local args = data.args or {}
    cb(lib.callback.await('nz_bank:mgr:' .. name, false, table.unpack(args, 1, tonumber(data.n) or #args)) or
        { ok = false, msg = 'The server did not answer.' })
end)

RegisterNUICallback('mgrClose', function(_, cb)
    close()
    cb(1)
end)

-- ── teleporting ──────────────────────────────────────────
local function mover()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return ped
end

--- Somewhere on the map: with no height given, the ground is found from above.
local moving = nil   -- { ent } while a teleport holds the player frozen behind a black screen

--- Somewhere on the map. The player waits frozen at the spot until the world
--- there has loaded, so they never drop through a floor; with no height given
--- the ground is found from above, and if it never is they go back where they were.
local function teleport(x, y, z, heading)
    local ent = mover()
    local from = GetEntityCoords(ent)
    moving = { ent = ent }
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    FreezeEntityPosition(ent, true)

    local function waitForWorld(atZ)
        SetEntityCoordsNoOffset(ent, x, y, atZ, false, false, false)
        local deadline = GetGameTimer() + 5000
        repeat
            RequestCollisionAtCoord(x, y, atZ)
            Wait(50)
        until HasCollisionLoadedAroundEntity(ent) or GetGameTimer() > deadline
    end

    if not z then
        waitForWorld(500.0)
        for _ = 1, 2 do   -- a slow stream gets a second sweep
            for h = 950.0, 0.0, -25.0 do
                SetEntityCoordsNoOffset(ent, x, y, h, false, false, false)
                RequestCollisionAtCoord(x, y, h)
                Wait(25)
                local found, gz = GetGroundZFor_3dCoord(x, y, h, false)
                if found then z = gz + 1.0 break end
            end
            if z then break end
        end
        if not z then
            SetEntityCoordsNoOffset(ent, from.x, from.y, from.z, false, false, false)
            FreezeEntityPosition(ent, false)
            DoScreenFadeIn(300)
            moving = nil
            return Bank.notify('Banking Manager', 'Could not find the ground there; pick a spot on a road or building.', 'error')
        end
    end

    waitForWorld(z)
    SetEntityCoords(ent, x, y, z, false, false, false, false)
    if heading then SetEntityHeading(ent, heading) end
    FreezeEntityPosition(ent, false)
    DoScreenFadeIn(300)
    moving = nil
end

local function here()
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    return { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(ped) }
end

-- ═══════════════════════════════════════════════════════════
--  PLACEMENT
-- ═══════════════════════════════════════════════════════════
local K = {
    up = 172, down = 173, left = 174, right = 175, raise = 10, lower = 11,
    turnL = 44, turnR = 38, fast = 21, fine = 19, swap = 37, snap = 47,
    save = 191, cancel = 194,
}
local BLOCK = { 172, 173, 174, 175, 10, 11, 44, 38, 21, 19, 37, 47, 191, 194, 24, 25, 140, 141, 142, 200, 199,
    14, 15, 16, 17, 241, 242, 261, 262, 81, 82, 99, 100 }   -- the scroll wheel, whatever it is bound to

local function hud(data) SendNUIMessage({ action = 'mgrHud', data = data }) end

local function held(c) return IsDisabledControlPressed(0, c) end
local function tapped(c) return IsDisabledControlJustPressed(0, c) end

--- How far a key moves things this frame: SHIFT faster, ALT finer.
local function step(base)
    if held(K.fast) then return base * 4 end
    if held(K.fine) then return base * 0.25 end
    return base
end

local function arrow(at)
    DrawMarker(2, at.x, at.y, at.z + 0.45, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.16, 0.16, 0.16,
        8, 175, 162, 220, true, false, 2, false, nil, nil, false)
end

local function ring(at)
    DrawMarker(25, at.x, at.y, at.z + 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.32, 0.32, 0.32,
        8, 175, 162, 160, false, false, 2, false, nil, nil, false)
end

--- Run a placement loop until ENTER or BACKSPACE. `frame` moves things and
--- draws; it returns the HUD rows when something changed. true = saved.
--- frame(first) returns the HUD rows when they changed, and true/false as a
--- second value to finish (save / cancel) on its own. saveKey defaults to ENTER.
local function placing(title, keys, frame, saveKey)
    Bank.placing = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'managerHide' })

    local saved = nil
    local first = true
    while saved == nil do
        for _, c in ipairs(BLOCK) do DisableControlAction(0, c, true) end
        -- an error in a frame ends the tool as a cancel, never leaves it stuck on
        local ran, rows, done = pcall(frame, first)
        if not ran then
            print('^1[nayzeee-banking]^7 placement tool failed: ' .. tostring(rows))
            rows, done = nil, false
        end
        if rows or first then hud({ title = title, keys = keys, rows = rows }) first = false end
        if done ~= nil then saved = done end
        if saved == nil and saveKey ~= false and tapped(saveKey or K.save) then saved = true end
        if tapped(K.cancel) then saved = false end
        Wait(0)
    end

    hud(nil)
    Bank.placing = false
    return saved
end

local function back(page, msg, ok)
    if msg then Bank.notify('Banking Manager', msg, ok == false and 'error' or 'success') end
    Bank.managerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'managerShow', page = page })
end

local function fmt(v) return ('%.2f'):format(v) end

-- ── a teller (or where a new branch's teller will stand) ─
local standIn = nil   -- the see-through teller the tool puts up, so a stop can take it down

--- What the server checks a save against, so a list another admin changed
--- meanwhile can never land on the wrong branch.
local function expect(cfg)
    return cfg and { label = cfg.label, x = cfg.coords.x, y = cfg.coords.y } or nil
end

local function placeTeller(index, label, pedModel)
    local cfg = index and Config.Banks[index]
    if index and not cfg then return back('branches', 'That branch is gone: the list was changed.', false) end
    local me = here()
    local pos = cfg and vector4(cfg.coords.x, cfg.coords.y, cfg.coords.z, cfg.coords.w) or vector4(me.x, me.y, me.z, me.w)
    local ped = index and Bank.peds[index]
    local temp = nil

    -- a stand-in teller for a branch that has none yet (or tellers are off)
    if not ped or not DoesEntityExist(ped) then
        local hash = joaat(pedModel or (cfg and cfg.ped) or 'ig_bankman')
        if IsModelInCdimage(hash) and pcall(lib.requestModel, hash, 5000) then
            temp = CreatePed(4, hash, pos.x, pos.y, pos.z - 1.0, pos.w, false, true)
            SetEntityInvincible(temp, true)
            SetBlockingOfNonTemporaryEvents(temp, true)
            FreezeEntityPosition(temp, true)
            SetEntityAlpha(temp, 200, false)
            Entity(temp).state:set('nzBankTeller', true, false)
            standIn = temp
            ped = temp
        end
    end
    if not ped then return back('branches', 'That teller model is not in the game.', false) end

    -- where the ped really sits against the config's height, so saving gives
    -- back the same kind of number config.lua holds
    Wait(50)
    local lift = GetEntityCoords(ped).z - pos.z
    local x, y, z, w = pos.x, pos.y, pos.z, pos.w
    if Bank.clearCounters then Bank.clearCounters() end

    local function apply()
        SetEntityCoordsNoOffset(ped, x, y, z + lift, false, false, false)
        SetEntityHeading(ped, w)
    end

    local ok = placing(index and ('Move teller · ' .. (cfg.label or 'Bank')) or ('New branch · ' .. (label or 'Bank')), {
        { '↑ ↓ ← →', 'move' }, { 'PG UP / DN', 'up · down' }, { 'Q / E', 'turn' },
        { 'G', 'to where you stand' }, { 'SHIFT / ALT', 'faster · finer' },
        { 'ENTER', 'save' }, { 'BACKSPACE', 'cancel' },
    }, function(first)
        local moved = false
        local cam = math.rad(GetGameplayCamRot(2).z)
        local fx, fy = -math.sin(cam), math.cos(cam)   -- the way the camera faces
        local s = step(0.02)
        if held(K.up) then x, y, moved = x + fx * s, y + fy * s, true end
        if held(K.down) then x, y, moved = x - fx * s, y - fy * s, true end
        if held(K.right) then x, y, moved = x + fy * s, y - fx * s, true end
        if held(K.left) then x, y, moved = x - fy * s, y + fx * s, true end
        if held(K.raise) then z, moved = z + step(0.01), true end
        if held(K.lower) then z, moved = z - step(0.01), true end
        if held(K.turnL) then w, moved = (w + step(1.0)) % 360, true end
        if held(K.turnR) then w, moved = (w - step(1.0)) % 360, true end
        if tapped(K.snap) then
            local me = here()
            x, y, z, w, moved = me.x, me.y, me.z, me.w, true
        end
        if moved then apply() end
        arrow(vector3(x, y, z + 0.6))
        if moved or first then
            return { { 'X', fmt(x) }, { 'Y', fmt(y) }, { 'Z', fmt(z) }, { 'Facing', ('%.0f°'):format(w) } }
        end
    end)

    if temp then DeleteEntity(temp) end
    standIn = nil
    if not ok then
        -- put the real teller back where it was
        if not temp and ped and DoesEntityExist(ped) then
            SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z + lift, false, false, false)
            SetEntityHeading(ped, pos.w)
        end
        if Bank.clearCounters then Bank.clearCounters() end
        return back('branches', 'Nothing was moved.', true)
    end

    local row = { label = label or (cfg and cfg.label) or 'Bank', ped = pedModel or (cfg and cfg.ped) or 'ig_bankman',
                  x = x, y = y, z = z, w = w }
    local res = lib.callback.await('nz_bank:mgr:branchSave', false, index, row, expect(cfg))
    back('branches', res and res.ok and (index and 'Teller moved for everyone.' or 'Branch added.') or (res and res.msg or 'Not saved.'),
        res and res.ok)
end

-- ── the money counter and the cash spot on a branch's counter ─
--  Aimed, not keyed: the prop sits wherever the camera looks (a ray from the
--  camera through the middle of the screen, so moving the mouse moves it),
--  the scroll wheel turns it and E puts it down. TAB puts the one in hand
--  down and picks up the other (the machine, then the spot the cash slides to).

local REACH = 2.6          -- how far from the teller either may go (the server allows 3)

--- Where the camera's line of sight first meets the world or an object. Peds
--- (the player, the teller) are not hit, and the props being placed have no
--- collision, so the ray goes through them to the counter beneath.
local function aim(distance)
    local from = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local to = from + dir * (distance or 8.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 17, PlayerPedId(), 7)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 and at then return at end
end

--- One notch of the scroll wheel: 1 up, -1 down, 0 none. A notch arrives on
--- several controls at once (cursor scroll, weapon wheel, next/previous
--- weapon), so it is read from all of them and counted once.
local function scrolled()
    local jp = IsDisabledControlJustPressed
    if jp(0, 241) or jp(0, 15) or jp(0, 17) then return 1 end
    if jp(0, 242) or jp(0, 14) or jp(0, 16) then return -1 end
    return 0
end

--- Where an entity sits, measured from the teller (x right, y forward, z up).
local function fromTeller(ped, ent)
    local p = GetEntityCoords(ent)
    return GetOffsetFromEntityGivenWorldCoords(ped, p.x, p.y, p.z)
end

local function placeCounter(index)
    local cfg = Config.Banks[index]
    local ped = Bank.peds[index]
    if not cfg or not ped or not DoesEntityExist(ped) then
        return back('branches', 'Stand near that branch first: its teller has to be there to place the counter.', false)
    end
    if not Bank.counterPreview or (Config.Teller and Config.Teller.enabled == false) or not Config.SpawnPeds then
        return back('branches', 'The teller counter is switched off (Settings > Teller counter).', false)
    end

    -- the props as they stand now, from config
    local c = Bank.counterConfig(index)
    local _, machine, notes = Bank.counterPreview(index, c)
    if not machine or not DoesEntityExist(machine) then
        return back('branches', 'The money counter model is not in the game: check Config.Teller.machineProp.', false)
    end

    local home = cfg.coords.w
    local tellerAt = GetEntityCoords(ped)
    local heading = GetEntityHeading(machine)
    local which = 'machine'
    local valid = true

    local function holding() return which == 'machine' and machine or notes end
    local function rel(h) return ((h - home + 180.0) % 360.0) - 180.0 end

    local ok = placing('Money counter · ' .. (cfg.label or 'Bank'), {
        { 'MOUSE', 'aim where it goes' }, { 'SCROLL', 'turn it (SHIFT finer)' }, { 'E', 'put it down and save' },
        { 'TAB', 'put it down, move the cash spot' }, { 'BACKSPACE', 'cancel' },
    }, function(first)
        local ent = holding()
        local changed = first
        local at = aim()
        local wasValid = valid

        if at and ent and DoesEntityExist(ent) then
            -- kept on the teller's side of the room
            valid = #(vector2(at.x, at.y) - vector2(tellerAt.x, tellerAt.y)) <= REACH
            if valid then
                local cur = GetEntityCoords(ent)
                if #(cur - at) > 0.003 then
                    SetEntityCoordsNoOffset(ent, at.x, at.y, at.z, false, false, false)
                    changed = true
                end
            end
        end

        if valid ~= wasValid then changed = true end   -- the HUD says when it is too far

        if which == 'machine' then
            local notch = scrolled()
            if notch ~= 0 then
                heading = (heading + notch * (held(K.fast) and 1.0 or 7.5)) % 360.0
                changed = true
            end
            SetEntityHeading(machine, heading)
        end

        -- what is in hand, and whether it can go there
        if ent and DoesEntityExist(ent) then
            local p = GetEntityCoords(ent)
            local r, g, b = 8, 175, 162
            if not valid then r, g, b = 229, 72, 77 end
            DrawMarker(25, p.x, p.y, p.z + 0.01, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.34, 0.34, 0.34,
                r, g, b, 170, false, false, 2, false, nil, nil, false)
            DrawMarker(2, p.x, p.y, p.z + 0.5, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.14, 0.14, 0.14,
                r, g, b, 220, true, false, 2, false, nil, nil, false)
        end

        if tapped(K.swap) and valid and notes and DoesEntityExist(notes) then
            which, changed = which == 'machine' and 'cash' or 'machine', true
        end
        local done
        if tapped(K.turnR) then   -- E
            if valid then done = true else Bank.notify('Banking Manager', 'Too far from the teller: keep it on their counter.', 'error') end
        end

        if changed then
            local m = fromTeller(ped, machine)
            local n = notes and DoesEntityExist(notes) and fromTeller(ped, notes)
            return {
                { 'In hand', which == 'machine' and 'Money counter' or 'Cash spot' },
                { 'Machine', ('%s, %s · %.0f°'):format(fmt(m.x), fmt(m.y), rel(heading)) },
                { 'Cash spot', n and ('%s, %s'):format(fmt(n.x), fmt(n.y)) or '—' },
                { 'Spot', valid and 'on the counter' or 'too far from the teller' },
            }, done
        end
        return nil, done
    end, false)   -- no other save key: E is handled above

    -- the machine went (the counter was switched off meanwhile): nothing sensible to save
    if ok and not (machine and DoesEntityExist(machine)) then
        Bank.counterPreviewEnd()
        return back('branches', 'The money counter disappeared before it was placed; nothing was saved.', false)
    end

    -- the props, measured from the teller the same way config.lua is
    local m = fromTeller(ped, machine)
    local n = notes and DoesEntityExist(notes) and fromTeller(ped, notes) or c.counter
    Bank.counterPreviewEnd()
    if Bank.clearCounters then Bank.clearCounters() end
    if not ok then return back('branches', 'Nothing was moved.', true) end

    local res = lib.callback.await('nz_bank:mgr:counterSave', false, index, expect(cfg), {
        machine = { x = m.x, y = m.y, z = m.z }, machineHeading = rel(heading),
        counter = { x = n.x, y = n.y, z = n.z },
    })
    back('branches', res and res.ok and 'Counter saved for everyone.' or (res and res.msg or 'Not saved.'), res and res.ok)
end

-- ── what the panel asks the world to do ──────────────────
RegisterNUICallback('mgrWorld', function(data, cb)
    local what = data and data.what
    if not Bank.managerOpen then return cb({ ok = false }) end

    if what == 'here' then return cb({ ok = true, pos = here() }) end

    if what == 'teleport' then
        cb({ ok = true })
        close()
        local x, y = tonumber(data.x), tonumber(data.y)
        if not x or not y then return end
        return CreateThread(function() teleport(x + 0.0, y + 0.0, tonumber(data.z), tonumber(data.w)) end)
    end

    if what == 'branch' then
        -- in front of the teller, facing them
        local b = Config.Banks[tonumber(data.index) or 0]
        cb({ ok = b ~= nil })
        if not b then return end
        close()
        local h = math.rad(b.coords.w)
        return CreateThread(function()
            teleport(b.coords.x - math.sin(h) * 1.6, b.coords.y + math.cos(h) * 1.6, b.coords.z, (b.coords.w + 180.0) % 360)
        end)
    end

    if what == 'player' then
        local target = GetPlayerFromServerId(tonumber(data.src) or -1)
        local ped = target ~= -1 and GetPlayerPed(target)
        if not ped or ped == 0 then return cb({ ok = false, msg = 'They are too far away to see; use their coordinates.' }) end
        cb({ ok = true })
        close()
        local p = GetEntityCoords(ped)
        return CreateThread(function() teleport(p.x + 1.0, p.y, p.z) end)
    end

    if what == 'placeTeller' then
        cb({ ok = true })
        return CreateThread(function() placeTeller(tonumber(data.index), data.label, data.ped) end)
    end

    if what == 'placeCounter' then
        cb({ ok = true })
        return CreateThread(function() placeCounter(tonumber(data.index)) end)
    end

    cb({ ok = false })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Bank.managerOpen or Bank.placing then SetNuiFocus(false, false) end
    -- a stop in the middle of a teleport or a tool: nothing left frozen, black or standing
    if moving then
        if DoesEntityExist(moving.ent) then FreezeEntityPosition(moving.ent, false) end
        DoScreenFadeIn(0)
    end
    if standIn and DoesEntityExist(standIn) then DeleteEntity(standIn) end
    if Bank.counterPreviewEnd then pcall(Bank.counterPreviewEnd) end
end)
