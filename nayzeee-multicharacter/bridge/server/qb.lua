if not NAYZEEE_LOCK_OK then return end
if not NZ.IsQB then return end

--[[
    QBCore + Qbox bridge.
    QBCore: remove qb-multicharacter.   Qbox: in qbx_core/config/client.lua set characters.useExternalCharacters = true

    Squad search by "state id": if your `players` table has a `stateid` column (custom / some Qbox forks)
    it is searched exactly. Rename STATEID_COLUMN below if yours is called differently.
]]

local QB
local qbx = NZ.IsQbox
local STATEID_COLUMN = 'stateid'

CreateThread(function()
    local res = qbx and 'qbx_core' or 'qb-core'
    while GetResourceState(res) ~= 'started' do Wait(100) end
    if qbx then
        QB = { qbx = true }
        if GetResourceState('qb-core') == 'started' then
            local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
            if ok and core then QB.core = core end
        end
    else
        QB = { core = exports['qb-core']:GetCoreObject() }
    end
end)

function Bridge.Ready() return QB ~= nil end

local function getPlayer(src)
    if qbx then return exports.qbx_core:GetPlayer(src) end
    return QB.core.Functions.GetPlayer(src)
end

local function licenses(src)
    local l1 = GetPlayerIdentifierByType(src, 'license')
    local l2 = GetPlayerIdentifierByType(src, 'license2')
    if qbx then return l2 or l1, l1 or l2 end
    return l1, l1
end

function Bridge.Owner(src)
    local primary = licenses(src)
    return primary
end

local function normalise(row, skinRow)
    local ci = NZ.Decode(row.charinfo) or {}
    local job = NZ.Decode(row.job) or {}
    local money = NZ.Decode(row.money) or {}
    local grade = type(job.grade) == 'table' and job.grade or {}
    local gender = (ci.gender == 1 or ci.gender == '1' or ci.gender == 'f') and 'f' or 'm'
    local skin = skinRow and NZ.Decode(skinRow.skin)
    local model = skinRow and skinRow.model
    if skin and model and not skin.model then skin.model = tonumber(model) or model end
    return {
        id          = row.citizenid,
        slot        = tonumber(row.cid) or tonumber(ci.cid),
        owner       = row.license,
        firstname   = ci.firstname or '',
        lastname    = ci.lastname or '',
        dob         = Bridge.ISO(ci.birthdate, 'YYYY-MM-DD'),
        gender      = gender,
        height      = tonumber(ci.height),
        nationality = ci.nationality,
        job         = { name = job.name or 'unemployed', label = job.label or job.name or NZ.T('unemployed'),
                        grade = tonumber(grade.level) or 0, gradeLabel = grade.name or '' },
        cash        = tonumber(money.cash) or 0,
        bank        = tonumber(money.bank) or 0,
        phone       = ci.phone or row.phone_number,
        position    = NZ.Vec(NZ.Decode(row.position)),
        skin        = skin,
        model       = model or Bridge.SkinModel(skin, gender),
        raw         = row,
    }
end

-- Active outfit per citizenid (illenium-appearance / qb-clothing playerskins)
local function skinsFor(ids)
    local skins = {}
    if #ids > 0 and Bridge.TableExists('playerskins', 'citizenid') then
        local sk = MySQL.query.await(('SELECT citizenid, model, skin FROM `playerskins` WHERE active = 1 AND citizenid IN (%s)'):format(Bridge.Marks(#ids)), ids) or {}
        for i = 1, #sk do skins[sk[i].citizenid] = sk[i] end
    end
    return skins
end

local function build(rows, needSlot)
    local ids = {}
    for i = 1, #rows do ids[#ids + 1] = rows[i].citizenid end
    local skins = skinsFor(ids)
    local list = {}
    for i = 1, #rows do
        local c = normalise(rows[i], skins[rows[i].citizenid])
        if c.slot or not needSlot then list[#list + 1] = c end
    end
    return list
end

function Bridge.Fetch(src)
    local a, b = licenses(src)
    local rows = MySQL.query.await('SELECT * FROM `players` WHERE `license` = ? OR `license` = ?', { a, b }) or {}
    return build(rows, true)
end

function Bridge.FetchByIds(ids)
    if #ids == 0 then return {} end
    local rows = MySQL.query.await(('SELECT * FROM `players` WHERE `citizenid` IN (%s)'):format(Bridge.Marks(#ids)), ids) or {}
    return build(rows, false)
end

-- Squad search. exact = citizenid / stateid match, otherwise full-name LIKE
function Bridge.Search(query, exact)
    local rows = {}
    local sb = Config.Squad.searchBy
    if exact then
        if sb.citizenid then
            rows = MySQL.query.await('SELECT citizenid, charinfo FROM `players` WHERE `citizenid` = ? LIMIT 1', { query }) or {}
        end
        if #rows == 0 and sb.stateid and Bridge.TableExists('players', STATEID_COLUMN) then
            rows = MySQL.query.await(('SELECT citizenid, charinfo FROM `players` WHERE `%s` = ? LIMIT 1'):format(STATEID_COLUMN), { query }) or {}
        end
    else
        rows = MySQL.query.await([[SELECT citizenid, charinfo FROM `players`
            WHERE CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
            LIMIT 25]], { '%' .. Bridge.LikeEscape(query) .. '%' }) or {}
    end
    local out = {}
    for i = 1, #rows do
        local ci = NZ.Decode(rows[i].charinfo) or {}
        out[#out + 1] = { id = rows[i].citizenid, firstname = ci.firstname or '', lastname = ci.lastname or '' }
    end
    return out
end

local function waitPlayer(src, ms)
    local deadline = GetGameTimer() + (ms or 8000)
    while not getPlayer(src) and GetGameTimer() < deadline do Wait(50) end
    return getPlayer(src)
end

function Bridge.Load(src, char)
    local current = getPlayer(src)
    if current and current.PlayerData.citizenid == char.id then return true end
    local ok
    if qbx then ok = exports.qbx_core:Login(src, char.id)
    else ok = QB.core.Player.Login(src, char.id) end
    if not ok or not waitPlayer(src) then return false end
    if not qbx then QB.core.Commands.Refresh(src) end
    return true
end

function Bridge.Create(src, slot, data)
    local newData = {
        cid = slot,
        charinfo = {
            firstname   = data.firstname,
            lastname    = data.lastname,
            birthdate   = Bridge.FormatDate(data.dobY, data.dobM, data.dobD, 'YYYY-MM-DD'),
            gender      = data.gender == 'f' and 1 or 0,
            nationality = data.nationality or Config.Registration.nationality.default,
            height      = data.height,
            cid         = slot,
        },
    }
    local ok
    if qbx then ok = exports.qbx_core:Login(src, false, newData)
    else ok = QB.core.Player.Login(src, false, newData) end
    local p = ok and waitPlayer(src)
    if not p then return false end
    if not qbx then QB.core.Commands.Refresh(src) end
    return true, p.PlayerData.citizenid
end

function Bridge.Delete(src, charId)
    for _, t in ipairs(ServerConfig.DeleteTables.qb or {}) do
        if Bridge.TableExists(t.table, t.column) then
            pcall(MySQL.query.await, ('DELETE FROM `%s` WHERE `%s` = ?'):format(t.table, t.column), { charId })
        end
    end
    local ok = pcall(function()
        if qbx then exports.qbx_core:DeleteCharacter(charId)
        elseif src and src > 0 then QB.core.Player.DeleteCharacter(src, charId)
        else error('console delete') end                    -- console / admin: raw delete below
    end)
    if not ok then
        MySQL.update.await('DELETE FROM `players` WHERE `citizenid` = ?', { charId })
    end
    return true
end

function Bridge.Logout(src)
    if qbx then exports.qbx_core:Logout(src) else QB.core.Player.Logout(src) end
    local deadline = GetGameTimer() + 4000
    while getPlayer(src) and GetGameTimer() < deadline do Wait(50) end
    return true
end

function Bridge.IsLoaded(src) return QB ~= nil and getPlayer(src) ~= nil end

function Bridge.ActiveId(src)
    local p = getPlayer(src)
    return p and p.PlayerData.citizenid
end

function Bridge.ActiveJob(src)
    local p = getPlayer(src)
    if not p then return nil, 0 end
    local j = p.PlayerData.job or {}
    return j.name, tonumber(j.grade and j.grade.level) or 0
end

function Bridge.NameTaken(first, last)
    return MySQL.scalar.await([[SELECT 1 FROM `players`
        WHERE LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname'))) = LOWER(?)
          AND LOWER(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) = LOWER(?) LIMIT 1]], { first, last }) ~= nil
end

function Bridge.AddMoney(src, account, amount)
    local p = getPlayer(src)
    if not p or amount <= 0 then return end
    p.Functions.AddMoney(account, amount, 'starter')
end

function Bridge.FrameworkAddItem(src, name, count, metadata)
    local p = getPlayer(src)
    return p and p.Functions.AddItem(name, count, false, metadata) or false
end

function Bridge.FrameworkStarter(src)
    local p = getPlayer(src)
    local shared = QB.core and QB.core.Shared
    if not p or not shared or not shared.StarterItems then return end
    local pd = p.PlayerData
    for _, v in pairs(shared.StarterItems) do
        local info = {}
        if v.item == 'id_card' then
            info = { citizenid = pd.citizenid, firstname = pd.charinfo.firstname, lastname = pd.charinfo.lastname,
                     birthdate = pd.charinfo.birthdate, gender = pd.charinfo.gender, nationality = pd.charinfo.nationality }
        elseif v.item == 'driver_license' then
            info = { firstname = pd.charinfo.firstname, lastname = pd.charinfo.lastname, birthdate = pd.charinfo.birthdate, type = 'Class C Driver License' }
        end
        Bridge.AddItem(src, v.item, v.amount or 1, info)
    end
end

function Bridge.Position(charId)
    local pos = MySQL.scalar.await('SELECT `position` FROM `players` WHERE `citizenid` = ?', { charId })
    return NZ.Vec(NZ.Decode(pos))
end

-- Weapon label from QBCore shared items (Qbox labels come from ox_inventory in inventory.lua)
function Bridge.FrameworkWeaponLabel(name)
    local items = QB and QB.core and QB.core.Shared and QB.core.Shared.Items
    local it = items and (items[name:lower()] or items[name])
    return it and it.label or nil
end

function Bridge.MulticharEnabled() return nil end
