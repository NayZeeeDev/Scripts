-----------------------------------------------------------------
-- Worn bags
--
-- The server owns the truth (Player(src).state.nayzeee_backpack).
-- Every client renders every player's bag from that statebag, so
-- nobody needs extra events to see each other's bags.
-----------------------------------------------------------------

local props = {}    -- [serverId] = { entity, sig }
local apply
local wanted = {}   -- [serverId] = state, what each player should be wearing
local myId = GetPlayerServerId(PlayerId())
local lastSig = nil -- what we last told the server about our inventory
local attaching = {} -- [serverId] = true while a model is loading
local localHidden = false -- shop / studio hide the worn bag
local openState = {} -- [serverId] = nb_open statebag: the bag is set down and open
local handHidden = {} -- [serverId] = true while the bag is in someone's hand (client/handoff.lua)
local quietUntil = 0  -- no equip/unequip animation before this (a hand-off animates itself)

--- Should this player's worn bag be drawn?
local function shown(serverId, state)
    return state and state.bag and (not state.stowed or openState[serverId]) and not handHidden[serverId]
end

local function pedFor(serverId)
    if serverId == myId then return PlayerPedId() end
    local ply = GetPlayerFromServerId(serverId)
    if ply == -1 then return 0 end
    return GetPlayerPed(ply)
end

local function sigOf(state, serverId)
    local o = serverId and openState[serverId]
    return ('%s|%s|%s'):format(state.bag, tostring(state.variant),
        o and (o.cash and 'cash' or 'open') or 'worn')
end

--- Set an opened bag down on the ground in front of its owner.
--- Uses the bag's open / cash model when it has one.
local function spawnOpen(serverId, state, ped)
    local info = Bags.openInfo(state.bag)
    local o = openState[serverId] or {}
    local model = (o.cash and info.cashModel) or info.model

    local entity, hash
    if model then
        entity, hash = Util.spawnModel(model, 0, GetEntityCoords(ped))
    end
    if not entity then
        entity, hash = Util.spawnBag(state.bag, state.variant, GetEntityCoords(ped))
    end
    if not entity then return nil end

    local pc = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    local r = math.rad(h)
    local dist = (Config.OpenBag and Config.OpenBag.distance) or 0.55
    local x, y = pc.x - math.sin(r) * dist, pc.y + math.cos(r) * dist
    local ok, gz = GetGroundZFor_3dCoord(x, y, pc.z + 0.3, false)
    local z = ok and gz or (pc.z - 0.98)

    -- mesh bottom-centre on the ground (these props rarely have a sane pivot)
    local c, mn = Util.modelCentre(hash)
    local heading = (h + (info.heading or 180.0)) % 360.0
    local hr = math.rad(heading)
    local co, si = math.cos(hr), math.sin(hr)
    SetEntityCoordsNoOffset(entity, x - (c.x * co - c.y * si), y - (c.x * si + c.y * co), z - mn.z, false, false, false)
    SetEntityHeading(entity, heading)
    FreezeEntityPosition(entity, true)
    return entity
end

-----------------------------------------------------------------
-- prop handling
-----------------------------------------------------------------

local function removeProp(serverId)
    local p = props[serverId]
    if not p then return end
    Util.delete(p.entity)
    props[serverId] = nil
end

local function attachProp(serverId, state)
    local ped = pedFor(serverId)
    if ped == 0 or not DoesEntityExist(ped) then return false end

    local current = props[serverId]
    local sig = sigOf(state, serverId)
    if current and current.sig == sig and DoesEntityExist(current.entity)
       and (current.grounded or IsEntityAttachedToEntity(current.entity, current.holder or ped)) then
        return true
    end

    if attaching[serverId] then return false end
    attaching[serverId] = true
    removeProp(serverId)

    local grounded = openState[serverId] ~= nil
    local entity
    if grounded then
        entity = spawnOpen(serverId, state, ped)
    else
        entity = Util.spawnBag(state.bag, state.variant, GetEntityCoords(ped))
    end
    attaching[serverId] = nil
    if not entity then return false end

    -- the state may have changed while the model loaded
    local now = wanted[serverId]
    local visible = shown(serverId, now)
    if not visible or sigOf(now, serverId) ~= sig or not DoesEntityExist(ped) then
        Util.delete(entity)
        if visible then CreateThread(function() apply(serverId) end) end
        return false
    end

    if not grounded then
        local bone, pos, rot = Bags.offset(state.bag)
        Util.attach(entity, ped, bone, pos, rot)
    end

    -- in a vehicle: hidden until the scope loop finds it a seat (a moment later)
    if (serverId == myId and localHidden) or IsPedInAnyVehicle(ped, false) then
        SetEntityVisible(entity, false, false)
    end

    props[serverId] = { entity = entity, sig = sig, ped = ped, grounded = grounded, holder = ped, place = 'worn' }

    -- learn how this bag sits on a wearer, for putting it on car seats later
    if not grounded and VehicleBags and VehicleBags.enabled and not IsPedInAnyVehicle(ped, false) then
        local key = state.bag .. '|' .. tostring(state.variant)
        if not VehicleBags.hasMeasure(key) then
            CreateThread(function()
                Wait(0); Wait(0)
                if not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped) then
                    VehicleBags.measure(key, entity, ped)
                end
            end)
        end
    end
    Bags.debug('attached', state.bag, 'to', serverId)
    return true
end

apply = function(serverId)
    local state = wanted[serverId]
    if shown(serverId, state) and Bags.exists(state.bag) then
        attachProp(serverId, state)
    else
        removeProp(serverId)
    end
end

--- Re-attach everything, e.g. after an admin saved a new offset.
function RefreshAllBags()
    for id in pairs(props) do removeProp(id) end
    -- each apply may wait on a model, so never block whoever called us
    for id in pairs(wanted) do CreateThread(function() apply(id) end) end
end

AddEventHandler('nayzeee-backpack:overridesChanged', RefreshAllBags)

--- Hide/show the bag the local player wears (shop preview, studio).
function SetWornPropVisible(visible)
    localHidden = not visible
    local p = props[myId]
    if p and DoesEntityExist(p.entity) then
        SetEntityVisible(p.entity, visible, false)
    end
end

--- The hand-off draws the bag in a hand; the worn one steps aside.
function SetHandoffHidden(serverId, hidden)
    handHidden[serverId] = hidden or nil
    CreateThread(function() apply(serverId) end)
end

--- Skip the equip / unequip animation for the next inventory change.
function QuietBagAnims(ms)
    quietUntil = GetGameTimer() + (ms or 3000)
end

--- Worn bags that carry a name tag and are on screen-able right now.
function BagTagTargets()
    local list = {}
    for serverId, p in pairs(props) do
        local st = wanted[serverId]
        if st and st.tag and p.entity and DoesEntityExist(p.entity) and IsEntityVisible(p.entity) then
            list[#list + 1] = { id = serverId, entity = p.entity, tag = st.tag, locked = st.locked }
        end
    end
    return list
end

function GetWornProp()
    local p = props[myId]
    return p and p.entity
end

-----------------------------------------------------------------
-- state sync
-----------------------------------------------------------------

AddStateBagChangeHandler('nayzeee_backpack', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == 0 then return end
    local serverId = GetPlayerServerId(ply)

    local before = wanted[serverId]
    wanted[serverId] = value

    -- applying waits on the ped, which the scope loop below handles too
    CreateThread(function() apply(serverId) end)

    if serverId == myId then
        if value and value.bag then
            TriggerEvent('nayzeee-backpack:client:equipped', value.bag, value.variant, value.stowed)
        elseif before and before.bag then
            TriggerEvent('nayzeee-backpack:client:removed')
        end
    end
end)

-----------------------------------------------------------------
-- inventory watch
--
-- The client only says "something changed". The server reads the
-- real inventory and sets the statebag from item metadata, which is
-- how a stowed bag stays stowed through relogs and restarts.
-----------------------------------------------------------------

local function inventorySig()
    local items = exports.ox_inventory:GetPlayerItems()
    if not items then return nil, nil end

    for _, item in pairs(items) do
        if item and Bags.exists(item.name) then
            local m = item.metadata or {}
            return ('%s|%s|%s|%s|%s'):format(item.name, item.slot, tostring(m.variant), tostring(m.stowed), tostring(m.pose)),
                   item.name, m
        end
    end
    return 'none', nil, nil
end

local function syncBackpack(skipAnim)
    local sig, bagKey, meta = inventorySig()
    if not sig or sig == lastSig then return end

    local hadBag = lastSig ~= nil and lastSig ~= 'none'
    lastSig = sig

    if not skipAnim and GetGameTimer() > quietUntil and Config.Animations and Config.Animations.enabled then
        local stowed = meta and meta.stowed
        if bagKey and not hadBag and not stowed then
            Anim.playAsync('equip')
        elseif not bagKey and hadBag then
            Anim.playAsync('unequip')
        end
    end

    TriggerServerEvent('nayzeee-backpack:sync')
    Bags.debug('sync ->', sig)
end

--- Force a fresh sync (spawn, resource restart, character switch).
function ResyncBackpack()
    lastSig = nil
    syncBackpack(true)
end

AddEventHandler('ox_inventory:updateInventory', function() syncBackpack() end)
RegisterNetEvent('ox_inventory:closedInventory', function() syncBackpack() end)

-----------------------------------------------------------------
-- lifecycle
-----------------------------------------------------------------

AddEventHandler('playerSpawned', function()
    SetTimeout(1500, ResyncBackpack)
end)

Framework.onPlayerLoaded(function()
    SetTimeout(2000, ResyncBackpack)
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- pick up everyone already wearing a bag
    for _, ply in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(ply)
        local st = Player(sid).state.nayzeee_backpack
        if st then wanted[sid] = st end
        openState[sid] = Player(sid).state.nb_open or nil
    end
    SetTimeout(1000, function()
        for id in pairs(wanted) do CreateThread(function() apply(id) end) end
        ResyncBackpack()
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(props) do removeProp(id) end
end)

RegisterNetEvent('nayzeee-backpack:clear', function(serverId)
    wanted[serverId] = nil
    openState[serverId] = nil
    handHidden[serverId] = nil
    removeProp(serverId)
end)

-- a player set their bag down to open it (or picked it back up)
AddStateBagChangeHandler('nb_open', nil, function(bagName, _, value)
    local ply = GetPlayerFromStateBagName(bagName)
    if ply == 0 then return end
    local serverId = GetPlayerServerId(ply)
    openState[serverId] = value or nil
    CreateThread(function() apply(serverId) end)
end)

-----------------------------------------------------------------
-- where a bag goes: back, car seat, hidden
-----------------------------------------------------------------

local placing = {} -- [serverId] = true while a bag is being moved (seat <-> back)

--- Put a bag where it should be: on its wearer, on a car seat, or hidden.
local function setPlacement(serverId, place)
    placing[serverId] = true
    local p, state, ped = props[serverId], wanted[serverId], pedFor(serverId)
    if not p or not state or ped == 0 or not DoesEntityExist(p.entity) then placing[serverId] = nil return end

    local function wear(visible)
        ResetEntityAlpha(p.entity)
        if p.holder ~= ped or not IsEntityAttachedToEntity(p.entity, ped) then
            local bone, pos, rot = Bags.offset(state.bag)
            Util.attach(p.entity, ped, bone, pos, rot)
            p.holder = ped
        end
        SetEntityVisible(p.entity, visible and not (serverId == myId and localHidden), false)
    end

    if place == 'worn' then
        wear(true)
    elseif place == 'hidden' then
        wear(false)
    else
        local veh, seat = place:match('^seat:(%-?%d+):(%-?%d+)$')
        veh, seat = tonumber(veh), tonumber(seat)
        local key = state.bag .. '|' .. tostring(state.variant)
        if not VehicleBags.hasMeasure(key) then
            -- never seen on foot: measure it on the seated wearer (stood upright)
            wear(false)
            Wait(0); Wait(0)
            VehicleBags.measure(key, p.entity, ped)
        end
        if veh and DoesEntityExist(veh) and VehicleBags.place(p.entity, GetEntityModel(p.entity), key, veh, seat) then
            p.holder = veh
        else
            wear(false)
            place = 'hidden'
        end
    end

    p.place = place
    placing[serverId] = nil
end

-----------------------------------------------------------------
-- scope + vehicle loop
--
-- Peds stream in and out, change model, get in cars. One cheap loop
-- keeps every bag on the right ped (or car seat). Idles at 2s with no
-- bags around, 250ms while a bag sits in a car so a passenger climbing
-- in never ends up sitting on it.
-----------------------------------------------------------------

CreateThread(function()
    while true do
        local any, inCar = false, false
        local desired = {}  -- [serverId] = placement
        local cars = {}     -- [veh] = { { id, ped }, ... }

        for serverId, state in pairs(wanted) do
            if shown(serverId, state) then
                any = true
                local ped = pedFor(serverId)
                local p = props[serverId]

                if ped == 0 or not DoesEntityExist(ped) then
                    if p then removeProp(serverId) end
                elseif not p or not DoesEntityExist(p.entity)
                    or (not p.grounded and not placing[serverId]
                        and not IsEntityAttachedToEntity(p.entity, p.holder or ped)) then
                    -- own thread: a model load may wait, and we're mid-iteration
                    if not attaching[serverId] then
                        local id = serverId
                        CreateThread(function() apply(id) end)
                    end
                elseif not p.grounded then
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh ~= 0 then
                        cars[veh] = cars[veh] or {}
                        cars[veh][#cars[veh] + 1] = { id = serverId, ped = ped }
                    else
                        desired[serverId] = 'worn'
                    end
                end
            end
        end

        for veh, holders in pairs(cars) do
            inCar = true
            local mode = VehicleBags and VehicleBags.modeFor(veh) or (Config.ShowInVehicle and 'worn' or 'hidden')
            if mode == 'seat' then
                local seats = VehicleBags.assign(veh, holders)
                local fallback = (Config.Vehicle and Config.Vehicle.fallback == 'worn') and 'worn' or 'hidden'
                for _, h in ipairs(holders) do
                    desired[h.id] = seats[h.id] and ('seat:%d:%d'):format(veh, seats[h.id]) or fallback
                end
            else
                for _, h in ipairs(holders) do desired[h.id] = mode end
            end
        end

        for id, place in pairs(desired) do
            local p = props[id]
            if p and p.place ~= place and not placing[id] and not attaching[id] then
                CreateThread(function() setPlacement(id, place) end)
            end
        end

        Wait(inCar and 250 or (any and 750 or 2000))
    end
end)

-----------------------------------------------------------------
-- open / notify
-----------------------------------------------------------------

--- `info` only comes with your OWN worn bag; placed bags and police
--- searches just open the stash.
RegisterNetEvent('nayzeee-backpack:open', function(stashId, info)
    if info and Open and Open.start(stashId, info) then return end
    if Config.Animations and Config.Animations.enabled then
        Anim.play('open')
    end
    exports.ox_inventory:openInventory('stash', stashId)
end)

RegisterNetEvent('nayzeee-backpack:notify', function(msg, type)
    Config.Notify(msg, type)
end)

--- Can this player use a bag with a `job` restriction?
function CanUseBag(bagKey)
    local job = Framework.getJob()
    if not Bags.jobAllows(bagKey, job) then return false end
    if Bags.isJobBag(bagKey) and Config.Jobs and Config.Jobs.requireDuty and job and not job.onDuty then
        return false
    end
    return true
end

exports('GetWornBag', function()
    local st = LocalPlayer.state.nayzeee_backpack
    return st and st.bag, st
end)
