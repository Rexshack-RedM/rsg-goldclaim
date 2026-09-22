local RSGCore = exports['rsg-core']:GetCoreObject()
local SpawnedGoldAgentBlips = {}

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

-----------------------------------------------------------------
-- blips
-----------------------------------------------------------------
Citizen.CreateThread(function()
    for _, v in pairs(Config.GoldAgentLocations) do
        if v.showblip == true then
            local GoldAgentBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v.coords)
            SetBlipSprite(GoldAgentBlip, joaat(Config.GoldAgentBlip.blipSprite), true)
            SetBlipScale(GoldAgentBlip, Config.GoldAgentBlip.blipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, GoldAgentBlip, Config.GoldAgentBlip.blipName)
            table.insert(SpawnedGoldAgentBlips, GoldAgentBlip)
        end
    end
end)

-----------------------------------------------------------------
-- gold agent main menu
-----------------------------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:goldagentmainmenu', function()
    OpenContext({
        id = 'agent_main_menu',
        title = locale('agent_gold_agent_menu'),
        position = 'top-right',
        options = {
            {
                title = locale('agent_smelt_gold'),
                description = locale('agent_smelt_gold_desc'),
                icon = 'fa-solid fa-fire',
                event = 'rsg-goldclaim:rocker:client:smeltnuggets',
            },
            {
                title = locale('agent_sell_gold_bars'),
                description = locale('agent_per_gold_bar', Config.GoldBarPrice),
                icon = 'fa-solid fa-fire',
                event = 'rsg-goldclaim:rocker:client:sellgoldbars',
            },
            {
                title = locale('agent_sell_silver_bars'),
                description = locale('agent_per_silver_bar', Config.SilverBarPrice),
                icon = 'fa-solid fa-fire',
                event = 'rsg-goldclaim:rocker:client:sellsilverbars',
            },
        },
    })
    ShowContext('agent_main_menu')
end)

---------------------------------------------
-- smelt gold bars (custom modal)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:smeltnuggets', function()
    OpenInputDialog(locale('agent_smelt_gold'), {
        {
            label = locale('agent_choose_nugget'),
            type = 'select',
            options = {
                { value = 'smallnugget',  label = locale('agent_small_nuggets', Config.SmallNuggetSmelt) },
                { value = 'mediumnugget', label = locale('agent_medium_nuggets', Config.MediumNuggetSmelt) },
                { value = 'largenugget',  label = locale('agent_large_nuggets', Config.LargeNuggetSmelt) },
            },
            icon = 'fa-solid fa-land-mine-on',
            required = true,
        },
        {
            label = locale('agent_amount'),
            description = locale('agent_amount_desc'),
            type = 'input',
            icon = 'fa-solid fa-hashtag',
            required = true,
        },
    }, function(input)
        if not input then return end

        local nuggetType = input[1]
        local bars = tonumber(input[2])
        if not bars or bars <= 0 then return end

        local nuggetCosts = {
            smallnugget  = Config.SmallNuggetSmelt,
            mediumnugget = Config.MediumNuggetSmelt,
            largenugget  = Config.LargeNuggetSmelt,
        }

        local errorMsgs = {
            smallnugget  = locale('agent_not_enough_small'),
            mediumnugget = locale('agent_not_enough_medium'),
            largenugget  = locale('agent_not_enough_large'),
        }

        local amount = nuggetCosts[nuggetType] * bars
        local hasItem = RSGCore.Functions.HasItem(nuggetType, amount)

        if hasItem then
            LocalPlayer.state:set("inv_busy", true, true)
            lib.progressBar({
                duration = Config.SmeltTime * bars,
                position = 'bottom',
                useWhileDead = false,
                canCancel = false,
                disableControl = true,
                disable = { move = true, mouse = true },
                label = locale('agent_smelting', bars),
            })
            -- the server recomputes the required nugget amount from nuggetType/bars itself
            TriggerServerEvent('rsg-goldclaim:rocker:server:finishsmelt', nuggetType, bars)
            LocalPlayer.state:set("inv_busy", false, true)
        else
            Notify(locale('agent_not_enough_nuggets'), errorMsgs[nuggetType], 'cross', 7000, 'ERROR')
        end
    end)
end)

---------------------------------------------
-- sell all gold bars
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:sellgoldbars', function()
    -- this is a UX-only precheck; the server recomputes the real amount from inventory itself
    local playerInventory = RSGCore.Functions.GetPlayerData().items
    local goldBarCount = 0

    for _, item in pairs(playerInventory) do
        if item.name == 'goldbar' then
            goldBarCount = goldBarCount + item.amount
        end
    end

    if goldBarCount > 0 then
        TriggerServerEvent('rsg-goldclaim:rocker:server:sellgoldbars')
    else
        Notify(locale('agent_not_enough_gold_bars'), locale('agent_no_gold_bars_desc'), 'cross', 7000, 'ERROR')
    end
end)

---------------------------------------------
-- sell all silver bars
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:rocker:client:sellsilverbars', function()
    -- this is a UX-only precheck; the server recomputes the real amount from inventory itself
    local playerInventory = RSGCore.Functions.GetPlayerData().items
    local silverBarCount = 0

    for _, item in pairs(playerInventory) do
        if item.name == 'silverbar' then
            silverBarCount = silverBarCount + item.amount
        end
    end

    if silverBarCount > 0 then
        TriggerServerEvent('rsg-goldclaim:rocker:server:sellsilverbars')
    else
        Notify(locale('agent_not_enough_silver_bars'), locale('agent_no_silver_bars_desc'), 'cross', 7000, 'ERROR')
    end
end)
