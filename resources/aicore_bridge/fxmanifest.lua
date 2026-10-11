fx_version 'cerulean'
game 'gta5'

name 'aicore_bridge'
description 'AicoreBridge - opt-in QBox/QBCore compatibility layer for Aicore'
author 'Aicore Contributors'
repository 'https://github.com/0error-scripts/ai-core'
version '0.1.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
}

server_scripts {
    'server/bridge.lua',
}

dependencies {
    'aicore',
    'ox_lib',
}

-- Makes exports['qb-core'] resolve to this bridge.
-- Only use alongside aicore, never with qb-core/qbx_core.
provide 'qb-core'
