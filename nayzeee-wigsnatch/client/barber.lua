-- Barbers: restore your hair, undo a haircut, repair wigs

Barber = { zones = {}, blips = {} }

local CBR = Config.Barber

local function open()
    local data = lib.callback.await('nz-wig:barber', false)
    if not data then return end
    NUI.Open('barber', data)
end

RegisterNUICallback('barberRestore', function(_, cb)
    TriggerServerEvent('nz-wig:s:barberRestore')
    cb(1)
end)

RegisterNUICallback('barberRepair', function(d, cb)
    if d and d.key then TriggerServerEvent('nz-wig:s:barberRepair', d.key) end
    cb(1)
end)

RegisterNUICallback('barberFetch', function(_, cb)
    cb(lib.callback.await('nz-wig:barber', false) or false)
end)

CreateThread(function()
    if not CBR.Enabled then return end
    for i, loc in ipairs(CBR.Locations) do
        if CBR.Blips then
            local b = AddBlipForCoord(loc.x, loc.y, loc.z)
            SetBlipSprite(b, CBR.Blip.sprite)
            SetBlipColour(b, CBR.Blip.color)
            SetBlipScale(b, CBR.Blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(CBR.Blip.label)
            EndTextCommandSetBlipName(b)
            Barber.blips[#Barber.blips + 1] = b
        end

        if CB.Target ~= 'none' then
            Barber.zones[i] = CB.AddSphere('nzwig_barber_' .. i, loc, CBR.Radius, {
                { name = 'nzwig_barber', label = L('barber_open'), icon = 'fa-solid fa-scissors', distance = 2.5, onSelect = open },
            })
        else
            local zone = lib.zones.sphere({ coords = loc, radius = CBR.Radius })
            function zone:onEnter() lib.showTextUI('[E] ' .. L('barber_open')) end
            function zone:onExit() lib.hideTextUI() end
            function zone:inside()
                if IsControlJustReleased(0, 38) and not NUI.app then open() end
            end
            Barber.zones[i] = zone
        end
    end
end)

function Barber.Cleanup()
    for _, b in ipairs(Barber.blips) do RemoveBlip(b) end
    for _, z in pairs(Barber.zones) do
        if type(z) == 'table' and z.remove then z:remove() else CB.RemoveZone(z) end
    end
end
