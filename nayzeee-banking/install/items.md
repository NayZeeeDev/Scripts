# 💳 Card items

Only needed when `Config.Cards.physicalItem = true`. One item per card type in `Config.CardTypes` — add or remove entries here to match if you change that list.

Every entry must be **non-stackable**, because the `cardId` in its metadata is what ties the item to a specific card in the database. Two cards sharing a stack would share an identity.

Images are in `install/images/`. Copy **all** of them wherever your inventory serves item images, then restart the inventory resource:

- `card_debit.png`, `card_secured.png`, `card_credit.png`, `card_platinum.png`: the item's own picture
- `card_<item>_<style>.png` (16 files): on ox_inventory each card is shown in the style the player picked in the app (teal, noir, chrome, crimson) and updates when they restyle it. Turn this off with `Config.Cards.skinImages = false`.

Added a style to `Config.Cards.skins`? Add its colours to `tools/cardicons.py` and run `python3 tools/cardicons.py` (needs `pip install numpy pillow`) to render its images.

---

## ox_inventory

`ox_inventory/data/items.lua`

```lua
['card_debit'] = {
    label = 'Debit Card',
    weight = 15,
    stack = false,
    close = true,
    description = 'Spends straight from the account it is attached to.',
    client = { export = 'nayzeee-banking.useCard' }
},

['card_secured'] = {
    label = 'Secured Card',
    weight = 15,
    stack = false,
    close = true,
    description = 'Backed by a deposit the bank is holding.',
    client = { export = 'nayzeee-banking.useCard' }
},

['card_credit'] = {
    label = 'Credit Card',
    weight = 15,
    stack = false,
    close = true,
    description = 'An unsecured line of credit, billed on a cycle.',
    client = { export = 'nayzeee-banking.useCard' }
},

['card_platinum'] = {
    label = 'Platinum Credit Card',
    weight = 15,
    stack = false,
    close = true,
    description = 'High limit, low rate, hard to qualify for.',
    client = { export = 'nayzeee-banking.useCard' }
},
```

Images go in `ox_inventory/web/images/`.

---

## qb-inventory

`qb-core/shared/items.lua`

```lua
['card_debit'] = { name = 'card_debit', label = 'Debit Card', weight = 15, type = 'item', image = 'card_debit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Spends straight from the account it is attached to.' },
['card_secured'] = { name = 'card_secured', label = 'Secured Card', weight = 15, type = 'item', image = 'card_secured.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'Backed by a deposit the bank is holding.' },
['card_credit'] = { name = 'card_credit', label = 'Credit Card', weight = 15, type = 'item', image = 'card_credit.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'An unsecured line of credit, billed on a cycle.' },
['card_platinum'] = { name = 'card_platinum', label = 'Platinum Credit Card', weight = 15, type = 'item', image = 'card_platinum.png', unique = true, useable = true, shouldClose = true, combinable = nil, description = 'High limit, low rate, hard to qualify for.' },
```

Images go in `qb-inventory/html/images/`.

---

## qs-inventory

Same table as qb-inventory above. Images go wherever your Quasar build serves them, usually `qs-inventory/html/images/`.

---

## ESX default inventory

```sql
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('card_debit',    'Debit Card',           1, 0, 1),
    ('card_secured',  'Secured Card',         1, 0, 1),
    ('card_credit',   'Credit Card',          1, 0, 1),
    ('card_platinum', 'Platinum Credit Card', 1, 0, 1);
```

{% hint style="warning" %}
The default ESX inventory does not keep per-item metadata, so every card of a type looks identical to it and the `cardId` is lost. Physical cards work properly only on an inventory that preserves metadata — ox_inventory, qs-inventory or qb-inventory. On the default inventory, leave `Config.Cards.physicalItem = false`.
{% endhint %}

---

## Matching the config

The item name on each card type in `config.lua` is what gets handed out:

```lua
Config.CardTypes = {
    { id = 'debit',     item = 'card_debit',    … },
    { id = 'secured',   item = 'card_secured',  … },
    { id = 'unsecured', item = 'card_credit',   … },
    { id = 'platinum',  item = 'card_platinum', … },
}
```

Set `item = nil` on a type that should not hand out an item at all.
