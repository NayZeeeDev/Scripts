-- Applies the server's hair state on top of whatever the appearance script loaded.
-- No loops: it only runs when the state changes or a skin reload happens.

Hair = { state = nil, natural = nil, applied = nil }

local function readHair(ped)
    return {
        d = GetPedDrawableVariation(ped, 2),
        t = GetPedTextureVariation(ped, 2),
        c = GetPedHairColor(ped),
        h = GetPedHairHighlightColor(ped),
    }
end
Hair.Read = readHair

local function same(a, b)
    return a and b and a.d == b.d and a.t == b.t
end

local function setHair(ped, h)
    SetPedComponentVariation(ped, 2, h.d, h.t or 0, 0)
    if h.c then SetPedHairColor(ped, h.c, h.h or h.c) end
end

function Hair.MyModel()
    return ModelKey(GetEntityModel(PlayerPedId()))
end

-- Whatever the ped shows right now is the "natural" hair, unless it's what we applied.
local function capture(ped)
    local cur = readHair(ped)
    if Hair.applied and same(cur, Hair.applied) then return end
    Hair.natural = cur
end

function Hair.Apply()
    local s = Hair.state
    if not s then return end
    local ped = PlayerPedId()
    local m = ModelKey(GetEntityModel(ped))
    if not m then return end
    capture(ped)
    local nat = Hair.natural or readHair(ped)

    local target
    if s.wig and s.wig.hair and s.wig.hair.m == m then
        local w = s.wig.hair
        target = { d = w.d, t = w.t, c = w.c, h = w.h }
    elseif s.bald then
        target = { d = s.bald.d, t = s.bald.t }
    elseif s.cut and (s.cut.m == nil or s.cut.m == m) then
        target = { d = s.cut.d, t = s.cut.t or 0, c = nat.c, h = nat.h }
    end

    if target then
        setHair(ped, target)
        Hair.applied = target
    else
        if Hair.applied then setHair(ped, nat) end
        Hair.applied = nil
    end
end

function Hair.Visible()
    local s = Hair.state
    if not s then return 'natural' end
    if s.wig then return 'wig' end
    if s.bald then return 'bald' end
    return 'natural'
end

RegisterNetEvent('nz-wig:c:hair', function(state, reason)
    Hair.state = state
    Hair.Apply()
    if reason ~= 'load' then TriggerEvent('nz-wig:hairChanged', state, reason) end
    if NUI.app == 'vault' then TriggerEvent('nz-wig:c:refresh') end
end)

-- server asks what our hair looks like right now
RegisterNetEvent('nz-wig:c:query', function(token)
    local ped = PlayerPedId()
    local h = readHair(ped)
    h.restrained = CB.IsRestrained(ped)
    h.handsUp = CB.HandsUp(ped)
    h.downed = CB.IsDowned(ped)
    TriggerServerEvent('nz-wig:s:queryReply', token, h)
end)

-- appearance scripts reload the whole skin, put our layer back on afterwards
local reloadPending = false
function Hair.Reapply(delay)
    if reloadPending then return end
    reloadPending = true
    SetTimeout(delay or 1500, function()
        reloadPending = false
        Hair.Apply()
    end)
end

for _, ev in ipairs({
    'skinchanger:modelLoaded',
    'esx_skin:playerRegistered',
    'qb-clothing:client:loadPlayerClothing',
    'illenium-appearance:client:reloadSkin',
    'fivem-appearance:client:reloadSkin',
    'nayzeee-appearance:client:reloadSkin',
}) do
    RegisterNetEvent(ev, function() Hair.Reapply(1500) end)
end

exports('ReapplyHair', function() Hair.Reapply(100) end)
exports('GetHairState', function() return Hair.state end)
