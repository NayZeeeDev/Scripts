-- Destructible speakers: shoot, hit or ram a placed speaker and it breaks.
local lastHit = {}          -- src -> last damage time, stops one player spamming hits
local KINDS = { bullet = 150.0, explosion = 150.0, melee = 8.0, vehicle = 8.0 }   -- hit kind -> how far away it can come from
local UNARMED = joaat('WEAPON_UNARMED') & 0xFFFFFFFF

local function destroy(e, src)
    e.health = 0
    TriggerClientEvent(RES .. ':client:broke', -1, e.id, EmitterPosition(e))
    if e.vinyl then Vinyl.Return(e, e.vinyl.ownerSrc) end

    local item, ownerSrc = e.item, e.ownerSrc
    RemoveEmitter(e)
    if Config.Damage.dropOnBreak and item and ownerSrc and GetPlayerName(ownerSrc) then Bridge.GiveOrDrop(ownerSrc, item) end
    Log('Speaker destroyed', ('`%s` was destroyed%s'):format(e.id, src and (' by **' .. GetPlayerName(src) .. '**') or ''))
end

--[[
    Explosions the game really had: OneSync tells the server about every one (explosionEvent). A
    reported blast only counts when one went off right next to that speaker in the last moment, and
    each blast hurts a speaker once however many players saw it, so a made-up report breaks nothing.
]]
local BLAST_RADIUS, BLAST_MEMORY = 12.0, 3000
local blasts = {}           -- { pos, at, hit = { [speakerId] = true } }, newest last

AddEventHandler('explosionEvent', function(_, ev)
    local x, y, z = tonumber(ev and ev.posX), tonumber(ev and ev.posY), tonumber(ev and ev.posZ)
    if not x or not y or not z then return end
    local t = GetGameTimer()
    while blasts[1] and (t - blasts[1].at > BLAST_MEMORY or #blasts >= 64) do table.remove(blasts, 1) end
    blasts[#blasts + 1] = { pos = vector3(x, y, z), at = t, hit = {} }
end)

local function blastAt(e)
    local t = GetGameTimer()
    for i = #blasts, 1, -1 do
        local b = blasts[i]
        if t - b.at > BLAST_MEMORY then break end
        if not b.hit[e.id] and #(b.pos - e.coords) <= BLAST_RADIUS then
            b.hit[e.id] = true
            return true
        end
    end
    return false
end

-- the report could be true: a blast really went off there (the player who set it off may report
-- it a moment before the server hears of it), or the player has a gun out / is in a vehicle
local function plausible(src, ped, e, kind)
    if kind == 'explosion' then
        for _ = 1, 4 do
            if blastAt(e) then return true end
            Wait(250)
            if Emitters[e.id] ~= e then return false end
        end
        return false
    end
    if kind == 'bullet' then
        if GetVehiclePedIsIn(ped, false) ~= 0 then return true end
        local w = GetSelectedPedWeapon(ped)
        return w ~= nil and w ~= 0 and (w & 0xFFFFFFFF) ~= UNARMED
    end
    return true
end

local function hurt(e, dmg, src)
    e.health = math.max(0, (e.health or Config.Damage.health) - dmg)
    if e.health <= 0 then return destroy(e, src) end
    Broadcast(e)
    TriggerClientEvent(RES .. ':client:hit', -1, e.id, EmitterPosition(e), e.health / Config.Damage.health)
end

RegisterNetEvent(RES .. ':damage', function(id, kind)
    local src = source
    local reach = KINDS[kind]
    if not Config.Damage.enabled or not reach then return end
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' or e.spawning then return end

    local t = GetGameTimer()
    if lastHit[src] and t - lastHit[src] < Config.Damage.cooldown then return end
    lastHit[src] = t

    -- the hit has to be plausible: the player must be near the speaker, and what hit it must exist
    local ped = GetPlayerPed(src)
    if ped == 0 or not e.coords or not (#(GetEntityCoords(ped) - e.coords) <= reach) then return end
    if not plausible(src, ped, e, kind) then return end
    if Emitters[e.id] ~= e or e.state ~= 'placed' then return end      -- gone / picked up meanwhile

    local dmg = tonumber(Config.Damage[kind]) or 0
    if dmg > 0 then hurt(e, dmg, src) end
end)

AddEventHandler('playerDropped', function() lastHit[source] = nil end)

-- repair with a command (admins) or by packing it up and placing it again
RegisterCommand('speakerrepair', function(src, args)
    if not Bridge.IsAdmin(src) then return Notify(src, 'no_permission') end
    local radius = tonumber(args[1]) or 20.0
    local origin = src ~= 0 and GetEntityCoords(GetPlayerPed(src)) or nil
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        if e.kind == 'boombox' and pos and (not origin or #(origin - pos) <= radius) and (e.health or 0) < Config.Damage.health then
            e.health = Config.Damage.health
            Broadcast(e)
            n = n + 1
        end
    end
    if src ~= 0 then Notify(src, 'repaired', 'success', n) else print(('[speaker] repaired %d'):format(n)) end
end, false)

exports('DamageSpeaker', function(id, amount)
    local e = Emitters[id]
    if not e then return false end
    hurt(e, tonumber(amount) or 0, nil)
    return true
end)
