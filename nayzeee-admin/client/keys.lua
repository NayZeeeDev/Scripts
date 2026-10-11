-- Bindable admin actions (Config.Keybinds). Each one is a key mapping that fires once per press,
-- so nothing here runs while idle. Players set them in Settings > Key Bindings > FiveM.
local Local = LocalActions

local function staff(perm) return Me.isStaff and (not perm or Can(perm)) end

local function done(ok, msg, fail)
    if ok then if msg then Notify(msg, 'success') end
    elseif fail then Notify(fail, 'error') end
end

local Binds = {
    duty = { 'Admin: toggle duty', function()
        if not Me.isStaff then return end
        CreateThread(function()
            local ok, err = RPC('staff:duty', { state = not Me.duty })
            if not ok then Notify(err, 'error') end
        end)
    end },
    god = { 'Admin: god mode', function() if staff() then SetToggle('god') end end },
    invis = { 'Admin: invisibility', function() if staff() then SetToggle('invis') end end },
    ids = { 'Admin: player IDs', function() if staff() then SetToggle('ids') end end },
    freeze = { 'Admin: freeze yourself', function() if staff() then SetToggle('freeze') end end },
    heal = { 'Admin: heal yourself', function() if staff('self.revive') then done(Local.selfHeal(), 'Healed.') end end },
    revive = { 'Admin: revive yourself', function() if staff('self.revive') then Local.selfRevive() end end },
    repair = { 'Admin: repair vehicle', function() if staff('vehicles.repair') then done(Local.vehRepair(), 'Vehicle repaired.', 'Sit in a vehicle first.') end end },
    flip = { 'Admin: flip vehicle', function() if staff('vehicles.repair') then done(Local.vehFlip(), nil, 'Sit in a vehicle first.') end end },
    delveh = { 'Admin: delete vehicle', function() if staff('vehicles.despawn') then done(Local.vehDelete(), 'Vehicle deleted.', 'No vehicle near you.') end end },
    copycoords = { 'Admin: copy coords', function() if staff() then Notify('Copied ' .. Local.copyCoords({ format = 'vec4' }), 'success') end end },
    reports = { 'Admin: open reports', function() if staff('reports.view') and not UI.open then OpenPanel('reports') end end },
    players = { 'Admin: open players', function() if staff() and not UI.open then OpenPanel('players') end end },
}

for id, key in pairs(Config.Keybinds or {}) do
    local b = Binds[id]
    if b and key ~= false then
        local name = 'nzadmin_' .. id
        RegisterCommand(name, b[2], false)
        RegisterKeyMapping(name, b[1], 'keyboard', type(key) == 'string' and key or '')
    end
end

--- The keys each bindable action is on right now (shown in the panel settings).
function BindLabels()
    local out = {}
    for id, key in pairs(Config.Keybinds or {}) do
        if Binds[id] and key ~= false then out[#out + 1] = { id = id, label = Binds[id][1]:gsub('^Admin: ', ''), key = KeyLabel('nzadmin_' .. id) or (key ~= '' and key or nil) } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end
