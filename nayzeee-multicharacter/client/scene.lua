if not NAYZEEE_LOCK_OK then return end

Scene = { def = nil, peds = {}, entities = {}, page = 0, partner = nil, shots = {}, shotUrl = {} }

local S = Config.Scene

function Scene.Pick()
    local choice = Config.Scene.playerPick and Settings.Get('scene') or 'auto'
    local byId = {}
    for _, s in ipairs(Config.Scenes) do byId[s.id] = s end
    if choice ~= 'auto' and byId[choice] then return byId[choice] end
    if S.pick == 'first' then return Config.Scenes[1] end
    if byId[S.pick] then return byId[S.pick] end
    return Config.Scenes[math.random(1, #Config.Scenes)]
end

function Scene.Weather()
    local def = Scene.def
    local w = Settings.Get('weather')
    local h = Settings.Get('hour')
    World.Apply((w ~= 'auto' and w) or def.weather, (h and h >= 0) and h or def.hour, (h and h >= 0) and 0 or def.minute)
end

function Scene.Filter()
    local f = Settings.Get('filter')
    ClearTimecycleModifier()
    if f and f ~= '' then
        SetTimecycleModifier(f)
        SetTimecycleModifierStrength(1.0)
    elseif Scene.def and Scene.def.timecycle then
        SetTimecycleModifier(Scene.def.timecycle.name)
        SetTimecycleModifierStrength((Scene.def.timecycle.strength or 1.0) + 0.0)
    end
end

-- Stream the area, place the hidden player, spawn props / vehicles
function Scene.Build(def)
    Scene.def = def
    local a = def.anchor
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, a.x, a.y, a.z, false, false, false)
    SetEntityHeading(ped, a.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)

    local cam = def.overview.coords
    SetFocusPosAndVel(cam.x, cam.y, cam.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(a.x, a.y, a.z, 60.0, 0)
    local deadline = GetGameTimer() + 6000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
    RequestCollisionAtCoord(a.x, a.y, a.z)

    Scene.Weather()
    Scene.Filter()

    for _, p in ipairs(def.props or {}) do
        local m = joaat(p.model)
        if U.Model(m) then
            local o = CreateObjectNoOffset(m, p.coords.x, p.coords.y, p.coords.z, false, false, false)
            SetEntityHeading(o, p.coords.w or 0.0)
            FreezeEntityPosition(o, true)
            SetModelAsNoLongerNeeded(m)
            Scene.entities[#Scene.entities + 1] = o
        end
    end
    for _, v in ipairs(def.vehicles or {}) do
        local m = joaat(v.model)
        if U.Model(m) then
            local veh = CreateVehicle(m, v.coords.x, v.coords.y, v.coords.z, v.coords.w or 0.0, false, false)
            SetVehicleOnGroundProperly(veh)
            SetEntityInvincible(veh, true)
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleDoorsLocked(veh, 2)
            if v.color then SetVehicleColours(veh, v.color[1] or 0, v.color[2] or 0) end
            if v.lights then SetVehicleLights(veh, 2) end
            for _, d in ipairs(v.doors or {}) do SetVehicleDoorOpen(veh, d, false, true) end
            FreezeEntityPosition(veh, true)
            SetModelAsNoLongerNeeded(m)
            Scene.entities[#Scene.entities + 1] = veh
        end
    end
end

local function clearPeds()
    for _, p in pairs(Scene.peds) do U.Delete(p.ped) end
    Scene.peds = {}
    if Scene.partner then U.Delete(Scene.partner.ped) Scene.partner = nil end
end

local function poseFor(pos, char)
    if char and char.pose and not pos.lockPose then
        local p = U.PoseById(char.pose)
        if p then return p end
    end
    return pos.anim
end

-- Spawn every ped for a page. chars = bySlot map, shown = highest slot number displayed
function Scene.Page(page, chars, total, shown)
    clearPeds()
    Scene.page = page
    local positions = Scene.def.positions
    local n = #positions
    for i = 1, n do
        local slot = (page - 1) * n + i
        if slot > shown then break end
        local pos = positions[i]
        local char = chars[slot]
        local ped
        if char then
            ped = U.PreviewPed(Appearance.Model(char.model, char.gender), pos.coords)
            Appearance.ApplyPed(ped, char.skin)
            if char.locked or char.disabled then SetEntityAlpha(ped, 170, false) end
        elseif S.ghostEmpty then
            ped = U.PreviewPed(slot % 2 == 0 and `mp_f_freemode_01` or `mp_m_freemode_01`, pos.coords)
            SetPedHeadBlendData(ped, 21, 0, 0, 21, 0, 0, 0.5, 0.5, 0.0, false)
            SetEntityAlpha(ped, slot > total and S.lockedAlpha or S.ghostAlpha, false)
        end
        if ped then
            Scene.peds[slot] = { ped = ped, pos = pos, char = char }
            U.Pose(ped, poseFor(pos, char))
        end
    end
end

-- Partner ped next to a character (focus shot only)
function Scene.Partner(slot)
    if Scene.partner then U.Delete(Scene.partner.ped) Scene.partner = nil end
    local entry = Scene.peds[slot]
    if not Config.Partner.enabled or not entry or not entry.char or not entry.char.partner then return end
    local p = entry.char.partner
    local o = Config.Partner.offset
    local at = GetOffsetFromEntityInWorldCoords(entry.ped, o.x, o.y, o.z)
    local h = GetEntityHeading(entry.ped)
    local ped = U.PreviewPed(Appearance.Model(p.model, p.gender), vec4(at.x, at.y, at.z, h))
    Appearance.ApplyPed(ped, p.skin)
    U.Pose(ped, Config.Partner.poses[p.type] or Config.Partner.poses.friend)
    Scene.partner = { ped = ped, slot = slot }
end

-- Re-apply a pose on a live ped (pose picker preview)
function Scene.PreviewPose(slot, poseId)
    local e = Scene.peds[slot]
    if not e or e.pos.lockPose then return end
    U.Pose(e.ped, U.PoseById(poseId) or e.pos.anim)
end

-- New-character preview: swap the ghost for an opaque default ped of the chosen gender
function Scene.CreatorPed(slot, gender)
    local e = Scene.peds[slot]
    if not e then return nil end
    U.Delete(e.ped)
    local ped = U.PreviewPed(gender == 'f' and `mp_f_freemode_01` or `mp_m_freemode_01`, e.pos.coords)
    SetPedHeadBlendData(ped, gender == 'f' and 21 or 0, gender == 'f' and 21 or 0, 0, gender == 'f' and 21 or 0, gender == 'f' and 21 or 0, 0, 0.5, 0.5, 0.0, false)
    for c = 0, 11 do if c ~= 2 then SetPedComponentVariation(ped, c, 0, 0, 0) end end
    U.Pose(ped, e.pos.lockPose and e.pos.anim or (U.PoseById('relaxed') or e.pos.anim))
    e.ped = ped
    return ped
end

-- Portraits for NUI slot cards (https://nui-img/<txd>/<txd>)
function Scene.Headshots()
    if not Config.UI.headshots then return end
    CreateThread(function()
        for slot, e in pairs(Scene.peds) do
            if e.char and not Scene.shotUrl[slot] and DoesEntityExist(e.ped) then
                local h = RegisterPedheadshotTransparent(e.ped)
                local deadline = GetGameTimer() + 2500
                while not IsPedheadshotReady(h) and GetGameTimer() < deadline do Wait(50) end
                if IsPedheadshotReady(h) and IsPedheadshotValid(h) then
                    local txd = GetPedheadshotTxdString(h)
                    Scene.shots[#Scene.shots + 1] = h
                    Scene.shotUrl[slot] = ('https://nui-img/%s/%s'):format(txd, txd)
                    U.Send('headshot', { slot = slot, url = Scene.shotUrl[slot] })
                else
                    UnregisterPedheadshot(h)
                end
            end
        end
    end)
end

-- Nameplate anchors above every ped on the page
function Scene.Plates()
    local pts = {}
    for slot, e in pairs(Scene.peds) do
        if DoesEntityExist(e.ped) then
            local h = U.Head(e.ped)
            pts[#pts + 1] = { slot = slot, pos = vec3(h.x, h.y, h.z + 0.34) }
        end
    end
    return Cam.Project(pts)
end

function Scene.PedOf(slot)
    local e = Scene.peds[slot]
    return e and e.ped, e and e.pos
end

function Scene.Teardown()
    clearPeds()
    for _, e in ipairs(Scene.entities) do U.Delete(e) end
    Scene.entities = {}
    for _, h in ipairs(Scene.shots) do UnregisterPedheadshot(h) end
    Scene.shots, Scene.shotUrl = {}, {}
    ClearTimecycleModifier()
    ClearFocus()
    Scene.def, Scene.page = nil, 0
end
