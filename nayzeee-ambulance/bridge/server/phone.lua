--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: phones (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Phone adapters: lb-phone, qs-smartphone,
    qs-smartphone-pro, npwd, yseries, gksphone, okokPhone, roadphone,
    high-phone, renewed-phone.

    API
      Bridge.Phone.Resource                       detected adapter name or nil (kept up to date)
      Bridge.Phone.Notify(src, { title, message, app?, icon?, fallback? }) → bool
          fallback = true shows an on-screen notification when there is no phone
      Bridge.Phone.Mail(src, { sender, subject, message }) → bool
      Bridge.Phone.Number(src) → string | nil
      Bridge.CallEMS(src, message, coords?, meta?) → ok, callId | err

    EXPORT (for phones, dispatch scripts, radial menus, anything)
      exports['nayzeee-ambulance']:CallEMS(src, message, coords?) → ok, callId
    SERVER EVENT (server side only, not callable by clients)
      TriggerEvent('nza:callEMS', src, message, coords?)

    911 / EMS FORWARDING
      Messages and calls that reach EMS through the phone become NZA dispatch
      calls (NZA.Dispatch.Create). Verified hooks: npwd onCall/onMessage,
      lb-phone server events 'lb-phone:newCompanyMessage' and 'lb-phone:newCall'
      (payload read defensively). qs-smartphone job alerts are read from the
      net event 'qs-smartphone:server:sendJobAlert' (community-documented).
      Any phone: add its event to Config.Bridge.phoneEmergency.events, or call
      the CallEMS export from the phone's own (open) config.

    EVENTS SENT
      nza:bridge:phone (S→C) action, payload    client half of an adapter (bridge/client/phone.lua)

    Each adapter note says whether the export was checked against the phone's
    public docs/source ("verified") or taken from community integrations.
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Phone = Bridge.Phone or {}
Bridge.Phone.Resource = nil

local P = {}
Bridge.PhoneAdapters = P

local function appFor(name, data)
    if data and data.app then return data.app end
    local apps = Bridge.Cfg('phoneApp', {}) or {}
    return apps[name]
end

local function relay(src, action, payload)
    TriggerClientEvent('nza:bridge:phone', src, action, payload)
    return true
end

local function frameworkPhone(src)
    local fw = Bridge.FrameworkAdapters and Bridge.FrameworkAdapters[Bridge.Framework]
    if not fw or not fw.charInfo then return nil end
    local ok, info = pcall(fw.charInfo, src)
    return ok and info and info.phone and tostring(info.phone) or nil
end

local function phoneSender()
    return NZA.L('bridge.mail_sender')
end

-- ═══════════════════════════════════════════════════════════════════════════
-- lb-phone  (verified: SendNotification, GetEquippedPhoneNumber, GetEmailAddress, SendMail)
-- ═══════════════════════════════════════════════════════════════════════════

P['lb-phone'] = {
    notify = function(src, data)
        exports['lb-phone']:SendNotification(src, {
            app = appFor('lb-phone', data),
            title = data.title,
            content = data.message,
        })
        return true
    end,
    mail = function(src, data)
        local number = exports['lb-phone']:GetEquippedPhoneNumber(src)
        if not number then return false end
        local email = exports['lb-phone']:GetEmailAddress(number)
        if not email then return false end
        local ok = exports['lb-phone']:SendMail({
            to = email,
            sender = data.sender or phoneSender(),
            subject = data.subject,
            message = data.message,
        })
        return ok ~= false
    end,
    number = function(src)
        return exports['lb-phone']:GetEquippedPhoneNumber(src)
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- qs-smartphone / qs-smartphone-pro
-- notification event: NAYZEEE multijob adapter; mail: client event used by
-- community bridges; number: qs-base export (falls back to the framework)
-- ═══════════════════════════════════════════════════════════════════════════

local function makeQs(resource)
    return {
        notify = function(src, data)
            TriggerClientEvent(resource .. ':client:notification', src, {
                title = data.title,
                text = data.message,
                icon = data.icon or 'fas fa-truck-medical',
                color = '#08afa2',
                timeout = data.duration or 6000,
                app = appFor(resource, data),
            })
            return true
        end,
        mail = function(src, data)
            return relay(src, 'mail', { phone = resource, sender = data.sender or phoneSender(), subject = data.subject, message = data.message })
        end,
        number = function(src)
            if Bridge.Started('qs-base') then
                local ok, number = pcall(function() return exports['qs-base']:GetPlayerPhone(src) end)
                if ok and number then return number end
            end
            return frameworkPhone(src)
        end,
        emergencyEvents = { { event = resource .. ':server:sendJobAlert', net = true } },
    }
end

P['qs-smartphone'] = makeQs('qs-smartphone')
P['qs-smartphone-pro'] = makeQs('qs-smartphone-pro')

-- ═══════════════════════════════════════════════════════════════════════════
-- npwd  (verified against the npwd source: getPhoneNumber, createNotification,
-- onCall, onMessage). npwd has no mail app: mail becomes a notification.
-- ═══════════════════════════════════════════════════════════════════════════

P['npwd'] = {
    notify = function(src, data)
        return relay(src, 'notify', { phone = 'npwd', app = appFor('npwd', data), title = data.title, message = data.message, duration = data.duration })
    end,
    number = function(src)
        return exports.npwd:getPhoneNumber(src)
    end,
    emergency = function(forward, cfg)
        for _, number in ipairs(cfg.numbers or {}) do
            number = tostring(number)
            exports.npwd:onCall(number, function(ctx)
                local caller = ctx.incomingCaller or {}
                forward(tonumber(caller.source), NZA.L('bridge.phone_call_text', caller.number or '?'), nil, { via = 'npwd:call', number = caller.number })
                if cfg.reply ~= false then ctx.reply(NZA.L('bridge.phone_reply')) end
                ctx.next()
            end)
            exports.npwd:onMessage(number, function(ctx)
                local msg = ctx.data and ctx.data.message
                forward(tonumber(ctx.source), msg, nil, { via = 'npwd:message', number = ctx.data and ctx.data.sourcePhoneNumber })
            end)
        end
        return true
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- yseries (TeamsGG docs: SendNotification(data, toType, to), SendMail(data, toType, to),
-- GetPhoneNumberBySourceId). No public services hook: use the CallEMS export
-- or Config.Bridge.phoneEmergency.events.
-- ═══════════════════════════════════════════════════════════════════════════

P['yseries'] = {
    notify = function(src, data)
        exports.yseries:SendNotification({
            app = appFor('yseries', data),
            title = data.title,
            text = data.message,
            timeout = data.duration or 6000,
            icon = data.icon,
        }, 'source', src)
        return true
    end,
    mail = function(src, data)
        exports.yseries:SendMail({
            title = data.subject,
            sender = data.sender or phoneSender(),
            senderDisplayName = data.sender or phoneSender(),
            content = data.message,
        }, 'source', src)
        return true
    end,
    number = function(src)
        return exports.yseries:GetPhoneNumberBySourceId(src)
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- gksphone (mail + number: community bridges; notify: NAYZEEE multijob adapter)
-- ═══════════════════════════════════════════════════════════════════════════

P['gksphone'] = {
    notify = function(src, data)
        TriggerClientEvent('gksphone:NotificationShow', src, {
            title = data.title,
            message = data.message,
            icon = appFor('gksphone', data),
            time = data.duration or 6000,
        })
        return true
    end,
    mail = function(src, data)
        exports['gksphone']:SendNewMail(src, {
            sender = data.sender or phoneSender(),
            image = '/html/static/img/icons/mail.png',
            subject = data.subject,
            message = data.message,
        })
        return true
    end,
    number = function(src)
        return exports['gksphone']:GetPhoneBySource(src)
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- okokPhone (okokPhone docs: pushNotifyViaPhoneNumber; community bridges:
-- getPhoneNumberFromSource, getEmailAddressFromSource, sendEmail)
-- ═══════════════════════════════════════════════════════════════════════════

P['okokPhone'] = {
    notify = function(src, data)
        local number = exports.okokPhone:getPhoneNumberFromSource(src)
        if not number then return false end
        exports.okokPhone:pushNotifyViaPhoneNumber(number, {
            app = appFor('okokPhone', data),
            title = data.title,
            message = data.message,
            type = data.type == 'error' and 'emergency' or 'normal',
        })
        return true
    end,
    mail = function(src, data)
        local email = exports.okokPhone:getEmailAddressFromSource(src)
        if not email then return false end
        return exports.okokPhone:sendEmail({
            sender = data.sender or phoneSender(),
            recipients = { email },
            subject = data.subject,
            body = data.message,
        }) ~= false
    end,
    number = function(src)
        return exports.okokPhone:getPhoneNumberFromSource(src)
    end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- roadphone (notify: NAYZEEE multijob adapter; mail: client export sendMail)
-- ═══════════════════════════════════════════════════════════════════════════

P['roadphone'] = {
    notify = function(src, data)
        TriggerClientEvent('roadphone:notify', src, {
            app = appFor('roadphone', data),
            title = data.title,
            message = data.message,
            timeout = data.duration or 6000,
        })
        return true
    end,
    mail = function(src, data)
        return relay(src, 'mail', { phone = 'roadphone', sender = data.sender or phoneSender(), subject = data.subject, message = data.message })
    end,
    number = frameworkPhone,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- high-phone (notify: NAYZEEE multijob adapter)
-- ═══════════════════════════════════════════════════════════════════════════

P['high-phone'] = {
    notify = function(src, data)
        TriggerClientEvent('high_phone:notification', src, {
            title = data.title,
            message = data.message,
            app = appFor('high-phone', data),
            timeout = data.duration or 6000,
        })
        return true
    end,
    number = frameworkPhone,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- renewed-phone (qb-phone fork: CustomNotification + sendNewMailToOffline)
-- ═══════════════════════════════════════════════════════════════════════════

P['renewed-phone'] = {
    notify = function(src, data)
        TriggerClientEvent('qb-phone:client:CustomNotification', src,
            data.title or 'EMS', data.message, data.icon or 'fas fa-truck-medical', '#08afa2', data.duration or 6000)
        return true
    end,
    mail = function(src, data)
        local identifier = Bridge.GetIdentifier(src)
        if not identifier then return false end
        exports['renewed-phone']:sendNewMailToOffline(identifier, {
            sender = data.sender or phoneSender(),
            subject = data.subject,
            message = data.message,
        })
        return true
    end,
    number = frameworkPhone,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- RESOLVE
-- ═══════════════════════════════════════════════════════════════════════════

local resolvedOnce = false

local function resolve()
    if resolvedOnce then return Bridge.Phone.Resource end
    resolvedOnce = true
    Bridge.Phone.Resource = Bridge.Pick('phone', Bridge.Cfg('phone', 'auto'), {
        has = function(name) return P[name] ~= nil end,
    })
    return Bridge.Phone.Resource
end

local function adapter()
    local name = resolve()
    return name and P[name] or nil, name
end

function Bridge.Phone.Notify(src, data)
    src = tonumber(src)
    if not src or type(data) ~= 'table' or not data.message then return false end
    local A, name = adapter()
    local ok, done = false, false
    if A and A.notify then
        ok, done = Bridge.Try('phone.' .. name .. '.notify', A.notify, src, data)
    end
    if ok and done then return true end
    if data.fallback then return Bridge.Notify(src, data) end
    return false
end

function Bridge.Phone.Mail(src, data)
    src = tonumber(src)
    if not src or type(data) ~= 'table' or not data.message then return false end
    local A, name = adapter()
    if not A then return false end
    if A.mail then
        local ok, done = Bridge.Try('phone.' .. name .. '.mail', A.mail, src, data)
        if ok and done then return true end
    end
    -- phones without mail: deliver as a phone notification
    return Bridge.Phone.Notify(src, { title = data.subject or data.sender, message = data.message })
end

function Bridge.Phone.Number(src)
    src = tonumber(src)
    if not src then return nil end
    local A, name = adapter()
    if A and A.number then
        local ok, number = Bridge.Try('phone.' .. name .. '.number', A.number, src)
        if ok and number and number ~= '' then return tostring(number) end
    end
    return frameworkPhone(src)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CALL EMS  (everything that turns into an EMS dispatch call goes through here)
-- ═══════════════════════════════════════════════════════════════════════════

local function emergencyCfg()
    return Bridge.Cfg('phoneEmergency', {}) or {}
end

local function notifyMedicsDirectly(call)
    for _, medic in ipairs(Bridge.GetMedics(true)) do
        Bridge.Notify(medic, { title = call.title, message = ('%s: %s'):format(call.caller, call.message), type = 'warning', duration = 10000 })
        Bridge.Phone.Notify(medic, { title = call.title, message = call.message })
    end
end

function Bridge.CallEMS(src, message, coords, meta)
    meta = type(meta) == 'table' and meta or {}
    src = tonumber(src)
    if src and (src <= 0 or not GetPlayerName(tostring(src))) then src = nil end
    local cfg = emergencyCfg()

    if src and not Bridge.Throttle(src, 'callems', math.max(1, tonumber(cfg.cooldown) or 60) * 1000) then
        Bridge.Notify(src, { title = NZA.L('bridge.callems_title'), message = NZA.L('bridge.callems_cooldown'), type = 'warning' })
        return false, 'cooldown'
    end

    coords = Bridge.ToVec3(coords)
    if not coords and src then coords = GetEntityCoords(GetPlayerPed(tostring(src))) end
    if not coords then return false, 'no_coords' end

    local text = Bridge.CleanText(message, 250) or NZA.L('bridge.callems_default')
    local caller = src and Bridge.GetName(src) or Bridge.CleanText(meta.caller, 64) or NZA.L('bridge.callems_unknown')

    local patients = {}
    if src and NZA.Patients and NZA.Patients.GetBySource then
        local ok, patient = pcall(NZA.Patients.GetBySource, src)
        if ok and patient and patient.state and patient.state ~= 'alive' then patients[1] = patient.pid end
    end

    local call = {
        code = '10-52',
        priority = #patients > 0 and 1 or 2,
        title = NZA.L('bridge.callems_call_title'),
        type = 'call',
        coords = coords,
        caller = caller,
        message = text,
        phone = src and Bridge.Phone.Number(src) or meta.number,
        patients = patients,
        npc = false,
        source = src and 'player' or 'system',
        callerSrc = src,
        via = meta.via or 'export',
    }

    if NZA.Dispatch and NZA.Dispatch.Create then
        local ok, callId = pcall(NZA.Dispatch.Create, call)
        if ok and callId then
            if src then Bridge.Notify(src, { title = NZA.L('bridge.callems_title'), message = NZA.L('bridge.callems_sent'), type = 'success' }) end
            return true, callId
        end
        Bridge.Warn('NZA.Dispatch.Create failed: ' .. tostring(callId))
    end

    -- no dispatch module running: still reach the medics
    if Bridge.Dispatch and Bridge.Dispatch.External then Bridge.Dispatch.External(call) end
    notifyMedicsDirectly(call)
    if src then Bridge.Notify(src, { title = NZA.L('bridge.callems_title'), message = NZA.L('bridge.callems_sent'), type = 'success' }) end
    return true, nil
end

exports('CallEMS', function(src, message, coords)
    local ok, result = Bridge.CallEMS(src, message, coords, { via = GetInvokingResource() or 'export' })
    return ok, result
end)

AddEventHandler('nza:callEMS', function(src, message, coords)
    -- server-side only: a client cannot trigger a non-net event on the server
    if source ~= '' and tonumber(source) and tonumber(source) > 0 then return end
    Bridge.CallEMS(src, message, coords, { via = 'event' })
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- DEFENSIVE PAYLOAD READER for phone events whose payload is not documented
-- ═══════════════════════════════════════════════════════════════════════════

local KEYS = {
    job     = { 'company', 'job', 'companyname', 'service', 'channel', 'jobname', 'name' },
    message = { 'message', 'content', 'text', 'body', 'msg', 'description' },
    number  = { 'callee', 'number', 'phonenumber', 'target', 'to', 'receiver', 'receivernumber', 'dialled', 'dialed' },
    source  = { 'source', 'src', 'callersource', 'playerid', 'sender_source', 'serverid' },
    coords  = { 'coords', 'location', 'position', 'gps', 'pos' },
}

local function flatten(value, out, depth)
    if depth > 3 or type(value) ~= 'table' then return end
    for k, v in pairs(value) do
        if type(k) == 'string' then
            local key = k:lower()
            if out.fields[key] == nil and type(v) ~= 'table' then out.fields[key] = v end
            if out.fields[key] == nil and (key == 'coords' or key == 'location' or key == 'position' or key == 'gps' or key == 'pos') then
                out.fields[key] = v
            end
        end
        if type(v) == 'table' then flatten(v, out, depth + 1) end
        if type(v) == 'vector3' or type(v) == 'vector4' then
            local key = type(k) == 'string' and k:lower() or 'coords'
            if out.fields[key] == nil then out.fields[key] = v end
        end
    end
end

local function pick(fields, keys)
    for _, key in ipairs(keys) do
        if fields[key] ~= nil then return fields[key] end
    end
    return nil
end

local function lowerSet(list)
    local set = {}
    for _, v in ipairs(list or {}) do set[tostring(v):lower()] = true end
    for _, v in ipairs(Bridge.MedicJobs()) do set[tostring(v):lower()] = true end
    return set
end

--- Read job / message / number / source / coords from any event arguments.
local function readPayload(...)
    local out = { fields = {}, strings = {}, numbers = {}, coords = nil }
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        local t = type(v)
        if t == 'table' then
            flatten(v, out, 0)
        elseif t == 'string' then
            out.strings[#out.strings + 1] = v
        elseif t == 'number' then
            out.numbers[#out.numbers + 1] = v
        elseif t == 'vector3' or t == 'vector4' then
            out.coords = v
        end
    end
    local f = out.fields
    return {
        job = pick(f, KEYS.job),
        message = pick(f, KEYS.message),
        number = pick(f, KEYS.number),
        source = tonumber(pick(f, KEYS.source)),
        coords = out.coords or pick(f, KEYS.coords),
        strings = out.strings,
        numbers = out.numbers,
    }
end

local function isEmsTarget(data, cfg)
    local companies = lowerSet(cfg.companies)
    local numbers = {}
    for _, n in ipairs(cfg.numbers or {}) do numbers[tostring(n)] = true end
    if data.job and companies[tostring(data.job):lower()] then return true end
    if data.number and numbers[tostring(data.number)] then return true end
    for _, s in ipairs(data.strings) do
        if companies[s:lower()] or numbers[s] then return true end
    end
    return false
end

local function longestString(list, exclude)
    local best
    for _, s in ipairs(list) do
        if not exclude[s:lower()] and (not best or #s > #best) then best = s end
    end
    return best
end

local function sourceFromNumber(number)
    if not number then return nil end
    number = tostring(number)
    if Bridge.Phone.Resource == 'lb-phone' then
        local ok, src = pcall(function() return exports['lb-phone']:GetSourceFromNumber(number) end)
        if ok and tonumber(src) then return tonumber(src) end
    end
    for _, src in ipairs(Bridge.GetPlayers()) do
        if Bridge.Phone.Number(src) == number then return src end
    end
    return nil
end

--- Build a handler for a phone event. netSource = true when a client fires it.
local function eventForwarder(eventName, netSource, forward)
    return function(...)
        local cfg = emergencyCfg()
        if cfg.enabled == false then return end
        local data = readPayload(...)
        if not isEmsTarget(data, cfg) then return end

        local src
        if netSource then
            src = tonumber(source)                       -- a client sent it: trust only the sender
        else
            src = data.source or sourceFromNumber(data.number)
            if not src then
                for _, n in ipairs(data.numbers) do
                    if n > 0 and GetPlayerName(tostring(n)) then src = n break end
                end
            end
        end
        if not src or src <= 0 or not GetPlayerName(tostring(src)) then
            Bridge.Debug(('phone event %s: EMS message without a resolvable player - ignored'):format(eventName))
            return
        end
        -- on-duty medics answering in the company chat are not new emergencies
        if Bridge.IsMedic(src) and Bridge.IsOnDuty(src) then return end

        local exclude = lowerSet(cfg.companies)
        local message = Bridge.CleanText(type(data.message) == 'string' and data.message or longestString(data.strings, exclude), 250)
        -- coordinates from a client are not trusted; the caller's position is used
        local coords = (not netSource) and Bridge.ToVec3(data.coords) or nil
        forward(src, message, coords, { via = eventName })
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REGISTER EMERGENCY HOOKS
-- ═══════════════════════════════════════════════════════════════════════════

local registeredEvents = {}
local registeredHooks = {}

local function forward(src, message, coords, meta)
    local cfg = emergencyCfg()
    if cfg.enabled == false then return false end
    return Bridge.CallEMS(src, message or NZA.L('bridge.callems_default'), coords, meta)
end

local function listenEvent(entry)
    if type(entry) ~= 'table' or type(entry.event) ~= 'string' then return end
    if registeredEvents[entry.event] then return end
    registeredEvents[entry.event] = true
    local handler = eventForwarder(entry.event, entry.net == true, forward)
    if entry.net then
        RegisterNetEvent(entry.event, handler)
    else
        AddEventHandler(entry.event, handler)
    end
    Bridge.Debug('listening for EMS messages on', entry.event)
end

-- lb-phone documents these server events; their payload is read defensively
local LB_EVENTS = {
    { event = 'lb-phone:newCompanyMessage', net = false },
    { event = 'lb-phone:newCall', net = false },
}

local function registerEmergency()
    local cfg = emergencyCfg()
    if cfg.enabled == false then return end
    local name = Bridge.Phone.Resource

    for _, entry in ipairs(cfg.events or {}) do listenEvent(entry) end

    if name == 'lb-phone' then
        for _, entry in ipairs(LB_EVENTS) do listenEvent(entry) end
    end

    local A = name and P[name]
    if not A then return end
    for _, entry in ipairs(A.emergencyEvents or {}) do listenEvent(entry) end
    if A.emergency and not registeredHooks[name] then
        local ok = Bridge.Try('phone.' .. name .. '.emergency', A.emergency, forward, cfg)
        registeredHooks[name] = ok
    end
end

local function onResource(resource, started)
    if resource == GetCurrentResourceName() or not Bridge.IsKnownResource('phone', resource) then return end
    resolvedOnce = false
    Bridge.Phone.Resource = nil
    for adapterName, res in pairs(Bridge.Resources.phone) do
        if res == resource then registeredHooks[adapterName] = nil end
    end
    if started then
        SetTimeout(1500, function()
            resolve()
            registerEmergency()
        end)
    else
        resolve()
    end
end

AddEventHandler('onResourceStart', function(resource) onResource(resource, true) end)
AddEventHandler('onResourceStop', function(resource) onResource(resource, false) end)

CreateThread(function()
    Wait(1000)
    resolve()
    registerEmergency()
    print(('^5[nayzeee-ambulance]^7 Bridge | phone: ^3%s^7'):format(Bridge.Phone.Resource or 'none'))
end)
