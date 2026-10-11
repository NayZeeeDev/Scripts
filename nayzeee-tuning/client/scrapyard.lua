--[[ Scrapyard: strip unowned cars for tuning components. ]]

if not Config.Scrapyard.Enabled then return end

local cfg = Config.Scrapyard
local inYard, working = false, false

CreateThread(function()
    local b = AddBlipForCoord(cfg.Zone.coords.x, cfg.Zone.coords.y, cfg.Zone.coords.z)
    SetBlipSprite(b, cfg.Blip.sprite)
    SetBlipColour(b, cfg.Blip.color)
    SetBlipScale(b, cfg.Blip.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(cfg.Label)
    EndTextCommandSetBlipName(b)
end)

lib.zones.sphere({
    coords = cfg.Zone.coords, radius = cfg.Zone.radius, debug = Config.Debug,
    onEnter = function() inYard = true end,
    onExit = function() inYard = false end,
})

local function dismantle(veh)
    if working then return end
    local ok, done = lib.callback.await('nayzeee-tuning:scrapStart', false, VehToNet(veh))
    if not ok then return Notify(done or L('failed'), 'error') end
    working = true
    CreateThread(function()
        for i, part in ipairs(cfg.Parts) do
            -- walking out of the yard abandons the job (it resumes from the server's list next time)
            if not working or not inYard or not DoesEntityExist(veh) then break end
            if not (done and (done[i] or done[tostring(i)])) then
                -- models without the bone (bikes, no boot...) are worked at the car itself: the server needs every part before the last
                do
                    local pos = VehUtil.BoneCoords(veh, { part.bone })
                    local shown = false
                    while working and inYard and DoesEntityExist(veh) do
                        DrawMarker(21, pos.x, pos.y, pos.z + 0.4, 0, 0, 0, 180.0, 0, 0, 0.25, 0.25, 0.25, 229, 72, 77, 200, true, true, 2, false, nil, nil, false)
                        if #(GetEntityCoords(cache.ped) - pos) < 1.8 then
                            if not shown then Bridge.TextUI(L('prompt_scrap', part.label)) shown = true end
                            if IsControlJustPressed(0, Config.Keys.Interact) then
                                Bridge.TextUI(false)
                                if part.door then SetVehicleDoorOpen(veh, part.door, false, false) end
                                if Bridge.Progress(L('scrapping', part.label), part.time, { 'mini@repair', 'fixing_a_ped', 1 }) then
                                    local ok2, res = lib.callback.await('nayzeee-tuning:scrapPart', false, VehToNet(veh), i)
                                    if ok2 then
                                        if part.door then SetVehicleDoorBroken(veh, part.door, true) end
                                        if part.wheel then SetVehicleTyreBurst(veh, part.wheel, true, 1000.0) end
                                        Notify(L('scrap_got', res.amount), 'success')
                                        if res.finished then working = false end
                                    else
                                        Notify(res or L('failed'), 'error')
                                    end
                                    break
                                end
                                shown = false
                            end
                        elseif shown then Bridge.TextUI(false) shown = false end
                        Wait(0)
                    end
                    if shown then Bridge.TextUI(false) end
                end
            end
        end
        working = false
        Bridge.TextUI(false)
    end)
end

Bridge.AddGlobalVehicle({
    { name = 'nzt_scrap', label = L('target_scrap'), icon = 'fa-recycle', distance = 3.0,
      canInteract = function(entity) return inYard and not working and GetPedInVehicleSeat(entity, -1) == 0 end,
      onSelect = function(d) dismantle(d.entity) end },
})
