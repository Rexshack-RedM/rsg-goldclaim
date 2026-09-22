local RSGCore = exports['rsg-core']:GetCoreObject()
local PropsLoaded = false
local PendingSmelterReturn = {} -- [citizenid] = true while a 'smelter' item has been consumed but not yet placed

---------------------------------------------
-- internal: persist a smelter prop to the database
-- (plain function, NOT a net event - never trust this with client-supplied data)
---------------------------------------------
function SmelterSaveProp(data, propId, citizenid, proptype)
    local datas = json.encode(data)
    MySQL.Async.execute('INSERT INTO player_smelter (properties, propid, citizenid, proptype) VALUES (@properties, @propid, @citizenid, @proptype)', {
        ['@properties'] = datas,
        ['@propid'] = propId,
        ['@citizenid'] = citizenid,
        ['@proptype'] = proptype
    })
end

---------------------------------------------
-- internal: broadcast current smelter prop data to all clients
---------------------------------------------
function SmelterUpdateProps()
    TriggerClientEvent('rsg-goldclaim:smelter:client:updatePropData', -1, Config.Smelter.PlayerProps)
end

---------------------------------------------
-- internal: load smelter props from the database into memory (idempotent)
---------------------------------------------
function SmelterLoadProps()
    Config.Smelter.PlayerProps = {}

    local result = MySQL.query.await('SELECT * FROM player_smelter')
    if not result or not result[1] then return end

    for i = 1, #result do
        local propData = json.decode(result[i].properties)
        if propData and propData.id then
            print(locale('smelter_server_loading') .. propData.proptype .. locale('smelter_server_with_id') .. propData.id)
            table.insert(Config.Smelter.PlayerProps, propData)
        else
            print("^1[rsg-goldclaim] Error: Missing ID for smelter propData^0", json.encode(propData))
        end
    end
end

---------------------------------------------
-- use smelter item
---------------------------------------------
RSGCore.Functions.CreateUseableItem("smelter", function(source)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    PendingSmelterReturn[Player.PlayerData.citizenid] = true
    TriggerClientEvent('rsg-goldclaim:smelter:client:createprop', src, 'playersmelter', Config.Smelter.SmelterProp)
    Player.Functions.RemoveItem('smelter', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['smelter'], "remove")
end)

---------------------------------------------
-- return smelter item on placement cancel
-- only honored once per consumed 'smelter' item (see PendingSmelterReturn)
---------------------------------------------
RegisterNetEvent('rsg-goldclaim:smelter:server:returnItem')
AddEventHandler('rsg-goldclaim:smelter:server:returnItem', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    if not PendingSmelterReturn[citizenid] then return end
    PendingSmelterReturn[citizenid] = nil

    Player.Functions.AddItem('smelter', 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['smelter'], "add")
end)

---------------------------------------------
-- check ingredients callback
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:smelter:server:checkingredients', function(source, cb, ingredients)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local icheck = 0
    for k, v in pairs(ingredients) do
        if Player.Functions.GetItemByName(v.item) and Player.Functions.GetItemByName(v.item).amount >= v.amount then
            icheck = icheck + 1
            if icheck == #ingredients then
                cb(true)
            end
        else
            cb(false)
            return
        end
    end
end)

---------------------------------------------
-- finish smelting
-- the client only ever sends a recipeKey + quantity; the server looks up the
-- authoritative ingredients/output from Config.Smelter.Recipes itself and
-- re-validates the player actually has every ingredient before removing anything
---------------------------------------------
RegisterServerEvent('rsg-goldclaim:smelter:server:finishcrafting')
AddEventHandler('rsg-goldclaim:smelter:server:finishcrafting', function(recipeKey, quantity)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local recipe = Config.Smelter.Recipes[recipeKey]
    if not recipe then return end

    quantity = tonumber(quantity)
    if not quantity or quantity < 1 or quantity ~= math.floor(quantity) then return end

    -- build the authoritative ingredient list from the server's own recipe config
    local requiredIngredients = {}
    for _, ingredient in ipairs(recipe.ingredients) do
        requiredIngredients[#requiredIngredients + 1] = {
            item = ingredient.item,
            amount = (ingredient.amount or 1) * quantity
        }
    end

    -- verify the player actually has every required ingredient before touching anything
    for _, ingredient in ipairs(requiredIngredients) do
        local hasItem = Player.Functions.GetItemByName(ingredient.item)
        if not hasItem or hasItem.amount < ingredient.amount then
            return
        end
    end

    -- remove ingredients only after all of them have been verified
    for _, ingredient in ipairs(requiredIngredients) do
        Player.Functions.RemoveItem(ingredient.item, ingredient.amount)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[ingredient.item], "remove")
    end

    -- add the smelted output (item + amount both come from the server's own recipe config)
    Player.Functions.AddItem(recipe.receive, quantity)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[recipe.receive], "add")

    local itemLabel = RSGCore.Shared.Items[recipe.receive] and RSGCore.Shared.Items[recipe.receive].label or recipe.receive
    Notify(src, locale('smelter_complete_title'), locale('smelter_complete_desc', quantity, itemLabel), 'leaderboard_gold', 5000, 'SUCCESS')
end)

---------------------------------------------
-- check ownership callback
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:smelter:server:checkOwnership', function(source, cb, smelterid)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    local cid = Player.PlayerData.citizenid
    MySQL.Async.fetchScalar('SELECT citizenid FROM player_smelter WHERE propid = ?', {smelterid}, function(ownerCid)
        cb(ownerCid == cid)
    end)
end)

---------------------------------------------
-- count props callback
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:smelter:server:countprop', function(source, cb, proptype)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return cb(0) end
    local citizenid = Player.PlayerData.citizenid
    local result = MySQL.prepare.await("SELECT COUNT(*) as count FROM player_smelter WHERE citizenid = ? AND proptype = ?", { citizenid, proptype })
    if result then
        cb(result)
    else
        cb(0)
    end
end)

---------------------------------------------
-- gold claim check callback
-- Only used when Config.Smelter.RequireGoldClaim = true
-- Checks if placement coords are within a licensed gold claim
-- (the rocker/claim subsystem lives in this same resource)
---------------------------------------------
RSGCore.Functions.CreateCallback('rsg-goldclaim:smelter:server:checkGoldClaim', function(source, cb, px, py, pz)
    local Player = RSGCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    local citizenid = Player.PlayerData.citizenid
    local radius = Config.Smelter.GoldClaimRadius

    -- query all licensed claims for this player
    local result = MySQL.query.await('SELECT properties FROM player_goldrockers WHERE citizenid = ? AND licensed = 1', {citizenid})
    if not result or #result == 0 then
        cb(false)
        return
    end

    for _, row in ipairs(result) do
        local propData = json.decode(row.properties)
        if propData and propData.x and propData.y and propData.z then
            local dist = math.sqrt((px - propData.x)^2 + (py - propData.y)^2 + (pz - propData.z)^2)
            if dist <= radius then
                cb(true)
                return
            end
        end
    end

    cb(false)
end)

---------------------------------------------
-- new prop
-- re-validates MaxSmelters + RequireGoldClaim server-side (never trust the
-- client-gated flow alone) and only proceeds if this player actually has a
-- pending smelter placement (i.e. they consumed a real 'smelter' item)
---------------------------------------------
RegisterServerEvent('rsg-goldclaim:smelter:server:newProp')
AddEventHandler('rsg-goldclaim:smelter:server:newProp', function(proptype, location, heading, hash)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    if not PendingSmelterReturn[citizenid] then return end
    if proptype ~= 'playersmelter' then return end
    if not location or type(location.x) ~= 'number' or type(location.y) ~= 'number' or type(location.z) ~= 'number' then return end
    heading = tonumber(heading) or 0.0

    -- re-validate max smelters server-side
    local existingCount = MySQL.prepare.await("SELECT COUNT(*) as count FROM player_smelter WHERE citizenid = ? AND proptype = ?", { citizenid, proptype }) or 0
    if existingCount >= Config.Smelter.MaxSmelters then
        Notify(src, locale('smelter_max_smelters'), nil, 'cross', 7000, 'ERROR')
        return
    end

    -- re-validate gold claim requirement server-side
    if Config.Smelter.RequireGoldClaim then
        local inClaim = false
        local claims = MySQL.query.await('SELECT properties FROM player_goldrockers WHERE citizenid = ? AND licensed = 1', { citizenid })
        if claims then
            for _, row in ipairs(claims) do
                local propData = json.decode(row.properties)
                if propData and propData.x and propData.y and propData.z then
                    local dist = math.sqrt((location.x - propData.x)^2 + (location.y - propData.y)^2 + (location.z - propData.z)^2)
                    if dist <= Config.Smelter.GoldClaimRadius then
                        inClaim = true
                        break
                    end
                end
            end
        end
        if not inClaim then
            Notify(src, locale('smelter_need_gold_claim'), nil, 'cross', 7000, 'ERROR')
            return
        end
    end

    -- this placement consumes the pending "owed a return" state permanently
    PendingSmelterReturn[citizenid] = nil

    local propId = math.random(111111, 999999)
    -- always use the configured smelter model, never trust a client-supplied hash
    local modelHash = GetHashKey(Config.Smelter.SmelterProp)

    local PropData = {
        id = propId,
        proptype = proptype,
        x = location.x,
        y = location.y,
        z = location.z,
        h = heading,
        hash = modelHash,
        builder = citizenid,
        buildtime = os.time()
    }

    table.insert(Config.Smelter.PlayerProps, PropData)
    SmelterSaveProp(PropData, propId, citizenid, proptype)
    SmelterUpdateProps()
end)

---------------------------------------------
-- pick up prop (returns smelter item to owner)
---------------------------------------------
RegisterServerEvent('rsg-goldclaim:smelter:server:pickupProp')
AddEventHandler('rsg-goldclaim:smelter:server:pickupProp', function(smelterid)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    -- verify ownership
    MySQL.Async.fetchScalar('SELECT citizenid FROM player_smelter WHERE propid = ?', {smelterid}, function(ownerCid)
        if not ownerCid then return end
        if ownerCid ~= cid then return end

        -- remove from memory
        for k, v in pairs(Config.Smelter.PlayerProps) do
            if v.id == smelterid then
                table.remove(Config.Smelter.PlayerProps, k)
                break
            end
        end

        TriggerClientEvent('rsg-goldclaim:smelter:client:removePropObject', -1, smelterid)

        -- remove from DB
        MySQL.Async.execute('DELETE FROM player_smelter WHERE propid = ?', {smelterid})

        SmelterUpdateProps()

        -- return smelter item to player
        Player.Functions.AddItem('smelter', 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items['smelter'], "add")

        Notify(src, locale('smelter_picked_up_title'), locale('smelter_picked_up_desc'), 'tick', 5000, 'SUCCESS')
    end)
end)

---------------------------------------------
-- periodic prop update
---------------------------------------------
CreateThread(function()
    while true do
        Wait(300000)
        if PropsLoaded then
            SmelterUpdateProps()
        end
    end
end)

---------------------------------------------
-- load props on start
---------------------------------------------
CreateThread(function()
    SmelterLoadProps()
    Wait(2000)
    PropsLoaded = true
    SmelterUpdateProps()
end)

---------------------------------------------
-- send props on player load
---------------------------------------------
AddEventHandler('RSGCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    if PropsLoaded then
        TriggerClientEvent('rsg-goldclaim:smelter:client:updatePropData', src, Config.Smelter.PlayerProps)
    end
end)

---------------------------------------------
-- resource start handler
---------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        local activePlayers = GetPlayers()
        for _, playerId in ipairs(activePlayers) do
            TriggerClientEvent('rsg-goldclaim:smelter:client:updatePropData', tonumber(playerId), Config.Smelter.PlayerProps)
        end
    end
end)
