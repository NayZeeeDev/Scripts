--[[
    NAYZEEE RADIO - luacheck configuration

    Run from anywhere:
        luacheck /home/user/Scripts/nayzeee-radio --config /home/user/Scripts/nayzeee-radio/.luacheckrc
    (from the resource folder: luacheck . )

    Goal: syntax errors and real mistakes, not native-name noise. FiveM natives are plain
    globals, so the default run ignores undefined globals (113) along with the style
    warnings below. A run must end with "0 errors"; warnings are allowed.

    Strict pass (also flags misspelt globals and natives missing from the list below):
        luacheck . --config .luacheckrc --enable 113
    Every name it reports is either a typo or a native to add to read_globals here.
    Also check syntax with the stock compiler: for f in $(find . -name '*.lua'); do luac5.4 -p "$f"; done
]]

std = 'lua54'
allow_defined_top = true
max_line_length = false

ignore = {
    '111', '112', '113',        -- setting / mutating / reading globals (FiveM natives are globals)
    '211/_.*',                  -- unused locals named _something
    '212', '213',               -- unused arguments / loop variables (callbacks keep their full signature)
    '231',                      -- variable set but never read
    '311',                      -- value assigned is overwritten before use
    '411', '421', '422', '431', '432',   -- redefinition / shadowing
    '542',                      -- empty if branch
    '611', '612', '613', '614', -- whitespace
    '631',                      -- line length
}

-- Our own globals (written by the resource)
globals = {
    'NZR', 'Config', 'ServerConfig', 'Bridge', 'PropsLayout', 'NAYZEEE_LOCK_OK',
}

-- Read-only globals: runtime libraries + FiveM natives used by the resource
read_globals = {
    -- runtime
    'lib', 'exports', 'json', 'msgpack', 'promise', 'Citizen', 'MySQL', 'cache', 'source',
    'GlobalState', 'LocalPlayer', 'Player', 'Entity',
    'vec', 'vec2', 'vec3', 'vec4', 'vector2', 'vector3', 'vector4', 'quat', 'joaat',

    -- scheduler / events / resources
    'CreateThread', 'Wait', 'SetTimeout', 'ClearTimeout',
    'AddEventHandler', 'RemoveEventHandler', 'RegisterNetEvent', 'RegisterServerEvent',
    'TriggerEvent', 'TriggerServerEvent', 'TriggerClientEvent', 'TriggerLatentClientEvent',
    'RegisterCommand', 'RegisterKeyMapping', 'ExecuteCommand',
    'AddStateBagChangeHandler', 'RemoveStateBagChangeHandler', 'GetStateBagValue',
    'GetCurrentResourceName', 'GetInvokingResource', 'GetResourceState', 'GetResourceMetadata',
    'LoadResourceFile', 'SaveResourceFile', 'StopResource', 'IsDuplicityVersion', 'GetConvar', 'GetConvarInt',
    'GetGameTimer', 'GetFrameTime', 'GetCloudTimeAsInt', 'GetHashKey', 'PerformHttpRequest',
    'GetResourceKvpString', 'GetResourceKvpInt', 'GetResourceKvpFloat', 'SetResourceKvp', 'SetResourceKvpInt',
    'SetResourceKvpFloat', 'DeleteResourceKvp',

    -- players
    'GetPlayers', 'GetPlayerName', 'GetPlayerPed', 'GetPlayerIdentifiers', 'GetPlayerIdentifierByType',
    'IsPlayerAceAllowed', 'GetPlayerServerId', 'GetPlayerFromServerId', 'GetActivePlayers', 'PlayerId',
    'PlayerPedId', 'NetworkIsPlayerActive', 'NetworkGetPlayerIndexFromPed', 'GetPlayerRoutingBucket',
    'IsPedAPlayer', 'IsEntityDead', 'IsPedDeadOrDying', 'IsPedFatallyInjured', 'IsPlayerDead',

    -- entities
    'DoesEntityExist', 'GetEntityCoords', 'GetEntityHeading', 'GetEntityRotation', 'GetEntityModel',
    'GetEntityForwardVector', 'GetEntityMatrix', 'GetEntityVelocity', 'GetOffsetFromEntityInWorldCoords',
    'GetWorldPositionOfEntityBone', 'GetEntityBoneIndexByName', 'GetPedBoneIndex', 'GetPedBoneCoords',
    'SetEntityCoords', 'SetEntityCoordsNoOffset', 'SetEntityHeading', 'SetEntityRotation', 'SetEntityAlpha',
    'ResetEntityAlpha', 'SetEntityVisible', 'SetEntityCollision', 'SetEntityInvincible', 'SetEntityAsMissionEntity',
    'SetEntityNoCollisionEntity', 'SetEntityDrawOutline', 'SetEntityDrawOutlineColor', 'SetEntityLodDist',
    'FreezeEntityPosition', 'AttachEntityToEntity', 'DetachEntity', 'IsEntityAttached', 'IsEntityAttachedToEntity',
    'IsEntityAPed', 'IsEntityAVehicle', 'IsEntityAnObject', 'IsEntityInWater', 'IsEntityPlayingAnim',
    'GetEntitySubmergedLevel', 'IsPedSwimmingUnderWater', 'IsPedSwimming',
    'CreateObject', 'CreateObjectNoOffset', 'DeleteEntity', 'DeleteObject', 'PlaceObjectOnGroundProperly',
    'GetGamePool', 'NetworkGetEntityIsNetworked', 'NetworkGetNetworkIdFromEntity', 'NetworkGetEntityFromNetworkId',
    'NetworkDoesNetworkIdExist', 'NetToVeh', 'NetToObj', 'NetToPed', 'VehToNet', 'ObjToNet', 'PedToNet',
    'GetEntityArchetypeName', 'GetModelDimensions',

    -- models / anims
    'IsModelInCdimage', 'IsModelValid', 'HasModelLoaded', 'RequestModel', 'SetModelAsNoLongerNeeded',
    'HasAnimDictLoaded', 'RequestAnimDict', 'RemoveAnimDict', 'GetAnimDuration', 'TaskPlayAnim',
    'StopAnimTask', 'ClearPedTasks', 'ClearPedTasksImmediately', 'ClearPedSecondaryTask',
    'TaskStartScenarioInPlace', 'SetPedCurrentWeaponVisible', 'SetCurrentPedWeapon', 'GetSelectedPedWeapon',

    -- vehicles
    'IsPedInAnyVehicle', 'GetVehiclePedIsIn', 'GetVehiclePedIsUsing', 'GetPedInVehicleSeat', 'GetVehicleClass',
    'GetVehicleMaxNumberOfPassengers', 'GetVehicleModelNumberOfSeats', 'GetDisplayNameFromVehicleModel',
    'GetVehicleDoorAngleRatio', 'GetNumberOfVehicleDoors', 'IsVehicleWindowIntact', 'GetIsVehicleEngineRunning',
    'GetVehicleNumberPlateText', 'IsThisModelACar', 'GetLastDrivenVehicle', 'IsPedShooting', 'GetPedLastWeaponImpactCoord',

    -- input / controls / cursor
    'DisableControlAction', 'EnableControlAction', 'DisableAllControlActions', 'EnableAllControlActions',
    'IsControlPressed', 'IsControlJustPressed', 'IsControlJustReleased', 'IsControlReleased',
    'IsDisabledControlPressed', 'IsDisabledControlJustPressed', 'IsDisabledControlJustReleased',
    'GetControlNormal', 'GetDisabledControlNormal', 'SetControlNormal', 'SetMouseCursorActiveThisFrame',
    'SetMouseCursorSprite', 'SetMouseCursorVisible', 'IsUsingKeyboard', 'IsPauseMenuActive',

    -- NUI / DUI / textures
    'SendNUIMessage', 'RegisterNUICallback', 'SetNuiFocus', 'SetNuiFocusKeepInput', 'IsNuiFocused',
    'CreateDui', 'DestroyDui', 'GetDuiHandle', 'IsDuiAvailable', 'SendDuiMessage', 'SetDuiUrl',
    'SendDuiMouseMove', 'SendDuiMouseDown', 'SendDuiMouseUp', 'SendDuiMouseWheel',
    'CreateRuntimeTxd', 'CreateRuntimeTextureFromDuiHandle', 'AddReplaceTexture', 'RemoveReplaceTexture',
    'RequestStreamedTextureDict', 'HasStreamedTextureDictLoaded', 'SetStreamedTextureDictAsNoLongerNeeded',

    -- cameras / screen
    'CreateCam', 'CreateCamWithParams', 'DestroyCam', 'SetCamActive', 'RenderScriptCams', 'SetCamCoord',
    'SetCamRot', 'SetCamFov', 'PointCamAtCoord', 'PointCamAtEntity', 'SetCamNearClip', 'SetCamFarClip',
    'DoesCamExist', 'GetGameplayCamCoord', 'GetGameplayCamRot', 'GetFinalRenderedCamCoord', 'GetFinalRenderedCamRot',
    'GetScreenCoordFromWorldCoord', 'GetActiveScreenResolution', 'GetAspectRatio', 'DisplayRadar', 'IsRadarHidden',
    'StartShapeTestLosProbe', 'StartExpensiveSynchronousShapeTestLosProbe', 'StartShapeTestRay', 'GetShapeTestResult',
    'GetShapeTestResultIncludingMaterial', 'GetGroundZFor_3dCoord', 'GetWaterHeight', 'TestProbeAgainstWater',

    -- drawing / text / blips
    'DrawMarker', 'DrawLine', 'DrawPoly', 'DrawRect', 'SetTextFont', 'SetTextScale', 'SetTextColour',
    'SetTextCentre', 'SetTextOutline', 'SetDrawOrigin', 'ClearDrawOrigin', 'BeginTextCommandDisplayText',
    'EndTextCommandDisplayText', 'AddTextComponentSubstringPlayerName', 'BeginTextCommandThefeedPost',
    'EndTextCommandThefeedPostTicker', 'BeginTextCommandSetBlipName', 'EndTextCommandSetBlipName',
    'AddBlipForCoord', 'AddBlipForRadius', 'RemoveBlip', 'DoesBlipExist', 'SetBlipSprite', 'SetBlipColour',
    'SetBlipScale', 'SetBlipAlpha', 'SetBlipFlashes', 'SetBlipAsShortRange', 'SetBlipRoute', 'SetBlipDisplay',
    'GetClockHours', 'GetClockMinutes',

    -- voice / audio (Mumble + submixes)
    'MumbleAddVoiceTargetPlayerByServerId', 'MumbleRemoveVoiceTargetPlayerByServerId', 'MumbleClearVoiceTargetPlayers',
    'MumbleSetVolumeOverrideByServerId', 'MumbleIsPlayerTalking', 'MumbleSetVoiceTarget', 'MumbleGetVoiceChannelFromServerId',
    'NetworkIsPlayerTalking', 'MumbleIsConnected', 'MumbleSetSubmixForServerId',
    'CreateAudioSubmix', 'SetAudioSubmixEffectRadioFx', 'SetAudioSubmixEffectParamInt', 'SetAudioSubmixEffectParamFloat',
    'SetAudioSubmixOutputVolumes', 'AddAudioSubmixOutput', 'PlaySoundFrontend',
}

-- the manifest's directives are globals of their own
files['fxmanifest.lua'] = {
    read_globals = {
        'fx_version', 'game', 'lua54', 'name', 'author', 'description', 'version', 'shared_scripts',
        'client_scripts', 'server_scripts', 'ui_page', 'files', 'dependencies', 'dependency',
        'escrow_ignore', 'data_file', 'this_is_a_map',
    },
}

-- generated by the prop pipeline: it only defines PropsLayout for the other files
files['shared/props_layout.lua'] = { ignore = { '131' } }
