Locales = Locales or {}

Locales.en = {
    no_permission      = 'You are not allowed to control this screen.',
    no_admin           = 'Only admins can open the screen manager.',
    locked             = 'This screen is locked.',
    too_far            = 'You are too far away from that screen.',
    invalid_url        = 'That link is not a supported video or stream.',
    blocked_url        = 'That website is blocked on this server.',
    queue_full         = 'The queue is full.',
    added_queue        = 'Added to the queue.',
    now_playing        = 'Now playing on %s.',
    stopped            = 'Playback stopped.',
    placed             = '%s placed.',
    picked_up          = '%s picked up.',
    max_screens        = 'You already have the maximum number of screens placed.',
    no_item            = 'You do not have that item anymore.',
    no_tv_near         = 'There is no screen nearby.',
    remote_taken       = 'Somebody else is holding that remote.',
    remote_paired      = 'Remote paired to %s.',
    remote_dropped     = 'Remote put down.',
    created            = 'Screen created.',
    deleted            = 'Screen removed.',
    saved              = 'Changes saved.',
    calib_saved        = 'Calibration saved for %s.',
    linked             = 'Screens linked — they now mirror each other.',
    unlinked           = 'Screen unlinked.',
    favorite_added     = 'Saved to favorites.',
    favorite_removed   = 'Removed from favorites.',
    search_disabled    = 'YouTube search is not enabled on this server — paste a link instead.',
    place_hint         = 'Place screen',
    place_wall_hint    = 'Draw wall screen',
    place_remote_hint  = 'Place remote',
    prompt_open        = 'Media panel',
    prompt_remote      = 'Use remote',
    prompt_pickup      = 'Pick up',
    prompt_take_remote = 'Pick up remote',
}

function _L(key, ...)
    local pack = Locales[Config.Locale] or Locales.en
    local str = pack[key] or Locales.en[key] or key
    if select('#', ...) > 0 then return str:format(...) end
    return str
end
