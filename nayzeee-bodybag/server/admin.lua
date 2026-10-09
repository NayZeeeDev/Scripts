-- ═══════════════════════════════════════════════════════════════
--  ADMIN MENU - /bodyadmin
--  Lists every active body, lets staff teleport to it, free the
--  victim, or clear everything.
-- ═══════════════════════════════════════════════════════════════

RegisterCommand(Config.Admin.Command, function(src)
    if src == 0 then return print('[nayzeee-bodybag] /' .. Config.Admin.Command .. ' is in-game only') end
    if not IsStaff(src) then return Notify(src, 'No permission', 'error') end
    TriggerClientEvent('nayzeee-bodybag:client:openAdmin', src)
end, false)

local function entry(type, key, kind, body, coords)
    return {
        type = type, key = key, kind = kind, coords = coords,
        name = body and (body.name or (body.npc and 'NPC' or 'Unknown')) or '-',
        stage = body and GetStage(body).label or '-',
        online = body and body.victimId ~= nil or false,
    }
end

lib.callback.register('nayzeee-bodybag:admin:list', function(src)
    if not IsStaff(src) then return nil end
    local list = {}
    for netId, c in pairs(Containers) do
        if DoesEntityExist(c.obj) then list[#list + 1] = entry('container', netId, c.kind, c.body, GetEntityCoords(c.obj)) end
    end
    for netId, b in pairs(Barrels) do
        if b.body and DoesEntityExist(b.obj) then list[#list + 1] = entry('barrel', netId, 'barrel', b.body, GetEntityCoords(b.obj)) end
    end
    for vehNetId, t in pairs(Trunks) do
        if DoesEntityExist(t.veh) then
            for _, item in ipairs(t.items) do
                list[#list + 1] = entry('trunk', vehNetId, 'trunk', item.body, GetEntityCoords(t.veh))
            end
        end
    end
    for netId, g in pairs(Graves) do
        if DoesEntityExist(g.obj) then
            list[#list + 1] = entry('grave', netId, g.cemetery and 'tombstone' or 'grave', g.body, GetEntityCoords(g.obj))
        end
    end
    return list
end)

-- free the body at (type, key): victim released, prop removed
local function freeBody(type, key)
    if type == 'container' then
        local c = RemoveContainer(key)
        if c then ReleaseBody(c.body) end
    elseif type == 'barrel' then
        local b = Barrels[key]
        if b and b.body then
            ReleaseBody(b.body)
            b.body, b.burning = nil, false
            if DoesEntityExist(b.obj) then
                Entity(b.obj).state:set('nzBody', nil, true)
                Entity(b.obj).state:set('nzBurning', nil, true)
            end
        end
    elseif type == 'trunk' then
        local t = Trunks[key]
        if t then
            for _, item in ipairs(t.items) do ReleaseBody(item.body) end
            t.items = {}
            RemoveFromTrunk(key, nil)
        end
    elseif type == 'grave' then
        local g = Graves[key]
        if g then
            Graves[key] = nil
            if DoesEntityExist(g.obj) then DeleteEntity(g.obj) end
            if g.dbId then MySQL.update('DELETE FROM nayzeee_bodybag_graves WHERE id = ?', { g.dbId }) end
        end
    end
end

RegisterNetEvent('nayzeee-bodybag:server:adminAction', function(action, type, key)
    local src = source
    if not IsStaff(src) then return end
    if action == 'free' then
        freeBody(type, key)
        Notify(src, 'Body removed and victim freed.', 'success')
        Log(src, 'ADMIN_FREE', ('%s %s'):format(type, key))
    elseif action == 'clearAll' then
        local n = 0
        for netId in pairs(Containers) do freeBody('container', netId) n = n + 1 end
        for netId, b in pairs(Barrels) do if b.body then freeBody('barrel', netId) n = n + 1 end end
        for vehNetId in pairs(Trunks) do freeBody('trunk', vehNetId) n = n + 1 end
        Notify(src, ('Cleared %d body(s). Graves were left alone.'):format(n), 'success')
        Log(src, 'ADMIN_CLEAR_ALL', ('%d cleared'):format(n))
    end
end)
