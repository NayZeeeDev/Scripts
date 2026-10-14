--[[
    NAYZEEE AMBULANCE - Client core: props & animations (NZA.Props, NZA.Anim)

      NZA.Props.Spawn(model, where, opts) → entity (0 on failure), netId|nil
          model  Config.Props key ('ivstand') or a model name / hash
          where  vector3 / vector4 / { x, y, z, w } coords
                 or { attach = { entity, bone, pos = vec3, rot = vec3, collision, fixedRot } }
          opts   { group = 'default', network = false, freeze = true, collision = true,
                   heading, rot = vec3, fallbackKey, ground = false, alpha, timeout = 5000,
                   invincible = true }
          The custom model is loaded with a timeout; when it is missing the native model in
          Config.PropFallbacks[fallbackKey] (or [model key]) is used instead.
      NZA.Props.Delete(entity)   NZA.Props.Clear(group)   NZA.Props.Group(group) → { entity, ... }
      NZA.Props.Resolve(model)   → modelName, fallbackKey
      Every prop spawned here is deleted when the resource stops.

      NZA.Anim.Play(ped, dict, clip, opts) → bool
          opts { flag = 1, blendIn = 8.0, blendOut = -8.0, duration = -1, rate = 0.0,
                 wait = false (block until the clip finished), scenario = 'NAME' (instead of dict),
                 prop = { model, bone, pos, rot } (attached for the anim, removed on Stop) }
      NZA.Anim.Stop(ped, opts)   stop what Play/Kneel started (opts.immediate = snap,
                                 opts.token = only if that Play is still the current anim)
      NZA.Anim.Current(ped)      → { dict, clip, scenario, token, duration (ms) } | nil
      NZA.Anim.Kneel lives in proc.lua.
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Props = NZA.Props or {}
NZA.Anim = NZA.Anim or {}
local Props = NZA.Props
local Anim = NZA.Anim

local groups = {}       -- [group] = { [entity] = true }
local owner = {}        -- [entity] = group
local reverseKey = nil  -- [modelName] = Config.Props key

-- ════════════════════════════════════════════════════════════════════════
-- MODELS
-- ════════════════════════════════════════════════════════════════════════

local function buildReverse()
    reverseKey = {}
    for k, v in pairs(Config.Props or {}) do
        if type(v) == 'string' then reverseKey[v] = k end
    end
end

function Props.Resolve(model)
    if type(model) == 'number' then return model, nil end
    if type(model) ~= 'string' then return nil, nil end
    if Config.Props and Config.Props[model] then return Config.Props[model], model end
    if not reverseKey then buildReverse() end
    return model, reverseKey[model]
end

local function loadModel(model, timeout)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) and not IsModelValid(hash) then return nil end
    local ok = pcall(lib.requestModel, hash, timeout or 5000)
    if ok and HasModelLoaded(hash) then return hash end
    return nil
end

-- → loaded hash or nil (tries the fallback model when the custom one is missing)
local function loadWithFallback(model, fallbackKey, timeout)
    local name, key = Props.Resolve(model)
    if not name then return nil end
    local hash = loadModel(name, timeout)
    if hash then return hash end
    key = fallbackKey or key
    local fb = key and Config.PropFallbacks and Config.PropFallbacks[key]
    if fb then
        NZA.Debug('prop fallback', tostring(name), '→', fb)
        return loadModel(fb, timeout)
    end
    NZA.Warn(('prop model "%s" could not be loaded'):format(tostring(name)))
    return nil
end

local function toVec3(v)
    if v == nil then return vector3(0.0, 0.0, 0.0) end
    return NZA.Util.vec(v) or vector3(0.0, 0.0, 0.0)
end

local function track(entity, group)
    group = group or 'default'
    groups[group] = groups[group] or {}
    groups[group][entity] = true
    owner[entity] = group
end

-- ════════════════════════════════════════════════════════════════════════
-- SPAWN / DELETE
-- ════════════════════════════════════════════════════════════════════════

function Props.Spawn(model, where, opts)
    opts = opts or {}
    local hash = loadWithFallback(model, opts.fallbackKey, opts.timeout)
    if not hash then return 0, nil end

    local network = opts.network == true
    local attach = type(where) == 'table' and where.attach or nil
    local pos, heading
    if attach then
        if not attach.entity or not DoesEntityExist(attach.entity) then
            SetModelAsNoLongerNeeded(hash)
            return 0, nil
        end
        pos = GetEntityCoords(attach.entity)
        heading = 0.0
    else
        pos = toVec3(where)
        heading = opts.heading
        if heading == nil and type(where) == 'vector4' then heading = where.w end
        if heading == nil and type(where) == 'table' then heading = where.w or where.h or where[4] end
        heading = tonumber(heading) or 0.0
    end

    local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, network, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return 0, nil end

    if attach then
        local ent = attach.entity
        local bone = attach.bone
        local boneIndex = 0
        if type(bone) == 'string' then
            boneIndex = GetEntityBoneIndexByName(ent, bone)
        elseif bone then
            boneIndex = IsEntityAPed(ent) and GetPedBoneIndex(ent, bone) or bone
        end
        local p, r = toVec3(attach.pos), toVec3(attach.rot)
        AttachEntityToEntity(obj, ent, boneIndex, p.x, p.y, p.z, r.x, r.y, r.z,
            false, false, attach.collision == true, IsEntityAPed(ent), 2, attach.fixedRot ~= false)
    else
        if opts.rot then
            local r = toVec3(opts.rot)
            SetEntityRotation(obj, r.x, r.y, r.z, 2, true)
        else
            SetEntityHeading(obj, heading)
        end
        if opts.ground then PlaceObjectOnGroundProperly(obj) end
        FreezeEntityPosition(obj, opts.freeze ~= false)
    end

    local collision = opts.collision ~= false
    if not attach then SetEntityCollision(obj, collision, collision) end
    if opts.alpha then SetEntityAlpha(obj, opts.alpha, false) end
    if opts.invincible ~= false then SetEntityInvincible(obj, true) end
    SetEntityAsMissionEntity(obj, true, true)
    track(obj, opts.group)

    local netId = nil
    if network and NetworkGetEntityIsNetworked(obj) then netId = NetworkGetNetworkIdFromEntity(obj) end
    return obj, netId
end

function Props.Delete(entity)
    if not entity or entity == 0 then return end
    local group = owner[entity]
    if group and groups[group] then groups[group][entity] = nil end
    owner[entity] = nil
    if DoesEntityExist(entity) then
        if IsEntityAttached(entity) then DetachEntity(entity, false, false) end
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        if DoesEntityExist(entity) then DeleteObject(entity) end
    end
end

function Props.Clear(group)
    local list = groups[group]
    if not list then return end
    groups[group] = nil
    for entity in pairs(list) do
        owner[entity] = nil
        if DoesEntityExist(entity) then
            if IsEntityAttached(entity) then DetachEntity(entity, false, false) end
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end
end

function Props.Group(group)
    local out = {}
    for entity in pairs(groups[group] or {}) do
        if DoesEntityExist(entity) then out[#out + 1] = entity end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- ANIMATIONS
-- ════════════════════════════════════════════════════════════════════════

local playing = {}   -- [ped] = { dict, clip, scenario, group, token }
local animToken = 0

local function animGroup(ped)
    return 'anim:' .. tostring(ped)
end

function Anim.Play(ped, dict, clip, opts)
    ped = ped or PlayerPedId()
    opts = opts or {}
    if not DoesEntityExist(ped) then return false end
    animToken = animToken + 1
    local token = animToken

    -- previous helper props of this ped go away with the previous anim
    Props.Clear(animGroup(ped))

    if opts.scenario then
        TaskStartScenarioInPlace(ped, opts.scenario, 0, opts.enter ~= false)
        playing[ped] = { scenario = opts.scenario, token = token }
    else
        local ok = pcall(lib.requestAnimDict, dict, opts.timeout or 3000)
        if not ok or not HasAnimDictLoaded(dict) then
            NZA.Debug('anim dict missing', dict)
            return false
        end
        local clipMs = math.floor(GetAnimDuration(dict, clip) * 1000)   -- read while the dict is loaded
        TaskPlayAnim(ped, dict, clip, opts.blendIn or 8.0, opts.blendOut or -8.0, opts.duration or -1,
            opts.flag or 1, opts.rate or 0.0, false, false, false)
        RemoveAnimDict(dict)
        playing[ped] = { dict = dict, clip = clip, token = token, duration = clipMs }
    end

    if type(opts.prop) == 'table' and opts.prop.model then
        Props.Spawn(opts.prop.model, { attach = {
            entity = ped, bone = opts.prop.bone or 57005, pos = opts.prop.pos, rot = opts.prop.rot,
        } }, { group = animGroup(ped), collision = false, fallbackKey = opts.prop.fallbackKey })
    end

    if opts.wait and not opts.scenario then
        local ms = opts.duration
        if not ms or ms < 0 then ms = playing[ped] and playing[ped].duration or 0 end
        local started = GetGameTimer()
        Wait(100)
        while GetGameTimer() - started < ms and IsEntityPlayingAnim(ped, dict, clip, 3) do Wait(50) end
    end
    return true, token
end

-- token = value returned by Play; when given, only stops if that anim is still the current one
function Anim.Stop(ped, opts)
    ped = ped or PlayerPedId()
    opts = opts or {}
    local cur = playing[ped]
    if opts.token and (not cur or cur.token ~= opts.token) then return false end
    playing[ped] = nil
    Props.Clear(animGroup(ped))
    if not DoesEntityExist(ped) then return true end
    if cur and cur.exit and not opts.immediate then
        -- e.g. kneel → stand up properly
        local ok = pcall(lib.requestAnimDict, cur.exit[1], 2000)
        if ok then
            if cur.dict then StopAnimTask(ped, cur.dict, cur.clip, 2.0) end
            TaskPlayAnim(ped, cur.exit[1], cur.exit[2], 4.0, -4.0, -1, 0, 0.0, false, false, false)
            RemoveAnimDict(cur.exit[1])
            return true
        end
    end
    if opts.immediate then
        ClearPedTasksImmediately(ped)
    elseif cur and cur.dict then
        StopAnimTask(ped, cur.dict, cur.clip, 2.0)
    else
        ClearPedTasks(ped)
    end
    return true
end

function Anim.Current(ped)
    return playing[ped or PlayerPedId()]
end

-- internal: lets Kneel mark an exit clip for Stop
function Anim._SetExit(ped, token, dict, clip)
    local cur = playing[ped]
    if cur and cur.token == token then cur.exit = { dict, clip } end
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    for group in pairs(groups) do Props.Clear(group) end
    for ped, cur in pairs(playing) do
        if DoesEntityExist(ped) and cur.dict then StopAnimTask(ped, cur.dict, cur.clip, 1.0) end
    end
end)
