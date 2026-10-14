--[[
    NAYZEEE AMBULANCE - Server exports & drop-in compatibility

    exports['nayzeee-ambulance']:
      GetPatient(src)                        → medic snapshot | nil
      GetPatientByPid(pid)                   → medic snapshot | nil
      IsDowned(src)                          → true while wounded, in arrest or dead
      IsDead(src)                            → true in cardiac arrest or dead (clinically dead)
      GetState(src)                          → 'alive'|'wounded'|'arrest'|'dead'|nil
      Revive(src, full)                      → bool   (full = heal everything; else back up, injuries patched)
      Heal(src)                              → bool   (remove injuries; revives if down)
      AddInjury(src, region, type, severity) → injury id | nil
      GetVitals(src)                         → vitals table | nil
      GetInjuries(src)                       → injuries array (medic detail) | nil
      CreateNPCPatient(opts)                 → pid | nil   (opts as NZA.Patients.CreateNPC)
      GetTriage(src)                         → 1|2|3, label, colour
      SetPatientMeta(pid, key, value)        → value   (for other resources: carried, stretcher ...)

    Compatibility server events (other scripts keep working):
      hospital:server:RevivePlayer (target)        qb-ambulancejob      admin or medic on duty
      hospital:server:SetLaststandStatus / SetDeathStatus / SetArmor   accepted, ignored (core owns state)
      esx_ambulancejob:revive (target)             esx_ambulancejob     admin only
      esx_ambulancejob:heal (target, type)         esx_ambulancejob     admin or medic on duty
      wasabi_ambulance:revive / wasabi_ambulance:revivePlayer (target)  admin or medic on duty
      Events triggered by another SERVER resource (no player source) are trusted.
    Client-side compatibility events are core-client's job.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Core = NZA.Core or {}
NZA.Patients = NZA.Patients or {}
local Core = NZA.Core
local P = NZA.Patients

local function bySrc(src)
    src = tonumber(src)
    if not src then return nil end
    return P.GetBySource(src)
end

exports('GetPatient', function(src)
    local p = bySrc(src)
    return p and P.Snapshot(p, 'medic') or nil
end)

exports('GetPatientByPid', function(pid)
    local p = P.Get(pid)
    return p and P.Snapshot(p, 'medic') or nil
end)

exports('IsDowned', function(src)
    local p = bySrc(src)
    return p ~= nil and p.state ~= 'alive'
end)

exports('IsDead', function(src)
    local p = bySrc(src)
    return p ~= nil and (p.state == 'arrest' or p.state == 'dead')
end)

exports('GetState', function(src)
    local p = bySrc(src)
    return p and p.state or nil
end)

local function revive(src, full, reason)
    local p = bySrc(src)
    if p then
        return P.Revive(p, { full = full == true, reason = reason or 'export' })
    end
    src = tonumber(src)
    if not src or not Core.Online(src) then return false end
    -- record not loaded yet: loading awaits the database, which must not happen inside an
    -- export call from another resource, so load + revive in our own thread
    CreateThread(function()
        local loaded = P.LoadPlayer(src)
        if loaded then
            P.Revive(loaded, { full = full == true, reason = reason or 'export' })
        elseif Core.Online(src) then
            TriggerClientEvent('nza:revived', src, { full = full == true, reason = reason })
        end
    end)
    return true
end

local function heal(src)
    local p = bySrc(src)
    if not p then return false end
    if p.state ~= 'alive' then return P.Revive(p, { full = true, reason = 'export' }) end
    P.Heal(p, 100)
    p.blood, p.fluid, p.pain = p.bloodMax, 0, 0
    P.Touch(p, true)
    return true
end

exports('Revive', function(src, full) return revive(src, full ~= false and full ~= nil, 'export') end)
exports('Heal', heal)

exports('AddInjury', function(src, region, kind, severity)
    local p = bySrc(src)
    if not p then return nil end
    local inj = P.AddInjury(p, { region = region, type = kind or 'contusion', severity = tonumber(severity) or 2, cause = 'export' })
    return inj and inj.id or nil
end)

exports('GetVitals', function(src)
    local p = bySrc(src)
    return p and NZA.Util.deepcopy(p.vitals) or nil
end)

exports('GetInjuries', function(src)
    local p = bySrc(src)
    if not p then return nil end
    return P.Snapshot(p, 'medic').injuries
end)

exports('CreateNPCPatient', function(opts)
    local p = P.CreateNPC(opts)
    return p and p.pid or nil
end)

exports('GetTriage', function(src)
    local p = bySrc(src)
    if not p then return nil end
    return P.Triage(p)
end)

exports('SetPatientMeta', function(pid, key, value)
    return P.SetMeta(pid, key, value)
end)

-- ════════════════════════════════════════════════════════════════════════
-- COMPATIBILITY EVENTS
-- ════════════════════════════════════════════════════════════════════════

local function medicOnDuty(src)
    local rec = NZA.Staff.Get(src)
    return rec ~= nil and rec.medic and (rec.onDuty or (Config.Jobs and Config.Jobs.requireDuty == false))
end

-- caller allowed? server resources (no source) always; players: admin, or (medicOk and medic on duty)
local function allowed(src, medicOk)
    if Core.IsLocalSource(src) then return true end
    src = tonumber(src)
    if Core.IsAdmin(src) then return true end
    if medicOk and medicOnDuty(src) then return true end
    NZA.Warn(('blocked compatibility revive from %s (not admin%s)'):format(tostring(src), medicOk and '/medic' or ''))
    return false
end

local function nearEnough(src, target)
    if Core.IsLocalSource(src) or Core.IsAdmin(tonumber(src)) then return true end
    local a, b = Core.SrcCoords(tonumber(src)), Core.SrcCoords(target)
    return a ~= nil and b ~= nil and #(a - b) <= 10.0
end

local function compatRevive(src, target, medicOk, full)
    if not allowed(src, medicOk) then return end
    target = tonumber(target) or tonumber(src)
    if not target or not Core.Online(target) then return end
    if not nearEnough(src, target) then return end
    revive(target, full, 'compat')
end

RegisterNetEvent('hospital:server:RevivePlayer', function(target)
    compatRevive(source, target, true, true)
end)

RegisterNetEvent('esx_ambulancejob:revive', function(target)
    compatRevive(source, target, false, true)
end)

RegisterNetEvent('esx_ambulancejob:heal', function(target)
    local src = source
    if not allowed(src, true) then return end
    target = tonumber(target)
    if target and Core.Online(target) and nearEnough(src, target) then heal(target) end
end)

RegisterNetEvent('wasabi_ambulance:revive', function(target)
    compatRevive(source, target, true, true)
end)

RegisterNetEvent('wasabi_ambulance:revivePlayer', function(target)
    compatRevive(source, target, true, true)
end)

-- qb clients report their own laststand/death; our core owns the state, so accept & ignore
RegisterNetEvent('hospital:server:SetLaststandStatus', function() end)
RegisterNetEvent('hospital:server:SetDeathStatus', function() end)
RegisterNetEvent('hospital:server:SetArmor', function() end)
