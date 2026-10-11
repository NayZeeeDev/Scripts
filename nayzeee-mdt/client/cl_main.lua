ESX = exports['es_extended']:getSharedObject()

MDT = {
    isOpen   = false,
    opening  = false,
    booted   = nil,
    onDuty   = false,
    status   = 'available',
    identifier = nil,
    tablet   = nil,
    settings = nil
}

local KVP_SETTINGS = 'nz_mdt:settings'
local KVP_NOTES    = 'nz_mdt:notes'

-- ═══════════════════════════════════════════════════════════
--  PER-OFFICER SETTINGS  (saved on this client, read by the tablet)
-- ═══════════════════════════════════════════════════════════
local SETTING_KEYS = { 'wallpaper', 'scale', 'lockAnimation', 'bootConsole', 'sounds', 'widgetAuto', 'notifications' }

function MDT.loadSettings()
    if MDT.settings then return MDT.settings end
    local raw = GetResourceKvpString(KVP_SETTINGS)
    local ok, data = pcall(json.decode, raw or '')
    MDT.settings = (ok and type(data) == 'table') and data or {}
    return MDT.settings
end

--- Read one setting, falling back when the officer never changed it.
function MDT.setting(key, default)
    local value = MDT.loadSettings()[key]
    if value == nil then return default end
    return value
end

-- ═══════════════════════════════════════════════════════════
--  NUI BRIDGE
-- ═══════════════════════════════════════════════════════════
--- Only these server callbacks can be reached from the browser.
local ALLOWED = {
    ['nz_mdt:boot']              = true,
    ['nz_mdt:dashboard']         = true,
    ['nz_mdt:search']            = true,

    ['nz_mdt:dispatch:board']    = true,
    ['nz_mdt:dispatch:create']   = true,
    ['nz_mdt:dispatch:attach']   = true,
    ['nz_mdt:dispatch:detach']   = true,
    ['nz_mdt:dispatch:unitStatus']= true,
    ['nz_mdt:dispatch:close']    = true,
    ['nz_mdt:dispatch:waypoint'] = true,

    ['nz_mdt:bolo:list']         = true,
    ['nz_mdt:bolo:create']       = true,
    ['nz_mdt:bolo:update']       = true,
    ['nz_mdt:bolo:resolve']      = true,
    ['nz_mdt:bolo:delete']       = true,

    ['nz_mdt:warrant:list']      = true,
    ['nz_mdt:warrant:create']    = true,
    ['nz_mdt:warrant:execute']   = true,
    ['nz_mdt:warrant:void']      = true,
    ['nz_mdt:warrant:delete']    = true,

    ['nz_mdt:incident:list']     = true,
    ['nz_mdt:incident:get']      = true,
    ['nz_mdt:incident:create']   = true,
    ['nz_mdt:incident:update']   = true,
    ['nz_mdt:incident:status']   = true,
    ['nz_mdt:incident:delete']   = true,
    ['nz_mdt:charges:list']      = true,

    ['nz_mdt:evidence:list']     = true,
    ['nz_mdt:evidence:get']      = true,
    ['nz_mdt:evidence:create']   = true,
    ['nz_mdt:evidence:update']   = true,
    ['nz_mdt:evidence:checkout'] = true,
    ['nz_mdt:evidence:photo']    = true,
    ['nz_mdt:evidence:delete']   = true,

    ['nz_mdt:citizen:list']      = true,
    ['nz_mdt:citizen:profile']   = true,
    ['nz_mdt:citizen:create']    = true,
    ['nz_mdt:citizen:update']    = true,
    ['nz_mdt:citizen:licence']   = true,
    ['nz_mdt:citizen:flag']      = true,
    ['nz_mdt:citizen:delete']    = true,
    ['nz_mdt:players:search']    = true,

    ['nz_mdt:vehicle:list']      = true,
    ['nz_mdt:vehicle:profile']   = true,
    ['nz_mdt:vehicle:create']    = true,
    ['nz_mdt:vehicle:update']    = true,
    ['nz_mdt:vehicle:delete']    = true,
    ['nz_mdt:vehicle:model']     = true,

    ['nz_mdt:weapon:list']       = true,
    ['nz_mdt:weapon:profile']    = true,
    ['nz_mdt:weapon:create']     = true,
    ['nz_mdt:weapon:update']     = true,
    ['nz_mdt:weapon:delete']     = true,

    ['nz_mdt:property:list']     = true,
    ['nz_mdt:property:create']   = true,
    ['nz_mdt:property:delete']   = true,

    ['nz_mdt:officer:roster']    = true,
    ['nz_mdt:officer:callsign']  = true,
    ['nz_mdt:officer:update']    = true,

    ['nz_mdt:announce:list']     = true,
    ['nz_mdt:announce:create']   = true,
    ['nz_mdt:announce:delete']   = true,

    ['nz_mdt:notes:list']        = true,
    ['nz_mdt:notes:add']         = true,
    ['nz_mdt:notes:delete']      = true,

    ['nz_mdt:duty:toggle']       = true,
    ['nz_mdt:duty:status']       = true,
    ['nz_mdt:audit:list']        = true,

    ['nz_mdt:photo:list']        = true,
    ['nz_mdt:photo:take']        = true,
    ['nz_mdt:photo:link']        = true,
    ['nz_mdt:photo:describe']    = true,
    ['nz_mdt:photo:avatar']      = true,
    ['nz_mdt:photo:delete']      = true,
    ['nz_mdt:photo:status']      = true,

    ['nz_mdt:link:list']         = true,
    ['nz_mdt:link:create']       = true,
    ['nz_mdt:link:remove']       = true,
    ['nz_mdt:link:search']       = true,

    ['nz_mdt:camera:list']       = true,
    ['nz_mdt:camera:get']        = true,
    ['nz_mdt:camera:update']     = true,
    ['nz_mdt:camera:repair']     = true,
    ['nz_mdt:camera:delete']     = true
}

RegisterNUICallback('request', function(data, cb)
    local name = type(data) == 'table' and data.name
    if not name or not ALLOWED[name] then return cb({ ok = false, msg = 'That request is not allowed.' }) end

    local args = type(data.args) == 'table' and data.args or {}
    -- `n` comes from the tablet so a nil in the middle never shortens the list
    local n = math.min(tonumber(data.n) or #args, 8)

    local res = lib.callback.await(name, false, table.unpack(args, 1, n))
    if res == nil then res = { ok = false, msg = 'The server did not answer.' } end

    -- keep the client in step with duty changes made from the tablet
    if name == 'nz_mdt:duty:toggle' and res.ok then
        MDT.onDuty = res.onDuty == true
        MDT.status = MDT.onDuty and 'available' or 'break'
    elseif name == 'nz_mdt:duty:status' and res.ok then
        MDT.status = args[1] or MDT.status
    end

    cb(res)
end)

RegisterNUICallback('close', function(_, cb)
    MDT.close(true)
    cb(1)
end)

--- The closest vehicle: the one we sit in, otherwise anything within `radius`.
function MDT.closestVehicle(radius)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end

    local pos = GetEntityCoords(ped)
    local best, bestDist = 0, radius or 8.0
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local d = #(pos - GetEntityCoords(vehicle))
        if d < bestDist then best, bestDist = vehicle, d end
    end
    return best
end

function MDT.plateOf(vehicle)
    local plate = GetVehicleNumberPlateText(vehicle) or ''
    return (plate:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Read the plate of the closest vehicle so the tablet can pre-fill lookups.
RegisterNUICallback('nearbyPlate', function(_, cb)
    local veh = MDT.closestVehicle(8.0)
    if veh == 0 then return cb({ ok = false }) end

    local display = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local label = GetLabelText(display)
    cb({
        ok    = true,
        plate = MDT.plateOf(veh),
        model = (label and label ~= 'NULL') and label or display:lower()
    })
end)

--- ESX stores owned vehicles by model hash — turn one into a readable name.
RegisterNUICallback('modelName', function(data, cb)
    local hash = tonumber(type(data) == 'table' and data.model)
    if not hash then return cb({ ok = false }) end
    hash = math.floor(hash)
    if hash > 2147483647 then hash = hash - 4294967296 end
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return cb({ ok = false }) end
    local display = GetDisplayNameFromVehicleModel(hash)
    local label = GetLabelText(display)
    cb({ ok = true, name = (label and label ~= 'NULL') and label or display })
end)

--- Where the officer is standing, for pre-filling call and evidence locations.
RegisterNUICallback('myLocation', function(_, cb)
    local pos = GetEntityCoords(PlayerPedId())
    cb({ ok = true, street = MDT.streetName(pos), x = pos.x, y = pos.y, z = pos.z })
end)

RegisterNUICallback('settings:set', function(data, cb)
    if type(data) == 'table' then
        local clean = {}
        for _, key in ipairs(SETTING_KEYS) do clean[key] = data[key] end
        MDT.settings = clean
        SetResourceKvp(KVP_SETTINGS, json.encode(clean))
    end
    cb({ ok = true })
end)

RegisterNUICallback('notepad:get', function(_, cb)
    local ok, notes = pcall(json.decode, GetResourceKvpString(KVP_NOTES) or '[]')
    cb({ ok = true, notes = (ok and type(notes) == 'table') and notes or {} })
end)

RegisterNUICallback('notepad:set', function(data, cb)
    local notes = type(data) == 'table' and type(data.notes) == 'table' and data.notes or {}
    local out = {}
    for i, n in ipairs(notes) do
        if i > 40 then break end
        if type(n) == 'table' then
            out[#out + 1] = {
                id      = tostring(n.id or i):sub(1, 24),
                title   = tostring(n.title or ''):sub(1, 80),
                body    = tostring(n.body or ''):sub(1, 6000),
                updated = tonumber(n.updated) or 0
            }
        end
    end
    SetResourceKvp(KVP_NOTES, json.encode(out))
    cb({ ok = true })
end)

RegisterNUICallback('panic', function(_, cb)
    local ok, msg = MDT.panic()
    cb({ ok = ok, msg = msg })
end)

RegisterNUICallback('backup', function(data, cb)
    if not Config.Backup or not Config.Backup.enabled then
        return cb({ ok = false, msg = 'Backup requests are switched off.' })
    end
    local pos = GetEntityCoords(PlayerPedId())
    local res = lib.callback.await('nz_mdt:dispatch:backup', false, {
        urgency = type(data) == 'table' and tonumber(data.urgency) or 3,
        note    = type(data) == 'table' and data.note or nil,
        street  = MDT.streetName(pos),
        x = pos.x, y = pos.y, z = pos.z
    })
    cb(res or { ok = false, msg = 'The server did not answer.' })
end)

-- ═══════════════════════════════════════════════════════════
--  OPEN / CLOSE
-- ═══════════════════════════════════════════════════════════
function MDT.streetName(coords)
    local street, cross = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local name = GetStreetNameFromHashKey(street)
    if cross and cross ~= 0 then
        local crossName = GetStreetNameFromHashKey(cross)
        if crossName and crossName ~= '' then
            return ('%s / %s'):format(name, crossName)
        end
    end
    if name == '' then return GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z)) end
    return name
end

local function notify(description, kind)
    lib.notify({ title = 'MDT', description = description, type = kind or 'error' })
end

-- ── tablet prop ──────────────────────────────────────────────
local tabletCfg = Config.Tablet or {}

local function dropTablet()
    if MDT.tablet and DoesEntityExist(MDT.tablet) then
        DetachEntity(MDT.tablet, true, false)
        DeleteEntity(MDT.tablet)
    end
    MDT.tablet = nil
end

local function playTablet(show)
    if not tabletCfg.prop then return end
    local ped = PlayerPedId()

    if not show then
        dropTablet()
        if MDT.animating then
            StopAnimTask(ped, tabletCfg.dict, tabletCfg.anim, 2.0)
            RemoveAnimDict(tabletCfg.dict)
            MDT.animating = false
        end
        return
    end

    if not tabletCfg.propInVehicle and IsPedInAnyVehicle(ped, false) then return end

    local okDict = pcall(lib.requestAnimDict, tabletCfg.dict, 2000)
    local model = joaat(tabletCfg.model or 'prop_cs_tablet')
    local okModel = pcall(lib.requestModel, model, 2000)

    if okModel then
        local pos = GetEntityCoords(ped)
        dropTablet()
        MDT.tablet = CreateObject(model, pos.x, pos.y, pos.z + 0.2, true, true, false)
        SetEntityCollision(MDT.tablet, false, false)
        local off, rot = tabletCfg.offset or vec3(0.03, 0.002, 0.0), tabletCfg.rotation or vec3(10.0, 160.0, 0.0)
        AttachEntityToEntity(MDT.tablet, ped, GetPedBoneIndex(ped, tabletCfg.bone or 60309),
            off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(model)
    end

    if okDict then
        TaskPlayAnim(ped, tabletCfg.dict, tabletCfg.anim, 3.0, 3.0, -1, 49, 0, false, false, false)
        MDT.animating = true

        -- put the animation back if something knocks it off, once a second, only while open
        CreateThread(function()
            while MDT.isOpen and MDT.animating do
                Wait(1000)
                local p = PlayerPedId()
                if MDT.isOpen and not IsEntityPlayingAnim(p, tabletCfg.dict, tabletCfg.anim, 3)
                   and not IsPedInAnyVehicle(p, false) and not IsPedRagdoll(p) then
                    TaskPlayAnim(p, tabletCfg.dict, tabletCfg.anim, 3.0, 3.0, -1, 49, 0, false, false, false)
                end
            end
        end)
    end
end

local function isDown(ped)
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or IsPedRagdoll(ped) then return true end
    if IsPedCuffed(ped) then return true end
    local state = LocalPlayer and LocalPlayer.state
    return state and (state.isDead or state.dead or state.isCuffed or state.handcuffed) and true or false
end

function MDT.open(app)
    if MDT.isOpen or MDT.opening then return end
    if IsPauseMenuActive() then return end

    local ped = PlayerPedId()
    if tabletCfg.blockWhenDown and isDown(ped) then
        return notify('You cannot use the tablet right now.')
    end

    if Config.Duty.requireForMDT and not MDT.onDuty then
        return notify('Clock on duty before opening the tablet.')
    end

    if Config.Access.inVehicleOnly and not IsPedInAnyVehicle(ped, false) then
        return notify('The terminal only runs from inside a unit.')
    end

    MDT.opening = true

    if Config.Access.item and Config.Access.item.enabled then
        if not lib.callback.await('nz_mdt:item:check', false) then
            MDT.opening = false
            return notify('You need your tablet on you to do that.')
        end
    end

    local boot = lib.callback.await('nz_mdt:boot', false)
    MDT.opening = false
    if not boot then return notify('You are not on a department roster.') end

    MDT.booted = boot
    MDT.identifier = boot.me.identifier
    MDT.onDuty = boot.me.onDuty == true
    MDT.status = boot.me.status or MDT.status
    MDT.isOpen = true

    if Dispatch then Dispatch.widget = false end
    TriggerServerEvent('nz_mdt:viewing', true)

    playTablet(true)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = boot, settings = MDT.loadSettings() })
    if app then SendNUIMessage({ action = 'openApp', app = app }) end
end

--- @param fromUi boolean the tablet already hid itself
function MDT.close(fromUi)
    if not MDT.isOpen then return end
    if Cameras and Cameras.viewing then Cameras.stopView(true) end
    MDT.isOpen = false
    TriggerServerEvent('nz_mdt:viewing', false)

    playTablet(false)
    SetNuiFocus(false, false)
    if not fromUi then SendNUIMessage({ action = 'close' }) end
end

function MDT.panic()
    if not Config.Panic.enabled then return false, 'The panic button is switched off.' end
    local pos = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('nz_mdt:panic', MDT.streetName(pos), pos.x, pos.y, pos.z)
    return true
end

--- Server-pushed live updates land here and get forwarded to the browser.
RegisterNetEvent('nz_mdt:live', function(event, payload)
    if not MDT.isOpen then return end
    SendNUIMessage({ action = 'live', event = event, data = payload })
end)

RegisterNetEvent('nz_mdt:dutyChanged', function(onDuty, status)
    MDT.onDuty = onDuty == true
    MDT.status = status or (MDT.onDuty and 'available' or 'break')
    if MDT.isOpen then
        SendNUIMessage({ action = 'live', event = 'duty', data = { onDuty = MDT.onDuty, status = MDT.status } })
    end
end)

RegisterNetEvent('nz_mdt:setWaypoint', function(x, y, _, ref)
    SetNewWaypoint(x + 0.0, y + 0.0)
    lib.notify({ title = 'Route set', description = ('Navigating to %s.'):format(ref or 'the call'), type = 'inform' })
end)

RegisterNetEvent('nz_mdt:openFromItem', function()
    MDT.open()
end)

--- If the officer gets knocked down with the tablet out, put it away.
AddEventHandler('gameEventTriggered', function(name, args)
    if not MDT.isOpen or name ~= 'CEventNetworkEntityDamage' then return end
    if args[1] ~= PlayerPedId() then return end
    if tabletCfg.blockWhenDown and IsEntityDead(args[1]) then MDT.close() end
end)

-- ═══════════════════════════════════════════════════════════
--  COMMANDS & KEYS
-- ═══════════════════════════════════════════════════════════
RegisterCommand(Config.OpenCommand, function() MDT.open() end, false)

if Config.OpenKey then
    RegisterKeyMapping(Config.OpenCommand, 'Open the MDT tablet', 'keyboard', Config.OpenKey)
end

RegisterCommand(Config.PanicCommand, function() MDT.panic() end, false)

if Config.PanicKey then
    RegisterKeyMapping(Config.PanicCommand, 'Panic button', 'keyboard', Config.PanicKey)
end

-- ═══════════════════════════════════════════════════════════
--  TERMINALS
-- ═══════════════════════════════════════════════════════════
CreateThread(function()
    if Config.Access.anywhere then return end

    if Config.Access.target == 'ox_target' and GetResourceState('ox_target') == 'started' then
        for i, t in ipairs(Config.Access.terminals) do
            exports.ox_target:addBoxZone({
                coords   = t.coords,
                size     = vec3(1.2, 1.2, 1.5),
                rotation = 0,
                options  = {{
                    name     = 'nz_mdt_terminal_' .. i,
                    icon     = 'fa-solid fa-tablet-screen-button',
                    label    = t.label or 'Use the terminal',
                    distance = 1.6,
                    onSelect = function() MDT.open() end
                }}
            })
        end
        return
    end

    local shown = false
    while true do
        local sleep = 1000
        local pos = GetEntityCoords(PlayerPedId())
        local near

        for _, t in ipairs(Config.Access.terminals) do
            local d = #(pos - t.coords)
            if d < 1.6 then near = t break end
            if d < 15.0 then sleep = 250 end
        end

        if near and not MDT.isOpen then
            sleep = 0
            if not shown then
                lib.showTextUI(('[E]  %s'):format(near.label or 'Use the terminal'))
                shown = true
            end
            if IsControlJustReleased(0, 38) then
                lib.hideTextUI()
                shown = false
                MDT.open()
            end
        elseif shown then
            lib.hideTextUI()
            shown = false
        end

        Wait(sleep)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  EXPORTS
-- ═══════════════════════════════════════════════════════════
exports('openMDT', function(app) MDT.open(app) end)
exports('closeMDT', function() MDT.close() end)
exports('isOpen', function() return MDT.isOpen end)
exports('isOnDuty', function() return MDT.onDuty end)
exports('panic', function() return MDT.panic() end)

-- ═══════════════════════════════════════════════════════════
--  CLEANUP
-- ═══════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    dropTablet()
    if MDT.isOpen then
        StopAnimTask(PlayerPedId(), tabletCfg.dict, tabletCfg.anim, 2.0)
        SetNuiFocus(false, false)
    end
    lib.hideTextUI()
end)
