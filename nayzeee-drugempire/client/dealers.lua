--[[ Hired dealers: a ped at their spot, stock them up, collect the cash ]]

Dealers = {}

local active = {}  -- id -> { blip, point, ped, target }

local function give(id)
    local stock = lib.callback.await('nzde:cust:stock', false) or {}
    local cfg = Config.DealerList[id]
    local pick = UI.panel('give', { mode = 'dealer', name = cfg.name, stock = stock, units = true })
    if not pick or not pick.pid then return end
    local ok, res = lib.callback.await('nzde:dealer:give', false, id, pick.pid, pick.q, pick.n or 1)
    if not ok then return UI.notify(res or 'They didn\'t take it', 'error') end
    UI.notify(('%s now holds %d units'):format(cfg.name, res.units), 'success')
end

local function collect(id)
    local ok, res = lib.callback.await('nzde:dealer:collect', false, id)
    if not ok then return UI.notify(res or 'Nothing to collect', 'info') end
    PlaySoundFrontend(-1, 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET', true)
    UI.notify(('Collected %s'):format(Utils.money(res)), 'success')
end

local function spawn(id, a)
    if a.ped then return end
    local cfg = Config.DealerList[id]
    a.ped = Util.ped(cfg.model, cfg.coords, 'WORLD_HUMAN_DRUG_DEALER')
    a.target = Target.addEntity(a.ped, {
        { name = 'nzde_dealer_give', label = 'Give ' .. cfg.name .. ' product', icon = 'fa-solid fa-box', distance = 2.5, onSelect = function() give(id) end },
        { name = 'nzde_dealer_cash', label = 'Collect cash', icon = 'fa-solid fa-sack-dollar', distance = 2.5, onSelect = function() collect(id) end },
    })
end

local function despawn(a)
    if a.target then Target.removeEntity(a.target) a.target = nil end
    Util.delete(a.ped)
    a.ped = nil
end

function Dealers.refresh(st)
    local want = {}
    for _, id in ipairs(st.dealers or {}) do want[id] = true end
    for id, a in pairs(active) do
        if not want[id] then
            despawn(a)
            Util.removeBlip(a.blip)
            if a.point then a.point:remove() end
            active[id] = nil
        end
    end
    for id in pairs(want) do
        local cfg = Config.DealerList[id]
        if cfg and not active[id] then
            local a = {}
            a.blip = Util.blip(cfg.coords, Config.Dealers.blip, 'Dealer: ' .. cfg.name, false)
            a.point = lib.points.new({ coords = vec3(cfg.coords.x, cfg.coords.y, cfg.coords.z), distance = 50.0,
                onEnter = function() spawn(id, a) end, onExit = function() despawn(a) end })
            active[id] = a
        end
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, a in pairs(active) do despawn(a) end
end)
