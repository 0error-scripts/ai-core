fx_version 'cerulean'
game 'gta5'

name 'aicore'
description 'Aicore - the performance-first FiveM server core'
author 'Aicore Contributors'
repository 'https://github.com/0error-scripts/ai-core'
version '0.1.0'

lua54 'yes'
use_experimental_fxv2_oal 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/storage.lua',
    'server/player.lua',
    'server/groups.lua',
    'server/character.lua',
    'server/functions.lua',
    'server/commands.lua',
    'server/events.lua',
    'server/loops.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

provide 'aicore'
