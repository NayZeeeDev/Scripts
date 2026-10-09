--[[
    The pair on your feet gets dirty and wears down as you walk around.

    Every second: how far you moved, whether you're running, the rain, and
    (every other second) what's under your feet. Every Config.Dirt.Sync seconds
    the total goes to the server, which keeps the worn pair's metadata.
]]

Dirt = {}

local D = Config.Dirt

-- GTA material names, grouped (the hash under your feet is the joaat of the name)
local MATERIALS = {
    mud    = { 'MUD_HARD', 'MUD_SOFT', 'MUD_DEEP', 'MUD_POTHOLE', 'MUD_UNDERWATER', 'MARSH', 'MARSH_DEEP', 'CLAY_HARD', 'CLAY_SOFT', 'SOIL' },
    sand   = { 'SAND_LOOSE', 'SAND_COMPACT', 'SAND_WET', 'SAND_TRACK', 'SAND_UNDERWATER', 'SAND_DRY_DEEP', 'SAND_WET_DEEP' },
    dirt   = { 'DIRT_TRACK' },
    grass  = { 'GRASS', 'GRASS_LONG', 'GRASS_SHORT', 'HAY', 'LEAVES', 'TWIGS', 'BUSHES' },
    gravel = { 'GRAVEL_SMALL', 'GRAVEL_LARGE', 'GRAVEL_DEEP', 'GRAVEL_TRAIN_TRACK', 'ROCK', 'ROCK_MOSSY' },
}
local groundOf = {}
for group, names in pairs(MATERIALS) do
    for _, n in ipairs(names) do groundOf[GetHashKey(n) & 0xFFFFFFFF] = group end
end

local pending = { km = 0.0, dirt = 0.0, swam = false }
local syncing = false

--- Multiplier for what's under the ped
local function groundMult(ped)
    local pos = GetEntityCoords(ped)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z, pos.x, pos.y, pos.z - 2.0, 1, ped, 7)
    local _, hit, _, _, material = GetShapeTestResultIncludingMaterial(ray)
    if hit ~= 1 and hit ~= true then return 1.0 end
    local group = groundOf[material & 0xFFFFFFFF]
    return group and D.Ground[group] or 1.0
end

local THRESHOLDS = { 25, 50, 75 }

--- Send what's been collected. Safe to call any time (taking shoes off calls it first).
function Dirt.Flush()
    if syncing or not Shoes.worn or (pending.km <= 0 and pending.dirt <= 0) then return end
    syncing = true
    local send = pending
    pending = { km = 0.0, dirt = 0.0, swam = false }
    local res = lib.callback.await('nayzeee-sneakers:wearTick', false, send.km, send.dirt, send.swam)
    syncing = false
    if not res or not Shoes.worn then return end

    local before = tonumber(Shoes.worn.dirt) or 0
    Shoes.worn.dirt, Shoes.worn.km, Shoes.worn.condition = res.dirt, res.km, res.condition
    local name = Config.Shoes[Shoes.worn.shoe] and Config.Shoes[Shoes.worn.shoe].label or 'shoes'
    if res.changed then
        UI.Notify(Config.Text.wornDown:format(name, Shared.ConditionLabel(res.condition)), 'warning')
    else
        for _, t in ipairs(THRESHOLDS) do
            if before < t and res.dirt >= t then
                UI.Notify(Config.Text.gettingDirty:format(name, math.floor(res.dirt)), 'warning')
                break
            end
        end
    end
end

if D.Enabled then
    CreateThread(function()
        local last, wet, tick, ground = nil, false, 0, 1.0
        local lastSync = GetGameTimer()
        while true do
            Wait(1000)
            local ped = PlayerPedId()
            if not Shoes.worn or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
                last = nil
            else
                local pos = GetEntityCoords(ped)
                local moved = last and #(pos.xy - last.xy) or 0.0
                last = pos
                if moved > 25.0 then moved = 0.0 end          -- teleports and respawns don't count

                tick = tick + 1
                if tick % 2 == 0 then ground = groundMult(ped) end
                local mult = ground
                if IsPedSprinting(ped) or IsPedRunning(ped) then mult = mult * D.Sprint end
                if GetRainLevel() > 0.15 and GetInteriorFromEntity(ped) == 0 then mult = mult * D.Rain end

                local inWater = IsPedSwimming(ped) or IsEntityInWater(ped)
                if inWater and not wet then
                    pending.dirt = pending.dirt + D.Swim
                    pending.swam = true
                end
                wet = inWater

                pending.km = pending.km + moved / 1000.0
                pending.dirt = pending.dirt + moved / 1000.0 * D.PerKm * mult
            end
            if GetGameTimer() - lastSync >= D.Sync * 1000 then
                lastSync = GetGameTimer()
                CreateThread(Dirt.Flush)
            end
        end
    end)
end

-- /sneakerdirt and anything else that changes the worn pair on the server
RegisterNetEvent('nayzeee-sneakers:client:wornMeta', function(meta)
    if Shoes.worn then Shoes.worn = meta end
end)
