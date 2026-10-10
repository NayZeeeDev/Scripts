--[[ Money counter — counts your stacks (strapped stacks pay more at the books) or your cash (roleplay).
     The count itself is public: everyone nearby sees the screen tick up. ]]

Counter = {}

local C = Config.Counter
local now = os.time

local function cashAccount() return Bridge.framework == 'esx' and 'money' or 'cash' end

lib.callback.register('nzmw:counter:start', function(src, id, mode)
    local st, p, err = Stations.guard(src, id, { type = 'counter', state = 'idle' })
    if not st then return err end
    local total, extra, ids = 0, nil, {}

    if mode == 'stacks' then
        for _, s in ipairs(Inv.batchSlots(src, NZ.finalItem())) do
            local b = Batches.get(s.metadata.batch)
            if b and not b.counted and b.stage >= #NZ.pipeline() then
                ids[#ids + 1] = b.id
                total = total + b.amount
            end
        end
        if #ids == 0 then return Stations.fail('No uncounted stacks on you.') end
    elseif mode == 'cash' then
        total = Bridge.getAccount(src, cashAccount())
        extra = 0
        for _, s in ipairs(Stations.dirtySources(src)) do extra = extra + s.total end
        if total + extra <= 0 then return Stations.fail('Your pockets are empty.') end
    else
        return Stations.fail('Unknown mode.')
    end

    local duration = math.floor(NZ.clamp(C.baseTime + (total + (extra or 0)) / C.perSecond, C.baseTime, C.maxTime))
    st.state, st.mode, st.amount, st.amount2 = 'counting', mode, total, extra
    st.endsAt, st.total, st.user = now() + duration, duration, src
    st.bills = math.floor((total + (extra or 0)) / 100)
    p.counting = ids
    Stations.commit(id)
    return { ok = true, duration = duration, total = total, extra = extra, stacks = #ids }
end)

-- called from the station ticker every second
function Counter.tick(id, st, p, t)
    if st.state == 'counting' and st.endsAt and t >= st.endsAt then
        local strapped = 0
        for _, bid in ipairs(p.counting or {}) do
            local b = Batches.get(bid)
            if b and not b.counted then
                b.counted = true
                Batches.trail(b, 'Counted and strapped')
                Batches.save(b)
                strapped = strapped + 1
            end
        end
        p.counting = nil
        local user = st.user
        st.state, st.endsAt, st.total, st.user = 'result', t + C.resultTime, nil, nil
        Stations.commit(id)
        if user and GetPlayerName(user) then
            if st.mode == 'stacks' then
                Bridge.notify(user, 'Counted', ('%s in %d stack(s), strapped. Worth +%d%% at the books.'):format(
                    NZ.money(st.amount), strapped, math.floor(C.bonus * 100)), 'success', 8000)
            else
                Bridge.notify(user, 'Counted', ('Clean %s · dirty %s'):format(NZ.money(st.amount), NZ.money(st.amount2 or 0)), 'info', 8000)
            end
        end
    elseif st.state == 'result' and st.endsAt and t >= st.endsAt then
        st.state, st.endsAt, st.mode, st.amount, st.amount2, st.bills = 'idle', nil, nil, nil, nil, nil
        Stations.commit(id)
    end
end
