-----------------------------------------------------------------
-- Police raids and insurance claims
-- Heat builds on a warehouse as cars are stored (hot cars more).
-- At the threshold police get a warrant to enter and seize cars;
-- with too few police on duty the cars are seized automatically.
-----------------------------------------------------------------
Raid = {}
local R = Config.Raids
local I = Config.Insurance

local function ownerSrc(w)
    for src, st in pairs(Server.Players) do
        if st.identifier == w.owner then return src end
    end
end

local function decay(w)
    local now = Server.Now()
    if (w.heat_at or 0) == 0 then w.heat_at = now return end
    local hours = (now - w.heat_at) / 3600
    if hours >= 0.05 then
        w.heat = math.max(0, (w.heat or 0) - hours * R.Decay)
        w.heat_at = now
    end
end

function Raid.Heat(w)
    if not R.Enabled or not w then return 0 end
    decay(w)
    return math.floor(w.heat or 0)
end

function Raid.AddHeat(wid, kind)
    if not R.Enabled then return end
    local w = DB.Warehouses[wid]
    if not w then return end
    decay(w)
    local before = w.heat or 0
    w.heat = math.min(R.Threshold * 1.5, before + (R.Heat[kind] or 0))
    DB.SaveWarehouse(w)
    if before < R.Warn and w.heat >= R.Warn then
        local src = ownerSrc(w)
        if src then Source.Contact(src, 'raid') end
    end
end

-----------------------------------------------------------------
-- Insurance
-----------------------------------------------------------------
function Raid.Insurable(item)
    if not I.Enabled or item.insured then return false end
    if Cargo.IsIllegal(item.base_rarity) and not I.Illegal then return false end
    if item.hot and not I.Hot then return false end
    return true
end

function Raid.Premium(w, item)
    return math.floor(Cargo.BaseValue(item, w.upgrades.contacts) * I.Premium)
end

-- The car is gone: the policy pays into the warehouse's claims balance
function Raid.Claim(w, item, reason)
    if not I.Enabled or not item or not item.insured then return 0 end
    local amount = math.floor(Cargo.BaseValue(item, w.upgrades.contacts) * I.Payout)
    w.claims = (w.claims or 0) + amount
    DB.SaveWarehouse(w)
    DB.Log(w.owner, w.id, 'claim', item.label, item.rarity, amount, { reason = reason })
    local src = ownerSrc(w)
    if src then Server.Notify(src, L('claim_paid', item.label, lib.math.groupdigits(amount)), 'success', 'Insurance') end
    return amount
end

-----------------------------------------------------------------
-- Raids
-----------------------------------------------------------------
local function seize(w, item, officer)
    DB.DeleteStock(item.id)
    DB.Log(w.owner, w.id, 'seized', item.label, item.rarity, 0, { officer = officer and Server.Get(officer) and Server.Get(officer).name or nil })
    Raid.Claim(w, item, 'seized')
    if officer and (R.PoliceReward or 0) > 0 then
        Bridge.AddMoney(officer, Config.Accounts.Payout, math.floor(Cargo.BaseValue(item, 0) * R.PoliceReward), 'vehiclecargo-seizure')
    end
end

local function closeRaid(w)
    if not w.raid then return end
    local police = w.raid.police
    w.raid = nil
    w.heat = R.After
    w.heat_at = Server.Now()
    w.raidedAt = Server.Now()
    DB.SaveWarehouse(w)
    TriggerClientEvent('nz_cargo:raid:close', -1, w.id)
    for src, st in pairs(Server.Players) do
        if st.inside == w.id and police[st.identifier] then TriggerClientEvent('nz_cargo:kick', src) end
    end
end

-- No police around: the cars are taken while nobody is looking
local function npcRaid(w)
    local list = {}
    for _, s in ipairs(DB.GetStock(w.id)) do if s.status == 'stored' then list[#list + 1] = s end end
    table.sort(list, function(a, b)
        if a.hot ~= b.hot then return a.hot end
        return (a.value or 0) > (b.value or 0)
    end)
    local taken = {}
    for i = 1, math.min(R.Seize, #list) do
        seize(w, list[i])
        taken[#taken + 1] = list[i].label
    end
    w.heat = R.After
    w.heat_at = Server.Now()
    w.raidedAt = Server.Now()
    DB.SaveWarehouse(w)
    Warehouse.Refresh(w.id)
    local src = ownerSrc(w)
    if src and #taken > 0 then
        Bridge.PhoneMessage(src, L('raid_npc_text', table.concat(taken, ', ')))
        Server.Notify(src, L('raid_npc', #taken), 'error', 'Raid')
    end
    Server.Webhook('Warehouse raided', { Warehouse = w.id, Owner = w.owner_name, Seized = #taken, Police = 'none' })
end

local function policeRaid(w)
    local loc = DB.Locations[w.location]
    if not loc then return end
    w.raid = { ends = Server.Now() + R.Window, police = {} }
    local door = loc.door
    Bridge.Dispatch({
        title = L('dispatch_raid'), message = ('%s · %s'):format(loc.name, w.owner_name or ''), coords = vector3(door.x, door.y, door.z),
        code = '10-99', blip = { sprite = 473, colour = 3 },
    })
    local jobs = {}
    for _, j in ipairs(Config.Sourcing.PoliceJobs) do jobs[j] = true end
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local job, duty = Bridge.GetJob(id)
        if job and jobs[job] and duty then
            TriggerClientEvent('nz_cargo:raid:open', id, { wid = w.id, door = door, name = loc.name, owner = w.owner_name, time = R.Window })
        end
    end
    local src = ownerSrc(w)
    if src then
        Bridge.PhoneMessage(src, L('raid_text', loc.name))
        Server.Notify(src, L('raid_started'), 'error', 'Raid')
    end
    Server.Webhook('Warehouse raided', { Warehouse = w.id, Owner = w.owner_name, Police = 'warrant open' })
    SetTimeout(R.Window * 1000, function() closeRaid(w) end)
end

-- Police side: enter the warehouse and seize cars
lib.callback.register('nz_cargo:raid:enter', function(src, wid)
    local w = DB.Warehouses[tonumber(wid)]
    local st = Server.Get(src)
    if not w or not w.raid or not st then return nil end
    local job, duty = Bridge.GetJob(src)
    local ok = false
    for _, j in ipairs(Config.Sourcing.PoliceJobs) do if j == job then ok = duty end end
    if not ok then return nil end
    local loc = DB.Locations[w.location]
    if loc and #(GetEntityCoords(GetPlayerPed(src)) - vector3(loc.door.x, loc.door.y, loc.door.z)) > 8.0 then return nil end
    w.raid.police[st.identifier] = true
    Server.PutInBucket(src, w.id)
    return Warehouse.EnterPayload(src, w, 'police')
end)

lib.callback.register('nz_cargo:raid:seize', function(src, stockId)
    local st = Server.Get(src)
    local w = st and st.inside and DB.Warehouses[st.inside]
    if not w or not w.raid or not w.raid.police[st.identifier] then return false end
    local item = DB.GetStockItem(tonumber(stockId))
    if not item or item.warehouse ~= w.id or item.status ~= 'stored' then return false end
    seize(w, item, src)
    Server.Notify(src, L('raid_seized', item.label), 'success', 'Raid')
    local owner = ownerSrc(w)
    if owner then Server.Notify(owner, L('raid_seized_owner', item.label), 'error', 'Raid') end
    Warehouse.Refresh(w.id)
    return true
end)

-- Owner side: pay the heat down
lib.callback.register('nz_cargo:bribe', function(src, steps)
    local s, w = Warehouse.Ctx(src, 'bribe')
    steps = math.floor(tonumber(steps) or 1)
    if not s or steps < 1 or not R.Enabled then return false end
    if w.raid then Server.Notify(src, L('raid_bribe_late'), 'error') return false end
    local heat = Raid.Heat(w)
    if heat <= 0 then return false end
    steps = math.min(steps, math.ceil(heat / R.Bribe.Step))
    local cost = steps * R.Bribe.Price
    if not Server.Charge(src, cost, 'vehiclecargo-bribe') then return false end
    w.heat = math.max(0, heat - steps * R.Bribe.Step)
    DB.SaveWarehouse(w)
    DB.Log(s.identifier, w.id, 'bribe', 'Paid off a contact', nil, -cost, { heat = steps * R.Bribe.Step })
    Server.Notify(src, L('raid_bribed', lib.math.groupdigits(cost)), 'success')
    return Warehouse.Payload(src, w.id)
end)

-- One pass over every warehouse: start raids where the heat is too high
function Raid.Check()
    if not R.Enabled then return end
    local now = Server.Now()
    local police
    for _, w in pairs(DB.Warehouses) do
        if not w.raid and Raid.Heat(w) >= R.Threshold and now - (w.raidedAt or 0) > R.Window * 2 then
            police = police or Bridge.CountPolice()
            if police >= R.MinPolice then policeRaid(w) else npcRaid(w) end
        end
    end
end

CreateThread(function()
    if not R.Enabled then return end
    while true do
        Wait(R.CheckEvery * 1000)
        Raid.Check()
    end
end)
