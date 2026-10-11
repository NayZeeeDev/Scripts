--[[ OBD diagnostics, police inspections, GPS tracker, customer quotes and "my orders". ]]

local modalOpen = false
local function openModal(action, data)
    modalOpen = true
    UI.Send(action, data)
    UI.Focus(true)
end

-- a modal shown over the open tablet must leave the tablet usable
local function releaseFocus()
    modalOpen = false
    if not (Tablet and Tablet.open) then UI.Focus(false) end
end

UI.On('modal:close', function()
    releaseFocus()
    return true
end)

--------------------------------------------------------------------- diagnostics

local function faultCodes(veh, d)
    local codes = {}
    local function add(code, text, sev) codes[#codes + 1] = { code = code, text = text, sev = sev } end
    local eng, body, tank = GetVehicleEngineHealth(veh), GetVehicleBodyHealth(veh), GetVehiclePetrolTankHealth(veh)
    if eng < 400 then add('P0217', L('dtc_overheat'), 'high') elseif eng < 750 then add('P0300', L('dtc_misfire'), 'med') end
    if tank < 700 then add('P0455', L('dtc_evap'), 'med') end
    if body < 600 then add('B1000', L('dtc_body'), 'med') end
    local wheelNames = { [0] = 'FL', [1] = 'FR', [4] = 'RL', [5] = 'RR' }
    for i, n in pairs(wheelNames) do
        if IsVehicleTyreBurst(veh, i, false) then add('C0750', L('dtc_tyre', n), 'high') end
    end
    local w = d.wear or {}
    if (w.engine or 100) < 50 then add('P0171', L('dtc_engine_wear'), (w.engine or 100) < 25 and 'high' or 'med') end
    if (w.brakes or 100) < 40 then add('C1234', L('dtc_brakes'), 'high') end
    if (w.turbo or 100) < 40 and IsToggleModOn(veh, 18) then add('P0299', L('dtc_turbo'), 'med') end
    if (w.transmission or 100) < 40 then add('P0700', L('dtc_trans'), 'med') end
    if (w.tyres or 100) < 30 then add('C0040', L('dtc_tread'), 'med') end
    if (w.suspension or 100) < 35 then add('C0550', L('dtc_susp'), 'low') end
    if d.nitrous and (d.nitrous.amount or 0) < 5 then add('N0001', L('dtc_nitrous'), 'low') end
    if GetVehicleDirtLevel(veh) > 11.0 then add('X0010', L('dtc_dirty'), 'low') end
    return codes
end

Diagnostics = {}

-- full report for one car (server data + live readings + fault codes). Used by the scanner and the tablet.
function Diagnostics.Build(veh)
    local ok, d = lib.callback.await('nayzeee-tuning:diagnose', false, VehToNet(veh))
    if not ok then return false, d end
    local label, make = VehUtil.Label(veh)
    local perf = {}
    for _, slot in ipairs({ 11, 12, 13, 15, 16 }) do perf[tostring(slot)] = GetVehicleMod(veh, slot) end
    d.vehicle = (make ~= '' and make .. ' ' or '') .. label
    d.live = {
        engine = math.floor(GetVehicleEngineHealth(veh) / 10), body = math.floor(GetVehicleBodyHealth(veh) / 10),
        tank = math.floor(GetVehiclePetrolTankHealth(veh) / 10), fuel = math.floor(GetVehicleFuelLevel(veh)),
        oil = NZ.Round(GetVehicleOilLevel(veh), 1), dirt = math.floor(GetVehicleDirtLevel(veh) / 15 * 100),
        temp = math.floor(GetVehicleEngineTemperature(veh)), turbo = IsToggleModOn(veh, 18), perf = perf,
    }
    d.codes = faultCodes(veh, d)
    d.netId = VehToNet(veh)
    return true, d
end

local function scan(veh)
    if not veh or veh == 0 then return Notify(L('no_vehicle'), 'error') end
    if not Bridge.Progress(L('scanning'), Config.Diagnostics.ScanTime, { 'amb@world_human_clipboard@male@idle_a', 'idle_c', 49 },
        { model = joaat('prop_cs_tablet'), bone = 60309, pos = vec3(0.03, 0.002, -0.0), rot = vec3(10.0, 160.0, 0.0) }) then return end
    local ok, d = Diagnostics.Build(veh)
    if not ok then return Notify(d or L('failed'), 'error') end
    openModal('diag:open', d)
end
Diagnostics.Scan = scan

RegisterNetEvent('nayzeee-tuning:useScanner', function()
    if cache.vehicle then return scan(cache.vehicle) end
    scan(VehUtil.Closest(4.0))
end)

if Config.Diagnostics.Enabled and Config.Diagnostics.TargetForMechanics then
    Bridge.AddGlobalVehicle({
        { name = 'nzt_diag', label = L('target_diag'), icon = 'fa-laptop-medical', distance = 2.5,
          canInteract = function() return Shops.MyShop() ~= nil and Bridge.Job.onDuty end,
          onSelect = function(d) scan(d.entity) end },
    })
end

--------------------------------------------------------------------- police

local inspectVeh
local function isPolice() return Config.Police.Enabled and NZ.InList(Config.Police.Jobs, Bridge.Job.name) end

local function inspect(veh)
    if not Bridge.Progress(L('inspecting'), Config.Police.InspectTime, { 'amb@world_human_clipboard@male@idle_a', 'idle_c', 49 },
        { model = joaat('p_amb_clipboard_01'), bone = 18905, pos = vec3(0.1, 0.02, 0.08), rot = vec3(-80.0, 0.0, 0.0) }) then return end
    local props = Bridge.GetProps(veh)
    local st = Entity(veh).state.nzTune or {}
    local found = NZ.IllegalParts(props, st)
    local ok, info = lib.callback.await('nayzeee-tuning:inspectLog', false, VehToNet(veh), #found)
    if not ok then return end
    inspectVeh = veh
    local label, make = VehUtil.Label(veh)
    local tint = props.windowTint or 0
    openModal('police:open', {
        plate = VehUtil.Plate(veh), vehicle = (make ~= '' and make .. ' ' or '') .. label, illegal = found,
        registered = info.registered, km = info.km, canStrip = Config.Police.AllowStrip,
        summary = {
            nitrous = st.nitrous ~= nil, antilag = st.antilag == true, swap = st.swap and NZ.SwapBySound[st.swap] and NZ.SwapBySound[st.swap].label or nil,
            tint = tint, camber = st.stance and math.max(st.stance.cF or 0, st.stance.cR or 0) or 0, height = st.height or 0,
            airride = st.airride == true,
        },
    })
end

if Config.Police.Enabled then
    Bridge.AddGlobalVehicle({
        { name = 'nzt_inspect', label = L('target_inspect'), icon = 'fa-magnifying-glass', distance = 2.5,
          canInteract = function() return isPolice() end,
          onSelect = function(d) inspect(d.entity) end },
    })
end

-- the dialog is already closed (panels.js), so focus goes back to the game on every path
UI.On('police:strip', function(d)
    releaseFocus()
    if not inspectVeh or not DoesEntityExist(inspectVeh) or type(d.ids) ~= 'table' then return false end
    if not Bridge.Progress(L('stripping'), Config.Police.StripTime, { 'mini@repair', 'fixing_a_ped', 1 }) then return false end
    local ok, err = lib.callback.await('nayzeee-tuning:strip', false, VehToNet(inspectVeh), d.ids)
    Notify(ok and L('stripped') or (err or L('failed')), ok and 'success' or 'error')
    return ok
end)

--------------------------------------------------------------------- GPS tracker

local pingBlip
if Config.Locator.Enabled then
    RegisterCommand(Config.Locator.Command, function()
        local list = lib.callback.await('nayzeee-tuning:locatorList', false)
        if #list == 0 then return Notify(L('no_trackers'), 'error') end
        openModal('locator:open', { list = list })
    end, false)
end

Locator = {}

function Locator.Ping(plate, route)
    local ok, res = lib.callback.await('nayzeee-tuning:locate', false, plate)
    if not ok then return { ok = false, error = res } end
    local d = { plate = plate, route = route }
    if pingBlip and DoesBlipExist(pingBlip) then RemoveBlip(pingBlip) end
    pingBlip = AddBlipForCoord(res.x, res.y, res.z)
    SetBlipSprite(pingBlip, 225)
    SetBlipColour(pingBlip, 5)
    SetBlipFlashes(pingBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('tracker_blip', d.plate))
    EndTextCommandSetBlipName(pingBlip)
    if d.route then SetBlipRoute(pingBlip, true) end
    local b = pingBlip
    SetTimeout(Config.Locator.BlipTime * 1000, function() if DoesBlipExist(b) then RemoveBlip(b) end end)
    return { ok = true, street = GetStreetNameFromHashKey(GetStreetNameAtCoord(res.x, res.y, res.z)) }
end

UI.On('locator:ping', function(d) return Locator.Ping(d.plate, d.route) end)

--------------------------------------------------------------------- customer quotes

RegisterNetEvent('nayzeee-tuning:quote', function(q)
    if Menu.open then return end
    openModal('quote:open', q)
    UI.Send('sound', { name = 'ping', volume = 0.4 })
end)

UI.On('quote:answer', function(d)
    local ok, res = lib.callback.await('nayzeee-tuning:answerQuote', false, d.id, d.accept == true, d.payment, d.code)
    if ok or not d.accept then releaseFocus() end
    if ok and d.accept then Notify(L('quote_paid', res.orderId), 'success') end
    return { ok = ok, error = not ok and res or nil }
end)

UI.On('quote:code', function(d)
    local ok, res = lib.callback.await('nayzeee-tuning:checkCode', false, d.shopId, d.code)
    return { ok = ok, data = res }
end)

--------------------------------------------------------------------- my orders

RegisterCommand('myorders', function()
    local list = lib.callback.await('nayzeee-tuning:myOrders', false)
    if #list == 0 then return Notify(L('no_orders'), 'inform') end
    openModal('orders:mine', { list = list })
end, false)

UI.On('orders:cancel', function(d)
    local ok, err = lib.callback.await('nayzeee-tuning:orderCancel', false, d.id)
    return { ok = ok, error = not ok and err or nil }
end)
