--[[
    NAYZEEE AMBULANCE - Client core: own staff record & permissions

    The server pushes this player's staff record whenever it changes (join, job change,
    duty toggle, department edit). Everything here is a UI-side cache: the server checks
    NZA.Staff.Can() again for every action (ARCHITECTURE §7, §13).

      NZA.Perm(perm)        → bool   may this player use 'perm' (filters menus/targets)
      NZA.Easy(perm)        → bool   easy mode (progress bar instead of minigame) for 'perm'
      NZA.IsMedic()         → bool   framework job is a medic job
      NZA.OnDuty()          → bool
      NZA.Staff.Get()       → record | nil
          { hospital, dept, grade, gradeLabel, perms = { [perm] = true },
            easy = { [perm] = true }, onDuty, medic, admin? }

    Net events handled: nza:staff:update (record)
    Bus events emitted: staff:changed (record)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Staff = NZA.Staff or {}
local Staff = NZA.Staff

local record = nil
local publicPerms = {}
local policePerms = {}

local function toSet(list)
    local out = {}
    if type(list) ~= 'table' then return out end
    for k, v in pairs(list) do
        if type(k) == 'number' then
            out[v] = true
        elseif v then
            out[k] = true
        end
    end
    return out
end

local function buildStatic()
    publicPerms = toSet(Config.PublicPerms)
    policePerms = toSet(Config.PolicePerms)
end
buildStatic()

local function bridgeCall(name)
    if Bridge and type(Bridge[name]) == 'function' then
        local ok, res = pcall(Bridge[name])
        if ok then return res end
    end
    return nil
end

function Staff.Get()
    return record
end

function NZA.IsMedic()
    if record and record.medic ~= nil then return record.medic == true end
    return bridgeCall('IsMedic') == true
end

function NZA.OnDuty()
    if record and record.onDuty ~= nil then return record.onDuty == true end
    local job = bridgeCall('GetJob')
    return type(job) == 'table' and job.onDuty == true
end

function NZA.Perm(perm)
    if perm == nil then return true end
    if publicPerms[perm] then return true end
    if record then
        if record.admin then return true end
        if record.perms and record.perms[perm] then
            -- medics off duty only keep the public perms (server enforces the same)
            if record.medic and Config.Jobs and Config.Jobs.requireDuty and record.onDuty == false then
                return false
            end
            return true
        end
        return false
    end
    -- no record yet: police get their default first-aid set
    if policePerms[perm] and bridgeCall('IsPolice') == true then return true end
    return false
end

function NZA.Easy(perm)
    if record and type(record.easy) == 'table' then
        if perm == nil then
            for _ in pairs(record.easy) do return true end
            return false
        end
        return record.easy[perm] == true
    end
    return Config.EasyMode and Config.EasyMode.default == true or false
end

RegisterNetEvent('nza:staff:update', function(rec)
    if type(rec) ~= 'table' then return end
    rec.perms = toSet(rec.perms)
    if rec.easy ~= nil then rec.easy = toSet(rec.easy) end
    record = rec
    NZA.Bus.Emit('staff:changed', rec)
end)

CreateThread(function()
    Wait(0)
    if Bridge and Bridge.OnJobChanged then
        -- the server pushes a fresh record shortly after; this keeps menus honest meanwhile
        Bridge.OnJobChanged(function(job)
            if record and type(job) == 'table' and job.onDuty ~= nil then
                record.onDuty = job.onDuty == true
            end
            NZA.Bus.Emit('staff:changed', record)
        end)
    end
end)
