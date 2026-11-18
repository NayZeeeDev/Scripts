if not NAYZEEE_LOCK_OK then return end

--[[
    Audio. The ambience itself is procedural Web Audio inside the NUI (or theme.ambience.url);
    Lua only tells the UI what to play. GTA frontend sounds are optional extra cues.
]]

Audio = { current = nil }

-- GTA frontend cue (Config.Audio.sounds key: select | back | nav | deploy)
function Audio.Play(name)
    if not Config.Audio.frontend or Settings.Get('muted') then return end
    local s = Config.Audio.sounds and Config.Audio.sounds[name]
    if not s then return end
    PlaySoundFrontend(-1, s[1], s[2], true)
end

local function push()
    local c = Audio.current
    U.Send('audio', {
        ambience = c and c.preset or nil,     -- procedural preset name (city, rooftop, club ...)
        theme    = c and c.theme or nil,
        url      = c and c.url or nil,
        muted    = Settings.Get('muted') == true,
        volume   = Settings.Get('ambientVolume'),
    })
end

-- Start the ambience of a theme. url overrides the theme's own (start screen music)
function Audio.Theme(themeId, url)
    local theme = NZ.Theme(themeId)
    if not Config.Audio.ambience or not theme then
        Audio.current = nil
        return push()
    end
    local amb = theme.ambience or {}
    local u = url
    if not u or u == '' then u = amb.url end
    Audio.current = { theme = themeId, preset = amb.preset or themeId, url = (u and u ~= '') and u or nil }
    push()
end

-- Settings changed (mute / volume)
function Audio.Refresh() push() end

function Audio.Stop()
    Audio.current = nil
    push()
end
