Shared = {}

local SERIAL_CHARS = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'

local function checksum(body)
    local sum = 0
    for i = 1, #body do sum = sum + body:byte(i) * i end
    local k = sum % #SERIAL_CHARS + 1
    return SERIAL_CHARS:sub(k, k)
end

--- Serial like NZ-7F3K2Q8M. Real pairs end in a valid check character;
--- fakes get a random one, which a legit check can catch later.
function Shared.NewSerial(real)
    local body = ''
    for _ = 1, 7 do
        local k = math.random(#SERIAL_CHARS)
        body = body .. SERIAL_CHARS:sub(k, k)
    end
    local check = checksum(body)
    if not real then
        repeat
            local k = math.random(#SERIAL_CHARS)
            check = SERIAL_CHARS:sub(k, k)
        until check ~= checksum(body)
    end
    return ('NZ-%s%s'):format(body, check)
end

function Shared.SerialValid(serial)
    local body, check = tostring(serial):match('^NZ%-(%w%w%w%w%w%w%w)(%w)$')
    return body ~= nil and checksum(body) == check
end

function Shared.ConditionLabel(id)
    for _, c in ipairs(Config.Conditions) do
        if c.id == id then return c.label end
    end
    return id or '?'
end

function Shared.ShoeName(meta)
    local shoe = meta and Config.Shoes[meta.shoe]
    if not shoe then return 'Unknown shoes' end
    return ("%s '%s'"):format(shoe.label, shoe.colourway)
end

--- Text shown under the item in the inventory
function Shared.Describe(meta)
    local dirt = tonumber(meta.dirt) or 0
    local lines = {
        ('US %s · %s'):format(meta.size or '?', Shared.ConditionLabel(meta.condition)),
        ('Serial %s'):format(meta.serial or '—'),
    }
    if dirt >= 5 then lines[#lines + 1] = ('Dirt %d%%'):format(dirt) end
    return table.concat(lines, '\n')
end

--- 'male' | 'female' | nil (non-freemode ped)
function Shared.PedGender(model)
    if model == `mp_m_freemode_01` then return 'male' end
    if model == `mp_f_freemode_01` then return 'female' end
    return nil
end

--- The clothing entry a ped of `gender` should get for this shoe, or nil
function Shared.ClothingFor(shoe, gender)
    local c = shoe and shoe.clothing
    if not c then return nil end
    if c[gender] then return c[gender] end
    if c.drawable ~= nil then return c end
    return nil
end

function Shared.Debug(...)
    if Config.Debug then print('^5[nz_sneakers]^7', ...) end
end
