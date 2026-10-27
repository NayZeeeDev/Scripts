--[[
    NAYZEEE RADIO - Client core: props & animations (NZR.Props, NZR.Anim)

    Every prop this resource creates is local (non-networked) unless asked otherwise:
    radios in hands, the pressable parts of a raised radio and the jammers are drawn
    by each client from state bags / GlobalState.

      NZR.Props.Load(model, timeout?) → hash | nil
          model = name or hash. Checks IsModelInCdimage / IsModelValid first (a missing
          props resource gives nil at once instead of a 5 s wait), then lib.requestModel
          in a pcall. The model stays requested: NZR.Props.Release(model) when done.
      NZR.Props.Release(model)
      NZR.Props.Spawn(model, where, opts) → entity (0 on failure), netId|nil
          where  vector3 / vector4 / { x, y, z, w } coords
                 or { attach = { entity, bone, pos = vec3, rot = vec3, collision, fixedRot = true,
                                 rotOrder = 2, soft = false } }   bone = index, ped bone id or name
          opts   { group = 'default', networked = false, frozen = true, collision = true,
                   heading, rot = vec3, ground = false, alpha, timeout = 5000, invincible = true,
                   fallback = 'prop_name' (used when the model is missing), keepModel = false }
          (network / freeze are accepted as aliases of networked / frozen.)
          A model that was not loaded before Spawn is released again right after; one
          you preloaded with Load stays loaded.
      NZR.Props.Delete(entity)   NZR.Props.Clear(group)   NZR.Props.Group(group) → { entity, ... }
      Every prop spawned here is deleted when the resource stops.

      NZR.Anim.Play(ped, dict, clip, opts) → ok, token
          opts { flag = 1, blendIn = 8.0, blendOut = -8.0, duration = -1, rate = 0.0,
                 wait = false (block until the clip finished), scenario = 'NAME' (instead of dict),
                 prop = { model, bone, pos, rot } (attached for the anim, removed on Stop) }
      NZR.Anim.Stop(ped, opts)   stop what Play started (opts.immediate = snap,
                                 opts.token = only if that Play is still the current anim)
      NZR.Anim.Current(ped)      → { dict, clip, scenario, token, duration (ms) } | nil
]]

if not NAYZEEE_LOCK_OK then return end

NZR.Props = NZR.Props or {}
NZR.Anim = NZR.Anim or {}
local Props = NZR.Props
local Anim = NZR.Anim

local groups = {}       -- [group] = { [entity] = true }
local owner = {}        -- [entity] = group

-- ════════════════════════════════════════════════════════════════════════
-- MODELS
-- ════════════════════════════════════════════════════════════════════════

local function hashOf(model)
    if type(model) == 'number' then return model end
    if type(model) == 'string' and model ~= '' then return GetHashKey(model) end
    return nil
end

function Props.Load(model, timeout)
    local hash = hashOf(model)
    if not hash then return nil end
    if not IsModelInCdimage(hash) and not IsModelValid(hash) then return nil end
    if HasModelLoaded(hash) then return hash end
    local ok = pcall(lib.requestModel, hash, timeout or 5000)
    if ok and HasModelLoaded(hash) then return hash end
    return nil
end

function Props.Release(model)
    local hash = hashOf(model)
    if hash then SetModelAsNoLongerNeeded(hash) end
end

-- → loaded hash or nil (tries opts.fallback when the custom model is missing)
local function loadWithFallback(model, fallback, timeout)
    local hash = Props.Load(model, timeout)
    if hash then return hash end
    if fallback then
        NZR.Debug('prop fallback', tostring(model), '→', tostring(fallback))
        hash = Props.Load(fallback, timeout)
        if hash then return hash end
    end
    NZR.Warn(('prop model "%s" could not be loaded'):format(tostring(model)))
    return nil
end

local function toVec3(v)
    local t = type(v)
    if t == 'vector3' then return v end
    if t == 'vector4' then return vector3(v.x, v.y, v.z) end
    if t == 'table' then
        local x, y, z = tonumber(v.x or v[1]), tonumber(v.y or v[2]), tonumber(v.z or v[3])
        if x and y then return vector3(x + 0.0, y + 0.0, (z or 0.0) + 0.0) end
    end
    return vector3(0.0, 0.0, 0.0)
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

local function opt(opts, name, alias, default)
    local v = opts[name]
    if v == nil then v = opts[alias] end
    if v == nil then return default end
    return v
end

function Props.Spawn(model, where, opts)
    opts = opts or {}
    local requested = hashOf(model)
    local preloaded = requested and HasModelLoaded(requested)
    local hash = loadWithFallback(model, opts.fallback, opts.timeout)
    if not hash then return 0, nil end
    local release = not opts.keepModel and not (preloaded and hash == requested)

    local network = opt(opts, 'networked', 'network', false) == true
    local attach = type(where) == 'table' and where.attach or nil
    local pos, heading
    if attach then
        if not attach.entity or not DoesEntityExist(attach.entity) then
            if release then SetModelAsNoLongerNeeded(hash) end
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
    if release then SetModelAsNoLongerNeeded(hash) end
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
            false, attach.soft == true, attach.collision == true, IsEntityAPed(ent), tonumber(attach.rotOrder) or 2,
            attach.fixedRot ~= false)
    else
        if opts.rot then
            local r = toVec3(opts.rot)
            SetEntityRotation(obj, r.x, r.y, r.z, 2, true)
        else
            SetEntityHeading(obj, heading)
        end
        if opts.ground then PlaceObjectOnGroundProperly(obj) end
        FreezeEntityPosition(obj, opt(opts, 'frozen', 'freeze', true) ~= false)
    end

    local collision = opts.collision ~= false
    if not attach then SetEntityCollision(obj, collision, collision) end
    if opts.alpha then SetEntityAlpha(obj, math.floor(tonumber(opts.alpha) or 255), false) end
    if opts.invincible ~= false then SetEntityInvincible(obj, true) end
    SetEntityAsMissionEntity(obj, true, true)
    track(obj, opts.group)

    local netId = nil
    if network and NetworkGetEntityIsNetworked(obj) then netId = NetworkGetNetworkIdFromEntity(obj) end
    return obj, netId
end

local function destroy(entity)
    if not DoesEntityExist(entity) then return end
    if IsEntityAttached(entity) then DetachEntity(entity, false, false) end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    if DoesEntityExist(entity) then DeleteObject(entity) end
end

function Props.Delete(entity)
    if not entity or entity == 0 then return end
    local group = owner[entity]
    if group and groups[group] then groups[group][entity] = nil end
    owner[entity] = nil
    destroy(entity)
end

function Props.Clear(group)
    local list = groups[group]
    if not list then return end
    groups[group] = nil
    for entity in pairs(list) do
        owner[entity] = nil
        destroy(entity)
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

local playing = {}   -- [ped] = { dict, clip, scenario, token, duration }
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
            NZR.Debug('anim dict missing', dict)
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
        } }, { group = animGroup(ped), collision = false, fallback = opts.prop.fallback })
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

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= NZR.Resource then return end
    for group in pairs(groups) do Props.Clear(group) end
    for ped, cur in pairs(playing) do
        if DoesEntityExist(ped) and cur.dict then StopAnimTask(ped, cur.dict, cur.clip, 1.0) end
    end
end)
