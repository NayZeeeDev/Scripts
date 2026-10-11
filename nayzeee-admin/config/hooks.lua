-- Server hooks. Runs on the server only. Keep these light.
Hooks = {}

--- A ban was created (panel, command, warning limit or export).
---@param ban { id:number, name:string, license:string, reason:string, staff:string, expires:number|nil, identifiers:string[], tokens:string[] }
function Hooks.OnBan(ban)
    -- exports['your-anticheat']:ban(...)
end

--- A ban was removed.
function Hooks.OnUnban(banId)
end

--- A player was warned. count = total warnings on record.
function Hooks.OnWarn(src, reason, count)
end

--- Only used when Config.Weather.Resource = 'custom'.
--- w = { weather, hour, minute, freeze, blackout } · changed = the fields the staff member changed
function Hooks.SetWeather(w, changed)
    -- exports['cd_easytime']:... / TriggerEvent('your-weather:set', w)
end

-- Tell other anticheats that a staff teleport / noclip is allowed.
-- Called on the server when a staff member teleports or toggles noclip.
function Hooks.AllowMovement(src, seconds)
    -- exports['your-anticheat']:whitelist(src, seconds)
end

--- Bans made by other resources can be mirrored in:
-- AddEventHandler('some_ac:banned', function(src, reason)
--     exports['nayzeee-admin']:BanPlayer(src, reason, 'perm')
-- end)
