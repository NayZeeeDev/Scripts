# Requests from the xray module

Nothing here blocks the module; it works with the files as they are.

## 1. ARCHITECTURE §4 — Injury fields written by radiology (lead)

Add to the `Injury` table description:

```lua
xrayMap = nil | { film = 'A2034', view = 'chest', ap = { x, y }, lat = { x, y }, depth = 34, n = 1, at = os.time() },
          -- set by the xray module when a retained fragment was pinned on both films (film space 0..1,
          -- AP: patient's right on the viewer's left, lateral: anterior on the left)
```
and note that `treat.xray` = seen on a film, `treat.xrayMarked` = confirmed on both films (the
exam already reads both).

## 2. Bullet / surgery module (owner of `surgery`)

`injury.xrayMap` tells where the fragment is (`depth` in mm, `ap`/`lat` positions) after a
confirmed X-ray reading — the extraction minigame can start the probe there / show the film
(`metadata` of `Config.Items.xray_film` with `findings[k = 'frag']` has the same data, the film id
is `xrayMap.film`). Bus event `xray:read (src, p, film, outcome)` fires after every reading.

## 3. Transport module (owner of `transport`)

Already integrated: this module hides its own *Help patient off the table* when
`NZA.Transport.OwnsHelpOff` is set and calls `NZA.Transport.HelpOff(entity, target)`; the client
reads `NZA.Transport.Bag(ped)` (`m = 'bed'`, `bt = 'xray'`, `b = point id`) to know a patient lies on
an X-ray table, and the server reads `patient.meta.bed.type == 'xray'`. Please keep those names.

## 4. Splint module (owner of `splint`)

A cast (`treat.cast`) replaces a splint: `xray_cast` removes `devices.splints[region]`. If the
splint module re-applies splints automatically, skip limbs whose fracture has `treat.cast`.
