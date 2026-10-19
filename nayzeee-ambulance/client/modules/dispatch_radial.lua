--[[
    NAYZEEE AMBULANCE - Dispatch (client): EMS radial job menu (NUI app 'radial')

    Opened with Config.Dispatch.radial.key (F6) by medics, on or off duty. Round nodes on an
    orbit; the centre is the unit badge: callsign + name, status word, the unit ring (call
    progress with four phase nodes while on a call) inside the duty ring (shift clock).
    Root (clockwise from 12): Status (on duty: go (un)available, end shift; off duty: start shift),
    Calls, Care, Pager + every root item other modules add. Calls: take next call, stand down,
    Board (Ops board on the fitting tab), street calls (toggle), link phone (phone.alerts = 'paired').
    Care holds the gurney sub-ring (move band). A ring never shows more than 9 nodes: Care is split
    into sub-rings by the §11 order bands (Assess / Resus & treat / Move / Procedures / Other) once it
    has more than 9 entries; any other ring gets a "More" node. Back = centre / right click.

    Other modules add entries at their file top level:
      NZA.RadialItems = NZA.RadialItems or {}
      table.insert(NZA.RadialItems, { id, parent = nil | 'status' | 'dispatch' | 'patient' | 'stretcher' | <any id>,
          label, icon, order, perm, desc?, danger?, keepOpen?, hideEmpty? (group hidden without entries),
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

-- the Ops board on the tab that fits: your call on the live map, else the overview
-- (the logbook, crews and ER intake are tabs of the same window)
local function openBoard()
    if not D.OpenBoard then return end
    D.OpenBoard(me().call and 'map' or 'overview')
end

local function builtins()
    local m = me()
    local duty = onDuty()
    local dutyToggle = cfg('radial', 'dutyToggle', true) ~= false
    -- root ring, clockwise from 12 o'clock: Status · Calls · Care · Pager (+ root entries of other modules)
    local list = {}
    if duty then
        list[#list + 1] = { id = 'status', label = L('dispatch.r_status'), icon = 'radio', order = 10,
            desc = L('dispatch.r_status_d', m.oos and L('dispatch.unit_107') or L('dispatch.unit_108')) }
        list[#list + 1] = { id = 'd_status', parent = 'status', order = 10, keepOpen = true,
            label = m.oos and L('dispatch.r_in_service') or L('dispatch.r_oos'), icon = m.oos and 'play' or 'pause',
            active = function() return me().oos == true end,
            desc = m.oos and L('dispatch.r_in_service_d') or L('dispatch.r_oos_d'),
            disabledText = m.call and L('dispatch.r_oos_busy') or nil,
            onSelect = function()
                local oos = not (me().oos == true)
                me().oos = oos
                me().status = oos and '10-7' or '10-8'
                D.SetStatus(oos and '10-7' or '10-8')
            end }
        if dutyToggle then
            list[#list + 1] = { id = 'duty', parent = 'status', order = 20, label = L('dispatch.r_duty_off'), icon = 'logout',
                danger = true, desc = L('dispatch.r_duty_off_d'), onSelect = function() D.SetDuty(false) end }
        end
    elseif dutyToggle then
        list[#list + 1] = { id = 'duty', label = L('dispatch.r_duty_on'), icon = 'login', order = 10,
            desc = L('dispatch.r_duty_on_d'), onSelect = function() D.SetDuty(true) end }
    end
    list[#list + 1] = { id = 'dispatch', label = L('dispatch.r_dispatch'), icon = 'broadcast', order = 20, desc = L('dispatch.r_dispatch_d'),
        disabledText = (not duty) and L('dispatch.r_need_duty') or nil }
    list[#list + 1] = { id = 'patient', label = L('dispatch.r_patient'), icon = 'heart', order = 30, desc = L('dispatch.r_patient_d'),
        emptyText = L('dispatch.r_patient_empty') }
    -- the gurney is part of Care (move band); it only shows when one of its entries can be used
    list[#list + 1] = { id = 'stretcher', parent = 'patient', label = L('dispatch.r_stretcher'), icon = 'bed', order = 55,
        desc = L('dispatch.r_stretcher_d'), hideEmpty = true }
    if duty and cfg('pager', 'enabled', true) ~= false then
        list[#list + 1] = { id = 'd_pager', label = L('dispatch.r_pager'), icon = 'pager', order = 40,
            disabledText = (not D.HasPager()) and L('dispatch.err_no_pager') or nil,
            onSelect = function() D.TogglePager() end }
    end
    if duty then
        -- Calls ring, clockwise from 12 o'clock (check-in adds 'Call next patient' 25 / 'Reception queue' 26)
        local dsp = {
            { id = 'd_respond', label = L('dispatch.r_respond'), icon = 'siren', order = 10, desc = L('dispatch.r_respond_d'),
              onSelect = function() D.Respond() end },
            { id = 'd_clear', label = L('dispatch.r_clear'), icon = 'x', order = 20, danger = true,
              disabledText = (not m.call) and L('dispatch.err_not_on_call') or nil,
              desc = m.call and L('dispatch.r_clear_d', m.call) or nil,
              onSelect = function() D.Clear() end },
            { id = 'd_board', label = L('dispatch.r_board'), icon = 'grid', order = 30,
              desc = m.call and L('dispatch.r_board_call') or L('dispatch.r_board_d'), onSelect = openBoard },
            { id = 'd_npc', label = L('dispatch.r_npc'), icon = 'call', order = 60, keepOpen = true,
              active = function() return me().npc == true end,
              desc = m.npc and L('dispatch.r_npc_on') or L('dispatch.r_npc_off'),
              onSelect = function()
                  local on = not (me().npc == true)
                  me().npc = on
                  D.SetNpcCalls(on)
              end },
        }
        -- phone alerts for medics without the pager menu at hand (Config.Dispatch.phone.alerts = 'paired')
        local hasPhone = Bridge and Bridge.Phone and Bridge.Phone.Resource ~= nil
        if D.PhoneMode and D.PhoneMode() == 'paired' and (hasPhone or m.paired) then
            local needPager = cfg('phone', 'linkNeedsPager', true) ~= false
            dsp[#dsp + 1] = { id = 'd_phone', label = L('dispatch.r_phone'), icon = 'phone', order = 70,
                active = function() return me().paired == true end,
                desc = m.paired and L('dispatch.r_phone_on') or L('dispatch.r_phone_off'),
                disabledText = (not m.paired and needPager and not D.HasPager()) and L('dispatch.err_no_pager') or nil,
                onSelect = function() D.Pair(not (me().paired == true)) end }
        end
        for _, it in ipairs(dsp) do it.parent = 'dispatch'; list[#list + 1] = it end
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════
-- TREE
-- ════════════════════════════════════════════════════════════════════════

local MAX_RING = 9    -- nodes per ring (quick pick 1-9); the rest goes into a "More" sub-ring

-- Care is split by the interaction order bands (ARCHITECTURE §11) once it has more than MAX_RING entries
local BANDS = {
    { key = 'assess', from = -math.huge, to = 29, icon = 'stetho' },
    { key = 'treat',  from = 30, to = 49, icon = 'medkit' },
    { key = 'move',   from = 50, to = 59, icon = 'walk' },
    { key = 'proc',   from = 60, to = 89, icon = 'scalpel' },
    { key = 'other',  from = 90, to = math.huge, icon = 'clipboard' },
}

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

local function byOrder(a, b)
    local oa, ob = tonumber(a.order) or 50, tonumber(b.order) or 50
    if oa ~= ob then return oa < ob end
    return tostring(a.id) < tostring(b.id)
end

-- built nodes → at most MAX_RING entries; the overflow becomes a synthetic "More" node (the JS
-- descends into any node with items, so synthetic nodes need no entry in `current`)
local function overflow(nodes, baseId)
    if #nodes <= MAX_RING then return nodes end
    local out, rest = {}, {}
    for i = 1, #nodes do
        if i < MAX_RING then out[#out + 1] = nodes[i] else rest[#rest + 1] = nodes[i] end
    end
    local id = baseId .. ':more'
    out[#out + 1] = { id = id, label = L('dispatch.r_more'), icon = 'more', desc = L('dispatch.r_more_d', #rest),
        items = overflow(rest, id) }
    return out
end

local function summary(nodes)
    local names = {}
    for i = 1, math.min(3, #nodes) do names[i] = nodes[i].label end
    return table.concat(names, ' · ') .. (#nodes > 3 and ' …' or '')
end

-- defs and their built nodes (same order) → sub-rings per order band
local function banded(defs, nodes, baseId)
    local groups, keys = {}, {}
    for i, d in ipairs(defs) do
        local o = tonumber(d.order) or 50
        for _, band in ipairs(BANDS) do
            if o >= band.from and o <= band.to then
                if not groups[band.key] then
                    groups[band.key] = { band = band, list = {} }
                    keys[#keys + 1] = band.key
                end
                table.insert(groups[band.key].list, nodes[i])
                break
            end
        end
    end
    if #keys < 2 then return overflow(nodes, baseId) end
    local out = {}
    for _, key in ipairs(keys) do
        local g = groups[key]
        if #g.list == 1 then
            out[#out + 1] = g.list[1]
        else
            local id = baseId .. ':' .. key
            out[#out + 1] = { id = id, label = L('dispatch.r_band_' .. key), icon = g.band.icon, desc = summary(g.list),
                items = overflow(g.list, id) }
        end
    end
    return overflow(out, baseId)
end

local function build()
    current = {}
    local defs = {}
    for _, d in ipairs(builtins()) do defs[#defs + 1] = d end
    local ownDuty = cfg('radial', 'dutyToggle', true) ~= false
    for _, d in ipairs(NZA.RadialItems) do
        -- the hospital module's duty entry does the same as our Status ▸ shift entry
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
            table.sort(kids, byOrder)
            local keptDefs, built = {}, {}
            for _, k in ipairs(kids) do
                local c = node(k, depth + 1)
                if c then
                    keptDefs[#keptDefs + 1] = k
                    built[#built + 1] = c
                end
            end
            if #built > 0 then
                n.items = d.id == 'patient' and banded(keptDefs, built, d.id) or overflow(built, d.id)
            end
        end
        if d.hideEmpty and not n.items then return nil end
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
    table.sort(root, byOrder)
    local out = {}
    for _, d in ipairs(root) do
        local n = node(d, 1)
        if n then out[#out + 1] = n end
    end
    return overflow(out, '_root')
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
        statusLabel = duty and (D.Phase[status] and L('dispatch.ph_' .. D.Phase[status])
            or L('dispatch.unit_' .. status:gsub('%-', ''))) or L('dispatch.r_shift_off'),
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
