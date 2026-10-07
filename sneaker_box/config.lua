Config = {}

-- Models (must match the names in stream/)
Config.BaseModel = `nz_shoebox`
Config.LidModel = `nz_shoebox_lid`

-- Where the lid hinges on the base (matches source/generate_model.py)
Config.HingeOffset = vector3(0.0, -0.105, 0.115)

-- Lid animation
Config.OpenAngle = 105.0     -- degrees the lid swings back
Config.OpenTime = 550        -- ms, eases out with a small overshoot
Config.CloseTime = 500       -- ms, lands with a little bounce

-- Interaction
Config.InteractDistance = 1.5
Config.Key = 38              -- E (INPUT_PICKUP)
Config.UseTarget = true      -- use ox_target when it's running, otherwise the key prompt
Config.Anim = { dict = 'pickup_object', clip = 'putdown_low', time = 900 } -- set to false to skip

-- Lids are spawned locally on each client for boxes within this range
Config.StreamDistance = 40.0

-- Commands / limits
Config.Commands = {
    spawn = 'shoebox',          -- /shoebox          place a box in front of you
    delete = 'shoebox_delete',  -- /shoebox_delete   remove the closest box you placed
}
Config.AdminOnly = false        -- true = needs ace 'nz_shoebox.admin' to place boxes
Config.MaxPerPlayer = 3
Config.CleanupOnDrop = true     -- remove a player's boxes when they leave

-- Text shown in the key prompt. Hook ShowPrompt up to your own UI if you want.
Config.Text = {
    open = 'Open box',
    close = 'Close box',
    noModel = 'Shoe box model is not streamed - check sneaker_box/stream',
    limit = 'You already have the max number of boxes out',
    noBox = 'No box of yours nearby',
}

Config.ShowPrompt = function(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(('~INPUT_PICKUP~ %s'):format(text))
    EndTextCommandDisplayHelp(0, false, false, -1)
end

Config.Notify = function(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end
