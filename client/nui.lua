-----------------------------------------------------------------------------------------------
-- shared NUI helper API
-- Provides a custom leather & gold themed context-menu + modal system used to replace
-- ox_lib's lib.registerContext/showContext/inputDialog throughout rsg-goldclaim, plus the
-- crafting panel wiring used by the smelter subsystem (client/smelter.lua).
-----------------------------------------------------------------------------------------------

local registeredContexts = {}
local contextStack = {}
local pendingModalCallback = nil

-----------------------------------------------------------------------------------------------
-- context menus (mirrors ox_lib's lib.registerContext / lib.showContext shape)
-----------------------------------------------------------------------------------------------

--- def = { id, title, subtitle?, position?, menu?, onBack?, options = { { title, description?, icon?, event?, args?, arrow?, disabled?, progress?, colorScheme? }, ... } }
function OpenContext(def)
    if not def or not def.id then return end
    registeredContexts[def.id] = def
end

local function renderContext(id)
    local def = registeredContexts[id]
    if not def then return end

    SendNUIMessage({
        action = 'openContext',
        id = id,
        title = def.title,
        subtitle = def.subtitle,
        canGoBack = #contextStack > 1,
        options = def.options or {},
    })
end

function ShowContext(id)
    local def = registeredContexts[id]
    if not def then return end

    if def.menu then
        table.insert(contextStack, id)
    else
        contextStack = { id }
    end

    renderContext(id)
    SetNuiFocus(true, true)
end

function HideContext()
    contextStack = {}
    SendNUIMessage({ action = 'closeContext' })
    SetNuiFocus(false, false)
end

RegisterNUICallback('contextSelect', function(data, cb)
    local id = contextStack[#contextStack]
    local def = id and registeredContexts[id]
    local option = def and def.options and def.options[(data.index or 0) + 1]

    if option and option.event and not option.disabled then
        TriggerEvent(option.event, option.args)
    end

    cb({})
end)

RegisterNUICallback('contextBack', function(data, cb)
    if #contextStack > 1 then
        local closingId = table.remove(contextStack)
        local closingDef = registeredContexts[closingId]
        if closingDef and closingDef.onBack then closingDef.onBack() end
        renderContext(contextStack[#contextStack])
    else
        HideContext()
    end

    cb({})
end)

RegisterNUICallback('contextClose', function(data, cb)
    HideContext()
    cb({})
end)

-----------------------------------------------------------------------------------------------
-- modal / input dialog (callback based -- NUI is async, unlike ox_lib's coroutine-based
-- lib.inputDialog, so callers pass a callback instead of receiving a direct return value)
-----------------------------------------------------------------------------------------------

--- fields = { { label, description?, type = 'input'|'select', options?, icon?, required?, default? }, ... }
--- callback(values | nil) -- values is an array matching the fields order, nil if cancelled
function OpenInputDialog(title, fields, callback)
    pendingModalCallback = callback

    SendNUIMessage({
        action = 'openModal',
        title = title,
        fields = fields,
    })
    SetNuiFocus(true, true)
end

--- simple yes/no confirmation modal
--- callback(bool)
function OpenConfirmDialog(title, description, callback)
    OpenInputDialog(title, {
        {
            label = description,
            type = 'confirm',
        },
    }, function(values)
        if not values then
            callback(false)
            return
        end
        callback(values[1] == 'yes')
    end)
end

--- simple alert modal with just a message + close button (used for missing-items lists etc.)
function OpenAlertDialog(title, lines)
    SendNUIMessage({
        action = 'openAlert',
        title = title,
        lines = lines or {},
    })
    SetNuiFocus(true, true)
end

RegisterNUICallback('modalSubmit', function(data, cb)
    SetNuiFocus(false, false)
    local callback = pendingModalCallback
    pendingModalCallback = nil
    if callback then callback(data.values) end
    cb({})
end)

RegisterNUICallback('modalCancel', function(data, cb)
    SetNuiFocus(false, false)
    local callback = pendingModalCallback
    pendingModalCallback = nil
    if callback then callback(nil) end
    cb({})
end)

RegisterNUICallback('alertClose', function(data, cb)
    SetNuiFocus(false, false)
    cb({})
end)

-----------------------------------------------------------------------------------------------
-- misc
-----------------------------------------------------------------------------------------------

RegisterNUICallback('closeAll', function(data, cb)
    contextStack = {}
    pendingModalCallback = nil
    SetNuiFocus(false, false)
    cb({})
end)
