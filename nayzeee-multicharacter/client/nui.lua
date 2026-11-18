if not NAYZEEE_LOCK_OK then return end

--[[
    NUI -> Lua callbacks (contract §7.2). Every reply shape is exact; slow work (cameras, scene rebuilds)
    runs in a thread so the UI never waits on it unless the contract asks for a result.
]]

-- ── UiConfig (reply of `ready`) ──────────────────────────────────────────
local function accent()
    local a = Config.UI.accent
    local list = Config.UI.accents or {}
    if type(a) == 'string' and list[a] then return list[a] end
    if type(a) == 'string' and a:sub(1, 1) == '#' then return { a, a, a } end
    for _, v in pairs(list) do return v end
    return { '#0fd4c4', '#08afa2', '#067d74' }
end

local function uiConfig()
    local themes = {}
    for _, id in ipairs(NZ.ThemeIds()) do
        local t = Config.LobbyThemes[id]
        themes[#themes + 1] = {
            id = id, label = t.label, description = t.description, icon = t.icon, category = t.category,
            palette = t.palette, mood = t.mood, moods = t.moods, inFlight = t.flight ~= nil, pets = t.pets ~= false,
        }
    end
    local moods = {}
    for _, m in ipairs(Config.Moods) do moods[#moods + 1] = { id = m.id, label = m.label, icon = m.icon, swatch = m.swatch } end
    local poses = {}
    for _, p in ipairs(Config.Poses) do
        poses[#poses + 1] = { id = p.id, label = p.label, icon = p.icon, category = p.category,
            prop = p.props ~= nil and #p.props > 0, weapon = p.weapon ~= false }
    end
    local couples = {}
    for _, c in ipairs(Config.CoupleAnimations) do couples[#couples + 1] = { id = c.id, label = c.label, icon = c.icon } end
    local pets = {}
    for _, p in ipairs(Config.Pets.list or {}) do pets[#pets + 1] = { id = p.id, label = p.label, icon = p.icon or p.kind, kind = p.kind } end

    local R, W, UI = Config.Registration, Config.WeaponShowcase, Config.UI
    return {
        version = NZ.Version,
        locale  = (NZ.Strings and NZ.Strings.ui) or {},
        ui = {
            serverName = UI.serverName, tagline = UI.tagline, logo = UI.logo, accent = accent(), accentKey = UI.accent,
            accents = UI.accents, socials = UI.socials, keys = UI.keys, scale = UI.scale, currency = UI.currency,
            dateFormat = UI.dateFormat, showOnline = UI.showOnline, nameplates = UI.nameplates,
        },
        start = Config.StartScreen,
        themes = themes,
        moods = moods,
        poses = poses,
        couplePoses = couples,
        pets = pets,
        petOptions = { enabled = Config.Pets.enabled ~= false, names = Config.Pets.names ~= false },
        scenePick = Config.Scene.playerPick ~= false,
        weapon = { mode = W.mode, allowNone = W.allowNone ~= false, allowAuto = W.allowAuto ~= false, enabled = W.enabled ~= false },
        registration = {
            nameMin = R.name.min, nameMax = R.name.max, minAge = R.dob.minAge, maxAge = R.dob.maxAge,
            height = R.height, nationality = R.nationality, backstory = R.backstory, genders = R.genders,
        },
        nationalities = Config.Nationalities or {},
        cameraModes = { 'squad', 'duo', 'body', 'face' },
        squad = { enabled = Config.Squad.enabled ~= false, maxLinks = Config.Squad.maxLinks, searchMin = Config.Squad.searchMin,
            couples = Config.Squad.couples ~= false },
        audio = { ambience = Config.Audio.ambience ~= false, uiSounds = Config.Audio.uiSounds ~= false, volume = Config.Audio.volume },
        typeToConfirm = Config.Characters.typeToConfirm ~= false,
        settings = Settings.data,
    }
end

-- ── helpers ──────────────────────────────────────────────────────────────
local function cb(name, fn)
    RegisterNUICallback(name, function(data, reply)
        local ok, res = pcall(fn, type(data) == 'table' and data or {})
        if not ok then
            print(('^1[nzm] NUI %s failed: %s^0'):format(name, res))
            res = { ok = false, msg = NZ.T('t_error') }
        end
        if res == nil then res = true end
        reply(res)
    end)
end

-- Async actions reply true right away and do their work in a thread
local function async(fn)
    return function(d)
        CreateThread(function()
            local ok, err = pcall(fn, d)
            if not ok then print(('^1[nzm] NUI async failed: %s^0'):format(err)) end
        end)
        return true
    end
end

-- Squad calls always act on the selected character; success refreshes squad + lobby actors
local function squadCall(name, ...)
    local id = Main.SelectedId()
    if not id or not Config.Squad.enabled then return { ok = false, msg = NZ.T('t_sq_disabled') } end
    local r = lib.callback.await(name, false, id, ...)
    if r and r.ok then CreateThread(Main.RefreshSquad) end
    return r or { ok = false, msg = NZ.T('t_error') }
end

-- ── callbacks ────────────────────────────────────────────────────────────
cb('ready', function()
    Main.nuiReady = true
    -- NUI reloaded (or loaded late) while the lobby is up: replay the current view
    if Main.open and Main.mode ~= 'busy' and Main.mode ~= 'boot' then
        CreateThread(function() Wait(100) Main.Resend() end)
    end
    return uiConfig()
end)

cb('startContinue', async(function() Start.Continue() end))
cb('select',  async(function(d) Main.Select(d.slot) end))
cb('camera',  async(function(d) Main.SetCamera(d.mode) end))
cb('previewPref', async(function(d) Main.PreviewPref(d.slot, d.key, d.value) end))
cb('setPref', function(d) return Main.SetPref(d.slot, d.key, d.value) end)
cb('play',    async(function(d) Main.Play(d.slot) end))

cb('spawnHover',   async(function(d) Spawn.Hover(d.id) end))
cb('spawnConfirm', function(d) return { ok = Spawn.Confirm(d.id) == true } end)

cb('createStart',  function(d) return Create.Start(d.slot) end)
cb('createGender', async(function(d) Create.Gender(d.gender) end))
cb('createCancel', async(function() Create.Cancel() end))
cb('createSubmit', function(d) return Create.Submit(d.form) end)

cb('delete', function(d) return Main.Delete(d.slot, d.confirm) end)

cb('squadSearch', function(d)
    local id = Main.SelectedId()
    local q = NZ.Trim(d.query)
    if not id or #q < (Config.Squad.searchMin or 3) and not tonumber(q) then return { results = {} } end
    local r = lib.callback.await('nzm:squad:search', false, id, q)
    return { results = type(r) == 'table' and r or {} }
end)
cb('squadRequest', function(d) return squadCall('nzm:squad:request', d.target, d.type) end)
cb('squadRespond', function(d) return squadCall('nzm:squad:respond', d.id, d.accept == true) end)
cb('squadRemove',  function(d) return { ok = squadCall('nzm:squad:remove', d.id).ok == true } end)
cb('squadSwitch',  function(d) return squadCall('nzm:squad:switch', d.id, d.type) end)
cb('squadSlot',    function(d) return { ok = squadCall('nzm:squad:slot', d.id, tonumber(d.slot)).ok == true } end)
cb('squadVisible', function(d) return { ok = squadCall('nzm:squad:visible', d.id, d.visible == true).ok == true } end)

cb('settings', function(d)
    local prev = NZ.Copy(Settings.data)
    local now = Settings.Save(d.settings or {})
    CreateThread(function()
        if prev.muted ~= now.muted or prev.ambientVolume ~= now.ambientVolume then Audio.Refresh() end
        if prev.perf ~= now.perf then Lights.Build() end
        -- sway / DoF / perf live on the camera itself: re-frame so the new look applies
        if (prev.sway ~= now.sway or prev.dof ~= now.dof or prev.perf ~= now.perf)
            and Main.open and not Main.busy and (Main.mode == 'lobby' or Main.mode == 'create') then
            Cam.Mode(Main.camera, 400)
        end
    end)
    return now
end)

cb('sound', function(d) Audio.Play(d.name) return true end)
cb('redeem', function(d) return Main.Redeem(NZ.Trim(d.code)) end)

cb('quit', function()
    TriggerServerEvent('nzm:server:quit')
    return true
end)
