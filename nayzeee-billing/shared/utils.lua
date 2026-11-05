--[[
    NAYZEEE BILLING - Shared utilities
    Discord: discord.gg/nayzeeedev
]]

Shared = {}
Shared.Version = '1.0.0'
Shared.Resource = GetCurrentResourceName()

Shared.OpenStatuses = { pending = true, partial = true, overdue = true }

-- ██╗      ██████╗  ██████╗ █████╗ ██╗     ███████╗
-- ██║     ██╔═══██╗██╔════╝██╔══██╗██║     ██╔════╝
-- ██║     ██║   ██║██║     ███████║██║     █████╗
-- ██║     ██║   ██║██║     ██╔══██║██║     ██╔══╝
-- ███████╗╚██████╔╝╚██████╗██║  ██║███████╗███████╗
-- ╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝

-- locales/<Config.Locale>.json, falling back to en.json, then to the text passed in code
local Locale, Fallback = {}, {}

local function loadLocale(lang)
    local raw = LoadResourceFile(Shared.Resource, ('locales/%s.json'):format(lang))
    if not raw then return {} end
    local ok, data = pcall(json.decode, raw)
    return ok and type(data) == 'table' and data or {}
end

Fallback = loadLocale('en')
Locale = Config.Locale ~= 'en' and loadLocale(Config.Locale) or Fallback

function Shared.LocaleTable()
    local merged = {}
    for k, v in pairs(Fallback) do merged[k] = v end
    for k, v in pairs(Locale) do merged[k] = v end
    return merged
end

-- L('payment.received', 'Received {amount}', { amount = '$5' })
function L(key, fallback, vars)
    if type(fallback) == 'table' then vars, fallback = fallback, nil end
    local text = Locale[key] or Fallback[key] or fallback or key
    if vars then
        text = text:gsub('{(%w+)}', function(k)
            local v = vars[k]
            return v ~= nil and tostring(v) or '{' .. k .. '}'
        end)
    end
    return text
end

-- ███████╗██████╗  █████╗ ███╗   ███╗███████╗██╗    ██╗ ██████╗ ██████╗ ██╗  ██╗
-- ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝██║    ██║██╔═══██╗██╔══██╗██║ ██╔╝
-- █████╗  ██████╔╝███████║██╔████╔██║█████╗  ██║ █╗ ██║██║   ██║██████╔╝█████╔╝
-- ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝  ██║███╗██║██║   ██║██╔══██╗██╔═██╗
-- ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║██║  ██╗
-- ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

Shared.Framework = nil

function Shared.GetFramework()
    if Shared.Framework then return Shared.Framework end
    local forced = Config.Framework
    if forced and forced ~= 'auto' then
        Shared.Framework = forced
    elseif GetResourceState('qbx_core') == 'started' then
        Shared.Framework = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then
        Shared.Framework = 'qbcore'
    elseif GetResourceState('es_extended') == 'started' then
        Shared.Framework = 'esx'
    else
        Shared.Framework = 'custom'
    end
    return Shared.Framework
end

-- ██╗   ██╗████████╗██╗██╗     ███████╗
-- ██║   ██║╚══██╔══╝██║██║     ██╔════╝
-- ██║   ██║   ██║   ██║██║     ███████╗
-- ██║   ██║   ██║   ██║██║     ╚════██║
-- ╚██████╔╝   ██║   ██║███████╗███████║
--  ╚═════╝    ╚═╝   ╚═╝╚══════╝╚══════╝

function Shared.Debug(...)
    if Config.Debug then print('^3[NAYZEEE-BILLING]^7', ...) end
end

function Shared.Round(n, decimals)
    local mult = 10 ^ (decimals or 2)
    n = tonumber(n) or 0
    if n >= 0 then return math.floor(n * mult + 0.5) / mult end
    return math.ceil(n * mult - 0.5) / mult
end

function Shared.Clamp(n, min, max)
    n = tonumber(n) or min
    if n ~= n then n = min end -- NaN
    if n < min then return min end
    if n > max then return max end
    return n
end

function Shared.FormatNumber(n)
    local formatted = string.format('%.2f', tonumber(n) or 0):gsub('%.00$', '')
    local k
    repeat formatted, k = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2') until k == 0
    return formatted
end

function Shared.Money(amount)
    local s = Shared.FormatNumber(amount)
    if Config.CurrencyPosition == 'after' then return s .. Config.Currency end
    return Config.Currency .. s
end

function Shared.Sanitize(str, maxLen)
    if type(str) == 'number' then str = tostring(str) end
    if type(str) ~= 'string' then return '' end
    str = str:gsub('[%c]', ' '):gsub('[<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #str > maxLen then str = str:sub(1, maxLen) end
    return str
end

function Shared.Slug(str)
    return (Shared.Sanitize(str, 40):lower():gsub('[^%w_%-]', '_'):gsub('_+', '_'))
end

local refChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
function Shared.RandomCode(len)
    local out = {}
    for i = 1, len or 8 do
        local idx = math.random(1, #refChars)
        out[i] = refChars:sub(idx, idx)
    end
    return table.concat(out)
end

function Shared.Contains(t, value)
    if type(t) ~= 'table' then return false end
    for _, v in pairs(t) do if v == value then return true end end
    return false
end

function Shared.Count(t)
    local c = 0
    for _ in pairs(t or {}) do c = c + 1 end
    return c
end

function Shared.Copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Shared.Copy(v) end
    return out
end

-- Society config with defaults applied
function Shared.Society(id)
    local s = id and Config.Societies[id]
    if not s then return nil end
    return s
end

function Shared.VatRate(societyId, personal)
    if not Config.VAT.Enabled then return 0 end
    if personal then return Config.Personal.VAT and Config.VAT.Rate or 0 end
    local s = Shared.Society(societyId)
    if s and s.vat == false then return 0 end
    if s and tonumber(s.vat) then return tonumber(s.vat) end
    return Config.VAT.Rate or 0
end

function Shared.Totals(items, vatRate)
    local subtotal = 0
    for _, item in ipairs(items or {}) do
        subtotal = subtotal + (tonumber(item.amount) or 0) * (tonumber(item.quantity) or 1)
    end
    subtotal = Shared.Round(subtotal)
    local vat = Shared.Round(subtotal * (tonumber(vatRate) or 0))
    return { subtotal = subtotal, vat = vat, total = Shared.Round(subtotal + vat) }
end
