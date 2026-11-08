# V2 change request (owner, verbatim intent + decisions)

Reference images: `/tmp/claude-0/-home-user-Scripts/939d8efe-994e-5a21-be29-bbf4e311b951/images/<n>`
(open them with the Read tool).
- **Owner's own UI** (copy the look): `1.png` / `5.png` = control-prompt bar (dark rounded bar,
  bordered key chips + white labels, bottom centre); `2.png` / `6.png` = the owner's
  "Vehicle Controls" menu (wide bottom panel, grid of square icon tiles with a label under the
  icon, tiny teal corner tags such as FL / FR / Driver, active tile = teal outline + teal wash,
  disabled tiles dimmed, "ESC to close" top right).
- **Competitor screens (JG)** — `3, 4, 7–26` — show WHICH FEATURES the owner wants. Never copy
  their layout, artwork, wording or branding. Build every screen in the owner's style
  (docs/UI_KIT.md, docs/design/*.html: Lexend, chamfered corner, grain, teal brand mark, teal
  toggles — never blue —, white-active pills, chips, uppercase section headings, red Close pill).

Everything stays original, open Lua, server-authoritative, translated (L()/t()), CEF-safe CSS.

## A. Garage menu (Showroom)
1. The vehicle image in the showcase becomes a **slowly spinning 3D model of the real car**:
   spawn a local (non-networked) preview vehicle with the stored props at a hidden studio spot
   (or near the garage, invisible to others), point a scripted camera at it, and make that part
   of the NUI stage transparent so the game render shows through; the NUI reports the stage
   rectangle so the camera framing fits it; rotate continuously; swap on selection; clean up on
   close / resource stop; fall back to the image when the model cannot load or in the browser.
   **Remove the spotlight** at the top of the stage.
2. Condition, Performance, Upgrades and Details become **collapsible dropdown sections**
   (accordion) with a control to **expand all at once**; remember the open state.
3. **"Enter interior"** button: teal (primary), not dark.
4. **Trailers**: a vehicle stored while towing a trailer must save the trailer and bring it
   back attached on retrieval (verify the whole path end to end and fix what is broken).
5. **Finance**: keep it, but the owner is writing a dealership script and will integrate other
   dealership scripts: expose a clean finance API (server exports to set / clear / read finance,
   record payments, an event when a payment is made or missed) and document it.

## B. Interiors
1. Default GTA garage interiors (IPL profiles in config/interiors.lua) come with **preset
   vehicle slots** at the default car positions and headings — no setup needed. Server owners
   can still build / edit their own interiors in the creator (option kept).
2. Entering an interior plays a **clean, unhurried cinematic camera**: a smooth path across the
   parked cars that ends on the player's character (eases, no jump cuts, ~6–9 s, skippable).
3. **Every player sees their own interior with their own vehicles** (own routing bucket), not
   other players' (config option for the current shared / invite behaviour).
4. In the interior, vehicle info is shown **floating above the car** when the player walks
   near it (not inside the car); sitting in the car shows **"Accelerate to leave the garage"**.

## C. Impound tow truck
Today the NPC gets stuck or despawns and takes the car with it. Make it reliable and
immersive: the flatbed drives up and stops **in front of** the impounded vehicle, the driver
gets out, walks to the controls, the car is **visibly loaded onto the bed**, the driver gets
back in and drives away; the car never disappears before it is on the bed, the truck never
leaves without it, and stuck trucks recover (re-path, nudge, teleport out of sight as last
resort). Test the geometry carefully (bed bone / offsets / ramp).

## D. Control prompts
Replace the transparent key-hint / prompt widgets with the owner's prompt bar (`1.png`):
dark solid rounded bar at the bottom centre, each control = bordered key chip(s) + label.

## E. Vehicle setup (liveries / extras)
Move to the **bottom middle**, wider and more detailed, like the owner's Vehicle Controls menu
(`2.png`): tile grid with icons, labels, corner tags, active = teal. Players can **orbit the
camera around the car** while choosing (mouse drag / keys, zoom).

## F. Garage zones (polyzones)
Instead of driving into a store circle, each garage has a **polygon zone** drawn by the admin
in the location editor (in-world point placement, ox_lib `lib.zones.poly`, no PolyZone
dependency). Inside the zone players can open the garage (see vehicles) and store vehicles.
Keep backwards compatibility with existing point-based locations.

## G. Vehicle keys (big rework)
1. **Key modes**: Flexible (default; inventory item; reuses a held or stored key, then creates
   one if allowed; sharing creates a copy, the sender keeps theirs) · Limited (inventory item;
   fixed starting set, 2 by default; sharing gives away the sender's copy) · Virtual (no item;
   issues access when allowed; sharing shares access, the sender keeps theirs).
2. **Keyless entry and exit**: with the fob on you, a locked car unlocks as you get in; walking
   away auto-locks at a set distance (per-player settings).
3. **Key ring**: find the right car; **tap** = lock / unlock, **hold** = start the engine,
   **keep holding** = roll the windows down. Grid of fob renders (several original fob designs),
   detail pane with lock / engine / distance, actions Use key, Inspect, Track, Share, Drop.
4. **Fob HUD**: an on-screen fob (position + size editable in an edit mode, keybind prompts
   toggle) with Throw / Inspect / Move / Help / Close.
5. **Physical key props**: hand keys up close, **throw** them a few steps for a catch (a missed
   catch leaves them on the ground), **toss them out of the driver's window** (bikes / quads have
   their own seated toss); keys on the ground are world props anyone can pick up; **inspect** a
   ground key (fob, vehicle name, plate; Keep / Return to ground) or one you carry.
6. **Lock picking**: a fully 3D five-pin lock in the NUI (tension the cylinder, find the binding
   pin, lift it to the shear line; overset / too much force snaps the pick, alarm sounds).
7. **Hotwiring**: match and splice three pairs of coloured wires behind the dash, or use a
   handheld **reader** to tune into the ignition signal (frequency / phase until the match is
   100%). Admins choose which classes need the reader and override models in game.
8. **Immobilisers & Ghost PINs**: a standard immobiliser blocks hotwiring; **Ghost** requires a
   four-digit PIN before the engine starts (even with keys), disables remote start, alarm +
   cooldown after repeated wrong guesses.
9. **Hold up NPC drivers**: reactions (hand over keys, drop them and run, fight, drive away)
   tunable in game, plus police requirements and dispatch delays.
10. **Track vehicle** modal (from the key ring and the garage): live map (our calibrated maps),
    street, distance / last seen, plate, lock, engine, tracking, alarm, immobiliser; Set waypoint.
11. **Player settings** (per player, saved): keyless auto-unlock / auto-lock / distance, start
    engine when entering, keep engine running on exit; fob beep, hints, position; key order,
    combined keyring for new keys, ground key prompts, distance units; lock / engine / sharing
    alerts, share recall reminder.
12. **Admin key manager** (`/vehiclekeysadmin`): search a player (name, citizen id, plate),
    their keys with type, origin, custody (inventory slot / stash / ground), vehicle spawned /
    distance; give key, track, delete; totals (keys, vehicles, shared in / out).
13. **Admin settings in game** (DB, tabs): Keys (default fob design, remote range, lock
    selection preferences, sharing limits / time, who can track), Ground keys (animate drops,
    keep after restart, remove after, markers style / colour / size / height), Vehicles,
    Lockpicking, Hotwiring, NPC keys, Job vehicles, Security.
