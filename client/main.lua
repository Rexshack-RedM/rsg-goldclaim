lib.locale()

local RSGCore = exports['rsg-core']:GetCoreObject()
local SpawnedProps = {}
local SpawnedOutputProps = {}
local ActiveZones = {}
local ActiveBlips = {}
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
-- helper: load anim dict
---------------------------------------------
local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local attempts = 0
    while not HasAnimDictLoaded(dict) and attempts < 200 do
        Wait(10)
        attempts = attempts + 1
    end
    return HasAnimDictLoaded(dict)
end

---------------------------------------------
-- helper: load model
---------------------------------------------
local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local attempts = 0
    while not HasModelLoaded(hash) and attempts < 100 do
        Wait(10)
        attempts = attempts + 1
    end
    return HasModelLoaded(hash)
end

---------------------------------------------
-- helper: get prop data by id
---------------------------------------------
local function GetPropDataById(propid)
    for i = 1, #Config.PlayerProps do
        if Config.PlayerProps[i].id == propid then
            return Config.PlayerProps[i]
        end
    end
    return nil
end

---------------------------------------------
-- spawn rocker props
---------------------------------------------
Citizen.CreateThread(function()
    while true do
        Wait(150)

        local pos = GetEntityCoords(cache.ped)
        local InRange = false

        for i = 1, #Config.PlayerProps do
            local prop = vector3(Config.PlayerProps[i].x, Config.PlayerProps[i].y, Config.PlayerProps[i].z)
            local dist = #(pos - prop)
            if dist >= 50.0 then goto continue end

            local hasSpawned = false
            InRange = true

            for z = 1, #SpawnedProps do
                if SpawnedProps[z].id == Config.PlayerProps[i].id then
                    hasSpawned = true
                end
            end

            if hasSpawned then goto continue end

            local modelHash = Config.PlayerProps[i].hash
            local data = {}

            if not HasModelLoaded(modelHash) then
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do
                    Wait(1)
                end
            end

            data.id = Config.PlayerProps[i].id
            data.obj = CreateObject(modelHash, Config.PlayerProps[i].x, Config.PlayerProps[i].y, Config.PlayerProps[i].z - 1.2, false, false, false)
            SetEntityHeading(data.obj, Config.PlayerProps[i].h)
            SetEntityAsMissionEntity(data.obj, true)
            PlaceObjectOnGroundProperly(data.obj)
            Wait(1000)
            FreezeEntityPosition(data.obj, true)
            SetModelAsNoLongerNeeded(data.obj)

            -- vegetation modifier
            if Config.EnableVegModifier then
                local veg_radius = 3.0
                local veg_Flags = 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128 + 256
                local veg_ModType = 1
                Citizen.InvokeNative(0xFA50F79257745E74, Config.PlayerProps[i].x, Config.PlayerProps[i].y, Config.PlayerProps[i].z, veg_radius, veg_ModType, veg_Flags, 0)
            end

            -- store reference
            data.licensed = Config.PlayerProps[i].licensed or 0
            data.claimname = Config.PlayerProps[i].claimname or ''
            data.citizenid = Config.PlayerProps[i].builder or ''
            SpawnedProps[#SpawnedProps + 1] = data

            -- create ox_target for the rocker entity
            SetupRockerTarget(data)

            ::continue::
        end

        if not InRange then
            Wait(5000)
        end
    end
end)

---------------------------------------------
-- setup ox_target on rocker
---------------------------------------------
function SetupRockerTarget(data)
    local options = {
        {
            name = 'rocker_menu_' .. data.id,
            label = locale('rocker_target_menu'),
            icon = 'fa-solid fa-bars',
            distance = 3.0,
            onSelect = function()
                TriggerEvent('rsg-goldclaim:rocker:client:mainmenu', data.id)
            end,
        },
        {
            name = 'add_paydirt_' .. data.id,
            label = locale('rocker_target_add_paydirt'),
            icon = 'fa-solid fa-hill-rockslide',
            distance = 3.0,
            onSelect = function()
                TriggerEvent('rsg-goldclaim:rocker:client:addpaydirt', data.id)
            end,
        },
        {
            name = 'add_water_' .. data.id,
            label = locale('rocker_target_add_water'),
            icon = 'fa-solid fa-droplet',
            distance = 3.0,
            onSelect = function()
                TriggerEvent('rsg-goldclaim:rocker:client:addwater', data.id)
            end,
        },
    }

    -- LEO destroy option for unlicensed claims
    if data.licensed == 0 then
        local PlayerData = RSGCore.Functions.GetPlayerData()
        if PlayerData and PlayerData.job and PlayerData.job.type == 'leo' then
            options[#options + 1] = {
                name = 'destroy_illegal_' .. data.id,
                label = locale('rocker_destroy_illegal'),
                icon = 'fa-solid fa-gavel',
                distance = 3.0,
                onSelect = function()
                    TriggerEvent('rsg-goldclaim:rocker:client:destroyillegal', data.id, data.obj)
                end,
            }
        end
    end

    exports.ox_target:addLocalEntity(data.obj, options)
end

---------------------------------------------
-- setup claim zone (licensed claims only)
---------------------------------------------
function SetupClaimZone(propData)
    local zoneId = 'goldclaim_' .. propData.id

    -- stop existing zone thread if any
    if ActiveZones[zoneId] then
        ActiveZones[zoneId].active = false
        ActiveZones[zoneId] = nil
    end

    -- capture values for the thread
    local claimname = propData.claimname or 'Gold Claim'
    local zoneCoords = vector3(propData.x, propData.y, propData.z)
    local zoneRadius = Config.ClaimZoneRadius
    local propId = propData.id

    -- zone state tracker
    local zoneData = { active = true, inside = false }
    ActiveZones[zoneId] = zoneData

    -- distance check thread (works for ALL players, including owner)
    Citizen.CreateThread(function()
        while zoneData.active do
            Wait(500)
            local playerPos = GetEntityCoords(cache.ped)
            local dist = #(playerPos - zoneCoords)

            if dist <= zoneRadius and not zoneData.inside then
                -- entered zone
                zoneData.inside = true
                lib.notify({
                    title = claimname,
                    description = locale('rocker_entering_claim_desc', claimname),
                    type = 'info',
                    icon = 'coins',
                    position = 'center-left',
                    duration = 7000,
                })
            elseif dist > zoneRadius and zoneData.inside then
                -- left zone
                zoneData.inside = false
                lib.notify({
                    title = claimname,
                    description = locale('rocker_leaving_claim_desc', claimname),
                    type = 'info',
                    icon = 'coins',
                    position = 'center-left',
                    duration = 5000,
                })
            end
        end
    end)

    -- create blip
    if ActiveBlips[propId] then
        RemoveBlip(ActiveBlips[propId])
        ActiveBlips[propId] = nil
    end

    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, zoneCoords)
    SetBlipSprite(blip, joaat(Config.ClaimBlip.blipSprite), true)
    SetBlipScale(blip, Config.ClaimBlip.blipScale)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, claimname)
    Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(Config.ClaimBlip.blipColour))
    ActiveBlips[propId] = blip
end

---------------------------------------------
-- main menu (custom NUI context menu)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:mainmenu', function(rockerid)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:getrockerdata', function(result)
        if not result then return end

        local quality = result.quality
        local licensed = result.licensed
        local claimname = result.claimname or ''
        local citizenid = result.citizenid
        local owner = result.owner
        local water = result.water
        local paydirt = result.paydirt

        local PlayerData = RSGCore.Functions.GetPlayerData()
        local isOwner = PlayerData.citizenid == citizenid
        local isLeo = PlayerData.job and PlayerData.job.type == 'leo'

        local menuOptions = {
            {
                title = locale('rocker_equipment_info'),
                icon = 'fa-solid fa-circle-info',
                event = 'rsg-goldclaim:rocker:client:checkrocker',
                args = { rockerid = rockerid },
                arrow = true,
            },
            {
                title = locale('rocker_start_processing'),
                icon = 'fa-solid fa-cogs',
                event = 'rsg-goldclaim:rocker:client:startprocessing',
                args = { rockerid = rockerid },
            },
            {
                title = locale('rocker_repair_equipment'),
                icon = 'fa-solid fa-screwdriver-wrench',
                event = 'rsg-goldclaim:rocker:client:repairrocker',
                args = { rockerid = rockerid },
            },
        }

        -- rename option (licensed + owner only)
        if licensed == 1 and isOwner then
            menuOptions[#menuOptions + 1] = {
                title = locale('rocker_rename_claim'),
                icon = 'fa-solid fa-pen',
                event = 'rsg-goldclaim:rocker:client:renameclaim',
                args = { rockerid = rockerid },
            }
        end

        -- pack up (owner only)
        if isOwner then
            menuOptions[#menuOptions + 1] = {
                title = locale('rocker_packup_equipment'),
                icon = 'fa-solid fa-box-open',
                event = 'rsg-goldclaim:rocker:client:packuprocker',
                args = { rockerid = rockerid },
            }
        end

        -- LEO destroy (unlicensed only)
        if licensed == 0 and isLeo then
            menuOptions[#menuOptions + 1] = {
                title = locale('rocker_destroy_illegal'),
                icon = 'fa-solid fa-gavel',
                event = 'rsg-goldclaim:rocker:client:destroyillegal',
                args = { rockerid = rockerid },
            }
        end

        OpenContext({
            id = 'goldclaim_main_menu',
            title = locale('rocker_menu'),
            position = 'top-right',
            options = menuOptions,
        })
        ShowContext('goldclaim_main_menu')

    end, rockerid)
end)

---------------------------------------------
-- equipment info
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:checkrocker', function(data)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:getrockerdata', function(result)
        if not result then return end

        local statusText = result.licensed == 1 and locale('rocker_info_licensed') or locale('rocker_info_unlicensed')

        local options = {
            {
                title = locale('rocker_info_id', result.propid),
                icon = 'fa-solid fa-fingerprint',
            },
            {
                title = locale('rocker_info_owner', result.owner, result.citizenid),
                icon = 'fa-solid fa-user',
            },
            {
                title = locale('rocker_info_condition', result.quality),
                progress = result.quality,
                colorScheme = 'green',
                icon = 'fa-solid fa-screwdriver-wrench',
            },
            {
                title = locale('rocker_info_water', result.water, Config.MaxWater),
                progress = (result.water / Config.MaxWater) * 100,
                colorScheme = 'blue',
                icon = 'fa-solid fa-droplet',
            },
            {
                title = locale('rocker_info_paydirt', result.paydirt, Config.MaxPaydirt),
                progress = (result.paydirt / Config.MaxPaydirt) * 100,
                colorScheme = 'orange',
                icon = 'fa-solid fa-hill-rockslide',
            },
            {
                title = locale('rocker_info_claim', result.claimname or 'N/A', statusText),
                icon = 'fa-solid fa-scroll',
            },
        }

        OpenContext({
            id = 'goldclaim_info',
            title = locale('rocker_info_title'),
            menu = 'goldclaim_main_menu',
            onBack = function() end,
            options = options,
        })
        ShowContext('goldclaim_info')

    end, data.rockerid)
end)

---------------------------------------------
-- add paydirt to rocker
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:addpaydirt', function(rockerid)
    if isBusy then
        Notify(locale('rocker_processing_busy'), nil, 'cross', 3000, 'ERROR')
        return
    end

    local hasItem = RSGCore.Functions.HasItem('paydirt', 1)
    if not hasItem then
        Notify(locale('rocker_no_paydirt'), nil, 'cross', 5000, 'ERROR')
        return
    end

    isBusy = true
    LocalPlayer.state:set("inv_busy", true, true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    local anim = Config.Anims.crouch_inspect
    TaskStartScenarioInPlace(ped, anim, 0, true)

    if lib.progressBar({
        duration = Config.AddPaydirtTime,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_adding_paydirt'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        TriggerServerEvent('rsg-goldclaim:rocker:server:addpaydirt', rockerid)
        Notify(locale('rocker_paydirt_added'), nil, 'tick', 3000, 'SUCCESS')
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    LocalPlayer.state:set("inv_busy", false, true)
    isBusy = false
end)

---------------------------------------------
-- add water to rocker (requires fullbucket)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:addwater', function(rockerid)
    if isBusy then
        Notify(locale('rocker_processing_busy'), nil, 'cross', 3000, 'ERROR')
        return
    end

    local hasItem = RSGCore.Functions.HasItem('fullbucket', 1)
    if not hasItem then
        Notify(locale('rocker_no_fullbucket'), nil, 'cross', 5000, 'ERROR')
        return
    end

    isBusy = true
    LocalPlayer.state:set("inv_busy", true, true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    local anim = Config.Anims.crouch_inspect
    TaskStartScenarioInPlace(ped, anim, 0, true)

    if lib.progressBar({
        duration = Config.AddWaterTime,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_adding_water'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        TriggerServerEvent('rsg-goldclaim:rocker:server:addwater', rockerid)
        Notify(locale('rocker_water_added'), nil, 'tick', 3000, 'SUCCESS')
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    LocalPlayer.state:set("inv_busy", false, true)
    isBusy = false
end)

---------------------------------------------
-- start processing (async - player is free to move)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:startprocessing', function(data)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:getrockerdata', function(result)
        if not result then return end

        if result.water <= 0 then
            Notify(locale('rocker_processing_no_water'), nil, 'cross', 5000, 'ERROR')
            return
        end

        if result.paydirt <= 0 then
            Notify(locale('rocker_processing_no_paydirt'), nil, 'cross', 5000, 'ERROR')
            return
        end

        -- tell server to start processing (server handles the loop)
        local cycles = math.min(result.water, result.paydirt)
        TriggerServerEvent('rsg-goldclaim:rocker:server:processrocker', data.rockerid)
        Notify(locale('rocker_processing_started'), locale('rocker_processing_will_run', cycles), 'leaderboard_gold', 5000, 'INFO')

    end, data.rockerid)
end)

---------------------------------------------
-- spawn output prop (triggered by server)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:spawnoutputprop', function(rockerid, resultType)
    local propData = GetPropDataById(rockerid)
    if not propData then return end

    local rockerPos = vector3(propData.x, propData.y, propData.z)

    -- calculate offset position to the side of the rocker
    local heading = math.rad(propData.h or 0)
    local offsetX = rockerPos.x + (Config.PropSpawnOffset * math.cos(heading + math.pi / 2))
    local offsetY = rockerPos.y + (Config.PropSpawnOffset * math.sin(heading + math.pi / 2))
    local spawnPos = vector3(offsetX, offsetY, rockerPos.z)

    local propHash, targetLabel, targetEvent

    if resultType == 'gold' then
        propHash = Config.GoldProp
        targetLabel = locale('rocker_target_pickup_gold')
        targetEvent = 'rsg-goldclaim:rocker:client:pickupgold'
        Notify(locale('rocker_processing_gold_title'), locale('rocker_processing_gold_desc'), 'leaderboard_gold', 5000, 'SUCCESS')
    else
        propHash = Config.PaydirtProp
        targetLabel = locale('rocker_target_pickup_paydirt')
        targetEvent = 'rsg-goldclaim:rocker:client:pickuppaydirt'
        Notify(locale('rocker_processing_paydirt_title'), locale('rocker_processing_paydirt_desc'), 'awards_set_c_001', 5000, 'INFO')
    end

    if not LoadModel(propHash) then
        if Config.Debug then print('[rsg-goldclaim] Failed to load output prop model') end
        return
    end

    local obj = CreateObject(propHash, spawnPos.x, spawnPos.y, spawnPos.z, false, true, false)
    PlaceObjectOnGroundProperly(obj)
    Wait(300)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(propHash)

    -- store reference
    local outputId = rockerid .. '_' .. GetGameTimer()
    SpawnedOutputProps[outputId] = obj

    -- add ox_target to pick up
    exports.ox_target:addLocalEntity(obj, {
        {
            name = 'pickup_' .. outputId,
            label = targetLabel,
            icon = 'fa-solid fa-hand',
            distance = 3.0,
            onSelect = function()
                TriggerEvent(targetEvent, outputId, rockerid)
            end,
        },
    })
end)

---------------------------------------------
-- pick up gold prop
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:pickupgold', function(outputId, rockerid)
    if isBusy then return end
    isBusy = true

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, Config.Anims.crouch_inspect, 0, true)

    if lib.progressBar({
        duration = 3000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_picking_up'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)

        -- delete the prop
        local obj = SpawnedOutputProps[outputId]
        if obj and DoesEntityExist(obj) then
            exports.ox_target:removeLocalEntity(obj)
            DeleteObject(obj)
        end
        SpawnedOutputProps[outputId] = nil

        -- server gives random nugget and sends back the result
        TriggerServerEvent('rsg-goldclaim:rocker:server:pickupgold', rockerid)
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    isBusy = false
end)

---------------------------------------------
-- gold pickup result notification
---------------------------------------------
local NuggetLabelKeys = {
    smallnugget  = 'rocker_nugget_small',
    mediumnugget = 'rocker_nugget_medium',
    largenugget  = 'rocker_nugget_large',
}

RegisterNetEvent('rsg-goldclaim:rocker:client:goldpickupresult', function(nuggetType, amount)
    local label = NuggetLabelKeys[nuggetType] and locale(NuggetLabelKeys[nuggetType]) or nuggetType
    Notify(
        locale('rocker_gold_pickedup_title'),
        locale('rocker_gold_pickedup_desc', amount, label),
        'leaderboard_gold',
        7000,
        'TIP_GOLD'
    )
end)

---------------------------------------------
-- pick up paydirt prop
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:pickuppaydirt', function(outputId, rockerid)
    if isBusy then return end
    isBusy = true

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, Config.Anims.crouch_inspect, 0, true)

    if lib.progressBar({
        duration = 3000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_picking_up'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)

        local obj = SpawnedOutputProps[outputId]
        if obj and DoesEntityExist(obj) then
            exports.ox_target:removeLocalEntity(obj)
            DeleteObject(obj)
        end
        SpawnedOutputProps[outputId] = nil

        TriggerServerEvent('rsg-goldclaim:rocker:server:pickuppaydirt', rockerid)
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    isBusy = false
end)

---------------------------------------------
-- repair rocker (5x wood)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:repairrocker', function(data)
    if isBusy then return end

    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:getrockerdata', function(result)
        if not result then return end

        if result.quality >= 100 then
            Notify(locale('rocker_repair_not_needed'), nil, 'warning', 5000, 'INFO')
            return
        end

        local hasWood = RSGCore.Functions.HasItem('wood', Config.RepairWoodAmount)
        if not hasWood then
            Notify(locale('rocker_not_enough_wood'), nil, 'cross', 5000, 'ERROR')
            return
        end

        isBusy = true
        LocalPlayer.state:set("inv_busy", true, true)

        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        TaskStartScenarioInPlace(ped, Config.Anims.crouch_inspect, 0, true)

        if lib.progressBar({
            duration = Config.RepairTime,
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            label = locale('rocker_repairing'),
        }) then
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, false)
            TriggerServerEvent('rsg-goldclaim:rocker:server:repairrocker', data.rockerid)
        else
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, false)
        end

        LocalPlayer.state:set("inv_busy", false, true)
        isBusy = false

    end, data.rockerid)
end)

---------------------------------------------
-- rename claim (custom modal)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:renameclaim', function(data)
    OpenInputDialog(locale('rocker_rename_title'), {
        {
            label = locale('rocker_rename_label'),
            description = locale('rocker_rename_desc'),
            type = 'input',
            icon = 'fa-solid fa-pen',
            required = true,
        },
    }, function(input)
        if not input or not input[1] then return end

        TriggerServerEvent('rsg-goldclaim:rocker:server:renameclaim', data.rockerid, input[1])
        Notify(locale('rocker_claim_renamed'), input[1], 'tick', 5000, 'SUCCESS')
    end)
end)

---------------------------------------------
-- pack up rocker
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:packuprocker', function(data)
    if isBusy then return end

    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:getrockerdata', function(result)
        if not result then return end

        if result.quality ~= 100 then
            Notify(locale('rocker_needs_repair'), nil, 'cross', 5000, 'ERROR')
            return
        end

        isBusy = true
        LocalPlayer.state:set("inv_busy", true, true)

        local ped = PlayerPedId()
        FreezeEntityPosition(ped, true)
        TaskStartScenarioInPlace(ped, Config.Anims.crouch_inspect, 0, true)

        if lib.progressBar({
            duration = Config.CollectGoldTime,
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            label = locale('rocker_packing_up'),
        }) then
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, false)

            -- smoke effect
            for _, sp in ipairs(SpawnedProps) do
                if sp.id == data.rockerid then
                    local propcoords = GetEntityCoords(sp.obj)
                    UseParticleFxAsset(fx_group)
                    StartParticleFxNonLoopedAtCoord(fx_name, propcoords.x, propcoords.y, propcoords.z, 0.0, 0.0, 0.0, fx_scale, false, false, false, true)
                    break
                end
            end

            TriggerServerEvent('rsg-goldclaim:rocker:server:destroyProp', data.rockerid)
        else
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, false)
        end

        LocalPlayer.state:set("inv_busy", false, true)
        isBusy = false

    end, data.rockerid)
end)

---------------------------------------------
-- LEO destroy illegal claim
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:destroyillegal', function(rockerid, entity)
    if isBusy then return end

    -- support both arg styles (from target vs menu)
    if type(rockerid) == 'table' then
        entity = nil
        rockerid = rockerid.rockerid
    end

    isBusy = true
    LocalPlayer.state:set("inv_busy", true, true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, Config.Anims.crouch_inspect, 0, true)

    if lib.progressBar({
        duration = 10000,
        position = 'bottom',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_destroying_claim'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)

        -- smoke effect
        for _, sp in ipairs(SpawnedProps) do
            if sp.id == rockerid then
                local propcoords = GetEntityCoords(sp.obj)
                UseParticleFxAsset(fx_group)
                StartParticleFxNonLoopedAtCoord(fx_name, propcoords.x, propcoords.y, propcoords.z, 0.0, 0.0, 0.0, fx_scale, false, false, false, true)
                break
            end
        end

        TriggerServerEvent('rsg-goldclaim:rocker:server:leodestroy', rockerid)
        Notify(locale('rocker_claim_destroyed'), locale('rocker_evidence_collected'), 'tick', 5000, 'SUCCESS')
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    LocalPlayer.state:set("inv_busy", false, true)
    isBusy = false
end)

---------------------------------------------
-- place gold rocker
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:placeNewProp')
AddEventHandler('rsg-goldclaim:rocker:client:placeNewProp', function(proptype, pHash, item, pos, heading)
    RSGCore.Functions.TriggerCallback('rsg-goldclaim:rocker:server:countprop', function(result)
        local inwater = IsEntityInWater(cache.ped)

        if inwater then
            Notify(locale('rocker_cant_place_here'), nil, 'cross', 5000, 'ERROR')
            return
        end

        if proptype == 'goldrocker' and result >= Config.MaxGoldRockers then
            Notify(locale('rocker_max_equipment'), nil, 'cross', 5000, 'ERROR')
            return
        end

        if not isBusy then
            isBusy = true
            LocalPlayer.state:set("inv_busy", true, true)

            local anim1 = `WORLD_HUMAN_CROUCH_INSPECT`
            FreezeEntityPosition(cache.ped, true)
            TaskStartScenarioInPlace(cache.ped, anim1, 0, true)
            Wait(10000)
            ClearPedTasks(cache.ped)
            FreezeEntityPosition(cache.ped, false)

            TriggerServerEvent('rsg-goldclaim:rocker:server:newProp', proptype, pos, heading, pHash)

            LocalPlayer.state:set("inv_busy", false, true)
            isBusy = false
        else
            Notify(locale('rocker_processing_busy'), nil, 'cross', 5000, 'ERROR')
        end

    end, proptype)
end)

---------------------------------------------
-- update props from server
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:updatePropData')
AddEventHandler('rsg-goldclaim:rocker:client:updatePropData', function(data)
    Config.PlayerProps = data
    -- rebuild zones and blips for all licensed claims
    SyncClaimZones()
end)

---------------------------------------------
-- sync claim zones & blips from prop data
-- runs on every prop data update so zones
-- persist across restarts for all players
---------------------------------------------
function SyncClaimZones()
    -- track which zones should exist
    local activeIds = {}

    for i = 1, #Config.PlayerProps do
        local p = Config.PlayerProps[i]
        local zoneId = 'goldclaim_' .. p.id
        local isLicensed = (p.licensed == 1 or p.licensed == true)

        if Config.Debug then print('[rsg-goldclaim] SyncZone check: id=' .. tostring(p.id) .. ' licensed=' .. tostring(p.licensed) .. '(' .. type(p.licensed) .. ') claimname=' .. tostring(p.claimname)) end

        if isLicensed and p.claimname and p.claimname ~= '' then
            activeIds[zoneId] = true

            -- only create if not already running
            if not ActiveZones[zoneId] then
                if Config.Debug then print('[rsg-goldclaim] Creating zone + blip for claim: ' .. p.claimname) end
                SetupClaimZone(p)
            end
        end
    end

    -- remove zones/blips for claims that no longer exist
    for zoneId, zoneData in pairs(ActiveZones) do
        if not activeIds[zoneId] then
            zoneData.active = false
            ActiveZones[zoneId] = nil

            -- extract propid from zoneId
            local propId = tonumber(zoneId:gsub('goldclaim_', ''))
            if propId and ActiveBlips[propId] then
                RemoveBlip(ActiveBlips[propId])
                ActiveBlips[propId] = nil
            end
        end
    end
end

---------------------------------------------
-- remove prop object
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:removePropObject')
AddEventHandler('rsg-goldclaim:rocker:client:removePropObject', function(prop)
    -- remove target, blip, zone
    for i = 1, #SpawnedProps do
        local o = SpawnedProps[i]
        if o.id == prop then
            if DoesEntityExist(o.obj) then
                exports.ox_target:removeLocalEntity(o.obj)
                SetEntityAsMissionEntity(o.obj, false)
                FreezeEntityPosition(o.obj, false)
                DeleteObject(o.obj)
            end
            table.remove(SpawnedProps, i)
            break
        end
    end

    -- stop zone thread
    local zoneId = 'goldclaim_' .. prop
    if ActiveZones[zoneId] then
        ActiveZones[zoneId].active = false
        ActiveZones[zoneId] = nil
    end

    -- remove blip
    if ActiveBlips[prop] then
        RemoveBlip(ActiveBlips[prop])
        ActiveBlips[prop] = nil
    end
end)

---------------------------------------------
-- refresh zone/blip after rename
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:refreshclaim', function(rockerid, newname)
    -- update local SpawnedProps data
    for _, sp in ipairs(SpawnedProps) do
        if sp.id == rockerid then
            sp.claimname = newname
            break
        end
    end
    -- update PlayerProps
    for i = 1, #Config.PlayerProps do
        if Config.PlayerProps[i].id == rockerid then
            Config.PlayerProps[i].claimname = newname
            break
        end
    end
    -- kill old zone/blip and recreate with new name
    local zoneId = 'goldclaim_' .. rockerid
    if ActiveZones[zoneId] then
        ActiveZones[zoneId].active = false
        ActiveZones[zoneId] = nil
    end
    if ActiveBlips[rockerid] then
        RemoveBlip(ActiveBlips[rockerid])
        ActiveBlips[rockerid] = nil
    end
    local propData = GetPropDataById(rockerid)
    if propData and propData.licensed == 1 then
        propData.claimname = newname
        SetupClaimZone(propData)
    end
end)

---------------------------------------------
-- processing complete notification
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:processingcomplete', function(propid)
    Notify(locale('rocker_processing_complete_title'), locale('rocker_processing_complete_desc'), 'leaderboard_gold', 7000, 'INFO')
end)

---------------------------------------------
-- use shovel (dig paydirt in water)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:useshovel', function()
    if isBusy then
        Notify(locale('rocker_processing_busy'), nil, 'cross', 3000, 'ERROR')
        return
    end

    local inwater = IsEntityInWater(cache.ped)
    if not inwater then
        Notify(locale('rocker_not_in_water'), nil, 'cross', 5000, 'ERROR')
        return
    end

    isBusy = true
    LocalPlayer.state:set("inv_busy", true, true)

    local ped = PlayerPedId()
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    FreezeEntityPosition(ped, true)

    -- attach shovel prop
    local shovelModel = GetHashKey(Config.ShovelProp.model)
    RequestModel(shovelModel)
    while not HasModelLoaded(shovelModel) do Wait(100) end

    local coords = GetEntityCoords(ped)
    local shovelObject = CreateObject(shovelModel, coords.x, coords.y, coords.z, true, true, true)
    local boneIndex = GetEntityBoneIndexByName(ped, Config.ShovelProp.bone)
    local offset = Config.ShovelProp.offset
    AttachEntityToEntity(shovelObject, ped, boneIndex, offset[1], offset[2], offset[3], offset[4], offset[5], offset[6], false, false, false, false, 2, true)

    -- dig animation
    local animData = Config.Anims.dig
    LoadAnimDict(animData.dict)
    TaskPlayAnim(ped, animData.dict, animData.name, 1.0, 1.0, -1, 1, 0, false, false, false)

    if lib.progressBar({
        duration = Config.ShovelDigTime,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_digging_paydirt'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        if DoesEntityExist(shovelObject) then
            DeleteObject(shovelObject)
        end
        SetModelAsNoLongerNeeded(shovelModel)
        TriggerServerEvent('rsg-goldclaim:rocker:server:digpaydirt')
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        if DoesEntityExist(shovelObject) then
            DeleteObject(shovelObject)
        end
        SetModelAsNoLongerNeeded(shovelModel)
    end

    LocalPlayer.state:set("inv_busy", false, true)
    isBusy = false
end)

---------------------------------------------
-- use bucket (fill with water)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:usebucket', function()
    if isBusy then
        Notify(locale('rocker_processing_busy'), nil, 'cross', 3000, 'ERROR')
        return
    end

    local inwater = IsEntityInWater(cache.ped)
    if not inwater then
        Notify(locale('rocker_not_in_water'), nil, 'cross', 5000, 'ERROR')
        return
    end

    isBusy = true
    LocalPlayer.state:set("inv_busy", true, true)

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)

    -- use scenario (reliable, no anim dict needed)
    TaskStartScenarioInPlace(ped, `WORLD_HUMAN_CROUCH_INSPECT`, 0, true)

    if lib.progressBar({
        duration = Config.BucketFillTime,
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        label = locale('rocker_filling_bucket'),
    }) then
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
        TriggerServerEvent('rsg-goldclaim:rocker:server:fillbucket')
    else
        ClearPedTasks(ped)
        FreezeEntityPosition(ped, false)
    end

    LocalPlayer.state:set("inv_busy", false, true)
    isBusy = false
end)

---------------------------------------------
-- clean up on resource stop
---------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for i = 1, #SpawnedProps do
        local props = SpawnedProps[i].obj
        if DoesEntityExist(props) then
            exports.ox_target:removeLocalEntity(props)
            SetEntityAsMissionEntity(props, false)
            FreezeEntityPosition(props, false)
            DeleteObject(props)
        end
    end

    for _, obj in pairs(SpawnedOutputProps) do
        if DoesEntityExist(obj) then
            exports.ox_target:removeLocalEntity(obj)
            DeleteObject(obj)
        end
    end

    for _, zone in pairs(ActiveZones) do
        zone.active = false
    end

    for _, blip in pairs(ActiveBlips) do
        RemoveBlip(blip)
    end
end)
