# NZ Inventory UI: an ox_inventory redesign

A full visual remaster of **ox_inventory 2.48.0**. It uses ox's normal NUI protocol, so shops, crafting, stashes, trunks, gloveboxes, containers, attachments, durability, ammo, serials and custom item buttons work exactly like stock ox_inventory.

## Features

| | |
|---|---|
| **Clean dark UI** | Lime accent, diamond badges, a segmented weight bar and the `HOTBAR` / `INVENTORY` rails |
| **Item rarity** | Common, uncommon, rare, epic, legendary and mythic. Each tier has its own glow, tooltip chip and give-popup chip |
| **View switcher** | Fullscreen backdrop, or compact floating panels with a bottom dock |
| **Perspective mode** | 3D-tilted panels |
| **Settings menu** | Layout, view, font (Default / Roboto / Manrope / Montserrat / Inter), server brand, theme colour (6 presets + custom picker), backdrop opacity, fast slot style, notification style and slot shape. Saved per player with KVP |
| **Fast slots** | Normal or hexagon hotbar |
| **Notifications** | Default (slot cards) or Modern (side toasts) |
| **Slot shape** | Square or hexagon grid |
| **Search** | Matching items are highlighted and the rest are dimmed |
| **Player card** | Ped headshot, name, server ID, wallet, bank and job. Works with ESX, QBX, QB, ox_core and ND, or plug in your own function |
| **Send Item popup** | Pick a nearby player, choose an amount and send |
| **Clothing menu** | A camera shows your ped, with toggles for hat, glasses, ears, mask, chain, top, vest, bag, watch, bracelet, pants and shoes |
| **Esc behaviour** | Esc closes the open popup first and doesn't close the whole inventory |

## Performance (resmon)

`nz/client.lua` has **no ticking threads**. Everything runs off NUI callbacks or events:

* Idle cost added by the redesign: **0.00 ms**. One start-up thread waits for the UI and then exits.
* When you open the inventory, it makes one server callback for the player card (cached for 5s) and one ped headshot (cached for 60s).
* The NUI uses no `backdrop-filter`. Slots are memoised, and the tooltip and drag preview use transforms only.

Your total resmon is still stock ox_inventory's own client cost. The redesign doesn't add anything on top of it.

## Install

You need ox_inventory **2.48.0**. If you're on another version, make the same 3 edits in your own `fxmanifest.lua`.

1. Back up your `ox_inventory` folder.
2. Copy everything in this folder **into** `resources/ox_inventory`, merging folders and replacing files when asked:
   * `fxmanifest.lua`: adds the three `nz/` lines
   * `nz/`: config, client and server
   * `web/build/`: the prebuilt UI, so no Node is needed
   * `web/src`, `web/package.json` and the rest: the UI source, only needed if you want to edit it
3. **Keep** your existing `web/images/` folder. The redesign doesn't touch item images.
4. Restart the server.

### Manual fxmanifest edits (other ox versions)

```lua
shared_scripts {
    '@ox_lib/init.lua',
    'nz/config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'init.lua',
    'nz/server.lua',
}

client_scripts {
    'init.lua',
    'nz/client.lua',
}
```

## Configuration (`nz/config.lua`)

* `Brand`: server name, tagline and logo URL
* `PlayerCard`: show or hide the card, bank and job; headshot avatar; currency symbol
* `GiveMenu`: on/off, distance, and whether to show IDs or character names. Names are checked server-side so only nearby players are revealed
* `Clothing`: camera offset and FOV, plus the "naked" drawable for each piece (male, female)
* `Colors`: the theme colour presets
* `DefaultSettings`: server-wide defaults. Players can override them from the settings menu
* `Rarity`: an item → rarity table
* `Strings`: override any UI text
* `GetPlayerInfo(source)`: optional custom function if you use a framework that isn't listed

### Setting rarity

There are three ways, from highest to lowest priority:

1. Per item instance: set `metadata.rarity = 'legendary'`
2. Per item definition in `data/items.lua`: `['burger'] = { label = 'Burger', rarity = 'epic', ... }`
3. In `NZConfig.Rarity` in `nz/config.lua`

## Editing the UI

```bash
cd web
npm install        # .npmrc sets legacy-peer-deps (same deps as upstream ox)
npm start          # browser preview with sample data
npm run build      # outputs to web/build
```

For the browser preview to show item icons, put ox's `images` folder (or a symlink to it) inside `web/`.

## Notes

* Clothing toggles are temporary, like dpclothing. Your framework's saved skin loads back on relog.
* Clothing packs can change the "naked" drawable IDs. If a piece doesn't come off cleanly, adjust `NZConfig.Clothing.pieces`.
* The UI is derived from ox_inventory's GPL-3.0 web source, so `web/` stays under GPL-3.0 (see `web/LICENSE`).
