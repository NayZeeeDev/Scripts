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

function IsPoliceJob()
    local data = ESX.GetPlayerData()
    return data and data.job and Config.Evidence.PoliceJobs[data.job.name] == true or false
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

local function bagStateOf(entity)
    return Entity(entity).state.nzBody
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
--  BAGGING A BODY
-- ═══════════════════════════════════════════════════════════════
local function bagBody(ped)
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

-- empty crate/coffin within Config.DirectLoad.Radius of a body
local function nearbyEmpty(coords)
    if not Config.DirectLoad.Enabled then return nil end
    for _, o in ipairs(lib.getNearbyObjects(coords, Config.DirectLoad.Radius)) do
        if Entity(o.object).state.nzEmpty then return o.object end
    end
    return nil
end

local function directLoad(ped)
    if IsBusy() then return end
    local target = nearbyEmpty(GetEntityCoords(ped))
    local ref = BodyRef(ped)
    if not target or not ref then return end
    PlayAnim('anim@gangops@facility@servers@bodysearch@', 'player_search', 1)
    local ok = Progress('Loading the body in...', Config.LoadTime)
    ClearPedTasks(cache.ped)
    if ok then TriggerServerEvent('nayzeee-bodybag:server:directLoad', ref, NetOf(target)) end
end

-- ═══════════════════════════════════════════════════════════════
--  INSPECT A BODY (bag / crate / coffin / barrel)
-- ═══════════════════════════════════════════════════════════════
local kindTitles = { bodybag = 'Body Bag', crate = 'Military Crate', coffin = 'Coffin', barrel = 'Burn Barrel' }

function InspectBody(entity)
    local info = lib.callback.await('nayzeee-bodybag:inspect', false, NetOf(entity))
    if not info then return Config.Notify('It\'s empty', 'inform') end

    local state = bagStateOf(entity)
    local rows = {
        { title = info.name or 'John Doe', icon = 'skull',
          description = info.name and 'Identity confirmed' or (info.npc and 'A local - nobody you know' or 'Unidentifiable remains') },
        { title = 'Condition: ' .. (info.stage or 'fresh'), icon = 'biohazard' },
    }
    if info.dna then
        rows[#rows + 1] = {
            title = #info.dna > 0 and ('DNA traces: ' .. table.concat(info.dna, ', ')) or 'No usable DNA traces',
            icon = 'dna', description = 'Forensics',
        }
    end
    lib.registerContext({ id = 'nz_inspect', title = kindTitles[state and state.kind] or 'Body', options = rows })
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
--  LOAD / REMOVE
-- ═══════════════════════════════════════════════════════════════
function RemoveBodyFrom(containerEnt)
    if IsBusy() then return end
    if not Progress('Removing the body...', Config.RemoveBody.Time or 5000) then return end
    TriggerServerEvent('nayzeee-bodybag:server:removeBody', NetOf(containerEnt))
end

-- carried bag -> placed empty crate/coffin
function LoadIntoPlaced(targetEnt, kind)
    if IsBusy() then return end
    if Carrying.kind ~= 'bodybag' then return Config.Notify('You need to be carrying a body bag', 'error') end
    local bagNetId = Carrying.netId
    if not Progress(('Loading body into the %s...'):format(kind), Config.LoadTime) then return end
    if lib.callback.await('nayzeee-bodybag:loadContainer', false, NetOf(targetEnt), bagNetId) then
        StopCarrying(false, true)
    else
        Config.Notify('Couldn\'t load it - get closer', 'error')
    end
end

-- ═══════════════════════════════════════════════════════════════
--  TARGET SETUP (ox_target third-eye options)
-- ═══════════════════════════════════════════════════════════════
CreateThread(function()
    -- ── dead bodies (players + NPCs share the same options) ──
    local bodyOptions = {
        {
            name = 'nz_direct_load', icon = 'fas fa-box-open', label = 'Place Body In Nearby Crate/Coffin', distance = 2.0,
            canInteract = function(entity)
                return not Carrying.entity and IsBodyDead(entity) and nearbyEmpty(GetEntityCoords(entity)) ~= nil
            end,
            onSelect = function(data) directLoad(data.entity) end,
        },
        {
            name = 'nz_bag_body', icon = 'fas fa-box-archive', label = 'Place In Body Bag', distance = 2.0,
            canInteract = function(entity)
                return not Carrying.entity and IsBodyDead(entity) and HasItem(Config.Items.bodybag)
            end,
            onSelect = function(data) bagBody(data.entity) end,
        },
    }
    local playerOptions = {
        {
            name = 'nz_chop_body', icon = 'fas fa-scissors', label = 'Dismember Body', distance = 2.0,
            canInteract = function(entity)
                if not Config.Dismember.Enabled or Carrying.entity then return false end
                local sid = ServerIdOfPed(entity)
                if sid and Player(sid).state.nzChopped then return false end -- one chop per body
                return IsPlayerTrulyDead(entity) and (HasItem(Config.Items.powersaw) or HasItem(Config.Items.woodsaw))
            end,
            onSelect = function(data) DismemberBody(data.entity) end,
        },
    }
    for _, o in ipairs(bodyOptions) do playerOptions[#playerOptions + 1] = o end
    exports.ox_target:addGlobalPlayer(playerOptions)

    if Config.AllowNPCBodies then
        local npcOptions = {}
        for _, o in ipairs(bodyOptions) do
            local copy = lib.table.deepclone(o)
            copy.name = o.name .. '_npc'
            local check = o.canInteract
            copy.canInteract = function(entity) return not IsPedAPlayer(entity) and check(entity) end
            copy.onSelect = o.onSelect
            npcOptions[#npcOptions + 1] = copy
        end
        exports.ox_target:addGlobalPed(npcOptions)
    end

    -- ── body bag prop ──
    exports.ox_target:addModel(Config.Props.bodybag, {
        { name = 'nz_pickup_bag', icon = 'fas fa-hand', label = 'Pick Up Bag', distance = 2.0,
          canInteract = function(e) return bagStateOf(e) ~= nil and not Carrying.entity end,
          onSelect = function(d) StartCarrying(d.entity, 'bodybag') end },
        { name = 'nz_inspect_bag', icon = 'fas fa-magnifying-glass', label = 'Inspect', distance = 2.0,
          canInteract = function(e) return bagStateOf(e) ~= nil end,
          onSelect = function(d) InspectBody(d.entity) end },
        { name = 'nz_bury_bag', icon = 'fas fa-trowel', label = 'Bury Body', distance = 2.5,
          canInteract = function(e) return bagStateOf(e) ~= nil and not Carrying.entity and HasItem(Config.Items.shovel) end,
          onSelect = function(d) BuryContainer(d.entity) end },
        { name = 'nz_acid_bag', icon = 'fas fa-flask', label = 'Pour Acid', distance = 2.0,
          canInteract = function(e) return bagStateOf(e) ~= nil and not Carrying.entity and HasItem(Config.Items.acid) end,
          onSelect = function(d) AcidDissolve(d.entity) end },
        { name = 'nz_remove_bag', icon = 'fas fa-person-falling', label = 'Remove Body', distance = 2.0,
          canInteract = function(e) return Config.RemoveBody.Enabled and bagStateOf(e) ~= nil and not Carrying.entity end,
          onSelect = function(d) RemoveBodyFrom(d.entity) end },
    })

    -- ── crate + coffin props (empty = deployed, waiting for a body; full = carries a body) ──
    for _, def in ipairs({ { model = Config.Props.crate, kind = 'crate', label = 'Crate' }, { model = Config.Props.coffin, kind = 'coffin', label = 'Coffin' } }) do
        exports.ox_target:addModel(def.model, {
            { name = 'nz_load_' .. def.kind, icon = 'fas fa-box-archive', label = 'Load Body Into ' .. def.label, distance = 2.0,
              canInteract = function(e) return Entity(e).state.nzEmpty ~= nil and Carrying.kind == 'bodybag' end,
              onSelect = function(d) LoadIntoPlaced(d.entity, def.kind) end },
            { name = 'nz_pickupempty_' .. def.kind, icon = 'fas fa-hand', label = 'Pack Up (Empty)', distance = 2.0,
              canInteract = function(e) return Entity(e).state.nzEmpty ~= nil and not Carrying.entity end,
              onSelect = function(d) TriggerServerEvent('nayzeee-bodybag:server:pickupEmpty', NetOf(d.entity)) end },
            { name = 'nz_pickup_' .. def.kind, icon = 'fas fa-hand', label = 'Pick Up', distance = 2.0,
              canInteract = function(e) return bagStateOf(e) ~= nil and not Carrying.entity end,
              onSelect = function(d) StartCarrying(d.entity, def.kind) end },
            { name = 'nz_inspect_' .. def.kind, icon = 'fas fa-magnifying-glass', label = 'Inspect', distance = 2.0,
              canInteract = function(e) return bagStateOf(e) ~= nil end,
              onSelect = function(d) InspectBody(d.entity) end },
            { name = 'nz_bury_' .. def.kind, icon = 'fas fa-trowel', label = 'Bury', distance = 2.5,
              canInteract = function(e) return bagStateOf(e) ~= nil and not Carrying.entity and HasItem(Config.Items.shovel) end,
              onSelect = function(d) BuryContainer(d.entity) end },
            { name = 'nz_remove_' .. def.kind, icon = 'fas fa-person-falling', label = 'Remove Body', distance = 2.0,
              canInteract = function(e) return Config.RemoveBody.Enabled and bagStateOf(e) ~= nil and not Carrying.entity end,
              onSelect = function(d) RemoveBodyFrom(d.entity) end },
        })
    end

    -- ── burn barrel ──
    exports.ox_target:addModel(Config.Props.barrel, {
        { name = 'nz_barrel_load', icon = 'fas fa-box-archive', label = 'Load Body Into Barrel', distance = 2.0,
          canInteract = function(e) local s = Entity(e).state return s.nzBarrel and not s.nzBody and Carrying.kind == 'bodybag' end,
          onSelect = function(d) LoadBarrel(d.entity) end },
        { name = 'nz_barrel_light', icon = 'fas fa-fire', label = 'Light It Up', distance = 2.0,
          canInteract = function(e)
              local s = Entity(e).state
              return s.nzBarrel and s.nzBody and not s.nzBurning
                  and (not Config.Cremation.RequiresMatches or HasItem(Config.Items.matches))
          end,
          onSelect = function(d) LightBarrel(d.entity) end },
        { name = 'nz_barrel_inspect', icon = 'fas fa-magnifying-glass', label = 'Look Inside', distance = 2.0,
          canInteract = function(e) local s = Entity(e).state return s.nzBarrel and s.nzBody and not s.nzBurning end,
          onSelect = function(d) InspectBody(d.entity) end },
        { name = 'nz_barrel_unload', icon = 'fas fa-person-falling', label = 'Take Body Out', distance = 2.0,
          canInteract = function(e) local s = Entity(e).state return s.nzBarrel and s.nzBody and not s.nzBurning and not Carrying.entity end,
          onSelect = function(d) UnloadBarrel(d.entity) end },
        { name = 'nz_barrel_pickup', icon = 'fas fa-hand', label = 'Pack Up Barrel', distance = 2.0,
          canInteract = function(e) local s = Entity(e).state return s.nzBarrel and not s.nzBody and not s.nzBurning and not Carrying.entity end,
          onSelect = function(d) TriggerServerEvent('nayzeee-bodybag:server:pickupBarrel', NetOf(d.entity)) end },
    })

    -- ── cemetery body hole: third-eye to lower a carried container in, perfectly placed ──
    if Config.Burial.Cemetery.Enabled then
        exports.ox_target:addSphereZone({
            coords = Config.Burial.Cemetery.Coords,
            radius = 2.5,
            name = 'nz_grave_hole',
            options = {
                { name = 'nz_place_in_grave', icon = 'fas fa-arrow-down', label = 'Lower Into Grave',
                  canInteract = function() return Carrying.entity ~= nil end,
                  onSelect = function() PlaceInGraveHole() end },
            },
        })
    end

    -- ── graves (shallow dirt piles AND cemetery tombstones) ──
    exports.ox_target:addModel({ Config.Props.shallowGrave, Config.Props.tombstone }, {
        { name = 'nz_grave_inspect', icon = 'fas fa-magnifying-glass', label = 'Inspect Grave', distance = 2.0,
          canInteract = function(e) return Entity(e).state.nzGrave ~= nil end,
          onSelect = function(d) InspectGrave(d.entity) end },
        { name = 'nz_grave_exhume', icon = 'fas fa-trowel', label = 'Exhume', distance = 2.5,
          canInteract = function(e)
              local g = Entity(e).state.nzGrave
              if not g or not HasItem(Config.Items.shovel) then return false end
              if Config.Burial.PoliceCanExhume and IsPoliceJob() then return true end
              local me = ESX.GetPlayerData()
              return me and me.identifier ~= nil and g.digger == me.identifier
          end,
          onSelect = function(d) ExhumeGrave(d.entity) end },
    })
end)

-- ═══════════════════════════════════════════════════════════════
--  EXPORTS for other resources
-- ═══════════════════════════════════════════════════════════════
-- exports['nayzeee-bodybag']:IsCarrying() -> 'bodybag' | 'crate' | 'coffin' | nil
exports('IsCarrying', function() return Carrying.kind end)
