--[[
    NAYZEEE Inventory Manager — framework bridge (server)
    Drop this file into es_extended, qb-core or qbx_core and add `server_script 'nayzeee.lua'`
    as the LAST line of that resource's fxmanifest (see INSTALL.md).

    Money and item changes run inside the framework, so logs would otherwise say every dollar
    came from the framework itself. This wraps the money functions, notes which script called
    them, and hands that name to the manager right before the framework fires its usual events.
]]
local RES = GetCurrentResourceName()

local function tagged(src, kind, name, fn, ...)
    local by = GetInvokingResource() or RES
    if src then TriggerEvent('nzinv:attr', src, kind, name, by) end
    local out = table.pack(pcall(fn, ...))
    if src then TriggerEvent('nzinv:attr', src, kind, name, nil) end
    if not out[1] then error(out[2], 0) end
    return table.unpack(out, 2, out.n)
end

-- ─── ESX Legacy ────────────────────────────────────────────────────────────
if type(CreateExtendedPlayer) == 'function' then
    local create = CreateExtendedPlayer
    CreateExtendedPlayer = function(...)
        local x = create(...)
        if type(x) ~= 'table' then return x end
        local src = x.source
        for _, m in ipairs({ 'addAccountMoney', 'removeAccountMoney', 'setAccountMoney' }) do
            local f = x[m]
            if f then x[m] = function(account, ...) return tagged(src, 'money', account, f, account, ...) end end
        end
        local addItem = x.addInventoryItem
        if addItem then x.addInventoryItem = function(item, ...) return tagged(src, 'item', item, addItem, item, ...) end end
        return x
    end
    print('^2[nayzeee]^0 money source tracking active (es_extended)')
    return
end

-- ─── Qbox ──────────────────────────────────────────────────────────────────
if RES == 'qbx_core' and type(AddMoney) == 'function' then
    local function srcOf(identifier)
        if type(identifier) == 'number' then return identifier end
        local ok, p = pcall(function() return exports.qbx_core:GetPlayerByCitizenId(identifier) end)
        return ok and p and p.PlayerData and p.PlayerData.source or nil
    end
    for _, m in ipairs({ 'AddMoney', 'RemoveMoney', 'SetMoney' }) do
        local f = _G[m]
        local wrapped = function(identifier, moneyType, ...)
            return tagged(srcOf(identifier), 'money', moneyType, f, identifier, moneyType, ...)
        end
        _G[m] = wrapped
        exports(m, wrapped)
    end
    print('^2[nayzeee]^0 money source tracking active (qbx_core)')
    return
end

-- ─── QBCore ────────────────────────────────────────────────────────────────
if QBCore and QBCore.Player and type(QBCore.Player.CreatePlayer) == 'function' then
    local METHODS = { 'AddMoney', 'RemoveMoney', 'SetMoney' }
    local create = QBCore.Player.CreatePlayer
    QBCore.Player.CreatePlayer = function(PlayerData, Offline, ...)
        local ret = create(PlayerData, Offline, ...)
        -- qb-core only returns the player for offline loads; online ones go into QBCore.Players
        local p = ret
        if type(p) ~= 'table' and not Offline and type(PlayerData) == 'table' and type(QBCore.Players) == 'table' then
            p = PlayerData.source and QBCore.Players[PlayerData.source]
            if not p then
                for _, x in pairs(QBCore.Players) do
                    if type(x) == 'table' and x.PlayerData and x.PlayerData.citizenid == PlayerData.citizenid then p = x break end
                end
            end
        end
        if type(p) ~= 'table' then return ret end
        -- class-style players (player:AddMoney)
        local mt = getmetatable(p)
        local cls = mt and type(mt.__index) == 'table' and mt.__index
        if cls and not rawget(cls, '__nzWrapped') then
            rawset(cls, '__nzWrapped', true)
            for _, m in ipairs(METHODS) do
                local f = rawget(cls, m)
                if f then
                    cls[m] = function(self, account, ...)
                        return tagged(self.PlayerData and self.PlayerData.source, 'money', account, f, self, account, ...)
                    end
                end
            end
        end
        -- Player.Functions.AddMoney style
        if type(p.Functions) == 'table' then
            for _, m in ipairs(METHODS) do
                local f = p.Functions[m]
                if f then
                    p.Functions[m] = function(account, ...)
                        return tagged(p.PlayerData and p.PlayerData.source, 'money', account, f, account, ...)
                    end
                end
            end
        end
        return ret
    end
    print('^2[nayzeee]^0 money source tracking active (qb-core)')
    return
end

print('^3[nayzeee]^0 framework bridge loaded in ' .. RES .. ' but no supported framework was found here')
