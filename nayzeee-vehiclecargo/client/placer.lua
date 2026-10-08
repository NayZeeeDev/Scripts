-----------------------------------------------------------------
-- Placement tool. Look around with the mouse and the preview follows:
--   car spots → a see-through ghost car
--   props     → a ghost of the prop (the laptop)
--   peds      → a ghost of the ped (the broker)
--   points    → a cylinder on the spot with a line from you to it
-- Scroll rotates (hold SHIFT for fine steps). The key guide is a
-- small stacked card on the right of the screen.
-----------------------------------------------------------------
Placer = { active = false }
local C = Config.Placer

local BLOCK = { 14, 15, 16, 17, 24, 25, 37, 44, 45, 140, 141, 142, 241, 242, 261, 262 }

local function blockControls()
    for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
end

local function scrolled()
    local step = IsControlPressed(0, 21) and C.FineStep or C.Step
    if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 17) or IsDisabledControlJustPressed(0, 241) then return step end
    if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 16) or IsDisabledControlJustPressed(0, 242) then return -step end
    return 0
end

local function camHeading() return GetGameplayCamRot(2).z % 360 end

-- Where the camera is looking. Peds and cars are ignored, and so is the ghost.
local function aim(ghost)
    local from = GetGameplayCamCoord()
    local r = GetGameplayCamRot(2)
    local rx, rz = math.rad(r.x), math.rad(r.z)
    local c = math.abs(math.cos(rx))
    local d = C.Distance
    local tx, ty, tz = from.x - math.sin(rz) * c * d, from.y + math.cos(rz) * c * d, from.z + math.sin(rx) * d
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, tx, ty, tz, 1 + 16, ghost or cache.ped, 7)
    local _, hit, pos = GetShapeTestResult(ray)
    if (hit == true or hit == 1) and pos and (pos.x ~= 0.0 or pos.y ~= 0.0) then return pos end
end

local function round(x, y, z, w)
    return { x = Cargo.Round(x * 100) / 100, y = Cargo.Round(y * 100) / 100, z = Cargo.Round(z * 100) / 100, w = Cargo.Round((w or 0.0) * 10) / 10 }
end

local function label3d(x, y, z, text)
    SetDrawOrigin(x, y, z, 0)
    SetTextFont(4)
    SetTextScale(0.0, 0.38)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function forward(h, len)
    local r = math.rad(h)
    return -math.sin(r) * len, math.cos(r) * len
end

local function drawLine(pos, r, g, b)
    local p = GetEntityCoords(cache.ped)
    DrawLine(p.x, p.y, p.z + 0.35, pos.x, pos.y, pos.z + 0.05, r, g, b, 220)
end

local function drawPoint(pos, h, r, g, b)
    DrawMarker(1, pos.x, pos.y, pos.z, 0, 0, 0, 0, 0, 0, 0.65, 0.65, 1.1, r, g, b, 140, false, false, 2, false, nil, nil, false)
    local fx, fy = forward(h, 0.9)
    DrawLine(pos.x, pos.y, pos.z + 1.15, pos.x + fx, pos.y + fy, pos.z + 1.15, 255, 255, 255, 230)
    DrawMarker(28, pos.x + fx, pos.y + fy, pos.z + 1.15, 0, 0, 0, 0, 0, 0, 0.07, 0.07, 0.07, 255, 255, 255, 230, false, false, 2, false, nil, nil, false)
end

local function drawSpot(s, n, r, g, b, a)
    DrawMarker(43, s.x, s.y, s.z + 0.02, 0, 0, 0, 0, 0, s.w or 0.0, 2.2, 4.8, 0.12, r, g, b, a or 70, false, false, 2, false, nil, nil, false)
    local fx, fy = forward(s.w or 0.0, 2.0)
    DrawMarker(28, s.x + fx, s.y + fy, s.z + 0.25, 0, 0, 0, 0, 0, 0, 0.1, 0.1, 0.1, 255, 255, 255, 200, false, false, 2, false, nil, nil, false)
    if n then label3d(s.x, s.y, s.z + 0.9, tostring(n)) end
end

-----------------------------------------------------------------
-- Ghost previews
-----------------------------------------------------------------
local function makeGhost(kind, model)
    if kind == 'point' then return nil, 0.0 end
    local fallback = kind == 'car' and C.GhostModel or nil
    local hash = (model and Client.LoadModel(model)) or (fallback and Client.LoadModel(fallback))
    if not hash then return nil, 0.0 end
    local e
    if kind == 'car' then
        e = CreateVehicle(hash, 0.0, 0.0, -200.0, 0.0, false, false)
        SetVehicleDoorsLocked(e, 2)
        SetVehicleLights(e, 2)
    elseif kind == 'ped' then
        e = CreatePed(4, hash, 0.0, 0.0, -200.0, 0.0, false, false)
        SetBlockingOfNonTemporaryEvents(e, true)
    else
        e = CreateObject(hash, 0.0, 0.0, -200.0, false, false, false)
    end
    SetModelAsNoLongerNeeded(hash)
    SetEntityAlpha(e, 170, false)
    SetEntityCollision(e, false, false)
    FreezeEntityPosition(e, true)
    SetEntityInvincible(e, true)
    local mn = GetModelDimensions(hash)
    return e, -mn.z
end

local function moveGhost(e, lift, pos, h)
    if not e then return end
    if pos then
        SetEntityVisible(e, true, false)
        SetEntityCoordsNoOffset(e, pos.x, pos.y, pos.z + lift, false, false, false)
        SetEntityHeading(e, h)
    else
        SetEntityVisible(e, false, false)
    end
end

-----------------------------------------------------------------
-- Key guide (stacked card, only re-sent when it changes)
-----------------------------------------------------------------
local lastGuide
local function guide(title, status, keys)
    local key = title .. '|' .. (status or '')
    if key == lastGuide then return end
    lastGuide = key
    Client.Send('guide', { title = title, status = status, keys = keys })
end

local function finish(e)
    lastGuide = nil
    Client.Send('guide', { hide = true })
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    Placer.active = false
end

local POINT_KEYS = { { 'E', 'Place' }, { 'SCROLL', 'Rotate' }, { 'SHIFT + SCROLL', 'Fine rotate' }, { 'BACKSPACE', 'Cancel' } }

-----------------------------------------------------------------
-- One placement.
-- opts = { label, kind = 'point' | 'car' | 'prop' | 'ped', model, face, heading }
-- face = true starts it turned towards you. Returns { x, y, z, w } or nil.
-- z: points = standing height · cars = just above the floor (they settle)
--    props = the surface you aimed at · peds = the floor
-----------------------------------------------------------------
function Placer.Point(opts)
    if Placer.active then return nil end
    Placer.active = true
    opts = opts or {}
    local kind = opts.kind or 'point'
    local r, g, b = Client.Accent()
    local ghost, lift = makeGhost(kind, opts.model)
    if kind ~= 'point' and not ghost then kind = 'point' end
    local heading = opts.heading or ((camHeading() + (opts.face and 180.0 or 0.0)) % 360)
    local result
    while true do
        blockControls()
        heading = (heading + scrolled()) % 360
        local pos = aim(ghost)
        if ghost then moveGhost(ghost, lift, pos, heading) elseif pos then drawPoint(pos, heading, r, g, b) end
        if pos then drawLine(pos, r, g, b) end
        guide(opts.label or 'Place', pos and ('Facing %d°'):format(math.floor(heading)) or 'Aim at the floor', POINT_KEYS)
        if IsControlJustPressed(0, 38) then
            if pos then
                local up = (kind == 'point' and 1.0) or (kind == 'car' and 0.5) or 0.0
                result = round(pos.x, pos.y, pos.z + up, heading)
                break
            end
            Bridge.Notify(L('placer_far'), 'error')
        elseif IsControlJustPressed(0, 177) then
            Bridge.Notify(L('placer_cancel'), 'info')
            break
        end
        Wait(0)
    end
    finish(ghost)
    return result
end

-- Several placements in a row. steps = { { key, label, kind, model, face }, ... }
function Placer.Steps(steps)
    local out = {}
    for _, st in ipairs(steps) do
        local p = Placer.Point(st)
        if not p then return nil end
        out[st.key] = p
        Wait(200)
    end
    return out
end

-----------------------------------------------------------------
-- Car spots with a ghost car that follows your aim.
-- opts = { label, spots = existing, max, fixed = n, model }
-- fixed = n: exactly n spots that can be moved, never removed
-- (the 4 illegal spots downstairs). Returns the list or nil.
-- Spot z is the floor; display cars settle onto it.
-----------------------------------------------------------------
function Placer.Spots(opts)
    if Placer.active then return nil end
    Placer.active = true
    local r, g, b = Client.Accent()
    local ghost, lift = makeGhost('car', opts.model)
    local spots = {}
    for i, s in ipairs(opts.spots or {}) do spots[i] = { x = s.x, y = s.y, z = s.z, w = s.w or 0.0 } end
    local fixed, max = opts.fixed, opts.fixed or opts.max or Config.Layout.MaxSlots
    local cursor = 1
    local heading = camHeading()
    local keys = fixed
        and { { 'E', 'Place this spot' }, { 'SCROLL', 'Rotate' }, { 'Z', 'Back one spot' }, { 'ENTER', 'Save' }, { 'BACKSPACE', 'Cancel' } }
        or  { { 'E', 'Place spot' }, { 'SCROLL', 'Rotate' }, { 'Z', 'Undo' }, { 'R', 'Clear all' }, { 'ENTER', 'Save' }, { 'BACKSPACE', 'Cancel' } }
    local result
    while true do
        blockControls()
        heading = (heading + scrolled()) % 360
        local pos = aim(ghost)
        moveGhost(ghost, lift, pos, heading)
        if pos then drawLine(pos, r, g, b) end
        for i, s in ipairs(spots) do
            local current = fixed and i == cursor
            drawSpot(s, i, current and 229 or r, current and 72 or g, current and 77 or b, current and 120 or 70)
        end
        guide(opts.label or 'Car spots', fixed and ('Spot %d of %d'):format(cursor, fixed) or ('%d / %d spots'):format(#spots, max), keys)

        if IsControlJustPressed(0, 38) then
            if not pos then
                Bridge.Notify(L('placer_far'), 'error')
            elseif fixed then
                spots[cursor] = round(pos.x, pos.y, pos.z, heading)
                cursor = cursor % fixed + 1
            elseif #spots >= max then
                Bridge.Notify(('That\'s the limit (%d).'):format(max), 'error')
            else
                spots[#spots + 1] = round(pos.x, pos.y, pos.z, heading)
            end
        elseif IsControlJustPressed(0, 20) then
            if fixed then cursor = cursor > 1 and cursor - 1 or fixed else spots[#spots] = nil end
        elseif not fixed and IsDisabledControlJustPressed(0, 45) then
            spots = {}
        elseif IsControlJustPressed(0, 191) then
            if #spots == 0 then Bridge.Notify('Place at least one spot.', 'error')
            else result = spots break end
        elseif IsControlJustPressed(0, 177) then
            Bridge.Notify(L('placer_cancel'), 'info')
            break
        end
        Wait(0)
    end
    finish(ghost)
    return result
end
