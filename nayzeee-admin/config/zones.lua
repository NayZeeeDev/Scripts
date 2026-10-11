-- Zone behaviours you can pick when creating a zone in the panel (Server > Zones).
-- Each handler runs on the client. onEnter / onExit get the zone row (with .options).
-- inside runs every frame while the player is inside, so only use it when needed.
ZoneHandlers = {
    safezone = {
        label = 'Safe zone (no weapons, no damage)',
        onEnter = function(zone)
            SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
            SetEntityInvincible(cache.ped, true)
            Bridge.Notify('You entered a safe zone.', 'success')
        end,
        onExit = function(zone)
            SetEntityInvincible(cache.ped, false)
            Bridge.Notify('You left the safe zone.', 'info')
        end,
        inside = function(zone)
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 140, true) -- melee
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
        end,
    },
    speedlimit = {
        label = 'Speed limit (options.kmh, default 50)',
        onEnter = function(zone)
            local v = cache.vehicle
            if v then SetVehicleMaxSpeed(v, ((zone.options.kmh or 50) / 3.6)) end
        end,
        onExit = function()
            local v = cache.vehicle
            if v then SetVehicleMaxSpeed(v, 0.0) end
        end,
    },
    novehicles = {
        label = 'No vehicles (kicks drivers out)',
        onEnter = function()
            if cache.vehicle and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped then
                TaskLeaveVehicle(cache.ped, cache.vehicle, 0)
                Bridge.Notify('Vehicles are not allowed here.', 'error')
            end
        end,
    },
    notify = {
        label = 'Show a message (options.enter / options.exit)',
        onEnter = function(zone) if zone.options.enter then Bridge.Notify(zone.options.enter, 'info', zone.name) end end,
        onExit = function(zone) if zone.options.exit then Bridge.Notify(zone.options.exit, 'info', zone.name) end end,
    },
}

ZoneHandlerList = {}
for k, v in pairs(ZoneHandlers) do ZoneHandlerList[#ZoneHandlerList + 1] = { id = k, label = v.label } end
table.sort(ZoneHandlerList, function(a, b) return a.label < b.label end)
