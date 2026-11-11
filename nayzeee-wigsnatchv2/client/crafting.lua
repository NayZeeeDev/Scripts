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

-- suppliers: the Hair Supply and the Beauty Supply ------------------------------------------------------

local SHOPS = { hair = SU, beauty = Config.BeautySupply }
local peds = {}

local function openShop(id)
    if Snatch.busy or NUI.app then return end
    local data = lib.callback.await('nz-wig:supplier', false, id)
    if not data or NUI.app then return end
    NUI.Side('shop', data)
end

RegisterNUICallback('shopClose', function(_, cb)
    NUI.CloseSide()
    cb(1)
end)

RegisterNUICallback('shopBuy', function(d, cb)
    local ok, msg, wallets = lib.callback.await('nz-wig:supplierBuy', false, d and d.cart or {}, d and d.account, d and d.shop)
    if msg then CB.Notify(msg, ok and 'success' or 'error') end
    if ok then NUI.Send('cash') end
    cb({ ok = ok == true, accounts = wallets })
end)

local function spawn(id, sh)
    if not pcall(lib.requestModel, sh.Ped, 5000) then return end
    local c = sh.Coords
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
    local ped = CreatePed(4, sh.Ped, c.x, c.y, found and z or c.z - 1.0, c.w, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    SetModelAsNoLongerNeeded(sh.Ped)
    if CB.Target ~= 'none' then
        CB.AddLocalEntity(ped, { { name = 'nzwig_supplier_' .. id, label = L('supplier_browse_at', sh.Label), icon = 'fa-solid fa-box-open', distance = 2.5, onSelect = function() openShop(id) end } })
    end
    peds[id] = ped
end

for id, sh in pairs(SHOPS) do
    if sh and sh.Enabled then
        CreateThread(function()
            if sh.Blip then
                local b = AddBlipForCoord(sh.Coords.x, sh.Coords.y, sh.Coords.z)
                SetBlipSprite(b, sh.Blip.sprite)
                SetBlipColour(b, sh.Blip.colour)
                SetBlipScale(b, sh.Blip.scale)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(sh.Label)
                EndTextCommandSetBlipName(b)
            end
            local shown = false
            while true do
                local d = #(GetEntityCoords(PlayerPedId()) - sh.Coords.xyz)
                if d < 80.0 and not peds[id] then spawn(id, sh)
                elseif d > 90.0 and peds[id] then DeleteEntity(peds[id]) peds[id] = nil end
                -- no target resource: [E] at the counter
                if CB.Target == 'none' and peds[id] and d < 2.2 and not NUI.app then
                    if not shown then lib.showTextUI('[E] ' .. L('supplier_browse_at', sh.Label)) shown, textShown = true, true end
                    if IsControlJustReleased(0, 38) then openShop(id) end
                    Wait(0)
                else
                    if shown then lib.hideTextUI() shown, textShown = false, false end
                    Wait(d < 10.0 and 250 or 1500)
                end
            end
        end)
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end
    for _, p in pairs(peds) do if DoesEntityExist(p) then DeleteEntity(p) end end
    if textShown then lib.hideTextUI() end
end)
