local function DebugPrint(msg)
    print("^5[MUGSHOT]^7 " .. msg)
end

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        DebugPrint("^2Resource started successfully!^7")
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        DebugPrint("^3Resource stopped!^7")
    end
end)

-- Create table + test DB on resource start
CreateThread(function()
    Wait(2000) -- wait for oxmysql to fully load

    DebugPrint("Checking database connection...")

    local success = pcall(function()
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS player_mugshots (
                id INT AUTO_INCREMENT PRIMARY KEY,
                identifier VARCHAR(64) NOT NULL UNIQUE,
                mugshot LONGTEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
        ]])
    end)

    if success then
        DebugPrint("^2Database connected & table ready!^7")
    else
        DebugPrint("^1Database check failed!^7")
    end
end)

local function GetLicenseIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src)

    for _, id in pairs(identifiers) do
        if string.find(id, "license2:") then
            return id
        end
    end

    for _, id in pairs(identifiers) do
        if string.find(id, "license:") then
            return id
        end
    end

    return nil
end

local function GetCharacterIdentifier(src)
    if GetResourceState('qbx_core') == 'started' then
        local success, player = pcall(function()
            return exports.qbx_core:GetPlayer(src)
        end)

        if success and player then
            local playerData = player.PlayerData
            local citizenId = playerData and playerData.citizenid or player.citizenid

            if citizenId and citizenId ~= '' then
                return ('char:%s'):format(citizenId)
            end
        end
    end

    if GetResourceState('qb-core') == 'started' then
        local success, qbCore = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)

        if success and qbCore and qbCore.Functions then
            local player = qbCore.Functions.GetPlayer(src)
            local citizenId = player and player.PlayerData and player.PlayerData.citizenid

            if citizenId and citizenId ~= '' then
                return ('char:%s'):format(citizenId)
            end
        end
    end

    return GetLicenseIdentifier(src)
end

local function NormalizeMugshotData(imageData, defaultMimeType)
    if type(imageData) ~= 'string' or imageData == '' then
        return nil
    end

    if imageData:match('^data:image/[%w%+%-%.]+;base64,') then
        return imageData
    end

    return ('data:%s;base64,%s'):format(defaultMimeType or 'image/png', imageData)
end

local function SaveMugshot(src, identifier, mugshot)
    if not identifier then
        return false
    end

    if not mugshot or mugshot == '' then
        return false
    end

    MySQL.query([[
        INSERT INTO player_mugshots (identifier, mugshot)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE mugshot = VALUES(mugshot)
    ]], { identifier, mugshot }, function()
        DebugPrint("^2Saved mugshot for " .. identifier .. "^7")

        if src then
            TriggerClientEvent('mugshot:saveConfirmed', src)
        end
    end)

    return true
end

-- Save mugshot
RegisterNetEvent("mugshot:save", function(mugshot)
    local src = source
    local identifier = GetCharacterIdentifier(src)

    if not identifier then
        DebugPrint("^1No identifier found for player " .. src .. "^7")
        return
    end

    mugshot = NormalizeMugshotData(mugshot, 'image/png')

    if not mugshot then
        DebugPrint("^1No mugshot received from player " .. src .. "^7")
        return
    end

    DebugPrint("Received mugshot from player " .. src)

    if not SaveMugshot(src, identifier, mugshot) then
        TriggerClientEvent('mugshot:saveFailed', src)
    end
end)