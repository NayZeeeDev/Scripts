/* ═══════════════════════════════════════════════════════════
   NAYZEEE DOCS · content
   Edit this file only. Every page is Markdown inside a template string.
   Extras that work inside pages:
     {fw:ESX, QBCore, Qbox}   framework logo chips
     {v:2.4.1}                version tag
     {kbd:F7}                 key cap
     > [!NOTE] Title          callout (NOTE / TIP / WARNING / DANGER)
     :::cards ... :::         card grid of links  (- [Title](#/section/page) description)
     :::kv ... :::            key/value list      (key: value)
     ```lua ... ```           code block with copy button (lua, js, json, bash, cfg, sql highlighted)
   ═══════════════════════════════════════════════════════════ */
window.DOCS = {
  site: {
    name: 'NAYZEEE DEV',
    tagline: 'Documentation',
    logo: '',                                  // optional logo URL, replaces the mark
    store: 'https://www.nayzeeedev.com',
    discord: 'https://discord.gg/nayzeee',
    footer: '© 2026 NAYZEEE DEV · Not affiliated with Cfx.re',
    logos: { esx: 'logos/esx.png', qb: 'logos/qb.png', qbx: 'logos/qbx.png' }
  },
  sections: [
    {
      title: 'Getting started', slug: 'start', icon: 'home',
      pages: [
        { title: 'Welcome', slug: 'welcome', icon: 'home', summary: 'Everything you need to install, configure and extend NayZeeeDev scripts.', body: `
## What you get

Every script in the store ships with a config file, framework bridges for {fw:ESX, QBCore, Qbox} and lifetime updates through your Keymaster. These docs cover installation, every config option, the exports and events you can hook into, and the questions we get asked most.

:::cards
- [Installation](#/start/installation) Download from Keymaster, dependencies, resource order.
- [NayZeee HUD](#/scripts/hud) Player status, vehicle HUD, compass and the settings menu.
- [Inventory](#/scripts/inventory) Grid inventory with crafting, stashes and shops.
- [Emergency Services MDT](#/scripts/mdt) Dispatch, records and reports for EMS and PD.
- [FAQ](#/help/faq) Escrow vs open source, licences, refunds.
- [Changelog](#/help/changelog) What changed in every release.
:::

## Need help?

> [!TIP] Fastest route to support
> Open a ticket in [Discord](https://discord.gg/nayzeee) with your framework, the script version and the server console output. Most tickets are answered within the hour.
` },
        { title: 'Installation', slug: 'installation', icon: 'bolt', summary: 'How to get a script from your Keymaster into your server in five minutes.', body: `
## Requirements

| Requirement | Version | Notes |
| --- | --- | --- |
| FXServer | 7290 or newer | Older builds miss natives we rely on |
| ox_lib | 3.x | Required by every script |
| Framework | ESX 1.10+, QBCore, Qbox | Auto-detected on start |
| MySQL | oxmysql | Used by scripts that persist data |

## Steps

1. Open [Keymaster](https://keymaster.fivem.net), find the asset under **Granted assets** and download it.
2. Drop the folder into your \`resources\` directory. Do not rename escrowed resources.
3. Add it to your \`server.cfg\` **after** ox_lib and your framework:

\`\`\`cfg
ensure ox_lib
ensure qb-core            # or es_extended / qbx_core
ensure oxmysql
ensure nz_hud
\`\`\`

4. Start the server once. The script prints its version and the detected framework:

\`\`\`bash
[nz_hud] v2.4.1 · framework: qbox · ui: ready
\`\`\`

5. Open \`config.lua\` and adjust what you need. Every option is documented inline.

> [!WARNING] Escrowed resources
> Files marked \`-- escrow\` cannot be edited. Everything in \`config/\` and \`bridge/\` is open and safe to change. If you need deeper changes, the open-source licence is available for every script.

## Updating

Updates land in your Keymaster automatically. Download the new build, replace the folder, keep your \`config/\` folder if the changelog says the config is unchanged, and restart the resource.
` }
      ]
    },
    {
      title: 'Scripts', slug: 'scripts', icon: 'layers',
      pages: [
        { title: 'NayZeee HUD', slug: 'hud', icon: 'layers', version: '2.4.1', frameworks: ['ESX', 'QBCore', 'Qbox'], store: 'https://www.nayzeeedev.com/package/101', summary: 'Player status, vehicle HUD, compass and a full in-game settings menu, all in one resource.', body: `
## Features

- Health, armour, hunger, thirst, stamina, stress and voice as rings, squircles, pills or minimal text.
- Vehicle HUD with speed, fuel, seatbelt, cruise control and nitro.
- Compass with street and zone names.
- Settings menu ({kbd:F7} by default) with a drag-and-drop layout editor and colour picker.
- Zero-config on {fw:ESX, QBCore, Qbox}. Bridges are open source.

## Config

\`\`\`lua
Config = {}
Config.Framework = 'auto'        -- 'auto', 'esx', 'qb', 'qbx'
Config.OpenKey   = 'F7'          -- settings menu key
Config.Style     = 'ring'        -- 'ring', 'squircle', 'pill', 'minimal'
Config.Colour    = '#08afa2'     -- default accent, players can change it
Config.HideWhenFull = false      -- hide bars at 100%
Config.Vehicle = {
  speedUnit = 'mph',             -- 'mph' or 'kmh'
  seatbelt  = true,
  cruise    = true,
}
Config.Compass = { enabled = true, streetNames = true, position = 'top' }
\`\`\`

:::kv
Config.Framework: Leave on \`auto\`. Set it only if you run a renamed core resource.
Config.Style: Players can override this per account in the settings menu.
Config.HideWhenFull: Good for immersion servers. Bars fade back in when a value drops.
:::

## Exports

\`\`\`lua
-- client
exports.nz_hud:SetVisible(false)                  -- hide the whole HUD (cinematic mode)
exports.nz_hud:SetStatus('stress', 42)            -- push a custom value
exports.nz_hud:AddStatus('thirst', { icon = 'droplet', colour = '#3fb6ff' })
local layout = exports.nz_hud:GetLayout()         -- current player layout table
\`\`\`

## Events

\`\`\`lua
-- fired when the player saves the settings menu
AddEventHandler('nz_hud:settingsSaved', function(settings)
  print(settings.style, settings.colour)
end)

-- hide the HUD from another resource
TriggerEvent('nz_hud:toggle', false)
\`\`\`

## Troubleshooting

> [!NOTE] HUD not showing after restart
> Make sure \`nz_hud\` starts after your framework and ox_lib. Check the console for \`ui: ready\`. If it says \`framework: unknown\`, set \`Config.Framework\` manually.

> [!DANGER] Duplicate HUDs
> Disable the default framework HUD (\`qb-hud\`, \`esx_status\` UI) or you will see both.
` },
        { title: 'Inventory', slug: 'inventory', icon: 'box', version: '1.9.0', frameworks: ['ESX', 'QBCore', 'Qbox'], store: 'https://www.nayzeeedev.com/package/401', summary: 'Grid inventory with weight, hotbar, crafting, stashes, shops and vehicle trunks.', body: `
## Features

- Drag-and-drop grid with weight and slot limits.
- Hotbar, item metadata, durability and decay.
- Stashes, trunks, gloveboxes, drops and shops.
- Crafting benches with recipes and blueprints.
- Compatible with ox_inventory item definitions.

## Config

\`\`\`lua
Config.MaxWeight = 120000
Config.Slots     = 40
Config.Hotbar    = 5
Config.Trunks = {
  compact = 60000, sedan = 80000, suv = 100000, truck = 160000,
}
\`\`\`

## Exports

\`\`\`lua
-- server
exports.nz_inventory:AddItem(source, 'water', 2, { quality = 100 })
exports.nz_inventory:RemoveItem(source, 'water', 1)
local count = exports.nz_inventory:GetItemCount(source, 'water')
exports.nz_inventory:OpenStash(source, 'police_evidence', { slots = 100, weight = 500000 })
\`\`\`
` },
        { title: 'Emergency Services MDT', slug: 'mdt', icon: 'shield', version: '3.1.2', frameworks: ['ESX', 'QBCore', 'Qbox'], store: 'https://www.nayzeeedev.com/package/201', summary: 'Dashboard, dispatch, triage, patient records and incident reports for EMS and PD.', body: `
## Features

- Dispatch board with live units, call priorities and ETA.
- Patient and citizen records with search.
- Incident reports, call reports and a duty roster.
- Works for EMS and PD with separate permissions.

## Jobs and permissions

\`\`\`lua
Config.Jobs = {
  ambulance = { label = 'EMS',    grades = { chief = 4, paramedic = 1 } },
  police    = { label = 'Police', grades = { chief = 4, officer = 1 } },
}
\`\`\`

## Events

\`\`\`lua
-- create a dispatch call from any resource
TriggerServerEvent('nz_mdt:dispatch', {
  code = '10-71', title = 'Shots fired', coords = GetEntityCoords(PlayerPedId()), priority = 1,
})
\`\`\`

> [!TIP] Pairs with Police Dispatch
> Install **Police Dispatch** and calls created there appear on the MDT dispatch board automatically.
` }
      ]
    },
    {
      title: 'Help', slug: 'help', icon: 'info',
      pages: [
        { title: 'FAQ', slug: 'faq', icon: 'info', summary: 'Licences, escrow, refunds and the other questions we get every week.', body: `
## Escrow or open source?

**Escrowed** is cheaper and protected by Cfx.re asset escrow. Config and bridge files stay editable. **Open source** gives you the full code to change anything. Both receive the same updates.

## How many servers can I use a script on?

One server per purchase. All Access plans include multiple server keys. For networks, open a ticket.

## Do I get updates?

Yes, for life on one-time purchases. Updates show up in your Keymaster and the changelog is posted in Discord.

## Refunds

Digital goods are delivered instantly, so refunds are only offered when an asset cannot be delivered. Open a ticket within 7 days.

## Can I transfer a script to another account?

Yes, through Keymaster's transfer feature. We cannot transfer on your behalf.
` },
        { title: 'Changelog', slug: 'changelog', icon: 'list', summary: 'Every release, newest first.', body: `
## NayZeee HUD {v:2.4.1}
*8 Oct 2026*
- New compass and street-name styles.
- Qbox support out of the box.
- Settings menu rebuilt in NAYZEEE UI v3.
- Fixed vehicle HUD flicker on seat swap.

## Inventory {v:1.9.0}
*2 Oct 2026*
- Crafting benches and blueprints.
- Item durability and decay.
- Trunk weight by vehicle class.

## Emergency Services MDT {v:3.1.2}
*28 Sep 2026*
- Dispatch board shows unit ETA.
- Fixed patient record search on ESX.
` }
      ]
    }
  ]
};
