fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'

name 'srp-vehprop'
description 'Vehicle Prop Attachment System'
author 'SRP'
version '1.0.0'

client_script "@mythic-pwnzor/client/check.lua"

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/gizmo.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'ui/dist/index.html'

files {
    'ui/dist/index.html',
    'ui/dist/**/*',
}

