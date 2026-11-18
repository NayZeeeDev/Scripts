--[[ Admin menu: screens, creation, link groups, calibrator, prop library ]]

Admin = { isOpen = false }

local function catalogue()
    local out = {}
    for _, def in ipairs(Props.Ordered) do
        out[#out + 1] = { model = def.model, label = def.label, cat = def.cat, range = def.range, style = def.style, available = IsModelInCdimage(def.hash) }
    end
    local cats = {}
    for k, v in pairs(Props.Categories) do cats[#cats + 1] = { id = k, label = v.label } end
    table.sort(cats, function(a, b) return a.label < b.label end)
    return out, cats
end

function Admin.open(tab)
    CreateThread(function()
        local dash, err = NZ.rpc('admin', 'dashboard')
        if not dash then return NZ.notify(_L(err or 'no_admin'), 'error') end
        if Panel.isOpen then Panel.close() end
        if Remote.uiOpen then Remote.closeUi() end
        local props, cats = catalogue()
        Admin.isOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({
            type = 'admin', show = true, data = dash, props = props, categories = cats, tab = tab,
            now = NZ.serverNow(), brand = Config.Brand, me = GetPlayerName(PlayerId()),
            pos = (function() local c = GetEntityCoords(PlayerPedId()) return { x = c.x, y = c.y, z = c.z } end)(),
        })
    end)
end

function Admin.close()
    if not Admin.isOpen then return end
    Admin.isOpen = false
    Render.debugOutline = nil
    NZ.calibPreview = {}
    for _, tv in pairs(NZ.tvs) do tv._screen = nil end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'admin', show = false })
end

RegisterCommand(Config.Commands.admin, function()
    Admin.open()
end, false)

RegisterNUICallback('admin', function(data, cb)
    local res, msg = NZ.call('admin', data.op, data.data)
    cb({ ok = res ~= false and res ~= nil, res = res, msg = msg })
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    local dash = NZ.rpc('admin', 'dashboard')
    cb(dash or false)
end)

RegisterNUICallback('adminTp', function(data, cb)
    cb(1)
    local tv = NZ.tvs[data.id]
    local c = NZ.rpc('admin', 'tp', data.id)
    if type(c) ~= 'table' then return end
    local ped = PlayerPedId()
    local h = math.rad((tv and tv.heading) or 0.0)
    -- stand a few metres in front of the screen, facing it
    local dist = tv and math.min(8.0, 1.6 + (tv.range or 20.0) * 0.08) or 2.0
    local fx, fy = -math.sin(h), math.cos(h)
    if tv and tv.kind ~= 'wall' then fx, fy = -fx, -fy end
    SetEntityCoords(ped, c.x + fx * dist, c.y + fy * dist, c.z, false, false, false, false)
    SetEntityHeading(ped, GetHeadingFromVector_2d(-fx, -fy))
end)

--- Admin placement flows: prop / wall / existing.
RegisterNUICallback('adminPlace', function(data, cb)
    cb(1)
    local form = data.form or {}
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'admin', show = false, keep = true })
    Admin.isOpen = false

    local geo
    if data.mode == 'wall' then
        geo = Placement.wall({ width = tonumber(form.width) or 3.0 })
        if geo then geo.kind = 'wall' geo.style = form.style or 'cinema' geo.hd = true end
    elseif data.mode == 'existing' then
        geo = Placement.existing()
        if geo then geo.kind = 'existing' end
    else
        local def = Props.Get(form.model or '')
        if def then
            geo = Placement.prop({ model = def.model, label = def.label, title = 'Place permanent screen', maxDistance = 25.0 })
            if geo then geo.kind = 'prop' geo.model = def.model end
        end
    end

    if geo then
        if Config.Remote.Enabled and form.remote then
            Wait(200)
            local r = Placement.prop({ model = Config.Remote.Model, title = _L('place_remote_hint'), label = 'Optional — Backspace to skip',
                maxDistance = 8.0, from = vector3(geo.coords.x, geo.coords.y, geo.coords.z), floorOnly = true })
            if r then geo.remote = { x = r.coords.x, y = r.coords.y, z = r.coords.z, h = r.heading } end
        end
        for k, v in pairs(form) do
            if geo[k] == nil and k ~= 'remote' and k ~= 'width' then geo[k] = v end
        end
        NZ.call('admin', 'create', geo)
    end
    Wait(250)
    Admin.open('screens')
end)

RegisterNUICallback('adminMove', function(data, cb)
    cb(1)
    local tv = NZ.tvs[data.id]
    if not tv then return end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'admin', show = false, keep = true })
    Admin.isOpen = false
    local geo
    if tv.kind == 'wall' then geo = Placement.wall({ width = tv.wall and tv.wall.w or 3.0 })
    elseif tv.kind == 'prop' then geo = Placement.prop({ model = tv.model, label = tv.label, title = 'Move screen', maxDistance = 25.0 }) end
    if geo then
        geo.id = tv.id
        NZ.call('admin', 'update', geo)
    end
    Wait(250)
    Admin.open('screens')
end)

-- ─── calibrator ───────────────────────────────────────────────
RegisterNUICallback('calibStart', function(data, cb)
    local tv = data.id and NZ.tvs[data.id] or NZ.target(20.0)
    if not tv or tv.kind == 'wall' then cb(false) return NZ.notify('Stand near a prop screen to calibrate it.', 'error') end
    if not tv._entity then cb(false) return NZ.notify(_L('too_far'), 'error') end
    Render.debugOutline = tv.id
    local current = Render.screenDef(tv)
    cb({ id = tv.id, label = tv.label, model = tv.model, screen = current,
        auto = Render.autoScreen(tv.model, NZ.prop(tv)), saved = NZ.calibration[tv.model] ~= nil })
end)

local function invalidate(model)
    for _, tv in pairs(NZ.tvs) do if tv.model == model then tv._screen = nil end end
end

RegisterNUICallback('calibPreview', function(data, cb)
    cb(1)
    if type(data.screen) ~= 'table' then return end
    NZ.calibPreview[data.model] = data.screen
    invalidate(data.model)
end)

RegisterNUICallback('calibSave', function(data, cb)
    local res = NZ.call('admin', 'calibrate', { model = data.model, screen = data.screen })
    NZ.calibPreview[data.model] = nil
    invalidate(data.model)
    cb({ ok = res == true })
end)

RegisterNUICallback('calibReset', function(data, cb)
    NZ.calibPreview[data.model] = nil
    NZ.call('admin', 'calibReset', data.model)
    invalidate(data.model)
    cb(1)
end)

RegisterNUICallback('calibStop', function(data, cb)
    cb(1)
    Render.debugOutline = nil
    if data and data.model then NZ.calibPreview[data.model] = nil invalidate(data.model) end
end)
