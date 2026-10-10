-- On-screen prompts answered with two keys: squad invites and ready checks.
-- One prompt shows at a time; a newer one replaces an older one of the same kind.
local Prompt = nil          -- { kind, data, expires }
local pendingInvites = {}   -- [squadId] = invite
local P = Config.Prompts

local function show(kind, data, seconds)
    Prompt = { kind = kind, data = data, expires = GetGameTimer() + seconds * 1000 }
    NUI('prompt', { kind = kind, data = data, duration = seconds, accept = P.AcceptKey, decline = P.DeclineKey })
    CreateThread(function()
        local mine = Prompt
        while Prompt == mine and GetGameTimer() < mine.expires do Wait(250) end
        if Prompt == mine then
            Prompt = nil
            NUI('prompt', false)
            if mine.kind == 'invite' then pendingInvites[mine.data.id] = nil end
        end
    end)
end

local function clear(kind)
    if Prompt and (not kind or Prompt.kind == kind) then
        Prompt = nil
        NUI('prompt', false)
    end
end
ClearPrompt = clear

--- Answers the running ready check (from a key, or from the menu).
function AnswerReady(answer)
    if Prompt and Prompt.kind == 'ready' then
        Prompt.answered = answer
        NUI('prompt', { kind = 'ready', data = Prompt.data, answered = answer, duration = math.max(1, (Prompt.expires - GetGameTimer()) / 1000) })
    end
    lib.callback.await('nz_squads:readyAnswer', false, answer == true)
end

local function answer(accept)
    if not Prompt then return end
    local p = Prompt
    if p.kind == 'invite' then
        Prompt = nil
        NUI('prompt', false)
        pendingInvites[p.data.id] = nil
        if accept then
            local ok, msg = lib.callback.await('nz_squads:join', false, p.data.id)
            if ok then Notify(('You joined %s'):format(p.data.name), 'success', 'invite', true)
            else Notify(msg or 'Could not join that squad', 'error', 'invite', true) end
        else
            lib.callback.await('nz_squads:declineInvite', false, p.data.id)
        end
    elseif p.kind == 'ready' then
        if p.answered ~= nil then return end
        AnswerReady(accept)
    end
end

lib.addKeybind({
    name = 'nz_squads_accept',
    description = 'Squads: accept the on-screen prompt',
    defaultKey = P.AcceptKey,
    onPressed = function() if Prompt and not MenuOpen then answer(true) end end,
})

lib.addKeybind({
    name = 'nz_squads_decline',
    description = 'Squads: decline the on-screen prompt',
    defaultKey = P.DeclineKey,
    onPressed = function() if Prompt and not MenuOpen then answer(false) end end,
})

-- ─── invites ───────────────────────────────────────────────
RegisterNetEvent('nz_squads:invite', function(inv)
    if Squad then return end
    pendingInvites[inv.id] = inv
    NUI('invite', inv)
    Notify(Config.Strings.invite_received:format(inv.from, inv.name), 'inform', 'invite', true)
    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
    if not MenuOpen then show('invite', inv, inv.expires or Config.InviteExpireSec) end
end)

-- ─── ready checks ──────────────────────────────────────────
RegisterNetEvent('nz_squads:readyCheck', function(data)
    NUI('readyCheck', data)
    if data.bySrc == Me() then
        show('ready', data, data.duration)
        Prompt.answered = true
        NUI('prompt', { kind = 'ready', data = data, answered = true, duration = data.duration })
        return
    end
    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
    show('ready', data, data.duration)
end)

RegisterNetEvent('nz_squads:readyProgress', function(answers)
    NUI('readyProgress', answers)
end)

RegisterNetEvent('nz_squads:readyResult', function(answers)
    clear('ready')
    NUI('readyResult', answers)
end)

AddEventHandler('nz_squads:client:changed', function(_, now)
    if now then
        -- joining a squad makes every open invite moot
        pendingInvites = {}
        clear('invite')
    else
        clear('ready')
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Prompt = nil
end)
