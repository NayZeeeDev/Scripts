-----------------------------------------------------------------
-- Padlocks (server)
--
-- A lock lives in the bag item's metadata, so it travels with the bag:
-- robbed, dropped, handed over or set down, it stays locked.
--
-- The code is stored as a salted hash. The salt never leaves the
-- server, so reading item metadata on a client gives nothing away.
--
-- Every way into a bag goes through Locks.gate(): it opens straight
-- away for the owner (and anyone who already typed the code), and
-- otherwise asks for the code, a lockpick or bolt cutters.
-----------------------------------------------------------------

Locks = {}

local cfg = Config.Padlock or {}
local enabled = cfg.enabled == true
local ox = exports.ox_inventory

local function S(key, ...) return select('#', ...) > 0 and Strings[key]:format(...) or Strings[key] end
local function tell(src, key, kind, ...) TriggerClientEvent('nayzeee-backpack:notify', src, S(key, ...), kind or 'error') end
local function sound(name, at, delay) if Sounds then Sounds.play(name, at, delay) end end

-----------------------------------------------------------------
-- hashing
-----------------------------------------------------------------

local salt = GetResourceKvpString('nb_lock_salt')
if not salt then
    local chars = {}
    for i = 1, 32 do chars[i] = string.char(math.random(33, 126)) end
    salt = table.concat(chars)
    SetResourceKvp('nb_lock_salt', salt)
end

local function hash(code, bagid)
    -- two rounds with different inputs: a 64-bit-ish fingerprint
    local a = joaat(('%s|%s|%s'):format(salt, bagid, code))
    local b = joaat(('%s|%s|%s'):format(code, salt, bagid))
    return ('%08x%08x'):format(a & 0xffffffff, b & 0xffffffff)
end

local function validCode(code)
    code = tostring(code or '')
    local digits = cfg.digits or 4
    return code:match(('^%s$'):format(('%d'):rep(digits))) and code or nil
end

-----------------------------------------------------------------
-- who may open without asking
-----------------------------------------------------------------

local known = {} -- [bagid] = { [identifier] = true } typed the right code (until restart / code change)

function Locks.isLocked(meta)
    return enabled and type(meta) == 'table' and type(meta.lock) == 'table'
end

local function trusted(src, meta)
    local id = Framework.getIdentifier(src)
    if cfg.ownerSkipsCode ~= false and meta.lock.owner == id then return true end
    local k = known[meta.bagid]
    return cfg.rememberCode ~= false and k ~= nil and k[id] == true
end

local function remember(src, bagid)
    known[bagid] = known[bagid] or {}
    known[bagid][Framework.getIdentifier(src)] = true
end

local function hasItem(src, name)
    return name and (ox:Search(src, 'count', name) or 0) > 0
end

-----------------------------------------------------------------
-- the gate
-----------------------------------------------------------------

local pending = {} -- [src] = { bagid, open, getMeta, save, label, at }
local fails = {}   -- [src .. bagid] = { n, until }

---@param opts { open: fun(), getMeta: fun(): table?, save: fun(meta: table), bag: string, police?: boolean }
function Locks.gate(src, meta, opts)
    if not Locks.isLocked(meta) or trusted(src, meta) then return opts.open() end
    if opts.police and cfg.policeOpen then return opts.open() end

    pending[src] = {
        bagid = meta.bagid, open = opts.open, getMeta = opts.getMeta, save = opts.save,
        bag = opts.bag, at = os.time(),
    }
    sound('lock', src) -- the rattle of a locked zip
    TriggerClientEvent('nayzeee-backpack:lock:prompt', src, {
        label = Bags.label(opts.bag),
        canPick = cfg.lockpick and cfg.lockpick.item and hasItem(src, cfg.lockpick.item) or false,
        canCut = cfg.cutter and cfg.cutter.item and hasItem(src, cfg.cutter.item) or false,
    })
end

--- Is this pending attempt still about the same, still-locked bag?
local function current(src)
    local p = pending[src]
    if not p or os.time() - p.at > 120 then pending[src] = nil return nil end
    local meta = p.getMeta()
    if not meta or meta.bagid ~= p.bagid then pending[src] = nil return nil end
    return p, meta
end

local function breakLock(src, p, meta, how)
    meta.lock = nil
    meta.description = BagDescription(p.bag, meta)
    p.save(meta)
    known[p.bagid] = nil
    pending[src] = nil
    if Logs then Logs.lock(src, p.bag, how) end
    p.open()
end

RegisterNetEvent('nayzeee-backpack:lock:try', function(method, value)
    local src = source
    local p, meta = current(src)
    if not p then return end
    if not Locks.isLocked(meta) then pending[src] = nil return p.open() end

    if method == 'code' then
        local key = src .. ':' .. p.bagid
        local f = fails[key]
        if f and f.untilAt and os.time() < f.untilAt then
            return tell(src, 'lk_lockout', 'error', f.untilAt - os.time())
        end
        local code = validCode(value)
        if code and hash(code, p.bagid) == meta.lock.h then
            fails[key] = nil
            remember(src, p.bagid)
            pending[src] = nil
            sound('unlock', src)
            return p.open()
        end
        f = f or { n = 0 }
        f.n = f.n + 1
        if f.n >= (cfg.maxTries or 3) then
            f.n, f.untilAt = 0, os.time() + (cfg.lockout or 60)
            tell(src, 'lk_lockout', 'error', cfg.lockout or 60)
        else
            tell(src, 'lk_wrong', 'error', (cfg.maxTries or 3) - f.n)
        end
        fails[key] = f
        sound('lock', src)

    elseif method == 'pick' then
        local lp = cfg.lockpick or {}
        if not hasItem(src, lp.item) then return tell(src, 'lk_no_pick') end
        -- the client minigame takes a few seconds; anything faster isn't a person
        if os.time() - p.at < 2 then return end
        if value == true then
            sound('unlock', src)
            tell(src, 'lk_picked', 'success')
            return breakLock(src, p, meta, 'picked')
        end
        if math.random(100) <= (lp.breakChance or 35) then
            ox:RemoveItem(src, lp.item, 1)
            tell(src, 'lk_pick_broke')
        else
            tell(src, 'lk_pick_failed')
        end
        p.at = os.time()

    elseif method == 'cut' then
        local c = cfg.cutter or {}
        if not hasItem(src, c.item) then return tell(src, 'lk_no_cutter') end
        if os.time() - p.at < math.floor((c.time or 6000) / 1000) - 1 then return end
        sound('cut', src)
        tell(src, 'lk_cut', 'success')
        return breakLock(src, p, meta, 'cut')
    end
end)

RegisterNetEvent('nayzeee-backpack:lock:cancel', function()
    pending[source] = nil
end)

-----------------------------------------------------------------
-- locking your own bag
-----------------------------------------------------------------

local function wornBag(src)
    local item = FindBagItem(src)
    if not item or not item.metadata or not item.metadata.bagid then return nil end
    return item, item.metadata
end

exports('usePadlock', function(event, item, inventory)
    if event ~= 'usingItem' then return end
    local src = inventory.id
    local bag, meta = wornBag(src)
    if not bag then tell(src, 'no_bag') return false end
    if Locks.isLocked(meta) then tell(src, 'lk_already') return false end
    TriggerClientEvent('nayzeee-backpack:lock:set', src, Bags.label(bag.name), cfg.digits or 4)
    return false -- taken when the lock actually goes on
end)

RegisterNetEvent('nayzeee-backpack:lock:apply', function(code)
    local src = source
    if not enabled then return end
    code = validCode(code)
    if not code then return tell(src, 'lk_bad_code', 'error', cfg.digits or 4) end

    local bag, meta = wornBag(src)
    if not bag then return tell(src, 'no_bag') end
    if Locks.isLocked(meta) then return tell(src, 'lk_already') end
    if Player(src).state.nb_open then return tell(src, 'ho_close_first') end
    if not ox:RemoveItem(src, cfg.item, 1) then return tell(src, 'lk_no_padlock') end

    meta.lock = { h = hash(code, meta.bagid), owner = Framework.getIdentifier(src), at = os.time() }
    meta.description = BagDescription(bag.name, meta)
    ox:SetMetadata(src, bag.slot, meta)
    known[meta.bagid] = nil
    remember(src, meta.bagid)
    RefreshBagState(src)

    sound('lock', src)
    tell(src, 'lk_locked', 'success')
    if Logs then Logs.lock(src, bag.name, 'locked') end
end)

--- Owner (or someone with the code) changes it or takes the lock off.
RegisterNetEvent('nayzeee-backpack:lock:manage', function(action, oldCode, newCode)
    local src = source
    local bag, meta = wornBag(src)
    if not bag or not Locks.isLocked(meta) then return end

    local ok = trusted(src, meta)
    if not ok then
        local c = validCode(oldCode)
        ok = c ~= nil and hash(c, meta.bagid) == meta.lock.h
    end
    if not ok then return tell(src, 'lk_wrong_plain') end

    if action == 'remove' then
        meta.lock = nil
        meta.description = BagDescription(bag.name, meta)
        ox:SetMetadata(src, bag.slot, meta)
        known[meta.bagid] = nil
        if cfg.returnPadlock ~= false then ox:AddItem(src, cfg.item, 1) end
        RefreshBagState(src)
        sound('unlock', src)
        tell(src, 'lk_removed', 'success')
    elseif action == 'change' then
        local c = validCode(newCode)
        if not c then return tell(src, 'lk_bad_code', 'error', cfg.digits or 4) end
        meta.lock.h = hash(c, meta.bagid)
        meta.lock.owner = Framework.getIdentifier(src)
        ox:SetMetadata(src, bag.slot, meta)
        known[meta.bagid] = nil
        remember(src, meta.bagid)
        sound('lock', src)
        tell(src, 'lk_changed', 'success')
    end
end)

--- Can this player skip the code on their own worn bag? (bag menu)
lib.callback.register('nayzeee-backpack:lock:state', function(src)
    local bag, meta = wornBag(src)
    if not bag then return nil end
    return {
        locked = Locks.isLocked(meta),
        trusted = Locks.isLocked(meta) and trusted(src, meta) or false,
        hasPadlock = enabled and hasItem(src, cfg.item) or false,
    }
end)

AddEventHandler('playerDropped', function()
    local src = source
    pending[src] = nil
    for k in pairs(fails) do
        if k:find('^' .. src .. ':') then fails[k] = nil end
    end
end)
