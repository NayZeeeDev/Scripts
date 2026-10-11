-- Persistent world objects created from the panel. Streamed by distance, no per-frame work.
local World = { blips = {}, props = {}, zones = {} }
local blipHandles, propHandles, zoneHandles = {}, {}, {}

-- ─── blips ──────────────────────────────────────────────────────────────
local function buildBlips(list)
    for _, b in pairs(blipHandles) do RemoveBlip(b) end
    blipHandles = {}
    for _, b in ipairs(list or {}) do
        local h = AddBlipForCoord(b.x + 0.0, b.y + 0.0, b.z + 0.0)
        SetBlipSprite(h, tonumber(b.sprite) or 1)
        SetBlipColour(h, tonumber(b.color) or 0)
        SetBlipScale(h, (tonumber(b.scale) or 0.8) + 0.0)
        SetBlipDisplay(h, tonumber(b.display) or 4)
        SetBlipAsShortRange(h, b.short_range == 1 or b.short_range == true)
        if b.category and b.category ~= '' then
            AddTextEntry('NZB_' .. b.id, b.category)
            BeginTextCommandSetBlipName('NZB_' .. b.id)
        else
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label)
        end
        EndTextCommandSetBlipName(h)
        blipHandles[b.id] = h
    end
end

-- ─── props ──────────────────────────────────────────────────────────────
local function despawnProp(id)
    local e = propHandles[id]
    if e and DoesEntityExist(e) then SetEntityAsMissionEntity(e, true, true); DeleteEntity(e) end
    propHandles[id] = nil
end

local function spawnProp(p)
    local model = joaat(p.model)
    if not IsModelInCdimage(model) or not lib.requestModel(model, 5000) then return end
    local e
    if p.type == 'ped' then
        e = CreatePed(4, model, p.x + 0.0, p.y + 0.0, p.z + 0.0, (p.rz or 0) + 0.0, false, false)
        SetBlockingOfNonTemporaryEvents(e, true)
        SetPedFleeAttributes(e, 0, false)
        SetEntityInvincible(e, true)
        if p.anim and p.anim ~= '' then
            local dict, name = p.anim:match('^(.-)@@(.+)$')
            if dict then
                lib.requestAnimDict(dict)
                TaskPlayAnim(e, dict, name, 8.0, 8.0, -1, 1, 0, false, false, false)
                RemoveAnimDict(dict)
            else
                TaskStartScenarioInPlace(e, p.anim, 0, true)
            end
        end
    elseif p.type == 'vehicle' then
        e = CreateVehicle(model, p.x + 0.0, p.y + 0.0, p.z + 0.0, (p.rz or 0) + 0.0, false, false)
        SetVehicleDoorsLocked(e, 2)
        SetEntityInvincible(e, true)
    else
        e = CreateObjectNoOffset(model, p.x + 0.0, p.y + 0.0, p.z + 0.0, false, false, false)
        SetEntityRotation(e, (p.rx or 0) + 0.0, (p.ry or 0) + 0.0, (p.rz or 0) + 0.0, 2, false)
    end
    SetModelAsNoLongerNeeded(model)
    if p.frozen ~= 0 then FreezeEntityPosition(e, true) end
    if p.collision == 0 then SetEntityCollision(e, false, false) end
    propHandles[p.id] = e
end

local propLoop = false
local function streamProps()
    if propLoop then return end
    propLoop = true
    CreateThread(function()
        while #World.props > 0 do
            local me = GetEntityCoords(cache.ped)
            local dist = Config.Props.StreamDistance
            for _, p in ipairs(World.props) do
                local near = #(me - vec3(p.x, p.y, p.z)) < dist
                if near and not propHandles[p.id] then spawnProp(p)
                elseif not near and propHandles[p.id] then despawnProp(p.id) end
            end
            Wait(Config.Props.StreamInterval)
        end
        propLoop = false
    end)
end

local function setProps(list)
    for id in pairs(propHandles) do despawnProp(id) end
    World.props = list or {}
    streamProps()
end

function GetWorldPropEntity(id) return propHandles[id] end
-- saved prop id for an entity (named so it does not shadow the IsWorldProp native)
function SavedPropId(entity)
    for id, e in pairs(propHandles) do if e == entity then return id end end
end

-- ─── zones ──────────────────────────────────────────────────────────────
local function buildZones(list)
    for _, z in pairs(zoneHandles) do z:remove() end
    zoneHandles = {}
    for _, row in ipairs(list or {}) do
        local pts = {}
        for _, p in ipairs(row.points or {}) do pts[#pts + 1] = vec3(p.x + 0.0, p.y + 0.0, p.z + 0.0) end
        if #pts >= 3 then
            local h = row.handler and ZoneHandlers[row.handler] or nil
            zoneHandles[row.id] = lib.zones.poly({
                points = pts,
                thickness = (tonumber(row.thickness) or 10) + 0.0,
                debug = row.debug == 1 or row.debug == true,
                onEnter = h and h.onEnter and function() h.onEnter(row) end or nil,
                onExit = h and h.onExit and function() h.onExit(row) end or nil,
                inside = h and h.inside and function() h.inside(row) end or nil,
            })
        end
    end
end

-- ─── sync ───────────────────────────────────────────────────────────────
RegisterNetEvent('nzadmin:cl:world', function(kind, list)
    if GetInvokingResource() then return end
    World[kind] = list or {}
    if kind == 'blips' then buildBlips(list) elseif kind == 'props' then setProps(list) elseif kind == 'zones' then buildZones(list) end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2500)
    local w = lib.callback.await('nzadmin:world', false)
    if not w then return end
    World.blips, World.zones = w.blips or {}, w.zones or {}
    buildBlips(World.blips)
    buildZones(World.zones)
    setProps(w.props)
end)

-- ─── weather / time (only when this resource owns it) ───────────────────
local function applyWeather(w)
    if not w or Toggles.localtime then return end
    SetWeatherTypeOvertimePersist(w.weather, 15.0)
    SetTimeout(15500, function()
        local cur = GlobalState.nzWeather
        if cur and cur.weather == w.weather and not Toggles.localtime then SetWeatherTypeNowPersist(w.weather) end
    end)
    SetRainLevel(w.weather:find('RAIN') and -1.0 or 0.0)
    SetForceVehicleTrails(w.weather:find('SNOW') ~= nil or w.weather == 'XMAS' or w.weather == 'BLIZZARD')
    SetForcePedFootstepsTracks(w.weather:find('SNOW') ~= nil or w.weather == 'XMAS' or w.weather == 'BLIZZARD')
    if not Toggles.blackout then SetArtificialLightsState(w.blackout == true); SetArtificialLightsStateAffectsVehicles(false) end
    local total = w.hour * 60 + w.minute
    if not w.freeze then total = total + math.floor((GetCloudTimeAsInt() - w.setAt) / 2) end
    total = total % 1440
    NetworkOverrideClockTime(total // 60, total % 60, 0)
    PauseClock(w.freeze == true)
end

function WorldWeather() applyWeather(GlobalState.nzWeather) end

AddStateBagChangeHandler('nzWeather', 'global', function(_, _, value) applyWeather(value) end)

-- re-sync the clock once a minute, only when builtin sync is in use
CreateThread(function()
    Wait(4000)
    applyWeather(GlobalState.nzWeather)
    while GlobalState.nzWeather do
        Wait(60000)
        local w = GlobalState.nzWeather
        if w and not Toggles.localtime then
            local total = w.hour * 60 + w.minute
            if not w.freeze then total = (total + math.floor((GetCloudTimeAsInt() - w.setAt) / 2)) % 1440 end
            NetworkOverrideClockTime(total // 60, total % 60, 0)
        end
    end
end)

-- ─── staff sprites (only while on duty) ─────────────────────────────────
local sprites = {}
local spriteLoop = false

local function clearSprites()
    for _, b in pairs(sprites) do RemoveBlip(b) end
    sprites = {}
end

local function startSprites()
    if spriteLoop or not Config.Staff.Sprites then return end
    spriteLoop = true
    CreateThread(function()
        while Me.isStaff and Me.duty do
            local list = lib.callback.await('nzadmin:staffSprites', false) or {}
            local seen = {}
            for _, s in ipairs(list) do
                seen[s.id] = true
                local b = sprites[s.id]
                if not b or not DoesBlipExist(b) then
                    b = AddBlipForCoord(s.x, s.y, s.z)
                    SetBlipSprite(b, s.sprite or 280)
                    SetBlipColour(b, 5)
                    SetBlipScale(b, 0.75)
                    SetBlipCategory(b, 7)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(('Staff · %s'):format(s.name))
                    EndTextCommandSetBlipName(b)
                    sprites[s.id] = b
                else
                    SetBlipCoords(b, s.x, s.y, s.z)
                end
            end
            for id, b in pairs(sprites) do if not seen[id] then RemoveBlip(b); sprites[id] = nil end end
            Wait(Config.Staff.SpriteRefresh or 4000)
        end
        clearSprites()
        spriteLoop = false
    end)
end

RegisterNetEvent('nzadmin:cl:staff', function(p) if p.isStaff and p.duty then startSprites() end end)
RegisterNetEvent('nzadmin:cl:duty', function(state) if state then SetTimeout(500, startSprites) end end)

AddEventHandler('onResourceStop', function(r)
    if r ~= NZ.Resource then return end
    for id in pairs(propHandles) do despawnProp(id) end
    for _, b in pairs(blipHandles) do RemoveBlip(b) end
    clearSprites()
end)
