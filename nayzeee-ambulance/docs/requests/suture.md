# Requests from the suture module

## 1. Unscoped CSS in another app (integration, not a lead file)

`html/apps/monitor/app.css` styles bare class names (`.pm`, `.pm-handle`, `.mon …`) without the
`#app-monitor` prefix. Because every app's CSS is loaded on the same page, these rules leak into
other apps: the suture pain meter (a `div.pm`) was stretched to 468 px with a dark pill frame.
Suture renamed its class to `.sz-pm`, so nothing is needed for suture any more, but the monitor
owner should scope those selectors under `#app-monitor` (or `.nza-monitor`) so other apps are safe.

## 2. Nothing else

Suture needs no change to lead-owned files. `html/core/nza3d.js` (owned by suture) is already in
`html/index.html` after `vendor/three.min.js`.
