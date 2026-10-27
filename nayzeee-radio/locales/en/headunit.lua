--[[
    NAYZEEE RADIO - English strings: MV-90 head unit app (ui.hu_*)

    The key-hint chips around the head unit (html/apps/headunit/app.js). Sent to the page
    with the rest of ui.* in '_core' config (client/core/ui.lua PushConfig); the app reads
    them with NZR.t('ui.<key>', fallback). Words printed on the unit itself (MV-90, VOL, CH,
    EMERG, the LCD indicators) are device labelling and stay as they are. What the LCD shows
    comes from the firmware (client.scr_* in client.lua).
    Translate by copying this file to locales/<lang>/headunit.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    ['ui.hu_close']             = 'Close',
    ['ui.hu_talk']              = 'Hold to talk',
    ['ui.hu_type']              = 'Key in a channel',
    ['ui.hu_channel']           = 'Channel',
    ['ui.hu_volume']            = 'Volume',
})
