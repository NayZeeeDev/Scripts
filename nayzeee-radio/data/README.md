# nayzeee-radio/data

Only used when oxmysql is not running. The radio then keeps its data here as JSON:

| File | What is in it |
|---|---|
| `players.json` | Memories and callsign per character |
| `channels.json` | Channel locks saved in `/radioadmin` |
| `vehicles.json` | Radio cars added in `/radioadmin` |

- The server must be able to write to this folder.
- **Keep this folder when you update the resource.** Replacing it loses every memory,
  callsign, channel lock and radio car stored here.
- With oxmysql running, the same data goes into the tables `nzr_players`, `nzr_channels` and
  `nzr_vehicles` instead, and nothing is written here.
