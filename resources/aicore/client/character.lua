---Aicore multicharacter selection UI (MIT-clean, built from scratch).
---ox_lib menus + a preview camera while choosing. No per-frame loops:
---everything is event-driven.
---Enable with Config.characters.useMultichar. When disabled, the core falls
---back to the instant auto-login flow in client/main.lua.

if not Config.characters.useMultichar then return end

local previewCam

local function setupPreview()
    local loc = Config.characters.previewLocation
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(100) end

    SetEntityCoords(ped, loc.x, loc.y, loc.z, false, false, false, false)
    SetEntityHeading(ped, loc.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    previewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(previewCam, loc.x + 2.5, loc.y + 2.5, loc.z + 1.6)
    PointCamAtCoord(previewCam, loc.x, loc.y, loc.z + 0.4)
    RenderScriptCams(true, false, 0, true, true)

    DoScreenFadeIn(500)
end

local function teardownPreview()
    if previewCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
end

-- Once the player has spawned into the world, the selection UI is done.
AddEventHandler('aicore:playerSpawned', function()
    teardownPreview()
end)

local function createCharacterDialog()
    local input = lib.inputDialog('Create Character', {
        { type = 'input', label = 'First name', required = true, max = 30 },
        { type = 'input', label = 'Last name', required = true, max = 30 },
    })
    if not input then
        openCharacterMenu()
        return
    end
    local name = (input[1] .. ' ' .. input[2]):sub(1, 60)
    TriggerServerEvent('aicore:server:createCharacter', name)
end

local function deleteCharacterDialog(citizenid, name)
    local confirm = lib.alertDialog({
        header = 'Delete character?',
        content = ('Permanently delete **%s**? This cannot be undone.'):format(name),
        centered = true,
        cancel = true,
    })
    if confirm == 'confirm' then
        TriggerServerEvent('aicore:server:deleteCharacter', citizenid)
    else
        openCharacterMenu()
    end
end

local function openCharacterSubmenu(citizenid, name, index)
    lib.registerContext({
        id = 'aicore_multichar_char_' .. index,
        title = name,
        menu = 'aicore_multichar',
        options = {
            {
                title = 'Play',
                description = 'Enter the world as ' .. name,
                icon = 'play',
                onSelect = function()
                    TriggerServerEvent('aicore:server:selectCharacter', citizenid)
                end,
            },
            {
                title = 'Delete',
                description = 'Permanently delete this character',
                icon = 'trash',
                onSelect = function()
                    deleteCharacterDialog(citizenid, name)
                end,
            },
        },
    })
    lib.showContext('aicore_multichar_char_' .. index)
end

function openCharacterMenu()
    local characters = lib.callback.await('aicore:server:getCharacters', false) or {}
    local options = {}

    for i, char in ipairs(characters) do
        options[#options + 1] = {
            title = char.name or ('Character ' .. i),
            icon = 'user',
            arrow = true,
            onSelect = function()
                openCharacterSubmenu(char.citizenid, char.name or ('Character ' .. i), i)
            end,
        }
    end

    if #characters < Config.characters.maxCharacters then
        options[#options + 1] = {
            title = 'Create new character',
            description = ('%d of %d slots used'):format(#characters, Config.characters.maxCharacters),
            icon = 'plus',
            onSelect = createCharacterDialog,
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'No characters yet',
            description = 'Something went wrong loading your characters.',
            icon = 'triangle-exclamation',
            readOnly = true,
        }
    end

    lib.registerContext({
        id = 'aicore_multichar',
        title = 'Select Character',
        options = options,
        onExit = function()
            -- Reopen if the player closes the menu without choosing.
            -- The select/create/delete handlers replace the menu on success.
            if not LocalPlayer.state.isLoggedIn then
                SetTimeout(500, openCharacterMenu)
            end
        end,
    })
    lib.showContext('aicore_multichar')
end

-- Refresh the list after create/delete.
RegisterNetEvent('aicore:client:characterCreated', function(ok)
    if ok then
        lib.notify({ description = 'Character created.', type = 'success' })
    else
        lib.notify({ description = 'Could not create character.', type = 'error' })
    end
    openCharacterMenu()
end)

RegisterNetEvent('aicore:client:characterDeleted', function(ok)
    lib.notify({
        description = ok and 'Character deleted.' or 'Could not delete character.',
        type = ok and 'success' or 'error',
    })
    openCharacterMenu()
end)

-- Entry point: hide the player, set up the camera, show the menu.
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(1000)
    setupPreview()
    openCharacterMenu()
end)
