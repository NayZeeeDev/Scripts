--[[
    Drying rack, mixing station and brick press, first person.

      Drying   drag each bud onto a free clip on the rack. Dry buds come off a quality higher.
      Mixing   drop the product and the ingredient into the bowl, press START, the bowl spins.
      Press    load the mould, pump the lever (drag it down) until the ram has pressed a brick.
]]

Processing = {}

local P = Config.Props
local E = Config.Equipment

local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

--- claim -> scene -> finish
local function flow(o, action, args, cfg, sceneFn, onDone)
    local ok, extra = lib.callback.await('nzwl:st:claim', false, action, o.data.id, args)
    if not ok then
        if extra then UI.notify(extra, 'error') end
        return
    end
    local res = Interact.scene({ entity = o.ent, cfg = cfg, ctx = extra }, function(S) return sceneFn(S, extra or {}) end)
    if not res then
        lib.callback.await('nzwl:st:cancel', false)
        return
    end
    local fin, out = lib.callback.await('nzwl:st:finish', false)
    if fin then
        if onDone then onDone(out) end
    elseif out then
        UI.notify(out, 'error')
    end
end

--- drag `item` ({ e, p, home }) on plane z; true when released within `radius` of `target`
local function carry(S, item, z, target, radius, extraTick)
    local I = Interact
    local over = false
    while S.down do
        if not I.frame(S) then return nil end
        if extraTick then extraTick() end
        local p = I.cursorOn(S, z, S.origin, 1.2)
        if p then
            SetEntityCoordsNoOffset(item.e, p.x, p.y, p.z, false, false, false)
            item.p = p
            over = flat(p, target) < radius
            I.marker(25, vec3(target.x, target.y, target.z + 0.005), radius * 2.0, over and { 63, 185, 80 } or { 8, 175, 162 }, 170)
        end
        Wait(0)
    end
    return over
end

--[[ ─────────────── drying rack ─────────────── ]]

--- point under the cursor on the vertical plane through `at`, facing the camera (the rack's front)
local function cursorOnWall(S, at)
    local n = GetOffsetFromEntityInWorldCoords(S.ent, 0.0, -1.0, 0.0) - S.origin
    local denom = S.rdir.x * n.x + S.rdir.y * n.y + S.rdir.z * n.z
    if math.abs(denom) < 1e-4 then return nil end
    local d = at - S.rpos
    local t = (d.x * n.x + d.y * n.y + d.z * n.z) / denom
    if t <= 0 then return nil end
    return S.rpos + S.rdir * t
end

local function carryWall(S, item, target, radius)
    local I = Interact
    local over = false
    while S.down do
        if not I.frame(S) then return nil end
        local p = cursorOnWall(S, target)
        if p then
            SetEntityCoordsNoOffset(item.e, p.x, p.y, p.z, false, false, false)
            item.p = p
            over = #(p - target) < radius
            I.marker(28, target, 0.03, over and { 63, 185, 80 } or { 8, 175, 162 }, 220)
        end
        Wait(0)
    end
    return over
end

local function dryScene(S, o, n, bud)
    local I = Interact
    local free = {}
    local used = #(o.data.st.slots or {})
    for i = used + 1, math.min(#E.dryrack.slots, used + n) do free[#free + 1] = E.dryrack.slots[i] end
    local model = P.bud[bud] or P.bud.green
    -- the buds wait in a loose pile in front of the rack, at hand height
    local pile = {}
    for i = 1, #free do
        local home = Util.off(S.ent, vec3(-0.12 + (i % 5) * 0.06, -0.42, 1.0 + math.floor(i / 5) * 0.05))
        local e = I.spawn(S, model, home, math.random(0, 359), P.budFallback)
        pile[i] = { e = e, p = home, home = home }
    end
    local hung = 0
    for _, slot in ipairs(free) do
        local clip = Util.off(S.ent, slot)
        while true do
            if not I.frame(S) then return nil end
            I.hint(S, 'Drag a bud onto the highlighted clip', nil, ('%d/%d'):format(hung, #free))
            I.marker(28, clip, 0.03, { 8, 175, 162 }, 200)
            if S.pressed then
                local b = I.pick(S, pile, 40)
                if b then
                    local over = carryWall(S, b, clip, 0.08)
                    if over == nil then return nil end
                    if over then
                        SetEntityCoordsNoOffset(b.e, clip.x, clip.y, clip.z - 0.005, false, false, false)
                        SetEntityRotation(b.e, 180.0, 0.0, S.heading, 2, true)
                        b.done = true
                        hung = hung + 1
                        PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                        break
                    else
                        I.slide(S, b.e, b.p, b.home, 200)
                        b.p = b.home
                    end
                end
            end
            Wait(0)
        end
    end
    return true
end

function Processing.dry(o)
    local data = lib.callback.await('nzwl:panel:open', false, o.data.id)
    if not data then return end
    local pick = UI.panel('dry', data)
    if not pick then return end
    if pick.collect then return Processing.dryCollect(o, pick.idx) end
    if not pick.pid then return end
    local n = math.max(1, math.floor(tonumber(pick.n) or 1))
    flow(o, 'dry_hang', { pid = pick.pid, q = pick.q, n = n }, E.dryrack, function(S, extra)
        return dryScene(S, o, n, extra.bud)
    end, function()
        UI.notify(('Hung %d to dry. Back in %d minutes.'):format(n, Config.Processing.dry.minutes), 'success')
    end)
end

function Processing.dryCollect(o, idx)
    local ok, res = lib.callback.await('nzwl:dry:collect', false, o.data.id, idx)
    if ok then UI.notify(('Took %d off the rack'):format(res or 0), 'success') elseif res then UI.notify(res, 'error') end
end

--[[ ─────────────── mixing station ─────────────── ]]

local function mixScene(S, o, extra)
    local I = Interact
    local c = E.mixstation
    local bowlAt = I.anchor(S, 'bowl')
    local items = {
        { e = I.spawn(S, P.bud[extra.bud] or P.bud.green, I.anchor(S, 'product'), S.heading, P.budFallback), label = 'product' },
        { e = I.spawn(S, extra.prop or 'prop_cs_pills', I.anchor(S, 'ingredient'), S.heading, 'prop_cs_pills'), label = 'ingredient' },
    }
    for _, it in ipairs(items) do it.p = GetEntityCoords(it.e) it.home = it.p end
    local planeZ = bowlAt.z + 0.12
    for k, it in ipairs(items) do
        while true do
            if not I.frame(S) then return nil end
            I.hint(S, k == 1 and 'Drag the product into the bowl' or 'Drag the ingredient into the bowl')
            I.marker(28, it.p + vec3(0.0, 0.0, 0.08), 0.025, { 255, 255, 255 }, 160)
            if S.pressed and it.e and I.pxTo(S, it.p) < 44 then
                local over = carry(S, it, planeZ, bowlAt, 0.1)
                if over == nil then return nil end
                if over then
                    I.slide(S, it.e, it.p, bowlAt - vec3(0.0, 0.0, 0.03) + vec3((k - 1.5) * 0.04, 0.0, 0.0), 220)
                    it.p = bowlAt
                    PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                    break
                else
                    I.slide(S, it.e, it.p, it.home, 200)
                    it.p = it.home
                end
            end
            Wait(0)
        end
    end
    -- press START
    local btn = I.anchor(S, 'start')
    while true do
        if not I.frame(S) then return nil end
        I.hint(S, 'Press START')
        I.marker(28, btn, 0.03, { 63, 185, 80 }, 220)
        if S.pressed and I.pxTo(S, btn) < 40 then break end
        Wait(0)
    end
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    -- the bowl spins, the mix churns
    local bowl = o.bowl
    local secs = Config.Mixing.seconds * 1000
    local t0, spin = GetGameTimer(), 0.0
    local bowlPos = bowl and GetEntityCoords(bowl)
    while GetGameTimer() - t0 < secs do
        if not I.frame(S) then return nil end
        local k = (GetGameTimer() - t0) / secs
        local speed = math.min(1.0, k * 4.0, (1.0 - k) * 4.0) * 720.0
        spin = (spin + speed * S.dt) % 360.0
        if bowl then SetEntityRotation(bowl, 0.0, 0.0, S.heading + spin, 2, true) end
        for _, it in ipairs(items) do
            if it.e then
                local a = math.rad(spin + (it.label == 'product' and 0 or 180))
                local p = bowlAt + vec3(math.cos(a) * 0.05, math.sin(a) * 0.05, -0.03)
                SetEntityCoordsNoOffset(it.e, p.x, p.y, p.z, false, false, false)
            end
        end
        I.particles(S, bowlAt + vec3((math.random() - 0.5) * 0.12, (math.random() - 0.5) * 0.12, 0.0), 'dust', bowlAt.z - 0.05, vec3(0.0, 0.0, 0.8))
        I.hint(S, 'Mixing...', math.floor(k * 100))
        Wait(0)
    end
    if bowl then SetEntityRotation(bowl, 0.0, 0.0, S.heading, 2, true) SetEntityCoordsNoOffset(bowl, bowlPos.x, bowlPos.y, bowlPos.z, false, false, false) end
    return true
end

function Processing.mix(o)
    local data = lib.callback.await('nzwl:panel:open', false, o.data.id)
    if not data then return end
    local pick = UI.panel('mix', data)
    if not pick or not pick.pid or not pick.ingredient then return end
    flow(o, 'mix', { pid = pick.pid, q = pick.q, ingredient = pick.ingredient, n = pick.n }, E.mixstation, function(S, extra)
        return mixScene(S, o, extra)
    end, function(res)
        if not res or not res.product then return end
        UI.notify(('%s · %s / unit'):format(res.product.name, Utils.money(res.product.value)), 'success', 7000, res.first and 'New discovery!' or 'Mixed')
    end)
end

--[[ ─────────────── brick press ─────────────── ]]

local function pressScene(S, o, extra)
    local I = Interact
    local c = E.brickpress
    local mould = I.anchor(S, 'mould')
    local model = P.bud[extra.bud] or P.bud.green
    -- 4 handfuls (each one is a quarter of the brick)
    local pile = {}
    for i = 1, 4 do
        local home = I.anchor(S, 'pile') + vec3((i % 2) * 0.05, math.floor(i / 3) * 0.05, 0.0)
        local e = I.spawn(S, model, home, math.random(0, 359), P.budFallback)
        pile[i] = { e = e, p = home, home = home }
    end
    local loaded = 0
    while loaded < #pile do
        if not I.frame(S) then return nil end
        I.hint(S, 'Load the mould', nil, ('%d/%d'):format(loaded, #pile))
        if S.pressed then
            local b = I.pick(S, pile, 42)
            if b then
                local over = carry(S, b, mould.z + 0.22, mould, 0.12)
                if over == nil then return nil end
                if over then
                    local spot = mould + vec3(((loaded % 2) - 0.5) * 0.12, (math.floor(loaded / 2) - 0.5) * 0.08, 0.02)
                    I.slide(S, b.e, b.p, spot, 200)
                    b.done = true
                    loaded = loaded + 1
                    PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                else
                    I.slide(S, b.e, b.p, b.home, 200)
                    b.p = b.home
                end
            end
        end
        Wait(0)
    end

    -- pump the lever: drag the grip down. Each full stroke drives the ram a third of the way.
    local lever, plate = o.lever, o.plate
    local platePos = plate and GetEntityCoords(plate)
    local pumpMax = c.lever.pump
    local pumps, need, angle, armed = 0, 3, 0.0, true
    local function setPlate(k)
        if plate and platePos then
            SetEntityCoordsNoOffset(plate, platePos.x, platePos.y, platePos.z - c.plate.travel * k, false, false, false)
        end
    end
    while pumps < need do
        if not I.frame(S) then return nil end
        local grip = lever and Util.off(lever, vec3(0.0, -0.05, 0.62)) or I.anchor(S, 'lever')
        I.hint(S, 'Drag the lever down to pump', math.floor((pumps / need) * 100))
        I.marker(28, grip, 0.03, { 255, 214, 10 }, 200)
        if S.pressed and I.pxTo(S, grip) < 60 then
            local sy0 = S.sy
            while S.down do
                if not I.frame(S) then return nil end
                angle = Utils.clamp((S.sy - sy0) * S.h / 220.0 * pumpMax, 0.0, pumpMax)
                if lever then SetEntityRotation(lever, angle, 0.0, S.heading, 2, true) end
                if armed and angle >= pumpMax * 0.95 then
                    armed = false
                    pumps = pumps + 1
                    PlaySoundFrontend(-1, 'Hydraulics_Down', 'Lowrider_Super_Mod_Garage_Sounds', true)
                    local from, to = (pumps - 1) / need, pumps / need
                    local t0 = GetGameTimer()
                    while GetGameTimer() - t0 < 250 do
                        setPlate(from + (to - from) * ((GetGameTimer() - t0) / 250.0))
                        if not I.frame(S) then return nil end
                        Wait(0)
                    end
                    setPlate(to)
                end
                if angle < pumpMax * 0.2 then armed = true end
                I.hint(S, 'Drag the lever down to pump', math.floor((pumps / need) * 100))
                Wait(0)
            end
            -- the handle springs back
            if lever then I.swing(S, lever, angle, 0.0, 220) end
            angle = 0.0
            armed = true
        end
        Wait(0)
    end
    -- the ram goes back up: there's a brick in the mould
    for _, b in ipairs(pile) do Util.delete(b.e) end
    local brick = I.spawn(S, P.brick, mould + vec3(0.0, 0.0, 0.012), S.heading, P.brickFallback)
    local t0 = GetGameTimer()
    while GetGameTimer() - t0 < 600 do
        setPlate(1.0 - (GetGameTimer() - t0) / 600.0)
        if not I.frame(S) then return nil end
        Wait(0)
    end
    setPlate(0.0)
    while true do
        if not I.frame(S) then return nil end
        I.hint(S, 'Take the brick')
        local at = mould + vec3(0.0, 0.0, 0.05)
        I.marker(28, at, 0.03, { 255, 255, 255 }, 200)
        if S.pressed and I.pxTo(S, at) < 50 then break end
        Wait(0)
    end
    if brick then I.slide(S, brick, mould, mould + vec3(0.0, -0.35, 0.35), 300) end
    return true
end

function Processing.press(o)
    local data = lib.callback.await('nzwl:panel:open', false, o.data.id)
    if not data then return end
    local pick = UI.panel('press', data)
    if not pick or not pick.pid then return end
    flow(o, 'press', { pid = pick.pid, q = pick.q }, E.brickpress, function(S, extra)
        return pressScene(S, o, extra)
    end, function()
        UI.notify('Pressed a brick', 'success')
    end)
end
