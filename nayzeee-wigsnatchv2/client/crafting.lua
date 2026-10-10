-- Wig making from materials (at a wig table) and the supplier who sells the materials.

local CC, SU = Config.Crafting, Config.Supplier
local textShown = false   -- our [E] prompt is up (ox_lib owns it, so it's hidden on stop)

-- every hairstyle of a model, read off a hidden local ped once and cached -------------------------

local styles = {}

local function readStyles(m)
    if styles[m] then return styles[m] end
    local hash = m == 'm' and Config.Models.male.model or Config.Models.female.model
    if not pcall(lib.requestModel, hash, 5000) then return {} end
    local c = GetEntityCoords(PlayerPedId())
    local ped = CreatePed(4, hash, c.x, c.y, c.z - 50.0, 0.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return {} end
    SetEntityVisible(ped, false, false)
    FreezeEntityPosition(ped, true)
    local out = {}
    for d = 0, GetNumberOfPedDrawableVariations(ped, 2) - 1 do
        if CC.ShortStyles or not IsShortDrawable(m, d) then
            out[#out + 1] = { d = d, n = math.max(1, GetNumberOfPedTextureVariations(ped, 2, d)), name = StyleNameFor(m, d, 0) }
        end
    end
    DeleteEntity(ped)
    styles[m] = out
    return out
end
Crafting = { Styles = readStyles }

-- make it: at the table you're at (or anywhere when wig tables aren't required)
RegisterNUICallback('make', function(d, cb)
    cb(1)
    if type(d) ~= 'table' then return end
    local req = { m = d.m, d = d.d, t = d.t, length = d.length, lace = d.lace, c = d.c, h = d.h }
    NUI.CloseSide()
    NUI.CloseApp()
    if Config.Tables.Enabled then
        return Tables.Job('make', req, d.view)
    end
    TriggerServerEvent('nz-wig:s:make', req)
end)

-- supplier ------------------------------------------------------------------------------------------

if not SU.Enabled then return end

local supplierPed

local function openShop()
    if Snatch.busy or NUI.app then return end
    local data = lib.callback.await('nz-wig:supplier', false)
    if not data or NUI.app then return end
    NUI.Side('shop', data)
end

RegisterNUICallback('shopClose', function(_, cb)
    NUI.CloseSide()
    cb(1)
end)

RegisterNUICallback('shopBuy', function(d, cb)
    local ok, msg, money = lib.callback.await('nz-wig:supplierBuy', false, d and d.cart or {})
    if msg then CB.Notify(msg, ok and 'success' or 'error') end
    if ok then NUI.Send('cash') end
    cb({ ok = ok == true, money = money })
end)

local OPT = { { name = 'nzwig_supplier', label = L('supplier_browse'), icon = 'fa-solid fa-box-open', distance = 2.5, onSelect = openShop } }

local function spawnSupplier()
    if not pcall(lib.requestModel, SU.Ped, 5000) then return end
    local c = SU.Coords
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    supplierPed = CreatePed(4, SU.Ped, c.x, c.y, found and z or c.z - 1.0, c.w, false, false)
    SetEntityInvincible(supplierPed, true)
    SetBlockingOfNonTemporaryEvents(supplierPed, true)
    FreezeEntityPosition(supplierPed, true)
    TaskStartScenarioInPlace(supplierPed, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(SU.Ped)
    if CB.Target ~= 'none' then CB.AddLocalEntity(supplierPed, OPT) end
end

CreateThread(function()
    if SU.Blip then
        local b = AddBlipForCoord(SU.Coords.x, SU.Coords.y, SU.Coords.z)
        SetBlipSprite(b, SU.Blip.sprite)
        SetBlipColour(b, SU.Blip.colour)
        SetBlipScale(b, SU.Blip.scale)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(SU.Label)
        EndTextCommandSetBlipName(b)
    end
    while true do
        local d = #(GetEntityCoords(PlayerPedId()) - SU.Coords.xyz)
        if d < 80.0 and not supplierPed then spawnSupplier()
        elseif d > 90.0 and supplierPed then DeleteEntity(supplierPed) supplierPed = nil end
        -- no target resource: [E] at the supplier
        if CB.Target == 'none' and supplierPed and d < 2.2 and not NUI.app then
            if not textShown then lib.showTextUI('[E] ' .. OPT[1].label) textShown = true end
            if IsControlJustReleased(0, 38) then openShop() end
            Wait(0)
        else
            if textShown then lib.hideTextUI() textShown = false end
            Wait(d < 10.0 and 250 or 1500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    if supplierPed then DeleteEntity(supplierPed) end
    if textShown then lib.hideTextUI() end
end)
