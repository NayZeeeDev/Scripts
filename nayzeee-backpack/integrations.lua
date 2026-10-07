--[[
    ██╗███╗   ██╗████████╗███████╗ ██████╗ ██████╗  █████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗
    ██║████╗  ██║╚══██╔══╝██╔════╝██╔════╝ ██╔══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝
    ██║██╔██╗ ██║   ██║   █████╗  ██║  ███╗██████╔╝███████║   ██║   ██║██║   ██║██╔██╗ ██║███████╗
    ██║██║╚██╗██║   ██║   ██╔══╝  ██║   ██║██╔══██╗██╔══██║   ██║   ██║██║   ██║██║╚██╗██║╚════██║
    ██║██║ ╚████║   ██║   ███████╗╚██████╔╝██║  ██║██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║███████║
    ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝

    Job, medical, police and dispatch systems plug in here.

    Built in (switch on automatically when the resource is running):
      wasabi_ambulance, wasabi_police, qb-ambulancejob, qb-policejob,
      qbx_medical, qbx_police, esx_ambulancejob, esx_policejob,
      ps-dispatch, cd_dispatch, qs-dispatch, core_dispatch

    ------------------------------------------------------------------
    FOR OTHER CREATORS
    ------------------------------------------------------------------
    Either add a block to this file, or register from your own resource
    (works from client OR server, register on each side you need):

        exports['nayzeee-backpack']:RegisterIntegration('my_script', {
            resource = 'my_script',          -- only active while this is started

            client = {
                isDead   = function() return MyScript.dead end,      -- local player dead/downed?
                isCuffed = function() return MyScript.cuffed end,    -- local player restrained?
                isOnDuty = function(job) return MyScript.duty end,   -- nil = no opinion
                dispatch = function(data) end,                       -- send a police alert
                                                                     -- data = { coords, street, title, message, code, jobs }
            },

            server = {
                isOnDuty = function(src, job) return true end,
                canWear  = function(src, bagKey) return true end,    -- false blocks wearing
                onIssue  = function(src, bagKey, stashId) end,       -- a job bag was handed out
                onRobbed = function(robber, victim, bagKey) end,
            },
        })

    Every hook is optional and every call is wrapped in pcall, so a
    broken integration can never take the backpack script down with it.

    Events you can listen to:
      client  'nayzeee-backpack:client:equipped'  (bagKey, variant)
      client  'nayzeee-backpack:client:removed'   ()
      server  'nayzeee-backpack:server:robbed'    (robberId, victimId, bagKey)
      server  'nayzeee-backpack:server:placed'    (src, bagKey, coords, placedId)

    Exports (server):
      GetWornBag(src)          -> bagKey, state
      GiveBag(src, key, var)   -> boolean
      OpenBag(src)             -> opens the worn bag for that player
      GetBagStash(src)         -> stash id of the worn bag
]]

Integrations = { list = {}, order = {} }

local IS_SERVER = IsDuplicityVersion()
local SIDE = IS_SERVER and 'server' or 'client'

function Integrations.register(name, def)
    if type(name) ~= 'string' or type(def) ~= 'table' then return false end
    if not Integrations.list[name] then
        Integrations.order[#Integrations.order + 1] = name
    end
    def.name = name
    Integrations.list[name] = def
    Bags.debug(('integration registered: %s (%s)'):format(name, SIDE))
    return true
end

exports('RegisterIntegration', Integrations.register)

local function isActive(def)
    if def.always then return true end
    local res = def.resource
    if not res then return true end
    if type(res) == 'string' then return GetResourceState(res) == 'started' end
    for _, r in ipairs(res) do
        if GetResourceState(r) == 'started' then return true end
    end
    return false
end

local function hooksOf(def)
    return def[SIDE] or {}
end

--- First integration that gives a non-nil answer wins.
function Integrations.first(hook, ...)
    for _, name in ipairs(Integrations.order) do
        local def = Integrations.list[name]
        local fn = isActive(def) and hooksOf(def)[hook]
        if fn then
            local ok, result = pcall(fn, ...)
            if ok and result ~= nil then return result, name end
            if not ok then Bags.debug(('integration %s.%s errored: %s'):format(name, hook, result)) end
        end
    end
    return nil
end

--- True if ANY integration says true.
function Integrations.any(hook, ...)
    for _, name in ipairs(Integrations.order) do
        local def = Integrations.list[name]
        local fn = isActive(def) and hooksOf(def)[hook]
        if fn then
            local ok, result = pcall(fn, ...)
            if ok and result == true then return true, name end
        end
    end
    return false
end

--- False if ANY integration says false (used for "can I?" checks).
function Integrations.allow(hook, ...)
    for _, name in ipairs(Integrations.order) do
        local def = Integrations.list[name]
        local fn = isActive(def) and hooksOf(def)[hook]
        if fn then
            local ok, result = pcall(fn, ...)
            if ok and result == false then return false, name end
        end
    end
    return true
end

--- Call a hook on every active integration.
function Integrations.each(hook, ...)
    for _, name in ipairs(Integrations.order) do
        local def = Integrations.list[name]
        local fn = isActive(def) and hooksOf(def)[hook]
        if fn then pcall(fn, ...) end
    end
end

-----------------------------------------------------------------
-- helpers for the built-ins below
-----------------------------------------------------------------

local function try(fn)
    local ok, r = pcall(fn)
    if ok then return r end
    return nil
end

local function stateFlag(...)
    if IS_SERVER then return nil end
    local st = LocalPlayer.state
    for _, key in ipairs({ ... }) do
        if st[key] == true then return true end
    end
    return nil
end

-----------------------------------------------------------------
-- MEDICAL
-----------------------------------------------------------------

Integrations.register('wasabi_ambulance', {
    resource = 'wasabi_ambulance',
    client = {
        isDead = function()
            local r = try(function() return exports.wasabi_ambulance:isPlayerDead() end)
            if r ~= nil then return r and true or false end
            return stateFlag('dead', 'isDead')
        end,
    },
})

Integrations.register('qbx_medical', {
    resource = 'qbx_medical',
    client = {
        isDead = function()
            return stateFlag('isDead', 'dead', 'inLastStand')
        end,
    },
})

Integrations.register('qb-ambulancejob', {
    resource = 'qb-ambulancejob',
    client = {
        isDead = function()
            if Framework.getMeta('isdead') or Framework.getMeta('inlaststand') then return true end
            return nil
        end,
    },
})

if not IS_SERVER then
    -- esx_ambulancejob doesn't expose a getter, so track its events
    local esxDead = false
    AddEventHandler('esx:onPlayerDeath', function() esxDead = true end)
    AddEventHandler('esx:onPlayerSpawn', function() esxDead = false end)
    AddEventHandler('esx_ambulancejob:revive', function() esxDead = false end)

    Integrations.register('esx_ambulancejob', {
        resource = 'esx_ambulancejob',
        client = {
            isDead = function() return esxDead or nil end,
        },
    })
end

-----------------------------------------------------------------
-- POLICE
-----------------------------------------------------------------

Integrations.register('wasabi_police', {
    resource = 'wasabi_police',
    client = {
        isCuffed = function()
            local r = try(function() return exports.wasabi_police:IsHandcuffed() end)
            if r ~= nil then return r and true or false end
            return stateFlag('handcuffed', 'isCuffed', 'cuffed')
        end,
    },
})

Integrations.register('qbx_police', {
    resource = 'qbx_police',
    client = {
        isCuffed = function() return stateFlag('handcuffed', 'isCuffed', 'cuffed') end,
    },
})

Integrations.register('qb-policejob', {
    resource = 'qb-policejob',
    client = {
        isCuffed = function()
            if Framework.getMeta('ishandcuffed') then return true end
            return nil
        end,
    },
})

Integrations.register('esx_policejob', {
    resource = 'esx_policejob',
    client = {
        isCuffed = function()
            return IsEntityPlayingAnim(PlayerPedId(), 'mp_arresting', 'idle', 3) or nil
        end,
    },
})

-----------------------------------------------------------------
-- DISPATCH (called on the robber's client after a robbery)
-----------------------------------------------------------------

Integrations.register('ps-dispatch', {
    resource = 'ps-dispatch',
    client = {
        dispatch = function(d)
            exports['ps-dispatch']:CustomAlert({
                coords = d.coords,
                message = d.title,
                dispatchCode = d.code,
                code = d.code,
                description = d.message,
                icon = 'fas fa-bag-shopping',
                priority = 2,
                radius = 0,
                sprite = 52,
                color = 1,
                scale = 1.0,
                length = 3,
                jobs = { 'leo' },
            })
            return true
        end,
    },
})

Integrations.register('cd_dispatch', {
    resource = 'cd_dispatch',
    client = {
        dispatch = function(d)
            local info = exports['cd_dispatch']:GetPlayerInfo()
            TriggerServerEvent('cd_dispatch:AddNotification', {
                job_table = d.jobs,
                coords = info and info.coords or d.coords,
                title = ('%s - %s'):format(d.code, d.title),
                message = d.message,
                flash = 0,
                unique_id = info and info.unique_id or tostring(math.random(100000, 999999)),
                sound = 1,
                blip = { sprite = 52, scale = 1.0, colour = 1, flashes = false, text = d.title, time = 5, radius = 0 },
            })
            return true
        end,
    },
})

Integrations.register('qs-dispatch', {
    resource = 'qs-dispatch',
    client = {
        dispatch = function(d)
            TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
                job = d.jobs,
                callLocation = d.coords,
                callCode = { code = d.code, snippet = d.title },
                message = d.message,
                flashes = false,
                blip = { sprite = 52, scale = 1.0, colour = 1, flashes = true, text = d.title, time = 300000 },
            })
            return true
        end,
    },
})

Integrations.register('core_dispatch', {
    resource = 'core_dispatch',
    client = {
        dispatch = function(d)
            exports['core_dispatch']:addCall(d.code, d.title,
                { { icon = 'fa-bag-shopping', info = d.message } },
                { d.coords.x, d.coords.y, d.coords.z }, d.jobs[1] or 'police', 3000, 52, 1)
            return true
        end,
    },
})
