--[[ THE WASH — client boot ]]

RegisterNUICallback('ready', function(_, cb)
    cb(1)
    UI.init()
end)

RegisterNetEvent('nzmw:marketEvent', function(e)
    if not e or CBridge.isPolice() then return end
    UI.toast('Word on the street · ' .. e.label, ('%s (%+d%% wash rate)'):format(e.note or '', math.floor(e.mod * 100)), e.mod >= 0 and 'success' or 'error', 9000)
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    UI.init()
    Render.syncIndex(GlobalState['nzmw:index'])
    Render.start()
    FrontDesk.init()
    PoliceUI.init()

    for _, op in ipairs(Config.Operations) do
        if op.blip and op.stations[1] then
            local c = op.stations[1].coords
            local b = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(b, op.blip.sprite or 500)
            SetBlipColour(b, op.blip.colour or 2)
            SetBlipScale(b, op.blip.scale or 0.7)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(op.label)
            EndTextCommandSetBlipName(b)
        end
        if op.entrance then
            local e = op.entrance
            Target.addZone('nzmw_in_' .. op.id, e.outside.xyz, 1.2, { {
                name = 'enter', label = 'Enter ' .. op.label, icon = 'fas fa-door-open',
                onSelect = function()
                    DoScreenFadeOut(400) Wait(450)
                    SetEntityCoords(PlayerPedId(), e.inside.x, e.inside.y, e.inside.z, false, false, false, false)
                    SetEntityHeading(PlayerPedId(), e.inside.w)
                    Wait(300) DoScreenFadeIn(400)
                end } })
            Target.addZone('nzmw_out_' .. op.id, e.inside.xyz, 1.2, { {
                name = 'exit', label = 'Leave', icon = 'fas fa-door-closed',
                onSelect = function()
                    DoScreenFadeOut(400) Wait(450)
                    SetEntityCoords(PlayerPedId(), e.outside.x, e.outside.y, e.outside.z, false, false, false, false)
                    SetEntityHeading(PlayerPedId(), e.outside.w)
                    Wait(300) DoScreenFadeIn(400)
                end } })
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == NZ.Resource and UI.isOpen() then SetNuiFocus(false, false) end
end)

if Config.Debug then
    -- draws every station's ped/bag/sheet offsets so you can tune Config.Offsets in-game
    local drawing = false
    RegisterCommand('nzmw_offsets', function()
        drawing = not drawing
        CreateThread(function()
            while drawing do
                for _, s in pairs(Render.stations) do
                    local d = s.data
                    for name, off in pairs(Config.Offsets[d.type] or {}) do
                        local p = U.offset(d, off)
                        DrawMarker(28, p.x, p.y, p.z + 0.05, 0, 0, 0, 0, 0, 0, 0.08, 0.08, 0.08, 8, 175, 162, 200, false, false, 2, false, nil, nil, false)
                        local onScreen, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 0.2)
                        if onScreen then
                            SetTextScale(0.25, 0.25) SetTextFont(4) SetTextCentre(true) SetTextOutline()
                            BeginTextCommandDisplayText('STRING')
                            AddTextComponentSubstringPlayerName(d.type .. '.' .. name)
                            EndTextCommandDisplayText(sx, sy)
                        end
                    end
                end
                Wait(0)
            end
        end)
    end, false)
end
