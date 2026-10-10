--[[
    Packaging station, first person (like the game):

      LEFT    the product tray: one bud per unit, laid out on the tray
      MIDDLE  the baggies / jars lined up in a row along the back of the mat
      RIGHT   the hatch: lift it and shut it, packages go in there

    For every package: it slides to the front of the mat, you drag buds from the tray into it,
    zip the baggie (or drag the lid onto the jar), then drag it to the hatch. The hatch lifts
    by itself when a package comes close, the package drops in and the hatch shuts again.
    You can click the hatch any time to lift or shut it yourself.

    The server pays out only the packages that actually went into the hatch.
]]

Packaging = {}

local P = Config.Props

local function lerp(a, b, t) return a + (b - a) * t end
local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function scene(S, o, kind, n, per, bud)
    local c = Config.Equipment.packstation
    local A = c.anchors
    local I = Interact
    local heading = S.heading
    local budModel = P.bud[bud] or P.bud.green
    local top = I.anchor(S, 'tray').z
    local liftZ = top + 0.16

    --[[ tray: one bud per unit ]]
    local tray = {}
    local cols, rows = c.tray.cols, c.tray.rows
    for i = 1, n * per do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols) % rows
        local lx = (col - (cols - 1) / 2) * (c.tray.size.x / (cols - 1))
        local ly = (row - (rows - 1) / 2) * (c.tray.size.y / (rows - 1))
        local home = Util.off(S.ent, A.tray + vec3(lx, ly, 0.012))
        local e = I.spawn(S, budModel, home, heading + math.random(0, 359), P.budFallback)
        if e then SetEntityRotation(e, 90.0, 0.0, heading + math.random(0, 359), 2, true) SetEntityCoordsNoOffset(e, home.x, home.y, home.z, false, false, false) end
        tray[#tray + 1] = { e = e, p = home, home = home }
    end

    --[[ the line-up: baggies or jars in a row (and the jar lids next to the work spot) ]]
    local step = c.lineupStep[kind]
    local line = {}
    for i = 1, n do
        local spot = Util.off(S.ent, A.lineup + vec3((i - 1) * step, 0.0, 0.0))
        local e = kind == 'jar'
            and I.spawn(S, P.jar, spot, heading, P.jarFallback)
            or I.spawn(S, P.baggie, spot, heading, P.baggieFallback)
        line[i] = { e = e, p = spot, contents = {} }
    end
    local lids = {}
    if kind == 'jar' then
        for i = 1, n do
            local spot = Util.off(S.ent, A.lid + vec3((i - 1) * 0.055 - 0.03, 0.06 * ((i - 1) % 2), 0.0))
            lids[i] = { e = I.spawn(S, P.jarLid, spot, heading, false), p = spot, home = spot }
        end
    end

    --[[ hatch: animated toward a target angle every frame ]]
    local H = { ent = o.hatch, angle = 0.0, target = 0.0, open = c.hatch.open, auto = false }
    local function hatchUpdate()
        if not H.ent or not DoesEntityExist(H.ent) then return end
        local speed = 260.0 * S.dt
        if math.abs(H.target - H.angle) > 0.01 then
            if H.target < H.angle then H.angle = math.max(H.target, H.angle - speed) else H.angle = math.min(H.target, H.angle + speed) end
            SetEntityRotation(H.ent, H.angle, 0.0, heading, 2, true)
            if H.angle == H.target then PlaySoundFrontend(-1, H.target == 0.0 and 'CLOSE_WINDOW' or 'OPEN_WINDOW', 'LESTER1A_SOUNDS', true) end
        end
    end
    local function hatchHandle()
        if not H.ent or not DoesEntityExist(H.ent) then return Util.off(S.ent, A.hatch) end
        return Util.off(H.ent, vec3(0.0, -0.43, 0.02))
    end
    local function hatchIsOpen() return H.angle <= H.open * 0.85 end
    local function hatchClick()
        if S.pressed and I.pxTo(S, hatchHandle()) < 46 then
            H.target = H.target == 0.0 and H.open or 0.0
            H.auto = false
            return true
        end
        return false
    end
    -- every frame of the scene: hatch animation + the hatch handle marker
    local function tick()
        hatchUpdate()
        I.marker(28, hatchHandle(), 0.02, { 8, 175, 162 }, 120)
    end

    local function moveWith(item, p)
        SetEntityCoordsNoOffset(item.e, p.x, p.y, p.z, false, false, false)
        item.p = p
        for _, cnt in ipairs(item.contents) do
            local q = p + cnt.off
            SetEntityCoordsNoOffset(cnt.e, q.x, q.y, q.z, false, false, false)
        end
        if item.lid then SetEntityCoordsNoOffset(item.lid, p.x, p.y, p.z + 0.104, false, false, false) end
    end

    local function slideItem(item, to, ms)
        local from = item.p
        local t0 = GetGameTimer()
        while true do
            local k = math.min(1.0, (GetGameTimer() - t0) / ms)
            local e = 1.0 - (1.0 - k) * (1.0 - k)
            moveWith(item, vec3(lerp(from.x, to.x, e), lerp(from.y, to.y, e), lerp(from.z, to.z, e)))
            if not I.frame(S) then return false end
            tick()
            if k >= 1.0 then return true end
            Wait(0)
        end
    end

    local work = Util.off(S.ent, A.work)
    local hatchAt = Util.off(S.ent, A.hatch)
    local done = 0

    for i = 1, n do
        local item = line[i]
        if not item.e then return done end
        S.lastHint = nil
        I.hint(S, ('Package %d of %d'):format(i, n))
        if not slideItem(item, work, 420) then return done end

        --[[ 1. fill: drag buds from the tray into the container ]]
        local filled = 0
        while filled < per do
            if not I.frame(S) then return done end
            tick()
            I.hint(S, kind == 'jar' and 'Drag the buds into the jar' or 'Drag a bud into the baggie', nil, ('%d/%d'):format(filled, per))
            I.marker(25, item.p + vec3(0.0, 0.0, 0.005), 0.12, { 8, 175, 162 }, 120)
            if not hatchClick() and S.pressed then
                local b = I.pick(S, tray, 36)
                if b then
                    -- carry it
                    local over = false
                    while S.down do
                        if not I.frame(S) then return done end
                        tick()
                        local p = I.cursorOn(S, liftZ, S.origin, 0.9)
                        if p then
                            SetEntityCoordsNoOffset(b.e, p.x, p.y, p.z, false, false, false)
                            b.p = p
                            over = flat(p, item.p) < 0.07
                            I.marker(25, item.p + vec3(0.0, 0.0, 0.005), 0.12, over and { 63, 185, 80 } or { 8, 175, 162 }, 170)
                        end
                        Wait(0)
                    end
                    if over then
                        local off = kind == 'jar'
                            and vec3(math.cos(filled * 1.3) * 0.016, math.sin(filled * 1.3) * 0.016, 0.006 + filled * 0.014)
                            or vec3(0.0, 0.0, 0.03)
                        I.slide(S, b.e, b.p, item.p + off, 220)
                        if kind ~= 'jar' then SetEntityRotation(b.e, 0.0, 90.0, heading, 2, true) end
                        b.done = true
                        item.contents[#item.contents + 1] = { e = b.e, off = off }
                        filled = filled + 1
                        PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                    else
                        I.slide(S, b.e, b.p, b.home, 220)
                        b.p = b.home
                    end
                end
            end
            Wait(0)
        end

        --[[ 2. close it: zip the baggie / drag the lid onto the jar ]]
        if kind == 'jar' then
            local lid = lids[i]
            local closed = false
            while not closed do
                if not I.frame(S) then return done end
                tick()
                I.hint(S, 'Drag the lid onto the jar')
                local jarTop = item.p + vec3(0.0, 0.0, 0.104)
                I.marker(28, lid.p + vec3(0.0, 0.0, 0.03), 0.03, { 255, 255, 255 }, 160)
                if not hatchClick() and S.pressed and lid.e and I.pxTo(S, lid.p) < 40 then
                    local over = false
                    while S.down do
                        if not I.frame(S) then return done end
                        tick()
                        local p = I.cursorOn(S, liftZ, S.origin, 0.9)
                        if p then
                            SetEntityCoordsNoOffset(lid.e, p.x, p.y, p.z, false, false, false)
                            lid.p = p
                            over = flat(p, jarTop) < 0.06
                            I.marker(25, jarTop + vec3(0.0, 0.0, 0.02), 0.1, over and { 63, 185, 80 } or { 8, 175, 162 }, 170)
                        end
                        Wait(0)
                    end
                    if over then
                        I.slide(S, lid.e, lid.p, jarTop, 180)
                        -- a quick twist
                        for a = 0, 180, 30 do
                            SetEntityRotation(lid.e, 0.0, 0.0, heading + a, 2, true)
                            if not I.frame(S) then return done end
                            Wait(0)
                        end
                        item.lid = lid.e
                        closed = true
                        PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                    else
                        I.slide(S, lid.e, lid.p, lid.home, 200)
                        lid.p = lid.home
                    end
                end
                Wait(0)
            end
        else
            S.lastHint = nil
            if not I.step.cut(S, { text = 'Click and drag along the top to zip the baggie', anchor = 'work', at = vec3(0.0, 0.0, 0.094), width = 0.07, zip = true }) then return done end
            local sealed = I.spawn(S, P.baggieSealed, item.p, heading, P.baggieFallback)
            if sealed then
                Util.delete(item.e)
                item.e = sealed
            end
            for _, cnt in ipairs(item.contents) do cnt.off = vec3(0.0, 0.0, 0.032) end
            moveWith(item, item.p)
        end

        --[[ 3. into the hatch: it lifts by itself when the package gets close ]]
        local dropped = false
        while not dropped do
            if not I.frame(S) then return done end
            tick()
            I.hint(S, 'Drag the package into the hatch')
            I.marker(25, hatchAt - vec3(0.0, 0.0, 0.16), 0.3, { 8, 175, 162 }, 90)
            if not hatchClick() and S.pressed and I.pxTo(S, item.p + vec3(0.0, 0.0, 0.05)) < 48 then
                local overHatch = false
                while S.down do
                    if not I.frame(S) then return done end
                    tick()
                    local p = I.cursorOn(S, liftZ + 0.05, S.origin, 0.95)
                    if p then
                        moveWith(item, p)
                        local d = flat(p, hatchAt)
                        if d < 0.24 and H.target == 0.0 then H.target, H.auto = H.open, true end
                        if d > 0.36 and H.auto and H.target ~= 0.0 then H.target, H.auto = 0.0, false end
                        overHatch = d < 0.14 and hatchIsOpen()
                        I.marker(25, hatchAt - vec3(0.0, 0.0, 0.16), 0.3, overHatch and { 63, 185, 80 } or { 8, 175, 162 }, 150)
                    end
                    Wait(0)
                end
                if overHatch then
                    -- drop it in, let the hatch fall shut
                    if not slideItem(item, hatchAt, 160) then return done end
                    local chute = Util.off(S.ent, A.chute)
                    if not slideItem(item, chute, 260) then return done end
                    Util.delete(item.e)
                    if item.lid then Util.delete(item.lid) end
                    for _, cnt in ipairs(item.contents) do Util.delete(cnt.e) end
                    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                    H.target, H.auto = 0.0, false
                    done = done + 1
                    dropped = true
                else
                    if H.auto then H.target, H.auto = 0.0, false end
                    if not slideItem(item, work, 220) then return done end
                end
            end
            Wait(0)
        end
    end

    -- let the hatch finish closing
    local t0 = GetGameTimer()
    while H.angle ~= 0.0 and GetGameTimer() - t0 < 800 do
        H.target = 0.0
        if not I.frame(S) then break end
        hatchUpdate()
        Wait(0)
    end
    return done
end

function Packaging.start(o)
    local data = lib.callback.await('nzwl:panel:open', false, o.data.id)
    if not data then return end
    local pick = UI.panel('pack', data)
    if not pick or not pick.pid then return end
    local kind = pick.kind == 'jar' and 'jar' or 'baggie'
    local n = math.max(1, math.floor(tonumber(pick.n) or 1))
    local ok, extra = lib.callback.await('nzwl:st:claim', false, 'pack', o.data.id, { pid = pick.pid, q = pick.q, kind = kind, n = n })
    if not ok then
        if extra then UI.notify(extra, 'error') end
        return
    end
    local cfg = Config.Equipment.packstation
    local done = Interact.scene({ entity = o.ent, cfg = cfg }, function(S)
        return scene(S, o, kind, n, extra.per, extra.bud)
    end) or 0
    if o.hatch and DoesEntityExist(o.hatch) then SetEntityRotation(o.hatch, 0.0, 0.0, o.data.h, 2, true) end
    if done < 1 then
        lib.callback.await('nzwl:st:cancel', false)
        return
    end
    local fin, res = lib.callback.await('nzwl:st:finish', false, { done = done })
    if fin then
        UI.notify(('Packaged %d %s'):format(res or done, kind == 'jar' and ((res or done) == 1 and 'jar' or 'jars') or ((res or done) == 1 and 'baggie' or 'baggies')), 'success')
    elseif res then
        UI.notify(res, 'error')
    end
end
