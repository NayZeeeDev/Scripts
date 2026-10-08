--[[ Local (non-networked) props. Loot props only exist on crew clients while they are near. ]]

Props = { list = {} }

local function load(model)
    model = type(model) == 'string' and joaat(model) or model
    if not IsModelValid(model) then
        Utils.debug('invalid model', model)
        return nil
    end
    lib.requestModel(model, 10000)
    return model
end

---@param key string unique key (node id)
function Props.spawn(key, model, coords, heading, opts)
    Props.delete(key)
    local hash = load(model)
    if not hash then return nil end
    opts = opts or {}
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(obj, heading or 0.0)
    if opts.rotation then SetEntityRotation(obj, opts.rotation.x, opts.rotation.y, opts.rotation.z, 2, true) end
    if opts.ground then PlaceObjectOnGroundProperly(obj) end
    FreezeEntityPosition(obj, opts.freeze ~= false)
    SetEntityCollision(obj, opts.collision ~= false, true)
    SetEntityInvincible(obj, true)
    SetModelAsNoLongerNeeded(hash)
    Props.list[key] = obj
    return obj
end

function Props.get(key)
    local e = Props.list[key]
    if e and DoesEntityExist(e) then return e end
    return nil
end

function Props.delete(key)
    local e = Props.list[key]
    if e and DoesEntityExist(e) then DeleteEntity(e) end
    Props.list[key] = nil
end

--- replace a prop's model in place (full trolley -> empty trolley)
function Props.swap(key, model)
    local e = Props.get(key)
    if not e then return nil end
    local c, r = GetEntityCoords(e), GetEntityRotation(e, 2)
    local spawned = Props.spawn(key, model, c, 0.0, { rotation = r })
    return spawned
end

function Props.clear()
    for key in pairs(Props.list) do Props.delete(key) end
end

--- attach a temporary prop to a ped bone (tools during animations)
function Props.attach(ped, model, bone, pos, rot)
    local hash = load(model)
    if not hash then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, bone or 57005),
        (pos and pos.x or 0.0), (pos and pos.y or 0.0), (pos and pos.z or 0.0),
        (rot and rot.x or 0.0), (rot and rot.y or 0.0), (rot and rot.z or 0.0),
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

AddEventHandler('onResourceStop', function(res)
    if res == RES then Props.clear() end
end)
