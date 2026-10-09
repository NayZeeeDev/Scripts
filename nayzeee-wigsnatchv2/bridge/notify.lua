-- Client notifications: ox_lib (lib.notify), nothing else.
-- kind is always one of: 'success' | 'error' | 'info' | 'warning'

Notifier = {}

-- the player's pick in Vault > Settings, in ox_lib's position names
local POSITION = {
    ['top-left'] = 'top-left', ['top-center'] = 'top', ['top-right'] = 'top-right',
    ['bottom-left'] = 'bottom-left', ['bottom-right'] = 'bottom-right',
}

function Notifier.Send(msg, kind, duration, title)
    kind = (kind == 'success' or kind == 'error' or kind == 'warning') and kind or 'info'
    local pos = Prefs and Prefs.Get('toastPos') or Config.UI.ToastPosition
    lib.notify({
        title = title or L('title'),
        description = msg,
        type = kind == 'info' and 'inform' or kind,
        duration = duration or 4200,
        position = POSITION[pos] or 'top-right',
    })
end
