-- ═══════════════════════════════════════════════════════════════
--  FUNERAL HOME (client)
--  Every location is a third-eye spot that opens a menu.
-- ═══════════════════════════════════════════════════════════════
local F = Config.Funeral

local function plotStates() return GlobalState.nzFuneralPlots or {} end

-- closest plot within radius -> index, state ('free'|'placed'|'service'|'memorial')
function NearestPlot(coords, radius)
    if not FuneralEnabled() then return nil end
    local best, bestDist
    for i, plot in ipairs(F.Plots) do
        local d = #(coords - plot.coords)
        if d <= (radius or 4.0) and (not bestDist or d < bestDist) then best, bestDist = i, d end
    end
    if not best then return nil end
    local st = plotStates()[best]
    return best, st and st.s or 'free'
end

-- ═══════════════════════════════════════════════════════════════
--  ACTIONS (also used by the [H] carry menu + headstone menu)
-- ═══════════════════════════════════════════════════════════════
function StoreInMorgue()
    if IsBusy() or not Carrying.entity then return end
    local netId = Carrying.netId
    if not Progress('Logging the body into the morgue...', F.Morgue.StoreTime) then return end
    if lib.callback.await('nayzeee-bodybag:funeral:storeBody', false, netId) then
        StopCarrying(false, true)
    end
end

function PlaceCasket(plotIndex)
    if IsBusy() or Carrying.kind ~= 'coffin' then return end
    local netId = Carrying.netId
    if not Progress('Setting the casket down...', 4000) then return end
    if lib.callback.await('nayzeee-bodybag:funeral:placeCasket', false, plotIndex, netId) then
        StopCarrying(false, true)
    end
end

function PayRespects(ent, plotIndex)
    if IsBusy() then return end
    PlayAnim('amb@medic@standing@kneel@base', 'base', 1)
    local ok = Progress('Paying your respects...', 5000)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:memorialRespects', plotIndex) end
end

function LayFlowers(ent, plotIndex)
    if IsBusy() then return end
    PlayAnim('amb@medic@standing@kneel@base', 'base', 1)
    local ok = Progress('Laying flowers...', 3000)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:memorialFlowers', plotIndex) end
end

-- ═══════════════════════════════════════════════════════════════
--  ANNOUNCEMENTS - "a funeral is being held" + a blip while it runs
-- ═══════════════════════════════════════════════════════════════
local serviceBlips = {}
RegisterNetEvent('nayzeee-bodybag:client:funeralAnnounce', function(coords, name, started)
    local key = ('%.0f:%.0f'):format(coords.x, coords.y)
    if serviceBlips[key] then RemoveBlip(serviceBlips[key]) serviceBlips[key] = nil end
    if not started then return end

    Config.Notify(('A funeral for %s is being held at the cemetery. All are welcome.'):format(name), 'inform', 'Funeral')
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, F.Blip.Sprite)
    SetBlipColour(blip, F.Blip.Colour)
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Funeral: ' .. name)
    EndTextCommandSetBlipName(blip)
    serviceBlips[key] = blip
    SetTimeout(30 * 60000, function() -- safety: never leave it forever
        if serviceBlips[key] == blip then RemoveBlip(blip) serviceBlips[key] = nil end
    end)
end)

if not FuneralEnabled() then return end
local L = F.Locations

-- ═══════════════════════════════════════════════════════════════
--  DUTY + GARAGE
-- ═══════════════════════════════════════════════════════════════
local function isEmployee() return MyJob().name == F.Job end

local function openDutyMenu()
    ShowActions('nz_f_duty', 'Funeral Home  •  ' .. (LocalPlayer.state.nzFuneralDuty and 'ON duty' or 'off duty'), {
        { title = LocalPlayer.state.nzFuneralDuty and 'Clock Out' or 'Clock In', icon = 'clock',
          description = 'On-duty staff get coroner calls and can use the garage, morgue and crematory.',
          available = isEmployee(), reason = 'You don\'t work here',
          onSelect = function() TriggerServerEvent('nayzeee-bodybag:server:funeralDuty') end },
        { title = 'How The Job Works', icon = 'circle-info', description = 'Open the guide.',
          onSelect = OpenHelp },
    })
end

local myHearse
local function takeHearse()
    if not Progress('Getting the keys...', 2000) then return end
    local res = lib.callback.await('nayzeee-bodybag:funeral:takeHearse', false)
    if type(res) ~= 'table' then return end
    local timeout, veh = GetGameTimer() + 5000, nil
    repeat
        veh = EntFromNet(res.netId)
        if not veh then Wait(50) end
    until veh or GetGameTimer() > timeout
    if not veh then return Config.Notify('The hearse didn\'t arrive - try again.', 'error') end
    myHearse = veh
    SetVehicleOnGroundProperly(veh)
    TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    Config.Hooks.GiveVehicleKeys(veh, res.plate)
    Config.Notify(('Hearse %s is yours. It holds up to %d bodies.'):format(res.plate, TrunkRules(F.Hearse.Model).MaxBodies), 'success', 'Funeral Home')
    Tip('Coroner calls show up on your map. Load bodies in through the back of the hearse.')
end

local function openGarageMenu()
    ShowActions('nz_f_garage', 'Hearse Garage', {
        { title = 'Take A Hearse', icon = 'car', description = 'Romero Hearse - fits coffins and body bags.',
          available = IsFuneralJob('Hearse'), reason = isEmployee() and 'Clock in first' or 'Funeral staff only',
          onSelect = takeHearse },
        { title = 'Return Your Hearse', icon = 'square-parking', description = 'Park it nearby first. Unload any bodies.',
          available = isEmployee(), reason = 'Funeral staff only',
          onSelect = function() TriggerServerEvent('nayzeee-bodybag:server:funeralReturnHearse') end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  MORGUE RECORDS
-- ═══════════════════════════════════════════════════════════════
local function recordTitle(r) return ('#%d  %s'):format(r.id, r.name) end

local function openRecord(r)
    local prepared = r.status == 'prepared'
    local desc = ('Logged %s by %s  •  condition: %s'):format(r.date, r.storedBy or '?', r.stage or '?')
    local actions = {
        { title = recordTitle(r), icon = 'file-lines', readOnly = true, description = desc,
          metadata = r.dna and { { label = 'DNA traces', value = #r.dna > 0 and table.concat(r.dna, ', ') or 'none' } } or nil },
        { title = 'Issue Death Certificate', icon = 'file-signature',
          description = 'An item with the name, date and condition. Give it to the family.',
          available = IsFuneralJob('Certificate'), reason = 'Needs a higher job grade (or clock in)',
          onSelect = function() TriggerServerEvent('nayzeee-bodybag:server:funeralCertificate', r.id) end },
        { title = 'Prepare For A Funeral', icon = 'cross',
          description = 'Embalm the body and lay it in a coffin on the prep table.',
          metadata = { { label = 'Needs', value = ItemLabel(Config.Items.coffin) } },
          available = IsFuneralJob('Morgue') and not prepared and HasItem(Config.Items.coffin),
          reason = prepared and 'Already in a coffin' or (IsFuneralJob('Morgue') and 'You need a coffin (sold at the counter)' or 'Clock in first'),
          onSelect = function()
              if Progress('Embalming the body...', 8000) then
                  lib.callback.await('nayzeee-bodybag:funeral:prepare', false, r.id)
              end
          end },
        { title = 'Discard Record', icon = 'trash', hidden = not IsFuneralJob('ClearPlot'),
          description = 'Director only. Removes the body and its record for good.',
          onSelect = function()
              if lib.alertDialog({ header = 'Discard record?', content = ('Remove **%s** from the morgue?'):format(r.name),
                  centered = true, cancel = true }) == 'confirm' then
                  TriggerServerEvent('nayzeee-bodybag:server:funeralDiscard', r.id)
              end
          end },
    }
    ShowActions('nz_f_record', 'Morgue Record', actions, 'nz_f_records')
end

local function openRecords(onPick, title, filter)
    local list = lib.callback.await('nayzeee-bodybag:funeral:records', false)
    if not list then return Config.Notify('You can\'t access the records.', 'error') end
    local options = {}
    for _, r in ipairs(list) do
        if not filter or filter(r) then
            options[#options + 1] = {
                title = recordTitle(r), icon = r.status == 'prepared' and 'cross' or 'temperature-low',
                iconColor = Config.UI.Accent, arrow = true,
                description = ('%s  •  %s  •  %s'):format(r.date, r.stage or '?', r.status == 'prepared' and 'in a coffin' or 'in a drawer'),
                onSelect = function() onPick(r) end,
            }
        end
    end
    if #options == 0 then options[1] = { title = 'No bodies here', icon = 'circle-check', disabled = true } end
    lib.registerContext({ id = 'nz_f_records', title = title or 'Morgue Records', options = options })
    lib.showContext('nz_f_records')
end

local function openMorgueMenu()
    local police = IsPoliceJob()
    ShowActions('nz_f_morgue', 'Morgue', {
        { title = 'Store The Body You\'re Carrying', icon = 'temperature-low',
          description = 'Logs the body and pays you. Then hold a funeral, cremate or certify.',
          available = IsFuneralJob('Morgue') and Carrying.entity ~= nil,
          reason = not IsFuneralJob('Morgue') and 'Funeral staff on duty only' or 'Carry a body here first',
          onSelect = StoreInMorgue },
        { title = 'Records', icon = 'folder-open', arrow = true,
          description = police and 'Police: see every body and its DNA.' or 'Every body currently in the morgue.',
          available = IsFuneralJob() or police, reason = 'Staff and police only',
          onSelect = function() openRecords(openRecord) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  CREMATORY
-- ═══════════════════════════════════════════════════════════════
local function cremate(r)
    if lib.alertDialog({ header = 'Cremate?', centered = true, cancel = true,
        content = ('Cremate **%s**? You will receive an urn with their ashes.'):format(r.name) }) ~= 'confirm' then return end
    PlayAnim('anim@amb@business@weed@weed_inspecting_lo_med_hi@', 'weed_crouch_checkingleaves_idle_01_inspector', 1)
    local ok = Progress('Cremating ' .. r.name .. '...', F.Cremation.Time)
    ClearPedTasks(cache.ped)
    if ok then lib.callback.await('nayzeee-bodybag:funeral:cremate', false, r.id) end
end

local function openCrematoryMenu()
    ShowActions('nz_f_crem', 'Crematory', {
        { title = 'Cremate A Body', icon = 'fire', arrow = true,
          description = 'Pick a body from the morgue. You get a named urn (and paid).',
          available = IsFuneralJob('Cremate'), reason = isEmployee() and 'Needs a higher job grade (or clock in)' or 'Funeral staff only',
          onSelect = function() openRecords(cremate, 'Choose who to cremate', function(r) return r.status == 'stored' end) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  SHOP (anyone)
-- ═══════════════════════════════════════════════════════════════
local function openShop()
    local actions = {}
    for i, entry in ipairs(F.Shop.Items) do
        actions[#actions + 1] = {
            title = ('%s  -  $%d'):format(entry.label, entry.price), icon = 'cart-shopping',
            description = entry.jobOnly and 'Staff only' or 'Available to everyone',
            available = not entry.jobOnly or IsFuneralJob(), reason = 'Funeral staff only',
            onSelect = function()
                local input = lib.inputDialog('Buy ' .. entry.label, {
                    { type = 'number', label = 'How many?', default = 1, min = 1, max = 10, required = true },
                })
                if input and input[1] then lib.callback.await('nayzeee-bodybag:funeral:buy', false, i, input[1]) end
            end,
        }
    end
    ShowActions('nz_f_shop', ('Funeral Home Counter  •  paid in %s'):format(F.Shop.Account == 'bank' and 'bank' or 'cash'), actions)
end

-- ═══════════════════════════════════════════════════════════════
--  CEMETERY PLOTS
-- ═══════════════════════════════════════════════════════════════
local function openPlotMenu(i)
    local st = plotStates()[i] or { s = 'free' }
    local director = IsFuneralJob('Service')
    local title = ('Plot %d  •  %s'):format(i, ({ free = 'free', placed = 'casket placed', service = 'service in progress', memorial = 'occupied' })[st.s] or st.s)

    ShowActions('nz_f_plot', title, {
        { title = st.name and ('Here lies: ' .. st.name) or 'An empty plot', icon = 'cross', readOnly = true,
          description = st.s == 'free' and 'Funeral directors can hold a service here.' or nil },
        { title = 'Place Casket', icon = 'arrow-down', hidden = not director or st.s ~= 'free',
          description = 'Set down the coffin you\'re carrying.',
          available = Carrying.kind == 'coffin', reason = 'Carry a coffin here (prepare one at the morgue)',
          onSelect = function() PlaceCasket(i) end },
        { title = 'Begin Service', icon = 'book-bible', hidden = not director or st.s ~= 'placed',
          description = 'Write the epitaph. Mourners nearby are told the service has started.',
          onSelect = function()
              local input = lib.inputDialog('Funeral of ' .. (st.name or 'the deceased'), {
                  { type = 'input', label = 'Epitaph (written on the headstone)', placeholder = 'Beloved friend. Gone too soon.',
                    max = F.Service.EpitaphMaxLength },
              })
              if input then TriggerServerEvent('nayzeee-bodybag:server:funeralBegin', i, input[1] or '') end
          end },
        { title = 'Lower The Casket', icon = 'hands-praying', hidden = not director or st.s ~= 'service',
          description = ('Ends the service. A headstone is raised and you get paid. (Allowed after %s.)'):format(FormatTime(F.Service.MinDuration)),
          onSelect = function()
              if Progress('Lowering the casket...', 6000) then
                  TriggerServerEvent('nayzeee-bodybag:server:funeralLower', i)
              end
          end },
        { title = 'Cancel', icon = 'xmark', hidden = not director or (st.s ~= 'placed' and st.s ~= 'service'),
          description = 'The coffin goes back on the ground.',
          onSelect = function() TriggerServerEvent('nayzeee-bodybag:server:funeralCancel', i) end },
    })
end

-- ═══════════════════════════════════════════════════════════════
--  MAP BLIP + THIRD-EYE SPOTS
-- ═══════════════════════════════════════════════════════════════
CreateThread(function()
    if F.Blip.Enabled then
        local blip = AddBlipForCoord(L.Duty.x, L.Duty.y, L.Duty.z)
        SetBlipSprite(blip, F.Blip.Sprite)
        SetBlipColour(blip, F.Blip.Colour)
        SetBlipScale(blip, F.Blip.Scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(F.Blip.Label)
        EndTextCommandSetBlipName(blip)
    end

    local function spot(name, coords, label, icon, fn, canInteract)
        exports.ox_target:addSphereZone({
            coords = vector3(coords.x, coords.y, coords.z), radius = 1.5, name = 'nz_f_' .. name,
            options = { { name = 'nz_f_' .. name, label = label, icon = icon, distance = 2.5,
                canInteract = canInteract, onSelect = fn } },
        })
    end

    spot('duty', L.Duty, 'Funeral Home Staff', 'fas fa-clock', openDutyMenu, isEmployee)
    spot('garage', L.Garage, 'Hearse Garage', 'fas fa-car', openGarageMenu, isEmployee)
    spot('morgue', L.Morgue, 'Morgue', 'fas fa-temperature-low', openMorgueMenu,
        function() return isEmployee() or IsPoliceJob() end)
    spot('crematory', L.Crematory, 'Crematory', 'fas fa-fire', openCrematoryMenu, isEmployee)
    spot('shop', L.Shop, 'Funeral Home Counter', 'fas fa-cart-shopping', openShop)

    for i, plot in ipairs(F.Plots) do
        exports.ox_target:addSphereZone({
            coords = PlotCasketCoords(plot), radius = 1.6, name = 'nz_f_plot_' .. i,
            options = { { name = 'nz_f_plot_' .. i, label = ('Cemetery Plot %d'):format(i), icon = 'fas fa-cross',
                distance = 3.0,
                canInteract = function()
                    local st = plotStates()[i]
                    return isEmployee() or (st and st.s ~= 'free' and st.s ~= 'memorial')
                end,
                onSelect = function() openPlotMenu(i) end } },
        })
    end
end)

-- going off duty / losing the job -> tell the player
AddStateBagChangeHandler('nzFuneralDuty', ('player:%s'):format(cache.serverId), function(_, _, value)
    if value == false and myHearse and DoesEntityExist(myHearse) then
        Config.Notify('You\'re off duty. Return your hearse to the garage.', 'inform', 'Funeral Home')
    end
end)
