# Requests from core-server

## 1. config/config.lua — two optional Physiology switches

core-server already reads these with a default of `true`; please add them to `Config.Physiology` so
server owners can see them:

```lua
    infection     = true,     -- dirty, uncovered wounds can get infected (fever, sepsis) - antibiotics cure it
    hypothermia   = true,     -- body temperature simulation (blood loss, water, cold fluids; foil blanket / bed warm up)
```

## 2. config/config.lua — clarify the bleed-out clock comment (no value change)

`Config.Wounded.maxClock` comment could read:
`-- the bleed-out clock never shows more than this (seconds). It runs in real time for heavy bleeding,
slower for a minor ooze, and pauses when the patient is stabilized`

## 3. sql/install.sql — core tables

Both are created automatically on start; for the install file:

```sql
CREATE TABLE IF NOT EXISTS `nza_patients` (
  `identifier` VARCHAR(64) NOT NULL,
  `data` LONGTEXT NOT NULL,
  `state` VARCHAR(16) NOT NULL DEFAULT 'alive',
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_records` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `medic` VARCHAR(64) NOT NULL DEFAULT 'system',
  `medic_name` VARCHAR(64) NULL,
  `action` VARCHAR(64) NOT NULL,
  `summary` LONGTEXT NULL,
  `created` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

`nza_records` has one extra column over ARCHITECTURE §12 (`medic_name`) so the history shows names
without a framework lookup.

## 4. ARCHITECTURE §17 — one extra S→C event

`nza:proc:aborted (token, reason, msg)` — the server ends a procedure session (patient died / left,
medic moved > maxDist + 4 m away, timeout). core-client's `NZA.Proc.Run` should close the minigame
when it receives it. Also `nza:patient:update (pid, nil)` means "watch ended".
