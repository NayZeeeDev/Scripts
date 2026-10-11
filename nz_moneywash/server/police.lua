--[[ Police side — dispatch, UV serial scanner, machine forensics ]]

Police = {}

local function mask(name)
    if not name then return 'Unknown' end
    local first, last = name:match('^(%S+)%s+(%S+)')
    if not first then return name:sub(1, 1) .. '.' end
    return ('%s. %s.'):format(first:sub(1, 1), last:sub(1, 1))
end

function Police.alert(coords, title, message, code)
    local data = { coords = coords, title = title, message = message, code = code or '10-66' }
    if SvConfig.Dispatch then
        local ok, handled = pcall(SvConfig.Dispatch, data)
        if ok and handled then return end
    end
    Bridge.eachPlayer(function(src)
        if NZ.isPoliceJob(Bridge.getJob(src)) then
            TriggerClientEvent('nzmw:policeAlert', src, { x = coords.x, y = coords.y, z = coords.z, title = title, message = message, code = data.code })
        end
    end)
end

local function canScan(src)
    return NZ.isPoliceJob(Bridge.getJob(src)) and Inv.count(src, Config.Heat.scannerItem) > 0
end

-- What a UV scan reveals about a batch
local function trace(b)
    local readable = not b.reserialized and b.heat >= 25
    return {
        serial = b.serial,
        amount = b.amount,
        heat = math.floor(b.heat),
        stage = b.stage,
        reserialized = b.reserialized,
        origin = readable and b.source or nil,
        loader = readable and mask(b.ownerName) or nil,
        verdict = b.reserialized and 'Serial chain broken — re-printed notes'
            or (b.heat >= 60 and 'Hot — matches flagged serial ranges')
            or (b.heat >= 25 and 'Warm — partial serial match')
            or 'Clean read',
    }
end

lib.callback.register('nzmw:scan:player', function(src, target)
    target = tonumber(target)
    if not target or not canScan(src) then return { ok = false, err = 'You need a UV scanner (police only).' } end
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 or #(GetEntityCoords(a) - GetEntityCoords(b)) > 3.5 then
        return { ok = false, err = 'Get closer.' }
    end

    local found = {}
    for _, stage in ipairs(NZ.pipeline()) do
        local item = Config.Stages[stage].outputItem
        for _, slot in ipairs(Inv.batchSlots(target, item)) do
            local batch = Batches.get(slot.metadata.batch)
            if batch then
                local t = trace(batch)
                t.item = Config.ItemLabels[item] or item
                found[#found + 1] = t
            end
        end
    end

    local dirty = {}
    for _, s in ipairs(Stations.dirtySources(target)) do
        dirty[#dirty + 1] = { label = s.label, total = s.total }
    end

    Bridge.notify(target, 'UV light', 'Someone sweeps a UV scanner over your pockets.', 'info')
    Bridge.log('UV scan (player)', { { 'Officer', Bridge.getName(src) }, { 'Target', Bridge.getName(target) }, { 'Batches', #found } })
    return { ok = true, kind = 'player', subject = Bridge.getName(target), batches = found, dirty = dirty }
end)

lib.callback.register('nzmw:scan:station', function(src, id)
    if not canScan(src) then return { ok = false, err = 'You need a UV scanner (police only).' } end
    local st = Stations.list[id]
    if not st then return { ok = false, err = 'Nothing here.' } end
    if #(GetEntityCoords(GetPlayerPed(src)) - vec3(st.x, st.y, st.z)) > Config.MaxInteractDistance then
        return { ok = false, err = 'Get closer.' }
    end
    local p = Stations.priv[id]
    local res = {
        ok = true, kind = 'station', subject = st.label .. (st.opLabel and (' · ' .. st.opLabel) or ''),
        state = st.state, wear = NZ.round(st.wear, 1), owner = st.placed and mask(st.ownerName) or nil, batches = {},
    }
    local b = p.batch and Batches.get(p.batch)
    if b then
        local t = trace(b)
        t.item = 'In machine'
        t.trail = {}
        for i = math.max(1, #b.trail - 5), #b.trail do
            local e = b.trail[i]
            t.trail[#t.trail + 1] = { t = e.t, text = e.text:gsub('by (.+)$', function(n) return 'by ' .. mask(n) end) }
        end
        res.batches[1] = t
    end
    return res
end)
