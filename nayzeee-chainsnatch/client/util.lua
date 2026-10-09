-----------------------------------------------------------------
-- Client helpers shared by every client file
-----------------------------------------------------------------

Util = {}

local warned = {}

--- Request a model, nil (with one clear console line) if it isn't streaming.
function Util.loadModel(model, quiet)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then
        if not quiet and not warned[hash] then
            warned[hash] = true
            print(('^1[nayzeee-chainsnatch] model "%s" is not registered.^0'):format(tostring(model)))
            print(('^3  - is %s started (ensure it in server.cfg)?^0'):format(Config.PropsResource))
            print('^3  - converted chains: run Build in /chainstudio > Convert^0')
        end
        return nil
    end
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() > timeout then return nil end
    end
    return hash
end

function Util.loadDict(dict)
    if not dict then return false end
    if HasAnimDictLoaded(dict) then return true end
    if not DoesAnimDictExist(dict) then
        if not warned[dict] then
            warned[dict] = true
            print(('^3[nayzeee-chainsnatch] anim dict "%s" does not exist^0'):format(dict))
        end
        return false
    end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 4000
    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeout then return false end
    end
    return true
end

function Util.playAnim(a, duration, flag, ped)
    if not a or not a.dict then return false end
    ped = ped or PlayerPedId()
    if not Util.loadDict(a.dict) then return false end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, duration or a.duration or -1, flag or a.flag or 48, 0.0, false, false, false)
    RemoveAnimDict(a.dict)
    return true
end

--- Spawn a local chain prop (no collision, only this client sees it).
function Util.spawnChain(key, letter, coords)
    local model = Chains.model(key, letter)
    if not model then return nil end
    local hash = Util.loadModel(model)
    if not hash then return nil end
    coords = coords or GetEntityCoords(PlayerPedId())
    local entity = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not entity or entity == 0 then return nil end
    SetEntityCollision(entity, false, false)
    SetEntityCompletelyDisableCollision(entity, false, false)
    SetEntityInvincible(entity, true)
    SetEntityLodDist(entity, 200)
    return entity, hash
end

function Util.attach(entity, ped, bone, pos, rot)
    AttachEntityToEntity(entity, ped, GetPedBoneIndex(ped, bone),
        pos.x, pos.y, pos.z, rot.x, rot.y, rot.z,
        true, true, false, true, 1, true)
end

function Util.delete(entity)
    if entity and DoesEntityExist(entity) then
        if IsEntityAttached(entity) then DetachEntity(entity, true, true) end
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end
end

--- Centre of a model's bounding box, in its own local space (converted chains: ~0,0,0).
function Util.modelCentre(hash)
    local mn, mx = GetModelDimensions(hash)
    return vector3((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, (mn.z + mx.z) * 0.5), mn, mx
end

function Util.isFemale(ped)
    return GetEntityModel(ped or PlayerPedId()) == `mp_f_freemode_01`
end

function Util.pedOf(serverId)
    local p = GetPlayerFromServerId(serverId)
    if p == -1 then return 0 end
    return GetPlayerPed(p)
end

function Util.serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

function Util.face(ped, target)
    local a, b = GetEntityCoords(ped), GetEntityCoords(target)
    SetEntityHeading(ped, GetHeadingFromVector_2d(b.x - a.x, b.y - a.y))
end

--- Closest player roughly in front of us.
function Util.closestInFront(range)
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

--- Direction vector from a camera rotation (degrees).
function Util.rotToDir(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local cx = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cx, math.cos(rz) * cx, math.sin(rx))
end

function Util.wrap180(v)
    v = (v + 180.0) % 360.0
    if v < 0 then v = v + 360.0 end
    return v - 180.0
end

function Util.round(v, dec)
    local m = 10 ^ (dec or 3)
    return math.floor(v * m + 0.5) / m
end

function Util.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

-----------------------------------------------------------------
-- tiny 3x3 matrix kit, columns are axes
-----------------------------------------------------------------

M3 = {}

function M3.fromAxes(r, f, u)
    return { r.x, f.x, u.x,
             r.y, f.y, u.y,
             r.z, f.z, u.z }
end

function M3.mul(a, b)
    local o = {}
    for i = 0, 2 do
        for j = 0, 2 do
            o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
        end
    end
    return o
end

function M3.t(a) return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] } end

function M3.apply(a, v)
    return vector3(
        a[1] * v.x + a[2] * v.y + a[3] * v.z,
        a[4] * v.x + a[5] * v.y + a[6] * v.z,
        a[7] * v.x + a[8] * v.y + a[9] * v.z)
end

function M3.rx(d) local r = math.rad(d); local c, s = math.cos(r), math.sin(r); return { 1,0,0, 0,c,-s, 0,s,c } end
function M3.ry(d) local r = math.rad(d); local c, s = math.cos(r), math.sin(r); return { c,0,s, 0,1,0, -s,0,c } end
function M3.rz(d) local r = math.rad(d); local c, s = math.cos(r), math.sin(r); return { c,-s,0, s,c,0, 0,0,1 } end

--- Rotation of `deg` degrees about a unit axis.
function M3.axis(axis, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    local t = 1 - c
    local x, y, z = axis.x, axis.y, axis.z
    return {
        t*x*x + c,   t*x*y - s*z, t*x*z + s*y,
        t*x*y + s*z, t*y*y + c,   t*y*z - s*x,
        t*x*z - s*y, t*y*z + s*x, t*z*z + c,
    }
end

function M3.err(a, b)
    local e = 0.0
    for i = 1, 9 do local d = a[i] - b[i]; e = e + d * d end
    return e
end

--- GTA's SetEntityRotation(.., 2) order: R = Rz * Ry * Rx (degrees)
function M3.euler(rx, ry, rz) return M3.mul(M3.mul(M3.rz(rz), M3.ry(ry)), M3.rx(rx)) end
