-- Panel boot payload.
NZ.Route('boot', 'view', function(src)
    local types = {}
    for _, t in ipairs(Config.Logs.Types) do types[#types + 1] = t end
    local bridge
    local E = Inv.a.editor
    if Config.Editor.enabled and type(E) == 'table' and E.bridge then
        local ok, info = pcall(E.bridge)
        if ok then bridge = info end
    end
    return {
        version = NZ.Version,
        me = { id = src, name = GetPlayerName(src), perms = NZ.Perms(src) },
        server = GetConvar('sv_projectName', GetConvar('sv_hostname', 'FiveM server')):gsub('%^%d', ''),
        framework = NZ.Framework,
        oxFramework = NZ.OxFramework,
        inventory = Inv.Info(),
        bridge = bridge,
        types = types,
        colors = Config.Logs.Colors,
        perPage = Config.Logs.PerPage,
        liveSeconds = Config.Logs.LiveRefreshSeconds,
        imagepath = Inv.ImagePath(),
        editor = Config.Editor.enabled and type(Inv.a.editor) == 'table',
        rollback = Config.Rollback.enabled,
        globalMax = Config.GlobalActions.maxGive,
        ui = Config.UI,
        remoteView = Config.AllowRemoteView,
        prefs = NZ.GetPrefs(src),
        notifyEnabled = Config.NotifyStaff,
    }
end)

NZ.Route('me:coords', 'editor', function(src)
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    return { x = NZ.Round(c.x, 2), y = NZ.Round(c.y, 2), z = NZ.Round(c.z, 2), w = NZ.Round(GetEntityHeading(ped), 1) }
end)

NZ.Route('prefs:set', 'view', function(src, d)
    return NZ.SetPrefs(src, d)
end)
