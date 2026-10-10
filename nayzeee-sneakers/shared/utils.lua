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
    if meta.limited then table.insert(lines, 1, 'Limited drop') end
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

local function defaultColour() return Config.BoxColours and Config.BoxColours[1] and Config.BoxColours[1].id or 'orange' end

--- A box colour id from the config, or the default one
function Shared.BoxColour(id)
    for _, c in ipairs(Config.BoxColours or {}) do if c.id == id then return id end end
    return defaultColour()
end

--- Base and lid model hashes for a box size in a colour (nzs_box_red / nzs_box_red_lid; the default
--- colour is the plain nzs_box)
function Shared.BoxModels(boxType, colour)
    local t = Config.BoxTypes[boxType] or Config.BoxTypes.shoe
    colour = Shared.BoxColour(colour)
    if colour == defaultColour() or not t.name then return t.base, t.lid end
    return GetHashKey(('%s_%s'):format(t.name, colour)), GetHashKey(('%s_%s_lid'):format(t.name, colour))
end

local modelMap
--- Box size id ('shoe' | 'heel' | 'boot') and colour for a placed box's model hash, or nil
function Shared.BoxTypeOfModel(model)
    if not modelMap then
        modelMap = {}
        for id, t in pairs(Config.BoxTypes) do
            for _, c in ipairs(Config.BoxColours or { { id = 'orange' } }) do
                local base = Shared.BoxModels(id, c.id)
                modelMap[base & 0xFFFFFFFF] = { id, c.id }
            end
        end
    end
    local e = modelMap[model & 0xFFFFFFFF]
    if e then return e[1], e[2] end
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
    local sm = Config.ShoeModels[modelId]
    if sm and sm.levelOverride then return sm.levelOverride end
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
-- Rockstar's clothing DLC names, without the mp_m_ / mp_f_ and the numbers (mp_m_heist3, mp_m_sum2_01 ...).
-- Their files are named like any pack's (mp_m_freemode_01_mp_m_airraces_01^feet_000_u), so it goes by name.
local GTA_DLC = {}
for _, n in ipairs({
    'airraces', 'apartment', 'arena', 'assault', 'battle', 'beach', 'biker', 'bikerdlc', 'business', 'casino',
    'christmas', 'cnc', 'executive', 'g9ec', 'gen9', 'gunrunning', 'halloween', 'heist', 'hipster',
    'importexport', 'independence', 'island', 'lowrider', 'lts', 'luxe', 'pilot', 'security', 'smuggler',
    'stunt', 'sum', 'summer', 'tuner', 'valentines', 'vinewood', 'xmas', 'fixer', 'chopshop', 'bounty',
}) do GTA_DLC[n] = true end

--- Is a clothing collection one of GTA's own (base game or a Rockstar DLC)? packs = set of collections
--- known to be clothing packs on this server (from sneakerkit's scan); they're never GTA.
function Shared.IsGtaCollection(collection, packs)
    local col = tostring(collection or ''):lower()
    if col == '' then return true end
    if col:sub(1, 1) == '@' or (packs and packs[col]) then return false end
    for _, extra in ipairs(Config.Studio and Config.Studio.GtaPacks or {}) do
        if tostring(extra):lower() == col then return true end
    end
    local rest = col:match('^mp_[mf]_(.+)$')
    if not rest then return false end
    local stem = rest:gsub('[_%d]+$', '')
    return stem == '' or GTA_DLC[stem] == true
end

function Shared.SupplierGoods()
    local out = {}
    for name, m in pairs(Config.Materials) do out[name] = m end
    for name, m in pairs(Config.Supplier.Extra or {}) do
        out[name] = m
    end
    return out
end

--------------------------------------------------------------------------------
-- Studio changes to the built-in shoes (name, price, level, colour names, on/off)
--------------------------------------------------------------------------------

local builtinOrig

--- over = { [modelId] = { label, retail, level, colours = { a = name }, enabled } }. Puts the built-in
--- shoes back as config/shoes.lua has them, then applies `over`. Call BuildShoes() after.
function Shared.ApplyBuiltinOverrides(over)
    if not builtinOrig then
        builtinOrig = {}
        for id, m in pairs(Config.ShoeModels) do
            if not m.studio then
                local cw = {}
                for l, n in pairs(m.colourways) do cw[l] = n end
                builtinOrig[id] = { label = m.label, retail = m.retail, colourways = cw }
            end
        end
    end
    for id, o in pairs(builtinOrig) do
        local m = Config.ShoeModels[id]
        if m then
            m.label, m.retail, m.levelOverride, m.hidden = o.label, o.retail, nil, nil
            m.colourways = {}
            for l, n in pairs(o.colourways) do m.colourways[l] = n end
            local v = over and over[id]
            if type(v) == 'table' then
                m.label = v.label or m.label
                m.retail = tonumber(v.retail) or m.retail
                m.levelOverride = tonumber(v.level)
                if type(v.colours) == 'table' then
                    for l, n in pairs(v.colours) do if m.colourways[l] then m.colourways[l] = n end end
                end
                if v.enabled == false then m.hidden = true end
            end
        end
    end
end
