--[[
    Equipment inside a lab: props, growth visuals, grow lights, labels, target options and actions.
    Everything here only exists while you're inside one of your labs.
]]

Stations = {}

local objs = {}          -- id -> { data, ent, soil, plant, light, hatch, bowl, plate, lever, hung = {}, target }
local skew = 0           -- server time - local cloud time
local loopOn = false
local E, LIGHTS = Config.Equipment, Config.Lights

local function now() return Utils.now() + skew end

function Stations.objects()
    local out = {}
    for id, o in pairs(objs) do out[id] = o.data end
    return out
end

function Stations.get(id) return objs[id] end

local function cfgOf(o) return E[o.data.type] end
local function isGrow(o) return cfgOf(o).grow end

local function boostOf(o)
    local list = {}
    for id, x in pairs(objs) do list[id] = x.data end
    local c = cfgOf(o)
    if c.boost then return c.boost end
    local best, area = 1.0, E.rack.area
    for _, r in pairs(list) do
        if r.type == 'rack' and r.st.light then
            local lx, ly = Utils.rotate(o.data.x - r.x, o.data.y - r.y, -(r.h or 0.0))
            if math.abs(lx) <= area.x and math.abs(ly) <= area.y then best = math.max(best, LIGHTS[r.st.light].boost) end
        end
    end
    return best
end

local function view(o)
    if isGrow(o) then return Grow.view(o.data.st, now(), boostOf(o)) end
    return o.data.st
end

local function worldPos(d) return Util.rel(Labs.origin, d) end

--[[ ─────────────── visuals ─────────────── ]]

local function strainCfg(st) return Config.Strains[st.strain or ''] end

--- a strain's growth steps: the nextgen pack if it's streamed, otherwise the base-game plants
local sets = {}
local function plantSet(strain)
    if sets[strain] then return sets[strain] end
    local s = Config.Strains[strain]
    local list = Config.PlantModels(strain)
    local streamed = true
    for _, m in ipairs(list) do
        if not IsModelInCdimage(joaat(m)) then streamed = false break end
    end
    local set
    if streamed then
        set = { models = list, pot = (s and s.plant) and s.plantPot == true or (not (s and s.plant) and Config.Plants.includesPot), scale = 1.0 }
    else
        print(('^3[%s] plants for %s are not streamed (is nextgen_weedprops started?), using base-game plants^7'):format(RES, tostring(strain)))
        set = { models = Config.Plants.fallback, pot = false, scale = Config.Plants.fallbackScale, grows = true }
    end
    sets[strain] = set
    return set
end

--- which growth step to show (the last one = ready to harvest)
local function plantStep(st, set)
    if not st.seed then return nil end
    local n = #set.models
    local g = st.growth or 0
    if g >= 1.0 then return n end
    return math.min(n - 1, math.floor(g * (n - 1)) + 1)
end

local function plantScaleOf(o, st, set)
    local base = (cfgOf(o).plantScale or 1.0) * set.scale
    if not set.grows then return base end
    -- 3-step fallback plants also fill out a little as they grow
    local g = Utils.clamp(st.growth or 0, 0, 1)
    return base * (0.75 + 0.25 * math.min(1.0, g / 0.67))
end

local function refreshGrow(o)
    local d, c = o.data, cfgOf(o)
    local st = view(o)
    local base = worldPos(d)
    local set = st.seed and plantSet(st.strain) or nil
    local step = set and plantStep(st, set)
    local want = step and set.models[step] or nil
    local ownPot = want ~= nil and set.pot
    -- soil surface (hidden once a plant with its own pot + gravel stands there)
    local wantSoil = (st.soil or 0) > 0 and not ownPot
    if wantSoil and not o.soil then
        o.soil = Util.prop(Config.Props.soil, base + vec3(0.0, 0.0, c.soilZ), d.h, { noCollision = true, fallback = false })
    elseif not wantSoil and o.soil then
        Util.delete(o.soil) o.soil = nil
    end
    if c.hidePot and o.ent then
        local hide = ownPot == true
        if o.potHidden ~= hide then
            SetEntityVisible(o.ent, not hide, false)
            o.potHidden = hide
        end
    end
    -- the plant
    local scale = set and plantScaleOf(o, st, set) or 1.0
    if o.plantModel ~= want then
        Util.delete(o.plant)
        o.plant, o.plantTop = nil, nil
        if want then
            o.plantPos = base + vec3(0.0, 0.0, set.pot and c.plantZ or c.soilZ + 0.02)
            o.plant = Util.prop(want, o.plantPos, d.h, { noCollision = true, fallback = false, scale = scale })
        end
        o.plantModel, o.plantScale = want, scale
    elseif o.plant and math.abs((o.plantScale or 1) - scale) > 0.02 then
        Util.transform(o.plant, o.plantPos, d.h, scale)
        o.plantScale = scale
    end
    if o.plant then
        local _, mx = GetModelDimensions(GetEntityModel(o.plant))
        o.plantTop = o.plantPos.z + mx.z * (o.plantScale or 1.0)
    end
end

--- the light rides on the rack's ratchet hangers: just above the tallest plant under it
local function lightHook(o)
    local r, area = E.rack, E.rack.area
    local l = LIGHTS[o.data.st.light]
    local origin = worldPos(o.data)
    local tallest
    for _, x in pairs(objs) do
        if x.plantTop then
            local lx, ly = Utils.rotate(x.data.x - o.data.x, x.data.y - o.data.y, -(o.data.h or 0.0))
            if math.abs(lx) <= area.x and math.abs(ly) <= area.y then tallest = math.max(tallest or 0, x.plantTop) end
        end
    end
    local z = r.hangMin
    if tallest then z = (tallest - origin.z) + 0.06 + (l.drop or 0.4) end
    return Utils.clamp(z, r.hangMin, r.hang.z)
end

local function refreshRack(o)
    local d = o.data
    local want = d.st.light and LIGHTS[d.st.light].model or nil
    if o.lightModel ~= want then
        Util.delete(o.light)
        o.light, o.hookZ = nil, nil
        if want then
            o.light = Util.prop(want, Util.off(o.ent, E.rack.hang), d.h, { noCollision = true, fallback = 'prop_worklight_03b' })
        end
        o.lightModel = want
    end
    if o.light then
        local z = lightHook(o)
        if not o.hookZ or math.abs(o.hookZ - z) > 0.01 then
            o.hookZ = z
            local p = Util.off(o.ent, vec3(0.0, 0.0, z))
            SetEntityCoordsNoOffset(o.light, p.x, p.y, p.z, false, false, false)
        end
    end
end

local function refreshDry(o)
    local slots = o.data.st.slots or {}
    o.hung = o.hung or {}
    for i, anchorPos in ipairs(E.dryrack.slots) do
        local s = slots[i]
        local want = s and (Config.Props.bud[s.bud or 'green'] or Config.Props.bud.green) or nil
        local cur = o.hung[i]
        if (cur and cur.model) ~= want then
            if cur then Util.delete(cur.ent) end
            o.hung[i] = nil
            if want then
                local p = Util.off(o.ent, anchorPos) - vec3(0.0, 0.0, 0.0)
                local e = Util.prop(want, p, o.data.h, { noCollision = true, fallback = Config.Props.budFallback })
                if e then SetEntityRotation(e, 180.0, 0.0, o.data.h, 2, true) end
                o.hung[i] = { ent = e, model = want }
            end
        end
    end
end

local function refreshVisual(o)
    if isGrow(o) then refreshGrow(o)
    elseif o.data.type == 'rack' then refreshRack(o)
    elseif o.data.type == 'dryrack' then refreshDry(o) end
end

local function spawnParts(o)
    local c, d = cfgOf(o), o.data
    local real = GetEntityModel(o.ent) == joaat(c.model)
    if not real then return end
    for _, key in ipairs({ 'hatch', 'bowl', 'plate', 'lever' }) do
        local part = c[key]
        if part then o[key] = Util.prop(part.model, Util.off(o.ent, part.offset), d.h, { noCollision = key ~= 'hatch', fallback = false }) end
    end
end

local function spawnObj(d)
    local c = E[d.type]
    if not c then return end
    local o = { data = d }
    o.ent = Util.prop(c.model, worldPos(d), d.h, { fallback = c.fallback })
    objs[d.id] = o
    spawnParts(o)
    refreshVisual(o)
    Stations.target(o)
end

local function despawnObj(o)
    if o.target then Target.removeEntity(o.target) end
    for _, key in ipairs({ 'plant', 'soil', 'light', 'hatch', 'bowl', 'plate', 'lever', 'ent' }) do Util.delete(o[key]) end
    for _, h in pairs(o.hung or {}) do Util.delete(h.ent) end
end

--[[ ─────────────── labels + lights (one loop, only inside a lab) ─────────────── ]]

local function text3d(p, str, r, g, b, scale)
    local ok, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
    if not ok then return nil end
    SetTextScale(0.0, scale or 0.3)
    SetTextFont(4)
    SetTextColour(r, g, b, 240)
    SetTextDropshadow(2, 0, 0, 0, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
    return x, y
end

local function fmtTime(s)
    if not s then return '--' end
    if s >= 3600 then return ('%dh %02dm'):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
    if s >= 60 then return ('%dm %02ds'):format(math.floor(s / 60), s % 60) end
    return ('%ds'):format(s)
end

local function drawLabel(o, pc)
    local d, c = o.data, cfgOf(o)
    local top = worldPos(d) + vec3(0.0, 0.0, (c.top or 0.5) + 0.12)
    if isGrow(o) then
        local st = view(o)
        local labelAt = o.plant and (o.plantPos + vec3(0.0, 0.0, 0.25 + 0.9 * (o.plantScale or 1))) or top
        if d.type == 'tent' then labelAt = worldPos(d) + vec3(0.0, -0.45, 1.75) end
        if #(pc - labelAt) > Config.UI.labels.distance + 1.0 then return false end
        local line, col
        if (st.soil or 0) <= 0 then
            line, col = 'NEEDS SOIL', { 229, 165, 10 }
        elseif not st.seed then
            line, col = 'READY FOR A SEED', { 158, 165, 170 }
        elseif Grow.stage(st) == 4 then
            line, col = 'READY TO HARVEST', { 15, 212, 196 }
        elseif (st.water or 0) <= 0 then
            line, col = 'NEEDS WATER', { 229, 72, 77 }
        else
            local s = strainCfg(st)
            line, col = ('%s  ·  %d%%  ·  %s'):format(s and s.label:upper() or 'GROWING', math.floor((st.growth or 0) * 100), fmtTime(Grow.eta(st, boostOf(o)))), { 242, 244, 245 }
        end
        local x, y = text3d(labelAt, line, col[1], col[2], col[3], 0.32)
        if x and (st.soil or 0) > 0 then
            local w, f = 0.05, st.water or 0
            DrawRect(x, y - 0.006, w + 0.002, 0.008, 0, 0, 0, 170)
            DrawRect(x - w / 2 + (w * f) / 2, y - 0.006, w * f, 0.005, f > 0 and 88 or 229, f > 0 and 166 or 72, f > 0 and 255 or 77, 230)
            local q = Utils.quality(Grow.quality(st))
            if st.seed then text3d(labelAt - vec3(0.0, 0.0, 0.07), q.label:upper() .. (boostOf(o) > 1.0 and ('  ·  x%.2f'):format(boostOf(o)) or ''), 190, 196, 200, 0.24) end
        end
        return true
    end
    if #(pc - top) > Config.UI.labels.distance then return false end
    if d.type == 'dryrack' and d.st.slots and #d.st.slots > 0 then
        local ready, soonest = 0, nil
        for _, s in ipairs(d.st.slots) do
            local left = s.done - now()
            if left <= 0 then ready = ready + 1 else soonest = math.min(soonest or left, left) end
        end
        text3d(top, ('DRYING  ·  %d/%d dry%s'):format(ready, #d.st.slots, soonest and ('  ·  ' .. fmtTime(soonest)) or ''), 242, 244, 245, 0.3)
        return true
    end
    if d.type == 'rack' and not d.st.light then
        text3d(top - vec3(0.0, 0.0, 0.4), 'NO LIGHT', 158, 165, 170, 0.28)
        return true
    end
    return false
end

local function drawLights()
    for _, o in pairs(objs) do
        local d = o.data
        if d.type == 'rack' and d.st.light and o.light then
            local l = LIGHTS[d.st.light]
            local hook = GetEntityCoords(o.light)
            for _, r in ipairs(E.rack.ratchets) do
                local q = Util.off(o.ent, r)
                DrawLine(hook.x, hook.y, hook.z, q.x, q.y, q.z, 30, 30, 32, 255)
            end
            local p = Util.off(o.light, l.glow)
            DrawLightWithRange(p.x, p.y, p.z - 0.1, l.color[1], l.color[2], l.color[3], l.range, l.intensity)
            DrawSpotLight(p.x, p.y, p.z, 0.0, 0.0, -1.0, l.color[1], l.color[2], l.color[3], 3.5, l.intensity * 1.5, 0.0, 70.0, 1.0)
        elseif d.type == 'tent' and o.ent then
            local l = E.tent.light
            local p = Util.off(o.ent, l.offset)
            DrawLightWithRange(p.x, p.y, p.z - 0.2, l.color[1], l.color[2], l.color[3], l.range, l.intensity)
        end
    end
end

local function startLoop()
    if loopOn then return end
    loopOn = true
    CreateThread(function()
        local lastVisual = 0
        while Labs.inside do
            local pc = GetEntityCoords(cache.ped)
            if not Interact.active then
                for _, o in pairs(objs) do drawLabel(o, pc) end
            end
            drawLights()
            if GetGameTimer() - lastVisual > 4000 then
                lastVisual = GetGameTimer()
                for _, o in pairs(objs) do if isGrow(o) then refreshGrow(o) end end
                for _, o in pairs(objs) do if o.data.type == 'rack' then refreshRack(o) end end
            end
            Wait(0)
        end
        loopOn = false
    end)
end

--[[ ─────────────── actions ─────────────── ]]

local function counts(items)
    return lib.callback.await('nzwl:inv:counts', false, items) or {}
end

--- let the player pick one of `list` (item names) they carry. nil = cancelled / none
local function chooseItem(title, names)
    local have = counts(names)
    local options = {}
    for _, item in ipairs(names) do
        if (have[item] or 0) > 0 then options[#options + 1] = { item = item, label = Utils.itemLabel(item), n = have[item], level = Utils.itemLevel(item), locked = (Main.state.level or 0) < Utils.itemLevel(item) } end
    end
    if #options == 0 then return nil, 'none' end
    if #options == 1 and not options[1].locked then return options[1].item end
    table.sort(options, function(a, b) return a.label < b.label end)
    local pick = UI.panel('choose', { title = title, options = options })
    return pick and pick.item
end

local function keysOf(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    return out
end

--- claim -> first person -> finish
function Stations.run(o, action, args, ctx, entity, cfg, spin)
    local ok, extra = lib.callback.await('nzwl:st:claim', false, action, o and o.data.id, args or {})
    if not ok then
        if extra then UI.notify(extra, 'error') end
        return false
    end
    ctx = ctx or {}
    if type(extra) == 'table' then for k, v in pairs(extra) do ctx[k] = ctx[k] or v end end
    local done = Interact.run({ entity = entity or o.ent, cfg = cfg or cfgOf(o), steps = Config.Actions[action].steps, ctx = ctx, spin = spin })
    if not done then
        lib.callback.await('nzwl:st:cancel', false)
        return false
    end
    local fin, err = lib.callback.await('nzwl:st:finish', false)
    if not fin then UI.notify(err or 'That didn\'t work', 'error') end
    return fin
end
local run = Stations.run

-- pots + tents: camera on the pot, A / D spins the plant
local function potCfg(o)
    local c = cfgOf(o)
    local top = c.soilZ + 0.03
    if o.plant and o.plantTop and o.data.type == 'pot' then
        -- frame the whole plant: back off and up as it gets taller
        local h = o.plantTop - worldPos(o.data).z
        if h > 0.9 then
            return { top = top, cam = { offset = vec3(0.0, -(0.55 + h * 0.6), 0.45 + h * 0.55), look = vec3(0.0, 0.0, h * 0.55), fov = 52 } }
        end
    end
    return { cam = c.cam, top = top }
end

local function potSpin(o)
    local items = {}
    if o.data.type == 'pot' then items[#items + 1] = { ent = o.ent, pos = worldPos(o.data), heading = o.data.h } end
    if o.soil then items[#items + 1] = { ent = o.soil, pos = worldPos(o.data) + vec3(0.0, 0.0, cfgOf(o).soilZ), heading = o.data.h } end
    if o.plant then items[#items + 1] = { ent = o.plant, pos = o.plantPos, heading = o.data.h, scale = o.plantScale } end
    return { items = items }
end

local function plantCtx(o, st)
    local ctx = {}
    if o.plant then
        local mn, mx = GetModelDimensions(GetEntityModel(o.plant))
        ctx.plantHeight = mx.z * (o.plantScale or 1.0)
        ctx.plantRadius = math.min(mx.x - mn.x, mx.y - mn.y) * 0.5 * (o.plantScale or 1.0)
        ctx.plantBase = o.plantPos
        ctx.plantScale = o.plantScale
    end
    local s = strainCfg(st)
    ctx.bud = s and s.bud or 'green'
    return ctx
end

local function potAction(o, action, args)
    local st = view(o)
    return run(o, action, args, plantCtx(o, st), o.ent, potCfg(o), potSpin(o))
end

local A = {}

function A.soil(o)
    local item, why = chooseItem('Pick a soil', keysOf(Config.Grow.soils))
    if not item then if why then UI.notify('You need soil. The hardware store has it.', 'error') end return end
    potAction(o, 'pot_soil', { item = item })
end

function A.seed(o)
    local seeds = {}
    for _, id in ipairs(Config.StrainOrder) do seeds[#seeds + 1] = Config.Strains[id].seed end
    local item, why = chooseItem('Pick a seed', seeds)
    if not item then if why then UI.notify('You need a seed', 'error') end return end
    potAction(o, 'pot_seed', { item = item })
end

function A.water(o) potAction(o, 'pot_water') end

function A.additive(o, item)
    potAction(o, Config.Grow.additives[item].action, { item = item })
end

function A.harvest(o)
    local st = view(o)
    local ok, extra = lib.callback.await('nzwl:st:claim', false, 'pot_harvest', o.data.id, {})
    if not ok then if extra then UI.notify(extra, 'error') end return end
    local ctx = plantCtx(o, st)
    ctx.count, ctx.rs = extra.count, extra.rs
    local done = Interact.run({ entity = o.ent, cfg = potCfg(o), steps = Config.Actions.pot_harvest.steps, ctx = ctx, spin = potSpin(o) })
    if not done then lib.callback.await('nzwl:st:cancel', false) return end
    local fin, err = lib.callback.await('nzwl:st:finish', false)
    if fin then UI.notify(('Trimmed %d buds'):format(extra.count), 'success') elseif err then UI.notify(err, 'error') end
end

function A.pickup(o)
    local ok, err = lib.callback.await('nzwl:lab:pickup', false, o.data.id)
    if not ok and err then UI.notify(err, 'error') end
end

function A.hang(o)
    local names = {}
    for _, l in pairs(LIGHTS) do names[#names + 1] = l.item end
    local item, why = chooseItem('Hang a grow light', names)
    if not item then if why then UI.notify('You have no grow lights', 'error') end return end
    Util.anim(cache.ped, 'anim@heists@prison_heiststation@cop_reactions', 'cop_b_idle', 1, 2500)
    local ok, err = lib.callback.await('nzwl:lab:hang', false, o.data.id, item)
    if not ok and err then UI.notify(err, 'error') end
    ClearPedTasks(cache.ped)
end

function A.unhang(o)
    local ok, err = lib.callback.await('nzwl:lab:unhang', false, o.data.id)
    if not ok and err then UI.notify(err, 'error') end
end

--[[ ─────────────── target options ─────────────── ]]

local function opt(name, label, icon, fn, can)
    return { name = 'nzwl_' .. name, label = label, icon = icon, distance = 2.4, onSelect = fn, canInteract = can }
end

local function busy() return LocalPlayer.state.nzwlBusy end

function Stations.target(o)
    if o.target then Target.removeEntity(o.target) o.target = nil end
    if not o.ent or not DoesEntityExist(o.ent) then return end
    local t, list = o.data.type, {}
    local function st() return view(o) end
    if E[t].grow then
        list = {
            opt('soil', 'Add soil', 'fa-solid fa-trowel', function() A.soil(o) end, function() return not busy() and (st().soil or 0) <= 0 end),
            opt('seed', 'Plant a seed', 'fa-solid fa-seedling', function() A.seed(o) end, function() local s = st() return not busy() and (s.soil or 0) > 0 and not s.seed end),
            opt('water', 'Water', 'fa-solid fa-droplet', function() A.water(o) end, function() local s = st() return not busy() and (s.soil or 0) > 0 and (s.water or 0) < 0.9 end),
            opt('fert', 'Spray fertilizer', 'fa-solid fa-spray-can', function() A.additive(o, 'nzw_fertilizer') end,
                function() local s = st() return not busy() and s.seed and (s.growth or 0) < 1 and not (s.used and s.used.nzw_fertilizer) end),
            opt('pgr', 'Add PGR', 'fa-solid fa-flask', function() A.additive(o, 'nzw_pgr') end,
                function() local s = st() return not busy() and s.seed and (s.growth or 0) < 1 and not (s.used and s.used.nzw_pgr) end),
            opt('speed', 'Add Speed Growth', 'fa-solid fa-bolt', function() A.additive(o, 'nzw_speedgrow') end,
                function() local s = st() return not busy() and s.seed and (s.growth or 0) < 1 and not (s.used and s.used.nzw_speedgrow) end),
            opt('harvest', 'Harvest', 'fa-solid fa-scissors', function() A.harvest(o) end, function() return not busy() and Grow.stage(st()) == 4 end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and not st().seed end),
        }
    elseif t == 'rack' then
        list = {
            opt('hang', 'Hang a grow light', 'fa-solid fa-lightbulb', function() A.hang(o) end, function() return not busy() and not o.data.st.light end),
            opt('unhang', 'Take the light down', 'fa-solid fa-lightbulb', function() A.unhang(o) end, function() return not busy() and o.data.st.light ~= nil end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    elseif t == 'dryrack' then
        list = {
            opt('dry', 'Hang weed to dry', 'fa-solid fa-wind', function() Processing.dry(o) end, function() return not busy() end),
            opt('drycollect', 'Collect dry weed', 'fa-solid fa-hand-holding', function() Processing.dryCollect(o) end, function()
                if busy() then return false end
                for _, s in ipairs(o.data.st.slots or {}) do if s.done <= now() then return true end end
                return false
            end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and #(o.data.st.slots or {}) == 0 end),
        }
    elseif t == 'packstation' then
        list = {
            opt('pack', 'Package product', 'fa-solid fa-box', function() Packaging.start(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    elseif t == 'mixstation' then
        list = {
            opt('mix', 'Mix product', 'fa-solid fa-blender', function() Processing.mix(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    elseif t == 'brickpress' then
        list = {
            opt('press', 'Press a brick', 'fa-solid fa-cube', function() Processing.press(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    end
    o.target = Target.addEntity(o.ent, list)
end

--[[ ─────────────── watering can at the tap ─────────────── ]]
function Stations.fillCan()
    if not Labs.inside or not Labs.cfg.tap or busy() then return end
    local tap = Util.rel(Labs.origin, Labs.cfg.tap)
    local base = Util.prop(Config.FallbackModel, tap - vec3(0.0, 0.0, 0.35), GetEntityHeading(cache.ped), { noCollision = true, fallback = false })
    if not base then return end
    SetEntityVisible(base, false, false)
    local cfg = { cam = { offset = vec3(0.0, -0.75, 0.55), look = vec3(0.0, 0.0, 0.3), fov = 48 }, top = 0.35 }
    run(nil, 'tap_fill', {}, { point = tap }, base, cfg)
    Util.delete(base)
end

--[[ ─────────────── lifecycle ─────────────── ]]
function Stations.load(list, serverNow)
    Stations.unload()
    skew = (serverNow or Utils.now()) - Utils.now()
    for _, d in pairs(list) do spawnObj(d) end
    -- lights take their height from the plants, which are all up now
    for _, o in pairs(objs) do if o.data.type == 'rack' then refreshRack(o) end end
    startLoop()
end

function Stations.unload()
    for _, o in pairs(objs) do despawnObj(o) end
    objs = {}
end

function Stations.now() return now() end

RegisterNetEvent('nzwl:lab:obj', function(d, removed, serverNow)
    if GetInvokingResource() or not Labs.inside then return end
    if serverNow then skew = serverNow - Utils.now() end
    local o = objs[d.id]
    if removed then
        if o then despawnObj(o) objs[d.id] = nil end
        return
    end
    if o then
        o.data = d
        refreshVisual(o)
    else
        spawnObj(d)
    end
    -- a light changed: every pot's boost may have too
    if d.type == 'rack' or E[d.type].grow then
        for _, x in pairs(objs) do if isGrow(x) then refreshGrow(x) end end
        for _, x in pairs(objs) do if x.data.type == 'rack' then refreshRack(x) end end
    end
end)

RegisterNetEvent('nzwl:water', function(w)
    if GetInvokingResource() then return end
    Main.water = w
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES then Stations.unload() end
end)
