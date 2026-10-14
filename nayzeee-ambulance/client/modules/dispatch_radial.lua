--[[
    NAYZEEE AMBULANCE - Dispatch (client): EMS radial job menu (NUI app 'radial')

    Opened with Config.Dispatch.radial.key (F6) by medics, on or off duty. Round nodes on an
    orbit; the centre is the unit badge: callsign + name, status word, the unit ring (6-stage
    ring while on a call) inside the duty ring (shift clock).
    Root (clockwise from 12): Calls, Care, Gurney, Start/End shift + every root item other
    modules add. Calls: take next call, stand down, live map, logbook, ER intake, street calls
    (toggle), go (un)available, pager. Back = centre / right click (no back node).

    Other modules add entries at their file top level:
      NZA.RadialItems = NZA.RadialItems or {}
      table.insert(NZA.RadialItems, { id, parent = nil | 'dispatch' | 'patient' | 'stretcher' | <any id>,
          label, icon, order, perm, desc?, danger?, keepOpen?,
          active = function() return bool end,     -- highlighted (toggle on)
          canShow = function() return bool end, onSelect = function() end })
    parent = nil puts it on the root ring; an item whose id is used as parent becomes a submenu.

    NUI callbacks: radial:select { id } → { close = true } | { items, title } (kept open for toggles)
    Keybind: nza_radial   Command: Config.Dispatch.radial.command
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Dispatch = NZA.Dispatch or {}
NZA.RadialItems = NZA.RadialItems or {}
local D = NZA.Dispatch

local APP = 'radial'
local current = {}       -- id → def while the menu is open
local isOpen = false
local changedAt = 0

local function cfg(section, key, default)
    local root = Config.Dispatch
    local c = type(root) == 'table' and root[section] or nil
    if type(c) ~= 'table' then return default end
    local v = c[key]
    if v == nil then return default end
    return v
end

local function L(key, ...) return NZA.L(key, ...) end
local function me() return (D.S and D.S.me) or {} end
local function onDuty() return D.IsOnDuty and D.IsOnDuty() or false end
local function isMedic() return me().medic == true or (NZA.IsMedic and NZA.IsMedic()) or false end

-- ════════════════════════════════════════════════════════════════════════
-- BUILT-IN ITEMS
-- ════════════════════════════════════════════════════════════════════════

local function board(tab) return function() if D.OpenBoard then D.OpenBoard(tab) end end end

local function builtins()
    local m = me()
    -- root ring, clockwise from 12 o'clock: Calls · Care · Gurney · Shift
    local list = {
        { id = 'dispatch', label = L('dispatch.r_dispatch'), icon = 'broadcast', order = 10, desc = L('dispatch.r_dispatch_d'),
          disabledText = (not onDuty()) and L('dispatch.r_need_duty') or nil },
        { id = 'patient', label = L('dispatch.r_patient'), icon = 'heart', order = 20, desc = L('dispatch.r_patient_d'),
          emptyText = L('dispatch.r_patient_empty') },
        { id = 'stretcher', label = L('dispatch.r_stretcher'), icon = 'bed', order = 30, desc = L('dispatch.r_stretcher_d'),
          emptyText = L('dispatch.r_stretcher_empty') },
    }
    if cfg('radial', 'dutyToggle', true) then
        list[#list + 1] = {
            id = 'duty', label = onDuty() and L('dispatch.r_duty_off') or L('dispatch.r_duty_on'), icon = onDuty() and 'logout' or 'login', order = 40,
            danger = onDuty(), desc = onDuty() and L('dispatch.r_duty_off_d') or L('dispatch.r_duty_on_d'),
            onSelect = function() D.SetDuty(not onDuty()) end,
        }
    end
    if onDuty() then
        -- Calls ring, clockwise from 12 o'clock
        local dsp = {
            { id = 'd_respond', label = L('dispatch.r_respond'), icon = 'siren', order = 10, desc = L('dispatch.r_respond_d'),
              onSelect = function() D.Respond() end },
            { id = 'd_clear', label = L('dispatch.r_clear'), icon = 'x', order = 20, danger = true,
              disabledText = (not m.call) and L('dispatch.err_not_on_call') or nil,
              desc = m.call and L('dispatch.r_clear_d', m.call) or nil,
              onSelect = function() D.Clear() end },
            { id = 'd_map', label = L('dispatch.r_map'), icon = 'map', order = 30, onSelect = board('map') },
            { id = 'd_log', label = L('dispatch.r_log'), icon = 'list', order = 40, onSelect = board('log') },
            { id = 'd_queue', label = L('dispatch.r_queue'), icon = 'hospital', order = 50, onSelect = board('queue') },
            { id = 'd_npc', label = L('dispatch.r_npc'), icon = 'call', order = 60, keepOpen = true,
              active = function() return me().npc == true end,
              desc = m.npc and L('dispatch.r_npc_on') or L('dispatch.r_npc_off'),
              onSelect = function()
                  local on = not (me().npc == true)
                  me().npc = on
                  D.SetNpcCalls(on)
              end },
            { id = 'd_status', label = m.oos and L('dispatch.r_in_service') or L('dispatch.r_oos'), icon = m.oos and 'play' or 'pause',
              order = 70, keepOpen = true, active = function() return me().oos == true end,
              desc = m.oos and L('dispatch.r_in_service_d') or L('dispatch.r_oos_d'),
              disabledText = m.call and L('dispatch.r_oos_busy') or nil,
              onSelect = function()
                  local oos = not (me().oos == true)
                  me().oos = oos
                  me().status = oos and '10-7' or '10-8'
                  D.SetStatus(oos and '10-7' or '10-8')
              end },
        }
        if cfg('pager', 'enabled', true) ~= false then
            dsp[#dsp + 1] = { id = 'd_pager', label = L('dispatch.r_pager'), icon = 'pager', order = 80,
                disabledText = (not D.HasPager()) and L('dispatch.err_no_pager') or nil,
                onSelect = function() D.TogglePager() end }
        end
        for _, it in ipairs(dsp) do it.parent = 'dispatch'; list[#list + 1] = it end
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════
-- TREE
-- ════════════════════════════════════════════════════════════════════════

local function allowed(def)
    if def.perm and not NZA.Perm(def.perm) then return false end
    if type(def.canShow) == 'function' then
        local ok, res = pcall(def.canShow)
        if not ok then
            NZA.Debug('radial: canShow failed for', def.id, res)
            return false
        end
        return res == true
    end
    return true
end

local function isActive(def)
    if type(def.active) == 'function' then
        local ok, res = pcall(def.active)
        return ok and res == true
    end
    return def.active == true
end

local function build()
    current = {}
    local defs = {}
    for _, d in ipairs(builtins()) do defs[#defs + 1] = d end
    local ownDuty = cfg('radial', 'dutyToggle', true) ~= false
    for _, d in ipairs(NZA.RadialItems) do
        -- the hospital module's duty entry does the same as our "Go on/off duty" segment
        if type(d) == 'table' and type(d.id) == 'string' and not (ownDuty and d.id == 'hospital_duty') then defs[#defs + 1] = d end
    end
    local byParent = {}
    for _, d in ipairs(defs) do
        if allowed(d) then
            current[d.id] = d
            local key = d.parent or '_root'
            byParent[key] = byParent[key] or {}
            table.insert(byParent[key], d)
        end
    end
    local function node(d, depth)
        local n = {
            id = d.id, label = d.label or d.id, icon = d.icon or 'more', desc = d.desc, danger = d.danger == true,
            active = isActive(d),
        }
        local kids = byParent[d.id]
        if kids and depth < 4 then
            table.sort(kids, function(a, b) return (a.order or 50) < (b.order or 50) end)
            n.items = {}
            for _, k in ipairs(kids) do n.items[#n.items + 1] = node(k, depth + 1) end
            if #n.items > 9 then
                for i = #n.items, 10, -1 do table.remove(n.items, i) end
            end
        end
        if d.disabledText then
            n.disabled = true
            n.desc = d.disabledText
        elseif not n.items and not d.onSelect then
            n.disabled = true
            n.desc = d.emptyText or L('dispatch.r_empty')
        end
        return n
    end
    local root = byParent._root or {}
    table.sort(root, function(a, b) return (a.order or 50) < (b.order or 50) end)
    local out = {}
    for _, d in ipairs(root) do
        out[#out + 1] = node(d, 1)
        if #out >= 10 then break end
    end
    return out
end

local STATUS_TONE = { ['10-8'] = 'teal', ['10-7'] = 'amber', DSP = 'amber', ENR = 'amber', SCN = 'red', CARE = 'red', TRN = 'white', HSP = 'teal' }

-- shift clock for the duty ring in the centre (counted from the first moment we see you on duty)
local shiftStart = nil
local function shiftSeconds()
    if not onDuty() then shiftStart = nil return 0 end
    shiftStart = shiftStart or GetGameTimer()
    return math.floor((GetGameTimer() - shiftStart) / 1000)
end

local function header()
    local m = me()
    local duty = onDuty()
    local status = duty and (m.status or '10-8') or '10-7'
    return {
        name = m.name or GetPlayerName(PlayerId()),
        callsign = duty and m.callsign or nil,
        grade = m.grade,
        status = status,
        statusLabel = duty and L('dispatch.unit_' .. status:gsub('%-', '')) or L('dispatch.r_shift_off'),
        tone = duty and (STATUS_TONE[status] or 'off') or 'off',
        onDuty = duty,
        shift = shiftSeconds(),
        call = m.call,
    }
end

function D.OpenRadial()
    if cfg('radial', 'enabled', true) == false then return end
    if GetGameTimer() - changedAt < 250 then return end
    changedAt = GetGameTimer()
    if isOpen and NZA.UI.IsOpen(APP) then
        NZA.UI.Close(APP)
        isOpen = false
        return
    end
    if not isMedic() then return end
    if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then return end
    if IsPauseMenuActive() then return end
    local data = header()
    data.items = build()
    data.key = cfg('radial', 'key', 'F6')
    data.locale = NZA.LocaleTable('dispatch')
    isOpen = true
    NZA.UI.Open(APP, data, { focus = true, cursor = true, keepInput = false })
end

NZA.UI.On(APP, 'select', function(data, cb)
    local id = type(data) == 'table' and data.id or nil
    local def = id and current[id]
    if not def or type(def.onSelect) ~= 'function' then
        cb({ ok = false })
        return
    end
    if def.keepOpen then
        local ok, err = pcall(def.onSelect)
        if not ok then NZA.Warn('radial: ' .. tostring(id) .. ' failed: ' .. tostring(err)) end
        local h = header()
        cb({ ok = true, items = build(), header = h })
        return
    end
    cb({ ok = true, close = true })
    NZA.UI.Close(APP)
    isOpen = false
    CreateThread(function()
        Wait(60)
        local ok, err = pcall(def.onSelect)
        if not ok then NZA.Warn('radial: ' .. tostring(id) .. ' failed: ' .. tostring(err)) end
    end)
end)

NZA.Bus.On('ui:closed', function(app)
    if app == APP then
        isOpen = false
        changedAt = GetGameTimer()
    end
end)

NZA.Bus.On('dispatch:me', function()
    shiftSeconds()   -- starts / resets the shift clock as soon as the duty state changes
    if isOpen and NZA.UI.IsOpen(APP) then
        NZA.UI.Send(APP, 'header', header())
    end
end)

CreateThread(function()
    Wait(0)
    if cfg('radial', 'enabled', true) == false then return end
    local key = cfg('radial', 'key', 'F6')
    if type(key) == 'string' and key ~= '' then
        lib.addKeybind({
            name = 'nza_radial',
            description = L('dispatch.bind_radial'),
            defaultMapper = 'keyboard',
            defaultKey = key,
            onPressed = function() D.OpenRadial() end,
        })
    end
    local cmd = cfg('radial', 'command', 'emsmenu')
    if type(cmd) == 'string' and cmd ~= '' then
        RegisterCommand(cmd, function() D.OpenRadial() end, false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then NZA.UI.Close(APP) end
end)
