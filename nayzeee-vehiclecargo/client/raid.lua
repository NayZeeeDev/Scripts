-----------------------------------------------------------------
-- Police raids (officer side) and crew job hand-off
-----------------------------------------------------------------
Raid = {}
local doors = {}   -- [wid] = point id

RegisterNetEvent('nz_cargo:raid:open', function(d)
    local id = 'nz_raid_' .. d.wid
    doors[d.wid] = id
    local c = vec3(d.door.x, d.door.y, d.door.z)
    Bridge.AddPoint(id, c, 2.0, {
        {
            label = ('Raid warehouse (%s)'):format(d.owner or d.name), icon = 'fa-solid fa-building-shield',
            onSelect = function()
                local data = lib.callback.await('nz_cargo:raid:enter', false, d.wid)
                if data then Warehouse.Load(data) else Bridge.Notify(L('raid_closed'), 'error') end
            end,
        },
    })
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, 473)
    SetBlipColour(b, 3)
    SetBlipFlashes(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Warrant: ' .. (d.name or 'Warehouse'))
    EndTextCommandSetBlipName(b)
    doors[d.wid .. ':blip'] = b
    Bridge.Notify(L('raid_police', d.name or ''), 'warning', 'Warrant')
end)

RegisterNetEvent('nz_cargo:raid:close', function(wid)
    if doors[wid] then Bridge.RemovePoint(doors[wid]) doors[wid] = nil end
    local b = doors[wid .. ':blip']
    if b and DoesBlipExist(b) then RemoveBlip(b) end
    doors[wid .. ':blip'] = nil
end)

function Raid.Seize(car)
    local ok = lib.progressCircle({
        duration = 4000, label = 'Logging the vehicle as evidence', position = 'bottom', canCancel = true,
        disable = { move = true, combat = true }, anim = { scenario = 'WORLD_HUMAN_CLIPBOARD' },
    })
    if ok then lib.callback.await('nz_cargo:raid:seize', false, car.id) end
end

-- A crew job started by someone else in the warehouse
RegisterNetEvent('nz_cargo:crewjob:begin', function(data)
    if Client.mission then return end
    if Laptop.open then Laptop.Close(true) end
    Client.CloseUI()
    Bridge.Notify(L('crew_started', data.crewJob or 'Crew Job'), 'info', data.crewJob)
    CreateThread(function() Source.Run(data) end)
end)
