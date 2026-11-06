-- Server only. Never sent to players.
ServerConfig = {}

-- Who can open the admin panel and use /givecoins /setcoins /removecoins.
-- Any match counts: identifier in the list, the ACE permission, or a framework admin group.
ServerConfig.Admins = {
    -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    -- 'discord:123456789012345678',
}
ServerConfig.AcePermission   = 'nayzeee.coinshop.admin'
ServerConfig.FrameworkGroups = { 'admin', 'superadmin', 'god' }    -- ESX groups / QBCore permissions that count as admin

-- Tebex: add a "Server Command" to your coin packages (run when the player is offline OR online):
--   coinshop_addcode {transaction} 1000
-- Players then redeem the tbx-... order number in the shop.
ServerConfig.TebexCommand = 'coinshop_addcode'

-- Discord profile picture + name in the shop (needs a bot token, bot does NOT need to be in your server)
ServerConfig.DiscordBotToken = ''

ServerConfig.Webhooks = {
    purchases = '',     -- Items / deals bought, gifts, refunds
    redeems   = '',     -- Tebex codes and promo codes redeemed, coin transfers
    admin     = '',     -- Everything admins change
}
ServerConfig.WebhookName   = 'Coin Shop'
ServerConfig.WebhookAvatar = ''
ServerConfig.WebhookColors = {
    purchases = 0x08afa2,
    redeems   = 0x3c83f6,
    admin     = 0xe5484d,
}
