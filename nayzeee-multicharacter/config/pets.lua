-- ██████╗ ███████╗████████╗███████╗
-- ██╔══██╗██╔════╝╚══██╔══╝██╔════╝
-- ██████╔╝█████╗     ██║   ███████╗
-- ██╔═══╝ ██╔══╝     ██║   ╚════██║
-- ██║     ███████╗   ██║   ███████║
-- ╚═╝     ╚══════╝   ╚═╝   ╚══════╝

--[[
    COMPANION PETS — a pet sits next to the character in the lobby (Customize > Pet) and follows them
    into the car / out of frame in the departure cutscene.

    access
      'all'     every character may pick any pet below
      'ace'     pets with `ace` need that permission (others are free)
      'bridge'  ask bridge/server/pets.lua (link your own pet script — return the pet ids a character owns)
    idles   pet animations (one is picked at random). kind = 'dog' | 'smalldog' | 'cat'
]]

Config.Pets = {
    enabled = true,
    access  = 'all',
    names   = true,                    -- players can name their pet (shown on its nameplate)

    list = {
        { id = 'husky',      label = 'Husky',           model = 'a_c_husky',      kind = 'dog' },
        { id = 'shepherd',   label = 'Shepherd',        model = 'a_c_shepherd',   kind = 'dog' },
        { id = 'rottweiler', label = 'Rottweiler',      model = 'a_c_rottweiler', kind = 'dog' },
        { id = 'retriever',  label = 'Retriever',       model = 'a_c_retriever',  kind = 'dog' },
        { id = 'pug',        label = 'Pug',             model = 'a_c_pug',        kind = 'smalldog' },
        { id = 'poodle',     label = 'Poodle',          model = 'a_c_poodle',     kind = 'smalldog' },
        { id = 'westy',      label = 'Westie',          model = 'a_c_westy',      kind = 'smalldog' },
        { id = 'cat',        label = 'Cat',             model = 'a_c_cat_01',     kind = 'cat' },
        -- { id = 'chop', label = 'Chop', model = 'a_c_chop', kind = 'dog', ace = 'nayzeee.pets.vip' },
    },

    idles = {
        dog = {
            { label = 'Sitting',   dict = 'creatures@rottweiler@amb@world_dog_sitting@base', clip = 'base' },
            { label = 'Laying',    dict = 'creatures@rottweiler@amb@sleep_in_kennel@',       clip = 'sleep_in_kennel' },
            { label = 'Barking',   dict = 'creatures@rottweiler@amb@world_dog_barking@idle_a', clip = 'idle_a' },
        },
        smalldog = {
            { label = 'Sitting',   dict = 'creatures@pug@amb@world_dog_sitting@idle_a', clip = 'idle_b' },
            { label = 'Barking',   dict = 'creatures@pug@amb@world_dog_barking@idle_a', clip = 'idle_a' },
        },
        cat = {
            { label = 'Resting',   dict = 'creatures@cat@amb@world_cat_sleeping@base', clip = 'base' },
        },
    },
}
