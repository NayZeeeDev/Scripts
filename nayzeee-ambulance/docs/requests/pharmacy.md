# Requests from the pharmacy module

## 1. Lead: `sql/install.sql`

The module creates its four tables on start (`CREATE TABLE IF NOT EXISTS`). Please add them to
the install file too:

```sql
CREATE TABLE IF NOT EXISTS `nza_insurance` (
  `identifier` VARCHAR(80) NOT NULL,
  `plan` VARCHAR(32) NOT NULL,
  `expires` INT UNSIGNED NOT NULL DEFAULT 0,
  `started` INT UNSIGNED NOT NULL DEFAULT 0,
  `serial` VARCHAR(24) NULL DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`identifier`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_bills` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(80) NOT NULL,
  `name` VARCHAR(80) NULL DEFAULT NULL,
  `amount` INT UNSIGNED NOT NULL DEFAULT 0,
  `covered` INT UNSIGNED NOT NULL DEFAULT 0,
  `reason` VARCHAR(120) NULL DEFAULT NULL,
  `kind` VARCHAR(32) NULL DEFAULT NULL,
  `medic` VARCHAR(80) NULL DEFAULT NULL,
  `medic_name` VARCHAR(80) NULL DEFAULT NULL,
  `society` VARCHAR(64) NULL DEFAULT NULL,
  `status` VARCHAR(12) NOT NULL DEFAULT 'unpaid',
  `created` INT UNSIGNED NOT NULL DEFAULT 0,
  `paid_at` INT UNSIGNED NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `identifier_status` (`identifier`, `status`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_pharmacy_stock` (
  `pool` VARCHAR(48) NOT NULL,
  `item` VARCHAR(64) NOT NULL,
  `stock` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`pool`, `item`)
) DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `nza_pharmacy_sales` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `pool` VARCHAR(48) NOT NULL,
  `point` INT NOT NULL DEFAULT 0,
  `identifier` VARCHAR(80) NULL DEFAULT NULL,
  `name` VARCHAR(80) NULL DEFAULT NULL,
  `items` LONGTEXT NULL,
  `subtotal` INT UNSIGNED NOT NULL DEFAULT 0,
  `discount` INT UNSIGNED NOT NULL DEFAULT 0,
  `tax` INT UNSIGNED NOT NULL DEFAULT 0,
  `total` INT UNSIGNED NOT NULL DEFAULT 0,
  `method` VARCHAR(8) NULL DEFAULT NULL,
  `kind` VARCHAR(16) NOT NULL DEFAULT 'shop',
  `created` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `pool_created` (`pool`, `created`)
) DEFAULT CHARSET=utf8mb4;
```

## 2. Check-in module (optional): a target option on the desk

Players already get "[H] Pay medical bills · 3 open · $2,055" at every check-in desk while they
have open bills (our own prompt, `Config.Pharmacy.desk`). Servers that rely on a target script
would also like a target option on the desk. In `client/modules/checkin.lua → targets()`:

```lua
{ name = 'bills', label = NZA.L('pharmacy.t_bills'), icon = 'receipt',
  canInteract = function() return NZA.Pharmacy and NZA.Pharmacy.Open ~= nil end,
  onSelect = function(p) NZA.Pharmacy.Open(p.id, 'bills') end },
```

The server already accepts `checkin` positions for the window (desk mode: Bills + Insurance,
no shop) and checks the distance to that desk.

## 3. Bridge (server, optional): `Bridge.HasLicense(src, name) → bool`

Products can need a framework licence (`license = 'weapon'` in `Config.Pharmacy.products`).
`server/modules/pharmacy.lua` checks it itself today: QBCore/Qbox `PlayerData.metadata.licences`,
ESX `esx_license:checkLicense`, standalone ace `nza.license.<name>`. If the bridge gets a
`HasLicense`, the pharmacy will be switched to it (one place for every framework).

## 4. Lead: `config/config.lua → Config.Billing`

Nothing to change. For the comment block: the extra billing options (insurance share, unpaid
bills, external invoice scripts, auto collect) live in `Config.Pharmacy.billing`;
`Config.Billing.enabled / society / account / medicCut` are read by `NZA.Billing.Charge`.
