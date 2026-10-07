-- Shared helpers (client + server)

RESOURCE = GetCurrentResourceName()
VERSION  = GetResourceMetadata(RESOURCE, 'version', 0) or '2.0.0'

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

-- tiers -------------------------------------------------------------------

TierIndex = {}
for i, t in ipairs(Config.Tiers) do TierIndex[t.id] = i end

function GetTier(id)
    return Config.Tiers[TierIndex[id] or 1]
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

-- Same hairstyle always maps to the same name
function StyleNameFor(model, drawable, texture)
    local n = #Config.Styles
    local seed = (drawable or 0) * 7 + (texture or 0) * 3 + (model == 'm' and 11 or 0)
    return Config.Styles[(seed % n) + 1]
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
