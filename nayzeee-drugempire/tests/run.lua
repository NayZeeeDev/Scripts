--[[
    Headless server test: loads the real server code with stubbed natives and plays a
    character from the first text to a running operation.
    lua5.4 tests/run.lua <resource dir>
]]

local ROOT = arg[1] or '.'
package.path = ROOT .. '/tests/?.lua;' .. package.path
local S = require('stubs')

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1 print('  FAIL ' .. msg) end
end
local function section(name) print('\n== ' .. name) end

local function load(file)
    local chunk, err = loadfile(ROOT .. '/' .. file)
    assert(chunk, err)
    chunk()
end

for _, f in ipairs({
    'config/main.lua', 'config/products.lua', 'config/stations.lua', 'config/customers.lua', 'config/shops.lua',
    'shared/utils.lua', 'shared/mixing.lua', 'shared/grow.lua',
    'config/server.lua', 'bridge/framework/server.lua', 'bridge/inventory/server.lua', 'bridge/dispatch/server.lua',
    'server/guard.lua', 'server/db.lua', 'server/profile.lua', 'server/products.lua', 'server/quests.lua', 'server/messages.lua',
    'server/story.lua', 'server/rv.lua', 'server/stations.lua', 'server/customers.lua', 'server/dealers.lua',
    'server/deliveries.lua', 'server/phone.lua', 'server/admin.lua', 'server/main.lua',
}) do load(f) end

--[[ fake framework money + metadata inventory ]]
local money, inv = {}, {}
local function same(a, b) return json.encode(a or {}) == json.encode(b or {}) end
FW.getPlayer = function() return nil end
FW.charName = function(src) return 'Tester ' .. src end
FW.isPolice = function() return false end
FW.getMoney = function(src, acc) return (money[src] or {})[acc] or 0 end
FW.addMoney = function(src, acc, n) money[src] = money[src] or {} money[src][acc] = (money[src][acc] or 0) + n return true end
FW.removeMoney = function(src, acc, n)
    if FW.getMoney(src, acc) < n then return false end
    money[src][acc] = money[src][acc] - n
    return true
end
local slotSeq = 0
Inv.add = function(src, name, count, meta)
    inv[src] = inv[src] or {}
    for _, s in ipairs(inv[src]) do
        if s.name == name and same(s.meta, meta) then s.count = s.count + count return true end
    end
    slotSeq = slotSeq + 1
    table.insert(inv[src], { name = name, count = count, meta = meta or {}, slot = slotSeq })
    return true
end
Inv.count = function(src, name)
    local n = 0
    for _, s in ipairs(inv[src] or {}) do if s.name == name then n = n + s.count end end
    return n
end
Inv.has = function(src, name, c) return Inv.count(src, name) >= (c or 1) end
Inv.slots = function(src, name)
    local out = {}
    for _, s in ipairs(inv[src] or {}) do if s.name == name and s.count > 0 then out[#out + 1] = { slot = s.slot, count = s.count, meta = s.meta } end end
    return out
end
Inv.removeSlot = function(src, name, count, slot)
    for i, s in ipairs(inv[src] or {}) do
        if s.slot == slot and s.name == name then
            if s.count < count then return false end
            s.count = s.count - count
            if s.count == 0 then table.remove(inv[src], i) end
            return true
        end
    end
    return false
end
Inv.remove = function(src, name, count)
    count = count or 1
    if Inv.count(src, name) < count then return false end
    for _, s in ipairs(Inv.slots(src, name)) do
        local take = math.min(count, s.count)
        Inv.removeSlot(src, name, take, s.slot)
        count = count - take
        if count == 0 then break end
    end
    return true
end
Inv.canCarry = function() return true end
Inv.payMoney = function(src, amount) return FW.addMoney(src, 'cash', amount) end
Dispatch.alert = function() S.alerts = (S.alerts or 0) + 1 end

local function finishAction(src, action, oid, args)
    local okc, extra = S.call(src, 'nzde:st:claim', action, oid, args)
    if not okc then return false, extra end
    S.advance(((Config.Actions[action].minSeconds or 1) + 1) * 1000 + 30000)
    return S.call(src, 'nzde:st:finish')
end

--[[ ─────────────────────────── unit: mixing ─────────────────────────── ]]
section('mixing')
local e1 = Mix.apply({ 'calming' }, 'nz_cuke')
ok(e1[1] == 'calming' and e1[2] == 'energizing' and #e1 == 2, 'cuke adds energizing')
local e2 = Mix.apply({ 'calming' }, 'nz_paracetamol')
ok(e2[1] == 'slippery' and e2[2] == 'sneaky', 'paracetamol turns calming into slippery and adds sneaky')
local e3 = Mix.apply(e1, 'nz_banana')
ok(e3[2] == 'thought_provoking' and e3[3] == 'gingeritis', 'banana: energizing -> thought provoking + gingeritis')
ok(Mix.value('ogkush', { 'calming' }) == math.floor(38 * 1.10 + 0.5), 'value = base x (1 + multipliers)')
ok(Mix.key('ogkush', { 'b', 'a' }) == Mix.key('ogkush', { 'a', 'b' }), 'mix key is order independent')
local full = {}
for k in pairs(Config.Effects) do if #full < 8 then full[#full + 1] = k end end
ok(#Mix.apply(full, 'nz_horsesemen') <= Config.Mixing.maxEffects, 'never more than max effects')

section('growth')
local g = { soil = 1, seed = 'x', crop = 'weed', growth = 0.0, water = 1.0, t = 0 }
Grow.tick(g, 12 * 60, 1.0)
ok(math.abs(g.growth - 12 / 30) < 1e-6 and g.water == 0, 'grows only while watered (12 of 30 min)')
Grow.tick(g, 40 * 60, 1.0)
ok(math.abs(g.growth - 12 / 30) < 1e-6, 'no growth while dry')
ok(Grow.stage(g) == 2, 'stage 2 at 40%')
ok(Utils.levelFromXp(0) == 1 and Utils.rankLabel(1) == 'Street Rat I' and Utils.rankLabel(6) == 'Hoodlum I', 'rank labels')

--[[ ─────────────────────────── story ─────────────────────────── ]]
section('story')
local P1 = 1
S.join(P1, vec3(100, 100, 30))
FW.addMoney(P1, 'bank', 50000)
S.fire(P1, 'nzde:ready')
local P = Profile.get(P1)
ok(P ~= nil and P.story.stage == 'none', 'profile loaded, stage none')
S.advance(200 * 1000)
ok(P.story.stage == 'texted', 'unknown number texted')
ok(S.lastClient('nzde:story:text') ~= nil, 'text card sent')

S.fire(P1, 'nzde:story:answer', false)
ok(P.story.stage == 'texted' and P.story.ignoredAt, 'ignored')
S.advance(Config.Story.retextMinutes * 60 * 1000 + 2000)
ok(P.story.ignoredAt == nil, 'texted again after ignoring')
S.advance(1500)
S.fire(P1, 'nzde:story:answer', true)
ok(P.story.stage == 'meet', 'going to meet')

local spot = Story.bensonSpot(P)
ok(S.call(P1, 'nzde:story:talk') == false, 'cannot talk from far away')
S.move(P1, spot)
ok(S.call(P1, 'nzde:story:talk') == 'intro', 'intro conversation')
ok(S.call(P1, 'nzde:story:done', 'intro') == true, 'intro done')
ok(P.story.stage == 'steal' and P.story.met, 'sent to steal the RV')
local mnet = Story.missionNet(P1)
ok(mnet ~= nil, 'mission RV spawned')
local mveh = NetworkGetEntityFromNetworkId(mnet)

S.fire(P1, 'nzde:story:stolen')
ok(P.story.stage == 'steal', 'not stolen while not in the RV')
S.inveh[P1] = mveh
S.fire(P1, 'nzde:story:stolen')
ok(P.story.stage == 'return', 'RV stolen')
ok(S.call(P1, 'nzde:story:talk') == 'noRv', 'Benson wants the RV close')
S.moveEnt(mveh, spot)
S.inveh[P1] = nil
ok(S.call(P1, 'nzde:story:talk') == 'rv', 'RV back at Benson')
S.advance(3000)
ok(S.call(P1, 'nzde:story:done', 'rv') == true, 'starter kit handed over')
ok(P.story.stage == 'setup' and P.story.app == true and P.rv.owned, 'app installed, RV owned')
ok(Inv.count(P1, 'nz_pot') == 2 and Inv.count(P1, 'nz_seed_ogkush') == 1 and Inv.count(P1, 'nz_packer') == 1, 'starter kit in inventory')
ok(P.customers.andy and P.customers.andy.u, 'starter customers unlocked')
ok(P.quests.done.contact and P.quests.done.wheels, 'first two journal quests done')

--[[ ─────────────────────────── the lab ─────────────────────────── ]]
section('RV lab')
local rveh = RV.vehicle(P1)
ok(rveh == mveh, 'story RV became the owned RV')
S.move(P1, GetEntityCoords(rveh) + vec3(2, 0, 0))
local entered, data = S.call(P1, 'nzde:rv:enter', 'shell')
ok(entered and data and data.objects, 'entered the RV')
ok(S.buckets[P1] == Config.RV.bucketBase + P1, 'own routing bucket')
local O = Config.RV.shell.origin
S.move(P1, O + vec3(0, 0, 1))
ok(S.call(P1, 'nzde:rv:place', 'nz_pot', 1.0, 0.0, 0.05, 90.0) == true, 'placed a pot')
ok(S.call(P1, 'nzde:rv:place', 'nz_pot', 9.0, 0.0, 0.05, 90.0) == false, 'cannot place outside the RV')
ok(S.call(P1, 'nzde:rv:place', 'nz_chem', 1.0, 1.0, 0.05, 0.0) == false, 'locked / missing equipment refused')
local potId
for id, o in pairs(P.objects) do if o.type == 'pot' then potId = id end end
ok(potId ~= nil and Inv.count(P1, 'nz_pot') == 1, 'pot object stored, item used')

-- too fast = rejected
local c1 = S.call(P1, 'nzde:st:claim', 'pot_soil', potId, { item = 'nz_soil' })
ok(c1 == true, 'soil claim ok')
ok(S.call(P1, 'nzde:st:finish') == false, 'instant finish rejected')
local r, err = finishAction(P1, 'pot_soil', potId, { item = 'nz_soil' })
ok(r == true, 'soil poured ' .. tostring(err))
ok(P.objects[potId].st.soil == 1 and Inv.count(P1, 'nz_soil') == 1, 'pot has soil')
ok(finishAction(P1, 'pot_seed', potId, { item = 'nz_seed_ogkush' }) == true, 'seed planted')
ok(finishAction(P1, 'pot_water', potId) == false, 'cannot water with an empty can')
S.move(P1, O + Config.RV.shell.sink)
ok(finishAction(P1, 'sink_fill', nil) == true, 'filled the watering can at the tap')
ok(P.water == Config.WateringCan.capacity, 'can full')
S.move(P1, O + vec3(1, 0, 1))
ok(finishAction(P1, 'pot_water', potId) == true, 'watered')
ok(P.quests.done.start, 'Getting Started complete')

-- grow it: water every 11 minutes
for _ = 1, 4 do
    S.advance(11 * 60 * 1000)
    if P.water < 1 then S.move(P1, O + Config.RV.shell.sink) finishAction(P1, 'sink_fill', nil) S.move(P1, O + vec3(1, 0, 1)) end
    finishAction(P1, 'pot_water', potId)
end
Stations.tickAll(P1)
ok(Grow.stage(P.objects[potId].st) == 4, 'plant fully grown (growth ' .. tostring(P.objects[potId].st.growth) .. ')')
local okh, extra = S.call(P1, 'nzde:st:claim', 'pot_harvest', potId, {})
ok(okh and extra and extra.count >= 8, 'harvest claim returns bud count')
S.advance(5000)
ok(S.call(P1, 'nzde:st:finish') == true, 'harvested')
local weed = Inv.count(P1, 'nz_weed')
ok(weed >= 8, 'got weed: ' .. weed)
ok(Inv.slots(P1, 'nz_weed')[1].meta.pid == 'ogkush', 'weed carries product metadata')
ok(P.objects[potId].st.soil == 0 and not P.objects[potId].st.seed, 'pot emptied')

-- packaging
ok(S.call(P1, 'nzde:rv:place', 'nz_packer', -1.0, 1.0, 0.05, 0.0) == true, 'placed packaging station')
local packId
for id, o in pairs(P.objects) do if o.type == 'packer' then packId = id end end
local panel = S.call(P1, 'nzde:panel:open', packId)
ok(panel and #panel.stacks == 1 and panel.baggies == 20, 'packaging panel lists product and baggies')
local st1 = panel.stacks[1]
ok(finishAction(P1, 'pack_baggie', packId, { item = st1.item, pid = st1.pid, q = st1.q, n = 6 }) == true, 'packed 6 baggies')
ok(Inv.count(P1, 'nz_baggie') == 6 and Inv.count(P1, 'nz_weed') == weed - 6, 'baggies made, weed used')
ok(P.quests.done.wrap, 'Wrapping Up complete')

--[[ ─────────────────────────── selling ─────────────────────────── ]]
section('customers')
S.call(P1, 'nzde:rv:exit')
ok(S.buckets[P1] == 0, 'left the RV')
ok(S.call(P1, 'nzde:phone:tab', 'contacts') == true, 'opened contacts')
ok(Customers.sampleable(P, 'chelsey'), 'Chelsey can be sampled')
ok(S.call(P1, 'nzde:cust:sampleTarget', 'chelsey') == true, 'sample target set')
S.move(P1, Config.Spots[Config.Customers.chelsey.home].coords)
local stock = S.call(P1, 'nzde:cust:stock')
ok(#stock == 1 and stock[1].pid == 'ogkush' and stock[1].n == 6, 'stock shows bagged weed')
local sok, sres = S.call(P1, 'nzde:cust:sample', stock[1].pid, stock[1].q)
ok(sok and sres.ok, 'first sample always lands')
ok(P.customers.chelsey.u, 'Chelsey is a customer')

P.nextDeal = 0
local reqs = 0
for _ = 1, 3 do if Customers.request(P1) then reqs = reqs + 1 end end
ok(reqs >= 1 and #P.deals >= 1, 'deal requests texted')
local d = P.deals[1]
d.qty = 2
local okr = S.call(P1, 'nzde:deal:respond', d.id, 'accept')
ok(okr and d.state == 'accepted', 'deal accepted')
S.move(P1, vec3(0, 0, 0))
ok(S.call(P1, 'nzde:deal:handover', d.id, 0) == false, 'hand-over refused from far away')
S.advance(3000)
S.move(P1, Config.Spots[d.spot].coords)
local before = FW.getMoney(P1, 'cash')
local hok, hres = S.call(P1, 'nzde:deal:handover', d.id, 0)
ok(hok and hres.price == d.price, 'deal done')
ok(FW.getMoney(P1, 'cash') == before + d.price, 'paid in cash')
ok(Inv.count(P1, 'nz_baggie') == 3, 'two baggies gone (sample + 2)')
ok(P.stats.deals == 1 and P.stats.sold == 2, 'stats updated')

section('counter offers + missed deals')
P.nextDeal = 0
P.deals = {}
for cid, c in pairs(P.customers) do c.last = 0 end
Customers.request(P1)
local d2 = P.deals[1]
ok(d2 ~= nil, 'another request')
if d2 then
    S.advance(1000)
    S.call(P1, 'nzde:deal:respond', d2.id, 'counter', d2.price * 10)
    ok(#P.deals == 0 or P.deals[1].state == 'accepted', 'greedy counter resolved')
end
Customers.request(P1)
local d3 = P.deals[1]
if d3 then
    S.advance(1000)
    S.call(P1, 'nzde:deal:respond', d3.id, 'accept')
    local relBefore = P.customers[d3.cid].rel
    S.advance((Config.Deals.windowMinutes + Config.Deals.lateGrace + 1) * 60 * 1000)
    Customers.tick(P1)
    ok(P.customers[d3.cid].rel < relBefore, 'no-show hurts the relationship')
end

--[[ ─────────────────────────── mixing station ─────────────────────────── ]]
section('mixing station')
Profile.addXp(P1, 2000, 'test')
ok(Profile.level(P) >= 6, 'level up to ' .. Utils.rankLabel(Profile.level(P)))
Inv.add(P1, 'nz_mixer', 1)
Inv.add(P1, 'nz_cuke', 5)
S.move(P1, GetEntityCoords(RV.vehicle(P1)) + vec3(1, 0, 0))
ok(S.call(P1, 'nzde:rv:enter', 'shell') == true, 're-entered the RV')
S.move(P1, O + vec3(0, 0, 1))
ok(S.call(P1, 'nzde:rv:place', 'nz_mixer', 0.0, 2.0, 0.05, 0.0) == true, 'placed mixer')
local mixId
for id, o in pairs(P.objects) do if o.type == 'mixer' then mixId = id end end
local mp = S.call(P1, 'nzde:panel:open', mixId)
ok(mp and #mp.ingredients == 1, 'mixer lists ingredients')
local ws = mp.stacks[1]
S.advance(10000)
local mixN = math.min(3, ws.n)
local mok, mres = S.call(P1, 'nzde:panel:mix', mixId, ws.item, ws.pid, ws.q, 'nz_cuke', mixN)
ok(mok and mres.product and mres.product.effects[2] == 'energizing', 'new product mixed: ' .. tostring(type(mres) == 'table' and mres.product and mres.product.name or mres))
ok(P.products[mres.product.id] ~= nil, 'discovered')
ok(Inv.count(P1, 'nz_cuke') == 5 - mixN, 'ingredients used')
ok(S.call(P1, 'nzde:panel:mix', mixId, ws.item, ws.pid, ws.q, 'nz_cuke', 99) == false, 'cannot mix more than you have')

section('grow tent')
Inv.add(P1, 'nz_tent', 1)
Inv.add(P1, 'nz_seed_sourdiesel', 1)
ok(S.call(P1, 'nzde:rv:place', 'nz_tent', -2.0, -1.0, 0.05, 0.0) == true, 'placed a grow tent')
local tentId
for tid, o in pairs(P.objects) do if o.type == 'tent' then tentId = tid end end
S.move(P1, O + vec3(-2, -1, 1))
ok(finishAction(P1, 'pot_soil', tentId, { item = 'nz_soil' }) == true, 'soil in the tent')
ok(finishAction(P1, 'pot_seed', tentId, { item = 'nz_seed_sourdiesel' }) == true, 'Sour Diesel planted in the tent')
P.water = 4
ok(finishAction(P1, 'pot_water', tentId) == true, 'tent watered')
local g0 = P.objects[tentId].st.growth
S.advance(10 * 60 * 1000)
Stations.tickAll(P1)
local grown = P.objects[tentId].st.growth - g0
ok(math.abs(grown - 10 * Config.Stations.tent.boost / 30) < 0.02, ('tent grows %.0f%% faster (%.3f)'):format((Config.Stations.tent.boost - 1) * 100, grown))
ok(S.call(P1, 'nzde:rv:pickup', tentId) == false, 'cannot pick up a tent with a plant in it')

--[[ ─────────────────────────── deliveries ─────────────────────────── ]]
section('deliveries')
local oko, ores = S.call(P1, 'nzde:order:place', 'hardware', { nz_soil = 3, nz_pot = 1 }, 'sandy_bins', 'bank')
ok(oko and ores.total == 3 * 10 + 20, 'order placed')
local oid = P.orders[#P.orders].id
ok(S.call(P1, 'nzde:order:collect', oid) == false, 'not ready yet')
S.advance(5 * 60 * 1000)
Deliveries.tick(P1)
S.call(P1, 'nzde:rv:exit')
local drop = Deliveries.drop('sandy_bins')
S.move(P1, drop.coords)
local soilBefore = Inv.count(P1, 'nz_soil')
ok(S.call(P1, 'nzde:order:collect', oid) == true, 'collected')
ok(Inv.count(P1, 'nz_soil') == soilBefore + 3, 'items delivered')

--[[ ─────────────────────────── dealers ─────────────────────────── ]]
section('dealers')
ok(S.call(P1, 'nzde:dealer:hire', 'benji', 'bank') == true, 'hired Benji')
ok(S.call(P1, 'nzde:dealer:assign', 'benji', 'doug', true) == true, 'assigned Doug')
Inv.add(P1, 'nz_baggie', 10, Products.meta('ogkush', 2, 1))
S.move(P1, Config.DealerList.benji.coords)
local gok = S.call(P1, 'nzde:dealer:give', 'benji', 'ogkush', 0, 6)
ok(gok, 'stocked Benji')
for _ = 1, 6 do S.advance(Config.Dealers.tickMinutes * 60 * 1000 + 1000) Dealers.tick(P1) end
ok(P.dealers.benji.cash > 0, 'Benji made money: ' .. math.floor(P.dealers.benji.cash))
local cash0 = FW.getMoney(P1, 'cash')
local cok, got = S.call(P1, 'nzde:dealer:collect', 'benji')
ok(cok and FW.getMoney(P1, 'cash') == cash0 + got, 'collected dealer cash')

--[[ ─────────────────────────── phone + persistence ─────────────────────────── ]]
section('phone + save')
local pd = S.call(P1, 'nzde:phone:data')
ok(pd and pd.me and #pd.threads > 0 and #pd.products >= 2 and pd.deliveries and pd.map, 'phone data complete')
local id = Profile.identifier(P1)
Profile.dirty(P1)
Profile.save(P1)
ok(S.db[id] ~= nil and #S.db[id] > 100, 'profile saved')
source = P1
for _, fn in ipairs(S.events['playerDropped'] or {}) do fn() end
source = nil
ok(Profile.get(P1) == nil, 'unloaded on drop')
ok(RV.vehicle(P1) == nil, 'RV stored on drop')

--[[ ─────────────────────────── exploits ─────────────────────────── ]]
section('exploits')
local P2 = 2
S.join(P2, vec3(0, 0, 0))
S.fire(P2, 'nzde:ready')
ok(S.call(P2, 'nzde:rv:enter', 'shell') == false, 'no RV, no lab')
ok(S.call(P2, 'nzde:story:done', 'rv') == false, 'cannot skip the story')
ok(S.call(P2, 'nzde:st:claim', 'pot_harvest', 'o1', {}) == false, 'cannot touch other people\'s equipment')
ok(S.call(P2, 'nzde:order:place', 'hardware', { nz_soil = 1 }, 'sandy_bins', 'bank') == false, 'no app, no orders')

print(('\n%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
