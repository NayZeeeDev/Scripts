-- Destructible speakers: shoot, hit or ram a placed speaker and it breaks.
local lastHit = {}          -- src -> last damage time, stops one player spamming hits
local KINDS = { bullet = 150.0, explosion = 150.0, melee = 8.0, vehicle = 8.0 }   -- hit kind -> how far away it can come from

local function destroy(e, src)
    e.health = 0
    TriggerClientEvent(RES .. ':client:broke', -1, e.id, EmitterPosition(e))
    if e.vinyl then Vinyl.Return(e, e.vinyl.ownerSrc) end

    local item, ownerSrc = e.item, e.ownerSrc
    RemoveEmitter(e)
    if Config.Damage.dropOnBreak and item and ownerSrc and GetPlayerName(ownerSrc) then Bridge.AddItem(ownerSrc, item) end
    Log('Speaker destroyed', ('`%s` was destroyed%s'):format(e.id, src and (' by **' .. GetPlayerName(src) .. '**') or ''))
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
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' then return end

    local t = GetGameTimer()
    if lastHit[src] and t - lastHit[src] < Config.Damage.cooldown then return end
    lastHit[src] = t

    -- the hit has to be plausible: the player must be near the speaker
    local ped = GetPlayerPed(src)
    if ped == 0 or not e.coords or not (#(GetEntityCoords(ped) - e.coords) <= reach) then return end

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
