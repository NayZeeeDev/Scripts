-- Player interactions that open a small picker: hair products, putting a wig on someone,
-- taking a wig off someone.

Interact = {}

local CP = Config.Products

local function free()
    return not Snatch.busy and not NUI.app and not Restrain.tied and not Restrain.held and not Restrain.acting
end

local function hasHead(entity)
    local m = ModelKey(GetEntityModel(entity))
    return m ~= nil and ModelEnabled(m)
end

-- products -----------------------------------------------------------------------------------------

local function openProducts(entity)
    local sid = ServerIdOf(entity)
    if not sid then return end
    local list = lib.callback.await('nz-wig:productCounts', false) or {}
    local usable = {}
    for _, p in ipairs(list) do
        if p.others then usable[#usable + 1] = p end
    end
    if #usable == 0 then return CB.Notify(L('no_products'), 'error') end
    local name = GetPlayerName(GetPlayerFromServerId(sid))
    NUI.Open('products', {
        target = sid, name = name, products = usable,
        behind = IsBehind(PlayerPedId(), entity, Config.Clash.Blindside.Angle),
        helpless = CB.Helpless(entity, sid),
    })
end

RegisterNUICallback('productUse', function(d, cb)
    NUI.CloseApp()
    if d and type(d.id) == 'string' then TriggerServerEvent('nz-wig:s:product', d.id, tonumber(d.target)) end
    cb(1)
end)

-- using a product from the inventory: on whoever is in front (if it works on others), else yourself
RegisterNetEvent('nz-wig:c:useProduct', function(id)
    local p = CP.List[id]
    if not p or not free() then return end
    if p.Others then
        local ped = ClosestInFront(CP.Range)
        local sid = ped and ServerIdOf(ped)
        if sid then return TriggerServerEvent('nz-wig:s:product', id, sid) end
    end
    if p.Self then return TriggerServerEvent('nz-wig:s:product', id) end
    CB.Notify(L('no_one_close'), 'error')
end)

-- wigs on other players ---------------------------------------------------------------------------------

local function openPutOn(entity)
    local sid = ServerIdOf(entity)
    if not sid then return end
    local model = ModelKey(GetEntityModel(entity))
    local wigs = {}
    for _, w in ipairs(lib.callback.await('nz-wig:myWigs', false) or {}) do
        if not w.generic and w.fits == model then wigs[#wigs + 1] = w end
    end
    if #wigs == 0 then return CB.Notify(L('no_wig_fits'), 'error') end
    NUI.Open('puton', { target = sid, name = GetPlayerName(GetPlayerFromServerId(sid)), wigs = wigs })
end

RegisterNUICallback('putOn', function(d, cb)
    NUI.CloseApp()
    if d and type(d.key) == 'string' then TriggerServerEvent('nz-wig:s:putOn', tonumber(d.target), d.key) end
    cb(1)
end)

-- options -------------------------------------------------------------------------------------------------

Interact.TargetOptions = {
    {
        name = 'nzwig_product', label = L('target_products'), icon = CP.TargetIcon, distance = CP.Range,
        canInteract = function(e) return free() and hasHead(e) end,
        onSelect = openProducts,
    },
}

if Config.Wig.PutOnOthers then
    Interact.TargetOptions[#Interact.TargetOptions + 1] = {
        name = 'nzwig_puton', label = Config.Wig.PutOnLabel, icon = 'fa-solid fa-hat-wizard', distance = 2.0,
        canInteract = function(e) return free() and hasHead(e) end,
        onSelect = openPutOn,
    }
end

if Config.Wig.TakeOffOthers then
    Interact.TargetOptions[#Interact.TargetOptions + 1] = {
        name = 'nzwig_takeoff', label = Config.Wig.TakeOffLabel, icon = 'fa-solid fa-hand-sparkles', distance = 2.0,
        canInteract = function(e)
            local sid = ServerIdOf(e)
            return free() and sid and Player(sid).state[ST.wig] == true
        end,
        onSelect = function(e) local sid = ServerIdOf(e) if sid then TriggerServerEvent('nz-wig:s:takeOff', sid) end end,
    }
end
