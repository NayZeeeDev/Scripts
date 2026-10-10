--[[ Client helpers — props, animations, ped alignment, access ]]

U = {}
U.busy = false

function U.myId() return GetPlayerServerId(PlayerId()) end
function U.now() return GetCloudTimeAsInt() end

function U.hash(model)
    return type(model) == 'number' and model or joaat(model)
end

function U.spawnProp(model, pos, heading, opts)
    opts = opts or {}
    local hash = U.hash(model)
    if not IsModelInCdimage(hash) then
        NZ.dbg('missing model', model)
        return nil
    end
    lib.requestModel(hash, 10000)
    local ent = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ent, heading or 0.0)
    FreezeEntityPosition(ent, true)
    if opts.noCollision then
        SetEntityCollision(ent, false, false)
        SetEntityCompletelyDisableCollision(ent, true, true) -- same flags as the prop author's reference
    end
    if opts.invisible then SetEntityVisible(ent, false, false) end
    SetEntityInvincible(ent, true)
    SetModelAsNoLongerNeeded(hash)
    return ent
end

function U.deleteEnt(ent)
    if ent and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

function U.playPed(anim, flag, duration)
    lib.requestAnimDict(anim.dict, 5000)
    TaskPlayAnim(PlayerPedId(), anim.dict, anim.clip, 8.0, -8.0, duration or -1, flag or 48, 0, false, false, false)
end

function U.animMs(anim, fallback)
    lib.requestAnimDict(anim.dict, 5000)
    local d = GetAnimDuration(anim.dict, anim.clip)
    if not d or d <= 0 then return fallback or 2000 end
    return math.floor(d * 1000)
end

function U.stopPed()
    ClearPedTasks(PlayerPedId())
end

-- world position from a station pivot + a local offset (vec3/vec4)
function U.offset(d, off)
    local h = math.rad(d.h)
    local c, s = math.cos(h), math.sin(h)
    local x = d.x + off.x * c - off.y * s
    local y = d.y + off.x * s + off.y * c
    return vec3(x, y, d.z + (off.z or 0.0))
end

-- walk the ped to an offset next to the machine and face the right way
function U.alignPed(d, off)
    local ped = PlayerPedId()
    local target = U.offset(d, off)
    local heading = (d.h + (off.w or 0.0)) % 360.0
    if #(GetEntityCoords(ped) - target) > 0.25 then
        TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, 3000, heading, 0.05)
        local t = GetGameTimer() + 3000
        while GetGameTimer() < t and #(GetEntityCoords(ped).xy - target.xy) > 0.2 do Wait(50) end
    end
    SetEntityCoords(ped, target.x, target.y, target.z, false, false, false, false)
    SetEntityHeading(ped, heading)
    Wait(50)
end

function U.faceCoords(pos)
    TaskTurnPedToFaceCoord(PlayerPedId(), pos.x, pos.y, pos.z, 800)
    Wait(800)
end

-- client-side mirror of Stations.hasAccess (server re-checks everything)
function U.hasAccess(d)
    if not d then return false end
    if d.placed then
        if d.owner and d.owner == CBridge.getIdentifier() then return true end
        if d.share then
            local kind, name = d.share:match('^(%a+):(.+)$')
            if kind == 'gang' then
                local g = CBridge.getGang()
                return g ~= nil and g.name == name
            elseif kind == 'job' then
                return CBridge.getJob().name == name
            elseif kind == 'facility' then
                local unit = LocalPlayer.state.nzmwUnit
                return unit ~= nil and tostring(unit.id) == name and (unit.role == 'owner' or unit.role == 'member')
            end
        end
        return false
    end
    local acc = d.access
    if not acc or (not acc.jobs and not acc.gangs and not acc.items) then return true end
    if acc.jobs then
        local j = CBridge.getJob()
        if acc.jobs[j.name] and j.grade >= acc.jobs[j.name] then return true end
    end
    if acc.gangs then
        local g = CBridge.getGang()
        if g and acc.gangs[g.name] and g.grade >= acc.gangs[g.name] then return true end
    end
    if acc.items then
        for _, item in ipairs(acc.items) do
            if CBridge.hasItem(item) then return true end
        end
    end
    return false
end

function U.lockMine(d)
    if not d.user or d.user == U.myId() then return true end
    return d.lockUntil ~= nil and U.now() > d.lockUntil
end

-- run an interaction once at a time
function U.run(fn)
    if U.busy then return end
    U.busy = true
    local ok, err = pcall(fn)
    U.busy = false
    if not ok then
        print('^1[nz_moneywash] ' .. tostring(err) .. '^7')
        U.stopPed()
    end
end

function U.fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return ('%02d:%02d'):format(math.floor(sec / 60), sec % 60)
end
