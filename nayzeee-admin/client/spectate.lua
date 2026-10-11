-- Spectate. Works across OneSync culling: we park near the target until their ped streams in.
local spec -- { id, name, origin, heading }

local function stopSpectate()
    if not spec then return end
    local s = spec
    spec = nil
    NetworkSetInSpectatorMode(false, cache.ped)
    local ped = cache.ped
    RequestCollisionAtCoord(s.origin.x, s.origin.y, s.origin.z)
    SetEntityCoords(ped, s.origin.x, s.origin.y, s.origin.z - 1.0, false, false, false, false)
    SetEntityHeading(ped, s.heading)
    FreezeEntityPosition(ped, Toggles.freeze)
    SetEntityVisible(ped, not Toggles.invis, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, Toggles.god)
    TriggerServerEvent('nzadmin:sv:spectateStop')
    TriggerServerEvent('nzadmin:sv:movement', 6)
    NUI('spectate', false)
end
StopSpectate = stopSpectate

local function park(c)
    local ped = cache.ped
    SetEntityCoords(ped, c.x, c.y, c.z - 25.0, false, false, false, false)
end

local function sortedIds()
    local ids = {}
    for _, p in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(p)
        if p ~= cache.playerId then ids[#ids + 1] = sid end
    end
    table.sort(ids)
    return ids
end

local function cycle(dir)
    local ids = sortedIds()
    if #ids < 2 then return end
    local idx = 1
    for i, v in ipairs(ids) do if v == spec.id then idx = i end end
    idx = idx + dir
    if idx < 1 then idx = #ids elseif idx > #ids then idx = 1 end
    local ok, err = RPC('player:spectate', { id = ids[idx] })
    if not ok then Notify(err, 'error') end
end

RegisterNetEvent('nzadmin:cl:spectate', function(d)
    if GetInvokingResource() or not Me.isStaff then return end
    if Toggles.noclip then SetToggle('noclip', false) end
    local fresh = spec == nil
    if fresh then
        local c = GetEntityCoords(cache.ped)
        spec = { origin = c, heading = GetEntityHeading(cache.ped) }
    else
        NetworkSetInSpectatorMode(false, cache.ped)
    end
    spec.id, spec.name, spec.ped = d.id, d.name, nil
    TriggerServerEvent('nzadmin:sv:movement', 10)

    local ped = cache.ped
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    if d.coords then park(d.coords) end
    if UI.open then CloseUI() end
    NUI('spectate', { id = d.id, name = d.name })

    if not fresh then return end
    CreateThread(function()
        local lastInfo, lastPing = 0, 0
        while spec do
            local now = GetGameTimer()
            local pl = GetPlayerFromServerId(spec.id)
            local tped = pl ~= -1 and GetPlayerPed(pl) or 0
            if tped ~= 0 and DoesEntityExist(tped) then
                if spec.ped ~= tped then
                    spec.ped = tped
                    NetworkSetInSpectatorMode(true, tped)
                end
                local c = GetEntityCoords(tped)
                SetEntityCoordsNoOffset(cache.ped, c.x, c.y, c.z - 25.0, false, false, false)
            end
            if now - lastInfo > 1000 then
                lastInfo = now
                CreateThread(function()
                    local info = lib.callback.await('nzadmin:spectateInfo', false, spec and spec.id)
                    if not spec then return end
                    if not info then Notify('Target left the server.', 'info'); stopSpectate(); return end
                    if tped == 0 and info.coords then park(info.coords) end
                    NUI('spectate', { id = spec.id, name = info.name, health = math.max(0, (info.health or 200) - 100), armour = info.armour or 0 })
                end)
            end
            if now - lastPing > 5000 then lastPing = now; TriggerServerEvent('nzadmin:sv:movement', 8) end

            DisableControlAction(0, 177, true)
            if IsDisabledControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then stopSpectate(); break end
            if IsControlJustPressed(0, 174) then cycle(-1) elseif IsControlJustPressed(0, 175) then cycle(1) end
            Wait(0)
        end
    end)
end)

LocalActions.stopSpectate = function() stopSpectate(); return true end

AddEventHandler('onResourceStop', function(r) if r == NZ.Resource and spec then stopSpectate() end end)
