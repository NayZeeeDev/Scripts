-----------------------------------------------------------------
-- Sourcing contract runner (client side of a contract)
-----------------------------------------------------------------
Source = {}
local handlers = Client.Handlers
local C = Config.Sourcing

local function v3(t) return vec3(t.x, t.y, t.z) end

-- What the player has to be driving: the car, or the flatbed carrying it
local function ride(m)
    if m.loaded and m.carrier and m.data.scenario == 'tow' then return m.carrier end
    return m.vehicle
end

local function objective(m, text, step)
    m.objective = text
    if step then m.step = step end
    Client.Send('hud', {
        mode = 'source', label = m.data.label, rarity = m.data.rarity, objective = text, step = m.step or 'find',
        remaining = math.max(0, math.floor((m.expiresAt - GetGameTimer()) / 1000)), plate = m.data.plate,
        tracker = m.tracker, stolen = m.data.stolen, chopOnly = m.data.chopOnly, illegal = m.data.illegal,
        attack = m.lastCombat and (GetGameTimer() - m.lastCombat < 15000) or false,
    })
end

local function removeBlips(m, key)
    for k, b in pairs(m.blips) do
        if not key or k == key or (type(k) == 'string' and k:find('^' .. key)) then
            if DoesBlipExist(b) then RemoveBlip(b) end
            m.blips[k] = nil
        end
    end
end

local function cleanup(m)
    m.done = true
    Heist.Cleanup(m)
    removeBlips(m)
    for _, p in pairs(m.points) do p:remove() end
    m.points = {}
    Scenarios.Release(m.peds)
    Bridge.HideText()
    Client.Send('hud', { mode = 'none' })
    if Client.mission == m then Client.mission = nil end
end

local function reportPeds(m, list)
    local ids = Scenarios.NetIds(list)
    if #ids > 0 then lib.callback.await('nz_cargo:source:peds', false, m.id, ids) end
end
Source.Objective, Source.RemoveBlips, Source.ReportPeds = objective, removeBlips, reportPeds

-----------------------------------------------------------------
-- Break-in (locked cars)
-----------------------------------------------------------------
local function breakIn(m, veh)
    if m.busy then return end
    m.busy = true
    if not lib.callback.await('nz_cargo:source:breakin', false, m.id) then m.busy = false return end
    local ped = cache.ped
    TaskTurnPedToFaceEntity(ped, veh, 600)
    Wait(600)
    lib.requestAnimDict('veh@break_in@0h@p_m_one@')
    TaskPlayAnim(ped, 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 3.0, 3.0, -1, 49, 0, false, false, false)
    local ok = lib.skillCheck(C.SkillCheck, { 'e' })
    ClearPedTasks(ped)
    RemoveAnimDict('veh@break_in@0h@p_m_one@')
    local unlocked = lib.callback.await('nz_cargo:source:unlock', false, m.id, ok)
    if unlocked then
        m.locked = false
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleAlarm(veh, true)
        StartVehicleAlarm(veh)
        if C.WantedLevel > 0 then
            SetPlayerWantedLevel(PlayerId(), C.WantedLevel, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        end
        -- guards in range react to the alarm
        for _, g in ipairs(m.peds) do
            if DoesEntityExist(g) and IsEntityAPed(g) and not IsPedInAnyVehicle(g, false) then TaskCombatPed(g, ped, 0, 16) end
        end
    end
    m.busy = false
end

-----------------------------------------------------------------
-- Scenario setup when the player gets close to the car
-----------------------------------------------------------------
local function setup(m, veh)
    m.setup = true
    local d = m.data
    local spot = v3(d.spot)
    if Client.Control(veh, 800) then
        SetVehicleOnGroundProperly(veh)
        SetVehicleNeedsToBeHotwired(veh, false)
    end

    local sc = d.scenario
    if sc == 'impound' then
        local guards = Scenarios.Guards(spot, d.crew or nil, 'impound', d.illegal)
        for _, g in ipairs(guards) do m.peds[#m.peds + 1] = g end
        reportPeds(m, guards)
    elseif sc == 'party' then Heist.Party(m, veh, spot)
    elseif sc == 'pickpocket' then Heist.Pickpocket(m, veh, spot)
    elseif sc == 'hostile' then Heist.Hostile(m, veh, spot)
    elseif sc == 'guarded' then Heist.Guarded(m, veh, spot)
    elseif sc == 'tow' or sc == 'cargobob' then Heist.DeadCar(m, veh)
    elseif sc == 'crew' then
        -- one crew member spawns the lot guards for everyone
        if d.crewLeader then
            local guards = Scenarios.Guards(spot, d.crew, 'guarded', false)
            for _, g in ipairs(guards) do m.peds[#m.peds + 1] = g end
            reportPeds(m, guards)
        end
        objective(m, 'The lot is guarded. Break into your ' .. d.label)
    elseif sc == 'moving' then
        if Client.Control(veh, 1500) then
            m.driver = Scenarios.Driver(veh)
            if m.driver then
                m.peds[#m.peds + 1] = m.driver
                reportPeds(m, { m.driver })
            end
        end
        objective(m, 'Stop the ' .. d.label .. ' and take it')
    end

    -- break in (parked / impound, or anything when KeysOnly is off)
    if d.locked and not d.carrierNet and (not d.keysOnly) and sc ~= 'party' then
        local bp = lib.points.new({ coords = spot, distance = 4.0 })
        function bp:nearby()
            if not m.locked or m.busy or IsPedInAnyVehicle(cache.ped, false) then return end
            if #(GetEntityCoords(cache.ped) - GetEntityCoords(veh)) > 2.6 then Bridge.HideText() return end
            Bridge.ShowText(Config.Interact.KeyLabel, 'Break in')
            if IsControlJustPressed(0, Config.Interact.Key) then
                Bridge.HideText()
                CreateThread(function() breakIn(m, veh) end)
            end
        end
        function bp:onExit() Bridge.HideText() end
        m.points.breakin = bp
        if sc == 'parked' or sc == 'impound' then
            objective(m, sc == 'impound' and 'Break into the impound and take the ' .. d.label or 'Break into the ' .. d.label)
        end
    end

    -- the target blip follows the car from here (recovery jobs keep their own blips)
    if d.carrierNet then return end
    removeBlips(m, 'spot')
    local b = AddBlipForEntity(veh)
    SetBlipSprite(b, 225)
    SetBlipColour(b, 5)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.label)
    EndTextCommandSetBlipName(b)
    m.blips.target = b
end

-----------------------------------------------------------------
-- Delivery / chop
-----------------------------------------------------------------
local function deliver(m, veh)
    if m.busy then return end
    m.busy = true
    Bridge.HideText()
    veh = m.vehicle or veh
    local props = Bridge.GetProps(veh)
    Client.Fade(true)
    local res = lib.callback.await('nz_cargo:source:deliver', false, m.id, props)
    if not res then
        Client.Fade(false)
        m.busy = false
        return
    end
    cleanup(m)
    Music.Stop(true)
    Warehouse.Load(res.enter, true)
    local r = res.result
    Client.Send('banner', {
        kind = 'success', title = r.floor == 'lower' and 'Contraband Stored' or 'Vehicle Sourced', subtitle = r.label, rarity = r.rarity,
        stats = { { 'Condition', r.condition .. '%' }, { 'XP', '+' .. r.xp }, { 'Time', Cargo.FormatTime(r.time) } },
    })
    Bridge.Notify(L('src_delivered', r.label, r.condition), 'success', 'Vehicle Cargo')
end

local function chop(m, veh)
    if m.busy then return end
    m.busy = true
    Bridge.HideText()
    local done = lib.progressBar({ duration = 7000, label = 'Stripping the car', canCancel = true, disable = { car = true, move = true, combat = true } })
    if not done then m.busy = false return end
    local res = lib.callback.await('nz_cargo:source:chop', false, m.id)
    if not res then m.busy = false return end
    TaskLeaveVehicle(cache.ped, veh, 0)
    cleanup(m)
    Music.Stop(true)
    Client.Send('banner', { kind = 'success', title = 'Vehicle Chopped', subtitle = res.label, rarity = res.rarity, stats = { { 'Paid', '$' .. lib.math.groupdigits(res.amount) } } })
end

local function addGarage(m)
    local g = m.data.garage
    if not g or m.data.chopOnly then return end
    local pos = v3(g)
    m.blips.garage = Client.Blip(pos, 524, 2, 'Your warehouse', not m.tracker or m.data.garageStrips)
    local gp = lib.points.new({ coords = pos, distance = 30.0 })
    function gp:nearby()
        local veh = ride(m)
        if not veh or GetVehiclePedIsIn(cache.ped, false) ~= veh then return end
        DrawMarker(1, pos.x, pos.y, pos.z - 1.0, 0, 0, 0, 0, 0, 0, C.DeliverRadius * 2, C.DeliverRadius * 2, 1.0, 8, 175, 162, 70, false, false, 2, false, nil, nil, false)
        if self.currentDistance < C.DeliverRadius then
            if m.tracker and not m.data.garageStrips then Bridge.ShowText('!', L('src_tracker')) return end
            Bridge.ShowText(Config.Interact.KeyLabel, m.tracker and 'Deliver (garage strips the tracker)' or L('ti_store'))
            if IsControlJustPressed(0, Config.Interact.Key) and GetEntitySpeed(veh) < 4.0 then
                CreateThread(function() deliver(m, veh) end)
            end
        else
            Bridge.HideText()
        end
    end
    function gp:onExit() Bridge.HideText() end
    m.points.garage = gp
end

local function addChopShops(m)
    for i, shop in ipairs(m.data.chopShops or {}) do
        local pos = v3(shop.coords or shop)
        m.blips['chop' .. i] = Client.Blip(pos, 643, 47, shop.label or 'Chop shop', m.data.chopOnly and i == 1)
        SetBlipAsShortRange(m.blips['chop' .. i], not m.data.chopOnly)
        -- another creator's chop shop handles the prompt itself
        if not m.data.chopExternal then
            local cp = lib.points.new({ coords = pos, distance = 12.0 })
            function cp:nearby()
                local veh = m.vehicle
                if m.busy or not veh or GetVehiclePedIsIn(cache.ped, false) ~= veh then return end
                DrawMarker(1, pos.x, pos.y, pos.z - 1.0, 0, 0, 0, 0, 0, 0, 6.0, 6.0, 1.0, 229, 72, 77, 70, false, false, 2, false, nil, nil, false)
                if self.currentDistance < 6.0 then
                    Bridge.ShowText(Config.Interact.KeyLabel, L('ti_chop'))
                    if IsControlJustPressed(0, Config.Interact.Key) and GetEntitySpeed(veh) < 3.0 then
                        CreateThread(function() chop(m, veh) end)
                    end
                else
                    Bridge.HideText()
                end
            end
            function cp:onExit() Bridge.HideText() end
            m.points['chop' .. i] = cp
        end
    end
    if m.data.chopExternal and m.vehicle then ChopShop.OnChopTarget(m.vehicle, m.data) end
end

local function trackerCleared(m)
    m.tracker = false
    removeBlips(m, 'shop')
    for k, p in pairs(m.points) do if k:find('^shop') then p:remove() m.points[k] = nil end end
    if m.blips.garage then SetBlipRoute(m.blips.garage, true) SetBlipRouteColour(m.blips.garage, 2) end
    Bridge.Notify(L('src_tracker_off'), 'success')
    objective(m, m.data.chopOnly and 'Take it to a chop shop' or ('Deliver the ' .. m.data.label .. ' to your warehouse'), m.data.chopOnly and 'chop' or 'deliver')
end

local function addTrackerShops(m)
    for i, shop in ipairs(m.data.trackerSpots or Config.TrackerShops) do
        local pos = v3(shop)
        m.blips['shop' .. i] = Client.Blip(pos, shop.own and 402 or 72, shop.own and 2 or 1, shop.own and 'Your tracker workshop' or 'Remove tracker', false)
        local sp = lib.points.new({ coords = pos, distance = 10.0 })
        function sp:nearby()
            if not m.tracker or m.busy then return end
            local veh = ride(m)
            if not veh or GetVehiclePedIsIn(cache.ped, false) ~= veh then return end
            Bridge.ShowText(Config.Interact.KeyLabel, L('ti_tracker'))
            if IsControlJustPressed(0, Config.Interact.Key) then
                m.busy = true
                Bridge.HideText()
                CreateThread(function()
                    local done = lib.progressBar({ duration = shop.own and 3500 or 6000, label = 'Pulling the tracker', canCancel = true, disable = { car = true, move = true, combat = true } })
                    if done and lib.callback.await('nz_cargo:source:removeTracker', false, m.id) then trackerCleared(m) end
                    m.busy = false
                end)
            end
        end
        function sp:onExit() Bridge.HideText() end
        m.points['shop' .. i] = sp
    end
end

-- Attack crews (rolled on the server by tier, more while a tracker is live)
local function spawnAttack(m, plan, now)
    local function go()
        if Client.mission ~= m or m.done then return end
        local made = Scenarios.Chasers(Config.Attackers, plan.cars or 1, 'shoot')
        for _, e in ipairs(made) do m.peds[#m.peds + 1] = e end
        reportPeds(m, made)
        m.lastCombat = GetGameTimer()
        Music.Play('attack')
        Bridge.Notify(L('src_ambush'), 'error', 'Attackers')
        objective(m, m.objective)
    end
    if now then go() else SetTimeout((plan.delay or 20) * 1000, go) end
end

local function startEscape(m, veh, res)
    m.stage = 'escape'
    m.tracker = res.tracker
    removeBlips(m, 'target')
    removeBlips(m, 'spot')
    if m.points.breakin then m.points.breakin:remove() m.points.breakin = nil end
    Bridge.GiveKeys(veh, m.data.plate)
    Music.RadioOff(veh)
    Music.Play('delivering')
    addGarage(m)
    addChopShops(m)
    if m.tracker then
        addTrackerShops(m)
        Bridge.Notify(L('src_tracker'), 'warning', 'Tracker')
        objective(m, m.data.garageStrips and 'Lose the tracker or drive it home (garage strips it)' or 'Lose the tracker at a mod shop', 'tracker')
    elseif m.data.chopOnly then
        objective(m, 'Take it to a chop shop', 'chop')
    elseif m.data.scenario == 'cargobob' then
        objective(m, 'Fly the ' .. m.data.label .. ' home and drop it at your garage', 'deliver')
    else
        objective(m, 'Deliver the ' .. m.data.label .. ' to your warehouse', 'deliver')
    end
    if res.attack then spawnAttack(m, res.attack, false) end
end
Source.StartEscape, Source.Deliver = startEscape, deliver

local function onEntered(m, veh)
    local res = lib.callback.await('nz_cargo:source:entered', false, m.id)
    if not res then return end
    Bridge.Notify(L('src_picked'), 'success')
    startEscape(m, veh, res)
end

-----------------------------------------------------------------
-- Main loop
-----------------------------------------------------------------
function Source.Run(d)
    local m = {
        kind = 'source', id = d.id, data = d, peds = {}, blips = {}, points = {}, stage = 'travel',
        locked = d.locked, expiresAt = GetGameTimer() + d.expires * 1000, tracker = false, step = 'find',
    }
    m.cancel = function() lib.callback.await('nz_cargo:source:cancel', false, m.id) end
    Client.mission = m

    if d.stolen then
        -- hijacked: we are already in the driver seat
        m.vehicle = GetVehiclePedIsIn(cache.ped, false)
        m.setup = true
        Music.Play('start')
        Bridge.Notify(d.chopOnly and L('hijack_chop') or L('hijacked'), 'warning', 'Hijacked')
        startEscape(m, m.vehicle, { tracker = d.tracker })
    else
        if Client.inside then Warehouse.Exit('front') end
        Music.Play('start')
        if d.lift then
            -- recovery: go get the flatbed / Cargobob first
            m.blips.spot = Client.Blip(v3(d.spot), 225, 5, d.label, false)
            m.blips.lift = Client.Blip(v3(d.lift), d.scenario == 'tow' and 68 or 481, 5, d.scenario == 'tow' and 'Flatbed' or 'Cargobob', true)
        else
            m.blips.spot = Client.Blip(v3(d.spot), 225, 5, d.label, true)
        end
        Bridge.Notify(L('src_started', d.label), 'info', 'Contract')
        if d.hotTip then
            local r = Cargo.Rarity[d.rarity]
            Bridge.Notify(('Your intel turned this into a %s contract.'):format(r and r.label or d.rarity), 'success', 'Hot Tip')
        end
        if d.lift then
            objective(m, d.scenario == 'tow' and 'Steal the flatbed from the depot' or 'Steal the Cargobob from the helipad', 'find')
        else
            objective(m, 'Find the ' .. d.label, 'find')
        end
    end

    CreateThread(function()
        while Client.mission == m and not m.done do
            local sleep = 1000
            local ped = cache.ped
            local pos = GetEntityCoords(ped)

            if not m.vehicle or not DoesEntityExist(m.vehicle) then
                if NetworkDoesEntityExistWithNetworkId(d.netId) then m.vehicle = NetToVeh(d.netId) end
            end
            local veh = m.vehicle
            -- recovery: the depot / helipad comes alive when you get close
            if d.lift and not m.depotReady and #(pos - v3(d.lift)) < 200.0 then Heist.Depot(m) end

            if veh and veh ~= 0 and DoesEntityExist(veh) then
                local dist = #(pos - GetEntityCoords(veh))
                if not m.setup and dist < 160.0 then setup(m, veh) end

                if IsEntityDead(veh) or GetVehicleEngineHealth(veh) < -3900.0 then
                    lib.callback.await('nz_cargo:source:destroyed', false, m.id)
                    break
                end

                local driving = GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped

                if m.stage == 'travel' then
                    if d.scenario == 'moving' and m.driver then
                        sleep = 250
                        local drv = m.driver
                        if not DoesEntityExist(drv) or IsEntityDead(drv) or not IsPedInVehicle(drv, veh, false) then
                            m.driver = nil
                        else
                            if dist < 45.0 and not m.fleeing then
                                m.fleeing = true
                                TaskVehicleMissionPedTarget(drv, veh, ped, 8, 38.0, 786468, 300.0, 15.0, true)
                                Music.Play('attack')
                            end
                            if dist < 9.0 and GetEntitySpeed(veh) < 1.5 then m.stopped = (m.stopped or 0) + 1 else m.stopped = 0 end
                            if m.stopped >= 4 or GetVehicleEngineHealth(veh) < 300.0 then
                                TaskLeaveVehicle(drv, veh, 256)
                                SetTimeout(1200, function()
                                    if DoesEntityExist(drv) then TaskSmartFleePed(drv, cache.ped, 250.0, -1, false, false) end
                                end)
                                m.driver = nil
                            end
                        end
                    end
                    if driving then onEntered(m, veh) end
                end

                -- music follows the action
                if Scenarios.InCombat(m.peds) then
                    if not m.lastCombat or GetGameTimer() - m.lastCombat > 14000 then m.lastCombat = GetGameTimer() objective(m, m.objective) end
                    m.lastCombat = GetGameTimer()
                end
                local hot = m.lastCombat and GetGameTimer() - m.lastCombat < 15000
                if not m.countdown then
                    if hot then Music.Play('attack')
                    elseif m.stage == 'escape' then Music.Play('delivering') end
                end
                if dist < 200.0 and sleep > 500 then sleep = 500 end
            end

            local remaining = (m.expiresAt - GetGameTimer()) / 1000
            if remaining <= 30 and not m.countdown then
                m.countdown = true
                Music.Play('countdown')
            end
            Wait(sleep)
        end
    end)
end

-- Another creator's chop shop took it
RegisterNetEvent('nz_cargo:source:externalChop', function(res)
    local m = Client.mission
    if not m or m.kind ~= 'source' then return end
    cleanup(m)
    Music.Stop(true)
    local stats = res.amount and res.amount > 0 and { { 'Paid', '$' .. lib.math.groupdigits(res.amount) } } or nil
    Client.Send('banner', { kind = 'success', title = 'Vehicle Chopped', subtitle = res.label, rarity = res.rarity, stats = stats })
end)

handlers.source = function(d)
    if Client.mission then Bridge.Notify(L('busy'), 'error') return { ok = false } end
    local data = lib.callback.await('nz_cargo:source:start', false, d.rarity)
    if not data then return { ok = false } end
    Laptop.Close(true)
    Client.CloseUI()
    CreateThread(function() Source.Run(data) end)
    return { ok = true }
end

RegisterNetEvent('nz_cargo:source:end', function(info)
    local m = Client.mission
    if not m or m.kind ~= 'source' then return end
    cleanup(m)
    Music.Stop(false)
    Client.Send('banner', { kind = 'fail', title = 'Contract Failed', subtitle = info and info.reason or '' })
end)

RegisterNetEvent('nz_cargo:source:ping', function()
    Bridge.Notify(L('src_tracker_ping'), 'warning', 'Tracker')
end)

-- another crew while the tracker is still live
RegisterNetEvent('nz_cargo:source:wave', function(id, wave)
    local m = Client.mission
    if m and m.kind == 'source' and m.id == id then spawnAttack(m, wave, true) end
end)

-----------------------------------------------------------------
-- Hijacking: getting into someone else's tracked car
-----------------------------------------------------------------
lib.onCache('seat', function(seat)
    if seat ~= -1 or Client.mission or not Config.Hijack.Enabled then return end
    SetTimeout(300, function()
        local veh = cache.vehicle
        if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= cache.ped then return end
        local st = Entity(veh).state.nzCargo
        if not st or not st.mission or st.sold or st.owner == cache.serverId then return end
        local data = lib.callback.await('nz_cargo:hijack', false, NetworkGetNetworkIdFromEntity(veh))
        if data then CreateThread(function() Source.Run(data) end) end
    end)
end)

RegisterCommand('cargocancel', function()
    local m = Client.mission
    if not m then return end
    local ok = lib.alertDialog({ header = 'Cancel job?', content = 'The car and your fee are lost.', centered = true, cancel = true })
    if ok == 'confirm' and m.cancel then m.cancel() end
end, false)
