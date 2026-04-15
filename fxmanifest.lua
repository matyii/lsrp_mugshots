fx_version 'cerulean'
game 'gta5'

author 'Matyas'
description 'Player Mugshot Saver (Base64)'
version '1.0.0'

-- Qbox / QB dependency (optional but recommended)
dependency 'qb-core'

-- If you use oxmysql (recommended for Qbox)
server_script '@oxmysql/lib/MySQL.lua'

-- Scripts
client_script 'client.lua'
server_script 'server.lua'

-- Export dependency (make sure this resource starts AFTER MugShotBase64)
dependency 'MugShotBase64'