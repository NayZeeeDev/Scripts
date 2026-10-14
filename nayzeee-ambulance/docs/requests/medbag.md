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

## 5. ARCHITECTURE §10.2 — documentation only (lead)

§10.2 lists the medic bag among the v5 WINDOWS. To keep the bag on the floor visible and to stay
clear of the reference product's layout (docs/design/ORIGINAL.md), the `medbag` app is built from HUD
cards instead: a pockets dock on the left edge (+ quantity dial), the bag dock on the right edge
drawn as the OPEN bag seen from above (lid mesh pocket, zipper hinge, main compartment with elastic
loops, side pouches, par levels with shadow outlines) (+ bag log) and a free centre. Please list it
under the HUD overlays. The same app also renders the body bag zip-up card (bottom-left, above the
minimap) and the toe tag (right-middle edge), both without NUI focus.

## 6. config/props.lua — optional keys for the bag colours (lead)

The four streamed colour variants are referenced in `Config.Medbag.Bag.colours`
(`nz_amb_medbag_red | _orange | _green | _magenta`). If you prefer every model name in
`config/props.lua`, add `medbag_orange`, `medbag_green`, `medbag_magenta` (and `medbag` = red) and
the module config can point at `Config.Props.medbag_*` instead.
