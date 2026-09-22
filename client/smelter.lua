local RSGCore = exports['rsg-core']:GetCoreObject()
local SpawnedProps = {}
local isBusy = false
local fx_group = "scr_dm_ftb"
local fx_name = "scr_mp_chest_spawn_smoke"
local fx_scale = 1.0

---------------------------------------------
-- helper: send ox_lib notification
---------------------------------------------
local NotifyIcons = {
    warning          = 'triangle-exclamation',
    cross            = 'circle-xmark',
    tick             = 'circle-check',
    leaderboard_gold = 'coins',
    awards_set_c_001 = 'box-open',
}

local NotifyTypes = {
    ERROR    = 'error',
    SUCCESS  = 'success',
    INFO     = 'info',
    TIP_GOLD = 'success',
}

local function Notify(title, description, icon, duration, template)
    lib.notify({
        title = title,
        description = description,
        type = NotifyTypes[template] or 'info',
        icon = NotifyIcons[icon] or icon,
        duration = duration or 5000,
        position = 'center-right',
    })
end

---------------------------------------------
-- spawn props
---------------------------------------------
Citizen.CreateThread(function()
    while true do
        Wait(150)

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local InRange = false

        for i = 1, #Config.Smelter.PlayerProps do
            local prop = vector3(Config.Smelter.PlayerProps[i].x, Config.Smelter.PlayerProps[i].y, Config.Smelter.PlayerProps[i].z)
            local dist = #(pos - prop)
            if dist >= 50.0 then goto continue end

            local hasSpawned = false
            InRange = true

            for z = 1, #SpawnedProps do
                local p = SpawnedProps[z]
                if p.id == Config.Smelter.PlayerProps[i].id then
                    hasSpawned = true
                end
            end

            if hasSpawned then goto continue end

            local modelHash = Config.Smelter.PlayerProps[i].hash
            local data = {}

            if not HasModelLoaded(modelHash) then
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do
                    Wait(1)
                end
            end

            data.id = Config.Smelter.PlayerProps[i].id
            data.obj = CreateObject(modelHash, Config.Smelter.PlayerProps[i].x, Config.Smelter.PlayerProps[i].y, Config.Smelter.PlayerProps[i].z - 1.2, false, false, false)
            SetEntityHeading(data.obj, Config.Smelter.PlayerProps[i].h)
            SetEntityAsMissionEntity(data.obj, true)
            PlaceObjectOnGroundProperly(data.obj)
            Wait(1000)
            FreezeEntityPosition(data.obj, true)
            SetModelAsNoLongerNeeded(data.obj)

            if Config.Smelter.EnableVegModifier then
                local veg_radius = 3.0
                local veg_Flags = 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128 + 256
                local veg_ModType = 1
                Citizen.InvokeNative(0xFA50F79257745E74, Config.Smelter.PlayerProps[i].x, Config.Smelter.PlayerProps[i].y, Config.Smelter.PlayerProps[i].z, veg_radius, veg_ModType, veg_Flags, 0)
            end

            SpawnedProps[#SpawnedProps + 1] = data
            hasSpawned = false

            -- create ox_target for the entity
            exports.ox_target:addLocalEntity(data.obj, {
                {
                    name = 'smelter_open_' .. data.id,
                    label = locale('smelter_open_smelting'),
                    icon = 'fa-solid fa-fire',
                    distance = 2.0,
                    onSelect = function()
                        TriggerEvent('rsg-goldclaim:smelter:client:openSmeltingMenu', { smelterid = data.id })
                    end,
                },
                {
                    name = 'smelter_pickup_' .. data.id,
                    label = locale('smelter_pickup_smelter'),
                    icon = 'fa-solid fa-box-open',
                    distance = 2.0,
                    onSelect = function()
                        TriggerEvent('rsg-goldclaim:smelter:client:pickupSmelter', { smelterid = data.id, entity = data.obj })
                    end,
                },
            })
            -- end of target

            ::continue::
        end

        if not InRange then
            Wait(100)
        end
    end
end)

---------------------------------------------
-- open smelting menu (NUI)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:client:openSmeltingMenu', function(data)
    local sortedRecipes = {}
    for k, v in pairs(Config.Smelter.Recipes) do
        table.insert(sortedRecipes, {
            key = k,
            name = v.name,
            ingredients = v.ingredients,
            crafttime = v.crafttime,
            receive = v.receive,
            category = v.category
        })
    end

    table.sort(sortedRecipes, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    local player = RSGCore.Functions.GetPlayerData()
    local inventory = {}
    for _, item in pairs(player.items) do
        inventory[item.name] = item.amount or 0
    end

    local craftingData = {}
    for _, recipe in ipairs(sortedRecipes) do
        table.insert(craftingData, {
            key = recipe.key,
            title = recipe.name,
            ingredients = recipe.ingredients,
            receive = recipe.receive,
            giveamount = 1,
            crafttime = recipe.crafttime,
            category = recipe.category
        })
    end

    SendNUIMessage({
        action = 'openCrafting',
        crafting = craftingData,
        inventory = inventory,
        lang = {
            categories = locale('smelter_label_categories'),
            craftable_items = locale('smelter_label_craftable_items'),
            item_details = locale('smelter_label_item_details'),
            required_items = locale('smelter_label_required_items'),
            craft = locale('smelter_label_craft'),
            close = locale('smelter_label_close'),
            missing_items = locale('smelter_label_missing_items'),
            crafting = locale('smelter_label_crafting'),
            in_progress = locale('smelter_label_in_progress'),
            cancel = locale('smelter_label_cancel'),
            needed = locale('smelter_label_needed'),
            you_have = locale('smelter_label_you_have'),
            select_item_to_view_details = locale('smelter_label_select_item')
        }
    })

    SetNuiFocus(true, true)
end)

---------------------------------------------
-- handle crafting request from NUI
-- the NUI only ever supplies a recipeKey + quantity; the authoritative
-- ingredients/output always come from Config.Smelter.Recipes (this is purely
-- for the client's own progress bar/UX - the server re-validates everything
-- again independently when finishcrafting fires)
---------------------------------------------
RegisterNUICallback('startCrafting', function(data, cb)
    local recipeKey = data.recipeKey
    local recipe = recipeKey and Config.Smelter.Recipes[recipeKey]
    if not recipe then
        cb({ success = false, error = 'Recipe not found' })
        return
    end

    local quantity = tonumber(data.giveamount) or 1
    if quantity < 1 then quantity = 1 end

    local multipliedIngredients = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        table.insert(multipliedIngredients, {
            item = ingredient.item,
            amount = (ingredient.amount or 1) * quantity
        })
    end

    RSGCore.Functions.TriggerCallback('rsg-goldclaim:smelter:server:checkingredients', function(hasRequired)
        if hasRequired then
            TriggerEvent('rsg-goldclaim:smelter:crafting', recipe.name, recipeKey, recipe.crafttime, recipe.receive, quantity)
            cb({ success = true })
        else
            local player = RSGCore.Functions.GetPlayerData()
            local inventory = {}
            for _, v in pairs(player.items) do
                inventory[v.name] = v.amount or 0
            end
            local missingItems = {}
            for _, ingredient in ipairs(multipliedIngredients) do
                local playerCount = inventory[ingredient.item] or 0
                if playerCount < ingredient.amount then
                    table.insert(missingItems, {
                        item = RSGCore.Shared.Items[ingredient.item] and RSGCore.Shared.Items[ingredient.item].label or ingredient.item,
                        have = playerCount,
                        required = ingredient.amount
                    })
                end
            end
            SendNUIMessage({
                action = 'showMissingItems',
                missingItems = missingItems
            })
            cb({ success = false })
        end
    end, multipliedIngredients)
end)

---------------------------------------------
-- handle quantity change from NUI
---------------------------------------------
RegisterNUICallback('quantityChanged', function(data, cb)
    local recipeKey = data.recipeKey
    local quantity = tonumber(data.quantity) or 1
    local recipe = Config.Smelter.Recipes[recipeKey]
    if not recipe then
        cb({ success = false, error = "Recipe not found" })
        return
    end

    local updatedIngredients = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        table.insert(updatedIngredients, {
            item = ingredient.item,
            amount = (ingredient.amount or 1) * quantity
        })
    end

    SendNUIMessage({
        action = 'updateIngredients',
        recipeKey = recipeKey,
        ingredients = updatedIngredients,
        quantity = quantity
    })
    cb({ success = true })
end)

---------------------------------------------
-- smelting progress bar
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:crafting', function(name, recipeKey, crafttime, receive, quantity)
    local recipe = Config.Smelter.Recipes[recipeKey]
    if not recipe then return end

    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'), crafttime, true, false, false, false)

    SendNUIMessage({
        action = 'startProgress',
        actionType = locale('smelter_label_crafting'),
        duration = crafttime
    })

    RSGCore.Functions.Progressbar('smelt', locale('smelter_progressbar_smelting') .. name, crafttime, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function() -- Done
        -- the server looks up the authoritative recipe from recipeKey itself
        TriggerServerEvent('rsg-goldclaim:smelter:server:finishcrafting', recipeKey, quantity)
        ClearPedTasks(ped)
    end, function() -- Cancel
        ClearPedTasks(ped)
    end)
end)

---------------------------------------------
-- cancel crafting from NUI
---------------------------------------------
RegisterNUICallback('cancelCrafting', function(data, cb)
    TriggerEvent('RSGCore:Client:CancelProgressbar')
    cb({})
end)

---------------------------------------------
-- close crafting from NUI
---------------------------------------------
RegisterNUICallback('closeCrafting', function(data, cb)
    SetNuiFocus(false, false)
    cb({})
end)

---------------------------------------------
-- pick up smelter (returns item to owner, custom confirm modal)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:client:pickupSmelter', function(data)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:smelter:server:checkOwnership', function(isOwner)
        if not isOwner then
            Notify(locale('smelter_not_owner'), nil, 'cross', 5000, 'ERROR')
            return
        end

        OpenInputDialog(locale('smelter_confirm_pickup'), {
            {
                label = locale('smelter_pickup_question'),
                description = locale('smelter_pickup_desc'),
                type = 'select',
                options = {
                    { value = 'yes', label = locale('smelter_yes') },
                    { value = 'no', label = locale('smelter_no') }
                },
                required = true
            },
        }, function(input)
            if not input then return end
            if input[1] == 'no' then return end

            lib.progressBar({
                duration = Config.Smelter.DestroyTime,
                position = 'bottom',
                useWhileDead = false,
                canCancel = false,
                disableControl = true,
                label = locale('smelter_picking_up'),
            })

            local stashcoords = GetEntityCoords(data.entity)
            local fxcoords = vector3(stashcoords.x, stashcoords.y, stashcoords.z)
            UseParticleFxAsset(fx_group)
            StartParticleFxNonLoopedAtCoord(fx_name, fxcoords, 0.0, 0.0, 0.0, fx_scale, false, false, false, true)
            TriggerServerEvent('rsg-goldclaim:smelter:server:pickupProp', data.smelterid)
        end)
    end, data.smelterid)
end)

---------------------------------------------
-- remove prop object
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:client:removePropObject')
AddEventHandler('rsg-goldclaim:smelter:client:removePropObject', function(prop)
    for i = 1, #SpawnedProps do
        local o = SpawnedProps[i]
        if o.id == prop then
            exports.ox_target:removeLocalEntity(o.obj)
            SetEntityAsMissionEntity(o.obj, false)
            FreezeEntityPosition(o.obj, false)
            DeleteObject(o.obj)
        end
    end
end)

---------------------------------------------
-- update props
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:client:updatePropData')
AddEventHandler('rsg-goldclaim:smelter:client:updatePropData', function(data)
    Config.Smelter.PlayerProps = data
end)

---------------------------------------------
-- place prop
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:client:placeNewProp')
AddEventHandler('rsg-goldclaim:smelter:client:placeNewProp', function(proptype, pHash, pos, heading)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:smelter:server:countprop', function(result)
        if result >= Config.Smelter.MaxSmelters then
            Notify(locale('smelter_max_smelters'), nil, 'cross', 7000, 'ERROR')
            TriggerServerEvent('rsg-goldclaim:smelter:server:returnItem')
            return
        end

        if Config.Smelter.RequireGoldClaim then
            RSGCore.Functions.TriggerCallback('rsg-goldclaim:smelter:server:checkGoldClaim', function(inClaim)
                if not inClaim then
                    Notify(locale('smelter_need_gold_claim'), nil, 'cross', 7000, 'ERROR')
                    TriggerServerEvent('rsg-goldclaim:smelter:server:returnItem')
                    return
                end
                DoPlaceSmelter(proptype, pHash, pos, heading)
            end, pos.x, pos.y, pos.z)
        else
            DoPlaceSmelter(proptype, pHash, pos, heading)
        end
    end, proptype)
end)

function DoPlaceSmelter(proptype, pHash, pos, heading)
    local ped = PlayerPedId()
    if CanPlacePropHere(pos) and not IsPedInAnyVehicle(ped, false) and not isBusy then
        isBusy = true
        local anim1 = `WORLD_HUMAN_CROUCH_INSPECT`
        FreezeEntityPosition(ped, true)
        TaskStartScenarioInPlace(ped, anim1, 0, true)
        Wait(10000)
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        TriggerServerEvent('rsg-goldclaim:smelter:server:newProp', proptype, pos, heading, pHash)
        isBusy = false
        return
    end
end

---------------------------------------------
-- check to see if prop can be placed here
---------------------------------------------
function CanPlacePropHere(pos)
    local canPlace = true
    for i = 1, #Config.Smelter.PlayerProps do
        local checkprops = vector3(Config.Smelter.PlayerProps[i].x, Config.Smelter.PlayerProps[i].y, Config.Smelter.PlayerProps[i].z)
        local dist = #(pos - checkprops)
        if dist < 1.3 then
            canPlace = false
        end
    end
    return canPlace
end

---------------------------------------------
-- clean up on resource stop
---------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for i = 1, #SpawnedProps do
        local props = SpawnedProps[i].obj
        exports.ox_target:removeLocalEntity(props)
        SetEntityAsMissionEntity(props, false)
        FreezeEntityPosition(props, false)
        DeleteObject(props)
    end
end)
