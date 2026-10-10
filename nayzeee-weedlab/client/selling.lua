--[[
    Selling, client side.
      Corner: /sellweed (or the key) turns selling mode on. The nearest person on foot gets an
              [E] prompt; they stop, face you, and either buy (hand-off) or walk off.
      Bulk:   the brick buyer (level gated) at his spot.
    The selling loop only runs while selling mode is on.
]]

Selling = { on = false }

local SC = Config.Selling
local asked = {}          -- ped entity -> true (this session)

local function candidate()
    local me = cache.ped
    local pc = GetEntityCoords(me)
    local best, bd
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not asked[ped] and not IsPedAPlayer(ped) and IsPedHuman(ped) and not IsPedDeadOrDying(ped, true)
            and not IsPedInAnyVehicle(ped, false) and NetworkGetEntityIsNetworked(ped) and GetPedType(ped) ~= 6 and GetPedType(ped) ~= 27 then
            local d = #(GetEntityCoords(ped) - pc)
            if d <= SC.corner.radius and (not bd or d < bd) then best, bd = ped, d end
        end
    end
    return best
end

local function handoff(ped)
    lib.requestAnimDict('mp_common')
    TaskPlayAnim(cache.ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 1600, 49, 0, false, false, false)
    TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 1600, 49, 0, false, false, false)
    local cash = Util.prop('prop_anim_cash_note', GetEntityCoords(ped), 0.0, { noCollision = true, fallback = false, freeze = false })
    if cash then AttachEntityToEntity(cash, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.02, -0.02, 0.0, 0.0, 0.0, true, true, false, true, 1, true) end
    Wait(1600)
    Util.delete(cash)
    RemoveAnimDict('mp_common')
end

local function offer(ped)
    asked[ped] = true
    LocalPlayer.state:set('nzwlBusy', true, false)
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, cache.ped, 1200)
    TaskTurnPedToFaceEntity(cache.ped, ped, 1200)
    Wait(900)
    local ok, res = lib.callback.await('nzwl:sell:offer', false, NetworkGetNetworkIdFromEntity(ped))
    if not ok then
        if res then UI.notify(res, 'error') end
    elseif res.accepted then
        handoff(ped)
        UI.notify(('Sold %dx %s · %s'):format(res.n, res.label, Utils.money(res.price)), 'success', 5000, res.item == Config.Product.jar and 'Jar sold' or 'Baggie sold')
    else
        PlayPedAmbientSpeechNative(ped, 'GENERIC_NO', 'SPEECH_PARAMS_FORCE')
        UI.notify(res.called and 'They pulled out a phone. Move.' or 'Not interested.', res.called and 'error' or 'info')
    end
    TaskWanderStandard(ped, 10.0, 10)
    SetPedKeepTask(ped, true)
    LocalPlayer.state:set('nzwlBusy', false, false)
end

function Selling.toggle(state)
    if state == nil then state = not Selling.on end
    if state and (Labs.inside or LocalPlayer.state.nzwlBusy) then return end
    Selling.on = state
    UI.notify(state and 'Selling. Walk up to people and press E.' or 'Stopped selling.', 'info', 3500)
    if not state then UI.hideTextui() return end
    CreateThread(function()
        local shown
        while Selling.on do
            local ped = (not cache.vehicle and not LocalPlayer.state.nzwlBusy) and candidate() or nil
            if ped then
                if shown ~= ped then
                    UI.textui({ { key = 'E', label = 'Offer weed' }, { key = SC.corner.key or '/' .. SC.corner.command, label = 'Stop selling' } })
                    shown = ped
                end
                if IsControlJustReleased(0, 38) then
                    UI.hideTextui()
                    shown = nil
                    offer(ped)
                end
                Wait(0)
            else
                if shown then UI.hideTextui() shown = nil end
                Wait(400)
            end
            if Labs.inside then Selling.on = false end
        end
        UI.hideTextui()
    end)
end

if SC.corner.enabled and SC.corner.command then
    RegisterCommand(SC.corner.command, function() Selling.toggle() end, false)
    if SC.corner.key then RegisterKeyMapping(SC.corner.command, 'Weed lab: sell weed', 'keyboard', SC.corner.key) end
end

--[[ ─────────────── the brick buyer ─────────────── ]]
local buyer = {}

local function openBulk()
    local data, err = lib.callback.await('nzwl:bulk:open', false)
    if not data then
        if err then UI.notify(err, 'error', 5000, SC.bulk.label) end
        return
    end
    while true do
        local pick = UI.panel('bulk', data)
        if not pick or not pick.slot then return end
        local ok, res = lib.callback.await('nzwl:bulk:sell', false, pick.slot, pick.n)
        if not ok then
            if res then UI.notify(res, 'error', 5000, SC.bulk.label) end
            return
        end
        UI.notify(('Paid %s'):format(Utils.money(res.total)), 'success', 5000, SC.bulk.label)
        data = res.panel
    end
end

CreateThread(function()
    local B = SC.bulk
    if not B.enabled then return end
    if B.blip then buyer.blip = Util.blip(B.ped, B.blip, B.blip.label, false) end
    buyer.point = lib.points.new({
        coords = vec3(B.ped.x, B.ped.y, B.ped.z), distance = 40.0,
        onEnter = function()
            buyer.ped = Util.ped(B.model, B.ped, 'WORLD_HUMAN_SMOKING')
            buyer.target = Target.addEntity(buyer.ped, {
                { name = 'nzwl_bulk', label = 'Sell bricks', icon = 'fa-solid fa-cube', distance = 2.5, onSelect = openBulk },
            })
        end,
        onExit = function()
            if buyer.target then Target.removeEntity(buyer.target) buyer.target = nil end
            Util.delete(buyer.ped)
            buyer.ped = nil
        end,
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    Util.removeBlip(buyer.blip)
    Util.delete(buyer.ped)
    if Selling.on then UI.hideTextui() end
end)
