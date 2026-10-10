--[[
    ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗
    ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝
    ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗
    ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝
    ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗
    ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝

    NAYZEEE BILLING - Shared Utilities
    Discord: discord.gg/nayzeeedev
]]

Shared = {}
Shared.Version = '2.0.0'
Shared.Resource = GetCurrentResourceName()

-- Invoice statuses
Shared.Status = {
    PENDING = 'pending',
    PARTIAL = 'partial',
    OVERDUE = 'overdue',
    DISPUTED = 'disputed',
    PAID = 'paid',
    CANCELLED = 'cancelled',
    REFUNDED = 'refunded',
}

-- Statuses that still have money owed on them
Shared.OpenStatuses = { 'pending', 'partial', 'overdue' }

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
        Shared.Framework = 'standalone'
    end

    Shared.Debug('Framework detected:', Shared.Framework)
    return Shared.Framework
end

-- ██╗   ██╗████████╗██╗██╗     ███████╗
-- ██║   ██║╚══██╔══╝██║██║     ██╔════╝
-- ██║   ██║   ██║   ██║██║     ███████╗
-- ██║   ██║   ██║   ██║██║     ╚════██║
-- ╚██████╔╝   ██║   ██║███████╗███████║
--  ╚═════╝    ╚═╝   ╚═╝╚══════╝╚══════╝

function Shared.Debug(...)
    if Config.Debug then
        print('^3[NAYZEEE-BILLING]^7', ...)
    end
end

function Shared.Round(n, decimals)
    local mult = 10 ^ (decimals or 2)
    n = tonumber(n) or 0
    if n >= 0 then
        return math.floor(n * mult + 0.5) / mult
    end
    return math.ceil(n * mult - 0.5) / mult
end

function Shared.Clamp(n, min, max)
    n = tonumber(n) or min
    if n < min then return min end
    if n > max then return max end
    return n
end

function Shared.FormatNumber(n)
    n = tonumber(n) or 0
    local formatted = string.format('%.2f', n)
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

function Shared.FormatCurrency(amount)
    return (Config.Currency or '$') .. Shared.FormatNumber(amount)
end

-- Strip control characters / HTML brackets and clamp length. The UI escapes everything too,
-- this just keeps garbage out of the database and Discord logs.
function Shared.Sanitize(str, maxLen)
    if type(str) ~= 'string' then
        if type(str) == 'number' then str = tostring(str) else return '' end
    end
    str = str:gsub('[%c]', ' '):gsub('[<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #str > maxLen then
        str = str:sub(1, maxLen)
    end
    return str
end

-- IDs used for registers/products/categories created in-game
function Shared.Slug(str)
    str = Shared.Sanitize(str, 40):lower():gsub('[^%w_%-]', '_'):gsub('_+', '_')
    return str
end

local idChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
function Shared.GenerateInvoiceId()
    local id = {}
    for i = 1, 8 do
        local idx = math.random(1, #idChars)
        id[i] = idChars:sub(idx, idx)
    end
    return 'INV-' .. table.concat(id)
end

function Shared.TableContains(t, value)
    if type(t) ~= 'table' then return false end
    for _, v in pairs(t) do
        if v == value then return true end
    end
    return false
end

function Shared.Count(t)
    local c = 0
    for _ in pairs(t or {}) do c = c + 1 end
    return c
end

-- Totals shared by client preview & server (server is always authoritative)
function Shared.CalculateTotals(items, discountPercent, taxRate)
    local subtotal = 0
    for _, item in ipairs(items or {}) do
        subtotal = subtotal + (tonumber(item.price) or 0) * (tonumber(item.quantity) or 0)
    end
    subtotal = Shared.Round(subtotal)
    local discount = Shared.Round(subtotal * ((tonumber(discountPercent) or 0) / 100))
    local tax = Shared.Round((subtotal - discount) * (tonumber(taxRate) or 0))
    local total = Shared.Round(subtotal - discount + tax)
    return { subtotal = subtotal, discount = discount, tax = tax, total = total }
end
