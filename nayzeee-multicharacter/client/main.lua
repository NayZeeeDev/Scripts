if not NAYZEEE_LOCK_OK then return end

--[[
    Lobby controller (contract §6.1). Nothing here runs once the player is in the world:
    every thread ends with the lobby (0.00 resmon while playing).
    Main.mode: closed | busy | boot | start | lobby | create | spawn | cutscene
]]

Main = { veil = true,
    open = false, mode = 'closed', busy = false, nuiReady = false,
    chars = {}, bySlot = {}, byId = {}, info = {}, selected = nil, squad = nil, pending = nil,
    camera = Config.Camera.defaultMode or 'squad', preview = {},
}

local MODES = { squad = true, duo = true, body = true, face = true }
local PREVIEW_ACTOR_KEYS = { 'pose', 'couplePose', 'weapon', 'pet', 'petName' }

-- ── data ─────────────────────────────────────────────────────────────────
function Main.SetData(data)
    Main.info = data or {}
    Main.chars = Main.info.characters or {}
    Main.bySlot, Main.byId = {}, {}
    for _, c in ipairs(Main.chars) do
        Main.bySlot[c.slot] = c
        Main.byId[c.id] = c
    end
end

function Main.Reset()
    Main.chars, Main.bySlot, Main.byId, Main.info = {}, {}, {}, {}
    Main.selected, Main.squad, Main.pending, Main.preview = nil, nil, nil, {}
end

function Main.TotalSlots()
    return (Main.info.slots and Main.info.slots.total) or Config.Slots.default or 1
end

local function shown()
    local s = Main.info.slots or {}
    local max = s.max or Config.Slots.max or 8
    local used, highest = #Main.chars, 0
    for _, c in ipairs(Main.chars) do if c.slot > highest then highest = c.slot end end
    return math.min(max, math.max(highest, math.min(used + 1, Main.TotalSlots()) + (Config.Slots.showLocked or 0)))
end

function Main.SelectedChar()
    return Main.selected and Main.bySlot[Main.selected] or nil
end

function Main.SelectedId()
    local c = Main.SelectedChar()
    return c and c.id or nil
end

-- CharacterNui = Character without skin, model, weapon.components
local function charNui(c)
    local o = {}
    for k, v in pairs(c) do
        if k ~= 'skin' and k ~= 'model' then o[k] = v end
    end
    if c.weapon then o.weapon = { name = c.weapon.name, label = c.weapon.label, class = c.weapon.class, tint = c.weapon.tint } end
    return o
end

-- SquadNui = Squad without skins / models / other.prefs
function Main.SquadNui(sq)
    if not sq then return { links = {}, incoming = {}, outgoing = {} } end
    local links = {}
    for i, l in ipairs(sq.links or {}) do
        local o = l.other or {}
        links[i] = {
            id = l.id, type = l.type, slot = l.slot, visible = l.visible ~= false,
            pendingType = l.pendingType, pendingByMe = l.pendingByMe == true,
            other = {
                id = o.id, name = o.name, online = o.online == true,
                job = o.job and { label = o.job.label } or nil,
                weapon = o.weapon and { name = o.weapon.name, label = o.weapon.label, class = o.weapon.class } or nil,
            },
        }
    end
    return { links = links, incoming = sq.incoming or {}, outgoing = sq.outgoing or {} }
end

function Main.Payload()
    local list = {}
    for i, c in ipairs(Main.chars) do list[i] = charNui(c) end
    local s = Main.info.slots or {}
    return {
        characters = list,
        slots      = { total = Main.TotalSlots(), used = #Main.chars, max = s.max or Config.Slots.max, shown = shown(), base = s.base, extra = s.extra },
        selected   = Main.selected or 1,
        canDelete  = Main.info.canDelete == true,
        theme      = Scene.id,
        mood       = Lights.moodId,
        camera     = Main.camera,
        squad      = Main.SquadNui(Main.squad),
        online     = Main.info.online or 0,
        maxPlayers = Main.info.maxPlayers or 0,
    }
end

function Main.SendData() U.Send('data', Main.Payload()) end

-- Replace a character with the server's updated copy (client-only fields kept when missing)
function Main.UpdateChar(nc)
    local old = Main.byId[nc.id]
    if old then
        nc.skin = nc.skin or old.skin
        nc.model = nc.model or old.model
        for i, c in ipairs(Main.chars) do if c.id == nc.id then Main.chars[i] = nc end end
        if old.slot ~= nc.slot then Main.bySlot[old.slot] = nil end
    else
        Main.chars[#Main.chars + 1] = nc
    end
    Main.bySlot[nc.slot], Main.byId[nc.id] = nc, nc
    return nc
end

-- Theme for a character: saved pref (server sends concrete ids when playerPick is off) > job > default
function Main.ThemeFor(c)
    local t = c and c.prefs and c.prefs.theme
    if t and NZ.Theme(t) then return t end
    local job = c and c.job and c.job.name
    local auto = job and Config.Scene.autoByJob and Config.Scene.autoByJob[job]
    if auto and NZ.Theme(auto) then return auto end
    if NZ.Theme(Config.Scene.defaultTheme) then return Config.Scene.defaultTheme end
    return NZ.ThemeIds()[1]
end

function Main.MoodFor(c, themeId)
    local m = c and c.prefs and c.prefs.mood
    if m and NZ.MoodById(m) then return m end
    local theme = NZ.Theme(themeId)
    return theme and theme.mood or nil
end

function Main.FetchSquad(charId)
    if not Config.Squad.enabled or not charId then return nil end
    local ok, sq = pcall(lib.callback.await, 'nzm:squad:get', false, charId)
    return ok and sq or nil
end

-- Initial selection: Config.Characters.autoSelect ('last' = server's last played, 'favorite', 'first')
function Main.AutoSlot()
    local mode = Config.Characters.autoSelect or 'last'
    local sel = Main.info.selected and Main.byId[Main.info.selected]
    local fav
    for _, c in ipairs(Main.chars) do if c.favorite then fav = c break end end
    local first
    for _, c in ipairs(Main.chars) do if not first or c.slot < first.slot then first = c end end
    local pick
    if mode == 'favorite' then pick = fav or sel or first
    elseif mode == 'first' then pick = first
    else pick = sel or fav or first end
    if pick then return pick.slot end
    for s = 1, Main.TotalSlots() do if not Main.bySlot[s] then return s end end
    return 1
end

-- ── presentation ─────────────────────────────────────────────────────────
-- Copy live previews back onto the actors after a rebuild
local function reapplyPreview()
    local any = false
    for _, k in ipairs(PREVIEW_ACTOR_KEYS) do
        if Main.preview[k] ~= nil then Actors.preview[k] = Main.preview[k] any = true end
    end
    if not any then return end
    Actors.Refresh()
    if Main.preview.pet ~= nil then Actors.SpawnPet() end
end

-- Show a slot (blocking). Theme differs (or force) -> fade + rebuild, else walk-in swap.
function Main.Present(slot, force, keepPreview)
    local c = Main.bySlot[slot]
    if Main.selected ~= slot or not keepPreview then Main.preview = {} end
    Main.selected = slot
    local squad = c and Main.FetchSquad(c.id) or nil
    Main.squad = squad
    local themeId = (keepPreview and Main.preview.theme) or (c and Main.ThemeFor(c)) or Scene.id or Main.ThemeFor(nil)
    local mood = (keepPreview and Main.preview.mood) or Main.MoodFor(c, themeId)
    local lobby = Main.mode == 'lobby' or Main.mode == 'create'

    if force or themeId ~= Scene.id or not Scene.loaded then
        -- Rebuild under a frozen frame of the current scene (crossfade), or fade through black if capture isn't available
        local frozen = lobby and not IsScreenFadedOut() and U.Freeze()
        local fade = not frozen and not IsScreenFadedOut()
        if fade then U.FadeOut(350) end
        Scene.Load(themeId, mood)
        if c then Actors.Show(c, squad) else Actors.Ghost('m', false) end
        if keepPreview then reapplyPreview() end
        Lights.Start()
        if Main.mode ~= 'start' and Main.mode ~= 'boot' then Audio.Theme(Scene.id) end
        if lobby then Cam.Mode(Main.camera, 0) end
        if frozen then Wait(200) U.Unfreeze(1000)
        elseif fade then Wait(150) U.FadeIn(500) end
    else
        if mood ~= Lights.moodId then Lights.SetMood(mood) end
        if c then Actors.SwapMain(c, squad) else Actors.Ghost('m', false) end
        if lobby then Cam.Mode(Main.camera, Config.Camera.transition) end
        local deadline = GetGameTimer() + 5000
        while Actors.walking and GetGameTimer() < deadline do Wait(50) end
    end
    U.Send('squad', Main.SquadNui(squad))
    Main.SendData()
end

function Main.Select(slot)
    slot = tonumber(slot)
    if not slot or not Main.open then return end
    local fromCreate = false
    if Main.mode == 'create' and not Main.busy then
        Create.slot, Create.prev = nil, nil
        Main.mode = 'lobby'
        fromCreate = true
        if not Main.bySlot[slot] then Main.selected = nil end
    end
    if Main.mode ~= 'lobby' then return end
    if Main.busy then
        -- Another operation (theme rebuild, delete...) owns the scene: wait for it, then apply the latest pick
        Main.pending = slot
        if Main.selWait then return end
        Main.selWait = true
        local deadline = GetGameTimer() + 10000
        while Main.busy and GetGameTimer() < deadline do Wait(50) end
        Main.selWait = false
        local p = Main.pending
        Main.pending = nil
        if p and Main.mode == 'lobby' then return Main.Select(p) end
        return
    end
    local c = Main.bySlot[slot]
    if not c then
        -- Empty unlocked slot -> creation silhouette; locked -> ignore
        if slot <= Main.TotalSlots() then Create.Start(slot) end
        return
    end
    if slot == Main.selected and Actors.char and Actors.char.id == c.id then return end
    Main.busy = true
    U.Send('select', { slot = slot })
    local ok, err = pcall(Main.Present, slot)
    if not ok then print(('^1[nzm] select failed: %s^0'):format(err)) end
    if fromCreate then
        U.Send('lobby', Main.Payload())
        U.Send('squad', Main.SquadNui(Main.squad))
    end
    Main.busy = false
    local p = Main.pending
    Main.pending = nil
    if p and p ~= Main.selected then Main.Select(p) end
end

function Main.SetCamera(mode)
    if not MODES[mode] then return end
    Main.camera = mode
    U.Send('camera', { mode = mode })
    if Main.open and not Main.busy and (Main.mode == 'lobby' or Main.mode == 'create') then
        Cam.Mode(mode, Config.Camera.transition)
    elseif Main.open and Main.busy then
        CreateThread(function()
            local deadline = GetGameTimer() + 10000
            while Main.busy and Main.open and GetGameTimer() < deadline do Wait(50) end
            if Main.camera == mode and not Main.busy and (Main.mode == 'lobby' or Main.mode == 'create') then Cam.Mode(mode, Config.Camera.transition) end
        end)
    end
end

-- ── prefs ────────────────────────────────────────────────────────────────
local function applyPref(key, c)
    if not Main.open or Main.SelectedId() ~= c.id then return end
    if key == 'theme' then
        local deadline = GetGameTimer() + 15000
        while Main.busy and GetGameTimer() < deadline do Wait(50) end
        c = Main.byId[c.id] or c
        if not Main.open or Main.SelectedId() ~= c.id or Main.busy then return end
        if Main.ThemeFor(c) ~= Scene.id then
            Main.busy = true
            Main.Present(c.slot, true)
            Main.busy = false
        end
    elseif key == 'mood' then
        Lights.SetMood(Main.MoodFor(c, Scene.id))
        Main.SendData()
    else
        Actors.SetChar(c, key)
        if key == 'couplePose' and Main.camera == 'duo' then Cam.Mode('duo', Config.Camera.transition) end
    end
end

function Main.SetPref(slot, key, value)
    local c = Main.bySlot[tonumber(slot)]
    if not c then return { ok = false, msg = NZ.T('t_error') } end
    local res = lib.callback.await('nzm:pref', false, c.id, key, value)
    if not res or not res.ok then return { ok = false, msg = res and res.msg or NZ.T('t_error') } end
    local nc = res.character and Main.UpdateChar(res.character) or c
    if key == 'favorite' and NZ.Truthy(value) then
        for _, o in ipairs(Main.chars) do if o.id ~= nc.id then o.favorite = false end end
    end
    Main.preview[key] = nil
    CreateThread(function()
        applyPref(key, nc)
        Main.SendData()
    end)
    return { ok = true, msg = res.msg }
end

-- Live preview (not saved). value = nil reverts to the saved value.
function Main.PreviewPref(slot, key, value)
    slot = tonumber(slot)
    local c = slot and Main.bySlot[slot]
    if not c or slot ~= Main.selected or Main.mode ~= 'lobby' then return end
    Main.preview[key] = value
    if key == 'theme' then
        if not Config.Scene.playerPick then return end
        local t = (value and NZ.Theme(value)) and value or Main.ThemeFor(c)
        if t ~= Scene.id and not Main.busy then
            Main.busy = true
            Main.Present(slot, true, true)
            Main.busy = false
        end
    elseif key == 'mood' then
        if not Config.Scene.playerPick then return end
        Lights.SetMood(value or Main.MoodFor(c, Scene.id))
    else
        Actors.Preview(1, key, value)
        if key == 'couplePose' and Main.camera == 'duo' then Cam.Mode('duo', Config.Camera.transition) end
    end
end

-- ── actions ──────────────────────────────────────────────────────────────
function Main.Play(slot)
    local c = Main.bySlot[tonumber(slot)]
    if not c or Main.mode ~= 'lobby' or Main.busy then return end
    if c.slot ~= Main.selected then return U.Send('select', { slot = Main.selected }) end
    Main.busy = true
    -- an unsaved hover preview must not ride into the departure
    if next(Main.preview) or next(Actors.preview) then
        local pv = Main.preview
        local hadPet = Actors.preview.pet ~= nil
        Main.preview, Actors.preview = {}, {}
        if pv.theme and Main.ThemeFor(c) ~= Scene.id then
            pcall(Main.Present, c.slot, true)
        else
            if pv.mood then Lights.SetMood(Main.MoodFor(c, Scene.id)) end
            pcall(Actors.Refresh)
            if hadPet then pcall(Actors.SpawnPet) end
        end
    end
    U.Send('busy', { on = true })
    local res = lib.callback.await('nzm:play', false, c.id)
    if not res or not res.ok then
        Main.busy = false
        U.Send('busy', { on = false })
        return U.Send('toast', { type = 'error', text = res and res.msg or NZ.T('t_error') })
    end
    Appearance.ApplyPlayer(res.skin or c.skin, res.model or c.model, res.gender or c.gender)
    Scene.ParkPlayer()            -- SetPlayerModel spawned a new, visible ped
    U.Send('busy', { on = false })
    Spawn.Begin(c.id, res.spawn, res.mode, false)
end

function Main.Delete(slot, confirm)
    local c = Main.bySlot[tonumber(slot)]
    if not c or Main.busy or Main.mode ~= 'lobby' then return { ok = false } end
    local res = lib.callback.await('nzm:delete', false, c.id, confirm)
    if not res or not res.ok then return { ok = false, msg = res and res.msg or NZ.T('t_error') } end
    local wasSelected = c.slot == Main.selected
    CreateThread(function()
        Main.busy = true
        local data = lib.callback.await('nzm:refresh', false)
        if data and not data.error then
            Main.SetData(data)
        else
            for i, o in ipairs(Main.chars) do if o.id == c.id then table.remove(Main.chars, i) break end end
            Main.bySlot[c.slot], Main.byId[c.id] = nil, nil
        end
        if wasSelected then Main.Present(Main.AutoSlot(), false) else Main.SendData() end
        Main.busy = false
    end)
    return { ok = true, msg = res.msg or NZ.T('t_deleted') }
end

function Main.Redeem(code)
    local r = lib.callback.await('nzm:redeem', false, code)
    if r and r.ok then
        CreateThread(function()
            local data = lib.callback.await('nzm:refresh', false)
            if data and not data.error then
                Main.SetData(data)
                Main.SendData()
            end
        end)
    end
    return { ok = r and r.ok == true, msg = r and r.msg or NZ.T('t_error') }
end

-- Squad changed (NUI action or server event): refetch, rebuild slots 2..4, tell the UI
function Main.RefreshSquad()
    local id = Main.SelectedId()
    if not id then return end
    local sq = Main.FetchSquad(id)
    if Main.SelectedId() ~= id then return end
    Main.squad = sq
    if Main.mode == 'lobby' and Actors.char and Actors.char.id == id then
        local deadline = GetGameTimer() + 5000
        while Actors.walking and GetGameTimer() < deadline do Wait(50) end
        Actors.SetSquad(sq)
    end
    U.Send('squad', Main.SquadNui(sq))
end

-- ── boot / open ──────────────────────────────────────────────────────────
function Main.WaitNui()
    local deadline = GetGameTimer() + 15000
    while not Main.nuiReady and GetGameTimer() < deadline do Wait(50) end
end

local function preparePlayer()
    local model = `mp_m_freemode_01`
    if not IsPedModel(PlayerPedId(), model) and not IsPedModel(PlayerPedId(), `mp_f_freemode_01`) then
        U.Model(model)
        SetPlayerModel(PlayerId(), model)
        SetPedDefaultComponentVariation(PlayerPedId())
        SetModelAsNoLongerNeeded(model)
    end
    local c = Config.Creation.coords
    if IsEntityDead(PlayerPedId()) or not Main.booted then
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, c.w or 0.0, true, false)
    end
    Main.booted = true
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    U.HidePlayer()
end

function Main.Boot(relog)
    if Main.open then return end
    Main.open, Main.mode, Main.busy = true, 'busy', true
    U.FadeOut(relog and 500 or 0)
    ClientBridge.Hud(false)
    ClientBridge.DisableAutoSpawn()

    local data = lib.callback.await('nzm:boot', false)
    if not data or data.error or data.loaded then
        Main.open, Main.mode, Main.busy = false, 'closed', false
        if data and data.error then print(('^1[nzm] boot failed: %s^0'):format(data.error)) end
        Main.veil = false
        ClientBridge.LoadingScreenOff()
        ClientBridge.Hud(true)
        U.Veil(false, 0)
        U.FadeIn(300)
        return
    end

    Main.SetData(data)
    Main.preview, Main.pending, Main.camera = {}, nil, Config.Camera.defaultMode or 'squad'
    preparePlayer()
    World.PauseSync(true)
    Main.mode = 'boot'
    Main.Present(Main.AutoSlot(), true)
    Plates.Start()
    Main.busy = false
    if Config.StartScreen.enabled and not relog then
        Start.Show()
    else
        Main.OpenLobby(false)
    end
end

-- Loading screen -> lobby hand-off. The UI veil (black) covers the swap, the scene starts rendering underneath,
-- then the veil dissolves over the live camera. Also used after /relog (screen already black).
function Main.Reveal(ms)
    Main.WaitNui()
    U.Veil(true, 0)
    Wait(80)
    ClientBridge.LoadingScreenOff()
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(0) end
    Wait(150)                                   -- a few frames of the scene render under the veil
    Main.veil = false
    U.Veil(false, ms or 1600)
end

local function sendLobby()
    U.Send('settings', Settings.data)
    U.Send('lobby', Main.Payload())
    U.Send('squad', Main.SquadNui(Main.squad))
end

function Main.OpenLobby(fromStart)
    Main.mode = 'lobby'
    Main.WaitNui()
    Audio.Theme(Scene.id)
    SetNuiFocus(true, true)
    if fromStart then
        -- The camera glides from the title shot into the lobby; the UI leads it, sliding in before the glide lands
        local glide = Config.Camera.introTime or 3200
        local lead = math.min(Config.StartScreen.interfaceLead or 900, glide)
        CreateThread(function()
            Wait(glide - lead)
            if Main.mode == 'lobby' or Main.mode == 'create' then sendLobby() end
        end)
        Cam.Mode(Main.camera, glide)
    else
        U.Veil(true, 0)
        sendLobby()
        Cam.Mode(Main.camera, 0)
        Main.Reveal(1200)
    end
    -- No character yet: straight into the creation silhouette
    if not Main.SelectedChar() and Main.selected and Main.selected <= Main.TotalSlots() then
        Create.Start(Main.selected)
    end
end

-- NUI (re)loaded while the lobby is open: send the current view again
function Main.Resend()
    if not Main.open then return end
    U.Send('settings', Settings.data)
    if Main.mode == 'lobby' then
        U.Send('lobby', Main.Payload())
        U.Send('squad', Main.SquadNui(Main.squad))
        Audio.Theme(Scene.id)
    elseif Main.mode == 'create' and Create.slot then
        U.Send('lobby', Main.Payload())
        U.Send('create', { slot = Create.slot })
    elseif Main.mode == 'start' and Start.payload then
        U.Send('veil', { on = Main.veil ~= false, ms = 0 })
        U.Send('start', Start.payload)
    elseif Main.mode == 'spawn' and Spawn.list then
        U.Send('spawn', { options = Spawn.list, selected = Spawn.list[1] and Spawn.list[1].id })
    end
end

-- ── entry points ─────────────────────────────────────────────────────────
CreateThread(function()
    -- Black from the first frame: if the loading screen closes on its own, nobody sees the world before the lobby
    DoScreenFadeOut(0)
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    Wait(250)
    Main.Boot(false)
end)

RegisterNetEvent('nzm:client:open', function()
    CreateThread(function()
        if Editor and Editor.active then Editor.Stop() end
        Main.Boot(true)
    end)
end)

RegisterNetEvent('nzm:client:relogPrepare', function()
    U.FadeOut(500)
    ClientBridge.Hud(false)
end)

RegisterNetEvent('nzm:client:notify', function(msg, kind)
    if Main.open and Main.mode ~= 'closed' then return U.Send('toast', { type = kind or 'info', text = msg }) end
    ClientBridge.Notify(msg, kind)
end)

RegisterNetEvent('nzm:client:squadChanged', function(charId)
    if not Main.open or Main.SelectedId() ~= charId then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 8000
        while Main.busy and GetGameTimer() < deadline do Wait(100) end
        Main.RefreshSquad()
    end)
end)

-- Online target of a squad / couple request while PLAYING (the lobby UI shows its own inbox)
RegisterNetEvent('nzm:client:squadInvite', function(fromName, kind, linkId)
    if Main.open then return end
    CreateThread(function()
        local label = NZ.T(kind == 'couple' and 'sq_couple' or 'sq_squad')
        local r = lib.alertDialog({
            header = label,
            content = NZ.T('t_sq_got_prompt', fromName or '?', label),
            centered = true,
            cancel = true,
        })
        TriggerServerEvent('nzm:server:squadAnswer', linkId, r == 'confirm')
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZ.Resource or not Main.open then return end
    SetNuiFocus(false, false)
    Plates.on, Start.orbiting = false, false
    Cutscene.Stop()
    Scene.Teardown()
    Cam.Stop()
    Lights.Stop()
    World.Restore()
    World.PauseSync(false)
    U.ShowPlayer()
    ClientBridge.Hud(true)
    DoScreenFadeIn(0)
end)
