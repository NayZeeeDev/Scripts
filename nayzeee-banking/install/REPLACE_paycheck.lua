--[[
    OPTIONAL — only needed when Config.Payroll.mode = 'bank' AND your ESX
    build has no xPlayer.togglePaycheck (pre-Legacy 1.9).

    In es_extended/server/paycheck.lua, find the line that pays the player:

        xPlayer.addAccountMoney('bank', salary, 'Paycheck')

    Replace it with:

        TriggerEvent('nz_bank:paycheck', xPlayer.source, salary, xPlayer.job.label)

    Then set Config.Payroll.mode = 'esx' back to 'bank' and make sure
    togglePaycheck is NOT also running, or wages pay twice.

    On ESX Legacy 1.9+ you do not need this file at all.
]]
