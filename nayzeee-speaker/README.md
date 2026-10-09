# 📻 NAYZEEE Speaker

Synced 3D music for placed boomboxes, carried boomboxes and vehicles (CarPlay).

## 📦 What's in the pack

| Folder | What it is |
|---|---|
| `nayzeee-speaker` | The script, with the 8 speaker models (`nayzeee_audio_a` … `h`) and their woofer / light animations streamed from `stream/` |

## 🔗 Dependencies

| Resource | Required |
|---|---|
| oxmysql | Yes |
| es_extended / qb-core / qbx_core | Yes (auto-detected) |
| ox_target or qb-target | Optional (falls back to an [E] prompt) |
| ox_lib | Optional (notifications + progress bars) |

## ⚙️ Install

1. Drop `nayzeee-speaker` into your resources.
2. In `server.cfg`, after oxmysql / your framework / your target:
   ```
   ensure nayzeee-speaker
   ```
3. Add the items from `install/items.md` and copy `install/images/*.png` into your inventory images.
4. Tables create themselves on first start (`sql/install.sql` if you prefer to run it by hand).

## 🎧 Music & the 3D effects

Paste a YouTube link or video ID, a direct audio link, **or just type a song name** and pick it from the search results.

**How the sound is handled decides which effects work.** A song played through YouTube's embedded player belongs to YouTube's frame and the browser will not let the game touch it, so only **volume** works — no direction, muffling, echo, doppler or EQ. To get those, the game needs a real audio file. `Config.Audio.source` picks how it gets one:

| Setting | What happens | 3D effects |
|---|---|---|
| `auto` (default) | tries the public Invidious / Piped servers in `Config.Audio.instances`, then your own API, then falls back to the embed | yes, when an instance answers |
| `api` | only your own `nayzeee-speaker-api` server | yes, always |
| `iframe` | always the embedded player, nothing to set up | no, volume only |

Public instances are run by volunteers: free, but they go down and change. For a server you charge for, run your own API. Direct `.mp3` / `.ogg` links always get the full effects.

> 💡 The player's **Settings › Sound** tells each player which mode the song they're hearing is in, and holds the Bass / Mid / Treble EQ.

## 🔎 Search & playlists

- Type words instead of a link to search; results play or queue in one click.
- **Playlists** tab: make playlists, add the playing song, share one with the whole city, or **import a Spotify or YouTube playlist** from a link.
- Spotify importing reads track names and finds each song. It does **not** stream Spotify — Spotify does not allow that in any third-party app. Fill in `Config.Spotify` with a free developer app to enable it.

## 💿 Turntable & records

The Turntable (`nayzeee_audio_g`) doesn't take links — it plays **records**, and each record item holds a whole album. **15 albums ship ready to use** in `vinyls.lua`. Tracks are found by search, so there are no video IDs to paste.

| Command | Does |
|---|---|
| `/vinylimport <spotify album link>` | Creates a record with the real tracklist and cover art, live |
| `/vinylimport <youtube playlist link>` | Same, from a YouTube playlist |
| `/vinyllist` | Lists every record and its item name |
| `/vinyldelete <item>` | Removes an imported record |

Add one inventory item per record, named exactly like its key (see `install/items.md`). Put a record on from the turntable's **Records** tab or by using the item nearby; **Take off** gives it back.

> ⚠️ The shipped tracklists were typed from memory and a few titles may be off. `/vinylimport` on the album's Spotify link replaces any of them with the exact tracklist in seconds.

Album art is fetched automatically from iTunes (no key, no setup) and falls back to Spotify if you've configured it, so records show their real sleeve without you pasting image links.

## 🔗 Linked speakers

Open a speaker › **Linked** and link any speaker in range. Linked speakers play the same song at the same moment, and controlling one controls them all. Good for club rooms, house parties and convoys.

## 💥 Destructible speakers

Placed speakers take damage from bullets, melee, vehicles and explosions (`Config.Damage`). At zero they break, the music stops, and the item either drops back or is gone — your choice. `/speakerrepair [radius]` fixes them.

## 📱 Phone app

A Speaker app is added to **lb-phone**, **qs-smartphone** or **yseries** automatically. Four tabs: **Speakers** (control anything you have access to), **Search** (type a song, heart it, play or queue it), **Library** (Liked Songs and your playlists) and **Jam**.

## 💚 Library, playlists & listening together

- **Liked songs** — heart anything from search, the player or the phone.
- **Playlists** — make them, import a Spotify or YouTube playlist, or share one with the city.
- **Collaborative** — pick a player and they can add to your playlist too.
- **Blend** — one playlist built from what you and another player both like.
- **Prompted** — type "late night drive rap" and it builds a playlist from that.
- **Mixed** — crossfades between songs instead of cutting.
- **Jam** — start a session and anyone who joins hears your music in their own ears, anywhere in the city.

> These are this script's own versions of those ideas. They don't connect to Spotify's features of the same name.

## 🖼️ Your own logo

Drop a square png at `html/img/logo.png` and it replaces the mark in the top-left of the player and the phone app. Turn it off entirely with `Config.Brand.watermark = false`.

## 🎴 Now playing card

Shows what you're hearing: your car first, then the loudest boombox near you. In **Settings** each player can turn it off, resize it, drag it anywhere, and restyle it:

- **7 skins** — Compact, Boxy, Gallery, Minimal, macOS, Shell, Bar
- **4 cover styles** — Square, Canvas, Vinyl (spins with the music), None
- **Cover glow** and **cover blur** backgrounds, and the visualizer can be hidden
- **11 reveal and 11 exit animations**, and a font picker

Server defaults live in `Config.NowPlaying`.

## 🎮 Controls

| Action | Default |
|---|---|
| Open car player / player of the boombox in your hands | `J` |
| Put down a carried boombox | `X` |
| Place / hold / cancel while placing | `E` / `H` / `G`, scroll to rotate |
| Streamer mode | `/streamermode` or the Settings tab |

Players can rebind `J` and `X` in Settings › Key Bindings › FiveM.

## 🛠️ Admin

| Command | Does |
|---|---|
| `/speakerstop [radius]` | Stops music near you (default 30 m) |
| `/speakerclear [radius]` | Removes boomboxes and stops car music (no radius = everywhere) |
| `/nzspk_attach <item>` | Live hand-position editor (needs `Config.Debug = true`), prints the offsets to paste into the config |

Admins are anyone with the `nayzeee.speaker.admin` ace or a group in `Config.Admin.groups`.

## 🚗 Garage hook (optional)

If `Config.Carplay.install.use = true`, installed units are saved by plate and checked automatically when someone presses `J`. You can also warm the check when your garage spawns a car:

```lua
exports['nayzeee-speaker']:CheckCarPlay(NetworkGetNetworkIdFromEntity(vehicle)) -- server
TriggerServerEvent('nayzeee-speaker:server:CheckCarPlay', netId)               -- client
```

## 🧯 Troubleshooting

| Issue | Solution |
|---|---|
| "Couldn't load that song" | The link is private, age-restricted or region-locked; try another upload of the song |
| Direct mp3 link plays with no 3D effect | That host doesn't send CORS headers; it falls back to plain volume on purpose |
| Boombox floats or sinks | Place it again; the preview snaps to whatever surface the crosshair hits |
| Carried boombox sits wrong in the hand | Tune it with `/nzspk_attach <item>` and paste the printed line into `Config.Boomboxes` |
