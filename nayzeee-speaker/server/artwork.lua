--[[
    Album art lookup.

    Tries iTunes first because it needs no key and no setup, then Spotify if it is configured.
    Results are cached, and a failed lookup is retried later instead of being remembered as "none".
]]
Artwork = {}

local cache = {}        -- key -> { url = string|false, at = number }
local OK_TTL = 30 * 24 * 3600
local FAIL_TTL = 10 * 60

local function key(artist, album) return ((artist or '') .. '|' .. (album or '')):lower() end

local function viaItunes(artist, album)
    local term = Search.Encode(('%s %s'):format(artist or '', album or ''))
    local r = Sources.Http(('https://itunes.apple.com/search?term=%s&entity=album&limit=1'):format(term), nil, 8000)
    if r.code ~= 200 or not r.body then return nil end
    local ok, d = pcall(json.decode, r.body)
    if not ok or not d or not d.results or not d.results[1] then return nil end
    local art = d.results[1].artworkUrl100
    if not art then return nil end
    -- the 100px thumbnail url also serves much larger sizes
    return (art:gsub('/100x100bb', '/600x600bb')), tonumber((d.results[1].releaseDate or ''):sub(1, 4))
end

-- Returns a cover url now if we have one, otherwise nil and looks it up in the background.
-- `onFound` is called once the art arrives, so the caller can refresh what players see.
function Artwork.Album(artist, album, onFound)
    local k = key(artist, album)
    local hit = cache[k]
    local now = os.time()
    if hit then
        if hit.url and now - hit.at < OK_TTL then return hit.url end
        if not hit.url and now - hit.at < FAIL_TTL then return nil end
        if hit.pending then return nil end
    end
    cache[k] = { url = hit and hit.url or false, at = now, pending = true }
    CreateThread(function()
        local url, year = viaItunes(artist, album)
        if not url and Spotify.Enabled() then
            local found = Spotify.FindAlbum(artist, album)
            if found then url, year = found.cover, found.year end
        end
        cache[k] = { url = url or false, at = os.time() }
        if url and onFound then onFound(url, year) end
    end)
    return hit and hit.url or nil
end

function Artwork.Clear() cache = {} end
