--[[
    NAYZEEE AMBULANCE - Blood services (server): bags, blood bank, Type & screen

    Public API (ARCHITECTURE §9, callable by every module):
      NZA.Blood.CreateBag(meta) → metadata          meta = { type, ml?, donor?, donorId?, created?, expires?,
                                                            bank? (stock key → unit goes into that bank) }
                                                    → { serial = 'BB-482913', type, ml, donor, created, expires,
                                                        product, label, description }
      NZA.Blood.TakeBag(src, sel) → metadata | nil, reasonText
                                                    sel = slot number | serial string |
                                                          { serial?, slot?, type?, recipient? (pid / patient) }
                                                    removes the item (the unit is logged as used)
      NZA.Blood.Compatible(recipient, donor) → bool recipient = blood type | pid | Patient ; NZA.Const.CanReceive
      NZA.Blood.GiveBag(src, meta) → bool           NZA.Blood.BagsOf(src, recipient?) → { bag view }
      NZA.Blood.Stock(bankKey) → { unit }           NZA.Blood.BankKey(point) → key
      NZA.Blood.AddToBank(bankKey, meta, actor?)    NZA.Blood.Log(bankKey, action, unit, actor)
      NZA.Blood.Bill(src, p, kind, count?, price?)          NZA.Blood.IsTyped(p) → bool
      NZA.Blood.ItemName(key) → inventory name      NZA.Blood.Cfg(section) → Config.Blood[section]

    Data (oxmysql, created on start):
      nza_blood (serial PK, type, ml, donor, donor_id, created, expires, used, bank, updated)
        used: 0 = in a bank, 1 = in circulation (an item), 2 = transfused, 3 = discarded
      nza_blood_donors (identifier PK, last, count, weak_until)
      nza_blood_log (id PK, bank, action, serial, type, actor, at)

    Instant treatment (NZA.Treat): 'blood:type' (Type & screen) → patient.meta.bloodTyped = true
    Callbacks: nza:blood:bank:open (pointId) · nza:blood:bank:deposit (pointId, serial)
               nza:blood:bank:withdraw (pointId, serial) · nza:blood:bank:fill (pointId, type)
               nza:blood:bank:discard (pointId, serial) · nza:blood:bags (recipient?) → bags you carry
    Usable items: Config.Items.blood_bag → S→C 'nza:blood:label' (bag view)
                  Config.Items.empty_blood_bag → hint toast
    Exports: GetBloodStock(bankKey), CreateBloodBag(meta), BloodCompatible(recipient, donor)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local Core = NZA.Core
local U = NZA.Util

local DAY = 86400

-- ════════════════════════════════════════════════════════════════════════
-- CONFIG / LOCALE / ITEMS
-- ════════════════════════════════════════════════════════════════════════

function B.Cfg(section)
    local c = Config.Blood or {}
    if section then return c[section] or {} end
    return c
end
local cfg = B.Cfg

local function L(key, ...) return NZA.L('blood.' .. key, ...) end
B.L = L

local function fail(key, ...)
    return false, { err = key, msg = L('err_' .. key, ...) }
end
B.Fail = fail

function B.ItemName(key)
    if not key then return nil end
    return (Config.Items and Config.Items[key]) or nil
end

-- { KEY = n } → { [inventory name] = n }
function B.Items(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = B.ItemName(key)
        if name and (tonumber(n) or 0) > 0 then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

local function bagItem() return B.ItemName(cfg('Bags').item or 'blood_bag') end
local function emptyItem() return B.ItemName(cfg('Bags').empty or 'empty_blood_bag') end

local function count(src, name)
    if not name then return 0 end
    return tonumber(Core.B('Inv.Count', src, name)) or 0
end
B.Count = count

local function validType(t)
    if type(t) ~= 'string' then return nil end
    for _, bt in ipairs(NZA.Const.BloodTypes) do
        if bt == t then return t end
    end
    return nil
end
B.ValidType = validType

-- ════════════════════════════════════════════════════════════════════════
-- DATABASE
-- ════════════════════════════════════════════════════════════════════════

local dbReady = false
local function hasDB() return MySQL ~= nil and MySQL.query ~= nil end

local function q(sql, params)
    if not hasDB() then return nil end
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        NZA.Warn('blood: query failed: ' .. tostring(res))
        return nil
    end
    return res
end

local function exec(sql, params)
    if not hasDB() then return end
    local ok, err = pcall(MySQL.query, sql, params or {})
    if not ok then NZA.Warn('blood: query failed: ' .. tostring(err)) end
end
B.Exec = exec
B.Query = q

local stock = {}        -- [bankKey] = { [serial] = unit }
local logs = {}         -- [bankKey] = { newest first }
local known = {}        -- [serial] = true (every serial ever issued)

local function unitView(row)
    return {
        serial = row.serial, type = row.type, ml = tonumber(row.ml) or 0, donor = row.donor,
        created = tonumber(row.created) or 0, expires = tonumber(row.expires) or 0,
    }
end

local function loadAll()
    q([[CREATE TABLE IF NOT EXISTS `nza_blood` (
        `serial` VARCHAR(16) NOT NULL,
        `type` VARCHAR(4) NOT NULL,
        `ml` INT NOT NULL DEFAULT 450,
        `donor` VARCHAR(80) NULL,
        `donor_id` VARCHAR(80) NULL,
        `created` INT NOT NULL DEFAULT 0,
        `expires` INT NOT NULL DEFAULT 0,
        `used` TINYINT NOT NULL DEFAULT 0,
        `bank` VARCHAR(64) NULL,
        `updated` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`serial`),
        KEY `bank_used` (`bank`, `used`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `nza_blood_donors` (
        `identifier` VARCHAR(80) NOT NULL,
        `last` INT NOT NULL DEFAULT 0,
        `count` INT NOT NULL DEFAULT 0,
        `weak_until` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`)
    )]])
    q([[CREATE TABLE IF NOT EXISTS `nza_blood_log` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `bank` VARCHAR(64) NULL,
        `action` VARCHAR(16) NOT NULL,
        `serial` VARCHAR(16) NULL,
        `type` VARCHAR(4) NULL,
        `actor` VARCHAR(80) NULL,
        `at` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `bank_at` (`bank`, `at`)
    )]])
    local rows = q('SELECT `serial`, `type`, `ml`, `donor`, `created`, `expires`, `used`, `bank` FROM `nza_blood`') or {}
    for _, r in ipairs(rows) do
        known[r.serial] = true
        if tonumber(r.used) == 0 and r.bank then
            stock[r.bank] = stock[r.bank] or {}
            stock[r.bank][r.serial] = unitView(r)
        end
    end
    dbReady = true
    NZA.Debug(('blood: %d units known'):format(U.tableCount(known)))
end

-- ════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY
-- ════════════════════════════════════════════════════════════════════════

local function recipientType(recipient)
    if type(recipient) == 'string' then
        local t = validType(recipient)
        if t then return t end
    end
    local p = recipient and NZA.Patients.Resolve(recipient) or nil
    return p and p.bloodType or nil
end

function B.Compatible(recipient, donor)
    local r = recipientType(recipient)
    donor = validType(donor)
    if not r or not donor then return false end
    local can = NZA.Const.CanReceive[r]
    return can ~= nil and can[donor] == true
end

-- the medic only knows the group after Type & screen (or after a donation for the donor)
function B.IsTyped(p)
    return type(p) == 'table' and type(p.meta) == 'table' and (p.meta.bloodTyped == true or p.meta.typed == true)
end

-- ════════════════════════════════════════════════════════════════════════
-- BAGS
-- ════════════════════════════════════════════════════════════════════════

local function newSerial()
    local prefix = cfg('Bags').serialPrefix or 'BB-'
    for _ = 1, 50 do
        local s = ('%s%06d'):format(prefix, math.random(0, 999999))
        if not known[s] then
            known[s] = true
            return s
        end
    end
    local s = ('%s%d'):format(prefix, os.time() % 1000000 + math.random(1000000, 8999999))
    known[s] = true
    return s
end

local function dateText(t)
    return os.date('%Y-%m-%d', math.floor(tonumber(t) or os.time()))
end

local function labelOf(meta)
    local base = Core.B('Inv.Label', bagItem()) or L('bag')
    return ('%s %s'):format(base, meta.type or '?')
end

local function describe(meta)
    return L('bag_desc', meta.type or '?', math.floor(meta.ml or 0), meta.serial or '?', dateText(meta.expires))
end

-- metadata as stored on the inventory item
local function itemMeta(u)
    local m = {
        serial = u.serial, type = u.type, ml = math.floor(tonumber(u.ml) or 0), donor = u.donor,
        created = u.created, expires = u.expires, product = cfg('Bags').product,
    }
    m.label = labelOf(m)
    m.description = describe(m)
    return m
end
B.ItemMeta = itemMeta

local function writeUnit(u, used, bank, donorId)
    exec('INSERT INTO `nza_blood` (`serial`, `type`, `ml`, `donor`, `donor_id`, `created`, `expires`, `used`, `bank`, `updated`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        .. 'ON DUPLICATE KEY UPDATE `used` = VALUES(`used`), `bank` = VALUES(`bank`), `ml` = VALUES(`ml`), `updated` = VALUES(`updated`)',
        { u.serial, u.type, math.floor(u.ml or 0), u.donor, donorId, u.created, u.expires, used, bank, os.time() })
end

local function setUsed(serial, used, bank)
    if type(serial) ~= 'string' then return end
    exec('UPDATE `nza_blood` SET `used` = ?, `bank` = ?, `updated` = ? WHERE `serial` = ?', { used, bank, os.time(), serial })
end
B.SetUsed = setUsed

function B.CreateBag(meta)
    meta = type(meta) == 'table' and meta or {}
    local bt = validType(meta.type) or U.RandomBloodType()
    local now = os.time()
    local bags = cfg('Bags')
    local u = {
        serial = newSerial(),
        type = bt,
        ml = math.floor(U.clamp(tonumber(meta.ml) or bags.ml or 450, 1, bags.bagSize or 500)),
        donor = type(meta.donor) == 'string' and meta.donor:sub(1, 60) or L('donor_anon'),
        created = tonumber(meta.created) or now,
        expires = tonumber(meta.expires) or (now + (tonumber(bags.shelfDays) or 35) * DAY),
    }
    if meta.bank then
        stock[meta.bank] = stock[meta.bank] or {}
        stock[meta.bank][u.serial] = u
        writeUnit(u, 0, meta.bank, meta.donorId)
    else
        writeUnit(u, 1, nil, meta.donorId)
    end
    return itemMeta(u)
end

function B.GiveBag(src, meta)
    local name = bagItem()
    if not name or type(meta) ~= 'table' then return false end
    if Core.Has('Inv.CanCarry') and Core.B('Inv.CanCarry', src, name, 1) == false then return false end
    return Core.B('Inv.AddItem', src, name, 1, meta) == true
end

local function isExpired(m, now)
    local e = tonumber(m and m.expires)
    return e ~= nil and e > 0 and e < (now or os.time())
end
B.IsExpired = isExpired

-- every labelled blood bag the player carries
function B.BagsOf(src, recipient)
    local out = {}
    local name = bagItem()
    if not name or not Core.Has('Inv.Search') then return out end
    local rt = recipient and recipientType(recipient) or nil
    local now = os.time()
    local warn = (tonumber(cfg('Bags').warnDays) or 3) * DAY
    for _, it in ipairs(Core.B('Inv.Search', src, name) or {}) do
        local m = type(it.metadata) == 'table' and it.metadata or {}
        local bt = validType(m.type or m.bloodType)
        if bt then
            local exp = tonumber(m.expires) or 0
            out[#out + 1] = {
                slot = it.slot, serial = m.serial, type = bt, ml = tonumber(m.ml) or cfg('Bags').ml or 450,
                donor = m.donor, created = tonumber(m.created) or 0, expires = exp,
                expired = isExpired(m, now), soon = exp > 0 and exp - now < warn,
                compatible = rt and (NZA.Const.CanReceive[rt] and NZA.Const.CanReceive[rt][bt] == true) or nil,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.expired ~= b.expired then return not a.expired end
        if (a.compatible == true) ~= (b.compatible == true) then return a.compatible == true end
        if a.type ~= b.type then return a.type < b.type end
        return (a.expires or 0) < (b.expires or 0)
    end)
    return out
end

-- find one carried bag by slot / serial / type
local function findBag(src, sel)
    local name = bagItem()
    if not name or not Core.Has('Inv.Search') then return nil end
    local slot, serial, want
    if type(sel) == 'number' then slot = sel
    elseif type(sel) == 'string' then serial = sel
    elseif type(sel) == 'table' then
        slot = tonumber(sel.slot)
        serial = type(sel.serial) == 'string' and sel.serial or nil
        want = validType(sel.type)
    end
    local now = os.time()
    local best
    for _, it in ipairs(Core.B('Inv.Search', src, name) or {}) do
        local m = type(it.metadata) == 'table' and it.metadata or {}
        local bt = validType(m.type or m.bloodType)
        if bt then
            if serial then
                if m.serial == serial then return it, m end
            elseif slot then
                if tonumber(it.slot) == slot then return it, m end
            elseif not want or want == bt then
                -- oldest valid unit of that type first
                if not isExpired(m, now) and (not best or (tonumber(m.expires) or 0) < (tonumber(best[2].expires) or 0)) then
                    best = { it, m }
                end
            end
        end
    end
    if best then return best[1], best[2] end
    return nil
end

function B.TakeBag(src, sel, opts)
    opts = opts or {}
    local name = bagItem()
    if not name then return nil, L('err_no_item_cfg') end
    local it, m = findBag(src, sel)
    if not it then return nil, L('err_no_bag') end
    if isExpired(m) and cfg('Bags').useExpired ~= true and not opts.allowExpired then
        return nil, L('err_expired', m.serial or '?')
    end
    local match = m.serial and { serial = m.serial } or nil
    local removed = Core.B('Inv.RemoveItem', src, name, 1, match, it.slot)
    if not removed then
        removed = Core.B('Inv.RemoveItem', src, name, 1, nil, it.slot)
    end
    if not removed then return nil, L('err_no_bag') end
    local meta = U.deepcopy(m)
    meta.type = validType(meta.type or meta.bloodType)
    meta.ml = tonumber(meta.ml) or cfg('Bags').ml or 450
    setUsed(meta.serial, opts.status or 2, nil)
    return meta
end

-- ════════════════════════════════════════════════════════════════════════
-- BANK
-- ════════════════════════════════════════════════════════════════════════

function B.BankKey(point)
    if cfg('Bank').shared == true then return 'shared' end
    if type(point) == 'table' and point.hospital ~= nil then return tostring(point.hospital) end
    return 'shared'
end

function B.Stock(key)
    local out = {}
    for _, u in pairs(stock[key] or {}) do out[#out + 1] = u end
    table.sort(out, function(a, b)
        if a.type ~= b.type then return a.type < b.type end
        return (a.expires or 0) < (b.expires or 0)
    end)
    return out
end

local function stockCount(key)
    local n = 0
    for _ in pairs(stock[key] or {}) do n = n + 1 end
    return n
end

function B.Log(key, action, unit, actor)
    local e = { action = action, serial = unit and unit.serial, type = unit and unit.type, actor = actor, at = os.time() }
    local list = logs[key]
    if list then
        table.insert(list, 1, e)
        local max = tonumber(cfg('Bank').logSize) or 30
        while #list > max do table.remove(list) end
    end
    exec('INSERT INTO `nza_blood_log` (`bank`, `action`, `serial`, `type`, `actor`, `at`) VALUES (?, ?, ?, ?, ?, ?)',
        { key, action, e.serial, e.type, actor, e.at })
end

local function logOf(key)
    if not logs[key] then
        local rows = q('SELECT `action`, `serial`, `type`, `actor`, `at` FROM `nza_blood_log` WHERE `bank` = ? ORDER BY `id` DESC LIMIT ?',
            { key, tonumber(cfg('Bank').logSize) or 30 }) or {}
        local list = {}
        for _, r in ipairs(rows) do
            list[#list + 1] = { action = r.action, serial = r.serial, type = r.type, actor = r.actor, at = tonumber(r.at) or 0 }
        end
        logs[key] = list
    end
    return logs[key]
end

-- puts an existing unit (label metadata) into a bank
function B.AddToBank(key, meta, actor)
    if type(meta) ~= 'table' or not validType(meta.type) then return false end
    local u = {
        serial = type(meta.serial) == 'string' and meta.serial or newSerial(), type = meta.type,
        ml = math.floor(tonumber(meta.ml) or cfg('Bags').ml or 450), donor = meta.donor or L('donor_anon'),
        created = tonumber(meta.created) or os.time(),
        expires = tonumber(meta.expires) or (os.time() + (tonumber(cfg('Bags').shelfDays) or 35) * DAY),
    }
    known[u.serial] = true
    stock[key] = stock[key] or {}
    stock[key][u.serial] = u
    writeUnit(u, 0, key, nil)
    B.Log(key, 'in', u, actor)
    return true, u
end

local function actorName(src)
    return Core.Name(src) or ('#' .. tostring(src))
end

local function bankPoint(src, pointId)
    if not (NZA.Hospitals and NZA.Hospitals.Point) then return nil, 'no_point' end
    local pt = NZA.Hospitals.Point(pointId)
    if not pt or pt.type ~= 'bloodbank' then return nil, 'no_point' end
    local c = pt.coords
    local pos = c and vector3(c.x, c.y, c.z) or nil
    local me = Core.SrcCoords(src)
    if not pos or not me or #(me - pos) > (tonumber(cfg('Bank').distance) or 2.5) + 2.0 then return nil, 'too_far' end
    if not NZA.Staff.Can(src, cfg('Bank').perm or 'blood') then return nil, 'no_perm' end
    local p = NZA.Patients.GetBySource(src)
    if p and p.state ~= 'alive' then return nil, 'down' end
    return pt
end

local withdrawals = {}   -- [identifier] = { times }

local function canWithdraw(src)
    local id = Core.Identifier(src) or tostring(src)
    local window = (tonumber(cfg('Bank').withdrawWindow) or 15) * 60
    local max = tonumber(cfg('Bank').maxWithdraw) or 6
    local now = os.time()
    local list = withdrawals[id] or {}
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < window then kept[#kept + 1] = t end
    end
    withdrawals[id] = kept
    if max > 0 and #kept >= max then return false end
    return true, function() kept[#kept + 1] = now end
end

local function bankData(src, pt)
    local key = B.BankKey(pt)
    local now = os.time()
    local warn = (tonumber(cfg('Bags').warnDays) or 3) * DAY
    local units = {}
    local byType = {}
    for _, bt in ipairs(NZA.Const.BloodTypes) do byType[bt] = { type = bt, units = 0, ml = 0 } end
    local soon = 0
    for _, u in ipairs(B.Stock(key)) do
        local expired = isExpired(u, now)
        local s = not expired and u.expires - now < warn
        if s then soon = soon + 1 end
        units[#units + 1] = {
            serial = u.serial, type = u.type, ml = u.ml, donor = u.donor, created = u.created,
            expires = u.expires, expired = expired, soon = s,
        }
        local t = byType[u.type]
        if t and not expired then
            t.units = t.units + 1
            t.ml = t.ml + (u.ml or 0)
        end
    end
    local types = {}
    for _, bt in ipairs(NZA.Const.BloodTypes) do types[#types + 1] = byType[bt] end
    local dept = pt.hospital and NZA.Hospitals.Get and NZA.Hospitals.Get(pt.hospital) or nil
    return {
        point = pt.id, bank = key, title = (dept and dept.label) or L('bank_title'),
        now = now, warnDays = tonumber(cfg('Bags').warnDays) or 3,
        units = units, types = types, soon = soon,
        mine = B.BagsOf(src), empty = count(src, emptyItem()),
        needEmpty = cfg('Bank').needEmptyBag ~= false, maxStock = tonumber(cfg('Bank').maxStock) or 60,
        log = logOf(key),
    }
end
B.BankData = bankData

local function errResp(code)
    return { ok = false, err = code, msg = L('err_' .. code) }
end

lib.callback.register('nza:blood:bank:open', function(src, pointId)
    if not Core.Rate('blood:bank', src, 6, 4000) then return errResp('rate') end
    local pt, err = bankPoint(src, pointId)
    if not pt then return errResp(err) end
    return { ok = true, data = bankData(src, pt) }
end)

lib.callback.register('nza:blood:bank:deposit', function(src, pointId, serial)
    if not Core.Rate('blood:bank', src, 6, 4000) then return errResp('rate') end
    local pt, err = bankPoint(src, pointId)
    if not pt then return errResp(err) end
    if type(serial) ~= 'string' then return errResp('no_bag') end
    local key = B.BankKey(pt)
    if stockCount(key) >= (tonumber(cfg('Bank').maxStock) or 60) then return errResp('bank_full') end
    local meta, why = B.TakeBag(src, serial, { status = 0, allowExpired = true })
    if not meta then return { ok = false, err = 'no_bag', msg = why } end
    if isExpired(meta) then
        setUsed(meta.serial, 3, key)
        B.Log(key, 'discard', meta, actorName(src))
        return { ok = true, msg = L('ok_discarded', meta.serial or '?'), data = bankData(src, pt) }
    end
    B.AddToBank(key, meta, actorName(src))
    return { ok = true, msg = L('ok_deposit', meta.type, meta.serial or '?'), data = bankData(src, pt) }
end)

local function takeFromBank(src, pt, pick)
    local key = B.BankKey(pt)
    local u = pick(B.Stock(key))
    if not u then return nil, 'no_unit' end
    stock[key][u.serial] = nil
    return u, key
end

lib.callback.register('nza:blood:bank:withdraw', function(src, pointId, serial)
    if not Core.Rate('blood:bank', src, 6, 4000) then return errResp('rate') end
    local pt, err = bankPoint(src, pointId)
    if not pt then return errResp(err) end
    if cfg('Bank').needEmptyBag ~= false then return errResp('need_fill') end
    if type(serial) ~= 'string' then return errResp('no_unit') end
    local okW, mark = canWithdraw(src)
    if not okW then return errResp('limit') end
    local name = bagItem()
    if Core.Has('Inv.CanCarry') and Core.B('Inv.CanCarry', src, name, 1) == false then return errResp('cant_carry') end
    local now = os.time()
    local u, key = takeFromBank(src, pt, function(list)
        for _, x in ipairs(list) do
            if x.serial == serial and not isExpired(x, now) then return x end
        end
    end)
    if not u then return errResp('no_unit') end
    if not B.GiveBag(src, itemMeta(u)) then
        stock[key][u.serial] = u
        return errResp('cant_carry')
    end
    mark()
    setUsed(u.serial, 1, nil)
    B.Log(key, 'out', u, actorName(src))
    return { ok = true, msg = L('ok_withdraw', u.type, u.serial), data = bankData(src, pt) }
end)

lib.callback.register('nza:blood:bank:fill', function(src, pointId, btype, serial)
    if not Core.Rate('blood:bank', src, 6, 4000) then return errResp('rate') end
    local pt, err = bankPoint(src, pointId)
    if not pt then return errResp(err) end
    btype = validType(btype)
    if not btype then return errResp('no_unit') end
    local okW, mark = canWithdraw(src)
    if not okW then return errResp('limit') end
    local needEmpty = cfg('Bank').needEmptyBag ~= false
    local empty = emptyItem()
    if needEmpty and count(src, empty) < 1 then return errResp('no_empty') end
    local name = bagItem()
    if Core.Has('Inv.CanCarry') and Core.B('Inv.CanCarry', src, name, 1) == false then return errResp('cant_carry') end
    local now = os.time()
    local u, key = takeFromBank(src, pt, function(list)
        if type(serial) == 'string' then
            for _, x in ipairs(list) do
                if x.serial == serial and x.type == btype and not isExpired(x, now) then return x end
            end
        end
        for _, x in ipairs(list) do      -- sorted: soonest expiry first (first in, first out)
            if x.type == btype and not isExpired(x, now) then return x end
        end
    end)
    if not u then return errResp('no_unit') end
    if needEmpty and not Core.B('Inv.RemoveItem', src, empty, 1) then
        stock[key][u.serial] = u
        return errResp('no_empty')
    end
    if not B.GiveBag(src, itemMeta(u)) then
        stock[key][u.serial] = u
        if needEmpty then Core.B('Inv.AddItem', src, empty, 1) end
        return errResp('cant_carry')
    end
    mark()
    setUsed(u.serial, 1, nil)
    B.Log(key, 'fill', u, actorName(src))
    return { ok = true, msg = L('ok_fill', u.type, u.serial), data = bankData(src, pt) }
end)

lib.callback.register('nza:blood:bank:discard', function(src, pointId, serial)
    if not Core.Rate('blood:bank', src, 6, 4000) then return errResp('rate') end
    local pt, err = bankPoint(src, pointId)
    if not pt then return errResp(err) end
    local key = B.BankKey(pt)
    local u = stock[key] and type(serial) == 'string' and stock[key][serial] or nil
    if not u then return errResp('no_unit') end
    if not isExpired(u) then return errResp('not_expired') end
    stock[key][serial] = nil
    setUsed(serial, 3, key)
    B.Log(key, 'discard', u, actorName(src))
    return { ok = true, msg = L('ok_discarded', serial), data = bankData(src, pt) }
end)

-- bags the medic carries (+ compatibility against a patient when given)
lib.callback.register('nza:blood:bags', function(src, recipient)
    if not Core.Rate('blood:bags', src, 6, 3000) then return nil end
    local p = recipient and NZA.Patients.Resolve(recipient) or nil
    if p and Core.DistanceTo(src, p) > 8.0 then p = nil end
    -- only reveal compatibility when the medic could know the group
    return B.BagsOf(src, (p and B.IsTyped(p)) and p or nil)
end)

-- ════════════════════════════════════════════════════════════════════════
-- BILLING
-- ════════════════════════════════════════════════════════════════════════

function B.Bill(src, p, kind, n, price)
    local per = tonumber(price) or tonumber(cfg('Billing')[kind]) or 0
    local amount = math.floor(per * (n or 1))
    if amount <= 0 or not p or p.kind ~= 'player' then return end
    if not (NZA.Billing and type(NZA.Billing.Charge) == 'function') then return end
    local rec = src and src > 0 and NZA.Staff.Get(src) or nil
    if src and src > 0 and not (rec and rec.medic and rec.onDuty) then return end
    local target = p.src or p.identifier
    if not target then return end
    local ok, err = pcall(NZA.Billing.Charge, target, amount, L('bill_' .. kind), { medic = src, kind = 'blood_' .. kind })
    if not ok then NZA.Warn('blood: billing failed: ' .. tostring(err)) end
end

-- ════════════════════════════════════════════════════════════════════════
-- TYPE & SCREEN
-- ════════════════════════════════════════════════════════════════════════

local ts = cfg('TypeScreen')
NZA.Treat.Register('blood:type', {
    perm = ts.perm or 'blood', maxDist = (tonumber(ts.distance) or 2.2) + 0.8, cooldown = 1500,
    states = { alive = true, wounded = true, arrest = true, dead = true },
    handler = function(src, p)
        if cfg('TypeScreen').enabled == false then return fail('disabled') end
        local bt = p.bloodType
        if not validType(bt) then return fail('failed') end
        local first = not B.IsTyped(p)
        NZA.Patients.SetMeta(p.pid, 'bloodTyped', true)
        if NZA.Findings and type(NZA.Findings.Add) == 'function' then
            pcall(NZA.Findings.Add, p.pid, 'bloodtype', { type = bt, by = src })
        end
        if first then B.Bill(src, p, 'typeScreen', 1, tonumber(cfg('TypeScreen').fee) or 0) end
        if p.kind == 'player' and p.src and p.src ~= src then
            Core.Notify(p.src, { title = L('ts_title'), message = L('ts_patient', bt), type = 'info' })
        end
        NZA.Bus.Emit('blood:typed', src, p, bt)
        return true, { bloodType = bt, title = L('ts_title'), msg = L('ts_result', bt), record = L('rec_typed', bt) }
    end,
})
-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEMS
-- ════════════════════════════════════════════════════════════════════════

local function registerUsables()
    local deadline = GetGameTimer() + 15000
    while not Core.Has('Inv.RegisterUsable') and GetGameTimer() < deadline do Wait(500) end
    if not Core.Has('Inv.RegisterUsable') then
        NZA.Warn('blood: Bridge.Inv.RegisterUsable is missing - blood bags cannot be used from the inventory')
        return
    end
    local bag, empty = bagItem(), emptyItem()
    if bag then
        Core.B('Inv.RegisterUsable', bag, function(src, item)
            if not Core.Rate('blood:use', src, 3, 2000) then return end
            local m = type(item) == 'table' and type(item.metadata) == 'table' and item.metadata or nil
            if not m or not validType(m.type or m.bloodType) then
                -- some inventories do not hand the metadata to the usable callback
                local list = B.BagsOf(src)
                for _, b in ipairs(list) do
                    if item and tonumber(item.slot) and tonumber(b.slot) == tonumber(item.slot) then m = b break end
                end
                m = m or list[1]
            end
            if not m then return end
            local view = {
                serial = m.serial, type = validType(m.type or m.bloodType), ml = tonumber(m.ml) or cfg('Bags').ml,
                donor = m.donor, created = tonumber(m.created), expires = tonumber(m.expires),
                expired = isExpired(m), product = m.product or cfg('Bags').product, bagSize = cfg('Bags').bagSize,
                now = os.time(), warnDays = cfg('Bags').warnDays,
            }
            TriggerClientEvent('nza:blood:label', src, view)
        end)
    end
    if empty then
        Core.B('Inv.RegisterUsable', empty, function(src)
            if not Core.Rate('blood:use', src, 3, 2000) then return end
            Core.Notify(src, { title = L('empty_title'), message = L('empty_hint'), type = 'info' })
        end)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- LOOPS: expiry, seeding, NPC donors
-- ════════════════════════════════════════════════════════════════════════

local function bankKeys()
    local keys = {}
    local pts = (NZA.Hospitals and NZA.Hospitals.Points) and NZA.Hospitals.Points('bloodbank') or {}
    for _, pt in ipairs(pts) do keys[B.BankKey(pt)] = true end
    return keys
end

local function sweepExpired()
    if cfg('Bank').discardExpired == false then return end
    local now = os.time()
    for key, list in pairs(stock) do
        for serial, u in pairs(list) do
            if isExpired(u, now) then
                list[serial] = nil
                setUsed(serial, 3, key)
                B.Log(key, 'expired', u, nil)
            end
        end
    end
end

local function seedBanks()
    local seed = cfg('Bank').seed
    if type(seed) ~= 'table' or not next(seed) then return end
    for key in pairs(bankKeys()) do
        local flag = 'nza_blood_seed:' .. key
        if GetResourceKvpInt(flag) ~= 1 then
            SetResourceKvpInt(flag, 1)
            if stockCount(key) == 0 then
                for bt, n in pairs(seed) do
                    if validType(bt) then
                        for _ = 1, math.min(20, math.floor(tonumber(n) or 0)) do
                            local m = B.CreateBag({ type = bt, bank = key, donor = L('donor_seed') })
                            B.Log(key, 'seed', m, nil)
                        end
                    end
                end
            end
        end
    end
end

local npcNext = {}
local function npcDonations()
    local nd = cfg('Bank').npcDonors or {}
    if nd.enabled == false then return end
    local now = os.time()
    local interval = (tonumber(nd.interval) or 40) * 60
    local maxPer = tonumber(nd.maxPerType) or 6
    local maxStock = tonumber(cfg('Bank').maxStock) or 60
    for key in pairs(bankKeys()) do
        if not npcNext[key] then
            npcNext[key] = now + math.random(math.floor(interval * 0.5), interval)
        elseif now >= npcNext[key] then
            npcNext[key] = now + math.random(math.floor(interval * 0.75), math.floor(interval * 1.25))
            if stockCount(key) < maxStock then
                local bt = U.RandomBloodType()
                local n = 0
                for _, u in pairs(stock[key] or {}) do
                    if u.type == bt then n = n + 1 end
                end
                if n < maxPer then
                    local m = B.CreateBag({ type = bt, bank = key, donor = L('donor_npc') })
                    B.Log(key, 'donated', m, L('donor_npc'))
                end
            end
        end
    end
end

CreateThread(function()
    if not hasDB() then
        NZA.Warn('blood: oxmysql is not available - the blood bank runs in memory only')
        dbReady = true
    elseif MySQL.ready then
        local done = false
        MySQL.ready(function()
            loadAll()
            done = true
        end)
        local deadline = GetGameTimer() + 30000
        while not done and GetGameTimer() < deadline do Wait(200) end
    else
        loadAll()
    end
    registerUsables()
    -- the hospital module loads its points from the database: wait for them before seeding
    local deadline = GetGameTimer() + 60000
    while NZA.Hospitals and NZA.Hospitals.Ready and not NZA.Hospitals.Ready() and GetGameTimer() < deadline do Wait(1000) end
    seedBanks()
    sweepExpired()
    local tick = 0
    while true do
        Wait(60000)
        tick = tick + 1
        local ok, err = pcall(npcDonations)
        if not ok then NZA.Warn('blood: npc donations failed: ' .. tostring(err)) end
        if tick % 10 == 0 then
            pcall(sweepExpired)
            pcall(seedBanks)
        end
    end
end)

function B.Ready() return dbReady end

-- ════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════

exports('GetBloodStock', function(key) return B.Stock(key or 'shared') end)
exports('CreateBloodBag', function(meta) return B.CreateBag(meta) end)
exports('BloodCompatible', function(recipient, donor) return B.Compatible(recipient, donor) end)
