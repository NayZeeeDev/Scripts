--[[ Remote control: placeable prop + marker, held remote, NUI remote, universal remote item ]]

Remote = {
    uiOpen = false,
    tv = nil,          -- tvId the open remote controls
    holding = nil,     -- tvId whose physical remote we hold
    handProp = nil,
    props = {},        -- tvId → world remote entity
    others = {},       -- tvId → remote prop attached to another player
}

local R = Config.Remote
local hash = GetHashKey(R.Model)

-- ─── world remote props ───────────────────────────────────────
local function deleteProp(id)
    local e = Remote.props[id]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    Remote.props[id] = nil
end

local function attachTo(ped)
    if not NZ.loadModel(hash) then return nil end
    local pc = GetEntityCoords(ped)
    local e = CreateObject(hash, pc.x, pc.y, pc.z + 0.2, false, false, false)
    SetEntityCollision(e, false, false)
    AttachEntityToEntity(e, ped, GetPedBoneIndex(ped, R.Hold.Bone), R.Hold.Offset.x, R.Hold.Offset.y, R.Hold.Offset.z,
        R.Hold.Rot.x, R.Hold.Rot.y, R.Hold.Rot.z, true, true, false, true, 1, true)
    return e
end

NZ.on('scan', function(pc)
    if not R.Enabled then return end
    for id, tv in pairs(NZ.tvs) do
        local want = tv.remote and not tv.remoteHolder and tv._dist and tv._dist < 40.0
        if want and not Remote.props[id] then
            if NZ.loadModel(hash) then
                local e = CreateObjectNoOffset(hash, tv.remote.x, tv.remote.y, tv.remote.z, false, false, false)
                SetEntityHeading(e, tv.remote.h or 0.0)
                FreezeEntityPosition(e, true)
                SetEntityCollision(e, false, false)
                Remote.props[id] = e
            end
        elseif not want and Remote.props[id] then
            deleteProp(id)
        end

        -- other players holding this TV's remote
        local holder = tv.remoteHolder
        if holder and holder ~= NZ.me and tv._dist and tv._dist < 40.0 then
            local player = GetPlayerFromServerId(holder)
            local ped = player ~= -1 and GetPlayerPed(player) or 0
            local o = Remote.others[id]
            if ped ~= 0 and (not o or o.ped ~= ped or not DoesEntityExist(o.e)) then
                if o and DoesEntityExist(o.e) then DeleteEntity(o.e) end
                local e = attachTo(ped)
                Remote.others[id] = e and { e = e, ped = ped } or nil
            end
        elseif Remote.others[id] then
            if DoesEntityExist(Remote.others[id].e) then DeleteEntity(Remote.others[id].e) end
            Remote.others[id] = nil
        end
    end
    for id in pairs(Remote.props) do if not NZ.tvs[id] then deleteProp(id) end end
end)

NZ.on('patch', function(tv, patch)
    if patch.remote ~= nil or patch.remoteHolder ~= nil then deleteProp(tv.id) end
    if tv.id == Remote.holding and patch.remoteHolder ~= nil and tv.remoteHolder ~= NZ.me then Remote.release(true) end
end)

NZ.on('removed', function(tv)
    deleteProp(tv.id)
    if Remote.holding == tv.id then Remote.release(true) end
    if Remote.tv == tv.id then Remote.closeUi() end
end)

-- marker above remotes
CreateThread(function()
    local M = R.Marker
    while true do
        local sleep = 600
        if R.Enabled and M.Enabled then
            local pc = GetEntityCoords(PlayerPedId())
            for _, e in pairs(Remote.props) do
                if DoesEntityExist(e) then
                    local c = GetEntityCoords(e)
                    local d = #(pc - c)
                    if d < M.Distance then
                        sleep = 0
                        local bob = M.Bob and (math.sin(GetGameTimer() / 380.0) * 0.025) or 0.0
                        local a = math.floor(M.Color[4] * math.min(1.0, (M.Distance - d) / 2.0))
                        DrawMarker(M.Type, c.x, c.y, c.z + M.Height + bob, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            M.Scale, M.Scale, M.Scale, M.Color[1], M.Color[2], M.Color[3], a, false, true, 2, false, nil, nil, false)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

function Remote.nearestProp(pc)
    if not R.Enabled or Remote.holding then return nil end
    local best, bd
    for id, e in pairs(Remote.props) do
        if DoesEntityExist(e) then
            local d = #(pc - GetEntityCoords(e))
            if d < R.PickupDistance and (not bd or d < bd) then best, bd = NZ.tvs[id], d end
        end
    end
    return best
end

-- ─── holding ──────────────────────────────────────────────────
local function playHoldAnim()
    local ped = PlayerPedId()
    RequestAnimDict(R.Hold.Dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(R.Hold.Dict) and GetGameTimer() < t do Wait(10) end
    if HasAnimDictLoaded(R.Hold.Dict) then
        TaskPlayAnim(ped, R.Hold.Dict, R.Hold.Clip, 3.0, 3.0, -1, 49, 0.0, false, false, false)
    end
end

local function stopHoldAnim()
    StopAnimTask(PlayerPedId(), R.Hold.Dict, R.Hold.Clip, 2.0)
end

function Remote.take(tv)
    CreateThread(function()
        local ok = NZ.call('remoteTake', tv.id)
        if not ok then return end
        Remote.holding = tv.id
        Remote.handProp = attachTo(PlayerPedId())
        playHoldAnim()
        Remote.openUi(tv, true)
    end)
end

--- Put the held remote down where you are aiming (or at your feet).
function Remote.putDown(tvId)
    tvId = tvId or Remote.holding
    if not tvId then return end
    CreateThread(function()
        Remote.closeUi()
        local tv = NZ.tvs[tvId]
        local res = tv and Placement.prop({
            model = R.Model, title = _L('place_remote_hint'), label = tv.label, maxDistance = 3.0, floorOnly = true,
        })
        local coords, heading
        if res then coords, heading = res.coords, res.heading end
        NZ.call('remoteDrop', tvId, coords, heading)
        Remote.release(false)
    end)
end

function Remote.release(silent)
    if Remote.handProp and DoesEntityExist(Remote.handProp) then DeleteEntity(Remote.handProp) end
    Remote.handProp = nil
    if Remote.holding then stopHoldAnim() end
    Remote.holding = nil
    if Remote.uiOpen and Remote.physical then Remote.closeUi() end
end

-- holding keeps the anim alive; G reopens the remote UI
CreateThread(function()
    while true do
        local sleep = 500
        if Remote.holding then
            sleep = 0
            local ped = PlayerPedId()
            if not Remote.uiOpen then
                if not IsEntityPlayingAnim(ped, R.Hold.Dict, R.Hold.Clip, 3) and not IsPedInAnyVehicle(ped, false) then playHoldAnim() end
                if IsControlJustReleased(0, Config.Interact.Keys.Remote) then
                    local tv = NZ.tvs[Remote.holding]
                    if tv then Remote.openUi(tv, true) end
                end
                if IsControlJustReleased(0, Config.Interact.Keys.Pickup) then Remote.putDown() end
            end
        end
        Wait(sleep)
    end
end)

-- ─── NUI remote ───────────────────────────────────────────────
function Remote.openUi(tv, physical)
    Remote.tv = tv.id
    Remote.physical = physical == true
    Remote.uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'remote', show = true, tv = Panel.lite(tv), now = NZ.serverNow(), physical = Remote.physical,
        channels = Config.Channels, brand = Config.Brand,
    })
end

function Remote.closeUi()
    if not Remote.uiOpen then return end
    Remote.uiOpen = false
    Remote.tv = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'remote', show = false })
    if not Remote.holding then stopHoldAnim() end
end

--- Remote without picking up a prop (target option, phone, universal remote).
function Remote.openVirtual(tv)
    CreateThread(function()
        local data, err = NZ.rpc('panel', tv.id) -- permission probe
        if not data then return NZ.notify(_L(err or 'no_permission'), 'error') end
        Remote.openUi(tv, false)
    end)
end

NZ.on('patch', function(tv, patch)
    if Remote.uiOpen and Remote.tv == tv.id then
        SendNUIMessage({ type = 'remotePatch', id = tv.id, patch = patch, now = NZ.serverNow() })
    end
end)

-- universal remote item
RegisterNetEvent('nztv:universalRemote', function()
    local tv = NZ.target(R.Range)
    if not tv then return NZ.notify(_L('no_tv_near'), 'error') end
    NZ.notify(_L('remote_paired', tv.label), 'success')
    Remote.openVirtual(tv)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.res then return end
    for id in pairs(Remote.props) do deleteProp(id) end
    for _, o in pairs(Remote.others) do if DoesEntityExist(o.e) then DeleteEntity(o.e) end end
    if Remote.handProp and DoesEntityExist(Remote.handProp) then DeleteEntity(Remote.handProp) end
end)
