-----------------------------------------------------------------
-- Status publisher
--
-- Cuffed / dead state lives inside whatever police or medical script
-- the server runs, and only on that player's own client. This reads
-- it through integrations.lua and publishes it on the player's
-- statebag, so robbers, police and the server can all see it.
--
-- One check per second, and the statebag is only written on change.
-----------------------------------------------------------------

local last = { cuffed = false, dead = false }

local function read()
    local ped = PlayerPedId()
    local dead = IsPedDeadOrDying(ped, true) or Integrations.any('isDead')
    local cuffed = Integrations.any('isCuffed')
        or IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3)
        or IsPedCuffed(ped)
    return { cuffed = cuffed and true or false, dead = dead and true or false }
end

CreateThread(function()
    while true do
        local now = read()
        if now.cuffed ~= last.cuffed or now.dead ~= last.dead then
            last = now
            LocalPlayer.state:set('nb_status', now, true)
        end
        Wait(1000)
    end
end)

--- Status of any player, from their statebag (or live for yourself).
function GetPlayerStatus(serverId)
    if serverId == GetPlayerServerId(PlayerId()) then return read() end
    return Player(serverId).state.nb_status or { cuffed = false, dead = false }
end
