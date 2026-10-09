-- Wig making from materials (Workshop > Make a wig) and the supplier who sells the materials.

local CC, SU = Config.Crafting, Config.Supplier

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

RegisterNUICallback('craftInfo', function(d, cb)
    local info = lib.callback.await('nz-wig:craftInfo', false)
    if not info then return cb(false) end
    local m = d and d.m == 'm' and 'm' or 'f'
    info.m = m
    info.styles = readStyles(m)
    info.shots = lib.callback.await('nz-wig:shots', false) or {}
    info.palette = HairPalette()
    info.myModel = GetEntityModel(PlayerPedId()) == Config.Models.male.model and 'm' or 'f'
    cb(info)
end)

-- make it: at the table you're at (or anywhere when wig tables aren't required)
RegisterNUICallback('make', function(d, cb)
    cb(1)
    if type(d) ~= 'table' then return end
    local req = { m = d.m, d = d.d, t = d.t, length = d.length, lace = d.lace, c = d.c, h = d.h }
    NUI.CloseApp()
    if Config.Tables.Enabled and (Config.Tables.RequireTable or Tables.Bench()) then
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
    if not data then return end
    NUI.Open('shop', data)
end

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
    local shown = false
    while true do
        local d = #(GetEntityCoords(PlayerPedId()) - SU.Coords.xyz)
        if d < 80.0 and not supplierPed then spawnSupplier()
        elseif d > 90.0 and supplierPed then DeleteEntity(supplierPed) supplierPed = nil end
        -- no target resource: [E] at the supplier
        if CB.Target == 'none' and supplierPed and d < 2.2 and not NUI.app then
            if not shown then lib.showTextUI('[E] ' .. OPT[1].label) shown = true end
            if IsControlJustReleased(0, 38) then openShop() end
            Wait(0)
        else
            if shown then lib.hideTextUI() shown = false end
            Wait(d < 10.0 and 250 or 1500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE and supplierPed then DeleteEntity(supplierPed) end
end)
