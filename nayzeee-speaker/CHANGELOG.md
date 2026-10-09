# Changelog

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
