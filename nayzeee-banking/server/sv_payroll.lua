if BankLocked then return end

-- ═══════════════════════════════════════════════════════════
--  SOCIETY PAYROLL
--  Bosses set a wage per job grade. Wages are drawn from the
--  society account on a timer and paid into personal accounts
--  (or cash, if the employee turned direct deposit off).
-- ═══════════════════════════════════════════════════════════

Bank.wageIntervals = {
    { id = 'half',   label = 'Every 30 minutes', minutes = 30 },
    { id = 'hourly', label = 'Every hour',       minutes = 60 },
    { id = 'shift',  label = 'Every 4 hours',    minutes = 240 },
}

local function intervalMinutes(id)
    for _, i in ipairs(Bank.wageIntervals) do
        if i.id == id then return i.minutes end
    end
    return 60
end

local function intervalId(minutes)
    for _, i in ipairs(Bank.wageIntervals) do
        if i.minutes == minutes then return i.id end
    end
    return 'hourly'
end

--- Grades for a job, straight from ESX.
local function jobGrades(job)
    local jobs = ESX.GetJobs()
    local data = jobs and jobs[job]
    if not data or not data.grades then return {} end

    local out = {}
    for grade, info in pairs(data.grades) do
        out[#out + 1] = {
            grade = tonumber(grade),
            label = info.label or info.name or tostring(grade),
            salary = info.salary or 0
        }
    end
    table.sort(out, function(a, b) return a.grade < b.grade end)
    return out
end

function Bank.getPayroll(job)
    if not job then return nil end
    if Config.Payroll.mode ~= 'bank' then
        return { mode = 'esx', rows = {}, nextIn = 0, onShift = 0, balance = 0 }
    end

    local saved = MySQL.query.await('SELECT * FROM nz_bank_payroll WHERE job = ?', { job }) or {}
    local byGrade = {}
    for _, r in ipairs(saved) do byGrade[r.grade] = r end

    local rows, soonest = {}, nil
    for _, g in ipairs(jobGrades(job)) do
        local r = byGrade[g.grade]
        rows[#rows + 1] = {
            grade    = g.grade,
            label    = g.label,
            amount   = r and r.amount or 0,
            interval = intervalId(r and r.interval_min or 60),
            enabled  = not r or r.enabled == 1,
            nextIn   = r and math.max(0, math.floor((r.next_run - os.time()) / 60)) or 0
        }
        if r and r.enabled == 1 and r.amount > 0 then
            if not soonest or r.next_run < soonest then soonest = r.next_run end
        end
    end

    local soc = Bank.getSociety(job)
    local staff = 0
    for _ in pairs(ESX.GetExtendedPlayers('job', job)) do staff = staff + 1 end

    return {
        mode      = 'bank',
        rows      = rows,
        nextIn    = soonest and math.max(0, math.floor((soonest - os.time()) / 60)) or 0,
        onShift   = staff,
        balance   = soc and soc.balance or 0,
        intervals = Bank.wageIntervals,
        maxWage   = Config.Payroll.maxWage
    }
end

Bank.callback('nz_bank:getPayroll', function(src, job)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return nil end

    local societies = Bank.societyJobs(xPlayer)
    local target = job or societies[1]
    if not target then return nil end

    local allowed = false
    for _, name in ipairs(societies) do if name == target then allowed = true break end end
    if not allowed then return nil end

    return Bank.getPayroll(target)
end)

Bank.callback('nz_bank:setPayroll', function(src, grade, amount, interval, enabled, job)
    local xPlayer = Bank.getPlayer(src)
    if not xPlayer then return { ok = false, msg = 'Player not found.' } end
    if Config.Payroll.mode ~= 'bank' then
        return { ok = false, msg = 'Wages are handled by ESX on this server.' }
    end

    local societies = Bank.societyJobs(xPlayer)
    local jobName = job or societies[1]
    local allowed = false
    for _, name in ipairs(societies) do if name == jobName then allowed = true break end end
    if not allowed then return { ok = false, msg = 'Only management can set wages.' } end

    grade  = tonumber(grade)
    amount = Bank.round(amount)
    if not grade then return { ok = false, msg = 'Unknown grade.' } end
    if amount < 0 or amount > Config.Payroll.maxWage then
        return { ok = false, msg = ('Wages must be between 0 and %s%s.'):format(Config.Currency, Config.Payroll.maxWage) }
    end

    local label
    for _, g in ipairs(jobGrades(jobName)) do
        if g.grade == grade then label = g.label break end
    end
    if not label then return { ok = false, msg = 'That grade does not exist on this job.' } end

    local minutes = intervalMinutes(interval)

    MySQL.query.await([[
        INSERT INTO nz_bank_payroll (job, grade, grade_label, amount, interval_min, next_run, enabled, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          grade_label = VALUES(grade_label), amount = VALUES(amount),
          interval_min = VALUES(interval_min), enabled = VALUES(enabled), updated_by = VALUES(updated_by)
    ]], {
        jobName, grade, label, amount, minutes,
        os.time() + (minutes * 60), enabled and 1 or 0, Bank.fullName(xPlayer)
    })

    Bank.log('admin', 'Payroll updated',
        ('**%s** set %s · %s to **%s%s** every %s min'):format(
            Bank.fullName(xPlayer), jobName, label, Config.Currency, amount, minutes))

    return { ok = true, msg = ('%s now earns %s%s.'):format(label, Config.Currency, amount) }
end)

--- Pay one employee. Returns true when the money moved.
local function payEmployee(xTarget, soc, wage)
    local ok = Bank.debit(soc.id, wage, {
        category = 'payroll',
        label    = ('Wage · %s'):format(Bank.fullName(xTarget)),
        actorName= 'Payroll'
    })
    if not ok then return false end

    local settings = MySQL.single.await(
        'SELECT direct_deposit FROM nz_bank_settings WHERE identifier = ?', { xTarget.identifier })
    local toBank = not settings or settings.direct_deposit == 1

    if toBank then
        local acc = Bank.getPersonal(xTarget.identifier)
        Bank.credit(acc.id, wage, { category = 'payroll', label = ('Wage · %s'):format(soc.label) })
    else
        Bank.addCash(xTarget, wage)
    end

    Bank.notify(xTarget.source, 'Wage paid',
        ('%s%s from %s'):format(Config.Currency, wage, soc.label), 'success')
    return true
end

--- Optional duty gate. Wire this to whatever duty system you run.
local function onDuty(xTarget)
    if not Config.Payroll.minDuty then return true end

    -- the multi-job resource knows best when it tracks shifts
    local fromJobs = Bank.onDuty and Bank.onDuty(xTarget)
    if fromJobs ~= nil then return fromJobs end

    -- esx_policejob / qb style duty flags live on the player metadata
    local duty = xTarget.get and xTarget.get('duty')
    if duty == nil then return true end
    return duty == true
end

CreateThread(function()
    while true do
        Wait(60000)

        if Config.Payroll.mode ~= 'bank' then goto continue end

        local due = MySQL.query.await(
            'SELECT * FROM nz_bank_payroll WHERE enabled = 1 AND amount > 0 AND next_run <= ?',
            { os.time() }) or {}

        for _, row in ipairs(due) do
            local soc = Bank.getSociety(row.job)
            MySQL.update.await('UPDATE nz_bank_payroll SET next_run = ? WHERE id = ?',
                { os.time() + (row.interval_min * 60), row.id })

            if soc then
                local paid, short = 0, false

                local roster = ESX.GetExtendedPlayers('job', row.job)

                -- with payInactiveJobs on, people clocked into another job
                -- still draw this wage as long as they hold the role
                if Config.MultiJob.enabled and Config.MultiJob.payInactiveJobs then
                    for _, xAny in pairs(ESX.GetExtendedPlayers()) do
                        if xAny.job.name ~= row.job then
                            for _, held in ipairs(Bank.jobsFor(xAny)) do
                                if held.name == row.job and held.grade == row.grade then
                                    roster[#roster + 1] = xAny
                                    break
                                end
                            end
                        end
                    end
                end

                for _, xTarget in pairs(roster) do
                    local grade = xTarget.job.name == row.job and xTarget.job.grade or row.grade
                    if grade == row.grade and onDuty(xTarget) then
                        if payEmployee(xTarget, soc, row.amount) then
                            paid = paid + 1
                        else
                            short = true
                            break
                        end
                    end
                end

                if short then
                    for _, xBoss in pairs(ESX.GetExtendedPlayers('job', row.job)) do
                        if Bank.canUseSociety(xBoss.job.name, xBoss.job.grade_name) then
                            Bank.notify(xBoss.source, 'Payroll failed',
                                ('%s does not have enough to cover wages.'):format(soc.label), 'error')
                        end
                    end
                end

                if paid > 0 then
                    Bank.log('admin', 'Payroll run',
                        ('%s · %s — %s employee%s paid %s%s each'):format(
                            soc.label, row.grade_label, paid, paid == 1 and '' or 's', Config.Currency, row.amount))
                end
            end
        end

        ::continue::
    end
end)

exports('setWage', function(job, grade, amount, minutes)
    local label = ('Grade %s'):format(grade)
    MySQL.query.await([[
        INSERT INTO nz_bank_payroll (job, grade, grade_label, amount, interval_min, next_run)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = VALUES(amount), interval_min = VALUES(interval_min)
    ]], { job, grade, label, Bank.round(amount), minutes or 60, os.time() + ((minutes or 60) * 60) })
    return true
end)
