# 📥 Installation

> Step-by-step installation for NAYZEEE WorldControl

---

## 📋 Prerequisites

- ✅ FiveM Server (recent artifacts)
- ✅ ox_lib (optional; without it the built-in NAYZEEE toasts are used)

---

## 🚀 Installation Steps

### Step 1: Remove old weather/traffic scripts

WorldControl replaces all of these. Running them together makes them fight over weather and time.

- `nayzeee-traffic`
- `cd_easytime`
- `qb-weathersync` / `qbx_weathersync`
- `vSync` / `weathersync`

Remove their `ensure` lines from `server.cfg`. The server console warns you if any of them are still running.

### Step 2: Download & Extract

1. Extract to your `resources` folder
2. Make sure the folder is named `nayzeee-worldcontrol`

### Step 3: Add to Server Config

```cfg
ensure nayzeee-worldcontrol
```

### Step 4: Permissions

In your `server.cfg`:

```cfg
add_ace group.admin worldcontrol.admin allow
```

ESX groups, QBCore permissions (`god`, `admin` and so on) and Qbox `group.*` ACEs from `Config.Permissions.allowedGroups` work automatically. The old `traffic.control` ACE still works too.

### Step 5 (optional): Real-world weather

1. Get a free API key from [openweathermap.org](https://openweathermap.org/api)
2. In `shared/config.lua`, set `Config.Weather.real.apiKey` and `Config.Weather.real.city`
3. Toggle **Real-World Weather** in the panel, or set `Config.Weather.method = 'real'`

### Step 6: Restart

```
ensure nayzeee-worldcontrol
```

---

## 🔄 Upgrading from nayzeee-traffic

- Your traffic presets now live in `Config.TrafficPresets` as an ordered list, and `Config.Defaults` is now `Config.Traffic.defaults`.
- `/traffic` still opens the panel because it's in `Config.CommandAliases`.
- The `traffic.control` ACE still works.
- The legacy exports `GetServerSettings` and `SetServerSettings` still work. Update the resource name in your calls to `nayzeee-worldcontrol`.
- Settings now save automatically on the server, so the old "Save Settings" button is gone.

---

## ⚠️ Troubleshooting

| Issue | Solution |
|-------|----------|
| UI not opening | Check F8 for errors and make sure you have permission (the server tells you if you don't) |
| Weather flickers or resets | Another weather script is still running. Check the server console for the conflict warning. |
| Weather wrong inside houses | Your housing script must trigger the pause events listed in the README |
| Real weather not working | Check the API key and city name. Errors are printed in the server console. |
| Restart warning didn't auto-start | Make sure `Config.RestartWarning.txAdmin = true` and the restart is scheduled in txAdmin |
