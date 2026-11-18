--[[ Media panel + NUI callbacks shared by panel, remote and TV OS actions ]]

Panel = { isOpen = false, tv = nil }

function Panel.lite(tv)
    return {
        id = tv.id, label = tv.label, power = tv.power, volume = tv.volume, muted = tv.muted, media = tv.media or false,
        queue = tv.queue or {}, history = tv.history or {}, loop = tv.loop, channel = tv.channel, settings = tv.settings,
        locked = tv.locked, group = tv.group, style = tv.style, model = tv.model, kind = tv.kind, permanent = tv.permanent,
        remote = tv.remote ~= nil, remoteHolder = tv.remoteHolder, range = tv.range, perms = tv.perms,
    }
end

function Panel.open(tv)
    CreateThread(function()
        if Placement.active then return end
        local data, err = NZ.rpc('panel', tv.id)
        if not data then return NZ.notify(_L(err or 'no_permission'), 'error') end
        if Remote.uiOpen then Remote.closeUi() end
        Panel.isOpen, Panel.tv = true, tv.id
        SetNuiFocus(true, true)
        data.tv = Panel.lite(tv)
        SendNUIMessage({ type = 'panel', show = true, data = data, now = NZ.serverNow(), brand = Config.Brand })
    end)
end

function Panel.close()
    if not Panel.isOpen then return end
    Panel.isOpen, Panel.tv = false, nil
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'panel', show = false })
end

NZ.on('patch', function(tv, patch)
    if Panel.isOpen and Panel.tv == tv.id then
        SendNUIMessage({ type = 'panelPatch', id = tv.id, patch = patch, now = NZ.serverNow() })
    end
end)

NZ.on('removed', function(tv)
    if Panel.tv == tv.id then Panel.close() end
end)

-- ─── commands ─────────────────────────────────────────────────
RegisterCommand(Config.Commands.panel, function()
    local tv = NZ.target(14.0)
    if not tv then return NZ.notify(_L('no_tv_near'), 'error') end
    Panel.open(tv)
end, false)

RegisterCommand(Config.Commands.remote, function()
    if Remote.holding then
        local tv = NZ.tvs[Remote.holding]
        if tv then return Remote.openUi(tv, true) end
    end
    local tv = NZ.target(Config.Remote.Range)
    if not tv then return NZ.notify(_L('no_tv_near'), 'error') end
    Remote.openVirtual(tv)
end, false)

-- ─── callbacks ────────────────────────────────────────────────
local function tvOf(data) return type(data) == 'table' and data.id and NZ.tvs[data.id] or nil end

RegisterNUICallback('close', function(data, cb)
    cb(1)
    local what = type(data) == 'table' and data.what or 'all'
    if what == 'panel' or what == 'all' then Panel.close() end
    if what == 'remote' or what == 'all' then Remote.closeUi() end
    if what == 'admin' or what == 'all' then Admin.close() end
    if what == 'all' then SetNuiFocus(false, false) end
end)

RegisterNUICallback('control', function(data, cb)
    local tv = tvOf(data)
    if not tv then return cb({ ok = false }) end
    local res, msg = NZ.call('control', tv.id, data.action, data.data)
    cb({ ok = res ~= false and res ~= nil, msg = msg })
end)

RegisterNUICallback('key', function(data, cb)
    local tv = tvOf(data)
    if not tv then return cb({ ok = false }) end
    local res, msg = NZ.rpc('key', tv.id, data.key)
    if res == false and msg then NZ.notify(_L(msg), 'error') end
    cb({ ok = res == true })
end)

RegisterNUICallback('type', function(data, cb)
    local tv = tvOf(data)
    if not tv then return cb({ ok = false }) end
    cb({ ok = NZ.rpc('type', tv.id, tostring(data.text or '')) == true })
end)

RegisterNUICallback('favorite', function(data, cb)
    local list = NZ.call('favorite', data.op, data.item)
    cb({ list = type(list) == 'table' and list or nil })
end)

RegisterNUICallback('search', function(data, cb)
    local res, msg = NZ.rpc('search', data.q)
    if res == false and msg then NZ.notify(_L(msg), 'error') end
    cb({ results = type(res) == 'table' and res or {} })
end)

RegisterNUICallback('manage', function(data, cb)
    local tv = tvOf(data)
    if not tv then return cb({ ok = false }) end
    local res = NZ.call('manage', tv.id, data.op, data.data)
    cb({ ok = res == true })
end)

RegisterNUICallback('panelRefresh', function(data, cb)
    local tv = tvOf(data)
    if not tv then return cb(false) end
    local res = NZ.rpc('panel', tv.id)
    if type(res) == 'table' then res.tv = Panel.lite(tv) end
    cb(res or false)
end)

RegisterNUICallback('pickup', function(data, cb)
    cb(1)
    local tv = tvOf(data)
    if not tv then return end
    Panel.close()
    NZ.call('pickup', tv.id)
end)

RegisterNUICallback('openRemote', function(data, cb)
    cb(1)
    local tv = tvOf(data)
    if not tv then return end
    Panel.close()
    Wait(50)
    if Remote.holding == tv.id then Remote.openUi(tv, true) else Remote.openUi(tv, false) end
end)

RegisterNUICallback('openPanel', function(data, cb)
    cb(1)
    local tv = tvOf(data)
    if not tv then return end
    Remote.closeUi()
    Wait(50)
    Panel.open(tv)
end)

RegisterNUICallback('remotePutDown', function(_, cb)
    cb(1)
    Remote.putDown()
end)

RegisterNUICallback('remotePlace', function(data, cb)
    cb(1)
    local tv = tvOf(data)
    if not tv then return end
    Panel.close()
    local res = Placement.prop({ model = Config.Remote.Model, title = _L('place_remote_hint'), label = tv.label, maxDistance = 6.0,
        from = vector3(tv.coords.x, tv.coords.y, tv.coords.z), floorOnly = true })
    if res then NZ.call('remotePlace', tv.id, res.coords, res.heading) end
end)

-- ─── TV OS actions (only from the DUI of the player who pressed the key) ──
local function osRelay(tv, payload) NZ.rpc('osData', tv.id, payload) end

NZ.on('osAction', function(tv, a)
    if type(a) ~= 'table' then return end
    if a.action == 'play' or a.action == 'queue' then
        NZ.call('control', tv.id, a.action, { url = a.url, title = a.title })
    elseif a.action == 'control' then
        NZ.call('control', tv.id, a.name, a.data)
    elseif a.action == 'keyboard' then
        if Remote.uiOpen and Remote.tv == tv.id then
            SendNUIMessage({ type = 'keyboard', show = true, value = a.value or '', hint = a.hint })
        end
    elseif a.action == 'search' then
        local res, msg = NZ.rpc('search', a.q)
        if res == false then
            osRelay(tv, { kind = 'searchError', text = msg and _L(msg) or 'Search failed' })
        else
            osRelay(tv, { kind = 'search', q = a.q, results = res })
        end
    elseif a.action == 'panel' then
        Remote.closeUi()
        Panel.open(tv)
    end
end)

RegisterNetEvent('nztv:osData', function(id, payload)
    local slot = Render.active[id]
    if slot then Render.send(slot, { type = 'osData', data = payload }) end
end)
