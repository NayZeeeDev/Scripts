--[[ Shop blips, tuning bays and boss desks. Everything is point-based: zero cost away from a shop. ]]

Shops = {}

local function isEmployee(shopId, rank)
    local shop = Config.Shops[shopId]
    if not shop or not shop.job then return false end
    if Bridge.Job.name ~= shop.job then return false end
    return (Bridge.Job.grade or 0) >= ((shop.grades or {})[rank or 'access'] or 0)
end
Shops.IsEmployee = isEmployee

-- the shop this player works at (first match)
function Shops.MyShop()
    for id, shop in pairs(Config.Shops) do
        if shop.job and isEmployee(id) then return id end
    end
end

--------------------------------------------------------------------- bays

local shown
local function prompt(text)
    if shown == text then return end
    shown = text
    Bridge.TextUI(text)
end

local B = Config.Bays

local function claimOf(shopId, bay)
    local all = GlobalState.nzBays or {}
    return all[shopId] and all[shopId][tostring(bay)] or nil
end
Shops.ClaimOf = claimOf

local function claimBay(shopId, bay, release)
    CreateThread(function()
        local ok, res = lib.callback.await(release and 'nayzeee-tuning:bayRelease' or 'nayzeee-tuning:bayClaim', false, bay, shopId)
        if ok then Notify(release and L('bay_released', bay) or L('bay_claimed', bay), 'success')
        else Notify(res or L('failed'), 'error') end
    end)
end

local function bayPrompt(point)
    if Menu.open or Menu.IsTestDriving() or Install.Active() then return prompt(nil) end
    local shopId = point.shopId
    if cache.vehicle and cache.seat == -1 then
        prompt(L('prompt_tune'))
        if IsControlJustPressed(0, Config.Keys.Interact) then prompt(nil) Menu.Open(shopId, false) end
        return
    end
    if cache.vehicle or not isEmployee(shopId) then return prompt(nil) end

    local claims = NZ.BayClaims(shopId)
    local c = claims and claimOf(shopId, point.bay) or nil
    local mine = c ~= nil and c.sid == cache.serverId
    local boss = B.ManagersUseAny and isEmployee(shopId, 'manager')
    local locked = c ~= nil and not mine and B.LockMechanicUse and not boss
    local veh = VehUtil.Closest(point.radius + 1.5)
    local hasCar = veh and veh ~= 0

    local text
    if locked then text = L('prompt_bay_locked', point.bay, c.name)
    elseif hasCar then text = L('prompt_tune_mechanic') end
    if claims and not locked then
        local extra = c == nil and L('prompt_bay_claim') or (mine or boss) and L('prompt_bay_release') or nil
        if extra then text = text and (text .. '  \n' .. extra) or extra end
    end
    prompt(text)
    if not text then return end
    if hasCar and not locked and IsControlJustPressed(0, Config.Keys.Interact) then prompt(nil) Menu.Open(shopId, true) return end
    if claims and not locked and IsControlJustPressed(0, B.ClaimKey) then
        if c == nil then claimBay(shopId, point.bay, false) elseif mine or boss then claimBay(shopId, point.bay, true) end
    end
end

local function bayLabel(bay, text)
    local on, x, y = World3dToScreen2d(bay.x, bay.y, bay.z + 1.4)
    if not on then return end
    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

--------------------------------------------------------------------- build / rebuild (the shop editor changes shops live)

local built = { blips = {}, points = {}, zones = {} }

function Shops.Clear()
    for _, b in ipairs(built.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    for _, p in ipairs(built.points) do p:remove() end
    for _, z in ipairs(built.zones) do Bridge.RemoveZone(z) end
    built = { blips = {}, points = {}, zones = {} }
    prompt(nil)
end

function Shops.Build()
    for id, shop in pairs(Config.Shops) do
        if shop.blip and shop.blip.enabled ~= false and shop.center then
            local b = AddBlipForCoord(shop.center.x, shop.center.y, shop.center.z)
            SetBlipSprite(b, shop.blip.sprite or 72)
            SetBlipColour(b, shop.blip.color or 0)
            SetBlipScale(b, shop.blip.scale or 0.8)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(shop.label or id)
            EndTextCommandSetBlipName(b)
            built.blips[#built.blips + 1] = b
        end

        for i, bay in ipairs(shop.bays or {}) do
            local r = NZ.BayRadius(shop, i)
            local point = lib.points.new({ coords = bay.xyz, distance = math.max(r + 0.5, 12.0), shopId = id, radius = r, bay = i })
            function point:nearby()
                if self.currentDistance < 12.0 and not Menu.open then
                    local c = B.ShowName and NZ.BayClaims(id) and claimOf(id, i) or nil
                    local r, g, b = 8, 175, 162
                    if c then r, g, b = (c.sid == cache.serverId) and 8 or 245, (c.sid == cache.serverId) and 175 or 158, (c.sid == cache.serverId) and 162 or 11 end
                    DrawMarker(1, bay.x, bay.y, bay.z - 0.95, 0, 0, 0, 0, 0, 0, self.radius * 2.0, self.radius * 2.0, 0.25, r, g, b, 70, false, false, 2, false, nil, nil, false)
                    if B.ShowName and NZ.BayClaims(id) and isEmployee(id) then
                        bayLabel(bay, c and L('bay_label_taken', i, c.name) or L('bay_label_free', i))
                    end
                end
                if self.currentDistance <= self.radius + 0.5 then
                    Shops.atBay = self
                    bayPrompt(self)
                elseif Shops.atBay == self then
                    Shops.atBay = nil
                    prompt(nil)
                end
            end
            function point:onExit() if Shops.atBay == self then Shops.atBay = nil prompt(nil) end end
            built.points[#built.points + 1] = point
        end

        -- supply storage: take parts out / put them back (tablet Storage app)
        if shop.job and shop.storage and Config.Storage.Enabled then
            local at = shop.storage
            local p = lib.points.new({ coords = at, distance = 10.0 })
            function p:nearby()
                if not isEmployee(id) or Menu.open or UI.focus or Install.Active() then return end
                if Supply.active and Supply.active.stage == 'unload' then return end
                DrawMarker(21, at.x, at.y, at.z + 0.4, 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 8, 175, 162, 200, true, true, 2, false, nil, nil, false)
                if self.currentDistance <= Config.Storage.UseRadius then
                    Shops.atStorage = self
                    prompt(L('prompt_storage'))
                    if IsControlJustPressed(0, Config.Keys.Interact) then prompt(nil) Tablet.Open({ app = 'storage' }) end
                elseif Shops.atStorage == self then
                    Shops.atStorage = nil
                    prompt(nil)
                end
            end
            function p:onExit() if Shops.atStorage == self then Shops.atStorage = nil prompt(nil) end end
            built.points[#built.points + 1] = p
        end

        if shop.job and shop.boss then
            local name = 'nzt_boss_' .. id
            local targetOk = Bridge.AddSphere(name, shop.boss, 1.2, {
                { name = name, label = L('target_business'), icon = 'fa-briefcase',
                  canInteract = function() return isEmployee(id) end,
                  onSelect = function() Tablet.Open({ app = 'dashboard', desk = true }) end },
            })
            if targetOk then built.zones[#built.zones + 1] = name
            else
                local p = lib.points.new({ coords = shop.boss, distance = 1.6 })
                function p:nearby()
                    if isEmployee(id) and not UI.focus then
                        prompt(L('prompt_business'))
                        if IsControlJustPressed(0, Config.Keys.Interact) then prompt(nil) Tablet.Open({ app = 'dashboard', desk = true }) end
                    end
                end
                function p:onExit() prompt(nil) end
                built.points[#built.points + 1] = p
            end
        end
    end
end

-- editor changes arrive through a global state bag
local function applyEdits(edits)
    NZ.ApplyShopEdits(edits or {})
    Shops.Clear()
    Shops.Build()
end

AddStateBagChangeHandler('nzShopEdits', 'global', function(_, _, value)
    applyEdits(value)
end)

CreateThread(function()
    local t = GetGameTimer() + 4000
    while GlobalState.nzShopEdits == nil and GetGameTimer() < t do Wait(200) end
    applyEdits(GlobalState.nzShopEdits)
end)

--------------------------------------------------------------------- commands

RegisterCommand('workorders', function()
    local shopId = Shops.MyShop()
    if not shopId then return Notify(L('no_permission'), 'error') end
    Tablet.Open({ app = 'orders' })
end, false)
