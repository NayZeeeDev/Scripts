--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: external dispatch / MDT mirror (server)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Our own dispatch board, pager and call cards
    always work. With Config.Bridge.externalDispatch = true every EMS call is
    ALSO sent to the dispatch/MDT script the server uses:
    lb-tablet, cd_dispatch, ps-dispatch, qs-dispatch, rcore_dispatch,
    core_dispatch, tk_dispatch, origen_police.

      Bridge.Dispatch.External(call) → bool
          call = the NZA call table (§9): { code, priority 1..3, title, message?,
                 coords, street?, caller?, callerSrc?, blip = { sprite, colour } }
      Bridge.Dispatch.Resource() → adapter name or nil

    Most dispatch scripts only accept alerts from a client. Those adapters run
    on one player's client (the caller if online, else an on-duty medic, else
    any player) through the event below; lb-tablet is called from the server.

    EVENTS SENT
      nza:bridge:dispatch (S→C) adapter, call, jobs     (bridge/client/dispatch.lua)

    ADDING YOUR OWN
      server side : Bridge.DispatchAdapters['my_dispatch'] = { server = function(call, jobs) ... return true end }
      client side : Bridge.DispatchClient['my_dispatch'] = function(call, jobs) ... end  (bridge/client/dispatch.lua)
      and Bridge.Resources.dispatch['my_dispatch'] = 'my_dispatch' + Bridge.Priority.dispatch
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

Bridge.Dispatch = Bridge.Dispatch or {}

local D = {}
Bridge.DispatchAdapters = D

local PRIORITY_WORD = { [1] = 'high', [2] = 'medium', [3] = 'low' }

-- lb-tablet (verified: server export AddDispatch)
D['lb-tablet'] = {
    server = function(call, jobs)
        exports['lb-tablet']:AddDispatch({
            priority = PRIORITY_WORD[call.priority] or 'medium',
            code = call.code,
            title = call.title,
            description = call.message or call.title,
            location = {
                label = call.street or call.title,
                coords = vector2(call.coords.x, call.coords.y),
            },
            time = 600,
            job = jobs[1],
        })
        return true
    end,
}

-- These run on a client (bridge/client/dispatch.lua)
D['cd_dispatch']    = { client = true }
D['ps-dispatch']    = { client = true }
D['qs-dispatch']    = { client = true }
D['rcore_dispatch'] = { client = true }
D['core_dispatch']  = { client = true }
D['tk_dispatch']    = { client = true }
D['origen_police']  = { client = true }

local resolved, resolvedOnce = nil, false

local function resolve()
    if resolvedOnce then return resolved end
    resolvedOnce = true
    resolved = Bridge.Pick('dispatch', Bridge.Cfg('dispatch', 'auto'), {
        has = function(name) return D[name] ~= nil end,
    })
    return resolved
end

function Bridge.Dispatch.Resource()
    return resolve()
end

local function relayPlayer(call)
    local src = tonumber(call.callerSrc)
    if src and GetPlayerName(tostring(src)) then return src end
    local medics = Bridge.GetMedics(true)
    if medics[1] then return medics[1] end
    local players = Bridge.GetPlayers()
    return players[1]
end

local function sanitize(call)
    local coords = Bridge.ToVec3(call.coords)
    if not coords then return nil end
    local priority = math.floor(tonumber(call.priority) or 2)
    if priority < 1 or priority > 3 then priority = 2 end
    local blip = type(call.blip) == 'table' and call.blip or {}
    return {
        code = Bridge.CleanText(call.code, 16) or '10-52',
        priority = priority,
        title = Bridge.CleanText(call.title, 80) or NZA.L('bridge.dispatch_title'),
        message = Bridge.CleanText(call.message, 250) or Bridge.CleanText(call.title, 80) or NZA.L('bridge.dispatch_title'),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        street = Bridge.CleanText(call.street, 80),
        caller = Bridge.CleanText(call.caller, 64),
        id = call.id or call.callId,
        blip = {
            sprite = tonumber(blip.sprite) or 153,
            colour = tonumber(blip.colour or blip.color) or 1,
            scale = tonumber(blip.scale) or 1.0,
        },
    }
end

function Bridge.Dispatch.External(call)
    if not Bridge.Cfg('externalDispatch', false) then return false end
    if type(call) ~= 'table' then return false end
    local name = resolve()
    if not name then return false end
    local c = sanitize(call)
    if not c then return false end
    local jobs = Bridge.Cfg('dispatchJobs', nil) or Bridge.MedicJobs()
    local A = D[name]

    if A.server then
        local ok, done = Bridge.Try('dispatch.' .. name, A.server, c, jobs)
        return ok and done ~= false
    end

    local target = relayPlayer(call)
    if not target then return false end
    TriggerClientEvent('nza:bridge:dispatch', target, name, c, jobs)
    return true
end

local function reset(resource)
    if resource == GetCurrentResourceName() then return end
    if Bridge.IsKnownResource('dispatch', resource) then
        resolvedOnce, resolved = false, nil
    end
end

AddEventHandler('onResourceStart', reset)
AddEventHandler('onResourceStop', reset)
