--[[
    NAYZEEE AMBULANCE - Admin commands

    Commands named in Config.Commands (set a name to false to disable it):
      /revive [id]                               full revive + heal (no id = yourself)
      /heal [id]                                 remove injuries; revives too if the target is down
      /injure [id] [region|random] [type] [sev]  add an injury (testing)
      /kill [id] [arrest]                        dead, or cardiac arrest with 'arrest' (only when Config.Commands.kill is set)
    /nzadmin belongs to the hospital module and is NOT registered here.

    Access: server console, or NZA.Core.IsAdmin (Bridge.IsAdmin / ace Config.Admin.ace).
    Chat suggestions are sent to admins when their character loads and on resource start.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Core = NZA.Core or {}
NZA.Patients = NZA.Patients or {}
local Core = NZA.Core
local P = NZA.Patients

local suggestions = {}

local function reply(src, msg, kind)
    if src == 0 then
        print('[nayzeee-ambulance] ' .. tostring(msg))
    else
        Core.Notify(src, msg, kind or 'info')
    end
end

local function targetOf(src, arg)
    local id = tonumber(arg)
    if not id then
        if src > 0 then return src end
        return nil
    end
    if not Core.Online(id) then return nil end
    return math.floor(id)
end

local function patientOf(id)
    return P.GetBySource(id) or P.LoadPlayer(id)
end

local function register(key, help, params, fn)
    local name = Config.Commands and Config.Commands[key]
    if type(name) ~= 'string' or name == '' then return end
    RegisterCommand(name, function(source, args)
        local src = tonumber(source) or 0
        if src > 0 and not Core.IsAdmin(src) then
            reply(src, NZA.L('core.cmd_no_perm'), 'error')
            return
        end
        local ok, err = pcall(fn, src, args or {})
        if not ok then
            NZA.Warn(('/%s failed: %s'):format(name, tostring(err)))
            reply(src, NZA.L('core.err_failed'), 'error')
        end
    end, false)
    suggestions[#suggestions + 1] = { name = '/' .. name, help = help, params = params }
end

local function sendSuggestions(src)
    if not Core.IsAdmin(src) then return end
    for _, s in ipairs(suggestions) do
        TriggerClientEvent('chat:addSuggestion', src, s.name, s.help, s.params)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- COMMANDS (registered from a thread: Config is final and every core file is loaded)
-- ════════════════════════════════════════════════════════════════════════

local function registerAll()
    local pId = { name = 'id', help = NZA.L('core.cmd_param_id') }

    register('revive', NZA.L('core.cmd_revive_help'), { pId }, function(src, args)
        local id = targetOf(src, args[1])
        if not id then return reply(src, NZA.L('core.cmd_no_target'), 'error') end
        local p = patientOf(id)
        if p then
            P.Revive(p, { full = true, reason = 'admin' })
        else
            TriggerClientEvent('nza:revived', id, { full = true, reason = 'admin' })
        end
        if id ~= src then reply(id, NZA.L('core.you_revived'), 'success') end
        reply(src, NZA.L('core.cmd_revived', Core.Name(id)), 'success')
    end)

    register('heal', NZA.L('core.cmd_heal_help'), { pId }, function(src, args)
        local id = targetOf(src, args[1])
        if not id then return reply(src, NZA.L('core.cmd_no_target'), 'error') end
        local p = patientOf(id)
        if not p then return reply(src, NZA.L('core.cmd_not_loaded'), 'error') end
        if p.state ~= 'alive' then
            P.Revive(p, { full = true, reason = 'admin' })
        else
            P.Heal(p, 100)
            p.blood, p.fluid, p.pain = p.bloodMax, 0, 0
            p.meds = {}
            P.Touch(p, true)
        end
        if id ~= src then reply(id, NZA.L('core.you_healed'), 'success') end
        reply(src, NZA.L('core.cmd_healed', Core.Name(id)), 'success')
    end)

    register('injure', NZA.L('core.cmd_injure_help'), {
        pId,
        { name = 'region', help = NZA.L('core.cmd_param_region') },
        { name = 'type', help = NZA.L('core.cmd_param_type') },
        { name = 'severity', help = NZA.L('core.cmd_param_severity') },
    }, function(src, args)
        local i, id = 1, nil
        if tonumber(args[1]) then
            id = targetOf(src, args[1])
            i = 2
        else
            id = src > 0 and src or nil
        end
        if not id then return reply(src, NZA.L('core.cmd_no_target'), 'error') end
        local p = patientOf(id)
        if not p then return reply(src, NZA.L('core.cmd_not_loaded'), 'error') end

        local region = args[i]
        if not region or region == 'random' then
            region = NZA.Const.Regions[math.random(#NZA.Const.Regions)].name
        end
        if not NZA.Const.Region[region] then
            local names = {}
            for _, r in ipairs(NZA.Const.Regions) do names[#names + 1] = r.name end
            return reply(src, NZA.L('core.cmd_bad_region', table.concat(names, ', ')), 'error')
        end
        local kind = args[i + 1] or 'gunshot'
        if not NZA.Const.InjuryTypes[kind] then
            return reply(src, NZA.L('core.cmd_bad_type', table.concat(NZA.Const.InjuryOrder, ', ')), 'error')
        end
        local sev = math.max(1, math.min(4, math.floor(tonumber(args[i + 2]) or 2)))
        local inj = P.AddInjury(p, { region = region, type = kind, severity = sev, cause = 'admin' })
        if not inj then return reply(src, NZA.L('core.err_failed'), 'error') end
        reply(src, NZA.L('core.cmd_injured', Core.Name(id), NZA.Util.InjuryLabel(kind), NZA.Util.RegionLabel(region), sev), 'success')
    end)

    register('kill', NZA.L('core.cmd_kill_help'), {
        pId, { name = 'arrest', help = NZA.L('core.cmd_param_arrest') },
    }, function(src, args)
        local id = targetOf(src, args[1])
        if not id then return reply(src, NZA.L('core.cmd_no_target'), 'error') end
        local p = patientOf(id)
        if not p then return reply(src, NZA.L('core.cmd_not_loaded'), 'error') end
        local to = (args[2] == 'arrest') and 'arrest' or 'dead'
        if not next(p.injuries) then P.AddInjury(p, { region = 'chest', type = 'contusion', severity = 3, cause = 'admin' }) end
        P.SetState(p, to, 'admin')
        reply(src, NZA.L('core.cmd_killed', Core.Name(id)), 'success')
    end)
end

NZA.Bus.On('player:loaded', function(src)
    SetTimeout(2000, function() if Core.Online(src) then sendSuggestions(src) end end)
end)

CreateThread(function()
    Wait(0)
    registerAll()
    Wait(4000)
    for _, id in ipairs(GetPlayers()) do sendSuggestions(tonumber(id)) end
end)
