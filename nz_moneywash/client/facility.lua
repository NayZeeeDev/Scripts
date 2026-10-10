--[[ Wash units — the door, the emptied counterfeit factory, the unit terminal ]]

FacilityUI = {}

local F = Config.Facility
local interiorId = 0

-- switch off every piece of GTA's own factory equipment so crews build their own floor
local function emptyInterior()
    if not F.enabled then return end
    RequestIpl(F.interior.ipl)
    local c = F.interior.coords
    for _ = 1, 25 do
        interiorId = GetInteriorAtCoords(c.x, c.y, c.z)
        if interiorId ~= 0 then break end
        Wait(200)
    end
    if interiorId == 0 then
        print('^3[nz_moneywash] Counterfeit factory interior not found — is the biker DLC IPL loaded (bob74_ipl)?^7')
        return
    end
    local sets = {}
    for _, name in ipairs(F.interior.sets) do sets[#sets + 1] = name end
    if F.interior.cashPiles then
        for n = 10, 100, 10 do
            for _, l in ipairs({ 'a', 'b', 'c', 'd' }) do sets[#sets + 1] = ('counterfeit_cashpile%d%s'):format(n, l) end
        end
    end
    for _, name in ipairs(sets) do
        if IsInteriorEntitySetActive(interiorId, name) then DeactivateInteriorEntitySet(interiorId, name) end
    end
    RefreshInterior(interiorId)
end

local function teleport(c)
    DoScreenFadeOut(350)
    while not IsScreenFadedOut() do Wait(10) end
    local ped = PlayerPedId()
    local inside = #(vec3(c.x, c.y, c.z) - F.interior.coords) < 80.0
    if inside then emptyInterior() end
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(0) end
    Wait(250)
    DoScreenFadeIn(450)
end

RegisterNetEvent('nzmw:unit:teleport', function(c) teleport(c) end)

local function myUnit() return LocalPlayer.state.nzmwUnit end

function FacilityUI.door()
    U.run(function()
        local data = lib.callback.await('nzmw:unit:list', false)
        if not data or not data.ok then return UI.err(data) end
        data.serverNow = U.now()
        local pick = UI.await('units', data)
        if not pick then return end
        if pick.action == 'enter' then
            local res = lib.callback.await('nzmw:unit:enter', false, pick.id)
            if not res or not res.ok then return UI.err(res) end
        elseif pick.action == 'buy' then
            local res = lib.callback.await('nzmw:unit:buy', false)
            if not res or not res.ok then return UI.err(res) end
            UI.toast('Unit #' .. res.id, 'The keys are yours. Order equipment at the terminal by the door.', 'success', 9000)
        elseif pick.action == 'breach' then
            local res = lib.callback.await('nzmw:unit:breach', false, pick.id, 'start')
            if not res or not res.ok then return UI.err(res) end
            U.playPed(Config.Anims.pry, 1)
            local ok = UI.progress(('Forcing the door of unit #%d'):format(pick.id), F.breachTime)
            U.stopPed()
            if not ok then return end
            res = lib.callback.await('nzmw:unit:breach', false, pick.id, 'finish')
            if not res or not res.ok then return UI.err(res) end
        end
    end)
end

function FacilityUI.leave()
    U.run(function()
        local res = lib.callback.await('nzmw:unit:leave', false)
        if not res or not res.ok then return UI.err(res) end
    end)
end

function FacilityUI.terminal()
    U.run(function()
        local data = lib.callback.await('nzmw:unit:data', false)
        if not data or not data.ok then return UI.err(data) end
        data.serverNow = U.now()
        UI.await('unit', data)
    end)
end

function FacilityUI.init()
    if not F.enabled then return end
    CreateThread(emptyInterior)

    Target.addZone('nzmw_units_door', F.entrance.xyz, 1.1, {
        { name = 'units', label = 'Wash units', icon = 'fas fa-warehouse',
          canInteract = function() return not U.busy and not UI.isOpen() and Render.bucket == 0 end,
          onSelect = FacilityUI.door },
    })
    Target.addZone('nzmw_units_exit', F.interior.inside.xyz, 1.3, {
        { name = 'terminal', label = 'Unit terminal', icon = 'fas fa-laptop',
          canInteract = function()
              local u = myUnit()
              return not U.busy and not UI.isOpen() and u ~= nil and (u.role == 'owner' or u.role == 'member')
          end,
          onSelect = FacilityUI.terminal },
        { name = 'leave', label = 'Leave the unit', icon = 'fas fa-door-open',
          canInteract = function() return not U.busy and not UI.isOpen() and myUnit() ~= nil end,
          onSelect = FacilityUI.leave },
    })

    -- follow our routing bucket so only this unit's machines exist for us
    AddStateBagChangeHandler('nzmwBucket', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
        Render.queueBucket(value or 0)
    end)
    Render.queueBucket(LocalPlayer.state.nzmwBucket or 0)

    -- reconnected inside the factory but back in the world bucket → walk them out the front door
    CreateThread(function()
        Wait(2000)
        local pos = GetEntityCoords(PlayerPedId())
        if (LocalPlayer.state.nzmwBucket or 0) == 0 and #(pos - F.interior.coords) < 60.0 then
            teleport({ x = F.entrance.x, y = F.entrance.y, z = F.entrance.z, w = (F.entrance.w + 180.0) % 360 })
        end
    end)
end
