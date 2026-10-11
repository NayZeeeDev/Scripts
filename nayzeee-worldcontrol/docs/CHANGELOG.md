# 📝 Changelog

## 2.0.0: nayzeee-traffic is now NAYZEEE WorldControl

### 🐛 Bug fixes (from nayzeee-traffic 1.1.0)

- **Resmon:** the density loop ran every frame forever, even at 100% density. It now runs only while a density is changed, so it's 0.00ms when idle. The new `Config.Performance.densityMode = 'zero'` option avoids per-frame natives entirely.
- **Resmon:** the services thread called 12+ natives every second. Services are now applied once when they change, with a light check every 15s.
- **The UI broke if the folder was renamed.** The NUI used a hardcoded `https://nayzeee-traffic/` and now uses `GetParentResourceName()`.
- **0% showed as 100%** in the panel (`settings[type] || 1.0` treats 0 as falsy).
- **Permission race:** the client waited a fixed 1 second and could use a stale or default result. The panel now opens only after the server confirms permission.
- **Wrong QBCore check:** it compared the player's **job name** to `admin`/`god`. It now uses `QBCore.Functions.HasPermission`.
- **No server validation:** any client could send any table as the new settings, with unlimited values or extra keys. Every value is now validated and clamped on the server.
- **Sync flag desync:** the `isUpdating` flag could swallow the next real sync from another admin.
- **Random preset order:** presets were built with `pairs()`, so their order shuffled. They're now an ordered list.
- **"Save Settings" was misleading:** it saved to the client's KVP, and the server state overwrote it. State is now saved on the server automatically.
- Only dispatch services 1-12 were disabled. All 15 are now handled.
- The console banner said version 1.0.0 while the manifest said 1.1.0. It now reads the version from the manifest.
- Notifications required ox_lib. Built-in toasts are now used as a fallback.

### ✨ New

- A full weather system: dynamic weighted cycle, forecast, skip and reroll, instant or smooth changes, and real-world weather.
- A full time system: a server-owned clock with no per-frame loops, quick times, smooth sky roll, freeze, day length and real-world time.
- Atmosphere controls: blackout, snow on the ground, synced wind and wind direction, and rain intensity.
- Ambient service toggles in the panel: dispatch, garbage trucks, boats, trains, cop patrols, wanted level and distant sirens.
- Scenes, lightning strikes, and a restart warning (storm, blackout, siren and countdown) that auto-starts with txAdmin.
- An activity log with optional Discord webhook, and live multi-admin panel sync.
- Quick commands: `/weather`, `/time`, `/freezetime`, `/blackout` and `/restartwarning`.
- Compatibility with the qb-weathersync, vSync and cd_easytime pause events for interiors.
- More exports (see the README).
