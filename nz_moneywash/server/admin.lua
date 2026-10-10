--[[ Admin layout tool — move any machine in game; the new spot survives restarts ]]

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command.nzmw')
end

lib.callback.register('nzmw:isAdmin', function(src)
    return isAdmin(src)
end)

lib.callback.register('nzmw:admin:move', function(src, id, pos, heading)
    if not isAdmin(src) then return { ok = false, err = 'Admins only.' } end
    local st = Stations.list[id]
    if not st then return { ok = false, err = 'That machine no longer exists.' } end
    if st.state ~= 'idle' then return { ok = false, err = 'Empty the machine before moving it.' } end
    if type(pos) ~= 'table' then return { ok = false, err = 'Bad position.' } end
    local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
    if not x or not y or not z then return { ok = false, err = 'Bad position.' } end

    st.x, st.y, st.z, st.h, st.moved = x, y, z, (tonumber(heading) or 0) % 360, true
    if st.placed then
        MySQL.update('UPDATE nzmw_equipment SET x = ?, y = ?, z = ?, h = ? WHERE id = ?', { x, y, z, st.h, tonumber(st.id:sub(2)) })
    end
    Stations.commit(id)

    local line = ('{ type = %q, coords = vec4(%.2f, %.2f, %.2f, %.1f) },'):format(st.type, x, y, z, st.h)
    print(('^2[nz_moneywash]^7 %s moved %s → paste into config/locations.lua to make it permanent:\n    %s'):format(GetPlayerName(src), id, line))
    return { ok = true, line = line }
end)

lib.callback.register('nzmw:admin:reset', function(src, id)
    if not isAdmin(src) then return { ok = false, err = 'Admins only.' } end
    local st = Stations.list[id]
    if not st or st.placed then return { ok = false, err = 'Only config machines can be reset.' } end
    if st.state ~= 'idle' then return { ok = false, err = 'Empty the machine first.' } end
    local opId, idx = id:match('^(.+):(%d+)$')
    for _, op in ipairs(Config.Operations) do
        if op.id == opId and op.stations[tonumber(idx)] then
            local c = op.stations[tonumber(idx)].coords
            st.x, st.y, st.z, st.h, st.moved = c.x, c.y, c.z, c.w, nil
            Stations.commit(id)
            return { ok = true }
        end
    end
    return { ok = false, err = 'Not found in config.' }
end)
