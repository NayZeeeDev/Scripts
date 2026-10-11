-- Client: opens the panel and relays its requests. Nothing runs while the panel is closed.
local open = false
local uploads = {}
local reqSeq = 0

local function setOpen(state)
    open = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

RegisterNetEvent('nzinv:open', function()
    if open then return end
    setOpen(true)
    SendNUIMessage({ action = 'open', ui = Config.UI })
end)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb(true)
end)

RegisterNUICallback('rpc', function(d, cb)
    local res = lib.callback.await('nzinv:rpc', false, d.name, d.data)
    cb(res or { ok = false, err = 'No response from the server.' })
end)

RegisterNUICallback('copy', function(d, cb)
    if d.text then lib.setClipboard(tostring(d.text)) end
    cb(true)
end)

RegisterNUICallback('waypoint', function(d, cb)
    local x, y = tonumber(d.x), tonumber(d.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
    cb(true)
end)

-- item image uploads go over a latent event so big files don't stall the connection
RegisterNUICallback('upload', function(d, cb)
    reqSeq = reqSeq + 1
    local id = reqSeq
    uploads[id] = cb
    TriggerLatentServerEvent('nzinv:image', 200000, id, d.item, d.data)
    SetTimeout(60000, function()
        local pending = uploads[id]
        if pending then uploads[id] = nil pending({ ok = false, err = 'Upload timed out.' }) end
    end)
end)

RegisterNetEvent('nzinv:imageDone', function(id, ok, msg, extra)
    local cb = uploads[id]
    if not cb then return end
    uploads[id] = nil
    cb({ ok = ok, msg = msg, data = extra })
end)

-- a data file or picture was changed outside the game and picked up by the server
RegisterNetEvent('nzinv:dataChanged', function(info)
    if type(info) ~= 'table' then return end
    if open then
        SendNUIMessage({ action = 'dataChanged', data = info })
    elseif info.notify and info.msg then
        lib.notify({ title = 'Inventory Manager', description = info.msg, type = info.ok == false and 'error' or 'inform', duration = 7000 })
    end
end)

-- ─── point capture ─────────────────────────────────────────────────────────
-- The panel hides, the player aims at a spot in the world and presses E. Runs only while capturing.
local capturing = false
local BLOCK = { 14, 15, 16, 17, 24, 25, 38, 44, 51, 140, 141, 142, 177, 199, 200, 257, 263 }

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

RegisterNUICallback('capture', function(d, cb)
    if capturing then return cb({ ok = false }) end
    capturing = true
    local withHeading = d and d.heading == true
    local heading = GetEntityHeading(cache.ped)
    SetNuiFocus(false, false)
    lib.showTextUI(withHeading and '[E] Place point  [Scroll] Rotate  [Backspace] Cancel' or '[E] Place point  [Backspace] Cancel', {
        position = 'top-center', icon = 'location-crosshairs',
    })
    CreateThread(function()
        local result
        while capturing do
            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end
            local hit, _, pos = lib.raycast.cam(1 | 16, 4, 40.0)
            if hit and pos then
                DrawMarker(28, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, 8, 175, 162, 170, false, false, 2, false, nil, nil, false)
                DrawMarker(25, pos.x, pos.y, pos.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 0.9, 8, 175, 162, 120, false, false, 2, false, nil, nil, false)
                if withHeading then
                    local r = math.rad(heading)
                    local tip = vec3(pos.x - math.sin(r) * 0.9, pos.y + math.cos(r) * 0.9, pos.z + 0.05)
                    DrawLine(pos.x, pos.y, pos.z + 0.05, tip.x, tip.y, tip.z, 255, 255, 255, 230)
                end
                if IsDisabledControlJustPressed(0, 38) then
                    result = { ok = true, x = round(pos.x), y = round(pos.y), z = round(pos.z), w = round(heading % 360) }
                    break
                end
            end
            if withHeading then
                local step = IsControlPressed(0, 21) and 1.0 or 7.5
                if IsDisabledControlJustPressed(0, 15) then heading = heading + step end
                if IsDisabledControlJustPressed(0, 14) then heading = heading - step end
            end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then break end
            Wait(0)
        end
        lib.hideTextUI()
        -- let go of the key first so it doesn't also trigger the pause menu or the panel
        local t = GetGameTimer()
        while GetGameTimer() - t < 250 do
            DisableControlAction(0, 177, true) DisableControlAction(0, 200, true) DisableControlAction(0, 38, true)
            Wait(0)
        end
        capturing = false
        if open then SetNuiFocus(true, true) end
        cb(result or { ok = false })
    end)
end)

AddEventHandler('onResourceStop', function(r)
    if r ~= GetCurrentResourceName() then return end
    if capturing then capturing = false lib.hideTextUI() end
    if open then SetNuiFocus(false, false) end
end)

if Config.OpenKey and Config.OpenKey ~= '' then
    RegisterKeyMapping(Config.Commands.open, 'Open the inventory manager', 'keyboard', Config.OpenKey)
end
