--[[ Delivery boxes: at dead drops once ready, or inside the RV ]]

Deliveries = {}

local drops = {}   -- order id -> { blip, point, box, target }
local rvBoxes = {} -- order id -> { box, target }

local function dropCfg(id)
    for _, d in ipairs(Config.DeadDrops) do
        if d.id == id then return d end
    end
end

local function collect(id)
    local ok, err = lib.callback.await('nzde:order:collect', false, id)
    if not ok then return UI.notify(err or 'You can\'t take that', 'error') end
    Util.anim(cache.ped, 'pickup_object', 'pickup_low', 0, 1200)
    UI.notify('Delivery collected', 'success')
end

local function spawnBox(id, a, c, exact)
    if a.box then return end
    local z = exact and c.z or Util.groundZ(c.x, c.y, c.z)
    a.box = Util.prop(Config.Deliveries.model, vec3(c.x, c.y, z), c.w or 0.0)
    if not exact then PlaceObjectOnGroundProperly(a.box) end
    a.target = Target.addEntity(a.box, {
        { name = 'nzde_drop', label = 'Collect delivery', icon = 'fa-solid fa-box-open', distance = 2.0, onSelect = function() collect(id) end },
    })
end

local function despawnBox(a)
    if a.target then Target.removeEntity(a.target) a.target = nil end
    Util.delete(a.box)
    a.box = nil
end

function Deliveries.refresh(st)
    local want = {}
    for _, o in ipairs(st.orders or {}) do
        if o.drop ~= 'rv' then want[o.id] = o.drop end
    end
    for id, a in pairs(drops) do
        if not want[id] then
            despawnBox(a)
            Util.removeBlip(a.blip)
            if a.point then a.point:remove() end
            drops[id] = nil
        end
    end
    for id, dropId in pairs(want) do
        local d = dropCfg(dropId)
        if d and not drops[id] then
            local a = {}
            a.blip = Util.blip(d.coords, Config.Deliveries.blip, 'Delivery: ' .. d.label, false)
            a.point = lib.points.new({ coords = vec3(d.coords.x, d.coords.y, d.coords.z), distance = 40.0,
                onEnter = function() spawnBox(id, a, d.coords) end, onExit = function() despawnBox(a) end })
            drops[id] = a
        end
    end
    -- orders shipped to the RV
    if RV.inside then
        local ids = {}
        for _, o in ipairs(st.orders or {}) do if o.drop == 'rv' then ids[#ids + 1] = o.id end end
        Deliveries.rvBoxes(ids)
    end
end

--- boxes by the RV door for orders shipped to the RV
function Deliveries.rvBoxes(ids)
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    for id, a in pairs(rvBoxes) do
        if not want[id] then despawnBox(a) rvBoxes[id] = nil end
    end
    if not RV.inside then return end
    local i = 0
    for id in pairs(want) do
        if not rvBoxes[id] then
            local sp = RV.cfg.spawn
            local p = Util.rel(RV.origin, vec3(sp.x + 0.6 + i * 0.45, sp.y + 0.7, RV.cfg.floor))
            local a = {}
            spawnBox(id, a, vec4(p.x, p.y, p.z, 0.0), true)
            rvBoxes[id] = a
        end
        i = i + 1
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, a in pairs(drops) do despawnBox(a) end
    for _, a in pairs(rvBoxes) do despawnBox(a) end
end)
