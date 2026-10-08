-- Small client helpers: animations, reactions, props, ped lookups

function PlayAnim(a, duration, ped)
    if not a or not a.dict then return false end
    ped = ped or PlayerPedId()
    if not pcall(lib.requestAnimDict, a.dict, 1500) then return false end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, duration or a.duration or -1, a.flag or 0, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
    return true
end

-- looped upper-body animation that keeps going until cleared
function LoopAnim(a, ped)
    if not a or not a.dict then return false end
    ped = ped or PlayerPedId()
    if not pcall(lib.requestAnimDict, a.dict, 1500) then return false end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, -1, (a.flag or 49) | 1, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
    return true
end

-- a random reaction from Config.Reactions[kind]
function Reaction(kind, delay)
    local R = Config.Reactions
    if not R.Enabled then return end
    local list = R[kind]
    if not list or #list == 0 then return end
    local a = list[math.random(1, #list)]
    SetTimeout(delay or 0, function()
        local ped = PlayerPedId()
        if IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end
        if LocalPlayer.state[ST.tied] or LocalPlayer.state[ST.held] then return end
        PlayAnim({ dict = a.dict, clip = a.clip, flag = a.flag or 48 }, a.duration or 2000)
    end)
end

RegisterNetEvent('nz-wig:c:react', function(kind, delay) Reaction(kind, delay) end)

function PedOf(serverId)
    local p = GetPlayerFromServerId(serverId)
    if p == -1 then return 0 end
    return GetPlayerPed(p)
end

function ServerIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

function FaceEntity(ped, target)
    local a, b = GetEntityCoords(ped), GetEntityCoords(target)
    SetEntityHeading(ped, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
end

-- attach a prop to a ped bone, returns the object (or nil)
function AttachProp(p, ped)
    if not p or not p.model then return nil end
    ped = ped or PlayerPedId()
    if not IsModelInCdimage(p.model) or not pcall(lib.requestModel, p.model, 1500) then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(p.model, c.x, c.y, c.z + 0.2, true, true, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, p.bone or 57005), p.pos.x, p.pos.y, p.pos.z, p.rot.x, p.rot.y, p.rot.z,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(p.model)
    return obj
end

function DeleteProp(obj)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
    return nil
end

-- is `me` behind `target` (within the blindside angle)?
function IsBehind(me, target, angle)
    local mc, tc = GetEntityCoords(me), GetEntityCoords(target)
    local h = math.rad(GetEntityHeading(target))
    local fx, fy = -math.sin(h), math.cos(h)
    local dx, dy = mc.x - tc.x, mc.y - tc.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return false end
    local dot = (fx * dx + fy * dy) / len
    return math.deg(math.acos(Clamp(dot, -1, 1))) >= 180 - (angle or 70)
end

-- closest player roughly in front of us
function ClosestInFront(range)
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local fwd = GetEntityForwardVector(me)
    local best, bestD
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me then
            local c = GetEntityCoords(ped)
            local d = #(c - mc)
            if d <= range then
                local dir = (c - mc) / math.max(d, 0.001)
                if (dir.x * fwd.x + dir.y * fwd.y) > 0.2 and (not bestD or d < bestD) then best, bestD = ped, d end
            end
        end
    end
    return best
end

-- a timed action with a progress bar that the player can't cancel by walking off
function TimedAction(label, duration, anim)
    local me = PlayerPedId()
    if anim then LoopAnim(anim, me) end
    NUI.Send('progress', { label = label, duration = duration })
    Wait(duration)
    if anim then ClearPedSecondaryTask(me) end
end
