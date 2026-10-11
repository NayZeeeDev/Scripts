if not NAYZEEE_LOCK_OK then return end
if not Config.Doctor then return end

-- Install report: catches the setup mistakes that break multicharacter scripts
CreateThread(function()
    Wait(4000)
    local problems, notes = {}, {}

    if NZ.Framework == 'none' then problems[#problems + 1] = 'No framework found (es_extended, qb-core or qbx_core).' end
    for _, dep in ipairs({ 'ox_lib', 'oxmysql' }) do
        if GetResourceState(dep) ~= 'started' then problems[#problems + 1] = dep .. ' is not started before this resource.' end
    end
    for _, res in ipairs(ServerConfig.Conflicts) do
        local st = GetResourceState(res)
        if st == 'started' or st == 'starting' then problems[#problems + 1] = ('"%s" is running. Stop or remove it; two multicharacters fight over the same player.'):format(res) end
    end

    if NZ.IsESX then
        local deadline = GetGameTimer() + 10000
        while not Bridge.Ready() and GetGameTimer() < deadline do Wait(200) end
        local mc = Bridge.MulticharEnabled and Bridge.MulticharEnabled()
        if mc == false then
            problems[#problems + 1] = 'ESX multicharacter mode is OFF. In es_extended config set Config.Multichar = true, then restart.'
        elseif mc == nil then
            notes[#notes + 1] = 'Could not read ESX Config.Multichar. Make sure it is true.'
        end
    elseif NZ.IsQbox then
        notes[#notes + 1] = 'Qbox: set characters.useExternalCharacters = true in qbx_core/config/client.lua.'
    end

    if ServerConfig.Logs.enabled and GetConvar(ServerConfig.Logs.convar, '') == '' then
        notes[#notes + 1] = ('Logs are enabled but the "%s" convar is empty.'):format(ServerConfig.Logs.convar)
    end
    if ServerConfig.Tebex.enabled and GetConvar(ServerConfig.Tebex.convar, '') == '' then
        notes[#notes + 1] = ('Tebex redeem is enabled but "%s" is not set.'):format(ServerConfig.Tebex.convar)
    end
    if Config.Slots.discord.enabled and GetConvar(ServerConfig.DiscordTokenConvar, '') == '' then
        notes[#notes + 1] = ('Discord role slots are enabled but "%s" is not set.'):format(ServerConfig.DiscordTokenConvar)
    end

    print(('^6[nayzeee-multicharacter]^7 v%s  framework: ^5%s^7'):format(NZ.Version, NZ.Framework))
    if #problems == 0 then
        print('^2  Install looks good.^7')
    else
        for _, p in ipairs(problems) do print('^1  x ' .. p .. '^7') end
    end
    for _, n in ipairs(notes) do print('^3  ! ' .. n .. '^7') end
end)
