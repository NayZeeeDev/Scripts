if not NAYZEEE_LOCK_OK then return end

--[[
    Appearance bridge.
      Appearance.ApplyPed(ped, skin)        dress any ped (lineup peds, partner) - auto-detects the skin format
      Appearance.ApplyPlayer(skin, model)   dress the player ped before spawning
      Appearance.OpenEditor(isNew, done)    open the clothing / creator menu for a brand new character

    Skin formats handled natively (no export needed):
      illenium-appearance / fivem-appearance / nayzeee-appearance  (components, props, headBlend ...)
      skinchanger / esx_skin                                         (tshirt_1, torso_1 ...)
      qb-clothing                                                    (via its own loadPlayerClothing event)
]]

Appearance = {}

local function started(res) return GetResourceState(res) == 'started' end

-- The illenium-style resource running on this server, if any
local ILLENIUM = nil
for _, r in ipairs({ 'nayzeee-appearance', 'illenium-appearance', 'fivem-appearance' }) do
    if GetResourceState(r) ~= 'missing' then ILLENIUM = r break end
end

-- ── format detection ──────────────────────────────────────────────────────
local function formatOf(skin)
    if type(skin) ~= 'table' then return nil end
    if skin.components or skin.headBlend or skin.props then return 'illenium' end
    if skin.tshirt_1 or skin.torso_1 or skin.sex ~= nil then return 'skinchanger' end
    if skin.pants or skin.torso2 or skin['t-shirt'] then return 'qb' end
    return nil
end
Appearance.FormatOf = formatOf

-- ── illenium format (native) ──────────────────────────────────────────────
local FACE = { 'noseWidth', 'nosePeakHigh', 'nosePeakSize', 'noseBoneHigh', 'nosePeakLowering', 'noseBoneTwist', 'eyeBrownHigh',
    'eyeBrownForward', 'cheeksBoneHigh', 'cheeksBoneWidth', 'cheeksWidth', 'eyesOpening', 'lipsThickness', 'jawBoneWidth',
    'jawBoneBackSize', 'chinBoneLowering', 'chinBoneLenght', 'chinBoneSize', 'chinHole', 'neckThickness' }
local OVERLAYS = { blemishes = 0, beard = 1, eyebrows = 2, ageing = 3, makeUp = 4, blush = 5, complexion = 6, sunDamage = 7,
    lipstick = 8, moleAndFreckles = 9, chestHair = 10, bodyBlemishes = 11 }
local OVERLAY_COLOR = { beard = 1, eyebrows = 1, chestHair = 1, makeUp = 2, blush = 2, lipstick = 2 }

local function applyIllenium(ped, s)
    local hb = s.headBlend
    if hb then
        SetPedHeadBlendData(ped, hb.shapeFirst or 0, hb.shapeSecond or 0, hb.shapeThird or 0, hb.skinFirst or 0, hb.skinSecond or 0, hb.skinThird or 0,
            (hb.shapeMix or 0) + 0.0, (hb.skinMix or 0) + 0.0, (hb.thirdMix or 0) + 0.0, false)
    end
    if s.faceFeatures then
        for i, k in ipairs(FACE) do
            local v = s.faceFeatures[k]
            if v then SetPedFaceFeature(ped, i - 1, v + 0.0) end
        end
    end
    if s.headOverlays then
        for k, o in pairs(s.headOverlays) do
            local idx = OVERLAYS[k]
            if idx and type(o) == 'table' then
                SetPedHeadOverlay(ped, idx, o.style or 0, (o.opacity or 0) + 0.0)
                if OVERLAY_COLOR[k] then SetPedHeadOverlayColor(ped, idx, OVERLAY_COLOR[k], o.color or 0, o.secondColor or 0) end
            end
        end
    end
    for _, c in ipairs(s.components or {}) do
        if c.component_id and c.component_id ~= 2 then SetPedComponentVariation(ped, c.component_id, c.drawable or 0, c.texture or 0, 0) end
    end
    ClearAllPedProps(ped)
    for _, p in ipairs(s.props or {}) do
        if p.prop_id then
            if (p.drawable or -1) < 0 then ClearPedProp(ped, p.prop_id)
            else SetPedPropIndex(ped, p.prop_id, p.drawable, p.texture or 0, true) end
        end
    end
    if s.hair then
        SetPedComponentVariation(ped, 2, s.hair.style or 0, s.hair.texture or 0, 0)
        SetPedHairColor(ped, s.hair.color or 0, s.hair.highlight or 0)
    end
    if s.eyeColor then SetPedEyeColor(ped, s.eyeColor) end
    if type(s.tattoos) == 'table' then
        ClearPedDecorations(ped)
        local male = GetEntityModel(ped) == `mp_m_freemode_01`
        for _, zone in pairs(s.tattoos) do
            for _, t in ipairs(type(zone) == 'table' and zone or {}) do
                local hash = male and t.hashMale or t.hashFemale
                if t.collection and hash and hash ~= '' then AddPedDecorationFromHashes(ped, joaat(t.collection), joaat(hash)) end
            end
        end
    end
end

-- ── skinchanger format (native) ───────────────────────────────────────────
local function n(v, d) return tonumber(v) or d or 0 end

local function applySkinchanger(ped, s)
    SetPedHeadBlendData(ped, n(s.mom, 21), n(s.dad), 0, n(s.mom, 21), n(s.dad), 0, n(s.face_md_weight, 50) / 100 + 0.0, n(s.skin_md_weight, 50) / 100 + 0.0, 0.0, false)
    local feat = { 'nose_1', 'nose_2', 'nose_3', 'nose_4', 'nose_5', 'nose_6', 'eyebrows_5', 'eyebrows_6', 'cheeks_1', 'cheeks_2', 'cheeks_3',
        'eye_squint', 'lip_thickness', 'jaw_1', 'jaw_2', 'chin_1', 'chin_2', 'chin_3', 'chin_4', 'neck_thickness' }
    for i, k in ipairs(feat) do SetPedFaceFeature(ped, i - 1, n(s[k]) / 10 + 0.0) end
    SetPedEyeColor(ped, n(s.eye_color))

    local ov = { { 'blemishes_1', 'blemishes_2' }, { 'beard_1', 'beard_2' }, { 'eyebrows_1', 'eyebrows_2' }, { 'age_1', 'age_2' },
        { 'makeup_1', 'makeup_2' }, { 'blush_1', 'blush_2' }, { 'complexion_1', 'complexion_2' }, { 'sun_1', 'sun_2' },
        { 'lipstick_1', 'lipstick_2' }, { 'moles_1', 'moles_2' }, { 'chest_1', 'chest_2' } }
    for i, o in ipairs(ov) do SetPedHeadOverlay(ped, i - 1, n(s[o[1]]), n(s[o[2]]) / 10 + 0.0) end
    SetPedHeadOverlayColor(ped, 1, 1, n(s.beard_3), n(s.beard_4))
    SetPedHeadOverlayColor(ped, 2, 1, n(s.eyebrows_3), n(s.eyebrows_4))
    SetPedHeadOverlayColor(ped, 4, 2, n(s.makeup_3), n(s.makeup_4))
    SetPedHeadOverlayColor(ped, 5, 2, n(s.blush_3), 0)
    SetPedHeadOverlayColor(ped, 8, 2, n(s.lipstick_3), n(s.lipstick_4))
    SetPedHeadOverlayColor(ped, 10, 1, n(s.chest_3), 0)
    local bb1, bb3 = n(s.bodyb_1, -1), n(s.bodyb_3, -1)
    SetPedHeadOverlay(ped, 11, bb1 == -1 and 255 or bb1, n(s.bodyb_2) / 10 + 0.0)
    SetPedHeadOverlay(ped, 12, bb3 == -1 and 255 or bb3, n(s.bodyb_4) / 10 + 0.0)

    SetPedComponentVariation(ped, 2, n(s.hair_1), n(s.hair_2), 2)
    SetPedHairColor(ped, n(s.hair_color_1), n(s.hair_color_2))

    local comps = { { 'tshirt_1', 'tshirt_2', 8 }, { 'torso_1', 'torso_2', 11 }, { 'decals_1', 'decals_2', 10 }, { 'arms', 'arms_2', 3 },
        { 'pants_1', 'pants_2', 4 }, { 'shoes_1', 'shoes_2', 6 }, { 'mask_1', 'mask_2', 1 }, { 'bproof_1', 'bproof_2', 9 },
        { 'chain_1', 'chain_2', 7 }, { 'bags_1', 'bags_2', 5 } }
    for _, c in ipairs(comps) do SetPedComponentVariation(ped, c[3], n(s[c[1]]), n(s[c[2]]), 2) end

    local props = { { 'helmet_1', 'helmet_2', 0 }, { 'glasses_1', 'glasses_2', 1 }, { 'ears_1', 'ears_2', 2 }, { 'watches_1', 'watches_2', 6 }, { 'bracelets_1', 'bracelets_2', 7 } }
    for _, p in ipairs(props) do
        local d = n(s[p[1]], -1)
        if d == -1 then ClearPedProp(ped, p[3]) else SetPedPropIndex(ped, p[3], d, n(s[p[2]]), true) end
    end
end

-- ── public ────────────────────────────────────────────────────────────────
-- Model hash for a skin (string name, number or numeric string)
function Appearance.Model(model, gender)
    if type(model) == 'string' then model = tonumber(model) or joaat(model) end
    if type(model) ~= 'number' or model == 0 or not IsModelInCdimage(model) then
        model = gender == 'f' and `mp_f_freemode_01` or `mp_m_freemode_01`
    end
    return model
end

function Appearance.ApplyPed(ped, skin)
    if not skin or not DoesEntityExist(ped) then return end
    local fmt = formatOf(skin)
    if fmt == 'illenium' then
        if ILLENIUM and started(ILLENIUM) then
            local copy = {}
            for k, v in pairs(skin) do if k ~= 'model' then copy[k] = v end end
            if pcall(function() exports[ILLENIUM]:setPedAppearance(ped, copy) end) then return end
        end
        applyIllenium(ped, skin)
    elseif fmt == 'skinchanger' then
        applySkinchanger(ped, skin)
    elseif fmt == 'qb' and started('qb-clothing') then
        TriggerEvent('qb-clothing:client:loadPlayerClothing', skin, ped)
    end
end

-- Dress the player before they enter the world
function Appearance.ApplyPlayer(skin, model, gender)
    local hash = Appearance.Model(model, gender)
    lib.requestModel(hash, 10000)
    if GetEntityModel(PlayerPedId()) ~= hash then
        SetPlayerModel(PlayerId(), hash)
        SetPedDefaultComponentVariation(PlayerPedId())
    end
    SetModelAsNoLongerNeeded(hash)
    if not skin then return end

    local fmt = formatOf(skin)
    if fmt == 'illenium' and ILLENIUM and started(ILLENIUM) then
        local ok = pcall(function() exports[ILLENIUM]:setPlayerAppearance(skin) end)
        if ok then return end
    end
    if fmt == 'skinchanger' and started('skinchanger') then
        TriggerEvent('skinchanger:loadSkin', skin)
        return
    end
    Appearance.ApplyPed(PlayerPedId(), skin)
end

-- Open the appearance editor for a new character. done() must be called once it closes.
function Appearance.OpenEditor(isNew, gender, done)
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    ResetEntityAlpha(ped)
    SetPedAoBlobRendering(ped, true)

    if ILLENIUM and started(ILLENIUM) then
        local cfg = { ped = true, headBlend = true, faceFeatures = true, headOverlays = true, components = true, props = true, tattoos = true, enableExit = false }
        local ok = pcall(function()
            exports[ILLENIUM]:startPlayerCustomization(function(appearance)
                if appearance then
                    if ILLENIUM == 'fivem-appearance' and NZ.IsESX then
                        TriggerServerEvent('esx_skin:save', appearance)
                    else
                        TriggerServerEvent(ILLENIUM .. ':server:saveAppearance', appearance)
                    end
                end
                done()
            end, cfg)
        end)
        if ok then return end
    end

    if started('esx_skin') or started('skinchanger') then
        TriggerEvent('skinchanger:loadSkin', { sex = gender == 'f' and 1 or 0 }, function()
            TriggerEvent('esx_skin:openSaveableMenu', function() done() end, function() done() end)
        end)
        return
    end

    if started('qb-clothing') or started('rcore_clothing') or started('crm-appearance') or started('tgiann-clothing') then
        -- These resources react to qb-clothing's "first character" event and save on their own
        TriggerEvent('qb-clothes:client:CreateFirstCharacter')
        CreateThread(function()
            Wait(1500)
            local deadline = GetGameTimer() + 30 * 60000
            while IsNuiFocused() and GetGameTimer() < deadline do Wait(500) end
            done()
        end)
        return
    end

    -- No editor found
    done()
end
