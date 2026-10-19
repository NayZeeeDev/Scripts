--[[
    NAYZEEE AMBULANCE - Client core: shared ped scan (NZA.Scan)

    NPC peds that carry NAYZEEE state (patient 'nza', transport 'nzaTr', IV stand 'nzaStand',
    first aid 'nzaFa', call NPC 'nzaNpc') are kept in one list, so the modules no longer walk
    the whole ped pool every second each. A state bag change adds the ped at once; a slow
    sweep, spread over several frames, picks up peds that streamed in with their state
    already set and drops the ones that are gone or no longer carry any of it.

      NZA.Scan.Peds() → { ped, ... }   tracked NPC peds that still exist (networked, not players)
      NZA.Scan.Track(ped)              add a ped right away (e.g. one this client just spawned)
      NZA.Scan.Near(pool) → { entity, ... }   'CPed' | 'CObject' | 'CVehicle' entities within 50 m of
                                        you, shared by every caller and refreshed every 2 s
                                        (callers check their own, shorter range on this list)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Scan = NZA.Scan or {}
local Scan = NZA.Scan

local KEYS = { 'nza', 'nzaTr', 'nzaStand', 'nzaFa', 'nzaNpc' }
local SWEEP_MS = 4000          -- full sweep of the ped pool
local SWEEP_RANGE = 180.0      -- peds further away are left to the state bag handlers
local SWEEP_SLICE = 48         -- peds checked per frame during a sweep

local NEAR_MS = 2000
local NEAR_RANGE = 50.0

local tracked = {}             -- [ped] = true
local near = {}                -- [pool] = { at, list }

local function hasState(ped)
    local st = Entity(ped).state
    for i = 1, #KEYS do
        if st[KEYS[i]] ~= nil then return true end
    end
    return false
end

function Scan.Track(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then tracked[ped] = true end
end

function Scan.Peds()
    local out = {}
    for ped in pairs(tracked) do
        if DoesEntityExist(ped) then out[#out + 1] = ped else tracked[ped] = nil end
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
        if value == nil or not bagName:find('^entity:') then return end
        local ent = GetEntityFromStateBagName(bagName)
        if ent ~= 0 then
            if IsEntityAPed(ent) then Scan.Track(ent) end
            return
        end
        -- not created on this client yet (the value can arrive just before the entity): look again for a
        -- few seconds; the sweep still catches anything later
        CreateThread(function()
            for _ = 1, 25 do
                Wait(200)
                local e = GetEntityFromStateBagName(bagName)
                if e ~= 0 then
                    if IsEntityAPed(e) then Scan.Track(e) end
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
        local peds = GetGamePool('CPed')
        for i = 1, #peds do
            local ped = peds[i]
            if not tracked[ped] and DoesEntityExist(ped) and not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped)
                and #(pos - GetEntityCoords(ped)) < range and hasState(ped) then
                tracked[ped] = true
            end
            if i % SWEEP_SLICE == 0 then Wait(0) end
        end
        for ped in pairs(tracked) do
            if not DoesEntityExist(ped) or not hasState(ped) then tracked[ped] = nil end
        end
        Wait(SWEEP_MS)
    end
end)
