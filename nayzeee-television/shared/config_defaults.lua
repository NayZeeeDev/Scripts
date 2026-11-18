--[[ Fills in anything missing from config.lua and derives the values the code uses.
     You never need to edit this file. ]]

local function default(t, k, v) if t[k] == nil then t[k] = v end return t[k] end
local function tbl(k) Config[k] = Config[k] or {} return Config[k] end

-- general
default(Config, 'Notify', 'nayzeee')
default(Config, 'Storage', 'auto')
default(Config, 'AdminAce', 'nztv.admin')
default(Config, 'AdminGroups', { 'admin', 'superadmin', 'god' })
Config.Commands = {
    admin     = default(Config, 'AdminCommand', 'tvadmin'),
    calibrate = default(Config, 'CalibrateCommand', 'tvcalibrate'),
    panel     = default(Config, 'PanelCommand', 'tv'),
    remote    = default(Config, 'RemoteCommand', 'tvremote'),
    settings  = default(Config, 'SettingsCommand', 'tvsettings'),
}
local B = tbl('Brand')
default(B, 'name', 'NAYZEEE') default(B, 'product', 'Television') default(B, 'os', 'NAYZEEE OS') default(B, 'version', '1.0.0')

-- render
local R = tbl('Render')
default(R, 'Resolution', { 1280, 720 })
default(R, 'CinemaResolution', { 1920, 1080 })
R.MaxScreens   = default(R, 'MaxActive', 6)
default(R, 'MaxDrawn', 10)
default(R, 'StreamDistance', 60.0)
R.TickIdle     = default(R, 'Tick', 750)
R.TickNear     = math.min(250, R.TickIdle)
default(R, 'RenderPadding', 15.0)
default(R, 'VisibilityCull', true)
default(R, 'Prefer', 'overlay')
default(R, 'ScreenOffset', 0.006)
default(R, 'DoubleSided', false)
default(R, 'Glow', true)
default(R, 'GlowColor', { 160, 190, 255 })
default(R, 'GlowIntensity', 0.35)

-- audio
local A = tbl('Audio')
A.Volume01          = (default(A, 'DefaultVolume', 35)) / 100.0
default(A, 'Rolloff', 1.6)
default(A, 'InnerRadius', 2.5)
A.WallVolume        = default(A, 'WallMuffle', 0.32)
A.RoomVolume        = default(A, 'RoomMuffle', 0.2)
A.RoomLowpass       = default(A, 'LowpassHz', 900)
A.WallLowpass       = math.floor(A.RoomLowpass * 1.6)
default(A, 'LineOfSight', true)
A.Stereo            = default(A, 'StereoPan', true)
A.UpdateRate        = default(A, 'Update', 200)
A.GroupSingleSource = default(A, 'LinkedOneSource', true)

-- sync
local S = tbl('Sync')
S.SeekDrift     = default(S, 'DriftSeek', 1.25)
S.NudgeDrift    = default(S, 'DriftNudge', 0.3)
S.ClockResyncMs = default(S, 'ClockResync', 60) * 1000
default(S, 'Interval', 2500)
default(S, 'HistorySize', 16)
default(S, 'QueueSize', 50)
default(S, 'PersistState', true)

-- media
local M = tbl('Media')
M.Blacklist  = default(M, 'BlockedHosts', {})
M.Direct     = default(M, 'AllowDirect', true)
M.Images     = default(M, 'AllowImages', true)
default(M, 'Local', true)
default(M, 'BlockedWords', {})
default(M, 'MaxUrlLength', 400)
default(M, 'Cooldown', 1200)
default(M, 'MaxFavorites', 40)
default(M, 'KickResolve', true)
default(M, 'YouTubeHost', 'www.youtube-nocookie.com')
default(M, 'TwitchParent', 'auto')
M.MaxQueue   = S.QueueSize
M.MaxHistory = S.HistorySize

-- remote
local RM = tbl('Remote')
default(RM, 'Item', 'tv_remote')
default(RM, 'Model', 'prop_cs_remote_01')
RM.Enabled   = RM.Model ~= false
default(RM, 'Range', 18.0)
default(RM, 'RequireRemote', false)
RM.AutoPlace = default(RM, 'PlaceWithTV', true)
default(RM, 'GiveOnPlace', false)
default(RM, 'PickupDistance', 1.6)
local off = default(RM, 'Offset', { 0.04, 0.0, -0.01, -80.0, 0.0, 0.0 })
local anim = default(RM, 'HoldAnim', { dict = 'cellphone@', clip = 'cellphone_text_read_base' })
RM.Marker = {
    Enabled = (RM.MarkerDistance or 7.0) > 0, Type = RM.MarkerType or 2, Scale = RM.MarkerScale or 0.12, Height = 0.28,
    Color = RM.MarkerColor or { 8, 175, 162, 190 }, Distance = RM.MarkerDistance or 7.0, Bob = true,
}
RM.Hold = {
    Bone = RM.Bone or 28422,
    Offset = vector3(off[1] or 0.04, off[2] or 0.0, off[3] or -0.01),
    Rot = vector3(off[4] or -80.0, off[5] or 0.0, off[6] or 0.0),
    Dict = anim.dict, Clip = anim.clip,
}

-- phone
local P = tbl('Phone')
default(P, 'Enabled', true)
default(P, 'Range', 25.0)
default(P, 'Name', 'TV Remote')
default(P, 'Description', 'Control any TV near you when the remote goes missing')
default(P, 'Developer', 'NayZeee Development')
default(P, 'Identifier', 'nayzeee-television')
default(P, 'YSeriesResource', 'yseries')
P.LbPhone = P.Enabled and P.LBPhone ~= false
P.YSeries = P.Enabled and P.YSeries ~= false

-- placement + access
local PL = tbl('Placement')
local AC = tbl('Access')
default(AC, 'DefaultMode', 'public')
default(AC, 'PlayerDefault', 'owner')
Config.PlayerScreens = {
    Persist           = true,
    MaxPerPlayer      = default(PL, 'MaxPerPlayer', 6),
    PickupReturnsItem = default(PL, 'PickupReturns', true),
    PlaceDistance     = default(PL, 'MaxDistance', 7.5),
    DefaultPublic     = AC.PlayerDefault == 'public',
}
default(PL, 'OwnerShare', true)
default(PL, 'CanPlace', function() return true end)
Config.DefaultPermissions = { public = AC.DefaultMode ~= 'restricted', jobs = {}, gangs = {} }
tbl('Items')

-- interaction (built-in prompt keys)
local I = tbl('Interact')
default(I, 'Distance', 2.4)
default(I, 'Keys', { Open = 38, Remote = 47, Pickup = 74 })

-- TV OS
local OS = tbl('OS')
default(OS, 'ScreensaverMin', 6)
default(OS, 'InfoBarSeconds', 4)
default(OS, 'HeroSeconds', 9)
default(OS, 'SleepOptions', { 0, 15, 30, 60, 90 })
default(OS, 'Apps', { 'youtube', 'tiktok', 'twitch', 'kick', 'vimeo', 'soundcloud', 'plex', 'pluto', 'web', 'library', 'queue', 'channels', 'settings' })
default(OS, 'Picture', { standard = { brightness = 100, contrast = 100, saturation = 100, warmth = 0 } })

-- library → home screen content
Config.Featured, Config.Channels, Config.Collections = {}, {}, {}
for _, e in ipairs(Config.Library or {}) do
    if e.type == 'featured' then
        Config.Featured[#Config.Featured + 1] = { title = e.title, subtitle = e.subtitle, url = e.url, image = e.image }
    elseif e.type == 'live' then
        Config.Channels[#Config.Channels + 1] = { name = e.title, url = e.url, thumb = e.image, group = e.category }
    elseif e.type == 'movie' or e.type == 'music' then
        Config.Collections[#Config.Collections + 1] = { kind = e.type, category = e.category, title = e.title, subtitle = e.subtitle, url = e.url, thumb = e.image }
    end
end
Config.LocalLibrary = {}
for _, f in ipairs(Config.LocalMedia or {}) do
    Config.LocalLibrary[#Config.LocalLibrary + 1] = { file = f.file, title = f.title, subtitle = f.subtitle, thumb = (f.image ~= '' and f.image) or nil }
end

-- logs
local L = tbl('Logs')
default(L, 'LogMedia', true)
default(L, 'Keep', 150)
tbl('Text')
