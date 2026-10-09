-- Destructible speakers: shoot, hit or ram a placed speaker and it breaks.
local RES = GetCurrentResourceName()
local lastHit = {}      -- src -> last damage time, stops one player spamming hits

local function isAdmin(src) return Bridge.IsAdmin(src) end

local function break_(e, src)
    e.health = 0
    local pos = EmitterPosition(e)
    TriggerClientEvent(RES .. ':client:broke', -1, e.id, pos)
    if e.vinyl then Vinyl.Return(e, e.vinyl.ownerSrc) end
    if e.group then Links.RemoveFrom(e) end

    local item = e.item
    local ownerSrc = e.ownerSrc
    RemoveEmitter(e)

    if Config.Damage.dropOnBreak and item then
        local to = ownerSrc and GetPlayerName(ownerSrc) and ownerSrc or nil
        if to then Bridge.AddItem(to, item) end
    end
    Log('Speaker destroyed', ('`%s` was destroyed%s'):format(e.id, src and (' by **' .. GetPlayerName(src) .. '**') or ''))
end

RegisterNetEvent(RES .. ':damage', function(id, kind)
    local src = source
    if not Config.Damage.enabled then return end
    local e = Emitters[id]
    if not e or e.kind ~= 'boombox' or e.state ~= 'placed' then return end

    local t = GetGameTimer()
    if lastHit[src] and t - lastHit[src] < Config.Damage.cooldown then return end
    lastHit[src] = t

    -- the hit has to be plausible: the player must be near the speaker
    local pos = EmitterPosition(e)
    local ped = GetPlayerPed(src)
    if not pos or ped == 0 then return end
    local d = #(GetEntityCoords(ped) - pos)
    local maxD = (kind == 'bullet' or kind == 'explosion') and 150.0 or 8.0
    if d > maxD then return end

    local dmg = Config.Damage[kind] or 0
    if dmg <= 0 then return end

    e.health = math.max(0, (e.health or Config.Damage.health) - dmg)
    if e.health <= 0 then return break_(e, src) end
    Broadcast(e)
    TriggerClientEvent(RES .. ':client:hit', -1, e.id, pos, e.health / Config.Damage.health)
end)

AddEventHandler('playerDropped', function() lastHit[source] = nil end)

-- repair with a command (admins) or by packing it up and placing it again
RegisterCommand('speakerrepair', function(src, args)
    if src ~= 0 and not isAdmin(src) then return Notify(src, 'no_permission') end
    local radius = tonumber(args[1]) or 20.0
    local origin = src ~= 0 and GetEntityCoords(GetPlayerPed(src)) or nil
    local n = 0
    for _, e in pairs(Emitters) do
        local pos = EmitterPosition(e)
        if e.kind == 'boombox' and pos and (not origin or #(origin - pos) <= radius) then
            if (e.health or 0) < Config.Damage.health then
                e.health = Config.Damage.health
                Broadcast(e)
                n = n + 1
            end
        end
    end
    if src ~= 0 then Notify(src, 'repaired', 'success', n) else print(('[speaker] repaired %d'):format(n)) end
end, false)

exports('DamageSpeaker', function(id, amount)
    local e = Emitters[id]
    if not e then return false end
    e.health = math.max(0, (e.health or Config.Damage.health) - (tonumber(amount) or 0))
    if e.health <= 0 then break_(e, nil) else Broadcast(e) end
    return true
end)
