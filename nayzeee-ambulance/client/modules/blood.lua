--[[
    NAYZEEE AMBULANCE - Blood services (client): blood bank, bag label, Type & screen, weakness

    Hospital point (NZA.Points.RegisterType, ARCHITECTURE §8):
        'bloodbank'  blood fridge - target "Open blood bank" (Config.Blood.Bank.perm) → NUI app
                     'donation' mode 'bank' (window: stock by group, units with expiry, your bags,
                     deposit / withdraw / fill an empty bag, discard expired, log)
    Patient option (NZA.Interact): nza_blood_type 'Type & screen' (order Config.Blood.TypeScreen.order)
        → bedside card test (progress) → NZA.Treat 'blood:type' → the group is shown to the medic and
        on bag labels / the IV stand from now on.
    Using a blood bag (server usable) → NUI app 'donation' mode 'label' (the printed bag label).
    Weakness after donating: walk style + no sprint + a short screen effect (also restored after a
    reconnect through nza:blood:me).

    Client API (NZA.Blood, runtime only):
        NZA.Blood.L(key, ...)  NZA.Blood.Locale()  NZA.Blood.Toast(msg, type, title)
        NZA.Blood.TypeScreen(entity, target) → bloodType | nil     NZA.Blood.OpenBank(point)
        NZA.Blood.Weak(seconds)   NZA.Blood.App = 'donation'
    NUI 'donation' callbacks handled here: donation:bank { action = refresh|deposit|withdraw|fill|discard,
        serial?, type? } → { ok, msg, data }, donation:close (bank / label sessions)
    Net events: nza:blood:label (bag view) S→C, nza:blood:weak (seconds) S→C
    Callbacks used: nza:blood:bank:* , nza:blood:me
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local U = NZA.Util

local APP = 'donation'
B.App = APP

local function cfg(section)
    local c = Config.Blood or {}
    if section then return c[section] or {} end
    return c
end
B.Cfg = cfg

local function L(key, ...) return NZA.L('blood.' .. key, ...) end
B.L = L

function B.Locale()
    return NZA.LocaleTable('blood')
end

function B.Toast(msg, kind, title)
    if not msg or msg == '' then return end
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info' })
end

function B.Item(key)
    return key and Config.Items and Config.Items[key] or nil
end

local function errMsg(res, fallback)
    if type(res) == 'table' then return res.msg or res.message or fallback end
    if type(res) == 'string' then return res end
    return fallback
end
B.ErrMsg = errMsg

-- ════════════════════════════════════════════════════════════════════════
-- BLOOD BANK (window in the 'donation' app)
-- ════════════════════════════════════════════════════════════════════════

local bank = nil   -- { point, coords }
local label = false

local function pointCoords(point)
    local c = point and point.coords
    if not c then return nil end
    return vector3(c.x, c.y, c.z)
end

function B.OpenBank(point)
    if bank or (B.Busy and B.Busy()) then return end
    if not NZA.Perm(cfg('Bank').perm or 'blood') then return B.Toast(L('err_no_perm'), 'error') end
    local res = lib.callback.await('nza:blood:bank:open', false, point.id)
    if type(res) ~= 'table' or not res.ok then return B.Toast(errMsg(res, L('err_failed')), 'error') end
    bank = { point = point, coords = pointCoords(point) }
    NZA.UI.Open(APP, { mode = 'bank', locale = B.Locale(), data = res.data }, { focus = true, cursor = true })
    CreateThread(function()
        local s = bank
        local reach = (tonumber(cfg('Bank').distance) or 2.5) + 2.5
        while bank == s do
            Wait(500)
            local ped = PlayerPedId()
            local far = s.coords and #(GetEntityCoords(ped) - s.coords) > reach
            if far or IsEntityDead(ped) or (NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown()) then
                NZA.UI.Close(APP)
                bank = nil
            end
        end
    end)
end

NZA.UI.On(APP, 'bank', function(data, cb)
    local s = bank
    if not s or type(data) ~= 'table' then return cb({ ok = false, msg = L('err_failed') }) end
    local action = data.action
    local res
    if action == 'refresh' then
        res = lib.callback.await('nza:blood:bank:open', false, s.point.id)
    elseif action == 'deposit' then
        res = lib.callback.await('nza:blood:bank:deposit', false, s.point.id, data.serial)
    elseif action == 'withdraw' then
        res = lib.callback.await('nza:blood:bank:withdraw', false, s.point.id, data.serial)
    elseif action == 'fill' then
        res = lib.callback.await('nza:blood:bank:fill', false, s.point.id, data.type, data.serial)
    elseif action == 'discard' then
        res = lib.callback.await('nza:blood:bank:discard', false, s.point.id, data.serial)
    end
    if type(res) ~= 'table' then res = { ok = false, msg = L('err_failed') } end
    if res.ok and res.msg then B.Toast(res.msg, 'success') end
    cb(res)
end)

NZA.UI.On(APP, 'close', function(_, cb)
    bank = nil
    label = false
    cb({ ok = true })
end)

-- ════════════════════════════════════════════════════════════════════════
-- BAG LABEL (using a blood bag item)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:blood:label', function(view)
    if type(view) ~= 'table' then return end
    if NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() then return end
    if bank or (B.Busy and B.Busy()) then return end
    label = true
    NZA.UI.Open(APP, { mode = 'label', locale = B.Locale(), bag = view }, { focus = true, cursor = true })
end)

-- ════════════════════════════════════════════════════════════════════════
-- TYPE & SCREEN
-- ════════════════════════════════════════════════════════════════════════

local typing = false

local function lyingDown(ped)
    if not ped or ped == 0 then return false end
    local st = NZA.Target.State(ped)
    if type(st) == 'table' and st.st and st.st ~= 'alive' then return true end
    return IsPedRagdoll(ped) or IsEntityPlayingAnim(ped, 'dead', 'dead_a', 3)
end

function B.TypeScreen(entity, target)
    if typing then return nil end
    local ts = cfg('TypeScreen')
    if ts.enabled == false then return nil end
    if not NZA.Perm(ts.perm or 'blood') then
        B.Toast(L('err_no_perm'), 'error')
        return nil
    end
    target = target or NZA.Target.FromEntity(entity)
    if not target then return nil end
    entity = entity or NZA.Target.Entity(target)
    typing = true
    local ped = PlayerPedId()
    if entity and entity ~= 0 and entity ~= ped then
        TaskTurnPedToFaceEntity(ped, entity, 600)
        Wait(450)
    end
    local anim = lyingDown(entity) and ts.anim or ts.animStand or ts.anim or {}
    local done = lib.progressBar({
        duration = math.floor((tonumber(ts.seconds) or 6) * 1000),
        label = L('ts_progress'),
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim.dict and { dict = anim.dict, clip = anim.clip, flag = 49 } or nil,
    })
    typing = false
    if not done then
        B.Toast(L('ts_cancel'), 'error')
        return nil
    end
    local ok, res = NZA.Treat.Do('blood:type', target, {}, { silent = true })
    if not ok then
        B.Toast(errMsg(res, L('err_failed')), 'error')
        return nil
    end
    local bt = type(res) == 'table' and res.bloodType or nil
    NZA.UI.Toast({ title = L('ts_title'), message = L('ts_result', bt or '?'), type = 'success', icon = 'bloodbag' })
    NZA.Bus.Emit('blood:typed', target, bt)
    return bt
end

NZA.Interact.Add({
    name = 'nza_blood_type', label = L('opt_type'), icon = cfg('TypeScreen').icon or 'bloodbag',
    order = tonumber(cfg('TypeScreen').order) or 27,
    perm = cfg('TypeScreen').perm or 'blood',
    states = { alive = true, wounded = true, arrest = true, dead = true },
    npc = true, player = true, self = false, distance = tonumber(cfg('TypeScreen').distance) or 2.2,
    canInteract = function()
        return cfg('TypeScreen').enabled ~= false and not typing
    end,
    onSelect = function(entity, target)
        B.TypeScreen(entity, target)
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- BLOOD BANK POINT
-- ════════════════════════════════════════════════════════════════════════

local bankProp = cfg('Bank').prop
NZA.Points.RegisterType('bloodbank', {
    label = L('point_bank'), icon = 'bloodbag',
    prop = (type(bankProp) == 'string' and Config.Props[bankProp]) or nil,
    needsHeading = type(bankProp) == 'string',
    radius = 1.0, distance = tonumber(cfg('Bank').distance) or 2.5,
    target = {
        {
            name = 'nza_blood_bank', label = L('opt_bank'), icon = 'bloodbag', perm = cfg('Bank').perm or 'blood',
            canInteract = function() return bank == nil end,
            onSelect = function(point)
                CreateThread(function() B.OpenBank(point) end)
            end,
        },
    },
})

-- ════════════════════════════════════════════════════════════════════════
-- WEAKNESS AFTER DONATING
-- ════════════════════════════════════════════════════════════════════════

local weakUntil = 0
local weakThread = false

local function weakOn(on)
    local w = cfg('Donation').weakness or {}
    if w.clipset and NZA.Self and NZA.Self.SetMoveOverride then
        if on then NZA.Self.SetMoveOverride('blood_weak', w.clipset) else NZA.Self.SetMoveOverride('blood_weak', nil) end
    end
    if w.noSprint ~= false then SetPlayerSprint(PlayerId(), not on) end
end

function B.Weak(seconds, fx)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return end
    weakUntil = math.max(weakUntil, GetGameTimer() + math.floor(seconds * 1000))
    local w = cfg('Donation').weakness or {}
    if fx ~= false and w.fx then
        CreateThread(function()
            AnimpostfxPlay(w.fx, 0, true)
            Wait(math.floor((tonumber(w.fxSeconds) or 6) * 1000))
            AnimpostfxStop(w.fx)
        end)
    end
    if weakThread then return end
    weakThread = true
    CreateThread(function()
        weakOn(true)
        while GetGameTimer() < weakUntil do
            Wait(1000)
            if NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then break end
        end
        weakOn(false)
        weakThread = false
        weakUntil = 0
    end)
end

RegisterNetEvent('nza:blood:weak', function(seconds)
    B.Weak(seconds, true)
end)

local function restoreWeak()
    local r = lib.callback.await('nza:blood:me', false)
    if type(r) == 'table' and tonumber(r.weakUntil) and tonumber(r.now) and r.weakUntil > r.now then
        B.Weak(r.weakUntil - r.now, false)
    end
end

if Bridge and Bridge.OnPlayerLoaded then
    Bridge.OnPlayerLoaded(function()
        SetTimeout(4000, function() CreateThread(restoreWeak) end)
    end)
end

NZA.Bus.On('self:revived', function()
    if weakUntil > 0 then weakUntil = 0 end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if weakThread then weakOn(false) end
end)

CreateThread(function()
    Wait(6000)
    if NetworkIsPlayerActive(PlayerId()) then restoreWeak() end
end)
