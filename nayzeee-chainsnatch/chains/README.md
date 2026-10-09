# chains/

Drop chain **clothing** here, one folder per chain. The folder name becomes the chain's name.

```
chains/
├─ Diamond Cuban Chain/
│  ├─ teef_000_u.ydd
│  └─ teef_diff_000_a_uni.ytd
└─ Female Cuban Choker/
   ├─ teef_001_u.ydd
   ├─ teef_diff_001_a.ytd      ← texture A
   └─ teef_diff_001_b.ytd      ← texture B
```

Then `/chainstudio` → **Convert** → **Build** (or just restart, `Config.Convert.AutoBuild` builds new ones on start).
Every texture (`_a_`, `_b_`, …) becomes its own prop, so a chain with three colours gives three items' worth of looks.

Files named `mp_m_freemode_01_pack^teef_…` work too. Don't put these files in a `stream/` folder:
this folder is only read by the converter, it is never streamed.
