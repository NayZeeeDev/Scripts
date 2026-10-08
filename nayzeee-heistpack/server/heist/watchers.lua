--[[
    Server-side objective watchers: eliminate / escape / deliver nodes, time limits,
    abandoned and wiped crews. One thread, alive only while at least one heist runs.
]]

Watchers = {}

local running = false

local function pedDead(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or not DoesEntityExist(ent) then return true end
    return GetEntityHealth(ent) <= 0
end

local function entityCoords(inst, key)
    local netId = inst.entities[key]
    local ent = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if ent == 0 or not DoesEntityExist(ent) then return nil end
    return GetEntityCoords(ent)
end

local function checkNode(inst, node)
    if node.type == 'eliminate' then
        local group = inst.guards[node.group or 'guards']
        if not group or #group == 0 then return false end
        for i = 1, #group do
            if not pedDead(group[i]) then return false end
        end
        return true
    elseif node.type == 'escape' then
        local center = Utils.vec3(node.coords)
        local any = false
        for i = 1, #inst.members do
            local src = inst.members[i]
            local c = Guard.coords(src)
            if c then
                any = true
                if #(c - center) < node.radius or GetPlayerRoutingBucket(src) == inst.bucket then return false end
            end
        end
        return any
    elseif node.type == 'deliver' then
        local keys = node.entities or { node.entity }
        local drop = Utils.vec3(node.dropoff)
        for i = 1, #keys do
            local c = entityCoords(inst, keys[i])
            if not c or #(c - drop) > (node.radius or 8.0) then return false end
        end
        return true
    end
    return false
end

local function tick(inst)
    local now = os.time()
    if inst.deadline and now >= inst.deadline then return Engine.fail(inst, 'time') end
    if inst.emptySince and now - inst.emptySince > Config.Gameplay.reconnectWindow then
        return Engine.fail(inst, 'abandoned')
    end

    if Config.Gameplay.failOnAllDead and #inst.members > 0 then
        local alive = false
        for i = 1, #inst.members do
            local ped = GetPlayerPed(inst.members[i])
            if ped ~= 0 and GetEntityHealth(ped) > 0 then alive = true break end
        end
        if alive then inst.wipedChecks = 0 else
            inst.wipedChecks = (inst.wipedChecks or 0) + 1
            if inst.wipedChecks >= 3 then return Engine.fail(inst, 'wasted') end
        end
    end

    for id, node in pairs(inst.nodes) do
        if inst.finished then return end
        local st = inst.nodeState[id]
        -- vehicle trackers ping the police until their flag is set
        if node.type == 'tracker' and st and not st.done then
            if inst.flags[node.flag] then
                st.done = true
            elseif now - (st.lastPing or 0) >= (node.interval or 30) then
                local c = entityCoords(inst, node.entity)
                if c then
                    st.lastPing = now
                    inst.alerted = nil
                    Engine.alert(inst, inst.leader, c)
                end
            end
        end
        if st and not st.done and (node.type == 'eliminate' or node.type == 'escape' or node.type == 'deliver') then
            if checkNode(inst, node) then
                Engine.complete(inst, node, nil)
                if node.type == 'deliver' and node.cleanup ~= false then
                    local keys = node.entities or { node.entity }
                    SetTimeout(8000, function()
                        for i = 1, #keys do
                            local netId = inst.entities[keys[i]]
                            local ent = netId and NetworkGetEntityFromNetworkId(netId) or 0
                            if ent ~= 0 and DoesEntityExist(ent) then
                                local occupied = false
                                if GetEntityType(ent) == 2 then
                                    for seat = -1, 6 do
                                        if GetPedInVehicleSeat(ent, seat) ~= 0 then occupied = true break end
                                    end
                                end
                                if not occupied then DeleteEntity(ent) end
                            end
                        end
                    end)
                end
            end
        end
    end
end

function Watchers.ensure()
    if running then return end
    running = true
    CreateThread(function()
        while true do
            local any = false
            for _, inst in pairs(Engine.instances) do
                if not inst.finished then
                    any = true
                    local ok, err = pcall(tick, inst)
                    if not ok then print('^1[nzh] watcher error: ' .. tostring(err) .. '^7') end
                end
            end
            if not any then break end
            Wait(1500)
        end
        running = false
    end)
end
