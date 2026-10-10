-- Server-only settings. This file never reaches players, keep webhooks here.

ServerConfig = {}

ServerConfig.Logs = {
    Enabled  = false,
    Name     = 'Wig Snatch',
    Avatar   = '',
    Webhooks = {
        snatch   = '',   -- every successful snatch (and steal-backs)
        clash    = '',   -- defended snatches
        sell     = '',   -- quick sells, meet-ups and orders
        listing  = '',   -- marketplace listings bought / cancelled
        trade    = '',   -- player to player trades and wigs put on others
        bounty   = '',   -- placed / claimed / expired
        haircut  = '',   -- first person cuts and shaves
        restrain = '',   -- tackles, ties and holds
        product  = '',   -- products used on other players
        workshop = '',   -- wigs crafted and dyed
        admin    = '',   -- admin commands
    },
}

-- Who can use /wigadmin. Uses ox_lib command permissions (ace).
-- Give it with: add_ace group.admin command.wigadmin allow
ServerConfig.AdminAce = 'group.admin'

-- Who can use the Wig Studio (/wigstudio). Checked on every upload too.
-- Give it with: add_ace group.admin command.wigstudio allow
ServerConfig.StudioAce = 'command.wigstudio'
