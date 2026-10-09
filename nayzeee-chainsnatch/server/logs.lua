-- Discord logs (ServerConfig.Webhook) + console

Logs = {}

local RES = GetCurrentResourceName()
local COLORS = { snatch = 15026509, throw = 569250, admin = 15050250, info = 10395294 }

function Logs.send(kind, title, text)
    if Config.Debug then print(('^5[%s]^7 %s: %s'):format(RES, title, text)) end
    local hook = ServerConfig.Webhook
    if not hook or hook == '' then return end
    PerformHttpRequest(hook, function() end, 'POST', json.encode({
        username = 'Chain Snatch',
        embeds = { {
            title = title, description = text, color = COLORS[kind] or COLORS.info,
            footer = { text = RES }, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }), { ['Content-Type'] = 'application/json' })
end

function Logs.who(src)
    return ('%s (%s)'):format(Bridge.GetCharName(src), src)
end

--- A real number in a sane range (rejects NaN, inf and strings from modded clients)
function Logs.num(v, lim)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) > (lim or 100000) then return nil end
    return v + 0.0
end

--- {x,y,z} of real numbers, or nil
function Logs.vec(t, lim)
    if type(t) ~= 'table' and type(t) ~= 'vector3' then return nil end
    local x, y, z = Logs.num(t.x, lim), Logs.num(t.y, lim), Logs.num(t.z, lim)
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

local asked = {}
--- At most one call per `ms` per player per kind (resend requests and the like)
function Logs.throttle(src, kind, ms)
    local k = kind .. ':' .. tostring(src)
    local now = GetGameTimer()
    if asked[k] and now - asked[k] < ms then return true end
    asked[k] = now
    return false
end
