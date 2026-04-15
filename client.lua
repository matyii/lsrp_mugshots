local CaptureSettings = {
    setupDelayMs = 1500,
    stableDurationMs = 2000,
    appearanceTimeoutMs = 20000,
    captureReadyTimeoutMs = 30000,
    captureReadyStableMs = 1500,
    postReadyDelayMs = 1000,
    cameraWarmupMs = 500,
    cleanupTimeoutMs = 10000,
    cropWidth = 200,
    cropHeight = 250,
    cameraDistance = 1.15,
    cameraHeight = 0.08,
    lookAtHeight = 0.04,
    fov = 26.0,
    lookAtTimeMs = 4000,
    facialExpression = 'mood_happy_1'
}

local captureToken = 0
local activeCamera = nil
local activeCameraToken = 0
local activePed = nil
local controlsLocked = false
local captureActive = false
local nuiCropperReady = false
local pendingCropPayload = nil
local pendingRawMugshot = nil
local CleanupMugshotCamera

local function SendMugshotChatMessage(message)
    TriggerEvent('chat:addMessage', {
        color = { 52, 152, 219 },
        multiline = false,
        args = { 'Mugshot', message }
    })
end

local function FlushPendingCropPayload()
    if nuiCropperReady and pendingCropPayload then
        SendNUIMessage(pendingCropPayload)
        pendingCropPayload = nil
    end
end

local function SubmitMugshotToServer(mugshot)
    if type(mugshot) ~= 'string' or mugshot == '' then
        CleanupMugshotCamera(true)
        SendMugshotChatMessage('A kép mentése nem sikerült, próbáld meg újra később.')
        return
    end

    TriggerServerEvent('mugshot:save', mugshot)
end

local function GetPedAppearanceSignature(ped)
    local signature = { tostring(GetEntityModel(ped)) }

    for componentId = 0, 11 do
        signature[#signature + 1] = ('c%s:%s:%s:%s'):format(
            componentId,
            GetPedDrawableVariation(ped, componentId),
            GetPedTextureVariation(ped, componentId),
            GetPedPaletteVariation(ped, componentId)
        )
    end

    for propId = 0, 7 do
        signature[#signature + 1] = ('p%s:%s:%s'):format(
            propId,
            GetPedPropIndex(ped, propId),
            GetPedPropTextureIndex(ped, propId)
        )
    end

    return table.concat(signature, '|')
end

local function GetFacialAnimDictForPed(ped)
    local model = GetEntityModel(ped)

    if model == GetHashKey('mp_f_freemode_01') then
        return 'facials@gen_female@variations@normal'
    end

    return 'facials@gen_male@variations@normal'
end

local function WaitForStablePed(token, requireAppearanceChange)
    local deadline = GetGameTimer() + CaptureSettings.appearanceTimeoutMs
    local firstSignature = nil
    local lastSignature = nil
    local stableSince = 0
    local seenAppearanceChange = false

    while token == captureToken and GetGameTimer() < deadline do
        local ped = PlayerPedId()

        if ped ~= 0 and DoesEntityExist(ped) then
            local currentSignature = GetPedAppearanceSignature(ped)

            if not firstSignature then
                firstSignature = currentSignature
                lastSignature = currentSignature
            elseif currentSignature ~= lastSignature then
                lastSignature = currentSignature
                stableSince = 0

                if currentSignature ~= firstSignature then
                    seenAppearanceChange = true
                end
            else
                stableSince = stableSince ~= 0 and stableSince or GetGameTimer()

                if (not requireAppearanceChange or seenAppearanceChange) and GetGameTimer() - stableSince >= CaptureSettings.stableDurationMs then
                    return ped
                end
            end
        end

        Wait(500)
    end

    return PlayerPedId()
end

local function IsCaptureSceneReady(ped)
    return ped ~= 0
        and DoesEntityExist(ped)
        and not IsEntityDead(ped)
        and IsEntityVisible(ped)
        and IsScreenFadedIn()
        and IsPlayerControlOn(PlayerId())
        and not IsPauseMenuActive()
        and not IsPlayerSwitchInProgress()
end

local function WaitForCaptureReady(token)
    local deadline = GetGameTimer() + CaptureSettings.captureReadyTimeoutMs
    local stableSince = 0

    while token == captureToken and GetGameTimer() < deadline do
        local ped = PlayerPedId()

        if IsCaptureSceneReady(ped) then
            stableSince = stableSince ~= 0 and stableSince or GetGameTimer()

            if GetGameTimer() - stableSince >= CaptureSettings.captureReadyStableMs then
                Wait(CaptureSettings.postReadyDelayMs)

                if token == captureToken and IsCaptureSceneReady(PlayerPedId()) then
                    return PlayerPedId()
                end

                stableSince = 0
            end
        else
            stableSince = 0
        end

        Wait(250)
    end

    return PlayerPedId()
end

CleanupMugshotCamera = function(silent)
    if activePed and DoesEntityExist(activePed) then
        FreezeEntityPosition(activePed, false)
        ClearFacialIdleAnimOverride(activePed)
        ClearPedSecondaryTask(activePed)
    end

    if activeCamera and DoesCamExist(activeCamera) then
        RenderScriptCams(false, true, 200, false, false)
        DestroyCam(activeCamera, false)
    end

    ClearFocus()

    activeCamera = nil
    activeCameraToken = 0
    activePed = nil
    controlsLocked = false
    pendingRawMugshot = nil

    captureActive = false
end

local function SetupMugshotCamera(token, ped)
    local headCoords = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local forward = GetEntityForwardVector(ped)
    local cameraPosition = vector3(
        headCoords.x + forward.x * CaptureSettings.cameraDistance,
        headCoords.y + forward.y * CaptureSettings.cameraDistance,
        headCoords.z + CaptureSettings.cameraHeight
    )
    local lookAtPosition = vector3(
        headCoords.x,
        headCoords.y,
        headCoords.z + CaptureSettings.lookAtHeight
    )

    CleanupMugshotCamera(true)

    activeCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if not activeCamera or not DoesCamExist(activeCamera) then
        activeCamera = nil
        return false
    end

    SetCamCoord(activeCamera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(activeCamera, lookAtPosition.x, lookAtPosition.y, lookAtPosition.z)
    SetCamFov(activeCamera, CaptureSettings.fov)
    SetCamActive(activeCamera, true)
    RenderScriptCams(true, false, 0, true, true)
    SetFocusPosAndVel(lookAtPosition.x, lookAtPosition.y, lookAtPosition.z, 0.0, 0.0, 0.0)
    FreezeEntityPosition(ped, true)
    SetFacialIdleAnimOverride(ped, CaptureSettings.facialExpression, GetFacialAnimDictForPed(ped))
    TaskLookAtCoord(ped, cameraPosition.x, cameraPosition.y, cameraPosition.z, CaptureSettings.lookAtTimeMs, 0, 2)

    activeCameraToken = token
    activePed = ped
    controlsLocked = true
    captureActive = true

    SendMugshotChatMessage('Mugshot fotó készül rólad, kérlek maradj mozdulatlan egy pillanatig.')

    return true
end

local function RequestMugshotScreenshot(token)
    if GetResourceState('screenshot-basic') ~= 'started' then
        CleanupMugshotCamera(true)
        return
    end

    exports['screenshot-basic']:requestScreenshot({
        encoding = 'png'
    }, function(data)
        if token ~= captureToken or token ~= activeCameraToken then
            return
        end

        if type(data) ~= 'string' or data == '' then
            CleanupMugshotCamera(true)
            return
        end

        pendingRawMugshot = {
            token = token,
            mugshot = data
        }

        pendingCropPayload = {
            type = 'cropMugshot',
            token = token,
            mugshot = data,
            width = CaptureSettings.cropWidth,
            height = CaptureSettings.cropHeight
        }

        FlushPendingCropPayload()
    end)
end

local function ResetMugshotCapture()
    captureToken = captureToken + 1
    CleanupMugshotCamera(true)
end

local function ScheduleMugshotCapture(requireAppearanceChange)
    captureToken = captureToken + 1
    local token = captureToken

    CleanupMugshotCamera(true)

    CreateThread(function()
        Wait(CaptureSettings.setupDelayMs)

        if token ~= captureToken then
            return
        end

        local ped = WaitForStablePed(token, requireAppearanceChange)

        if token ~= captureToken or ped == 0 or not DoesEntityExist(ped) then
            return
        end

        ped = WaitForCaptureReady(token)

        if token ~= captureToken or ped == 0 or not DoesEntityExist(ped) then
            return
        end

        if not SetupMugshotCamera(token, ped) then
            return
        end

        Wait(CaptureSettings.cameraWarmupMs)

        if token ~= captureToken or activeCameraToken ~= token then
            CleanupMugshotCamera(true)
            return
        end

        RequestMugshotScreenshot(token)

        CreateThread(function()
            Wait(CaptureSettings.cleanupTimeoutMs)

            if token == activeCameraToken then
                CleanupMugshotCamera(true)
            end
        end)
    end)
end

RegisterNUICallback('mugshotCropResult', function(data, cb)
    cb({ ok = true })

    local token = tonumber(data and data.token)
    local mugshot = data and data.mugshot

    if not token or token ~= captureToken or token ~= activeCameraToken then
        return
    end

    if type(mugshot) ~= 'string' or mugshot == '' then
        if pendingRawMugshot and pendingRawMugshot.token == token then
            SubmitMugshotToServer(pendingRawMugshot.mugshot)
        else
            CleanupMugshotCamera(true)
            SendMugshotChatMessage('A kép feldolgozása nem sikerült, próbáld meg újra később.')
        end

        return
    end

    SubmitMugshotToServer(mugshot)
end)

RegisterNUICallback('mugshotCropperReady', function(_data, cb)
    nuiCropperReady = true
    cb({ ok = true })
    FlushPendingCropPayload()
end)

RegisterNetEvent('mugshot:saveConfirmed', function()
    CleanupMugshotCamera()
    SendMugshotChatMessage('A kép elkészült, most már újra tudsz mozogni. Az UCP-ben lévő képed sikeresen frissítve lett.')
end)

RegisterNetEvent('mugshot:saveFailed', function()
    CleanupMugshotCamera(true)
    SendMugshotChatMessage('A kép mentése nem sikerült, próbáld meg újra később.')
end)

CreateThread(function()
    while true do
        if activeCamera then
            HideHudAndRadarThisFrame()

            if controlsLocked then
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 45, true)
                DisableControlAction(0, 75, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 143, true)
            end

            for componentId = 1, 19 do
                HideHudComponentThisFrame(componentId)
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        CleanupMugshotCamera(true)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    ScheduleMugshotCapture(true)
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    ResetMugshotCapture()
end)

RegisterNetEvent('qbx_core:client:onPlayerLoaded', function()
    ScheduleMugshotCapture(true)
end)

RegisterNetEvent('qbx_core:client:onPlayerUnload', function()
    ResetMugshotCapture()
end)

RegisterNetEvent('playerSpawned', function()
    ScheduleMugshotCapture(false)
end)

RegisterNetEvent('qb-clothing:client:loadPlayerClothing', function()
    ScheduleMugshotCapture(false)
end)

RegisterNetEvent('qb-clothes:client:loadPlayerClothing', function()
    ScheduleMugshotCapture(false)
end)

RegisterNetEvent('illenium-appearance:client:reloadSkin', function()
    ScheduleMugshotCapture(false)
end)