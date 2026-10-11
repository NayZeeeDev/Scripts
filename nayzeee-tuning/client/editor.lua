--[[ /mechaniceditor: walk to a spot, "set here", preview the markers, save them live. ]]

local open, preview, walking = false, nil, false

local function toVec(t) return t and vec3(t.x, t.y, t.z) or nil end

local COLORS = { bay = { 8, 175, 162 }, boss = { 245, 158, 11 }, booth = { 168, 85, 247 }, pile = { 59, 130, 246 }, drop = { 34, 197, 94 }, truck = { 229, 72, 77 }, storage = { 34, 211, 238 }, center = { 255, 255, 255 } }

local function marker(kind, c, heading, radius)
    local col = COLORS[kind] or COLORS.center
    if kind == 'bay' then
        local r = radius or 2.4
        DrawMarker(1, c.x, c.y, c.z - 0.98, 0, 0, 0, 0, 0, 0, r * 2.0, r * 2.0, 0.3, col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
        DrawMarker(22, c.x, c.y, c.z + 0.6, 0, 0, 0, 90.0, (heading or 0.0) + 90.0, 0, 0.6, 0.6, 0.6, col[1], col[2], col[3], 200, false, false, 2, false, nil, nil, false)
    elseif kind == 'booth' then
        local r = radius or 4.5
        DrawMarker(1, c.x, c.y, c.z - 0.98, 0, 0, 0, 0, 0, 0, r * 2.0, r * 2.0, 1.2, col[1], col[2], col[3], 60, false, false, 2, false, nil, nil, false)
    elseif kind == 'truck' then
        DrawMarker(36, c.x, c.y, c.z + 0.8, 0, 0, 0, 0, 0, heading or 0.0, 1.6, 1.6, 1.6, col[1], col[2], col[3], 200, false, false, 2, false, nil, nil, false)
        DrawMarker(43, c.x, c.y, c.z - 0.98, 0, 0, 0, 0, 0, heading or 0.0, 3.0, 8.0, 0.3, col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
    elseif kind == 'drop' then
        DrawMarker(1, c.x, c.y, c.z - 0.98, 0, 0, 0, 0, 0, 0, 8.0, 8.0, 0.4, col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
    else
        DrawMarker(kind == 'pile' and 39 or kind == 'boss' and 31 or kind == 'storage' and 21 or 2, c.x, c.y, c.z + 0.4, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, col[1], col[2], col[3], 220, true, true, 2, false, nil, nil, false)
    end
end

local function label(c, text)
    local on, x, y = World3dToScreen2d(c.x, c.y, c.z + 1.2)
    if not on then return end
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

-- draw every point of the shop being edited
CreateThread(function()
    while true do
        if open and preview then
            local d = preview
            local me = GetEntityCoords(cache.ped)
            local function near(c) return c and #(me - c) < 120.0 end
            local c = toVec(d.center)
            if near(c) then marker('center', c) label(c, (d.label or d.id) .. ' (centre)') end
            for i, b in ipairs(d.bays or {}) do local v = toVec(b) if near(v) then marker('bay', v, b.w, b.r or d.bayRadius) label(v, ('Bay %d · %.1fm'):format(i, b.r or d.bayRadius or 2.4)) end end
            for i, b in ipairs(d.booths or {}) do local v = toVec(b.coords) if near(v) then marker('booth', v, nil, b.radius) label(v, 'Paint booth ' .. i) end end
            for pile, p in pairs(d.stockpiles or {}) do local v = toVec(p) if near(v) then marker('pile', v) label(v, 'Rack: ' .. pile) end end
            local boss = toVec(d.boss)
            if near(boss) then marker('boss', boss) label(boss, 'Boss desk') end
            local drop = toVec(d.drop)
            if near(drop) then marker('drop', drop) label(drop, 'Drop point') end
            local st = toVec(d.storage)
            if near(st) then marker('storage', st) label(st, 'Supply storage') end
            local ts = d.truckSpawn and toVec(d.truckSpawn)
            if near(ts) then marker('truck', ts, d.truckSpawn.w) label(ts, 'Work truck') end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

--------------------------------------------------------------------- "set here" + walk mode

-- where you stand (or your car, for bays and the work truck), on the ground + ped height
local function here(kind)
    local ent = (cache.vehicle and (kind == 'bay' or kind == 'truck')) and cache.vehicle or cache.ped
    local p = GetEntityCoords(ent)
    local z = p.z
    local ok, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 0.5, false)
    if ok and gz ~= 0 and p.z - gz < 3.0 then z = gz + 0.98 end
    return { x = p.x, y = p.y, z = z, w = GetEntityHeading(ent) % 360.0 }
end

-- blur the editor and hand control back so you can walk to the next spot
local function walk(on)
    if not open then return end
    walking = on
    UI.Focus(not on)
    UI.Send('editor:walk', on)
end

lib.addKeybind({
    name = 'nzt_editor_walk',
    description = 'Tuning: shop editor, walk around / back to the editor',
    defaultKey = (Config.Editor and Config.Editor.WalkKey) or 'F2',
    onPressed = function() if open then walk(not walking) end end,
})

--------------------------------------------------------------------- NUI

RegisterNetEvent('nayzeee-tuning:editor', function()
    if open then return end
    local ok, data = lib.callback.await('nayzeee-tuning:editor:open', false)
    if not ok then return Notify(data or L('no_permission'), 'error') end
    open = true
    local p = GetEntityCoords(cache.ped)
    data.here = { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(cache.ped) }
    UI.Send('editor:open', data)
    UI.Focus(true)
end)

UI.On('ed:close', function()
    open, preview, walking = false, nil, false
    UI.Send('editor:close')
    UI.Focus(false)
    return true
end)

UI.On('ed:preview', function(d) preview = d return true end)

UI.On('ed:here', function(d) return here(d and d.kind) end)
UI.On('ed:walk', function() walk(true) return true end)

UI.On('ed:goto', function(d)
    if d and d.x then
        SetEntityCoords(cache.vehicle or cache.ped, d.x + 0.0, d.y + 0.0, d.z + 0.0, false, false, false, false)
    end
    return true
end)

local function wrap(ok, res) return { ok = ok == true, data = ok and res or nil, error = not ok and res or nil } end
UI.On('ed:save', function(d) return wrap(lib.callback.await('nayzeee-tuning:editor:save', false, d.id, d.data)) end)
UI.On('ed:reset', function(d) return wrap(lib.callback.await('nayzeee-tuning:editor:reset', false, d.id)) end)
UI.On('ed:disable', function(d) return wrap(lib.callback.await('nayzeee-tuning:editor:disable', false, d.id)) end)
