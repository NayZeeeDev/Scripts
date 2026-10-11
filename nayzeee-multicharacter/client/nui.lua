if not NAYZEEE_LOCK_OK then return end

-- Static config for the UI, sent once when the NUI reports ready
local function uiConfig()
    local scenes = {}
    for _, s in ipairs(Config.Scenes) do scenes[#scenes + 1] = { id = s.id, label = s.label } end
    local poses = {}
    for _, p in ipairs(Config.Poses) do poses[#poses + 1] = { id = p.id, label = p.label } end
    local shop = {}
    for _, it in ipairs(Config.StarterShop.items) do
        shop[#shop + 1] = { key = it.type .. ':' .. it.name, type = it.type, name = it.name, label = it.label, price = it.price, max = it.max or 1,
            image = it.image or (it.type == 'item' and Config.StarterShop.imagePath:format(it.name) or nil) }
    end
    local R = Config.Registration
    return {
        version  = NZ.Version,
        locale   = NZ.Strings,
        ui       = Config.UI,
        fields   = Config.Characters.fields,
        typeToConfirm = Config.Characters.typeToConfirm,
        reg = {
            nameMin = R.name.min, nameMax = R.name.max, blacklist = R.name.blacklist,
            minAge = R.dob.minAge, maxAge = R.dob.maxAge,
            height = R.height, nationality = R.nationality, backstory = R.backstory, genders = R.genders,
        },
        nationalities = Config.Nationalities,
        poses    = poses,
        scenes   = scenes,
        scenePick = Config.Scene.playerPick,
        weathers = Config.World.weathers,
        filters  = Config.World.filters,
        music    = Config.Music,
        shop     = { enabled = Config.StarterShop.enabled, budget = Config.StarterShop.budget, items = shop, refund = Config.StarterShop.refundLeftover },
        settings = Settings.data,
        partner  = Config.Partner.enabled,
    }
end

local function cb(name, fn)
    RegisterNUICallback(name, function(data, reply)
        local ok, res = pcall(fn, data or {})
        if not ok then
            print(('^1[nzm] NUI %s failed: %s^0'):format(name, res))
            res = false
        end
        reply(res == nil and true or res)
    end)
end

-- Async actions reply right away and do their camera work in a thread
local function async(fn) return function(d) CreateThread(function() fn(d) end) return true end end

cb('ready', function() return uiConfig() end)
cb('select',   async(function(d) Main.Select(d.slot, d.focus ~= false) end))
cb('overview', async(function() if Main.mode == 'focus' then Main.Overview() end end))
cb('play',     async(function(d) Main.Play(d.slot) end))
cb('delete',   function(d) return Main.Delete(d.slot, d.confirm) end)
cb('meta',     function(d) return Main.Meta(d.slot, d.key, d.value) end)
cb('posePreview', function(d) Scene.PreviewPose(tonumber(d.slot), d.pose) return true end)

cb('createStart',  function(d) return Create.Start(d.slot) end)
cb('createGender', async(function(d) Create.Gender(d.gender) end))
cb('createCancel', async(function() Create.Cancel() end))
cb('createSubmit', function(d) return Create.Submit(d.form or {}) end)

cb('shopConfirm', function(d) return Create.Shop(d.cart or {}) end)
cb('shopSkip',    function() return Create.ShopSkip() end)

cb('spawnHover',   async(function(d) Spawn.Hover(d.id) end))
cb('spawnConfirm', function(d) return Spawn.Confirm(d.id) end)

cb('settings', function(d)
    local prev = NZ.Copy(Settings.data)
    Settings.Save(d.settings or {})
    CreateThread(function() Main.ApplySettings(prev) end)
    return Settings.data
end)
cb('settingsReset', function()
    local prev = NZ.Copy(Settings.data)
    Settings.Reset()
    CreateThread(function() Main.ApplySettings(prev) end)
    return Settings.data
end)

cb('redeem', function(d)
    local r = lib.callback.await('nzm:redeem', false, d.code)
    if r and r.ok and r.data then CreateThread(function() Main.Refresh(r.data) end) end
    return { ok = r and r.ok, msg = r and r.msg }
end)

cb('quit', function()
    TriggerServerEvent('nzm:server:quit')
    return true
end)

-- Re-project nameplates if the NUI resized
cb('replate', function()
    if Main.mode == 'overview' then U.Send('plates', { items = Scene.Plates() }) end
    return true
end)
