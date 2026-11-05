--[[
    NAYZEEE BILLING - Custom framework template (server)

    Set Config.Framework = 'custom' and implement every function below for your framework.
    Each one is documented with what it receives and must return. Until you do, the resource
    refuses to start billing (it prints which function is missing).
]]

if Shared.GetFramework() ~= 'custom' then return end

Framework = { Name = 'custom' }

local function todo(name)
    return function()
        error(('[nayzeee-billing] bridge/framework/custom.lua: implement Framework.%s'):format(name))
    end
end

Framework.GetPlayer = todo('GetPlayer')                 -- (source) -> player object or nil
Framework.GetIdentifier = todo('GetIdentifier')         -- (source) -> unique character id (string)
Framework.GetName = todo('GetName')                     -- (source) -> character full name
Framework.GetJob = todo('GetJob')                       -- (source) -> { name, label, grade (number), gradeLabel, isBoss (bool), onDuty (bool) }
Framework.GetMoney = todo('GetMoney')                   -- (source, 'cash'|'bank') -> number
Framework.RemoveMoney = todo('RemoveMoney')             -- (source, account, amount, reason) -> bool (false if they can't cover it)
Framework.AddMoney = todo('AddMoney')                   -- (source, account, amount, reason) -> bool
Framework.GetSource = todo('GetSource')                 -- (identifier) -> source or nil (offline)
Framework.IsAdminGroup = function() return false end    -- (source) -> bool (ACE Config.Admin.Ace is checked separately)
Framework.GetJobLabel = function(job) return nil end    -- (job) -> label or nil
Framework.SearchCharacters = function() return {} end   -- (query, limit) -> { { identifier, name } }
Framework.GetCharacterName = todo('GetCharacterName')   -- (identifier) -> name or nil (online or offline)
Framework.GetOfflineBank = function() return nil end    -- (identifier) -> number or nil
Framework.RemoveOfflineBank = function() return false end -- (identifier, amount, allowNegative) -> bool (atomic)
Framework.AddOfflineBank = function() return false end  -- (identifier, amount) -> bool
Framework.GetSocietyMembers = function() return {} end  -- (job) -> { { identifier, name, grade, gradeLabel, isBoss, online } }
Framework.RegisterUsableItem = function() end           -- (itemName, cb(source, metadata))
Framework.OnPlayerLoaded = function() end               -- (cb(source)) called when a character finishes loading

CreateThread(function()
    Console.log('warn', 'Config.Framework is "custom": fill in bridge/framework/custom.lua before going live')
end)
