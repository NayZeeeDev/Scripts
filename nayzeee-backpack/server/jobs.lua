-----------------------------------------------------------------
-- Job bags (server)
--
-- * job / grade / duty checks (via the framework bridge + integrations)
-- * the SAME bag comes back every shift: its stash id is remembered
--   per character, so handing a bag in never loses what was inside
-- * starter kits added the first time a bag is issued
-- * auto-issue on duty, auto-return off duty (optional)
-- * police "Search backpack" on cuffed / downed / hands-up players
-----------------------------------------------------------------

local ox = exports.ox_inventory
local cfg = Config.Jobs or {}

local function kvpKey(src, bagKey)
    return ('jobbag:%s:%s'):format(Framework.getIdentifier(src), bagKey)
end

--- Fill a fresh job bag with its configured kit. Unknown items are skipped.
local function giveKit(bagKey, bagid)
    local bag = Config.Backpacks[bagKey]
    if not cfg.giveKit or not bag or type(bag.kit) ~= 'table' then return end

    local id = PrepareStash(bagKey, bagid)
    for _, entry in ipairs(bag.kit) do
        local name, count = entry[1] or entry.name, entry[2] or entry.count or 1
        if name and ox:Items(name) then
            ox:AddItem(id, name, count)
        elseif name then
            print(('^3[nayzeee-backpack] kit item "%s" for %s does not exist in ox_inventory, skipped^0'):format(name, bagKey))
        end
    end
end

--- Hand a job bag to a player, reusing their previous one if they had it.
--- Returns true when the item was added.
function IssueJobBag(src, bagKey, variant)
    if not Bags.isJobBag(bagKey) then return false end

    local key = kvpKey(src, bagKey)
    local bagid = GetResourceKvpString(key)
    local fresh = not bagid
    if fresh then
        bagid = ('%s%s'):format(os.time(), math.random(100000, 999999))
    end

    local meta = { bagid = bagid, issued = true }
    if variant and Bags.variant(bagKey, variant) then meta.variant = tonumber(variant) end

    if not ox:AddItem(src, bagKey, 1, meta) then return false end

    SetResourceKvp(key, bagid)
    if fresh then giveKit(bagKey, bagid) end

    Integrations.each('onIssue', src, bagKey, ('backpack_%s'):format(bagid))
    return true
end

--- Take a job bag back in. The stash is kept for next shift.
function ReturnJobBag(src, bagKey)
    local items = ox:GetInventoryItems(src) or {}
    for _, item in pairs(items) do
        if item and item.name == bagKey then
            if item.metadata and item.metadata.bagid then
                SetResourceKvp(kvpKey(src, bagKey), item.metadata.bagid)
            end
            return ox:RemoveItem(src, bagKey, 1, item.metadata, item.slot)
        end
    end
    return false
end

--- Job bags this player's job is allowed, best grade match first.
local function bagsForJob(job)
    local out = {}
    if not job or not job.name then return out end
    for key in pairs(Config.Backpacks) do
        if Bags.isJobBag(key) and Bags.jobAllows(key, job) then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

-----------------------------------------------------------------
-- job / duty changes
-----------------------------------------------------------------

Framework.onJobChange(function(src, job)
    -- wearing a bag you're no longer allowed takes it off your back
    RefreshBagState(src)

    if not cfg.autoIssue and not cfg.autoReturn then return end

    local onDuty = job and job.onDuty
    local held = FindBagItem(src)

    if cfg.autoReturn and held and Bags.isJobBag(held.name) then
        if not Bags.jobAllows(held.name, job) or not onDuty then
            if ReturnJobBag(src, held.name) then
                TriggerClientEvent('nayzeee-backpack:notify', src, Strings.job_returned, 'inform')
            end
            held = nil
        end
    end

    if cfg.autoIssue and onDuty and not held then
        local key = bagsForJob(job)[1]
        if key and IssueJobBag(src, key) then
            TriggerClientEvent('nayzeee-backpack:notify', src, Strings.job_issued, 'success')
        end
    end
end)

-----------------------------------------------------------------
-- police search
-----------------------------------------------------------------

local search = cfg.policeSearch or {}

local function isPolice(src)
    local job = Framework.getJob(src)
    if not job then return false end
    for _, j in ipairs(search.jobs or {}) do
        if j == job.name then return not cfg.requireDuty or job.onDuty end
    end
    return false
end

RegisterNetEvent('nayzeee-backpack:policeSearch', function(targetId)
    local src = source
    targetId = tonumber(targetId)
    if not search.enabled or not targetId or targetId == src then return end
    if not isPolice(src) then return end

    local a, b = GetPlayerPed(src), GetPlayerPed(targetId)
    if a == 0 or b == 0 then return end
    if #(GetEntityCoords(a) - GetEntityCoords(b)) > (search.distance or 2.0) + 1.5 then return end

    local item = FindBagItem(targetId)
    if not item or not item.metadata or not item.metadata.bagid then
        return TriggerClientEvent('nayzeee-backpack:notify', src, Strings.search_none, 'error')
    end

    local id = PrepareStash(item.name, item.metadata.bagid)
    if Logs then Logs.search(src, targetId, item.name) end
    TriggerClientEvent('nayzeee-backpack:open', src, id)
end)
