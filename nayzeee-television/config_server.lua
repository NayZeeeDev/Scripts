--[[
    NAYZEEE TELEVISION — server-only configuration
    ─────────────────────────────────────────────────────────────
    This file is a server_script: players never download it.
    Keep keys and tokens here, never in config.lua.
]]

ServerConfig = {}

-- Optional: enables YouTube search on the TV and in the media panel.
-- Create a key at console.cloud.google.com → YouTube Data API v3.
ServerConfig.YouTubeApiKey = ''

-- Discord webhook for admin, placement and media logs ('' = off)
ServerConfig.Webhook = ''

-- Channel playlists (M3U / M3U8). Every channel in them is added to the Live tab and CH ▲ / ▼.
-- Use this for Pluto TV and other free live-TV (FAST) channel lists you have the rights to use.
--   { name = 'Pluto TV', url = 'https://…/plutotv_us.m3u8', brand = 'pluto', max = 150, groups = { ['News'] = true } }
ServerConfig.ChannelPlaylists = {
    -- Examples (use lists you have the rights to use; brand picks the logo shown on the channel):
    -- { name = 'Pluto TV',  url = 'https://…/pluto_us.m3u8', brand = 'pluto', max = 150 },
    -- { name = 'Plex Live', url = 'https://…/plex_us.m3u8',  brand = 'plex',  max = 150, groups = { ['News'] = true, ['Movies'] = true } },
}
ServerConfig.ChannelRefreshHours = 6   -- live-TV stream links often expire; playlists are re-read this often

-- Plex Media Server — browse your own movies and shows on any TV.
-- ⚠ The token ends up in the stream links every nearby player loads. Use a Plex Home *managed user*
--   that can only see the libraries you want in game — never your admin token.
ServerConfig.Plex = {
    Enabled    = false,
    Url        = 'http://127.0.0.1:32400',  -- how the FiveM server reaches Plex
    PublicUrl  = '',                        -- how players' games reach Plex (https://plex.example.com); empty = Url
    Token      = '',
    Transcode  = true,                      -- HLS transcode (plays everything). false = direct file play
    MaxBitrate = 8000,                      -- kbps when transcoding
    Limit      = 60,
    Sections   = nil,                       -- { ['Movies'] = true } to only show some libraries
}

