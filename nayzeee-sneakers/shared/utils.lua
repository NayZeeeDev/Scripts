Shared = {}

-- Text for the chosen language (locales/*.lua), falling back to English for anything missing
local chosen = Locales[Config.Locale]
Config.Text = (chosen and chosen ~= Locales.en) and setmetatable(chosen, { __index = Locales.en }) or Locales.en

local SERIAL_CHARS = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'

local function checksum(body)
    local sum = 0
    for i = 1, #body do sum = sum + body:byte(i) * i end
    local k = sum % #SERIAL_CHARS + 1
    return SERIAL_CHARS:sub(k, k)
end

--- Serial like NZ-7F3K2Q8M. Real pairs end in a valid check character;
--- fakes get a random one, which a legit check can catch later.
function Shared.NewSerial(real)
    local body = ''
    for _ = 1, 7 do
        local k = math.random(#SERIAL_CHARS)
        body = body .. SERIAL_CHARS:sub(k, k)
    end
    local check = checksum(body)
    if not real then
        repeat
            local k = math.random(#SERIAL_CHARS)
            check = SERIAL_CHARS:sub(k, k)
        until check ~= checksum(body)
    end
    return ('NZ-%s%s'):format(body, check)
end

function Shared.SerialValid(serial)
    local body, check = tostring(serial):match('^NZ%-(%w%w%w%w%w%w%w)(%w)$')
    return body ~= nil and checksum(body) == check
end

function Shared.ConditionLabel(id)
    for _, c in ipairs(Config.Conditions) do
        if c.id == id then return c.label end
    end
    return id or '?'
end

function Shared.ShoeName(meta)
    local shoe = meta and Config.Shoes[meta.shoe]
    if not shoe then return 'Unknown shoes' end
    return ("%s '%s'"):format(shoe.label, shoe.colourway)
end

--- Text shown under the item in the inventory
function Shared.Describe(meta)
    local dirt = tonumber(meta.dirt) or 0
    local lines = {
        ('US %s · %s'):format(meta.size or '?', Shared.ConditionLabel(meta.condition)),
        ('Serial %s'):format(meta.serial or '—'),
    }
    if dirt >= 5 then lines[#lines + 1] = ('Dirt %d%%'):format(dirt) end
    local km = tonumber(meta.km) or 0
    if km >= 0.1 then lines[#lines + 1] = ('Worn %.1f km'):format(km) end
    return table.concat(lines, '\n')
end

--- 'male' | 'female' | nil (non-freemode ped)
function Shared.PedGender(model)
    if model == `mp_m_freemode_01` then return 'male' end
    if model == `mp_f_freemode_01` then return 'female' end
    return nil
end

--- The clothing entry a ped of `gender` should get for this shoe, or nil
function Shared.ClothingFor(shoe, gender)
    local c = shoe and shoe.clothing
    if not c then return nil end
    if c[gender] then return c[gender] end
    if c.drawable ~= nil or c.slot ~= nil or c.index ~= nil then return c end
    return nil
end

function Shared.Debug(...)
    if Config.Debug then print('^5[nayzeee-sneakers]^7', ...) end
end

--- Box size id ('shoe' | 'heel' | 'boot') for a placed box's model hash, or nil
function Shared.BoxTypeOfModel(model)
    local m = model & 0xFFFFFFFF
    for id, t in pairs(Config.BoxTypes) do
        if (t.base & 0xFFFFFFFF) == m then return id end
    end
end

--- Box size id for an empty-box item name, or nil
function Shared.BoxTypeOfItem(name)
    for id, t in pairs(Config.BoxTypes) do
        if t.item == name then return id end
    end
end

--- The box size a shoe goes in
function Shared.BoxTypeForShoe(shoeId)
    local shoe = Config.Shoes[shoeId]
    return shoe and Config.BoxTypes[shoe.box] and shoe.box or 'shoe'
end

--------------------------------------------------------------------------------
-- Crafting and XP
--------------------------------------------------------------------------------

--- level, XP where this level starts, XP where the next one starts (nil at max)
function Shared.LevelFor(xp)
    local levels = Config.XP.levels
    local level = 1
    for i = 1, #levels do
        if xp >= levels[i] then level = i end
    end
    return level, levels[level], levels[level + 1]
end

function Shared.ModelLevel(modelId)
    local over = Config.Crafting.models[modelId]
    if over and over.level then return over.level end
    local m = Config.ShoeModels[modelId]
    return m and m.level or 1
end

--- Materials for one pair of `modelId`: { [item] = count }
function Shared.Recipe(modelId, real)
    local m = Config.ShoeModels[modelId]
    if not m then return nil end
    local over = Config.Crafting.models[modelId]
    local out = {}
    for k, v in pairs(over and over.recipe or Config.Recipes[m.box] or Config.Recipes.shoe) do out[k] = v end
    if real then
        for k, v in pairs(Config.Crafting.realExtra) do out[k] = (out[k] or 0) + v end
    end
    return out
end

--- The stages for `modelId` at `level`, with times sped up by level
function Shared.Stages(modelId, level)
    local m = Config.ShoeModels[modelId]
    local list = Config.Crafting.stages[m and m.box or 'shoe'] or Config.Crafting.stages.shoe
    local speed = 1.0 - math.min(0.4, (level - 1) * Config.Crafting.speedPerLevel)
    local out = {}
    for i, s in ipairs(list) do
        out[i] = {
            label = s.label,
            time = math.floor(s.time * speed),
            check = Config.Crafting.skillChecks and s.check or false,
            anim = s.anim,
        }
    end
    return out
end

--- Display name for any item this script knows about
function Shared.ItemLabel(name)
    if Config.Materials[name] then return Config.Materials[name].label end
    if Config.Supplier.Extra and Config.Supplier.Extra[name] then return Config.Supplier.Extra[name].label end
    if Config.Tables.items[name] then return Config.Tables.items[name].label end
    return name
end

--------------------------------------------------------------------------------
-- Wear
--------------------------------------------------------------------------------

local GRADE = { DS = 1, VNDS = 2, USED = 3, BEAT = 4 }

--- Condition after `km` of wear. A pair never gets better than it already is.
function Shared.WearCondition(km, current)
    local grade = 'DS'
    for _, c in ipairs({ 'VNDS', 'USED', 'BEAT' }) do
        if km > Config.WearOut[c] then grade = c end
    end
    if GRADE[current] and GRADE[current] > GRADE[grade] then return current end
    return grade
end

--- Everything the supplier sells: materials plus Config.Supplier.Extra
function Shared.SupplierGoods()
    local out = {}
    for name, m in pairs(Config.Materials) do out[name] = m end
    for name, m in pairs(Config.Supplier.Extra or {}) do
        out[name] = m
    end
    return out
end
