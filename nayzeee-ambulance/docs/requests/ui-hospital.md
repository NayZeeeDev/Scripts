# UI requests — group hospital (apps `manager`, `builder`)

Originality pass (docs/design/ORIGINAL.md) on the Department Console (`manager`) and the site
survey HUD (`builder`). Everything was done inside the apps; one small core change would help
every app that shows rolling numbers.

## 1. `NZA.ui.FlipClock` — only blink the colon (core, nza.js / nza.css)
`.odo .c` blinks every non-digit character (`nza-blink`). That is right for the `:` of a timer,
but the same widget now renders decimals and thousands (`087.5°` bearing in the survey HUD,
`148,250` balance in the console account view), where a blinking `.` or `,` looks like a fault.
Suggestion: give `:` its own class (e.g. `.odo .c.colon`) and only animate that one, or accept
`{ blink: false }` in the options.
Workaround in place: `#app-builder .bx-cv .odo .c` and `.mx-bal .odo .c` set `animation:none`
inside the apps. Remove those two rules once the core handles it.
