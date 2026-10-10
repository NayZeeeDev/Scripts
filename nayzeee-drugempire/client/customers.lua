--[[ Deals and samples on the street: blips, customer peds walking up, the hand-over ]]

Customers = {}

local meets = {}   -- key -> { kind = 'deal'|'sample', data, blip, point, ped, target }

local function giveAnim(ped)
    local dict = 'mp_common'
    lib.requestAnimDict(dict)
    TaskPlayAnim(cache.ped, dict, 'givetake1_a', 8.0, -8.0, 2000, 49, 0, false, false, false)
    if ped and DoesEntityExist(ped) then
        TaskPlayAnim(ped, dict, 'givetake1_b', 8.0, -8.0, 2000, 49, 0, false, false, false)
    end
    RemoveAnimDict(dict)
end

local function leave(m)
    local ped = m.ped
    m.ped = nil
    if m.target then Target.removeEntity(m.target) m.target = nil end
    if ped and DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        SetTimeout(12000, function() Util.delete(ped) end)
    end
end

local function cleanup(m)
    Util.removeBlip(m.blip)
    if m.point then m.point:remove() end
    if m.target then Target.removeEntity(m.target) end
    Util.delete(m.ped)
end

local function handover(m)
    local stock = lib.callback.await('nzde:cust:stock', false) or {}
    local d = m.data
    local cfg = Config.Customers[d.cid] or {}
    local pick = UI.panel('give', {
        mode = m.kind, name = d.name, standards = cfg.standards, favorites = cfg.favorites,
        want = m.kind == 'deal' and { product = d.product, qty = d.qty } or nil, stock = stock,
    })
    if not pick or not pick.pid then return end
    if m.kind == 'deal' then
        local ok, res = lib.callback.await('nzde:deal:handover', false, d.id, pick.q)
        if not ok then return UI.notify(res or 'They didn\'t take it', 'error') end
        giveAnim(m.ped)
        UI.notify(('%s paid %s'):format(res.name, Utils.money(res.price)), res.happy and 'success' or 'warning', 6000, 'Deal done')
        PlaySoundFrontend(-1, 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET', true)
    else
        local ok, res = lib.callback.await('nzde:cust:sample', false, pick.pid, pick.q)
        if not ok then return UI.notify(res or 'They didn\'t take it', 'error') end
        giveAnim(m.ped)
        if res.ok then
            UI.notify(('%s liked it. New customer!'):format(res.name), 'success', 7000, 'Sample')
        else
            UI.notify(('%s wasn\'t impressed. Try again later with something better.'):format(res.name), 'warning', 7000, 'Sample')
        end
    end
    Wait(1500)
    leave(m)
end

local function spawnPed(m, coords)
    if m.ped then return end
    local d = m.data
    m.ped = Util.ped(d.model or 'a_m_y_hippy_01', coords, 'WORLD_HUMAN_SMOKING')
    m.target = Target.addEntity(m.ped, {
        { name = 'nzde_meet', label = m.kind == 'deal' and ('Hand over %dx %s'):format(d.qty, d.product) or 'Offer a free sample',
          icon = 'fa-solid fa-handshake', distance = Config.Deals.handoverDistance,
          canInteract = function() return not LocalPlayer.state.nzdeBusy end,
          onSelect = function() handover(m) end },
    })
end

local function open(key, kind, data, spotId)
    local spot = Config.Spots[spotId]
    if not spot then return end
    local c = spot.coords
    local m = { kind = kind, data = data }
    m.blip = Util.blip(c, { sprite = kind == 'deal' and 500 or 280, color = kind == 'deal' and 2 or 5, scale = 0.85 },
        kind == 'deal' and ('Deal: %s'):format(data.name) or ('Sample: %s'):format(data.name), false)
    m.point = lib.points.new({
        coords = vec3(c.x, c.y, c.z), distance = Config.Deals.spawnDistance,
        onEnter = function() spawnPed(m, c) end,
        onExit = function() if m.target then Target.removeEntity(m.target) m.target = nil end Util.delete(m.ped) m.ped = nil end,
    })
    meets[key] = m
end

--- reconcile with the server state
function Customers.refresh(st)
    local want = {}
    for _, d in ipairs(st.deals or {}) do want['d:' .. d.id] = { 'deal', d, d.spot } end
    if st.sample then
        local s = st.sample
        want['s:' .. s.cid] = { 'sample', { cid = s.cid, name = s.name, model = s.model }, s.spot }
    end
    for key, m in pairs(meets) do
        if not want[key] then
            cleanup(m)
            meets[key] = nil
        end
    end
    for key, w in pairs(want) do
        if not meets[key] then open(key, w[1], w[2], w[3]) end
    end
end

--- route to a deal from the phone
function Customers.route(spotId)
    local s = Config.Spots[spotId]
    if s then SetNewWaypoint(s.coords.x, s.coords.y) end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, m in pairs(meets) do cleanup(m) end
end)
