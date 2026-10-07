Locales = Locales or {}

Locales['en'] = {
    title              = 'Wig Snatch',

    -- snatch
    no_one_close       = 'No one is close enough',
    cooldown           = 'Slow down, you can snatch again in %ss',
    already_bald       = 'They have nothing left to snatch',
    cant_snatch        = "You can't snatch them right now",
    target_protected   = 'They are protected right now',
    target_immune      = 'They just lost their hair, give them a minute',
    target_new         = "They're new in the city, leave them be",
    target_job         = "You can't snatch someone on duty",
    target_busy        = 'They are busy',
    self_protected     = "You can't snatch while protected",
    self_job           = "You can't snatch while on duty",
    in_vehicle         = "Can't do that from a vehicle",
    pockets_full       = 'Your pockets are full',
    wrong_model        = "That character can't be snatched",
    no_zone            = "You can't do that here",
    protection_ended   = 'Your new player protection has ended',

    -- clash
    clash_win          = 'You snatched %s',
    clash_lose_snatcher = '%s held on to it',
    clash_defended     = 'You held on to your hair',
    clash_lost         = '%s snatched your hair',
    clash_lost_wig     = '%s snatched your wig',
    revenge            = 'Revenge. You got %s back',
    bounty_claimed     = 'Bounty claimed: $%s',
    streak             = '%s snatch streak',

    -- hair
    regrown            = 'Your hair grew back',
    restored           = 'Your hair is back',
    cut_reset          = 'Your haircut has been reset',
    wig_on             = 'You put on the wig',
    wig_off            = 'You took off the wig',
    wig_wrong_model    = "That wig doesn't fit your character",
    no_wig_worn        = "You're not wearing a wig",
    glue_on            = 'Lace glued down for %s minutes',
    glue_bald          = 'You need hair to glue down',
    kit_used           = 'Wig repaired to %s%%',
    kit_full           = 'That wig is already in perfect condition',
    no_kit             = 'You need a wig kit',

    -- buyer
    buyer_calling      = 'Texting the buyer...',
    buyer_coming       = 'The buyer is on his way',
    buyer_arrived      = 'The buyer is here',
    buyer_left         = 'The buyer left',
    buyer_lost         = "The buyer couldn't reach you",
    buyer_cooldown     = 'The buyer will answer again in %ss',
    buyer_none         = "You don't have any wigs to sell",
    buyer_active       = 'The buyer is already on his way',
    buyer_session      = 'The buyer is gone',
    sold               = 'Sold %s wig(s) for $%s',

    -- barber
    barber_open        = 'Barber',
    barber_not_needed  = 'Nothing to fix',
    paid               = 'Paid $%s',
    no_money           = "You can't afford that",
    repaired           = 'Wig repaired for $%s',

    -- tools
    tool_need          = 'You need %s',
    tool_request_sent  = 'Asked %s if they want a haircut',
    tool_declined      = '%s said no',
    tool_timeout       = '%s didn\'t answer',
    tool_cancelled     = 'Haircut cancelled',
    tool_done_barber   = 'Haircut done',
    tool_done_client   = 'New look',
    buzz_forced        = 'You buzzed %s',
    buzz_victim        = '%s buzzed your hair off',
    buzz_needs_restrain = 'They have to be cuffed, downed or have their hands up',
    tool_prompt_title  = 'Haircut',
    tool_prompt_body   = '%s wants to give you a haircut',

    -- bounty
    bounty_placed      = 'Bounty of $%s placed on %s',
    bounty_bad_amount  = 'Bounty must be between $%s and $%s',
    bounty_not_allowed = 'You can only put a bounty on someone who snatched you',
    bounty_self        = "You can't put a bounty on yourself",
    bounty_refund      = 'Your bounty on %s expired. Refunded $%s',
    bounty_broadcast   = '$%s bounty on %s',

    -- trade
    trade_sent         = 'Offer sent to %s',
    trade_prompt_title = 'Wig offer',
    trade_prompt_sell  = '%s wants to sell you a wig for $%s',
    trade_prompt_gift  = '%s wants to give you a wig',
    trade_accepted     = '%s accepted your offer',
    trade_declined     = '%s declined your offer',
    trade_expired      = 'The offer expired',
    trade_done_buyer   = 'You got the wig',
    trade_failed       = 'Trade failed',
    trade_too_far      = 'They are too far away',
    trade_pending      = 'They already have an offer waiting',

    -- passive
    passive_on         = 'Passive mode on. You can\'t snatch or be snatched',
    passive_off        = 'Passive mode off',
    passive_cooldown   = 'You can toggle passive mode again in %s minutes',

    -- catalog
    catalog_reward     = 'Catalog milestone: %s styles. +$%s',
    level_up           = 'New title: %s',

    -- generic
    busy               = "You're busy",
    invalid            = 'Something went wrong',
}
