local spawnedPeds = {}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        for k, v in pairs(Config.GoldAgentLocations) do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - v.npccoords.xyz)

            if distance < Config.DistanceSpawn and not spawnedPeds[k] then
                local spawnedPed = NearPed(v.npcmodel, v.npccoords)
                spawnedPeds[k] = { spawnedPed = spawnedPed }
            end

            if distance >= Config.DistanceSpawn and spawnedPeds[k] then
                if Config.FadeIn then
                    for i = 255, 0, -51 do
                        Citizen.Wait(50)
                        SetEntityAlpha(spawnedPeds[k].spawnedPed, i, false)
                    end
                end
                DeletePed(spawnedPeds[k].spawnedPed)
                spawnedPeds[k] = nil
            end
        end
    end
end)

function NearPed(npcmodel, npccoords)
    RequestModel(npcmodel)
    while not HasModelLoaded(npcmodel) do
        Citizen.Wait(50)
    end
    local spawnedPed = CreatePed(npcmodel, npccoords.x, npccoords.y, npccoords.z - 1.0, npccoords.w, false, false, 0, 0)
    SetEntityAlpha(spawnedPed, 0, false)
    Citizen.InvokeNative(0x283978A15512B2FE, spawnedPed, true)
    SetEntityCanBeDamaged(spawnedPed, false)
    SetEntityInvincible(spawnedPed, true)
    FreezeEntityPosition(spawnedPed, true)
    SetBlockingOfNonTemporaryEvents(spawnedPed, true)

    -- relationship group
    Citizen.InvokeNative(0xC80A74AC829DDD92, spawnedPed, GetPedRelationshipGroupHash(spawnedPed))
    Citizen.InvokeNative(0xBF25EB89375A37AD, 1, GetPedRelationshipGroupHash(spawnedPed), `PLAYER`)

    if Config.FadeIn then
        for i = 0, 255, 51 do
            Citizen.Wait(50)
            SetEntityAlpha(spawnedPed, i, false)
        end
    end

    -- ox_target on NPC
    if Config.EnableTarget then
        exports.ox_target:addLocalEntity(spawnedPed, {
            {
                name = 'goldagent_npc',
                label = locale('agent_gold_agent_menu'),
                icon = 'fa-solid fa-eye',
                distance = 3.0,
                onSelect = function()
                    TriggerEvent('rsg-goldclaim:rocker:client:goldagentmainmenu')
                end,
            },
        })
    end

    return spawnedPed
end

-- cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for k, v in pairs(spawnedPeds) do
        DeletePed(spawnedPeds[k].spawnedPed)
        spawnedPeds[k] = nil
    end
end)
