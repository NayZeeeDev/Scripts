# Requests from the hospital module

## 1. Core (server/core/staff.lua + client/core/staff.lua): explicit "easy off" per department

`finalize()` turns `record.easy` into a set of `true` keys, so a department that has easy
mode switched OFF cannot override `Config.EasyMode.default = true`: `NZA.Staff.Easy` and the
client `NZA.Easy` fall back to the config default for every permission that is not in the set.

Request: honour an optional `record.easyDefault` (boolean) from the provider:
- server `S.Easy(src, perm)`: `if rec.easy[perm] then return true end; if rec.easyDefault ~= nil then return rec.easyDefault end; return Config.EasyMode.default`
- client `NZA.Easy(perm)`: the same with `record.easyDefault`.

The hospital provider would then set `easyDefault = false` for every department member (the
department's easy switch + per-permission overrides already fill `easy`). Until then easy mode
per department works exactly as designed as long as `Config.EasyMode.default = false` (the default).

## 2. Bridge (server): `Bridge.SetJob(src, job, grade) → bool`

Hiring into / firing from a department that is linked to a framework job should also set the
framework job (ESX `xPlayer.setJob`, QBCore `Player.Functions.SetJob`, Qbox `exports.qbx_core:SetJob`).
The hospital already calls it through `NZA.Core.B('SetJob', src, job, grade)` when it exists
(`Config.Hospital.staff.syncFrameworkJob`, `Config.Hospital.staff.fireJob`). Without it, firing a
linked member keeps an "excluded" staff row so the job link does not re-add them.

## 3. Bridge (server): `Bridge.Inv.OpenStash(src, id, { label, slots, weight, owner }) → bool`

Department stashes currently open ox_inventory (`RegisterStash` + client `openInventory`),
qb-inventory 2.x (`exports['qb-inventory']:OpenInventory`) and the classic
`inventory:server:OpenInventory` event (qb old, ps, lj, qs) from `server/modules/hospital_runtime.lua`,
and fall back to the built-in NAYZEEE storage window for every other inventory. If the bridge
gets a generic stash opener, the hospital uses it first (`NZA.Core.Has('Inv.OpenStash')`).

## 4. Lead: `sql/install.sql`

Add the four hospital tables (the module also creates them on start):

```sql
CREATE TABLE IF NOT EXISTS `nza_departments` (
  `id` VARCHAR(48) NOT NULL, `label` VARCHAR(64) NOT NULL, `job` VARCHAR(64) NULL DEFAULT NULL,
  `data` LONGTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_points` (
  `id` INT NOT NULL AUTO_INCREMENT, `department` VARCHAR(48) NOT NULL, `type` VARCHAR(32) NOT NULL,
  `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL DEFAULT 0,
  `label` VARCHAR(64) NULL DEFAULT NULL, `data` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `department` (`department`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_staff` (
  `identifier` VARCHAR(80) NOT NULL, `department` VARCHAR(48) NOT NULL, `grade` INT NOT NULL DEFAULT 0,
  `name` VARCHAR(80) NULL DEFAULT NULL, `excluded` TINYINT(1) NOT NULL DEFAULT 0,
  `hired_by` VARCHAR(80) NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`), KEY `department` (`department`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_hospital_stash` (
  `id` VARCHAR(120) NOT NULL, `items` LONGTEXT NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) DEFAULT CHARSET=utf8mb4;
```

`nza_hospitals` from ARCHITECTURE §12 is not needed: a department IS the hospital
(`point.hospital` = department id, `NZA.Hospitals.Get(id)` returns the department).

## 5. Lead: ARCHITECTURE §8 point type names

The hospital registers `locker` (outfits) instead of the `wardrobe` named in §8, plus
`elevator`, `bed`, `respawn` and `hq`. Please update the list:
`duty locker stash boss storage garage heli elevator bed respawn hq` (hospital).

## 6. Dispatch: radial "Go on duty"

`nza:dispatch:duty` only toggles framework medics through `Bridge.SetDuty`. Members of a
standalone department (hired in the EMS Manager, no framework medic job) get
"not a medic". Please call the hospital instead — client `NZA.Hospitals.ToggleDuty(on)` or the
callback `nza:hospital:duty` `({ on })` → `{ ok, onDuty }` — which handles both kinds of member
and respects `Config.Hospital.duty.requirePoint`. The hospital's own radial duty item stays off
(`Config.Hospital.duty.radial = false`) so the menu never shows two.

## 7. Transport: beds and treatment rooms

When a medic puts a patient on a hospital point, call `NZA.Hospitals.OccupyBed(pointId, pid)`
(server) and `NZA.Hospitals.ReleaseBed(pointId)` when they are taken off. It keeps the
occupancy table right for `FreeBed` / respawn, sets `patient.meta.bed = { point, type, hospital }`
and, for `bed` points, `patient.meta.inBed = true` (healing ×4 in physiology).
