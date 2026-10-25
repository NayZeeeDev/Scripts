-----------------------------------------------------------------
-- Bag sounds (server)
--
-- Sends a sound to the players close enough to hear it. Clients do
-- the volume / left-right from their own camera.
-----------------------------------------------------------------

Sounds = {}

local cfg = Config.Sounds or {}
local RANGE = cfg.range or 12.0

--- Play `name` at a player (src) or at coords, optionally after `delay` ms.
function Sounds.play(name, at, delay)
    if not cfg.enabled or (cfg.levels and cfg.levels[name] == 0) then return end
    if delay and delay > 0 then
        return SetTimeout(delay, function() Sounds.play(name, at) end)
    end

    local coords = at
    if type(at) == 'number' then
        local ped = GetPlayerPed(at)
        if ped == 0 then return end
        coords = GetEntityCoords(ped)
    end
    if not coords then return end

    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - coords) <= RANGE then
            TriggerClientEvent('nayzeee-backpack:sound', tonumber(id), name, coords)
        end
    end
end

-- A few sounds the client may ask for at its own position (menus the
-- server never sees open). Rate-limited.
local ASKABLE = { zip_open = true, zip_close = true, rustle = true }
local lastAsk = {}

RegisterNetEvent('nayzeee-backpack:sound:ask', function(name)
    local src = source
    if not ASKABLE[name] then return end
    local now = GetGameTimer()
    if lastAsk[src] and now - lastAsk[src] < 400 then return end
    lastAsk[src] = now
    Sounds.play(name, src)
end)

AddEventHandler('playerDropped', function() lastAsk[source] = nil end)
