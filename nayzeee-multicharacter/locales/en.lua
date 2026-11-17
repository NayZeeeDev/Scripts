Locales = Locales or {}

--[[
    Lua-side strings (server messages, validation, commands, in-game prompts).
    The lobby UI ships its own English text inside web/; any key in the `ui` table below overrides a UI string
    with the same key, so you can translate the interface from here without rebuilding it.
]]

Locales['en'] = {
    -- validation (server checks the creation form)
    v_required        = 'Required',
    v_min             = 'At least %s characters',
    v_max             = 'At most %s characters',
    v_letters         = 'Letters, spaces, - and \' only',
    v_blacklist       = 'That name is not allowed',
    v_taken           = 'Someone already uses this name',
    v_date            = 'Enter a valid date',
    v_age_min         = 'Must be at least %s years old',
    v_age_max         = 'Must be at most %s years old',
    v_height          = 'Between %s and %s cm',
    v_nationality     = 'Pick a nationality',
    v_gender          = 'Pick a gender',

    -- toasts / server messages
    t_created         = 'Character created',
    t_deleted         = 'Character deleted',
    t_saved           = 'Saved',
    t_error           = 'Something went wrong. Try again.',
    t_rate            = 'Slow down a little',
    t_no_delete       = 'You can not delete characters',
    t_name_mismatch   = 'The name does not match',
    t_slot_locked     = 'That slot is locked',
    t_slot_taken      = 'That slot is already used',
    t_redeemed        = '%s slot(s) added',
    t_redeem_bad      = 'Code not found or already used',
    t_redeem_off      = 'Code redemption is disabled',
    t_disabled        = 'This character is disabled',
    t_relog_wait      = 'You can relog again in %ss',
    t_relog_busy      = 'You can not relog right now',
    t_quit            = 'See you soon.',
    t_invalid         = 'That option is not available',
    t_not_owned       = 'This character does not own that',

    -- squad / couple
    t_sq_sent         = 'Request sent to %s',
    t_sq_got          = '%s wants to link with you as %s',
    t_sq_got_prompt   = '%s wants to show up in your lobby as your %s. Accept?',
    t_sq_accepted     = 'You are now linked with %s',
    t_sq_declined     = '%s declined your request',
    t_sq_removed      = 'Link removed',
    t_sq_switch_sent  = 'Asked %s to switch to %s',
    t_sq_switched     = 'You and %s are now %s',
    t_sq_self         = 'You can not link your own characters',
    t_sq_exists       = 'You are already linked or have a pending request',
    t_sq_full         = 'Your lobby is full',
    t_sq_target_full  = 'Their lobby is full',
    t_sq_couple_taken = 'One of you already has a partner',
    t_sq_pending_max  = 'Too many pending requests',
    t_sq_not_found    = 'No character found',
    t_sq_disabled     = 'Squads are disabled',
    sq_squad          = 'Squad',
    sq_couple         = 'Partner',

    -- spawn
    last_location     = 'Last location',
    last_location_sub = 'Where you logged off',
    your_house        = 'Your property',
    first_spawn       = 'Arrival',
    first_spawn_sub   = 'Where every new story starts',

    -- in-game
    relog_prompt      = '[E] Change character',
    relog_target      = 'Change character',
    unemployed        = 'Unemployed',

    -- commands
    c_relog           = 'Go back to character selection',
    c_setslots        = 'Set granted extra slots for a player',
    c_addslots        = 'Add granted extra slots for a player',
    c_delchar         = 'Delete a character by id',
    c_disable         = 'Disable a character',
    c_enable          = 'Enable a character',
    c_forcerelog      = 'Send a player back to character selection',
    c_coords          = 'Copy position + camera for scene building',
    c_lobby           = 'Preview a lobby theme (admin scene editor)',
    c_slotsinfo       = 'Show slot sources for a player',
    done              = 'Done',
    not_found         = 'Not found',

    -- UI overrides: any lobby UI string key -> your text (see web/src/i18n/en.ts for the keys)
    ui = {
        -- deploy = 'Enter the city',
    },
}
