--[[
    NAYZEEE AMBULANCE - Hospitals (client): position types, blips and what each position does

    Position types registered here (NZA.Points.RegisterType, ARCHITECTURE §8):
      duty      go on / off duty                     locker   department outfits + civilian clothes
      stash     department storage                   boss     boss menu (manager, own department)
      storage   supply cabinet (per-shift limits)    garage   vehicle spawn (ghost car while placing)
      heli      helipad spawn (ghost helicopter)      elevator linked floors (same "group") → fade teleport
      bed       lie down to heal ×4                   respawn  where the dead wake up (NZA.Hospitals.RespawnPoint)
      hq        department HQ (blip; placed from the manager's HQ card, never a stored point)
    Every option checks the player's department on the client for the menu; the server checks
    it again (server/modules/hospital_runtime.lua).

    Small menus (locker, stash, supply cabinet, garage, elevator) use the 'manager' NUI app in
    its compact modes. NUI callbacks: manager:wear, manager:civvies, manager:take,
    manager:spawn, manager:floor, manager:stashMove.

    Client API (other modules, runtime only)
      NZA.Hospitals.Departments() → { [id] = public department }   NZA.Hospitals.Department(id)
      NZA.Hospitals.ToggleDuty(on?, pointId?) → ok, onDuty         NZA.Hospitals.InBed() → pointId | nil
    Internals for hospital_builder.lua / hospital_manager.lua: NZA.HospitalC
    Net events handled: nza:hospital:depts
    Net events sent: nza:hospital:ready
    Callbacks used: nza:hospital:duty, :locker, :stash, :stash:move, :storage, :storage:take,
                    :garage, :garage:spawn, :garage:store, :bed
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Hospitals = NZA.Hospitals or {}
NZA.HospitalC = NZA.HospitalC or {}
local H = NZA.Hospitals
local C = NZA.HospitalC

local depts = {}          -- [id] = { id, label, job, hq, blip, vehicles }
local blips = {}          -- [deptId] = blip handle
local myVehicles = {}     -- [netId] = { dept, point, plate }
local compact = nil       -- { mode, point }  open compact menu
local lying = nil         -- { point, token }

C.depts = depts

local function hc(key, default)
    local c = Config.Hospital
    if c and c[key] ~= nil then return c[key] end
    return default
end
C.cfg = hc

local function L(key, ...) return NZA.L('hospital.' .. key, ...) end
C.L = L

local function toast(msg, kind, title)
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info' })
end
C.toast = toast

local function reply(res)
    if type(res) ~= 'table' then return { ok = false, msg = L('err_failed') } end
    return res
end

local function call(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok then return { ok = false, msg = L('err_failed') } end
    return reply(res)
end
C.call = call

local function failToast(res)
    if res and res.msg and res.err ~= 'rate' then toast(res.msg, 'error') end
end
C.failToast = failToast

-- ════════════════════════════════════════════════════════════════════════
-- WHO AM I
-- ════════════════════════════════════════════════════════════════════════

local function rec()
    return NZA.Staff.Get() or {}
end
C.rec = rec

local function memberOf(point)
    local r = rec()
    return r.dept ~= nil and point ~= nil and r.dept == point.hospital
end

local function onDutyMember(point)
    return memberOf(point) and rec().onDuty == true
end

function C.Gender()
    local model = GetEntityModel(PlayerPedId())
    if model == joaat('mp_m_freemode_01') then return 'male' end
    if model == joaat('mp_f_freemode_01') then return 'female' end
    return nil
end

function H.Departments() return depts end
function H.Department(id) return depts[id] end

-- ════════════════════════════════════════════════════════════════════════
-- BLIPS
-- ════════════════════════════════════════════════════════════════════════

local function clearBlips()
    for id, b in pairs(blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
        blips[id] = nil
    end
end

local function buildBlips()
    clearBlips()
    for id, d in pairs(depts) do
        local b = d.blip
        if d.hq and b and b.enabled ~= false then
            local blip = AddBlipForCoord(d.hq.x + 0.0, d.hq.y + 0.0, d.hq.z + 0.0)
            SetBlipSprite(blip, tonumber(b.sprite) or 61)
            SetBlipColour(blip, tonumber(b.colour) or 1)
            SetBlipScale(blip, (tonumber(b.scale) or 0.85) + 0.0)
            SetBlipAsShortRange(blip, b.shortRange ~= false)
            SetBlipDisplay(blip, 4)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label or d.label or id)
            EndTextCommandSetBlipName(blip)
            blips[id] = blip
        end
    end
end

RegisterNetEvent('nza:hospital:depts', function(list)
    if type(list) ~= 'table' then return end
    for k in pairs(depts) do depts[k] = nil end
    for _, d in ipairs(list) do
        if type(d) == 'table' and d.id then depts[d.id] = d end
    end
    buildBlips()
    NZA.Bus.Emit('hospital:depts', depts)
end)

-- ════════════════════════════════════════════════════════════════════════
-- DUTY
-- ════════════════════════════════════════════════════════════════════════

function H.ToggleDuty(on, pointId)
    local res = call('nza:hospital:duty', { point = pointId, on = on })
    if not res.ok then
        failToast(res)
        return false
    end
    if not res.onDuty and hc('duty', {}).offDutyCivvies and Bridge.Clothing and Bridge.Clothing.HasSaved and Bridge.Clothing.HasSaved() then
        Bridge.Clothing.Restore()
    end
    NZA.Staff.Refresh()
    return true, res.onDuty
end

-- ════════════════════════════════════════════════════════════════════════
-- COMPACT MENUS (manager app, small window)
-- ════════════════════════════════════════════════════════════════════════

local function openCompact(mode, point, data)
    compact = { mode = mode, point = point }
    data.mode = mode
    data.compact = true
    data.locale = NZA.LocaleTable('hospital')
    data.point = point and { id = point.id, type = point.type, label = point.label, hospital = point.hospital } or nil
    local d = point and depts[point.hospital]
    data.dept = d and d.label or nil
    NZA.UI.Open('manager', data, { focus = true, cursor = true })
end

local function compactPoint(mode)
    if not compact or compact.mode ~= mode then return nil end
    return compact.point
end

NZA.Bus.On('ui:closed', function(app)
    if app == 'manager' then compact = nil end
end)

-- ── LOCKER ───────────────────────────────────────────────────────────────

local outfitsCache = {}

function C.ApplyOutfit(data)
    local ped = PlayerPedId()
    if type(data) ~= 'table' then return false end
    for _, c in ipairs(data.components or {}) do
        local id, d, t = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
        if id and d then SetPedComponentVariation(ped, id, d, t or 0, 0) end
    end
    for _, p in ipairs(data.props or {}) do
        local id, d, t = tonumber(p[1]), tonumber(p[2]), tonumber(p[3])
        if id and d then
            if d < 0 then ClearPedProp(ped, id) else SetPedPropIndex(ped, id, d, t or 0, true) end
        end
    end
    return true
end

function C.CaptureOutfit()
    local ped = PlayerPedId()
    local lk = hc('locker', {})
    local data = { components = {}, props = {} }
    for _, id in ipairs(lk.components or { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }) do
        data.components[#data.components + 1] = { id, GetPedDrawableVariation(ped, id), GetPedTextureVariation(ped, id) }
    end
    for _, id in ipairs(lk.props or { 0, 1, 2, 6, 7 }) do
        data.props[#data.props + 1] = { id, GetPedPropIndex(ped, id), math.max(0, GetPedPropTextureIndex(ped, id)) }
    end
    return data
end

local function changeAnim()
    local a = hc('locker', {}).anim
    if type(a) ~= 'table' or not a.dict then return end
    local ped = PlayerPedId()
    NZA.Anim.Play(ped, a.dict, a.clip, { flag = 48, duration = a.time or 1800 })
    Wait(a.time or 1800)
    NZA.Anim.Stop(ped, { immediate = true })
end

function C.Wear(data)
    if not data then return false end
    if Bridge.Clothing and Bridge.Clothing.HasSaved and not Bridge.Clothing.HasSaved() then
        Bridge.Clothing.Save()
    end
    changeAnim()
    return C.ApplyOutfit(data)
end

function C.Civvies()
    if not (Bridge.Clothing and Bridge.Clothing.HasSaved and Bridge.Clothing.HasSaved()) then return false end
    changeAnim()
    return Bridge.Clothing.Restore() ~= false
end

local function openLocker(point)
    local res = call('nza:hospital:locker', point.id)
    if not res.ok then return failToast(res) end
    outfitsCache = {}
    local gender = C.Gender()
    local list = {}
    for _, o in ipairs(res.outfits or {}) do
        outfitsCache[o.id] = o
        list[#list + 1] = {
            id = o.id, name = o.name, grades = o.grades,
            male = o.male ~= nil, female = o.female ~= nil,
            fits = gender ~= nil and o[gender] ~= nil,
        }
    end
    openCompact('locker', point, {
        outfits = list, gender = gender, grade = res.grade, grades = res.grades,
        civvies = Bridge.Clothing and Bridge.Clothing.HasSaved and Bridge.Clothing.HasSaved() or false,
    })
end

NZA.UI.On('manager', 'wear', function(data, cb)
    local point = compactPoint('locker')
    local o = point and outfitsCache[data and data.id]
    local gender = C.Gender()
    if not o or not gender or not o[gender] then
        cb({ ok = false, msg = gender and L('err_no_gender_outfit') or L('err_no_freemode') })
        return
    end
    cb({ ok = true })
    NZA.UI.Close('manager')
    compact = nil
    if C.Wear(o[gender]) then toast(L('wearing', o.name), 'success') end
end)

NZA.UI.On('manager', 'civvies', function(_, cb)
    cb({ ok = true })
    NZA.UI.Close('manager')
    compact = nil
    if C.Civvies() then toast(L('civvies_on'), 'success') else toast(L('err_no_civvies'), 'error') end
end)

-- ── STASH ────────────────────────────────────────────────────────────────

local function openStash(point)
    local res = call('nza:hospital:stash', point.id)
    if not res.ok then return failToast(res) end
    if res.mode == 'ox' then
        local ok = pcall(function() exports.ox_inventory:openInventory('stash', res.id) end)
        if not ok then toast(L('err_failed'), 'error') end
    elseif res.mode == 'qbold' then
        -- classic stash event (qb-inventory 1.x, lj, qs; the server never picks it for ps-inventory)
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', res.id, { maxweight = res.weight, slots = res.slots })
        TriggerEvent('inventory:client:SetCurrentStash', res.id)
    elseif res.mode == 'own' then
        openCompact('stash', point, { title = res.label, items = res.items, inv = res.inv, max = res.max })
    end
end

NZA.UI.On('manager', 'stashMove', function(data, cb)
    local point = compactPoint('stash')
    if not point or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end
    local res = call('nza:hospital:stash:move', {
        point = point.id, dir = data.dir, slot = data.slot, index = data.index, name = data.name, count = data.count,
    })
    cb(res)
end)

-- ── SUPPLY OFFICER (medical bag + supplies) ─────────────────────────────

local greetOfficer
local function openStorage(point)
    if greetOfficer then greetOfficer(point) end
    local res = call('nza:hospital:storage', point.id)
    if not res.ok then return failToast(res) end
    openCompact('storage', point, { items = res.items })
end

-- the supply officer: an NPC standing at the supply point (Config.Hospital.storage.npc)
local officers = {}       -- [pointId] = ped | false (loading)

local function removeOfficer(id)
    local ped = officers[id]
    officers[id] = nil
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
end

local function spawnOfficer(point)
    local nc = (hc('storage', {}).npc) or {}
    if nc.enabled == false or (type(point.data) == 'table' and point.data.npc == false) then return end
    if officers[point.id] ~= nil then return end
    officers[point.id] = false
    CreateThread(function()
        local models = {}
        for _, m in ipairs(nc.models or { 's_m_m_paramedic_01' }) do models[#models + 1] = m end
        local hash
        for i = 0, #models - 1 do
            local h = joaat(models[((tonumber(point.id) or 0) + i) % #models + 1])
            if IsModelInCdimage(h) and IsModelAPed(h) then hash = h break end
        end
        if not hash then officers[point.id] = nil return end
        local ok = pcall(lib.requestModel, hash, 8000)
        if not ok or not HasModelLoaded(hash) or officers[point.id] ~= false or not NZA.Points.Get(point.id) then
            if officers[point.id] == false then officers[point.id] = nil end
            return
        end
        local c = point.coords
        local x, y, z, h = (tonumber(c.x) or 0.0) + 0.0, (tonumber(c.y) or 0.0) + 0.0, (tonumber(c.z) or 0.0) + 0.0, (tonumber(c.w or c.h) or 0.0) + 0.0
        local ped = CreatePed(4, hash, x, y, z, h, false, true)
        SetModelAsNoLongerNeeded(hash)
        if not ped or ped == 0 then officers[point.id] = nil return end
        if officers[point.id] ~= false or not NZA.Points.Get(point.id) then DeleteEntity(ped) return end
        officers[point.id] = ped
        SetEntityAsMissionEntity(ped, true, true)
        SetEntityHeading(ped, h)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        SetEntityCanBeDamaged(ped, false)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDiesWhenInjured(ped, false)
        SetPedCanBeTargetted(ped, false)
        SetPedKeepTask(ped, true)
        SetPedConfigFlag(ped, 17, true)
        FreezeEntityPosition(ped, true)
        if type(nc.scenario) == 'string' and nc.scenario ~= '' then TaskStartScenarioInPlace(ped, nc.scenario, 0, true) end
    end)
end

greetOfficer = function(point)
    local ped = officers[point.id]
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    PlayPedAmbientSpeechNative(ped, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
end

NZA.UI.On('manager', 'take', function(data, cb)
    local point = compactPoint('storage')
    if not point or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end
    cb(call('nza:hospital:storage:take', { point = point.id, key = data.key, count = data.count }))
end)

-- ── GARAGE / HELIPAD ─────────────────────────────────────────────────────

local function vehicleFromNet(net, timeout)
    local t = GetGameTimer()
    while not NetworkDoesNetworkIdExist(net) and GetGameTimer() - t < (timeout or 4000) do Wait(25) end
    if not NetworkDoesNetworkIdExist(net) then return 0 end
    local veh = NetToVeh(net)
    while (veh == 0 or not DoesEntityExist(veh)) and GetGameTimer() - t < (timeout or 4000) do
        Wait(25)
        veh = NetToVeh(net)
    end
    return veh
end

local function control(ent)
    local t = GetGameTimer()
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() - t < 1500 do
        Wait(25)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

local function setupVehicle(veh, res)
    control(veh)
    SetVehicleOnGroundProperly(veh)
    SetVehicleModKit(veh, 0)
    local livery = tonumber(res.livery) or -1
    if livery >= 0 then
        if GetVehicleLiveryCount(veh) > 0 then
            SetVehicleLivery(veh, livery)
        else
            SetVehicleMod(veh, 48, livery, false)
        end
    end
    if type(res.extras) == 'table' and #res.extras > 0 then
        local on = {}
        for _, e in ipairs(res.extras) do on[tonumber(e) or -1] = true end
        for i = 0, 20 do
            if DoesExtraExist(veh, i) then SetVehicleExtra(veh, i, not on[i]) end
        end
    end
    local colour = tonumber(res.colour) or -1
    if colour >= 0 then SetVehicleColours(veh, colour, colour) end
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleNumberPlateText(veh, res.plate)
    if Bridge.Vehicle then
        if Bridge.Vehicle.SetFuel then pcall(Bridge.Vehicle.SetFuel, veh, (tonumber(res.fuel) or 100.0) + 0.0) end
        if Bridge.Vehicle.GiveKeys then pcall(Bridge.Vehicle.GiveKeys, veh, res.plate) end
    end
    if res.warp then
        local ped = PlayerPedId()
        TaskWarpPedIntoVehicle(ped, veh, -1)
    end
end

local function openGarage(point)
    local res = call('nza:hospital:garage', point.id)
    if not res.ok then return failToast(res) end
    openCompact('garage', point, { vehicles = res.vehicles, out = res.out, max = res.max, kind = res.kind })
end

NZA.UI.On('manager', 'spawn', function(data, cb)
    local point = compactPoint('garage')
    if not point or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end
    local res = call('nza:hospital:garage:spawn', { point = point.id, id = data.id })
    cb({ ok = res.ok, msg = res.msg })
    if not res.ok then return end
    NZA.UI.Close('manager')
    compact = nil
    local veh = vehicleFromNet(res.net)
    if veh == 0 then return toast(L('err_spawn_failed'), 'error') end
    myVehicles[res.net] = { dept = point.hospital, point = point.id, plate = res.plate }
    setupVehicle(veh, res)
    toast(L('spawned', res.label or ''), 'success')
end)

local function storeVehicle(point, veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local net = VehToNet(veh)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) == veh then
        TaskLeaveVehicle(ped, veh, 0)
        local t = GetGameTimer()
        while IsPedInVehicle(ped, veh, false) and GetGameTimer() - t < 3000 do Wait(50) end
    end
    local res = call('nza:hospital:garage:store', { point = point.id, net = net })
    if not res.ok then return failToast(res) end
    myVehicles[net] = nil
    toast(res.msg or L('stored'), 'success')
end

-- the department vehicle closest to a garage point (yours or a colleague's)
local function nearDeptVehicle(point, radius)
    local pos = vector3(point.coords.x, point.coords.y, point.coords.z)
    local ped = PlayerPedId()
    local inside = GetVehiclePedIsIn(ped, false)
    if inside ~= 0 and #(GetEntityCoords(inside) - pos) <= radius then return inside end
    local best, bestD = nil, radius
    for net in pairs(myVehicles) do
        if NetworkDoesNetworkIdExist(net) then
            local veh = NetToVeh(net)
            if veh ~= 0 and DoesEntityExist(veh) then
                local d = #(GetEntityCoords(veh) - pos)
                if d <= bestD then best, bestD = veh, d end
            end
        else
            myVehicles[net] = nil
        end
    end
    return best
end

-- driving a department vehicle up to a garage / helipad: [E] Store vehicle
CreateThread(function()
    local shown = false
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local target = nil
        if veh ~= 0 and next(myVehicles) and GetPedInVehicleSeat(veh, -1) == ped and NetworkGetEntityIsNetworked(veh) and myVehicles[VehToNet(veh)] then
            local r = (hc('garage', {}).storeRadius) or 12.0
            for _, kind in ipairs({ 'garage', 'heli' }) do
                local pt, dist = NZA.Points.Nearest(kind, GetEntityCoords(veh), r)
                if pt and memberOf(pt) and dist then target = pt; break end
            end
        end
        if target then
            sleep = 0
            if not shown then
                NZA.UI.Prompt('nza_hospital_store', { key = 'E', label = L('store_vehicle'), sub = depts[target.hospital] and depts[target.hospital].label or nil })
                shown = true
            end
            if IsControlJustPressed(0, 38) then
                NZA.UI.HidePrompt('nza_hospital_store')
                shown = false
                storeVehicle(target, veh)
                Wait(500)
            end
        elseif shown then
            NZA.UI.HidePrompt('nza_hospital_store')
            shown = false
        end
        Wait(sleep)
    end
end)

-- ── ELEVATOR ─────────────────────────────────────────────────────────────

local function floorsOf(point)
    local group = tostring((point.data and point.data.group) or 'main')
    local out = {}
    for _, p in ipairs(NZA.Points.All('elevator')) do
        if p.hospital == point.hospital and tostring((p.data and p.data.group) or 'main') == group then
            out[#out + 1] = p
        end
    end
    table.sort(out, function(a, b)
        local oa, ob = tonumber(a.data and a.data.order) or 0, tonumber(b.data and b.data.order) or 0
        if oa ~= ob then return oa > ob end
        return a.id < b.id
    end)
    return out
end

local function openElevator(point)
    local list = {}
    for _, p in ipairs(floorsOf(point)) do
        list[#list + 1] = {
            id = p.id, label = (p.data and p.data.floor) or p.label or L('floor_n', tonumber(p.data and p.data.order) or 0),
            order = tonumber(p.data and p.data.order) or 0, current = p.id == point.id,
        }
    end
    if #list < 2 then return toast(L('err_no_floors'), 'error') end
    openCompact('elevator', point, { floors = list, group = (point.data and point.data.group) or 'main' })
end

function C.Teleport(coords, heading)
    local ped = PlayerPedId()
    local fade = (hc('elevator', {}).fade) or 450
    DoScreenFadeOut(fade)
    local t = GetGameTimer()
    while not IsScreenFadedOut() and GetGameTimer() - t < fade + 600 do Wait(10) end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false, false)
    if heading then SetEntityHeading(ped, heading + 0.0) end
    t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() - t < 3000 do Wait(20) end
    Wait(150)
    DoScreenFadeIn(fade)
end

NZA.UI.On('manager', 'floor', function(data, cb)
    local point = compactPoint('elevator')
    local target = data and NZA.Points.Get(tonumber(data.id) or data.id)
    if not point or not target or target.type ~= 'elevator' or target.hospital ~= point.hospital
        or tostring((target.data and target.data.group) or 'main') ~= tostring((point.data and point.data.group) or 'main') then
        cb({ ok = false })
        return
    end
    cb({ ok = true })
    NZA.UI.Close('manager')
    compact = nil
    local me = GetEntityCoords(PlayerPedId())
    if #(me - vector3(point.coords.x, point.coords.y, point.coords.z)) > 6.0 then return end
    C.Teleport(target.coords, target.coords.w)
end)

-- ── BEDS ─────────────────────────────────────────────────────────────────

function H.InBed()
    return lying and lying.point or nil
end

local function getUp(silent)
    if not lying then return end
    local state = lying
    lying = nil
    NZA.UI.HidePrompt('nza_hospital_bed')
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    NZA.Anim.Stop(ped, { immediate = true })
    ClearPedTasks(ped)
    local pt = NZA.Points.Get(state.point)
    if pt then
        local h = math.rad((pt.coords.w or 0.0) + 90.0)
        local side = (hc('bed', {}).exitSide) or 1.1
        SetEntityCoords(ped, pt.coords.x - math.sin(h) * side, pt.coords.y + math.cos(h) * side, pt.coords.z, false, false, false, false)
    end
    CreateThread(function() call('nza:hospital:bed', { point = state.point, on = false }) end)
    if not silent then toast(L('bed_up'), 'info') end
end

local function lieDown(point)
    if lying then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    local res = call('nza:hospital:bed', { point = point.id, on = true })
    if not res.ok then return failToast(res) end
    local bc = hc('bed', {})
    local c = point.coords
    local at = vector4(c.x + 0.0, c.y + 0.0, c.z + 0.0, (c.w or 0.0) + 0.0)
    -- on the mattress, not in it (the transport module finds the top and lifts the body onto it)
    local spot = NZA.Transport and NZA.Transport.BedSpot and NZA.Transport.BedSpot(at, 'bed', ped) or at
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z + (bc.zOffset or 0.0), false, false, false)
    SetEntityHeading(ped, (c.w or 0.0) + 0.0)
    FreezeEntityPosition(ped, true)
    local ok, token = NZA.Anim.Play(ped, bc.dict or 'anim@gangops@morgue@table@', bc.clip or 'body_search', { flag = 1 })
    lying = { point = point.id, token = ok and token or nil }
    NZA.UI.Prompt('nza_hospital_bed', { key = bc.getUpKey or 'X', label = L('bed_get_up'), sub = L('bed_resting') })
    CreateThread(function()
        while lying and lying.point == point.id do
            if IsControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 73) then
                getUp()
                break
            end
            local st = NZA.Self.State()
            if st ~= 'alive' or not NZA.Points.Get(point.id) then
                getUp(true)
                break
            end
            if lying and lying.token and not IsEntityPlayingAnim(ped, bc.dict or 'anim@gangops@morgue@table@', bc.clip or 'body_search', 3) then
                NZA.Anim.Play(ped, bc.dict or 'anim@gangops@morgue@table@', bc.clip or 'body_search', { flag = 1 })
            end
            Wait(0)
        end
    end)
end

NZA.Bus.On('self:revived', function() if lying then getUp(true) end end)

-- ════════════════════════════════════════════════════════════════════════
-- POSITION TYPES
-- ════════════════════════════════════════════════════════════════════════

local function opt(label, icon, canInteract, onSelect, extra)
    local o = { label = label, icon = icon, canInteract = canInteract, onSelect = onSelect }
    if extra then for k, v in pairs(extra) do o[k] = v end end
    return o
end

NZA.Points.RegisterType('duty', {
    label = L('type_duty'), icon = 'clock', radius = 1.0, desc = L('type_duty_desc'),
    target = {
        opt(L('go_on_duty'), 'clock', function(p) return memberOf(p) and not rec().onDuty end,
            function(p) H.ToggleDuty(true, p.id) end, { name = 'on' }),
        opt(L('go_off_duty'), 'clock', function(p) return memberOf(p) and rec().onDuty == true end,
            function(p) H.ToggleDuty(false, p.id) end, { name = 'off' }),
    },
})

NZA.Points.RegisterType('locker', {
    label = L('type_locker'), icon = 'shirt', radius = 1.0, desc = L('type_locker_desc'),
    target = { opt(L('open_locker'), 'shirt', function(p) return memberOf(p) end, openLocker, { name = 'open' }) },
})

NZA.Points.RegisterType('stash', {
    label = L('type_stash'), icon = 'box', radius = 1.0, desc = L('type_stash_desc'),
    data = { slots = (hc('stash', {}).slots) or 80, weight = (hc('stash', {}).weight) or 250000, personal = false, minGrade = 0 },
    target = { opt(L('open_stash'), 'box', function(p) return onDutyMember(p) end, openStash, { name = 'open' }) },
})

NZA.Points.RegisterType('boss', {
    label = L('type_boss'), icon = 'crown', radius = 1.0, desc = L('type_boss_desc'),
    target = {
        opt(L('open_boss'), 'crown', function(p) return memberOf(p) and rec().isBoss == true end,
            function(p) if C.OpenManager then C.OpenManager('boss', p.id) end end, { name = 'open' }),
    },
})

NZA.Points.RegisterType('storage', {
    label = L('type_storage'), icon = 'medkit', radius = 1.0, desc = L('type_storage_desc'), needsHeading = true,
    data = { npc = true },
    onSpawn = function(p) spawnOfficer(p) end,
    onRemove = function(p) removeOfficer(p.id) end,
    target = { opt(L('open_storage'), 'medkit', function(p) return onDutyMember(p) end, openStorage, { name = 'open' }) },
})

local function garageType(name, icon, ghost)
    NZA.Points.RegisterType(name, {
        label = L('type_' .. name), icon = icon, radius = ghost == 'heli' and 3.5 or 2.5, ghost = ghost,
        desc = L('type_' .. name .. '_desc'), distance = 3.0,
        target = {
            opt(L(name == 'heli' and 'open_helipad' or 'open_garage'), icon,
                function(p) return onDutyMember(p) and not IsPedInAnyVehicle(PlayerPedId(), false) end, openGarage, { name = 'open' }),
            opt(L('store_vehicle'), 'garage',
                function(p) return onDutyMember(p) and nearDeptVehicle(p, (hc('garage', {}).storeRadius) or 12.0) ~= nil end,
                function(p) storeVehicle(p, nearDeptVehicle(p, (hc('garage', {}).storeRadius) or 12.0)) end, { name = 'store' }),
        },
    })
end
garageType('garage', 'car', 'car')
garageType('heli', 'heli', 'heli')

NZA.Points.RegisterType('elevator', {
    label = L('type_elevator'), icon = 'building', radius = 1.0, desc = L('type_elevator_desc'),
    data = { group = 'main', floor = L('floor_default'), order = 0, staffOnly = false },
    target = {
        opt(L('use_elevator'), 'building', function(p)
            return not (p.data and p.data.staffOnly) or memberOf(p)
        end, openElevator, { name = 'use' }),
    },
})

NZA.Points.RegisterType('bed', {
    label = L('type_bed'), icon = 'bed', radius = 1.1, desc = L('type_bed_desc'),
    target = {
        opt(L('bed_lie'), 'bed', function() return lying == nil and not IsPedInAnyVehicle(PlayerPedId(), false) end, lieDown, { name = 'lie' }),
    },
})

NZA.Points.RegisterType('respawn', {
    label = L('type_respawn'), icon = 'heart', desc = L('type_respawn_desc'),
})

-- placed from the HQ card of the manager; stored on the department, never streamed as a point
NZA.Points.RegisterType('hq', {
    label = L('type_hq'), icon = 'flag', manager = false, desc = L('type_hq_desc'),
})

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (EMS job menu)
-- ════════════════════════════════════════════════════════════════════════

NZA.RadialItems = NZA.RadialItems or {}

table.insert(NZA.RadialItems, {
    id = 'hospital_duty', parent = nil, label = L('radial_duty'), icon = 'clock', order = 90,
    canShow = function()
        return hc('duty', {}).radial == true and rec().dept ~= nil
    end,
    onSelect = function()
        CreateThread(function() H.ToggleDuty(nil, nil) end)
    end,
})

table.insert(NZA.RadialItems, {
    id = 'hospital_manager', parent = nil, label = L('radial_manager'), icon = 'hospital', order = 99, perm = 'builder',
    canShow = function() return rec().admin == true end,
    onSelect = function()
        CreateThread(function() if C.OpenManager then C.OpenManager('admin') end end)
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('nza:hospital:ready')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    clearBlips()
    for id in pairs(officers) do removeOfficer(id) end
    NZA.UI.HidePrompt('nza_hospital_store')
    if lying then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
        lying = nil
    end
end)
