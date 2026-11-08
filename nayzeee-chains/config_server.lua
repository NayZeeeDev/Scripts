-- Server-only settings. This file is never sent to players, so secrets go here.

ServerConfig = {}

-- Discord webhook for snatches, throws, studio changes. '' = off
ServerConfig.Webhook = ''

-- Who counts as an admin for the studio (besides the ace in Config.Studio.Ace)
ServerConfig.AdminGroups = { 'admin', 'god', 'superadmin' }
