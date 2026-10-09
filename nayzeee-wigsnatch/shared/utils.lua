-- Shared helpers (client + server)

RESOURCE = GetCurrentResourceName()
VERSION  = GetResourceMetadata(RESOURCE, 'version', 0) or '3.1.0'
IS_SERVER = IsDuplicityVersion()

local locale = Locales and (Locales[Config.Locale] or Locales.en) or {}

function L(key, ...)
    local s = locale[key] or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        return ok and out or s
    end
    return s
end

function Debug(...)
    if Config.Debug then print(('^5[%s]^7'):format(RESOURCE), ...) end
end

-- Player statebags this script owns. Other scripts can read them too.
ST = {
    tied    = 'nzTied',      -- true while zip-tied
    held    = 'nzHeld',      -- holder's server id while being held
    holding = 'nzHolding',   -- held player's server id while holding someone
    down    = 'nzDown',      -- true for a few seconds after being tackled
    fx      = 'nzHairFx',    -- { burn = until, lice = until, dirt = until } for visuals
    busy    = 'nzWigBusy',   -- true while in a minigame / cut / restraint action
    wig     = 'nzWigOn',     -- true while wearing a wig item
}

-- our own restraint states count everywhere a restrained check happens
do
    local function add(list, key)
        for _, k in ipairs(list) do if k == key then return end end
        list[#list + 1] = key
    end
    add(Config.RestrainedStates, ST.tied)
    add(Config.RestrainedStates, ST.held)
    add(Config.RestrainedStates, ST.down)
end

function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Round(v) return math.floor(v + 0.5) end

-- tiers -------------------------------------------------------------------

TierIndex = {}
for i, t in ipairs(Config.Tiers) do TierIndex[t.id] = i end

function GetTier(id)
    return Config.Tiers[TierIndex[id] or 1]
end

GradeIndex = {}
for i, g in ipairs(Config.Bundles.Grades) do GradeIndex[g.id] = i end

function GetGrade(id)
    return Config.Bundles.Grades[GradeIndex[id] or 1]
end

-- levels ------------------------------------------------------------------

function GetLevel(xp)
    xp = xp or 0
    local lvl = 1
    for i = 1, #Config.Levels do
        if xp >= Config.Levels[i].xp then lvl = i else break end
    end
    return lvl, Config.Levels[lvl]
end

function GetPerks(xp)
    local _, data = GetLevel(xp)
    local p = data.perks or {}
    return {
        cooldown = p.cooldown or 0,
        zone     = p.zone or 0,
        sell     = p.sell or 0,
        luck     = p.luck or 0,
    }
end

-- styles ------------------------------------------------------------------

-- Names given to hairstyles in the Wig Studio: StyleNames['m:12'] = 'Knotless Braids'
StyleNames = {}

function LoadStyleNames()
    local raw = LoadResourceFile(RESOURCE, 'data/style_names.json')
    local ok, data = pcall(json.decode, raw or '{}')
    StyleNames = (ok and type(data) == 'table') and data or {}
end
LoadStyleNames()

-- Same hairstyle always maps to the same name
function StyleNameFor(model, drawable, texture)
    local named = StyleNames[('%s:%d:%d'):format(model or 'f', drawable or 0, texture or 0)]
        or StyleNames[('%s:%d'):format(model or 'f', drawable or 0)]
    if named and named ~= '' then return named end
    local n = #Config.Styles
    local seed = (drawable or 0) * 7 + (texture or 0) * 3 + (model == 'm' and 11 or 0)
    return Config.Styles[(seed % n) + 1]
end

-- Every style name a player can collect (config + studio names, no duplicates)
function CatalogStyles()
    local out, seen = {}, {}
    for _, s in ipairs(Config.Styles) do
        if not seen[s] then seen[s] = true out[#out + 1] = s end
    end
    for _, s in pairs(StyleNames) do
        if type(s) == 'string' and s ~= '' and not seen[s] then seen[s] = true out[#out + 1] = s end
    end
    return out
end

function ModelKey(hash)
    if hash == Config.Models.female.model then return 'f' end
    if hash == Config.Models.male.model then return 'm' end
    return nil
end

function ModelEnabled(key)
    if key == 'f' then return Config.Models.female.enabled end
    if key == 'm' then return Config.Models.male.enabled end
    return false
end

function GenderKey(key)
    return key == 'm' and 'male' or 'female'
end

function IsBaldDrawable(key, drawable)
    local list = Config.BaldDrawables[GenderKey(key)]
    return list and list[drawable] == true
end

-- Hair short enough that scissors won't give bundles (bald, buzz, fade results)
function IsShortDrawable(key, drawable)
    if IsBaldDrawable(key, drawable) then return true end
    local g = GenderKey(key)
    for _, kind in ipairs({ 'buzz', 'fade', 'bald' }) do
        for _, d in ipairs(Config.Cutting.Results[kind][g] or {}) do
            if d == drawable then return true end
        end
    end
    return false
end

-- Studio photo path for a hairstyle (relative to the resource)
-- wig_f_12_0: the studio photo's file name (also its ox_inventory image name)
function StudioShotName(model, drawable, texture)
    return ('wig_%s_%d_%d'):format(model == 'm' and 'm' or 'f', drawable or 0, texture or 0)
end

function StudioShotPath(model, drawable, texture)
    return ('shots/%s.png'):format(StudioShotName(model, drawable, texture))
end

-- all tool names in a stable order
ToolOrder = { 'scissors', 'clippers', 'razor' }

function ProductByItem(item)
    for id, p in pairs(Config.Products.List) do
        if p.Item == item then return id, p end
    end
end
