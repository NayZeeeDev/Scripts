# nayzeee-multijob review (v1.0.0)

Reviewed every file in the upload. The corrected build is `nayzeee-multijob-v1.0.0.zip`
next to this file. Only the version was changed; everything below is reported, not fixed.

## What changed in the zip

- Every `1.2.0` string became `1.0.0`: `fxmanifest.lua`, `config.lua` banner, `client/main.lua`,
  `server/main.lua` (header and console banner), `install/install.sql`, `html/index.html`
  (both title bars), `html/app.js`, `html/style.css` (was "UI v5").
- The version now has one source of truth. The server banner and the badge in both title bars
  read `version` from `fxmanifest.lua` at runtime, so the next bump is a one-line edit.

## Critical: server trusts the client

These are exploitable by any player with a Lua executor. None of the admin or job events verify
anything server-side; the only checks live in the NUI and `client/main.lua`.

| # | Where | Problem |
|---|-------|---------|
| 1 | `server/main.lua` admin events (`adminAddJob`, `adminRemoveJob`, `adminBulkAction`) and callbacks (`getAdminData`, `adminGetPlayer`) | No permission check. Anyone can `TriggerServerEvent('nayzeee-multijob:adminBulkAction', 'setjob', {id}, 'police', 10)` and set any player to any job and grade. Check the admin group server-side with the framework (`xPlayer.getGroup()` / `HasPermission`) at the top of every admin handler. |
| 2 | `nayzeee-multijob:checkNewJob` | Takes `newJob` and `newGrade` straight from the client and inserts the row. A player can give themselves `police` grade 10 in their job list, then `switchJob` to it. The server should read the player's real job from the framework object instead of trusting the event args. |
| 3 | `clockIn` / `clockOut` | `jobName` and `dutySeconds` come from the client. Hours, earnings and both leaderboards can be spoofed. Compute duration server-side from `DutySessions[source].startTime` and take the job from the framework. |
| 4 | Cooldowns | Enforced only on the client (`lastJobSwitch`), reset on resource restart. Move to the server. |
| 5 | `quitJob` and `removeJob` | Never check the DB `removeable` flag, only the config list. A job an admin marked non-removable can still be deleted by the player. |

## Bugs

| # | Where | Problem |
|---|-------|---------|
| 6 | `html/app.js` `refreshData()` and `refreshAdminData()` | Both call `post('close')`. The two Refresh buttons close the menu. |
| 7 | `exports('TrackPaycheck')` | Passes `amount` as the first arg; the handler expects `(source, amount, job)`. The export is broken. |
| 8 | Earnings double count | `clockOut` adds `salary * hours` to stats, and `REPLACE_paycheck.lua` also adds every real paycheck. Salary is per paycheck interval, not per hour, so the first number is meaningless and inflates everything. Pick one source (paychecks). |
| 9 | Admin analytics "Most worked jobs" | Server returns `{ job, count }` from `nayzeee_multijob`; the UI renders `j.hours`, so every bar is 0h at 3%. Query `SUM(total_hours)` from the stats table instead. |
| 10 | Inactivity warning | Fires every 10 seconds between the warn and clock-out minute (about 30 toasts). Fire once. |
| 11 | Unemployed auto clock-out | Inactivity clock-out applies to unemployed players too. After that they stop receiving welfare until they reconnect or change job, because the paycheck gate sees them off duty. |
| 12 | Duplicate `clockIn` | A second `clockIn` for the same source overwrites the session and leaves the earlier shift row with `clock_out = NULL` forever (shows "Active" in history). Close the open session first. |
| 13 | External job changes | If another resource sets the job while the player is on duty, the client never clocks out. The server session still has the old job, the client reports the new one, and the hours land on the wrong job. Clock out in the `setJob` / `OnJobUpdate` handlers when `isOnDuty`. |
| 14 | `playerDropped` | Uses grade 0 salary for everyone. |
| 15 | Schedule checker | `diff == 0` and `diff == notifyBefore` are exact matches on a loop that drifts past 60s. Minutes get skipped. Track the last fired minute and use a window. Also runs on server time while the UI shows the player's local clock, with nothing telling the player that. |
| 16 | `Config.Schedule.maxSchedules` and `playerCanCreate` | Never enforced. |
| 17 | `jobs_held` leaderboard | Counts `unemployed`, so everyone gets +1. |
| 18 | Log styling | Server logs `quit_job`; the UI styles `job_quit`. The log filter dropdown also misses `job_added`, `job_removed`, `quit_job` and `admin_bulk_*`. |
| 19 | NUI focus on restart | No `onResourceStop` handler releases `SetNuiFocus`. Restarting the resource with the menu open leaves the player stuck with a cursor. |
| 20 | Unconditional `print`s | Every switch, clock-in and clock-out prints to console regardless of `Config.Debug`. Route them through `Shared.Debug`. |
| 21 | Status bar hint | Shows "↵ Switch job" but no Enter handler exists. |
| 22 | Favorites | Config, locale, DB column and server response all carry favorites, but there is no button, NUI callback or server event to toggle one. The feature is half-built. |
| 23 | Root `install.sql` | Stale duplicate of `install/install.sql` with two extra tables (`_perks`, `_rewards`) nothing uses. Delete it. |
| 24 | `Config.Discord` | Defined, never read. No webhook code exists. |
| 25 | Locale | `Config.Locale` is sent to the UI but the UI never reads it. Every string in `app.js` and `index.html` is hard-coded English. |
| 26 | Dead config | `OffDutyJob`, `AdminPermissions` (sent, never checked), `DutyTracking.dutyZones`, `Leaderboards.refreshInterval` and `categories`, `Categories[].color`. |
| 27 | CDN assets | Lexend and Font Awesome load from Google and cdnjs. Players with the CDN blocked, or an offline dev server, get a fallback font and no icons. Bundle them in `html/`. |

## README drift

- Advertises Job Requirements, Job Perks, `Config.Perks`, `HasPerk` exports, Weekly/Monthly
  reports and Earnings History. None exist in the code.
- Shows `Config.MaxJobs = 5` and `Config.Keybind = 'F6'`; the shipped config is 4 and `false`.
- Says background is `#0f1419`; the UI uses `#000000`.
- Tells people to edit `style.css` for colours in one section and to use `Config.UI` in another.
- Missing from the exports list: `Notify`, `NotifyPlayer`, `IsPlayerOnDuty`, `GetJobEarnings`,
  `TrackPaycheck`, client `ClockIn`, `ClockOut`, `OpenMenu`.
- `notify/adapters.lua` header still documents `phone.enabled`, `phone.alsoShowNotify` and
  `system = false`. The config now uses `output`.
- Copyright year is 2024.

## UI style

No memory directory was available in this session, so I could not compare against your saved
UI style. On its own the UI is consistent: pure black surfaces stepped up by small lightness
increments, one teal accent with derived hi/lo/wash/edge tokens, red for destructive only,
Lexend throughout, cut-corner frame and brand mark, 46px title bar, 190px rail, 26px status bar
with key hints, tabular numerals. Every colour is a CSS variable and `applyTheme` rewrites them
from `Config.UI`, so the theme is portable. Nothing in the CSS contradicts the README's
"NAYZEEE design system" description except the background value noted above.

## Suggested new features (in priority order)

1. **Finish favorites.** Star button on each row, pinned to the top of the list, toggled through
   a `toggleFavorite` NUI callback and server event. Everything else is already there.
2. **Paycheck gate without replacing a core file.** ESX Legacy has
   `xPlayer.setPaycheckEnabled(bool)`. Call it on clock in and clock out and drop
   `REPLACE_paycheck.lua`, which breaks on every ESX update. Keep the file as an optional path
   for old ESX builds.
3. **Discord webhook logging.** The config block exists. Post embeds for job switch, clock in/out,
   admin actions, with the character name and identifier.
4. **Localisation.** Read `Config.Locale` in `app.js` for every string. Ship `locales/en.lua` and
   let `Config.Locale = 'en'` pick the file.
5. **Job conflicts and per-category limits.** `Config.Conflicts = { police = { 'gang', 'mafia' } }`
   and `Config.CategoryLimits = { emergency = 1 }` so a player can hold police or ambulance but
   not both.
6. **Boss integration.** Hook `esx_society` / `qb-management` hire and fire so the job list stays
   in sync when a boss fires someone. Hiring already works through `checkNewJob` once that event is
   fixed.
7. **Duty zones and job center NPC.** The config block exists. Clock in only inside a zone, show
   blips, and open the menu from an `ox_target` ped instead of a command.
8. **Milestones and perks.** The root `install.sql` already has the tables. Unlock a bonus or
   label at N hours per job and show progress bars on the Statistics tab.
9. **Weekly and monthly reports.** `nayzeee_multijob_shifts` has the timestamps. Add a
   "This week / This month / All time" segment to the Statistics tab.
10. **On-duty exports for other scripts.** `GetOnDutyCount(job)` and `GetOnDutyPlayers(job)` for
    dispatch, MDT and "not enough cops" checks.
11. **Shift summary toast.** On clock out, one toast with duration and pay instead of the plain
    "You have clocked out after …".
12. **Admin extras.** Offline lookup by identifier, schedule management (the permission flag
    exists), and enforce `Config.AdminPermissions` server-side.
13. **Server-side cooldowns persisted in the DB** so a restart does not reset them.
14. **Version check** against a GitHub tag on start, printing "update available".
