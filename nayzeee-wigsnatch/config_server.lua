-- Server-only settings. This file never reaches players, keep webhooks here.

ServerConfig = {}

ServerConfig.Logs = {
    Enabled  = false,
    Name     = 'Wig Snatch',
    Avatar   = '',
    Webhooks = {
        snatch  = '',   -- every successful snatch
        clash   = '',   -- defended snatches
        sell    = '',   -- buyer sales
        trade   = '',   -- player to player trades
        bounty  = '',   -- placed / claimed / expired
        haircut = '',   -- styles and forced buzz cuts
        admin   = '',   -- admin commands
    },
}

-- Who can use /wigadmin. Uses ox_lib command permissions (ace).
-- Give it with: add_ace group.admin command.wigadmin allow
ServerConfig.AdminAce = 'group.admin'
