# Requests from the blood module

The blood module owns `client/modules/blood*.lua`, `server/modules/blood*.lua`,
`config/modules/blood.lua`, `locales/en/blood.lua`, `html/apps/donation/**`, `html/apps/ivstand/**`.
Everything below needs a change in a file owned by someone else.

## 1. lead — `config/props.lua` (`Config.PropScreens`)

The mixer LCD is driven by a DUI (`html/apps/donation/lcd.html`). The code already falls back to
`{ txd = 'nz_amb_blood_mixer', tex = 'nz_amb_screen' }`, so this is only for consistency
(also asked by the props module):

```lua
    blood_mixer   = { txd = 'nz_amb_blood_mixer',   tex = 'nz_amb_screen' },   -- live mL counter (blood module DUI)
```

The embedded default texture of `nz_amb_blood_mixer` / `nz_amb_screen` should not show a brand
(ORIGINAL.md: no NAYZEEE on device faces). The DUI page itself shows the generic model code `CM-450`.

## 2. core-server — `locales/en/core.lua`

The transfusion reaction is a patient condition named `reaction` (`{ stage = 1..3, ml, since }`,
set with `NZA.Patients.SetCondition`). The examination reads `cond.<name>`; please add:

```lua
    ['cond.reaction']      = 'Transfusion reaction',
```

(Optional, physiology: the core already applies `p.meds.reaction` while incompatible blood runs —
fever, tachycardia, hypotension. The blood module adds haemolysis on top with `AddBlood(-mL)`.)

## 3. integration — `sql/install.sql`

The module creates its tables itself on start (`CREATE TABLE IF NOT EXISTS`). For the install file:

```sql
CREATE TABLE IF NOT EXISTS `nza_blood` (
  `serial` VARCHAR(16) NOT NULL,
  `type` VARCHAR(4) NOT NULL,
  `ml` INT NOT NULL DEFAULT 450,
  `donor` VARCHAR(80) NULL,
  `donor_id` VARCHAR(80) NULL,
  `created` INT NOT NULL DEFAULT 0,
  `expires` INT NOT NULL DEFAULT 0,
  `used` TINYINT NOT NULL DEFAULT 0,
  `bank` VARCHAR(64) NULL,
  `updated` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`serial`),
  KEY `bank_used` (`bank`, `used`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `nza_blood_donors` (
  `identifier` VARCHAR(80) NOT NULL,
  `last` INT NOT NULL DEFAULT 0,
  `count` INT NOT NULL DEFAULT 0,
  `weak_until` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `nza_blood_log` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `bank` VARCHAR(64) NULL,
  `action` VARCHAR(16) NOT NULL,
  `serial` VARCHAR(16) NULL,
  `type` VARCHAR(4) NULL,
  `actor` VARCHAR(80) NULL,
  `at` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `bank_at` (`bank`, `at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## 4. pharmacy / storage / transport (supplies)

Issuing a unit at a blood bank (and 'Bag a unit' from the ambulance fridge) decants it into an
**empty collection bag** when `Config.Blood.Bank.needEmptyBag = true` (default). Medics need a way
to get `Config.Items.empty_blood_bag`:

- pharmacy (`config/modules/pharmacy.lua`): sell `empty_blood_bag` (staff only, perm `blood`, ~$25).
- transport (`config/modules/transport.lua`, `Bay.supplies.items`): add `empty_blood_bag` to the
  `fluids` category of the ambulance shelves.

## 5. field

- `Config.Blood.Stand.placeIv.interact = 'nza_field_iv'` — the IV stand calls this patient option's
  `onSelect(entity, target)` for "Place an IV first" and reopens the stand when the line is in
  (state bag `iv = true`). Please keep that option name (it currently matches `client/modules/field.lua`).
- The field 'infuse' treatment already uses `NZA.Blood.TakeBag(src, { serial, type, recipient })`
  (supported: returns the label metadata or `nil, reasonText`). Bags hung by the field module are
  adopted by the IV stand (they get a hook and are drawn on the stand) when a medic opens it.
- Compatibility before typing: the blood module marks a typed patient with
  `patient.meta.bloodTyped = true` (Type & screen, or after a donation) — the field module already
  reads it.
