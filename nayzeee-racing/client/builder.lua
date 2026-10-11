if not NAYZEEE_LOCK_OK then return end

--[[
    Track builder. Drive the route and drop gates.
    Arrows: left/right = gate width, up/down = rotate. Shift + arrows = left post, Ctrl + arrows = right post.
    Enter = add gate, Delete = remove last, Z = circuit / sprint, F10 = help, Shift + Enter = save, Esc = cancel.
]]

Builder = { active = false }

local K = Config.KEYS
local gates, posts, blips = {}, {}, {}
local preview = {}
local trackType = TrackType.SPRINT
local saving = false
local crewOnly = false

local function post(model, p)
    local obj = CreateObjectNoOffset(model, p.x, p.y, p.z, false, false, false)
    SetEntityCollision(obj, false, false)
    SetEntityAlpha(obj, 210, false)
    PlaceObjectOnGroundProperly(obj)
    return obj
end

local function text3d(p, label)
    local on, x, y = World3dToScreen2d(p.x, p.y, p.z + 1.2)
    if not on then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayText(x, y)
end

local function length()
    local cps = {}
    for i, g in ipairs(gates) do cps[i] = g end
    return NZR.TrackLength(cps, trackType == TrackType.CIRCUIT)
end

local function sync()
    local pts = {}
    for i, g in ipairs(gates) do pts[i] = { g.center.x, g.center.y } end
    UI('builder', { phase = 'update', count = #gates, length = length(), type = trackType, preview = pts })
end

local function clearAll()
    for _, pair in ipairs(posts) do for _, o in ipairs(pair) do if DoesEntityExist(o) then DeleteEntity(o) end end end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    for _, o in ipairs(preview) do if DoesEntityExist(o) then DeleteEntity(o) end end
    gates, posts, blips, preview = {}, {}, {}, {}
end

local function addGate(left, right)
    local center = (left + right) / 2
    local tb = Config.Trackbuilder
    if #gates >= tb.MaxCheckpoints then return Config.Notify(L('TB_MAX', tb.MaxCheckpoints), 'error') end
    if #gates > 0 and #(center - gates[#gates].center) < tb.DistanceBetweenCheckpoints then
        return Config.Notify(L('TB_TOO_CLOSE', math.floor(tb.DistanceBetweenCheckpoints)), 'error')
    end
    gates[#gates + 1] = { left = left, center = center, right = right }
    local model = joaat(#gates == 1 and tb.StartpointModel or tb.CheckpointModel)
    lib.requestModel(model, 2000)
    posts[#posts + 1] = { post(model, left), post(model, right) }
    local b = AddBlipForCoord(center.x, center.y, center.z)
    SetBlipSprite(b, 1)
    SetBlipColour(b, Config.UI.BlipColor)
    SetBlipScale(b, 0.7)
    ShowNumberOnBlip(b, #gates)
    blips[#blips + 1] = b
    PlaySound(Config.Races.Sounds.Checkpoint)
    sync()
end

local function removeGate()
    if #gates == 0 then return end
    for _, o in ipairs(posts[#posts]) do if DoesEntityExist(o) then DeleteEntity(o) end end
    RemoveBlip(blips[#blips])
    posts[#posts], blips[#blips], gates[#gates] = nil, nil, nil
    sync()
end

function Builder.Stop(reopen)
    if not Builder.active then return end
    Builder.active = false
    saving = false
    clearAll()
    if not reopen then ReleaseStreamMaps() end
    SetNuiFocus(false, false)
    UI('builder', { phase = 'stop' })
    if reopen then SetTimeout(200, OpenApp) end
end

local function trySave()
    local tb = Config.Trackbuilder
    if #gates < tb.MinCheckpoints then return Config.Notify(L('TB_MIN', tb.MinCheckpoints), 'error') end
    if trackType == TrackType.CIRCUIT and #(gates[1].center - gates[#gates].center) > tb.CircuitMinimumDistanceBetweenFirstAndLastCheckpoint then
        return Config.Notify(L('TB_NOT_CLOSED', math.floor(tb.CircuitMinimumDistanceBetweenFirstAndLastCheckpoint)), 'error')
    end
    saving = true
    SetNuiFocus(true, true)
    UI('builder', { phase = 'save', count = #gates, length = length(), type = trackType, crewOnly = crewOnly,
        hasCrew = App.profile and App.profile.crewId ~= nil, crewTracks = Config.Trackbuilder.CrewTracks })
end

RegisterNUICallback('builder:save', function(d, cb)
    if not Builder.active then return cb({ error = 'ERR_GENERIC' }) end
    local cps = {}
    for i, g in ipairs(gates) do
        cps[i] = {
            left = { x = g.left.x, y = g.left.y, z = g.left.z },
            center = { x = g.center.x, y = g.center.y, z = g.center.z },
            right = { x = g.right.x, y = g.right.y, z = g.right.z },
        }
    end
    local res = lib.callback.await('nzr:req', false, 'track:create', {
        name = d.name, description = d.description, visibility = d.visibility, type = trackType, checkpoints = cps,
    })
    if res and res.data then
        Config.Notify(L('TB_SAVED'), 'success')
        Builder.Stop(true)
    end
    cb(res or { error = 'ERR_GENERIC' })
end)

RegisterNUICallback('builder:cancelSave', function(_, cb)
    saving = false
    SetNuiFocus(false, false)
    cb(true)
end)

RegisterNUICallback('builder:type', function(d, cb)
    trackType = d.type == TrackType.CIRCUIT and TrackType.CIRCUIT or TrackType.SPRINT
    sync()
    cb(true)
end)

function Builder.Start(crew)
    if Builder.active then return end
    Builder.active = true
    crewOnly = crew == true
    LoadStreamMaps()
    trackType = TrackType.SPRINT
    clearAll()
    local model = joaat(Config.Trackbuilder.CheckpointModel)
    lib.requestModel(model, 2000)
    local c = GetEntityCoords(cache.ped)
    preview = { post(model, c), post(model, c) }
    local half = Config.Trackbuilder.DefaultWidth / 2
    local off = { left = vector2(-half, 3.0), right = vector2(half, 3.0) }
    UI('builder', { phase = 'start', type = trackType, min = Config.Trackbuilder.MinCheckpoints, max = Config.Trackbuilder.MaxCheckpoints })
    sync()

    CreateThread(function()
        local step = 0.05
        while Builder.active do
            if saving then
                Wait(100)
            else
                local ent = cache.vehicle or cache.ped
                DisableControlAction(0, K.ESC, true)
                DisableControlAction(0, 199, true)
                for _, key in ipairs({ K.ARROW_UP, K.ARROW_DOWN, K.ARROW_LEFT, K.ARROW_RIGHT, K.Z, K.F10, K.DELETE, 85, 81, 82 }) do
                    DisableControlAction(0, key, true)
                end
                local shift = IsControlPressed(0, K.LEFT_SHIFT)
                local ctrl = IsControlPressed(0, K.LEFT_CTRL) or IsControlPressed(0, 36)
                local dx = (IsDisabledControlPressed(0, K.ARROW_RIGHT) and step or 0) - (IsDisabledControlPressed(0, K.ARROW_LEFT) and step or 0)
                local dy = (IsDisabledControlPressed(0, K.ARROW_UP) and step or 0) - (IsDisabledControlPressed(0, K.ARROW_DOWN) and step or 0)
                if dx ~= 0 or dy ~= 0 then
                    if shift then off.left = off.left + vector2(dx, dy)
                    elseif ctrl then off.right = off.right + vector2(dx, dy)
                    else
                        off.left = off.left + vector2(-dx, -dy)
                        off.right = off.right + vector2(dx, dy)
                    end
                end
                local left = GetOffsetFromEntityInWorldCoords(ent, off.left.x, off.left.y, 0.0)
                local right = GetOffsetFromEntityInWorldCoords(ent, off.right.x, off.right.y, 0.0)
                local _, lz = GetGroundZFor_3dCoord(left.x, left.y, left.z + 2.0, false)
                local _, rz = GetGroundZFor_3dCoord(right.x, right.y, right.z + 2.0, false)
                if lz and lz ~= 0 then left = vector3(left.x, left.y, lz) end
                if rz and rz ~= 0 then right = vector3(right.x, right.y, rz) end
                SetEntityCoordsNoOffset(preview[1], left.x, left.y, left.z, false, false, false)
                SetEntityCoordsNoOffset(preview[2], right.x, right.y, right.z, false, false, false)
                DrawLine(left.x, left.y, left.z + 0.6, right.x, right.y, right.z + 0.6, 8, 175, 162, 230)
                text3d(left, L('TB_LEFT'))
                text3d(right, L('TB_RIGHT'))
                for i, g in ipairs(gates) do
                    if #(g.center - left) < 120.0 then
                        DrawLine(g.left.x, g.left.y, g.left.z + 0.6, g.right.x, g.right.y, g.right.z + 0.6, 255, 255, 255, 140)
                        text3d(g.center, tostring(i))
                    end
                end

                if IsControlJustReleased(0, K.ENTER) or IsDisabledControlJustReleased(0, K.ENTER) then
                    if shift then trySave() else addGate(left, right) end
                elseif IsDisabledControlJustReleased(0, K.DELETE) then removeGate()
                elseif IsDisabledControlJustReleased(0, K.Z) then
                    trackType = trackType == TrackType.CIRCUIT and TrackType.SPRINT or TrackType.CIRCUIT
                    sync()
                elseif IsDisabledControlJustReleased(0, K.F10) then UI('builder', { phase = 'help' })
                elseif IsDisabledControlJustReleased(0, K.ESC) then Builder.Stop(true) end
                Wait(0)
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == NZR.Resource and Builder.active then clearAll() end
end)
