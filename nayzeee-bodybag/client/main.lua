ESX = exports.es_extended:getSharedObject()

-- ═══════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════
Carrying = { entity = nil, netId = nil, kind = nil }   -- what I'm holding (bag/crate/coffin)

-- ═══════════════════════════════════════════════════════════════
--  HELPERS (used by every client file)
-- ═══════════════════════════════════════════════════════════════
-- server -> client notify, always in the NAYZEEE style
RegisterNetEvent('nayzeee-bodybag:client:notify', function(msg, type, title)
    Config.Notify(msg, type, title)
end)

function Tip(msg)
    if Config.Tips then Config.Notify(msg, 'inform', 'Next step') end
end

function ShowHint(text)
    lib.showTextUI(text, {
        position = 'bottom-center',
        style = { backgroundColor = Config.UI.Background, color = Config.UI.Accent, borderRadius = Config.UI.Radius },
    })
end

function HideHint() lib.hideTextUI() end

function HasItem(name, amount)
    local count = exports.ox_inventory:Search('count', name)
    return (type(count) == 'number' and count or 0) >= (amount or 1)
end

-- "Shovel" instead of "shovel" for menus
function ItemLabel(name)
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    return ok and type(item) == 'table' and item.label or name
end

function LoadModel(model)
    lib.requestModel(model, 5000)
    return HasModelLoaded(model)
end

function PlayAnim(dict, clip, flag, duration)
    lib.requestAnimDict(dict, 5000)
    TaskPlayAnim(cache.ped, dict, clip, 8.0, -8.0, duration or -1, flag or 1, 0, false, false, false)
end

-- standard "do a thing" progress bar: can't move, drive or fight while it runs
function Progress(label, duration)
    return lib.progressBar({
        duration = duration, label = label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
end

-- true while another progress bar is running (stops double actions)
function IsBusy()
    return lib.progressActive and lib.progressActive() or false
end

function NetOf(entity) return NetworkGetNetworkIdFromEntity(entity) end

function EntFromNet(netId)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
    local ent = NetworkGetEntityFromNetworkId(netId)
    return (ent ~= 0 and DoesEntityExist(ent)) and ent or nil
end

function ServerIdOfPed(ped)
    local index = NetworkGetPlayerIndexFromPed(ped)
    if index == -1 then return nil end
    local sid = GetPlayerServerId(index)
    return (sid and sid > 0) and sid or nil
end

function MyJob()
    local data = ESX.GetPlayerData()
    return data and data.job or {}
end

function IsPoliceJob()
    return Config.Evidence.PoliceJobs[MyJob().name or ''] == true
end

-- funeral employee, on duty, with at least the grade for gradeKey (Config.Funeral.Grades)
function IsFuneralJob(gradeKey)
    if not FuneralEnabled() then return false end
    local job = MyJob()
    if job.name ~= Config.Funeral.Job then return false end
    if Config.Funeral.RequireDuty and not LocalPlayer.state.nzFuneralDuty then return false end
    return (job.grade or 0) >= (gradeKey and Config.Funeral.Grades[gradeKey] or 0)
end

-- dead = GTA dead OR the ambulance script says so (wasabi 'dead', others 'isDead')
function IsPlayerTrulyDead(ped)
    if IsPedDeadOrDying(ped, true) then return true end
    local sid = ServerIdOfPed(ped)
    if sid then
        local st = Player(sid).state
        if st and (st.dead or st.isDead) then return true end
    end
    return false
end

-- works for players AND NPCs
function IsBodyDead(ped)
    if IsPedAPlayer(ped) then return IsPlayerTrulyDead(ped) end
    return IsPedDeadOrDying(ped, true)
end

-- how the server identifies a body: { player = serverId } or { npc = pedNetId }
function BodyRef(ped)
    if IsPedAPlayer(ped) then
        local sid = ServerIdOfPed(ped)
        return sid and { player = sid } or nil
    end
    if not Config.AllowNPCBodies or not NetworkGetEntityIsNetworked(ped) then return nil end
    return { npc = PedToNet(ped) }
end

function BodyState(entity) return Entity(entity).state.nzBody end

-- first entity near coords whose statebag passes check(state)
function FindNearbyObject(coords, radius, check)
    for _, o in ipairs(lib.getNearbyObjects(coords, radius)) do
        if check(Entity(o.object).state, o.object) then return o.object end
    end
    return nil
end

-- empty crate/coffin within Config.DirectLoad.Radius
function NearbyEmpty(coords, radius)
    return FindNearbyObject(coords, radius or Config.DirectLoad.Radius, function(s) return s.nzEmpty ~= nil end)
end

-- ═══════════════════════════════════════════════════════════════
--  PROP SETTLING - props are spawned SERVER-SIDE (anti-cheat safe).
--  The client that OWNS a new prop drops it onto the ground once.
-- ═══════════════════════════════════════════════════════════════
AddStateBagChangeHandler('nzInit', nil, function(bagName, _, value)
    if not value then return end
    CreateThread(function()
        -- the entity may not exist on our side yet when the state arrives
        local entity, timeout = 0, GetGameTimer() + 3000
        repeat
            entity = GetEntityFromStateBagName(bagName)
            if entity == 0 then Wait(50) end
        until entity ~= 0 or GetGameTimer() > timeout
        if entity == 0 or not DoesEntityExist(entity) then return end
        if NetworkGetEntityOwner(entity) ~= cache.playerId then return end
        if IsEntityAttached(entity) then return end

        FreezeEntityPosition(entity, false)
        PlaceObjectOnGroundProperly(entity)
        FreezeEntityPosition(entity, true)
        TriggerServerEvent('nayzeee-bodybag:server:settled', NetOf(entity))
    end)
end)

-- ═══════════════════════════════════════════════════════════════
--  ACTIONS ON A LOOSE BODY
-- ═══════════════════════════════════════════════════════════════
function BagBody(ped)
    if IsBusy() then return end
    if Carrying.entity then return Config.Notify('Your hands are full', 'error') end
    if Config.OnlyDeadBodies and not IsBodyDead(ped) then
        return Config.Notify('They\'re still breathing...', 'error')
    end
    local ref = BodyRef(ped)
    if not ref then return Config.Notify('You can\'t bag that body', 'error') end
    if not HasItem(Config.Items.bodybag) then return Config.Notify('You need a body bag', 'error') end

    PlayAnim('anim@gangops@facility@servers@bodysearch@', 'player_search', 1)
    local ok = Progress('Zipping the body bag...', Config.BagTime)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:bagBody', ref) end
end

function DirectLoad(ped)
    if IsBusy() then return end
    local target = NearbyEmpty(GetEntityCoords(ped))
    local ref = BodyRef(ped)
    if not target or not ref then return Config.Notify('There\'s no empty crate or coffin next to the body', 'error') end
    PlayAnim('anim@gangops@facility@servers@bodysearch@', 'player_search', 1)
    local ok = Progress('Loading the body in...', Config.LoadTime)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:directLoad', ref, NetOf(target)) end
end

function CallCoroner(coords)
    if not Progress('Calling the coroner...', 2500) then return end
    TriggerServerEvent('nayzeee-bodybag:server:callCoroner', coords)
end

-- ═══════════════════════════════════════════════════════════════
--  INSPECT A BODY (bag / crate / coffin / barrel)
-- ═══════════════════════════════════════════════════════════════
function InspectBody(entity)
    local info = lib.callback.await('nayzeee-bodybag:inspect', false, NetOf(entity))
    if not info then return Config.Notify('It\'s empty', 'inform') end

    local state = BodyState(entity)
    local rows = {
        { title = info.name or 'John Doe', icon = 'skull',
          description = info.name and 'Identity confirmed'
              or (info.npc and 'Nobody you recognise' or 'Unidentifiable remains') },
        { title = 'Condition: ' .. (info.stage or 'fresh'), icon = 'biohazard',
          description = info.stage == 'embalmed' and 'Prepared by the funeral home' or 'Bodies rot over time - and start to smell' },
    }
    if info.dna then
        rows[#rows + 1] = {
            title = #info.dna > 0 and ('DNA traces: ' .. table.concat(info.dna, ', ')) or 'No usable DNA traces',
            icon = 'dna', description = 'Police forensics - everyone who handled this body',
        }
    end
    lib.registerContext({ id = 'nz_inspect', title = KindLabel(state and state.kind), options = rows })
    lib.showContext('nz_inspect')
end

-- ═══════════════════════════════════════════════════════════════
--  DEPLOY CONTAINERS (crate / coffin / barrel) - use the item
-- ═══════════════════════════════════════════════════════════════
local deployLabels = { crate = 'Placing crate...', coffin = 'Placing coffin...', barrel = 'Setting up barrel...' }

local itemToKind = {
    [Config.Items.burnBarrel] = 'barrel',
    [Config.Items.bodyCrate]  = 'crate',
    [Config.Items.coffin]     = 'coffin',
}

local function deployContainer(kind)
    if IsBusy() then return end
    if Carrying.entity then return Config.Notify('Drop what you\'re carrying first', 'error') end
    if IsPedInAnyVehicle(cache.ped, false) then return Config.Notify('Get out of the vehicle first', 'error') end
    if not Progress(deployLabels[kind] or 'Placing...', 3000) then return end
    TriggerServerEvent('nayzeee-bodybag:server:deployContainer', kind,
        GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 1.5, GetEntityHeading(cache.ped))
end

RegisterNetEvent('nayzeee-bodybag:client:useItem', function(item)
    local kind = itemToKind[item]
    if kind then deployContainer(kind) end
end)

-- ═══════════════════════════════════════════════════════════════
--  LOAD / REMOVE / PACK UP
-- ═══════════════════════════════════════════════════════════════
function RemoveBodyFrom(containerEnt)
    if IsBusy() then return end
    if not Progress('Taking the body out...', Config.RemoveBody.Time or 5000) then return end
    TriggerServerEvent('nayzeee-bodybag:server:removeBody', NetOf(containerEnt))
end

-- carried bag -> placed empty crate/coffin
function LoadIntoPlaced(targetEnt)
    if IsBusy() then return end
    if Carrying.kind ~= 'bodybag' then return Config.Notify('You need to be carrying a body bag', 'error') end
    local kind = Entity(targetEnt).state.nzEmpty
    local bagNetId = Carrying.netId
    if not Progress(('Loading the body into the %s...'):format(KindLabel(kind):lower()), Config.LoadTime) then return end
    if lib.callback.await('nayzeee-bodybag:loadContainer', false, NetOf(targetEnt), bagNetId) then
        StopCarrying(false, true)
    else
        Config.Notify('Couldn\'t load it - get closer', 'error')
    end
end

function PackUpEmpty(entity)
    if IsBusy() then return end
    if not Progress('Packing it up...', 2000) then return end
    TriggerServerEvent('nayzeee-bodybag:server:pickupEmpty', NetOf(entity))
end

function PackUpBarrel(entity)
    if IsBusy() then return end
    if not Progress('Packing up the barrel...', 2000) then return end
    TriggerServerEvent('nayzeee-bodybag:server:pickupBarrel', NetOf(entity))
end

-- ═══════════════════════════════════════════════════════════════
--  THIRD-EYE: ONE option per object -> opens its action menu
--  (all menus live in client/menus.lua)
-- ═══════════════════════════════════════════════════════════════
CreateThread(function()
    -- dead bodies (players + NPCs)
    local bodyOption = {
        name = 'nz_body', icon = 'fas fa-skull', label = 'Handle Body', distance = 2.0,
        canInteract = function(entity) return not Carrying.entity and IsBodyDead(entity) end,
        onSelect = function(d) OpenBodyMenu(d.entity) end,
    }
    exports.ox_target:addGlobalPlayer({ bodyOption })
    if Config.AllowNPCBodies then
        exports.ox_target:addGlobalPed({ {
            name = 'nz_body_npc', icon = 'fas fa-skull', label = 'Handle Body', distance = 2.0,
            canInteract = function(entity)
                return not Carrying.entity and not IsPedAPlayer(entity) and IsBodyDead(entity)
            end,
            onSelect = function(d) OpenBodyMenu(d.entity) end,
        } })
    end

    -- bag / crate / coffin (full OR empty)
    for _, def in ipairs({
        { model = Config.Props.bodybag, kind = 'bodybag', icon = 'fas fa-bag-shopping' },
        { model = Config.Props.crate,   kind = 'crate',   icon = 'fas fa-box' },
        { model = Config.Props.coffin,  kind = 'coffin',  icon = 'fas fa-cross' },
    }) do
        exports.ox_target:addModel(def.model, { {
            name = 'nz_container_' .. def.kind, icon = def.icon, label = KindLabel(def.kind), distance = 2.5,
            canInteract = function(e) local s = Entity(e).state return s.nzBody ~= nil or s.nzEmpty ~= nil end,
            onSelect = function(d) OpenContainerMenu(d.entity) end,
        } })
    end

    -- burn barrel
    exports.ox_target:addModel(Config.Props.barrel, { {
        name = 'nz_barrel', icon = 'fas fa-fire', label = KindLabel('barrel'), distance = 2.5,
        canInteract = function(e) return Entity(e).state.nzBarrel ~= nil end,
        onSelect = function(d) OpenBarrelMenu(d.entity) end,
    } })

    -- graves, cemetery tombstones and funeral headstones
    exports.ox_target:addModel({ Config.Props.shallowGrave, Config.Props.tombstone }, { {
        name = 'nz_grave', icon = 'fas fa-cross', label = 'Grave', distance = 2.5,
        canInteract = function(e) local s = Entity(e).state return s.nzGrave ~= nil or s.nzMemorial ~= nil end,
        onSelect = function(d) OpenGraveMenu(d.entity) end,
    } })

    -- cemetery body hole + water dump spots: third-eye works too (same as the [H] carry menu)
    if Config.Burial.Cemetery.Enabled then
        exports.ox_target:addSphereZone({
            coords = Config.Burial.Cemetery.Coords, radius = 2.5, name = 'nz_grave_hole',
            options = { {
                name = 'nz_place_in_grave', icon = 'fas fa-arrow-down', label = 'Lower Into Grave',
                canInteract = function() return Carrying.entity ~= nil end,
                onSelect = function() PlaceInGraveHole() end,
            } },
        })
    end
    for i, zone in ipairs(Config.WaterDump.Zones) do
        exports.ox_target:addSphereZone({
            coords = zone.coords, radius = zone.radius or 4.0, name = 'nz_dump_' .. i,
            options = { {
                name = 'nz_dump_body_' .. i, icon = 'fas fa-water', label = 'Dump Body In The Water',
                canInteract = function() return Carrying.entity ~= nil end,
                onSelect = function() DumpCarried() end,
            } },
        })
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  EXPORTS for other resources
-- ═══════════════════════════════════════════════════════════════
-- exports['nayzeee-bodybag']:IsCarrying() -> 'bodybag' | 'crate' | 'coffin' | nil
exports('IsCarrying', function() return Carrying.kind end)
