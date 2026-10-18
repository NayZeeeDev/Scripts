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

2. **`html/core/nza.js` · `NZA.ui.Grade` / `NZA.toast({ grade })` draw a letter badge.**
   ORIGINAL.md lists "a big letter grade" as a competitor signature. cpr no longer shows letters
   (score ring + a one-word verdict, toast with an icon). A shared verdict helper (score → word +
   tone) would keep every debrief consistent.

3. **Still open from `docs/requests/cpr.md`**: optional CPR artefact on the ECG trace
   (`NZA.vitals.Trace(canvas, { artifact: 0..1 })`).
