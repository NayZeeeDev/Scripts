if not NAYZEEE_LOCK_OK then return end

--[[
    Selection controller. Nothing here runs once the player is in the world:
    every thread ends when the selection closes (0.00 resmon while playing).
]]

Main = { open = false, mode = 'closed', chars = {}, bySlot = {}, byId = {}, total = 0, shown = 0, selected = nil, info = {} }

local S = Config.Scene

-- ── data ─────────────────────────────────────────────────────────────────
local function forNui(c)
    local o = {}
    for k, v in pairs(c) do
        if k ~= 'skin' and k ~= 'model' then o[k] = v end
    end
    if c.partner then o.partner = { name = c.partner.name, type = c.partner.type } end
    o.headshot = Scene.shotUrl[c.slot]
    return o
end

function Main.SetData(data)
    Main.chars = data.characters or {}
    Main.bySlot, Main.byId = {}, {}
    local highest = 0
    for _, c in ipairs(Main.chars) do
        Main.bySlot[c.slot] = c
        Main.byId[c.id] = c
        if c.slot > highest then highest = c.slot end
    end
    Main.info = data
    Main.total = data.slots.total
    Main.shown = math.min(Config.Slots.max, math.max(highest, Main.total + (Config.Slots.showLocked or 0)))
    Main.shown = math.max(Main.shown, highest)
end

local function autoSelect()
    local pick
    local mode = Config.Characters.autoSelect
    for _, c in ipairs(Main.chars) do
        if mode == 'favorite' and c.favorite then return c.slot end
        if mode == 'last' and (c.lastPlayed or 0) > ((pick and pick.lastPlayed) or -1) then pick = c end
    end
    if pick then return pick.slot end
    if Main.chars[1] then return Main.chars[1].slot end
    return 1
end

function Main.Payload()
    local list = {}
    for _, c in ipairs(Main.chars) do list[#list + 1] = forNui(c) end
    return {
        characters = list,
        slots      = Main.info.slots,
        total      = Main.total,
        shown      = Main.shown,
        selected   = Main.selected,
        canDelete  = Main.info.canDelete,
        online     = Main.info.online,
        maxPlayers = Main.info.maxPlayers,
        tebex      = Main.info.tebex,
        page       = Scene.page,
        perPage    = Scene.def and #Scene.def.positions or 1,
    }
end

local function pageOf(slot)
    return (NZ.PageOf(slot, #Scene.def.positions))
end

-- ── camera states ────────────────────────────────────────────────────────
function Main.Overview(ms)
    Main.mode = 'overview'
    U.Send('plates', { items = {} })
    if Scene.partner then U.Delete(Scene.partner.ped) Scene.partner = nil end
    local o = Scene.def.overview
    if not Cam.Go({ coords = o.coords, pointAt = o.pointAt, rot = o.rot, fov = o.fov }, ms or S.focusTime) then return end
    if Config.UI.nameplates and Main.mode == 'overview' then
        Wait(60)
        U.Send('plates', { items = Scene.Plates() })
    end
end

local function showPage(page)
    if Scene.page == page then return end
    U.Send('plates', { items = {} })
    U.FadeOut(220)
    Scene.Page(page, Main.bySlot, Main.total, Main.shown)
    Wait(120)
    U.FadeIn(260)
    Scene.Headshots()
end

function Main.Select(slot, focus)
    if Main.mode == 'busy' or Main.mode == 'create' then return end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > Main.shown then return end
    Main.selected = slot
    U.Send('select', { slot = slot })
    local page = pageOf(slot)
    local changed = page ~= Scene.page
    showPage(page)
    if focus == false then
        if changed then Main.Overview(0) end
        return
    end
    local ped, pos = Scene.PedOf(slot)
    if not ped then return Main.Overview() end
    Main.mode = 'focus'
    U.Send('plates', { items = {} })
    Scene.Partner(slot)
    Cam.Go(Cam.Focus(ped, pos.camera), changed and 0 or S.focusTime)
end

-- ── open / close ─────────────────────────────────────────────────────────
local function preparePlayer(def)
    local a = def.anchor
    local model = `mp_m_freemode_01`
    U.Model(model)
    if GetEntityModel(PlayerPedId()) ~= model then
        SetPlayerModel(PlayerId(), model)
        SetPedDefaultComponentVariation(PlayerPedId())
    end
    SetModelAsNoLongerNeeded(model)
    NetworkResurrectLocalPlayer(a.x, a.y, a.z, a.w or 0.0, true, false)
    ClearPedTasksImmediately(PlayerPedId())
    RemoveAllPedWeapons(PlayerPedId(), true)
end

function Main.Open(relog)
    if Main.open then return end
    Main.open, Main.mode = true, 'busy'
    U.FadeOut(relog and 500 or 0)
    ClientBridge.Hud(false)
    if GetResourceState('spawnmanager') == 'started' then pcall(function() exports.spawnmanager:setAutoSpawn(false) end) end

    local data = lib.callback.await('nzm:boot', false)
    if not data or data.loaded or data.error then
        Main.open, Main.mode = false, 'closed'
        if data and data.loaded then
            ClientBridge.Hud(true)
            U.FadeIn(300)
        end
        return
    end

    Main.SetData(data)
    local def = Scene.Pick()
    preparePlayer(def)
    World.PauseSync(true)
    Scene.Build(def)
    Main.selected = autoSelect()
    Scene.Page(pageOf(Main.selected), Main.bySlot, Main.total, Main.shown)

    -- Intro glide
    local o = def.overview
    local intro = def.intro or { coords = o.coords, pointAt = o.pointAt, rot = o.rot, fov = math.min(o.fov + 20.0, 80.0) }
    Cam.Go(intro, 0)
    ClientBridge.LoadingScreenOff()

    U.Send('open', Main.Payload())
    SetNuiFocus(true, true)
    U.FadeIn(900)
    Scene.Headshots()

    if S.intro then
        if Config.UI.welcome.enabled then U.Send('welcome', Config.UI.welcome) end
        Cam.Go({ coords = o.coords, pointAt = o.pointAt, rot = o.rot, fov = o.fov }, S.introTime)
    end
    Main.Overview(0)
end

-- Close the selection UI and release everything (called right before the player enters the world)
function Main.Close()
    Main.open, Main.mode = false, 'closed'
    SetNuiFocus(false, false)
    U.Send('close', {})
    Scene.Teardown()
    Spawn.Clear()
    Main.chars, Main.bySlot, Main.byId = {}, {}, {}
end

-- ── actions ──────────────────────────────────────────────────────────────
function Main.Play(slot)
    local c = Main.bySlot[tonumber(slot)]
    if not c or Main.mode == 'busy' then return end
    local prevMode = Main.mode
    Main.mode = 'busy'
    U.Send('busy', { on = true })
    local res = lib.callback.await('nzm:play', false, c.id)
    if not res or not res.ok then
        Main.mode = prevMode
        U.Send('busy', { on = false })
        return U.Send('toast', { type = 'error', text = res and res.msg or NZ.T('t_error') })
    end
    Appearance.ApplyPlayer(res.skin, res.model, res.gender)
    Spawn.Begin(c.id, res.spawn, res.mode, false)
end

function Main.Refresh(data)
    Main.SetData(data)
    if Main.selected and Main.selected > Main.shown then Main.selected = 1 end
    local page = pageOf(Main.selected or 1)
    Scene.Page(page, Main.bySlot, Main.total, Main.shown)
    Scene.Headshots()
    U.Send('data', Main.Payload())
end

function Main.Delete(slot, typed)
    local c = Main.bySlot[tonumber(slot)]
    if not c then return { ok = false } end
    local res = lib.callback.await('nzm:delete', false, c.id, typed)
    if res and res.ok then
        Scene.shotUrl[c.slot] = nil
        U.FadeOut(200)
        Main.Refresh(res.data)
        U.FadeIn(300)
        Main.Overview(0)
        return { ok = true, msg = NZ.T('t_deleted') }
    end
    return { ok = false, msg = res and res.msg or NZ.T('t_error') }
end

function Main.Meta(slot, key, value)
    local c = Main.bySlot[tonumber(slot)]
    if not c then return false end
    local ok = lib.callback.await('nzm:meta', false, c.id, key, value)
    if not ok then return false end
    if key == 'pose' then
        c.pose = value
        Scene.PreviewPose(c.slot, value)
    elseif key == 'favorite' then
        for _, o in ipairs(Main.chars) do o.favorite = false end
        c.favorite = value == true
    elseif key == 'backstory' then
        c.backstory = value ~= '' and value or nil
    elseif key == 'partner' then
        c.partner = nil
        if Scene.partner then U.Delete(Scene.partner.ped) Scene.partner = nil end
        local e = Scene.peds[c.slot]
        if e then e.char = c end
    end
    U.Send('data', Main.Payload())
    return true
end

-- Rebuild everything with the current settings (scene / weather / filter changed)
function Main.ApplySettings(prev)
    local now = Settings.data
    U.Send('settings', now)
    if not Main.open or not Scene.def then return end
    if prev.scene ~= now.scene and Config.Scene.playerPick then
        local def = Scene.Pick()
        if def ~= Scene.def then
            U.FadeOut(300)
            Scene.Teardown()
            preparePlayer(def)
            Scene.Build(def)
            Scene.Page(pageOf(Main.selected or 1), Main.bySlot, Main.total, Main.shown)
            U.Send('data', Main.Payload())
            Main.Overview(0)
            U.FadeIn(500)
            Scene.Headshots()
            return
        end
    end
    Scene.Weather()
    Scene.Filter()
    if prev.distance ~= now.distance and Main.mode == 'focus' and Main.selected then
        Main.Select(Main.selected)
    end
end

-- ── entry points ─────────────────────────────────────────────────────────
CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    Wait(250)
    Main.Open(false)
end)

RegisterNetEvent('nzm:client:open', function()
    Main.Open(true)
end)

RegisterNetEvent('nzm:client:relogPrepare', function()
    U.FadeOut(500)
    ClientBridge.Hud(false)
end)

RegisterNetEvent('nzm:client:notify', function(msg, kind)
    if Main.open then return U.Send('toast', { type = kind, text = msg }) end
    ClientBridge.Notify(msg, kind)
end)

RegisterNetEvent('nzm:client:partnerInvite', function(fromName, kind)
    local r = lib.alertDialog({ header = NZ.T('partner'), content = NZ.T('t_partner_got', fromName, kind), centered = true, cancel = true })
    TriggerServerEvent('nzm:server:partnerAnswer', r == 'confirm')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.Resource or not Main.open then return end
    SetNuiFocus(false, false)
    Cam.Stop(false)
    Scene.Teardown()
    World.Restore()
    World.PauseSync(false)
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(0)
end)
