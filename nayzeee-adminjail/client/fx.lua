--[[
    Cinematics — sky camera transitions, mugshot booking, escape alarm, release.
    Everything here only runs during the moment itself; nothing stays resident.
]]

Fx = {}

local C = Config.Cinematic
local ON = C.enabled

local function sound(name, set)
    if ON and C.sounds then PlaySoundFrontend(-1, name, set, true) end
end
Fx.Sound = sound

local function waitFor(cond, timeout)
    local deadline = GetGameTimer() + timeout
    while not cond() and GetGameTimer() < deadline do Wait(0) end
end

local function effect(name, ms)
    if not (ON and C.effects) then return end
    AnimpostfxPlay(name, 0, true)
    SetTimeout(ms, function() AnimpostfxStop(name) end)
end

--[[ Movement ]]

--- Moves the ped and waits for the world to stream in around it.
function Fx.Place(coords)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, true)

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(50) end
    FreezeEntityPosition(ped, false)
end

--- Fade to black, run `mid` (teleport / outfit change), fade back in.
function Fx.Fade(mid, ms)
    DoScreenFadeOut(ms or 400)
    waitFor(IsScreenFadedOut, 2000)
    mid()
    DoScreenFadeIn(700)
end

--- GTA character-switch camera: pulls up into the sky, travels, drops back down.
function Fx.Sky(mid)
    if not (ON and C.skyCam) then return Fx.Fade(mid) end

    SwitchOutPlayer(PlayerPedId(), 0, 1)
    waitFor(function() return GetPlayerSwitchState() == 5 end, 10000)
    mid()
    SwitchInPlayer(PlayerPedId())
    waitFor(function() return not IsPlayerSwitchInProgress() end, 15000)
end

--[[ Headshot — the player's real face, rendered by the game, shown in the NUI ]]

local headshot

function Fx.Headshot()
    if headshot then UnregisterPedheadshot(headshot) headshot = nil end

    local handle = RegisterPedheadshotTransparent(PlayerPedId())
    local deadline = GetGameTimer() + 4000
    while not (IsPedheadshotReady(handle) and IsPedheadshotValid(handle)) do
        if GetGameTimer() > deadline then
            UnregisterPedheadshot(handle)
            return nil
        end
        Wait(50)
    end

    headshot = handle
    local txd = GetPedheadshotTxdString(handle)
    return ('https://nui-img/%s/%s'):format(txd, txd)
end

function Fx.FreeHeadshot()
    if headshot then UnregisterPedheadshot(headshot) end
    headshot = nil
end

--[[ Booking — mugshot board + two flashes, front and side ]]

local BOARD, BOARD_TEXT = `prop_police_id_board`, `prop_police_id_text`

local function renderTarget(name, model)
    if not IsNamedRendertargetRegistered(name) then RegisterNamedRendertarget(name, false) end
    if not IsNamedRendertargetLinked(model) then LinkNamedRendertarget(model) end
    return GetNamedRendertargetRenderId(name)
end

local function createBoard(ped, s)
    local scaleform = RequestScaleformMovie('mugshot_board_01')
    waitFor(function() return HasScaleformMovieLoaded(scaleform) end, 3000)
    lib.requestModel(BOARD)
    lib.requestModel(BOARD_TEXT)

    local c = GetEntityCoords(ped)
    local board = CreateObject(BOARD, c.x, c.y, c.z, false, true, false)
    local text = CreateObject(BOARD_TEXT, c.x, c.y, c.z, false, true, false)
    AttachEntityToEntity(text, board, -1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    AttachEntityToEntity(board, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetModelAsNoLongerNeeded(BOARD)
    SetModelAsNoLongerNeeded(BOARD_TEXT)

    BeginScaleformMovieMethod(scaleform, 'SET_BOARD')
    PushScaleformMovieMethodParameterString(C.board)
    PushScaleformMovieMethodParameterString(s.name or '')
    PushScaleformMovieMethodParameterString(s.caseId or '')
    PushScaleformMovieMethodParameterString(s.bookedOn or '')
    PushScaleformMovieMethodParameterInt(0)
    PushScaleformMovieMethodParameterInt(math.random(1, 9))
    PushScaleformMovieMethodParameterInt(0)
    EndScaleformMovieMethod()

    local b = { board = board, text = text, scaleform = scaleform, target = renderTarget('ID_Text', BOARD_TEXT), alive = true }

    CreateThread(function()
        while b.alive do
            SetTextRenderId(b.target)
            SetScriptGfxDrawOrder(4)
            SetScriptGfxDrawBehindPausemenu(true)
            DrawScaleformMovie(b.scaleform, 0.405, 0.37, 0.81, 0.74, 255, 255, 255, 255, 0)
            SetScriptGfxDrawBehindPausemenu(false)
            SetTextRenderId(GetDefaultScriptRendertargetRenderId())
            Wait(0)
        end
    end)
    return b
end

local function destroyBoard(b)
    if not b then return end
    b.alive = false
    if DoesEntityExist(b.text) then DeleteEntity(b.text) end
    if DoesEntityExist(b.board) then DeleteEntity(b.board) end
    SetScaleformMovieAsNoLongerNeeded(b.scaleform)
    if IsNamedRendertargetRegistered('ID_Text') then ReleaseNamedRendertarget('ID_Text') end
end

local function flash()
    sound('Camera_Shoot', 'Phone_Soundset_Franklin')
    Hud.Fx('flash')
end

--- Plays the booking scene. `avatar` is the headshot url for the booking card.
function Fx.Booking(s, avatar)
    Hud.Fx('booking', { sentence = s, avatar = avatar })
    if not (ON and C.mugshot) then
        Wait(5200)
        return
    end

    local ped = PlayerPedId()
    local heading = GetEntityHeading(ped)
    local female = GetEntityModel(ped) == `mp_f_freemode_01`
    local dict = female and 'mp_character_creation@lineup@female_a' or 'mp_character_creation@lineup@male_a'

    FreezeEntityPosition(ped, true)
    lib.requestAnimDict(dict)
    TaskPlayAnim(ped, dict, 'loop_raised', 8.0, -8.0, -1, 49, 0, false, false, false)
    local board = createBoard(ped, s)

    local front = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.0, 0.55)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', front.x, front.y, front.z, 0.0, 0.0, 0.0, 40.0, false, 2)
    PointCamAtPedBone(cam, ped, 31086, 0.0, 0.0, -0.12, true)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 900, true, true)

    Wait(1700)
    flash()
    Wait(1300)
    SetEntityHeading(ped, heading - 90.0) -- side profile
    Wait(800)
    flash()
    Wait(1400)
    SetEntityHeading(ped, heading)

    RenderScriptCams(false, true, 900, true, true)
    Wait(900)
    DestroyCam(cam, false)
    destroyBoard(board)
    StopAnimTask(ped, dict, 'loop_raised', 2.0)
    RemoveAnimDict(dict)
    FreezeEntityPosition(ped, false)
end

--[[ Escape — alarm, red pulse, shake ]]

function Fx.Escape(penalty, attempt)
    Hud.Fx('alarm', { penalty = penalty, attempt = attempt })
    sound('TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET')
    sound('Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS')
    effect('Rampage', 2600)
    if ON and C.effects then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35) end
end

--[[ Release — summary card, then the sky camera home ]]

function Fx.Release(summary)
    Hud.Fx('release', summary)
    sound('CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET')
    effect('SuccessNeutral', 3500)
    Wait(2600)
    Fx.Sky(function()
        Outfit.Restore()
        Fx.Place(summary.coords)
    end)
end

--[[ Work feedback ]]

function Fx.TaskDone(cycle)
    if cycle then
        sound('MEDAL_UP', 'HUD_MINI_GAME_SOUNDSET')
    else
        sound('PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET')
    end
end
