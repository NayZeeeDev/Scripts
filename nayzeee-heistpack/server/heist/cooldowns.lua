--[[ Cooldowns: global (per heist), per location, per player. Optional KVP persistence across restarts. ]]

Cooldowns = { heist = {}, location = {}, player = {} }

local KVP = 'nzh_cooldowns'

local function save()
    if not ServerConfig.PersistCooldowns then return end
    SetResourceKvp(KVP, json.encode(Cooldowns))
end

CreateThread(function()
    if not ServerConfig.PersistCooldowns then return end
    local raw = GetResourceKvpString(KVP)
    if not raw then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
        local now = os.time()
        for _, bucket in ipairs({ 'heist', 'location', 'player' }) do
            for k, v in pairs(data[bucket] or {}) do
                if v > now then Cooldowns[bucket][k] = v end
            end
        end
    end
end)

local function remaining(bucket, key)
    local t = Cooldowns[bucket][key]
    if not t then return 0 end
    local r = t - os.time()
    if r <= 0 then Cooldowns[bucket][key] = nil return 0 end
    return r
end

function Cooldowns.heistRemaining(id) return remaining('heist', id) end
function Cooldowns.locationRemaining(id, idx) return remaining('location', id .. ':' .. idx) end
function Cooldowns.playerRemaining(identifier) return remaining('player', identifier) end

function Cooldowns.setHeist(id, minutes)
    if minutes and minutes > 0 then Cooldowns.heist[id] = os.time() + math.floor(minutes * 60) save() end
end

function Cooldowns.setLocation(id, idx, minutes)
    if minutes and minutes > 0 then Cooldowns.location[id .. ':' .. idx] = os.time() + math.floor(minutes * 60) save() end
end

function Cooldowns.setPlayer(identifier, minutes)
    if minutes and minutes > 0 then Cooldowns.player[identifier] = os.time() + math.floor(minutes * 60) save() end
end

function Cooldowns.reset(kind)
    if kind == nil or kind == 'all' then
        Cooldowns.heist, Cooldowns.location, Cooldowns.player = {}, {}, {}
    elseif Cooldowns[kind] then
        Cooldowns[kind] = {}
    end
    save()
end
