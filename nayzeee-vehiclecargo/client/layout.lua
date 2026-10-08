-----------------------------------------------------------------
-- Owner tools: own floor layout (ghost car, scroll to rotate) and
-- the custom tracker removal spot. Opened from the laptop or by
-- command.
-----------------------------------------------------------------
Layout = {}

local function sampleModel()
    local disp = Client.inside and Client.inside.display
    local first = disp and disp.main and disp.main[1]
    return first and first.model or Config.Placer.GhostModel
end

function Layout.Start()
    if Placer.active then return end
    if not Client.inside or Client.inside.role ~= 'owner' then Bridge.Notify(L('not_owner'), 'error') return end
    if Warehouse.Floor() ~= 'main' then Warehouse.GoFloor('main') Wait(250) end
    Bridge.Notify(('Aim at the floor and place up to %d spots. ENTER saves.'):format(Config.Layout.MaxSlots), 'info', 'Floor Layout', 7000)
    local spots = Placer.Spots({
        label = 'Your floor layout', spots = Client.inside.interior.slots,
        max = Config.Layout.MaxSlots, model = sampleModel(),
    })
    if spots and not lib.callback.await('nz_cargo:layout:custom', false, spots) then
        Bridge.Notify('Layout not saved.', 'error')
    end
end

RegisterCommand(Config.Layout.Command, function() CreateThread(Layout.Start) end, false)

-- Tracker Workshop level 3: your own tracker removal spot (outside)
function Layout.TrackerSpot()
    if Client.inside then Bridge.Notify('Do this outside, where you want the spot.', 'error') return end
    local p = Placer.Point({ label = 'Tracker removal spot', kind = 'point' })
    if not p then return end
    if not lib.callback.await('nz_cargo:tracker:spot', false, { x = p.x, y = p.y, z = p.z }) then
        Bridge.Notify('You need Tracker Workshop level 3.', 'error')
    end
end

RegisterCommand('cargotrackerspot', function() CreateThread(Layout.TrackerSpot) end, false)
