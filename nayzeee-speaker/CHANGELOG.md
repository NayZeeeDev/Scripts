# Changelog

## 2.0.0

**New: looks & RGB lights**
- The speakers are restyled live in game: textures of the pack's own dictionary are swapped for images in `html/looks/` while the resource runs. The prop pack's files in `stream/` are never modified; stop the resource and the props look exactly as shipped.
- 12 fabric looks per speaker (6 colours, carbon, honeycomb grille, two-tone stripe, camo, sunset gradient, original), 9 driver looks for the Roll Bar, the NAYZEEE logo instead of BZOOMBOX (or a teal one), a NAYZEEE record and 3 coloured vinyls on the turntable. Pick them in `Config.Looks`; every option is listed in `html/looks/library.json`.
- Fresh default look per speaker: violet Pulse Tower, honeycomb Echo Column and Carry Cube, cobalt Drum Hub, sunset Orb, crimson Roll Bar with chrome drivers.
- The turntable's record shows the album cover as its label while an album plays on the nearest one (`Config.Looks.recordArt`).
- Animated RGB lights: `rainbow`, `fade`, `pulse`, `static` or `music` (follows the music you hear). They only run while a speaker is near, and each player can turn them off in Settings › RGB lights. Certain on the Carry Cube and Roll Bar; the other speakers' lights are built into their models and are tried best effort (`rgb.builtIn`).
- A wrong look name or a missing file prints one yellow `Config.Looks:` line in F8 and leaves that texture as shipped.
- New 512 px inventory images for all eight speakers in their default look, with the lights on.

**New: record shop**
- Walk up to the shopkeeper and the camera moves over the counter; the records stand above it in a row, the featured sleeve swaying with its record half out, the previous / next ones either side, with album, artist, year, tracks, price and description above.
- Listen (`L`) plays 30 seconds of the first song in your own ears at your own music volume; Buy (`ENTER`) pays from cash, bank or an item. The server checks where you stand, the price, your money and your pockets, refunds when the record can't be given, and logs every sale to Discord.
- Genre chips, an Owned filter, search, wallet; `A` / `D` or the mouse wheel to browse, drag to spin, `ESC` to leave.
- Every record has a price, genre and description in `vinyls.lua`; imported records get theirs from `Config.RecordShop.records` (`price = false` = not sold).
- Shopkeeper with ox_target / qb-target, or an [E] prompt. Tills and monitors by the display are hidden for the shopper only. `/recordshop` for admins, `exports['nayzeee-speaker']:OpenRecordShop(index)`.
- Without the Record Console upgrade the shop draws cover cards (vinyl slides out, flip side with the tracklist); with it the sleeves are real 3D props with the album cover on them.
- Bridge: money (cash / bank / item) for ESX, QBCore, Qbox and ox_inventory, room checks, item counts, targets on local peds.
- New item images: one per record (`vinyl_<key>.png`, the record half out of a sleeve in the album's own colours, title + artist), a generic record, the CarPlay unit and a new phone app icon.

**New: audio engine**
- Every value glides between updates (no zipper / steps); natural distance curve (full level within 1.5 m, silent exactly at the range); air absorption; room / hall / street echo with generated stereo reverb.
- True stereo when you're at the speaker (in the car, carrying it, jam, shop preview, closer than 1.2 m), one point in the world further away, with a 0.3 s crossfade between the two.
- Occlusion from 3 rays (doorways sound half open), inside vs outside muffle, sealed cars keep their bass thump and open up with windows / doors / roof.
- Doppler from real velocities, capped at 3 % (`maxDoppler`), never fights the sync check.
- Each speaker model has its own tone (`Config.Audio.voices`); gentle glue compressor and a safety limiter on the master.
- Mixed playlists really crossfade (`Config.Social.mixedFade`). The YouTube fallback's volume changes are smoothed.
- New settings: `reverbLevel`, `occlusionRate`, `roomRate`, `maxDoppler`, `fullVolumeDistance`, `rolloff`, `closeStereo`, `voices`.

**New: phone app**
- Rebuilt: fits lb-phone / qs-smartphone / yseries screens (fluid width, status bar and home bar kept clear, `Config.Phone.insets`), device picker, Now Playing screen with live seek, queue, repeat / shuffle, menus with add to queue / like / add to playlist. Streamer mode hides song names and covers.
- It reads the client's live copy of the speakers about once a second while in use (slower when idle, paused when hidden) and runs the position locally, instead of fetching the full list from the server every 5 s.

**New: Record Console upgrade (optional)**
- A record console you can watch: the record shows in the hand of whoever puts it on, drops onto the spindle, the platter spins up to 33⅓, the tonearm swings over and lowers, and the music starts the moment the needle lands. While it plays the arm creeps inward track by track; pause spins down, skip lifts the arm, the end of the record sends it home.
- Everyone sees the same thing at the same time; someone walking up mid-song sees it already in place. All props are local and cost nothing when no console is near.
- It is added next to the speaker pack (`nayzeee_console`, its own texture dictionary `nayzeee_console_texture` and `nayzeee_console.ytyp`); converting it never replaces any of the pack's files. Until it is converted the pack's turntable keeps working as before (no needle wait) and the shop shows cover cards. Steps in `nayzeee-speaker-assets/README.md`.

**New: jam player**
- Starting or joining a jam opens the player on the jam's own speaker, so what you play goes to everyone in it. `J` on foot opens your jam's player, and the Jam tab has an "Open the jam player" button.

**Fixed**
- The server stripped `mode` from tracks, so every song ran through the YouTube embed (no 3D, and direct `.mp3` links could not play at all).
- A song whose file failed fell back to the embed and then re-mounted the file every frame.
- A removed / private / non-embeddable video or a dead direct link stalled the speaker (or the album). Once most players in earshot report it, it skips to the next song.
- Linked followers ran their own end-of-song check and could advance the whole group; only the leader does now, and a looping leader re-syncs its followers.
- Records: an album could skip straight through when a track took a while to find; linked decks only got the next song when something else synced them; a track whose link stops working now searches "artist title"; skipping stops the current song while the next one is found.
- Records could be handed back twice when a linked deck was emptied, packed or broken, and linking an idle deck that held a record could destroy it.
- Unlinking a speaker duplicated the record and shared the queue. The group keeps its music and the speaker that leaves goes quiet (a leader that leaves with a record keeps it); group counts stay right.
- Shared / mixed playlist flags were read wrong on oxmysql (TINYINT comes back as true / false), so sharing and crossfade toggles misbehaved.
- Collaborators were shown a remove button the server refused; anyone who can add to a playlist can now remove from it.
- Turned-off features now say "That's turned off on this server." instead of silently doing nothing.
- Slow searches, imports, shop previews and prompted playlists were cut off after 15 s; they now get 60 / 150 / 90 / 180 s. The phone's search waits for them too.
- ESX: the fresh speaker snapshot after a character switch never came (`esx:playerLoaded` wasn't registered as a net event); unknown items were treated as real, so unregistered records showed in the shop.
- ox_inventory without a framework: items were not usable. `install/items.md` now gives every item the `useItem` export and the console lists the ones missing it.
- Typing in the car player passed keys to the game (`F` left the car, `J` closed the player).
- Instant placement (`selectLocation = false`) put the speaker to your right. The default offset is now `vector4(0.0, 0.75, 0.0, 180.0)` (x right, y forward); **update it if you keep an old config.lua**.
- A carried boombox could be put down inside a blacklisted zone.
- Phone: commands to a speaker you weren't standing next to were refused ("Move closer") even with `Config.Phone.range = 0`; "Play" on Liked Songs sent every song at once so all but the first hit the rate limit (lists now start on the first song and fill the queue in the background); jam members (not the host) never saw the jam.
- The record console's label and the shop's 3D sleeve covers could never show: FiveM doesn't load `data:` pages in a DUI and drops a page set before its browser exists. They are now real pages in `html/dui/`, applied once the page is ready.
- The shop releasing the record model could break the turntable's record; counter props hidden by the shop were hidden for everyone when they were networked.
- With no custom logo the player showed an empty square; the built-in mark shows until a logo actually loads. The player kept a stale link group after an unlink.

**Hardening**
- Pockets full: taking a record off, packing up and swapping a record only go ahead when the item fits ("No room for it in your pockets."). Where nobody can refuse (a broken speaker, a resource stop, removing a CarPlay unit) the item goes to your pockets, else is dropped at your feet (ox_inventory), else is logged so staff can hand it out.
- Links: someone else's speaker can only be linked while you stand at it; a record taken off through a link goes back to whoever put it on; a locked leader locks the music of its whole group.
- CarPlay units: the server keeps its own list of installed cars, pays a unit back only when one was really removed and refunds a racing double install.
- Song length / end reports and failure reports only count from players who may control the speaker, or from most of the players in earshot.
- Damage: explosion reports need a real explosion nearby; bullet reports need a weapon out or a vehicle; packing, carrying or linking a speaker while its prop is still being made is refused.
- Blend / prompted count toward the playlist limit, run one at a time per player and have cooldowns (10 s / 30 s). Searches: at most 6 at once server-wide, repeated queries share one lookup, one at a time and 20 a minute per player.
- Less traffic: volume / range no longer resend the whole link group; buttons need 0.25 s between presses and link / unlink 0.6 s.

**Changed**
- `config.lua`: new `Config.Looks`, `Config.Turntable` and `Config.RecordShop`; new audio settings (above); `Config.Phone.insets`. Every new key also has a default in the code, so an old config still starts, but without `Config.Looks` / `Config.RecordShop` there are no looks / no shop.
- `fxmanifest.lua`: `client/looks.lua`, `client/turntable.lua`, `client/shop.lua`, `server/shop.lua`, the `html/looks/` and `html/dui/` pages, the phone icon, and two commented lines for the Record Console upgrade.
- The speakers' own `.ycd` animations only play when their dictionary exists.
- Locales: new strings for the shop (`shop_*`, `shop_ui`), the phone app (`phone`), `feature_off`, `rgb_lights`, `jam_play`; unused player strings removed. Missing keys in a translation fall back to English.
- Removed: the unfinished replacement speaker models; the speakers keep the pack's models and are restyled at runtime.
- Asset tools (`nayzeee-speaker-assets`): the renderer no longer leaves a white haze around chrome parts in transparent renders.

## 1.0.1

**Fixed**
- Expand / collapse button: the compact layout targeted an older version of the markup, so all three columns stacked inside a 420px frame and ran off the screen. Compact now shows only the now-playing rail (art, title, search box, seek, transport, volume / range, footer), pinned bottom-right, and is capped to the screen height. The full player is also capped so it fits smaller resolutions.
- Liked songs: the client answered the heart with `1` instead of the list, which broke the UI's favourites array, so the heart never lit up and the second click removed the song again ("Removed from favorites"). Every heart (now playing, search, recent, liked, phone) now gets the real list back and ignores anything else.
- Search results had no `src`, so hearting or adding them to a playlist was silently refused. They now carry `src = 'yt'`.
- Phone app: the heart on a speaker card sent only title / author / thumb, so it could never save. The speaker list now carries the full track.
- Jam sessions were silent: jam emitters never reached the audio engine. Members now hear the jam at full volume in their own ears, and the now-playing card picks it up.
- Records / Tracklist nav entries showed on every speaker (the CSS rule used a class that was never set). They only show on a turntable now.
- Compact state is remembered for every speaker, not only vehicles.
- Init / settings are no longer sent to the NUI page before it has loaded.
- Subtitle toasts ("Nobody else is around") now restore the original subtitle.

**3D audio**
- Listener direction uses the camera's yaw only; the third-person camera's downward pitch was pushing every speaker "below" the listener, which made HRTF sound hollow. Height is still passed, damped.
- Reverb is much drier (max wet ~0.24 instead of 0.5).
- Doppler is smoothed over several frames, ignores jumps (teleports, entering / leaving a car), is clamped to ±4% and defaults to a subtle amount (`Config.Audio.dopplerAmount = 0.6`). The sync check gives doppler room instead of snapping the song back every couple of seconds.
- New `Config.Audio.distanceMuffle`: far speakers lose their highs like real air.
- Turning "3D effects" off now uses plain stereo instead of HRTF with the source parked in front of you.
- Spatial updates every 120 ms (was 200).
