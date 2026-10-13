# 💼 NAYZEEE MultiJob

Advanced Multi-Job Management System for FiveM with comprehensive tracking, scheduling, and admin features.

![Version](https://img.shields.io/badge/version-1.0.0-08afa2)
![Framework](https://img.shields.io/badge/framework-ESX%20%7C%20QBCore%20%7C%20QBox-blue)

---

## ✨ Features

### Jobs
- **Multiple jobs per character** - switch between them from one menu
- **Job Categories** - Emergency, Government, Business, Service, Underground, Civilian, with icons
- **Favorite Jobs** - star the ones you use most, they sort to the top
- **Search & Filter** - instant search, press Enter to switch to the top result
- **Hire detection** - a job set by any boss menu or admin command is added to the list automatically

### Duty & Time Tracking
- **Server-side clock in / out** - the server owns duty state, so it can't be faked
- **Live shift timer** and **shift history** with what each shift paid
- **Auto clock-out** after inactivity; the default job pauses and resumes when the player moves
- **Paycheck gating** - ESX via `install/REPLACE_paycheck.lua`, QBCore / QBox via the framework's own duty flag
- **Crash and restart safe** - open shifts are saved every minute and resumed after a resource restart

### Statistics & Rankings
- **Hours, earnings and shifts** per job
- **Leaderboards** for hours, earnings and jobs held (cached, character names, your row highlighted)

### Schedules
- **Auto-switch at a set time** on chosen days, with a reminder beforehand
- Pause / resume or delete schedules, limit per player

### Team Tab (for bosses)
- **Roster of everyone in the job** - online and offline, on duty, hours this week and in total
- **Hire** people standing near you - they get an offer to accept or turn down
- **Promote, demote and let go** staff below your own grade, even while they are offline

### Clock-in Points
- **Clock in at the station** - jobs with points only clock in there
- **Press E** (ox_lib text UI) or an **ox_target** option at the point, with map blips
- Clocking in from the menu elsewhere marks the nearest point on the map

### Admin Panel
- **Player management** - view, add and remove jobs for anyone online
- **Offline characters** - search everyone who has played by name or identifier and edit their jobs
- **Bulk operations** - add, remove or set a job for many players at once
- **Activity logs** and **job analytics**
- **Per-permission tabs** - every action is checked on the server

### Smart Features
- **Job Cooldowns** - enforced on the server to stop rapid switching
- **Discord logging** - webhook kept server-side
- **Notifications** - 12 notify resources and 9 phones supported

---

## 📦 Dependencies

| Dependency | Required |
|------------|----------|
| [ox_lib](https://github.com/overextended/ox_lib) | ✅ |
| [oxmysql](https://github.com/overextended/oxmysql) | ✅ |
| ESX / QBCore / QBox | ✅ |

---

## 🔧 Installation

1. Download and extract to your resources folder
2. Add `ensure nayzeee-multijob` to your server.cfg
3. Database tables are created automatically on first start
4. Configure `config.lua` to your preferences
5. Restart your server

---

## ⚙️ Configuration

### General Settings
```lua
Config.MaxJobs = 4          -- Maximum secondary jobs (the default job never counts)
Config.Command = 'jobs'     -- Command to open menu
Config.AdminCommand = 'jobadmin'  -- Admin panel command
Config.Keybind = false      -- e.g. 'F6', or false to disable
```

### Job Categories
```lua
Config.Categories = {
    emergency = {
        label = 'Emergency Services',
        icon = 'fa-solid fa-truck-medical',
        color = '#ef4444',
        jobs = { 'police', 'ambulance', 'firefighter' }
    },
    -- Add more categories...
}
```

### Cooldowns
```lua
Config.Cooldowns = {
    enabled = true,
    globalCooldown = 300,  -- 5 minutes
    jobCooldowns = {
        police = 600,      -- 10 minutes for police
    },
    exempt = { 'unemployed', 'offduty' }
}
```

### Earnings
```lua
Config.Earnings = {
    mode = 'auto',          -- 'paycheck' | 'estimate' | 'auto'
    paycheckMinutes = nil,  -- nil = framework default (ESX 7, QBCore 10)
}
```

| Mode | Where earnings come from |
|---|---|
| `paycheck` | Real paychecks only, reported by `install/REPLACE_paycheck.lua` or `TrackPaycheck` |
| `estimate` | `salary x shift length / paycheckMinutes` - no paycheck hook needed |
| `auto` | `paycheck` on ESX, `estimate` on QBCore / QBox |

### Team tab (bosses)
```lua
Config.Boss = {
    enabled = true,
    minGrade = {},             -- e.g. police = 3 to make grade 3+ a boss
    promoteToOwnGrade = false, -- bosses hand out grades up to one below their own
    hireDistance = 5.0,        -- metres; 0 = hire anyone online
    requireAccept = true,      -- new hires get an accept / decline pop-up
    offerTimeout = 60,
    permissions = { hire = true, fire = true, promote = true },
}
```

Who counts as a boss: QBCore / QBox grades with `isboss = true`, ESX grades named
`boss` (the same rule as esx_society), or a job's highest grade when nothing is
marked. A boss only ever manages staff below their own grade and can never give
out a grade above the limit.

The roster includes staff who are offline and staff who only have the job in
the framework (hired before the resource was installed). Firing someone who is
working the job right now drops them to the default job, online or offline.

### Clock-in points
```lua
Config.DutyPoints = {
    enabled = true,
    interact = 'textui',     -- 'textui' (press E) | 'target' (ox_target) | false
    blips = true,
    clockOutAtPoint = false,
    waypoint = true,
    points = {
        { job = 'police', label = 'Mission Row PD', coords = vec3(441.1, -981.9, 30.7), radius = 3.0,
          blip = { sprite = 60, colour = 29, scale = 0.7 } },
    },
}
```
Only jobs with a point are restricted; every other job clocks in anywhere. The
server checks the player's real position (OneSync), so it can't be skipped from
the client. QBCore's own duty toggles (station duty scripts, `/duty`) still work.

### QBCore / QBox duty sync
```lua
Config.DutyTracking.syncFrameworkDuty = true
```
Clocking in through the menu sets QBCore's own on-duty flag - which is what
QBCore paychecks check - and a duty toggle from any other script (a station
duty point, `/duty`) starts or ends the shift here. No core files to replace.

---

## 📋 Commands

| Command | Description |
|---------|-------------|
| `/jobs` | Open the job menu |
| `/jobadmin` | Open admin panel (requires permission) |

### Admin access

Checked on the server every time. A player gets the panel if their group is in
`Config.AdminGroups` (ESX `xPlayer.getGroup()`, QBCore permission or the
`group.<name>` ACE), or if they have this ACE:

```
add_ace group.admin nayzeee-multijob.admin allow
```

Turn single tabs off for everyone with `Config.AdminPermissions`.

The Players tab has an **All characters** switch: search by name or identifier
to open anyone who has ever played. Adding, removing or making a job active
works the same online or offline - offline changes are written to the
framework's saved job (`users` on ESX, `players.job` on QBCore, QBox's own
exports on QBox).

---

## 🔌 Exports

### Client Exports
```lua
exports['nayzeee-multijob']:GetPlayerJobs()         -- jobs on the player's record
local job, grade = exports['nayzeee-multijob']:GetCurrentJob()
exports['nayzeee-multijob']:IsOnDuty()
exports['nayzeee-multijob']:GetDutyTime()           -- seconds in the current shift
exports['nayzeee-multijob']:ClockIn()
exports['nayzeee-multijob']:ClockOut()
exports['nayzeee-multijob']:OpenMenu()
```

### Server Exports
```lua
exports['nayzeee-multijob']:IsPlayerOnDuty(source)
exports['nayzeee-multijob']:GetDutyTime(source)
exports['nayzeee-multijob']:ClockIn(source)
exports['nayzeee-multijob']:ClockOut(source)
exports['nayzeee-multijob']:SwitchJob(source, 'mechanic')   -- must be on their record
exports['nayzeee-multijob']:GetPlayerJobs(source)
exports['nayzeee-multijob']:AddPlayerJob(source, 'mechanic', 2)
exports['nayzeee-multijob']:RemovePlayerJob(source, 'mechanic')
exports['nayzeee-multijob']:GetJobHours(source, 'police')
exports['nayzeee-multijob']:GetJobEarnings(source, 'police')
exports['nayzeee-multijob']:TrackPaycheck(source, amount)   -- call from any paycheck loop
exports['nayzeee-multijob']:IsAdmin(source)
exports['nayzeee-multijob']:IsBoss(source, 'police')
exports['nayzeee-multijob']:GetBossJobs(source)             -- { { name, label, grade, gradeLabel } }
```

---

## 📁 Folder Name

The folder **must** be named exactly `nayzeee-multijob`.

If it is renamed, `lock.lua` prints the reason to console and stops the
resource before anything else loads — it will not run half-working. The name
is baked into the exports, the `nayzeee-multijob:*` events and
`install/REPLACE_paycheck.lua`, so a rename would break duty checks, paycheck
gating and notifications silently.

`lock.lua` is encrypted with the rest of the resource, not in `escrow_ignore`.

---

## 🎨 UI Theme

The whole menu is driven off `Config.UI`. Change the accent and every teal
element follows it — nav highlight, buttons, tags, meters, the brand mark, the
glow on the duty ring.

```lua
Config.UI = {
    accent     = '#08afa2',  -- one value themes the entire menu
    accentHi   = nil,        -- nil = derived from accent
    accentLo   = nil,
    danger     = '#e5484d',  -- Close pill, deletes, warnings
    background = '#000000',  -- surfaces step up from this automatically
    font       = 'Lexend',
    title      = 'Job Center',
    subtitle   = 'Employment Services',
    grain      = true,       -- film grain over the window
    watermark  = true,       -- faded shape bottom-right

    width      = 860,        -- window width in px
    height     = 470,        -- content area height in px
    sidebar    = 190,        -- left nav rail width in px
}
```

The menu is a compact in-game panel by default, not a full-screen takeover.
`width` / `height` / `sidebar` resize it without touching the CSS — the layout
is built on those three tokens.

Only `accent` is needed. Highlights, gradients, washes and borders are derived
from it at runtime, and button text flips between black and white depending on
how light the accent is, so nothing goes unreadable.

Changing `font` also means swapping the Google Fonts link in
`html/index.html` for the family you want.

---

## 🔔 Notifications & Phone Support

One switch decides what the player sees. A message is never shown twice unless
you ask for it.

```lua
Config.Notifications.output = 'notify'
```

| Value | Result |
|---|---|
| `notify` | on-screen notification only — no phone |
| `phone` | phone notification only — no on-screen popup |
| `both` | both at once (optional) |

If `output` is `phone` but no supported phone is running, messages fall back to
the on-screen notify so nothing is silently lost, and the console says so once
on startup.

### Which notify resource

```lua
Config.Notifications.system = 'auto'
```

`auto` · `nayzeee` · `ox_lib` · `okok` · `codem` · `mythic` · `brutal` ·
`t-notify` · `qb` · `esx` · `esx_advanced` · `chat` · `native`

`native` uses the GTA feed and needs no dependency at all.

### Which phone

```lua
Config.Notifications.phone = {
    resource = 'auto',
    app      = 'Wallet',
}
```

`auto` · `lb-phone` · `qs-smartphone` · `qs-smartphone-pro` · `gksphone` ·
`roadphone` · `yflip-phone` · `high-phone` · `npwd` · `qb-phone`

### Adding your own

`notify/adapters.lua` is open (escrow_ignore). Add one function and point the
config at it:

```lua
-- client
NayNotify.Systems['myNotify'] = function(data)
    exports['my-notify']:Send(data.title, data.message, data.type, data.duration)
end

-- server (phone)
NayNotify.Phones['my-phone'] = function(src, data)
    exports['my-phone']:Notify(src, data.app, data.title, data.message)
end
```

Phone resources change their export signatures between versions. If a phone
doesn't fire on your build, fix that one function — nothing else changes.

### Notification exports

```lua
exports['nayzeee-multijob']:Notify(src, { title = 'Job', message = 'Hello', type = 'success' })
exports['nayzeee-multijob']:NotifyPlayer(src, 'Job', 'Hello', 'success')
exports['nayzeee-multijob']:GetActivePhone()       -- detected phone name, or nil
exports['nayzeee-multijob']:RefreshNotifyTargets() -- re-detect after restarting a phone
```

---

## 📜 Discord Logging

Set up in `config_server.lua`, which is never sent to players - a webhook in
`config.lua` could be read and spammed by anyone who joins.

```lua
ServerConfig.Discord = {
    enabled = true,
    webhook = '', -- or: set nayzeee_multijob_webhook "https://discord.com/api/webhooks/..."
    logEvents = { jobSwitch = true, clockIn = true, clockOut = true, adminAction = true },
}
```

---

## 💵 ESX Paycheck Integration

`install/REPLACE_paycheck.lua` replaces `es_extended/server/paycheck.lua`.
Players only get paid while clocked in through the job menu; unemployed players
still receive welfare normally.

Options at the top of that file:

```lua
local NAYZEEE = {
    requireClockIn    = true,          -- pay only while clocked in
    notifySkipped     = true,          -- tell the player why they weren't paid
    useMultijobNotify = true,          -- use Config.Notifications (phones + notify)
    fallback          = 'esx_advanced',-- used if multijob is stopped
}
```

Paycheck amounts are written back into `nayzeee_multijob_stats` so the earnings
leaderboard and shift history stay accurate.

Not on ESX? Call `exports['nayzeee-multijob']:TrackPaycheck(source, amount)`
from your paycheck loop and set `Config.Earnings.mode = 'paycheck'`.

---

## 🎨 Customization

The UI uses the NAYZEEE design system:
- **Primary Color:** `#08afa2` (Teal)
- **Danger:** `#e5484d` (Red)
- **Background:** `#000000` (Black)
- **Font:** Lexend

Use `Config.UI` for colours and size first; `html/style.css` for anything deeper.

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Menu won't open | Check if ox_lib is started before this resource |
| Jobs not saving | Verify oxmysql is connected and running |
| Admin panel access denied | Add your group to `Config.AdminGroups` |
| Cooldown not working | Check `Config.Cooldowns.enabled` is true |
| Paid while clocked out (ESX) | Install `install/REPLACE_paycheck.lua` |
| Paid while clocked out (QBCore) | Keep `Config.DutyTracking.syncFrameworkDuty = true` |
| Shift clock-in time equals clock-out | Old table definition - restart once, the resource fixes the column itself |
| Nobody shows up in the Hire list | Stand within `Config.Boss.hireDistance`, or set it to `0` on servers without OneSync |
| Team tab missing | The player needs a boss grade - see `Config.Boss.minGrade` |
| Can clock in anywhere despite points | Set `Config.DutyPoints.enabled = true` and check the point's `job` name |

---

## 📞 Support

- Discord: [discord.gg/nayzeeedev](https://discord.gg/nayzeeedev)
- Documentation: Coming soon

---

## 📄 License

© 2024 NAYZEEE Development. All rights reserved.
