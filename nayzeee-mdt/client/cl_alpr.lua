-- ═══════════════════════════════════════════════════════════
--  ALPR — automatic plate reader
--  One sweep every few seconds, one server round trip per sweep
--  no matter how many cars are around.
-- ═══════════════════════════════════════════════════════════

local recent = {}   -- [plate] = GetGameTimer() of the last read
local recentCount = 0

local function remember(plate, now)
    if not recent[plate] then recentCount = recentCount + 1 end
    recent[plate] = now
end

local function prune(now)
    if recentCount < 200 then return end
    local window = (Config.ALPR.cooldown or 45) * 1000
    recentCount = 0
    for plate, at in pairs(recent) do
        if now - at > window then recent[plate] = nil else recentCount = recentCount + 1 end
    end
end

local function report(hit)
    local first = hit.hits[1]
    lib.notify({
        title       = ('Plate reader — %s'):format(hit.plate),
        description = ('%s%s'):format(first.label, first.detail and (' · ' .. first.detail) or ''),
        type        = first.tone == 'red' and 'error' or 'warning',
        position    = 'top-right',
        duration    = 8000
    })
    if MDT.setting('sounds', true) ~= false then
        PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
    end
    if MDT.isOpen then
        SendNUIMessage({ action = 'live', event = 'alpr', data = hit })
    end
end

local function sweep()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local mine = GetVehiclePedIsIn(ped, false)
    local now = GetGameTimer()
    local window = (Config.ALPR.cooldown or 45) * 1000
    local radius = Config.ALPR.scanRadius or 25.0
    local batch = {}

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= mine and #(pos - GetEntityCoords(vehicle)) <= radius then
            local plate = MDT.plateOf(vehicle):upper()
            if plate ~= '' and (not recent[plate] or now - recent[plate] > window) then
                remember(plate, now)
                batch[#batch + 1] = plate
                if #batch >= 15 then break end
            end
        end
    end

    prune(now)
    if #batch == 0 then return end

    local hits = lib.callback.await('nz_mdt:alpr:batch', false, batch)
    if type(hits) ~= 'table' then return end
    for _, hit in ipairs(hits) do
        if hit.hits and hit.hits[1] then report(hit) end
    end
end

CreateThread(function()
    if not Config.ALPR.enabled then return end

    while true do
        local wait = (Config.ALPR.scanSeconds or 3) * 1000
        local ok = true

        if Config.ALPR.onlyOnDuty and not MDT.onDuty then ok = false end
        if ok and Config.ALPR.onlyInVehicle and not IsPedInAnyVehicle(PlayerPedId(), false) then ok = false end

        if ok then
            local success, err = pcall(sweep)
            if not success and Config.Debug then print('[nayzeee-mdt] ALPR sweep failed: ' .. tostring(err)) end
        else
            wait = 6000
        end

        Wait(wait)
    end
end)

--- Manual scan: /plate <plate>  (no plate = the vehicle you are in or next to)
RegisterCommand('plate', function(_, args)
    local plate = table.concat(args or {}, ' '):upper()
    if plate == '' then
        local veh = MDT.closestVehicle(6.0)
        if veh == 0 then
            return lib.notify({ title = 'Plate reader', description = 'Give a plate or stand next to a vehicle.', type = 'error' })
        end
        plate = MDT.plateOf(veh):upper()
    end

    local res = lib.callback.await('nz_mdt:vehicle:profile', false, plate)
    if not res or not res.ok then
        return lib.notify({ title = 'Plate reader', description = res and res.msg or 'Nothing came back.', type = 'error' })
    end

    local v = res.vehicle
    local reg = v.registration or 'valid'
    lib.notify({
        title       = ('%s · %s'):format(v.plate, v.model or 'unknown model'),
        description = ('Owner: %s%s%s%s'):format(
            v.ownerName or 'unregistered',
            v.stolen and '  ·  REPORTED STOLEN' or '',
            reg ~= 'valid' and ('  ·  registration ' .. reg) or '',
            (res.bolos and res.bolos[1] and res.bolos[1].status == 'active') and '  ·  ACTIVE BOLO' or ''),
        type        = (v.stolen or (res.bolos and res.bolos[1] and res.bolos[1].status == 'active')) and 'error' or 'inform',
        duration    = 8000
    })
end, false)
