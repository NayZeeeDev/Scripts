--[[ Market drone delivery visuals. The server owns the order; this only flies a drone to you. ]]

Market = { pending = false }

local MarketCfg = lib.load('config.market')

local function collectTarget(bagCoords)
    local zone
    zone = Target.addZone(bagCoords, 1.2, {
        {
            name = 'nzh_market_collect', label = locale('market_collect'), icon = 'fas fa-box-open',
            onSelect = function()
                if not Anim.run('pickup', { coords = bagCoords }) then return end
                local ok, err = lib.callback.await('nzh:market:collect', false)
                if ok then
                    Target.removeZone(zone)
                    Props.delete('market_bag')
                    Market.pending = false
                    UI.notify(locale('market_collected'), 'success')
                elseif err then
                    UI.notify(err, 'error')
                end
            end,
        },
    })
end

local function fly(drone, from, to, ms)
    local t0 = GetGameTimer()
    while GetGameTimer() - t0 < ms do
        local k = (GetGameTimer() - t0) / ms
        local p = from + (to - from) * k
        SetEntityCoordsNoOffset(drone, p.x, p.y, p.z, false, false, false)
        Wait(0)
    end
end

function Market.deliver(seconds)
    if Market.pending then return end
    Market.pending = true
    local cfg = MarketCfg.delivery
    CreateThread(function()
        local endAt = GetGameTimer() + seconds * 1000
        UI.send('delivery', { remaining = seconds })
        while GetGameTimer() < endAt do Wait(1000) end
        UI.send('delivery', false)

        local ped = cache.ped
        local target = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.5, 0.0)
        local found, ground = GetGroundZFor_3dCoord(target.x, target.y, target.z + 5.0, false)
        if found then target = vec3(target.x, target.y, ground) end

        local blip = AddBlipForCoord(target.x, target.y, target.z)
        SetBlipSprite(blip, cfg.blip.sprite) SetBlipColour(blip, cfg.blip.color) SetBlipScale(blip, cfg.blip.scale)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(cfg.blip.label) EndTextCommandSetBlipName(blip)

        local drone = Props.spawn('market_drone', cfg.droneModel, target + vec3(0.0, 0.0, 60.0), 0.0, { freeze = false, collision = false })
        if drone then
            SetEntityHasGravity(drone, false)
            fly(drone, target + vec3(0.0, 0.0, 60.0), target + vec3(0.0, 0.0, 2.2), 6000)
            local bag = Props.spawn('market_bag', cfg.bagModel, target, 0.0, { ground = true })
            if bag then collectTarget(GetEntityCoords(bag)) end
            PlaySoundFrontend(-1, 'Drop_Item', 'GTAO_FM_Events_Soundset', false)
            Wait(800)
            fly(drone, target + vec3(0.0, 0.0, 2.2), target + vec3(0.0, 0.0, 80.0), 5000)
            Props.delete('market_drone')
        end
        RemoveBlip(blip)
        UI.notify(locale('market_arrived'), 'success')
    end)
end
