--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE AMBULANCE - Bridge: external dispatch (client half)
    ═══════════════════════════════════════════════════════════════════════════

    OPEN FILE (escrow_ignore). Most dispatch/MDT scripts only accept alerts
    from a client. The server picks one player (the caller, an on-duty medic
    or anyone online) and sends 'nza:bridge:dispatch' (adapter, call, jobs);
    this file forwards the call to that script.

    call = { code, priority 1..3, title, message, coords = { x, y, z }, street?, caller?, blip = { sprite, colour, scale } }

    Sources: ps-dispatch CustomAlert (verified against its source);
    cd_dispatch, qs-dispatch, tk_dispatch, origen_police (community bridges);
    rcore_dispatch 'rcore_dispatch:server:sendAlert' and core_dispatch addCall
    (vendor docs, not checkable here - wrapped in pcall).

    ADDING YOUR OWN
      Bridge.DispatchClient['my_dispatch'] = function(call, jobs) ... end
    ═══════════════════════════════════════════════════════════════════════════
]]

if not NAYZEEE_LOCK_OK then return end

local D = {}
Bridge.DispatchClient = D

local PRIORITY_WORD = { [1] = 'high', [2] = 'medium', [3] = 'low' }

local function vec(call)
    return vector3(call.coords.x + 0.0, call.coords.y + 0.0, call.coords.z + 0.0)
end

D['cd_dispatch'] = function(call, jobs)
    local ok, info = pcall(function() return exports['cd_dispatch']:GetPlayerInfo() end)
    TriggerServerEvent('cd_dispatch:AddNotification', {
        job_table = jobs,
        coords = vec(call),
        title = ('%s - %s'):format(call.code, call.title),
        message = call.message,
        flash = call.priority == 1 and 1 or 0,
        unique_id = (ok and type(info) == 'table' and info.unique_id) or tostring(math.random(1000000, 9999999)),
        sound = 1,
        blip = {
            sprite = call.blip.sprite, scale = call.blip.scale, colour = call.blip.colour,
            flashes = call.priority == 1, text = call.title, time = 5, radius = 0,
        },
    })
end

D['ps-dispatch'] = function(call, jobs)
    exports['ps-dispatch']:CustomAlert({
        message = call.title,
        dispatchCode = 'nza_ems',
        code = call.code,
        icon = 'fas fa-truck-medical',
        priority = call.priority == 1 and 1 or 2,
        coords = vec(call),
        information = call.message,
        name = call.caller,
        sprite = call.blip.sprite,
        color = call.blip.colour,
        scale = call.blip.scale,
        length = 3,
        flash = call.priority == 1,
        jobs = jobs,
    })
end

D['qs-dispatch'] = function(call, jobs)
    TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
        job = jobs,
        callLocation = vec(call),
        callCode = { code = call.code, snippet = call.title },
        message = call.message,
        flashes = call.priority == 1,
        image = nil,
        blip = {
            sprite = call.blip.sprite, scale = call.blip.scale, colour = call.blip.colour,
            flashes = call.priority == 1, text = call.title, time = 20000,
        },
        otherData = { { text = call.caller or 'N/A', icon = 'fas fa-user' } },
    })
end

D['rcore_dispatch'] = function(call, jobs)
    TriggerServerEvent('rcore_dispatch:server:sendAlert', {
        code = call.code,
        default_priority = PRIORITY_WORD[call.priority] or 'medium',
        coords = vec(call),
        job = jobs,
        text = call.message,
        type = 'alerts',
        blip_time = 5,
        blip = {
            sprite = call.blip.sprite, colour = call.blip.colour, scale = call.blip.scale,
            text = call.title, flashes = call.priority == 1, radius = 0,
        },
    })
end

D['core_dispatch'] = function(call, jobs)
    for _, job in ipairs(jobs) do
        exports['core_dispatch']:addCall(call.code, call.title, {
            { icon = 'fa-solid fa-truck-medical', info = call.message },
            { icon = 'fa-solid fa-user', info = call.caller or 'N/A' },
        }, { call.coords.x, call.coords.y, call.coords.z }, job, 5000, call.blip.sprite, call.blip.colour)
    end
end

D['tk_dispatch'] = function(call, jobs)
    exports.tk_dispatch:addCall({
        title = call.title,
        code = call.code,
        message = call.message,
        priority = ('Priority %d'):format(call.priority),
        coords = vec(call),
        showLocation = true,
        showGender = false,
        playSound = true,
        blip = { color = call.blip.colour, sprite = call.blip.sprite, scale = call.blip.scale },
        jobs = jobs,
    })
end

D['origen_police'] = function(call, jobs)
    TriggerServerEvent('SendAlert:police', {
        coords = vec(call),
        title = ('%s %s'):format(call.code, call.title),
        message = call.message,
        job = jobs[1] or 'ambulance',
    })
end

RegisterNetEvent('nza:bridge:dispatch', function(adapter, call, jobs)
    if type(adapter) ~= 'string' or type(call) ~= 'table' or type(call.coords) ~= 'table' then return end
    if type(jobs) ~= 'table' or #jobs == 0 then jobs = Bridge.MedicJobs() end
    call.blip = type(call.blip) == 'table' and call.blip or { sprite = 153, colour = 1, scale = 1.0 }
    local fn = D[adapter]
    if fn then Bridge.Try('dispatch.' .. adapter, fn, call, jobs) end
end)
