# Requests from the medbag module (medical bag, body bag, morgue)

Nothing here blocks the module; it works with the files as they are.

## 1. sql/install.sql — table `nza_bags` (lead, integration)

The module creates it on start (`CREATE TABLE IF NOT EXISTS`); add the same statement to the
install file:

```sql
CREATE TABLE IF NOT EXISTS `nza_bags` (
    `id` VARCHAR(32) NOT NULL,
    `owner` VARCHAR(64) NULL DEFAULT NULL,
    `items` LONGTEXT NULL,
    PRIMARY KEY (`id`),
    KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```
`items` is JSON: `{ v = 1, slots = { { s, n, c, m } }, locked, ownerName, world = { x, y, z, h, b } | nil }`.

## 2. ARCHITECTURE §8 / §17 — documentation only (lead)

- Point type `morgue` is registered by the **medbag** module (§8 lists the owner as "bodybag").
- New state bags (server-set, replicated):
  - medical bag prop `nzaMedbag = { id, owner, locked }`
  - body bag prop `nzaBag = { kind, sid | net }` (core contract) + `nzaBody = { id, name, kind, mode }`
  - player `nzaInBag = { id, net, mode, off }` (the bagged player's own client hides + attaches the ped)
  - stretcher `nzaBodyOn = bodyId`, vehicle `nzaBodies = { n, ids }`
- Server bus: `medbag:placed (src, id)`, `medbag:picked (src, id)`, `medbag:moved (src, id, moved)`,
  `bodybag:bagged (src, body)`, `bodybag:morgue (src, body, point)`.

## 3. Transport module (owner of the stretcher records) — optional

A body bag laid on a stretcher is attached to the cot entity; the cot record (`T.stretchers[net]`)
stays empty (`pid = nil`), so loading / unloading / pushing the cot works unchanged and the bag rides
along. The medbag watchdog keeps `rec.touched` fresh so the cot is not removed as abandoned.
Two small additions would make it airtight:
- treat a cot whose entity state bag has `nzaBodyOn` as occupied in `str:place` (no patient on top of
  a body bag) and in `str:store` (do not put the cot away with a body bag on it);
- optionally show the bag on the bay cot when such a stretcher is loaded (the bay cot is a local prop).
Today, if a cot with a body bag is stored or deleted, the medbag watchdog puts the bag on the ground
where the cot was.

## 4. ox_inventory install (bridge module, already true)

`medbag` must be usable without being consumed (`consume = 0`); `install/generate.lua` already writes
that for every usable item. The item keeps its `bagId` in metadata (`description` shows the bag id,
item count and weight).
