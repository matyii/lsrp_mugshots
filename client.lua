local captureToken = 0

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

local function WaitForStablePed(token, requireAppearanceChange)
    local deadline = GetGameTimer() + 20000
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

                if (not requireAppearanceChange or seenAppearanceChange) and GetGameTimer() - stableSince >= 2000 then
                    return ped
                end
            end
        end

        Wait(500)
    end

    return PlayerPedId()
end

local function ResetMugshotCapture()
    captureToken = captureToken + 1
end

local function ScheduleMugshotCapture(requireAppearanceChange)
    captureToken = captureToken + 1
    local token = captureToken

    CreateThread(function()
        Wait(1500)

        if token ~= captureToken then
            return
        end

        local ped = WaitForStablePed(token, requireAppearanceChange)

        if token ~= captureToken or ped == 0 or not DoesEntityExist(ped) then
            return
        end

        local mugshot = exports['MugShotBase64']:GetMugShotBase64(ped, true)

        if mugshot and token == captureToken then
            TriggerServerEvent('mugshot:save', mugshot)
        end
    end)
end

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