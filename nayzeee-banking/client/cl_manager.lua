if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  BANKING MANAGER · CLIENT
--
--  Opens the panel (the server decides who may), carries its
--  requests to the server, and runs the parts that have to happen
--  in the world: teleporting, and the placement tools that move a
--  teller, the money counter and the cash spot by eye.
--
--  Placement keys
--    arrows        move          SHIFT  faster    ALT  finer
--    PAGE UP/DOWN  up and down   Q / E  turn
--    TAB           machine / cash spot (counter only)
--    G             to where you stand (teller only)
--    ENTER         save          BACKSPACE  cancel
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
local function teleport(x, y, z, heading)
    local ent = mover()
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    FreezeEntityPosition(ent, true)

    if not z then
        for h = 950.0, 0.0, -25.0 do
            SetEntityCoordsNoOffset(ent, x, y, h, false, false, false)
            RequestCollisionAtCoord(x, y, h)
            Wait(25)
            local found, gz = GetGroundZFor_3dCoord(x, y, h, false)
            if found then z = gz + 1.0 break end
        end
        z = z or 120.0
    else
        RequestCollisionAtCoord(x, y, z)
        local deadline = GetGameTimer() + 3000
        while not HasCollisionLoadedAroundEntity(ent) and GetGameTimer() < deadline do Wait(0) end
    end

    SetEntityCoords(ent, x, y, z, false, false, false, false)
    if heading then SetEntityHeading(ent, heading) end
    FreezeEntityPosition(ent, false)
    DoScreenFadeIn(300)
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
local BLOCK = { 172, 173, 174, 175, 10, 11, 44, 38, 21, 19, 37, 47, 191, 194, 24, 25, 140, 141, 142, 200, 199 }

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
local function placing(title, keys, frame)   -- frame(first): first = draw the values once
    Bank.placing = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'managerHide' })

    local saved = nil
    local first = true
    while saved == nil do
        for _, c in ipairs(BLOCK) do DisableControlAction(0, c, true) end
        local rows = frame(first)
        if rows or first then hud({ title = title, keys = keys, rows = rows }) first = false end
        if tapped(K.save) then saved = true end
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
local function placeTeller(index, label, pedModel)
    local cfg = index and Config.Banks[index]
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
    local res = lib.callback.await('nz_bank:mgr:branchSave', false, index, row)
    back('branches', res and res.ok and (index and 'Teller moved for everyone.' or 'Branch added.') or (res and res.msg or 'Not saved.'),
        res and res.ok)
end

-- ── the money counter and the cash spot on a branch's counter ─
local function placeCounter(index)
    local cfg = Config.Banks[index]
    local ped = Bank.peds[index]
    if not cfg or not ped or not DoesEntityExist(ped) then
        return back('branches', 'Stand near that branch first: its teller has to be there to place the counter.', false)
    end
    if not Bank.counterPreview then return back('branches', 'The teller counter is switched off.', false) end

    local c = Bank.counterConfig(index)
    local m = { x = c.machine.x, y = c.machine.y, z = c.machine.z, h = c.machineHeading }
    local cash = { x = c.counter.x, y = c.counter.y, z = c.counter.z }
    local which = 'machine'

    local machine, notes
    local function show()
        local _, a, b = Bank.counterPreview(index, { machine = vector3(m.x, m.y, m.z), machineHeading = m.h,
            counter = vector3(cash.x, cash.y, cash.z) })
        machine, notes = a, b
    end
    show()

    local ok = placing('Money counter · ' .. (cfg.label or 'Bank'), {
        { 'TAB', 'machine / cash spot' }, { '← →', 'along the counter' }, { '↑ ↓', 'toward the customer' },
        { 'PG UP / DN', 'up · down' }, { 'Q / E', 'turn the machine' }, { 'SHIFT / ALT', 'faster · finer' },
        { 'ENTER', 'save' }, { 'BACKSPACE', 'cancel' },
    }, function(first)
        local t = which == 'machine' and m or cash
        local moved = false
        local s = step(0.01)
        if held(K.right) then t.x, moved = t.x + s, true end
        if held(K.left) then t.x, moved = t.x - s, true end
        if held(K.up) then t.y, moved = t.y + s, true end
        if held(K.down) then t.y, moved = t.y - s, true end
        if held(K.raise) then t.z, moved = t.z + s, true end
        if held(K.lower) then t.z, moved = t.z - s, true end
        if which == 'machine' and held(K.turnL) then m.h, moved = m.h + step(1.0), true end
        if which == 'machine' and held(K.turnR) then m.h, moved = m.h - step(1.0), true end
        if tapped(K.swap) then which, moved = (which == 'machine' and 'cash' or 'machine'), true end
        if moved then show() end

        local ent = which == 'machine' and machine or notes
        if ent and DoesEntityExist(ent) then
            local at = GetEntityCoords(ent)
            arrow(at)
            ring(at)
        end
        if moved or first then
            return {
                { 'Moving', which == 'machine' and 'Money counter' or 'Cash spot' },
                { 'Machine', ('%s, %s · %.0f°'):format(fmt(m.x), fmt(m.y), m.h) },
                { 'Cash spot', ('%s, %s'):format(fmt(cash.x), fmt(cash.y)) },
            }
        end
    end)

    Bank.counterPreviewEnd()
    if Bank.clearCounters then Bank.clearCounters() end
    if not ok then return back('branches', 'Nothing was moved.', true) end

    local res = lib.callback.await('nz_bank:mgr:counterSave', false, index, {
        machine = { x = m.x, y = m.y, z = m.z }, machineHeading = m.h, counter = { x = cash.x, y = cash.y, z = cash.z },
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
end)
