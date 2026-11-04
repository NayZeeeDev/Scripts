--[[
    NAYZEEE AMBULANCE - Client core: shared ped scan (NZA.Scan)

    NPC peds that carry NAYZEEE state (patient 'nza', transport 'nzaTr', IV stand 'nzaStand',
    first aid 'nzaFa', call NPC 'nzaNpc') are kept in one list, so the modules no longer walk
    the whole ped pool every second each. A state bag change adds the ped at once; a slow
    sweep, spread over several frames, picks up peds that streamed in with their state
    already set and drops the ones that are gone or no longer carry any of it.

    Reading a state bag unpacks the whole value every time, and several modules read the same
    bags of the same NPC patients every second. For tracked peds the values of those five keys
    are kept here: the state bag change handlers write each new value as it arrives and the
    sweep re-reads them every few seconds as a safety net.

      NZA.Scan.Peds() → { ped, ... }   tracked NPC peds that still exist (networked, not players)
      NZA.Scan.Track(ped)              add a ped right away (e.g. one this client just spawned)
      NZA.Scan.State(ped, key) → value one of the keys above, from the cache for tracked peds
                                        (READ ONLY: the table is shared, never change it); any
                                        other key or ped is read from the state bag directly
      NZA.Scan.Near(pool) → { entity, ... }   'CPed' | 'CObject' | 'CVehicle' entities within 50 m of
                                        you, shared by every caller and refreshed every 2 s
                                        (callers check their own, shorter range on this list)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Scan = NZA.Scan or {}
local Scan = NZA.Scan

local KEYS = { 'nza', 'nzaTr', 'nzaStand', 'nzaFa', 'nzaNpc' }
local CACHED = {}
for _, k in ipairs(KEYS) do CACHED[k] = true end

local SWEEP_MS = 4000          -- full sweep of the ped pool
local SWEEP_RANGE = 180.0      -- peds further away are left to the state bag handlers
local SWEEP_SLICE = 48         -- peds looked at per frame during a sweep
local SWEEP_READS = 8          -- of those, peds whose state bags are read per frame
local RECHECK_MS = 12000       -- an untracked ped that had no NAYZEEE state is read again after this long
                               -- (a value set later reaches the change handlers anyway)

local NEAR_MS = 2000
local NEAR_RANGE = 50.0

local tracked = {}             -- [ped] = true
local cache = {}               -- [ped] = { [key] = value | NONE }   tracked peds only
local NONE = {}                -- cached "no value"
local quiet = {}               -- [ped] = game time it was last read without any NAYZEEE state
local near = {}                -- [pool] = { at, list }

local function untrack(ped)
    tracked[ped] = nil
    cache[ped] = nil
end

function Scan.State(ped, key)
    if not tracked[ped] or not CACHED[key] then
        if not ped or ped == 0 then return nil end
        return Entity(ped).state[key]
    end
    local c = cache[ped]
    if not c then
        c = {}
        cache[ped] = c
    end
    local v = c[key]
    if v == nil then
        v = Entity(ped).state[key]
        c[key] = v == nil and NONE or v
        return v
    end
    if v == NONE then return nil end
    return v
end

local function hasState(ped)
    if tracked[ped] then
        for i = 1, #KEYS do
            if Scan.State(ped, KEYS[i]) ~= nil then return true end
        end
        return false
    end
    local st = Entity(ped).state
    for i = 1, #KEYS do
        if st[KEYS[i]] ~= nil then return true end
    end
    return false
end

function Scan.Track(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
        tracked[ped] = true
        quiet[ped] = nil
    end
end

function Scan.Peds()
    local out = {}
    for ped in pairs(tracked) do
        if DoesEntityExist(ped) then out[#out + 1] = ped else untrack(ped) end
    end
    return out
end

function Scan.Near(pool)
    local c = near[pool]
    local now = GetGameTimer()
    if not c or now - c.at > NEAR_MS then
        local pos = GetEntityCoords(PlayerPedId())
        local out = {}
        for _, e in ipairs(GetGamePool(pool)) do
            if #(pos - GetEntityCoords(e)) < NEAR_RANGE then out[#out + 1] = e end
        end
        c = { at = now, list = out }
        near[pool] = c
    end
    return c.list
end

for _, key in ipairs(KEYS) do
    AddStateBagChangeHandler(key, nil, function(bagName, _, value)
        if not bagName:find('^entity:') then return end
        local ent = GetEntityFromStateBagName(bagName)
        if ent ~= 0 then
            if value ~= nil and not tracked[ent] and IsEntityAPed(ent) then Scan.Track(ent) end
            -- the handler runs before the bag holds the new value: keep the new one
            if tracked[ent] then
                local c = cache[ent]
                if not c then
                    c = {}
                    cache[ent] = c
                end
                c[key] = value == nil and NONE or value
            end
            return
        end
        if value == nil then return end
        -- not created on this client yet (the value can arrive just before the entity): look again for a
        -- few seconds; the sweep still catches anything later
        CreateThread(function()
            for _ = 1, 25 do
                Wait(200)
                local e = GetEntityFromStateBagName(bagName)
                if e ~= 0 then
                    if IsEntityAPed(e) then
                        cache[e] = nil   -- read fresh from the bag
                        Scan.Track(e)
                    end
                    return
                end
            end
        end)
    end)
end

CreateThread(function()
    Wait(1500)
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        -- far enough for the NPC-call upkeep radius (Config.Calls.npc.radius) when that is set higher
        local npcR = tonumber((Config.Calls and Config.Calls.npc or {}).radius) or 0.0
        local range = math.max(SWEEP_RANGE, npcR + 10.0)
        local now = GetGameTimer()
        local peds = GetGamePool('CPed')
        local nextQuiet = {}
        local reads = 0
        for i = 1, #peds do
            local ped = peds[i]
            if not tracked[ped] then
                local q = quiet[ped]
                if q and now - q < RECHECK_MS then
                    nextQuiet[ped] = q
                elseif DoesEntityExist(ped) and NetworkGetEntityIsNetworked(ped) and not IsPedAPlayer(ped)
                    and #(pos - GetEntityCoords(ped)) < range then
                    reads = reads + 1
                    if hasState(ped) then
                        tracked[ped] = true
                    else
                        nextQuiet[ped] = now
                    end
                    if reads % SWEEP_READS == 0 then Wait(0) end
                end
            end
            if i % SWEEP_SLICE == 0 then Wait(0) end
        end
        quiet = nextQuiet
        for ped in pairs(tracked) do
            cache[ped] = nil   -- re-read once per sweep: a safety net for a change this client missed
            if not DoesEntityExist(ped) or not hasState(ped) then untrack(ped) end
        end
        Wait(SWEEP_MS)
    end
end)
