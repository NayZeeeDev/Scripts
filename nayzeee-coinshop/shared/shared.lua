if not NAYZEEE_LOCK_OK then return end

NZC = {}
NZC.Resource = GetCurrentResourceName()
NZC.Version  = GetResourceMetadata(NZC.Resource, 'version', 0) or '1.0.0'

Categories = { VEHICLE = 'vehicle', ITEM = 'item', WEAPON = 'weapon', TOOL = 'tool' }

-- Defaults in case the Config.Bundles block is missing from config.lua
Config.Bundles = Config.Bundles or {}
if Config.Bundles.CashAccount == nil then Config.Bundles.CashAccount = 'bank' end
if Config.Bundles.MaxCash == nil then Config.Bundles.MaxCash = 10000000 end
if Config.Bundles.HeroSeconds == nil then Config.Bundles.HeroSeconds = 7 end

-- ── locale ──────────────────────────────────────────────────────────────
local strings = {}
do
    local raw = LoadResourceFile(NZC.Resource, ('locales/%s.json'):format(Config.Locale or 'en'))
        or LoadResourceFile(NZC.Resource, 'locales/en.json')
    local ok, data = pcall(json.decode, raw or '{}')
    strings = ok and data or {}
    if Config.Locale ~= 'en' then
        local ok2, en = pcall(json.decode, LoadResourceFile(NZC.Resource, 'locales/en.json') or '{}')
        if ok2 and en then for k, v in pairs(en) do if strings[k] == nil then strings[k] = v end end end
    end
end

function NZC.Locale() return strings end

function T(key, ...)
    local s = strings[key] or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end

function Log(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    print(('^5[coinshop]^0 %s'):format(ok and msg or tostring(fmt)))
end

function Debug(fmt, ...)
    if Config.Debug then Log(fmt, ...) end
end

function NZC.Trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

function NZC.Int(v, min, max, default)
    v = math.floor(tonumber(v) or default or 0)
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end
