# CUT UP - NayZeee Development

No Hesi style highway cut-up for FiveM. Dense traffic that reacts to you, near-miss scoring with combos,
crews with ghosting and flow state, a full leaderboard, cockpit FOV cameras and race wheel support.

Discord: discord.gg/nayzeeedev

## Install

1. Drop `nayzeee-cutup` in your resources folder.
2. Add `ensure nayzeee-cutup` to your `server.cfg` (after `oxmysql` if you use it).
3. Turn on OneSync (Infinity recommended) so traffic, crews and ghosting sync between players.
4. Optional: `add_ace group.admin cutup.admin allow` for `/cutupadmin`.

Storage is automatic. With `oxmysql` running the tables are created on start (`sql/install.sql` has them too).
Without it everything goes to `data/db.json`.

If your server uses `sv_entityLockdown strict`, client-spawned traffic is blocked. Use `relaxed` or set
`Config.Traffic.Networked = false` (traffic is then local to each player).

## Features

| Feature | What it does |
| --- | --- |
| Cockpit FOV | Custom in-car camera with your own FOV, seat position and tilt. Free look, look back, speed FOV, road shake. |
| Camera angles | Cockpit, hood, bumper, chase near, chase far, cinematic low, GTA native. Chase cams are smoothed and never clip through walls. |
| Race wheels | Any wheel Windows lists as a game controller. Setup wizard, per-device profiles, calibration, curves, deadzones, H-shifter, paddles, rumble. |
| Dense traffic | Native density plus scripted cars topped up ahead of you. Shared between players so crews don't stack traffic. |
| Lane changes | Traffic changes lanes on its own with blinkers, only into lanes that are clear and going the same way. |
| NPC awareness | Drivers notice you in their mirrors after a short reaction time. Yielders move over, stubborn drivers speed up or flash you, nervous ones brake-tap and honk. |
| High beam flash | Hold G (or use your real high beams) and cars ahead in your cone move over. |
| Collisions | Deformation lands where you were actually hit. Tyre bursts, smashed glass, hood pops, bent steering, limp mode. Hit NPCs put their hazards on and honk. |
| Gearbox | Automatic, sequential or H-pattern with clutch. Rev limiter bounce, no accidental reversing. ABS and TC lights on the tacho. |
| Scoring | Near misses graded INSANE, VERY CLOSE, CLOSE or PASS. Combo with hold and bleed, speed multiplier up to 9.9x, oncoming bonus. |
| Bonuses | Aggro multiplier, physics bonus (manual or wheel), FPV bonus (cockpit cam), sync and crew flow. |
| Runs | 15:00 timer, 3 hearts, crash penalty, run summary card, server-validated submissions. |
| Flow state | Match another driver's speed and line to build sync. Crew flow pays more for every extra crewmate in the train. |
| Crew gap | The more crewmates on the road together, the bigger the gap you can keep and stay in flow. |
| Ghosting | Players outside your crew drive straight through you, and they render see-through. |
| Threat arrows | Red arrows orbit your car while a non-crew player closes in, and drop off once they pass. |
| Leaderboard | Solo, crew runs and crews boards with expandable run details, search and your pinned position. |
| Ranks | Rookie through Legend by personal best, with progress to the next rank on the HUD. |
| Interface | NayZeee UI settings window. Players pick their own menu accent, HUD colours, size, notification spot, sounds and HUD parts (Config.UI). |
| Notifications | ox_lib (`lib.notify`) when it's running, otherwise the GTA feed. Quick feedback (camera, FOV, gearbox) shows as a small hint on the HUD. |

## Keys and commands

All keys are rebindable in Settings > Key Bindings > FiveM.

| Key | Command | Action |
| --- | --- | --- |
| F6 | `/cutup` | Toggle CUT UP mode |
| F5 | `/cutupmenu` | Menu (also `/wheel`, `/crew`, `/cutupsettings`) |
| F10 | `/leaderboard` | Leaderboard |
| V | `/cutupcam` | Cycle camera |
| PAGE UP / DOWN | | FOV up / down |
| LSHIFT / LCTRL | | Shift up / down |
| X | | Clutch (hold) |
| G | | Flash high beams (hold) |
| F7 | `/cutuphud` | Toggle HUD |
| | `/cutuprepair` | Repair while stopped with no run going |
| | `/cutupadmin resetboards` | Wipe every leaderboard |
| | `/cutupadmin resetplayer <id>` | Wipe one driver's bests |

ox_lib is optional. Set `Config.Notify` to `'native'` to always use the GTA feed, or `false` to turn notifications off.

## Race wheels

The menu page reads the wheel through the browser Gamepad API and sends the mapped values into the car every
frame. If Windows lists it under "Set up USB game controllers" (joy.cpl), it works. Presets ship for:

| Brand | Wheels |
| --- | --- |
| Logitech | G29, G920, G923, G27, G25, Driving Force GT, G Pro |
| Thrustmaster | T80, T128, TMX, T150, T248, T300RS, TX, T-GT, TS-PC, TS-XW, T-GT II |
| Thrustmaster (Xbox) | Ferrari 458 Spider, Ferrari 458 Italia (when Windows shows them as an Xbox controller) |
| Fanatec | CSL Elite, CSL DD, GT DD Pro, ClubSport, Podium DD |
| Moza | R3, R5, R9, R12, R16, R21 |
| Simagic | Alpha Mini, Alpha, Alpha U, Evo |
| Others | Cammus C5 / C12, PXN V9 / V10 / V12, Hori Racing Wheel / Apex, any Xbox or PlayStation pad |

**Separate pedals, shifters and handbrakes work too**, whether they plug into the wheel base or into their own
USB port: Heusinkveld, Simagic P1000 / P2000, Fanatec, Thrustmaster T-LCM / TH8A / TSS, Logitech Driving Force
Shifter, Moza SR-P / HGP / HBP and any USB handbrake. Pick your wheel as the **main device**, then run the wizard
or hit Detect and use the pedal, shifter or button: the script finds it on whichever device it lives on and links
that device to your wheel. The device list shows them as **Main** and **Linked**.

1. Open F5 > Wheel and turn the wheel or press a pedal so Windows wakes it up.
2. Pick a preset, switch on **Main device** and press **Run setup wizard**: turn right, press each pedal fully then let go, pull the paddles.
3. Map any extra buttons. For an H-shifter map Gear 1-7 + Reverse and pick H-Pattern in Driving. For a sequential shifter map Shift up / Shift down and pick Sequential.

The **Thrustmaster Ferrari 458 Spider** is an Xbox One wheel with no official PC driver. If Windows shows it as
an Xbox controller, its preset maps it (wheel on the left stick, pedals on the triggers). If Windows doesn't see
it at all, no game or script can read it.

FiveM cannot drive force feedback motors, so wheels get no FFB. Rumble works on devices that support it.

## Config

Everything is in `config.lua`, one block per system. Strings players see are in `locales/en.lua`.
`Config.Everywhere` lets the camera, wheel and gearbox work outside CUT UP mode too.
