--[[
    Equipment inside the RV: props, growth visuals, labels, target options and actions.
    Everything here only exists while you're inside your RV.
]]

Stations = {}

local objs = {}          -- id -> { data, ent, pot, plant, lid, target }
local skew = 0           -- server time - local cloud time
local labelThread = false

local function now() return Utils.now() + skew end

function Stations.objects()
    local out = {}
    for id, o in pairs(objs) do out[id] = o.data end
    return out
end

local function cfgOf(o) return Config.Stations[o.data.type] end
local function potLike(o) return o.data.type == 'pot' or o.data.type == 'tent' end

local function boostOf(o)
    local c = cfgOf(o)
    if c.boost then return c.boost end
    for _, other in pairs(objs) do
        if other.data.type == 'light' then
            local dx, dy = other.data.x - o.data.x, other.data.y - o.data.y
            if dx * dx + dy * dy <= Config.Grow.lightRadius ^ 2 then return Config.Grow.lightBoost end
        end
    end
    return 1.0
end

local function view(o)
    if potLike(o) or o.data.type == 'bed' then return Grow.view(o.data.st, now(), boostOf(o)) end
    return o.data.st
end

local function worldPos(d) return Util.rel(RV.origin, d) end

--[[ ─────────────── visuals ─────────────── ]]

local function potEntity(o) return o.pot or o.ent end

local function refreshVisual(o)
    local d, c = o.data, cfgOf(o)
    local st = view(o)
    local base = worldPos(d)
    if potLike(o) then
        -- pot model: empty / with soil
        local want = (st.soil or 0) > 0 and Config.GrowProps.soil or (d.type == 'tent' and c.fallback or c.model)
        if d.type == 'tent' then
            if o.potModel ~= want then
                Util.delete(o.pot)
                local p = GetOffsetFromEntityInWorldCoords(o.ent, c.potOffset.x, c.potOffset.y, c.potOffset.z)
                o.pot = Util.prop(want, p, d.h, { fallback = 'bkr_prop_weed_bucket_01a' })
                o.potModel = want
            end
        elseif o.potModel ~= want then
            Util.delete(o.ent)
            o.ent = Util.prop(want, base, d.h, { fallback = c.model })
            o.potModel = want
            Stations.target(o)
        end
    end
    if potLike(o) or d.type == 'bed' then
        local stage = Grow.stage(st)
        local crop = st.crop or 'weed'
        local list = Config.GrowProps[crop] or Config.GrowProps.weed
        local want = stage > 0 and list[math.min(stage, 3)] or nil
        if o.plantModel ~= want then
            Util.delete(o.plant)
            o.plant = nil
            if want then
                local pe = potEntity(o)
                local p = GetOffsetFromEntityInWorldCoords(pe, 0.0, 0.0, d.type == 'bed' and (c.top - 0.05) or 0.05)
                o.plant = Util.prop(want, p, d.h, { noCollision = true, fallback = false })
            end
            o.plantModel = want
        end
    end
end

local function spawnObj(d)
    local c = Config.Stations[d.type]
    if not c then return end
    local o = { data = d }
    o.ent = Util.prop(c.model, worldPos(d), d.h, { fallback = c.fallback })
    if d.type == 'pot' then o.potModel = c.model end
    if d.type == 'packer' and c.lid and GetEntityModel(o.ent) == joaat(c.model) then
        local l = c.lid.offset
        local lp = GetOffsetFromEntityInWorldCoords(o.ent, l.x, l.y, l.z)
        o.lid = Util.prop(c.lid.model, lp, d.h, { fallback = false })
    end
    objs[d.id] = o
    refreshVisual(o)
    Stations.target(o)
end

local function despawnObj(o)
    if o.target then Target.removeEntity(o.target) end
    Util.delete(o.plant)
    Util.delete(o.pot)
    Util.delete(o.lid)
    Util.delete(o.ent)
end

--[[ ─────────────── labels ─────────────── ]]

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
    if s >= 60 then return ('%dm %02ds'):format(math.floor(s / 60), s % 60) end
    return ('%ds'):format(s)
end

local function drawLabel(o, pc)
    local d, c = o.data, cfgOf(o)
    local st = view(o)
    local top = worldPos(d) + vec3(0.0, 0.0, (c.top or 0.5) + 0.12)
    if #(pc - top) > Config.UI.labels.distance then return false end
    local line, col = nil, { 242, 244, 245 }
    if potLike(o) or d.type == 'bed' then
        if (st.soil or 0) <= 0 then
            line, col = d.type == 'bed' and 'NEEDS SUBSTRATE' or 'NEEDS SOIL', { 229, 165, 10 }
        elseif not st.seed then
            line, col = 'EMPTY', { 158, 165, 170 }
        elseif Grow.stage(st) == 4 then
            line, col = 'READY TO HARVEST', { 15, 212, 196 }
        elseif (st.water or 0) <= 0 then
            line, col = 'NEEDS WATER', { 229, 72, 77 }
        else
            line = ('GROWING %d%%  ·  %s'):format(math.floor((st.growth or 0) * 100), fmtTime(Grow.eta(st, boostOf(o))))
        end
        local x, y = text3d(top, line, col[1], col[2], col[3], 0.32)
        if x and (st.soil or 0) > 0 then
            -- water bar
            local w = 0.05
            DrawRect(x, y - 0.006, w + 0.002, 0.008, 0, 0, 0, 170)
            local f = st.water or 0
            DrawRect(x - w / 2 + (w * f) / 2, y - 0.006, w * f, 0.005, f > 0 and 88 or 229, f > 0 and 166 or 72, f > 0 and 255 or 77, 230)
        end
        return true
    end
    if st.busy and st.done then
        local left = st.done - now()
        if left > 0 then
            text3d(top, ('%s  ·  %s'):format(c.label:upper(), fmtTime(left)), 242, 244, 245, 0.3)
        else
            text3d(top, 'READY', 15, 212, 196, 0.32)
        end
        return true
    end
    if d.type == 'rack' and st.slots and #st.slots > 0 then
        local ready = 0
        for _, s in ipairs(st.slots) do if s.done <= now() then ready = ready + 1 end end
        text3d(top, ('DRYING  ·  %d/%d ready'):format(ready, #st.slots), 242, 244, 245, 0.3)
        return true
    end
    return false
end

local function startLabels()
    if labelThread then return end
    labelThread = true
    CreateThread(function()
        local lastVisual = 0
        while RV.inside do
            local pc = GetEntityCoords(cache.ped)
            local any = false
            if not Interact.active then
                for _, o in pairs(objs) do
                    if drawLabel(o, pc) then any = true end
                end
            end
            -- growth stage swaps (sprout -> grown) every few seconds
            if GetGameTimer() - lastVisual > 4000 then
                lastVisual = GetGameTimer()
                for _, o in pairs(objs) do refreshVisual(o) end
            end
            Wait(any and 0 or 500)
        end
        labelThread = false
    end)
end

--[[ ─────────────── actions ─────────────── ]]

local function counts(items)
    return lib.callback.await('nzde:inv:counts', false, items) or {}
end

--- let the player pick one of `list` (item names) they actually carry. nil = cancelled / none
local function chooseItem(title, list)
    local names = {}
    for item in pairs(list) do names[#names + 1] = item end
    local have = counts(names)
    local options = {}
    for _, item in ipairs(names) do
        if (have[item] or 0) > 0 then options[#options + 1] = { item = item, label = Utils.itemLabel(item), n = have[item] } end
    end
    if #options == 0 then return nil, 'none' end
    if #options == 1 then return options[1].item end
    table.sort(options, function(a, b) return a.label < b.label end)
    local pick = UI.panel('choose', { title = title, options = options })
    return pick and pick.item
end

local function run(o, action, args, ctx, entity, cfg)
    local ok, extra = lib.callback.await('nzde:st:claim', false, action, o and o.data.id, args or {})
    if not ok then
        if extra then UI.notify(extra, 'error') end
        return false
    end
    ctx = ctx or {}
    ctx.count = type(extra) == 'table' and extra.count or nil
    local done = Interact.run({ entity = entity or potEntity(o), cfg = cfg or cfgOf(o), steps = Config.Actions[action].steps, ctx = ctx })
    if not done then
        lib.callback.await('nzde:st:cancel', false)
        return false
    end
    local fin, err = lib.callback.await('nzde:st:finish', false)
    if not fin then UI.notify(err or 'That didn\'t work', 'error') end
    return fin
end

-- pots + tents use the pot's camera; a tent pot is framed by the tent's own camera
local function potCfg(o)
    local c = cfgOf(o)
    if o.data.type ~= 'tent' then return c end
    return { cam = c.cam, top = c.top, anchors = c.anchors }
end

local function potAction(o, action, args)
    return run(o, action, args, nil, potEntity(o), potCfg(o))
end

local A = {}

function A.soil(o)
    local item, why = chooseItem('Pick a soil', Config.Grow.soils)
    if not item then if why then UI.notify('You need soil', 'error') end return end
    potAction(o, o.data.type == 'bed' and 'bed_fill' or 'pot_soil', { item = item })
end

function A.seed(o)
    local item, why = chooseItem('Pick a seed', Config.Grow.seeds)
    if not item then if why then UI.notify('You need a seed', 'error') end return end
    potAction(o, 'pot_seed', { item = item })
end

function A.water(o)
    potAction(o, o.data.type == 'bed' and 'bed_mist' or 'pot_water')
end

function A.additive(o)
    local item, why = chooseItem('Pick an additive', Config.Grow.additives)
    if not item then if why then UI.notify('You have no additives', 'error') end return end
    potAction(o, 'pot_additive', { item = item })
end

function A.harvest(o)
    potAction(o, o.data.type == 'bed' and 'bed_harvest' or 'pot_harvest')
end

function A.pickup(o)
    local ok, err = lib.callback.await('nzde:rv:pickup', false, o.data.id)
    if not ok and err then UI.notify(err, 'error') end
end

function A.collect(o)
    local ok, err = lib.callback.await('nzde:st:collect', false, o.data.id)
    if not ok and err then UI.notify(err, 'error') end
    if ok then UI.notify('Collected', 'success') end
end

function A.timed(o, action)
    run(o, action)
end

function A.oven(o)
    local have = counts({ Config.Processing.oven.meth.input, Config.Processing.oven.coke.input })
    local opts = {}
    if (have[Config.Processing.oven.meth.input] or 0) > 0 then opts[#opts + 1] = { item = 'meth', label = 'Bake liquid meth', n = have[Config.Processing.oven.meth.input] } end
    if (have[Config.Processing.oven.coke.input] or 0) > 0 then opts[#opts + 1] = { item = 'coke', label = 'Bake coca base', n = have[Config.Processing.oven.coke.input] } end
    if #opts == 0 then UI.notify('You need liquid meth or coca base', 'error') return end
    local mode = opts[1].item
    if #opts > 1 then
        local pick = UI.panel('choose', { title = 'Lab oven', options = opts })
        if not pick then return end
        mode = pick.item
    end
    run(o, 'oven_load', { mode = mode })
end

function A.smash(o)
    run(o, 'oven_smash')
end

-- packaging bench: choose what to pack, then the first package by hand
function A.pack(o)
    local data = lib.callback.await('nzde:panel:open', false, o.data.id)
    if not data then return end
    local pick = UI.panel('pack', data)
    if not pick or not pick.pid then return end
    local kind = pick.kind == 'jar' and 'jar' or 'baggie'
    local c = cfgOf(o)
    local P = Config.PackProps
    local bagAt = GetOffsetFromEntityInWorldCoords(o.ent, c.anchors.bag.x, c.anchors.bag.y, c.anchors.bag.z)
    local sceneEnt = kind == 'jar'
        and Util.prop(P.jar, bagAt, o.data.h, { noCollision = true, fallback = P.jarFallback })
        or Util.prop(P.bag, bagAt, o.data.h, { noCollision = true, fallback = P.bagFallback })
    local n = math.max(1, math.floor(pick.n or 1))
    local ctx = {
        lid = o.lid,
        scene = { bag = sceneEnt, jar = sceneEnt },
        after = function(S)
            -- the rest of the batch plays out on its own: lid up, package in, lid down
            if n <= 1 then return true end
            local drawer = Interact.anchor(S, 'drawer')
            for i = 2, n do
                Interact.hint(S, ('Packing %d/%d'):format(i, n))
                local e = Interact.spawn(S, kind == 'jar' and P.jar or P.bag, bagAt, o.data.h, kind == 'jar' and P.jarFallback or P.bagFallback)
                Wait(250)
                Interact.lidTo(S, true)
                if e and not Interact.slide(S, e, bagAt + vec3(0.0, 0.0, 0.12), drawer, 380) then return false end
                Util.delete(e)
                Interact.lidTo(S, false)
            end
            return true
        end,
    }
    run(o, 'pack_' .. kind, { item = pick.item, pid = pick.pid, q = pick.q, n = n }, ctx)
    Util.delete(sceneEnt)
end

-- drying rack + mixing station: panels that talk to the server directly
local openPanelObj

function A.rack(o)
    local data = lib.callback.await('nzde:panel:open', false, o.data.id)
    if not data then return end
    openPanelObj = o
    UI.panel('rack', data)
    openPanelObj = nil
end

function A.mix(o)
    local data = lib.callback.await('nzde:panel:open', false, o.data.id)
    if not data then return end
    openPanelObj = o
    UI.panel('mix', data)
    openPanelObj = nil
end

RegisterNUICallback('rack:add', function(d, cb)
    if not openPanelObj then return cb(false) end
    local ok, res = lib.callback.await('nzde:panel:rackAdd', false, openPanelObj.data.id, d.what, d.n)
    if not ok and res then UI.notify(res, 'error') end
    cb(ok and res or false)
end)

RegisterNUICallback('rack:take', function(d, cb)
    if not openPanelObj then return cb(false) end
    local ok, res = lib.callback.await('nzde:panel:rackTake', false, openPanelObj.data.id, d.idx)
    if not ok and res then UI.notify(res, 'error') end
    cb(ok and res or false)
end)

RegisterNUICallback('mix:go', function(d, cb)
    if not openPanelObj then return cb(false) end
    local ok, res = lib.callback.await('nzde:panel:mix', false, openPanelObj.data.id, d.item, d.pid, d.q, d.ingredient, d.n)
    if not ok and res then UI.notify(res, 'error') end
    cb(ok and res or false)
end)

--[[ ─────────────── target options ─────────────── ]]

local function st(o) return view(o) end

local function opt(name, label, icon, fn, can)
    return { name = 'nzde_' .. name, label = label, icon = icon, distance = 2.2, onSelect = fn, canInteract = can }
end

function Stations.target(o)
    if o.target then Target.removeEntity(o.target) o.target = nil end
    if not o.ent or not DoesEntityExist(o.ent) then return end
    local t, list = o.data.type, {}
    local function busy() return LocalPlayer.state.nzdeBusy end
    if t == 'pot' or t == 'tent' then
        list = {
            opt('soil', 'Add soil', 'fa-solid fa-trowel', function() A.soil(o) end, function() return not busy() and (st(o).soil or 0) <= 0 end),
            opt('seed', 'Plant a seed', 'fa-solid fa-seedling', function() A.seed(o) end, function() local s = st(o) return not busy() and (s.soil or 0) > 0 and not s.seed end),
            opt('water', 'Water', 'fa-solid fa-droplet', function() A.water(o) end, function() local s = st(o) return not busy() and (s.soil or 0) > 0 and (s.water or 0) < 0.9 end),
            opt('additive', 'Use an additive', 'fa-solid fa-flask', function() A.additive(o) end, function() local s = st(o) return not busy() and s.seed and (s.growth or 0) < 1 end),
            opt('harvest', 'Harvest', 'fa-solid fa-scissors', function() A.harvest(o) end, function() return not busy() and Grow.stage(st(o)) == 4 end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and not st(o).seed end),
        }
    elseif t == 'bed' then
        list = {
            opt('fill', 'Fill the bed', 'fa-solid fa-trowel', function() potAction(o, 'bed_fill') end, function() return not busy() and (st(o).soil or 0) <= 0 end),
            opt('mist', 'Mist', 'fa-solid fa-droplet', function() A.water(o) end, function() local s = st(o) return not busy() and (s.soil or 0) > 0 and (s.water or 0) < 0.9 end),
            opt('harvest', 'Harvest', 'fa-solid fa-hand-scissors', function() A.harvest(o) end, function() return not busy() and Grow.stage(st(o)) == 4 end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and not st(o).seed end),
        }
    elseif t == 'chem' or t == 'cauldron' or t == 'spawn' then
        local start = ({ chem = 'chem_start', cauldron = 'cauldron_start', spawn = 'spawn_start' })[t]
        local label = ({ chem = 'Start a cook', cauldron = 'Start the cauldron', spawn = 'Inject spores' })[t]
        list = {
            opt('start', label, 'fa-solid fa-fire-burner', function() A.timed(o, start) end, function() return not busy() and not st(o).busy end),
            opt('collect', 'Collect', 'fa-solid fa-box-open', function() A.collect(o) end, function() local s = st(o) return not busy() and s.busy and s.done <= now() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and not st(o).busy end),
        }
    elseif t == 'oven' then
        list = {
            opt('load', 'Load the oven', 'fa-solid fa-fire', function() A.oven(o) end, function() return not busy() and not st(o).busy end),
            opt('smash', 'Smash the meth', 'fa-solid fa-hammer', function() A.smash(o) end, function() local s = st(o) return not busy() and s.busy == 'meth' and s.done <= now() end),
            opt('collect', 'Collect cocaine', 'fa-solid fa-box-open', function() A.collect(o) end, function() local s = st(o) return not busy() and s.busy == 'coke' and s.done <= now() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and not st(o).busy end),
        }
    elseif t == 'packer' then
        list = {
            opt('pack', 'Package product', 'fa-solid fa-box', function() A.pack(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    elseif t == 'rack' then
        list = {
            opt('rack', 'Use the drying rack', 'fa-solid fa-wind', function() A.rack(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() and #(st(o).slots or {}) == 0 end),
        }
    elseif t == 'mixer' then
        list = {
            opt('mix', 'Mix', 'fa-solid fa-blender', function() A.mix(o) end, function() return not busy() end),
            opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end),
        }
    else
        list = { opt('pickup', 'Pick up', 'fa-solid fa-hand', function() A.pickup(o) end, function() return not busy() end) }
    end
    o.target = Target.addEntity(o.ent, list)
end

--[[ ─────────────── watering can at the tap ─────────────── ]]
function Stations.fillCan()
    if not RV.inside or not RV.cfg.sink or LocalPlayer.state.nzdeBusy then return end
    local tap = Util.rel(RV.origin, RV.cfg.sink)
    local base = Util.prop(Config.FallbackModel, tap - vec3(0.0, 0.0, 0.35), 0.0, { noCollision = true, fallback = false })
    if not base then return end
    SetEntityVisible(base, false, false)
    local cfg = { cam = { offset = vec3(0.0, -0.75, 0.55), look = vec3(0.0, 0.0, 0.3), fov = 48 }, top = 0.35 }
    run(nil, 'sink_fill', {}, { point = tap }, base, cfg)
    Util.delete(base)
end

--[[ ─────────────── lifecycle ─────────────── ]]
function Stations.load(list, serverNow)
    Stations.unload()
    skew = (serverNow or Utils.now()) - Utils.now()
    for _, d in pairs(list) do spawnObj(d) end
    startLabels()
end

function Stations.unload()
    for _, o in pairs(objs) do despawnObj(o) end
    objs = {}
end

RegisterNetEvent('nzde:rv:obj', function(d, removed, serverNow)
    if GetInvokingResource() or not RV.inside then return end
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
end)

RegisterNetEvent('nzde:water', function(w)
    if GetInvokingResource() then return end
    Main.water = w
end)

AddEventHandler('onResourceStop', function(res)
    if res == RES then Stations.unload() end
end)
