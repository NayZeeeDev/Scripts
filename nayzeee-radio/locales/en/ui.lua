--[[
    NAYZEEE RADIO - English strings: shared NUI kit (ui.*)

    Sent to the page as '_core' action 'config' → locale (client/core/ui.lua PushConfig),
    every key twice: 'close' and 'ui.close'. html/core/nzr.js reads them with
    NZR.t('ui.close', 'Close'); apps may add their own ui.* keys here or keep their
    strings in their module's locale file and send them with their 'open' data.

    Translate by copying this file to locales/<lang>/ui.lua and changing the values.
]]

if not NAYZEEE_LOCK_OK then return end

NZR.AddLocale('en', {
    -- ── buttons and words every window uses
    ['ui.close']          = 'Close',
    ['ui.cancel']         = 'Cancel',
    ['ui.confirm']        = 'Confirm',
    ['ui.back']           = 'Back',
    ['ui.done']           = 'Done',
    ['ui.save']           = 'Save',
    ['ui.saving']         = 'Saving',
    ['ui.saved']          = 'Saved',
    ['ui.delete']         = 'Delete',
    ['ui.remove']         = 'Remove',
    ['ui.edit']           = 'Edit',
    ['ui.add']            = 'Add',
    ['ui.search']         = 'Search',
    ['ui.refresh']        = 'Refresh',
    ['ui.yes']            = 'Yes',
    ['ui.no']             = 'No',
    ['ui.on']             = 'On',
    ['ui.off']            = 'Off',
    ['ui.loading']        = 'Loading',
    ['ui.empty']          = 'Nothing here yet',
    ['ui.error']          = 'Something went wrong',
    ['ui.unknown']        = 'Unknown',

    -- ── toast titles (when a message has none)
    ['ui.success']        = 'Done',
    ['ui.warning']        = 'Heads up',
    ['ui.info']           = 'Radio',
    ['ui.failed']         = 'Failed',

    -- ── key names shown in key chips
    ['ui.esc']            = 'ESC',
    ['ui.enter']          = 'ENTER',
    ['ui.space']          = 'SPACE',
    ['ui.shift']          = 'SHIFT',
    ['ui.lmb']            = 'LMB',
    ['ui.rmb']            = 'RMB',
    ['ui.wheel']          = 'WHEEL',

    -- ── units
    ['ui.seconds']        = 's',
    ['ui.minutes']        = 'min',
    ['ui.metres']         = 'm',
    ['ui.percent']        = '%',
    ['ui.mhz']            = 'MHz',
})
