--[[
    ═══════════════════════════════════════════════════════════════════════════
    NAYZEEE MULTIJOB - ESX Paycheck with Duty Check
    ═══════════════════════════════════════════════════════════════════════════

    REPLACE your es_extended/server/paycheck.lua with this file.

    Players will ONLY receive paychecks if they are clocked in via
    nayzeee-multijob. Unemployed players are auto clocked-in so they
    still receive welfare as normal.

    ───────────────────────────────────────────────────────────────────────────
    NOTIFICATIONS
    ───────────────────────────────────────────────────────────────────────────
    By default every paycheck message is handed to nayzeee-multijob, which
    sends it wherever Config.Notifications.output points:

        output = 'notify'  -> on-screen notification only
        output = 'phone'   -> phone notification only
        output = 'both'    -> both at once

    You do NOT need a phone. 'notify' is the default and never touches one.

    If you would rather keep paycheck messages independent of nayzeee-multijob,
    set NAYZEEE.useMultijobNotify = false below and pick a fallback.

    Search for "NAYZEEE" to see every change from default ESX.
    ═══════════════════════════════════════════════════════════════════════════
]]

-- ═══════════════════════════════════════════════════════════════════════════
-- NAYZEEE CONFIG
-- ═══════════════════════════════════════════════════════════════════════════

local NAYZEEE = {
    -- Require the player to be clocked in via nayzeee-multijob to get paid
    requireClockIn = true,

    -- Tell the player when a paycheck was skipped because they were off duty
    notifySkipped = true,

    -- Route all paycheck messages through nayzeee-multijob's notification
    -- config (recommended - one place to configure phones + notify systems)
    useMultijobNotify = true,

    -- Used when useMultijobNotify = false, or nayzeee-multijob is stopped.
    -- 'esx' | 'esx_advanced' | 'ox_lib' | 'chat' | 'none'
    fallback = 'esx_advanced',

    -- Phone/bank app label used by the fallback advanced notification
    bankDict = 'CHAR_BANK_MAZE',
}

-- ═══════════════════════════════════════════════════════════════════════════
-- NAYZEEE NOTIFICATION BRIDGE
-- ═══════════════════════════════════════════════════════════════════════════

local function MultijobReady()
    return GetResourceState('nayzeee-multijob') == 'started'
end

--- @param nType 'success' | 'error' | 'warning' | 'info'
local function Notify(player, title, message, nType)
    if NAYZEEE.useMultijobNotify and MultijobReady() then
        local ok = pcall(function()
            exports['nayzeee-multijob']:Notify(player, {
                title = title,
                message = message,
                type = nType or 'info',
            })
        end)
        if ok then return end
    end

    local mode = NAYZEEE.fallback

    if mode == 'none' then
        return

    elseif mode == 'ox_lib' then
        TriggerClientEvent('ox_lib:notify', player, {
            title = title,
            description = message,
            type = nType == 'error' and 'error' or nType == 'warning' and 'warning' or 'success',
        })

    elseif mode == 'chat' then
        TriggerClientEvent('chat:addMessage', player, {
            color = { 8, 175, 162 },
            multiline = true,
            args = { title, message },
        })

    elseif mode == 'esx' then
        local prefix = nType == 'error' and '~r~' or nType == 'warning' and '~o~' or '~g~'
        TriggerClientEvent('esx:showNotification', player, prefix .. title .. ': ~s~' .. message)

    else -- esx_advanced
        local prefix = nType == 'error' and '~r~' or nType == 'warning' and '~o~' or '~g~'
        TriggerClientEvent('esx:showAdvancedNotification', player,
            title, prefix .. (nType == 'error' and 'Failed' or 'Paycheck'),
            message, NAYZEEE.bankDict, 9
        )
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PAYCHECK LOOP
-- ═══════════════════════════════════════════════════════════════════════════

function StartPayCheck()
    CreateThread(function()
        while true do
            Wait(Config.PaycheckInterval)

            for player, xPlayer in pairs(ESX.Players) do
                local jobLabel = xPlayer.job.label
                local job = xPlayer.job.grade_name
                local onDuty = xPlayer.job.onDuty

                local salary = (job == "unemployed" or onDuty)
                    and xPlayer.job.grade_salary
                    or ESX.Math.Round(xPlayer.job.grade_salary * Config.OffDutyPaycheckMultiplier)

                if xPlayer.paycheckEnabled then
                    if salary > 0 then

                        -- ═══════════════════════════════════════════════════
                        -- NAYZEEE MULTIJOB: Check if player is clocked in
                        -- Skip paycheck if not clocked in via multijob
                        -- ═══════════════════════════════════════════════════
                        local isClockedIn = true
                        local multijobReady = MultijobReady()

                        if multijobReady and NAYZEEE.requireClockIn then
                            isClockedIn = exports['nayzeee-multijob']:IsPlayerOnDuty(player)
                        end

                        if not isClockedIn then
                            if NAYZEEE.notifySkipped then
                                Notify(player, "Paycheck Skipped",
                                    "You must be clocked in to receive your salary.", "error")
                            end
                            goto continue
                        end
                        -- ═══════════════════════════════════════════════════
                        -- END NAYZEEE MULTIJOB CHECK
                        -- ═══════════════════════════════════════════════════

                        -- UNEMPLOYED / WELFARE
                        if job == "unemployed" then
                            xPlayer.addAccountMoney("bank", salary, "Welfare Check")

                            Notify(player, "Welfare",
                                "You received a welfare payment of $" .. salary, "success")

                            if Config.LogPaycheck then
                                ESX.DiscordLogFields("Paycheck", "Paycheck - Unemployment Benefits", "green", {
                                    { name = "Player", value = xPlayer.name, inline = true },
                                    { name = "ID", value = xPlayer.source, inline = true },
                                    { name = "Amount", value = salary, inline = true },
                                })
                            end

                            -- NAYZEEE: Track paycheck earnings
                            if multijobReady then
                                TriggerEvent('nayzeee-multijob:trackPaycheck', player, salary, xPlayer.job.name)
                            end


                        -- SOCIETY JOB PAY
                        elseif Config.EnableSocietyPayouts then
                            TriggerEvent("esx_society:getSociety", xPlayer.job.name, function(society)

                                if society ~= nil then
                                    TriggerEvent("esx_addonaccount:getSharedAccount", society.account, function(account)

                                        if account.money >= salary then
                                            xPlayer.addAccountMoney("bank", salary, "Paycheck")
                                            account.removeMoney(salary) -- society pays the wage (stock ESX does this too)

                                            Notify(player, "Paycheck",
                                                "Your salary of $" .. salary .. " has been deposited", "success")

                                            if Config.LogPaycheck then
                                                ESX.DiscordLogFields("Paycheck", "Paycheck - " .. jobLabel, "green", {
                                                    { name = "Player", value = xPlayer.name, inline = true },
                                                    { name = "ID", value = xPlayer.source, inline = true },
                                                    { name = "Amount", value = salary, inline = true },
                                                })
                                            end

                                            -- NAYZEEE: Track paycheck earnings
                                            if multijobReady then
                                                TriggerEvent('nayzeee-multijob:trackPaycheck', player, salary, xPlayer.job.name)
                                            end

                                        else
                                            Notify(player, "Paycheck Failed",
                                                "Your company cannot afford to pay salaries right now.", "error")
                                        end

                                    end)
                                else
                                    -- JOB WITHOUT SOCIETY
                                    xPlayer.addAccountMoney("bank", salary, "Paycheck")

                                    Notify(player, "Paycheck",
                                        "You received a paycheck of $" .. salary, "success")

                                    if Config.LogPaycheck then
                                        ESX.DiscordLogFields("Paycheck", "Paycheck - " .. jobLabel, "green", {
                                            { name = "Player", value = xPlayer.name, inline = true },
                                            { name = "ID", value = xPlayer.source, inline = true },
                                            { name = "Amount", value = salary, inline = true },
                                        })
                                    end

                                    -- NAYZEEE: Track paycheck earnings
                                    if multijobReady then
                                        TriggerEvent('nayzeee-multijob:trackPaycheck', player, salary, xPlayer.job.name)
                                    end
                                end
                            end)

                        else
                            -- GENERIC PAYCHECK
                            xPlayer.addAccountMoney("bank", salary, "Paycheck")

                            Notify(player, "Paycheck",
                                "You received a paycheck of $" .. salary, "success")

                            if Config.LogPaycheck then
                                ESX.DiscordLogFields("Paycheck", "Paycheck - Generic", "green", {
                                    { name = "Player", value = xPlayer.name, inline = true },
                                    { name = "ID", value = xPlayer.source, inline = true },
                                    { name = "Amount", value = salary, inline = true },
                                })
                            end

                            -- NAYZEEE: Track paycheck earnings
                            if multijobReady then
                                TriggerEvent('nayzeee-multijob:trackPaycheck', player, salary, xPlayer.job.name)
                            end
                        end

                    end
                end

                ::continue::
            end
        end
    end)
end
