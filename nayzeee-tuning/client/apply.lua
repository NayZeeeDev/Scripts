--[[
    Two jobs:
      1. Apply / read single tuning items on a vehicle (menu preview, installs).
      2. Keep custom data (state bag 'nzTune') applied to every nearby car: stance, wheel size,
         ride height, air ride, engine swap sound, headlight RGB, drift / run-flat tyres, underglow modes.

    Idle cost is a 1 s scan. Per-frame work only happens while a stanced car is on screen nearby.
]]

Apply = {}

local preview = {}       -- [veh] = extras table used instead of the state bag (menu / test drive)
local applied = {}       -- [veh] = { key = true } features we changed on this car
local defaults = {}      -- [veh] = { offsets = {}, size, width }
local lastSig = {}       -- [veh] = json signature of the last data applied
local tracked = {}       -- list of { veh, data } within range
local anims = {}         -- [veh] = { from, to, start, dur } ride height transitions
local neonBase = {}      -- [veh] = { r, g, b, sides }

local PI180 = math.pi / 180.0
local CFG_ST = Config.Stance

--------------------------------------------------------------------- data access

function Apply.Data(veh)
    local p = preview[veh]
    if p then return p end
    local st = Entity(veh).state
    return st and st.nzTune or nil
end

function Apply.SetPreview(veh, data)
    preview[veh] = data or {}
    lastSig[veh] = nil
    local found = false
    for i = 1, #tracked do if tracked[i].veh == veh then tracked[i].data = preview[veh] found = true end end
    if not found then tracked[#tracked + 1] = { veh = veh, data = preview[veh] } end
    Apply.Refresh(veh)
end

function Apply.ClearPreview(veh)
    preview[veh] = nil
    lastSig[veh] = nil
    Apply.Refresh(veh)
end

function Apply.HasPreview(veh) return preview[veh] ~= nil end

--------------------------------------------------------------------- defaults

local function getDefaults(veh)
    local d = defaults[veh]
    if d then return d end
    d = { offsets = {}, size = GetVehicleWheelSize(veh), width = GetVehicleWheelWidth(veh) }
    for i = 0, GetVehicleNumberOfWheels(veh) - 1 do d.offsets[i] = GetVehicleWheelXOffset(veh, i) end
    defaults[veh] = d
    return d
end

local function stanceAllowed(veh)
    if not CFG_ST.Enabled then return false end
    if CFG_ST.BlockedClasses[GetVehicleClass(veh)] then return false end
    return true
end

--------------------------------------------------------------------- per-frame pieces

local function applyStance(veh, st)
    local d = getDefaults(veh)
    local n = GetVehicleNumberOfWheels(veh)
    for i = 0, n - 1 do
        local front = i < 2
        local left = i % 2 == 0
        local off = front and (st.oF or 0) or (st.oR or 0)
        local cam = (front and (st.cF or 0) or (st.cR or 0)) * PI180
        local base = d.offsets[i] or GetVehicleWheelXOffset(veh, i)
        SetVehicleWheelXOffset(veh, i, base + (left and -off or off))
        SetVehicleWheelYRotation(veh, i, left and -cam or cam)
    end
end

local function resetStance(veh)
    local d = defaults[veh]
    if not d then return end
    for i = 0, GetVehicleNumberOfWheels(veh) - 1 do
        if d.offsets[i] then SetVehicleWheelXOffset(veh, i, d.offsets[i]) end
        SetVehicleWheelYRotation(veh, i, 0.0)
    end
end

local function targetHeight(data)
    if data.airride then
        local p = Config.AirRide.Presets[data.air or Config.AirRide.DefaultPreset]
        return p and p.height or 0.0
    end
    return data.height or 0.0
end

--------------------------------------------------------------------- one-shot pieces

local function mark(veh, key, on)
    applied[veh] = applied[veh] or {}
    applied[veh][key] = on or nil
end

local function wasApplied(veh, key) return applied[veh] and applied[veh][key] end

local function applyOnce(veh, data)
    data = data or {}

    -- wheel size / width (only works with custom rims fitted)
    if data.size or data.width then
        if GetVehicleMod(veh, 23) ~= -1 then
            getDefaults(veh)
            if data.size then SetVehicleWheelSize(veh, data.size + 0.0) end
            if data.width then SetVehicleWheelWidth(veh, data.width + 0.0) end
            mark(veh, 'dims', true)
        end
    elseif wasApplied(veh, 'dims') then
        local d = defaults[veh]
        if d then SetVehicleWheelSize(veh, d.size) SetVehicleWheelWidth(veh, d.width) end
        mark(veh, 'dims', false)
    end

    -- ride height / air ride
    local h = targetHeight(data)
    if h ~= 0.0 or wasApplied(veh, 'height') then
        local cur = GetVehicleSuspensionHeight(veh)
        if data.airride and math.abs(cur - h) > 0.004 and wasApplied(veh, 'height') then
            anims[veh] = { from = cur, to = h, start = GetGameTimer(), dur = Config.AirRide.TransitionMs }
            if Config.AirRide.HissSound and #(GetEntityCoords(veh) - GetEntityCoords(cache.ped)) < 25.0 then
                UI.Send('sound', { name = 'hiss', volume = 0.5 })
            end
        else
            SetVehicleSuspensionHeight(veh, h + 0.0)
        end
        mark(veh, 'height', h ~= 0.0 or data.airride == true)
    end

    -- engine note: a sound pack wins over the swapped engine's own sound
    local note = data.sound or data.swap
    if note then
        if wasApplied(veh, 'swap') ~= note then
            ForceUseAudioGameObject(veh, note)
            applied[veh] = applied[veh] or {}
            applied[veh].swap = note
        end
    elseif wasApplied(veh, 'swap') then
        ForceUseAudioGameObject(veh, GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
        applied[veh].swap = nil
    end

    -- headlight RGB
    if data.xenonRGB then
        SetVehicleXenonLightsCustomColor(veh, data.xenonRGB.r, data.xenonRGB.g, data.xenonRGB.b)
        mark(veh, 'xenon', true)
    elseif wasApplied(veh, 'xenon') then
        ClearVehicleXenonLightsCustomColor(veh)
        mark(veh, 'xenon', false)
    end

    -- tyres
    if data.drift or wasApplied(veh, 'drift') then
        SetDriftTyresEnabled(veh, data.drift == true)
        mark(veh, 'drift', data.drift == true)
    end
    if data.bulletproof or wasApplied(veh, 'bp') then
        SetVehicleTyresCanBurst(veh, not data.bulletproof)
        mark(veh, 'bp', data.bulletproof == true)
    end

    -- stance reset (application itself happens per frame)
    if not data.stance and wasApplied(veh, 'stance') then
        resetStance(veh)
        mark(veh, 'stance', false)
    elseif data.stance and stanceAllowed(veh) then
        getDefaults(veh)
        applyStance(veh, data.stance)
        mark(veh, 'stance', true)
    end

    -- underglow modes: restore the real colour when a pattern is removed
    if not data.neonPattern and neonBase[veh] then
        local b = neonBase[veh]
        SetVehicleNeonLightsColour(veh, b.r, b.g, b.b)
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, b.sides[i] == true) end
        neonBase[veh] = nil
    end
end

function Apply.Refresh(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local data = Apply.Data(veh)
    local sig = data and json.encode(data) or ''
    if lastSig[veh] == sig then return end
    lastSig[veh] = sig
    applyOnce(veh, data)
end

--------------------------------------------------------------------- scanning

local function forget(veh)
    preview[veh], applied[veh], defaults[veh], lastSig[veh], anims[veh], neonBase[veh] = nil, nil, nil, nil, nil, nil
end

local range = CFG_ST.StreamRange
CreateThread(function()
    while true do
        local me = GetEntityCoords(cache.ped)
        local list = {}
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            local data = preview[veh]
            if not data then
                local st = Entity(veh).state
                data = st and st.nzTune
            end
            if data then
                if #(GetEntityCoords(veh) - me) <= range then
                    list[#list + 1] = { veh = veh, data = data }
                    local sig = json.encode(data)
                    if lastSig[veh] ~= sig then lastSig[veh] = sig applyOnce(veh, data)
                    elseif (data.size or data.width) and GetVehicleMod(veh, 23) ~= -1 and data.size
                        and math.abs(GetVehicleWheelSize(veh) - data.size) > 0.01 then
                        applyOnce(veh, data)           -- the game reset it (rim change / re-stream)
                    end
                end
            elseif applied[veh] then
                applyOnce(veh, nil)
                forget(veh)
            end
        end
        for veh in pairs(applied) do
            if not DoesEntityExist(veh) then forget(veh) end
        end
        tracked = list
        Wait(1000)
    end
end)

-- per-frame stance + ride height animation, only while needed
CreateThread(function()
    while true do
        local busy = false
        local now = GetGameTimer()
        for veh, a in pairs(anims) do
            busy = true
            if not DoesEntityExist(veh) then anims[veh] = nil
            else
                local t = math.min(1.0, (now - a.start) / a.dur)
                local e = t < 0.5 and 2 * t * t or 1 - ((-2 * t + 2) ^ 2) / 2
                SetVehicleSuspensionHeight(veh, a.from + (a.to - a.from) * e)
                if t >= 1.0 then anims[veh] = nil end
            end
        end
        if CFG_ST.Enabled then
            for i = 1, #tracked do
                local t = tracked[i]
                local st = t.data.stance
                if st and DoesEntityExist(t.veh) and (not CFG_ST.OnScreenOnly or IsEntityOnScreen(t.veh)) and stanceAllowed(t.veh) then
                    busy = true
                    local live = preview[t.veh] and preview[t.veh].stance or st
                    applyStance(t.veh, live)
                end
            end
        end
        Wait(busy and 0 or 300)
    end
end)

--------------------------------------------------------------------- underglow modes

local HUES = { { 1, 't', 0 }, { 'q', 1, 0 }, { 0, 1, 't' }, { 0, 'q', 1 }, { 't', 0, 1 }, { 1, 0, 'q' } }
local function hsv(h)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local row = HUES[i % 6 + 1]
    local function v(x) if x == 't' then return f elseif x == 'q' then return 1 - f end return x end
    return math.floor(v(row[1]) * 255), math.floor(v(row[2]) * 255), math.floor(v(row[3]) * 255)
end

CreateThread(function()
    while true do
        local any = false
        local now = GetGameTimer()
        for i = 1, #tracked do
            local t = tracked[i]
            local pat = (preview[t.veh] or t.data).neonPattern
            if pat and DoesEntityExist(t.veh) and IsEntityOnScreen(t.veh) then
                any = true
                local veh = t.veh
                local base = neonBase[veh]
                if not base then
                    local r, g, b = GetVehicleNeonLightsColour(veh)
                    local sides = {}
                    for s = 0, 3 do sides[s] = IsVehicleNeonLightEnabled(veh, s) end
                    base = { r = r, g = g, b = b, sides = sides }
                    neonBase[veh] = base
                end
                local speed = (pat.speed or 5) / 5
                local c2 = pat.color2 or { r = 255, g = 255, b = 255 }
                local r, g, b = base.r, base.g, base.b
                local on = { base.sides[0], base.sides[1], base.sides[2], base.sides[3] }
                local id = pat.id
                if id == 'pulse' then
                    local k = 0.15 + 0.85 * (0.5 + 0.5 * math.sin(now / 1000 * math.pi * speed))
                    r, g, b = math.floor(r * k), math.floor(g * k), math.floor(b * k)
                elseif id == 'strobe' then
                    local lit = math.floor(now / (140 / speed)) % 2 == 0
                    for s = 1, 4 do on[s] = on[s] and lit end
                elseif id == 'chase' then
                    local step = math.floor(now / (220 / speed)) % 4
                    local order = { 2, 1, 3, 0 }         -- front, right, back, left
                    for s = 1, 4 do on[s] = base.sides[s - 1] and order[step + 1] == s - 1 end
                elseif id == 'rainbow' then
                    r, g, b = hsv((now / (6000 / speed)) % 1.0)
                elseif id == 'dual' then
                    if math.floor(now / (600 / speed)) % 2 == 1 then r, g, b = c2.r, c2.g, c2.b end
                elseif id == 'police' then
                    local phase = math.floor(now / (120 / speed)) % 8
                    if phase < 4 then r, g, b = 255, 20, 20 else r, g, b = 20, 60, 255 end
                    local lit = phase % 2 == 0
                    for s = 1, 4 do on[s] = base.sides[s - 1] and lit end
                end
                SetVehicleNeonLightsColour(veh, r, g, b)
                for s = 0, 3 do SetVehicleNeonLightEnabled(veh, s, on[s + 1] == true) end
            end
        end
        Wait(any and 100 or 1000)
    end
end)

-- when a pattern starts on a car, remember its real colour first
function Apply.ResetNeonBase(veh) neonBase[veh] = nil end

--------------------------------------------------------------------- state bag hooks

AddStateBagChangeHandler('nzTune', nil, function(bagName)
    local ent = GetEntityFromStateBagName(bagName)
    if ent == 0 then return end
    SetTimeout(0, function()
        if DoesEntityExist(ent) and not preview[ent] then
            lastSig[ent] = nil
            neonBase[ent] = nil
            Apply.Refresh(ent)
        end
    end)
end)

AddStateBagChangeHandler('nzProps', nil, function(bagName, _, value)
    if not value or not value.props then return end
    local ent = GetEntityFromStateBagName(bagName)
    local tries = 0
    while ent == 0 and tries < 20 do Wait(100) tries = tries + 1 ent = GetEntityFromStateBagName(bagName) end
    if ent == 0 or NetworkGetEntityOwner(ent) ~= PlayerId() then return end
    Bridge.SetProps(ent, value.props)
end)

RegisterNetEvent('nayzeee-tuning:serviceActions', function(netId, lines)
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 or NetworkGetEntityOwner(veh) ~= PlayerId() then return end
    Apply.Service(veh, lines)
end)

function Apply.Service(veh, lines)
    for _, l in ipairs(lines or {}) do
        local kind = Config.Parts[l.id] and Config.Parts[l.id].kind
        if kind == 'repair' then
            SetVehicleFixed(veh)
            SetVehicleDeformationFixed(veh)
            SetVehicleEngineHealth(veh, 1000.0)
            SetVehicleBodyHealth(veh, 1000.0)
            SetVehiclePetrolTankHealth(veh, 1000.0)
            SetVehicleUndriveable(veh, false)
        elseif kind == 'clean' then
            SetVehicleDirtLevel(veh, 0.0)
            WashDecalsFromVehicle(veh, 1.0)
        end
    end
end

--------------------------------------------------------------------- single items (preview + install)

local function setColor(veh, target, v)
    if target == 'primary' or target == 'secondary' then
        local c1, c2 = GetVehicleColours(veh)
        if v.mode == 'rgb' then
            if target == 'primary' then
                SetVehicleModColor_1(veh, v.finish or 0, 0, 0)
                SetVehicleCustomPrimaryColour(veh, v.r, v.g, v.b)
            else
                SetVehicleModColor_2(veh, v.finish or 0, 0)
                SetVehicleCustomSecondaryColour(veh, v.r, v.g, v.b)
            end
        else
            if target == 'primary' then
                ClearVehicleCustomPrimaryColour(veh)
                SetVehicleColours(veh, v.index, c2)
            else
                ClearVehicleCustomSecondaryColour(veh)
                SetVehicleColours(veh, c1, v.index)
            end
        end
    elseif target == 'pearl' then
        local _, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, v.index, wheel)
    elseif target == 'wheel' then
        local pearl = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, pearl, v.index)
    elseif target == 'interior' then
        SetVehicleInteriorColor(veh, v.index)
    elseif target == 'dashboard' then
        SetVehicleDashboardColor(veh, v.index)
    end
end

-- applies GTA-side items. Extras-side items are handled through Apply.SetPreview.
function Apply.Item(veh, id, value)
    local part = Config.Parts[id]
    if not part then return end
    local k = part.kind
    SetVehicleModKit(veh, 0)
    if k == 'mod' then
        if part.slot == 23 or part.slot == 24 then
            SetVehicleMod(veh, part.slot, value, GetVehicleModVariation(veh, 23))
        else
            SetVehicleMod(veh, part.slot, value, false)
        end
    elseif k == 'toggle' then
        ToggleVehicleMod(veh, part.slot, value == true)
    elseif k == 'color' then
        setColor(veh, part.target, value)
    elseif k == 'wheels' then
        local custom = GetVehicleModVariation(veh, 23)
        SetVehicleWheelType(veh, value.type)
        SetVehicleMod(veh, 23, value.index, custom)
        if GetVehicleClass(veh) == 8 then SetVehicleMod(veh, 24, value.index, custom) end
    elseif k == 'rearWheels' then
        SetVehicleMod(veh, 24, value, GetVehicleModVariation(veh, 24))
    elseif k == 'customTires' then
        SetVehicleMod(veh, 23, GetVehicleMod(veh, 23), value)
        if GetVehicleClass(veh) == 8 then SetVehicleMod(veh, 24, GetVehicleMod(veh, 24), value) end
    elseif k == 'smoke' then
        ToggleVehicleMod(veh, 20, true)
        SetVehicleTyreSmokeColor(veh, value.r, value.g, value.b)
    elseif k == 'neon' then
        SetVehicleNeonLightEnabled(veh, 0, value.l)
        SetVehicleNeonLightEnabled(veh, 1, value.r)
        SetVehicleNeonLightEnabled(veh, 2, value.f)
        SetVehicleNeonLightEnabled(veh, 3, value.b)
        SetVehicleNeonLightsColour(veh, value.color.r, value.color.g, value.color.b)
        neonBase[veh] = nil
    elseif k == 'xenonColor' then
        ToggleVehicleMod(veh, 22, true)
        if value.mode == 'index' then
            SetVehicleXenonLightsColor(veh, value.index == -1 and 255 or value.index)
        end
    elseif k == 'plateIndex' then
        SetVehicleNumberPlateTextIndex(veh, value)
    elseif k == 'tint' then
        SetVehicleWindowTint(veh, value)
    elseif k == 'extras' then
        for extraId, on in pairs(value) do
            local n = tonumber(extraId)
            if n and DoesExtraExist(veh, n) then SetVehicleExtra(veh, n, not on) end
        end
    elseif k == 'livery' then
        if GetVehicleLiveryCount(veh) > 0 then SetVehicleLivery(veh, value) else SetVehicleMod(veh, 48, value, false) end
    elseif k == 'roofLivery' then
        SetVehicleRoofLivery(veh, value)
    end
end

-- current value of an item on the car, in the same shape the menu / validators use
function Apply.Current(veh, id, extras)
    local part = Config.Parts[id]
    if not part then return nil end
    local k = part.kind
    extras = extras or {}
    if k == 'mod' then return GetVehicleMod(veh, part.slot)
    elseif k == 'toggle' then return IsToggleModOn(veh, part.slot)
    elseif k == 'color' then
        local t = part.target
        if t == 'primary' then
            if GetIsVehiclePrimaryColourCustom(veh) then
                local r, g, b = GetVehicleCustomPrimaryColour(veh)
                local finish = GetVehicleModColor_1(veh)
                return { mode = 'rgb', r = r, g = g, b = b, finish = finish }
            end
            local c1 = GetVehicleColours(veh)
            return { mode = 'index', index = c1 }
        elseif t == 'secondary' then
            if GetIsVehicleSecondaryColourCustom(veh) then
                local r, g, b = GetVehicleCustomSecondaryColour(veh)
                local finish = GetVehicleModColor_2(veh)
                return { mode = 'rgb', r = r, g = g, b = b, finish = finish }
            end
            local _, c2 = GetVehicleColours(veh)
            return { mode = 'index', index = c2 }
        elseif t == 'pearl' then
            local pearl = GetVehicleExtraColours(veh)
            return { mode = 'index', index = pearl }
        elseif t == 'wheel' then
            local _, wheel = GetVehicleExtraColours(veh)
            return { mode = 'index', index = wheel }
        elseif t == 'interior' then return { mode = 'index', index = GetVehicleInteriorColor(veh) }
        elseif t == 'dashboard' then return { mode = 'index', index = GetVehicleDashboardColor(veh) } end
    elseif k == 'wheels' then return { type = GetVehicleWheelType(veh), index = GetVehicleMod(veh, 23) }
    elseif k == 'rearWheels' then return GetVehicleMod(veh, 24)
    elseif k == 'customTires' then return GetVehicleModVariation(veh, 23) == true
    elseif k == 'smoke' then local r, g, b = GetVehicleTyreSmokeColor(veh) return { r = r, g = g, b = b }
    elseif k == 'drift' then return extras.drift == true
    elseif k == 'bulletproof' then return extras.bulletproof == true
    elseif k == 'wheelSize' then return NZ.Round(extras.size or GetVehicleWheelSize(veh), 2)
    elseif k == 'wheelWidth' then return NZ.Round(extras.width or GetVehicleWheelWidth(veh), 2)
    elseif k == 'stance' then
        local s = extras.stance or {}
        return { oF = s.oF or 0, oR = s.oR or 0, cF = s.cF or 0, cR = s.cR or 0 }
    elseif k == 'height' then return extras.height or 0.0
    elseif k == 'neon' then
        local r, g, b = GetVehicleNeonLightsColour(veh)
        return { l = IsVehicleNeonLightEnabled(veh, 0), r = IsVehicleNeonLightEnabled(veh, 1),
                 f = IsVehicleNeonLightEnabled(veh, 2), b = IsVehicleNeonLightEnabled(veh, 3), color = { r = r, g = g, b = b } }
    elseif k == 'neonPattern' then return extras.neonPattern and NZ.Copy(extras.neonPattern) or { id = 'static', speed = 5 }
    elseif k == 'xenonColor' then
        if extras.xenonRGB then return { mode = 'rgb', r = extras.xenonRGB.r, g = extras.xenonRGB.g, b = extras.xenonRGB.b } end
        local c = GetVehicleXenonLightsColor(veh)
        return { mode = 'index', index = (c == 255 or c < 0) and -1 or c }
    elseif k == 'plateText' then return VehUtil.Plate(veh)
    elseif k == 'plateIndex' then return GetVehicleNumberPlateTextIndex(veh)
    elseif k == 'tint' then local t = GetVehicleWindowTint(veh) return t < 0 and 0 or t
    elseif k == 'extras' then
        local out = {}
        for i = 0, 20 do
            if DoesExtraExist(veh, i) then out[tostring(i)] = IsVehicleExtraTurnedOn(veh, i) end
        end
        return out
    elseif k == 'livery' then
        if GetVehicleLiveryCount(veh) > 0 then return GetVehicleLivery(veh) end
        return GetVehicleMod(veh, 48)
    elseif k == 'roofLivery' then return GetVehicleRoofLivery(veh)
    elseif k == 'nitrous' then return extras.nitrous and extras.nitrous.level or 0
    elseif k == 'ecu' then return extras.ecu ~= nil
    elseif k == 'swap' then return extras.swap or false
    elseif k == 'antilag' then return extras.antilag == true
    elseif k == 'launch' then return extras.launch == true
    elseif k == 'airride' then return extras.airride == true
    elseif k == 'locator' then return extras.locator == true
    elseif k == 'tyres' then return extras.tyres or 'stock'
    elseif k == 'drivetrain' then return extras.drive or 'stock'
    elseif k == 'ceramic' then return extras.ceramic == true
    elseif k == 'driftKit' then return extras.driftKit == true
    elseif k == 'gearbox' then return extras.gearbox == 'manual' and 'manual' or 'auto'
    elseif k == 'sound' then return extras.sound or false
    end
    return nil
end
