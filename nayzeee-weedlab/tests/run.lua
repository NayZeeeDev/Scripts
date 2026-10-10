--[[
    Headless server test: loads the real server code with stubbed natives and plays a
    character from finding Uncle Benson to a running weed operation.
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

math.randomseed(7)
for _, f in ipairs({
    'config/main.lua', 'config/strains.lua', 'config/equipment.lua', 'config/shop.lua',
    'shared/utils.lua', 'shared/mixing.lua', 'shared/grow.lua',
    'config/server.lua', 'bridge/framework/server.lua', 'bridge/inventory/server.lua', 'bridge/dispatch/server.lua',
    'server/guard.lua', 'server/db.lua', 'server/profile.lua', 'server/products.lua', 'server/story.lua',
    'server/labs.lua', 'server/stations.lua', 'server/shop.lua', 'server/selling.lua', 'server/admin.lua', 'server/main.lua',
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
Inv.canCarry = function() return true end
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
        if count <= 0 then break end
    end
    return true
end
local function metaOf(src, name)
    local s = Inv.slots(src, name)[1]
    return s and s.meta or {}
end

local A = 1          -- the player
local B = 2          -- somebody else
local function P() return Profile.get(A) end
local function stage() return P().story.stage end
local function call(name, ...) return S.call(A, name, ...) end
local function claimFinish(action, oid, args, secs, extra)
    local okc, err = call('nzwl:st:claim', action, oid, args)
    if not okc then return false, err end
    S.advance((secs or 5) * 1000)
    return call('nzwl:st:finish', extra)
end

--[[ ─────────────────────────────── boot ─────────────────────────────── ]]
section('boot')
S.join(A, vec3(0, 0, 0))
S.join(B, vec3(0, 0, 0))
S.fire(A, 'nzwl:ready')
S.fire(B, 'nzwl:ready')
ok(P() ~= nil, 'profile loaded')
ok(stage() == 'none', 'starts with no story')
ok(Profile.level(P()) == 0, 'starts at level 0')
ok(GlobalState.nzwlBenson == Story.spot and Config.Benson.spots[Story.spot] ~= nil, 'Benson has a spot this restart')
local st = S.lastClient('nzwl:state')
ok(st and st.args[1].level == 0, 'state synced to the client')

--[[ ─────────────────────────────── Benson ─────────────────────────────── ]]
section('Uncle Benson')
ok(call('nzwl:story:talk') == false, 'can\'t talk to Benson from across the map')
local benson = Config.Benson.spots[Story.spot]
S.move(A, benson)
ok(call('nzwl:story:talk') == 'intro', 'first talk is the intro')
ok(call('nzwl:story:accept') == true, 'accept the RV job')
ok(stage() == 'steal', 'stage: steal')
local m = S.lastClient('nzwl:story:mission')
ok(m and m.args[1].net, 'mission RV spawned and sent to the client')
ok(call('nzwl:story:talk') == 'waiting', 'Benson waits for the RV')

--[[ ─────────────────────────────── the Ballas RV ─────────────────────────────── ]]
section('the Ballas RV')
local veh = NetworkGetEntityFromNetworkId(m.args[1].net)
S.fire(A, 'nzwl:story:stolen')
ok(stage() == 'steal', 'not stolen while not in the driver seat')
S.inveh[A] = veh
S.fire(A, 'nzwl:story:stolen')
ok(stage() == 'escape', 'stage: escape once in the RV')
S.runThreads()
ok(stage() == 'escape', 'still escaping near the Ballas')
local spot = Config.Story.rv.spots[P().story.rvSpot].vehicle
S.moveEnt(veh, vec3(spot.x + Config.Story.rv.escapeDistance + 10, spot.y, spot.z))
S.runThreads()
ok(stage() == 'deaddrop', 'lost the Ballas -> dead drop')
ok(P().labs.rv.owned == true, 'the RV is now the player\'s lab')
ok(Labs.rvNet(A) ~= nil, 'RV registered as the player\'s')
ok(P().xp == Config.Levels.xp.rv, 'xp for the RV')
S.inveh[A] = nil

--[[ ─────────────────────────────── dead drop ─────────────────────────────── ]]
section('dead drop')
ok(call('nzwl:story:search') == false, 'can\'t search from far away')
S.move(A, Config.Story.deadDrop.spots[P().story.drop])
ok(call('nzwl:story:search') == true, 'search started at the drop')
ok(call('nzwl:story:searched') == false, 'searching instantly is rejected')
ok(call('nzwl:story:search') == true, 'search again')
S.advance(Config.Story.deadDrop.searchSeconds * 1000)
local got, n = call('nzwl:story:searched')
ok(got and n >= 2 and n <= 3, '2-3 seeds found')
ok(Inv.count(A, 'nzw_seed_ogkush') == n, 'seeds in the inventory')
ok(stage() == 'hardware', 'stage: hardware')

--[[ ─────────────────────────────── hardware store ─────────────────────────────── ]]
section('hardware store')
money[A] = { cash = 2000, bank = 0 }
ok(call('nzwl:shop:open') == false, 'store only opens at a store')
S.move(A, Config.Stores[1].ped)
local shop = call('nzwl:shop:open')
ok(shop and #shop.items > 10, 'catalogue loaded')
local tent
for _, it in ipairs(shop.items) do if it.item == 'nzw_growtent' then tent = it end end
ok(tent and tent.locked, 'grow tent is locked at level 0')
local okb, err = call('nzwl:shop:buy', { { item = 'nzw_growtent', n = 1 } }, 'cash')
ok(not okb and err and err:find('level'), 'can\'t buy a locked item')
S.advance(2000)
local basket = {
    { item = 'nzw_pot', n = 4 }, { item = 'nzw_soil', n = 4 }, { item = 'nzw_wateringcan', n = 1 }, { item = 'nzw_trimmers', n = 1 },
    { item = 'nzw_packstation', n = 1 }, { item = 'nzw_baggie_empty', n = 20 }, { item = 'nzw_fertilizer', n = 1 },
}
local okb2, total = call('nzwl:shop:buy', basket, 'cash')
ok(okb2 and total == 4 * 60 + 4 * 25 + 40 + 30 + 300 + 20 * 2 + 45, 'basket paid ($' .. tostring(total) .. ')')
ok(money[A].cash == 2000 - total, 'cash taken')
ok(Inv.count(A, 'nzw_pot') == 4, 'pots in the inventory')
ok(stage() == 'setup', 'stage: setup')

--[[ ─────────────────────────────── the RV lab ─────────────────────────────── ]]
section('the RV lab')
ok(call('nzwl:lab:enter', 'rv', 'ipl') == false, 'can\'t enter the RV from the store')
S.move(A, GetEntityCoords(Labs.vehicle(A)))
local okE, data = call('nzwl:lab:enter', 'rv', 'ipl')
ok(okE and data.objects, 'entered the RV')
ok(S.buckets[A] == Config.Buckets.base + A, 'own routing bucket inside')
local cfg = Utils.labInterior('rv', 'ipl')
local o = cfg.origin
S.move(A, vec3(o.x, o.y, o.z + 1.0))
local placed = {}
local function place(item, x, y)
    local before = Utils.count(P().labs.rv.objects)
    local r, e = call('nzwl:lab:place', item, x, y, 0.0, 0.0)
    if r then
        for id, obj in pairs(P().labs.rv.objects) do
            local fresh = true
            for _, pid in ipairs(placed) do if pid == id then fresh = false end end
            if fresh then placed[#placed + 1] = id end
        end
    end
    return r, e, Utils.count(P().labs.rv.objects) - before
end
ok(place('nzw_pot', -1.0, 0.0), 'pot 1 placed')
ok(not place('nzw_pot', -1.0, 0.1), 'pot on top of a pot is rejected')
ok(place('nzw_pot', -1.0, 0.6), 'pot 2 placed')
ok(place('nzw_pot', -1.0, 1.2), 'pot 3 placed')
local r4, e4 = place('nzw_pot', -1.0, 1.8)
ok(not r4 and e4 and e4:find('fits 3'), 'the RV only fits 3 growing stations')
ok(not place('nzw_packstation', 9.0, 0.0), 'out of bounds is rejected')
ok(place('nzw_packstation', 1.4, -1.5), 'packaging station placed')
local pot1, pack
for id, obj in pairs(P().labs.rv.objects) do
    if obj.type == 'pot' and obj.y == 0.0 then pot1 = id end
    if obj.type == 'packstation' then pack = id end
end
S.move(A, vec3(o.x - 1.0, o.y - 0.6, o.z + 1.0))

--[[ ─────────────────────────────── growing ─────────────────────────────── ]]
section('growing')
local okc = call('nzwl:st:claim', 'pot_seed', pot1, { item = 'nzw_seed_ogkush' })
ok(not okc, 'no seed before soil')
ok(claimFinish('pot_soil', pot1, { item = 'nzw_soil' }), 'soil poured')
ok(P().labs.rv.objects[pot1].st.soil == 1, 'pot has soil')
ok(claimFinish('pot_seed', pot1, { item = 'nzw_seed_ogkush' }), 'seed planted')
ok(P().labs.rv.objects[pot1].st.strain == 'ogkush', 'strain recorded')
local okw, ew = call('nzwl:st:claim', 'pot_water', pot1, {})
ok(not okw and ew:find('empty'), 'the watering can starts empty')
S.move(A, vec3(o.x + cfg.tap.x, o.y + cfg.tap.y, o.z + cfg.tap.z))
ok(claimFinish('tap_fill', nil, {}), 'filled the watering can at the tap')
ok(P().water == Config.WateringCan.capacity, 'can is full')
S.move(A, vec3(o.x - 1.0, o.y - 0.6, o.z + 1.0))
ok(claimFinish('pot_water', pot1, {}), 'watered')
ok(claimFinish('pot_fertilizer', pot1, { item = 'nzw_fertilizer' }), 'sprayed fertilizer')
ok(not claimFinish('pot_fertilizer', pot1, { item = 'nzw_fertilizer' }), 'fertilizer only once')
ok(not call('nzwl:st:claim', 'pot_harvest', pot1, {}), 'not ready yet')
-- grow: 13 min watered, rewater, 14 more
S.advance(13 * 60 * 1000)
ok(claimFinish('pot_water', pot1, {}), 'watered again')
S.advance(14 * 60 * 1000)
local g = Grow.view(P().labs.rv.objects[pot1].st, os.time(), 1.0)
ok(Grow.stage(g) == 4, 'fully grown after 26 watered minutes')
-- exploit: instant finish
call('nzwl:st:claim', 'pot_harvest', pot1, {})
S.dropped = nil
ok(not call('nzwl:st:finish'), 'an instant harvest is rejected')
-- the other player can't touch this pot
S.move(B, vec3(o.x - 1.0, o.y - 0.6, o.z + 1.0))
ok(not S.call(B, 'nzwl:st:claim', 'pot_harvest', pot1, {}), 'someone else can\'t harvest your plant')
local okh, extra = call('nzwl:st:claim', 'pot_harvest', pot1, {})
ok(okh and extra.count >= 6, 'harvest claim tells the client the bud count (' .. tostring(extra and extra.count) .. ')')
S.advance(5000)
local xpBefore = P().xp
ok(call('nzwl:st:finish'), 'harvested')
local buds = Inv.count(A, 'nzw_weed')
ok(buds == extra.count, 'one loose unit per bud')
ok(metaOf(A, 'nzw_weed').pid == 'ogkush' and metaOf(A, 'nzw_weed').quality == 2, 'Potting Soil + fertilizer = Standard OG Kush')
ok(P().xp > xpBefore, 'xp for the harvest')
ok(P().labs.rv.objects[pot1].st.soil == 0, 'soil used up')
ok(stage() == 'pack', 'stage: pack')

--[[ ─────────────────────────────── packaging ─────────────────────────────── ]]
section('packaging')
S.move(A, vec3(o.x + 1.4, o.y - 1.5, o.z + 1.0))
local pdata = call('nzwl:panel:open', pack)
ok(pdata and #pdata.stacks == 1 and pdata.stacks[1].n == buds, 'panel lists the loose weed')
ok(not call('nzwl:st:claim', 'pack', pack, { pid = 'ogkush', q = 2, kind = 'baggie', n = 7 }), 'more than fit on the station is rejected')
ok(not call('nzwl:st:claim', 'pack', pack, { pid = 'ogkush', q = 2, kind = 'jar', n = 1 }), 'jars are locked at level ' .. Profile.level(P()))
ok(call('nzwl:st:claim', 'pack', pack, { pid = 'ogkush', q = 2, kind = 'baggie', n = 4 }), 'pack claim for 4 baggies')
S.advance(3000)
ok(not call('nzwl:st:finish', { done = 4 }), '4 baggies in 3 seconds is too fast')
ok(call('nzwl:st:claim', 'pack', pack, { pid = 'ogkush', q = 2, kind = 'baggie', n = 4 }), 'pack again')
S.advance(9000)
local okp, done = call('nzwl:st:finish', { done = 3 })
ok(okp and done == 3, 'only the 3 that went in the hatch are paid')
ok(Inv.count(A, 'nzw_baggie') == 3 and Inv.count(A, 'nzw_weed') == buds - 3 and Inv.count(A, 'nzw_baggie_empty') == 17, 'inventory adds up')
ok(metaOf(A, 'nzw_baggie').units == 1 and metaOf(A, 'nzw_baggie').pid == 'ogkush', 'baggie metadata')
ok(stage() == 'sell', 'next: sell it')
ok(call('nzwl:st:claim', 'pack', pack, { pid = 'ogkush', q = 2, kind = 'baggie', n = 1 }), 'claim')
S.advance(4000)
ok(not call('nzwl:st:finish', { done = 0 }), 'nothing packed = nothing paid')

--[[ ─────────────────────────────── levels + more gear ─────────────────────────────── ]]
section('levels, lights, tent')
ok(not place('nzw_growtent', 1.2, 1.4), 'can\'t place a tent without having one')
S.commands[Config.Admin.command](0, { 'level', tostring(A), '12' })
ok(Profile.level(P()) == 12, 'admin set level 12')
Inv.add(A, 'nzw_rack', 1)
Inv.add(A, 'nzw_light_led', 1)
Inv.add(A, 'nzw_dryrack', 1)
Inv.add(A, 'nzw_mixstation', 1)
Inv.add(A, 'nzw_brickpress', 1)
Inv.add(A, 'nzw_ing_banana', 10)
S.move(A, vec3(o.x, o.y, o.z + 1.0))
ok(place('nzw_rack', -1.0, 0.6), 'suspension rack over the pots (racks may overlap)')
local rack
for id, obj in pairs(P().labs.rv.objects) do if obj.type == 'rack' then rack = id end end
S.move(A, vec3(o.x - 1.0, o.y + 0.6, o.z + 1.0))
ok(S.call(A, 'nzwl:lab:hang', rack, 'nzw_light_led'), 'LED hung on the rack')
local pot2
for id, obj in pairs(P().labs.rv.objects) do if obj.type == 'pot' and obj.y == 0.6 then pot2 = id end end
ok(math.abs(Labs.boostFor(P().labs.rv.objects, P().labs.rv.objects[pot2]) - 1.25 * 1.15) < 1e-6, 'pot under the LED grows 15% faster than halogen')
ok(Labs.boostFor(P().labs.rv.objects, { type = 'pot', x = 2.0, y = -3.0 }) == 1.0, 'a pot outside the rack gets no boost')
ok(S.call(A, 'nzwl:lab:pickup', pot2) == true, 'an empty pot can be picked up')
Inv.add(A, 'nzw_pot', 1)
S.move(A, vec3(o.x, o.y, o.z + 1.0))
ok(place('nzw_pot', -1.0, 0.6), 'pot back under the light')

--[[ ─────────────────────────────── drying ─────────────────────────────── ]]
section('drying rack')
ok(place('nzw_dryrack', 1.6, 2.6), 'drying rack placed')
local dry
for id, obj in pairs(P().labs.rv.objects) do if obj.type == 'dryrack' then dry = id end end
S.move(A, vec3(o.x + 1.6, o.y + 2.6, o.z + 1.0))
local before = Inv.count(A, 'nzw_weed')
ok(claimFinish('dry_hang', dry, { pid = 'ogkush', q = 2, n = 2 }, 3), 'hung 2 buds')
ok(Inv.count(A, 'nzw_weed') == before - 2, 'buds taken')
ok(not call('nzwl:dry:collect', dry), 'nothing is dry yet')
S.advance(Config.Processing.dry.minutes * 60 * 1000)
local okd, nd = call('nzwl:dry:collect', dry)
ok(okd and nd == 2, 'collected the dry buds')
local q3 = 0
for _, s in ipairs(Inv.slots(A, 'nzw_weed')) do if s.meta.quality == 3 then q3 = q3 + s.count end end
ok(q3 == 2, 'dried buds are a quality higher (Premium)')

--[[ ─────────────────────────────── mixing ─────────────────────────────── ]]
section('mixing')
S.move(A, vec3(o.x, o.y, o.z + 1.0))
ok(place('nzw_mixstation', 1.5, 0.4), 'mixing station placed')
local mixer
for id, obj in pairs(P().labs.rv.objects) do if obj.type == 'mixstation' then mixer = id end end
S.move(A, vec3(o.x + 1.5, o.y + 0.4, o.z + 1.0))
local okm, res = claimFinish('mix', mixer, { pid = 'ogkush', q = 2, ingredient = 'nzw_ing_banana', n = 2 }, 9)
ok(okm and res and res.product and res.first, 'mixed a new product: ' .. tostring(res and res.product and res.product.name))
ok(Inv.count(A, 'nzw_ing_banana') == 8, 'one ingredient per unit')
local p = res and Products.get(res.product.id)
ok(p and Utils.contains(p.effects, 'sneaky') and Utils.contains(p.effects, 'gingeritis'), 'Banana turns Calming into Sneaky and adds Gingeritis')
local okm2, res2 = claimFinish('mix', mixer, { pid = 'ogkush', q = 2, ingredient = 'nzw_ing_banana', n = 1 }, 9)
ok(okm2 and res2.product.id == res.product.id and not res2.first, 'same recipe = same product')

--[[ ─────────────────────────────── brick press ─────────────────────────────── ]]
section('brick press')
S.move(A, vec3(o.x, o.y, o.z + 1.0))
ok(place('nzw_brickpress', -1.6, -2.4), 'brick press placed')
local press
for id, obj in pairs(P().labs.rv.objects) do if obj.type == 'brickpress' then press = id end end
S.move(A, vec3(o.x - 1.6, o.y - 2.4, o.z + 1.0))
ok(not call('nzwl:st:claim', 'press', press, { pid = 'ogkush', q = 2 }), 'needs ' .. Config.Product.unitsPerBrick .. ' units')
Inv.add(A, 'nzw_weed', 30, Products.meta('ogkush', 2))
local w0 = Inv.count(A, 'nzw_weed')
ok(claimFinish('press', press, { pid = 'ogkush', q = 2 }, 7), 'pressed a brick')
ok(Inv.count(A, 'nzw_brick') == 1 and Inv.count(A, 'nzw_weed') == w0 - Config.Product.unitsPerBrick, 'brick for 20 units')
ok(metaOf(A, 'nzw_brick').units == Config.Product.unitsPerBrick, 'brick metadata')

--[[ ─────────────────────────────── warehouses ─────────────────────────────── ]]
section('warehouses')
call('nzwl:lab:exit')
ok(S.buckets[A] == 0, 'back in the main bucket after leaving')
money[A].bank = 100000
local okw1, ew1 = call('nzwl:lab:buy', 'warehouse', 1, 'bank')
ok(not okw1 and ew1:find('level 15'), 'weed warehouse needs level 15')
S.advance(4000)
ok(call('nzwl:lab:buy', 'small', 2, 'bank'), 'bought the small warehouse')
ok(money[A].bank == 100000 - Config.Labs.small.price, 'paid for it')
ok(not call('nzwl:lab:enter', 'small'), 'must be at the door')
S.move(A, Config.Labs.small.entrances[2].door)
local okS = call('nzwl:lab:enter', 'small')
ok(okS and Labs.inside(A).lab == 'small', 'inside the small warehouse')
local sc = Config.Labs.small.interior
S.move(A, vec3(sc.origin.x, sc.origin.y, sc.origin.z + 1.0))
Inv.add(A, 'nzw_pot', 5)
for i = 1, 5 do place('nzw_pot', -4.0 + i * 0.6, 0.0) end
local grow = 0
for _, obj in pairs(P().labs.small.objects) do if obj.type == 'pot' then grow = grow + 1 end end
ok(grow == 5, 'the warehouse fits more than the RV')
ok(Utils.count(P().labs.rv.objects) > 0, 'the RV keeps its own equipment')
S.move(B, vec3(sc.origin.x, sc.origin.y, sc.origin.z + 1.0))
ok(not S.call(B, 'nzwl:lab:place', 'nzw_pot', 0.0, 2.0, 0.0, 0.0), 'someone who isn\'t inside their lab can\'t place')

--[[ ─────────────────────────────── selling ─────────────────────────────── ]]
section('selling')
local C = Config.Selling.corner
call('nzwl:lab:exit')
local street = vec3(200.0, -900.0, 30.0)
S.move(A, street)
local guy = S.npc(vec3(street.x + 1.0, street.y, street.z))
local far = S.npc(vec3(street.x + 30.0, street.y, street.z))
ok(not call('nzwl:sell:offer', far), 'can\'t sell to someone across the street')
S.advance(C.cooldown * 1000)
ok(not call('nzwl:sell:offer', NetworkGetNetworkIdFromEntity(GetPlayerPed(B))), 'can\'t sell to another player')
S.advance(C.cooldown * 1000)
local acc = C.accept
C.accept = { base = 1, perQuality = 0, min = 1, max = 1 }
local cash0, bags0 = money[A].cash, Inv.count(A, 'nzw_baggie') + Inv.count(A, 'nzw_jar')
local oks, sale = call('nzwl:sell:offer', guy)
ok(oks and sale.accepted and sale.price > 0, 'sold to a local for $' .. tostring(sale and sale.price))
ok(money[A].cash == cash0 + sale.price, 'paid in cash')
ok(Inv.count(A, 'nzw_baggie') + Inv.count(A, 'nzw_jar') == bags0 - sale.n, 'the product is gone')
ok(stage() == 'done', 'story done after the first sale')
local again, why = call('nzwl:sell:offer', guy)
ok(not again, 'no second offer straight away')
S.advance(C.cooldown * 1000)
again, why = call('nzwl:sell:offer', guy)
ok(not again and why and why:find('already'), 'the same person won\'t buy again for a while')
C.accept = { base = 0, perQuality = 0, min = 0, max = 0 }
S.advance(C.cooldown * 1000)
local okr, refused = call('nzwl:sell:offer', S.npc(vec3(street.x, street.y + 1.0, street.z)))
ok(okr and refused.accepted == false, 'people can say no')
C.accept = acc

section('brick buyer')
local BB = Config.Selling.bulk
ok(not call('nzwl:bulk:open'), 'the buyer is only at his spot')
S.move(A, BB.ped)
local bulk = call('nzwl:bulk:open')
ok(bulk and #bulk.bricks == 1 and bulk.left == BB.perDay, 'he sees the brick')
local cash1 = money[A].cash
local okb3, resb = call('nzwl:bulk:sell', bulk.bricks[1].slot, 1)
ok(okb3 and resb.total == bulk.bricks[1].price and money[A].cash == cash1 + resb.total, 'brick sold for $' .. tostring(resb and resb.total))
ok(Inv.count(A, 'nzw_brick') == 0 and resb.panel.left == BB.perDay - 1, 'brick gone, daily limit counts down')

--[[ ─────────────────────────────── save ─────────────────────────────── ]]
section('saving')
Profile.save(A, true)
ok(S.db[Profile.identifier(A)] ~= nil, 'profile written to the database')
TriggerEvent('nzwl:server:unload', A)
Profile.unload(A)
ok(Profile.get(A) == nil, 'unloaded')

print(('\n%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
