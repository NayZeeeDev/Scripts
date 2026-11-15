Locales = Locales or {}

Locales['en'] = {
    -- mode
    mode_on          = 'CUT UP mode on. Hit 80 km/h to start a run.',
    mode_off         = 'CUT UP mode off',
    mode_blocked     = "You can't cut up here",
    need_driver      = 'Get in the driver seat first',

    -- runs
    run_start        = 'RUN STARTED',
    run_over         = 'RUN OVER',
    run_saved        = 'Run saved: %s pts',
    run_too_small    = 'Run too short to save',
    run_rejected     = 'Run rejected: %s',
    new_pb           = 'NEW PERSONAL BEST',
    rank_up          = 'RANK UP: %s',
    crash            = 'CRASH',
    scrape           = 'SCRAPE',
    hearts_left      = '%d hearts left',
    out_of_hearts    = 'Out of hearts',
    time_up          = 'Time up',
    idle_end         = 'You stopped for too long',
    left_vehicle     = 'You left your car',
    top_announce     = '%s just took #%d on the %s board with %s pts',

    -- flow
    flow_state       = 'FLOW STATE',
    crew_flow        = 'CREW FLOW',
    flow_broken      = 'FLOW BROKEN',

    -- car
    repaired         = 'Car repaired',
    repair_denied    = 'Stop and finish your run first',
    camera_mode      = 'Camera: %s',
    fov              = 'FOV %d',
    gearbox          = 'Gearbox: %s',
    no_clutch        = 'Clutch in to change gear',

    -- crews
    crew_created     = 'Crew [%s] %s created',
    crew_joined      = 'You joined [%s] %s',
    crew_left        = 'You left the crew',
    crew_kicked      = 'You were kicked from the crew',
    crew_disbanded   = 'Your crew was disbanded',
    crew_invite      = '%s invited you to [%s] %s. Open F5 > Crew to accept.',
    crew_invite_sent = 'Invite sent to %s',
    crew_member_join = '%s joined the crew',
    crew_member_left = '%s left the crew',
    crew_promoted    = '%s is now %s',
    crew_no_perm     = "You don't have permission for that",
    crew_full        = 'That crew is full',
    crew_in_one      = "You're already in a crew",
    crew_not_in      = "You're not in a crew",
    crew_bad_name    = 'Name must be %d-%d characters',
    crew_bad_tag     = 'Tag must be %d-%d letters or numbers',
    crew_taken       = 'That name or tag is taken',
    crew_no_invite   = 'No invite waiting',
    crew_no_player   = 'Player not found',
    crew_target_in   = 'They are already in a crew',

    -- admin
    admin_reset      = 'Leaderboards reset',
    admin_usage      = 'Usage: /cutupadmin resetboards | resetplayer <id>',
}
