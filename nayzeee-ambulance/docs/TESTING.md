# NAYZEEE AMBULANCE · in-game test list

Go through it top to bottom on a test server. Tick each line; when one fails, note **what you did,
what happened, and what you expected**, and grab the F8 console (client) and the server console.

Before you start: restart the resource, then look at F8 and the server console. There should be no
red errors. Test as a medic **on duty** unless a line says otherwise.

## 1 · Duty, job menu, NPC calls
- [ ] Clock on at a **Shift Clock** point. A toast confirms it.
- [ ] **F6** opens the EMS job menu.
- [ ] With NPC calls never touched, **no NPC 911 calls** arrive (wait 5 minutes).
- [ ] Job menu → **Dispatch → NPC calls** says it is off. Click it → toast "NPC 911 calls on".
- [ ] Within a few minutes an NPC call comes in (call card + pager).
- [ ] Switch it off again → no new calls. Reconnect → your choice is remembered.

## 2 · Supply officer & medical bag
- [ ] `/nzadmin` → hospital builder → place a **Supply Officer** point. An NPC with a clipboard stands there.
- [ ] Target the NPC → **Supply officer: medical bag & supplies** → take the **Medical Bag** (one per shift).
- [ ] Use the bag item → it goes on the ground in front of you.
- [ ] Open it: only the **bag** shows (no "Your pockets"). Every slot reads **∞**.
- [ ] Click a supply → you get one. Shift + click → you get up to its limit. Once at the limit → "You already carry …".
- [ ] Colour button → change the colour → the bag on the ground changes colour.
- [ ] **Carry** the bag: it hangs at your side by its handle (not through your leg or arm).
- [ ] Walk, run and **sprint** while carrying it. Other players see it in your hand.
- [ ] While carrying: **G** puts it down, **E** opens it, **H** puts it in your inventory.

## 3 · Press-E prompts & third eye
- [ ] Walk up to something with a prompt: the **[E] pills** show on the right side, like the original.
- [ ] Hold the third eye (Alt / your target key) → the E pills **hide**. Let go → they come back.
- [ ] With the care card open, the pills sit left of the card, not under it.

## 4 · NPC patient on scene (with NPC calls on)
- [ ] Respond to a call, reach the scene. The care card lists the steps.
- [ ] Third eye on the patient shows the next step highlighted.
- [ ] **Stop the bleeding** → 3D close-up (pressure, pack, wrap). Clicks and holds register; no lag.
- [ ] **Tourniquet** → 3D close-up (place, pull slack, twist, lock).
- [ ] **IV** → 3D forearm close-up (tourniquet, vein, swab, cannula, flashback, dressing).
- [ ] **Splint** → 3D limb close-up (lay, pad, shape, straps, check fingers/toes).
- [ ] **CPR** on an arrest patient: the 30-compression / breaths cycle keeps going forward, the medic kneels at the side.
- [ ] Any close-up: **Esc / hold to cancel** leaves cleanly; opening it again works.

## 5 · Trauma kit (field resuscitation)
- [ ] Carry only the **trauma kit**: no pelvic binder, IO kit, lidocaine or saline in your inventory.
- [ ] Start **Field resuscitation** on a heavily bleeding patient.
- [ ] Step 1: the **binder comes out of the kit**, goes under the hips and tightens itself. You do nothing.
- [ ] Steps 2-5: the **IO driver comes out of the kit**, drills by itself, draws back, flushes, then goes back into the kit.
- [ ] **N / Skip** still skips a step. The fluids step (6) still works by hand.

## 6 · Transport & beds (nobody sinks)
- [ ] Load the patient on the **stretcher**: they lie on the mattress.
- [ ] Transfer to a **hospital bed** point: they lie **on top** of the bed, not in it or under the floor.
- [ ] Same for the **X-ray table**, **operating table** and **angiography table**.
- [ ] As a player, **Lie down** on a bed point and on a check-in bed: on top of the mattress.
- [ ] If anyone floats or sinks a little: tell me which bed and by how much (it is one config value).

## 7 · Hospital & release
- [ ] Bring the NPC to the hospital. The care card's "Take them to hospital" step **disappears** once you are there; the hospital work shows as normal steps.
- [ ] X-ray → reduce → **cast** (3D close-up: stockinette, padding, wrap, mould).
- [ ] Put the NPC in a **hospital bed** → you get paid (hand-over).
- [ ] Finish the treatment → **Release patient** shows (care card + third eye) → the NPC gets up, thanks you and walks out.
- [ ] Not released → the NPC stays in the bed (removed after 15 minutes).

## 8 · Look & performance
- [ ] Every 3D close-up at **1080p** and, if you can, **1440p**: clicks land where you click.
- [ ] No big FPS drop in the close-ups. Settings → quality "auto" is fine.
- [ ] No red errors in F8 / server console after all of the above.

## When something fails, send me
1. The section and line (e.g. "4 · IV").
2. What you did, what happened, what you expected.
3. A screenshot, and F8 / server console lines if there are errors.
