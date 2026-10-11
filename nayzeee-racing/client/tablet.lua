if not NAYZEEE_LOCK_OK then return end

--[[
    Tablet prop + animation while the tablet is open. Other players see it through a state bag,
    each client spawns a local prop (no networked entities).
]]

Tablet = {}

local DICT, ANIM, BONE = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base', 28422
local OFFSET, ROT = vec3(0.05, -0.005, -0.04), vec3(0.0, 0.0, 0.0)
local mine, others = nil, {}

local function attach(ped)
    if not lib.requestModel(Config.General.Tablet, 3000) then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(Config.General.Tablet, c.x, c.y, c.z - 5.0, false, false, false)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, BONE), OFFSET.x, OFFSET.y, OFFSET.z, ROT.x, ROT.y, ROT.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(Config.General.Tablet)
    return obj
end

local function remove(obj) if obj and DoesEntityExist(obj) then DeleteEntity(obj) end end

function Tablet.Start()
    if not Config.General.TabletProp or mine then return end
    CreateThread(function()
        local ped = cache.ped
        if not lib.requestAnimDict(DICT, 3000) then return end
        mine = attach(ped)
        LocalPlayer.state:set('nzrTablet', true, true)
        while App.open and mine do
            if not IsEntityPlayingAnim(ped, DICT, ANIM, 3) and not IsPedRagdoll(ped) then
                TaskPlayAnim(ped, DICT, ANIM, 8.0, -4.0, -1, 49, 0, false, false, false)
            end
            Wait(500)
        end
        Tablet.Stop()
    end)
end

function Tablet.Stop()
    if not mine then return end
    remove(mine)
    mine = nil
    StopAnimTask(cache.ped, DICT, ANIM, 2.0)
    RemoveAnimDict(DICT)
    LocalPlayer.state:set('nzrTablet', false, true)
end

-- Clean up props of players who left scope. Only runs while someone else holds a tablet.
local sweeping = false
local function sweep()
    if sweeping then return end
    sweeping = true
    CreateThread(function()
        while next(others) do
            Wait(5000)
            for sid, obj in pairs(others) do
                if GetPlayerFromServerId(sid) == -1 or not DoesEntityExist(obj) or not IsEntityAttached(obj) then
                    remove(obj)
                    others[sid] = nil
                end
            end
        end
        sweeping = false
    end)
end

AddStateBagChangeHandler('nzrTablet', nil, function(bag, _, value)
    local sid = tonumber(bag:match('player:(%d+)'))
    if not sid or sid == cache.serverId then return end
    -- model loading waits, so it runs in its own thread (state bag handlers can't yield)
    CreateThread(function()
        remove(others[sid])
        others[sid] = nil
        if not value or not Config.General.TabletProp then return end
        local player = GetPlayerFromServerId(sid)
        if player == -1 then return end
        local ped = GetPlayerPed(player)
        if ped == 0 then return end
        others[sid] = attach(ped)
        if others[sid] then sweep() end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    remove(mine)
    for _, obj in pairs(others) do remove(obj) end
end)
