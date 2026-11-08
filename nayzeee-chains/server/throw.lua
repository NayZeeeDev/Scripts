-----------------------------------------------------------------
-- Throwing a chain
--
-- The thrower's client works out the whole flight once (gravity,
-- raycasts, a bounce or two) and sends the path. The server checks
-- it, takes the chain off them and plays the same path on every
-- client nearby, so everyone sees the same throw. When it lands it
-- becomes a drop, or the player standing there catches it.
-----------------------------------------------------------------

local cfg = Config.Throw
local T = Config.Text
local last = {}
local DT = 1 / 30

local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

RegisterNetEvent('nzc:s:throw', function(path, rest)
    local src = source
    if not cfg.Enabled or type(path) ~= 'table' then return end
    local now = GetGameTimer()
    if last[src] and now - last[src] < 1000 then return end
    last[src] = now

    if Worn.busy(src) then return end
    local w = Worn.get(src)
    if not w then return end
    local n = #path
    if n < 2 or n > 400 then return end

    -- everything is checked before the chain leaves the player
    local pts = {}
    for i = 1, n do
        pts[i] = Logs.vec(path[i], 20000)
        if not pts[i] then return end
    end
    local r = type(rest) == 'table' and Logs.vec(rest, 720) or vector3(0.0, 0.0, 0.0)
    if not r then return end
    local pc = Drops.pedCoords(src)
    if not pc or #(pc - pts[1]) > 3.0 then return end
    -- measured flat, so a throw off a roof can still fall all the way down
    if flat(pts[1], pts[n]) > (cfg.MaxDistance or 30.0) then return end
    for i = 2, n do
        if #(pts[i] - pts[i - 1]) > 2.5 then return end -- nothing moves that fast in 1/30 s
    end

    local meta = Worn.strip(src)
    if not meta then return end

    local land = pts[n]
    local duration = math.floor((n - 1) * DT * 1000)
    local fx = { from = src, chain = w.key, variant = w.letter, path = pts, dt = DT, rest = { x = r.x, y = r.y, z = r.z } }
    for _, id in ipairs(GetPlayers()) do
        local p = tonumber(id)
        local c = Drops.pedCoords(p)
        if c and #(c - land) < 150.0 then TriggerClientEvent('nzc:c:throwFx', p, fx) end
    end
    Worn.notify(src, T.thrown:format(meta.label), 'info')
    Logs.send('throw', 'Chain thrown', ('%s threw %s (%.1fm)'):format(Logs.who(src), meta.label or '?', #(pts[1] - land)))

    SetTimeout(duration, function()
        -- catch: the closest other player right where it lands
        if cfg.Catch then
            local best, bestD = nil, cfg.CatchRadius or 1.6
            for _, id in ipairs(GetPlayers()) do
                local p = tonumber(id)
                if p ~= src then
                    local c = Drops.pedCoords(p)
                    -- peds stand ~1m above the ground the chain lands on
                    local d = c and #(vector3(c.x, c.y, c.z - 0.6) - land)
                    if d and d < bestD then best, bestD = p, d end
                end
            end
            if best and Inv.CanCarry(best, meta) and Inv.Add(best, meta) then
                Worn.notify(best, T.caught:format(meta.label), 'success')
                TriggerClientEvent('nzc:c:anim', best, 'catch')
                Logs.send('throw', 'Chain caught', ('%s caught %s from %s'):format(Logs.who(best), meta.label or '?', Logs.who(src)))
                return
            end
        end
        Drops.add({
            meta = meta, coords = { x = land.x, y = land.y, z = land.z },
            rot = { x = r.x, y = r.y, z = r.z }, ownerSrc = src, thrown = true,
        })
    end)
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
