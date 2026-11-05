--[[
    Folder name lock.

    Every export, event and NUI callback in this resource is namespaced to
    nayzeee-banking. Renaming the folder breaks all of them quietly — the
    script boots, the UI opens, and then exports fail somewhere else on the
    server with no obvious cause.

    So it refuses to run at all instead.
]]

local REQUIRED = 'nayzeee-banking'
local current  = GetCurrentResourceName()

BankLocked = current ~= REQUIRED

if BankLocked then
    -- the same block the console module prints, which never loads when locked
    local function rule(corner, title)
        local head = ('^5   %s─ %s ^5'):format(corner, title)
        local visible = utf8.len((head:gsub('%^%d', ''))) or #head
        return head .. string.rep('─', math.max(3, 66 - visible))
    end
    print(table.concat({
        '',
        '^5   ███╗   ██╗ █████╗ ██╗   ██╗███████╗███████╗███████╗███████╗',
        '^5   ████╗  ██║██╔══██╗╚██╗ ██╔╝╚══███╔╝██╔════╝██╔════╝██╔════╝',
        '^5   ██╔██╗ ██║███████║ ╚████╔╝   ███╔╝ █████╗  █████╗  █████╗',
        '^5   ██║╚██╗██║██╔══██║  ╚██╔╝   ███╔╝  ██╔══╝  ██╔══╝  ██╔══╝',
        '^5   ██║ ╚████║██║  ██║   ██║   ███████╗███████╗███████╗███████╗',
        '^5   ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝╚══════╝╚══════╝',
        ('^7   NayZeee Banking ^5v%s'):format(GetResourceMetadata(current, 'version', 0) or '1.0.0'),
        '',
        rule('┌', '^7About'),
        '^5   │ ^7Developer    ^5NayZeee Development',
        '^5   │ ^7Discord      ^5discord.gg/nayzeeedev',
        ('^5   │ ^7Resource     ^5%s'):format(current),
        rule('├', '^7Server'),
        ('^5   │^1 FAIL ^7Folder name    ^7is "%s": rename the folder to %s and restart'):format(current, REQUIRED),
        rule('└', '^1Stopped ^7the resource will not run'),
        '^0',
    }, '\n'))

    if IsDuplicityVersion() then
        CreateThread(function()
            Wait(500)
            StopResource(current)
        end)
    end
end
