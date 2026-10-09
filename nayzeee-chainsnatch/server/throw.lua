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

local function v3(t) return vector3((t.x or t[1] or 0) + 0.0, (t.y or t[2] or 0) + 0.0, (t.z or t[3] or 0) + 0.0) end

RegisterNetEvent('nzc:s:throw', function(path, rest)
    local src = source
    if not cfg.Enabled or type(path) ~= 'table' then return end
    local now = GetGameTimer()
    if last[src] and now - last[src] < 1000 then return end
    last[src] = now

    local w = Worn.get(src)
    if not w then return end
    local n = #path
    if n < 2 or n > 400 then return end

    local pts = {}
    for i = 1, n do
        if type(path[i]) ~= 'table' and type(path[i]) ~= 'vector3' then return end
        pts[i] = v3(path[i])
    end
    local pc = Drops.pedCoords(src)
    if not pc or #(pc - pts[1]) > 3.0 then return end
    if #(pts[1] - pts[n]) > (cfg.MaxDistance or 30.0) then return end
    for i = 2, n do
        if #(pts[i] - pts[i - 1]) > 2.5 then return end -- nothing moves that fast in 1/30 s
    end

    local meta = Worn.strip(src)
    if not meta then return end

    local land = pts[n]
    local duration = math.floor((n - 1) * DT * 1000)
    local fx = { from = src, chain = w.key, variant = w.letter, path = path, dt = DT, rest = rest }
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
            rot = type(rest) == 'table' and rest or nil, ownerSrc = src, thrown = true,
        })
    end)
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
