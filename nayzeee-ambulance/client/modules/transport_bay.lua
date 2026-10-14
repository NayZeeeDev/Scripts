--[[
    NAYZEEE AMBULANCE - Transport (client): walk-in ambulance treatment bay

    'Enter treatment bay' at the back doors of a configured ambulance (or from one of its passenger
    seats while it drives - radial) → fade → the interior model
    (Config.Props[Config.Transport.Bay.shell]) is spawned LOCALLY at this ambulance's hidden slot
    (Config.Transport.Bay.base + slot offset), lit with DrawLightWithRange, and you stand at your
    crew spot. The patient on the loaded stretcher comes along (player: their own client moves them;
    NPC: the first medic in moves it). Leaving puts you behind the ambulance's CURRENT back doors, or
    back in a free passenger seat when it is still driving.

      NZA.Transport.Bay.Enter(veh)   Exit(kicked?, at?)   Active() → state | nil
      NZA.Transport.Bay.Origin(slot) → vector3            PatientSpot(slot) → vector4
      NZA.Transport.Bay.OpenSupplies()   Tool('examine'|'monitor'|'ivstand')
      NZA.Transport.Bay.Info() → { veh, slot, origin, hooks = { vector3 IV hooks }, cot = vector4 } | nil
      Patient side (from the nzaTr bag): PlacePatient(ped, cmd, isSelf), EnsurePatient(ped, cmd),
                                         ReturnFromBay(ped, cmd, isSelf), NpcNeedsFix(ped, bag)

    NUI app 'bay' (no focus; the supplies window takes focus while open)
      Lua → JS: open { locale, keys, unit, crew, me, warnings, tools }, patient (lite | nil), crew,
                tick { speed, plate }, supplies (list), monitor { on }, tools
      JS → Lua: bay:take { key, count } → { ok, list | msg }, bay:supplies { open = false }, bay:action { id }
    Key mappings (rebindable): nza_bay_exit (BACKSPACE), nza_bay_examine (F1), nza_bay_supplies (F2),
                               nza_bay_ivstand (F3), nza_bay_monitor (F4)
    Client bus emitted: bay:entered (vehNet, target|nil), bay:left (vehNet),
                        bay:ivstand (target, info), bay:monitor (target, info) - other modules can
                        handle the IV stand / big monitor; nothing listening → built-in fallback
    Net events handled: nza:transport:bay:crew, nza:transport:bay:tick, nza:transport:bay:kick
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Transport = NZA.Transport or {}
local Tr = NZA.Transport
Tr.Bay = Tr.Bay or {}
local Bay = Tr.Bay
local U = NZA.Util

local APP = 'bay'
local GROUP = 'transport_bay'

local shell = { slot = nil, ents = {}, cot = 0, zones = {}, lights = false }

local function S() return Tr.S end
local function bc() return Tr.Cfg('Bay') end

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY
-- ════════════════════════════════════════════════════════════════════════

function Bay.Origin(slot)
    local c = bc()
    local base = c.base or vector3(480.0, 5580.0, 360.0)
    local cols = math.max(1, math.floor(tonumber(c.columns) or 6))
    local sp = tonumber(c.spacing) or 32.0
    local i = (tonumber(slot) or 1) - 1
    local col, row = i % cols, math.floor(i / cols)
    return vector3(base.x + col * sp, base.y + row * sp, base.z)
end

local function world(slot, off)
    local o = Bay.Origin(slot)
    return vector4(o.x + (off.x or 0.0), o.y + (off.y or 0.0), o.z + (off.z or 0.0), off.w or 0.0)
end

local function rotate(x, y, deg)
    local r = math.rad(deg)
    local cs, sn = math.cos(r), math.sin(r)
    return x * cs - y * sn, x * sn + y * cs
end

function Bay.CotSpot(slot)
    return world(slot, bc().stretcher or vector4(-0.42, 0.10, 0.0, 0.0))
end

function Bay.PatientSpot(slot)
    local cot = Bay.CotSpot(slot)
    local pc = Tr.Cfg('Stretcher').patient or {}
    local pos = pc.pos or vector3(0.0, 0.05, 1.33)
    local rot = pc.rot or vector3(0.0, 0.0, 180.0)
    local x, y = rotate(pos.x, pos.y, cot.w)
    return vector4(cot.x + x, cot.y + y, cot.z + pos.z, (cot.w + rot.z) % 360.0)
end

local function medicSpot(slot, idx)
    local list = bc().medics or {}
    if #list == 0 then return world(slot, vector4(-0.55, -0.55, 0.0, 300.0)) end
    local i = ((math.max(1, tonumber(idx) or 1) - 1) % #list) + 1
    return world(slot, list[i])
end

local function lyingAnim()
    return (Tr.Cfg('Stretcher').patient or {}).anim or Tr.Cfg('Beds').anim
end

local function fadeOut(ms)
    DoScreenFadeOut(ms)
    local t = GetGameTimer() + ms + 1500
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
end

local function fadeIn(ms)
    DoScreenFadeIn(ms)
end

-- ════════════════════════════════════════════════════════════════════════
-- SHELL (local, per client)
-- ════════════════════════════════════════════════════════════════════════

local function lightsLoop()
    if shell.lights then return end
    shell.lights = true
    CreateThread(function()
        while shell.slot do
            local o = Bay.Origin(shell.slot)
            for _, l in ipairs(bc().lights or {}) do
                local p = l.pos or vector3(0.0, 0.0, 2.0)
                local col = l.color or { 255, 248, 235 }
                DrawLightWithRange(o.x + p.x, o.y + p.y, o.z + p.z, col[1] or 255, col[2] or 255, col[3] or 255,
                    l.range or 4.0, l.intensity or 2.0)
            end
            Wait(0)
        end
        shell.lights = false
    end)
end

local function clearShell()
    if Bridge and Bridge.Target then
        for _, id in ipairs(shell.zones) do pcall(Bridge.Target.Remove, id) end
    end
    shell.zones = {}
    NZA.Props.Clear(GROUP)
    shell.ents, shell.cot, shell.slot = {}, 0, nil
end

local function asList(v)
    if v == nil then return {} end
    if type(v) == 'table' and v.x == nil and v[1] ~= nil then return v end
    return { v }
end

local function spawnShell(slot, medic)
    if shell.slot == slot and #shell.ents > 0 then return end
    clearShell()
    local o = Bay.Origin(slot)
    RequestCollisionAtCoord(o.x, o.y, o.z)
    local key = bc().shell or 'bay_shell'
    local name = Config.Props and Config.Props[key]
    local ent = 0
    if name and IsModelInCdimage(GetHashKey(name)) then
        ent = NZA.Props.Spawn(key, vector4(o.x, o.y, o.z, 0.0), { group = GROUP, network = false, freeze = true, collision = true })
    end
    if ent == 0 and bc().fallbackFloor then
        local h = GetHashKey(bc().fallbackFloor)
        if IsModelInCdimage(h) then
            local _, mx = GetModelDimensions(h)
            ent = NZA.Props.Spawn(bc().fallbackFloor, vector4(o.x, o.y, o.z - mx.z, 0.0),
                { group = GROUP, network = false, freeze = true, collision = true })
        end
    end
    shell.slot = slot
    shell.ents = { ent }
    local cot = Bay.CotSpot(slot)
    shell.cot = NZA.Props.Spawn(Tr.Cfg('Stretcher').model or 'stretcher', cot,
        { group = GROUP, network = false, freeze = true, collision = true, fallbackKey = 'stretcher' })
    -- dress the bay (monitor on the shelf, sharps bin, kit case)
    for _, d in ipairs(bc().props or {}) do
        if d.model and d.pos then
            local name = Config.Props and Config.Props[d.model] or d.model
            if name and IsModelInCdimage(GetHashKey(name)) then
                NZA.Props.Spawn(d.model, world(slot, d.pos), { group = GROUP, network = false, freeze = true, collision = false })
            end
        end
    end
    if medic and Bridge and Bridge.Target and bc().supplies and bc().supplies.enabled ~= false then
        for i, sh in ipairs(asList(bc().shelves)) do
            shell.zones[#shell.zones + 1] = Bridge.Target.Sphere('nza_bay_supplies_' .. i, vector3(o.x + sh.x, o.y + sh.y, o.z + sh.z), 0.9, {
                {
                    name = 'nza_bay_supplies', label = Tr.L('supplies'), icon = 'box', distance = 2.2,
                    canInteract = function() return S().bay ~= nil end,
                    onSelect = function() CreateThread(Bay.OpenSupplies) end,
                },
            })
        end
    end
    lightsLoop()
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT (lite snapshot for the HUD)
-- ════════════════════════════════════════════════════════════════════════

local function count(t)
    local n = 0
    if type(t) == 'table' then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function lite(s)
    if type(s) ~= 'table' then return nil end
    local inj, surgery = {}, false
    for _, v in ipairs(s.injuries or {}) do
        local t = v.treat or {}
        if (tonumber(v.retained) or 0) > 0 and not t.extracted then surgery = true end
        if v.type == 'internal' and not t.coiled then surgery = true end
        if #inj < 6 then
            inj[#inj + 1] = {
                region = v.region, regionLabel = U.RegionLabel(v.region), type = v.type, typeLabel = U.InjuryLabel(v.type),
                severity = v.severity, status = v.status, bleed = U.round(tonumber(v.bleed) or 0, 1),
            }
        end
    end
    local inf, blood = {}, false
    for _, f in ipairs(s.infusions or {}) do
        if f.kind == 'blood' and not f.paused then blood = true end
        inf[#inf + 1] = {
            kind = f.kind, left = math.floor(tonumber(f.left) or 0), ml = math.floor(tonumber(f.ml) or 0),
            rate = U.round(tonumber(f.rate) or 0, 0), type = type(f.bag) == 'table' and f.bag.type or nil,
            paused = f.paused and true or nil,
        }
    end
    local d = s.devices or {}
    local v = s.vitals or {}
    return {
        name = s.name, sex = s.sex, age = s.age, bloodType = s.bloodType, state = s.state,
        stabilized = s.stabilized == true, clock = s.clock, clockText = s.clockText, triage = s.triage,
        vitals = { hr = v.hr, ecgRate = v.ecgRate, sys = v.sys, dia = v.dia, map = v.map, spo2 = v.spo2, rr = v.rr,
                   temp = v.temp, etco2 = v.etco2, rhythm = v.rhythm, avpu = v.avpu },
        temp = s.temp or v.temp, bleed = U.round(tonumber(s.bleedTotal) or 0, 1), bloodPct = s.bloodPct,
        lossMl = math.max(0, math.floor((tonumber(s.bloodMax) or 5000) - (tonumber(s.blood) or 5000))),
        injuries = inj, injuryCount = #(s.injuries or {}), infusions = inf,
        access = (d.iv ~= nil and d.iv ~= false) or (d.port ~= nil and d.port ~= false),
        devices = {
            iv = type(d.iv) == 'table' and (d.iv.kind or 'iv') or (d.iv and 'iv' or nil),
            intubated = d.intubated and true or nil, oxygen = d.oxygen and true or nil, collar = d.collar and true or nil,
            binder = d.binder and true or nil, foil = d.foil and true or nil, tq = count(d.tourniquet), splints = count(d.splints),
        },
        surgery = surgery, bloodRunning = blood,
    }
end

local function stopWatch()
    local b = S().bay
    if b and b.stopWatch then pcall(b.stopWatch) end
    if b then b.stopWatch, b.watching = nil, nil end
end

local function watchPatient(target)
    local b = S().bay
    if not b then return end
    if b.watching and target and NZA.Target.Same(b.watching, target) then return end
    stopWatch()
    b.patient = target
    if not target then
        NZA.UI.Send(APP, 'patient', false)
        return
    end
    b.watching = target
    b.stopWatch = NZA.Patient.Watch(target, function(snap)
        if not S().bay then return end
        if not snap then
            NZA.UI.Send(APP, 'patient', false)
            return
        end
        NZA.UI.Send(APP, 'patient', lite(snap))
    end, { keep = true })
end

-- ════════════════════════════════════════════════════════════════════════
-- TOOLS (other modules hook in through the bus)
-- ════════════════════════════════════════════════════════════════════════

local function hasHandler(name)
    local list = NZA.Bus.handlers and NZA.Bus.handlers[name]
    return type(list) == 'table' and #list > 0
end

local function tools()
    return {
        examine = NZA.Assess ~= nil and NZA.Assess.Start ~= nil and NZA.Assess.Start.exam ~= nil,
        monitor = true,
        ivstand = hasHandler('bay:ivstand') or (NZA.Blood ~= nil and type(NZA.Blood.OpenStand) == 'function'),
        supplies = bc().supplies ~= nil and bc().supplies.enabled ~= false,
    }
end

-- what other modules get with bay:ivstand / bay:monitor (world positions of the bay fittings)
local function bayInfo()
    local b = S().bay
    if not b then return nil end
    local hooks = {}
    for _, h in ipairs(bc().ivHooks or {}) do
        local w = world(b.slot, vector4(h.x, h.y, h.z, 0.0))
        hooks[#hooks + 1] = vector3(w.x, w.y, w.z)
    end
    local origin = Bay.Origin(b.slot)
    return { veh = b.veh, slot = b.slot, bay = true, origin = origin, hooks = hooks, cot = Bay.CotSpot(b.slot) }
end
Bay.Info = bayInfo

function Bay.Tool(id)
    local b = S().bay
    if not b or b.leaving then return end
    local target = b.patient
    if id == 'exit' then
        if NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() then return Tr.Toast(Tr.L('err_proc'), 'error') end
        CreateThread(function() Bay.Exit(false) end)
    elseif id == 'supplies' then
        CreateThread(Bay.OpenSupplies)
    elseif id == 'examine' then
        if not target then return Tr.Toast(Tr.L('err_no_bay_patient'), 'error') end
        local ent = NZA.Target.Entity(target)
        if ent ~= 0 and NZA.Assess and NZA.Assess.Start and NZA.Assess.Start.exam then
            CreateThread(function() NZA.Assess.Start.exam(ent, target) end)
        else
            Tr.Toast(Tr.L('err_no_tool'), 'error')
        end
    elseif id == 'ivstand' then
        if not target then return Tr.Toast(Tr.L('err_no_bay_patient'), 'error') end
        if NZA.Blood and type(NZA.Blood.OpenStand) == 'function' then
            CreateThread(function() NZA.Blood.OpenStand(target, bayInfo()) end)
        elseif hasHandler('bay:ivstand') then
            NZA.Bus.Emit('bay:ivstand', target, bayInfo())
        else
            Tr.Toast(Tr.L('err_no_tool'), 'error')
        end
    elseif id == 'monitor' then
        if hasHandler('bay:monitor') and target then
            NZA.Bus.Emit('bay:monitor', target, bayInfo())
        else
            b.bigMonitor = not b.bigMonitor
            NZA.UI.Send(APP, 'monitor', { on = b.bigMonitor })
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- HUD
-- ════════════════════════════════════════════════════════════════════════

local function keyLabel(name)
    local k = (bc().keys or {})[name]
    if not k then return '' end
    if k == 'BACK' then return 'BACKSPACE' end
    return tostring(k)
end

local function unitLabel(model)
    if not model then return nil end
    local disp = GetDisplayNameFromVehicleModel(model)
    if not disp or disp == '' or disp == 'CARNOTFOUND' then return nil end
    local txt = GetLabelText(disp)
    if txt and txt ~= 'NULL' and txt ~= '' then return txt end
    return disp
end

local function openHud(res)
    NZA.UI.Open(APP, {
        locale = NZA.LocaleTable('transport'),
        keys = {
            exit = keyLabel('exit'), examine = keyLabel('examine'), supplies = keyLabel('supplies'),
            ivstand = keyLabel('ivstand'), monitor = keyLabel('monitor'),
        },
        unit = { plate = res.plate, label = unitLabel(res.model) },
        crew = res.crew or {}, me = GetPlayerServerId(PlayerId()),
        warnings = bc().warnings or {},
        tools = tools(),
        patient = false,
    }, { focus = false })
end

-- ════════════════════════════════════════════════════════════════════════
-- ENTER / EXIT (medic)
-- ════════════════════════════════════════════════════════════════════════

local function moveNpcIn(net, slot)
    local npc = Tr.Ent(net, 1500)
    if npc == 0 or not Tr.Control(npc, 1500) then return end
    local spot = Bay.PatientSpot(slot)
    DetachEntity(npc, true, false)
    SetEntityCoordsNoOffset(npc, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(npc, spot.w)
    FreezeEntityPosition(npc, true)
    Tr.Play(npc, lyingAnim(), { blendIn = 8.0 })
end

function Bay.Active()
    return S().bay
end

function Bay.Enter(veh)
    local busy = Tr.Busy()
    if busy and not (busy == 'vehicle' and IsPedInVehicle(PlayerPedId(), veh, false)) then
        return Tr.Toast(Tr.L('err_busy'), 'error')
    end
    local vnet = Tr.Net(veh)
    if not vnet then return end
    local ok, res = Tr.Call('bay:enter', vnet)
    if not ok then return Tr.Err(res) end
    local me = PlayerPedId()
    local fade = bc().fadeMs or 550
    local seated = IsPedInVehicle(me, veh, false)
    local from = seated and Tr.Rear(veh, bc().exitBehind or 1.2) or GetEntityCoords(me)
    -- the rear doors open while you climb in from outside
    if not seated and Tr.Control(veh, 400) then
        for _, d in ipairs((Tr.VehCfg(veh) or {}).doors or { 2, 3 }) do SetVehicleDoorOpen(veh, d, false, false) end
    end
    fadeOut(fade)
    if seated then
        TaskLeaveVehicle(me, veh, 16)
        local t = GetGameTimer() + 1500
        while IsPedInAnyVehicle(me, false) and GetGameTimer() < t do Wait(20) end
    end
    S().bay = {
        veh = vnet, slot = res.slot, idx = res.idx, patient = res.patient, str = res.str, plate = res.plate,
        from = vector4(from.x, from.y, from.z, GetEntityHeading(me)), crew = res.crew,
    }
    -- an NPC patient comes with the first medic (move it while it is still streamed in)
    if res.npc then moveNpcIn(res.npc, res.slot) end
    spawnShell(res.slot, true)
    local spot = medicSpot(res.slot, res.idx)
    FreezeEntityPosition(me, true)
    SetEntityCoords(me, spot.x, spot.y, spot.z + 0.05, false, false, false, false)
    SetEntityHeading(me, spot.w)
    local t = GetGameTimer() + 1500
    while GetGameTimer() < t do
        RequestCollisionAtCoord(spot.x, spot.y, spot.z)
        if HasCollisionLoadedAroundEntity(me) then break end
        Wait(50)
    end
    Wait(150)
    FreezeEntityPosition(me, false)
    if bc().hideRadar ~= false then DisplayRadar(false) end
    openHud(res)
    watchPatient(res.patient)
    NZA.Bus.Emit('bay:entered', vnet, res.patient)
    fadeIn(fade)
    if not seated and DoesEntityExist(veh) and Tr.Control(veh, 300) then
        for _, d in ipairs((Tr.VehCfg(veh) or {}).doors or { 2, 3 }) do SetVehicleDoorShut(veh, d, false) end
    end
    Bay.Loop()
end

function Bay.Loop()
    CreateThread(function()
        local nextCheck = 0
        while S().bay do
            local b = S().bay
            local now = GetGameTimer()
            if now >= nextCheck and not b.leaving then
                nextCheck = now + 1000
                -- fell out of the interior (missing model, glitch): put back on the floor
                local me = PlayerPedId()
                local o = Bay.Origin(b.slot)
                local p = GetEntityCoords(me)
                if p.z < o.z - 3.0 or #(vector2(p.x, p.y) - vector2(o.x, o.y)) > 12.0 then
                    local spot = medicSpot(b.slot, b.idx)
                    SetEntityCoords(me, spot.x, spot.y, spot.z + 0.05, false, false, false, false)
                end
                if shell.slot ~= b.slot then spawnShell(b.slot, true) end
            end
            Wait(250)
        end
    end)
end

local function closeHud()
    NZA.UI.Close(APP)
end

function Bay.Exit(kicked, at)
    local b = S().bay
    if not b or b.leaving then return end
    b.leaving = true
    local res = { at = at }
    if not kicked then
        local ok, r = Tr.Call('bay:exit')
        if ok then res = r end
    end
    local fade = bc().fadeMs or 550
    fadeOut(fade)
    closeHud()
    stopWatch()
    local me = PlayerPedId()
    -- last one out takes an NPC patient back to the ambulance
    local npc = 0
    if type(res.returnNpc) == 'table' then
        npc = Tr.Ent(res.returnNpc.net, 800)
        if npc ~= 0 and not Tr.Control(npc, 1000) then npc = 0 end
    end
    local dest = Tr.V4(res.at) or b.from
    FreezeEntityPosition(me, true)
    SetEntityCoords(me, dest.x, dest.y, dest.z, false, false, false, false)
    SetEntityHeading(me, dest.w)
    if npc ~= 0 then
        SetEntityCoordsNoOffset(npc, dest.x, dest.y, dest.z + 0.4, false, false, false)
    end
    clearShell()
    S().bay = nil
    DisplayRadar(true)
    -- the ambulance may have moved on: line up with its doors once it streamed in
    local veh = Tr.Ent(b.veh, 3000)
    local seatedBack = false
    if veh ~= 0 and GetEntitySpeed(veh) > 3.0 then
        -- still driving: take a free passenger seat instead of jumping out on the road
        for _, seat in ipairs({ 1, 2, 0 }) do
            if seat < GetVehicleMaxNumberOfPassengers(veh) and IsVehicleSeatFree(veh, seat) then
                FreezeEntityPosition(me, false)
                SetPedIntoVehicle(me, veh, seat)
                seatedBack = true
                break
            end
        end
    end
    if seatedBack then
        -- nothing else to do
    elseif veh ~= 0 then
        local rear = Tr.Rear(veh, bc().exitBehind or 1.2)
        local gz = Tr.Ground(rear, rear.z - 0.9)
        SetEntityCoords(me, rear.x, rear.y, gz, false, false, false, false)
        SetEntityHeading(me, (GetEntityHeading(veh) + 180.0) % 360.0)
    else
        local gz = Tr.Ground(vector3(dest.x, dest.y, dest.z), dest.z)
        SetEntityCoords(me, dest.x, dest.y, gz, false, false, false, false)
    end
    local t = GetGameTimer() + 1500
    while not HasCollisionLoadedAroundEntity(me) and GetGameTimer() < t do Wait(50) end
    FreezeEntityPosition(me, false)
    if npc ~= 0 then
        local r = res.returnNpc
        local se = r.s and Tr.Ent(r.s, 4000) or 0
        if se ~= 0 and Tr.Control(npc, 1000) then
            FreezeEntityPosition(npc, false)
            Tr.AttachToStretcher(npc, se)
            Tr.Play(npc, lyingAnim(), { blendIn = 8.0 })
        elseif Tr.Control(npc, 500) then
            FreezeEntityPosition(npc, false)
            local p = GetEntityCoords(me)
            SetEntityCoordsNoOffset(npc, p.x + 0.8, p.y, Tr.Ground(p, p.z), false, false, false)
            SetPedToRagdoll(npc, 1500, 1500, 0, false, false, false)
        end
    end
    NZA.Bus.Emit('bay:left', b.veh)
    fadeIn(fade)
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT SIDE (from the nzaTr bag, see transport.lua Tr.Apply)
-- ════════════════════════════════════════════════════════════════════════

function Bay.PlacePatient(ped, cmd, isSelf)
    local slot = tonumber(cmd.slot)
    if not slot then return false end
    local spot = Bay.PatientSpot(slot)
    if isSelf then
        local fade = bc().fadeMs or 550
        fadeOut(fade)
        spawnShell(slot, false)
        if bc().hideRadar ~= false then DisplayRadar(false) end
        S().patientBay = { slot = slot, veh = cmd.v }
    end
    DetachEntity(ped, true, false)
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(ped, spot.w)
    FreezeEntityPosition(ped, true)
    Tr.Play(ped, lyingAnim(), { blendIn = 8.0 })
    if isSelf then
        local t = GetGameTimer() + 1500
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
        fadeIn(bc().fadeMs or 550)
    end
    return true
end

function Bay.EnsurePatient(ped, cmd)
    local slot = tonumber(cmd.slot)
    if not slot then return end
    if shell.slot ~= slot then spawnShell(slot, false) end
    local spot = Bay.PatientSpot(slot)
    if #(GetEntityCoords(ped) - vector3(spot.x, spot.y, spot.z)) > 0.8 then
        SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
        SetEntityHeading(ped, spot.w)
    end
    if not IsEntityPositionFrozen(ped) then FreezeEntityPosition(ped, true) end
    if not Tr.Playing(ped, lyingAnim()) then Tr.Play(ped, lyingAnim()) end
end

function Bay.NpcNeedsFix(ped, bag)
    local slot = tonumber(bag.slot)
    if not slot then return false end
    local spot = Bay.PatientSpot(slot)
    if #(GetEntityCoords(ped) - vector3(spot.x, spot.y, spot.z)) > 0.8 then return true end
    return not IsEntityPositionFrozen(ped) or not Tr.Playing(ped, lyingAnim())
end

-- the patient's own interior (not a medic in the bay)
function Bay.ClearPatientShell()
    if not S().patientBay then return end
    S().patientBay = nil
    if not S().bay then clearShell() end
    DisplayRadar(true)
end

-- out of the bay: back onto the stretcher in the ambulance (or on the ground if it is gone)
function Bay.ReturnFromBay(ped, cmd, isSelf)
    local at = Tr.V4(cmd.at)
    local fade = bc().fadeMs or 550
    if isSelf then
        fadeOut(fade)
        if not S().bay then clearShell() end
        S().patientBay = nil
        DisplayRadar(true)
    end
    FreezeEntityPosition(ped, false)
    DetachEntity(ped, true, false)
    if at then SetEntityCoordsNoOffset(ped, at.x, at.y, at.z + 0.4, false, false, false) end
    if cmd.m == 'str' then
        local se = Tr.Ent(cmd.s, 5000)
        if se ~= 0 then
            Tr.AttachToStretcher(ped, se)
            Tr.Play(ped, lyingAnim(), { blendIn = 8.0 })
        end
    elseif at then
        local gz = Tr.Ground(vector3(at.x, at.y, at.z), at.z)
        SetEntityCoordsNoOffset(ped, at.x, at.y, gz + 0.1, false, false, false)
        Tr.StopAnim(ped, lyingAnim())
        if not isSelf then SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false) end
    end
    if isSelf then
        local t = GetGameTimer() + 1500
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
        fadeIn(fade)
    end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- SUPPLIES
-- ════════════════════════════════════════════════════════════════════════

local function withImages(list)
    if type(list) ~= 'table' then return list end
    for _, it in ipairs(list.items or {}) do
        if Bridge and Bridge.Inv and Bridge.Inv.Image then
            local ok, img = pcall(Bridge.Inv.Image, it.name)
            if ok then it.img = img end
        end
    end
    return list
end

function Bay.OpenSupplies()
    local b = S().bay
    if not b or b.leaving then return end
    local ok, res = Tr.Call('bay:supplies')
    if not ok then return Tr.Err(res) end
    b.supplies = true
    NZA.UI.Send(APP, 'supplies', withImages(res))
    NZA.UI.SetFocus(APP, { focus = true, cursor = true })
end

local function closeSupplies()
    local b = S().bay
    if b then b.supplies = false end
    if NZA.UI.IsOpen(APP) then NZA.UI.SetFocus(APP, { focus = false }) end
end

NZA.UI.On(APP, 'take', function(data, cb)
    if not S().bay or type(data) ~= 'table' then return cb({ ok = false }) end
    local ok, res = Tr.Call('bay:take', tostring(data.key or ''), tonumber(data.count) or 1)
    if not ok then return cb({ ok = false, msg = res.msg }) end
    Tr.Toast(res.msg, 'success')
    cb({ ok = true, list = withImages(res.list) })
end)

NZA.UI.On(APP, 'supplies', function(_, cb)
    cb({ ok = true })
    closeSupplies()
end)

NZA.UI.On(APP, 'action', function(data, cb)
    cb({ ok = true })
    if type(data) == 'table' and type(data.id) == 'string' then
        if data.id ~= 'supplies' then closeSupplies() end
        Bay.Tool(data.id)
    end
end)

-- the HUD was closed from the page (should not happen): bring it back while inside
NZA.Bus.On('ui:closed', function(app)
    if app ~= APP then return end
    local b = S().bay
    if b and not b.leaving then
        CreateThread(function()
            Wait(100)
            if not S().bay then return end
            openHud({ plate = b.plate, crew = b.crew })
            local target = b.patient
            b.watching = nil
            watchPatient(target)
        end)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:transport:bay:crew', function(payload)
    local b = S().bay
    if not b or type(payload) ~= 'table' then return end
    b.crew = payload.crew or {}
    NZA.UI.Send(APP, 'crew', b.crew)
    if payload.patient and not (b.watching and NZA.Target.Same(b.watching, payload.patient)) then
        watchPatient(payload.patient)
    end
end)

RegisterNetEvent('nza:transport:bay:tick', function(data)
    if not S().bay or type(data) ~= 'table' then return end
    if data.plate then S().bay.plate = data.plate end
    NZA.UI.Send(APP, 'tick', { speed = tonumber(data.speed) or 0, plate = data.plate })
end)

RegisterNetEvent('nza:transport:bay:kick', function(data)
    if not S().bay then return end
    CreateThread(function() Bay.Exit(true, type(data) == 'table' and data.at or nil) end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- KEYS
-- ════════════════════════════════════════════════════════════════════════

local function bind(cmd, label, key, fn)
    RegisterCommand(cmd, function()
        if not S().bay or S().bay.leaving or IsPauseMenuActive() then return end
        if S().bay.supplies and cmd ~= 'nza_bay_supplies' then return end
        fn()
    end, false)
    if key and key ~= '' then RegisterKeyMapping(cmd, label, 'keyboard', key) end
end

do
    local keys = (Config.Transport and Config.Transport.Bay and Config.Transport.Bay.keys) or {}
    bind('nza_bay_exit', NZA.L('transport.bay_exit'), keys.exit or 'BACK', function() Bay.Tool('exit') end)
    bind('nza_bay_examine', NZA.L('transport.examine'), keys.examine or 'F1', function() Bay.Tool('examine') end)
    bind('nza_bay_supplies', NZA.L('transport.supplies'), keys.supplies or 'F2', function()
        if S().bay.supplies then
            NZA.UI.Send(APP, 'suppliesClose', {})
            closeSupplies()
        else
            Bay.Tool('supplies')
        end
    end)
    bind('nza_bay_ivstand', NZA.L('transport.ivstand'), keys.ivstand or 'F3', function() Bay.Tool('ivstand') end)
    bind('nza_bay_monitor', NZA.L('transport.monitor'), keys.monitor or 'F4', function() Bay.Tool('monitor') end)
end

-- ════════════════════════════════════════════════════════════════════════
-- AMBULANCE TARGET + RADIAL
-- ════════════════════════════════════════════════════════════════════════

local function canEnter(veh)
    local c = bc()
    if c.enabled == false or not NZA.Perm(c.perm or Tr.Cfg().perm or 'transport') then return false end
    local vc = Tr.VehCfg(veh)
    if not vc or vc.bay == false then return false end
    local me = PlayerPedId()
    if IsPedInVehicle(me, veh, false) then
        -- passenger of this ambulance: climb into the back (the driver keeps driving)
        return GetPedInVehicleSeat(veh, -1) ~= me and not S().bay and not S().carrying and not S().pushing
            and (not NZA.Self or NZA.Self.State() == 'alive')
    end
    if Tr.Busy() then return false end
    if GetEntitySpeed(veh) > (c.maxEnterSpeed or 1.5) then return false end
    return Tr.NearRear(veh, c.rearReach or 2.3)
end

CreateThread(function()
    Wait(600)
    if not Bridge or not Bridge.Target then return end
    local names = {}
    for name, vc in pairs(Tr.Cfg('Stretcher').vehicles or {}) do
        if vc.bay ~= false then names[#names + 1] = name end
    end
    if #names == 0 then return end
    Bridge.Target.Model(names, {
        {
            name = 'nza_amb_bay', label = Tr.L('bay_enter'), icon = 'door', distance = 6.0, order = 5,
            canInteract = function(veh) return canEnter(veh) end,
            onSelect = function(veh) CreateThread(function() Bay.Enter(veh) end) end,
        },
    })
end)

NZA.RadialItems = NZA.RadialItems or {}

local function bayVehicle()
    local me = PlayerPedId()
    local cur = GetVehiclePedIsIn(me, false)
    if cur ~= 0 and canEnter(cur) then return cur end
    local pos = GetEntityCoords(me)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(pos - GetEntityCoords(veh)) < 12.0 and canEnter(veh) then return veh end
    end
    return nil
end

table.insert(NZA.RadialItems, {
    id = 'tr_bay_enter', parent = 'stretcher', label = Tr.L('bay_enter'), icon = 'door', order = 8,
    perm = (Config.Transport and Config.Transport.Bay and Config.Transport.Bay.perm) or 'transport',
    canShow = function() return Tr.Cfg().radial ~= false and bayVehicle() ~= nil end,
    onSelect = function()
        CreateThread(function()
            local veh = bayVehicle()
            if veh then Bay.Enter(veh) end
        end)
    end,
})

table.insert(NZA.RadialItems, {
    id = 'tr_bay_exit', label = Tr.L('bay_exit'), icon = 'logout', order = 90,
    canShow = function() return S().bay ~= nil and not S().bay.leaving end,
    onSelect = function() Bay.Tool('exit') end,
})

table.insert(NZA.RadialItems, {
    id = 'tr_bay_supplies', label = Tr.L('supplies'), icon = 'box', order = 91,
    canShow = function() return S().bay ~= nil and not S().bay.leaving and tools().supplies end,
    onSelect = function() Bay.Tool('supplies') end,
})

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local b = S().bay
    local me = PlayerPedId()
    if b then
        S().bay = nil
        closeHud()
        if b.from then
            SetEntityCoords(me, b.from.x, b.from.y, b.from.z, false, false, false, false)
            SetEntityHeading(me, b.from.w)
        end
    end
    if S().patientBay then
        S().patientBay = nil
        FreezeEntityPosition(me, false)
    end
    if shell.slot then
        clearShell()
        DisplayRadar(true)
        FreezeEntityPosition(me, false)
        if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(300) end
    end
end)
