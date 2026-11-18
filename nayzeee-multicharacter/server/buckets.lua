if not NAYZEEE_LOCK_OK then return end

-- Private routing bucket per player while in the lobby (Config.Bucket). Bucket = base + server id.
Buckets = {}

local cfg = Config.Bucket
local inLobby = {}

function Buckets.Lobby(src)
    if not cfg.enabled then return end
    local b = cfg.base + src
    SetPlayerRoutingBucket(src, b)
    if cfg.noPopulation then SetRoutingBucketPopulationEnabled(b, false) end
    inLobby[src] = b
end

function Buckets.World(src)
    if not cfg.enabled then return end
    -- only move players we isolated (survives a resource restart: bucket id is deterministic)
    if GetPlayerName(src) and (inLobby[src] or GetPlayerRoutingBucket(src) == cfg.base + src) then
        SetPlayerRoutingBucket(src, 0)
    end
    inLobby[src] = nil
end

function Buckets.InLobby(src) return inLobby[src] ~= nil end

AddEventHandler('playerDropped', function()
    local src = source
    local b = inLobby[src]
    if b and cfg.noPopulation then SetRoutingBucketPopulationEnabled(b, true) end
    inLobby[src] = nil
end)
