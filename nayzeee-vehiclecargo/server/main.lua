-----------------------------------------------------------------
-- Core server state
-----------------------------------------------------------------
Server = {
    Players  = {},   -- [src] = { identifier, name, inside, mission }
    Cleanup  = {},   -- functions(src, state) run on drop / logout
}

local bucketsReady = {}

function Server.Get(src)
    local s = Server.Players[src]
    local identifier = Bridge.GetIdentifier(src)
    if s and s.identifier then
        if s.identifier == identifier then return s end
        -- character switched without a logout event: clean the old one up
        for _, fn in ipairs(Server.Cleanup) do pcall(fn, src, s) end
        DB.DropProfile(s.identifier)
        Server.Players[src] = nil
    end
    if not identifier then return nil end
    s = { identifier = identifier, name = Bridge.GetName(src) }
    Server.Players[src] = s
    return s
end

function Server.Profile(src)
    local s = Server.Get(src)
    if not s then return nil end
    local p = DB.GetProfile(s.identifier, s.name)
    if p.name ~= s.name then p.name = s.name end
    return p
end

function Server.Level(src)
    local p = Server.Profile(src)
    return p and Cargo.LevelFromXp(p.xp) or 1
end

-- Prestige: permanent bonuses and (optionally) every unlock kept after the reset
local P = Config.Prestige or {}
function Server.PrestigeOf(p) return (P.Enabled and p and p.prestige) or 0 end
function Server.Level(p)
    local lvl = Cargo.LevelFromXp(p.xp)
    if P.KeepUnlocks and Server.PrestigeOf(p) > 0 then return Config.Levels.Max end
    return lvl
end
function Server.SaleMult(src)
    return 1 + Server.PrestigeOf(Server.Profile(src)) * (P.SaleBonus or 0)
end

function Server.AddXp(src, amount)
    local p = Server.Profile(src)
    if not p or amount <= 0 then return false end
    amount = amount * (1 + Server.PrestigeOf(p) * (P.XpBonus or 0))
    local before = Cargo.LevelFromXp(p.xp)
    p.xp = p.xp + math.floor(amount)
    DB.SaveProfile(p)
    local after = Cargo.LevelFromXp(p.xp)
    if after > before then
        Bridge.Notify(src, L('level_up', after), 'success', 'Level Up')
        TriggerClientEvent('nz_cargo:levelUp', src, after)
        return true
    end
    return false
end

function Server.Notify(src, msg, t, title) Bridge.Notify(src, msg, t, title) end

function Server.Charge(src, amount, reason)
    amount = math.floor(amount)
    if amount <= 0 then return true end
    if Bridge.RemoveMoney(src, Config.Accounts.Purchase, amount, reason or 'vehiclecargo') then return true end
    Server.Notify(src, L('no_money', lib.math.groupdigits(amount)), 'error')
    return false
end

function Server.Now() return os.time() end

-----------------------------------------------------------------
-- Vehicle pool (config defaults + admin added)
-----------------------------------------------------------------
local pool, poolByRarity

function Server.RebuildPool()
    local merged, order = {}, {}
    for _, v in ipairs(Config.Vehicles) do
        merged[v.model] = { model = v.model, label = v.label or v.model, rarity = v.rarity, value = v.value, type = v.type, enabled = true, custom = false }
        order[#order + 1] = v.model
    end
    for _, v in ipairs(Config.IllegalVehicles or {}) do
        merged[v.model] = { model = v.model, label = v.label or v.model, rarity = Config.Illegal.id, value = v.value, type = v.type, enabled = true, custom = false }
        order[#order + 1] = v.model
    end
    for model, v in pairs(DB.Custom) do
        if not merged[model] then order[#order + 1] = model end
        merged[model] = { model = model, label = v.label, rarity = v.rarity, value = v.value, enabled = v.enabled, custom = true,
            type = merged[model] and merged[model].type or nil, override = merged[model] ~= nil }
    end
    pool, poolByRarity = {}, {}
    for _, m in ipairs(order) do
        local v = merged[m]
        pool[#pool + 1] = v
        if v.enabled and Cargo.Rarity[v.rarity] then
            poolByRarity[v.rarity] = poolByRarity[v.rarity] or {}
            table.insert(poolByRarity[v.rarity], v)
        end
    end
end

function Server.Pool() return pool end
function Server.TypeOf(model)
    for _, v in ipairs(pool) do if v.model == model then return v.type or 'automobile' end end
    return 'automobile'
end
function Server.PoolFor(rarity) return poolByRarity[rarity] or {} end

-----------------------------------------------------------------
-- Interior layout (config, overridden by /cargoslots saves)
-----------------------------------------------------------------
-- Every floor preset: config ones plus any saved by admins.
-- The open floor (admin override → config). Presets are fitted inside it.
function Server.FloorArea()
    local o = (DB.Settings.interior or {}).floor
    local f = Config.Interior.Floor or {}
    local src = o or { min = f.Min, max = f.Max, z = f.Z, obstacles = {} }
    local area = {
        min = { x = math.min(src.min.x, src.max.x), y = math.min(src.min.y, src.max.y) },
        max = { x = math.max(src.min.x, src.max.x), y = math.max(src.min.y, src.max.y) },
        z = src.z or f.Z or Config.Interior.Entry.z, obstacles = {},
    }
    local obs = o and o.obstacles or nil
    if not obs then
        obs = {}
        for _, ob in ipairs(f.Obstacles or {}) do obs[#obs + 1] = { min = ob.Min, max = ob.Max } end
    end
    for _, ob in ipairs(obs) do
        area.obstacles[#area.obstacles + 1] = {
            min = { x = math.min(ob.min.x, ob.max.x), y = math.min(ob.min.y, ob.max.y) },
            max = { x = math.max(ob.min.x, ob.max.x), y = math.max(ob.min.y, ob.max.y) },
        }
    end
    return area
end

function Server.Presets()
    local out = {}
    local area = Server.FloorArea()
    for _, p in ipairs(Config.LayoutPresets) do
        out[#out + 1] = { id = p.id, label = p.label, slots = Cargo.PresetSlots(p, area) }
    end
    for _, p in ipairs(DB.Settings.presets or {}) do
        out[#out + 1] = { id = p.id, label = p.label, slots = Cargo.PresetSlots({ slots = p.slots }), admin = true }
    end
    return out
end

function Server.Preset(id)
    for _, p in ipairs(Server.Presets()) do if p.id == id then return p end end
end

-- Server-wide default floor: the admin's /cargoslots layout, else the default preset.
function Server.DefaultSlots()
    local o = DB.Settings.interior or {}
    if o.slots and #o.slots > 0 then return o.slots end
    local p = Server.Preset(Config.DefaultPreset) or Server.Presets()[1]
    return p and p.slots or {}
end

function Server.Interior()
    local o = DB.Settings.interior or {}
    local i = Config.Interior
    local L = i.Lower
    -- the lower floor always has exactly 4 spots: admin-moved ones, else the config defaults
    local lowerSlots = {}
    local moved = o.lowerSlots or {}
    for k = 1, 4 do
        local v = moved[k] or moved[tostring(k)] or L.Slots[k]
        if v then lowerSlots[#lowerSlots + 1] = DB.V4(v) end
    end
    return {
        ipl      = i.Ipl,
        coords   = DB.V4(i.Coords),
        entry    = o.entry or DB.V4(i.Entry),
        exit     = o.exit or DB.V4(i.Exit),
        laptop   = o.laptop or DB.V4(i.Laptop),
        design   = o.design or DB.V4(i.Design),
        slots    = Server.DefaultSlots(),
        cam      = i.DesignCam,
        sets     = i.ExtraSets,
        lower    = {
            ipl = L.Ipl, coords = DB.V4(L.Coords),
            split = L.SplitZ or (L.Coords.z + 4.5),
            slots = lowerSlots,
        },
    }
end

-- Main floor spots for one warehouse: owner layout → chosen preset → server default.
function Server.Slots(w)
    if w.layout and #w.layout > 0 then return w.layout end
    if w.preset then
        local p = Server.Preset(w.preset)
        if p then return p.slots end
    end
    return Server.DefaultSlots()
end

function Server.InteriorFor(w)
    local i = Server.Interior()
    i.slots = Server.Slots(w)
    i.lowerOpen = (w.upgrades.lower or 0) >= 1
    return i
end

-----------------------------------------------------------------
-- Owner preferences (laptop look + accent), validated against config
-----------------------------------------------------------------
local function prefIds(list)
    local ids = {}
    for _, v in ipairs(list) do ids[v.id] = true end
    return ids
end

function Server.Prefs(w)
    local P, out = Config.Prefs, {}
    for k, v in pairs(P.Default) do out[k] = v end
    local saved = w and w.prefs or {}
    local acc, fin, wal = prefIds(P.Accents), prefIds(P.Finishes), prefIds(P.Wallpapers)
    if acc[saved.accent] then out.accent = saved.accent end
    if fin[saved.finish] then out.finish = saved.finish end
    if wal[saved.wallpaper] then out.wallpaper = saved.wallpaper end
    if saved.clock == '12' or saved.clock == '24' then out.clock = saved.clock end
    for _, b in ipairs({ 'fastboot', 'sounds', 'glass', 'radio' }) do
        if type(saved[b]) == 'boolean' then out[b] = saved[b] end
    end
    return out
end

-- The look a player carries everywhere: their own (first) warehouse
function Server.MyPrefs(src)
    local s = Server.Get(src)
    local own = s and Server.Owned(s.identifier)[1]
    return Server.Prefs(own)
end

-----------------------------------------------------------------
-- Warehouses & access
-----------------------------------------------------------------
function Server.Owned(identifier)
    local out = {}
    for _, id in ipairs(DB.ByOwner[identifier] or {}) do
        if DB.Warehouses[id] then out[#out + 1] = DB.Warehouses[id] end
    end
    return out
end

function Server.Access(src, wid)
    local s = Server.Get(src)
    local w = DB.Warehouses[wid]
    if not s or not w then return nil end
    if w.owner == s.identifier then return 'owner' end
    for _, a in ipairs(w.associates) do
        if a.identifier == s.identifier then return 'associate' end
    end
    if w.raid and w.raid.police and w.raid.police[s.identifier] then return 'police' end
    if w.guests and w.guests[s.identifier] then return 'guest' end
    return nil
end

-- Crew roles (Config.Roles). The owner can do everything.
function Server.Role(id)
    for _, r in ipairs(Config.Roles.List) do if r.id == id then return r end end
    return Server.Role(Config.Roles.Default) or Config.Roles.List[#Config.Roles.List]
end

function Server.RoleOf(src, wid)
    local s = Server.Get(src)
    local w = DB.Warehouses[wid]
    if not s or not w then return nil end
    if w.owner == s.identifier then return 'owner' end
    for _, a in ipairs(w.associates) do
        if a.identifier == s.identifier then return Server.Role(a.role).id end
    end
end

-- perm = a key from Config.Roles, or 'owner' for owner-only actions
function Server.Can(src, wid, perm)
    local role = Server.RoleOf(src, wid)
    if not role then return false end
    if role == 'owner' then return true end
    if perm == 'owner' then return false end
    local r = Server.Role(role)
    return r and r.perms and r.perms[perm] == true or false
end

function Server.Perms(src, wid)
    local role = Server.RoleOf(src, wid)
    local out = {}
    if not role then return out end
    for _, r in ipairs(Config.Roles.List) do for k in pairs(r.perms) do out[k] = role == 'owner' or nil end end
    if role ~= 'owner' then for k, v in pairs(Server.Role(role).perms) do out[k] = v end end
    out.owner = role == 'owner'
    return out
end

-- every warehouse this player can open (own + associate)
function Server.Accessible(src)
    local s = Server.Get(src)
    if not s then return {} end
    local out = {}
    for _, w in pairs(DB.Warehouses) do
        if w.owner == s.identifier then
            out[#out + 1] = { id = w.id, location = w.location, role = 'owner', owner = w.owner_name }
        else
            for _, a in ipairs(w.associates) do
                if a.identifier == s.identifier then
                    out[#out + 1] = { id = w.id, location = w.location, role = 'associate', owner = w.owner_name }
                    break
                end
            end
        end
    end
    return out
end

function Server.Capacity(w, floor)
    if floor == 'lower' then
        if (w.upgrades.lower or 0) < 1 then return 0 end
        return #Server.Interior().lower.slots
    end
    local u = Cargo.Upgrade('capacity', w.upgrades.capacity)
    return math.min(u and u.slots or 8, #Server.Slots(w), Config.Layout.MaxSlots)
end

function Server.Bucket(wid) return Config.BucketBase + wid end

function Server.PutInBucket(src, wid)
    local b = wid and Server.Bucket(wid) or 0
    if b ~= 0 and not bucketsReady[b] then
        SetRoutingBucketPopulationEnabled(b, false)
        SetRoutingBucketEntityLockdownMode(b, 'relaxed')
        bucketsReady[b] = true
    end
    SetPlayerRoutingBucket(src, b)
    local s = Server.Get(src)
    if s then
        s.inside = wid
        -- remembered per character so a restart / relog inside puts them back in the right one
        if not s.preview then DB.SetLastInside(Server.Profile(src), wid) end
    end
end

-- Front door to send someone to when they can't go back inside
function Server.FallbackDoor(src, w)
    local loc = w and DB.Locations[w.location]
    if loc then return loc.door end
    for _, a in ipairs(Server.Accessible(src)) do
        loc = DB.Locations[a.location]
        if loc then return loc.door end
    end
    local broker = (DB.Settings.brokers or {})[1]
    if broker then return broker end
    for _, l in pairs(DB.Locations) do return l.door end
end

-- Everyone currently inside a warehouse (for live refreshes)
function Server.Occupants(wid)
    local out = {}
    for src, s in pairs(Server.Players) do
        if s.inside == wid then out[#out + 1] = src end
    end
    return out
end

-----------------------------------------------------------------
-- Logs
-----------------------------------------------------------------
function Server.Webhook(title, fields)
    if not Config.Logs.Webhook or Config.Logs.Webhook == '' then return end
    local f = {}
    for k, v in pairs(fields or {}) do f[#f + 1] = { name = k, value = tostring(v), inline = true } end
    PerformHttpRequest(Config.Logs.Webhook, function() end, 'POST', json.encode({
        username = 'Vehicle Cargo',
        embeds = { { title = title, color = Config.Logs.Color, fields = f, footer = { text = 'nayzeee-vehiclecargo v' .. Cargo.Version }, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

-----------------------------------------------------------------
-- Boot
-----------------------------------------------------------------
CreateThread(function()
    DB.Init()
    Server.RebuildPool()
    print(('^5[nayzeee-vehiclecargo]^7 v%s ready  ·  %d locations  ·  %d warehouses  ·  %d vehicles  ·  framework: %s'):format(
        Cargo.Version, (function() local n = 0 for _ in pairs(DB.Locations) do n = n + 1 end return n end)(),
        (function() local n = 0 for _ in pairs(DB.Warehouses) do n = n + 1 end return n end)(),
        #Server.Pool(), tostring(Bridge.Framework)))
end)

Bridge.OnUnload(function(src)
    local s = Server.Players[src]
    if not s then return end
    for _, fn in ipairs(Server.Cleanup) do pcall(fn, src, s) end
    if s.identifier then DB.DropProfile(s.identifier) end
    Server.Players[src] = nil
    if GetPlayerPing(src) > 0 then SetPlayerRoutingBucket(src, 0) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= Cargo.Resource then return end
    for src, s in pairs(Server.Players) do
        if s.inside then SetPlayerRoutingBucket(src, 0) end
        for _, fn in ipairs(Server.Cleanup) do pcall(fn, src, s) end
    end
end)

lib.callback.register('nz_cargo:ready', function() return DB.Ready end)

-- Exports for other resources
exports('GetLevel', function(src) return Server.Level(src) end)
exports('AddXp', function(src, amount) return Server.AddXp(src, amount) end)
exports('IsInWarehouse', function(src) local s = Server.Players[src] return s and s.inside or false end)
