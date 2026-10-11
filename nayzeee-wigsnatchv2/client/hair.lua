-- Applies the server's hair state on top of whatever the appearance script loaded:
-- wig / bald / haircut / dye on the hair, shaved eyebrows / beard on the face overlays,
-- and the burn / lice / dirt visuals on every ped that has them.
-- No loops while nothing is going on.

Hair = { state = nil, natural = nil, applied = nil }

local BROWS, BEARD = 2, 1

local function readHair(ped)
    return {
        d = GetPedDrawableVariation(ped, 2),
        t = GetPedTextureVariation(ped, 2),
        c = GetPedHairColor(ped),
        h = GetPedHairHighlightColor(ped),
        p = GetPedPaletteVariation(ped, 2),
    }
end
Hair.Read = readHair

local function same(a, b)
    return a and b and a.d == b.d and a.t == b.t
end

local tint = SetPedHairTint or SetPedHairColor   -- the native's current and old name

-- The hair's palette: the one your appearance script put on your own hair (ESX skinchanger uses 2,
-- most others 0). Custom hair, female packs especially, only colours right on the palette it was
-- made for and turns green on the other one. Config.HairPalette forces one.
local function paletteFor(h)
    if Config.HairPalette ~= nil then return Config.HairPalette end
    return h.p or (Hair.natural and Hair.natural.p) or 0
end
Hair.Palette = paletteFor

-- Putting hair on and colouring it. GTA drops a hair colour that's set while the hairstyle is still
-- streaming in, or while the head is being re-blended after the hair changed (that's what turned
-- heavier hair, female hair mostly, green: the colour never landed, while the game still reported
-- it as set). So: stream the hairstyle in first, set it, wait for the head blend, colour it, then
-- colour it again a few times over the next seconds no matter what the game says.
local hairToken, applying = 0, false
local function setHair(ped, h)
    applying = true
    hairToken = hairToken + 1
    local token = hairToken
    local d, t, pal = h.d, h.t or 0, paletteFor(h)
    local c, hl = h.c, h.h or h.c
    CreateThread(function()
        SetPedPreloadVariationData(ped, 2, d, t)
        local until_ = GetGameTimer() + 2000
        while not HasPedPreloadVariationDataFinished(ped) and GetGameTimer() < until_ do Wait(0) end
        if token ~= hairToken or not DoesEntityExist(ped) then
            if token == hairToken then applying = false end
            return ReleasePedPreloadVariationData(ped)
        end
        SetPedComponentVariation(ped, 2, d, t, pal)
        ReleasePedPreloadVariationData(ped)
        applying = false
        if not c then return end
        tint(ped, c, hl)
        until_ = GetGameTimer() + 2000
        while not HasPedHeadBlendFinished(ped) and GetGameTimer() < until_ do Wait(0) end
        for _, wait in ipairs({ 0, 100, 400, 1000, 2500 }) do
            Wait(wait)
            if token ~= hairToken or not DoesEntityExist(ped) then return end
            tint(ped, c, hl)
        end
    end)
end

-- /wighair: what the game says about your hair right now (for support)
RegisterCommand('wighair', function()
    local ped = PlayerPedId()
    local d = GetPedDrawableVariation(ped, 2)
    local ok, coll = pcall(GetPedCollectionNameFromDrawable, ped, 2, d)
    print(('[%s] hair: model %s · drawable %d (%s) · texture %d · palette %d · colour %d / highlight %d · head blend done: %s'):format(
        RESOURCE, ModelKey(GetEntityModel(ped)) or '?', d, ok and (coll == '' and 'base game' or tostring(coll)) or '?',
        GetPedTextureVariation(ped, 2), GetPedPaletteVariation(ped, 2), GetPedHairColor(ped), GetPedHairHighlightColor(ped),
        tostring(HasPedHeadBlendFinished(ped))))
    if Hair.applied then
        print(('[%s] this script put on: drawable %s · texture %s · colour %s / %s'):format(RESOURCE,
            tostring(Hair.applied.d), tostring(Hair.applied.t), tostring(Hair.applied.c), tostring(Hair.applied.h)))
    end
    CB.Notify('Hair info printed in F8', 'info')
end, false)

function Hair.MyModel()
    return ModelKey(GetEntityModel(PlayerPedId()))
end

-- Whatever the ped shows right now is the "natural" hair, unless it's what we applied.
local function capture(ped)
    if applying then return end   -- our own hair is still going on, what's there now isn't "natural"
    local cur = readHair(ped)
    if Hair.applied and same(cur, Hair.applied) then return end
    Hair.natural = cur
end

-- face overlays -----------------------------------------------------------------------------------

local face = { natural = {}, applied = {} }

local function readOverlay(ped, idx)
    local ok, value, ctype, c1, c2, opacity = GetPedHeadOverlayData(ped, idx)
    if not ok then return { v = GetPedHeadOverlayValue(ped, idx), o = 1.0, ct = 1, c1 = 0, c2 = 0 } end
    return { v = value, o = opacity, ct = ctype, c1 = c1, c2 = c2 }
end

local function applyOverlay(ped, idx, mode)
    local cur = readOverlay(ped, idx)
    local was = face.applied[idx]
    -- capture the real overlay unless it's the one we set
    if not was or cur.v ~= was.v or math.abs((cur.o or 0) - (was.o or 0)) > 0.01 then
        face.natural[idx] = cur
    end
    local nat = face.natural[idx] or cur
    if mode == 'gone' then
        SetPedHeadOverlay(ped, idx, 255, 0.0)
        face.applied[idx] = { v = 255, o = 0.0 }
    elseif (mode == 'thin' or mode == 'trim') and nat.v ~= 255 then
        local o = math.min(nat.o or 1.0, Config.Cutting.Face.ThinOpacity)
        SetPedHeadOverlay(ped, idx, nat.v, o)
        face.applied[idx] = { v = nat.v, o = o }
    elseif was then
        -- back to normal
        if nat.v ~= 255 then
            SetPedHeadOverlay(ped, idx, nat.v, nat.o or 1.0)
            SetPedHeadOverlayColor(ped, idx, nat.ct or 1, nat.c1 or 0, nat.c2 or 0)
        end
        face.applied[idx] = nil
    end
end

local function applyFace(ped, s)
    local f = s.face or {}
    applyOverlay(ped, BROWS, f.brows)
    applyOverlay(ped, BEARD, f.beard)
end

-- hair ------------------------------------------------------------------------------------------------

function Hair.Apply()
    local s = Hair.state
    if not s then return end
    local ped = PlayerPedId()
    local m = ModelKey(GetEntityModel(ped))
    if not m then return end
    capture(ped)
    local nat = Hair.natural or readHair(ped)

    local target
    local wearing = s.wig and s.wig.hair and s.wig.hair.m == m
    if wearing then
        local w = s.wig.hair
        target = { d = w.d, t = w.t, c = w.c, h = w.h }
    elseif s.bald then
        target = { d = s.bald.d, t = s.bald.t }
    elseif s.cut and (s.cut.m == nil or s.cut.m == m) then
        target = { d = s.cut.d, t = s.cut.t or 0, c = nat.c, h = nat.h }
    end

    -- colour layers on your own hair (a wig keeps its own colour)
    if not wearing then
        if s.dye then
            target = target or { d = nat.d, t = nat.t }
            target.c, target.h = s.dye.c, s.dye.h
        end
        if s.status and s.status.burn then
            local bc = Config.Products.Status.burn.HairColor
            if bc then
                target = target or { d = nat.d, t = nat.t }
                target.c, target.h = bc[1], bc[2]
            end
        end
    end

    if target then
        setHair(ped, target)
        Hair.applied = target
    else
        if Hair.applied then setHair(ped, nat) end
        Hair.applied = nil
    end
    applyFace(ped, s)
end

function Hair.Visible()
    local s = Hair.state
    if not s then return 'natural' end
    if s.wig then return 'wig' end
    if s.bald then return 'bald' end
    return 'natural'
end

local selfStatus = {}

RegisterNetEvent('nz-wig:c:hair', function(state, reason)
    Hair.state = state
    Hair.Apply()
    Hair.SelfStatus(state.status or {})
    if reason ~= 'load' then TriggerEvent('nz-wig:hairChanged', state, reason) end
    if NUI.app == 'vault' then TriggerEvent('nz-wig:c:refresh') end
end)

-- server asks what our hair / face looks like right now
RegisterNetEvent('nz-wig:c:query', function(token)
    local ped = PlayerPedId()
    local h = readHair(ped)
    h.bv = GetPedHeadOverlayValue(ped, BROWS)
    h.fv = GetPedHeadOverlayValue(ped, BEARD)
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
        face.applied = {}
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

-- skinchanger (ESX) and other appearance scripts load a saved skin with these local events,
-- which puts the saved hair (and colour) back over a wig or dye
for _, ev in ipairs({ 'skinchanger:loadSkin', 'skinchanger:loadClothes' }) do
    AddEventHandler(ev, function() Hair.Reapply(600) end)
end

exports('ReapplyHair', function() Hair.Reapply(100) end)
exports('GetHairState', function() return Hair.state end)

-- statuses on yourself: itching from lice, washing mud off in the water ------------------------------------

local selfToken = 0
function Hair.SelfStatus(status)
    selfStatus = status
    selfToken = selfToken + 1
    local token = selfToken
    local CS = Config.Products.Status

    if status.lice and CS.lice and (CS.lice.ItchEvery or 0) > 0 then
        CreateThread(function()
            while selfToken == token do
                Wait(CS.lice.ItchEvery * 1000)
                if selfToken ~= token then break end
                Reaction('lice')
            end
        end)
    end
    if status.dirt and CS.dirt and CS.dirt.WaterCleans then
        CreateThread(function()
            while selfToken == token do
                local ped = PlayerPedId()
                if IsEntityInWater(ped) or IsPedSwimming(ped) then
                    TriggerServerEvent('nz-wig:s:washed')
                    break
                end
                Wait(1000)
            end
        end)
    end
end

-- status visuals on every ped (statebag driven) --------------------------------------------------------------

local fx = {} -- [serverId] = { ped, kinds = {}, ptfx = { kind = handle } }

local function stopFx(e)
    for _, h in pairs(e.ptfx or {}) do
        if h and DoesParticleFxLoopedExist(h) then StopParticleFxLooped(h, false) end
    end
    e.ptfx = {}
end

local function clearVisuals(ped)
    if ped == 0 or not DoesEntityExist(ped) then return end
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedEnvDirt(ped)
end

local function startPtfx(ped, p)
    if not p or not p.asset then return nil end
    if not pcall(lib.requestNamedPtfxAsset, p.asset, 1500) then return nil end
    UseParticleFxAssetNextCall(p.asset)
    local h = StartParticleFxLoopedOnPedBone(p.name, ped, 0.0, 0.0, 0.12, 0.0, 0.0, 0.0, GetPedBoneIndex(ped, 31086), p.scale or 0.5, false, false, false)
    return h ~= 0 and h or nil
end

local function applyFx(sid, kinds)
    local e = fx[sid]
    local ped = PedOf(sid)
    if e then
        stopFx(e)
        if e.ped and e.ped ~= 0 then clearVisuals(e.ped) end
    end
    if not kinds or next(kinds) == nil then fx[sid] = nil return end
    e = { ped = ped, kinds = kinds, ptfx = {} }
    fx[sid] = e
    if ped == 0 or not DoesEntityExist(ped) then return end -- out of scope, picked up when they appear

    local CS = Config.Products.Status
    for kind in pairs(kinds) do
        local s = CS[kind]
        if s then
            if s.DamagePack then ApplyPedDamagePack(ped, s.DamagePack, 0.0, 1.0) end
            if s.Particle then e.ptfx[kind] = startPtfx(ped, s.Particle) end
        end
    end
end

AddStateBagChangeHandler(ST.fx, nil, function(bagName, _, value)
    local sid = tonumber(bagName:match('^player:(%d+)$'))
    if not sid then return end
    -- the handler runs before the value is stored, apply on the next tick
    SetTimeout(0, function() applyFx(sid, value) end)
end)

-- peds stream in and out (and respawn), so keep visuals attached to the right ped while anyone has a status
CreateThread(function()
    while true do
        Wait(next(fx) and 2000 or 5000)
        local seen = {}
        for _, pl in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(pl)
            seen[sid] = true
            local kinds = Player(sid).state[ST.fx]
            local e = fx[sid]
            if kinds and (not e or e.ped ~= GetPlayerPed(pl)) then
                applyFx(sid, kinds)
            elseif not kinds and e then
                applyFx(sid, nil)
            end
        end
        for sid, e in pairs(fx) do
            if not seen[sid] then stopFx(e) fx[sid] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    for _, e in pairs(fx) do
        stopFx(e)
        clearVisuals(e.ped)
    end
end)
