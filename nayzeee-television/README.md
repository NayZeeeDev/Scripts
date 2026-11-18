# NAYZEEE Television

Synced smart TVs, cinema screens, venue walls, remotes and phone control for FiveM.
Everything is styled in the NAYZEEE UI (black · white · teal `#08afa2` · red `#e5484d`, Lexend).

## What's in it

| | |
|---|---|
| **NAYZEEE OS** | Every screen runs its own smart-TV interface: boot animation, home screen with an expanding left rail, hero banner, *For You / Live / Apps* tabs, Continue Watching, app tiles, search, library, queue, settings, an ambient clock screensaver, volume / channel / now-playing overlays. CRT and arcade models get scanlines and the classic collapse-to-a-line power-off. |
| **Sources** | YouTube · TikTok · Twitch · Kick · Vimeo · SoundCloud · Streamable · Medal · Instagram · Dailymotion · Reddit · Rumble · Pluto TV and other live-TV channel playlists (M3U) · your own Plex server · direct `.mp4/.webm/.mp3` · HLS `.m3u8` · images · files in `html/media`. See **Platforms** below for what each one supports. |
| **Own screen per TV** | Every TV has its own browser and its own texture, so two TVs of the same model play different things. The exception is linked screens: they share one browser because they show the same feed, which keeps them frame-identical and costs one browser for the whole group. |
| **Sync** | The server owns a clock. Every screen corrects drift every 2.5 s (hard seek above 1.25 s; small playback-rate nudges for direct/HLS media). Players who crash, relog or walk in late join at the exact current moment. Queues, loops and playlists advance on the server even when nobody is near. |
| **3D audio** | Volume falls off with distance (configurable rolloff). Walls muffle the sound, and so does being in another room of an interior. For direct, HLS and local media it pans left/right with your camera and applies a real low-pass filter. YouTube, Twitch and Kick embeds can only change volume. |
| **Linked screens** | Mirror one feed to many screens (bars, clubs, casinos, stadiums). Only the loudest linked screen near you plays sound, so there is no echo. |
| **Performance** | Props are client-side local objects (OneSync Infinity safe). A pool of at most `MaxScreens` browsers is shared between the closest powered screens. When nothing is near, the threads sleep 750 ms (≈0.00 ms). |
| **Remote** | Every TV can have a physical remote prop with a floating marker. Pick it up (E) and your ped holds it with an animation, and other players see it in your hand. G reopens it and H puts it down. The NUI remote has a D-pad, OK, back, home, play, VOL and CH rockers, mute, stop, menu, source, info, app keys and a keyboard for search. It also works with your keyboard (arrows, Enter, Backspace, + −, Space, PgUp/PgDn, K). |
| **Lost the remote?** | The *SmartView* phone app (lb-phone, plus a yseries adapter) lists screens near you and gives you a full remote and "cast a link". |
| **Media panel** | Now Playing with seek and controls, Browse (links, optional YouTube search, channels, server library), Up Next queue with reordering, History, personal Favorites, Display (picture mode, size, repeat, ambient, OSD, rename, place/move the remote), Access (public, lock, jobs/grades, gangs/grades, ACE, allow a player), Links (mirroring). |
| **Admin menu** | Dashboard (screens, on air, people watching, link groups), searchable screen table (teleport, play, power, lock, stop, move, edit, delete), Create (157-prop picker, wall-screen designer, claim an existing MLO prop), link groups, live **Calibrator**, and a prop library that shows which models exist in your game build. |
| **Items** | One usable item per TV model. Players place it with a ghost preview that snaps to walls, then place the remote. Picking it up gives the item back. |

## Platforms

| Platform | How it plays | Late joiners land on the right moment | Pause / seek follow the room | Distance volume | Wall muffling + stereo |
|---|---|---|---|---|---|
| YouTube (videos, Shorts, live, playlists) | official player API | ✅ | ✅ | ✅ | — |
| Twitch (channels, VODs) | official player API | ✅ | ✅ (VODs) | ✅ | — |
| Vimeo | official player API | ✅ | ✅ | ✅ | — |
| SoundCloud (tracks) | official widget API | ✅ | ✅ | ✅ | — |
| Streamable | resolved to the video file | ✅ | ✅ | ✅ | ✅ |
| Reddit video | resolved to HLS | ✅ | ✅ | ✅ | ✅ |
| Kick | resolved to HLS (falls back to embed) | ✅ | live | ✅ | ✅ |
| Pluto TV / M3U channels | HLS | live | live | ✅ | ✅ |
| Plex (your server) | HLS transcode or direct file | ✅ | ✅ | ✅ | ✅ |
| Direct mp4 / webm / mp3 / m3u8, server media | native | ✅ | ✅ | ✅ | ✅* |
| Dailymotion, Rumble | embed with start time | ✅ | reloads at the new time | sound cuts out of range | — |
| TikTok | official embed player | starts from 0 | pause only | mute out of range | — |
| Medal | embed | starts from 0 | pause only | sound cuts out of range | — |
| Instagram (posts, reels) | embed; the TV taps play for you | starts from 0 | pause only | sound cuts out of range | — |

\* Needs the host to send CORS headers. Without them the file still plays, with distance volume only.

**Not possible: Tubi.** Tubi's video is DRM-protected and its site refuses to load inside other pages, so no in-game browser screen can play it. The same applies to Netflix, Disney+, Hulu, Prime Video, Max and Spotify. Facebook and X videos mostly need a signed-in session, so they aren't included.

**Embeds** (TikTok, Medal, Instagram, Dailymotion, Rumble) don't let other pages control their volume or report when they end. Clips from these platforms only advance the queue when someone presses Next.

Logos live in `html/brand/` as transparent single-colour SVGs. Most come from Simple Icons (CC0). Medal, Streamable and Pluto TV were traced from their official logos into the same flat style. Logos are trademarks of their owners and are only used to show where a video comes from.

### Pluto TV and other live-TV channels

Add M3U playlists you have the rights to use to `ServerConfig.ChannelPlaylists` in `config_server.lua`. Every channel appears in the TV's **Live** tab and on CH ▲▼, with its logo and group. Playlists are re-read every few hours, because live-TV links expire. A single Pluto TV `…pluto.tv/…/master.m3u8` link also plays directly and is tagged as Pluto TV.

### Plex

Fill in `ServerConfig.Plex` in `config_server.lua`: the URL, a public URL players can reach, and a token. Plex then appears as an app on every TV and as *Recently added* in the media panel's Browse page.

**Use a Plex Home managed user token, not your own.** The token is part of the stream link every nearby player's game loads. Give that managed user access to only the libraries you want in game.

## Install

1. Drop the `nayzeee-television` folder into your resources and `ensure nayzeee-television` **after** your framework, inventory, target and phone. Keep the folder name: the item exports use it.
2. Give admins access: `add_ace group.admin nztv.admin allow`. Groups listed in `Config.AdminGroups` count as admin too.
3. Put secrets (YouTube API key, Discord webhook, Plex token, channel playlists) in **`config_server.lua`**. It's server-only: players never download it, unlike `config.lua`.
4. Storage is automatic. With `oxmysql` running, the tables are created on first start (`install/nayzeee_television.sql` if your database user can't create tables). Without it, data is written to `data/*.json`.
5. Add the items from the `install/` folder, restart, then run `/tvadmin`.

| File | Where it goes |
|---|---|
| `install/ox_inventory_items.lua` | `ox_inventory/data/items.lua` (Qbox and any ox server) |
| `install/qb_items.lua` | `qb-core/shared/items.lua`, plus the ESX `INSERT` at the bottom for ESX without ox |
| `install/nayzeee_television.sql` | Only if the tables can't be created automatically |

Items: `tv_flat_32`, `tv_flat_42`, `tv_flat_55`, `tv_flat_65`, `tv_flat_wall`, `tv_crt`, `tv_retro`, `tv_monitor`, `tv_laptop`, `tv_projector` and `tv_remote`. Add more in `Config.Items`.

## Commands

| Command | |
|---|---|
| `/tv` | Media panel for the screen you're looking at |
| `/tvremote` | Remote for the nearest screen (or the one whose remote you're holding) |
| `/tvsettings` | My TV settings: your own volume for every TV, plus streamer mode, which mutes every TV for you only |
| `/tvadmin` | Screen manager (admins) |
| `/tvcalibrate` | Opens the calibrator on the screen you're looking at (admins) |

Without a target resource, standing at a screen shows a NAYZEEE prompt: **E** media panel · **G** remote · **H** pick up. With `ox_target` or `qb-target`, the same options appear on the prop. With `Config.Remote.RequireRemote = true` there's no virtual remote at the TV: players need the physical remote, the remote item or the phone app.

## Admin workflows

- **Permanent prop screen:** Create → pick a model → Place prop → optionally place its remote.
- **Custom wall screen / billboard:** Create → Wall screen. Aim at any wall. Scroll changes the size, ← → change the aspect (16:9, 21:9, 2.39:1, 4:3, 1:1, 9:16), PgUp/PgDn change the height, and E creates it.
- **Use an MLO's own TV:** Create → Existing prop. Aim at the prop and press E. The script takes over that exact object.
- **Autoplay:** give a screen a default video and turn on Autoplay. It plays after every restart.
- **Calibrate a model:** stand in front of a screen, go to Calibrator → *Calibrate nearest screen*, then drag the sliders. A teal outline shows the picture edges and a red line shows which way it faces. Saving writes `data/calibration.json` and updates everyone instantly.

## Custom TV props

Stream your `.ydr/.ytyp` from any resource, then add a line to `Props.Custom` in `data/props.lua`:

```lua
{ 'my_oled_85', '85" OLED Wall TV', 'custom', { range = 28.0, screen = { x = 0.0, y = -0.04, z = 1.1, w = 1.88, h = 1.06, face = '-y' } } },
```

Leave `screen` out to use auto-fit, then fine-tune it with the Calibrator.

## Exports

```lua
-- server
exports.nayzeee-television:GetScreens()                 -- id → screen table
exports.nayzeee-television:PlayOnScreen(id, url)        -- true | false, reason
exports.nayzeee-television:StopScreen(id)
```

## Configuration highlights (`config.lua`)

`config.lua` uses the NayZeee layout: General, Render, Audio, Sync, Media, Remote, Phone, Placement, Access, TV OS, Library, Logs and Text. If you delete an option, its default is used.

- **Render** — `MaxActive` sets how many screens can show video at once per player (linked screens share one). `MaxDrawn` and `VisibilityCull` limit drawing. `Prefer = 'rendertarget'` uses the game's built-in screen on props that have one (pixel-perfect), but GTA shares it between every copy of a model, so it only kicks in when that model isn't already showing something else.
- **Audio** — `DefaultVolume` (0-100), `InnerRadius` in metres, wall and room muffling, low-pass, line of sight and stereo.
- **Sync** — drift thresholds, history and queue size, and `PersistState` to keep volume, picture, history and queue across restarts.
- **Media** — platform switches, `BlockedHosts`, `BlockedWords` (titles containing them get stopped), an anti-spam `Cooldown`, the YouTube embed host and the Twitch parent.
- **Remote** — prop model, marker, hold animation, `RequireRemote`, `PlaceWithTV` (a remote prop set down next to every new TV) and `GiveOnPlace` (a remote item paired to the TV, via ox_inventory metadata or qb info).
- **Placement** — distance, per-player limit, pick-up refunds, and the `CanPlace(source, coords, model)` hook for housing zones and no-build areas.
- **Access** — default mode for admin TVs and player TVs.
- **TV OS** — screensaver delay, info-bar time, banner rotation, sleep-timer steps, the home screen's app order, and picture presets as brightness, contrast, saturation and warmth.
- **Library** — `featured` banners, `live` channels (CH ▲▼), `movie` and `music` collections, plus `ytlive:<channel id>` to play whatever a YouTube channel is streaming. Local files go in `Config.LocalMedia`.
- **Logs** — what's kept for `/tvadmin` > Logs. Put the Discord webhook in `config_server.lua`.
- **Text** — every message players see.

## Good to know

- **Prop calibration.** Pictures are auto-fitted from each model's bounding box, and on most flat TVs that is close. Some props (laptops, arcade cabinets, AV units with shelves) need a quick pass with the Calibrator, and that's a one-time job per model. If a model's picture is on the back, switch *Facing* to `+y`.
- **Model availability** depends on your game build (`sv_enforceGameBuild`). Models that aren't in your build are flagged in the admin library and are never spawned.
- **Embeds.** YouTube videos whose owners have turned off embedding can't play on any in-game TV, and the TV says so. Twitch embeds need the page's host as `parent`; the script passes `cfx-nui-<resource>` automatically.
- **Kick.** Kick channels are resolved to HLS on the server when Kick's API allows it, which gives full audio control. If it doesn't, they fall back to Kick's embed player, which is volume-limited.
- **yseries.** Custom-app exports differ between yseries versions. The adapter in `client/phone.lua` is wrapped in a `pcall`. If your version uses a different export, change that one call. lb-phone uses its documented `AddCustomApp`.
- **Direct links** need CORS headers for wall muffling and stereo. Without them the file still plays, with distance volume only.
