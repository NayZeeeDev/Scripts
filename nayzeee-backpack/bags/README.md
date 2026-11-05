# bags/

Drop bag **clothing** here, one folder per bag. The folder name becomes the bag's name.

```
bags/
├─ Mew Backpack/
│  ├─ mp_f_freemode_01^hand_005_u.ydd          ← female model
│  ├─ mp_f_freemode_01^hand_diff_005_a_uni.ytd
│  ├─ mp_m_freemode_01^hand_005_u.ydd          ← male model
│  └─ mp_m_freemode_01^hand_diff_005_a_uni.ytd
└─ Gym Bag/
   ├─ task_001_u.ydd
   ├─ task_diff_001_a_uni.ytd     ← colour A
   └─ task_diff_001_b_uni.ytd     ← colour B …
```

Bags are clothing component `hand` (bags & parachutes) or `task` (vests, where some backpacks live).
Every texture (`_a_`, `_b_`, …) becomes its own colour. Male + female files in one folder become
*Name (Male)* and *Name (Female)*. Subfolders are fine (`Pack/stream/…`): the name comes from the first
folder that isn't `stream`, `male`, `female` …

Then restart the server (new bags convert on start) or run `/bagconvert` in game. Don't put these files in a
`stream/` folder of a started resource: this folder is only read by the converter, never streamed.
