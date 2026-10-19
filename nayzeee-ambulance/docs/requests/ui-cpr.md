# UI pass requests from the `cpr` group (lead-owned files)

Nothing blocks the app; each item below has a workaround in `html/apps/cpr/app.js`.

1. **`html/core/nza.js` · `ProcPanel.set()` replays the text animation on every update.**
   `if (('title' in n && n.title !== prev.title) || ('text' in n && n.text !== prev.text) || 'titleTone' in n) renderText();`
   The `'titleTone' in n` term is true whenever a caller passes `titleTone`, even when it did not
   change, so `renderText()` restarts the 260 ms `pp-swap` animation (opacity from 0). Apps that call
   `pp.set({...})` once a second with stats + title (the cpr step card, probably others) catch the
   step card half transparent or blank in screenshots and in game.
   Proposal: `|| ('titleTone' in n && n.titleTone !== prev.titleTone)`.
   Workaround in cpr: it only passes `title` / `titleTone` / `text` when one of them changed.
   Status: done. `ProcPanel.set()` in `html/core/nza.js` only re-renders when `titleTone` actually changes.

2. **`html/core/nza.js` · `NZA.ui.Grade` / `NZA.toast({ grade })` draw a letter badge.**
   ORIGINAL.md lists "a big letter grade" as a competitor signature. cpr no longer shows letters
   (score ring + a one-word verdict, toast with an icon). A shared verdict helper (score → word +
   tone) would keep every debrief consistent.
   Status: done. `NZA.toast({ score })` draws a score ring with the percentage, `grade` is never drawn,
   and `NZA.ui.Grade` is an alias of the new `NZA.ui.ScoreRing`. The core result toast shows the score
   with a verdict word (`client/core/proc.lua`, `core_client.proc.verdict_*`).

3. **From `docs/requests/cpr.md`**: optional CPR artefact on the ECG trace
   (`NZA.vitals.Trace(canvas, { artifact: 0..1 })`).
   Status: done. `html/core/nza-vitals.js` takes `artifact` (0..1) and `cprRate` and draws the
   compression deflections on the ECG trace.
