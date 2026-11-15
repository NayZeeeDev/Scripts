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
| Interface | Players pick their own accent colours, size, notification spot, sounds and HUD parts (Config.UI). |

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

## Race wheels

The menu page reads the wheel through the browser Gamepad API and sends the mapped values into the car every
frame. Anything Windows sees as a game controller works: Logitech, Thrustmaster, Fanatec, Moza, Simagic,
Xbox wheels and pads.

1. Open F5 > Wheel and turn the wheel or press a pedal so Windows wakes it up.
2. Pick a preset and press **Run setup wizard**: turn right, press each pedal fully then let go, pull the paddles.
3. Map any extra buttons. Map Gear 1-7 + Reverse for an H-shifter and pick H-Pattern in Driving.

The **Thrustmaster Ferrari 458 Spider** is an Xbox One wheel with no official PC driver. If Windows shows it as
an Xbox controller, its preset maps it (wheel on the left stick, pedals on the triggers). If Windows doesn't see
it at all, no game or script can read it.

FiveM cannot drive force feedback motors, so wheels get no FFB. Rumble works on devices that support it.

## Config

Everything is in `config.lua`, one block per system. Strings players see are in `locales/en.lua`.
`Config.Everywhere` lets the camera, wheel and gearbox work outside CUT UP mode too.
