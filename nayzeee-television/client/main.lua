--[[ NAYZEEE TELEVISION — client core: registry, clock, RPC, streaming ]]

NZ = {
    tvs = {},           -- id → tv (public data + client runtime fields prefixed with _)
    calibration = {},
    channels = {},      -- live channels (config + M3U playlists), sent by the server
    calibPreview = {},  -- model → screen (admin calibrator live preview)
    offset = 0,         -- server clock offset (ms)
    admin = false,
    me = GetPlayerServerId(PlayerId()),
    ready = false,
}

local RES = GetCurrentResourceName()
NZ.res = RES

-- ─── tiny event bus ───────────────────────────────────────────
local listeners = {}
function NZ.on(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
function NZ.emit(name, ...)
    for _, fn in ipairs(listeners[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then print(('^1[nayzeee-television] %s handler: %s^7'):format(name, err)) end
    end
end

-- ─── RPC ──────────────────────────────────────────────────────
local pending, seq = {}, 0

RegisterNetEvent('nztv:rpc', function(id, res, err)
    local p = pending[id]
    if p then pending[id] = nil p:resolve({ res, err }) end
end)

function NZ.rpc(name, ...)
    seq = seq + 1
    local id = seq
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('nztv:rpc', id, name, ...)
    SetTimeout(12000, function()
        if pending[id] then pending[id] = nil p:resolve({ nil, 'timeout' }) end
    end)
    local r = Citizen.Await(p)
    return r[1], r[2]
end

--- Fire an RPC and toast its result message.
function NZ.call(name, ...)
    local res, msg = NZ.rpc(name, ...)
    if msg and msg ~= 'timeout' and msg ~= 'error' and msg ~= 'unknown' then
        NZ.notify(_L(msg), (res == false) and 'error' or 'success')
    end
    return res, msg
end

-- ─── clock ────────────────────────────────────────────────────
function NZ.serverNow() return GetGameTimer() + NZ.offset end

local function calibrateClock()
    local best
    for _ = 1, 3 do
        local t0 = GetGameTimer()
        local s = NZ.rpc('time')
        local t1 = GetGameTimer()
        if type(s) == 'number' then
            local rtt = t1 - t0
            if not best or rtt < best.rtt then best = { rtt = rtt, offset = s + rtt / 2 - t1 } end
        end
        Wait(60)
    end
    if best then NZ.offset = best.offset end
end

-- ─── notifications (NAYZEEE toast) ────────────────────────────
function NZ.notify(msg, kind, title)
    local n = Config.Notify
    if n == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({ title = title or Config.Brand.product, description = msg, type = kind == 'error' and 'error' or (kind == 'success' and 'success' or 'inform') })
    elseif n == 'esx' and GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', msg, kind == 'error' and 'error' or 'info')
    elseif n == 'qb' and (GetResourceState('qb-core') == 'started' or GetResourceState('qbx_core') == 'started') then
        TriggerEvent('QBCore:Notify', msg, kind == 'error' and 'error' or (kind == 'success' and 'success' or 'primary'))
    elseif n == 'native' then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    else
        SendNUIMessage({ type = 'toast', text = msg, kind = kind or 'info', title = title })
    end
end

-- ─── personal settings (only affect you) ──────────────────────
NZ.personal = { volume = 1.0, streamer = false }
do
    local v = GetResourceKvpFloat('nztv_personal_volume')
    NZ.personal.volume = (v and v > 0) and v or (GetResourceKvpInt('nztv_personal_set') == 1 and 0.0 or 1.0)
    NZ.personal.streamer = GetResourceKvpInt('nztv_streamer') == 1
end
function NZ.savePersonal()
    SetResourceKvpFloat('nztv_personal_volume', NZ.personal.volume)
    SetResourceKvpInt('nztv_personal_set', 1)
    SetResourceKvpInt('nztv_streamer', NZ.personal.streamer and 1 or 0)
end
RegisterNetEvent('nztv:notify', function(msg, kind, title) NZ.notify(_L(msg), kind, title) end)

-- ─── helpers ──────────────────────────────────────────────────
function NZ.prop(tv) return tv.model and Props.Get(tv.model) or nil end

function NZ.center(tv)
    if tv._screen then return tv._screen.center end
    return vector3(tv.coords.x, tv.coords.y, tv.coords.z)
end

function NZ.loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > t then return false end
        Wait(10)
    end
    return true
end

-- ─── registry sync ────────────────────────────────────────────
local function despawn(tv)
    local ent = tv._entity
    tv._entity = nil
    tv._screen = nil
    tv._roomKey = nil
    -- listeners (targets, browsers) clean up while the entity still exists
    if ent ~= nil then NZ.emit('despawned', tv, ent) end
    if ent and ent ~= 0 and tv.kind == 'prop' and DoesEntityExist(ent) then DeleteEntity(ent) end
end

local function boot()
    local data = NZ.rpc('boot')
    if type(data) ~= 'table' then return end
    for _, tv in pairs(NZ.tvs) do despawn(tv) NZ.emit('removed', tv) end
    NZ.tvs = {}
    NZ.admin = data.admin == true
    NZ.me = data.me or NZ.me
    NZ.calibration = data.calibration or {}
    NZ.channels = data.channels or {}
    NZ.plex = data.plex == true
    NZ.search = data.search == true
    for _, tv in ipairs(data.tvs) do NZ.tvs[tv.id] = tv end
    calibrateClock()
    NZ.ready = true
    NZ.emit('boot')
end

RegisterNetEvent('nztv:client:reboot', function() CreateThread(boot) end)

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    boot()
    while true do
        Wait(Config.Sync.ClockResyncMs)
        calibrateClock()
    end
end)

RegisterNetEvent('nztv:channels', function(list)
    NZ.channels = list or {}
    NZ.emit('channels', NZ.channels)
end)

RegisterNetEvent('nztv:add', function(tv)
    NZ.tvs[tv.id] = tv
    NZ.emit('added', tv)
end)

RegisterNetEvent('nztv:remove', function(id)
    local tv = NZ.tvs[id]
    if not tv then return end
    despawn(tv)
    NZ.tvs[id] = nil
    NZ.emit('removed', tv)
end)

local GEOMETRY = { coords = true, heading = true, pitch = true, roll = true, wall = true }

RegisterNetEvent('nztv:patch', function(id, patch, cleared)
    local tv = NZ.tvs[id]
    if not tv then return end
    local moved = false
    for k, v in pairs(patch) do
        tv[k] = v
        if GEOMETRY[k] then moved = true end
    end
    for _, k in ipairs(cleared or {}) do
        tv[k] = nil
        patch[k] = false
        if GEOMETRY[k] then moved = true end
    end
    if moved then despawn(tv) end
    NZ.emit('patch', tv, patch, cleared or {})
end)

RegisterNetEvent('nztv:calibration', function(model, screen)
    NZ.calibration[model] = screen
    for _, tv in pairs(NZ.tvs) do if tv.model == model then tv._screen = nil end end
end)

-- ─── streaming (local, non-networked props → OneSync Infinity safe) ──
local function spawn(tv)
    if tv.kind == 'wall' then
        tv._entity = 0
        NZ.emit('spawned', tv)
        return
    end
    local hash = GetHashKey(tv.model)
    if tv.kind == 'existing' then
        local ent = GetClosestObjectOfType(tv.coords.x, tv.coords.y, tv.coords.z, 1.5, hash, false, false, false)
        if ent ~= 0 then
            tv._entity = ent
            NZ.emit('spawned', tv)
        end
        return
    end
    if not NZ.loadModel(hash) then
        if not tv._warned then
            tv._warned = true
            print(('^3[nayzeee-television]^7 model %s is not available on this build'):format(tv.model))
        end
        return
    end
    local ent = CreateObjectNoOffset(hash, tv.coords.x, tv.coords.y, tv.coords.z, false, false, false)
    SetEntityRotation(ent, tv.pitch or 0.0, tv.roll or 0.0, tv.heading or 0.0, 2, true)
    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityCanBeDamaged(ent, false)
    SetEntityLodDist(ent, 200)
    SetModelAsNoLongerNeeded(hash)
    tv._entity = ent
    NZ.emit('spawned', tv)
end

--[[ Objects created by scripts inside an MLO are not attached to a room, which
     makes them render unlit or vanish at some angles. Once the player is in
     the same interior we pin the TV to the room the player is standing in
     (they are within 25 m of it, so it is almost always the same room). ]]
local function pinToRoom(tv)
    local ent = tv._entity
    if not ent or ent == 0 then return end
    local int = GetInteriorAtCoords(tv.coords.x, tv.coords.y, tv.coords.z)
    if int == 0 then tv._roomKey = false return end
    local ped = PlayerPedId()
    if GetInteriorFromEntity(ped) ~= int then return end
    local room = GetRoomKeyFromEntity(ped)
    if room == 0 then return end
    ForceRoomForEntity(ent, int, room)
    tv._roomKey = room
    tv._screen = nil
end

NZ.nearest = { tv = nil, dist = 9999.0 }

CreateThread(function()
    while true do
        local sleep = Config.Render.TickIdle
        if NZ.ready then
            local pc = GetEntityCoords(PlayerPedId())
            local near, nearDist = nil, 9999.0
            for _, tv in pairs(NZ.tvs) do
                local c = tv.coords
                local d = #(pc - vector3(c.x, c.y, c.z))
                tv._dist = d
                local streamDist = math.max(Config.Render.StreamDistance, (tv.range or 20.0) + Config.Render.RenderPadding)
                if d < streamDist then
                    if not tv._entity then spawn(tv)
                    elseif tv.kind ~= 'wall' and not DoesEntityExist(tv._entity) then
                        -- MLO streamed out or another script deleted it: forget it and find / spawn again
                        despawn(tv)
                    elseif tv.kind == 'prop' and tv._roomKey == nil and d < 25.0 then
                        pinToRoom(tv)
                    end
                elseif d > streamDist + 10.0 and tv._entity then
                    despawn(tv)
                end
                if d < nearDist then near, nearDist = tv, d end
                if d < (tv.range or 20.0) + 10.0 then sleep = Config.Render.TickNear end
            end
            NZ.nearest.tv, NZ.nearest.dist = near, nearDist
            NZ.emit('scan', pc)
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, tv in pairs(NZ.tvs) do despawn(tv) end
end)

-- ─── finding the screen the player means ──────────────────────
--- The screen in front of the camera, else the nearest one in reach.
function NZ.target(maxDist)
    maxDist = maxDist or 12.0
    local camPos = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local best, bestScore
    for _, tv in pairs(NZ.tvs) do
        if tv._entity and tv._dist and tv._dist < maxDist + 6.0 then
            local c = NZ.center(tv)
            local to = c - camPos
            local dist = #to
            if dist < maxDist then
                local dot = (to.x * dir.x + to.y * dir.y + to.z * dir.z) / math.max(dist, 0.001)
                local score = (1.0 - dot) * 20.0 + dist
                if dot > 0.6 and (not bestScore or score < bestScore) then best, bestScore = tv, score end
            end
        end
    end
    if best then return best end
    local n = NZ.nearest
    if n.tv and n.dist < maxDist then return n.tv end
end
