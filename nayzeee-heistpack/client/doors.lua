--[[
    Heist doors, synced for every player through GlobalState['nzh:doors'].
    Each door gets an ox_lib point; state is applied only when the player streams in,
    so far-away doors cost nothing. Vault doors swing open with an animation.
]]

local points = {}   -- key -> point
local applied = {}  -- key -> { entity, closedHeading, open }

local function findDoor(d)
    for i = 1, #d.models do
        local m = d.models[i]
        local obj = GetClosestObjectOfType(d.coords.x, d.coords.y, d.coords.z, d.radius, type(m) == 'string' and joaat(m) or m, false, false, false)
        if obj ~= 0 then return obj end
    end
    return 0
end

local function animateVault(obj, from, to)
    CreateThread(function()
        local steps = 120
        for i = 1, steps do
            if not DoesEntityExist(obj) then return end
            SetEntityHeading(obj, from + (to - from) * (i / steps))
            Wait(30)
        end
    end)
end

local function apply(key, d, animate)
    local obj = findDoor(d)
    if obj == 0 then return false end
    local a = applied[key]
    if not a or a.entity ~= obj then
        a = { entity = obj, closedHeading = GetEntityHeading(obj), open = false, kind = d.kind }
        applied[key] = a
    end
    if d.kind == 'vault' then
        FreezeEntityPosition(obj, true)
        local target = d.open and (a.closedHeading + d.delta) or a.closedHeading
        if a.open ~= d.open then
            if animate then animateVault(obj, GetEntityHeading(obj), target) else SetEntityHeading(obj, target) end
        end
    else
        -- gates / swing doors: frozen = locked, unfrozen = free to push open
        if not d.open then SetEntityHeading(obj, a.closedHeading) end
        FreezeEntityPosition(obj, not d.open)
    end
    a.open = d.open
    return true
end

local function release(key)
    local a = applied[key]
    if a and DoesEntityExist(a.entity) then
        SetEntityHeading(a.entity, a.closedHeading)
        FreezeEntityPosition(a.entity, true)
        -- vanilla gates go back to their default unlocked behaviour; vaults stay shut
        if a.kind ~= 'vault' then FreezeEntityPosition(a.entity, false) end
    end
    applied[key] = nil
end

local function sync(doors)
    doors = doors or {}
    -- removed doors
    for key, point in pairs(points) do
        if not doors[key] then
            point:remove()
            points[key] = nil
            release(key)
        end
    end
    -- new / changed doors
    for key, d in pairs(doors) do
        local point = points[key]
        if not point then
            point = lib.points.new({
                coords = d.coords, distance = 60.0, door = d, key = key,
                onEnter = function(self)
                    -- object may stream a moment after the point triggers
                    for _ = 1, 10 do
                        if apply(self.key, self.door, false) then return end
                        Wait(300)
                    end
                end,
            })
            points[key] = point
        else
            local changed = point.door.open ~= d.open
            point.door = d
            if changed and point.currentDistance and point.currentDistance < 60.0 then apply(key, d, true) end
        end
    end
end

AddStateBagChangeHandler('nzh:doors', 'global', function(_, _, value)
    sync(value)
end)

CreateThread(function()
    sync(GlobalState['nzh:doors'])
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for key in pairs(applied) do release(key) end
end)
