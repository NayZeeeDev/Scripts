# 📻 NAYZEEE Speaker

Synced 3D music for placed boomboxes, carried boomboxes and vehicles (CarPlay), a turntable that plays real records, a record shop to buy them in, and a phone app to run it all.

## ✨ New in 2.0

- **Restyled speakers** — new colours and designs, the NAYZEEE logo and **animated RGB lights**, applied live in game. The prop pack's own files are never modified (see **Looks & RGB lights** below).
- **Record shop** — browse, preview and buy records over a shop counter.
- **New audio engine** — smoother, more natural 3D sound, real room echo, a tone for every speaker and true stereo up close.
- **Phone app rebuilt** — fits every phone, picks which speaker it controls, full Now Playing screen.
- **Record Console upgrade (optional)** — a turntable you can watch: the record goes on, the platter spins and the needle drops.
- **Jam player** — start or join a jam and the player switches to the jam, so what you play goes to everyone in it.
- Lots of fixes and hardening, see `CHANGELOG.md`.

## 📦 What's in the pack

| Folder | What it is |
|---|---|
| `nayzeee-speaker` | The script, with the 8 speaker models (`nayzeee_audio_a` … `h`) and their woofer / light animations streamed from `stream/` |
| `nayzeee-speaker-assets` | Optional, **not a resource**: the source files and tools of the Record Console upgrade. Don't put it in your server's resources |

The files in `stream/` are the original prop pack and stay exactly as they are. Everything new about how the speakers look is swapped in while the game runs; stop the resource and the props look as shipped.

## 🔗 Dependencies

| Resource | Required |
|---|---|
| oxmysql | Yes |
| es_extended / qb-core / qbx_core | Yes (auto-detected), or ox_inventory on its own |
| ox_inventory | Optional (auto-detected, otherwise the framework's inventory) |
| ox_target or qb-target | Optional (falls back to an [E] prompt) |
| ox_lib | Optional (notifications + progress bars) |
| lb-phone / qs-smartphone / yseries | Optional (the Speaker app is added automatically) |

## ⚙️ Install

1. Drop `nayzeee-speaker` into your resources.
2. In `server.cfg`, after oxmysql / your framework / your inventory / your target / your phone:
   ```
   ensure nayzeee-speaker
   ```
3. Add the items from `install/items.md` and copy `install/images/*.png` into your inventory images. Every image is named like its item.
4. Tables create themselves on first start (`sql/install.sql` if you prefer to run it by hand).
5. **Move the record shop.** The shipped spot is an example (the counter of the 24/7 on Innocence Blvd); see **Record shop** below. Don't want a shop? `Config.RecordShop.enabled = false`.

> 💡 **Updating from 1.x?** Take the new `config.lua` and copy your settings into it. An old config still starts (every new setting has a default in the code), but without `Config.Looks` the speakers keep the pack's look and without `Config.RecordShop` there is no shop.

## 🎨 Looks & RGB lights

The speakers keep their models. While the server runs, the script swaps textures of the pack's texture dictionary (`nayzeee_audio_texture`) for the images in `html/looks/`, so the original files are never touched. Looks are server-wide: every speaker of one model wears the same look.

**Pick a look per texture** in `Config.Looks.textures`:

| Key | What it is | Speakers it changes | Default |
|---|---|---|---|
| `sp1` | fabric | Pulse Tower | `violet` |
| `sp2` | fabric | Echo Column **and** Carry Cube (one texture, so they always match) | `honeycomb` |
| `sp3` | fabric | Drum Hub | `cobalt` |
| `sp4` | fabric | Orb | `sunset` |
| `sp5` | fabric | Roll Bar | `crimson` |
| `repro` | the drivers on both ends | Roll Bar | `chrome` |

- **Fabrics** (`sp1` … `sp5`): `original` `graphite` `teal` `crimson` `violet` `cobalt` `arctic` `carbon` `honeycomb` `stripe` `camo` `sunset`
- **Drivers** (`repro`): `original` `graphite` `chrome` `teal` `crimson` `violet` `gold` `carbon` `honeycomb`

`original` puts the pack's own texture back; a texture you leave out stays as shipped. The full list lives in `html/looks/library.json`: for each texture the speakers that use it (`usedBy`), its size, every look (`variants`) and the shipped default.

The logo and the turntable's record have their own settings:

| Setting | Speakers | Options |
|---|---|---|
| `logo` | Pulse Tower, Drum Hub, Carry Cube, Roll Bar, Turntable, Studio Set | `true` = NAYZEEE · `'nayzeee_teal'` · `false` = the pack's BZOOMBOX badge |
| `record` | Turntable | `true` = NAYZEEE · `'teal_vinyl'` · `'crimson_vinyl'` · `'smoke_vinyl'` · `false` = the pack's own |
| `recordArt` | Turntable | `true` = while an album plays on the nearest turntable, its record shows the album cover as the label (hidden in streamer mode) |

**Your own look:** drop a png into `html/looks/<texture>/<name>.png` (same shape as the original: square for fabrics, drivers and the record, 4:1 for the logo; lowercase letters, numbers and `_` in the name), add `<name>` to that texture's `variants` in `library.json` and set it in the config. A missing file or a wrong name prints one yellow `Config.Looks:` line in F8 and leaves that texture as shipped.

> ⚠️ The speakers' bodies and caps are built into each model file, so they can't be recoloured this way; only the fabrics, the Roll Bar's drivers, the logo and the turntable's record can.

### 🌈 RGB lights

`Config.Looks.rgb` turns the speakers' light strips into animated lights:

| `mode` | What the lights do |
|---|---|
| `rainbow` (default) | a rainbow running along the strip |
| `fade` | cross-fades through `colors` |
| `pulse` | breathes each of `colors` in turn |
| `static` | the first of `colors`, still (costs nothing at all) |
| `music` | follows the loudest speaker you hear: brighter when it's loud, colours drift faster and jump on the beat, a slow dim breath when it's quiet. `colors` isn't used |

`speed`, `brightness` and `saturation` tune it. The lights only run while one of these speakers is within `distance` metres of you, so far away they cost nothing. Each player can switch them off for themselves in the player's **Settings › RGB lights**; their strips then show a still look.

> ⚠️ **Which speakers light up:** the animation is certain on the **Carry Cube** and **Roll Bar**, whose light strip comes from the pack's shared texture dictionary. The Pulse Tower, Echo Column, Drum Hub, Orb and Studio Set have their lights built into their own model files; with `builtIn = true` the script tries those too, best effort. If the game doesn't allow it they simply keep their own colours, nothing breaks. The Turntable has no lights.

## 🎧 Music & the 3D effects

Paste a YouTube link or video ID, a direct audio link, **or just type a song name** and pick it from the search results.

**How the sound is handled decides which effects work.** A song played through YouTube's embedded player belongs to YouTube's frame and the browser will not let the game touch it, so only **volume** works — no direction, muffling, echo, doppler or EQ. To get those, the game needs a real audio file. `Config.Audio.source` picks how it gets one:

| Setting | What happens | 3D effects |
|---|---|---|
| `auto` (default) | tries the public Invidious / Piped servers in `Config.Audio.instances`, then your own API, then falls back to the embed | yes, when an instance answers |
| `api` | only your own `nayzeee-speaker-api` server | yes, always |
| `iframe` | always the embedded player, nothing to set up | no, volume only |

Public instances are run by volunteers: free, but they go down and change. For a server you charge for, run your own API. Direct `.mp3` / `.ogg` links always get the full effects.

**What the 2.0 engine does with a real audio file:**

- Every value glides between updates, so nothing steps or zips as you walk around.
- A natural fade: full level within `fullVolumeDistance` (1.5 m), always silent exactly at the speaker's range, and far speakers lose their highs like real air.
- Echo from the space around the speaker: room, hall or street (`reverb`, `reverbLevel`).
- Walls between you and the speaker dampen it (doorways sound half open); a speaker in a building is muffled from outside and the other way round.
- Car music is muffled outside the car but the bass still thumps; windows, doors and the roof open it up.
- Doppler as a car with music drives past, subtle and capped (`dopplerAmount`, `maxDoppler`).
- True stereo when you're at the speaker (in the car, carrying it, in a jam, the shop preview, or closer than `closeStereo`); further away it's one point in the world.
- Every speaker model has its own tone (`Config.Audio.voices`: the Pulse Tower has party bass, the Roll Bar sounds like an 80s boombox, the Turntable is warm).
- Mixed playlists really crossfade (`Config.Social.mixedFade`).

> 💡 The player's **Settings › Sound** tells each player which mode the song they're hearing is in, and holds the Bass / Mid / Treble EQ.

## 🔎 Search & playlists

- Type words instead of a link to search; results play or queue in one click.
- **Playlists** tab: make playlists, add the playing song, share one with the whole city, or **import a Spotify or YouTube playlist** from a link.
- Spotify importing reads track names and finds each song. It does **not** stream Spotify — Spotify does not allow that in any third-party app. Fill in `Config.Spotify` with a free developer app to enable it.

## 💿 Turntable & records

The Turntable (`nayzeee_audio_g`) doesn't take links — it plays **records**, and each record item holds a whole album. **15 albums ship ready to use** in `vinyls.lua`, each with its own item image, price, genre and a line of description for the shop. Tracks are found by search, so there are no video IDs to paste.

| Command | Does |
|---|---|
| `/vinylimport <spotify album link>` | Creates a record with the real tracklist and cover art, live |
| `/vinylimport <youtube playlist link>` | Same, from a YouTube playlist |
| `/vinyllist` | Lists every record and its item name |
| `/vinyldelete <item>` | Removes an imported record |

Add one inventory item per record, named exactly like its key (see `install/items.md`). Players buy them in the **record shop**. Put a record on from the turntable's **Records** tab or by using the item nearby; **Take off** gives it back.

On the pack's turntable the record wears the NAYZEEE look, and while an album plays its cover shows on the record's label (`Config.Looks.recordArt`). With the **Record Console upgrade** you can watch the whole thing happen.

> ⚠️ The shipped tracklists were typed from memory and a few titles may be off. `/vinylimport` on the album's Spotify link replaces any of them with the exact tracklist in seconds.

Album art is fetched automatically from iTunes (no key, no setup) and falls back to Spotify if you've configured it, so records show their real sleeve without you pasting image links.

## 🛍️ Record shop

Walk up to the shopkeeper and the camera moves over the counter. The records stand above it in a row: the featured sleeve in the middle, gently swaying with its record half out, the previous and next ones either side. Album, artist, year, tracks, price and description float above it.

- **Listen** (`L`) plays 30 seconds of the record's first song, only for you, at your own music volume.
- **Buy** (`ENTER`) pays from cash or bank. The server checks where you stand, the price, your money and the room in your pockets, refunds if the record can't be given, and logs every sale to the Discord webhook.
- Genre chips, an **Owned** filter, search and your wallet at the top.

Set it up in `Config.RecordShop`:

- **Move the example location.** The shipped spot is the counter of the 24/7 on Innocence Blvd. In `locations`, `coords` is where the shopkeeper stands and `heading` the way they face the customer; the display is worked out from that, or set `display.point` / `display.cam` exactly. `ped = false` gives a marker with an [E] prompt instead of a shopkeeper.
- **Money:** `currency = 'cash'` or `'bank'` uses the ESX / QBCore / Qbox accounts; with ox_inventory and no framework, cash is the `money` item. `currency = 'item'` pays with any item (`moneyItem`). With no money system at all the shop won't open and says so in the console.
- **Prices:** from `vinyls.lua` (`price`, `genre`, `description`), else `defaultPrice`. Imported records, or overrides, go in `records`; `price = false` takes a record out of the shop. `maxCopies` caps how many of one record a player can hold.
- Every record item must exist in your inventory; one that doesn't is left out of the shop with a console warning naming it.
- Tills and monitors right by the display are hidden for the shopper only (`hideProps`).

The sleeves are real 3D props with the album cover on them once the **Record Console upgrade** is converted. Until then the same shop draws the records as cover cards (the vinyl slides out, drag to flip to the tracklist). `display = '2d'` keeps the cards.

## 🎚️ Record Console upgrade (optional)

The turntable works out of the box with the pack's own model. For the full show (the record goes onto the platter, the platter spins and the tonearm drops the needle and moves in while the album plays, plus 3D sleeves on the record shop counter) convert the upgrade once: `nayzeee-speaker-assets/README.md` has the exact CodeWalker clicks. It only ADDS files to `stream/` (own texture dictionary `nayzeee_console_texture`, own `nayzeee_console.ytyp`); nothing from the pack is removed or changed. Then:

1. Uncomment the two `nayzeee_console.ytyp` lines in `fxmanifest.lua`.
2. Set `Config.Boomboxes['nayzeee_audio_g'].model = 'nayzeee_console'` and delete its `anim` line (`label = 'Record Console'` fits it too).

Until you do, nothing changes: the pack's turntable keeps working and the shop shows cover cards. On the console the music waits for the needle to land (`Config.Turntable.needleDrop`), everyone nearby sees the same thing at the same moment, and the album cover is printed on the record's label (`labelArt`).

## 🖼️ Item images

`install/images/` has a 512 px image for every item: the eight speakers in their default look, the CarPlay unit, a generic record (`vinyl_record.png`) and one per record in `vinyls.lua` (`vinyl_<key>.png`: the record half out of a sleeve in its own colours with the album title and artist; no real album art). Add a record and want its image: `python3 tools/item_images.py --only vinyl_<key>` in nayzeee-speaker-assets.

## 🔗 Linked speakers

Open a speaker › **Linked** and link any speaker in range. Linked speakers play the same song at the same moment, and controlling one controls them all. Good for club rooms, house parties and convoys. To link someone else's speaker you have to stand at it, and when the group's leader is locked, so is the music on every speaker in the group.

## 💥 Destructible speakers

Placed speakers take damage from bullets, melee, vehicles and explosions (`Config.Damage`). At zero they break, the music stops, and the item either drops back or is gone — your choice. `/speakerrepair [radius]` fixes them.

## 📱 Phone app

A Speaker app is added to **lb-phone**, **qs-smartphone** (and -pro) or **yseries** automatically. It works like a Connect device picker: choose which speaker the app controls (yours anywhere, other people's nearby, your car, your jam) and it remembers it. **Home** shows what that speaker is playing with a live seek bar, transport, repeat / shuffle and volume; a mini player sits above the tabs and opens a full Now Playing screen with the queue (or the record's track list on a turntable). **Search** plays, queues, likes or adds to a playlist. **Library** has Liked Songs and your playlists (play from any song, or shuffle). **Jam** starts, joins and leaves listening sessions. Streamer mode hides song names and covers here too.

The layout fits every phone screen; if your phone's status bar or home bar overlaps it, set `Config.Phone.insets`. `Config.Phone.range = 0` lets players control their own speakers from anywhere.

## 💚 Library, playlists & listening together

- **Liked songs** — heart anything from search, the player or the phone.
- **Playlists** — make them, import a Spotify or YouTube playlist, or share one with the city.
- **Collaborative** — pick a player and they can add to your playlist too.
- **Blend** — one playlist built from what you and another player both like.
- **Prompted** — type "late night drive rap" and it builds a playlist from that.
- **Mixed** — crossfades between songs instead of cutting.
- **Jam** — start a session and anyone who joins hears your music in their own ears, anywhere in the city. Starting or joining one opens the jam's player, and `J` on foot brings it back.

> These are this script's own versions of those ideas. They don't connect to Spotify's features of the same name.

## 🖼️ Your own logo

Drop a square png at `html/img/logo.png` and it replaces the mark in the top-left of the player, the record shop and the phone app. Turn it off entirely with `Config.Brand.watermark = false`.

## 🎴 Now playing card

Shows what you're hearing: your car first, then the loudest boombox near you. In **Settings** each player can turn it off, resize it, drag it anywhere, and restyle it:

- **7 skins** — Compact, Boxy, Gallery, Minimal, macOS, Shell, Bar
- **4 cover styles** — Square, Canvas, Vinyl (spins with the music), None
- **Cover glow** and **cover blur** backgrounds, and the visualizer can be hidden
- **11 reveal and 11 exit animations**, and a font picker

Server defaults live in `Config.NowPlaying`.

## 🧾 Config highlights

| Section | What it's for |
|---|---|
| `Config.Audio` | where songs come from (`source`), the 3D effects, each speaker's tone (`voices`), the starting EQ |
| `Config.Looks` | speaker colours / designs, logo, the turntable's record, RGB lights |
| `Config.Boomboxes` | each speaker's label, model, carry position and animation (and the console switch) |
| `Config.Turntable` | the Record Console upgrade: needle drop, label art, how far its parts show |
| `Config.RecordShop` | currency, prices, preview, the counter display, locations |
| `Config.Phone` | which phone, app name, `range`, `insets` |
| `Config.Carplay` | car music, the J key, who controls it, the optional unit item |
| `Config.Links` / `Config.Damage` / `Config.Social` / `Config.Playlists` | linked groups, destructible speakers, jam / blend / collab / prompted / mixed, playlist limits |
| `Config.Limits` / `Config.Ranges` | rate limits, queue size, song length, hearing ranges |
| `Config.NowPlaying` / `Config.StreamerMode` / `Config.Brand` | the card's defaults, streamer mode, your logo |
| `Config.Actions` / `Config.BlacklistedZones` | placing, who can carry / control, where speakers aren't allowed |

## 🎮 Controls

| Action | Default |
|---|---|
| Open car player / player of the boombox in your hands / your jam's player | `J` |
| Put down a carried boombox | `X` |
| Place / hold / cancel while placing | `E` / `H` / `G`, scroll to rotate |
| Record shop: browse / listen / buy / search / leave | `A` `D` (or arrows, mouse wheel) / `L` / `ENTER` / `/` / `ESC`, drag to spin the sleeve |
| Streamer mode | `/streamermode` or the Settings tab |
| RGB lights on / off for yourself | Settings tab |

Players can rebind `J` and `X` in Settings › Key Bindings › FiveM. While typing in the car player, game keys are paused so `F` doesn't throw you out of the car.

## 🛠️ Admin

| Command | Does |
|---|---|
| `/speakerstop [radius]` | Stops music near you (default 30 m) |
| `/speakerclear [radius]` | Removes boomboxes and stops car music (no radius = everywhere) |
| `/speakerrepair [radius]` | Repairs damaged speakers near you (default 20 m) |
| `/vinylimport` `/vinyllist` `/vinyldelete` | Records, see **Turntable & records** |
| `/recordshop` | Opens the record shop where you stand, for testing (`Config.RecordShop.command`, `''` = off) |
| `/nzspk_attach <item>` | Live hand-position editor (needs `Config.Debug = true`), prints the offsets to paste into the config |

Admins are anyone with the `nayzeee.speaker.admin` ace or a group in `Config.Admin.groups`.

## 🚗 Garage hook (optional)

If `Config.Carplay.install.use = true`, installed units are saved by plate and checked automatically when someone presses `J`. You can also warm the check when your garage spawns a car:

```lua
exports['nayzeee-speaker']:CheckCarPlay(NetworkGetNetworkIdFromEntity(vehicle)) -- server
TriggerServerEvent('nayzeee-speaker:server:CheckCarPlay', netId)               -- client
```

## 🧩 Exports

| Export | Side | Does |
|---|---|---|
| `OpenRecordShop(locationIndex)` | client | Opens that shop location if the player is at it (the server still checks) |
| `CheckCarPlay(netId)` | server | See the garage hook above |
| `GetEmitters()` | server | Every speaker / car / jam with what it's playing |
| `LinkSpeakers(idA, idB)` | server | Links two speakers |
| `DamageSpeaker(id, amount)` | server | Damages a placed speaker |
| `ImportRecord(link)` / `GetRecords()` | server | Imports a record from a Spotify / YouTube link / lists every record |
| `PhoneCanUse(src)` | server | Whether that player may use the phone app |
| `useItem` | server | ox_inventory item export (see `install/items.md`) |

## 🧯 Troubleshooting

| Issue | Solution |
|---|---|
| "Couldn't load that song" | The link is private, age-restricted or region-locked; try another upload of the song |
| Direct mp3 link plays with no 3D effect | That host doesn't send CORS headers; it falls back to plain volume on purpose |
| Boombox floats or sinks | Place it again; the preview snaps to whatever surface the crosshair hits |
| Carried boombox sits wrong in the hand | Tune it with `/nzspk_attach <item>` and paste the printed line into `Config.Boomboxes` |
| Speakers still look like the original pack | Check `Config.Looks.enabled`, look for yellow `Config.Looks:` lines in F8, and clear your FiveM cache |
| RGB lights only move on the Carry Cube and Roll Bar | Expected when the game won't let the other speakers' built-in lights be swapped; those are only tried best effort and keep their own colours |
| Using a speaker or record does nothing (ox_inventory, no framework) | The item needs `server = { export = 'nayzeee-speaker.useItem' }`; the server console lists the ones missing it |
| A record is missing from the shop | Its item isn't registered in your inventory (the console names it), or its `price` is `false` |
| Shop says it has no money system | No framework or ox_inventory money found; set `Config.RecordShop.currency = 'item'` and a `moneyItem` |
| Shop shows flat cover cards | The Record Console upgrade isn't converted yet; that's the 2D shop working as intended |
| Console shows no platter, arm or record | The upgrade's 9 files aren't in `stream/`, the two `fxmanifest.lua` lines are still commented, or the turntable's `model` isn't `'nayzeee_console'` |
| Phone app overlaps the status bar / home bar | Set `Config.Phone.insets` (pixels to keep clear) |
