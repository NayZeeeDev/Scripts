-- ═══════════════════════════════════════════════════════════════
--  VEHICLE TRUNKS - load a carried body into a car, take it out later
-- ═══════════════════════════════════════════════════════════════

local function hasTrunk(veh)
    return not Config.Trunk.BlockedClasses[GetVehicleClass(veh)]
end

-- police can always open a trunk (warrant), everyone else needs it unlocked
local function isLocked(veh)
    return Config.Trunk.MustBeUnlocked and not IsPoliceJob() and GetVehicleDoorLockStatus(veh) >= 2
end

function TrunkCount(veh)
    return Entity(veh).state.nzTrunk or 0
end

-- can the thing I'm carrying go in this vehicle? -> ok, reason
function CanLoadTrunk(veh)
    if not Config.Trunk.Enabled then return false, 'Trunks are disabled' end
    if not Carrying.entity then return false, 'Pick up a body first' end
    if not hasTrunk(veh) then return false, 'This vehicle has no trunk' end
    local rules = TrunkRules(GetEntityModel(veh))
    if not rules.AllowedKinds[Carrying.kind] then
        return false, ('A %s doesn\'t fit in this vehicle'):format(KindLabel(Carrying.kind):lower())
    end
    if TrunkCount(veh) >= rules.MaxBodies then return false, ('Full (%d/%d)'):format(TrunkCount(veh), rules.MaxBodies) end
    if isLocked(veh) then return false, 'The trunk is locked' end
    return true
end

-- closest vehicle whose trunk I'm standing at (used by the [H] carry menu)
function TrunkVehicleNearMe()
    local me = GetEntityCoords(cache.ped)
    local veh = lib.getClosestVehicle(me, 5.0, false)
    if not veh then return nil end
    local bone = GetEntityBoneIndexByName(veh, 'boot')
    local spot = bone ~= -1 and GetWorldPositionOfEntityBone(veh, bone) or GetEntityCoords(veh)
    return #(me - spot) <= (bone ~= -1 and 2.5 or 4.0) and veh or nil
end

-- pop the trunk open for the duration of the action
local function withTrunkOpen(veh, label, fn)
    SetVehicleDoorOpen(veh, 5, false, false)
    local ok = Progress(label, Config.Trunk.Time)
    if ok then fn() end
    Wait(500)
    SetVehicleDoorShut(veh, 5, false)
end

function PutInTrunk(veh)
    if IsBusy() then return end
    local ok, reason = CanLoadTrunk(veh)
    if not ok then return Config.Notify(reason, 'error') end
    local bagNetId = Carrying.netId
    withTrunkOpen(veh, 'Loading the body into the trunk...', function()
        if lib.callback.await('nayzeee-bodybag:trunkPut', false, NetOf(veh), bagNetId) then
            StopCarrying(false, true)
            Tip('Drive somewhere quiet. Bodies left in a trunk start to smell after a while.')
        end
    end)
end

function TakeFromTrunk(veh)
    if IsBusy() or Carrying.entity then return end
    if isLocked(veh) then return Config.Notify('The trunk is locked', 'error') end
    withTrunkOpen(veh, 'Pulling the body out...', function()
        TriggerServerEvent('nayzeee-bodybag:server:trunkTake', NetOf(veh))
    end)
end

function SearchTrunk(veh)
    if IsBusy() then return end
    withTrunkOpen(veh, 'Searching the trunk...', function()
        local list = lib.callback.await('nayzeee-bodybag:trunkSearch', false, NetOf(veh))
        if not list or #list == 0 then return Config.Notify('Nothing suspicious in the trunk.', 'inform') end
        local rows = {}
        for i, b in ipairs(list) do
            local desc = 'Condition: ' .. (b.stage or 'fresh')
            if b.dna and #b.dna > 0 then desc = desc .. '  •  DNA: ' .. table.concat(b.dna, ', ') end
            rows[#rows + 1] = { title = ('Body #%d - %s'):format(i, b.name or 'John Doe'), description = desc, icon = 'skull' }
        end
        lib.registerContext({ id = 'nz_trunk_search', title = 'Trunk Contents', options = rows })
        lib.showContext('nz_trunk_search')
    end)
end

function OpenTrunkMenu(veh)
    local rules = TrunkRules(GetEntityModel(veh))
    local count = TrunkCount(veh)
    local canLoad, loadWhy = CanLoadTrunk(veh)
    local police = IsPoliceJob()

    ShowActions('nz_trunk', ('Trunk  •  %d/%d bodies'):format(count, rules.MaxBodies), {
        { title = 'Put Body In Trunk', icon = 'car-rear',
          description = 'Load what you are carrying. The victim rides along with the car.',
          available = canLoad, reason = loadWhy, onSelect = function() PutInTrunk(veh) end },
        { title = 'Take Body Out', icon = 'person-falling',
          description = 'Drops the last body loaded on the ground behind the car.',
          available = count > 0 and not Carrying.entity and not isLocked(veh),
          reason = Carrying.entity and 'Your hands are full' or (count == 0 and 'The trunk is empty' or 'The trunk is locked'),
          onSelect = function() TakeFromTrunk(veh) end },
        { title = 'Search For Bodies', icon = 'magnifying-glass', hidden = not (police and Config.Trunk.PoliceCanSearch),
          description = 'Police: check the trunk and see any DNA on the bodies.',
          onSelect = function() SearchTrunk(veh) end },
    })
end

CreateThread(function()
    if not Config.Trunk.Enabled then return end
    exports.ox_target:addGlobalVehicle({ {
        name = 'nz_trunk', icon = 'fas fa-car-rear', label = 'Trunk', distance = 2.5, bones = Config.Trunk.Bones,
        canInteract = function(veh)
            if not hasTrunk(veh) then return false end
            return Carrying.entity ~= nil or TrunkCount(veh) > 0 or (IsPoliceJob() and Config.Trunk.PoliceCanSearch)
        end,
        onSelect = function(d) OpenTrunkMenu(d.entity) end,
    } })
end)
