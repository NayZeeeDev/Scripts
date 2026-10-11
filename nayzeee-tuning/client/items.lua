--[[ Usable items: lighting controller, stancer kit, repair kit, duct tape, cleaning kit. ]]

local U = Config.UsableItems
local remote -- { kind, veh, saved }

local function sfx(name) if Install.Sfx then Install.Sfx(name) end end

local function stateOf(veh) return NZ.Copy(Entity(veh).state.nzTune or {}) end

local function closeRemote(save)
    if not remote then return end
    local r = remote
    remote = nil
    UI.Send('remote:close')
    UI.Focus(false)
    if not save and DoesEntityExist(r.veh) then
        if r.kind == 'lighting' then
            for i = 0, 3 do SetVehicleNeonLightEnabled(r.veh, i, r.saved.sides[i + 1]) end
            SetVehicleNeonLightsColour(r.veh, r.saved.color.r, r.saved.color.g, r.saved.color.b)
            Apply.ResetNeonBase(r.veh)
        end
        Apply.ClearPreview(r.veh)
    elseif DoesEntityExist(r.veh) then
        -- the state bag update brings the saved look; drop the preview once it lands
        SetTimeout(600, function() if DoesEntityExist(r.veh) then Apply.ClearPreview(r.veh) end end)
    end
end

UI.On('remote:cancel', function() closeRemote(false) return true end)

--------------------------------------------------------------------- lighting controller

RegisterNetEvent('nayzeee-tuning:useLighting', function()
    if remote or Menu.open then return end
    local veh = cache.vehicle
    if not veh or cache.seat ~= -1 then return Notify(L('must_drive'), 'error') end
    local cls = GetVehicleClass(veh)
    if cls == 8 or cls == 13 then return Notify(L('remote_no_neon'), 'error') end
    local r, g, b = GetVehicleNeonLightsColour(veh)
    local sides = {}
    for i = 0, 3 do sides[i + 1] = IsVehicleNeonLightEnabled(veh, i) end
    local st = stateOf(veh)
    remote = { kind = 'lighting', veh = veh, saved = { sides = sides, color = { r = r, g = g, b = b } } }
    UI.Send('remote:open', {
        kind = 'lighting', label = select(1, VehUtil.Label(veh)), plate = VehUtil.Plate(veh),
        l = sides[1], r = sides[2], f = sides[3], b = sides[4], color = { r = r, g = g, b = b },
        pattern = st.neonPattern and st.neonPattern.id or 'static', speed = st.neonPattern and st.neonPattern.speed or 5,
        patterns = Config.NeonPatterns, canPattern = st.neonOwned == true or st.neonPattern ~= nil,
        presets = Config.NeonPresets,
    })
    UI.Focus(true)
end)

UI.On('remote:lighting', function(d)
    if not remote or remote.kind ~= 'lighting' then return false end
    local veh = remote.veh
    local c = d.color or {}
    SetVehicleNeonLightsColour(veh, math.floor(c.r or 255), math.floor(c.g or 255), math.floor(c.b or 255))
    local sides = { d.l, d.r, d.f, d.b }
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, sides[i + 1] == true) end
    Apply.ResetNeonBase(veh)
    local ex = stateOf(veh)
    if d.pattern and d.pattern ~= 'static' then ex.neonPattern = { id = d.pattern, speed = d.speed or 5 } else ex.neonPattern = nil end
    Apply.SetPreview(veh, ex)
    if d.save then
        local ok, err = lib.callback.await('nayzeee-tuning:lighting', false, VehToNet(veh), d)
        if not ok then Notify(err or L('failed'), 'error') return { ok = false, error = err } end
        closeRemote(true)
        Notify(L('remote_saved'), 'success')
    end
    return { ok = true }
end)

--------------------------------------------------------------------- stancer kit

RegisterNetEvent('nayzeee-tuning:useStancer', function()
    if remote or Menu.open then return end
    local veh = cache.vehicle or VehUtil.Closest(4.0)
    if not veh or veh == 0 then return Notify(L('no_vehicle'), 'error') end
    if Config.Stance.BlockedClasses[GetVehicleClass(veh)] then return Notify(L('remote_no_stance'), 'error') end
    local st = stateOf(veh)
    if U.StancerNeedsFitment and not st.stance and not st.stanceKit then return Notify(L('need_fitment'), 'error') end
    if not cache.vehicle then
        TaskTurnPedToFaceEntity(cache.ped, veh, 800)
        if not Bridge.Progress(L('remote_connecting'), 2500, { 'anim@heists@prison_heiststation@cop_reactions', 'cop_b_idle', 49 },
            { model = joaat('prop_cs_tablet'), bone = 28422, pos = vec3(0.0, -0.03, 0.0), rot = vec3(20.0, -90.0, 0.0) }) then return end
    end
    remote = { kind = 'stancer', veh = veh }
    local lim = Config.Stance.ModelLimits[select(3, VehUtil.Label(veh))] or {}
    local s = st.stance or {}
    UI.Send('remote:open', {
        kind = 'stancer', label = select(1, VehUtil.Label(veh)), plate = VehUtil.Plate(veh),
        stance = { oF = s.oF or 0, oR = s.oR or 0, cF = s.cF or 0, cR = s.cR or 0 },
        height = st.height or 0.0, airride = st.airride == true,
        offset = lim.Offset or Config.Stance.Offset, camber = lim.Camber or Config.Stance.Camber,
        heightRange = { min = Config.RideHeight.min, max = Config.RideHeight.max, step = Config.RideHeight.step },
    })
    UI.Focus(true)
    sfx('ratchet')
end)

UI.On('remote:stancer', function(d)
    if not remote or remote.kind ~= 'stancer' then return false end
    local veh = remote.veh
    if not DoesEntityExist(veh) then closeRemote(false) return false end
    local stance = d.stance
    if stance and not NZ.Validate('stance', stance) then return false end
    local height = tonumber(d.height)
    if height ~= nil and not NZ.Validate('height', height) then height = nil end
    local ex = stateOf(veh)
    if stance then NZ.ApplyToExtras(ex, 'stance', stance) end
    if height ~= nil and not ex.airride then ex.height = height ~= 0 and height or nil end
    Apply.SetPreview(veh, ex)
    if d.save then
        local ok, err = lib.callback.await('nayzeee-tuning:stancer', false, VehToNet(veh), stance, height)
        if not ok then Notify(err or L('failed'), 'error') return { ok = false, error = err } end
        sfx('tighten')
        closeRemote(true)
        Notify(L('remote_saved'), 'success')
    end
    return { ok = true }
end)

-- leaving the car / car gone closes the remote
CreateThread(function()
    while true do
        if remote then
            local gone = not DoesEntityExist(remote.veh)
            if remote.kind == 'lighting' and cache.vehicle ~= remote.veh then gone = true end
            if remote.kind == 'stancer' and #(GetEntityCoords(cache.ped) - GetEntityCoords(remote.veh)) > 8.0 then gone = true end
            if gone then closeRemote(false) end
        end
        Wait(remote and 500 or 2000)
    end
end)

--------------------------------------------------------------------- repair kit / duct tape / cleaning kit

local busy = false

local function kit(kind, cfg, anim, prop, label, hood)
    if busy or cache.vehicle then return Notify(L('kit_leave_car'), 'error') end
    local veh = VehUtil.Closest(3.5)
    if not veh or veh == 0 then return Notify(L('no_vehicle'), 'error') end
    if kind == 'tape' and GetVehicleEngineHealth(veh) >= cfg.minEngine then return Notify(L('kit_not_needed'), 'inform') end
    if kind == 'clean' and GetVehicleDirtLevel(veh) < 1.0 then return Notify(L('kit_not_needed'), 'inform') end
    busy = true
    TaskTurnPedToFaceEntity(cache.ped, veh, 900)
    Wait(900)
    if hood then SetVehicleDoorOpen(veh, 4, false, false) end
    sfx(kind == 'clean' and 'clean' or 'ratchet')
    local done = Bridge.Progress(label, cfg.time, anim, prop)
    if hood then SetVehicleDoorShut(veh, 4, false) end
    if not done then busy = false return end
    local ok, res = lib.callback.await('nayzeee-tuning:useKit', false, kind, VehToNet(veh))
    busy = false
    if not ok then return Notify(res or L('failed'), 'error') end
    if not VehUtil.Control(veh, 1500) then return Notify(L('failed'), 'error') end
    if kind == 'repair' then
        local eng = GetVehicleEngineHealth(veh)
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, math.max(eng, res.engine))
        SetVehicleBodyHealth(veh, res.body)
        sfx('tighten')
    elseif kind == 'tape' then
        SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), res.engine))
        SetVehicleUndriveable(veh, false)
    elseif kind == 'clean' then
        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
    end
    Notify(L('kit_done_' .. kind), 'success')
end

RegisterNetEvent('nayzeee-tuning:useRepairKit', function()
    kit('repair', U.RepairKit, { 'mini@repair', 'fixing_a_ped', 1 }, nil, L('kit_repairing'), true)
end)

RegisterNetEvent('nayzeee-tuning:useDuctTape', function()
    kit('tape', U.DuctTape, { 'mini@repair', 'fixing_a_ped', 1 }, nil, L('kit_taping'), true)
end)

RegisterNetEvent('nayzeee-tuning:useCleaningKit', function()
    kit('clean', U.CleaningKit, { 'timetable@floyd@clean_kitchen@base', 'base', 1 },
        { model = joaat('prop_sponge_01'), bone = 28422, pos = vec3(0.0, 0.0, -0.01), rot = vec3(90.0, 0.0, 0.0) }, L('kit_cleaning'), false)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and remote then closeRemote(false) end
end)
