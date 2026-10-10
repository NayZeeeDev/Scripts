--[[ Hardware stores: a clerk + blip at every store, the catalogue opens in the NAYZEEE store panel ]]

Shop = {}

local stores = {}

local function open()
    local data = lib.callback.await('nzwl:shop:open', false)
    if not data then return end
    local res = UI.panel('shop', data)
    if not res or not res.basket or #res.basket == 0 then return end
    local ok, out = lib.callback.await('nzwl:shop:buy', false, res.basket, res.account)
    if ok then
        UI.notify(('Paid %s'):format(Utils.money(out)), 'success', 5000, 'Hardware store')
    elseif out then
        UI.notify(out, 'error')
    end
end

CreateThread(function()
    for i, s in ipairs(Config.Stores) do
        local st = { blip = Util.blip(s.ped, Config.StoreBlip, Config.StoreBlip.label, false) }
        st.point = lib.points.new({
            coords = vec3(s.ped.x, s.ped.y, s.ped.z), distance = 40.0,
            onEnter = function()
                st.ped = Util.ped(s.model, s.ped, 'WORLD_HUMAN_CLIPBOARD')
                st.target = Target.addEntity(st.ped, {
                    { name = 'nzwl_store_' .. i, label = 'Browse ' .. s.label, icon = 'fa-solid fa-store', distance = 2.5, onSelect = open },
                })
            end,
            onExit = function()
                if st.target then Target.removeEntity(st.target) st.target = nil end
                Util.delete(st.ped)
                st.ped = nil
            end,
        })
        stores[i] = st
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, st in pairs(stores) do
        Util.removeBlip(st.blip)
        Util.delete(st.ped)
    end
end)
