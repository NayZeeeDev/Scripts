-----------------------------------------------------------------
-- Sourcing contracts (server authoritative)
-- Contracts, illegal contracts, trackers, attackers, police live
-- tracking, scanner pings, hijacking and chop shops.
-----------------------------------------------------------------
Source = {}
local missions = {}     -- [missionId] = mission
local nextId = 0
local usedSpots = {}    -- [scenario..index] = missionId
local A = Config.Attackers

local function plateText()
    local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
    local t = { 'N', 'Z' }
    for i = 3, 8 do
        local n = math.random(1, #chars)
        t[i] = chars:sub(n, n)
    end
    return table.concat(t)
end
Source.Plate = plateText

local function pick(list) return list[math.random(1, #list)] end

local function deleteNet(netId)
    if not netId then return end
    local e = NetworkGetEntityFromNetworkId(netId)
    if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
end

local function pendingFor(wid, floor)
    local n = 0
    for _, m in pairs(missions) do
        if m.wid == wid and (m.illegal and 'lower' or 'main') == (floor or 'main') then n = n + 1 end
    end
    return n
end
Source.PendingFor = pendingFor

local function pickSpot(scenario)
    local list = Config.SourceSpots[scenario] or (scenario == 'crew' and Config.SourceSpots.guarded) or Config.SourceSpots.parked
    local free = {}
    for i = 1, #list do
        if not usedSpots[scenario .. i] then free[#free + 1] = i end
    end
    if #free == 0 then return nil end
    local i = free[math.random(1, #free)]
    return i, list[i]
end

local function tierXp(id) local r = Cargo.Rarity[id] return r and r.xp or 0 end

-- Roll a crew for this tier. Returns nil or { cars, delay }.
local function rollAttack(kind, rarity)
    local cfg = A[kind] and A[kind][rarity]
    if not cfg or math.random() >= cfg[1] then return nil end
    return { cars = math.random(cfg[2], cfg[3]), delay = math.random(A.Delay[1], A.Delay[2]) }
end
Source.RollAttack = rollAttack

function Source.Text(src, pool)
    local list = A.Messages[pool]
    if list and #list > 0 then Bridge.PhoneMessage(src, pick(list)) end
end

-- Your contact texting you about the job (Config.Phone.Contact)
function Source.Contact(src, key, ...)
    local list = Config.Phone.Contact and Config.Phone.Contact[key]
    if not list or #list == 0 then return end
    local ok, text = pcall(string.format, pick(list), ...)
    Bridge.PhoneMessage(src, ok and text or pick(list))
end

-- /cargotext [id]: check that phone texts reach a player
RegisterCommand('cargotext', function(src, args)
    if src ~= 0 and not Bridge.IsAdmin(src) then return end
    local target = tonumber(args[1]) or src
    if target == 0 then print('usage: cargotext <id>') return end
    local ok = Bridge.PhoneMessage(target, 'Test text from Vehicle Cargo. If you can read this, texts work.')
    local msg = ok and 'Text handed to the phone resource.' or 'No phone resource took the text (check Config.Phone and that the player has a phone equipped).'
    if src == 0 then print(msg) else Server.Notify(src, msg, ok and 'success' or 'error') end
end, false)

local crewDone   -- crew job bookkeeping (defined with the crew jobs below)

local function finish(m, success, reason, keepEntity)
    missions[m.id] = nil
    if m.group and crewDone then crewDone(m, success and not m.chopped) end
    Radio.Stop(m)
    if m.spotKey then usedSpots[m.spotKey] = nil end
    local st = Server.Players[m.src]
    if st and st.mission and st.mission.id == m.id then st.mission = nil end
    if not keepEntity then
        for _, n in ipairs(m.peds or {}) do deleteNet(n) end
    end
    if m.carrier and DoesEntityExist(m.carrier) then
        local carrier = m.carrier
        if success then DeleteEntity(carrier)
        else
            -- never pull a Cargobob out from under someone flying it: wait until it's empty
            local tries = 0
            local function sweep()
                if not DoesEntityExist(carrier) then return end
                tries = tries + 1
                if GetPedInVehicleSeat(carrier, -1) ~= 0 and tries < 40 then SetTimeout(15000, sweep) return end
                DeleteEntity(carrier)
            end
            SetTimeout(15000, sweep)
        end
    end
    if not success then
        if not keepEntity and m.entity and DoesEntityExist(m.entity) then DeleteEntity(m.entity) end
        local p = st and st.identifier and DB.GetProfile(st.identifier)
        if p then p.failed = p.failed + 1 DB.SaveProfile(p) end
        if st and st.identifier then DB.Log(st.identifier, m.wid or 0, 'failed', m.label, m.rarity, 0, { reason = reason }) end
        if GetPlayerPing(m.src) > 0 then
            Server.Notify(m.src, L('src_failed', reason or ''), 'error', 'Contract Failed')
            TriggerClientEvent('nz_cargo:source:end', m.src, { success = false, reason = reason })
        end
    end
end

local function fail(m, reason) finish(m, false, reason) end
Source.Fail = fail

local function owned(src, id)
    local m = missions[tonumber(id)]
    if not m or m.src ~= src then return nil end
    return m
end

local function inDriverSeat(src, m)
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return false end
    return veh == m.entity
end

-- Driving the flatbed / Cargobob that carries the car
local function inCarrier(src, m)
    if not m.carrier or not DoesEntityExist(m.carrier) then return false end
    local ped = GetPlayerPed(src)
    return GetVehiclePedIsIn(ped, false) == m.carrier and GetPedInVehicleSeat(m.carrier, -1) == ped
end

local function garageOf(wid)
    local w = wid and DB.Warehouses[wid]
    local loc = w and DB.Locations[w.location]
    return loc and loc.garage, loc and loc.door
end

-- Tracker removal points this mission may use (shops + the owner's own spot)
local function trackerSpots(m)
    local list = {}
    for _, s in ipairs(Config.TrackerShops) do list[#list + 1] = { x = s.x, y = s.y, z = s.z } end
    local w = m.wid and DB.Warehouses[m.wid]
    local trk = w and Cargo.Upgrade('tracker', w.upgrades.tracker)
    if w and trk and trk.custom and w.trackerSpot then list[#list + 1] = { x = w.trackerSpot.x, y = w.trackerSpot.y, z = w.trackerSpot.z, own = true } end
    return list
end

local function clientData(m)
    local garage, door = garageOf(m.wid)
    local w = m.wid and DB.Warehouses[m.wid]
    local trk = w and Cargo.Upgrade('tracker', w.upgrades.tracker)
    return {
        id = m.id, netId = m.netId, model = m.model, label = m.label, rarity = m.rarity, hotTip = m.hotTip,
        scenario = m.scenario, spot = m.spot, plate = m.plate, locked = m.locked, illegal = m.illegal,
        expires = math.max(0, m.expires - Server.Now()), garage = garage, door = door, wid = m.wid,
        guests = m.guests or 0, trackerSpots = trackerSpots(m), chopShops = ChopShop.Locations(), chopExternal = ChopShop.External(),
        garageStrips = trk and trk.garage or false, stolen = m.stolen, chopOnly = m.chopOnly, stage = m.stage,
        tracker = m.tracker, crew = m.crew, keysOnly = m.keysOnly, hasKeys = m.hasKeys,
        keyHolder = m.scenario == 'guarded' and m.keyHolder or nil, crewLeader = m.crewLeader, crewJob = m.crewJob,
        carrierNet = m.carrierNet, lift = m.lift, loaded = m.loaded,
        contract = m.contract,
    }
end

-- Cooldowns: one global timer, or one per contract card (Config.Sourcing.CooldownMode)
local function perContract() return Config.Sourcing.CooldownMode == 'contract' end

function Source.CooldownLeft(p, id)
    if perContract() then return math.max(0, ((p.contract_cd or {})[id] or 0) - Server.Now()) end
    return math.max(0, (p.source_cd or 0) - Server.Now())
end

local function setCooldown(p, id, cut)
    local base = perContract() and ((Config.Sourcing.ContractCooldowns or {})[id] or Config.Sourcing.Cooldown) or Config.Sourcing.Cooldown
    local secs = math.floor(base * (1 - (cut or 0)))
    if perContract() then
        p.contract_cd = p.contract_cd or {}
        p.contract_cd[id] = Server.Now() + secs
    else
        p.source_cd = Server.Now() + secs
    end
end

function Source.Special(id)
    for _, c in ipairs(Config.SpecialContracts or {}) do if c.id == id then return c end end
end

-- Scenarios where the car can't be lockpicked: you need the keys.
local KEY_SCENARIOS = { party = true, pickpocket = true, hostile = true, guarded = true }
local RECOVERY = { tow = 'depot', cargobob = 'pad' }
Source.KeyScenarios = KEY_SCENARIOS

local function crewSize(scenario, illegal)
    local G = Config.Sourcing.Guards
    local range = G.Count[scenario]
    if not range then return 0 end
    local n = math.random(range[1], range[2])
    if illegal and G.Illegal then n = n + (G.Illegal.Extra or 0) end
    return n
end

local function spawnServer(model, kind, at)
    local e = CreateVehicleServerSetter(joaat(model), kind, at.x, at.y, at.z, at.w or 0.0)
    local tries = 0
    while not DoesEntityExist(e) and tries < 50 do Wait(20) tries = tries + 1 end
    return DoesEntityExist(e) and e or nil
end

-----------------------------------------------------------------
-- Start
-----------------------------------------------------------------
lib.callback.register('nz_cargo:source:start', Server.Once('player', function(src, contractId)
    local st = Server.Get(src)
    if not st or not st.inside then return false end
    if st.mission then Server.Notify(src, L('busy'), 'error') return false end
    local wid = st.inside
    local w = DB.Warehouses[wid]
    if not w or not Server.Can(src, wid, 'contracts') then Server.Notify(src, L('no_perm'), 'error') return false end

    local special = Source.Special(contractId)
    local rarity = not special and Cargo.Rarity[contractId] or nil
    local tier = special or rarity
    if not tier then return false end
    local illegal = rarity and Cargo.IsIllegal(contractId) or false
    local floor = illegal and 'lower' or 'main'
    local p = Server.Profile(src)
    local level = Server.Level(p)
    if level < tier.level then Server.Notify(src, L('level_locked', tier.level), 'error') return false end
    if illegal and (w.upgrades.lower or 0) < 1 then Server.Notify(src, L('lower_locked'), 'error') return false end
    local cd = Source.CooldownLeft(p, contractId)
    if cd > 0 then Server.Notify(src, L('cooldown', Cargo.FormatTime(cd)), 'error') return false end
    if DB.CountStock(wid, floor) + pendingFor(wid, floor) >= Server.Capacity(w, floor) then
        Server.Notify(src, L(illegal and 'lower_full' or 'warehouse_full'), 'error') return false
    end
    if Config.Sourcing.MinPolice > 0 and Bridge.CountPolice() < Config.Sourcing.MinPolice then
        Server.Notify(src, L('not_enough_police'), 'error') return false
    end

    -- pick the car
    local intel = Cargo.Upgrade('intel', w.upgrades.intel)
    local veh, final, hotTip
    if special then
        local list = {}
        for _, v in ipairs((Config.SpecialVehicles or {})[special.id] or {}) do
            if Cargo.Rarity[v.rarity] then list[#list + 1] = v end
        end
        if #list == 0 then return false end
        veh = list[math.random(1, #list)]
        final, hotTip = Cargo.Rarity[veh.rarity], false
    else
        -- Intel can bump a ladder contract one tier
        final, hotTip = rarity, false
        if not illegal and math.random() < (intel and intel.rollUp or 0) and rarity.index < #Config.Rarities then
            final, hotTip = Cargo.RarityAt(rarity.index + 1), true
        end
        local candidates = Server.PoolFor(final.id)
        if #candidates == 0 then final, hotTip = rarity, false candidates = Server.PoolFor(rarity.id) end
        if #candidates == 0 then return false end
        veh = candidates[math.random(1, #candidates)]
    end

    local weights = special and special.scenarios or Config.Sourcing.Scenarios[final.id] or Config.Sourcing.Scenarios[contractId]
    local scenario = Cargo.PickWeighted(weights or { parked = 1 }) or 'parked'
    local spotIndex, entry = pickSpot(scenario)
    if not spotIndex then scenario = 'parked' spotIndex, entry = pickSpot('parked') end
    if not spotIndex then Server.Notify(src, L('busy'), 'error') return false end
    local spot = entry.car or entry
    local liftSpot = RECOVERY[scenario] and entry[RECOVERY[scenario]] or nil
    if RECOVERY[scenario] and not liftSpot then scenario = 'parked' end

    if not Server.Charge(src, tier.fee, 'vehiclecargo-contract') then return false end

    local entity = spawnServer(veh.model, veh.type or Server.TypeOf(veh.model), spot)
    if not entity then
        Bridge.AddMoney(src, Config.Accounts.Purchase, tier.fee, 'vehiclecargo-refund')
        return false
    end

    -- the flatbed / Cargobob for recovery jobs
    local carrier
    if RECOVERY[scenario] then
        local R = Config.Sourcing.Recovery
        local cfg = scenario == 'tow' and R.Tow or R.Cargobob
        carrier = spawnServer(cfg.Model, scenario == 'tow' and 'automobile' or 'heli', liftSpot)
        if not carrier then
            DeleteEntity(entity)
            Bridge.AddMoney(src, Config.Accounts.Purchase, tier.fee, 'vehiclecargo-refund')
            return false
        end
        SetVehicleDoorsLocked(carrier, 2)
    end

    local plate = plateText()
    SetVehicleNumberPlateText(entity, plate)
    local locked = scenario ~= 'moving'
    SetVehicleDoorsLocked(entity, locked and 2 or 1)

    nextId = nextId + 1
    setCooldown(p, contractId, intel and intel.cooldownCut or 0)
    DB.SaveProfile(p)

    local crew = scenario == 'party' and math.random(Config.Sourcing.PartyGuests[1], Config.Sourcing.PartyGuests[2]) or crewSize(scenario, illegal)
    local m = {
        id = nextId, kind = 'source', src = src, wid = wid, illegal = illegal,
        entity = entity, netId = NetworkGetNetworkIdFromEntity(entity),
        model = veh.model, label = veh.label, rarity = final.id, contract = contractId,
        value = math.floor(veh.value * (special and special.valueMult or 1)), xp = special and special.xp or nil,
        scenario = scenario, spot = DB.V4(spot), spotKey = scenario .. spotIndex,
        plate = plate, locked = locked, tracker = math.random() < (Config.Sourcing.TrackerChance[final.id] or 0), stage = 'travel',
        crew = crew, guests = scenario == 'party' and crew or 0,
        -- who has the keys: a guest / guard index, or the owner (1) for pickpocket and hostile
        keyHolder = (scenario == 'party' or scenario == 'guarded') and math.random(1, math.max(1, crew)) or ((scenario == 'pickpocket' or scenario == 'hostile') and 1 or nil),
        keysOnly = KEY_SCENARIOS[scenario] and Config.Sourcing.KeysOnly or false,
        carrier = carrier, carrierNet = carrier and NetworkGetNetworkIdFromEntity(carrier) or nil,
        lift = liftSpot and DB.V4(liftSpot) or nil,
        expires = Server.Now() + Config.Sourcing.TimeLimit, peds = {}, hotTip = hotTip,
        attack = rollAttack('source', final.id),
    }
    m.hadTracker = m.tracker
    missions[m.id] = m
    usedSpots[m.spotKey] = m.id
    st.mission = m
    Radio.Start(m)
    Entity(entity).state:set('nzCargo', { mission = m.id, owner = src }, true)

    DB.Log(st.identifier, wid, 'contract', veh.label, final.id, -tier.fee, { scenario = scenario, contract = contractId })
    Cargo.Debug(('contract %d %s %s %s tracker=%s'):format(m.id, veh.model, final.id, scenario, tostring(m.tracker)))

    -- your contact texts you the brief
    SetTimeout(2500, function()
        if not missions[m.id] then return end
        Source.Contact(src, 'start', veh.label)
        if Config.Phone.Contact and Config.Phone.Contact[scenario] then
            SetTimeout(3500, function() if missions[m.id] then Source.Contact(src, scenario, veh.label) end end)
        end
    end)
    if illegal then SetTimeout(12000, function() if missions[m.id] then Source.Text(src, 'illegal') end end) end

    return clientData(m)
end))

-----------------------------------------------------------------
-- In-mission events
-----------------------------------------------------------------
lib.callback.register('nz_cargo:source:peds', function(src, id, netIds)
    local m = owned(src, id)
    if not m or type(netIds) ~= 'table' then return false end
    for _, n in ipairs(netIds) do
        if #m.peds < 32 then m.peds[#m.peds + 1] = tonumber(n) end
    end
    return true
end)

-- Called before a break-in (lockpick). Handles item + dispatch.
lib.callback.register('nz_cargo:source:breakin', function(src, id)
    local m = owned(src, id)
    if not m or not m.locked then return false end
    if m.keysOnly or m.carrier then Server.Notify(src, L('src_need_keys'), 'error') return false end
    if Config.Sourcing.LockpickItem and not Bridge.HasItem(src, Config.Sourcing.LockpickItem) then
        Server.Notify(src, ('You need a %s.'):format(Config.Sourcing.LockpickItem), 'error')
        return false
    end
    if not m.dispatched and (m.scenario == 'impound' or math.random() < Config.Sourcing.DispatchChance) then
        m.dispatched = true
        Bridge.Dispatch({
            title = m.scenario == 'impound' and L('dispatch_impound') or L('dispatch_theft'),
            message = ('%s · %s'):format(m.label, m.plate), coords = GetEntityCoords(m.entity), code = '10-60',
            blip = { sprite = 225, colour = 1 }, plate = m.plate, model = m.model, src = src,
        })
    end
    return true
end)

lib.callback.register('nz_cargo:source:unlock', function(src, id, success)
    local m = owned(src, id)
    if not m then return false end
    if not success then
        if Config.Sourcing.LockpickItem and math.random() < 0.35 then Bridge.RemoveItem(src, Config.Sourcing.LockpickItem, 1) end
        return false
    end
    local d = #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(m.entity))
    if d > 6.0 then return false end
    m.locked = false
    SetVehicleDoorsLocked(m.entity, 1)
    return true
end)

-- Keys: searching a guest / body, lifting them off the owner, or picking up
-- the ones a guard dropped. The server decides who actually has them.
local function giveKeys(m)
    m.locked = false
    m.hasKeys = true
    if DoesEntityExist(m.entity) then SetVehicleDoorsLocked(m.entity, 1) end
end

local function nearCar(src, m, range)
    if not DoesEntityExist(m.entity) then return false end
    return #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(m.entity)) < (range or 120.0)
end

lib.callback.register('nz_cargo:source:keys', function(src, id, index, how)
    local m = owned(src, id)
    if not m or not KEY_SCENARIOS[m.scenario] or m.hasKeys then return 'none' end
    if not nearCar(src, m, 150.0) then return 'none' end
    index = tonumber(index)
    if not index then return 'none' end
    m.searched = m.searched or {}
    if m.searched[index] then return 'none' end
    m.searched[index] = true
    local count = 0
    for _ in pairs(m.searched) do count = count + 1 end
    -- whoever is left last has them, so a dead or missing key holder never soft-locks the job
    if index == m.keyHolder or count >= (m.crew or 99) then
        giveKeys(m)
        DB.Log(Server.Get(src).identifier, m.wid or 0, 'keys', m.label, m.rarity, 0, { how = how })
        return 'found'
    end
    if m.scenario == 'party' and how == 'search' and math.random() < (Config.Sourcing.Party.FightChance or 0) then return 'armed' end
    return 'none'
end)

-- The client tells us how many guests / guards actually spawned
lib.callback.register('nz_cargo:source:crew', function(src, id, count)
    local m = owned(src, id)
    count = tonumber(count)
    if not m or not count or count < 1 then return false end
    if count < (m.crew or 0) then
        m.crew = count
        if m.keyHolder and m.keyHolder > count then m.keyHolder = count end   -- the client uses the last one too
    end
    return true
end)

-- The pickpocket target noticed you and ran: he calls it in.
lib.callback.register('nz_cargo:source:spooked', function(src, id)
    local m = owned(src, id)
    if not m or m.spooked then return false end
    m.spooked = true
    if DoesEntityExist(m.entity) then
        Bridge.Dispatch({
            title = L('dispatch_mugging'), message = ('%s · %s'):format(m.label, m.plate), coords = GetEntityCoords(GetPlayerPed(src)),
            code = '10-31', blip = { sprite = 280, colour = 1 }, plate = m.plate, model = m.model, src = src,
        })
    end
    return true
end)

-- Recovery: steal the flatbed / Cargobob
lib.callback.register('nz_cargo:source:hotwire', function(src, id, success)
    local m = owned(src, id)
    if not m or not m.carrier or not DoesEntityExist(m.carrier) or m.hotwired then return false end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(m.carrier)) > 8.0 then return false end
    if not success then
        if not m.dispatched and math.random() < Config.Sourcing.DispatchChance then
            m.dispatched = true
            Bridge.Dispatch({
                title = L('dispatch_theft'), message = ('%s · %s'):format(m.scenario == 'tow' and 'Flatbed' or 'Cargobob', m.plate),
                coords = GetEntityCoords(m.carrier), code = '10-60', blip = { sprite = m.scenario == 'tow' and 68 or 481, colour = 1 }, src = src,
            })
        end
        return false
    end
    m.hotwired = true
    SetVehicleDoorsLocked(m.carrier, 1)
    return true
end)

-- Recovery: the car is on the flatbed / hooked to the Cargobob. The escape starts.
lib.callback.register('nz_cargo:source:loaded', function(src, id, on)
    local m = owned(src, id)
    if not m or not m.carrier or not m.hotwired then return false end
    if not inCarrier(src, m) and on then return false end
    if on and #(GetEntityCoords(m.carrier) - GetEntityCoords(m.entity)) > 30.0 then return false end
    m.loaded = on and true or false
    if not on then return { ok = true } end
    local attack
    if m.stage ~= 'escape' then
        m.stage = 'escape'
        m.pickedAt = Server.Now()
        if m.tracker then
            m.nextPing = Server.Now() + Config.Sourcing.Tracker.PingEvery
            m.nextWave = Server.Now() + A.TrackerWave
        end
        attack = m.attack
        if attack then
            SetTimeout(math.max(1, attack.delay - 6) * 1000, function()
                if missions[m.id] and missions[m.id].src == src then Source.Text(src, m.illegal and 'illegal' or 'source') end
            end)
        end
    end
    return { ok = true, tracker = m.tracker, attack = attack }
end)

lib.callback.register('nz_cargo:source:entered', function(src, id)
    local m = owned(src, id)
    if not m or not inDriverSeat(src, m) then return false end
    local attack
    if m.stage ~= 'escape' then
        m.stage = 'escape'
        m.pickedAt = Server.Now()
        if m.tracker then
            m.nextPing = Server.Now() + Config.Sourcing.Tracker.PingEvery
            m.nextWave = Server.Now() + A.TrackerWave
        end
        attack = m.attack
        if attack then
            SetTimeout(math.max(1, attack.delay - 6) * 1000, function()
                if missions[m.id] and missions[m.id].src == src then Source.Text(src, m.illegal and 'illegal' or 'source') end
            end)
        end
    end
    return { tracker = m.tracker, attack = attack }
end)

lib.callback.register('nz_cargo:source:removeTracker', function(src, id)
    local m = owned(src, id)
    if not m or not m.tracker or not (inDriverSeat(src, m) or (m.loaded and inCarrier(src, m))) then return false end
    local pos = GetEntityCoords(m.entity)
    for _, s in ipairs(trackerSpots(m)) do
        if #(pos - vector3(s.x, s.y, s.z)) < 12.0 then
            m.tracker = false
            TriggerClientEvent('nz_cargo:untrack', -1, m.id)
            return true
        end
    end
    return false
end)

lib.callback.register('nz_cargo:source:destroyed', function(src, id)
    local m = owned(src, id)
    if m then fail(m, L('src_destroyed')) end
    return true
end)

lib.callback.register('nz_cargo:source:cancel', function(src, id)
    local m = owned(src, id)
    if m then fail(m, L('src_abandoned')) end
    return true
end)

-----------------------------------------------------------------
-- Delivery into the warehouse garage
-----------------------------------------------------------------
lib.callback.register('nz_cargo:source:deliver', Server.Once('srcmission', function(src, id, props)
    local m = owned(src, id)
    if not m or m.chopOnly then return false end
    -- driving it, towing it on the flatbed, or it was just dropped by the Cargobob
    local carried = m.carrier and m.loaded and inCarrier(src, m)
    local dropped = m.scenario == 'cargobob' and m.hotwired and not m.loaded
        and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(m.entity)) < 90.0
    if not (inDriverSeat(src, m) or carried or dropped) then return false end
    local w = DB.Warehouses[m.wid]
    local loc = w and DB.Locations[w.location]
    if not loc then fail(m, L('src_abandoned')) return false end
    local pos = GetEntityCoords(m.entity)
    if #(pos - vector3(loc.garage.x, loc.garage.y, loc.garage.z)) > Config.Sourcing.DeliverRadius + (dropped and 14.0 or carried and 10.0 or 6.0) then
        Server.Notify(src, L('src_wrong_garage'), 'error') return false
    end
    local floor = m.illegal and 'lower' or 'main'
    if DB.CountStock(m.wid, floor) >= Server.Capacity(w, floor) then
        Server.Notify(src, L(m.illegal and 'lower_full' or 'warehouse_full'), 'error') return false
    end
    if m.tracker then
        local trk = Cargo.Upgrade('tracker', w.upgrades.tracker)
        if not (trk and trk.garage) then Server.Notify(src, L('src_tracker'), 'error') return false end
        if (trk.garageFee or 0) > 0 and not Server.Charge(src, trk.garageFee, 'vehiclecargo-tracker') then return false end
        m.tracker = false
        TriggerClientEvent('nz_cargo:untrack', -1, m.id)
    end

    local body   = Cargo.Clamp(GetVehicleBodyHealth(m.entity), 0, 1000)
    local engine = Cargo.Clamp(GetVehicleEngineHealth(m.entity), 0, 1000)
    local cond = Cargo.Clamp(Cargo.Round((body / 1000 * 0.6 + engine / 1000 * 0.4) * 100), 5, 100)

    if type(props) ~= 'table' then props = {} end
    props.plate = m.plate

    local st = Server.Get(src)
    local stockId = DB.AddStock({
        warehouse = m.wid, model = m.model, label = m.label, base_rarity = m.rarity, rarity = m.rarity,
        value = m.value, condition = cond, build = {}, score = 0, props = props, plate = m.plate, sourced_by = st.identifier,
        floor = floor, hot = m.illegal or m.stolen or m.hadTracker,
    })
    Raid.AddHeat(m.wid, m.illegal and 'illegal' or (m.stolen and 'stolen') or (m.hadTracker and 'tracked') or 'clean')

    finish(m, true)
    if DoesEntityExist(m.entity) then DeleteEntity(m.entity) end

    local p = Server.Profile(src)
    p.sourced = p.sourced + 1
    DB.SaveProfile(p)
    local xp = m.xp or tierXp(m.rarity)
    if cond >= 95 then xp = math.floor(xp * 1.2) end
    if m.stolen then xp = math.floor(xp * 0.8) end
    Server.AddXp(src, xp)
    DB.Log(st.identifier, m.wid, 'sourced', m.label, m.rarity, 0, { condition = cond, scenario = m.scenario, stolen = m.stolen })
    Server.Webhook('Vehicle sourced', { Player = st.name, Vehicle = m.label, Rarity = Cargo.Rarity[m.rarity].label, Condition = cond .. '%', Stolen = m.stolen and 'yes' or 'no' })

    Server.PutInBucket(src, m.wid)
    Warehouse.Refresh(m.wid)
    return {
        result = { label = m.label, rarity = m.rarity, condition = cond, xp = xp, stockId = stockId, scenario = m.scenario, floor = floor,
                   time = Server.Now() - (m.expires - Config.Sourcing.TimeLimit) },
        enter = Warehouse.EnterPayload(src, w, Server.Access(src, m.wid)),
    }
end))

-----------------------------------------------------------------
-- Chop shop: break any sourced car down for cash
-----------------------------------------------------------------
lib.callback.register('nz_cargo:source:chop', function(src, id)
    local m = owned(src, id)
    if not m or not inDriverSeat(src, m) then return false end
    local pos = GetEntityCoords(m.entity)
    local near = false
    for _, c in ipairs(Config.ChopShops) do if #(pos - c) < 12.0 then near = true end end
    if not near then return false end
    local body = Cargo.Clamp(GetVehicleBodyHealth(m.entity), 0, 1000)
    local amount = math.floor(m.value * Config.Hijack.ChopPayout * (0.4 + 0.6 * body / 1000))
    local st = Server.Get(src)
    m.chopped = true
    finish(m, true)
    if DoesEntityExist(m.entity) then DeleteEntity(m.entity) end
    Bridge.AddMoney(src, Config.Accounts.Payout, amount, 'vehiclecargo-chop')
    Server.AddXp(src, math.floor(tierXp(m.rarity) * Config.Hijack.ChopXp))
    DB.Log(st.identifier, m.wid or 0, 'chop', m.label, m.rarity, amount, { stolen = m.stolen })
    Server.Webhook('Vehicle chopped', { Player = st.name, Vehicle = m.label, Amount = '$' .. lib.math.groupdigits(amount) })
    return { amount = amount, label = m.label, rarity = m.rarity }
end)

-- Another creator's chop shop chopped one of our job cars
function Source.ExternalChop(m)
    local src = m.src
    local st = Server.Get(src)
    m.chopped = true
    finish(m, true)
    if m.entity and DoesEntityExist(m.entity) then DeleteEntity(m.entity) end
    local C = Config.ChopShop
    local amount = 0
    if C.PayOnExternal then
        amount = math.floor(m.value * Config.Hijack.ChopPayout)
        Bridge.AddMoney(src, Config.Accounts.Payout, amount, 'vehiclecargo-chop')
    end
    if C.XpOnExternal then Server.AddXp(src, math.floor(tierXp(m.rarity) * Config.Hijack.ChopXp)) end
    if st and st.identifier then DB.Log(st.identifier, m.wid or 0, 'chop', m.label, m.rarity, amount, { external = ChopShop.System(), stolen = m.stolen }) end
    if GetPlayerPing(src) > 0 then
        TriggerClientEvent('nz_cargo:source:externalChop', src, { label = m.label, rarity = m.rarity, amount = amount })
    end
end

-- One line in another chop script: exports['nayzeee-vehiclecargo']:VehicleChopped(source, plate)
local function cleanPlate(p) return tostring(p or ''):upper():gsub('%s+', '') end
exports('VehicleChopped', function(src, plate)
    local want = cleanPlate(plate)
    if want == '' then return false end
    local found
    for _, m in pairs(missions) do
        if m.kind == 'source' and cleanPlate(m.plate) == want then
            found = m
            if m.src == tonumber(src) then break end    -- prefer the player who chopped it
        end
    end
    if not found then return false end
    Source.ExternalChop(found)
    return true
end)

-----------------------------------------------------------------
-- Hijack: another player takes a car that still has its tracker on
-----------------------------------------------------------------
lib.callback.register('nz_cargo:hijack', function(src, netId)
    if not Config.Hijack.Enabled then return false end
    local m
    for _, x in pairs(missions) do if x.netId == tonumber(netId) then m = x end end
    if not m or m.src == src or m.stage ~= 'escape' then return false end
    if Config.Hijack.TrackedOnly and not m.tracker then return false end
    if not inDriverSeat(src, m) then return false end
    local thief = Server.Get(src)
    if not thief or thief.mission then return false end

    -- the old owner loses the car (the entity stays, the thief is driving it)
    local victim, victimName = m.src, (Server.Players[m.src] and Server.Players[m.src].name) or 'someone'
    finish(m, false, L('src_stolen'), true)
    Bridge.PhoneMessage(victim, L('sms_stolen', m.label))

    -- the thief stores it in their own warehouse, or chops it
    local w = Server.Owned(thief.identifier)[1]
    local chopOnly = not w or (m.illegal and (w.upgrades.lower or 0) < 1)
    if w and not chopOnly then
        local floor = m.illegal and 'lower' or 'main'
        if DB.CountStock(w.id, floor) + pendingFor(w.id, floor) >= Server.Capacity(w, floor) then chopOnly = true end
    end

    nextId = nextId + 1
    local n = {
        id = nextId, kind = 'source', src = src, wid = (not chopOnly) and w.id or nil, illegal = m.illegal,
        entity = m.entity, netId = m.netId, model = m.model, label = m.label, rarity = m.rarity, value = m.value,
        scenario = 'hijack', spot = m.spot, plate = m.plate, locked = false, tracker = m.tracker, hadTracker = true, stage = 'escape',
        expires = Server.Now() + Config.Sourcing.TimeLimit, peds = {}, stolen = true, chopOnly = chopOnly,
        pickedAt = Server.Now(), nextPing = Server.Now() + Config.Sourcing.Tracker.PingEvery, nextWave = Server.Now() + A.TrackerWave,
    }
    missions[n.id] = n
    thief.mission = n
    Radio.Start(n)
    Entity(n.entity).state:set('nzCargo', { mission = n.id, owner = src }, true)
    Server.Webhook('Vehicle hijacked', { Thief = thief.name, Victim = victimName, Vehicle = m.label })
    return clientData(n)
end)

-- Tracked cars other owners can hunt (laptop scanner app)
function Source.HotList(forSrc)
    local out = {}
    for _, m in pairs(missions) do
        if m.tracker and m.stage == 'escape' and m.src ~= forSrc and DoesEntityExist(m.entity) then
            local c = GetEntityCoords(m.entity)
            out[#out + 1] = { id = m.id, label = m.label, rarity = m.rarity, x = c.x, y = c.y, z = c.z, illegal = m.illegal }
        end
    end
    return out
end

-----------------------------------------------------------------
-- Watchdog: timeouts, tracker pings, police live tracking,
-- scanner pings, tracker attack waves, vanished vehicles
-----------------------------------------------------------------
local function policeIds()
    local jobs, out = {}, {}
    for _, j in ipairs(Config.Sourcing.PoliceJobs) do jobs[j] = true end
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local job, duty = Bridge.GetJob(id)
        if job and jobs[job] and duty then out[#out + 1] = id end
    end
    return out
end

local function scannerIds(exclude)
    local out = {}
    for psrc, st in pairs(Server.Players) do
        if psrc ~= exclude and st.identifier then
            local w = Server.Owned(st.identifier)[1]
            local intel = w and Cargo.Upgrade('intel', w.upgrades.intel)
            if intel and intel.scanner then out[#out + 1] = psrc end
        end
    end
    return out
end

CreateThread(function()
    local lastLive = 0
    while true do
        local any = false
        local now = Server.Now()
        local live = now - lastLive >= Config.Sourcing.Tracker.PoliceLive
        local police
        for _, m in pairs(missions) do
            any = true
            if m.stage == 'escape' and not m.tracker and DoesEntityExist(m.entity) then m.lastPos = GetEntityCoords(m.entity) end
            if now >= m.expires then
                fail(m, L('src_timeout'))
            elseif not DoesEntityExist(m.entity) then
                -- gone next to another script's chop shop = chopped there
                if ChopShop.External() and m.stage == 'escape' and ChopShop.Near(m.lastPos) then
                    Source.ExternalChop(m)
                else
                    fail(m, L('src_destroyed'))
                end
            elseif m.tracker and m.stage == 'escape' then
                local c = GetEntityCoords(m.entity)
                m.lastPos = c
                if live then
                    police = police or policeIds()
                    for _, pid in ipairs(police) do
                        TriggerClientEvent('nz_cargo:track', pid, { id = m.id, x = c.x, y = c.y, z = c.z, label = m.label, plate = m.plate })
                    end
                end
                if m.nextPing and now >= m.nextPing then
                    m.nextPing = now + Config.Sourcing.Tracker.PingEvery
                    Bridge.Dispatch({
                        title = L('dispatch_tracker'), message = ('%s · %s'):format(m.label, m.plate),
                        coords = c, code = '10-60', blip = { sprite = 225, colour = 1 }, plate = m.plate, model = m.model, src = m.src,
                    })
                    TriggerClientEvent('nz_cargo:source:ping', m.src)
                    if Config.Hijack.Enabled then
                        for _, sid in ipairs(scannerIds(m.src)) do
                            TriggerClientEvent('nz_cargo:hot', sid, { id = m.id, x = c.x, y = c.y, z = c.z, label = m.label, rarity = m.rarity })
                        end
                    end
                end
                if m.nextWave and now >= m.nextWave then
                    m.nextWave = now + A.TrackerWave
                    local wave = rollAttack('source', m.rarity) or { cars = 1, delay = 1 }
                    wave.delay = 1
                    TriggerClientEvent('nz_cargo:source:wave', m.src, m.id, wave)
                    Source.Text(m.src, 'tracker')
                end
            end
        end
        if live then lastLive = now end
        Wait(any and 1000 or 5000)
    end
end)

table.insert(Server.Cleanup, function(src, st)
    for _, m in pairs(missions) do
        if m.src == src then finish(m, false, L('src_abandoned')) end
    end
end)

-----------------------------------------------------------------
-- Crew jobs: one guarded lot, a car for everyone inside the
-- warehouse. Every car home = everyone gets the bonus.
-----------------------------------------------------------------
local crews, nextCrew = {}, 0

local function crewJob(id)
    for _, j in ipairs(Config.CrewJobs.Jobs) do if j.id == id then return j end end
end

-- owner / associates inside this warehouse who are free
local function crewHere(wid)
    local out = {}
    for _, o in ipairs(Server.Occupants(wid)) do
        local r = Server.Access(o, wid)
        local st = Server.Get(o)
        if (r == 'owner' or r == 'associate') and st and not st.mission then out[#out + 1] = o end
    end
    return out
end

function Source.CrewJobs(src, wid)
    local CJ = Config.CrewJobs
    if not CJ or not CJ.Enabled then return nil end
    local p = Server.Profile(src)
    local level = Server.Level(p)
    local here = #crewHere(wid)
    local out = {}
    for _, j in ipairs(CJ.Jobs) do
        local r = Cargo.Rarity[j.rarity] or {}
        out[#out + 1] = {
            id = j.id, label = j.label, icon = j.icon, desc = j.desc, level = j.level, fee = j.fee, cars = j.cars,
            rarity = j.rarity, rarityLabel = r.label, bonusCash = j.bonusCash, bonusXp = j.bonusXp,
            unlocked = level >= j.level, cd = math.max(0, ((p.contract_cd or {})['crew:' .. j.id] or 0) - Server.Now()),
        }
    end
    return { jobs = out, here = here, min = CJ.MinCrew }
end

crewDone = function(m, delivered)
    local g = crews[m.group]
    if not g then return end
    if delivered then g.delivered = g.delivered + 1 else g.failed = g.failed + 1 end
    if g.delivered + g.failed < g.total then return end
    crews[m.group] = nil
    for _, msrc in pairs(g.members) do
        if GetPlayerPing(msrc) > 0 then
            if g.failed == 0 then
                Bridge.AddMoney(msrc, Config.Accounts.Payout, g.job.bonusCash, 'vehiclecargo-crewbonus')
                Server.AddXp(msrc, g.job.bonusXp)
                Server.Notify(msrc, L('crew_bonus', lib.math.groupdigits(g.job.bonusCash)), 'success', g.job.label)
            else
                Server.Notify(msrc, L('crew_nobonus'), 'error', g.job.label)
            end
        end
    end
end

lib.callback.register('nz_cargo:crewjob:start', Server.Once('player', function(src, jobId)
    local CJ = Config.CrewJobs
    local job = CJ and CJ.Enabled and crewJob(jobId)
    local st = Server.Get(src)
    if not job or not st or not st.inside then return false end
    if st.mission then Server.Notify(src, L('busy'), 'error') return false end
    local wid = st.inside
    local w = DB.Warehouses[wid]
    if not w or not Server.Can(src, wid, 'crewjob') then Server.Notify(src, L('no_perm'), 'error') return false end
    local p = Server.Profile(src)
    if Server.Level(p) < job.level then Server.Notify(src, L('level_locked', job.level), 'error') return false end
    local key = 'crew:' .. job.id
    local cd = math.max(0, ((p.contract_cd or {})[key] or 0) - Server.Now())
    if cd > 0 then Server.Notify(src, L('cooldown', Cargo.FormatTime(cd)), 'error') return false end

    local crew = { src }
    for _, o in ipairs(crewHere(wid)) do
        if o ~= src and #crew < job.cars then crew[#crew + 1] = o end
    end
    if #crew < CJ.MinCrew then Server.Notify(src, L('crew_need', CJ.MinCrew), 'error') return false end
    if DB.CountStock(wid, 'main') + pendingFor(wid, 'main') + #crew > Server.Capacity(w, 'main') then
        Server.Notify(src, L('warehouse_full'), 'error') return false
    end
    if Config.Sourcing.MinPolice > 0 and Bridge.CountPolice() < Config.Sourcing.MinPolice then
        Server.Notify(src, L('not_enough_police'), 'error') return false
    end
    local pool = Server.PoolFor(job.rarity)
    if #pool == 0 then return false end
    local spotIndex, spot = pickSpot('crew')
    if not spotIndex then Server.Notify(src, L('busy'), 'error') return false end
    if not Server.Charge(src, job.fee, 'vehiclecargo-crewjob') then return false end
    p.contract_cd = p.contract_cd or {}
    p.contract_cd[key] = Server.Now() + (job.cooldown or Config.Sourcing.Cooldown)
    DB.SaveProfile(p)

    nextCrew = nextCrew + 1
    local g = { id = nextCrew, job = job, members = {}, total = 0, delivered = 0, failed = 0 }
    crews[g.id] = g
    -- cars side by side across the lot
    local h = math.rad(spot.w or 0.0)
    local rx, ry = math.cos(h), math.sin(h)
    local guards = crewSize('guarded', false) + #crew
    for i, member in ipairs(crew) do
        local off = (i - (#crew + 1) / 2) * 4.2
        local at = { x = spot.x + rx * off, y = spot.y + ry * off, z = spot.z, w = spot.w }
        local veh = pool[math.random(1, #pool)]
        local entity = spawnServer(veh.model, veh.type or Server.TypeOf(veh.model), at)
        local mst = Server.Get(member)
        if entity and mst then
            local plate = plateText()
            SetVehicleNumberPlateText(entity, plate)
            SetVehicleDoorsLocked(entity, 2)
            nextId = nextId + 1
            local m = {
                id = nextId, kind = 'source', src = member, wid = wid, illegal = false,
                entity = entity, netId = NetworkGetNetworkIdFromEntity(entity),
                model = veh.model, label = veh.label, rarity = job.rarity, contract = key, value = veh.value,
                scenario = 'crew', spot = DB.V4(at), spotKey = i == 1 and ('crew' .. spotIndex) or nil,
                plate = plate, locked = true, tracker = math.random() < (Config.Sourcing.TrackerChance[job.rarity] or 0), stage = 'travel',
                crew = i == 1 and guards or 0, crewLeader = i == 1, crewJob = job.label, group = g.id,
                expires = Server.Now() + Config.Sourcing.TimeLimit, peds = {}, attack = rollAttack('source', job.rarity),
            }
            m.hadTracker = m.tracker
            missions[m.id] = m
            if m.spotKey then usedSpots[m.spotKey] = m.id end
            mst.mission = m
            Radio.Start(m)
            Entity(entity).state:set('nzCargo', { mission = m.id, owner = member }, true)
            g.members[m.id] = member
            g.total = g.total + 1
            TriggerClientEvent('nz_cargo:crewjob:begin', member, clientData(m))
        end
    end
    if g.total == 0 then crews[g.id] = nil return false end
    DB.Log(st.identifier, wid, 'contract', job.label, job.rarity, -job.fee, { crew = #crew })
    return { ok = true }
end))
