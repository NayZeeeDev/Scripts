local T = Config.Tablet
local MODEL = joaat(T.model)
local prop

local function putAway()
    local ped = PlayerPedId()
    StopAnimTask(ped, T.anim.dict, T.anim.clip, 2.0)
    RemoveAnimDict(T.anim.dict)
    if prop then DeleteEntity(prop) prop = nil end
    Trading.busy = false
end

function Trading.UseTablet()
    if Trading.busy or Trading.open then return end
    Trading.busy = true

    local ped = PlayerPedId()
    lib.requestAnimDict(T.anim.dict)
    lib.requestModel(MODEL)

    prop = CreateObject(MODEL, GetEntityCoords(ped), true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, T.bone), T.pos.x, T.pos.y, T.pos.z, T.rot.x, T.rot.y, T.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(MODEL)
    TaskPlayAnim(ped, T.anim.dict, T.anim.clip, 3.0, 3.0, -1, 49, 0, false, false, false)

    if not Trading.Open('tablet', putAway) then putAway() end
end

RegisterNetEvent('nz_trading:client:useTablet', Trading.UseTablet)
exports('useTablet', Trading.UseTablet)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and prop then DeleteEntity(prop) end
end)
