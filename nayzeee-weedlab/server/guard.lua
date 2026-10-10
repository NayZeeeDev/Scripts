--[[ Anti-exploit helpers shared by every server module ]]

Guard = {}

local buckets = {}

--- true if `src` may run `key` now (one call per `ms`)
function Guard.rate(src, key, ms)
    local now = GetGameTimer()
    local b = buckets[src]
    if not b then b = {} buckets[src] = b end
    local last = b[key]
    if last and now - last < ms then return false end
    b[key] = now
    return true
end

--- Global per-player call budget (calls per second) for every callback
local counters = {}
function Guard.budget(src)
    local now = os.time()
    local c = counters[src]
    if not c or c.t ~= now then
        counters[src] = { t = now, n = 1 }
        return true
    end
    c.n = c.n + 1
    if c.n > ServerConfig.Exploit.maxCallsPerSecond then
        if c.n == ServerConfig.Exploit.maxCallsPerSecond + 1 then
            Guard.flag(src, 'callback spam')
        end
        return false
    end
    return true
end

function Guard.flag(src, reason)
    local msg = ('[nzwl] exploit check: %s (%s) - %s'):format(GetPlayerName(src) or '?', src, reason)
    print('^1' .. msg .. '^7')
    if Logs then Logs.send('Exploit check', msg, 15158332) end
    if ServerConfig.Exploit.action == 'kick' then
        DropPlayer(src, 'nayzeee-weedlab: invalid request')
    end
end

function Guard.coords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

function Guard.near(src, coords, max)
    local c = Guard.coords(src)
    return c ~= nil and #(c - Utils.vec3(coords)) <= max
end

--- lib.callback.register wrapper with the call budget applied
function Guard.callback(name, fn)
    lib.callback.register(name, function(src, ...)
        if not Guard.budget(src) then return false end
        return fn(src, ...)
    end)
end

AddEventHandler('playerDropped', function()
    buckets[source] = nil
    counters[source] = nil
end)

--[[ Discord logs ]]
Logs = {}
function Logs.send(title, description, color)
    if ServerConfig.Webhook == '' then return end
    PerformHttpRequest(ServerConfig.Webhook, function() end, 'POST', json.encode({
        username = ServerConfig.WebhookName,
        embeds = { { title = title, description = description, color = color or 7101695, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end
