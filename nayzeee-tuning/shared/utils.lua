NZ = NZ or {}
Locales = Locales or {}

local IS_SERVER = IsDuplicityVersion()

function L(key, ...)
    local pack = Locales[Config.Locale] or Locales.en or {}
    local str = pack[key] or (Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, str, ...)
        return ok and out or str
    end
    return str
end

function NZ.Debug(...)
    if Config.Debug then print(('^5[nayzeee-tuning]^7 %s'):format(table.concat({ ... }, ' '))) end
end

function NZ.Round(n, dp)
    local m = 10 ^ (dp or 0)
    return math.floor(n * m + 0.5) / m
end

function NZ.Clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function NZ.Count(t)
    local c = 0
    for _ in pairs(t or {}) do c = c + 1 end
    return c
end

function NZ.Copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = NZ.Copy(v) end
    return out
end

-- deep compare (numbers within 1e-4, key order irrelevant)
function NZ.Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == 'number' then return math.abs(a - b) < 1e-4 end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not NZ.Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function NZ.InList(list, value)
    for i = 1, #(list or {}) do if list[i] == value then return true end end
    return false
end

function NZ.TrimPlate(plate)
    return plate and (plate:gsub('^%s+', ''):gsub('%s+$', '')) or ''
end

--------------------------------------------------------------------- lookup tables

NZ.CategoryOf = {}
for _, cat in ipairs(Config.Categories) do
    for _, id in ipairs(cat.items) do NZ.CategoryOf[id] = cat.id end
end

NZ.PaintIndex = {}
for _, group in ipairs(Config.Paints) do
    for _, c in ipairs(group.colors) do NZ.PaintIndex[c[1]] = group.id end
end
if Config.ChameleonPaints.Enabled then
    for _, c in ipairs(Config.ChameleonPaints.colors) do NZ.PaintIndex[c[1]] = 'chameleon' end
end

NZ.SwapBySound = {}
for i, s in ipairs(Config.EngineSwaps.List) do NZ.SwapBySound[s.sound] = s; s.index = i end

NZ.PatternIds = {}
for _, p in ipairs(Config.NeonPatterns) do NZ.PatternIds[p[1]] = true end

NZ.TyreById, NZ.DriveById, NZ.SoundByAudio = {}, {}, {}
for _, t in ipairs(Config.Tyres.List) do NZ.TyreById[t.id] = t end
for _, d in ipairs(Config.Drivetrain.List) do NZ.DriveById[d.id] = d end
-- engine sounds bundled inside this resource (fxmanifest.lua ENGINE_SOUNDS) join the menu list automatically
do
    local res = GetCurrentResourceName()
    local listed = {}
    for _, sp in ipairs(Config.SoundPacks.List) do listed[sp.audio] = true end
    for i = 0, GetNumResourceMetadata(res, 'nz_engine_sound') - 1 do
        local entry = GetResourceMetadata(res, 'nz_engine_sound', i)
        local audio, label = (entry or ''):match('^([^|]+)|?(.*)$')
        if audio and not listed[audio] then
            Config.SoundPacks.List[#Config.SoundPacks.List + 1] = { audio = audio, label = label ~= '' and label or audio, bundled = true }
            listed[audio] = true
        end
    end
end
for _, sp in ipairs(Config.SoundPacks.List) do NZ.SoundByAudio[sp.audio] = sp end

NZ.EcuParams = {}
for _, p in ipairs(Config.ECU.Params) do NZ.EcuParams[p.key] = p end

--------------------------------------------------------------------- shop rules

-- Is an item allowed at a shop for a vehicle class? unlocked = set of upgrade keys a shop owns (nil = all)
function NZ.ShopAllows(shopId, itemId, class, unlocked)
    local shop = Config.Shops[shopId]
    local part = Config.Parts[itemId]
    if not shop or not part then return false end
    local cat = NZ.CategoryOf[itemId]
    local allow, block = shop.allow or {}, shop.block or {}

    if block.items and NZ.InList(block.items, itemId) then return false end
    if block.categories and NZ.InList(block.categories, cat) then return false end
    if class and block.classes and block.classes[class] then return false end
    if allow.items and #allow.items > 0 and not NZ.InList(allow.items, itemId) then
        if not (allow.categories and NZ.InList(allow.categories, cat)) then return false end
    elseif allow.categories and #allow.categories > 0 and not NZ.InList(allow.categories, cat) then
        return false
    end
    if class and allow.classes and next(allow.classes) and not allow.classes[class] then return false end

    -- feature toggles
    local k = part.kind
    if k == 'stance' and not Config.Stance.Enabled then return false end
    if k == 'height' and not Config.RideHeight.Enabled then return false end
    if k == 'airride' and not Config.AirRide.Enabled then return false end
    if k == 'nitrous' and not Config.Nitrous.Enabled then return false end
    if k == 'ecu' and not Config.ECU.Enabled then return false end
    if k == 'swap' and not Config.EngineSwaps.Enabled then return false end
    if k == 'antilag' and not Config.AntiLag.Enabled then return false end
    if k == 'launch' and not Config.LaunchControl.Enabled then return false end
    if k == 'locator' and not Config.Locator.Enabled then return false end
    if k == 'plateText' and not Config.Plates.Enabled then return false end
    if k == 'service' and not Config.Wear.Enabled then return false end
    if k == 'tyres' and not Config.Tyres.Enabled then return false end
    if k == 'drivetrain' and (not Config.Drivetrain.Enabled or (class and Config.Drivetrain.BlockedClasses[class])) then return false end
    if k == 'ceramic' and not Config.CeramicBrakes.Enabled then return false end
    if k == 'driftKit' and not Config.DriftKit.Enabled then return false end
    if k == 'gearbox' and not Config.Gearbox.Enabled then return false end
    if k == 'sound' and not Config.SoundPacks.Enabled then return false end

    -- workshop upgrades
    if Config.ShopUpgrades.Enabled and shop.job and unlocked then
        for key, up in pairs(Config.ShopUpgrades.List) do
            local gated = (up.categories and NZ.InList(up.categories, cat)) or (up.items and NZ.InList(up.items, itemId))
            if gated and not unlocked[key] then return false end
        end
    end
    return true
end

--------------------------------------------------------------------- validation

local function isInt(v, lo, hi) return type(v) == 'number' and v == math.floor(v) and v >= lo and v <= hi end
local function isNum(v, lo, hi) return type(v) == 'number' and v == v and v >= lo - 1e-6 and v <= hi + 1e-6 end
local function isRGB(t) return type(t) == 'table' and isInt(t.r, 0, 255) and isInt(t.g, 0, 255) and isInt(t.b, 0, 255) end

local validators = {
    mod = function(v) return isInt(v, -1, 250) end,
    toggle = function(v) return type(v) == 'boolean' end,
    color = function(v, part)
        if type(v) ~= 'table' then return false end
        if v.mode == 'index' then
            if not isInt(v.index, 0, 255) then return false end
            local grp = NZ.PaintIndex[v.index]
            return grp ~= nil
        elseif v.mode == 'rgb' then
            if part.target ~= 'primary' and part.target ~= 'secondary' then return false end
            return isRGB(v) and isInt(v.finish or 0, 0, 5)
        end
        return false
    end,
    wheels = function(v) return type(v) == 'table' and isInt(v.type, 0, 12) and isInt(v.index, -1, 500) end,
    rearWheels = function(v) return isInt(v, -1, 500) end,
    customTires = function(v) return type(v) == 'boolean' end,
    smoke = function(v) return isRGB(v) end,
    drift = function(v) return type(v) == 'boolean' end,
    bulletproof = function(v) return type(v) == 'boolean' end,
    wheelSize = function(v) local c = Config.WheelDimensions.Size return isNum(v, c.min, c.max) end,
    wheelWidth = function(v) local c = Config.WheelDimensions.Width return isNum(v, c.min, c.max) end,
    stance = function(v)
        if type(v) ~= 'table' then return false end
        local o, c = Config.Stance.Offset, Config.Stance.Camber
        return isNum(v.oF or 0, o.min, o.max) and isNum(v.oR or 0, o.min, o.max)
            and isNum(v.cF or 0, c.min, c.max) and isNum(v.cR or 0, c.min, c.max)
    end,
    height = function(v) return isNum(v, Config.RideHeight.min, Config.RideHeight.max) end,
    neon = function(v)
        return type(v) == 'table' and type(v.l) == 'boolean' and type(v.r) == 'boolean'
            and type(v.f) == 'boolean' and type(v.b) == 'boolean' and isRGB(v.color)
    end,
    neonPattern = function(v)
        return type(v) == 'table' and NZ.PatternIds[v.id] == true and (v.color2 == nil or isRGB(v.color2))
            and isInt(v.speed or 5, 1, 10)
    end,
    xenonColor = function(v)
        if type(v) ~= 'table' then return false end
        if v.mode == 'index' then return isInt(v.index, -1, 12) end
        return Config.XenonCustomRGB and v.mode == 'rgb' and isRGB(v)
    end,
    plateText = function(v)
        if type(v) ~= 'string' then return false end
        local p = v:upper()
        if #p < Config.Plates.MinLength or #p > Config.Plates.MaxLength then return false end
        if not p:match(Config.Plates.AllowedPattern) then return false end
        if p:match('^%s') or p:match('%s$') then return false end
        for _, w in ipairs(Config.Plates.BlockedWords) do if p:find(w, 1, true) then return false end end
        return true
    end,
    plateIndex = function(v) return isInt(v, 0, 12) end,
    tint = function(v) return isInt(v, 0, 6) end,
    extras = function(v)
        if type(v) ~= 'table' then return false end
        for k, on in pairs(v) do
            if not isInt(tonumber(k) or -1, 0, 20) or type(on) ~= 'boolean' then return false end
        end
        return true
    end,
    livery = function(v) return isInt(v, -1, 100) end,
    roofLivery = function(v) return isInt(v, -1, 100) end,
    nitrous = function(v) return v == 'refill' or isInt(v, 0, #Config.Nitrous.Levels) end,
    ecu = function(v) return type(v) == 'boolean' end,   -- fit / remove the programmable ECU (tuning is done on the tablet)
    swap = function(v) return v == false or (type(v) == 'string' and NZ.SwapBySound[v] ~= nil) end,
    antilag = function(v) return type(v) == 'boolean' end,
    launch = function(v) return type(v) == 'boolean' end,
    airride = function(v) return type(v) == 'boolean' end,
    locator = function(v) return type(v) == 'boolean' end,
    tyres = function(v) return type(v) == 'string' and NZ.TyreById[v] ~= nil end,
    drivetrain = function(v) return type(v) == 'string' and NZ.DriveById[v] ~= nil end,
    ceramic = function(v) return type(v) == 'boolean' end,
    driftKit = function(v) return type(v) == 'boolean' end,
    gearbox = function(v) return v == 'auto' or v == 'manual' end,
    sound = function(v) return v == false or (type(v) == 'string' and NZ.SoundByAudio[v] ~= nil) end,
    repair = function(v) return v == true end,
    clean = function(v) return v == true end,
    service = function(v) return v == true end,
}

function NZ.Validate(itemId, value)
    local part = Config.Parts[itemId]
    if not part then return false end
    local fn = validators[part.kind]
    return fn ~= nil and fn(value, part) == true
end

--------------------------------------------------------------------- pricing

local function clampPrice(part, p)
    if part.min and p < part.min then p = part.min end
    if part.max and p > part.max then p = part.max end
    return math.floor(p + 0.5)
end

local function base(part, vehPrice)
    if part.price then return part.price end
    local m = part.mult or 0
    if type(m) == 'table' then m = m[#m] end
    return clampPrice(part, vehPrice * m)
end

--[[ ctx = { extras = { ... current custom data ... }, wear = { ... } }
     returns price (0 = free), or nil when the value is invalid ]]
function NZ.ItemPrice(itemId, value, vehPrice, ctx)
    local part = Config.Parts[itemId]
    if not part then return nil end
    ctx = ctx or {}
    local k = part.kind

    if k == 'mod' then
        if value == -1 then return Config.Economy.RemovalFee end
        local m = part.mult
        if type(m) == 'table' then
            m = m[math.min(value + 1, #m)] or m[#m]
        end
        return clampPrice(part, vehPrice * (m or 0))
    elseif k == 'toggle' or k == 'drift' or k == 'bulletproof' or k == 'customTires'
        or k == 'antilag' or k == 'launch' or k == 'airride' or k == 'locator' then
        if value == false then return Config.Economy.RemovalFee end
        return base(part, vehPrice)
    elseif k == 'color' then
        local p = base(part, vehPrice)
        if value.mode == 'rgb' then p = p * (1 + (part.rgbExtra or 0)) end
        if value.mode == 'index' and NZ.PaintIndex[value.index] == 'chameleon' then
            p = p * Config.ChameleonPaints.PriceMultiplier
        end
        return math.floor(p + 0.5)
    elseif k == 'xenonColor' then
        local p = base(part, vehPrice)
        if value.mode == 'rgb' then p = p * (1 + (part.rgbExtra or 0)) end
        return math.floor(p + 0.5)
    elseif k == 'tyres' then
        return (NZ.TyreById[value] or {}).price
    elseif k == 'drivetrain' then
        return (NZ.DriveById[value] or {}).price
    elseif k == 'ceramic' then
        return value and Config.CeramicBrakes.Price or Config.Economy.RemovalFee
    elseif k == 'driftKit' then
        return value and Config.DriftKit.Price or Config.Economy.RemovalFee
    elseif k == 'gearbox' then
        return value == 'manual' and Config.Gearbox.Price or Config.Economy.RemovalFee
    elseif k == 'sound' then
        return value and Config.SoundPacks.Price or Config.Economy.RemovalFee
    elseif k == 'wheels' or k == 'rearWheels' then
        local idx = type(value) == 'table' and value.index or value
        if idx == -1 then return Config.Economy.RemovalFee end
        return base(part, vehPrice)
    elseif k == 'nitrous' then
        if value == 'refill' then return Config.Nitrous.RefillPrice end
        if value == 0 then return Config.Economy.RemovalFee end
        local lvl = Config.Nitrous.Levels[value]
        return lvl and lvl.price or nil
    elseif k == 'ecu' then
        if value == false then return Config.Economy.RemovalFee end
        return base(part, vehPrice)
    elseif k == 'swap' then
        if value == false then return Config.Economy.RemovalFee end
        local s = NZ.SwapBySound[value]
        return s and s.price or nil
    elseif k == 'service' then
        local restore = 0
        for _, v in pairs(ctx.wear or {}) do
            if type(v) == 'number' then restore = restore + math.max(0, 100 - v) end
        end
        return base(part, vehPrice) + math.floor(restore * Config.Wear.ServicePricePerPoint)
    end
    return base(part, vehPrice)
end

-- labour + tax + discount breakdown for a priced list
-- opts: { labour = per-item labour fee, surcharge = % added (self-service at staffed shops) }
function NZ.Totals(lines, discountPct, marginPct, opts)
    opts = opts or {}
    local perItem = opts.labour or Config.Economy.LaborPerItem
    local subtotal, labour = 0, 0
    for i = 1, #lines do
        subtotal = subtotal + (lines[i].price or 0)
        if (lines[i].price or 0) > 0 then labour = labour + perItem end
    end
    local mult = 1 + (marginPct or 0) / 100 + (opts.surcharge or 0) / 100
    if mult ~= 1 then subtotal = math.floor(subtotal * mult + 0.5) end
    local discount = discountPct and discountPct > 0 and math.floor(subtotal * discountPct / 100 + 0.5) or 0
    local taxed = subtotal - discount + labour
    local tax = Config.Economy.TaxPercent > 0 and math.floor(taxed * Config.Economy.TaxPercent / 100 + 0.5) or 0
    return {
        subtotal = subtotal, labour = labour, discount = discount, tax = tax, surcharge = opts.surcharge or 0,
        total = math.max(0, taxed + tax),
    }
end

--------------------------------------------------------------------- custom data (extras)

--[[ Custom data that GTA vehicle properties can't hold. Lives in the 'nzTune' state bag and the
     nz_tuning_vehicles table. Returns true when the item is an extras item. ]]
function NZ.ApplyToExtras(ex, itemId, value)
    local part = Config.Parts[itemId]
    if not part then return false end
    local k = part.kind
    if k == 'stance' then
        local empty = (value.oF or 0) == 0 and (value.oR or 0) == 0 and (value.cF or 0) == 0 and (value.cR or 0) == 0
        ex.stance = not empty and { oF = value.oF or 0, oR = value.oR or 0, cF = value.cF or 0, cR = value.cR or 0 } or nil
    elseif k == 'wheelSize' then ex.size = value
    elseif k == 'wheelWidth' then ex.width = value
    elseif k == 'height' then ex.height = value ~= 0 and value or nil
    elseif k == 'airride' then
        ex.airride = value or nil
        ex.air = value and (ex.air or Config.AirRide.DefaultPreset) or nil
    elseif k == 'swap' then ex.swap = value or nil
    elseif k == 'nitrous' then
        if value == 'refill' then
            if ex.nitrous then
                local lvl = Config.Nitrous.Levels[ex.nitrous.level]
                ex.nitrous.amount = lvl and lvl.capacity or 100
            end
        elseif value == 0 then ex.nitrous = nil
        else
            local lvl = Config.Nitrous.Levels[value]
            ex.nitrous = { level = value, amount = lvl and lvl.capacity or 100 }
        end
    elseif k == 'ecu' then
        -- fitting keeps whatever calibration the car already had; removing wipes it
        if value then ex.ecu = ex.ecu or {} else ex.ecu = nil end
    elseif k == 'antilag' then ex.antilag = value or nil
    elseif k == 'launch' then ex.launch = value or nil
    elseif k == 'neonPattern' then
        ex.neonPattern = value.id ~= 'static' and NZ.Copy(value) or nil
        ex.neonOwned = true
    elseif k == 'xenonColor' then ex.xenonRGB = value.mode == 'rgb' and { r = value.r, g = value.g, b = value.b } or nil
    elseif k == 'drift' then ex.drift = value or nil
    elseif k == 'bulletproof' then ex.bulletproof = value or nil
    elseif k == 'locator' then ex.locator = value or nil
    elseif k == 'tyres' then ex.tyres = value ~= 'stock' and value or nil
    elseif k == 'drivetrain' then ex.drive = value ~= 'stock' and value or nil
    elseif k == 'ceramic' then ex.ceramic = value or nil
    elseif k == 'driftKit' then ex.driftKit = value or nil
    elseif k == 'gearbox' then ex.gearbox = value == 'manual' and 'manual' or nil
    elseif k == 'sound' then ex.sound = value or nil
    elseif k == 'service' then
        ex.wear = { engine = 100, transmission = 100, brakes = 100, suspension = 100, tyres = 100, turbo = 100 }
    else
        return false
    end
    return true
end

-- kinds that are purely extras (no GTA property involved)
NZ.ExtrasKinds = {
    stance = true, wheelSize = true, wheelWidth = true, height = true, airride = true, swap = true, nitrous = true,
    ecu = true, antilag = true, launch = true, neonPattern = true, drift = true, bulletproof = true, locator = true, service = true,
    tyres = true, drivetrain = true, ceramic = true, driftKit = true, gearbox = true, sound = true,
}

--------------------------------------------------------------------- required part items

local cosmeticSlot = {}
for _, slot in ipairs(Config.PartItems.CosmeticSlots) do cosmeticSlot[slot] = true end

-- inventory items needed to fit one cart line ({} when none)
function NZ.RequiredItems(itemId, value, wear)
    local cfg = Config.PartItems
    if cfg.Mode == 'off' then return {} end
    local part = Config.Parts[itemId]
    if not part then return {} end
    local k, out = part.kind, {}
    local function add(x)
        if type(x) == 'table' then for _, i in ipairs(x) do out[#out + 1] = i end
        elseif x then out[#out + 1] = x end
    end
    -- removing a part never needs a new one
    if value == false or value == -1 or value == 0 and k == 'nitrous' or value == 'auto' then return {} end
    if k == 'swap' then
        local sw = NZ.SwapBySound[value]
        add(sw and cfg.Engines[sw.family])
    elseif k == 'tyres' then add(cfg.Tyres[value])
    elseif k == 'drivetrain' then add(cfg.Drivetrain[value])
    elseif k == 'nitrous' then add(value == 'refill' and Config.Nitrous.RefillItem or cfg.Items.nitrous)
    elseif k == 'service' then
        add(cfg.Service)
        for system, item in pairs(cfg.ServiceWorn) do
            if wear and (wear[system] or 100) < 70 then add(item) end
        end
    elseif k == 'wheels' and type(value) == 'table' and value.index == -1 then
        return {}
    elseif cfg.Items[itemId] ~= nil then add(cfg.Items[itemId])
    elseif k == 'mod' and cosmeticSlot[part.slot] then add(cfg.CosmeticDefault)
    end
    return out
end

--------------------------------------------------------------------- ECU ignition map

-- cells: list of numbers 0-100, fuel: 0-100. Returns gain (% power), knock (cells knocking), list of knocking cells
function NZ.EcuMap(cells, fuel)
    local m = Config.ECU.Map
    fuel = NZ.Clamp(tonumber(fuel) or 0, 0, 100)
    local over, knocking = 0, {}
    for i = 1, m.Cells do
        local v = NZ.Clamp(tonumber(cells and cells[i]) or m.Base, 0, 100)
        over = over + (v - m.Base)
        local thr = (m.Thresholds[i] or 70) + fuel * m.FuelRaise
        if v > thr then knocking[#knocking + 1] = i end
    end
    local gain = (over / (m.Cells * (100 - m.Base))) * m.MaxGain - (fuel / 100) * m.FuelCost
    return NZ.Round(gain, 2), #knocking, knocking
end

-- ECU calibration sliders from the tablet: { power = 6, grip = -2, ... }
function NZ.ValidEcuParams(t)
    if type(t) ~= 'table' then return false end
    for k, n in pairs(t) do
        local p = NZ.EcuParams[k]
        if not p or type(n) ~= 'number' or n ~= n or n < p.min or n > p.max then return false end
    end
    return true
end

function NZ.ValidMap(cells)
    if type(cells) ~= 'table' or #cells ~= Config.ECU.Map.Cells then return false end
    for i = 1, #cells do
        local v = cells[i]
        if type(v) ~= 'number' or v ~= v or v < 0 or v > 100 then return false end
    end
    return true
end

--------------------------------------------------------------------- engine swaps

function NZ.SwapsFor(modelName, class)
    local byModel = modelName and Config.EngineSwaps.ByModel[modelName]
    local list = byModel
    if list == nil then list = Config.EngineSwaps.ByClass[class] end
    if list == false then return {} end
    if list == nil then
        local all = {}
        for _, s in ipairs(Config.EngineSwaps.List) do all[#all + 1] = s.sound end
        return all
    end
    return list
end

--------------------------------------------------------------------- illegal parts

function NZ.IllegalParts(props, extras)
    local out, cfg = {}, Config.Police.Illegal
    props, extras = props or {}, extras or {}
    local function add(id, label) out[#out + 1] = { id = id, label = label } end

    if cfg.nitrous and extras.nitrous and (extras.nitrous.level or 0) > 0 then add('nitrous', L('illegal_nitrous')) end
    if cfg.antilag and extras.antilag then add('antilag', L('illegal_antilag')) end
    if cfg.launch and extras.launch then add('launch', L('illegal_launch')) end
    if cfg.engineSwap and extras.swap then add('swap', L('illegal_swap')) end
    if cfg.airride and extras.airride then add('airride', L('illegal_airride')) end
    if cfg.neonPattern and extras.neonPattern and extras.neonPattern.id ~= 'static' then add('neonPattern', L('illegal_neon_pattern')) end
    if cfg.neon and props.neonEnabled then
        for _, on in pairs(props.neonEnabled) do if on == true or on == 1 then add('neon', L('illegal_neon')) break end end
    end
    if type(cfg.tint) == 'table' and props.windowTint and cfg.tint[props.windowTint] then add('tint', L('illegal_tint')) end
    if type(cfg.xenonColor) == 'table' and type(props.xenonColor) == 'number' and cfg.xenonColor[props.xenonColor] then add('xenon', L('illegal_xenon')) end
    if cfg.customXenonRGB and extras.xenonRGB then add('xenonRGB', L('illegal_xenon')) end
    if cfg.bulletproof and extras.bulletproof then add('bulletproof', L('illegal_bulletproof')) end
    local st = extras.stance
    if cfg.camberAbove and st and ((st.cF or 0) > cfg.camberAbove or (st.cR or 0) > cfg.camberAbove) then add('camber', L('illegal_camber')) end
    if cfg.heightBelow and extras.height and extras.height > cfg.heightBelow then add('height', L('illegal_height')) end
    return out
end

NZ.IsServer = IS_SERVER

--------------------------------------------------------------------- shop editor (/mechaniceditor)

-- bays can be vec4(...) or { coords = vec4(...), radius = 2.4 }: keep shop.bays a plain vec4 list
-- and put any per-bay radius in shop.bayRadii[i]
local function normalizeBays(shop)
    shop.bayRadii = shop.bayRadii or {}
    for i, b in ipairs(shop.bays or {}) do
        if type(b) == 'table' and b.coords then
            if b.radius then shop.bayRadii[i] = tonumber(b.radius) end
            shop.bays[i] = b.coords
        end
    end
end
for _, shop in pairs(Config.Shops) do normalizeBays(shop) end

-- radius of one bay (its own, else the shop's bayRadius)
function NZ.BayRadius(shop, i)
    return (shop.bayRadii and shop.bayRadii[i]) or shop.bayRadius or 2.4
end

-- shops exactly as config.shops.lua defines them; edits are layered on top of this copy
NZ.ShopBase = NZ.Copy(Config.Shops)

NZ.EditorPiles = { 'body', 'exhaust', 'engine', 'jacks', 'wheels', 'paint', 'interior', 'electronics', 'repair' }

local function v3(t) return type(t) == 'table' and t.x and vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0) or nil end
local function v4(t) return type(t) == 'table' and t.x and vec4(t.x + 0.0, t.y + 0.0, t.z + 0.0, (t.w or 0.0) + 0.0) or nil end

-- vectors -> plain tables (safe for json / state bags)
function NZ.Plain(v)
    local tv = type(v)
    if tv == 'vector3' then return { x = v.x, y = v.y, z = v.z } end
    if tv == 'vector4' then return { x = v.x, y = v.y, z = v.z, w = v.w } end
    if tv ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = NZ.Plain(x) end
    return out
end

local function applyOne(id, e)
    if e.deleted then Config.Shops[id] = nil return end
    local shop = Config.Shops[id]
    if not shop then
        shop = { grades = { access = 0, manager = 2, boss = 3 }, bays = {}, bayRadii = {}, bayRadius = 2.4, radius = 30.0, booths = {}, stockpiles = {},
            parts = {}, allow = {}, block = {}, blip = { enabled = true, sprite = 446, color = 5, scale = 0.8 }, created = true }
        Config.Shops[id] = shop
    end
    for k, v in pairs(e) do
        if k == 'bays' then
            shop.bays, shop.bayRadii = {}, {}
            for i, b in ipairs(v) do
                shop.bays[i] = v4(b)
                if tonumber(b.r) then shop.bayRadii[i] = tonumber(b.r) end
            end
        elseif k == 'booths' then
            shop.booths = {}
            for i, b in ipairs(v) do shop.booths[i] = { coords = v3(b.coords), radius = tonumber(b.radius) or 4.5 } end
        elseif k == 'stockpiles' then
            shop.stockpiles = {}
            for pile, c in pairs(v) do shop.stockpiles[pile] = v3(c) end
        elseif k == 'center' or k == 'boss' or k == 'drop' or k == 'storage' then shop[k] = v ~= false and v3(v) or nil
        elseif k == 'truckSpawn' then shop[k] = v ~= false and v4(v) or nil
        elseif k == 'claimBays' then shop.claimBays = v ~= 'auto' and v or nil
        elseif k == 'partSource' then shop.partSource = v ~= 'default' and v or nil
        elseif k == 'grades' then shop.grades = NZ.Copy(v)
        elseif k == 'blip' then shop.blip = NZ.Copy(v)
        elseif k ~= 'deleted' then shop[k] = v end
    end
end

-- rebuild Config.Shops from the config file plus every saved edit
function NZ.ApplyShopEdits(edits)
    for id in pairs(Config.Shops) do if not NZ.ShopBase[id] then Config.Shops[id] = nil end end
    for id, base in pairs(NZ.ShopBase) do Config.Shops[id] = NZ.Copy(base) end
    for id, e in pairs(edits or {}) do applyOne(id, e) end
end

--------------------------------------------------------------------- supply storage / bays

-- where a shop's work-order parts come from: 'supply' | 'inventory' | 'both'
function NZ.PartSource(shopId)
    local shop = Config.Shops[shopId]
    local src = shop and shop.partSource or Config.Storage.PartSource
    if not Config.Storage.Enabled then return 'inventory' end
    if src ~= 'supply' and src ~= 'inventory' and src ~= 'both' then return 'supply' end
    return src
end

-- supply storage point (falls back to the boss desk, then the drop point)
function NZ.StorageOf(shopId)
    local shop = Config.Shops[shopId]
    if not shop then return nil end
    return shop.storage or shop.boss or shop.drop
end

-- do mechanics claim bays at this shop?
function NZ.BayClaims(shopId)
    local shop = Config.Shops[shopId]
    local B = Config.Bays
    if not shop or not shop.job or not B.Claims then return false end
    if shop.claimBays ~= nil then return shop.claimBays == true end
    return B.Modes[shop.mode or 'self'] == true and #(shop.bays or {}) >= (B.MinBays or 1)
end
