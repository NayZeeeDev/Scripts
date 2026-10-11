-- Discord avatars for player cards (optional, needs a bot token + guild id).
local cache = {}

function GetDiscordAvatar(discordId)
    local D = Config.Discord
    if not D or not D.enabled or D.botToken == '' or D.guildId == '' or not discordId then return nil end
    local hit = cache[discordId]
    if hit and os.time() - hit.time < (D.cacheSeconds or 600) then return hit.url end
    cache[discordId] = { url = hit and hit.url or nil, time = os.time() }
    PerformHttpRequest(('https://discord.com/api/v10/guilds/%s/members/%s'):format(D.guildId, discordId), function(code, body)
        if code ~= 200 or not body then return end
        local data = json.decode(body)
        if not data or not data.user then return end
        local hash = data.avatar or data.user.avatar
        local url
        if hash then
            local ext = hash:sub(1, 2) == 'a_' and 'gif' or 'png'
            if data.avatar then
                url = ('https://cdn.discordapp.com/guilds/%s/users/%s/avatars/%s.%s?size=64'):format(D.guildId, data.user.id, hash, ext)
            else
                url = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=64'):format(data.user.id, hash, ext)
            end
        else
            url = ('https://cdn.discordapp.com/embed/avatars/%d.png'):format((math.tointeger(tonumber(data.user.id) or 0) or 0) % 5)
        end
        cache[discordId] = { url = url, time = os.time() }
    end, 'GET', '', { Authorization = 'Bot ' .. D.botToken })
    return hit and hit.url or nil
end
