fx_version 'cerulean'
game 'gta5'

author 'Matyas'
description 'Player Mugshot Saver (Screenshot Capture)'
version '1.1.0'

ui_page 'html/index.html'

-- If you use oxmysql (recommended for Qbox)
server_script '@oxmysql/lib/MySQL.lua'

files {
	'html/index.html',
	'html/app.js'
}

-- Scripts
client_script 'client.lua'
server_script 'server.lua'

-- Screenshot dependency used for face-camera captures
dependency 'screenshot-basic'