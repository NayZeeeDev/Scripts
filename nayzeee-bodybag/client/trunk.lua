-- ═══════════════════════════════════════════════════════════════
--  VEHICLE TRUNKS - third-eye the back of a car while carrying a bag
-- ═══════════════════════════════════════════════════════════════
if not Config.Trunk.Enabled then return end

local function hasTrunk(veh)
    return not Config.Trunk.BlockedClasses[GetVehicleClass(veh)]
end

-- police can always open a trunk (warrant), everyone else needs it unlocked
local function isLocked(veh)
    return Config.Trunk.MustBeUnlocked and not IsPoliceJob() and GetVehicleDoorLockStatus(veh) >= 2
end

local function trunkCount(veh)
    return Entity(veh).state.nzTrunk or 0
end

-- pop the trunk open for the duration of the action
local function withTrunkOpen(veh, label, fn)
    SetVehicleDoorOpen(veh, 5, false, false)
    local ok = Progress(label, Config.Trunk.Time)
    if ok then fn() end
    Wait(500)
    SetVehicleDoorShut(veh, 5, false)
end

local function putInTrunk(veh)
    if IsBusy() or not Carrying.entity then return end
    if isLocked(veh) then return Config.Notify('The trunk is locked', 'error') end
    if trunkCount(veh) >= Config.Trunk.MaxBodies then return Config.Notify('The trunk is full', 'error') end
    local bagNetId = Carrying.netId
    withTrunkOpen(veh, 'Stuffing the body in the trunk...', function()
        if lib.callback.await('nayzeee-bodybag:trunkPut', false, NetOf(veh), bagNetId) then
            StopCarrying(false, true)
            Config.Notify('The body is in the trunk.', 'success')
        else
            Config.Notify('Couldn\'t load it - get closer', 'error')
        end
    end)
end

local function takeFromTrunk(veh)
    if IsBusy() or Carrying.entity then return end
    if isLocked(veh) then return Config.Notify('The trunk is locked', 'error') end
    withTrunkOpen(veh, 'Pulling the body out...', function()
        TriggerServerEvent('nayzeee-bodybag:server:trunkTake', NetOf(veh))
    end)
end

local function searchTrunk(veh)
    if IsBusy() then return end
    withTrunkOpen(veh, 'Searching the trunk...', function()
        local list = lib.callback.await('nayzeee-bodybag:trunkSearch', false, NetOf(veh))
        if not list or #list == 0 then return Config.Notify('Nothing suspicious in the trunk.', 'inform') end
        local rows = {}
        for i, b in ipairs(list) do
            local desc = 'Condition: ' .. (b.stage or 'fresh')
            if b.dna and #b.dna > 0 then desc = desc .. ' • DNA: ' .. table.concat(b.dna, ', ') end
            rows[#rows + 1] = { title = ('Body #%d - %s'):format(i, b.name or 'John Doe'), description = desc, icon = 'skull' }
        end
        lib.registerContext({ id = 'nz_trunk_search', title = 'Trunk Contents', options = rows })
        lib.showContext('nz_trunk_search')
    end)
end

CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        { name = 'nz_trunk_put', icon = 'fas fa-car-rear', label = 'Put Body In Trunk', distance = 2.5,
          bones = Config.Trunk.Bones,
          canInteract = function(veh)
              return Carrying.entity ~= nil and Config.Trunk.AllowedKinds[Carrying.kind] and hasTrunk(veh)
          end,
          onSelect = function(d) putInTrunk(d.entity) end },
        { name = 'nz_trunk_take', icon = 'fas fa-person-falling', label = 'Take Body Out Of Trunk', distance = 2.5,
          bones = Config.Trunk.Bones,
          canInteract = function(veh) return not Carrying.entity and trunkCount(veh) > 0 end,
          onSelect = function(d) takeFromTrunk(d.entity) end },
        { name = 'nz_trunk_search', icon = 'fas fa-magnifying-glass', label = 'Search Trunk For Bodies', distance = 2.5,
          bones = Config.Trunk.Bones,
          canInteract = function(veh) return Config.Trunk.PoliceCanSearch and IsPoliceJob() and hasTrunk(veh) end,
          onSelect = function(d) searchTrunk(d.entity) end },
    })
end)
